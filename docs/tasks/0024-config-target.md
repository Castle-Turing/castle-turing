# Task 0024 — The worker names which checkout its diff targets

**Before starting:** read `CLAUDE.md` in full, `docs/tasks/0023-resume-cold.md`
in full (this task's immediate predecessor, its format model, and the
source of the resumption machinery §12 below reuses rather than
reinvents), `docs/architecture.md` (Records, Seats — especially Worker
and Dispatch — Proposals 03, 04, 05), `agent/README.md` in full (the
`castle` CLI section, "The record format," "The claim record, and the
`outcome` field," "Resuming an errand, and the `blocking` field," and
Testing), `docs/private-layer.md` in full (especially "The agent's
state," "Automatic dispatch," and the `resident.nix` template),
`docs/principles/01-open-by-construction.md` and
`docs/principles/02-the-resident-owns-the-configuration.md`. Then,
closely: `agent/castle` — `FIELD_ORDER`, `OUTCOME_VALUES`,
`write_record`, `_write_worker_result`, `run_worker_turn` (all of it,
especially the three `TenantNotRunnable` branches and the
`env[...]`/`env.setdefault(...)` block), `cmd_work`, `cmd_record`,
`cmd_validate`'s `outcome`/`blocking` blocks — `agent/castle-worker-claude`
in full, `modules/agent/default.nix` in full, `modules/desktop/default.nix`
(the `castle.display`/`castle.input` options and their descriptions),
`modules/home/default.nix` (the `uiFontSet`/`terminalFont`/`pointerCursor`
gates), `hosts/xps9370/default.nix` and `hosts/xps9370/README.md`,
`flake.nix`'s `assertions` blocks on `nixosConfigurations.example` and
`.example-dispatch`, `test/desktop-loop/test.nix` (the `dispatchWorker`
fixture and its assertions), and `test/agent-loop/contract-worker.sh`,
`dispatch-test.sh`, `resume.sh`, `scripted-worker-blocking.sh`,
`scripted-worker-blocking-alt.py`, `contract-worker-straggler.sh`, and
`normalize_journal.py`. Work on branch `sprint/0024-config-target`, cut
from `origin/main` at `8e97248` (this branch already carries 0021,
0022, 0023, and 0029). This brief rides it. Per `SPRINT.md`'s stacked-
branch plan, PR target and merge timing are decided by the human when
this sprint closes, not by this brief.

## Why

`agent/castle-worker-claude`'s prompt already tells its tenant, in
step 1, to "decide which layer the fix belongs in (public mechanism, a
host module, or a private-layer slot — see
`docs/principles/01-open-by-construction.md` if it's ambiguous)." That
instruction has been unimplementable since the day it was written, for
one structural reason: `run_worker_turn` hands the tenant exactly one
directory, and that directory is whatever the process happened to be
sitting in.

```
agent/castle:2668  env.setdefault("CASTLE_REPO_ROOT", str(pathlib.Path.cwd()))
```

Under a human typing `castle work` in a terminal, `cwd()` was a
tolerable guess — a resident runs the CLI from inside the repo they
mean. Under `docs/tasks/0021-auto-dispatch.md`'s dispatch unit it is
not a guess at all: the unit's `WorkingDirectory` is `%h`, so an
unconfigured dispatched worker is unconditionally told its repo is the
resident's home directory. `castle.agent.worker.repoRoot`
(`modules/agent/default.nix:179-207`) already exists to override this,
and its own description already says the quiet part out loud:

> **Left unset, a dispatched worker is told its repo is your home
> directory.**

That sentence has been sitting in this framework's own Nix option
description, admitting a defect, since 0021 shipped it. This task is
what removes the need for the sentence rather than continuing to
disclose it.

The deeper problem is not the fallback, it is the singular. A resident
running Castle Turing has, in general, **two** checkouts that matter to
a worker: their **private** repository (`resident.nix`, any host module
they wrote themselves, the journal) and, optionally, a checkout of
**this** framework repo (`modules/`, `hosts/`, the option declarations
themselves) — the two halves Principle 01 splits the system into. A
single `CASTLE_REPO_ROOT` cannot name both, so a worker diagnosing "the
cursor is too small" has no way to know, from its environment, whether
the fix belongs in a file it can reach at all. Worse, the framework's
own documented convention already routes exactly this kind of
complaint to the **host module**, not the private layer:
`hosts/xps9370/default.nix:58-71` names task 0008's "the cursor is too
small" as "not a cursor-theme bug, a panel-density fact this host
module is exactly the right layer for," and
`docs/private-layer.md`'s layering table (the "resolved by a host
module" row) says the same for `scale`, `cursorTheme`, `cursorSize`,
and `consoleFont`. A worker with one undifferentiated `$CASTLE_REPO_ROOT`
cannot act on that convention even when it knows it.

This task gives the worker seat the two roots it actually needs, a
mechanically parseable way to say which one a diff targets, and a
tenant prompt that turns "decide which layer" from an unimplementable
instruction into a checkable four-step rule. It also closes two
related gaps found while tracing the code this task touches: a stale
number in `hosts/xps9370/README.md` that reproduces the exact
double-compensation bug `docs/tasks/0013-first-deploy-findings.md`
already found and fixed once, and a decision, left open by an earlier
design pass, about what a worker should do when the "right" value for
a perceptual option is a judgment call rather than a derived fact —
resolved here by reusing the resumption machinery `docs/tasks/0023-
resume-cold.md` already built, which did not exist the last time this
question was asked.

**Provenance note on this brief.** Most of the design below is not
being decided fresh. It was worked out in a decision-exhaustion pass
(`~/castle-sprint/exhaustion/0024-decisions.md`, 2026-08-17, not
committed to this repo) against `origin/main` as it stood *before*
0021, 0022, 0023, and 0029 existed. Every decision below either adopts
that pass's recommendation, or — where the merged state of those four
tasks changed the facts on the ground — corrects it explicitly, with
the correction and its reasoning stated in place rather than silently
substituted. Where this brief says "the exhaustion pass recommended
X," that is a citation, not a hedge: the reasoning belongs to that
pass and is carried forward here because it is, in every case checked,
still the better argument.

## The design

### 1. Two options, and a rename that does not break anyone

**`castle.agent.repo.private`** and **`castle.agent.repo.mechanism`**,
both `lib.types.nullOr lib.types.str`, both defaulting to `null`, in a
new `repo` sub-namespace of `castle.agent` (`modules/agent/default.nix`)
— matching the shape every other string option in this module already
uses (`stateDir`, `notify.command`).

**Why a sub-namespace and not two flat names.** `worker.command` and
`notify.command` already establish singular-noun sub-namespaces in
this module; `repo.private`/`repo.mechanism` follows the same
convention and leaves room for a third checkout later (a resident's
own fork of a dependency, say) with no new top-level identifier to
invent.

**Why `str`, never `path`, and this is the load-bearing type decision
in this section.** `stateDir`'s own description already gives half the
argument: these values are wired straight into
`environment.sessionVariables`, an environment-variable slot, and a
Nix `path` typed option would coerce to a store path rather than
staying the string it needs to be there. The other half is worse than
`stateDir`'s case: a `path` literal pointing at the resident's private
checkout is **copied into the world-readable `/nix/store`** at
evaluation time. Every credential, journal entry, and stated priority
living in that checkout would land in the store the moment someone
typed `castle.agent.repo.private = ./private;` instead of a string.
`str` cannot do that — Nix has no way to interpret a string as
"please copy this directory in."

**Default `null`, and no non-null assertion, matching `stateDir`
exactly and for the identical reason.** `modules/agent`'s own posture,
stated in `stateDir`'s description, is that an unset value "just falls
back to a per-user or built-in default rather than failing evaluation,
since the agent layer is optional the way `desktop`/`dev` are."
Principle 02 consequence 2 forbids requiring anything person-shaped at
evaluation time, and `nixosConfigurations.example` imports
`nixosModules.agent` while setting neither option — a required
assertion on either would break `nix flake check` on this task's own
first commit. The refusal that matters belongs at errand time (§16),
not eval time, exactly as `worker.repoRoot`'s absence is handled today.

**Two assertions each, following the four existing options' pattern
exactly:**

- The `"` check every string option in this module already carries
  (`!(lib.hasInfix "\"" cfg.repo.private)`, guarded `== null ||` for
  `nullOr`), because these ride `environment.sessionVariables` into
  `/etc/pam/environment`, whose `pam_env` rule is `required`
  (`modules/agent/default.nix:630-638`'s own comment) — a malformed
  value here is a whole-host login lockout, not a broken environment
  variable.
- A **new** absolute-path assertion (`lib.hasPrefix "/" cfg.repo.private`,
  same `null ||` guard), which `stateDir` does not currently carry.
  Add it to the two new options only; widening `stateDir` to match is
  explicitly out of scope for this task — a separate, easy follow-up
  with no dependency on anything here, not folded in just because the
  pattern is now visible.

**`castle.agent.worker.repoRoot` is renamed, not deleted, using
`lib.mkRenamedOptionModule`.** This is new to this repo — grep confirms
no existing use of it — so state plainly what it does and why it is
the right tool here rather than assuming the implementer already knows:
it declares the old option path as an alias for the new one, so a
private layer that still writes `castle.agent.worker.repoRoot = "...";`
keeps evaluating exactly as before, with a deprecation warning printed
at eval time naming the new path. In `modules/agent/default.nix`:

```nix
imports = [
  (lib.mkRenamedOptionModule [ "castle" "agent" "worker" "repoRoot" ] [ "castle" "agent" "repo" "private" ])
];
```

**Why rename rather than break.** Principle 02: the resident owns the
configuration. `worker.repoRoot` shipped in 0021, is documented in
`docs/private-layer.md`'s `resident.nix` template, and is exercised by
`test/desktop-loop/test.nix`. A private layer that already set it —
which, per Principle 02, this repo cannot see, audit, or migrate on
anyone's behalf — would otherwise fail to evaluate the next time its
owner updated the `flake.lock` pin, with no warning and no forwarding
address. `mkRenamedOptionModule` is exactly nixpkgs' own answer to
this shape of change, used throughout nixpkgs itself for identical
reasons; using it here is not a new pattern for this project, only the
first time this project has needed one.

**Old option, once, points at the new one; no dual-write, no
compatibility shim beyond the alias itself.** `worker.repoRoot` as a
declared option ceases to exist as its own thing — its type, default,
and description move to `repo.private` verbatim (the description text
needs light editing for the new name and the new sibling option; see
§18) — and every remaining reference to it in this repo (`flake.nix`,
`test/desktop-loop/test.nix`, `docs/private-layer.md`,
`agent/README.md`) is updated to the new name in this same commit,
because this repo is not the private layer the rename exists to
protect: nothing stops this codebase from simply using the current
name everywhere it controls.

**Confidence, carried from the exhaustion pass:** high on shape, type,
and the no-assertion call. Medium on the literal names
`repo.private`/`repo.mechanism` — a reviewer preferring different
nouns would not be wrong, and nothing downstream depends on the exact
spelling. Changed by: a strong reviewer preference, or a third
checkout appearing that makes the namespace read badly.

### 2. Retiring `CASTLE_REPO_ROOT`

**Retire it outright**, replacing it with two new variables,
`CASTLE_PRIVATE_ROOT` and `CASTLE_MECHANISM_ROOT`, set from the two
options above via `environment.sessionVariables` and the dispatch
unit's `environment` block — the same two wiring points
`CASTLE_REPO_ROOT` already used
(`modules/agent/default.nix:349-354` and `:522-527`).

`grep -rn CASTLE_REPO_ROOT` over this repo returns hits in exactly
these files, all of which this task updates in the same commit:
`agent/castle` (the `env.setdefault(...)` line and its neighboring
comment), `agent/castle-worker-claude` (the fallback default and the
prompt's interpolated path), `agent/README.md` (the `work` bullet and
"The claim record" section), `modules/agent/default.nix` (the renamed
option, `environment.sessionVariables`, the dispatch unit's
`environment` block, the `"`-character assertion), `docs/private-layer.md`
("The agent's state" and "Automatic dispatch"), `flake.nix`
(`nixosConfigurations.example-dispatch`'s dummy value and its
assertion), `test/desktop-loop/test.nix` (`testRepoRoot`'s option
assignment and the final assertion reading it back), and six files
under `test/agent-loop/`: `contract-worker.sh`,
`contract-worker-straggler.sh`, `scripted-worker-blocking.sh`,
`scripted-worker-blocking-alt.py`, `dispatch-test.sh`, and `resume.sh`.
None of these hits are external to this repo — the rename is cheap in
that sense even though it touches many files.

**`agent/castle-worker-claude`'s use is not identical to the others**
and is worth flagging so the implementer does not treat the six
`test/agent-loop/` hits and this one hit the same way: line 42,
`: "${CASTLE_REPO_ROOT:=$PWD}"`, is the tenant's own fallback for
`castle work` invocations that predate `repo.private` existing at all
(a bare, unconfigured host running `castle work` by hand). This line
becomes `: "${CASTLE_PRIVATE_ROOT:=$PWD}"` — kept, not deleted, because
a resident who never configured `repo.private` and is running `castle
work` by hand from inside their own checkout still deserves the same
degraded-but-functional behavior they get today. What changes is that
`run_worker_turn` no longer supplies that fallback on the dispatch
path (see immediately below) — the fallback becomes purely the
tenant's own last resort, exercised only when the tenant is invoked
with the variable genuinely absent from its environment.

**Two mechanical sub-decisions in `run_worker_turn`
(`agent/castle:2650-2696`), both more consequential than they look:**

- **Assign, never `setdefault`.** `env["CASTLE_PRIVATE_ROOT"]` is set
  from configuration when configured, and **left absent from `env`
  entirely** when not — never falling back to the ambient
  `os.environ` the way the current `setdefault` does. `env` starts as
  `dict(os.environ)` (`agent/castle:2655`), so an unconditional
  assignment here is what actually removes the fallback; merely
  changing `setdefault` to a conditional `if cfg: env["..."] = cfg`
  while leaving `os.environ`'s own copy of the variable untouched
  would silently resurrect it for any process whose environment
  happens to carry a stale `CASTLE_PRIVATE_ROOT` from an earlier login
  or a hand-exported shell variable. `env["CASTLE_MECHANISM_ROOT"]` is
  set the same way, but **only when `repo.mechanism` is both
  configured and usable** — §16 gives the full three-state design
  (absent / usable / configured-but-unusable) and the reason a
  configured-but-broken value is deliberately kept out of this
  variable rather than passed through and left for the tenant to
  discover is broken on its own; the unusable case instead sets a
  different variable, `CASTLE_MECHANISM_ROOT_INVALID`. Pop all three
  keys from `env` unconditionally before their conditional
  assignments, the same defensive pattern `RESUME_ANSWER_IDS_ENV`
  already uses two lines below this block (`agent/castle:2692-2695`,
  "popped rather than merely left unset, because a tenant that itself
  runs `castle work` ... would otherwise leak a stale value").
- **Delete the `cwd()` fallback outright, with nothing replacing it.**
  Absent configuration means the variable is simply absent from the
  tenant's environment; §16 is what a turn does about that, and it is
  not "guess a directory."

**Confidence:** high; the exhaustion pass's confidence on this point
did not depend on anything that has since changed.

### 3. The public-mechanism checkout is optional, and this is the normal case

`repo.mechanism = null` is expected to be the common configuration for
a real resident, and this has to be stated loudly enough that neither
the tenant prompt nor a careless implementer treats it as a
misconfiguration to warn about.

Principle 02 consequence 1: the public repo has no installable
configuration. A resident consumes this framework as a **flake input
pinned in `flake.lock`**, not as a working tree they keep around and
edit. A checkout of this repo exists on the reference development host
only because this project is developed there — a fact about the
machine building Castle Turing, not a fact about Castle Turing itself.
`docs/private-layer.md`'s `flake.nix` template names `castle-turing`
purely as `inputs.castle-turing.url`, never as a path a resident is
told to clone and keep locally.

**The concrete consequence:** a worker running on a host where
`repo.mechanism` is null cannot propose a change to `modules/` at all
— there is nowhere on disk to diff against; the flake input resolves
to a read-only Nix store path, and a diff against a store path is not
an artifact a resident can apply. On such a host the worker must say
so, in prose, and stop, rather than fabricating a diff against a path
that does not exist or silently doing nothing. This is Proposal 03's
degradation rule — "the chain ends at an empty seat and a told
resident, never a faked seat" — applied one layer down, to a
*checkout* rather than a *seat*.

### 4. Configuration by environment variable only — no new `castle work` flag

`castle work REQUEST_ID` gains no new flag for either root. Every
configurable location this CLI already has arrives as `CASTLE_*`
environment (`state_dir()`, `CASTLE_WORKER_COMMAND`,
`CASTLE_NOTIFY_COMMAND`), and that convention is exactly what lets
both the Nix module and the plain-bash test harness set the same
values through the same mechanism — `test/agent-loop/*.sh` already
sets `CASTLE_STATE_DIR` and `CASTLE_REPO_ROOT` directly, "bypassing Nix
entirely" (the module's own established pattern), and this task's new
variables follow it unchanged. A flag would be a second source of
truth a dispatcher then has to choose between when the two disagree;
nothing in this codebase has ever needed that, and this task does not
introduce the first case.

### 5. How the tenant reports its target: a second output file

**`$CASTLE_TARGET_FILE`**, containing at most one word, symmetric with
the already-established `$CASTLE_DIFF_FILE` shape. `run_worker_turn`
creates it as a fresh temp file before the tenant runs (the same
`tempfile.mkstemp` pattern `diff_path` already uses at
`agent/castle:2650-2652`), sets it in the tenant's environment
alongside `CASTLE_DIFF_FILE`, reads it back after the tenant exits
(alongside the existing `diff_text` read at `agent/castle:2868-2878`),
and unlinks it in the same `finally` block that already unlinks
`diff_path`.

**Why a second file and not a sentinel line on stdout.** Stdout is the
reasoning channel — the journal quotes it verbatim into the result
body, unedited (`agent/README.md`'s "The record format": "prose
belongs in the body"). Parsing a structured token out of that prose
is exactly the shape the flat, non-YAML frontmatter format was chosen
to avoid in the first place (`agent/README.md`'s "The record format"
section, on why frontmatter is a flat `key: value` list rather than
anything requiring a real parser). A file the tenant writes to,
exactly like `$CASTLE_DIFF_FILE`, keeps stdout pure and keeps the
mechanism mechanically parseable with no prose grammar.

**Why not a `castle record` call from inside the tenant.**
`run_worker_turn` — specifically `_write_worker_result` — is the one
writer of a given turn's `result` record. Letting the tenant write its
own result record (or a supplementary one) via `castle record` creates
two writers for one record, which is exactly the shape
`docs/tasks/0023-resume-cold.md §5` had to close a real defect over
(a tenant writing its own `answer`). This channel does not reopen that
class of problem, because it never lets the tenant write a journal
record at all — only a scratch file `run_worker_turn` reads and folds
into the one record it already owns.

**Reading it: lenient, one line, absent means absent.** After the
tenant exits, read `target_path` the same lenient way `diff_path` is
read (`.read_bytes().decode("utf-8", errors="replace")` — a tenant's
output encoding is not part of the contract, the exact reasoning
already given for the diff read), strip it, and take only the first
non-blank line. An empty or missing file — the file is always created,
so "missing" only happens if something deleted it out from under this
process, treated the same as empty — means **no target stamped**,
exactly the same honest handling `$CASTLE_DIFF_FILE`'s absence already
gets (`agent/castle:2921-2927`: "no diff produced ... or the worker
tenant did not write one"). This is not validated against a fixed
vocabulary at read time; §6 explains why.

**Corrected during implementation: honest is not the same as
harmless, and this paragraph originally conflated them.** Treating an
absent target file as simply "the tenant did not declare one" is
accurate and was written before §6 committed `docs/tasks/0025` and
`0026` to reading this field to decide which checkout a proposal goes
to. Once something downstream routes on it, silence about its absence
stops being neutral: a turn that produced a real diff and no target
leaves an applyable artifact whose destination is missing, which is
the gap this whole task exists to close, reappearing one layer in. It
is also the likelier of the two mistakes a tenant can make here — the
second output file is easy to forget, while stamping a target and
producing nothing is odd.

So the result body says so, in both directions and symmetrically. A
target with no diff is discarded with a sentence saying it was (§6);
a diff with no target is recorded, kept, and accompanied by a sentence
saying a proposal with no target cannot be routed to a checkout.
Neither is a failure — the first is inert, and the second did real
work whose diff is still the durable artifact. What neither may be is
silent.

**Consequence for the fixtures, decided rather than dodged.** Six
fixtures under `test/agent-loop/` produce a diff, and five of them
stamped no target: `contract-worker-detach.sh`, `-filer.sh`,
`-straggler.sh`, `scripted-worker-blocking.sh`, and
`scripted-worker-blocking-alt.py`. Every one of them was read before
deciding, and none omits a target for any reason of its own — they
predate the mechanism entirely, having been written for
`docs/tasks/0021` and `0023`, and each produces an ordinary synthetic
private-layer diff. So they stamp `private`, rather than the note
going unwritten to keep unrelated harnesses quiet. The fixtures that
still declare no target are exactly the ones that write no diff
(`-die`, `-fail`, `-hang`, `scripted-worker-self-answer.sh`), which is
correct and needs no change. The note itself is exercised by a
purpose-built tenant in `config-target.sh`, not by leaving a
production-shaped fixture deliberately incomplete.

### 6. The `target` field on `result` records

**One new optional field, `target`, on `result` records only, written
by `_write_worker_result` from what `$CASTLE_TARGET_FILE` held** —
never a new record type, never a new durable artifact of its own. This
follows the exhaustion pass's "five durable-data questions" analysis
exactly, and the reasoning is worth carrying forward rather than
re-deriving:

1. **Durable.** Which checkout a proposal targets is a judgment a
   later task (0025's approval binding, 0026's applier) needs to act
   on against *this exact* proposal, not something that can be
   recomputed after the fact.
2. **Not reconstructable from anything else already in the record.** A
   unified diff's `a/`/`b/` paths are relative and can be identical in
   both checkouts — `flake.nix` exists in both a mechanism checkout and
   (per `docs/private-layer.md`) a private layer that legitimately
   contains its own `hosts/` directory. Nothing else in the record
   names a repo at all.
3. **Cold-readable.** A role word (`private`/`mechanism`) is legible to
   a future tenant or a human years later with no schema archaeology;
   an absolute path would be readable today and stale tomorrow (the
   checkout moves, the machine is reinstalled); a hash or machine id is
   not readable at all. So the frontmatter field carries the **role**,
   and the **body prose**, right next to the embedded diff, states the
   actual resolved path — see the body text below.
4. **Observation, not inference.** "This diff targets the private
   checkout" is a fact about which file the tenant wrote to, not an
   inference about the resident. Nothing here reads as a resident-model
   entry and nothing here should ever be routed toward one (§21 of
   `docs/tasks/0023`'s stop conditions, restated as this brief's own
   Hard constraint).
5. **Needed now, not speculative.** `target` is needed by any future
   consumer that applies a proposal to a specific checkout; nothing
   speculative rides alongside it (no digest, no validation-plan field,
   no proposal id — all considered and rejected by the exhaustion pass
   for the same "needed now" test this repo's other schema decisions
   already apply, e.g. `agent/README.md`'s "Fields considered ... and
   deliberately dropped" for the `claim` record).

**Optional, checked only when present — the exact precedent
`considered`/`propensity` and `outcome` already set, for the identical
reason**: the journal is append-only, so a validator that started
requiring a field no prior writer could have supplied would fail every
pre-existing `result` record retroactively. `cmd_validate` gains a
block modeled directly on the `blocking` check
(`agent/castle:4170-4216`): scoped to `result` records (present on any
other type is an error, mirroring `blocking`'s question-only scoping,
because nothing anywhere reads `target` off a non-`result` record and
a field that validates clean while doing nothing is worse than one
that was never written).

**Deliberately not a closed-vocabulary membership check, unlike
`outcome`.** This is a real difference from `outcome`'s
`OUTCOME_VALUES` tuple, and the reason is worth stating rather than
leaving as an inconsistency a later reader has to puzzle out: today
there are exactly two roles, `private` and `mechanism`, and a third
checkout role (a resident's own additional repo, hinted at as a
possibility in §1's sub-namespace reasoning) would widen the set with
no schema migration needed if the validator only checks "is this
non-blank on a `result` record" rather than "is this one of exactly
two strings." `cmd_validate`'s check is therefore: present and
non-blank on a `result` record is well-formed; present on any other
type is an error; absent is always fine. The two currently-known
values are documented in `agent/README.md`, not enforced in code.

**`--target` on `castle record`,** for the same reason `--outcome` and
`--blocking` exist there: a human holding the worker seat by hand, or
a test fixture constructing a `result` record directly, needs the same
lever the automatic path has.

**Corrected during implementation: it takes `--blocking`'s
hard-refusal treatment, not `--outcome`'s convention-only one.** This
paragraph originally specified the looser posture, reasoning that
`target` carries none of `--blocking`'s dangling-reference hazard.
That is true and turned out to be the wrong test. The paragraph above
this one specifies a `cmd_validate` check that *rejects* `target` on a
non-result record and rejects a blank value — so the loose writer and
the strict validator, both specified here, contradict each other, and
`/code-review` reproduced both halves: `castle record --type decision
--target private` and `--type result --target "   "` were each written
successfully and then failed `castle validate`. In an append-only
journal that is unfixable without editing history the whole design
says is never edited, and `castle validate` is advisory and invoked
automatically by nothing, so the writer is the only place the refusal
does any good. This is exactly the defect §6's own model, the
`--blocking` guard, was reversed into place over in `docs/tasks/0023`
— "a validator laxer than the writer makes the backstop weaker than
the door" — met from the other direction. `--target` is therefore
refused at write time on any type but `result`, and refused blank.
The *vocabulary* stays unenforced, exactly as argued above: a third
checkout role must not need a schema migration. No `--spool` refusal,
unlike `--blocking`, whose spool refusal exists because a durable
claim that an errand stopped is incoherent in an ephemeral store; a
target on a spooled scratch record makes no such claim.

**`FIELD_ORDER`** gains `target`, placed immediately after `outcome`
(`agent/castle:210`, before `filed-during-turn`) — the same
"machine-readable half of what the record says about itself, met
before the prose" reasoning `outcome` and `blocking` already carry in
the comment at that location, extended by one more result-only field.
Presentation-only, exactly as that comment already says for
`blocking`: `render_record` skips any key a given record does not
carry, and parsing never consults field order.

**Written only when there is a diff, and this is a correction made
during implementation.** Nothing in this brief originally gated the
field, so `target_text` being non-empty was the whole condition — and
a tenant that stamped `$CASTLE_TARGET_FILE` while leaving
`$CASTLE_DIFF_FILE` empty produced a body reading "(no diff produced
...)" immediately followed by "This diff targets the **private**
checkout", with `target: private` in the frontmatter. Since this same
section names `docs/tasks/0025` and `0026` as keying on this field to
decide where a proposal goes, that record reads to both as an
applicable proposal with nothing to apply. A target with no diff is
not a weaker claim than a target with one; it is an incoherent claim,
because the field's whole meaning is "the checkout this diff applies
to." Both the field and the body sentence are therefore gated on a
non-empty diff, and the stamp is discarded with one visible sentence
saying so — the same reasoning as §16's mechanism note, which exists
so a fault cannot go quiet just because nothing downstream needed it.

**The body prose, next to the diff, is where the resolved path
lives.** When `target_text` is exactly `private` or `mechanism`,
`_write_worker_result`'s body assembly (the block already building
`body_lines` around `diff_text` at `agent/castle:2921-2927`) appends
one line stating which checkout the diff targets **and** the absolute
path it resolved to — read from `env.get("CASTLE_PRIVATE_ROOT")` or
`env.get("CASTLE_MECHANISM_ROOT")` respectively, the same environment
dict already in scope at that point in the function. If `target_text`
is present but not one of those two known roles, state it verbatim
with no path resolution attempted (there is no variable to look it up
against) — consistent with §6's "not a closed vocabulary" call above;
a future third role is handled honestly rather than silently
mis-resolved to the wrong path.

### 7. The layer-decision rule, made checkable

This is the core of what makes step 1 of `agent/castle-worker-claude`'s
prompt implementable rather than aspirational. A four-step ordered
rule, first match wins, with one override checked first — written to
be *checkable against the repo*, not merely persuasive prose. This
text (or a close paraphrase preserving every step and the override) is
what gets added to the prompt in §18.

**Override, checked first:** if the change would put a person into a
file in the public mechanism repo, it is private, full stop
(`CLAUDE.md`'s hard rule). State plainly, in the prompt itself, that
for the display/input/power surface this task bounds (§13) this
almost never fires: `hosts/xps9370/default.nix` argues explicitly that
a cursor theme name "identifies no one," and a panel's DPI is a
machine fact, not personal data — so a tenant does not over-apply this
override and route every taste question through a privacy argument it
does not need.

1. **Is there an option covering this symptom at all?** If not, the
   fix is *mechanism* — a new or widened option under `modules/` — not
   a configuration change. This requires `repo.mechanism`; if it is
   null (§3), the worker says so and stops. Grounded in Principle 01
   consequence 5: a feature that cannot split into mechanism plus
   configuration is not designed yet, and silently inventing the
   option in the private layer instead — a `resident.nix` that grows
   its own ad-hoc knob no `modules/` option declares — is exactly how
   that discipline gets skipped.
2. **Would the same value be right for a *different person* on the
   *same machine*?** If yes → the host module, at `lib.mkDefault`
   priority. This is the panel-DPI / pixel-grid / chassis-port /
   can-this-machine-hibernate row: `scale`, `cursorSize`,
   `cursorTheme`, `consoleFont`, `castle.hardware.hasEthernet`,
   `castle.power.criticalPowerAction` — all set exactly this way in
   `hosts/xps9370/default.nix:148-151`, and all in
   `docs/private-layer.md`'s "resolved by a host module" table row.
3. **Would the same value be right for the *same person* on a
   *different machine*?** If yes, and step 2 said no, it is taste →
   `resident.nix` in the private checkout, at normal (unprefixed)
   priority. This is the `terminalFont`/`uiFont`/`idleBlankSeconds`/
   touchpad row.
4. **Neither cleanly?** Do not pick. File a question (§12).

**The trap, stated explicitly in the prompt because a worker cannot
discover it by reading code alone:** *the layer that currently
supplies a value is not necessarily the layer the fix belongs in.*
`hosts/xps9370` supplies `cursorSize` at `mkDefault`; a resident whose
eyesight wants it bigger overrides in `resident.nix` (step 3 fires),
while a resident who finds the host's number wrong *for that panel*
fixes the host module (step 2 fires). The discriminator is the
*reason* a resident gave for the complaint, and a worker usually
cannot know that reason from the repo alone — which is exactly why §12
exists as a real branch in this rule, not a fallback for when the
worker is confused.

### 8. Observe the layering; do not reason about it

**How the worker learns which layer currently defines an option: ask
Nix, never infer from reading module source and guessing priority.**
Verified present in this era's pinned nixpkgs (`lib/modules.nix`):
every option carries `.files` (the files that actually defined it)
and `.definitionsWithLocations`/`.highestPrio` (what won, and from
where). The prompt tells the tenant to run:

```
nix eval --json <mechanism-or-private-flake>#nixosConfigurations.<attr>.options.castle.display.<opt>.files
nix eval --json <mechanism-or-private-flake>#nixosConfigurations.<attr>.options.castle.display.<opt>.definitionsWithLocations
```

`.files` answers step 2 of §7 correctly even in the one case a static
reading of this repo's own `hosts/` directory cannot: a resident who
wrote **their own** host module inside their private repo, which
`docs/private-layer.md` explicitly permits and
`docs/backlog/where-do-host-modules-live.md` leaves open (see Stop
condition S1, below — this task must not resolve that question, only
observe wherever the answer currently lives).

This is also the concrete answer to a hazard this project's own
history already produced once: `docs/tasks/0017`'s brief told its
implementer to use `lib.mkDefault` where a plain `mkOption` default
was actually correct, and it was caught only because that particular
implementer had the judgment to argue with its own brief. A worker
that *reads* the priority with `.files`/`.highestPrio` instead of
guessing at it structurally cannot make that mistake — it is asking
Nix the question, not reasoning about Nix's behavior from memory.

### 9. Which `nixosConfigurations` attribute the worker evaluates

**Derive it from the running host's own hostname; never declare a
third Nix option for it, and never enumerate and pick.**
`/proc/sys/kernel/hostname` names the attribute to try:
`nixosConfigurations.<hostname>`. If that attribute does not exist in
the evaluated flake, the worker refuses and files a question naming
exactly what it tried and what it found instead (a list of the
attribute names that *do* exist, read via a single, cheap
`builtins.attrNames` — enumeration for the sole purpose of composing an
honest refusal message is fine; enumeration to *pick* one silently is
not).

**Why derive rather than declare a third option.**
`docs/private-layer.md`'s own template is
`nixosConfigurations.<yourhost>` paired with `networking.hostName =
"<host>"` in the host module, and `hosts/xps9370/README.md`'s rebuild
instructions are literally `--flake .#xps9370` on a host whose
`networking.hostName = "xps9370"` — the convention is already
universal in the documented interface, just never written down as a
promise anything may rely on. A declared option would be a second copy
of a fact that can silently drift from the truth (a resident renames
their `nixosConfigurations` attribute without touching
`networking.hostName`, or vice versa); a derived value is checkable at
the moment it is used and fails loudly, honestly, when it does not
hold.

**Why not enumerate the flake's `nixosConfigurations` and match by
`networking.hostName`.** A private flake also carries an **installer**
configuration (`docs/private-layer.md`'s "The installer image"
section) — a second `nixosConfigurations.<host>-installer` attribute
that builds a bootable ISO. Enumerating and evaluating every attribute
to find the one whose `networking.hostName` matches would force
building an ISO configuration's evaluation graph to answer a cursor
question, which is disproportionate cost for a check that a direct
attribute-name lookup avoids entirely.

**This convention is currently incidental documentation and this task
makes it load-bearing**, so `docs/private-layer.md` gains one sentence
saying so explicitly (§18) — a resident whose `nixosConfigurations`
attribute genuinely does not match their `networking.hostName` will
meet the worker's refusal, and the fix at that point is either to
rename the attribute or, if that is never going to hold for a good
reason, to add `castle.agent.repo.configurationName` as a real Nix
option at that point. **Do not pre-build that option now** — nothing
in this task's own testing needs it, and the exhaustion pass's
"changed by" note applies verbatim: build it the day it actually bites
a real resident, not speculatively today.

### 10. Reading the running value: the allowed-command list

**An enumerated allowlist, written into the tenant prompt and into
`agent/README.md`, not enforced by the harness.** Proposal 03 puts the
contract at the errand boundary and leaves the harness free inside a
seat; building a command sandbox into `cmd_work` would be precisely
the "generalized tool-execution platform" this project's own non-goals
already forbid. But "read-only commands where useful" is not a
contract on its own, so the list has to be stated rather than implied.

**Allowed**, each verified reachable during the decision-exhaustion
pass unless noted otherwise below:

- `swaymsg -t get_config` — the entire loaded Sway config as text,
  including the `output "*" { scale ... }` and `seat "*" { xcursor_theme
  <name> <size> }` stanzas, the top-level `font pango:...`, and the
  `bar { font ... }` block. Covers most of the `castle.display.*`
  surface in one command, and is read-only by IPC type.
- `swaymsg -t get_outputs` (live per-output scale/rect), `-t get_inputs`
  (live touchpad state for `castle.input.*`), `-t get_seats`,
  `-t get_version`.
- `cat`/`readlink -f` on the home-manager-generated files:
  `~/.config/sway/config`, `~/.config/foot/foot.ini`,
  `~/.config/gtk-3.0/settings.ini`, `~/.config/i3status/config`, and
  `/etc/pam/environment` (where `XCURSOR_*` actually lands).
- `/sys/class/graphics/fb0/virtual_size` — the console's raw pixel
  grid, the same fact `docs/tasks/0017`'s measurement table used, and
  the only way to reason about `consoleFont` from inside a Wayland
  session.
- `fc-list`, `fc-match`.
- `nix eval` against the configured private and/or mechanism flake
  (§8/§9).
- `git -C <root> status --porcelain`, `git -C <root> log -1`,
  `git -C <root> diff` — read-only git, and the mechanism by which the
  worker forms its own diff.
- Reading any file under either configured root.

**Forbidden, listed explicitly rather than left to a "read-only" norm
the tenant has to infer:** `nixos-rebuild` in any form, `systemctl`,
`git commit`/`add`/`checkout`/`apply`/`stash`, any `swaymsg` invocation
that is not `-t get_*` (bare `swaymsg <command>` mutates the live
session), `gsettings set`, `setfont`, `sudo`, any write under either
configured root, and any network access beyond the tenant's own model
call.

**One documented negative finding: `nixos-option` does not work on a
flake-built host.** Verified during the exhaustion pass:
`nixos-option console.font` on a flake-built system fails with `error:
file 'nixos-config' was not found in the Nix search path`. It ships on
`$PATH` by default and looks like exactly the right tool for "read the
running value," so state the trap in the prompt or every tenant burns
a cycle rediscovering it independently.

**One documented caveat on `swaymsg`'s reachability, which this task
does not get to promise away.** Whether `swaymsg` works at all from a
dispatched worker depends entirely on how the process was invoked, and
0021 already fixed the answer for this codebase: `castle.agent.dispatch.enable`'s
sweep runs as a `systemd --user` unit with no environment reset, so it
*inherits* `SWAYSOCK` once Sway's own
`dbus-update-activation-environment --systemd ... SWAYSOCK ...` line
(generated by home-manager, not written by this repo) has run and
exported it to the user manager. Two caveats bound what the prompt may
honestly promise:

- The dispatch unit's `OnStartupSec=5s` timer sweep can lose that race
  at login — this is a first-sweep-only risk; a later sweep runs as a
  fresh service instance that picks up whatever the manager's
  environment holds by then.
- A Sway restart within one login session leaves a stale socket path
  in the manager's environment, which `swaymsg` will fail against
  until the next login.

Nothing in this repository passes a compositor handle to a worker
**deliberately** — this reachability is pure inheritance, not a
designed channel — so the prompt must treat every `swaymsg` read as
**best-effort**, with reading the home-manager-generated config files
(already in the allowed list above) as the path that always works
regardless of session timing. **Do not write prompt text that assumes
`swaymsg` succeeds.** A tenant whose `swaymsg -t get_config` fails
falls back to the file reads and says so in its reasoning, rather than
treating the failure as a reason to stop the errand.

### 11. Evidence discipline: cite, never dump

The result body names the specific fact and its source — *"`swaymsg -t
get_config` shows `xcursor_theme <theme> 18` on seat `*`"* — and never
embeds the several-kilobyte config dump the command actually produced.
This is Proposal 04 (`docs/architecture.md`) applied to the worker
seat the same way it already applies to sensors: "an observation
persists only by being cited as evidence in a decision that relied on
it." Progress chatter, if any, goes to the spool
(`$XDG_RUNTIME_DIR/castle/spool/`), which exists for exactly this and
is never committed or read back by anything durable.

### 12. Ask first, diff on resumption — the human's decision

This is the one place this brief overrides, rather than adopts, the
exhaustion pass's recommendation, and the override was made by the
human, not derived from anything in this repo — record it here as a
decision, with its reasoning, the way `docs/tasks/0023-resume-cold.md
§6` records its own human-made call.

**The old recommendation, and why it no longer applies.** The
exhaustion pass's NOW 12 said the worker should ship a real, defensible
candidate value in an applyable diff **alongside** a question in the
same turn, because at the time it was written, filing a question ended
the errand permanently — `docs/backlog/errand-resume-after-answer.md`
was still an open backlog entry, not a shipped mechanism. Under that
constraint, a question with no diff bought nothing durable; the
resident's answer would land in the journal and nothing would ever act
on it.

**`docs/tasks/0023-resume-cold.md` changed the ground this
recommendation stood on.** Resumption now exists, is merged, and is
tested (`test/agent-loop/resume.sh`, the VM's blocking-question
segment). A `--blocking` question genuinely resumes the same errand,
automatically, with the resident's own words in the next turn's
continuation packet.

**The design this task ships instead: ask first, diff on
resumption.** When the layer-decision rule (§7) identifies an option
whose correct *value* is a perceptual judgment rather than something
that follows from a stated fact — the exact line
`docs/tasks/0023`'s prompt work does not otherwise draw — the worker's
**first turn** does the following and nothing more:

1. Diagnoses the symptom, names the option and the layer (§7 already
   answers this deterministically), and states why the value itself
   cannot be derived from anything on disk.
2. Files a `--blocking` question naming the option, the layer, and —
   where one exists — the sweep tool to run
   (`tools/font-sweep.sh` for terminal/UI faces and sizes,
   `tools/console-font-sweep.sh` for `consoleFont`, the one surface
   here that cannot be previewed from inside a running Wayland session
   at all).

   **Corrected during implementation: "where one exists" has to be
   checked, not assumed.** Those scripts live in the *public* repo
   under `tools/`, and `tools/README.md` says plainly they are
   "developer tooling for working on this repo ... not anything a
   deployed system runs" — nothing packages them into a system
   profile. On a host with `repo.mechanism = null`, which §3 of this
   brief calls the normal case, they exist nowhere the resident could
   run them. Naming one there is the worst possible failure of this
   whole section: the errand stops, and the single instruction the
   resident is given points at a path that is not on their machine.
   The prompt therefore makes the pointer conditional on
   `CASTLE_MECHANISM_ROOT` being set, naming the real absolute path
   when there is one and otherwise describing what would settle the
   value — comparing candidates side by side — without naming a
   command. Packaging the sweep tools for a deployed host would also
   answer this and is deliberately **not** done here: it is a separate
   decision about what a deployed system installs, and this task has
   no standing to take it.
3. **Produces no diff.** `$CASTLE_DIFF_FILE` stays empty, and
   `$CASTLE_TARGET_FILE` stays empty too — there is nothing to target
   yet.

**This empty diff does not mean what an empty diff ordinarily means,
and the brief must say so rather than leave it to be inferred — §16
makes exactly the same point from the other direction.** §16 argues
that an empty `$CASTLE_DIFF_FILE` "already carries its own meaning,
'no change was warranted,'" and that a turn must never overload that
signal. Turn one of this section produces an empty diff for a
different reason entirely: not because no change is warranted, but
because the worker asked instead of concluding. The two are told apart
by the same signal already in the journal, not by a new field — §6's
own five-question analysis already argues against inventing one for a
narrower version of this exact question, and the argument holds here
without modification: an errand whose latest result carries an empty
diff **and** an open, unanswered `--blocking` question is waiting on
the resident; an errand whose latest result carries an empty diff with
no open question attached is a considered no-change. This is exactly
the pendingness fold `_pending_questions`/`_errand_state`
(`docs/tasks/0023`) already compute for an unrelated purpose (the
modal's status surface), reused here rather than duplicated.

**Stated for `docs/tasks/0025`'s benefit, since it is not yet specced
and will need this the moment it is:** an approval flow reading these
records must check for an open blocking question before concluding an
errand produced nothing to approve, or it will treat every
asked-and-waiting errand from this section as a considered no-change
— silently discarding exactly the errands this section's whole design
exists to eventually turn into a real proposal.

The resident answers. The **resumed turn**, per `docs/tasks/0023`'s
existing machinery with no new code of its own, receives the
continuation packet containing the original diagnosis, the question,
and the resident's answer verbatim, and writes the diff around the
resident's own number this time — stamping `$CASTLE_TARGET_FILE`
because this turn genuinely produces something to target.

**Why this is not new resumption machinery, and the brief says so
explicitly so nobody reads this section as reopening `docs/tasks/0023`'s
design.** Every mechanical piece — the `--blocking` flag, the
eligibility fold, the claim's spend accounting, the continuation
packet — already exists, is merged, and is untouched by this task.
What this section adds is purely a **policy** the worker prompt states
for one category of errand: when to use a question with no diff at
all, rather than a diff plus a non-blocking question (which is what
the current prompt already tells a tenant to do for anything it *can*
finish). Nothing in `agent/castle` changes to support this section;
everything in it lives in `agent/castle-worker-claude`'s prompt text
(§18).

**Costs, stated plainly because the design accepts them rather than
hiding them:**

- An errand nobody answers yields no proposal at all, ever — not even
  a provisional one. A resident who never runs the sweep tool and
  never answers the question simply never gets a diff for that
  complaint.
- Whatever depends on a proposal existing — `docs/tasks/0025`'s
  approval binding, `docs/tasks/0026`'s applier — receives nothing for
  this errand until the question is answered. This is not a bug this
  task introduces; it is the honest consequence of never proposing a
  value the system does not stand behind.
- This shape costs **two** model calls where a single-turn
  candidate-plus-question would have cost one: the diagnosis turn, and
  the diff-writing turn after the answer lands.

**Three rejected alternatives, recorded in full because each is the
kind of thing a future reader — or a future agent re-specifying this
task — will reach for again:**

- **Candidate value plus question in one turn (the exhaustion pass's
  own original recommendation).** Superseded, not wrong when it was
  written: it was the only shape available before `docs/tasks/0023`
  existed. Kept exactly as it was decided against here, rather than
  silently dropped, because the next reader deserves to see that this
  was the default answer and why it stopped being the right one.
- **Candidate-now, revised-if-answered.** Ship a real diff with a
  candidate value on turn one *and* a non-blocking question asking
  whether the resident wants a different number; if they answer, a
  resumed turn produces a *second* diff around their number. Rejected:
  this produces two proposals for one errand, and
  `docs/tasks/0025` — not yet specced — has not decided which of two
  proposals an approval binds to. Building that ambiguity into the
  journal now, for a task not yet designed to resolve it, is exactly
  the kind of premature commitment `docs/tasks/0023 §6`'s own
  "considered and rejected" section already warns against for a
  structurally similar shape (full answer-amendment semantics,
  deferred rather than improvised).
- **Let the tenant choose per errand.** Leave the ask-first-versus-
  guess-a-candidate decision to the model's own judgment on each turn.
  Rejected because it makes the behavior a property of *which model
  happens to hold the seat that day* rather than a property of the
  design — a resident cannot predict what filing a complaint will do
  if the answer depends on which tenant is currently configured, and
  Proposal 03's whole premise (a seat's contract does not change when
  its tenant is re-tenanted) argues directly against it.

**Interaction with the free-text answer surface, restated because it
constrains the prompt's own wording.** `castle-modal`'s answer mode
(`docs/tasks/0022-answer-in-ui.md`) lets the resident pick *which*
question to answer, never *which value* from a candidate set — there
is no multiple-choice affordance anywhere in the answer path, only
free text. A question this task files for a perceptual value must
therefore be phrased so a bare number or a short phrase is
unambiguous on its own, with no assumed context from a candidate list
the modal never showed. Where a sweep tool exists, point at the tool
rather than asking the resident to state a number cold — this is
`tools/font-sweep.sh`/`tools/console-font-sweep.sh`'s whole reason for
existing, and it is cheaper for the worker to name the tool than to
ask the resident to eyeball a value with nothing to compare it
against.

### 13. No cursor special case — bounded by option namespaces

An errand is in scope for a configuration proposal iff the symptom
maps to one or more options under `castle.display.*`, `castle.input.*`,
`castle.power.*`, or `castle.hardware.*` — declared in
`modules/desktop` (and `hasEthernet` specifically in `modules/base`),
every one of them already carrying a description written richly enough
to name its own consumer, layer, and failure mode (confirmed by
reading them: `modules/desktop/default.nix`'s `castle.display` and
`castle.input.touchpad` blocks, `modules/base/default.nix`'s
`castle.hardware`/`castle.power` blocks). The tenant reads the module
source directly — cheap, no eval required — rather than consulting a
second, hand-maintained list this task would otherwise have to invent
and keep in sync. Out of scope means the worker says so honestly and
proposes nothing.

Two properties this buys, worth stating because they are the actual
argument for this shape rather than a keyword list: zero keyword
matching (no brittle "does the request mention 'cursor'" check), and
the boundary widens automatically the moment a future task like
`docs/tasks/0020-laptop-ergonomics.md` adds a new option namespace,
with no second place in this codebase to remember to update.

### 14. The inert-proposal traps

Two coupling rules that produce a *silently* no-op diff if a worker
does not check them, both already documented in the module sources
this task's tenant is told to read:

1. **`cursorSize` is inert unless `cursorTheme` is non-null somewhere
   in the stack.** `modules/home/default.nix:597`,
   `home.pointerCursor = lib.mkIf (swayEnabled && displayCfg.cursorTheme
   != null) { ... }` — the entire cursor-theme block is skipped when no
   theme is configured, and `cursorSize` has nothing to attach to.
   Likewise `terminalFont`/`terminalFontSize` (gated together at
   `modules/home/default.nix:504`) and `uiFont`/`uiFontSize` (via
   `uiFontSet`, `modules/home/default.nix:49`) must **both** be
   non-null or the corresponding font is unmanaged. A proposal touching
   one half of any of these pairs must check the other and, if
   necessary, include it in the same diff.
2. **Priority collisions.** Editing a `lib.mkDefault` in a host module
   is inert if the private layer already defines the same option at
   normal priority — the private value always wins. `.definitionsWithLocations`/
   `.highestPrio` (§8) answer this observationally; guessing does not.

**Note for whoever writes the test fixture (§19): an acceptance case
built on `cursorSize` needs its fixture's `resident.nix` to set
`cursorTheme`, or the "correct" proposal is a silent no-op and the
test would pass for the wrong reason** — proving nothing about the
mechanism under test.

### 15. What happens when a fix would touch both checkouts: refuse

**One diff file, one target, one result — always.** A fix that
genuinely needs both a new option (`repo.mechanism`) and a resident
value set against it (`repo.private`) is a mechanism change first: the
worker proposes the mechanism half if `repo.mechanism` is configured,
states in prose that a follow-on private-layer change will be needed
once that mechanism change is adopted, and stops — or, if
`repo.mechanism` is null, says the errand needs a framework change it
cannot make from this host at all (§3).

Grounded in the worker prompt's own existing instruction to produce
"a unified diff of the fix" (singular), in this task's own scope being
ordinary configuration adjustments rather than framework development,
and in a concrete downstream fact: `docs/tasks/0026` (not yet specced)
is expected to apply "one exact patch to the resident's private
configuration" — a dual-repo patch has no downstream applier that
exists or is planned to exist, and would strand the errand at that
task instead of completing here.

### 16. Honest failure when the target is unconfigured

**A pre-flight check inside `run_worker_turn`, placed beside the three
existing `TenantNotRunnable` branches** (empty command, unparseable
command, `OSError` on exec — `agent/castle:2608-2752`), structurally
identical to them: it runs after the claim is written
(`agent/castle:2551-2569`) and before the tenant command is resolved
at all, and on failure it writes a `result` record with `outcome:
failed` through `_write_worker_result` (never raises without one,
never exits silently) and raises `TenantNotRunnable`, exactly the
pattern the other three branches already establish. **This check
covers `repo.private` only** — see below for why `repo.mechanism`
never reaches this branch at all, however it is configured. It never
produces an empty diff in the sense §12 means the phrase: this is a
turn that never invoked a tenant, so there is no diff-shaped decision
to make one way or the other. (An empty diff a tenant *did* produce
carries its own meaning, "no change was warranted" — see §12's own
note on the one case where that reading needs a caveat.)

**The refusal is scoped to `repo.private` alone, and this is a
correction to this brief's own first draft, recorded here because the
reasoning is the point.** An earlier version of this section refused
the turn whenever *either* configured root existed but failed the
usability test — treating `repo.private` and `repo.mechanism`
symmetrically on the theory that a resident who bothered to set either
one expects it to work. That instinct is right about the resident's
expectation and wrong about the correct response to disappointing it.
Work the blast radius through: §13 scopes this task to
`castle.display.*`/`castle.input.*`/`castle.power.*`/`castle.hardware.*`,
and §16's own next paragraph already establishes that the overwhelming
majority of errands in that scope target the private checkout or a
host module living inside it — never the mechanism repo alone. A typo
in `repo.mechanism`'s path would, under the symmetric rule, refuse
*every one of those errands*, including the ones that never touch
mechanism at all, to report a fault in a checkout the work in question
never needed. And refusing gains nothing in the one case it is
actually about: if a given errand's fix genuinely does belong in
mechanism, the tenant reports honestly that it cannot propose one —
whether `repo.mechanism` is absent or merely unusable, the tenant's
answer to "can I fix this in mechanism" is identically no. This is
Proposal 03's degradation rule applied at the granularity that
actually matches the failure: end at an empty *seat* and a told
resident, never a faked one — but here that means ending the
mechanism-checkout capability for this turn, not the errand itself.

**Exactly what the pre-flight checks, and what it does not.** The
refusal fires when, and only when:

- `CASTLE_PRIVATE_ROOT` is absent from the tenant's environment (i.e.
  `repo.private` is unconfigured), **or**
- `CASTLE_PRIVATE_ROOT` is present but the path it names does not
  exist, or exists but is not the root of a git working tree (checked
  as a plain filesystem test — `(pathlib.Path(root) / ".git").exists()`
  — no `git` subprocess needed for this check).
- **Added during implementation: or is not absolute.** §1 puts an
  absolute-path assertion on the Nix options, which covers a value
  arriving through Nix and nothing else — while §4 of this brief
  establishes the environment variable as the other, equally
  documented route, and it is the route every harness in
  `test/agent-loop/` uses. §1's own justification ("a relative path
  names a different place depending on who invoked the turn") applies
  with more force on the route where there is no evaluation to fail:
  a relative root would simply resolve against whatever directory the
  sweep happened to start in, which is a rediscovery of the very
  `cwd()` guess §2 deleted. Checked before the existence test, since a
  relative path that happens to resolve against the caller's cwd is
  the failure and not an escape from it. It applies to `repo.mechanism`
  by the same code path, where — per this section's asymmetry — it
  degrades that checkout rather than refusing the turn.

`repo.mechanism` never trips this check, in either of its two failure
shapes (unset, or set-but-unusable) — see the next paragraph for how
those two shapes are told apart and reported instead of silently
degrading into each other.

**A configured-but-unusable `repo.mechanism` degrades the seat, not
the errand — and the degradation has to be attributable, or a typo
becomes permanently invisible.** Two requirements make this honest
rather than merely lenient, and both are new to this section relative
to this brief's first draft:

1. **The tenant must be able to tell "no mechanism checkout
   configured" apart from "configured as `<path>`, but not a usable
   git working tree."** The channel chosen: `CASTLE_MECHANISM_ROOT` is
   set in the tenant's environment only when `repo.mechanism` is both
   configured *and* usable — the same "absent means nothing to
   signal" convention `CASTLE_RESUME_ANSWER_IDS` already establishes
   (`docs/tasks/0023 §8`). A **new** variable,
   `CASTLE_MECHANISM_ROOT_INVALID`, carries the raw configured path
   (not the usability verdict — the path itself, so the tenant can
   name it) exactly when `repo.mechanism` was configured but failed
   the usability test, and is absent in both other cases (unconfigured,
   or configured and usable). A tenant reading its environment can
   therefore always tell all three states apart: neither variable set
   (no mechanism checkout was ever configured, §3's normal case);
   `CASTLE_MECHANISM_ROOT` set (usable, operate on it); only
   `CASTLE_MECHANISM_ROOT_INVALID` set (configured, broken — name the
   real reason in the diagnosis rather than degrading silently to "no
   mechanism checkout available," which would misdescribe a
   misconfiguration as an absence). `agent/castle-worker-claude`'s
   prompt (§18) is written against all three states explicitly, not
   just the two it currently distinguishes.
2. **The result body states a configured-but-unusable mechanism root
   on every errand this turn produces a result for — not only ones
   whose diagnosis happened to touch that layer.** Computed once, near
   the top of `run_worker_turn` (alongside where `command` is read,
   using `os.environ.get("CASTLE_MECHANISM_ROOT", "")` directly — the
   raw configured value, checked before any tenant-facing `env` dict is
   built), and appended as one fixed sentence to `body_lines` in
   **every** branch that calls `_write_worker_result` for this turn:
   the three existing `TenantNotRunnable` branches, this section's own
   `repo.private` pre-flight branch, and the ordinary
   completed/failed/timeout tail. This is deliberately *not* left to
   the model's own reasoning to surface — a tenant working a private-
   layer errand has no reason to mention a mechanism-root typo it
   never needed, so relying on the model to say so would make the typo
   silent on every errand except the rare one that happens to need
   mechanism, which is precisely the failure this whole task exists to
   remove one layer down. One sentence, stated plainly: *"Note:
   `castle.agent.repo.mechanism` is configured (`<path>`) but is not a
   usable git working tree, so this turn treated the mechanism
   checkout as unavailable."* This is harness-level, not tenant-level
   — it appears whether or not the tenant's own prose mentions
   anything about mechanism at all, which is what makes it a real
   backstop rather than a second copy of what the tenant might already
   say.

`repo.private` remains the one root that must resolve for a turn to
proceed at all: the vast majority of what this task's scope (§13)
covers — display, input, power, hardware taste and host-module fixes —
targets the private checkout or a host module living inside it, never
the mechanism repo alone. A turn with no usable private root cannot do
anything this task's scope asks of it, regardless of whether a
mechanism checkout happens to be configured, usable, or absent.

**Why after the claim write, not before — the decision the exhaustion
pass explicitly left open, decided here.** Placing it after gets
consistent claim/result/spend accounting and the sweep-stopping
behavior of the other three branches for free, and matches how every
other configuration-shaped fault in this function is already handled.
The alternative — checking before the claim exists — would make this
one failure mode observably different from its three siblings for no
benefit, and `docs/tasks/0023 §3`'s own "considered and rejected"
section already worked through the alternative of moving a
runnability-shaped check earlier and rejected it for the identical
reason: every path that starts a turn has to leave a claim, or a
misconfigured host retries forever at one model call per timer tick.

**The consequence is sharp on a resumed turn, and the result body
must say so explicitly, not leave it to be inferred.** A *resumed*
turn — one carrying `$CASTLE_RESUME_ANSWER_IDS` — that hits this
pre-flight spends the resident's answer on a turn that never actually
produced anything: the claim is written (naming the answer, per
`docs/tasks/0023 §3`) before this check runs, so the answer is spent
the instant the turn starts, regardless of what happens next. The
result body must state plainly, the same way the three existing
branches' `spent_note` already does for their own failures, that the
answer given has been spent and that `castle work <request-id>` will
hand the tenant that same answer again once the target is configured
— because the errand's records are rendered into every turn's
continuation packet regardless of what earlier turns accomplished,
spent or not.

**The consequence for the common first-run case must also be stated
out loud, because it is the likelier of the two.** A resident who
opts into `castle.agent.dispatch.enable` on a fresh host without also
setting `repo.private` — a plausible sequencing mistake, not an
exotic one — will see every dispatched errand end in this exact
failure. Per `docs/tasks/0021`'s "one automatic attempt per request,
ever" rule, that `failed` result makes the request **permanently
ineligible for automatic dispatch**: "resident files a complaint on a
fresh host with no target configured" ends at an errand reading
`failed — castle work <request-id> to retry` that will never restart
itself, even after the target is later configured correctly. This is
accepted and is consistent with 0021's retry policy, but a resident
meeting it for the first time deserves to read the reason in the
result body rather than discover it by re-reading `docs/tasks/0021`.

### 17. Small mechanics

- **`--target` on `castle record`** — see §6.
- **`FIELD_ORDER`** gains `target` — see §6.
- **`cmd_validate`** gains the `target` block — see §6.
- **`_write_worker_result`** gains an optional `target: str | None =
  None` keyword, only ever passed non-`None` from the one call site
  that follows a successfully-run tenant; every `TenantNotRunnable`
  branch (the three existing ones and this task's new pre-flight one)
  continues to call it with no `target` argument, since none of those
  turns ever ran a tenant that could have produced one.
- **`CASTLE_MECHANISM_ROOT_INVALID`** — see §16 — a new tenant-facing
  environment variable, set only when `repo.mechanism` is configured
  but fails the usability test, carrying the raw configured path.
  Popped from `env` unconditionally alongside the other two roots
  (§2), the same defensive pattern `RESUME_ANSWER_IDS_ENV` already
  establishes.
- **The mechanism-unusable body note** (§16) — computed once, near the
  top of `run_worker_turn`, from the raw `os.environ.get("CASTLE_MECHANISM_ROOT",
  "")` value (not the tenant's `env` dict, which by then may already
  have had the key popped) so it is available to every branch that can
  write a result, including the three pre-existing `TenantNotRunnable`
  branches that run before the tenant `env` dict is even built.
  Appended to `body_lines`, when non-empty, in every branch that calls
  `_write_worker_result` for this turn.

### 18. Documentation and prompt changes

- **`agent/castle-worker-claude`.** Line 42's fallback becomes
  `: "${CASTLE_PRIVATE_ROOT:=$PWD}"` (§2). Line 131's interpolated
  sentence ("in the repository checked out at `${CASTLE_REPO_ROOT}`")
  is rewritten to name both roots and to distinguish all three states
  §16 defines for the mechanism root, not just the two the first draft
  of this brief named: `CASTLE_MECHANISM_ROOT` set (usable — operate
  on it); neither `CASTLE_MECHANISM_ROOT` nor
  `CASTLE_MECHANISM_ROOT_INVALID` set (no mechanism checkout was ever
  configured, §3's normal case — say so plainly, mechanism-shaped
  fixes cannot be produced here); `CASTLE_MECHANISM_ROOT_INVALID` set
  (a mechanism checkout was configured at the named path but is not a
  usable git working tree — tell the tenant to treat mechanism as
  unavailable *and* to name the real reason in its own diagnosis if
  this errand's fix would have needed mechanism, rather than
  describing it as simply absent). The harness-level body note (§16)
  covers the case where the tenant's own diagnosis has no occasion to
  mention mechanism at all; this prompt text is what lets the tenant
  give the more specific reason on the turns where it does. Step 1 of
  the contract list (`agent/castle-worker-claude:162-165`) is expanded from
  its current single sentence into the full four-step rule plus
  override from §7, since that sentence today asks the tenant to do
  something with no operational content behind it. Step 2
  (`:166-168`) gains the `$CASTLE_TARGET_FILE` instruction: write
  `private` or `mechanism` to it whenever a diff is written, matching
  which root the diff's paths resolve against; leave it empty when no
  diff is produced. A new numbered contract item (or an expansion of
  step 1) states the allowed/forbidden command list from §10,
  including the `nixos-option` trap and the `swaymsg` best-effort
  caveat. A new contract item states §12's ask-first-diff-on-resumption
  policy for perceptual values, including the sweep-tool-pointer
  instruction and the free-text-answer phrasing constraint. **None of
  this touches the "THE ONE RULE THAT OVERRIDES EVERYTHING ELSE" block**
  (`:193-205`) or the boundary-token fencing mechanism
  (`:60-115`) — this task adds contract content inside the existing
  fenced sections, it does not touch the fencing itself.
- **`modules/agent/default.nix`.** The rename (§1), the new
  `repo.mechanism` option, the two new `"`-character and absolute-path
  assertions, `environment.sessionVariables` and the dispatch unit's
  `environment` block both gaining `CASTLE_PRIVATE_ROOT`/
  `CASTLE_MECHANISM_ROOT` in place of `CASTLE_REPO_ROOT` (§2),
  `worker.command`'s description sentence naming
  `$CASTLE_REPO_ROOT` (`:114-118`) updated to name both new variables
  and the target-file/target-field contract, and
  `dispatch.enable`'s description sentence pointing at
  `worker.repoRoot` (`:233-235`) updated to point at `repo.private`.
- **`agent/README.md`.** The `work` bullet
  (`:169-201`) updates its `$CASTLE_REPO_ROOT` mention to both new
  variables and adds the `$CASTLE_TARGET_FILE`/`target` contract in
  the same register it already uses for `$CASTLE_DIFF_FILE`. "The
  claim record, and the `outcome` field" section gains a short
  paragraph on `target`, modeled on how that section already
  introduces `outcome` itself. The `record` bullet documents
  `--target` alongside its existing `--outcome`/`--blocking`
  documentation. A new short subsection (or an extension of "Resuming
  an errand") documents the ask-first-diff-on-resumption pattern from
  §12 as a worked example of blocking-question resumption in practice
  — this is the first place in this document where that machinery is
  shown doing something concrete rather than described abstractly.
- **`docs/architecture.md`.** Exactly one added sentence in the Worker
  seat's description (`:165-197`). Its contract sentence — "a `request`
  record in; a `result` record, a diff against the relevant repo, and
  journal entries out" — described one undifferentiated repo; rewrite
  "a diff against the relevant repo" to name that the diff targets a
  checkout the worker names, and add one sentence noting the two
  configured roots and that a host may configure either, both, or
  neither. **Do not touch any Proposal's statement, teeth, or
  hardening test** — a Proposal is a commitment-level artifact this
  brief has no standing to alter; that is reserved for the human, per
  `CLAUDE.md`.
- **`docs/private-layer.md`.** The `resident.nix` template block gains
  `castle.agent.repo.private`/`castle.agent.repo.mechanism` in place of
  `castle.agent.worker.repoRoot`, with a note that the old name still
  works via a deprecation-warning alias. "The agent's state" and
  "Automatic dispatch" sections update their `CASTLE_REPO_ROOT`
  mentions, including the "Left unset, a dispatched worker is told its
  repo is your home directory" sentence this Why section quotes — it
  still applies to `repo.private` specifically and should say so.
  §9's hostname-attribute convention gains its one load-bearing
  sentence, stated as a real interface promise rather than incidental
  documentation. Disclose, in one sentence, that these values land in
  `/etc/pam/environment`, which is world-readable — `stateDir` already
  has this property undocumented; this task's two new values inherit
  it and this is the moment to write it down for all three at once,
  not a blocker on a single-user laptop but something a stranger
  reading this document deserves to know. State, separately, the
  boundary that is easy to get backwards: the resident's real checkout
  path *may* appear in the journal (which lives inside the private
  repo, so that's fine), but must never appear in the **public**
  repo — fixtures, docs, commit messages, or anything pasted out of
  the journal into a PR.
- **`hosts/xps9370/README.md:24-25`.** Fixed in this task, in this
  commit, because it sits directly in the blast radius of the prompt
  change in §7/§18: it currently states `castle.display.cursorSize`
  defaults to `48` "(double the nominal 24px)" against the actual
  `18` set at `hosts/xps9370/default.nix:150`, and "double the
  nominal" is the exact double-compensation reasoning
  `docs/tasks/0013-first-deploy-findings.md` already identified as
  wrong and fixed once. A worker told, by this task's own prompt
  changes, to "inspect the public mechanism" for a cursor complaint
  would read that sentence as ground truth and reproduce the 0013 bug
  a second time. Replace it with the actual value and a pointer to
  `hosts/xps9370/default.nix`'s own long comment (`:70-98`) explaining
  why 18, not 48, is correct on this panel — do not re-derive the
  reasoning here; point at the one place it is already argued in full.

### 19. The test fixture

**Built entirely under `mktemp -d`, in the plain-bash harness, no
Nix** — matching every existing script in `test/agent-loop/`'s own
stated constraint ("runs anywhere bash + python3 do"), which is what
keeps the `agent-loop-test` CI job free of a Nix install.

- **`$WORKDIR/mechanism/`** — `git init`, populated with `git -C
  <this-repo> archive HEAD | tar -x -C "$WORKDIR/mechanism"`, then one
  commit. `git archive HEAD`, not `cp -r`: it takes only tracked
  content at `HEAD`, so no untracked file, no ignored build output, and
  nothing from the developer's own live worktree can leak into a
  fixture that is about to be committed to this repo. It also means
  the fixture exercises the real, current option surface and real
  module descriptions the tenant reads (§13), rather than a synthetic
  stand-in that can silently drift from what `modules/desktop` actually
  declares.
- **`$WORKDIR/private/`** — `git init`, plus a synthetic `flake.nix`,
  `resident.nix`, and `state/`. Reuse the placeholder literals this
  repo already publishes, rather than inventing new ones:
  `nixosConfigurations.example`'s `"resident"` admin username and
  `"ssh-ed25519 REPLACE-WITH-YOUR-PUBLIC-KEY this-is-a-placeholder-not-a-key"`
  key string, and `test/desktop-loop/test.nix`'s
  `/home/resident/private/state` shape. `resident.nix` sets
  `castle.display.cursorTheme` and leaves `cursorSize` unset — see §14
  for why that pairing is load-bearing rather than incidental.
- **`CASTLE_STATE_DIR="$WORKDIR/private/state"`**, so the fixture
  makes the documented state-dir-inside-the-private-repo relationship
  real, rather than merely asserting it exists in prose.
- **A new scripted tenant,
  `test/agent-loop/scripted-worker-config-target.sh`**, reading the
  continuation packet on stdin and
  `CASTLE_PRIVATE_ROOT`/`CASTLE_MECHANISM_ROOT`/`CASTLE_DIFF_FILE`/
  `CASTLE_TARGET_FILE` from the environment — the real
  `CASTLE_WORKER_COMMAND` contract, modeled directly on
  `test/agent-loop/contract-worker.sh`'s shape (not `scripted-worker.sh`'s
  positional-argument shape, which bypasses `cmd_work` entirely and is
  wrong for testing anything this task changes). **Leave every existing
  scripted tenant exactly as it is** — `scripted-worker.sh`/
  `scripted-worker-alt.py` because `tenant-swap.sh` depends on their
  behavior being byte-identical across runs, and `contract-worker*.sh`
  and `scripted-worker-blocking*` because `dispatch-test.sh`/`resume.sh`
  already depend on their current shapes and this task's own six-file
  rename (§2) already touches their `CASTLE_REPO_ROOT` references —
  changing anything else about them in the same commit would make it
  hard to tell a rename-only diff from a behavior change.

  **Corrected during implementation: three unavoidable exceptions,
  each forced by something else this brief asks for.**
  `contract-worker.sh` gains one line stamping `private` into
  `$CASTLE_TARGET_FILE`, because the `target: private` assertion this
  section adds to `test/desktop-loop/test.nix` reads exactly that
  fixture's output back — the assertion cannot pass without it.
  `dispatch-test.sh` and `resume.sh` gain a `git init` on their
  private root, because §16's pre-flight refuses a root that is not a
  git working tree and both harnesses previously used a bare `mkdir`.
  And `resume.sh`'s three direct `castle-worker-claude` invocations
  gain `CASTLE_TARGET_FILE`, since §18 makes the tenant require it.
  All four are one-line, mechanical, and land in the commits that
  made them necessary.

**Assertions, in the order they should be written, mirroring
`docs/tasks/0023 §11`'s own enumerated-coverage style:**

1. The diff lands in the result body, and the body's prose names the
   resolved path (§6) next to it.
2. The result carries `target: private`.
3. `git -C "$WORKDIR/private" status --porcelain` **and**
   `git -C "$WORKDIR/mechanism" status --porcelain` are both empty
   after the run, and both `git rev-parse HEAD` are unchanged — the
   no-mutation proof, and the acceptance condition's real teeth (S3,
   restated below).

   **Corrected during implementation:** the private half needs one
   exclusion, `:(exclude)state`, because this same section puts
   `CASTLE_STATE_DIR` *inside* that checkout. The journal growing
   there is the documented shape working, not a worker mutating a
   working tree, so a literal reading of this assertion fails on the
   first errand every time. Everything else under that root is still
   in scope, and the mechanism half takes no exclusion at all —
   nothing legitimately writes anything there.
4. `castle validate` passes over the resulting journal.
5. With `CASTLE_PRIVATE_ROOT` unset entirely, the run produces a
   `failed` result naming the missing configuration, and a non-zero
   exit (§16).
6. With `CASTLE_PRIVATE_ROOT` set to a path that exists but is not a
   git working tree, the same failure shape (§16's second clause).
7. With the fixture's `cursorTheme` left unset (§14), a proposal
   touching `cursorSize` alone is either refused or includes the
   sibling `cursorTheme` change — never silently produced as an inert
   no-op diff.
8. **The ask-first-diff-on-resumption path (§12), end to end**: file a
   request whose fixture-scripted tenant recognizes as a perceptual
   value (e.g. a terminal font size with no sweep-tool answer yet
   given), assert the first turn files a `--blocking` question and
   writes **no** diff and **no** `target`, answer the question, run
   dispatch again, and assert the resumed turn's result carries a real
   diff and a `target` this time, built around the resident's answer
   text appearing in the diff or its accompanying prose. This is the
   proof that §12 actually composes with `docs/tasks/0023`'s existing
   machinery rather than merely being described as compatible with it.
9. **A configured-but-unusable `repo.mechanism` does not refuse the
   turn (§16's corrected asymmetry).** With `CASTLE_PRIVATE_ROOT` valid
   and `CASTLE_MECHANISM_ROOT` set (via the harness) to a path that
   exists but is not a git working tree, run an errand entirely inside
   §13's scope that never needed mechanism at all: assert the turn
   still produces an ordinary `outcome: completed` result with a real
   `target: private` diff, **and** that the result body carries the
   one-sentence mechanism-unusable note regardless — proving the note
   is harness-level and not dependent on the tenant's own diagnosis
   mentioning mechanism. A second case, using the fixture tenant to
   simulate a mechanism-shaped errand under the same broken
   configuration, asserts the tenant's environment carries
   `CASTLE_MECHANISM_ROOT_INVALID` (not `CASTLE_MECHANISM_ROOT`) naming
   the broken path, and that the tenant declines to produce a
   mechanism diff and says why in its own reasoning — proving the
   three-state channel (§16) actually reaches the tenant, not only the
   harness-level note.
10. **The empty-diff/open-question disambiguation (§12's cross-reference
    to §16).** Using the ask-first fixture from assertion 8 before its
    question is answered, assert directly on the journal fold — not
    only on the absence of a second result — that the errand's latest
    result has an empty diff **and** `_pending_questions`/`_errand_state`-
    equivalent logic (or `castle-modal --mode status`'s own output,
    whichever is cheaper to assert against from this harness) reports
    the errand as waiting on the resident, never as a considered
    no-change. This is the concrete proof that the two "empty diff"
    meanings this brief distinguishes in prose are actually
    distinguishable by whatever reads the journal, not merely
    documented as distinguishable.
11. **The private-data boundary check `CLAUDE.md`'s hard rule already
    requires**: grep the *committed* fixture files for any absolute
    home path or `$HOME`-derived literal and fail if one is found. Every
    path used at runtime is `$WORKDIR`-derived; the only home-shaped
    string permitted in a committed file is the already-published
    `/home/resident/...` placeholder this repo uses elsewhere.

**Where it runs.** A new step in an existing CI job
(`.github/workflows/check.yml`), not a new job — the stock runner
needs no Nix for this, and one more script costs nothing while keeping
the job count flat, the same reasoning `docs/tasks/0023 §11` already
gives for `resume.sh`'s own placement.

**Corrected during implementation: the job is `dispatch-test`, not
`agent-loop-test`.** This brief named the latter while citing
`resume.sh`'s placement as the precedent, and `resume.sh` is in fact a
step of `dispatch-test` — the reasoning pointed at one job and the
sentence named the other. `dispatch-test` is where the cited reasoning
actually leads: it is the job that drives `castle dispatch` and
`castle work` against the real worker contract, which is exactly what
this harness does, and the two share every helper and convention.

**The `test/desktop-loop/test.nix` extension is minimal and mostly a
rename, not new coverage.** Per the exhaustion pass's own recommendation,
carried forward because nothing since has changed the argument: that
VM test already carries the whole modal → dispatch → result → resume
path (0021/0022/0023 all extended it), and building a second, parallel
VM path for one field would be disproportionate. What is required, not
merely nice to have, is keeping the existing test **passing**: `testRepoRoot`
(`:181`) and its use at `castle.agent.worker.repoRoot = testRepoRoot`
(`:315`) rename to `castle.agent.repo.private`, `dispatchWorker`'s
delegation to `contract-worker.sh` (`:157`) picks up that fixture's own
rename (§2) with no changes needed in `test.nix` itself, and the final
assertion (`:470-473`, `assert "${testRepoRoot}" in result_record`)
continues to pass unmodified — it checks for the *path string*, not
the *variable name*, so it is agnostic to the rename by construction
and needs no edit. **One new assertion, at most**, is worth adding
directly beside the existing one: that the result record also carries
`target: private`, since the fixture's diff genuinely targets the
private checkout and this is the cheapest possible proof that the real
dispatch unit's environment wiring (not just the plain-bash harness's)
carries the new variable correctly end to end. Nothing more.

**`flake.nix`'s `nixosConfigurations.example-dispatch`
(`:405-525`)** needs updating in the same commit or `nix flake check`
breaks: `worker.repoRoot = dummyRepoRoot;` (`:425`) becomes `repo.private
= dummyRepoRoot;`, and a new `dummyMechanismRoot` local plus `repo.mechanism
= dummyMechanismRoot;` should be added alongside it so this
configuration proves **both** new environment variables reach the
dispatch unit, not only one — the existing assertion block
(`:448-525`) already checks `environment.CASTLE_REPO_ROOT or null ==
dummyRepoRoot` at line 483; this becomes two checks,
`environment.CASTLE_PRIVATE_ROOT or null == dummyRepoRoot` and
`environment.CASTLE_MECHANISM_ROOT or null == dummyMechanismRoot`, and
the assertion's own `message` text (`:513-524`) updates its variable
names accordingly. **No dedicated test of `mkRenamedOptionModule`
itself is needed**: nixpkgs' own implementation is well-exercised
elsewhere, and a module that declared the rename incorrectly (mismatched
option paths, incompatible types) would fail `nix flake check` outright
on this repo's own `nixosConfigurations.example` the moment the old
option name stopped resolving to anything — that failure mode is
already covered by the existing eval-everything CI gate with no new
harness required.

## Considered and rejected

Gathered here once, for a reader who wants the full list without
re-deriving it from the sections above — every entry below is argued
in full at the section cited, this is the index, not the argument:

- **The option name/shape.** Two flat top-level options instead of a
  `repo` sub-namespace — rejected in favor of matching `worker.command`/
  `notify.command`'s existing sub-namespace convention. `path`-typed
  options instead of `str` — rejected because a `path` literal copies
  the resident's private checkout into the world-readable Nix store at
  evaluation. A required (non-null) value — rejected on Principle 02
  consequence 2 grounds, identically to `stateDir`. See §1.
- **Breaking `castle.agent.worker.repoRoot` outright rather than
  renaming it.** Rejected: it is a shipped, documented option a real
  private layer may already set, and Principle 02 forbids this repo
  silently breaking configuration it cannot see. See §1.
- **A candidate value for `CASTLE_REPO_ROOT`'s replacement: keep a
  single, renamed variable rather than splitting into two.** Rejected
  — "the repo root" as a singular concept is precisely what this task
  exists to remove; a lone renamed alias would just relocate the same
  ambiguity under a new name and invite a tenant to use it and stay
  unclear about which checkout it names. See §2.
- **A `castle work --private-root`/`--mechanism-root` flag.** Rejected
  — every configurable location in this CLI already arrives as
  environment, which is what lets the Nix module and the plain-bash
  harness set the same values through the same mechanism; a flag would
  be a second source of truth a dispatcher then has to arbitrate. See
  §4.
- **A sentinel line on stdout for the target, instead of a second
  file.** Rejected — stdout is the pure reasoning channel quoted
  verbatim into the journal, and parsing structure out of it is exactly
  what the flat frontmatter format exists to avoid. **The tenant
  calling `castle record` itself to declare its target.** Rejected —
  `run_worker_turn` is the one writer of a turn's result record, and a
  second writer for the same record is how `docs/tasks/0023 §5`'s
  self-answering defect happened once already. See §5.
- **A closed-vocabulary `target` field, enforced like `outcome`.**
  Rejected — a fourth checkout role would need a schema migration; a
  non-blank check on a `result` record gets the same practical safety
  (a validator that catches a genuinely malformed write) without that
  cost. See §6.
- **A hard write-time refusal on `--target`, mirroring `--blocking`'s
  dangling-reference guard.** Rejected — `target` carries none of
  `--blocking`'s hazard (nothing downstream silently mis-attributes an
  unresumable record the way an unattributable blocking question
  would), so the stricter treatment is unrequested rigor. See §6.
- **Declaring a third Nix option for the `nixosConfigurations`
  attribute name.** Rejected in favor of deriving it from
  `/proc/sys/kernel/hostname`, matching the interface this repo already
  documents everywhere else. **Enumerating and matching by
  `networking.hostName` instead of a direct attribute lookup.**
  Rejected — forces evaluating an installer ISO configuration to answer
  a cursor question. See §9.
- **Enforcing the allowed/forbidden command list in the harness rather
  than only in the prompt.** Rejected — that is the "generalized
  tool-execution platform" this project's contract deliberately keeps
  outside the errand boundary; Proposal 03 leaves the harness free
  inside a seat. See §10.
- **Candidate-plus-question in one turn, for a perceptual value (the
  exhaustion pass's own original NOW 12 recommendation).**
  Superseded by `docs/tasks/0023-resume-cold.md` existing — see §12
  for the full argument and the two further alternatives rejected
  alongside it (candidate-now-revised-if-answered; letting the tenant
  choose per errand).
- **A hard-coded keyword match ("cursor", "font", "dpi") for whether
  an errand is a configuration errand.** Rejected in favor of bounding
  scope by the declared option namespaces themselves, which grows
  automatically with the module surface and needs no second list kept
  in sync. See §13.
- **Silently allowing a proposal to touch both checkouts in one
  diff.** Rejected — no downstream applier (0026, not yet specced)
  is planned to accept one, and it strands the errand rather than
  completing it. See §15.
- **The target pre-flight before the claim write, rather than
  after.** Rejected — after gets consistent claim/result/spend
  accounting for free and matches the other three configuration-shaped
  faults `run_worker_turn` already has; before would make this one
  failure mode gratuitously different from its siblings, and
  `docs/tasks/0023 §3`'s own "considered and rejected" section already
  worked through the identical tradeoff for a structurally similar
  check. See §16.
- **Refusing the pre-flight whenever `repo.mechanism` is null.**
  Rejected outright — that is the documented normal case (§3), not a
  misconfiguration, and treating it as one would make automatic
  dispatch unusable on the overwhelming majority of real hosts. See
  §16.
- **Refusing the pre-flight whenever `repo.mechanism` is configured
  but unusable, symmetrically with `repo.private`.** This was this
  brief's own first-draft design, and it was wrong for a reason worth
  keeping visible rather than quietly editing away: §13 scopes this
  task to options whose fixes overwhelmingly target the private
  checkout, so a typo in the *mechanism* path would refuse the large
  majority of errands that never needed it, to report a fault in
  something the work at hand did not touch. Replaced with degrading
  the mechanism-checkout capability for that turn alone — absent from
  `CASTLE_MECHANISM_ROOT`, named instead in the new
  `CASTLE_MECHANISM_ROOT_INVALID` variable, and stated once in every
  result's body regardless of whether the turn's own diagnosis touched
  that layer, so the misconfiguration cannot go silent on the errands
  that never mention it. See §16.
- **Leaving a configured-but-unusable `repo.mechanism` to be
  discovered only by a tenant whose diagnosis happens to need
  mechanism.** Rejected — a typo the model never has reason to mention
  would then be invisible on every other errand, forever, which is the
  exact failure this task exists to remove one layer down (the framework's
  own `worker.repoRoot` description silently admitting a defect, quoted
  in this brief's Why section). The harness-level, always-appended
  note (§16) is what makes the misconfiguration attributable regardless
  of what any given errand needed.
- **A second, parallel VM test path built specifically for this
  task.** Rejected in favor of extending the existing
  `test/desktop-loop/test.nix` path minimally (a rename plus one new
  assertion) and letting the plain-bash harness (§19) carry the actual
  proof, following the exhaustion pass's own cost argument: that VM
  path already exists and is not free to duplicate.

## Hard constraints, restated

- **Never write personal data into this repo.** Every fixture in §19
  uses the placeholders this repo already publishes
  (`nixosConfigurations.example`'s admin username and key,
  `/home/resident/private/...` path shapes) — never a real path, a
  real complaint, or a real answer. The private-data boundary check
  (§19, assertion 9) is the mechanical backstop for this, not a
  substitute for writing the fixture correctly the first time.
- **Principle 01: public mechanism, private configuration.** This
  task's whole point is giving the worker seat the vocabulary to tell
  the two layers apart and act inside the correct one — see §7's layer
  rule and §15's refusal on a fix that cannot be split.
- **Principle 02: nothing person-shaped is required at evaluation
  time.** Both new options default `null` with no non-null assertion;
  the refusal that matters happens at errand time (§16), never at
  `nix flake check` time. State this explicitly in the PR, the same
  way `docs/tasks/0023`'s own Hard constraints section states its
  analogous claim about `castle.agent.dispatch.enable`'s existing gate
  — a reviewer will reasonably ask whether either new option needs an
  assertion beyond the two given, and the answer is no, for the
  identical reason `stateDir` has none.
- **S1 (restated from the exhaustion pass): this task must not settle
  where a stranger's host module lives.** §7's layer rule needs a
  *destination repo* for a host-layer change, and it is tempting to
  resolve `docs/backlog/where-do-host-modules-live.md`'s open question
  in passing while writing that rule. Do not. §8's `.files`-based
  observation is written specifically so the rule **observes** where a
  host module currently is — including a resident's own, inside their
  private repo — rather than **deciding** where one belongs. That
  backlog entry stays open, untouched, for the human.
- **S2: never edit `CLAUDE.md`.** No exception, autonomy grant or not.
- **S3: not one inch of relaxation on the worker's no-deploy
  boundary.** Not `git add -N` to make a diff cleaner, not `nix build`
  of a toplevel to "validate" a proposal, not a dry-run rebuild of
  either checkout. §10's allowed-command list is exhaustive and
  read-only by construction; §19's assertion 3 (both checkouts'
  `git status`/`rev-parse HEAD` unchanged after every fixture run) is
  this constraint's own teeth, not decoration.
- **S4: no worker-seat write path into the resident model.** §6 point
  4 and §12 both stay strictly inside "observation and question," never
  "the resident prefers X" written as a model entry. If §12's question
  is answered, the existing `cmd_answer`/`file_answer` path is what
  writes any resident-model entry, from the resident's own words — the
  same mechanism `docs/tasks/0023`'s own S4 already relies on, unchanged
  by this task.
- **S5: nothing from this task is promoted into `docs/principles/`.**
  "The worker names its target" is a plausible-looking candidate for a
  numbered principle and is not one — `docs/architecture.md`'s
  Proposals are the correct holding pen for anything this substantial,
  and only the human merges a principle doc.
- **S6: no real path or value in a fixture "because it's only a
  test."** CLAUDE.md's hard rule already forbids this; §19's own
  assertion 9 is the mechanical check, and the placeholders already
  published in `flake.nix` and `test/desktop-loop/test.nix` exist so
  this never has to be re-decided per task.

## Non-goals

- **Resolving `docs/backlog/where-do-host-modules-live.md`.** See S1
  above — this task observes, it does not decide.
- **Sandboxing or enforcing the allowed-command list (§10) in the
  harness.** Stated in the prompt and the docs, per Proposal 03's
  "harness is free inside a seat" — not built as a technical control.
- **`castle.agent.repo.configurationName`, or any other new option for
  the `nixosConfigurations` attribute name.** Derived from hostname
  (§9); build the option the day a real resident's naming genuinely
  does not fit the convention, not speculatively here.
- **Widening `stateDir`'s assertions to match the new absolute-path
  check added to `repo.private`/`repo.mechanism`.** A real, easy
  follow-up with no dependency on this task; not folded in here.
- **Full answer-amendment semantics, or any change to how an answer,
  once filed, can be revised.** Entirely `docs/tasks/0023`'s own scope
  and its own deferred backlog entry
  (`docs/backlog/answer-amendment-semantics.md`); §12's ask-first
  design does not touch this.
- **Workers reading the resident model, on any turn.** Unchanged from
  `docs/tasks/0023`'s own non-goal; this task's questions and results
  stay strictly observation, never a model write (S4).
- **Any change to `castle.agent.dispatch.enable`'s meaning, default,
  or gating**, or to the resumption mechanism `docs/tasks/0023`
  built. §12 is a prompt-level policy riding existing machinery
  unchanged.
- **Autonomous deployment, proposal approval, or configuration
  application from any seat.** Unchanged from every prior task in this
  directory — the worker proposes, and this task adds no path by which
  anything it produces is ever applied automatically. See S3.
- **A sandbox, timeout, or cost cap on the worker's own `nix eval`
  calls (§8/§9).** Real eval cost exists and is not measured by this
  task; if it turns out to matter in practice, that is its own,
  separately-specced follow-up.

## Implementation prompt

For the session that implements this brief: read `CLAUDE.md` in full,
this brief in full, `docs/tasks/0023-resume-cold.md` in full (the
resumption machinery §12 rides), `docs/architecture.md`,
`agent/README.md`, `docs/private-layer.md`, and every file this brief
names as being modified, before writing any code. Work on branch
`sprint/0024-config-target` (already created and carrying this brief;
do not rewrite the brief silently — if implementation surfaces a
genuine deviation from what it specifies, say so prominently in your
own report and amend this brief in the same PR, per `CLAUDE.md`'s rule
that a brief overtaken by the work it rides gets corrected in place).
Keep `agent/castle` stdlib-only, no third-party dependency of any
kind, readable top to bottom — carried over from every prior task in
this directory, not new to this one.

Implementation order, matching the design's own dependency chain:

1. The two Nix options, the `lib.mkRenamedOptionModule` alias, the two
   new assertions, and the environment-variable wiring in
   `modules/agent/default.nix` (§1, §2) — the foundation everything
   else configures against.
2. The `CASTLE_REPO_ROOT` → `CASTLE_PRIVATE_ROOT`/`CASTLE_MECHANISM_ROOT`
   rename across every file `grep -rn CASTLE_REPO_ROOT` finds (§2's own
   enumerated list) — mechanical, and worth doing as its own isolated
   commit-sized chunk before anything behavioral changes, so a review
   can tell the rename apart from the new logic.
3. `$CASTLE_TARGET_FILE`, the `target` field, `FIELD_ORDER`,
   `cmd_validate`'s block, and `--target` on `castle record` (§5, §6,
   §17) — the new record-format surface, testable in isolation against
   a hand-built journal before it is wired into `run_worker_turn`.
4. The `repo.private` pre-flight check in `run_worker_turn` (§16),
   placed beside the three existing `TenantNotRunnable` branches, and
   — in the same pass, since both read the same raw environment value
   before it is copied into the tenant's `env` dict — the
   `CASTLE_MECHANISM_ROOT`/`CASTLE_MECHANISM_ROOT_INVALID` three-state
   split and the always-appended mechanism-unusable body note.
5. The worker prompt (`agent/castle-worker-claude`, §7, §10, §12, §18)
   — write this once the mechanical plumbing above exists, so the
   prompt text can be checked against real environment variables and a
   real `$CASTLE_TARGET_FILE` rather than written blind against a
   spec.
6. Documentation (§18) — `modules/agent/default.nix`'s option
   descriptions, `agent/README.md`, `docs/architecture.md`'s one
   sentence, `docs/private-layer.md`, and
   `hosts/xps9370/README.md`'s stale-number fix.
7. The test fixture and CI wiring (§19) — write the new scripted
   tenant and `resume.sh`-adjacent(-or-sibling) harness script
   alongside the code they exercise, per `docs/tasks/0023`'s own
   observation that a fixture's stdin-reading/echoing behavior is
   easiest to get right iteratively against real code rather than
   written blind against a spec.
8. `flake.nix`'s `nixosConfigurations.example-dispatch` and
   `test/desktop-loop/test.nix`'s rename plus one new assertion (§19).

Run `test/agent-loop/*.sh` (every harness in that directory, including
the new one) and `nix flake check` locally before opening a PR; build
`test/desktop-loop/test.nix` locally with `nix build
.#desktop-loop-test` if the machine has the resources, or trigger it
in CI via `gh workflow run desktop-loop-test.yml` if not. Per
`CLAUDE.md`'s multi-agent conventions: run `/code-review` scoped
against `origin/main` and address its findings, then run
`tools/codex-review.sh` for a second, cross-model opinion, posting its
findings verbatim with any disposition in a separate comment
underneath. `git fetch` first and confirm the real diff scope with
`git diff origin/main...HEAD --stat` before trusting any review
output — this branch carries 0021/0022/0023/0029 already, so scope the
diff against `origin/main`, not against wherever this branch started
from, or the review will re-litigate work this task did not touch.

Never touch `docs/principles/` or `CLAUDE.md`. Never settle
`docs/backlog/where-do-host-modules-live.md` (S1). Never relax the
worker's no-deploy boundary by one inch, in a fixture or anywhere else
(S3). Never write anything resembling a real resident's path,
complaint, or answer into a fixture, a test, or a code comment — every
example string in this brief and in the existing codebase it extends
is invented and hardware-neutral, and new ones must be too.
