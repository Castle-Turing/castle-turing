Title: Task 0062 — the operator handover, a generated where-we-are report
Model: deep
Requires: 0061
Milestone: m2-done
Model-because: the deliverable is resident-facing text whose measured failure mode is calibrated-looking fiction — agent self-reports of completion are false 45–76% of the time and fluent summaries raise reader confidence without raising accuracy. The implementer's central job is *refusing* to write fluent prose where the ledger does not support it, and deriving every claim from artifact state instead. A standard-tier implementer would produce exactly the plausible summary this task exists to prevent, and no test distinguishes plausible from grounded until the generator's claim-checker exists — which is itself part of this task.
Requires-because: every handover restates the milestone and reports the delta against it; without `docs/state/MILESTONE.md` there is no intent to report against, only activity.

# Task 0062 — the operator handover, a generated where-we-are report

**Status: approved by the resident 2026-09-06 (read via
dovetail-show); queued — implementation follows task 0061's merge,
which this file's Requires: header exists to enforce.**

**Before starting:** read `CLAUDE.md` and
`.claude/skills/implement-brief/SKILL.md`. Then
`docs/research/operator-handover.md` (landed with task 0061 — the
evidence base; its design implications 1–10 are the requirements list
this brief instantiates), `docs/architecture.md` Proposal 06 (the
receipt/verdict split, which binds this surface), and
`docs/backlog/legible-history-calibrated-trust.md` (why fluent
reasoning is an anchoring device and cited evidence is the
load-bearing half). Emcee's `docs/research/agentic-pr-review.md`
(2026-09-02) is the companion for where review attention goes.

## Naming, first, because it is load-bearing

The word "brief" is taken — it means a task spec in this repo, and a
word doing two jobs in one project is a defect. This document uses
**handover** for the generated resident-facing report, reserving
**handoff** for agent-to-agent state passing (the distinction the two
research reports encode in their titles). The resident may rename;
whatever wins, the collision with "brief" must not.

## What this builds

A generator — `tools/handover.sh` driving an agent turn, in the shape
of the existing tool conventions — that reads the ledgers this repo
already accumulates (git and PR history via `gh`, `docs/tasks/` and
`done/`, the backlog, the journal, review dispositions) plus
`docs/state/MILESTONE.md`, and emits a short markdown handover. On
demand first; cadence is a resident decision later. Public mechanism,
private nothing: the generator reads only this repo and its own
hosting forge — Principle 01 holds with no private-layer slot needed.

## The field list — fixed, small, ordered, and why each field earns
its place

1. **Intent, restated.** The milestone and its done-criteria, from
   `MILESTONE.md`, in two or three sentences — never assumed held in
   the reader's head. Trained humans acting on remembered intent
   matched it 34% of the time (Shattuck); the delta against restated
   intent is the report's spine.
2. **Threats and drift, before accomplishments.** What could go wrong
   next, what is drifting from the milestone, and spend that served no
   milestone clause — the projection level that 92.6% of status
   displays and 88.5% of real handovers omit, and the aviation
   redesign deliberately put first so the report cannot be a victory
   monologue.
3. **What changed — evidence only, never completeness.** One line per
   merged or moved piece of work, and each line enumerates receipts
   with citations: "PR #101 merged, checks green, findings
   dispositioned [links]" — computed from artifact state (merge
   status, checks, review dispositions, state-doc diffs), never from
   any agent's account of its own work, since self-asserted
   completion is false 45–76% of measured cases and LLM judges cannot
   detect it (AUROC ≤ 0.65). **The resident's requirement, stated
   2026-09-06 and stronger than the evidence-derivation rule alone:
   the handover makes no completeness claims at all.** Even a derived
   "task 0059 is complete" asserts more than its evidence grounds —
   27–78% of benchmark-verified successes conceal procedural
   violations — and in Proposal 06's grammar completeness is a
   verdict, which only the resident renders. Enforced mechanically,
   not stylistically: the claim-checker rejects
   completion-assertion vocabulary ("done," "complete," "finished,"
   "successfully") in generated lines outside quoted resident
   verdicts. This is a blockable lint, not a warn — the generator
   controls its own output, so a violation is a generator bug, and
   the rule exists precisely because the confident-closure register
   is a trained stylistic default (false success has a TF-IDF
   signature at 0.83–0.95 AUROC that LLM judges talk themselves out
   of) that no instruction reliably suppresses. Each line's citation
   makes it cheaper to check than to re-derive — verification cost,
   not exhortation, is what moves whether a reader checks anything.
4. **Unverified, marked in place.** Anything the generator could not
   ground in an artifact appears with an explicit `[unverified]`
   marker rather than being omitted or smoothed over. The documented
   failure of agent self-reporting is uniform positivity; the
   resident's defence is knowing which lines were checked.
5. **Verdicts requested.** The short list of decisions only the
   resident can make, cheapest first, each with its evidence attached.
   This is Proposal 06's grammar applied to the pipeline: the system
   may report its receipts; it may never grade its own judgment.
   "Merged, checks green, findings dispositioned" is a receipt.
   "This was the right work" is a verdict, and this section is where
   the report *asks* for verdicts instead of implying them. The
   question-budget evidence binds this field too: a trained clarifier
   beat stock models while asking 1.2 questions to their 2.6, and
   the measured failure is over-asking and under-targeting at once
   (`docs/research/elicitation-papers.md`) — so a verdict request
   must name what changes depending on the answer, and a request
   nothing depends on is a defect the golden test should catch. Any
   ambiguity tags carried in the state layer (task 0061's
   stated-versus-inferred convention) surface here rather than
   silently expiring.
6. **The reader's closing act.** The handover ends by asking for a
   written-back acknowledgment — verdicts given, or an explicit
   "nothing needed" — mirroring I-PASS's synthesis-by-receiver, so the
   format cannot be satisfied by generation alone. Unacknowledged
   handovers are visible in the next handover. The machine-checkable
   half of read-back is a faithfulness-and-coverage pair (the
   Inter2US construct): every claim in the handover traceable to a
   ledger artifact — the claim-checker below — and every substantive
   ledger event since the last handover reflected in some line, so
   omission is as detectable as fabrication. The human-confirmed half
   has never been evaluated anywhere; the elicitation review marks it
   as territory this project enters first, which is one more reason
   the golden test measures the reader's catch rate rather than
   assuming the ritual works.

A handover is one screenful. Comprehensiveness is an anti-goal with
evidence: more visible detail reliably raises reader confidence and
speed and does not reliably raise error-detection — in the largest
study it lowered it. When the generator has more to say than fits,
it links; it does not append.

## What this changes about pull-request reading

Stated because it is the resident's live problem: PR review is today
the only verdict channel, so it is carrying two jobs — "was this done
correctly?" (quality) and "was this the right work?" (direction) —
and uniform skimming serves neither: vigilance research shows miss
rates climbing toward 40% as real defects get rarer, at full
attention cost. The division this task assumes: quality verdicts
migrate to the measured gate ladder emcee's
`docs/research/agentic-pr-review.md` already specs (disposition
capture, seeded-bug benchmark, staged auto-merge with a randomized
holdout) — that plan is emcee's to implement and is not widened here.
Direction verdicts move to this surface, where field 5 makes them
cheap and explicit. What remains of PR reading is deliberate deep
review, routed, not skimmed: state-document diffs always; a uniform
random draw of the rest, sized to the resident's real bandwidth —
mixed sampling exactly as Proposal 06 prescribes for the audit, so
the sample's bias is measured rather than invisible. The sampling
parameters are audit-surface design work and are *not* fixed by this
brief; they land with the audit task the weekly-audit backlog entry
already reserves them for.

## What this task does not do

No scheduled delivery, no notification channel, no castle-modal
integration — the product-side digest (task 0009) and status surfaces
are different audiences, and unifying them is a later decision once
both exist. No salting of the handover with planted errors yet: the
evidence says measure the reader's catch rate, and Proposal 06's salt
discipline (pre-registered floor, labeled in the journal) is exactly
the mechanism — but it belongs to the audit-surface task, and this
brief only requires that the generator's output format not preclude
it. No trust dashboard, no metrics rollup: SPACE's one rule is that
no single metric may stand alone, and the ledger citations *are* the
drill-down.

## Implementation plan and verification

Branch `castle/0062-operator-handover`. The generator, a fixture, and
a claim-checker. The claim-checker is the heart of verification and
runs with no human: for every citation-bearing line in a generated
handover, it resolves the citation (PR, commit, journal id) and
confirms the artifact exists and its state matches the claim — a
merged-PR line whose PR is open, a green-checks line whose checks
failed, a cited journal id that does not resolve, all fail loudly.
Golden test: generate the handover for the real week of 2026-09-01
through 2026-09-05 and run the checker over it. Verification needing
the resident, and this task's falsifier: read that golden handover
cold and try to catch the errors in it — if the resident finds a
claim the checker passed but the ledger contradicts, the derivation
rule is broken and the task is not done. Per the evidence, the
handover is measured by whether its reader can catch errors, never by
how confident its reader feels.

## Decisions reserved for the resident

1. **The name** (handover is this brief's proposal; the collision
   with "brief" is the only non-negotiable).
2. **Cadence and channel**, once the on-demand generator exists.
3. **The review-sampling parameters** — deferred to the audit-surface
   task by design, flagged here so their absence reads as a decision,
   not an oversight.

## Sources

`docs/research/operator-handover.md` (evidence base; per-claim [V]/[R]
markers — note the Shattuck primary and the SA-taxonomy percentages
are [R] and flagged for re-verification).
`docs/research/elicitation-papers.md` (question-budget discipline for
field 5; the Inter2US faithfulness/coverage pair and the unstudied
human-confirmation half of read-back for field 6).
`docs/backlog/legible-history-calibrated-trust.md` and
`docs/backlog/weekly-audit-vigilance.md` (both stay open; this brief
draws on them without promoting them). `docs/architecture.md`
Proposal 06. Emcee's `docs/research/agentic-pr-review.md` (the
quality-verdict ladder this brief leans on and does not widen).
