# The agent layer — architecture

*Castle Turing — how the agent layer is put together: the seats
intelligence occupies, the plain-text artifacts they communicate
through, and where runtime state lives. This document also carries the
project's **proposed commitments** — principle-shaped decisions being
tested by implementation before formal adoption. Per CLAUDE.md, drafts
never enter `docs/principles/`; a principle doc is a commitment. A
proposal is promoted to a numbered principle only after implementation
has leaned on it and it held, and each proposal below states the
hardening test that decides that. Proposals 03–05 were proposed with
task 0008; Proposal 06 came out of asking what an outcome actually is —
task 0010 built its verdict half, and its audit mechanics were revised
against the measurement-and-oversight literature before any audit
existed to harden.*

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
- `type` — `request`, `decision`, `result`, `question`, `answer`,
  `correction`.
- `provenance` — `requested` (the resident asked for this) or
  `initiated` (the system undertook it on its own). See below.
- `refs` — ids of the records this one responds to.
- `seat` — which seat wrote it.
- `created` — timestamp.

Decision records carry one more required field: `evidence` (see
Proposal 04). The body carries the prose — a request's description, a
diagnosis, a decision's rationale.

A `correction` (docs/tasks/0010-correction-record.md) is the resident
speaking unbidden — not asking for anything, not answering a question
the system posed, but volunteering a judgment about how the system is
doing. It carries `provenance: requested` and `seat: intake` like any
other resident word entering through that seat, plus one mechanical
field, `surface` (`cli` or `modal`), and a handful of `context-*`
fields stamped at write time from what the journal showed at that
instant — never a causal claim, only what was true then (see
`agent/README.md` for the exact fields). It is the durable half of
Proposal 06's verdict; the resident-model entry it also produces is the
half the router actually reads.

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
record. The first intake was a CLI (`castle ask`); a compositor
keybinding opening a modal — `agent/castle-modal`, bound to
`$mod+Shift+space` in `modules/home`'s Sway config, docs/tasks/0009 —
is the second, and eventually mail or calendar will be later ones. The
modal doubles as the "come back and check in later" surface: its status
mode folds recent errands from the journal, the same fold `castle
digest` does, without waiting for a digest period to end. An intake
adds no judgment — it captures the request and its provenance.

The same surfaces also take a second kind of speech: a `correction`,
the resident volunteering how the system is doing rather than asking
for anything (`castle correct`; the modal's compose mode, after one
plain-language keypress — docs/tasks/0010-correction-record.md). Intake
stays judgment-free either way — the resident classifies which kind of
speech this is, the surface never guesses — and transcription is
mechanical and verbatim: no seat paraphrases a correction, at write
time or ever.

**Router.** The seat the vision calls a core competence: "the
interruption medium is itself a decision the AI makes." The router
reads records addressed to the resident — results, questions from any
seat, anything initiated — together with the resident model and (later)
sensors, and decides *channel and timing*. Two channels exist today:
**notify** — a real interruption, `notify-send` through mako
(`modules/desktop`), for `requested` work — and **digest** — folded
into the next digest read, for `initiated` work (see Provenance,
below). Its one hard obligation: **no routing without an appended
decision record citing its evidence.** A worker that needs the
resident's input mid-errand does not get to interrupt either — it
appends a `question` record, and the router decides when and how that
question reaches a human, through the same two channels. The question
economy is a property of the plumbing, not a policy anyone must
remember.

**Worker.** Executes errands. Its contract sits at the *errand
boundary*, never the model-call boundary: a `request` record in; a
`result` record, a diff against the relevant repo, and journal entries
out. Inside the seat the harness is free — which is what lets a human
drive the seat manually before any harness exists, and lets the
harness be replaced without the structure noticing.
`castle.agent.worker.command` (`modules/agent`) names whatever holds
this seat — a headless `claude -p` by default (`agent/castle-worker-claude`,
docs/tasks/0009). One product-level constraint holds regardless of
tenant: **the worker proposes a diff; it never deploys.** No
`nixos-rebuild`, no `git commit`, no applying anything to a running
system, from this seat, in this slice — applying a reviewed diff stays
a resident action. Autonomous deployment is a real authority-taxonomy
question for a later task, not a side effect of this one.

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

### Proposal 06 — The system may grade its own delivery; it may never grade its own judgment

**Statement.** An outcome comes in two kinds, with unequal authority. A
**receipt** is the reception of an intervention — dismissed, acted on,
left untouched — observed only through the surface that delivered it,
within a window the deciding record declared in advance. A **verdict**
is a resident-authored judgment: an audit answer, a volunteered
correction, a keep-or-rollback. Receipts may inform; only verdicts may
settle. The system may grade how well it delivered; it may never grade
whether it was right.

**Why the split is the whole point.** Receipts are cheap, continuous,
and machine-observable; verdicts are expensive, sparse, and
authoritative. Every system that has gone wrong here went wrong the same
way: it promoted receipts to verdicts, because receipts were the ones it
could get for free. That promotion *is* the mechanism of the feed
algorithm — revealed behavior, harvested continuously, treated as ground
truth. The design problem was never "how do we get labels." It is "how
do we keep the two kinds from contaminating each other."

When first drafted, that was an argument from design history. It is now
the best-evidenced claim in this document. The field that spent two
decades learning from clicks has published its own reckoning:
state-of-the-art click debiasing, applied across more than a billion
sessions, improved click prediction without improving relevance (Hager
et al. 2024) — the receipts got better at predicting receipts. And the
gap is not noise that more data averages away: inferring what someone
values from how they behave is formally sign-indeterminate — the same
observed behavior is consistent with opposite underlying preferences
(Kleinberg, Mullainathan & Raghavan 2023). A system that promotes
receipts to verdicts is not taking a shortcut to the truth; there is no
road from the one to the other.

**Teeth.**

- **Decisions declare a falsifier, not a metric.** Every decision record
  carries one line stating what would make it wrong, mechanically
  checked for non-emptiness the way `evidence` already is.
  `unobservable — audit only` is a valid value; blank is not. Requiring
  a *measurement* instead would force one of two bad moves: building
  instruments (surveillance) or inventing metrics that measure nothing
  (engagement theater). Falsifiability gets the discipline — a seat must
  articulate its own failure condition at write time — without either.
- **An intervention may watch its own splash; it may never leave a tap
  running.** Observing the response to a notification the system itself
  rendered is not surveillance: it is the return half of a round trip
  the system started. Anything beyond that surface and that window must
  be declared in the decision record *before* acting. Undeclared or
  unbounded post-intervention observation is a violation. Sensors answer
  "may I interrupt"; they are never outcome instruments.
- **Receipts accumulate into questions — and question selection is
  itself a decision.** Receipts never write the resident model, never
  mark a decision right or wrong, never create or remove a rule about
  whether something is communicated. Four dismissed morning digests earn
  the system a question ("move it to evening?"), never a silent
  adjustment — Proposal 05's grammar extended from the model to the
  router. But the question channel is not the firewall it looks like: at
  the label volumes this system runs on, *which* question gets asked
  shapes the verdict corpus more than how many questions do (the
  organizing premise of the active-learning literature; Settles 2009),
  so
  receipt-driven curiosity is agenda-setting power over ground truth —
  one indirection removed, not removed. Two guards, not a prohibition:
  promoting a receipt pattern into an audit question is itself a
  journaled decision citing the receipts it rests on; and the audit's
  sample mixes uniform-random draws with receipt-driven ones, each
  labeled as which, so the query distribution's bias is a measured
  quantity instead of an invisible one. The uniform half also keeps
  feedback arriving on the decisions the system actually makes, not
  only the ones it finds interesting.
- **The audit judges blind, then sees the outcome, and both are
  logged.** Identical decisions are rated better when they happened to
  turn out well — by judges explicitly instructed to ignore outcomes
  and sincerely convinced they had (Baron & Hershey 1988, still
  replicating) — and manipulations designed to remove hindsight bias
  reliably fail to remove it (Guilbault et al. 2004, across
  ninety-five studies). No audit design eliminates this; a design can
  only measure it. The audit records the resident's verdict on a
  decision *before* revealing how it turned out, then records whether
  the verdict flipped. The divergence is our own outcome bias, in a
  column. Honest limit: this works only for outcomes the resident has
  not already lived — an interruption's outcome arrived with the
  interruption — so the measured divergence is a floor, not the whole
  bias.
- **The audit stream is salted with synthetic known-bad decisions at a
  controlled, logged rate.** Vigilance collapses when targets are rare:
  miss rates climb from under ten percent toward forty as target
  prevalence falls (Wolfe, Horowitz & Kenner 2005) — so a naive audit
  gets *less* sensitive exactly as the router gets better. Raising the
  effective prevalence artificially is the one manipulation reliably
  known to counter this, and it is deployed practice, not theory:
  airport screening projects synthetic threats into real bags for
  precisely this reason. Three disciplines keep the mechanism honest.
  *Salt is indistinguishable on its surface*: it carries the same
  fields, the same constant falsifier text, the same shape as the real
  decisions beside it — what is known in advance is that a salt
  decision *fails* its own falsifier check, because the evidence it
  cites contradicts the routing it made. Catching it requires actually
  performing the check, which is the very work being calibrated; salt
  an auditor could spot by field inspection would measure nothing (see
  the weak point below for what this does and does not fix). *Salt
  never masquerades in the journal*: it exists nowhere as a
  freestanding decision record — it appears only inside the audit's
  own journaled record, labeled as salt, which lists what was shown,
  what was salt, and what was caught. A successor tenant reading the
  corpus meets salt only under that label, and the sensitivity series
  is as durable as any other judgment (Proposal 04 intact on both
  counts). *The floor is pre-registered*: the detection floor and the
  salt rate are declared in the audit surface's configuration before
  the first salted audit runs, and changing either is a journaled
  decision — a floor chosen after seeing the detection rate is not a
  floor.
- **Missing labels degrade the router toward conservatism** — interrupt
  less, ask smaller — never toward learning from receipts instead.

**On the clause deliberately left out.** An earlier draft let receipts
tune "salience-neutral delivery mechanics" — batching, timing within an
already-granted window. It is cut. The line between *how* something
lands and *whether* it lands is not crisp: a notification batched into
tomorrow's digest was, functionally, not communicated today. Every other
proposal here was written strict and can be loosened once lived use
argues for it; this one starts at receipts-inform-questions-only and the
mechanics clause has to earn its way in.

**Cost, stated honestly.** The system stays miscalibrated between
audits, and learning is bottlenecked on the resident's audit attention:
skip the audits and it does not quietly degrade into a behavioral
learner, it simply stops learning. Most decisions will die unlabeled —
and the cruel structural fact underneath that cannot be engineered
away: this system's *best* outcomes look like nothing, and being
ignored also looks like nothing. Two harder costs, learned from the
oversight literature rather than guessed. First, audit sensitivity and
router quality pull against each other by construction — the better
the router, the rarer the real error, the higher the auditor's miss
rate — so the safety mechanism is least sensitive exactly when trust
in the system is highest, and only the salt floor keeps that
measurable rather than assumed. Second, the documented failure mode of
human-oversight regimes is not that review catches too little but
that it *legitimizes*: across dozens of studied policies requiring
human oversight of algorithmic decisions, the reviewers could not
perform the oversight assumed, while the requirement itself lent the
overseen systems a false sense of security (Green 2022). An audit
that catches nothing licenses everything; unsalted, this proposal
would be that pattern wearing a principle's clothes. What the
evidence supports unchanged is the founding commitment itself —
batched review beats in-the-moment confirmation, because confirmation
prompts habituate to click-through within a few exposures (Akhawe &
Felt 2013, across twenty-five million warning impressions). Within
batching, *cadence* is the parameter the evidence actually attacks:
the vision's "weekly" is an opening value, not a commitment — a
shorter batch raises per-audit prevalence and shrinks the share of
outcomes already lived before judgment, which is exactly the share
blind-then-reveal cannot measure. The open parameter work (cadence,
the floor and rate values, an audit cost budget) lives in
`docs/backlog/weekly-audit-vigilance.md`. It is the naive batched
audit — outcome-visible, unsalted, sensitivity assumed — that the
research demolishes, and this revision is what remains after taking
that seriously. A competitor optimizing on receipts still calibrates
in a week.

**Sequencing.** The verdict half is built
(`docs/tasks/0010-correction-record.md`): `correction` records,
`castle correct`, and verbatim resident-model entries with
`volunteered` provenance, each stamped with filing-time context. The
receipt half still waits for a delivery surface that can actually
report reception — mako cannot distinguish dismissed from expired —
and speculative receipt infrastructure stays unbuilt until one
exists. Decision records also need the fields that keep a logged
decision counterfactually evaluable — the considered set, and the
propensity with which the chosen option was selected (Bottou et al.
2013) — a schema change tracked separately; see
`docs/backlog/citation-only-evidence.md` for the research note it
rides with. The next buildable piece is the audit surface
itself, and it must be built to this proposal's shape from its first
version: blind-then-reveal ordering, labeled mixed sampling, salt.

One adjacent gap this proposal points at without owning: grading
delivery only matters if there is a delivery option worth choosing,
and a roster of `notify`, `digest`, and implied silence is
impoverished. The reviewed evidence runs against pure silence —
suppression without an ambient alternative produced no measured
concentration benefit while raising anxiety and compulsive
checking — and toward a glanceable, zero-commitment channel as the
default resting place for most information. That is router and
channel work, deferred with its evidence to
`docs/backlog/ambient-default-channel.md`, not outcome-measurement
work for this proposal.

**Hardening test.** Duration was the wrong pass criterion — an audit
that runs in ten minutes and catches nothing has passed a test of
nothing. After a quarter of lived audits, sensitivity is what is
measured, against parameters fixed in advance: the salt detection
rate holds above its pre-registered floor as the router improves — if
it falls through, the audit has become legitimation, and this
paragraph says so. Blind-then-reveal divergence is logged wherever an
outcome was on record to reveal — if verdicts routinely flip on
reveal, the training signal is outcome noise and the proposal's
central claim fails. Every change in routing behavior traces to a
verdict or an explicit answer, none to receipts alone. The audit
sample is uniform-random by default; from the day receipt-driven
draws exist (none can before a delivery surface reports reception),
each traces to a journaled selection decision and carries its label —
a receipt-less quarter satisfies this vacuously, and the audit
records say so rather than leaving it ambiguous. At least one
volunteered correction has traversed correction → model entry →
visibly changed routing, cited end to end. And duration is still
recorded in every audit's own record — demoted from pass criterion to
tracked cost, because time-on-task fatigue is itself a sensitivity
threat: an audit that must grow ever longer to hold its floor is
failing differently, and the record has to show it. If calibration
demonstrably cannot be bought without promoting receipts to verdicts,
the proposal was wrong, and this paragraph says where.

**Known weak point.** The falsifier requirement remains schema
discipline rather than principle, and salting resolves only half of
its problem. The half it resolves: the falsifier now names a check
the audit actually performs — salt is constructed to fail its own
falsifier, and catching that failure is the auditor's measured
task — so the concept no longer waits for the router's second rule to
mean anything. The half that stands: the router's rule set is still
provenance alone, so every falsifier on a *real* decision is still
the same sentence, and a required field with one constant value is
still ritual on those records — which is also why salt can share that
constant text and stay surface-indistinguishable at all. That may yet
be evidence that the router writes too many decisions — one per
routed record — where it should write fewer and coarser ones.
Unresolved on purpose, and now narrowed: it is a question about
decision granularity, no longer about whether falsifiers earn their
keep.

## Relation to the vision

`docs/vision.md`'s architecture paragraph originally named Claude Code
as the acting layer. Under Proposal 03 that is a category error the
project no longer makes: Claude Code is the *current tenant* of the
worker seat — the best available today, replaceable tomorrow, and
required never. The vision text has been adjusted to match; the
founding reasoning is unchanged.
