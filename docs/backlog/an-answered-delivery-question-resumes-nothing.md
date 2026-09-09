An answered delivery question resumes nothing

The delivery seat's paragraph (task 0069) commits to the worker's
bound for parked questions: one answer producing exactly one
resumption, chained by the `claim` that names it. The mechanism that
would make the bound true does not exist and — until this entry —
was captured nowhere: the amendment deferred it to "the unbuilt
shim", but the shim entry (the backlog entry
"the-delivery-seat-has-no-record-shim") owns only the outbound
direction, tenant events translated into journal records. This entry
owns the inbound one.

What is missing, concretely. Task 0023's machinery is worker-shaped
at both ends: the eligibility fold reads `request` records, and the
resumed turn re-invokes the worker's tenant, writing `seat: worker`.
A delivery errand is a numbered brief, not a `request` record, so an
answer closing a delivery question is invisible to that fold — and
nothing else watches for it. Today a parked delivery errand resumes
only when the operator relaunches the harness by hand, which loses
exactly the property the bound promises: nothing chains the answer
to the resumption it caused, and nothing prevents an answer from
being spent twice or never.

What the mechanism must do, whoever specs it: notice an `answer`
record closing a delivery seat's `question`; invoke the delivery
tenant's own resume path with that answer injected (the tenant-side
half already exists — the harness's park-and-answer machinery);
write the `claim` that names the answer it spent, so one answer
produces exactly one resumption, cold-checkably. It is
dispatch-shaped work (notice an eligible record, run one turn), and
it will land with or beside the record shim, since both sit on the
same tenant boundary — but it is a distinct mechanism from
translation, which is why it has its own entry.

How this would have been caught sooner: a bound stated in
architecture with no mechanism and no capture is invisible to every
check that exists. The detector for this class is an audit rule the
invariant-sweep entry ("nothing-sweeps-the-pipeline-invariants")
should inherit: a `question` record from a seat with no resumption
path older than N days is a defect the sweep reports.
