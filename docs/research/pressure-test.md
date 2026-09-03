# The Pressure Test

*Castle Turing · four literature reviews · 16 August 2026.*

*What decades of prior art say about the design commitments this
project made from first principles — organized by what changes, not by
who published it. Originally rendered as a private Claude artifact;
transcribed to the repo 2026-09-03 so the record travels with the
project. The compressed, decision-relevant versions live in
`docs/backlog/` — this is the full report behind them.*

## Scorecard

Eleven claims · detail below.

| Verdict | Claim |
|---|---|
| **Contradicted** | A **weekly** retrospective audit is sound oversight |
| **Contradicted** | Provenance is the router's primary channel input |
| **Contradicted** | Silence is the safe default under uncertainty |
| **Revise** | Trust is built through a legible history |
| **Revise** | Receipts accumulating into questions is a firewall |
| **Revise** | Proposal 05 as an accuracy claim |
| **Vindicated** | Never promote implicit signals to ground truth |
| **Vindicated** | A very small sensor set is enough |
| **Vindicated** | Corrections, verbatim, over ratings |
| **Vindicated** | No numeric self-report scale anywhere |
| **New gap** | Suppressions leave no record |

## Contradicted

*Where the evidence runs against us.*

### The weekly audit

**Claimed: "Weekly" is the wrong parameter — "batched" is right.**

You suspected this one, and you were right, though not for the reason
either of us expected. Memory turned out to be the weaker half of the
case.

**Outcome bias is structural.** Identical decisions were rated better
when they happened to turn out well — even when subjects were
explicitly instructed to ignore the outcome and sincerely believed
they had. By audit time you know how it turned out and cannot un-know
it. We would be training on outcomes while believing we were training
on decision quality.

**The low-prevalence effect inverts the audit's usefulness.** Miss
rates rise from 7% at 50% target prevalence to 30–40% at 1%. The
audit's error-detection sensitivity *degrades as the agent improves* —
a safety mechanism whose sensitivity is inversely proportional to how
much it is needed.

And this exact governance pattern has been studied: 41 policies
requiring human oversight of algorithms, concluding people cannot
perform the oversight assumed, and that the requirements' main effect
is to **legitimize** the systems they oversee.

**What survives:** the founding commitment is *batched review replaces
in-the-moment confirmation*, and that is well supported — a third of
SSL warnings are clicked through, with habituation after 2–3
exposures. Batched is right. Weekly is the part under attack.

Citations: Baron & Hershey, JPSP 1988 (repl. 2023) · Guilbault et
al. 2004, 95 studies, d=.39, debiasing manipulations did not reduce
it · Wolfe, Horowitz & Kenner, Nature 2005 · Green, Computer Law &
Security Review 2022 · Akhawe & Felt, USENIX Security 2013, 25M+
impressions.

**Do:** Shorten the loop, keep the batch — daily or every-other-day.
Withhold the outcome until after judgment is recorded, and log both;
the divergence measures our own bias. Salt the sample with synthetic
known-bad decisions. Sample uniformly at random, never by
interestingness.

### Provenance as the router's primary input

**Claimed: It is a good prior and a bad axis.**

In the one study that deployed a real deferral system on authentic
two-hour tasks, **content relevance was the larger and more robust
effect on frustration** (F=13.9, p<.001, both task types) than
delivery policy (F=5.4, significant in only one). Worse, its headline
finding is an *interaction*: relevant content belongs at fine
breakpoints, general-interest at coarse. Provenance cannot express
that.

> Provenance is anti-correlated with value precisely in the tail where
> value is highest: the agent's most valuable output — an unrequested,
> urgent, highly relevant finding — is by construction the one our
> router is most likely to bury in a digest.

Citations: Iqbal & Bailey, CHI 2008 · Horvitz, "Principles of
Mixed-Initiative User Interfaces", CHI 1999 · Mehrotra et al.,
PrefMiner, UbiComp 2016 — 91% precision from content + coarse context,
no interruptibility model at all.

**Do:** Keep provenance as the day-one default and as a prior on "does
the resident want this." Add a coarse relevance-to-current-activity
signal and an urgency decay. Wire attention to *threshold modulation*
rather than direct channel selection — a noisy estimate then moves a
bar slightly instead of flipping a discrete decision.

### Silence as the safe default

**Claimed: Strictly dominated, and we may be laundering attention.**

In a two-week RCT (n=237), the **never-notify arm was strictly
dominated**: no improvement in inattention or concentration, but
anxiety +0.56, FoMO +0.60, and intentional checking +0.43. Batching
3×/day worked well — but hourly batching was *indistinguishable from
control*, so there is no smooth dial, and the largest single effect of
batching was *increased* fear of missing something. You buy calm with
unease.

Sharper still: disabling notifications for 20 users lengthened every
subsequent email check from **74.9s to 149.9s**. Three-quarters of
notifications are resolved by being *seen and ignored* — they are an
awareness mechanism, not an interruption.

Our vision's second-most-common output is "a completed action you only
notice if you go looking." **That is the un-notified condition in this
study.** If the resident starts checking what the agent has been up
to, we have converted a 2-second system-initiated glance into a
150-second self-initiated excursion — and moved it off our
instrumentation.

Citations: Fitz, Kushlev, Jagannathan, Lewis, Paliwal & Ariely,
Computers in Human Behavior 101, 2019 · Iqbal & Horvitz, CSCW 2010 ·
Pielot & Rello, MobileHCI 2017.

**Do:** Make the ambient, glanceable, zero-commitment channel the
*default* rather than one option among five — the status bar turning
amber, not silence. Reserve silence for things genuinely never worth
knowing. And instrument self-initiated checking of the action log: it
is the sharpest testable prediction in all four reports.

## Revise

*Right instinct, wrong argument or wrong scope.*

### Trust through a legible history

**Claimed: Two independent reviews hit this without knowing about each
other.**

Explanations increased the rate at which humans accepted an AI's
recommendation **regardless of whether it was correct**. A separate
review reports the XAI literature repeatedly finding that visible
explanations inflate trust rather than calibrate it — and that
*placebic* explanations work almost as well as real ones.

The journal may buy *trust* without buying *calibrated* trust, which
is the opposite of what it is for.

**The salvage both reviews found independently:** cited evidence is
the load-bearing half, not the reasoning prose. Evidence a resident
can check against an external source restores an independent
verification path; fluent reasoning is an anchoring device, and a
capable agent always produces plausible reasoning.

Citations: Bansal, Wu, Zhou, Fok, Nushi, Kamar, Ribeiro & Weld, CHI
2021 · Lee & See, "Trust in Automation: Designing for Appropriate
Reliance", 2004 — its calibration vocabulary is directly reusable.

**Do:** Demote "not shown, but always inspectable" from trust
mechanism to accountability floor. Surface evidence prominently and
reasoning secondarily. Consider showing some audit items *without* the
reasoning, to get an unanchored verdict.

### Proposal 06's question-selection firewall

**Claimed: It protects the weaker of the two channels.**

"Receipts may only accumulate into a question the resident answers" is
not the firewall it appears to be. **Controlling which questions get
asked is agenda-setting power over ground truth** — the verdict
distribution is a function of the query distribution, which is a
function of receipts. Removed by one indirection, not removed.

And the active-learning literature is unanimous that at low label
volume, *which* question you ask dominates *how many*.

**Do:** Give the question-selection policy the same suspicion,
auditability, and append-only record as the labeling policy.

### Proposal 05 stated as an accuracy claim

**Claimed: Defensible as values, indefensible as prediction.**

The literature supplies the conditions under which revealed preference
*is* the better estimator. If you say at audit "interrupt me less"
while reliably engaging with every interruption, our rule sides with
the statement. That is defensible as *your considered self governs*;
it is not defensible as *the statement predicts better*.

**The far stronger argument is exogeneity.** Revealed-preference
inference requires the choice set to be exogenous to the inferring
party — and an OS-level agent with authority *sets the choice set*.
Under those conditions revealed preference is not merely biased, it is
**circular**, and the circularity carries an active gradient toward
preferences that are cheapest to satisfy.

Citations: Kleinberg, Mullainathan & Raghavan, Management Science
2023 · Carroll et al., ICML 2022 & 2024 · Milli, Carroll, Wang,
Pandey, Zhao & Dragan, PNAS Nexus 2025 — stated-preference ranking
fixed the harm it targeted and produced echo chambers instead.

**Do:** Rewrite 05's rationale around exogeneity: stated preference's
advantage is not that you know what you want, it is that it is the one
channel the agent does not control. Much harder to attack.

## Vindicated

*Hold these — the evidence is stronger than our arguments were.*

### Never promoting implicit signals to ground truth

**Claimed: Better founded in 2026 than it would have been in 2020.**

State-of-the-art debiasing of implicit feedback, evaluated on 1.2B+
sessions against expert relevance labels, **improved click prediction
without improving actual relevance** — the field auditing its own
flagship correction machinery and finding it wanting. Separately, the
behaviour→values mapping is formally *sign-indeterminate*, not merely
noisy.

And our specific receipts are among the worst implicit signals
available: notification dismissal conflates content rejection, timing
rejection, triage-for-later, and ambient unavailability. Treating it
as valence is a category error before any bias correction enters.

Citations: Hager, Deffayet, Renders, Zoeter & de Rijke, SIGIR 2024 ·
Chaney, Stewart & Engelhardt, RecSys 2018 · Kleinberg et al.,
Management Science 2023.

### A very small sensor set

**Claimed: The best-supported claim in the whole design.**

An ablation study settles it. Desktop system events alone: **.64/.60
accuracy vs a .53/.37 base rate.** Cameras, microphones and calendars
*without* system events: .53–.58 — essentially baseline. Adding
perceptual sensing on top of system events buys about five points.

Expect roughly **+8 to +12 points over always-guessing**. A router
right four times in five, not one that knows. And note the asymmetry:
a model landing on "worst" moments scores *below* random, so a
confident router acting on a .64 signal can be net-negative.

Citations: Horvitz & Apacible, ICMI 2003 · Fogarty, Hudson & Lai, CHI
2004 — four features reach 77.6% of an eventual 79.5%.

**Add, free:** Application-switch pattern over a ~15s window, and
completion events (message sent, file closed, app closed). These were
the high-signal features in both studies and they turn "idle + focused
app" from a presence signal into a task-structure signal.

### Corrections, verbatim, over ratings

**Claimed: Task 0010's design is well supported.**

Corrections are choices from a tightly constrained implicit set, hence
high information per unit — and being *volunteered* rather than
solicited removes the acquiescence effects that contaminate solicited
ratings.

Two findings arrived after 0010 was drafted and support its
verbatim-only rule directly. People do not hold preference orderings
waiting to be read out — they **construct them at elicitation**, so
the resident did not *have* the scope when they said it. And in
measured robot-correction studies, people *cannot* give corrections
that isolate what they meant; systems updating everything a correction
touches "learn things the human never intended."

**The qualification that matters:** silence is a label, but only
interpretable against a known denominator. Volunteered corrections
arrive from a self-selected sample — so the audit's job is to define
the denominator that makes corrections interpretable. Corrections and
audit are complements; C2 cannot be used to weaken C1.

Citations: Jeon, Milli & Dragan, NeurIPS 2020 · Lichtenstein & Slovic
(eds.), *The Construction of Preference*, 2006 · Bajcsy, Losey,
O'Malley & Dragan, HRI 2018 · Spencer et al., Autonomous Robots 2022.

### No numeric self-report scale

**Claimed: Correct, and for a better reason than we had.**

Every standard correction for rating-scale drift — hierarchical
scale-usage models, anchoring vignettes, inter-rater renormalization —
requires **either many raters or repeated calibration items.** A
one-resident system has no other raters by construction, which makes a
0–5 scale *worse* here than in the population settings where it is
normally deployed.

That also disposes of the Claude Code observation cleanly: that widget
is a population telemetry instrument whose two enabling conditions —
many raters to average over, and a need for an absolute longitudinal
level — are exactly the two we lack.

**What we give up:** the ability to answer "is this better than a year
ago?" Comparison yields only a relative scale. The mitigation is
available but must be built — re-surface an archived decision
alongside a recent one and ask for a direct comparison.

Citations: Kiritchenko & Mohammad, ACL 2017 — best-worst scaling beats
rating scales at matched annotation budget · Rossi, Gilula & Allenby,
JASA 2001 · counterpoint: Wang et al., HelpSteer2-Preference, ICLR
2025 — ratings and preferences carry *complementary* information, so
"nowhere" is stronger than the evidence strictly supports.

## New gaps

*No slot in the architecture for these.*

### Suppressions leave no record

**Claimed: Four findings converged on it; none was looking for it.**

Low prevalence says absent behaviour is the hardest error to detect.
Narrow-then-widen scoping produces errors of omission by construction.
Stated-preference optimisation narrows monotonically. And the journal
records *decisions taken*, never things quietly not surfaced.

> The most likely long-run failure is not the agent doing something
> you did not want. It is the agent, correctly and with explicit
> authorisation at every step, gradually ceasing to do things — with
> no record, nothing in the audit sample, and no correction ever
> volunteered, because you cannot correct an absence you never
> noticed.

A filter bubble built entirely out of consent, invisible to every
oversight mechanism we have. Filed as `suppressions-leave-no-record.md`
with three candidate fixes.

### Bounded deferral — we jumped a literature

**Claimed: Seconds, not hours.**

The desktop interruption literature's deferral horizon is **43
seconds** mean busy duration across 113 users and 4,803 busy sessions,
and **88.6 seconds** actual mean deferral in the only authentic-task
deployment. Our digest is hours. Those are two different mechanisms
optimising different objectives, and we built only the second.

Citations: Achlioptas & Horvitz, MSR-TR-2005-87 · Iqbal & Bailey, CHI
2008.

**Do:** Hold a requested result 30–90 seconds until the next
app-switch or completion event, with a hard bound so it fires anyway.
Best-evidenced intervention in the corpus, uses exactly the sensors
already planned, costs the resident almost nothing.

### Three more, briefly

**Claimed: Cheap now, expensive later.**

- **Dismissal must be persistent state**, not a per-event outcome.
  Clippy repeated suggestions after any number of dismissals — an
  agent that never updates fails regardless of timing or channel.
  Cheapest single mechanism in all four reports.
- **Single-rater drift has no standard fix.** We cannot distinguish
  "the resident's values changed" from "the resident was inconsistent
  this week" unless the audit deliberately re-asks previously-answered
  questions and records the divergence. Nothing does.
- **Considered set and selection propensity** on decision records —
  without them off-policy evaluation is not identified, and Proposal
  04's no-relabeling rule makes the loss permanent, retroactive and
  silent. *Being built now.*

## On Clippy

*Our cautionary tale is better than we stated, and incomplete.*

The strong form of our claim is **primary-sourced and true**: the
Lumière paper says in its own words that the shipped Office Assistant
dropped the expected-utility gate, the persistent user profile,
competency reasoning, and multi-event history. The component that
decided *whether and when to surface* is precisely the component that
got cut. That is a better argument than the one in our vision doc,
because it names a mechanism rather than a vibe.

But the most rigorous study of why users actually hated it finds
**four co-equal failures**, of which timing and channel is one: it
never learned (repeating suggestions after any number of dismissals),
it had no relationship model, and its content was not useful. Plus two
mechanisms our design has never considered — **status threat**
(proactively offering help encodes a claim about your competence: "it
reminds me of how much I don't know") and **observation anxiety**
(being watched degraded task performance independent of any
interruption).

Three of the four are live risks for us *even if the router is
perfect*. The one we have designed against most carefully is a quarter
of the story.

Citations: Horvitz, Breese, Heckerman, Hovel & Rommelse, UAI 1998 ·
Swartz, "Why People Hate the Paperclip", Stanford, 2003.

## How much to trust this

*Read before quoting any of it.*

- **The production thumbs-up/down figures circulating in this space
  are simulation outputs** from an unreviewed 2026 preprint, not
  measured deployments. Do not repeat them as production evidence.
- One researcher caught a summarizer **confidently hallucinating**
  specifics about a paper it had not opened, and flagged that this
  literature circulates heavily as folk summary — treat any figure in
  a proactive-computing design doc as unverified until someone opens
  the PDF.
- Several load-bearing numbers went unverified, including the one that
  would decide whether value-of-information-gated asking preserves
  model quality. Get that before building EVOI-gated questions.
- Two literatures are contested: process supervision (complicated in
  2025 by a theoretical result showing outcome supervision is no
  harder statistically) and the filter-bubble evidence, where the
  strong popular claim has repeatedly failed to replicate. Cite the
  formal work, not the rhetoric.

## What is waiting on you

*Five decisions, none of which I should make.*

- **Proposal 06** — revise the audit assumptions, and give
  question-selection the same auditability as labeling.
- **Proposal 05** — rewrite the rationale around exogeneity rather
  than accuracy.
- **The router** — demote provenance from primary axis to prior, and
  add a relevance signal.
- **The ambient channel** — promote it to default, and instrument
  self-initiated checking so we can tell whether the digest is saving
  attention or laundering it.
- **Suppressions** — pick one of the three candidate mechanisms, or
  decide the gap is acceptable and say why.

---

*Four reviews · ~430k tokens · findings organized by consequence, not
by source. The compressed findings and the ten backlog entries live in
`docs/backlog/`; citations are marked [verify] there where
unconfirmed.*
