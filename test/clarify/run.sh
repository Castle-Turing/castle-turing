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
# The brackets are load-bearing: an unanchored substring match makes
# `rule-1` match a `rule-10` finding and `form` match "malformed", which
# would defeat the entire point of asserting on the rule at all.
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
# For the loader's own refusals, which are SystemExit messages rather
# than findings and so carry no rule bracket.
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

# Lay down a fresh copy of the worked example and apply one mutation to
# it. Each case gets its own directory: a mutation left behind would
# quietly change the meaning of every case after it.
mutate() {
    local name="$1"
    local dir="$WORKDIR/$name"
    mkdir -p "$dir"
    cp "$PROBE/oracle/requirements.md" "$PROBE/oracle/transcript.md" "$dir/"
    # The seeded statement rides along whenever it exists, because a
    # probe run without one — or with one that differs from what the
    # seed record builds — is refused as not being the registered
    # experiment. Check-only cases ignore it.
    [ -f "$RUN/statement.md" ] && cp "$RUN/statement.md" "$dir/"
    echo "$dir"
}

echo "== the worked example passes =="
expect_pass "check (form, questions, read-back)" \
    "$CLARIFY" check "$PROBE/oracle/requirements.md"

echo
echo "== the probe harness =="
RUN="$WORKDIR/probe-run"
expect_pass "probe build" "$CLARIFY" probe build cursor-too-small --out "$RUN"

# Deletion-only editing, checked by a second implementation rather than
# by the builder agreeing with itself. The builder's own subsequence
# assertion cannot fail — its only operation is removing a span, so the
# result is a subsequence by construction, and a check that cannot fail
# is the failure mode this file's header comment is about. What CAN fail
# is the builder removing something the seed record did not name, or
# mangling what it left behind: so this re-derives the expected statement
# here, from source.md and seed.md, and compares byte for byte.
python3 - "$PROBE/source.md" "$PROBE/seed.md" "$RUN/statement.md" <<'PY' || fail "the built statement is not the source minus exactly the seeded spans"
import re
import sys

source = open(sys.argv[1], encoding="utf-8").read()
seed = open(sys.argv[2], encoding="utf-8").read()
built = open(sys.argv[3], encoding="utf-8").read()

spans = re.findall(r"^```delete\n(.*?)^```$", seed, flags=re.S | re.M)
if not spans:
    sys.exit("no ```delete spans in the seed record")

expected = source
for span in spans:
    lines = span.split("\n")
    if lines and lines[-1] == "":
        lines.pop()  # the newline before the closing fence is not content
    text = "\n".join(lines)
    if expected.count(text) != 1:
        sys.exit(f"span occurs {expected.count(text)} times, expected once")
    expected = expected.replace(text, "", 1)
expected = re.sub(r"\n{3,}", "\n\n", expected).strip() + "\n"

if expected != built:
    sys.exit("built statement differs from source-minus-seeds")
PY
echo "  ok   the built statement is the source minus exactly the seeded spans"

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

# ...and the same defect must not become invisible by narrowing the run.
# Rules 1 and 4 are computed from those numbers, so a missing one does
# not weaken them, it switches them off. A check that can be switched off
# by omitting a header is worse than none, because the run still prints a
# zero.
expect_catch "a missing threshold under --only questions" form -- \
    "$CLARIFY" check --only questions "$DIR/requirements.md"

# Form — a clause heading with no key. Left unreported, its body merges
# into the clause above and a whole clause vanishes while the document
# still checks out.
DIR="$(mutate form-keyless-heading)"
sed -i 's/^### How the value is picked \[cursor-value-by-sweep\]$/### How the value is picked/' \
    "$DIR/requirements.md"
expect_catch "a clause heading with no key" form -- \
    "$CLARIFY" check "$DIR/requirements.md"

# Form — a clause whose opening assertion is unattributed, picking up a
# mark from a later line.
DIR="$(mutate form-late-mark)"
python3 - "$DIR/requirements.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
text = text.replace(
    "[stated 2026-09-08] The compositor's pointer must be large enough",
    "The compositor's pointer must be large enough",
).replace(
    "does not satisfy this clause even if it computes to the same number.",
    "does not satisfy this clause.\n[stated 2026-09-08] It is also nice.",
)
open(path, "w", encoding="utf-8").write(text)
PY
expect_catch "a clause whose opening assertion is unattributed" form -- \
    "$CLARIFY" check "$DIR/requirements.md"

# Form — an utterance claiming to answer two questions at once.
DIR="$(mutate form-multi-answer)"
sed -i 's/^answers: Q1$/answers: Q1, Q2/' "$DIR/transcript.md"
expect_catch "an utterance answering two questions at once" form -- \
    "$CLARIFY" check "$DIR/requirements.md"

# Form — prose opening a sentence with a reserved field name. `Level:`
# and `Traces:` are read as fields wherever they appear, so a second one
# overwrites the first and vanishes out of the prose, leaving a clause
# whose declared level is not the level anyone wrote — with rule 5
# computed from it.
DIR="$(mutate form-reserved-in-prose)"
python3 - "$DIR/requirements.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
text = text.replace(
    "on the real hardware. A size derived by arithmetic",
    "on the real hardware.\nLevel: constraint work is out of scope here.\n"
    "A size derived by arithmetic",
)
open(path, "w", encoding="utf-8").write(text)
PY
expect_catch "prose opening with a reserved field name" form -- \
    "$CLARIFY" check "$DIR/requirements.md"

# Rule 5 — the goal-deferral ban is on the level, not on the number.
# Certainty is written by the phase about itself and is explicitly not
# checked for honesty, so a ban that only applied below the nocuity
# threshold could be lifted by writing a high certainty.
DIR="$(mutate rule5-deferred-goal-high-certainty)"
python3 - "$DIR/requirements.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
text = text.replace("Level: constraint", "Level: goal")
text = text.replace("certainty=0.50 state=deferred", "certainty=0.99 state=deferred")
open(path, "w", encoding="utf-8").write(text)
PY
expect_catch "a goal-level ambiguity deferred behind a high certainty" rule-5 -- \
    "$CLARIFY" check "$DIR/requirements.md"

# Form — a nocuity threshold in range syntactically but empty in effect.
# `Nocuity-threshold: 0` makes nothing nocuous and rule 1 vacuous, so
# the range check lives beside the presence check and outside --only.
DIR="$(mutate form-threshold-zero)"
sed -i 's/^Nocuity-threshold: 0.7$/Nocuity-threshold: 0/' "$DIR/requirements.md"
expect_catch "a nocuity threshold of zero" form -- \
    "$CLARIFY" check "$DIR/requirements.md"
expect_catch "...and still under --only questions" form -- \
    "$CLARIFY" check --only questions "$DIR/requirements.md"

# Rule 4 — an alpha large enough to make the stop arithmetic vacuous.
DIR="$(mutate rule4-alpha-out-of-range)"
sed -i 's/^Stop-alpha: 0.25$/Stop-alpha: 100/' "$DIR/requirements.md"
sed -i 's/^alpha: 0.25$/alpha: 100/' "$DIR/transcript.md"
expect_catch "an alpha that makes every stop satisfy itself" form -- \
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

# The statement scored must be the statement registered. A run whose
# statement.md was replaced with the full source would let the phase
# read the deleted answers and report a perfect catch; one with no
# statement at all is no experiment. Both are refused before scoring.
DIR="$(mutate probe-statement-replaced)"
cp "$PROBE/source.md" "$DIR/statement.md"
expect_die "a probe run whose statement is the unseeded source" \
    "not the experiment" -- \
    "$CLARIFY" probe score cursor-too-small "$DIR"

DIR="$(mutate probe-statement-missing)"
rm "$DIR/statement.md"
expect_die "a probe run with no statement at all" "no statement.md" -- \
    "$CLARIFY" probe score cursor-too-small "$DIR"

echo
echo "== only the resident's words are the resident's words =="

# Rewriting every speaker to system leaves the same text in place, but
# a [stated] clause may no longer claim it: system-authored utterances
# ground nothing and count toward no coverage.
DIR="$(mutate speaker-system)"
sed -i 's/^speaker: resident$/speaker: system/' "$DIR/transcript.md"
expect_catch "a stated clause tracing only system-authored text" readback -- \
    "$CLARIFY" check "$DIR/requirements.md"

# And an utterance that declares no speaker at all is a form error, not
# a silent pass into the resident's column.
DIR="$(mutate speaker-missing)"
sed -i '0,/^speaker: resident$/{/^speaker: resident$/d}' "$DIR/transcript.md"
expect_catch "an utterance with no speaker" form -- \
    "$CLARIFY" check "$DIR/requirements.md"

# Pre-registered bounds outside the unit interval can never fail a run:
# a floor of -1 is missable by nothing, a ceiling above 1 exceedable by
# nothing. Refused at load, before any scoring.
BADBOUNDS="$WORKDIR/badbounds"
mkdir -p "$BADBOUNDS"
cp "$PROBE/source.md" "$BADBOUNDS/"
sed 's/^Floor-coverage: .*/Floor-coverage: -1/' "$PROBE/seed.md" \
    >"$BADBOUNDS/seed.md"
expect_die "a pre-registered floor below zero" "outside" -- \
    "$CLARIFY" probe build "$BADBOUNDS" --out "$WORKDIR/badbounds-run"

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
expect_die "a probe with no pre-registered floor" Floor-coverage -- \
    "$CLARIFY" probe build "$BADPROBE" --out "$WORKDIR/badprobe-run"

# A seed whose span is not in the source is a broken seed, not a silent
# no-op deletion.
BADSEED="$WORKDIR/badseed"
mkdir -p "$BADSEED"
cp "$PROBE/seed.md" "$BADSEED/"
sed 's/^Done means I have looked/Done means somebody looked/' "$PROBE/source.md" \
    >"$BADSEED/source.md"
expect_die "a seed whose span is not in the source" "occurs 0 times" -- \
    "$CLARIFY" probe build "$BADSEED" --out "$WORKDIR/badseed-run"

# The ground truth must not be rewritable by the seed record's own prose.
# A seed's fields end at the first line that is not one, blank lines
# included — otherwise a sentence beginning "expect-tag:" silently
# changes what the probe is measuring.
# Kept under the probe's own name so the run's `Probe:` label still
# matches: this case is about the seed parser, not about the salt rule.
PROSESEED="$WORKDIR/proseseed/cursor-too-small"
mkdir -p "$PROSESEED"
cp "$PROBE/source.md" "$PROSESEED/"
python3 - "$PROBE/seed.md" "$PROSESEED/seed.md" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
text = text.replace(
    "Deleting the acceptance criterion leaves",
    "expect-tag: syntactic\n\nDeleting the acceptance criterion leaves",
)
open(sys.argv[2], "w", encoding="utf-8").write(text)
PY
"$CLARIFY" probe build "$PROSESEED" --out "$WORKDIR/proseseed-run" >/dev/null
cp "$PROBE/oracle/transcript.md" "$PROBE/oracle/requirements.md" \
    "$WORKDIR/proseseed-run/"
expect_pass "seed prose cannot rewrite the pre-registered ground truth" \
    "$CLARIFY" probe score "$PROSESEED" "$WORKDIR/proseseed-run"

# A seed deletes one span. A second fence under the same seed would
# discard the first silently.
TWOFENCE="$WORKDIR/twofence"
mkdir -p "$TWOFENCE"
cp "$PROBE/source.md" "$TWOFENCE/"
python3 - "$PROBE/seed.md" "$TWOFENCE/seed.md" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
extra = "\n```delete\nThe mouse cursor is too small to find on this laptop's panel.\n```\n"
head, sep, tail = text.partition("## seed S2")
open(sys.argv[2], "w", encoding="utf-8").write(head + extra + sep + tail)
PY
expect_die "a seed with two delete fences" "more than one" -- \
    "$CLARIFY" probe build "$TWOFENCE" --out "$WORKDIR/twofence-run"

echo
echo "== every requirements document in docs/state/ still checks out =="

# Discovery is by exclusion, not by grepping for a header a broken
# document would be missing: a requirements document with no
# `Nocuity-threshold:` is the exact defect check_knobs blocks, and a
# sweep that found documents *by* that header would skip it and stay
# green. The two documents named below are the directory's non-
# requirements documents; adding a third kind of document there is
# already a deliberate act under that directory's rule 4, and adding it
# to this list is part of the act.
# Recursive, because the clarify-check workflow triggers on
# docs/state/** — a document in a subdirectory would fire the gate and
# then be skipped by a top-level-only glob, arriving validated by
# nothing. The two exclusions are exact top-level paths: a README.md
# nested deeper is *not* excused, it is a new kind of document under
# that directory's rule 4 and gets named here as part of the act.
found=0
while IFS= read -r doc; do
    case "${doc#"$REPO_ROOT"/}" in
    docs/state/README.md | docs/state/MILESTONE.md) continue ;;
    esac
    found=$((found + 1))
    expect_pass "docs/state: ${doc#"$REPO_ROOT"/docs/state/}" "$CLARIFY" check "$doc"
done < <(find "$REPO_ROOT/docs/state" -name '*.md' -type f | sort)
echo "  ok   $found requirements document(s) under docs/state/"

echo
echo "clarify: all checks passed."
