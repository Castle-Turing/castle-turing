Title: Task 0061 — a current-state layer, and the milestone document as its first page
Model: deep
Milestone: m2-done
Model-because: nothing here is mechanical and everything here is a
commitment — this task decides which text in the repo is authoritative
*now* versus historical record, a distinction every later task and
every generated report will lean on. The diff is small; a standard-tier
implementer would produce the same files with plausibly-wrong authority
semantics, and no test can catch "this document quietly claims more
than was decided." The judgment is the deliverable.

# Task 0061 — a current-state layer, and the milestone document as its first page

**Status: approved by the resident 2026-09-06 (read via
dovetail-show) and committed on its implementing branch — this PR is
the implementation. The milestone content in §Decisions was updated
2026-09-06 with the resident's stated direction before approval.**

**Before starting:** read `CLAUDE.md` and
`.claude/skills/implement-brief/SKILL.md`. Then
`docs/research/inter-task-handoff.md` (landed with this brief — the
evidence base), and emcee's `docs/research/skill-state-review.md`
(2026-09-02), whose caveats about SKILL.state's evidence bind every
claim made here.

## The problem, in one paragraph

The repo records intent at three altitudes — the vision (timeless),
two principles (binding), and a flat backlog plus numbered briefs
(ground level) — with nothing in between stating what the project is
building *now* and what "done" looks like. Direction lives in the
resident's head, so the pipeline optimizes the only signal it can see:
whatever lands in the backlog. The evidence is recent: while the
vision's own declared starting point (focus mode, email triage,
decision journal) remains unbuilt, the autonomous pipeline's last
three merged tasks were a sandbox fix, confirmation copy, and a
terminal-padding sweep tool — each individually correct, each clearing
every quality gate, because the gates answer "was this done well?"
and nothing answers "was this worth doing?" A second symptom of the
same defect: briefs are cited as current authority (task 0058 calls a
done brief "the authority record this task extends"), so the
required-reading graph grows with project history — the append-only
context pattern the research review documents as the failure mode.
The backlog entry
`docs/backlog/tidying-a-brief-into-done-rots-its-citations.md`
records 140 stale brief citations across 25 files; that rot is what
citing history as authority costs.

## What this task builds

A `docs/state/` directory: the small set of documents that claim to
be true *now*. Everything else in `docs/` — briefs, backlog, research,
journal — is record: what was decided, found, or considered, never
what currently holds. Two files to start:

1. **`docs/state/README.md`** — the authority rule, stated for
   strangers (contents specced below).
2. **`docs/state/MILESTONE.md`** — the current milestone: what it is,
   what "done" looks like, what it explicitly excludes, and the
   current position against it. Content is the resident's decision —
   see "Decisions reserved for the resident."

And four conventions, added to `docs/tasks/README` (and a two-line
pointer in `CLAUDE.md`, which needs the resident's explicit approval
regardless of any autonomy grant):

1. **The authority rule.** A document in `docs/state/` is maintained
   and authoritative; a brief or backlog entry is a record. When later
   work needs to cite a brief *as authority*, that is the signal to
   extract the load-bearing content into `docs/state/` (or an existing
   maintained doc) in the same PR, leaving the brief as the record of
   how the decision was reached. Records are cited by task number as a
   name ("task 0048"), never by path — which is this brief's answer to
   the citation-rot entry's closing question ("decide whether a
   citation is a link or a name"): a citation of *history* is a name;
   a citation of *authority* is a link, and it points into
   `docs/state/`.
2. **The same-PR patch rule.** A PR that changes what is true —
   completes milestone work, makes a design decision, retires a
   constraint — updates `docs/state/` in the same PR. The reviewer
   reads the state diff as part of the review: it is the SKILL.state
   "validated patch," with PR review as the validator. This is also
   the fix for spec drift, the dominant reported failure of
   spec-driven artifact chains (see the research review §5).
3. **The milestone citation.** Every backlog→brief promotion carries a
   `Milestone:` header line naming the milestone section it serves, or
   the explicit value `none — hygiene`. Deriving tasks cite the
   specific `MILESTONE.md` clause they derive from, so a milestone
   revision identifies exactly the queued tasks it invalidates
   (PlanFence's result: freshness alone let 30 of 30 stale plans
   execute; clause citation stopped all 30).
4. **Deliberate accommodation.** Adding a document or top-level
   section to `docs/state/` is a deliberate act recorded in the PR
   that does it, with one line on why the new slot exists — lighter
   than adopting a principle, but never incidental. The schema is
   discovered as the project self-assembles; each discovery is logged,
   not slipped in. Automatic slot *induction* is explicitly out of
   scope now — the induction literature (GenDSI) clusters candidates
   across thousands of instances, and this project has one milestone
   document and no history; a wrong automatic schema decision corrupts
   everything downstream, and supersession error is the measured
   dominant failure of model-maintained state. The designed-for
   evolution, once the state layer has months of patch history: an
   agent that repeatedly finds content with no slot to assimilate into
   may *propose* a new slot through this accommodation step, citing
   the recurring instances as evidence — Proposal 05's grammar, with
   only the resident closing the question.

## Constraints on how state documents are written

From the research review's best-evidenced findings, stated here as
binding style rules for `docs/state/` content:

- **Constraints carry four fields where they bind:** what must hold
  (prerequisite), who may waive it (authority), what to do if it
  cannot hold (fallback), and what breaks if violated (consequence).
  Restoring exactly these four fields took constraint violations from
  54.2% to 0.0% in the one controlled ablation
  (arXiv:2608.24569). Written out in prose is fine; present is
  mandatory.
- **Explicit language, never hedged.** Vaguely worded constraints
  leaked through summarization in 50–73% of cases; explicit wording
  cut leakage below 15% (arXiv:2608.29028).
- **Prose with headings, not a data format.** Structure buys
  auditability, not accuracy — structured notes tied prose summaries
  in the one direct comparison, and converting instructions to markup
  *cost* accuracy (arXiv:2606.02875, 2608.20786). State documents are
  small structured *prose*; do not invent a schema language.
- **Deletion is reviewed like addition.** Premature overwrite/deletion
  is the dominant measured failure of model-maintained state (68% of
  categorized failures in SKILL.state; supersession accuracy does not
  improve with a bigger budget, arXiv:2606.27472). The state diff in
  every PR is where a human or reviewing agent catches it. The
  backlog stays append-only precisely as the hedge against deleting
  what later turns out to matter.
- **Uncertainty is written down, never resolved by guess.** A state
  document's clauses distinguish what the resident *stated* from what
  the system *inferred*, and a clause whose ambiguity is unresolved
  carries an explicit tag rather than a silently chosen reading — the
  measured primary failure of agents given ambiguous direction is
  "silent commitment": clean artifacts hiding an unintended
  interpretation (Ambig-DS, arXiv:2605.09698), and no published
  system yet records ambiguity and proceeds
  (`docs/research/elicitation-papers.md`, where this convention makes
  the project first). Tags are lintable (present, and cleared only by
  a cited answer), and the future intake phase resolves them through
  its question channel rather than this layer resolving them by
  fiat.

## Relationship to OpenSpec, stated honestly

OpenSpec's layout (`openspec/specs/` as maintained current truth,
`openspec/changes/` as archived deltas) is this same split, arrived at
independently — corroborating the shape. The resident is considering
trialling OpenSpec. This brief deliberately builds the split natively
in `docs/` rather than adopting the tool, for two reasons: the queue
contract (`Title:`-headed files emcee reads) and the briefs convention
already exist and work, and the one independent evaluation of
spec-driven development found *no* support for its vendor quality
claims — the Hill study, verified first-hand on 2026-09-06 against
the resident-supplied paper (see the addendum in
`docs/research/inter-task-handoff.md`). Two of its readings bind this
brief directly: its construct mostly measured artifacts looser than
this project's briefs, so it is weak evidence about disciplined
briefs specifically; and its own discussion distinguishes *directing*
an agent (which specs may do well) from *ensuring quality* (the claim
its five nulls reject), arguing that a spec "does not tell the AI
what it forgot to specify" and that specs create value as audit trail
and durable documentation — which are precisely the direction,
record, and forgot-to-specify functions this project's documents
serve. The case for this task rests on the state-versus-history
literature and those functions, not on SDD quality marketing. An OpenSpec trial stays compatible: its `specs/`
maps onto `docs/state/`, its archive onto `docs/tasks/done/`. Whether
and where to run that trial is the resident's call, recorded below.

## What this task does not do

It does not shorten or restructure existing briefs; they are records
and stay as written. It does not fix the 140 stale citations (that
backlog entry stays open; this brief settles only the link-or-name
question its last line asked). It does not build the generated
operator report — that is task 0062, which requires this one. It does
not add CI enforcement of any new convention; enforcement, if wanted,
is a later task once the convention has been lived with.

## Decisions reserved for the resident

1. **The milestone's content — decided by the resident, 2026-09-06,
   superseding the seat's earlier recommendation** (which had been the
   vision's founding loop; the resident chose differently and the
   choice is recorded here so `MILESTONE.md` drafts from direction,
   not from a suggestion). The first milestone — "my cursor is too
   small," chosen in mid-August 2026 as a deliberately tiny slice to
   force the plumbing into existence — was achieved on 2026-09-05.
   The second milestone is the **self-assembling slice**: the
   castle-modal UX redesign (per the existing design comp in
   `docs/comps/`), delivered *by* the pipeline this brief and task
   0062 describe rather than by hand. The forcing function is the
   point: the resident opens the modal with the key chord and states
   the complaint; clarifying questions about what exactly to
   implement come back through the modal; the milestone lands in
   `docs/state/`; the work is decomposed into small, well-defined
   tasks; clarifying questions route to the resident automatically;
   emcee picks tasks up; handovers report where the plan stands; the
   resident approves PRs (explicitly retained for now) and finally
   the deployment. Deliberately deferred by the resident: work
   prioritization (assume accepted work gets implemented) and any
   change to PR approval. Done looks like: the resident interacts
   with a visibly better modal that the system built for itself, and
   a surface exists that a conversational interface can later be
   grafted onto.
2. **The CLAUDE.md pointer** (two lines naming `docs/state/` and the
   same-PR patch rule) — explicit approval required by standing rule.
3. **The OpenSpec trial** — whether, and in which repo.

## Implementation plan and verification

Branch `castle/0061-the-current-state-layer`. Commit this brief, the
research reports with a one-paragraph addition to
`docs/research/README.md`'s trust-discipline section, the
`docs/state/` directory, and the `docs/tasks/README` amendment. No
code changes; `nix flake check` must remain green (expected trivially).

*(Updated in-PR per the design-shift rule, 2026-09-06: the branch
carries all six research reports of the series, not the two this plan
first named — one series, one trust paragraph, and the reports
cross-reference each other. It also carries the research loop's other
records — the backlog entries filed across the same two days — and
the two approved, unimplemented briefs, tasks 0062 and 0065, which
land at the queue's top level where their `Requires: 0061` holds them
until this PR merges. One vehicle for one loop's records, so the
working tree is empty when the loop closes.)*

Verification that needs no human: a checker pass over `docs/state/`
confirming every constraint paragraph names its four fields, and that
`MILESTONE.md` contains the required sections (intent, done-criteria,
exclusions, current position).

**Lint inventory, recorded here for the checker and its successors.**
Deterministic checks beat model reviewers on everything mechanically
decidable (the inspection review's central result), so the roadmap is
written down even where this task ships only the first piece. For
state documents (this task): required sections present; clause
anchors unique and stable; every queued task's clause citation
resolves against a live clause; diffs that delete state lines are
flagged for explicit review attention. For task files (follow-on,
once the conventions here have been lived with): header keys present
and paired (`Model:`/`Model-because:`, `Requires:`/
`Requires-because:`, `Milestone:`); cited task numbers resolve
against `docs/tasks/` including `done/`; authority links resolve into
`docs/state/`; a length cap. Two disciplines bind all of it: lints
that require judgment (hedged constraint wording, smell-type checks)
run at 30–59% measured precision and therefore *warn into review*,
never block — a blocking lint at that precision gets switched off;
and no lint claims to check completeness, correctness, or necessity,
which have no operational detector anywhere in the literature and
stay with review and this brief's falsifier. Verification that needs the resident:
read `MILESTONE.md` cold and answer one question — "from this document
alone, would the padding-sweep tool have been queued this week?" If
the document does not answer that, it has failed its purpose and goes
back for revision. That question is this task's falsifier.

## Sources

`docs/research/inter-task-handoff.md` (evidence base; per-claim [V]/[R]
markers, and the 2026-09-06 addendum verifying the Hill study
first-hand). `docs/research/elicitation-papers.md` (the
stated-versus-inferred and ambiguity-tag conventions; silent
commitment as the measured failure). Emcee's
`docs/research/skill-state-review.md` (SKILL.state caveats).
`docs/backlog/tidying-a-brief-into-done-rots-its-citations.md`
(the citation-rot record; stays open). SKILL.state itself: arXiv
2608.26263, read first-hand 2026-09-05.
