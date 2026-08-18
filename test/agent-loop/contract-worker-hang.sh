#!/usr/bin/env bash
# test/agent-loop/contract-worker-hang.sh — a worker tenant that hangs
# far longer than any test's configured CASTLE_WORKER_TIMEOUT
# (docs/tasks/0021-auto-dispatch.md §7).
#
# It sleeps in a *child* process rather than in this shell, on purpose:
# `cmd_work` kills the tenant's whole process group on timeout
# (os.killpg after start_new_session=True) precisely because real
# tenants like `claude -p` spawn their own subprocesses, and a timeout
# that killed only the direct child would leave those running. A
# fixture that only ever slept in its own PID could not tell the two
# implementations apart.
set -euo pipefail

: "${CASTLE_REQUEST_ID:?contract-worker-hang.sh: CASTLE_REQUEST_ID must be set}"
: "${CASTLE_DIFF_FILE:?contract-worker-hang.sh: CASTLE_DIFF_FILE must be set}"

cat > /dev/null

echo "contract-worker-hang: sleeping far past any test timeout"
sleep 300 &
wait $!
