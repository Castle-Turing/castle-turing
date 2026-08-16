#!/usr/bin/env bash
# test/agent-loop/run.sh — the scripted-tenant agent-loop harness
# (docs/tasks/0008-agent-layer-skeleton.md).
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
# to "now" and an `initiated` one must route to "digest" — a single
# errand would leave the *other* branch of that rule completely
# unexercised.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CASTLE="$REPO_ROOT/agent/castle"
WORKER="$REPO_ROOT/test/agent-loop/scripted-worker.sh"
CHECK="$REPO_ROOT/test/agent-loop/check_assertions.py"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/castle-agent-loop.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

# CASTLE_STATE_DIR is the env var docs/tasks/0008 calls out as what
# makes this harness possible: it points a real journal at a throwaway
# temp directory instead of a resident's actual state/ dir.
export CASTLE_STATE_DIR="$WORKDIR/state"
export XDG_RUNTIME_DIR="$WORKDIR/runtime"
mkdir -p "$CASTLE_STATE_DIR" "$XDG_RUNTIME_DIR"

log() { printf '>>> %s\n' "$*"; }
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  printf 'Journal preserved would have been at: %s (already cleaned up on exit)\n' "$CASTLE_STATE_DIR/journal" >&2
  exit 1
}

log "intake: filing a resident-requested errand"
REQ1="$("$CASTLE" ask "Test errand alpha: resident-requested, should surface now.")"
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

log "scripted worker seat: request alpha"
RES1="$("$WORKER" "$CASTLE" "$REQ1")"
log "  -> $RES1"

log "scripted worker seat: request beta"
RES2="$("$WORKER" "$CASTLE" "$REQ2")"
log "  -> $RES2"

log "router pass: must append a decision record for each result, nothing silent"
"$CASTLE" route

DECISION_COUNT_1="$(find "$CASTLE_STATE_DIR/journal" -name '*-decision-*.md' | wc -l | tr -d ' ')"
[ "$DECISION_COUNT_1" -eq 2 ] || fail "expected exactly 2 decision records after routing both results, got $DECISION_COUNT_1"

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

log "digest: fold the journal and check both errands render"
DIGEST_OUT="$("$CASTLE" digest)"
echo "$DIGEST_OUT"
echo "$DIGEST_OUT" | grep -q "Test errand alpha" || fail "digest did not render errand alpha's request body"
echo "$DIGEST_OUT" | grep -q "Test errand beta" || fail "digest did not render errand beta's request body"
echo "$DIGEST_OUT" | grep -q "channel: now" || fail "digest did not show a 'now'-channel decision anywhere"
echo "$DIGEST_OUT" | grep -q "channel: digest" || fail "digest did not show a 'digest'-channel decision anywhere"

log "checking the channel landed on the RIGHT errand, not just present somewhere"
DECISION_FOR_RES1="$(grep -l "^refs: $RES1\$" "$CASTLE_STATE_DIR"/journal/*-decision-*.md)"
grep -q '^channel: now$' "$DECISION_FOR_RES1" || fail "the requested errand's result did not route to 'now': $DECISION_FOR_RES1"
DECISION_FOR_RES2="$(grep -l "^refs: $RES2\$" "$CASTLE_STATE_DIR"/journal/*-decision-*.md)"
grep -q '^channel: digest$' "$DECISION_FOR_RES2" || fail "the initiated errand's result did not route to 'digest': $DECISION_FOR_RES2"

log "all assertions passed"
