# The Delegation Papers

*Castle Turing · four reviews · 17 August 2026.*

*Everything the prior art says before the authority taxonomy gets
written — from the system that already tried this in 2000, and failed
in four named ways. Originally rendered as a private Claude artifact;
transcribed to the repo 2026-09-03 so the record travels with the
project. The compressed, decision-relevant versions live in
`docs/backlog/` — this is the full report behind them.*

> The vision calls the authority taxonomy "more than any model
> capability, the actual spec." The record agrees it must be settled
> early. It disagrees, sharply, about *what* to settle.

## Someone built this, and it broke

*USC Electric Elves · 2000 · seven months in production.*

Not an analogy — the same system. A dozen personal-assistant agents,
one per person, rescheduling meetings and declining on their users'
behalf. Their first design learned a decision tree mapping decision
features to tiers: **our taxonomy, learned rather than written.**

Four named catastrophes, and **every one was a transition failure**:

1. Cancelled a meeting with the **division director** — over-generalised
   from training examples.
2. Cancelled the weekly research meeting when **a timeout forced an
   autonomous choice**.
3. Delayed a meeting **~50 times, five minutes each**. Every delay
   correctly classified and in-tier; the damage was entirely in the
   sequence.
4. **Volunteered its user for a presentation** he was unwilling to
   give.

Before the timeout existed, the failure was its mirror image: the
agent waited indefinitely for a user who never answered,
miscoordinating with everyone. In the authors' words — rigidly
transferring control to the user failed, *and* a timeout that rigidly
transferred it back also failed.

**Their fix was a mechanism, not a better taxonomy.** A pre-defined
conditional sequence of control transfers. After it shipped, "the
agents have never repeated any of the catastrophic mistakes."

Citation: Scerri, Pynadath & Tambe, JAIR 2002 — read from primary
text.

## Three things to settle before writing a single category

*The reviewer's own list.*

**Gap 1 — There is no timeout policy, and that is half a spec.** The
tiers say nothing about what happens when a queued approval goes
unanswered. That gap killed Electric Elves twice, in both directions.
A three-tier document without one is incomplete in the specific way
that produced the only two failures anyone documented.

**Gap 2 — The fourth move is missing.** Electric Elves had three
options, not two: act, transfer control, or **change the coordination
constraints** — buy time, stall cheaply, lower the stakes. That move
fixed two of the four catastrophes and is absent from our tiers
entirely. An auto-reply "let me check and come back to you" is not a
decision at any tier. It is the thing that lets the approval tier
survive a resident who is asleep — which, for an attention-defence
agent, is a designed state rather than an exception.

**Structure — Maes built these three tiers the other way round.** Same
vocabulary — do-it / tell-me / ask — but the **tier is computed per
decision** from a confidence score. The category sets the
*thresholds*, not the tier. Cut-points are placed by
**reversibility**. Made-then-reported is **pull, not push**. And
competence is surfaced to the human, who moves the boundary — **the
agent never promotes itself.** One catch: her confidence number had a
real denominator, a count of similar remembered cases. An LLM's
self-reported confidence does not. The mechanism cannot be lifted
without building the case memory underneath it. (Maes & Kozierok,
AAAI-93 — read from primary text.)

The boundary condition comes from the Elves authors themselves: fixed
allocation works where response probability and wait cost are
*stable*. Our two live cases split cleanly on it. Config commits to a
private repo — nobody waiting, wait cost zero, reversible. Fine.
Declining a meeting — a third party waits, cost rises, and the
resident is sometimes *deliberately* unreachable because that is the
product.

**The uncomfortable corollary:** our one existing taxonomy entry comes
from the regime where fixed categories work, and will teach the wrong
lesson about the regime where they don't.

## The competence-gating clause is a feedback loop

*Two reviews, different literatures, same defect.*

The vision gates explanation depth and authority scope on demonstrated
competence. **That couples the safeguard to the variable it
protects.** Widening authority in a domain is what stops the resident
practising in it, so the calibration signal decays as a direct
consequence of acting on it — fastest where authority is already
widest. No damping term.

One review found it via Bainbridge (1983) and Endsley's automation
conundrum; the other via Lee et al. (CHI 2025), where **trust in AI is
associated with less critical thinking while self-confidence is
associated with more.** The two move against each other.

Both also noted independently that **resident-competence and
agent-competence are different numbers moving in opposite directions**
as authority widens. One signal driving both will be dominated by the
domain where the agent is already active — the domain with the least
resident data.

**Inverted assumption — Execution is sticky. Judgment is fragile.**
Casner et al., 16 airline pilots: manual control was "surprisingly
resistant to forgetting, even after four months of inactivity." What
collapsed was cognition — **44% error identifying missed approach
points, 38% on missed approach headings**, plus failures to
cross-check instruments and diagnose abnormal indications. The design
assumes the reverse — that you can hand over the doing and keep the
judging. Judgment is the entire content of an audit. (Casner, Geven,
Recker & Schooler, Human Factors 56, 2014 · Ebbatson et al.,
Ergonomics 2010 — decay measurable at a one-week recency.)

**The auditor cannot self-assess — Experts missed a 19% slowdown in
their own work.** METR (2025): 16 experienced developers, 246 tasks,
repos they had worked five years. Forecast **+24%**. Self-reported
afterward **+20%**. Measured: **−19%**. If experts cannot audit their
own throughput in their own codebase, the prior on auditing an agent's
judgment should be low.

**The trap for anyone fixing this with a checklist — The instrument
that makes a novice reliable inverts the expertise ordering.** Hodges
et al. (1999): clerks, residents and family physicians scored on
identical encounters. Experienced clinicians scored **significantly
better on global ratings and significantly worse on checklists** —
experts skip steps they have already ruled out, and a checklist reads
that as omission. So a comprehension-level audit aid would
systematically flag a well-performing agent taking expert shortcuts,
and pass an agent that is thorough and wrong.

## The algebraic result

*Not a tuning problem — an identifiability one.*

**You cannot infer both how good the resident is and how hard the task
was from whether the task went well.**

van de Sande solves the Bayesian Knowledge Tracing model analytically.
Its four nominal parameters collapse in the observable:

    P(correct) = 1 − P(slip) − A·e^(−βj)
    where  A = (1 − P(slip) − P(guess))(1 − P(prior knowledge))

Guess and prior knowledge enter *only through their product*.
Different combinations giving the same A produce models with the exact
same functional form. His stated fix: fix one of them "by some
external constraint."

Populations break this by holding the item fixed and varying the
person. **An N=1 system has no such lever.** Elo-style adaptive
practice hits the identical wall — item difficulty calibrates only
because thousands of learners answer the same items.

And the error is *signed*: a misspecified mastery model yields
confidently wrong parameters whose direction of error changes with
observation count, and the operational consequence is **premature
declaration of mastery**. For an authority gate, that is over-granting.

**The fix, and it fits this architecture — Pre-register the
difficulty.** Have the agent commit **in writing, before observing the
outcome**, to how hard the task was and what supervision level it
expected to be adequate. That makes the confound identifiable by
construction rather than by inference. Plain text,
provenance-carrying, and auditable — you can check whether the agent's
difficulty priors run systematically optimistic, which no inferential
scheme affords. Same shape as Proposal 04's evidence requirement and
Proposal 06's pre-declared window. **If that field can ever be filled
in after the outcome, the scheme silently reverts to unidentifiable
with no visible symptom.**

Everything else in that review pointed the same direction —
over-granting. Assessors with a relationship to the assessed are
systematically lenient (12.5–38% pass people who should fail), and
*the agent's relationship is stronger than a clinical supervisor's
with worse incentives*. Self-report cannot fill the gap: the two
cheapest N=1 signals are biased the same way and do not cancel. And
the resident can edit the log — medical trainees cannot rewrite their
portfolios.

## The social failure is not the one we anticipated

*And the fix for machine-worn authority is cheaper than expected.*

**Electric Elves, 2008 retrospective — Users gamed the taxonomy to
launder refusals.** Users deliberately routed decisions into the
autonomous tier so that refusals "would be attributed to the agent,
rather than directly to the user." **It came to light only after the
project ended.** The taxonomy is not only a safety spec. It is a
plausible-deniability API, and it will be used as one — the incentive
is real and it isn't even dishonest. If the log doesn't record who
moved each threshold, when, and immediately before what, nobody finds
out.

**The reframe — Delegation is free. Wearing the principal's identity
is not.** Schilke & Reimann (13 preregistered experiments, 4,093
observations) built human-delegation controls into four studies.
Disclosing that a *person* did the work: no significant penalty (d =
0.06–0.17, ns). Disclosing *AI*: d = 0.77–1.11 in the same designs.
And Study 10: an email from an **openly autonomous AI agent** was
trusted *more* (M=5.61) than one from a human disclosing AI help
(M=4.94), and was indistinguishable from a human disclosing nothing
(M=5.72). The blended human-AI author is the least legitimate
configuration, because nobody clearly holds responsibility. **So the
design lever is: don't wear the resident's authority.** Let the agent
sign as the agent. The vision states the problem as machine-worn
authority; the evidence says that framing describes an avoidable
configuration rather than an inherent one.

Two more that shape the outward-facing row.
**Concealment-then-discovery is the worst outcome and it is
measured** — exposure by a third party (M=2.49) sits below
self-disclosure (M=3.15) and far below undetected non-disclosure
(M=4.02). Non-disclosure wins only conditional on never being found
out, and for an always-on agent that probability converges on one. And
**the measured harm is to the resident's standing**, not the third
party's welfare — no study measures whether the declined party was
worse off. Self-interest and ethics point the same way, which makes
the rule enforceable by appeal to reputation rather than altruism.

## What is genuinely unresolved

*Including one place the science has not gone.*

- **Whether assessment competence survives loss of production
  competence in knowledge work.** One reviewer searched specifically
  and found no direct literature. Everything available is indirect —
  motor-domain, assessors' self-reported beliefs, or code review. The
  project's most load-bearing oversight assumption sits exactly where
  the evidence stops.
- **The agent is a compromised assessor and there is no committee.**
  Medicine's answer to assessor leniency is a panel of people who
  don't work with the trainee daily. There is no N=1 analogue, and
  reading more literature will not produce one.
- **No standard-setter.** Every threshold in the literature comes from
  an expert panel or a norm sample. At N=1, "good enough" is a policy
  act, not a measurement — and the design should say so rather than
  letting a magic constant sneak in.
- **Categories vs. thresholds is a real trade, not a solved
  question.** Categories buy predictability and auditability — which
  matters more for one resident building a mental model than for
  shift-rotating crews. Thresholds buy calibration. Every failure in
  the record is a system that had one without the other.
- **The lumberjack effect is contested.** Four papers, unresolved,
  with the contrary result coming from the setting closest to this
  one. Cite as hypothesis, never as settled.

## How much to trust this

*Read before quoting any of it.*

- Every reviewer tagged its own verification level, and each ran out
  of search budget before finishing. Primary-text reads are marked as
  such in the backlog entries; several load-bearing numbers are
  abstract-level or summary-level only.
- **Sparrow et al.'s "Google effects" failed to replicate** — twice.
  Do not build on it. The metacognitive findings (Fisher/Goddu/Keil, 9
  experiments) are the sturdier ground.
- The GPS/hippocampus longitudinal arm is **N=13**. Directionally
  consistent, evidentially thin.
- Institutional decay windows — ten Cate's "one to five years," the
  FAA's 90 days — are **administrative convention, not measurement**.
  The FAA's own material teaches that currency ≠ proficiency, and the
  90-day figure was extended from 30 for cross-part harmonisation. Use
  the decay meta-analyses instead: roughly a **3–6 month half-life**
  for the cognitive, accuracy-based tasks this system actually gates.

---

*Four reviews · findings recorded durably in `docs/backlog/` with
per-claim verification levels: authority-taxonomy-prior-art ·
delegation-atrophy · competence-measurement-entrustment ·
machine-worn-authority.*
