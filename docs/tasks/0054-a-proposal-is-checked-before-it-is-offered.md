# Task 0054 — a proposal is checked before it is offered

**Before starting:** `CLAUDE.md` in full; `docs/architecture.md`
(Records, Seats, Proposals 03–06); `docs/tasks/done/0025-approval.md`
§B (how a proposal question is filed, what `authorizes-apply` and
`proposal-sha256` mean, and why the field's absence is a positive
fact); `docs/tasks/done/0026-apply-validate.md` §C and §F (where the
applier's refusals sit, and the `outcome`-versus-its-own-field split
every seat since has reused); `docs/tasks/done/0033-byte-exact-proposal.md`
(the `.patch` sidecar these bytes become);
`docs/tasks/done/0044-mechanism-findings-not-proposals.md` §1 (the one
existing exception to "a targeted result files a question"). Then, in
`agent/castle`: `run_worker_turn`'s tail from `stamped_target` to
`_file_finding`, `_file_proposal_question`, `_write_worker_result`,
`_run_git`, `_patch_paths`, `_dirty_under`, `_checkout_fault`, and
`cmd_validate`'s `apply-outcome` block.

## The finding

On 2026-09-05 a worker filed a proposal question against a patch that
git cannot parse. The resident approved it. The applier then spent that
approval on `refused-patch-stale`, and the approval is gone — the answer
record is written, the applier consumed it, and the question is
answered.

The resident was asked to authorize a change that could never have been
made, and the cost of the malformed patch was charged to their decision
rather than to the turn that produced it.

Nothing between the worker writing the patch and the question reaching
the review screen looked at the patch. `git apply --check` would have
taken milliseconds and answered exactly the right question.

Related but distinct: task 0053 removes the cause of *this* malformed
patch by not asking a model to compose one. This task is the general
guard, and stays worth doing even after 0053 lands — a generated patch
can still fail to apply against a checkout that moved between the
worker reading it and the question being filed, and that is precisely
the case where the resident must not be asked.

## §A — the rule

**A proposal that cannot be applied does not become a question.**

At filing time, in the same seat that writes the question,
`run_worker_turn` runs the check the applier would run — `git apply
--check` against the target checkout at its current state, over the
exact bytes that become the `.patch` sidecar — and branches on the
result:

- **It applies.** The question is filed exactly as today.
- **It does not apply, and the tree is clean under the paths it
  touches.** No question is filed. The result records the refusal and
  git's own message, and routes like any other result.

The gate is the same one that decides whether a question is filed at
all: a completed turn with a diff and a resolved, non-`mechanism`
target. A mechanism-targeted diff files no question (0044 §1) and is
not checked here — it travels the outbox as a candidate patch, and
what a candidate patch is worth against a checkout this machine may
not write is a different question this task does not open.

## §B — the vocabulary, and what it depends on

A new result-record field, `proposal-outcome`, written by
`run_worker_turn` and by nothing else. It is to the PROPOSAL what
`apply-outcome` is to the change and `build-outcome` is to the build:
`outcome` stays an observation about the seat's own run
(`agent/README.md`'s reservation), and this is an observation about the
thing the run was about. Four values:

| value | question filed? | means |
| --- | --- | --- |
| `offered` | yes | git was asked and the patch applies against the target checkout as it stands. |
| `offered-tree-dirty` | yes | the patch does not apply, and the resident has uncommitted work under the files it touches, so the failure cannot be charged to the patch. |
| `offered-unchecked` | yes | git never answered — not on `PATH`, would not exec, or outlived its bound. Nothing is known about the patch either way. |
| `refused-patch-stale` | **no** | git was asked, the patch does not apply, and the tree is clean under the paths it touches. |

**`refused-patch-stale` is the applier's existing code, taken verbatim
from `APPLY_OUTCOME_VALUES` as it stands on `main`.** Today that one
code covers both halves of what `git apply` can refuse: `_apply_one`
writes it when `_patch_paths` cannot read the patch at all ("Git could
not even read the change as a patch") *and* when `git apply --check`
says it no longer fits. Task 0055 splits malformed from stale. This
task does not pre-empt that split and does not invent a third spelling:
it reuses the one code that exists, and when 0055 lands it must move
this call site with the rest, because a value in
`PROPOSAL_OUTCOME_VALUES` that no longer exists in the applier's
vocabulary is exactly the divergence this rule is written to prevent.
That is a dependency in one direction only — this task can land first
or second, and 0055's own change is where the two spellings appear.

`offered` is stamped positively rather than left as an absence.
Absence would mean both "checked and fine" and "never checked", and a
check that did not happen is the whole of this finding. Absence
therefore keeps exactly one meaning: this result comes from a turn that
filed no proposal question — a mechanism target, no diff, no clean
finish — or from before this field existed, in an append-only journal
that cannot be backfilled.

## §C — the dirty tree is advisory, not blocking

A dirty working tree can fail `git apply --check` for reasons that are
not the patch's fault, and refusing to file a question because the
resident happened to be mid-edit would be its own silence: the errand
did its work, the patch may well be perfect, and the resident would
never be shown it. So a failure that can be attributed to the
resident's own uncommitted work files the question anyway, stamped
`offered-tree-dirty`, and says so in the result body. The applier
re-checks at apply time and has its own `refused-tree-dirty` with a
remedy the resident can act on; nothing here needs to pre-empt it.

Order, and why: `git apply --check` runs first and the dirty probe runs
only if it fails. On the working path that is one git invocation rather
than three, and a patch that applies *right now* against a tree the
resident is mid-edit in is `offered` — that is the true fact, and
degrading it because a status probe found something would be reporting
a doubt the check has already resolved.

Scoped to the patch's own paths, via `_patch_paths` and `_dirty_under`,
never repo-wide: three documented private-layer layouts leave a healthy
config repo dirty, so a repo-wide probe would excuse every failure
forever (0026's reasoning, reused unchanged).

**If the dirty probe itself cannot answer, the refusal stands.** git
has already spoken about the patch; the dirty tree is the excuse, and
an excuse that cannot be established is not one. The cost of being
wrong there is an errand the resident must file again, which is the
direction this whole task chooses to fail in.

`offered-unchecked` is the other side of that coin and is deliberately
generous: when git never ran at all, nothing is known about the patch,
and refusing on the strength of a check that produced no answer would
repeat the defect at the opposite pole. `_checkout_fault` already
takes this posture by name — "when git is not on `$PATH`, this does not
refuse" — because `git` reaches a dispatched worker only through the
optional `modules/dev`, and a tenant can write a unified diff by hand
on a host that has no git anywhere.

## §D — this adds no authority

The check reads. It does not write, stage, stash, apply, or touch the
index.

- `git apply --check` is documented as making no change: it reports
  whether the patch would apply and stops. `--numstat` likewise.
- `git status --porcelain` **does** refresh the index as a side effect,
  which is why the worker contract makes every git command it permits a
  tenant carry `--no-optional-locks` (0024 §17, `docs/tasks/done/0047`'s
  allowlist). The reasoning transfers directly: this runs unattended, in
  a checkout the resident may be using, and a lock taken to write an
  index refresh is a write. `_dirty_entries` is the caller here and it
  gains `--no-optional-locks` for that reason — it is reached from the
  applier too, where the same argument holds and no behaviour depends on
  the refresh.
- Everything goes through `_run_git`/`_git_stripped_env`, so `GIT_*` is
  stripped and the resident's hooks and attributes are disabled
  (`GIT_ISOLATION_ARGS`). A hook is arbitrary code; a check that runs
  one is not a check.
- The bytes checked are a private temporary file holding `diff_bytes`,
  not the `.patch` sidecar — which does not exist yet at this point in
  the turn, since it is named after a `result_id` the record has not
  been assigned. Same snapshot idiom the applier uses, and the same
  guarantee: what was checked is exactly what the sidecar will hold.

`test/agent-loop/approval.sh`'s `assert_checkouts_untouched` runs after
every scenario and is the teeth on all of this.

## §E — what the resident sees

On a refusal the result body gains a paragraph, below the diff, saying
that nothing was filed to approve, that the change does not apply to
the named checkout, and git's own message in a fenced block. It does
not speculate about why and does not blame the tenant; a patch that
does not fit is a fact about two things, and this turn only established
one of them.

On `offered-tree-dirty` and `offered-unchecked` the body says the check
could not settle the question and the change is being offered anyway,
so a resident reading the review screen knows the pre-flight abstained
rather than passed. Neither paragraph names a file the resident is
working on: `_dirty_under` exists precisely to summarise as status
letters and a count, and this record is durable.

## §F — validation

`cmd_validate` gets the same "well-formed if present, never required"
treatment `apply-outcome` has: `proposal-outcome` is a result-record
field, and its value must be one of `PROPOSAL_OUTCOME_VALUES`. The
vocabulary is closed by construction — exactly one writer exists — so a
membership test is right here where `target`'s open non-blank check is
right there. It joins `FIELD_ORDER` beside `target`, which is the field
it qualifies.

Nothing is retro-required. Every result already in a journal validates
unchanged.

## Explicitly not in scope

**Re-opening the spent approval from 2026-09-05.** Records are
append-only and an approval that was spent stays spent. The resident
can file the request again; nothing may rewrite that history, and this
task adds no path that does.

**Validating the patch's *content*.** Whether the change is a good idea
is the resident's judgment and the reviewer's, not a check's. This task
answers one question only: can this patch be applied at all.

**Retrying, repairing or re-prompting the tenant.** A turn that
produced an unappliable patch produced one. Handing the model its own
failure and asking again is a different design with a different cost,
and 0053 is the task that reduces how often this arises at all.

**Checking mechanism-targeted diffs**, per §A.

## The fixtures this changes, and why that is not scope creep

Every tenant fixture in `test/agent-loop/` except
`scripted-worker-applyable.sh` writes a deliberately synthetic diff
naming a file that does not exist — correct for harnesses proving
nothing is ever applied, and *unappliable by construction*. With this
check in place those turns would all take the new refusal branch, and
the harnesses asserting a question is filed would fail. That is the
check working, not a reason to weaken it.

The fix keeps every diff synthetic, and takes one of three shapes
depending on what the fixture is for.

**Express it as a file creation** (`--- /dev/null`, `@@ -0,0 +1 @@`)
rather than as a modification of a file that is not there. A creation
patch applies cleanly in any checkout that does not already have the
file, which every one of these fixtures is, and it stays as invented as
it was — no fixture starts naming a real path and no harness starts
applying anything. This covers `contract-worker.sh`, the
`scripted-worker-blocking` pair (changed identically, since the whole
point of that pair is that two differently-shaped tenants produce the
same journal), and approval.sh's private-plus-finding tenant.

Verified against git 2.5x: a creation patch whose `+++` path contains
spaces (`docs/backlog/example-item (synthetic, harness fixture only)`)
still passes `--check` and still reports that whole path through
`--numstat -z`.

**Give the hunk header the file's real line numbers**, where the
fixture already diffs a file that exists.
`scripted-worker-config-target.sh` reads the checkout to decide how big
its proposal has to be — the sibling-option coupling rule — so a
creation patch would delete the point of the fixture. Its hunks said
`@@ -1,3` out of habit against content living at line 8. **git anchors a
hunk beginning at line 1 to the beginning of the file and will not
search past it**, which is why the wrong number failed outright rather
than succeeding with an offset; verified by running it.

**Grow the fixture, where the diff genuinely needs `-` lines.**
approval.sh's fenced-diff scenario asserts that all four of
`FENCED-{BEFORE,AFTER}-{INSIDE,AFTER}` survive the round trip, which a
creation patch cannot express. So that harness's private checkout gains
a synthetic `README.md` holding exactly the pre-image its diff assumes.
Still invented, still never applied.

That last fixture then does double duty: run once against a clean tree
it is the `offered` control, and run again with an uncommitted edit
under the same file it is the dirty-tree case, with nothing differing
between the two but the dirt.

## Verification plan

Fully agent-testable; no human hands. `test/agent-loop/approval.sh`
gains:

1. **A malformed-patch tenant.** A scripted tenant writing bytes git
   cannot read as a patch, targeting `private`. Asserts: no question
   record is filed for that errand; the result carries
   `proposal-outcome: refused-patch-stale`; the body carries git's own
   message; a router decision record names the result, so it routed
   like any other; `castle validate` passes; and
   `assert_checkouts_untouched`.
2. **A stale-patch tenant.** A well-formed patch against a file that is
   not in the state the patch expects — the case 0053 does not remove.
   Same assertions.
3. **The working path, unchanged.** The existing first scenario keeps
   asserting the question is filed, with its stamp, its refs and its
   `authorizes-apply` — and gains an assertion that its result carries
   `proposal-outcome: offered`. This task is a new branch, not a new
   hoop for the working path.
4. **A dirty-tree scenario.** The same well-formed patch, run with an
   uncommitted edit in place under the file it touches so the check
   fails for a reason that is not the patch's. Asserts the question
   **is** filed, that the result says `offered-tree-dirty` and not
   `refused-patch-stale`, and that the record therefore distinguishes
   "your patch is bad" from "your tree was busy". The fixture restores
   the tree afterwards so `assert_checkouts_untouched` still holds.
5. **The vocabulary.** `castle validate` refuses a hand-planted
   `proposal-outcome` on a question record, and one carrying a value
   outside the list.

The other agent-loop harnesses are the regression surface for the
fixture change and are run unchanged.
