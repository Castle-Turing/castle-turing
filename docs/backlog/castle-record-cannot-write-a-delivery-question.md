# `castle record` cannot write a delivery question

**What.** `castle record --blocking` refuses a question whose first
`--refs` entry does not walk back to a `request` record. A delivery
errand has no `request` record to point at — its upstream is a numbered
brief, a file — so the one hand-writable path to a blocking delivery
question is closed. `agent/castle-delivery-shim` writes through
`write_record` instead, which is how every other seat's hands write,
but a human holding the delivery seat at a keyboard has no equivalent.

**Why it matters.** The architecture's founding claim about seats is
that "any intelligence that can read and write those artifacts can hold
the seat — a frontier model behind a harness, a local model, a shell
script in CI, or a human at a keyboard." A seat with a record only one
program can write has quietly stopped being that. The gap is small
today because the shim is the only writer; it becomes load-bearing the
first time somebody has to park a delivery errand by hand because the
shim is down, which is exactly when the hand path matters.

**What the fix probably is.** The guard's real rule is not "refs[0]
reaches a request" but "this question is attributable to something that
can resume it." For a worker question that is the refs chain; for a
delivery question it is the errand the record names. Teaching the guard
the second form — rather than exempting a seat, which would let any
caller claim the exemption — keeps it a guard. Whether the shim should
then go back through `castle record` is a separate and probably
negative call: writing in-process is what `route_journal` and
`file_answer` already do.

**How this would have been caught sooner.** It was, and by the thing
that should catch it: writing the shim against the real CLI surfaced it
immediately. What has no detector is the *claim* the architecture makes
— that every record type is hand-writable through `castle`. Nothing
checks that today, and a check that walked `RECORD_TYPES` against the
CLI's own refusals would have named this before a seat needed it.
