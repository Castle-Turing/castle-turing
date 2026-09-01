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
PTY_DRIVE="$REPO_ROOT/test/agent-loop/pty-drive.py"

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
# reading of the field, not any particular writer of it. `castle
# record` does take --outcome (this same file exercises it further
# down, for the human-worker-seat case) — the field is optional and
# validated when present — but planting the record directly pins the
# exact bytes each state is read from, which is the same technique
# run.sh already uses for its malformed-propensity fixtures.
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

log "status mode: an outcome value this version does not know renders verbatim, never as 'done'"
# `outcome` is a named cross-task contract (0026/0027 reuse it), so a
# value from a later task, a hand-written record, or a typo will reach
# this surface eventually. Reporting it as success because it was not
# recognised is precisely the prose-vs-field failure the field exists
# to end. Planted directly and removed again, the same pattern
# run.sh's malformed-propensity fixtures use: `castle validate`
# rejects unknown outcomes on purpose, so the record cannot be left
# lying in the journal.
REQ_UNKNOWN_OUTCOME="$("$CASTLE" ask "An outcome from a vocabulary this version has never heard of.")"
UNKNOWN_RESULT="$CASTLE_STATE_DIR/journal/20260101T000500Z-result-0e0001.md"
cat > "$UNKNOWN_RESULT" <<EOF
---
id: 20260101T000500Z-result-0e0001
type: result
provenance: requested
refs: $REQ_UNKNOWN_OUTCOME
seat: worker
created: 2026-01-01T00:05:00Z
outcome: cancelled
---

Planted fixture: an outcome value outside this version's vocabulary.
EOF
STATUS_UNKNOWN="$("$MODAL" --mode status --limit 40)"
echo "$STATUS_UNKNOWN" | grep -q "^\[$REQ_UNKNOWN_OUTCOME\] requested — cancelled — castle work $REQ_UNKNOWN_OUTCOME to retry$" \
  || fail "an unrecognised outcome did not render verbatim with a retry hint: $(echo "$STATUS_UNKNOWN" | grep "$REQ_UNKNOWN_OUTCOME" || true)"
echo "$STATUS_UNKNOWN" | grep -q "^\[$REQ_UNKNOWN_OUTCOME\] requested — done$" \
  && fail "an unrecognised outcome was reported as done — success by default on a field that exists to prevent exactly that"
rm -f "$UNKNOWN_RESULT"
"$CASTLE" validate || fail "the journal did not validate clean once the unknown-outcome fixture was removed"

log "castle record --outcome: a human holding the worker seat can state the fact, and the surface reads it"
REQ_HANDFAIL="$("$CASTLE" ask "A failed errand a human recorded by hand.")"
"$CASTLE" record --type result --provenance requested --seat worker --refs "$REQ_HANDFAIL" \
  --outcome failed --body "Tried it by hand; it did not work." >/dev/null
STATUS_HANDFAIL="$("$MODAL" --mode status --limit 40)"
echo "$STATUS_HANDFAIL" | grep -q "^\[$REQ_HANDFAIL\] requested — failed — castle work $REQ_HANDFAIL to retry$" \
  || fail "a hand-written result with --outcome failed did not read as failed: $(echo "$STATUS_HANDFAIL" | grep "$REQ_HANDFAIL" || true)"
"$CASTLE" validate || fail "a hand-written result carrying --outcome does not validate"

log "status mode: a claim closed by a HAND-WRITTEN result (no claim id in its refs) reads by that result, not as interrupted"
# The human-seat-holder shape: `castle work` crashed, the resident
# finished the errand with `castle record --type result --refs R` — the
# spelling the CLI implies — and the status surface used to mask that
# closure behind "interrupted" forever, while the next sweep prepared
# to contradict it in the journal. Same two-clause rule as the reaper,
# from the same function.
REQ_HAND_CLOSED="$("$CASTLE" ask "A crashed turn the resident closed by hand.")"
plant_claim "$REQ_HAND_CLOSED" 0d0001 20260101T000100Z >/dev/null
# Request-only refs, newer id: exactly what `castle record` writes.
plant_result_with_outcome "$REQ_HAND_CLOSED" completed 0d0002 "" 20260101T000200Z >/dev/null
"$CASTLE" validate || fail "the hand-closure fixtures do not validate"
STATUS_HAND_CLOSED="$("$MODAL" --mode status --limit 40)"
echo "$STATUS_HAND_CLOSED" | grep -q "^\[$REQ_HAND_CLOSED\] requested — done$" \
  || fail "an errand a resident closed by hand still reads as unfinished: $(echo "$STATUS_HAND_CLOSED" | grep "$REQ_HAND_CLOSED" || true)"

log "status mode: a request the watermark excluded says so, instead of waiting for a worker that will never come"
# The watermark names its excluded requests in its own refs, so the
# explanation is already in this errand's downstream fold — and
# "awaiting a worker" on an errand automatic dispatch has permanently
# declined to touch is 0015's failure exactly.
REQ_PREDATES="$("$CASTLE" ask "Filed before dispatch existed on this journal.")"
# A SECOND outstanding request, named after the first in the same
# watermark. A real watermark names every request outstanding when
# dispatch began, so all but one of them sit past `refs[0]` — and the
# errand fold that finds this record has to reach it from each of them,
# not only from the first. With one excluded request the two cases are
# indistinguishable, which is how this stayed untested until
# docs/tasks/0023 keyed that fold to the lineage edge and had to carve
# out "or names this errand directly" to keep it working.
REQ_PREDATES_2="$("$CASTLE" ask "Also filed before dispatch existed, and named second.")"
WATERMARK_FIXTURE="$CASTLE_STATE_DIR/journal/20260101T000600Z-decision-0f0001.md"
cat > "$WATERMARK_FIXTURE" <<EOF
---
id: 20260101T000600Z-decision-0f0001
type: decision
provenance: initiated
refs: $REQ_PREDATES,$REQ_PREDATES_2
seat: dispatch
created: 2026-01-01T00:06:00Z
evidence: planted watermark fixture: dispatch began after this request was filed
watermark: 2026-01-01T00:06:00Z
---

Planted fixture: the dispatch watermark, naming $REQ_PREDATES and $REQ_PREDATES_2 as excluded.
EOF
"$CASTLE" validate || fail "the planted watermark fixture does not validate"
STATUS_PREDATES="$("$MODAL" --mode status --limit 40)"
echo "$STATUS_PREDATES" | grep -q "^\[$REQ_PREDATES\] requested — not started automatically (predates dispatch) — castle work $REQ_PREDATES to run it$" \
  || fail "a watermark-excluded request did not say so: $(echo "$STATUS_PREDATES" | grep "$REQ_PREDATES" || true)"
echo "$STATUS_PREDATES" | grep -q "^\[$REQ_PREDATES\] requested — awaiting a worker$" \
  && fail "a watermark-excluded request still claims to be awaiting a worker — nothing will ever start it automatically"
# The watermark is a decision with no channel, and the fold renders it
# as a note rather than inventing a routing that never happened.
echo "$STATUS_PREDATES" | grep -A2 "^\[$REQ_PREDATES\]" | grep -q "noted: planted watermark fixture" \
  || fail "the channel-less watermark decision did not render as a note under the errand it excluded"
# And the same for the request named SECOND in that watermark's refs,
# which is the case a lineage-edge-only fold would lose.
echo "$STATUS_PREDATES" | grep -q "^\[$REQ_PREDATES_2\] requested — not started automatically (predates dispatch) — castle work $REQ_PREDATES_2 to run it$" \
  || fail "the request named second in the watermark's refs did not say it predates dispatch: $(echo "$STATUS_PREDATES" | grep "$REQ_PREDATES_2" || true)"
echo "$STATUS_PREDATES" | grep -q "^\[$REQ_PREDATES_2\] requested — awaiting a worker$" \
  && fail "the second watermark-excluded request claims to be awaiting a worker — nothing will ever start it"

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
echo "$STATUS_OVERLAY" | grep -q "^\[$REQ_FAILED\] requested — failed — castle work $REQ_FAILED to retry, waiting on you — press Mod4+Shift+Return to answer$" \
  || fail "the ', waiting on you — press Mod4+Shift+Return to answer' overlay did not compose with an outcome label"
"$CASTLE" validate || fail "the journal did not validate after the outcome/claim fixtures"

# ---------------------------------------------------------------------
log "status mode: a follow-up errand's turns never label the errand it was filed against"
# ---------------------------------------------------------------------
# `castle ask --refs R1` is the documented way to file a follow-up, and
# `_collect_downstream` is transitive over refs with no keying by
# errand — so R2, and everything hanging off R2, lands in R1's fold.
# Deriving R1's turn state from that fold read R2's abandoned turn as
# R1's own: a finished errand labelled "interrupted — castle work R1 to
# retry", about a turn R1 never had. The fold stays transitive (a
# question raised anywhere on the chain is still the resident's to
# answer); what is keyed to the request is the turn state.
REQ_PARENT="$("$CASTLE" ask "Parent errand: finishes cleanly, must not inherit a follow-up's state.")"
CLAIM_PARENT="$(plant_claim "$REQ_PARENT" 0e0001 20260101T000700Z)"
plant_result_with_outcome "$REQ_PARENT" completed 0e0002 "$CLAIM_PARENT" 20260101T000701Z >/dev/null
REQ_FOLLOW="$("$CASTLE" ask --refs "$REQ_PARENT" "Follow-up errand: its own turn dies, and stays its own.")"
plant_claim "$REQ_FOLLOW" 0e0003 20260101T000800Z >/dev/null
"$CASTLE" validate || fail "the follow-up fixture does not validate"
STATUS_FOLLOW="$("$MODAL" --mode status --limit 40)"
echo "$STATUS_FOLLOW" | grep -q "^\[$REQ_PARENT\] requested — done$" \
  || fail "the parent errand took its state from a follow-up's turn: $(echo "$STATUS_FOLLOW" | grep "$REQ_PARENT" || true)"
echo "$STATUS_FOLLOW" | grep -q "^\[$REQ_FOLLOW\] requested — interrupted — castle work $REQ_FOLLOW to retry$" \
  || fail "the follow-up errand did not report its own dead turn: $(echo "$STATUS_FOLLOW" | grep "$REQ_FOLLOW" || true)"

# ---------------------------------------------------------------------
log "status mode: answering one question does not silence the next one"
# ---------------------------------------------------------------------
# The overlay used to be "there is a question and there is no answer",
# which never paired the two: the first answer on an errand made every
# later question invisible, on the one surface whose whole job is to
# say when a worker is blocked on the resident.
REQ_TWOQ="$("$CASTLE" ask "An errand whose worker asks twice.")"
Q_FIRST="$("$CASTLE" record --type question --provenance requested --seat worker \
  --refs "$REQ_TWOQ" --body "First question?")"
STATUS_Q1="$("$MODAL" --mode status --limit 40)"
echo "$STATUS_Q1" | grep -q "^\[$REQ_TWOQ\] requested — waiting on you — press Mod4+Shift+Return to answer$" \
  || fail "an unanswered question did not raise the overlay: $(echo "$STATUS_Q1" | grep "$REQ_TWOQ" || true)"
"$CASTLE" answer "$Q_FIRST" "Yes, go ahead." >/dev/null
STATUS_Q1A="$("$MODAL" --mode status --limit 40)"
echo "$STATUS_Q1A" | grep -q "^\[$REQ_TWOQ\] requested — waiting on you — press Mod4+Shift+Return to answer$" \
  && fail "an answered question still reads as waiting on the resident"
"$CASTLE" record --type question --provenance requested --seat worker \
  --refs "$REQ_TWOQ" --body "Second question, after the first was answered?" >/dev/null
STATUS_Q2="$("$MODAL" --mode status --limit 40)"
echo "$STATUS_Q2" | grep -q "^\[$REQ_TWOQ\] requested — waiting on you — press Mod4+Shift+Return to answer$" \
  || fail "a SECOND question went unnoticed because an earlier one had been answered — the overlay is not pairing answers with questions"
"$CASTLE" validate || fail "the journal does not validate after the two-question fixture"


# ---------------------------------------------------------------------
# docs/tasks/0022-answer-in-ui.md — answer mode.
# ---------------------------------------------------------------------
#
# A fresh state dir for this whole section, and every question below
# planted with an explicit id. Both are about determinism, not tidiness:
# the picker is a screen-relative, oldest-first list of every pending
# question in the journal, so asserting "[1] is the one I just filed"
# against the journal the sections above accumulated would be asserting
# on this file's own history instead. And record ids are timestamp-
# prefixed to one-second granularity — two questions filed in the same
# second sort by their random suffix, which is exactly the coin flip a
# test about "press 2 and get the second one" must not contain.
#
# For the same reason each test below leaves the fold empty when it is
# done: a question deliberately left pending by one test is a silent
# off-by-one in the next one's picker indices.
export CASTLE_STATE_DIR="$WORKDIR/answer-state"
export XDG_RUNTIME_DIR="$WORKDIR/answer-runtime"
mkdir -p "$CASTLE_STATE_DIR/journal" "$XDG_RUNTIME_DIR"

# $3 is the body, $4 an optional `fact` name. The id's suffix is derived
# from the stamp rather than random, so a failing assertion names a
# fixture a reader can find.
plant_question() {
  local request_id="$1" stamp="$2" body="$3" fact="${4:-}"
  local id="$stamp-question-q$(printf '%s' "$stamp" | tail -c 7)"
  {
    echo "---"
    echo "id: $id"
    echo "type: question"
    echo "provenance: requested"
    echo "refs: $request_id"
    echo "seat: worker"
    echo "created: 2026-02-01T00:00:00Z"
    [ -n "$fact" ] && echo "fact: $fact"
    echo "---"
    echo
    echo "$body"
  } > "$CASTLE_STATE_DIR/journal/$id.md"
  echo "$id"
}

journal_file_count() { find "$CASTLE_STATE_DIR/journal" -name '*.md' | wc -l | tr -d ' '; }
model_byte_count() {
  if [ -f "$CASTLE_STATE_DIR/resident-model.md" ]; then
    wc -c < "$CASTLE_STATE_DIR/resident-model.md" | tr -d ' '
  else
    echo 0
  fi
}
answers_naming() { grep -l "^refs: $1\$" "$CASTLE_STATE_DIR"/journal/*-answer-*.md 2>/dev/null || true; }

# One reusable pty driver for every interactive assertion below, rather
# than a fresh inline PYEOF block per test. It lives in its own file —
# test/agent-loop/pty-drive.py — since docs/tasks/0025-approval.md gave
# it a second caller (approval.sh drives review mode the same way): two
# copies of a pty driver would be two places for a timing subtlety to
# be fixed once, and every subtlety in it was found the hard way. See
# that file's header for the step vocabulary.

drive_modal() {
  # Usage: drive_modal <transcript-path> <modal-arg>... -- <step>...
  local transcript="$1"; shift
  python3 "$PTY_DRIVE" "$MODAL" "$@" > "$transcript" || {
    cat "$transcript" >&2
    fail "pty driver failed (see the transcript above)"
  }
}
transcript_rc() { sed -n 's/^RC=//p' "$1"; }
refute() {
  # `grep -q X && fail` is safe at top level under `set -e` (the failing
  # grep is not the last command of the && list) but NOT as the last
  # statement of a loop body or function, where the compound's own
  # nonzero status becomes the loop's and trips the errexit. This says
  # the same thing in a form that is safe everywhere.
  local haystack="$1" needle="$2" message="$3"
  if printf '%s' "$haystack" | grep -qi -- "$needle"; then
    fail "$message"
  fi
}

log "status and the picker agree about one answered question, even when the answer names two errands"
# docs/tasks/0015 scope 3, in the shape docs/tasks/0023's narrowed
# errand walk could have produced: an answer written through the
# generic door as `--refs Q_A,Q_B` belongs to A's fold and not B's, so
# a "waiting on you" overlay derived from that walk would nag about
# Q_B forever while the picker — which folds every answer record flat
# — correctly declines to offer it. Telling the resident to answer
# something the answer surface will not show them is worse than either
# surface being wrong alone, so all three folds (this overlay,
# `_pending_questions`, and `file_answer`'s duplicate guard) read
# answeredness the same way.
REQ_SHARED_A="$("$CASTLE" ask "Shared-answer errand A: an invented request.")"
REQ_SHARED_B="$("$CASTLE" ask "Shared-answer errand B: another invented request.")"
Q_SHARED_A="$(plant_question "$REQ_SHARED_A" 20260201T000010Z "Errand A's question, answered jointly.")"
Q_SHARED_B="$(plant_question "$REQ_SHARED_B" 20260201T000011Z "Errand B's question, answered jointly.")"
"$CASTLE" record --type answer --provenance requested --seat intake \
  --refs "$Q_SHARED_A,$Q_SHARED_B" \
  --body "One answer closing both errands' questions." >/dev/null
"$CASTLE" validate >/dev/null || fail "the shared-answer fixture does not validate"

STATUS_SHARED="$("$MODAL" --mode status --limit 40)"
echo "$STATUS_SHARED" | grep "^\[$REQ_SHARED_B\]" | grep -q "waiting on you" \
  && fail "errand B says 'waiting on you' for a question that IS answered: $(echo "$STATUS_SHARED" | grep "^\[$REQ_SHARED_B\]")"
echo "$STATUS_SHARED" | grep "^\[$REQ_SHARED_A\]" | grep -q "waiting on you" \
  && fail "errand A says 'waiting on you' for a question that IS answered: $(echo "$STATUS_SHARED" | grep "^\[$REQ_SHARED_A\]")"
# And the picker agrees: neither question is offered, which is the half
# that was already right and that the overlay now matches.
PICKER_SHARED="$("$MODAL" --mode answer </dev/null)"
echo "$PICKER_SHARED" | grep -q "$Q_SHARED_B" \
  && fail "the picker offered an answered question"
echo "$PICKER_SHARED" | grep -q "Errand B's question" \
  && fail "the picker offered an answered question by its text"

log "answer mode: nothing pending prints a friendly line and exits 0 (test 1)"
ANSWER_NONE_OUT="$("$MODAL" --mode answer </dev/null)" || fail "answer mode with nothing pending should exit 0"
echo "$ANSWER_NONE_OUT" | grep -q "Nothing is waiting on you." \
  || fail "answer mode with an empty fold did not print the friendly line: $ANSWER_NONE_OUT"

log "answer mode: one question, picked and answered on a pty (tests 2 and 4)"
REQ_ANS_1="$("$CASTLE" ask "Answer-mode errand one: the pointer is hard to follow.")"
Q_ANS_1="$(plant_question "$REQ_ANS_1" 20260201T000100Z \
  "Cap the pointer speed, or leave it alone?
Second line of the question, which the picker's preview does not show.")"
"$CASTLE" validate || fail "the planted question fixture does not validate"
drive_modal "$WORKDIR/answer-1.txt" --mode answer -- \
  "wait:any other key to close" "key:1" "wait:End with a line containing just" \
  "send:Cap it.\n.\n" "wait:Press Enter to close" "send:\n"
ANSWER_1_OUT="$(cat "$WORKDIR/answer-1.txt")"
echo "$ANSWER_1_OUT"
[ "$(transcript_rc "$WORKDIR/answer-1.txt")" = "0" ] || fail "answer mode did not exit 0 after filing an answer"
echo "$ANSWER_1_OUT" | grep -q "\[1\] Cap the pointer speed, or leave it alone?" \
  || fail "the picker did not show the pending question as entry [1]"
echo "$ANSWER_1_OUT" | grep -q "about: Answer-mode errand one: the pointer is hard to follow." \
  || fail "the picker did not show an 'about:' line sourced from the root request"
echo "$ANSWER_1_OUT" | grep -q "Second line of the question" \
  || fail "the selected question's body was truncated — the full text must be shown before answering"
# A bare "Filed.", with no second sentence: docs/tasks/0023 deleted the
# "Nothing picks this errand back up automatically yet." half, because an
# answered *blocking* question now resumes its errand. Asserted as a whole
# line (grep -x on the stripped output would need the trailing prompt text
# too, so this checks the sentence and then that nothing follows it) —
# the point is that no replacement promise crept in: the modal cannot know
# whether dispatch is running, so it must not claim a continuation.
# `tr -d '\r'` because this transcript came off a pty, which translates
# every newline to CRLF — without it an anchored whole-line match can
# never succeed here, for a reason that has nothing to do with the text.
printf '%s\n' "$ANSWER_1_OUT" | tr -d '\r' | grep -qx "Filed." \
  || fail "the confirmation is not a bare 'Filed.': $ANSWER_1_OUT"
echo "$ANSWER_1_OUT" | grep -q "picks this errand back up" \
  && fail "the confirmation still claims nothing resumes the errand — 0023 made that false"
echo "$ANSWER_1_OUT" | grep -q "Press Enter to close" \
  || fail "answer mode did not hold the window open until dismissed"
ANSWER_1_FILE="$(answers_naming "$Q_ANS_1" | head -1)"
[ -n "$ANSWER_1_FILE" ] || fail "no answer record naming $Q_ANS_1 was written"
grep -q "^refs: $Q_ANS_1\$" "$ANSWER_1_FILE" || fail "$ANSWER_1_FILE's refs is not exactly the question it closes"
grep -q "^seat: intake\$" "$ANSWER_1_FILE" || fail "$ANSWER_1_FILE should carry seat=intake, like every other intake write"
grep -q "Cap it." "$ANSWER_1_FILE" || fail "$ANSWER_1_FILE did not capture the typed answer body"
[ ! -f "$CASTLE_STATE_DIR/resident-model.md" ] \
  || fail "answering a question that carries no 'fact' field wrote a resident-model entry anyway"

# Test 4, the positive assertion: every id involved is absent from what
# the resident actually saw, and so is the journal's own vocabulary.
ANSWER_1_ID="$(basename "$ANSWER_1_FILE" .md)"
for LEAKED in "$Q_ANS_1" "$REQ_ANS_1" "$ANSWER_1_ID"; do
  refute "$ANSWER_1_OUT" "$LEAKED" "answer mode printed the record id $LEAKED — no internal identifier may reach this surface"
done
for LEAKED in seat provenance refs journal record channel evidence; do
  refute "$ANSWER_1_OUT" "$LEAKED" "answer mode printed the internal word '$LEAKED' — this surface speaks plain language only"
done

log "answer mode: with two pending, pressing 2 answers the SECOND and leaves the first pending (test 3)"
REQ_ANS_2="$("$CASTLE" ask "Answer-mode errand two: the fan runs loud after suspend.")"
REQ_ANS_3="$("$CASTLE" ask "Answer-mode errand three: the display wakes dim.")"
Q_ANS_2="$(plant_question "$REQ_ANS_2" 20260201T000200Z "Cap the fan curve, or leave it?")"
Q_ANS_3="$(plant_question "$REQ_ANS_3" 20260201T000300Z "Raise the wake brightness, or leave it?")"
"$CASTLE" validate || fail "the two-question fixtures do not validate"
drive_modal "$WORKDIR/answer-2.txt" --mode answer -- \
  "wait:any other key to close" "key:2" "wait:End with a line containing just" \
  "send:Raise it.\n.\n" "wait:Press Enter to close" "send:\n"
ANSWER_2_OUT="$(cat "$WORKDIR/answer-2.txt")"
[ "$(transcript_rc "$WORKDIR/answer-2.txt")" = "0" ] || fail "answer mode did not exit 0 after answering the second question"
echo "$ANSWER_2_OUT" | grep -q "\[1\] Cap the fan curve, or leave it?" \
  || fail "oldest-first ordering broke: the older question is not entry [1]"
echo "$ANSWER_2_OUT" | grep -q "\[2\] Raise the wake brightness, or leave it?" \
  || fail "the newer question is not entry [2]"
[ -n "$(answers_naming "$Q_ANS_3")" ] || fail "pressing 2 did not answer the second question"
[ -z "$(answers_naming "$Q_ANS_2")" ] \
  || fail "pressing 2 answered the FIRST question as well — the picker index selected the wrong record"

log "answer mode: reopening it afterwards offers only the question that is still pending"
drive_modal "$WORKDIR/answer-3.txt" --mode answer -- \
  "wait:any other key to close" "key:q"
ANSWER_3_OUT="$(cat "$WORKDIR/answer-3.txt")"
echo "$ANSWER_3_OUT" | grep -q "\[1\] Cap the fan curve, or leave it?" \
  || fail "the still-pending question is not offered on a second opening"
refute "$ANSWER_3_OUT" "^  \[2\]" "an already-answered question is still being offered"

log "answer mode: dismissal writes nothing at all, anywhere (test 5)"
FILES_BEFORE="$(journal_file_count)"
MODEL_BEFORE="$(model_byte_count)"
drive_modal "$WORKDIR/answer-dismiss.txt" --mode answer -- \
  "wait:any other key to close" "key:x"
[ "$(transcript_rc "$WORKDIR/answer-dismiss.txt")" = "0" ] \
  || fail "dismissing the picker did not exit 0 — looking and declining is a successful use of this surface, not a failure"
refute "$(cat "$WORKDIR/answer-dismiss.txt")" "Press Enter to close" \
  "dismissal asked for a second keypress to confirm — the keypress IS the dismissal"
[ "$(journal_file_count)" = "$FILES_BEFORE" ] || fail "dismissing the picker wrote a journal record"
[ "$(model_byte_count)" = "$MODEL_BEFORE" ] || fail "dismissing the picker wrote to the resident model"
"$CASTLE" validate || fail "the journal does not validate after a dismissal"

log "answer mode: an empty answer body is refused, and nothing is filed (test 6)"
FILES_BEFORE="$(journal_file_count)"
drive_modal "$WORKDIR/answer-empty.txt" --mode answer -- \
  "wait:any other key to close" "key:1" "wait:End with a line containing just" \
  "send:.\n" "wait:Press Enter to close" "send:\n"
[ "$(transcript_rc "$WORKDIR/answer-empty.txt")" = "1" ] || fail "an empty answer did not exit 1"
grep -q "empty answer, nothing filed" "$WORKDIR/answer-empty.txt" \
  || fail "the empty-answer refusal did not use compose mode's existing 'nothing filed' vocabulary"
[ "$(journal_file_count)" = "$FILES_BEFORE" ] || fail "an empty answer wrote a record anyway"

# Everything above deliberately left one question pending — the second
# opening, the dismissal and the empty answer all need a non-empty fold
# to exercise anything. Clear it here so every test below starts from a
# fold it fully controls, and its picker indices mean what they say.
printf 'Answered, so the tests below start from a fold they control.\n.\n' \
  | "$MODAL" --mode answer --question "$Q_ANS_2" >/dev/null

log "answer mode: --question is the script path, and every refusal on it exits 1 without writing (test 7)"
REQ_ANS_4="$("$CASTLE" ask "Answer-mode errand four: the lock screen takes a moment.")"
Q_ANS_4="$(plant_question "$REQ_ANS_4" 20260201T000400Z "Shorten the lock delay, or leave it?")"
"$CASTLE" validate || fail "the script-path question fixture does not validate"
# With something pending and no --question, a script gets a refusal
# rather than a guess: choosing for a caller with no human present is
# the silent wrong-record path this flag exists to avoid.
FILES_BEFORE="$(journal_file_count)"
if printf 'Which one?\n.\n' | "$MODAL" --mode answer 2>"$WORKDIR/answer-noflag-err"; then
  fail "a piped session with pending questions and no --question guessed one instead of refusing"
fi
grep -q "no terminal" "$WORKDIR/answer-noflag-err" \
  || fail "the piped-without---question refusal did not explain itself: $(cat "$WORKDIR/answer-noflag-err")"
[ "$(journal_file_count)" = "$FILES_BEFORE" ] || fail "the piped-without---question refusal wrote a record anyway"

SCRIPTED_ANSWER_ID="$(printf 'Shorten it.\n.\n' | "$MODAL" --mode answer --question "$Q_ANS_4")"
[ -n "$SCRIPTED_ANSWER_ID" ] || fail "--question printed no answer id on stdout"
[ -f "$CASTLE_STATE_DIR/journal/$SCRIPTED_ANSWER_ID.md" ] \
  || fail "--question printed $SCRIPTED_ANSWER_ID but no such record exists"

# The fold is empty now, and that must change none of the above
# (review round 1, finding 2). The empty-fold short-circuit used to run
# first for every caller, which turned each documented --question
# refusal into exit 0 with prose on stdout — precisely where a script
# is most likely to hit one, since answering a question is exactly what
# empties the fold.
printf 'Which one?\n.\n' | "$MODAL" --mode answer > "$WORKDIR/answer-emptyfold-out" 2>&1 \
  || fail "with nothing pending and no --question, answer mode should exit 0"
grep -q "Nothing is waiting on you." "$WORKDIR/answer-emptyfold-out" \
  || fail "the empty fold stopped printing its friendly line: $(cat "$WORKDIR/answer-emptyfold-out")"
FILES_BEFORE="$(journal_file_count)"
if printf 'Nowhere.\n.\n' | "$MODAL" --mode answer --question "20260201T000000Z-question-nope" 2>"$WORKDIR/emptyfold-bogus-err"; then
  fail "with an empty fold, --question naming a nonexistent record exited 0 instead of refusing"
fi
grep -q "no such question, nothing filed." "$WORKDIR/emptyfold-bogus-err" \
  || fail "the empty-fold bogus-id refusal said something else: $(cat "$WORKDIR/emptyfold-bogus-err")"
if printf 'Not a question.\n.\n' | "$MODAL" --mode answer --question "$REQ_ANS_4" 2>"$WORKDIR/emptyfold-type-err"; then
  fail "with an empty fold, --question naming a request exited 0 instead of refusing"
fi
grep -q "that is not a question, nothing filed." "$WORKDIR/emptyfold-type-err" \
  || fail "the empty-fold wrong-type refusal said something else: $(cat "$WORKDIR/emptyfold-type-err")"
if printf 'Again.\n.\n' | "$MODAL" --mode answer --question "$Q_ANS_4" 2>"$WORKDIR/emptyfold-again-err"; then
  fail "with an empty fold, --question on an already-answered question exited 0 instead of refusing"
fi
grep -q "already answered elsewhere, nothing filed." "$WORKDIR/emptyfold-again-err" \
  || fail "the empty-fold already-answered refusal said something else: $(cat "$WORKDIR/emptyfold-again-err")"
[ "$(journal_file_count)" = "$FILES_BEFORE" ] || fail "an empty-fold --question refusal wrote a record anyway"

log "answer mode: an interactive session ignores --question and shows the picker anyway (test 8)"
REQ_ANS_5="$("$CASTLE" ask "Answer-mode errand five: the terminal font looks thin.")"
REQ_ANS_6="$("$CASTLE" ask "Answer-mode errand six: the clock is hard to read.")"
Q_ANS_5="$(plant_question "$REQ_ANS_5" 20260201T000500Z "Thicken the terminal font, or leave it?")"
Q_ANS_6="$(plant_question "$REQ_ANS_6" 20260201T000600Z "Enlarge the clock, or leave it?")"
"$CASTLE" validate || fail "the ignore---question fixtures do not validate"
drive_modal "$WORKDIR/answer-ignore.txt" --mode answer --question "$Q_ANS_6" -- \
  "wait:any other key to close" "key:1" "wait:End with a line containing just" \
  "send:Thicken it.\n.\n" "wait:Press Enter to close" "send:\n"
grep -q "\[2\] Enlarge the clock, or leave it?" "$WORKDIR/answer-ignore.txt" \
  || fail "--question preselected a question in an interactive session instead of showing the whole picker"
[ -n "$(answers_naming "$Q_ANS_5")" ] \
  || fail "pressing 1 did not answer the oldest pending question — --question was not ignored"
[ -z "$(answers_naming "$Q_ANS_6")" ] \
  || fail "the interactive session answered the --question target instead of the one the resident picked"
printf 'Answered, so the next test starts from an empty fold.\n.\n' \
  | "$MODAL" --mode answer --question "$Q_ANS_6" >/dev/null

log "answer mode: a fact-carrying question writes the elicited entry, and says so in plain language (test 9)"
REQ_ANS_7="$("$CASTLE" ask "Answer-mode errand seven: the notification sound is startling.")"
Q_ANS_7="$(plant_question "$REQ_ANS_7" 20260201T000700Z \
  "Silence the notification sound, or keep it?" "notification-sound-posture")"
"$CASTLE" validate || fail "the fact-carrying question fixture does not validate"
drive_modal "$WORKDIR/answer-fact.txt" --mode answer -- \
  "wait:any other key to close" "key:1" "wait:End with a line containing just" \
  "send:Silence it.\n.\n" "wait:Press Enter to close" "send:\n"
ANSWER_FACT_OUT="$(cat "$WORKDIR/answer-fact.txt")"
[ "$(transcript_rc "$WORKDIR/answer-fact.txt")" = "0" ] || fail "answering a fact-carrying question did not exit 0"
ANSWER_FACT_FILE="$(answers_naming "$Q_ANS_7" | head -1)"
[ -n "$ANSWER_FACT_FILE" ] || fail "the fact-carrying question was not the one answered"
ANSWER_FACT_ID="$(basename "$ANSWER_FACT_FILE" .md)"
MODEL_FILE="$CASTLE_STATE_DIR/resident-model.md"
[ -f "$MODEL_FILE" ] || fail "answering a fact-carrying question through the modal wrote no resident-model entry"
grep -q "^fact: notification-sound-posture\$" "$MODEL_FILE" || fail "$MODEL_FILE does not name the fact the question declared"
grep -q "^asked: $Q_ANS_7\$" "$MODEL_FILE" || fail "$MODEL_FILE's entry does not cite the question it was elicited by"
grep -q "^answered: $ANSWER_FACT_ID\$" "$MODEL_FILE" || fail "$MODEL_FILE's entry does not cite the answer just written"
echo "$ANSWER_FACT_OUT" | grep -q "Noted — I'll remember that." \
  || fail "the modal did not tell the resident, in plain language, that something was written to their model"
refute "$ANSWER_FACT_OUT" "recorded resident-model entry" "the modal printed the CLI's internal resident-model line"
refute "$ANSWER_FACT_OUT" "notification-sound-posture" "the modal printed the internal fact name"

log "castle answer: a second answer on the same question is refused, and exactly one answer record survives (test 10)"
REQ_ANS_8="$("$CASTLE" ask "Answer-mode errand eight: the CLI must refuse a double answer.")"
Q_ANS_8="$(plant_question "$REQ_ANS_8" 20260201T000800Z "Answer me once, and only once?")"
"$CASTLE" answer "$Q_ANS_8" "Once." >/dev/null || fail "the first castle answer was refused"
if "$CASTLE" answer "$Q_ANS_8" "Twice." 2>"$WORKDIR/answer-twice-err"; then
  fail "castle answer accepted a second answer on an already-answered question"
fi
grep -q "was already answered by" "$WORKDIR/answer-twice-err" \
  || fail "the CLI's already-answered refusal did not name the existing answer: $(cat "$WORKDIR/answer-twice-err")"
ANSWERS_FOR_Q8="$(answers_naming "$Q_ANS_8" | wc -l | tr -d ' ')"
[ "$ANSWERS_FOR_Q8" = "1" ] || fail "expected exactly one answer record for $Q_ANS_8, found $ANSWERS_FOR_Q8"
"$CASTLE" validate || fail "the journal does not validate after the double-answer refusal"

log "answer mode: more than nine pending shows nine and names the rest honestly (test 11)"
REQ_ANS_9="$("$CASTLE" ask "Answer-mode errand nine: ten questions at once.")"
for N in 01 02 03 04 05 06 07 08 09 10; do
  plant_question "$REQ_ANS_9" "20260201T0009${N}Z" "Overflow question number $N?" >/dev/null
done
"$CASTLE" validate || fail "the overflow question fixtures do not validate"
drive_modal "$WORKDIR/answer-overflow.txt" --mode answer -- \
  "wait:any other key to close" "key:x"
ANSWER_OVERFLOW_OUT="$(cat "$WORKDIR/answer-overflow.txt")"
echo "$ANSWER_OVERFLOW_OUT" | grep -q "\[9\] Overflow question number 09?" \
  || fail "the picker did not show a ninth entry: $ANSWER_OVERFLOW_OUT"
refute "$ANSWER_OVERFLOW_OUT" "\[10\]" "the picker showed a tenth entry — the cap is nine"
echo "$ANSWER_OVERFLOW_OUT" | grep -q "…and 1 more waiting — press m to see them." \
  || fail "the picker did not name the overflow count and the way to reach it: $ANSWER_OVERFLOW_OUT"
echo "$ANSWER_OVERFLOW_OUT" | grep -q "Press a number to answer, m for more, or any other key to close." \
  || fail "the picker did not offer paging in its prompt when more than nine are pending"

log "answer mode: a page turn past the last page wraps back to the first"
drive_modal "$WORKDIR/answer-wrap.txt" --mode answer -- \
  "wait:any other key to close" "key:m" "wait:Overflow question number 10?" \
  "key:m" "sleep:1" "key:z"
[ "$(transcript_rc "$WORKDIR/answer-wrap.txt")" = "0" ] || fail "wrapping around the pages did not exit 0"
# The first page rendered twice: once on open, once after the second m
# wrapped past the last page. A cumulative transcript makes every
# `wait` for already-seen text return instantly, so this counts renders
# rather than waiting for one.
WRAP_RENDERS="$(grep -c "\[1\] Overflow question number 01?" "$WORKDIR/answer-wrap.txt" || true)"
[ "$WRAP_RENDERS" -ge 2 ] \
  || fail "m on the last page did not wrap back to the first (first page rendered $WRAP_RENDERS time(s))"

log "answer mode: m turns the page, and the tenth question is reachable and answerable (review round 1, finding 1)"
# The cap alone made question ten unreachable — possibly the very
# question a notification had just pointed the resident at, on a
# surface whose fold exists so nothing can be hidden by construction.
drive_modal "$WORKDIR/answer-page.txt" --mode answer -- \
  "wait:any other key to close" "key:m" "wait:Overflow question number 10?" \
  "key:1" "wait:End with a line containing just" \
  "send:Answered from the second page.\n.\n" "wait:Press Enter to close" "send:\n"
ANSWER_PAGE_OUT="$(cat "$WORKDIR/answer-page.txt")"
[ "$(transcript_rc "$WORKDIR/answer-page.txt")" = "0" ] || fail "answering from the second page did not exit 0"
echo "$ANSWER_PAGE_OUT" | grep -q "\[1\] Overflow question number 10?" \
  || fail "pressing m did not put the tenth question at [1] on a new page: $ANSWER_PAGE_OUT"
Q_TENTH="20260201T000910Z-question-q000910Z"
[ -n "$(answers_naming "$Q_TENTH")" ] \
  || fail "the answer filed from the second page does not name the tenth question"
grep -q "Answered from the second page." "$(answers_naming "$Q_TENTH" | head -1)" \
  || fail "the second-page answer body did not land verbatim"

log "answer mode: a keypress that only *looks* like a digit closes cleanly (review round 1, finding 5)"
# str.isdigit() is true of '²' and of Eastern-Arabic digits, and int()
# accepts the latter — so the old predicate crashed on one and silently
# selected an entry on the other.
FILES_BEFORE="$(journal_file_count)"
drive_modal "$WORKDIR/answer-superscript.txt" --mode answer -- \
  "wait:any other key to close" "key:²"
[ "$(transcript_rc "$WORKDIR/answer-superscript.txt")" = "0" ] \
  || fail "a superscript digit at the picker did not close cleanly"
grep -q "Traceback" "$WORKDIR/answer-superscript.txt" \
  && fail "a superscript digit at the picker raised — the transcript carries a traceback"
[ "$(journal_file_count)" = "$FILES_BEFORE" ] || fail "a superscript digit wrote something"

log "status mode: it now holds its window open until dismissed, on both exit paths (test 12)"
drive_modal "$WORKDIR/status-pause.txt" --mode status -- \
  "wait:Press Enter to close" "send:\n"
[ "$(transcript_rc "$WORKDIR/status-pause.txt")" = "0" ] || fail "status mode did not exit 0 after dismissal"
grep -q "asked: Answer-mode errand nine" "$WORKDIR/status-pause.txt" \
  || fail "the status listing did not render before the pause"
grep -q "waiting on you — press Mod4+Shift+Return to answer" "$WORKDIR/status-pause.txt" \
  || fail "the status overlay does not name the chord that answers the question it is reporting"
EMPTY_STATUS_STATE="$WORKDIR/empty-status-state"
mkdir -p "$EMPTY_STATUS_STATE"
CASTLE_STATE_DIR="$EMPTY_STATUS_STATE" python3 "$PTY_DRIVE" "$MODAL" --mode status -- \
  "wait:Press Enter to close" "send:\n" > "$WORKDIR/status-empty.txt" \
  || { cat "$WORKDIR/status-empty.txt" >&2; fail "status mode's empty-journal path did not hold its window open"; }
grep -q "No errands yet" "$WORKDIR/status-empty.txt" \
  || fail "the empty-journal status path did not print its message before pausing"
[ "$(transcript_rc "$WORKDIR/status-empty.txt")" = "0" ] || fail "empty-journal status mode did not exit 0"

log "the dismissal pause needs a tty on BOTH ends, or a command substitution hangs forever (review round 1, finding 4)"
# `$(castle-modal --mode status)` from a terminal pipes stdout while
# stdin stays the caller's tty. A stdin-only gate read that as "a human
# is here" and blocked on a keypress nobody knew to press — a reviewer
# hung a harness on exactly this. Captured output means nobody is
# watching a window that could close, which is the only thing the pause
# exists to prevent. Driven with a pty for stdin and a pipe for stdout,
# under `timeout` so a regression fails this test rather than wedging
# the whole suite.
cat > "$WORKDIR/pty-stdin-pipe-stdout.py" <<'PYSTDOUT'
"""Run castle-modal with a real tty on stdin and a pipe on stdout —
the shape a command substitution produces from a terminal, and the one
a stdin-only isatty() gate misreads as "a human is watching".

Any arguments after the mode are written to the pty in order, each
after a pause: with stdout captured there is nothing to wait *for*, so
this drives blind rather than pretending to synchronise on prompts it
cannot see. The pauses are generous for the same cbreak-gap reason the
other driver documents."""
import os
import pty
import subprocess
import sys
import time

modal, mode, writes = sys.argv[1], sys.argv[2], sys.argv[3:]
main_fd, sub_fd = pty.openpty()
proc = subprocess.Popen(
    [modal, "--mode", mode],
    stdin=sub_fd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, close_fds=True,
)
os.close(sub_fd)
for chunk in writes:
    time.sleep(1.5)
    os.write(main_fd, chunk.replace("\\n", "\n").encode())
out, _ = proc.communicate(timeout=20)
sys.stdout.write(out.decode(errors="replace"))
sys.stdout.write(f"\nRC={proc.returncode}\n")
PYSTDOUT
timeout 30 python3 "$WORKDIR/pty-stdin-pipe-stdout.py" "$MODAL" status > "$WORKDIR/status-piped-stdout.txt" 2>&1 \
  || fail "status mode with a tty stdin and a piped stdout did not exit promptly — the pause is gating on stdin alone again"
[ "$(transcript_rc "$WORKDIR/status-piped-stdout.txt")" = "0" ] || fail "the piped-stdout status run did not exit 0"
grep -q "Press Enter to close" "$WORKDIR/status-piped-stdout.txt" \
  && fail "status mode asked a captured run to press Enter — nobody is watching a window that could close"
# Answer mode's picker legitimately blocks on a keypress with a tty
# stdin (that is a keyboard, and the picker needs one) — so this drives
# a whole answer through and asserts only that the *pause* stayed away.
timeout 40 python3 "$WORKDIR/pty-stdin-pipe-stdout.py" "$MODAL" answer "1" "Answered with stdout captured.\\n.\\n" \
  > "$WORKDIR/answer-piped-stdout.txt" 2>&1 \
  || fail "answer mode with a tty stdin and a piped stdout did not exit promptly"
[ "$(transcript_rc "$WORKDIR/answer-piped-stdout.txt")" = "0" ] || fail "the piped-stdout answer run did not exit 0"
tr -d '\r' < "$WORKDIR/answer-piped-stdout.txt" | grep -qx "Filed." \
  || fail "the piped-stdout answer run did not file anything: $(cat "$WORKDIR/answer-piped-stdout.txt")"
grep -q "Press Enter to close" "$WORKDIR/answer-piped-stdout.txt" \
  && fail "answer mode asked a captured run to press Enter"
true

log "file_answer: a resident-model entry that cannot be written must not cost the resident their answer (review round 1, finding 3)"
# The answer record is durable before the entry is attempted, and the
# already-answered guard would refuse a retry — so an escaping OSError
# here would lose the typed answer permanently. The model is a view
# over the journal and can be re-derived; the record cannot.
REQ_MODEL_FAIL="$("$CASTLE" ask "Answer-mode errand ten: the model file is not writable.")"
Q_MODEL_FAIL="$(plant_question "$REQ_MODEL_FAIL" 20260201T001000Z \
  "Does a failed model write still leave the answer filed?" "model-write-posture")"
MODEL_FILE="$CASTLE_STATE_DIR/resident-model.md"
MODEL_BEFORE="$(model_byte_count)"
chmod 0444 "$MODEL_FILE"
set +e
MODEL_FAIL_ID="$("$CASTLE" answer "$Q_MODEL_FAIL" "Yes, it should." 2>"$WORKDIR/model-fail-err")"
MODEL_FAIL_RC=$?
set -e
chmod 0644 "$MODEL_FILE"
[ "$MODEL_FAIL_RC" = "0" ] || fail "castle answer exited $MODEL_FAIL_RC when only the resident-model write failed — the answer itself was fine"
[ -n "$MODEL_FAIL_ID" ] || fail "castle answer printed no record id when the resident-model write failed"
[ -f "$CASTLE_STATE_DIR/journal/$MODEL_FAIL_ID.md" ] || fail "castle answer printed $MODEL_FAIL_ID but wrote no such record"
grep -q "could not be written" "$WORKDIR/model-fail-err" \
  || fail "nothing on stderr said the resident-model entry failed: $(cat "$WORKDIR/model-fail-err")"
grep -q "$MODEL_FAIL_ID" "$WORKDIR/model-fail-err" \
  || fail "the diagnostic did not name the answer that WAS filed: $(cat "$WORKDIR/model-fail-err")"
[ "$(model_byte_count)" = "$MODEL_BEFORE" ] || fail "the resident model grew even though its write failed"
grep -q "recorded resident-model entry" "$WORKDIR/model-fail-err" \
  && fail "castle answer claimed it recorded an entry that was never written"
"$CASTLE" validate || fail "the journal does not validate after a failed resident-model write"

log "file_answer: an answer record that does not parse stops the guard cold, on both surfaces (review round 1, finding 8)"
# load_all skips what it cannot parse, so folding the guard over it
# would let one corrupt answer re-open the silent duplicate the guard
# exists to close. An unreadable answer means pendingness cannot be
# established, and neither surface may write through that.
REQ_CORRUPT="$("$CASTLE" ask "Answer-mode errand eleven: a corrupt answer record blocks the guard.")"
Q_CORRUPT="$(plant_question "$REQ_CORRUPT" 20260201T001100Z "Is this question still open?")"
CORRUPT_ANSWER="$CASTLE_STATE_DIR/journal/20260201T001101Z-answer-broken.md"
printf 'this file has no frontmatter at all and cannot be parsed\n' > "$CORRUPT_ANSWER"
FILES_BEFORE="$(journal_file_count)"
if "$CASTLE" answer "$Q_CORRUPT" "Trying anyway." 2>"$WORKDIR/corrupt-cli-err"; then
  fail "castle answer wrote an answer while an unparseable answer record made pendingness unknowable"
fi
grep -q "cannot verify" "$WORKDIR/corrupt-cli-err" \
  || fail "the CLI refusal did not say it could not verify the question's state: $(cat "$WORKDIR/corrupt-cli-err")"
grep -q "castle validate" "$WORKDIR/corrupt-cli-err" \
  || fail "the CLI refusal did not point at castle validate: $(cat "$WORKDIR/corrupt-cli-err")"
if printf 'Trying anyway.\n.\n' | "$MODAL" --mode answer --question "$Q_CORRUPT" 2>"$WORKDIR/corrupt-modal-err"; then
  fail "castle-modal wrote an answer while an unparseable answer record made pendingness unknowable"
fi
grep -q "can.t check that question is still open, nothing filed." "$WORKDIR/corrupt-modal-err" \
  || fail "the modal refusal did not use its plain, path-free wording: $(cat "$WORKDIR/corrupt-modal-err")"
grep -q "$CORRUPT_ANSWER" "$WORKDIR/corrupt-modal-err" \
  && fail "the modal named a journal path — this surface may not hand the resident a filename"
[ "$(journal_file_count)" = "$FILES_BEFORE" ] || fail "something was written despite both refusals"
rm -f "$CORRUPT_ANSWER"
"$CASTLE" validate || fail "the journal does not validate once the corrupt fixture is removed"
# And with the corrupt file gone, the same answer goes through: the
# refusal was about the unreadable file, not about this question.
"$CASTLE" answer "$Q_CORRUPT" "Now it works." >/dev/null \
  || fail "the answer was still refused after the unparseable record was removed"

# ---------------------------------------------------------------------
# docs/tasks/0025-approval.md — review mode.
# ---------------------------------------------------------------------
#
# A fresh state dir again, for the reason the answer-mode section gives
# for its own: these assertions are about what a resident sees on
# screen and which entry the picker offers, so they cannot be made
# against the journal every section above accumulated.
#
# The result record below is planted by hand rather than produced by a
# worker turn, which is the opposite of what approval.sh does and is
# deliberate. approval.sh drives the real mechanism end to end; this
# section is about the *rendering*, and rendering assertions need a
# body whose every line is known — including the vocabulary check,
# which cannot mean anything against a real tenant's stdout or a real
# diff, since neither is bound by this surface's rules (a diff of
# modules/ legitimately contains the word "record").
export CASTLE_STATE_DIR="$WORKDIR/review-state"
export XDG_RUNTIME_DIR="$WORKDIR/review-runtime"
mkdir -p "$CASTLE_STATE_DIR/journal" "$XDG_RUNTIME_DIR"

REVIEW_REQ="$("$CASTLE" ask "REVIEW-FIXTURE: an invented complaint about something being hard to see.")"
plant_proposal() {
  # Usage: plant_proposal <stamp> <account-line> <diff-file|-> [no-boundary]
  # Echoes the question id.
  #
  # Writes a result whose body has the exact shape run_worker_turn
  # produces — the harness's own turn header, the tenant's account, the
  # diff wrapped in this record's own boundary lines, the resolved-path
  # sentence and the worker-proposes note — then a question stamped
  # with that result file's real hash, computed with sha256sum rather
  # than with the tool under test.
  #
  # A fourth argument suppresses the `diff-boundary` field (while still
  # writing the boundary lines), which is how the no-boundary
  # degradation is exercised: that is every result written before the
  # field existed, and it must show its body whole rather than guess.
  #
  # A fifth appends the OTHER prose `run_worker_turn` can write after
  # the diff — the mechanism-unavailable note and the undrained-output
  # note, quoted from `agent/castle` — which is what the tail-dropping
  # rule is asserted against.
  # A sixth stamps `authorizes-apply: true` on the question
  # (docs/tasks/0026-apply-validate.md §A). Absent by default, and that
  # default is the point: every fixture in this file predates the
  # applier the way every proposal in a real journal did, so the
  # pre-apply boundary statement is what they all render, and the one
  # case below that passes it is the mirror.
  local stamp="$1" account="$2" diff_file="$3" no_boundary="${4:-}" harness_tail="${5:-}"
  local authorizes_apply="${6:-}"
  local result_id="$stamp-result-r${stamp: -7}"
  local question_id="$stamp-question-q${stamp: -7}"
  # Sixteen hex characters, derived from the stamp so a failing
  # assertion names a fixture a reader can find — the real one is eight
  # random bytes from os.urandom.
  local boundary
  boundary="$(printf '%s' "$stamp" | sha256sum | cut -c1-16)"
  {
    echo "---"
    echo "id: $result_id"
    echo "type: result"
    echo "provenance: requested"
    echo "refs: $REVIEW_REQ"
    echo "seat: worker"
    echo "created: 2026-02-01T00:00:00Z"
    echo "outcome: completed"
    echo "target: private"
    [ -n "$no_boundary" ] || echo "diff-boundary: $boundary"
    echo "---"
    echo
    echo "Errand \`$REVIEW_REQ\` completed by worker tenant \`/nix/store/invented-hash-not-a-real-path/bin/tenant\`."
    echo
    echo "$account"
    echo
    echo "CASTLE-DIFF-$boundary BEGIN"
    echo '```diff'
    if [ "$diff_file" = "-" ]; then
      echo "--- a/invented.nix"
      echo "+++ b/invented.nix"
      echo "@@ -1 +1 @@"
      echo "-INVENTED-DIFF-BEFORE"
      echo "+INVENTED-DIFF-AFTER"
    else
      cat "$diff_file"
    fi
    echo '```'
    echo "CASTLE-DIFF-$boundary END"
    echo
    echo "This diff targets the **private** checkout, which on this host resolved to \`/invented/checkout\`."
    if [ -n "$harness_tail" ]; then
      # Both quoted from `run_worker_turn`, which appends them after
      # the diff on a turn that completed: the undrained-output note (a
      # setsid grandchild can hold the pipes open on a turn that still
      # exits 0) and the mechanism-unavailable note. The second is the
      # one that matters — it carries an internal option name and a
      # configured filesystem path, and it landed in the section
      # labelled as the machine's own reasoning. The username is this
      # repo's own published placeholder, the same one
      # nixosConfigurations.example uses; nothing here is a real path.
      echo
      echo "The tenant's own stdout and stderr could not be collected. This turn killed the tenant's whole process group and the pipes were still held 5s later, which narrows what is holding them to one thing: a descendant that called setsid() and so is outside the group this turn can reach. It is still running, and this turn cannot end it. Nothing above came from the tenant's output stream."
      echo
      echo "Note: \`castle.agent.repo.mechanism\` is configured (\`/home/resident/invented-checkout\`) but it is not a git checkout, so this turn treated the mechanism checkout as unavailable. Nothing else about the turn was refused on that account."
    fi
    echo
    echo "This result was produced by the worker seat. Per docs/tasks/0009-ambient-intake.md's non-goals, the worker proposes; it does not deploy — nothing above was applied to any running system or committed to any repo by this seat."
  } > "$CASTLE_STATE_DIR/journal/$result_id.md"
  {
    echo "---"
    echo "id: $question_id"
    echo "type: question"
    echo "provenance: requested"
    echo "refs: $REVIEW_REQ,$result_id"
    echo "seat: worker"
    echo "created: 2026-02-01T00:00:00Z"
    echo "proposal-sha256: $(sha256sum "$CASTLE_STATE_DIR/journal/$result_id.md" | cut -d' ' -f1)"
    [ -z "$authorizes_apply" ] || echo "authorizes-apply: true"
    echo "---"
    echo
    echo "This errand produced a proposed change to your private configuration. Nothing has been applied. Review it to approve, reject, or set it aside."
  } > "$CASTLE_STATE_DIR/journal/$question_id.md"
  echo "$question_id"
}

plant_bare_proposal() {
  # Usage: plant_bare_proposal <request-id>; echoes the question id.
  # A minimal, `castle validate`-clean question carrying a
  # syntactically valid proposal-sha256 stamp and no result at all —
  # enough for `_is_proposal`'s own check, which is the stamp and not a
  # matching result. Two callers now: the overlay-wording assertions at
  # the end of this file, and the refusal case below, where a proposal
  # naming no result is exactly the shape review mode must decline to
  # offer keys for.
  local req="$1"
  local qid="${req}-bareprop"
  {
    echo "---"
    echo "id: $qid"
    echo "type: question"
    echo "provenance: requested"
    echo "refs: $req"
    echo "seat: worker"
    echo "created: 2026-02-01T00:00:00Z"
    echo "proposal-sha256: $(printf '%s' "$qid" | sha256sum | cut -d' ' -f1)"
    echo "---"
    echo
    echo "A bare proposal fixture, only for overlay-wording assertions."
  } > "$CASTLE_STATE_DIR/journal/$qid.md"
  echo "$qid"
}

REVIEW_Q="$(plant_proposal 20260301T000100Z "The value it uses now is too small to read at arm's length, so this raises it." -)"
"$CASTLE" validate || fail "the planted proposal fixture does not validate"

log "review mode: a change picked out of the ANSWER picker branches into review, not into free text"
# The path a resident actually takes: the same chord, the same list,
# and no advance knowledge of which of two kinds of waiting this was.
CASTLE_REVIEW_RESIZE_COMMAND="" drive_modal "$WORKDIR/review-branch.txt" --mode answer -- \
  "wait:any other key to close" "key:1" "wait:any other key closes this" "key:x"
BRANCH_OUT="$(cat "$WORKDIR/review-branch.txt")"
[ "$(transcript_rc "$WORKDIR/review-branch.txt")" = "0" ] || fail "the answer picker's review branch did not exit 0"
echo "$BRANCH_OUT" | grep -q "\[a\]pprove" \
  || fail "picking a proposed change dropped into the free-text grammar instead of review: $BRANCH_OUT"
echo "$BRANCH_OUT" | grep -q "Answer in your own words." \
  && fail "picking a proposed change offered the ordinary answer grammar"

log "review mode: what the resident sees, in the order it has to be in"
CASTLE_REVIEW_RESIZE_COMMAND="" drive_modal "$WORKDIR/review-render.txt" --mode review -- \
  "wait:any other key closes this" "key:x"
RENDER_OUT="$(tr -d '\r' < "$WORKDIR/review-render.txt")"
echo "$RENDER_OUT"
[ "$(transcript_rc "$WORKDIR/review-render.txt")" = "0" ] || fail "a dismissed review did not exit 0"

# Each of the four sections, present.
echo "$RENDER_OUT" | grep -q "Where this applies:" || fail "the review does not say where the change applies"
echo "$RENDER_OUT" | grep -qF 'resolved to `/invented/checkout`' \
  || fail "the review does not quote the harness's own resolved-path sentence"
# The PRE-APPLY branch (docs/tasks/0026-apply-validate.md §A): this
# fixture's question carries no `authorizes-apply`, so nothing will ever
# apply it and the older, narrower statement is what a resident decides
# it under — forever, because the field travels with the record that was
# shown and no migration can reach backwards. The other branch is
# asserted in its own section further down.
echo "$RENDER_OUT" | grep -q "NOTHING ON THIS MACHINE IS EDITED, COMMITTED, OR APPLIED" \
  || fail "the review does not say plainly that approving applies nothing"
refute "$RENDER_OUT" "APPROVING IT AUTHORIZES CASTLE TO MAKE THIS CHANGE" \
  "a change offered before the applier existed was shown as one an apply follows"
echo "$RENDER_OUT" | grep -q "its words, not verified by a person" \
  || fail "the machine's own account is not attributed as machine-authored"
echo "$RENDER_OUT" | grep -q "The value it uses now is too small to read" \
  || fail "the account itself is missing"
echo "$RENDER_OUT" | grep -q '^+INVENTED-DIFF-AFTER$' || fail "the diff is missing"
echo "$RENDER_OUT" | grep -q "Shift+Page Up" \
  || fail "nothing tells the resident the window has scrollback for a long diff"

# And in that order, checked by line number rather than by presence —
# "evidence before reasoning, the diff always available and always
# last" is the whole ordering claim, and five greps in any order prove
# none of it.
line_of() { printf '%s\n' "$RENDER_OUT" | grep -n -- "$1" | head -1 | cut -d: -f1; }
WHERE_AT="$(line_of 'Where this applies:')"
BOUNDARY_AT="$(line_of 'NOTHING ON THIS MACHINE IS EDITED')"
KEYS_AT="$(line_of '\[a\]pprove')"
ACCOUNT_AT="$(line_of 'its words, not verified by a person')"
DIFF_AT="$(line_of '^+INVENTED-DIFF-AFTER$')"
[ "$WHERE_AT" -lt "$BOUNDARY_AT" ] || fail "the boundary statement comes before where the change applies"
[ "$BOUNDARY_AT" -lt "$KEYS_AT" ] || fail "the keys are offered before the sentence saying what they do"
[ "$KEYS_AT" -lt "$ACCOUNT_AT" ] || fail "the keys are not beside the boundary statement"
[ "$ACCOUNT_AT" -lt "$DIFF_AT" ] || fail "the diff is not last"

log "review mode: no record id, and none of the internal vocabulary, in what the tool itself says"
# Scoped to the text this surface ADDS, which is what the rule binds:
# everything below the attribution label is the result body, shown
# verbatim, and is no more bound by this than a question body is. The
# label itself is the boundary, so everything above it is the tool's
# own words.
TOOL_SAYS="$(printf '%s\n' "$RENDER_OUT" | sed -n "1,$((ACCOUNT_AT - 1))p")"
for LEAKED in "$REVIEW_Q" "$REVIEW_REQ"; do
  refute "$TOOL_SAYS" "$LEAKED" "review mode printed the record id $LEAKED"
done
for LEAKED in seat provenance refs journal record channel evidence proposal; do
  refute "$TOOL_SAYS" "$LEAKED" "review mode printed the internal word '$LEAKED'"
done
# And the two things the result body's own harness-written header
# carries, which this surface may not repeat at all — a record id and a
# store path — checked over the WHOLE transcript, not just the tool's
# half, because dropping that header is exactly how they stay out.
refute "$RENDER_OUT" "/nix/store/invented-hash" \
  "the review printed the tenant's store path — the turn header must not be quoted"
refute "$RENDER_OUT" "docs/tasks/0009-ambient-intake" \
  "the review quoted the harness's worker-proposes note under the machine's own account"

log "review mode: a change that DOES carry apply authority says so, and confirms differently"
# The mirror of the pre-apply assertions above
# (docs/tasks/0026-apply-validate.md §A). Two surfaces change with the
# stamp and no others: the boundary statement the resident decides
# under, and the line printed after they decide. Both are asserted here
# against the same fixture shape the pre-apply case uses, so the only
# difference between the two runs is the one field.
#
# Scripted rather than pty-driven: `--question` is honoured on the piped
# path, which is what lets this pick its own fixture instead of whatever
# an interactive picker would choose, and the two wordings are text
# either way.
APPLY_Q="$(plant_proposal 20260301T000800Z "A change offered under the statement that an apply follows approving it." - "" "" yes)"
"$CASTLE" validate || fail "the apply-authorizing proposal fixture does not validate"
grep -q '^authorizes-apply: true$' "$CASTLE_STATE_DIR/journal/$APPLY_Q.md" \
  || fail "the apply-authorizing fixture did not stamp the field, so this section proves nothing"
printf 'a\n.\n' | "$MODAL" --mode review --question "$APPLY_Q" >"$WORKDIR/review-applyable.txt" 2>&1 \
  || fail "approving an apply-authorizing change failed: $(cat "$WORKDIR/review-applyable.txt")"
APPLYABLE_OUT="$(tr -d '\r' < "$WORKDIR/review-applyable.txt")"
printf '%s\n' "$APPLYABLE_OUT" | grep -q "APPROVING IT AUTHORIZES CASTLE TO MAKE THIS CHANGE IN YOUR" \
  || fail "the review does not say approving authorizes the change to be made: $APPLYABLE_OUT"
printf '%s\n' "$APPLYABLE_OUT" | grep -q "NOTHING IS ACTIVATED AND NOTHING IS REBUILT" \
  || fail "the review no longer says nothing is activated: $APPLYABLE_OUT"
refute "$APPLYABLE_OUT" "NOTHING ON THIS MACHINE IS EDITED" \
  "an apply-authorizing change was decided under the retired statement"
printf '%s\n' "$APPLYABLE_OUT" \
  | grep -qF "Approved. Castle will make this change in your configuration repository. Nothing will be activated." \
  || fail "the confirmation does not say what approving an applyable change does: $APPLYABLE_OUT"

log "  -- and the pre-apply change confirms with the bare 'Approved.', so the two really differ"
# The control. Without it the assertion above is satisfied by a
# confirmation that says the same thing on every change in the system,
# including the ones nothing will ever apply.
PREAPPLY_Q="$(plant_proposal 20260301T000700Z "A change offered before the applier existed." -)"
"$CASTLE" validate || fail "the pre-apply proposal fixture does not validate"
printf 'a\n.\n' | "$MODAL" --mode review --question "$PREAPPLY_Q" >"$WORKDIR/review-preapply.txt" 2>&1 \
  || fail "approving a pre-apply change failed: $(cat "$WORKDIR/review-preapply.txt")"
PREAPPLY_OUT="$(tr -d '\r' < "$WORKDIR/review-preapply.txt")"
printf '%s\n' "$PREAPPLY_OUT" | grep -qx 'Approved.' \
  || fail "the pre-apply confirmation is not a bare 'Approved.': $PREAPPLY_OUT"
printf '%s\n' "$PREAPPLY_OUT" | grep -q "NOTHING ON THIS MACHINE IS EDITED" \
  || fail "the pre-apply review lost its own statement: $PREAPPLY_OUT"

log "  -- the status surface distinguishes the two approvals it now has to distinguish"
# "approved — nothing applied yet" stays exactly true for a change
# nothing will ever apply, and becomes a lie for one waiting on an
# applier that exists. Both fixtures hang off the same request, and the
# overlay describes the newest proposal on an errand — which is the
# apply-authorizing one, deliberately: its stamp is the later of the
# two.
STATUS_TWO_APPROVALS="$("$MODAL" --mode status --limit 40)"
printf '%s\n' "$STATUS_TWO_APPROVALS" | grep -F "$REVIEW_REQ" | grep -q 'approved — waiting to be applied' \
  || fail "the newest approval, which authorizes an apply, does not say it is waiting to be applied: $(printf '%s\n' "$STATUS_TWO_APPROVALS" | grep -F "$REVIEW_REQ")"

# No `clear_pending_changes` here: both fixtures this section planted
# were decided by it, so it leaves the fold exactly as it found it —
# which is what lets it sit above the interactive sections that need a
# fold they control.

log "review mode: the resize shell-out IS attempted on the interactive path"
# The double-tty gate does not exclude a pty-driven test, on purpose:
# this driver puts a real tty on both ends to exercise the real
# interactive code path. What makes that safe on a developer's own Sway
# session is the app_id criteria, which match zero windows when no
# castle-modal `foot` window exists. Here the whole command is replaced
# by a stub, so nothing needs swaymsg installed at all — exactly how
# CASTLE_NOTIFY_COMMAND lets these harnesses assert routing with no
# notification daemon.
RESIZE_MARKER="$WORKDIR/resize-marker"
RESIZE_STUB="$WORKDIR/resize-stub.sh"
cat > "$RESIZE_STUB" <<STUB
#!/usr/bin/env bash
printf 'hit\n' >> "$RESIZE_MARKER"
STUB
chmod +x "$RESIZE_STUB"
: > "$RESIZE_MARKER"
CASTLE_REVIEW_RESIZE_COMMAND="$RESIZE_STUB" drive_modal "$WORKDIR/review-resize.txt" --mode review -- \
  "wait:any other key closes this" "key:x"
[ -s "$RESIZE_MARKER" ] \
  || fail "the interactive review never attempted to resize its own window — the claim that it does is unbacked"

log "review mode: and it is NOT attempted on a piped path, which has no window to resize"
: > "$RESIZE_MARKER"
printf 'x\n' | CASTLE_REVIEW_RESIZE_COMMAND="$RESIZE_STUB" \
  "$MODAL" --mode review --question "$REVIEW_Q" >/dev/null
[ ! -s "$RESIZE_MARKER" ] \
  || fail "a piped review tried to resize a window it does not have — the double-tty gate is not doing its job"

log "review mode: the empty spelling opts out entirely"
: > "$RESIZE_MARKER"
CASTLE_REVIEW_RESIZE_COMMAND="" drive_modal "$WORKDIR/review-noresize.txt" --mode review -- \
  "wait:any other key closes this" "key:x"
[ ! -s "$RESIZE_MARKER" ] || fail "an explicitly empty resize command still ran something"

log "review mode: with nothing to decide, it says so and exits 0"
NOTHING_STATE="$(mktemp -d)"
CASTLE_STATE_DIR="$NOTHING_STATE" "$MODAL" --mode review </dev/null >"$WORKDIR/review-none.txt" \
  || fail "review mode with nothing pending should exit 0"
grep -q "No changes are waiting for your decision." "$WORKDIR/review-none.txt" \
  || fail "review mode with nothing pending said something else: $(cat "$WORKDIR/review-none.txt")"
rm -rf "$NOTHING_STATE"

log "review mode: a piped session with no --question refuses rather than guessing an authorization"
if "$MODAL" --mode review </dev/null 2>"$WORKDIR/review-noflag.err"; then
  fail "a piped review with a change pending guessed one instead of refusing"
fi
grep -q "no terminal" "$WORKDIR/review-noflag.err" \
  || fail "the piped-without---question refusal did not explain itself: $(cat "$WORKDIR/review-noflag.err")"

log "review mode: --question naming something that is not a proposed change is refused"
if printf 'a\n' | "$MODAL" --mode review --question "$REVIEW_REQ" 2>"$WORKDIR/review-wrongtype.err"; then
  fail "review mode accepted a request id"
fi
grep -q "not a question, nothing filed." "$WORKDIR/review-wrongtype.err" \
  || fail "review mode's wrong-type refusal said something else: $(cat "$WORKDIR/review-wrongtype.err")"
ORDINARY_Q="$("$CASTLE" record --type question --provenance requested --seat worker \
  --refs "$REVIEW_REQ" --body "An ordinary question, not a change.")"
if printf 'a\n' | "$MODAL" --mode review --question "$ORDINARY_Q" 2>"$WORKDIR/review-ordinary.err"; then
  fail "review mode accepted an ordinary question"
fi
grep -q "not a proposed change" "$WORKDIR/review-ordinary.err" \
  || fail "review mode's not-a-change refusal said something else: $(cat "$WORKDIR/review-ordinary.err")"

log "review mode: a change that resolves to nothing is refused BEFORE the keys are offered"
# `file_answer` refuses this either way and nothing is written, so this
# is not about data integrity. It is that the boundary statement, the
# three keys and the optional-comment prompt were all printed for a
# change the surface had already established it could not show: `where`,
# the account and the diff were every one of them empty, and the
# resident was asked to authorize a blank screen. On the one screen
# where authority is granted, the refusal comes first.
BARE_Q="$(plant_bare_proposal "$REVIEW_REQ")"
"$CASTLE" validate || fail "the bare-proposal fixture does not validate"
if printf 'a\n' | "$MODAL" --mode review --question "$BARE_Q" \
  >"$WORKDIR/review-bare.txt" 2>"$WORKDIR/review-bare.err"; then
  fail "review mode offered a decision on a change it cannot resolve"
fi
grep -q "can't find the change that was proposed, nothing filed." "$WORKDIR/review-bare.err" \
  || fail "the unresolvable-change refusal said something else: $(cat "$WORKDIR/review-bare.err")"
BARE_OUT="$(tr -d '\r' < "$WORKDIR/review-bare.txt")"
refute "$BARE_OUT" '\[a\]pprove' \
  "the keys were offered for a change the surface could not resolve"
refute "$BARE_OUT" "NOTHING ON THIS MACHINE IS EDITED" \
  "the boundary statement was printed for a change the surface could not resolve"
refute "$BARE_OUT" "Anything you want to say about it" \
  "the comment prompt ran for a change the surface could not resolve"
# Removed rather than decided: `clear_pending_changes` below closes
# every pending change with a real `castle answer --decision defer`,
# which this one — by construction — is refused for.
rm -f "$CASTLE_STATE_DIR/journal/$BARE_Q.md"
"$CASTLE" validate || fail "the journal does not validate after review mode's refusals"

# Each of the two cases below needs a fold it fully controls: an
# interactive review ignores --question and chooses for itself, exactly
# as answer mode does, so a change left pending by an earlier case
# would put a picker in front of a rendering assertion. Deferring is
# the honest way to clear one — a real decision a resident can make.
clear_pending_changes() {
  local path id
  for path in $(grep -l '^proposal-sha256: ' "$CASTLE_STATE_DIR"/journal/*-question-*.md 2>/dev/null || true); do
    id="$(basename "$path" .md)"
    grep -lq "^refs: $id[,$]" "$CASTLE_STATE_DIR"/journal/*-answer-*.md 2>/dev/null \
      || "$CASTLE" answer --decision defer "$id" </dev/null >/dev/null \
      || fail "could not clear pending change $id"
  done
}
clear_pending_changes

log "review mode: a diff that contains markdown fences is shown WHOLE, not truncated at one"
# ---------------------------------------------------------------------
# The defect this boundary exists for, in the shape a resident actually
# meets it: a change to a file that itself contains a fenced code block.
# Every context line of such a diff carries a leading space, so a
# reader scanning for "```" finds one inside the diff, closes the block
# early, and prints the rest — real `-`/`+` lines included — under
# "Castle's own account of why". On this screen that is not a
# rendering wobble: the resident is shown less than the change they
# are approving, with the missing half relabelled as the machine's
# reasoning.
#
# Both hostile lines are here, and the second is the worse one: a
# context line spelling ```diff would have moved the START of the
# block, not merely its end.
ADVERSARIAL_DIFF="$WORKDIR/adversarial.diff"
cat > "$ADVERSARIAL_DIFF" <<'DIFF'
--- a/README.md
+++ b/README.md
@@ -1,9 +1,9 @@
 Some prose above a fenced block.
 
 ```diff
 an example the file itself contains
-ADVERSARIAL-BEFORE-INSIDE-FENCE
+ADVERSARIAL-AFTER-INSIDE-FENCE
 ```
 
-ADVERSARIAL-BEFORE-AFTER-FENCE
+ADVERSARIAL-AFTER-AFTER-FENCE
DIFF
ADVERSARIAL_Q="$(plant_proposal 20260301T000200Z "This change touches a file that contains a fenced code block." "$ADVERSARIAL_DIFF")"
"$CASTLE" validate || fail "the adversarial-diff fixture does not validate"
CASTLE_REVIEW_RESIZE_COMMAND="" drive_modal "$WORKDIR/review-adversarial.txt" \
  --mode review --question "$ADVERSARIAL_Q" -- "wait:any other key closes this" "key:x"
ADV_OUT="$(tr -d '\r' < "$WORKDIR/review-adversarial.txt")"
[ "$(transcript_rc "$WORKDIR/review-adversarial.txt")" = "0" ] || fail "the adversarial review did not exit 0"

# Every line of the diff is present...
for NEEDLE in ADVERSARIAL-BEFORE-INSIDE-FENCE ADVERSARIAL-AFTER-INSIDE-FENCE \
              ADVERSARIAL-BEFORE-AFTER-FENCE ADVERSARIAL-AFTER-AFTER-FENCE; do
  printf '%s\n' "$ADV_OUT" | grep -q -- "$NEEDLE" \
    || fail "the diff was truncated: $NEEDLE is missing from what the resident saw"
done
# ...and every one of them is BELOW the attribution label, which is
# where the diff is, rather than above it, which is where the machine's
# account is. This is the assertion that would have caught the original
# defect: the lines were all still on screen, in the wrong section.
ADV_ACCOUNT_AT="$(printf '%s\n' "$ADV_OUT" | grep -n 'its words, not verified by a person' | head -1 | cut -d: -f1)"
[ -n "$ADV_ACCOUNT_AT" ] || fail "the attribution label is missing from the adversarial review"
for NEEDLE in ADVERSARIAL-BEFORE-INSIDE-FENCE ADVERSARIAL-AFTER-AFTER-FENCE; do
  LINE_AT="$(printf '%s\n' "$ADV_OUT" | grep -n -- "$NEEDLE" | head -1 | cut -d: -f1)"
  [ "$LINE_AT" -gt "$ADV_ACCOUNT_AT" ] \
    || fail "$NEEDLE was printed as the machine's own account instead of as part of the diff"
done
# And the boundary lines themselves are never shown to the resident:
# they are the record's structure, not its content.
refute "$ADV_OUT" "CASTLE-DIFF-" "the review printed its own boundary marker at the resident"
printf 'Every line of the adversarial diff rendered below the attribution label.\n'

clear_pending_changes

log "review mode: a result with no boundary stamped shows its body whole rather than guessing"
# Every result written before this field existed, in an append-only
# journal that cannot be backfilled. Nothing may be hidden; what is
# given up is the split, not the content.
LEGACY_Q="$(plant_proposal 20260301T000300Z "A legacy result, from before the boundary field existed." - no-boundary)"
"$CASTLE" validate || fail "the legacy-result fixture does not validate"
CASTLE_REVIEW_RESIZE_COMMAND="" drive_modal "$WORKDIR/review-legacy.txt" \
  --mode review --question "$LEGACY_Q" -- "wait:any other key closes this" "key:x"
LEGACY_OUT="$(tr -d '\r' < "$WORKDIR/review-legacy.txt")"
[ "$(transcript_rc "$WORKDIR/review-legacy.txt")" = "0" ] || fail "the legacy review did not exit 0"
printf '%s\n' "$LEGACY_OUT" | grep -q -- "+INVENTED-DIFF-AFTER" \
  || fail "a result with no boundary lost its diff entirely — nothing may be hidden"
printf '%s\n' "$LEGACY_OUT" | grep -q "A legacy result, from before" \
  || fail "a result with no boundary lost its account"
printf '%s\n' "$LEGACY_OUT" | grep -q "Where this applies:" \
  && fail "a result with no boundary had a sentence lifted out of a body this cannot safely split"
printf '%s\n' "$LEGACY_OUT" | grep -q "NOTHING ON THIS MACHINE IS EDITED" \
  || fail "the boundary statement is missing from a legacy review — it is never optional"

clear_pending_changes

log "review mode: nothing the harness appended after the diff is quoted as the machine's own reasoning"
# ---------------------------------------------------------------------
# `_split_proposal_body` used to drop two named lines from the tail and
# let everything else through into the section labelled "Castle's own
# account of why (its words, not verified by a person)". Everything
# `run_worker_turn` writes after the closing boundary is harness prose
# by construction — the tenant's stdout goes in before it — so that
# enumeration leaked by default, and the worst of what it leaked was
# the mechanism-unavailable note: an internal option name and a
# configured filesystem path, on the one screen where a resident grants
# authority.
#
# Asserted as a property of the SECTION, not as a list of lines: what
# may never appear there is a home-shaped path or an internal option
# name, however a future `run_worker_turn` comes to phrase them.
# `approval.sh` has a home-shaped-path check of its own, but that one
# is about what this repo commits; this one is about what the surface
# prints, which is a different claim and could not be made there.
TAIL_Q="$(plant_proposal 20260301T000400Z "TAIL-FIXTURE-ACCOUNT: the reasoning the tenant itself wrote, above the diff." - "" harness-tail)"
"$CASTLE" validate || fail "the harness-tail fixture does not validate"
CASTLE_REVIEW_RESIZE_COMMAND="" drive_modal "$WORKDIR/review-tail.txt" \
  --mode review --question "$TAIL_Q" -- "wait:any other key closes this" "key:x"
TAIL_OUT="$(tr -d '\r' < "$WORKDIR/review-tail.txt")"
[ "$(transcript_rc "$WORKDIR/review-tail.txt")" = "0" ] || fail "the harness-tail review did not exit 0"

TAIL_ACCOUNT_AT="$(printf '%s\n' "$TAIL_OUT" | grep -n 'its words, not verified by a person' | head -1 | cut -d: -f1)"
[ -n "$TAIL_ACCOUNT_AT" ] || fail "the attribution label is missing, so there is no section to make this claim about"
TAIL_DIFF_AT="$(printf '%s\n' "$TAIL_OUT" | grep -n 'Full diff below' | head -1 | cut -d: -f1)"
[ -n "$TAIL_DIFF_AT" ] || fail "the diff heading is missing, so the account section has no end to find"
TAIL_ACCOUNT="$(printf '%s\n' "$TAIL_OUT" | sed -n "$((TAIL_ACCOUNT_AT + 1)),$((TAIL_DIFF_AT - 1))p")"

# The control first: without the tenant's own words in it, every
# refutation below is satisfied by an empty section.
printf '%s\n' "$TAIL_ACCOUNT" | grep -q 'TAIL-FIXTURE-ACCOUNT' \
  || fail "the tenant's own reasoning is missing from the account section: $TAIL_ACCOUNT"

refute "$TAIL_ACCOUNT" "/home/" \
  "a home-shaped path was printed under the label that says these are the machine's own words"
refute "$TAIL_ACCOUNT" "castle.agent.repo" \
  "an internal option name was printed under the label that says these are the machine's own words"
refute "$TAIL_ACCOUNT" "setsid" \
  "the harness's undrained-output note was quoted as the machine's reasoning about the change"
refute "$TAIL_ACCOUNT" "docs/tasks/0009-ambient-intake" \
  "the harness's worker-proposes note was quoted as the machine's reasoning about the change"
# And the same two, over the whole render rather than one section: the
# tail is dropped outright, so neither reaches the resident at all.
refute "$TAIL_OUT" "/home/resident" "the review printed a home-shaped path anywhere on screen"
refute "$TAIL_OUT" "castle.agent.repo" "the review printed an internal option name anywhere on screen"

# The one line the tail still contributes, so this is a rule about
# where a line came from rather than a blanket refusal to read the
# tail at all.
printf '%s\n' "$TAIL_OUT" | grep -q 'Where this applies:' \
  || fail "dropping the tail also lost the resolved-checkout sentence, which is lifted out of it deliberately"
printf '%s\n' "$TAIL_OUT" | grep -qF 'resolved to `/invented/checkout`' \
  || fail "the resolved-checkout sentence is no longer quoted in the harness's own words"

clear_pending_changes

log "review mode: control bytes in a tenant diff or account cannot repaint the boundary or the keys (0025 review pass, escape-sequence finding)"
# This surface reads an approve/reject/defer keypress moments after
# printing the tenant's diagnosis and diff verbatim. A clear-screen or
# cursor-reposition escape sequence in either — reachable via a changed
# file's own bytes on the diff side, or the tenant's own stdout on the
# account side — would repaint over the boundary statement and the key
# list an instant before the keypress is read, so the resident
# authorizes whatever was left on screen rather than what was actually
# shown. `_defang_for_terminal` drops every control byte but newline
# and tab before either reaches print().
ESCAPE_DIFF="$WORKDIR/escape.diff"
printf -- '--- a/evil.txt\n+++ b/evil.txt\n@@ -1 +1 @@\n-before\n+after\033[2J\033[HFAKE-DIFF-PAYLOAD\n' \
  > "$ESCAPE_DIFF"
ESCAPE_ACCOUNT="$(printf 'An account that also tries a screen clear.\033[2JFAKE-ACCOUNT-PAYLOAD')"
ESCAPE_Q="$(plant_proposal 20260301T000500Z "$ESCAPE_ACCOUNT" "$ESCAPE_DIFF")"
"$CASTLE" validate || fail "the escape-sequence fixture does not validate"
CASTLE_REVIEW_RESIZE_COMMAND="" drive_modal "$WORKDIR/review-escape.txt" \
  --mode review --question "$ESCAPE_Q" -- "wait:any other key closes this" "key:x"
[ "$(transcript_rc "$WORKDIR/review-escape.txt")" = "0" ] || fail "the escape-sequence review did not exit 0"

# No raw ESC byte reaches the transcript at all, checked over the whole
# file rather than one section: a control byte that repaints the
# screen does not respect section boundaries either.
ESC_BYTE="$(printf '\033')"
if grep -qF -- "$ESC_BYTE" "$WORKDIR/review-escape.txt"; then
  fail "a raw ESC byte from the tenant's diff or account reached the review transcript"
fi

# And the surrounding text is still there — this is defanging, not
# deletion. Losing either payload string here would mean the fix
# over-corrected into hiding part of the change instead of just the
# control byte.
ESCAPE_OUT="$(tr -d '\r' < "$WORKDIR/review-escape.txt")"
printf '%s\n' "$ESCAPE_OUT" | grep -q "FAKE-DIFF-PAYLOAD" \
  || fail "defanging the diff also deleted its content instead of just the control byte"
printf '%s\n' "$ESCAPE_OUT" | grep -q "FAKE-ACCOUNT-PAYLOAD" \
  || fail "defanging the account also deleted its content instead of just the control byte"

clear_pending_changes

log "status overlay: the verb names what is actually waiting, not always 'answer'"
# _errand_state's ", waiting on you" overlay used to say "press
# Mod4+Shift+a to answer" unconditionally, but a proposal is not
# answered, it is decided (docs/tasks/0025-approval.md §G) — the same
# wrong-verb defect `_show_picker`'s own `action` parameter exists to
# avoid one screen over ("press a number to answer" would name the
# wrong act there too). Three isolated errands, one fixture each, so
# none of them can be left half-decided by a `clear_pending_changes`
# call written for a different section: all proposals says "review"
# (the picker's own word for it); no proposals is already covered by
# REQ_TWOQ earlier in this file and must go on saying "answer",
# unchanged; a mix of both kinds is neither, so it falls back to the
# same kind-agnostic wording this file already reaches for elsewhere
# ("to see what is waiting on them", above run_answer's branch into
# review mode).
REQ_ALLPROP="$("$CASTLE" ask "ALLPROP-FIXTURE: an errand whose only unanswered question is a proposed change.")"
plant_bare_proposal "$REQ_ALLPROP" >/dev/null
"$CASTLE" validate || fail "the all-proposal overlay fixture does not validate"
STATUS_ALLPROP="$("$MODAL" --mode status --limit 40)"
echo "$STATUS_ALLPROP" | grep -q "^\[$REQ_ALLPROP\] requested — waiting on you — press Mod4+Shift+Return to review\$" \
  || fail "an errand waiting on a proposal alone did not say 'review': $(echo "$STATUS_ALLPROP" | grep "$REQ_ALLPROP" || true)"

REQ_MIXED="$("$CASTLE" ask "MIXED-FIXTURE: an errand waiting on both a proposal and an ordinary question.")"
"$CASTLE" record --type question --provenance requested --seat worker \
  --refs "$REQ_MIXED" --body "An ordinary question, not a change." >/dev/null
plant_bare_proposal "$REQ_MIXED" >/dev/null
"$CASTLE" validate || fail "the mixed overlay fixture does not validate"
STATUS_MIXED="$("$MODAL" --mode status --limit 40)"
echo "$STATUS_MIXED" | grep -q "^\[$REQ_MIXED\] requested — waiting on you — press Mod4+Shift+Return to see what's waiting\$" \
  || fail "an errand waiting on both a proposal and an ordinary question did not use the neutral wording: $(echo "$STATUS_MIXED" | grep "$REQ_MIXED" || true)"

# ---------------------------------------------------------------------
# docs/tasks/0034-inbox-modal.md — the inbox layout (--mode inbox).
# ---------------------------------------------------------------------
#
# A fresh state dir, for the same reason every other section here takes
# one: these assertions are about a specific, known ordering and a
# specific, known set of pending items, which cannot be made against a
# journal every earlier section in this file already wrote into.
export CASTLE_STATE_DIR="$WORKDIR/inbox-state"
export XDG_RUNTIME_DIR="$WORKDIR/inbox-runtime"
mkdir -p "$CASTLE_STATE_DIR/journal" "$XDG_RUNTIME_DIR"
INBOX_SEEN="$CASTLE_STATE_DIR/inbox-seen"

# Raw bytes for the two keys pty-drive.py's textual "\n" substitution
# does not cover: Tab (0x09) and Esc (0x1b). "\n" survives as literal
# backslash-n text through bash and is converted by pty-drive.py itself
# (the same mechanism every existing "send:...\n.\n" step in this file
# already relies on); Tab and Esc have no such textual escape there, so
# the real bytes are embedded directly, the same technique this file's
# own $ESC_BYTE (review-mode section, above) already uses to grep for
# a raw Esc in a transcript.
TAB_KEY="key:$(printf '\t')"
ESC_KEY="key:$(printf '\033')"

plant_inbox_proposal() {
  # Usage: plant_inbox_proposal <request-id> <question-body>
  # Echoes the question id. A minimal but RESOLVABLE proposal (a result
  # naming <request-id>, and a question stamped with that result's real
  # hash) — enough for both `_is_proposal` and `_proposal_result` to
  # accept it, unlike plant_bare_proposal above, which is deliberately
  # unresolvable and exists only for review mode's refusal-before-keys
  # path. The inbox digit-open and --focus assertions below need a
  # proposal that actually opens into review mode's rendering.
  local request_id="$1" body="$2"
  local result_id="20260401T000100Z-result-${request_id: -6}"
  local question_id="20260401T000200Z-question-${request_id: -6}"
  cat > "$CASTLE_STATE_DIR/journal/$result_id.md" <<EOF
---
id: $result_id
type: result
provenance: requested
refs: $request_id
seat: worker
created: 2026-04-01T00:01:00Z
outcome: completed
target: private
---

Inbox-proposal fixture result body — not rendered by the picker.
EOF
  cat > "$CASTLE_STATE_DIR/journal/$question_id.md" <<EOF
---
id: $question_id
type: question
provenance: requested
refs: $request_id,$result_id
seat: worker
created: 2026-04-01T00:02:00Z
proposal-sha256: $(sha256sum "$CASTLE_STATE_DIR/journal/$result_id.md" | cut -d' ' -f1)
---

$body
EOF
  echo "$question_id"
}

log "inbox: no read cursor exists in a fresh state dir, and listing an empty inbox does not create one"
[ ! -e "$INBOX_SEEN" ] || fail "inbox-seen already exists in a fresh state dir"
INBOX_EMPTY="$("$MODAL" --mode inbox </dev/null)"
echo "$INBOX_EMPTY" | grep -q "Nothing is waiting on you." \
  || fail "an empty inbox did not say nothing is waiting: $INBOX_EMPTY"
[ ! -e "$INBOX_SEEN" ] || fail "listing an empty inbox created a read cursor — the cursor must be written only on render, not on list"

log "inbox: fixtures — a blocking question, a non-blocking question, a resolvable proposal, and two finished results"
IX_REQ_BLOCKING="$("$CASTLE" ask "Inbox fixture: an errand needing a blocking answer.")"
IX_Q_BLOCKING="$("$CASTLE" record --type question --provenance requested --seat worker \
  --refs "$IX_REQ_BLOCKING" --blocking --body "BLOCKING-Q-MARKER: needs your answer now.")"
IX_REQ_NONBLOCK="$("$CASTLE" ask "Inbox fixture: an errand needing a non-blocking answer.")"
IX_Q_NONBLOCK="$("$CASTLE" record --type question --provenance requested --seat worker \
  --refs "$IX_REQ_NONBLOCK" --body "NONBLOCK-Q-MARKER: needs your answer eventually.")"
IX_REQ_PROP="$("$CASTLE" ask "Inbox fixture: an errand that produced a change to review.")"
IX_Q_PROP="$(plant_inbox_proposal "$IX_REQ_PROP" "PROPOSAL-MARKER: a change worth reviewing.")"
IX_REQ_UNREAD="$("$CASTLE" ask "Inbox fixture: FRESH-RESULT-MARKER, an errand whose worker just finished.")"
IX_RESULT_UNREAD="$("$CASTLE" record --type result --provenance requested --seat worker \
  --refs "$IX_REQ_UNREAD" --body "FRESH-BODY-MARKER: here is the answer you were waiting for.")"
IX_REQ_READ="$("$CASTLE" ask "Inbox fixture: STALE-RESULT-MARKER, an errand already read.")"
IX_RESULT_READ="$("$CASTLE" record --type result --provenance requested --seat worker \
  --refs "$IX_REQ_READ" --body "STALE-BODY-MARKER: this one has already been read.")"
"$CASTLE" validate || fail "the inbox fixtures do not validate"

log "inbox: the read cursor is appended only when a RESULT's body is actually rendered — never for a question or a proposal"
"$MODAL" --mode inbox --focus "$IX_Q_BLOCKING" </dev/null >/dev/null \
  || fail "piped --focus on a question exited nonzero"
[ ! -e "$INBOX_SEEN" ] || fail "opening a QUESTION through --focus wrote to the read cursor"
"$MODAL" --mode inbox --focus "$IX_Q_PROP" </dev/null >/dev/null \
  || fail "piped --focus on a proposal exited nonzero"
[ ! -e "$INBOX_SEEN" ] || fail "opening a PROPOSAL through --focus wrote to the read cursor"

log "inbox: rendering a result's body through --focus appends its id to the read cursor"
FOCUS_READ_OUT="$("$MODAL" --mode inbox --focus "$IX_RESULT_READ" </dev/null)"
echo "$FOCUS_READ_OUT" | grep -q "STALE-BODY-MARKER" \
  || fail "--focus on a result did not render its body: $FOCUS_READ_OUT"
[ -f "$INBOX_SEEN" ] || fail "rendering a result's body did not create the read cursor"
grep -qx "$IX_RESULT_READ" "$INBOX_SEEN" || fail "the read cursor does not name the result that was rendered"
[ "$(wc -l < "$INBOX_SEEN" | tr -d ' ')" = "1" ] || fail "the read cursor has more than one line after exactly one result was rendered"

log "inbox: reading the same result again does not duplicate its line — append-only, never rewritten"
"$MODAL" --mode inbox --focus "$IX_RESULT_READ" </dev/null >/dev/null \
  || fail "re-focusing an already-read result exited nonzero"
[ "$(wc -l < "$INBOX_SEEN" | tr -d ' ')" = "1" ] || fail "re-reading an already-seen result duplicated its line in the cursor"

log "inbox ordering, piped: blocking questions first, then non-blocking, then proposals, then unread results — a read result is absent entirely"
IX_LIST="$("$MODAL" --mode inbox </dev/null)"
echo "$IX_LIST"
echo "$IX_LIST" | grep -q "needs your answer: BLOCKING-Q-MARKER" \
  || fail "the blocking question is not labelled 'needs your answer' in the inbox list"
echo "$IX_LIST" | grep -q "a change to review: PROPOSAL-MARKER" \
  || fail "the proposal is not labelled 'a change to review' in the inbox list"
echo "$IX_LIST" | grep -q "FRESH-RESULT-MARKER" \
  || fail "the unread result's originating request is not named in its 'about:' line"
echo "$IX_LIST" | grep -q "STALE-RESULT-MARKER" \
  && fail "a result the cursor has already seen still appears in the inbox list"
LINE_BLOCKING="$(echo "$IX_LIST" | grep -n "BLOCKING-Q-MARKER" | head -1 | cut -d: -f1)"
LINE_NONBLOCK="$(echo "$IX_LIST" | grep -n "NONBLOCK-Q-MARKER" | head -1 | cut -d: -f1)"
LINE_PROP="$(echo "$IX_LIST" | grep -n "PROPOSAL-MARKER" | head -1 | cut -d: -f1)"
LINE_UNREAD="$(echo "$IX_LIST" | grep -n "FRESH-RESULT-MARKER" | head -1 | cut -d: -f1)"
[ -n "$LINE_BLOCKING" ] && [ -n "$LINE_NONBLOCK" ] && [ -n "$LINE_PROP" ] && [ -n "$LINE_UNREAD" ] \
  || fail "one of the four expected inbox entries did not appear at all"
[ "$LINE_BLOCKING" -lt "$LINE_NONBLOCK" ] \
  || fail "the blocking question did not sort ahead of the non-blocking one"
[ "$LINE_NONBLOCK" -lt "$LINE_PROP" ] \
  || fail "a question sorted after the proposal — questions must come first (docs/tasks/0034 §1)"
[ "$LINE_PROP" -lt "$LINE_UNREAD" ] \
  || fail "the proposal did not sort ahead of the unread result"

log "inbox: --focus lands on and expands a QUESTION directly, skipping the list"
IX_REQ_FOCUS_Q="$("$CASTLE" ask "Focus fixture: a non-blocking question to land on directly.")"
IX_Q_FOCUS="$("$CASTLE" record --type question --provenance requested --seat worker \
  --refs "$IX_REQ_FOCUS_Q" --body "FOCUS-Q-MARKER: direct landing question.")"
"$CASTLE" validate || fail "the focus-question fixture does not validate"
drive_modal "$WORKDIR/ix-focus-question.txt" --mode inbox --focus "$IX_Q_FOCUS" -- \
  "wait:Answer in your own words." "send:.\n" "wait:Press Enter to close" "send:\n"
FOCUS_Q_OUT="$(tr -d '\r' < "$WORKDIR/ix-focus-question.txt")"
echo "$FOCUS_Q_OUT" | grep -q "FOCUS-Q-MARKER" \
  || fail "--focus on a question did not show that question's own text: $FOCUS_Q_OUT"
refute "$FOCUS_Q_OUT" "Waiting on you:" "--focus on a question showed the inbox list first instead of landing directly on it"

log "inbox: --focus lands on and expands a PROPOSAL directly, skipping the list"
IX_REQ_FOCUS_PROP="$("$CASTLE" ask "Focus fixture: a proposal to land on directly.")"
IX_Q_FOCUS_PROP="$(plant_inbox_proposal "$IX_REQ_FOCUS_PROP" "FOCUS-PROP-MARKER: direct landing proposal.")"
"$CASTLE" validate || fail "the focus-proposal fixture does not validate"
drive_modal "$WORKDIR/ix-focus-proposal.txt" --mode inbox --focus "$IX_Q_FOCUS_PROP" -- \
  "wait:any other key closes this" "key:x"
FOCUS_PROP_OUT="$(tr -d '\r' < "$WORKDIR/ix-focus-proposal.txt")"
echo "$FOCUS_PROP_OUT" | grep -q "FOCUS-PROP-MARKER" \
  || fail "--focus on a proposal did not show that proposal's own text: $FOCUS_PROP_OUT"
echo "$FOCUS_PROP_OUT" | grep -q "\[a\]pprove" \
  || fail "--focus on a proposal did not open review mode's rendering"
refute "$FOCUS_PROP_OUT" "Waiting on you:" "--focus on a proposal showed the inbox list first instead of landing directly on it"

log "inbox: --focus lands on and expands a RESULT directly, and Esc backs out ONE level to the list rather than closing the modal"
IX_REQ_FOCUS_RESULT="$("$CASTLE" ask "Focus fixture: a result to land on directly.")"
IX_RESULT_FOCUS="$("$CASTLE" record --type result --provenance requested --seat worker \
  --refs "$IX_REQ_FOCUS_RESULT" --body "FOCUS-RESULT-MARKER: the answer text.")"
"$CASTLE" validate || fail "the focus-result fixture does not validate"
drive_modal "$WORKDIR/ix-focus-result.txt" --mode inbox --focus "$IX_RESULT_FOCUS" -- \
  "wait:Esc to go back." "$ESC_KEY" "wait:Press a number to open" "key:z"
FOCUS_RESULT_OUT="$(tr -d '\r' < "$WORKDIR/ix-focus-result.txt")"
[ "$(transcript_rc "$WORKDIR/ix-focus-result.txt")" = "0" ] \
  || fail "focused result view did not exit 0 after backing out and closing"
echo "$FOCUS_RESULT_OUT" | grep -q "FOCUS-RESULT-MARKER" \
  || fail "--focus on a result did not render its body: $FOCUS_RESULT_OUT"
echo "$FOCUS_RESULT_OUT" | grep -q "Waiting on you:" \
  || fail "Esc from a focused result view did not back out to the inbox list — it closed the whole modal instead"
grep -qx "$IX_RESULT_FOCUS" "$INBOX_SEEN" \
  || fail "the read cursor does not name the focused result after its body was rendered"

log "inbox: the compose view's waiting-count line names the count, and the compose prompt carries the exact new wording (docs/tasks/0034 §4)"
# Six items are pending at this point, not the four the ordering fold
# above showed: the blocking question, the non-blocking question, the
# proposal and IX_RESULT_UNREAD from that fixture set, PLUS the
# question and the proposal from the two --focus "lands directly"
# assertions just above (IX_Q_FOCUS and IX_Q_FOCUS_PROP) — each was
# only VIEWED there (an empty-body refusal, a dismissing keypress),
# never answered or decided, so both are still pending. IX_RESULT_FOCUS
# is the one fixture genuinely excluded: its body was rendered, so the
# read cursor already has it.
JOURNAL_COUNT_BEFORE_ESC="$(find "$CASTLE_STATE_DIR/journal" -name '*.md' | wc -l | tr -d ' ')"
drive_modal "$WORKDIR/ix-ready-line.txt" --mode inbox -- \
  "wait:ready — Tab to view" "$ESC_KEY"
READY_OUT="$(tr -d '\r' < "$WORKDIR/ix-ready-line.txt")"
[ "$(transcript_rc "$WORKDIR/ix-ready-line.txt")" = "0" ] \
  || fail "Esc on a fresh compose view (nothing typed) did not exit 0 — compose's discard semantics should carry over to the inbox layout"
echo "$READY_OUT" | grep -q "^6 ready — Tab to view\$" \
  || fail "the compose view's waiting-count line is wrong: $READY_OUT"
echo "$READY_OUT" | grep -qF "What do you need? Describe it in your own words." \
  || fail "the compose prompt's exact new wording is missing from the inbox layout's compose view"
echo "$READY_OUT" | grep -qF "Describe the problem" \
  && fail "the OLD compose wording ('Describe the problem in your own words') is still present"
JOURNAL_COUNT_AFTER_ESC="$(find "$CASTLE_STATE_DIR/journal" -name '*.md' | wc -l | tr -d ' ')"
[ "$JOURNAL_COUNT_BEFORE_ESC" = "$JOURNAL_COUNT_AFTER_ESC" ] \
  || fail "Esc on the compose view (nothing typed) filed a record anyway"

log "inbox: with nothing pending, the compose view shows no waiting-count line at all"
IX_EMPTY_STATE="$(mktemp -d)"
mkdir -p "$IX_EMPTY_STATE/journal"
CASTLE_STATE_DIR="$IX_EMPTY_STATE" drive_modal "$WORKDIR/ix-empty-ready.txt" --mode inbox -- \
  "wait:What do you need?" "$ESC_KEY"
EMPTY_READY_OUT="$(tr -d '\r' < "$WORKDIR/ix-empty-ready.txt")"
echo "$EMPTY_READY_OUT" | grep -q "ready — Tab to view" \
  && fail "the compose view showed a waiting-count line with nothing pending"

log "inbox: Tab from compose reaches an empty inbox list, which says so and offers compose"
CASTLE_STATE_DIR="$IX_EMPTY_STATE" drive_modal "$WORKDIR/ix-empty-list.txt" --mode inbox -- \
  "wait:What do you need?" "$TAB_KEY" "wait:Nothing is waiting on you." \
  "wait:Press Tab to write something, or any other key to close." "key:z"
[ "$(transcript_rc "$WORKDIR/ix-empty-list.txt")" = "0" ] \
  || fail "closing an empty inbox list did not exit 0"
rm -rf "$IX_EMPTY_STATE"

log "inbox: Tab toggles compose -> inbox and back to compose"
drive_modal "$WORKDIR/ix-tab-toggle.txt" --mode inbox -- \
  "wait:What do you need?" "$TAB_KEY" "wait:Waiting on you:" "$TAB_KEY" "wait:What do you need?" "$ESC_KEY"
[ "$(transcript_rc "$WORKDIR/ix-tab-toggle.txt")" = "0" ] \
  || fail "Tab -> Tab -> Esc did not exit cleanly"

log "inbox: at the top of the list, Esc closes the whole modal — nothing opened, nothing written to the read cursor"
SEEN_LINES_BEFORE="$(wc -l < "$INBOX_SEEN" | tr -d ' ')"
drive_modal "$WORKDIR/ix-list-esc.txt" --mode inbox -- \
  "wait:What do you need?" "$TAB_KEY" "wait:Waiting on you:" "$ESC_KEY"
[ "$(transcript_rc "$WORKDIR/ix-list-esc.txt")" = "0" ] \
  || fail "Esc at the top of the inbox list did not exit 0"
[ "$(wc -l < "$INBOX_SEEN" | tr -d ' ')" = "$SEEN_LINES_BEFORE" ] \
  || fail "closing the list with Esc wrote to the read cursor"

log "inbox: a bare Enter at the list opens nothing (deviation: digit grammar, not Enter) — a reflex key must not mark a result read"
drive_modal "$WORKDIR/ix-list-enter.txt" --mode inbox -- \
  "wait:What do you need?" "$TAB_KEY" "wait:Waiting on you:" "key:\n"
[ "$(transcript_rc "$WORKDIR/ix-list-enter.txt")" = "0" ] \
  || fail "a bare Enter at the inbox list did not exit 0"
[ "$(wc -l < "$INBOX_SEEN" | tr -d ' ')" = "$SEEN_LINES_BEFORE" ] \
  || fail "a bare Enter at the inbox list wrote to the read cursor — it must open nothing"

log "inbox: a digit opens the item at that position — 1 is the blocking question"
drive_modal "$WORKDIR/ix-digit-1.txt" --mode inbox -- \
  "wait:What do you need?" "$TAB_KEY" "wait:Waiting on you:" "key:1" \
  "wait:Answer in your own words." "send:.\n" "wait:Press Enter to close" "send:\n"
DIGIT1_OUT="$(tr -d '\r' < "$WORKDIR/ix-digit-1.txt")"
echo "$DIGIT1_OUT" | grep -q "BLOCKING-Q-MARKER" \
  || fail "pressing 1 in the inbox list did not open the blocking question: $DIGIT1_OUT"

log "inbox: a digit opens the item at that position — 6 is the unread result (two more pending items now sit ahead of it: IX_Q_FOCUS and IX_Q_FOCUS_PROP from the --focus assertions above), and opening it spends the read cursor"
drive_modal "$WORKDIR/ix-digit-6.txt" --mode inbox -- \
  "wait:What do you need?" "$TAB_KEY" "wait:Waiting on you:" "key:6" \
  "wait:Esc to go back." "$ESC_KEY" "wait:Press a number to open" "key:z"
DIGIT6_OUT="$(tr -d '\r' < "$WORKDIR/ix-digit-6.txt")"
[ "$(transcript_rc "$WORKDIR/ix-digit-6.txt")" = "0" ] \
  || fail "digit-open on the unread result did not exit 0"
echo "$DIGIT6_OUT" | grep -q "FRESH-BODY-MARKER" \
  || fail "pressing 6 in the inbox list did not open the unread result: $DIGIT6_OUT"
grep -qx "$IX_RESULT_UNREAD" "$INBOX_SEEN" \
  || fail "opening the unread result through the inbox list did not append it to the read cursor"

log "inbox: with that result now read, it no longer appears in the list"
IX_LIST_2="$("$MODAL" --mode inbox </dev/null)"
echo "$IX_LIST_2" | grep -q "FRESH-RESULT-MARKER" \
  && fail "a result the cursor has now seen still appears in the inbox list"

log "inbox: the compose view files a record exactly like --mode compose (the chord's default view)"
JOURNAL_COUNT_BEFORE_COMPOSE="$(find "$CASTLE_STATE_DIR/journal" -name '*.md' | wc -l | tr -d ' ')"
drive_modal "$WORKDIR/ix-compose-file.txt" --mode inbox -- \
  "wait:What do you need?" "send:Filed via the inbox view.\n.\n" \
  "wait:something to fix" "send:\n" "wait:Filed as" "send:\n"
IX_COMPOSE_OUT="$(tr -d '\r' < "$WORKDIR/ix-compose-file.txt")"
[ "$(transcript_rc "$WORKDIR/ix-compose-file.txt")" = "0" ] \
  || fail "composing through the inbox layout did not exit 0"
echo "$IX_COMPOSE_OUT" | grep -q "Filed as" \
  || fail "composing through the inbox layout did not confirm a filed record: $IX_COMPOSE_OUT"
JOURNAL_COUNT_AFTER_COMPOSE="$(find "$CASTLE_STATE_DIR/journal" -name '*.md' | wc -l | tr -d ' ')"
[ "$JOURNAL_COUNT_AFTER_COMPOSE" -gt "$JOURNAL_COUNT_BEFORE_COMPOSE" ] \
  || fail "composing through the inbox layout did not add a journal record"
IX_FILED_ID="$(echo "$IX_COMPOSE_OUT" | grep -oE '[0-9]{8}T[0-9]{6}Z-request-[a-z0-9]+' | tail -1)"
[ -n "$IX_FILED_ID" ] || fail "could not recover the filed record id from the inbox compose transcript"
grep -q "Filed via the inbox view." "$CASTLE_STATE_DIR/journal/$IX_FILED_ID.md" \
  || fail "the record filed through the inbox compose view does not carry the typed body"

"$CASTLE" validate || fail "the journal does not validate after the inbox-layout assertions"

# ---------------------------------------------------------------------
# docs/tasks/0034-inbox-modal.md §3 — the notification action-waiter
# (`castle notify-waiter`), the detached half of `_fire_notification`.
# ---------------------------------------------------------------------
#
# Faked `swaymsg` and `foot` on $PATH stand in for a real Sway session
# and a real terminal — the brief's own words: "The headless harness
# covers the decision logic (a fake swaymsg on $PATH); the two real-
# window behaviors are part of the one human verification click."
# CASTLE_NOTIFY_COMMAND points at a fake notify-send that logs its argv
# and prints back a controllable action name, the same lever
# notify-stub.sh already gives the router's OWN invocation one process
# earlier — this is the waiter's own invocation, tested directly via
# `castle notify-waiter`, the same internal subcommand the router
# spawns detached.
NW_BIN="$WORKDIR/notify-waiter-bin"
mkdir -p "$NW_BIN"

cat > "$NW_BIN/swaymsg" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SWAYMSG_LOG"
if [ "$1" = "-t" ] && [ "$2" = "get_tree" ]; then
  if [ -f "$SWAY_HAS_MODAL_FILE" ]; then
    printf '%s' '{"app_id": null, "nodes": [], "floating_nodes": [{"app_id": "castle-modal", "nodes": [], "floating_nodes": []}]}'
  else
    printf '%s' '{"app_id": null, "nodes": [], "floating_nodes": []}'
  fi
fi
exit 0
STUB
chmod +x "$NW_BIN/swaymsg"

cat > "$NW_BIN/foot" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FOOT_LOG"
exit 0
STUB
chmod +x "$NW_BIN/foot"

NW_NOTIFY="$WORKDIR/notify-waiter-notify.sh"
cat > "$NW_NOTIFY" <<'STUB'
#!/usr/bin/env bash
# Stands in for notify-send under CASTLE_NOTIFY_COMMAND: logs its full
# argv (so the exact --app-name=castle and --action=open=Open spelling
# can be asserted on) and prints back whatever action name
# NOTIFY_ACTION_FILE names — faking the "activated/dismissed/expired"
# contract the real notify-send's own --wait gives.
printf '%s\n' "$*" >> "$NOTIFY_ARGS_LOG"
[ -f "$NOTIFY_ACTION_FILE" ] && cat "$NOTIFY_ACTION_FILE"
exit 0
STUB
chmod +x "$NW_NOTIFY"

NW_SWAYMSG_LOG="$WORKDIR/nw-swaymsg.log"
NW_FOOT_LOG="$WORKDIR/nw-foot.log"
NW_ARGS_LOG="$WORKDIR/nw-notify-args.log"
NW_ACTION_FILE="$WORKDIR/nw-action"
NW_HAS_MODAL_FILE="$WORKDIR/nw-has-modal"

log "notify-waiter: an existing castle-modal window is focused, not duplicated"
: > "$NW_SWAYMSG_LOG"; : > "$NW_FOOT_LOG"; : > "$NW_ARGS_LOG"
printf 'open\n' > "$NW_ACTION_FILE"
: > "$NW_HAS_MODAL_FILE"
PATH="$NW_BIN:$PATH" CASTLE_NOTIFY_COMMAND="$NW_NOTIFY" \
  SWAYMSG_LOG="$NW_SWAYMSG_LOG" SWAY_HAS_MODAL_FILE="$NW_HAS_MODAL_FILE" FOOT_LOG="$NW_FOOT_LOG" \
  NOTIFY_ARGS_LOG="$NW_ARGS_LOG" NOTIFY_ACTION_FILE="$NW_ACTION_FILE" \
  "$CASTLE" notify-waiter "20260401T000000Z-result-nwfix1" \
    "Castle: your request has an answer" "Fixture notification body." \
  || fail "notify-waiter exited nonzero when an existing window was found"
grep -q -- '--app-name=castle' "$NW_ARGS_LOG" \
  || fail "notify-waiter did not pass --app-name=castle to the notify command"
grep -q -- '--action=open=Open' "$NW_ARGS_LOG" \
  || fail "notify-waiter did not use the --action=open=Open spelling (docs/tasks/0034, implementation deviations)"
grep -q "Castle: your request has an answer" "$NW_ARGS_LOG" \
  || fail "notify-waiter did not pass the title through to the notify command"
grep -qE '\[app_id="castle-modal"\].*focus' "$NW_SWAYMSG_LOG" \
  || fail "notify-waiter did not focus the existing castle-modal window: $(cat "$NW_SWAYMSG_LOG")"
[ ! -s "$NW_FOOT_LOG" ] \
  || fail "notify-waiter launched a second castle-modal window when one already existed: $(cat "$NW_FOOT_LOG")"

log "notify-waiter: with no existing window, it launches one via foot, focused on the record"
: > "$NW_SWAYMSG_LOG"; : > "$NW_FOOT_LOG"; : > "$NW_ARGS_LOG"
rm -f "$NW_HAS_MODAL_FILE"
PATH="$NW_BIN:$PATH" CASTLE_NOTIFY_COMMAND="$NW_NOTIFY" \
  SWAYMSG_LOG="$NW_SWAYMSG_LOG" SWAY_HAS_MODAL_FILE="$NW_HAS_MODAL_FILE" FOOT_LOG="$NW_FOOT_LOG" \
  NOTIFY_ARGS_LOG="$NW_ARGS_LOG" NOTIFY_ACTION_FILE="$NW_ACTION_FILE" \
  "$CASTLE" notify-waiter "20260401T000000Z-result-nwfix2" \
    "Castle: your request has an answer" "Fixture notification body." \
  || fail "notify-waiter exited nonzero when no existing window was found"
[ -s "$NW_FOOT_LOG" ] \
  || fail "notify-waiter did not launch a new castle-modal window when none existed"
grep -q -- '--app-id=castle-modal' "$NW_FOOT_LOG" || fail "the launched window is not tagged app-id=castle-modal"
grep -q -- '--mode inbox' "$NW_FOOT_LOG" || fail "the launched window did not open in inbox mode"
grep -q -- '--focus 20260401T000000Z-result-nwfix2' "$NW_FOOT_LOG" \
  || fail "the launched window was not focused on the record the notification was about"
if grep -qE '\[app_id="castle-modal"\].*focus' "$NW_SWAYMSG_LOG"; then
  fail "notify-waiter tried to focus a window that does not exist"
fi

log "notify-waiter: dismissing or letting the notification expire launches nothing and never touches Sway"
: > "$NW_SWAYMSG_LOG"; : > "$NW_FOOT_LOG"; : > "$NW_ARGS_LOG"
printf 'dismiss\n' > "$NW_ACTION_FILE"
PATH="$NW_BIN:$PATH" CASTLE_NOTIFY_COMMAND="$NW_NOTIFY" \
  SWAYMSG_LOG="$NW_SWAYMSG_LOG" SWAY_HAS_MODAL_FILE="$NW_HAS_MODAL_FILE" FOOT_LOG="$NW_FOOT_LOG" \
  NOTIFY_ARGS_LOG="$NW_ARGS_LOG" NOTIFY_ACTION_FILE="$NW_ACTION_FILE" \
  "$CASTLE" notify-waiter "20260401T000000Z-result-nwfix3" \
    "Castle: your request has an answer" "Fixture notification body." \
  || fail "notify-waiter exited nonzero on a dismissal"
[ ! -s "$NW_SWAYMSG_LOG" ] \
  || fail "notify-waiter queried Sway even though the notification was dismissed, not clicked: $(cat "$NW_SWAYMSG_LOG")"
[ ! -s "$NW_FOOT_LOG" ] \
  || fail "notify-waiter launched a window even though the notification was dismissed, not clicked"

log "notify-waiter: CASTLE_NOTIFY_COMMAND set to the empty string opts out silently, same as the router's own invocation"
: > "$NW_SWAYMSG_LOG"; : > "$NW_FOOT_LOG"; : > "$NW_ARGS_LOG"
PATH="$NW_BIN:$PATH" CASTLE_NOTIFY_COMMAND="" \
  SWAYMSG_LOG="$NW_SWAYMSG_LOG" SWAY_HAS_MODAL_FILE="$NW_HAS_MODAL_FILE" FOOT_LOG="$NW_FOOT_LOG" \
  NOTIFY_ARGS_LOG="$NW_ARGS_LOG" NOTIFY_ACTION_FILE="$NW_ACTION_FILE" \
  "$CASTLE" notify-waiter "20260401T000000Z-result-nwfix4" \
    "Castle: your request has an answer" "Fixture notification body." \
  || fail "notify-waiter exited nonzero with CASTLE_NOTIFY_COMMAND=''"
[ ! -s "$NW_ARGS_LOG" ] || fail "notify-waiter ran a notify command even though CASTLE_NOTIFY_COMMAND was set empty"
[ ! -s "$NW_SWAYMSG_LOG" ] || fail "notify-waiter queried Sway with the notify channel disabled"
[ ! -s "$NW_FOOT_LOG" ] || fail "notify-waiter launched a window with the notify channel disabled"


log "all assertions passed"
