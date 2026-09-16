Title: Wire the outcome log — rows on every task PR, redirects an agent can log
Model: deep
Model-because: the design question — how a verdict reaches the log without a human hand-editing a TSV, while the receipt/verdict split still holds — is judgment about the measurement's integrity, not mechanical wiring; a smaller model would build the command and miss that an agent transcribing a verdict must cite where the resident authored it or the split is broken. Implementation of the wiring and the lint may route down once this brief is settled.
Milestone: m2-constraints
Requires: 0070-the-task-outcome-log
Requires-because: this wires the tool and gate task 0070 built; without 0070's checker, log and CI check there is nothing to wire into, and the redirect command matures a row 0070 defines.

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
