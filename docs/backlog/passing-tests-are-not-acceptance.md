Title: The acceptance harness — a completion claim must survive its criteria
Status: ready
Model: deep
Model-because: the design decides what an automated pass may claim on
the resident's behalf — the receipt/verdict boundary under Proposal
06, and the isolation rules that keep a verifier from rationalizing
toward what got built. Encoding that boundary wrongly produces green
runs that mean nothing, which is this task's own subject. The runner's
mechanics, once the rules are fixed, are standard-tier work kept here
so rules and enforcement land together.
Milestone: m2-done
Requires: the planner seat (backlog item the-speccing-step-is-an-unnamed-seat; task id fixed at transfer)
Requires-because: acceptance checks are authored into each brief by the planner's slate format; this harness executes what the planner defines, and its criteria-immutability rule leans on criteria having a committed, spec-time home the planner creates.

# The acceptance harness — a completion claim must survive its criteria

## Where this came from

The pipeline's named failure mode, stated by the resident 2026-09-10:
an implementer reports work complete while holding a different
definition of complete than the resident. Unit tests passing is not
"works the way the resident expects," and today that gap is closed by
the resident's own manual acceptance testing — the scarce resource
everything else conserves. This backlog item is the record, grown in place per the work
layout; the transfer to docs/tasks/ retires it. Its worked specimen is task 0070: every test green, gate armed,
and the resident's reading — rows get written as work happens — unmet,
caught only by a human reading the PR.

## The mechanism

**Criteria are compiled at spec time and frozen against the
implementer.** Each brief's verification plan (mandatory, per the
planner item's slate format — id fixed at transfer) carries
acceptance criteria that assert
reachability — a feature is accepted when exercised in its real
invocation path, never when it merely exists and unit-passes. They are
committed with the brief before implementation exists. That ordering
is the load-bearing defense, with measurement behind it: a judge that
commits its assessment before seeing the candidate cuts false
positives from 0.72 to 0.01 (the automated-approval research review).
The mechanical half of frozen: the runner flags any change to a
brief's criteria made on that brief's own implementing branch — a
criterion may change only by a commit the resident reviews, never by
the implementer widening its own gate. The documented failure this
resists: LLM verifiers weakening assertions and deleting failing
checks to manufacture passes.

**The acceptance agent is isolated from the implementer.** Two rules,
each independently evidenced in the research review *Decomposition
and iteration-cycle calibration* (docs/research/): it runs in a
separate context — sharing the generator's context measurably worsens
reward hacking over repeated cycles — and where stakes warrant, a
different model family, the sentinel argument. It receives the
criteria, the built artifact, and its invocation path. It does not
receive the implementer's transcript, reasoning, or diff narrative.

**A pass is a receipt, never a verdict.** The run's report states
which criteria were exercised and what was observed, with citations —
and no completion vocabulary: the report is lintable for the same
banned assertions as every generated surface (Proposal 06, the
resident's 2026-09-06 requirement). An agent-as-user pass is solid
evidence a mechanism fired and weak evidence a person is satisfied —
the simulated-user research independently confirms what the
architecture already commits to. The resident's verdict stays the
only verdict; what this harness changes is that the resident spends
it on work that has already survived its stated criteria.

**A criterion that cannot compile to an executable check must say
so** and name the manual step that stands in. Blank is not an answer
— the non-emptiness rule that binds a falsifier, a Model-because, and
a deferral reason. This is the detector the source entry owed: a task
whose checks do not pass cannot report itself complete, and a brief
with no executable check has said so out loud where the slate review
reads it.

**Repair cycles are bounded by a condition, not a count.** When a
run fails and the implementer retries, the loop's stopping rule is
the measured shape from the self-correction literature — stop when
error-introduction catches error-correction, with a hard cycle cap
as backstop only — and any failure the criteria did not anticipate
escalates to the resident immediately rather than being interpreted
by the loop. The full measurement (per-model correction and
introduction rates) is not this slice; this slice is the cap plus
the escalate-on-novelty rule, with the measured condition named as
the successor so the cap is not mistaken for the design.

## What lands

1. The acceptance-run format and rules in the planning document
   (extending 0079's, same checked/not-checked discipline).
2. tools/accept/accept — run one brief's criteria against a built
   artifact; report as receipt; flag implementer-branch criteria
   edits; refuse a brief whose criteria section is empty rather than
   passing vacuously.
3. test/accept/run.sh fixtures: a criterion that fails is reported
   failed; an implementer-branch criteria edit is flagged; an empty
   criteria section refuses; completion vocabulary in a report fails
   the lint; a clean run passes and its report cites what it
   exercised.
4. Reachability: CI caller and feeder line; invokes markers at the
   documented steps.
5. The milestone position patched.

## Verification plan

Automated: the fixtures above in CI; outcomes-check and reachability
green. End-to-end, no human: run the harness once against an already-
merged task with post-hoc criteria (task 0072's "a row appears when a
task lands" is the natural specimen — the exact criterion whose
absence let 0070 through) and commit the run's receipt as a fixture.
Needs the resident: sampled reads of real acceptance receipts against
their own judgment — the calibration the source entry reserves, and
this harness's falsifier: if receipts and the resident's verdicts
diverge on the sample, the compilation is wrong, and the receipt
says which criterion diverged.
