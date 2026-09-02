#!/usr/bin/env bash
# docs/tasks/0041: the one commented place holding CI's list of
# recognizable, signature-matched infrastructure flakes. Every workflow
# step that retries a transient failure once greps its own captured log
# against this same list (GitHub Actions has no cross-file YAML anchor —
# see vm-install-test.yml's own comment on that — so the list has to live
# in a real file, not be duplicated as inline shell in each workflow).
#
# A pattern belongs here only once it has actually been observed and
# confirmed transient (a same-runner retry cleared it with no code
# change). Do not add a pattern speculatively: a real regression that
# happens to print a similar string would otherwise get one free,
# silent retry instead of surfacing.
#
# Usage: known-transient-ci-failure.sh <log-file>
# Exit 0 — the log matches a known-transient signature; one retry is
#          warranted.
# Exit 1 — no match; this is a real failure and must be surfaced, not
#          retried.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <log-file>" >&2
  exit 2
fi
log_file="$1"

# docs/backlog/ci-flakes-deserve-retries-not-vigilance.md: PR #63,
# 2026-09-01. FlakeHub's login endpoint returned a transient auth error,
# and — independently or as a downstream symptom — the GitHub Actions
# cache backing magic-nix-cache-action then rate-limited narinfo lookups
# into HTTP 418s. Both lines are grepped for on their own: either one
# appearing alone is enough to call the run a known flake.
known_transient_signatures=(
  'Login failure: Transient authentication mechanism error'
  'HTTP error 418'
  'GitHub Actions Cache throttled Magic Nix Cache'
)

for pattern in "${known_transient_signatures[@]}"; do
  if grep -qF "$pattern" "$log_file"; then
    exit 0
  fi
done

exit 1
