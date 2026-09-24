# Nothing polls the delivery shim

**What.** `agent/castle-delivery-shim fold` is designed so that the
tenant's journal hook and an interval poll are the same command — a
missed doorbell delays a read and never changes what the read finds.
The hook half is wireable today (the tenant's roster names a
`journal_hook` per repository). The poll half is wired by nothing: no
timer, no sweep, no CI step runs the fold on its own.

**Why it matters.** The hook is best-effort by the tenant's own
statement — no ordering guarantee, no retry, no at-least-once promise,
and a hook still running after ten seconds is killed. Without the poll,
a dropped firing means a `claim`, `result` or blocking `question` that
simply never reaches the journal, and the failure looks exactly like a
quiet day: the errand ran, the pull request opened, and the journal
that the weekly audit reads says the seat did nothing. Half of the
liveness design is present and idle, which is worse than absent because
it reads as done.

**What the wired version is.** A castle-side timer — the natural home
is beside the other things `modules/agent` already declares — running
`fold` per configured run directory on an interval. Task 0071 left the
interval deliberately open: how large a blind window is tolerable is
the resident's judgment and not a fact any brief can derive, and it is
the one thing about this shim that genuinely needs human hands.

**How this would have been caught sooner.** The same acceptance rule
`passing-tests-are-not-acceptance.md` draws: a mechanism whose liveness
depends on a caller nobody has written is not delivered. The mechanical
form of the check is `tools/reachability-check.py`, which fails a tool
under `tools/` that nothing calls — it does not scan `agent/`, which is
where seat hands live, and widening it there would have named this
automatically.
