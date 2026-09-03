# The things the system quietly stops doing leave no record

**What.** The journal records **decisions taken**. It has no record type
for a thing considered and *not* surfaced, an action the system decided
against, or a category it has quietly stopped raising. Silence produces
no artifact, so it never enters a digest, never lands in an audit
sample, and never provokes a correction.

**Why it matters.** Four findings from the August 2026 literature
reviews converge on this, and none of them was looking for it:

- **Low prevalence.** Wolfe et al. (*Nature* 2005): rare targets are
  missed at 30–40% versus 7% for common ones. Absent behaviour is the
  hardest error class for a human reviewer to detect, because there is
  nothing to look at.
- **Narrow-then-widen scoping** — the safe direction for interpreting a
  correction, adopted in task 0010 — produces errors of *omission* by
  construction. The recovery path for a too-narrow scope requires the
  resident to notice the system no longer doing something.
- **Stated-preference optimisation narrows monotonically.** Milli et al.
  (*PNAS Nexus* 2025) found that ranking on stated preference fixed the
  harm it targeted and produced a new one: reinforced echo chambers.
  Nobody volunteers a correction asking for friction, or asking to be
  shown the thing they would rather avoid.
- **The correction channel cannot help.** Task 0010 gives the resident a
  way to speak unbidden — but you cannot correct an absence you never
  noticed.

Put together:

> The most likely long-run failure of this system is not the agent doing
> something the resident did not want. It is the agent, correctly and
> with explicit authorisation at every step, gradually ceasing to do
> things — with no decision record generated, nothing appearing in the
> audit sample, and no correction ever volunteered.

A filter bubble built entirely out of consent, and invisible to every
oversight mechanism the architecture currently has.

**The shape of the fix (not yet decided).** Three candidates, and they
are not exclusive:

- **A `suppression` record** — the system emits a record when it decides
  *not* to surface something, so the audit can sample from suppressions
  as well as actions. Cost: potentially far more records than decisions,
  and most of them correctly boring. Interacts with Proposal 06's open
  question about whether the router already writes too many decisions.
- **Sample the complement.** Rather than recording every suppression,
  have the audit periodically ask about a category the system has *not*
  raised recently — derived by comparing current behaviour against an
  earlier window.
- **Monitor for monotone narrowing directly.** Carroll et al. (*ICML*
  2022) propose estimating and penalising induced preference shift. The
  analogue here: track whether stored preferences are drifting toward
  states that make the agent's job easier, and treat that as an alarm
  rather than as learning.

**Note.** Whatever is chosen must not become a surveillance record by
the back door. Proposal 04's rule — observations persist only by being
cited in a decision — should hold for suppressions too, which argues for
the second or third option over the first.

**Related.** [[weekly-audit-vigilance]] (the audit's sensitivity
problem), [[legible-history-calibrated-trust]] (oversight that does not
oversee). Proposal 06's receipt/verdict split assumes the resident can
see what to render a verdict *on*; this is the case where they cannot.

*Full review: see `docs/research/pressure-test.md` (landed after this entry was written).*
