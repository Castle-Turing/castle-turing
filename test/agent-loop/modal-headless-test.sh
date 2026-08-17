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

log "all assertions passed"
