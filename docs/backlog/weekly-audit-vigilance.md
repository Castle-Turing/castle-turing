# Will the weekly audit survive being mostly right?

*A research question, not deferred implementation. **Largely answered
already** — see below. What remains is a design decision, not a
literature search.*

**What.** `docs/vision.md`: "A short weekly audit replaces confirmation
dialogs sprayed across the day. Corrections during the audit are the
training signal." Proposal 06 (`docs/architecture.md`) sharpens the
dependency: "learning is bottlenecked on the resident's audit
attention: skip the audits and it … simply stops learning," with a
hardening test of "the audit runs mechanically off sampled falsifiers
in under ten minutes."

The unstated assumption: a human can sustain real scrutiny of a
mostly-correct system indefinitely.

**What the completed research found.** The assumption is contradicted,
and not for the reason expected — memory turned out to be the weaker
half of the case.

- **Outcome bias is structural.** Baron & Hershey (*JPSP* 1988,
  replicated 2023): identical decisions were rated better when they
  happened to turn out well — *even when subjects were explicitly
  instructed to ignore the outcome and themselves reported having done
  so.* By audit time the resident knows how it turned out and cannot
  un-know it. **We would be training on outcomes while believing we
  were training on decision quality.** No audit design removes this;
  withholding the outcome until after the judgment is recorded is the
  only mitigation, and it also measures the bias.
- **Hindsight bias resists debiasing.** Guilbault et al. (2004), 95
  studies, mean d = .39: studies with manipulations designed to reduce
  hindsight bias **did not produce lower effect sizes.** A prompt saying
  "judge on what was knowable at the time" is decoration.
- **The low-prevalence effect inverts the audit's usefulness.** Wolfe,
  Horowitz & Kenner (*Nature* 2005): miss rates rise from 7% at 50%
  target prevalence to 30–40% at 1%. **The audit's error-detection
  sensitivity degrades exactly as the agent improves** — a safety
  mechanism whose sensitivity is inversely proportional to how much it
  is needed.
- **This governance pattern has been studied directly.** Ben Green,
  "The flaws of policies requiring human oversight of government
  algorithms" (*Computer Law & Security Review* 2022) surveyed 41 such
  policies: people cannot perform the oversight functions assumed, and
  the requirements' main effect is to **legitimize** faulty systems,
  "providing a false sense of security."
- **The ritual lapses.** Epstein et al.'s lived-informatics model
  (UbiComp 2015) exists because reflection is the stage users skip.

**What survives.** The founding commitment is *batched review replaces
in-the-moment confirmation*, and that is well supported — Akhawe & Felt
(USENIX Security 2013, 25M+ warning impressions) found a third of SSL
warnings clicked through with habituation after 2–3 exposures. Batched
is right. **"Weekly" is the parameter the evidence attacks, not
"batched."**

**What would change — four concrete moves, all preserving the
commitment.**

1. Shorten the loop, keep the batch. Daily or every-other-day wins on
   episodic access, outcome contamination, and compliance, and costs
   nothing on the axis the vision cared about.
2. Withhold outcomes during judgment; reveal after, and log both. The
   divergence is a measurement of our own outcome bias.
3. **Salt the audit with synthetic known-bad decisions** — raising
   effective prevalence is the only manipulation that reliably works,
   and it turns "is the audit still working?" into a number. Two
   independent reviews arrived at this from different literatures; the
   directly transferable precedent is Threat Image Projection in airport
   baggage screening.
4. Sample uniformly at random from the agent's own decision
   distribution, never by interestingness — this preserves the property
   that feedback is collected on the distribution the learner induces.

**Priority: high.** Three documents lean on the audit, and its ritual
design is imminent. Proposal 06's "bottlenecked on audit attention"
cost should be repriced upward, which bears on its own open question
about whether the router writes too many decisions.
