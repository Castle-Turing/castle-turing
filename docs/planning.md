# The planner seat

A requirements document becomes a slate: numbered task briefs, the
edges between them, and an accounting of every requirement that shows
which brief carries it.

This document is the seat's mechanism — what it produces, what rules it
runs under, and which of those rules a machine checks. The evidence for
every rule is in `docs/research/decomposition-and-iteration-caps.md`,
which is a record and is not repeated here. `tools/plan/plan` is the
checker, `test/plan/run.sh` is the proof that the checker can fail, and
`tools/plan/oracle/slate.md` is a worked example produced by running
this procedure over a requirements document the repository already
ships.

## The seat

**Planner** — a reasoning seat, the fourth, after worker, router and
delivery. It reads a requirements document that passes `clarify check`
(`docs/clarifying-questions.md`), the milestone state
(`docs/state/MILESTONE.md`), and the briefs that already exist. It
writes one slate.

**The planner proposes; it never dispatches.** No brief it writes is
eligible work until the resident approves the slate. It never approves
its own slate, never launches a sprint, and never edits the documents it
is checked against — a requirement that needs changing goes back through
the clarifying-questions phase, because a planner that edits the
requirements document has made coverage a statement about its own
output. Approval is a resident verdict (Proposal 06); a green
`plan check` is at most a receipt that the discipline was followed.

**The unit of approval is the slate, not the brief.** A decomposition is
wrong in ways no single brief shows: two briefs that overlap, a seam in
the wrong place, an edge that serialises work that could have run at
once. Reviewing briefs one at a time cannot see any of those, so the
whole decomposition is read as one artifact and approved or sent back as
one.

**A question is how the seat stops.** When the decomposition turns on a
judgment only the resident can supply, the planner opens a question
rather than deciding — including when a clause it must decompose still
carries an open ambiguity from the clarifying-questions phase, which it
may neither settle nor quietly route around. In this slice a question
travels through the session or the pull request carrying the slate,
file-native, exactly as the clarifying phase's do; the slate's own copy
sits in a `## Questions` section, which nothing checks. Routing
questions to the modal is the question-routing work and deliberately not
this seat's.

### Two framings this seat is not

Recorded because they will be proposed again.

**Role-shaped agents** — an "AI product manager" who writes the
requirements and an "AI architect" who decomposes them. The seat
vocabulary names function rather than org-chart titles
(`docs/architecture.md`), and a seat named for a job title invites a
reader to assume capabilities from the title rather than from the
contract. The closest evidence there is points the same way and is
about people rather than models: the elicitation library's family of
experiments found analyst seniority a weak predictor of elicitation
effectiveness, with domain familiarity and specific interviewing skill
carrying the variance (`docs/research/elicitation-papers.md`). Nothing
measures whether role-shaped prompting helps a model, which is itself
the reason not to build a seat vocabulary on it.

**A fixed unit-size target** — "every brief is half a day", an INVEST or
SPIDR score, a story-point ceiling. The size-versus-success evidence is
correlational, and the named heuristics are practitioner vocabulary
rather than measured rules. A number borrowed from a framework nobody
measured would look exactly like a rule and carry none of the authority
of one. Right-sizing is item 1 on the checklist below, where it is
judgment and says so.

## The slate

Plain markdown with a header of `Key: value` lines, the same discipline
as the requirements document and for the same reason: boring enough that
a session with nothing but a text editor can produce one, and boring
enough that a checker needs no parser library.

The header declares, before the run:

    Requirements: <the requirements document this slate decomposes>
    Brief-budget: <the most briefs this slate may contain>
    Tasks: <where task numbers are allocated against>

`Brief-budget` is the bound on over-splitting. The one firm decomposition
finding in the literature is that automated splitting over-generates and
under-targets at the same time — AI-assisted teams produced 5.4 tasks
per story against 3.2 for manual splitting, and implemented 59% of them
against 100% — and the asymmetry rule
`docs/clarifying-questions.md` rule 6 applies to questions transfers
without modification. An unnecessary split is the cheap error and the
budget bounds it. A missed split, producing one oversized unreviewable
brief, is the expensive error, and it is caught by the resident reading
the slate, never by a count.

Declared **before** the run, and raising it is a decision somebody makes
on the record. A budget edited to fit the count it was meant to bound is
not a budget — the same discipline Proposal 06 requires of a probe's
floors.

`Tasks` is this seat's private configuration in Principle 01's sense:
the rule computed from it is identical everywhere, and what changes per
deployment is which directory numbers are allocated against. A real
slate names `docs/tasks`; the worked example names its own frozen
fixture directory, so that a real task reaching one of the example's
numbers can never fail CI for a reason that is not the pull request's.

### A brief in a slate

`### <title> [<NNNN>]`, then a block of fields, then the brief's body.

    ### The chosen size is what the compositor draws on that host [0003]

    Model: standard
    Model-because: the brief cannot name the host —
        [cursor-target-host]'s ambiguity is deferred on the record
        precisely because "this laptop's panel" names none.
    Milestone: m2-done
    Traces: cursor-visible-size, cursor-target-host
    Requires: 0002
    Requires-because: the value this brief commits is 0002's output.
    Criterion: after a rebuild and a switch on the host, the compositor's
        pointer on the internal panel at default scale is the size chosen
        in 0002, shown in a screenshot of the running session.

    The brief's body: the spec and reasoning an implementing agent reads
    cold, including what was considered and rejected.

Every brief carries what a brief in `docs/tasks/` already owes under the
work-layout contract — `Title` (the heading), `Model` with a non-empty
`Model-because`, `Milestone`, and `Requires` with `Requires-because`
where an edge is real — plus two the slate adds:

- **`Traces:`** the requirements clause keys this brief serves. This is
  what makes coverage and grounding computable at all. A brief serving
  no clause is either a clause somebody forgot to clarify, which belongs
  in the requirements document first, or scope the planner invented.
- **`Criterion:`** repeatable, and together the brief's verification
  plan. Each one says what would demonstrate the traced requirement
  working **in its real invocation path** — not that the code runs, that
  the thing the clause asks for is reachable. That is the acceptance
  doctrine, whose harness is task 0080's work and not this seat's.

The criteria are authored here, at spec time, before any implementation
exists. That ordering is the point rather than a convenience: writing
them afterwards means writing them having seen what got built, and
pre-commitment is the best-measured defence against a verifier
rationalising toward the artifact in front of it — false positives fell
from 0.72 to 0.01 in the review `docs/research/automated-approval.md`
records. Until the acceptance harness runs them, the criteria are what
the slate review and the pull-request reviews read against.

**Fields are contiguous from the top of the brief, and a wrapped value
continues on an indented line.** RFC-822 style, and chosen rather than
inherited: `tools/outcomes/outcomes` names exactly this format change as
the real fix for its own named gap, where a wrapped value that runs to
the next blank line silently swallows the header after it. The cost is
that a field written below the blank line is outside the block — so it
is refused by name rather than read, because a brief whose stated
`Milestone` nobody reads is the failure this closes.

### Coverage, and the index nobody writes

Every clause of the requirements document is carried by at least one
brief's `Traces:`, or listed under `## Coverage` as

    Deferred: <clause-key> — <why deferring it is acceptable>

There is no third state. Deferring is legal; deferring silently is not —
the same no-third-state rule `docs/clarifying-questions.md` rule 1
applies to a nocuous ambiguity, and for the same reason: a clause nobody
mentioned is indistinguishable, from the outside, from a clause somebody
decided against, and only one of those is a decision. The dash is
required rather than optional, so that the format cannot express a
deferral with no reason.

The **index** — the map from each clause to the briefs that carry it —
is derived by `plan check` from the briefs' own `Traces:` lines and
printed on every run. It is never authored. Two authored copies of one
mapping drift, and the drift is silent.

## The checker

`tools/plan/plan check <slate>` — mechanical, stdlib only, no network,
no model. Eight rules, and each says what a machine can check and what
it cannot, because some of this is judgment and a validator pretending
to grade judgment would produce ritual compliance rather than reasoning.

All eight block rather than warn, which is a difference from `clarify`
and follows from what they are: every rule here is a presence, a name
that resolves, or a graph property, so unlike that tool's style lint
there is no precision to lose by blocking.

**`header` — the knobs, before anything computed from them.**
`Requirements:` names a file that exists, `Brief-budget:` is a whole
number of at least one, and a tasks directory is resolvable from either
`Tasks:` or `--tasks`. *Checked:* fully, and it cannot be narrowed
away, for the reason `docs/clarifying-questions.md` gives about its own
knobs — a knob out of range does not weaken the rule computed from it,
it empties the rule out. A missing `Requirements:` makes coverage and
grounding unrunnable, a requirements document with no keyed clauses
makes coverage vacuous, since every possible slate covers it, and a
slate with neither `Tasks:` nor `--tasks` would otherwise leave
`numbers` and the edges rule's outside-the-slate check silently
skipped rather than run; all three fail rather than pass.

**`coverage` — omission.** Every clause is traced by some brief or
deferred with a non-empty reason, and never both at once. *Checked:*
fully. *Not checked:* whether a deferral's reason is true, which is
checklist item 3.

**`grounding` — invention.** Every `Traces:` and `Deferred:` key is a
clause that exists, and every brief traces at least one. *Checked:*
fully. *Not checked:* whether a brief's body stays inside what its
`Traces:` claim, which is checklist item 6 and the direction this rule
cannot see: a brief can cite the right clause and then do more than the
clause asked.

**`obligations` — what every brief owes.** `Model`, a non-empty
`Model-because`, `Milestone`, and at least one non-empty `Criterion`.
*Checked:* presence only. A `Model-because:` that would have supported
the opposite tier equally well passes, and so does a `Criterion:` that
exercises code without demonstrating anything. CLAUDE.md's argument for
why `Model-because:` is not a validator applies here unchanged: a
required free-text field with nothing reading it produces ritual
compliance. Those are checklist items 5 and 2.

**`budget` — the cheap error, bounded.** The brief count is within
`Brief-budget`. *Checked:* the count. *Not checked:* whether the budget
itself is reasonable — `Brief-budget: 99` passes and empties the rule
out. What the tool does instead is print the count, the budget and the
slack on every run, where a reader can see the emptying happen.
Right-sizing is checklist item 1.

**`edges` — the graph.** Every `Requires` has a `Requires-because`, no
edge points at a brief that exists nowhere, no brief requires itself,
and there are no cycles. *Checked:* fully. *Not checked:* whether an
edge is real. That is checklist item 4, and it is the quiet one: a false
edge breaks nothing, serialises a sprint that could have run in
parallel, and costs nothing anybody measures.

**`numbers` — allocation.** No brief's number is already taken under
`Tasks:`, read from the directory at check time rather than from any
listing. *Checked:* fully, and this is the one rule whose weakness is
in time rather than in substance: it was true when it ran, and other
work lands between a slate's writing and its transfer. That is why a
slate's numbers are proposals, re-checked at transfer — see below.

**`form` — what the format would otherwise drop silently.** One
disposition per field, fields where the format reads them, and a number
on every `###` heading. *Checked:* fully. Every failure here is a thing
the parser could have swallowed instead: a second `Milestone:`
overwriting the first, a field below the blank line that closes the
block, a `Deferred:` buried inside a brief, a heading whose brief has no
number and so can be required by nothing.

A passing run prints, after the index, a standing statement of what it
did not check. That is not decoration: a green exit that said nothing
would be the promotion from receipt to verdict Proposal 06 forbids,
arriving through the one surface most likely to be read as a verdict.

*Not checked, stated out loud:* everything on the slate-review checklist
below. Every judgment item is either on that checklist or its omission
is a defect in this document.

## The slate review — the resident's checklist

Written down so it is a discipline rather than a vibe, and so pieces of
it can be automated later without redesign. Each item names its future
mechanical assist; none of those assists exists today.

1. **Right-sizing.** Each brief is independently implementable and
   reviewable; none carries two unrelated changes. *Later assist:*
   diff-size and rework statistics from `docs/log/task-outcomes.tsv`,
   once enough rows exist to calibrate against.
2. **Criteria capture intent.** Each verification plan would actually
   demonstrate the requirement it traces, not merely exercise code.
   *Later assist:* seeded probes, the `clarify` pattern — a requirements
   document with known-needed criteria, scored for coverage.
3. **Deferral honesty.** Each `Deferred:` reason is true and the
   deferral is genuinely acceptable. *Later assist:* none foreseen; this
   is judgment about intent.
4. **Edge truthfulness.** Each `Requires:` reflects a real constraint. A
   false edge breaks nothing, silently serialises a sprint that could
   have run in parallel, and costs nothing anybody measures. *Later
   assist:* an overlap check on the files each brief predicts touching.
5. **Routing reasons.** Each `Model-because:` could not equally have
   supported the opposite tier. *Later assist:* none — this is the same
   human-enforced rule the conventions already state.
6. **Scope faithfulness.** No brief smuggles work its `Traces:` do not
   claim. *Later assist:* post-hoc — compare each landed diff against
   its brief's traced clauses, feeding the outcome log's rework column.

## Running it

This section is where these two steps are owned, and
`tools/reachability-check.py` holds it to that: the markers below are
what stop each of them being an entrypoint nobody invokes.

<!-- invokes: tools/plan/plan scaffold -->
<!-- invokes: tools/plan/plan check -->

    tools/plan/plan scaffold <requirements> --out <slate> --budget <n>
    tools/plan/plan check <slate>

`scaffold` writes the skeleton: the header, every clause of the
requirements document listed to be placed, and the next free number
allocated against the tasks directory. It is the whole of what a tool
can honestly do here. It enumerates the clauses so that no clause is
missed by never having been looked at — asking is structural rather than
hoped for, the same argument `docs/clarifying-questions.md` rule 1 makes
— and it allocates the number so that parallel writers do not each
invent one. It pre-fills no deferral, because a pre-filled deferral
would let a clause nobody considered pass as a clause somebody declined,
and its own output does not pass `check`: a scaffold that passed would
be a slate that looks complete while deciding nothing.

`check` resolves the requirements document and the tasks directory
through the slate's own headers; `--tasks` overrides the latter. Exit
status is zero when every rule passed.

## From an approved slate to a dispatched brief

Approval of the slate is the resident's act and the gate; what follows
is the route the work-layout contract already defines, unchanged. Each
brief becomes an item in `docs/backlog/`, reaches `Status: ready` by the
resident's mark, and is transferred verbatim into `docs/tasks/` with its
number allocated against the live directory at that moment. Nothing in
this seat shortens that path.

Which means a slate's numbers are **proposals, not reservations.**
Nothing in `tools/plan/` writes to `docs/tasks/`, and the `numbers` rule
checks only that a proposed number is not already taken — re-checked at
transfer, because between a slate's writing and its transfer other work
lands.

## Where a slate lives — open

Not settled, and deliberately written open rather than decided here.
`docs/state/` admits requirements documents by an explicit act of its
own README (rule 4 there), on the argument that a definition of work not
yet done is a thing later work must read as current; a slate has some of
that property and loses it the moment its briefs are transferred, after
which it is a record. The candidates are that directory, the backlog
item the slate grew out of, and `docs/tasks/` alongside the briefs
themselves. Nothing in `tools/plan/` cares: `check` takes a path.

What the choice turns on is whether anything is expected to re-read a
slate after its briefs land. If nothing is, it is a record and belongs
with the records; if the acceptance harness or the outcome log reads a
brief's traced clauses back, it is current truth and belongs with the
current truth. That is the resident's call and no decision record makes
it yet. The worked example sits under `tools/plan/oracle/` because it is
a fixture, which settles nothing about a real one.

## What this seat does not do

It is not wired to anything. No harness watches for a slate, the modal
does not display one, and a question it opens reaches the resident
because a person is reading the session or the pull request. That is the
same order the clarifying-questions phase was built in and for the same
reason: a phase that only works through a UI cannot be checked, and a
phase that cannot be checked is what these documents exist to avoid.

It does not prioritise. Which of an approved slate's briefs runs first
is the router's question and the resident's, and `[m2-out]` puts work
prioritisation outside this milestone entirely.

It does not write the requirements document it decomposes. That is the
clarifying-questions phase, and the separation is what makes coverage
mean anything.

## Where the judgment still lives

Everything above narrows what can go wrong. None of it decides whether
the decomposition is the *right* one — no rule in `plan` can, and a
reader who takes a green run as a verdict has made exactly the promotion
Proposal 06 forbids. The green run says the discipline was followed.
Whether following it produced the right slate is the resident's verdict
on the slate review, and nothing else.

That verdict is also this seat's falsifier, and it is unrun: no
requirements document has been decomposed for real, and until one is,
the checklist above is a design rather than a finding — exactly the
position `docs/clarifying-questions.md` is in on its own one-real-intake
test.
