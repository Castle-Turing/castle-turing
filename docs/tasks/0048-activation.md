# Task 0048 — Castle rebuilds the machine it is running on

**Before starting:** read `CLAUDE.md` in full, and
`.claude/skills/implement-brief/SKILL.md`; both bind everything below.
Then `docs/vision.md` and both numbered principles. Then, closely:
`docs/tasks/done/0025-approval.md` — the review flow this task's
question rides, and the exact-wording discipline it is held to;
`docs/tasks/done/0026-apply-validate.md` — the applier, whose species
of plumbing seat this task adds two siblings to, and whose reasoning
about refs, one-attempt bounds and `outcome`-versus-`apply-outcome`
this task copies rather than reinvents;
`docs/tasks/done/0033-byte-exact-proposal.md` — why an artifact a
resident authorized is carried as bytes and not as a description;
`docs/architecture.md`'s Applier, Outbox and "Where runtime state
lives" sections; `modules/agent/default.nix` in full;
`docs/backlog/headless-recovery.md` (cited here, deliberately not
promoted); and
`docs/backlog/vm-fixture-never-shows-the-boot-menu.md` (which named
this task's predecessor as its consumer — §L records the call).

**This is the resurrection of 0027, which never landed.** The gap at
0027/0028 in `docs/tasks/done/` is that history. Its pre-0025
exhaustion analysis is obsolete and is not a source; the design below
was settled fresh with the resident on 2026-09-03 and is recorded here
as decided rather than as proposed.

## Why

Everything the agent layer can do today stops at the edge of the
running system. A worker proposes a diff; the resident approves it;
the applier makes the change in the private configuration repository
and commits it there. Then the sentence every one of those surfaces
ends with is the same one: *nothing was activated*. The machine keeps
running the generation it was already running, and the last step —
`nixos-rebuild switch` — is a thing the resident types by hand or the
change never happens at all.

That is the correct place to have stopped. It is not a good place to
stay. A system whose whole argument is that a resident's configuration
is legible, reviewable and rollbackable, and which cannot reach the
one command that makes a reviewed configuration real, is a system that
has automated the cheap half of the loop and left the half that costs
attention. The applier's own record says so in every body it writes.

This task closes that loop, and it is the first time anything in this
project acquires a lever over the machine it is running on. Three
things follow from that, and they are the design rather than
decoration:

- **Building is free and activating is not.** A build changes nothing.
  It costs electricity and disk and tells the truth about whether a
  configuration is real. There is no reason to ask permission for it
  and every reason not to: a question a resident cannot meaningfully
  refuse is a question that trains them to say yes.
- **The authority spent is exactly what the resident was shown.** The
  0025 discipline, unchanged and now load-bearing in a harder place:
  the boundary statement on the review screen is the scope of the
  grant, absence of a stamp is the positive fact that a proposal was
  offered under a narrower statement, and no later change of wording
  reaches backwards.
- **A switch that cannot be confirmed is undone.** The asymmetry is
  the whole argument for the health window and is stated in §E.

## The design

### §A. Two seats, and why they are two

**Builder** (plumbing, not a reasoning seat). It notices that a build
is owed, builds it, and files either an honest failure or a question.
It holds no judgment about whether the build is worth doing, spends no
authorization, and touches nothing outside `/nix/store` and a
throwaway git worktree it removes.

**Activation** (plumbing, not a reasoning seat). It spends exactly one
recorded approval: it writes the pin bump the resident authorized, if
there was one, commits it, and asks the system to switch to the
configuration that produces. It reasons about nothing and chooses
nothing.

Two seats and not one, for the reason the applier's own paragraph
gives about its name: a seat is what reads and writes, and these two
write incomparable things. The builder writes a store path. The
activation seat writes the resident's repository and the running
system. "Which seat changed the machine I am using" has to have an
answer that is not also the answer to "which seat compiled
something".

**This paragraph exists to stop a later agent completing either of
them into a reasoning seat.** Giving the builder a policy about which
triggers are worth building, or the activation seat a policy about
which approvals are worth spending or a say in whether to spend one at
all, would make it a reasoning seat. Neither may acquire one. What
each does is a total function of the journal and the tree, and a
re-run of the same fold over the same snapshot reaches the same
answer.

### §B. The two triggers

The builder sweep looks for exactly two facts, in this order, and
builds at most one candidate per sweep.

1. **An applied private-layer change.** The newest applier result
   whose `apply-outcome` is `applied-validated` or
   `applied-unvalidated` and which no builder result names in its
   `refs`. The resident's configuration repository has moved and the
   running system has not; that is the whole trigger.

2. **The pin is behind.** The private flake's `flake.lock` pins the
   framework input (`castle.agent.activation.frameworkInput`, default
   `castle-turing`) at a revision that is not the one
   `refs/remotes/origin/main` names in the configured mechanism
   checkout.

   **No fetch, ever, from this seat.** The outbox's rule verbatim and
   for its reason: a fetch is network with nobody watching, and what
   `origin/main` means here is "what the last fetch saw". A host with
   no `castle.agent.repo.mechanism` configured never fires this
   trigger at all, and the record says so rather than the trigger
   silently not existing.

Both bounds are "does a record exist", never a timestamp and never a
counter, for the reason `_eligible_approvals` gives: a bound expressed
as the presence of a record cannot be reset by anything short of
writing history. Trigger 1 is barred by any builder result naming that
apply result. Trigger 2 is barred by any builder result carrying
`build-target-rev: <sha>` for that revision — including a failed one.
A build that failed does not get retried automatically; the conditions
that produced it do not clear themselves, and a loop that rebuilds a
broken revision every minute is the failure mode this bound exists to
make impossible.

**Amended during implementation, and the harness is what found it.**
Trigger 2's bound is lifted for a revision whose *activation* refused.
A refusal is a record saying the world moved between the build and the
switch — the repository gained a commit, its lock went dirty — so a
rebuild after one is not a retry of the same attempt but a build
against a different base. Without the exception the first refusal
barred that revision forever and the resident had to notice and drive
it by hand, which is exactly the silence this whole mechanism exists to
remove. It cannot run away: a rebuild files a question and stops, so
nothing reaches a refusal again without a deliberate human approval in
between.

**The dirty check before a pin bump is scoped to `flake.lock` and
`flake.nix`, never repo-wide**, and this too is a correction made
against the code rather than against the brief's first draft.
`_dirty_entries` documents at length why a repo-wide check refuses
forever on residents who did nothing wrong — a `state/` submodule
dirties the outer gitlink on every journal commit, an un-gitignored key
file shows as untracked. What that concedes is stated in the record
rather than hidden: a pin candidate is built from the repository's
committed state, so uncommitted edits elsewhere are not in it, and the
build result names the commit it was made from.

### §C. A failed build files a result and asks nothing

`build-outcome: build-failed`, `outcome: failed`, the tail of the
build log (`APPLY_LOG_TAIL_LINES` worth, the same screenful the
applier keeps and for the same reason), and no question. There is
nothing here to approve: the resident is not being asked to authorize
a broken build, they are being told one happened. It routes through
the ordinary channel like any other result.

The other refusals — no mechanism checkout, an unresolvable pin, a
private tree with uncommitted work on `flake.lock`, `nix` not on
`PATH` — are the same shape: a result, an honest first line, no
question. `refused-*` names, matching `APPLY_OUTCOME_VALUES`'
convention exactly.

### §D. A clean build files an activation question

Two records, in this order, and the second is written only if the
first landed — `_file_proposal_question`'s sequencing and its failure
posture, copied:

1. A **result**, `seat: builder`, `build-outcome: built`, carrying the
   store path of the closure that was built (`build-toplevel`), and —
   on the pin-bump trigger only — the exact bytes of the new
   `flake.lock` between a nonce diff boundary, stamped `lock-sha256`.

   **`lock-sha256` and not `patch-sha256`**, which is what this brief
   said before the harness ran. `patch-sha256` means something exact
   since docs/tasks/0033: there is a `<result-id>.patch` sidecar file
   beside this record and this is its digest, and `cmd_validate`
   condemns a record carrying the field without one. Same purpose,
   different location, so a different name.
   The prose above the boundary names what is being adopted: the
   revision, how many commits it is ahead, and the subject line of
   each merge commit in that range. Titles, not shas, because a
   resident deciding this is deciding about work, not about hashes.

2. A **question**, stamped `proposal-sha256` over that result's exact
   bytes and `authorizes-activation: true`.

`refs` on the question are `[anchor, build_result_id]`, where the
anchor is the build result's own first ref when it has one — the
apply result, on trigger 1, so the lineage walk reaches the errand
that started all this — and the build result's own id otherwise. A
pin bump has no antecedent record anywhere in the journal; it is its
own lineage root, and saying so by self-reference is honest where
inventing a parent would not be. `_find_root_request` and
`_collect_downstream` both carry `seen` sets and are unharmed.

`refs[1]` is the result, because `file_answer` binds a decision to
`question.refs[1]` and re-derives its hash from disk at write time.
The activation question is a proposal in every mechanical sense the
0025 machinery already understands, and nothing about that machinery
changes.

### §E. The boundary statement, and the health window

A third boundary statement joins the two `castle-modal` already
carries, selected by `authorizes-activation` exactly as the second is
selected by `authorizes-apply`. The two existing statements are
untouched: they are what residents were told, and for questions
carrying neither new stamp they remain true forever.

The new one says, and must keep saying:

- **approving switches the running system to the build described
  below** — the boundary sentence the resident's own instruction
  specified, in those words;
- what a pin bump additionally authorizes, when the question is one:
  writing the new `flake.lock`, committing it in the private
  repository, and switching. One question, one act. It still pushes
  nothing;
- **what `switch` cannot fully apply.** A kernel, initrd, or firmware
  change is staged into the new generation and takes effect at the
  next boot, not now; a `switch` that succeeds does not mean the
  machine is running every part of what was approved. This goes in the
  question's own body text as well as the boundary statement, because
  the body is what a digest and a notification carry;
- **the health window, in the same breath as the approval.** After the
  switch, Castle asks whether the machine is working. If nothing says
  so within the window, Castle rolls back to the previous generation
  on its own.

That last one is the one place this surface deliberately contradicts
the sentence the other two statements end with — "nothing expires, and
nothing decides on your behalf". Here something does expire and
something does decide, and the screen says so rather than inheriting a
promise it cannot keep.

**The asymmetry that makes automatic rollback right.** A good
generation rolled back costs one cheap re-approval: the resident says
"actually it was fine", approves again, and the machine switches
again in seconds. A bad generation left running costs a USB-stick
round trip — a machine with no network, no display, or no working
castle cannot be told anything at all
(`docs/backlog/headless-recovery.md`, whose 0003 incident is the
concrete form of this). The two failure costs differ by orders of
magnitude and the default belongs on the cheap side. That is the
argument; it is not a preference about caution.

**What counts as confirmation.** The switch files a second question —
"Castle switched this machine to the new configuration; is it
working?" — carrying `confirms-activation: <activation-result-id>`
and stamped `proposal-sha256` like the first, so it rides the same
review surface and the same notification. Approving it is the
confirmation. Rejecting it rolls back immediately rather than waiting
out the window. Setting it aside decides nothing, and the window still
expires — which the boundary statement says outright, because a
`defer` that silently triggers a rollback would be exactly the label
that causes the outcome it does not describe (docs/tasks/0015).

A notification click reaches this question through the machinery
0034 already built: the router notifies, the waiter opens the modal
deep-linked to the record, and the record is a question the review
surface knows how to decide. No new surface, no new deep-link kind,
no new keypress.

### §F. The records this task writes

`build-outcome`, result-only, closed vocabulary:
`built`, `build-failed`, `refused-no-mechanism-checkout`,
`refused-pin-unresolvable`, `refused-tree-dirty`, `refused-no-nix`.

`activation-outcome`, result-only, closed vocabulary:
`switched`, `switch-failed`, `confirmed`, `rolled-back`,
`rollback-failed`, `refused-pin-stale`, `refused-tree-dirty`,
`refused-no-privilege`.

`build-toplevel` (result-only) — the store path built. `lock-sha256`
(result-only) — the digest of the `flake.lock` bytes carried in the
body. `build-target-rev`
(result-only) — the framework revision this build adopts, absent on the
applied-change trigger. `activation-commit` (result-only) — the pin-bump
commit, stamped only where a single commit was verified to have landed,
exactly as `apply-commit` is. `authorizes-activation` and
`confirms-activation` (question-only).

`outcome` is not widened and never will be by this task.
`agent/README.md` reserves its four values, and the split the applier
established holds here unchanged: `outcome` is an observation about
the seat's own run, `activation-outcome` is an observation about the
machine. A switch that ran to a recorded refusal is `outcome:
completed`.

No new record type, and no `claim`. A killed activation leaves no
record at all and the next sweep finds the approval still eligible —
except where it may have moved the repository, which §G covers.

**One unconfirmed generation at a time.** The sweep spends no approval
while any health window is open. Two switches stacked would leave a
single rollback between two unconfirmed generations, so the window that
expired would restore the *first* unconfirmed one and call the machine
recovered. This cannot wedge — the window closes at its deadline
whatever anyone does — so what it costs at worst is one window's delay.

### §G. The in-flight marker, unchanged in kind

The activation seat writes a pin bump before it switches, so it has
the same "may have moved the tree and never wrote its account"
window the applier has, and it uses the same mechanism:
`apply_in_flight_path`'s species of breadcrumb, reconciled at the top
of every sweep, before anything fresh. The reasoning is 0026's and is
not re-derived here.

What is new is a second window with no repository in it: a switch
started and never accounted for. The root unit is a systemd oneshot,
so the system journal has the truth even when castle's does not, and
the reconciliation for that window is a comparison rather than a
guess — `readlink /run/current-system` against the `build-toplevel`
the approval named. Equal means the switch happened; unequal means it
did not. Recorded as found, either way.

### §H. Privilege: the first standing root grant in the authority record

Switching needs root. This task records that plainly rather than
burying it in a module: **`castle.agent.activation.enable` is the
first standing root authority in this project**, and until the
authority taxonomy exists as its own document
(`docs/backlog/authority-taxonomy-prior-art.md`) this brief and
`docs/architecture.md`'s "Where runtime state lives" bullets are where
it is written down.

Its scope is two commands and nothing else:

    nixos-rebuild switch --flake <private>#<host>
    nixos-rebuild switch --rollback

The mechanism is a pair of **system** systemd oneshot units carrying
exactly those two `ExecStart` lines, with no argument reaching them
from the resident's session, plus a **polkit rule** permitting exactly
one named user to `org.freedesktop.systemd1.manage-units` on exactly
those two unit names. The resident's user seat signals them with
`systemctl start`, which blocks until the unit finishes and exits
nonzero if it failed, so the outcome needs no side channel.

**Why this and not the alternatives**, all three of which were
weighed against the pinned nixpkgs rather than from memory:

- *A sudoers entry for the exact command.* Narrow in principle, wider
  in practice: a sudoers entry naming a command with no arguments
  permits every argument, so scoping it means either a wrapper script
  whose argv handling becomes the real boundary, or an argument list
  that must be kept in step with what the caller sends. It also
  presumes `security.sudo` is enabled, which is a host's choice.
- *Passing the store path to a privileged helper.* Rejected, and this
  is the load-bearing one: a helper that activates whatever path it is
  handed makes the request channel the security boundary, and that
  channel is a file or an argument any process running as the resident
  can produce. The static unit takes nothing, so there is nothing to
  forge.
- *A root daemon that reads the journal itself.* Rejected for the same
  reason one layer further in: it makes a resident-writable directory
  the input to a root process, permanently.

**The cost of the static unit, stated rather than hidden.**
`nixos-rebuild switch --flake` re-evaluates; it does not activate a
store path handed to it. So the closure that gets activated is not
*by construction* the closure the resident was shown. It is in
practice — the private repository is committed, its lock is pinned,
and the pin bump is committed before the switch is asked for — and
where it is not, the mismatch is caught rather than assumed: the
activation result records the `build-toplevel` it was approved for
alongside `readlink /run/current-system` after the switch, and says
plainly when they differ. A recorded, checkable mismatch is a better
trade than a forgeable privileged argument.

### §I. The health window's timer runs as root, and what that costs

The window is a system timer (`OnActiveSec`, started by the activation
unit's own `ExecStartPost`) firing a system oneshot that runs
`castle activate --close-window`. It has to be root, because what it
may need to do is roll back.

That means one code path in `castle` runs as root and writes to the
resident's journal. Records it writes are chowned to the journal
directory's owner immediately after landing, so a root-written record
does not quietly make the state repository unusable to the resident
who has to commit it. This is the only such path, and it is named
here so nobody adds a second by analogy.

The window never has to be cancelled. On confirmation it fires,
observes the confirmation, writes `activation-outcome: confirmed`, and
does nothing else — which is why the polkit grant needs no third unit
and no `stop` permission.

### §J. Nothing pushes

`docs/architecture.md`'s push bullet stands unamended. The pin-bump
commit is local. A resident whose private repository has a remote
pushes it themselves, exactly as they do for every applier commit
today.

### §K. Verification

**In CI, on every push** — `test/agent-loop/activation.sh`, a sibling
of `apply.sh` and `outbox.sh` and the same species: real `castle`,
real `git`, real journal, plain bash and stdlib python3, no Nix, no
models, no network. Every `nix`, `nixos-rebuild` and `systemctl` in it
is a stub that logs its own argv, and the argv comparison is the
assertion. It proves, end to end: both triggers firing and both
one-attempt bounds holding; a failed build filing a result and no
question; a clean build filing a question carrying the exact stamps;
the review surface printing the activation boundary statement and not
either of the other two; an approval spending exactly once; the
pin-bump bytes landing byte-exact in one commit; the switch being
asked for with the argv the module declares; the confirmation path
writing `confirmed`; and the window expiring unconfirmed writing
`rolled-back` after asking for the rollback command.

**In CI, cheaply** — `nix flake check` proves the new options and
units evaluate. The check job additionally reads the *generated* unit
files and the generated polkit rule and asserts their content, because
`nix flake check` proves evaluation and not that the generated
artifact says the right thing (the lesson `sway --validate` taught
this project once already), and `nixosConfigurations.example-activation`
asserts the generated units and the generated **polkit rule text**. That
last one matters most: a rule matching the action id and not the unit
name would grant this user start/stop/restart over every unit on the
machine and evaluate exactly as cleanly.
`nixosConfigurations.example` carries the matching default-off proof,
covering the units *and* the rule — a grant nobody uses is still a
grant.

**What only a real host proves, named as human steps.** That
`nixos-rebuild switch` succeeds on real hardware; that the polkit rule
actually permits the start on a live session; that the notification
click reaches the health question; that a kernel change stages rather
than applies. These are reference-host steps and the brief does not
pretend otherwise.

### §L. The boot-menu backlog entry: not promoted, and why

`docs/backlog/vm-fixture-never-shows-the-boot-menu.md` was filed
naming this task's predecessor as its consumer, on the expectation
that the rollback story would lean on the bootloader menu. It does
not. **This task's rollback is `nixos-rebuild switch --rollback` on a
running machine**, which never reaches a bootloader at all: the
previous generation is selected by the system profile, not by a menu.
The menu is the recovery path for a generation that will not *boot*,
which is `docs/backlog/headless-recovery.md`'s territory and stays
there.

So the entry stays filed, its 0027 references are corrected to name
this task, and a paragraph is added recording that its named consumer
arrived and did not need it. The fixture's `boot.loader.timeout = 0`
is untouched, and `test/vm-install`'s timing assertions are therefore
not re-tuned by this task — the condition that entry set for changing
them never arose.

The half of its question that this task *would* have wanted — "the
previous generation is present and selectable after an activation" —
is not provable in `test/vm-install` for a different and more
important reason: `hosts/vm-test` deliberately imports no agent
module, and that is the anti-bricking regression test rather than an
oversight. Proving a real activation in a VM needs a fixture that
imports the agent layer, which is the `test/desktop-loop` family's
shape rather than this one's. That leg is filed as a backlog entry by
this task rather than half-built inside it.

## Judgment calls

Recorded because this task grants the system its first real lever over
itself, and the wording choices are the authority record.

1. **Two seats rather than one.** The instruction said "a new plumbing
   seat of the applier's species", singular. Building and switching
   are split into `builder` and `activation` because they write
   incomparable things and because a build must be able to happen with
   no authorization anywhere near it. Recorded as a deviation.
2. **The health confirmation is a proposal-shaped question, decided
   with the existing approve/reject/defer keys**, rather than a new
   record type or a new `castle confirm` verb. It reuses the review
   surface, the notification deep-link and the answer write path
   whole. The cost is that `defer` acquires a meaning it does not have
   anywhere else — decides nothing, window still expires — which the
   boundary statement therefore has to say explicitly.
3. **The activation question self-anchors on the pin-bump trigger**
   (`refs[0] == refs[1] == the build result`). A pin bump has no
   antecedent record; inventing a synthetic request to be its parent
   would put a fabricated errand in an append-only journal.
4. **The new lock is carried as whole bytes, not as a diff.** A
   `flake.lock` is generated JSON; a resident reads the prose above it,
   not the JSON, and the activation seat needs bytes it can write
   verbatim. Embedding both a display diff and application bytes would
   be two copies of one artifact.
5. **`--override-input` was dropped during implementation, and the
   check that replaced it is stronger.** The override would have meant
   reconstructing a flakeref from the lock's `original` node — a parser
   this task would own forever. Instead `nix flake update <input>
   --flake <worktree>` runs unconstrained and the *result* is checked:
   the revision the new lock names has to be the one the framework
   checkout's `origin/main` names, or the build refuses and says the two
   disagree. That also catches the case an override would have papered
   over, where upstream and the local checkout genuinely differ. What
   remains unprovable in CI is the spelling itself — that `nix flake
   update <input> --flake <dir>` is what this flake's pinned nix takes.
   The exact command line is recorded in every build result whether it
   ran or not, the applier's own practice, so a resident can paste it.
6. **The pin-behind trigger requires a mechanism checkout and is
   silently inert without one.** The alternative was fetching, which
   this seat may not do. A host with no mechanism checkout gets the
   applied-change trigger only, and the option's description says so.
7. **The working tree is synced by writing the file and updating one
   index entry, not by `checkout-index` or `read-tree`.** Found by the
   harness: the commit is built in a private index, so `checkout-index`
   restores what the *real* index still says — the old lock — and
   `read-tree` would discard anything the resident had staged
   elsewhere. One path in, one path out.
8. **One user-unit trio, not two.** Build and activation share one
   sweep, one path unit, one timer, because they are one seat's
   concern and serialize naturally. The applier's argument for its own
   trio — that a build inside the *dispatch* sweep would stall every
   errand — does not apply between these two.

## Stop conditions — what this brief does not decide

- **Any standing or autonomous activation tier.** Every activation
  costs one approval, every time. Widening that is the resident's
  later act, on evidence from this mechanism's own track record, and
  the record this task leaves is exactly the evidence such a decision
  would need.
- **Pushing.** Out of scope by name.
- **The installer image**, and any interaction between activation and
  a fresh install.
- **Disk encryption interactions** (`docs/backlog/disk-encryption.md`).
- **Where the authority taxonomy puts a standing root grant.** This
  brief says what the grant is and what it is scoped to; which of
  silent / made-then-reported / queued-for-approval it belongs in
  stays with the taxonomy task, exactly as the three bullets in
  `docs/architecture.md` already defer.
- **Garbage collection and generation retention.** Rollback needs the
  previous generation to still exist; nothing here manages that, and
  the default NixOS retention is what holds.

## Considered and rejected

**Asking permission to build.** Rejected in the design's first
sentence. A question whose only honest answer is yes is a question
that teaches a resident to stop reading questions, and this project
has one screen where that habit would be expensive.

**Rolling back by selecting a generation at the boot menu.** That is
the recovery path for a machine that will not boot, and it needs
somebody physically present. The window this task closes is a machine
that boots fine and is broken in some other way — no network, no
display, no castle — where a running-system rollback works and a menu
is unreachable.

**A confirmation that defaults to "keep".** That is the same design
with the asymmetry reversed, and §E is the argument against it.

**Activating a store path handed to a privileged helper.** §H.

**Widening `outcome`.** §F, and `agent/README.md`'s reservation.

## Hard constraints, restated

No personal data anywhere: no usernames, hostnames, paths, or
revisions belonging to a real machine, in code, docs, fixtures or
commit messages. Every string in the harness is invented; the
placeholder conventions this repo already publishes (`resident`,
`<you>`, `example.invalid`) are the only ones used.

Principle 01: the mechanism is public and the configuration is
private. The units, the polkit rule, the boundary statement and the
sweep are mechanism. Which user holds the grant, which private
repository, which host, how long the window is, and whether any of it
is on at all are configuration, and every one of them defaults off or
null.

Principle 02: nothing person-shaped is required to evaluate this
module. Every assertion this task adds sits inside a branch a resident
opted into.

`hosts/vm-test` imports no agent module and this task does not change
that.

## File-by-file change list

- `docs/tasks/0048-activation.md` — this brief.
- `agent/castle` — the two seats: constants and their reasoning, the
  trigger fold, the builder, the activation seat, the window closer,
  the `castle build` and `castle activate` subcommands, and
  `cmd_validate`'s rules for every new field and both new seats.
- `agent/castle-modal` — the third boundary statement, the third
  approve-confirmation line, and the inbox vocabulary for the two new
  question shapes.
- `agent/README.md` — the new fields and seats in the vocabulary
  reference.
- `modules/agent/default.nix` — `castle.agent.activation.*` options,
  the user unit trio, the two system units, the window timer and its
  service, the polkit rule, and the assertions.
- `docs/architecture.md` — the two seat paragraphs, and the standing
  root grant recorded beside the existing standing-authority bullets.
- `test/agent-loop/activation.sh` — the harness.
- `.github/workflows/check.yml` — the job that runs it, and the
  generated-artifact assertions.
- `docs/backlog/vm-fixture-never-shows-the-boot-menu.md` — corrected
  and annotated per §L, not deleted.
- `docs/backlog/activation-is-not-proven-on-a-real-vm.md` — new, the
  deferred leg §L names.

## Verification plan

Automated, no human: `test/agent-loop/activation.sh` in CI on every
push; `nix flake check`; the generated-unit and generated-polkit
assertions in the check job.

Human, on the reference host: turn `castle.agent.activation.enable`
on, let a build happen, read the review screen, approve, watch the
machine switch, confirm from the notification. Then do it again and
say nothing, and watch it roll back.

## Implementation prompt

Read `CLAUDE.md`, this brief in full, and the four documents its
preamble names. Then implement the file-by-file list. Do not widen
`outcome`. Do not touch `hosts/vm-test`. Do not push. Record every
judgment call the brief left ambiguous in the session's decision log,
and update this brief in the same branch if the design shifts.
