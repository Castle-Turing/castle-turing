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

**2. A verification step outside the model's control (the load-bearing
piece).** A new "Wrap gh to catch silent posting failures" step runs
immediately after checkout, before the Claude action. It resolves the
real `gh` binary, writes a shim of the same name to a scratch
directory, and prepends that directory to `PATH` via `$GITHUB_PATH` —
so every `gh` invocation for the rest of the job, including all of the
model's own tool calls, runs through the shim first. The shim always
calls through to the real `gh` and passes its exit code back
unchanged, but if that exit code is nonzero, it appends the failing
command and its arguments to a log file in `$RUNNER_TEMP`. A final
"Fail loudly if any gh call failed this run" step, `if: always()`,
checks that log after the Claude action step completes (success or
failure) and fails the job — with `::error::` and the log's contents —
if it is non-empty. The model never sees the shim, cannot disable it
short of reading and defeating it deliberately, and its own narration
in a final summary comment has no bearing on whether the job goes red.

The entry's second, more thorough suggestion — checking that the
artifacts a run's replies actually *reference* exist on the forge, not
just that the `gh` calls that create them exited zero — was not built.
The entry itself only asks for it "if... cheaply"; doing it for real
means parsing the model's free-text summary for claimed artifact
identifiers and cross-checking each against the GitHub API, which is
real complexity for a marginal gain: the exit-code check below is
already a superset of what it would catch, since every way a "reply
succeeded" claim can be false while a `gh` call still exited zero
(wrong PR, wrong comment ID, wrong body) is a bug in the model's
*arguments*, not something this run's own replies would let it lie
about undetected — the model would have to fabricate the reply's
content in its summary while the real API call still succeeded, which
is a different, narrower failure mode than the one PR #73 actually hit
(a call that just never happened). If that narrower failure mode is
ever observed, it is worth a new backlog entry naming it specifically,
rather than building the general mechanism speculatively now.

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
  model's summary claims (see "not built," above) — only that the `gh`
  call used to post it exited zero.
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

What only a real run proves, and what a reviewer should look for on
this task's own PR: `claude-codex-followup.yml` triggers on
`pull_request_review` submissions from the Codex bot, so if Codex
reviews this PR, that review is this change's own first live exercise.
Look for:

- Both new steps present and green in the run.
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
