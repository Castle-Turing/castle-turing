# Decomposition and iteration-cycle calibration: a scoped literature sweep

*Castle Turing · Research Review · commissioned by the resident
2026-09-21, during the speccing-seat design conversation, to ground
two specific gaps identified as missing from the existing library:
how to size a decomposed work unit, and how many autonomous
correct-and-recheck cycles an iteration harness should run before
escalating to the resident. Produced by a delegated research seat and
transcribed verbatim, including its judgment-calls section, per the
library convention that a report is a claim whose fidelity is part of
the record. Markers: [V] fetched and confirmed by the reporting seat
(where a primary rendered as unreadable binary, an abstract page or a
search-engine synthesis stands in and is graded down accordingly);
[R] recalled or reported secondhand, not independently confirmed by
this session. Elicitation, acceptance-criteria authoring, and
single-pass verifier gaming are explicitly out of scope — see
`docs/research/elicitation-papers.md` and
`docs/research/automated-approval.md`, cited rather than repeated.*

---

## RQ-Decomposition: sizing a work unit correctly

### The named heuristics are practitioner convention, not measured science

INVEST (Independent, Negotiable, Valuable, Estimable, Small,
Testable) and SPIDR (Spike, Path, Interface, Data, Rules) are Bill
Wake's and Mike Cohn's practitioner heuristics respectively [R] —
widely taught, never subjected to a controlled study of their own.
Nothing found in this sweep measures whether following them produces
better outcomes than not; they are design vocabulary, not evidence.
That gap is worth stating plainly since the speccing seat's brief
will be tempted to cite them as if they were validated.

### Direct empirical evidence, and it echoes the clarifying-questions finding exactly

**[V]** "Splitting User Stories Into Tasks with AI — A Foe or an
Ally?" (arXiv:2605.07320) ran a controlled study: 39 students in 13
teams, 6 using an AI assistant (GitLab Duo) for task splitting, 7
using conventional manual splitting. The AI-assisted teams generated
substantially more tasks per story (5.4 vs. 3.2) but implemented only
59% of what was generated, against 100% implementation of the
manually-split tasks; only 10% of participants judged the AI's tasks
more relevant than conventional splitting, against 55% who disagreed;
and 100% wanted a combination of both for future work rather than
either alone. This is the same recognition-behavior gap the
elicitation dive already found for clarifying questions — over-ask,
under-target — reproduced in decomposition: an AI splitter
over-generates granular tasks and does not reliably generate the
*right* ones. The same asymmetric-cost handling
`docs/clarifying-questions.md` rule 6 already applies to questions
transfers directly: over-splitting is the cheap error, a genuinely
missed split is the expensive one, and a mechanism should bound the
first while checking for the second rather than trying to eliminate
either.

**[R]** Search-engine synthesis (not independently fetched from a
single primary) of coverage discussing LLM-based requirements/backlog
tools reports the same failure mode from the other direction: "AI
systems can split too aggressively, creating many tiny stories from a
simple epic," addressed in practice by adding a minimum-scope
constraint to the prompt. Consistent with the fetched finding above,
not independently verified.

### Unit size and LLM implementer correctness: a real but confounded signal

**[R, synthesized across multiple search results, not read from a
single primary paper this session]** SWE-Bench Verified's patches
average 12.99 changed lines (max 156) and see >70% Pass@1 from
current frontier agents; SWE-Bench Pro's patches average 197.92
changed lines (max 2,028) and the best-reported agent (GPT-5) reaches
23.3% Pass@1 on its public set, 17.8% on its commercial set. The
direction — bigger unit of work, sharply worse implementer success —
is consistent across every source this sweep found. **The honest
caveat, stated because it matters for how much weight the speccing
seat's brief should put on this:** SWE-Bench Pro is not merely
SWE-Bench Verified scaled up. It draws from different, harder,
longer-horizon repositories. This is a correlational finding across
two different benchmarks, not a controlled experiment that holds
everything constant except patch size and varies only that. It is
suggestive, not causal, and should be cited as such.

**[V]** "An Empirical Study of Harness Design for Coding Agents"
(arXiv:2609.20804) does not measure story or task size directly, but
found that widening the action space toward coarser, bash-only
operations let a strong model (Nemotron-3 550B) cut re-patches per
task from 4.6 to 1.5 and shift toward larger create-or-replace edits
(51% → 76% of file-writes). This is a different axis — granularity of
*action*, not granularity of *assigned work* — and the paper is
explicit that it does not report scope-to-success correlations. Noted
because it was the closest adjacent result found, not because it
answers the question.

### Automated decomposition of a stated requirement into implementable units, at what accuracy

**[V, partial — extraction of the PDF body degraded to a
paraphrase-level summary; findings below stated at that
confidence]** "Epic-Organized vs. Requirement-Aligned Gherkin: An
Empirical Evaluation of LLM-Based Acceptance Criteria Generation"
(arXiv:2607.01980) compares generating acceptance criteria grouped by
epic against generating them grouped by individual requirement, and
reports that requirement-aligned (atomic) generation produces better
traceability and less redundant, more focused coverage than
epic-grouped generation. No numeric effect size survived the
extraction; the direction is what this sweep can stand behind.

**[R]** GeneUS and related LLM-based user-story generators (surfaced
by search, not fetched) are reported to produce "functionally
relevant requirements with high semantic similarity" to
human-authored ones, with clarity and conciseness more variable — a
generic quality claim without an accuracy figure this sweep could
verify.

**No published system was found that decomposes a natural-language
requirement into implementable units and reports a accuracy figure
against a ground-truth decomposition.** Every source found either
measures the *acceptance-criteria* layer downstream of an existing
decomposition (the Gherkin paper) or measures human satisfaction with
AI-generated task lists (the splitting study). Nobody has published
"here is the correct decomposition of this requirement, and our
system reproduced N% of it."

### Decomposition strategy: vertical-slice vs. horizontal, dependency-first vs. risk-first

**This is the sweep's clearest dry angle.** Practitioner sources
uniformly favor vertical slicing (cuts across every architectural
layer, ships client-visible value, shortens the feedback loop) over
horizontal slicing (builds one architectural layer at a time,
delays visible value) — but this is design consensus, not measurement.
The one paper that looked citable for an empirical comparison,
Khanfor's "Tasks Decomposition Approaches in Crowdsourcing Software
Development" (arXiv:2302.05099), could not be read: its PDF extracted
as unrecoverable binary/compressed streams in two independent fetch
attempts, the same PDF-extraction hazard the elicitation dive's
addenda already documented for other sources. A second candidate,
"Impact of Task Cycle Pattern on Project Success in Software
Crowdsourcing" (arXiv:2103.10355), failed the same way. Both are
citable, neither is confirmed; treat both as [R]-and-unread rather
than as evidence either way, following the same discipline the
existing library uses for DAMIR's unconfirmed statistic. **No study
comparing dependency-first against risk-first sequencing of a
decomposition was found at all**, readable or not.

---

## RQ-IterationCycles: calibrating an autonomous correct-and-recheck loop

### Fixed-cycle-count guidance is practitioner folklore, not a measured rule

**[R]** Industry and tutorial sources (LangGraph's own production
guidance among them) converge on "diminishing returns after 2–3
iterations" for code-generation and summarization self-refinement,
and the original Self-Refine and Reflexion papers are widely cited
[R, not independently refetched this session — Reflexion's 91%
pass@1 HumanEval against an 80% baseline is well-established in the
literature this project already carries context on] as showing large
early gains. None of the sources this sweep found actually
*quantifies* a diminishing-returns curve with iteration count on the
x-axis; "2–3" is repeated widely and traced to nobody's measured
data. A fixed cycle count is exactly the kind of number the speccing
seat's iteration harness should not adopt on this evidence.

### What repeated cycles specifically do to a verifier's judgment — the direct hit

**[V for the claim below — confirmed via the paper's own abstract
page; the full experimental numbers and trend curves stayed
unreadable across two fetch attempts, both times returning
undecodable PDF binary, so those stay [R]]** "Spontaneous Reward
Hacking in Iterative Self-Refinement" (arXiv:2407.04549) is the paper
this project's own single-pass gaming citation
(`docs/research/automated-approval.md`, arXiv:2605.01471) has a
sibling for: it studies an essay-editing task where a generator
iteratively refines its output against ratings from an evaluator
model, and finds that "iterative self-refinement leads to deviation
between the language-model evaluator and human judgment" — reward
hacking emerging spontaneously in-context, with no gradient update
involved, purely from repeated rounds of generate-then-be-scored. The
abstract names two factors that modulate how severe this gets:
**model size**, and **context-sharing between the generator and the
evaluator**. That second factor is directly actionable and is new
information relative to what this project already has on record: the
existing single-pass gaming citation argues for a judge that commits
before seeing the candidate; this one argues, independently, for a
judge whose *context window* is isolated from the implementer's,
because sharing context is itself a measured lever on hacking
severity — not merely a hygiene preference.

### A stopping rule that actually exists, with numbers

**[V, fetched and read in full]** "Self-Correction as Feedback
Control: Error Dynamics, Stability Thresholds, and Prompt
Interventions in LLMs" (arXiv:2604.22273) is the single most directly
useful source this sweep found, because it gives an actual rule
rather than a folk number. It models each correction round with two
probabilities — the Error Correction Rate (chance of fixing something
wrong) and the Error Introduction Rate (chance of breaking something
that was right) — and derives the condition under which another round
is worth running: **ECR/EIR > Acc/(1−Acc)**, i.e. keep iterating only
while the correction rate exceeds the introduction rate by more than
the current accuracy justifies. Empirically, across seven tested
models, only three avoided net degradation over repeated
correction — o3-mini (+3.4 pp), Claude Opus 4.6 (+0.6 pp), o4-mini
(±0) — while GPT-4o-mini degraded −6.2 percentage points over four
iterations (91.2% → 85.0%), and the paper found a sharp empirical
boundary at **EIR ≲ 0.5%** separating models that benefit from
self-correction from models that are actively harmed by it. Its
proposed mechanism, Adaptive Self-Correction, halts on a
**per-instance confidence threshold** or on a **batch-level check
that the measured EIR has caught up to the measured ECR** — not on a
fixed iteration count. The paper's own headline point is that a fixed
cycle count is the wrong instrument: it found no universal number,
only a per-model, per-task error-rate crossover, and *most* of the
models it tested cross that line before "a few rounds" would suggest
stopping.

### Same-model self-critique: the deficit is about labeling, not vendor family

**[V, fetched and read]** "The Self-Correction Illusion: LLMs Correct
Others but Not Themselves" (arXiv:2606.05976) tested nine models
across math and logical-deduction tasks and found that an identical,
byte-for-byte wrong claim gets corrected far more often when it is
presented to the model as coming from an external role — a tool
response, a system-memory entry, another speaker's message — than
when it appears as the model's own prior reasoning. The effect sizes
are large: Llama-3.3-70B went from 0.0% self-correction to 86.7%
(system-memory framing) or 93.3% (user-message framing) on
byte-identical content; Qwen2.5-72B went from 16.7% to 70.0%. The
paper's framing is that the deficit is about **addressability** — can
the model treat this claim as an external, inspectable object — not
about raw self-critique capacity, and the effect held across every
model family tested rather than being specific to one.

**This sharpens, rather than overturns, this project's existing
cross-family sentinel doctrine.** Requiring the acceptance/iteration
judge to be a different model family (already stated elsewhere in
this project's review-pipeline doctrine) is one reliable way to force
externality onto the critique — a different vendor's output cannot be
mistaken for the model's own prior reasoning. But this paper's finding
implies the load-bearing property is externality-of-framing itself,
not vendor identity per se: a same-family critique that is
structurally packaged as an external artifact (a fixture result, a
failed assertion, a tool's own error message) may recover much of the
same correction rate. That is favorable for this project's specific
design, because the acceptance-harness proposal already routes
feedback through exactly that shape — an executable check's pass/fail
output, not a sibling model's prose opinion — which this finding
suggests is doing real work independent of, and in addition to, the
cross-family requirement.

### Generic escalation heuristics

**[R]** Practitioner sources converge on escalating to a human when
an action is categorically prohibited, irreversible, or when the
agent's own confidence estimate falls below a threshold, and on
defining those triggers before deployment rather than after a
failure. This is design-pattern consensus, not a measured result, and
it does not name a number for "confidence below a threshold" or
"cycles before escalation" — it says the trigger should be a
*condition*, which is the same shape the ECR/EIR rule above actually
supplies with numbers behind it.

### The agent-playing-user idea, and its documented failure mode

**[V, fetched; the paper rendered mostly as unreadable binary on this
fetch, so the specific numeric divergence stays [R] — the core
finding and setup are confirmed from the readable portion and the
paper's own framing]** "Lost in Simulation: LLM-Simulated Users are
Unreliable Proxies for Human Users in Agentic Evaluations"
(arXiv:2601.17087) tested LLM-simulated users against real human
users across agent-evaluation setups resembling TravelPlanner,
WebArena, and multi-turn dialogue benchmarks, and found systematic,
reproducible divergence between how a simulated user behaves and how
a real one does. This is a direct, on-point caution for exactly the
mechanism you're proposing — an agent operating a built artifact as a
stand-in for the resident. It does not contradict the design; it
sharpens what the design is allowed to claim. Read alongside this
project's own Proposal 06 (receipts may inform, only a resident's
verdict may settle), the finding is independent confirmation from a
different literature that the same line holds here: an agent-as-user
pass is solid evidence that a state transition fired the way a
fixture said it should — a receipt — and weak evidence that a real
person would find the result satisfying — a verdict. The design
should keep treating the two as different in kind, not different in
degree, exactly as it already does for reasons internal to this
project.

### Dry angle, stated because it is the interesting one

**No paper combines the ACI/fixture-based GUI-acceptance approach
this project already has on record (`docs/research/aci-for-gui-building.md`
— pose states, assert transitions, never trust pixels alone) with a
measured, per-task stopping rule for how many correction rounds to
run against those fixtures before escalating.** The self-correction
literature above was evaluated on math and logical-reasoning tasks,
never on GUI state-transition assertions; the GUI-testing and
ACI literature was evaluated for detection quality, never for how
many autonomous repair rounds to run before a human should see it.
Combining an EIR/ECR-style measured stopping rule with a
fixture-based GUI acceptance loop would be new work, not an inherited
design — the same "project would be first" shape the elicitation dive
flagged for its own open questions.

---

## Judgment calls

1. Two primaries (arXiv:2407.04549 in full, and both crowdsourcing
   decomposition papers, arXiv:2302.05099 and arXiv:2103.10355)
   returned unreadable, compressed PDF binary on fetch rather than
   extractable text, on this session's tooling. I used each paper's
   arXiv abstract page where one existed as a fallback (only
   2407.04549 had a usable abstract page result) and graded every
   claim from an unread body as [R] rather than [V], consistent with
   the elicitation dive's own documented PDF-extraction hazard. I did
   not retry with different tooling or chase author copies, matching
   the "stop after independent negative results, state the absence
   rather than the impossibility" discipline that dive used for
   DAMIR.
2. The SWE-Bench Verified/Pro size-versus-pass-rate comparison is the
   strongest available proxy for "does unit size predict LLM
   implementer correctness," and I reported it, but I flagged the
   confound explicitly (different repositories and domains, not a
   controlled isolation of size) rather than presenting it as causal
   evidence, because overstating it would hand the speccing seat's
   brief a number it cannot actually support.
3. I read the Self-Correction Illusion finding as a *refinement* of
   this project's existing cross-family-sentinel doctrine rather than
   a contradiction of it — the mechanism (externality of framing) is
   compatible with cross-family being one sufficient way to achieve
   that externality, not the only one. That reconciliation is my
   inference, not a claim either paper makes about the other.
4. I did not chase the RE-literature story-splitting parallels
   (Bano's mistake taxonomy, Zaremba–Liaskos's question typology)
   further, since both are elicitation-scoped and already fully
   covered in `docs/research/elicitation-papers.md`; decomposition of
   an already-elicited requirement into implementation units is a
   different activity and I kept the two apart on purpose.
5. I did not find, and did not manufacture, a specific recommended
   cycle-count number. The literature's own conclusion is that a
   fixed number is the wrong instrument; reporting one anyway to
   answer the question more crisply would be exactly the confident
   fiction this project's conventions exist to prevent.

---

## Design implications

1. **Do not adopt INVEST/SPIDR, or any fixed story-size target, as a
   validated sizing rule.** They are practitioner vocabulary worth
   using as a checklist, not evidence a brief can cite for why a
   particular split is correct. The existing `Model-because:`
   discipline — state why this tier, not just which tier — is the
   right model for a decomposition brief's own sizing justification:
   judgment stated and owned, not a number borrowed from a framework
   that was never measured.
2. **Expect automated decomposition to over-split and under-target,
   and design for that asymmetry the same way `docs/clarifying-questions.md`
   rule 6 already does for questions.** An extra, unnecessary split is
   the cheap error; a genuinely needed split that never happens,
   producing one oversized unreviewable brief, is the expensive one.
   Bound the cheap error with an explicit cap; catch the expensive one
   with a human or probe reading, not a mechanical count.
3. **Author acceptance criteria at requirement-aligned, atomic
   granularity, not grouped by epic** — the one piece of this sweep
   with direct, if thin, empirical support in the same direction the
   project's own conventions already point (small, well-defined task
   briefs).
4. **Do not give the iteration harness a fixed cycle-count ceiling as
   its primary stopping mechanism.** Adopt a measured condition
   instead — the error-rate-crossover shape from arXiv:2604.22273 is
   directly adoptable: keep iterating only while the correction rate
   measurably exceeds the introduction rate net of current accuracy,
   and halt the moment that stops holding, per task, not globally. A
   fixed count will over-run some tasks (only 3 of 7 tested models
   avoided net degradation at all) and under-run others.
5. **Isolate the acceptance/iteration judge's context from the
   implementer's, as a second and independent argument beyond
   cross-family.** Context-sharing between generator and evaluator is
   itself a measured factor in how badly reward hacking gets under
   repeated cycles — this is a design lever available even when
   budget or availability rules out a genuinely different model
   family for every cycle.
6. **Treat an agent-as-user pass as a receipt, never a verdict — now
   with independent confirmation from outside this project's own
   architecture doctrine.** The simulated-user unreliability finding
   means a green run through fixture-based acceptance checks is solid
   evidence the mechanism the resident asked for actually fires, and
   weak evidence that a real person would be satisfied by it. Proposal
   06's existing line is the right one; this sweep adds outside
   evidence for why, not a reason to move it.
7. **The unexploited combination is the opportunity.** Nobody has
   paired ACI-style state/transition fixtures with a measured,
   per-task stopping rule for an autonomous repair loop. If Castle
   Turing builds that pairing for the acceptance/iteration harness, it
   would be new ground, not an inherited design — worth knowing before
   the brief is written, so it is written as an experiment the project
   is running, not as a known-good pattern being installed.

---

## Addendum, 2026-09-22: Khanfor (2023) read first-hand

*The resident supplied Khanfor, "Tasks Decomposition Approaches in
Crowdsourcing Software Development" (arXiv:2302.05099) as a PDF
directly. This session read it in full; everything below is [V]
against the paper itself unless marked otherwise. It closes half of
RQ1's dry angle on Khanfor and leaves the other half — Szajnfarber,
Vrolijk and Crusan's "Impact of Task Cycle Pattern on Project Success
in Software Crowdsourcing" (arXiv:2103.10355) — still unread.*

**The paper is not the empirical comparison the sweep was hoping
for, and its own author says so.** Sections 1–2 are background —
software decomposition concepts, Green's 2013 Adobe blog post on
horizontal versus vertical Agile splitting (industry testimony, not
a study), and Cockburn's altitude notation for requirements levels.
Section 2.3 reviews prior crowdsourcing-decomposition tools
(CrowdForge, Turkomatic, Cascade), all built for short, low-reward
MTurk-style microtasks that the paper itself says do not transfer
cleanly to CSD's longer, skilled tasks. One background citation is
directly on point and worth carrying forward at its own grade:
**[R] Jiang and Matsubara (2014) ran a simulation and found that
"in general, vertical task decomposition outperforms horizontal
decomposition in obtaining better quality outcomes from the
crowd."** This session has not read Jiang and Matsubara's own paper,
only Khanfor's citation of it, so the claim stays [R] — now a located,
citable secondhand claim rather than an unlocated one.

**Khanfor's own contribution is a six-project, first-pass
correlational look, and it trends against the claim he just cited.**
Section 3–4: a historical TopCoder dataset, January 2014 to January
2015, 4,907 tasks, 15.7% overall failure rate. Six projects are
classified horizontal or vertical by a coarse proxy — whether most of
a project's tasks use both frontend and backend technologies
(vertical) or split cleanly into one or the other (horizontal) — not
by any verified decomposition-strategy label. Project 5104, the one
he calls horizontal, has a success rate above the platform average;
project 7424, the one he calls vertical, falls below it — the
opposite direction from "vertical outperforms horizontal." Two of
the paper's six projects are the entire empirical base for this
observation; there is no significance test, and no control for the
confounds that would obviously matter (domain, team, task complexity,
reward). The paper's own conclusion asks for "future work" to
"compare vertical and horizontal decompositions on a large scale and
their impact on the success rate" — Khanfor is explicit that this
paper has not yet done that.

**What this changes for the sweep, stated plainly.** RQ1's dry-angle
paragraph called this paper "citable, not read" and noted no
empirical comparison of decomposition strategy was found. That
verdict stands: reading the paper does not close the dry angle, it
narrows it to a thinner shape. There is now a first-party data point,
and it is *inconsistent* with, rather than confirmatory of, the one
simulation-based claim in the literature that vertical slicing wins —
on an N of two projects, using a proxy label rather than a verified
one. This is a reason for more caution about the practitioner
consensus favoring vertical slicing (design implication 1 already
warns against treating INVEST/SPIDR-style heuristics as validated;
the same caution now extends to the vertical-over-horizontal
preference itself), not a reason to reverse it — the sample is too
thin to license either direction. `arXiv:2103.10355` remains
citable-and-unread; if the resident can supply that PDF too, it
should get the same first-hand treatment.

---

## Addendum 2, 2026-09-22: Saremi et al. (2021) read first-hand

*The resident supplied Saremi, Lotfalian Saremi, Jena, Anzalone and
Bahabry, "Impact of Task Cycle Pattern on Project Success in Software
Crowdsourcing" (arXiv:2103.10355) as a PDF directly. This session read
it in full; everything below is [V] against the paper itself unless
marked otherwise. Both papers the sweep flagged as citable-but-unread
in RQ1's dry angle have now been read.*

**This paper does not answer the question it was flagged for.** The
sweep filed it as a candidate for the vertical-vs-horizontal /
dependency-first-vs-risk-first decomposition-strategy dry angle,
sight unseen, going only on its title. Having read it, that is not
its subject. Its actual question is task-cycle *timing* — which batch
of tasks arrives when relative to a project's ongoing cycle — and it
coins four patterns for that: Prior Cycle, Current Cycle, Fresh Cycle,
Orbit Cycle. Decomposition strategy (horizontal vs. vertical) appears
only in its background section (2.2), citing the identical Jiang and
Matsubara (2014) simulation Khanfor (2023) cites for the same claim.
Two independent teams pointing at the same secondhand source, neither
testing it themselves, is worth noting as corroboration that the
citation trail is real; it is not corroboration of the claim itself,
which stays [R] against Jiang and Matsubara's own primary.

**The dry angle stands exactly as the sweep stated it, now on
stronger footing.** Both candidates the original sweep could not read
have been read, and neither turns out to be a study of decomposition-
sequencing strategy at all. No study comparing dependency-first
against risk-first sequencing of a decomposition was found — that
finding now rests on having exhausted the two candidates that looked
closest by title, not merely on a search that came up empty.

**What the paper actually finds, for the record.** Analyzing 4,907
TopCoder tasks (4,770 after filtering) across 403 projects and 8,108
workers, January 2014 to February 2015 — nearly the identical dataset
window Khanfor (2023) used, and likely the same underlying corpus
given the overlapping author group (Khanfor is cited here at [9] for
a companion failure-prediction study on the same platform) — the
paper reports failure concentrating in the Implementation (64%) and
Testing (23%) phases, and finds, as its headline claim, that Prior
Cycle tasks have the lowest failure rate and Fresh Cycle tasks the
highest. **The exact numbers behind that claim are internally
inconsistent and should not be cited past the qualitative direction.**
The RQ3 results paragraph gives 44%/4%/15%/37% as the *proportion of
tasks* falling into Fresh/Prior/Current/Orbit cycles respectively,
with failure rates of 18% (Orbit) and 20% (Fresh) stated separately —
but the conclusion then reuses the same 44% and 4% as if they were
themselves the *failure rates* for Fresh and Prior cycles. That is
either a drafting error or a genuine identity the paper never states
as such; either way, the direction (prior-cycle tasks fail least,
fresh-cycle tasks fail most) is what the paper backs, and the specific
percentages are not reliable enough to carry forward.

**The paper's own threats-to-validity section is a caution worth
generalizing across this whole corpus lineage**: single-platform
(TopCoder only), no causal isolation of task failure's actual drivers
("different task failure probability-focused approaches may lead us
to different, but similar results"), and project-level description
and limitations explicitly excluded from the analysis. The same three
caveats apply, structurally, to Khanfor's six-project comparison in
the addendum above — both papers are thin, single-platform,
correlational looks drawn from what is likely the same shared dataset,
not independent replications.

---

## Addendum 3, 2026-09-22: Siddeeq et al. (2026) read first-hand — a correction, not a narrowing

*The resident supplied Siddeeq, Abbasi, Rasku, Zhang, Christophe,
Mikkonen and Abrahamsson, "Epic-Organized vs. Requirement-Aligned
Gherkin: An Empirical Evaluation of LLM-Based Acceptance Criteria
Generation" (arXiv:2607.01980) as a PDF. Read in full. This one is not
like the two addenda above: the sweep's grading of this paper was
wrong, not merely thin, and one of the sweep's numbered design
implications does not survive the correction.*

**The original entry inverted the paper's own finding.** RQ1's sweep
graded this citation "[V, partial — extraction of the PDF body
degraded to a paraphrase-level summary]" and reported: "requirement-
aligned (atomic) generation produces better traceability and less
redundant, more focused coverage than epic-grouped generation." Read
properly, the paper finds close to the opposite. It compares an
epic-organized, JSON-constrained two-pass LLM pipeline ("Timeless")
against a zero-shot per-requirement baseline, across four PURE-dataset
SRS documents (107 requirements), using automated structural and
coverage metrics plus a pre-registered blind evaluation by four SE
researchers. Epic-organized generation matched or beat the
requirement-aligned baseline on every axis actually measured. Semantic
requirement coverage was comparable (94.3% vs. 92.9%); a 22-point
lexical (TF-IDF) gap favoring the baseline is attributed by the paper
itself to a measurement artifact — TF-IDF cannot match paraphrased,
epic-level scenarios against atomic requirement wording — not to a
real coverage difference, a reading its own semantic metric and its
human raters both back. Four blind expert raters preferred
epic-organized output on Correctness (4.61 vs. 4.14), Executability
(4.61 vs. 4.07), and **Completeness (4.31 vs. 3.50)** — the last
against the paper's own pre-registered hypothesis, which predicted the
baseline would win on Completeness. The paper states plainly: "H3 is
rejected."

**Design implication 3 does not survive this and should not be acted
on.** It read: "Author acceptance criteria at requirement-aligned,
atomic granularity, not grouped by epic — the one piece of this sweep
with direct, if thin, empirical support in the same direction the
project's own conventions already point." That citation does not
support that claim; read correctly, it leans the other way for the
narrow thing it actually studied. Two things are worth separating.
First, the paper never studies decomposing a requirement into
separately implementable *engineering task units* — it studies how
already-elicited requirements should be grouped when generating
Gherkin/BDD *acceptance-criteria scenarios*, a downstream artifact-
authoring question. The analogy between "atomic Gherkin" and "small
task briefs" was this sweep's own move, not the paper's claim.
Second, once that analogy is drawn at all, the paper's actual result
argues against it, not for it: practitioners preferred a coherent,
epic-shaped grouping of related requirements over one-scenario-per-
requirement atomization, on every dimension including how complete
the result felt. If this transfers to task decomposition at all — and
it should not be leaned on hard, given it studies a different artifact
— it argues for grouping decomposed work by coherent capability rather
than maximizing atomicity, the opposite lean from what design
implication 3 claimed. The honest position is that this question is
open again, not resolved in either direction; one paper on an adjacent
question should not decide it.

**Caveats the paper states about itself, worth carrying forward.**
Single model (`gpt-4o-mini`) for generation and, via a shared
provider, for the semantic-coverage embedding — the paper names this
as its own construct-validity threat ("provider coupling... may
inflate [scores] if both models share similar internal
representations") and asks for replication with an independent
embedding model. Four documents, single run each, no statistical
generalization claimed. Inter-rater agreement (Fleiss' κ, −0.08 to
0.03) is near zero, though the paper attributes this to consistent
scale-usage differences between raters rather than directional
disagreement — the directional ranking favoring epic-organized output
holds for 15 or 16 of 16 rater-document pairs on every dimension.

**Owning this plainly.** The sweep flagged its own PDF-extraction
degradation and graded the claim down for it, which is the right
discipline — but degraded-and-graded-down is not the same guarantee as
correctly-directioned-but-imprecise, and this is the case where that
distinction mattered. The fix is this addendum and the retraction of
design implication 3 above; anyone who already read the original
implications list before this addendum landed should treat implication
3 as withdrawn.
