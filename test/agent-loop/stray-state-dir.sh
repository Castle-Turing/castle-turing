#!/usr/bin/env bash
# test/agent-loop/stray-state-dir.sh — a second, independent journal left
# lying around under $CASTLE_PRIVATE_ROOT
# (docs/tasks/0040-validate-stray-state-directory.md).
#
# A resident migrating state out of the flake
# (docs/tasks/0030-state-outside-the-flake.md) copies the journal to its
# new home and only then removes the old `state/` directory from the
# private checkout. On 2026-09-01 a resident skipped the removal, and a
# worker turn read the stale `state/journal` under
# `CASTLE_PRIVATE_ROOT` instead of the configured one, took its single
# ancient record for the whole journal, and reported anomalies that were
# artifacts of reading the wrong directory.
#
# This is a different hazard than state-layout.sh next door covers: that
# harness asks whether the *configured* state directory is safe to
# publish to the Nix store. This one asks whether a *second*,
# unconfigured directory shaped like a journal exists and could be
# mistaken for the real one — a question with nothing to do with git
# tracking at all, so it is exercised with no git repository anywhere in
# sight.
#
# Same conventions as state-layout.sh: plain bash, stdlib python3, no
# Nix, no models, no network, a throwaway root per case, and every path
# $WORKDIR-derived.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CASTLE="$REPO_ROOT/agent/castle"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/castle-stray-state.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT
# Canonicalised for the same reason state-layout.sh canonicalises its
# own $WORKDIR: the code under test compares realpath'd directories, so
# an uncanonicalised $WORKDIR (a symlinked $TMPDIR) would make this
# harness and the code under test disagree about identity for a reason
# that has nothing to do with the rule.
WORKDIR="$(cd "$WORKDIR" && pwd -P)"

log() { printf '>>> %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

export XDG_RUNTIME_DIR="$WORKDIR/runtime"
mkdir -p "$XDG_RUNTIME_DIR"

run_case() {
  local label="$1" statedir="$2" privateroot="$3" subcommand="$4"
  if [ -n "$privateroot" ]; then
    CASTLE_STATE_DIR="$statedir" CASTLE_PRIVATE_ROOT="$privateroot" \
      "$CASTLE" "$subcommand" >"$WORKDIR/out.txt" 2>"$WORKDIR/err.txt" \
      || fail "$label: castle $subcommand exited nonzero over an empty, valid journal: $(cat "$WORKDIR/err.txt")"
  else
    env -u CASTLE_PRIVATE_ROOT CASTLE_STATE_DIR="$statedir" \
      "$CASTLE" "$subcommand" >"$WORKDIR/out.txt" 2>"$WORKDIR/err.txt" \
      || fail "$label: castle $subcommand exited nonzero over an empty, valid journal: $(cat "$WORKDIR/err.txt")"
  fi
}

assert_warns() {
  local label="$1" statedir="$2" privateroot="$3" subcommand="$4" strayname="$5"
  run_case "$label" "$statedir" "$privateroot" "$subcommand"
  grep -q '^WARNING: ' "$WORKDIR/err.txt" \
    || fail "$label: castle $subcommand printed no WARNING for a stray journal-shaped directory. stderr was: $(cat "$WORKDIR/err.txt")"
  grep -qF "$strayname" "$WORKDIR/err.txt" \
    || fail "$label: the warning does not name the stray directory $strayname: $(cat "$WORKDIR/err.txt")"
  grep -qF "$statedir/journal" "$WORKDIR/err.txt" \
    || fail "$label: the warning does not name the configured journal $statedir/journal: $(cat "$WORKDIR/err.txt")"
  grep -qF 'private-layer.md' "$WORKDIR/err.txt" \
    || fail "$label: the warning does not point at the migration doc: $(cat "$WORKDIR/err.txt")"
  grep -q '^WARNING: ' "$WORKDIR/out.txt" \
    && fail "$label: the warning went to stdout, where it would be folded into the document castle $subcommand writes"
  return 0
}

assert_silent() {
  local label="$1" statedir="$2" privateroot="$3" subcommand="$4"
  run_case "$label" "$statedir" "$privateroot" "$subcommand"
  grep -q 'WARNING' "$WORKDIR/err.txt" \
    && fail "$label: castle $subcommand warned about a layout with no stray journal. stderr was: $(cat "$WORKDIR/err.txt")"
  grep -q 'WARNING' "$WORKDIR/out.txt" \
    && fail "$label: castle $subcommand warned on stdout about a layout with no stray journal"
  return 0
}

# ---------------------------------------------------------------------
log "case 1 — no CASTLE_PRIVATE_ROOT at all: silent"
# ---------------------------------------------------------------------
# The check has nothing to compare against and must not guess.
CASE1_STATE="$WORKDIR/case1-state"
mkdir -p "$CASE1_STATE"
for sub in validate digest; do
  assert_silent "no-private-root" "$CASE1_STATE" "" "$sub"
done

# ---------------------------------------------------------------------
log "case 2 — a private root with no state/journal under it: silent"
# ---------------------------------------------------------------------
CASE2_STATE="$WORKDIR/case2-state"
CASE2_PRIVATE="$WORKDIR/case2-private"
mkdir -p "$CASE2_STATE" "$CASE2_PRIVATE"
for sub in validate digest; do
  assert_silent "clean-private-root" "$CASE2_STATE" "$CASE2_PRIVATE" "$sub"
done

# ---------------------------------------------------------------------
log "case 3 — a stray state/journal under the private root: warns, naming both paths and the migration doc"
# ---------------------------------------------------------------------
CASE3_STATE="$WORKDIR/case3-state"
CASE3_PRIVATE="$WORKDIR/case3-private"
mkdir -p "$CASE3_STATE" "$CASE3_PRIVATE/state/journal"
# An old record left behind by the migration — a well-formed one, so a
# careless implementation that folded the stray directory into
# `journal_dir()`'s glob (it must not) fails this test for the right
# reason rather than a schema error masking it.
cat > "$CASE3_PRIVATE/state/journal/0001-stray.md" <<'EOF'
id: 0001-stray
type: request
provenance: resident
created: 2025-01-01T00:00:00Z

Fixture: a stray record, from before the migration.
EOF
for sub in validate digest; do
  assert_warns "stray-journal" "$CASE3_STATE" "$CASE3_PRIVATE" "$sub" "$CASE3_PRIVATE/state/journal"
done

# ---------------------------------------------------------------------
log "case 3b — the exit code is untouched: a stray directory is not a schema error"
# ---------------------------------------------------------------------
CASTLE_STATE_DIR="$CASE3_STATE" CASTLE_PRIVATE_ROOT="$CASE3_PRIVATE" "$CASTLE" validate \
  >/dev/null 2>"$WORKDIR/err.txt" \
  || fail "castle validate exited nonzero over a clean journal purely because of the stray-directory warning"
grep -q '^OK: ' <(CASTLE_STATE_DIR="$CASE3_STATE" CASTLE_PRIVATE_ROOT="$CASE3_PRIVATE" "$CASTLE" validate 2>/dev/null) \
  || fail "castle validate did not report the configured journal clean"

# ---------------------------------------------------------------------
log "case 4 — CASTLE_STATE_DIR pointed straight at \$CASTLE_PRIVATE_ROOT/state: silent, because it is not stray"
# ---------------------------------------------------------------------
# The undocumented-but-real layout where the resident configured their
# journal to live inside the private root's own state/ directory. The
# candidate and the configured directory resolve to the exact same path,
# so this is the directory in actual use, not a leftover — even though
# state-layout.sh's rule may separately have something to say about it
# once a flake is involved (out of scope here; no git repo exists in
# this fixture at all).
CASE4_PRIVATE="$WORKDIR/case4-private"
mkdir -p "$CASE4_PRIVATE/state/journal"
for sub in validate digest; do
  assert_silent "state-dir-is-the-candidate" "$CASE4_PRIVATE/state" "$CASE4_PRIVATE" "$sub"
done

# ---------------------------------------------------------------------
log "case 5 — a symlink at the stray path resolving to the real journal: silent"
# ---------------------------------------------------------------------
CASE5_STATE="$WORKDIR/case5-state"
CASE5_PRIVATE="$WORKDIR/case5-private"
mkdir -p "$CASE5_STATE/journal" "$CASE5_PRIVATE/state"
ln -s "$CASE5_STATE/journal" "$CASE5_PRIVATE/state/journal"
for sub in validate digest; do
  assert_silent "symlinked-to-real-journal" "$CASE5_STATE" "$CASE5_PRIVATE" "$sub"
done

# ---------------------------------------------------------------------
log "and castle dispatch stays silent, because it runs every minute"
# ---------------------------------------------------------------------
# Deliberately not a call site, same reasoning state-layout.sh already
# gives for the layout warning: castle-dispatch.timer fires once a
# minute whether or not there is work, and a warning there would either
# become log spam or need de-duplication state of its own.
CASTLE_STATE_DIR="$CASE3_STATE" CASTLE_PRIVATE_ROOT="$CASE3_PRIVATE" "$CASTLE" dispatch --watermark-only \
  >"$WORKDIR/out.txt" 2>"$WORKDIR/err.txt" \
  || fail "castle dispatch --watermark-only failed: $(cat "$WORKDIR/err.txt")"
grep -q 'WARNING' "$WORKDIR/out.txt" "$WORKDIR/err.txt" \
  && fail "castle dispatch printed the stray-journal warning — it runs once a minute under a timer, so this is log spam by design"

# ---------------------------------------------------------------------
log "no home-shaped path in anything this fixture commits to the repo"
# ---------------------------------------------------------------------
LEAKS="$(grep -nE '(/home/|\$HOME)' "${BASH_SOURCE[0]}" | grep -v 'NOT-A-LEAK' || true)"  # NOT-A-LEAK
[ -z "$LEAKS" ] || fail "a home-shaped path leaked into a committed fixture file:
$LEAKS"

log "all assertions passed"
