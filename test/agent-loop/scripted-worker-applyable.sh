#!/usr/bin/env bash
# test/agent-loop/scripted-worker-applyable.sh — a worker tenant whose
# diffs REALLY APPLY (docs/tasks/0026-apply-validate.md's verification
# plan).
#
# Every other tenant fixture in this directory produces a deliberately
# synthetic diff naming a file that does not exist — correct for a
# harness proving nothing is ever applied, and useless for one proving
# something is. This one computes its diff from the actual current
# contents of `$CASTLE_PRIVATE_ROOT`, so `git apply` can consume it.
#
# It reads the continuation packet on stdin, takes everything else from
# the environment, and "decides" what to propose from markers in the
# request text — nothing model-shaped, nothing non-deterministic.
#
# **It never writes inside the checkout**, exactly like every other
# tenant fixture here: it copies the file it is proposing a change to
# out to a scratch directory, edits the copy, and diffs the two.
# apply.sh's `assert_private_untouched` is the teeth on that claim after
# every turn that is not followed by an apply.
#
# Its second output is the byte-exact post-image of every path it
# expects to exist afterwards, written under
# $CASTLE_APPLYABLE_EXPECT_DIR with `/` flattened to `%`. That is what
# lets the harness assert the applied file is byte-identical to what the
# patch was supposed to produce, against a copy the tenant itself
# computed rather than a second, independently typed one free to drift.
#
# THE WORKER MUST NOT DEPLOY, and neither does this: it writes to
# $CASTLE_DIFF_FILE, $CASTLE_TARGET_FILE and its own scratch
# directories, and to nothing else, ever.
set -euo pipefail

: "${CASTLE_REQUEST_ID:?scripted-worker-applyable.sh: CASTLE_REQUEST_ID must be set}"
: "${CASTLE_DIFF_FILE:?scripted-worker-applyable.sh: CASTLE_DIFF_FILE must be set}"
: "${CASTLE_TARGET_FILE:?scripted-worker-applyable.sh: CASTLE_TARGET_FILE must be set}"
: "${CASTLE_PRIVATE_ROOT:?scripted-worker-applyable.sh: CASTLE_PRIVATE_ROOT must be set}"
: "${CASTLE_APPLYABLE_EXPECT_DIR:?scripted-worker-applyable.sh: CASTLE_APPLYABLE_EXPECT_DIR must be set}"

say() { printf 'applyable-worker: %s\n' "$*"; }

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

errand_records="$SCRATCH/packet"
cat > "$errand_records"
packet_has() { grep -qF -- "$1" "$errand_records"; }

: > "$CASTLE_DIFF_FILE"

# The post-image the harness will compare the applied file against,
# byte for byte. Written for every path this tenant expects to EXIST
# afterwards; a path it expects to be gone deliberately gets none, and
# the harness reads that absence as "assert it was removed."
expect() {
  # Usage: expect <repo-relative-path> <file-holding-its-post-image>
  cp "$2" "$CASTLE_APPLYABLE_EXPECT_DIR/${1//\//%}"
}

# One `diff -u` hunk set, labelled with the repository-relative path on
# both sides — the shape `git apply` reads paths out of, and the shape a
# tenant with no git can produce. `diff` exits 1 when the files differ,
# which is the ordinary case here and not an error, hence the `|| [ $? = 1 ]`.
emit_diff() {
  # Usage: emit_diff <repo-relative-path> <before-file> <after-file>
  diff -u --label "a/$1" --label "b/$1" "$2" "$3" >> "$CASTLE_DIFF_FILE" \
    || [ "$?" = 1 ]
}

# The marker line every fixture file in the private repo carries, and
# the one thing this tenant ever rewrites in one. A single line with a
# token on it keeps consecutive proposals against the same file
# genuinely distinct — each turn diffs against whatever the previous
# apply left there, which is exactly the sequence a resident's
# repository really sees.
rewrite_marker() {
  # Usage: rewrite_marker <repo-relative-path> <new-token>; echoes the
  # scratch path of the rewritten copy.
  local rel="$1" token="$2" before="$SCRATCH/before-${1//\//%}" after="$SCRATCH/after-${1//\//%}"
  cp "$CASTLE_PRIVATE_ROOT/$rel" "$before"
  sed "s/^# APPLYABLE-MARKER: .*/# APPLYABLE-MARKER: $token/" "$before" > "$after"
  cmp -s "$before" "$after" \
    && { printf 'applyable-worker: %s already carries token %s\n' "$rel" "$token" >&2; exit 2; }
  emit_diff "$rel" "$before" "$after"
  expect "$rel" "$after"
}

# The token a MODIFY-shaped errand carries, so two proposals against one
# file are never the same bytes.
marker_token() {
  sed -n 's/.*APPLYABLE-MODIFY-\([A-Za-z0-9]*\).*/\1/p' "$errand_records" | head -1
}

if packet_has "APPLYABLE-MECHANISM"; then
  # Deliberately NOT computed from any checkout: the applier refuses a
  # mechanism-targeted change before it ever looks at a patch, and a
  # fixture that could really edit this framework's own checkout is
  # exactly what `assert_mechanism_untouched` exists to make impossible.
  say "this one belongs in the framework checkout, not the private layer"
  cat >> "$CASTLE_DIFF_FILE" <<'DIFF'
--- a/modules/example (synthetic, harness fixture only)
+++ b/modules/example (synthetic, harness fixture only)
@@ -1 +1 @@
-MECHANISM-PLACEHOLDER-BEFORE
+MECHANISM-PLACEHOLDER-AFTER
DIFF
  printf 'mechanism\n' > "$CASTLE_TARGET_FILE"
  exit 0
fi

if packet_has "APPLYABLE-CREATE"; then
  say "proposing a file this configuration does not have yet"
  : > "$SCRATCH/nothing"
  printf '# Created by the applyable fixture tenant, harness fixture only.\n# APPLYABLE-MARKER: created\n' \
    > "$SCRATCH/created"
  emit_diff "hosts/example/created.nix" "$SCRATCH/nothing" "$SCRATCH/created"
  expect "hosts/example/created.nix" "$SCRATCH/created"
  printf 'private\n' > "$CASTLE_TARGET_FILE"
  exit 0
fi

if packet_has "APPLYABLE-NEWFILE-"; then
  # A creation, like APPLYABLE-CREATE, but at a path chosen per errand
  # so more than one scenario can use one. `applied-uncommitted` needs
  # its own, because that record's recovery command is different for a
  # path the change created than for one it modified.
  TOKEN="$(sed -n 's/.*APPLYABLE-NEWFILE-\([A-Za-z0-9]*\).*/\1/p' "$errand_records" | head -1)"
  say "proposing a new file this configuration does not have yet ($TOKEN)"
  : > "$SCRATCH/nothing"
  printf '# Created by the applyable fixture tenant, harness fixture only.\n# APPLYABLE-MARKER: %s\n' \
    "$TOKEN" > "$SCRATCH/newfile"
  emit_diff "hosts/example/new-$TOKEN.nix" "$SCRATCH/nothing" "$SCRATCH/newfile"
  expect "hosts/example/new-$TOKEN.nix" "$SCRATCH/newfile"
  printf 'private\n' > "$CASTLE_TARGET_FILE"
  exit 0
fi

if packet_has "APPLYABLE-FILTERED"; then
  say "proposing a change to a file the repository runs a content filter over"
  rewrite_marker "filtered.nix" "filteredchange"
  printf 'private\n' > "$CASTLE_TARGET_FILE"
  exit 0
fi

if packet_has "APPLYABLE-ODDNAMES"; then
  # Two file names git's own pathspec and encoding rules have to be
  # asked about rather than assumed: one carrying a byte that is not
  # valid UTF-8, and one carrying a `*`, which is a glob to a pathspec
  # that has not been marked literal. The harness builds both names —
  # once, with printf, so this fixture's source stays plain ASCII — and
  # passes them in, the same discipline
  # scripted-worker-byte-fidelity.sh uses for its own byte sequences.
  : "${CASTLE_APPLYABLE_ODD_NAMES:?scripted-worker-applyable.sh: CASTLE_APPLYABLE_ODD_NAMES must be set}"
  say "proposing two files whose names git has to be asked about"
  : > "$SCRATCH/nothing"
  while IFS= read -r odd; do
    [ -n "$odd" ] || continue
    printf '# Created by the applyable fixture tenant, harness fixture only.\n' \
      > "$SCRATCH/odd"
    emit_diff "$odd" "$SCRATCH/nothing" "$SCRATCH/odd"
    expect "$odd" "$SCRATCH/odd"
  done < "$CASTLE_APPLYABLE_ODD_NAMES"
  printf 'private\n' > "$CASTLE_TARGET_FILE"
  exit 0
fi

if packet_has "APPLYABLE-DELETE"; then
  say "proposing that a file stop existing"
  # A plain `diff -u` against /dev/null only truncates a file to empty —
  # git needs the `deleted file mode` header to remove it, verified by
  # running it rather than read off a manual page. The `index` line real
  # git emits is deliberately omitted: `git apply` neither needs nor
  # reads it here, and a fixture inventing a blob hash would be stating
  # something it has not computed.
  : > "$SCRATCH/nothing"
  {
    echo "diff --git a/del-me.nix b/del-me.nix"
    echo "deleted file mode 100644"
  } >> "$CASTLE_DIFF_FILE"
  diff -u --label "a/del-me.nix" --label "/dev/null" \
    "$CASTLE_PRIVATE_ROOT/del-me.nix" "$SCRATCH/nothing" >> "$CASTLE_DIFF_FILE" \
    || [ "$?" = 1 ]
  # No `expect` for it: absence is what the harness asserts.
  printf 'private\n' > "$CASTLE_TARGET_FILE"
  exit 0
fi

if packet_has "APPLYABLE-TWOFILE"; then
  say "proposing one change that spans two files"
  rewrite_marker "resident.nix" "twofile"
  rewrite_marker "hosts/example/default.nix" "twofile"
  printf 'private\n' > "$CASTLE_TARGET_FILE"
  exit 0
fi

if packet_has "APPLYABLE-OTHER"; then
  say "proposing a change to a file no other fixture here touches"
  rewrite_marker "hosts/example/default.nix" "other$(date +%s%N | tail -c 6)"
  printf 'private\n' > "$CASTLE_TARGET_FILE"
  exit 0
fi

TOKEN="$(marker_token)"
if [ -n "$TOKEN" ]; then
  say "proposing a one-line change to the private layer"
  rewrite_marker "resident.nix" "$TOKEN"
  printf 'private\n' > "$CASTLE_TARGET_FILE"
  exit 0
fi

say "no fixture marker in this errand; proposing nothing"
exit 0
