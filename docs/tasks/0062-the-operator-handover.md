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

## As built — where the design moved, and the judgment calls

Written during implementation, per the rule that a brief its work has
overtaken is worse than none.

**Four pieces, not three, and the fourth is the point.** The plan said
a generator, a fixture and a claim-checker. What landed splits the
generator in two: `tools/handover-ledger.py` reads git, the forge and
the working tree into artifact state as JSON with no model in it, and
`tools/handover.sh` drives the agent turn between that and
`tools/handover-check.py`. The derivation rule is only enforceable if
something with no model in it establishes what is true; a single script
that both asked a model and judged its answer would be the thing this
brief exists to refuse. `tools/handover-prompt.md` holds the format and
doubles as its human-readable spec.

**The checker is a pure function of (ledger, handover).** It reads no
git, no forge, no tree. This was not in the plan and is what makes the
golden test possible at all: a frozen ledger keeps checking the same
way while the repo moves underneath it — briefs sweep into `done/`,
branches vanish, pull requests collect comments. A checker re-deriving
truth from the live repo would fail the golden test for reasons having
nothing to do with the handover under test. `test/handover/run.sh`
asserts the purity by running the checker from a directory that is not
a repository.

**A coverage unit is a pull request.** Field 6's coverage half needed a
definition of "substantive ledger event" and the brief does not fix
one. Merged-in-window and currently-open pull requests are the units;
briefs, backlog entries and state patches all ride one, so counting
them separately would demand the same event be narrated three times and
fight the one-screenful bound for no gain in what a reader can catch. A
line may cite a dozen at once, and grouped citation is how coverage and
one screenful coexist over a forty-merge window.

**The citation grammar and a closed receipt vocabulary.** Both are new
here. A citation is a bracketed span of `#102`, `commit <sha>`,
`task 0059`, `backlog: <name>`, `journal <id>`, `state <clause>` or
`unverified`, and anything else in brackets is an error, because a
reader cannot distinguish a decorative bracket from a citation at a
glance. Claims about artifact state use fixed phrases — `merged`,
`checks green`, `findings dispositioned`, `in the queue` — each checked
against what it cites. This is what makes "a merged-PR line whose PR is
open" mechanically detectable rather than a thing a reader must notice.

**Field 5's mechanical check is a `Depends:` line.** The brief requires
a verdict request to name what changes depending on the answer and says
the golden test should catch one that does not. That is only checkable
if the dependency is a field, so each request bullet carries an
indented `Depends:` continuation and its absence is a violation.

**A named gap in receipt matching.** Receipt phrases are ordinary
English — "a queue holding merged briefs", "backlog entries filed via
merged PRs" — and a checker reading every occurrence as a claim
rejected honest handovers while catching nothing. A phrase now binds to
the nearest citation group that cites an artifact of its kind, and one
with no such group anywhere in the item is treated as prose. What
escapes is a receipt asserted about a kind of artifact the item never
cites; what does not escape is a *wrong* claim, because the grounding
rule forces it to cite the artifact it is wrong about. Stated rather
than hidden: this tool is one control among several, not the whole of
one.

**Three defects the golden run found that reasoning had not.**

1. The ledger reader's first run wrote 308 real journal record ids and
   their absolute paths into a committed fixture. A journal is the
   private layer and CLAUDE.md's first hard rule bans every part of it
   from this repo. The reader now returns record ids only — never
   paths, never bodies, never the journal root — `--no-journal` exists
   for anything that gets committed, and `test/handover/run.sh` asserts
   the committed fixtures carry neither.
2. The ledger handed the generator clause keys with no text behind
   them, and the first draft said outright that it therefore could not
   restate the milestone — failing field 1, the field the evidence is
   strongest about. Clause text is now carried.
3. Seven docs-only merges read as "checks green" when `check.yml`'s
   `paths-ignore` had skipped every run. That is a false receipt of
   exactly the kind this surface exists to prevent, so a check set with
   no `SUCCESS` in it is now `skipped`, distinct from `absent` (no run
   was ever created), with a receipt phrase of its own.

**The golden test runs the checking half only.** CI has no `gh`, no
network and no model, so `test/handover/run.sh` checks the frozen
golden handover against its frozen ledger and asserts that twelve
reject fixtures are each refused with the violation code they name. The
generating half ran once, by hand, against the live forge; its output
is `test/handover/fixture/handover.md`. The falsifier this brief names
— the resident reading that file cold and finding a claim the checker
passed that the ledger contradicts — is unchanged and still needs
human hands.

**Not renamed.** "Handover" survives implementation as the brief
proposed it; the collision with "brief" does not occur anywhere in the
tooling. The name stays the resident's to settle.
