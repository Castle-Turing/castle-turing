# tools/ — developer tooling for working on this repo

Not the agent layer (`agent/` is Castle Turing's own product — the record
format, the `castle` CLI, the modal intake). This directory holds scripts
for the humans and agent sessions who *work on* this repo: the pre-PR
ritual, not anything a deployed system runs.

## `font-sweep.sh` / `console-font-sweep.sh` — pick display values by looking

```
tools/font-sweep.sh terminal 'monospace:size=11' 'monospace:size=12'
tools/font-sweep.sh ui 'DejaVu Sans 11' 'Iosevka Aile Medium 10'
tools/console-font-sweep.sh spleen:spleen-16x32 terminus_font:ter-v32n
```

Open N candidates side by side with one variable changed, look, then
press Enter to tear it all down. `terminal` tiles foot panes on a
scratch workspace; `ui` stacks swaynag bars (the surface that renders
Sway titlebars, the nagbar, and — via the same Pango description — GTK
chrome); `console-font-sweep.sh` loads PSF fonts onto spare VTs so you
can compare by switching to them, and restores the kernel default when
you are done.

Every display value in `docs/tasks/0017-legible-defaults.md` was picked
this way. That was a deliberate reaction to
`docs/tasks/0013-first-deploy-findings.md`, where a cursor size was
reasoned into place and shipped unusably wrong — a mistake no further
reasoning would have caught and thirty seconds of looking did. These
scripts exist because that brief instructs its reader to *re-run the
sweep* rather than edit a digit, and an instruction to re-run something
that lives only in a dead session is worthless.

`--font-dir DIR` exposes fonts that are not installed system-wide (a
store path is fine) through a scratch `XDG_DATA_HOME`, so nothing is
written to your home and no `fc-cache` runs against `~`.

**`console-font-sweep.sh` needs sudo and changes VT state.** `setfont`
is privileged. It restores the kernel default on every VT it touched,
including on Ctrl-C, and never touches the VT your graphical session is
on — but if it is killed with `-9`, reset by hand with `sudo setfont -C
/dev/ttyN`.

### An unresolved boundary

These do not cleanly fit this directory's charter, stated above: "no
reason to exist on a resident's actual machine after this repo stops
changing." That is true of `codex-review.sh` and false of these. A
resident re-runs a font sweep whenever they want to change how their
machine looks, which is a customisation task, not a repo-editing task —
and Castle Turing is supposed to be *about* easy customisation.

So either this directory's scope widens, or these eventually belong on
a deployed system as a real command (`castle-font-sweep` on `$PATH`
from `modules/desktop`) — which is a decision about the framework's
product surface, not a tooling tidy-up. Parked here deliberately, with
the tension recorded rather than papered over. See scope item 10 of
`docs/tasks/0017-legible-defaults.md`.

## `codex-review.sh` — the second, cross-model opinion

```
tools/codex-review.sh [--base REF] [--pr N] [--post] [--title TEXT]
```

Runs a review of the current branch's diff through the [Codex
CLI](https://developers.openai.com/codex/cli) (`codex exec review`) and
prints the result verbatim. With `--post`, posts that same output — word
for word, no editing — as a comment on the current branch's open PR.

Read the script itself for the full story; the header comment is long on
purpose, because the thing it replaces failed silently and this one is
designed not to. Short version: `CLAUDE.md` describes a two-model review
ritual — `/code-review` (Claude) plus Codex reviewing the PR as an
independent second opinion. The GitHub-integrated half of that stopped
running when this repo moved to the `Castle-Turing` org (that integration's
automatic review requires a ChatGPT Pro plan on an org-owned repo, and
nothing about the failure was visible from inside GitHub or Codex's own
settings). This script gets the second opinion back by running the *Codex
CLI* instead — a different product, authenticated against the same ChatGPT
sign-in, that operates on local files and has nothing to do with GitHub's
App or its org-plan gate.

### Where it fits in the pre-PR ritual

`CLAUDE.md` already says: run `/code-review` on the branch and address its
findings before opening a PR. Add this step alongside it, after the PR
exists (Codex needs something to diff against and somewhere to post to):

1. `/code-review` locally, as before — fix what it finds.
2. Open the PR.
3. `tools/codex-review.sh --post` — posts Codex's raw findings as a PR
   comment.
4. Read that comment and reply with a **separate** comment underneath:
   Claude's disposition of each finding — agreed and fixed (with the fix
   commit), or disagreed and why. Never silently skip a finding, and never
   edit the comment Codex's output landed in — the human needs to see both
   the original finding and the response to it.

   **This step is manual — nothing automates it for CLI-posted reviews.**
   `.github/workflows/claude-codex-followup.yml` triggers only on a
   `pull_request_review` event authored by the `chatgpt-codex-connector[bot]`
   GitHub App — the *integrated* review this tool replaces. `gh pr comment`
   (what `tools/codex-review.sh --post` uses) creates a plain issue
   comment from the human's own `gh` identity, which is neither of those
   things, so that workflow never fires on it. Step 4 above is the
   substitute: a human or an agent session doing by hand what that
   workflow does automatically for the App-integrated flow. See "Why a
   script instead of a GitHub Action," below, for why this wasn't wired up
   the same way.

### Why a script instead of a GitHub Action

The Codex CLI authenticates via an interactive ChatGPT login (or an API
key). Running it in CI would mean either handing a long-lived credential to
a GitHub Actions runner — a bigger blast radius for a repo whose whole
premise is legible, auditable automation — or paying for API usage that
duplicates a subscription already paid for, to review a repo that's mostly
worked on from one machine. A local script run by hand (or by an agent
session with the same access the human has) avoids both, at the cost of
being one more manual step. `docs/backlog/weekly-audit-vigilance.md`'s
whole argument is that manual steps decay under repetition — worth
remembering if this one starts getting skipped.

### Why this isn't in `agent/`

`agent/` is Castle Turing's own product: the record format and the `castle`
CLI that a deployed system runs. This script never touches a journal,
never runs as a seat, and has no reason to exist on a resident's actual
machine after this repo stops changing — it's tooling for people (and
agent sessions) editing the repo itself, which is what `tools/` is for.
