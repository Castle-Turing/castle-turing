# Measuring demonstrated competence: what the research found

*Research done 2026-08-17. Records findings rather than posing the
question. The reviewer tagged every claim by verification level and ran
out of search budget partway; the weakest items are omitted here.*

**What.** `docs/vision.md` asks, as an explicit open question: "How is a
resident's demonstrated competence actually measured and stored per
domain — and does that one signal drive both explanation altitude and
the authority taxonomy, or do the two need separate mechanisms?"

## The result that is not a tuning problem

**You cannot infer both how good the resident is and how hard the task
was from whether the task went well.** This is algebraic, not empirical.

van de Sande, *Journal of Educational Data Mining* 5(2), 2013, solves
the Bayesian Knowledge Tracing model analytically. Its four nominal
parameters collapse in the observable: P(correct) = 1 − P(slip) −
A·e^(−βj), where **A = (1 − P(slip) − P(guess))(1 − P(prior
knowledge))**. Guess and prior knowledge enter only through their
product. "Different combinations… that give the same value for A will
result in models that have the exact same functional form." His stated
fix is to fix one of them "by some external constraint."

Hofman et al. (*Journal of Intelligence* 2018) hit the same wall from
Elo-style adaptive practice: item difficulty calibrates only because
thousands of learners answer the same items. With one person, ability
and difficulty update from the same scalar and are confounded.

Populations break this by holding the item fixed and varying the person.
**An N=1 system has no such lever.**

And the error is signed. Doroudi & Brunskill (EDM 2017) show a
misspecified mastery model yields confidently wrong parameters whose
*direction of error changes with observation count*, and that the
operational consequence is **premature declaration of mastery** — for a
tutor, under-practice; for an authority gate, **over-granting**.

## The fix, and it fits this architecture

Have the agent commit **in writing, before observing the outcome**, to
how hard the task was and what supervision level it expected to be
adequate. A pre-registered difficulty estimate makes the confound
identifiable by construction rather than by inference.

It is plain text, it carries provenance, and it is auditable — you can
later check whether the agent's difficulty priors were systematically
optimistic, which no purely inferential scheme affords. Same shape as
Proposal 04's evidence requirement and Proposal 06's pre-declared
observation window.

**If that field is ever allowed to be filled in after the outcome, the
scheme silently reverts to unidentifiable with no visible symptom.**

## Everything else points the same direction: over-granting

- **The agent is the wrong assessor.** Across medical studies, ~12.5% of
  assessors self-report passing someone who should have failed (one
  study: 38.3%). Assessors with a relationship to the assessed are
  systematically lenient. **The agent's relationship is stronger than a
  clinical supervisor's and its incentives are worse.** Medicine's
  answer is a committee of people who don't work with the trainee
  daily; there is no N=1 analogue.
- **Self-report cannot fill the gap.** Davis et al. (*JAMA* 2006):
  physicians have "a limited ability to accurately self-assess."
  Kruger & Dunning: overestimation is largest exactly where competence
  is lowest. So the two cheapest N=1 signals — the resident's
  self-report and the agent's own judgment — are biased **in the same
  direction** and do not cancel.
- **The resident can edit the log.** Medical trainees cannot rewrite
  their portfolios. Any signal the resident knows gates their own
  authority is under adversarial pressure from a party with root
  access.

Given errors that consistently signed, the system's default under
uncertainty must lean against them.

## Structure worth stealing from entrustable professional activities

- **The unit is an activity, not a competence.** ten Cate's AMEE Guide
  99 is explicit that competencies are qualities of persons and EPAs are
  units of work. Store `rotate-tls-certificates` at level 3 — never
  "competent at networking." The guide rejects titles carrying
  proficiency adjectives outright: proficiency lives in the *level*, not
  the name. A person-level label is the easiest way to build
  over-granting into the schema.
- **Expiry is already component 7 of the data model**, and it is
  triggered by *non-exercise*, not clock time, with graded
  re-verification ("a marginal or a more substantive check").
- **Uncertainty maps to level 3, not level 1** — act, then have it
  reviewed. It does not punish the resident for the system's ignorance,
  does not grant, and **generates exactly the evidence that resolves the
  uncertainty**. The system never needs to manufacture an exam; it needs
  to manufacture a review.

## Decay windows: use the science, not the institutions

Tatel & Ackerman (*Psychological Bulletin* 2025; 1,344 effect sizes,
457 reports): **0.08 SD/month for accuracy-based measures; half of
acquisition gains gone at ~6.5 months.** Arthur et al. (1998) add the
moderator that matters here — **cognitive, artificial and
accuracy-based tasks decay *faster* than the motor baseline**, which is
precisely the category this system gates.

So **3–6 months is the defensible starting half-life**, not ten Cate's
"one to five years" and not the FAA's 90 days. Both of those are
administrative convention — the FAA's own educational material teaches
*currency ≠ proficiency*, and the 90-day figure was extended from 30
for cross-part harmonisation.

Decay the derived level, never delete evidence. Drop one level per
half-life. **Time may only remove authority; only evidence adds it.**

## One signal cannot drive both

Contradicted on three independent grounds: authority requires strictly
more inputs than teaching (trustworthiness, task consequence, risk
posture — capability is one of five factors in ten Cate & Chen's RICH
model); **gating on a signal destroys it** (when workplace assessments
carry summative weight, engagement drops and supervisors inflate — and
Kennedy et al., *BMJ* 2009, found trainees suppress help-seeking to
protect credibility, so making help-seeking an authority input teaches
the resident to stop asking); and the two need incompatible latencies —
altitude should be fast and cheaply reversible, authority slow and
expensive.

What medicine actually built: **one stored substrate, one shared
vocabulary, two derived signals** with different aggregation, thresholds
and latency. The single-scale appearance is surface.

## What N=1 can and cannot support

- **Change detection: supported.** Molenaar and Fisher et al. (*PNAS*
  2018) establish that population-calibrated instruments do not validly
  describe within-person dynamics anyway — so the missing cohort costs
  less than intuition suggests. Caveat: within-person variance ran
  **2–4× larger** than within-group, so "enough observations" is a
  larger number than group intuitions suggest.
- **Absolute standard-setting: contradicted.** Every threshold in the
  literature comes from an expert panel or a normative sample. There is
  no procedure for deriving "good enough" from one person's data.
  **Make thresholds explicit resident policy and stop calling that part
  measurement.**

## What remains open

The reviewer's own ranked list of where this breaks, none solved: the
agent is a compromised assessor with no committee available; there is no
standard-setter; difficulty is unobservable without pre-registration;
the resident has root on their own record; and the activity list has no
validator, where a badly-carved activity over-generalises in exactly the
direction case specificity warns about.

**Do not store Dreyfus stages as a field.** No empirical evidence for
discrete stages, and they index to the person — the error AMEE Guide 99
and case specificity both warn against.
