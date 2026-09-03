#!/usr/bin/env bash
# test/agent-loop/record-order.sh — the shared record ordering
# (docs/tasks/0046-record-ordering-helper.md).
#
# Record ids carry a one-second stamp and a random suffix, so sorting
# records by the whole id is chronological only across seconds: within
# one second the type name decides and then a coin does. That produced a
# defect in four separate tasks before one shared comparison replaced
# the per-surface ones. This harness pins the comparison, and then pins
# the thing that keeps it shared — that no fold in either script has
# gone back to sorting by `rec.id`.
#
# Same conventions as the harnesses next door: plain bash, stdlib
# python3, no Nix, no models, no network. Unlike the others it needs no
# journal on disk at all — the ordering helpers are pure functions of
# the records handed to them, so the fixtures are `Record` objects built
# inline, with ids chosen by hand to put two records in one second on
# purpose. A harness that filed real records and hoped two landed in the
# same second would be a flake; this one makes the collision the input.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

log() { printf '>>> %s\n' "$*"; }

log "ordering rules and the no-bypass guard"
REPO_ROOT="$REPO_ROOT" python3 - <<'PYEOF'
import importlib.machinery
import ast
import importlib.util
import os
import pathlib
import re
import sys

REPO_ROOT = pathlib.Path(os.environ["REPO_ROOT"])


def load(path, name):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


castle = load(REPO_ROOT / "agent" / "castle", "castle_lib")

failures = []


def check(label, condition, detail=""):
    if condition:
        print(f"    ok: {label}")
    else:
        failures.append(f"{label}{': ' + detail if detail else ''}")
        print(f"    FAIL: {label} {detail}")


def rec(record_id, record_type, refs=()):
    return castle.Record(
        {"id": record_id, "type": record_type, "refs": ",".join(refs)}, ""
    )


def ids(records):
    return [r.id for r in records]


def naive(records):
    """What every fold did before this task: sort by the whole id."""
    return [r.id for r in sorted(records, key=lambda r: r.id)]


# ---------------------------------------------------------------------
# Two records in one second, WITH a refs edge between them.
# ---------------------------------------------------------------------
result = rec("20260903T101500Z-result-ffee11", "result", ["20260903T101400Z-request-aaaaaa"])
answer = rec("20260903T101500Z-answer-001122", "answer", ["20260903T101400Z-question-bbbbbb", "20260903T101500Z-result-ffee11"])

check(
    "an edge orders two records written in the same second",
    ids(castle.order_records([answer, result])) == [result.id, answer.id],
    ids(castle.order_records([answer, result])),
)
check(
    "and the naive whole-id sort gets it backwards, which is why this test exists",
    naive([answer, result]) == [answer.id, result.id],
    naive([answer, result]),
)
check(
    "record_is_before follows the edge",
    castle.record_is_before(result, answer) and not castle.record_is_before(answer, result),
)
check(
    "an edge is not a tie",
    ids(castle.tied_for_newest([answer, result])) == [answer.id],
    ids(castle.tied_for_newest([answer, result])),
)
check("newest_record picks the decision", castle.newest_record([answer, result]).id == answer.id)
check("oldest_record picks the result", castle.oldest_record([answer, result]).id == result.id)

# ---------------------------------------------------------------------
# The docs/tasks/0025 case in full: an errand's question, the result
# proposing a change, and the answer deciding it — the answer and the
# result written in the same second, which is what a scripted caller
# does every time and what a resident approving straight off the
# notification does too. `answer` sorts before `result` by alphabet, so
# the old comparison called the decision older than the change it
# decides.
# ---------------------------------------------------------------------
question = rec("20260903T101400Z-question-bbbbbb", "question", ["20260903T101400Z-request-aaaaaa"])
full = [answer, question, result]
check(
    "0025's decision-versus-result tie-break falls out of the shared rule",
    ids(castle.order_records(full)) == [question.id, result.id, answer.id],
    ids(castle.order_records(full)),
)
check(
    "which the naive sort does not",
    naive(full) != [question.id, result.id, answer.id],
    naive(full),
)

# ---------------------------------------------------------------------
# Two records in one second with NO edge between them: a genuine tie.
# The order is arbitrary — the contract is only that it is the same
# arbitrary answer every time, whatever order the caller's fold
# happened to produce, and that the tie is sayable.
# ---------------------------------------------------------------------
tie_a = rec("20260903T102000Z-result-00ff00", "result", ["20260903T101400Z-request-aaaaaa"])
tie_b = rec("20260903T102000Z-result-11aa11", "result", ["20260903T101400Z-request-cccccc"])
check(
    "a genuine tie is not ordered in either direction",
    not castle.record_is_before(tie_a, tie_b) and not castle.record_is_before(tie_b, tie_a),
)
check(
    "tied_for_newest says there are two, rather than picking one",
    sorted(ids(castle.tied_for_newest([tie_a, tie_b]))) == sorted([tie_a.id, tie_b.id]),
    ids(castle.tied_for_newest([tie_a, tie_b])),
)
check(
    "and the arbitrary choice is identical whichever way the fold hands them over",
    ids(castle.order_records([tie_a, tie_b])) == ids(castle.order_records([tie_b, tie_a])),
)
check(
    "a record never ties with itself",
    not castle.record_is_before(tie_a, tie_a),
)

# A chain inside one second: only the end of it is newest, and the
# helpers have to agree about that. `tied_for_newest` checking each
# candidate against `ordered[-1]` alone would call the head of the
# chain tied with its tail — no direct edge, same stamp — while
# excluding the record in between, which is both wrong and a
# contradiction of the order `order_records` returns for the same input
# (this task's code review, finding 1).
chain_a = rec("20260903T103000Z-result-aaaaaa", "result", [])
chain_b = rec("20260903T103000Z-result-bbbbbb", "result", ["20260903T103000Z-result-aaaaaa"])
chain_c = rec("20260903T103000Z-result-cccccc", "result", ["20260903T103000Z-result-bbbbbb"])
chain = [chain_c, chain_a, chain_b]
check(
    "a same-second chain is ordered by its edges",
    ids(castle.order_records(chain)) == [chain_a.id, chain_b.id, chain_c.id],
    ids(castle.order_records(chain)),
)
check(
    "and only the end of the chain is newest — nothing ties with it",
    ids(castle.tied_for_newest(chain)) == [chain_c.id],
    ids(castle.tied_for_newest(chain)),
)
check(
    "the tie is always a tail of the order the same input produces",
    ids(castle.tied_for_newest(full)) == ids(castle.order_records(full))[-len(castle.tied_for_newest(full)):],
)

# ---------------------------------------------------------------------
# A refs edge that contradicts the stamps — a clock that moved, a
# restored journal, two processes disagreeing about the time. The edge
# is evidence and the stamp is a claim, so the edge wins.
# ---------------------------------------------------------------------
skewed_first = rec("20260903T110000Z-result-abcabc", "result", [])
skewed_second = rec("20260903T105900Z-answer-defdef", "answer", ["20260903T110000Z-result-abcabc"])
check(
    "a refs edge beats the stamps even when they contradict it",
    ids(castle.order_records([skewed_second, skewed_first])) == [skewed_first.id, skewed_second.id],
    ids(castle.order_records([skewed_second, skewed_first])),
)
check(
    "record_is_before agrees",
    castle.record_is_before(skewed_first, skewed_second),
)

# ---------------------------------------------------------------------
# Across seconds, with nothing else in play, it is plain chronology.
# ---------------------------------------------------------------------
early = rec("20260901T090000Z-request-aaaaaa", "request", [])
middle = rec("20260902T090000Z-claim-bbbbbb", "claim", [])
late = rec("20260903T090000Z-result-cccccc", "result", [])
check(
    "cross-second ordering is chronological",
    ids(castle.order_records([late, early, middle])) == [early.id, middle.id, late.id],
    ids(castle.order_records([late, early, middle])),
)
check(
    "every record handed in comes back out",
    len(castle.order_records(full + [early, middle, late])) == 6,
)

# ---------------------------------------------------------------------
# Degenerate inputs, including one an append-only journal cannot
# produce: a cycle, which would mean a hand-edited directory. Ordering
# it oddly is fine; raising in a status surface is not.
# ---------------------------------------------------------------------
check("no records has no newest", castle.newest_record([]) is None)
check("no records has no oldest", castle.oldest_record([]) is None)
check("no records tie", castle.tied_for_newest([]) == [])
check("one record is its own order", ids(castle.order_records([early])) == [early.id])

cyc_x = rec("20260903T120000Z-result-aaa111", "result", ["20260903T120000Z-result-ccc333"])
cyc_y = rec("20260903T120000Z-result-bbb222", "result", ["20260903T120000Z-result-aaa111"])
cyc_z = rec("20260903T120000Z-result-ccc333", "result", ["20260903T120000Z-result-bbb222"])
cycle = [cyc_x, cyc_y, cyc_z]
check(
    "a cycle is ordered rather than raised, and ordered the same way twice",
    len(castle.order_records(cycle)) == 3
    and ids(castle.order_records(cycle)) == ids(castle.order_records(list(reversed(cycle)))),
)

# ---------------------------------------------------------------------
# The guard that makes the helper shared rather than merely available.
# Without it, this task lands one correct comparison that the next fold
# is free to not know about — which is exactly the history the task is
# a record of.
# ---------------------------------------------------------------------
# Read with `ast` rather than grepped, because the shape most likely to
# bring id-ordering back is the one this task removed from
# `_inbox_items` — a composite key, wrapped over several lines by the
# repo's own formatting, with `q.id` on a line of its own. A regex over
# lines does not see it, and a guard that passes on the exact case it
# exists to catch is worse than no guard, because `check.yml` and
# `agent/README.md` both advertise this one as load-bearing (this
# task's code review, finding 2).
def sorts_by_record_id(node):
    """Is this `key=` argument ordering records by their whole id?"""
    if isinstance(node, ast.Lambda):
        parameters = {arg.arg for arg in node.args.args}
        return any(
            isinstance(inner, ast.Attribute)
            and inner.attr == "id"
            and isinstance(inner.value, ast.Name)
            and inner.value.id in parameters
            for inner in ast.walk(node.body)
        )
    # `operator.attrgetter("id")` and `functools.partial(getattr, ...)`
    # reach the same place by another spelling.
    if isinstance(node, ast.Call):
        name = node.func.attr if isinstance(node.func, ast.Attribute) else getattr(node.func, "id", "")
        if name in ("attrgetter", "itemgetter"):
            return any(
                isinstance(a, ast.Constant) and a.value == "id" for a in node.args
            )
    return False


def compares_two_record_ids(node):
    """`rec.id > claim.id` — ordering by id without sorting by it."""
    if not isinstance(node, ast.Compare):
        return False
    if not all(isinstance(op, (ast.Lt, ast.LtE, ast.Gt, ast.GtE)) for op in node.ops):
        return False
    operands = [node.left] + list(node.comparators)
    return all(
        isinstance(operand, ast.Attribute) and operand.attr == "id"
        for operand in operands
    )


offenders = []
for name in ("castle", "castle-modal"):
    path = REPO_ROOT / "agent" / name
    tree = ast.parse(path.read_text(), filename=str(path))
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            for keyword in node.keywords:
                if keyword.arg == "key" and sorts_by_record_id(keyword.value):
                    offenders.append(
                        f"agent/{name}:{node.lineno} sorts records by their whole id"
                    )
        if compares_two_record_ids(node):
            offenders.append(
                f"agent/{name}:{node.lineno} compares two record ids directly"
            )
check(
    "no fold sorts records by id behind the shared helper's back",
    not offenders,
    "\n      " + "\n      ".join(offenders) if offenders else "",
)

if failures:
    print(f"\nFAIL: {len(failures)} assertion(s) failed:", file=sys.stderr)
    for failure in failures:
        print(f"  - {failure}", file=sys.stderr)
    print(
        "\nIf the last one failed, the fix is to call castle.order_records / "
        "newest_record / oldest_record / record_is_before rather than sorting "
        "by rec.id — see docs/tasks/0046-record-ordering-helper.md.",
        file=sys.stderr,
    )
    sys.exit(1)
print("\nAll record-ordering assertions passed.")
PYEOF

log "record-order.sh: PASS"
