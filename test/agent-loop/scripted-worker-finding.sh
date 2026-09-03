#!/usr/bin/env bash
# test/agent-loop/scripted-worker-finding.sh — a worker tenant that
# writes findings (docs/tasks/0042-finding-outbox.md's verification
# plan).
#
# Proposal 03's hardening test, held to literally: "any intelligence
# that can read and write [the artifacts] can hold the seat." This one
# is a shell script with no judgment at all — it reads markers out of
# the continuation packet on stdin and writes the finding those markers
# name. Zero models, zero network.
#
# It writes to $CASTLE_FINDING_FILE and to nothing else, ever. It never
# writes a diff and never names a target: the lane this fixture exists
# to exercise is the one that has no proposal in it, which is exactly
# the errand shape that used to have nowhere to go.
#
# Nothing in here is a real complaint, a real defect or a real path.
# Every string is invented.
set -euo pipefail

: "${CASTLE_REQUEST_ID:?scripted-worker-finding.sh: CASTLE_REQUEST_ID must be set}"
: "${CASTLE_DIFF_FILE:?scripted-worker-finding.sh: CASTLE_DIFF_FILE must be set}"
: "${CASTLE_TARGET_FILE:?scripted-worker-finding.sh: CASTLE_TARGET_FILE must be set}"
: "${CASTLE_FINDING_FILE:?scripted-worker-finding.sh: CASTLE_FINDING_FILE must be set}"

say() { printf 'finding-worker: %s\n' "$*"; }

packet="$(cat)"
packet_has() { printf '%s' "$packet" | grep -qF -- "$1"; }
marker_token() {
  printf '%s' "$packet" | sed -n "s/.*$1-\([A-Za-z0-9]*\).*/\1/p" | head -1
}

: > "$CASTLE_DIFF_FILE"
: > "$CASTLE_TARGET_FILE"
: > "$CASTLE_FINDING_FILE"

if packet_has "FINDING-NONE"; then
  say "nothing about the framework to report on this errand"
  exit 0
fi

if packet_has "FINDING-NOHEADER"; then
  say "reporting something, in the wrong shape on purpose"
  cat > "$CASTLE_FINDING_FILE" <<'ENTRY'
I think something is wrong with the harness but I am writing prose
where the header goes, which is not a work item.
ENTRY
  exit 0
fi

if packet_has "FINDING-NOTITLE"; then
  say "reporting something with no title on purpose"
  cat > "$CASTLE_FINDING_FILE" <<'ENTRY'
Destination: mechanism

**What.** A header with no Title: in it.
ENTRY
  exit 0
fi

if packet_has "FINDING-BADDEST"; then
  say "reporting something addressed somewhere that does not exist"
  cat > "$CASTLE_FINDING_FILE" <<'ENTRY'
Title: A fixture finding addressed to nowhere
Destination: somewhere-else

**What.** The destination on this one is not a checkout role, so the
outbox has nothing to resolve it against.

**Why it matters.** Harness fixture only.
ENTRY
  exit 0
fi

if packet_has "FINDING-DUP"; then
  # A title whose slug collides with an entry the framework checkout
  # already has on origin/main.
  say "reporting something already filed under that name"
  cat > "$CASTLE_FINDING_FILE" <<'ENTRY'
Title: Declarative wifi
Destination: mechanism

**What.** Something by this name is already in the backlog.

**Why it matters.** Harness fixture only.
ENTRY
  exit 0
fi

TOKEN="$(marker_token FINDING-GOOD)"
if [ -n "$TOKEN" ]; then
  say "reporting a defect in the framework itself ($TOKEN)"
  # Deliberately carries a fenced block of its own, so the record that
  # quotes a refused finding has to pick a longer fence than three
  # backticks, and so the committed bytes are not trivially simple.
  cat > "$CASTLE_FINDING_FILE" <<ENTRY
Title: The fixture harness noticed something $TOKEN
Destination: mechanism

**What.** An invented defect in an invented mechanism, filed by a
fixture tenant so that a test has a finding to carry.

\`\`\`
a fenced block, inside the finding
\`\`\`

**Why it matters.** Nothing depends on it. Harness fixture only.
ENTRY
  exit 0
fi

say "no fixture marker in this errand; reporting nothing"
exit 0
