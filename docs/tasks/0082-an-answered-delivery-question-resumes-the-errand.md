Title: An answered delivery question resumes the errand
Model: deep
Model-because: the deliverable is exactly-once accounting on an
append-only journal — the claim/answer chaining that makes a
resumption cold-checkable, and the crash-window reasoning at the
tenant boundary. A smaller model following the mechanism list would
produce a working watcher whose double-spend and claim-without-invoke
cases are decided by accident; those cases are the task.
Milestone: m2-done
Requires: 0081-implement-the-delivery-record-shim
Requires-because: the answer this mechanism spends closes a
`question` record only the shim's fold puts in the journal; without
it there is nothing to notice.

# An answered delivery question resumes the errand

## Where this came from

The delivery seat's paragraph (task 0069) commits to the worker's
bound for parked questions: one answer producing exactly one
resumption, chained by the `claim` that names it. The mechanism that
would make the bound true does not exist. Task 0023's machinery is
worker-shaped at both ends: its eligibility fold reads `request`
records, and its resumed turn re-invokes the worker's tenant. A
delivery errand is a numbered brief, not a `request` record, so an
answer closing a delivery question is invisible to that fold — and
nothing else watches for it. Today a parked delivery errand resumes
only when the operator relaunches the harness by hand, which loses
exactly what the bound promises: nothing chains the answer to the
resumption it caused, and nothing prevents an answer being spent
twice or never. The shim item owns the outbound direction (tenant
events into records); this item owns the inbound one. This backlog
item is the record, grown in place per the work layout; the transfer
to docs/tasks/ retires it.

## The mechanism

**Dispatch-shaped plumbing, not a reasoning seat.** Eligibility is a
total function of the journal: an `answer` record closing a delivery
seat's `question`, minus answers a resumption `claim` already names
as spent. The guard sentence every plumbing paragraph in the
architecture carries applies here verbatim — no policy about *which*
eligible answer, no say in *whether*; giving it either would make it
a reasoning seat, and that is precisely what this paragraph exists
to stop a later agent from "completing" it into.

**Write-ahead, then invoke.** The `claim` naming the answer is
written before the tenant's resume verb runs — and its `refs` is
non-empty: the answer is a real journal record, so the chaining
promise task 0069 made can finally be kept literally (unlike the
shim's outbound records, whose upstream is a file; that remains
friction 2's open question and is not changed here). The crash
window — claim written, invoke died — is handled at the tenant
boundary: re-invoking resume on a task no longer parked must be a
no-op, and the implementer verifies emcee's resume actually has that
property before relying on it, surfacing a blocker if not. When a
claim exists but the tenant still shows the task parked after a
grace interval, re-invoking is legal and safe for the same reason.

**The answer reaches the tenant verbatim.** No seat paraphrases the
resident, at spend time or ever — the same transcription rule intake
carries.

**Liveness by polling.** The watcher also wakes on an interval
independent of any notification, the shim's rule verbatim: a missed
notice delays the resumption, never corrupts the accounting. Nothing
is ever inferred from a notification's absence.

**The detector rides along.** The invariant sweep (the backlog item
nothing-sweeps-the-pipeline-invariants) gains the rule this item's
own filing promised: a delivery `question` older than N days with no
resumption path is a defect the sweep reports — a silently stranded
park must never again look like a quiet day.

## Verification plan

Automated, as fixtures over a journal: one answer produces exactly
one resumption and its claim cites the answer; a replay of the same
answer produces none; two answers closing two questions produce two;
claim-without-invoke recovers without double-spending; an unanswered
question resumes nothing. The tenant boundary is exercised against
emcee's real resume verb, not a mock of it — the idempotence
property relied on above is demonstrated, not assumed.

End to end, and this mechanism's falsifier: a real parked errand,
answered through `castle answer`, resumes with no human relaunch —
the first time the full loop (park, question, answer, resumption)
executes without an operator's hand. That run's records are
committed as the fixture.

Needs the resident: one answer, given through the real surface, for
the end-to-end run.

## Verification plan, as amended by the implementing PR

**The tenant boundary was exercised against the real verb, and the
property holds.** `emcee resume` was read first and then run: an
unanswered park makes it exit 1 having journaled nothing; an answered
park makes it re-run the errand from scratch with the answer injected;
and a park it has already resolved makes it dispatch nothing, because it
flips its own question file to `Status: resolved` strictly before it
selects the task. That third fact is what closes the crash window
between "claim written" and "invocation died", so the write-ahead
ordering needed it demonstrated rather than assumed, and it is. The
demonstration is `test/delivery-shim/tenant-boundary.sh` — a script, not
a one-off, so it can be re-run when the tenant changes — and the run it
produces is captured in `test/delivery-shim/fixtures/resumed/`. No
blocker was hit and nothing needed surfacing.

That script is deliberately not in CI. It needs the tenant installed and
the stock runner does not have it, and a check that skips wherever it
runs is a check that cannot fail — so the live exercise is invoked by
hand on a host that has the tenant, and `run.sh` reads the capture it
produced. What `run.sh` checks against that capture is not a recording
played back: it asserts what the tenant's own journal says about the
resumption and the re-invocation, and it runs *this repository's* reader
over a question file the tenant itself wrote and resolved, so a drift in
the pinned header spelling fails there rather than silently making an
answer invisible to the tenant.

**Everything this plan asked for automatically is in
`test/delivery-shim/run.sh`,** thirteen new numbered checks under the
existing fifteen, carrying twenty-three assertions, wired into the same
`check.yml` job that already runs the outbound half's. One answer produces exactly
one resumption and its claim's `refs` name the answer; a replay produces
none and invokes nothing; two answers closing two questions produce two,
each invocation scoped to its own run; claim-without-invoke recovers past
a grace interval without writing a second claim, and is left alone inside
it; an unanswered question resumes nothing. Beyond the plan: the answer
reaching the tenant is byte-compared against the record rather than
grepped for a phrase, an answer that did not come through `file_answer`'s
own provenance buys nothing, a park the tenant no longer has refuses
rather than recording an impossible resumption, an errand the operator
already relaunched by hand is recorded as theirs and not resumed a second
time, a second answer to one park refuses rather than overwriting the
first, and the detector is checked in both directions — reporting a
stranded question and staying quiet once a claim exists.

**Every new check has a confirmed falsifier.** Nine mutations were
applied to the shim and each was observed to fail the check that claims
to catch it: dropping the spent-answer subtraction, dropping the intake
filter, never writing the claim, paraphrasing the answer on the way to
the tenant, dropping the run scoping, ignoring the grace interval,
attributing an operator's own relaunch to the shim, letting `stranded`
ignore whether a claim spent the answer, and claiming a park that is
gone instead of refusing.

**One of those mutations found a check that could not fail, and it is
recorded rather than quietly fixed.** The first version of the
two-answers check answered and resumed one run before the second run
existed, so the first answer was already spent by the time a pass over
the second could leak onto it — removing the run scoping outright left
the suite green. Both answers are now filed before either is spent,
which is where the leak is observable, and the mutation fails as it
should.

**The falsifier this brief names is unrun, and it needs the resident.**
The end-to-end loop executed for real — park, question, answer through
`castle answer`, resumption with no relaunch by hand — but the answer was
written by the implementing session standing in for the resident. The
record went through the real `file_answer`, so `provenance: requested`
and `seat: intake` are exactly what that path writes and the mechanism
was exercised exactly as it will be in service; what has not happened is
the resident's own answer, on a real parked errand, which is the step
this brief already reserved to them. `fixtures/README.md` says so where
the capture lives, so nothing reads it as having happened.

**Two things this implementation does that the mechanism list did not
specify, both stated here because they are judgment calls.**

*One invocation per pass, not one per answer.* The tenant's resume verb
is run-scoped: it re-runs every answered park in the run it is pointed
at. So a pass that claimed two answers invokes once and the tenant
resumes both errands. The per-answer accounting is the claim, which is
what the bound is about. Invoking once per answer would race the
tenant's own per-repository sprint lock and report its refusal of the
second invocation as a failure, which is the opposite of true.

*A resumption the operator made by hand gets its receipt.* When the
tenant's question file already says resolved and no claim names the
answer, the operator relaunched the tenant themselves — the only path
before this existed, and still legal. The answer bought its one
resumption and what is missing is the receipt, so a claim is written with
`resumed-by: operator` and nothing is invoked. That is an observation of
the tenant's own durable state rather than a verdict; the alternative is
refusing, on every poll, forever, about something that is not wrong.

**What was left out, and why.** The poll is not wired. `resume` is a
total fold, correct on any trigger and with no second code path for a
timer — but no timer calls it, exactly as none calls `fold`.
`docs/backlog/nothing-polls-the-delivery-shim.md` now carries both
directions rather than one, because it is one wiring act and one
interval decision, and task 0071 reserved that interval to the resident's
own tolerance for a blind window. What changed is that the gap is no
longer silent: the detector this brief asked for
(`castle-delivery-shim stranded`) reports a delivery question that has
had no resumption path for N days, which is precisely the shape an
unwired poll produces. The rule is recorded in
`docs/backlog/nothing-sweeps-the-pipeline-invariants.md` so the eventual
sweep calls this command rather than deriving the same fold again.

**The outcome row was left unfilled, as task 0081's was, and this is
what running the step actually did.** `outcomes derive --env e2 --fill`
on this branch wrote nothing to 0082's own row — its write-once cells
were already wrong from the transfer, and a run's cost and turns are not
in the harness journal until the attempt ends — and it wrote `landed`,
`outcome: merged` and a pull-request number into **0081's** row, the
previous task of this same sprint, which has not merged. A sprint's tasks
share one harness journal and `--fill` rewrites every pending cell it can
reach, not only the branch's own. So the prescribed step is a no-op for
the row it is meant to mature and damages the rows beside it. The log is
left as the transfer wrote it, `check` passes on it, and the observation
is added to `docs/backlog/a-transferred-brief-reads-as-merged-work.md` —
which had already recorded the defect for the deriving task's own row and
not for its neighbours'.
