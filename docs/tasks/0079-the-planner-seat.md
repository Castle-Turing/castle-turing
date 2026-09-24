Title: The planner seat — a requirements document becomes a brief slate
Model: deep
Model-because: the deliverable is a seat contract and an artifact
format that every later decomposition will be checked against — the
judgment about what the checker can honestly claim versus what stays
the resident's is the work, and a smaller model following a plausible
spec would encode the wrong boundary as green CI. The checker itself,
once this brief fixes the rules, is mechanical follow-up a cheaper
tier could build; it is kept in this brief because the rules and their
enforcement drift apart when they land separately (task 0070's lesson).
Milestone: m2-done

# The planner seat — a requirements document becomes a brief slate

## Where this came from

[m2-done] requires the work to be "decomposed into small, well-defined
task briefs," and the milestone state names this the largest unspecced
piece. The pipeline's one unnamed arrow — a requirements document or
backlog entry becoming numbered briefs — is held today by the resident
and ad-hoc sessions; this backlog item is the record, grown in place
per the work layout; the transfer to docs/tasks/ retires it.
The resident settled the shape on 2026-09-24: the seat consumes a
requirements document (the clarifying-questions phase's artifact,
task 0065), it is named **planner**, and the resident's approval
gates the **slate** — the whole decomposition reviewed as one
artifact — not each brief singly.

## The seat, in the architecture's terms

**Planner** (a reasoning seat — the fourth, after worker, router,
delivery). Reads a requirements document that passes `clarify check`,
the milestone state, and the existing briefs. Writes a **slate**: a
set of numbered task briefs, their dependency edges, and a slate index
that maps every requirements clause to the briefs that carry it.
Opens a `question` when blocked on a judgment only the resident can
supply — in this slice questions travel through the session or the
PR, file-native, exactly as the clarifying phase's do; wiring them to
the modal is the routing work, deliberately not this brief's.

The authority ceiling, stated the way delivery's is: **the planner
proposes; it never dispatches.** No brief it writes is eligible work
until the resident approves the slate. It never approves its own
slate, never launches a sprint, never edits the documents it is
checked against. Approval is a resident verdict (Proposal 06); the
planner's own output is at most a receipt of discipline followed.

Two framings were considered and rejected, recorded because they will
be proposed again: role-shaped agents (an "AI product manager" and an
"AI architect") — the seat vocabulary names function, not org-chart
titles, and the elicitation research found role and seniority framing
predicts little; and a fixed unit-size target — the size-versus-
success evidence is correlational only, and INVEST-style heuristics
are vocabulary, not validated rules. The research review
*Decomposition and iteration-cycle calibration* (docs/research/)
grounds every evidence claim in this brief.

## The slate artifact

Plain markdown, Key: value header, same discipline as the
requirements document. The header declares, before the run:

    Requirements: <the requirements document this slate decomposes>
    Brief-budget: <max briefs this slate may contain>

Brief-budget is the over-splitting bound: the research's one firm
decomposition finding is that automated splitting over-generates and
under-targets (5.4 vs 3.2 tasks per story, 59% vs 100% implemented),
and the same asymmetry rule as clarifying-questions rule 6 applies —
an unnecessary split is the cheap error, bounded by budget; a missed
split producing one oversized unreviewable brief is the expensive
error, caught by the resident's slate read, never by a count.

Each brief in the slate carries what every brief already owes
(Title, Model + Model-because, Milestone, Requires + Requires-because
where real) plus, mandatorily:

- **Traces:** the requirements clause keys this brief serves.
- **A verification plan whose criteria assert reachability** — what
  demonstrates the feature working in its real invocation path, per
  the acceptance doctrine (task 0080 is its harness). Authored here,
  at spec time, before implementation exists: the pre-commitment
  that is the best-measured defense against a verifier rationalizing
  toward what got built (false positives 0.72 to 0.01 in the
  automated-approval review). Until that harness runs them, the
  criteria are what the slate review and the PR reviews check
  against.

The slate index maps the coverage: every clause in the requirements
document is cited by at least one brief's Traces, or listed under
**Deferred:** with a non-empty reason. Deferring is legal; silence is
not — the same no-third-state rule the clarifying phase applies to
nocuous ambiguities.

## What the checker enforces, and what it cannot

`tools/plan/plan check <slate>` — mechanical, no network, no model:

- **Coverage:** every requirements clause is traced or deferred-with-
  reason. Catches omission.
- **Grounding:** every Traces: key exists in the requirements
  document. Catches invention — a brief serving no stated requirement.
- **Completeness of each brief's obligations:** Model + non-empty
  Model-because, Milestone, a verification-plan section present and
  non-empty. Presence only; a vacuous criterion passes the checker
  and fails the resident's read, and the checker's output says so
  rather than implying otherwise.
- **Budget:** brief count within Brief-budget.
- **Edges:** every Requires has a Requires-because; the graph is
  acyclic; numbers are allocated against the live directory.

*Not checked, stated out loud:* everything on the slate-review
checklist below. Every judgment item is either on that checklist or
its omission is a defect in this document.

## The slate review — the resident's checklist

Written down so it is a discipline rather than a vibe, and so pieces
of it can be automated later without redesign. Each item names its
future mechanical assist; none of the assists is this brief's work.

1. **Right-sizing.** Each brief is independently implementable and
   reviewable; none carries two unrelated changes. *Later assist:*
   diff-size and rework statistics from the outcome log, once enough
   rows exist to calibrate against.
2. **Criteria capture intent.** Each verification plan would actually
   demonstrate the requirement it traces — not merely exercise code.
   *Later assist:* seeded probes, the clarify pattern: a requirements
   document with known-needed criteria, scored for coverage.
3. **Deferral honesty.** Each Deferred reason is true and the
   deferral is genuinely acceptable. *Later assist:* none foreseen —
   this is judgment about intent.
4. **Edge truthfulness.** Each Requires reflects a real constraint;
   a false edge silently serializes a sprint. *Later assist:* an
   overlap check on the files each brief predicts touching.
5. **Routing reasons.** Each Model-because could not equally support
   the opposite tier. *Later assist:* none — this is the same
   human-enforced rule the conventions already state.
6. **Scope faithfulness.** No brief smuggles work its Traces do not
   claim. *Later assist:* post-hoc — compare each landed diff against
   its brief's traced clauses, feeding the outcome log's rework
   column.

## What lands

1. The architecture document gains the planner paragraph (seat,
   ceiling, records) — ordinary PR material, not CLAUDE.md.
2. docs/planning.md — the slate format, the checker's rules, and the
   slate-review checklist, each rule marked checked / not-checked.
3. tools/plan/plan (check subcommand) + test/plan/run.sh fixtures
   proving each rule can fail: uncovered clause, invented clause,
   missing Model-because, empty deferral reason, budget exceeded,
   dependency cycle — plus a passing oracle slate.
4. Reachability: the checker gets a CI workflow with a feeder line;
   the documented steps carry invokes markers. The lint stays green.
5. The milestone position is patched: decomposition specced as of
   this task.

## Verification plan

Automated: test/plan/run.sh in CI (each fixture fails for its own
stated reason; the oracle passes); outcomes-check and reachability
green. End-to-end, no human: run the planner procedure once against
the cursor-too-small oracle requirements document (task 0065's probe
ships one) and commit the resulting slate as a fixture — the format
demonstrated on real artifact shapes, not invented examples.
Needs the resident: one real slate review against the checklist
above — the first requirements document decomposed for real. That
review is this seat's falsifier, exactly as one real intake is the
clarifying phase's, and both remain unrun until scheduled.

## What implementation settled that this brief left open

Added in the implementing pull request, per the convention that the same
PR updates a brief the work has overtaken. Each of these was a judgment
call where the brief was silent or where following it literally would
have produced something worse; none changes the seat's contract.

**A `scaffold` subcommand exists, and it is what feeds the gate.** The
brief's item 4 requires the checker to have a CI workflow with a feeder
line, and `tools/reachability-check.py` requires a feeder to name a tool
entrypoint that *produces* what the gate checks. A slate is produced by
the seat, and no lint can check that a seat ran — so the only honest
options were to hide the gate behind the test wrapper (where the feeder
rule does not fire, which is the gap that lint's own header names) or to
give `plan` the mechanical half of slate production. The second is
better on its own merits: `scaffold` enumerates every clause so that
none is missed by never having been looked at, which is the same
structural-rather-than-hoped-for argument as clarifying-questions
rule 1, and allocates the next number so parallel writers do not each
invent one. It pre-fills no deferral and its own output fails `check`,
both asserted in `test/plan/run.sh`. The workflow's comment says out
loud that the feeder is the mechanical half only.

**"Edges" became two rules, `edges` and `numbers`.** The brief groups
number allocation under edges. They are separated because
`test/plan/run.sh` asserts on the rule name that owns each mutation — a
defect caught by the wrong check has to be a failure — and a colliding
task number is not a graph defect. Both are in `docs/planning.md` and
both are checked.

**The slate declares `Tasks:`, and the worked example points it at a
frozen fixture directory.** Numbers have to be checked against a live
directory, but the oracle slate is committed and CI-checked, so checking
it against `docs/tasks/` would make it fail the day a real task reached
one of its numbers — an armed gate failing for a reason that is not the
pull request's, which is the exact incident class task 0072's detector
exists for. The header makes the directory configuration in Principle
01's sense: the rule is identical, the path is not.

**A brief's verification plan is repeatable `Criterion:` field lines,
not a subsection.** The brief says "a verification-plan section present
and non-empty". Flat fields keep the parser free of nested headings, and
they make each criterion an individually addressable unit — which is
what the acceptance harness will need, and what item 2 of the checklist
reads one at a time.

**Fields are contiguous from the top of a brief and wrap on indented
lines.** RFC-822 style, adopted rather than copying the existing brief
header parser: `tools/outcomes/outcomes` names exactly this format
change as the real fix for its own named gap, where a wrapped value
swallows the header after it. The cost — a field below the blank line is
outside the block — is refused by name rather than silently ignored.

**The slate index is derived and printed, never authored.** The brief
describes "a slate index that maps every requirements clause to the
briefs that carry it". That map is computable from the briefs' own
`Traces:` lines plus the `Deferred:` lines, so asking a planner to write
it as well would put two copies of one fact in one file, and the copy
nobody computes is the one that goes stale silently. `plan check` prints
it on every run.

**The worked example defers nothing.** All four clauses of the clarify
probe's requirements document are carried by two briefs against a
declared budget of three. Deferring a clause the decomposition can
perfectly well carry would have demonstrated the syntax by teaching the
wrong thing; the `Deferred:` rules are exercised by mutations in
`test/plan/run.sh` instead, including a positive control where a
deferral with a real reason passes.

**Where a real slate lives is left open, on the record.**
`docs/state/README.md` admits requirements documents to that directory
by an explicit act of its own, and admitting a third kind of document is
not this task's to decide. `docs/planning.md` states the candidates and
what the choice turns on — whether anything re-reads a slate after its
briefs land — rather than recording an unmade decision as settled.

**The delivery seat's paragraph was corrected, not extended.** It cited
the backlog entry "the-speccing-step-is-an-unnamed-seat", which this
task's transfer deleted, and called the arrow into delivery unnamed.
Both are now false. What delivery may read of a slate beyond the brief
itself is stated as unsettled rather than closed, because no decision
record settles it and this brief is not about delivery.

**One defect found and not fixed here.** `tools/outcomes/outcomes
derive` logs a transferred brief as already merged, dating it to the pull
request that filed its backlog entry —
`docs/backlog/a-transferred-brief-is-logged-as-already-merged.md` is the
record, including the detector it owes. This task's own row is one of
the three affected. The cells are immutable, so the entry names the
repair options rather than choosing one.
