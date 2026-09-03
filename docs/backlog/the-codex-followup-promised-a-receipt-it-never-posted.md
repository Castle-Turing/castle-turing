# The Codex followup promised a receipt it never posted

**What.** On PR #73 (2026-09-02), the followup session's inline
replies said the two workflow fixes it could not push (see
[[the-codex-followup-cannot-push-workflow-fixes]]) were "reproduced
verbatim in the PR-level summary comment" for a human to apply. That
comment does not exist. Nothing errored and nothing warned; the
promised artifact simply never landed, and the absence was noticed
only because a human went looking for the diff to apply it. The 0041
brief happened to carry prose descriptions of both fixes — had it not,
the fixes would have been recorded nowhere while two PR threads
claimed otherwise.

**Why this shape is familiar.** It is the failure
`tools/codex-review.sh`'s own header was written against: when the
GitHub-integrated Codex review silently stopped running, "nothing
failed, it just stopped happening," and the review gap went unnoticed
for days ([[cross-model-review-is-paywalled]] records the original
incident). A report that describes work as done is not evidence the
work happened — this project already applies that rule to sub-agent
reports ("every report is a claim"), and the followup automation is a
sub-agent whose delegator is a YAML file that verifies nothing.

**Fix direction.** Two complementary pieces, both small:

- The followup's prompt should order operations so a reply never
  refers to an artifact that has not already been posted — post the
  thing first, cite it second, and on failure say "I could not post
  X" rather than describing X as existing.
- The workflow itself should end with a verification step outside the
  model's control: confirm the artifacts the run's replies reference
  actually exist (or more cheaply, fail the job loudly when any `gh`
  posting call in the run exited nonzero), so a silent partial
  delivery turns into a red run a human can see.

The second piece is the load-bearing one. Prompts drift and models
have off days; a check that runs after the session, against the forge
itself, does not.
