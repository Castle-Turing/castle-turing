# The outcome row is written by CI after the fact, not by the seat that opens the pull request

**What.** `.github/workflows/outcomes-row.yml` derives a task's outcome
row and commits it to the pull request's branch (task 0072). That is not
where it belongs. The seat that opens these pull requests is
**delivery** (`docs/architecture.md`, task 0069), and it should write
the row when it takes the brief, alongside the `claim`, `result` and
`question` records it already owes the journal. Two things should move
it there: the delivery seat gaining a record shim at all
(`docs/backlog/the-delivery-seat-has-no-record-shim.md`), and this row
being one of the things that shim writes.

**Why it matters.** Three costs, in increasing order of how much they
actually matter.

The row arrives late. CI writes it after the pull request is open,
which means a window where the branch exists and the coverage gate is
red, and a second push on every task pull request.

The row is disconnected from the journal. The weekly audit reads
records; the row is a TSV line in another file with nothing tying it to
the `claim` that started the attempt. Cost, turns and model have to be
reconciled by matching task stems rather than by following a reference.

And the arrangement launders a seat's work through a workflow. Task
0069's whole argument is that the delivery seat is a *named* seat rather
than an invisible harness, precisely so its parks, retries and routing
appear somewhere the audit can read. A row written by CI on the seat's
behalf is the seat's work appearing under someone else's name, which is
the shape 0069 was written to stop.

**What we already know.** Why it landed as CI and not as the seat: this
repository contains no code that opens a pull request. The delivery seat
is a name given to a harness in another repository, so there was nothing
local to wire `derive` into at PR-open time, and guessing that harness's
hook contract from memory is how a confident wrong integration gets
written. Task 0072 §1 records the choice and the three properties that
make a bot writing rows tolerable meanwhile: `derive` has no code path
to a verdict cell, the log is held append-only against the merge base so
a bad run can only fail its own gate, and the workflow terminates
because its own push finds nothing left to do.

Also settled and worth not re-deriving: the *verdict* columns must not
follow the row into the seat. `outcomes redirect` requires a citation
the resident authored, and no workflow may run it. Whatever writes the
receipt row, a verdict stays transcribed by an agent from something the
resident said.

`docs/backlog/coverage-is-checked-against-a-base-that-can-move.md` is
the adjacent, unclosed problem: the branch-side row does not help when
another task lands between a pull request's last check run and its
merge.

**Open questions.**

- Does the seat write the row directly, or write a journal record that
  something else folds into the log? The second keeps the log's writer
  single and the journal authoritative, at the cost of a fold nobody
  has designed.
- What does `env` come from once the seat writes it — the harness's own
  environment, or configuration in the checkout? The column is
  immutable, so this decides a permanent value.
- Does the CI workflow stay as a backstop after the seat does this, or
  come out? A backstop that never fires is also a thing nobody notices
  has broken.
