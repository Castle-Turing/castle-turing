Title: Task 0071 — the delivery seat's record shim
Model: deep
Milestone: m2-now
Model-because: the deliverable is a contract between two documents
neither of which this task may edit to make it fit — the general
record contract in `docs/architecture.md`'s "Records" section, written
for the worker seat, and the delivery-specific contract task 0069
added to the same document. Writing the shim's behavior down honestly
surfaces two places those contracts assume something a hook-driven
external translator cannot supply (a record written at the instant of
the act it describes; an upstream journal record to `refs`). A
standard implementer would paper over both — invent a plausible `refs`
value, or claim the timing gap away — and a plausible invention here
is a false receipt of exactly the kind this document exists to
prevent. The judgment is knowing which sentences to leave open rather
than close.

# Task 0071 — the delivery seat's record shim

## Where this came from

The backlog entry "the-delivery-seat-has-no-record-shim", promoted and
deleted by this commit. Task 0069 named the delivery seat and fixed
the records it owes the journal — a `claim` when a brief is taken, a
`result` carrying `outcome`, tenant, model and provider, and a
`question` when the seat blocks on a judgment only the resident can
supply — but deliberately left the translator that writes them as
tooling that does not yet exist, because the tenant (emcee, the
operator's harness) never learns this project's record format: it
emits its own events through a generic hook, and a castle-owned shim
must translate them. `[m2-now]` records the same gap, patched by this
commit to say what is now specced rather than merely missing.

The backlog entry set one precondition for speccing this: "the hook
and its event schema exist on the harness side." This task's worktree
is sandboxed to this repository and cannot read emcee's checkout to
confirm either — see "What this brief deliberately does not pin down,"
below, for what that does and does not block.

## Scope: outbound only

This shim owns one direction — the tenant's events translated into
journal records. The reverse direction — an answered delivery
`question` resuming the tenant's own errand — is a distinct mechanism
the sibling backlog entry "an-answered-delivery-question-resumes-nothing"
already names and this brief does not touch. Repeating architecture.md's
own sentence so nobody reads this brief as having quietly built it:
until that mechanism exists, an answered delivery question resumes
nothing automatically, however this shim writes it.

## What this brief specs

A castle-owned process — its runtime home (a timer, a CI step, a
sweep beside `castle dispatch`) is an implementation choice left open
below — that:

1. **Wakes on the tenant's hook firing**, for a given delivery errand.
2. **On waking, reads the tenant's own durable event log for that
   errand directly, and folds it into the three owed record types** —
   never trusting only the payload the hook delivered. A brief taken
   becomes a `claim`; a brief's terminal state (a pull request opened,
   or given up) becomes a `result` carrying `outcome`, tenant, model
   and provider; a park becomes a `question` with `blocking: true`.
   The hook is a doorbell, not the mail, exactly as the promoted entry
   said: it says *when* to look, never *what happened* — that always
   comes from the tenant's own log, read fresh.
3. **The fold is idempotent and total.** Run twice against the same
   log state, the second run writes nothing new — already-written
   records are recognized and skipped, never reappended. This is the
   concrete answer to "what happens when an event arrives twice": it
   cannot produce a duplicate record, because nothing about the
   translation is keyed on the event itself, only on what the log
   currently shows.
4. **A missing or dropped hook firing is a liveness problem, never a
   correctness one.** The log is the source of truth and the hook
   only triggers a read of it, so the shim also polls on an interval
   independent of the hook — a doorbell that never rings delays the
   read; it does not change what the read finds when it eventually
   happens. Nothing is ever inferred from a hook's absence.

## Two open frictions this brief surfaces rather than resolves

The dispatch for this task asked for exactly this: where the promoted
entry and the two contracts it sits between disagree, name it rather
than pick a reading and move on. Two came out of writing the fold
above down precisely.

1. **"Written the instant" cannot mean the same thing for an external
   translator that it means for the worker.** The general record
   contract's `claim` exists "for observability across a restart,"
   and the worker's own is written "before the tenant command is even
   resolved" — the record and the act are the same moment. A shim
   reacting to a hook necessarily writes its `claim` some time after
   the tenant actually took the brief; the gap is however long the
   hook takes to fire plus however long the shim takes to wake and
   read. For that whole gap the journal is exactly as blind to the
   errand as it would be with no shim at all — the restart-observability
   failure the general contract exists to prevent, recurring one layer
   out. Polling narrows the gap; nothing closes it to zero. This brief
   does not decide how small is small enough — that is an operator
   tolerance, not a fact this task can derive, and it is left to
   whoever tunes the shim's wake interval.
2. **`refs` has nothing to point at.** Every record type's `refs` in
   the general contract — and the delivery `claim`'s own chaining
   promise in task 0069's paragraph, "chained by the `claim` that
   names it" — presumes an upstream journal record to reference: a
   worker's claim `refs` the `request` it answers. A delivery errand's
   upstream is a numbered brief, a file in `docs/tasks/`, not a
   journal record — the backlog entry "the-speccing-step-is-an-unnamed-seat"
   already names that arrow as unbuilt. The shim therefore has no
   record id for `refs` on any of the three types it writes. This
   brief's answer: leave `refs` empty on delivery's records for now,
   name the brief by its task number and slug in the body prose
   instead — the same "history is a name" rule `docs/state/README.md`
   already applies to citations — and treat a non-empty `refs` as
   something to add only once the speccing-step seat exists and gives
   the brief itself a citable id. Inventing one now, or reusing an
   unrelated id to satisfy the schema, would be exactly the kind of
   confident wrong record architecture.md's delivery paragraph exists
   to prevent.

Provenance (`requested` vs `initiated`) has the same shape as friction
2 but is left unremarked here rather than opened as a third: which one
applies depends on how a brief entered the seat, and that is squarely
"the-speccing-step-is-an-unnamed-seat"'s question, not this shim's.
Flagged here so the next reader of that entry knows delivery's records
inherit it too.

## What this brief deliberately does not pin down

**The tenant's hook and event schema.** The backlog entry's
precondition for speccing this shim was that emcee's hook and event
schema exist. This task cannot confirm their current shape or field
names — its worktree is sandboxed to this repository, consistent with
architecture.md's own "substrates are the tenant's business": the
harness depends on nothing above it, and this project does not reach
into its internals as a dependency either. The fold in "What this
brief specs" is written to need nothing schema-specific — an event
that names which errand woke the shim, and a durable log the shim can
read directly — and nothing in points 1 through 4 depends on a
particular field name. Pinning the actual mapping (what a "brief
taken," a "park," and a "brief finished" look like in emcee's own
vocabulary) is implementation work for a separate task, dispatched
once whoever implements it can read the live schema.

**Where the shim runs, and in what language.** Castle-owned per
architecture.md's own sentence; which checkout, which trigger, which
runtime is an implementation choice this brief leaves open rather than
one worth guessing at without the schema in hand.

## What not to do

Do not write the translator's code in this PR — the schema it needs
is not reachable from here (see above). Do not touch the inbound
(answer-resumes-errand) mechanism; that is the sibling backlog entry's
job. Do not re-derive or restate architecture.md's delivery-seat
paragraphs beyond the one-word citation fix this commit makes (the
stale backlog-entry name it pointed at, now that the entry is
deleted) — task 0069 already fixed the records, and the two frictions
above are surfaced here, in the record built for exactly this purpose,
rather than folded back into a binding document as a decision that
was never actually made. Do not invent a `refs` value for delivery's
records.

## Verification plan

Agent-verifiable now: none beyond `nix flake check` — this PR lands
no code, only this brief and the two doc patches
(`docs/architecture.md`'s citation, `[m2-now]`), so there is nothing
else to run.

For the implementation task this brief hands off: the fold's
idempotency (point 3) and its indifference to a missed hook (point 4)
are both mechanically testable with no human involved, against a
synthetic tenant event log — replay the same log twice and diff the
journal for a second write; delete an event from the log and confirm
the next scheduled read still produces the record it described. Needs
human hands: judging whether the restart-observability gap (friction
1) is small enough in practice once a real wake interval is chosen —
a question about the operator's actual tolerance for a blind window,
not something a checker can rule on.

## Implementation prompt for a separate session

Read this brief, `docs/architecture.md`'s delivery-seat paragraphs,
and emcee's current hook and event schema — from a worktree that can
actually reach it — before writing anything. Implement the fold
described in "What this brief specs," pin the exact event-to-record
mapping against the real schema, and record in a follow-up section of
this file which of the two open frictions above changed shape once
the real schema was in hand: a schema that turns out to carry its own
errand-identity concept, for instance, might close the `refs` gap
rather than leave it open. If the schema does not in fact exist yet,
or is not reachable from that session's worktree either, that is the
backlog entry's original blocking condition recurring — stop and say
so rather than guess at it a second time.
