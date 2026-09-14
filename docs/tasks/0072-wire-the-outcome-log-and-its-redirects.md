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

It sets `redirects` (incrementing, pending→value per 0070's rules),
requires `--ref` (a PR comment number, review URL fragment, or journal
record id), and writes `redirects_wrong` beside it (default 0, since a
redirect is presumed correct until reassessed). It refuses to write a
verdict without a citation, and refuses to overwrite a recorded value
with a different one — the same write-once discipline the checker
enforces.

**The integrity rule this brief exists to get right.** The receipt/
verdict split (`docs/measurement.md`, Proposal 06) says no automation
may author a verdict. This command does not author one: it **transcribes**
a verdict the resident stated, and `--ref` is the proof of authorship —
it must point at where the resident actually made the judgment. An agent
running this command is the resident's hand, not a second opinion. The
command must make fabrication detectable, not merely discouraged: a
`--ref` that resolves to nothing is a defect a check can catch, and the
brief states how (does the ref resolve to a real comment/record?). An
agent may transcribe; it may never originate. Say this in the command's
help text, not only here.

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
- `outcomes redirect` matures a row, refuses a missing/​unresolvable
  `--ref`, and refuses to rewrite a recorded verdict. `outcomes check`
  passes on the result.
- **Inaugural datum:** the command's first real use logs task 0070's
  redirect — `outcomes redirect 0070-the-task-outcome-log --ref <the PR
  #120 redirect comment>` — maturing that row to `redirects=1,
  redirects_wrong=0`. The first verdict in the log is the redirect that
  created this task. That row, green under `outcomes check`, is this
  task's acceptance test.

## Approval and sequencing

0070 (PR #120) stays open until this lands; they merge as a set, 0070
first or together, so the coverage gate is never armed against an
unfed pipeline. The CLAUDE.md instruction (§4) is the one piece that
needs the resident's explicit approval independent of this brief's.
