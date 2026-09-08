Title: Task 0065 — the clarifying-questions intake
Model: deep
Requires: 0061
Milestone: m2-done
Model-because: the deliverable is the phase that decides what gets built — a requirements state document plus the discipline that fills it — and every measured failure in its literature is a plausible artifact hiding a wrong reading (silent commitment). A smaller implementer would produce a working question loop whose questions are the wrong questions; nothing mechanical can tell it so. What is mechanical here (the lints, the probe harness) is not the part that can be got wrong.
Requires-because: the phase's output is a `docs/state/` requirements document using 0061's clause keys, stated-versus-inferred marks, and ambiguity tags; without that layer there is nothing disciplined for answers to patch.

# Task 0065 — the clarifying-questions intake

**Status: drafted 2026-09-06 at the close of the research loop,
after the resident approved tasks 0061/0062 but NOT yet read by the
resident. The review of this PR is the approval gate: merging queues
this brief; requesting changes sends it back. It must not be
implemented from a branch state the resident has not merged.**

**Before starting:** read `CLAUDE.md` and
`.claude/skills/implement-brief/SKILL.md`. Then
`docs/research/elicitation-papers.md` in full — its design
implications 1–10 and both dated addenda are this brief's evidence
base, and this brief deliberately repeats none of the citations it
compresses. `docs/state/README.md` binds the output artifact's form.

## What this is, in the milestone's terms

`[m2-done]`'s opening move: the resident opens the modal, complains,
points at a comp — and the system asks exactly the right questions
before anything gets built. This brief specs the phase's *artifact
and discipline*; wiring it into castle-modal's surface is a
follow-on, so the phase must work first as a plain conversation over
files (a brief-shaped intake document in, questions and answers
through the existing answer channel, a requirements state document
out).

## The output artifact

A requirements state document under `docs/state/` (one per intake,
promoted into or superseded by the milestone file as the resident
decides): clauses with keys, each marked `[stated]` or `[inferred]`,
each carrying its unresolved-ambiguity tags by category (lexical,
syntactic, semantic, vagueness — Orchid's taxonomy) until a cited
answer clears them. Unresolved ambiguity is *written down and
carried forward*, never resolved by silent choice — the literature's
named primary failure, and territory where no published system does
what this one will.

## The question discipline, each rule from measured evidence

1. **Asking is structural, never hoped for.** Frontier models'
   natural asking rates span 0%–52% on identical tasks; the phase
   *requires* an ask-or-explicitly-pass step per tagged clause.
2. **Questions are selected in solution space.** Sample multiple
   interpretations consistent with the current document; ask what
   best discriminates between them — never "what would a good
   question be?"
3. **Every question cites** the clause key and ambiguity tag it
   would resolve; a question with no citable tag is a defect the
   lint catches.
4. **Stopping is a rule, not a feeling**: stop when the best
   remaining question's expected value, minus a redundancy penalty,
   falls below a fraction of the leading interpretation's weight —
   with an explicit "no clarification needed" exit that scores zero,
   not negative. Budget toward one or two well-targeted questions;
   the measured failure is over-asking and under-targeting at once.
5. **Goal-level ambiguities first**; constraint-level ones may be
   deferred into the document's tags — goal clarification loses
   nearly all value after 10% of execution, constraint clarification
   barely pays at any point.
6. **The error costs are asymmetric and both bounded** (the 2005
   origin report's rule): treating a nocuous ambiguity as innocuous
   is the dangerous error, a wasted question merely spends
   attention — so the budget bounds the cheap error while the
   probes below measure the expensive one. The nocuity threshold τ
   is a per-document-class knob (stricter for authority-touching
   intakes), estimated by sampled-interpretation divergence.
7. **Question style has a negative lint**: the content-maneuvering
   types — forced-choice, leading, declarative, negative-balance —
   are flagged (warn, not block: indicator precision). The
   clearinghouse probe ("what have I not asked that matters?") is a
   required closing question — it is the forgot-to-specify gap as a
   question type.

## Exit: read-back

The phase ends with the system restating what it now believes it is
building — the requirements document, not the transcript — and the
resident's verdict on the restatement is the gate. Machine-checkable
half, which ships with this task: a faithfulness-and-coverage pair
over the conversation (every clause traceable to an utterance or
marked `[inferred]`; every substantive utterance reflected in some
clause, so omission is as detectable as invention). The
human-confirmed half is unstudied anywhere; the golden test below is
its first measurement.

## Measured by seeded probes

The probe harness ships with the phase, per the QC-with-everything
direction: seed intakes with ambiguities — Orchid's labelled variants
directly for code-shaped tasks, deletion-only editing (never
contradiction) for this repo's own brief-shaped intakes — with the
seed record isolated from the agent's reach and an oracle
demonstration that each seed is catchable. Score coverage of seeded
ambiguities *and* redundant-question rate together: rewarding only
asking builds an interrogation, penalizing only asking rebuilds
silent commitment. Probe records follow Proposal 06's salt
discipline: pre-registered, labeled in the journal, never
masquerading.

## What this does not do

No castle-modal wiring (follow-on; the phase must work over plain
files first). No automatic milestone decomposition — that is
[m2-now]'s largest unspecced piece and a separate brief. No question
delivery changes: questions travel the existing channel (task 0022's
answer path). No training or fine-tuning: rules 2 and 4 are
implementable as sampling and scoring with the session's own model.

## Verification

Machine: the lints (rules 3 and 7), the faithfulness/coverage
checker, and the probe harness run on a fixture intake — a seeded
version of a real past request ("the cursor is too small" is the
canonical candidate: small, real, and its true requirements are now
known history). Human, and this task's falsifier: the resident runs
one real intake end to end — if the phase's questions feel like an
interrogation, or the read-back misstates what they asked for and
the checker passed it anyway, the discipline has failed its purpose
and goes back for revision.

## As built

Added on the implementing branch, per CLAUDE.md's rule that a brief the
work has overtaken is worse than none. The design above did not shift;
what follows is where it landed and the calls the brief left open.

**Where it lives.** `docs/clarifying-questions.md` is the phase — the
artifact grammar and the seven rules, written for a stranger.
`tools/clarify/clarify` is the checker, `tools/clarify/probes/` the
seeded probes, `test/clarify/run.sh` the CI harness,
`.github/workflows/clarify-check.yml` the gate. `docs/state/README.md`
gains a "Requirements documents" section — the deliberate accommodation
its own rule 4 requires.

`tools/` rather than `agent/`, and the boundary is real: the phase is
destined for the product, and when the modal wiring lands the checks
should follow it. Recorded in `tools/README.md` beside the same tension
the sweep scripts carry, rather than settled quietly. Putting it in
`agent/` today would install an unwired phase onto deployed machines and
put a Nix rebuild behind every edit to a lint.

**The naming collision, resolved.** This brief's title says "intake",
which is already the agent layer's word for the seat that turns a
resident's words into a `request` record. One word, two jobs. The
implementation uses none of it: the **statement** is what the resident
said, the **transcript** is the conversation, the **requirements
document** is the output, and the tool is `clarify`.

**Rules 4 and 7 conflict as written, and the resolution is a choice.**
Rule 4 grants an explicit "no clarification needed" exit; rule 7 calls
the clearinghouse probe "a required closing question". A phase taking
the zero-question exit cannot do both. As built: the clearinghouse probe
is required if and only if at least one question was asked. The reading
is that a phase which asked nothing has already asserted there was
nothing to ask, and forcing a question on it would make the zero-value
exit cost one question — which is the thing rule 4 exists to prevent.

**Nocuity is `certainty <= tau`**, following the threshold's original
definition: an instance is nocuous when no interpretation's certainty
exceeds the tolerance. Declared per document rather than globally, which
is the per-document-class knob rule 6 asks for. The tool checks that the
number is declared before the run and used consistently; it cannot check
that the number is right, and does not pretend to.

**Rule 2 has no mechanical residue.** Sampling interpretations and
choosing the question that discriminates between them is not visible in
the artifacts, so nothing checks it. Stated in the phase document rather
than left as an implied gap — its effect shows up only indirectly, in a
probe score.

**Seed matching is literal term matching**, not a model's judgment: this
runs in CI with no network and no model, and a score needing a model to
reproduce is not a score anybody can check. The seed record registers the
terms. The clearinghouse probe is excluded from the redundancy
denominator, since by construction it hits no seed.

**The probe ships two seeds, both goal-level**, with coverage floor 1.0
and redundancy ceiling 0.0 pre-registered. Goal-level because that is
the kind whose value collapses if it is not asked early, so it is the
kind worth being able to tell whether the phase reaches.

**The question budget blocks; the style lint warns.** That asymmetry is
rule 6 implemented rather than described: the budget bounds the cheap
error, and a blocking style lint at 30-59% indicator precision would buy
that at the price of the expensive one.

**Its own CI workflow, not a job in `check.yml`.** That workflow carries
`paths-ignore: docs/**` deliberately (task 0018), and a requirements
document under `docs/state/` is prose by that filter's reckoning — the
one gate on those documents would never have fired on the PRs that
change them.

**What is unrun.** The falsifier in this brief's verification section:
the resident has not taken one real statement through the phase end to
end. No requirements document exists from a real statement — the only
one in the tree is the probe's oracle, labelled as such. Everything
green here says the discipline is checkable, not that following it
produces the right questions.
