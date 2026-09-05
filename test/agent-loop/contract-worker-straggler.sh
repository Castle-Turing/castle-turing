#!/usr/bin/env bash
# test/agent-loop/contract-worker-straggler.sh — a worker tenant that
# exits 0 leaving a child of its OWN process group holding stdout and
# stderr (docs/tasks/0021-auto-dispatch.md §3.3).
#
# The sibling fixture contract-worker-detach.sh calls setsid, so its
# helper escapes the process group and nothing in the turn can reach
# it. This one deliberately does not: a non-interactive shell runs
# background jobs in its own process group, and `castle work` starts
# the tenant with start_new_session=True as that group's leader, so
# this child is exactly what `_kill_tenant_group` exists to reach.
#
# It was reachable in theory and not in practice: the kill only ran
# when the tenant itself was still alive, so a tenant that exited
# leaving this child behind had its turn recorded `completed` while
# the child lived on — free to keep writing into $CASTLE_PRIVATE_ROOT
# after the journal's account of the turn was already final.
#
# The pid file is how the harness checks the child is gone. It goes in
# $CASTLE_PRIVATE_ROOT because that is the directory the escape actually
# threatens.
set -euo pipefail

: "${CASTLE_REQUEST_ID:?contract-worker-straggler.sh: CASTLE_REQUEST_ID must be set}"
: "${CASTLE_DIFF_FILE:?contract-worker-straggler.sh: CASTLE_DIFF_FILE must be set}"
: "${CASTLE_TARGET_FILE:?contract-worker-straggler.sh: CASTLE_TARGET_FILE must be set}"
: "${CASTLE_PRIVATE_ROOT:?contract-worker-straggler.sh: CASTLE_PRIVATE_ROOT must be set}"

cat > /dev/null

# A creation patch, and appliable on purpose: since
# docs/tasks/0054-a-proposal-is-checked-before-it-is-offered.md a
# diff that does not apply to its target checkout files no proposal
# question, so a header-only diff here would put this fixture's
# scenario on the refusal branch — which is not the branch it is
# about. Same reasoning and same shape as contract-worker.sh's.
printf -- '--- /dev/null\n+++ b/synthetic (harness fixture only)\n@@ -0,0 +1 @@\n+placeholder after\n' > "$CASTLE_DIFF_FILE"
# Every fixture here that produces a diff also declares which checkout
# it is against, since docs/tasks/0024-config-target.md. These
# fixtures predate that mechanism — they omitted a target because
# there was none to omit, not because a diff without one is a shape
# worth exercising — and a diff with no target now draws a note in the
# result body saying it cannot be routed. Stamping is the honest fix;
# leaving them silent to keep that note out of unrelated harnesses
# would be a fixture's convenience deciding a product behaviour.
printf 'private\n' > "$CASTLE_TARGET_FILE"
echo "contract-worker-straggler: work done; leaving an in-group child holding the pipes"

# No setsid, and no redirection: it stays in the tenant's process group
# and inherits the pipes `castle work` is reading. Long enough that
# only a kill can end it inside this harness's lifetime.
sleep 45 &
echo "$!" > "$CASTLE_PRIVATE_ROOT/straggler.pid"

exit 0
