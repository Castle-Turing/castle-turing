# docs/log — append-only measurement

One kind of file lives here: a log that is written once and never
edited, because something later depends on its past being unaltered.

`task-outcomes.tsv` is the first. Its definitions, its column meanings
and the reasoning for all of it are in `docs/measurement.md`; task 0070
is the brief. `tools/outcomes/outcomes check` enforces the rules on
every pull request that touches it.

## Why this is not `docs/state/`

`docs/state/` holds what is true *now*, maintained and patched as the
world moves. A log is the opposite: it is a record, finished the moment
each row is written, and its value comes entirely from staying exactly
as written. `docs/state/README.md` draws that line; this directory sits
on the record side of it, alongside `docs/tasks/` and `docs/research/`.

The distinction has teeth here. A state document that goes stale is a
bug to be fixed. A log row that changes after the fact destroys the
thing the log exists for — a pre-intervention baseline nobody can
quietly improve.

## What may go in one

Counts, dates, keys, enumerations, and identifiers of things that are
already public. No prose beyond a short bounded note, and nothing about
the resident, ever — `docs/measurement.md` states the rule and the
checker enforces a floor under it.

## Who writes a row, and when

Nothing here is written by hand if it can be helped, and the split is
the receipt/verdict split:

**Receipts write themselves.** `.github/workflows/outcomes-row.yml`
runs on every pull request that touches `docs/tasks/`, derives the row
for any brief that has none, and commits it to that branch. So a brief
and its row land together and the coverage gate always has something to
gate. It writes no verdict cell and cannot: `derive` has no code path to
one.

**The step someone owns, when the workflow cannot.** A fork's branch
cannot be pushed to, and a repository with no `OUTCOMES_ENV` variable
set has no environment key to write — in both cases the workflow fails
loudly naming this command, which the operator or the session on the
branch runs:

    tools/outcomes/outcomes derive --fill --env e1 --provenance live --main origin/main

Then commit `docs/log/task-outcomes.tsv` with the work. `e1` is an
environment key from `docs/measurement.md`; `env` is immutable, so
getting it right matters more than getting it quickly.

**Verdicts are transcribed, never derived.** When the resident redirects
an attempt — sends work back, in conversation or on a pull request — the
agent that received the redirect records it against the row, citing
where the resident said it:

    tools/outcomes/outcomes redirect 0070-the-task-outcome-log --ref https://github.com/o/r/pull/120#issuecomment-5659322373

The command resolves the reference and checks that the resident wrote
it before any cell moves; `redirect --help` states both what that check
proves and what it cannot. `redirects_wrong` stays `-` until the
resident reassesses, which is a second thing they have to say, later.
The resident does not run either command; that is the point of both.

## The debt behind this arrangement

The workflow is an interim. The seat that opens these pull requests is
the **delivery** seat (`docs/architecture.md`, task 0069), it lives in
another repository, and the row it should be writing alongside its own
`claim` and `result` journal records is instead written by CI after the
fact. `docs/backlog/the-outcome-row-is-written-by-ci-not-the-seat.md`
carries that, and task 0072 is the reasoning for settling here for now.
