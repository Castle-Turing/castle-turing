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
can compare by switching to them, and restores whatever font the host
is configured for (`console.font`, via /etc/vconsole.conf) when you are
done — not the kernel default, which on a HiDPI host would leave the
console worse than it started.

Every display value in `docs/tasks/0017-legible-defaults.md` was picked
this way. That was a deliberate reaction to
`docs/tasks/0013-first-deploy-findings.md`, where a cursor size was
reasoned into place and shipped unusably wrong — a mistake no further
reasoning would have caught and thirty seconds of looking did. These
scripts exist because that brief instructs its reader to *re-run the
sweep* rather than edit a digit, and an instruction to re-run something
that lives only in a dead session is worthless.

`--font-dir DIR` exposes fonts that are not installed system-wide (a
store path is fine) through a scratch `XDG_DATA_HOME` and `XDG_CACHE_HOME`,
so nothing is written to your home — including fontconfig's cache, which
otherwise lands in `~/.cache/fontconfig` even when the font directory is
redirected.

One trade that follows from it: overriding `XDG_DATA_HOME` also hides
your real `~/.local/share/fonts` from the swept processes, so a face
installed only there won't appear in the comparison unless you pass its
directory as another `--font-dir`.

**`console-font-sweep.sh` needs sudo and changes VT state.** `setfont`
is privileged. It restores the host's configured font on every VT it
touched, including on Ctrl-C, and never touches the VT your graphical
session is on — but if it is killed with `-9`, reset by hand with
`sudo setfont -C /dev/ttyN <font>`.

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

## `handover.sh` — the where-we-are report, and the check that gates it

```
tools/handover.sh [--since DATE] [--until DATE] [--ledger FILE] [--out DIR]
```

Reads the ledgers this repo already accumulates — git history, pull
requests via `gh`, `docs/tasks/` and `done/`, the backlog, the journal if
the machine has one, and `docs/state/MILESTONE.md` — and emits one
screenful: the milestone restated, threats and drift *before*
accomplishments, what changed as receipts with citations, what could not
be grounded, and the short list of decisions only the resident can make.
On demand only. Cadence and channel are the resident's to decide once
this exists to have an opinion about, and `docs/tasks/0062` reserves
them.

Three files, and the split between them is the design:

- **`handover-ledger.py`** turns git, the forge and the working tree into
  artifact state as JSON. No model in it. This is what makes the brief's
  derivation rule — claims come from artifact state, never from an
  agent's account of its own work — enforceable rather than
  aspirational.
- **`handover-prompt.md`** is the format, handed to the agent turn, and
  doubles as the human-readable spec of that format.
- **`handover-check.py`** is a pure function of (ledger, handover). It
  resolves every citation and matches every receipt phrase against the
  artifact it names, and it **blocks**.

The model sits between two things it cannot influence: it chooses what to
say and how to group it, never what is true.

### Why the check blocks rather than warns

The generator controls its own output, so a violation is a bug in this
tool, not a style disagreement with a third party. And the specific thing
being guarded against — the confident-closure register, "done",
"complete", "successfully" — is a trained default with a measurable
signature that model judges talk themselves out of
(`docs/research/operator-handover.md` §3). An instruction not to use it
is not a control; a lint is. `docs/state/MILESTONE.md`'s
`[m2-constraints]` carries the same rule with no fallback: a reporting
surface that cannot comply does not ship.

### The one hazard worth knowing before you run it

A ledger built on a real machine carries **journal record ids**, which
are private layer and may never be committed to this repo. `handover.sh`
therefore writes to a scratch directory under `$TMPDIR` by default,
outside the checkout, and `handover-ledger.py --no-journal` exists for
the case that matters — building something that gets committed, like the
fixture under `test/handover/`. This is scar tissue: the reader's first
run wrote 308 real record ids and their absolute paths into a fixture.

### Verification

`test/handover/run.sh`, in CI. It runs the checking half only — the
generating half needs `gh`, the network and a model, and CI has none of
them. Read that directory's README before adding a fixture.

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

## `outcomes/` — the task-outcome log's mechanism

```
tools/outcomes/outcomes check [--base REF] [--no-base]
tools/outcomes/outcomes derive [--harness-journal FILE]... [--env KEY] [--fill]
```

The instrument specced in task 0070 and defined in
`docs/measurement.md`. `docs/log/task-outcomes.tsv` carries one row per
task attempt, and this is what keeps it honest.

Two subcommands, deliberately unequal. `derive` reads git and — when
pointed at one — a harness journal, and writes rows; it needs a
repository, a history, and paths outside the checkout. `check` is a
pure function of (log, working tree): no network, no forge, no model,
no clock. It is what CI runs, and it still runs on a clone made after
the forge this repository lives on has stopped existing. That is the
same split `handover-ledger.py` and `handover-check.py` make, for the
reason task 0062 gives.

What `check` guards, in one list: rows are append-only against the
trunk, immutable cells never change, a pending cell goes from `-` to a
value exactly once, every brief under `docs/tasks/` has a row, a
verdict column carries a citation to where the resident said it, a
redirect count never appears without its miscorrection rate beside it,
salt never wears a real brief's name, and a note never carries an
address or a home path.

The coverage rule is the detector, in the sense the "an incident ships
its detector" convention means: a task that lands unlogged fails the
very next pull request, which is the only moment the row is still cheap
to write. Everything else in the design is downstream of one property —
a pre-intervention baseline is worth nothing if its past can be quietly
improved.

### Why this isn't in `agent/`

Same test as `codex-review.sh` and `clarify/`: it never touches a
journal and never runs as a seat. It measures the pipeline that builds
this repository, from inside this repository, which is what `tools/` is
for. Unlike those two it does not sit on the sweep scripts' unresolved
boundary — a resident who is not developing this framework has no tasks
to log.

### Verification

`test/outcomes/run.sh`, in CI via `.github/workflows/outcomes-check.yml`.
It runs `check` over the real log, then builds a synthetic repository
and mutates it once per rule — twenty-odd rejects, each asserted to be
caught by the rule that owns it, plus the three transitions that must
still be *allowed*. Plain bash, stdlib python3, no Nix, no network,
zero models.

## `clarify/` — check a clarifying-questions phase run

```
tools/clarify/clarify check docs/state/<requirements>.md
tools/clarify/clarify probe build cursor-too-small --out /tmp/run
tools/clarify/clarify probe score cursor-too-small /tmp/run
tools/clarify/clarify probe oracle cursor-too-small
```

The mechanical half of the phase specced in task 0065 and written out in
`docs/clarifying-questions.md`. It does not *run* the phase — a seat does
that, and the judgment stays there. It reads what the seat produced (a
requirements document and the conversation behind it) and says whether
the discipline was followed: every question cites the ambiguity it would
resolve, every nocuous ambiguity is asked about or explicitly passed
over, the phase stopped under a rule whose terms it stated and whose
arithmetic holds, every clause traces to something the resident said or
admits to being inferred, and every substantive thing the resident said
reached some clause.

Read `docs/clarifying-questions.md` before the script; the script's
comments say what each check does, and the document says why it is a
check at all and — for the two rules that could not be made mechanical
— what it deliberately does not check.

`probes/` holds seeded probes: a complete statement, plus a seed record
that deletes answers out of it. `test/clarify/run.sh` runs the whole
thing in CI, and is mostly its negative half — twenty-odd mutations of
the worked example, each asserted to be caught by the rule that owns it.

### Why this isn't in `agent/`, and the boundary it sits on

Same test as `codex-review.sh` above: this never touches a journal and
never runs as a seat. Today the phase produces a document in
`docs/state/` — a file in this repo — and the sessions running it are
sessions editing this repo, which is what `tools/` is for. Putting it in
`agent/` would also install a half-built, unwired phase onto deployed
machines and drag a Nix rebuild behind every edit to a lint.

But the honest version is that this sits on the same unresolved boundary
`font-sweep.sh` does, and closer to the edge. The clarifying-questions
phase is *destined* for the product: the milestone it serves ends with a
resident opening the modal, stating a complaint, and being asked good
questions. When that wiring lands, the checks belong wherever the phase
does. Parked here deliberately, with the tension recorded rather than
papered over — the same call, and the same reasoning, as the sweep
scripts.
