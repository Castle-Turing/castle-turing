#!/usr/bin/env python3
"""test/agent-loop/scripted-worker-blocking-alt.py — the same worker
tenant as scripted-worker-blocking.sh, in a different language and a
different shape (docs/tasks/0023-resume-cold.md §11).

It exists for one assertion: swapping the tenant *between* an errand's
first turn and its resumed one must not break resumption. That is
Proposal 03's re-tenanting claim inside a single errand, a stronger
form of what tenant-swap.sh already proves across whole runs — the
errand boundary is what makes continuation possible, so nothing about
it may depend on the same harness being on both sides of the question.

Same contract as its bash twin (the packet on stdin,
CASTLE_REQUEST_ID/CASTLE_DIFF_FILE/CASTLE_TARGET_FILE/CASTLE_PRIVATE_ROOT and
CASTLE_TEST_CASTLE_BIN in the environment, reasoning on stdout, a diff
or nothing to $CASTLE_DIFF_FILE) and the same two shapes: a
`--blocking` question and nothing else on a first invocation; on a
resumed one — CASTLE_RESUME_ANSWER_IDS set — proof, line by line, of
what the continuation packet actually contained. Deliberately NOT a
copy of scripted-worker-alt.py, which takes two positional arguments,
never reads stdin, and stays byte-for-byte untouched so tenant-swap.sh
keeps meaning what it means.
"""

from __future__ import annotations

import os
import pathlib
import re
import subprocess
import sys


def need(name: str) -> str:
    value = os.environ.get(name, "")
    if not value:
        print(f"scripted-worker-blocking-alt.py: {name} must be set", file=sys.stderr)
        raise SystemExit(2)
    return value


def main() -> int:
    request_id = need("CASTLE_REQUEST_ID")
    diff_file = need("CASTLE_DIFF_FILE")
    target_file = need("CASTLE_TARGET_FILE")
    repo_root = need("CASTLE_PRIVATE_ROOT")
    castle = need("CASTLE_TEST_CASTLE_BIN")

    packet = sys.stdin.read()
    resuming = os.environ.get("CASTLE_RESUME_ANSWER_IDS", "").strip()

    if not resuming:
        question_id = subprocess.run(
            [
                castle, "record",
                "--type", "question",
                "--provenance", "requested",
                "--seat", "worker",
                "--refs", request_id,
                "--blocking",
                "--body",
                f"Blocking fixture question for {request_id}: the errand cannot "
                "continue until this is answered.",
            ],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
        print(f"scripted-worker-blocking-alt: filed blocking question {question_id} and stopped")
        print("scripted-worker-blocking-alt: no work was done on this turn")
        return 0

    print(f"scripted-worker-blocking-alt: RESUMED with {resuming}")

    # Same checks the bash twin makes, for the same reasons: read the
    # boundary token out of the packet's own preamble (it is generated
    # per turn, so nothing can hardcode it — which is exactly what makes
    # a quoted body unable to forge a boundary), then require the
    # section boundary to be a whole line of its own, which is only true
    # if the newline before it came from the renderer rather than from
    # whatever the previous body happened to end with.
    match = re.search(r"CASTLE-PACKET-[0-9a-f]{16}", packet)
    if match is None:
        print(
            "scripted-worker-blocking-alt: the packet declared no section-boundary token",
            file=sys.stderr,
        )
        return 8
    nonce = match.group(0)
    lines = packet.splitlines()
    if f"{nonce} BEGIN a question this errand raised (blocking, answered below)" not in lines:
        print(
            "scripted-worker-blocking-alt: the packet's question boundary is not on a "
            "line of its own",
            file=sys.stderr,
        )
        return 8
    real_answers = lines.count(
        f"{nonce} BEGIN the resident's answer to that question, verbatim"
    )
    print(f"scripted-worker-blocking-alt: real resident-answer sections: {real_answers}")
    for label, needle in (
        ("request", "RESUME-FIXTURE-REQUEST-MARKER"),
        ("question", "the errand cannot continue until this is answered"),
        ("answer", "RESUME-FIXTURE-ANSWER-MARKER"),
    ):
        found = [line for line in packet.splitlines() if needle in line]
        if not found:
            print(
                f"scripted-worker-blocking-alt: the packet did not carry the {label}",
                file=sys.stderr,
            )
            return 5
        print(f"scripted-worker-blocking-alt: packet carried the {label}: {found[0]}")

    # The negative half, same as the bash twin: a correction the
    # harness planted against this errand's request must not be here.
    if "RESUME-FIXTURE-MUST-NOT-REACH-A-TENANT" in packet:
        print(
            "scripted-worker-blocking-alt: the packet leaked a record this seat "
            "must never read",
            file=sys.stderr,
        )
        return 6

    pathlib.Path(diff_file).write_text(
        "--- a/docs/backlog/example-item (synthetic, harness fixture only)\n"
        "+++ b/docs/backlog/example-item (synthetic, harness fixture only)\n"
        "@@ -1 +1 @@\n"
        "-placeholder before the resumed turn\n"
        "+placeholder after the resumed turn\n"
    )
    # Every fixture that produces a diff also declares which checkout
    # it is against, since docs/tasks/0024-config-target.md. This one
    # predates that mechanism — it omitted a target because there was
    # none to omit, not because a diff without one is a shape worth
    # exercising — and a diff with no target now draws a note in the
    # result body saying it cannot be routed.
    pathlib.Path(target_file).write_text("private\n")
    print(
        f"scripted-worker-blocking-alt: finished {request_id} on a resumed turn in {repo_root}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
