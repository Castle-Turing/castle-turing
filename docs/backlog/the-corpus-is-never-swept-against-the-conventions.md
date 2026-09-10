# The corpus is never swept against the conventions

**What.** Conventions bind at the moment of writing and then never
again: nothing re-reads the accumulated corpus — code, comments,
merged history, records — against the rules the project has since
adopted, so debt accumulates invisibly wherever a rule postdates the
artifact or attention lapsed. Two receipts, both named by the
resident (2026-09-10): reasoning-lore spread through code comments
where the conventions say it must not live (the failure class
[[code-comments-accrete-the-reasoning-record]] already files), and
merged pull requests that received no review round at all, through
inattention rather than decision. A first enumeration of the second
class, across the organization's repositories, is running as this
entry is filed; its findings attach as instances when they arrive.

**Why it matters.** The human ceremony for this is the
retrospective, and the resident is rightly dubious of bolting human
workflows onto an agentic one. The razor that resolves it: adopt the
ceremony's *function*, never its *form*. A retrospective batches
three functions because human memory is lossy and gathering is
expensive — reconstruction, lesson-extraction, and norm-gaveling.
Here the record is already complete (journals, git history,
dispositions) and attention is purchasable, so reconstruction is
free, lesson-extraction is a sweep, and only norm-gaveling stays
human — which is exactly where [[the-resident-reviews-specs-not-code]]
already puts the resident's attention. Self-improvement is
self-assembly pointed at a new target: the spec is the delta between
the corpus as it is and the conventions as stated.

**What we already know.**

- The loop needs no new pipeline. A conformance sweep reads reality
  against one checkable convention and files findings; findings
  become backlog entries; entries become briefs; briefs become PRs;
  the incident-ships-its-detector rule then closes the class with a
  standing check so the sweep never finds the same debt twice.
- The aggregation rule is load-bearing: **one entry per convention
  violated, carrying its instance list as receipts — never one entry
  per instance.** A sweep that files two hundred items has relocated
  the inattention problem into the resident's queue.
- The two named debts differ instructively. Unreviewed merges are
  mechanically enumerable (PR metadata against review receipts), and
  the retro-fix is running the review gate against the merged diffs
  — demonstrated the same day this was filed, when a belatedly-run
  review of an already-merged-adjacent PR produced genuine findings.
  Comment lore is a *relocation*, not a deletion: the reasoning is
  valuable and misfiled, so the sweep classifies (constraint the
  code cannot show stays, with its task-number citation; narrative
  moves to the brief or record it belongs to) and the diffs are
  reviewable by sample.
- [[nothing-sweeps-the-pipeline-invariants]] is the runtime sibling
  of this entry: it sweeps what the pipeline's records claim against
  what they must contain; this entry sweeps what the corpus is
  against what the conventions say. The eventual briefs should
  decide whether they share machinery.
- Sweeps cost tokens against uncertain yield, so they start
  scheduled and sampled rather than continuous, and their cost and
  yield land in the task-outcome baseline like any other work.

**The vigilance trap, stated so the spec cannot forget it.** A sweep
fleet that files tidy entries can feel like self-improvement while
the conventions themselves drift. Sweeps check the corpus against
the rules; only the resident's spec gate and audit check the rules
against the vision. The machine half of self-improvement is
buildable; the compass half is the human ceremony this project
deliberately keeps.

**How this would have been caught sooner.** Both receipts were
caught by the resident noticing, which is the pattern every entry in
this family reports. The detector is the sweep itself, on a cadence:
a scheduled pass whose empty result is a receipt ("swept N artifacts
against convention X, zero divergences") rather than silence, per
the rule that a quiet day and a broken detector must not look alike.

**Constraint at promotion time.** Pipeline-changing;
[m2-constraints] applies.

**Open questions.** Who runs the sweep — a standing seat, a phase of
the audit, or a scheduled job — and on what cadence. Whether the
merged-without-review invariant becomes a standing CI check on every
repo rather than a periodic sweep. Which conventions are checkable
enough to sweep today and which need restating first — the sweep
will force conventions to become checkable, which is itself a
benefit worth recording. And the lifecycle question this entry
deliberately does not absorb: where *new* conventions come from and
how measurement joins their lifecycle — that is its own problem,
adjacent but distinct.
