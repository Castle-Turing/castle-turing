#!/usr/bin/env bash
# test/agent-loop/state-layout.sh — where the journal is allowed to live
# (docs/tasks/0030-state-outside-the-flake.md §4).
#
# `castle validate` and `castle digest` warn when the resolved state
# directory sits inside the tracked tree of a git repository that
# carries a flake.nix, because evaluating such a flake — every
# `nixos-rebuild --flake /path#host` does — copies that tracked tree
# into the world-readable /nix/store. This harness builds the four
# layouts the rule has to tell apart and asserts on stderr for both
# commands.
#
# Same conventions as config-target.sh next door: plain bash, stdlib
# python3, no Nix, no models, no network, a throwaway state directory
# per case, and a git identity scoped to this process so a developer's
# own config cannot decide whether the test passes. Every path is
# $WORKDIR-derived and every literal is invented; nothing here is or
# resembles a real resident.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CASTLE="$REPO_ROOT/agent/castle"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/castle-state-layout.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

log() { printf '>>> %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

export GIT_AUTHOR_NAME="castle-state-layout-fixture"
export GIT_AUTHOR_EMAIL="fixture@example.invalid"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

# The runtime dir is never used by validate or digest, but exporting a
# throwaway one keeps this harness from touching a real session's.
export XDG_RUNTIME_DIR="$WORKDIR/runtime"
mkdir -p "$XDG_RUNTIME_DIR"

# A flake.nix that evaluates to nothing in particular. What matters
# about it here is only that the file exists at a repository root —
# the rule under test never reads it.
write_flake() {
  cat > "$1/flake.nix" <<'EOF'
# Synthetic flake, harness fixture only. Never evaluated by this test.
{
  outputs = { self }: { placeholder = "fixture"; };
}
EOF
}

# ---------------------------------------------------------------------
log "checking the ground every case stands on"
# ---------------------------------------------------------------------
# Every "silent" assertion below is made about a directory under
# $WORKDIR, and $WORKDIR's own ancestry belongs to whoever set $TMPDIR,
# not to this harness. A $TMPDIR inside somebody's flake checkout would
# make all four cases warn for a reason that has nothing to do with the
# layouts under test — green or red by accident. That is the condition
# worth refusing to run under, and it is checked rather than assumed.
#
# A bare `.git` above $WORKDIR with no flake.nix beside it is a
# different matter and is tolerated: the rule stops at the first
# repository root either way, so every case still reaches the same
# verdict. It does mean case 4 stops at that root instead of walking
# all the way to the filesystem root, so say so out loud rather than
# leaving a reader to assume otherwise. (Seen in the wild: a stray
# empty /tmp/.git left behind by some other tool.)
probe="$WORKDIR"
while :; do
  if [ -e "$probe/.git" ]; then
    [ ! -e "$probe/flake.nix" ] \
      || fail "\$WORKDIR sits inside a flake repository ($probe) — every case here would warn for an environmental reason and none of them would mean anything. Set TMPDIR to somewhere outside any flake checkout."
    log "  note: \$WORKDIR sits under a non-flake git repository ($probe), so case 4 exercises the stop-at-the-first-root branch rather than the walk-to-/ branch. Both must be silent; both are asserted."
    break
  fi
  [ "$probe" != "/" ] || break
  probe="$(dirname "$probe")"
done

# ---------------------------------------------------------------------
log "building the six layouts"
# ---------------------------------------------------------------------

# Case 1 — state inside the flake repo's own tracked tree. The layout
# docs/private-layer.md used to recommend, and the one this whole task
# exists to warn about.
INFLAKE="$WORKDIR/inflake"
mkdir -p "$INFLAKE/state/journal" "$INFLAKE/state/nested"
write_flake "$INFLAKE"
# Committed, not merely present. The rule's third stage asks git
# whether anything under the state directory is *tracked* — untracked
# content is never copied into the store, so it is not the hazard — and
# an empty directory is not a git object at all, so a fixture that only
# mkdir'd state/ would leave nothing tracked under it and would
# correctly be reported safe, making this case assert a warning that
# should not fire.
#
# What gets committed is deliberately not a journal record. Every case
# here drives `castle validate` over the directory, and that command
# parses every `journal/*.md` it finds; a planted file that is not a
# well-formed record fails the schema check and the run with it,
# turning a test about a stderr warning into a test about frontmatter.
# A `.gitkeep` inside `journal/` and a `resident-model.md` beside it
# are both real parts of the documented layout, both tracked, and
# neither is a `journal/*.md`.
: > "$INFLAKE/state/journal/.gitkeep"
: > "$INFLAKE/state/resident-model.md"
: > "$INFLAKE/state/nested/.gitkeep"
git -C "$INFLAKE" init -q
git -C "$INFLAKE" add -A
git -C "$INFLAKE" commit -q -m "fixture: a flake repo with a committed state/ inside it"

# Case 5 — the false positive the path-only rule produced, and the
# reason this rule asks git at all (docs/tasks/0030 finding 2). A
# resident's home directory is itself a git repository with a flake.nix
# in it — an ordinary dotfiles-flake setup, nothing to do with this
# project — and they leave castle.agent.stateDir unset, so the CLI
# resolves ~/.local/state/castle. Stages 1 and 2 alone find a root
# carrying a flake and warn; the layout is safe, because nothing under
# that directory is in the index and an untracked path is never copied.
# A warning on the default configuration is a warning residents learn
# to skip.
DOTFILES="$WORKDIR/dotfiles-home"
mkdir -p "$DOTFILES/.local/state/castle/journal"
write_flake "$DOTFILES"
git -C "$DOTFILES" init -q
git -C "$DOTFILES" add flake.nix
git -C "$DOTFILES" commit -q -m "fixture: a dotfiles flake in a home directory"

# Case 6 — the same shape stated explicitly rather than by omission: a
# state/ inside a flake repo that is gitignored. Also safe, also for
# the tracked-ness reason, and worth its own case because a resident
# who deliberately ignored the directory took the right precaution and
# must not be nagged for it.
IGNORED="$WORKDIR/ignored"
mkdir -p "$IGNORED/state/journal"
write_flake "$IGNORED"
printf 'state/\n' > "$IGNORED/.gitignore"
: > "$IGNORED/state/journal/.gitkeep"
: > "$IGNORED/state/resident-model.md"
git -C "$IGNORED" init -q
git -C "$IGNORED" add -A
git -C "$IGNORED" commit -q -m "fixture: a flake repo whose state/ is ignored"

# The repository `state/` becomes a submodule of, in case 2. A separate
# repository in its own right — which is also, unchanged, the
# recommended sibling layout of case 3.
STATE_SRC="$WORKDIR/state-src"
mkdir -p "$STATE_SRC/journal"
: > "$STATE_SRC/journal/.gitkeep"
git -C "$STATE_SRC" init -q
git -C "$STATE_SRC" add -A
git -C "$STATE_SRC" commit -q -m "fixture: a state repository"

# Case 2 — state as a real git submodule of a flake repo.
#
# The outer repository MUST carry a flake.nix, and that is the whole
# point of this case rather than a detail copied from case 1. A
# submodule's content is genuinely excluded from the store copy a path
# flakeref makes (verified against a real `nix eval` for
# docs/tasks/0030 — no `state/` directory appears in the store path at
# all), so the correct answer here is "safe" even though a flake.nix
# sits one directory up. A version of the rule that walked past the
# submodule's own `.git` looking for a flake.nix anywhere above would
# find the outer one and report this provably-safe layout as unsafe.
# Without a flake.nix at the outer root there is nothing for such a
# broken walk to find, and this case would silently degrade into a
# second copy of case 3, passing for the wrong reason. Do not
# "simplify" it away. The mutation assertion at the end of this file
# is what keeps that claim honest rather than merely commented.
OUTER="$WORKDIR/outer"
mkdir -p "$OUTER"
write_flake "$OUTER"
git -C "$OUTER" init -q
git -C "$OUTER" add -A
git -C "$OUTER" commit -q -m "fixture: a flake repo"
# `protocol.file.allow=always` because git refuses the file transport
# for submodules by default since 2.38 (CVE-2022-39253). A local path
# is deliberate: this fixture needs no network.
git -c protocol.file.allow=always -C "$OUTER" submodule add -q "$STATE_SRC" state
git -C "$OUTER" commit -q -m "fixture: state/ as a submodule"
[ -e "$OUTER/state/.git" ] || fail "the submodule fixture has no state/.git — the case under test does not exist"
[ -f "$OUTER/state/.git" ] || fail "state/.git is not a file — the submodule fixture is not a submodule"

# Case 3 — state in a sibling repository beside the flake repo. The
# recommended layout.
SIBLING_FLAKE="$WORKDIR/sibling-flake"
mkdir -p "$SIBLING_FLAKE"
write_flake "$SIBLING_FLAKE"
git -C "$SIBLING_FLAKE" init -q
git -C "$SIBLING_FLAKE" add -A
git -C "$SIBLING_FLAKE" commit -q -m "fixture: the config repo"
SIBLING_STATE="$WORKDIR/sibling-state"
mkdir -p "$SIBLING_STATE/nested"
git -C "$SIBLING_STATE" init -q
git -C "$SIBLING_STATE" commit -q --allow-empty -m "fixture: the state repo"

# Case 4 — a plain directory with no repository anywhere above it: what
# an unset `castle.agent.stateDir` already resolves to.
PLAIN="$WORKDIR/plain/state"
mkdir -p "$PLAIN"

# ---------------------------------------------------------------------
# The assertions themselves.
# ---------------------------------------------------------------------
# Both commands, every case. `digest` is in scope alongside `validate`
# because a resident who never runs the validator still has to be told,
# and because the two call sites can drift apart if only one is
# covered.
run_case() {
  local label="$1" statedir="$2" subcommand="$3" bin="${4:-$CASTLE}"
  CASTLE_STATE_DIR="$statedir" "$bin" "$subcommand" \
    >"$WORKDIR/out.txt" 2>"$WORKDIR/err.txt" \
    || fail "$label: castle $subcommand exited nonzero over an empty, valid journal: $(cat "$WORKDIR/err.txt")"
}

assert_warns() {
  local label="$1" statedir="$2" subcommand="$3" names="$4"
  run_case "$label" "$statedir" "$subcommand"
  grep -q '^WARNING: ' "$WORKDIR/err.txt" \
    || fail "$label: castle $subcommand printed no WARNING for a state directory inside an evaluated flake. stderr was: $(cat "$WORKDIR/err.txt")"
  grep -qF "$names" "$WORKDIR/err.txt" \
    || fail "$label: the warning does not name the repository at $names: $(cat "$WORKDIR/err.txt")"
  grep -qF "$statedir" "$WORKDIR/err.txt" \
    || fail "$label: the warning does not name the state directory $statedir: $(cat "$WORKDIR/err.txt")"
  grep -q '^WARNING: ' "$WORKDIR/out.txt" \
    && fail "$label: the warning went to stdout, where it would be folded into the document castle $subcommand writes"
  return 0
}

assert_silent() {
  local label="$1" statedir="$2" subcommand="$3"
  run_case "$label" "$statedir" "$subcommand"
  grep -q 'WARNING' "$WORKDIR/err.txt" \
    && fail "$label: castle $subcommand warned about a layout that is safe. stderr was: $(cat "$WORKDIR/err.txt")"
  grep -q 'WARNING' "$WORKDIR/out.txt" \
    && fail "$label: castle $subcommand warned on stdout about a layout that is safe"
  return 0
}

for sub in validate digest; do
  log "case 1 — state inside the flake repo ($sub): warns, and names both paths"
  assert_warns "inside-flake" "$INFLAKE/state" "$sub" "$INFLAKE"

  log "case 1b — a tracked subdirectory of it ($sub): warns too"
  assert_warns "inside-flake/nested" "$INFLAKE/state/nested" "$sub" "$INFLAKE"

  log "case 2 — state as a submodule of the flake repo ($sub): silent"
  assert_silent "submodule" "$OUTER/state" "$sub"

  log "case 3 — state in a sibling repository ($sub): silent"
  assert_silent "sibling-root" "$SIBLING_STATE" "$sub"
  assert_silent "sibling-nested" "$SIBLING_STATE/nested" "$sub"

  log "case 4 — no repository above it at all ($sub): silent"
  assert_silent "xdg-default" "$PLAIN" "$sub"

  log "case 5 — the XDG default under a dotfiles-flake home directory ($sub): silent"
  assert_silent "dotfiles-home" "$DOTFILES/.local/state/castle" "$sub"

  log "case 6 — a gitignored state/ inside a flake repo ($sub): silent"
  assert_silent "gitignored" "$IGNORED/state" "$sub"
done

# ---------------------------------------------------------------------
log "the exit code is untouched: an unsafe layout is not a schema error"
# ---------------------------------------------------------------------
# The warning must never fail an otherwise-clean journal — an
# environment fact is not a malformed record, and no edit to any record
# could fix it. Asserted for both commands over the case that warns.
CASTLE_STATE_DIR="$INFLAKE/state" "$CASTLE" validate >/dev/null 2>"$WORKDIR/err.txt" \
  || fail "castle validate exited nonzero over a clean journal purely because of the layout warning"
grep -q '^OK: ' <(CASTLE_STATE_DIR="$INFLAKE/state" "$CASTLE" validate 2>/dev/null) \
  || fail "castle validate did not report the journal clean"
CASTLE_STATE_DIR="$INFLAKE/state" "$CASTLE" digest >/dev/null 2>&1 \
  || fail "castle digest exited nonzero purely because of the layout warning"

# ---------------------------------------------------------------------
log "and castle dispatch stays silent, because it runs every minute"
# ---------------------------------------------------------------------
# Deliberately not a call site (docs/tasks/0030 §2): castle-dispatch.timer
# fires this once a minute whether or not there is work, and a warning
# there would either become log spam or need de-duplication state of its
# own. Asserted rather than left as prose, since adding the call would
# be a one-line change nobody would otherwise notice.
CASTLE_STATE_DIR="$INFLAKE/state" "$CASTLE" dispatch --watermark-only \
  >"$WORKDIR/out.txt" 2>"$WORKDIR/err.txt" \
  || fail "castle dispatch --watermark-only failed: $(cat "$WORKDIR/err.txt")"
grep -q 'WARNING' "$WORKDIR/err.txt" "$WORKDIR/out.txt" \
  && fail "castle dispatch printed the layout warning — it runs once a minute under a timer, so this is log spam by design"

# ---------------------------------------------------------------------
log "with no git to ask, the rule still warns — and says what it did not check"
# ---------------------------------------------------------------------
# `git` reaches a session only through the optional modules/dev, so a
# host running the agent layer without it genuinely has none. The rule
# then cannot run its third stage, and the direction it fails in is a
# decision rather than an accident: it warns on what stages 1 and 2
# established, and the message names the untracked case as the one it
# could not rule out. A false positive costs a paragraph of reading; a
# silent miss costs a published journal.
#
# A PATH holding python3 and nothing else. `castle` is stdlib-only, so
# this is enough to run it — which is itself the reason this fixture
# can exist at all.
NOGIT_BIN="$WORKDIR/bin-nogit"
mkdir -p "$NOGIT_BIN"
ln -s "$(command -v python3)" "$NOGIT_BIN/python3"
PATH="$NOGIT_BIN" command -v git >/dev/null \
  && fail "the no-git fixture still has git on its PATH, so it proves nothing"

env PATH="$NOGIT_BIN" CASTLE_STATE_DIR="$INFLAKE/state" "$CASTLE" validate \
  >"$WORKDIR/out.txt" 2>"$WORKDIR/err.txt" \
  || fail "castle validate failed with no git on PATH: $(cat "$WORKDIR/err.txt")"
grep -q '^WARNING: ' "$WORKDIR/err.txt" \
  || fail "with no git to ask, the committed-inside-a-flake case drew no warning at all — the fallback fails in the wrong direction"
grep -qF 'not checked' "$WORKDIR/err.txt" \
  || fail "the fallback warning does not say that tracked-ness went unchecked, so it claims a git-verified fact no git verified: $(cat "$WORKDIR/err.txt")"
grep -qF 'PATH' "$WORKDIR/err.txt" \
  || fail "the fallback warning does not say why it could not check: $(cat "$WORKDIR/err.txt")"

# And the hedged warning reaches the safe-but-unverifiable case too,
# which is the honest cost of the fallback rather than a defect: with
# no git, an ignored state/ is indistinguishable from a committed one.
env PATH="$NOGIT_BIN" CASTLE_STATE_DIR="$IGNORED/state" "$CASTLE" validate \
  >/dev/null 2>"$WORKDIR/err.txt" || fail "castle validate failed on the ignored case with no git"
grep -q '^WARNING: ' "$WORKDIR/err.txt" \
  || fail "the no-git fallback did not warn on the ignored case — it cannot tell that case apart, so silence there would mean it is not falling back at all"

# The contrast that proves the two branches are actually different:
# with git present, that same directory is silent.
assert_silent "gitignored (git present)" "$IGNORED/state" validate

# ---------------------------------------------------------------------
log "mutation: a walk that does not stop at the first repository root fails case 2"
# ---------------------------------------------------------------------
# Case 2 asserts a *silence*, and a silence passes for any number of
# wrong reasons — a rule that never warns at all satisfies it. This
# step proves the case is load-bearing by breaking the one property it
# exists to defend and checking that the fixture notices.
#
# The mutation is the smallest edit that expresses "do not stop at the
# first repository root": the real rule's walk stops at the first
# directory carrying a .git, whatever it finds there, and the mutant
# keeps walking until it finds one that carries a flake.nix as well.
# So the mutant sails past the submodule's own .git, reaches the outer
# flake repo, finds the gitlink `state` tracked in that repo's index,
# and warns about a layout that is provably safe.
#
# This is not a second implementation of the rule maintained alongside
# the first — it is a two-line patch applied to the real file at
# runtime. If `_state_layout_finding` is rewritten such that the anchor
# below no longer matches, this step fails loudly rather than quietly
# passing, and whoever rewrote it should re-express the same mutation
# rather than delete this check.
MUTANT="$WORKDIR/castle-mutant"
python3 - "$CASTLE" "$MUTANT" <<'MUTATE_PY'
import pathlib
import sys

real, mutant = sys.argv[1], sys.argv[2]
src = pathlib.Path(real).read_text()
anchor = '''        if (directory / ".git").exists():
            root = directory
            break
'''
patched = '''        if (directory / ".git").exists() and (directory / "flake.nix").exists():
            root = directory
            break
'''
if src.count(anchor) != 1:
    sys.stderr.write(
        "the mutation anchor matched %d times, not once — _state_layout_finding "
        "has been rewritten. Re-express the same mutation (a walk that does not "
        "stop at the first repository root) against the new shape; do not delete "
        "this check, which is the only thing proving the submodule case is not "
        "vacuous.\n" % src.count(anchor)
    )
    raise SystemExit(1)
pathlib.Path(mutant).write_text(src.replace(anchor, patched, 1))
MUTATE_PY
chmod +x "$MUTANT"

# The mutant must still be right about everything the fixture does not
# distinguish — otherwise it proves nothing about *this* property.
run_case "mutant/inside-flake" "$INFLAKE/state" validate "$MUTANT"
grep -q '^WARNING: ' "$WORKDIR/err.txt" || fail "the mutant does not warn on case 1, so it is broken in some other way and proves nothing here"
run_case "mutant/xdg-default" "$PLAIN" validate "$MUTANT"
grep -q 'WARNING' "$WORKDIR/err.txt" && fail "the mutant warns on case 4, so it is broken in some other way and proves nothing here"

run_case "mutant/submodule" "$OUTER/state" validate "$MUTANT"
grep -q '^WARNING: ' "$WORKDIR/err.txt" \
  || fail "a walk that does not stop at the first repository root did NOT warn on the submodule case — which means the submodule fixture is not load-bearing (most likely the outer repo lost its flake.nix), and case 2 above is passing vacuously"

# ---------------------------------------------------------------------
log "no home-shaped path in anything this fixture commits to the repo"
# ---------------------------------------------------------------------
# CLAUDE.md's hard rule, checked mechanically rather than trusted. Every
# path this harness touches is $WORKDIR-derived, so unlike
# config-target.sh next door there is no placeholder to allow through —
# the only permitted match is the line that names the pattern, tagged
# explicitly rather than left to exclude itself by coincidence the way
# that file's version does.
LEAKS="$(grep -nE '(/home/|\$HOME)' "${BASH_SOURCE[0]}" | grep -v 'NOT-A-LEAK' || true)"  # NOT-A-LEAK
[ -z "$LEAKS" ] || fail "a home-shaped path leaked into a committed fixture file:
$LEAKS"

log "all assertions passed"
