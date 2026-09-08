#!/usr/bin/env bash
# tools/handover.sh — generate the operator handover, and refuse to hand
# over one that does not check out.
#
# WHY THIS EXISTS (read before touching it)
#
# docs/tasks/0062-the-operator-handover.md. The resident's own summary of
# the problem: pull-request review is today the only channel through which
# they render a verdict, so it carries two jobs at once — "was this done
# correctly" and "was this the right work" — and uniform skimming serves
# neither. This surface takes the second job. It reads the ledgers this
# repo already accumulates and emits one screenful: intent restated,
# threats first, receipts with citations, what could not be grounded, and
# the short list of decisions only the resident can make.
#
# THE THREE PIECES, AND WHY THEY ARE THREE
#
#   tools/handover-ledger.py   git + gh + the tree -> artifact state, JSON.
#                              No model in it. This is what makes the
#                              derivation rule enforceable rather than
#                              aspirational.
#   tools/handover-prompt.md   the format, handed to the agent turn. Also
#                              the human-readable spec of that format.
#   tools/handover-check.py    a pure function of (ledger, handover). It
#                              resolves every citation and matches every
#                              receipt phrase against the artifact state,
#                              and it BLOCKS.
#
# The model sits in the middle, between two things it cannot influence.
# That is the whole design: it may choose what to say and how to group it,
# and it may not choose what is true.
#
# WHY THE CHECK BLOCKS RATHER THAN WARNS
#
# The generator controls its own output, so a violation is a bug in this
# tool, not a stylistic disagreement with a third party. And the specific
# failure being guarded against — the confident-closure register, "done",
# "complete", "successfully" — is a trained default with a measurable
# signature that model judges talk themselves out of
# (docs/research/operator-handover.md §3). An instruction not to use it is
# not a control. A lint is.
#
# In the same spirit as tools/codex-review.sh next door: this script would
# rather be annoying than quiet. Every failure is loud, nothing is retried
# silently, and a rejected draft is kept on disk so you can read what it
# got wrong rather than guess.
#
# USAGE
#
#   tools/handover.sh [--since DATE] [--until DATE] [--out DIR]
#                     [--ledger FILE] [--keep] [--model NAME]
#
#   --since/--until  the window; --until is exclusive. Defaults to the
#                    last seven days.
#   --ledger FILE    use an existing ledger instead of building one. The
#                    window then comes from that file, and gh is never
#                    called.
#   --out DIR        where the ledger and handover are written. Defaults
#                    to a scratch directory under $TMPDIR, deliberately
#                    NOT inside this repo: a ledger built on a real
#                    machine carries journal record ids, which are private
#                    layer and may never be committed here (CLAUDE.md's
#                    first hard rule).
#   --keep           keep a rejected draft's directory and say where it is.
#                    On by default for failures; this also keeps it on
#                    success.
#   --model NAME     passed to `claude --model`.
#
# CADENCE AND CHANNEL ARE NOT DECIDED HERE. On demand only, on purpose —
# the brief reserves scheduling, notification and any castle-modal
# integration for the resident, once this exists to have an opinion about.

set -euo pipefail

SINCE=""
UNTIL=""
OUT_DIR=""
LEDGER=""
KEEP=0
MODEL=""

while [ $# -gt 0 ]; do
  case "$1" in
    --since|--until|--out|--ledger|--model)
      # Same argument-shape guard as tools/codex-review.sh, for the same
      # two bugs it was written for: a value-taking flag at the end of the
      # line crashing on "$2: unbound variable" under `set -u`, and
      # `--since --keep` silently eating the next flag as its value.
      FLAG="$1"
      if [ $# -lt 2 ] || [[ "$2" == -* ]]; then
        echo "tools/handover.sh: $FLAG requires a value." >&2
        exit 2
      fi
      case "$FLAG" in
        --since) SINCE="$2" ;;
        --until) UNTIL="$2" ;;
        --out) OUT_DIR="$2" ;;
        --ledger) LEDGER="$2" ;;
        --model) MODEL="$2" ;;
      esac
      shift 2
      ;;
    --keep) KEEP=1; shift ;;
    -h|--help)
      sed -n '2,/^set -euo pipefail/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "tools/handover.sh: unrecognized argument: $1" >&2
      echo "Run with --help for usage." >&2
      exit 2
      ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [ -z "$SINCE" ]; then SINCE="$(date -u -d '7 days ago' +%Y-%m-%d)"; fi
if [ -z "$UNTIL" ]; then UNTIL="$(date -u -d 'tomorrow' +%Y-%m-%d)"; fi

# --- preflight ---------------------------------------------------------
#
# Every one of these is a hard stop with a named cause. The failure this
# repo has already paid for once is a review step that stopped happening
# and said nothing about it (docs/backlog/cross-model-review-is-paywalled.md);
# a handover that silently stopped being generated would be the same
# failure on a surface whose entire job is telling the resident what is
# true.

for tool in python3 claude; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "handover: '$tool' is not installed. Nothing was generated." >&2
    exit 1
  fi
done

if [ -z "$LEDGER" ]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "handover: the GitHub CLI ('gh') is not installed, so pull-request state cannot be read." >&2
    echo "handover: install it (https://cli.github.com), or pass --ledger with a ledger built elsewhere." >&2
    exit 1
  fi
  if ! gh auth status >/dev/null 2>&1; then
    echo "handover: 'gh' is not authenticated. Run 'gh auth login'. Nothing was generated." >&2
    exit 1
  fi
fi

if [ -z "$OUT_DIR" ]; then
  OUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/castle-handover.XXXXXX")"
fi
mkdir -p "$OUT_DIR"

# --- the ledger --------------------------------------------------------

if [ -z "$LEDGER" ]; then
  LEDGER="$OUT_DIR/ledger.json"
  echo "handover: reading the ledgers for $SINCE..$UNTIL (exclusive). This calls 'gh' once per pull request." >&2
  python3 tools/handover-ledger.py --since "$SINCE" --until "$UNTIL" -o "$LEDGER"
else
  echo "handover: using the ledger at $LEDGER; not calling gh." >&2
fi

# --- the agent turn ----------------------------------------------------

DRAFT="$OUT_DIR/handover.md"
TRANSCRIPT="$OUT_DIR/agent-stderr.log"

PROMPT_FILE="$OUT_DIR/prompt.md"
{
  cat tools/handover-prompt.md
  printf '\n\n## The ledger\n\nEverything you may cite is in this JSON document and nothing else is.\n\n```json\n'
  cat "$LEDGER"
  printf '\n```\n'
} >"$PROMPT_FILE"

CLAUDE_ARGS=(-p --output-format text)
if [ -n "$MODEL" ]; then CLAUDE_ARGS+=(--model "$MODEL"); fi

echo "handover: generating." >&2
AGENT_EXIT=0
claude "${CLAUDE_ARGS[@]}" <"$PROMPT_FILE" >"$DRAFT" 2>"$TRANSCRIPT" || AGENT_EXIT=$?

if [ "$AGENT_EXIT" -ne 0 ]; then
  echo "handover: the agent turn exited $AGENT_EXIT. Nothing was generated. Its stderr:" >&2
  cat "$TRANSCRIPT" >&2
  exit 1
fi

if [ ! -s "$DRAFT" ]; then
  echo "handover: the agent turn exited 0 and wrote nothing. Treating that as a failure rather than reporting an empty handover — an empty report is indistinguishable from a quiet week and this surface may not be ambiguous about that." >&2
  exit 1
fi

# A model asked for markdown will sometimes wrap the whole document in a
# fence anyway. Strip exactly that shape — a first line that opens a fence
# and a last line that closes one — and nothing else; a fence in the
# middle of the document is the model's business, not this script's.
if [ "$(head -n1 "$DRAFT")" = '```markdown' ] || [ "$(head -n1 "$DRAFT")" = '```' ]; then
  if [ "$(tail -n1 "$DRAFT")" = '```' ]; then
    sed -i '1d;$d' "$DRAFT"
  fi
fi

# --- the check ---------------------------------------------------------

if ! python3 tools/handover-check.py --ledger "$LEDGER" "$DRAFT"; then
  cat >&2 <<EOF

handover: the generated handover did not pass the claim-checker, so it is
not being reported. The rejected draft and the ledger it was checked
against are kept for diagnosis:

    draft:  $DRAFT
    ledger: $LEDGER

Each violation above is a bug in this generator — the prompt in
tools/handover-prompt.md, or the checker's own rules. Fix one of those;
do not weaken the check to make a draft pass.
EOF
  exit 1
fi

echo "" >&2
cat "$DRAFT"

if [ "$KEEP" -eq 1 ]; then
  echo "" >&2
  echo "handover: kept at $DRAFT (ledger: $LEDGER)." >&2
else
  echo "" >&2
  echo "handover: draft at $DRAFT, ledger at $LEDGER." >&2
fi
