# Briefs quote operator paths verbatim, and nothing catches it

**What.** Twice in two days (task 0041 via PR #73, task 0045 via PR
#78), an implementing agent quoted a review excerpt verbatim into its
brief — correctly, per the evidence-citing culture — and the excerpt
carried the absolute path of the run's worktree, which includes the
operator's home directory. Both leaks were caught by review after the
fact (the second by the Codex pass, the first not until a manual sweep
a day after merging); both were scrubbed to a `<worktree>/`
placeholder. The username was already inferable from public commit
metadata, so the exposure was small — but the repo's own standard
(Principle 02's test: no person-identifying string anywhere) is the
standard, and two occurrences in two days is a rate, not an accident.

**Why it recurs.** Review tools cite findings as `absolute-path:line`,
briefs are told to quote review findings verbatim, and the two rules
compose into a leak. No agent is being careless; the pipeline's
defaults produce this and only vigilance removes it — the exact
posture this project keeps finding insufficient.

**Fix direction.** A CI guard, not more instructions: the check
workflow greps the tree (docs/ at minimum, plausibly everything) for
`/home/` and fails loudly on a match, so the leak becomes a red run at
PR time instead of a review catch. One deliberate exception mechanism
for any legitimate literal (none known today). Optionally, the
brief-writing guidance says to relativize quoted paths — but the grep
is the load-bearing half; prompts drift.

**Open questions.** Does the guard belong in this repo's CI alone, or
also in emcee (which could relativize paths in the excerpts it hands
to agents — fixing the composition at its source)? And should the
`whharris/castle-turing-private` references in
`docs/tasks/done/0002-private-layer-slot.md` — deliberate at the time,
predating Principle 02 — be generalized the same way, or left as
historical record? That one is the resident's call and is explicitly
not decided here.
