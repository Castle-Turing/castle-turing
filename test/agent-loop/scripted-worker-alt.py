#!/usr/bin/env python3
"""test/agent-loop/scripted-worker-alt.py — a second scripted worker
tenant, deliberately a different shape (Python, not bash) from
test/agent-loop/scripted-worker.sh.

This is docs/tasks/0009-ambient-intake.md's half of Proposal 03's
hardening test (docs/architecture.md): "at least one seat is
successfully re-tenanted (a different model or harness) with no
structural change." test/agent-loop/tenant-swap.sh runs the whole
test/agent-loop/run.sh loop once with each of these two scripts holding
the worker seat and diffs a normalized, id-stripped summary of the two
resulting journals — they have to match exactly for the claim to hold.
That comparison only means something if this script's *behavior*
(what records it writes, with what type/provenance/seat) is identical
to scripted-worker.sh's, even though the implementation — argument
parsing, string building, the language itself — is not. See that
script for the reasoning behind each behavior; this file only repeats
what, not why.
"""

from __future__ import annotations

import subprocess
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: scripted-worker-alt.py <castle-bin> <request-id>", file=sys.stderr)
        return 2
    castle, request_id = sys.argv[1], sys.argv[2]

    shown = subprocess.run(
        [castle, "show", request_id], capture_output=True, text=True, check=True
    ).stdout
    provenance = ""
    for line in shown.splitlines():
        if line.startswith("provenance:"):
            provenance = line.split(":", 1)[1].strip()
            break
    if not provenance:
        print(f"scripted-worker-alt: could not read provenance from {request_id}", file=sys.stderr)
        return 1

    question = subprocess.run(
        [
            castle,
            "record",
            "--type",
            "question",
            "--provenance",
            provenance,
            "--seat",
            "worker",
            "--refs",
            request_id,
            "--fact",
            "scripted-worker-test-fact",
            "--body",
            f"Scripted posture question for {request_id}: fix it and tell you, or explain first?",
        ],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
    print(f"scripted-worker-alt: raised question {question} for {request_id}", file=sys.stderr)

    body = f"""Errand `{request_id}` complete.

This result was produced by test/agent-loop/scripted-worker-alt.py, a
second scripted worker tenant — deliberately a different shape
(Python, not bash) from scripted-worker.sh — with zero model and zero
network involvement. The diff below is synthetic — a fixed string, not
a real repo change — since this harness never touches a working tree:

```diff
--- a/docs/backlog/example-item (synthetic, harness fixture only)
+++ b/docs/backlog/example-item (synthetic, harness fixture only)
@@ -1 +1 @@
-placeholder before
+placeholder after
```
"""

    result = subprocess.run(
        [
            castle,
            "record",
            "--type",
            "result",
            "--provenance",
            provenance,
            "--seat",
            "worker",
            "--refs",
            request_id,
            "--body",
            body,
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    print(result.stdout, end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
