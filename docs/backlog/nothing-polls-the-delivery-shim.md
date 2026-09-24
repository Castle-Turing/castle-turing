# Nothing polls the delivery shim

**What.** Both directions of `agent/castle-delivery-shim` are designed so
that a doorbell and an interval poll are the same command — a missed
notice delays a read or a resumption and never changes what either
finds. `fold`'s doorbell half is wireable today (the tenant's roster
names a `journal_hook` per repository). Every other half is wired by
nothing: no timer, no sweep, no CI step runs `fold` on its own, and
nothing at all runs `resume`.

**Why it matters.** Two failures, and the second is worse than the
first. The hook is best-effort by the tenant's own statement — no
ordering guarantee, no retry, no at-least-once promise, and a hook still
running after ten seconds is killed — so without the poll a dropped
firing means a `claim`, `result` or blocking `question` that simply never
reaches the journal, and it looks exactly like a quiet day: the errand
ran, the pull request opened, and the journal the weekly audit reads says
the seat did nothing.

The inbound direction has no doorbell at all. `resume` (task 0082) is a
total fold over the journal and correct on any trigger, and nothing
triggers it — so an answer the resident gave sits unspent until somebody
runs the command, and the delivery paragraph's bound is kept by a
mechanism nobody calls. The one thing that is no longer silent is the
silence itself: `castle-delivery-shim stranded` reports a delivery
question that has had no resumption path for N days, and it exists
precisely because this gap does.

**What the wired version is.** A castle-side timer — the natural home is
beside the other things `modules/agent` already declares — running
`fold` and `resume` per configured run directory on an interval. `resume`
needs one input `fold` does not: the repository the run's errands belong
to, for the tenant's own verb. That is per-run configuration and the
module is where it belongs.

Task 0071 left the interval deliberately open: how large a blind window
is tolerable is the resident's judgment and not a fact any brief can
derive, and it is the one thing about this shim that genuinely needs
human hands. The inbound direction narrows the question rather than
changing it — a resumption that waits is the resident waiting on work
they already unblocked, which is a shorter tolerance than a record
arriving late.

**How this would have been caught sooner.** The same acceptance rule
`passing-tests-are-not-acceptance.md` draws: a mechanism whose liveness
depends on a caller nobody has written is not delivered. The mechanical
form of the check is `tools/reachability-check.py`, which fails a tool
under `tools/` that nothing calls — it does not scan `agent/`, which is
where seat hands live, and widening it there would have named this
automatically.
