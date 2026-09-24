Title: Task 0077 — cross-review the 18 unreviewed merged PRs
Model: deep
Milestone: none — hygiene
Model-because: the deliverable is 18 disposition judgments, each
weighed against this repo's own conventions (`docs/backlog/README`,
the incident-detector rule, the verbatim-findings rule) rather than
against a spec an implementer can check mechanically — a standard
implementer would file a backlog entry for a finding that's already
stale, or clear one that's still live, and nothing catches that until
the resident reads it. The marker substitution in step 4 is the other
half: posting the live marker instead of the retro one fires
`handle-review-findings.yml` eighteen times against closed PRs with
deleted branches, a failure mode invisible until the runs go red. A
cheap-tier implementer would follow the recipe's mechanics correctly
and still get the judgment calls wrong, which is the failure this
tier exists to catch.

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

       <your chevaline checkout>/scripts/cross-vendor-review.py \
         --repo <your worktree> --base <sha>^ --head <sha> \
         --reviewer opencode --model opencode/kimi-k3 \
         --timeout 900 --out <your worktree>/.review-sweep/review-N.json

   The script lives in the resident's private Chevaline profile, not
   in this repo (`docs/backlog/the-review-gate-fails-silently.md`);
   locate your own checkout rather than assuming a path, since this
   brief runs on whatever machine picks it up.

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

Read this brief in full — it is self-contained; the backlog entry
that seeded it, `docs/backlog/merged-code-prs-were-never-cross-reviewed.md`,
was promoted into this file and deleted in commit `d0e23c9`, so it no
longer exists in the working tree. Its titles and merge dates, if
ever needed, are `git show d0e23c9^:docs/backlog/merged-code-prs-were-never-cross-reviewed.md`
— though `gh` is trusted over that list per the Why section above.
Update this brief in the same PR if the plan shifts. Work the 18 PRs
per the recipe, file what the dispositions require, append the
receipts table, and report any judgment call you had to make where
these instructions were ambiguous — the still-live calls especially.
