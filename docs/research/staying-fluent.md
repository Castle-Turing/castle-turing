# Staying Fluent

*Research brief · augmentation, not safety · prepared for Castle
Turing · 15 August 2026 · 8 threads across two research passes ·
frame: Primer-style augmentation, explicitly not AI-safety.*

*How a human stays a capable supervisor when the agent doing the work
has already outpaced their expertise in it. Originally rendered as a
private Claude artifact; transcribed to the repo 2026-09-03 so the
record travels with the project. The compressed, decision-relevant
versions live in `docs/backlog/` — this is the full report behind
them.*

The question behind this brief: when an agent is doing technical work
well beyond its principal's current expertise — Nix and NixOS system
administration is the concrete case — what keeps the principal capable
of real judgment, not just nominal oversight? The literature splits
cleanly into two families. One optimizes for *preventing bad
outcomes*; the other, much thinner, optimizes for *making the human
more capable*. This brief stays deliberately on the second side of
that line.

## 01 · Augmentation- vs. safety-oriented frameworks

**Shneiderman — *Human-Centered AI* (2020).** Automation and human
control are not opposite ends of one dial — his framework argues
designers should pursue both at once, aiming explicitly to augment and
enhance human lives, not merely avoid harm. *The strongest existing
anchor for an augmentation-first, not safety-first, design principle.*

**Horvitz — "Principles of Mixed-Initiative User Interfaces"
(1999).** Frames the interruption question as when and how an agent
should take initiative versus wait, weighing uncertainty about the
user's goals against the cost of interrupting them. *The direct
academic ancestor of the "interruption medium is itself a decision"
idea already in the project's vision.*

**Bainbridge — "Ironies of Automation" (1983).** The more reliable and
automated a system becomes, the less practice its human operator
gets — yet that operator remains nominally responsible, and needs more
skill, not less, to handle the rare case the automation can't. Several
2024–2025 essays re-run this argument explicitly for LLM agents. *The
load-bearing citation. Maps directly onto a resident supervising agent
work in a domain they have barely begun learning.*

**Lee & See — "Trust in Automation" (2004).** Separates trust
*calibration* (does trust match real capability) from *resolution*
(can the human tell where the automation is reliable versus not).
Overtrust breeds misuse; undertrust breeds disuse. *Useful vocabulary:
the resident's trust needs to be well-resolved per domain, not just
well-calibrated on average.*

**Parasuraman, Sheridan & Wickens — "Types and Levels of Human
Interaction with Automation" (2000).** Automation isn't one dial per
task — it's four, independently settable: information acquisition,
analysis, decision selection, and action implementation. *A
decomposition tool — an authority taxonomy could assign a resident's
rung per stage, not just per domain.*

## 02 · AI coding agents and developer understanding

**NAV IT longitudinal Copilot study (2023–25).** A rare field study
rather than a lab study, tracking 100 to 250 developers over time.
*One of the few empirical anchors for productivity and skill claims,
worth reading in full if this becomes a cited principle.*

**Practitioner consensus on acceptance-rate as an over-reliance signal
(2024–25).** Healthy Copilot suggestion-acceptance sits around 25–35%;
above 40% is a warning sign, and juniors accept at markedly higher
rates than seniors. "Copilot-free Fridays" is a cited team-level
countermeasure. *Confirms Bainbridge concretely: the people with the
least grounding lean hardest on the agent.*

**Osmani — "vibe coding" critique cluster (2024–25).** Distinguishes
vibe coding (agent output, no review loop) from AI-assisted
engineering (agent output inside a real review discipline), and names
the gap between output volume and verification capacity "verification
debt." *Directly reusable: a decision journal is a verification-debt
ledger, not just a record of reasoning.*

## 03 · Educational theory for the supervisor, not the operator

**Collins, Brown & Newman — cognitive apprenticeship (1987/91).** Six
methods for making expert thinking visible: modeling, coaching,
scaffolding, articulation, reflection, exploration. Already prompted
into an agent once ("MentorAI"), though the authors flag metacognitive
transparency as the hard part to get an LLM to enact reliably. *A
model for narrating "why this shape, not that one" as a first-class
agent output, not an afterthought.*

**Bjork — desirable difficulties (1994).** Difficulty that feels bad
in the moment can improve long-term retention — but only if the
learner already has the prerequisite background to work through it.
Without that footing, it's just frustration. *A direct caution against
"make the human read more" without regard for what they can actually
use.*

**The teach-back method (clinical origin).** Borrowed from healthcare
communication. The nearest AI-product cousin — an agent restating what
it understood before acting — is common; the stronger, more
Primer-like version, the *human* explaining it back, is not. *A
genuine gap, and a plausible feature in its own right.*

**Kapur — productive failure (ongoing).** Letting a learner attempt a
solution, even a wrong one, before being shown the answer primes
better uptake of the real explanation — Kapur reports roughly 73%
higher retention when the failure is properly scaffolded. Recent
papers (2026) operationalize this directly for AI tutoring. *The
closest prior art to a real feature — worth reading in full before
designing anything.*

## 04 · Friction calibrated by stakes *and* competence

**The gap.** Nearly all existing human-in-the-loop design — including
the Tiered Controllability Framework and most current "adaptive AI
oversight" writing — keys friction on task risk and action
reversibility alone. None of it varies engagement on the human's own
demonstrated competence in that specific domain.

That's a real opening, not just a citation gap: a taxonomy that scales
friction by *stakes × demonstrated competence* — inferred from how a
resident has actually engaged at past reviews, not from a one-time
self-report — would be original design work, not an implementation of
something already solved.

## 05 · Management literature — the human-to-human analog

**Grove — *High Output Management*.** A manager's output is what the
team produces because of the manager, not the manager's own hands-on
work. Staying grounded comes from recurring, low-cost information
touchpoints — the "breakfast factory," informal check-ins, skip-level
contact — not from re-executing the work personally. *The weekly audit
is this project's version of Grove's loop, sized for one report
instead of a team.*

**Marquet — *Turn the Ship Around!* / the Ladder of Leadership.**
Delegate authority in graduated rungs, tied explicitly to a report's
demonstrated competence and clarity of intent — never more than one
rung away from where they actually are. *The best human precedent for
a competence-gated authority taxonomy — worth mining directly.*

**Fournier — *The Manager's Path*; Larson — staff-engineer credibility
writing.** Both name the same failure mode directly: a leader's
technical credibility and judgment decay once they stop touching the
real work — and both treat this as a threat to decision quality, not a
matter of ego. *A leader who can't evaluate a technical claim can only
rubber-stamp it, never actually supervise it.*

**The "player-coach" pattern.** Practitioner consensus (LeadDev and
others): staying in the code at a small, fixed dose — one pull request
a quarter is the figure cited as sufficient for credibility — beats
both full disengagement and trying to keep pace hands-on.
Over-participating starves the team's growth and creates a single
point of failure. *A concrete personal habit, deliberately small,
rather than an open-ended "read more."*

**Mechanism convergence.** Skip-levels, code review, and Grove's
breakfast factory are all structured, low-frequency, high-signal
touchpoints — never continuous monitoring. *The clearest transferable
lesson: supervising something moving faster than you can track is
solved by periodic structured sampling, not real-time oversight.*

## 06 · Learning by doing: situated performance, not exposition

**Ericsson, Krampe & Tesch-Römer — deliberate practice (1993).**
Expertise comes from practice on specific, coach-designed tasks with
immediate feedback and repeated refinement — not passive exposure. *An
honest near-miss: Ericsson's classic setting is a teacher designing
drills around one student's specific weaknesses over years. Castle
Turing can offer real tasks inside real work, not constructed drills —
closer to the entry below than to this one.*

**Lave & Wenger — *Situated Learning: Legitimate Peripheral
Participation* (1991).** Learning happens by doing real, low-stakes,
peripheral slices of the actual work inside a community of practice,
graduating toward full participation — not simulation, not
explanation. *The single best-fitting theory for what's being
proposed: not explaining Nix, but handing over small real pieces of
the actual work and widening scope over time.*

**Wood, Bruner & Ross — scaffolding, the guided-practice half of
Vygotsky's ZPD (1976).** Scaffolding means guided practice, not
explanation: the real goal is broken into manageable steps and support
fades as competence grows. *Confirms doing and explaining are
genuinely separable mechanisms, distinct from the modeling/narration
side already covered under cognitive apprenticeship.*

**Not yet built.** AI coaching-agent products found skew toward
real-time guidance during a task — closer to this cluster than to pure
narration. But none hand the user a bounded slice of a *real system*,
not a simulated exercise, and widen scope as demonstrated competence
grows. That specific pattern is a genuine design opening, not
something to borrow.

## 07 · Automation complacency and behavioral over-reliance signals

**Parasuraman & Manzey — "Complacency and Bias in Human Use of
Automation" (2010).** Complacency arises specifically under multi-task
load, when attention gets diverted from the automated task —
historically measured by missed-fault-detection rates and monitoring
dwell-time in simulator studies. *The mechanism: it's an
attention-allocation failure, not a knowledge failure, which is a
different lever than the education-focused material above.*

**"Habituation at the Gate: Rising Approval and Declining Scrutiny in
Human Review of AI Agent Code" (2026).** Real telemetry, 400 repeat
reviewers across 11,429 reviews: approval rates rose 14.5 points
across reviewer-experience deciles, review latency rose 3.5×,
inline-comment effort fell 22%, and agent pull requests grew 51%
larger over the same period — reviewers spent more wall-clock time but
did less actual inspection as habituation set in. *Direct answer to
the acceptance-rate question: latency-vs-diff-size and comment density
are real behavioral signals of rubber-stamping, not just aggregate
acceptance rate. Recent enough (2026) that it's worth reading directly
rather than taking secondhand.*

**"Approval Fatigue" — Encyclopedia of Agentic Coding Patterns
(practitioner).** Practitioner-level naming of the same failure mode,
with a stated mitigation: keep pull requests small, since reviewer
engagement is one of the strongest predictors a PR gets a real review
at all. *Confirms this is a recognized live problem in the field, not
just an academic finding.*

## 08 · Adaptive autonomy from an explicit competence model

**Bradshaw, Feltovich et al. — adjustable autonomy / KAoS (2003–).**
Foundational human-agent-teaming work: authority and constraints
transfer dynamically between human and automation to hold trust steady
while maximizing useful autonomy — mostly space-robotics and
multi-agent-teaming contexts. *Keys off task/trust context, not a
persistent, per-individual, per-domain competence profile carried
across sessions.*

**Adaptive Oversight Calibration Model (2025–26).** Frames oversight
as a continuous function of task criticality, AI competency, human
cognitive capacity, and trust dynamics, rather than a static policy.
*Closer, but "human cognitive capacity" here is generic and
workload-based, not a persistent model of one specific user's
demonstrated competence in one specific domain.*

**Risk-contingent autonomy.** Delegates control only when risk is
detected, shown to raise perceived control and reduce decision fatigue
versus constant-approval regimes. *Still keyed on risk, not
competence.*

**Verdict.** No system found — in HCI, human-robot/adjustable-autonomy,
or LLM-agent literature — ties required oversight to an explicit,
persistent, per-domain model of one specific user's demonstrated
competence, as opposed to generic workload modeling or flat risk
gating. The closest real precedent is human, not software: Marquet's
Ladder of Leadership, above. Building this for Castle Turing would be
original design work.

## Design patterns already shipped or proposed

- Scheduled, periodic disengagement from AI assistance ("Copilot-free
  Fridays") as a team-level anti-atrophy ritual
- Agent restates what it understood before acting — a weak teach-back
  precursor, already common
- A prompted cognitive-apprenticeship agent that narrates expert
  reasoning, not just output ("MentorAI")
- Trust-calibration nudges that fire when reliance behavior looks
  off — approvals arriving too fast, for instance
- Marquet's Ladder of Leadership — graduated authority tied to
  demonstrated competence and clarity, one rung at a time
- A fixed, small dose of hands-on participation ("one pull request a
  quarter") as a credibility-maintenance ritual, not full engagement

## Flagged and set aside

**Safety-framed, not augmentation-framed.** The Tiered Controllability
Framework and most 2025 "adaptive AI oversight" industry writing
(Galileo, Illumination Works, and similar) are risk- and
reversibility-gated guardrail frameworks aimed at preventing bad
autonomous actions. Genuinely useful as an input to a reversibility
axis — but they don't address competence-building or augmentation at
all, and shouldn't be cited as though they solve the Primer-style goal
of making the human more capable.

---

*Compiled from two background research passes · first pass: five
threads requested, a fifth (management literature) added mid-run ·
second pass: learning-by-doing, complacency signals, and
adaptive-autonomy prior art, added after the first draft's
altitude-only framing was corrected.*
