# A model declaring a task infeasible should trigger escalation, not settle it

**What.** When a delegated implementer reports that a task is
technically infeasible, treat that report as a mandatory trigger to
re-run the same task on a stronger model — logged as such — rather
than as a verdict that closes the task. Applies wherever this project
already delegates to a sized-down model: `CLAUDE.md`'s Delegation
section here, and the analogous Architect/Implementer/Mechanical split
in the tools built to run Castle Turing's own sprints.

**Why it matters.** `CLAUDE.md` already treats an implementation
report as a claim rather than evidence — "whoever delegated re-reads
the diff and re-runs the check." An infeasibility report is a sharper
version of the same problem, and currently gets *less* scrutiny than a
normal report, not more: a wrong implementation leaves a diff or a
test run to check it against; a claim of infeasibility leaves nothing
to check at all. There is no artifact to re-run, so it is, if
anything, the single least verifiable thing a delegated model can
report, and today nothing distinguishes it from any other outcome.

**What we already know.** One observed case, outside this repo: a
smaller model spent a long session on a task, declared it technically
infeasible, and a stronger model solved the same task directly
afterward, from the same starting point. A single data point, not a
study — but it's the exact failure this entry proposes closing, and
the proposed fix costs nothing to try: a policy addition to an
existing convention, not new infrastructure. It composes with a
cheap, ongoing measurement for free — if escalation is logged every
time it fires, the log itself becomes the evidence for whether this is
worth keeping, without anyone having to run a dedicated study to find
out.

**Open questions.** Whether this should be an unconditional rule or
scoped to certain kinds of task (an infeasibility claim in an
unfamiliar or sparse-training-data domain seems like a likelier false
negative than one in a well-trodden domain, though that's a guess, not
a finding). How many escalations are owed before an infeasibility
claim is actually accepted — an unbounded escalation ladder isn't
right either, since a stronger model can still be correct that
something can't be done. Whether the rule belongs in this repo's
`CLAUDE.md`, in a sibling tool's own conventions, or both, given both
already have their own version of "a report is a claim, not
evidence."
