# The direnv-delivery test is timing-flaky in CI

**What.** Found when the check failed twice on PR #154 — a PR that
touches nothing direnv-related — after passing on the same content's
main run minutes earlier. The test's whitelisted-project probe
exercises a real cold-cache `direnv export bash`, which runs a genuine
flake evaluation inside the VM; on a loaded runner that evaluation
outlives the probe's own bound. `test/direnv-delivery/test.nix`
(`probeScript`) runs the probe under `timeout 180`, which kills the
shell before `PROBE_DONE` is written (the log shows direnv's "is taking
a while to execute" warning, then "error: interrupted by the user"),
and the marker assertion fails on healthy code. The comment there
records a cold load measured up to ~105s; a loaded runner evidently
exceeds the remaining margin.

The workflow already wraps `nix build` in
`test/ci/retry-on-known-transient.sh`; an earlier run on the same PR
died on an Actions-cache rate limit (HTTP 418) that the wrapper
absorbs, so that is not a defect here.

**Why it matters.** This check gates every pull request that trips its
path filter. A detector that reds healthy branches teaches people to
re-run until green, which is indistinguishable from teaching them to
ignore it — the exact decay the incident-ships-its-detector rule
exists to prevent, on the detector shipped for the 2026-10-02 incident
itself.

**How it would have been caught sooner.** It was found by a human
reading red checks on an unrelated PR. Mechanically: the test's
failure output cannot tell "probe killed by `timeout 180`" from
"marker genuinely absent" — the assertion just sees a missing
`PROBE_DONE`/marker. The detector is to make the probe distinguish the
two (record the `timeout` exit status, 124, in the probe output and
assert on it separately), so a timeout names itself instead of
masquerading as a regression; and to log the measured probe duration
on every run so creeping eval cost shows up as a trend before it
crosses the bound.

**What we already know.** The cold-cache evaluation case is
load-bearing (it asserts the eval-storm fix's re-entrancy guard against
a real evaluation, task 0083's decision) — deleting it is not the fix.
Candidate fixes: raise or restructure the `timeout 180` bound; shrink
the evaluated flake so cold-cache cost is seconds, not a
nixpkgs-scale evaluation, while still being a real evaluation; or
both.

**Open questions.** Whether the sample project's evaluation can be made
small without hollowing out the re-entrancy assertion, and what bound
is right if it cannot.
