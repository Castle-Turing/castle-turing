# Task 0030 — State lives outside the flake

**Before starting:** read `CLAUDE.md` in full;
`docs/backlog/private-layer-lands-in-the-world-readable-store.md` (this
task promotes it — delete it in the same commit, per that directory's
own README); `docs/private-layer.md` in full, especially "The agent's
state" (~line 452 onward); `docs/architecture.md`'s "Where runtime
state lives"; `docs/principles/01-open-by-construction.md` and
`02-the-resident-owns-the-configuration.md`. Then, closely: `agent/castle`'s
`state_dir()`, `journal_dir()`, `cmd_validate`, `cmd_digest`, and the
existing `.git`-detection pattern in `_checkout_fault` (~line 2447
onward, `docs/tasks/0024-config-target.md` §16) — this task's new check
follows that function's own established convention of testing the
filesystem before ever reaching for a `git` subprocess, for the same
reason: `git` is optional (`modules/dev`), not guaranteed on `$PATH`.
Also `modules/agent/default.nix`'s `stateDir` option in full, and
`docs/tasks/0024-config-target.md` §8 for the related finding and its
supersession note (skim; do not re-absorb the whole brief).

Work on branch `sprint/0030-state-outside-the-flake` (already created,
carrying this brief; do not rewrite it silently — if implementation
surfaces a genuine deviation, say so prominently and amend this brief
in the same PR, per `CLAUDE.md`'s rule that a brief the work overtakes
gets corrected in place, not left stale). **This branch is cut from
`sprint/0024-config-target` at `7360333`, and 0024 is not yet merged —
it stacks on 0024.** Scope every diff and review against
`origin/sprint/0024-config-target`, not `origin/main`, until 0024
lands; `git fetch` first. Open the PR against `sprint/0024-config-target`.
If 0024 merges to `main` before this one is ready, rebase onto `main`
and re-point the PR before opening it, and say so in the PR description.

**Goal.** Stop recommending a private-layer layout that publishes a
resident's decision journal to the world-readable Nix store on every
`nixos-rebuild`; add a check that tells a resident who already followed
the old recommendation; and document how to move.

## Why

### The mechanism, reproduced

`/nix/store` is a single global directory, root-owned, every file mode
`r--r--r--` — a shared cache of build inputs and outputs with no
per-path permissions and no way to add any. Evaluating a **path
flakeref** — `nixos-rebuild --flake /path/to/private#host`, the
documented way to use Castle Turing — copies that flake's entire
**tracked** git tree into it.

Reproduced for this brief: a file committed at `state/journal/rec.md`
in a fixture flake appeared at
`/nix/store/<hash>-source/state/journal/rec.md`, mode `-r--r--r--`,
after a single `nix eval` — no build, no `nixos-rebuild`. An
**untracked** file at the same path was not copied; the exposure is
exactly the tracked tree, nothing more and nothing less. This
corroborates the identical finding `docs/tasks/0024-config-target.md`
§8 made independently while removing a different piece of machinery
(a worker-side `nix eval`) — two unrelated tasks, two reproductions,
same mechanism.

`docs/private-layer.md`'s "The agent's state" section (as it reads
today) tells a resident to create `state/` — `journal/` (one file per
record: every request, decision, result, question, answer, and
correction) and `resident-model.md` (one entry per fact about the
resident, with provenance) — **inside the private repo**, the same
repo whose `flake.nix` gets evaluated on every rebuild. So the
documented layout makes the resident's decision history a compiler
input: published on every `nixos-rebuild`, immutable in the store
until garbage collection, and accumulating one fresh snapshot per
distinct content, in a place the resident has no reason to think holds
any of it.

### What this is, and is not

**This is one documented layout decision, not an architectural flaw.**
Seats, the journal-as-files design, the record schema, and the
`stateDir` option are all untouched. `stateDir` already resolves to an
absolute path the CLI does not interpret — it does not care whether
that path sits inside a flake, beside one, or nowhere near one. The
only thing wrong is what `docs/private-layer.md` tells a resident to
point it at. Overstating this as a structural defect in the agent
layer would be exactly as wrong as the backlog entry's original
omission was; say it plainly and move on.

### The threat model this actually names, corrected

The backlog entry's own draft of this argument reached for "an AI
tenant could read the journal off the store." That argument is weak
and should not survive into this brief unchanged: the worker tenant
runs as the resident's own user and can already read the journal at
its real path, `$CASTLE_STATE_DIR`, with no store detour required. A
store copy grants that tenant nothing it did not already have.

What the store copy uniquely breaks is the **user boundary** — every
account and process that is *not* the resident but shares the machine
or a machine class with them: another local account, a shared VPS's
other tenants, a work laptop's IT-managed monitoring agent, any
process on any box where "no one else uses this machine" is not
true. Principle 01's whole premise is strangers adopting this
framework, so the threat model is every machine an adopter runs it on
— not the reference host, which happens to have one account and one
user and is therefore the least representative machine to reason
about this on. That is the resident's own correction to an earlier
framing of this finding, and it is the argument that decided this
design, not the AI-tenant framing the backlog entry led with.

## The design

### 1. The documented layout changes

`docs/private-layer.md`'s "The agent's state" section (lines 452–501)
is rewritten. The `state/`-as-a-subdirectory-of-the-flake-repo tree
diagram and its surrounding prose are replaced with two layouts, one
recommended and one documented as an accepted alternative. Neither
changes what `stateDir` is or how the CLI resolves it — both are
choices about what path a resident points `stateDir` *at*.

**Recommended: a sibling git repository.** `state/` moves out of the
flake's tracked tree entirely, into its own repository beside the
config repo rather than inside it:

```
~/private/               your existing flake repo — resident.nix, flake.nix, flake.lock
~/private-state/         a second, separate git repository
  journal/                 same contents, same schema, same append-only
                            discipline as today
  resident-model.md
```

```nix
castle.agent.stateDir = "/home/<you>/private-state";
```

Every property the current placement was chosen for —
`docs/architecture.md`'s "survives a reinstall, moves to new
hardware, moves with a change of which model holds the worker seat,
one `git commit` per turn is the audit trail" — comes from **git**,
not from cohabiting with the flake. None of it is lost by splitting
the repository; a `git clone` restores this repo exactly as it
restores the config repo. The cost is real and stated plainly: two
repositories to `git commit` (and, per the existing "pushing stays
manual" rule, to push) instead of one.

**Documented alternative: a git submodule at `state/`.** Verified for
this brief: with `state/` wired in as a submodule of the private repo,
the flake's store copy contains **no `state/` directory at all** — the
submodule's content is provably excluded, because a plain path
flakeref does not fetch submodule contents. This keeps one clone and
one everyday `git` workflow (`git submodule update`, ordinary `git
status` inside `state/`), at the cost of the two-step submodule
mental model.

Document the caveat beside the recommendation, not as a footnote: the
exclusion holds **only** because Nix does not fetch submodules for an
ordinary path flakeref. A flakeref written with the `?submodules=1`
query parameter defeats it and re-includes the submodule's content in
the store copy — silently, from the resident's point of view, since
nothing about `nixos-rebuild --flake /path#host` versus
`--flake "/path?submodules=1#host"` looks alarming. `docs/private-layer.md`
must say this explicitly: if you choose the submodule layout, never
add `?submodules=1` to any flakeref that names this flake, anywhere
(a `nixos-rebuild` invocation, a CI job, another private layer's
`flake.nix` `inputs`).

The sibling-repo recommendation is the primary path precisely because
it carries no equivalent footgun — its safety does not depend on how
the flake happens to be referenced.

**`stateDir`'s default does not change.** Unset, `state_dir()` already
resolves to `$XDG_STATE_HOME/castle` (or `~/.local/state/castle`) —
outside any flake, already safe, and unaffected by anything in this
task. This task changes what `docs/private-layer.md` *recommends a
resident set `stateDir` to*, not the code's own unset behavior.

### 2. A runtime guard in `castle`

Rewriting the docs protects a resident who has not yet created
`state/`. A resident who already followed the old recommendation needs
to be told by the tool, not left to notice on their own. Add a pure
check that reports when the resolved state directory sits inside a
flake that gets evaluated.

**The rule.** Add `_state_layout_finding(path: pathlib.Path) -> str |
None` beside `state_dir()`/`journal_dir()` in `agent/castle`:

Resolve `path` to an absolute path, then walk upward. At each
directory, ask one question: does it contain a `.git` entry (file or
directory — a submodule and a linked worktree both carry a `.git`
*file*, not a directory)? **Stop at the first directory where the
answer is yes.** That is the repository root the state directory
lives inside, and it is the only directory this rule asks about next:
does *it* also contain `flake.nix`? If yes, the state directory is
inside an evaluated flake — unsafe, return a message naming both
paths. If no, stop — safe, return `None`, regardless of what sits
above that repository root. If the walk reaches the filesystem root
without ever finding a `.git` entry, no repository contains the state
directory at all — safe, return `None`.

**The rule must stop at the first repository root, not just the first
`flake.nix` found anywhere above.** This is the specific bug the
"stop at the first" clause exists to prevent, traced through all four
cases the check must get right:

- **State inside the flake repo, not a submodule.** `state/` has no
  `.git` of its own. The first `.git` found while walking up is the
  flake repo's own — and it has `flake.nix` right there. **Unsafe.**
- **State as a submodule of the flake repo.** `state/.git` exists (a
  file, pointing at `../.git/modules/state`), so the walk stops
  *immediately*, at `state/` itself. `state/` has no `flake.nix`.
  **Safe.** A version of this rule that did not stop at the first
  repository root — one that kept walking past `state/.git` looking
  for a `flake.nix` anywhere above — would keep going, reach the outer
  flake repo, find its `flake.nix`, and wrongly report this case as
  unsafe. That is precisely the bug "stop at the first repository
  root" exists to prevent, and §4's verification plan turns it into an
  assertion rather than leaving it as prose.
- **State as a sibling repository.** The first `.git` found walking up
  from the sibling repo's `state/` (or from its root, if `stateDir`
  points at the root itself) is that sibling repo's own. It has no
  `flake.nix`. **Safe.**
- **State at the XDG default, nothing versioned above it.** The walk
  never finds a `.git` at all. **Safe.**

**Pure filesystem, no `git` subprocess.** `git` reaches a session only
through `modules/dev`, which is optional — the same reason
`_checkout_fault` (§16 of 0024) tests filesystem state before ever
shelling out. This check never needs git's own answer to "is this a
repository" (unlike `_checkout_fault`, which separately needs to know
whether git can actually *use* a checkout); existence of a `.git` entry
is exactly what the rule above asks, and Python's `pathlib` answers it
with no subprocess and no `$PATH` dependency at all.

**Where it surfaces.** Two call sites, both places a resident already
reads output deliberately, and both chosen by elimination of
everywhere else:

- **`castle validate`.** Already an advisory schema check the resident
  runs and reads a report from (`cmd_validate`'s own comment: "advisory
  and nothing invokes it automatically"). Call
  `_state_layout_finding(state_dir())` once, unconditionally — before
  the `if errors:` branch, so it prints regardless of whether the
  journal itself is schema-clean — and if it returns a message, print
  `WARNING: <message>` to stderr. **This does not change
  `cmd_validate`'s exit code or its error count**: an unsafe layout is
  an environment fact, not a malformed record, and folding it into
  `errors` would make an otherwise-clean journal fail validation for a
  reason `cmd_validate` cannot fix by editing any record.
- **`castle digest`.** Print the same warning, same wording, once at
  the very top of `cmd_digest`'s output — before the "No errands
  recorded" early return and before the per-errand loop — so a
  resident who runs `digest` without ever running `validate` still
  sees it.

**Confirmed: `castle digest` is never run unattended.** Its own
docstring already says so ("Invoked by hand — no scheduling in this
skeleton"), and `modules/agent/default.nix`'s only `systemd.user`
units (`castle-dispatch`, its path unit and timer, and
`castle-dispatch-watermark`) invoke `castle dispatch` and nothing
else — no unit, path, or timer anywhere in this repo runs `castle
digest`. Wiring the warning there does not create a per-minute log
line; the minute-by-minute surface is `castle dispatch`, and this
warning is deliberately **not** added there (see below).

**Explicitly not added to `run_worker_turn`, `castle dispatch`, or any
other CLI invocation.** `castle dispatch` runs every minute under
`castle-dispatch.timer` regardless of whether there is eligible work —
a warning there would either fire once a minute forever (spam a log
nobody reads that often) or need its own de-duplication state, which
is more mechanism than this fact is worth. `validate` and `digest` are
the two places a resident already looks at output on purpose; nothing
else needs the check at all.

**This widens `cmd_validate`'s job, and the widening is argued rather
than done silently.** `cmd_validate` has been a journal *schema*
checker since `docs/tasks/0008-agent-layer-skeleton.md` — every prior
addition to it (the `outcome` vocabulary, the `blocking` scoping, the
`target` field) checked a property of a *record*. This is the first
check of a property of the *environment* the journal happens to sit
in. The case for putting it here anyway: `validate` is already the
one command whose entire job is "tell me what's wrong with my
journal," it is already read as a list of findings rather than a pure
pass/fail, and a resident who has never heard of this task's fix is
exactly the resident who benefits from finding this warning attached
to a command they already run rather than needing to know a new one
exists. The alternative — a dedicated `castle check-layout` or
similar — was considered and rejected; see Considered and rejected.
The widening costs nothing existing: it adds one optional stderr line
and changes no exit code, no existing message, and no existing
behavior for the (currently universal, since `stateDir` unset is the
only shipped configuration) case where the layout is already safe.

### 3. Migration, for a resident who already has the unsafe layout

Add a short "Migrating state out of the flake" subsection to
`docs/private-layer.md`, immediately after the rewritten "The agent's
state" section. Contents, plainly stated rather than glossed:

1. Move the directory: `git mv state ../private-state` (or `cp -r` plus
   deleting the old `state/` and committing the deletion, if a fresh
   sibling repository is being created rather than reusing history) —
   whichever matches the chosen layout from §1.
2. Repoint `castle.agent.stateDir` at the new location and rebuild.
3. Run `nix-collect-garbage` (or wait for the host's normal GC
   schedule) once the move is committed and rebuilt.

Three caveats, stated rather than implied:

- **Old store copies persist until garbage collection runs.**
  Deleting `state/` from the repo, or moving it, does not remove
  anything already in `/nix/store` — store paths are immutable by
  design. `nix-collect-garbage` is the only thing that removes them,
  and only once nothing still references them (an old generation that
  still points at a build containing the old store path keeps it
  alive; `nixos-rebuild boot`/`switch` followed by removing stale
  generations may be needed first).
- **The config repo's git history still contains the journal content,
  even after the move.** `git mv` followed by a commit does not erase
  the blob from history; every prior commit's tree still has it. That
  is not a store exposure — history is not published anywhere by
  evaluation — but it matters the moment that repo is ever pushed
  somewhere, cloned by someone else, or made public. Scrubbing history
  (`git filter-repo` or equivalent, on an unpushed or not-yet-shared
  repo, per Principle 02 consequence 4's identical remediation
  reasoning for public-repo leaks) is the resident's own call and
  outside this task's scope to prescribe further.
- **An untracked or gitignored `state/` was never exposed.** Only the
  *tracked* tree is copied into the store (§"Why" above, reproduced).
  A resident who created `state/` but never `git add`ed or committed
  it has nothing to clean up on the store side — the migration is
  still worth doing for the git-history reason above if anything was
  ever committed, but if truly nothing was, moving the directory is a
  purely cosmetic tidy-up, and the doc should say so rather than imply
  urgency that is not there.

## Considered and rejected

- **Leaving this documented-but-unfixed, filing it and moving on.**
  Rejected — the finding is precise, the fix is cheap (a doc rewrite
  and a filesystem check), and Principle 01's whole premise is
  strangers adopting this framework on machines this project cannot
  see; publishing a stranger's decision journal to a shared store by
  following the documented instructions exactly is not a risk this
  project gets to leave open once it is this well understood.
- **Changing `stateDir`'s default instead of (or as well as) the
  docs.** Rejected. The default is already `null`, which already
  resolves to the safe XDG path — there is no unsafe default to fix.
  The unsafe *value* only ever arrives by a resident explicitly
  setting `castle.agent.stateDir` to a path inside their flake repo,
  following what `docs/private-layer.md` told them to do. Fixing the
  instruction is the correct level; there is no code-level default to
  change.
- **Refusing to evaluate, or refusing to run, rather than warning.**
  Rejected. Nothing in the agent layer evaluates the private flake at
  all (0024 §8's supersession made that explicit), so there is no
  evaluation step for `castle` itself to refuse at. A refusal inside
  `castle validate`/`castle digest` — exiting nonzero until the
  resident moves the directory — would also be disproportionate to
  what those commands are for: the exposure already happened on the
  next `nixos-rebuild` regardless of whether `castle` runs at all, so
  the tool cannot prevent it by refusing to run; refusing only
  withholds the two commands most likely to carry the warning to the
  resident in the first place. A loud, unmissable, non-blocking
  warning gets the fact in front of the resident without making the
  tool less useful the moment it is most needed.
- **Eval-time detection inside `modules/agent`.** Rejected.
  `stateDir` is `str`, not `path`, by deliberate design (the module's
  own comment on `repo.private`, and this same reasoning restated in
  the promoted backlog entry): a `path`-typed option would itself copy
  the checkout into the store to evaluate the option, which is the
  exact hazard this task exists to close, applied by the fix. Beyond
  that, eval time cannot stat the resident's disk to walk up looking
  for `.git`/`flake.nix` — Nix evaluation is sandboxed from arbitrary
  filesystem reads by design, and this repo does not fight that
  sandboxing anywhere else either. The check belongs at runtime, in
  the CLI, which is exactly where §2 puts it.
- **A version of the walk that does not stop at the first repository
  root.** Rejected — this is the specific bug the chosen rule exists
  to avoid (§2's submodule case), not a simplification of it. A
  "does any ancestor have `.git`, and does any ancestor (not
  necessarily the same one) have `flake.nix`" test would report the
  submodule layout as unsafe, which is false — a submodule genuinely
  excludes its content from the store copy — and would make the
  warning noisy enough that a resident who followed the recommended
  or the documented-alternative layout correctly would see a false
  positive on every `validate` and stop trusting the check.
- **A `git`-subprocess-based check (`git rev-parse --show-toplevel`,
  `git rev-parse --show-superproject-working-tree`) instead of a pure
  filesystem walk.** Rejected for the same reason `_checkout_fault`
  falls back to a filesystem test when git is unavailable: `git`
  reaches a session only through the optional `modules/dev`, and this
  check runs unconditionally on every `validate`/`digest` — it must
  not silently stop working, or start printing a different kind of
  error, on a host that never installed `git`.
- **A dedicated new subcommand (`castle check-layout` or similar)
  instead of widening `cmd_validate`.** Rejected, argued in §2: a new
  subcommand is invisible to a resident who does not already know it
  exists, and the whole problem this half of the task solves is a
  resident who followed stale documentation and has no reason to know
  anything changed. Attaching the warning to a command already in
  regular use reaches that resident; a new command only reaches
  someone who reads `docs/tasks/` or `--help` looking for it.
- **Recommending the submodule layout as the sole or primary answer,
  dropping the sibling-repo option.** Rejected — the submodule's
  safety is conditional on how the flake is referenced
  (`?submodules=1` defeats it) in a way a resident could reintroduce
  months later without noticing, while a sibling repository's safety
  has no equivalent failure mode. Documented as a legitimate
  alternative, not the recommendation, for exactly that asymmetry.

## Hard constraints, restated

- **Never write personal data into this repo.** Every path in this
  brief and in the doc rewrite (`~/private-state`, `/home/<you>/...`)
  is a placeholder already matching this repo's existing convention
  (`docs/private-layer.md`'s own `resident.nix` example). The
  verification harness (§4) uses the same fixture-identity convention
  `test/agent-loop/config-target.sh` already established
  (`fixture@example.invalid`) — never a real name, path, or journal
  entry.
- **Principle 01 test.** This task is entirely public mechanism (a
  documentation rewrite and a CLI check) plus zero new private
  configuration surface — it adds no option, requires nothing new from
  a resident's `resident.nix`, and changes no default.
- **Principle 02.** `stateDir` stays `str`, `nullOr`, default `null`,
  asserted only where it already is (`dispatch.enable` requiring it
  non-null). Nothing in this task adds an assertion, a required value,
  or any evaluation-time check of a resident's filesystem.
- **S1: the worker still never evaluates the resident's flake.**
  Unchanged by this task, and stated here so a reviewer does not read
  the sibling-repo/submodule split as touching that rule — it does
  not. It stands as defence in depth regardless of where `state/`
  ends up: even a resident who has not yet migrated is protected from
  a *worker tenant* reading their journal off the store by that rule
  already, independent of anything this task does. This task closes
  the *other* route to the same content — the store copy `nixos-rebuild`
  itself makes, available to every local process, not only the worker
  seat.
- **S2: never edit `CLAUDE.md`.** No exception, autonomy grant or not.

## File-by-file change list

- **`docs/backlog/private-layer-lands-in-the-world-readable-store.md`**
  — deleted, in the same commit that adds this brief, per
  `docs/backlog/README.md`'s lifecycle rule.
- **`docs/private-layer.md`** — "The agent's state" (lines 452–501)
  rewritten per §1 (both layouts, the submodule caveat, the unchanged
  default); new "Migrating state out of the flake" subsection added
  immediately after it, per §3. `docs/architecture.md`'s cross-link
  from this section ("Where runtime state lives") stays valid; no
  other section of this document names `state/`'s location.
- **`docs/architecture.md`** — "Where runtime state lives" (~line
  253–291): the opening sentence currently reads "The journal and the
  resident model are plain text in the **private repo**, under a
  `state/` directory." Loosen "private repo" to "private layer" and
  add one clause pointing at `docs/private-layer.md`'s layout options,
  so this narrative section does not silently keep asserting the
  layout §1 just moved away from. A small, precise edit — not a
  rewrite of the section's own reasoning about durability and
  authority, which is unaffected by which repository the directory
  lives in.
- **`agent/castle`** — new `_state_layout_finding()` beside
  `state_dir()`/`journal_dir()` (§2); the warning call in
  `cmd_validate` (before the `if errors:` branch); the warning call at
  the top of `cmd_digest` (before the "No errands recorded" early
  return and the per-errand loop).
- **`test/agent-loop/state-layout.sh`** (new) — the four-case harness,
  §4.
- **`.github/workflows/check.yml`** — one new step in the
  `agent-loop-test` job (no Nix required, same stock-runner reasoning
  already given for every step in that job; `git init` is available on
  the stock Ubuntu runner with no extra setup).
- **`docs/tasks/0030-state-outside-the-flake.md`** — this brief,
  committed on this branch per the tasks convention.

Nothing in `modules/agent/default.nix` changes. Nothing in
`agent/README.md` names a layout for `state/` today (it is the
mechanism spec, not the private-layer instructions), so it needs no
edit; confirm this while reading it and say so in the PR if that has
changed since this brief was written.

## Non-goals

- **The credential half of the same finding.**
  `castle.admin.initialHashedPassword` reaches the store by two
  routes — the flake source copy this task addresses, and NixOS's own
  `users.users.*.hashedPassword` in the activation script, which is a
  separate mechanism this task does not touch at all.
  `hashedPasswordFile` is the standard remedy for the second route and
  is not implemented here. `docs/backlog/secrets-tooling.md` is the
  correct successor task, and this brief names it as being **in
  arrears** against Principle 01 consequence 1 ("secret tooling enters
  the repo before the first credential exists") — the first credential
  already exists, in the documented `resident.nix` template, and has
  since `docs/private-layer.md` first shipped a password-hash example.
  This task's own reproduction is further, sharper evidence for
  speccing that entry next; it does not spec it.
- **0024's rule that the worker never evaluates the resident's
  flake.** Unchanged, restated as S1 above — it stands on its own,
  independent of this task, as defence in depth.
- **Eval-time detection in `modules/agent`.** Rejected in Considered
  and rejected; `stateDir` stays a plain string by design and eval
  never stats a resident's disk.
- **Any change to `castle.agent.dispatch.enable`'s gating, default, or
  meaning.** Untouched. `castle dispatch` deliberately gains no new
  output from this task (§2).
- **Scrubbing a real resident's git history, or building tooling to do
  so.** The migration section (§3) names the caveat and points at the
  general remediation this repo already uses for Principle 02
  consequence 4; it does not build a `git filter-repo` wrapper or
  automate history rewriting for anyone.
- **A `git push` credential story, or any change to "pushing stays
  manual."** `docs/private-layer.md`'s existing rule stands unchanged
  for whichever repository holds `state/` after this task — sibling or
  submodule, neither gets automatic pushing before secrets tooling
  lands.
- **Resolving `docs/backlog/where-do-host-modules-live.md`, or any
  other open backlog entry this task's reasoning brushes past.**
  Untouched, per the same discipline `docs/tasks/0024-config-target.md`
  states for itself (its own S1).

## Verification plan

**Automatable, and built as part of this task:**

- `test/agent-loop/state-layout.sh` — plain bash, `mktemp -d`,
  `git init`, no Nix, no models, matching `test/agent-loop/`'s existing
  convention (`config-target.sh` is the closest sibling: real git
  checkouts under `$WORKDIR`, a scoped `GIT_AUTHOR_*`/`GIT_COMMITTER_*`
  identity so a developer's own git config cannot affect the result).
  One `CASTLE_STATE_DIR` per case, driving `castle validate` (with an
  empty, schema-valid journal — the point is the stderr warning, not
  the schema check) and asserting on stderr:
  - **Inside-flake case**: a repo with `flake.nix` and `.git` at its
    root, `state/journal/` beneath it with no `.git` of its own.
    Assert the `WARNING:` line appears and names the repo's path.
  - **Submodule case**: the same outer repo (with `flake.nix` at its
    root — this is load-bearing, see below), with `state/` added as a
    real submodule (`git submodule add <local-path> state`, a
    same-filesystem path so the fixture needs no network). Assert no
    `WARNING:` line appears.
  - **Sibling-repo case**: two separate repos under `$WORKDIR`, one
    with `flake.nix`, one without, `CASTLE_STATE_DIR` pointed at (a
    subdirectory of) the one without. Assert no `WARNING:` line
    appears.
  - **XDG-default case**: `CASTLE_STATE_DIR` pointed at a plain
    directory under `$WORKDIR` with no `.git` anywhere in its
    ancestry up to `$WORKDIR` itself. Assert no `WARNING:` line
    appears.
  - Repeat the assertion (stderr present/absent, same four cases)
    against `castle digest` as well, not only `castle validate` — both
    call sites are this task's scope and both need coverage.
- **The mutation-test property is a fixture-construction requirement,
  not a second implementation to write.** The submodule case's outer
  repo *must* have `flake.nix` at its root (not merely exist as a
  repo) — that is what makes the case load-bearing rather than
  redundant with the sibling-repo case. A correct implementation
  reports this case safe; a version of the walk that does not stop at
  the first repository root (Considered and rejected) would walk past
  `state/.git`, reach the outer repo, find its `flake.nix`, and
  wrongly report unsafe. Comment the harness to say exactly this at
  the submodule case, so a future reader does not mistake it for
  redundant coverage and simplify it away.
- `nix flake check` — this task adds no Nix option, module, or
  `nixosConfigurations` change, so this is a regression check, not new
  coverage; run it anyway, per `CLAUDE.md`'s standing rule.

**Not automated, with the reasoning stated rather than left implicit:**
the store-copy reproduction in this brief's "Why" section is a one-off
fact about how Nix's own flake evaluation behaves, not a property of
this repo's code — it does not change from commit to commit, and there
is nothing in this task's diff that could regress it (the fix is
documentation and a filesystem check; it does not touch Nix's copying
behavior at all, which is upstream and out of this project's control
either way). Re-deriving it in CI on every run would pay a real `nix
eval` cost to reconfirm an upstream fact, forever, for no regression
this repo could cause. It was verified by hand for this brief (see
"Why") and that is the right amount of proof for a fact this stable —
`CLAUDE.md`'s own bias applies here in its harness-avoiding direction,
not its harness-building one: a one-off manual check beats an ongoing
CI cost for something that will not recur.

**Genuinely needs human hands:** actually migrating a real resident's
real `state/` directory on a real machine, per §3 — nothing in this
task's scope can do that on anyone's behalf, and nothing should try
to; §3's steps are what a human follows by hand.

## Amendments made during implementation

Recorded here rather than left to a PR description, per `CLAUDE.md`:
a brief the work overtakes gets corrected in place. Six things this
brief got wrong or left out, all found while implementing it.

1. **The file-by-file list was incomplete, and its two "nothing
   changes here" claims were both false.** The brief scoped the
   documentation change to one section of `docs/private-layer.md`,
   but four other places recommend the layout this task moves away
   from, and one of them is the single most consequential: the
   `resident.nix` **template** at `docs/private-layer.md`'s
   "`resident.nix`" section, which a stranger copies verbatim, set
   `castle.agent.stateDir = "/home/<your-login>/private/state"` with
   a comment describing it as "this private repo's own state/
   directory". Fixing the explanatory section while leaving the
   template pointing inside the flake would have changed nothing
   about what an adopter actually does. Also rewritten, for the same
   reason:
   - `docs/private-layer.md`'s `castle.agent.stateDir` bullet in the
     `resident.nix` option list.
   - `docs/private-layer.md`'s paragraph in "Automatic dispatch"
     explaining why the worker never evaluates the flake, which
     asserted that "your journal and resident model live in that
     tree" and pointed at the backlog entry this brief deletes — a
     link that would have dangled the moment the entry was removed.
   - **`modules/agent/default.nix`** — the brief says "Nothing in
     `modules/agent/default.nix` changes." Wrong: that option's own
     `description` told a resident the value "is a path into the
     private repo's checkout on the host (its `state/` directory)"
     and gave `/home/<you>/private/state` as the example, and the
     `dispatch.enable` assertion message said "Set
     castle.agent.stateDir to your private repo's state/ directory."
     Those strings are rendered into the NixOS option documentation a
     resident reads. No option's type, default, or assertion changed —
     the brief's actual constraint holds — but the prose did.
   - **`agent/README.md`** — the brief says it "names no layout for
     `state/` today" and asks the implementer to confirm. It did name
     one, in four places ("the private repo's own `state/`
     directory", "Living at `state/resident-model.md` in the private
     repo", and two more). Corrected.

2. **"Path flakeref" needed qualifying, and the doc now qualifies
   it.** Re-verified for this implementation: a *bare* path flakeref
   (`nix eval /path#attr`, what `nixos-rebuild --flake /path#host`
   uses) copies only the tracked tree — an untracked file at
   `state/journal/` was confirmed absent from the store copy. But the
   **explicit `path:` scheme** (`path:/path#attr`) copies the
   directory as it stands, untracked files and all; that was
   confirmed too, by finding an untracked marker file inside the
   resulting store path. The brief's "the exposure is exactly the
   tracked tree, nothing more and nothing less" is true of the form
   this project documents and false of the other one, so
   `docs/private-layer.md` states the distinction rather than
   inheriting the ambiguity — it matters directly to the migration
   caveat that an uncommitted `state/` was never exposed.

3. **The `digest` warning goes to stderr, like `validate`'s.** The
   brief says stderr for `validate` and only "at the very top of
   `cmd_digest`'s output" for `digest`. stderr for both: `castle
   digest` writes a document a resident may redirect to a file or pipe
   into a reader, and a warning about the machine's configuration is
   not part of that document. The harness asserts the warning is
   absent from stdout for exactly this reason.

4. **`cmd_validate` asks about `state_dir()`, not `args.journal`.**
   As the brief specifies — recorded here because the two can differ
   (`castle validate --journal <path>` checks some other directory)
   and the choice deserves to be visible rather than looking like an
   oversight. The question is where the resident's state lives;
   `--journal` is a one-off check of somewhere else and moves nothing.

5. **The mutation test is executed, not only commented.** The brief
   calls it "a fixture-construction requirement, not a second
   implementation to write." Both, in the end: the fixture is
   constructed as specified (the submodule case's outer repo carries
   `flake.nix`), *and* `test/agent-loop/state-layout.sh` applies a
   two-line patch to the real `agent/castle` at runtime — turning the
   "no `flake.nix` here" branch's `return None` into `continue` — and
   asserts the resulting mutant *does* warn on the submodule case.
   That is not a second implementation maintained alongside the first;
   it is the first one, broken on purpose. Without it, case 2 asserts
   a silence, and a silence is satisfied by a rule that never warns at
   all. The mutation step fails loudly if its anchor stops matching,
   which is the correct outcome: whoever rewrites the rule should
   re-express the mutation.

6. **The harness cannot assume its own `$TMPDIR` is outside every
   repository.** The XDG-default case wants "no `.git` anywhere in
   its ancestry". Found in practice on the machine this was written
   on: a stray empty `/tmp/.git` left behind by some other tool. The
   harness therefore refuses to run only when an ancestor of
   `$WORKDIR` carries **both** `.git` and `flake.nix` (which would
   make every case warn for an environmental reason and mean
   nothing), and otherwise logs that case 4 is exercising the
   stop-at-the-first-repository-root branch rather than the
   walk-to-the-filesystem-root branch. Both must be silent; both are
   asserted.

## Implementation prompt

For the session that implements this brief: read `CLAUDE.md` in full,
this brief in full, `docs/private-layer.md` in full (not only the
section being rewritten — the surrounding sections' cross-references
and tone need matching), `docs/architecture.md`'s "Where runtime state
lives", and every file this brief names as being modified, before
writing anything. Work on branch `sprint/0030-state-outside-the-flake`
(already checked out in this worktree; do not create a new branch or
touch any other checkout). This branch stacks on
`sprint/0024-config-target`, not yet merged — scope diffs and reviews
against `origin/sprint/0024-config-target` (`git fetch` first), and
open the PR against that branch, re-pointing to `main` only if 0024
merges first (say so in the PR description if that happens). Keep
`agent/castle` stdlib-only, no third-party dependency, readable top to
bottom, matching every prior task in this directory.

Implementation order:

1. `docs/backlog/private-layer-lands-in-the-world-readable-store.md`
   — delete it in the same commit this brief is added in, per
   `docs/backlog/README.md`'s lifecycle rule.
2. `docs/private-layer.md` — rewrite "The agent's state" per §1, add
   the migration subsection per §3. Verify the submodule claim by
   hand before writing it as fact: build a small fixture flake with
   `state/` as a real submodule, `nix eval` it, and confirm no
   `state/` directory appears anywhere under the resulting store path
   — this brief states the claim as already verified, but the
   implementer should re-confirm it once, since the doc will assert it
   to every future reader.
3. `docs/architecture.md`'s one-clause edit per the file-by-file list.
4. `agent/castle` — `_state_layout_finding()`, then the two call
   sites, in that order, so the function can be exercised standalone
   before it is wired in.
5. `test/agent-loop/state-layout.sh` — write against the real `castle`
   binary and real `git`, iterating the fixture until each of the four
   cases (plus the mutation-catching comment on the submodule case)
   passes for the right reason; this is easier to get right iteratively
   than written blind against the spec, per `docs/tasks/0023-resume-cold.md`'s
   own observation about fixture-writing.
6. `.github/workflows/check.yml` — one new step in `agent-loop-test`.

Run `test/agent-loop/state-layout.sh` directly, then the full existing
`test/agent-loop/*.sh` suite (nothing in this task should change any
of their behavior — a regression there means the new `cmd_validate`/
`cmd_digest` output broke something an existing assertion depends on),
and `nix flake check`, before opening a PR. Per `CLAUDE.md`'s
multi-agent conventions: run `/code-review` scoped against
`origin/sprint/0024-config-target` and address its findings, then run
`tools/codex-review.sh` for a second, cross-model opinion, posting its
findings verbatim with any disposition in a separate comment
underneath.
