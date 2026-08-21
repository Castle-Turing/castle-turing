#!/usr/bin/env python3
"""test/agent-loop/pty-drive.py — drive an interactive terminal program
under a real pty and print its transcript.

Extracted from modal-headless-test.sh, which wrote it into $WORKDIR
from a heredoc, when test/agent-loop/approval.sh needed the same driver
(docs/tasks/0025-approval.md). Two copies of a pty driver is two places
for a timing subtlety to be fixed once — and every subtlety in here was
found the hard way: the needle-based wait rather than a quiet-gap
heuristic (a keypress is echoed by the tty driver long before the
program has finished acting on it), and the deliberate sleep before a
single keypress (see the `key` step).

Steps are given after `--`:

  wait:TEXT    block until TEXT appears in the transcript
  key:C        sleep past the cbreak gap, then send C
  send:TEXT    write TEXT verbatim ('\\n' understood)
  sleep:N      wait N seconds
  run:CMD      run CMD through the shell, right here in the sequence

The whole transcript goes to stdout followed by a final RC=<n> line
carrying the child's exit status, so a caller can grep the one and read
the other. The driver exits 2 if a `wait` step times out, which is
distinguishable from every exit code the programs under test produce.
"""

import os
import pty
import select
import subprocess
import sys
import time

argv = sys.argv[1:]
separator = argv.index("--")
command, steps = argv[:separator], argv[separator + 1:]

main_fd, sub_fd = pty.openpty()
proc = subprocess.Popen(command, stdin=sub_fd, stdout=sub_fd, stderr=sub_fd, close_fds=True)
os.close(sub_fd)
transcript = b""


def pump(timeout=0.2):
    """One poll of the pty master. Returns "data", "idle" or "eof".

    Three states rather than a boolean, because two of them used to
    collapse: "I read something" and "I waited and nothing came" both
    returned true, so the final drain below could only ever end on EOF.
    That works while the child's exit closes the last handle on the
    slave — but a grandchild holding the pty open leaves `proc.poll()`
    non-None, the master perfectly healthy, and the drain spinning
    forever with no deadline anywhere to stop it. A harness that hangs
    instead of failing is worse than one that fails.
    """
    global transcript
    ready, _, _ = select.select([main_fd], [], [], timeout)
    if main_fd not in ready:
        return "idle"
    try:
        chunk = os.read(main_fd, 4096)
    except OSError:
        return "eof"
    if not chunk:
        return "eof"
    transcript += chunk
    return "data"


def wait_for(needle: bytes, timeout=15.0) -> bool:
    deadline = time.time() + timeout
    while needle not in transcript and time.time() < deadline:
        if pump() == "eof":
            break
    return needle in transcript


def die(message: str) -> None:
    sys.stderr.write(f"pty-drive: {message}\n")
    sys.stderr.write(transcript.decode(errors="replace") + "\n")
    proc.kill()
    sys.exit(2)


for step in steps:
    kind, _, value = step.partition(":")
    value = value.replace("\\n", "\n")
    if kind == "wait":
        if not wait_for(value.encode()):
            die(f"timed out waiting for {value!r}")
    elif kind == "key":
        # The documented 0.2s gap before a single keypress: printing the
        # prompt and switching the tty into cbreak mode are two separate
        # statements, and a keypress landing between them is held by the
        # kernel's still-canonical line discipline until a newline
        # arrives — which a bare keypress never sends. This sleeps past
        # that window. It is a property of simulating a keystroke at an
        # instant no human types at, not of castle-modal.
        time.sleep(0.2)
        os.write(main_fd, value.encode())
    elif kind == "send":
        os.write(main_fd, value.encode())
    elif kind == "sleep":
        time.sleep(float(value))
    elif kind == "run":
        # Runs *between* two steps, which is the only way a harness can
        # change the world while the program under test is sitting at a
        # prompt. docs/tasks/0025-approval.md's "altered mid-review"
        # case mutates a file after the change is on screen and before
        # the deciding keypress lands, to prove the write path
        # re-derives from disk rather than trusting what it displayed.
        subprocess.run(value, shell=True, check=False)
    else:
        die(f"unknown step {step!r}")

deadline = time.time() + 15
while proc.poll() is None and time.time() < deadline:
    if pump() == "eof":
        break
# The final drain: everything the child wrote before it exited but that
# has not been read yet. It stops on EOF, on the first quiet poll, or
# at a deadline — three exits, because the first is the one that used
# to be the only one and the one a grandchild holding the pty can deny
# forever.
drain_deadline = time.time() + 5
while time.time() < drain_deadline and pump(0.05) == "data":
    pass
try:
    returncode = proc.wait(timeout=5)
except subprocess.TimeoutExpired:
    proc.kill()
    die(f"{command[0]} never exited")

sys.stdout.write(transcript.decode(errors="replace"))
sys.stdout.write(f"\nRC={returncode}\n")
