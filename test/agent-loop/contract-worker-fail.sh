#!/usr/bin/env bash
# test/agent-loop/contract-worker-fail.sh — a worker tenant that fails
# cleanly (docs/tasks/0021-auto-dispatch.md §7): nonzero exit, a
# diagnosis on stderr, no diff written at all.
#
# The point it proves is not "cmd_work notices a nonzero exit" but that
# the failure becomes a `result` record carrying `outcome: failed` —
# which is what makes the request permanently ineligible and bounds
# automatic retry to exactly one attempt. Before task 0021 a failing
# tenant left a record; before it, the three *recordless* failure paths
# (empty command, unparseable command, OSError) left nothing, and a
# timer re-firing dispatch against a misconfigured tenant would have
# retried forever in silence.
set -euo pipefail

: "${CASTLE_REQUEST_ID:?contract-worker-fail.sh: CASTLE_REQUEST_ID must be set}"
: "${CASTLE_DIFF_FILE:?contract-worker-fail.sh: CASTLE_DIFF_FILE must be set}"

cat > /dev/null  # drain the request body: the contract still applies

echo "contract-worker-fail: this tenant fails on purpose, every time" >&2
exit 3
