# The delivery shim's fixture corpus

Every journal here came out of emcee's own writer on a real sprint.
That is the corpus's whole value: a hand-written fixture encodes what
somebody believed the tenant's schema to be, and a captured one encodes
the schema — including the quirks nobody would have thought to
reproduce. Two directories are derived from captures rather than
captures themselves, and both say so in their names: `no-identity/` and
`synthetic-retry/`.

## The shape checklist, and where each shape is covered

| shape | fixture | how |
| --- | --- | --- |
| brief taken | all four | `step_started`, keyed by the errand's own name |
| pull request opened | `castle-turing/2026-09-22T09-09-47` | two errands, each `pr` then `step_finished{outcome: pr_opened}` |
| given up | `emcee/2026-09-05T13-22-37` | `step_finished{error}` — the tenant died on a provider error |
| parked on a question | `dovetail/2026-09-05T01-45-45` | `parked`, with the question file it names still beside it |
| resumed second attempt | `emcee/2026-08-20` | parked, `answered`, then a second `step_started` for the same errand |
| an attempt's facts, per attempt | `synthetic-retry/` — **synthetic**, see below | two `step_started` records for one errand, with different models |
| a replayed event | every fixture | a property of the fold, proven by running it twice over these same logs rather than by a shape in any of them |

Two of them carry a second shape worth having on purpose. `emcee/2026-08-20`
predates emcee making `model` a required field, so its results exercise
the refusal that fires when a result cannot name its implementer; and
`emcee/2026-09-05T13-22-37` is the one adapter that records its provider
explicitly, so it exercises the first of the two provider rules while
the others exercise the second.

**No shape on the checklist needed provoking.** The brief's second tier
— run a one-task sprint against a disposable repository to force a
missing shape — was not reached, because the inventory of existing run
history covered the checklist outright.

**One fixture is synthetic, and it is `synthetic-retry/`.** It is named
that way on purpose; a synthetic fixture passing silently as real
coverage is a checker that cannot fail. It exists because of a property
the corpus cannot otherwise show: an attempt's model and pull request
must be attributed to *that* attempt, and the corpus's one retry inside
a single run is the 2026-08-20 journal, which predates `model` being
required — so both of its results refuse, and a misattribution between
them would be invisible. `synthetic-retry/` is that same real journal
with `model` and `model_source` added to its `step_started` records,
differing between the two attempts, and nothing else changed.

**The criterion resting on it, named:** "an attempt's facts belong to
that attempt, not to the errand" (check 9). Every other criterion in
`../run.sh` runs against captured journals. This one is downgraded from
real to synthetic, and it will stay that way until a run with a
retry-and-a-model lands in history — at which point capture it and
delete this.

## What was changed, and it is the only thing

One substitution, applied mechanically to every byte of every file:

    /home/wesley         ->  /home/operator
    "wesley"             ->  "operator"
    chevaline-whharris   ->  chevaline-profile

The operator's home directory, login name and private profile
repository are personal data, and this repository takes no personal
data in any file, fixtures included. Everything else — timestamps,
session ids, costs, turn counts, model ids, pull-request URLs, the
tenant's own error strings, and the records the shim ignores entirely —
is exactly as emcee wrote it.

`no-identity/` is the one derived fixture, and says so by its name: the
`castle-turing` journal with every `seq` removed. It is a journal that
cannot be folded, and it exists to prove that the shim refuses one
rather than guessing.

## Refreshing a fixture

Capture, redact, commit — never edit in place. A fixture edited by hand
to make a test pass has stopped being evidence of anything.
