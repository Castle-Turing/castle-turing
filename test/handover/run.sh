#!/usr/bin/env bash
# test/handover/run.sh — the operator handover's claim-checker, held to
# what docs/tasks/0062-the-operator-handover.md says it must catch.
#
# The golden test the brief names: generate the handover for the real
# week of 2026-09-01 through 2026-09-05, and run the checker over it.
# The generated half of that ran once, by hand, against the live forge
# (tools/handover.sh); what is committed here is its ledger and its
# output, frozen. This harness runs the checking half, which is the half
# with no model, no network and no cost in it.
#
# That split is only possible because tools/handover-check.py is a pure
# function of (ledger, handover) — it never reads git, the forge or the
# working tree. A checker that re-derived truth from the live repo would
# fail this test for reasons having nothing to do with the handover it
# was checking: briefs get swept into docs/tasks/done/, branches get
# deleted, pull requests collect comments. See the header of
# tools/handover-ledger.py.
#
# Same conventions as test/agent-loop next door: plain bash, stdlib
# python3, no Nix, no network, zero models.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE="$REPO_ROOT/test/handover/fixture"
CHECK="$REPO_ROOT/tools/handover-check.py"

log() { printf '>>> %s\n' "$*"; }
FAILURES=0
fail() { printf '    FAIL: %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
pass() { printf '    ok: %s\n' "$*"; }

# --- the golden handover -------------------------------------------------

log "the golden handover for 2026-09-01..2026-09-05 passes its own ledger"
if python3 "$CHECK" --ledger "$FIXTURE/ledger.json" "$FIXTURE/handover.md" >/dev/null; then
  pass "every citation resolves and every receipt matches"
else
  python3 "$CHECK" --ledger "$FIXTURE/ledger.json" "$FIXTURE/handover.md" || true
  fail "the golden handover no longer passes"
fi

log "the synthetic handover passes the invented ledger"
if python3 "$CHECK" --ledger "$FIXTURE/synthetic-ledger.json" \
     "$FIXTURE/synthetic-handover.md" >/dev/null; then
  pass "the fixture the reject cases are mutated from is itself clean"
else
  python3 "$CHECK" --ledger "$FIXTURE/synthetic-ledger.json" \
    "$FIXTURE/synthetic-handover.md" || true
  fail "the synthetic handover no longer passes, so every reject below proves nothing"
fi

# --- what the checker must refuse ----------------------------------------
#
# One file per hazard, each a minimal mutation of synthetic-handover.md
# above, and each stating in its first line the violation code it exists
# to provoke. Asserting on the code rather than only on the exit status
# is the point: a fixture that fails for some *other* reason would
# otherwise look like a working check.

log "every reject fixture is refused, for the reason it names"
shopt -s nullglob
REJECTS=("$FIXTURE"/rejects/*.md)
if [ "${#REJECTS[@]}" -eq 0 ]; then
  fail "no reject fixtures found — this harness would pass vacuously"
fi
for f in "${REJECTS[@]}"; do
  name="$(basename "$f" .md)"
  expected="$(sed -n '1s/.*expect: \([A-Z-]*\).*/\1/p' "$f")"
  if [ -z "$expected" ]; then
    fail "$name states no expected violation code in its first line"
    continue
  fi
  out="$(python3 "$CHECK" --ledger "$FIXTURE/synthetic-ledger.json" "$f" 2>&1 || true)"
  if python3 "$CHECK" --ledger "$FIXTURE/synthetic-ledger.json" "$f" >/dev/null 2>&1; then
    fail "$name was accepted; it should have been refused with $expected"
  elif printf '%s' "$out" | grep -q "^  $expected "; then
    pass "$name refused with $expected"
  else
    fail "$name was refused, but not with $expected. Got:"
    printf '%s\n' "$out" | sed 's/^/        /'
  fi
done

# --- the checker reads nothing but its two arguments ---------------------
#
# The purity claim above is load-bearing enough to test rather than
# assert. Run the checker from a directory that is not a git repository
# and holds nothing but copies of the two inputs: if it had grown a
# `git` call or a read of docs/, this is where that shows up.

log "the checker is a pure function of (ledger, handover)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
cp "$FIXTURE/ledger.json" "$FIXTURE/handover.md" "$SANDBOX/"
if ( cd "$SANDBOX" && python3 "$CHECK" --ledger ledger.json handover.md >/dev/null 2>&1 ); then
  pass "it checks the same outside the repository, with no git and no docs/ around it"
else
  fail "the checker needs something other than its two arguments"
fi

# --- no private-layer data in a committed fixture ------------------------
#
# CLAUDE.md's first hard rule, tested rather than trusted. The ledger
# reader's first run wrote 308 real journal record ids and their
# absolute paths into a fixture, which is why this check exists at all:
# a journal is the private layer, and a ledger is a file an agent may be
# about to commit.

log "no private-layer data in the committed fixtures"
LEAKS=0
for f in "$FIXTURE"/*.json "$FIXTURE"/*.md "$FIXTURE"/rejects/*.md; do
  if grep -nE '/home/|/Users/|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$f" >/dev/null; then
    fail "$(basename "$f") contains a home path or an email address"
    grep -nE '/home/|/Users/|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$f" | sed 's/^/        /'
    LEAKS=$((LEAKS + 1))
  fi
done
if python3 - "$FIXTURE/ledger.json" <<'PYEOF'
import json, sys
ledger = json.load(open(sys.argv[1]))
sys.exit(0 if not ledger["journal"]["records"] else 1)
PYEOF
then
  [ "$LEAKS" -eq 0 ] && pass "the committed ledger carries no journal records and no home paths"
else
  fail "the committed ledger carries journal records — rebuild it with --no-journal"
fi

# --- the ledger reader parses ---------------------------------------------
#
# Not a behavioural test of the reader: it needs `gh` and the network,
# which this harness deliberately has neither of. This is the cheap half
# — that the file the generator depends on is at least loadable, so a
# syntax error in it surfaces here rather than at the resident's prompt.

log "the ledger reader and the generator are loadable"
if python3 -c "
import ast, pathlib, sys
for p in ('tools/handover-ledger.py', 'tools/handover-check.py'):
    ast.parse(pathlib.Path('$REPO_ROOT/' + p).read_text())
"; then
  pass "both python tools parse"
else
  fail "a handover tool does not parse"
fi
if bash -n "$REPO_ROOT/tools/handover.sh"; then
  pass "tools/handover.sh parses"
else
  fail "tools/handover.sh does not parse"
fi

echo
if [ "$FAILURES" -ne 0 ]; then
  echo "test/handover: $FAILURES assertion(s) failed."
  exit 1
fi
echo "test/handover: all assertions held."
