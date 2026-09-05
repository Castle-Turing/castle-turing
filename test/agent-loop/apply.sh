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

# docs/tasks/0034-inbox-modal.md §3 moved the whole notify-send
# invocation into a detached waiter process (`castle notify-waiter`)
# that the router does not wait on — "the dispatch sweep must never
# block on notification interaction" — so `$CASTLE_NOTIFY_LOG` can lag
# a few milliseconds behind the command that triggers it returning.
# Polls rather than sleeping a fixed amount: bounded at ~10s so a
# genuine failure still fails promptly, and fast on the happy path
# (0.1s granularity) since the notify-stub this file uses is a
# synchronous script with no real --wait to block on. Returns 1 rather
# than failing itself, so callers keep their own "$(cat log)" message.
wait_for_notify_log() {
  local pattern="$1" tries=100 i
  for ((i = 0; i < tries; i++)); do
    grep -q -- "$pattern" "$CASTLE_NOTIFY_LOG" 2>/dev/null && return 0
    sleep 0.1
  done
  grep -q -- "$pattern" "$CASTLE_NOTIFY_LOG" 2>/dev/null
}

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
  # `core.quotePath=false` so a name that is not plain ASCII comes back
  # as its own bytes rather than as git's `"\377"` escape, and `LC_ALL=C`
  # so the two sorts below agree about byte order rather than about some
  # locale's collation.
  named="$(git -C "$PRIVATE" -c core.quotePath=false show --name-only --format= "$head_now" \
    | sed '/^$/d' | LC_ALL=C sort | tr '\n' ' ')"
  want="$(printf '%s\n' "${expected[@]}" | LC_ALL=C sort | tr '\n' ' ')"
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

log "  -- and the commit it made is a FIELD, not a sentence something would have to grep for"
# docs/tasks/0027 is the surface that will need this mechanically, and
# this project's own named contract says no surface may ever infer a
# fact by grepping a body (agent/README.md's `outcome` section). The
# prose stays for the resident; the field is what a machine reads.
[ "$(field_of "$AP1" apply-commit)" = "$(git -C "$PRIVATE" rev-parse HEAD)" ] \
  || fail "the record's apply-commit is not the commit the apply made: field says [$(field_of "$AP1" apply-commit)], repository says [$(git -C "$PRIVATE" rev-parse HEAD)]"

log "  -- and the resident is told, in the words drafted for that one line"
wait_for_notify_log 'The change you approved is now in your configuration repository. It was not checked, and nothing was activated.' \
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
log "the resident's git hooks do not run on the applier's commit"
# ---------------------------------------------------------------------
# Reproduced before it was fixed, and it broke the digest chain the
# whole design rides on: an ordinary formatting `pre-commit` rewrote the
# committed bytes, so the commit whose message asserts `patch-sha256`
# did not contain those bytes; a `post-commit` hook then dirtied the
# tree, and `rev-parse HEAD` could name a commit the applier never made
# — with `git revert <sha>` printed beside it in the record.
#
# Both hooks are real, ordinary shapes: reformat-and-restage, and
# generate-a-file. Neither is adversarial; that is the point.
mkdir -p "$PRIVATE/.git/hooks"
cat > "$PRIVATE/.git/hooks/pre-commit" <<'HOOK'
#!/usr/bin/env bash
# An ordinary formatting hook, harness fixture only.
printf '# reformatted by the resident hook\n' >> resident.nix
git add resident.nix
HOOK
cat > "$PRIVATE/.git/hooks/post-commit" <<'HOOK'
#!/usr/bin/env bash
# An ordinary generate-something hook, harness fixture only.
printf 'generated by the resident hook\n' > hook-generated.txt
HOOK
chmod +x "$PRIVATE/.git/hooks/pre-commit" "$PRIVATE/.git/hooks/post-commit"
read -r REQ_H R_H Q_H A_H <<<"$(new_approval APPLYABLE-MODIFY-hooks)"
"$CASTLE" apply "$A_H" >/dev/null || fail "an apply in a repository with hooks failed"
# The full assertion: exactly one commit, whose parent is where we
# started, naming exactly the patch's path, byte-identical to what the
# tenant computed, and a clean tree afterwards.
assert_private_changed_exactly "an apply in a repository with hooks" "$A_H" resident.nix
git -C "$PRIVATE" show HEAD:resident.nix | grep -q 'reformatted by the resident hook' \
  && fail "the pre-commit hook rewrote the bytes the record's own digest was verified against"
[ ! -e "$PRIVATE/hook-generated.txt" ] \
  || fail "the post-commit hook ran and left a file behind"
AP_H="$(newest_apply_result_for "$A_H")"
grep -qF "$(git -C "$PRIVATE" rev-parse HEAD)" "$AP_H" \
  || fail "the record names a commit sha that is not the repository's head: $(cat "$AP_H")"
rm -f "$PRIVATE/.git/hooks/pre-commit" "$PRIVATE/.git/hooks/post-commit"

log "  -- the control: those hooks really do run on a commit the resident makes"
# Without this the assertions above are satisfied by two hooks that were
# never executable, never found, or silently broken — proving nothing.
cat > "$PRIVATE/.git/hooks/post-commit" <<'HOOK'
#!/usr/bin/env bash
printf 'generated by the resident hook\n' > hook-generated.txt
HOOK
chmod +x "$PRIVATE/.git/hooks/post-commit"
printf '# an edit the resident made themselves\n' >> "$PRIVATE/hosts/example/default.nix"
git -C "$PRIVATE" commit -q -am "the resident commits, with their own hooks"
[ -e "$PRIVATE/hook-generated.txt" ] \
  || fail "the fixture hooks do not run even for the resident, so the assertions above prove nothing"
rm -f "$PRIVATE/.git/hooks/post-commit" "$PRIVATE/hook-generated.txt"
git -C "$PRIVATE" checkout -q -- .
PRIVATE_HEAD="$(git -C "$PRIVATE" rev-parse HEAD)"
assert_private_untouched "after the hook control"
assert_mechanism_untouched "after the hook scenarios"

# ---------------------------------------------------------------------
log "a content filter cannot reach the commit at all, and the disagreement is reported"
# ---------------------------------------------------------------------
# This used to be a detection scenario, and the temp-index construction
# turned it into a prevention one. A `.gitattributes` clean filter runs
# at `add`/`commit` even with hooks disabled, so the old
# apply-then-commit sequence committed the filter's bytes rather than
# the approved ones. `git apply --cached` does NOT run clean filters —
# established by running it — so a commit built in a private index from
# `head_before` plus the verified patch holds exactly what was
# approved, and the filter has nowhere to act.
#
# What is left is a real disagreement that has to be *said* rather than
# resolved: the repository's own filter would canonicalise those bytes
# differently, so git will report the file as modified. The applier does
# not pick a side; it commits what was approved and names the
# difference.
FILTER_HEAD_BEFORE="$PRIVATE_HEAD"
# An ordinary formatter-shaped filter: rewrites on the way in, passes
# through on the way out. Nothing adversarial.
#
# Configured BEFORE the fixture file is committed, deliberately. Added
# afterwards, the index would hold unfiltered bytes and `git status`
# would report the file modified forever — the apply would refuse
# `refused-tree-dirty` and never reach the commit this is about.
# Committing under the filter is also what a resident's repository
# actually looks like.
#
# No space in the sed script: git splits a filter command on whitespace.
git -C "$PRIVATE" config filter.rewriter.clean "sed s/filteredchange/FILTERED-filteredchange/"
git -C "$PRIVATE" config filter.rewriter.smudge cat
printf '# Synthetic file this repository filters, harness fixture only.\n# APPLYABLE-MARKER: start\n' \
  > "$PRIVATE/filtered.nix"
printf 'filtered.nix filter=rewriter\n' > "$PRIVATE/.gitattributes"
git -C "$PRIVATE" add -A
git -C "$PRIVATE" commit -q -m "fixture: a file this repository runs a content filter over"
PRIVATE_HEAD="$(git -C "$PRIVATE" rev-parse HEAD)"
[ -z "$(git -C "$PRIVATE" status --porcelain)" ] \
  || fail "the filtered fixture is dirty before the scenario starts: $(git -C "$PRIVATE" status --porcelain)"
read -r REQ_FL R_FL Q_FL A_FL <<<"$(new_approval APPLYABLE-FILTERED)"
"$CASTLE" apply "$A_FL" >/dev/null \
  || fail "an apply into a repository with a content filter failed"
AP_FL="$(newest_apply_result_for "$A_FL")"
grep -q '^apply-outcome: applied-unvalidated$' "$AP_FL" \
  || fail "the filtered apply has the wrong outcome: $(field_of "$AP_FL" apply-outcome)"
log "  -- and the commit holds the APPROVED bytes, not the filter's"
# The whole point, and the assertion that would have failed before the
# construction changed.
git -C "$PRIVATE" cat-file blob HEAD:filtered.nix | grep -q 'APPLYABLE-MARKER: filteredchange' \
  || fail "the commit does not hold the approved bytes: $(git -C "$PRIVATE" cat-file blob HEAD:filtered.nix)"
git -C "$PRIVATE" cat-file blob HEAD:filtered.nix | grep -q 'FILTERED-' \
  && fail "the content filter reached the commit — it committed bytes nobody approved"
[ "$(field_of "$AP_FL" apply-commit)" = "$(git -C "$PRIVATE" rev-parse HEAD)" ] \
  || fail "the filtered apply did not stamp the commit it made"
log "  -- and the record says why git will keep showing that file as modified"
grep -q 'content filter' "$AP_FL" \
  || fail "the record does not explain the disagreement: $(cat "$AP_FL")"
grep -q 'filtered.nix' "$AP_FL" \
  || fail "the record does not name the file the disagreement is about: $(cat "$AP_FL")"
[ -n "$(git -C "$PRIVATE" status --porcelain)" ] \
  || fail "the fixture filter does not actually disagree, so this proves nothing"
# Put the fixture back: drop the commit and the filter with it.
git -C "$PRIVATE" config --unset filter.rewriter.clean
git -C "$PRIVATE" config --unset filter.rewriter.smudge
git -C "$PRIVATE" reset -q --hard "$FILTER_HEAD_BEFORE"
PRIVATE_HEAD="$FILTER_HEAD_BEFORE"
assert_private_untouched "after the content-filter scenario"
assert_mechanism_untouched "after the content-filter scenario"
"$CASTLE" validate >/dev/null || fail "the journal does not validate after the content-filter scenario"

# ---------------------------------------------------------------------
log "a crash between moving the reference and writing the record does not become a lie"
# ---------------------------------------------------------------------
# The window, and it is now much smaller than it was: everything up to
# `git update-ref` is a read plus a private index, so the only span in
# which the repository can have moved without the journal saying so is
# the reference update and the working-tree sync after it. If the
# process dies there, no result names the answer, so it stays eligible —
# and a fresh attempt would refuse `refused-patch-stale` over a change
# that is already committed. A durable record saying the applier
# declined a change sitting in the resident's repository.
#
# **Killed for real, through a `git` on $PATH rather than a seam in the
# code under test.** The wrapper runs the real git and then SIGKILLs its
# own parent, which is the castle process. Same discipline as the `nix`
# stub, and the reason the brief rejected a `CASTLE_APPLY_NIX`-style
# override.
KILL_BIN="$WORKDIR/kill-bin"
MARKER_PROBE="$WORKDIR/marker-probe.log"
mkdir -p "$KILL_BIN"
REAL_GIT="$(command -v git)"
cat > "$KILL_BIN/git" <<KILLER
#!/usr/bin/env bash
# A real git that dies at a chosen moment, harness fixture only.
mutating=no
case " \$* " in *" update-ref "*) mutating=update-ref ;; esac
# Whether the crash breadcrumb was on disk at the instant the
# repository moved — asserted below, because "it is written before the
# first mutation" is the whole claim.
if [ "\$mutating" != no ] && [ -n "\${CASTLE_TEST_MARKER_DIR:-}" ]; then
  if [ -e "\$CASTLE_TEST_MARKER_DIR/\${CASTLE_TEST_MARKER_ID:-none}" ]; then
    printf '%s marker-present\n' "\$mutating" >> "$MARKER_PROBE"
  else
    printf '%s marker-ABSENT\n' "\$mutating" >> "$MARKER_PROBE"
  fi
fi
if [ -n "\${CASTLE_TEST_KILL_BEFORE:-}" ] && [ "\$mutating" = "\${CASTLE_TEST_KILL_BEFORE}" ]; then
  kill -9 "\$PPID"
  sleep 5
fi
"$REAL_GIT" "\$@"
status=\$?
if [ -n "\${CASTLE_TEST_KILL_AFTER:-}" ] && [ "\$mutating" = "\${CASTLE_TEST_KILL_AFTER}" ]; then
  kill -9 "\$PPID"
fi
exit \$status
KILLER
chmod +x "$KILL_BIN/git"
MARKER_DIR="$CASTLE_STATE_DIR/apply-in-flight"

log "  -- killed BEFORE the reference moved: nothing changed, and the record is conservative"
# The breadcrumb cannot know whether the update happened, so it says an
# attempt may have begun and gives the resident both shas to compare.
# Here they are equal, and the record says so.
read -r REQ_IF R_IF Q_IF A_IF <<<"$(new_approval APPLYABLE-MODIFY-inflight)"
[ ! -e "$MARKER_DIR/$A_IF" ] || fail "a marker exists before any attempt began"
: > "$MARKER_PROBE"
FILES_BEFORE="$(journal_file_count)"
PATH="$KILL_BIN:$PATH" CASTLE_TEST_KILL_BEFORE=update-ref CASTLE_TEST_MARKER_DIR="$MARKER_DIR" \
  CASTLE_TEST_MARKER_ID="$A_IF" "$CASTLE" apply "$A_IF" >/dev/null 2>&1 \
  && fail "the applier was supposed to be killed at the reference update and exited 0"
grep -q '^update-ref marker-present$' "$MARKER_PROBE" \
  || fail "the breadcrumb was not on disk at the instant the repository was about to move: $(cat "$MARKER_PROBE")"
[ -f "$MARKER_DIR/$A_IF" ] || fail "the killed attempt left no breadcrumb behind"
grep -q "^answer: $A_IF\$" "$MARKER_DIR/$A_IF" \
  || fail "the breadcrumb does not name the authorization: $(cat "$MARKER_DIR/$A_IF")"
[ "$(journal_file_count)" = "$FILES_BEFORE" ] || fail "the killed attempt wrote a record after all"
assert_private_untouched "after a kill before the reference moved"
"$CASTLE" apply --sweep >/dev/null
AP_IF="$(newest_apply_result_for "$A_IF")"
[ -n "$AP_IF" ] || fail "the sweep did not account for the interrupted attempt"
grep -q '^outcome: failed$' "$AP_IF" \
  || fail "an interrupted attempt is not recorded as a failed run: $(field_of "$AP_IF" outcome)"
grep -q '^apply-outcome:' "$AP_IF" \
  && fail "an interrupted attempt claimed something about the change"
grep -q '^apply-commit:' "$AP_IF" \
  && fail "an interrupted attempt named a commit it cannot vouch for"
grep -qE '^apply-outcome: (refused-tree-dirty|refused-patch-stale)$' "$AP_IF" \
  && fail "the sweep refused a change rather than recording that an attempt was interrupted"
grep -q 'has NOT moved' "$AP_IF" \
  || fail "the record does not tell the resident nothing was committed: $(cat "$AP_IF")"
[ ! -e "$MARKER_DIR/$A_IF" ] || fail "the breadcrumb survived its own reconciliation"
assert_private_untouched "after reconciling an attempt killed before the reference moved"

log "  -- killed AFTER the reference moved: the commit is there, and the record says so"
# The half that matters. A fresh attempt here would have refused
# `refused-patch-stale` about a change that is already committed.
read -r REQ_IF2 R_IF2 Q_IF2 A_IF2 <<<"$(new_approval APPLYABLE-MODIFY-inflight2)"
: > "$MARKER_PROBE"
PATH="$KILL_BIN:$PATH" CASTLE_TEST_KILL_AFTER=update-ref CASTLE_TEST_MARKER_DIR="$MARKER_DIR" \
  CASTLE_TEST_MARKER_ID="$A_IF2" "$CASTLE" apply "$A_IF2" >/dev/null 2>&1 \
  && fail "the applier was supposed to be killed after the reference moved and exited 0"
[ -f "$MARKER_DIR/$A_IF2" ] || fail "the killed-after-update attempt left no breadcrumb"
LANDED_HEAD="$(git -C "$PRIVATE" rev-parse HEAD)"
[ "$LANDED_HEAD" != "$PRIVATE_HEAD" ] \
  || fail "the killed-after-update attempt did not move the reference, so this proves nothing"
"$CASTLE" apply --sweep >/dev/null
AP_IF2="$(newest_apply_result_for "$A_IF2")"
grep -q '^outcome: failed$' "$AP_IF2" || fail "the killed-after-update case is not a failed run"
grep -q '^apply-outcome:' "$AP_IF2" \
  && fail "the killed-after-update case claimed something about the change"
grep -q 'HAS moved' "$AP_IF2" \
  || fail "the record does not say the head moved, which is the fact that matters here: $(cat "$AP_IF2")"
grep -qF "$PRIVATE_HEAD" "$AP_IF2" \
  || fail "the record does not name where the repository was when the attempt began"
[ ! -e "$MARKER_DIR/$A_IF2" ] || fail "the breadcrumb survived its own reconciliation"
[ "$(git -C "$PRIVATE" rev-parse HEAD)" = "$LANDED_HEAD" ] \
  || fail "the sweep committed on top of a change that was already committed"
# The interrupted attempt never got to sync the working tree, which is
# exactly the state the record describes; put it right the way a
# resident would.
git -C "$PRIVATE" reset -q --hard "$LANDED_HEAD"
PRIVATE_HEAD="$LANDED_HEAD"
assert_private_untouched "after reconciling an attempt killed after the reference moved"

log "  -- a breadcrumb naming nothing this journal has is discarded, with no record"
printf 'answer: 20260101T000000Z-answer-invented\nhead-before: \npaths:\n' \
  > "$MARKER_DIR/20260101T000000Z-answer-invented"
FILES_BEFORE="$(journal_file_count)"
"$CASTLE" apply --sweep >"$WORKDIR/stray-marker.out" 2>&1
grep -q 'discarding an in-flight marker' "$WORKDIR/stray-marker.out" \
  || fail "a stray breadcrumb was not reported: $(cat "$WORKDIR/stray-marker.out")"
[ ! -e "$MARKER_DIR/20260101T000000Z-answer-invented" ] || fail "a stray breadcrumb survived"
[ "$(journal_file_count)" = "$FILES_BEFORE" ] \
  || fail "a stray breadcrumb produced a record about a checkout nothing can name"
"$CASTLE" validate >/dev/null || fail "the journal does not validate after the interruption scenarios"
assert_mechanism_untouched "after the interruption scenarios"

# ---------------------------------------------------------------------
log "a concurrent edit cannot get into the commit, and is not destroyed either"
# ---------------------------------------------------------------------
# The finding this construction exists for. Under the old sequence — 
# apply to the working tree, then commit from it — anything writing one
# of those paths in between got its bytes committed and certified under
# a message asserting the approved patch's digest, with every check
# passing because the committed blob and the working tree agreed.
# Reproduced before the change.
#
# There is no worktree-apply step any more, so the edit is injected into
# the only window that remains: after the reference moves, before the
# working tree is synced to it. The wrapper writes the file the instant
# it sees `update-ref` succeed.
CONCURRENT_BIN="$WORKDIR/concurrent-bin"
mkdir -p "$CONCURRENT_BIN"
cat > "$CONCURRENT_BIN/git" <<CONC
#!/usr/bin/env bash
# A real git that lets somebody else write a file mid-sequence.
mutating=no
case " \$* " in *" update-ref "*) mutating=update-ref ;; esac
"$REAL_GIT" "\$@"
status=\$?
if [ "\$mutating" = update-ref ] && [ \$status -eq 0 ] && [ -n "\${CASTLE_TEST_CONCURRENT_FILE:-}" ]; then
  printf '%s' "\${CASTLE_TEST_CONCURRENT_BODY}" > "\$CASTLE_TEST_CONCURRENT_FILE"
  unset CASTLE_TEST_CONCURRENT_FILE
fi
exit \$status
CONC
chmod +x "$CONCURRENT_BIN/git"
read -r REQ_CC R_CC Q_CC A_CC <<<"$(new_approval APPLYABLE-MODIFY-concurrent)"
CONCURRENT_BODY='# Synthetic private layer, harness fixture only.
# APPLYABLE-MARKER: the resident typed this instead
'
PATH="$CONCURRENT_BIN:$PATH" CASTLE_TEST_CONCURRENT_FILE="$PRIVATE/resident.nix" \
  CASTLE_TEST_CONCURRENT_BODY="$CONCURRENT_BODY" "$CASTLE" apply "$A_CC" >/dev/null \
  || fail "an apply raced by a concurrent edit failed outright"
AP_CC="$(newest_apply_result_for "$A_CC")"

log "  -- the commit holds the approved change, and none of the concurrent edit"
git -C "$PRIVATE" cat-file blob HEAD:resident.nix | grep -q 'the resident typed this instead' \
  && fail "bytes nobody approved were committed and certified as the approved change"
git -C "$PRIVATE" cat-file blob HEAD:resident.nix | grep -q 'APPLYABLE-MARKER: concurrent' \
  || fail "the commit does not hold the approved change: $(git -C "$PRIVATE" cat-file blob HEAD:resident.nix)"
[ "$(field_of "$AP_CC" apply-commit)" = "$(git -C "$PRIVATE" rev-parse HEAD)" ] \
  || fail "the record does not stamp the commit that was made"
[ "$(git -C "$PRIVATE" rev-list --count "$PRIVATE_HEAD..HEAD")" = "1" ] \
  || fail "the raced apply did not make exactly one commit"

log "  -- and their edit is still on disk, untouched, as ordinary visible dirt"
# `cmp`, not `$(cat) = $VAR`: command substitution strips trailing
# newlines from one side and not the other, which would let a genuinely
# clobbered file compare equal.
printf '%s' "$CONCURRENT_BODY" > "$WORKDIR/concurrent-expected"
cmp -s "$WORKDIR/concurrent-expected" "$PRIVATE/resident.nix" \
  || fail "the concurrent edit was overwritten: $(cat "$PRIVATE/resident.nix")"
[ -n "$(git -C "$PRIVATE" status --porcelain -- resident.nix)" ] \
  || fail "the concurrent edit is not visible as dirt, so the resident would never see it"

log "  -- and the record names the divergence rather than pretending it did not happen"
grep -q 'left exactly as you left them' "$AP_CC" \
  || fail "the record does not say the file was left alone: $(cat "$AP_CC")"
grep -q 'resident.nix' "$AP_CC" \
  || fail "the record does not name the diverged file: $(cat "$AP_CC")"
STATUS_CC="$("$MODAL" --mode status --limit 40)"
printf '%s\n' "$STATUS_CC" | grep -F "$REQ_CC" | grep -q 'applied, not checked — not activated' \
  || fail "the raced errand does not read as applied: $(printf '%s\n' "$STATUS_CC" | grep -F "$REQ_CC")"
# The resident's own call to make; the harness takes the commit.
git -C "$PRIVATE" checkout -q -- resident.nix
PRIVATE_HEAD="$(git -C "$PRIVATE" rev-parse HEAD)"
assert_private_untouched "after the concurrent-edit scenario"
assert_mechanism_untouched "after the concurrent-edit scenario"
"$CASTLE" validate >/dev/null || fail "the journal does not validate after the concurrent-edit scenario"

# ---------------------------------------------------------------------
log "file names git has to be asked about: an invalid UTF-8 byte, and a glob character"
# ---------------------------------------------------------------------
# Built with printf, never pasted, so this file's own source stays plain
# ASCII (the same discipline config-target.sh's byte-fidelity fixtures
# keep). The invalid byte is Codex's P2: `--numstat -z` was read as text
# with errors="replace", so a name like this became U+FFFD, the dirty
# check inspected a path that does not exist, and the pathspec commit
# then failed AFTER the tree had been modified. The `*` is the pathspec
# half: `--` ends options, it does not stop git reading what follows as
# a glob.
ODD_NAMES="$WORKDIR/odd-names"
printf 'odd-\377-byte.nix\nodd-*-glob.nix\n' > "$ODD_NAMES"
export CASTLE_APPLYABLE_ODD_NAMES="$ODD_NAMES"
# A decoy the glob would match if the pathspec were not literal. If `*`
# were read as a pattern, the commit would contain this file too — which
# `assert_private_changed_exactly` refuses by name.
printf '# A file the glob must not reach, harness fixture only.\n' > "$PRIVATE/odd-DECOY-glob.nix"
git -C "$PRIVATE" add -A && git -C "$PRIVATE" commit -q -m "fixture: a file a glob could reach"
PRIVATE_HEAD="$(git -C "$PRIVATE" rev-parse HEAD)"
DECOY_BEFORE="$(sha256_of "$PRIVATE/odd-DECOY-glob.nix")"
read -r REQ_ODD R_ODD Q_ODD A_ODD <<<"$(new_approval APPLYABLE-ODDNAMES)"
"$CASTLE" apply "$A_ODD" >/dev/null || fail "an apply creating oddly-named files failed"
assert_private_changed_exactly "oddly-named files" "$A_ODD" \
  "$(printf 'odd-\377-byte.nix')" 'odd-*-glob.nix'
[ "$(sha256_of "$PRIVATE/odd-DECOY-glob.nix")" = "$DECOY_BEFORE" ] \
  || fail "the glob-named pathspec reached a file it should not have"
log "  -- and the record it wrote is still valid UTF-8, which is what makes a journal readable"
"$CASTLE" validate >/dev/null \
  || fail "a path that is not valid UTF-8 made it into a record and broke the journal"
unset CASTLE_APPLYABLE_ODD_NAMES
assert_mechanism_untouched "after the odd-name scenarios"

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
log "an unattended applier refuses to make liveness decisions on world-writable locks"
# ---------------------------------------------------------------------
# Mirroring dispatch-test.sh's own scenario for the same hazard, one
# seat up. With no XDG_RUNTIME_DIR and no /run/user/$UID, the only lock
# directory left is /tmp/castle-$UID, which any local user can create
# first: they hold `apply.lock`, the sweep reports "another applier is
# already running" and exits 0 forever, green in systemctl, while every
# approval the resident granted sits unapplied. The hand path keeps that
# fallback on purpose — a human is watching it — and a timer is not.
#
# Branching on the directory because both worlds are real: a developer
# machine has /run/user/$UID, a CI runner may not.
FILES_BEFORE="$(journal_file_count)"
if [ -d "/run/user/$(id -u)" ]; then
  log "  -- /run/user/$(id -u) exists here, so the sweep should fall back to it and run normally"
  env -u XDG_RUNTIME_DIR "$CASTLE" apply --sweep >"$WORKDIR/no-xdg.out" 2>&1 \
    || fail "a sweep with no XDG_RUNTIME_DIR but a real /run/user/\$UID refused to run: $(cat "$WORKDIR/no-xdg.out")"
else
  log "  -- no /run/user/$(id -u) here, so the only lock directory is world-writable and the sweep must refuse"
  if env -u XDG_RUNTIME_DIR "$CASTLE" apply --sweep >"$WORKDIR/no-xdg.out" 2>&1; then
    fail "a sweep with only the /tmp lock fallback available exited 0 instead of refusing: $(cat "$WORKDIR/no-xdg.out")"
  fi
  grep -q "world-writable" "$WORKDIR/no-xdg.out" \
    || fail "the refusal did not explain itself: $(cat "$WORKDIR/no-xdg.out")"
  grep -q "castle apply <answer-id>" "$WORKDIR/no-xdg.out" \
    || fail "the refusal does not name the hand path it deliberately keeps: $(cat "$WORKDIR/no-xdg.out")"
fi
[ "$(journal_file_count)" = "$FILES_BEFORE" ] \
  || fail "the fallback-lock scenario spent an approval"
assert_private_untouched "after the world-writable lock scenario"

# ---------------------------------------------------------------------
log "refused: a change to the framework itself is not this seat's to make"
# ---------------------------------------------------------------------
# **The historical-record backstop**
# (docs/tasks/0044-mechanism-findings-not-proposals.md §3). Since that
# task a mechanism-targeted turn files no proposal question at all, so
# `new_approval` — which gets its question from a real turn — can no
# longer build this fixture. The question is planted by hand instead,
# exactly as the "old approvals are inert" section above plants one and
# for the same reason: no supported writer produces one any more, and
# journals are append-only, so proposals of this shape sit in real
# journals, decided and undecided, and a resident who approves one
# tomorrow must still meet this refusal unchanged.
#
# The result underneath it is real — a turn, its diff, its `target:
# mechanism` and its byte-exact sidecar — because every check the
# applier runs before it reaches the target is a check about those.
REQ_M="$("$CASTLE" ask "APPLY-FIXTURE APPLYABLE-MECHANISM: an invented complaint whose fix is a one-line change.")"
"$CASTLE" work "$REQ_M" >/dev/null
R_M="$(basename "$(newest_result_for "$REQ_M")" .md)"
grep -q '^target: mechanism$' "$JOURNAL/$R_M.md" \
  || fail "the mechanism fixture did not stamp target: mechanism"
[ -f "$JOURNAL/$R_M.patch" ] || fail "the mechanism fixture kept no byte-exact copy of its diff"
[ -z "$(proposal_question_for "$REQ_M")" ] \
  || fail "a mechanism-targeted turn filed a proposal question the applier could never spend"
Q_M="20260201T000400Z-question-mechhistoric"
{
  echo "---"
  echo "id: $Q_M"
  echo "type: question"
  echo "provenance: requested"
  echo "refs: $REQ_M,$R_M"
  echo "seat: worker"
  echo "created: 2026-02-01T00:04:00Z"
  echo "proposal-sha256: $(sha256_of "$JOURNAL/$R_M.md")"
  echo "authorizes-apply: true"
  echo "---"
  echo
  echo "A change against the framework checkout, offered while such changes were"
  echo "still offered. Harness fixture only."
} > "$JOURNAL/$Q_M.md"
"$CASTLE" validate >/dev/null || fail "the planted mechanism proposal does not validate"
A_M="$("$CASTLE" answer --decision approve "$Q_M" </dev/null)"
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
# And the other end of the same turn: its diff was routed to the outbox
# rather than to the inbox, and refused there because THIS fixture's
# framework checkout deliberately has no `origin/main` to branch from.
# That is what keeps `assert_mechanism_untouched` above as strong as it
# has always been — this file's whole claim is that nothing in it ever
# writes the framework checkout, and the branch-cutting half of the
# routing is proved in test/agent-loop/approval.sh, which builds a
# fixture that can receive one.
OB_M="$(grep -l "^refs: $R_M\$" "$JOURNAL"/*-result-*.md 2>/dev/null | head -1 || true)"
[ -n "$OB_M" ] || fail "the mechanism-targeted diff reached no outbox record at all"
grep -q '^finding-outcome: refused-no-base$' "$OB_M" \
  || fail "the outbox did not refuse for want of a base: $(field_of "$OB_M" finding-outcome)"
grep -q 'MECHANISM-PLACEHOLDER-AFTER' "$OB_M" \
  || fail "the refused candidate was not preserved in the record: $(cat "$OB_M")"

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
log "refused: the kept copy is not a patch at all (a malformed patch is not a stale one)"
# ---------------------------------------------------------------------
# docs/tasks/0055-a-malformed-patch-is-not-a-stale-one.md: a turn that
# never produced anything git can read as a patch is a different fact
# from a turn whose good patch stopped fitting the tree. Confusing the
# two told a resident to go looking for a change in their own
# repository that never happened. Nothing here validates a tenant's
# diff before filing it as a proposal, so what the tenant wrote is kept
# byte-exact and is not a diff at all.
#
# **Getting one as far as the applier takes a machine that could not
# check it.** Since docs/tasks/0054-a-proposal-is-checked-before-it-is-
# offered.md, a patch git cannot parse is refused at filing time and
# never becomes a question — wherever git can be asked. The route that
# survives is the one 0054 built for a machine where it cannot:
# `offered-unchecked`, the question filed with nothing known either
# way. So this turn runs with a `git` that cannot be executed, and the
# apply runs with the ordinary PATH, where git works perfectly and
# reads the kept copy for the first time. (Before 0056 this scenario
# called `new_approval` on the ordinary PATH and had been failing on
# `main` since the two tasks merged: no question was filed, and every
# assertion below it went unrun.)
BROKEN_GIT_BIN="$WORKDIR/broken-git-bin"
mkdir -p "$BROKEN_GIT_BIN"
# On PATH, executable, and impossible to exec: the interpreter its
# shebang names does not exist, so the kernel refuses the exec and
# Python raises OSError. `shutil.which` finds it, which is the whole
# point — this is "git could not be run", not "git is not there", and
# the two are different conditions the applier must not confuse.
printf '#!%s/no-such-interpreter\n' "$WORKDIR" > "$BROKEN_GIT_BIN/git"
chmod +x "$BROKEN_GIT_BIN/git"
read -r REQ_MF R_MF Q_MF A_MF <<<"$(PATH="$BROKEN_GIT_BIN:$PATH" new_approval APPLYABLE-MALFORMED)"
grep -q '^proposal-outcome: offered-unchecked$' "$JOURNAL/$R_MF.md" \
  || fail "a turn that could not ask git about its patch did not offer it unchecked: $(field_of "$JOURNAL/$R_MF.md" proposal-outcome)"
"$CASTLE" apply "$A_MF" >/dev/null 2>&1 && fail "an unparseable patch was applied anyway"
AP_MF="$(newest_apply_result_for "$A_MF")"
grep -q '^apply-outcome: refused-patch-malformed$' "$AP_MF" \
  || fail "an unparseable patch was refused for the wrong reason: $(field_of "$AP_MF" apply-outcome)"
grep -q 'no longer fits your configuration repository' "$AP_MF" \
  && fail "the malformed-patch refusal claims the repository moved, which is the exact confusion this task removes: $(cat "$AP_MF")"
grep -qi 'No valid patches in input' "$AP_MF" \
  || fail "the refusal does not carry git's own account: $(cat "$AP_MF")"
assert_private_untouched "after the malformed-patch refusal"
assert_mechanism_untouched "after the malformed-patch refusal"

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
log "a repository that signs every commit: the failure mode is gone, not handled"
# ---------------------------------------------------------------------
# This section used to prove `applied-uncommitted` — the patch in the
# working tree with the commit refused — using a signing program that
# always fails. That state can no longer occur: the commit is built in
# a private index and the reference is moved in one guarded step, so
# there is no window in which the tree carries the change and the
# repository does not. `commit-tree` does not sign at all.
#
# The value stays in the vocabulary (the journal is append-only, and a
# validator must not condemn a record some writer of this code could
# have written) and nothing produces it. What is asserted here instead
# is that the configuration which used to break an apply now does not,
# and that the commit is NOT signed as the resident — the identity on it
# is the applier seat, and signing a seat's commit with a resident's key
# would assert authorship they do not have.
FAILING_SIGNER="$WORKDIR/failing-signer.sh"
cat > "$FAILING_SIGNER" <<'SIGNER'
#!/usr/bin/env bash
printf 'invented signing failure, harness fixture only\n' >&2
exit 1
SIGNER
chmod +x "$FAILING_SIGNER"
read -r REQ_SG R_SG Q_SG A_SG <<<"$(new_approval APPLYABLE-MODIFY-signing)"
git -C "$PRIVATE" config commit.gpgsign true
git -C "$PRIVATE" config gpg.program "$FAILING_SIGNER"
"$CASTLE" apply "$A_SG" >/dev/null \
  || fail "an apply into a repository that signs every commit failed"
git -C "$PRIVATE" config --unset commit.gpgsign
git -C "$PRIVATE" config --unset gpg.program
AP_SG="$(newest_apply_result_for "$A_SG")"
grep -q '^apply-outcome: applied-unvalidated$' "$AP_SG" \
  || fail "the signing-repository apply has the wrong outcome: $(field_of "$AP_SG" apply-outcome)"
grep -q '^apply-commit:' "$AP_SG" || fail "the signing-repository apply stamped no commit"
assert_private_changed_exactly "a repository that signs every commit" "$A_SG" resident.nix
log "  -- and the commit is not signed, because it is the applier's and not the resident's"
[ "$(git -C "$PRIVATE" show -s --format=%G? HEAD)" = "N" ] \
  || fail "the applier's commit carries a signature: $(git -C "$PRIVATE" show -s --format=%G? HEAD)"
assert_mechanism_untouched "after the signing-repository scenario"

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
# And no commit field either: there is no commit to name, and a field
# naming one would be the machine-readable half of the same overclaim.
grep -q '^apply-commit:' "$AP_EF" \
  && fail "an attempt that made no commit stamped one anyway: $(field_of "$AP_EF" apply-commit)"
grep -q 'castle.agent.repo.private' "$AP_EF" \
  || fail "the environment fault does not name the option that fixes it: $(cat "$AP_EF")"
# The real green control for the validator's cross-record rule below:
# this record is `seat: applier` with no `apply-outcome`, which is
# exactly the shape that rule now covers, and it is legitimate — its
# first ref resolves to the answer that approved the change. A rule that
# condemned it would condemn every environment fault this task records.
"$CASTLE" validate >/dev/null \
  || fail "a legitimate no-conclusion apply record does not validate: $(cat "$AP_EF")"
assert_private_untouched "after the environment fault"
assert_mechanism_untouched "after the environment fault"

log "  -- and it bars the approval from the sweep, so the surface must NAME the way back"
# The failure the review found: this record carries no `apply-outcome`,
# so the status fold's fourth stage did not recognise it — while its
# refs bar the answer from `_eligible_approvals` forever. The errand
# read "approved — waiting to be applied" permanently, for something
# that would never run, with the remedy named nowhere. Asserted on the
# surface a resident actually reads, not on field absence.
FILES_BEFORE="$(journal_file_count)"
"$CASTLE" apply --sweep > "$WORKDIR/envfault-sweep.txt"
grep -q 'nothing eligible' "$WORKDIR/envfault-sweep.txt" \
  || fail "a burnt approval is still eligible for an automatic apply: $(cat "$WORKDIR/envfault-sweep.txt")"
[ "$(journal_file_count)" = "$FILES_BEFORE" ] || fail "the sweep wrote a record for a burnt approval"
STATUS_EF="$("$MODAL" --mode status --limit 40)"
printf '%s\n' "$STATUS_EF" | grep -F "$REQ_EF" | grep -q "could not be applied — castle apply $A_EF to try again" \
  || fail "an errand whose apply failed before reaching a conclusion does not name the way back: $(printf '%s\n' "$STATUS_EF" | grep -F "$REQ_EF")"
printf '%s\n' "$STATUS_EF" | grep -F "$REQ_EF" | grep -q 'waiting to be applied' \
  && fail "an errand that will never be applied automatically still reads as waiting for it"

log "  -- and running the command that label names actually works"
# The other half, and the reason the label is worth printing at all
# (docs/tasks/0015: a label must not cause the inaction it describes).
# The environment is repaired — the root points at the checkout again —
# and the remedy the surface named is executed verbatim.
#
# A whole second first, for the reason approval.sh's own retry case
# spells out: record ids are chronological only to one second, so two
# apply records for one approval written inside the same second sort by
# their random suffix and the surface can describe the older one. That
# limit is `docs/tasks/0046-record-ordering-helper.md`'s and
# is inherited rather than worked around here — the harness separates
# them the way a resident's hands would.
sleep 1
"$CASTLE" apply "$A_EF" >/dev/null || fail "the hand retry the status surface names did not work"
assert_private_changed_exactly "the remedy the status surface named" "$A_EF" resident.nix
STATUS_EF_AFTER="$("$MODAL" --mode status --limit 40)"
printf '%s\n' "$STATUS_EF_AFTER" | grep -F "$REQ_EF" | grep -q 'applied, not checked — not activated' \
  || fail "the errand does not read as applied after the remedy: $(printf '%s\n' "$STATUS_EF_AFTER" | grep -F "$REQ_EF")"
assert_mechanism_untouched "after the environment-fault remedy"
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
#
# Not `kill -0`: a zombie's pid is still visible to it — the process
# table entry survives until its parent reaps it — so `kill -0` alone
# cannot tell "already killed, not yet reaped" from "still running".
# Reproduced in CI: the killed `sleep` stayed `<defunct>` long enough
# for `kill -0` to see it and fail the assertion (Codex review on this
# PR). `/proc/<pid>/stat`'s state field says which: `Z` (or the file
# being gone once something does reap it) means it already died.
builder_stat_state() {
  local pid="$1" stat
  stat="$(cat "/proc/$pid/stat" 2>/dev/null)" || { printf 'gone'; return; }
  # Field 3 is the state letter. Field 2 is "(comm)", and a command
  # name can itself contain spaces or parentheses, so split on the
  # LAST ")" rather than by naive whitespace splitting.
  stat="${stat##*) }"
  printf '%s' "${stat%% *}"
}
BUILDER_STATE="$(builder_stat_state "$BUILDER_PID")"
[ "$BUILDER_STATE" = "gone" ] || [ "$BUILDER_STATE" = "Z" ] \
  || fail "the check's own child survived the timeout — only the parent was killed (state: $BUILDER_STATE)"
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
expect_invalid "an apply naming no approval" "must spend a real authorization"

log "  -- a commit id that is not one, on a record that claims to name a commit"
plant_base
plant 20260201T000004Z-result-eeeeee result \
  "20260201T000003Z-answer-dddddd,20260201T000002Z-question-cccccc" \
  "outcome: completed" "apply-outcome: applied-validated" "apply-commit: NOTASHA"
expect_invalid "a malformed commit id" "40 or 64 lowercase hex"

log "  -- and the control: a sha256-format commit id is accepted, because git really has those"
# Hard-coding forty would have been a latent lie — `git init
# --object-format=sha256` is real, and a resident's own repository is
# theirs to create however they like.
plant_base
plant 20260201T000004Z-result-eeeeee result \
  "20260201T000003Z-answer-dddddd,20260201T000002Z-question-cccccc" \
  "outcome: completed" "apply-outcome: applied-validated" \
  "apply-commit: $(printf 'an invented sha256-shaped commit id' | sha256sum | cut -d' ' -f1)"
expect_valid "a sha256-format commit id"

log "  -- a commit id on a record that reads it nowhere"
plant_base
plant 20260201T000004Z-question-ffffff question 20260201T000000Z-request-aaaaaa \
  "proposal-sha256: $VALID_HASH" "apply-commit: $VALID_HASH"
expect_invalid "a commit id on a question" "'apply-commit' is a result-record field"

log "  -- an applier-seat result with NO apply-outcome, naming something that is not an answer"
# The shape this batch introduced and the validator did not learn: an
# apply that reached no conclusion about the change writes `seat:
# applier` with `outcome: failed` and no `apply-outcome` at all. Gated
# on the field alone, this passed clean — while `_eligible_approvals`
# still counted it as having spent whatever answer it names, and the
# status fold still recognised it by seat. Reproduced through `castle
# record` before it was fixed, so this is a shape the record door
# really does let through, not only a hand-edited file.
plant_base
plant 20260201T000004Z-result-eeeeee result 20260201T000001Z-result-bbbbbb \
  "outcome: failed"
sed -i 's/^seat: intake$/seat: applier/' "$PLANT/20260201T000004Z-result-eeeeee.md"
expect_invalid "a no-conclusion applier result naming a result" "must spend a real authorization"

log "  -- and one naming nothing at all"
plant_base
plant 20260201T000004Z-result-eeeeee result "" "outcome: failed"
sed -i 's/^seat: intake$/seat: applier/' "$PLANT/20260201T000004Z-result-eeeeee.md"
expect_invalid "a no-conclusion applier result naming nothing" "must spend a real authorization"

log "  -- the green control: a LEGITIMATE no-conclusion result still validates clean"
# Without this, the two cases above are satisfied by a check that
# condemns every applier record that did not reach a conclusion —
# which is every environment fault this task deliberately records.
plant_base
plant 20260201T000004Z-result-eeeeee result \
  "20260201T000003Z-answer-dddddd,20260201T000002Z-question-cccccc" \
  "outcome: failed"
sed -i 's/^seat: intake$/seat: applier/' "$PLANT/20260201T000004Z-result-eeeeee.md"
expect_valid "a legitimate no-conclusion applier result"

log "  -- and one naming an answer that did not approve"
plant_base
plant 20260201T000004Z-answer-eeeeee answer \
  "20260201T000002Z-question-cccccc,20260201T000001Z-result-bbbbbb" \
  "decision: reject" "proposal-sha256: $VALID_HASH"
plant 20260201T000005Z-result-ffffff result \
  "20260201T000004Z-answer-eeeeee,20260201T000002Z-question-cccccc" \
  "outcome: completed" "apply-outcome: applied-validated"
expect_invalid "an apply on a rejection" "must spend a real authorization"

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
