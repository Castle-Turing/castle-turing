# Task 0077 — cross-review the 18 unreviewed merged PRs

## Why

The first org-wide conformance sweep (PR #124's charge; receipt PR
#133) found 18 code-touching pull requests in this repository that
merged with no review round at all. Retroactive conformance is the
point: a convention applies to the work that predates it. The sweep's
first belated review, on PR #132, caught a one-line kernel-parameter
fix that was a silent no-op — each PR below is a diff that reached
`main` with no such second look. The source entry is
`docs/backlog/merged-code-prs-were-never-cross-reviewed.md`; it is
promoted here and must be deleted in the same commit that lands this
brief.

The 18, by number: 2, 3, 7, 9, 15, 19, 22, 27, 37, 38, 45, 46, 47,
50, 86, 106, 107, 129. Titles and merge dates are in the backlog
entry; trust `gh` over the list if they disagree, and say so.

## The recipe, per PR

1. **Skip check first** (this is what makes an interrupted run cheap
   to resume): if the PR already carries a comment containing
   `chevaline-gate: cross-vendor-review`, record it as already
   receipted and move on.
2. Reconstruct the merged diff: `gh pr view N --json mergeCommit`
   gives the SHA; the diff is `<sha>^` to `<sha>` (first parent —
   run `git fetch origin main` once so every merge commit is local).
3. Run the review locally, without posting:

       /home/wesley/projects/chevaline-whharris/scripts/cross-vendor-review.py \
         --repo <your worktree> --base <sha>^ --head <sha> \
         --reviewer opencode --model opencode/kimi-k3 \
         --timeout 900 --out <your worktree>/.review-sweep/review-N.json

   Keep `--out` inside your own worktree (writes outside it are
   vetoed) and never commit `.review-sweep/`. Provider policy, from
   the backlog entry: OpenCode Zen, because the Deep Infra route
   timed out on exactly this workload; never the Codex CLI across a
   set this size (metered). The 900 s cap bounds the sweep's worst
   case; if a review times out or comes back empty, retry once, then
   fall back to `opencode/qwen3.6-plus` (still cross-vendor); if that
   also fails, record the PR as un-reviewed in the receipts — never
   silently.
4. **Post the review with a retro marker, not the live gate marker.**
   The `--out` JSON names the `review_file`; edit only its marker line
   from `<!-- chevaline-gate: cross-vendor-review -->` to
   `<!-- chevaline-gate: cross-vendor-review retro-sweep -->`, then
   `gh pr comment N --body-file <file>`. The reviewer's prose stays
   verbatim — the verbatim rule is about prose, and the marker is not
   prose. Why: the exact live marker triggers
   `.github/workflows/handle-review-findings.yml`, which would fire
   eighteen times against closed PRs whose branches are deleted — a
   red run each, and a second dispositioner racing this task, whose
   own job the dispositions are. The retro spelling keeps a
   machine-greppable review-round signal for the future sweep
   detector while staying outside the workflow's `contains()` match.
5. Disposition every finding in a **separate comment underneath** the
   review (the standing convention: no seat edits or filters an
   independent reviewer). For each finding: still live against
   current `origin/main` → a new backlog entry, filed per
   `docs/backlog/README` (one plain-text file named as the problem;
   include the incident-detector section where the finding class
   warrants it) and named in the disposition; fixed since → where;
   stale or wrong → why. An empty review is itself the receipt.

Reviews run one at a time, and each PR's receipt is posted as soon as
its review completes, so partial progress survives.

## What this task commits

On its branch: this brief, with a receipts table appended (per PR:
review model, P1/P2/P3 counts, disposition summary — filed / fixed
since / stale / clean / un-reviewed-because); the backlog entry's
deletion; any new backlog entries the dispositions require; and the
task-outcome row per `docs/measurement.md`, so `outcomes-check` is
green. The comments on the 18 PRs live on the forge; the table here is
the in-repo record the forge-independence convention requires.

## Verification

Self-verifying by receipts, no human step in the sweep itself: every
one of the 18 PRs ends with either a posted review comment (finding or
"no issues") or an explicit un-reviewed-because row — the table and
the forge must agree, and the count must be 18. New backlog entries
are read by the resident through the normal pipeline afterwards.

## Implementation prompt

Read this brief in full, then
`docs/backlog/merged-code-prs-were-never-cross-reviewed.md`. Commit
this brief at
`docs/tasks/0077-cross-review-the-unreviewed-merged-prs.md` on your
branch, updating it in the same PR if the plan shifts, and delete the
backlog entry in that same commit. Work the 18 PRs per the recipe,
file what the dispositions require, append the receipts table, and
report any judgment call you had to make where these instructions
were ambiguous — the still-live calls especially.
