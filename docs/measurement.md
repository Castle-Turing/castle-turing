# Measuring this pipeline

This document defines what a task outcome is, how it is recorded, and
what may honestly be said about the recording afterwards. The log it
governs is `docs/log/task-outcomes.tsv`; the mechanism that keeps the
log honest is `tools/outcomes/outcomes`. Task 0070 is the reasoning
behind all three.

It is a *mechanism* document, in the same sense as
`docs/clarifying-questions.md`: public, versioned, and inherited by
anyone who deploys this framework. What it deliberately is not is
`docs/state/` truth — nothing here says what is happening now, and the
milestone document keeps that job.

## Why a log exists at all, and why it exists before the work it measures

Milestone two changes how this pipeline works, one intervention at a
time. Every credible causal design for a change like that borrows
strength from many units adopting at different times, and this project
has one resident and one installation. The one single-unit design that
transfers is an **interrupted time series** — model the pre-existing
trend, then test whether the intervention changed its level or its slope
— and it is worthless without a pre-intervention period.
`docs/research/measurement-methodology.md` states that as design
implication 9: start logging task-level outcomes immediately and hold
the workflow steady long enough for a trend to exist. Applying an
interrupted time series to an agentic workflow appears, on that report's
search, to be unprecedented; the pre-period is the whole price of
finding out.

`docs/state/MILESTONE.md`'s `[m2-constraints]` carries the consequence
of skipping it: every measure without a pre-period is forfeit, and the
resident may knowingly waive the constraint, in which case the
intervention lands as an unmeasured bet and is recorded as one.

The literature also says why the log must be boring and mechanical
rather than a discipline anyone remembers to follow. Unmeasured process
discipline decays into ritual; a solo operator's impression of whether a
change helped is not evidence — developers in METR's randomized trial
believed AI had made them 20% faster while measurement showed them 19%
slower, a 39-point gap between perception and fact.

## What a row is

One row per **task attempt**: one task from `docs/tasks/`, one run at
implementing it. A task that is attempted twice has two rows. A row is
appended when the attempt starts, and its remaining cells are filled in
as they become knowable — the pull request opens, the review lands, the
resident says something about the result.

The file is tab-separated because tabs never appear inside a cell here
and because a cell is never quoted, so `cut`, `awk`, `grep` and a
three-line reader all work on it forever. `-` means *not recorded*; an
empty cell is a defect. Nothing distinguishes "zero" from "unknown"
except writing `0` for the first and `-` for the second, and the
checker will not accept a blank.

### The columns, schema 1

Every row's first cell is its schema version, so a row stays readable
when excerpted, pooled, or read by something written after the schema
moved on. Adding or renaming a column is a version bump: the new
definition is added to this document, both versions are taught to the
checker, and no existing row is ever rewritten into the new shape.

| # | Column | Kind | Meaning |
|---|--------|------|---------|
| 1 | `schema` | — | `1` for every row defined here. |
| 2 | `task` | key | The brief's file stem, e.g. `0069-the-delivery-seat`. The stem rather than the number, because this repository's history contains two briefs numbered `0003`. A brief renamed after its row was written still resolves, by number, where that number names one brief — the cell is immutable and the row cannot be deleted, so the alternative is a log that deadlocks on a rename. |
| 3 | `attempt` | key | 1-based. A second attempt at the same task is a second row, never an edit to the first. |
| 4 | `queued` | receipt | The date (UTC, `YYYY-MM-DD`) a file with this number first appeared under `docs/tasks/`. |
| 5 | `landed` | receipt | The date the attempt's work merged to the trunk. Work that has not reached the trunk has not landed, whatever branch it sits on. |
| 6 | `outcome` | receipt | `merged`, `abandoned` or `superseded` once the attempt is terminal; `-` until then. Delivery only — see the receipt/verdict split below. |
| 7 | `tier` | receipt | The brief's `Model:` header: `deep`, `standard`, `cheap`, or `human`. The routing *decision*. |
| 8 | `model` | receipt | The model that actually ran, as the harness recorded it. The routing *outcome*. |
| 9 | `milestone` | receipt | The brief's `Milestone:` header as a bare clause key, or `none-hygiene`. Never inferred: a brief with no header is `-`. |
| 10 | `pr` | receipt | The pull-request number, bare. |
| 11 | `cost_usd` | receipt | What *this attempt* spent, to the cent, from the harness's own usage ledger. Left `-` where the ledger cannot say — a task attempted more than once, or an event carrying no figure. A recorded `0.00` claims the attempt was free. |
| 12 | `turns` | receipt | Model turns in the attempt, from the same ledger. |
| 13 | `questions` | receipt | Clarifying questions this attempt routed to the resident. |
| 14 | `question_wait_h` | receipt | Hours the attempt was blocked waiting for those answers, to one decimal, summed. |
| 15 | `redirects` | **verdict** | Times the resident redirected this attempt after seeing its work. |
| 16 | `redirects_wrong` | **verdict** | How many of those redirects were later judged to have been wrong. |
| 17 | `reworks` | receipt | The task number(s) whose merged work this attempt amends, comma-separated. |
| 18 | `findings` | receipt | Findings raised by the cross-model review gate on this attempt's pull request. |
| 19 | `findings_fixed` | receipt | How many of those were dispositioned as fixed rather than declined. |
| 20 | `verdict_ref` | — | Where the resident said the thing a verdict column records: a pull-request comment number, a review URL fragment, or a journal record id. |
| 21 | `probe` | — | `-` for a real record; otherwise the probe's identifier. |
| 22 | `env` | — | The environment key (see below). |
| 23 | `provenance` | — | `live` if the row was written as the attempt happened, `backfilled` if it was reconstructed from history. |
| 24 | `note` | — | Up to 200 printable characters naming public artifacts. The one cell that may be rewritten, because it is the only one that could ever need redacting. |

### The receipt/verdict split, and why two columns carry it

`docs/architecture.md`'s Proposal 06 divides outcomes into two kinds
with unequal authority. A **receipt** is the observable reception of
work — merged, reverted, dismissed — and receipts may inform. A
**verdict** is a resident-authored judgment, and only verdicts settle.
The system may grade how well it delivered; it may never grade whether
it was right.

Columns 15 and 16 are the only verdicts in schema 1, and the checker
enforces two rules about them. A non-zero verdict must carry a
`verdict_ref`, so that a judgment in the log always points at the place
the resident actually made it. And `redirects` may not be recorded
without `redirects_wrong` beside it: a redirect count is a *detection*
rate, and measured conditional miscorrection rates run 53–94%, so a
detection rate reported alone is uninterpretable
(`docs/research/measurement-methodology.md`, design implication 1). The
log will not hold half of that pair.

Everything else is a receipt, derivable from artifact state by something
with no model in it. That is deliberate and it is the same rule task
0062 put above every other for the operator handover: claims come from
artifact state, never from an agent's account of its own work.
Self-asserted completion is false in 45–76% of measured cases and no
model reliably detects it.

### Environments

Measured infrastructure noise on agentic evaluations reaches six
percentage points — larger than many effects worth detecting — so the
environment is a variable, not a footnote. `env` holds a short key
defined here:

- **`e1`** — the development laptop (`hosts/xps9370`, 16 GB, NixOS),
  work dispatched by emcee, model per row.

A new environment gets a new key and a line here, in the pull request
that first uses it. The key is a key and not a description on purpose:
it is content-free, so a measure carrying it can be shared without
carrying anything about the household it came from.

## How a row is written

Rows are appended and matured, never rewritten. Three cell classes:

- **Immutable** (`schema`, `task`, `attempt`, `queued`, `tier`, `model`,
  `milestone`, `probe`, `env`, `provenance`): fixed when the row is
  written. A change to one is a rewrite of history.
- **Pending** (`landed`, `outcome`, `pr`, `cost_usd`, `turns`,
  `questions`, `question_wait_h`, `redirects`, `redirects_wrong`,
  `reworks`, `findings`, `findings_fixed`, `verdict_ref`): `-` may
  become a value exactly once. A value never becomes a different value.
- **Amendable** (`note`): may be rewritten, because a note is the only
  cell that could ever need redacting.

The enumeration for `outcome` has no in-flight value for the same
reason. An `open` that later became `merged` would be a pending cell
written twice, so an attempt in flight leaves the cell `-` — and a `-`
against a task that plainly landed is a visible defect rather than a
silent one.

`tools/outcomes/outcomes check` holds every change to the log against
the trunk — the merge base with `origin/main`, which is what `git diff
origin/main...HEAD` means and what CI passes — and fails on any
transition outside those rules, including the deletion of a row. This is the point of the whole design: the value
of a pre-period is entirely in nobody being able to quietly improve it
later, and premature deletion is the measured dominant failure of
machine-maintained state (`docs/state/README.md`, rule 2).

The same check enforces **coverage**: every brief under `docs/tasks/` or
`docs/tasks/done/` has a row. That is the detector. A task that lands
without being logged fails the very next pull request — which is the
only moment when writing the row is still cheap and the facts are still
in someone's head.

## Salt

A probe row — a synthetic task planted to measure whether some part of
the pipeline catches something — carries its identifier in `probe` and
may not name a real brief. Proposal 06's discipline applies unchanged:
salt never masquerades as a real record, its rate and its detection
floor are pre-registered before the first probe runs, and a floor chosen
after seeing a detection rate is not a floor. No probe is defined at
schema 1; the column exists so that the first one cannot be added by
quietly relabelling real rows.

## What may honestly be said from this log

**Bets, not findings, below about twenty points.** At this project's
task volume the honest power ceiling is roughly a twenty-percentage-
point effect in a binary outcome — 40%→60% needs about 94 tasks per
arm, 50%→60% about 384. Intervention decisions smaller than that are
bets under acknowledged uncertainty, and the documents that carry them
say so in those words.

**Two measures have no literature at all.** Off-milestone spend share
(computed from `milestone` and `cost_usd`) and question-routing latency
(`questions`, `question_wait_h`) are, on the measurement review's
search, unvalidated against outcomes anywhere. They are reported as
*instrumented observations* and never as quality measures, and any
document citing them repeats that sentence. The cost of forgetting is
the Goodhart failure that this literature has already measured
elsewhere: procedural compliance falling to 30–35% while success rate
reads 97%.

**Never a single run.** Agentic pass rates swing several points run to
run at temperature zero. A row is one observation, and one row is never
an argument.

**The baseline is already contaminated.** The pre-period is not an
agent-free period — every task in it was done with agents. Any effect
measured here is an increment on top of existing assistance, which is
the regime where the one large study of this question found gains
smallest.

**Off-milestone share has a task-shaped denominator.** It is computed
over *tasks*, so work that never became a numbered brief — a
conversation, a sweep, an unbriefed fix — is outside it entirely. It is
the share of *task* spend that served no milestone clause, and calling
it anything broader would be false.

## Pooling across installations, if that day comes

`docs/backlog/measurement-is-designed-for-one-resident.md` states four
requirements for keeping a multi-installation future open, and schema 1
meets them by construction rather than by later export:

1. **The definitions are public and versioned** — this document, and the
   `schema` cell on every row.
2. **The shareable measures are content-free** — columns 1 through 23
   are counts, dates, keys and enumerations. Nothing in them holds
   text. Column 24, `note`, is the single exception and is therefore
   *outside* the shareable set by definition, not by filtering.
3. **Infrastructure facts are first-class** — the `env` column, on every
   row, from the first row.
4. **The analysis plan assumes clustering** — any pooled analysis uses
   per-installation clustered standard errors. Written down here before
   the first shared byte, per the same pre-registration discipline
   Proposal 06 applies to salt.

Sharing itself is opt-in, off by default, and a resident-consent act.
Nothing in this repository sends anything anywhere.

## What this log deliberately does not measure

- **Whether the work was any good.** That is a verdict, and it lives
  where the resident put it — a review, an answer, a rollback. The log
  points at those with `verdict_ref`; it does not summarise them.
- **Trace quality.** Scoring a trajectory span by span is the right way
  to do it and it is a different instrument with a different cost.
  Trajectory *length* is deliberately absent: it is a confound for task
  difficulty that reverses sign once difficulty is controlled.
- **Anything about the resident.** No priorities, no calendar, no
  correspondents, no words of theirs beyond a reference to where they
  are already recorded. The `note` lint rejects the two shapes that
  have come closest in this repository's history — an address and a
  home path — which is a floor under reading the diff, not a substitute
  for it.
