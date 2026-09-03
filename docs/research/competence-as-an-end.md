# Competence as an End in Itself

*Castle Turing · Research Review · 17 August 2026 · 62 sources · 5
questions · 4 claims.*

*What the evidence says about building a system that does the work
**and** builds the resident — and where the founding documents are
currently wrong. Originally rendered as a private Claude artifact;
transcribed to the repo 2026-09-03 so the record travels with the
project. The compressed, decision-relevant versions live in
`docs/backlog/` — this is the full report behind them.*

## The claim under examination, and how to read the citations

The vision holds that Castle Turing exists to elevate its resident,
the way the Primer exists to elevate Nell. This review asks whether
the evidence supports that — and pressure-tests four specific claims
the founding documents make. It deliberately does not redo the
defensive sweep (Bainbridge, Casner, Ebbatson, Buçinca), though the
anchor citations are included so it stands alone.

Every citation carries a provenance marker. The web-search quota was
exhausted before this review began, so verification went through
Crossref, OpenAlex, Europe PMC and PMC full text rather than general
search. That worked well for confirming named papers and poorly for
*discovering* critique literature. Where that shows, it is flagged
rather than papered over.

**Legend:**

- **[V]** — Bibliographic record verified this session. Where the
  abstract or the numbers were also retrieved, the text says so.
- **[V-META]** — Record verified — authors, venue, volume, pages, DOI
  are right — but the abstract could not be retrieved. Any figures
  quoted are from training memory.
- **[R]** — Recalled from training, not verified. A lead to check, not
  a citation to rely on.

Contents: 1. The finding that reframes the problem · 2. Verdicts on
the four claims · 3. What actually produces durable capability ·
4. Are doing-systems and teaching-systems in conflict · 5. Is
competence intrinsically valuable · 6. Does the rollback claim
survive · 7. What is contingent on today's models · 8. The four
claims, in detail · 9. What an evidence-based principle would say ·
10. Sources · 11. Known gaps.

## 01 · The Bastani result is not a fact about AI. It is a thirty-year-old dissociation.

Before anything else: performance during training is a poor, and
sometimes inverted, proxy for learning. Conditions that make practice
feel fluent often *reduce* durable retention; conditions that make
practice effortful often increase it. That is Soderstrom & Bjork's
integrative review, 2015 [V].

Now the verified Bastani abstract, retrieved verbatim from Europe PMC:

> …having GPT-4 access while solving problems significantly improves
> performance (48% improvement in grades for GPT Base and 127% for GPT
> Tutor). However, we additionally find that when access is
> subsequently taken away, students actually perform worse than those
> who never had access (17% reduction in grades for GPT Base)…
> Without guardrails, students attempt to use GPT-4 as a "crutch"
> during practice problem sessions, and subsequently perform worse on
> their own.

**+48% / −17%** — Assisted performance up, unaided performance down,
in the same experiment. That is the learning/performance dissociation
with a dollar figure on it — and it means **the mechanism is not
model-specific.**

**On the correction notice.** There is a correction — *PNAS* 122(34)
[V]. Its full text was retrieved: it corrects **Osbert Bastani's
institutional affiliation only**, described as a production error. No
data, analysis or conclusion was corrected. The result stands as
published.

**One nuance the project has been understating.** GPT Tutor did not
merely eliminate the harm at parity. It produced a *larger*
assisted-performance gain than GPT Base — 127% against 48% — *and*
mitigated the learning harm. So the frontier is **not strict**: a
Pareto improvement was available and prompt engineering found it. What
guardrails did not do is beat the no-AI control on unaided
performance.

The correct summary: *guardrails bought back the learning loss and
improved assisted output; they did not produce learning gains over
no-AI instruction.* That distinction changes the first claim's
verdict.

## 02 · Verdicts on the four claims

Detail and counter-evidence for each is in section 08. This is the
scan.

- **C1 — A doing-system can also build capability: MIXED · contradicted
  as stated.** Supported only in a weaker, specific form. No single
  implicit policy can serve both objectives across a competence
  range — expertise reversal alone refutes it. Mode must be explicit,
  per-domain, and legible.
- **C2 — "Doing, not being shown" is the right default: MIXED · right
  mechanism, wrong starting point.** For a novice, unguided doing is
  one of the reliably worse options. The supported sequence is study →
  complete → solve. The vision's escalation mechanism is exactly
  right; it starts at the wrong end of the ramp.
- **C3 — Rollback makes real tasks safe enough to substitute for
  practice: MIXED, LEANING CONTRADICTED.** The conclusion survives;
  the reasoning doesn't, and the scope is overclaimed. Fidelity
  doesn't drive transfer, so "real" was never the scarce ingredient.
  And rollback covers system state, not sent mail.
- **C4 — Competence is worth supporting for its own sake: SUPPORTED AS
  A VALUE · not establishable as a finding.** No evidence can license
  a value claim. What it does license: mastery orientation predicts
  engagement, not achievement. Which is what "for its own sake" looks
  like in data.

## 03 · What actually produces durable capability

### Deliberate practice is contested, and the contest matters here specifically

The original claim is Ericsson, Krampe & Tesch-Römer 1993 [V-META].
The meta-analytic pushback is Macnamara, Hambrick & Oswald 2014 [V,
figures verified], and its domain gradient is the single most
important number in this section.

| Domain | Variance in performance explained |
|---|---|
| Games | 26% |
| Music | 21% |
| Sports | 18% |
| **Education** | **4%** |
| **Professions** | **<1%** |

The domains where structured practice explains a lot have stable
rules, immediate unambiguous feedback, and fixed task structure. The
domains where it explains essentially nothing are open-ended
professional work. **A personal computing environment's growth
domains — managing correspondence, deciding what deserves attention,
configuring one's own tools — sit at the professions end.** Whatever
principle gets written should not assume games-end dynamics.

A corrigendum exists — *Psychological Science* 29(7), 2018 [V-META],
existence verified, contents not retrieved. Check it before quoting
those figures anywhere published. The direct replication (Macnamara &
Maitra 2019 [V]) reproduced the relationship in direction, at an
effect size "considerably smaller than the original study's."

What survives: practice is necessary and insufficient. Both camps
overstate — the Macnamara figures are correlational variance
explained, not the causal effect of a training intervention, and range
restriction in expert samples biases them downward. **Do not build a
principle on hours of practice. Build it on the mechanisms below,
which replicate far better.**

### The robust mechanisms

**Retrieval practice.** The most robust finding in this entire review.
Roediger & Karpicke 2006 [V-META]; Rowland 2014 [V] — free-recall
tests yield larger benefits than recognition, i.e. *retrieval
difficulty drives the effect*; Adesope et al. 2017 [V] — practice
testing beat restudying and every other comparison condition. Effect
sizes around g ≈ 0.5 are [R]; the direction is verified. **It is also
the finding an agentic system most reliably destroys: every task the
agent completes is a retrieval opportunity the resident did not
take.**

**Spacing** — Cepeda et al. 2006 [V-META]. Robust and large; the
optimal gap scales with the retention interval you want [R].

**Desirable difficulties** — the umbrella construct. Cite Soderstrom &
Bjork 2015 [V] rather than the canonical Bjork & Bjork 2011 chapter,
which is not in Crossref and could not be verified [R]; the
peer-reviewed paper makes the same argument more rigorously.

**Interleaving — real but heavily moderated, and over-generalised in
the popular literature.** Brunmair & Richter 2019 [V]: stronger
effects for material with high between-category similarity, low
within-category similarity, and higher complexity; the authors
explicitly caution against interleaving for expository texts. It is an
inductive-category-learning effect. Flag it as domain-bound.

**The discipline worth importing:** Dunlosky et al. 2013 [V-META]
rated ten learning techniques. Their high-utility list is two items
long: **practice testing and distributed practice.** Everything else
came in moderate or low.

### The transfer ceiling

Barnett & Ceci 2002 [V-META]: far transfer is rare and context-bound.
**There is no such thing as growing "general competence."** A
principle must name domains — which the vision's per-domain framing
already does, and is one place the founding document is on solid
ground.

## 04 · Are doing-systems and teaching-systems in structural conflict?

### Two sigma does not replicate. The real band is 0.4–0.8.

Bloom's 2 Sigma paper [V-META] is the source of the expectation.
VanLehn 2011 [V-META] is the standard correction — but it is paywalled
and its abstract is elided from every reachable metadata source. Its
headline figures (human tutoring d ≈ 0.79, step-based ITS d ≈ 0.76,
answer-based d ≈ 0.31) are [R] and should be verified before
publication.

The argument does not depend on that recall, because an independent
source was verified in full: **0.66 SD** — median effect size across
50 controlled evaluations of intelligent tutoring systems. Kulik &
Fletcher 2016 [V, numbers verified]. Effects varied substantially
between local and standardised tests, and shrank further with
non-conventional controls or flawed implementation.

**So: ~0.66, not 2.0.** Two sigma is a target from a small set of
mastery-learning studies the subsequent literature has not reproduced.
Any document citing the Primer should not import two-sigma
expectations along with it.

### The assistance dilemma — the formal statement of the tension

Koedinger & Aleven 2007 [V-META] — 608 citations, and the abstract is
elided from Crossref, OpenAlex and Semantic Scholar with no reachable
open-access copy. The characterisation below is recalled [R], though
the citation itself is solid.

Instructional science holds two large, well-supported, opposed bodies
of evidence. *Assistance-giving* effects — worked examples, direct
instruction, immediate feedback — each have solid support.
*Assistance-withholding* effects — problem-solving practice, testing,
delayed feedback, generation — also each have solid support. The
dilemma is that no theory said **when to give and when to withhold.**

That framing is nearly twenty years old and substantially still open.
Koedinger, Booth & Klahr 2013 [V-META] argues the design space of
instructional-choice combinations is too large to derive analytically
and must be searched empirically. And the KLI framework (Koedinger,
Corbett & Perfetti 2012 [V]) shows different knowledge types demand
*different* instructional treatments — so a single global assistance
policy is wrong by construction.

### The resolution the evidence supports: a trajectory, not a setting

This is the most actionable cluster in the review, and it cuts against
the vision's current default.

**Expertise reversal** — Kalyuga, Ayres, Chandler & Sweller 2003
[V-META]. Instructional techniques that help novices become
ineffective or *actively harmful* as expertise grows, and the
converse. The optimal assistance level is a function of current
competence and **changes sign along the way.**

**Study → complete → solve** — Renkl & Atkinson 2003 [V-META];
Atkinson, Renkl & Merrill 2003 [V-META]. Fading worked steps
*gradually*, with self-explanation prompts, outperforms both pure
example study and pure problem solving.

**Self-explanation is the active ingredient** — Aleven & Koedinger
2002 [V-META]. Note the title: learning by doing *and explaining*.
Doing alone was not the intervention.

**Where this bites the vision:** The founding clause says the default
posture is "doing, not being shown." The expertise-reversal and fading
literatures say the correct posture for a **novice** is *being shown
first, then completing partial work, then doing* — and that jumping a
novice straight to unguided doing is one of the reliably worse
options. The vision's *mechanism* — scope widening only as
demonstrated performance earns it — is exactly right and matches the
fading literature. Its *starting point* is set at the wrong end of the
ramp.

### Is the "AI can teach" evidence any good? Currently there is no aggregate evidence at all.

**The headline meta-analysis was retracted.** Wang & Fan, "The effect
of ChatGPT on students' learning performance, learning perception, and
higher-order thinking," *Humanities and Social Sciences
Communications* 12(1), 2025 — **RETRACTED.** The retraction note
published 22 April 2026 [V] records that concerns were originally
raised by Magnus Ingebrigtsen and Marko Lukic. The note's full text
was behind a paywall redirect, so the stated grounds are unverified.
And the statistical critique: Bartoš, Martinková & Wagenmakers 2025
[V], verbatim from the abstract — the effects "greatly diminish once
publication bias is accounted for, and the evidence in favor of the
benefits disappears." **Treat every aggregate claim that AI improves
learning as currently unsupported.**

### The strongest apparent counterexample, and why it isn't one

Kestin, Miller, Klales, Milbourne & Ponti 2025 [V, full text read].
Harvard undergraduate physics, N = 194, randomised at the
peer-instruction group level. **0.63–1.3 SD** — AI tutor over in-class
active learning; 0.63 by linear regression, which the authors say
underestimates due to ceiling effects, and 0.73–1.3 by quantile
regression. Median time 49 minutes against roughly 60. More learning
in less time.

**But: pre-test immediately before, post-test immediately after each
lesson. There was no delayed retention test.** Verified from the full
text. The authors' own limitation is that the approach suits the
foundational levels of Bloom's taxonomy, not complex synthesis.

This does not contradict Bastani, because it measures a different
construct at a different time. Kestin measured immediate post-lesson
performance; Bastani measured unaided performance after access was
withdrawn. Soderstrom & Bjork's whole point is that these routinely
dissociate — and Bastani observed exactly that dissociation within one
experiment. **Kestin's design is structurally incapable of detecting
the Bastani effect.**

### Verdict

The objectives are **partially, not strictly, opposed.**

- **Within a single act, they conflict.** Every step the agent
  completes is a step the resident did not retrieve, and expertise
  reversal guarantees no single assistance level is right for both
  output and learning across a competence range.
- **Across a system, they need not.** GPT Tutor is the existence
  proof — better assisted output *and* preserved learning. It just did
  not exceed the no-AI control on learning.
- **What the literature does not support** is a system that serves
  both objectives *implicitly*. Everything that worked — GPT Tutor's
  prompts, faded worked examples, self-explanation — worked by making
  a deliberate, visible choice about how much to withhold.

**Mode must be explicit, per-domain, and legible to the resident.** A
system that silently interpolates will land on the
completion-optimised end, because that is what its objective function
rewards.

## 05 · Is competence intrinsically valuable, with evidence behind it?

White 1959 [V-META] is the origin of "effectance motivation" — that
organisms seek effective interaction with their environment for its
own sake, not as a derivative of drive reduction. It is the
intellectual ancestor of the resident's framing. It is **theory, not
evidence**, and should be cited as such.

### Self-determination theory: genuinely strong, genuinely oversold

Ryan & Deci 2000 [V-META]. The descriptive association between need
satisfaction and wellbeing is one of the most replicated findings in
motivation psychology and holds cross-culturally (Chen et al. 2015
[V-META]).

**Small · heterogeneous.** The *causal* evidence is modest. Ntoumanis
et al. 2021 [V, verified]: 73 intervention studies; small-to-medium
changes in SDT constructs at end of intervention; **small** positive
changes in physical and psychological health at follow-up. The
authors' own word for the effects is "modest." The honest causal
statement: *deliberately supporting psychological needs measurably
improves wellbeing, by a small amount.* Not nothing. Not
transformative.

The "undermining effect" sub-literature is contested — Deci, Koestner
& Ryan 1999 [V-META] was published in the same issue as a critical
comment from Lepper, Henderlong & Gingras [V-META]. The theory's own
leadership acknowledges open critical questions (Vansteenkiste, Ryan &
Soenens 2020 [V-META]).

**Declared gap:** Several targeted attempts to surface the *external*
critique literature on SDT — falsifiability, near-total reliance on
cross-sectional self-report, construct proliferation — failed through
metadata APIs alone. The assessment that SDT is hard to falsify and
that its measurement base is overwhelmingly self-report is **a read,
not a cited finding.** Anyone relying on this section should search
that literature properly.

### Mastery vs performance goals — the most useful, and most damaging, finding

Hulleman, Schrager, Bodmann & Harackiewicz 2010 [V, numbers verified].
243 correlational studies, N = 91,087.

**r ≈ .05** — the correlation between mastery-approach goals and
performance outcomes. Essentially null. Worse for the field:
performance-approach goals correlated **+.14** when scales used
normatively-referenced items and **−.14** when they used
appearance/evaluative items. The same named construct produces
opposite signs depending on item wording.

**Read this carefully, because it cuts both ways.** It is bad news for
anyone claiming mastery orientation improves achievement — it doesn't,
measurably. But mastery goals do reliably predict interest, enjoyment
and persistence [R — the standard reading; the null-on-achievement
half was verified, this half was not].

That is a *supportive* result for the resident's actual question,
correctly stated: **pursuing competence for its own sake is not
justified by producing better outcomes. It is justified by producing
sustained voluntary engagement.** Which is precisely what "for its own
sake" means.

Two supporting notes: intrinsic motivation does predict performance
incrementally to incentives (Cerasoli, Nicklin & Ford 2014 [V-META]),
more strongly for quality than quantity [R]. And flow is the weakest
evidentiary leg — Fong, Zaleski & Leach 2015 [V-META] finds
challenge–skill balance relates to flow only modestly, it is measured
almost entirely by self-report, and the popular framing runs well
ahead of the measurement literature. **Do not make flow
load-bearing.**

### Verdict — the honest answer

**No empirical literature can establish that competence is
intrinsically valuable.** That is a category error. "Intrinsically
valuable" is a claim about what is worth wanting; psychology reports
what people pursue, what predicts what, and what interventions move.
Asking the evidence to license the value is asking the wrong question
of it — and the attempt is what makes such statements sound
embarrassed. **The value is a choice. The evidence constrains what you
may promise as a consequence of the choice.**

What the evidence does license, precisely:

1. People pursue competence absent external reward — White
   theoretically, SDT empirically, though largely by self-report.
2. Competence experiences robustly predict wellbeing, interest and
   persistence, across cultures.
3. Deliberately supporting those experiences causally improves
   wellbeing by a **small** amount.
4. Orienting toward mastery predicts sustained engagement but **not**
   better achievement.

**What it does not license:** the claim that supporting competence
will make the resident more effective, more productive, or better at
anything. If the principle promises that, the evidence contradicts it.

**The robustness argument.** There is one further argument for
competence-as-an-end that is not psychological at all, and in this
project's context it is the strongest available: **competence is the
only asset that survives the system being wrong, being unavailable, or
going away.** Every other capability the resident has is mediated by
an agent that can fail, hallucinate, lose funding, or change its
terms. That is an argument from robustness, and Bastani's design is
literally a measurement of it — *what happens when access is taken
away.* It is available even to someone who thinks competence has no
intrinsic value whatsoever. Build the principle's spine from it.

## 06 · Does the rollback claim survive?

The clause asserts rollback is "the safe place to fail that the Primer
needed fiction for" — that reversibility lets real tasks substitute
for simulated practice. The claim bundles several propositions. They
separate cleanly, and they do not all survive.

### "Real beats simulated" — supported, but for the wrong reason

Cook et al. 2011 [V, numbers verified]: 609 studies, 35,226 trainees.
Pooled effects against no intervention — knowledge 1.20, skills
1.09–1.14, behaviours 0.81, patient outcomes 0.50. Those are large,
but the comparison is against nothing; the comparison against other
instruction is much smaller [R].

**Fidelity ≉ transfer.** Norman, Dore & Grierson 2012 [V-META]: how
realistic practice is has minimal relationship to how well it
transfers. "Real" was never the scarce ingredient. The Primer did not
need fiction because simulation is pedagogically deficient — it needed
fiction for narrative reasons. Rollback is therefore not required to
make practice work.

### What rollback actually buys: error permissiveness — well supported

Keith & Frese 2008 [V, numbers verified]. 24 studies, N = 2,183. Error
management training vs. error-avoidant training: overall d = 0.44;
post-training transfer d = 0.56; analogical transfer (similar tasks)
d = 0.44; **adaptive transfer (structurally novel tasks) d = 0.80.**

Mechanism in Keith & Frese 2005 [V-META]: emotion control and
metacognition as mediators. This is genuine support for "a safe place
to fail" — with a sharp caveat. Error management training works by
actively encouraging errors and framing them as informative, not by
merely making them costless. Rollback removes the cost. It does not
supply the framing. Two separate design obligations, only one of which
is a filesystem property.

Note the largest effect is on adaptive transfer — novel, structurally
different situations. That is the profile of a resident's actual
future problems, and it is a point in the clause's favour.

### Productive failure — supported, with a condition the vision omits

Sinha & Kapur 2021 [V, all numbers verified]. 53 studies, 166
comparisons. **g = 0.36 [0.20, 0.51]** for
problem-solving-then-instruction over instruction-then-problem-solving,
rising to 0.37–0.58 at high implementation fidelity, and 0.87 after
correcting for publication bias. But the reversals matter enormously:
effects reversed in favour of instruction-first for younger learners,
and reversed for domain-general skills — and "domain-general" fairly
describes much of what a resident wants to grow in around a personal
computing environment.

**The single most actionable finding in this review:** it is "problem
solving followed by instruction." Productive failure is productive
because of the consolidating instruction that follows it. A system
that hands over a bounded task, lets the resident fail, and rolls
back — without the subsequent consolidation — has implemented failure,
not productive failure. The rollback is the cheap half. The debrief is
the half that carries the effect. The medical simulation literature
says the same independently: Cheng et al. 2014 [V-META] — simulation
without debrief is a weaker intervention.

### Does psychological safety require reversibility? No — it's a different construct.

Edmondson 1999 [V-META]: psychological safety is about interpersonal
risk — the belief that one will not be humiliated or penalised for
speaking up, asking questions, or admitting error. It is about how
failure is witnessed and responded to, not whether its consequences
can be undone.

Rollback does not supply psychological safety. In a single-resident
system the relevant witness is the agent itself. A system with perfect
rollback that visibly logs, summarises or references the resident's
fumbles can destroy psychological safety while satisfying every
reversibility guarantee. Conversely an environment can be
psychologically safe with irreversible consequences, if failure is
treated as information. This is a real design surface the current
clause does not name.

### The unexamined premise

Does consequence-free work teach as well as consequential work? Direct
evidence is thin and none of it settles the question. For the claim:
Norman et al. — fidelity doesn't drive transfer, so consequence
probably isn't the mechanism. Against: the desirable-difficulties
literature implies what matters is effort actually invested, and
stakes plausibly drive effort allocation. If rollback signals "this
doesn't really matter," the resident may not engage the retrieval
processes that produce the learning.

This is the review's clearest evidence gap and the thing most worth
testing in-house. It is also cheap to test on a population of one:
alternate real-consequence and rollback-protected handovers in the
same domain, then compare unaided performance later.

### The premise that is straightforwardly false on its own terms

Rollback covers system state. It does not cover the resident's actual
domain. Castle Turing triages mail and defends attention. A sent email
cannot be rolled back. Neither can a missed deadline, a decision
communicated to a colleague, an hour of attention, or a relationship.
NixOS generations roll back configuration; they do not roll back
consequences in the world.

Rollback genuinely makes self-modification of the system a safe place
to fail — a real and unusual affordance, worth claiming. It does not
make the resident's correspondence and commitments a safe place to
fail. Those are exactly the domains the vision is most interested in.

## 07 · What is contingent on today's models

### Survives a large capability jump unchanged

These are facts about human memory, motivation and attention. No model
improvement touches them.

- Retrieval practice, spacing, desirable difficulties. A model that
  could perfectly diagnose the resident's knowledge state still cannot
  retrieve on their behalf and have it count. The requirement that the
  human do the effortful thing is not a limitation of current AI; it
  is the mechanism. This is the sharpest boundary in the review.
- The learning/performance dissociation. Better models make assisted
  performance higher, which widens the gap between the two measures
  and makes the dissociation harder to notice, not easier.
- Expertise reversal — a property of learners.
- Far-transfer limits.
- Error-management benefits, and the requirement for consolidating
  instruction.
- Psychological safety — arguably more relevant with a more capable
  agent, since a system that reasons well about the resident can also
  be experienced as judging them.
- Skill decay and recency effects.

### Needs re-testing after a capability jump

Everything with an effect size attached to a specific AI system.

- Bastani's −17%. The mechanism — crutch use displacing retrieval
  practice — is general. The magnitude is GPT-4-era behaviour, one
  interface, one subject, one population, one country.
- Kestin's 0.63–1.3 SD — same caveat, plus no delayed post-test.
- The "guardrail ceiling" — that guarded AI reached only parity with
  control. This is a property of prompt-engineered GPT-4 in 2024–25,
  not a law of nature. It is the number most likely to move, and the
  one the resident most wants to move. Treating it as a ceiling to
  argue with rather than a settled result is the correct posture — the
  evidence base is one study.
- All AI-tutor meta-analytic estimates — there currently isn't a
  trustworthy one.
- Cognitive-offloading magnitudes (Risko & Gilbert 2016 [V-META]; Lee
  et al. CHI 2025 [V-META]). Offloading propensity scales with
  perceived tool reliability, so better models increase offloading —
  direction predictable, magnitude not.

### Already about the machine, not the person

**The one that moves:** the assistance dilemma's optimal policy. It
has stayed open partly because no instructional system could estimate
a learner's momentary competence well enough to dose assistance
correctly. A model that could reliably infer the resident's current
competence per-domain, in real time, would genuinely move this
frontier. It is the one place where a capability jump changes a
substantive conclusion in this review rather than just a number.

The feasibility of fading: faded worked examples require knowing when
to fade, which currently needs a fixed schedule or explicit
assessment. A sufficiently capable model could fade continuously from
observed behaviour — close to what "scope widening as demonstrated
performance earns it" describes, and more achievable now than when
Koedinger & Aleven wrote.

The measurement problem: Bastani could only detect harm by withdrawing
access and testing. A system that can't withdraw access can't measure
learning. Whether a more capable model could estimate the resident's
unaided competence without withdrawing support is open, genuinely
model-contingent, and would be the most valuable single capability for
this project.

## 08 · The four claims, in detail

### C1 — A system whose purpose is to do the work can also build the resident's capability

**MIXED — CONTRADICTED AS STATED; SUPPORTED IN A WEAKER FORM.**

*Strongest evidence against:* Bastani et al. 2025 [V] is a direct
randomised test with ~1,000 subjects, and the completion-optimised
interface produced a 17% reduction in unaided performance versus never
having had access. Backed theoretically by Soderstrom & Bjork:
optimising the performance signal is a known way to damage the
learning signal. Koedinger & Aleven's dilemma and Kalyuga's expertise
reversal together imply no single assistance policy is simultaneously
optimal for output and learning across a competence range.

*Strongest evidence for:* GPT Tutor achieved higher assisted
performance than GPT Base (127% vs 48%) and mitigated the learning
harm. The frontier is not strict; a Pareto improvement existed and
prompt engineering found it. Kulik & Fletcher's 0.66 median shows
computational systems can teach at real effect sizes.

*What we'd have to believe for the choice to be wrong:* That a single,
implicit, always-on interaction policy can be simultaneously optimal
for output quality and for learning. Expertise reversal alone refutes
this: the right policy for a novice and for a near-expert differ in
sign, so no fixed policy is right for both, let alone both objectives
at once.

*Design conclusion:* The system can serve both objectives — but not in
the same act, and not implicitly. Mode must be explicit, per-domain
and legible. The unmarked default should be "do the work"; growth
domains are opted into. That is what the vision already says, and it
is right. The gap is that it doesn't say what happens inside a growth
domain.

### C2 — "Doing, not being shown" is the right default for a domain someone wants to grow in

**MIXED — RIGHT MECHANISM, WRONG END OF THE RAMP.**

*Strongest evidence for:* Sinha & Kapur 2021: g = 0.36 [0.20, 0.51],
rising to 0.87 after publication-bias correction. Keith & Frese 2008:
d = 0.44 overall, d = 0.80 for adaptive transfer. Plus the entire
retrieval-practice literature — doing generates retrieval; watching
does not.

*Strongest evidence against, as a default:* Expertise reversal and the
worked-example/fading literature: for a genuine novice, unguided doing
is one of the reliably worse options, and the supported sequence is
study → complete → solve with self-explanation prompts throughout.
Sinha & Kapur's own moderators reverse the advantage for younger
learners and for domain-general skills. Aleven & Koedinger found the
effective intervention was doing and explaining, not doing alone.

*What we'd have to believe for the choice to be wrong:* Either (a) the
resident is a near-novice in the domain — in which case handing over a
bounded task with light coaching is worse than showing worked examples
first; or (b) no consolidating instruction follows the attempt — in
which case you get failure, not productive failure, and the whole
effect evaporates. Both are likely to be true in practice unless the
design specifically prevents them.

*Design conclusion:* Replace "doing, not being shown" with "doing
before being shown, followed by being shown." The vision's escalation
mechanism is exactly the fading trajectory the literature supports. It
needs to start further up the assistance ramp and make consolidation
mandatory rather than implicit.

### C3 — Rollback makes real tasks safe enough to substitute for simulated practice

**MIXED, LEANING CONTRADICTED — CONCLUSION FINE, REASONING ISN'T,
SCOPE OVERCLAIMED.**

*Against the reasoning:* Norman, Dore & Grierson 2012: fidelity has
minimal relationship to transfer, so "real" was never the scarce
ingredient and rollback isn't buying what the clause says it's buying.

*For a different, better justification:* Keith & Frese:
error-permissive practice genuinely beats error-avoidant practice,
most strongly for adaptive transfer. Rollback creates the conditions
for that. That is a real and defensible claim — and it is not the one
the clause makes.

*Three things rollback does not deliver, which the clause implies it
does:* consolidating instruction (the effect lives in the instruction
that follows failure, not in the failure); psychological safety
(that's interpersonal risk, not reversibility — a perfectly reversible
system that visibly records fumbles is not psychologically safe); and
coverage of the actual domain (sent mail, spent attention,
communicated decisions and relationships are not in any generation).

*Design conclusion:* Keep rollback; restate what it's for. It is an
error-permissiveness affordance, not a reality-substitution argument.
And it is honestly claimable only for the domain it covers:
self-modification of the system. That is still a genuinely unusual
thing to be able to offer, and the vision undersells it by
over-generalising it.

### C4 — Competence is worth supporting for its own sake, not merely as a gate on authority

**SUPPORTED AS A VALUE COMMITMENT — NOT ESTABLISHED, AND NOT
ESTABLISHABLE, EMPIRICALLY.**

The full argument is in section 05. The short version: stop trying to
get the literature to authorise the value — it can't, and the attempt
is what makes such statements sound embarrassed. State it as a choice,
then claim only the consequences the evidence supports: engagement,
persistence, modest wellbeing gains, and robustness against the
system's own failure. Do not claim it makes the resident more
effective. Hulleman's r ≈ .05 contradicts that directly, and a
principle that promises it will be falsified by the resident's own
experience.

*What we'd have to believe for the choice to be wrong:* That the
resident's stated preference for growth is one they'd revise on
reflection — the evidence gives no purchase on this, which is the
point; it is the resident's call. Or that competence support costs
more in foregone output than the engagement and robustness gains are
worth. That second one is empirically tractable, and Castle Turing is
unusually well-placed to measure it on a population of one.

## 09 · What a principle would have to say, if it were evidence-based rather than aspirational

Each of these is traceable to a verified finding above.

1. **Name the value as a value; promise only the consequences the
   evidence supports.** Say that this system exists to elevate its
   resident, and that this is a choice, not a finding. Then claim
   engagement, persistence, modest wellbeing gains, and robustness. Do
   not claim it makes the resident more effective — Hulleman (r ≈ .05)
   contradicts it.
2. **Growth domains are explicitly declared, per domain, and never
   inferred.** Far transfer is rare; there is no general competence to
   grow. The default in undeclared domains is: do the work. This is
   the Principle 01 split done properly — public mechanism is the mode
   machinery and the fading policy; private configuration is which
   domains the resident declared.
3. **Inside a growth domain the posture is a trajectory, not a
   setting — and it starts higher than "doing."** Worked example →
   partial completion → unaided attempt → consolidation. Fade as
   demonstrated competence rises, because the correct assistance level
   reverses sign as expertise grows.
4. **Failure without consolidation is not productive failure. The
   debrief is mandatory.** Sinha & Kapur's g = 0.36–0.87 lives
   entirely in the instruction that follows the failed attempt. A
   principle that authorises handing over a task and rolling back the
   mess, without requiring the system to then explain what happened,
   has implemented the cheap half. If only one thing from this review
   survives, make it this one.
5. **Every completed task is a retrieval opportunity spent. Budget
   them.** Retrieval practice is the most robust finding here and the
   one an agentic system most efficiently destroys. In a growth domain
   the system should be spending retrieval opportunities on the
   resident — and should say so, since the resident will experience
   this as the system being slower and more annoying than it could be.
6. **Assisted performance is not evidence of learning. Measuring
   learning requires withdrawing support.** Bastani could only detect
   harm by taking access away and testing. A principle should commit
   the system to periodically operating unassisted in declared growth
   domains — otherwise it has no measurement, and its "demonstrated
   performance" gate is measuring the wrong variable. This is
   uncomfortable, and it is the honest consequence of the evidence.
7. **Rollback is an error-permissiveness affordance, scoped to system
   state.** The supported claim is Keith & Frese's. The unsupported
   claim is that reversibility is what makes real practice work. And
   the scope is narrower than written — claim self-modification as the
   safe-to-fail domain. Precision makes it stronger, not weaker.
8. **Add the obligation rollback doesn't cover: psychological
   safety.** Safety is about how failure is witnessed. In a
   one-resident system the witness is the agent. A principle should
   constrain how the system records, summarises and refers back to the
   resident's failures. Perfect rollback plus a system that remembers
   every fumble out loud is not a safe place to fail.
9. **Mark what's model-contingent, in the principle text itself.** The
   human-learning findings hold regardless of capability. The
   AI-specific magnitudes are 2024–25 measurements and should be
   re-tested, not enshrined. No capability jump removes the
   requirement that the resident do the effortful thing.
10. **Declare the open question rather than assuming it away.**
    Nothing found tests whether consequence-free real work teaches as
    well as consequential real work. That is the load-bearing
    empirical assumption under the rollback clause, and it is
    unverified. A principle that names its own untested assumption is
    stronger than one that doesn't.

## 10 · Sources

Verified this session unless marked otherwise. Grouped by section.

**The core result.** Bastani, Bastani, Sungu, Ge, Kabakcı & Mariman
(2025). Generative AI without guardrails can harm learning. PNAS
122(26). 10.1073/pnas.2422633122 [V, abstract verbatim] — correction
(affiliation only): 10.1073/pnas.2518204122 [V, full text read] ·
Soderstrom & Bjork (2015). Learning Versus Performance: An Integrative
Review. Perspectives on Psychological Science 10(2), 176–199.
10.1177/1745691615569000 [V].

**Durable capability.** Ericsson, Krampe & Tesch-Römer (1993).
Psychological Review 100(3), 363–406. 10.1037/0033-295X.100.3.363
[V-META] · Macnamara, Hambrick & Oswald (2014). Psychological Science
25(8), 1608–1618. 10.1177/0956797614535810 [V, figures verified] ·
corrigendum (2018) 29(7), 1202–1204. 10.1177/0956797618769891 [V-META]
· Macnamara & Maitra (2019). Royal Society Open Science 6(8), 190327.
10.1098/rsos.190327 [V] · Hambrick, Oswald, Altmann, Meinz, Gobet &
Campitelli (2014). Intelligence 45, 34–45. 10.1016/j.intell.2013.04.001
[V-META] · Roediger & Karpicke (2006). Test-Enhanced Learning.
Psychological Science 17(3), 249–255. 10.1111/j.1467-9280.2006.01693.x
[V-META] · Rowland (2014). Psychological Bulletin 140(6), 1432–1463.
10.1037/a0037559 [V] · Adesope, Trevisan & Sundararajan (2017). Review
of Educational Research 87(3), 659–701. 10.3102/0034654316689306 [V] ·
Cepeda, Pashler, Vul, Wixted & Rohrer (2006). Psychological Bulletin
132(3), 354–380. 10.1037/0033-2909.132.3.354 [V-META] · Brunmair &
Richter (2019). Similarity matters. Psychological Bulletin 145(11),
1029–1052. 10.1037/bul0000209 [V] · Bjork & Kroll (2015). American
Journal of Psychology 128(2), 241–252. 10.5406/amerjpsyc.128.2.0241
[V-META] · Dunlosky, Rawson, Marsh, Nathan & Willingham (2013).
Psychological Science in the Public Interest 14(1), 4–58.
10.1177/1529100612453266 [V-META] · Barnett & Ceci (2002). When and
where do we apply what we learn? Psychological Bulletin 128(4),
612–637. 10.1037/0033-2909.128.4.612 [V-META].

**Tutoring, the assistance dilemma, AI evidence.** Bloom (1984). The 2
Sigma Problem. Educational Researcher 13(6), 4–16.
10.3102/0013189X013006004 [V-META] · VanLehn (2011). Educational
Psychologist 46(4), 197–221. 10.1080/00461520.2011.611369 [V-META;
effect sizes unverified] · Kulik & Fletcher (2016). Review of
Educational Research 86(1), 42–78. 10.3102/0034654315581420 [V, median
0.66 verified] · Koedinger & Aleven (2007). Educational Psychology
Review 19(3), 239–264. 10.1007/s10648-007-9049-0 [V-META; abstract
unobtainable] · Koedinger, Booth & Klahr (2013). Science 342(6161),
935–937. 10.1126/science.1238056 [V-META] · Koedinger, Corbett &
Perfetti (2012). The Knowledge-Learning-Instruction Framework.
Cognitive Science 36(5), 757–798. 10.1111/j.1551-6709.2012.01245.x [V]
· Kalyuga, Ayres, Chandler & Sweller (2003). The Expertise Reversal
Effect. Educational Psychologist 38(1), 23–31.
10.1207/S15326985EP3801_4 [V-META] · Renkl & Atkinson (2003).
Educational Psychologist 38(1), 15–22. 10.1207/S15326985EP3801_3
[V-META] · Atkinson, Renkl & Merrill (2003). Journal of Educational
Psychology 95(4), 774–783. 10.1037/0022-0663.95.4.774 [V-META] ·
Aleven & Koedinger (2002). Cognitive Science 26(2), 147–179.
10.1207/s15516709cog2602_1 [V-META] · Kestin, Miller, Klales,
Milbourne & Ponti (2025). Scientific Reports 15(1).
10.1038/s41598-025-97652-6 [V, full text read] · Wang & Fan (2025).
Humanities and Social Sciences Communications 12(1).
10.1057/s41599-025-04787-y — RETRACTED; note at
10.1057/s41599-026-07310-z [V] · Bartoš, Martinková & Wagenmakers
(2025). PsyArXiv preprint. 10.31234/osf.io/8vs32 [V].

**Competence and motivation.** White (1959). Motivation reconsidered:
The concept of competence. Psychological Review 66(5), 297–333.
10.1037/h0040934 [V-META] · Ryan & Deci (2000). American Psychologist
55(1), 68–78. 10.1037/0003-066X.55.1.68 [V-META] · Deci, Koestner &
Ryan (1999). Psychological Bulletin 125(6), 627–668.
10.1037/0033-2909.125.6.627 [V-META] · Lepper, Henderlong & Gingras
(1999) comment, 125(6), 669–676. 10.1037/0033-2909.125.6.669 [V-META]
· Vansteenkiste, Ryan & Soenens (2020). Motivation and Emotion 44(1),
1–31. 10.1007/s11031-019-09818-1 [V-META] · Chen et al. (2015).
Motivation and Emotion 39(2), 216–236. 10.1007/s11031-014-9450-1
[V-META] · Ntoumanis et al. (2021). Health Psychology Review 15(2),
214–244. 10.1080/17437199.2020.1718529 [V] · Ng et al. (2012).
Perspectives on Psychological Science 7(4), 325–340.
10.1177/1745691612447309 [V-META] · Cerasoli, Nicklin & Ford (2014).
Psychological Bulletin 140(4), 980–1008. 10.1037/a0035661 [V-META] ·
Hulleman, Schrager, Bodmann & Harackiewicz (2010). Psychological
Bulletin 136(3), 422–449. 10.1037/a0018947 [V, numbers verified] ·
Senko, Hulleman & Harackiewicz (2011). Educational Psychologist 46(1),
26–47. 10.1080/00461520.2011.538646 [V-META] · Fong, Zaleski & Leach
(2015). Journal of Positive Psychology 10(5), 425–446.
10.1080/17439760.2014.967799 [V-META].

**Simulation, failure, safety.** Cook et al. (2011).
Technology-Enhanced Simulation for Health Professions Education. JAMA
306(9). 10.1001/jama.2011.1234 [V, numbers verified] · Norman, Dore &
Grierson (2012). The minimal relationship between simulation fidelity
and transfer of learning. Medical Education 46(7), 636–647.
10.1111/j.1365-2923.2012.04243.x [V-META] · Cheng, Eppich, Grant,
Sherbino, Zendejas & Cook (2014). Medical Education 48(7), 657–666.
10.1111/medu.12432 [V-META] · Sinha & Kapur (2021). When Problem
Solving Followed by Instruction Works. Review of Educational Research
91(5), 761–798. 10.3102/00346543211019105 [V, numbers verified] ·
Keith & Frese (2008). Effectiveness of error management training.
Journal of Applied Psychology 93(1), 59–69. 10.1037/0021-9010.93.1.59
[V, numbers verified] · Keith & Frese (2005). Journal of Applied
Psychology 90(4), 677–691. 10.1037/0021-9010.90.4.677 [V-META] ·
Edmondson (1999). Psychological Safety and Learning Behavior in Work
Teams. Administrative Science Quarterly 44(2), 350–383. 10.2307/2666999
[V-META].

**Model contingency and prior-sweep anchors.** Bainbridge (1983).
Ironies of automation. Automatica 19(6), 775–779.
10.1016/0005-1098(83)90046-8 [V-META] · Risko & Gilbert (2016).
Cognitive Offloading. Trends in Cognitive Sciences 20(9), 676–688.
10.1016/j.tics.2016.07.002 [V-META] · Lee, Sarkar, Tankelevitch,
Drosos, Rintel, Banks & Wilson (2025). CHI 2025, 1–22.
10.1145/3706598.3713778 [V-META] · Buçinca, Malaya & Gajos (2021).
PACM HCI 5(CSCW1), 1–21. 10.1145/3449287 [V-META].

## 11 · Known gaps

Stated plainly so the reader knows where the review is thin.

- VanLehn's specific effect sizes are unverified. The paper is
  paywalled and its abstract is elided everywhere reachable. Kulik &
  Fletcher's verified 0.66 carries the same argument; use that until
  VanLehn is checked directly.
- Koedinger & Aleven's abstract was unobtainable. The citation is
  solid; the characterisation of the assistance dilemma's content is
  from memory.
- The external critique literature on SDT is a real hole. Metadata
  APIs are poor at concept-level discovery and the search quota was
  gone. The claims about falsifiability and self-report dependence are
  assessment, not cited findings.
- The Wang & Fan retraction grounds are unverified. The retraction is
  confirmed; the stated reasons are not.
- "Mastery goals predict interest" — the null-on-achievement half of
  the Hulleman finding was verified, the positive-on-interest half was
  not, and claim C4 leans on it.
- Cook et al.'s simulation-vs-other-instruction comparison is
  recalled, not verified.
- No evidence found either way on whether consequence-free real work
  teaches as well as consequential real work — the review's central
  untested assumption, and commitment ten.
