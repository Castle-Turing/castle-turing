#!/usr/bin/env bash
# test/clarify/run.sh — the clarifying-questions phase's checks, checked
# (docs/tasks/0065-the-clarifying-questions-intake.md).
#
# Two halves, and the second is the one that matters.
#
# The first half runs `clarify` over the worked example and expects it to
# pass. That proves the fixture is well-formed and nothing more.
#
# The second half mutates the worked example, one defect at a time, and
# expects each mutation to be caught *by the specific rule that owns it*.
# A lint nobody has watched fail is indistinguishable from a lint that
# cannot fail: `sway --validate` accepted a config with one keybinding
# and no way to exit, and this repo has the scar. So every mutation
# asserts on the rule name in the output, not merely on a non-zero exit —
# a check that failed for an unrelated reason would otherwise look
# exactly like a check that worked.
#
# Plain bash and stdlib python3, no Nix: `clarify` is a single stdlib
# script, the same reasoning test/agent-loop/run.sh gives for itself.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLARIFY="$REPO_ROOT/tools/clarify/clarify"
PROBE="$REPO_ROOT/tools/clarify/probes/cursor-too-small"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/clarify-test.XXXXXX")"
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
expect_catch() {
	local what="$1" rule="$2"
	shift 3 # what, rule, --
	run "$@"
	if [ "$STATUS" -eq 0 ]; then
		echo "$OUT" >&2
		fail "$what: expected a non-zero exit, got 0 — the defect was not caught"
	fi
	if ! grep -qF "$rule" <<<"$OUT"; then
		echo "$OUT" >&2
		fail "$what: caught, but not by [$rule]"
	fi
	echo "  ok   $what (caught by $rule)"
}

# Lay down a fresh copy of the worked example and apply one mutation to
# it. Each case gets its own directory: a mutation left behind would
# quietly change the meaning of every case after it.
mutate() {
	local name="$1"
	local dir="$WORKDIR/$name"
	mkdir -p "$dir"
	cp "$PROBE/oracle/requirements.md" "$PROBE/oracle/transcript.md" "$dir/"
	echo "$dir"
}

echo "== the worked example passes =="
expect_pass "check (form, questions, read-back)" \
	"$CLARIFY" check "$PROBE/oracle/requirements.md"

echo
echo "== the probe harness =="
RUN="$WORKDIR/probe-run"
expect_pass "probe build" "$CLARIFY" probe build cursor-too-small --out "$RUN"

# Deletion-only editing, proved rather than promised: the seeded
# statement must be obtainable from the source by removing characters.
# The builder asserts this internally; this asserts it again from
# outside, because the builder asserting about itself is a claim.
python3 - "$PROBE/source.md" "$RUN/statement.md" <<'PY' || fail "seeded statement is not a subsequence of source.md"
import sys
source = open(sys.argv[1], encoding="utf-8").read()
seeded = open(sys.argv[2], encoding="utf-8").read()
# Whitespace runs are tidied after seeding, so compare on non-whitespace.
source = "".join(source.split())
seeded = "".join(seeded.split())
it = iter(source)
sys.exit(0 if all(c in it for c in seeded) else 1)
PY
echo "  ok   the seeded statement is a subsequence of the source (deletion only)"

# The seed record must not be reachable from the run directory: that is
# the isolation, and it is structural rather than promised.
if [ -e "$RUN/seed.md" ]; then
	fail "the seed record was copied into the run directory"
fi
echo "  ok   the seed record is not in the run directory"

expect_pass "probe oracle (every seed is catchable)" \
	"$CLARIFY" probe oracle cursor-too-small

echo
echo "== each rule catches its own defect =="

# Rule 3 — a question that cites nothing.
DIR="$(mutate rule3-no-tag)"
sed -i '/^tag: semantic$/d' "$DIR/transcript.md"
expect_catch "a question with no ambiguity tag" rule-3 -- \
	"$CLARIFY" check "$DIR/requirements.md"

# Rule 3 — a question citing a tag the clause does not carry. This also
# leaves the clause's real ambiguity unasked, so rule 1 fires too.
DIR="$(mutate rule3-wrong-tag)"
sed -i 's/^tag: semantic$/tag: lexical/' "$DIR/transcript.md"
expect_catch "a question citing a tag the clause does not carry" rule-3 -- \
	"$CLARIFY" check "$DIR/requirements.md"

# Rule 1 — a nocuous ambiguity neither asked about nor deferred.
DIR="$(mutate rule1-unasked)"
python3 - "$DIR/transcript.md" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
# Drop the whole Q2 block, leaving its ambiguity unasked.
text = re.sub(r"## question Q2\n.*?(?=## utterance U3)", "", text, flags=re.S)
text = text.replace("answers: Q2\n", "")
open(path, "w", encoding="utf-8").write(text)
PY
expect_catch "a nocuous ambiguity nobody asked about" rule-1 -- \
	"$CLARIFY" check "$DIR/requirements.md"

# Rule 5 — a goal-level ambiguity deferred instead of asked.
DIR="$(mutate rule5-deferred-goal)"
sed -i 's/^Level: constraint$/Level: goal/' "$DIR/requirements.md"
expect_catch "a goal-level ambiguity deferred" rule-5 -- \
	"$CLARIFY" check "$DIR/requirements.md"

# Rule 5 — a constraint-level question asked before a goal-level one.
DIR="$(mutate rule5-ordering)"
sed -i '0,/^Level: goal$/s//Level: constraint/' "$DIR/requirements.md"
expect_catch "a constraint-level question asked first" rule-5 -- \
	"$CLARIFY" check "$DIR/requirements.md"

# Rule 4 — a stop whose arithmetic does not hold.
DIR="$(mutate rule4-stop-arithmetic)"
sed -i 's/^best-remaining: 0.06$/best-remaining: 0.60/' "$DIR/transcript.md"
expect_catch "a stop claiming a threshold it does not meet" rule-4 -- \
	"$CLARIFY" check "$DIR/requirements.md"

# Rule 4 — an alpha chosen after the fact rather than declared.
DIR="$(mutate rule4-alpha-drift)"
sed -i 's/^alpha: 0.25$/alpha: 0.90/' "$DIR/transcript.md"
expect_catch "a stop alpha contradicting the declared one" rule-4 -- \
	"$CLARIFY" check "$DIR/requirements.md"

# Rule 4 — over the declared question budget.
DIR="$(mutate rule4-budget)"
sed -i 's/^Question-budget: 2$/Question-budget: 1/' "$DIR/requirements.md"
expect_catch "more questions than the declared budget" rule-4 -- \
	"$CLARIFY" check "$DIR/requirements.md"

# Rule 4 — no stop block at all.
DIR="$(mutate rule4-no-stop)"
python3 - "$DIR/transcript.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
open(path, "w", encoding="utf-8").write(text.split("## stop")[0])
PY
expect_catch "a phase that stopped without saying why" rule-4 -- \
	"$CLARIFY" check "$DIR/requirements.md"

# Rule 7 — the clearinghouse probe was never asked.
DIR="$(mutate rule7-no-clearinghouse)"
python3 - "$DIR/transcript.md" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
text = re.sub(r"## question Q3\n.*?(?=## utterance U4)", "", text, flags=re.S)
text = text.replace("answers: Q3\n", "")
open(path, "w", encoding="utf-8").write(text)
PY
expect_catch "the clearinghouse probe was never asked" rule-7 -- \
	"$CLARIFY" check "$DIR/requirements.md"

# Rule 10 — an ambiguity cleared without a citation.
DIR="$(mutate rule10-no-ref)"
sed -i 's/ state=cleared ref=U2 / state=cleared /' "$DIR/requirements.md"
expect_catch "an ambiguity cleared with no citation" rule-10 -- \
	"$CLARIFY" check "$DIR/requirements.md"

# Rule 10 — cleared by an utterance that answers nothing.
DIR="$(mutate rule10-bad-ref)"
sed -i 's/ state=cleared ref=U2 / state=cleared ref=U1 /' "$DIR/requirements.md"
expect_catch "an ambiguity cleared by an utterance answering nothing" rule-10 -- \
	"$CLARIFY" check "$DIR/requirements.md"

# Read-back, omission half — an utterance no clause reflects.
DIR="$(mutate readback-omission)"
sed -i '/^Traces: U4$/d' "$DIR/requirements.md"
expect_catch "an utterance no clause reflects" readback -- \
	"$CLARIFY" check "$DIR/requirements.md"

# Read-back, invention half — a stated clause with nothing behind it.
DIR="$(mutate readback-invention)"
sed -i 's/^Traces: U1, U3$//' "$DIR/requirements.md"
expect_catch "a stated clause with no utterance behind it" readback -- \
	"$CLARIFY" check "$DIR/requirements.md"

# Read-back — an utterance excused from coverage with no reason given.
DIR="$(mutate readback-silent-excuse)"
sed -i '/^reason: closing acknowledgement/d' "$DIR/transcript.md"
expect_catch "an utterance excused from coverage without a reason" readback -- \
	"$CLARIFY" check "$DIR/requirements.md"

# Form — an unmarked clause: the system's reading passed off as words.
DIR="$(mutate form-unmarked)"
sed -i 's/^\[stated 2026-09-08\] The compositor/The compositor/' "$DIR/requirements.md"
expect_catch "a clause marked neither stated nor inferred" form -- \
	"$CLARIFY" check "$DIR/requirements.md"

# Form — a document that declares none of its own knobs.
DIR="$(mutate form-no-knobs)"
sed -i '/^Nocuity-threshold: /d' "$DIR/requirements.md"
expect_catch "a document declaring no nocuity threshold" form -- \
	"$CLARIFY" check "$DIR/requirements.md"

echo
echo "== the salt discipline =="

# A probe artifact may never sit where current truth lives.
DIR="$WORKDIR/salt/docs/state"
mkdir -p "$DIR"
cp "$PROBE/oracle/requirements.md" "$PROBE/oracle/transcript.md" "$DIR/"
expect_catch "a probe artifact under docs/state/" salt -- \
	"$CLARIFY" check "$DIR/requirements.md"

# A probe run whose document does not admit to being one.
DIR="$(mutate salt-unlabelled)"
cp "$RUN/statement.md" "$DIR/"
sed -i '/^Probe: cursor-too-small$/d' "$DIR/requirements.md"
expect_catch "a probe run's document not labelled as one" salt -- \
	"$CLARIFY" probe score cursor-too-small "$DIR"

echo
echo "== the probe scores in both directions =="

# Under-asking: drop the question that catches S2 and coverage falls
# below the pre-registered floor.
DIR="$(mutate probe-under-asking)"
python3 - "$DIR/transcript.md" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
text = re.sub(r"## question Q2\n.*?(?=## utterance U3)", "", text, flags=re.S)
open(path, "w", encoding="utf-8").write(text)
PY
expect_catch "a run that missed a seeded ambiguity" probe -- \
	"$CLARIFY" probe score cursor-too-small "$DIR"

# Over-asking: a question that hits no unhit seed pushes the redundant-
# question rate above the pre-registered ceiling. Scoring only asking
# would call this run better than the oracle.
DIR="$(mutate probe-over-asking)"
python3 - "$DIR/transcript.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
extra = (
    "## question Q4\n"
    "clause: cursor-value-by-sweep\n"
    "tag: lexical\n"
    "type: discriminating\n"
    "\n"
    "Would you like the value written down anywhere in particular?\n"
    "\n"
)
open(path, "w", encoding="utf-8").write(text.replace("## stop\n", extra + "## stop\n"))
PY
expect_catch "a run that asked a question worth nothing" probe -- \
	"$CLARIFY" probe score cursor-too-small "$DIR"

echo
echo "== the style lint warns and never blocks =="

DIR="$(mutate style-leading)"
python3 - "$DIR/transcript.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
text = text.replace(
    "How will you know the cursor is big enough?",
    "You want it bigger, don't you? How will you know the cursor is big enough?",
)
open(path, "w", encoding="utf-8").write(text)
PY
expect_pass "a leading question does not block" \
	"$CLARIFY" check "$DIR/requirements.md"
if ! grep -q "rule-7" <<<"$OUT"; then
	echo "$OUT" >&2
	fail "a leading question produced no rule-7 warning"
fi
echo "  ok   ...but it warns"
expect_catch "--strict turns the warning into a failure" rule-7 -- \
	"$CLARIFY" --strict check "$DIR/requirements.md"

echo
echo "== the pre-registration cannot be skipped =="

BADPROBE="$WORKDIR/badprobe"
mkdir -p "$BADPROBE"
cp "$PROBE/source.md" "$BADPROBE/"
sed '/^Floor-coverage: /d' "$PROBE/seed.md" >"$BADPROBE/seed.md"
expect_catch "a probe with no pre-registered floor" Floor-coverage -- \
	"$CLARIFY" probe build "$BADPROBE" --out "$WORKDIR/badprobe-run"

# A seed whose span is not in the source is a broken seed, not a silent
# no-op deletion.
BADSEED="$WORKDIR/badseed"
mkdir -p "$BADSEED"
cp "$PROBE/seed.md" "$BADSEED/"
sed 's/^Done means I have looked/Done means somebody looked/' "$PROBE/source.md" \
	>"$BADSEED/source.md"
expect_catch "a seed whose span is not in the source" "occurs 0 times" -- \
	"$CLARIFY" probe build "$BADSEED" --out "$WORKDIR/badseed-run"

echo
echo "== every requirements document in docs/state/ still checks out =="

found=0
while IFS= read -r doc; do
	found=$((found + 1))
	expect_pass "docs/state: $(basename "$doc")" "$CLARIFY" check "$doc"
done < <(grep -rl '^Nocuity-threshold:' "$REPO_ROOT/docs/state" 2>/dev/null || true)
echo "  ok   $found requirements document(s) under docs/state/"

echo
echo "clarify: all checks passed."
