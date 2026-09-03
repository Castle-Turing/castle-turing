# The authority taxonomy: what the prior art says before we write it

*Research done 2026-08-17. Records findings rather than posing the
question. The reviewer read primary text for the closest precedents;
secondary-source items are marked in its report and the weaker ones are
omitted here.*

**What.** `docs/vision.md`: "Decide the authority taxonomy early. Which
categories of decision are made silently, which are made-then-reported,
and which are queued for explicit approval… This taxonomy, more than any
model capability, is the actual spec."

**The verdict: deciding early is right; deciding it as a fixed
assignment of categories to tiers is the move the closest precedent
tried, and it failed at transitions.**

## USC's Electric Elves ran this experiment

Not an analogy — the same system. A dozen personal assistant agents, one
per person, running seven months in 2000, rescheduling meetings and
declining on their users' behalf. Their first design learned a decision
tree mapping decision features to tiers: our taxonomy, learned rather
than written (Scerri, Pynadath & Tambe, *JAIR* 2002).

Four named catastrophes, **every one a transition failure**:

1. Cancelled a meeting with the division director — over-generalised.
2. Cancelled the weekly research meeting when **a timeout forced an
   autonomous choice**.
3. Delayed a meeting ~50 times by 5 minutes each, every delay correctly
   classified and in-tier; the damage was in the sequence.
4. Volunteered its user for a presentation he was unwilling to give.

And before the timeout existed, the failure was the mirror image: the
agent waited indefinitely for a user who never answered, miscoordinating
with everyone else. The authors: "rigidly transferring control to one
agent (user) failed. Furthermore, using a time-out that rigidly
transferred control back to the agent… also failed."

**Their fix was a mechanism, not a better taxonomy** — a
"transfer-of-control strategy," a pre-defined conditional sequence of
control transfers and coordination changes. After it shipped, "the
agents have never repeated any of the catastrophic mistakes."

## The boundary condition, from the same authors

Fixed allocation is adequate "in applications where [probability of
response and wait cost] do not change dramatically from decision to
decision." Applied here, our two live cases split:

- **Config commits to the private repo** — nobody waiting, wait cost ≈ 0,
  reversible by design. Fixed tier is genuinely fine.
- **Declining a meeting, triaging mail** — a third party is waiting, wait
  cost varies and rises, and response probability swings wildly because
  *the resident is sometimes deliberately unreachable, which is the
  product*. E-Elves' parameters exactly.

Uncomfortable corollary: our one existing taxonomy entry comes from the
regime where fixed categories work, and will teach the wrong lesson
about the regime where they don't.

## Maes built these three tiers the other way round

Maes & Kozierok, "Learning Interface Agents" (AAAI-93), behind the CACM
1994 paper. Same three tiers — do-it / tell-me / ask — but:

- The **tier is computed per decision** from a confidence score, not
  looked up per category. The same category lands differently on
  different days.
- The **category sets the thresholds**, not the tier. What is written
  and stable is the cut-point per action type.
- Cut-points are placed by **reversibility** — "higher 'do-it'
  thresholds for actions which are harder to reverse."
- Made-then-reported is **pull, not push**: a report the user requests.
- Competence is surfaced to the *user*, who moves the boundary. **The
  agent never promotes itself.**

Her confidence number had a real denominator — a count of similar
remembered cases. An LLM's self-reported confidence does not. The
mechanism cannot be lifted without building the case memory underneath
it.

## Two gaps in our three tiers

1. **The missing fourth move.** E-Elves had three options, not two:
   act, transfer control, or **change the coordination constraints** —
   buy time, stall cheaply, lower the stakes. That move fixed two of the
   four catastrophes and is absent from our tiers. An auto-reply "let me
   check and come back to you" is not a decision at any tier; it is what
   lets the approval tier survive an unreachable resident.
2. **No stated behaviour on approval timeout.** That gap killed E-Elves
   twice, in both directions. A three-tier document with no timeout
   policy is half a spec.

## The social failure that actually materialised

Not the one the vision anticipates. From the 2008 retrospective (Tambe
et al., *AI Magazine* 29(2)): users deliberately routed decisions into
the autonomous tier so refusals "would be attributed to the agent,
rather than directly to the user" — laundering socially costly declines.
**It came to light only after the project ended.**

The taxonomy is not only a safety spec. It is a plausible-deniability
API and it will be used as one. If the log does not record who moved
each threshold, when, and immediately before what, nobody finds out.

Same paper, adjacent: agents in office settings "may need to politely
lie on behalf of their users"; and when one agent's meeting-importance
model leaked, revealing how it ranked people, "a minor controversy
ensued." A tier vocabulary says *whether* the agent may decline and
nothing about *how*, which is where the social failure lands.

## What remains open

The three recommendations the reviewer would give someone writing the
document tomorrow, none of them adopted here:

1. **Spec the timeout and the stall move before a single category.**
2. **Make the tier a computed output over written, stable inputs** —
   action types, reversibility classes, who may move a cut-point and how
   that move is logged. Note this passes the Principle 01 test more
   cleanly than a category table: public mechanism is the threshold
   machinery, private configuration is where this resident sets each
   cut-point.
3. **Split the competence signal in two** and instrument the resident's
   gaming of the taxonomy from day one.

Also unresolved: the general levels-of-automation literature has largely
turned against levels as a *design* instrument while conceding they work
as an *evaluation* instrument — and Billings' predictability argument
cuts the other way for a single resident building a mental model of a
system living in their OS. Categories buy predictability and
auditability; thresholds buy calibration. Every failure in the record is
a system that had one without the other.

*Full review: see `docs/research/delegation-papers.md` (landed after this entry was written).*
