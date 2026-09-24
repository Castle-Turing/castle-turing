# A transferred brief reads as merged work

**What.** `tools/outcomes/outcomes derive --fill`, run on a task branch
before the pull request opens — the step `docs/measurement.md` names and
CLAUDE.md requires — writes `outcome: merged` and a `landed` date into
the row of a task whose work has not landed. Reproduced on task 0081:
the row went from `landed: -  outcome: -` to `landed: 2026-09-23
outcome: merged` while the work was uncommitted in a worktree. Both
cells are write-once.

**Why it happens, exactly.** `landing()` guards this and says so in its
own docstring: "Work that has not reached the trunk has not landed, and
this says so rather than dating the landing to the commit's own day.
Without the ancestry test, running this on the branch that is *doing*
the work marks the work merged." The ancestry test asks whether the
commit that *added the brief* is on the trunk. That was a good proxy
while briefs arrived on the same pull request as their work. It stopped
being one when the transfer convention landed: a brief now reaches
`docs/tasks/` by a commit made directly on `main` and pushed, which is
the dispatch trigger. So every brief is on the trunk from the moment it
is dispatched, the guard's condition is satisfied before any work
exists, and the fallback dates the landing to the transfer.

**Why it matters.** These are the log's write-once cells, and the log's
entire value is that nobody can quietly improve its past. A false
`merged` cannot be corrected — `check` refuses a value becoming another
value, which is the rule that makes the log worth reading. So the
defect does not merely produce a wrong number; it produces a
permanently wrong one, at the exact moment the repository's own
convention tells a session to run the command. Rows 0079, 0080 and
0082 already carry `merged` with dates and pull-request numbers that
do not correspond to their work; whether those came from this path or
another is worth establishing before deciding what, if anything, can
honestly be done about them.

**Observed again on task 0082, and wider than first written.** The
defect does not need the derive to be *for* the row it damages. Run on
0082's branch, `derive --fill` wrote `landed`, `outcome: merged` and a
pull-request number into **0081's** row — the previous task of the same
sprint, still unmerged — because a sprint's tasks share one harness
journal and `--fill` rewrites every pending cell it can reach, not only
the branch's own. So one session running the prescribed step
permanently mis-dates its neighbours. 0082's own row gained nothing: its
write-once cells were already wrong from the transfer, and its cost and
turns are not in the journal until the attempt ends. The step is
therefore a no-op for the row it is meant to mature and harmful to the
rows beside it, which is why 0082 left the log untouched exactly as 0081
did.

**What the fix probably is.** Ask the question the cell actually means.
The work landing is a merge whose branch names the task — which is what
`merges_by_task` already answers — and the brief's own commit says
nothing about it under the current convention. Deleting the fallback
would leave the pre-convention era's rows underived; scoping it to
briefs whose introducing commit is not a transfer commit is the
narrower change, and telling those apart is mechanical (a transfer
commit deletes a backlog file and adds a brief in the same commit).

**How this would have been caught sooner.** A property test: `derive
--fill`, run on a branch with no merge, must not write `outcome:
merged` for the task that branch is for — nor for any other task whose
branch has not merged either, which is the half the first statement of
this missed. That is one fixture repository
and one assertion in `test/outcomes/run.sh`, and it is exactly the
shape of check `docs/state/README.md`'s rule 2 asks for — the guard's
correctness depended on a convention outside the tool, and nothing
noticed when the convention moved.
