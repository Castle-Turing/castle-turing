#!/usr/bin/env bash
# test/reachability/run.sh — the reachability lint, held to the tree that
# produced the incident it exists to catch (task 0072).
#
# Two halves, like test/outcomes/run.sh next door. The first runs the
# lint over this repository, which is what CI is really gating. The
# second builds a synthetic repository and mutates it once per rule: a
# subcommand called only from a test, a subcommand shown only in a
# synopsis, a gate that names no feeder, a gate that names one that does
# not exist. A lint whose negative cases are untested is a lint that
# passes everything — and this one's whole job is to not be that.
#
# Plain bash, stdlib python3, no Nix, no network, zero models.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LINT="$REPO_ROOT/tools/reachability-check.py"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/reachability-test.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

log() { printf '>>> %s\n' "$*"; }
FAILURES=0
fail() { printf '    FAIL: %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
pass() { printf '    ok: %s\n' "$*"; }

log "this repository is reachable"
if python3 "$LINT" --repo-root "$REPO_ROOT" --quiet >/dev/null; then
  pass "every tool subcommand has a caller and every gate names a feeder"
else
  python3 "$LINT" --repo-root "$REPO_ROOT" || true
  fail "the repository does not pass its own reachability lint"
fi

# --- the synthetic repository -------------------------------------------

SANDBOX="$WORKDIR/repo"
mkdir -p "$SANDBOX/tools/widget" "$SANDBOX/test/widget" \
         "$SANDBOX/.github/workflows" "$SANDBOX/docs"

cat > "$SANDBOX/tools/widget/widget" <<'PY'
#!/usr/bin/env python3
"""A tool with two subcommands, for the lint to have an opinion about."""
import argparse
ap = argparse.ArgumentParser()
sub = ap.add_subparsers()
sub.add_parser("check")
sub.add_parser("derive")
PY
chmod +x "$SANDBOX/tools/widget/widget"

workflow() { # workflow <feeder-line-or-empty>
  {
    printf 'name: widget-check\n\n'
    printf '# The widget gate.\n'
    [ -n "${1:-}" ] && printf '# Feeder: %s\n' "$1"
    printf 'jobs:\n  g:\n    steps:\n'
    printf '      - run: tools/widget/widget check --strict\n'
  } > "$SANDBOX/.github/workflows/widget-check.yml"
}

runbook() { # runbook <line...>
  { printf '# Widget runbook\n\n'; printf '    %s\n' "$@"; } \
    > "$SANDBOX/docs/widget.md"
}

lint() { python3 "$LINT" --repo-root "$SANDBOX" "$@"; }

reject() { # reject <name> <expected substring>
  local name=$1 expect=$2 out
  if out=$(lint 2>&1); then
    fail "$name: accepted"
  elif printf '%s' "$out" | grep -qF -- "$expect"; then
    pass "$name"
  else
    fail "$name: rejected for the wrong reason: $(printf '%s' "$out" | tail -3 | head -1)"
  fi
}

accept() { # accept <name>
  local name=$1 out
  if out=$(lint 2>&1); then
    pass "$name"
  else
    fail "$name: rejected — $(printf '%s' "$out" | grep -v '^$' | tail -2 | head -1)"
  fi
}

log "the baseline the rejects are mutated from"
workflow "tools/widget/widget derive, run by docs/widget.md"
runbook "tools/widget/widget derive --fill --env e1"
accept "a tool whose every subcommand has a runbook caller, behind a fed gate"

log "orphan entrypoints"

runbook "tools/widget/widget check --strict"
reject "a subcommand nothing outside its own source calls" \
  "subcommand \`derive\` has no caller"

# The 0070 tree, exactly: thorough tests, no caller.
runbook "tools/widget/widget check --strict"
cat > "$SANDBOX/test/widget/run.sh" <<'SH'
#!/usr/bin/env bash
tools/widget/widget derive --fill --env e1
SH
reject "a subcommand called only from its own tests" \
  "subcommand \`derive\` has no caller"
rm -f "$SANDBOX/test/widget/run.sh"

# The other half of the 0070 tree: the usage listing that was there all along.
runbook "tools/widget/widget check --strict" \
        "tools/widget/widget derive [--harness-journal FILE]... [--env KEY]"
reject "a subcommand shown only as a synopsis with placeholders" \
  "subcommand \`derive\` has no caller"

printf '# Widget runbook\n\nSomeone should really run tools/widget/widget derive one day.\n' \
  > "$SANDBOX/docs/widget.md"
reject "a subcommand mentioned only in running prose" \
  "subcommand \`derive\` has no caller"

log "and what must still count as a caller"

runbook "tools/widget/widget check --strict" \
        "tools/widget/widget derive --fill --env \"\$OUTCOMES_ENV\""
accept "a command using a shell variable, which is not a placeholder"

log "armed gates"

runbook "tools/widget/widget derive --fill --env e1" \
        "tools/widget/widget check --strict"
workflow ""
reject "a gate that runs a tool and names no feeder" "names no \`# Feeder:\`"

workflow "tools/widget/wodget derive"
reject "a gate whose feeder names a path that is not there" "does not exist"

workflow "somebody, probably"
reject "a gate whose feeder names no path at all" "names no path in this repository"

workflow "none — "
reject "an opt-out with no reason after it" "Blank is not an answer"

workflow "none — this gate checks a file committed by hand and nothing produces it"
accept "an opt-out that says why, at length"

printf '\n'
if [ "$FAILURES" -eq 0 ]; then
  log "all checks passed"
else
  log "$FAILURES check(s) failed"
  exit 1
fi
