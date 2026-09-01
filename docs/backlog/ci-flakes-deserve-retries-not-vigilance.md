# CI flakes deserve retries, not vigilance

**What.** PR #63's desktop-loop-test failed twice in one afternoon
(2026-09-01) with the code green both times, and each recovery was a
human (or an agent a human interrupted) reading logs and clicking
re-run. Two distinct failure classes, both with recognizable
signatures and deterministic cures:

1. **Transient infrastructure**: a FlakeHub login failure
   ("Transient authentication mechanism error") followed by the GitHub
   Actions cache rate-limiting narinfo downloads into HTTP 418s. Cure:
   retry the job.
2. **The runner-capability lottery**: a runner without KVM. The
   workflow's own fail-fast caught this on one path and printed
   exactly the right message — and a second path slipped past it and
   crawled under TCG emulation for 44 minutes until the job's time
   budget cancelled it. Cure: check KVM first on every path, and when
   it is absent, fail within seconds so a retry (which lands on a
   fresh runner) is cheap.

**Fix direction.** A bounded retry at the workflow level for
signature-matched failures — a re-run step or a small
`workflow_run`-triggered job that re-runs a failed required check once
when its log matches the known-transient list, and never twice. Keep
the signature list in one commented place; it will grow. This is
mechanism-over-vigilance: every class CI can recognize and retry
itself is a class no agent loop (and no resident) ever has to notice.
The harness-side triage of failures needing *judgment* is the coding
harness's job, not this repo's — this entry covers only what CI can
prove about itself.
