# The current milestone

This is `docs/state/` truth (see this directory's README): what the
project is building now, patched in the same PR that changes it.
Clauses carry bracketed keys; deriving work cites them.
`[stated <date>]` marks the resident's words; `[inferred]` marks the
system's reading, held until the resident confirms or corrects it.

## Milestone 2 — the self-assembling slice

Declared by the resident on 2026-09-06. Milestone 1 — "my cursor is
too small," a deliberately tiny slice chosen to force the plumbing
into existence — was achieved 2026-09-05; its history lives in the
records (task 0008 through task 0013), not here.

### Intent [m2-intent]

[stated 2026-09-06] Redesign castle-modal's UX per the design comp
in `docs/comps/`, delivered *by* the pipeline rather than by hand.
The forcing function is the point: the system must be
self-assembling to meet its goal of adapting automatically to its
resident, and this slice makes the workflow pieces prove themselves
end to end.

### Done looks like [m2-done]

[stated 2026-09-06] The resident opens the modal with the key chord
and states the complaint, pointing at the comp. Clarifying questions
about exactly what to implement come back through the modal. The
milestone lands in this file. The work is decomposed into small,
well-defined task briefs. Clarifying questions route to the resident
automatically. emcee picks the tasks up. Handovers report where the
plan stands. The resident approves PRs and, finally, the deployment
— and then interacts with a visibly better modal that the system
built for itself, a surface a conversational interface can later be
grafted onto.

### Explicitly out [m2-out]

[stated 2026-09-06] Work prioritization: accepted work simply gets
implemented for now (the modal may eventually clarify priority too —
not in this milestone). Any change to PR approval: merging stays the
resident's throughout. [inferred] Unifying the pipeline's handover
with the product-side digest and status surfaces — task 0062 defers
it explicitly.

### Constraints binding this milestone's work [m2-constraints]

- **Baseline before intervention.** Prerequisite: task-level outcome
  logging is running before pipeline-changing work lands — the
  mechanism is `docs/measurement.md`, the log is
  `docs/log/task-outcomes.tsv`, and task 0070 is the reasoning.
  Authority: the resident may knowingly waive this. Fallback: the
  intervention lands anyway and is recorded as an unmeasured bet.
  Consequence of violation: the interrupted time series and the
  study-grade exhaust (the backlog's twelve-studies entry) are forfeit
  for every measure without a pre-period. [inferred from the
  measurement review; direction endorsed by the resident 2026-09-06]
- **Receipts are never verdicts.** Prerequisite: no pipeline surface
  asserts completeness — evidence with citations only, and
  completion vocabulary is a lintable defect in generated reporting.
  Authority: Proposal 06, and the resident's explicit requirement of
  2026-09-06. Fallback: none — a surface that cannot comply does not
  ship. Consequence of violation: the reporting surface becomes the
  confident fiction the false-success evidence documents, and the
  resident's verdicts are made on it. [stated 2026-09-06]

### Position [m2-now] — patched per PR

- Current-state layer: landing with task 0061's PR (this file).
- Operator handover: the generator, the ledger reader and the
  claim-checker land with task 0062's PR, on demand only. [inferred]
  the report's name, its cadence and its channel stay open — that
  brief reserves all three to the resident.
- Clarifying-questions phase: the artifact and the discipline are
  built (task 0065) — the requirements-document form is specified in
  this directory's README, the phase is written out in
  `docs/clarifying-questions.md`, and `tools/clarify/clarify` checks a
  phase run against it with one seeded probe shipped. It works over
  plain files only: not wired to the modal, and no requirements
  document has been produced from a real statement yet. The falsifier
  is unrun — one real intake end to end, whose questions the resident
  either recognises or experiences as an interrogation. "Intake" is
  deliberately no longer the name: it was already the agent layer's
  word for the seat that files a `request` record.
- Decomposition into task briefs: the artifact and the discipline are
  built (task 0079). The seat is named **planner** in
  `docs/architecture.md`, the mechanism is written out in
  `docs/planning.md`, and `tools/plan/plan` checks a decomposition
  against it. What it consumes is a requirements document — the
  clarifying-questions phase's artifact — rather than this file
  directly, which is why the wording here changed: a milestone reaches
  a slate through a requirements document, and naming this file as the
  input would skip the phase that turns a complaint into clauses. What
  it produces is a **slate**, and the resident's approval gates the
  slate as one artifact rather than each brief singly. One worked
  example ships (`tools/plan/oracle/slate.md`, over the clarify
  probe's requirements document). It works over plain files only: not
  wired to the modal, nothing watches for a slate, and no requirements
  document has been decomposed for real yet. The falsifier is unrun —
  one real slate review against the checklist, whose six judgment
  items no checker can carry.
- Acceptance of finished work: the artifact and the discipline are
  built (task 0080). The acceptance run is written out in
  `docs/planning.md` beside the seat that authors the criteria, and
  `tools/accept/accept` runs one brief's criteria against what got
  built and reports the run as a **receipt** — each criterion with its
  command, its exit status and its transcript, never a verdict. A
  criterion now carries the disposition that answers it: `Check:` with a
  command, or `Manual:` with the step a person takes instead, checked at
  spec time by `plan check` so that a criterion nothing can run and
  nobody was asked to take cannot reach an implementer. The frozen rule
  flags any criterion changed on the branch being measured against it,
  and repair cycles stop at a cap that names the measured stopping rule
  it stands in for. One worked example ships
  (`tools/accept/oracle/`, task 0072's criteria read back post-hoc, with
  the receipt of a real run committed beside it). It works over plain
  files only: nothing runs it on a pull request, no brief in
  `docs/tasks/` yet carries the disposition fields, and no second agent
  reads a receipt. The falsifier is unrun — the resident's sampled reads
  of real receipts against their own judgment, which is also the only
  thing that can tell whether the compilation from criterion to check is
  right. [inferred] the second clause of [m2-constraints] binds this
  surface hardest and is met mechanically: the receipt's completion
  vocabulary is a blocking lint and its standing limit is required
  verbatim.
- Question routing to the resident: product plumbing exists (the
  answer chord, task 0022); pipeline wiring not designed.
- emcee dispatch: operating (sprints through task 0060 and PRs
  since). The seat it occupies is named as of task 0069 —
  **delivery**, in `docs/architecture.md` — and the shim translating
  the tenant's own events into `claim`, `result` and `question`
  records is specced as of task 0071: its castle-side contract and
  reconciliation policy, not its code. The tenant's exact hook and
  event schema were not reachable from that task's worktree, so the
  translation itself — and the schema it pins against — is a
  separate implementation task, not yet built.
- Baseline instrumentation ([m2-constraints] first clause): running
  as of task 0070, and fed as of task 0072.
  `docs/log/task-outcomes.tsv` carries one row per
  task attempt, `docs/measurement.md` defines the columns and what may
  honestly be said from them, and `tools/outcomes/outcomes check`
  gates every pull request that touches a brief or the log — a task
  that lands unlogged fails CI. Rows are appended by the session that
  opens the task's pull request, a named step in `docs/measurement.md`
  rather than a wired one — the delivery seat writing its own rows is
  filed at `docs/backlog/the-outcome-row-is-written-by-hand.md`. The
  verdict columns have an invocation path: `outcomes redirect`
  transcribes a resident's redirect against a citation whose author it
  verifies, and `tools/reachability-check.py` fails CI if either step
  loses its named caller. The pre-period is uneven and the brief
  says exactly where: landing dates reach back to 2026-08-14 for all
  68 prior briefs, pull-request numbers for 65 of them, per-task
  spend for 23,
  and the verdict columns (redirects and their miscorrection rate)
  have no pre-period at all — their series starts with the first
  transcribed redirect, which is task 0070's own, logged by task
  0072. [inferred]
  the clause is satisfied for the measures with a pre-period and
  explicitly not for the rest; an intervention landing against one of
  those is a bet, and the document carrying it says so.
