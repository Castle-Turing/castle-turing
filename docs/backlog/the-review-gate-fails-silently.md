# The review gate fails silently

**What.** On 2026-09-10 the cross-vendor review gate produced no
posted review for five pull requests across emcee and dovetail while
reporting success: the gate script's transcript parser could not find
the reviewer's output (Codex v0.147.0 began emitting ANSI color codes
even when piped, so the bare-speaker marker and the metadata regexes
stopped matching), so it printed "produced no review" and posted
nothing — indistinguishable, to anyone not watching, from "the
reviewer had no findings." The reviews existed in full in the
transcripts and were recovered and posted by hand. The parser was
fixed the same day (`chevaline-whharris/scripts/cross-vendor-review.py`,
an ANSI strip before parsing) and verified end-to-end. This entry
exists because the fix closes the specific bug, not the class.

**Why it matters.** [[the-resident-reviews-specs-not-code]] makes the
automated review layer the sole defense against code-level defects.
The day that doctrine was stated, that same layer failed in the one
way the resident is structurally unable to catch — a silent success —
and it was caught only because a person happened to be watching the
sprint. This is the second time the review pipeline has failed
silently: a predecessor findings-handler had never once worked and
nothing said so (the incident behind the chevaline
`handle-review-findings` rewrite). A defense relied on completely
whose failure mode is a quiet day is the exact hazard the
incident-ships-its-detector rule exists for.

**How it would have been caught sooner — the detector this owes.**
Two mechanical checks, neither of which exists:

- *The gate asserts it ran.* A gate invocation that finds no review
  must be distinguishable from a gate that was never invoked and from
  a review with genuinely zero findings. The empty result should be a
  positive receipt ("gate ran, reviewer returned N findings" or
  "reviewer returned an empty review, transcript at X"), and a parse
  that yields nothing from a non-empty transcript is an error exit,
  not a silent "no review."
- *Every merged PR carries its review receipts.* A periodic (or
  CI-time) check that a merged pull request received a review round
  turns "the gate silently didn't run" into a flagged finding rather
  than an invisible gap. This is the same invariant
  [[the-corpus-is-never-swept-against-the-conventions]] would sweep
  retroactively and [[nothing-sweeps-the-pipeline-invariants]] would
  enforce at runtime; this entry is the concrete incident that
  motivates baking it in.

**Note on scope.** The gate script lives in the resident's private
Chevaline profile, not in this repo, so the parser fix landed there.
What belongs here is the repo-side invariant (merged-carries-review)
and the general "a gate that finds nothing must prove it ran"
contract — both of which are this project's to enforce regardless of
which vendor's reviewer the gate wraps.

**Open questions.** Whether the merged-carries-review check is a
standing CI job per repo or a phase of the conformance sweep. What
the gate's "I ran and found nothing" receipt looks like in the
journal so the sentinel and digest can read it. And whether the
parser fragility itself (a reviewer CLI's output format silently
breaking a downstream parser) wants a contract test in the profile,
which is the resident's call on their own repository.
