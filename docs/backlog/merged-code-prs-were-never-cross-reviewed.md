# Merged code PRs were never cross-reviewed

**What.** The first org-wide conformance sweep — the merged-without-review
receipt named in `the-corpus-is-never-swept-against-the-conventions`
(PR #124) — found 18 code-touching pull requests in this repository
that merged with no review round at all: no `/code-review`, no
cross-vendor (Codex/OpenCode) review, no formal GitHub review, through
inattention or through predating the convention rather than by
decision. Documentation-only PRs are excluded, because skipping their
review is itself a standing convention, not this debt. The instances,
by number, merge date, and title:

- #2 (2026-08-14) Add Claude Code GitHub Workflow
- #3 (2026-08-14) Auto-handle Codex PR reviews with Claude
- #7 (2026-08-15) Codex handler: reply on finding threads and resolve them
- #9 (2026-08-15) ci: allow claude[bot] to trigger PR review workflow
- #15 (2026-08-15) Task 0005: the dogfooding desktop
- #19 (2026-08-16) installer: nmtui needs timeout --foreground or it ignores the keyboard
- #22 (2026-08-16) Tasks 0008 + 0009: the agent layer, and an ambient way in
- #27 (2026-08-16) CI: skip model review on documentation-only PRs
- #37 (2026-08-17) Task 0013: two bugs the first real deploy found
- #38 (2026-08-17) Task 0012: the installer console must have an escape hatch
- #45 (2026-08-18) Task 0017: legible text by default
- #46 (2026-08-18) Task 0018: don't run the build gate on documentation-only changes
- #47 (2026-08-18) Task 0019: two defaults the managed Sway config got wrong
- #50 (2026-08-18) Task 0022: answer a Castle question without knowing its name
- #86 (2026-09-05) Task 0051: the notification waiter leaves the dispatch unit's cgroup
- #106 (2026-09-08) Task 0066: the rollback re-execs before it rolls back
- #107 (2026-09-08) Task 0067: an approved switch is classified by what it would churn
- #129 (2026-09-16) Task 0073: the oomd swap rule, and a liveness check

**Why it matters.** Retroactive conformance is the whole point of
PR #124: a convention is applied to the work that predates it, not
only to work that comes after. Unreviewed merged code is code no
second reader ever examined, and a cross-model reviewer earns its keep
precisely on work its own model family wrote — the same sweep's first
belated review, on PR #132, caught a one-line kernel-parameter fix
that was a silent no-op (it compared against the wrong latency field).
Each entry above is a diff that reached `main` with no such second
look.

**How to review them, cheaply.** Run
`chevaline/scripts/cross-vendor-review.py --reviewer opencode` against
each PR's merged diff — reconstruct it with `--base <mergeCommit>^
--head <mergeCommit>` (get the SHA from `gh pr view N --json
mergeCommit`) — and post the review verbatim as a comment on the
(closed) PR. Provider policy: exhaust the Deep Infra budget first if
at all, then OpenCode Zen — Deep Infra proved too slow for this (a
Kimi-K3 spike timed out at 900s on a 700-line diff). Never the Codex
CLI across a set this size; it is the metered path. A finding still
live against current `main` becomes its own backlog entry → brief →
fix, per the normal pipeline; an empty review is a receipt on the PR.

**How this would have been caught sooner.** The enumeration is a
scheduled sweep, not a one-off: an org-wide `gh`-driven pass that
flags any merged code PR carrying no review-round signal, whose empty
result is a receipt ("swept N, all reviewed") rather than silence, per
the rule that a quiet day and a broken detector must not look alike.
That detector is PR #124's charge; this entry is one of its first
instances, and the review gate on every code PR keeps the set from
regrowing.

**Scope.** A hygiene-sprint unit, prioritized with everything else.
Work the 18 reviews, file the findings, and record cost and yield in
the task-outcome baseline like any other work.
