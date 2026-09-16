# Feedback routing is an unnamed seat

**What.** Resident feedback needs a post-processing pipeline —
distill the event into a rule, route it to the layer with the right
scope, propose the change through that layer's review gate — and
nothing owns that job. The castle-modal's feedback intake is, per the
resident (2026-09-10), built but wired to nothing; this entry is
about what happens after intake. Today the routing step is
undocumented session behavior: on 2026-09-10 a session ran the whole
pipeline by hand — feedback event, distillation into a rule with its
why, routing first to harness memory and then, on the resident's
instruction, promotion into the resident's private instruction
profile — and the only record of *how* it decided any of that is a
chat transcript. A behavior that important with no artifact is
exactly what this project files entries about.

Naming note, to head off a collision: `docs/architecture.md` already
defines a **Router** seat — channel and timing for records addressed
to the resident. That is a different job. This entry's subject is the
**feedback-routing seat**, and any brief promoted from here must pick
a name that cannot be read as that Router; "scope routing" is used
below for the activity.

**Why it matters.** Instruction-shaped feedback will not stay at the
volume one coding subsystem generates. Once agents launch campaigns —
the resident's term (2026-09-10) for programs of work larger than a
sprint, spanning repos and seats — feedback arrives faster than
ad-hoc sessions can conscientiously route it, and misrouted or
dropped feedback is the silent-failure shape this project's
conventions exist to prevent: a dropped complaint looks exactly like
no complaint. The sibling entry
[[the-speccing-step-is-an-unnamed-seat]] makes the structurally
identical argument for a different pipeline step; if both promote,
the unnamed-seat pattern (name the seat, declare its records, give it
an occupant) is probably worth generalizing once rather than speccing
twice.

**What we already know.** From the founding discussion (2026-09-10).
Decisions are the resident's; the rest is proposal until a brief
ratifies it.

- *The destinations and their gates already exist.* Session context,
  campaign scope, a repo's conventions, harness memory, the
  resident's instruction profile — each has an owner and a review
  gate (repo conventions and the profile require the resident;
  memory is agent-owned). The routing seat proposes into those
  gates; it installs nothing. The load-bearing invariant: **no path
  from feedback to installed instruction that does not pass a gate
  the pipeline cannot edit.** Routing procedure is public mechanism;
  the destination map and gate assignments are private configuration
  (Principle 01).
- *Route by the home of the thing the feedback concerns.* This makes
  the reflexive case ordinary rather than paradoxical: feedback
  about the routing seat routes to that seat's own artifact, which
  requires only that the seat have an artifact — the gap this entry
  names. Correct routing is not required for the reflexive route to
  work; knowing the seat's address is.
- *The hazard is silent drop, not misrouting.* Every feedback record
  gets a journaled disposition — routed to X because Y, or declined
  with reasoning — so a misbehaving routing seat leaves receipts in
  a record it does not control. Those dispositions get a second
  reader that is not the seat itself; the weekly audit is the
  natural home for that reading, though whether the audit can carry
  a seat-like obligation is an open question below. The shape of the
  argument is the one emcee's sprint digest states for its sentinel:
  it deliberately refuses a default sentinel model from the workers'
  own family, because a same-family reviewer prejudges what it
  reviews.
- *Instances route to kinds.* A campaign ends; feedback about it
  arrives after its scope is gone, and routes to the playbook or
  template that spawned it — the way an incident's lesson lands in
  the detector, not the outage report. Anything worth keeping past
  its scope's end belongs, by that fact, to a higher rung: a usable
  routing test.
- *Classification precedes routing.* Feedback splits into what-gets-
  built (routes to a backlog entry) and how-agents-work (routes to
  an instruction layer). The 2026-09-10 manual run handled only the
  second kind.

**How this would have been caught sooner.** It was caught by the
resident probing a live example, not by anything automated — the
usual way. The detector the eventual brief owes: feedback records
become a declared record type whose dispositions are checkable, so a
feedback record with no disposition is a hole a completeness sweep
reports. Two sibling entries already propose disposition-completeness
checks of exactly this shape —
[[nothing-sweeps-the-pipeline-invariants]] and
[[the-connector-reviews-have-no-dispositioner]] — and the brief
should extend one sweep to the new record type rather than spec a
third checker. A mechanical check cannot judge whether a route was
*right*; it can make silence impossible, which is the half that
matters. The audit samples dispositions for routing quality.

**Constraint at promotion time.** The routing seat is
pipeline-changing work, so [m2-constraints]'s baseline-before-
intervention clause applies to any brief promoted from this entry:
task-level outcome logging runs first, or the resident knowingly
waives it and the brief records the unmeasured bet.

**Open questions.** Whether the seat is a standing agent, a phase of
the weekly audit (and whether the audit — an oversight process, not
a seat in `docs/architecture.md`'s vocabulary — can carry such an
obligation without becoming one), or a step every session owes
before it closes. Where the routing rule itself lives — the
resident's profile serves one deployment, but the mechanism should
be statable as castle public mechanism with the profile as its
configuration. How campaign scope is declared so scope routing can
see it. And whether the modal's feedback intake and this seat share
a record type from day one, so wiring the modal later is
configuration rather than surgery.
