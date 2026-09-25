Title: A transferred brief is logged as already merged, dated to the PR that filed its backlog entry

# A transferred brief is logged as already merged

`tools/outcomes/outcomes derive` writes `landed`, `outcome` and `pr` for
a brief that has not been implemented, taking them from the pull request
that filed the *backlog entry* the brief was transferred from. Those
three are immutable cells — written once, never corrected — so the log
now holds three confident wrong landings, with a fourth one keystroke
away.

## What is in the log

Three rows, committed at the 2026-09-24 transfer of tasks 0079 to 0082:

    0079-the-planner-seat            landed 2026-09-07  merged  pr 109
    0080-the-acceptance-harness      landed 2026-09-10  merged  pr 123
    0082-an-answered-delivery-...    landed 2026-09-09  merged  pr 114

PR 109 is `docs/delivery-seat-backlog`. PR 123 is
`backlog/acceptance-and-review-doctrine`. PR 114 is
`emcee/0069-the-delivery-seat`. None of them implemented the task whose
row cites them; each is the pull request that filed or discussed the
backlog entry. 0081's row was still honest at transfer (`landed -`) and
`derive --fill` run on a later branch wants to flip it to
`2026-09-23 merged`, which is how this was noticed.

## Why it happens

Two mechanisms, and the second is the one the conventions created.

`task_landing` prefers `merges_by_task` — a merge whose branch name
carries the task number — and falls back to `landing()`, which asks when
the commit that introduced the brief file reached the trunk. That
fallback's own docstring names its weakness: "a brief queued as a prompt
reaches the trunk on whatever pull request queued it, which may not be
the one that did the work." Speccing in place makes that weakness bite
every time rather than occasionally: the brief's file *is* the backlog
item's file, with the backlog item's whole history behind it, so the
commit that introduced it is the commit that filed the item.

Then `landing()`'s trunk test passes for a reason it was not written
for. The transfer commit lands directly on `main` by design — CLAUDE.md
calls it "the one commit class an agent session makes directly on
`main`" — so `rev-list --ancestry-path --merges <transfer>..main` is
empty, which `landing()` reads as "landed straight on the trunk, as this
repository's earliest work did" and dates to the commit's own day. The
ancestry guard that exists precisely to stop a branch doing the work
from marking itself merged does not fire, because the brief really is on
main. Only the *work* is not.

## What it costs

`landed` and `outcome` are what every time series in
`docs/measurement.md` is computed against, and the immutability rule
means these cannot be repaired by the session that notices. A queue of
four tasks reads as three merged ones: lead time comes out at zero or
negative, and the pre-period the `[m2-constraints]` baseline clause
exists to protect is polluted for every measure that groups by landing
date.

It also disarms the coverage gate for exactly the briefs it should be
watching. `outcomes check` passes on a row that exists, and these rows
exist; a task that never lands keeps a row saying it did.

## How it would have been caught sooner

An incident ships its detector (CLAUDE.md). Two candidates, and the
first is mechanical:

**A row may not claim a landing the git history cannot corroborate.**
`check` already refuses `outcome: merged` with no `landed` date. The
missing rule is the converse and is computable from what `derive`
already knows: a row whose `pr` names a pull request whose merged branch
name does not carry that row's task number is asserting a landing from
the weak fallback, and should be refused — or at least demoted to
`pending` — rather than written. The three rows above all fail that test
and the honest ones pass it.

**`derive` must not treat the transfer commit as a landing.** The
transfer commit is identifiable: it lands on `main` directly, it adds a
file under `docs/tasks/`, and it deletes the backlog file in the same
commit. A commit of that shape is a *queueing*, and `landing()` should
return `(None, None)` for it rather than dating the work to it.

Whichever lands, the check belongs in `tools/outcomes/outcomes check` so
that the next transfer fails CI instead of quietly writing the next batch of
wrong rows.

## What this entry does not do

It does not correct the four rows. They are immutable cells and the
correction is a decision about the log's integrity that belongs to the
resident: a `note` column entry on each, an appended attempt row, or a
deliberate rewrite of cells the format says are never rewritten. Naming
the option is not choosing it.

## Where this came from

Found while appending task 0079's outcome row. `outcomes check` passes
on the branch, so nothing failed; running `derive --env e2 --fill` and
reading the diff is what surfaced it, which is the argument for the
detector above — a silent failure looks like a quiet day.
