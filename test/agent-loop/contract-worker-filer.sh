#!/usr/bin/env bash
# test/agent-loop/contract-worker-filer.sh — a worker tenant that files
# a follow-up request during its own turn
# (docs/tasks/0021-auto-dispatch.md §2.4(e)).
#
# Not a pathological tenant: this is what a *reasonable* one does. A
# model that notices a second problem while fixing the first has an
# obvious, sanctioned way to record it — `castle ask`, the same intake
# any seat uses — and nothing about that is wrong. What was wrong was
# the consequence: each filed request is a fresh errand with its own
# fresh automatic attempt, so a tenant could extend a sweep
# indefinitely, spending unattended, while holding the global dispatch
# lock the whole time. Reproduced before the fix: one sweep, five
# turns, from a single resident request.
#
# The fix stamps `filed-during-turn` on anything filed while a turn is
# running, and dispatch never auto-starts a request carrying it. This
# fixture is what proves that end to end, including the inheritance
# path that makes it work at all: the tenant does not set the stamp,
# and does not know it exists — it just runs `castle ask`, which
# inherits CASTLE_WORKER_CLAIM from this script's own environment.
set -euo pipefail

: "${CASTLE_REQUEST_ID:?contract-worker-filer.sh: CASTLE_REQUEST_ID must be set}"
: "${CASTLE_DIFF_FILE:?contract-worker-filer.sh: CASTLE_DIFF_FILE must be set}"
# The harness passes the castle binary this way rather than assuming a
# `castle` on $PATH: nothing installs one in this no-Nix harness, and a
# real tenant on a real host gets it from the system profile.
: "${CASTLE_TEST_CASTLE_BIN:?contract-worker-filer.sh: CASTLE_TEST_CASTLE_BIN must be set}"

cat > /dev/null

follow_up="$("$CASTLE_TEST_CASTLE_BIN" ask "Follow-up filed by the tenant during its turn on $CASTLE_REQUEST_ID.")"
printf 'contract-worker-filer: filed follow-up request %s while working %s\n' \
  "$follow_up" "$CASTLE_REQUEST_ID"

printf -- '--- a/synthetic (harness fixture only)\n+++ b/synthetic (harness fixture only)\n' > "$CASTLE_DIFF_FILE"
