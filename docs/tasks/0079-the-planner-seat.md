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
