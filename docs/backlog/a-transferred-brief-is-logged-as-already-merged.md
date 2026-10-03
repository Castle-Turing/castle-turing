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

## Seen again at the next transfer, and `queued` is wrong too

The 2026-10-02 transfer of tasks 0083 to 0085 reproduced this exactly
as predicted, and the "fourth one keystroke away" landed: `derive --env
e1 --fill`, run on 0084's branch, wanted to write

    0083-a-dev-shell-entry-...  queued 2026-10-02  landed 2026-10-02  merged  pr 149
    0084-an-oomd-kill-...       queued 2026-09-15  landed 2026-09-16  merged  pr 128
    0085-an-agent-workload-...  queued 2026-09-06  landed 2026-09-06  merged  pr 103

and to flip 0081's row to `2026-10-02 merged pr 146`. PR 128 is
`backlog/an-oomd-kill-takes-the-whole-desktop`, PR 103 is
`castle/0063-oomd-watches-user-slices`, PR 149 is
`dev-shell-eval-cost`. None implemented the task whose row cites it.
The work for 0084 was, at that moment, uncommitted on a branch.

**A fourth immutable cell is wrong, and this entry had not named it:
`queued`.** `docs/measurement.md` defines it as "the date a file with
this number first appeared under `docs/tasks/`", but `brief_added`
reads it with `git log --diff-filter=A --follow`, and `--follow`
traces the brief straight through the transfer rename into the backlog
file's own first commit. For 0084 that is 2026-09-15 — the day the
*problem was filed*, three weeks before anything was dispatched. A
backlog file has no number, so by the column's own definition it
cannot be what `queued` reads. Any fix to `landing()` leaves this one
standing: `brief_added` has to stop following the rename, or ask for
the first commit that placed the file under `docs/tasks/`.

The consequence is that lead time, computed as `landed - queued`, is
wrong at both ends for every brief the speccing-in-place convention
produces — and the error in `queued` runs in the opposite direction to
the error in `landed`, so the two do not cancel, they compound.

0084's session wrote its row by hand instead (`queued 2026-10-02`,
`landed -`, `outcome -`, `pr -`) and left 0083's and 0085's to the
sessions that own them, so no new wrong cell was committed. That is
not a fix: it depends on a session reading the diff, which is the
thing a detector exists to stop depending on.

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
