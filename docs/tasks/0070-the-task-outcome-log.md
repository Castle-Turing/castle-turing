Title: Task 0070 — the task-outcome log
Model: deep
Milestone: m2-constraints
Model-because: the deliverable is a measurement instrument whose first
rows are a baseline that must never be rewritten, and almost every
decision in it is a judgment about what may honestly be claimed from a
number — which columns are receipts and which are verdicts, what a
backfilled cell is allowed to assert, where the private-layer line
falls in a file of counts. A standard implementer following an exact
spec would produce a working TSV and a working checker; what breaks is
a column that quietly promotes a receipt to a verdict, or a
reconstructed pre-period that reads like an observed one. Both failures
look like a clean green diff.

# Task 0070 — the task-outcome log

## Where this came from

`docs/backlog/the-workflow-interventions-have-no-outcome-measures.md`,
promoted and deleted by this commit. Its substance is already a binding
constraint: `docs/state/MILESTONE.md` `[m2-constraints]`, first clause,
says task-level outcome logging must be running before pipeline-changing
work lands, and that every measure without a pre-period is forfeit if it
is not.

The reason that constraint exists is narrow and worth restating.
Milestone two changes the workflow continuously, one intervention at a
time. `docs/research/measurement-methodology.md` found that the only
single-unit causal design that transfers to a one-resident project is an
interrupted time series, that it needs task-level outcomes logged
*before* the interventions and a stable pre-period, and that applying it
to an agentic workflow appears to be unprecedented. It also found that
two of this project's planned measures — off-milestone spend share and
question-routing latency — have no validating literature anywhere, and
that a redirect count reported without its miscorrection rate is
uninterpretable.

So this task is not "add metrics." It is: start the clock, in a form
whose past cannot later be improved, before the queue behind it moves.

## What lands

**`docs/measurement.md`** — the mechanism document, and the authority
for everything below. What a task outcome is, the twenty-four columns of
schema 1 with each one's meaning and kind, the receipt/verdict split,
the environment table, the write-once rules, what may honestly be said
from the log, the four requirements that keep a multi-installation
future open, and what the log deliberately does not measure. It is a
mechanism document in the sense `docs/clarifying-questions.md` is one —
public, versioned, inherited by anyone deploying this framework — and
explicitly not `docs/state/` truth.

**`docs/log/task-outcomes.tsv`** — the log, with `docs/log/README.md`
saying why the directory exists and why it is a record rather than
state.

**`tools/outcomes/outcomes`** — stdlib Python, two subcommands and a
deliberate inequality between them:

- `derive` reads git and, when pointed at one, a harness journal, and
  writes rows. It needs a repository, a history, and paths outside the
  checkout.
- `check` is a pure function of (log, working tree). No network, no
  forge, no model, no clock. It is what CI runs, and it will still run
  on a clone made after the forge this repository lives on has stopped
  existing.

That is the same split `tools/handover-ledger.py` and
`tools/handover-check.py` make, for the reason task 0062 gives: a check
that re-derived truth from the live world fails for reasons having
nothing to do with the thing it is checking.

**`test/outcomes/run.sh`** and **`.github/workflows/outcomes-check.yml`**
— the harness and its gate.

**`docs/state/MILESTONE.md`** — `[m2-now]`'s baseline bullet moves from
"not started" to what is actually running, and `[m2-constraints]`'s
first clause gains the pointer to the mechanism that now satisfies it.

## The design decisions worth arguing with

**One row per task attempt, appended and matured.** A row is written
when an attempt starts and its remaining cells are filled as they become
knowable. The alternative — write the row when the outcome is terminal —
was rejected because it puts the write after the merge, which means
nothing in a pull request can gate on it, which means the log's
liveness depends on somebody remembering. The whole literature this
project is standing on says that decays.

**No in-flight `outcome` value.** An attempt that has not finished
leaves the cell `-`. The obvious alternative, an `open` that later
becomes `merged`, is a pending cell written twice — the exact rewrite
the write-once rule exists to forbid — and buying an in-flight marker
by punching a hole in that rule is a bad trade.

**Three cell classes, enforced against `origin/main`.** Immutable cells
are fixed at write. Pending cells go from `-` to a value exactly once.
`note` is the single amendable cell, because it is the only one that
could ever need redacting. The checker compares every change to the
base revision and rejects a deleted row, a changed immutable cell, or a
rewritten pending one. A pre-period nobody can quietly improve is the
entire product here; without this check the file is a well-formatted
opinion.

**A renamed brief does not deadlock the log.** A row's `task` is
immutable and a row is never deleted, so a brief renamed after its row
was written would otherwise be uncoverable: the checker would demand a
row that the append-only rule forbids writing. Coverage therefore
resolves a stale stem by number — but only where that number names
exactly one brief, because two briefs here are numbered `0003` and
guessing between them is the invention this design exists to keep out.

**Coverage is the detector.** Every brief under `docs/tasks/` or
`docs/tasks/done/` must have a row, checked on every pull request that
touches either. This is the answer to the convention's "an incident
ships its detector" requirement, and it is deliberately the *cheap*
moment: a task that lands unlogged fails immediately, while the facts
are still in someone's head, rather than being noticed a month later
when the row can only be guessed at.

**Two verdict columns, and a citation rule.** `redirects` and
`redirects_wrong` are the only cells in schema 1 that record a
resident's judgment. Proposal 06 says the system may grade its own
delivery and never its own judgment, so a non-zero verdict must carry a
`verdict_ref` naming where the resident actually said it, and the
checker refuses `redirects` without `redirects_wrong` beside it. That
second rule is the measurement review's design implication 1 made
mechanical: a detection rate without its conditional miscorrection rate
is uninterpretable, and this log will not hold half the pair.

**`env` on every row from the first row.** Infrastructure noise on
agentic evaluations is measured at up to six percentage points, larger
than many effects worth detecting. The column holds a key (`e1`) whose
expansion is a table in `docs/measurement.md` — content-free by
construction, which is requirement 2 of
`docs/backlog/measurement-is-designed-for-one-resident.md` satisfied at
definition time rather than at export time.

**Tab-separated, `-` for unrecorded.** Tabs never appear inside a cell
here and no cell is ever quoted, so `cut`, `awk`, `grep` and a
three-line reader all work on it forever — which is the plain-text
preference in `CLAUDE.md` applied to a file that has to outlive its
tooling. `-` rather than an empty cell so that a missing column is a
visible error rather than an invisible one, and so that `0` (measured
as zero) and `-` (never recorded) can never be confused.

## What the first logged rows are

Sixty-eight backfilled rows and one live row.

**The backfill** covers every numbered brief in the repository —
`0001-flake-eval-gate` through `0069-the-delivery-seat`, including both
files numbered `0003` and skipping the numbers 27 and 28, which were
never used. Each row is `provenance: backfilled` and carries only what
artifact state can honestly supply:

- `queued`, from the commit that first added a file with that number,
  following renames into `docs/tasks/done/`.
- `landed` and `pr`, from the earliest merge commit whose branch names
  that task number — which is why `0067`, whose brief and branch
  disagree about the slug, resolves correctly. For the era before
  branches were named after task numbers, the fallback is the merge that
  first carried the brief file to the trunk.
- `tier` and `milestone`, from the brief's own `Model:` and `Milestone:`
  headers where it has them. Both headers are themselves recent
  conventions, so this is thin: seven briefs carry `Milestone:` and
  thirteen carry `Model:`; the rest are `-`.
- `cost_usd`, `turns` and `model`, from the harness's usage ledger for
  the seventeen runs it has kept since 2026-08-31 — twenty-three rows
  get a real cost and twenty-two a real model. Only numbers are taken
  from that ledger; it lives outside this repository and nothing
  textual in it is ever copied in. One task, `0068`, was attempted
  twice, so its cost is left unrecorded: the column means "this
  attempt", summing would make it mean something else, and choosing one
  of the two would be arbitrary.

Everything else is `-`. In particular **every verdict cell in the
backfill is unrecorded**, and this is the single most important honesty
property of the whole exercise: nobody can reconstruct from git whether
the resident redirected an attempt, so nothing pretends to. A
reconstructed pre-period that reads like an observed one is worse than
no pre-period at all.

**The live row** is this task's own: `0070-the-task-outcome-log`,
attempt 1, `provenance: live`, `env: e1`. It is appended by this pull
request, which makes the log's first live row the row for the mechanism
that writes it — and the smallest possible end-to-end exercise of the
thing.

### What the pre-period will and will not support

This matters more than the row count, and it is the part a later reader
will otherwise have to rediscover:

- **Landing latency, landing rate, per-task spend and routing tier have
  a real pre-period** back to 2026-08-14 — 68 landing dates, 65
  pull-request numbers, 23 costs, 13 routing tiers. An interrupted time series on the first two is
  available now; on spend and tier it is available for the second half
  of the pre-period only.
- **Off-milestone spend share does not.** The `Milestone:` header is
  itself an intervention (task 0061), so the column is `-` for
  everything before it. Its pre-period starts at the first brief that
  carried the header, and it will be short. Say "bet," not "finding."
- **Redirects, questions, question latency and review findings have no
  pre-period at all.** Their series starts with the first live row.
  Every one of them is a measure whose t=0 is this task.
- **`env` is `-` for the entire backfill.** The environment was not
  recorded before this task and inventing it retroactively is exactly
  the guessing the rest of this design forbids.

## Verification

Runs with no human involved, in CI, on every pull request touching the
log, the briefs, the tool or the document:

1. **`tools/outcomes/outcomes check`** over the real committed log: the
   header is schema 1's columns in order, every row has twenty-four
   non-empty cells, every enumerated cell is in its enumeration, dates
   parse and order, `landed` never precedes `queued`, `(task, attempt)`
   is unique, a terminal outcome is one of the three the enumeration
   allows and a `merged` one has a landing date, `findings_fixed`
   never exceeds `findings`, the redirect pair is complete, a non-zero
   verdict has a citation, a probe row does not name a real brief, and
   `note` is within its length and content limits.
2. **The append-only comparison against `origin/main`** — scoped against
   the remote and never a local ref, per `CLAUDE.md`. No row from the
   base is missing, no immutable cell differs, no already-recorded
   pending cell has changed.
3. **The coverage check** — every brief has a row; every non-probe row
   names a real brief.
4. **`test/outcomes/run.sh`**, whose bulk is its negative half: a
   battery of mutations of a synthetic fixture, each asserted to be
   caught by the rule that owns it — a deleted row, a rewritten
   immutable cell, a rewritten pending cell, a bad enumeration, a
   reversed date pair, an unlogged brief, a phantom task, a lone
   redirect count, an uncited verdict, a probe row wearing a real
   brief's name, an address and a home path in a note. A checker whose
   negative cases are untested is a checker that passes everything.

Needs a human, and is not built here:

- **Whether the columns are the right columns.** That is answerable only
  by trying to compute something from them in a few weeks, and the
  honest posture is that schema 1 is a first version with a documented
  bump procedure, not a settled ontology.
- **Filling verdict cells.** By construction no automation may write
  one. The resident's redirects and their later reassessment reach the
  log by hand, or they do not reach it.

## What this does not do

- **It does not report anything.** No dashboard, no summary, no derived
  rates. The log is the instrument; reading it is a later task, and
  deliberately so — a reporting surface built before there is a month of
  data would be designed against imaginary numbers.
- **It does not measure non-task work.** Conversations, sweeps and
  unbriefed fixes are outside it, which bounds off-milestone spend share
  to task spend. `docs/measurement.md` says so where the measure is
  defined.
- **It does not run any probe.** The `probe` column exists so that the
  first seeded-defect probe cannot be added by quietly relabelling real
  rows; designing that probe is entry 1 of
  `docs/backlog/twelve-studies-nobody-has-run.md` and its own task.
- **It does not wire the harness up.** Filling `cost_usd`, `turns` and
  `questions` for a live attempt today means running `derive --fill`
  with the harness journal's path. Having the delivery seat write its
  own rows is the natural successor and belongs with the record shim
  that seat already owes the journal (task 0069).

## Four rules that came out of review, and are not optional

`/code-review` found four ways this could write a confident wrong number
into a cell that is written once and never corrected. The fixes are
small; the reasoning is not, and it belongs here rather than only in the
code.

**Unlanded work is not merged.** Deriving on the branch that is *doing*
the work found no merge carrying its brief and dated the landing to the
commit's own day. `landing()` now tests ancestry first. The failure mode
is the worst shape available: a plausible date, in a write-once cell,
produced by the tool on the exact branch where it is most likely to be
run.

**A missing figure stays missing, and so does an ambiguous one.** A
`usage` event with no cost became `0.00`, which claims the attempt was
free, and several events for one task were collapsed to the last one.
Only an unambiguous single figure is recorded now; `0068` is the task
this costs, and it is named above.

**A number that names two briefs names neither.** The landing lookup
keyed on the four-digit prefix while the log keys on the stem — which is
the whole reason the log keys on the stem. It now falls back for a
number shared by two briefs rather than writing one task's landing into
the other's row.

**An unresolvable `--base` is an error.** It previously skipped the
append-only comparison and reported `ok`, which is a silently absent
guard on the one thing this design exists to guard. `--no-base` remains
for skipping it on purpose.

Each of the four has a test beside it in `test/outcomes/run.sh`.

## Judgment calls made where the brief or the backlog entry was silent

Reported per the dispatch prompt's instruction, because these are the
places a different reading was available:

1. **The brief and the implementation land together.** The dispatch
   prompt asked for a numbered brief; `CLAUDE.md` says a brief is
   committed on the branch that implements it and never separately, and
   `[m2-constraints]` says logging must be *running*, which a brief
   alone does not achieve. Both are satisfied by landing them together,
   which is what happened.
2. **`docs/measurement.md` rather than a section in `docs/state/`.**
   The definitions are mechanism, not current truth, and
   `docs/state/README.md` rule 4 makes adding a document there a
   deliberate act needing a reason. `docs/clarifying-questions.md` is
   the precedent for a mechanism document at the `docs/` root with its
   checker in `tools/`.
3. **Keyed by file stem, not task number.** Two briefs are numbered
   `0003`. Keying by number would have required inventing a
   disambiguator; keying by stem costs nothing and matches how the
   harness names tasks.
4. **A per-row `schema` cell rather than a version in the header.** It
   costs one character per row and makes a row self-describing when
   excerpted or pooled — which is the case the multi-installation
   requirements are written for.
5. **`note` kept, but bounded and linted.** A free-text column in a
   repository whose hard rule is "no personal data" is a hazard. It is
   kept because Mediatron's prior art shows the value of a place to say
   "three dispatch attempts abandoned before this one," and bounded to
   200 printable characters with a lint against an address or a home
   path — the two shapes that have come closest here. It is also the
   one cell excluded from the shareable set by definition rather than
   by filtering.
6. **The backfill was written by tool, not by hand or by model.** Every
   backfilled cell comes from `git` or the harness's own usage ledger.
   No cell was inferred, and the columns that cannot be derived were
   left `-` rather than estimated.
7. **`0064`'s backfilled pull request is the one that queued its brief,
   not the one that did its work** — it has no number-named branch, so
   the fallback derivation applied. It is labelled `backfilled` like
   every other reconstructed row, which is exactly what that label is
   for. Tasks in that era are accurate to the week rather than the day.
8. **No sub-agent was delegated to.** `CLAUDE.md`'s delegation section
   describes the session that talks to the resident handing work down;
   this session was dispatched by the harness with no resident in the
   loop, and the environment it runs in forbids spawning agents. Sizing
   applies anyway: this is deep-tier work by the standard the header
   states.
