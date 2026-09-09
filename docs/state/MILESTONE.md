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
  logging is running before pipeline-changing work lands. Authority:
  the resident may knowingly waive this. Fallback: the intervention
  lands anyway and is recorded as an unmeasured bet. Consequence of
  violation: the interrupted time series and the study-grade exhaust
  (the backlog's twelve-studies entry) are forfeit for every measure
  without a pre-period. [inferred from the measurement review;
  direction endorsed by the resident 2026-09-06]
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
- Decomposition of a milestone into task briefs: not designed.
  [inferred] the largest unspecced piece of [m2-done].
- Question routing to the resident: product plumbing exists (the
  answer chord, task 0022); pipeline wiring not designed.
- emcee dispatch: operating (sprints through task 0060 and PRs
  since). The seat it occupies is named as of task 0069 —
  **delivery**, in `docs/architecture.md` — but the records that
  seat owes the journal do not exist yet: the shim translating the
  tenant's own events into `claim`, `result` and `question`
  records is backlog, not built.
- Baseline instrumentation ([m2-constraints] first clause): not
  started. [inferred] must precede the pipeline-changing briefs
  above.
