Title: The direnv probe names its own timeout and logs its duration
Model: standard
Milestone: none — hygiene
Model-because: the edit is small and fully specified — one probe
script, one reader function, one bound — but it sits in measured-timing
terrain where the failure mode of a wrong change is the exact flake
being fixed, and the semantics being handled (timeout's 124, a shell
with set -u but no set -e, the test driver's outer 900s bound) are the
kind a cheap implementer follows off a cliff without noticing a
contradiction. Standard, not deep: every decision is made below and the
verification plan includes forcing the new failure path once, so wrong
assumptions surface in the implementer's own run rather than in CI.

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

## Decisions, closing this entry's open questions

**The evaluation stays nixpkgs-scale; the bound moves.** Shrinking the
fixture flake was considered and rejected: the cold-cache case exists
to hold task 0083's re-entrancy guard against a *real* evaluation, and
a toy flake that evaluates in seconds hollows out exactly the property
being asserted. The right bound given a ~105s idle-runner measurement
and CI runners that evidently more than double it: **600 seconds** —
generous against load, while still well inside the test driver's own
default 900s bound on the `wait_until_succeeds` that polls for
`PROBE_DONE`, so a genuine hang is still detected by the probe's own
bound, with its own message, before the driver's generic one fires.

**The inner `timeout` stays, and becomes the detector.** Removing it
and leaning on the driver's outer bound was also considered and
rejected: a probe that just never finishes fails as a generic
`wait_until_succeeds` timeout — "marker genuinely absent" again, which
is precisely the ambiguity this entry exists to close. The inner
`timeout` is what lets the probe *say* it timed out.

## Spec

All changes in `test/direnv-delivery/test.nix`; nothing else moves.

**1. The probe records its own outcome.** `probeScript` wraps the
timed section so the output file carries, after the existing `RESULT`
line and before `PROBE_DONE`:

- `PROBE_STATUS <n>` — the exit status of the `timeout 600 bash -c`
  invocation, captured immediately (`status=$?`; the script runs under
  `set -u` without `set -e`, so a non-zero status reaches the capture
  rather than aborting the block — keep it that way).
- `PROBE_SECONDS <n>` — wall-clock duration of that invocation,
  measured with `date +%s` before and after. This is the trend line:
  it prints on every run, pass or fail, so creeping eval cost is
  visible in CI logs long before it crosses the bound.

The bound itself: `timeout 180` becomes `timeout 600`, and the
adjacent comment is rewritten to carry the new numbers and the outer
900s relationship (present tense only — the incident narrative lives
in this brief, not in the test's comments).

**2. The reader asserts on the status, separately and first.**
`read_probe_result` (testScript) parses `PROBE_STATUS` and
`PROBE_SECONDS` alongside `RESULT`:

- Status `124`: fail immediately with a message naming the timeout —
  the probe's cold evaluation outran its 600s bound after
  `<PROBE_SECONDS>` seconds; this is load or eval-cost growth, not a
  missing marker.
- Any other non-zero status: fail naming the status.
- Status `0`: proceed to the existing marker assertions unchanged.
- In every case, print the duration (the existing `print` of the raw
  probe output already surfaces it; keep that, and include the parsed
  seconds in the returned context or an explicit print so the number
  is greppable per-probe).

Every probe call goes through this — the status check is uniform, not
special-cased to the cold probe, so any future probe kill names
itself too.

## Plan

1. Edit `probeScript`: bound to 600, status and duration capture, new
   output lines, comment rewrite.
2. Edit `read_probe_result`: parse and assert `PROBE_STATUS` before
   the marker logic; surface `PROBE_SECONDS`.
3. Run the VM test once with the bound temporarily set to `1` to see
   the new timeout failure message fire, then restore 600 — the one
   cheap proof that the detector detects.
4. Run the real test to green; outcome row; PR.

## Verification plan

Machine-only, no human hands:

- `nix build .#direnv-delivery-test` passes with the final bound —
  the test still proves everything it proved before (markers,
  whitelist, re-entrancy storm count, warm-cache zero).
- The bound-set-to-1 proof runs through CI rather than a local scratch
  run (this host has no `nix` build capacity for the VM test): a commit
  setting the bound to 1 is pushed, triggered via `workflow_dispatch`,
  and observed to fail with the named `PROBE_STATUS 124` message rather
  than a marker-absent assertion, then reverted on the branch (`git
  revert`, keeping both commits in history) — the detector's own
  detector, with both runs' ids reported in the PR description.
- The probe output in the passing run's log shows `PROBE_SECONDS` for
  every probe — the trend instrumentation exists from day one.

## Implementation prompt

Implement docs/tasks/<this task's number> in the castle-turing repo.
Read the brief in full first; the Decisions section closes both of the
entry's open questions — do not reopen them, and do not shrink the
fixture flake. The only file you touch is
`test/direnv-delivery/test.nix`. Mind the shell semantics the brief
names: the probe runs under `set -u` without `set -e`, and the status
capture must be the first thing after the `timeout` invocation. The VM
test is expensive — build it as few times as the plan allows (the
bound-1 scratch run, then the real run). Work on a branch, never on
main. Report any judgment call where this brief was ambiguous.
