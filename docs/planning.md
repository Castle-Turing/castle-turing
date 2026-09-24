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

It also carries **the acceptance run** — the format and rules for
executing a brief's criteria against what got built
(`tools/accept/accept`). That belongs here rather than in a document of
its own because the criteria are written by this seat: rules and the
thing that enforces them drift apart when they land separately, and a
criterion is written once and read by both halves.

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
    Manual: rebuild and switch on the host, then photograph the pointer
        beside the candidate the sweep chose.
    Criterion: the value lives in that host's own module and nothing
        changes for a second host with a different panel.
    Check: ! nix eval --json ".#nixosConfigurations.<the other
        host>.config.environment.sessionVariables" | grep -q XCURSOR_SIZE

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
  the thing the clause asks for is reachable.
- **`Check:` or `Manual:`** one per criterion, immediately below it, and
  never blank. `Check:` carries the command that exercises the criterion;
  `Manual:` carries the step a person takes where no command can stand in
  — which is legal and has to be said out loud, because a criterion
  nothing can run and nobody was asked to take is a verification plan
  that verifies nothing. The acceptance run below is what executes these,
  and it is the reason the pair is the unit rather than the prose alone.

The criteria are authored here, at spec time, before any implementation
exists. That ordering is the point rather than a convenience: writing
them afterwards means writing them having seen what got built, and
pre-commitment is the best-measured defence against a verifier
rationalising toward the artifact in front of it — false positives fell
from 0.72 to 0.01 in the review `docs/research/automated-approval.md`
records. The acceptance run below is what executes them; the slate review
and the pull-request reviews read them either way, because no run of
anything decides whether a criterion was the right one.

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
`Model-because`, `Milestone`, and at least one non-empty `Criterion`,
each carrying exactly one non-empty `Check:` or `Manual:`.
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
disposition per field, one `Check:` or `Manual:` per criterion and none
stranded above every criterion, fields where the format reads them, and a
number on every `###` heading. *Checked:* fully. Every failure here is a thing
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

## The acceptance run

A brief's criteria are authored here, at spec time. `tools/accept/accept`
is what later runs them against what got built, and this section is that
run's format and rules — the second half of the same discipline, kept in
this document because the criteria and the thing that executes them drift
apart when they are written down separately.

The failure it closes is the pipeline's named one: an implementer reports
work complete while holding a different definition of complete than the
resident. Task 0070 is the worked specimen. Every test passed, the gate
was armed, and the resident's actual reading — rows get written as work
happens — was unmet, which a person found by reading the pull request.
Unit tests passing is not "works the way the resident expects", and the
resident's own acceptance testing is the scarce resource everything else
here conserves. What this run changes is not who decides: it is that the
resident's verdict gets spent on work that has already survived its
stated criteria.

### Frozen against the implementer

The criteria are committed with the brief, before the implementation
exists. That ordering is the load-bearing defence and not a convenience:
a judge that commits its assessment before seeing the candidate cuts
false positives from 0.72 to 0.01
(`docs/research/automated-approval.md`), and the documented failure in
the other direction is a verifier weakening its own assertions and
deleting failing checks until a run passes.

The mechanical half is the `frozen` rule: `accept run --base <ref>`
compares the criteria as they stand against the criteria as they were
committed on a ref the implementing branch does not control, and flags
every difference. Editing one is flagged, deleting one is flagged, and
*adding* one is flagged too — a criterion written where the artifact is
already visible is not the pre-commitment that makes a pass mean
anything, however honest the addition. The flag asks for a commit the
resident reviews; it accuses nobody. A criterion also *is* a shell
command this tool executes, which is a second reason the comparison is
against a ref the branch under measurement cannot move.

Without `--base` the rule does not run, and the receipt says so on its
`Base:` line and again in what the run did not check. A rule that can be
skipped silently is not a rule.

### Isolated from the implementer

Two rules, each independently evidenced in
`docs/research/decomposition-and-iteration-caps.md`. The acceptance agent
runs in a **separate context** — sharing the generator's context
measurably worsens reward hacking over repeated cycles — and where the
stakes warrant, on a **different model family**, which is the sentinel
argument. It receives the criteria, the built artifact and the invocation
path. It does not receive the implementer's transcript, reasoning or diff
narrative.

What the tool can be held to is its inputs: `accept run` reads the brief
and runs the commands, and there is nothing in it that reads a diff or a
transcript. *Not checked:* whether the agent reading the receipt was in a
separate context at all, and whether it was a different family. No tool
can see that. It is the caller's discipline, stated here so that a caller
who skips it has departed from something written down rather than from
nothing.

### A pass is a receipt, never a verdict

The run's output is a **receipt**: these commands ran, in this invocation
path, at this commit, and exited this way. Proposal 06 forbids the
promotion of that into a verdict, and the receipt is built so the
promotion cannot happen quietly:

- Every criterion is reported **one at a time**, with the criterion
  quoted, the command shown, its exit status, and the tail of its
  transcript. A report that aggregates has hidden exactly the criterion a
  reader needs.
- A criterion's outcome is one of **four phrases** and the set is closed
  — observed as the criterion states, observed differently, could not be
  exercised, not exercised here. A heading is where "acceptance passed"
  would be smuggled in.
- The **standing limit** — the paragraph saying this is evidence a
  mechanism fired and not a judgment that the work is what the resident
  asked for — is printed on every run and required verbatim by
  `accept check`. A receipt that has lost it is refused.
- **Completion-assertion vocabulary is a blocking lint** on the receipt's
  own prose: the register is a trained default with a measurable
  signature that model judges talk themselves out of, so an instruction
  not to use it is not a control. The vocabulary's first home is
  `tools/handover-check.py`, which bans it in the operator handover;
  `accept` carries a second copy because each tool here is one stdlib
  file that runs on its own, and `test/accept/run.sh` fails if the two
  copies ever differ.

A quoted criterion and a captured transcript are read past by that lint,
and so are the title's text and the header's values. A criterion whose own
prose says "complete" is the spec-time author's sentence, a test named
`test_completes_cleanly` in captured output is evidence rather than a
claim, and a brief's own title or its path under `docs/tasks/done/` is an
identifier — a lint that read those would refuse to report on anything
named after the word it bans. Masking them is what lets the lint be
blocking without making the receipt unable to quote its own inputs. The
header's *keys* stay visible, so a header renamed into a sentence is still
read.

An agent-as-user pass is solid evidence a mechanism fired and weak
evidence a person is satisfied. That is what the simulated-user research
finds and what this architecture already committed to, and it is why the
sampled reads below stay the resident's.

### A criterion that cannot be run says so

Each criterion carries exactly one disposition, and neither may be blank:

    Criterion: <what demonstrates the requirement in its real invocation path>
    Check: <the command that exercises it, from the repository root>

or

    Criterion: <…>
    Manual: <the step a person takes, and what they would see>

Blank is not a third option — the same non-emptiness rule that binds a
falsifier, a `Model-because:` and a deferral reason. A criterion nothing
can run and nobody was asked to take is a verification plan that passes
review and then verifies nothing, which is the detector this harness owes
its own source incident. `plan check` enforces the disposition at spec
time, where the slate review reads it, and `accept run` refuses a brief
whose criteria are missing or dispositionless rather than exercising
nothing and exiting zero.

A `Check:` written at spec time names an invocation path that does not
exist yet. That is expected: a check that could already run is a check
that demonstrates nothing new.

A brief whose criteria are *all* manual gets a receipt naming every step
that stands in place of a check, and a non-zero exit under the `vacuous`
rule. That is not a defect in the brief — a criterion may legally stand
on a person's eyes — it is this tool declining to emit a passing receipt
for work it did not exercise. A green exit over nothing exercised is the
promotion again, wearing an exit status.

### Repair cycles, bounded by a condition this slice does not have

When a run fails and the implementer retries, the stopping rule the
self-correction literature measures is error-introduction catching
error-correction. That needs per-model correction and introduction rates,
which nothing here measures yet, so this slice ships the backstop and
names the successor rather than mistaking one for the other: `accept run
--cycle <n> --cap <n>` refuses to run past the cap, and reaching it is an
escalation rather than a retry.

Two results are escalations rather than failures, and the difference is
the point. A command that could not be run at all, and a command that
never finished, are failures the criteria did not anticipate — and
nothing here can tell a missing artifact from a broken check. The run
says so and stops; interpreting it is the resident's, immediately. A loop
that guessed would be a loop rationalising toward the artifact in front
of it, which is the whole thing the isolation rules exist to prevent.

### What the runner checks, and what it cannot

`tools/accept/accept run <brief>` — mechanical, stdlib only, no network,
no model. Every finding blocks, for the reason `plan check` gives about
its own: each is a presence, an exit status or a comparison against
history, with no precision to lose.

**`criteria` — the vacuous pass, refused.** A brief with no `Criterion:`
in its field block, a criterion with no prose, a criterion with no
disposition, a disposition with nothing after it. *Checked:* fully.
*Not checked:* whether a criterion is worth running, which is item 2 of
the slate-review checklist above.

**`form` — what the format would otherwise drop silently.** A
disposition with no criterion above it, two dispositions on one
criterion, an acceptance field below the field block that closes it.
*Checked:* fully. Each of these is a criterion the tool would read
differently from the way a person reads it, which is the one failure a
format check exists for.

**`frozen` — the ordering, held.** Every difference between the criteria
on the branch and the criteria at the merge base, including a brief that
does not exist there at all. *Checked:* fully when `--base` is given.
*Not checked:* anything at all when it is not, which the receipt states
rather than passing over.

**`criterion` — what was observed.** A check that exited non-zero is
reported as observed differently from what the criterion states, with its
transcript. A check that timed out carries whatever it had printed before
it hung, which is the only evidence there is about where it hung. *Checked:* the exit status. *Not checked:* whether the
criterion's own wording captures what the resident meant — the receipt
carries the evidence, and the reading stays a person's.

**`escalate` — the failures the criteria did not anticipate.** A command
that was not found, and a check that outlasted `--timeout`. *Checked:*
fully, and deliberately not interpreted.

**`vacuous` — nothing exercised.** No criterion carried an executable
check. *Checked:* fully.

**`cycles` — the backstop.** The repair cycle against the cap; nothing is
run and no receipt is written past it. *Checked:* the count. *Not
checked:* the measured condition the cap stands in for, which is named
above as the successor.

`tools/accept/accept check <receipt>` reads a receipt on its own, which is
the case that needs a checker at all: a receipt that arrives from an
acceptance agent is prose somebody wrote, in exactly the register a model
reaches for when asked whether work is done. Three rules — `form` (the
title, the five headers in order, criteria numbered 1..N and as many of
them as the header declares, an outcome phrase from the closed set, the
standing limit verbatim), `grounding` (each criterion quoted, and either a
command with its exit status or a named manual step, never both — and the
outcome phrase agreeing with the exit status beside it), and `claim` (the
vocabulary).

Two of those exist because the format's own defences are otherwise
one-sided. Numbering 1..N cannot see a dropped tail, so the declared count
is compared against the sections present: delete the last two and the
numbering still runs, which is how a receipt loses exactly the criteria
that diverged. And a closed phrase set buys nothing unless the phrase is
held to its evidence, so "observed as the criterion states" over a
non-zero exit is refused — the heading is the line a reader trusts, and it
is the one written by hand. The run
lints its own output through the same three before anybody reads it: the
generator controls its output, so a violation there is a bug in the tool
rather than a style note.

*Not checked, stated out loud:* whether the criteria were the right
criteria. Every judgment item is on the slate-review checklist above or
its omission is a defect in this document.

### Running it

<!-- invokes: tools/accept/accept run -->
<!-- invokes: tools/accept/accept check -->

    tools/accept/accept run <brief> --base origin/main -o <receipt>
    tools/accept/accept check <receipt>

Run from the repository root, which is where a criterion's check is run
unless `--root` says otherwise. The receipt's `Commit:` is that
checkout's, because it attests the artifact the commands ran against
rather than the tree the criteria were read from — the two are the same
repository in this step and need not be. `--base` is what arms the frozen rule;
`--cycle` and `--cap` carry the repair loop's position. Exit status is
zero when every criterion with an executable check was exercised and
observed as the criterion states, and when nothing else above blocked.

The worked example is `tools/accept/oracle/brief.md`, whose criteria are
task 0072's read back post-hoc — "a row appears when a task lands", the
exact criterion whose absence let task 0070 through — with the receipt of
a real run committed beside it. The receipt is a specimen rather than a
golden file: it carries the commit it ran at, so a byte comparison would
pin a sha and rot. What CI holds it to is that it still passes
`accept check`.

### What the acceptance run does not do

It is not wired to anything. No harness runs it on a pull request, no
brief in `docs/tasks/` yet carries the disposition fields it reads, and
nothing hands its receipt to a second agent. That is the same order the
clarifying-questions phase and this seat were built in, and for the same
reason: a phase that only works through a harness cannot be checked, and
a phase that cannot be checked is what these documents exist to avoid.

It never approves. A receipt is not a merge, a passing run is not a
verdict, and neither this tool nor the agent reading its output decides
that work is acceptable. The resident does.

Its falsifier is a sampled read: the resident reads real receipts against
their own judgment of the same work, and if the two diverge, the
compilation from criterion to check is wrong — and the receipt says which
criterion diverged, which is what makes the divergence diagnosable rather
than merely disappointing. That read is unrun. Until it happens this
section is a design, exactly as the slate review is, and for the same
reason.

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
