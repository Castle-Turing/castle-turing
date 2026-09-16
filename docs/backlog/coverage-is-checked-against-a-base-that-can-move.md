# The outcome log's coverage is checked against a base that can move after CI last ran

**What.** On 2026-09-16 `main` went red on `outcomes-check` within
minutes of task 0070 landing. Task 0073 merged first (PR #129,
`e4cdcfc`), task 0070 second (PR #120, `3b8d14d`). The coverage rule
that 0070 introduced — every brief under `docs/tasks/` has a row in
`docs/log/task-outcomes.tsv` — was satisfied on PR #120's own merge
result at the time its checks last ran, because `0073`'s brief was not
yet on the trunk. Nothing re-ran those checks when the base moved, so
#120 merged green onto a trunk its log no longer covered, and the
push-to-`main` trigger failed immediately afterwards.

**Why it matters.** This is structural, not a one-off. The coverage
check is a predicate over the *union* of two things a pull request does
not control together: the briefs on the trunk, and the log on the
branch. Any task that merges between a log-touching pull request's last
check run and its merge leaves `main` red, and the pull request that
caused it is already closed. The window is widest exactly when the
project is moving fastest — parallel sprint branches, which is the
normal mode here.

The failure is benign in its current form: the row was reconstructible
from git, every cell derived by `tools/outcomes/outcomes derive`, and
no write-once cell was at risk. What makes it worth recording is that
the repair happens *after* the causing pull request is gone, which is
the condition the log's own design argues against — 0070's brief puts
the coverage check at the cheap moment "while the facts are still in
someone's head". A backfilled row reconstructed days later by whoever
notices the red trunk is the expensive moment, and it is the one this
window produces.

**How it would have been caught sooner.** It was caught, and quickly,
which is worth stating plainly: `outcomes-check` carries a
`push: branches: [main]` trigger alongside its `pull_request` one, so
the red trunk was visible rather than silent. That trigger is the
detector and it worked. What is missing is not detection but
prevention — the check passing at merge time rather than being
contradicted by it. GitHub's own mechanism for this is a merge queue,
or the weaker "require branches to be up to date before merging"
setting, neither of which is enabled on this repository.

**Fix directions, none chosen.**

- Enable "require branches to be up to date before merging" for the
  `outcomes-check` context. Cheapest, and costs a rebase on every
  log-touching pull request whenever anything else lands first.
- Enable a merge queue, which re-runs checks against the real merge
  result. Correct, and heavier than a one-resident project may want.
- Make coverage self-healing: have the handler that already runs on
  review findings append missing rows by `derive` on a push to `main`
  that fails coverage. Removes the human from the loop at the cost of a
  bot writing rows into a write-once file, which wants its own argument
  before anyone builds it.
- Accept the window and treat a red trunk as the signal to run
  `derive --fill`, which is what happened here and took one command.
