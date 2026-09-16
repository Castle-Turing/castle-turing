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

log "the receipt/verdict split, and the citations that carry it"

# `verdict` rewrites columns 15..20 in one go: redirects, redirects_wrong,
# reworks, findings, findings_fixed, verdict_ref. Written out rather than
# patched cell by cell because the rules being tested are about how those
# six agree with each other.
verdict() { # verdict <redirects> <wrong> <verdict_ref>
  base_log | sed "2s#\t-\t-\t-\t2\t2\t-\t#\t$1\t$2\t-\t2\t2\t$3\t#"
}
CITE1="redirect/pr-7-comment-9"
CITE2="redirect/pr-8-comment-3"
REASSESS="reassessed/record-20260914T051123Z-answer-ab12cd"

verdict 1 - - > "$LOG"
reject "a redirect count with no citation behind it" "cites 0 redirect event(s)"

verdict 2 - "$CITE1" > "$LOG"
reject "a redirect count that disagrees with its citations" \
  "the count is the citations"

verdict - - "$CITE1" > "$LOG"
reject "a citation with no count beside it" "redirects is unrecorded"

verdict 1 2 "$CITE1" > "$LOG"
reject "more redirects judged wrong than were made" "exceeds redirects"

verdict - 0 - > "$LOG"
reject "a miscorrection count with no redirects to divide" \
  "redirects_wrong recorded without redirects"

# The rule the whole column turns on: a value here says the resident
# looked again, so a value with nowhere they looked is a fabrication —
# including, and especially, a 0.
verdict 1 0 "$CITE1" > "$LOG"
reject "a reassessment with nowhere the resident made it" \
  "cites no resident reassessment"

verdict 1 - "pr-comment-9" > "$LOG"
reject "a citation in the shape schema 1 used to allow" "is not <redirect|reassessed>"

verdict 2 - "$CITE1,$CITE1" > "$LOG"
reject "one citation counted twice" "twice"

verdict 1 - "redirect/somebody-said-so" > "$LOG"
reject "a citation naming no resolvable place" "is not <redirect|reassessed>"

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

verdict 1 - "$CITE1" > "$LOG"
accept "a cited redirect whose reassessment is still pending"

verdict 2 1 "$CITE1,$CITE2,$REASSESS" > "$LOG"
accept "two cited redirects and a cited reassessment of them"

verdict 0 0 - > "$LOG"
accept "no redirects and none wrong, which is arithmetic rather than judgment"

base_log | sed '2s/\tlive\t-$/\tlive\tan amended note, which is the one cell that may be/' > "$LOG"
accept "a note rewritten, because a note may need redacting"

{ base_log; row 0004-the-fourth-thing 1 2026-08-07 - -; } > "$LOG"
brief 0004-the-fourth-thing deep
accept "a new row appended with its outcome still pending"
rm -f "$SANDBOX/docs/tasks/0004-the-fourth-thing.md"

# --- append-only, per citation -------------------------------------------
#
# The rules above hold a row against a base revision that carries no
# verdict at all. These hold one against a base that does — which is the
# only shape in which a verdict can be *rewritten*, and therefore the
# only shape that matters. The base revision is advanced to a log with a
# cited redirect in it, and `base_log` is redefined so the resets below
# land back on that.

log "append-only, per citation"

CITED_BASE="$(verdict 1 - "$CITE1")"
printf '%s\n' "$CITED_BASE" > "$LOG"
git -C "$SANDBOX" -c user.email=t@t -c user.name=t commit -aqm "a cited redirect"
git -C "$SANDBOX" update-ref refs/remotes/origin/main HEAD
base_log() { printf '%s\n' "$CITED_BASE"; }

cited() { # cited <redirects> <wrong> <verdict_ref>
  printf '%s\n' "$CITED_BASE" \
    | sed "2s#\t1\t-\t-\t2\t2\t$CITE1\t#\t$1\t$2\t-\t2\t2\t$3\t#"
}

cited 2 - "$CITE1" > "$LOG"
reject "a redirect count raised with no new citation" "the count is the citations"

cited 2 - "$CITE1,$CITE2" > "$LOG"
accept "a second redirect, arriving with the citation that licenses it"

cited 1 - "$CITE2" > "$LOG"
reject "an existing citation swapped for another" "never edited"

cited 0 - - > "$LOG"
reject "a citation deleted and the count walked back" "never edited"

cited 2 - "$CITE2,$CITE1" > "$LOG"
reject "citations reordered so the appended one is not last" "never edited"

cited 1 0 "$CITE1" > "$LOG"
reject "a reassessment written with nothing new cited" "cites no resident reassessment"

cited 1 0 "$CITE1,$REASSESS" > "$LOG"
accept "a reassessment maturing pending to zero, with the citation for it"

# The move the brief spends a page on: a second redirect raising the
# count is not an overwrite, and the log has to be able to tell that from
# one.
cited 2 1 "$CITE1,$CITE2,$REASSESS" > "$LOG"
accept "a second redirect and a reassessment of both, each cited"

# --- redirect, the verdict logger ----------------------------------------
#
# `redirect` is the only thing in this repository that writes a verdict
# cell, so its refusals are the whole integrity story. The forge is
# stubbed: every case the resolver must tell apart is a fixture file, and
# anything else 404s exactly as the real `gh` does. No network.

log "redirect"

mkdir -p "$WORKDIR/bin" "$WORKDIR/gh" "$WORKDIR/journal"
cat > "$WORKDIR/bin/gh" <<'SH'
#!/usr/bin/env bash
# A stand-in forge. `gh api <path>` serves $GH_FIXTURE/<path with / as _>
# or 404s; `--jq .permission` reads that one field out of it.
if [ "$1 $2" = "repo view" ]; then echo "castle/turing"; exit 0; fi
f="$GH_FIXTURE/$(printf '%s' "$2" | tr '/' '_')"
if [ ! -f "$f" ]; then echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi
if [ "${3:-}" = "--jq" ]; then
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["permission"])' "$f"
else
  cat "$f"
fi
SH
chmod +x "$WORKDIR/bin/gh"
export GH_FIXTURE="$WORKDIR/gh"

comment() { # comment <id> <pr> <login> <type>
  printf '{"user": {"login": "%s", "type": "%s"}, "issue_url": "https://api.github.com/repos/castle/turing/issues/%s"}\n' \
    "$3" "$4" "$2" > "$GH_FIXTURE/repos_castle_turing_issues_comments_$1"
}
perm() { # perm <login> <permission>
  printf '{"permission": "%s"}\n' "$2" \
    > "$GH_FIXTURE/repos_castle_turing_collaborators_$1_permission"
}
record() { # record <id> <type>
  printf -- '---\nid: %s\ntype: %s\nprovenance: requested\nrefs: \nseat: resident\ncreated: 2026-09-14T05:11:23Z\n---\n\nbody\n' \
    "$1" "$2" > "$WORKDIR/journal/$1.md"
}

comment 100 7 theresident User
comment 200 7 theresident User
comment 300 7 anagent User
comment 400 7 somebot Bot
perm theresident admin
perm anagent write
record 20260914T051123Z-answer-ab12cd answer
record 20260914T051124Z-request-ff00aa request

# The log `redirect` writes into, and a base revision to hold it against.
base_log > "$LOG"
git -C "$SANDBOX" -c user.email=t@t -c user.name=t commit -aqm "reset for redirect" \
  --allow-empty
git -C "$SANDBOX" update-ref refs/remotes/origin/main HEAD

redirect() {
  PATH="$WORKDIR/bin:$PATH" python3 "$OUTCOMES" --repo-root "$SANDBOX" redirect \
    --journal-dir "$WORKDIR/journal" "$@"
}
cell() { # cell <task> <column-number>
  grep "	$1	" "$LOG" | cut -f"$2"
}
refuses() { # refuses <name> <expected substring> <args...>
  local name=$1 expect=$2 out; shift 2
  local before; before="$(cat "$LOG")"
  if out=$(redirect "$@" 2>&1); then
    fail "$name: accepted"
  elif ! printf '%s' "$out" | grep -qF -- "$expect"; then
    fail "$name: refused for the wrong reason: $(printf '%s' "$out" | head -1)"
  elif [ "$before" != "$(cat "$LOG")" ]; then
    fail "$name: refused and wrote to the log anyway"
  else
    pass "$name"
  fi
}

refuses "a task with no row" "no row for" \
  0009-a-task-that-never-existed --ref 7#issuecomment-100
refuses "a reference in no shape this understands" "is not a citation this understands" \
  0002-the-second-thing --ref "the resident said so on Tuesday"
refuses "a reference that resolves to nothing" "Not Found" \
  0002-the-second-thing --ref 7#issuecomment-999
refuses "a reference written by the agent rather than the resident" \
  "whose permission on" 0002-the-second-thing --ref 7#issuecomment-300
refuses "a reference written by a bot" "a bot account cannot hold one" \
  0002-the-second-thing --ref 7#issuecomment-400
refuses "a reassessment of a task with no redirect recorded" \
  "no recorded redirect to reassess" \
  0002-the-second-thing --ref 7#issuecomment-100 --wrong 0
refuses "a record the journal does not have" "names no record at" \
  0002-the-second-thing --ref 20260101T000000Z-answer-000000
refuses "a record type a worker tenant is allowed to write" "is a 'request' record" \
  0002-the-second-thing --ref 20260914T051124Z-request-ff00aa

if out=$(PATH="$WORKDIR/bin:$PATH" python3 "$OUTCOMES" --repo-root "$SANDBOX" \
          redirect 0002-the-second-thing --ref 7#issuecomment-300 \
          --resident theresident 2>&1); then
  fail "a configured resident did not override the permission check"
elif printf '%s' "$out" | grep -qF "the configured resident is"; then
  pass "a named resident refuses a reference written by anyone else"
else
  fail "the configured-resident refusal said: $(printf '%s' "$out" | head -1)"
fi

# A PATH with python3 on it and no gh — not an empty PATH, which would
# only prove that the test runner cannot find an interpreter.
mkdir -p "$WORKDIR/nogh"
ln -sf "$(command -v python3)" "$WORKDIR/nogh/python3"
if out=$(PATH="$WORKDIR/nogh" python3 "$OUTCOMES" --repo-root "$SANDBOX" redirect \
          0002-the-second-thing --ref 7#issuecomment-100 2>&1); then
  fail "a missing gh let an unverified verdict through"
elif printf '%s' "$out" | grep -qF "refuses to write an unverified verdict"; then
  pass "no gh is a refusal, not a skipped check"
else
  fail "a missing gh said: $(printf '%s' "$out" | head -1)"
fi

log "redirect, writing"

if redirect 0002-the-second-thing --ref 7#issuecomment-100 >/dev/null \
   && [ "$(cell 0002-the-second-thing 15)" = "1" ] \
   && [ "$(cell 0002-the-second-thing 16)" = "-" ] \
   && [ "$(cell 0002-the-second-thing 20)" = "redirect/pr-7-comment-100" ]; then
  pass "a redirect matures the row to 1, cited, with the reassessment pending"
else
  fail "the first redirect wrote: $(cell 0002-the-second-thing 15) \
$(cell 0002-the-second-thing 16) $(cell 0002-the-second-thing 20)"
fi

before="$(cat "$LOG")"
if redirect 0002-the-second-thing --ref pr-7-comment-100 >/dev/null \
   && [ "$before" = "$(cat "$LOG")" ]; then
  pass "replaying a recorded citation, in the form the tool itself stored, changes nothing"
else
  fail "a replay was not a no-op"
fi

if redirect 0002-the-second-thing --ref 7#issuecomment-200 >/dev/null \
   && [ "$(cell 0002-the-second-thing 15)" = "2" ] \
   && [ "$(cell 0002-the-second-thing 20)" = "redirect/pr-7-comment-100,redirect/pr-7-comment-200" ]; then
  pass "a second, distinct citation raises the count to 2"
else
  fail "the second redirect wrote: $(cell 0002-the-second-thing 15) \
$(cell 0002-the-second-thing 20)"
fi

refuses "a reassessment claiming more wrong than there were redirects" \
  "exceeds the 2 redirect(s)" \
  0002-the-second-thing --ref 20260914T051123Z-answer-ab12cd --wrong 3

if redirect 0002-the-second-thing --ref 20260914T051123Z-answer-ab12cd --wrong 1 \
     >/dev/null \
   && [ "$(cell 0002-the-second-thing 16)" = "1" ]; then
  pass "a journal answer record matures redirects_wrong, pending to 1"
else
  fail "the reassessment wrote redirects_wrong=$(cell 0002-the-second-thing 16)"
fi

refuses "a different number replayed against a citation already spent" \
  "needs its own citation" \
  0002-the-second-thing --ref 20260914T051123Z-answer-ab12cd --wrong 2

log "and the result of all that passes the checker"
if check >/dev/null 2>&1; then
  pass 'two cited redirects and a cited reassessment survive the checker'
else
  check || true
  fail "redirect wrote a row its own checker rejects"
fi
base_log > "$LOG"

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
