#!/usr/bin/env bash
# test/agent-loop/contract-worker.sh — a worker tenant that conforms to
# the REAL castle.agent.worker.command contract
# (docs/tasks/0021-auto-dispatch.md §7).
#
# Why a new fixture instead of reusing scripted-worker.sh: that script
# is invoked by run.sh/tenant-swap.sh as `scripted-worker.sh
# <castle-bin> <request-id>` and writes its own records with `castle
# record`, bypassing `cmd_work` entirely. That shape is load-bearing
# for Proposal 03's re-tenanting proof (tenant-swap.sh diffs a
# normalized journal fingerprint between two differently-shaped
# workers, and the comparison only means something if neither harness
# moved out from under it), so it stays byte-for-byte untouched. The
# consequence is that the contract `cmd_work` actually implements —
# request body on stdin, reasoning on stdout, a diff or nothing to
# $CASTLE_DIFF_FILE, $CASTLE_REQUEST_ID/$CASTLE_REPO_ROOT in the
# environment — was exercised nowhere at all before this file.
#
# This one is the happy path: it succeeds and writes a diff. Its
# siblings cover the unhappy ones (-fail, -hang, -die).
set -euo pipefail

# The contract's environment half, asserted rather than assumed: a
# tenant that silently tolerated a missing CASTLE_REQUEST_ID would let
# a regression in cmd_work's env setup pass this harness unnoticed.
: "${CASTLE_REQUEST_ID:?contract-worker.sh: CASTLE_REQUEST_ID must be set}"
: "${CASTLE_DIFF_FILE:?contract-worker.sh: CASTLE_DIFF_FILE must be set}"
: "${CASTLE_REPO_ROOT:?contract-worker.sh: CASTLE_REPO_ROOT must be set}"

request_body="$(cat)"

# Optional, default 0: widens the window in which this tenant is
# running, which is how dispatch-test.sh's concurrency assertion gets a
# race worth catching a regression with. A separate near-identical
# fixture file would have been the alternative; one knob on the happy
# path keeps the fixture family at the four shapes the brief names.
sleep "${CASTLE_TEST_WORKER_SLEEP:-0}"

# Optional, default off: emit a byte that is not valid UTF-8 on stdout
# and into the diff. A tenant's output encoding is not part of the
# contract — a real one only has to cat a binary file once to produce
# this — and before `castle work` decoded leniently, a single such byte
# crashed the turn out of its own result-writing path and left the
# claim to be reaped as a false `interrupted`. A knob rather than a
# sixth fixture, same reasoning as CASTLE_TEST_WORKER_SLEEP above.
if [ -n "${CASTLE_TEST_WORKER_BINARY:-}" ]; then
  printf 'contract-worker: here comes a stray byte: \377\n'
fi

cat <<EOF > "$CASTLE_DIFF_FILE"
--- a/docs/backlog/example-item (synthetic, harness fixture only)
+++ b/docs/backlog/example-item (synthetic, harness fixture only)
@@ -1 +1 @@
-placeholder before
+placeholder after
EOF

if [ -n "${CASTLE_TEST_WORKER_BINARY:-}" ]; then
  printf 'a stray byte in the diff too: \377\n' >> "$CASTLE_DIFF_FILE"
fi

printf 'contract-worker: handled %s in %s\n' "$CASTLE_REQUEST_ID" "$CASTLE_REPO_ROOT"
printf 'contract-worker: the request said: %s\n' "${request_body%%$'\n'*}"
