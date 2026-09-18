#!/usr/bin/env bash
# test/reachability/run.sh — the reachability lint, held to what
# docs/tasks/0072-wire-the-outcome-log-and-its-redirects.md says it must
# catch.
#
# Two halves. The first runs the lint over this repository, which is
# what CI is really gating. The second builds synthetic trees — a tool
# with two subcommands, a workflow, a document, a test — and asserts
# each rule fires on the shape it owns and stays quiet on the shapes it
# must not flag. The exclusions are the interesting cases: a test and a
# usage synopsis must *not* rescue an orphan, because the incident this
# lint exists for had both.
#
# Same conventions as test/outcomes next door: plain bash, stdlib
# python3, no Nix, no network, zero models.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LINT="$REPO_ROOT/tools/reachability-check.py"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/reachability-test.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

log() { printf '>>> %s\n' "$*"; }
FAILURES=0
fail() { printf '    FAIL: %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
pass() { printf '    ok: %s\n' "$*"; }

# --- the real tree -------------------------------------------------------

log "this repository's own entrypoints are all reachable"
if python3 "$LINT" "$REPO_ROOT" >/dev/null; then
  pass "every tool subcommand has an operational caller, every gate a feeder"
else
  python3 "$LINT" "$REPO_ROOT" || true
  fail "the repository does not pass its own reachability lint"
fi

# --- synthetic trees -----------------------------------------------------

SANDBOX="$WORKDIR/repo"

fresh() { # fresh — a tree with a two-subcommand tool and nothing else
  rm -rf "$SANDBOX"
  mkdir -p "$SANDBOX/tools/thing" "$SANDBOX/.github/workflows" \
           "$SANDBOX/test/thing" "$SANDBOX/docs"
  cat > "$SANDBOX/tools/thing/thing" <<'TOOL'
#!/usr/bin/env python3
import argparse


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check")
    c.set_defaults(func=None)
    w = sub.add_parser("write")
    w.set_defaults(func=None)
    g = sub.add_parser("group")
    gs = g.add_subparsers(dest="sub", required=True)
    gs.add_parser("leaf")
    return ap.parse_args()
TOOL
  chmod +x "$SANDBOX/tools/thing/thing"
}

lint() { python3 "$LINT" "$SANDBOX" 2>&1; }

reject() { # reject <name> <expected substring>
  local name=$1 expect=$2 out
  if out=$(lint); then
    fail "$name: accepted"
  elif printf '%s' "$out" | grep -qF -- "$expect"; then
    pass "$name"
  else
    fail "$name: rejected for the wrong reason: $(printf '%s' "$out" | head -1)"
  fi
}

accept() { # accept <name>
  local name=$1 out
  if out=$(lint); then
    pass "$name"
  else
    fail "$name: rejected — $(printf '%s' "$out" | head -1)"
  fi
}

# A caller for `check` and `group leaf` in every tree below, so that the
# subject of each assertion is `write` alone.
baseline_callers() {
  cat > "$SANDBOX/.github/workflows/gate.yml" <<'YML'
# feeder: tools/thing/thing write (docs/how.md)
jobs:
  gate:
    steps:
      - run: tools/thing/thing check
YML
  cat > "$SANDBOX/docs/leaf.md" <<'MD'
<!-- invokes: tools/thing/thing group leaf -->
MD
}

log "the orphan entrypoint rule"

fresh; baseline_callers
cat > "$SANDBOX/docs/how.md" <<'MD'
<!-- invokes: tools/thing/thing write -->
MD
accept "a documented step that declares itself is a caller"

fresh; baseline_callers
rm -f "$SANDBOX/docs/how.md"
cat > "$SANDBOX/docs/how.md" <<'MD'
Nothing here declares anything.
MD
reject "a subcommand nothing calls" "\`write\` has no operational caller"

fresh; baseline_callers
cat > "$SANDBOX/docs/how.md" <<'MD'
<!-- invokes: tools/thing/thing write -->
MD
cat > "$SANDBOX/test/thing/run.sh" <<'SH'
THING="$REPO_ROOT/tools/thing/thing"
"$THING" write --out /tmp/x
SH
rm -f "$SANDBOX/docs/how.md"
cat > "$SANDBOX/docs/how.md" <<'MD'
Nothing here declares anything.
MD
reject "a test does not rescue an orphan — the 0070 miss had tests" \
  "\`write\` has no operational caller"

fresh; baseline_callers
cat > "$SANDBOX/tools/README.md" <<'MD'
## Synopsis

    tools/thing/thing write [--out DIR]
MD
reject "a usage synopsis does not rescue an orphan either" \
  "\`write\` has no operational caller"

fresh; baseline_callers
cat > "$SANDBOX/docs/how.md" <<'MD'
<!-- invokes: tools/thing/thing write -->
MD
cat > "$SANDBOX/tools/wrapper.sh" <<'SH'
#!/bin/sh
exec tools/thing/thing write "$@"
SH
accept "another tool calling it is a caller"

fresh; baseline_callers
cat > "$SANDBOX/docs/how.md" <<'MD'
<!-- invokes: tools/thing/thing write -->
<!-- invokes: tools/thing/thing fly -->
MD
reject "a marker naming an entrypoint that does not exist" \
  "names no entrypoint any tool exposes"

fresh; baseline_callers
cat > "$SANDBOX/docs/how.md" <<'MD'
<!-- invokes: tools/thing/thing write -->
MD
cat > "$SANDBOX/tools/prose.py" <<'PY'
"""A file that merely mentions tools/thing/thing group leaf in prose."""
# tools/thing/thing check is discussed here and not called.
PY
rm -f "$SANDBOX/docs/leaf.md"
reject "a tool's own prose is not a call" "\`group leaf\` has no operational caller"

log "the armed-gate rule"

fresh
cat > "$SANDBOX/.github/workflows/gate.yml" <<'YML'
jobs:
  gate:
    steps:
      - run: tools/thing/thing check
YML
cat > "$SANDBOX/docs/how.md" <<'MD'
<!-- invokes: tools/thing/thing write -->
<!-- invokes: tools/thing/thing group leaf -->
MD
reject "a gate that names nothing feeding it" "names nothing that feeds it"

fresh
cat > "$SANDBOX/.github/workflows/gate.yml" <<'YML'
# feeder: tools/thing/thing conjure (docs/how.md)
jobs:
  gate:
    steps:
      - run: tools/thing/thing check
YML
cat > "$SANDBOX/docs/how.md" <<'MD'
<!-- invokes: tools/thing/thing write -->
<!-- invokes: tools/thing/thing group leaf -->
MD
reject "a feeder naming a command that does not exist" \
  "is not an entrypoint any tool exposes"

fresh
cat > "$SANDBOX/.github/workflows/gate.yml" <<'YML'
# feeder: tools/thing/thing write (docs/nowhere.md)
jobs:
  gate:
    steps:
      - run: tools/thing/thing check
YML
cat > "$SANDBOX/docs/how.md" <<'MD'
<!-- invokes: tools/thing/thing write -->
<!-- invokes: tools/thing/thing group leaf -->
MD
reject "a feeder citing a file that is not there" "is not a file here"

fresh
cat > "$SANDBOX/.github/workflows/gate.yml" <<'YML'
# feeder: tools/thing/thing write (docs/elsewhere.md)
jobs:
  gate:
    steps:
      - run: tools/thing/thing check
YML
cat > "$SANDBOX/docs/how.md" <<'MD'
<!-- invokes: tools/thing/thing write -->
<!-- invokes: tools/thing/thing group leaf -->
MD
cat > "$SANDBOX/docs/elsewhere.md" <<'MD'
A document that says nothing about running anything.
MD
reject "a feeder citing a document that does not own the step" \
  "carries no"

fresh; baseline_callers
cat > "$SANDBOX/docs/how.md" <<'MD'
<!-- invokes: tools/thing/thing write -->
MD
accept "a gate whose feeder citation resolves to the step that owns it"

printf '\n'
if [ "$FAILURES" -eq 0 ]; then
  log "all checks passed"
else
  log "$FAILURES check(s) failed"
  exit 1
fi
