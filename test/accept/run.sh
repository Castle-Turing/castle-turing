#!/usr/bin/env bash
# test/accept/run.sh — the acceptance harness's own checks, checked
# (docs/tasks/0080-the-acceptance-harness.md).
#
# Three halves, and the middle one is the one that matters.
#
# The first runs `accept run` over the worked example and `accept check`
# over the receipt committed beside it, and expects both to pass. That
# proves the fixtures are well-formed and nothing more.
#
# The second mutates a brief or a receipt, one defect at a time, and
# expects each mutation to be caught *by the specific rule that owns
# it*. A lint nobody has watched fail is indistinguishable from a lint
# that cannot fail — `sway --validate` accepted a config with no way to
# exit, and this repo has the scar — so every mutation asserts on the
# rule name in the output rather than merely on a non-zero exit. A defect
# caught by the wrong rule is a failure here.
#
# The third builds throwaway git repositories, because the frozen rule is
# the one rule that reads history: a criterion edited on the branch being
# measured against it has to be flagged, and a branch that edited nothing
# has to pass. Both directions, since a freeze check that flagged
# everything would be satisfied by a tool that never compared anything.
#
# Plain bash and stdlib python3, no Nix: `accept` is a single stdlib
# script, the same reasoning test/plan/run.sh gives for itself.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ACCEPT="$REPO_ROOT/tools/accept/accept"
ORACLE="$REPO_ROOT/tools/accept/oracle"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/accept-test.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

# Git needs an identity and must not read the caller's, so the fixture
# repositories below declare their own. A test that depended on the
# machine's git config would pass here and fail on a runner.
export GIT_AUTHOR_NAME="accept test" GIT_AUTHOR_EMAIL="accept@example.invalid"
export GIT_COMMITTER_NAME="accept test" GIT_COMMITTER_EMAIL="accept@example.invalid"

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
# mutation caught by the wrong check is a failure rather than a pass. The
# brackets are load-bearing: an unanchored substring match makes `form`
# match "malformed" and `criteria` match `criterion`, which would defeat
# the point of asserting on the rule at all.
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

# A brief carrying exactly the fields a case needs. Every fixture brief
# is written from scratch rather than mutated out of the worked example:
# the worked example's checks run against this repository's own log, and
# a case about the format should not fail because that log changed.
brief() {
    local name="$1"
    shift
    local dir="$WORKDIR/$name"
    mkdir -p "$dir"
    printf '%s\n' "$@" > "$dir/brief.md"
    printf '\n%s\n' "The body, which carries no fields." >> "$dir/brief.md"
    echo "$dir/brief.md"
}

echo "== the worked example =="

# The end-to-end case the brief's verification plan names: the harness
# run against a real, already-merged task's criteria, in this
# repository's own invocation paths.
expect_pass "run (the worked example, against this repository)" \
    "$ACCEPT" run "$ORACLE/brief.md" --root "$REPO_ROOT" -o "$WORKDIR/fresh.md"

# A receipt has to cite what it exercised. A run that passed while
# reporting nothing would satisfy every rule above and be worthless.
for needle in \
    "tools/outcomes/outcomes check --no-base" \
    "exit: 0" \
    "## Criterion 4 — not exercised here" \
    "manual: the resident picks a row"
do
    grep -qF "$needle" "$WORKDIR/fresh.md" \
        || fail "the receipt does not cite $needle"
done
echo "  ok   the receipt cites the commands it ran and the step it did not take"

expect_pass "check (the receipt committed beside the example)" \
    "$ACCEPT" check "$ORACLE/receipt.md"

echo "== a brief's criteria =="

B="$(brief no-criteria "Title: nothing to run" "Model: cheap")"
expect_catch "a brief with no criteria at all" criteria -- \
    "$ACCEPT" run "$B"

B="$(brief no-disposition "Title: a criterion nobody can answer" \
    "Criterion: the thing works in its real invocation path")"
expect_catch "a criterion with no Check: or Manual:" criteria -- \
    "$ACCEPT" run "$B"

B="$(brief empty-check "Title: a check with no command" \
    "Criterion: the thing works" "Check:")"
expect_catch "a Check: with no command" criteria -- \
    "$ACCEPT" run "$B"

B="$(brief empty-manual "Title: a manual step nobody named" \
    "Criterion: the thing works" "Manual:")"
expect_catch "a Manual: naming no step" criteria -- \
    "$ACCEPT" run "$B"

B="$(brief two-dispositions "Title: two answers to one criterion" \
    "Criterion: the thing works" "Check: true" "Manual: a person looks")"
expect_catch "a criterion carrying both a Check: and a Manual:" form -- \
    "$ACCEPT" run "$B"

B="$(brief orphan-disposition "Title: an answer to nothing" "Check: true")"
expect_catch "a Check: with no Criterion: above it" form -- \
    "$ACCEPT" run "$B"

# The field block is contiguous from the top and ends at the first blank
# line, exactly as `plan` reads a brief in a slate. A criterion below it
# is read by nothing — which is indistinguishable, from the outside, from
# a criterion that passed.
mkdir -p "$WORKDIR/below-block"
cat > "$WORKDIR/below-block/brief.md" <<'EOF'
Title: a criterion outside the block
Criterion: the thing works
Check: true

Criterion: the one nobody reads
Check: false
EOF
expect_catch "a Criterion: below the field block" form -- \
    "$ACCEPT" run "$WORKDIR/below-block/brief.md"

# Positive control for the same rule. A format rule proved only by its
# failures can be satisfied by a parser that reads nothing at all, so a
# wrapped check has to be shown actually running as one command.
B="$(brief wrapped "Title: a check that wraps" \
    "Criterion: the wrapped command runs as one command" \
    "Check: test \"one" "    two\" = \"one two\"")"
expect_pass "a Check: wrapped over two lines runs as one command" \
    "$ACCEPT" run "$B" --root "$WORKDIR"

echo "== what a run observes =="

B="$(brief failing "Title: a criterion that does not hold" \
    "Criterion: the invocation path shows what the criterion says" \
    "Check: false")"
expect_catch "a criterion whose check exits non-zero" criterion -- \
    "$ACCEPT" run "$B" -o "$WORKDIR/failed.md"
grep -qF "## Criterion 1 — observed differently from what the criterion states" \
    "$WORKDIR/failed.md" \
    || fail "the receipt does not report the criterion as observed differently"
echo "  ok   the failing criterion is reported as such in the receipt"

B="$(brief missing-command "Title: a check naming no such command" \
    "Criterion: the built artifact answers in its real path" \
    "Check: definitely-not-a-command-on-this-host --please")"
expect_catch "a check whose command does not exist" escalate -- \
    "$ACCEPT" run "$B" -o "$WORKDIR/escalated.md"
grep -qF "## Criterion 1 — could not be exercised; escalated to the resident" \
    "$WORKDIR/escalated.md" \
    || fail "the receipt does not report the criterion as escalated"
echo "  ok   a command that could not run escalates rather than reading as a failure"

B="$(brief slow "Title: a check that does not finish" \
    "Criterion: the path answers promptly" "Check: sleep 30")"
expect_catch "a check that outlasts the timeout" escalate -- \
    "$ACCEPT" run "$B" --timeout 1

B="$(brief manual-only "Title: nothing here is executable" \
    "Criterion: the resident sees the redesigned surface" \
    "Manual: the resident opens the modal and says whether it is the comp")"
expect_catch "a brief no criterion of which is executable" vacuous -- \
    "$ACCEPT" run "$B" -o "$WORKDIR/manual.md"
grep -qF "manual: the resident opens the modal" "$WORKDIR/manual.md" \
    || fail "the receipt does not name the manual step that stands in"
echo "  ok   the manual step is named in the receipt of the run that exercised nothing"

B="$(brief cycles "Title: a repair loop that will not stop" \
    "Criterion: the thing works" "Check: true")"
expect_catch "a repair cycle past the cap" cycles -- \
    "$ACCEPT" run "$B" --cycle 4 --cap 3 -o "$WORKDIR/never.md"
[ -f "$WORKDIR/never.md" ] \
    && fail "a run refused at the cap still wrote a receipt"
echo "  ok   nothing is run and no receipt is written past the cap"

echo "== the receipt's own lint =="

RECEIPT="$WORKDIR/fresh.md"

# The claim lint. The vocabulary is banned in the receipt's own prose,
# and the mutation goes in a plain paragraph rather than in a quote or a
# transcript — which is exactly the distinction the two controls below
# hold the masking to.
mutate_receipt() {
    local name="$1"
    local dir="$WORKDIR/receipt-$name"
    mkdir -p "$dir"
    cp "$RECEIPT" "$dir/receipt.md"
    echo "$dir/receipt.md"
}

R="$(mutate_receipt claim)"
printf '\n%s\n' "The work is complete and was delivered successfully." >> "$R"
expect_catch "completion vocabulary in a receipt's own prose" claim -- \
    "$ACCEPT" check "$R"

R="$(mutate_receipt claim-quoted)"
printf '\n%s\n' "> the feature is complete when the modal opens on the chord" >> "$R"
expect_pass "the same vocabulary inside a quoted criterion" \
    "$ACCEPT" check "$R"

R="$(mutate_receipt claim-transcript)"
printf '\n%s\n' "    | ok: test_completes_cleanly ... success" >> "$R"
expect_pass "the same vocabulary inside a captured transcript" \
    "$ACCEPT" check "$R"

R="$(mutate_receipt no-limit)"
python3 - "$R" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
cut = text.index("What this run observed is that")
open(path, "w", encoding="utf-8").write(text[:cut])
PY
expect_catch "a receipt with the standing limit removed" form -- \
    "$ACCEPT" check "$R"

R="$(mutate_receipt reworded-limit)"
python3 - "$R" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
open(path, "w", encoding="utf-8").write(
    text.replace("It is not a judgment that the work is what the resident asked",
                 "It is a judgment that the work is what the resident asked"))
PY
expect_catch "a receipt whose standing limit was reworded" form -- \
    "$ACCEPT" check "$R"

R="$(mutate_receipt invented-phrase)"
sed -i 's/^## Criterion 1 — .*/## Criterion 1 — acceptance passed/' "$R"
expect_catch "an outcome phrase the format does not have" form -- \
    "$ACCEPT" check "$R"

R="$(mutate_receipt renumbered)"
sed -i 's/^## Criterion 2 — /## Criterion 3 — /' "$R"
expect_catch "criterion sections that skip a number" form -- \
    "$ACCEPT" check "$R"

R="$(mutate_receipt no-exit)"
sed -i '0,/^    exit: /{/^    exit: /d}' "$R"
expect_catch "a criterion reported as exercised with no exit status" grounding -- \
    "$ACCEPT" check "$R"

R="$(mutate_receipt no-quote)"
python3 - "$R" <<'PY'
import sys
path = sys.argv[1]
lines = open(path, encoding="utf-8").read().splitlines(keepends=True)
out, dropping = [], False
for line in lines:
    if line.startswith("## Criterion 1 "):
        dropping = True
        out.append(line)
        continue
    if dropping and line.startswith(">"):
        continue
    if dropping and line.startswith("    "):
        dropping = False
    out.append(line)
open(path, "w", encoding="utf-8").write("".join(out))
PY
expect_catch "a criterion reported without quoting the criterion" grounding -- \
    "$ACCEPT" check "$R"

R="$(mutate_receipt no-header)"
sed -i '/^Cycle: /d' "$R"
expect_catch "a receipt with no Cycle: header" form -- \
    "$ACCEPT" check "$R"

R="$(mutate_receipt no-manual-step)"
sed -i 's/^    manual: .*/    manual:/' "$R"
expect_catch "a manual criterion naming no step" grounding -- \
    "$ACCEPT" check "$R"

echo "== the frozen rule =="

# A throwaway repository per case: the criteria as committed on the base
# against the criteria as they stand on the branch.
freeze_repo() {
    local name="$1"
    local dir="$WORKDIR/git-$name"
    mkdir -p "$dir"
    git -C "$dir" init -q -b main
    cat > "$dir/brief.md" <<'EOF'
Title: the criteria as the resident approved them
Criterion: the documented step answers in its real invocation path
Check: true
Criterion: the second thing the resident asked for
Check: true
EOF
    git -C "$dir" add brief.md
    git -C "$dir" commit -qm "the brief, before any implementation exists"
    git -C "$dir" checkout -q -b implementing
    echo "$dir"
}

D="$(freeze_repo untouched)"
expect_pass "a branch that edited no criterion" \
    "$ACCEPT" run "$D/brief.md" --base main --root "$D"

D="$(freeze_repo widened)"
sed -i 's/^Check: true$/Check: true # widened/' "$D/brief.md"
expect_catch "a criterion edited on the implementing branch" frozen -- \
    "$ACCEPT" run "$D/brief.md" --base main --root "$D"

D="$(freeze_repo deleted)"
sed -i '/^Criterion: the second thing/,+1d' "$D/brief.md"
expect_catch "a criterion deleted on the implementing branch" frozen -- \
    "$ACCEPT" run "$D/brief.md" --base main --root "$D"

D="$(freeze_repo added)"
printf '%s\n' "Criterion: one the implementer thought of later" "Check: true" \
    >> "$D/brief.md"
python3 - "$D/brief.md" <<'PY'
import sys
# The appended fields have to be inside the field block, which ends at
# the first blank line — otherwise this case would be caught by `form`
# for being below it, and would prove nothing about the frozen rule.
path = sys.argv[1]
lines = open(path, encoding="utf-8").read().splitlines()
fields = [l for l in lines if l and not l.startswith("#")]
open(path, "w", encoding="utf-8").write("\n".join(fields) + "\n")
PY
expect_catch "a criterion added on the implementing branch" frozen -- \
    "$ACCEPT" run "$D/brief.md" --base main --root "$D"

D="$(freeze_repo unborn)"
cp "$D/brief.md" "$D/second.md"
expect_catch "a brief that does not exist on the base at all" frozen -- \
    "$ACCEPT" run "$D/second.md" --base main --root "$D"

D="$(freeze_repo noref)"
expect_die "a base ref that does not resolve" "no merge base" -- \
    "$ACCEPT" run "$D/brief.md" --base no-such-ref --root "$D"

mkdir -p "$WORKDIR/nogit"
cp "$WORKDIR/git-untouched/brief.md" "$WORKDIR/nogit/brief.md" 2>/dev/null \
    || cp "$ORACLE/brief.md" "$WORKDIR/nogit/brief.md"
if [ -n "$(git -C "$WORKDIR/nogit" rev-parse --show-toplevel 2>/dev/null)" ]; then
    # The scratch directory is itself inside a checkout (TMPDIR under a
    # repository), so this one case cannot be built here. Said out loud
    # rather than skipped silently.
    echo "  --   a brief outside any checkout: not testable with TMPDIR inside a repository"
else
    expect_die "--base outside a git checkout" "not inside a git checkout" -- \
        "$ACCEPT" run "$WORKDIR/nogit/brief.md" --base main
fi

echo "== the vocabulary has one home =="

# The banned list is duplicated between `accept` and
# `tools/handover-check.py` on purpose — each tool is one stdlib file
# that runs on its own — and the cost of a copy is drift, which in a lint
# is silent. So the copies are held identical here rather than by hope.
python3 - "$REPO_ROOT" <<'PY'
import ast
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
lists = {}
for rel in ("tools/accept/accept", "tools/handover-check.py"):
    tree = ast.parse((root / rel).read_text(encoding="utf-8"))
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and any(
            isinstance(t, ast.Name) and t.id == "BANNED" for t in node.targets
        ):
            lists[rel] = [e.value for e in node.value.elts]
if len(lists) != 2:
    sys.exit("could not find a BANNED list in both tools: found %s" % sorted(lists))
first, second = lists["tools/accept/accept"], lists["tools/handover-check.py"]
if first != second:
    only_a = [w for w in first if w not in second]
    only_b = [w for w in second if w not in first]
    sys.exit(
        "the two completion-vocabulary lists have drifted; only in accept: %s; "
        "only in handover-check.py: %s" % (only_a, only_b)
    )
print("  ok   accept and handover-check.py ban the same %d words" % len(first))
PY

echo
echo "test/accept/run.sh: every case above behaved as its own line says."
