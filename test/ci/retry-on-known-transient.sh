#!/usr/bin/env bash
# docs/tasks/0041: run a command, retrying it exactly once if — and only
# if — it fails with a signature known-transient-ci-failure.sh
# recognizes. Shared by vm-install-test.yml and desktop-loop-test.yml so
# the retry loop itself (not just the signature list) lives in one
# place; a fix to the loop's control flow lands once, not once per
# workflow file.
#
# Usage: retry-on-known-transient.sh [--stdout FILE] -- CMD [ARGS...]
#   --stdout FILE   redirect CMD's own stdout there, untouched by this
#                    script's capture/retry bookkeeping. Needed by
#                    desktop-loop-test.yml: `nix build --print-out-paths`
#                    writes a store path to stdout that a later step
#                    trusts unconditionally (see that step's own
#                    comment on why an empty/garbage out-path file is a
#                    real incident, not a theoretical one) — only the
#                    build's stderr (the `-L` log) should be captured
#                    and grepped for a transient signature.
#
# This script controls its own `set -e`/pipefail from its own shebang,
# unlike the workflow step that calls it (GitHub Actions' default shell
# for a bare `run:` step is `bash -e {0}`, `-e` only, confirmed by a
# comment already in desktop-loop-test.yml from an earlier incident) —
# but the pipeline below still has to sit in an `if` condition for the
# same reason: `-e` does not abort on the test-part of an `if`/`while`,
# but does abort on a bare pipeline statement, and this script's own
# `set -e` would otherwise kill it on the very first (possibly
# retryable) failure, before the retry logic ever ran.
set -uo pipefail

usage() {
  echo "usage: $0 [--stdout FILE] -- CMD [ARGS...]" >&2
  exit 2
}

stdout_target=""
if [ "${1:-}" = "--stdout" ]; then
  [ "$#" -ge 2 ] || usage
  stdout_target="$2"
  shift 2
fi
[ "${1:-}" = "--" ] || usage
shift
[ "$#" -ge 1 ] || usage

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log_file="$(mktemp)"

attempt=1
while :; do
  if [ -n "$stdout_target" ]; then
    if { "$@" > "$stdout_target"; } 2>&1 | tee "$log_file"; then
      exit 0
    fi
  else
    if "$@" 2>&1 | tee "$log_file"; then
      exit 0
    fi
  fi
  status="${PIPESTATUS[0]}"

  if [ "$attempt" -ge 2 ] || ! "$script_dir/known-transient-ci-failure.sh" "$log_file"; then
    exit "$status"
  fi

  msg="Attempt $attempt failed with a known-transient CI signature (see test/ci/known-transient-ci-failure.sh); retrying once."
  echo "$msg" >&2
  # A plain redirect, not a pipe: if this write fails (e.g.
  # GITHUB_STEP_SUMMARY unset when this script is run outside CI), it
  # must not take the retry down with it — the retry the whole task
  # exists to guarantee must not depend on a step-summary write
  # succeeding.
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    echo "$msg" >> "$GITHUB_STEP_SUMMARY" || true
  fi
  attempt=$((attempt + 1))
done
