#!/usr/bin/env bash
# test/agent-loop/tenant-swap.sh — Proposal 03's hardening test, second
# half (docs/architecture.md): "at least one seat is successfully
# re-tenanted (a different model or harness) with no structural
# change." docs/tasks/0009-ambient-intake.md's verification plan asks
# for this to be proven structurally rather than by burning tokens in
# CI, so this runs the whole test/agent-loop/run.sh loop twice — once
# with the reference scripted-worker.sh (bash) holding the worker seat,
# once with scripted-worker-alt.py (Python), a deliberately different
# implementation of the identical contract — and diffs a normalized,
# id-and-timestamp-stripped summary of each run's resulting journal
# (test/agent-loop/normalize_journal.py). Zero models, zero network,
# same as run.sh itself.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN="$REPO_ROOT/test/agent-loop/run.sh"

SUMMARY_A="$(mktemp)"
SUMMARY_B="$(mktemp)"
LOG_A="$(mktemp)"
LOG_B="$(mktemp)"
trap 'rm -f "$SUMMARY_A" "$SUMMARY_B" "$LOG_A" "$LOG_B"' EXIT

log() { printf '>>> %s\n' "$*"; }

log "tenant A: scripted-worker.sh (bash)"
if ! CASTLE_AGENT_LOOP_WORKER="$REPO_ROOT/test/agent-loop/scripted-worker.sh" \
     CASTLE_AGENT_LOOP_SUMMARY_OUT="$SUMMARY_A" \
     "$RUN" > "$LOG_A" 2>&1; then
  cat "$LOG_A" >&2
  echo "FAIL: tenant A (scripted-worker.sh) run failed" >&2
  exit 1
fi

log "tenant B: scripted-worker-alt.py (python — a different shape)"
if ! CASTLE_AGENT_LOOP_WORKER="$REPO_ROOT/test/agent-loop/scripted-worker-alt.py" \
     CASTLE_AGENT_LOOP_SUMMARY_OUT="$SUMMARY_B" \
     "$RUN" > "$LOG_B" 2>&1; then
  cat "$LOG_B" >&2
  echo "FAIL: tenant B (scripted-worker-alt.py) run failed" >&2
  exit 1
fi

log "diffing normalized, id-stripped record-level outcomes"
if ! diff -u "$SUMMARY_A" "$SUMMARY_B"; then
  echo "FAIL: swapping the worker tenant changed the record-level shape of the run — Proposal 03 violated" >&2
  exit 1
fi

log "identical record-level outcomes across two differently-shaped worker tenants — worker seat re-tenanted with no structural change"
