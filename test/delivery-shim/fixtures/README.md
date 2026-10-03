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
| an errand resumed by the inbound half | `resumed/` | the dovetail park, answered through `castle answer` and resumed by the tenant's own verb — see below |

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

## `resumed/` — the inbound half's capture

`resumed/` is what the live exercise produced: the dovetail park above,
folded into a castle journal, answered through `castle answer`, and
resumed by **emcee's own `resume` verb** with no relaunch by hand. It is a
capture like every other directory here, from a real run of the real verb,
and `../tenant-boundary.sh` is the script that produces it — run by hand on
a host that has the tenant, because the stock CI runner does not.

Three parts:

- `dovetail/2026-09-05T01-45-45/journal.jsonl` — the tenant's journal after
  the whole loop. It carries the original park, then the tenant's own
  `answered` record naming the `Answered-by:` line the shim wrote, then the
  errand's second `step_started`, and finally a re-invocation that
  dispatched nothing and recorded `sentinel_held{reason: nothing_dispatched}`.
  That last part is the property the write-ahead ordering depends on, in the
  tenant's own words.
- `dovetail/2026-09-05T01-45-45/parked/README.md` — the question file as the
  shim filled it in and the tenant then resolved. `../run.sh` reads it with
  the shim's own reader, so a drift in the pinned header spelling fails
  there rather than silently making an answer invisible to the tenant.
- `records/` — the nine castle records that run produced, including the
  resumption `claim` whose `refs` name the answer. They validate as a
  journal.

**The answer in this capture is not the resident's.** It was written by the
implementing session as a stand-in, through the real `castle answer`, so the
record's `provenance: requested` and `seat: intake` are exactly what that
path writes and the mechanism was exercised exactly as it will be in
service. What has not happened is the falsifier task 0082 names: the
resident's own answer, through the real surface, on a real parked errand.
That step needs their hands and the brief says so; nothing here should be
read as it having happened.

The tenant ran with its dry-run adapter, so the second attempt called no
model — `adapter: dry-run`, `cost_usd: 0` on the `usage` record say so on
the page. Everything the resumption actually turns on is the real verb:
the park's file, `resolvable`, the selection loop, and the `resolve` that
happens strictly before dispatch.

## What was changed, and it is the only thing

Three substitutions, applied mechanically to every byte of every file:
the operator's home-directory prefix becomes `/home/operator`, their
login name wherever a record quotes it becomes `operator`, and the name
of their private profile repository — which appears inside command
strings the tenant journaled — becomes `chevaline-profile`.

Those three are personal data, and this repository takes no personal
data in any file, fixtures included. They are described here rather
than tabulated for the same reason: a table of what was redacted would
put the values back. Everything else — timestamps,
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
