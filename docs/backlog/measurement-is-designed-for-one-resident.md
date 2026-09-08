# Measurement is designed for one resident, and the n>1 door must stay open

**What.** Stated as direction by the resident, 2026-09-06, reading
the measurement review: design measurement for n=1 now — the ITS
baseline, paired comparisons, bets-stated-as-bets discipline of
`the-workflow-interventions-have-no-outcome-measures.md` stands
unchanged — but keep open the n>1 future where other residents run
this system and opt in to sharing measurements, so the agents improve
from a fleet's evidence rather than one household's. The hope is
explicit: other people use this system.

**Why the door is worth designing for now.** The measurement review's
sharpest structural finding is that every credible causal design in
this space borrows strength from many units adopting at different
times — staggered difference-in-differences is the one design that
worked at scale, and a single installation cannot run it. n>1 also
unlocks the studies a single resident cannot answer (clarification
budget tolerance; developer-level randomization, which is where METR
retreated to after abandoning task-level RCTs). A fleet does not just
add power; it changes which questions are answerable at all.

**What keeping the door open costs today — four requirements, all
cheap now and expensive to retrofit.**

1. **Metric definitions live in the public mechanism, versioned.** If
   each installation improvises its own task-outcome definitions,
   pooling is impossible by construction. The definitions (what
   counts as a task outcome, a redirect, a question, a probe catch)
   ship with the framework the way the journal schema does, so every
   installation measures identically without coordinating.
2. **Shareable measures are content-free by construction.** Counts,
   rates, latencies, spend, catch rates — never text, never clause
   content, never anything from the journal's substance. The
   private/public split decides what a measure may *contain* at
   definition time, not at export time; a measure designed
   content-free cannot leak what it never held.
3. **Infrastructure facts are first-class variables.** Measured
   infrastructure noise on agentic evals reaches 6 percentage
   points — larger than many treatment effects — so pooled data
   without per-installation hardware and configuration facts is
   uninterpretable. Record host class, memory, and relevant config
   beside every measure from day one.
4. **The analysis plan assumes clustering.** Per-installation
   clustered standard errors are the stated future analysis, which
   costs nothing now except writing it down before the first shared
   byte, per the same pre-registration discipline Proposal 06 applies
   to salt.

**The sharing itself is a resident-consent feature, not a telemetry
default.** Opt-in only, off by default, and legible in Proposal 05's
sense: the resident sees the exact payload a share would send before
any share happens, consent is a verdict-level act, and revocation is
as easy as the grant. An open-by-construction system that phones home
by default would betray the principle that makes it worth trusting;
the design here must be the opposite pole — sharing as a deliberate,
inspectable gift.

**Open questions.** Where the metric schema lives once `docs/state/`
exists (task 0061's accommodation step is the natural mechanism);
whether shared measures flow to a place at all before more than one
installation exists (probably not — the schema is the deliverable,
the plumbing can wait); and how probe records (seeded defects,
salted audits) pool across installations without the pooling itself
revealing which records were salt — pre-registration per
installation, labeled in each journal, is the current answer carried
from Proposal 06.
