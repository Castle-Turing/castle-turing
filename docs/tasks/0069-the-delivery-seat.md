Title: Task 0069 — the delivery seat
Model: deep
Milestone: m2-done
Model-because: the deliverable is an amendment to docs/architecture.md,
a document whose seat paragraphs are commitments with guard language
later agents are held to. The judgment is the work: where this seat's
boundary sits against the worker, outbox, and builder paragraphs, and
which sentences must constrain a later agent from "completing" the
seat into something it must not be. A standard implementer following
this brief would produce plausible prose; what breaks is load-bearing
wording, and that failure reads well in review precisely when it is
wrong.

# Task 0069 — the delivery seat

## Where this came from

Decided with the resident on 2026-09-07. The loop that turns a
numbered brief into a merged change — brief in `docs/tasks/`,
implementation on a branch, pull request, cross-model review,
dispositions, human merge — is the mechanism by which this system's
own findings become landed changes. Today that loop is held end to
end by an external harness (the operator runs emcee), and it is
invisible to this architecture: its parks, retries, budget aborts,
and model routing appear in no journal the weekly audit can read.
The outbox seat carries a finding *out* of the OS; nothing names
what happens to it after. The fix is not to absorb the harness; it
is to name the seat it occupies, exactly as Proposal 03 names Claude
Code a tenant of the worker seat rather than a structural member.

## What to write

Amend `docs/architecture.md` with a **delivery** seat. The name is
chosen because "builder" is taken by the compile seat; if review
finds a better name, change it before merge, not after. The
paragraph must establish:

- **What it reads and writes.** The seat reads a numbered brief from
  a configured checkout's `docs/tasks/` and writes three things: a
  branch and pull request against that checkout's repository, and
  journal records — a `claim` when it takes a brief, a `result`
  carrying `outcome` and which tenant and model implemented, and
  `question` records when it blocks on a judgment only the resident
  can supply. A park is not a private state of the harness; it is a
  question, routed by the router like any other, and the answer
  resumes the errand through the same machinery task 0023 built for
  the worker.
- **It is a reasoning seat.** Unlike dispatch, applier, outbox,
  builder, and activation, this seat holds judgment: it chooses an
  implementer sized to the brief, judges whether a CI failure is the
  task's fault, and decides retries. It is the third reasoning seat,
  after worker and router. The guard language therefore points the
  other way from the plumbing seats' — not "do not give it a
  policy" but a hard ceiling on its authority: **the delivery seat
  never merges, never approves, never closes a review finding
  silently, and never deploys.** Its product is a pull request
  nobody has merged; the resident's judgment is spent once, at the
  merge — the outbox's sentence, holding one seat further down the
  pipeline.
- **The result names its implementer** — tenant and model — because
  the review section's premise is that disagreement between
  independent reviewers is the signal, and a change implemented and
  reviewed by the same vendor has quietly lost its second opinion.
  Review routing needs the implementer's identity as a recorded
  fact, not a thing to reconstruct.
- **Substrates are the tenant's business.** The current tenant runs
  several coding harnesses behind its own adapter interface. None of
  that enters this architecture: inside the seat the harness is
  free, and a resident swaps tenants — or brings their own harness —
  by configuration, not by amending this document. This is the
  Principle 01 split: the seat contract is public mechanism; which
  harness, which models, whose subscription, is private
  configuration.
- **Records arrive through a shim the integrator owns.** The tenant
  never learns this project's record format; it emits its own
  events, and a castle-side shim translates them into records. The
  amendment fixes the records; the shim is tooling
  (`docs/backlog/the-delivery-seat-has-no-record-shim.md`).
- **Authority.** Pushing branches and opening pull requests on a
  remote is an authority the resident grants this seat, and its
  taxonomy category is deferred to the authority-taxonomy task the
  same way the existing standing-authority bullets defer theirs.
  State what is settled: the seat is off unless configured, and
  every branch it pushes traces to a claim record.

## What not to do

Do not model substrates, adapters, or any harness-internal interface
in architecture.md. Do not write the shim. Do not touch
`docs/principles/` — if the amendment seems to need a new principle,
stop and say so. Do not give the delivery seat any path to merging,
approving, or activating anything.

## Verification plan

Agent-verifiable: `nix flake check`; the amendment's claims
cross-read against the worker, outbox, and review sections for
contradictions (the worker's "proposes, never deploys" and the
outbox's "judgment spent once" must survive unamended). Needs human
hands: the naming call and the merge itself — this is a change to a
binding document and the resident reads every line.

## Implementation record

Written as three edits, all in `docs/architecture.md` except the
last:

1. A **Delivery** entry in the Seats section, placed after
   Activation and before Sensors. Placement is accretion order — the
   position every seat since dispatch has taken — and it keeps the
   run of five plumbing paragraphs contiguous rather than splitting
   it with a reasoning seat.
2. A sixth bullet in the standing-authority list under "Where
   runtime state lives", because this is the first seat in the
   architecture that reaches a remote and the bullet above it says
   pushes are left to the resident. That bullet is scoped to the
   repository holding `state/`; the new one says so explicitly
   rather than leaving a reader to decide which sentence wins.
3. A one-line patch to `[m2-now]` in `docs/state/MILESTONE.md`,
   under the same-PR rule in `docs/state/README.md`: the seat the
   pipeline's harness occupies is now named, and the records it owes
   the journal still do not exist.

Judgment calls a reviewer should check:

- **Two paragraphs, not one.** Every other seat is a single
  paragraph. This one carries the contract and its ceiling in the
  first, and what the document deliberately does not model in the
  second, because a single paragraph carrying both ran past the
  length of the worker's — the longest in the document — by half
  again.
- **New citations name records rather than linking them**
  (`docs/state/README.md` rule 1), so the text says "task 0023"
  where the paragraphs around it say `docs/tasks/0023-resume-cold.md`.
  The older citations are left as written; they are the scar that
  rule exists for, and rewriting them is not this task.
- **The `[m2-now]` patch was not requested by the brief.** It is
  here under rule 2 of the state README — this PR makes a design
  decision about the pipeline the milestone describes.
- **The list introduced as "Two consequences" now carries six
  bullets** and did already carry five. Left alone deliberately: it
  is a pre-existing defect in a binding document, and correcting it
  is not this brief's scope.
