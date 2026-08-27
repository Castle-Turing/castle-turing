#!/usr/bin/env bash
# test/agent-loop/scripted-worker-byte-fidelity.sh — a worker tenant for
# docs/tasks/0033-byte-exact-proposal.md's sidecar.
#
# Modeled on scripted-worker-config-target.sh's environment contract:
# reads the continuation packet on stdin, takes everything else from
# the environment, and "decides" from a lookup table keyed off markers
# in the request text — nothing model-shaped, nothing non-deterministic.
#
# What this tenant writes to $CASTLE_DIFF_FILE is not built here. The
# harness (config-target.sh) constructs the exact adversarial byte
# sequences under test — once, with `printf`, so the byte-fidelity
# harness's own source stays plain ASCII even for the invalid-UTF-8
# case — and hands this tenant a directory of pre-built fixture files
# via $CASTLE_BYTE_FIDELITY_DIR. This tenant's only job is `cp` from
# that directory to $CASTLE_DIFF_FILE, so there is exactly one place in
# the whole harness that spells out the bytes under test, and the
# assertions that follow compare the sidecar against the same file this
# tenant copied from, not against a second, independently-typed copy
# that could quietly drift from the first.
#
# THE WORKER MUST NOT DEPLOY, and neither does this: it writes to
# $CASTLE_DIFF_FILE and $CASTLE_TARGET_FILE and to nothing else, ever.
set -euo pipefail

: "${CASTLE_REQUEST_ID:?scripted-worker-byte-fidelity.sh: CASTLE_REQUEST_ID must be set}"
: "${CASTLE_DIFF_FILE:?scripted-worker-byte-fidelity.sh: CASTLE_DIFF_FILE must be set}"
: "${CASTLE_TARGET_FILE:?scripted-worker-byte-fidelity.sh: CASTLE_TARGET_FILE must be set}"
: "${CASTLE_PRIVATE_ROOT:?scripted-worker-byte-fidelity.sh: CASTLE_PRIVATE_ROOT must be set}"
: "${CASTLE_BYTE_FIDELITY_DIR:?scripted-worker-byte-fidelity.sh: CASTLE_BYTE_FIDELITY_DIR must be set}"

say() { printf 'byte-fidelity-worker: %s\n' "$*"; }

errand_records="$(cat)"
records_file="$(mktemp)"
trap 'rm -f "$records_file"' EXIT
printf '%s\n' "$errand_records" > "$records_file"
packet_has() { grep -qF -- "$1" "$records_file"; }

propose() {
  # $1 = fixture file, already built byte-for-byte by the harness.
  cp "$CASTLE_BYTE_FIDELITY_DIR/$1" "$CASTLE_DIFF_FILE"
  printf 'private\n' > "$CASTLE_TARGET_FILE"
}

if packet_has "BYTE-FIDELITY-FIXTURE-CRLF"; then
  say "proposing a diff whose content uses CRLF line endings"
  propose crlf.diff
  exit 0
fi

if packet_has "BYTE-FIDELITY-FIXTURE-FORMFEED"; then
  say "proposing a diff whose content carries a form feed"
  propose formfeed.diff
  exit 0
fi

if packet_has "BYTE-FIDELITY-FIXTURE-U2028"; then
  say "proposing a diff whose content carries a U+2028 LINE SEPARATOR"
  propose u2028.diff
  exit 0
fi

if packet_has "BYTE-FIDELITY-FIXTURE-INVALIDUTF8"; then
  say "proposing a diff whose content carries one byte that is not valid UTF-8"
  propose invalid-utf8.diff
  exit 0
fi

if packet_has "BYTE-FIDELITY-FIXTURE-NONEWLINE"; then
  say "proposing a diff with no trailing newline at all"
  propose no-trailing-newline.diff
  exit 0
fi

say "no fixture marker in this errand; proposing nothing"
exit 0
