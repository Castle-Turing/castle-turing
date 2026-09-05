Title: The review-findings handler that never ran

# 0052 — The review-findings handler that never ran

`claude-codex-followup.yml` has never once completed. Across its last
sixty runs: twenty-nine cancelled, thirty skipped, one failed, zero
successful. Every finding it was supposed to judge, fix or answer has
been handled by a human, or not at all — and nothing anywhere reported
that the automation was dead. This brief replaces it.

## The defect

The workflow declared

    concurrency:
      group: codex-followup-${{ github.event.pull_request.number }}
      cancel-in-progress: true

and triggered on `pull_request_review`, filtering to the Codex reviewer
in the job's `if:`.

GitHub evaluates a workflow's concurrency group **before** the job's
`if:` condition. Every `pull_request_review` event on the pull request
therefore joined the group — including the reviews posted by this
repository's own `claude-code-review.yml`, which fires on every
non-documentation pull request and posts within a few minutes of the
Codex review. Those events cancelled the in-flight Codex handler and
were then skipped by the `if:`, leaving nothing running.

The evidence is in the run timings. On pull request 81, the handler
started at 16:52:33 when Codex reviewed and was killed at 16:56:45, as
the repository's own review landed at 16:56:26. On pull request 80, the
same shape: started 13:20:47, killed 13:23:12. The comment block at the
head of the old file listed the concurrency slot under "loop prevention,
by construction" — it was preventing the work, not a loop.

The lesson generalizes past this file: **a concurrency group scoped to a
pull request must not cancel in progress**, because the group catches
events the job then declines to act on.

## The change

`.github/workflows/claude-codex-followup.yml` is deleted and replaced by
`.github/workflows/handle-review-findings.yml`, an unmodified copy of
the canonical workflow in the resident's profile — the same file every
repository the operator owns now carries. It differs from its
predecessor in three ways:

1. **It triggers on the cross-vendor gate's comment**, matched by a
   marker (`<!-- chevaline-gate: cross-vendor-review -->`) that the gate
   script emits and nothing else does. Matching a marker rather than a
   heading means the review's wording can change without silently
   switching the automation off.
2. **A concurrency group computed from the marker, which never
   cancels.** Disabling cancellation is necessary but not sufficient:
   GitHub keeps at most one *pending* run per group and a newer run
   evicts the waiting one, so an ordinary comment could still discard a
   queued handler. Keying the group by comment id fixes that and breaks
   something else — two gate comments on one pull request then run at
   once and race to push to the same head. So gate comments share one
   per-pull-request group and serialize, while every other comment gets
   a singleton group that can neither cancel nor evict them. The
   workflow also checks the commenter's effective repository permission
   rather than their `author_association`, which on a public
   organization repository admits members and collaborators who cannot
   write here. All of that came from the gate reviewing this workflow
   on the sibling repository that adopted it first — two rounds of it,
   each round trading one hazard for a subtler one.
3. **Dispositions go in one comment**, because the gate posts its
   findings as one comment rather than as inline review threads. The
   predecessor replied on each inline thread and resolved it, which was
   better; see the cost below.

The copy stays unmodified. A repository that edits its own copy has
forked the operator's default without saying so; improvements belong in
the profile's template and are copied outward.

## What this costs, stated plainly

**Receipts no longer sit on the line they concern.** The gate posts one
comment holding every finding, so every disposition lands in one reply.
The old inline-thread behaviour was better on this axis and is not
recoverable until the gate itself posts inline review comments.

**The hosted Codex reviewer's own reviews are no longer auto-handled.**
That reviewer still comments on pull requests here, and its findings now
wait for a human unless the gate is also run on the branch. This is the
deliberate consequence of having one mechanism rather than two: the gate
runs locally and therefore works on every repository, including those a
hosted reviewer cannot reach, and it is the mechanism the profile
declares. The gate has to actually run on this repository's pull
requests for the automation to have anything to act on — as the sprint
harness's post-pull-request hook, or invoked by hand on a
hand-opened pull request.

**Findings from this repository's own `claude-code-review.yml` remain
unhandled**, as they were before. Closing that loop is a separate
decision — it means a model of the same family judging its own family's
findings — and it is already recorded as an option in
`docs/backlog/cross-model-review-is-paywalled.md`.

## Considered and rejected

**Fixing the concurrency key and keeping the Codex-review trigger.** The
smaller change, and it would have restored the old behaviour including
inline receipts. Rejected because it leaves two different mechanisms for
the same job — a hosted reviewer here, a local gate everywhere else —
and a default that only works where a vendor's connector reaches is not
a default. One mechanism, one file, one place to fix it.

**Keeping both triggers in one workflow.** Broader coverage, but two
trigger paths to keep working and a duplicate second opinion on every
pull request where both fire. Worth revisiting only if the hosted
reviewer turns out to catch things the gate does not.

## Verification plan

Agent-testable:

- The workflow file parses as valid YAML and declares the expected
  trigger, job condition and concurrency settings.
- It is byte-identical to the profile's template. The profile is not
  public, so this is verified by whoever holds it at the moment of
  copying rather than by a check in this repository.

Needs human hands, because the failure this task exists to fix is
invisible without looking:

1. On the next pull request that receives gate findings, read the run
   list for this workflow and confirm the run **completed** — not
   cancelled, not skipped. That is the specific check the predecessor
   would have failed on every one of the sixty runs examined here.
2. Confirm the dispositions comment names every finding, each fixed with
   a commit hash or declined with reasoning.
