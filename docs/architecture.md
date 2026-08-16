# The agent layer — architecture

*Castle Turing — how the agent layer is put together: the seats
intelligence occupies, the plain-text artifacts they communicate
through, and where runtime state lives. This document also carries the
project's **proposed commitments** — principle-shaped decisions being
tested by implementation before formal adoption. Per CLAUDE.md, drafts
never enter `docs/principles/`; a principle doc is a commitment. A
proposal is promoted to a numbered principle only after implementation
has leaned on it and it held, and each proposal below states the
hardening test that decides that. Proposed with task 0008.*

## The layer in one paragraph

The agent layer is a set of **seats** — named roles such as intake,
router, and worker — connected by plain-text **records** flowing
through a **journal** that serves as message bus, audit log, and state
store at once. No seat *is* a model: each is defined entirely by the
artifacts it reads and writes, and any intelligence that can read and
write those artifacts can hold the seat — a frontier model behind a
harness, a local model, a shell script in CI, or a human at a
keyboard. That is the same reasoning that put the system's
configuration in a flake, the backlog in files, and the docs in
markdown, applied to the agent itself: the structure is plain text,
and the intelligence is a tenant (Proposal 03, below).

## Records

Every message in the system is a record: one file per record, YAML
frontmatter for machine-readable fields, markdown body for prose. One
file per record for the same reason `docs/backlog/` is one file per
entry — concurrent writers never conflict where a shared file would.
Records are append-only in spirit: a record is never edited after
writing; anything that changes is expressed as a *new* record
referencing the old one.

Frontmatter fields, minimum set:

- `id` — unique, sortable (timestamp-prefixed).
- `type` — `request`, `decision`, `result`, `question`, `answer`.
- `provenance` — `requested` (the resident asked for this) or
  `initiated` (the system undertook it on its own). See below.
- `refs` — ids of the records this one responds to.
- `seat` — which seat wrote it.
- `created` — timestamp.

Decision records carry one more required field: `evidence` (see
Proposal 04). The body carries the prose — a request's description, a
diagnosis, a decision's rationale.

The exact schema is versioned with the tooling in `agent/`; this
document fixes only the commitments above.

## The journal and the spool

**The journal** is the durable log: requests, decisions, results,
questions, answers, and the resident's corrections. It is three things
at once, deliberately:

- *Message bus* — seats communicate by appending records and reading
  records that reference theirs.
- *Audit log* — the weekly audit reads it; every decision is in it,
  with reasoning and evidence (vision: "trust is built through a
  legible history").
- *State store* — the current state of any errand is a fold over its
  records. There is no separate database to drift out of sync with the
  log.

**The spool** is the ephemeral counterpart: progress chatter,
heartbeats, partial output — same record format, machine-local,
never committed, deletable at any time without loss. The split exists
so the journal stays an account of judgments rather than rotting into
a gigabyte of progress ticks.

## Seats

**Intake** (a surface). Turns a resident's request into a `request`
record. The first intake is a CLI; a compositor keybinding opening a
modal, and eventually mail or calendar, are later intakes. An intake
adds no judgment — it captures the request and its provenance.

**Router.** The seat the vision calls a core competence: "the
interruption medium is itself a decision the AI makes." The router
reads records addressed to the resident — results, questions from any
seat, anything initiated — together with the resident model and (later)
sensors, and decides *channel and timing*: interrupt now, defer to a
visible moment, fold into the digest, stay silent. Its one hard
obligation: **no routing without an appended decision record citing
its evidence.** A worker that needs the resident's input mid-errand
does not get to interrupt either — it appends a `question` record, and
the router decides when and how that question reaches a human. The
question economy is a property of the plumbing, not a policy anyone
must remember.

**Worker.** Executes errands. Its contract sits at the *errand
boundary*, never the model-call boundary: a `request` record in; a
`result` record, a diff against the relevant repo, and journal entries
out. Inside the seat the harness is free — which is what lets a human
drive the seat manually before any harness exists, and lets the
harness be replaced without the structure noticing.

**Sensors.** Answer one question for the router: may I interrupt, and
is it worth it. Raw sensor streams live in a ring buffer that answers
"right now" and forgets; an observation becomes durable only by being
cited as evidence in a decision (Proposal 04). Each sensor is
individually revocable, and a revoked sensor degrades the router
toward conservatism — interrupt less, batch more — never toward
breakage. No sensors exist in the first slice.

**Digest** (a surface). A fold over the journal rendering "what
happened, and why" for a period. This is where `initiated` work
reports by default, and where "check in later" lives.

**The resident model** is not a seat — it is an artifact the router
and workers read: the system's accumulated understanding of the
resident, one entry per fact, each entry carrying its provenance
(Proposal 05). It is the private layer's "agent's accumulated model of
its user" slot (Principle 01) given a concrete shape.

## Provenance

`requested` versus `initiated` is the router's primary input.
Requested work carries an implicit "tell me": its result must reach
the resident through some channel they will actually encounter.
Initiated work defaults to the digest and has to *earn* an
interruption. This single field does more channel-selection work than
any estimate of salience, and unlike salience it is a fact, not a
judgment.

## Where runtime state lives

The journal and the resident model are plain text in the **private
repo**, under a `state/` directory: Nix declares the slot and the
schema, git carries the contents, and neither is in the derivation
path — runtime state can change without a rebuild, and a rebuild
never contains a person (Principle 02).

Private-repo-tracked rather than machine-local is a deliberate
durability decision: the accumulated model and journal are the most
valuable artifacts on the machine and the least reproducible. They
must survive a reinstall, move to the next machine, and survive a
*model* transition — two years of elicited preferences and decided
outcomes should be exactly what a successor intelligence reads on day
one. They are portable precisely because no model's format is
load-bearing (Proposal 03).

Two consequences, recorded here until the authority taxonomy exists
as its own document:

- The agent committing to the private repo is a **standing
  authority** — the first entry in the authority taxonomy, in the
  made-then-reported category: commits are routine, and the diff is
  part of the audit trail.
- The push cadence (and the credential that enables pushing from a
  host) is an open design item; until secrets tooling lands, commits
  may be local-only with pushes left to the resident.

## Capability tiers

Seats declare the minimum capability they need; hosts declare the
tiers available to them. The fallback chain for a seat that cannot be
filled at its tier ends at **"seat empty, and the resident is told"** —
never at a weaker tenant faking a seat it cannot hold. A local model
that can render digests but cannot do configuration surgery holds the
digest seat and leaves the worker seat empty, and the system says so.
The concrete tier configuration format is deliberately unspecified
until a second tenant actually exists; inventing it earlier would be
speculation.

## Proposed commitments

### Proposal 03 — Intelligence is a tenant, not a structural member

**Statement.** The system's structure — records, journal, schemas,
slots, the escalation grammar — is plain text and contains no model.
Every agent role is a seat defined by the artifacts it reads and
writes; any intelligence that can read and write them can hold the
seat.

**Teeth.**

- Contracts sit at the errand boundary, not the model-call boundary.
  Inside a seat, the harness is free; outside it, only records exist.
- **The machine with every seat empty is a complete NixOS system.** No
  model in the boot path, login path, network path, or rollback path —
  the four things that make a machine reachable. Losing every model
  loses the assistant, never the computer.
- Degradation is tiered and honest (see Capability tiers): the chain
  ends at an empty seat and a told resident, never a faked seat.
- No harness feature may be load-bearing: session transcripts are not
  memory, a context window is not the state store.

**Cost.** Convenient harness capabilities must be reproduced as
artifacts even when a harness offers them natively, and mid-errand
interactivity must go through the bus rather than a direct prompt.

**Hardening test.** CI exercises the full loop with scripted tenants
in every seat — zero models, zero network. The VM host builds and
passes the install harness with no agent layer at all. And at least
one seat is successfully re-tenanted (a different model or harness)
with no structural change.

### Proposal 04 — Decisions are durable; observations are ephemeral

**Statement.** Every decision any seat makes is an appended,
inspectable record carrying its own reasoning and **citing its
evidence** — concretely ("he locked and unlocked the screen within a
minute"), not impressionistically ("seemed busy"). Raw observation
streams are ring-buffered and forgotten: an observation persists only
by being cited in a decision that relied on it.

**Teeth.** `evidence` is a required, mechanically-checked field on
decision records. Sensors are individually revocable and degrade the
system toward conservatism. The journal is private-layer data, always.

**Cost.** Stated honestly: nothing can be retro-audited beyond the
cited evidence. If a rationale was wrong, the raw stream that would
prove it is gone; the error is detectable only as a pattern of
outcomes at the weekly audit. That trade is what keeps the journal an
audit log of judgments rather than a surveillance record, and what
makes it safe to version in a private repo.

**Hardening test.** The corpus proves sufficient: a resident profile
can be usefully (re)derived from journal plus model alone, and the
weekly audit works from citations alone. If lived use shows a
successor model or the audit genuinely hobbled by the missing raw
stream, the proposal was wrong — and this document says precisely
where.

### Proposal 05 — Inference may open a question; only the resident may close it

**Statement.** Every entry in the resident model carries provenance:
what was asked, what was answered, when. Behavioral signal may raise a
question's priority or mark an entry stale — it may never write or
revise an entry.

**Teeth.** The erosion edge, named in advance: implicit action is not
statement. The resident rolling back the same kind of change twice
earns the system a *question* ("you've undone this twice — should I
stop?"), never a model write. This is where the principle will erode
first if it erodes, and the erosion path ends at what the vision calls
"a feed algorithm with root access."

**Cost.** The system stays wrong longer than a behavioral learner
would, and the apprenticeship period is chattier — which the vision
already endorses: the early questions *are* the model-building. A
competitor system will look smarter in week one; this one has to be
trustable in year five.

**Hardening test.** After the apprenticeship period, every model entry
traces to an explicit exchange, and the audit shows question frequency
declining while decision accuracy holds. If accuracy can only be
bought by silently learning from behavior, the proposal failed.

## Relation to the vision

`docs/vision.md`'s architecture paragraph originally named Claude Code
as the acting layer. Under Proposal 03 that is a category error the
project no longer makes: Claude Code is the *current tenant* of the
worker seat — the best available today, replaceable tomorrow, and
required never. The vision text has been adjusted to match; the
founding reasoning is unchanged.
