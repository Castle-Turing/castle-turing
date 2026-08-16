#!/usr/bin/env bash
# test/agent-loop/modal-headless-test.sh — drives agent/castle-modal
# headlessly (docs/tasks/0009-ambient-intake.md's verification plan):
# "the modal is a script reading stdin and writing records; drive it
# headlessly with canned input and assert the request record it
# produces. No compositor required." Pipes canned input at both of its
# modes and checks the journal/output on the other side — no foot, no
# Sway, no display server anywhere in this script.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODAL="$REPO_ROOT/agent/castle-modal"
CASTLE="$REPO_ROOT/agent/castle"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/castle-modal-test.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT
export CASTLE_STATE_DIR="$WORKDIR/state"
export XDG_RUNTIME_DIR="$WORKDIR/runtime"
mkdir -p "$CASTLE_STATE_DIR" "$XDG_RUNTIME_DIR"

log() { printf '>>> %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

log "compose mode: canned multi-line input ending in a lone '.' line"
REQUEST_ID="$(printf 'The cursor is too small on the laptop screen.\nHappens after every login.\n.\n' | "$MODAL" --mode compose)"
[ -n "$REQUEST_ID" ] || fail "compose mode printed no record id"
log "  -> $REQUEST_ID"

RECORD_FILE="$CASTLE_STATE_DIR/journal/$REQUEST_ID.md"
[ -f "$RECORD_FILE" ] || fail "expected a journal record at $RECORD_FILE"
grep -q '^type: request$' "$RECORD_FILE" || fail "$RECORD_FILE is not a request record"
grep -q '^provenance: requested$' "$RECORD_FILE" || fail "$RECORD_FILE should carry provenance=requested (a human typed at the modal)"
grep -q '^seat: intake$' "$RECORD_FILE" || fail "$RECORD_FILE should carry seat=intake — the modal is an intake surface, same as castle ask"
grep -q "The cursor is too small on the laptop screen." "$RECORD_FILE" || fail "$RECORD_FILE did not capture the first line of the composed body"
grep -q "Happens after every login." "$RECORD_FILE" || fail "$RECORD_FILE did not capture the second line of the composed body"

log "compose mode: EOF with no trailing '.' line must also terminate cleanly"
REQUEST_ID_2="$(printf 'Wi-Fi keeps dropping after suspend.' | "$MODAL" --mode compose)"
[ -n "$REQUEST_ID_2" ] || fail "compose mode (EOF-terminated) printed no record id"

log "compose mode: an empty request must be refused, not filed as a blank errand"
if printf '.\n' | "$MODAL" --mode compose >"$WORKDIR/modal-empty-out" 2>"$WORKDIR/modal-empty-err"; then
  fail "compose mode accepted an empty request"
fi
grep -q "empty request" "$WORKDIR/modal-empty-err" || fail "compose mode's refusal message changed unexpectedly"

log "status mode: both filed errands must render, with what was asked and their state"
STATUS_OUT="$("$MODAL" --mode status)"
echo "$STATUS_OUT"
echo "$STATUS_OUT" | grep -q "$REQUEST_ID" || fail "status mode did not list $REQUEST_ID"
echo "$STATUS_OUT" | grep -q "$REQUEST_ID_2" || fail "status mode did not list $REQUEST_ID_2"
echo "$STATUS_OUT" | grep -q "The cursor is too small on the laptop screen." || fail "status mode did not show what was asked"
echo "$STATUS_OUT" | grep -q "in progress" || fail "status mode did not show a request with no result yet as 'in progress'"

log "status mode: a request with a result renders as 'done'"
"$CASTLE" record --type result --provenance requested --seat worker --refs "$REQUEST_ID" --body "Fixed." >/dev/null
STATUS_OUT_2="$("$MODAL" --mode status)"
echo "$STATUS_OUT_2" | grep -A1 "^\[$REQUEST_ID\]" | grep -q "done" || fail "status mode did not mark the completed errand as 'done'"

log "status mode: an unanswered question must be surfaced even alongside a result (0009 review pass finding 4)"
log "  -- the worker prompt tells tenants to file the question alongside the result rather than stopping, so this is the NORMAL shape, not an edge case"
REQUEST_ID_3="$(printf 'Third errand: worker files a result and an unanswered question together.\n.\n' | "$MODAL" --mode compose)"
"$CASTLE" record --type question --provenance requested --seat worker --refs "$REQUEST_ID_3" --body "Should I also handle the related case?" >/dev/null
"$CASTLE" record --type result --provenance requested --seat worker --refs "$REQUEST_ID_3" --body "Handled the main case." >/dev/null
STATUS_OUT_3="$("$MODAL" --mode status)"
echo "$STATUS_OUT_3" | grep -A1 "^\[$REQUEST_ID_3\]" | grep -q "waiting on you" || fail "status mode did not surface 'waiting on you' for an errand with an unanswered question, even though it also has a result"

log "status mode: an empty journal renders a friendly message, not a crash"
EMPTY_STATE="$(mktemp -d)"
CASTLE_STATE_DIR="$EMPTY_STATE" "$MODAL" --mode status | grep -q "No errands yet" || fail "empty-journal status mode did not print the expected message"
rm -rf "$EMPTY_STATE"

log "all assertions passed"
