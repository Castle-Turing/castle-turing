Title: Implement the delivery record shim — outbound, per task 0071
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

## Verification plan, as amended by the implementing PR

**Tier 1 was enough: no shape needed provoking, and none is synthetic.**
The inventory of existing run history covered the checklist outright.
Sixty-one journals were read; four were captured whole, and between
them they carry every shape the checklist names — a brief taken, a
pull request opened, a give-up, a park with the question file it names
still beside it, and a park answered by the resident followed by a
second attempt on the same errand in the same journal. The second tier
(provoke the missing shape with a one-task sprint against a disposable
repository) was therefore not reached.

**The third tier was reached once, and this is the downgrade it
requires.** One criterion rests on a synthetic fixture: *an attempt's
facts belong to that attempt, not to the errand* — that a result names
the model and pull request of its own attempt rather than the last one
the errand had. Attribution across attempts is only observable where
one errand is attempted twice inside one run and the facts differ, and
the corpus's single instance of that shape is the 2026-08-20 journal,
which predates `model` being required: both of its results refuse, so a
misattribution between them leaves no trace. The fixture is that real
journal with `model` and `model_source` added to its two
`step_started` records and nothing else changed; it is named
`synthetic-retry/` and says so in `fixtures/README.md`. It should be
replaced by a capture the first time a real run retries a task and
records a model. The property it pins is not cosmetic — it was a defect
in the first implementation of this shim, found in self-review, where
the facts were collected per errand instead of per attempt, and the
mutant is confirmed to fail this check. `test/delivery-shim/fixtures/README.md` is the corpus's own
account of itself, including the one mechanical redaction — the
operator's home directory, login name and private profile repository —
applied to every byte of every file, because this repository takes no
personal data in any file, fixtures included.

Two shapes came free and are worth naming because they are the ones a
hand-written fixture would never have produced. One journal predates
emcee making `model` a required field, so it exercises the refusal that
fires when a result cannot name its implementer; one ran through the
OpenCode adapter, which declares its provider explicitly, so it
exercises the first of the two provider-sourcing rules while the others
exercise the second.

`no-identity/` is the single derived fixture and says so by its name: a
real journal with every `seq` removed, which the shim must refuse.

**What the automated half proves**, in `test/delivery-shim/run.sh`
(eighteen checks, wired into `check.yml`'s `agent-loop-test` job): one
errand folds to its claim and its result, with outcome, tenant, model,
provider and the pull request all read from the tenant's log; a park
folds to a blocking question carrying the tenant's own words verbatim;
a double run appends nothing, on provoked-real logs rather than mocks;
one errand attempted twice produces two records rather than one; a hook
payload that lies about every fact it could lie about produces exactly
the records the log describes, and a run with no payload at all
produces the same ones; provenance on every record is sourced and reads
back to a brief that exists, with the sourcing named on the record; a
journal stripped of event identity refuses the whole pass and writes
nothing. `castle validate` accepts everything written, and `castle
route` routes it — the seat's records are usable by the surface they
exist for, not merely well-formed.

**Where the end-to-end run landed.** `castle-turing/2026-09-22T09-09-47`
is this repository's own sprint on tasks 0076 and 0077, folded against
this repository's own `docs/tasks/`, and committed as a fixture. That
is the "one real sprint task's records folded into the castle journal"
this plan asked for.

**What was left out, and why.** The outcome-log row is implemented as
`castle-delivery-shim row` and has no caller. The row belongs on the
errand's own branch before the pull request opens — both the cheap
moment and the only moment `queued` is still accurate — and a journal
hook fires against the operator's primary checkout, which is on `main`.
Rather than paper that over by maturing rows on the wrong branch, `row`
refuses any checkout that is not on the errand's branch, so the
shortfall is a mechanical failure rather than a sentence in a document.
The remaining half is a caller inside the seat, which is emcee: the
contract gap is recorded in
`docs/backlog/the-outcome-row-is-written-by-hand.md`, whose three open
questions this implementation does answer. The liveness poll is in the
same position and for a related reason
(`docs/backlog/nothing-polls-the-delivery-shim.md`); task 0071 left the
wake interval to the resident's own tolerance for a blind window, and
it still is.

**The outcome row was left unfilled, deliberately.** This plan asks for
outcomes-check green, and it is — but the prescribed step that would
normally precede a pull request, `outcomes derive --env e2 --fill`,
writes `outcome: merged` and a `landed` date into this task's row while
the work is still in a worktree. Both cells are write-once, so
committing that would put a permanently wrong receipt in the log to
satisfy a step. The row appended at transfer stands as it is, `check`
passes on it, and the defect is filed at
`docs/backlog/a-transferred-brief-reads-as-merged-work.md` with the
mechanism reproduced — the fallback's ancestry test asks whether the
*brief's* commit is on the trunk, which the transfer convention made
true from the moment the task was dispatched.
