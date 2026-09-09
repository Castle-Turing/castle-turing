# The clarifying-questions phase

Before anything gets built, the system asks about what it does not
understand — and writes down what it still does not understand after
asking.

This document is the phase's mechanism: what it produces, what rules it
runs under, and which of those rules a machine checks. The evidence for
every rule is in `docs/research/elicitation-papers.md`, which is a
record and is not repeated here; task 0065 is the brief that compressed
it into this design. `tools/clarify/clarify` is the checker, and
`test/clarify/run.sh` is the proof that the checker can fail.

## Why the phase exists at all

An agent handed an underspecified request does not usually fail
loudly. It produces a clean, plausible, executable artifact built on a
reading of the request that nobody chose — a *silent commitment*. That
is the named primary failure mode in this literature, and it is
dangerous precisely because the output looks fine. The ambiguity does
not surface as a bug; it surfaces months later as a thing that was
built correctly and was the wrong thing.

Two measured facts shape everything below. First, models are far better
at *recognising* ambiguity than at *asking* about it, and how often a
given model volunteers a question ranges from never to about half the
time on identical tasks — so a phase that hopes the model will ask is
depending on a property that is not there to depend on. Asking has to be
structural. Second, the models that do ask over-ask and under-target at
the same time: more questions than a trained clarifier needs, aimed at
the wrong things. So the phase is not "ask more." It is "ask few, ask
the right ones, and write down what is still open."

The third thing is the one nobody has published. Every system in the
literature either resolves an ambiguity, asks about it, or is measured
failing to. None of them writes an unresolved ambiguity down and
proceeds. That is what the requirements document below does, and the
project should expect to be measuring rather than inheriting.

## A word doing two jobs, and how it is split

The agent layer already calls a seat **intake**: the surface that turns
a resident's words into a `request` record (`castle ask`,
`agent/castle-modal`). Task 0065's title uses "intake" again for this
phase. Two different things, one word, and a reader cannot tell which is
meant — so nothing here is called intake. The vocabulary is:

- The **statement** is the resident's request as it arrives.
- The **transcript** is the conversation: the statement, the questions
  the phase asked, and the answers.
- The **requirements document** is what the phase produces: what the
  system now believes it is building, with what it does not know still
  attached.

## The artifacts

All three are plain markdown with a header of `Key: value` lines. The
format is boring on purpose — boring enough that a session with nothing
but a text editor can produce one, and boring enough that a checker
needs no parser library.

### The transcript

Blocks, each opening `## <kind> <id>`, then a contiguous run of
`key: value` lines, then a blank line, then prose. Three kinds:

    ## utterance U1
    speaker: resident
    date: 2026-09-08

    The mouse cursor is too small to find on this laptop's panel.

    ## question Q1
    clause: cursor-visible-size
    tag: vagueness
    type: discriminating

    How will you know the cursor is big enough? ...

    ## utterance U2
    speaker: resident
    answers: Q1

    My eye. Put candidate sizes up side by side, I pick one.

    ## stop
    reason: below-threshold
    best-remaining: 0.06
    leading-weight: 0.68
    alpha: 0.25

Field lines are contiguous from the top of a block: the run ends at the
first line that is not a field, blank lines included, so a sentence of
prose that happens to carry a colon is never silently read as one.

Every utterance declares `speaker:`, and only `speaker: resident`
utterances can ground a `[stated]` clause or count toward coverage.
Unattributed or system-authored text scoring as the resident's words
would defeat both marks at once: faithfulness would credit invention,
and coverage would count text the resident never produced.

An utterance may carry `substantive: no` with a `reason:` — that is how
a closing "thanks, that's it" is excused from the coverage count. The
reason is required so that the coverage number is not simply whatever
the phase decided to count.

`answers:` names exactly one question. The phase asks one question per
turn, so a reply covering two of them is two utterances; the checker
refuses the comma-separated form by name rather than letting it fail
later as a missing question id.

A question carries `type: discriminating` (the default) or
`type: clearinghouse`. The stop block is last and is described under
rule 4.

### The requirements document

Sections of clauses. A clause is `### <title> [<key>]`, then `Level:`,
then prose opening with `[stated <date>]` or `[inferred]`, then
`Traces:` and any number of `Ambiguity:` lines. Every `###` heading is a
clause and every clause carries a key — a keyless one is refused rather
than absorbed into the clause above it. The mark is read off the
clause's *opening* line only: a clause that opens with an unattributed
assertion and picks up a `[stated]` further down is the system's reading
wearing the resident's words, which is the thing the mark exists to
stop.

`Level:`, `Traces:` and `Ambiguity:` are reserved names: a line
beginning with one is read as that field wherever it sits in the clause,
so prose must not open a sentence with one. A second `Level:` or
`Traces:` in a clause is refused rather than allowed to overwrite the
first and disappear out of the prose.

    ### The surface the cursor is drawn on [cursor-surface]

    Level: goal

    [stated 2026-09-08] The cursor in scope is the one the compositor
    itself draws. ...
    Traces: U1, U3
    Ambiguity: semantic certainty=0.45 state=open — whether the console cursor before a graphical session starts is also in scope. Asked as Q2 and answered only in part ...

`Level:` is `goal`, `input` or `constraint`, in the order their measured
value decays: goal clarification loses nearly all its worth if it is not
asked early, input clarification holds for a while, constraint
clarification barely pays at any point. The level is what decides
question order and what may be deferred.

An `Ambiguity:` line names one of four categories — `lexical`,
`syntactic`, `semantic`, `vagueness` — and carries three things:

- `certainty=` — the share of sampled interpretations that hold the
  leading reading. This is the estimate, not a confidence: it comes from
  sampling several implementations or readings consistent with the
  document so far and seeing how far apart they land.
- `state=` — `open`, `deferred`, or `cleared`.
- prose after an em dash saying what is unresolved, which is the part a
  human actually reads.

An ambiguity is **nocuous** when its certainty is at or below the
document's `Nocuity-threshold:` — that is, when no reading commands
enough of the weight to be treated as the reading. Nocuity is relative
to a tolerance, and the tolerance is per document class: strict for
anything touching authority, looser for a cosmetic preference.

`cleared` requires `ref=<utterance id>`, and that utterance must answer
a question that cited this clause and this category. An ambiguity is
closed by a citation or it is not closed. There is no state for "we
decided" — deciding is what `[inferred]` is for, and `[inferred]` says
whose reading it is.

The document header declares its own knobs before the phase runs:

    Nocuity-threshold: 0.7
    Stop-alpha: 0.25
    Question-budget: 2
    Transcript: transcript.md

These are the phase's private configuration in Principle 01's sense: the
mechanism is public and identical everywhere, and a deployment that
wants a stricter threshold for authority-touching work sets a different
number without touching any of it.

Both the presence of these three and their ranges are checked before
anything else and cannot be narrowed away with `--only`. The reason is
that a knob out of range does not *weaken* the rule computed from it, it
empties the rule out: `Nocuity-threshold: 0` makes nothing nocuous and
rule 1 vacuous, and a `Stop-alpha` above 1 makes every stop satisfy its
own arithmetic. A check that can be switched off by editing a header is
worse than no check, because the run still prints a zero.

## The seven rules

Each rule says what a machine can check and what it cannot. The split is
deliberate: some of this is judgment, and a validator that pretended to
grade judgment would produce ritual compliance rather than reasoning —
the same argument CLAUDE.md makes for `Model-because:`.

**1. Asking is structural, never hoped for.** Every nocuous ambiguity
must be asked about or explicitly passed over; there is no third state
where nothing happened. *Checked:* every ambiguity at or below the
threshold is either cited by a question, `deferred` with a reason, or
`cleared`. *Not checked:* whether the certainty estimate is honest. A
seat that writes `certainty=0.95` on a genuinely contested clause defeats
this, and only a probe or a reader catches that.

**2. Questions are selected in solution space.** Do not ask a model
"what would be a good question here?" Sample several interpretations of
the statement that are all consistent with what is written, then ask the
question that best separates them. The gain comes from reasoning about
solutions rather than about questions. *Checked:* nothing. This is the
one rule with no mechanical residue at all, which is worth saying out
loud rather than implying by omission. Its effect shows up indirectly —
a phase that ignores it produces questions that hit no seeded ambiguity,
and the probe scores that.

**3. Every question cites what it would resolve.** A question carries
the clause key and the ambiguity category it is aimed at. *Checked:*
fully. A question that cites nothing, or cites a clause that does not
exist, or names a category that clause does not carry, is a defect. The
clearinghouse probe is the sole exemption, because the gap it aims at is
by definition not in the document yet.

**4. Stopping is a rule, not a feeling.** The phase stops when the best
remaining question's expected value, net of a penalty for re-asking
about ground already covered, falls below a fraction (`Stop-alpha:`) of
the leading interpretation's weight — or when the budget runs out, or
when nothing was worth asking in the first place. That last exit scores
exactly zero, never negative: not asking is a legitimate move, and the
phase must be able to take it without penalty. *Checked:* the stop block
must state its terms and the terms must actually satisfy the rule it
claims to have stopped under, and its alpha must match the alpha the
document declared before the phase ran. *Not checked:* whether the
numbers describe reality. As with rule 1, the check is for presence and
self-consistency; a human reads whether the reasoning is any good.

**5. Goal-level ambiguities first.** Constraint-level ones may be
deferred into the document's tags. *Checked:* a question about a
lower-level clause may not precede one about a higher-level clause, and
a goal-level ambiguity may never be `deferred` — the ban is on the
level, not on the certainty, so it holds however confident the phase
claims to be. That distinction matters because certainty is a number the
phase writes about itself, and a ban that applied only below the
threshold could be lifted by writing a high one. *Not checked:* whether
a clause's declared level is the right level.

**6. The two errors are not the same size, and both are bounded.**
Treating a nocuous ambiguity as innocuous is the dangerous error; a
wasted question merely spends attention. So the budget bounds the cheap
error — `Question-budget:` blocks when exceeded — while the probes
measure the expensive one. This asymmetry is also why the style lint in
rule 7 warns rather than blocks. *Checked:* the budget. *Not checked:*
the threshold's calibration, which is what probes are for.

**7. Question style has a negative lint, and one required question.**
Four question types steer the answer rather than eliciting it —
forced-choice with no escape, leading, declarative, negative-balance —
and a steered answer is not the resident's answer. All four are detected
by keyword heuristics and all four **warn only**. Indicators of this
shape run at 30-59% precision in the requirements literature, and a
blocking check at that precision teaches a seat to stop asking, which
trades the cheap error for the expensive one. Against that, the
**clearinghouse probe** — "what have I not asked about that matters?" —
is required, and must be the last question asked. It is the only
question aimed at the forgot-to-specify gap, which no discriminating
question can reach by construction. *Checked:* both, at their stated
strengths. Run `clarify --strict` to make the warnings block, which is
useful when tightening a fixture and wrong as a gate.

## The exit: read-back

The phase ends by restating what it now believes it is building — the
requirements document, not the transcript — and the resident's verdict
on that restatement is the gate. Only the resident can give it.

The machine-checkable half is a pair, and both halves are needed:

- **Faithfulness** catches invention. Every clause is traceable to
  something the resident said, or is marked `[inferred]` and thereby
  admits to being the system's own reading.
- **Coverage** catches omission. Every substantive utterance is
  reflected in at least one clause. A read-back checked only for
  faithfulness passes a document that quietly dropped half the
  conversation.

The honest limit, which the source of this pair states about itself:
**coverage is not completeness.** Requirements legitimately come from
outside the conversation, which is what `[inferred]` is for, and no
count of covered utterances says the document is right. The
human-confirmed half of read-back has not been evaluated anywhere; this
project is measuring it, not inheriting it.

## Probes

A phase that is never measured drifts, and the direction it drifts is
not predictable from the outside: it can become an interrogation or
revert to silent commitment, and both look like a working phase from a
distance.

A probe is a complete statement with answers deleted out of it.
Deletion only — never contradiction — because deleting cannot
accidentally manufacture an inconsistency while aiming for an ambiguity.
That property comes from the format rather than from a check: a seed
record can express nothing but a span to remove, and the builder's only
operation is removing one. `clarify probe build` does assert that the
result is a subsequence of the source, but be clear about what that
assertion is worth — it cannot fail as the builder is written today, and
it is there as a guard against a future builder that grows the ability
to add text. The check that can actually fail lives in
`test/clarify/run.sh`, which re-derives the seeded statement from the
source and the seed record by its own implementation and compares byte
for byte.

The seed record holds the deletions, the ambiguity category each one
creates, and the terms a question would have to contain to count as
having found it. It is never copied into the run directory, so the
isolation is structural rather than promised.

Two scores, always together:

- **Coverage** of the seeded ambiguities. Rewarding this alone builds an
  interrogation.
- **Redundant-question rate**: questions that hit no unhit seed.
  Penalising asking alone rebuilds silent commitment.

Both floors are declared in the seed record *before* the first run and
changing either is a decision somebody makes on the record. A floor
chosen after seeing a score is not a floor — Proposal 06's discipline,
which also supplies the other rule here: a probe artifact carries
`Probe:` in its header and may never sit under `docs/state/`. It is
shaped exactly like current truth, and nothing but the label
distinguishes them.

Every probe ships an `oracle/` — a transcript and requirements document
that catch every seed — because a seeded ambiguity that nothing could
catch measures the seeder rather than the phase.

The matching between questions and seeds is literal term matching, not a
model's judgment. That is crude, and it is crude deliberately: this runs
in CI with no network and no model, and a score that needed a model to
reproduce would not be a score anybody could check.

## Running it

    tools/clarify/clarify check docs/state/<requirements>.md
    tools/clarify/clarify probe build cursor-too-small --out /tmp/run
    tools/clarify/clarify probe score cursor-too-small /tmp/run
    tools/clarify/clarify probe oracle cursor-too-small

`check` finds the transcript through the document's `Transcript:`
header. `--only form|questions|readback` narrows it. Exit status is zero
when every blocking check passed; warnings do not fail unless
`--strict`.

## What this phase does not do

It is not wired into `castle-modal`. Questions do not yet route to the
resident automatically; that is the answer channel task 0022 built, and
connecting the two is separate work. The phase works today as a
conversation over files, which is the order the design demands: a phase
that only works through a UI cannot be checked, and a phase that cannot
be checked is the thing this document exists to avoid.

It also does not decompose a milestone into task briefs. That is the
next unspecced piece and a different problem.

## Where the judgment still lives

Everything above narrows what can go wrong. None of it decides whether
the phase asked the *right* questions — no check in `clarify` can, and
a reader who takes a green run as a verdict has made exactly the
promotion Proposal 06 forbids. The green run says the discipline was
followed. Whether following it produced the right requirements document
is the resident's verdict on the read-back, and nothing else.
