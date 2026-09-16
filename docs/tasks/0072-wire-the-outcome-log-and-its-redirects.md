Title: Wire the outcome log — rows on every task PR, redirects an agent can log
Model: deep
Milestone: m2-constraints
Model-because: the deliverable is the boundary between what a machine may
write and what only the resident may say, in the one column where getting
it wrong silently corrupts a published measure. The brief hands the
implementer a conflict it has to resolve rather than follow — the
checker's existing pairing rule refuses the very row this task's
acceptance test demands — and resolving it means changing what the log
will hold, in a file whose whole value is that its past cannot be
improved. A standard implementer would take the cheapest exit and default
`redirects_wrong` to 0, which reads as compliance and is exactly the
defect. What rules out cheap and standard is that the wrong answer here
is the plausible one.

# 0072 — Wire the outcome log, and give redirects a hand that isn't the resident's

## Why this exists

Task 0070 built the outcome log, its checker, and a coverage gate that
fails any task PR whose brief has no row. It deliberately did **not**
wire row-writing to anything (`derive` is run by hand) and, by the
receipt/verdict split, left verdict cells to be written "by hand, or
not at all." The resident's review of 0070 (PR #120, redirect recorded
2026-09-14) found the consequence: merging 0070 alone arms the coverage
gate against a pipeline that feeds it nothing, so every subsequent task
PR fails CI, and the verdict columns — `redirects`, `redirects_wrong` —
have no invocation path a resident who will not hand-edit a TSV would
ever use. The measurement would exist and stay empty. 0070 is held open
until this lands.

This is a specimen of the failure
`docs/backlog/passing-tests-are-not-acceptance.md` names: "logging is
running" passed every test and satisfied the implementer's honest
reading, while the resident's reading — rows get written as work
happens, and a redirect is loggable — was unmet. The fix is reachability,
and a detector so the class does not recur.

## What to build

### 1. Row-writing wired into the task-PR flow

A brief and its outcome row land together, without the resident. The
implementer decides the mechanism against what the pipeline already has,
and records the choice in the brief:

- Preferred: the delivery seat runs `outcomes derive` when it opens a
  task's PR, so the row is appended on the branch with the brief. This
  is 0070's own named successor and belongs with the record shim that
  seat already owes the journal (task 0069 / PR #122).
- Acceptable interim: a documented one-command step in the sprint
  runbook that the operator or a session runs per task PR, named
  explicitly so it is a step someone owns, not a thing everyone
  assumes. An interim that will repeat must be filed as debt toward the
  wired version, per the conventions.

The bar: after this lands, a task PR that would fail the coverage gate
cannot reach the resident — the row is present because the flow put it
there, or CI is red on the branch where it is cheap to fix.

### 2. `outcomes redirect` — a verdict logger the agent invokes

A subcommand that matures a task's row verdict cells:

    outcomes redirect <task> --ref <citation> [--wrong <n>]

It counts **distinct cited redirect events**: every invocation requires
`--ref` (a PR comment number, review URL fragment, or journal record
id), and `redirects` is the number of distinct citations recorded for
the task. A `--ref` already recorded is an idempotent replay — exit
zero, change nothing — while a new `--ref` increments the count. The
write-once discipline the checker enforces holds **per citation**, not
on the aggregate: the count moves only because a new citation was
added, never because a cell was edited, so a second redirect maturing
`redirects` from 1 to 2 is not an overwrite and a bare edit of the
number with no citation behind it is.

`redirects_wrong` stays **pending until the resident reassesses** —
never defaulted. The measure this column feeds is defined over
redirects *later judged* wrong
(`the-workflow-interventions-have-no-outcome-measures.md`, methodology
postscript), and writing 0 at redirect time would record the absence
of a judgment as a judgment of correctness, biasing the conditional
miscorrection rate downward — the same silence-reads-as-a-decision
defect this project keeps paying for. It matures pending→value only
when an invocation transcribes an explicit resident reassessment, with
its own `--ref` to where the resident made it, under the same
per-citation rules as `redirects`.

**The integrity rule this brief exists to get right.** The receipt/
verdict split (`docs/measurement.md`, Proposal 06) says no automation
may author a verdict. This command does not author one: it **transcribes**
a verdict the resident stated, and `--ref` is the proof of authorship —
it must point at where the resident actually made the judgment. An agent
running this command is the resident's hand, not a second opinion. The
command must make fabrication detectable, not merely discouraged, and
resolution alone is not detection: a `--ref` pointing at a real comment
the *agent* wrote would pass an existence check while carrying no
resident judgment at all. The resolver therefore verifies two things
mechanically — the ref resolves to a real comment/record, **and** its
author is the configured resident identity (the GitHub login for PR
refs, the journal's author field for record ids). What no resolver can
verify is that the cited text actually states the claimed verdict;
that semantic residue belongs to the weekly audit's sampled reads, and
the command's help text states the boundary so nobody mistakes the
mechanical check for it. An agent may transcribe; it may never
originate. Say all of this in the command's help text, not only here.

### 3. The detector, so this class does not recur

An incident ships its detector (CLAUDE.md). The incident is "functionality
was added with no invocation path, behind an armed gate." The mechanical
half is a lint, run in CI:

- **Orphan entrypoint:** a subcommand of a tool under `tools/` that no
  workflow, hook, runbook, or other script invokes is flagged. `derive`
  and `redirect` must each have a named caller after this task, or the
  lint fails — which is the same task's own first test.
- **Armed gate with no feeder:** a required CI check that gates on an
  artifact no automation or documented step produces is flagged. The
  coverage gate must name what feeds it.

The lint cannot judge whether a feature serves the resident's intent —
that is acceptance, and it lives in
`docs/backlog/passing-tests-are-not-acceptance.md` (acceptance criteria
must assert reachability, not only correctness). State that boundary in
the brief: this lint catches the mechanical shape of the 0070 miss, not
its semantic cause.

### 4. The agent instruction (needs the resident's explicit approval)

The resident will not run `outcomes redirect` themselves, so the agent
must — when the resident redirects an attempt in conversation or on a
PR, the agent recognizes it and logs it, citing where the resident said
it. This is agent behavior and belongs in agent guidance. **Draft the
exact CLAUDE.md (or referenced convention) text in this PR and get the
resident's explicit sign-off at review — a CLAUDE.md change always needs
explicit approval, autonomy grant or not.** The instruction states: the
agent transcribes the resident's redirects and their later reassessment
into the log via `outcomes redirect`, with a citation, and never
invents one; recognizing a redirect is part of closing out any exchange
where the resident sent work back.

## Verification

- The reachability lint fails on the current tree (an orphan `derive`)
  and passes once wiring lands — the detector demonstrably detects.
- A task PR opened through the wired flow carries its row with no human
  step; a PR that removes the row fails CI.
- `outcomes redirect` matures a row; refuses a missing, unresolvable,
  or non-resident-authored `--ref`; replays an already-recorded
  citation as a no-op; increments on a second, distinct citation; and
  refuses any change to a cell that no new citation licenses.
  `outcomes check` passes on the result.
- **Inaugural datum:** the command's first real use logs task 0070's
  redirect — `outcomes redirect 0070-the-task-outcome-log --ref <the PR
  #120 redirect comment>` — maturing that row to `redirects=1` with
  `redirects_wrong` still pending, because no reassessment of that
  redirect has happened and pending is the truthful value. The first
  verdict in the log is the redirect that created this task. That row,
  green under `outcomes check`, is this task's acceptance test.

## Approval and sequencing

0070 (PR #120) stays open until this lands; they merge as a set, 0070
first or together, so the coverage gate is never armed against an
unfed pipeline. The CLAUDE.md instruction (§4) is the one piece that
needs the resident's explicit approval independent of this brief's.

---

# What implementation decided

Everything above is the brief as written. What follows is what the
implementation chose where the brief left the choice open, and the two
places it had to overrule something — recorded here rather than in a
pull-request description, because a hosting service is the one place
these conventions exist to avoid depending on.

## §1: the mechanism chosen, and why it is not the preferred one

**Chosen: a CI workflow, `.github/workflows/outcomes-row.yml`, that
appends the row to the pull request's own branch.** It runs on any pull
request touching `docs/tasks/`, runs `outcomes derive --fill` against
the merge base, and commits and pushes the result to the branch if the
log changed. So the row is present because the flow put it there, and
the resident never sees a task PR failing the coverage gate for the
reason 0070 would have caused.

The brief prefers the delivery seat doing this at PR-open time. That
was not available: the delivery seat is a *name* as of task 0069, given
to a harness that lives in another repository. This repository contains
no code that opens a pull request, so there is nothing here to wire
`derive` into at the moment the PR is opened. Wiring it into emcee
would be a change to emcee, not to this repository, and guessing its
hook contract from memory is how a confident wrong integration gets
written.

What the CI workflow is not: it is not the delivery seat, so the row it
writes is still not a journal record that the weekly audit can read
alongside the seat's `claim` and `result`. That gap is filed as
`docs/backlog/the-outcome-row-is-written-by-ci-not-the-seat.md`, which
also carries the same reasoning for the sprint runbook step in
`docs/log/README.md`. Both are debt toward the same wired version, per
the conventions' rule about an interim that will repeat.

Three properties that make a bot writing rows safe, none of them
accidental:

- **It writes receipts only.** `derive` cannot write a verdict cell;
  the verdict path is `redirect`, which requires a citation the
  resident authored. A bot appending rows is therefore not automation
  grading itself.
- **It cannot damage the past.** The log is held append-only against
  the merge base by `outcomes check`, so the worst a misbehaving
  workflow can do is fail its own gate.
- **It terminates.** Its own push retriggers it, and the second run
  finds every brief already has a row, changes nothing, and pushes
  nothing.

Two configuration facts it needs, and what happens without them.
`OUTCOMES_ENV` is a repository variable naming the environment key for
new rows (`e1` today, per `docs/measurement.md`); `env` is immutable, so
a row written under the wrong key can never be corrected, which is why
the workflow refuses to derive a row rather than guessing. It refuses
*only when a row is actually missing* — a pull request with nothing to
append passes whether or not the variable is set. `REVIEW_BOT_TOKEN` is
optional and does the same job it does for the review-findings handler:
without it, the push happens but starts no checks, so the run says so in
its own log rather than leaving a green tick belonging to the previous
commit.

This pull request writes its own row by hand (`derive --fill` run
locally), so the workflow has nothing to do here and is first exercised
on the next task PR. That is a real gap in this task's own verification
and it is named as one: what is tested here is the command the workflow
runs, in `test/outcomes/run.sh`, not the workflow's YAML.

## §2: the conflict the brief created, and how it was resolved

The brief's acceptance test — task 0070's row green under `outcomes
check` with `redirects=1` and `redirects_wrong` pending — was rejected
by the checker 0070 shipped. That checker enforces a pairing rule:
`redirects` may not be recorded without `redirects_wrong` beside it,
because a detection rate reported without its conditional miscorrection
rate is uninterpretable (`docs/research/measurement-methodology.md`,
design implication 1).

Both rules are right about different moments. The pairing rule is about
*reporting*: a number published alone misleads. The brief's rule is
about *writing*: a 0 written at redirect time is not a measurement of
anything, it is the absence of a judgment wearing a judgment's clothes,
and it biases the conditional miscorrection rate downward in exactly the
direction that flatters the pipeline.

Resolution: **the pairing rule moves to reporting time.** The checker
now accepts `redirects_wrong = -` beside a recorded `redirects` and
reads it as *pending*; `docs/measurement.md` gains the rule that no
report of a detection rate from this log may omit how much of it is
unreassessed. The other direction of the pairing rule is unchanged —
`redirects_wrong` without `redirects` is still refused, because a
numerator with no denominator is meaningless in every direction.

The cell needs no new sentinel. `redirects` recorded with
`redirects_wrong = -` *is* the pending state and says so unambiguously;
`-` in both is "no redirect recorded"; the two cannot be confused.

## §2: how a count becomes unforgeable

`redirects` is defined as the number of distinct cited redirect events,
so the count and the evidence for it are one fact written twice, and the
checker holds them equal. That is what turns "do not fabricate" from a
request into a rule: a bare edit of the digit fails, because the
citations did not change with it.

`verdict_ref` accordingly became a comma-separated, append-only list of
**kinded** citations — `redirect/pr-120-comment-5659322373`,
`reassessed/record-20260914T051123Z-answer-ab12cd`. The kind is in the
cell because one row accumulates both sorts: the redirects, and the
later reassessment of whether they were right. Without it, `redirects`
could not be "the number of citations" once a reassessment added one.

This is a refinement of column 20's grammar under schema 1, not a
version bump, and the reason is checkable rather than argued: every one
of the 70 rows in the log carries `-` in that column, so no existing row
changes shape and nothing is rewritten. Had one carried a bare citation,
this would have been a schema 2.

Per-citation write-once falls out of it. The base revision's citation
list must be a *prefix* of the current one — appended to, never edited,
removed or reordered — and a verdict number may differ from the base
only in a revision that appended a citation of the kind that licenses
it. `redirects` 1 → 2 beside a new `redirect/` citation is a second
redirect; the identical change without one is a rewrite and fails.

## §2: what "the resident authored it" can mean mechanically

The brief says the resolver checks "the configured resident identity
(the GitHub login for PR refs, the journal's author field for record
ids)." Two adjustments, both forced by what exists:

**There is no author field on a journal record.** `agent/castle`'s
record format carries `id`, `type`, `provenance`, `refs`, `seat`,
`created` — and no author. What the journal has instead is stronger than
a field: `write_record` is a single choke point that *refuses* to write
an `answer` or a `correction` from inside any worker turn (task 0021
§2.4(e), task 0023 §5), precisely so a tenant cannot fabricate resident
speech. So a record of one of those two types could not have come from a
seat, and those are the only two types this command accepts as a
citation. That is the journal's mechanical proof of resident authorship,
and it is a property already enforced rather than a new one asserted.

**The GitHub login is private configuration, not repository content.**
Principle 01, and this repository's hard rule about personal data: the
resident's forge login is theirs, and no file here holds it. So identity
is configuration — `--resident`, or `OUTCOMES_RESIDENT` — and with
nothing configured the question is put to the forge instead, where it
can be answered without anyone writing a name down: an account holding
`admin` or `maintain` on the repository is the resident of this
installation for the purpose of authoring a verdict. That is the
review-findings workflow's permission check, one notch stricter, and for
the same reason it exists there: `author_association` says nothing
useful and write access is held by too many things.

The stored citation contains no login either — `pr-120-comment-…` is a
public identifier. So the log stays content-free (`docs/measurement.md`,
pooling requirement 2) and `check` stays a pure function of the working
tree, with no network and nothing to resolve. Verification happens on
the write path only, which is the same place `derive`/`check` already
draws that line.

There is no flag to skip the check. An escape hatch is the hole, and a
missing `gh` is a loud refusal rather than an unverified write.

## §3: what the lint counts as a caller, and why it is strict

Two exclusions carry the weight, and both were chosen by running the
lint against the tree 0070 left rather than reasoned out in advance:

- **A test is not a caller.** 0070 had thorough tests for `derive`. A
  lint that accepted a test would have passed the exact tree that
  produced the incident.
- **A synopsis is not a caller.** `tools/README.md` has listed
  `derive`'s usage the whole time. So a caller is a line someone could
  paste and run, and a line carrying `[--env KEY]` is documentation of
  the interface rather than a use of it. A mention in running prose is
  neither.

The armed-gate half is a `Feeder:` line required in the header comment
of any workflow that runs a tool under `tools/`, naming what produces
what the gate checks, with the named path verified to exist. The escape
hatch is `Feeder: none — <reason>` and it requires the reason, not a
keyword: the same non-emptiness rule that binds `Model-because:`.

The lint's boundary, restated where it will be read: it catches the
mechanical silhouette of the 0070 miss, not its cause. The cause was a
feature that did not do, for the resident, what the resident meant, and
no lint reads intent. That is acceptance, and it is
`docs/backlog/passing-tests-are-not-acceptance.md`'s problem — an entry
the brief cites and which does not exist in this repository. It is filed
in this pull request, from the brief's own words, so the citation
resolves.

## §4: the CLAUDE.md text proposed, awaiting explicit approval

**Not applied.** A CLAUDE.md change needs the resident's explicit
approval, autonomy grant or not, so this is a draft for sign-off at
review. If approved, it is added to `CLAUDE.md` under `## Conventions`,
after the "An incident ships its detector" bullet:

> - **A redirect is logged where it happens.** When the resident sends
>   work back — in conversation, on a pull request, in an answer — the
>   agent that received the redirect records it against the task's row
>   with `tools/outcomes/outcomes redirect <task> --ref <where they said
>   it>`, and commits it with the work. Recognizing a redirect is part
>   of closing out any exchange where work was sent back, not a separate
>   errand to be remembered later. The agent transcribes; it never
>   invents one, and it never writes `--wrong` from its own reading of
>   whether the redirect was right — that number is a second thing the
>   resident has to say, later, and until they say it the cell stays
>   pending. The resident does not run this command; that is the whole
>   reason it exists. (Task 0072.)

Two things that text deliberately does not say. It does not tell the
agent to judge whether something *was* a redirect in a hard case — a
borderline reading logged as a redirect inflates the detection rate, and
the honest move there is to ask. And it does not ask the agent to
backfill redirects from history, because a citation reconstructed after
the fact is the reconstruction's judgment, not the resident's.

## Judgment calls the implementer made that a reader should check

1. **The PR #120 redirect comment asks for `redirects_wrong=0`; this
   PR writes pending instead.** The comment says "A correct redirect,
   not a wrong one", and on its own that reads as an instruction to log
   0. The brief, written afterwards and at length, says the opposite and
   gives the reason: the measure is over redirects *later judged* wrong,
   and a judgment made in the same breath as the redirect is not a later
   one. The brief is the later and more considered instruction and it
   won. If the resident disagrees, the fix is one command —
   `outcomes redirect 0070-the-task-outcome-log --ref <a comment saying
   so> --wrong 0` — and it is a legal, licensed, citation-carrying
   transition, which is the design working rather than a repair.

2. **0070 has already merged.** The brief's sequencing section holds it
   open until this lands; PR #120 merged on 2026-09-16, so the coverage
   gate is armed on `main` right now and this is the branch that feeds
   it. Nothing about what to build changed; the urgency did.

3. **The workflow is unexercised by this pull request.** See §1. The
   command it runs is tested; the YAML is not, and the first real proof
   is the next task PR.

4. **`redirects_wrong` requires a `reassessed/` citation even for 0,
   except when `redirects` is 0.** Reassessing zero redirects is
   arithmetic rather than judgment, so that one case needs no citation.
   Every other value of that cell does, including 0.

## Verification, as run

- `test/outcomes/run.sh` — the 0070 suite, plus the citation rules, the
  pending rule, and `redirect`'s refusals and replays against a
  sandboxed repository with a stubbed `gh` on `PATH`. No network, no
  model, no Nix.
- `test/reachability/run.sh` — the lint against a sandbox containing a
  deliberately orphaned subcommand and an unfed gate, plus a run against
  this repository.
- `tools/outcomes/outcomes check` — green on the real log, including
  0070's matured row and this task's own.
- Not run without human hands: the `outcomes-row.yml` workflow, which
  needs a task pull request and a configured `OUTCOMES_ENV`.
