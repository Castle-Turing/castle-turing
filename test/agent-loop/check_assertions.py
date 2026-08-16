#!/usr/bin/env python3
"""test/agent-loop/check_assertions.py — independent verification for
test/agent-loop/run.sh (docs/tasks/0008).

Deliberately does NOT import agent/castle. The point of a test harness
is to check the tool under test from the outside; sharing its parser
would mean a bug in castle's own understanding of the record format
could hide behind the exact same bug here. This file re-implements just
enough of the frontmatter format (agent/README.md) to read `type`,
`provenance`, `refs`, and `evidence` back out independently.
"""

from __future__ import annotations

import argparse
import pathlib
import sys


def parse_frontmatter(path: pathlib.Path) -> dict:
    lines = path.read_text().splitlines()
    if not lines or lines[0].strip() != "---":
        raise ValueError(f"{path}: no opening '---' fence")
    fields: dict[str, str] = {}
    i = 1
    while i < len(lines) and lines[i].strip() != "---":
        if lines[i].strip():
            key, _, value = lines[i].partition(":")
            fields[key.strip()] = value.strip()
        i += 1
    if i >= len(lines):
        raise ValueError(f"{path}: no closing '---' fence")
    return fields


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("journal", help="journal directory to check")
    ap.add_argument(
        "--routable-type",
        action="append",
        default=None,
        help="record type the router must have routed (repeatable; default: result, question)",
    )
    args = ap.parse_args()
    routable_types = args.routable_type or ["result", "question"]

    jdir = pathlib.Path(args.journal)
    files = sorted(jdir.glob("*.md"))
    if not files:
        print("FAIL: journal is empty", file=sys.stderr)
        return 1

    records: dict[str, dict] = {}
    for f in files:
        try:
            records[f.stem] = parse_frontmatter(f)
        except ValueError as exc:
            print(f"FAIL: {exc}", file=sys.stderr)
            return 1

    failures: list[str] = []

    decisions = [fields for fields in records.values() if fields.get("type") == "decision"]
    if not decisions:
        failures.append("no decision records found at all")
    for d in decisions:
        if not d.get("evidence", "").strip():
            failures.append(f"decision {d.get('id')} has an empty 'evidence' field")

    # "Nothing was routed silently": every result/question record has at
    # least one decision record whose refs cite it.
    routed_refs: set[str] = set()
    for d in decisions:
        for ref in d.get("refs", "").split(","):
            ref = ref.strip()
            if ref:
                routed_refs.add(ref)

    routable = [fields for fields in records.values() if fields.get("type") in routable_types]
    if not routable:
        failures.append(f"no records of routable type {routable_types} found to check routing against")
    for r in routable:
        if r.get("id") not in routed_refs:
            failures.append(
                f"{r.get('type')} {r.get('id')} was never routed: no decision record references it"
            )

    # Propensity fields (docs/architecture.md's Records section;
    # agent/README.md's "The considered set and the selection
    # propensity"): checked independently of agent/castle's own
    # cmd_validate, same "check the tool from the outside" reasoning as
    # the rest of this file. Only decisions carrying a `channel` field
    # are checked — that's the existing, pre-established signal for "a
    # router-written decision" (agent/README.md: "castle route adds a
    # channel field... to the decision records it writes"), and this
    # harness also plants hand-written decision records without
    # considered/confidence on purpose (the backward-compatibility
    # fixture in run.sh), which must NOT be flagged here.
    for d in decisions:
        if "channel" not in d:
            continue
        channel = d.get("channel", "")
        considered_raw = d.get("considered", "")
        considered = [part.strip() for part in considered_raw.split(",") if part.strip()]
        if not considered:
            failures.append(
                f"decision {d.get('id')} has channel={channel!r} but no non-empty "
                "'considered' field"
            )
        elif channel not in considered:
            failures.append(
                f"decision {d.get('id')} chose channel={channel!r}, which is not "
                f"among the channels it claims to have considered: {considered_raw!r}"
            )
        confidence_raw = d.get("confidence", "")
        try:
            confidence = float(confidence_raw)
        except ValueError:
            failures.append(
                f"decision {d.get('id')} has channel={channel!r} but 'confidence' "
                f"({confidence_raw!r}) does not parse as a float"
            )
        else:
            if not (0.0 <= confidence <= 1.0):
                failures.append(
                    f"decision {d.get('id')}'s confidence ({confidence_raw!r}) is not in [0,1]"
                )

    # docs/tasks/0010-correction-record.md scope 4: resident speech is
    # never "addressed to the resident," so no decision record may ever
    # cite a correction — that would be the router routing the
    # resident's own words back at them. Checked independently of
    # agent/castle's own cmd_route (same "check the tool from the
    # outside" reasoning as the rest of this file): a bug that made
    # cmd_route route corrections would still leave *this* check able to
    # catch it.
    correction_ids = {
        fields.get("id") for fields in records.values() if fields.get("type") == "correction"
    }
    for d in decisions:
        for ref in d.get("refs", "").split(","):
            ref = ref.strip()
            if ref and ref in correction_ids:
                failures.append(
                    f"decision {d.get('id')} routes correction {ref} — corrections must "
                    "never be routed (docs/tasks/0010-correction-record.md scope 4)"
                )

    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        return 1

    print(
        f"OK: {len(files)} record(s), {len(decisions)} decision(s), "
        f"every routable record was routed with cited evidence and well-formed propensity fields"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
