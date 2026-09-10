# Passing tests are not acceptance

**What.** The pipeline's known failure mode, named by the resident
(2026-09-10): an implementing agent reports work complete while
holding an entirely different definition of complete than the
resident. "Unit tests all pass" is not "this works the way the
resident expects," and today the gap between those two sentences is
closed by the resident doing manual acceptance testing — the exact
scarce resource everything else exists to conserve. The resident's
direction: this failure mode must become significantly harder to
trigger, which means investing in a harness for agentic acceptance
testing, beyond the integration- and fuzz-testing investments
already recommended.

**Why it matters.** A one-human-plus-n-agents team scales only as
far as the human's attention, and manual acceptance is attention
spent at the worst point: after implementation, per change, on work
whose spec moment has passed. Worse, a completion claim that goes
unchallenged is the confident fiction the receipts rule exists to
prevent — the ban on completion vocabulary is discipline at the
reporting layer, but nothing mechanical stands behind it at the
artifact layer.

**What we already know.**

- The raw material exists at spec time. Milestone documents carry
  "done looks like" clauses; the elicitation protocol extracts them
  from the resident's words; every brief owes a verification plan.
  All of it is prose today, and prose is where an implementer's
  private definition of "complete" hides.
- The design move is compilation: the done-looks-like clause and the
  brief's verification plan become executable acceptance checks,
  authored at spec time and run by an agent standing in for the
  resident against the real artifact.
- The 2026-09-10 research round supplies the strongest argument from
  an unexpected angle: the best-measured mitigation against a
  verifier gaming its own verdict is having the judge commit its
  assessment *before* seeing the candidate. Acceptance criteria
  written at spec time, before any implementation exists, are
  structurally that commitment — the acceptance agent cannot
  rationalize toward what got built, because the bar was set when
  nothing was built.
- The same round documented the failure this harness must resist:
  LLM verifiers weakening assertions and deleting failing checks to
  manufacture passes. Consequences for the design: the acceptance
  seat is distinct from the implementer (the sentinel argument —
  cross-family where stakes warrant), acceptance criteria live where
  the implementer cannot edit them, and criteria change only by
  reviewed commit.
- For GUI surfaces, the ACI research round (same date, recorded in
  the gui-surfaces backlog entry's amendment before promotion) makes
  acceptance mechanical: posed fixtures, interaction contracts (in
  state X, activating Y yields Z), and a tree-inspection verb are
  exactly "works the way the resident expects" rendered checkable.
- Proportionality holds: a harness step is owed when it will repeat
  (the existing convention). A one-off manual check the resident can
  do in a minute stays manual; the acceptance harness exists for the
  checks that recur with every change to a surface.

**How this would have been caught sooner.** It is caught today — by
the resident, manually, every time, which is the problem statement
rather than a detector. The detector the eventual brief owes is the
harness itself: a task whose acceptance checks do not pass cannot
report itself complete, and a brief whose done-looks-like clause
compiles to no executable check must say so explicitly and name the
manual step that stands in — blank is not an answer, per the same
rule that binds this section.

**Constraint at promotion time.** This is pipeline-changing work;
[m2-constraints]'s baseline-before-intervention clause applies to
any brief promoted from this entry.

**Open questions.** Whether acceptance checks live with the brief
(spec and check merge together) or in a standing suite the brief
extends. What the acceptance agent's report owes the journal so a
pass is a receipt rather than a claim. How far criteria compilation
can be automated before the elicitation itself becomes the
bottleneck it was meant to relieve. And where the harness draws the
line against [[the-resident-reviews-specs-not-code]]'s sampled
manual reads — a sample of real resident acceptance should probably
survive as calibration for the agentic kind.
