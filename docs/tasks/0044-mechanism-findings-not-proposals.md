# Task 0044 — a mechanism-targeted diff becomes a finding, not a proposal

Promotes `docs/backlog/mechanism-proposals-are-approvable-but-unapplyable.md`,
deleted in the same commit per that directory's README.

**Before starting:** read `CLAUDE.md` in full. Then, closely:
`docs/tasks/done/0024-config-target.md` §6 and §16 (the two-value
`target` role, and why an unresolvable role is discarded rather than
stamped); `docs/tasks/done/0025-approval.md` §B and its stop condition
at `:1087-1090` (how a proposal question is filed, and its own note
that nothing there distinguishes the two targets);
`docs/tasks/done/0026-apply-validate.md` §A and §G (what
`authorizes-apply` means, why absence is a *positive* fact, and why
the refusal sat at apply time then); and
`docs/tasks/0042-finding-outbox.md` §3–§6, which is the lane this task
routes into and whose plumbing is reused whole.

In the code: `run_worker_turn`'s closing block in `agent/castle` — the
`stamped_target` computation, `_file_proposal_question`, and the
`_file_finding` call behind its catch-all — plus `_parse_finding`,
`_fence_for` and `_write_finding_result`.

## The problem

A worker turn that proposes a change to this framework
(`target: mechanism`) files an ordinary proposal question. The resident
reads the change, decides it is right, and approves it — and the
applier then refuses it by name, `refused-target-mechanism`. The
refusal is correct, and it says the right things: the approval is still
the record of what they thought, and the change is theirs to carry
upstream. But it arrives *after* the approval.

That is a small betrayal on the one screen in this system where
authority is granted. It is also exactly the shape
`docs/tasks/done/0015-filed-not-in-progress.md` named as the defect
this project keeps rediscovering: a label that causes the inaction it
describes. Honesty after the fact is not the same as not asking.

`docs/tasks/done/0026-apply-validate.md` §G saw this and deliberately
did not fix it there, on the grounds that moving the check is a change
to 0024/0025's *writing* path rather than to the applier's. This is
that change.

## The design

Settled with the resident on 2026-09-03. Recorded here as decided.

### 1. A completed turn with `target: mechanism` files no question

`run_worker_turn` currently ends with:

    if stamped_target:
        _file_proposal_question(request, result_id, stamped_target)

It becomes conditional on the target *not* being `mechanism`. Nothing
else about `_file_proposal_question` changes, and nothing about a
`private` target changes anywhere — end to end, byte for byte.

This is a **removal of a filing path**, and that framing is load-bearing
for §3: no new field, no new value, no third meaning for anything.

### 2. The diff rides the finding lane instead

Task 0042 opened a lane out of the OS for the case "this is not a
configuration problem, it is a defect in the thing doing the
configuring." A mechanism-targeted diff is the adjacent case — the
tenant not only found the defect but wrote the fix — and it belongs on
the same lane, because it has the same destination and the same
authority tier.

After the result is written, and on exactly the same catch-all the
outbox already runs behind, a turn with `stamped_target == "mechanism"`
hands the outbox a finding **carrying the diff in its body as a
candidate fix**:

- **If the tenant wrote a finding**, the candidate section is appended
  to it. The tenant's title, destination and problem statement are
  untouched: they are the entry, and the patch is a suggestion
  underneath it.
- **If the tenant wrote no finding**, one is synthesized (§4).

The header/body split `_parse_finding` reads is unaffected because the
append lands at the end of the body, past the blank line the header
already terminates at. A finding that was malformed stays malformed and
is refused by name with everything — including the candidate — carried
verbatim in the refusal record, exactly as 0042 §6 already promises.

**The branch gets a problem statement carrying a candidate patch, never
the patched code.** This is the whole restraint of the task. A change
to this repository lands through a numbered brief and a review; an
outbox that committed the *applied* diff would be a back door around
that pipeline, opened by a machine, in a repository whose entire
premise is that its argument travels with its code. What lands is a
`docs/backlog/` entry — a statement of a problem — with a patch quoted
in it for whoever specs it.

### 3. What this deliberately preserves

**The applier's `refused-target-mechanism` stays.** It is now a
backstop rather than the primary path, and it is not optional. The
journal is append-only: mechanism-targeted proposal questions already
sit in real journals, decided and undecided, and nothing may rewrite
them. A resident who approves one tomorrow must meet the same refusal,
with the same wording, that 0026 §G specified — including its rule that
the wording must not say or imply the change was proposed against the
wrong layer, because `docs/backlog/where-do-host-modules-live.md` is
still open and this task does not touch it.

**Private-target proposals are untouched.** Every scenario in
`test/agent-loop/approval.sh` and `test/agent-loop/apply.sh` that ends
in `target: private` behaves identically, and this brief's diff should
be readable as evidence of that.

**`authorizes-apply` semantics are untouched.** This task removes a
filing path; it does not add a third meaning to the field or to its
absence. Absence still means, and only means, "this proposal was
offered under the older, narrower statement" (0026 §A). A
mechanism-targeted question filed before this task carries
`authorizes-apply: true` if it was filed after 0026 and nothing at all
if it was filed before, and both keep meaning exactly what they meant
the day they were written. **No migration, and there can never be one.**

**The `target` field is still stamped.** `target: mechanism` on the
result is a true statement about the diff and is what 0024 built the
field to say. Only the question stops being filed.

**A mechanism target this turn could not resolve is unchanged.** 0024
§16 blanks `stamped_target` when the role resolves to no configured
root, so such a turn already filed no question and still files none; it
also routes no candidate, because there is no checkout to route one to.
The result body's existing sentence about an unresolvable role is the
whole account, as before.

### 4. The synthesized finding, and why it says so little

A turn that wrote a diff and no finding has produced a fix with no
problem statement, addressed to a directory that holds nothing else.
The harness has to write the entry, and there is exactly one thing it
may put in the title: its own observation. Not the errand's text, not
the tenant's reasoning — **those are the resident's words about the
resident's machine, and this entry becomes a file in a public
repository.** That constraint decides the shape.

    Title: A worker turn proposed a change to the framework without a finding
    Destination: mechanism

with a body saying what the harness actually knows: a worker turn
produced this candidate while working on an errand, wrote no finding to
say what problem it solves, and the patch below is therefore a fix
whose reason a cold reader cannot recover. That is a real gap in this
framework's worker contract, stated for a stranger, which is what a
backlog entry is.

**The title is fixed prose, so a second synthesized entry collides with
the first and is refused `refused-already-there`.** Deliberate, and
consistent with 0042's own rejection of suffix disambiguation: a
near-duplicate backlog entry filed automatically is a mess a human
reconciles later. Nothing is lost when it fires — the refusal record
carries the finding, candidate patch and all, and the byte-exact copy
of the diff is still in the journal beside the worker result. What the
resident reads is "something by that name is already filed", which is
true and is the useful sentence: the first such entry is still
unmerged and the same contract gap has now produced a second one.

The fix for the collision is not a suffix; it is a tenant that writes a
finding, which §5 asks for in the one place a tenant is told what to
write.

### 5. The tenant is told what happens to a mechanism diff

`agent/castle-worker-claude`'s prompt gains one paragraph in its
diff-and-target section: a diff targeting `mechanism` is not something
the resident approves — it travels as a candidate patch inside a
finding, on a branch of the framework checkout, and the framework's own
review decides it. And therefore: write the finding as well as the
diff whenever you target `mechanism`, because it is the problem
statement the patch needs and without one the harness writes a
placeholder that says less than the tenant knows.

This is the same restraint 0042 §2 put on the format paragraph — the
prompt is the one place a tenant is told what to write, so the sentence
goes there and nowhere else.

### 6. Byte fidelity, restated for a patch rather than for prose

0042 §6 argued that carrying a finding's bytes in a record body does not
contradict `docs/backlog/a-proposed-diff-does-not-survive-the-journal.md`,
because a finding is prose nothing mechanical reads back. A **patch** is
not prose, so the argument has to be made again rather than inherited.

It holds, for a different reason: nothing applies this copy either.
The candidate in the backlog entry is quoted inside a fence chosen by
`_fence_for`, for a human to read and re-derive. The byte-exact copy the
applier's discipline exists to protect is unaffected — the `.patch`
sidecar beside the worker result is still written on exactly the gate
it was (a non-empty diff), still hashed into `patch-sha256`, and still
the only artifact any applier ever reads. The entry says so in prose, so
that a reader who wants the exact bytes knows they are not looking at
them.

The one thing this must never become is an outbox that commits the
patch *applied*. See §2.

## Considered and rejected

**Refusing to stamp `authorizes-apply` on a mechanism proposal, leaving
it decidable.** The backlog entry called this "almost certainly right"
— the question still gets filed, deciding it still records what the
resident thought, and the review screen says plainly that approving
authorizes nothing. Rejected: it makes the *absence* of
`authorizes-apply` mean two different things in the same journal, and
0026 §A spent its whole argument establishing that absence is a single
positive fact ("this proposal was offered under the older, narrower
statement"). A second meaning is not a small addition to that field; it
retroactively muddies every pre-0026 record, which is the one thing an
append-only journal cannot recover from. It also still asks the
resident to spend attention on a decision with no consequence, which is
the defect rather than a milder form of it.

**Refusing to file the question and doing nothing else.** The other
shape the backlog entry named. Rejected because the diagnosis and the
fix then die in a result record, which is the manual channel 0042 was
built to retire — one layer further in.

**Routing the mechanism diff to review mode as a non-authorizing
"read this" screen.** A modal change, out of scope for the same reason
0042 gave when it rejected rendering findings in review mode: that
surface renders diffs against a checkout the resident owns, and this
one is not.

**Deriving the synthesized entry's title from the errand, the tenant's
reasoning, or the journal record id.** The first two are the resident's
private layer and may never enter this repository. The record id would
make every synthesized entry unique and so would avoid
`refused-already-there` — but `docs/backlog/README.md` says entries are
not numbered, slugs only, and a filename carrying a UTC timestamp from
a resident's machine is a fact about them for no gain. (Record ids do
already appear in a finding commit's *message*, from 0042; this task
does not disturb that and does not extend it to file names.)

**Suffixing a colliding synthesized slug.** 0042 rejected this for
tenant findings and the reasoning transfers unchanged. See §4.

**Moving `refused-target-mechanism` out of the applier once nothing
files such a proposal any more.** The journal is append-only. A
vocabulary value a past writer could have written is never removed —
the same rule that keeps `applied-uncommitted` in
`APPLY_OUTCOME_VALUES` after no path produced it.

**Making a mechanism-targeted diff with no accompanying finding a
refusal.** Honest, and it was tempting: the tenant has broken a
contract this task then writes into the prompt. Rejected because the
resident settled the synthesized-finding design, and because a refusal
would throw away a real candidate fix over a missing paragraph. The
gap is reported instead — which is what the synthesized entry's title
says.

## Non-goals

- **Where host modules live.** `docs/backlog/where-do-host-modules-live.md`
  stays open and nothing here touches it. In particular no refusal, note
  or prompt sentence added by this task may say or imply that a
  mechanism-targeted change was proposed against the wrong layer. The
  re-baseline trap 0026 §G names — refusing any root containing
  `docs/principles/` — is not adopted here either.
- **Pushing, or opening a pull request.** Unchanged from 0042:
  `docs/architecture.md`'s push bullet stays open and the outbox still
  commits local-only.
- **Any new Nix option, any new record type, any new field.** The lane,
  the vocabulary and the checkout all already exist.
- **`authorizes-apply`, `target`, `patch-sha256` and the `.patch`
  sidecar.** All untouched.
- **Private-target proposals.** Untouched end to end.
- **Any modal or review-surface change.** A mechanism proposal simply
  stops appearing there; nothing about how the surface renders what
  remains changes.

## File-by-file change list

- **`agent/castle`** — the routing (§1, §2), the synthesized finding
  and the candidate-section builder (§4), and one sentence in the
  worker result body for a mechanism target saying nothing was filed
  for approval and where the diff went instead.
- **`agent/castle-worker-claude`** — §5's paragraph.
- **`docs/architecture.md`** — the **Outbox** paragraph gains the
  candidate-patch clause and the "never the patched code" restraint;
  the **Applier** paragraph's mechanism clause is restated as a
  backstop for records already in the journal.
- **`agent/README.md`** — the `target` field's paragraph, which
  currently says the applier's refusal is what a `mechanism` target
  gets, is corrected to say a mechanism target files no proposal and
  the refusal is the backstop.
- **`test/agent-loop/approval.sh`** — the mechanism scenario, rewritten
  (verification plan below).
- **`test/agent-loop/apply.sh`** — its mechanism scenario builds its
  proposal through a worker turn, which no longer files one; rebuilt on
  the hand-planted-record pattern that file already uses for
  "old approvals are inert".
- **`docs/backlog/mechanism-proposals-are-approvable-but-unapplyable.md`**
  — deleted. `docs/tasks/0042-finding-outbox.md` and
  `docs/tasks/done/0026-apply-validate.md` cite it by path; both are
  updated to point here, and 0042's own non-goal ("mechanism-targeted
  *diffs* … is task 0044") is left standing because it is now true by
  name.

## Verification plan

### `test/agent-loop/approval.sh` — the routing, end to end, zero models

0026 §G kept this file's mechanism-target scenario meaningful on
purpose. This task is the deliberate change of that meaning, so the
scenario is rewritten rather than deleted:

1. **A completed turn targeting the mechanism checkout files no
   proposal question.** `proposal_question_for` returns nothing for that
   errand — asserted by the field, never by wording, as that helper
   already insists. The result still carries `target: mechanism` and
   still names the resolved path (the existing assertion, kept: it is
   what proves `CASTLE_MECHANISM_ROOT` is real rather than decorative),
   and its body says plainly that nothing was filed for approval.
2. **The diff is committed as a candidate instead.** An outbox record
   naming that worker result carries `finding-outcome: filed`, and the
   named branch in the mechanism checkout holds exactly one commit off
   `origin/main` whose single file is a `docs/backlog/` entry
   containing the diff's marker lines inside a fence. The fixture
   mechanism checkout gains an `origin/main` ref for this — the same
   one-line `update-ref` `outbox.sh` uses, and for the same reason: the
   outbox branches from it and never fetches.
3. **Never the patched code.** The committed tree differs from
   `origin/main` in exactly one path, `docs/backlog/<slug>.md`, and the
   file the diff was against is byte-identical on both. This is §2's
   central restraint stated as a test.
4. **A tenant that writes a finding of its own keeps it.** A second
   mechanism tenant writes a diff, a target and a finding; the branch's
   entry carries the tenant's `Title:` and the candidate section
   underneath. The synthesized title does not appear.
5. **The historical record stays decidable and stays inert.** A
   mechanism-targeted proposal question is planted by hand — the
   pattern `apply.sh` already uses, and the only way to produce one now
   — with `authorizes-apply: true` and a `proposal-sha256` over a real
   `target: mechanism` result. `castle validate` accepts it, the
   resident can approve it, the approval records, and
   `assert_checkouts_untouched` holds. Nothing rewrites it and nothing
   drops it.
6. **`assert_checkouts_untouched` after every scenario, unweakened.**
   Creating a branch ref moves no HEAD and dirties no tree, so the
   file's central negative claim is unchanged and still has teeth.

### `test/agent-loop/apply.sh` — the backstop

Its mechanism scenario currently gets its proposal from `new_approval`,
which runs a worker turn; that turn now files no question. Rebuilt to
plant the question by hand over a real mechanism-targeted result and
its `.patch` sidecar, mirroring "old approvals are inert" a hundred
lines above it. Every assertion it already makes is kept verbatim,
including the two that guard 0026 §G's wording — the refusal names the
framework by project name, never by path, and never implies the change
was proposed against the wrong layer.

That file's mechanism fixture deliberately keeps **no** `origin/main`,
so the outbox refuses `refused-no-base` and writes nothing to the
checkout. `assert_mechanism_untouched` therefore stays exactly as
strong as it was, and this file's claim — nothing here may ever write
the framework checkout — stays crisp.

### Everything else

`test/agent-loop/config-target.sh` runs a mechanism-targeting turn and
asserts on the result, never on a question, so it is unchanged; its
fixture also has no `origin/main`, so the outbox refuses there too and
`assert_checkouts_untouched` holds. `castle validate` runs over the
finished journal in every harness, and `nix flake check` runs in CI.

### What only a live errand on the reference host proves

One mechanism-shaped errand dispatched for real, after 0042 and 0043
are deployed, on a host with a mechanism checkout configured: the turn
completes, no approval appears in the inbox, and a branch shows up in
the framework checkout carrying a backlog entry with the candidate
patch in it. Do not simulate it. What a person is checking that no
harness can is whether the entry reads as a problem statement a
stranger could act on, and whether the candidate section reads as a
suggestion rather than as an instruction.

## Judgment calls

Reported here because the instructions that produced this brief left
them open, and because this task touches the one screen where authority
is granted, so the wording choices are design.

1. **The synthesized entry's title is fixed prose, and collisions
   refuse.** §4 argues it. The alternative that always lands — a title
   carrying the worker result id — was rejected against
   `docs/backlog/README.md`'s "slugs only, entries are not numbered"
   and against putting a timestamp from a resident's machine into a
   public file name. A reviewer who would rather every candidate land
   than have the second one refused would change this, and it is a
   one-line change.
2. **The title names the *contract gap* rather than the change.** "A
   worker turn proposed a change to the framework without a finding" is
   a statement of a problem, which is what a backlog entry is; "a
   candidate change to the framework" would be a statement of an
   artifact. The cost is that an entry whose patch is excellent still
   reads as a complaint about the harness. Accepted, because the
   complaint is true and the resident renames it when they spec it.
3. **The candidate is appended to a tenant's finding regardless of what
   its `Destination:` says.** With `mechanism` the only member of the
   destination set, any other value is already refused by name and the
   whole thing rides verbatim into the refusal record. Deciding
   otherwise would put a judgment in `run_worker_turn` about whether a
   finding is "the right" finding for a diff, which is the reasoning
   the outbox paragraph forbids one line away.
4. **The append happens in `run_worker_turn`, not in the outbox.** The
   outbox stays a total function of bytes-plus-checkouts with no
   knowledge that candidates exist. What composes the finding is the
   turn, which is the only party that has both deliverables in hand.
5. **The gate is written as "not `mechanism`" rather than "is
   `private`".** Faithful to what the task is: the removal of one
   filing path. A future third role would go on filing a question,
   which is the behaviour 0025 specified, rather than silently
   acquiring this task's exception.
6. **A mechanism target that resolved to no checkout routes nothing.**
   Unchanged behaviour, stated in §3 because it is the one case where a
   tenant names `mechanism` and neither a question nor a candidate is
   produced, and a reader could otherwise think this task lost it. The
   diff is still in the result and still in the sidecar.
7. **`apply.sh`'s fixture is left without an `origin/main`** so its
   mechanism scenario keeps writing nothing to the framework checkout.
   The alternative — give it one, and assert the branch there too —
   would duplicate `approval.sh` and blunt the one assertion `apply.sh`
   is organised around.
8. **`test/agent-loop/outbox.sh` is not extended.** Its tenant writes
   no diff and names no target; the routing this task adds lives in
   `run_worker_turn` and is covered where the other proposal-filing
   scenarios are. A reviewer who wants the candidate path exercised
   against the outbox's own refusal matrix (dirty tree, taken name)
   should say so — it is more coverage, at the cost of a second copy of
   the mechanism-tenant fixture.
