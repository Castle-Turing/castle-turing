# An RCA finding has no dispositions ledger

**What.** A root-cause analysis enumerates findings; nothing binds the
brief that follows to account for every one of them. The worked
example: the 2026-09-06 crash diagnosis observed, in one sentence,
that systemd-oomd was watching zero cgroups for *both* of its kill
rules — the memory-pressure rule and the swap rule. Task 0063 fixed
and verified the pressure rule, and deferred (to
`the-kernel-oom-killer-has-no-swap-headroom.md`) the disk swap
partition — a different, adjacent thing that happens to share the
word "swap". The second finding, the userspace swap rule, was never
assigned to either column. It was not implemented-and-unlit, and it
was not declined; it fell between "fixed" and "deferred" without a
decision, plausibly by name-association with the deferred disk work.
It stayed inert for nine days and was rediscovered only because the
crash recurred on 2026-09-15 (task 0073 now owns it).

**Why it matters.** The project already holds one hard-won rule of
exactly this shape: review findings get dispositions — every finding
fixed with the commit named or declined with the reasoning stated,
because a silently dropped finding is worse than either verdict. That
rule is scoped to reviewer findings on pull requests. RCA findings
have no equivalent, and they are the *more* dangerous case: a dropped
review finding usually costs a defect in one change, while a dropped
diagnosis finding is a defense that never materializes, and its
failure mode is the original incident happening again. This is also a
different gap from `passing-tests-are-not-acceptance.md`, its nearest
sibling: that one is about a *feature* declared complete short of its
finish line; this one is about a *diagnosis* whose findings dissolve
during the reach for completion. And it is adjacent to, not covered
by, `a-crash-goes-uninvestigated.md`: the inquest seat would
mechanize producing findings for crashes and journaling them as
records, but nothing there — or anywhere — makes the set of findings
and the set of dispositions reconcile.

**How it would have been caught sooner.** Two detectors, one per
layer. The instance-level one is mechanical and is what task 0073
lands: a liveness check asserting oomd actually watches cgroups for
both rules — that would have flagged the dropped finding the day 0063
deployed. The class-level one is the ledger itself, applied at
brief-review time: a brief that cites a diagnosis must enumerate the
diagnosis's findings and give each a disposition, and the reviewer of
the brief's diff checks that the ledger balances. Like
`Model-because:`, this cannot be a validator — a harness can confirm
a section exists, not that it accounts for anything, and a required
free-text field with nothing reading it produces ritual compliance.
It is enforced by the brief's writer and the diff's reader, which is
where the review-dispositions rule already lives too.

**Fix directions, none chosen.**

- The spec workflow states the rule: any brief written from an RCA or
  incident diagnosis carries a findings ledger — every finding the
  diagnosis enumerated, each marked fixed (with the change named),
  deferred (with the backlog entry named), or declined (with the
  reason stated). Blank is not an answer, the same non-emptiness rule
  that binds a decision's falsifier and `Model-because:`.
- The inquest seat (`a-crash-goes-uninvestigated.md`), when it
  exists, journals each crash finding as its own record routed like a
  decision — which mechanizes the ledger for crash RCAs specifically,
  since an unrouted record is already a visible defect in that
  plumbing. This entry then covers only diagnoses made outside that
  seat.
- A convention-level note: when a diagnosis finding and a deferred
  work item share a word, the collision is itself a hazard — the 0063
  drop rode on "swap" meaning two things. The naming-collision rule
  already treats one word doing two jobs in a document as a defect;
  extend the habit to the boundary between a brief's fixed and
  deferred columns.

**Open questions.** Whether the ledger belongs in the brief (beside
`Model-because:`, enforced socially) or in the diagnosis document
itself (findings numbered at birth, so a later brief can cite them by
number and an unaccounted number is conspicuous). And whether the
review-dispositions rule and this one should eventually be stated
once, as a single "no finding is silently dropped, whatever produced
it" principle, rather than accreting per-source copies.
