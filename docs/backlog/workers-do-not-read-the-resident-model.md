# Workers never see the resident model

**What.** `docs/architecture.md` describes the resident model as "an
artifact the router and workers read." The router reads it. No code
passes it to a worker, on any turn.

**Why it matters.** The resident model is where the system's durable
knowledge of stated preferences lives — the artifact the whole
apprenticeship idea in `docs/vision.md` accumulates into. A worker seat
that cannot read it is doing every errand with no idea who it is working
for, which means either it asks questions the model already answers, or
it guesses. Both are the failure the model exists to prevent.

**What we already know.** Task 0023 built the continuation packet — a
rendering of an errand's own records handed to a fresh worker tenant on
every turn — and deliberately left the resident model out of it (§7).
Three reasons, worth keeping: it is a different feature from resumption;
it applies equally to first turns, so folding it into a resumption task
would put it in the wrong place; and 0023's diff was already large.

A resumed tenant is the case that makes the gap most visible. It arrives
holding the resident's verbatim answer to one question while knowing
nothing else the resident has ever stated — the narrowest possible view
of a person the system supposedly has a durable theory of.

**Open questions.** Does the worker get the whole model or a relevant
slice, and if a slice, who selects it and is that selection a judgment
under Proposal 05? Does it arrive on stdin with the rest of the packet,
or by a path the tenant reads itself? What stops a worker treating a
stated preference as authority to act (0023's §S5 boundary — the answer
closes a question, it does not grant authority — generalizes here)?
Should a worker be able to *write* to the model, or is elicitation
strictly intake's? And does handing a tenant the resident's stated
preferences change what may be committed to a public repo in a test
fixture — the model is private-layer data by construction.
