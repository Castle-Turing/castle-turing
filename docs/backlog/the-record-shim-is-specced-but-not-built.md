Title: Implement the delivery record shim — outbound, per task 0071
Status: ready
Model: deep
Model-because: task 0071's spec is thorough but names three open
frictions the implementer must navigate at the live boundary — the
per-event identity the fold's idempotence depends on, and provenance
that must be sourced or surfaced as a blocker, never defaulted. An
implementer that cannot argue with the spec where emcee's real schema
disagrees will paper exactly the gaps 0071 says to halt on, and a
papered gap here writes wrong records into an append-only journal.
Milestone: m2-done

# Implement the delivery record shim — outbound, per task 0071

## Where this came from

Task 0071 specced the castle-side contract: a fold that reads the
delivery tenant's own durable log and writes the three owed record
types into the journal. It could not reach the tenant's exact hook
and event schema from its worktree, so the translation itself is this
task. 0071 is the spec, including its own implementation prompt —
this brief points there rather than paraphrasing it, and everything
0071 fixes (hook as doorbell never mail, idempotent total fold,
liveness by polling, the three frictions and their resolutions) binds
here unrestated.

## What this brief adds beyond 0071

- **Pin the tenant's real hook and event schema.** Emcee's
  `--journal-hook CMD` — run on every journal record appended — is
  the doorbell candidate; the schema pinned is its `journal.jsonl`'s,
  read fresh on every wake. The pinned schema is recorded in the
  shim's own documentation with the emcee version it was read from.
- **The outcome-log row rides this shim**, per 0071's own scope
  section ("the outcome-log row is part of this shim, not a later
  errand"). This answers part of the backlog entry
  *the-outcome-row-is-written-by-hand* structurally; that entry's
  three open questions — does the seat write the row or run derive,
  what provenance value a seat-written row carries, and what happens
  when the log's check fails on the branch the seat just wrote — are
  answered in this brief's implementation or surfaced as questions to
  the resident, never left to drift.
- **Blockers surface, never paper.** No stable per-event identity in
  emcee's journal: halt and report, per 0071. Provenance not
  recoverable from what the shim can read: halt and report, per
  0071's friction 3. Either becomes a contract gap to fix in emcee,
  not a value to invent castle-side.

## Verification plan

**The fixture corpus is a deliverable, against a shape checklist.**
One journal excerpt per record-producing shape: brief taken, pull
request opened, given up, parked on a question, resumed second
attempt, and a replayed event. Three tiers, in hard preference order:

1. **Inventory.** Existing run history is checked against the
   checklist first; whatever is already there is captured as-is.
2. **Provoke what is missing.** A shape absent from history is
   produced by running it for real: a one-task sprint against a
   disposable target repository, with a brief written to force the
   shape — a brief instructing the implementer to ask the resident
   before proceeding forces a park; an impossible deliverable forces
   a give-up; answering the park forces the second attempt. Cheap
   tier, budget-capped. The point is that the journal comes out of
   emcee's actual writer, so the fixture encodes the real schema and
   its quirks rather than a guess about them. Captured once,
   committed, re-checked against forever.
3. **Synthetic only with a label and a downgrade.** A shape that
   genuinely cannot be provoked (a crash between write and flush is
   the plausible case) may be hand-written, but the fixture file says
   it is synthetic and this section, as amended in the implementing
   PR, says which criterion now rests on a synthetic shape and why. A
   synthetic fixture passing silently as real coverage is the
   checker-that-cannot-fail defect and is a review-blocking finding.

Automated, against that corpus: one errand folds to its claim and
result; a park folds to a blocking question; a double run appends
nothing — idempotence proven on provoked-real logs, not mocks;
provenance on every record is sourced, with the sourcing named; a
journal deliberately stripped of event identity makes the shim refuse
loudly. End to end: one real sprint task's records folded into the
castle journal, committed as a fixture. Reachability and
outcomes-check green.

Needs the resident: nothing during implementation; the blockers named
above, if hit, come back as questions.
