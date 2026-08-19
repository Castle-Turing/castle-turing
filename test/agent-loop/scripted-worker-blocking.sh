#!/usr/bin/env bash
# test/agent-loop/scripted-worker-blocking.sh — a worker tenant that
# stops on a question it cannot answer for itself, and continues when
# the resident has (docs/tasks/0023-resume-cold.md §11).
#
# Conforms to the real castle.agent.worker.command contract, like its
# contract-worker*.sh siblings and unlike scripted-worker.sh: the
# errand's records arrive on stdin, CASTLE_REQUEST_ID/CASTLE_DIFF_FILE/
# CASTLE_REPO_ROOT arrive in the environment. Only a tenant reached
# through `castle work`/`castle dispatch` sees the continuation packet,
# the widened claim refs, or CASTLE_RESUME_ANSWER_IDS at all, which is
# why resume.sh drives everything through those two rather than
# assembling a journal with `castle record`.
#
# Two shapes, one file, because the pair is the point:
#
#   First invocation. Files a `--blocking` question and produces
#   nothing else — no diff, no work. This is the "question INSTEAD of a
#   result" shape the blocking field exists to distinguish, as opposed
#   to the common "question ALONGSIDE a result" one that resumes
#   nothing.
#
#   Resumed invocation, detected by CASTLE_RESUME_ANSWER_IDS being set.
#   Reads the whole packet off stdin and echoes back, on its own
#   stdout, the three things it found there: the original request's
#   text, the blocking question's text, and the resident's answer. Each
#   on its own greppable line, so the harness can assert them
#   independently. That half is what actually proves cold resumption —
#   a fixture that only proved "a second claim and result exist" would
#   pass just as happily against an empty or malformed packet.
#
# Every string it writes is invented and hardware-neutral, per this
# repo's hard rule about the journal: nothing here resembles anything a
# real resident ever said.
set -euo pipefail

: "${CASTLE_REQUEST_ID:?scripted-worker-blocking.sh: CASTLE_REQUEST_ID must be set}"
: "${CASTLE_DIFF_FILE:?scripted-worker-blocking.sh: CASTLE_DIFF_FILE must be set}"
: "${CASTLE_REPO_ROOT:?scripted-worker-blocking.sh: CASTLE_REPO_ROOT must be set}"
# Same reason contract-worker-filer.sh takes it this way: nothing
# installs a `castle` on $PATH in this no-Nix harness, and a real
# tenant on a real host gets one from the system profile.
: "${CASTLE_TEST_CASTLE_BIN:?scripted-worker-blocking.sh: CASTLE_TEST_CASTLE_BIN must be set}"

packet="$(cat)"

if [ -z "${CASTLE_RESUME_ANSWER_IDS:-}" ]; then
  # --refs naming the request directly: the canonical shape the real
  # worker prompt now mandates. The resumption *mechanism* tolerates
  # other shapes (it walks the refs chain back to the request), and
  # resume.sh has a separate case for a question filed against its own
  # result — this fixture stays canonical so the ordinary path is what
  # most of the harness exercises.
  question_id="$("$CASTLE_TEST_CASTLE_BIN" record \
    --type question \
    --provenance requested \
    --seat worker \
    --refs "$CASTLE_REQUEST_ID" \
    --blocking \
    --body "Blocking fixture question for $CASTLE_REQUEST_ID: the errand cannot continue until this is answered.")"
  printf 'scripted-worker-blocking: filed blocking question %s and stopped\n' "$question_id"
  printf 'scripted-worker-blocking: no work was done on this turn\n'
  exit 0
fi

# Optional, default off, in the same style as contract-worker.sh's
# CASTLE_TEST_WORKER_SLEEP/CASTLE_TEST_WORKER_BINARY knobs: fail the
# resumed turn rather than adding a near-identical sixth fixture file.
# What it proves is that the answer is spent by the claim regardless of
# how the turn ends, so a failed resumption is not automatically tried
# again.
if [ -n "${CASTLE_TEST_WORKER_FAIL_ON_RESUME:-}" ]; then
  echo "scripted-worker-blocking: failing the resumed turn on purpose" >&2
  exit 4
fi

sleep "${CASTLE_TEST_WORKER_SLEEP:-0}"

printf 'scripted-worker-blocking: RESUMED with %s\n' "$CASTLE_RESUME_ANSWER_IDS"

# One line per thing the packet was supposed to carry, echoed with the
# matched text so the assertion in the harness reads the tenant's own
# report rather than re-deriving it. Each grep is captured on its own —
# not piped into a formatter — because a failing grep at the head of a
# pipeline says nothing about the pipeline's exit status, so a missing
# section would otherwise sail through as an empty, passing line.
echoed() {
  local label="$1" needle="$2" line
  line="$(printf '%s\n' "$packet" | grep -F -m1 -- "$needle")" || {
    printf 'scripted-worker-blocking: the packet did not carry the %s\n' "$label" >&2
    exit 5
  }
  printf 'scripted-worker-blocking: packet carried the %s: %s\n' "$label" "$line"
}
# The heading has to be a WHOLE line of its own. `castle work` emits
# every body byte-for-byte, so the blank line before this heading can
# only have come from the renderer — a request body that ends mid-line,
# which resume.sh deliberately files, would otherwise have this heading
# welded onto its last line and `grep -x` would not find it. That is
# the half of "verbatim bodies" a marker search cannot see.
if ! printf '%s\n' "$packet" | grep -qx -- "## A question this errand raised (blocking, answered below)"; then
  echo "scripted-worker-blocking: the packet's question heading is not on a line of its own" >&2
  exit 8
fi

echoed "request" "RESUME-FIXTURE-REQUEST-MARKER"
echoed "question" "the errand cannot continue until this is answered"
echoed "answer" "RESUME-FIXTURE-ANSWER-MARKER"

# The other half of the same proof, and the sharper one: what the
# packet must NOT contain. A `correction` is the resident judging the
# system, and a fold built on `_collect_downstream` would have handed
# one straight to this tenant — a verdict about the system becoming an
# input to the work being judged. The harness plants a correction
# carrying this marker, against the errand's own request, before
# answering; refusing here is what makes that a real assertion rather
# than a hopeful one.
if printf '%s\n' "$packet" | grep -qF -- "RESUME-FIXTURE-MUST-NOT-REACH-A-TENANT"; then
  echo "scripted-worker-blocking: the packet leaked a record this seat must never read" >&2
  exit 6
fi

cat <<EOF > "$CASTLE_DIFF_FILE"
--- a/docs/backlog/example-item (synthetic, harness fixture only)
+++ b/docs/backlog/example-item (synthetic, harness fixture only)
@@ -1 +1 @@
-placeholder before the resumed turn
+placeholder after the resumed turn
EOF

printf 'scripted-worker-blocking: finished %s on a resumed turn in %s\n' \
  "$CASTLE_REQUEST_ID" "$CASTLE_REPO_ROOT"
