#!/usr/bin/env bash
# tools/codex-review.sh — the second, cross-model opinion, run locally.
#
# WHY THIS EXISTS (read this before touching the script)
#
# CLAUDE.md's review paragraph says: "run `/code-review` on the branch...
# Codex reviews the PR itself as a second, cross-model opinion." The second
# half of that stopped happening, silently, the day this repo moved under
# the Castle-Turing GitHub org: GitHub-integrated Codex code review on an
# *organization-owned* repo requires a ChatGPT Pro plan, and this resident
# has Plus. Nothing errored. Nothing warned. Reviews just stopped being
# attempted, and the only symptom was a greyed-out toggle with the reason in
# a tooltip. Full diagnosis: PR #28
# (https://github.com/Castle-Turing/castle-turing/pull/28), branch
# backlog-codex-paywall, docs/backlog/cross-model-review-is-paywalled.md —
# linked as a PR rather than a repo-relative path because that file may not
# exist on whatever branch you're reading this from yet: it lands on `main`
# only once #28 merges (or, if it's since been specced into a numbered task
# brief, whatever superseded it — check git log for that file's history).
#
# The value of a second reviewer was never "finds more bugs" — it's "finds
# *different* bugs," because a model reviewing its own family's work shares
# its family's blind spots. That's worth paying a script for even when it's
# mildly annoying to run by hand.
#
# The fix here is NOT the GitHub App integration. It's the Codex *CLI*
# (`codex`, npm package `@openai/codex`), a separate product that runs
# locally against files on disk over your ChatGPT sign-in. It has nothing to
# do with GitHub's App, org-owned repos, or that plan gate — verified by
# hand before this script was written: `codex login status` succeeded on an
# existing Plus-plan ChatGPT session with no upgrade, and
# `codex exec review --base origin/main` produced a real, useful review
# (correctly flagging a deliberately-planted bug, file:line and all) with
# nothing but that login. See this tool's introducing PR description for
# the verification transcript.
#
# WHAT THIS SCRIPT DELIBERATELY DOES NOT DO
#
#   - It does not judge Codex's findings. That is a separate, later step,
#     done by a human or by Claude reading this script's output — never by
#     this script, and never by editing the text below before a human sees
#     it. A model summarizing or filtering an independent reviewer's words
#     reintroduces that same model's blind spots into the one check meant
#     to be free of them. This script's job stops at "here is exactly what
#     Codex said."
#   - It does not retry, hide, or soften a failure. If Codex isn't
#     installed, isn't logged in, is rate-limited, or there's simply
#     nothing to review, this script says so loudly on stderr and exits
#     nonzero. A cross-model review step that fails silently is the exact
#     failure mode that caused the gap this script fills — see the backlog
#     doc above, whose whole first section is "nothing failed, it just
#     stopped happening." This script would rather be annoying than quiet.
#   - It is not a daemon, a git hook, or a CI job. It is one more step in
#     the human's (or an agent's) pre-PR ritual, run by hand next to
#     `/code-review`, on purpose — CI has no ChatGPT login to hand it, and
#     giving it one via CODEX_API_KEY would spend API credits duplicating a
#     subscription this resident already pays for, for a repo that mostly
#     runs on one person's machine anyway. Keep it boring.
#
# USAGE
#
#   tools/codex-review.sh [--base REF] [--pr N] [--post] [--title TEXT]
#
#   --base REF     Compare the current branch against REF instead of the
#                   default, origin/main. Per CLAUDE.md's own rule for
#                   `/code-review`, always diff against a freshly-fetched
#                   remote ref, never a local branch — this script does not
#                   fetch for you (a script silently fetching on your
#                   behalf is its own surprise); run `git fetch origin`
#                   first if you're not sure origin/main is current.
#   --pr N          Post to PR #N instead of auto-detecting the PR open for
#                   the current branch. Only meaningful with --post.
#   --post          After a successful review, post Codex's raw output as a
#                   PR comment via `gh pr comment`, wrapped in a short
#                   attribution header/footer this script adds (identifying
#                   it as Codex CLI output, not GitHub-integrated Codex, and
#                   pointing at this file) but never touching a word of
#                   Codex's own text. Without --post, the review is only
#                   printed to stdout and saved to a temp file whose path is
#                   printed at the end — read it, or post it yourself.
#   --title TEXT    Passed through to `codex exec review --title`; purely
#                   cosmetic, shown in Codex's own summary line. Defaults to
#                   the current branch name.
#
# After this script posts (or you post its saved output) to the PR, the
# NEXT step — not automated here, because it requires judgment this script
# doesn't have — is for Claude to read the posted comment and reply
# separately and underneath: "agreed, fixed in <commit>" or "disagreed,
# because <reason>" for each finding, never silently skipping one. Both the
# original finding and its disposition must stay visible to the human in
# the PR thread. See this tool's introducing PR description for the
# proposed CLAUDE.md wording that documents this as the new ritual step.

set -euo pipefail

# --- argument parsing -------------------------------------------------

BASE="origin/main"
PR=""
POST=0
TITLE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --base|--pr|--title)
      # A value-taking flag with nothing after it, or with another flag
      # immediately after it, are both real user mistakes worth a clear
      # message rather than either of the two bad things that happened
      # here before this check existed: under `set -u`, `--base` with no
      # following argument crashed on a raw "$2: unbound variable" instead
      # of a usage error; and `--base --post` silently consumed "--post"
      # as --base's *value*, leaving POST unset with no indication why the
      # post never happened. Caught by a Codex CLI review of an earlier
      # version of this script.
      FLAG="$1"
      if [ $# -lt 2 ] || [[ "$2" == -* ]]; then
        echo "tools/codex-review.sh: $FLAG requires a value." >&2
        echo "Run with --help for usage." >&2
        exit 2
      fi
      case "$FLAG" in
        --base) BASE="$2" ;;
        --pr) PR="$2" ;;
        --title) TITLE="$2" ;;
      esac
      shift 2
      ;;
    --post)
      POST=1
      shift
      ;;
    -h|--help)
      # Print this file's own header comment as the help text, rather than
      # maintaining a second, shorter description that inevitably drifts
      # from the real one above.
      sed -n '2,/^set -euo pipefail/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "tools/codex-review.sh: unrecognized argument: $1" >&2
      echo "Run with --help for usage." >&2
      exit 2
      ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [ -z "$TITLE" ]; then
  TITLE="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "codex-review")"
fi

# --- preflight: is there even a `codex` to run? ------------------------

if ! command -v codex >/dev/null 2>&1; then
  cat >&2 <<'EOF'
codex-review: the Codex CLI isn't installed.

Install it with:
    npm install -g @openai/codex

(Requires Node.js. If you don't have npm, see
https://developers.openai.com/codex/cli — do not guess at a different
package name; the CLI has been renamed before.)

Nothing was reviewed. This is a hard stop, not a skip: a cross-model
review step that quietly does nothing is the exact failure this script
exists to avoid repeating.
EOF
  exit 1
fi

# --- preflight: is it logged in? ---------------------------------------
#
# `codex login status` exits 0 and prints "Logged in using ChatGPT" (or an
# API-key equivalent) when authenticated. This script never runs `codex
# login` itself and never will — authentication is an interactive, human
# step (a browser OAuth flow or an API key), and a script silently trying
# to authenticate on someone's behalf is a credential-handling foot-gun,
# not a convenience.
#
# Every `mktemp` call in this script uses an explicit "$TMPDIR/prefix.XXXXXX"
# template rather than `-t prefix`, on purpose: BSD/macOS mktemp treats
# `-t prefix` as a convenience flag, but GNU coreutils mktemp (what a NixOS
# host — this project's actual deployment target — ships) treats the
# argument as a template and requires it to contain literal `X`
# characters, so `-t codex-review-foo` fails outright on Linux. The
# explicit-template form works identically on both. A Codex CLI review of
# an earlier version of this script caught this exact bug before it ever
# shipped.

LOGIN_STATUS_FILE="$(mktemp "${TMPDIR:-/tmp}/codex-review-login-status.XXXXXX")"
if ! codex login status >"$LOGIN_STATUS_FILE" 2>&1; then
  cat >&2 <<EOF
codex-review: the Codex CLI is installed but not logged in.

$(cat "$LOGIN_STATUS_FILE")

Log in yourself with:
    codex login

(ChatGPT sign-in via a Plus plan is sufficient — the GitHub-integrated
Codex review that required a Pro plan on org-owned repos is a different
product from this CLI; see this script's header comment.) Then re-run
this script.

Nothing was reviewed.
EOF
  rm -f "$LOGIN_STATUS_FILE"
  exit 1
fi
rm -f "$LOGIN_STATUS_FILE"

# --- preflight: is there actually a diff to review? ---------------------
#
# Handled explicitly, before ever invoking `codex`, rather than letting
# Codex discover "there's nothing here" on its own: an empty-diff run still
# spends a model call and produces a review that says "no changes," which
# reads exactly like a healthy "no issues found" result unless you're
# looking closely. Distinguishing "nothing to review" from "reviewed and
# found nothing" up front is the whole point of this script refusing to be
# quiet about its own failure modes.

if ! git rev-parse --verify --quiet "$BASE" >/dev/null; then
  echo "codex-review: base ref '$BASE' doesn't resolve. Did you \`git fetch origin\` first?" >&2
  exit 1
fi

# CLAUDE.md's rule for /code-review: "Scope every review and diff against
# origin/main, never a local branch ref... a stale base produces confident
# findings about code you never touched." A bare local branch name passed
# to --base is exactly that trap — it can sit arbitrarily far behind the
# real origin/main with nothing here noticing. This is a warning, not a
# hard rejection: a full commit SHA never goes stale (it names one
# immutable commit) and a differently-named remote (upstream/main,
# fork/main) is a legitimate override this script has no business
# blocking, so the check only fires on what actually resolves as a local
# branch — checked directly against `refs/heads/`, before the SHA-shape
# check below, so a hex-named local branch (`git checkout -b deadbeef`)
# still gets flagged instead of being waved through because its name
# happens to look like a commit id.
IS_LOCAL_BRANCH=0
if git show-ref --verify --quiet "refs/heads/$BASE"; then
  IS_LOCAL_BRANCH=1
  echo "codex-review: warning — '$BASE' looks like a local branch, not a remote ref. Consider --base origin/$BASE (after \`git fetch origin\`) instead — see CLAUDE.md's review-scoping rule." >&2
fi

# Staleness nudge — does not fetch, and never silently would (see the
# header comment's "boring, no surprise network calls" rule). Skipped
# entirely for a bare commit SHA (nothing to go stale: it names one
# immutable commit forever) — recognized by shape AND by NOT already
# having resolved as a local branch above, since a hex-named branch must
# still get checked like any other mutable ref, not waved through by
# `git show-ref` never firing on refs/remotes/that-hex-name.
#
# This does NOT use `.git/FETCH_HEAD`'s mtime, on purpose, after two
# rounds of dogfooding this script against itself found it wrong twice
# over: FETCH_HEAD is worktree-local (`git worktree` — the multi-agent
# setup CLAUDE.md itself mandates — gives each worktree its own, so a
# freshly-added worktree with a perfectly current origin/main falsely
# reports "never fetched"), and even where it exists its mtime reflects
# "was *anything* fetched from this worktree recently," not "is $BASE
# itself current" (fetching an unrelated branch refreshes it while
# origin/main sits stale). What actually answers "when was $BASE itself
# last updated, from any worktree" is $BASE's own reflog — shared across
# worktrees, like all of refs/ and logs/refs/, and updated only when that
# specific ref moves.
LOOKS_LIKE_SHA=0
if [[ "$BASE" =~ ^[0-9a-f]{7,40}$ ]] && [ "$IS_LOCAL_BRANCH" -eq 0 ]; then
  LOOKS_LIKE_SHA=1
fi
if [ "$LOOKS_LIKE_SHA" -eq 0 ]; then
  # `%ct`/`%cd` (even under `git log -g`) is the *commit object's* own
  # committer timestamp, not the reflog entry's — a ref fetched five
  # minutes ago can point at a commit that was authored last week, and
  # `%ct` reports the week, not the five minutes. `%gd` is the field that
  # actually carries the reflog entry's own time, and only when combined
  # with `--date=unix` does it render as `ref@{<unix-timestamp>}` instead
  # of `ref@{<Nth-entry>}` — hence the grep to pull the number back out.
  # A Codex CLI review of an earlier version of this script (which used
  # `%ct`) caught this: it warned on a freshly-fetched-but-old-commit
  # `origin/main` and would have stayed silent on the opposite case, a
  # stale ref that happened to point at a recent commit.
  #
  # The extraction below pulls the digits out of the `@{...}` braces
  # *specifically*, not just any digit run in the line: a first attempt at
  # this used a bare `grep -oE '[0-9]+'`, which also matches digits that
  # are simply part of the ref's own name (`origin/release/2025` produces
  # `origin/release/2025@{<timestamp>}`, and that grep returns both "2025"
  # and the timestamp on separate lines, turning $REF_MTIME into a
  # multi-line value that breaks the arithmetic below). Also a Codex CLI
  # finding.
  # The trailing `|| true` matters under this script's `set -e -o
  # pipefail`: if `$BASE` has no reflog at all, `git log -g` itself exits
  # nonzero, and pipefail propagates that through `sed` (which exits 0 on
  # simply finding no match) to the whole pipeline — which, inside a `$()`
  # feeding a variable assignment, would otherwise abort the script here
  # instead of falling through to the "no reflog history" message below.
  REF_MTIME="$(git log -g -1 --date=unix --format=%gd "$BASE" 2>/dev/null | sed -n 's/.*@{\([0-9]\{1,\}\)}.*/\1/p' || true)"
  if [ -z "$REF_MTIME" ]; then
    echo "codex-review: warning — no local reflog history for '$BASE', so its last-updated time can't be determined here. If it's a remote ref, run \`git fetch origin\` first, or this review may be scoped against a stale base." >&2
  else
    FETCH_AGE_SECONDS=$(( $(date +%s) - REF_MTIME ))
    if [ "$FETCH_AGE_SECONDS" -gt 900 ]; then
      echo "codex-review: warning — '$BASE' was last updated $(( FETCH_AGE_SECONDS / 60 )) minutes ago, per its own reflog. If it's a remote ref, consider \`git fetch origin\` first." >&2
    fi
  fi
fi

if git diff --quiet "$BASE"...HEAD 2>/dev/null; then
  cat >&2 <<EOF
codex-review: no diff between HEAD and '$BASE'. Nothing to review.

If you meant to review uncommitted changes, commit them first (Codex
reviews the diff against $BASE, not your working tree) — or edit this
script to add a --uncommitted passthrough if that becomes a real need.
EOF
  exit 1
fi

# --- run the review ------------------------------------------------------
#
# `codex exec review` (the *automation-oriented* review subcommand, under
# `exec`, distinct from the bare top-level `codex review`) is used
# deliberately: with `-o/--output-last-message`, it writes only the model's
# final review text to a file, cleanly separated from the exploratory
# tool-call transcript (file reads, greps, git-diff calls) it prints to
# stdout while working. The transcript is Codex's scratchpad, useful for
# debugging this script, not for the PR — only the file this flag writes is
# "Codex's output" in the sense the verbatim-posting rule means.

OUTPUT_FILE="$(mktemp "${TMPDIR:-/tmp}/codex-review-output.XXXXXX")"
TRANSCRIPT_FILE="$(mktemp "${TMPDIR:-/tmp}/codex-review-transcript.XXXXXX")"
trap 'rm -f "$TRANSCRIPT_FILE"' EXIT

echo "codex-review: running \`codex exec review --base $BASE\` — this calls out to your ChatGPT-authenticated Codex session and may take a few minutes." >&2

CODEX_EXIT=0
codex exec review --base "$BASE" --title "$TITLE" -o "$OUTPUT_FILE" \
  >"$TRANSCRIPT_FILE" 2>&1 || CODEX_EXIT=$?

if [ "$CODEX_EXIT" -ne 0 ]; then
  cat >&2 <<EOF
codex-review: \`codex exec review\` exited nonzero ($CODEX_EXIT). Nothing
was posted. Full transcript below — the most common causes are a lapsed
login (re-run \`codex login\`), hitting your ChatGPT plan's Codex usage
limit (check https://chatgpt.com/codex/settings/usage), or a transient
API error worth simply retrying.

--- transcript ---
$(cat "$TRANSCRIPT_FILE")
--- end transcript ---
EOF
  exit 1
fi

if [ ! -s "$OUTPUT_FILE" ]; then
  cat >&2 <<EOF
codex-review: \`codex exec review\` exited 0 but wrote no review text.
Treating this as a failure rather than silently reporting "no findings" —
an empty successful-looking result is precisely the kind of silent no-op
this script exists to refuse. Transcript below.

--- transcript ---
$(cat "$TRANSCRIPT_FILE")
--- end transcript ---
EOF
  exit 1
fi

# --- report ---------------------------------------------------------------

echo "codex-review: review complete. Raw output follows verbatim." >&2
echo "" >&2
cat "$OUTPUT_FILE"
echo ""
echo "codex-review: raw output also saved at: $OUTPUT_FILE" >&2

if [ "$POST" -eq 0 ]; then
  echo "codex-review: not posting (pass --post to post to the PR). Review the file above, then either re-run with --post or post it yourself with:" >&2
  echo "    gh pr comment <PR> --body-file '$OUTPUT_FILE'" >&2
  exit 0
fi

# --- posting ---------------------------------------------------------------
#
# The wrapper below adds attribution and a pointer back to this script and
# the disposition step that must follow it. It never rewrites, trims, or
# reflows a single word of $OUTPUT_FILE's contents — everything after the
# "---" rule is byte-for-byte what Codex wrote.
#
# `gh` gets the same two-stage "is it even here, is it usable" preflight
# `codex` got above, rather than letting a missing/unauthenticated `gh`
# surface as a bare "no open PR found" — a diagnosis that's actively wrong
# (it tells you to push a branch and open a PR that may already exist) and
# was, before this check existed, indistinguishable from the genuine "no
# PR yet" case and from an ambiguous head-branch match. All three collapse
# to one `gh pr view` failure with its stderr discarded; this at least
# rules the first two causes out explicitly before blaming "no open PR."

if ! command -v gh >/dev/null 2>&1; then
  cat >&2 <<'EOF'
codex-review: --post was given but the GitHub CLI (`gh`) isn't installed.

Install it (see https://cli.github.com), run `gh auth login`, and re-run
this script — or drop --post and post the saved review yourself.

Nothing was posted; the review above is still saved to disk.
EOF
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  cat >&2 <<'EOF'
codex-review: --post was given but `gh` isn't authenticated.

Run `gh auth login`, then re-run this script — or drop --post and post
the saved review yourself.

Nothing was posted; the review above is still saved to disk.
EOF
  exit 1
fi

if [ -z "$PR" ]; then
  if ! PR="$(gh pr view --json number -q .number 2>/dev/null)"; then
    cat >&2 <<'EOF'
codex-review: --post was given but no open PR was found for the current
branch (and no --pr N was given). This can also mean the current branch's
head matches more than one open PR, which `gh pr view` refuses to
disambiguate — pass --pr N explicitly in that case. Push the branch and
open the PR first if it doesn't exist yet.

Nothing was posted; the review above is still saved to disk if you want
to post it by hand later.
EOF
    exit 1
  fi
fi

POST_FILE="$(mktemp "${TMPDIR:-/tmp}/codex-review-post.XXXXXX")"
{
  printf '## Cross-model review — Codex CLI (raw, unfiltered)\n\n'
  printf 'Generated locally via `tools/codex-review.sh` (`codex exec review --base %s`), ' "$BASE"
  printf "not GitHub's Codex integration — see PR #28 "
  printf '(https://github.com/Castle-Turing/castle-turing/pull/28, '
  printf 'docs/backlog/cross-model-review-is-paywalled.md) for why that integration stopped running. '
  printf 'Everything below the rule is Codex'"'"'s own output, unedited by any other model. '
  printf "Claude's disposition of each finding — agreed and fixed, or disagreed and why — follows as a separate comment underneath.\n\n"
  printf -- '---\n\n'
  cat "$OUTPUT_FILE"
} >"$POST_FILE"

# `set -e` would otherwise kill the script mid-post with a bare `gh`
# stderr and no explanation — and, worse, skip the cleanup below, leaving
# a stray file holding the full review text sitting in $TMPDIR. Capturing
# the exit code explicitly avoids both: a clear message either way, and
# $POST_FILE is always removed once we've decided what to tell the user.
POST_EXIT=0
gh pr comment "$PR" --body-file "$POST_FILE" || POST_EXIT=$?
rm -f "$POST_FILE"

if [ "$POST_EXIT" -ne 0 ]; then
  cat >&2 <<EOF
codex-review: \`gh pr comment\` failed (exit $POST_EXIT) while posting to
PR #$PR. Common causes: the PR was closed or merged since --pr/auto-detect
ran, the auth token expired mid-run, or a network error. The review text
itself is unaffected and still saved at: $OUTPUT_FILE — post it by hand
once the underlying problem is fixed:
    gh pr comment $PR --body-file '$OUTPUT_FILE'
(note: that command posts the raw review with no attribution wrapper;
re-run this script with --post to get the wrapped version instead.)
EOF
  exit 1
fi

echo "codex-review: posted to PR #$PR." >&2
echo "codex-review: next step — read the comment just posted, then reply with Claude's disposition of each finding as a SEPARATE comment underneath (agreed+fixed, or disagreed+why). Do not edit the comment just posted." >&2
