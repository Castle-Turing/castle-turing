# docs/log — append-only measurement

One kind of file lives here: a log that is written once and never
edited, because something later depends on its past being unaltered.

`task-outcomes.tsv` is the first. Its definitions, its column meanings
and the reasoning for all of it are in `docs/measurement.md`.
`tools/outcomes/outcomes check` enforces the rules on every pull
request that touches it.

"Written once" is a claim about facts, not about characters. A row is
appended when an attempt starts and its cells mature as the attempt
does — a pending cell goes from unrecorded to a value exactly once, and
one cell holds an append-only list of citations, because a task can be
redirected twice and a write-once cell could only ever have recorded
the first. What never happens is a recorded fact becoming a different
fact.

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
