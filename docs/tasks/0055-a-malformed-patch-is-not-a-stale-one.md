# Task 0055 — a malformed patch is not a stale one

There is no backlog entry behind this one, the same shape as
`docs/tasks/done/0051-dispatch-waiter-leaves-the-cgroup.md`: it comes
from a finding made on 2026-09-05, reproduced in full below, and the
task file that carried it into the queue is this brief's predecessor
rather than a separate document.

## The finding

On 2026-09-05 the applier refused a proposal and told the resident:

> The change you approved no longer fits your configuration repository,
> so it was not made.

Nothing had moved. The patch had never been parseable — git's own
message, printed further down the same record, was `corrupt patch at
<file>:19`. The record therefore leads with a claim its own evidence
contradicts, and the resident's reaction to reading it was that the
message was strange, which is the correct reaction.

The cause is that `refused-patch-stale` (`docs/tasks/done/0026-apply-
validate.md` §C.7) covers two different facts. `agent/castle`'s
`_apply_one` calls `_patch_paths(root, snapshot)` before it ever asks
`git apply --check` whether the patch fits the current tree; that
first call runs `git apply --numstat -z` purely to read which paths a
patch touches, and it fails whenever git cannot parse the kept copy as
a patch at all — a torn hunk header, truncated output, anything short
of a well-formed diff. Until this task, that failure and a genuinely
stale-but-parseable patch were refused with the identical outcome and
near-identical prose.

The distinction is not cosmetic. Stale means the world moved and the
proposal was once good: refiling the request is the remedy, and the
worker did its job. Malformed means the turn produced something that
was never usable: the worker did not do its job, and refiling without
fixing that produces the same outcome again. A resident who reads "no
longer fits" will go looking for what changed in their repository, and
will find nothing, because nothing did.

## What was built

A distinct outcome, `refused-patch-malformed`, added to
`APPLY_OUTCOME_VALUES` beside the other applier refusals in
`agent/castle`, and routed to from the one call site that used to fall
through to `refused-patch-stale`: the `paths is None` branch right
after `_patch_paths` runs, in `_apply_one`. `git apply --check`'s own
non-zero exit — reached only once a patch has already parsed —
continues to produce `refused-patch-stale` unchanged, which is what
that code has always meant and is the whole reason this task exists
rather than a rename.

The rendered text for the new outcome, in both places `apply-outcome`
is rendered prose (`APPLY_FIRST_LINES` in `agent/castle`, the result
body's first line; `_APPLY_REFUSAL_REASONS` in `agent/castle-modal`,
the status-line fold), says plainly that the change could not be read
as a patch, that the repository was never examined, and that
re-approving the same proposal will not help — asking for the change
again is what will. Neither surface asserts that anything in the
resident's configuration moved, which is the defect this task closes.

`agent/README.md`'s `apply-outcome` table gains a row for the same
reason `outcome` itself is documented there: a fact this many surfaces
branch on belongs in the one place a cold reader checks first.

**Existing records keep the code they were stamped with.** This was
the one settled judgment call, made before implementation rather than
left to it: the journal is append-only and a record's outcome is a
fact about what the applier decided at the time, under the vocabulary
that existed then. Nothing in this task rewrites, reinterprets, or
migrates `20260905T022156Z-result-42c611` or any other record. Readers
of old records see `refused-patch-stale` and that remains correct as a
historical statement, exactly as `authorizes-apply`'s absence
(`docs/tasks/done/0026-apply-validate.md` §A) is a positive fact about
pre-0026 proposals rather than a gap to be filled. Nothing reads
`apply-outcome` off an old record and expects the new value to appear
there; the split is prospective only.

## Verification

`test/agent-loop/apply.sh` gains a scenario between the "no exact copy
was kept" and "no longer fits the repository" scenarios: an approved
proposal whose kept copy is plain text with no diff structure at all,
constructed by a new `APPLYABLE-MALFORMED` marker in
`test/agent-loop/scripted-worker-applyable.sh`. Nothing in the worker
contract or the proposal-filing path validates a tenant's diff before
it is kept and offered for approval (verified by reading
`run_worker_turn`'s tail — the bytes in `$CASTLE_DIFF_FILE` are hashed
and sidecared as-is), so this is an ordinary approved proposal by the
time `castle apply` sees it, and its kept copy simply is not a patch.

The scenario asserts: the result carries
`apply-outcome: refused-patch-malformed`; the body does **not** contain
the string "no longer fits your configuration repository" (the exact
confusion this task removes); the body carries git's own account
(`No valid patches in input`, what `git apply --numstat -z` says about
this fixture's bytes); and the private and mechanism checkouts are
both untouched, using the same `assert_private_untouched` /
`assert_mechanism_untouched` helpers every other refusal scenario in
that file uses.

The existing stale-patch scenario ("refused: the change no longer fits
the repository") is unchanged — same fixture, same assertions, same
outcome code — because this task splits a bucket, it does not rename
one.

Human hands: none. Everything above is exercised by
`test/agent-loop/apply.sh`, which runs with no Nix, no models, and no
network.
