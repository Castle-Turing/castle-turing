# Is the diff-producing worker contract the general shape, or one worker among several?

**What.** `cmd_work`'s contract sits at the errand boundary: a
`request` record in; a `result` record, a diff against the relevant
repo, and journal entries out (`docs/architecture.md`'s Worker
section). Task 0021 makes that specific contract start itself
automatically. Whether it is the *only* shape a Castle Turing worker
should ever have is a separate question 0021 deliberately does not
answer.

**Why it matters.** Many tasks a resident would plausibly fire off are
not diffs — a question answered from the web, a file organized, a
calendar checked, a piece of research summarized. If the diff contract
is treated as the general worker shape by default, either those tasks
get awkwardly forced through a "propose a diff" frame that doesn't fit
them, or the system quietly stays diff-only and the vision's broader
"fire off lots of tasks" pattern (`docs/vision.md`'s core inversion)
never extends past repo work.

**What we already know.** `docs/backlog/fire-and-forget-lives-in-the-
harness.md` — the entry this question was originally filed under — is
now closed by `docs/tasks/0021-auto-dispatch.md`, which built the
dispatch mechanism (a systemd path unit plus timer, a `castle dispatch`
sweep, per-request leases, a durable `claim` record, and a closed
`outcome` vocabulary on results) for exactly one worker contract: the
one `agent/castle-worker-claude` and `cmd_work` already implement.
Nothing about the dispatch mechanism itself assumes the tenant produces
a diff — the sweep's contract with a worker is "invoke it, wait for a
result, read its `outcome`" — but the worker *contract itself*
(`$CASTLE_DIFF_FILE`, stdin/stdout shape, "propose, never deploy") is
diff-shaped throughout, and every seat downstream (the router, the
status surfaces, the digest) currently only ever renders that shape.

**Open questions.** Does a second worker contract get a second record
type, or does `result` grow a field distinguishing what kind of output
it carries? Does "propose, never deploy" (Proposal 03's hard line for
the diff worker) even make sense for a non-repo task, or does that task
class need its own authority boundary? Is there one worker seat with
multiple tenants keyed by task shape, or multiple seats? How would
`castle dispatch`'s eligibility fold (docs/tasks/0021) decide which
contract a given `request` wants, if more than one exists — a field on
the request, or an inference step, and if inference, who's allowed to
make it per Proposal 05? Answering this well probably wants a few real
non-diff errands tried by hand first, the same way 0008's single cursor
fix grounded the original record schema before it was generalized.
