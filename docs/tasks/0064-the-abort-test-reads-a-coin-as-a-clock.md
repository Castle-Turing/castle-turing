Title: Task 0064 — the abort test reads a coin as a clock
Model: deep
Model-because: the diff is a mechanical rewrite of one test scenario,
but it is the transcription of a root-cause diagnosis this session
performed against live CI history, and the wrong fix (a sleep between
the approvals) would have gone green while leaving the false
assumption latent. The judgment was the diagnosis; the implementer is
the diagnostician.

# Task 0064 — the abort test reads a coin as a clock

## The symptom

`dispatch-test` fails intermittently in CI with "one broken machine
spent the second authorization as well, which is what the abort
exists to prevent" — observed failing on the merge push of PR #100,
passing on PR #102's push a minute later with identical code, and
failing again on PR #103's branch. The failing scenario is
`test/agent-loop/apply.sh`'s "no git on the applier's PATH: the sweep
aborts rather than burning every approval."

## The root cause

The scenario creates two approvals back to back and asserts the
broken sweep's abort spent the *first-created* one, checking that the
second specifically has zero apply results. But the two chains share
no `refs` edge, and `make_id` stamps ids at one-second resolution
with a random suffix — so when both answer records land inside the
same UTC second, `order_records`' final tie-break (whole id, declared
arbitrary by task 0046's own docstring) decides which approval the
sweep meets first. On a fast CI runner the same-second case is
common, and the coin lands against the assertion roughly half the
time. Every observed failure shows the abort working exactly as
designed: exactly one authorization spent — just not the one the test
presumed. This is the fifth documented catch of the 0046 hazard, the
first inside the test suite, and it sat twenty-odd lines above a
`sleep 1` whose comment correctly explains the identical fact about
apply records — task 0046's "a hazard that defeats an author who has
just finished writing about it," verbatim.

## The fix

Assert the contract, not the coin. The abort's contract is "exactly
one authorization spent, sweep aborted, the other authorization
untouched" — it never promises which. The scenario now counts apply
results across both approvals and requires the sum to be exactly one,
derives spent/spared roles (and their expected files) from what
actually happened, runs the record-shape assertions against the spent
record whichever it is, and drives the recovery half — hand retry of
the spent authorization, resumed sweep applying the spared one — off
the same roles. The rejected alternative, sleeping one second between
the two `new_approval` calls, would force distinct stamps and go
green while leaving the order assumption in place for the next
same-second pair anywhere in the suite.

## Verification

`bash test/agent-loop/apply.sh` run locally to completion before the
PR. One honesty note: a single run exercises whichever branch of the
spent/spared split the coin picks that day; the other branch is
verified by symmetry of the rewritten assertions and, over time, by
the CI history that exposed the defect — the same runs that used to
flip this test now exercise both branches.

## The convention this bought, and what stays open

The review of this branch argued, correctly, that deferring the
prose convention to "whoever next trips the hazard" priced a
sentence at a sixth diagnosis. `test/agent-loop/README.md` now
exists, founded on exactly that sentence: a scenario creating two
records with no refs edge either gives them a real order (a refs
edge, or a commented sleep) or asserts order-agnostically. What
stays open is the mechanical half only:
`test/agent-loop/record-order.sh` forbids mechanism code sorting by
`rec.id`, but no grep pattern distinguishes a test *assuming*
creation order from a legitimate assertion — the README sentence is
the guard, and reviewers of test diffs are its enforcement.
