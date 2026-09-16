# The resident reviews specs, not code

**What.** The resident's statement of their actual review practice
(2026-09-10), recorded because the approval-automation spec must be
built for the workflow that exists rather than the one convention
assumes. Deep reads happen where the resident has interest or
expertise; otherwise a pull request is read as a check against
priority and vision drift, not for code-level problems. Code-level
correctness relies entirely on the automated review layer — this
system was built bottom-up by agents, and the resident does not
carry the code-level context to be a productive reviewer of it. The
stated direction: front-load the resident's involvement into backlog
entries and task specs, automate aggressively around that gate to
keep its cognitive load low, and let PR approval shed ceremony in
favor of industry-standard merge de-risking — ample testing, staged
rollout, easy rollback. The load-bearing sentence: enough
human-in-the-loop ceremony must exist *somewhere* to keep the system
pointed in the right direction, while maximizing throughput for one
human plus n agents.

**Why it matters.** Three consequences follow, and each reshapes
work already in flight.

- *The spec gate becomes the bottleneck by design*, so it earns the
  automation investment: lint for briefs, agent helpers that reduce
  each spec decision to its genuine residue, rendered reading
  surfaces. Attention moves to the artifact where a wrong decision
  is cheapest to fix and the resident's judgment is genuinely
  irreplaceable — the reasoning the delegation conventions already
  hold ("a brief nobody reviewed is not a brief"), now with the
  resident's explicit weight behind it.
- *A defense relied on completely must watch itself.* On the same
  day this was stated, the review gate was found silently broken (the
  incident is filed with its own detector as
  [[the-review-gate-fails-silently]]): reviews went unposted because
  a parser failure looked exactly like "no findings today," echoing
  the earlier finding that a predecessor handler had never once
  worked and nothing said so. If automated review is
  the sole code-level defense, review-pipeline self-monitoring is
  not hygiene but a precondition: gate-ran-at-all checks,
  disposition-completeness sweeps (already in backlog), and a filled
  sentinel seat — emcee's second-reader deliberately has no default
  model and currently none configured, a concrete open gap.
- *Resident approval retires as a quality signal.* Any measurement
  or authority envelope that planned to read the resident's merge as
  a correctness label should not: by the resident's own account it
  is an interest-weighted drift check, and the external evidence
  agrees that merge outcomes are poor quality labels generally
  (`docs/research/automated-approval.md`, MSR 2026 arXiv:2605.22534:
  of hand-coded agentic-PR rejections only ~36% reflect genuine
  failure, a third are workflow artifacts, a third show no rationale).
  Quality labels come instead from operational outcomes (reverts,
  incident-shaped failures, check regressions — timely, and
  involving no resident attention) and from acceptance verdicts
  ([[passing-tests-are-not-acceptance]]). Because the journals are
  append-only, expert human labeling remains a costable *research*
  option applicable retroactively without slowing velocity — but
  live authority envelopes need timely signals, so they key on
  operational outcomes, never on labels that arrive in batches.
  *This bullet is settled doctrine, not deferred work: on promotion,
  the retirement of resident approval as a quality label and the
  operational-outcome substitute land in `docs/state/`, not vanish
  with the file — the carry-forward the gui-surfaces entry owes its
  own rules.*

**What the drift check becomes.** Explicitly a sample, and
scheduled. A nominally-universal review that is actually a skim is
the same silent decay the completion-vocabulary ban exists to
prevent, one level up — and the backlog already documents how
unscheduled vigilance rots ([[weekly-audit-vigilance]],
[[delegation-atrophy]]). An honest design says: the resident
deep-reads a declared sample of merged work on a cadence, reads
every spec, and reads no code out of obligation.

**How this would have been caught sooner.** Not an incident — a
standing mismatch between convention and practice, surfaced by the
resident describing their actual workflow during the
approval-automation design discussion. The nearest detector the
eventual brief owes: the review-pipeline self-monitoring named
above, since the day this doctrine makes the automated layer
load-bearing is the day its silent failure stops being
recoverable by the resident noticing — the resident, by this
entry, is no longer looking.

**Constraint at promotion time.** Pipeline-changing;
[m2-constraints] applies as usual.

**Open questions.** What spec-lint actually checks — the
prescriptive-formats direction suggests per-kind guidelines with
mechanical checkers, and briefs are a kind. What the sampling rate
and cadence for drift reads should be, and whether the weekly audit
absorbs it. And how [m2-out]'s "merging stays the resident's
throughout" is amended when this doctrine and the approval spec
land — that clause was written for a workflow this entry supersedes,
and the amendment is the resident's to gavel, in state, not here.
