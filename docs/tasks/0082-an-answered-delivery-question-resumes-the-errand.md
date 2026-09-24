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
