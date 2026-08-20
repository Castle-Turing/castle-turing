#!/usr/bin/env bash
# test/agent-loop/scripted-worker-config-target.sh — a worker tenant
# for docs/tasks/0024-config-target.md's two-checkout contract.
#
# Modeled on contract-worker.sh, not on scripted-worker.sh: it reads
# the continuation packet on stdin and takes everything else from the
# environment, which is the real castle.agent.worker.command contract.
# scripted-worker.sh's positional-argument shape bypasses `cmd_work`
# entirely and could not exercise one line of what this task changed.
#
# It is model-free and deterministic, like every other fixture here.
# What it "decides" is a lookup table keyed off markers in the request
# text and off which roots its environment actually carries — enough to
# prove the mechanism carries a tenant's judgment through to a record,
# which is the only thing a harness can prove about a judgment.
#
# THE WORKER MUST NOT DEPLOY, and neither does this: it writes to
# $CASTLE_DIFF_FILE and $CASTLE_TARGET_FILE and to nothing else, ever.
# config-target.sh asserts both checkouts' `git status` and `git
# rev-parse HEAD` are unchanged after every run, which is that
# constraint's teeth rather than this comment.
set -euo pipefail

# The contract's environment half, asserted rather than assumed.
# CASTLE_PRIVATE_ROOT is required here even though `castle work` now
# refuses before starting a tenant without one: a fixture that
# tolerated its absence would let a regression in that pre-flight pass
# unnoticed, since the failure would look like an ordinary turn.
: "${CASTLE_REQUEST_ID:?scripted-worker-config-target.sh: CASTLE_REQUEST_ID must be set}"
: "${CASTLE_DIFF_FILE:?scripted-worker-config-target.sh: CASTLE_DIFF_FILE must be set}"
: "${CASTLE_TARGET_FILE:?scripted-worker-config-target.sh: CASTLE_TARGET_FILE must be set}"
: "${CASTLE_PRIVATE_ROOT:?scripted-worker-config-target.sh: CASTLE_PRIVATE_ROOT must be set}"

errand_records="$(cat)"

# The tenants here file their questions with this rather than a
# `castle` on $PATH, which no-Nix CI does not have. Same convention
# scripted-worker-blocking.sh uses.
CASTLE_BIN="${CASTLE_TEST_CASTLE_BIN:?scripted-worker-config-target.sh: CASTLE_TEST_CASTLE_BIN must be set}"

say() { printf 'config-target-worker: %s\n' "$*"; }

# Which of the mechanism checkout's three states this turn is in
# (docs/tasks/0024 §16). All three are reported on stdout, because the
# harness asserts the tenant could tell them apart — a fixture that
# collapsed "unconfigured" into "broken" would prove the channel
# reached it while proving nothing about what it carried.
if [ -n "${CASTLE_MECHANISM_ROOT:-}" ]; then
  say "mechanism checkout available at ${CASTLE_MECHANISM_ROOT}"
elif [ -n "${CASTLE_MECHANISM_ROOT_INVALID:-}" ]; then
  say "mechanism checkout CONFIGURED BUT UNUSABLE at ${CASTLE_MECHANISM_ROOT_INVALID}"
else
  say "no mechanism checkout configured (the normal case)"
fi
say "private checkout at ${CASTLE_PRIVATE_ROOT}"

# Reported for the same reason contract-worker.sh reports it: the
# preamble arriving is the part a conforming tenant must read before
# it can trust anything else in the packet.
records_file="$(mktemp)"
trap 'rm -f "$records_file"' EXIT
printf '%s\n' "$errand_records" > "$records_file"
say "boundary token present: $(grep -c -m1 -o 'CASTLE-PACKET-[0-9a-f]\{16\}' "$records_file" || true)"

packet_has() { grep -qF -- "$1" "$records_file"; }

# ---------------------------------------------------------------------
# A perceptual value: ask on the first turn, diff on the resumed one
# (docs/tasks/0024 §12).
# ---------------------------------------------------------------------
if packet_has "CONFIG-TARGET-FIXTURE-PERCEPTUAL"; then
  if [ -z "${CASTLE_RESUME_ANSWER_IDS:-}" ]; then
    say "the option and the layer are decidable; the VALUE is not"
    say "filing a blocking question and writing no diff and no target"
    # The sweep tools live in the public repo under tools/, which is
    # developer tooling no deployed system installs — so naming one is
    # only honest when a mechanism checkout is configured to hold it.
    # This fixture mirrors the real tenant's own conditional
    # (agent/castle-worker-claude, docs/tasks/0024 §12) rather than
    # hard-coding a path, because a fixture that always named one
    # would assert the very behaviour that was wrong.
    # Three branches, matching the real tenant's own (agent/castle-
    # worker-claude). Two would make this fixture structurally
    # incapable of catching the bug it exists to catch: with only
    # if/else, a configured-but-unusable mechanism root falls into the
    # "none configured" arm and the question tells the resident
    # something their own configuration contradicts — which is exactly
    # how the real prompt regressed while this fixture stayed green.
    if [ -n "${CASTLE_MECHANISM_ROOT:-}" ]; then
      sweep_line="Run ${CASTLE_MECHANISM_ROOT}/tools/font-sweep.sh and tell me the number you settled on."
    elif [ -n "${CASTLE_MECHANISM_ROOT_INVALID:-}" ]; then
      sweep_line="The configured mechanism checkout ${CASTLE_MECHANISM_ROOT_INVALID} is unusable, so the sweep tool under it is out of reach; compare a few candidate sizes side by side and tell me which one reads best."
    else
      sweep_line="No sweep tool is installed on this host, so compare a few candidate sizes side by side and tell me which one reads best."
    fi
    "$CASTLE_BIN" record --type question --provenance requested --seat worker \
      --refs "$CASTLE_REQUEST_ID" --blocking \
      --body "CONFIG-TARGET-FIXTURE-QUESTION: castle.display.terminalFontSize in resident.nix is the layer, but the size itself is a judgment about how this reads to you. $sweep_line" \
      >/dev/null
    # Both files stay empty. This empty diff does NOT mean "no change
    # was warranted" — it means the worker asked instead of
    # concluding, and the open blocking question is what tells the two
    # apart to anything folding the journal.
    exit 0
  fi

  # The resumed turn. A fresh tenant with no memory of the first one:
  # everything it knows about the answer is in the packet on stdin.
  answer_value="$(grep -o 'CONFIG-TARGET-FIXTURE-ANSWER-[0-9]\{1,4\}' "$records_file" | head -1 || true)"
  if [ -z "$answer_value" ]; then
    say "resumed with no recognisable answer in the packet" >&2
    exit 3
  fi
  chosen="${answer_value##*-}"
  say "resumed on the resident's own answer; building the diff around $chosen"
  cat <<EOF > "$CASTLE_DIFF_FILE"
--- a/resident.nix
+++ b/resident.nix
@@ -1,3 +1,4 @@
   castle.display = {
+    terminalFontSize = $chosen;
     cursorTheme = "Example-Cursors";
   };
EOF
  printf 'private\n' > "$CASTLE_TARGET_FILE"
  exit 0
fi

# ---------------------------------------------------------------------
# A mechanism-shaped errand: a fix that needs an option that does not
# exist yet, so it belongs under modules/ or nowhere (§3, §16).
# ---------------------------------------------------------------------
if packet_has "CONFIG-TARGET-FIXTURE-MECHANISM"; then
  if [ -n "${CASTLE_MECHANISM_ROOT:-}" ]; then
    say "no option covers this symptom; widening one under modules/"
    cat <<EOF > "$CASTLE_DIFF_FILE"
--- a/modules/desktop/default.nix
+++ b/modules/desktop/default.nix
@@ -1 +1,2 @@
 placeholder before
+placeholder after (synthetic, harness fixture only)
EOF
    printf 'mechanism\n' > "$CASTLE_TARGET_FILE"
    exit 0
  fi
  if [ -n "${CASTLE_MECHANISM_ROOT_INVALID:-}" ]; then
    say "DECLINING: this fix needs a new option under modules/, and the"
    say "configured mechanism checkout ${CASTLE_MECHANISM_ROOT_INVALID} is not a"
    say "usable git working tree — so this is a misconfiguration to fix, not"
    say "a checkout that was never configured. Proposing nothing."
    exit 0
  fi
  say "DECLINING: this fix needs a new option under modules/, and no"
  say "mechanism checkout is configured on this host, so there is nowhere"
  say "on disk to diff against. Proposing nothing."
  exit 0
fi

# ---------------------------------------------------------------------
# An ordinary private-layer errand, and the sibling-option coupling
# rule that decides how big its diff has to be (§14).
# ---------------------------------------------------------------------
if packet_has "CONFIG-TARGET-FIXTURE-CURSOR"; then
  # cursorSize is inert unless cursorTheme is non-null somewhere in the
  # stack, so a proposal touching one half of the pair has to check the
  # other. Observed by reading the checkout, not assumed.
  if grep -q 'cursorTheme' "$CASTLE_PRIVATE_ROOT/resident.nix" 2>/dev/null; then
    say "cursorTheme is already set in this checkout, so cursorSize alone is enough"
    cat <<EOF > "$CASTLE_DIFF_FILE"
--- a/resident.nix
+++ b/resident.nix
@@ -1,3 +1,4 @@
   castle.display = {
     cursorTheme = "Example-Cursors";
+    cursorSize = 32;
   };
EOF
  else
    say "cursorTheme is unset here, so cursorSize alone would be a silent no-op"
    say "including the sibling option in the same diff"
    cat <<EOF > "$CASTLE_DIFF_FILE"
--- a/resident.nix
+++ b/resident.nix
@@ -1,2 +1,4 @@
   castle.display = {
+    cursorTheme = "Example-Cursors";
+    cursorSize = 32;
   };
EOF
  fi
  printf 'private\n' > "$CASTLE_TARGET_FILE"
  exit 0
fi

say "no fixture marker in this errand; proposing nothing"
exit 0
