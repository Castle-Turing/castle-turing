# Will the weekly audit survive being mostly right?

*Originally a research question; the research is done, and its main
moves are now Proposal 06's audit mechanics (`docs/architecture.md`):
blind-then-reveal judgment with the divergence logged, salt at a
controlled rate with a pre-registered floor, mixed sampling with
labeled draws. What remains here is the parameter work the proposal
deliberately does not fix — values, not mechanisms.*

**What remains open.**

1. **Cadence.** "Weekly" is the parameter the evidence attacks, not
   "batched" (outcome bias, episodic memory, and the low-prevalence
   effect all worsen with batch size; batching itself is well
   supported — Akhawe & Felt 2013). A shorter batch also interacts
   with blind-then-reveal's honest limit: the longer the cadence, the
   larger the share of outcomes already lived before judgment, and
   that share is exactly what the divergence column cannot measure.
   Daily or every-other-day likely wins on all three axes at no cost
   to the founding commitment; the vision's "weekly" should be read
   as an opening value.
2. **The salt rate and the detection floor.** Proposal 06 requires
   both declared before the first salted audit runs and never
   retro-fitted; choosing the numbers is audit-surface design work.
   The screening literature (Threat Image Projection) is the place to
   crib starting values from.
3. **An audit cost budget.** The old "under ten minutes" bound was
   demoted from pass criterion to tracked cost — an audit can be fast
   and useless. But tracked is not budgeted: what the ritual may
   spend, and what gets dropped when it overruns, is unresolved.
   Time-on-task fatigue is itself a sensitivity threat, so cost and
   sensitivity have to be designed together, not traded off after the
   fact.

**Where it lands.** These are decided when the audit surface is
specced as a task — the next buildable piece of Proposal 06 — not
before.

**Priority: high.** Unchanged from the original entry: three
documents lean on the audit, and its ritual design is imminent.
