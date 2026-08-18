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
# It is also the first harness in this directory to exercise the REAL
# castle.agent.worker.command contract: request body on stdin,
# reasoning on stdout, a diff or nothing to $CASTLE_DIFF_FILE,
# $CASTLE_REQUEST_ID/$CASTLE_REPO_ROOT in the environment. run.sh and
# tenant-swap.sh still call scripted-worker.sh with two positional
# arguments and bypass `cmd_work` entirely — see contract-worker.sh's
# header for why those stay exactly as they are. (test/desktop-loop
# went through `cmd_work` as of this same task: dispatch invokes it
# there, with a contract-conforming tenant pinned in the VM.)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CASTLE="$REPO_ROOT/agent/castle"
CHECK="$REPO_ROOT/test/agent-loop/check_assertions.py"
WORKER_OK="$REPO_ROOT/test/agent-loop/contract-worker.sh"
WORKER_FAIL="$REPO_ROOT/test/agent-loop/contract-worker-fail.sh"
WORKER_HANG="$REPO_ROOT/test/agent-loop/contract-worker-hang.sh"
WORKER_DIE="$REPO_ROOT/test/agent-loop/contract-worker-die.sh"
WORKER_FILER="$REPO_ROOT/test/agent-loop/contract-worker-filer.sh"
WORKER_DETACH="$REPO_ROOT/test/agent-loop/contract-worker-detach.sh"
WORKER_STRAGGLER="$REPO_ROOT/test/agent-loop/contract-worker-straggler.sh"

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

SWEEP1_OUT="$("$CASTLE" dispatch)"
echo "$SWEEP1_OUT"
WATERMARK_FILES="$(grep -l '^watermark: ' "$JOURNAL"/*-decision-*.md 2>/dev/null || true)"
WATERMARK_COUNT="$(echo "$WATERMARK_FILES" | grep -c . || true)"
[ "$WATERMARK_COUNT" -eq 1 ] || fail "expected exactly 1 watermark decision record after the first sweep, got $WATERMARK_COUNT"
grep -q '^seat: dispatch$' "$WATERMARK_FILES" || fail "the watermark record does not carry seat: dispatch"
grep -q '^type: decision$' "$WATERMARK_FILES" || fail "the watermark record is not a decision record"
grep -q '^provenance: initiated$' "$WATERMARK_FILES" || fail "the watermark record should carry provenance: initiated"
# The exclusion is by NAME, not by timestamp: the outstanding request
# has to be listed in this record's own refs, because that list is the
# whole of eligibility rule (d). A timestamp comparison used to do this
# job and could strand the very request whose arrival woke the first
# sweep (whole-second `created` granularity, a wall-clock tick in the
# wrong place); naming the excluded set removes that class of bug
# rather than narrowing its window.
grep -q "^refs: .*$REQ_OLD" "$WATERMARK_FILES" || fail "the watermark record does not name the outstanding request $REQ_OLD in its refs — nothing else excludes it"
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

log "the boundary case a timestamp comparison got wrong: a request filed in the same wall-clock second as an existing watermark still runs"
# Deliberately NO sleep here. Under the old `created >= watermark`
# rule this was the bug that mattered most in practice: on a fresh
# host the first sweep is triggered by the arrival of the resident's
# first request, so the request that woke dispatch was the one request
# dispatch would refuse to run — permanently, and with no explanation
# anywhere. The watermark already exists at this point in the script,
# so this is the same-second case with nothing else going on.
REQ_SAME_SECOND="$("$CASTLE" ask "Dispatch test: filed in the same second as a sweep, must still run.")"
"$CASTLE" dispatch >/dev/null
[ "$(count_referencing result "$REQ_SAME_SECOND")" -eq 1 ] || fail "a request filed in the same wall-clock second as a sweep was not dispatched — the watermark is excluding by timestamp again, not by name"

# ---------------------------------------------------------------------
log "--watermark-only establishes the boundary and sweeps nothing — the session-start unit's whole job"
# ---------------------------------------------------------------------
# On a real host this is what modules/agent's castle-dispatch-watermark
# runs, at the instant the user manager starts. It exists because the
# first *sweep* is too late: its 5s OnStartupSec is measured from that
# same instant, and test/desktop-loop showed a graphical login plus one
# modal keystroke beating it comfortably — the resident's first request
# was outstanding when the sweep wrote the watermark, landed in the
# watermark's own refs, and was excluded from automatic dispatch by
# name, forever. Establishing the boundary before any compositor exists
# moves it from "filed before the first sweep happened to run" to
# "filed before this dispatch-enabled session existed."
#
# Its own state directory, because every assertion here is about a
# journal that has never been swept and the one above has been swept
# three times. `$JOURNAL` and `$CASTLE_STATE_DIR` are restored at the
# end of the section — everything after it works the main journal.
MAIN_STATE_DIR="$CASTLE_STATE_DIR"
MAIN_JOURNAL="$JOURNAL"
export CASTLE_STATE_DIR="$WORKDIR/state-watermark-only"
JOURNAL="$CASTLE_STATE_DIR/journal"
mkdir -p "$CASTLE_STATE_DIR"

REQ_PRE="$("$CASTLE" ask "Dispatch test: outstanding before the session-start watermark ran.")"
log "  -> $REQ_PRE"
WM_ONLY_OUT="$("$CASTLE" dispatch --watermark-only)"
echo "$WM_ONLY_OUT"
case "$WM_ONLY_OUT" in
  *"not sweeping"*) : ;;
  *) fail "--watermark-only did not say it was not sweeping: $WM_ONLY_OUT" ;;
esac
WM_ONLY_FILES="$(grep -l '^watermark: ' "$JOURNAL"/*-decision-*.md 2>/dev/null || true)"
[ "$(echo "$WM_ONLY_FILES" | grep -c . || true)" -eq 1 ] || fail "--watermark-only did not establish exactly one watermark record"
grep -q "^refs: .*$REQ_PRE" "$WM_ONLY_FILES" || fail "the watermark --watermark-only wrote does not name the outstanding request $REQ_PRE in its refs"
# Nothing else happened: no claim, no result, no routing decision. The
# whole point of the flag is that a unit in default.target's activation
# path cannot afford a sweep — a oneshot holding the user manager open
# for worker.timeoutSeconds per eligible errand is exactly what the
# sweep service is kept out of default.target to avoid.
[ "$(count_of_type claim)" -eq 0 ] || fail "--watermark-only claimed a request"
[ "$(count_of_type result)" -eq 0 ] || fail "--watermark-only produced a result"
[ "$(all_records)" -eq 2 ] || fail "expected exactly 2 records (the request and the watermark) after --watermark-only, got $(all_records)"
"$CASTLE" validate

log "--watermark-only is idempotent: a second session-start run writes nothing"
"$CASTLE" dispatch --watermark-only >/dev/null
[ "$(all_records)" -eq 2 ] || fail "a second --watermark-only run changed the journal (now $(all_records) records) — the boundary must be written exactly once, ever"

log "a later full sweep respects the boundary the session-start unit put down"
REQ_POST="$("$CASTLE" ask "Dispatch test: filed after the session-start watermark, must run.")"
"$CASTLE" dispatch >/dev/null
[ "$(count_referencing result "$REQ_PRE")" -eq 0 ] || fail "the request the session-start watermark excluded was auto-dispatched by a later sweep anyway"
[ "$(count_referencing claim "$REQ_PRE")" -eq 0 ] || fail "the request the session-start watermark excluded was claimed by a later sweep anyway"
[ "$(count_referencing result "$REQ_POST")" -eq 1 ] || fail "a request filed after the session-start watermark was not dispatched"
"$CASTLE" validate

export CASTLE_STATE_DIR="$MAIN_STATE_DIR"
JOURNAL="$MAIN_JOURNAL"

# ---------------------------------------------------------------------
log "a state dir that does not exist yet is not a mechanism fault: the sweep says so, creates nothing, and exits 0"
# ---------------------------------------------------------------------
# The restore-order hazard: dispatch enabled and rebuilt before the
# private repo holding the journal has been cloned. A sweep that
# created the directory would break that clone AND write a watermark
# with empty refs, so the history restored ten minutes later would
# arrive with nothing marked as predating dispatch — every request in
# it newly eligible, which is the exact outcome the watermark exists
# to prevent.
MISSING_STATE="$WORKDIR/not-restored-yet"
[ ! -e "$MISSING_STATE" ] || fail "the missing-state-dir fixture path already exists"
if ! GUARD_OUT="$(CASTLE_STATE_DIR="$MISSING_STATE" "$CASTLE" dispatch 2>&1)"; then
  fail "a sweep against a nonexistent state dir exited nonzero — a machine that is not ready yet is not a mechanism fault: $GUARD_OUT"
fi
echo "$GUARD_OUT"
case "$GUARD_OUT" in
  *"does not exist yet"*) ;;
  *) fail "the sweep did not explain that the state dir is missing: $GUARD_OUT" ;;
esac
[ ! -e "$MISSING_STATE" ] || fail "the sweep created $MISSING_STATE — it must wait for the private repo, not conjure a state directory"

# ---------------------------------------------------------------------
log "an unattended sweep refuses to make liveness decisions on world-writable locks"
# ---------------------------------------------------------------------
# With no XDG_RUNTIME_DIR and no /run/user/$UID, the only lock
# directory left is /tmp/castle-$UID, which any local user can create
# first: they hold the sweep lock and dispatch reports "another sweep
# is already running" and exits 0, forever, green in systemctl while
# nothing runs. A hand-run `castle work` keeps that fallback on
# purpose — a human is watching it — but a timer is not.
#
# Branching on the directory because both worlds are real: a developer
# machine has /run/user/$UID, a CI runner may not.
if [ -d "/run/user/$(id -u)" ]; then
  log "  -- /run/user/$(id -u) exists here, so the sweep should fall back to it and run normally"
  env -u XDG_RUNTIME_DIR "$CASTLE" dispatch >"$WORKDIR/no-xdg.out" 2>&1 \
    || fail "a sweep with no XDG_RUNTIME_DIR but a real /run/user/\$UID refused to run: $(cat "$WORKDIR/no-xdg.out")"
else
  log "  -- no /run/user/$(id -u) here, so the only lock directory is world-writable and the sweep must refuse"
  if env -u XDG_RUNTIME_DIR "$CASTLE" dispatch >"$WORKDIR/no-xdg.out" 2>&1; then
    fail "a sweep with only the /tmp lock fallback available exited 0 instead of refusing: $(cat "$WORKDIR/no-xdg.out")"
  fi
  grep -q "world-writable" "$WORKDIR/no-xdg.out" || fail "the refusal did not explain itself: $(cat "$WORKDIR/no-xdg.out")"
fi

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
log "a hand-run castle route racing a sweep's tail routes each record exactly once, and notifies once"
# ---------------------------------------------------------------------
# Routing had one invoker — a human — until this task gave it a second
# one that runs unattended. Two folds in flight at the same instant
# both see a record as unrouted, both append a decision for it, and
# both fire a notification. The route lock serializes them; the loser
# waits and then finds nothing to do, which is why blocking (not
# skipping) is the right shape for a fold this cheap and this
# idempotent.
REQ_RACE="$("$CASTLE" ask "Dispatch test: a hand-run route racing the sweep's tail.")"
NOTIFY_BEFORE_RACE="$(wc -l < "$CASTLE_NOTIFY_LOG" | tr -d ' ')"
"$CASTLE" dispatch >"$WORKDIR/race-dispatch.out" 2>&1 &
RACE_DISPATCH=$!
"$CASTLE" route >"$WORKDIR/race-route.out" 2>&1 &
RACE_ROUTE=$!
wait "$RACE_DISPATCH" || fail "the racing sweep exited nonzero: $(cat "$WORKDIR/race-dispatch.out")"
wait "$RACE_ROUTE" || fail "the racing hand-run route exited nonzero: $(cat "$WORKDIR/race-route.out")"
RESULT_RACE="$(basename "$(referencing result "$REQ_RACE")" .md)"
[ -n "$RESULT_RACE" ] || fail "the raced sweep produced no result for $REQ_RACE"
DECISIONS_FOR_RACE="$(referencing decision "$RESULT_RACE" | grep -c . || true)"
[ "$DECISIONS_FOR_RACE" -eq 1 ] || fail "the raced result was routed $DECISIONS_FOR_RACE times, expected exactly 1 — a hand-run route and the sweep's tail both routed it"
NOTIFY_AFTER_RACE="$(wc -l < "$CASTLE_NOTIFY_LOG" | tr -d ' ')"
[ "$(( NOTIFY_AFTER_RACE - NOTIFY_BEFORE_RACE ))" -eq 1 ] || fail "the raced result fired $(( NOTIFY_AFTER_RACE - NOTIFY_BEFORE_RACE )) notifications, expected exactly 1"
"$CASTLE" validate

# ---------------------------------------------------------------------
log "a hand-run castle work is refused while another turn holds the errand's lease, and writes nothing"
# ---------------------------------------------------------------------
REQ_LEASE="$("$CASTLE" ask "Dispatch test: the lease refusal path.")"
# Ten seconds, not three: the assertion below is that a *second*
# castle work is refused while this one holds the lease, and on a
# loaded CI runner a three-second turn can finish before the refusal is
# even attempted — turning a real regression into a legitimate retry
# that passes. The window only needs to be wider than the harness is
# slow.
CASTLE_TEST_WORKER_SLEEP=10 "$CASTLE" work "$REQ_LEASE" >"$WORKDIR/lease-holder.out" 2>&1 &
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
log "a tenant that emits a non-UTF-8 byte still completes — the turn is recorded, not crashed out of"
# ---------------------------------------------------------------------
# Verified as a real crash before the fix: `text=True` decoding raised
# UnicodeDecodeError out of communicate(), and the diff read raised it
# again from read_text(), which the OSError handler there did not
# catch. Either one escaped run_worker_turn with the claim already
# written and no result — so `castle work` died with a traceback,
# `castle dispatch` exited 1 (the code reserved for mechanism faults),
# and the NEXT sweep reaped a turn that had actually finished into a
# permanent, false `outcome: interrupted`, discarding the diff the
# tenant produced.
REQ_BINARY="$("$CASTLE" ask "Dispatch test: the tenant emits a byte that is not valid UTF-8.")"
CASTLE_TEST_WORKER_BINARY=1 "$CASTLE" dispatch >"$WORKDIR/binary-sweep.out" 2>&1 \
  || fail "a sweep whose tenant emitted a non-UTF-8 byte exited nonzero: $(cat "$WORKDIR/binary-sweep.out")"
RESULT_BINARY_FILE="$(referencing result "$REQ_BINARY")"
[ -n "$RESULT_BINARY_FILE" ] || fail "the non-UTF-8 tenant produced no result record at all"
grep -q '^outcome: completed$' "$RESULT_BINARY_FILE" || fail "$RESULT_BINARY_FILE should carry outcome: completed — the tenant exited 0, it just wrote a byte python could not decode"
grep -q 'placeholder after' "$RESULT_BINARY_FILE" || fail "$RESULT_BINARY_FILE lost the diff the tenant wrote"
"$CASTLE" validate || fail "the journal does not validate after a tenant emitted an undecodable byte"
"$CASTLE" dispatch >/dev/null
[ "$(count_referencing result "$REQ_BINARY")" -eq 1 ] || fail "the next sweep wrote a second result for $REQ_BINARY — a completed turn was reaped as interrupted"

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
log "a tenant that exits 0 while a detached helper still holds the pipes is completed, not timed out"
# ---------------------------------------------------------------------
# communicate(timeout=...) fires on pipe EOF, not on process exit. A
# `claude`-style CLI spawning a background helper that inherits its
# stdout/stderr diverges those two constantly: before this, such a
# turn blocked for the whole timeout and was recorded `outcome:
# timeout` with a body saying its process group had been killed — over
# an errand that finished and wrote its diff. The fix asks the process
# (proc.poll()), not the pipes.
#
# CASTLE_WORKER_TIMEOUT is deliberately LARGE here, and that is the
# assertion. Classifying the turn correctly was only half the bug: a
# single communicate(timeout=CASTLE_WORKER_TIMEOUT) still *waited* the
# whole timeout before the classification could happen, dispatch lock
# held, on a tenant that had already exited. This scenario used to run
# with a 3s timeout, where a 25s bound passed either way and proved
# nothing about the wait. At 600s the old code takes over ten minutes
# to write this result; the sliced wait takes seconds.
REQ_DETACH="$("$CASTLE" ask "Dispatch test: the tenant exits 0 but leaves a helper holding the pipes.")"
DETACH_START="$(date +%s)"
CASTLE_WORKER_COMMAND="$WORKER_DETACH" CASTLE_WORKER_TIMEOUT=600 "$CASTLE" dispatch >"$WORKDIR/detach-sweep.out" 2>&1 \
  || fail "the detached-helper sweep exited nonzero: $(cat "$WORKDIR/detach-sweep.out")"
DETACH_ELAPSED=$(( $(date +%s) - DETACH_START ))
RESULT_DETACH_FILE="$(referencing result "$REQ_DETACH")"
[ -n "$RESULT_DETACH_FILE" ] || fail "the detached-helper tenant produced no result record"
grep -q '^outcome: completed$' "$RESULT_DETACH_FILE" || fail "$RESULT_DETACH_FILE should carry outcome: completed — the tenant exited 0, only its leftover helper held the pipes open; got: $(grep '^outcome:' "$RESULT_DETACH_FILE" || echo none)"
grep -q 'synthetic (harness fixture only)' "$RESULT_DETACH_FILE" || fail "$RESULT_DETACH_FILE lost the diff the tenant wrote before exiting"
# Bounded by the poll slice plus the two drain windows — seconds — and
# nowhere near either the fixture's 30s helper or the 600s timeout.
[ "$DETACH_ELAPSED" -lt 60 ] || fail "the sweep waited ${DETACH_ELAPSED}s on a tenant that had already exited (CASTLE_WORKER_TIMEOUT was 600: the wait is not being sliced)"
log "  -> swept in ${DETACH_ELAPSED}s with CASTLE_WORKER_TIMEOUT=600 (the helper sleeps 30s and is not waited on)"
"$CASTLE" validate

# ---------------------------------------------------------------------
log "an IN-GROUP child left holding the pipes is killed with the turn, not left running past its own account"
# ---------------------------------------------------------------------
# The other half of the exited-tenant path. contract-worker-detach.sh
# calls setsid, so its helper is beyond any kill this turn can make.
# This fixture's child stays in the tenant's process group — and until
# now nothing killed it, because _kill_tenant_group ran only while the
# tenant itself was still alive. So the turn was recorded `completed`
# and the child ran on, able to keep writing into $CASTLE_REPO_ROOT
# after the journal's account of that turn was final.
#
# Three things at once: the wait is sliced (large timeout, seconds
# elapsed), the child is dead once the sweep returns, and killing it
# is what lets the drain finally succeed — so the tenant's own stdout
# lands in the result instead of the "could not be collected" note.
rm -f "$CASTLE_REPO_ROOT/straggler.pid"
REQ_STRAG="$("$CASTLE" ask "Dispatch test: the tenant exits 0 leaving an in-group child on the pipes.")"
STRAG_START="$(date +%s)"
CASTLE_WORKER_COMMAND="$WORKER_STRAGGLER" CASTLE_WORKER_TIMEOUT=600 "$CASTLE" dispatch >"$WORKDIR/straggler-sweep.out" 2>&1 \
  || fail "the in-group-straggler sweep exited nonzero: $(cat "$WORKDIR/straggler-sweep.out")"
STRAG_ELAPSED=$(( $(date +%s) - STRAG_START ))
[ "$STRAG_ELAPSED" -lt 60 ] || fail "the sweep waited ${STRAG_ELAPSED}s on a tenant that had already exited (CASTLE_WORKER_TIMEOUT was 600)"
RESULT_STRAG_FILE="$(referencing result "$REQ_STRAG")"
[ -n "$RESULT_STRAG_FILE" ] || fail "the in-group-straggler tenant produced no result record"
grep -q '^outcome: completed$' "$RESULT_STRAG_FILE" || fail "$RESULT_STRAG_FILE should carry outcome: completed — the tenant exited 0; got: $(grep '^outcome:' "$RESULT_STRAG_FILE" || echo none)"
STRAG_PID="$(cat "$CASTLE_REPO_ROOT/straggler.pid" 2>/dev/null || true)"
[ -n "$STRAG_PID" ] || fail "the straggler fixture wrote no pid file — it never ran as intended"
# The kill is a signal, so allow the exit to land; a couple of seconds
# is generous for a SIGKILL the sweep already issued before returning.
for _ in 1 2 3 4 5; do
  kill -0 "$STRAG_PID" 2>/dev/null || break
  sleep 1
done
if kill -0 "$STRAG_PID" 2>/dev/null; then
  kill -9 "$STRAG_PID" 2>/dev/null || true
  fail "the in-group child ($STRAG_PID) outlived the turn whose result already claims to account for it"
fi
# Killing the holder is what closes the pipes, so the drain that
# follows it succeeds and the tenant's reasoning survives.
grep -q 'could not be collected' "$RESULT_STRAG_FILE" && fail "$RESULT_STRAG_FILE gave up on the tenant's output even though the only thing holding the pipes was in-group and killable"
grep -q 'leaving an in-group child holding the pipes' "$RESULT_STRAG_FILE" || fail "$RESULT_STRAG_FILE lost the tenant's stdout, which the post-kill drain should have collected"
log "  -> swept in ${STRAG_ELAPSED}s; in-group child $STRAG_PID did not outlive the turn"
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

log "the reaper also handles a claim whose lease FILE outlived the process holding it — the file's presence proves nothing, only the lock does"
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
# Deliberately NOT asserting the lease file is gone. The reaper used to
# unlink it, which reintroduced the flock/unlink race the worker's own
# lock handling refuses: unlink is not atomic against an acquirer that
# already opened the old path, so one process can hold a lock on an
# unlinked inode while the next creates a fresh file and locks that.
# A leftover unheld lease file is harmless — the journal, not this
# directory, says whether a turn finished — so the file may or may not
# remain, and either way the reaping above is what matters.
"$CASTLE" validate

log "a resident who closes a crashed errand by hand is not contradicted by the next sweep"
# The shape the CLI itself suggests: `castle work R` crashed leaving a
# dangling claim, and the resident finishes the errand by hand with
# `castle record --type result --refs R` — no claim id, because the
# help text never asks for one. Before the recency clause, the next
# sweep reaped that claim into a permanent `interrupted` contradicting
# the result the resident had just written, fired a second
# notification about it, and the status surface masked the human's own
# closure forever.
REQ_HANDCLOSE="$("$CASTLE" ask "Dispatch test: a crashed turn the resident finishes by hand.")"
CLAIM_HANDCLOSE="$("$CASTLE" record --type claim --provenance requested --seat worker --refs "$REQ_HANDCLOSE" \
  --body "Planted claim: a turn that crashed before writing anything.")"
HANDCLOSE_RESULT="$("$CASTLE" record --type result --provenance requested --seat worker --refs "$REQ_HANDCLOSE" \
  --body "Resident finished this errand by hand after the worker crashed.")"
log "  -> claim $CLAIM_HANDCLOSE closed by hand-written result $HANDCLOSE_RESULT"
"$CASTLE" dispatch >/dev/null
[ "$(count_referencing result "$REQ_HANDCLOSE")" -eq 1 ] || fail "the sweep wrote a second result for $REQ_HANDCLOSE — it reaped a turn the resident had already accounted for by hand"
grep -l '^outcome: interrupted$' "$JOURNAL"/*-result-*.md 2>/dev/null | xargs -r grep -l "$CLAIM_HANDCLOSE" >/dev/null 2>&1 \
  && fail "an interrupted result was written for $CLAIM_HANDCLOSE despite a hand-written closure"
"$CASTLE" validate

log "  -- and the same closure holds when the resident's --refs also names some other errand's claim"
# `--refs R,C` is the spelling a resident lands on by copy-paste, and
# it used to make the two surfaces disagree. The exclusion in
# closing_result's clause (b) — a result naming any claim of this
# request does not close a different one by recency — was assembled by
# each caller: the reaper passed every claim in the journal, so a
# result naming an UNRELATED errand's claim tripped the exclusion and
# the turn looked open; castle-modal passed only this errand's fold,
# where that unrelated claim does not appear, so the same result read
# as a valid closure. The modal showed the errand closed while the next
# sweep wrote a permanent `interrupted` over it — precisely the
# disagreement closing_result's docstring promises cannot happen. The
# narrowing now lives inside closing_result, so no caller can diverge.
REQ_CROSSREF="$("$CASTLE" ask "Dispatch test: a crashed turn closed by hand, with a stray claim ref.")"
CLAIM_CROSSREF="$("$CASTLE" record --type claim --provenance requested --seat worker --refs "$REQ_CROSSREF" \
  --body "Planted claim: a turn that crashed before writing anything.")"
CROSSREF_RESULT="$("$CASTLE" record --type result --provenance requested --seat worker \
  --refs "$REQ_CROSSREF,$CLAIM_HANDCLOSE" \
  --body "Resident finished this errand by hand, naming another errand's claim by mistake.")"
log "  -> $CROSSREF_RESULT names $REQ_CROSSREF and the UNRELATED claim $CLAIM_HANDCLOSE"
"$CASTLE" dispatch >/dev/null
[ "$(count_referencing result "$REQ_CROSSREF")" -eq 1 ] || fail "the sweep reaped $CLAIM_CROSSREF despite a hand-written closure, because the closure also named an unrelated errand's claim"
grep -l '^outcome: interrupted$' "$JOURNAL"/*-result-*.md 2>/dev/null | xargs -r grep -l "$CLAIM_CROSSREF" >/dev/null 2>&1 \
  && fail "an interrupted result was written for $CLAIM_CROSSREF — the reaper and the status surface are reading the same closure differently again"
"$CASTLE" validate

log "per-turn accounting: an interrupted RETRY of an already-failed errand is still reaped"
# The case a per-request rule got wrong. $REQ_FAIL already carries a
# `failed` result from its automatic attempt. A resident retries it by
# hand; that turn dies without writing anything. Under "a claim is
# closed if its request has some result," the first turn's account
# closed the second turn's claim, the retry was never reaped, and the
# errand sat showing a stale `failed` forever with its real last turn
# unrecorded. Results now name the claim they close, so each turn is
# accounted for on its own.
RETRY_CLAIM="$("$CASTLE" record --type claim --provenance requested --seat worker --refs "$REQ_FAIL" \
  --body "Planted claim: a hand-run retry of an already-failed errand, whose process then died.")"
RESULTS_BEFORE_RETRY_REAP="$(count_referencing result "$REQ_FAIL")"
"$CASTLE" dispatch >/dev/null
[ "$(count_referencing result "$REQ_FAIL")" -eq $(( RESULTS_BEFORE_RETRY_REAP + 1 )) ] || fail "the interrupted retry of an already-failed errand was not reaped — claim $RETRY_CLAIM has no result of its own"
RETRY_RESULT_FILE="$(grep -l "^refs: .*$RETRY_CLAIM" "$JOURNAL"/*-result-*.md 2>/dev/null || true)"
[ -n "$RETRY_RESULT_FILE" ] || fail "no result record references the retry's claim $RETRY_CLAIM"
grep -q '^outcome: interrupted$' "$RETRY_RESULT_FILE" || fail "$RETRY_RESULT_FILE does not carry outcome: interrupted"
# And it is still not re-dispatched: eligibility is per request, and
# this request has results. Only the reaping is per turn.
[ "$(count_referencing claim "$REQ_FAIL")" -eq 2 ] || fail "a further automatic turn was started on the failed errand"
"$CASTLE" validate

log "every worker-written result names the claim it closes, not just the request"
grep -q "^refs: $REQ1,$(basename "$(referencing claim "$REQ1")" .md)\$" "$JOURNAL/$RESULT1.md" \
  || fail "$RESULT1 does not reference the claim of the turn that produced it: $(grep '^refs:' "$JOURNAL/$RESULT1.md")"

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
log "  -- and its BLOCKING twin, the same shape with one flag added, DOES resume the errand exactly once (docs/tasks/0023)"
# ---------------------------------------------------------------------
# Deliberately beside the non-behavior test above rather than in
# resume.sh: the pair is the proof that resumption is opt-in. The two
# fixtures differ in exactly one argument, and go opposite ways.
REQ_BLOCKING="$("$CASTLE" ask "Dispatch test: an errand whose question will stop it.")"
"$CASTLE" dispatch >/dev/null
[ "$(count_referencing claim "$REQ_BLOCKING")" -eq 1 ] || fail "the blocking-twin errand was never worked"
Q_BLOCKING="$("$CASTLE" record --type question --provenance requested --seat worker --refs "$REQ_BLOCKING" \
  --blocking --body "Dispatch test: a question its writer says the errand cannot proceed without.")"
grep -q '^blocking: true$' "$JOURNAL/$Q_BLOCKING.md" || fail "$Q_BLOCKING does not carry blocking: true"
"$CASTLE" dispatch >/dev/null
[ "$(count_referencing claim "$REQ_BLOCKING")" -eq 1 ] || fail "an UNANSWERED blocking question resumed $REQ_BLOCKING — only the resident may close a question"
A_BLOCKING="$("$CASTLE" answer "$Q_BLOCKING" "Dispatch test: the resident closes the blocking question.")"
"$CASTLE" dispatch >/dev/null
[ "$(count_referencing claim "$REQ_BLOCKING")" -eq 2 ] || fail "answering a BLOCKING question did not resume $REQ_BLOCKING"
[ "$(count_referencing result "$REQ_BLOCKING")" -eq 2 ] || fail "the resumed turn on $REQ_BLOCKING wrote no result"
grep -q "^refs: $REQ_BLOCKING,$A_BLOCKING\$" "$JOURNAL"/*-claim-*.md \
  || fail "the resuming claim does not name the answer it spent — nothing bounds the resumption"
"$CASTLE" dispatch >/dev/null
"$CASTLE" dispatch >/dev/null
[ "$(count_referencing claim "$REQ_BLOCKING")" -eq 2 ] || fail "a spent answer resumed $REQ_BLOCKING a second time"
"$CASTLE" validate

log "  -- castle record refuses a --blocking question with no --refs: it could never be attributed to an errand"
if "$CASTLE" record --type question --provenance requested --seat worker --blocking \
  --body "Dispatch test: a blocking question with nothing to attribute it to." >"$WORKDIR/blocking-norefs.out" 2>&1; then
  fail "castle record wrote a --blocking question with no --refs"
fi
grep -q "refusing to write a --blocking question with no --refs" "$WORKDIR/blocking-norefs.out" \
  || fail "the --blocking/--refs refusal did not explain itself: $(cat "$WORKDIR/blocking-norefs.out")"

log "  -- and validate rejects a hand-planted blocking value that is not the one spelling any writer produces"
BAD_BLOCKING_FILE="$JOURNAL/20260101T000000Z-question-bad0b1.md"
cat > "$BAD_BLOCKING_FILE" <<EOF
---
id: 20260101T000000Z-question-bad0b1
type: question
provenance: requested
refs: $REQ1
seat: worker
created: 2026-01-01T00:00:00Z
blocking: false
---

Malformed blocking fixture: 'false' would read as truthy to the fold that resumes errands.
EOF
if "$CASTLE" validate >"$WORKDIR/bad-blocking.out" 2>"$WORKDIR/bad-blocking.err"; then
  fail "castle validate accepted a question record with blocking: false"
fi
grep -q "blocking" "$WORKDIR/bad-blocking.err" || fail "castle validate's blocking rejection message changed unexpectedly"
rm -f "$BAD_BLOCKING_FILE"
"$CASTLE" validate || fail "the journal did not validate clean once the malformed blocking fixture was removed"

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
log "a request a tenant files during its own turn is stamped, and never auto-dispatched (docs/tasks/0021 §2.4(e))"
# ---------------------------------------------------------------------
# The unbounded-spend case, and the reason it is not hypothetical: a
# tenant that notices a second problem while fixing the first files it
# the sanctioned way, with `castle ask`. Each filed request used to be
# a fresh errand with its own fresh automatic attempt, so one sweep
# could run turn after turn — holding the global dispatch lock
# throughout — off a single resident request. Reproduced at five turns
# before the stamp existed.
REQ_FILER="$("$CASTLE" ask "Dispatch test: the tenant will file a follow-up while working this.")"
REQUESTS_BEFORE_FILER="$(count_of_type request)"
FILER_START="$(date +%s)"
CASTLE_WORKER_COMMAND="$WORKER_FILER" CASTLE_TEST_CASTLE_BIN="$CASTLE" "$CASTLE" dispatch >"$WORKDIR/filer-sweep.out" 2>&1   || fail "the filer sweep exited nonzero: $(cat "$WORKDIR/filer-sweep.out")"
FILER_ELAPSED=$(( $(date +%s) - FILER_START ))
cat "$WORKDIR/filer-sweep.out"
# It terminated at all: the assertion that would have hung forever (or
# until the harness was killed) before the fix.
[ "$FILER_ELAPSED" -lt 60 ] || fail "the sweep took ${FILER_ELAPSED}s — a tenant-filed request is extending it"
[ "$(count_referencing result "$REQ_FILER")" -eq 1 ] || fail "expected exactly 1 result for $REQ_FILER, got $(count_referencing result "$REQ_FILER")"
[ "$(count_of_type request)" -eq $(( REQUESTS_BEFORE_FILER + 1 )) ] || fail "expected exactly one follow-up request to have been filed, got $(( $(count_of_type request) - REQUESTS_BEFORE_FILER ))"

FOLLOW_UP_FILE="$(grep -l '^filed-during-turn: ' "$JOURNAL"/*-request-*.md 2>/dev/null || true)"
[ -n "$FOLLOW_UP_FILE" ] || fail "the tenant's follow-up request carries no filed-during-turn stamp — nothing stops it being auto-dispatched"
FOLLOW_UP="$(basename "$FOLLOW_UP_FILE" .md)"
log "  -> follow-up request: $FOLLOW_UP"
CLAIM_FOR_FILER="$(basename "$(referencing claim "$REQ_FILER")" .md)"
grep -q "^filed-during-turn: $CLAIM_FOR_FILER\$" "$FOLLOW_UP_FILE" || fail "$FOLLOW_UP_FILE's filed-during-turn does not name the claim of the turn that filed it ($CLAIM_FOR_FILER)"
# The tenant never sets this itself — it runs plain `castle ask`. The
# stamp arrives because the tenant inherits CASTLE_WORKER_CLAIM, which
# is the whole mechanism, and a `castle record --type request` would
# have been stamped identically.
"$CASTLE" dispatch >/dev/null
"$CASTLE" dispatch >/dev/null
[ "$(count_referencing result "$FOLLOW_UP")" -eq 0 ] || fail "a tenant-filed request was auto-dispatched on a later sweep"
[ "$(count_referencing claim "$FOLLOW_UP")" -eq 0 ] || fail "a tenant-filed request was claimed by a worker on a later sweep"
"$CASTLE" validate

log "  -- and it stays an ordinary request: runnable by hand, not deleted or downgraded"
"$CASTLE" work "$FOLLOW_UP" >/dev/null || fail "castle work refused to run a tenant-filed request by hand — the stamp must bound automatic spend, not forbid the work"
[ "$(count_referencing result "$FOLLOW_UP")" -eq 1 ] || fail "a hand-run castle work on the tenant-filed request produced no result"
# That hand-run result is unrouted until something routes it, and the
# next section asserts a sweep appends nothing when only a correction
# is outstanding — so route it here rather than leaving a false
# positive lying in wait for that assertion.
"$CASTLE" dispatch >/dev/null
"$CASTLE" validate

# ---------------------------------------------------------------------
log "a tenant that cannot be started stops the sweep — it does not burn every eligible request's one attempt"
# The bounded-retry rule is per request, so a sweep that shrugged at an
# unrunnable tenant and carried on would spend the single automatic
# attempt of EVERY eligible errand on one transient fault — a store
# path swapped mid-rebuild, a broken PATH — and exit 0 while doing it.
# The errand it did attempt still gets its `outcome: failed` result
# (that is what closes the silent-retry loop); what stops is the sweep.
REQ_ABORT_A="$("$CASTLE" ask "Dispatch test: first of two, attempted with a broken tenant.")"
sleep 1
REQ_ABORT_B="$("$CASTLE" ask "Dispatch test: second of two, must survive the broken tenant untouched.")"
if CASTLE_WORKER_COMMAND="$WORKDIR/still-not-a-real-binary" "$CASTLE" dispatch >"$WORKDIR/abort-sweep.out" 2>&1; then
  fail "a sweep whose tenant could not be started exited 0 — the unit's health signal has to say the mechanism broke"
fi
cat "$WORKDIR/abort-sweep.out"
grep -q "stopping this sweep" "$WORKDIR/abort-sweep.out" || fail "the aborting sweep did not explain itself: $(cat "$WORKDIR/abort-sweep.out")"
[ "$(count_referencing result "$REQ_ABORT_A")" -eq 1 ] || fail "the attempted request has no failed result — the silent-retry loop is back"
grep -q '^outcome: failed$' "$(referencing result "$REQ_ABORT_A")" || fail "the attempted request's result does not carry outcome: failed"
[ "$(count_referencing result "$REQ_ABORT_B")" -eq 0 ] || fail "the second eligible request was attempted too — one broken tenant consumed more than one automatic attempt"
[ "$(count_referencing claim "$REQ_ABORT_B")" -eq 0 ] || fail "the second eligible request was claimed despite the sweep aborting"
"$CASTLE" validate

log "  -- and the survivor is still eligible once the tenant works again"
"$CASTLE" dispatch >/dev/null
[ "$(count_referencing result "$REQ_ABORT_B")" -eq 1 ] || fail "the request spared by the abort was not picked up by the next healthy sweep"
grep -q '^outcome: completed$' "$(referencing result "$REQ_ABORT_B")" || fail "the spared request did not complete on the next sweep"
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
