#!/usr/bin/env bash
# test/agent-loop/run.sh — the scripted-tenant agent-loop harness
# (docs/tasks/0008-agent-layer-skeleton.md, extended by
# docs/tasks/0009-ambient-intake.md).
#
# Proposal 03's hardening test taking its first steps: exercises the
# full record loop — intake -> router -> worker -> router -> digest —
# with a scripted worker holding the worker seat and nothing else in
# the loop but this script and `castle` itself. Zero models, zero
# network, no Nix (agent/castle is stdlib Python; this harness runs
# anywhere bash + python3 do, unlike test/vm-install's harness).
#
# Two canned errands run through the loop so the router's provenance
# rule is checked in both directions: a `requested` errand must route
# to "notify" and an `initiated` one must route to "digest" — a single
# errand would leave the *other* branch of that rule completely
# unexercised. Both errands' scripted worker now also raises a
# mid-errand `question` record before its `result` (docs/tasks/0009
# item 7's third gap: nothing previously produced one in CI, even
# though worker-questions-route-through-the-router is a central claim
# of the architecture) — the requested errand's question is answered
# for real via `castle answer`, exercising Proposal 05's write path
# into the resident model end to end.
#
# The worker script itself is overridable via
# CASTLE_AGENT_LOOP_WORKER — test/agent-loop/tenant-swap.sh runs this
# whole script twice with two differently-shaped scripted workers and
# diffs a normalized summary of the resulting journals, which this
# script writes to CASTLE_AGENT_LOOP_SUMMARY_OUT when that variable is
# set.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CASTLE="$REPO_ROOT/agent/castle"
WORKER="${CASTLE_AGENT_LOOP_WORKER:-$REPO_ROOT/test/agent-loop/scripted-worker.sh}"
CHECK="$REPO_ROOT/test/agent-loop/check_assertions.py"
NORMALIZE="$REPO_ROOT/test/agent-loop/normalize_journal.py"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/castle-agent-loop.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

# CASTLE_STATE_DIR is the env var docs/tasks/0008 calls out as what
# makes this harness possible: it points a real journal at a throwaway
# temp directory instead of a resident's actual state/ dir.
export CASTLE_STATE_DIR="$WORKDIR/state"
export XDG_RUNTIME_DIR="$WORKDIR/runtime"
mkdir -p "$CASTLE_STATE_DIR" "$XDG_RUNTIME_DIR"

# CASTLE_NOTIFY_COMMAND (docs/tasks/0009 item 5): CI has no notification
# daemon and no display session, so `castle route`'s attempt to fire a
# real notification on the `notify` channel is pointed at a stub that
# logs each call instead of failing (harmlessly) against a missing
# notify-send. This is the same pattern CASTLE_STATE_DIR already uses:
# the Nix module (modules/agent) wires a Nix option into this
# environment variable for a real deployment; this plain-bash harness
# sets the variable directly, bypassing Nix entirely.
export CASTLE_NOTIFY_LOG="$WORKDIR/notify.log"
export CASTLE_NOTIFY_COMMAND="$REPO_ROOT/test/agent-loop/notify-stub.sh"
: > "$CASTLE_NOTIFY_LOG"

log() { printf '>>> %s\n' "$*"; }
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  printf 'Journal preserved would have been at: %s (already cleaned up on exit)\n' "$CASTLE_STATE_DIR/journal" >&2
  exit 1
}

log "using worker tenant: $WORKER"

log "intake: filing a resident-requested errand"
REQ1="$("$CASTLE" ask "Test errand alpha: resident-requested, should surface via notify.")"
log "  -> $REQ1"

log "intake: filing a system-initiated errand"
REQ2="$("$CASTLE" ask --provenance initiated "Test errand beta: system-initiated, should fold into the digest.")"
log "  -> $REQ2"

log "router pass before any result exists — must be a no-op, not a crash"
ROUTE1_OUT="$("$CASTLE" route)"
echo "$ROUTE1_OUT"
case "$ROUTE1_OUT" in
  *"nothing unrouted"*) ;;
  *) fail "router routed something before any result/question record existed: $ROUTE1_OUT" ;;
esac

log "scripted worker seat: request alpha (raises a question, then a result)"
RES1="$("$WORKER" "$CASTLE" "$REQ1")"
log "  -> $RES1"

log "scripted worker seat: request beta (raises a question, then a result)"
RES2="$("$WORKER" "$CASTLE" "$REQ2")"
log "  -> $RES2"

# `|| true` on every grep-into-a-variable below (finding 7, 0009 review
# pass): under `set -euo pipefail`, a `grep` that matches nothing exits
# non-zero, and that failure — piped through `head -n1` or not — kills
# the script right here, before the `[ -n ... ] || fail "..."` on the
# next line ever runs. The operator then sees a bare grep error instead
# of the descriptive diagnostic this script was written to give them.
# `|| true` lets the assignment fall through to empty, so the actual
# check on the next line is the thing that fails loudly.
QUESTION1="$(grep -l "^refs: $REQ1\$" "$CASTLE_STATE_DIR"/journal/*-question-*.md | head -n1 || true)"
[ -n "$QUESTION1" ] || fail "expected the alpha worker to raise a question referencing $REQ1; none found"
QUESTION1="$(basename "$QUESTION1" .md)"
QUESTION2="$(grep -l "^refs: $REQ2\$" "$CASTLE_STATE_DIR"/journal/*-question-*.md | head -n1 || true)"
[ -n "$QUESTION2" ] || fail "expected the beta worker to raise a question referencing $REQ2; none found"
QUESTION2="$(basename "$QUESTION2" .md)"
log "  -> question alpha: $QUESTION1, question beta: $QUESTION2"

log "router pass: must append a decision record for each result and question, nothing silent"
"$CASTLE" route

DECISION_COUNT_1="$(find "$CASTLE_STATE_DIR/journal" -name '*-decision-*.md' | wc -l | tr -d ' ')"
[ "$DECISION_COUNT_1" -eq 4 ] || fail "expected exactly 4 decision records after routing both questions and both results, got $DECISION_COUNT_1"

log "router pass: idempotent — a fully-routed journal produces zero new decisions"
ROUTE3_OUT="$("$CASTLE" route)"
echo "$ROUTE3_OUT"
case "$ROUTE3_OUT" in
  *"nothing unrouted"*) ;;
  *) fail "a second route pass over an already-routed journal routed something again: $ROUTE3_OUT" ;;
esac
DECISION_COUNT_2="$(find "$CASTLE_STATE_DIR/journal" -name '*-decision-*.md' | wc -l | tr -d ' ')"
[ "$DECISION_COUNT_2" -eq "$DECISION_COUNT_1" ] || fail "idempotency check failed: decision count went from $DECISION_COUNT_1 to $DECISION_COUNT_2"

log "validate: every record in the journal must pass the schema check"
"$CASTLE" validate

log "independent structural assertions (evidence non-empty, nothing routed silently)"
"$CHECK" "$CASTLE_STATE_DIR/journal"

log "notify channel: the requested errand's question+result must have actually fired the (stubbed) notify command"
NOTIFY_COUNT="$(wc -l < "$CASTLE_NOTIFY_LOG" | tr -d ' ')"
[ "$NOTIFY_COUNT" -eq 2 ] || fail "expected exactly 2 notify-command invocations (question+result for the requested errand), got $NOTIFY_COUNT"

log "digest: fold the journal and check both errands render"
DIGEST_OUT="$("$CASTLE" digest)"
echo "$DIGEST_OUT"
echo "$DIGEST_OUT" | grep -q "Test errand alpha" || fail "digest did not render errand alpha's request body"
echo "$DIGEST_OUT" | grep -q "Test errand beta" || fail "digest did not render errand beta's request body"
echo "$DIGEST_OUT" | grep -q "channel: notify" || fail "digest did not show a 'notify'-channel decision anywhere"
echo "$DIGEST_OUT" | grep -q "channel: digest" || fail "digest did not show a 'digest'-channel decision anywhere"

log "checking the channel landed on the RIGHT errand, not just present somewhere"
# Same `|| true` reasoning as above (finding 7): each assignment below
# has no `[ -n ... ]` check of its own, but a `grep -l` that matches
# nothing would still kill the script via set -e before the `grep -q
# ... || fail "..."` on the following line ever ran. With `|| true`,
# a no-match assignment instead leaves the variable empty, `grep -q
# pattern ""` fails to open a file named "" and returns non-zero, and
# the intended `fail "..."` diagnostic fires as designed.
DECISION_FOR_RES1="$(grep -l "^refs: $RES1\$" "$CASTLE_STATE_DIR"/journal/*-decision-*.md || true)"
grep -q '^channel: notify$' "$DECISION_FOR_RES1" || fail "the requested errand's result did not route to 'notify': $DECISION_FOR_RES1"
DECISION_FOR_RES2="$(grep -l "^refs: $RES2\$" "$CASTLE_STATE_DIR"/journal/*-decision-*.md || true)"
grep -q '^channel: digest$' "$DECISION_FOR_RES2" || fail "the initiated errand's result did not route to 'digest': $DECISION_FOR_RES2"
DECISION_FOR_Q1="$(grep -l "^refs: $QUESTION1\$" "$CASTLE_STATE_DIR"/journal/*-decision-*.md || true)"
grep -q '^channel: notify$' "$DECISION_FOR_Q1" || fail "the requested errand's question did not route to 'notify': $DECISION_FOR_Q1"
DECISION_FOR_Q2="$(grep -l "^refs: $QUESTION2\$" "$CASTLE_STATE_DIR"/journal/*-decision-*.md || true)"
grep -q '^channel: digest$' "$DECISION_FOR_Q2" || fail "the initiated errand's question did not route to 'digest': $DECISION_FOR_Q2"

log "resident-model write path (Proposal 05): answering the alpha question, fact name read from the question record itself"
ANSWER1="$("$CASTLE" answer "$QUESTION1" "Fix small perceptual issues like this one and tell me afterward.")"
log "  -> $ANSWER1"
MODEL_FILE="$CASTLE_STATE_DIR/resident-model.md"
[ -f "$MODEL_FILE" ] || fail "castle answer --fact (auto-detected) did not create $MODEL_FILE"
grep -q '^fact: scripted-worker-test-fact$' "$MODEL_FILE" || fail "resident-model.md missing the expected fact entry"
grep -q "^asked: $QUESTION1\$" "$MODEL_FILE" || fail "resident-model.md entry does not cite the question it was asked from"
grep -q "^answered: $ANSWER1\$" "$MODEL_FILE" || fail "resident-model.md entry does not cite the answer record that closed it"

log "router bug regression (docs/tasks/0009 item 7): a non-router decision referencing a result must not suppress routing"
REQ3="$("$CASTLE" ask --provenance initiated "Test errand gamma: only exists to exercise the router-bug regression test.")"
RES3="$("$CASTLE" record --type result --provenance initiated --seat worker --refs "$REQ3" --body "Errand gamma result, for the regression test only.")"
FAKE_DECISION="$("$CASTLE" record --type decision --provenance initiated --seat worker --refs "$RES3" --evidence "not a real router decision: seat=worker, not router — this is the exact shape docs/tasks/0009 item 7's bug fix guards against")"
log "  -> a decision from seat=worker (not router) now references $RES3: $FAKE_DECISION"
"$CASTLE" route
ROUTER_DECISIONS_FOR_RES3="$(grep -l "^refs: $RES3\$" "$CASTLE_STATE_DIR"/journal/*-decision-*.md | xargs grep -l '^seat: router$' || true)"
[ -n "$ROUTER_DECISIONS_FOR_RES3" ] || fail "router bug regressed: a non-router decision referencing $RES3 suppressed its routing — no router decision was appended for it"
grep -q '^channel: digest$' "$ROUTER_DECISIONS_FOR_RES3" || fail "errand gamma's result did not route to 'digest' (provenance=initiated): $ROUTER_DECISIONS_FOR_RES3"

if [ -n "${CASTLE_AGENT_LOOP_SUMMARY_OUT:-}" ]; then
  log "writing normalized journal summary to $CASTLE_AGENT_LOOP_SUMMARY_OUT (test/agent-loop/tenant-swap.sh)"
  "$NORMALIZE" "$CASTLE_STATE_DIR/journal" > "$CASTLE_AGENT_LOOP_SUMMARY_OUT"
fi

log "all assertions passed"
