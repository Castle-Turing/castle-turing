# Task 0050 — scrub operator paths from merged briefs

**Motivation.** The 0041 brief (merged in PR #73) quotes a review
excerpt verbatim, and the excerpt cites its finding by the absolute
path of the run's worktree — an operator home path in the public tree,
against Principle 02's no-person-identifying-strings test. Found
2026-09-03 during the sweep triggered by the identical leak in PR #78
(task 0045, caught there by the Codex review and scrubbed on that
branch).

**What was done.** The absolute worktree prefix in
`docs/tasks/done/0041-ci-transient-retries.md` is replaced with the
`<worktree>/` placeholder, preserving the file:line half of the
citation. Per Principle 02's remediation clause, history is rewritten
only on unmerged branches — this leak merged a day ago, so the fix is
tip-only and the history is accepted as the cost of catching it late.

**The recurrence guard** is deliberately not built here — it needs a
decision about where it lives (this repo's CI, emcee, or both), filed
as `docs/backlog/briefs-quote-operator-paths-verbatim.md` in this same
commit.

**Note on numbering and placement.** This brief lands directly in
`done/` because the work is implemented in the same commit — there is
no open task for a harness to pick up, and a file at the top level of
`docs/tasks/` is now, by convention, queued work.

**Verification.** `grep -rn "/home/wesley" docs/` returns only the
pre-existing, deliberate references in
`docs/tasks/done/0002-private-layer-slot.md` (whharris repo names,
flagged in the backlog entry as the resident's call), and nothing
else.
