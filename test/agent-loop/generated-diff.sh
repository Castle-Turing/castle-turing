#!/usr/bin/env bash
# test/agent-loop/generated-diff.sh — a proposed diff is GENERATED from
# what a tenant edited, and the patch that reaches the journal applies
# (docs/tasks/0053-diffs-are-generated-not-composed.md's verification
# plan).
#
# **Its own file rather than more scenarios in dispatch-test.sh**, for
# the reason apply.sh gives about itself: this one needs a real git
# checkout it can run `git apply --check` against after every turn, and
# the bar it holds the harness to is not "a record was written" but "the
# bytes in the journal are a patch git accepts."
#
# The regression at the bottom is the shape that produced this task. On
# 2026-09-05 the first live errand to make a real proposal composed its
# own unified diff, and git refused it: the hunk header declared one
# fewer new line than the hunk carried, and the blank context line was
# written as an empty line rather than as a single space. That patch's
# content is a resident's private configuration and is not reproduced
# here — CLAUDE.md's rule against writing the private layer into this
# repository outranks quoting evidence verbatim. What is reproduced is
# its exact shape on invented content, with both defects and with each
# defect alone, because which one was fatal is a measurement and not an
# assumption: see the case itself.
#
# Same conventions as apply.sh otherwise: real git checkouts under
# $WORKDIR, a state repository beside them rather than inside either, a
# git identity scoped to this process, the notify stub, plain bash and
# stdlib python3, no Nix, zero models, zero network. Nothing in here is
# a real path, a real complaint or a real decision.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CASTLE="$REPO_ROOT/agent/castle"
WORKER="$REPO_ROOT/test/agent-loop/scripted-worker-editing.sh"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/castle-generated-diff.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT
WORKDIR="$(cd "$WORKDIR" && pwd -P)"

log() { printf '>>> %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

export GIT_AUTHOR_NAME="castle-generated-diff-fixture"
export GIT_AUTHOR_EMAIL="fixture@example.invalid"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

# ---------------------------------------------------------------------
# Two synthetic checkouts and a state repository beside them.
# ---------------------------------------------------------------------
# The blank line inside resident.nix is deliberate and load-bearing: it
# sits within three lines of the marker every scenario rewrites, so
# every generated hunk carries a BLANK CONTEXT LINE — the thing defect 2
# of the finding got wrong, and the thing a resident's own git
# configuration can still get wrong through `diff.suppressBlankEmpty`.
PRIVATE="$WORKDIR/private"
mkdir -p "$PRIVATE/hosts/example"
cat > "$PRIVATE/resident.nix" <<'EOF'
# Synthetic private layer, harness fixture only.
{
  castle.admin.username = "resident";

  # GENDIFF-MARKER: start

  castle.display.scale = 1.0;
}
EOF
cat > "$PRIVATE/hosts/example/default.nix" <<'EOF'
# Synthetic host module, harness fixture only.

# GENDIFF-MARKER: start
{ }
EOF
cat > "$PRIVATE/del-me.nix" <<'EOF'
# Synthetic file a scenario tries, and fails, to propose removing.
{ }
EOF
ln -s resident.nix "$PRIVATE/link.nix"
cat > "$PRIVATE/.gitignore" <<'EOF'
scratch-*
EOF
git -C "$PRIVATE" init -q
git -C "$PRIVATE" add -A
git -C "$PRIVATE" commit -q -m "fixture: a synthetic private layer"
# Untracked on purpose: `git ls-files` is what decides the copy's
# contents, so this file must not appear in it.
printf 'untracked, and not the copy\n' > "$PRIVATE/untracked.nix"

MECHANISM="$WORKDIR/mechanism"
mkdir -p "$MECHANISM/hosts/example"
cat > "$MECHANISM/hosts/example/default.nix" <<'EOF'
# Synthetic framework host module, harness fixture only.

# GENDIFF-MARKER: start
{ }
EOF
git -C "$MECHANISM" init -q
git -C "$MECHANISM" add -A
git -C "$MECHANISM" commit -q -m "fixture: a synthetic framework checkout"

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

PRIVATE_HEAD="$(git -C "$PRIVATE" rev-parse HEAD)"
MECHANISM_HEAD="$(git -C "$MECHANISM" rev-parse HEAD)"

# ---------------------------------------------------------------------
# Helpers, copied from apply.sh rather than shared: these are plain bash
# harnesses with no library between them.
# ---------------------------------------------------------------------
referencing() {
  local rtype="$1" id="$2"
  grep -l "^refs: .*$id" "$JOURNAL"/*-"$rtype"-*.md 2>/dev/null || true
}
newest_of() {
  xargs -r stat -c '%.Y	%n' 2>/dev/null | sort -k1,1n | tail -1 | cut -f2-
}
newest_result_for() { referencing result "$1" | newest_of; }
field_of() { sed -n "s/^$2: //p" "$1" | head -1; }

# Nothing this suite does may move either checkout. The tenant edits a
# COPY; that claim is worth nothing without a check on the original
# after every single turn, including the turns that fail.
assert_checkouts_untouched() {
  local where="$1"
  [ -z "$(git -C "$PRIVATE" status --porcelain --untracked-files=no)" ] \
    || fail "$where: the private checkout has uncommitted changes: $(git -C "$PRIVATE" status --porcelain)"
  [ "$(git -C "$PRIVATE" rev-parse HEAD)" = "$PRIVATE_HEAD" ] \
    || fail "$where: the private checkout moved"
  [ -z "$(git -C "$MECHANISM" status --porcelain --untracked-files=no)" ] \
    || fail "$where: the mechanism checkout has uncommitted changes"
  [ "$(git -C "$MECHANISM" rev-parse HEAD)" = "$MECHANISM_HEAD" ] \
    || fail "$where: the mechanism checkout moved"
}

# One turn. Echoes "<request-id> <result-path>".
run_turn() {
  local marker="$1" request result
  request="$("$CASTLE" ask "GENDIFF fixture $marker: an invented complaint whose fix is a one-line change.")"
  "$CASTLE" work "$request" >/dev/null
  result="$(newest_result_for "$request")"
  [ -n "$result" ] || fail "$marker: the turn wrote no result record"
  assert_checkouts_untouched "$marker"
  printf '%s %s\n' "$request" "$result"
}

sidecar_of() { printf '%s\n' "$JOURNAL/$(basename "$1" .md).patch"; }

# ---------------------------------------------------------------------
log "a one-line edit becomes a patch git applies, and the tenant wrote no diff at all"
# ---------------------------------------------------------------------
read -r REQ1 RESULT1 <<<"$(run_turn "GENDIFF-ONELINE-alpha")"
PATCH1="$(sidecar_of "$RESULT1")"
[ -f "$PATCH1" ] || fail "the turn produced no .patch sidecar: $(cat "$RESULT1")"
git -C "$PRIVATE" apply --check "$PATCH1" \
  || fail "the generated patch does not apply to the checkout it was generated from: $(cat "$PATCH1")"
grep -qxF -- "--- a/resident.nix" "$PATCH1" \
  || fail "the patch does not name the path it changes as the applier expects: $(cat "$PATCH1")"
grep -qF "+  # GENDIFF-MARKER: alpha" "$PATCH1" \
  || fail "the patch does not carry the change the tenant made: $(cat "$PATCH1")"
[ "$(field_of "$RESULT1" target)" = "private" ] \
  || fail "the result does not target the checkout the tenant edited: $(field_of "$RESULT1" target)"
[ "$(field_of "$RESULT1" outcome)" = "completed" ] \
  || fail "the turn did not complete: $(field_of "$RESULT1" outcome)"

log "  -- and its blank context line is a single space, which is defect 2 of the finding"
grep -qx ' ' "$PATCH1" \
  || fail "no blank context line in the patch at all, so this case proves nothing: $(cat -A "$PATCH1")"
if grep -qx '' "$PATCH1"; then
  fail "the patch carries an EMPTY context line, which is the shape git refuses to parse: $(cat -A "$PATCH1")"
fi

log "  -- and applying it really does produce the file the tenant meant"
APPLY_PROBE="$WORKDIR/apply-probe"
rm -rf "$APPLY_PROBE"
git clone -q "$PRIVATE" "$APPLY_PROBE"
git -C "$APPLY_PROBE" apply "$PATCH1" \
  || fail "the patch checked clean and then failed to apply"
grep -qxF "  # GENDIFF-MARKER: alpha" "$APPLY_PROBE/resident.nix" \
  || fail "applying the patch did not produce the change: $(cat "$APPLY_PROBE/resident.nix")"

# ---------------------------------------------------------------------
log "the copy the tenant is given is the checkout's tracked files, and nothing else"
# ---------------------------------------------------------------------
read -r _ RESULT_REPORT <<<"$(run_turn "GENDIFF-REPORT")"
for claim in COPY-BYTES-MATCH COPY-HAS-NO-SYMLINK COPY-HAS-NO-UNTRACKED COPY-HAS-NO-GIT COPY-HAS-MECHANISM; do
  grep -qF "$claim" "$RESULT_REPORT" \
    || fail "the tenant did not find $claim in its copy: $(cat "$RESULT_REPORT")"
done

# ---------------------------------------------------------------------
log "a change spanning two files in one checkout is one patch (docs/tasks/0053 §2)"
# ---------------------------------------------------------------------
read -r _ RESULT2 <<<"$(run_turn "GENDIFF-TWOFILE")"
PATCH2="$(sidecar_of "$RESULT2")"
git -C "$PRIVATE" apply --check "$PATCH2" \
  || fail "the two-file patch does not apply: $(cat "$PATCH2")"
grep -qxF -- "--- a/resident.nix" "$PATCH2" \
  || fail "the two-file patch is missing one of its files: $(cat "$PATCH2")"
grep -qxF -- "--- a/hosts/example/default.nix" "$PATCH2" \
  || fail "the two-file patch is missing one of its files: $(cat "$PATCH2")"

# ---------------------------------------------------------------------
log "a file the checkout does not have yet is a creation git accepts"
# ---------------------------------------------------------------------
read -r _ RESULT3 <<<"$(run_turn "GENDIFF-NEWFILE-beta")"
PATCH3="$(sidecar_of "$RESULT3")"
git -C "$PRIVATE" apply --check "$PATCH3" \
  || fail "the creation patch does not apply: $(cat "$PATCH3")"
grep -qF "new file mode" "$PATCH3" \
  || fail "the creation carries no new-file header, so git would truncate rather than create: $(cat "$PATCH3")"

# ---------------------------------------------------------------------
log "a file removed from the copy is never read as a deletion (docs/tasks/0053 §5)"
# ---------------------------------------------------------------------
# The conservative reading, and the reason for it: a copy that fell
# short for any reason would otherwise become a patch deleting a
# resident's files.
read -r _ RESULT4 <<<"$(run_turn "GENDIFF-DELETE")"
PATCH4="$(sidecar_of "$RESULT4")"
[ ! -f "$PATCH4" ] \
  || fail "removing a file from the copy produced a patch: $(cat "$PATCH4")"
grep -qF "(no diff produced" "$RESULT4" \
  || fail "the record does not say the turn proposed nothing: $(cat "$RESULT4")"
[ -f "$PRIVATE/del-me.nix" ] || fail "the checkout lost the file the tenant removed from its own copy"

# ---------------------------------------------------------------------
log "a change spanning BOTH checkouts is refused, and the refusal is in the record"
# ---------------------------------------------------------------------
read -r _ RESULT5 <<<"$(run_turn "GENDIFF-BOTH")"
[ ! -f "$(sidecar_of "$RESULT5")" ] \
  || fail "a proposal spanning two repositories was recorded as an applyable patch"
grep -qF "A proposal applies to one checkout" "$RESULT5" \
  || fail "the record does not say why nothing was proposed: $(cat "$RESULT5")"
[ -z "$(field_of "$RESULT5" target)" ] \
  || fail "a refused proposal still carries a target: $(field_of "$RESULT5" target)"

# ---------------------------------------------------------------------
log "the checkout is taken from the copy the tenant edited, not from the word it stamped"
# ---------------------------------------------------------------------
read -r _ RESULT6 <<<"$(run_turn "GENDIFF-WRONGSTAMP")"
[ "$(field_of "$RESULT6" target)" = "private" ] \
  || fail "the stamped word beat the copy the tenant actually edited: $(field_of "$RESULT6" target)"
grep -qF "disagreed with it" "$RESULT6" \
  || fail "the disagreement was smoothed over rather than stated: $(cat "$RESULT6")"
git -C "$PRIVATE" apply --check "$(sidecar_of "$RESULT6")" \
  || fail "the patch from the mis-stamped turn does not apply to the checkout it names"

# ---------------------------------------------------------------------
log "a tenant that also composes a diff by hand has it discarded, and the record says so"
# ---------------------------------------------------------------------
read -r _ RESULT7 <<<"$(run_turn "GENDIFF-ALSODIFF")"
PATCH7="$(sidecar_of "$RESULT7")"
grep -qF "GENDIFF-MARKER: alsodiff" "$PATCH7" \
  || fail "the generated patch is not what was recorded: $(cat "$PATCH7")"
if grep -qF "HAND-WRITTEN" "$PATCH7"; then
  fail "the hand-composed diff won over the generated one"
fi
grep -qF "It has been discarded in favour of the patch generated" "$RESULT7" \
  || fail "a deliverable was dropped silently: $(cat "$RESULT7")"

# ---------------------------------------------------------------------
log "an edit in the mechanism copy targets the mechanism checkout"
# ---------------------------------------------------------------------
read -r _ RESULT8 <<<"$(run_turn "GENDIFF-MECHANISM")"
[ "$(field_of "$RESULT8" target)" = "mechanism" ] \
  || fail "an edit under the mechanism copy did not target it: $(field_of "$RESULT8" target)"
git -C "$MECHANISM" apply --check "$(sidecar_of "$RESULT8")" \
  || fail "the mechanism-targeted patch does not apply to the mechanism checkout"

# ---------------------------------------------------------------------
log "a turn that edits nothing proposes nothing, which is a legitimate outcome"
# ---------------------------------------------------------------------
read -r _ RESULT9 <<<"$(run_turn "GENDIFF-NOTHING")"
[ ! -f "$(sidecar_of "$RESULT9")" ] || fail "a turn that edited nothing produced a patch"
[ "$(field_of "$RESULT9" outcome)" = "completed" ] \
  || fail "editing nothing was recorded as a failure: $(field_of "$RESULT9" outcome)"

# ---------------------------------------------------------------------
log "the generation does not inherit its output format from the resident's own git configuration"
# ---------------------------------------------------------------------
# `diff.suppressBlankEmpty = true` in a user's ~/.gitconfig makes git
# write a blank context line as an EMPTY line — which is defect 2 of the
# finding, reproduced by the mechanism itself out of private
# configuration. Principle 01: the mechanism must not take its behaviour
# from the private layer.
HOSTILE_HOME="$WORKDIR/hostile-home"
mkdir -p "$HOSTILE_HOME"
cat > "$HOSTILE_HOME/.gitconfig" <<'EOF'
[diff]
	suppressBlankEmpty = true
EOF
# The control first: without the pin, this configuration really does
# produce the broken shape. Without this assertion the case below would
# pass just as well against a git that ignores the setting.
CONTROL="$WORKDIR/control"
mkdir -p "$CONTROL/a" "$CONTROL/b"
printf 'one\n\nthree\n' > "$CONTROL/a/f.nix"
printf 'one\n\nCHANGED\n' > "$CONTROL/b/f.nix"
CONTROL_OUT="$WORKDIR/control.patch"
( cd "$CONTROL" && env -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_NOSYSTEM HOME="$HOSTILE_HOME" \
    git diff --no-index --no-prefix -- a b > "$CONTROL_OUT" 2>/dev/null || true )
grep -qx '' "$CONTROL_OUT" \
  || fail "the hostile git configuration did not produce an empty context line, so the case below proves nothing: $(cat -A "$CONTROL_OUT")"

read -r _ RESULT10 <<<"$(HOME="$HOSTILE_HOME" run_turn "GENDIFF-ONELINE-gamma")"
PATCH10="$(sidecar_of "$RESULT10")"
grep -qx ' ' "$PATCH10" \
  || fail "no blank context line in the patch, so this case proves nothing: $(cat -A "$PATCH10")"
if grep -qx '' "$PATCH10"; then
  fail "a resident's own git configuration decided the patch's format, and produced the shape git refuses"
fi
git -C "$PRIVATE" apply --check "$PATCH10" \
  || fail "the patch generated under a hostile git configuration does not apply"

# ---------------------------------------------------------------------
log "nor from the git repository the state directory itself is"
# ---------------------------------------------------------------------
# The copy and the diff both live under the state directory, which
# docs/private-layer.md recommends be a git repository of the
# resident's own — so the generation runs INSIDE one unless something
# stops the discovery. `color.ui = always` in that repository is enough
# to make every patch an ANSI-coloured file, which `git apply` refuses
# with "No valid patches in input": a live errand would produce a
# proposal nothing could ever apply, out of a setting that has nothing
# to do with this framework.
#
# Local config rather than global, deliberately: this is the layer
# GIT_CONFIG_GLOBAL cannot reach, and the only thing that keeps it out
# is the ceiling that stops repository discovery.
git -C "$STATE_REPO" config color.ui always
git -C "$STATE_REPO" config diff.suppressBlankEmpty true
read -r _ RESULT11 <<<"$(run_turn "GENDIFF-ONELINE-delta")"
git -C "$STATE_REPO" config --unset color.ui
git -C "$STATE_REPO" config --unset diff.suppressBlankEmpty
PATCH11="$(sidecar_of "$RESULT11")"
[ -f "$PATCH11" ] || fail "the turn produced no patch at all under a coloured state repository: $(cat "$RESULT11")"
if LC_ALL=C grep -q $'\033' "$PATCH11"; then
  fail "the generated patch carries terminal colour escapes, so the state repository's own config decided its bytes: $(cat -A "$PATCH11")"
fi
grep -qx ' ' "$PATCH11" \
  || fail "the state repository's suppressBlankEmpty reached the patch: $(cat -A "$PATCH11")"
git -C "$PRIVATE" apply --check "$PATCH11" \
  || fail "the patch generated inside a configured state repository does not apply: $(cat "$PATCH11")"

# ---------------------------------------------------------------------
log "the scratch directory is empty afterwards: no copy of a checkout outlives its turn"
# ---------------------------------------------------------------------
LEFTOVERS="$(find "$CASTLE_STATE_DIR/work" -mindepth 1 2>/dev/null || true)"
[ -z "$LEFTOVERS" ] \
  || fail "a turn left its scratch behind, including a copy of the resident's checkout: $LEFTOVERS"

# ---------------------------------------------------------------------
log "the regression: the hand-composed shape this task came from, and each half of it"
# ---------------------------------------------------------------------
# Reproduces the framing of `20260905T021750Z-result-ce2d07.patch` on
# invented content: three context lines, one removed line, eight added
# lines, three more context lines — the second of them blank — under a
# header claiming thirteen new lines where the hunk carries fourteen.
# The blank context line is written as an empty line rather than as a
# single space. Both defects, then each alone, then neither.
REG="$WORKDIR/regression"
mkdir -p "$REG"
cat > "$REG/before.nix" <<'EOF'
{
  # A synthetic option block, harness fixture only.
  # The three lines above this one are the hunk's leading context.
  colors.alpha = 0.95;
};

wayland.windowManager.sway.config = {
EOF
( cd "$REG" && git init -q . && git add -A \
  && git -c user.email="$GIT_AUTHOR_EMAIL" -c user.name="$GIT_AUTHOR_NAME" commit -q -m fixture )

# `%s` throughout: the blank context line's content is the entire point,
# so it is written as an explicit argument rather than left to a
# here-document a later edit could trim.
write_regression_patch() {
  # Usage: write_regression_patch <path> <new-line-count> <blank-context-line>
  local out="$1" newcount="$2" blank="$3"
  {
    printf -- '--- a/before.nix\n'
    printf -- '+++ b/before.nix\n'
    printf -- '@@ -1,7 +1,%s @@\n' "$newcount"
    printf -- ' {\n'
    printf -- '   # A synthetic option block, harness fixture only.\n'
    printf -- '   # The three lines above this one are the hunk'"'"'s leading context.\n'
    printf -- '-  colors.alpha = 0.95;\n'
    printf -- '+  #\n'
    printf -- '+  # Seven added comment lines and one added setting, which is what\n'
    printf -- '+  # makes the arithmetic below wrong by exactly one.\n'
    printf -- '+  #\n'
    printf -- '+  # A model composing this by hand has to count them, and did not.\n'
    printf -- '+  #\n'
    printf -- '+  # The line that replaces the one above:\n'
    printf -- '+  "colors-dark".alpha = 0.95;\n'
    printf -- ' };\n'
    printf -- '%s\n' "$blank"
    printf -- ' wayland.windowManager.sway.config = {\n'
  } > "$out"
}

write_regression_patch "$REG/both-defects.patch" 13 ""
write_regression_patch "$REG/count-fixed.patch" 14 ""
write_regression_patch "$REG/space-fixed.patch" 13 " "
write_regression_patch "$REG/correct.patch" 14 " "

# `corrupt patch` and not merely a nonzero exit: a patch that parses and
# then does not apply exits nonzero too, and the two are different
# failures. This suite is about the parse.
assert_corrupt() {
  local where="$1" patch="$2" out
  out="$(git -C "$REG" apply --check "$patch" 2>&1 || true)"
  printf '%s' "$out" | grep -qF 'corrupt patch' \
    || fail "$where: git did not refuse this as a corrupt patch (it said: ${out:-nothing})"
}
assert_corrupt "both defects together" "$REG/both-defects.patch"
# The header alone is fatal, and this is the half that corrects the
# finding as it was written. Measured on the recorded bytes and
# reproduced here: `git apply` TOLERATES an empty line where a blank
# context line belongs — a documented leniency toward tools that strip
# trailing whitespace — so with the count corrected the patch parses and
# applies even with the empty line still in it. The arithmetic was the
# fatal defect, which is exactly the half a model cannot do by looking.
# The empty line stays worth preventing: `patch(1)` and a human reader
# need not forgive it, and a proposal's bytes must not depend on whose
# git configuration generated them (see the case above).
git -C "$REG" apply --check "$REG/count-fixed.patch" \
  || fail "correcting only the count did not make the patch apply, so the finding's fatal defect is not where this says it is"
assert_corrupt "the context line restored and the count still wrong" "$REG/space-fixed.patch"
git -C "$REG" apply --check "$REG/correct.patch" \
  || fail "the corrected shape does not apply, so the defects above are not the whole story: $(cat -A "$REG/correct.patch")"

log "  -- and nothing the generator produces can carry either defect"
# Asserted against the real patches this run generated rather than
# against a fresh one: every hunk header in them was written by git, and
# every blank context line came out as a single space, which the earlier
# cases checked one by one.
python3 - "$PATCH1" "$PATCH2" "$PATCH10" <<'PY'
import re, sys
for path in sys.argv[1:]:
    lines = open(path, encoding="utf-8").read().split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    hunks = 0
    i = 0
    while i < len(lines):
        m = re.match(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", lines[i])
        if not m:
            i += 1
            continue
        hunks += 1
        old_want = int(m.group(2) or 1)
        new_want = int(m.group(4) or 1)
        old_seen = new_seen = 0
        i += 1
        while i < len(lines) and not lines[i].startswith("@@") and not lines[i].startswith("diff --git"):
            line = lines[i]
            if line.startswith("\\"):
                pass
            elif line.startswith("-"):
                old_seen += 1
            elif line.startswith("+"):
                new_seen += 1
            elif line.startswith(" "):
                old_seen += 1
                new_seen += 1
            elif line == "":
                raise SystemExit(f"{path}: an empty line inside a hunk, which is defect 2 of the finding")
            else:
                raise SystemExit(f"{path}: unreadable line inside a hunk: {line!r}")
            i += 1
        if (old_seen, new_seen) != (old_want, new_want):
            raise SystemExit(
                f"{path}: hunk header declares {old_want}/{new_want} and the hunk carries "
                f"{old_seen}/{new_seen} — defect 1 of the finding"
            )
    if not hunks:
        raise SystemExit(f"{path}: no hunks at all, so this check proves nothing")
PY

assert_checkouts_untouched "at the end of the run"
# Every record this suite wrote, read back by the validator: the notes
# 0053 adds are prose in a body, and prose in a body is exactly where a
# malformed record hides until something reads it.
"$CASTLE" validate >/dev/null || fail "the journal this suite wrote does not validate"
log "all assertions passed"
