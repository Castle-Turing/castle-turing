#!/usr/bin/env bash
# test/agent-loop/config-target.sh — the worker seat's two checkouts
# (docs/tasks/0024-config-target.md §19).
#
# Same shape and same conventions as dispatch-test.sh and resume.sh:
# plain bash and stdlib python3, no Nix, zero models, zero network, a
# throwaway state dir and runtime dir, the same notify stub. Everything
# goes through `castle work` or `castle dispatch` rather than `castle
# record` assembling a scenario by hand — the target file, the two
# roots, the pre-flight and the mechanism three-state all live inside
# `run_worker_turn`, and those two entry points are the only things
# that reach it.
#
# What is new here is the fixture's *shape*: two real git checkouts
# under $WORKDIR, one standing in for a resident's private
# configuration repository and one for a checkout of this framework, so
# the assertions about which repo a diff targets are made against two
# directories that genuinely both exist and genuinely both contain a
# flake.nix. Nothing in here is a real path, a real complaint or a real
# answer: every string is invented or reuses a placeholder this repo
# already publishes.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CASTLE="$REPO_ROOT/agent/castle"
MODAL="$REPO_ROOT/agent/castle-modal"
WORKER="$REPO_ROOT/test/agent-loop/scripted-worker-config-target.sh"
BYTE_WORKER="$REPO_ROOT/test/agent-loop/scripted-worker-byte-fidelity.sh"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/castle-config-target.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

log() { printf '>>> %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Committing needs an identity, and a developer's own git config must
# not decide whether this test passes. Scoped to this process only.
export GIT_AUTHOR_NAME="castle-config-target-fixture"
export GIT_AUTHOR_EMAIL="fixture@example.invalid"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
# The identity vars above are not the only thing a developer's git
# config can decide. Reproduced: `apply.whitespace = error` in
# ~/.gitconfig makes `git apply --check` of the CRLF byte-fidelity
# sidecar exit 128 ("blank-at-eol") — a false FAIL, not the real
# assertion; `core.autocrlf = true` makes the body-copy apply write
# CRLF too, so the CRLF-loss contrast this fixture exists to prove
# stops being observable — also a false FAIL. Every git call in this
# file inherits these two, closing the gap for good rather than only
# for the sites that happened to be new when this was noticed
# (code review finding on this task).
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

# ---------------------------------------------------------------------
log "building the two checkouts"
# ---------------------------------------------------------------------
# The mechanism checkout is this repository's own tracked content at
# HEAD, exported with `git archive` rather than copied with `cp -r`.
# The difference matters twice: `git archive` takes only what is
# committed, so no untracked scratch file and no ignored build output
# from the developer's live worktree can leak into a fixture, and what
# the fixture then contains is the real, current module surface a
# tenant would read — not a synthetic stand-in free to drift from what
# modules/desktop actually declares.
MECHANISM="$WORKDIR/mechanism"
mkdir -p "$MECHANISM"
git -C "$REPO_ROOT" archive HEAD | tar -x -C "$MECHANISM"
git -C "$MECHANISM" init -q
git -C "$MECHANISM" add -A
git -C "$MECHANISM" commit -q -m "fixture: this framework at HEAD"

# The private checkout is synthetic, and every literal in it is one
# this repo already publishes: nixosConfigurations.example's "resident"
# admin username and its placeholder key string, and the
# /home/resident/private-state state-directory shape, which is
# docs/private-layer.md's own recommended layout written with the
# placeholder resident this repo already publishes. Nothing here
# resembles a real one.
PRIVATE="$WORKDIR/private"
mkdir -p "$PRIVATE"
cat > "$PRIVATE/flake.nix" <<'EOF'
# Synthetic private flake, harness fixture only.
{
  inputs.castle-turing.url = "github:Castle-Turing/castle-turing";
  outputs = { self, castle-turing, ... }: {
    nixosConfigurations.example-private = castle-turing.lib.placeholder;
  };
}
EOF
# cursorTheme set and cursorSize deliberately left unset. That pairing
# is load-bearing rather than decorative (docs/tasks/0024 §14):
# cursorSize is inert unless a theme is configured somewhere in the
# stack, so a cursor acceptance case built on a checkout with no theme
# would pass while proposing a silent no-op — green for the wrong
# reason, proving nothing about the mechanism under test.
cat > "$PRIVATE/resident.nix" <<'EOF'
# Synthetic private layer, harness fixture only.
{
  castle.admin.username = "resident";
  castle.admin.sshKeys = [
    "ssh-ed25519 REPLACE-WITH-YOUR-PUBLIC-KEY this-is-a-placeholder-not-a-key"
  ];
  castle.agent.stateDir = "/home/resident/private-state";
  castle.display = {
    cursorTheme = "Example-Cursors";
  };
}
EOF
git -C "$PRIVATE" init -q
git -C "$PRIVATE" add -A
git -C "$PRIVATE" commit -q -m "fixture: a synthetic private layer"

# A second private checkout differing in exactly one thing: no
# cursorTheme. The sibling-coupling assertion below needs a checkout
# where the naive one-option proposal WOULD be inert, and mutating the
# first one mid-run would dirty the working tree the no-mutation proof
# depends on.
PRIVATE_NOTHEME="$WORKDIR/private-notheme"
mkdir -p "$PRIVATE_NOTHEME"
cp "$PRIVATE/flake.nix" "$PRIVATE_NOTHEME/flake.nix"
cat > "$PRIVATE_NOTHEME/resident.nix" <<'EOF'
# Synthetic private layer with no cursor theme, harness fixture only.
{
  castle.admin.username = "resident";
  castle.display = { };
}
EOF
git -C "$PRIVATE_NOTHEME" init -q
git -C "$PRIVATE_NOTHEME" add -A
git -C "$PRIVATE_NOTHEME" commit -q -m "fixture: a private layer with no cursor theme"

# A directory that exists and is not a git working tree. Two
# assertions use it, from opposite directions: as a private root it
# must refuse the turn, and as a mechanism root it must not.
NOT_A_CHECKOUT="$WORKDIR/not-a-checkout"
mkdir -p "$NOT_A_CHECKOUT"

PRIVATE_HEAD="$(git -C "$PRIVATE" rev-parse HEAD)"
MECHANISM_HEAD="$(git -C "$MECHANISM" rev-parse HEAD)"

# The documented relationship made real rather than merely asserted in
# prose (docs/private-layer.md's "The agent's state"): the journal is
# git-tracked and durable, and it lives in a repository *beside* the
# private flake checkout rather than inside it. That sibling placement
# is not decoration here — a state directory inside $PRIVATE would sit
# in the tracked tree of a repo carrying a flake.nix, which is exactly
# what `castle validate` and `castle digest` now warn about
# (docs/tasks/0030-state-outside-the-flake.md), and this fixture would
# then spend its CI run demonstrating the layout the docs tell a
# resident not to use.
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
export CASTLE_TEST_CASTLE_BIN="$CASTLE"
export CASTLE_PRIVATE_ROOT="$PRIVATE"

records_of_type() { find "$JOURNAL" -name "*-$1-*.md" 2>/dev/null || true; }
referencing() {
  local rtype="$1" id="$2"
  grep -l "^refs: .*$id" "$JOURNAL"/*-"$rtype"-*.md 2>/dev/null || true
}
count_referencing() { referencing "$1" "$2" | grep -c . || true; }
# The newest result for an errand, by MTIME and not by filename.
# Record ids carry a one-second timestamp and a random hex suffix, so
# two results written inside the same second sort by that suffix —
# which is to say, by chance. Every call site but one has a single
# result and would never notice; the ask-first case deliberately
# produces two and then asserts on the second, so a fast machine could
# make it read the first and fail for a reason that has nothing to do
# with the code. This repo has been bitten by one-second id
# granularity before, so the fix is to stop asking filenames a
# question they cannot answer.
#
# `%.Y` and not `%Y`: whole-second mtimes reproduce the very problem
# being fixed, since two records written in the same second tie and
# fall back to filename order again. Checked rather than assumed — with
# `%Y` this helper still picked the wrong file out of a same-second
# pair; with nanoseconds it picks the one actually written last. Tab
# separator so the filename is untouched by the split.
newest_result_for() {
  local id="$1"
  referencing result "$id" \
    | xargs -r stat -c '%.Y	%n' 2>/dev/null \
    | sort -k1,1n \
    | tail -1 \
    | cut -f2-
}
blocking_question_for() {
  local request_id="$1" path
  path="$(grep -l "^refs: .*$request_id" "$JOURNAL"/*-question-*.md 2>/dev/null \
    | xargs -r grep -l '^blocking: true$' | head -1 || true)"
  [ -n "$path" ] || return 0
  basename "$path" .md
}
# Both checkouts, every time. This is S3's teeth: the worker proposes
# and never deploys, and the only way a harness can say that about a
# fixture rather than about a comment is to check that nothing moved.
# Neither half carries an exclusion. An earlier version of this
# function excluded `state/` from the private checkout, because the
# journal lived inside it and `castle` writing a record there was the
# system working rather than a worker mutating a checkout. Moving the
# journal to a sibling repository (see CASTLE_STATE_DIR above) retires
# that exclusion and strengthens the assertion: nothing whatsoever
# legitimately writes inside either checkout now, so any change at all
# is a failure.
# Extracts the diff a record's body renders, using the SAME logic a
# real reader uses rather than a second, hand-rolled re-implementation
# of it: agent/castle-modal's own `_split_proposal_body`, imported and
# called directly (docs/tasks/0033-byte-exact-proposal.md's
# verification plan). This is deliberately how a resident's own review
# screen sees the diff, splitlines()-round-trip and all — the exact
# transform this task's sidecar exists to route around.
extract_record_diff() {
  local record="$1" out="$2"
  python3 - "$CASTLE" "$MODAL" "$record" "$out" <<'EXTRACT'
import importlib.machinery, importlib.util, pathlib, sys

def load_module(path, name):
    loader = importlib.machinery.SourceFileLoader(name, path)
    spec = importlib.util.spec_from_file_location(name, path, loader=loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module

castle_path, modal_path, record_path, out_path = sys.argv[1:5]
castle = load_module(castle_path, "castle_lib_bf")
modal = load_module(modal_path, "castle_modal_lib_bf")

rec = castle.parse_record(pathlib.Path(record_path))
_where, _diagnosis, diff = modal._split_proposal_body(castle, rec)
with open(out_path, "wb") as f:
    f.write(diff.encode("utf-8"))
EXTRACT
}

assert_checkouts_untouched() {
  local where="$1"
  [ -z "$(git -C "$PRIVATE" status --porcelain)" ] \
    || fail "$where: the private checkout was MUTATED — $(git -C "$PRIVATE" status --porcelain)"
  [ -z "$(git -C "$MECHANISM" status --porcelain)" ] \
    || fail "$where: the mechanism checkout was MUTATED — $(git -C "$MECHANISM" status --porcelain)"
  [ "$(git -C "$PRIVATE" rev-parse HEAD)" = "$PRIVATE_HEAD" ] \
    || fail "$where: the private checkout's HEAD moved"
  [ "$(git -C "$MECHANISM" rev-parse HEAD)" = "$MECHANISM_HEAD" ] \
    || fail "$where: the mechanism checkout's HEAD moved"
}

"$CASTLE" dispatch --watermark-only >/dev/null
"$CASTLE" validate >/dev/null

# ---------------------------------------------------------------------
log "a private-layer errand: the diff lands, the target is stamped, the body names the resolved path"
# ---------------------------------------------------------------------
REQ1="$("$CASTLE" ask "CONFIG-TARGET-FIXTURE-CURSOR: an invented complaint about a pointer being hard to see.")"
log "  -> $REQ1"
"$CASTLE" dispatch >/dev/null
R1="$(newest_result_for "$REQ1")"
[ -n "$R1" ] || fail "the sweep wrote no result for $REQ1"
grep -q '^outcome: completed$' "$R1" || fail "$REQ1 did not complete: $(grep '^outcome:' "$R1")"

log "  -- assertion 1: the diff is in the body, and the prose beside it names the resolved path"
grep -q '^+    cursorSize = 32;$' "$R1" || fail "the tenant's diff is not embedded in the result body"
grep -qF "This diff targets the **private** checkout, which on this host resolved to \`$PRIVATE\`." "$R1" \
  || fail "the result body does not name the resolved private path beside the diff: $(grep -n 'targets' "$R1")"

log "  -- assertion 2: the result carries target: private"
grep -q '^target: private$' "$R1" || fail "$R1 carries no 'target: private' field"

log "  -- assertion 3: neither checkout was touched"
assert_checkouts_untouched "after the first errand"

log "  -- assertion 4: castle validate passes over the journal"
"$CASTLE" validate >/dev/null || fail "the journal does not validate after the first errand"

log "  -- and neither the mechanism-unusable note nor either target-mismatch note appears"
grep -q 'castle.agent.repo.mechanism` is configured' "$R1" \
  && fail "a result carried the mechanism-unusable note on a host with no mechanism root configured"
grep -q 'declared no target' "$R1" \
  && fail "a turn that stamped a target was told it had not"
grep -q 'it has been discarded rather than recorded' "$R1" \
  && fail "a turn that produced a diff was told its target was discarded"

# ---------------------------------------------------------------------
log "assertion 7: the sibling-option coupling rule — cursorSize alone would be a silent no-op"
# ---------------------------------------------------------------------
# Same errand text, run against the checkout whose resident.nix sets no
# cursorTheme. The proposal must either refuse or carry the sibling;
# what it must never do is propose the inert half on its own.
REQ_NT="$("$CASTLE" ask "CONFIG-TARGET-FIXTURE-CURSOR: the same invented complaint, on a checkout with no cursor theme.")"
CASTLE_PRIVATE_ROOT="$PRIVATE_NOTHEME" "$CASTLE" work "$REQ_NT" >/dev/null
R_NT="$(newest_result_for "$REQ_NT")"
grep -q '^outcome: completed$' "$R_NT" || fail "$REQ_NT did not complete"
if grep -q '^+    cursorSize' "$R_NT"; then
  grep -q '^+    cursorTheme' "$R_NT" \
    || fail "a diff touching cursorSize on a theme-less checkout omitted the sibling cursorTheme — that proposal is a silent no-op"
fi
"$CASTLE" validate >/dev/null

# ---------------------------------------------------------------------
log "assertion 5: with no private root configured at all, the turn refuses"
# ---------------------------------------------------------------------
REQ_NOROOT="$("$CASTLE" ask "CONFIG-TARGET-FIXTURE-CURSOR: an invented complaint filed on a host with nothing configured.")"
if env -u CASTLE_PRIVATE_ROOT "$CASTLE" work "$REQ_NOROOT" >"$WORKDIR/noroot.out" 2>"$WORKDIR/noroot.err"; then
  fail "castle work exited 0 with no private checkout configured"
fi
R_NOROOT="$(newest_result_for "$REQ_NOROOT")"
[ -n "$R_NOROOT" ] || fail "the refused turn wrote no result at all — that leaves a dangling claim for the reaper"
grep -q '^outcome: failed$' "$R_NOROOT" || fail "the refused turn did not record outcome: failed"
grep -q 'castle.agent.repo.private' "$R_NOROOT" \
  || fail "the refused turn's result does not name the option that is missing"
grep -q '^target:' "$R_NOROOT" \
  && fail "a turn that never ran a tenant stamped a target anyway"
# The claim exists and the result names it: a refusal that skipped
# either would be reaped into a false `interrupted` by the next sweep.
[ "$(count_referencing claim "$REQ_NOROOT")" -eq 1 ] || fail "the refused turn left no claim"
"$CASTLE" validate >/dev/null

# ---------------------------------------------------------------------
log "assertion 6: a private root that exists but is not a git working tree refuses the same way"
# ---------------------------------------------------------------------
REQ_NOTREPO="$("$CASTLE" ask "CONFIG-TARGET-FIXTURE-CURSOR: an invented complaint filed against a directory that is not a checkout.")"
if CASTLE_PRIVATE_ROOT="$NOT_A_CHECKOUT" "$CASTLE" work "$REQ_NOTREPO" >/dev/null 2>&1; then
  fail "castle work exited 0 with a private root that is not a git working tree"
fi
R_NOTREPO="$(newest_result_for "$REQ_NOTREPO")"
grep -q '^outcome: failed$' "$R_NOTREPO" || fail "the unusable-root turn did not record outcome: failed"
grep -qF "$NOT_A_CHECKOUT" "$R_NOTREPO" || fail "the unusable-root turn's result does not name the path it was given"
# Either wording is correct and which one appears is a property of the
# host, not of the code under test: with git reachable the pre-flight
# asks git and quotes it, and without git it falls back to the `.git`
# existence test and says so. Asserting one spelling would make this
# harness pass or fail on whether modules/dev happened to be installed.
# The git-reachable wording, asserted directly rather than as one arm
# of an alternation. This harness builds its fixtures with `git init`
# and `git archive` before it does anything else, so git is a hard
# prerequisite of running it at all and the pre-flight is always in
# its git-reachable mode here — an assertion tolerating the no-git
# wording would be a branch that can never execute.
#
# Worth recording that the tolerant version was tried first and had a
# real bug in exactly that unreachable arm: `has no .git. entry`, one
# wildcard short of the backtick-dot pair the message contains. It
# could never have matched, and nothing noticed, because it never ran.
# The no-git fallback is verified directly against `_checkout_fault`
# instead, where it can actually be reached.
grep -q 'cannot use it as a working tree' "$R_NOTREPO" \
  || fail "the unusable-root turn's result does not say what was wrong with the path: $(grep -n 'could not start' "$R_NOTREPO")"
"$CASTLE" validate >/dev/null
assert_checkouts_untouched "after the two refusals"

# ---------------------------------------------------------------------
log "a checkout git cannot actually use is refused, not merely one with no .git"
# ---------------------------------------------------------------------
# The `.git` existence test this pre-flight used to stop at answers a
# weaker question than the refusal message claimed: an empty `.git`
# directory and a linked-worktree `.git` file whose target is gone
# both satisfy it, and git can do nothing with either. A pre-flight
# that exists to fail before a model call is spent must not pass those
# through to spend one (Codex review, P2).
#
# Not guarded on git being present, because this harness cannot run
# without it: the fixtures at the top are built with `git init` and
# `git archive`. On a host with no git the pre-flight degrades to the
# old existence test and these three cases legitimately pass — that is
# the documented fallback, and refusing there would break work that
# can still succeed. The block after these four covers that fallback
# for real, in-process.
EMPTY_GIT="$WORKDIR/empty-git"
mkdir -p "$EMPTY_GIT/.git"
REQ_EMPTYGIT="$("$CASTLE" ask "CONFIG-TARGET-FIXTURE-CURSOR: an invented complaint against a directory with an empty .git.")"
if CASTLE_PRIVATE_ROOT="$EMPTY_GIT" "$CASTLE" work "$REQ_EMPTYGIT" >/dev/null 2>&1; then
  fail "castle work accepted a private root whose .git is an empty directory — git cannot use it, and a model call was spent finding that out"
fi
R_EMPTYGIT="$(newest_result_for "$REQ_EMPTYGIT")"
grep -q '^outcome: failed$' "$R_EMPTYGIT" || fail "the empty-.git turn did not record outcome: failed"
grep -q 'cannot use it as a working tree' "$R_EMPTYGIT" \
  || fail "the empty-.git refusal does not say git is what could not use the path"

BROKEN_LINK="$WORKDIR/broken-worktree-link"
mkdir -p "$BROKEN_LINK"
# The shape a linked worktree or a submodule really has — a `.git`
# FILE pointing elsewhere — with its target removed. `.exists()` on
# `.git` is true here, which is exactly why that test was too weak.
printf 'gitdir: %s/nowhere-at-all\n' "$WORKDIR" > "$BROKEN_LINK/.git"
REQ_BROKENLINK="$("$CASTLE" ask "CONFIG-TARGET-FIXTURE-CURSOR: an invented complaint against a dangling worktree link.")"
if CASTLE_PRIVATE_ROOT="$BROKEN_LINK" "$CASTLE" work "$REQ_BROKENLINK" >/dev/null 2>&1; then
  fail "castle work accepted a private root whose .git file points nowhere"
fi
R_BROKENLINK="$(newest_result_for "$REQ_BROKENLINK")"
grep -q 'cannot use it as a working tree' "$R_BROKENLINK" \
  || fail "the dangling-worktree-link refusal does not say git is what could not use the path"

log "  -- and a SUBDIRECTORY of a real checkout is refused, naming the root it found"
# Nobody asked for this one, and it is the quietest of the four. A
# subdirectory passes every filesystem test and passes git's own
# exit status too; only the toplevel it reports gives it away. A
# diff produced there carries paths relative to a root the applier
# will not use — a well-formed, unapplyable proposal that nothing
# downstream could detect.
REQ_SUBDIR="$("$CASTLE" ask "CONFIG-TARGET-FIXTURE-CURSOR: an invented complaint against a subdirectory of a checkout.")"
mkdir -p "$PRIVATE/state/journal"
if CASTLE_PRIVATE_ROOT="$PRIVATE/state" "$CASTLE" work "$REQ_SUBDIR" >/dev/null 2>&1; then
  fail "castle work accepted a subdirectory of a checkout as the private root — a diff written there would be relative to the wrong root"
fi
R_SUBDIR="$(newest_result_for "$REQ_SUBDIR")"
grep -q '^outcome: failed$' "$R_SUBDIR" || fail "the subdirectory turn did not record outcome: failed"
grep -qF "it is inside the working tree rooted at \`$PRIVATE\`" "$R_SUBDIR" \
  || fail "the subdirectory refusal does not name the working tree it actually found: $(grep -n 'could not start' "$R_SUBDIR")"
grep -q 'relative to the wrong root' "$R_SUBDIR" \
  || fail "the subdirectory refusal does not say what would go wrong"

log "  -- while the real checkout, the root of a working tree, still passes"
# The control. Without it the three refusals above are satisfied by a
# pre-flight that refuses everything.
REQ_STILLOK="$("$CASTLE" ask "CONFIG-TARGET-FIXTURE-CURSOR: an invented complaint against the real checkout, which must still work.")"
"$CASTLE" work "$REQ_STILLOK" >/dev/null
R_STILLOK="$(newest_result_for "$REQ_STILLOK")"
grep -q '^outcome: completed$' "$R_STILLOK" \
  || fail "the stronger checkout probe now refuses a perfectly good checkout"
grep -q '^target: private$' "$R_STILLOK" || fail "the control turn produced no target"
"$CASTLE" validate >/dev/null
assert_checkouts_untouched "after the checkout-probe cases"

# ---------------------------------------------------------------------
log "the no-git fallback: degrade to the .git test, and say only what was checked"
# ---------------------------------------------------------------------
# This path cannot be reached through `castle work` from here — the
# harness itself needs git, so a run without it never gets this far —
# and for a while these lines were a COMMENT claiming it was "verified
# directly against _checkout_fault" when nothing verified it at all.
# That is worse than no comment: it tells the next reader not to
# bother, which is exactly how the dead assertion earlier in this same
# branch survived. So the claim is now the test.
#
# In-process, importing agent/castle the way castle-modal already does
# (its `_load_castle_module`), because the branch is selected by
# `shutil.which("git")` and the only honest way to reach it is to make
# that return None. `python3` bare, matching resume.sh's own snippets.
(
python3 - "$CASTLE" "$WORKDIR" <<'NOGIT'
import importlib.machinery, importlib.util, pathlib, sys

castle_path, workdir = sys.argv[1], sys.argv[2]
loader = importlib.machinery.SourceFileLoader("castle_lib", castle_path)
spec = importlib.util.spec_from_file_location("castle_lib", castle_path, loader=loader)
castle = importlib.util.module_from_spec(spec)
loader.exec_module(castle)

failures = []

def check(label, path, want_fault, needle=None):
    got = castle._checkout_fault(path)
    if want_fault and got is None:
        failures.append(f"{label}: expected a refusal, got none")
    elif not want_fault and got is not None:
        failures.append(f"{label}: expected no fault, got {got!r}")
    elif needle and got is not None and needle not in got:
        failures.append(f"{label}: refusal does not say {needle!r}: {got!r}")

# With git reachable, an empty .git is refused — the whole point of the
# probe, and the control proving the stub below really changes things.
check("git present, empty .git", f"{workdir}/empty-git", True, "cannot use it as a working tree")

castle.shutil.which = lambda _name: None   # a host with no git at all

check("no git, real checkout", f"{workdir}/private", False)
check("no git, empty .git dir", f"{workdir}/empty-git", False)
check("no git, dangling link", f"{workdir}/broken-worktree-link", False)
# Refused, but by the weaker route and for the weaker reason: with no
# git there is no way to learn that this is INSIDE a checkout, only
# that it is not the root of one. The decision lands in the right
# place; the explanation is honestly smaller.
check("no git, subdirectory", f"{workdir}/private/state", True, "has no `.git` entry")
check("no git, plain directory", f"{workdir}/not-a-checkout", True, "has no `.git` entry")
check("no git, missing path", f"{workdir}/nowhere-at-all", True, "does not exist")
check("no git, relative path", "private", True, "not absolute")

# The wording half: a check that never ran must not claim it did.
fault = castle._checkout_fault(f"{workdir}/not-a-checkout")
if "nothing stronger than that was checked" not in fault:
    failures.append(f"the no-git refusal claims more than it verified: {fault!r}")
if "working tree" in fault:
    failures.append(f"the no-git refusal asserts a git-verified fact no git verified: {fault!r}")

if failures:
    for f in failures:
        print(f"  {f}", file=sys.stderr)
    sys.exit(1)
print("  no-git fallback: 9 cases, wording included")
NOGIT
) || fail "the no-git fallback does not behave as documented"

# ---------------------------------------------------------------------
log "a RELATIVE private root refuses too, and never resolves against the caller's cwd"
# ---------------------------------------------------------------------
# modules/agent asserts absoluteness at evaluation time, which covers a
# value arriving through Nix and nothing else — while the documented
# non-Nix route is this variable, set directly, which is how every
# harness in this directory does it. Run from inside $WORKDIR, where
# `private` really would resolve to the valid checkout, so this fails
# if the check ever weakens to "does it exist."
REQ_REL="$("$CASTLE" ask "CONFIG-TARGET-FIXTURE-CURSOR: an invented complaint filed against a relative path.")"
if (cd "$WORKDIR" && CASTLE_PRIVATE_ROOT="private" "$CASTLE" work "$REQ_REL" >/dev/null 2>&1); then
  fail "castle work accepted a relative private root, resolving it against its own working directory"
fi
R_REL="$(newest_result_for "$REQ_REL")"
grep -q '^outcome: failed$' "$R_REL" || fail "the relative-root turn did not record outcome: failed"
grep -q 'the path is not absolute' "$R_REL" \
  || fail "the relative-root turn's result does not say what was wrong with the path"
"$CASTLE" validate >/dev/null

# ---------------------------------------------------------------------
log "a target stamped with no diff is discarded, not recorded"
# ---------------------------------------------------------------------
# `target` means "the checkout this diff applies to". With no diff
# there is nothing for it to be about, and a record carrying one reads
# to docs/tasks/0025 and 0026 as an applicable proposal with nothing to
# apply. Discarded visibly rather than silently, so a tenant that
# misunderstood the contract leaves a trace.
STAMP_ONLY="$WORKDIR/stamp-only-tenant.sh"
cat > "$STAMP_ONLY" <<'TENANT'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
printf 'stamp-only tenant: a target with nothing to target\n'
printf 'private\n' > "$CASTLE_TARGET_FILE"
TENANT
chmod +x "$STAMP_ONLY"
REQ_STAMP="$("$CASTLE" ask "An invented errand whose tenant stamps a target and writes no diff.")"
CASTLE_WORKER_COMMAND="$STAMP_ONLY" "$CASTLE" work "$REQ_STAMP" >/dev/null
R_STAMP="$(newest_result_for "$REQ_STAMP")"
grep -q '^outcome: completed$' "$R_STAMP" || fail "the stamp-only turn did not complete"
grep -q '^target:' "$R_STAMP" \
  && fail "a result with no diff carries a target field — that reads as a proposal with nothing to apply"
grep -q 'it has been discarded rather than recorded' "$R_STAMP" \
  || fail "the discarded target was swallowed silently instead of being named in the body"
"$CASTLE" validate >/dev/null

# ---------------------------------------------------------------------
log "a diff with no target says so — the mirror, and the one that matters more"
# ---------------------------------------------------------------------
# A stamp with no diff is incoherent but inert. A diff with no target
# is a real, applyable artifact whose destination is missing, and
# docs/tasks/0025 and 0026 both read that field to decide which
# checkout a proposal goes to. A note rather than a failure: the turn
# did the work, the diff is still the durable artifact, and what is
# absent is routing information a later task needs.
DIFF_ONLY="$WORKDIR/diff-only-tenant.sh"
cat > "$DIFF_ONLY" <<'TENANT'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
printf 'diff-only tenant: a diff with nowhere declared to apply it
'
printf -- '--- a/resident.nix
+++ b/resident.nix
@@ -1 +1 @@
-placeholder before
+placeholder after
' > "$CASTLE_DIFF_FILE"
TENANT
chmod +x "$DIFF_ONLY"
REQ_DIFFONLY="$("$CASTLE" ask "An invented errand whose tenant writes a diff and declares no target.")"
CASTLE_WORKER_COMMAND="$DIFF_ONLY" "$CASTLE" work "$REQ_DIFFONLY" >/dev/null
R_DIFFONLY="$(newest_result_for "$REQ_DIFFONLY")"
grep -q '^outcome: completed$' "$R_DIFFONLY" || fail "the diff-only turn did not complete"
grep -q '^+placeholder after$' "$R_DIFFONLY" || fail "the diff-only turn's diff is not in the result body"
grep -q '^target:' "$R_DIFFONLY" && fail "a turn that declared no target carries a target field"
grep -q 'produced a diff but declared no target' "$R_DIFFONLY" \
  || fail "a diff with no target was recorded silently — 0025 and 0026 cannot route it and nothing says so"
grep -q 'cannot be routed to a checkout' "$R_DIFFONLY" \
  || fail "the note does not say what is actually lost by the missing target"
"$CASTLE" validate >/dev/null

# ---------------------------------------------------------------------
log "a target is recorded only on a turn that finished, with a resolvable role"
# ---------------------------------------------------------------------
# `target` is what 0025 and 0026 route on, so it must mean "this
# result carries a proposal, and here is the checkout it applies to."
# Three ways that could be false while the field said otherwise, all
# checked here: no diff (covered above), a turn that did not end in
# `completed`, and a role this turn could not resolve to a path.

log "  -- a turn killed at the timeout stamps nothing, and is not accused of anything"
SLOW_STAMPER="$WORKDIR/slow-stamper.sh"
cat > "$SLOW_STAMPER" <<'TENANT'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
printf 'slow-stamper: both files written, then killed mid-turn
'
printf -- '--- a/resident.nix
+++ b/resident.nix
@@ -1 +1 @@
-before
+after
' > "$CASTLE_DIFF_FILE"
printf 'private
' > "$CASTLE_TARGET_FILE"
sleep 30
TENANT
chmod +x "$SLOW_STAMPER"
REQ_TIMEOUT="$("$CASTLE" ask "An invented errand whose tenant writes both files and is then killed.")"
CASTLE_WORKER_TIMEOUT=2 CASTLE_WORKER_COMMAND="$SLOW_STAMPER" "$CASTLE" work "$REQ_TIMEOUT" >/dev/null 2>&1 || true
R_TIMEOUT="$(newest_result_for "$REQ_TIMEOUT")"
grep -q '^outcome: timeout$' "$R_TIMEOUT" || fail "the slow stamper did not time out: $(grep '^outcome:' "$R_TIMEOUT")"
grep -q '^target:' "$R_TIMEOUT" \
  && fail "a timed-out turn stamped a target — the field says routable while outcome says the tenant was killed, which is failure readable only from prose"
grep -q 'did not end in .completed.' "$R_TIMEOUT" \
  || fail "the unfinished result does not say why it carries no target"
grep -q 'declared no target' "$R_TIMEOUT" \
  && fail "a tenant killed by this invoker is accused of not declaring a target"
"$CASTLE" validate >/dev/null

log "  -- and an unresolvable role is diagnosed, not recorded"
BAD_ROLE="$WORKDIR/bad-role.sh"
cat > "$BAD_ROLE" <<'TENANT'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
printf 'bad-role: a one-character slip in the role name
'
printf -- '--- a/resident.nix
+++ b/resident.nix
@@ -1 +1 @@
-before
+after
' > "$CASTLE_DIFF_FILE"
printf 'Private
' > "$CASTLE_TARGET_FILE"
TENANT
chmod +x "$BAD_ROLE"
REQ_BADROLE="$("$CASTLE" ask "An invented errand whose tenant names a checkout role that does not exist.")"
CASTLE_WORKER_COMMAND="$BAD_ROLE" "$CASTLE" work "$REQ_BADROLE" >/dev/null
R_BADROLE="$(newest_result_for "$REQ_BADROLE")"
grep -q '^outcome: completed$' "$R_BADROLE" || fail "the bad-role turn did not complete"
grep -q '^target:' "$R_BADROLE" \
  && fail "a role this turn could not resolve was written into the frontmatter anyway — castle validate accepts it and an applier reads it as routable while it points nowhere"
grep -qF 'named `Private` as this diff' "$R_BADROLE" \
  || fail "the unresolvable role is not named in the body"
grep -q 'has not been recorded' "$R_BADROLE" \
  || fail "the body does not say the role was dropped rather than recorded"
"$CASTLE" validate >/dev/null
assert_checkouts_untouched "after the target-gating cases"

# ---------------------------------------------------------------------
log "castle record refuses a --target it would then fail to validate"
# ---------------------------------------------------------------------
# The door must not be laxer than the backstop. In an append-only
# journal a record written and only later condemned by `castle
# validate` cannot be withdrawn — the remedy would be editing history
# the whole design says is never edited.
if "$CASTLE" record --type decision --provenance requested --seat worker \
  --refs "$REQ1" --evidence "an invented decision" --target private --body "placeholder" >/dev/null 2>&1; then
  fail "castle record wrote --target on a decision record, which castle validate then rejects"
fi
if "$CASTLE" record --type result --provenance requested --seat worker \
  --refs "$REQ1" --outcome completed --target "   " --body "placeholder" >/dev/null 2>&1; then
  fail "castle record wrote a blank --target, which castle validate then rejects"
fi
"$CASTLE" validate >/dev/null

# ---------------------------------------------------------------------
log "assertion 9a: a broken mechanism root does NOT refuse a turn that never needed it"
# ---------------------------------------------------------------------
REQ_BROKEN="$("$CASTLE" ask "CONFIG-TARGET-FIXTURE-CURSOR: an invented complaint on a host whose mechanism path is a typo.")"
CASTLE_MECHANISM_ROOT="$NOT_A_CHECKOUT" "$CASTLE" work "$REQ_BROKEN" >/dev/null
R_BROKEN="$(newest_result_for "$REQ_BROKEN")"
grep -q '^outcome: completed$' "$R_BROKEN" \
  || fail "a configured-but-unusable mechanism root refused an errand that never touched mechanism"
grep -q '^target: private$' "$R_BROKEN" || fail "the degraded turn produced no private target"
grep -q '^+    cursorSize = 32;$' "$R_BROKEN" || fail "the degraded turn produced no diff"
# The note is harness-level: it is here whether or not the tenant's own
# prose mentions mechanism, which is the only thing that keeps a typo
# visible on the errands that never needed that checkout.
grep -qF "Note: \`castle.agent.repo.mechanism\` is configured (\`$NOT_A_CHECKOUT\`)" "$R_BROKEN" \
  || fail "the result carries no mechanism-unusable note: $(grep -n 'mechanism' "$R_BROKEN")"
"$CASTLE" validate >/dev/null

# ---------------------------------------------------------------------
log "assertion 9b: and the tenant itself can tell 'broken' from 'never configured'"
# ---------------------------------------------------------------------
REQ_MECHBROKEN="$("$CASTLE" ask "CONFIG-TARGET-FIXTURE-MECHANISM: an invented complaint needing an option that does not exist yet.")"
CASTLE_MECHANISM_ROOT="$NOT_A_CHECKOUT" "$CASTLE" work "$REQ_MECHBROKEN" >/dev/null
R_MECHBROKEN="$(newest_result_for "$REQ_MECHBROKEN")"
grep -qF "mechanism checkout CONFIGURED BUT UNUSABLE at $NOT_A_CHECKOUT" "$R_MECHBROKEN" \
  || fail "the tenant did not receive CASTLE_MECHANISM_ROOT_INVALID naming the broken path"
grep -q 'DECLINING' "$R_MECHBROKEN" || fail "the tenant proposed a mechanism diff against an unusable checkout"
grep -q '^target:' "$R_MECHBROKEN" && fail "a declined mechanism errand stamped a target anyway"
grep -q 'misconfiguration to fix, not' "$R_MECHBROKEN" \
  || fail "the tenant described a misconfiguration as an absence"
"$CASTLE" validate >/dev/null

# ---------------------------------------------------------------------
log "a usable mechanism root: a mechanism-shaped errand targets it"
# ---------------------------------------------------------------------
REQ_MECH="$("$CASTLE" ask "CONFIG-TARGET-FIXTURE-MECHANISM: the same invented complaint, on a host that does keep a framework checkout.")"
CASTLE_MECHANISM_ROOT="$MECHANISM" "$CASTLE" work "$REQ_MECH" >/dev/null
R_MECH="$(newest_result_for "$REQ_MECH")"
grep -q '^target: mechanism$' "$R_MECH" || fail "the mechanism errand did not stamp target: mechanism"
grep -qF "This diff targets the **mechanism** checkout, which on this host resolved to \`$MECHANISM\`." "$R_MECH" \
  || fail "the result body does not name the resolved mechanism path"
grep -q 'castle.agent.repo.mechanism` is configured' "$R_MECH" \
  && fail "a usable mechanism root produced the unusable note"

# ---------------------------------------------------------------------
log "and with no mechanism root at all, the same errand says so and proposes nothing"
# ---------------------------------------------------------------------
REQ_NOMECH="$("$CASTLE" ask "CONFIG-TARGET-FIXTURE-MECHANISM: the same invented complaint, on a host with no framework checkout.")"
"$CASTLE" work "$REQ_NOMECH" >/dev/null
R_NOMECH="$(newest_result_for "$REQ_NOMECH")"
grep -q 'no mechanism checkout configured (the normal case)' "$R_NOMECH" \
  || fail "the tenant was not told the mechanism checkout is simply absent"
grep -q 'nowhere' "$R_NOMECH" || fail "the tenant did not say why it cannot propose a mechanism change"
grep -q '^target:' "$R_NOMECH" && fail "an errand that proposed nothing stamped a target"
assert_checkouts_untouched "after the mechanism errands"
"$CASTLE" validate >/dev/null

# ---------------------------------------------------------------------
log "assertion 8: ask first, diff on resumption — end to end"
# ---------------------------------------------------------------------
REQP="$("$CASTLE" ask "CONFIG-TARGET-FIXTURE-PERCEPTUAL: an invented complaint whose right value is a judgment, not a fact.")"
log "  -> $REQP"
"$CASTLE" dispatch >/dev/null
RP1="$(newest_result_for "$REQP")"
[ -n "$RP1" ] || fail "the first turn on the perceptual errand wrote no result"
grep -q '^outcome: completed$' "$RP1" || fail "the ask-first turn did not complete"

log "  -- turn one writes NO diff and NO target, and files a blocking question"
grep -q '^target:' "$RP1" && fail "the ask-first turn stamped a target with nothing to target"
grep -q 'no diff produced' "$RP1" || fail "the ask-first turn produced a diff it should not have"
QP="$(blocking_question_for "$REQP")"
[ -n "$QP" ] || fail "the ask-first turn filed no blocking question"

log "  -- and with no mechanism checkout, it names no tool path the resident could not run"
# The sweep scripts live in the public repo under tools/, which
# tools/README.md calls developer tooling rather than anything a
# deployed system installs. On a host with no mechanism checkout —
# the normal case — a question whose one instruction is "run
# tools/font-sweep.sh" stops the errand and then points the resident
# at a path that is not on their machine. Asserted from both sides so
# neither half can rot: no script path when there is nowhere for one
# to live, and something actionable in its place.
grep -q 'font-sweep.sh' "$JOURNAL/$QP.md" \
  && fail "the question names a sweep script on a host with no mechanism checkout to hold one"
grep -q 'compare a few candidate sizes side by side' "$JOURNAL/$QP.md" \
  || fail "the question offers the resident no way to settle the value: $(sed -n '/^$/,$p' "$JOURNAL/$QP.md")"

# ---------------------------------------------------------------------
log "the rendered prompt never contradicts itself about the mechanism checkout"
# ---------------------------------------------------------------------
# Asserted against the REAL tenant's rendered prompt, not the fixture's
# behaviour, because this is a defect the fixture cannot see: the
# prompt is prose assembled from several independently-branched
# variables, and one of them regressed to a two-way test while the
# others stayed three-way. The result was a single prompt saying, two
# screens apart, both "configured at <path> but not usable" and "no
# mechanism checkout is configured here" — the collapse of "absent"
# into "misconfigured" that the third variable exists to prevent.
#
# Rendered with the tenant's own exec replaced by a cat, the same
# technique resume.sh uses on this file. Every branch of every
# mechanism-keyed variable has to agree, so the test is a search for
# the absent-phrasing in a state where it is false.
#
# EVERY SEARCH GOES THROUGH `flat`, which squashes all whitespace onto
# one line first. The prompt is hand-wrapped prose, so "no mechanism
# checkout is configured" is split across two lines in the source and
# a line-oriented grep for it silently never matches. The first
# version of this assertion had exactly that defect and passed against
# a deliberately reintroduced bug; it is the third time in this task
# that a check has been written against text it could not see, and the
# only reliable fix is to stop matching against wrapped prose.
PROMPT_RENDER="$WORKDIR/render-tenant.sh"
sed 's|^exec claude.*|cat <\&3|' "$REPO_ROOT/agent/castle-worker-claude" > "$PROMPT_RENDER"
# The deliverable paths this probe hands over, and the home directory
# the tenant is told to measure them against. Since docs/tasks/0039 the
# reference tenant declares its sandbox — writes only beneath the
# resident home directory it is given — and refuses before rendering
# anything when the two output files fall outside it. These were
# /dev/null, which is outside any home; the probe never writes either
# file (the exec is replaced by `cat <&3` above), so what they need to
# be is inside the declared sandbox, not real.
RENDER_HOME="$WORKDIR/render-home"
mkdir -p "$RENDER_HOME"
render_prompt() {
  # $1 is one of: usable | invalid | absent
  local packet='CASTLE-PACKET-0123456789abcdef a rendering probe, not a real packet'
  case "$1" in
    usable)  env HOME="$RENDER_HOME" CASTLE_REQUEST_ID=probe CASTLE_DIFF_FILE="$RENDER_HOME/diff" CASTLE_TARGET_FILE="$RENDER_HOME/target" \
               CASTLE_PRIVATE_ROOT="$PRIVATE" CASTLE_MECHANISM_ROOT="$MECHANISM" \
               bash "$PROMPT_RENDER" <<<"$packet" 2>&1 ;;
    invalid) env HOME="$RENDER_HOME" CASTLE_REQUEST_ID=probe CASTLE_DIFF_FILE="$RENDER_HOME/diff" CASTLE_TARGET_FILE="$RENDER_HOME/target" \
               CASTLE_PRIVATE_ROOT="$PRIVATE" CASTLE_MECHANISM_ROOT_INVALID="$NOT_A_CHECKOUT" \
               bash "$PROMPT_RENDER" <<<"$packet" 2>&1 ;;
    absent)  env -u CASTLE_MECHANISM_ROOT -u CASTLE_MECHANISM_ROOT_INVALID \
               HOME="$RENDER_HOME" CASTLE_REQUEST_ID=probe CASTLE_DIFF_FILE="$RENDER_HOME/diff" CASTLE_TARGET_FILE="$RENDER_HOME/target" \
               CASTLE_PRIVATE_ROOT="$PRIVATE" \
               bash "$PROMPT_RENDER" <<<"$packet" 2>&1 ;;
  esac
}

# Whole rendered prompt, all whitespace collapsed, so a phrase the
# prose wrapped is still one searchable string.
flat() { printf '%s' "$1" | tr -s '[:space:]' ' '; }

R_INVALID="$(flat "$(render_prompt invalid)")"
printf '%s' "$R_INVALID" | grep -qF "$NOT_A_CHECKOUT" \
  || fail "the invalid-mechanism prompt never names the broken path"
printf '%s' "$R_INVALID" | grep -qF 'no mechanism checkout is configured' \
  && fail "the rendered prompt says a mechanism checkout is configured-but-broken AND that none is configured — the three-state channel has collapsed somewhere in it"
printf '%s' "$R_INVALID" | grep -qF 'NOT a usable git working tree' \
  || fail "the invalid-mechanism prompt does not describe the checkout as unusable"

R_ABSENT="$(flat "$(render_prompt absent)")"
printf '%s' "$R_ABSENT" | grep -qF 'NO checkout of the public Castle Turing framework repository is configured' \
  || fail "the absent-mechanism prompt does not say plainly that none is configured"
printf '%s' "$R_ABSENT" | grep -qF 'NOT a usable git working tree' \
  && fail "the absent-mechanism prompt describes a broken checkout that does not exist"

R_USABLE="$(flat "$(render_prompt usable)")"
printf '%s' "$R_USABLE" | grep -qF "$MECHANISM/tools/font-sweep.sh" \
  || fail "the usable-mechanism prompt does not point at the sweep tool that really is there"
printf '%s' "$R_USABLE" | grep -qF 'no mechanism checkout is configured' \
  && fail "the usable-mechanism prompt claims none is configured"

# The positive control for the searches above: the phrase they hunt
# for must really be findable in the one state where it belongs, or
# all three greps are vacuous whatever the code does.
printf '%s' "$R_ABSENT" | grep -qF 'no mechanism checkout is configured' \
  || fail "the absent-state prompt does not contain the phrase the other two states are checked against — those checks would pass vacuously"

# And no branch may leave a shell substitution error in the tenant's
# own instructions — the backtick hazard this prompt already carries a
# warning about, checked rather than trusted.
for state in usable invalid absent; do
  printf '%s\n' "$(render_prompt $state)" | grep -qE 'command not found|missing operand|unexpected EOF' \
    && fail "the $state-mechanism prompt renders with a shell error in it"
done

# ---------------------------------------------------------------------
log "assertion 10: this empty diff is legible as 'waiting on you', not as 'no change warranted'"
# ---------------------------------------------------------------------
# Asserted against the fold something real actually reads, rather than
# only against the absence of a second result: the two meanings of an
# empty diff are distinguished by the open blocking question, through
# machinery that already existed, and nothing new was added to the
# record schema to carry the distinction.
STATUS_WAITING="$("$MODAL" --mode status --limit 40)"
printf '%s\n' "$STATUS_WAITING" | grep -F "$REQP" | grep -q 'waiting on you' \
  || fail "the ask-first errand does not read as waiting on the resident: $(printf '%s\n' "$STATUS_WAITING" | grep -F "$REQP")"
# The contrast case, from the same fold in the same breath: an errand
# that finished with no open question must NOT read as waiting, or the
# assertion above would be satisfied by everything. Its presence in the
# listing is checked first — a contrast case the fold never rendered
# would pass this vacuously.
#
# $REQ_NOMECH rather than $REQ1, and the swap is this task's doing
# rather than tidying: since docs/tasks/0025-approval.md a turn that
# finishes with a real diff and a resolved target files a proposal
# question of its own, so $REQ1 — the completed, targeted, diffed
# errand this line used to contrast against — now genuinely IS waiting
# on the resident, and correctly says so. $REQ_NOMECH is the errand
# that completed and proposed nothing: no diff, no target, no proposal
# question, no question of any kind. It is the shape this assertion
# was always about.
printf '%s\n' "$STATUS_WAITING" | grep -qF "$REQ_NOMECH" \
  || fail "the contrast errand $REQ_NOMECH is not in the status listing at all, so the check below proves nothing"
printf '%s\n' "$STATUS_WAITING" | grep -F "$REQ_NOMECH" | grep -q 'waiting on you' \
  && fail "a completed errand with no open question reads as waiting on the resident"
# And the other half of the same swap, asserted rather than left
# implied: the completed errand that DID propose something is waiting,
# because a proposal nobody has decided is exactly that.
printf '%s\n' "$STATUS_WAITING" | grep -F "$REQ1" | grep -q 'waiting on you' \
  || fail "a completed errand carrying an undecided proposal does not read as waiting on the resident: $(printf '%s\n' "$STATUS_WAITING" | grep -F "$REQ1")"

log "  -- an unanswered blocking question resumes nothing, however many sweeps run"
"$CASTLE" dispatch >/dev/null
"$CASTLE" dispatch >/dev/null
[ "$(count_referencing result "$REQP")" -eq 1 ] || fail "an unanswered blocking question started another turn"

log "  -- the resident answers, and the resumed turn writes the diff around their number"
AP="$("$CASTLE" answer "$QP" "CONFIG-TARGET-FIXTURE-ANSWER-16 — the number an invented resident settled on.")"
"$CASTLE" dispatch >/dev/null
[ "$(count_referencing result "$REQP")" -eq 2 ] || fail "the answered blocking question did not resume the errand"
RP2="$(newest_result_for "$REQP")"
grep -q '^outcome: completed$' "$RP2" || fail "the resumed turn did not complete"
grep -q '^target: private$' "$RP2" || fail "the resumed turn stamped no target"
grep -q '^+    terminalFontSize = 16;$' "$RP2" \
  || fail "the resumed turn's diff is not built around the resident's own answer: $(grep -n '^+' "$RP2")"
grep -qF "resolved to \`$PRIVATE\`" "$RP2" || fail "the resumed result does not name the resolved path"
assert_checkouts_untouched "after the resumption"
"$CASTLE" validate >/dev/null

# ---------------------------------------------------------------------
log "byte fidelity: the sidecar carries the tenant's exact bytes (docs/tasks/0033-byte-exact-proposal.md)"
# ---------------------------------------------------------------------
# The fixture bytes are built exactly once, here, with printf — never
# pasted as literal characters in this file — so this harness's own
# source stays plain, valid UTF-8 even for the invalid-UTF-8 case
# below. scripted-worker-byte-fidelity.sh only `cp`s from this
# directory; it never constructs a byte sequence itself, so there is
# one spelling of each adversarial case, not two that could drift.
BYTE_FIDELITY_DIR="$WORKDIR/byte-fidelity"
mkdir -p "$BYTE_FIDELITY_DIR"

# CRLF line endings: a unified diff adding a new file whose content
# lines end \r\n. A "new file" diff so applying it needs no matching
# context in the checkout it targets.
printf -- '--- /dev/null\n+++ b/byte-fidelity-crlf.txt\n@@ -0,0 +1,3 @@\n+line one\r\n+line two\r\n+line three\r\n' \
  > "$BYTE_FIDELITY_DIR/crlf.diff"

# A form feed (\f) inside a content line, not at either end — so
# str.splitlines()'s treatment of \f as a line break (not str.strip()'s
# whitespace trimming at the ends) is what this case isolates.
printf -- '--- /dev/null\n+++ b/byte-fidelity-formfeed.txt\n@@ -0,0 +1,1 @@\n+before\fafter\n' \
  > "$BYTE_FIDELITY_DIR/formfeed.diff"

# U+2028 LINE SEPARATOR (UTF-8: e2 80 a8), also inside a content line.
# Valid UTF-8, so the lenient decode (transform 1) does not touch it —
# only the splitlines() round trip (transform 4) can lose it.
printf -- '--- /dev/null\n+++ b/byte-fidelity-u2028.txt\n@@ -0,0 +1,1 @@\n+before\xe2\x80\xa8after\n' \
  > "$BYTE_FIDELITY_DIR/u2028.diff"

# One byte that is not valid UTF-8 on its own (a lone continuation
# byte). Generated with printf, never pasted, per the same rule as the
# rest of this block.
printf -- '--- /dev/null\n+++ b/byte-fidelity-invalid.txt\n@@ -0,0 +1,1 @@\n+before\x80after\n' \
  > "$BYTE_FIDELITY_DIR/invalid-utf8.diff"

# No trailing newline at all — the last byte of the file is the last
# character of the patch, not a newline.
printf -- '--- /dev/null\n+++ b/byte-fidelity-notrail.txt\n@@ -0,0 +1,2 @@\n+line one\n+line two' \
  > "$BYTE_FIDELITY_DIR/no-trailing-newline.diff"

export CASTLE_BYTE_FIDELITY_DIR="$BYTE_FIDELITY_DIR"

# One helper, reused by every case below: dispatch the errand, find its
# result, confirm the sidecar exists and byte-matches exactly what the
# tenant copied from — the harness's own fixture file, not a second
# hand-typed copy of it.
run_byte_fidelity_case() {
  local marker="$1" fixture="$2"
  local req result sidecar
  req="$("$CASTLE" ask "$marker: an invented probe exercising one byte-fidelity case.")"
  CASTLE_WORKER_COMMAND="$BYTE_WORKER" "$CASTLE" work "$req" >/dev/null
  result="$(newest_result_for "$req")"
  [ -n "$result" ] || fail "$marker: no result written"
  grep -q '^outcome: completed$' "$result" || fail "$marker: the turn did not complete"
  grep -q "^${PATCH_SHA256_FIELD}: " "$result" \
    || fail "$marker: the result carries no patch-sha256 field"
  sidecar="${result%.md}.patch"
  [ -f "$sidecar" ] || fail "$marker: no sidecar file was written beside the result"
  cmp -s "$sidecar" "$BYTE_FIDELITY_DIR/$fixture" \
    || fail "$marker: the sidecar is not byte-identical to what the tenant wrote"
  printf '%s\n' "$result"
}

PATCH_SHA256_FIELD="patch-sha256"

log "  -- CRLF: sidecar applies cleanly; the record body's copy does not, or applies to different content"
R_CRLF="$(run_byte_fidelity_case BYTE-FIDELITY-FIXTURE-CRLF crlf.diff)"
SIDECAR_CRLF="${R_CRLF%.md}.patch"
extract_record_diff "$R_CRLF" "$WORKDIR/crlf-extracted.diff"
cmp -s "$WORKDIR/crlf-extracted.diff" "$BYTE_FIDELITY_DIR/crlf.diff" \
  && fail "CRLF: the record body's copy is byte-identical to the raw bytes — the contrast this task exists to prove did not happen"

CRLF_CLONE_SIDECAR="$WORKDIR/crlf-clone-sidecar"
CRLF_CLONE_BODY="$WORKDIR/crlf-clone-body"
git clone -q "$PRIVATE" "$CRLF_CLONE_SIDECAR"
git clone -q "$PRIVATE" "$CRLF_CLONE_BODY"
(cd "$CRLF_CLONE_SIDECAR" && git apply --check "$SIDECAR_CRLF") \
  || fail "CRLF: git apply --check rejected the sidecar's own bytes against a fresh clone"
(cd "$CRLF_CLONE_SIDECAR" && git apply "$SIDECAR_CRLF") 2>/dev/null \
  || fail "CRLF: git apply (not --check) rejected the sidecar's own bytes"
if (cd "$CRLF_CLONE_BODY" && git apply --check "$WORKDIR/crlf-extracted.diff") 2>/dev/null; then
  # It applied — the weaker of the two outcomes the brief allows. What
  # must still be true is that it produced DIFFERENT file content than
  # the sidecar's real apply did, or CRLF fidelity was not actually
  # lost anywhere observable.
  (cd "$CRLF_CLONE_BODY" && git apply "$WORKDIR/crlf-extracted.diff") \
    || fail "CRLF: the record body's copy passed --check but failed a real apply"
  cmp -s "$CRLF_CLONE_SIDECAR/byte-fidelity-crlf.txt" "$CRLF_CLONE_BODY/byte-fidelity-crlf.txt" \
    && fail "CRLF: both the sidecar and the record body's copy applied to IDENTICAL file content — CRLF fidelity was not actually lost"
  log "  -- record body's copy applied, but to different (CRLF-stripped) content — confirmed"
else
  log "  -- record body's copy correctly refused by git apply --check"
fi
"$CASTLE" validate >/dev/null

log "  -- form feed: sidecar exact, record body's copy diverges (splitlines() treats \\f as a line break)"
R_FF="$(run_byte_fidelity_case BYTE-FIDELITY-FIXTURE-FORMFEED formfeed.diff)"
extract_record_diff "$R_FF" "$WORKDIR/formfeed-extracted.diff"
cmp -s "$WORKDIR/formfeed-extracted.diff" "$BYTE_FIDELITY_DIR/formfeed.diff" \
  && fail "form feed: the record body's copy is byte-identical to the raw bytes — expected the splitlines() divergence to be observable"

log "  -- U+2028 LINE SEPARATOR: sidecar exact, record body's copy diverges"
R_U2028="$(run_byte_fidelity_case BYTE-FIDELITY-FIXTURE-U2028 u2028.diff)"
extract_record_diff "$R_U2028" "$WORKDIR/u2028-extracted.diff"
cmp -s "$WORKDIR/u2028-extracted.diff" "$BYTE_FIDELITY_DIR/u2028.diff" \
  && fail "U+2028: the record body's copy is byte-identical to the raw bytes — expected the splitlines() divergence to be observable"

log "  -- invalid UTF-8 byte: sidecar exact, record body's copy substitutes U+FFFD"
R_BADUTF8="$(run_byte_fidelity_case BYTE-FIDELITY-FIXTURE-INVALIDUTF8 invalid-utf8.diff)"
extract_record_diff "$R_BADUTF8" "$WORKDIR/invalid-utf8-extracted.diff"
cmp -s "$WORKDIR/invalid-utf8-extracted.diff" "$BYTE_FIDELITY_DIR/invalid-utf8.diff" \
  && fail "invalid UTF-8: the record body's copy is byte-identical to the raw bytes — errors=\"replace\" should have substituted the invalid byte"
grep -qF $'\xef\xbf\xbd' "$R_BADUTF8" \
  || fail "invalid UTF-8: the record body does not contain a U+FFFD replacement character where the invalid byte was"

log "  -- no trailing newline: the sidecar preserves the missing final newline exactly"
R_NOTRAIL="$(run_byte_fidelity_case BYTE-FIDELITY-FIXTURE-NONEWLINE no-trailing-newline.diff)"
# The cmp inside run_byte_fidelity_case is the assertion that matters
# here: the sidecar's last byte is 'o', not a newline, exactly as the
# tenant wrote it.

assert_checkouts_untouched "after the byte-fidelity cases"
"$CASTLE" validate >/dev/null

# ---------------------------------------------------------------------
log "a turn killed at the timeout still gets a sidecar, and that sidecar is unreachable through the approval channel"
# ---------------------------------------------------------------------
# `patch-sha256` and the sidecar ride `diff-boundary`'s own gate —
# `if diff_text`, unconditional on outcome — not `stamped_target`'s
# narrower `diff_text and finished_cleanly` gate. So a tenant that
# writes a real diff and is then killed at CASTLE_WORKER_TIMEOUT still
# gets a byte-exact sidecar (agent/README.md's "The byte-exact
# sidecar"): completed-and-targeted is the normal case, not the rule.
# What must also be true, and is the whole point of the split: no
# `target` field (the SLOW_STAMPER case above already covers this) and
# — new here — no proposal question ever filed for this result, so
# nothing reaches the resident to approve and nothing for 0026's
# applier to spend. Reuses the byte-fidelity block's own
# no-trailing-newline fixture rather than typing a second copy of the
# bytes under test.
TIMEOUT_DIFF_WORKER="$WORKDIR/timeout-diff-worker.sh"
cat > "$TIMEOUT_DIFF_WORKER" <<'TENANT'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
printf 'timeout-diff-worker: diff and target written, then killed mid-turn\n'
cp "$CASTLE_BYTE_FIDELITY_DIR/no-trailing-newline.diff" "$CASTLE_DIFF_FILE"
printf 'private\n' > "$CASTLE_TARGET_FILE"
sleep 30
TENANT
chmod +x "$TIMEOUT_DIFF_WORKER"
REQ_TIMEOUT_DIFF="$("$CASTLE" ask "An invented errand whose tenant writes a real diff, then is killed at the timeout.")"
CASTLE_WORKER_TIMEOUT=3 CASTLE_WORKER_COMMAND="$TIMEOUT_DIFF_WORKER" "$CASTLE" work "$REQ_TIMEOUT_DIFF" >/dev/null 2>&1 || true
R_TIMEOUT_DIFF="$(newest_result_for "$REQ_TIMEOUT_DIFF")"
R_TIMEOUT_DIFF_ID="$(basename "$R_TIMEOUT_DIFF" .md)"

grep -q '^outcome: timeout$' "$R_TIMEOUT_DIFF" \
  || fail "timeout-with-diff: the tenant did not time out: $(grep '^outcome:' "$R_TIMEOUT_DIFF")"
grep -q '^diff-boundary: ' "$R_TIMEOUT_DIFF" \
  || fail "timeout-with-diff: no diff-boundary field — a timed-out turn that wrote a diff should still gate on it"
grep -q "^${PATCH_SHA256_FIELD}: " "$R_TIMEOUT_DIFF" \
  || fail "timeout-with-diff: no patch-sha256 field — the sidecar gate must ride diff-boundary's, not stamped_target's"
SIDECAR_TIMEOUT_DIFF="${R_TIMEOUT_DIFF%.md}.patch"
[ -f "$SIDECAR_TIMEOUT_DIFF" ] \
  || fail "timeout-with-diff: patch-sha256 is stamped but no sidecar file exists beside the result"
cmp -s "$SIDECAR_TIMEOUT_DIFF" "$BYTE_FIDELITY_DIR/no-trailing-newline.diff" \
  || fail "timeout-with-diff: the sidecar is not byte-identical to what the tenant wrote"
grep -q '^target:' "$R_TIMEOUT_DIFF" \
  && fail "timeout-with-diff: a target was stamped on a turn that did not finish cleanly"
grep -l "$R_TIMEOUT_DIFF_ID" "$JOURNAL"/*-question-*.md >/dev/null 2>&1 \
  && fail "timeout-with-diff: a proposal question was filed for a result that never stamped a target — the approval channel is not supposed to be reachable from here"
"$CASTLE" validate >/dev/null \
  || fail "timeout-with-diff: castle validate is not green on a journal holding this sidecar"
assert_checkouts_untouched "after the timeout-with-diff case"

# ---------------------------------------------------------------------
log "castle validate red/green matrix: patch-sha256"
# ---------------------------------------------------------------------
# Reuses the CRLF case's already-completed, already-valid turn as the
# green baseline, mutating and restoring it once per red case so a
# later assertion never sees a case this block itself left broken.
#
# Output is captured to a file and grepped separately from the
# validate call, deliberately not `validate 2>&1 | grep -q ...`: under
# `set -o pipefail` (this file's own setting) a pipeline reports the
# last NON-ZERO stage, not the last stage — so with `castle validate`
# expected to fail and `grep -q` expected to succeed, that pattern
# reports the pipeline as failed even when the grep matched exactly
# what it was looking for. Caught by this harness failing on its own
# correct output the first time this block was written.
validate_output="$WORKDIR/validate-output.log"

log "  -- red: a tampered sidecar"
cp "$SIDECAR_CRLF" "$WORKDIR/sidecar-backup.patch"
printf 'x' >> "$SIDECAR_CRLF"
"$CASTLE" validate >/dev/null 2>&1 && fail "castle validate passed with a tampered sidecar"
"$CASTLE" validate > "$validate_output" 2>&1 || true
grep -q "does not match the sidecar" "$validate_output" \
  || fail "the tampered-sidecar error does not name the mismatch"
cp "$WORKDIR/sidecar-backup.patch" "$SIDECAR_CRLF"
"$CASTLE" validate >/dev/null || fail "castle validate did not recover once the sidecar was restored"

log "  -- red: a deleted sidecar"
mv "$SIDECAR_CRLF" "$WORKDIR/sidecar-moved.patch"
"$CASTLE" validate >/dev/null 2>&1 && fail "castle validate passed with a deleted sidecar"
"$CASTLE" validate > "$validate_output" 2>&1 || true
grep -q "no sidecar file exists" "$validate_output" \
  || fail "the deleted-sidecar error does not say a sidecar is missing"
mv "$WORKDIR/sidecar-moved.patch" "$SIDECAR_CRLF"
"$CASTLE" validate >/dev/null || fail "castle validate did not recover once the sidecar was restored"

log "  -- red: a malformed patch-sha256"
cp "$R_CRLF" "$WORKDIR/record-backup.md"
sed -i 's/^patch-sha256: .*/patch-sha256: not-a-hex-value/' "$R_CRLF"
"$CASTLE" validate >/dev/null 2>&1 && fail "castle validate passed with a malformed patch-sha256"
"$CASTLE" validate > "$validate_output" 2>&1 || true
grep -q "is not 64 lowercase hex characters" "$validate_output" \
  || fail "the malformed-field error does not name the hex-shape problem"
cp "$WORKDIR/record-backup.md" "$R_CRLF"
"$CASTLE" validate >/dev/null || fail "castle validate did not recover once the record was restored"

log "  -- red: a sidecar replaced by a directory"
# Reproduced: `sidecar.read_bytes()` with the sidecar path pointing at
# a directory raises `IsADirectoryError` uncaught — `castle validate`'s
# whole job is to report a broken journal, not crash on one.
mv "$SIDECAR_CRLF" "$WORKDIR/sidecar-crlf-real.patch"
mkdir "$SIDECAR_CRLF"
"$CASTLE" validate >/dev/null 2>&1 && fail "castle validate passed with the sidecar replaced by a directory"
"$CASTLE" validate > "$validate_output" 2>&1 || true
grep -qF "Traceback" "$validate_output" \
  && fail "castle validate crashed with a Python traceback instead of reporting the directory-sidecar error"
grep -qF "$(basename "$SIDECAR_CRLF")" "$validate_output" \
  || fail "the directory-sidecar error does not name the sidecar path"
rmdir "$SIDECAR_CRLF"
mv "$WORKDIR/sidecar-crlf-real.patch" "$SIDECAR_CRLF"
"$CASTLE" validate >/dev/null || fail "castle validate did not recover once the sidecar was restored"

log "  -- red: a record containing one invalid UTF-8 byte"
# `parse_record`'s `read_text(encoding="utf-8")` raises
# `UnicodeDecodeError` on this, and every existing caller before this
# task's fix caught only OSError/RecordError, so `castle validate` and
# `castle digest` both tracebacked instead of reporting the file. Not a
# regression this task introduced, but this is the branch that made
# "records are UTF-8 by definition" an explicit, enforced claim, so it
# owns making a violation report cleanly (docs/tasks/0033-byte-exact-
# proposal.md, agent/README.md's "The record format").
cp "$R_CRLF" "$WORKDIR/record-backup.md"
printf '\x80' >> "$R_CRLF"
"$CASTLE" validate >/dev/null 2>&1 && fail "castle validate passed with a record containing an invalid UTF-8 byte"
"$CASTLE" validate > "$validate_output" 2>&1 || true
grep -qF "Traceback" "$validate_output" \
  && fail "castle validate crashed with a Python traceback on invalid UTF-8 instead of reporting it"
grep -qF "$(basename "$R_CRLF")" "$validate_output" \
  || fail "the invalid-UTF-8 error does not name the file"
digest_output="$WORKDIR/digest-output.log"
"$CASTLE" digest > "$digest_output" 2>&1 \
  || fail "castle digest did not exit 0 over a journal with one invalid-UTF-8 record (load_all's documented skip contract): $(cat "$digest_output")"
grep -qF "Traceback" "$digest_output" \
  && fail "castle digest crashed with a Python traceback on invalid UTF-8 instead of skipping the record"
cp "$WORKDIR/record-backup.md" "$R_CRLF"
"$CASTLE" validate >/dev/null || fail "castle validate did not recover once the record was restored"

log "  -- green: a result with neither diff-boundary nor patch-sha256 at all"
# $R_NOMECH, from the mechanism block above: a completed turn that
# proposed nothing. Absent means absent — no sidecar expected.
grep -q "^${PATCH_SHA256_FIELD}:" "$R_NOMECH" \
  && fail "the no-proposal result unexpectedly carries a patch-sha256 field"
[ ! -f "${R_NOMECH%.md}.patch" ] \
  || fail "a sidecar exists beside a result that stamped no patch-sha256"
"$CASTLE" validate >/dev/null || fail "castle validate is not green on a journal with no mutations left in it"

# ---------------------------------------------------------------------
log "assertion 11: no home-shaped path in anything this fixture commits to the repo"
# ---------------------------------------------------------------------
# CLAUDE.md's hard rule, checked mechanically rather than trusted. Every
# path used at runtime above is $WORKDIR-derived; the only home-shaped
# literal permitted in a committed file is the /home/resident/...
# placeholder this repo already publishes elsewhere.
LEAKS="$(grep -nE '(/home/|\$HOME)' "$WORKER" "$BYTE_WORKER" "${BASH_SOURCE[0]}" | grep -v '/home/resident' || true)"
[ -z "$LEAKS" ] || fail "a home-shaped path leaked into a committed fixture file:
$LEAKS"

log "all assertions passed"
