#!/usr/bin/env bash
# test/agent-loop/contract-worker-detach.sh — a worker tenant that
# leaves a detached helper holding its stdout and stderr, then exits 0
# (docs/tasks/0021-auto-dispatch.md §3.3).
#
# This is not an exotic shape: a `claude`-style CLI spawns background
# helpers routinely, and any child that does not have its stdout/stderr
# redirected inherits the tenant's — which are the pipes `castle work`
# is reading. `communicate(timeout=...)` fires on pipe EOF, not on
# process exit, so a tenant that finishes its work and exits 0 while
# such a helper lives on used to be recorded `outcome: timeout` with a
# body claiming its process group had been killed, over an errand that
# had actually completed and written its diff.
#
# The helper deliberately does NOT redirect its own streams — that
# inheritance is the entire mechanism under test — and calls setsid so
# it also survives the process-group kill, which is what makes the
# distinction between "the pipes are open" and "the tenant is running"
# observable at all.
set -euo pipefail

: "${CASTLE_REQUEST_ID:?contract-worker-detach.sh: CASTLE_REQUEST_ID must be set}"
: "${CASTLE_DIFF_FILE:?contract-worker-detach.sh: CASTLE_DIFF_FILE must be set}"
: "${CASTLE_TARGET_FILE:?contract-worker-detach.sh: CASTLE_TARGET_FILE must be set}"

cat > /dev/null

printf -- '--- a/synthetic (harness fixture only)\n+++ b/synthetic (harness fixture only)\n' > "$CASTLE_DIFF_FILE"
# Every fixture here that produces a diff also declares which checkout
# it is against, since docs/tasks/0024-config-target.md. These
# fixtures predate that mechanism — they omitted a target because
# there was none to omit, not because a diff without one is a shape
# worth exercising — and a diff with no target now draws a note in the
# result body saying it cannot be routed. Stamping is the honest fix;
# leaving them silent to keep that note out of unrelated harnesses
# would be a fixture's convenience deciding a product behaviour.
printf 'private\n' > "$CASTLE_TARGET_FILE"
echo "contract-worker-detach: work done; leaving a detached helper holding the pipes"

# Short-lived on purpose: the harness does not wait for it, so it
# lingers past the test either way, and 30s keeps that harmless.
setsid sleep 30 < /dev/null &

exit 0
