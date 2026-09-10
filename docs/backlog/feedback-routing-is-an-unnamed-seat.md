# Feedback routing is an unnamed seat

**What.** Resident feedback needs a post-processing pipeline —
distill the event into a rule, route it to the layer with the right
scope, propose the change through that layer's review gate — and
nothing owns that job. The castle-modal's feedback mechanism (built,
unwired) is the intake side; this entry is about what happens after
intake. Today the router is undocumented session behavior: on
2026-09-10 a session ran the whole pipeline by hand — feedback event,
distillation into a rule with its why, routing first to harness
memory and then, on the resident's instruction, promotion to the
Chevaline profile (`instructions/communication.md`, "A no-op is not
fulfillment") — and the only record of *how* it decided any of that
is a chat transcript. A behavior that important with no artifact is
exactly what this project files entries about.

**Why it matters.** The resident expects far more instruction-shaped
feedback than the agentic-coding subsystem alone generates once
agents launch campaigns (the resident's term, 2026-09-10: programs of
work larger than a sprint, spanning repos and seats). Feedback will
arrive faster than ad-hoc sessions can conscientiously route it, and
misrouted or dropped feedback is the silent-failure shape this
project's conventions exist to prevent: a dropped complaint looks
exactly like no complaint.

**Design positions from the founding discussion (2026-09-10),
recorded so the spec does not re-derive them.** Decisions are the
resident's; the rest is proposal until a brief ratifies it.

- *The destinations and their gates already exist.* Session context,
  campaign scope, a repo's conventions, harness memory, the Chevaline
  profile — each has an owner and a review gate (repo conventions and
  the profile require the resident; memory is agent-owned). The
  router proposes into those gates; it installs nothing. The load-
  bearing invariant: **no path from feedback to installed instruction
  that does not pass a gate the pipeline cannot edit.** Routing
  procedure is public mechanism; the destination map and gate
  assignments are private configuration (Principle 01).
- *Route by the home of the thing the feedback concerns.* This makes
  the reflexive case ordinary rather than paradoxical: feedback about
  the router routes to the router's own artifact, which requires only
  that the router have an artifact — the gap this entry names.
  Correct routing is not required for the reflexive route to work;
  knowing the router's address is.
- *The hazard is silent drop, not misrouting.* Every feedback record
  gets a journaled disposition — routed to X because Y, or declined
  with reasoning — so a misbehaving router leaves receipts in a
  record it does not control. The router's dispositions get a second
  reader that is not the router (the weekly audit is the natural
  seat; same argument as emcee's refusal to default a sentinel from
  the workers' own model family).
- *Instances route to kinds.* A campaign ends; feedback about it
  arrives after its scope is gone, and routes to the playbook or
  template that spawned it — the way an incident's lesson lands in
  the detector, not the outage report. Anything worth keeping past
  its scope's end belongs, by that fact, to a higher rung: a usable
  routing test.
- *Classification precedes routing.* Feedback splits into what-gets-
  built (routes to a backlog entry) and how-agents-work (routes to an
  instruction layer). The 2026-09-10 manual run handled only the
  second kind.

**How this would have been caught sooner.** It was caught by the
resident probing a live example, not by anything automated — the
usual way. The detector the eventual brief owes: feedback records are
a declared record type whose dispositions are checkable, so a
feedback record with no disposition is a hole the completeness pass
reports, and the audit samples dispositions for routing quality. A
mechanical check cannot judge whether a route was *right*; it can
make silence impossible, which is the half that matters.

**Open questions.** Whether the seat is a standing agent, a phase of
the weekly audit, or a step every session owes before it closes.
Where the routing rule itself lives — the Chevaline profile serves
one resident's version, but the mechanism should be statable as
castle public mechanism with the profile as its configuration. How
campaign scope is declared so the router can see it. And whether the
modal's feedback intake and this seat share a record type from day
one, so wiring the modal later is configuration rather than surgery.
