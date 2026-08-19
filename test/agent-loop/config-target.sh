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
# /home/resident/private/state path shape test/desktop-loop/test.nix
# already uses. Nothing here resembles a real resident.
PRIVATE="$WORKDIR/private"
mkdir -p "$PRIVATE/state/journal"
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
  castle.agent.stateDir = "/home/resident/private/state";
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
mkdir -p "$PRIVATE_NOTHEME/state/journal"
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
# prose: the journal lives inside the private repo's own checkout.
export CASTLE_STATE_DIR="$PRIVATE/state"
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
newest_result_for() {
  local id="$1"
  referencing result "$id" | sort | tail -1
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
# `state/` is excluded from the private checkout's half, and the
# exclusion is the honest one rather than a convenience. The journal
# lives inside the private repository — that is the documented shape
# this fixture exists partly to make real — so `castle` writing a
# record there is the system working, not a worker mutating a
# checkout. Everything else under that root is in scope, and the
# mechanism checkout is checked with no exclusion at all, because
# nothing legitimately writes anything there.
assert_checkouts_untouched() {
  local where="$1"
  [ -z "$(git -C "$PRIVATE" status --porcelain -- ':(exclude)state')" ] \
    || fail "$where: the private checkout was MUTATED — $(git -C "$PRIVATE" status --porcelain -- ':(exclude)state')"
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

log "  -- and the mechanism-unusable note is ABSENT when nothing is misconfigured"
grep -q 'castle.agent.repo.mechanism` is configured' "$R1" \
  && fail "a result carried the mechanism-unusable note on a host with no mechanism root configured"

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
grep -q 'not the root of a git working tree' "$R_NOTREPO" \
  || fail "the unusable-root turn's result does not say what was wrong with the path"
"$CASTLE" validate >/dev/null
assert_checkouts_untouched "after the two refusals"

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
grep -q 'tools/font-sweep.sh' "$JOURNAL/$QP.md" || fail "the question does not point at the sweep tool"

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
# that finished with a real diff and no open question must NOT read as
# waiting, or the assertion above would be satisfied by everything.
# Its presence in the listing is checked first — a contrast case the
# fold never rendered would pass this vacuously.
printf '%s\n' "$STATUS_WAITING" | grep -qF "$REQ1" \
  || fail "the contrast errand $REQ1 is not in the status listing at all, so the check below proves nothing"
printf '%s\n' "$STATUS_WAITING" | grep -F "$REQ1" | grep -q 'waiting on you' \
  && fail "a completed errand with no open question reads as waiting on the resident"

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
log "assertion 11: no home-shaped path in anything this fixture commits to the repo"
# ---------------------------------------------------------------------
# CLAUDE.md's hard rule, checked mechanically rather than trusted. Every
# path used at runtime above is $WORKDIR-derived; the only home-shaped
# literal permitted in a committed file is the /home/resident/...
# placeholder this repo already publishes elsewhere.
LEAKS="$(grep -nE '(/home/|\$HOME)' "$WORKER" "${BASH_SOURCE[0]}" | grep -v '/home/resident' || true)"
[ -z "$LEAKS" ] || fail "a home-shaped path leaked into a committed fixture file:
$LEAKS"

log "all assertions passed"
