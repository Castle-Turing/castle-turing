# The outcome row is written by hand

**What.** A task's row in `docs/log/task-outcomes.tsv` is appended by
the session that did the work, running
`tools/outcomes/outcomes derive --env <key> --fill` on the branch
before it opens the pull request. Task 0072 named that step, gave it an
owner in agent guidance, and put a lint in CI that fails if the naming
is ever removed. What it did not do is make the step happen without
somebody choosing to take it.

**Why it matters.** Everything this repository says about machine-kept
state says a step held in place by somebody remembering decays.
`docs/state/README.md` rule 2 is exactly that, and the measurement
literature the log rests on says it about logging specifically. Two
failure shapes follow from this one. A session that forgets fails the
coverage gate, which is noisy and cheap — the good half. A session that
runs it *late*, after landing, writes `queued` from a commit date that
has drifted, and `queued` is immutable. The cheap moment and the
accurate moment are the same moment, and nothing currently holds the
step to it.

**What the wired version is.** The delivery seat (`docs/architecture.md`,
task 0069) writes the row when it opens the pull request, alongside the
record shim that seat already owes the journal (task 0071). The seat is
occupied today by emcee, a separate repository, which is why task 0072
could not land it: there is no code in this checkout that opens a pull
request. The work is in emcee, and it is small — the seat already knows
the task's brief, the environment it dispatched into, and the tier it
routed at, which are precisely the three cells a session has to supply
by hand today.

**How this would have been caught sooner.** It is being caught, by the
coverage gate task 0070 built: a brief that lands with no row fails the
next pull request that touches `docs/tasks/` or `docs/log/`. That gate
is the detector for a *missing* row and it is enough. The detector this
entry still owes is for a *late* one — an immutable cell derived after
the fact reads exactly like one derived on time. The candidate check:
`derive` refuses to write a `live` row whose `queued` date is older than
some small number of days, on the ground that a live row being written
about last week's work is not live. It is not built, and the reason is
that the threshold is a guess until the wired version makes lateness
rare enough to be an exception worth failing on.

**Open questions.** Whether the seat writes the row or runs `derive`
(the second keeps one derivation, the first keeps the seat's own
knowledge). Whether a row written by the seat is still `provenance:
live` or earns a third value naming who wrote it. What the seat does
when the log's `check` fails on the branch it just wrote — the row is
the thing the gate wants, and a seat that pushes an unloggable row has
made the gate's failure its own.
