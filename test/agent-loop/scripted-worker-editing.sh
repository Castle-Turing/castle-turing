#!/usr/bin/env bash
# test/agent-loop/scripted-worker-editing.sh — a worker tenant that
# proposes by EDITING ITS COPY, the way the reference tenant does since
# docs/tasks/0053-diffs-are-generated-not-composed.md.
#
# Every other tenant fixture in this directory writes a diff to
# $CASTLE_DIFF_FILE. This one writes none at all: it edits files under
# $CASTLE_EDIT_DIR and lets `castle work` generate the patch, which is
# the whole mechanism 0053 added and the only thing generated-diff.sh
# can assert against.
#
# It reads the continuation packet on stdin, takes everything else from
# the environment, and decides what to propose from markers in the
# request text — nothing model-shaped, nothing non-deterministic.
#
# **It never writes inside a configured checkout.** It writes under
# $CASTLE_EDIT_DIR, to $CASTLE_TARGET_FILE, and — in the one scenario
# that exists to prove the harness prefers the generated patch — to
# $CASTLE_DIFF_FILE. generated-diff.sh asserts the checkouts never moved
# after every scenario.
#
# THE WORKER MUST NOT DEPLOY, and neither does this.
set -euo pipefail

: "${CASTLE_REQUEST_ID:?scripted-worker-editing.sh: CASTLE_REQUEST_ID must be set}"
: "${CASTLE_DIFF_FILE:?scripted-worker-editing.sh: CASTLE_DIFF_FILE must be set}"
: "${CASTLE_TARGET_FILE:?scripted-worker-editing.sh: CASTLE_TARGET_FILE must be set}"
: "${CASTLE_EDIT_DIR:?scripted-worker-editing.sh: CASTLE_EDIT_DIR must be set}"
: "${CASTLE_PRIVATE_ROOT:?scripted-worker-editing.sh: CASTLE_PRIVATE_ROOT must be set}"

say() { printf 'editing-worker: %s\n' "$*"; }

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
errand_records="$SCRATCH/packet"
cat > "$errand_records"
packet_has() { grep -qF -- "$1" "$errand_records"; }
token_after() { sed -n "s/.*$1-\([A-Za-z0-9]*\).*/\1/p" "$errand_records" | head -1; }

PRIV_COPY="$CASTLE_EDIT_DIR/private"
MECH_COPY="$CASTLE_EDIT_DIR/mechanism"

# The one edit every ordinary scenario makes: rewrite the marker line in
# the copy, in place, with sed. `sed -i` on a file in the copy is not a
# write under a configured root — the copy is the point of 0053.
rewrite_marker() {
  # Usage: rewrite_marker <copy root> <repo-relative path> <token>
  #
  # The leading whitespace is captured and put back, so a marker inside
  # an indented block keeps its indentation and the hunk stays a
  # one-line change. A rewrite that changed nothing is a fixture that
  # would assert nothing, so it stops the turn rather than reporting
  # success — the same guard scripted-worker-applyable.sh keeps.
  local root="$1" rel="$2" token="$3"
  [ -f "$root/$rel" ] || { printf 'editing-worker: %s is not in my copy\n' "$rel" >&2; exit 2; }
  cp "$root/$rel" "$SCRATCH/before"
  sed -i "s/^\( *\)# GENDIFF-MARKER: .*/\1# GENDIFF-MARKER: $token/" "$root/$rel"
  cmp -s "$SCRATCH/before" "$root/$rel" \
    && { printf 'editing-worker: %s already carries token %s\n' "$rel" "$token" >&2; exit 2; }
  return 0
}

# What the tenant can see of its own copy, printed on stdout so the
# harness can assert on the record rather than on a side channel. These
# are the properties docs/tasks/0053 §1 claims about what gets mirrored.
if packet_has "GENDIFF-REPORT"; then
  say "reporting on the copy I was given"
  if cmp -s "$PRIV_COPY/resident.nix" "$CASTLE_PRIVATE_ROOT/resident.nix"; then
    say "COPY-BYTES-MATCH"
  else
    say "COPY-BYTES-DIFFER"
  fi
  [ -e "$PRIV_COPY/link.nix" ] && say "COPY-HAS-SYMLINK" || say "COPY-HAS-NO-SYMLINK"
  [ -e "$PRIV_COPY/untracked.nix" ] && say "COPY-HAS-UNTRACKED" || say "COPY-HAS-NO-UNTRACKED"
  [ -e "$PRIV_COPY/.git" ] && say "COPY-HAS-GIT" || say "COPY-HAS-NO-GIT"
  [ -d "$MECH_COPY" ] && say "COPY-HAS-MECHANISM" || say "COPY-HAS-NO-MECHANISM"
  exit 0
fi

if packet_has "GENDIFF-NOTHING"; then
  say "nothing here warrants a change, so I am editing nothing"
  exit 0
fi

if packet_has "GENDIFF-DELETE"; then
  # A tenant CAN remove a file from its own copy. What it cannot do is
  # have that read as a deletion: absence means "unchanged", which is
  # the conservative reading docs/tasks/0053 §5 argues for, and the
  # harness asserts no deletion reaches the patch.
  say "removing a file from my copy, which proposes nothing"
  rm -f "$PRIV_COPY/del-me.nix"
  printf 'private\n' > "$CASTLE_TARGET_FILE"
  exit 0
fi

if packet_has "GENDIFF-BOTH"; then
  say "editing both copies, which is a proposal spanning two repositories"
  rewrite_marker "$PRIV_COPY" resident.nix bothprivate
  rewrite_marker "$MECH_COPY" "hosts/example/default.nix" bothmechanism
  printf 'private\n' > "$CASTLE_TARGET_FILE"
  exit 0
fi

if packet_has "GENDIFF-MECHANISM"; then
  say "this one belongs in the framework checkout"
  rewrite_marker "$MECH_COPY" "hosts/example/default.nix" mechanismedit
  printf 'mechanism\n' > "$CASTLE_TARGET_FILE"
  exit 0
fi

if packet_has "GENDIFF-WRONGSTAMP"; then
  say "editing the private copy and stamping the other word, which is the confusion worth catching"
  rewrite_marker "$PRIV_COPY" resident.nix wrongstamp
  printf 'mechanism\n' > "$CASTLE_TARGET_FILE"
  exit 0
fi

if packet_has "GENDIFF-ALSODIFF"; then
  say "editing my copy and also composing a diff by hand, which contradicts itself"
  rewrite_marker "$PRIV_COPY" resident.nix alsodiff
  cat > "$CASTLE_DIFF_FILE" <<'HANDDIFF'
--- a/hand-written.nix
+++ b/hand-written.nix
@@ -1 +1 @@
-HAND-WRITTEN-BEFORE
+HAND-WRITTEN-AFTER
HANDDIFF
  printf 'private\n' > "$CASTLE_TARGET_FILE"
  exit 0
fi

if packet_has "GENDIFF-NEWFILE"; then
  TOKEN="$(token_after GENDIFF-NEWFILE)"
  say "proposing a file this configuration does not have yet ($TOKEN)"
  printf '# Created by the editing fixture tenant, harness fixture only.\n# GENDIFF-MARKER: %s\n' \
    "$TOKEN" > "$PRIV_COPY/hosts/example/new-$TOKEN.nix"
  printf 'private\n' > "$CASTLE_TARGET_FILE"
  exit 0
fi

if packet_has "GENDIFF-TWOFILE"; then
  say "proposing one change that spans two files in one checkout"
  rewrite_marker "$PRIV_COPY" resident.nix twofile
  rewrite_marker "$PRIV_COPY" "hosts/example/default.nix" twofile
  printf 'private\n' > "$CASTLE_TARGET_FILE"
  exit 0
fi

TOKEN="$(token_after GENDIFF-ONELINE)"
if [ -n "$TOKEN" ]; then
  say "proposing a one-line change to the private layer"
  rewrite_marker "$PRIV_COPY" resident.nix "$TOKEN"
  printf 'private\n' > "$CASTLE_TARGET_FILE"
  exit 0
fi

say "no fixture marker in this errand; proposing nothing"
exit 0
