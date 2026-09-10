# Agent-computer interfaces for GUI-building: what the sweeps found

*Research done 2026-09-09/10: six parallel literature sweeps, each
instructed to refute a stated design hypothesis, run while designing
the Mediatron platform (the gui-surfaces backlog entry, promoted or
pending, holds the design context). This records the verdicts and
the load-bearing sources so later specs cite a record, not a
conversation. Figures a sweep could not verify against primary text
are flagged in place.*

## Verdicts

**ACI principles are real; the winning property is curated
informativeness, not small action spaces.** SWE-agent's ablations
(Yang et al., NeurIPS 2024, arXiv:2405.15793) are measured results:
a 100-line windowed file view beats both a full dump and a smaller
window; an edit command with a syntax-lint guardrail that rejects
unparseable edits is worth ~3 points alone; summarized search beats
stepping through results. Anthropic's tool-design writing agrees
directionally (tool consolidation; a measured 206-token to 72-token
response cut). No published work tests transfer to artifact-building
tasks; a CHI 2026 workshop paper (arXiv:2603.10664) names that gap
as its own limitation.

**Semantic-tree perception wins, but never trust one surface.**
UIFormer (arXiv:2512.13438): consolidating accessibility trees into
user-perceived semantic components — one level up, where a component
kit sits — cut observation tokens 50–88% while raising task success
across five models, beating both flatter and more verbose
representations. CI4A (arXiv:2601.14790) builds the semantic
interface into a component framework and reports a large WebArena
jump [headline number unverified against the primary PDF]. Cautions
that survived: screenshots still catch layout defects a tree misses
(VF-Coder, arXiv:2604.19750); models over-trust structure when it
contradicts pixels, with near-zero self-recovery (arXiv:2607.04334);
and mechanically-valid markup can be semantically empty (CHI EA '26,
541 violations passing every syntactic check). Consequence: a
tree-first inspection verb in the authoring vocabulary, screenshots
as cross-check, and tree/screenshot disagreement treated as a
first-class failure signal.

**Fixtures: pose states, diff assertions, never pixels.** WebRISE
(arXiv:2606.03220): state-and-transition assertion graphs catch
defects at 2–16x the rate of checkpoint-style golden comparison, and
visual quality is no proxy for behavior. Pixel-golden diffing is
being designed away from across the field (FSE 2026 WebTestPilot;
Chromatic noise complaints). An autonomous test-repair case study
(arXiv:2605.01471) documents LLM verifiers weakening assertions and
deleting failing tests to inflate pass rates — verification lives
outside the authoring model, and goldens change only by reviewed
commit.

**A constrained component kit: structural certainty, honestly
bounded.** Catalog-constrained generation reports 98%+ structural
validity and under 1% component hallucination, with a 4B model
recovering ~97% of frontier quality at a tenth the cost
(arXiv:2609.04184); an LLM-oriented DSL beat Python by 40 points on
multi-step composition (arXiv:2512.23214); type-constrained decoding
halves compile errors while improving functional correctness (ACM
PACMPL, arXiv:2504.09246). Bounds: constrained decoding can relocate
errors into valid-but-wrong output unless the constraint targets the
real failure mechanism (arXiv:2606.21619); format constraints tax
weaker models on hard reasoning; and Google DeepMind's Generative UI
(arXiv:2604.09577) reached 0% output errors with free-form HTML plus
a heavy repair pipeline — constraint is one road, not the only one.
The near-zero hallucination figures in production systems are
properties of a validate-and-retry loop, not of model virtue.
Functional correctness is explicitly not the kit's job; fixtures and
verbs carry it.

**Derive live, never scaffold once.** Django admin (runtime
introspection, regenerated every run, overrides layered on top) has
outlived every scaffold-then-edit generator; the AWS CLI is
generated from service models across 300+ services; kubectl keeps
hand-written workflow verbs above a generated floor. A derived
default surface should be regenerated from the schema at runtime
with authored overrides — never emitted once as code to fork.

**Multi-target: share semantics, delegate rendering.** Survivors
(MAUI, SwiftUI, Lyft's product-named server-driven components) share
a semantic description and let per-target machinery own pixels;
failures owned pixels across targets or coupled to one engine. Ink
shares React's programming model but ships a separate terminal
vocabulary — identical semantics, not identical components. The
strongest counter-thesis on record (Increment, 2021): the layer that
survives sharing is business logic, not UI. Terminal-renderability
works as an abstraction-level test for kit components.

**Gap claim: partially refuted.** Pieces exist as vendor tooling —
Storybook's MCP server (a real perception verb in `stories-preview`,
component manifests), Figma Dev Mode MCP, shadcn's registry, and
Replit's "Potemkin interfaces" write-up naming exactly the
renders-but-nothing-wired failure. No synthesized, evaluated ACI
discipline for GUI-building exists; no controlled study measures a
harness intervention (every benchmark measures models, none measures
tooling); "fixture posing" and "perception verbs" appear as
vocabulary nowhere.

## Unrun experiments worth owning

1. The harness intervention: add ACI verbs to a UI-construction
   benchmark one at a time; measure the delta. Nobody has run it.
2. The kit A/B: same model, same prompts, kit code versus raw HTML.
   The catalog literature assumes the answer; no head-to-head exists.
3. The instrumented first build: log loop iterations, stall points,
   and verbs-used-versus-worked-around from Mediatron's first real
   app, under the baseline-before-intervention constraint.

## Method note

Six sweeps, ~240 tool calls. Systematic hazards the sweeps caught:
arXiv PDF extraction frequently returned paraphrase rather than
source text (derived numbers flagged), and one fetched summary
mirrored the query's own taxonomy and was discarded as
summarizer-confabulation — itself a finding about
summarizer-in-the-loop research. Full sweep reports with per-source
confidence live in the session transcripts of 2026-09-09/10.
