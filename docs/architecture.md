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
existed to harden. Proposal 07 came out of asking how a seat changes
hands, and is not yet implemented by anything.*

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
  `correction`, `claim`.
- `provenance` — `requested` (the resident asked for this) or
  `initiated` (the system undertook it on its own). See below.
- `refs` — ids of the records this one responds to.
- `seat` — which seat wrote it.
- `created` — timestamp.

Decision records carry one more required field: `evidence` (see
Proposal 04). The body carries the prose — a request's description, a
diagnosis, a decision's rationale.

`castle route` also stamps every decision it writes with `considered`
(the channels it evaluated) and `propensity` (the probability its
policy would make that choice in that context — how likely the policy
was to choose it, not how sure anyone is that the choice was right) —
the considered-set and selection-propensity pair counterfactual
off-policy evaluation needs (Bottou et al., JMLR 14, 2013), written now
for corpus continuity since the journal is append-only and cannot be
backfilled later. Unlike `evidence`, neither is required on records
that predate this addition; see `agent/README.md` for the fields, the
honest limits of what they buy under today's deterministic rule, and
why they're optional rather than required.

A `claim` (docs/tasks/0021-auto-dispatch.md) is written the instant a
worker takes an errand — before the tenant command is even resolved.
It exists for observability across a restart, never for mutual
exclusion: exclusion comes free from an `flock` lease under
`$XDG_RUNTIME_DIR`, and that lease dies with the login session, so
without a durable record an interrupted turn would be
indistinguishable from an untouched one. With it, three states are
distinguishable cold: claim plus live lease (running now), claim with
no live lease and no result (interrupted, and reapable), no claim at
all (nothing has ever touched this errand). `result` records written
from that task forward also carry `outcome` — `completed`, `failed`,
`timeout`, or `interrupted` — because the exit code exists nowhere
else once the process is gone, and no surface may ever infer failure
by grepping a body for prose like "FAILED".

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
keybinding opening a modal — `agent/castle-modal`, bound to a fixed
`Mod4+Shift+Return` (not `$mod`-relative — deliberate, docs/tasks/0019)
in `modules/home`'s Sway config, docs/tasks/0009 — is the second, and
eventually mail or calendar will be later ones. The
modal doubles as the "come back and check in later" surface: its status
mode folds recent errands from the journal, the same fold `castle
digest` does, without waiting for a digest period to end. An intake
adds no judgment — it captures the request and its provenance.

The same surfaces also take a second kind of speech: a `correction`,
the resident volunteering how the system is doing rather than asking
for anything (`castle correct`; the modal's compose mode, after one
plain-language keypress — docs/tasks/0010-correction-record.md). And a
third: closing a `question` the system opened, which is the modal's
answer mode (`Mod4+Shift+a`, docs/tasks/0022-answer-in-ui.md) and
`castle answer` underneath it — the resident picks a pending question
out of a plain-language list and answers it in their own words, with no
record id typed or shown, because a question economy that costs the
resident the system's internal vocabulary to participate in is one they
will stop participating in. Intake stays judgment-free through all
three — the resident classifies which kind of speech this is, and
chooses which question they are closing; the surface never guesses —
and transcription is mechanical and verbatim: no seat paraphrases a
correction, at write time or ever.

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
`result` record, a diff against a checkout the worker itself names,
and journal entries out. Since docs/tasks/0024-config-target.md that
checkout is one of two the seat may be configured with — the
resident's private configuration repository and, optionally, a
checkout of this public framework — and a host may configure either,
both, or neither, with the result record carrying which one its diff
is against. Inside the seat the harness is free — which is what lets a human
drive the seat manually before any harness exists, and lets the
harness be replaced without the structure noticing.
`castle.agent.worker.command` (`modules/agent`) names whatever holds
this seat — a headless `claude -p` by default (`agent/castle-worker-claude`,
docs/tasks/0009). One product-level constraint holds regardless of
tenant: **the worker proposes a diff; it never deploys.** No
`nixos-rebuild`, no `git commit`, no applying anything to a running
system, from this seat, in this slice — applying a reviewed diff stays
a resident action. **Since docs/tasks/0048-activation.md a switch can
be performed by the machine, and that changes nothing about this
sentence**: it is a different seat, unreachable from a worker turn,
spending an authorization the resident granted on a screen of its own.
Autonomous deployment — a switch with no per-change approval behind it
— remains a real authority-taxonomy question for a later task, and is
not something this one grants. Since
docs/tasks/0021-auto-dispatch.md the seat's *invocation* can be
automatic — a resident who opts into `castle.agent.dispatch.enable`
has filed requests start themselves — and that changes nothing about
the constraint: the worker proposes and never deploys regardless of
who or what invoked it, and an automatically-started errand keeps the
provenance of whoever wanted the work. Since
docs/tasks/0023-resume-cold.md that contract describes one *turn*
rather than necessarily a whole errand: a worker that cannot proceed
without the resident's judgment marks its question as blocking and
stops, and answering it makes the errand eligible for one further turn,
each turn producing its own account. The turns are chained by the
answer that resumed the next one, named in that turn's own `claim`
record — which is what makes a given answer produce exactly one
resumption and never a second. The resumed tenant is a fresh one with
no memory of the earlier turn: it is handed that errand's own records
and nothing else, which is Proposal 03's "no harness feature may be
load-bearing" applied to continuity. An answer closes a question; it
grants no authority, and a resumed turn proposes and never deploys
exactly like a first one.

**Dispatch** (plumbing, not a reasoning seat). The mechanism that
invokes the worker seat on the journal's behalf: it notices that an
eligible request exists, runs one worker turn at a time, and runs the
router once afterward. It holds no judgment of its own and chooses no
tenant. Which request runs next is a total function of the journal —
the eligibility fold plus oldest-first order — reconstructable exactly
by re-running that fold over the same snapshot, which is why dispatch
writes no decision record per errand: a record carrying identical
evidence text on every invocation forever is ritual, not
accountability. The one record it writes about itself is a watermark,
marking the instant automatic dispatch began existing on this journal
and naming, in its own `refs`, the requests outstanding at that moment
— which are the ones it will not start on its own. Both halves are
there because nothing else can recover either fact: not when dispatch
began, and not which errands predate it. `seat: dispatch` is a
new value in an existing category, not a new category — `digest` is
already a non-reasoning surface seat. Giving dispatch a policy for
*which* eligible request to run, or a say in whether to run one at
all, would make it a reasoning seat; that is precisely what this
paragraph exists to stop a later agent from "completing" it into.

**Applier** (plumbing, not a reasoning seat). The mechanism that spends
one recorded approval: it makes the exact change a resident authorized
in the resident's own configuration checkout and commits it there,
naming the authorization in the commit message. It **activates
nothing** — no rebuild, no new generation, no change to the running
system — it **pushes nothing**, and it never writes a checkout of this
framework, which it refuses by name rather than by error. That refusal
is a backstop rather than a path anything routes into: a turn whose diff
is against this framework files no approval at all and travels the
outbox instead, so nobody is asked to authorize a change this machine
could never spend. It stays, and stays exact, because journals are
append-only and proposals of that shape already sit in them, decided and
undecided. Every apply spends exactly one `answer` record, whose
question said at the moment it was shown that approving authorizes
this; an approval granted under
any earlier wording is inert forever, by construction, because the
scope of an authority is what the person was told when they granted it.
`seat: applier` is a new value in an existing category, not a new
category, exactly as `dispatch` was — and it is a distinct name from
`worker` because a seat is what reads and writes, and this one writes a
resident's repository, so "which seat touched my configuration" has an
answer. Like dispatch, what it does is a total function of the journal
and the tree. Giving it a policy about which approvals are worth
applying, or a say in whether to apply one at all, would make it a
reasoning seat; that is precisely what this paragraph exists to stop a
later agent from "completing" it into.

**Outbox** (plumbing, not a reasoning seat). The mechanism that carries
a worker's finding out of the OS: when a turn reports something wrong
with this framework rather than with the resident's configuration, it
commits that report as a backlog entry on a fresh branch in a checkout
of this framework, if one is configured. When the turn also wrote the
fix, that diff rides the same entry as a **candidate patch quoted for
review — never the patched code**, because a change to this framework
lands through a written brief and a review like any other, and an outbox
that committed the change applied would be a back door around that,
opened by a machine. It is a total function of the
turn's outputs and the tree — the same finding and the same checkout
produce the same branch, reconstructable by re-running it — and it
holds no judgment of its own: it does not decide whether a finding is
worth filing, does not read it for quality, and runs no tenant. It
**activates nothing**, it **pushes nothing**, it never writes `main`,
and it never touches the branch the resident has checked out; where the
applier refuses over uncommitted resident work, this refuses the same
way and by name. Nothing it does needs a per-change authorization,
because nothing it does changes a running system: what it produces is a
branch nobody has merged, and the resident's judgment is spent once, at
the pull request, rather than twice. `seat: outbox` is a new value in
an existing category, as `dispatch` and `applier` were, and it is a
distinct name for the same reason the applier's is — this one writes a
checkout, so "which seat touched my repository" has an answer. Giving
it a policy about which findings are worth landing, or a say in whether
to land one, would make it a reasoning seat; that is precisely what
this paragraph exists to stop a later agent from "completing" it into.

**Builder** (plumbing, not a reasoning seat). The mechanism that
notices this machine is owed a build and makes one: either because the
applier has just moved the resident's configuration repository, or
because the framework revision that repository pins has fallen behind
the one the machine's framework checkout last fetched. It **fetches
nothing** — `origin/main` here means what the last fetch saw, the
outbox's rule verbatim — it writes no checkout, and it **activates
nothing**. A failed build files an honest result and asks nothing; a
clean one files a question. Nothing it does needs an authorization,
because **a build changes nothing**, and a question whose only honest
answer is yes is a question that teaches a resident to stop reading
questions. `seat: builder` is a new value in an existing category, as
`dispatch`, `applier` and `outbox` were. Giving it a policy about which
triggers are worth building, or a say in whether to build at all, would
make it a reasoning seat; that is precisely what this paragraph exists
to stop a later agent from "completing" it into.

**Activation** (plumbing, not a reasoning seat). The mechanism that
spends one recorded approval on the running system: it writes and
commits the framework pin the resident authorized, if the approval was
for one, and then asks this machine to switch to the configuration that
produces. It is the first thing in this architecture that changes the
machine rather than a file, and the only one — it **pushes nothing**,
it never writes a checkout of this framework, and it activates exactly
one approval at a time. Every switch spends exactly one `answer`
record, whose question said at the moment it was shown that approving
switches the running system to the build described below; an approval
granted under any other wording is inert forever, by construction, for
the reason the applier's paragraph gives. After a switch it opens a
**health window**: a question asking whether the machine is working,
and a bounded deadline after which, with no confirmation, it rolls back
to the previous generation. That is the one thing in this system that
decides without the resident, and the asymmetry is why — a good
generation rolled back costs one cheap re-approval, a bad generation
left running costs a physical trip to the machine. `seat: activation`
is a new value in an existing category, and a distinct name from
`builder`'s for the same reason the applier's is distinct from the
worker's: a seat is what reads and writes, and "which seat changed the
machine I am using" must not have the same answer as "which seat
compiled something". Giving it a policy about which approvals are worth
spending, or a say in whether to spend one at all, would make it a
reasoning seat; that is precisely what this paragraph exists to stop a
later agent from "completing" it into
(`docs/tasks/0048-activation.md`).

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
layer**, under a `state/` directory: Nix declares the slot and the
schema, git carries the contents, and neither is in the derivation
path — runtime state can change without a rebuild, and a rebuild
never contains a person (Principle 02). Which repository that
directory belongs to is a layout choice with a security consequence,
because evaluating a flake copies its tracked tree into the
world-readable Nix store — see `docs/private-layer.md`'s "The agent's
state" for the two layouts this project recommends and why a
subdirectory of the flake repo is not one of them
(`docs/tasks/0030-state-outside-the-flake.md`).

Git-tracked rather than machine-local is a deliberate durability
decision: the accumulated model and journal are the most valuable
artifacts on the machine and the least reproducible. They must
survive a reinstall, move to the next machine, and survive a
*model* transition — two years of elicited preferences and decided
outcomes should be exactly what a successor intelligence reads on day
one. They are portable precisely because no model's format is
load-bearing (Proposal 03).

Two consequences, recorded here until the authority taxonomy exists
as its own document:

- The agent committing to the private repo is a **standing
  authority** — the first entry in the authority taxonomy, in the
  made-then-reported category: commits are routine, and the diff is
  part of the audit trail. Note that the applier
  (`docs/tasks/0026-apply-validate.md`) does **not** rely on this
  sentence and this bullet is unamended by it: every commit that task
  makes is authorized *individually*, by a specific answer record the
  commit message names, under a screen that says in capitals what
  approving authorizes. A per-change authorization needs no standing
  one — which matters, because the only document that scopes this
  standing authority scopes it to whichever repository holds `state/`
  (docs/private-layer.md), and under the recommended layout that is a
  different repository from the config repo the applier writes.
- The push cadence (and the credential that enables pushing from a
  host) is an open design item. Secrets tooling has landed since this
  was written (docs/tasks/0031-secrets-tooling.md), so such a
  credential now has somewhere to live — but nothing has decided what
  it is, what it may push to, or what an unattended push is allowed to
  do with nobody watching, which is an authority question rather than a
  storage one. Commits stay local-only, with pushes left to the
  resident, until that is answered.
- Activation (`castle.agent.activation.enable`,
  docs/tasks/0048-activation.md) is a **standing authority** and the
  first one in this project that is a **standing root grant**: it
  declares two privileged systemd units, carrying `nixos-rebuild switch
  --flake <repo>#<host>` and `nixos-rebuild switch --rollback` and no
  argument reaching them from anywhere, and a polkit rule permitting one
  named account to start exactly those two. Since
  docs/tasks/0057-the-privileged-switch-cannot-read-the-repository.md it
  also declares a third, smaller thing without which the first two do
  not work: a `safe.directory` entry in the system git config naming
  exactly the configured repository, because a switch running as root
  is otherwise refused read access to a repository the resident owns.
  That entry grants no authority the ExecStart line above it did not
  already grant — the unit's purpose is to activate that repository's
  configuration as root — and it names one path, not a pattern. What is
  standing is the
  *ability to be asked*; every individual switch is still authorized
  one at a time, by a specific answer record, under a screen that says
  in capitals what approving does — so the applier bullet's "a
  per-change authorization needs no standing one" does not apply here,
  and this needs both. Which taxonomy category the grant belongs in is
  deferred to the authority-taxonomy task exactly as the bullets above
  defer; what is settled now is that it is off unless a resident turns
  it on, that its scope is two commands, and that a switch nothing
  confirms is undone rather than kept.
- The worker's product-level constraint is unchanged by any of this.
  The worker proposes and never deploys; what changed is that a
  *separate* seat can now deploy, on a resident's individual say-so, and
  no tenant can reach it — `castle build` and `castle activate` both
  refuse outright from inside a worker turn, by the same environment
  check `castle apply` uses.
- Automatic dispatch of resident-filed errands
  (`castle.agent.dispatch.enable`, docs/tasks/0021-auto-dispatch.md) is
  a **standing authority** too: opt-in and default-off, because it lets
  a tenant start work — and spend money — with no human present at the
  moment it happens. Which taxonomy category it belongs in (silent /
  made-then-reported / queued-for-approval) is deliberately deferred to
  the authority-taxonomy task, the same way the two bullets above defer
  the private-repo-commit authority; see
  `docs/backlog/authority-taxonomy-prior-art.md`. What is settled now:
  it is off unless a resident turns it on in their own private layer,
  and every turn it starts leaves a claim record and a result behind.

## Seat occupancy

Seats declare the minimum capability they need; hosts declare the
tiers available to them. The fallback chain for a seat that cannot be
filled at its tier ends at **"seat empty, and the resident is told"** —
never at a weaker tenant faking a seat it cannot hold. A local model
that can render digests but cannot do configuration surgery holds the
digest seat and leaves the worker seat empty, and the system says so.

A tenant is anything that satisfies the seat's contract, and the range
is wider than "which model":

- a **deterministic rule** — `cmd_route`'s provenance rule is one, and
  for decisions whose rule can be written this is the *best* tenant, not
  a placeholder: auditable, free, instant, and its failure modes are
  enumerable rather than emergent;
- a **frontier model** behind a harness, where the judgment genuinely
  cannot be written down;
- a **local or fine-tuned model**, chosen for latency, cost, or privacy;
- a **fallback chain** of the above, so a network outage or a crashed
  local model degrades the system rather than stopping it;
- a **human**, which is how every seat here was first held.

Two arrangements run more than one tenant at once, and they answer
different questions. **Ensemble** runs several and merges their output
into one answer — it buys accuracy at N× cost and latency per decision
and needs a merge rule someone has to defend, which is poor value for a
router whose decisions are constant and whose best output is silence.
The exception is review, where the *unmerged* ensemble is the whole
point: two models reading the same diff, both outputs shown, because the
disagreement is the signal. **Shadow** runs a candidate alongside the
incumbent, records what it *would* have done, and acts on the incumbent
— no merge rule, no latency cost, and it produces the evidence promotion
requires. Shadow is how a seat changes hands (Proposal 07).

The concrete configuration format lives with the tooling in `agent/`;
this document fixes only that occupancy is **declared**, not implicit —
a seat names what holds it, what it falls back to, and what runs in
shadow behind it.

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

### Proposal 07 — Who holds a seat is itself a decision, and a tenant is promoted by verdicts, never by agreement

**Statement.** Occupancy is declared, not implicit: a seat names what
holds it, what it falls back to, and what runs in shadow behind it. A
seat holds the **simplest tenant that suffices** — escalation to a
model is a justified choice, never a default. A candidate tenant earns
the seat by running in **shadow**, acting on nothing, while its
would-be decisions accumulate; and it is **promoted on verdicts, never
on agreement with the incumbent.** The promotion is itself a decision
record, citing the evidence that earned it.

**What this adds to Proposal 03.** That proposal established that a
seat is defined by the artifacts it reads and writes, and that any
intelligence satisfying the contract can hold it. It never said how a
seat *changes hands*. Without an answer, re-tenanting is either an act
of faith — swap it and hope — or it never happens at all, which makes
Proposal 03 a claim the project never cashes.

**Why agreement is the wrong criterion, and this is the whole point.**
Promoting a candidate because it matches the incumbent 96% of the time
measures **mimicry**, not judgment. It selects for a good imitator over
a good decider, and it does so confidently, because the number looks
like evidence. In Proposal 06's vocabulary, agreement is a *receipt* —
cheap, continuous, machine-observable, and weak as truth. Only verdicts
settle. That firewall was written to keep the resident's preferences
from being inferred from their behaviour; it applies unchanged to
keeping a seat's occupancy from being inferred from a candidate's
conformity. Agreement may **screen** — below some threshold, do not
bother auditing the disagreements — but it may never promote.

**Teeth.**

- **Simplest tenant that suffices.** A deterministic rule is a
  destination, not a waypoint: where the rule can be written it is
  auditable, free, instant, and its failure modes are enumerable rather
  than emergent. `cmd_route`'s provenance rule is one such tenant. An
  occupancy declaration that names a model states why the rule could
  not be written.
- **Shadow tenants never act.** A shadow candidate reads what the
  incumbent reads and writes a `shadow-decision` record referencing the
  live decision it shadowed, carrying the same fields the real decision
  carries — channel, evidence, considered set, propensity — plus which
  tenant produced it. `route` never routes it, `digest` never renders
  it, and no downstream seat may read it as though it were a decision.
  The journal stays complete, with nothing hidden and nothing acted on
  that should not have been.
- **Promotion cites verdicts.** The promotion record names the period,
  the shadowed sample, and the resident-authored judgments that
  favoured the candidate — audit answers, corrections, keep-or-rollback
  outcomes. *"Promoted the local model to the router seat: 412 shadowed
  decisions, and of 17 disagreements the resident's verdicts favoured
  the candidate 12 to 5."* A promotion that can only cite an agreement
  rate is not a promotion; it is a coin flip wearing a statistic.
- **Demotion is symmetric and cheaper.** Reverting a promoted tenant is
  a decision record too, but it needs only the evidence any decision
  needs — the bar to remove a tenant is deliberately lower than the bar
  to install one.
- **The fallback chain still ends where Proposal 03 put it** — seat
  empty, and the resident told. Shadow adds a candidate; it never adds
  a way to fake occupancy.

**The trap, named in advance.** Letting shadow *disagreements* drive
which decisions the audit asks about is the query-selection problem
Proposal 06 identifies, wearing a new hat: the candidate would be
shaping the very sample that judges it, and a tenant that disagrees
loudly on the cases it happens to be wrong about could talk its way
into a seat. The mitigation is the same one — the audit sample mixes
uniform-random with disagreement-driven items, **labelled as such**, so
the bias is visible in the record rather than baked invisibly into the
promotion evidence.

**Cost, stated honestly.** Shadow costs N× compute for zero immediate
benefit — the whole point is that its output changes nothing until it
has earned the right to. Worse, promotion inherits Proposal 06's
scarcity and compounds it: verdicts are sparse by design, disagreements
between a decent candidate and a decent incumbent are rarer still, and
verdicts *on those disagreements* are the intersection of two sparse
things. The real failure mode is not a bad promotion. It is that
**nothing is ever promotable**, the incumbent stays by default, and
Proposal 03's replaceability quietly becomes theoretical — a seat that
cannot change hands is a seat with a permanent occupant, whatever the
architecture says.

**Hardening test.** At least one seat is re-tenanted end to end —
shadow records accumulated, a promotion decision written citing
verdicts rather than agreement, the new tenant serving, and the whole
chain readable cold from the journal. Separately, a seat that declares
a deterministic tenant is *still* deterministic a release later, which
is what distinguishes "simplest thing that suffices" from a slogan. And
if after a year of lived use no seat has ever accumulated enough
verdicts to promote anything, the verdict bar was set beyond what this
system can supply, and this paragraph says so.

**Known weak points.** Two, both left open rather than papered over.
Shadow records grow without bound and nothing here says when they may
be discarded — they are decisions, not observations, so Proposal 04's
ephemerality rule does not reach them, and the honest answer is that
nobody has needed one yet. And **ensemble is deliberately unmodelled**:
the unmerged two-reviewer arrangement this project uses for code review
is a real and valuable pattern, but it is a way of *serving* a seat
rather than of changing who holds it, and folding it in here would blur
a proposal that is about succession.

## Relation to the vision

`docs/vision.md`'s architecture paragraph originally named Claude Code
as the acting layer. Under Proposal 03 that is a category error the
project no longer makes: Claude Code is the *current tenant* of the
worker seat — the best available today, replaceable tomorrow, and
required never. The vision text has been adjusted to match; the
founding reasoning is unchanged.
