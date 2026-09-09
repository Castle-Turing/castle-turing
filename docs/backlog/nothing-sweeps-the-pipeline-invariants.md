Nothing sweeps the pipeline's invariants

Filed 2026-09-08, the day two review-pipeline holes were found by the
resident asking a question rather than by anything automated: on this
repository, connector reviews accumulating with no dispositions (the
sibling entry, the-connector-reviews-have-no-dispositioner); on
dovetail and emcee, sprint PRs with no review at all. Both failures
were silent for the same structural reason: every guard in the
pipeline is event-triggered, and this failure class *is* the absence
of events. A workflow that never fires emits no failure. An unplugged
handler looks exactly like "no findings today". Nothing that waits
for an event can detect that the event stopped coming.

How would this have been caught sooner — and the detector this entry
exists to get built:

- **A scheduled sweep asserting invariants over artifact state**, not
  over steps. The suite starts small and broad: an open PR carrying a
  review older than N hours and no dispositions comment is a defect;
  an open PR older than N hours with no review at all is a defect. It
  runs on a schedule (cron workflow, or castle-side tooling reading
  the forge), because absence is only visible to something that runs
  regardless. Violations fail loudly, into a channel someone reads.
- **A salted canary through the whole chain.** A static sweep cannot
  catch the second pathology found the same day in the git history:
  the handler that exists, fires, and dies (a run history of
  cancelled and skipped, none finishing, nothing saying so).
  Periodically, a synthetic marker comment on a designated canary PR,
  with a pre-registered SLA for the dispositions comment appearing
  and a logged pass/fail — Proposal 06's salt discipline applied to
  the pipeline itself. And the salt must include its known-bad half,
  exactly as Proposal 06's does: a healthy pipeline answers every
  ordinary canary before the SLA, so that canary exercises only the
  pass path, and the sweeper's own overdue-predicate and alert path
  could rot in silence behind a wall of passes. At a pre-registered
  rate, a canary is planted that the handler will not answer — one
  constructed to be ignored — and the assertion inverts: the sweeper
  must raise, and the alert must land where the operator reads. A
  canary that can only pass proves only the pass path; the
  known-bad one is how the sweeper proves it can still fail, which
  is the only honest answer to "who watches the watcher".
- **Reporting lands in the handover's threats-and-drift field**
  (task 0062), built precisely so this class of news arrives before
  accomplishments.

A discipline to hold when speccing: checks accrete, and every check
has maintenance cost and its own silent-failure mode. The answer is a
small suite of artifact-state invariants plus one canary — few,
broad, self-proving — never a monitor per step.

This entry is the first filed under the incident-ships-its-detector
convention (CLAUDE.md, adopted 2026-09-08), and the entry that
motivated it.
