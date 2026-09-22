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

**The failure this actually names.** Not that a row is written by
hand — that the outcome-log work was marked complete while it armed a
gate that fails against the pipeline as it then stood: nothing wrote
rows, so every subsequent task pull request would fail the coverage
check until the operator hand-edited the log. Deferring the wiring
would have been a fine call — but a deferral is only real when it is a
written backlog entry, and none was; the gap was reconstructed only
when the resident caught the failing builds. "Complete" cannot mean
"green only while a human performs a recurring manual step nobody
automated or filed."

**How this would have been caught sooner.** The guard is at acceptance,
not in a late-row lint: a task that arms a gate is not done unless the
gate passes against the repository as it will be after merge without a
standing manual step, or the shortfall is a backlog entry that exists.
This is the same acceptance rule `passing-tests-are-not-acceptance.md`
draws and the same obligation `an incident ships its detector` places
on a filed regression — a check is not delivered by being armed; it is
delivered by being fed. Whether any part of this is mechanical (a task
whose merge would leave a required check red against the current tree
is a candidate signal) or whether it stays an acceptance-review
judgment is the open question — but the late-row `queued`-drift check
this entry first proposed is not the guard, and has been dropped.

**Open questions.** Whether the seat writes the row or runs `derive`
(the second keeps one derivation, the first keeps the seat's own
knowledge). Whether a row written by the seat is still `provenance:
live` or earns a third value naming who wrote it. What the seat does
when the log's `check` fails on the branch it just wrote — the row is
the thing the gate wants, and a seat that pushes an unloggable row has
made the gate's failure its own.
