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
log "building the four layouts"
# ---------------------------------------------------------------------

# Case 1 — state inside the flake repo's own tracked tree. The layout
# docs/private-layer.md used to recommend, and the one this whole task
# exists to warn about.
INFLAKE="$WORKDIR/inflake"
mkdir -p "$INFLAKE/state/journal"
write_flake "$INFLAKE"
git -C "$INFLAKE" init -q
git -C "$INFLAKE" add -A
git -C "$INFLAKE" commit -q -m "fixture: a flake repo with state/ inside it"

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

  log "case 1b — a subdirectory of it ($sub): warns too"
  assert_warns "inside-flake/nested" "$INFLAKE/state/nested" "$sub" "$INFLAKE"

  log "case 2 — state as a submodule of the flake repo ($sub): silent"
  assert_silent "submodule" "$OUTER/state" "$sub"

  log "case 3 — state in a sibling repository ($sub): silent"
  assert_silent "sibling-root" "$SIBLING_STATE" "$sub"
  assert_silent "sibling-nested" "$SIBLING_STATE/nested" "$sub"

  log "case 4 — no repository above it at all ($sub): silent"
  assert_silent "xdg-default" "$PLAIN" "$sub"
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
log "mutation: a walk that does not stop at the first repository root fails case 2"
# ---------------------------------------------------------------------
# Case 2 asserts a *silence*, and a silence passes for any number of
# wrong reasons — a rule that never warns at all satisfies it. This
# step proves the case is load-bearing by breaking the one property it
# exists to defend and checking that the fixture notices.
#
# The mutation is the smallest edit that expresses "do not stop at the
# first repository root": where the real rule returns None on finding a
# repository root with no flake.nix, the mutant keeps walking, so it
# sails past the submodule's own .git, reaches the outer flake repo,
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
anchor = '''        if not (directory / "flake.nix").exists():
            return None
'''
patched = '''        if not (directory / "flake.nix").exists():
            continue
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
