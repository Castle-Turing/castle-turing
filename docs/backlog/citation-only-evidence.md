# Can a decider curate its own audit trail?

*A research question, not deferred implementation. Citations from
memory; **[verify]** marks the unconfirmed.*

**What.** Proposal 04 (`docs/architecture.md`): "an observation persists
only by being cited as evidence in a decision that relied on it," with
the cost stated honestly — "If a rationale was wrong, the raw stream
that would prove it is gone; the error is detectable only as a pattern
of outcomes at the weekly audit."

**The question.** Is an audit restricted to decider-cited evidence
sufficient to catch the errors that matter, or does it structurally
inherit the decider's blind spots — since the evidence available for
review was selected by the party under review? And a second question
riding along: does requiring a seat to write its own rationale at
decision time *improve* the decision, or merely produce fluent
self-justification?

**Where the answer likely lives.** Lerner & Tetlock, "Accounting for the
Effects of Accountability" (1999) — from memory, accountability improves
judgment mainly when the decider expects evaluation by an audience of
*unknown* views, *before* deciding; otherwise it produces conformity or
post-hoc bolstering **[verify details]**. Accident investigation
methodology: the entire rationale for flight data recorders is that
participants' contemporaneous accounts are insufficient. Dekker's *Field
Guide to Understanding Human Error*; Fischhoff (1975) on hindsight.
Financial auditing: substantive testing exists because auditors may not
rely solely on management-cited evidence **[verify against actual audit
standards]**.

On the proposal's side, and genuinely strong: data minimisation (GDPR),
Mayer-Schönberger's *Delete* (2009), and Sellen & Whittaker's "Beyond
Total Capture" (*CACM* 2010), which found lifelogging's total-capture
premise mostly worthless in practice.

**A related finding already in hand.** Bottou et al. (*JMLR* 2013) show
that what makes logged interaction data reusable is not raw observation
but the **considered set and selection propensity**. That is compatible
with citation-only persistence and is being added to the decision
record separately — but it sharpens this brief's question, because it
means the *shape* of what a decider records matters as much as whether
it records at all.

**What would change.** Probably not abandonment — the privacy trade is
well defended — but bounded compromises: a ring-buffer TTL aligned to
the audit cadence (raw stream survives until the next audit, then
dies), mechanical evidence-quality standards (verbatim and timestamped,
which Proposal 04's "concretely, not impressionistically" already
gestures at), or occasional spot-checks against the still-live buffer.
If the literature supports citation-only auditing for low-stakes
domains, the proposal gets promoted with its confidence earned rather
than asserted.

**Priority: medium.** Proposal 04 is implemented and its hardening test
is running in lived use. The cheapest time to adjust the ring buffer's
contract is before sensors exist — and none do yet.
