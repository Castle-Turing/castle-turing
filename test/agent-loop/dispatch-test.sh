#!/usr/bin/env bash
# test/agent-loop/dispatch-test.sh — the automatic-dispatch harness
# (docs/tasks/0021-auto-dispatch.md §7).
#
# Same shape as its siblings in this directory: plain bash and stdlib
# python3, no Nix, zero models, zero network. It drives `castle
# dispatch` — the sweep a systemd path unit and timer trigger on a real
# host (modules/agent) — directly, by hand, which is the whole reason
# dispatch is a subcommand rather than a shell script embedded in a
# unit file.
#
# It is also the first harness anywhere that exercises the REAL
# castle.agent.worker.command contract: request body on stdin,
# reasoning on stdout, a diff or nothing to $CASTLE_DIFF_FILE,
# $CASTLE_REQUEST_ID/$CASTLE_REPO_ROOT in the environment. run.sh and
# test/desktop-loop/test.nix both call scripted-worker.sh with two
# positional arguments, bypassing `cmd_work` entirely — see
# contract-worker.sh's header for why those stay exactly as they are.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CASTLE="$REPO_ROOT/agent/castle"
CHECK="$REPO_ROOT/test/agent-loop/check_assertions.py"
WORKER_OK="$REPO_ROOT/test/agent-loop/contract-worker.sh"
WORKER_FAIL="$REPO_ROOT/test/agent-loop/contract-worker-fail.sh"
WORKER_HANG="$REPO_ROOT/test/agent-loop/contract-worker-hang.sh"
WORKER_DIE="$REPO_ROOT/test/agent-loop/contract-worker-die.sh"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/castle-dispatch-test.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

export CASTLE_STATE_DIR="$WORKDIR/state"
export XDG_RUNTIME_DIR="$WORKDIR/runtime"
mkdir -p "$CASTLE_STATE_DIR" "$XDG_RUNTIME_DIR"
JOURNAL="$CASTLE_STATE_DIR/journal"
LEASES="$XDG_RUNTIME_DIR/castle/leases"

# The same notify stub run.sh uses, for the same reason: the sweep's
# tail step is a real `castle route`, and a CI runner has no
# notification daemon for it to shell out to.
export CASTLE_NOTIFY_LOG="$WORKDIR/notify.log"
export CASTLE_NOTIFY_COMMAND="$REPO_ROOT/test/agent-loop/notify-stub.sh"
: > "$CASTLE_NOTIFY_LOG"

# A real (empty) directory rather than whatever this script's cwd
# happens to be: $CASTLE_REPO_ROOT is part of the worker contract, and
# contract-worker.sh asserts it is set.
export CASTLE_REPO_ROOT="$WORKDIR/repo"
mkdir -p "$CASTLE_REPO_ROOT"
export CASTLE_WORKER_COMMAND="$WORKER_OK"

log() { printf '>>> %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# All three helpers below tolerate "no such file" (an empty journal, or
# no record of that type yet) rather than letting a non-matching glob
# or grep kill the script under `set -e` before the assertion that was
# supposed to produce a readable diagnostic ever runs — the same
# `|| true` reasoning run.sh documents at length (0009 review finding 7).
records_of_type() { find "$JOURNAL" -name "*-$1-*.md" 2>/dev/null || true; }
count_of_type() { records_of_type "$1" | grep -c . || true; }
# `refs` is a flat comma-separated list, so a substring match is the
# honest test for "this record references that id" — ids carry a random
# 6-hex-char suffix, so a false positive is not a practical concern.
referencing() {
  local rtype="$1" id="$2"
  grep -l "^refs: .*$id" "$JOURNAL"/*-"$rtype"-*.md 2>/dev/null || true
}
count_referencing() { referencing "$1" "$2" | grep -c . || true; }

all_records() { find "$JOURNAL" -name '*.md' | grep -c . || true; }

# ---------------------------------------------------------------------
log "watermark: the first sweep writes exactly one, and a request filed before it is never auto-started"
# ---------------------------------------------------------------------
REQ_OLD="$("$CASTLE" ask "Dispatch test: filed before dispatch ever existed on this journal.")"
log "  -> $REQ_OLD"
# One second, deliberately: `created` has whole-second granularity and
# eligibility is `created >= watermark`, so a request filed in the same
# second as the first sweep is (by design) picked up rather than
# stranded. This test is about the boundary a second earlier.
sleep 1

SWEEP1_OUT="$("$CASTLE" dispatch)"
echo "$SWEEP1_OUT"
WATERMARK_FILES="$(grep -l '^watermark: ' "$JOURNAL"/*-decision-*.md 2>/dev/null || true)"
WATERMARK_COUNT="$(echo "$WATERMARK_FILES" | grep -c . || true)"
[ "$WATERMARK_COUNT" -eq 1 ] || fail "expected exactly 1 watermark decision record after the first sweep, got $WATERMARK_COUNT"
grep -q '^seat: dispatch$' "$WATERMARK_FILES" || fail "the watermark record does not carry seat: dispatch"
grep -q '^type: decision$' "$WATERMARK_FILES" || fail "the watermark record is not a decision record"
grep -q '^provenance: initiated$' "$WATERMARK_FILES" || fail "the watermark record should carry provenance: initiated"
grep -q '^refs: *$' "$WATERMARK_FILES" || fail "the watermark record should reference nothing"
grep -q '^evidence: .' "$WATERMARK_FILES" || fail "the watermark record has no non-empty evidence (Proposal 04)"
grep -q "castle work" "$WATERMARK_FILES" || fail "the watermark record's body should tell the resident how to run pre-watermark requests by hand"
"$CASTLE" validate

[ "$(count_referencing result "$REQ_OLD")" -eq 0 ] || fail "a request filed before the watermark was auto-dispatched anyway"
[ "$(count_referencing claim "$REQ_OLD")" -eq 0 ] || fail "a request filed before the watermark was claimed by a worker anyway"

log "watermark: a second sweep does not write a second one"
"$CASTLE" dispatch >/dev/null
WATERMARK_COUNT_2="$(grep -l '^watermark: ' "$JOURNAL"/*-decision-*.md 2>/dev/null | grep -c . || true)"
[ "$WATERMARK_COUNT_2" -eq 1 ] || fail "a second sweep wrote another watermark record (got $WATERMARK_COUNT_2)"
[ "$(count_referencing result "$REQ_OLD")" -eq 0 ] || fail "the pre-watermark request was dispatched on a later sweep"

# ---------------------------------------------------------------------
log "an eligible request gets exactly one turn, and the same sweep routes its result"
# ---------------------------------------------------------------------
REQ1="$("$CASTLE" ask "Dispatch test: filed after the watermark, should start itself.")"
log "  -> $REQ1"
NOTIFY_BEFORE="$(wc -l < "$CASTLE_NOTIFY_LOG" | tr -d ' ')"
SWEEP_OUT="$("$CASTLE" dispatch)"
echo "$SWEEP_OUT"

[ "$(count_referencing claim "$REQ1")" -eq 1 ] || fail "expected exactly 1 claim record for $REQ1, got $(count_referencing claim "$REQ1")"
[ "$(count_referencing result "$REQ1")" -eq 1 ] || fail "expected exactly 1 result record for $REQ1, got $(count_referencing result "$REQ1")"
RESULT1="$(basename "$(referencing result "$REQ1")" .md)"
RESULT1_FILE="$JOURNAL/$RESULT1.md"
grep -q '^outcome: completed$' "$RESULT1_FILE" || fail "$RESULT1_FILE does not carry outcome: completed"
grep -q '^seat: worker$' "$RESULT1_FILE" || fail "$RESULT1_FILE should carry seat: worker — dispatch invokes the worker seat, it does not become one"
grep -q '^provenance: requested$' "$RESULT1_FILE" || fail "$RESULT1_FILE lost the request's provenance — automatic starting must not change who wanted the work"
grep -q "contract-worker: handled $REQ1" "$RESULT1_FILE" || fail "$RESULT1_FILE does not carry the tenant's stdout reasoning"
grep -q 'placeholder after' "$RESULT1_FILE" || fail "$RESULT1_FILE does not carry the diff the tenant wrote to \$CASTLE_DIFF_FILE"

CLAIM1_FILE="$(referencing claim "$REQ1")"
grep -q '^type: claim$' "$CLAIM1_FILE" || fail "$CLAIM1_FILE is not a claim record"
grep -q "$WORKER_OK" "$CLAIM1_FILE" || fail "$CLAIM1_FILE does not name the tenant command it started"

DECISION_FOR_RESULT1="$(referencing decision "$RESULT1")"
[ -n "$DECISION_FOR_RESULT1" ] || fail "the auto-produced result was not routed by the same sweep"
grep -q '^channel: notify$' "$DECISION_FOR_RESULT1" || fail "the requested-provenance result did not route to notify: $DECISION_FOR_RESULT1"
NOTIFY_AFTER="$(wc -l < "$CASTLE_NOTIFY_LOG" | tr -d ' ')"
[ "$NOTIFY_AFTER" -gt "$NOTIFY_BEFORE" ] || fail "routing the auto-produced result fired no notification"
"$CASTLE" validate

# ---------------------------------------------------------------------
log "no self-retrigger: a second sweep over an already-worked journal changes nothing (record counts, not just exit 0)"
# ---------------------------------------------------------------------
# The sweep writes records into the very directory the path unit
# watches, so finishing one re-triggers the unit on a real host. The
# second cycle must find the eligible set empty and write nothing —
# that is what makes the loop terminate rather than run forever.
COUNT_BEFORE="$(all_records)"
"$CASTLE" dispatch >/dev/null
COUNT_AFTER="$(all_records)"
[ "$COUNT_AFTER" -eq "$COUNT_BEFORE" ] || fail "a sweep over an already-worked journal wrote records ($COUNT_BEFORE -> $COUNT_AFTER) — dispatch would retrigger itself forever"

# ---------------------------------------------------------------------
log "concurrency: two simultaneous sweeps against the same request produce exactly one claim and one result"
# ---------------------------------------------------------------------
REQ_CONC="$("$CASTLE" ask "Dispatch test: two sweeps race for this one.")"
CASTLE_TEST_WORKER_SLEEP=2 "$CASTLE" dispatch >"$WORKDIR/conc-a.out" 2>&1 &
CONC_A=$!
CASTLE_TEST_WORKER_SLEEP=2 "$CASTLE" dispatch >"$WORKDIR/conc-b.out" 2>&1 &
CONC_B=$!
wait "$CONC_A" || fail "the first concurrent sweep exited nonzero: $(cat "$WORKDIR/conc-a.out")"
wait "$CONC_B" || fail "the second concurrent sweep exited nonzero: $(cat "$WORKDIR/conc-b.out")"
cat "$WORKDIR/conc-a.out" "$WORKDIR/conc-b.out"
# Only the invariants are asserted, never an interleaving: which sweep
# wins the lock, and whether the loser skipped or simply found nothing
# eligible, are both legitimate outcomes of the same race.
[ "$(count_referencing claim "$REQ_CONC")" -eq 1 ] || fail "expected exactly 1 claim for $REQ_CONC across two concurrent sweeps, got $(count_referencing claim "$REQ_CONC")"
[ "$(count_referencing result "$REQ_CONC")" -eq 1 ] || fail "expected exactly 1 result for $REQ_CONC across two concurrent sweeps, got $(count_referencing result "$REQ_CONC")"
"$CASTLE" validate

# ---------------------------------------------------------------------
log "a hand-run castle work is refused while another turn holds the errand's lease, and writes nothing"
# ---------------------------------------------------------------------
REQ_LEASE="$("$CASTLE" ask "Dispatch test: the lease refusal path.")"
CASTLE_TEST_WORKER_SLEEP=3 "$CASTLE" work "$REQ_LEASE" >"$WORKDIR/lease-holder.out" 2>&1 &
LEASE_HOLDER=$!
for _ in $(seq 1 50); do
  [ "$(count_referencing claim "$REQ_LEASE")" -eq 1 ] && break
  sleep 0.2
done
[ "$(count_referencing claim "$REQ_LEASE")" -eq 1 ] || fail "the background castle work never wrote its claim record"
RECORDS_BEFORE_REFUSAL="$(all_records)"
if "$CASTLE" work "$REQ_LEASE" >"$WORKDIR/lease-refused.out" 2>"$WORKDIR/lease-refused.err"; then
  fail "a second castle work on an errand whose lease is held was accepted"
fi
grep -q "already holds this errand's lease" "$WORKDIR/lease-refused.err" || fail "castle work's lease-refusal message changed unexpectedly: $(cat "$WORKDIR/lease-refused.err")"
[ "$(all_records)" -eq "$RECORDS_BEFORE_REFUSAL" ] || fail "the refused castle work wrote a record anyway — nothing began, so nothing should look like it did"
wait "$LEASE_HOLDER" || fail "the background castle work exited nonzero: $(cat "$WORKDIR/lease-holder.out")"
[ "$(count_referencing result "$REQ_LEASE")" -eq 1 ] || fail "the background castle work wrote no result"
"$CASTLE" validate

# ---------------------------------------------------------------------
log "a failing tenant yields outcome: failed, and is never re-dispatched"
# ---------------------------------------------------------------------
REQ_FAIL="$("$CASTLE" ask "Dispatch test: the tenant fails on purpose.")"
CASTLE_WORKER_COMMAND="$WORKER_FAIL" "$CASTLE" dispatch >"$WORKDIR/fail-sweep.out" 2>&1 || fail "a sweep whose tenant failed exited nonzero — an errand failing is not a mechanism fault: $(cat "$WORKDIR/fail-sweep.out")"
cat "$WORKDIR/fail-sweep.out"
[ "$(count_referencing result "$REQ_FAIL")" -eq 1 ] || fail "the failing tenant produced no result record"
RESULT_FAIL_FILE="$(referencing result "$REQ_FAIL")"
grep -q '^outcome: failed$' "$RESULT_FAIL_FILE" || fail "$RESULT_FAIL_FILE does not carry outcome: failed"
grep -q 'fails on purpose' "$RESULT_FAIL_FILE" || fail "$RESULT_FAIL_FILE does not carry the tenant's stderr"
"$CASTLE" dispatch >/dev/null
[ "$(count_referencing result "$REQ_FAIL")" -eq 1 ] || fail "a failed errand was re-dispatched automatically — retry is one attempt, always, by construction"
[ "$(count_referencing claim "$REQ_FAIL")" -eq 1 ] || fail "a failed errand was claimed a second time"

# ---------------------------------------------------------------------
log "a tenant killed by a signal yields outcome: failed, NOT interrupted — the invoker survived to write the account"
# ---------------------------------------------------------------------
REQ_DIE="$("$CASTLE" ask "Dispatch test: the tenant dies by signal.")"
CASTLE_WORKER_COMMAND="$WORKER_DIE" "$CASTLE" dispatch >/dev/null 2>&1 || true
RESULT_DIE_FILE="$(referencing result "$REQ_DIE")"
[ -n "$RESULT_DIE_FILE" ] || fail "a signal-killed tenant produced no result record"
grep -q '^outcome: failed$' "$RESULT_DIE_FILE" || fail "$RESULT_DIE_FILE should carry outcome: failed (the invoker watched the death); got: $(grep '^outcome:' "$RESULT_DIE_FILE" || echo none)"
grep -q 'killed by signal 9' "$RESULT_DIE_FILE" || fail "$RESULT_DIE_FILE does not say the tenant was killed by a signal"

# ---------------------------------------------------------------------
log "a hanging tenant under CASTLE_WORKER_TIMEOUT=2 yields outcome: timeout within seconds, not its full sleep"
# ---------------------------------------------------------------------
REQ_HANG="$("$CASTLE" ask "Dispatch test: the tenant hangs.")"
HANG_START="$(date +%s)"
CASTLE_WORKER_COMMAND="$WORKER_HANG" CASTLE_WORKER_TIMEOUT=2 "$CASTLE" dispatch >/dev/null 2>&1 || true
HANG_ELAPSED=$(( $(date +%s) - HANG_START ))
RESULT_HANG_FILE="$(referencing result "$REQ_HANG")"
[ -n "$RESULT_HANG_FILE" ] || fail "a hanging tenant produced no result record"
grep -q '^outcome: timeout$' "$RESULT_HANG_FILE" || fail "$RESULT_HANG_FILE does not carry outcome: timeout"
# The fixture sleeps 300s. A generous ceiling: this asserts the timeout
# fired at all, not a precise duration a loaded CI runner could miss.
[ "$HANG_ELAPSED" -lt 60 ] || fail "the hanging tenant was not killed on time (sweep took ${HANG_ELAPSED}s with CASTLE_WORKER_TIMEOUT=2)"
log "  -> timed out after ${HANG_ELAPSED}s"
"$CASTLE" validate

# ---------------------------------------------------------------------
log "an interrupted turn is reaped: a planted claim with no live lease yields outcome: interrupted, and it gets routed"
# ---------------------------------------------------------------------
# A planted claim, not a real crash: `castle record --type claim` is
# deliberately permitted through the generic writer (a claim is a
# mechanical observation, not resident speech), which is exactly what
# lets this harness simulate a process that died mid-turn without
# having to kill one at the right microsecond.
REQ_INT="$("$CASTLE" ask "Dispatch test: a turn that began and never finished.")"
CLAIM_INT="$("$CASTLE" record --type claim --provenance requested --seat worker --refs "$REQ_INT" \
  --body "Planted claim: stands in for a worker turn whose process died before writing anything.")"
[ ! -e "$LEASES/$REQ_INT.lock" ] || fail "the planted claim's lease file already exists; this fixture assumes the reboot case (no lease at all)"
"$CASTLE" dispatch >/dev/null
RESULT_INT_FILE="$(referencing result "$REQ_INT")"
[ -n "$RESULT_INT_FILE" ] || fail "the reaper wrote no result for an interrupted turn"
grep -q '^outcome: interrupted$' "$RESULT_INT_FILE" || fail "$RESULT_INT_FILE does not carry outcome: interrupted"
grep -q '^seat: dispatch$' "$RESULT_INT_FILE" || fail "$RESULT_INT_FILE should carry seat: dispatch — the reaper wrote it, not a worker"
grep -q "^refs: $REQ_INT,$CLAIM_INT\$" "$RESULT_INT_FILE" || fail "$RESULT_INT_FILE should reference both the request and the claim it reaped"
RESULT_INT="$(basename "$RESULT_INT_FILE" .md)"
[ -n "$(referencing decision "$RESULT_INT")" ] || fail "the reaped result was not routed"
[ "$(count_referencing result "$REQ_INT")" -eq 1 ] || fail "the reaped request was ALSO dispatched — a reaped result must make it ineligible"

log "the reaper also clears a stale lease file left behind by a dead process"
REQ_INT2="$("$CASTLE" ask "Dispatch test: an interrupted turn whose lease file outlived it.")"
CLAIM_INT2="$("$CASTLE" record --type claim --provenance requested --seat worker --refs "$REQ_INT2" \
  --body "Planted claim: the lease file survived, but nothing holds it.")"
mkdir -p "$LEASES"
printf 'request: %s\nstarted: stale\n' "$REQ_INT2" > "$LEASES/$REQ_INT2.lock"
"$CASTLE" dispatch >/dev/null
RESULT_INT2_FILE="$(referencing result "$REQ_INT2")"
[ -n "$RESULT_INT2_FILE" ] || fail "the reaper ignored a claim whose lease file exists but is unheld"
grep -q '^outcome: interrupted$' "$RESULT_INT2_FILE" || fail "$RESULT_INT2_FILE does not carry outcome: interrupted"
grep -q "$CLAIM_INT2" "$RESULT_INT2_FILE" || fail "$RESULT_INT2_FILE does not cite the claim it reaped"
[ ! -e "$LEASES/$REQ_INT2.lock" ] || fail "the reaper left the stale lease file behind"
"$CASTLE" validate

# ---------------------------------------------------------------------
log "NON-behavior (task 0023's territory): answering a question on an already-worked errand does not make it eligible again"
# ---------------------------------------------------------------------
# Asserted explicitly rather than left implicit: errand resumption is
# docs/backlog/errand-resume-after-answer.md's problem, and a
# regression here would silently widen this task's scope into 0023's.
QUESTION="$("$CASTLE" record --type question --provenance requested --seat worker --refs "$REQ1" \
  --body "Dispatch test: a mid-errand question on an already-worked errand.")"
"$CASTLE" dispatch >/dev/null
ANSWER="$("$CASTLE" answer "$QUESTION" "Dispatch test: the resident answers it.")"
log "  -> answered $QUESTION with $ANSWER"
"$CASTLE" dispatch >/dev/null
[ "$(count_referencing result "$REQ1")" -eq 1 ] || fail "an answer re-opened an already-worked errand: $REQ1 now has $(count_referencing result "$REQ1") results"
[ "$(count_referencing claim "$REQ1")" -eq 1 ] || fail "an answer caused a second worker turn on $REQ1"

# ---------------------------------------------------------------------
log "an empty CASTLE_WORKER_COMMAND yields outcome: failed on the very first sweep, not a silent unbounded retry loop"
# ---------------------------------------------------------------------
REQ_NOWORKER="$("$CASTLE" ask "Dispatch test: no worker tenant is configured at all.")"
CASTLE_WORKER_COMMAND="" "$CASTLE" dispatch >/dev/null 2>&1 || true
RESULT_NOWORKER_FILE="$(referencing result "$REQ_NOWORKER")"
[ -n "$RESULT_NOWORKER_FILE" ] || fail "an empty CASTLE_WORKER_COMMAND left no record at all — this is the unbounded silent retry loop task 0021 fixes"
grep -q '^outcome: failed$' "$RESULT_NOWORKER_FILE" || fail "$RESULT_NOWORKER_FILE does not carry outcome: failed"
grep -q 'CASTLE_WORKER_COMMAND is empty' "$RESULT_NOWORKER_FILE" || fail "$RESULT_NOWORKER_FILE does not name what was misconfigured"
CASTLE_WORKER_COMMAND="" "$CASTLE" dispatch >/dev/null 2>&1 || true
CASTLE_WORKER_COMMAND="" "$CASTLE" dispatch >/dev/null 2>&1 || true
[ "$(count_referencing result "$REQ_NOWORKER")" -eq 1 ] || fail "a misconfigured tenant was retried across sweeps: $(count_referencing result "$REQ_NOWORKER") results for $REQ_NOWORKER"

log "an unrunnable CASTLE_WORKER_COMMAND (a binary that does not exist) is recorded the same way"
REQ_NOBIN="$("$CASTLE" ask "Dispatch test: the configured tenant is not a real command.")"
CASTLE_WORKER_COMMAND="$WORKDIR/definitely-not-a-real-binary" "$CASTLE" dispatch >/dev/null 2>&1 || true
RESULT_NOBIN_FILE="$(referencing result "$REQ_NOBIN")"
[ -n "$RESULT_NOBIN_FILE" ] || fail "an unrunnable worker command left no record at all"
grep -q '^outcome: failed$' "$RESULT_NOBIN_FILE" || fail "$RESULT_NOBIN_FILE does not carry outcome: failed"
"$CASTLE" validate

# ---------------------------------------------------------------------
log "corrections are never routed, even when dispatch is what triggers the router"
# ---------------------------------------------------------------------
CORRECTION="$("$CASTLE" correct "Dispatch test: the resident says how the system is doing.")"
NOTIFY_BEFORE_CORRECTION="$(wc -l < "$CASTLE_NOTIFY_LOG" | tr -d ' ')"
DECISIONS_BEFORE_CORRECTION="$(count_of_type decision)"
"$CASTLE" dispatch >/dev/null
[ "$(count_of_type decision)" -eq "$DECISIONS_BEFORE_CORRECTION" ] || fail "a dispatch sweep appended a decision when only a correction was unrouted"
[ -z "$(referencing decision "$CORRECTION")" ] || fail "a decision record references correction $CORRECTION — corrections must never be routed"
[ "$(wc -l < "$CASTLE_NOTIFY_LOG" | tr -d ' ')" -eq "$NOTIFY_BEFORE_CORRECTION" ] || fail "filing a correction and sweeping fired a notification"

# ---------------------------------------------------------------------
log "outcome is validated when present and never required (the same treatment considered/propensity already get)"
# ---------------------------------------------------------------------
OLD_STYLE_RESULT="$("$CASTLE" record --type result --provenance initiated --seat worker --refs "$REQ_OLD" \
  --body "Backward-compatibility fixture: a result with no outcome field, the pre-0021 shape.")"
grep -q '^outcome:' "$JOURNAL/$OLD_STYLE_RESULT.md" && fail "$OLD_STYLE_RESULT unexpectedly has an outcome field — this fixture is supposed to lack one"
"$CASTLE" validate || fail "a result record with no outcome field failed to validate — backward compatibility is broken"

BAD_OUTCOME_FILE="$JOURNAL/20260101T000000Z-result-bad0c1.md"
cat > "$BAD_OUTCOME_FILE" <<EOF
---
id: 20260101T000000Z-result-bad0c1
type: result
provenance: requested
refs: $REQ1
seat: worker
created: 2026-01-01T00:00:00Z
outcome: kind-of-worked
---

Malformed outcome fixture: not a member of the closed vocabulary.
EOF
if "$CASTLE" validate >"$WORKDIR/bad-outcome.out" 2>"$WORKDIR/bad-outcome.err"; then
  fail "castle validate accepted a result record with outcome: kind-of-worked"
fi
grep -q "outcome" "$WORKDIR/bad-outcome.err" || fail "castle validate's outcome rejection message changed unexpectedly"
rm -f "$BAD_OUTCOME_FILE"
"$CASTLE" validate || fail "the journal did not validate clean once the malformed outcome fixture was removed"

# ---------------------------------------------------------------------
log "final sweep, then independent structural assertions over the whole journal"
# ---------------------------------------------------------------------
"$CASTLE" dispatch >/dev/null
"$CASTLE" validate
"$CHECK" "$JOURNAL"

log "all assertions passed"
