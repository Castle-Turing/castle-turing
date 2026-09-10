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

base_log | sed '2s/\t-\t-\t-\t2\t2\t/\t1\t-\t-\t2\t2\t/' > "$LOG"
reject "a redirect count with no miscorrection rate beside it" \
  "a detection rate is never logged alone"

base_log | sed '2s/\t-\t-\t-\t2\t2\t/\t1\t2\t-\t2\t2\t/' > "$LOG"
reject "more redirects judged wrong than were made" "exceeds redirects"

base_log | sed '2s/\t-\t-\t-\t2\t2\t/\t1\t0\t-\t2\t2\t/' > "$LOG"
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

base_log | sed '2s/\t-\t-\t-\t2\t2\t-\t/\t2\t1\t-\t2\t2\tpr-comment-9\t/' > "$LOG"
accept "a verdict pair arriving together with its citation"

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
