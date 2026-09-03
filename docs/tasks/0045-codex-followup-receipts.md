# Task 0045 — the codex followup proves its receipts

On PR #73 (2026-09-02), `claude-codex-followup.yml`'s prompt told the
session to reproduce two workflow fixes it could not push "in the
PR-level summary comment" for a human to apply. That comment does not
exist. Nothing errored and nothing warned; the promised artifact simply
never landed, and the absence was noticed only because a human went
looking for the diff to apply it
(`docs/backlog/the-codex-followup-promised-a-receipt-it-never-posted.md`,
promoted and deleted by this commit). The failure is the same shape
`tools/codex-review.sh`'s own header was written against
([[cross-model-review-is-paywalled]]): "nothing failed, it just stopped
happening." A report that describes work as done is not evidence the
work happened, and the followup automation is a sub-agent whose
delegator is a YAML file that verified nothing.

This task does not touch the sibling problem the same PR exposed —
whether the followup's GitHub App should ever hold `workflows`
permission — which stays open in
[[the-codex-followup-cannot-push-workflow-fixes]]. That entry's own
push wall does not bind *this* task, though: these changes are pushed
by the coding harness under the operator's own credentials, not the
App's token, so `.github/workflows/claude-codex-followup.yml` could be
edited directly. No new permission was granted to the App itself —
this task changes what the workflow verifies about a run already using
the permissions it has, not what it's allowed to do.

## Fix: two complementary pieces

The backlog entry named two pieces and ranked them; this brief repeats
that ranking because the two are not equally load-bearing.

**1. Prompt ordering (the minor piece).** `claude-codex-followup.yml`'s
prompt now tells the session to POST each reply before citing it, to
resolve a thread only after its own reply has actually posted, and —
on a failed post — to say "I could not post `<X>`" rather than
describe `<X>` as if it existed. This is the fix a careful model
follows correctly most of the time; it is also exactly the layer that
failed silently on PR #73, because prompts drift and models have off
days.

**2. Two verification steps outside the model's control (the
load-bearing piece).** A new "Wrap gh to catch silent posting
failures" step runs immediately after checkout, before the Claude
action. It resolves the real `gh` binary, writes a shim of the same
name to a scratch directory, and prepends that directory to `PATH` via
`$GITHUB_PATH` — so every `gh` invocation for the rest of the job,
including all of the model's own tool calls, runs through the shim
first. The shim always calls through to the real `gh` and passes its
exit code back unchanged, but if that exit code is nonzero, it appends
the failing command and its arguments to a log file in `$RUNNER_TEMP`.
A "Fail loudly if any gh call failed this run" step, `if: always()`,
checks that log after the Claude action step completes (success or
failure) and fails the job — with `::error::` and the log's contents —
if it is non-empty. The model never sees the shim, cannot disable it
short of reading and defeating it deliberately, and its own narration
in a final summary comment has no bearing on whether the job goes red.

That call-failure shim was the only mechanism through the first
`/code-review` pass, and it has a real gap: it only proves something
about calls that were *attempted*. `tools/codex-review.sh`'s
cross-model pass caught this directly — see the disposition in
Verification below — and it is exactly the shape PR #73 actually hit:
"nothing errored, nothing warned," which reads far more like a `gh`
call that was simply never made than one that was made and failed.
A second step, "Confirm the review's receipts actually landed," now
runs after the failure-log check and queries the forge itself: every
inline comment on the triggering review must have at least one reply
(`in_reply_to_id` pointing at it, via `gh api
.../pulls/N/comments`), and the PR's top-level comment count
(`gh api .../issues/N --jq .comments`, snapshotted before the Claude
step runs and compared after) must have increased by at least one —
proving the step-4 summary comment specifically, the exact artifact
missing on PR #73. This is the entry's own "if the run's replies can
be checked against the forge for referenced artifacts cheaply, do
that too" — the two `gh api` calls plus a `jq` diff per check qualify
as cheap; it does not attempt to check that a reply's *content*
matches what the model claims, only that a reply and a new summary
comment *exist*, which is what "receipt" means here.

## Why every failing `gh` call, not just "posting" calls

The entry's language is "any `gh` posting call... exited nonzero."
Distinguishing a posting call from a read at the shim layer is more
fragile than it looks: `gh api graphql -f query=...` (used for the
`resolveReviewThread` mutation) issues a POST by default whenever `-f`
or `-F` data flags are present, without an explicit `-X POST` to match
on, while a plain string match on `comment`/`reply` would also catch
the prompt's own step-1 *read* calls
(`.../reviews/ID/comments`). Rather than build and maintain that
classifier, the shim logs **every** failing `gh` call regardless of
verb. This is a strict superset of "posting calls that failed," so it
cannot miss the failure mode the entry cares about; the cost is that a
failed *read* (step 1, rare — a transient GitHub API hiccup) also
fails the job loudly, which is the same bias this whole task is built
on: a false loud failure costs a human a glance at a red run, a false
silent success costs nobody noticing at all. Recorded here because a
future editor tightening this to "only posting calls" would be
narrowing the check, not just refactoring it.

## Non-goals

- Does not decide whether the App should hold `workflows` permission —
  that question stays open in
  [[the-codex-followup-cannot-push-workflow-fixes]], unchanged by this
  task.
- Does not verify that a posted artifact's *content* matches what the
  model's summary claims — only that a reply and a new summary comment
  *exist*, and that the `gh` calls that created them exited zero.
  Checking content would mean parsing the model's free-text summary
  for claimed specifics and cross-checking each against the GitHub
  API, which is real complexity for a narrower gain: the model would
  have to fabricate a claim while the underlying post still succeeded,
  a different failure mode than the one this task was built against
  (a post that never happened, or one that failed outright). If that
  narrower failure mode is ever observed, it is worth a new backlog
  entry naming it specifically, rather than building the general
  mechanism speculatively now.
- Does not verify that a resolved thread (the GraphQL
  `resolveReviewThread` mutation) actually succeeded, only that its
  reply exists — an unresolved-but-replied thread is still visible to
  a human on the PR, unlike a missing reply, so this was judged a
  smaller gap than the two checks that are built.
- Does not change loop prevention, concurrency, trigger conditions, or
  any other part of `claude-codex-followup.yml`'s existing behavior.

## Judgment calls

1. **Log every failing `gh` call, not a pattern-matched subset of
   "posting" ones.** Reasoning above. A reviewer who wanted the
   narrower check should know it was considered and rejected, not
   just absent.
2. **The shim is a heredoc written by an earlier `run:` step, not a
   committed script file.** `test/ci/*.sh` is the repo's normal home
   for shared shell logic, but this shim is single-use, generated
   fresh per run (it needs the real `gh` path resolved at run time,
   before it shadows itself), and only exists to sit in front of one
   command for one job. A committed script would need the same
   run-time `command -v gh` resolution and PATH-prepend wiring around
   it anyway, so it gains nothing over the inline heredoc for this
   size of logic. If a second workflow ever needs the same shim, that
   is the point to factor it out — `test/ci/retry-on-known-transient.sh`
   went through exactly that promotion in task 0041, after a review
   caught the duplication, not before.
3. **The heredoc bakes `$real_gh` and `$log` (the shim-creation-time
   values) into the generated script literally, while `\$@`, `\$?`,
   and `\$*` are escaped so they evaluate at the shim's own run
   time.** This is the one subtlety in the diff a future editor could
   break silently: unescaping any of those three turns the shim into
   one that always reports the *shim-creation* invocation's argv
   instead of whatever command actually ran. Verified locally (see
   below) rather than assumed.
4. **Sibling entry's citation was reworded, not just relinked.** It
   used to call the receipt-trust problem "its own open problem"; that
   is no longer accurate once this task lands a fix, so the sentence
   now points at this brief as where the mechanism lives instead of
   describing it as unaddressed.
5. **Whether `claude-code-action`'s own subprocess actually resolves
   `gh` through the runner's updated `PATH`, rather than an
   absolute path fixed at the action's own install time, was not
   fully verified — it could not be, without observing a real run.**
   `/code-review`'s verification pass fetched the published `action.yml`
   for `anthropics/claude-code-action@v1` and confirmed it is a
   **composite action** (`bun run .../src/entrypoints/run.ts`), not a
   Docker action — it runs in-job on the same runner process tree the
   "Wrap gh" step already modified, so it inherits `$GITHUB_PATH`'s
   prepend the same way any later step would. That raises confidence
   in this design considerably, but does not fully close the question:
   nothing rules out the CLI or its `bun` runtime caching a resolved
   `gh` path once per process rather than re-resolving `PATH` on every
   invocation, and that wasn't (and couldn't cheaply be) inspected.
   If it resolves `gh` by an absolute or cached path instead, the shim
   is silently never on the path the model's calls run through, and
   the failure log stays empty even on a real posting failure — a
   false negative. This is the one remaining risk in this design and
   is called out explicitly in Verification below as the thing this
   task's own PR needs to prove.
6. **`/code-review` caught a real wording regression in the prompt
   edit, fixed in this branch's second workflow commit.** The first
   draft of step 3 replaced "Then resolve each addressed thread via
   the GraphQL resolveReviewThread mutation" (an unconditional command
   to resolve every addressed thread) with "Resolve a thread ... only
   after its own reply has posted; never resolve a thread you have not
   replied to" — a precondition and a prohibition, but no longer a
   command to resolve every thread it addressed. A model could satisfy
   that wording by replying to every thread and resolving none of
   them. Fixed by keeping "resolve each addressed thread" as the
   command and adding the ordering constraint alongside it, rather
   than in place of it.
7. **`tools/codex-review.sh` caught that the failure-log shim alone
   cannot detect a `gh` call that was never made — only one that was
   made and failed — which is the PR #73 shape specifically.** Fixed
   by adding "Confirm the review's receipts actually landed" (see
   piece 2 above), a genuine forge-side existence check, rather than
   trying to stretch the exit-code shim to cover a case it structurally
   cannot see (a call that never happens produces no exit code to log).
8. **The new forge-side check needs its own GitHub API credential.**
   `gh` calls made from inside the Claude action authenticate somehow
   internal to that action (its own `github_token` handling — not
   inspected, and not this task's concern, since those calls already
   work today); a plain `run:` step has no such thing implicitly and
   needs `env: GH_TOKEN: ${{ github.token }}` set explicitly, which is
   GitHub's own documented pattern for using `gh` in a workflow step.
   Added to both the snapshot half (in "Wrap gh") and the check itself,
   scoped to those two steps only — not job-wide — so as not to change
   anything about how the Claude action step authenticates its own
   `gh` calls, which already work and were out of scope to touch.
9. **The before/after comment-count snapshot lives in `$RUNNER_TEMP`,
   written by "Wrap gh" and read by "Confirm the review's receipts
   actually landed."** Two other options considered: a `GITHUB_OUTPUT`
   step output (more idiomatic for passing a value between steps, but
   this value only needs to survive to one specific later step in the
   same job, and $RUNNER_TEMP is already the pattern this task uses
   for the failure log) and re-deriving "before" from the review's own
   `submitted_at` timestamp instead of snapshotting a count (rejected:
   comparing counts sidesteps any ambiguity about which comments were
   created before vs. after a given instant, and needs no timestamp
   parsing).
10. **A second `/code-review` pass, run after the forge-check commit,
    found a real redundancy and fixed it, and raised one already-known
    risk plus a narrow race worth naming explicitly.** "Confirm the
    review's receipts actually landed" originally made two paginated
    `gh api` calls — one scoped to the triggering review's own
    comments, one for the whole PR's comments — to check for replies.
    A finder confirmed live against PR #73 that every comment on a PR
    already carries both `pull_request_review_id` and
    `in_reply_to_id`, so the review-scoped call was pure duplication of
    data the whole-PR call already returns, and a per-finding loop
    spawning one `jq` process each was replaced with a single `jq`
    pass over the one fetch (`$review_ids - $replied`, a set
    difference). Fixed in this branch. A second finder flagged the
    before/after comment-count check as racy: an unrelated top-level
    comment landing on the PR from a human or another bot during the
    job's run window would make `after > before` true even if Claude's
    own summary comment never posted, a false pass. This was judged an
    accepted, narrow limitation rather than something to harden further
    — it requires a coincidental unrelated comment on this specific
    PR in this specific few-minute window, on top of the summary
    comment already having silently failed to post, and closing it
    properly (matching by author identity or timestamp against the
    review's `submitted_at`) adds real complexity for an edge case
    layered on an edge case. Recorded here rather than silently
    dropped, per this task's own "no silent caps" standard.
11. **A third review pass claimed the "Wrap gh" step's heredoc
    terminator was space-indented and therefore never recognized by
    bash, silently swallowing the rest of the step (the `chmod`, the
    `$GITHUB_PATH` append, and the comment-count snapshot) into the
    heredoc body — a claim serious enough to re-verify from scratch
    rather than take on trust.** It does not hold up: GitHub Actions'
    `run: |` is a YAML literal block scalar, and YAML strips the
    block's *common* leading indentation from every line before bash
    ever sees the text — confirmed authoritatively this time by
    parsing the actual committed file with `PyYAML` (`nix-shell -p
    python3 python3Packages.pyyaml`) rather than reasoning about it,
    printing the exact string bash receives, and running that exact
    string with `bash -n` and live execution against a mocked `gh`:
    the heredoc terminates correctly, the shim file is written and
    made executable, `$GITHUB_PATH` is appended, and the snapshot file
    is populated. The claim is consistent with what a reviewer would
    see by copying the *file's own indented lines* directly into a
    test script without first stripping that common indentation —
    every line in the "Wrap gh" step's body shares the same base
    indentation (10 spaces, matching the step's `run: |` nesting), so
    a test that skips the dedent would reproduce exactly the false
    positive reported. No change made; recorded here because a false
    "critical, confirmed" finding is exactly the kind of thing that
    should stay legible rather than be silently dropped, per this
    project's own "every disagreement between reviewers must stay
    legible to the human" standard (echoing the prompt text this same
    task added to `claude-codex-followup.yml`).

## Verification

Workflow YAML cannot be fully proven locally — this development
machine has no `nix`, and no `actionlint` or `pyyaml` were available
in this environment either (same gap task 0041's brief recorded).

What was done locally:

- Careful manual review of the diff for YAML structure, matching this
  file's existing step indentation (6/8/10-space nesting, consistent
  with every other `run: |` block in `check.yml`).
- The two new `run:` blocks' content was extracted exactly as YAML's
  block-literal scalar would present it to `bash` (stripping the
  block's common 10-space indentation, preserving the `if`-body's
  extra 2 spaces) and checked with `bash -n` — no syntax errors.
- The "Wrap gh" step's script was then actually run, against a fake
  `gh` on `PATH` and `$RUNNER_TEMP`/`$GITHUB_PATH` set the way GitHub
  Actions sets them, confirming end to end: a successful call passes
  through with its real output and exit code, unlogged; a failing call
  (`gh api .../replies -f body=fail`, mocked to exit 7) still returns
  its own real exit code to the caller *and* appends `FAILED (exit 7):
  gh api .../replies -f body=fail` to the log, with the full argument
  list intact.
- The "Fail loudly" step was run against both states of that log: with
  the failure entry present, it printed the `::error::` line, the
  logged line, and exited 1; with the log emptied, it printed "Every
  gh call in this run exited zero." and exited 0.
- `grep` across the repo confirmed the deleted backlog file had exactly
  one citation (the sibling entry, updated above) and nothing else
  referenced its path.
- `/code-review` (scoped against `origin/main`), three finder angles:
  reuse/simplification/efficiency found nothing; altitude/conventions
  confirmed this is genuinely new ground (no comparable mechanism
  elsewhere in the repo to reuse) and flagged the same PATH-resolution
  risk as judgment call 5; correctness confirmed the heredoc's
  YAML-dedent and `\$`-escaping are both right, fetched
  `claude-code-action`'s `action.yml` to strengthen judgment call 5
  (folded in above), and caught the real prompt-wording regression
  described in judgment call 6, fixed in this branch. The remaining
  candidate — the blanket-`gh`-failure shim can flag an unrelated
  transient read failure as if a receipt failed to post — is the
  tradeoff already reasoned through and accepted under "Why every
  failing `gh` call, not just 'posting' calls," above; no further
  change made.
- `tools/codex-review.sh` (cross-model pass, also scoped against
  `origin/main`), run after the `/code-review` fixes above, one P1
  finding, reproduced here verbatim per this repo's convention (raw
  output saved at `/tmp/codex-review-output.XnKYEn` at review time; no
  PR exists yet for this branch to comment on, since the harness opens
  it, so this disposition stands in for the usual separate PR
  comment):

  > The verification mechanism misses the motivating silent-omission
  > scenario because no failed `gh` call is recorded when no call
  > occurs. The workflow can therefore remain green while required
  > receipts are absent.
  >
  > Review comment:
  >
  > - [P1] Detect missing receipt calls, not only failed calls —
  >   /home/wesley/.local/share/emcee/runs/castle-turing/2026-09-02T23-41-35/wt-0045-codex-followup-receipts-1/.github/workflows/claude-codex-followup.yml:118-118
  >   When Claude claims a receipt was posted but never invokes
  >   `gh`—the exact failure mode this change is intended to
  >   catch—the log remains empty and this step reports success.
  >   Checking only nonzero invocations therefore cannot prove that the
  >   required inline replies, resolutions, or summary comment were
  >   attempted; track successful posting calls and expected counts, or
  >   query GitHub afterward to verify the artifacts exist.

  **Disposition: fixed, by the second option offered — querying
  GitHub afterward.** "Track successful posting calls and expected
  counts" was considered and rejected: it would mean pattern-matching
  the shim's *successful* calls by shape (reply-vs-resolve-vs-comment)
  to derive an "expected count," which is exactly the fragile
  classifier problem already reasoned through and rejected under "Why
  every failing `gh` call, not just 'posting' calls," above — a
  `resolveReviewThread` GraphQL mutation and a plain read both go
  through `gh api graphql`/`gh api`, and distinguishing them from
  argument shape alone is brittle. Querying the forge afterward avoids
  that entirely: the two `gh api` calls "Confirm the review's receipts
  actually landed" makes don't care what commands the model ran or in
  what shape, only what state the PR is actually in — closer to the
  entry's own stronger suggestion ("confirm the artifacts the run's
  replies reference actually exist") than to its cheap fallback, but
  still only two `gh api` calls and a `jq` diff, not the elaborate
  free-text-parsing version the brief had originally scoped out.
  Verified locally against four scenarios with a fake `gh` returning
  fixture JSON (real `jq` via `nix-shell -p jq`, since this development
  machine has no system `jq`): every inline comment replied to and the
  comment count increased (pass); one inline comment left unreplied
  (fails, names the specific comment ID); comment count unchanged, i.e.
  no summary posted (fails, names the PR #73 shape explicitly); a
  review with zero inline comments and a summary posted (pass, the
  inline-reply loop correctly no-ops on an empty ID list).
- A second `/code-review` pass (scoped against `origin/main`, run
  after the forge-check commit above), three finder angles: altitude
  and CLAUDE.md conventions found no violation; a cleanup finder
  caught the redundant paginated call and the per-finding `jq`-spawn
  loop, both fixed (judgment call 10) and re-verified locally against
  the same four scenarios plus a fifth confirming a reply comment that
  itself carries the review's `pull_request_review_id` (a real shape,
  confirmed live against PR #73's own data by that same finder) is
  still correctly excluded from the "needs a reply" set; a correctness
  finder reported a "confirmed, critical" heredoc-termination bug that
  did not survive re-verification with an actual YAML parser (judgment
  call 11) and also raised the before/after comment-count race,
  recorded as an accepted limitation (judgment call 10) rather than
  hardened further.

What only a real run proves, and what a reviewer should look for on
this task's own PR: `claude-codex-followup.yml` triggers on
`pull_request_review` submissions from the Codex bot, so if Codex
reviews this PR, that review is this change's own first live exercise.
Look for:

- All three new/changed steps present and green in the run (the "Wrap
  gh" snapshot addition, "Fail loudly," and "Confirm the review's
  receipts actually landed").
- The "Fail loudly" step's own log line — "Every gh call in this run
  exited zero." — confirming the job reached that step cleanly.
- Corroboration that the shim was actually live, not silently bypassed
  (judgment call 5, above): the "Run Claude on Codex's findings" step's
  own logs should show `gh` invocations executing normally with their
  usual output: an empty failure log by itself doesn't distinguish "no
  posting calls failed" from "no gh calls went through the shim at
  all," so the corroborating signal matters as much as the log's
  emptiness.
- If a real posting failure occurs on this or a future PR, the job
  should go red with the `::error::` annotation naming the failing
  command — that is the actual event this task exists to make visible,
  and it may never happen to be observed on this specific PR.
- The "Confirm the review's receipts actually landed" step's own log
  line — either the pass message or an `::error::` naming a specific
  unreplied comment ID or the missing-summary-comment message. If
  `env: GH_TOKEN: ${{ github.token }}` (judgment call 8) turns out to
  be insufficient permission for a `run:` step despite being GitHub's
  documented pattern, this step's own `gh api` calls fail under the
  job's default `bash -e` shell and the step goes red directly on its
  own — still the fail-safe direction (a broken check still shows red,
  it just wouldn't say why in the friendly `::error::` form), but
  worth distinguishing from an actual missing-receipt finding if seen.
