# The status surface still speaks the journal's internal vocabulary

**What.** `castle-modal --mode status` (and, to a lesser extent, `castle
digest`) prints bracketed record ids (`[20260816T130000Z-request-4e13ec]`),
the bare word `provenance` in the errand-provenance field, and the
router's own decision prose — `decided -> notify: <evidence text>` —
which itself embeds record ids in its `evidence` sentence
(`docs/architecture.md`'s Router seat, `agent/castle`'s `route_journal`).
`castle digest` renders the same shapes for the same reason: it folds
the identical journal records. None of this is disguised or abbreviated;
it is the journal's own schema, read cold, exactly as designed for an
auditor.

**Why it matters.** The status surface's entire premise is "come back
and check in later" — a resident who was never asked to learn `seat`,
`provenance`, `refs`, or what a `decision -> channel: evidence` line
means opens it expecting plain language and meets journal internals
instead. That is a smaller version of the problem
`docs/tasks/0022-answer-in-ui.md` solved for *answering*: a resident
should not need the journal's vocabulary to participate in the system.
Status is the read half of the same promise, still unmet.

**What we already know.** `docs/tasks/0022-answer-in-ui.md` (which
added the answer-mode chord Mod4+Shift+a to `castle-modal`) deliberately
did not clean this up, for two reasons stated in that brief. First, the
status labels were rebuilt across four review passes during
`docs/tasks/0021-auto-dispatch.md`, and the retry hints in particular
(`"failed — castle work <id> to retry"`) are pinned by roughly twenty
exact-match assertions in `test/agent-loop/modal-headless-test.sh` — the
record id in a retry hint is deliberate, `docs/tasks/0015`-grounded
design (a resident needs the exact id to type the retry command), not an
oversight to be cleaned up incidentally. Second, discovery no longer
needs to pass through status at all: dispatch (0021) starts eligible
errands automatically, and the notification (0022) now names the answer
chord directly, so the acceptance path — noticing a pending question and
answering it — never requires reading a bracketed id off the status
screen. What remains on status is a genuine, if now secondary, leak.

The escape valve already in place: ids are greppable straight out of the
plain-text journal, and `castle show <id>` prints any record verbatim.
Nothing is hidden from a resident willing to read the journal directly —
the gap is only that the "quick check-in" surface still requires it.

**Open questions.** Whether ids belong on status at all, or only in the
retry-hint case where they are load-bearing (the resident must type
exactly that string into `castle work`); whether `provenance` and
`decided -> channel: evidence` can be rephrased in plain language without
losing the auditability that makes the router's reasoning legible;
whether such a rewrite belongs in `_errand_state`/`run_status` directly
or as a distinct rendering layer, given how tightly the existing
assertions pin today's exact strings; and whether `castle digest`, a
different-audience surface (a period's account, not a live check-in),
should be rewritten the same way or left as the more technical of the
two views.
