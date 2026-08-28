# Task 0026 — An approved proposal becomes a validated private change

**Before starting:** read `CLAUDE.md` in full; both
`docs/principles/`; `docs/architecture.md` (Records, Seats — this task
adds one — Provenance, and "Where runtime state lives", especially the
standing-authority bullets); `docs/private-layer.md`'s "The agent's
state" (`:505-700`), "Two things worth repeating" (`:742-755`), "The
worker never evaluates your flake" (`:969-979`) and "Secrets"
(`:1085-1105`); `docs/tasks/0033-byte-exact-proposal.md` in full — the
artifact this task applies is 0033's, and this brief depends on that
**brief's** contracts, not on its implementation's incidental details;
`docs/tasks/0025-approval.md` §A–§C, §F–§H and its stop conditions;
`docs/tasks/0024-config-target.md` §6, §8, §9, §16;
`docs/tasks/0030-state-outside-the-flake.md` (`_state_layout_finding`
and its considered-and-rejected list, which this task makes one entry
of false); `agent/README.md` in full, especially the `outcome`
reservation at `:790-838` — this task is held to it by name — plus
"Proposing a change, and deciding it" (`:1280-1305`) and "The
byte-exact sidecar" (`:1307-1352`). Then, in `docs/backlog/`:
`env-stripping-defeats-write-guards.md`,
`record-ids-are-only-second-resolution.md`,
`where-do-host-modules-live.md`,
`approval-channel-has-no-transfer-of-control-strategy.md`,
`a-deferred-proposal-cannot-be-revisited.md`,
`stalled-mount-wedges-a-sweep.md`,
`eligibility-fold-rescans-per-request.md`.

Then, closely, the code this brief cites by line: in `agent/castle`,
`run_worker_turn`'s tail (`:4246-4547`), `_write_worker_result`
(`:3349`), `_file_proposal_question` (`:3413`), `file_answer`
(`:1434`), `write_record`'s `WORKER_CLAIM_ENV` refusal (`:1250`),
`_checkout_fault` (`:3175`), `_state_layout_finding` (`:712`),
`closing_result` (`:4640`), `_reap_interrupted` (`:4893`),
`_eligible_requests` (`:5136`), `cmd_dispatch` (`:5223`, sweep lock at
`:5295`), `_collect_downstream` (`:5537`), `cmd_validate` (`:5777`),
the lock family (`:910-1000`), `build_parser` (`:6220`); in
`agent/castle-modal`, `REVIEW_BOUNDARY_STATEMENT` (`:694`),
`REVIEW_CONFIRMATIONS` (`:1057`), `run_review_for` (`:1064`),
`_is_proposal` (`:323`), `_errand_state` (`:1308`, the decision
override at `:1537-1585`); in `modules/agent/default.nix`, the option
block (`:189-360`), the assertions (`:770-860`) and the four
`systemd.user` units (`:531-753`); and `test/agent-loop/approval.sh`
plus `config-target.sh` for the fixture conventions this task's
harness extends and, in one place, inverts.

**This branch is stacked.** `sprint/0026-apply-validate` sits on
`task/0033-byte-exact-proposal`, which sits on `sprint/0025-approval`
(PR #58). Neither is merged as this brief is written. Scope every diff
and review against `origin/task/0033-byte-exact-proposal` until 0033
lands, then against whatever it lands on. Merge order is
0025 → 0033 → 0026, and the PR description says so. Work in worktree
`ct-0026` on `sprint/0026-apply-validate`; do not touch any other
checkout.

## Why

Since `docs/tasks/0025-approval.md` a resident can authorize an exact
proposed configuration change, and since
`docs/tasks/0033-byte-exact-proposal.md` the bytes of that change
survive the journal intact. Nothing spends either. An approved
proposal is **inert by construction** — verified, not assumed:
`_eligible_requests` (`agent/castle:5136-5220`) never reads
`decision`, `proposal-sha256` or `target`; the proposal question is
never `blocking`, so `_resumable_answers` cannot admit an answer to it
(`_file_proposal_question`'s docstring states this as a structural
guarantee, `agent/castle:3428-3436`); and any result at all bars a
second automatic attempt on the request (`:5212`). The journal
therefore accumulates authorizations that nothing acts on, and
`castle-modal --mode status` says so in as many words —
`"approved — nothing applied yet"` (`agent/castle-modal:1582`), a
sentence the code itself names this task as the one that must come
back and change (`:1571-1573`, `:690-693`, `agent/README.md:1298-1302`).

This task builds the seat that spends one: an **applier** that folds
the journal for approvals carrying apply authority, verifies the
artifact it is about to use against two independent digests, applies
those exact bytes to the resident's configured private checkout,
commits them there in one commit naming the authorization, optionally
evaluates and builds the resulting host configuration, and writes one
durable record saying which of those things happened. It activates
nothing. It pushes nothing. It never touches the mechanism checkout.

It is also the first time the agent layer changes a resident's
configuration at all, which is why more than half of this brief is
about what it refuses to do and what the resident was told before they
authorized it.

### Where this task starts from

`~/castle-sprint/exhaustion/0026-decisions.md` (2026-08-17, against
post-0020 `main`) and its re-baselined successor
`~/castle-sprint/exhaustion/0026-rebaselined.md` (2026-08-26, against
0025's branch) are outside this repo; this brief cites their labels
(H1, N-3, NOW-9…) rather than re-deriving their arguments, and says so
wherever the code has since moved under one.

Six things the merged and stacked work gives this task that neither
pass could assume:

- **The byte-exact artifact exists.** H1's stop condition — "if 0024
  shipped only a fenced diff in a result body, 0026 cannot proceed
  safely" — is closed by 0033, not by this task. A completed, targeted
  turn now writes `<result-id>.patch` beside the record and stamps
  `patch-sha256` (`agent/castle:4346`, `:4543-4544`;
  `docs/tasks/0033-byte-exact-proposal.md` design items 1 and 5). The
  applier reads that sidecar and never the body's copy, which is
  explicitly decorative as of 0033. This also dissolves N-1's first
  and third consequences: there is no need to lift
  `_split_proposal_body` out of `castle-modal`, and no need to guess a
  trailing newline back onto a stripped diff.
- **`castle validate` already proves the sidecar.** A stamped record
  whose sidecar is missing or whose digest disagrees is a validation
  error today (`agent/castle:5999-6012`). The applier re-derives both
  digests itself anyway, at apply time, for `file_answer`'s own stated
  reason (`:1625-1634`): a check that re-reads from disk holds with no
  state carried between the process that displayed something and the
  process that acts on it.
- **The authorization exists and is shape-checked.** `decision` ∈
  `("approve","reject","defer")` on `answer` records, bound to the
  proposal by `refs: [question-id, result-id]` and by
  `proposal-sha256` re-derived at write time
  (`agent/castle:1613-1644`), with `cmd_validate` checking the shape
  `refs` now carries (`:6078-6090`, `:6143-6179`).
- **The two checkouts exist as roles.** `target: private` or
  `mechanism` (`agent/castle:125-146`, `agent/README.md:840-859`), a
  role and never a path, resolved per turn from
  `CASTLE_PRIVATE_ROOT`/`CASTLE_MECHANISM_ROOT`
  (`agent/castle:4466-4502`).
- **0030 moved the ground under the whole validation question.** The
  journal is no longer inside the flake repo in the recommended layout
  (`docs/private-layer.md:612-637`), `_state_layout_finding`
  (`agent/castle:712-878`) can say whether a given state directory is
  inside an evaluated flake's tracked tree, and the harnesses already
  assert repo-wide cleanliness rather than excluding `state/`
  (`test/agent-loop/config-target.sh:205-213`). Evaluating the private
  flake is defensible for the first time — see §E, and note that
  `docs/tasks/0030-state-outside-the-flake.md:411-418` records
  "nothing in the agent layer evaluates the private flake at all" as a
  *reason* for one of its own decisions. This task makes that sentence
  false, deliberately, under an option that is off by default.
- **Nothing triggers anything.** C-6 resolved: an approved proposal is
  inert, so "without resident CLI work" costs a second trigger
  mechanism. §B builds it.

### The acceptance condition, corrected before it becomes a test

`~/castle-implementation-queue.md`'s Task 6 and
`~/castle-sprint/exhaustion/codex-task-6.md` state the condition this
task is measured against. The re-baseline's §6 finds it wrong in four
places, one of them the same class of error 0024's prompt made. **The
corrected conditions below are what this brief's verification plan
tests. The original wording is not, anywhere.** A fifth correction is
this brief's own.

Original:

> after one exact proposal is approved, Castle can apply it to a
> disposable private checkout and validate the intended host
> configuration without resident CLI work; stale, unsafe, or invalid
> proposals leave the checkout unchanged or explicitly recovered, and
> the journal never claims success when validation failed.

1. **"one exact proposal" (§6a).** Corrected in this task's favour by
   0033, which the prompt could not know about: the exact artifact is
   `<result-id>.patch`, and `patch-sha256` is what makes "exact"
   checkable. The corrected condition: *the applier uses the sidecar's
   bytes, verified against `patch-sha256`, and never the record body's
   rendered copy.*
2. **"validate the intended host configuration" (§6b).** No input
   exists. Nothing declares the option path or the intended value
   (C-5 resolved NO — `$CASTLE_TARGET_FILE` holds one word,
   `agent/castle:4281-4289`), and the host attribute comes from
   `/proc/sys/kernel/hostname` (`docs/private-layer.md:957-967`),
   which is a fact about the machine running the applier rather than
   about the proposal. Corrected condition: *the applier validates
   that the configuration named by this machine's hostname evaluates
   and that its `system.build.toplevel` builds, and the record says
   plainly that nothing checked whether the change did what the
   proposal claimed.* Anything stronger would be a claim about a check
   that never ran, which is the failure `_write_worker_result`'s own
   comments already refuse twice (`agent/castle:4471-4486`).
3. **"without resident CLI work" (§6c).** Nothing triggers an apply
   today. Corrected condition: *an approval carrying apply authority
   is picked up automatically, with no resident command, on a host
   where the resident opted in — and exactly once, with a hand-run
   retry available and named.*
4. **"refuse changes outside the configured private repo" / "do not
   add public-repo self-modification" (§6d).** Collides with 0024's
   `target: mechanism`, which 0025 makes approvable and explicitly
   declines to distinguish (`docs/tasks/0025-approval.md:1087-1090`).
   Corrected condition: *an approved `target: mechanism` proposal is
   refused with its own named terminal outcome, rendered honestly, and
   the refusal decides nothing about where host modules ought to live*
   (`docs/backlog/where-do-host-modules-live.md` is still open, and
   §G says why this task must not close it by implication).
5. **"a disposable private checkout" (this brief's correction).**
   There is no disposable checkout and no mechanism to make one useful:
   a clone would have to be reconciled back into the resident's real
   tree by pushing or by replaying, and pushing is a non-goal on
   authority grounds (`docs/architecture.md:283-290`,
   `docs/private-layer.md:747-755`). SPRINT.md decision 4 authorises
   applying to the real private working tree precisely because nothing
   activates. Corrected condition: *the applier applies to the
   resident's configured private checkout, and the proof that this is
   safe is that no path anywhere in this task rebuilds or switches.*

Two things the prompt gets right and this task keeps: "do not assume
[the standing-authority] statement automatically authorizes applying
an agent-generated configuration patch; analyze the distinction and
record it" — analysed in §D — and "full build logs and progress belong
outside the durable journal", which §E honours through the spool.
One exclusion needs the re-baseline's reading note: "do not add secret
management" does not forbid *refusing* to patch `secrets.yaml` or
`.sops.yaml`; those files postdate the prompt, and refusing to patch
them is a refusal predicate, not secret management. This brief does
not build that refusal either — see Non-goals and Stop conditions for
why the allow-list is deferred rather than half-built.

## The design

### A. What authorises an apply: `authorizes-apply`, and the three sentences that change

*(Decision D2 of the owner's spec, [ADOPTED], and the sharpest
resident-facing question in the task — the re-baseline's H4 and Q3.)*

Every approval already in a journal was granted under a screen that
says, in capitals:

> NOTHING ON THIS MACHINE IS EDITED, COMMITTED, OR APPLIED BY
> APPROVING IT — no file changes, no `git commit`, no rebuild, no new
> generation. (`agent/castle-modal:698-700`)

An applier that spends those approvals spends an authorization whose
stated scope was "nothing is edited." **It may not.** Changing what a
resident was told at the moment they granted authority changes what
the authority was, and no amount of updating the wording afterwards
reaches backwards.

The mechanism is a new frontmatter field on the proposal **question**,
stamped by the harness at filing time:

```python
# The field that says this proposed change, if approved, carries
# authority to APPLY it (docs/tasks/0026-apply-validate.md §A).
# Stamped by `_file_proposal_question` on every proposal it files from
# this task onward, and by nothing else.
#
# It exists because the sentence a resident read while deciding is the
# scope of what they decided. Every proposal filed before this task
# was decided under a screen saying in capitals that approving edits
# nothing, so approving one authorized a record and nothing more, and
# no later change to that wording reaches backwards. Absence is
# therefore not "unknown": it is the positive fact that this proposal
# was offered under the older, narrower statement.
#
# Drawing the line by comparing timestamps against the commit that
# changed the wording would be wrong twice over: record ids are
# one-second resolution
# (docs/backlog/record-ids-are-only-second-resolution.md), and a
# restored or synced journal has no defensible relationship between
# its stamps and this repo's history. The field travels with the
# record that was shown.
#
# Literal "true", the only spelling, following BLOCKING_FIELD's
# reasoning exactly: absence means no, an unrecognised value means no,
# and `cmd_validate` names any other spelling rather than letting it
# sit there looking meaningful.
AUTHORIZES_APPLY_FIELD = "authorizes-apply"
```

`_file_proposal_question` (`agent/castle:3413`) stamps it beside
`proposal-sha256`, unconditionally, on every proposal question it
files. Added to `FIELD_ORDER` beside `blocking` for the same
presentation-only reason every other addition there gives.

**The applier honours only decisions whose question carries it.** Old
approvals are inert by construction: no migration, no backfill, no
timestamp arithmetic, and — because the journal is append-only —
nothing that could ever make them applyable later. That is the point.

**Three resident-facing surfaces change, in this commit, and their
replacement text is written here rather than left to the implementer.**
Authority wording is not something to improvise.

**A.1 — `REVIEW_BOUNDARY_STATEMENT` (`agent/castle-modal:694-704`).**
Split into two constants, selected by whether the question being
decided carries `authorizes-apply`. The new text is used for
field-carrying proposals; the existing text is preserved verbatim as
`REVIEW_BOUNDARY_STATEMENT_PRE_APPLY` and used for a proposal filed
before this task, because for those it remains exactly true.

```
Approving this is you authorizing this exact change, and that
authorization is kept.

APPROVING IT AUTHORIZES CASTLE TO MAKE THIS CHANGE IN YOUR
CONFIGURATION REPOSITORY — to edit those files and commit them there,
on your say-so, without asking again. It pushes nothing anywhere.

NOTHING IS ACTIVATED AND NOTHING IS REBUILT: no new generation, and no
change to the machine you are using right now. Switching to the new
configuration stays yours to do, by hand.

Rejecting says this change is wrong. Setting it aside says you are not
deciding it now. Both close it for good — nothing expires, and nothing
decides on your behalf.
```

Four decisions inside that text, each deliberate:

- **"authorizes Castle to make", not "makes".** Whether the change is
  applied promptly depends on `castle.agent.apply.enable` (§K), which
  is off by default. A screen that predicted an application that never
  happens would be 0015's defect — a label causing the inaction it
  describes — and one that predicted it correctly on some hosts and
  not others would be worse. What approving *is* does not vary: it is
  the authorization. The applier's own record (§F) reports what then
  happened.
- **It does not promise a check.** Validation is gated by a second
  option that is also off by default (§E). Promising "and then checks
  it builds" on a screen that cannot know whether that option is set
  would be the same overclaim in a smaller font. The check, when it
  runs, is reported afterwards by the thing that ran it.
- **"without asking again"** is there because there is no second
  confirmation keypress (0025 §G left that open as S8, and this task
  does not close it — see Stop conditions). A resident should learn
  that from the screen, not from the consequence.
- **"It pushes nothing anywhere"** because "commit" is the word most
  likely to be read as "publish", and pushing is an open authority
  question this task does not touch
  (`docs/architecture.md:283-290`).

**A.2 — `REVIEW_CONFIRMATIONS` (`agent/castle-modal:1057-1061`).** The
re-baseline's H4 names this as the third surface the code's own
"exactly two places" comment misses. `approve` becomes a two-way
choice on the same predicate; `reject` and `defer` are untouched:

- field-carrying: `"Approved. Castle will make this change in your
  configuration repository. Nothing will be activated."`
- pre-field: `"Approved."` (unchanged)

Implemented as a small helper rather than a second dict, so the
predicate is spelled once: `_review_confirmation(decision, *,
authorizes_apply)`.

**A.3 — `_errand_state`'s decision label
(`agent/castle-modal:1581-1585`).** Covered in §H, because it now has
a fourth stage to fold in as well.

**Where the predicate lives.** `_is_proposal` (`agent/castle-modal:323`)
already exists and keys on `PROPOSAL_SHA256_FIELD`; it stays exactly
as it is — pendingness, picker routing and the review branch must not
change, because a pre-field proposal is still a proposal and still
gets decided. A second, separate helper `_authorizes_apply(castle,
question)` keys on the new field, and is used only by the two wording
choices above. Two predicates, two jobs, no widening of either.

### B. The applier: seat, invocable, lock, fold, trigger

*(Decision D4, [ADOPTED default] — with one factual correction to the
mechanism it names, argued below.)*

**Seat: `applier`.** A new value in an existing category, not a new
category, exactly as `seat: dispatch` was
(`docs/architecture.md:217-219`). Not `worker`: 0025 gave the proposal
question `seat: worker` on "a seat is what reads and writes"
reasoning (`agent/README.md:1223-1225`), and an applier reads and
writes a different set — it reads decisions and sidecars, it writes a
resident's checkout. Keeping the two names distinct is what lets a
reader ask "which seat touched my repository" and get an answer.
Like dispatch, it is plumbing rather than a reasoning seat: what it
does is a total function of the journal and the tree, it holds no
judgment, and giving it one — a policy about which approvals are worth
applying, or whether to apply one at all — is precisely what
`docs/architecture.md`'s Seats section must be extended to forbid.

**Invocable: `castle apply`.** A new subcommand in the one stdlib
file, per NOW-3 and 0021's own precedent (ten subcommands,
`agent/castle:6224-6288`), not a separately installed binary.

```
castle apply <answer-id>     apply one approved change, by hand
castle apply --sweep         apply every eligible approved change
```

Exactly one of the two forms; argparse enforces it. The pair mirrors
`castle work <id>` / `castle dispatch` deliberately: the id form is
the hand-retry path and is *not* bounded by the one-attempt rule
(`cmd_work`'s own comment, `agent/castle:4566-4570`, says re-running
by hand IS the retry path), and the sweep form is the automatic one
and is.

**The exit codes, which this brief did not specify and the
implementation had to choose.** The two forms get different contracts,
for the same reason their bounds differ. `castle apply --sweep` keeps
`castle dispatch`'s: 0 whenever the sweep ran and recorded outcomes for
whatever it found, with refusals visible in records rather than in the
exit code, so the unit's failed state keeps meaning "the mechanism
broke." `castle apply <answer-id>` exits 0 only for `applied-validated`
and `applied-unvalidated` — a human typing it is asking "did my change
land, and is it all right?", and the shell's status is where they read
the answer — and 1 for a refusal, a failed check, an uncommitted apply
or an environment fault.

**And two more things the sweep does that this brief did not say.**

*It aborts on the first environment fault* rather than continuing,
raising after the record is written, exactly as `TenantNotRunnable`
does for a sweep of errands and for a sharper version of its reason. A
misconfigured `CASTLE_PRIVATE_ROOT` is the same for every eligible
approval, and any result at all bars a second automatic attempt (the
fold below) — so a sweep that shrugged and carried on would burn every
resident authorization in the journal on `failed` records in a single
pass. An authorization is costlier and less repeatable than an errand's
automatic attempt, which is the whole argument §K makes for the second
assertion; the abort is that argument applied at runtime.

*It routes once at the end*, the same tail step `cmd_dispatch` runs and
via the same `route_journal()` fold, when it applied anything. Without
it, §F's stated intent — "the resident authorized something, and the
push channel is how they learn what happened to it" — is only true on a
host that also enabled dispatch, since nothing else would ever route
the apply's result. The hand path deliberately does **not** route,
exactly as `castle work` does not: a human at a terminal can see what
happened, and `castle route` is one command away. Lock ordering is
unaffected — nothing takes `apply.lock` while holding the router's, so
`apply.lock -> route.lock` closes no cycle.

**The argument is the answer id, not the question id.** The
authorization is the answer; the question is a proposal, which
authorizes nothing on its own. Naming the thing being spent is the
same discipline `refs` already follows.

**Lock: `apply.lock`**, via a new `apply_lock_path()` beside
`route_lock_path`/`dispatch_lock_path`/`spend_lock_path`
(`agent/castle:969-1000`), acquired non-blockingly with the existing
`acquire_lock` helper. One applier at a time, globally, because they
would all be writing one checkout. It is **not** the dispatch sweep
lock and is never taken together with it.

**Eligibility fold: `_eligible_approvals(records)`.** An `answer`
record is eligible iff:

1. `decision == "approve"`;
2. `refs[0]` resolves to a `question` carrying
   `authorizes-apply: true` (§A) and `proposal-sha256`;
3. `refs[1]` resolves to a `result` — the same shape `cmd_validate`
   already checks (`agent/castle:6150-6161`);
4. **no `result` record names this answer id in its `refs`.** Any
   apply result at all, of any outcome, bars a second automatic
   attempt — structurally the same bound `_requests_with_results`
   gives a request (`agent/castle:4717-4721`), and for the same
   reason: a bound expressed as "does a record exist" cannot be reset
   by anything but writing history.

Sorted oldest-id-first, like every other fold here.

**Cost, stated because the neighbouring fold's cost is a filed
backlog entry.** This is a single flat pass: one sweep over
`records.values()` builds the set of answer ids named by any result's
refs, then one filter over answers. It is O(records), not
requests × records — it does not inherit
`docs/backlog/eligibility-fold-rescans-per-request.md`'s 117 ms
measurement, and the implementer must not write it as a per-answer
rescan.

**Trigger, and where this brief argues with its own spec.** D4 says
automatic triggering is achieved "by the dispatch sweep NOTICING
eligible approved work and invoking the applier as a detached unit,
**the same pattern dispatch already uses for worker turns**", and
invites the brief writer to say so if that proves incoherent against
the code. It does. **Dispatch does not invoke worker turns as detached
units.** `cmd_dispatch` calls `run_worker_turn` in-process, inside the
loop, while holding the global sweep lock (`agent/castle:5295-5314`,
`:5397-5417`); the tenant is a `Popen` child in its own process
*group* (`start_new_session=True`, `:4108`) but inside the sweep's own
lifetime and cgroup. There is no detached-unit pattern to copy — and
one would not work if there were: `castle-dispatch` is `Type =
"oneshot"` (`modules/agent/default.nix:589`), so systemd tears down
the unit's cgroup when `ExecStart` returns, taking any still-running
descendant with it.

The smallest honest alternative, and what this brief specifies:
**the applier gets its own three systemd user units, watching the same
journal directory, and `cmd_dispatch` is not modified at all.**

```
systemd.user.paths.castle-apply       PathChanged = <stateDir>/journal
systemd.user.services.castle-apply    Type = oneshot; castle apply --sweep
systemd.user.timers.castle-apply      OnStartupSec = 15s; OnUnitActiveSec = 1min
```

modelled line-for-line on the dispatch trio (`modules/agent/default.
nix:531-693`), including `ConditionUser = "!@system"`, no
`wantedBy` on the service, `WorkingDirectory = "%h"`, and the same
`environment` treatment (the unit-level option, never a raw
`serviceConfig.Environment` list, for the whitespace-splitting reason
that block documents at `:613-629`). No watermark unit: the applier
needs no boundary, because its bound is per-answer and an answer that
predates this task lacks `authorizes-apply` and is invisible to the
fold anyway.

This is *more* faithful to D4's principle than D4's own mechanism —
its own lock, its own fold, nothing under the sweep lock — and it
buys three things the in-sweep version cannot:

- A slow validation (§E permits up to thirty minutes) cannot wedge
  dispatch. Under D4's mechanism, or under any in-process variant, a
  `nix build` either holds the global sweep lock —
  `docs/backlog/stalled-mount-wedges-a-sweep.md`'s hazard escalated
  from "one errand hangs" to "the whole mechanism stops, silently" —
  or holds the dispatch *unit* busy, which stops the next sweep at the
  systemd level even with the lock free.
- Dispatch learns nothing about applies. Its eligibility fold, its
  one-attempt bound, and its "the wakeup is a hint, the fold is the
  authority" doctrine are untouched; the second watcher on the same
  directory is that doctrine applied twice rather than bent once.
- `castle dispatch`'s exit-code contract keeps meaning what it means.
  An apply refusal is not a dispatch mechanism fault, and folding one
  into that unit's health signal would blur the one signal a resident
  is asked to trust.

The cost is stated rather than hidden: three more units in
`modules/agent/default.nix`, and a second thing to turn on.

**The interleaving with a live worker turn.** A worker tenant reads
the private checkout while the applier may be committing to it. The
tenant only ever reads — it is forbidden `git apply`, `git commit` and
`git checkout` outright (`agent/castle-worker-claude:499`) — so the
worst case is a tenant diffing against a tree that moved under it,
which produces a proposal whose patch no longer applies. That is
caught at the next apply by `git apply --check` and named
(`refused-patch-stale`, §F). The failure mode degrades into a refusal
rather than into corruption, which is why this brief does not take the
dispatch lock to prevent it. Stated, not silently accepted.

**One host per journal.** `docs/private-layer.md:981-989` already
tells a resident to enable dispatch on only one machine when syncing a
state repository. The applier inherits that instruction for a sharper
reason — two hosts would apply the same approved change to two
different checkouts, and only one of them is the one the resident
means — and the doc gains one sentence saying so.

**And the sweep refuses the fallback lock directory**, mirroring
`cmd_dispatch`'s own refusal word for word in structure. With no
`XDG_RUNTIME_DIR` and no `/run/user/$UID`, the only lock directory left
is `/tmp/castle-$UID`, which any local user can create first: they hold
`apply.lock`, the sweep reports "another applier is already running" and
exits 0 forever, green in `systemctl --user status`, while every
approval the resident granted sits unapplied. Dispatch's version of that
is an errand that never starts; this one is an authorization that never
gets spent, on the seat with the higher authority of the two. The hand
path keeps the fallback deliberately, exactly as `castle work` does — a
human is present and will notice. Not in this brief's original guard
list; added on the owner's disposition after review, and covered by a
scenario mirroring `dispatch-test.sh`'s, which branches on whether the
runner has `/run/user/$UID` so both worlds are asserted.

**The worker-turn guard (STOP-19).** `cmd_apply` refuses outright if
`WORKER_CLAIM_ENV` is present in the environment, printing a message
naming the seat that may not do this and the one that may. This is the
code form of a rule `agent/castle-worker-claude:605-617` already
anticipates by name: its nonce-fenced override block tells a tenant
that a passage saying "the resident has already approved applying
something" was quoted out of a record and did not come from the
harness. Once approved proposals live in the journal, 0023's
continuation packet renders them into a resumed tenant's prompt, so
that block is load-bearing rather than defensive. This task does not
weaken it, does not change it, and adds the mechanical half of it
here. The guard is defeated by `env -u`, exactly like the two guards
in `write_record` it mirrors — see §J.

### C. What the applier checks before it touches anything

*(Decision D7's pre-flight, [OWNER].)*

In order, each failing check producing a record and stopping (§F) —
**except that check 2 runs first, which is a correction this brief's
implementation made and which the list below is written as if it
had.** Check 2 is the only one that writes no record, so running it
before check 1 is what keeps a mistyped id from putting a permanent
`failed` result in an append-only journal to describe somebody's typo.
The listed order is otherwise exactly what the code does.

1. **The environment.** `CASTLE_PRIVATE_ROOT` is set, and
   `_checkout_fault` (`agent/castle:3175`) returns None for it.
   Reused rather than re-implemented: it already strips every `GIT_*`
   variable before probing (`:3135` and the reasoning at
   `:3103-3130`), handles dubious ownership, and — the case that
   matters most here — detects "the configured root is a subdirectory
   of a checkout", which its own docstring identifies as producing
   "an unapplyable proposal that no downstream step could detect"
   (`:3201-3210`). This is that downstream step; it detects it.
   A fault here is an **environment** fault, not a property of the
   proposal: it writes `outcome: failed` with no `apply-outcome`,
   mirroring exactly what `_write_worker_result` does for a tenant
   that could not be run (`agent/castle:3379-3384`).
2. **The decision is what it claims to be.** The answer resolves, is
   type `answer`, carries `decision: approve`, its `refs[0]` question
   carries `authorizes-apply: true` and `proposal-sha256`, its
   `refs[1]` result resolves. On the hand-run path these produce a
   plain CLI refusal with no record written — a mistyped id is not an
   event the journal needs an opinion about. On the sweep path they
   cannot fire: the fold already required them.
3. **`proposal-sha256` still matches.** Re-derived from the result
   file's bytes on disk, right now, compared against the **answer's**
   stamp (not the question's — the answer's is the value that was
   verified at the moment authority was granted, and
   `file_answer:1641-1644` only writes it after it matched). A
   mismatch means the record changed after it was authorized:
   `refused-artifact-changed`.
4. **The sidecar exists and matches `patch-sha256`.** Absent field or
   absent file: `refused-no-patch`. This is N-1's live consequence and
   it needs a name rather than an exception — a result carrying no
   diff boundary and no sidecar is approvable today (0025's review
   surface renders such a body whole, deliberately,
   `agent/README.md:1194-1198`), so an authorization can legitimately
   resolve to no bytes. Digest mismatch: `refused-artifact-changed`.
   Note the division of labour with 0033: `cmd_validate` proves the
   pair for the whole journal on demand; the applier proves it again
   for the one record it is about to act on, because "validate was run
   at some point" is not the same claim.
5. **`target` says `private`.** The literal `mechanism` gets
   `refused-target-mechanism` (§G). No third value is reachable: a
   result with no `target` never produced a proposal question at all
   (`_file_proposal_question` runs only under `if stamped_target:`,
   `agent/castle:4545-4546`), and an unresolvable role is discarded
   before it is stamped (`:4470-4496`). So a third value is not given
   a fifth refusal it would never earn — it produces `outcome: failed`
   with no `apply-outcome` and a body saying the field named a role
   this applier has no checkout for, the same posture one layer down
   as the worker's own refusal to record an unresolvable role.
6. **The tree is clean under the paths the patch touches.**
   `git -C <root> apply --numstat -z -- <sidecar>` is git's own patch
   parser and touches nothing; it yields the paths. **Read as bytes and
   decoded with `surrogateescape`**, which the brief did not say and
   Codex's review found the cost of: `text=True, errors="replace"`
   turned any byte that is not valid UTF-8 into U+FFFD, in the one
   function that chose `-z` specifically so as not to mangle a name, so
   the dirty check inspected a path that does not exist and the pathspec
   commit failed *after* the tree had been modified. `surrogateescape`
   round-trips the original bytes back into git's argument list. Its
   cost is that these strings are not safe to render — a lone surrogate
   makes `write_text` raise, and records are UTF-8 by definition — so
   every point where a path reaches a record, a message or a
   notification sanitises it for display first while git keeps the real
   value. **And every pathspec is `:(literal)`**, because `--` ends
   options without stopping git reading what follows as a *pattern*: a
   resident's file named `weird*.nix` would otherwise glob-match others.
   Every traced shape failed safe, which is not a property to leave
   resting on luck. Then
   `git -C <root> status --porcelain -- <those paths>` must be empty.
   Non-empty: `refused-tree-dirty`, with the offending paths' *status
   letters and count* in the body but not their names — a private
   checkout's file names are resident data, and the record is durable
   (see Hard constraints). The resident's own `git status` tells them
   which files; this record tells them that it did not overwrite their
   work.

   **Scoped to the patch's paths, not repo-wide**, and NOW-9's own
   re-baselined argument is why: three documented layouts make a
   repo-wide clean check fire on residents who did nothing wrong — a
   `state/` submodule dirties the outer gitlink on every journal
   commit (`docs/private-layer.md:639-656`), an un-gitignored
   `key.txt` shows as untracked (`:1166-1167`), and the "set nothing"
   fallback leaves cleanliness unrelated to anything (`:677-684`). A
   check that refuses forever on a supported layout is worse than no
   check.
7. **`git apply --check`.** Fails: `refused-patch-stale`, with git's
   own stderr (bounded, §F) in the body. **No fuzz, ever** — no
   `-3`, no `--recount`, no `patch(1)` fallback. A patch that does not
   apply exactly is not the change the resident approved, and a
   three-way merge would produce a change nobody authorized. This is
   also what stands in for NOW-8's absent `repo-head` stamp: C-4
   resolved NO, nothing records the checkout's rev at proposal time,
   so "has the tree moved since approval" is answerable only by
   asking git whether the patch still fits. This brief does **not**
   add a `repo-head` stamp to 0024's writer; see Considered and
   rejected.

### D. How the change lands, and the authority it is spent against

*(Decision D7, [OWNER], with SPRINT.md decision 4's hardware
boundary.)*

**Working-tree edit plus exactly one commit, on the private repo's
current branch, no push, ever.**

```
git -C <root> apply -- <sidecar>                       # working tree
git -C <root> add -N -- <paths>                        # created files only
git -C <root> -c user.name=... -c user.email=... \
    commit -m <message> -- <paths>                     # exactly those paths
```

Every subprocess runs with `GIT_*` stripped from the environment, the
same blanket `_state_tracked_in` applies for the same reason
(`agent/castle:680-687`): git reads that environment to decide what a
repository even is.

- **The resident's git hooks do not run**, and this was missing from
  this brief until code review reproduced what it costs. Every git
  invocation carries `-c core.hooksPath=/dev/null`, and the commit adds
  `--no-verify`. Both are needed: `--no-verify` skips `pre-commit` and
  `commit-msg` only, and `core.hooksPath` is what stops `post-commit`.
  An ordinary formatting `pre-commit` rewrote the committed bytes, so
  the commit whose message asserts `patch-sha256` did not contain the
  bytes that digest describes — the audit chain this whole design rides
  on, broken silently. A `post-commit` hook is worse in a different
  direction: it can commit again, so `rev-parse HEAD` afterwards names a
  commit the applier never made, and the record's own `git revert <sha>`
  then reverts the hook's work while leaving the approved change in
  place. It also closes a hole the subprocess timeout cannot, since that
  kills only the direct child and a daemonising hook outlives it.
  `/dev/null` is the hooks path deliberately: any real directory has to
  exist and be trusted, and one under the runtime dir would be
  world-writable on the `/tmp` fallback — replacing the resident's hooks
  with an attacker's. `/dev/null` can never be a directory. The
  resident's hooks still run on the commits they make themselves.
- **And what landed is verified, not assumed.** After the commit
  reports success: `HEAD`'s parent is where this started, exactly one
  commit separates them, and the patch's paths are clean. Only then is
  the sha taken and printed. If any of the three fails the record is
  `outcome: failed` with no `apply-outcome` and **no sha at all** — a
  record naming an unverified commit beside a `git revert` is worse than
  one naming none.
- **`-c user.name`/`-c user.email` rather than writing config.**
  Nothing this task does may modify the resident's `.git/config`. The
  identity is `Castle applier <applier@castle.invalid>` — `.invalid`
  is reserved by RFC 2606 and can never be a real address, and the
  name is the seat, so `git log` answers "who made this commit" with
  the seat vocabulary rather than with a person.
- **`commit -- <paths>` and not a bare `commit`.** A bare commit
  sweeps in whatever the resident had staged. A pathspec commit builds
  a temporary index from HEAD plus those paths' working-tree content
  and leaves the index alone, so the commit contains exactly the
  patch's paths and the resident's staged work is neither committed
  nor lost.
- **`git add -N` for created files** so a pathspec commit can name
  them at all. On already-tracked paths it is a no-op.
- **The message names the authorization**, and only ids:

  ```
  castle: apply an approved change

  errand:   <request-id>
  change:   <question-id>
  decision: <answer-id>
  proposal: <result-id>
  patch-sha256: <digest>

  Applied by `castle apply` on the resident's recorded approval
  (docs/tasks/0026-apply-validate.md). Nothing was activated: no
  nixos-rebuild, no switch, no new generation.
  ```

  No paths, no prose from the tenant, nothing that could be resident
  data. The digest is what makes the commit checkable against the
  journal years later with no tooling.

**The authority analysis Codex asks for, recorded.**
`docs/architecture.md:279-281` calls the agent committing to the
private repo a **standing authority**. **This task does not rely on
that sentence**, for two reasons. It has been scoped away from the
repository this task patches: `docs/private-layer.md:742-755`
restates both consequences as holding "for whichever repository ends
up holding `state/`", which under the recommended sibling layout
(`:612-637`) is a *different* repository from the config repo — the
only document that scopes the standing authority scopes it elsewhere.
And, sufficient on its own, every commit this task makes is
authorized *individually*, by a specific answer record the commit
message names, under a screen that says in capitals what approving
authorizes (§A). A per-change authorization needs no standing one.
That is the analysed distinction, and it is why this task amends
neither `docs/architecture.md`'s authority bullets nor the
authority-taxonomy work (the re-baseline's STOP-13 is aimed at the
wrong words; the scoping already happened one document over).

**Why a commit rather than a working-tree edit** — reversing NOW-1's
re-baselined default, which leaned "working tree, `git add -N`, no
commit" and rested half its case on `REVIEW_BOUNDARY_STATEMENT` saying
approving commits nothing. §A changes that statement in the same
commit, with the resident told before they decide, which removes the
half of NOW-1's argument that was about what the resident was
promised. What remains argues *for* the commit:

- **Validation is meaningless without it.** A plain path flakeref
  evaluates the tracked tree; an untracked new file is simply not
  there, so a configuration with the change missing would evaluate
  green and the record would report a check that examined the wrong
  thing (`docs/private-layer.md:593-601`, and the `path:`-scheme
  exception it names is the only way round, which would mean
  evaluating an archive nobody will build). A committed tree is
  unambiguously the thing `nixos-rebuild --flake <root>#host` would
  build.
- **The commit is the recovery mechanism.** Codex's "unchanged or
  explicitly recovered" is satisfied by a change that is one
  `git revert` away and named as such in the record, far better than
  by a tree in an in-between state with no name.
- **A commit is legible cold.** `git log` becomes the second, tool-
  free account of what the agent layer did to a resident's
  configuration — the same property the journal exists for, in the
  repository the change actually lives in.

**What happens when the commit fails after the patch applied.** The
working tree carries the change and the repository does not. This is a
real state and it gets a real name (`applied-uncommitted`, §F) with
`outcome: failed`, plus a body giving the commands that resolve it in
either direction. It is not rolled back: see the next paragraph.

**Those commands are rendered per path shape, and the brief's original
"both recovery commands" was wrong about one of them.** Code review ran
what this used to print — `git checkout -- .` — and found it actively
harmful for two of the three shapes: on a path the change *created*,
`git add -N` has already put an intent-to-add entry in the index, so
`checkout` restores the file from that entry's **empty blob** and
leaves it on disk with its contents destroyed, reporting success; and
on a path the change *deleted*, it leaves the deletion staged in the
index for the resident's next commit to pick up. It was also repo-wide,
which the dirty check is deliberately not. So: `git reset` over the
patch's paths first (the index is what `add -N` touched), then
`git checkout --` for paths that existed before and `rm -f --` for ones
the change created — path-scoped throughout, never `.`. Distinguishing
the two needs one `git ls-files` **before** the patch is applied, since
the numstat data cannot tell a creation from an append to an empty
file; when that could not be asked, the record prints no command and
says so rather than printing the half that destroys work.

**Nothing is ever rolled back, and this is a decision.** No `git reset
--hard`, no `git checkout --`, no auto-revert of a committed change
whose validation failed. Three reasons. A hard reset destroys any
uncommitted work in the tree that the applier did not put there, and
the applier's dirty check is scoped to the patch's paths (§C.6), so
there provably may be such work. The resident owns the configuration
(Principle 02); silently rewinding their repository's history is a
larger authority than adding one commit they authorized. And nothing
is activated, so a bad commit is inert until the resident's own
`nixos-rebuild`, which would fail in exactly the same way and tell
them so. "Explicitly recovered" is honoured by naming the commit and
the command, not by acting again unbidden.

### E. Validation: the gate, the command, the bound

*(Decisions D1 [HUMAN] and D8 [OWNER].)*

**This is the first thing in the agent layer that evaluates a
resident's flake, and it is off by default.**

```nix
castle.agent.apply.evaluateFlake = lib.mkOption {
  type = lib.types.bool;
  default = false;
  ...
};
```

Named for evaluation and not for "validation" generally, per D1, so
what is being authorised is legible in the option name itself. Wired
to `CASTLE_APPLY_EVALUATE_FLAKE`.

Four conditions, all required, before `nix` is invoked at all — the
brief specified three, and code review found the fourth by running it:

1. **The option is on.** Absent or unset means no evaluation, no
   subprocess, and an `applied-unvalidated` outcome whose body says
   which option would turn it on.
2. **`_state_layout_finding(state_dir())` returns None**
   (`agent/castle:712`). If the state directory sits inside an
   evaluated flake's tracked tree, evaluating that flake publishes the
   resident's whole decision history to the world-readable store —
   and unlike `nixos-rebuild`, *this tool* would be the one causing
   it. Refuse to evaluate, quote the finding verbatim, and name
   `docs/private-layer.md`'s "Migrating state out of the flake" — the
   same three-stage remedy 0030 shipped. Outcome:
   `applied-unvalidated`. The apply itself still happens; the gate is
   on evaluation, which is the only thing that copies anything.
3. **The private root's own path can be a flakeref.** A path flakeref
   splits its attribute path at `#` and its query at `?`, so a checkout
   whose path contains either makes `nix` resolve a shorter, wrong
   directory. Verified against nix 2.34: it does not fail as a
   malformed argument, it fails as "getting status of … No such file or
   directory" — which arrived here as a nonzero exit and was recorded
   as `validation-failed`, *a false claim that the resident's
   configuration no longer builds*. There is no escaping rule for these
   in a path flakeref, which is why this is a skip rather than
   something to quote around: outcome `applied-unvalidated`, body
   naming the character, and — unlike the other three skips — **no
   command line printed**, because there is no command to print and
   printing the one that cannot work would be the record recommending
   what produced the wrong answer.
4. **`nix` is on `$PATH`.** `shutil.which("nix")` — a host running the
   agent layer without `modules/dev` genuinely has none, exactly as
   `_checkout_fault` documents for `git` (`agent/castle:3212-3221`).
   Absent: `applied-unvalidated`, body saying so. No refusal, no
   crash.

**`_state_layout_finding`'s docstring must be amended in this commit.**
It currently ends "Advisory only. It reports; it never refuses"
(`agent/castle:818-821`), and its argument for that is explicitly
about `validate` and `digest` — "the store copy is made by
`nixos-rebuild`, not by this tool, so refusing would prevent
nothing." At this new call site refusing prevents exactly the thing
the check is about. The docstring gains a paragraph scoping its own
claim to those two callers and naming this one as the case where the
finding is a gate; `docs/private-layer.md:725-730`'s matching sentence
gets the same treatment.

**The command (D8):**

```
nix build --no-link --no-write-lock-file --no-update-lock-file \
    <private-root>#nixosConfigurations.<host>.config.system.build.toplevel
```

- `<host>` from `/proc/sys/kernel/hostname`, the rule 0024 §9 decided
  and `docs/tasks/0024-config-target.md:856-864` explicitly forbids
  turning into an option ("Do not pre-build that option now"). This
  brief does not add one. The record states the hostname it used and
  states that this is a fact about the machine that ran the applier,
  not about the proposal — the honest form of §6b's correction, and
  the concrete shape of N-7's second gap.
- `--no-write-lock-file --no-update-lock-file` are **mandatory, not
  stylistic**: 0024 verified by running it that a bare evaluation of a
  path flake creates or updates `flake.lock` in that directory
  (`docs/tasks/0024-config-target.md:915-923`), and `flake.lock` is
  the audit artifact Principle 02 consequence 3 names. A validator
  that silently updated a resident's lock would be making an
  unauthorized change while checking an authorized one.
- `--no-link`: no `result` symlink, no GC root, nothing left in the
  checkout.
- **Never `nix flake check`** on a resident's flake: it builds every
  resident-authored `checks` output, which is unbounded work this task
  never asked for.
- **Never as root, never `sudo`.** Verified possible: sops-nix's
  evaluation-time check needs the sops file to exist and be readable
  and its build-time `checkPhase` runs `sops-install-secrets
  -check-mode=sopsfile`, and *neither needs the private key*
  (`flake.nix:137-152`,
  `docs/tasks/0031-secrets-tooling.md:1027-1040`). An unprivileged
  applier can evaluate and build a secrets-bearing configuration; what
  it can never confirm is that decryption would succeed, and the
  record must not imply otherwise.

**The bound.** `castle.agent.apply.timeoutSeconds`, positive int,
default **1800**, wired to `CASTLE_APPLY_TIMEOUT` and parsed by a
helper written in `worker_timeout_seconds`'s exact shape
(`agent/castle:2793-2820`: warn on stderr, fall back, never refuse to
work). Thirty minutes is chosen, not derived, and the reasoning is in
the option's own description: the worker's 900s bounds a *model call*,
while this bounds a *build*, and the one Nix-capable host this ever
runs on is the resident's laptop
(`docs/backlog/no-build-host-but-the-target.md:3-7`), which may
legitimately compile a kernel. On timeout, the whole process group is
killed with the existing `_kill_tenant_group` (`agent/castle:2704`) —
`nix build` spawns builders, and killing only the parent leaves them —
and the record carries `outcome: timeout` with
`apply-outcome: validation-failed`.

**Output, and the spool.** Combined stdout+stderr is captured. The
**last 40 lines** go into the record body inside a fence. Forty is a
chosen bound: about a screen, which is what a resident reading a
notification or a digest can absorb, and Nix puts the failing
derivation and its final log lines at the end. The **full** output is
written best-effort to `spool_dir()/apply-<answer-id>.log`, which is
the named answer to Codex's "full build logs and progress belong
outside the durable journal" — the spool is ephemeral, under
`$XDG_RUNTIME_DIR` (`agent/castle:943-947`), and the body names the
file. A failure writing the spool copy is printed and ignored; it is
never the reason an apply is reported as failed.

**The exact command is always recorded**, on its own line in the body,
shell-quoted, whether it ran or not. When the gate is off, the body
says "evaluation is off; the check that would have run is:" and gives
the same line. This is the dry-run seam (§Verification): it makes the
argv assertable with no new environment variable and no injection
point that could drift from what production does, and it gives the
resident the one command they can paste to check it themselves.

**"Validated" in this task's title means exactly two things**: the
flake evaluates, and `system.build.toplevel` builds. It does not mean
the change did what the proposal claimed (no input exists — §6b), it
does not mean secrets will decrypt, and it does not mean the
configuration will activate. `dry-activate` and everything
activation-adjacent is 0027's (Non-goals).

**The worker's never-evaluates rule is untouched, and this is a
different seat.** `docs/private-layer.md:969-979` is a promise about
the *worker*: it reads files, it never evaluates, and the cost is that
it asks rather than guessing where reading and evaluating could
differ. Nothing in this task changes that, and
`agent/castle-worker-claude`'s forbidden list keeps `nix eval`
(`:371-376`). What the applier does is a different act by a different
seat at a different moment: after a resident authorized a specific
change, on a machine whose own `nixos-rebuild` already publishes the
same tree. The parenthetical at `docs/private-layer.md:975-979` says
this in the doc's own voice — the rule is "the other half of the same
defence" against a store copy the resident's own rebuild makes anyway
— which is what makes it defence-in-depth for non-recommended layouts
rather than the primary defence. The primary defence is 0030's layout
rule, and condition 2 above is that rule enforced at the moment it
would matter.

### F. What an apply writes: one `result` record

*(Decision D6, [OWNER, mechanical] — and the one place D6 explicitly
defers to what `agent/README.md` actually says.)*

**No new record type.** `result`, for 0025 decision 1's reasoning:
`RECORD_TYPES` is a schema surface every fold, the router's `to_route`
tuple, `cmd_digest` and the README's vocabulary all key on, and
nothing here needs a type that `result` does not already mean — an
account of a turn that a seat ran.

**`refs: [answer-id, question-id]`, and deliberately NOT the request.**
This is the one place this brief overrides the re-baseline's N-5,
which says an apply result "must name the request somewhere in `refs`"
to participate in the errand's base label. Verified reason not to:
`closing_result`'s clause (b) (`agent/castle:4705-4713`) treats *any*
result that names a claim's request, is newer than the claim, and
names no claim of that request, as the account closing that claim.
The reaper passes it every result in the journal
(`_reap_interrupted:4926`). So an apply result naming the request
would silently close a genuinely dangling worker claim — an errand
whose hand-run retry died would be labelled with the *apply's*
outcome and never reaped. Keeping the request out of `refs` makes the
apply result invisible to both `closing_result` and
`_errand_state`'s `results` selection (`agent/castle-modal:1404-1407`,
which filters on `request_id in rec.refs`), which is exactly right:
the apply is not a turn of the errand. Lineage still works —
`_find_root_request` walks `refs[0]` multi-hop
(`agent/castle:2354-2369`), reaching the request in two hops
(answer → question → request), so the router's evidence sentence and
`castle digest`'s grouping are correct with no change — and
`_collect_downstream` still collects it, because its walk follows
`refs[0]` transitively (`:5598-5611`). §H uses that.

**`seat: applier`. `provenance` inherited from the answer**, which is
always `requested` (`file_answer:1652`), so the router notifies. That
is intended: the resident authorized something, and the push channel
is how they learn what happened to it. The body's **first line is
harness prose** written for that purpose, because `_fire_notification`
takes exactly that line (`agent/castle:2507`) and a result's first
line has leaked a store path onto the notification channel before
(0025 §I).

**`outcome`: the existing four values, unwidened.** D6 says to read
the README's reservation and follow what it actually says rather than
the spec's guess. It says (`agent/README.md:814-816`): *"Tasks 0026
and 0027 are expected to reuse this field name and these four values
rather than each inventing a sibling field."* Both halves are binding
— the name **and** the values — so this task neither widens
`OUTCOME_VALUES` nor invents a differently-named replacement for it.
The re-baseline's N-3 reaches the same conclusion from the other
direction (widening ripples into `_outcome_label`, the reaper,
`closing_result` and every surface that branches), and calls option 1
"almost certainly right". It is right, and here is the split that
makes it honest: **`outcome` is an observation about the applier's own
run; a second field is an observation about the change.** That is
precisely the epistemic shape the field already has — "an observation
about the writer's own turn rather than a judgment about anyone
else's" (`agent/castle:117-122`).

**`apply-outcome`: the new field, result-only, closed vocabulary.**

```python
# What happened to the CHANGE, on a result written by the applier seat
# (docs/tasks/0026-apply-validate.md §F). Distinct from `outcome`,
# which stays exactly what agent/README.md reserves it as: an
# observation about the writer's own run. The two compose — a
# validation killed at its bound is `outcome: timeout` with
# `apply-outcome: validation-failed`, and nothing had to widen a
# vocabulary that four surfaces branch on to say it.
APPLY_OUTCOME_VALUES = (
    "applied-validated",
    "applied-unvalidated",
    "applied-uncommitted",
    "validation-failed",
    "refused-target-mechanism",
    "refused-artifact-changed",
    "refused-no-patch",
    "refused-patch-stale",
    "refused-tree-dirty",
)
```

| `apply-outcome` | `outcome` | The tree | What it means |
|---|---|---|---|
| `applied-validated` | `completed` | one commit | applied, committed, and the host configuration builds |
| `applied-unvalidated` | `completed` | one commit | applied and committed; no evaluation was attempted (option off, unsafe state layout, or no `nix`) — the body says which |
| `validation-failed` | `completed` / `timeout` | one commit | applied and committed; the build failed or outlived its bound |
| `applied-uncommitted` | `failed` | edited, not committed | the patch applied and the commit did not; the body gives both recovery commands |
| `refused-target-mechanism` | `completed` | untouched | §G |
| `refused-artifact-changed` | `completed` | untouched | a digest no longer matches |
| `refused-no-patch` | `completed` | untouched | no sidecar to apply |
| `refused-patch-stale` | `completed` | untouched | `git apply --check` refused it |
| `refused-tree-dirty` | `completed` | untouched | the resident has uncommitted work under those paths |

`outcome: completed` on a refusal is deliberate and follows the
field's own definition: the applier ran to a recorded conclusion. A
refusal is a conclusion, correctly reached. `outcome: failed` is
reserved for the applier not reaching one — an environment fault
(§C.1), a role it has no checkout for (§C.5), or a commit that failed
after its patch applied — and those records carry no `apply-outcome`
except in the last case, which is the one partial state that needs
naming.

`interrupted` is never written by this task and never will be by it:
that value is supplied retroactively by a reaper reading a surviving
`claim`, and **the applier writes no claim record** (see Considered
and rejected — it would make the dispatch reaper offer `castle work
<id>` as the retry for an apply that died). An applier killed before
it writes anything leaves no record, and the next sweep simply finds
the approval still eligible and tries once more. That is the one place
the one-attempt bound is bounded by process death rather than by a
record, and it is the honest behaviour: nothing was written, so
nothing was attempted as far as the journal is concerned.

**Body shape**, in order: the harness's one-sentence first line (the
notification, per outcome — see the table below); what was applied,
by id; the `target` copied from the proposal's result (D6) — **in the
body's prose and deliberately not as a frontmatter field**, because
`target` is defined as "which checkout the diff a turn produced applies
to", the applier's result carries no diff, and the value would be
either constant (`private`, on every record that applied anything) or
absent; what 0027 is guaranteed is that the role is stated and
reachable, not that a second record type now carries the field — and
the role's resolved path **not** stated (unlike the worker's result body,
which does state it — the applier's record is routed to a notification
and rendered in digests, and it has no reason a resident needs to see
the path they configured); the commit sha, when there is one, and the
`git revert` command; the exact validation command line (§E); the
bounded tail of its output when it ran; the spool log's path when one
was written. Nothing model-authored ever enters this record — the
applier runs no tenant.

**First lines, per outcome.** These are the notification a resident
actually receives, so they are drafted here rather than improvised.
No ids, no paths, under 200 characters
(`_route_journal_locked:2513`):

- `applied-validated` — "The change you approved is now in your
  configuration repository, and the configuration still builds.
  Nothing was activated."
- `applied-unvalidated` — "The change you approved is now in your
  configuration repository. It was not checked, and nothing was
  activated."
- `validation-failed` — "The change you approved is now in your
  configuration repository, but the configuration no longer builds.
  Nothing was activated."
- `applied-uncommitted` — "The change you approved was made in your
  configuration repository but could not be committed there. Nothing
  was activated."
- `refused-target-mechanism` — "The change you approved is to the
  Castle Turing framework itself rather than to your own
  configuration, so it was not made."
- `refused-artifact-changed` — "The change you approved could not be
  made: what is on disk is no longer the change you approved."
- `refused-no-patch` — "The change you approved could not be made: no
  exact copy of it was kept, so there is nothing to apply."
- `refused-patch-stale` — "The change you approved no longer fits your
  configuration repository, so it was not made."
- `refused-tree-dirty` — "The change you approved was not made: your
  configuration repository has uncommitted edits to the same files."

### G. An approved `target: mechanism` proposal is refused

*(Decision D3, [HUMAN via re-baseline defaults accepted].)*

0024 made `target` a two-value role; 0025 files a proposal question
for any stamped target and states in its own stop conditions that
nothing distinguishes the two
(`docs/tasks/0025-approval.md:1087-1090`). So a resident can approve a
change to this framework today, and `test/agent-loop/approval.sh`
already exercises that path deliberately. **An approved-but-unapplyable
proposal is a terminal state with a name, not an error.**

`refused-target-mechanism`. The record's body says: this change is to
the Castle Turing framework repository rather than to the resident's
own configuration; the applier only ever writes the private checkout;
the change is the resident's to carry upstream if they want it; and
their approval is recorded and remains the record of what they
thought. The body names the public repo by project name, never by
path.

**It decides nothing about where host modules live.**
`docs/backlog/where-do-host-modules-live.md` is open, and Principle
01:15 puts hardware host modules in the private layer while
`hosts/xps9370/README.md` reads as an instruction to add them here.
The refusal wording must therefore not say or imply that a
mechanism-targeted proposal is a mistake, or that the tenant chose the
wrong layer — only that this seat has no authority over that
repository. The re-baseline's X5 is the trap: the original pass's
NOW-25 proposed refusing any root containing `docs/principles/`, which
would contradict 0024's own design rather than protect anything. Not
adopted, and named here so nobody re-derives it.

**Refusing earlier is a better design and is not this task.** A check
at *proposal* time — refusing to file an applyable proposal question
for a mechanism target at all, so the resident is never asked to
authorize something that cannot be spent — avoids the small betrayal
of a refusal arriving after an approval. It is a change to 0024/0025's
filing path, not to this one, and it interacts with the open host-module
question. Filed as a backlog entry by this task
(`docs/backlog/mechanism-proposals-are-approvable-but-unapplyable.md`),
not built.

### H. The status surface, and the fold that would otherwise lie

*(The re-baseline's N-4, which must be closed in this commit.)*

Verified mechanism: `_errand_state` sets `base_source_id` from the
result closing the newest **claim** (`agent/castle-modal:1424-1447`),
and the decision override stands aside only for a record newer than
`base_source_id` (`:1565`). An apply result closes no claim, so
without a change here the errand reads `"approved — nothing applied
yet"` forever — over a *failed* apply, permanently. That is Codex's
"the journal never claims success when validation failed", made
concrete.

**A fourth stage, inside the existing decision block.** After the
deciding answer `rec` is found (`:1561-1566`), look in `downstream`
for the newest `result` whose `refs[0] == rec.id` and which was
**written by the applier seat**, and let it set `base`.

**Keyed on the seat and not on `apply-outcome`, which is a correction
code review made by execution.** Three paths write `outcome: failed`
with no `apply-outcome` at all — an unusable checkout, a `target`
naming a role this applier has no checkout for, and a `git apply` git
never finished — and after this brief's own amendments, a fourth: a
commit that reported success while leaving the repository in a state
that contradicts it. Every one of those records names the answer, so
every one bars it from `_eligible_approvals` forever; keyed on the
field, none of them was recognised here, and the errand read
`approved — waiting to be applied` permanently for something that would
never run, with the remedy named nowhere. The new row's label names the
hand path, per docs/tasks/0015's rule that a label must not cause the
inaction it describes — the automatic bar is deliberate and stays; what
was missing was telling the resident that `castle apply <answer-id>` is
still open to them. It also makes the fail-closed record-door denial
visible rather than silent: a hand-planted `seat: applier` result is
still refused, and now says so.

The same accepted limit `proposals[-1]` carries applies to
`applies[-1]`: ids are chronological only to one second, so a hand
retry landing in the same second as the attempt it retries can be
described by the wrong one of the two. Inherited from
`docs/backlog/record-ids-are-only-second-resolution.md` rather than
worked around, on that entry's own finding that a fifth local
workaround would not help. It inherits the enclosing
block's two guards for free — never over a live turn, never over
something newer — and it needs no new keying rule, because
`_collect_downstream` reaches it through the same `refs[0]` chain that
reaches the answer.

Labels, resident-facing, obeying the mode's vocabulary rule (no
`record`/`refs`/`seat`/`journal`; `castle apply <id>` is a command and
is fine, exactly as `_outcome_label` already prints `castle work
<id>`):

| state | label |
|---|---|
| approved, carries `authorizes-apply`, no apply record yet | `approved — waiting to be applied` |
| approved, pre-field proposal | `approved — nothing applied yet` (unchanged, and now true only here) |
| `applied-validated` | `applied and checked — not activated` |
| `applied-unvalidated` | `applied, not checked — not activated` |
| `validation-failed` | `applied, and the check failed — not activated` |
| `applied-uncommitted` | `partly applied — see your configuration repository` |
| any `refused-*` | `approved, but not applied — <short reason>` |
| an applier result with **no** `apply-outcome` | `could not be applied — castle apply <answer-id> to try again` |
| unrecognised `apply-outcome` | rendered verbatim, never collapsed |

The five short reasons, written here for the same reason the
notification lines are, and obeying the same vocabulary rule: "it
changes the Castle Turing framework, not your own configuration";
"what is on disk is no longer what you approved"; "no exact copy of
the change was kept"; "it no longer fits your configuration
repository"; "you have uncommitted edits to the same files."

The unrecognised case follows `_outcome_label`'s own rule
(`agent/castle-modal:1293-1304`) for the same reason it gives: a
surface quietly reporting a state because it did not understand what
it was told is the failure both closed vocabularies exist to prevent.
"not activated" appears in four of them on purpose — it is the one
fact SPRINT.md decision 4 turns on, and the status surface is where a
resident would otherwise assume otherwise.

### I. `cmd_validate` learns two fields

Following the exact "well-formed if present, never required" pattern
`blocking`/`target`/`diff-boundary`/`patch-sha256` already establish
(`agent/castle:5860-6012`), for the same append-only reason each of
them states:

- **`authorizes-apply`** — question-only (`rtype != "question"` is an
  error naming this task), and the literal string `"true"` or nothing.
  Word-for-word `blocking`'s two checks and error shapes
  (`:5893-5906`), including its argument for being strict about one
  spelling: the fold is strict in the other direction, so a
  hand-written `authorizes-apply: false` is inert rather than
  dangerous — what it is not is *visible*, and this check is what
  names it. No `cmd_record` writer guard is needed or added:
  `cmd_record` has no generic field flag, so it cannot write this
  field at all.
- **`apply-outcome`** — result-only, and a member of
  `APPLY_OUTCOME_VALUES`. A membership test rather than `target`'s
  open non-blank check, because unlike `target` this vocabulary is
  closed by construction: only one writer exists and every surface
  branches on it.

And one cross-record rule, in the whole-journal pass beside 0025's two
(`agent/castle:6143-6179`):

- **At most one result carrying `apply-outcome` per answer id.** The
  one-attempt bound is structural (§B), but the applier's lock is a
  lock and not a transaction, and a hand-run `castle apply <answer-id>`
  is deliberately allowed to retry. Two apply records for one
  authorization are legitimate in that case, so this is **not** an
  error — and that is the interesting part. What *is* checked is
  narrower and worth having: **a result carrying `apply-outcome` whose
  `refs[0]` does not resolve to an `answer` carrying `decision:
  approve`.** That is an apply claiming an authorization that does not
  exist, which is the one shape of this record nobody should ever be
  able to hand-write into a journal and have validate clean.

### J. The forged-approval hole, stated

*(Decision D5, [ADOPTED default]. STOP-9 stands: no signing mechanism
is invented here.)*

`write_record`'s refusal to write an `answer` or `correction` from
inside a worker turn keys on an environment variable the tenant can
unset (`agent/castle:1250-1262`;
`docs/backlog/env-stripping-defeats-write-guards.md`). A tenant
running `env -u CASTLE_WORKER_CLAIM castle answer --decision approve
<its own proposal question>` goes through `file_answer`, which
verifies a hash the tenant can compute itself, writes `seat: intake`,
and passes `castle validate`. `castle record --decision` is refused
(`:6334-6346`) but `castle answer --decision` is not and cannot be —
it is the documented resident path (`agent/README.md:91-99`). §B's
`cmd_apply` guard keys on the same variable and is defeated the same
way.

**Until this task, a forged approval was inert. This task is the thing
that makes it mutate a configuration.** That is the whole change in
the hole's consequence, and it is stated here rather than discovered
later. Three things bound it, none of which is a fix: the tenant is a
model this system chose to run rather than an attacker
(the backlog entry's own threat-model paragraph); nothing is
activated, so the worst case is a commit in a repository the resident
reads; and a stripped write is visible in the journal as a record with
no claim link where its siblings have one — the backlog entry's own
suggested detection (`:47-50`), which is now worth more than when it
was written and which this task deliberately does **not** build,
because a detector belongs with the weekly audit rather than bolted
onto an applier.

### K. Principle 01, and the three new options

Everything in this task is public mechanism. The three options are
slots; their values are private configuration; and **every default is
the inert one**:

- `castle.agent.apply.enable` — bool, default **false**. Declares the
  three units. Turning it on is a standing authority in exactly the
  sense `dispatch.enable`'s description already uses, and its
  description says so and points at the same undecided taxonomy
  (`docs/backlog/authority-taxonomy-prior-art.md`).
- `castle.agent.apply.evaluateFlake` — bool, default **false**. §E.
  Its description states the store consequence plainly, in D1's own
  terms: evaluating copies the tracked tree into the world-readable
  store, which is safe exactly because 0030–0032 made that tree
  publish-safe — the rule is "keep *plaintext* out of the store"
  (`docs/private-layer.md:1103-1105`), the journal is out of the tree
  since 0030, and `secrets.yaml` is ciphertext by design.
- `castle.agent.apply.timeoutSeconds` — positive int, default 1800.

Two assertions, following `modules/agent/default.nix:770-860`'s
existing shapes:

- `!cfg.apply.enable || cfg.stateDir != null`, mirroring dispatch's
  identical assertion and its reasoning verbatim.
- `!cfg.apply.enable || cfg.repo.private != null`. **This deviates
  from the neighbouring precedent and the deviation is deliberate.**
  `dispatch.enable` has no such assertion, on the argument that the
  errand-time refusal is the right place; here the thing burned by an
  unconfigured root is not an errand's automatic attempt but *a
  resident's granted authorization*, which is a costlier and less
  repeatable thing to spend on a `failed` result. Principle 02
  consequence 2 is not violated: nothing person-shaped is required to
  evaluate the module — the requirement exists only inside a branch
  the resident opted into, exactly like the `stateDir` assertion
  beside it.

No new option decides *which* changes may be applied, and none ever
should: the rule this task ships is the same **floor** 0025 shipped —
every change gets its own decision, and now every decision gets at
most one automatic apply. A floor with no dial cannot be gamed.

## Stop conditions — what this brief deliberately does not decide

A resuming session must not improvise any of these. Where a default is
implemented, it is named as a default.

- **Whether an apply may ever happen without a per-change approval.**
  No standing, blanket, class-scoped or "trusted path" apply authority
  is designed, implied, or left a hole for. Every apply spends exactly
  one answer record.
- **What a validation failure should *do*.** It is recorded and
  nothing else. STOP-6 (no auto-repair) binds: no re-proposal, no
  reopened question, no retry loop. Note the amplifier the re-baseline
  found (N-8, X3, and `docs/backlog/a-deferred-proposal-cannot-be-
  revisited.md`): `defer` is a one-way door, so "report it and let the
  resident re-decide" is not available as a mechanism at all today.
  The only remedy is a fresh `castle ask`, and that is what the record
  says.
- **Whether the private repo's standing commit authority extends to
  agent-authored configuration patches.** Analysed in §D and
  deliberately not relied on. This task does not amend
  `docs/architecture.md`'s standing-authority bullets, does not
  propose the amendment the original pass's STOP-13 wanted, and does
  not decide the push question.
- **Where host modules live** (§G). Untouched, in the wording as much
  as in the code.
- **Whether the applier should ever push.** No. Not built, not
  configurable, not left a seam for.
- **A confirming second keypress before approve** (0025's S8). Still
  open, still a single keypress, and this task raises the stakes of
  that open question without closing it — which is stated here so the
  human can close it if they want to.
- **An allow-list or deny-list of paths the applier may patch.**
  NOW-13 argues for an allow-list and the argument is good — 0031 put
  `secrets.yaml` and `.sops.yaml` in the private repo by name
  (`docs/private-layer.md:1096-1100`), and `.sops.yaml` deserves its
  own sentence because nothing in Nix reads it, so a patch to it is
  invisible to every check this task could run and silently changes
  which recipients future encryptions target (`:1320-1328`). It is not
  built here for one reason: `docs/private-layer.md:15-20`'s "minimum
  contents" listing predates 0031 and names four files, so there is no
  documented interface to ground a list on, and inventing one quietly
  is worse than not having one. Filed as
  `docs/backlog/the-applier-patches-any-path-in-the-private-repo.md`,
  which is where the list belongs once the file inventory is fixed.
- **Sub-second record ordering.** The applier's fold picks the oldest
  eligible answer by id and inherits
  `docs/backlog/record-ids-are-only-second-resolution.md`'s limit. It
  is bounded here: two approvals in one second are applied in an
  arbitrary order, both are applied, and each names its own
  authorization. No new local workaround is added — that entry's own
  finding is that a fifth one would not help.
- **Whether 0027 activates from the applier's commit or re-derives
  anything.** Not decided. What this task guarantees 0027 is: a
  commit sha in a record, a `target` role, and an `apply-outcome` that
  says whether the configuration was known to build.
- **Two dispatch- or apply-enabled hosts sharing one journal.**
  Documented as unsupported, exactly as dispatch already documents it.
  Nothing reconciles them and this task does not pretend to.

## Considered and rejected

- **Running the applier inside `castle dispatch`'s sweep.** §B, at
  length: it would put a `git apply` and a potentially thirty-minute
  `nix build` under the global sweep lock, escalating
  `docs/backlog/stalled-mount-wedges-a-sweep.md` from "one errand
  hangs" to "the whole mechanism stops, silently", and it would need a
  second, differently-keyed eligibility fold inside a function whose
  existing fold is already a filed performance debt.
- **Dispatch spawning the applier as a detached child.** D4's stated
  mechanism. Rejected on a code fact: no such pattern exists (worker
  turns run in-process, `agent/castle:5417`), and `castle-dispatch` is
  a `Type = oneshot` unit whose cgroup teardown would kill the child
  when `ExecStart` returns.
- **Widening `OUTCOME_VALUES`.** §F. `agent/README.md:814-816`
  reserves the field name *and* the four values for this task by name;
  widening ripples into `_outcome_label`, `closing_result`, the
  reaper and every surface that branches on it, to say something a
  second field says without touching any of them.
- **A new `apply` record type.** Same reasoning 0025 gave for not
  adding an `approval` type: it ripples into `RECORD_TYPES`,
  `to_route`, `cmd_digest` and the README's vocabulary, and buys
  nothing a field on `result` does not. It is also the "new authority
  vocabulary" `docs/backlog/authority-taxonomy-prior-art.md` warns
  against introducing casually.
- **Writing a `claim` record for the apply turn** (N-4's first way
  out). Rejected on a verified consequence: `_reap_interrupted`
  (`agent/castle:4930-4939`) walks every claim, and a claim whose
  `refs[0]` is a request with no closing result gets an `interrupted`
  result and a `castle work <request-id>` retry hint — the wrong
  command for an apply that died, written by a reaper that has no idea
  what it is reaping. The fourth-stage fold in §H costs less and lies
  about nothing.
- **Naming the request in the apply result's `refs`** (N-5's
  recommendation). Rejected on `closing_result`'s clause (b) — §F.
- **A `repo-head` stamp added to 0024's writer**, so staleness could
  be tested by comparing revs (NOW-8's first option). Rejected for
  this task: it only helps proposals filed *after* it ships, it widens
  a writer this task otherwise does not touch, and `git apply --check`
  already answers the question that actually matters ("does this
  patch still fit this tree") more precisely than a rev comparison
  can, since a rev that moved for unrelated reasons is not staleness.
- **Fuzzy or three-way patch application** (`git apply -3`,
  `--recount`, `patch(1)`). Rejected outright and named as a non-goal:
  a patch that does not apply exactly is not the change the resident
  approved.
- **Rolling back a commit whose validation failed.** §D. Destroys
  work the applier did not put there, is a larger authority than the
  one granted, and prevents nothing, since nothing is activated.
- **A repo-wide clean check before applying** (NOW-9's original
  premise). Rejected in favour of a path-scoped one: three documented
  layouts leave a config repo legitimately dirty
  (`docs/private-layer.md:639-656`, `:1166-1167`, `:677-684`), and a
  refusal that fires forever on a supported layout is worse than none.
- **Refusing a mechanism-targeted proposal at filing time instead**
  (D3's own named alternative, and the better design). Deferred to a
  backlog entry rather than folded in: it is a change to 0024/0025's
  writing path, and it interacts with an open question about where
  host modules live.
- **`nix flake check` or `nix eval` instead of `nix build`.** `flake
  check` builds every resident-authored `checks` output — unbounded
  work nobody asked for. A bare `nix eval` proves less than the task's
  own title claims: a configuration can evaluate and still fail to
  build.
- **A `CASTLE_APPLY_NIX`-style environment override for the `nix`
  binary**, so the harness could point it at a stub. Rejected because
  `$PATH` plus `shutil.which("nix")` already gives the harness that
  seam, using the pattern 0025 already built and proved
  (`docs/tasks/0025-approval.md:1325-1327`), and a second injection
  point is a second thing that can drift from what production does.
  The exact-argv assertion is served by the record itself (§E), which
  has permanent value to the resident as well.
- **Lifting `_split_proposal_body` out of `castle-modal` into
  `agent/castle`** (N-1's first consequence). Unnecessary since 0033:
  the applier reads the sidecar, so there is no second parser and no
  risk of two parsers disagreeing about where a diff ends.
- **Building the backlog entry's stripped-write detector** (§J).
  Belongs with the weekly audit, not with an applier.

## Hard constraints, restated

- **Never write personal data into this repo.** Every id, path and
  string in this brief and in the code it specifies is a placeholder
  this repo already publishes or an invented literal. Note the two
  places the *code* has to be careful, because they are new: the
  refusal body for a dirty tree names status letters and a count but
  **not** the resident's file names (§C.6), and the applier's commit
  message contains ids and no paths (§D). Both are durable artifacts
  that leave the machine more easily than a journal does.
- **Principle 01 test.** Public mechanism: a subcommand, a seat, two
  fields, a lock, a fold, three units and three options. Private
  configuration: whether those options are on, and what is in the
  checkout they point at. Every default is off.
- **Principle 02.** Nothing person-shaped is required to evaluate
  `modules/agent`; the two new assertions fire only inside a branch
  the resident opted into. No public module gains a resident-shaped
  requirement, and `nixosConfigurations.example` must still evaluate
  with the module imported and every new option at its default.
- **SPRINT.md decision 4 — the hardware boundary.** Nothing
  activates. No `nixos-rebuild`, no `switch-to-configuration`, no
  `systemctl`, no generation change, no `sudo`, and no path that could
  reach one. 0027 owns activation and the human performs the real one.
  This is proved, not asserted — see the stub-`$PATH` scenario in the
  verification plan.
- **The worker still never deploys, and never applies.** No change to
  `agent/castle-worker-claude`, and specifically none to its
  nonce-fenced override block (`:605-617`), which already anticipates
  this task by name. §B's environment guard is the mechanical half.
- **`agent/castle` stays stdlib-only.** `subprocess`, `shutil`,
  `hashlib`, `shlex` are all already imported or trivially available;
  nothing third-party enters.
- **Records are never rewritten, and neither are sidecars.** Nothing
  in this task opens an existing journal file or `.patch` file for
  writing.

## File-by-file change list

- **`agent/castle`**
  - New constants: `AUTHORIZES_APPLY_FIELD`, `APPLY_OUTCOME_FIELD`,
    `APPLY_OUTCOME_VALUES`, `APPLIER_SEAT`, `DEFAULT_APPLY_TIMEOUT_
    SECONDS`, `APPLY_EVALUATE_ENV`, `APPLY_TIMEOUT_ENV`; `FIELD_ORDER`
    gains `authorizes-apply` (beside `blocking`) and `apply-outcome`
    (beside `outcome`).
  - `_file_proposal_question` (~:3413): stamp `authorizes-apply: true`.
  - `apply_lock_path()` beside the existing three (~:969-1000).
  - `apply_timeout_seconds()`, modelled on `worker_timeout_seconds`
    (~:2793).
  - `_eligible_approvals(records)` — the fold (§B).
  - `_apply_one(answer, records)` — the pre-flight (§C), the git
    sequence (§D), the validation (§E), and the one record (§F).
  - `cmd_apply` / `p_apply` — the subcommand, its two forms, its lock,
    and the `WORKER_CLAIM_ENV` refusal (§B).
  - `cmd_validate` (~:5777): the two new field checks and the one new
    cross-record check (§I).
  - `_state_layout_finding` (~:818): the docstring's "advisory only"
    paragraph scoped to its two existing callers, naming this one.
  - `build_parser` (~:6220): `p_apply`.
- **`agent/castle-modal`**
  - `REVIEW_BOUNDARY_STATEMENT` (new text) and
    `REVIEW_BOUNDARY_STATEMENT_PRE_APPLY` (today's text, verbatim);
    the comment at `:690-693` naming "exactly two places" corrected to
    three and marked done.
  - `_authorizes_apply(castle, question)` — the new predicate.
  - `_review_confirmation(...)` replacing the flat
    `REVIEW_CONFIRMATIONS` lookup at the one call site (`:1144`).
  - `_render_proposal` (~:943): select the boundary statement.
  - `_errand_state` (~:1537-1585): the fourth stage and the label map
    (§H), and the `:1571-1573` comment marked done.
  - The mode's header comment (`:45-56`), which currently tells a
    reader nothing is applied by any of the three values.
- **`modules/agent/default.nix`**
  - `castle.agent.apply.enable`, `.evaluateFlake`, `.timeoutSeconds`.
  - Two assertions (§K).
  - `systemd.user.paths.castle-apply`, `.services.castle-apply`,
    `.timers.castle-apply`, modelled on the dispatch trio.
  - `CASTLE_APPLY_EVALUATE_FLAKE`/`CASTLE_APPLY_TIMEOUT` added to the
    existing `environment.sessionVariables` block so a hand-run
    `castle apply` in a terminal behaves like the unit.
- **`flake.nix`** — not in this brief's original list, and added on the
  precedent 0021 set for exactly this shape. `nixosConfigurations.example`
  gains the assertion that **no** `castle-apply` unit exists while the
  option is at its default, written as an implication so the variant
  below can inherit it; and `nixosConfigurations.example-apply` is that
  variant, turning the option on and asserting the three units carry
  what an apply needs — including, deliberately, no
  `CASTLE_MECHANISM_ROOT`. Default-off has to be provably off, and it
  matters more here than it did for dispatch: what importing
  `nixosModules.agent` must never quietly acquire is the authority to
  change a resident's configuration.
- **`agent/README.md`** — a new "Applying an approved change" section
  after "Proposing a change, and deciding it"; the `outcome`
  reservation paragraph (`:814-816`) gains one sentence recording that
  0026 honoured it and how; `apply-outcome` and `authorizes-apply`
  documented in the record vocabulary; `:101-102` and `:1296-1305`'s
  "nothing is applied" passages corrected; the `patch-sha256` section's
  "nothing reads it yet" (`:1350-1352`) corrected.
- **`docs/architecture.md`** — the Seats section gains **Applier**;
  the standing-authority bullet (`:279-281`) gains one sentence
  recording §D's analysis (that 0026 spends per-change authorizations
  and does not rely on the standing one), without amending the
  standing authority itself.
- **`docs/private-layer.md`** — "seven options" → "ten" at `:83` and
  the list beside it; the three options documented in the options
  section (`:239-320`); a new resident-facing subsection saying what
  appears in their config repo after an approval and what does not;
  the advisory-only sentence at `:725-730` scoped; the "one host per
  journal" paragraph (`:981-989`) extended to the applier; and **the
  stale sentence at `:300-301`** ("The journal lives inside this
  repository, so a path in a result body is fine") corrected — it
  contradicts `:535-537` and the template at `:154-162`, it was
  introduced by 0024 and missed by 0030's sweep, and it is exactly the
  sentence a reader would cite when reasoning about where this task's
  own journal writes land.
- **`docs/backlog/mechanism-proposals-are-approvable-but-unapplyable.md`**
  (new) — §G.
- **`docs/backlog/the-applier-patches-any-path-in-the-private-repo.md`**
  (new) — Stop conditions.
- **`test/agent-loop/scripted-worker-applyable.sh`** (new) — see
  Verification.
- **`test/agent-loop/apply.sh`** (new) — see Verification.
- **`.github/workflows/check.yml`** — one step running
  `test/agent-loop/apply.sh` in the `dispatch-test` job, beside
  `approval.sh`, with a comment in that job's established style.
- **`test/agent-loop/approval.sh`** — its premises change and must be
  re-asserted rather than relaxed: every proposal question it produces
  now carries `authorizes-apply`, and the interactive review scenarios
  now render the new boundary statement. Add the positive assertion
  for both rather than only letting the old ones keep passing.
- **`test/agent-loop/modal-headless-test.sh`** — review-mode
  assertions on the boundary statement text, plus the pre-field
  branch driven from a hand-planted question with no
  `authorizes-apply`.
- **`test/desktop-loop/test.nix`** — extended only as far as the
  modal surfaces changed (see Verification).
- **`docs/tasks/0026-apply-validate.md`** — this brief, committed on
  this branch per the tasks convention.

Nothing in `agent/castle-worker-claude` changes. Nothing in
`modules/home/default.nix` changes. Confirm both while reading and say
so in the PR if either has moved since this brief was written.

## Non-goals

- **Activating anything.** No `nixos-rebuild`, no
  `switch-to-configuration`, no `boot`/`test`/`dry-activate`, no
  generation change, no `sudo`, no root. 0027 owns activation and the
  human performs the first real one (SPRINT.md decision 4).
- **Pushing.** Not built, not configurable, not seamed for.
- **Applying a `target: mechanism` proposal.** Refused with a named
  outcome (§G).
- **Any signing, attestation or authorship mechanism.** STOP-9. §J
  states the hole rather than closing it.
- **Retroactive migration of existing approvals.** Impossible by
  construction and deliberately so (§A).
- **Fuzzy patch application.** Exact or refused.
- **Any timeout, expiry, or scheduled re-notification on a pending
  approval.** 0025's §L and its backlog entry stand untouched; the
  timeout in this task bounds a *build*, never a resident.
- **Any auto-repair, re-proposal, or reopening of a question after a
  failed apply or validation.** STOP-6.
- **A path allow-list for the applier**, including any refusal keyed
  on `secrets.yaml`/`.sops.yaml`. Filed, argued, not built.
- **Changing `agent/castle-worker-claude`**, and specifically its
  nonce-fenced override block. Its sentence "the resident applies it"
  becomes imprecise — a machine applies it on the resident's
  authorization — and it is left alone anyway: for its only audience,
  the tenant, "you do not apply it" is what the sentence means and
  what stays true, and editing an unforgeable override block to
  improve a nuance trades a real guarantee for a small one. Recorded
  here so 0027 can decide it deliberately rather than inheriting it.
- **Changing `_eligible_requests`, `_resumable_answers`,
  `cmd_dispatch`, or the dispatch units.** None of the five is touched.
- **Any private-layer configuration surface for which changes may be
  applied** (§K).

## Verification plan

Model-free throughout, per the conventions: plain bash and stdlib
python3, real `git`, **no Nix anywhere**. The `dispatch-test` job runs
on a stock Ubuntu runner with no Nix and no private layer
(`.github/workflows/check.yml:109-142`), and nothing in this harness
may need either.

### `test/agent-loop/apply.sh` (new)

Its own file rather than more scenarios in `approval.sh`, because it
inverts that file's central assertion and the two claims must not
share a helper name that means opposite things in the same suite.
Same conventions otherwise: `mktemp -d` workdir with a trap, scoped
`GIT_AUTHOR_*`/`GIT_COMMITTER_*` identity (`fixture@example.invalid`),
the notify stub, `CASTLE_STATE_DIR` a sibling state repo, and
`CASTLE_REVIEW_RESIZE_COMMAND=""`.

**The fixture private repo.** Built by the harness, committed once,
and containing only literals this repo already publishes:

- `flake.nix` — the synthetic private flake `approval.sh` already
  builds (`:73-84`). Never evaluated by anything in this harness.
- `resident.nix` — the same synthetic file, and the target of the
  ordinary apply cases.
- `hosts/example/default.nix` — a second synthetic file, so a patch
  touching a *different* path than another scenario's can prove the
  path-scoped dirty check.
- A `.gitignore`, so an ignored scratch file can prove the dirty check
  does not fire on one.

`PRIVATE_HEAD` is captured after the initial commit, as `approval.sh`
does — and, unlike there, **advanced by
`assert_private_changed_exactly` itself**, so "exactly one commit"
means one since the previous scenario rather than one since the run
began.

**One isolation the neighbouring harnesses do not need, and it is the
applier's own design that requires it.** Every git subprocess the
applier runs has its whole `GIT_*` environment stripped — deliberately,
so what a repository *is* cannot be decided by whoever exported
something — which means `GIT_CONFIG_GLOBAL=/dev/null`, the shield every
other harness here uses, does not reach it. That was harmless while
nothing ever committed. This harness commits, so it also points `HOME`
and `XDG_CONFIG_HOME` at empty directories under `$WORKDIR`: a
developer with `commit.gpgsign = true` set globally would otherwise
watch every scenario fail for a reason unrelated to the code.

**The scripted tenant, `scripted-worker-applyable.sh` (new).**
`contract-worker.sh`'s diff is deliberately synthetic and names a file
that does not exist in the fixture, so it can never apply — which is
correct for a harness that proves nothing is applied and useless for
one that proves something is. The new tenant produces a diff that
**really applies**: it copies the target file out of
`$CASTLE_PRIVATE_ROOT` to a temp path, edits the copy, and emits
`diff -u --label a/<path> --label b/<path>` between the two, writing
the result to `$CASTLE_DIFF_FILE` and one word to
`$CASTLE_TARGET_FILE`. It never writes inside the checkout — the same
constraint every other tenant fixture here honours, and
`assert_private_untouched` (below) is its teeth. Markers in the
request text select which of these it produces: a modification, a
file creation, a file deletion, a two-file patch, a patch to a path
another scenario will dirty, and `target: mechanism`.

Two things the implementation found by running git rather than by
reading about it, both recorded here because the brief reasoned from
documentation:

- **A deletion needs git's own `deleted file mode` header.** A plain
  `diff -u <file> /dev/null` produces a well-formed patch that `git
  apply` accepts and that *truncates the file to empty* rather than
  removing it. The fixture emits the two-line git header before the
  hunks; the `index` line real git also writes is omitted deliberately,
  because `git apply` neither needs nor reads it here and a fixture
  inventing a blob hash would be stating something it has not computed.
- **The rest of the sequence behaves exactly as this brief predicted.**
  `git apply --numstat -z` yields `<added>\t<deleted>\t<path>NUL`, with
  a rename spelled as an empty third field followed by two more
  NUL-terminated records (handled in the code, though no fixture here
  produces one); `git add -N` is a no-op on an already-tracked path,
  succeeds on a path the patch deleted, and is what lets a pathspec
  commit name a created one; and a pathspec commit leaves the
  resident's staged work in another file staged and uncommitted. All
  three verified against this fixture.

The tenant's second output is the byte-exact post-image of every path
it expects to exist afterwards, written under
`$CASTLE_APPLYABLE_EXPECT_DIR`. That is what lets
`assert_private_changed_exactly` compare an applied file against what
the patch was *supposed* to produce, using a copy the tenant itself
computed rather than a second, independently typed one free to drift —
and a path with no expect file is one the harness asserts was removed.

**The inverted assertion.** `approval.sh`'s
`assert_checkouts_untouched` is the claim this task is here to break
in exactly one direction. This harness carries two helpers instead:

- `assert_mechanism_untouched` — unchanged in force. The mechanism
  checkout's `git status --porcelain` is empty and its `HEAD` is
  `MECHANISM_HEAD`, after **every** scenario without exception,
  including the `target: mechanism` one. Nothing in this task may ever
  write the framework checkout.
- `assert_private_changed_exactly` — the inversion, and the assertion
  the whole task turns on. Given an expected list of paths and an
  expected content per path, it asserts: `HEAD` advanced by **exactly
  one** commit from the previous scenario's head; that commit's
  `git show --name-only` names exactly the expected paths and no
  others; each named path's content is byte-identical to what the
  patch was supposed to produce; the commit's committer name is the
  applier identity and its message contains the answer id; and
  `git status --porcelain` is empty afterwards (nothing left staged,
  nothing left dirty, no stray file). A companion
  `assert_private_untouched` (status empty, HEAD unmoved) is used for
  every refusal case.

**Scenarios.** Each ends with the appropriate private assertion, the
mechanism assertion, and `castle validate` exiting 0.

*The happy path, both trigger forms:*

1. **Automatic, end to end.** `castle ask` → `castle dispatch` →
   the proposal question exists and carries `authorizes-apply: true`
   → `castle answer --decision approve` → `castle apply --sweep` →
   `assert_private_changed_exactly` on `resident.nix`; exactly one
   result record with `seat: applier`, `apply-outcome:
   applied-unvalidated` (the gate is off — this is the default and it
   is the case a resident gets), `refs: <answer>,<question>`, and
   `outcome: completed`; the record does **not** name the request in
   `refs` (asserted directly, because §F's whole argument rests on
   it); the notification stub fired once for it with the drafted first
   line.
2. **Hand-run.** The same shape driven by `castle apply <answer-id>`.
3. **File creation** and **file deletion** and **a two-file patch** —
   three scenarios proving the `git add -N` / pathspec-commit sequence
   handles all three. The implementer verifies the exact
   `git apply --numstat -z` framing and the intent-to-add commit
   behaviour **against this fixture**, not against this brief's prose,
   and corrects the brief if git disagrees.

*The bound and the trigger:*

4. **Exactly once.** A second `castle apply --sweep` after a
   successful apply writes nothing and changes nothing; the fold is
   empty. Then `castle apply <answer-id>` by hand **does** run again
   and is refused as `refused-patch-stale` (the change is already
   there), proving the hand path is the retry path and that retrying
   is safe.
5. **Old approvals are inert.** A hand-planted proposal question with
   no `authorizes-apply`, approved through the ordinary path: the
   sweep's fold does not see it, `castle apply <answer-id>` refuses
   with a message naming the field's absence, nothing is written,
   `assert_private_untouched`. This is D2's mechanism proved rather
   than asserted.
6. **A tenant cannot apply.** `CASTLE_WORKER_CLAIM=x castle apply
   --sweep` is refused, exit nonzero, nothing written
   (`assert_private_untouched`). STOP-19's mechanical half.

6b. **An unattended applier refuses a world-writable lock directory**,
   mirroring `dispatch-test.sh`'s existing scenario for the same
   hazard: branch on whether `/run/user/$UID` exists, assert the sweep
   runs normally where it does and refuses — naming the hand path it
   deliberately keeps — where it does not.

*Every refusal, one scenario each:*

7. `refused-target-mechanism` — the mechanism-targeted proposal,
   approved, swept. Record carries the outcome; the body names the
   framework and does not name a path;
   `assert_mechanism_untouched` **and** `assert_private_untouched`.
8. `refused-artifact-changed` — flip a byte in the result record file
   after the approval (the answer's stamp no longer matches). Refused,
   nothing written to either checkout. The scenario restores the byte
   afterwards and says so in a comment, so the scenarios after it start
   from a journal nothing has tampered with. **Plus the second variant
   the brief omitted and the two-digest design requires**: leave the
   record exactly as approved and tamper with the *sidecar* instead.
   The record can be word for word what the resident read while the
   bytes that would actually be written to their files are not, which
   is precisely why there are two digests. Same outcome, different
   check — and a control afterwards that restoring the exact bytes
   makes the same approval applyable again, so neither refusal is
   satisfied by a check that simply never lets anything through once it
   has been near a file.
9. `refused-no-patch` — delete the `.patch` sidecar after approval.
   (And a second variant: a hand-planted proposal question whose
   result carries neither `patch-sha256` nor a sidecar — the pre-0033
   shape, which is the case N-1 says needs a name.)
10. `refused-patch-stale` — commit an unrelated edit to the same file
    in the fixture after the approval, so `git apply --check` fails.
    The body carries git's own message.
11. `refused-tree-dirty` — leave an uncommitted edit in the patch's
    path. Refused; the resident's edit is still there afterwards,
    byte-for-byte (asserted, because not destroying it is the point).
    Plus the **negative** control that makes the check meaningful: an
    uncommitted edit to a *different* path, and an ignored scratch
    file, both leave the apply proceeding normally.
11b. **The resident's git hooks, planted and asserted not to have
    run** — a scenario code review added. An ordinary formatting
    `pre-commit` and an ordinary generating `post-commit` in the
    fixture, then an apply: exactly one commit, its parent where the
    scenario started, its bytes the patch's and not the hook's, the
    tree clean, and the sha the record names the repository's actual
    head. Plus the control that makes it mean anything — the same two
    hooks demonstrably do run on a commit the *resident* makes, so the
    scenario cannot pass because the fixtures were never executable.

11c. **Two file names git has to be asked about** — one carrying a byte
    that is not valid UTF-8, one carrying a `*`, both generated with
    `printf` so this harness's own source stays plain ASCII. Assert the
    apply succeeds, the commit names exactly those two paths and not a
    decoy file the glob would otherwise reach, and — the half that
    matters for the journal — `castle validate` is still green, because
    a surrogate reaching a record body would make it unwritable.

12. `applied-uncommitted` — the commit made to fail. Simplest
    reproduction: point `HOME`/`GIT_CONFIG_GLOBAL` at a directory
    containing a `commit.gpgsign = true` config with no signing key,
    or make `.git` read-only for one step. Whichever the implementer
    finds reliable in CI: the assertion is that the patch is in the
    tree, `HEAD` has not moved, the record says `outcome: failed` with
    `apply-outcome: applied-uncommitted`, and the body names both
    recovery commands. If neither method is reliable on the runner,
    the scenario is skipped **loudly** with a printed reason rather
    than quietly dropped. (Implemented as a repository-local
    `commit.gpgsign` pointing at a signing program that always refuses,
    which needs no gpg on the runner at all and never depends on luck.)

    **Two variants, and the recorded recovery is EXECUTED rather than
    grepped for** — code review found that a scenario asserting the
    string is present passes just as happily when the command does
    nothing. One variant on a path the change *modified* and one on a
    path it *created*, each running the block out of the record and
    asserting both the working tree and the index return to their
    pre-apply state, with the resident's own staged work untouched. The
    created variant is the one that caught the defect: the old advice
    left the file on disk with its contents destroyed.
13. **Environment fault** — `CASTLE_PRIVATE_ROOT` pointed at a
    subdirectory of the checkout (`_checkout_fault`'s
    toplevel-mismatch case, the one its docstring says nothing
    downstream could detect). `outcome: failed`, no `apply-outcome`,
    body naming the option.

    **And then two assertions about the surface, which the brief's
    original scenario lacked entirely** — it checked field absence and
    never looked at what a resident would read. The approval is now
    barred from the sweep, so: the status line must say
    `could not be applied — castle apply <answer-id> to try again` and
    must *not* still say it is waiting; and then that command is run
    verbatim against a repaired root and must actually apply the
    change. A label naming a remedy nobody tried is how
    docs/tasks/0015's defect gets reintroduced one surface over.

13b. **A repository whose path Nix cannot name** — its own throwaway
    checkout at a path containing `#`, gate on, `nix` stubbed. Assert
    the stub was **never invoked** (the sharp assertion, and the one a
    stub can actually prove — a stub exits 0 whatever argv it gets, so
    it cannot reproduce the false `validation-failed` itself), the
    outcome is `applied-unvalidated`, the body names the character, and
    the change still landed as exactly one commit.

*The eval gate, proven in all three directions with no Nix:*

14. **Off (the default) → nothing is reached for.** With
    `CASTLE_APPLY_EVALUATE_FLAKE` unset, run an apply under a `$PATH`
    where `nix`, `nixos-rebuild`, `switch-to-configuration`,
    `systemctl` and `sudo` are stubs that log their own invocation —
    0025's pattern (`docs/tasks/0025-approval.md:1325-1327`), with
    `git` deliberately **real**, because this task needs it. Assert
    the log is empty. Assert the record says `applied-unvalidated`
    and its body contains the exact command line that would have run.
    That body line is the argv assertion: it must contain
    `--no-link`, `--no-write-lock-file`, `--no-update-lock-file`, the
    fixture's root, and
    `#nixosConfigurations.<hostname>.config.system.build.toplevel`
    with the hostname read from `/proc/sys/kernel/hostname`.
    **Compared through a shell-word splitter, not by string
    equality.** The recorded line is `shlex.join`'d so a resident can
    paste it, and the `#` in a flakeref makes that quote the whole
    argument — correctly. A harness asserting on the quoting rather
    than on the arguments would break the first time either side got
    safer, so it splits the recorded line with `shlex.split` and
    compares the list.
15. **On, unsafe layout → refuses to evaluate, names the doc.** Point
    `CASTLE_STATE_DIR` at a directory inside a fixture repo carrying a
    `flake.nix` with committed content under it — the exact shape
    `test/agent-loop/state-layout.sh` already builds, whose helpers
    this scenario copies rather than re-derives. Gate on, `nix` stub
    on `$PATH`. Assert: the stub was never invoked,
    `apply-outcome: applied-unvalidated`, and the body quotes the
    finding and names `docs/private-layer.md`.
16. **On, safe layout → the evaluation happens.** Gate on, safe state
    layout, a `nix` stub on `$PATH` that logs its full argv (one
    argument per line, for the quoting reason above) and exits
    0. Assert the stub was invoked exactly once, that its logged argv
    matches the command line the record reports argument for argument,
    and that
    the outcome is `applied-validated`. Then the same with a stub that
    exits 1 and prints 200 lines: outcome `validation-failed`,
    `outcome: completed`, the body carries the **last 40** of those
    lines and not the first, and the spool log holds all 200.
    A third variant with a stub that sleeps past a
    `CASTLE_APPLY_TIMEOUT=2`: `outcome: timeout`,
    `apply-outcome: validation-failed`, and the stub's own child (a
    background `sleep` it spawns, to model a builder) is dead
    afterwards — the process-group kill proved rather than assumed.
17. **On, no `nix` on `$PATH` at all.** `applied-unvalidated`, body
    saying so, no crash. Two binaries are borrowed onto the otherwise
    empty `$PATH` and only two: `git`, which this task needs, and the
    interpreter `castle`'s own `/usr/bin/env` shebang resolves.

*Validator coverage:*

18. `castle validate` red on: `authorizes-apply` on a non-question;
    `authorizes-apply: false`; `apply-outcome` on a non-result;
    `apply-outcome: sure-why-not`; a result carrying `apply-outcome`
    whose `refs[0]` is not an approving answer. Green on every record
    this harness produced.

### `test/agent-loop/approval.sh` and `modal-headless-test.sh`

`approval.sh` gains two positive assertions rather than being left to
pass by inertia: every proposal question it files carries
`authorizes-apply: true`, and the interactive review transcripts
contain the new boundary statement's "NOTHING IS ACTIVATED" line and
do **not** contain the retired "NOTHING ON THIS MACHINE IS EDITED"
one. `modal-headless-test.sh` gains the mirror: a hand-planted
proposal question **without** the field renders the pre-apply
statement, and the confirmation lines differ between the two.
Both keep every existing assertion, including
`assert_checkouts_untouched` — nothing in `approval.sh` applies
anything, and if that ever changes, that helper is what says so.

### `test/desktop-loop/test.nix`

Extended only as far as the modal surfaces changed, per the
established "one representative path, not the matrix" discipline: the
existing end-to-end approve path asserts the new authority wording
reaches a real compositor, and the status line afterwards reads
`approved — waiting to be applied`.

**One correction to which sentence gets asserted there.** The brief
said "the boundary statement"; the test asserts the **confirmation**
instead, and the reason is the existing code's own. That path
deliberately waits for the diff — the last thing printed — because the
boundary statement may already have scrolled past, and the file says so
in a comment: "That the boundary statement is printed at all, and
printed before the keys, is asserted by
`test/agent-loop/modal-headless-test.sh`, where it can be checked
against a transcript instead of against pixels." The confirmation is
printed last and is still on screen, so it is the surface a compositor
can actually be asked about. Both new wordings are asserted in full,
against transcripts, in the headless harness. The status label is read
as text from `castle-modal --mode status` rather than off the screen,
for the same reason: it is a fold's output.

**The VM does not run an apply**:
`castle.agent.apply.enable` stays at its default there, so the
existing "neither checkout moved / no `nixos-rebuild` ran" assertions
keep holding unchanged and keep meaning what they mean — and one
assertion is added to say why they still do: no `castle-apply` unit
file exists on that machine at all.

### `nix flake check`

This task adds three options, two assertions and three units, so this
is a real check rather than a formality: `nixosConfigurations.example`
must evaluate with every new option at its default, and the two
assertions must be provably reachable (evaluate a scratch
configuration with `apply.enable = true` and `stateDir = null` and
confirm it fails with the intended message).

Both halves are now permanent rather than one-off, per the file list's
`flake.nix` entry: `nixosConfigurations.example` asserts the units are
absent at defaults and `nixosConfigurations.example-apply` asserts they
carry what they need when the option is on, so `nix flake check` proves
the wiring on every run. The two assertions' *reachability* stays a
one-off check, because a configuration that fails to evaluate cannot be
a flake output — it is confirmed by temporarily forcing `stateDir` and
`repo.private` to null in `example-apply` and watching both messages
appear, then reverting.

### Genuinely needs human hands

Two things, and they are the ones SPRINT.md decision 4 reserves.

- **A real apply against a real private checkout**, with
  `apply.enable` on and `evaluateFlake` off. Everything mechanical is
  covered above; what a person is checking is that the commit reads
  well in `git log` on a repository they care about, and that the
  notification says something they would want to receive.
- **One real evaluation**, with `evaluateFlake` on, on the one
  Nix-capable host that exists. The harness proves the argv and every
  refusal path; only a real machine proves that the argv actually
  builds a toplevel, and no VM in this repo has a private layer to
  build one from. If the desktop-loop VM ever gains a synthetic
  private flake it can build cheaply, this moves into it; this brief
  does not build that, because a VM that builds a NixOS toplevel to
  prove one subprocess call is a large cost for a small assertion.

Everything else is the ordinary pre-PR pass `CLAUDE.md` requires:
`/code-review` on the branch, then `tools/codex-review.sh` for the
cross-model opinion, its findings posted verbatim with any disposition
in a separate comment underneath.

## Implementation prompt

You are implementing `docs/tasks/0026-apply-validate.md` in the Castle
Turing repository. You are an Opus-class implementer and you are
expected to argue with this brief where the code disagrees with it —
prominently, in the PR, and by correcting the brief in the same PR per
`CLAUDE.md`'s rule that a brief the work overtakes gets fixed in place.
This is the first task that gives the agent layer authority to change a
resident's configuration; a plausible-looking implementation that is
subtly wrong about *what was authorized* is the failure mode to fear,
not a compile error.

**Your branch is `sprint/0026-apply-validate`, already checked out in
worktree `ct-0026`, and it is stacked.** It sits on
`task/0033-byte-exact-proposal`, which sits on `sprint/0025-approval`
(PR #58). Neither is merged. `git fetch` first, then scope every diff
and every review against `origin/task/0033-byte-exact-proposal` — not
against `origin/main`, which is missing both parents and would give
you confident findings about code you never touched
(`CLAUDE.md:59-65`). Open the PR against `task/0033-byte-exact-
proposal`, re-pointing as its parents land. Merge order is
0025 → 0033 → 0026; say so in the PR description. Do not create a
branch and do not touch any other checkout. **Depend on 0033's brief
for contracts** (`<result-id>.patch`, `patch-sha256`,
"the body copy is decorative"), not on incidental details of its
implementation — 0033 is under review and may gain fix commits.

Read, in order: `CLAUDE.md`; this brief in full; the "Before starting"
list at its head, all of it, before writing anything. This brief cites
exact function names, line numbers and existing patterns you are
expected to match rather than approximate — the validator's
"well-formed if present" shape, `_fire_notification`'s best-effort
subprocess idiom, `_checkout_fault`'s `GIT_*`-stripped probe, the
`route.lock`/`dispatch.lock` family, and the dispatch units' exact
structure.

Implement in this order, each step leaving the existing suite green:

1. `agent/castle`: the constants, `FIELD_ORDER`,
   `_file_proposal_question`'s new stamp, and `cmd_validate`'s three
   new checks (§A, §I). Run the full `test/agent-loop/*.sh` suite
   immediately — the new stamp changes records every existing harness
   reads, and you want that isolated.
2. `agent/castle-modal`: the two boundary statements, the predicate,
   the confirmation helper, and `_errand_state`'s fourth stage (§A,
   §H). Run `modal-headless-test.sh` and `approval.sh`; update their
   premises as §File-by-file describes — a premise that is now false
   is corrected, never relaxed.
3. `agent/castle`: `apply_lock_path`, `apply_timeout_seconds`,
   `_eligible_approvals`, `_apply_one`, `cmd_apply`, `p_apply` (§B–§F).
   Write the git sequence against the real fixture from the start; the
   `git apply --numstat -z` framing and the intent-to-add pathspec
   commit are the two places this brief is reasoning from documentation
   rather than from a run, and if git behaves differently, fix the
   code and fix the brief.
4. `test/agent-loop/scripted-worker-applyable.sh` and
   `test/agent-loop/apply.sh` (§Verification). Write these against the
   real code and iterate until each case passes **for the right
   reason** — a refusal scenario that passes because the fixture was
   misbuilt proves nothing. `assert_private_changed_exactly` is the
   assertion the whole task turns on; write it first and make it fail
   before you make it pass.
5. `modules/agent/default.nix`: the three options, the two assertions,
   the three units, the sessionVariables entries (§K). Then
   `nix flake check`.
6. `agent/README.md`, `docs/architecture.md`, `docs/private-layer.md`
   (§File-by-file). The README's `outcome` reservation paragraph is
   the one to write carefully: a reader arriving cold must come away
   knowing that `outcome` describes the writer's run and
   `apply-outcome` describes the change, without re-reading either.
7. The two backlog entries.
8. `.github/workflows/check.yml`; `test/desktop-loop/test.nix`. Build
   and run the VM locally if the environment supports it; if not, say
   so explicitly in the PR rather than claiming coverage you did not
   run.

Then run, and check the output of rather than assuming: the full
`test/agent-loop/*.sh` suite, `nix flake check`, and the desktop-loop
VM. Then `/code-review`, address its findings, then
`tools/codex-review.sh`, posting Codex's findings verbatim with your
disposition underneath.

Four things to hold onto while you work:

- **Nothing activates.** If you find yourself typing `nixos-rebuild`,
  `switch-to-configuration`, `systemctl` or `sudo` anywhere outside a
  test stub or a comment explaining why it is never run, stop: that is
  0027, and the human performs the first real one.
- **Do not improvise authority wording.** The boundary statement, the
  confirmations, the status labels and the notification first lines
  are drafted in this brief because what they say is what a resident's
  authority *means*. If one of them is wrong, argue it in the PR and
  change the brief; do not quietly write a better sentence.
- **Do not widen `OUTCOME_VALUES`**, do not write a `claim` record for
  an apply, and do not put the request id in the apply result's
  `refs`. All three are load-bearing against verified code (§F), and
  all three look like tidying.
- **The refusals are the product.** Nine of them, each with a distinct
  remedy, each with a scenario. An applier that applies is easy; an
  applier a resident can trust is one that declines correctly and says
  why.
