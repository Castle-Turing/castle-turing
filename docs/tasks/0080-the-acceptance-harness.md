Title: The acceptance harness — a completion claim must survive its criteria
Model: deep
Model-because: the design decides what an automated pass may claim on
the resident's behalf — the receipt/verdict boundary under Proposal
06, and the isolation rules that keep a verifier from rationalizing
toward what got built. Encoding that boundary wrongly produces green
runs that mean nothing, which is this task's own subject. The runner's
mechanics, once the rules are fixed, are standard-tier work kept here
so rules and enforcement land together.
Milestone: m2-done
Requires: 0079-the-planner-seat
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
implementer.** Each brief's verification plan (mandatory, per task
0079's slate format) carries
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

## What implementation settled that this brief left open

Added in the implementing pull request, per the convention that the same
PR updates a brief the work has overtaken. Each of these was a judgment
call where the brief was silent or where following it literally would
have produced something worse; none changes what a pass may claim.

**A criterion carries its check as a field, and `plan` learned two of
them.** The brief requires criteria that assert reachability and requires
an uncompilable criterion to "say so", and is silent on where either
lives. They are `Check:` and `Manual:` field lines immediately under each
`Criterion:`, repeatable, exactly one per criterion, neither blank — and
`plan check` enforces the pairing at spec time. The alternative was for
the implementer to compile criteria into commands at run time, which is
the implementer authoring its own gate: the same defect the frozen rule
exists to stop, arriving one level down. The cost is that the slate
format changed under task 0079's checker, which is why that checker, its
fixtures and its worked example are all in this pull request.

**The receipt's lint is `accept check`, not `accept lint`.** Naming
matters mechanically here, not only for consistency with `clarify check`,
`plan check` and `outcomes check`: `tools/reachability-check.py` treats a
subcommand named `check` as a gate and then requires the workflow running
it to name what feeds it. A subcommand named `lint` would have left this
workflow's feeder line unvalidated decoration, and the feeder is the one
honest thing this gate can say — a receipt really is produced by a tool,
which is more than the planner seat's feeder can claim.

**The frozen rule is off without `--base`, and says so twice.** Making it
mandatory was considered and rejected on two grounds. The worked example
is introduced by this pull request, so a mandatory comparison would flag
the example against its own base and teach nothing; and the criteria of
an already-merged task are post-hoc by construction. The receipt states
the rule did not run on its `Base:` line and again in what the run did
not check, because a rule that can be skipped silently is not a rule.

**A brief whose criteria are all manual exits non-zero.** The brief
requires refusing an *empty* criteria section. It does not say what to do
when every criterion legally stands on a person's eyes, and the answer
here is a receipt naming every step that stands in place of a check and a
non-zero exit under a `vacuous` rule whose message says this is not a
defect in the brief. A green exit over nothing exercised is the promotion
Proposal 06 forbids wearing an exit status.

**Escalate-on-novelty is two mechanical shapes.** The brief names the
rule; the shapes that can carry it are a command that could not be run at
all (exit 127) and a check that outlasted the timeout. Both are reported
as escalations rather than failures, and the message says out loud that
nothing here can tell a missing artifact from a broken check — the
distinction is exactly the interpretation the rule forbids the loop from
making.

**A criterion's outcome heading is a closed set of four phrases.** The
banned-vocabulary lint the brief asks for would admit "criterion
satisfied" or "acceptance passed", neither of which contains a banned
word and both of which are verdicts. The receipt's headings are therefore
a closed vocabulary and `check` holds a receipt to it, because a heading
is where a reader looks first.

**The completion vocabulary is duplicated rather than imported, and a
test holds the copies identical.** `tools/handover-check.py` is the
list's first home. Importing it was considered and rejected: the import
would name that file in a string, `tools/reachability-check.py` reads a
string naming a tool as a call to it, and the lint would then print
`handover-check.py` as operationally reachable — which an import of a
constant is not. Duplication's cost is silent drift, so
`test/accept/run.sh` extracts both lists and fails if they differ.

**The committed receipt is a specimen, not a golden file.** It carries
the commit it ran at and a scratch directory name from one check's
transcript, so a byte comparison would pin a sha and rot. CI holds it to
passing `accept check` and re-runs the worked example's criteria against
the checkout instead.

**The isolation rules are written down and not enforced, on the record.**
What a tool can be held to is its inputs, and `accept run` reads the
brief and runs commands — no diff, no transcript, no reasoning. Whether
the agent reading the receipt ran in a separate context, and on a
different model family, is stated in `docs/planning.md` as the caller's
discipline and marked not checked. Recording it as enforced would have
been an unsourced closure.

**What is not built, named rather than implied.** No harness runs this on
a pull request; no second agent reads a receipt; and no brief already in
`docs/tasks/` carries the disposition fields — this one included.
Retrofitting eighty briefs is not this task's, and the format arrives
with the slates the planner seat writes. The per-model correction and
introduction rates that would replace the repair cap with the measured
stopping rule are named as the successor in `docs/planning.md` and are
not measured here.
