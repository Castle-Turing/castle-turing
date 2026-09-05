# Task 0042 — the finding outbox

Promotes two backlog entries, both deleted in the same commit per that
directory's README:

- `docs/backlog/a-framework-defect-found-by-a-worker-has-no-outbox.md`
  — the lane.
- `docs/backlog/work-leaves-the-os-in-a-boring-format.md` — what
  travels down it, and the restraint that keeps it boring. Its
  **example-profile half stays deferred** and is not promoted here;
  see Non-goals.

**Before starting:** read `CLAUDE.md` in full. Then, closely:
`agent/castle`'s `run_worker_turn` — specifically the deliverable
allocation task 0039 moved under the state directory and the `finally`
that unlinks it; `closing_result` and the `refs` paragraph of
`_write_apply_result`, which is the reasoning this task's journal
accounting has to satisfy rather than rediscover
(`docs/tasks/0026-apply-validate.md` §F); `_run_git`, `_build_commit`,
`_dirty_entries` and `_dirty_under`, which are the git posture this
task copies; and the **Dispatch** and **Applier** paragraphs of
`docs/architecture.md`, which are the register the new paragraph is
written in. Read `docs/backlog/a-proposed-diff-does-not-survive-the-
journal.md` as context — it is not promoted by this task, but it is
why a deliverable is a file the tenant writes and never a record body
the harness reconstructs.

## The problem

Three times on the first night of live dispatch (2026-08-31/09-01) a
worker turn correctly diagnosed something wrong in the **framework** —
a feature with no option surface, and two defects in the worker
plumbing itself — and had nowhere to send the finding. The contract's
honest dead-end ("say so and stop, having proposed nothing") puts the
diagnosis in a result record's prose, where the only reader is the
resident, and the only way it reaches `docs/backlog/` is a human
carrying it there through a development session. Each of those three
findings did reach this repository, through exactly the manual channel
this project exists to retire.

The worker seat has two output lanes and both point at the resident's
own configuration: a diff, and the name of the checkout that diff
applies to. There is no lane for "this is not a configuration problem,
it is a defect in the thing doing the configuring."

## The design

Settled with the resident on 2026-09-03. Recorded here as decided.

### 1. A third deliverable: `$CASTLE_FINDING_FILE`

A worker turn gets a third file beside the diff and the target,
allocated **exactly** the way task 0039 allocates the other two:
`tempfile.mkstemp(dir=work_scratch_dir())`, so it is mode `0600`,
collision-free, under the state directory where a sandboxed tenant can
reach it, read back as bytes, and unlinked in the same `finally` on
every ordinary and exceptional exit. It is pruned by the same
`cmd_dispatch` sweep, because it is in the same directory. Nothing
about 0039's argument for that location is re-litigated here; the
third file simply joins the other two everywhere they are already
handled.

**One file, one finding.** A turn with more than one thing to report
picks the one worth reporting and says the rest on stdout, where the
result record keeps it. A list format would be the first inch of a
schema, and the second promoted entry is explicitly about not taking
that inch.

**A turn that has nothing to report leaves it empty**, which is the
normal case and is never a fault — the same posture an empty
`$CASTLE_DIFF_FILE` already has, and for the same reason task 0039
gave when it rejected making an empty diff an error.

### 2. The format: boring, and a preference rather than a standard

The finding is a work item in the layout the 2026-09-01 deliberation
settled: a header of `Key: value` lines, a blank line, then a markdown
body.

```
Title: A framework defect found by a worker has no outbox
Destination: mechanism

**What.** One or two sentences on the problem.

**Why it matters.** The cost of not fixing it.
```

`Title:` and `Destination:` are both required. The body is shaped like
a `docs/backlog/` entry — **a statement of a problem, not a solution**,
written for a stranger — because `docs/backlog/` is where it lands and
that directory's README already says what an entry is.

**One paragraph of format documentation, at the emission site.** That
paragraph lives in `agent/castle-worker-claude`'s prompt, which is the
one place a tenant is told what to write, with a pointer to it from
`_parse_finding`'s docstring in `agent/castle`. Explicitly **no schema
document, no versioning, no registry**. That restraint is the point of
the second promoted entry, not an omission from this task: if a second
resident's harness ever chokes on the format, that adoption pressure
is what promotes the paragraph to something specced. Anything built
now would be an RFC for a population of one.

### 3. The outbox is plumbing

**Outbox** (plumbing, not a reasoning seat). It is a total function of
one turn's outputs: given the bytes in `$CASTLE_FINDING_FILE`, the
turn's outcome, and the configured checkouts, what it does is fully
determined and reconstructable by re-running it against the same
inputs. It holds no judgment, runs no tenant, consults no model, and
has no opinion about whether a finding is worth filing — the seat that
wrote the file already decided that, and the resident decides again at
the eventual pull request. Giving it a policy about which findings are
worth landing, or a say in whether to land one, would make it a
reasoning seat; this paragraph exists to stop a later agent from
"completing" it into one, exactly as the same sentence does for
dispatch and for the applier.

An **Outbox** paragraph in that register is added to
`docs/architecture.md` beside those two.

After a completed turn whose finding file is non-empty, the outbox:

1. Parses the header. No `Title:`, no `Destination:`, or a title that
   slugifies to nothing → refuse, `finding-outcome:
   refused-malformed`.
2. Validates `Destination:` against a **closed set of configured
   checkouts**. In v1 that set is exactly `mechanism`, resolved to
   `castle.agent.repo.mechanism`. Anything else → refuse,
   `refused-destination-unknown`, naming the value and the set.
3. Resolves the destination to a usable checkout. Unconfigured, or
   configured-and-broken (`_checkout_fault`, so
   `CASTLE_MECHANISM_ROOT` is unset for the turn) → refuse,
   `refused-destination-unconfigured`. **This is the honest dead-end
   becoming a stated limit rather than a silent drop** — see §6.
4. Refuses when the checkout is dirty under the target path →
   `refused-tree-dirty`, reported as a count and status letters and
   never as file names, through the existing `_dirty_under`. That
   helper's own docstring is the reason: a path the resident happens
   to be working on is theirs, and this record is durable and leaves
   the machine more easily than a journal does.
5. Refuses when there is nowhere free to land: the path already exists
   in the base tree, or a branch of that name already exists →
   `refused-already-there`.
6. Otherwise commits the finding as `docs/backlog/<slug>.md` on a
   fresh branch off `origin/main`, and moves the branch ref.
   `finding-outcome: filed`.

**It never touches the resident's current branch and never writes
`main`.** The commit is built entirely with git plumbing — `read-tree`
into a private `GIT_INDEX_FILE`, `hash-object -w`, `update-index
--add --cacheinfo`, `write-tree`, `commit-tree`, then one
`update-ref refs/heads/<branch> <sha> ""` — so the working tree, the
real index and `HEAD` are never read for content and never written.
The three-argument `update-ref` with an empty old value is what makes
"fresh branch" a git-enforced precondition rather than a check with a
race after it. `_build_commit`'s argument transfers exactly: the
content of the commit is a pure function of things already verified,
and the working tree is not one of them, so a failure at any stage is
a clean refusal with nothing to undo.

**It NEVER pushes.** `docs/architecture.md`'s push bullet is
unamended by this task: the push cadence and the credential that would
enable pushing from a host are an open design item — "an authority
question rather than a storage one" — and commits stay local-only with
pushes left to the resident until that is answered. A finding lands as
a branch in a checkout on the resident's own machine and goes no
further without them.

**Base ref is `origin/main`, never a local ref**, which is `CLAUDE.md`'s
own rule for anything derived from a ref and the reason the branch is
useful: a branch cut from whatever the resident happened to have
checked out would carry their in-progress work into a finding's pull
request. The outbox does **not** fetch first — a fetch is network, and
this seat does no network at all — so the branch may be based on a
stale `origin/main`. That is stated in the record and is the
resident's to rebase. `origin/main` not resolving is
`refused-no-base`: a fact about the checkout, named rather than worked
around by falling back to `HEAD`.

**The commit identity is the outbox seat**, `Castle outbox
<outbox@castle.invalid>`, for the reason the applier states about its
own: signing a seat's commit with a resident's key would assert
authorship they do not have. `commit-tree` does not sign, and
`GIT_ISOLATION_ARGS` keeps the resident's hooks and their
`core.attributesFile` out of it, for the reasons that constant already
documents at length.

### 4. Authority tier: made-then-reported

**No approval question is filed for a finding.** The resident's
judgment is spent once, at the eventual pull request, not twice. A
finding that had to be approved before it could become a branch would
put the resident in the loop for the cheapest, most reversible thing
the system does — writing a file on a branch nobody has merged — and
would recreate the manual channel this task exists to retire, one
click further along.

That places it in the authority taxonomy's **made-then-reported**
category, and the reporting half is not optional:

- **The digest** renders the outbox's record like any other, and
  additionally prints its `finding-outcome` on its own line beside the
  `outcome` line it already prints for results.
- **The status surface** (`castle-modal --mode status`) prints a line
  per finding under the errand it came out of, naming the branch and
  the checkout — reachable because `_collect_downstream` is transitive
  over `refs` and the outbox record's `refs[0]` is the worker result,
  whose own `refs[0]` is the request.

Nothing lands silently. What this deliberately does **not** do is fire
a push notification per finding; see §5 on provenance.

### 5. Journal accounting, and the refs trap

The outbox writes **its own `result` record** of what it committed:
the branch, the commit sha and the repository-relative path. No new
record type — `RECORD_TYPES` is a schema surface every fold, the
router's `to_route` tuple, `cmd_digest` and `agent/README.md`'s
vocabulary all key on, and nothing here needs a type that `result`
does not already mean: an account of a turn a seat ran.

**`refs: [worker-result-id]`, and deliberately NOT the request.** This
is the part `docs/tasks/0026-apply-validate.md` §F's reasoning exists
to protect, and it applies here unchanged. `closing_result`'s clause
(b) treats *any* result that names a claim's request, is newer than
the claim, and names no claim of that request as the account closing
that claim — and `_reap_interrupted` passes it every result in the
journal. An outbox result naming the request would therefore silently
close a genuinely dangling worker claim: an errand whose hand-run
retry died would be labelled with the *outbox's* outcome and never
reaped. Keeping the request out of `refs` makes the outbox record
invisible to both `closing_result` and `castle-modal`'s
`_errand_state`, which filters results on `request_id in rec.refs`.
That is exactly right: **filing a finding is not a turn of the
errand.**

It must also not name the **claim**, which would be worse. A result
naming a claim is `closing_result`'s clause (a) — the exact,
per-turn, unambiguous case — so an outbox record referencing the claim
would not merely risk closing a dangling turn, it would positively
assert that it is that turn's account.

Naming the worker **result** instead is safe on both clauses and is
also the true statement: this record is about what happened to that
result's finding file. Lineage survives it — `_find_root_request`
walks `refs[0]` transitively and reaches the request in two hops
(outbox result → worker result → request) — so `castle digest`'s
grouping and the router's evidence sentence are correct with no change
anywhere, and `_collect_downstream` still collects it, which is what
§4's status line rides on.

`castle validate` gains a guard that keeps this true forever rather
than only until someone edits it: an `outbox`-seat result whose
`refs[0]` does not resolve to a `result`, or which names a `request`
record anywhere in its refs at all, is an error naming this section.
The reasoning above is a paragraph in a docstring; without the check,
the defect it prevents reappears the first time someone "fixes" the
refs to be more informative.

**Fields.** Two new ones, both result-only and both shape-checked by
`castle validate` the way every field since 0024 has been — checked
when present, never required, so no record written before they existed
fails retroactively:

- `finding-outcome`, closed vocabulary: `filed`,
  `refused-malformed`, `refused-destination-unknown`,
  `refused-destination-unconfigured`, `refused-tree-dirty`,
  `refused-already-there`, `refused-no-base`, `failed-git`. A
  membership test rather than `target`'s open check, for the same
  reason `apply-outcome` gets one: exactly one writer exists and every
  surface that reads it branches on the value.
- `finding-commit`, the commit sha, stamped **only** on the `filed`
  path. 40 or 64 lowercase hex, both lengths and no third, because
  git's sha256 object format is real and a resident's repository is
  theirs to create however they like.

- `finding-branch` and `finding-destination`, also stamped only on
  `filed`. These are fields rather than prose because §4's status line
  has to name the branch and the checkout, and `agent/README.md`'s
  `outcome` section forbids a surface inferring a fact by grepping a
  body — the lesson `apply-commit` was promoted for. `finding-
  destination` carries a **role**, never a path, for exactly
  `target`'s reason: a role is legible cold years later and an
  absolute path is a lie the first time the checkout moves.

The repository-relative path of the entry itself stays prose-only,
beside the resolved checkout path, for the split `apply-commit`
established: the field is the machine-facing fact, the prose is the
resident-facing copy. Nothing keys on the path, and a field is a
promise that something may.

**`outcome`** is not widened. `failed-git` — git absent, or a git
command that did not finish — is `outcome: failed`, an environment
fault. Every refusal is `outcome: completed`, because the outbox ran
to a recorded conclusion and a conclusion correctly reached is not a
failure of the run. That is the same split `apply-outcome` made, for
the same stated reason: `outcome` is an observation about the writer's
own run, and the new field is an observation about the finding.

**`provenance: initiated`**, and this is a departure from
`_write_worker_result`'s inheritance that needs stating. Provenance
records who *wanted* the work. The resident asked for the errand; they
did not ask for the finding — the worker volunteered it, unbidden,
about the framework rather than about the errand. `initiated` is the
true value, and the router's provenance rule then sends it to the
digest rather than to a notification, which is the reporting cadence
§4 wants: a finding is worth reading in the day's account, not worth
interrupting someone for.

### 6. The honest dead-end

If no mechanism checkout is configured — the **normal** case for a
resident who consumes this framework as a pinned flake input rather
than as a working tree — the finding has nowhere to go, and the record
says so plainly rather than dropping it: what the destination was, why
nothing could receive it, and the option that would change that
(`castle.agent.repo.mechanism`).

**The finding's own text is carried verbatim in the record body on
every path except `filed`.** This is the only place the finding's
bytes ever enter a record body, and it does not contradict
`docs/backlog/a-proposed-diff-does-not-survive-the-journal.md`. That
entry's failure mode is a byte-exact artifact being *reconstructed*
from a record body that a line-oriented format is entitled to
normalise — a diff that `git apply` then rejects. Here, on the `filed`
path, the record body carries no copy at all and the committed file is
the artifact; on the refusal paths nothing was committed anywhere, so
the body copy is the only copy and there is no second source for it to
disagree with. Nothing mechanical ever reads it back. A finding is
prose for a human, so a normalising round trip costs legibility at
worst, never correctness — which is precisely not true of a patch.

## Considered and rejected

**Routing the finding through review mode as an approvable
proposal.** The promoted entry sketched this ("the router routes it
like a proposal — the resident approves it in review mode"). Rejected
after the 2026-09-03 deliberation for the reason §4 states: it spends
the resident's judgment twice on the same artifact, and the second
spend — at the pull request — is the one that can actually see the
change in context. It also would have needed review mode to render a
markdown document where it renders diffs, which is a modal change this
task is explicitly out of scope for.

**Appending to a single findings file.** One file per entry is what
`docs/backlog/README.md` requires, and its stated reason is exactly
this case: parallel writers never conflict where a shared list would.

**Disambiguating a slug collision with a suffix.** Rejected in favour
of `refused-already-there`. A near-duplicate backlog entry filed
automatically is a mess a human has to reconcile later; a refusal
whose record carries the finding verbatim loses nothing and says
plainly that the repository already has an entry by that name.

**Defaulting an absent `Destination:` to `mechanism`.** It is the only
member of the set, so the default would be harmless today and would be
judgment — the one thing plumbing may not have. When the set grows,
the default would silently start being wrong.

**Fetching `origin/main` before branching.** The outbox does no
network, and an unattended `git fetch` against a resident's remote is
a different authority question from the one this task settles. A stale
base is visible, stated in the record, and fixed by a rebase.

**A `castle outbox` subcommand.** Nothing needs to invoke this by
hand: it is a function of a turn's outputs and runs where those
outputs exist. A subcommand would be a second entry point that could
be pointed at a different finding file, which is the shape of thing
that later needs its own authority argument.

## Non-goals

- **Pushing, or opening a pull request.** Named out of scope by the
  brief that commissioned this, and consistent with
  `docs/architecture.md`'s open push-authority bullet.
- **Any modal or approval-surface change** beyond the one status line
  in §4. No new mode, no new picker, no review-mode rendering of a
  finding.
- **The `chevaline-example/` profile half** of
  `work-leaves-the-os-in-a-boring-format.md`. It stays deferred and is
  re-filed as its own backlog entry in this commit, so promoting the
  parent does not delete work nobody has done.
- **Mechanism-targeted *diffs*.** A worker that wants to change the
  framework rather than report a problem with it is
  `docs/tasks/0044-mechanism-findings-not-proposals.md`, which builds
  on this lane and which promoted the backlog entry this non-goal
  originally cited. The applier's `refused-target-mechanism` is
  untouched here, and 0044 keeps it as a backstop.
- **No new Nix option.** The destination set resolves to
  `castle.agent.repo.mechanism`, which already exists. Principle 01
  splits cleanly: the outbox and the format are public mechanism, the
  checkout path and whether one exists at all are private
  configuration.
- Not `docs/backlog/a-proposed-diff-does-not-survive-the-journal.md`,
  which §6 argues against and does not close.

## Verification plan

### What `test/agent-loop/outbox.sh` proves, with zero models

A new harness in the shape of `apply.sh`: two real git checkouts under
`$WORKDIR`, a state repository beside them, a git identity scoped to
the process, the notify stub, plain bash and stdlib `python3`, no Nix,
zero models, zero network. Its tenant is a new
`scripted-worker-finding.sh` that writes `$CASTLE_FINDING_FILE` from
markers in the request text — Proposal 03's hardening test, that a
seat's contract holds for any intelligence that can read and write the
artifacts, including a shell script.

Scenarios, each asserting on the artifact and not on the exit status:

1. **A turn that writes a finding produces the branch commit and the
   journal record.** `git show <branch>:docs/backlog/<slug>.md` is
   byte-identical to what the tenant wrote; the branch has exactly one
   commit and its parent is `origin/main`; `HEAD`, the resident's
   current branch and the working tree are all untouched; the outbox
   record carries `finding-outcome: filed`, a `finding-commit`
   matching the branch tip, and names the branch and the path in its
   body.
2. **The refs reasoning holds.** Asserted on every scenario, not just
   the happy one: the outbox record's `refs` is the worker result
   alone, and the request id appears nowhere in it. Then the guard
   itself, stated as a test — a hand-written outbox record naming the
   request is built by copying a real one and rewriting that line, and
   `castle validate` must refuse it and cite this brief. Without that,
   §5's paragraph is a comment.
3. **An empty finding file produces nothing** — no branch, no outbox
   record, no commit, and a turn that is otherwise completely
   ordinary.
4. **A bad `Destination:` produces the named refusal** —
   `refused-destination-unknown`, no branch, the finding verbatim in
   the record body.
5. **A dirty checkout produces the named refusal** —
   `refused-tree-dirty`, with a count and status letters in the body
   and no file name.
6. **An unconfigured mechanism checkout produces the honest result
   text** — `CASTLE_MECHANISM_ROOT` unset, `finding-outcome:
   refused-destination-unconfigured`, and a body naming
   `castle.agent.repo.mechanism` and carrying the finding.
7. **A malformed finding and a taken name** — `refused-malformed` for
   a body with no header and for one with no `Title:`, and
   `refused-already-there` for a slug that already exists on
   `origin/main`. The fixture checkout is built with `git archive`
   from this repository's own `HEAD`, so "already exists" means a real
   backlog entry rather than a planted one.
8. **The digest and the status surface both report a filed finding**,
   naming the branch and the checkout — the reporting half of §4's
   authority tier, which is the half a test can actually hold.
9. **The scratch file is allocated and cleaned up.** `outbox.sh`
   asserts `$CASTLE_STATE_DIR/work` is empty at the end of the run;
   `dispatch-test.sh`, where 0039's equivalent assertions already
   live, has its scratch witness extended so the tenant reports all
   three handed-over paths and all three are checked to be under the
   state directory.

Three existing harnesses invoke `agent/castle-worker-claude` directly
with stub deliverable paths — `dispatch-test.sh`, `resume.sh` and
`config-target.sh` — and each gains a `CASTLE_FINDING_FILE` beside the
two it already sets, for the reason 0039 recorded when it made the
same kind of edit: stating "this fixture is configured the way this
task requires" is right, where exempting the fixture from the
mechanism standing next to it would not be.

`castle validate` runs over the finished journal at the end, as every
harness here does, and `nix flake check` runs in CI.

### What only a live dispatched errand on the reference host proves

That a **sandboxed** tenant can write the third file. No harness in
this repository runs one — this is exactly the gap 0039's own
verification plan names, and the third deliverable inherits it whole.
The pass condition is a real dispatched errand, with
`castle.agent.worker.command` at its default and a mechanism checkout
configured, whose turn produces an outbox record with `finding-outcome:
filed`. Do not simulate it.

It also proves the half of the format that no test can: whether a
model handed the prompt paragraph in §2 actually produces a
backlog-shaped entry rather than a summary of its own turn. That is a
judgment about prose, and the first few findings should be read as
prose before this lane is trusted unattended.

### What a human must eyeball

- **The digest line.** Run `castle digest` over a period containing a
  finding and read it: the `finding-outcome` line, the record's body,
  and that the branch and path are legible to someone who did not
  write this code.
- **The branch in the checkout.** `git log --oneline origin/main..
  castle/finding/<slug>` in the mechanism checkout, and
  `git show` on the commit. Confirm one commit, one file, the right
  parent, and that the resident's own branch and working tree are
  where they left them.

## Judgment calls

Reported here because the instructions that produced this brief left
them open and a reviewer might have decided differently.

1. **The task was read as full implementation, not spec-only.** The
   instructions ordered "write the brief" first and then "tests:
   extend `test/agent-loop/`", which reads as code rather than as a
   description of code. The brief, the mechanism, and the harness all
   land on this branch together.
2. **`refused-no-base` and `refused-already-there` are mine.** The
   instructions named three refusals (bad destination, dirty checkout,
   unconfigured checkout). A total function has to answer for a
   checkout with no `origin/main` and for a slug that is already
   taken, and inventing a fallback for either would be judgment. Both
   are refusals with the finding preserved.
3. **`refused-malformed` too**, for a finding with no parseable header
   — including one with no `Destination:` at all. See Considered and
   rejected on why an absent destination is not defaulted.
4. **`provenance: initiated` rather than inherited.** Every other
   record `run_worker_turn` writes inherits the request's provenance,
   and the docstring for that says provenance records who wanted the
   work rather than who started it. Applying that rule honestly to a
   finding gives `initiated`, and the visible consequence — the digest
   rather than a notification — is the reporting cadence §4 argues
   for. A reviewer who thinks a finding should interrupt the resident
   would change one word here.
5. **The finding's bytes go in the record body on refusal paths.** §6
   argues this is compatible with the byte-fidelity entry rather than
   in tension with it. The alternative considered was a journal
   sidecar file with a digest field, mirroring `.patch` and
   `patch-sha256` from 0033; rejected as disproportionate for prose
   nothing mechanical reads, and as a second sidecar mechanism
   `castle validate` would then owe a check.
6. **The commit is built with git plumbing rather than by reusing
   `_build_commit`.** That helper takes a patch file and runs `git
   apply --cached`; using it would have meant synthesising a
   creation-patch from the finding's bytes, including its line counts
   and its no-trailing-newline marker, which is a byte-fidelity hazard
   invented for no gain. `hash-object -w` takes the bytes as they are.
   The two functions share `_run_git`, `GIT_ISOLATION_ARGS` and the
   private-index discipline.
7. **`_run_git` is not modified.** `hash-object` needs the finding's
   bytes, and `_run_git` runs in text mode with no stdin channel. The
   outbox writes the bytes to a scratch file under
   `work_scratch_dir()` and passes its path, rather than adding a
   binary-stdin parameter to a helper whose docstring carefully scopes
   what it does. The scratch file is unlinked in a `finally`.
8. **The status line is added to `run_status` only**, not to inbox
   mode. Inbox is the surface for things *waiting* on the resident,
   and a filed finding is waiting on nothing.
9. **`finding-branch` and `finding-destination` became fields during
   implementation**, and this section of the brief was rewritten to
   match rather than left describing the design it started from. The
   first draft kept both in body prose on the grounds that nothing
   keyed on them; writing §4's status line made that false in the same
   commit, and a surface grepping a body for the branch name is the
   exact defect `apply-commit` exists to have already fixed once.
10. **The reaper scenario in the verification plan became an
    assertion on the refs plus a rejected forgery.** The plan as
    drafted called for driving a dangling claim through a dispatch
    sweep to prove the outbox record does not close it. Rewritten
    during implementation: `dispatch-test.sh` already owns the
    reaper's scenarios, and re-staging one here would have coupled
    this harness to that machinery to prove a property that is
    exactly "these refs, and no others". The direct assertion plus
    `castle validate` refusing a forged record covers it without the
    coupling — but a reviewer who wants the end-to-end version should
    say so, because it is the stronger test.
11. **The outbox runs last in the turn, behind a catch-all.** It is
    the newest and least load-bearing lane; the proposal question and
    the byte-exact sidecar are the oldest and most. An unexpected
    exception in the outbox must not cost a turn its proposal, so it
    runs after both and an escaping exception becomes a line on
    stderr rather than a raised turn. This is the one place the
    "never silently drop" rule is relaxed, and only for faults
    outside `finding-outcome`'s vocabulary — every reachable outcome
    writes a record.
12. **The `[[…]]` link in
   `docs/backlog/the-worker-cited-a-rule-its-contract-does-not-
   contain.md` now points at this brief** rather than at a deleted
   entry. (That entry has itself since been promoted to
   `docs/tasks/0043-worker-contract-revision.md`, which deleted it —
   the path above is where it lived, not where it is.) The
   `chevaline-example/` half of the second promoted
   entry is re-filed as
   `docs/backlog/the-example-profile-has-no-work-section.md` so that
   promoting the parent does not silently delete undone work.
