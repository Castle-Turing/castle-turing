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

**The three open questions, answered.** Task 0081 answered them in
`agent/castle-delivery-shim`'s `row` subcommand rather than leaving
them to drift.

*Does the seat write the row, or run `derive`?* It runs `derive`. The
cells the seat holds — model, cost, turns, the pull request — are
exactly the cells `harness_facts` already reads out of the same journal,
and a second derivation of the same numbers is the drift `check` exists
to catch.

*Is a seat-written row still `provenance: live`?* Yes. The column says
*when* the row was written, not *who* wrote it, and a seat maturing a
row while the attempt is still warm is `live` by that definition. A
third value would make one column answer two questions, where `env` and
the seat's own `claim` record already answer the second. It is also
immutable and written at transfer, so a third value could only arrive
by rewriting history.

*What if `check` fails on the branch the seat just wrote?* The seat says
so, exits non-zero, and leaves the filled log in the working tree for a
human to read as a diff — `derive --fill`'s own stated contract. It
cannot push an unloggable row because it does not push at all.

**What is still missing, and it is the whole remaining half.** Nothing
calls `row`. It refuses any checkout that is not on the errand's own
branch, which is the correct refusal and also means a journal hook
firing against the operator's primary checkout can never satisfy it:
the accurate moment is inside the seat, before the pull request opens,
and the seat is emcee. That is the same sentence this entry opened with
— "the work is in emcee, and it is small" — now with a castle-side
command for it to call, and a mechanical failure rather than a
convention standing in for the caller.
