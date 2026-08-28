#!/usr/bin/env bash
# test/agent-loop/apply.sh — an approved change is made in the
# resident's own configuration repository, and every way of getting that
# wrong is refused by name (docs/tasks/0026-apply-validate.md's
# verification plan).
#
# **Its own file rather than more scenarios in approval.sh, because it
# inverts that file's central assertion.** There, `assert_checkouts_
# untouched` is the whole point: a decision is a decision and nothing
# else. Here, exactly one checkout is supposed to move, exactly once per
# authorization — and the two claims must not share a helper name that
# means opposite things in the same suite. What does NOT invert is the
# mechanism half: `assert_mechanism_untouched` holds after every
# scenario in this file without exception, including the one that
# approves a change targeting the framework itself.
#
# Same conventions as approval.sh and config-target.sh otherwise: two
# real git checkouts under $WORKDIR, a state repository beside them
# rather than inside either, a git identity scoped to this process, the
# notify stub, plain bash and stdlib python3, no Nix, zero models, zero
# network. Every `nix` in this file is a stub that logs its own
# invocation; nothing here ever builds anything, and the scenario that
# proves nothing is even reached for is the reason the stubs exist.
#
# Nothing in here is a real path, a real complaint or a real decision:
# every string is invented or reuses a placeholder this repo already
# publishes.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CASTLE="$REPO_ROOT/agent/castle"
MODAL="$REPO_ROOT/agent/castle-modal"
WORKER="$REPO_ROOT/test/agent-loop/scripted-worker-applyable.sh"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/castle-apply.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT
# Canonicalised for `_state_layout_finding`'s sake, the same reason
# state-layout.sh gives: that rule calls os.path.realpath before it
# walks anywhere, so an uncanonicalised $WORKDIR would have this harness
# and the code under test comparing two different ancestries.
WORKDIR="$(cd "$WORKDIR" && pwd -P)"

log() { printf '>>> %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Committing needs an identity, and a developer's own git config must
# not decide whether this test passes.
export GIT_AUTHOR_NAME="castle-apply-fixture"
export GIT_AUTHOR_EMAIL="fixture@example.invalid"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

# **And a second isolation the other harnesses in this directory do not
# need.** Every git subprocess the applier runs has its whole `GIT_*`
# environment stripped — deliberately, so that what a repository *is*
# cannot be decided by whoever exported something — which means the two
# variables above do not reach it and `GIT_CONFIG_GLOBAL=/dev/null` does
# not shield it from a developer's own `~/.gitconfig`. That was harmless
# while nothing ever committed; this file commits. A developer with
# `commit.gpgsign = true` set globally would otherwise watch every
# scenario here fail for a reason that has nothing to do with the code.
# HOME is not a `GIT_*` variable, so pointing it at an empty directory
# is the isolation that survives the strip. XDG_CONFIG_HOME comes with
# it, because git reads a global config from there too.
export HOME="$WORKDIR/nobody"
export XDG_CONFIG_HOME="$WORKDIR/nobody/.config"
mkdir -p "$XDG_CONFIG_HOME"

export CASTLE_REVIEW_RESIZE_COMMAND=""

# ---------------------------------------------------------------------
log "building the two checkouts"
# ---------------------------------------------------------------------
# `git archive` rather than `cp -r`, the same choice approval.sh and
# config-target.sh make and for the same two reasons: only committed
# content, so no untracked scratch file from a developer's live worktree
# leaks into a fixture, and what the fixture holds is the real current
# module surface rather than a synthetic stand-in free to drift.
MECHANISM="$WORKDIR/mechanism"
mkdir -p "$MECHANISM"
git -C "$REPO_ROOT" archive HEAD | tar -x -C "$MECHANISM"
git -C "$MECHANISM" init -q
git -C "$MECHANISM" add -A
git -C "$MECHANISM" commit -q -m "fixture: this framework at HEAD"

# Synthetic, and every literal in it is one this repo already publishes:
# nixosConfigurations.example's "resident" admin username and its
# placeholder key string. Four files and a .gitignore, each with a job:
# `resident.nix` is what the ordinary apply cases change,
# `hosts/example/default.nix` is a DIFFERENT path so a scenario can
# dirty one without dirtying the other, `del-me.nix` exists to stop
# existing, and the .gitignore is what makes the ignored-scratch-file
# control mean something.
PRIVATE="$WORKDIR/private"
mkdir -p "$PRIVATE/hosts/example"
cat > "$PRIVATE/flake.nix" <<'EOF'
# Synthetic private flake, harness fixture only. Never evaluated by
# anything in this harness — every `nix` here is a stub.
{
  inputs.castle-turing.url = "github:Castle-Turing/castle-turing";
  outputs = { self, castle-turing, ... }: {
    nixosConfigurations.example-private = castle-turing.lib.placeholder;
  };
}
EOF
cat > "$PRIVATE/resident.nix" <<'EOF'
# Synthetic private layer, harness fixture only.
# APPLYABLE-MARKER: start
{
  castle.admin.username = "resident";
  castle.admin.sshKeys = [
    "ssh-ed25519 REPLACE-WITH-YOUR-PUBLIC-KEY this-is-a-placeholder-not-a-key"
  ];
}
EOF
cat > "$PRIVATE/hosts/example/default.nix" <<'EOF'
# Synthetic host module, harness fixture only.
# APPLYABLE-MARKER: start
{ }
EOF
cat > "$PRIVATE/del-me.nix" <<'EOF'
# Synthetic file that exists only so a change can remove it.
{ }
EOF
cat > "$PRIVATE/.gitignore" <<'EOF'
scratch-*
EOF
git -C "$PRIVATE" init -q
git -C "$PRIVATE" add -A
git -C "$PRIVATE" commit -q -m "fixture: a synthetic private layer"

# Tracked as the head each assertion measures from, and advanced by
# `assert_private_changed_exactly` itself — so "exactly one commit"
# means one commit since the LAST scenario, not since the run began.
PRIVATE_HEAD="$(git -C "$PRIVATE" rev-parse HEAD)"
MECHANISM_HEAD="$(git -C "$MECHANISM" rev-parse HEAD)"

# Beside the private checkout, never inside it (docs/tasks/0030-state-
# outside-the-flake.md). One scenario below deliberately makes this
# repository unsafe for a moment and puts it back, which is the only
# way to exercise the evaluation gate's second condition.
STATE_REPO="$WORKDIR/private-state"
mkdir -p "$STATE_REPO"
git -C "$STATE_REPO" init -q
export CASTLE_STATE_DIR="$STATE_REPO"
export XDG_RUNTIME_DIR="$WORKDIR/runtime"
mkdir -p "$XDG_RUNTIME_DIR"
JOURNAL="$CASTLE_STATE_DIR/journal"
SPOOL="$XDG_RUNTIME_DIR/castle/spool"

export CASTLE_NOTIFY_LOG="$WORKDIR/notify.log"
export CASTLE_NOTIFY_COMMAND="$REPO_ROOT/test/agent-loop/notify-stub.sh"
: > "$CASTLE_NOTIFY_LOG"

export CASTLE_WORKER_COMMAND="$WORKER"
export CASTLE_PRIVATE_ROOT="$PRIVATE"
export CASTLE_MECHANISM_ROOT="$MECHANISM"
export CASTLE_APPLYABLE_EXPECT_DIR="$WORKDIR/expected"
mkdir -p "$CASTLE_APPLYABLE_EXPECT_DIR"

# ---------------------------------------------------------------------
# Journal helpers, copied from approval.sh rather than shared: these are
# plain bash harnesses with no library between them, and the duplication
# is the price of each being readable start to finish.
# ---------------------------------------------------------------------
referencing() {
  local rtype="$1" id="$2"
  grep -l "^refs: .*$id" "$JOURNAL"/*-"$rtype"-*.md 2>/dev/null || true
}
# Newest by MTIME and not by filename — ids carry a one-second timestamp
# and a random suffix, so two records written inside the same second
# sort by chance.
newest_of() {
  xargs -r stat -c '%.Y	%n' 2>/dev/null | sort -k1,1n | tail -1 | cut -f2-
}
newest_result_for() { referencing result "$1" | newest_of; }
proposal_question_for() {
  local request_id="$1" path
  path="$(grep -l "^refs: $request_id," "$JOURNAL"/*-question-*.md 2>/dev/null \
    | xargs -r grep -l '^proposal-sha256: ' | head -1 || true)"
  [ -n "$path" ] || return 0
  basename "$path" .md
}
# An apply result names the authorization it spent FIRST and nothing
# else of the errand at all, so "which result accounts for this
# approval" is a `refs[0]` question and is asked as one.
apply_results_for() { grep -l "^refs: $1," "$JOURNAL"/*-result-*.md 2>/dev/null || true; }
newest_apply_result_for() { apply_results_for "$1" | newest_of; }
count_apply_results_for() { apply_results_for "$1" | grep -c . || true; }
journal_file_count() { find "$JOURNAL" -name '*.md' | wc -l | tr -d ' '; }
# The record states the validation command shell-quoted, on its own
# indented line, so a resident can paste it. Comparing it to an expected
# argv therefore has to go back through a shell-word splitter rather
# than through string equality — `#` in a flakeref makes `shlex.join`
# quote the whole argument, correctly, and a harness asserting on the
# quoting rather than on the arguments would break the first time either
# side got safer.
argv_matches() {
  # Usage: argv_matches <record> <expected-arg>...
  local record="$1"; shift
  local line
  line="$(grep -m1 '^    nix ' "$record" | sed 's/^    //')"
  [ -n "$line" ] || return 1
  python3 - "$line" "$@" <<'PY'
import shlex, sys
sys.exit(0 if shlex.split(sys.argv[1]) == sys.argv[2:] else 1)
PY
}
recorded_command_line() { grep -m1 '^    nix ' "$1" | sed 's/^    //'; }
sha256_of() { sha256sum "$1" | cut -d' ' -f1; }
field_of() { sed -n "s/^$2: //p" "$1"; }

# ---------------------------------------------------------------------
# The two assertions this whole file turns on.
# ---------------------------------------------------------------------

# Unchanged in force from approval.sh's half of the same claim. Nothing
# in this task may ever write the framework checkout, and this says so
# after EVERY scenario, including the one that approves a change
# targeting it.
assert_mechanism_untouched() {
  local where="$1"
  [ -z "$(git -C "$MECHANISM" status --porcelain)" ] \
    || fail "$where: the MECHANISM checkout was mutated — $(git -C "$MECHANISM" status --porcelain)"
  [ "$(git -C "$MECHANISM" rev-parse HEAD)" = "$MECHANISM_HEAD" ] \
    || fail "$where: the mechanism checkout's HEAD moved"
}

# The refusal-case companion: nothing moved, nothing is dirty, nothing
# was left behind.
assert_private_untouched() {
  local where="$1"
  [ -z "$(git -C "$PRIVATE" status --porcelain)" ] \
    || fail "$where: the private checkout was mutated — $(git -C "$PRIVATE" status --porcelain)"
  [ "$(git -C "$PRIVATE" rev-parse HEAD)" = "$PRIVATE_HEAD" ] \
    || fail "$where: the private checkout's HEAD moved"
}

# The inversion, and the assertion the whole task turns on. Given the
# answer that authorized it and the exact paths it was supposed to
# touch: HEAD advanced by exactly one commit, that commit names exactly
# those paths and no others, each path's content is byte-identical to
# what the tenant computed the patch would produce (or is gone, when the
# tenant expected it gone), the committer is the applier identity, the
# message names the authorization, and the checkout is clean afterwards
# — nothing staged, nothing dirty, no stray file.
assert_private_changed_exactly() {
  local where="$1" answer="$2"; shift 2
  local expected=("$@") head_now count named want path expect_file
  head_now="$(git -C "$PRIVATE" rev-parse HEAD)"
  [ "$head_now" != "$PRIVATE_HEAD" ] || fail "$where: the private checkout's HEAD did not move at all"
  count="$(git -C "$PRIVATE" rev-list --count "$PRIVATE_HEAD..$head_now")"
  [ "$count" = "1" ] \
    || fail "$where: the private checkout advanced by $count commits, not exactly one"
  named="$(git -C "$PRIVATE" show --name-only --format= "$head_now" | sed '/^$/d' | sort | tr '\n' ' ')"
  want="$(printf '%s\n' "${expected[@]}" | sort | tr '\n' ' ')"
  [ "$named" = "$want" ] \
    || fail "$where: the commit names [$named] but the change was supposed to touch [$want]"
  [ "$(git -C "$PRIVATE" show -s --format=%cn "$head_now")" = "Castle applier" ] \
    || fail "$where: the commit's committer is not the applier seat: $(git -C "$PRIVATE" show -s --format='%cn <%ce>' "$head_now")"
  [ "$(git -C "$PRIVATE" show -s --format=%ce "$head_now")" = "applier@castle.invalid" ] \
    || fail "$where: the commit's committer address is not the reserved one: $(git -C "$PRIVATE" show -s --format=%ce "$head_now")"
  git -C "$PRIVATE" show -s --format=%B "$head_now" | grep -qF "$answer" \
    || fail "$where: the commit message does not name the authorization it was made on"
  git -C "$PRIVATE" show -s --format=%B "$head_now" | grep -q 'Nothing was activated' \
    || fail "$where: the commit message does not say nothing was activated"
  [ -z "$(git -C "$PRIVATE" status --porcelain)" ] \
    || fail "$where: the checkout is not clean after the commit — $(git -C "$PRIVATE" status --porcelain)"
  for path in "${expected[@]}"; do
    expect_file="$CASTLE_APPLYABLE_EXPECT_DIR/${path//\//%}"
    if [ -f "$expect_file" ]; then
      cmp -s "$expect_file" "$PRIVATE/$path" \
        || fail "$where: $path is not byte-identical to what the change was supposed to produce"
    else
      [ ! -e "$PRIVATE/$path" ] \
        || fail "$where: $path was supposed to stop existing and is still there"
    fi
  done
  PRIVATE_HEAD="$head_now"
}

# One approval, from a real turn through the real worker contract.
# Echoes "<request> <result> <question> <answer>".
new_approval() {
  local marker="$1" request result question answer
  request="$("$CASTLE" ask "APPLY-FIXTURE $marker: an invented complaint whose fix is a one-line change.")"
  "$CASTLE" work "$request" >/dev/null
  result="$(basename "$(newest_result_for "$request")" .md)"
  question="$(proposal_question_for "$request")"
  [ -n "$question" ] || fail "$marker: the turn filed no change to decide"
  answer="$("$CASTLE" answer --decision approve "$question" </dev/null)"
  printf '%s %s %s %s\n' "$request" "$result" "$question" "$answer"
}

# Asserts the shape every apply result has, whatever its outcome.
assert_apply_result_shape() {
  local where="$1" record="$2" answer="$3" question="$4" request="$5"
  grep -q '^seat: applier$' "$record" \
    || fail "$where: the record was not written by the applier seat: $(field_of "$record" seat)"
  grep -q "^refs: $answer,$question\$" "$record" \
    || fail "$where: the record's refs are not <answer>,<question>: $(grep '^refs:' "$record")"
  # §F's whole argument rests on this: a result naming the request would
  # be picked up by `closing_result`'s second clause and would silently
  # close a genuinely dangling worker claim.
  grep -q "$request" "$record" \
    && fail "$where: the apply record names the errand's request, which would close a dangling worker claim"
  return 0
}

"$CASTLE" dispatch --watermark-only >/dev/null
"$CASTLE" validate >/dev/null

# ---------------------------------------------------------------------
log "automatic, end to end: an approved change lands with no command typed"
# ---------------------------------------------------------------------
REQ1="$("$CASTLE" ask "APPLY-FIXTURE APPLYABLE-MODIFY-one: an invented complaint whose fix is a one-line change.")"
"$CASTLE" dispatch >/dev/null
R1="$(basename "$(newest_result_for "$REQ1")" .md)"
grep -q '^outcome: completed$' "$JOURNAL/$R1.md" || fail "the sweep's turn did not complete"
grep -q '^target: private$' "$JOURNAL/$R1.md" || fail "the turn stamped no private target"
[ -f "$JOURNAL/$R1.patch" ] || fail "the turn kept no byte-exact copy of its diff"
Q1="$(proposal_question_for "$REQ1")"
[ -n "$Q1" ] || fail "the turn filed no change to decide"
grep -q '^authorizes-apply: true$' "$JOURNAL/$Q1.md" \
  || fail "the proposal does not say approving it authorizes an apply, so nothing could ever apply it"
A1="$("$CASTLE" answer --decision approve "$Q1" "Yes, do that." )"

: > "$CASTLE_NOTIFY_LOG"
"$CASTLE" apply --sweep >/dev/null
AP1="$(newest_apply_result_for "$A1")"
[ -n "$AP1" ] || fail "the sweep applied nothing at all"
assert_apply_result_shape "the automatic apply" "$AP1" "$A1" "$Q1" "$REQ1"
grep -q '^outcome: completed$' "$AP1" \
  || fail "the apply's own run is not recorded as completed: $(field_of "$AP1" outcome)"
# The default a resident actually gets: applying is on, evaluating is
# not, and the record says which of the two happened rather than
# claiming a check that never ran.
grep -q '^apply-outcome: applied-unvalidated$' "$AP1" \
  || fail "the apply's outcome is not applied-unvalidated: $(field_of "$AP1" apply-outcome)"
assert_private_changed_exactly "the automatic apply" "$A1" resident.nix
assert_mechanism_untouched "the automatic apply"
"$CASTLE" validate >/dev/null || fail "the journal does not validate after an apply"

log "  -- and the resident is told, in the words drafted for that one line"
grep -q 'The change you approved is now in your configuration repository. It was not checked, and nothing was activated.' \
  "$CASTLE_NOTIFY_LOG" \
  || fail "the apply's notification is not the drafted line: $(cat "$CASTLE_NOTIFY_LOG")"

log "  -- and the status surface stops saying it is waiting, and says what happened instead"
STATUS_APPLIED="$("$MODAL" --mode status --limit 40)"
printf '%s\n' "$STATUS_APPLIED" | grep -F "$REQ1" | grep -q 'applied, not checked — not activated' \
  || fail "an applied errand does not read as applied: $(printf '%s\n' "$STATUS_APPLIED" | grep -F "$REQ1")"
printf '%s\n' "$STATUS_APPLIED" | grep -F "$REQ1" | grep -q 'waiting to be applied' \
  && fail "an applied change still reads as waiting to be applied"

# ---------------------------------------------------------------------
log "exactly once: a second sweep spends nothing, and the hand path is the retry"
# ---------------------------------------------------------------------
FILES_BEFORE="$(journal_file_count)"
"$CASTLE" apply --sweep > "$WORKDIR/second-sweep.txt"
grep -q 'nothing eligible' "$WORKDIR/second-sweep.txt" \
  || fail "a second sweep found something to spend: $(cat "$WORKDIR/second-sweep.txt")"
[ "$(journal_file_count)" = "$FILES_BEFORE" ] || fail "the second sweep wrote a record anyway"
assert_private_untouched "after a second sweep"

log "  -- but castle apply <answer-id> runs again by hand, and is refused because the change is already there"
if "$CASTLE" apply "$A1" >"$WORKDIR/hand-retry.txt" 2>&1; then
  fail "re-applying an already-applied change reported success: $(cat "$WORKDIR/hand-retry.txt")"
fi
RETRY="$(newest_apply_result_for "$A1")"
grep -q '^apply-outcome: refused-patch-stale$' "$RETRY" \
  || fail "the hand retry was not refused as stale: $(field_of "$RETRY" apply-outcome)"
[ "$(count_apply_results_for "$A1")" = "2" ] \
  || fail "the hand retry did not write its own record: $(count_apply_results_for "$A1") records name $A1"
assert_private_untouched "after the hand retry"
assert_mechanism_untouched "after the hand retry"

# ---------------------------------------------------------------------
log "hand-run: the same shape, driven by castle apply <answer-id>"
# ---------------------------------------------------------------------
read -r REQ2 R2 Q2 A2 <<<"$(new_approval APPLYABLE-MODIFY-two)"
"$CASTLE" apply "$A2" >/dev/null || fail "a hand-run apply of a fresh approval failed"
AP2="$(newest_apply_result_for "$A2")"
grep -q '^apply-outcome: applied-unvalidated$' "$AP2" \
  || fail "the hand-run apply's outcome is wrong: $(field_of "$AP2" apply-outcome)"
assert_apply_result_shape "the hand-run apply" "$AP2" "$A2" "$Q2" "$REQ2"
assert_private_changed_exactly "the hand-run apply" "$A2" resident.nix
assert_mechanism_untouched "the hand-run apply"

# ---------------------------------------------------------------------
log "a created file, a deleted file, and a change spanning two files"
# ---------------------------------------------------------------------
# The three shapes the `git add -N` plus pathspec-commit sequence has to
# handle, verified against this fixture rather than against a manual
# page: a path that does not exist yet cannot be named by a pathspec
# commit without an intent-to-add, and a path that stops existing has to
# be committed as a removal rather than as an empty file.
read -r REQ_C R_C Q_C A_C <<<"$(new_approval APPLYABLE-CREATE)"
"$CASTLE" apply "$A_C" >/dev/null || fail "applying a file creation failed"
assert_private_changed_exactly "creating a file" "$A_C" hosts/example/created.nix
grep -q '^apply-outcome: applied-unvalidated$' "$(newest_apply_result_for "$A_C")" \
  || fail "the creation's outcome is wrong"

read -r REQ_D R_D Q_D A_D <<<"$(new_approval APPLYABLE-DELETE)"
"$CASTLE" apply "$A_D" >/dev/null || fail "applying a file deletion failed"
assert_private_changed_exactly "deleting a file" "$A_D" del-me.nix
[ ! -e "$PRIVATE/del-me.nix" ] || fail "the deleted file is still on disk"

read -r REQ_T R_T Q_T A_T <<<"$(new_approval APPLYABLE-TWOFILE)"
"$CASTLE" apply "$A_T" >/dev/null || fail "applying a two-file change failed"
assert_private_changed_exactly "a change spanning two files" "$A_T" \
  resident.nix hosts/example/default.nix
assert_mechanism_untouched "after the three patch shapes"
"$CASTLE" validate >/dev/null || fail "the journal does not validate after the three patch shapes"

# ---------------------------------------------------------------------
log "old approvals are inert: no authorizes-apply, no apply, ever"
# ---------------------------------------------------------------------
# D2's whole mechanism, proved rather than asserted. Every proposal
# filed before docs/tasks/0026 was decided under a screen saying in
# capitals that approving edits nothing, so approving one authorized a
# record and nothing more. Planted by hand precisely because no
# supported writer can produce one any more.
REQ_OLD="$("$CASTLE" ask "APPLY-FIXTURE APPLYABLE-OTHER: an invented complaint decided under the older statement.")"
"$CASTLE" work "$REQ_OLD" >/dev/null
R_OLD="$(basename "$(newest_result_for "$REQ_OLD")" .md)"
# The turn files its own, applyable proposal too; set that one aside so
# only the planted one is left to decide.
"$CASTLE" answer --decision defer "$(proposal_question_for "$REQ_OLD")" </dev/null >/dev/null
Q_OLD="20260201T000100Z-question-preapply"
{
  echo "---"
  echo "id: $Q_OLD"
  echo "type: question"
  echo "provenance: requested"
  echo "refs: $REQ_OLD,$R_OLD"
  echo "seat: worker"
  echo "created: 2026-02-01T00:01:00Z"
  echo "proposal-sha256: $(sha256_of "$JOURNAL/$R_OLD.md")"
  echo "---"
  echo
  echo "A change offered before an applier existed, harness fixture only."
} > "$JOURNAL/$Q_OLD.md"
"$CASTLE" validate >/dev/null || fail "the pre-apply proposal fixture does not validate"
A_OLD="$("$CASTLE" answer --decision approve "$Q_OLD" </dev/null)"

FILES_BEFORE="$(journal_file_count)"
"$CASTLE" apply --sweep > "$WORKDIR/old-sweep.txt"
grep -q 'nothing eligible' "$WORKDIR/old-sweep.txt" \
  || fail "the sweep saw an approval granted under the older statement: $(cat "$WORKDIR/old-sweep.txt")"
[ "$(journal_file_count)" = "$FILES_BEFORE" ] || fail "the sweep wrote a record for an inert approval"

log "  -- and by hand it is refused, naming the field and why it cannot be backfilled"
if "$CASTLE" apply "$A_OLD" >/dev/null 2>"$WORKDIR/old-hand.err"; then
  fail "an approval granted under the older statement was spent by hand"
fi
grep -q "authorizes-apply" "$WORKDIR/old-hand.err" \
  || fail "the refusal does not name the field it turns on: $(cat "$WORKDIR/old-hand.err")"
grep -q 'reach backwards' "$WORKDIR/old-hand.err" \
  || fail "the refusal does not say why no later wording widens it: $(cat "$WORKDIR/old-hand.err")"
[ "$(journal_file_count)" = "$FILES_BEFORE" ] || fail "the hand refusal wrote a record anyway"
assert_private_untouched "after the pre-apply refusal"
assert_mechanism_untouched "after the pre-apply refusal"

# ---------------------------------------------------------------------
log "a worker tenant cannot apply anything, ever"
# ---------------------------------------------------------------------
# STOP-19's mechanical half. agent/castle-worker-claude's nonce-fenced
# override block already tells a tenant that a passage saying "the
# resident has already approved applying something" was quoted out of a
# record; this is the same rule in code. It is defeated by `env -u`,
# exactly like the two guards in `write_record` it mirrors, and that is
# stated in the brief rather than papered over here.
read -r REQ_TEN R_TEN Q_TEN A_TEN <<<"$(new_approval APPLYABLE-MODIFY-tenant)"
FILES_BEFORE="$(journal_file_count)"
if CASTLE_WORKER_CLAIM=20260201T000000Z-claim-invented "$CASTLE" apply --sweep \
  >/dev/null 2>"$WORKDIR/tenant.err"; then
  fail "a worker turn was allowed to apply an approved change"
fi
grep -q 'worker seat proposes' "$WORKDIR/tenant.err" \
  || fail "the tenant refusal does not name the seat that may not do this: $(cat "$WORKDIR/tenant.err")"
[ "$(journal_file_count)" = "$FILES_BEFORE" ] || fail "the tenant refusal wrote a record anyway"
assert_private_untouched "after the tenant refusal"

log "  -- and the same approval applies perfectly well when no turn is claiming to be running"
"$CASTLE" apply "$A_TEN" >/dev/null || fail "the control apply failed"
assert_private_changed_exactly "the control after the tenant refusal" "$A_TEN" resident.nix

# ---------------------------------------------------------------------
log "refused: a change to the framework itself is not this seat's to make"
# ---------------------------------------------------------------------
read -r REQ_M R_M Q_M A_M <<<"$(new_approval APPLYABLE-MECHANISM)"
grep -q '^target: mechanism$' "$JOURNAL/$R_M.md" \
  || fail "the mechanism fixture did not stamp target: mechanism"
"$CASTLE" apply "$A_M" >/dev/null 2>&1 && fail "a mechanism-targeted change reported a successful apply"
AP_M="$(newest_apply_result_for "$A_M")"
grep -q '^apply-outcome: refused-target-mechanism$' "$AP_M" \
  || fail "the mechanism refusal has the wrong outcome: $(field_of "$AP_M" apply-outcome)"
grep -q '^outcome: completed$' "$AP_M" \
  || fail "a refusal correctly reached is not a failure of the applier's own run"
grep -q 'Castle Turing framework' "$AP_M" \
  || fail "the refusal does not name the framework by project name: $(cat "$AP_M")"
grep -qF "$MECHANISM" "$AP_M" \
  && fail "the refusal names the mechanism checkout's path, which is not the resident's business"
# The wording must not decide where host modules live
# (docs/backlog/where-do-host-modules-live.md is open, and §G says why).
grep -qi 'wrong layer\|mistake\|should have' "$AP_M" \
  && fail "the refusal implies the change was proposed against the wrong layer"
assert_private_untouched "after the mechanism refusal"
assert_mechanism_untouched "after the mechanism refusal"

# ---------------------------------------------------------------------
log "refused: the proposal on disk is no longer the one that was approved"
# ---------------------------------------------------------------------
read -r REQ_AC R_AC Q_AC A_AC <<<"$(new_approval APPLYABLE-MODIFY-changed)"
# One byte, appended, over a copy kept so the exact original can come
# back — the same shape approval.sh's stale case uses. Restored at the
# end of this section rather than left, so the scenarios after it start
# from a journal nothing has tampered with.
cp "$JOURNAL/$R_AC.md" "$WORKDIR/changed-original"
printf ' ' >> "$JOURNAL/$R_AC.md"
"$CASTLE" apply "$A_AC" >/dev/null 2>&1 && fail "a proposal altered since approval was applied anyway"
AP_AC="$(newest_apply_result_for "$A_AC")"
grep -q '^apply-outcome: refused-artifact-changed$' "$AP_AC" \
  || fail "an altered proposal was refused for the wrong reason: $(field_of "$AP_AC" apply-outcome)"
assert_private_untouched "after the altered-proposal refusal"
assert_mechanism_untouched "after the altered-proposal refusal"
cp "$WORKDIR/changed-original" "$JOURNAL/$R_AC.md"
"$CASTLE" validate >/dev/null || fail "the journal does not validate once the tampered bytes are restored"

log "  -- and the same refusal when it is the KEPT COPY that moved, not the record"
# The second digest, checked independently of the first. The record can
# be word for word what was approved while the bytes that would actually
# be written to the resident's files are not, which is precisely why
# there are two digests and not one.
read -r REQ_SC R_SC Q_SC A_SC <<<"$(new_approval APPLYABLE-MODIFY-sidecar)"
cp "$JOURNAL/$R_SC.patch" "$WORKDIR/sidecar-original"
printf '\n' >> "$JOURNAL/$R_SC.patch"
"$CASTLE" apply "$A_SC" >/dev/null 2>&1 \
  && fail "a change whose kept copy moved since approval was applied anyway"
AP_SC="$(newest_apply_result_for "$A_SC")"
grep -q '^apply-outcome: refused-artifact-changed$' "$AP_SC" \
  || fail "a tampered kept copy was refused for the wrong reason: $(field_of "$AP_SC" apply-outcome)"
assert_private_untouched "after the tampered-copy refusal"
assert_mechanism_untouched "after the tampered-copy refusal"
cp "$WORKDIR/sidecar-original" "$JOURNAL/$R_SC.patch"
"$CASTLE" validate >/dev/null || fail "the journal does not validate once the kept copy is restored"

log "  -- and the control: restoring the exact bytes makes it applyable again"
# Without this, the two refusals above are satisfied by a check that
# simply never lets anything through once it has been near a file.
"$CASTLE" apply "$A_SC" >/dev/null || fail "a change whose bytes are exactly what was approved is still refused"
assert_private_changed_exactly "the restored-bytes control" "$A_SC" resident.nix

# ---------------------------------------------------------------------
log "refused: no exact copy of the change was kept"
# ---------------------------------------------------------------------
read -r REQ_NP R_NP Q_NP A_NP <<<"$(new_approval APPLYABLE-MODIFY-nopatch)"
# `castle validate` would flag a `patch-sha256` naming a sidecar that is
# not there, correctly — so the sidecar is moved aside and put back,
# rather than deleted.
mv "$JOURNAL/$R_NP.patch" "$WORKDIR/kept.patch"
"$CASTLE" apply "$A_NP" >/dev/null 2>&1 && fail "a change with no kept copy was applied anyway"
AP_NP="$(newest_apply_result_for "$A_NP")"
grep -q '^apply-outcome: refused-no-patch$' "$AP_NP" \
  || fail "a missing sidecar was refused for the wrong reason: $(field_of "$AP_NP" apply-outcome)"
grep -q 'for reading, not for applying' "$AP_NP" \
  || fail "the refusal does not say why the rendered copy is not usable: $(cat "$AP_NP")"
assert_private_untouched "after the missing-copy refusal"
mv "$WORKDIR/kept.patch" "$JOURNAL/$R_NP.patch"

log "  -- and the pre-0033 shape: a proposal that never kept one at all"
# The case that needs a name rather than an exception. A result carrying
# no diff boundary and no sidecar is approvable today — the review
# surface renders such a body whole, deliberately — so an authorization
# can legitimately resolve to no bytes.
R_BARE="20260201T000200Z-result-nosidecar"
Q_BARE="20260201T000201Z-question-nosidecar"
{
  echo "---"
  echo "id: $R_BARE"
  echo "type: result"
  echo "provenance: requested"
  echo "refs: $REQ_NP"
  echo "seat: worker"
  echo "created: 2026-02-01T00:02:00Z"
  echo "outcome: completed"
  echo "target: private"
  echo "---"
  echo
  echo "A result from before an exact copy was kept, harness fixture only."
} > "$JOURNAL/$R_BARE.md"
{
  echo "---"
  echo "id: $Q_BARE"
  echo "type: question"
  echo "provenance: requested"
  echo "refs: $REQ_NP,$R_BARE"
  echo "seat: worker"
  echo "created: 2026-02-01T00:02:01Z"
  echo "proposal-sha256: $(sha256_of "$JOURNAL/$R_BARE.md")"
  echo "authorizes-apply: true"
  echo "---"
  echo
  echo "A change with nothing kept to apply, harness fixture only."
} > "$JOURNAL/$Q_BARE.md"
"$CASTLE" validate >/dev/null || fail "the no-sidecar fixture does not validate"
A_BARE="$("$CASTLE" answer --decision approve "$Q_BARE" </dev/null)"
"$CASTLE" apply "$A_BARE" >/dev/null 2>&1 && fail "a change with nothing kept was applied anyway"
grep -q '^apply-outcome: refused-no-patch$' "$(newest_apply_result_for "$A_BARE")" \
  || fail "a proposal that kept nothing was refused for the wrong reason"
assert_private_untouched "after the never-kept-a-copy refusal"

# ---------------------------------------------------------------------
log "refused: the change no longer fits the repository"
# ---------------------------------------------------------------------
read -r REQ_ST R_ST Q_ST A_ST <<<"$(new_approval APPLYABLE-MODIFY-stale)"
# An edit the resident made themselves and committed, to the same lines
# — after the approval. Nothing here fuzzes, merges or recounts, so the
# change stops fitting and is refused rather than guessed at. It has to
# land on the patch's own lines rather than merely in the same file:
# `git apply` is perfectly happy to apply a hunk to a file that grew a
# line somewhere else, and a scenario that only appended one would prove
# nothing.
sed -i 's/^# APPLYABLE-MARKER: .*/# APPLYABLE-MARKER: the-resident-changed-this-themselves/' \
  "$PRIVATE/resident.nix"
git -C "$PRIVATE" commit -q -am "the resident edits their own configuration"
PRIVATE_HEAD="$(git -C "$PRIVATE" rev-parse HEAD)"
"$CASTLE" apply "$A_ST" >/dev/null 2>&1 && fail "a change that no longer fits was applied anyway"
AP_ST="$(newest_apply_result_for "$A_ST")"
grep -q '^apply-outcome: refused-patch-stale$' "$AP_ST" \
  || fail "a stale change was refused for the wrong reason: $(field_of "$AP_ST" apply-outcome)"
grep -q 'error:' "$AP_ST" \
  || fail "the refusal does not carry git's own account: $(cat "$AP_ST")"
assert_private_untouched "after the stale refusal"
assert_mechanism_untouched "after the stale refusal"

# ---------------------------------------------------------------------
log "refused: the resident has uncommitted work under the same files"
# ---------------------------------------------------------------------
read -r REQ_TD R_TD Q_TD A_TD <<<"$(new_approval APPLYABLE-MODIFY-dirty)"
RESIDENT_EDIT="$(cat "$PRIVATE/resident.nix")
# Work in progress the resident has not committed."
printf '%s\n' "$RESIDENT_EDIT" > "$PRIVATE/resident.nix"
cp "$PRIVATE/resident.nix" "$WORKDIR/resident-work-in-progress"
"$CASTLE" apply "$A_TD" >/dev/null 2>&1 && fail "an apply wrote over the resident's uncommitted work"
AP_TD="$(newest_apply_result_for "$A_TD")"
grep -q '^apply-outcome: refused-tree-dirty$' "$AP_TD" \
  || fail "a dirty tree was refused for the wrong reason: $(field_of "$AP_TD" apply-outcome)"
# Status letters and a count, never the resident's file names: this
# record is durable and leaves the machine more easily than a journal.
grep -q 'status M' "$AP_TD" \
  || fail "the refusal does not say what kind of work is in the way: $(cat "$AP_TD")"
grep -q 'resident.nix' "$AP_TD" \
  && fail "the refusal names the resident's own file, which is resident data in a durable record"
log "  -- and their work is still there, byte for byte"
cmp -s "$WORKDIR/resident-work-in-progress" "$PRIVATE/resident.nix" \
  || fail "the refusal destroyed the resident's uncommitted work"
[ "$(git -C "$PRIVATE" rev-parse HEAD)" = "$PRIVATE_HEAD" ] || fail "the dirty refusal moved HEAD"

log "  -- the negative control: uncommitted work under a DIFFERENT file does not stop it"
# Without this, the check above is satisfied by a refusal that fires on
# any dirt anywhere — which is exactly the repo-wide check this design
# rejected, because three documented layouts leave a healthy config repo
# dirty forever.
git -C "$PRIVATE" checkout -q -- resident.nix
printf '# Work in progress somewhere else entirely.\n' >> "$PRIVATE/hosts/example/default.nix"
cp "$PRIVATE/hosts/example/default.nix" "$WORKDIR/elsewhere-work-in-progress"
printf 'a scratch file the resident ignores\n' > "$PRIVATE/scratch-notes"
"$CASTLE" apply "$A_TD" >/dev/null || fail "an unrelated dirty file stopped an apply that touches neither"
AP_TD2="$(newest_apply_result_for "$A_TD")"
grep -q '^apply-outcome: applied-unvalidated$' "$AP_TD2" \
  || fail "the apply was refused despite the dirt being elsewhere: $(field_of "$AP_TD2" apply-outcome)"
NEW_HEAD="$(git -C "$PRIVATE" rev-parse HEAD)"
[ "$(git -C "$PRIVATE" rev-list --count "$PRIVATE_HEAD..$NEW_HEAD")" = "1" ] \
  || fail "the apply past unrelated dirt did not make exactly one commit"
[ "$(git -C "$PRIVATE" show --name-only --format= "$NEW_HEAD" | sed '/^$/d')" = "resident.nix" ] \
  || fail "the commit swept in the resident's unrelated work: $(git -C "$PRIVATE" show --name-only --format= "$NEW_HEAD")"
cmp -s "$WORKDIR/elsewhere-work-in-progress" "$PRIVATE/hosts/example/default.nix" \
  || fail "the apply disturbed the resident's work on another file"
[ -f "$PRIVATE/scratch-notes" ] || fail "the apply removed the resident's ignored scratch file"
PRIVATE_HEAD="$NEW_HEAD"
git -C "$PRIVATE" checkout -q -- hosts/example/default.nix
rm -f "$PRIVATE/scratch-notes"
assert_private_untouched "after the dirty-tree controls"
assert_mechanism_untouched "after the dirty-tree controls"

# ---------------------------------------------------------------------
log "the partial state that gets a name: applied, and not committed"
# ---------------------------------------------------------------------
# Made to fail deterministically rather than by luck: a repository-local
# `commit.gpgsign` pointed at a signing program that always refuses.
# Nothing about a resident's own config is assumed, and nothing on the
# runner has to have gpg at all.
FAILING_SIGNER="$WORKDIR/failing-signer.sh"
cat > "$FAILING_SIGNER" <<'SIGNER'
#!/usr/bin/env bash
printf 'invented signing failure, harness fixture only\n' >&2
exit 1
SIGNER
chmod +x "$FAILING_SIGNER"
signing_fails() { git -C "$PRIVATE" config commit.gpgsign true; git -C "$PRIVATE" config gpg.program "$FAILING_SIGNER"; }
signing_works() { git -C "$PRIVATE" config --unset commit.gpgsign; git -C "$PRIVATE" config --unset gpg.program; }

# The recovery block out of the record, EXECUTED rather than grepped for.
# A command that reads plausibly and does nothing — or, worse, destroys
# the thing it claims to restore — is exactly what this scenario missed
# until the review ran it: `git checkout -- .` truncated a created file
# to empty, left it on disk, and left a deletion staged in the index for
# the resident's next commit to pick up.
run_recorded_recovery() {
  local record="$1" script="$WORKDIR/recovery.sh"
  awk '/^Or to drop it/ { grab = 1; next }
       grab && /^    / { sub(/^    /, ""); print; next }
       grab && NF { exit }' "$record" > "$script"
  [ -s "$script" ] || fail "the record printed no recovery command at all: $(cat "$record")"
  grep -qx 'cd <your configuration repository>' "$script" \
    || fail "the recovery block does not begin by naming the repository: $(cat "$script")"
  # The one placeholder a resident substitutes by hand; everything after
  # it must work verbatim.
  sed -i "1s|^cd <your configuration repository>$|cd '$PRIVATE'|" "$script"
  bash -e "$script" >"$WORKDIR/recovery.out" 2>&1 \
    || fail "the recorded recovery command failed: $(cat "$script")
$(cat "$WORKDIR/recovery.out")"
}

log "  -- a MODIFIED path: the change is in the tree, HEAD has not moved, and the recovery works"
read -r REQ_UC R_UC Q_UC A_UC <<<"$(new_approval APPLYABLE-MODIFY-uncommitted)"
INDEX_BEFORE="$(git -C "$PRIVATE" ls-files -s | sha256sum)"
signing_fails
"$CASTLE" apply "$A_UC" >/dev/null 2>&1 && fail "an apply whose commit failed reported success"
signing_works
AP_UC="$(newest_apply_result_for "$A_UC")"
grep -q '^apply-outcome: applied-uncommitted$' "$AP_UC" \
  || fail "a commit that failed after the patch applied has the wrong outcome: $(field_of "$AP_UC" apply-outcome)"
grep -q '^outcome: failed$' "$AP_UC" \
  || fail "an apply that did not reach a conclusion is not recorded as failed: $(field_of "$AP_UC" outcome)"
grep -q '^    git commit$' "$AP_UC" \
  || fail "the record does not name the way to keep the change: $(cat "$AP_UC")"
# Never `.`: a recovery reaching past the paths this applier touched
# would destroy the resident's other uncommitted work.
grep -qE '^    git (checkout|reset).* \.$' "$AP_UC" \
  && fail "the recovery command is repo-wide rather than scoped to the change's own paths: $(cat "$AP_UC")"
[ "$(git -C "$PRIVATE" rev-parse HEAD)" = "$PRIVATE_HEAD" ] \
  || fail "the failed commit moved HEAD anyway"
[ -n "$(git -C "$PRIVATE" status --porcelain -- resident.nix)" ] \
  || fail "the change is not in the working tree, so 'applied-uncommitted' is not what happened"
run_recorded_recovery "$AP_UC"
assert_private_untouched "after running the recorded recovery for a modified path"
[ "$(git -C "$PRIVATE" ls-files -s | sha256sum)" = "$INDEX_BEFORE" ] \
  || fail "the recorded recovery left the index changed"

log "  -- a CREATED path: the recovery that would silently destroy it instead removes it"
# The shape the generic advice got wrong. `git add -N` put an
# intent-to-add entry in the index, so `git checkout --` on this path
# restores it from an EMPTY blob: exit 0, success reported, file still
# present, contents gone.
read -r REQ_UC2 R_UC2 Q_UC2 A_UC2 <<<"$(new_approval APPLYABLE-NEWFILE-uncommitted)"
NEW_PATH="hosts/example/new-uncommitted.nix"
INDEX_BEFORE="$(git -C "$PRIVATE" ls-files -s | sha256sum)"
signing_fails
"$CASTLE" apply "$A_UC2" >/dev/null 2>&1 && fail "an apply whose commit failed reported success"
signing_works
AP_UC2="$(newest_apply_result_for "$A_UC2")"
grep -q '^apply-outcome: applied-uncommitted$' "$AP_UC2" \
  || fail "the created-path uncommitted case has the wrong outcome: $(field_of "$AP_UC2" apply-outcome)"
[ -s "$PRIVATE/$NEW_PATH" ] \
  || fail "the created file is not in the working tree, so this proves nothing"
grep -qF "$NEW_PATH" "$AP_UC2" \
  || fail "the recovery does not name the path it created: $(cat "$AP_UC2")"
run_recorded_recovery "$AP_UC2"
[ ! -e "$PRIVATE/$NEW_PATH" ] \
  || fail "the recorded recovery left the created file behind (contents: $(od -c "$PRIVATE/$NEW_PATH" | head -2))"
assert_private_untouched "after running the recorded recovery for a created path"
[ "$(git -C "$PRIVATE" ls-files -s | sha256sum)" = "$INDEX_BEFORE" ] \
  || fail "the recorded recovery left the index changed for a created path"
assert_mechanism_untouched "after the uncommitted apply"

# ---------------------------------------------------------------------
log "an environment fault is about the environment, not about the change"
# ---------------------------------------------------------------------
# `_checkout_fault`'s toplevel-mismatch case, the one its own docstring
# says nothing downstream could detect: a root that is a SUBDIRECTORY of
# a checkout, whose diffs carry paths relative to a root the applier
# will not be using. This is that downstream step.
read -r REQ_EF R_EF Q_EF A_EF <<<"$(new_approval APPLYABLE-MODIFY-envfault)"
if CASTLE_PRIVATE_ROOT="$PRIVATE/hosts" "$CASTLE" apply "$A_EF" \
  >/dev/null 2>"$WORKDIR/envfault.err"; then
  fail "an apply against a subdirectory of a checkout reported success"
fi
AP_EF="$(newest_apply_result_for "$A_EF")"
grep -q '^outcome: failed$' "$AP_EF" \
  || fail "an environment fault is not recorded as a failed run: $(field_of "$AP_EF" outcome)"
grep -q '^apply-outcome:' "$AP_EF" \
  && fail "an environment fault claimed something about the change: $(field_of "$AP_EF" apply-outcome)"
grep -q 'castle.agent.repo.private' "$AP_EF" \
  || fail "the environment fault does not name the option that fixes it: $(cat "$AP_EF")"
assert_private_untouched "after the environment fault"
assert_mechanism_untouched "after the environment fault"
"$CASTLE" validate >/dev/null || fail "the journal does not validate after the refusal scenarios"

# ---------------------------------------------------------------------
log "the evaluation gate, off: nothing is even reached for"
# ---------------------------------------------------------------------
# Behavioural rather than a grep over the source: a grep cannot tell a
# command named in a comment explaining why it is never run from one
# that is actually run, and agent/castle is full of the former. `git` is
# deliberately NOT stubbed — this task needs it — and every tool that
# could activate anything is.
GUARD_BIN="$WORKDIR/guard-bin"
GUARD_LOG="$WORKDIR/guard.log"
mkdir -p "$GUARD_BIN"
: > "$GUARD_LOG"
for tool in nix nixos-rebuild switch-to-configuration systemctl sudo; do
  cat > "$GUARD_BIN/$tool" <<GUARD
#!/usr/bin/env bash
printf '%s %s\n' "$tool" "\$*" >> "$GUARD_LOG"
exit 0
GUARD
  chmod +x "$GUARD_BIN/$tool"
done
read -r REQ_G1 R_G1 Q_G1 A_G1 <<<"$(new_approval APPLYABLE-MODIFY-gateoff)"
PATH="$GUARD_BIN:$PATH" "$CASTLE" apply "$A_G1" >/dev/null \
  || fail "an apply with the evaluation gate off failed"
[ ! -s "$GUARD_LOG" ] \
  || fail "applying a change ran something that could evaluate or activate one: $(cat "$GUARD_LOG")"
AP_G1="$(newest_apply_result_for "$A_G1")"
grep -q '^apply-outcome: applied-unvalidated$' "$AP_G1" \
  || fail "the gate-off apply has the wrong outcome: $(field_of "$AP_G1" apply-outcome)"
grep -q 'evaluateFlake' "$AP_G1" \
  || fail "the record does not name the option that would turn the check on: $(cat "$AP_G1")"
assert_private_changed_exactly "the gate-off apply" "$A_G1" resident.nix

log "  -- and the record still states the exact command that would have run"
# The dry-run seam: it makes the argv assertable with no new environment
# variable and no injection point that could drift from what production
# does, and it gives the resident the one command they can paste.
HOSTNAME_NOW="$(cat /proc/sys/kernel/hostname)"
argv_matches "$AP_G1" nix build --no-link --no-write-lock-file --no-update-lock-file \
  "$PRIVATE#nixosConfigurations.$HOSTNAME_NOW.config.system.build.toplevel" \
  || fail "the record's command line is not the exact argv: $(recorded_command_line "$AP_G1")"
grep -q 'fact about the machine this applier ran on' "$AP_G1" \
  || fail "the record does not say the hostname is a fact about the machine, not about the change"

# ---------------------------------------------------------------------
log "the evaluation gate, on but the journal would be published: refuses to evaluate"
# ---------------------------------------------------------------------
# The state directory made unsafe for exactly one apply, and put back
# afterwards: a flake.nix committed at the state repository's own root
# is enough for `_state_layout_finding`'s two stages — an ancestor that
# is both a git repository and a flake, with real content tracked under
# the state directory.
cat > "$STATE_REPO/flake.nix" <<'EOF'
# Synthetic flake, harness fixture only. Never evaluated by this test.
{ outputs = { self }: { placeholder = "fixture"; }; }
EOF
git -C "$STATE_REPO" add flake.nix
git -C "$STATE_REPO" commit -q -m "fixture: make this state directory unsafe for one scenario"
read -r REQ_G2 R_G2 Q_G2 A_G2 <<<"$(new_approval APPLYABLE-MODIFY-unsafelayout)"
: > "$GUARD_LOG"
PATH="$GUARD_BIN:$PATH" CASTLE_APPLY_EVALUATE_FLAKE=true "$CASTLE" apply "$A_G2" >/dev/null \
  || fail "an apply refusing to evaluate an unsafe layout failed outright"
[ ! -s "$GUARD_LOG" ] \
  || fail "the applier evaluated a flake that would publish the journal: $(cat "$GUARD_LOG")"
AP_G2="$(newest_apply_result_for "$A_G2")"
grep -q '^apply-outcome: applied-unvalidated$' "$AP_G2" \
  || fail "refusing to evaluate is not applied-unvalidated: $(field_of "$AP_G2" apply-outcome)"
grep -q 'readable by every account and every process' "$AP_G2" \
  || fail "the record does not quote the layout finding verbatim: $(cat "$AP_G2")"
grep -qF "$STATE_REPO" "$AP_G2" \
  || fail "the record does not say which directory is the problem: $(cat "$AP_G2")"
grep -q 'docs/private-layer.md' "$AP_G2" \
  || fail "the record does not name the document with the remedy: $(cat "$AP_G2")"
assert_private_changed_exactly "the unsafe-layout apply" "$A_G2" resident.nix
git -C "$STATE_REPO" rm -q --cached flake.nix
rm -f "$STATE_REPO/flake.nix"
git -C "$STATE_REPO" commit -q -m "fixture: put the state directory back"

# ---------------------------------------------------------------------
log "the evaluation gate, on and safe: the check runs, and the record is what ran"
# ---------------------------------------------------------------------
NIX_BIN="$WORKDIR/nix-bin"
NIX_LOG="$WORKDIR/nix.log"
NIX_ARGV="$WORKDIR/nix.argv"
mkdir -p "$NIX_BIN"
make_nix_stub() {
  # Usage: make_nix_stub <body>; the stub records that it was invoked,
  # writes its own argv one argument per line — so the comparison below
  # is about arguments and not about anybody's quoting — and then does
  # whatever the body says.
  cat > "$NIX_BIN/nix" <<STUB
#!/usr/bin/env bash
printf 'invoked\n' >> "$NIX_LOG"
printf '%s\n' "\$@" > "$NIX_ARGV"
$1
STUB
  chmod +x "$NIX_BIN/nix"
}

: > "$NIX_LOG"
make_nix_stub 'exit 0'
read -r REQ_V1 R_V1 Q_V1 A_V1 <<<"$(new_approval APPLYABLE-MODIFY-validates)"
PATH="$NIX_BIN:$PATH" CASTLE_APPLY_EVALUATE_FLAKE=true "$CASTLE" apply "$A_V1" >/dev/null \
  || fail "an apply whose check succeeded exited nonzero"
[ "$(grep -c . "$NIX_LOG")" = "1" ] \
  || fail "the check was invoked $(grep -c . "$NIX_LOG") times, not exactly once"
AP_V1="$(newest_apply_result_for "$A_V1")"
grep -q '^apply-outcome: applied-validated$' "$AP_V1" \
  || fail "a successful check is not applied-validated: $(field_of "$AP_V1" apply-outcome)"
log "  -- and what the record says ran is argument-for-argument what ran"
mapfile -t RAN_ARGS < "$NIX_ARGV"
argv_matches "$AP_V1" nix "${RAN_ARGS[@]}" \
  || fail "the record's command line is not what the check was actually invoked with: record says [$(recorded_command_line "$AP_V1")], ran [nix ${RAN_ARGS[*]}]"
assert_private_changed_exactly "the validated apply" "$A_V1" resident.nix
assert_mechanism_untouched "the validated apply"

log "  -- a check that fails: the change stays, the record says the check failed, the log is bounded"
: > "$NIX_LOG"
make_nix_stub 'for i in $(seq 1 200); do printf "invented build log line %s\n" "$i"; done; exit 1'
read -r REQ_V2 R_V2 Q_V2 A_V2 <<<"$(new_approval APPLYABLE-MODIFY-buildfails)"
if PATH="$NIX_BIN:$PATH" CASTLE_APPLY_EVALUATE_FLAKE=true "$CASTLE" apply "$A_V2" >/dev/null 2>&1; then
  fail "an apply whose check failed exited 0"
fi
AP_V2="$(newest_apply_result_for "$A_V2")"
grep -q '^apply-outcome: validation-failed$' "$AP_V2" \
  || fail "a failed check is not validation-failed: $(field_of "$AP_V2" apply-outcome)"
# The applier's own run reached a recorded conclusion, so `outcome` says
# `completed`: the two fields are about different things, which is the
# whole reason the second one exists.
grep -q '^outcome: completed$' "$AP_V2" \
  || fail "a failed check was recorded as a failure of the applier's own run: $(field_of "$AP_V2" outcome)"
grep -q 'invented build log line 200' "$AP_V2" \
  || fail "the record does not carry the end of the failing output"
grep -q 'invented build log line 161' "$AP_V2" \
  || fail "the record does not carry the whole last 40 lines"
grep -q 'invented build log line 160' "$AP_V2" \
  && fail "the record carries more than the last 40 lines of output"
grep -q 'invented build log line 1$' "$AP_V2" \
  && fail "the record carries the START of the output instead of the end"
SPOOL_LOG="$SPOOL/apply-$A_V2.log"
[ -f "$SPOOL_LOG" ] || fail "the full output was not spooled at all"
[ "$(grep -c 'invented build log line' "$SPOOL_LOG")" = "200" ] \
  || fail "the spool does not hold the whole output: $(grep -c . "$SPOOL_LOG") lines"
grep -qF "$SPOOL_LOG" "$AP_V2" || fail "the record does not name where the full output is"
# The change is still there: nothing is rolled back, and the record says
# so rather than acting again unbidden.
assert_private_changed_exactly "the failed-check apply" "$A_V2" resident.nix
grep -q 'no automatic repair' "$AP_V2" \
  || fail "the record does not say a failed check is not repaired automatically"

log "  -- a check that outlives its bound: killed as a group, so its own children die too"
: > "$NIX_LOG"
make_nix_stub 'sleep 120 & printf "%s\n" "$!" > "'"$WORKDIR"'/builder.pid"; sleep 120'
read -r REQ_V3 R_V3 Q_V3 A_V3 <<<"$(new_approval APPLYABLE-MODIFY-timesout)"
rm -f "$WORKDIR/builder.pid"
if PATH="$NIX_BIN:$PATH" CASTLE_APPLY_EVALUATE_FLAKE=true CASTLE_APPLY_TIMEOUT=2 \
  "$CASTLE" apply "$A_V3" >/dev/null 2>&1; then
  fail "an apply whose check timed out exited 0"
fi
AP_V3="$(newest_apply_result_for "$A_V3")"
grep -q '^outcome: timeout$' "$AP_V3" \
  || fail "a check killed at its bound is not outcome: timeout: $(field_of "$AP_V3" outcome)"
grep -q '^apply-outcome: validation-failed$' "$AP_V3" \
  || fail "a timed-out check did not compose into validation-failed: $(field_of "$AP_V3" apply-outcome)"
BUILDER_PID="$(cat "$WORKDIR/builder.pid" 2>/dev/null || true)"
[ -n "$BUILDER_PID" ] || fail "the timeout fixture never recorded its own child's pid"
# The proof that the whole process group was killed rather than just the
# parent: `nix build` spawns builders, and killing only the parent
# leaves them running.
kill -0 "$BUILDER_PID" 2>/dev/null \
  && fail "the check's own child survived the timeout — only the parent was killed"
assert_private_changed_exactly "the timed-out apply" "$A_V3" resident.nix

log "  -- a repository whose own path Nix cannot be told about at all"
# Verified against real nix before it was fixed: a `#` in the private
# root makes the flakeref split there, so nix resolves a shorter path,
# reports it does not exist, and exits nonzero — which landed as
# `validation-failed`, a false claim that the resident's configuration
# no longer builds. There is no escaping rule for `#` or `?` in a path
# flakeref, so this is a skip with an honest reason and not a refusal:
# the apply and the commit are fine, only the check is inexpressible.
#
# The sharp assertion here is that nix is **never invoked**, which is
# what this harness can prove with a stub and what no real-nix run is
# needed for. A stub exits 0 whatever argv it is handed, so it cannot
# reproduce the false `validation-failed` itself; what it can prove is
# that the wrong flakeref is never constructed in the first place.
#
# Its own throwaway checkout, because the character has to be in the
# repository's real path.
HASHED="$WORKDIR/private#hash"
mkdir -p "$HASHED"
cp "$PRIVATE/flake.nix" "$HASHED/flake.nix"
printf '# Synthetic private layer, harness fixture only.\n# APPLYABLE-MARKER: start\n{ }\n' \
  > "$HASHED/resident.nix"
git -C "$HASHED" init -q
git -C "$HASHED" add -A
git -C "$HASHED" commit -q -m "fixture: a checkout at a path Nix cannot name"
: > "$NIX_LOG"
make_nix_stub 'exit 0'
read -r REQ_HR R_HR Q_HR A_HR <<<"$(CASTLE_PRIVATE_ROOT="$HASHED" new_approval APPLYABLE-MODIFY-hashroot)"
PATH="$NIX_BIN:$PATH" CASTLE_PRIVATE_ROOT="$HASHED" CASTLE_APPLY_EVALUATE_FLAKE=true \
  "$CASTLE" apply "$A_HR" >/dev/null \
  || fail "an apply into a repository Nix cannot name failed outright"
AP_HR="$(newest_apply_result_for "$A_HR")"
grep -q '^apply-outcome: applied-unvalidated$' "$AP_HR" \
  || fail "an unexpressible flakeref was reported as a failed build: $(field_of "$AP_HR" apply-outcome)"
grep -qF 'flakeref syntax' "$AP_HR" \
  || fail "the record does not say why nothing could be checked: $(cat "$AP_HR")"
grep -qF '`#`' "$AP_HR" \
  || fail "the record does not name the character in the way: $(cat "$AP_HR")"
[ ! -s "$NIX_LOG" ] \
  || fail "nix was invoked with a flakeref that names the wrong directory: $(cat "$NIX_LOG")"
# The change itself landed perfectly well — only the check was skipped.
[ "$(git -C "$HASHED" rev-list --count HEAD)" = "2" ] \
  || fail "the apply into the oddly-named checkout did not make exactly one commit"
[ -z "$(git -C "$HASHED" status --porcelain)" ] \
  || fail "the apply into the oddly-named checkout left the tree dirty"
assert_private_untouched "after the unnameable-root scenario"

log "  -- and with no nix on PATH at all: not checked, and no crash"
read -r REQ_V4 R_V4 Q_V4 A_V4 <<<"$(new_approval APPLYABLE-MODIFY-nonix)"
EMPTY_BIN="$WORKDIR/empty-bin"
mkdir -p "$EMPTY_BIN"
# Two things borrowed onto the stripped PATH, and only two: `git`,
# which this task genuinely needs, and the interpreter `castle`'s own
# shebang resolves through `/usr/bin/env`. Everything else — `nix` above
# all — is deliberately absent, which is the whole point of the
# scenario.
ln -sf "$(command -v git)" "$EMPTY_BIN/git"
ln -sf "$(command -v python3)" "$EMPTY_BIN/python3"
PATH="$EMPTY_BIN" CASTLE_APPLY_EVALUATE_FLAKE=true "$CASTLE" apply "$A_V4" >/dev/null \
  || fail "an apply on a host with no nix failed instead of reporting it was not checked"
AP_V4="$(newest_apply_result_for "$A_V4")"
grep -q '^apply-outcome: applied-unvalidated$' "$AP_V4" \
  || fail "a host with no nix is not applied-unvalidated: $(field_of "$AP_V4" apply-outcome)"
grep -q 'not on this session' "$AP_V4" \
  || fail "the record does not say why nothing was checked: $(cat "$AP_V4")"
assert_private_changed_exactly "the no-nix apply" "$A_V4" resident.nix
assert_mechanism_untouched "after the evaluation-gate scenarios"
"$CASTLE" validate >/dev/null || fail "the journal does not validate after the evaluation-gate scenarios"

# ---------------------------------------------------------------------
log "the validator's permanent gate: the two new fields, and the cross-record rule"
# ---------------------------------------------------------------------
# Planted into a throwaway journal via --journal, so the real one stays
# clean and every case here can be genuinely malformed. These are the
# records a hand edit, a restore, or a future tool could produce.
PLANT="$WORKDIR/plant"
plant_reset() { rm -rf "$PLANT"; mkdir -p "$PLANT"; }
plant() {
  local id="$1" rtype="$2" refs="$3"; shift 3
  {
    echo "---"
    echo "id: $id"
    echo "type: $rtype"
    echo "provenance: requested"
    echo "refs: $refs"
    echo "seat: intake"
    echo "created: 2026-02-01T00:00:00Z"
    local line
    for line in "$@"; do echo "$line"; done
    echo "---"
    echo
    echo "A planted record, harness fixture only."
  } > "$PLANT/$id.md"
}
VALID_HASH="$(printf 'anything at all' | sha256sum | cut -d' ' -f1)"
plant_base() {
  plant_reset
  plant 20260201T000000Z-request-aaaaaa request ""
  plant 20260201T000001Z-result-bbbbbb result 20260201T000000Z-request-aaaaaa \
    "outcome: completed" "target: private"
  plant 20260201T000002Z-question-cccccc question \
    "20260201T000000Z-request-aaaaaa,20260201T000001Z-result-bbbbbb" \
    "proposal-sha256: $VALID_HASH" "authorizes-apply: true"
  plant 20260201T000003Z-answer-dddddd answer \
    "20260201T000002Z-question-cccccc,20260201T000001Z-result-bbbbbb" \
    "decision: approve" "proposal-sha256: $VALID_HASH"
}
expect_valid() {
  "$CASTLE" validate --journal "$PLANT" >/dev/null 2>"$WORKDIR/plant.err" \
    || fail "$1: the validator rejected a well-formed journal: $(cat "$WORKDIR/plant.err")"
}
expect_invalid() {
  local label="$1" needle="$2"
  if "$CASTLE" validate --journal "$PLANT" >/dev/null 2>"$WORKDIR/plant.err"; then
    fail "$label: the validator accepted it"
  fi
  grep -q -- "$needle" "$WORKDIR/plant.err" \
    || fail "$label: the validator complained about something else: $(cat "$WORKDIR/plant.err")"
}

log "  -- the well-formed shape validates (the control: without it every case below is vacuous)"
plant_base
plant 20260201T000004Z-result-eeeeee result \
  "20260201T000003Z-answer-dddddd,20260201T000002Z-question-cccccc" \
  "outcome: completed" "apply-outcome: applied-validated"
expect_valid "a well-formed apply record"

log "  -- authorizes-apply on a record that reads it nowhere"
plant_base
plant 20260201T000004Z-result-eeeeee result 20260201T000000Z-request-aaaaaa \
  "outcome: completed" "authorizes-apply: true"
expect_invalid "authorizes-apply on a result" "'authorizes-apply' is a question-record field"

log "  -- authorizes-apply: false, which is inert but not visible"
plant_base
plant 20260201T000004Z-question-ffffff question 20260201T000000Z-request-aaaaaa \
  "proposal-sha256: $VALID_HASH" "authorizes-apply: false"
expect_invalid "authorizes-apply: false" "is not the literal 'true'"

log "  -- apply-outcome on a record that reads it nowhere"
plant_base
plant 20260201T000004Z-answer-eeeeee answer 20260201T000002Z-question-cccccc \
  "apply-outcome: applied-validated"
expect_invalid "apply-outcome on an answer" "'apply-outcome' is a result-record field"

log "  -- an apply-outcome outside the vocabulary"
plant_base
plant 20260201T000004Z-result-eeeeee result \
  "20260201T000003Z-answer-dddddd,20260201T000002Z-question-cccccc" \
  "outcome: completed" "apply-outcome: sure-why-not"
expect_invalid "an unknown apply-outcome" "is not one of applied-validated"

log "  -- an apply claiming an authorization that does not exist"
plant_base
plant 20260201T000004Z-result-eeeeee result \
  "20260201T000000Z-request-aaaaaa,20260201T000002Z-question-cccccc" \
  "outcome: completed" "apply-outcome: applied-validated"
expect_invalid "an apply naming no approval" "not an answer approving a change"

log "  -- and one naming an answer that did not approve"
plant_base
plant 20260201T000004Z-answer-eeeeee answer \
  "20260201T000002Z-question-cccccc,20260201T000001Z-result-bbbbbb" \
  "decision: reject" "proposal-sha256: $VALID_HASH"
plant 20260201T000005Z-result-ffffff result \
  "20260201T000004Z-answer-eeeeee,20260201T000002Z-question-cccccc" \
  "outcome: completed" "apply-outcome: applied-validated"
expect_invalid "an apply on a rejection" "not an answer approving a change"

# ---------------------------------------------------------------------
log "everything this run produced still validates, and the framework never moved"
# ---------------------------------------------------------------------
"$CASTLE" validate || fail "the journal this whole run produced does not validate"
assert_mechanism_untouched "at the end of the run"

# ---------------------------------------------------------------------
log "no home-shaped path in anything this fixture commits to the repo"
# ---------------------------------------------------------------------
# CLAUDE.md's hard rule, checked mechanically rather than trusted.
LEAKED_PATHS="$(grep -nE '(/home/|\$HOME)' "${BASH_SOURCE[0]}" | grep -v '/home/resident' || true)"
[ -z "$LEAKED_PATHS" ] || fail "a home-shaped path leaked into a committed fixture file:
$LEAKED_PATHS"

log "all assertions passed"
