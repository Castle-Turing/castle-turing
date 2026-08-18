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

log "status mode: a request with no downstream records must not claim to be 'in progress' (docs/tasks/0015) — nothing has claimed it yet"
echo "$STATUS_OUT" | grep -q "in progress" && fail "status mode still claims an untouched errand is 'in progress' — no worker has ever run automatically on the reference host, so this reads as permanently true"
echo "$STATUS_OUT" | grep -A1 "^\[$REQUEST_ID\]" | grep -q "awaiting a worker" || fail "status mode did not show a request with no downstream records as 'awaiting a worker'"
echo "$STATUS_OUT" | grep -A1 "^\[$REQUEST_ID_2\]" | grep -q "awaiting a worker" || fail "status mode did not show the second untouched request as 'awaiting a worker'"

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

log "compose mode, headless correction path (docs/tasks/0010-correction-record.md): --kind correction produces a correction record and a volunteered resident-model entry"
CORRECTION_ID="$(printf 'You pinged me about something that could have waited.\n.\n' | "$MODAL" --mode compose --kind correction)"
[ -n "$CORRECTION_ID" ] || fail "compose mode --kind correction printed no record id"
CORRECTION_FILE="$CASTLE_STATE_DIR/journal/$CORRECTION_ID.md"
[ -f "$CORRECTION_FILE" ] || fail "expected a journal record at $CORRECTION_FILE"
grep -q '^type: correction$' "$CORRECTION_FILE" || fail "$CORRECTION_FILE is not a correction record"
grep -q '^seat: intake$' "$CORRECTION_FILE" || fail "$CORRECTION_FILE should carry seat=intake, same as every other intake write"
grep -q '^provenance: requested$' "$CORRECTION_FILE" || fail "$CORRECTION_FILE should carry provenance=requested — a correction is resident speech through intake, not addressed to the resident"
grep -q '^surface: modal$' "$CORRECTION_FILE" || fail "$CORRECTION_FILE should carry surface=modal"
grep -q "You pinged me about something that could have waited." "$CORRECTION_FILE" || fail "$CORRECTION_FILE did not capture the correction body verbatim"
MODEL_FILE="$CASTLE_STATE_DIR/resident-model.md"
[ -f "$MODEL_FILE" ] || fail "compose --kind correction did not create $MODEL_FILE"
grep -q '^provenance: volunteered$' "$MODEL_FILE" || fail "$MODEL_FILE is missing a provenance: volunteered entry"
grep -q "^stated: $CORRECTION_ID\$" "$MODEL_FILE" || fail "$MODEL_FILE's volunteered entry does not cite the correction record it came from"
grep -q "You pinged me about something that could have waited." "$MODEL_FILE" || fail "$MODEL_FILE does not carry the correction's full text verbatim"
"$CASTLE" validate || fail "journal failed to validate after filing a correction through the modal"

log "compose mode, backward compatibility: piped input with no --kind flag still files a plain request (default unchanged)"
COMPAT_ID="$(printf 'Backward-compat check: no --kind flag at all.\n.\n' | "$MODAL" --mode compose)"
[ -n "$COMPAT_ID" ] || fail "compose mode with no --kind flag printed no record id"
grep -q '^type: request$' "$CASTLE_STATE_DIR/journal/$COMPAT_ID.md" || fail "compose mode with no --kind flag should still file a plain request"

log "status mode: corrections never appear — they are not errands awaiting anything"
STATUS_AFTER_CORRECTION="$("$MODAL" --mode status)"
echo "$STATUS_AFTER_CORRECTION" | grep -q "$CORRECTION_ID" && fail "status mode listed a correction record ($CORRECTION_ID) — corrections are not errands"
true

log "compose mode: an interactive session must hold the window open until dismissed (0009 review pass finding 5)"
log "  -- foot closes the instant this process exits, so the confirmation must not flash for zero frames; a real pty (stdlib 'pty') stands in for foot here, not a piped stdin"
if ! python3 - "$MODAL" "$CASTLE_STATE_DIR" "$XDG_RUNTIME_DIR" <<'PYEOF'
import os
import pty
import select
import subprocess
import sys
import time

modal, state_dir, runtime_dir = sys.argv[1], sys.argv[2], sys.argv[3]
env = dict(os.environ)
env["CASTLE_STATE_DIR"] = state_dir
env["XDG_RUNTIME_DIR"] = runtime_dir

main_fd, sub_fd = pty.openpty()
proc = subprocess.Popen(
    [modal, "--mode", "compose"],
    stdin=sub_fd, stdout=sub_fd, stderr=sub_fd,
    env=env, close_fds=True,
)
os.close(sub_fd)


def read_available(timeout=3.0):
    data = b""
    deadline = time.time() + timeout
    while time.time() < deadline:
        ready, _, _ = select.select([main_fd], [], [], 0.2)
        if main_fd in ready:
            try:
                chunk = os.read(main_fd, 4096)
            except OSError:
                break
            if not chunk:
                break
            data += chunk
        elif data:
            break
    return data


os.write(main_fd, b"Testing the pause-on-dismissal fix.\n.\n")
prompt_out = read_available()
if b"something to fix" not in prompt_out:
    print(f"FAIL: classification prompt did not appear before filing (0010): {prompt_out!r}", file=sys.stderr)
    sys.exit(1)

# Bare Enter answers the classification prompt (defaults to "something
# to fix" — docs/tasks/0010-correction-record.md scope 6), independent
# of the *second* Enter below that dismisses the window afterward.
os.write(main_fd, b"\n")
out = read_available()

if proc.poll() is not None:
    print("FAIL: castle-modal exited before it was dismissed with Enter", file=sys.stderr)
    sys.exit(1)
if b"Filed as" not in out:
    print(f"FAIL: no readable confirmation (with record id) before the pause: {out!r}", file=sys.stderr)
    sys.exit(1)
if b"Press Enter to close" not in out:
    print(f"FAIL: no dismissal prompt seen — window would close unattended: {out!r}", file=sys.stderr)
    sys.exit(1)

os.write(main_fd, b"\n")
try:
    returncode = proc.wait(timeout=5)
except subprocess.TimeoutExpired:
    proc.kill()
    print("FAIL: castle-modal did not exit after Enter was sent to dismiss it", file=sys.stderr)
    sys.exit(1)
if returncode != 0:
    print(f"FAIL: castle-modal exited {returncode} after dismissal, expected 0", file=sys.stderr)
    sys.exit(1)

print("OK: interactive compose mode held the window open until dismissed, then exited cleanly")
PYEOF
then
  fail "interactive dismissal-hold regression test failed (see output above)"
fi

log "compose mode: interactive classification, driven on a pty (docs/tasks/0010-correction-record.md scope 6)"
log "  -- after the '.' terminator, the plain-language prompt with both labels must appear; the feedback key files a correction, the fix key and bare Enter both file a request"
if ! python3 - "$MODAL" "$CASTLE_STATE_DIR" "$XDG_RUNTIME_DIR" <<'PYEOF'
import os
import pty
import select
import subprocess
import sys
import time

modal, state_dir, runtime_dir = sys.argv[1], sys.argv[2], sys.argv[3]
env = dict(os.environ)
env["CASTLE_STATE_DIR"] = state_dir
env["XDG_RUNTIME_DIR"] = runtime_dir


def read_until(main_fd, needle: bytes, timeout=5.0) -> bytes:
    # Waits for `needle` to show up in the accumulated output, rather
    # than stopping on the first quiet gap: a keypress is echoed by the
    # pty's own tty driver the instant it's typed, well before the
    # program has actually finished acting on it and printed anything
    # of its own, so a gap-based "nothing arrived for 200ms, must be
    # done" heuristic (fine for the single uninterrupted burst of output
    # the dismissal-hold test above reads) is exactly wrong here and
    # returns just the echoed keystroke.
    data = b""
    deadline = time.time() + timeout
    while time.time() < deadline:
        ready, _, _ = select.select([main_fd], [], [], 0.2)
        if main_fd in ready:
            try:
                chunk = os.read(main_fd, 4096)
            except OSError:
                break
            if not chunk:
                break
            data += chunk
            if needle in data:
                return data
    return data


def drive(body: bytes, keypress: bytes):
    main_fd, sub_fd = pty.openpty()
    proc = subprocess.Popen(
        [modal, "--mode", "compose"],
        stdin=sub_fd, stdout=sub_fd, stderr=sub_fd,
        env=env, close_fds=True,
    )
    os.close(sub_fd)
    os.write(main_fd, body + b"\n.\n")
    prompt = read_until(main_fd, b"telling you how you're doing")
    # A short pause between the last byte of the prompt reaching us and
    # sending the keypress: printing the prompt and switching the tty
    # into cbreak mode are two separate statements in castle-modal
    # (print, then tty.setcbreak()), so a keypress that lands in the
    # narrow gap between them is held by the kernel's still-canonical
    # line discipline until a newline arrives — which, for a bare
    # single-character keypress, never does, hanging the child forever.
    # This sleeps past that gap; it is not needed for correctness of
    # castle-modal itself, only for this test's ability to simulate a
    # keystroke landing at a precise instant no human types at.
    time.sleep(0.2)
    os.write(main_fd, keypress)
    after_key = read_until(main_fd, b"Filed as")
    os.write(main_fd, b"\n")  # dismiss
    try:
        rc = proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        rc = None
    return prompt, after_key, rc


def find_record_id(out: bytes) -> str:
    for line in out.decode(errors="replace").splitlines():
        line = line.strip()
        if not line or " " in line or "\t" in line:
            continue
        if "-request-" in line or "-correction-" in line:
            return line
    return ""


failures = []

prompt, after_key, rc = drive(b"Testing the feedback key.", b"t")
if b"something to fix" not in prompt or b"telling you how you're doing" not in prompt:
    failures.append(f"plain-language classification prompt missing a label: {prompt!r}")
if rc != 0:
    failures.append(f"castle-modal did not exit cleanly after the feedback key + dismissal (rc={rc})")
record_id = find_record_id(after_key)
if not record_id or "-correction-" not in record_id:
    failures.append(f"feedback key did not file a correction record: {after_key!r}")
else:
    record_path = os.path.join(state_dir, "journal", record_id + ".md")
    if not os.path.exists(record_path):
        failures.append(f"feedback key printed {record_id} but no such journal record exists")

prompt2, after_fix, rc2 = drive(b"Testing the fix key.", b"f")
if rc2 != 0:
    failures.append(f"castle-modal did not exit cleanly after the fix key + dismissal (rc={rc2})")
fix_id = find_record_id(after_fix)
if not fix_id or "-request-" not in fix_id:
    failures.append(f"fix key did not file a plain request: {after_fix!r}")

prompt3, after_enter, rc3 = drive(b"Testing bare Enter.", b"\n")
if rc3 != 0:
    failures.append(f"castle-modal did not exit cleanly after bare Enter + dismissal (rc={rc3})")
enter_id = find_record_id(after_enter)
if not enter_id or "-request-" not in enter_id:
    failures.append(f"bare Enter (the default) did not file a plain request: {after_enter!r}")

if failures:
    for f in failures:
        print(f"FAIL: {f}", file=sys.stderr)
    sys.exit(1)

print("OK: interactive classification — feedback key files a correction, fix key and bare Enter both file a request")
PYEOF
then
  fail "interactive classification regression test failed (see output above)"
fi

# ---------------------------------------------------------------------
# docs/tasks/0021-auto-dispatch.md §4: _errand_state now reads a
# result's `outcome` field and probes the live lease behind a `claim`.
# Every pre-existing assertion above stays exactly as it was — in
# particular "a result with no outcome field reads as done", which is
# every result written before that field existed and must keep reading
# that way forever in an append-only journal.
# ---------------------------------------------------------------------

# The four fixtures below are hand-written rather than produced by
# running a real worker: this file's subject is `_errand_state`'s
# reading of the field, and `castle record` has no --outcome flag (the
# field is written by the code paths that observe an outcome, never
# passed in by a caller). Planting a record directly is the same
# technique run.sh already uses for its malformed-propensity fixtures.
# $4 (optional) is the claim this result closes, and $5 (optional) an
# id timestamp for ordering. Both matter since docs/tasks/0021 made the
# ledger per turn: a result closes the claim it names, and "newest"
# is decided by id, so a fixture that wants to be the newest turn's
# account has to say so.
plant_result_with_outcome() {
  local request_id="$1" outcome="$2" suffix="$3" claim_id="${4:-}" stamp="${5:-20260101T000000Z}"
  local id="$stamp-result-$suffix"
  local refs="$request_id"
  [ -n "$claim_id" ] && refs="$request_id,$claim_id"
  cat > "$CASTLE_STATE_DIR/journal/$id.md" <<EOF
---
id: $id
type: result
provenance: requested
refs: $refs
seat: worker
created: 2026-01-01T00:00:00Z
outcome: $outcome
---

Planted fixture: a result carrying outcome: $outcome (docs/tasks/0021).
EOF
  echo "$id"
}

plant_claim() {
  local request_id="$1" suffix="$2" stamp="${3:-20260101T000000Z}"
  local id="$stamp-claim-$suffix"
  cat > "$CASTLE_STATE_DIR/journal/$id.md" <<EOF
---
id: $id
type: claim
provenance: requested
refs: $request_id
seat: worker
created: 2026-01-01T00:00:00Z
---

Planted fixture: a worker turn began here (docs/tasks/0021).
EOF
  echo "$id"
}

log "status mode: each outcome value produces its own label, and every failure label names the retry command (docs/tasks/0021 §4)"
REQ_COMPLETED="$("$CASTLE" ask "Outcome fixture: a completed errand.")"
REQ_FAILED="$("$CASTLE" ask "Outcome fixture: a failed errand.")"
REQ_TIMEOUT="$("$CASTLE" ask "Outcome fixture: a timed-out errand.")"
REQ_INTERRUPTED="$("$CASTLE" ask "Outcome fixture: an interrupted errand.")"
plant_result_with_outcome "$REQ_COMPLETED" completed 0c0001 >/dev/null
plant_result_with_outcome "$REQ_FAILED" failed 0c0002 >/dev/null
plant_result_with_outcome "$REQ_TIMEOUT" timeout 0c0003 >/dev/null
plant_result_with_outcome "$REQ_INTERRUPTED" interrupted 0c0004 >/dev/null
"$CASTLE" validate || fail "the planted outcome fixtures do not validate"

# --limit well above the default 10: this file has filed more errands
# than the status fold shows by default.
STATUS_OUTCOMES="$("$MODAL" --mode status --limit 40)"
echo "$STATUS_OUTCOMES" | grep -q "^\[$REQ_COMPLETED\] requested — done$" \
  || fail "outcome: completed did not render as 'done'"
echo "$STATUS_OUTCOMES" | grep -q "^\[$REQ_FAILED\] requested — failed — castle work $REQ_FAILED to retry$" \
  || fail "outcome: failed did not render a label naming the retry command"
echo "$STATUS_OUTCOMES" | grep -q "^\[$REQ_TIMEOUT\] requested — timed out — castle work $REQ_TIMEOUT to retry$" \
  || fail "outcome: timeout did not render a label naming the retry command"
echo "$STATUS_OUTCOMES" | grep -q "^\[$REQ_INTERRUPTED\] requested — interrupted — castle work $REQ_INTERRUPTED to retry$" \
  || fail "outcome: interrupted did not render a label naming the retry command"

log "status mode: a claim with a DEAD lease reads as interrupted, not 'in progress' — nothing is actually running"
REQ_CLAIMED="$("$CASTLE" ask "Claim fixture: a worker turn that began.")"
CLAIM_ID="$("$CASTLE" record --type claim --provenance requested --seat worker --refs "$REQ_CLAIMED" \
  --body "Planted claim: a turn began here.")"
[ -n "$CLAIM_ID" ] || fail "could not plant a claim record"
STATUS_DEAD_LEASE="$("$MODAL" --mode status --limit 40)"
echo "$STATUS_DEAD_LEASE" | grep -q "^\[$REQ_CLAIMED\] requested — interrupted — castle work $REQ_CLAIMED to retry$" \
  || fail "a claim with no live lease did not read as interrupted"

log "status mode: the same claim with a LIVE lease reads as 'in progress (started HH:MM)' — backed by a held flock, not by absence of evidence"
cat > "$WORKDIR/hold-lease.py" <<'PYEOF'
"""Hold a real flock on an errand's lease file, the way a running
`castle work` would, so the modal's live-lease probe has something
genuine to find. Deliberately does not import agent/castle: this is
the harness checking the tool from the outside, same reasoning
check_assertions.py's header gives."""
import fcntl
import pathlib
import sys
import time

runtime_dir, request_id, ready_path = sys.argv[1], sys.argv[2], sys.argv[3]
leases = pathlib.Path(runtime_dir) / "castle" / "leases"
leases.mkdir(parents=True, exist_ok=True)
handle = (leases / f"{request_id}.lock").open("a+")
fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
pathlib.Path(ready_path).write_text("held\n")
time.sleep(60)
PYEOF
python3 "$WORKDIR/hold-lease.py" "$XDG_RUNTIME_DIR" "$REQ_CLAIMED" "$WORKDIR/lease-held" &
LEASE_HOLDER=$!
for _ in $(seq 1 50); do
  [ -f "$WORKDIR/lease-held" ] && break
  sleep 0.2
done
[ -f "$WORKDIR/lease-held" ] || fail "the lease-holder helper never took the lock"
STATUS_LIVE_LEASE="$("$MODAL" --mode status --limit 40)"
echo "$STATUS_LIVE_LEASE" | grep -qE "^\[$REQ_CLAIMED\] requested — in progress \(started [0-9]{2}:[0-9]{2}\)$" \
  || fail "a claim with a live lease did not read as 'in progress (started HH:MM)': $(echo "$STATUS_LIVE_LEASE" | grep "$REQ_CLAIMED" || true)"
kill "$LEASE_HOLDER" 2>/dev/null || true
wait "$LEASE_HOLDER" 2>/dev/null || true

log "status mode: once the lease dies with its holder, the same errand reads as interrupted again"
STATUS_AFTER_LEASE="$("$MODAL" --mode status --limit 40)"
echo "$STATUS_AFTER_LEASE" | grep -q "^\[$REQ_CLAIMED\] requested — interrupted — castle work $REQ_CLAIMED to retry$" \
  || fail "the errand still claimed to be in progress after its lease holder died"

log "status mode: a live turn outranks an existing result — a failed errand being retried right now reads as 'in progress', not as advice to retry it"
# The label this ordering exists for. Under results-win-outright, an
# errand whose failed turn the resident was retrying at that very
# moment rendered "failed — castle work <id> to retry": advice to run a
# command that was already running, and that would be refused the lease
# if the resident took it.
# Closing $CLAIM_ID specifically: since the ledger is per turn, a
# result that named only the request would leave this errand's newest
# claim unclosed, and the honest label for that is "interrupted", not
# "failed" — which is a different assertion than the one this section
# is making.
plant_result_with_outcome "$REQ_CLAIMED" failed 0c0005 "$CLAIM_ID" >/dev/null
STATUS_FAILED_CLAIM="$("$MODAL" --mode status --limit 40)"
echo "$STATUS_FAILED_CLAIM" | grep -q "^\[$REQ_CLAIMED\] requested — failed — castle work $REQ_CLAIMED to retry$" \
  || fail "with a failed result and no live lease, the errand should read as failed"
python3 "$WORKDIR/hold-lease.py" "$XDG_RUNTIME_DIR" "$REQ_CLAIMED" "$WORKDIR/lease-held-2" &
LEASE_HOLDER_2=$!
for _ in $(seq 1 50); do
  [ -f "$WORKDIR/lease-held-2" ] && break
  sleep 0.2
done
[ -f "$WORKDIR/lease-held-2" ] || fail "the lease-holder helper never took the lock for the retry case"
STATUS_LIVE_RETRY="$("$MODAL" --mode status --limit 40)"
echo "$STATUS_LIVE_RETRY" | grep -qE "^\[$REQ_CLAIMED\] requested — in progress \(started [0-9]{2}:[0-9]{2}\)$" \
  || fail "a live turn on an errand that already has a failed result did not read as 'in progress': $(echo "$STATUS_LIVE_RETRY" | grep "$REQ_CLAIMED" || true)"
kill "$LEASE_HOLDER_2" 2>/dev/null || true
wait "$LEASE_HOLDER_2" 2>/dev/null || true

log "status mode: the errand's state is its NEWEST turn's state, not its newest result's (docs/tasks/0021 §4)"
# Scenario (a), verified as a real misreport before the fix: an errand
# whose retry completed, and whose older abandoned turn was reaped
# afterwards, carries an `interrupted` result NEWER than its
# `completed` one — because the reaper wrote it later. Keyed on the
# newest result it read as interrupted forever, though it was finished.
REQ_TWO_TURNS="$("$CASTLE" ask "Two turns: an old one reaped after a newer one completed.")"
CLAIM_A="$(plant_claim "$REQ_TWO_TURNS" 0a0001 20260101T000100Z)"
CLAIM_B="$(plant_claim "$REQ_TWO_TURNS" 0a0002 20260101T000200Z)"
plant_result_with_outcome "$REQ_TWO_TURNS" completed 0a0003 "$CLAIM_B" 20260101T000300Z >/dev/null
# The reaper's account of the OLDER turn, written last of all.
plant_result_with_outcome "$REQ_TWO_TURNS" interrupted 0a0004 "$CLAIM_A" 20260101T000400Z >/dev/null
"$CASTLE" validate || fail "the two-turn fixtures do not validate"
STATUS_TWO_TURNS="$("$MODAL" --mode status --limit 40)"
echo "$STATUS_TWO_TURNS" | grep -q "^\[$REQ_TWO_TURNS\] requested — done$" \
  || fail "an errand whose newest turn completed reads as something else because an older turn was reaped later: $(echo "$STATUS_TWO_TURNS" | grep "$REQ_TWO_TURNS" || true)"

log "status mode: and an open newest turn is not masked by an older turn's result"
# Scenario (b), the same bug from the other side: a second turn that
# died leaves a claim no result closes, and an older result hid it
# entirely.
REQ_OPEN_TURN="$("$CASTLE" ask "Two turns: the newer one died and nothing closed it.")"
CLAIM_C="$(plant_claim "$REQ_OPEN_TURN" 0b0001 20260101T000100Z)"
plant_result_with_outcome "$REQ_OPEN_TURN" completed 0b0002 "$CLAIM_C" 20260101T000200Z >/dev/null
plant_claim "$REQ_OPEN_TURN" 0b0003 20260101T000300Z >/dev/null
"$CASTLE" validate || fail "the open-turn fixtures do not validate"
STATUS_OPEN_TURN="$("$MODAL" --mode status --limit 40)"
echo "$STATUS_OPEN_TURN" | grep -q "^\[$REQ_OPEN_TURN\] requested — interrupted — castle work $REQ_OPEN_TURN to retry$" \
  || fail "an unclosed newest turn was masked by an older turn's result: $(echo "$STATUS_OPEN_TURN" | grep "$REQ_OPEN_TURN" || true)"

log "status mode: a request a tenant filed during its own turn says so, instead of promising a worker that is never coming"
# docs/tasks/0021 §2.4(e): dispatch deliberately never starts these, so
# "awaiting a worker" would be 0015's exact failure — a label promising
# a start that will not happen. Filed through the real mechanism (the
# tenant's inherited CASTLE_WORKER_CLAIM), not by hand-editing a record.
REQ_STAMPED="$(CASTLE_WORKER_CLAIM="$CLAIM_A" "$CASTLE" ask "Filed by a tenant mid-turn: should not claim to be awaiting a worker.")"
grep -q "^filed-during-turn: $CLAIM_A\$" "$CASTLE_STATE_DIR/journal/$REQ_STAMPED.md" \
  || fail "$REQ_STAMPED carries no filed-during-turn stamp — the fixture is not exercising what it claims to"
STATUS_STAMPED="$("$MODAL" --mode status --limit 40)"
echo "$STATUS_STAMPED" | grep -q "^\[$REQ_STAMPED\] requested — filed during a worker turn — castle work $REQ_STAMPED to run it$" \
  || fail "a tenant-filed request did not say so: $(echo "$STATUS_STAMPED" | grep "$REQ_STAMPED" || true)"
echo "$STATUS_STAMPED" | grep -q "^\[$REQ_STAMPED\] requested — awaiting a worker$" \
  && fail "a tenant-filed request still claims to be awaiting a worker — nothing will ever start it automatically"
"$CASTLE" validate || fail "the journal does not validate after the tenant-filed request fixture"

log "status mode: an unanswered question still overlays every one of these states unchanged"
"$CASTLE" record --type question --provenance requested --seat worker --refs "$REQ_FAILED" \
  --body "Should I try a different approach?" >/dev/null
STATUS_OVERLAY="$("$MODAL" --mode status --limit 40)"
echo "$STATUS_OVERLAY" | grep -q "^\[$REQ_FAILED\] requested — failed — castle work $REQ_FAILED to retry, waiting on you$" \
  || fail "the ', waiting on you' overlay did not compose with an outcome label"
"$CASTLE" validate || fail "the journal did not validate after the outcome/claim fixtures"

log "all assertions passed"
