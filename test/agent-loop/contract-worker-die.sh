#!/usr/bin/env bash
# test/agent-loop/contract-worker-die.sh — a worker tenant killed by a
# signal mid-turn (docs/tasks/0021-auto-dispatch.md §7).
#
# Distinct from contract-worker-fail.sh's clean nonzero exit because
# the distinction decides which `outcome` value gets written
# (docs/tasks/0021 §3.5): a tenant that dies by signal while its
# invoker survives to watch it is `failed`, exactly like any other
# tenant death the invoker observed. `interrupted` is reserved for the
# case where the *invoker itself* died and only a later dispatch sweep
# could supply the account. A harness that never exercised a signal
# death would leave that boundary untested and easy to blur.
set -euo pipefail

: "${CASTLE_REQUEST_ID:?contract-worker-die.sh: CASTLE_REQUEST_ID must be set}"
: "${CASTLE_DIFF_FILE:?contract-worker-die.sh: CASTLE_DIFF_FILE must be set}"

cat > /dev/null

echo "contract-worker-die: about to kill myself with SIGKILL"
kill -KILL $$
# Unreachable: SIGKILL cannot be caught, blocked, or ignored.
sleep 5
