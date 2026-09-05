# Task 0056 — an environment fault is not a malformed patch

There is no backlog entry behind this one, the same shape as its
predecessor `docs/tasks/0055-a-malformed-patch-is-not-a-stale-one.md`:
it comes from the cross-vendor review of the pull request that landed
0055 (2026-09-05, posted verbatim on that pull request), and the task
file that carried it into the queue is this brief's predecessor rather
than a separate document.

This finishes the split 0055 started. 0055 separated "the kept copy is
not a patch" from "the patch no longer fits". What it did not separate
is "this machine could not tell us either way", which was already
sitting inside the first of those.

## The finding

`_patch_paths` returns "no paths" for four distinct conditions, and
0055's new `refused-patch-malformed` outcome covered all four — but
only one of them is a malformed patch:

1. `shutil.which("git")` is None — git is not on this session's PATH.
2. `subprocess.run` raises `OSError` or `TimeoutExpired` — git could
   not be run there.
3. git runs and exits nonzero parsing the kept copy — the genuine
   malformed patch, 0055's own case.
4. git succeeds and its `--numstat -z` output surprises the parser
   (unexpected field count, or output ending mid-rename) — this code
   meeting output it did not expect.

For 1, 2 and 4 the record told the resident the kept copy "could not be
read as a patch at all … re-approving the same proposal would fail the
same way. Ask for the change again" — which is false. The same proposal
on a working machine would apply, and the remedy the record prescribes
buys a second turn that produces the same patch and meets the same
broken machine.

The applier already treats this distinction as load-bearing twenty
lines below. When `_run_git(["apply", "--check"])` returns None it
writes `outcome: failed` with no `apply-outcome` and raises
`ApplyEnvironmentFault`, aborting the sweep so that one broken machine
cannot burn every pending authorization in a single pass. The identical
conditions inside `_patch_paths` bypassed that shape entirely.

Second, and pre-existing: `why_paths` was rendered into the record body
without `_displayable`, against `_patch_paths`' own docstring warning
that its strings are not safe to render. Case 3 decodes git's stderr
with `errors="replace"` and is safe; the unsafe residue is exactly what
cases 1, 2 and 4 produce — an `OSError` stringifies with the path it
failed on, and that path can carry a lone surrogate into a record that
is UTF-8 by definition.

## What was built

`_patch_paths` returns three slots instead of two —
`(paths, why, fault)` — and the two failure slots are never both
filled:

| condition | slot | what `_apply_one` does |
| --- | --- | --- |
| git not on PATH (1) | `fault` | `outcome: failed`, no `apply-outcome`, `ApplyEnvironmentFault`, sweep aborts |
| git would not run or outlived its bound (2) | `fault` | the same |
| git read the bytes and refused them (3) | `why` | `apply-outcome: refused-patch-malformed`, exactly as 0055 built it |
| git's own `--numstat -z` output could not be read (4) | `fault` | the environment-fault shape |

Two slots rather than one string a caller parses. The choice between
them is the difference between telling a resident their proposal was
never usable and telling them their machine is broken, and nothing that
consequential may rest on a substring match. `_run_git` splits the same
two facts the same way, and reusing its shape is what keeps a third
convention from appearing.

Every string that can reach a record body now goes through
`_displayable` at the point of rendering — `why_paths` in the malformed
refusal, and the fault in both the record body and the
`ApplyEnvironmentFault` message, which `cmd_apply` prints to stderr.
The sanitising happens at the caller and not inside `_patch_paths`,
because a value a caller might hand back to git must keep its bytes;
that is the same reason the paths themselves are returned raw.

### Judgment call: case 4 is the machine's fault

The review said either bucket is defensible if chosen deliberately.
This chooses the environment side, for three reasons in descending
order of weight.

**The record would otherwise prescribe a remedy that cannot work.**
git exited zero — it parsed the patch. What failed afterwards is this
parser meeting output it did not expect, and no re-proposal changes
that. "Ask for the change again" is precisely the false remedy this
task exists to delete; putting a fourth condition behind it would
reintroduce the defect in the same commit that removes it.

**The failure directions are not symmetric.** Being wrong in this
direction costs a sweep that stops early and runs again next timer
tick — no authorization is spent, because the aborted sweep never
reaches the remaining approvals. Being wrong in the other direction
spends an authorization on a record that misdescribes what happened,
and an authorization is the one thing here that is neither cheap nor
repeatable.

**The counter-argument, stated rather than dismissed.** Case 4 is
reachable only for *some* patches — a rename is the shape that gets
near it — so a sweep that aborts on one may be refusing to try
approvals that would have applied perfectly. That is real, and it is
the cost accepted above: a delayed sweep against a misdescribed
authorization. It also argues for `_patch_paths` being taught the
rename form properly rather than for re-bucketing the failure, which
is a different task from this one.

### Judgment call: proposal time keeps the answer git already gave

`_check_proposal_applies` (0054) calls `_patch_paths` too, inside a
worker turn where "abort the sweep" is not the frame and the no-raise
contract stands. It calls it only *after* `git apply --check` has
already returned nonzero, and only to find out whether the resident's
own uncommitted work excuses that failure.

So an environment fault there does not degrade the verdict to
`offered-unchecked`. git has already spoken about this patch; what
could not be established is the *excuse*, and 0054's own rule is that
"a dirty tree excuses the failure; an unanswerable dirty probe does
not". Both halves of a failed attribution therefore fall through to
`refused-patch-stale`, which rests on git's answer and not on the probe
that failed. The obvious-looking alternative — degrade to
`offered-unchecked` — would report a doubt that the check has already
resolved, which is the defect 0054 names at its own opposite pole.

Note that the dominant route for an environment fault at proposal time
never reaches `_patch_paths` at all: if git is missing or unrunnable,
`--check` returns None first and the proposal is already
`offered-unchecked`. What is left for `_patch_paths` to report is a
machine that broke between two calls a few milliseconds apart, and
`refused-patch-stale` is the honest reading of that: git said no, and
nothing excused it.

### Append-only: nothing to reconcile, stated rather than assumed

The outcome vocabulary does not change. No value is added, renamed or
retired in `APPLY_OUTCOME_VALUES`, `PROPOSAL_OUTCOME_VALUES` or
`APPLY_FIRST_LINES`, so no existing record can be condemned by a
validator that did not condemn it yesterday, and no reader learns a
value it does not know.

What changes is which records *future* faults produce. Records already
stamped `refused-patch-malformed` by cases 1, 2 or 4 would now be
written as environment faults instead — and none is believed to exist:
0055 merged on 2026-09-05 and the only journal it has run against is
this repository's test harness, whose fixture is case 3. That belief is
stated here rather than asserted as fact, because nothing in this
change depends on it: an old record keeps the code it was stamped with,
exactly as 0055 settled, and remains a correct historical statement of
what the applier decided under the vocabulary of the day.

### Two things found on the way, and what was done with each

**`test/agent-loop/apply.sh` was already failing on `main`.** 0055's
malformed scenario builds its fixture with `new_approval`, which runs a
real turn and expects a proposal question. 0054 — merged first, but
branched later — makes the harness refuse to file a question for a
patch git cannot parse. The two are individually correct and their
merge is not: since 2026-09-05 the scenario fails at
`APPLYABLE-MALFORMED: the turn filed no change to decide`, and the
assertions below it never run.

The fixture is repaired here rather than left for another task, because
this task cannot be verified without it. It now runs the work turn with
a `git` on PATH that cannot be executed, which is a real machine state
and reaches `_check_proposal_applies`' `offered-unchecked` degrade: the
question is filed unchecked, the resident approves it, and the applier
— on a machine where git works — meets the malformed patch. That is not
a contrivance to keep an old assertion alive. It is the route by which
a malformed patch still reaches the applier at all now that 0054 checks
proposals, and the scenario asserts the whole chain rather than only
its last step.

**Proposal time still spells both facts `refused-patch-stale`.** The
comment above `PROPOSAL_OUTCOME_VALUES` said 0055 would move that
vocabulary with the applier's when it landed. 0055 did not, and the
comment has been describing a plan rather than the code ever since.
Closing that gap means a new proposal-outcome value, prose on two more
surfaces and a decision about whether a malformed proposal should be
refused differently from a stale one at filing time — a task, not a
detail of this one. So the comment is corrected to say what is
actually true, and the work is filed as
`docs/backlog/proposal-time-cannot-name-a-malformed-patch.md`.

## Verification

`test/agent-loop/apply.sh`, which runs with no Nix, no models and no
network. Three scenarios are added under one heading, all of them
asserting the same shape — `outcome: failed`, no `apply-outcome`, no
`apply-commit`, the body naming the fault, the private and mechanism
checkouts untouched, and `castle validate` still green:

- **git is absent.** Two approvals are made eligible and the sweep runs
  with a PATH that has no git on it. It aborts: exactly one record is
  written, the second authorization is untouched and still spendable,
  and the record is not `refused-patch-malformed`. Then the machine is
  repaired, the burnt approval is applied by hand — the remedy the
  status surface names — and a second sweep spends the one the abort
  protected. That last half is what proves the abort cost a delay
  rather than an authorization.
- **git will not run.** A `git` on PATH whose interpreter does not
  exist, so `subprocess.run` raises `OSError` inside `_patch_paths`
  while `_checkout_fault` upstream degrades past it exactly as its
  docstring says it does. This is case 2's `OSError` half.
- **git's output is not what this code can read.** A `git` shim that
  passes everything through to the real one except `apply --numstat`,
  where it exits zero with a record that has too few fields. This is
  case 4, and it is here because case 4 is this brief's open judgment
  call: a test is the only thing that can hold a decision like that in
  place.

Two conditions are deliberately not fixtured, and this says so rather
than leaving the gap silent. **`TimeoutExpired`** (case 2's other half)
would need a `git` shim sleeping past `CHECKOUT_PROBE_SECONDS`, a real
ten seconds in a suite that otherwise runs on stubs; it shares its
`except` clause and its return slot with the `OSError` half that is
tested, so what a test would add is coverage of `subprocess`' own
timeout rather than of anything this task decides. **Output ending
mid-rename** is the second of case 4's two parsing surprises and
returns in the same slot as the first, which is fixtured.

0055's malformed scenario stays, with its original assertions
unchanged: `apply-outcome: refused-patch-malformed`, git's own account
in the body, no claim that the repository moved. What is added to it is
the two facts its fixture now depends on — that the turn's result
carries `proposal-outcome: offered-unchecked`, and that the question
was filed anyway.

Human hands: none.

## Non-goals

- No new outcome value anywhere, and no rewording of
  `refused-patch-malformed`'s prose. 0055 settled what that record says
  to a resident; this task only settles which conditions get to say it.
- Not the proposal-time split (backlog entry above).
- Not teaching `_patch_paths` git's rename form better than it knows it
  today. Case 4 is routed, not eliminated.
