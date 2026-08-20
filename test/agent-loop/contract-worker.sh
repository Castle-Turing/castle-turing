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
# $CASTLE_DIFF_FILE, $CASTLE_REQUEST_ID/$CASTLE_PRIVATE_ROOT in the
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
: "${CASTLE_PRIVATE_ROOT:?contract-worker.sh: CASTLE_PRIVATE_ROOT must be set}"
: "${CASTLE_TARGET_FILE:?contract-worker.sh: CASTLE_TARGET_FILE must be set}"

# Named for what `castle work` actually pipes here. Since
# docs/tasks/0023-resume-cold.md that is the errand's whole
# continuation packet — a preamble naming this turn's section-boundary
# token, then the request, then every prior turn's account, question
# and answer — not the bare request body it was called before. This
# fixture is the reference implementation of the tenant contract, so a
# stranger reading it to build their own must not be told the first
# line of stdin is the resident's text: it is the packet's own opening
# line.
errand_records="$(cat)"

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

# The other half of the contract since
# docs/tasks/0024-config-target.md: a diff is not a proposal until
# something says which checkout it is against. This fixture's diff is
# a private-layer change, so it stamps `private` — which is also what
# test/desktop-loop/test.nix reads back out of the result record to
# prove the target channel survives the real dispatch unit's
# environment and not only this plain-bash harness's.
printf 'private\n' > "$CASTLE_TARGET_FILE"

printf 'contract-worker: handled %s in %s\n' "$CASTLE_REQUEST_ID" "$CASTLE_PRIVATE_ROOT"
# Reports something true of the packet rather than mislabelling its
# first line. The line count is the honest one-line summary a fixture
# can give of a document whose shape is the mechanism's business, and
# the boundary token proves the preamble arrived — which is the part a
# conforming tenant has to read before it can trust anything else.
# Counted off a file, not a pipe. `grep -m1` against a piped-in packet
# exits at the first match while printf is still writing, and under
# `set -o pipefail` that SIGPIPE becomes the pipeline's status — a
# failure that only appears once the packet outgrows the pipe buffer,
# which is the worst size for a bug to wait at.
records_file="$(mktemp)"
trap 'rm -f "$records_file"' EXIT
printf '%s\n' "$errand_records" > "$records_file"
printf 'contract-worker: received %s lines of errand records\n' "$(grep -c '' "$records_file" || true)"
printf 'contract-worker: boundary token present: %s\n' \
  "$(grep -c -m1 -o 'CASTLE-PACKET-[0-9a-f]\{16\}' "$records_file" || true)"
