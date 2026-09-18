#!/usr/bin/env bash
# test/outcomes/run.sh — the task-outcome log's checker, held to what
# docs/tasks/0070-the-task-outcome-log.md says it must catch.
#
# Two halves, and the second is the bigger one on purpose.
#
# The first runs `check` over the log this repository actually carries,
# which is the thing CI is really gating. The second builds a synthetic
# repository — a handful of briefs, a small valid log, a base revision —
# and mutates it once per rule, asserting each mutation is rejected by
# the rule that owns it. A checker whose negative cases are untested is
# a checker that passes everything, and this one is the only thing
# standing between a pre-intervention baseline and somebody quietly
# improving it.
#
# Same conventions as test/clarify next door: plain bash, stdlib
# python3, no Nix, no network, zero models.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTCOMES="$REPO_ROOT/tools/outcomes/outcomes"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/outcomes-test.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

log() { printf '>>> %s\n' "$*"; }
FAILURES=0
fail() { printf '    FAIL: %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
pass() { printf '    ok: %s\n' "$*"; }

# --- the real log --------------------------------------------------------

log "the committed log passes its own checker"
# --no-base: on a fresh clone or a shallow CI checkout there may be no
# origin/main to compare against, and this half is about the file's own
# consistency. The append-only half is exercised against the synthetic
# repository below, where a base revision is guaranteed to exist.
if python3 "$OUTCOMES" --repo-root "$REPO_ROOT" check --no-base >/dev/null; then
  pass "docs/log/task-outcomes.tsv is well formed and covers every brief"
else
  python3 "$OUTCOMES" --repo-root "$REPO_ROOT" check --no-base || true
  fail "the committed log does not pass"
fi

# --- the synthetic repository -------------------------------------------

SANDBOX="$WORKDIR/repo"
mkdir -p "$SANDBOX/docs/tasks/done" "$SANDBOX/docs/log"

brief() { # brief <stem> <model-header>
  printf 'Title: %s\nModel: %s\n\n# %s\n' "$1" "$2" "$1" \
    > "$SANDBOX/docs/tasks/$1.md"
}
brief 0001-the-first-thing deep
brief 0002-the-second-thing standard
printf 'Title: 0003-the-third-thing\nModel: cheap\n\n# third\n' \
  > "$SANDBOX/docs/tasks/done/0003-the-third-thing.md"

HEADER=$(python3 - "$OUTCOMES" <<'PY'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("o", sys.argv[1])
spec = importlib.util.spec_from_loader("o", loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)
print("\t".join(m.COLUMNS))
PY
)

row() { # row <task> <attempt> <queued> <landed> <outcome> <tail...>
  local task=$1 attempt=$2 queued=$3 landed=$4 outcome=$5
  printf '1\t%s\t%s\t%s\t%s\t%s\tdeep\tclaude-opus-5\tm2-done\t7\t1.50\t20\t0\t0.0\t-\t-\t-\t2\t2\t-\t-\te1\tlive\t%s\n' \
    "$task" "$attempt" "$queued" "$landed" "$outcome" "${6:--}"
}

base_log() {
  printf '%s\n' "$HEADER"
  row 0001-the-first-thing 1 2026-08-01 2026-08-02 merged
  row 0002-the-second-thing 1 2026-08-03 2026-08-04 merged
  row 0003-the-third-thing 1 2026-08-05 2026-08-06 merged
}

LOG="$SANDBOX/docs/log/task-outcomes.tsv"
base_log > "$LOG"

git -C "$SANDBOX" init -q
git -C "$SANDBOX" -c user.email=t@t -c user.name=t add -A
git -C "$SANDBOX" -c user.email=t@t -c user.name=t commit -qm base
git -C "$SANDBOX" update-ref refs/remotes/origin/main HEAD

check() { python3 "$OUTCOMES" --repo-root "$SANDBOX" check "$@"; }

log "the synthetic log the rejects are mutated from is itself clean"
if check >/dev/null 2>&1; then
  pass "base fixture passes, so every reject below proves something"
else
  check || true
  fail "the base fixture does not pass; nothing below is meaningful"
fi

# reject <name> <expected substring> — the fixture is already mutated.
reject() {
  local name=$1 expect=$2 out
  if out=$(check 2>&1); then
    fail "$name: accepted"
  elif printf '%s' "$out" | grep -qF -- "$expect"; then
    pass "$name"
  else
    fail "$name: rejected for the wrong reason: $(printf '%s' "$out" | head -1)"
  fi
  base_log > "$LOG"
  rm -f "$SANDBOX/docs/tasks/0004-the-fourth-thing.md"
}

log "structure"

printf '%s\n' "$HEADER" | sed 's/^schema/scheme/' > "$LOG"
reject "a header that is not schema 1's columns" "header is not schema"

base_log | sed '2s/\tmerged\t/\t/' > "$LOG"
reject "a row with the wrong number of cells" "cells, expected"

base_log | sed '2s/\tm2-done\t/\t\t/' > "$LOG"
reject "a blank cell where unrecorded is a dash" "is empty"

base_log | sed '2s/^1\t/2\t/' > "$LOG"
reject "a row claiming another schema version" "is not '1'"

printf '%s' "$(base_log)" > "$LOG"
reject "a file with no trailing newline" "no trailing newline"

log "values"

base_log | sed '2s/\tmerged\t/\tlanded\t/' > "$LOG"
reject "an outcome outside the enumeration" "is not one of"

base_log | sed '2s/2026-08-02/2026-07-01/' > "$LOG"
reject "a landing date before the task was queued" "precedes queued"

base_log | sed '2s/\t1\t2026-08-01/\t0\t2026-08-01/' > "$LOG"
reject "an attempt number of zero" "positive integer"

{ base_log; row 0001-the-first-thing 1 2026-08-01 2026-08-02 merged; } > "$LOG"
reject "two rows for the same task and attempt" "already has a row"

base_log | sed '2s/\t1\.50\t/\t1.5\t/' > "$LOG"
reject "a cost that is not a 2-decimal amount" "2-decimal"

base_log | sed '2s/\t2\t2\t/\t1\t2\t/' > "$LOG"
reject "more findings fixed than raised" "findings_fixed exceeds findings"

log "the receipt/verdict split"

# The verdict cells are counts over the citations in verdict_ref (task
# 0072), so every mutation below is a number moving with nothing behind
# it — which is the whole fabrication surface, and it has to be caught
# by a checker with no network in it.
base_log | sed '2s/\t-\t-\t-\t2\t2\t-\t/\t1\t-\t-\t2\t2\t-\t/' > "$LOG"
reject "a redirect count with no citation behind it" \
  "never a number someone typed"

base_log | sed '2s/\t-\t-\t-\t2\t2\t-\t/\t2\t-\t-\t2\t2\tr\/pr9\/ic1\t/' > "$LOG"
reject "a redirect count larger than its citations" \
  "never a number someone typed"

base_log | sed '2s/\t-\t-\t-\t2\t2\t-\t/\t-\t-\t-\t2\t2\tr\/pr9\/ic1\t/' > "$LOG"
reject "a citation with no count read off it" \
  "redirects is unrecorded"

base_log | sed '2s/\t-\t-\t-\t2\t2\t-\t/\t1\t0\t-\t2\t2\tr\/pr9\/ic1\t/' > "$LOG"
reject "a miscorrection rate of zero that nobody reassessed" \
  "0 is a judgment too"

base_log | sed '2s/\t-\t-\t-\t2\t2\t-\t/\t1\t2\t-\t2\t2\tr\/pr9\/ic1,w2\/pr9\/ic2\t/' > "$LOG"
reject "more redirects judged wrong than were made" "exceeds redirects"

base_log | sed '2s/\t-\t-\t-\t2\t2\t-\t/\t-\t0\t-\t2\t2\tw0\/pr9\/ic2\t/' > "$LOG"
reject "a reassessment of redirects that were never cited" \
  "reassesses redirects that were never cited"

base_log | sed '2s/\t-\t-\t-\t2\t2\t-\t/\t1\t0\t-\t2\t2\tpr-comment-9\t/' > "$LOG"
reject "a citation that is not a citation" "is not a citation token"

base_log | sed '2s/\t-\t-\t-\t2\t2\t-\t/\t2\t-\t-\t2\t2\tr\/pr9\/ic1,r\/pr9\/ic1\t/' > "$LOG"
reject "the same citation counted twice" "cited twice"

base_log | sed '2s/\t-\t-\t-\t2\t2\t-\t/\t1\t1\t-\t2\t2\tr\/pr9\/ic1,w0\/pr9\/ic2,w1\/pr9\/ic2\t/' > "$LOG"
reject "one comment made to say two different things" "one citation states one judgment"

base_log | sed '2s/\t-\t-\t-\t2\t2\t-\t/\t1\t0\t-\t2\t2\t-\t/' > "$LOG"
reject "a verdict with nowhere the resident said it" "carries no verdict_ref"

log "coverage, the detector"

brief 0004-the-fourth-thing deep
reject "a brief that landed without a row" "has no row in"

base_log | sed '4s/0003-the-third-thing/0009-a-task-that-never-existed/' > "$LOG"
reject "a row naming no brief at all" "matches no brief"

base_log | sed '2s/\t-\te1\tlive\t/\tp1\te1\tlive\t/' > "$LOG"
reject "salt wearing a real brief's name" "never masquerades"

log "the note lint"

base_log | sed '2s/\tlive\t-$/\tlive\tmailed to someone@example.com/' > "$LOG"
reject "an address in a note" "no personal data"

base_log | sed '2s#\tlive\t-$#\tlive\tsee /home/somebody/notes.txt#' > "$LOG"
reject "a home path in a note" "no personal data"

base_log | sed "2s/\tlive\t-$/\tlive\t$(python3 -c 'print("x"*201)')/" > "$LOG"
reject "a note over the length cap" "over the 200 cap"

log "append-only, against the base revision"

base_log | sed '3d' > "$LOG"
reject "a row deleted since the base revision" "rows are never deleted"

base_log | sed '2s/2026-08-01/2026-08-09/' > "$LOG"
reject "an immutable cell rewritten" "fixed when the row is written"

base_log | sed '2s/\t1\.50\t/\t9.99\t/' > "$LOG"
reject "a pending cell rewritten after it was recorded" "written once"

# The citation list is append-only, and the verdict counts are read off
# it, so these three are the only ways a recorded verdict could be
# rewritten. They are held against a base revision that already carries
# one citation.
CITED='1\t0001-the-first-thing\t1\t2026-08-01\t2026-08-02\tmerged\tdeep\tclaude-opus-5\tm2-done\t7\t1.50\t20\t0\t0.0\t2\t-\t-\t2\t2\tr/pr9/ic1,r/pr9/ic2\t-\te1\tlive\t-'
cited_log() { base_log | sed "2s#.*#$CITED#"; }
cited_log > "$LOG"
git -C "$SANDBOX" -c user.email=t@t -c user.name=t commit -qam cited
git -C "$SANDBOX" update-ref refs/remotes/origin/main HEAD

cited_log | sed '2s#r/pr9/ic1,r/pr9/ic2#r/pr9/ic1#; 2s#\t2\t-\t-\t2\t2\t#\t1\t-\t-\t2\t2\t#' > "$LOG"
reject "a citation removed since the base revision" "only ever appended"

cited_log | sed '2s#r/pr9/ic1,r/pr9/ic2#r/pr9/ic2,r/pr9/ic1#' > "$LOG"
reject "citations reordered, which is a substitution nobody can see" \
  "only ever appended"

cited_log | sed '2s#r/pr9/ic1,r/pr9/ic2#r/pr9/ic1,r/pr9/ic3#' > "$LOG"
reject "a citation swapped for a different one" "only ever appended"

cited_log > "$LOG"
if check >/dev/null 2>&1; then
  pass "a citation appended on top of the base is allowed"
else
  fail "appending a citation was rejected"
fi
cited_log | sed '2s#r/pr9/ic1,r/pr9/ic2#r/pr9/ic1,r/pr9/ic2,w1/pr9/ic3#; 2s#\t2\t-\t-\t2\t2\t#\t2\t1\t-\t2\t2\t#' > "$LOG"
if check >/dev/null 2>&1; then
  pass "a reassessment appended later matures redirects_wrong"
else
  check || true
  fail "appending a reassessment was rejected"
fi

# Back to the uncited base for everything below.
git -C "$SANDBOX" -c user.email=t@t -c user.name=t checkout -q -- .
base_log > "$LOG"
git -C "$SANDBOX" -c user.email=t@t -c user.name=t commit -qam uncited
git -C "$SANDBOX" update-ref refs/remotes/origin/main HEAD

log "and what must still be allowed"

accept() { # accept <name>
  local name=$1 out
  if out=$(check 2>&1); then
    pass "$name"
  else
    fail "$name: rejected — $(printf '%s' "$out" | head -1)"
  fi
  base_log > "$LOG"
}

base_log | sed '2s/\t-\t-\t-\t2\t2\t-\t/\t2\t1\t-\t2\t2\tr\/pr9\/ic1,r\/pr9\/ic2,w1\/pr9\/ic3\t/' > "$LOG"
accept "a verdict pair arriving together with its citations"

# The rule task 0072 relaxed, and the reason it had to be relaxed: a
# redirect is logged the moment it happens, and whether it was a *wrong*
# redirect is not knowable then. Defaulting the cell to 0 would record
# the absence of a judgment as a judgment of correctness.
base_log | sed '2s/\t-\t-\t-\t2\t2\t-\t/\t1\t-\t-\t2\t2\tr\/pr9\/ic1\t/' > "$LOG"
accept "a redirect standing with its reassessment still pending"

base_log | sed '2s/\t-\t-\t-\t2\t2\t-\t/\t1\t0\t-\t2\t2\tr\/pr9\/ic1,w0\/pr9\/ic1\t/' > "$LOG"
accept "a reassessment that found the redirect correct, cited"

base_log | sed '2s/\tlive\t-$/\tlive\tan amended note, which is the one cell that may be/' > "$LOG"
accept "a note rewritten, because a note may need redacting"

{ base_log; row 0004-the-fourth-thing 1 2026-08-07 - -; } > "$LOG"
brief 0004-the-fourth-thing deep
accept "a new row appended with its outcome still pending"
rm -f "$SANDBOX/docs/tasks/0004-the-fourth-thing.md"

# --- derive, where a wrong cell would be permanent -----------------------
#
# `check` is the gate, but `derive` is what writes most cells, and every
# cell it writes is written once. These are the three ways it could put a
# confident wrong number into one.

log "redirect, the verdict logger"

# The resolver is the one place this tool touches a network, so it is
# the one place substituted here. `check` keeps its no-network property
# by never calling it at all; these tests keep theirs by replacing it.
# What is *not* faked is everything the command decides after it has an
# author: the identity comparison, the counting, the replay, and the
# refusals.
cat > "$WORKDIR/redirect.py" <<'DRIVER'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("o", sys.argv[1])
spec = importlib.util.spec_from_loader("o", loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)
author = sys.argv[2]


def fake(repo_root, source, journals):
    if author == "-":
        raise m.Fail(f"{source} does not resolve")
    return author


m.resolve_author = fake
sys.exit(m.main(sys.argv[3:]))
DRIVER

cat > "$WORKDIR/cell.py" <<'CELL'
import sys
log, task, name, header = sys.argv[1:5]
cols = header.split("\t")
for line in open(log):
    c = line.rstrip("\n").split("\t")
    if c[1] == task:
        print(c[cols.index(name)])
        break
CELL

XDG="$WORKDIR/xdg"
mkdir -p "$XDG"
# HOME and XDG_CONFIG_HOME are redirected so that the machine this runs
# on cannot lend the test a resident identity it did not set itself.
redirect() { # redirect <author-the-resolver-returns> <args...>
  local author=$1; shift
  env -u OUTCOMES_RESIDENT HOME="$WORKDIR/home" XDG_CONFIG_HOME="$XDG" \
    python3 "$WORKDIR/redirect.py" "$OUTCOMES" "$author" \
    --repo-root "$SANDBOX" redirect "$@"
}

expect_redirect() { # expect_redirect <name> <expect-exit> <author> <args...>
  local name=$1 want=$2 author=$3; shift 3
  local before after out rc
  before=$(cat "$LOG")
  out=$(redirect "$author" "$@" 2>&1) && rc=0 || rc=$?
  after=$(cat "$LOG")
  if [ "$rc" != "$want" ]; then
    fail "$name: exit $rc, wanted $want — $(printf '%s' "$out" | head -1)"
  elif [ "$want" != "0" ] && [ "$before" != "$after" ]; then
    fail "$name: refused and wrote to the log anyway"
  else
    pass "$name"
  fi
}

cell() { python3 "$WORKDIR/cell.py" "$LOG" "$1" "$2" "$HEADER"; }

expect_cells() { # expect_cells <name> <task> <redirects> <wrong> <verdict_ref>
  local name=$1 task=$2
  local got="$(cell "$task" redirects)/$(cell "$task" redirects_wrong)/$(cell "$task" verdict_ref)"
  if [ "$got" = "$3/$4/$5" ]; then pass "$name"; else fail "$name: row reads $got"; fi
}

base_log > "$LOG"

expect_redirect "a citation the resident wrote matures the row" 0 boss \
  0001-the-first-thing --ref 'https://github.com/o/r/pull/9#issuecomment-11' --resident boss
expect_cells "  ...to one redirect, reassessment pending" \
  0001-the-first-thing 1 - r/pr9/ic11

expect_redirect "the same citation again is a replay" 0 boss \
  0001-the-first-thing --ref 9#issuecomment-11 --resident boss
expect_cells "  ...and changes nothing" 0001-the-first-thing 1 - r/pr9/ic11

expect_redirect "a second, distinct citation is a second redirect" 0 boss \
  0001-the-first-thing --ref 9#discussion_r12 --resident boss
expect_cells "  ...counted as two" 0001-the-first-thing 2 - r/pr9/ic11,r/pr9/rc12

expect_redirect "a cited reassessment matures redirects_wrong" 0 boss \
  0001-the-first-thing --wrong 1 --ref 9#issuecomment-13 --resident boss
expect_cells "  ...to the number the resident judged wrong" \
  0001-the-first-thing 2 1 r/pr9/ic11,r/pr9/rc12,w1/pr9/ic13

if check >/dev/null 2>&1; then
  pass "the log the command wrote passes its own checker"
else
  check || true
  fail "redirect wrote a log that does not check"
fi

base_log > "$LOG"

expect_redirect "a comment somebody else wrote is refused" 2 stranger \
  0001-the-first-thing --ref 9#issuecomment-11 --resident boss
expect_redirect "a citation that does not resolve is refused" 2 - \
  0001-the-first-thing --ref 9#issuecomment-11 --resident boss
expect_redirect "a reference in no format it can read is refused" 2 boss \
  0001-the-first-thing --ref 'the comment where they said it' --resident boss
expect_redirect "no configured resident is refused, not assumed" 2 boss \
  0001-the-first-thing --ref 9#issuecomment-11
expect_redirect "a task with no row is refused" 2 boss \
  0009-no-such-task --ref 9#issuecomment-11 --resident boss
expect_redirect "a reassessment of a redirect nobody logged is refused" 2 boss \
  0001-the-first-thing --wrong 1 --ref 9#issuecomment-13 --resident boss
expect_redirect "an invocation with no --ref at all is refused" 2 boss \
  0001-the-first-thing --resident boss

expect_redirect "  (setup: one cited redirect)" 0 boss \
  0001-the-first-thing --ref 9#issuecomment-11 --resident boss
expect_redirect "more judged wrong than were ever cited is refused" 2 boss \
  0001-the-first-thing --wrong 2 --ref 9#issuecomment-13 --resident boss

base_log > "$LOG"

log "derive"

brief 0005-the-fifth-thing deep
git -C "$SANDBOX" -c user.email=t@t -c user.name=t add -A
git -C "$SANDBOX" -c user.email=t@t -c user.name=t commit -qm "queue the fifth"

derived="$(python3 "$OUTCOMES" --repo-root "$SANDBOX" derive \
  --env e1 --main refs/remotes/origin/main 2>/dev/null)"
if printf '%s' "$derived" | grep -q '^1	0005-the-fifth-thing	1	[0-9-]*	-	-	'; then
  pass "work that has not reached the trunk is not called merged"
else
  fail "unlanded work was dated and marked merged: $derived"
fi

if python3 "$OUTCOMES" --repo-root "$SANDBOX" derive --provenance live \
     >/dev/null 2>&1; then
  fail "a live row was derived with no environment key"
else
  pass "a live row with no environment key is refused, since env is immutable"
fi

JOURNAL="$WORKDIR/journal.jsonl"
brief 0006-the-sixth-thing deep
cat > "$JOURNAL" <<'JSON'
{"type": "usage", "task": "0005-the-fifth-thing", "cost_usd": 1.0, "turns": 4}
{"type": "usage", "task": "0005-the-fifth-thing", "cost_usd": 2.5, "turns": 6}
{"type": "usage", "task": "0006-the-sixth-thing", "cost_usd": null, "turns": 3}
JSON
derived="$(python3 "$OUTCOMES" --repo-root "$SANDBOX" derive --env e1 \
  --harness-journal "$JOURNAL" --main refs/remotes/origin/main 2>/dev/null)"
fifth="$(printf '%s\n' "$derived" | grep '0005-the-fifth-thing' || true)"
sixth="$(printf '%s\n' "$derived" | grep '0006-the-sixth-thing' || true)"
if printf '%s' "$fifth" | grep -qE '	(1\.00|2\.50|3\.50)	'; then
  fail "two attempts' costs were written to one attempt's row: $fifth"
else
  pass "a task attempted twice leaves cost unrecorded rather than ambiguous"
fi
if printf '%s' "$sixth" | grep -q '	0\.00	'; then
  fail "a usage event with no cost was recorded as costing nothing"
else
  pass "a missing cost stays missing rather than becoming zero"
fi
rm -f "$SANDBOX/docs/tasks/0006-the-sixth-thing.md"
rm -f "$SANDBOX/docs/tasks/0005-the-fifth-thing.md"

printf '\n'
if [ "$FAILURES" -eq 0 ]; then
  log "all checks passed"
else
  log "$FAILURES check(s) failed"
  exit 1
fi
