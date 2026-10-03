# The direnv-delivery test is timing-flaky in CI, and its workflow skips the transient-retry wrapper

**What.** Two defects in the same check, found when it failed twice on
PR #154 — a PR that touches nothing direnv-related — after passing on
the same content's main run minutes earlier. First: the test's
whitelisted-project probe exercises a real cold-cache
`direnv export bash`, which runs a genuine flake evaluation inside the
VM; on a loaded runner that evaluation outlives something's patience
(the log shows direnv's "is taking a while to execute" warning, then
"error: interrupted by the user") and the marker assertion fails on
healthy code. Second: `.github/workflows/direnv-delivery-test.yml`
invokes `nix build` bare, while its sibling workflows wrap the build in
`test/ci/retry-on-known-transient.sh` — so the run before the flaky one
died on an Actions-cache rate limit (HTTP 418) that the wrapper exists
to absorb.

**Why it matters.** This check gates every pull request that trips its
path filter. A detector that reds healthy branches teaches people to
re-run until green, which is indistinguishable from teaching them to
ignore it — the exact decay the incident-ships-its-detector rule
exists to prevent, on the detector shipped for the 2026-10-02 incident
itself.

**What we already know.** The cold-cache evaluation case is
load-bearing (it asserts the eval-storm fix's re-entrancy guard against
a real evaluation, task 0083's decision) — deleting it is not the fix.
Candidate fixes: identify and raise whatever timeout interrupts the
evaluation (the "interrupted by the user" source — test-driver command
timeout, or a wrapper's — needs identifying first); shrink the
evaluated flake so cold-cache cost is seconds, not a nixpkgs-scale
evaluation, while still being a real evaluation; or both. The retry
wrapper is a one-line workflow fix with sibling precedent.

**Open questions.** What actually sends the interrupt, and whether the
sample project's evaluation can be made small without hollowing out
the re-entrancy assertion.
