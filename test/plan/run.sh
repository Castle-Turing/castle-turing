#!/usr/bin/env bash
# test/plan/run.sh — the planner seat's checks, checked
# (docs/tasks/0079-the-planner-seat.md).
#
# Two halves, and the second is the one that matters.
#
# The first half runs `plan check` over the worked example and expects
# it to pass. That proves the fixture is well-formed and nothing more.
#
# The second half mutates the worked example, one defect at a time, and
# expects each mutation to be caught *by the specific rule that owns
# it*. A lint nobody has watched fail is indistinguishable from a lint
# that cannot fail: `sway --validate` accepted a config with one
# keybinding and no way to exit, and this repo has the scar. So every
# mutation asserts on the rule name in the output, not merely on a
# non-zero exit — a check that failed for an unrelated reason would
# otherwise look exactly like a check that worked.
#
# Two of the cases below are positive controls rather than mutations: a
# clause deferred *with* a reason passes, and a wrapped field value is
# actually read. A format rule proved only by its failures can be
# satisfied by a parser that reads nothing at all.
#
# Plain bash and stdlib python3, no Nix: `plan` is a single stdlib
# script, the same reasoning test/clarify/run.sh gives for itself.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLAN="$REPO_ROOT/tools/plan/plan"
ORACLE="$REPO_ROOT/tools/plan/oracle"
REQUIREMENTS="$REPO_ROOT/tools/clarify/probes/cursor-too-small/oracle/requirements.md"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/plan-test.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# Run a command, capture output and status, print both on an unexpected
# result so a red run says what happened rather than only that it did.
OUT=""
STATUS=0
run() {
    set +e
    OUT="$("$@" 2>&1)"
    STATUS=$?
    set -e
}

expect_pass() {
    local what="$1"
    shift
    run "$@"
    if [ "$STATUS" -ne 0 ]; then
        echo "$OUT" >&2
        fail "$what: expected exit 0, got $STATUS"
    fi
    echo "  ok   $what"
}

# expect_catch <what> <rule> -- <command...>
# The command must exit non-zero AND the output must name the rule, so a
# mutation caught by the wrong check is a failure rather than a pass.
# The brackets are load-bearing: an unanchored substring match makes
# `edges` match a message that merely uses the word, and `form` match
# "malformed", which would defeat the point of asserting on the rule.
expect_catch() {
    local what="$1" rule="$2"
    shift 3 # what, rule, --
    run "$@"
    if [ "$STATUS" -eq 0 ]; then
        echo "$OUT" >&2
        fail "$what: expected a non-zero exit, got 0 — the defect was not caught"
    fi
    if ! grep -qF "[$rule]" <<<"$OUT"; then
        echo "$OUT" >&2
        fail "$what: caught, but not by [$rule]"
    fi
    echo "  ok   $what (caught by $rule)"
}

# expect_die <what> <substring> -- <command...>
# For refusals that are SystemExit messages rather than findings, and so
# carry no rule bracket.
expect_die() {
    local what="$1" needle="$2"
    shift 3 # what, needle, --
    run "$@"
    if [ "$STATUS" -eq 0 ]; then
        echo "$OUT" >&2
        fail "$what: expected a non-zero exit, got 0"
    fi
    if ! grep -qF "$needle" <<<"$OUT"; then
        echo "$OUT" >&2
        fail "$what: refused, but not for '$needle'"
    fi
    echo "  ok   $what (refused: $needle)"
}

# Lay down a fresh copy of the worked example and print its path. Each
# case gets its own directory: a mutation left behind would quietly
# change the meaning of every case after it.
#
# The two path headers are rewritten to absolute paths on the way in.
# The slate's own `Requirements:` and `Tasks:` are relative to the slate
# — which is what makes a slate movable — and a copy in a scratch
# directory would resolve both to nothing, so every case after the first
# would "pass" by checking against a missing document.
mutate() {
    local name="$1"
    local dir="$WORKDIR/$name"
    mkdir -p "$dir"
    python3 - "$ORACLE/slate.md" "$dir/slate.md" "$REQUIREMENTS" "$ORACLE/tasks" <<'PY'
import sys
src, dst, requirements, tasks = sys.argv[1:5]
text = open(src, encoding="utf-8").read()
out = []
for line in text.splitlines(keepends=True):
    if line.startswith("Requirements:"):
        out.append(f"Requirements: {requirements}\n")
    elif line.startswith("Tasks:"):
        out.append(f"Tasks: {tasks}\n")
    else:
        out.append(line)
open(dst, "w", encoding="utf-8").write("".join(out))
PY
    echo "$dir"
}

# Drop one field line and any indented continuation lines under it.
drop_field() {
    python3 - "$1" "$2" <<'PY'
import sys
path, key = sys.argv[1], sys.argv[2]
out, dropping = [], False
for line in open(path, encoding="utf-8"):
    if line.startswith(key + ":"):
        dropping = True
        continue
    if dropping and line[:1].isspace() and line.strip():
        continue
    dropping = False
    out.append(line)
open(path, "w", encoding="utf-8").writelines(out)
PY
}

# Append a line at the end of the slate, which is where `## Coverage` is.
append_coverage() {
    printf '%s\n' "$2" >>"$1"
}

echo "== the worked example passes =="
expect_pass "check (the oracle slate)" "$PLAN" check "$ORACLE/slate.md"

# The index is derived rather than authored, so it has to actually name
# the briefs: a derived map that silently came out empty would leave
# every coverage rule passing over nothing.
run "$PLAN" check "$ORACLE/slate.md"
grep -q "cursor-visible-size  *0003" <<<"$OUT" ||
    { echo "$OUT" >&2; fail "the derived index does not map cursor-visible-size to 0003"; }
grep -q "1 unspent" <<<"$OUT" ||
    { echo "$OUT" >&2; fail "the run does not print the unspent budget"; }
grep -q "open ambiguity" <<<"$OUT" ||
    { echo "$OUT" >&2; fail "the run does not surface the requirements document's open ambiguities"; }
echo "  ok   the derived index, the budget slack and the open ambiguities are printed"

# The standing limit is part of the output, not part of the prose about
# the output. A green run that did not say what it had not checked would
# be the promotion Proposal 06 forbids, arriving through this tool.
grep -q "the form, not the decomposition" <<<"$OUT" ||
    { echo "$OUT" >&2; fail "a passing run does not state what it did not check"; }
echo "  ok   a passing run states what it did not check"

echo
echo "== coverage: a clause is traced, or deferred with a reason, or the slate fails =="

DIR="$(mutate coverage-uncovered)"
sed -i 's/^Traces: cursor-visible-size, cursor-target-host$/Traces: cursor-visible-size/' "$DIR/slate.md"
expect_catch "a clause carried by no brief and deferred by nothing" coverage -- \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate coverage-deferred-with-reason)"
sed -i 's/^Traces: cursor-visible-size, cursor-target-host$/Traces: cursor-visible-size/' "$DIR/slate.md"
append_coverage "$DIR/slate.md" \
    "Deferred: cursor-target-host — constraint-level and inferred; which host is read off the deployment."
expect_pass "the same clause deferred with a reason" "$PLAN" check "$DIR/slate.md"

DIR="$(mutate coverage-empty-reason)"
sed -i 's/^Traces: cursor-visible-size, cursor-target-host$/Traces: cursor-visible-size/' "$DIR/slate.md"
append_coverage "$DIR/slate.md" "Deferred: cursor-target-host —"
expect_catch "a deferral with an empty reason" coverage -- \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate coverage-no-dash)"
sed -i 's/^Traces: cursor-visible-size, cursor-target-host$/Traces: cursor-visible-size/' "$DIR/slate.md"
append_coverage "$DIR/slate.md" "Deferred: cursor-target-host"
expect_catch "a deferral with no reason at all" coverage -- \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate coverage-both)"
append_coverage "$DIR/slate.md" \
    "Deferred: cursor-target-host — deferred and traced at the same time."
expect_catch "a clause both traced and deferred" coverage -- \
    "$PLAN" check "$DIR/slate.md"

echo
echo "== grounding: a brief serves a clause that exists, or it is invented scope =="

DIR="$(mutate grounding-invented)"
sed -i 's/^Traces: cursor-surface, cursor-value-by-sweep$/Traces: cursor-surface, cursor-theme-name/' "$DIR/slate.md"
expect_catch "a brief tracing a clause nobody required" grounding -- \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate grounding-no-traces)"
drop_field "$DIR/slate.md" Traces
expect_catch "a brief with no Traces: at all" grounding -- \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate grounding-invented-deferral)"
append_coverage "$DIR/slate.md" \
    "Deferred: cursor-theme-name — a deferral of something nobody required."
expect_catch "a deferral of a clause that does not exist" grounding -- \
    "$PLAN" check "$DIR/slate.md"

echo
echo "== obligations: what every brief owes, checked for presence =="

DIR="$(mutate obligations-no-model-because)"
drop_field "$DIR/slate.md" Model-because
expect_catch "a brief with a tier and no reason for it" obligations -- \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate obligations-empty-model-because)"
drop_field "$DIR/slate.md" Model-because
sed -i '0,/^Milestone: none/s//Model-because:\nMilestone: none/' "$DIR/slate.md"
expect_catch "a Model-because: line with nothing after it" obligations -- \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate obligations-no-model)"
drop_field "$DIR/slate.md" Model
expect_catch "a brief with no Model: at all" obligations -- \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate obligations-no-milestone)"
drop_field "$DIR/slate.md" Milestone
expect_catch "a brief with no Milestone:" obligations -- \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate obligations-no-criterion)"
drop_field "$DIR/slate.md" Criterion
expect_catch "a brief whose verification plan is empty" obligations -- \
    "$PLAN" check "$DIR/slate.md"

# A criterion's disposition — `Check:` with the command that exercises it,
# `Manual:` with the step a person takes instead — is what the acceptance
# harness runs, and exactly one of them is mandatory (task 0080). A
# criterion carrying neither passes review as a verification plan and
# verifies nothing.
DIR="$(mutate obligations-no-disposition)"
drop_field "$DIR/slate.md" Check
drop_field "$DIR/slate.md" Manual
expect_catch "a criterion with no Check: and no Manual:" obligations -- \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate obligations-empty-disposition)"
sed -i "s|^Check: gh pr view.*|Check:|" "$DIR/slate.md"
expect_catch "a criterion whose Check: names no command" obligations -- \
    "$PLAN" check "$DIR/slate.md"

# The pairing is the part the format could swallow: a disposition binds to
# the criterion above it, so one with no criterion above it answers a
# question nobody asked, and two on one criterion leave a reader unable to
# tell whether it is run or stands aside.
DIR="$(mutate form-orphan-disposition)"
python3 - "$DIR/slate.md" <<'INNER'
import sys
path = sys.argv[1]
lines = open(path, encoding="utf-8").read().splitlines(keepends=True)
out = []
for line in lines:
    if line.startswith("Traces:"):
        out.append("Check: true\n")
    out.append(line)
open(path, "w", encoding="utf-8").write("".join(out))
INNER
expect_catch "a Check: with no Criterion: above it" form -- \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate form-two-dispositions)"
python3 - "$DIR/slate.md" <<'INNER'
import sys
path = sys.argv[1]
lines = open(path, encoding="utf-8").read().splitlines(keepends=True)
out = []
for line in lines:
    out.append(line)
    if line.startswith("Check: gh pr view"):
        out.append("Manual: and a person looks as well\n")
open(path, "w", encoding="utf-8").write("".join(out))
INNER
expect_catch "a criterion carrying both a Check: and a Manual:" form -- \
    "$PLAN" check "$DIR/slate.md"

echo
echo "== budget: the bound on the cheap error =="

DIR="$(mutate budget-exceeded)"
sed -i 's/^Brief-budget: 3$/Brief-budget: 1/' "$DIR/slate.md"
expect_catch "more briefs than the declared budget" budget -- \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate budget-absent)"
sed -i '/^Brief-budget: 3$/d' "$DIR/slate.md"
expect_catch "a slate that declared no budget" header -- \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate budget-zero)"
sed -i 's/^Brief-budget: 3$/Brief-budget: 0/' "$DIR/slate.md"
expect_catch "a budget that admits no briefs" header -- \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate budget-not-a-number)"
sed -i 's/^Brief-budget: 3$/Brief-budget: generous/' "$DIR/slate.md"
expect_catch "a budget that is not a number" header -- \
    "$PLAN" check "$DIR/slate.md"

echo
echo "== the header's own knobs, which empty the rules out rather than weaken them =="

DIR="$(mutate header-no-requirements)"
sed -i '/^Requirements: /d' "$DIR/slate.md"
expect_catch "a slate naming no requirements document" header -- \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate header-missing-requirements)"
sed -i 's|^Requirements: .*$|Requirements: nowhere.md|' "$DIR/slate.md"
expect_catch "a Requirements: header pointing at nothing" header -- \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate header-clauseless-requirements)"
printf '# Not a requirements document\n\nNo keyed clauses here.\n' >"$DIR/empty.md"
sed -i "s|^Requirements: .*$|Requirements: $DIR/empty.md|" "$DIR/slate.md"
expect_catch "a requirements document with no clauses, over which coverage is vacuous" coverage -- \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate header-keyless-clause)"
sed -e 's|^### How the value is picked \[cursor-value-by-sweep\]$|### How the value is picked|' \
    "$REQUIREMENTS" >"$DIR/requirements.md"
sed -i "s|^Requirements: .*$|Requirements: $DIR/requirements.md|" "$DIR/slate.md"
expect_catch "a requirements clause with no key to trace" form -- \
    "$PLAN" check "$DIR/slate.md"

echo
echo "== edges: an edge is a real constraint with a reason, or it silently serialises a sprint =="

DIR="$(mutate edges-cycle)"
python3 - "$DIR/slate.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
# 0003 already requires 0002; make 0002 require 0003 and the ring closes.
text = text.replace(
    "Traces: cursor-surface, cursor-value-by-sweep\n",
    "Traces: cursor-surface, cursor-value-by-sweep\n"
    "Requires: 0003\n"
    "Requires-because: a false edge, closing the ring.\n",
    1,
)
open(path, "w", encoding="utf-8").write(text)
PY
expect_catch "a dependency cycle no order satisfies" edges -- \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate edges-no-reason)"
drop_field "$DIR/slate.md" Requires-because
expect_catch "an edge with no reason for it" edges -- \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate edges-reason-no-edge)"
sed -i '/^Requires: 0002$/d' "$DIR/slate.md"
expect_catch "a reason for an edge that is not declared" edges -- \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate edges-dangling)"
sed -i 's/^Requires: 0002$/Requires: 0099/' "$DIR/slate.md"
expect_catch "an edge to a brief that exists nowhere" edges -- \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate edges-self)"
sed -i 's/^Requires: 0002$/Requires: 0003/' "$DIR/slate.md"
expect_catch "a brief requiring itself" edges -- \
    "$PLAN" check "$DIR/slate.md"

# The cycle finder, over graphs a slate fixture cannot conveniently
# express. Two of these cases are where a naive implementation is wrong:
# a ring reachable only from a node the search enters later (a
# finished-node set that is checked before the on-path set swallows it),
# and two rings sharing a node (a per-node report counts them as one, or
# as four). The deep chain is here because the recursive form of this
# search crashes rather than reporting, and a tool that crashes looks
# like a tool with nothing to say.
python3 - "$PLAN" <<'PY' || fail "the cycle finder is wrong on a graph a fixture cannot express"
import importlib.machinery, pathlib, shutil, sys, tempfile

with tempfile.TemporaryDirectory() as tmp:
    # Imported through a `.py` copy: `plan` is extensionless, and
    # dataclasses needs the module registered under a real name.
    copy = pathlib.Path(tmp) / "planmod.py"
    shutil.copyfile(sys.argv[1], copy)
    sys.path.insert(0, tmp)
    import planmod

    cases = {
        "a chain with no cycle": ({"a": ["b"], "b": ["c"], "c": []}, 0),
        "a three-brief ring": ({"a": ["b"], "b": ["c"], "c": ["a"]}, 1),
        "two disjoint rings": ({"a": ["b"], "b": ["a"], "c": ["d"], "d": ["c"]}, 2),
        "a diamond, which is acyclic": (
            {"a": ["b", "c"], "b": ["d"], "c": ["d"], "d": []}, 0),
        "a ring with a tail into it": ({"t": ["a"], "a": ["b"], "b": ["a"]}, 1),
        "two rings sharing one brief": (
            {"a": ["b"], "b": ["c", "a"], "c": ["b"]}, 2),
        "an empty graph": ({}, 0),
        "an edge out of the slate": ({"a": ["zz"]}, 0),
        "a ring reachable only from a later root": (
            {"z": ["a"], "a": ["b"], "b": ["a"]}, 1),
    }
    n = 20000
    chain = {str(i): [str(i + 1)] for i in range(n)}
    chain[str(n)] = ["0"]
    cases[f"a chain of {n} closing into a ring"] = (chain, 1)

    bad = False
    for name, (graph, want) in cases.items():
        got = planmod.find_cycles(graph)
        if len(got) != want:
            print(f"    {name}: expected {want} cycle(s), got {len(got)}: {got}")
            bad = True
    sys.exit(1 if bad else 0)
PY
echo "  ok   the cycle finder is right on nine graphs, including a 20000-long chain"

echo
echo "== numbers: allocated against the live directory, never from a stale listing =="

DIR="$(mutate numbers-collision)"
sed -i 's/^### The chosen size is what the compositor draws on that host \[0003\]$/### The chosen size is what the compositor draws on that host [0001]/' "$DIR/slate.md"
expect_catch "a number already taken in the tasks directory" numbers -- \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate numbers-duplicate)"
sed -i 's/^### The chosen size is what the compositor draws on that host \[0003\]$/### The chosen size is what the compositor draws on that host [0002]/' "$DIR/slate.md"
expect_catch "two briefs claiming one number" form -- \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate numbers-no-directory)"
sed -i "s|^Tasks: .*$|Tasks: $DIR/not-a-directory|" "$DIR/slate.md"
expect_catch "numbers checked against a directory that is not there" numbers -- \
    "$PLAN" check "$DIR/slate.md"

echo
echo "== form: a field the format would silently drop is refused by name =="

# The reason the field block is contiguous and wraps on indentation
# rather than running to the first blank line: `tools/outcomes/outcomes`
# names this exact format change as the real fix for its own named gap,
# where a wrapped value swallows the header after it.
DIR="$(mutate form-unindented-continuation)"
python3 - "$DIR/slate.md" <<'PY'
import sys
path = sys.argv[1]
out, in_mb = [], False
for line in open(path, encoding="utf-8"):
    if line.startswith("Model-because:"):
        in_mb = True
        out.append(line)
        continue
    if in_mb and line[:1].isspace() and line.strip():
        out.append(line.lstrip())
        continue
    in_mb = False
    out.append(line)
open(path, "w", encoding="utf-8").writelines(out)
PY
expect_catch "a wrapped value whose continuation is not indented" form -- \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate form-value-on-next-line)"
python3 - "$DIR/slate.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
# The value starts on the continuation line. It is still the value: a
# format rule proved only by its failures can be satisfied by a parser
# that reads nothing.
needle = "Model-because: every judgment"
if needle not in text:
    # This case is a positive control, so a mutation that quietly missed
    # would leave the unmodified oracle passing and the check would read
    # as proving something it never touched.
    sys.exit(f"the oracle slate no longer contains {needle!r}; fix this case")
text = text.replace(needle, "Model-because:\n    every judgment", 1)
open(path, "w", encoding="utf-8").write(text)
PY
expect_pass "a value that begins on its continuation line is still read" \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate form-field-below-block)"
python3 - "$DIR/slate.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
text = text.replace(
    "Milestone: none — worked example, not work\n",
    "\nMilestone: none — worked example, not work\n",
    1,
)
open(path, "w", encoding="utf-8").write(text)
PY
expect_catch "a field below the blank line that closes the block" form -- \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate form-duplicate-field)"
sed -i '0,/^Milestone: none/s//Milestone: none — the first\nMilestone: none/' "$DIR/slate.md"
expect_catch "a second Milestone: overwriting the first" form -- \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate form-unknown-field)"
sed -i '0,/^Milestone: none/s//Priority: high\nMilestone: none/' "$DIR/slate.md"
expect_catch "a field name the format does not have" form -- \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate form-keyless-brief)"
sed -i 's/^### The cursor.s size is chosen by looking at candidates on the panel \[0002\]$/### The cursor size is chosen by looking/' "$DIR/slate.md"
expect_catch "a brief heading with no number" form -- \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate form-deferral-in-brief)"
python3 - "$DIR/slate.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
text = text.replace(
    "Milestone: none — worked example, not work\n",
    "Milestone: none — worked example, not work\nDeferred: cursor-target-host — buried where nothing reads it.\n",
    1,
)
open(path, "w", encoding="utf-8").write(text)
PY
expect_catch "a deferral buried inside a brief" form -- \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate form-stranded-brief-field)"
append_coverage "$DIR/slate.md" "Model: cheap"
expect_catch "a brief's field stranded outside every brief" form -- \
    "$PLAN" check "$DIR/slate.md"

DIR="$(mutate form-field-in-header-block)"
sed -i '0,/^Brief-budget: 3$/s//Brief-budget: 3\nDeferred: cursor-target-host — up where only the knobs are read./' \
    "$DIR/slate.md"
expect_catch "a deferral in the header block, where only the knobs are read" form -- \
    "$PLAN" check "$DIR/slate.md"

echo
echo "== the tasks directory: a header travels with the file, a flag is typed at a shell =="

# `--tasks` resolves against the working directory and the header
# against the slate. Getting that backwards is silent: the flag would
# resolve to something under the slate's directory, usually nothing, and
# the `numbers` rule would fail for a reason the caller did not cause.
DIR="$(mutate tasks-flag)"
sed -i '/^Tasks: /d' "$DIR/slate.md"
# `run` rather than a pipeline: this file sets `pipefail`, so piping a
# deliberately-failing command into grep reports the command's status,
# not grep's, and the assertion would read backwards.
expect_pass "--tasks resolves against the working directory" \
    bash -c "cd '$REPO_ROOT' && '$PLAN' check '$DIR/slate.md' --tasks tools/plan/oracle/tasks"

expect_catch "the same slate against the real docs/tasks, where 0002 is taken" numbers -- \
    bash -c "cd '$REPO_ROOT' && '$PLAN' check '$DIR/slate.md' --tasks docs/tasks"

echo
echo "== scaffold: the mechanical half, and it does not pretend to be the other half =="

SCAFFOLD="$WORKDIR/scaffold"
expect_pass "scaffold from a requirements document" \
    "$PLAN" scaffold "$REQUIREMENTS" --out "$SCAFFOLD/slate.md" --budget 3 \
    --tasks "$ORACLE/tasks"

for key in cursor-visible-size cursor-surface cursor-value-by-sweep cursor-target-host; do
    grep -qF "clause: $key" "$SCAFFOLD/slate.md" ||
        fail "the scaffold does not list clause $key; a clause never looked at is a clause missed"
done
echo "  ok   every clause of the requirements document is listed to be placed"

grep -qF "[0002]" "$SCAFFOLD/slate.md" ||
    fail "the scaffold did not allocate the next free number against the tasks directory"
echo "  ok   the next free number is allocated against the tasks directory"

grep -qE '^Deferred: [a-z]' "$SCAFFOLD/slate.md" &&
    fail "the scaffold pre-filled a deferral: silence would pass as a decision"
echo "  ok   no deferral is pre-filled"

# A scaffold whose own output passed would be a slate that looks
# complete while deciding nothing.
expect_catch "the scaffold's own output does not pass check" coverage -- \
    "$PLAN" check "$SCAFFOLD/slate.md"

expect_die "scaffold refuses to overwrite" "pass --force" -- \
    "$PLAN" scaffold "$REQUIREMENTS" --out "$SCAFFOLD/slate.md" --budget 3 \
    --tasks "$ORACLE/tasks"

expect_die "scaffold refuses a budget it was not given" "required" -- \
    "$PLAN" scaffold "$REQUIREMENTS" --out "$WORKDIR/nope.md" \
    --tasks "$ORACLE/tasks"

echo
echo ">>> all checks passed"
