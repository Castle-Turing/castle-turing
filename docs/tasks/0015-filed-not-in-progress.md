# Task 0015 — An unstarted errand is not "in progress"

**Before starting:** read `CLAUDE.md`, `agent/castle-modal`'s
`_errand_state` and `run_status`, `agent/castle`'s `cmd_digest`, and
`docs/tasks/0009-ambient-intake.md` (which built the status surface).
Work on branch `errand-state-honesty`; this brief rides it. PR to
`main`.

**Goal.** The status surface stops claiming work is underway when
nothing has touched the errand.

## Why

`_errand_state` returns `"in progress"` as its **fallthrough** — the
last line, reached when there is no `result` and no unanswered
`question`. It is not a claim that a worker is running; it is "none of
the other states matched." And since no record type means *a tenant
claimed this errand*, the fallthrough can never mean anything else.

So every filed request reads "in progress" indefinitely, including ones
nothing will ever pick up. The resident found this by reading the status
output on the reference host, on a system where **no worker has ever run
automatically** — `castle work` is invoked by hand.

**The harm is not cosmetic: the label causes the inaction it
describes.** A resident who sees "in progress" does not run
`castle work`, so the errand sits, still reading "in progress." The
display generates the appearance of activity from the *absence* of
evidence rather than the presence of it — the same failure shape as a
check that passes because it verifies nothing.

## Scope

1. **Rename the fallthrough** in `agent/castle-modal`'s `_errand_state`
   to something true — `filed`, `awaiting a worker`, or similar. Pick
   one and use it consistently; do not introduce two spellings.
2. **Say why in a comment**, in the style of the existing block above it
   (which records the 0009 review finding about "done" masking "waiting
   on you"). The next reader must understand that this state means
   *nothing has claimed the errand*, and that a genuine in-progress
   state requires a record type that does not exist yet.
3. **Check `cmd_digest` for the same claim.** The digest folds the same
   journal; if it reports a comparable state anywhere, it must agree
   with the modal. Two surfaces disagreeing about an errand's state is
   worse than one being wrong.
4. **Test it.** `test/agent-loop/modal-headless-test.sh` should assert a
   request with no downstream records reports the new state, and the
   existing states (`done`, `waiting on you`, `done, waiting on you`)
   still report unchanged.

## Non-goals

- **Do not add a started/claimed record type.** That is the real fix for
  making "in progress" *earnable*, and it belongs with the first
  asynchronous worker — writing it now would add a record always written
  and read microseconds apart, since `castle work` runs synchronously
  from a shell. Note it in the PR as the deferred half.
- No other change to `_errand_state`'s logic. The `done` / `waiting on
  you` / `done, waiting on you` branches were fixed in the 0009 review
  pass and are correct.
- No change to record types, the schema, or `castle route`.

## Verification

Agent-testable in full: the headless modal test plus `nix flake check`.
No VM run needed — this is a string and a comment, and the assertions
are already headless.

Human hands: none. The resident will see the new label next time they
open the status view.
