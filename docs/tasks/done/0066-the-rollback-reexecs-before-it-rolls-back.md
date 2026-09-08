Title: Task 0066 — the rollback re-execs before it rolls back
Model: standard
Model-because: the diagnosis and the fix are already settled in the
backlog entry this task promotes — written from nixos-rebuild-ng
source and since confirmed by a live failure with journal receipts.
What remains is transcription into a brief and a one-flag diff to one
ExecStart line, with the single hazard (widening into
castle-activate's grant) fenced off explicitly below. A deep
implementer would re-derive a conclusion the entry has already
reached; nothing in this diff calls for judgment the entry has not
already exercised.

# Task 0066 — the rollback re-execs before it rolls back

**Before starting:** read `CLAUDE.md` and
`.claude/skills/implement-brief/SKILL.md`; both bind everything below.
Then `docs/tasks/done/0048-activation.md` §H, the authority record this
task narrows and must not widen past the one line named here, and
`docs/tasks/done/0057-the-privileged-switch-cannot-read-the-repository.md`
§E, which found this defect by reading source and deferred the fix to
the backlog entry this task promotes. This brief promotes
`docs/backlog/rollback-may-die-before-it-rolls-back.md` and deletes it
in the same commit.

## Why

`castle-rollback.service` runs `nixos-rebuild switch --rollback` with
no `--flake` (`modules/agent/default.nix`, `systemd.services.castle-rollback`).
In this flake's pinned nixpkgs (rev
`0e251e24a4f24e036a084b6b4b2d2491af4167f4`), `system.build.nixos-rebuild`
is the Python `nixos-rebuild-ng` — the bash implementation is gone and
`system.rebuild.enableNg` is a *removed* option, so there is no other
implementation to fall back to. Read directly from the built package
(`nixos_rebuild/__init__.py`), `execute()` computes `can_run = action in
(SWITCH, BOOT, TEST)` from the **action**, not from whether `--rollback`
was also given, and calls `services.reexec()` whenever `can_run and not
args.no_reexec` — before the `--rollback` branch inside
`build_and_activate_system` is ever reached. `reexec()` resolves
`Flake.from_arg(args.flake, …)`; with no `--flake` and no
`/etc/nixos/flake.nix`, that returns `None`, and `reexec()` falls back to
`nix.build(NIXOS_REBUILD_ATTR, BuildAttr.from_arg(None, None), …)` — the
classic `nix-build '<nixpkgs/nixos>' --attr
config.system.build.nixos-rebuild`, which has no `nixos-config` to
evaluate on a flake-only host and fails. `run_wrapper` runs with
`check=True`, so that failure propagates and the process exits before
`nix-env --rollback` — the actual rollback — is ever called.

**This is no longer a source-reading prediction.** On 2026-09-06 at
20:33:12 local time, the resident rejected a switch's health question
and `castle-rollback.service` fired for the first time on real
hardware. The previous boot's journal:

    nixos-rebuild[53021]: error: file 'nixpkgs/nixos' was not found in the Nix search path (add it using $NIX_PATH or -I)
    nixos-rebuild[53011]: Command 'nix-build '<nixpkgs/nixos>' --attr config.system.build.nixos-rebuild --no-out-link' returned non-zero exit status 1.
    systemd[1]: castle-rollback.service: Main process exited, code=exited, status=1/FAILURE

That is the backlog entry's second bullet, failing exactly as
predicted, before `nix-env --rollback` was ever reached. The machine
stayed on the unconfirmed generation. `castle activate --close-window`'s
`rollback-failed` record was written and routed, so the surfacing half
of the mechanism worked — the rollback itself is the whole defect. The
rollback is the safety net under every activation, and it is precisely
the situation where the resident may not be watching: a rollback that
aborts in a re-exec step it has no use for leaves the unconfirmed
generation running and records a failure nobody is present to read.

## The fix

One flag on one `ExecStart` line, in `modules/agent/default.nix`:

    - ExecStart = "${config.system.build.nixos-rebuild}/bin/nixos-rebuild switch --rollback";
    + ExecStart = "${config.system.build.nixos-rebuild}/bin/nixos-rebuild switch --rollback --no-reexec";

Verified against the pinned nixpkgs rather than assumed: `--no-reexec`
is a real flag on the built `nixos-rebuild-ng` (`main_parser.add_argument("--no-reexec", …)` in `nixos_rebuild/__init__.py`), with `--fast`
present only as its deprecated, warning-emitting spelling — the backlog
entry's claim, checked. With `--no-reexec` set, `execute()`'s `if
can_run and not args.no_reexec: services.reexec(...)` is skipped
entirely; the only other `Flake.from_arg` call in `execute()` (used to
decide whether to write a version suffix, per `can_run and not flake
and not args.store_path`) already tolerates a `None` flake and is never
reached for a rollback anyway, since `build_and_activate_system`'s
`elif args.rollback:` branch calls `_rollback_system` directly and does
not consult `flake`. There is no path left in the rollback's execution
by which a missing `/etc/nixos` reaches a build step. A rollback needs
no evaluation — `nix-env --rollback` plus the previous generation's own
`switch-to-configuration` is the whole operation — so this removes a
step that was never on the rollback's path by design, rather than
working around a step that belongs there.

## This is a change to a standing root grant, not an implementation detail

Per `docs/tasks/done/0048-activation.md` §H, the two privileged units'
`ExecStart` lines **are** the standing root grant a resident reads and
accepts — "The mechanism is a pair of **system** systemd oneshot units
carrying exactly those two `ExecStart` lines." This brief changes the
text of one of them. Narrower, not wider — it removes a step
(re-exec-into-a-newer-`nixos-rebuild`) from what the rollback command
does, rather than adding one — but it is still an edit to the sentence
0048 §H says is the whole of what the resident gave away, and review of
this PR is review of that narrowed grant. That approval happens on the
PR, which is why the PR description quotes the `ExecStart` line before
and after unchanged from this brief's fix section, verbatim, rather
than summarizing it. It is not sought through any other channel, and
this task does not proceed as though the change were routine on the
strength of the diagnosis alone.

`docs/architecture.md`'s activation bullet quotes both `ExecStart`
commands verbatim as the standing grant's text (`nixos-rebuild switch
--flake <repo>#<host>` and `nixos-rebuild switch --rollback`) — the
second gains ` --no-reexec` in the same sentence, so the document that
states the grant does not go stale against the module that declares it.

## What this does not touch

**`castle-activate.service` is untouched.** Its `ExecStart` runs
`nixos-rebuild switch --flake <repo>#<host>`, which must evaluate the
flake regardless of `--no-reexec` — the flag would only stop it from
re-execing into a `nixos-rebuild` built from the configuration it is
about to switch to, before running that evaluation. Whether a
privileged unit should run exactly the binary the resident's *current*
generation shipped, rather than one built from the configuration it is
switching to, is a judgment about the grant's shape, not a bug fix, and
it belongs to whoever decides the grant next — carried into Open
questions below verbatim from the backlog entry, not answered here.

**Proving the rollback end to end on real hardware or a VM stays out of
scope.** That is `docs/backlog/activation-is-not-proven-on-a-real-vm.md`,
which remains open; this task does not attempt to close it. The
2026-09-06 failure is cited above as evidence the defect is real, not
as proof this fix has been observed to work — nobody has watched this
`ExecStart` line roll a machine back yet.

## Open questions

Carried verbatim from the backlog entry, unanswered by this task:
should `castle-activate.service` also get `--no-reexec`? Its case
differs because it must evaluate the flake regardless, so the flag
would only stop it re-execing into a `nixos-rebuild` built from the new
configuration rather than the one the current generation shipped.
There is an argument that a privileged unit should run exactly the
binary its current generation shipped rather than one built from the
configuration it is about to switch to — but that is a judgment about
the grant, not a bug report, and it is for the resident to decide, on
its own PR, not folded into this one.

## File-by-file change list

- `modules/agent/default.nix` — `--no-reexec` appended to
  `castle-rollback`'s `ExecStart`.
- `flake.nix` — the `nixosConfigurations.example-activation` assertion
  that reads the rollback unit's `ExecStart` as generated text (already
  asserting `lib.hasInfix "nixos-rebuild switch --rollback"
  rollbackUnit.serviceConfig.ExecStart`) gains a clause asserting
  `lib.hasInfix "--no-reexec" rollbackUnit.serviceConfig.ExecStart`, so
  the narrowed grant is proven present in generated output the same way
  every other clause of that grant already is, and the assertion's
  message names the expectation.
- `docs/architecture.md` — the activation bullet's quoted rollback
  command gains ` --no-reexec`.
- `docs/backlog/rollback-may-die-before-it-rolls-back.md` — deleted,
  promoted by this brief.
- This brief.

## Verification plan

Agent-verifiable, no human: `nix flake check`, which evaluates
`nixosConfigurations.example-activation` and exercises the extended
assertion above; the existing `test/agent-loop/activation.sh` suite,
which stubs `systemctl`/`nixos-rebuild`/`nix` and checks that a
rollback asks `systemctl start castle-rollback.service` — unaffected by
this change, since it never inspects the unit's `ExecStart` text
directly (that is what the `flake.nix` assertion is for) and never
invokes `nixos-rebuild` itself. The `--no-reexec` flag's existence and
`--fast`'s deprecated status were verified against the pinned nixpkgs'
built `nixos_rebuild/__init__.py` in the course of writing this brief,
not recalled — see "The fix" above for what was read.

Needs human hands, and stays out of scope: proving the rollback rolls
a machine back end to end, on real hardware or a VM — that is
`docs/backlog/activation-is-not-proven-on-a-real-vm.md`, cited rather
than built here.

## Implementation prompt

Read `CLAUDE.md`, this brief in full, and the two documents its
preamble names. Then make exactly the four changes in the file-by-file
list above. Do not touch `castle-activate.service` or its `ExecStart`.
Do not add `--no-reexec` anywhere but the rollback unit. Do not attempt
to prove the rollback on real hardware or a VM. The PR description
must quote the rollback `ExecStart` line before and after, verbatim,
and say plainly that review of this PR is review of the narrowed
grant. Record any judgment call in the session's decision log.
