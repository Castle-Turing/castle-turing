#!/usr/bin/env python3
"""test/agent-loop/normalize_journal.py — a record-level (not
id-level) fingerprint of a journal, for test/agent-loop/tenant-swap.sh.

Strips everything that legitimately differs between two runs of the
same loop (ids, timestamps, refs, prose bodies, evidence text — all of
it references or embeds an id, which is randomized per run by
agent/castle's make_id()) and keeps only the shape Proposal 03's
hardening test actually cares about: how many records of what type,
provenance, and seat exist, and which channel each decision assigned.
Two runs of test/agent-loop/run.sh with differently-shaped worker
tenants plugged in should produce byte-identical output from this
script even though no individual record between the two runs matches.

Deliberately reimplements the tiny frontmatter reader rather than
importing agent/castle, for the same "check the tool from the outside"
reason test/agent-loop/check_assertions.py already does.
"""

from __future__ import annotations

import argparse
import pathlib
import sys


def parse_frontmatter(path: pathlib.Path) -> dict:
    lines = path.read_text().splitlines()
    fields: dict[str, str] = {}
    if not lines or lines[0].strip() != "---":
        return fields
    i = 1
    while i < len(lines) and lines[i].strip() != "---":
        if lines[i].strip():
            key, _, value = lines[i].partition(":")
            fields[key.strip()] = value.strip()
        i += 1
    return fields


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("journal", help="journal directory to fingerprint")
    args = ap.parse_args()

    jdir = pathlib.Path(args.journal)
    rows = []
    for path in sorted(jdir.glob("*.md")):
        fields = parse_frontmatter(path)
        rows.append(
            "|".join(
                [
                    fields.get("type", ""),
                    fields.get("provenance", ""),
                    fields.get("seat", ""),
                    fields.get("channel", ""),
                ]
            )
        )
    for row in sorted(rows):
        print(row)
    return 0


if __name__ == "__main__":
    sys.exit(main())
