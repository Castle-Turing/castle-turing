#!/usr/bin/env bash
# test/agent-loop/outbox.sh — a worker turn's finding about the
# framework becomes a backlog entry on a branch, and every way of
# getting that wrong is refused by name
# (docs/tasks/0042-finding-outbox.md's verification plan).
#
# **Its own file rather than more scenarios in apply.sh, because it
# inverts that file's central assertion.** There,
# `assert_mechanism_untouched` holds after every scenario without
# exception — nothing may ever write the framework checkout. Here the
# mechanism checkout is exactly what moves, and what must not move is
# the resident's own branch inside it, `main`, and the working tree.
# Two claims that opposite in the same suite must not share a helper
# name.
#
# Same conventions as apply.sh otherwise: two real git checkouts under
# $WORKDIR, a state repository beside them, a git identity scoped to
# this process, the notify stub, plain bash and stdlib python3, no Nix,
# zero models, zero network. Nothing here is a real path, a real
# complaint or a real finding; every string is invented.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CASTLE="$REPO_ROOT/agent/castle"
MODAL="$REPO_ROOT/agent/castle-modal"
WORKER="$REPO_ROOT/test/agent-loop/scripted-worker-finding.sh"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/castle-outbox.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT
WORKDIR="$(cd "$WORKDIR" && pwd -P)"

log() { printf '>>> %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

export GIT_AUTHOR_NAME="castle-outbox-fixture"
export GIT_AUTHOR_EMAIL="fixture@example.invalid"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

# The isolation that survives `_run_git`'s `GIT_*` strip, for the reason
# apply.sh gives: this file commits, and a developer with
# `commit.gpgsign = true` set globally would otherwise watch every
# scenario fail for a reason unrelated to the code.
export HOME="$WORKDIR/nobody"
export XDG_CONFIG_HOME="$WORKDIR/nobody/.config"
mkdir -p "$XDG_CONFIG_HOME"

# ---------------------------------------------------------------------
log "building the two checkouts"
# ---------------------------------------------------------------------
# `git archive` rather than `cp -r`, the same choice apply.sh makes: only
# committed content, and what the fixture holds is the real current
# docs/backlog/ rather than a synthetic stand-in — which is what makes
# the "something by that name is already filed" scenario mean something.
MECHANISM="$WORKDIR/mechanism"
mkdir -p "$MECHANISM"
git -C "$REPO_ROOT" archive HEAD | tar -x -C "$MECHANISM"
git -C "$MECHANISM" init -q
git -C "$MECHANISM" add -A
git -C "$MECHANISM" commit -q -m "fixture: this framework at HEAD"
# A remote-tracking ref with no remote behind it. The outbox branches
# from `origin/main` and never fetches, so this is exactly what it needs
# and exactly as much as it needs — a fixture with a real remote would
# be testing git rather than this code.
git -C "$MECHANISM" update-ref refs/remotes/origin/main HEAD
git -C "$MECHANISM" branch -q -M main
# And then the resident goes off and works on something else. Every
# scenario below asserts this branch is still checked out, still at this
# commit, with a clean tree: the outbox must never touch what a resident
# has in flight.
git -C "$MECHANISM" checkout -q -b resident-work
echo "# a fixture file the resident is in the middle of" > "$MECHANISM/RESIDENT-WIP.md"
git -C "$MECHANISM" add RESIDENT-WIP.md
git -C "$MECHANISM" commit -q -m "fixture: the resident is working on something"
MECHANISM_HEAD="$(git -C "$MECHANISM" rev-parse HEAD)"
MECHANISM_MAIN="$(git -C "$MECHANISM" rev-parse main)"

# The private layer, which no scenario in this file ever changes: this
# tenant proposes nothing, so every turn here ends with an empty diff.
PRIVATE="$WORKDIR/private"
mkdir -p "$PRIVATE"
cat > "$PRIVATE/resident.nix" <<'EOF'
# Synthetic private layer, harness fixture only.
{
  castle.admin.username = "resident";
}
EOF
git -C "$PRIVATE" init -q
git -C "$PRIVATE" add -A
git -C "$PRIVATE" commit -q -m "fixture: a synthetic private layer"
PRIVATE_HEAD="$(git -C "$PRIVATE" rev-parse HEAD)"

STATE_REPO="$WORKDIR/private-state"
mkdir -p "$STATE_REPO"
git -C "$STATE_REPO" init -q
export CASTLE_STATE_DIR="$STATE_REPO"
export XDG_RUNTIME_DIR="$WORKDIR/runtime"
mkdir -p "$XDG_RUNTIME_DIR"
JOURNAL="$CASTLE_STATE_DIR/journal"

export CASTLE_NOTIFY_LOG="$WORKDIR/notify.log"
export CASTLE_NOTIFY_COMMAND="$REPO_ROOT/test/agent-loop/notify-stub.sh"
: > "$CASTLE_NOTIFY_LOG"

export CASTLE_WORKER_COMMAND="$WORKER"
export CASTLE_PRIVATE_ROOT="$PRIVATE"
export CASTLE_MECHANISM_ROOT="$MECHANISM"

# ---------------------------------------------------------------------
# Journal helpers, copied from apply.sh rather than shared: these are
# plain bash harnesses with no library between them.
# ---------------------------------------------------------------------
newest_of() {
  xargs -r stat -c '%.Y	%n' 2>/dev/null | sort -k1,1n | tail -1 | cut -f2-
}
field_of() { sed -n "s/^$2: //p" "$1"; }
worker_result_for() {
  grep -l "^refs: $1," "$JOURNAL"/*-result-*.md 2>/dev/null | newest_of
}
outbox_records() {
  grep -l '^seat: outbox$' "$JOURNAL"/*-result-*.md 2>/dev/null || true
}
outbox_record_for() {
  grep -l "^refs: $1\$" "$JOURNAL"/*-result-*.md 2>/dev/null | newest_of
}
count_outbox_records() { outbox_records | grep -c . || true; }

# ---------------------------------------------------------------------
# The assertion this whole file turns on, and its inverse.
# ---------------------------------------------------------------------

# What must be true after EVERY scenario, including the one that files
# successfully: the resident's own branch is still checked out, still
# where they left it, `main` never moved, and there is nothing dirty.
assert_resident_work_untouched() {
  local where="$1"
  [ "$(git -C "$MECHANISM" rev-parse --abbrev-ref HEAD)" = "resident-work" ] \
    || fail "$where: the outbox changed which branch is checked out"
  [ "$(git -C "$MECHANISM" rev-parse HEAD)" = "$MECHANISM_HEAD" ] \
    || fail "$where: the resident's own branch moved"
  [ "$(git -C "$MECHANISM" rev-parse main)" = "$MECHANISM_MAIN" ] \
    || fail "$where: main moved, and nothing here may ever write main"
  [ -z "$(git -C "$MECHANISM" status --porcelain -- docs/backlog)" ] \
    || fail "$where: the working tree under docs/backlog is dirty — $(git -C "$MECHANISM" status --porcelain -- docs/backlog)"
}

assert_private_untouched() {
  local where="$1"
  [ -z "$(git -C "$PRIVATE" status --porcelain)" ] \
    || fail "$where: the private checkout was mutated"
  [ "$(git -C "$PRIVATE" rev-parse HEAD)" = "$PRIVATE_HEAD" ] \
    || fail "$where: the private checkout's HEAD moved"
}

assert_no_finding_branches_beyond() {
  local where="$1" want="$2" count
  count="$(git -C "$MECHANISM" for-each-ref --format='%(refname)' 'refs/heads/castle/finding/*' | grep -c . || true)"
  [ "$count" = "$want" ] \
    || fail "$where: the mechanism checkout has $count finding branches, expected $want"
}

# The shape every outbox record has, whatever its outcome — and the one
# property docs/tasks/0042 §5 exists to protect.
assert_outbox_record_shape() {
  local where="$1" record="$2" result="$3" request="$4" outcome="$5"
  [ -n "$record" ] || fail "$where: no outbox record was written"
  grep -q '^seat: outbox$' "$record" \
    || fail "$where: the record was not written by the outbox seat: $(field_of "$record" seat)"
  grep -q '^provenance: initiated$' "$record" \
    || fail "$where: the record's provenance is not 'initiated': $(field_of "$record" provenance)"
  # The refs trap, stated as a test. A result naming the request is read
  # by `closing_result`'s clause (b) as the account closing a dangling
  # worker claim; one naming the claim is clause (a) and asserts it IS
  # that turn's account. Both are permanent in an append-only journal.
  grep -q "^refs: $result\$" "$record" \
    || fail "$where: the record's refs are not the worker result alone: $(grep '^refs:' "$record")"
  grep -q "^refs:.*$request" "$record" \
    && fail "$where: the outbox record names the request — closing_result would read it as closing a dangling worker claim"
  [ "$(field_of "$record" finding-outcome)" = "$outcome" ] \
    || fail "$where: finding-outcome is '$(field_of "$record" finding-outcome)', expected '$outcome'"
}

# Every refusal preserves the finding verbatim, because on those paths
# the record body is the only copy that exists anywhere.
assert_finding_preserved() {
  local where="$1" record="$2"
  grep -q 'The finding itself, verbatim' "$record" \
    || fail "$where: the refusal did not preserve the finding text"
}

# One turn, through the real worker contract. Echoes "<request> <result>".
new_turn() {
  local marker="$1" request result
  request="$("$CASTLE" ask "OUTBOX-FIXTURE $marker: an invented complaint for a fixture tenant.")"
  "$CASTLE" work "$request" >/dev/null
  result="$(worker_result_for "$request")"
  [ -n "$result" ] || fail "$marker: the turn wrote no worker result"
  printf '%s %s\n' "$request" "$(basename "$result" .md)"
}

# ---------------------------------------------------------------------
log "1. a turn that writes a finding produces the branch commit and the record"
# ---------------------------------------------------------------------
read -r REQ RES <<<"$(new_turn "FINDING-GOOD-alpha")"
BRANCH="castle/finding/the-fixture-harness-noticed-something-alpha"
ENTRY="docs/backlog/the-fixture-harness-noticed-something-alpha.md"

git -C "$MECHANISM" rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null \
  || fail "1: the finding branch was not created"
COUNT="$(git -C "$MECHANISM" rev-list --count "main..$BRANCH")"
[ "$COUNT" = "1" ] || fail "1: the branch carries $COUNT commits, not exactly one"
PARENT="$(git -C "$MECHANISM" rev-parse "$BRANCH^")"
[ "$PARENT" = "$MECHANISM_MAIN" ] \
  || fail "1: the finding commit is not parented on origin/main"
NAMED="$(git -C "$MECHANISM" show --name-only --format= "$BRANCH" | sed '/^$/d')"
[ "$NAMED" = "$ENTRY" ] || fail "1: the commit names [$NAMED], expected [$ENTRY]"
[ "$(git -C "$MECHANISM" show -s --format=%cn "$BRANCH")" = "Castle outbox" ] \
  || fail "1: the commit's committer is not the outbox seat"
[ "$(git -C "$MECHANISM" show -s --format=%ce "$BRANCH")" = "outbox@castle.invalid" ] \
  || fail "1: the commit's committer address is not the reserved one"
git -C "$MECHANISM" show -s --format=%B "$BRANCH" | grep -qF "$RES" \
  || fail "1: the commit message does not name the worker result it came from"
git -C "$MECHANISM" show -s --format=%B "$BRANCH" | grep -q 'Nothing was pushed' \
  || fail "1: the commit message does not say nothing was pushed"

# Byte-exact: what is committed is what the tenant wrote, not a copy
# that went through a record body. Reproduced independently of the
# tenant so the two cannot drift together.
git -C "$MECHANISM" show "$BRANCH:$ENTRY" > "$WORKDIR/committed"
grep -q '^Title: The fixture harness noticed something alpha$' "$WORKDIR/committed" \
  || fail "1: the committed entry has no Title header"
grep -q '^Destination: mechanism$' "$WORKDIR/committed" \
  || fail "1: the committed entry has no Destination header"
grep -q 'a fenced block, inside the finding' "$WORKDIR/committed" \
  || fail "1: the committed entry lost the tenant's own fenced block"

REC="$(outbox_record_for "$RES")"
assert_outbox_record_shape "1" "$REC" "$RES" "$REQ" "filed"
[ "$(field_of "$REC" finding-commit)" = "$(git -C "$MECHANISM" rev-parse "$BRANCH")" ] \
  || fail "1: finding-commit does not name the branch tip"
[ "$(field_of "$REC" finding-branch)" = "$BRANCH" ] \
  || fail "1: finding-branch does not name the branch"
[ "$(field_of "$REC" finding-destination)" = "mechanism" ] \
  || fail "1: finding-destination does not name the checkout role"
[ "$(field_of "$REC" outcome)" = "completed" ] || fail "1: outcome is not completed"
grep -qF "$ENTRY" "$REC" || fail "1: the record does not name the path it filed"
grep -q 'nothing was pushed' "$REC" || fail "1: the record does not say nothing was pushed"
grep -q 'The finding itself, verbatim' "$REC" \
  && fail "1: a filed finding must NOT also be copied into the record body — the committed file is the artifact"
assert_resident_work_untouched "1"
assert_private_untouched "1"
assert_no_finding_branches_beyond "1" 1

# The worker result itself is unaffected: filing a finding is not a turn
# of the errand, so the errand's own account is exactly what it was.
[ "$(field_of "$JOURNAL/$RES.md" outcome)" = "completed" ] \
  || fail "1: the worker result did not complete"
[ -z "$(field_of "$JOURNAL/$RES.md" finding-outcome)" ] \
  || fail "1: the WORKER result carries a finding-outcome; that field is the outbox's"

# ---------------------------------------------------------------------
log "2. the status surface and the digest both report it"
# ---------------------------------------------------------------------
"$MODAL" --mode status --limit 20 > "$WORKDIR/status.txt" </dev/null
grep -q "finding -> filed: $BRANCH in the mechanism checkout" "$WORKDIR/status.txt" \
  || fail "2: the status surface does not name the branch and the checkout: $(cat "$WORKDIR/status.txt")"
"$CASTLE" digest > "$WORKDIR/digest.txt"
grep -q '^- finding: filed$' "$WORKDIR/digest.txt" \
  || fail "2: the digest does not report that a finding landed"

# ---------------------------------------------------------------------
log "3. an empty finding file produces nothing at all"
# ---------------------------------------------------------------------
BEFORE="$(count_outbox_records)"
read -r REQ RES <<<"$(new_turn "FINDING-NONE")"
[ "$(count_outbox_records)" = "$BEFORE" ] \
  || fail "3: an empty finding file wrote an outbox record"
[ -z "$(outbox_record_for "$RES")" ] || fail "3: an empty finding file wrote a record"
assert_resident_work_untouched "3"
assert_no_finding_branches_beyond "3" 1

# ---------------------------------------------------------------------
log "4. a bad Destination is refused by name"
# ---------------------------------------------------------------------
read -r REQ RES <<<"$(new_turn "FINDING-BADDEST")"
REC="$(outbox_record_for "$RES")"
assert_outbox_record_shape "4" "$REC" "$RES" "$REQ" "refused-destination-unknown"
grep -q 'somewhere-else' "$REC" || fail "4: the refusal does not name the value it refused"
[ -z "$(field_of "$REC" finding-branch)" ] \
  || fail "4: a refusal stamped finding-branch"
assert_finding_preserved "4" "$REC"
assert_resident_work_untouched "4"
assert_no_finding_branches_beyond "4" 1

# ---------------------------------------------------------------------
log "5. a malformed finding, and one with no Title, are refused by name"
# ---------------------------------------------------------------------
read -r REQ RES <<<"$(new_turn "FINDING-NOHEADER")"
REC="$(outbox_record_for "$RES")"
assert_outbox_record_shape "5" "$REC" "$RES" "$REQ" "refused-malformed"
assert_finding_preserved "5" "$REC"

read -r REQ RES <<<"$(new_turn "FINDING-NOTITLE")"
REC="$(outbox_record_for "$RES")"
assert_outbox_record_shape "5b" "$REC" "$RES" "$REQ" "refused-malformed"
grep -q 'Title' "$REC" || fail "5b: the refusal does not say which key was missing"
assert_finding_preserved "5b" "$REC"
assert_resident_work_untouched "5"
assert_no_finding_branches_beyond "5" 1

# ---------------------------------------------------------------------
log "6. a name that is already filed is refused rather than disambiguated"
# ---------------------------------------------------------------------
read -r REQ RES <<<"$(new_turn "FINDING-DUP")"
REC="$(outbox_record_for "$RES")"
assert_outbox_record_shape "6" "$REC" "$RES" "$REQ" "refused-already-there"
grep -q 'declarative-wifi' "$REC" || fail "6: the refusal does not name the entry it collided with"
assert_finding_preserved "6" "$REC"
assert_resident_work_untouched "6"
assert_no_finding_branches_beyond "6" 1

# ---------------------------------------------------------------------
log "7. a dirty checkout under the target path is refused politely"
# ---------------------------------------------------------------------
# The resident is drafting the very entry this finding would create.
DIRTY_ENTRY="docs/backlog/the-fixture-harness-noticed-something-beta.md"
echo "# the resident is already writing this one" > "$MECHANISM/$DIRTY_ENTRY"
read -r REQ RES <<<"$(new_turn "FINDING-GOOD-beta")"
REC="$(outbox_record_for "$RES")"
assert_outbox_record_shape "7" "$REC" "$RES" "$REQ" "refused-tree-dirty"
grep -q 'status ??' "$REC" \
  || fail "7: the refusal does not report the status letters: $(grep -n 'uncommitted' "$REC")"
grep -qF "$DIRTY_ENTRY" "$REC" \
  && fail "7: the refusal names the resident's own file — a dirty-tree refusal reports a count, never a name"
assert_finding_preserved "7" "$REC"
assert_no_finding_branches_beyond "7" 1
rm -f "$MECHANISM/$DIRTY_ENTRY"
assert_resident_work_untouched "7"

# ---------------------------------------------------------------------
log "8. no mechanism checkout configured is an honest dead-end, not a drop"
# ---------------------------------------------------------------------
(
  unset CASTLE_MECHANISM_ROOT
  REQ8="$("$CASTLE" ask "OUTBOX-FIXTURE FINDING-GOOD-gamma: an invented complaint for a fixture tenant.")"
  "$CASTLE" work "$REQ8" >/dev/null
  RES8="$(basename "$(worker_result_for "$REQ8")" .md)"
  REC8="$(outbox_record_for "$RES8")"
  assert_outbox_record_shape "8" "$REC8" "$RES8" "$REQ8" "refused-destination-unconfigured"
  grep -q 'castle.agent.repo.mechanism' "$REC8" \
    || fail "8: the dead-end does not name the option that would change it"
  assert_finding_preserved "8" "$REC8"
)
assert_resident_work_untouched "8"
assert_no_finding_branches_beyond "8" 1

# ---------------------------------------------------------------------
log "9. nothing is left in the worker scratch directory"
# ---------------------------------------------------------------------
LEFT="$(find "$CASTLE_STATE_DIR/work" -type f 2>/dev/null | wc -l | tr -d ' ')"
[ "$LEFT" = "0" ] \
  || fail "9: $LEFT scratch files were left behind in $CASTLE_STATE_DIR/work"

# ---------------------------------------------------------------------
log "10. the journal validates"
# ---------------------------------------------------------------------
"$CASTLE" validate || fail "10: castle validate rejected the journal this run produced"

# And the guard that keeps §5's reasoning true forever: a hand-written
# outbox record naming the request is an error, not a curiosity.
# Built by copying a real outbox record and rewriting one line, so the
# fixture cannot drift from the record format it is meant to be a
# well-formed example of.
GOOD="$(outbox_records | newest_of)"
FORGED_ID="$(basename "$GOOD" .md | sed 's/-result-.*/-result-fa11ed/')"
FORGED="$JOURNAL/$FORGED_ID.md"
sed -e "s|^id: .*|id: $FORGED_ID|" -e "s|^refs: .*|refs: $REQ|" "$GOOD" > "$FORGED"
if "$CASTLE" validate >"$WORKDIR/validate.txt" 2>&1; then
  fail "10: castle validate accepted an outbox record naming the request"
fi
grep -q '0042-finding-outbox' "$WORKDIR/validate.txt" \
  || fail "10: the validate failure does not cite the brief: $(cat "$WORKDIR/validate.txt")"
rm -f "$FORGED"

log "outbox.sh: all scenarios passed"
