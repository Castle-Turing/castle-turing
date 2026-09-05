# The rollback unit re-evaluates a flake before it rolls anything back

**What.** `castle-rollback.service` runs `nixos-rebuild switch
--rollback` with no `--flake`
(`modules/agent/default.nix`, docs/tasks/done/0048-activation.md §H).
In this flake's pinned nixpkgs, `system.build.nixos-rebuild` is the
Python implementation, `nixos-rebuild-ng` — the bash one has been
removed and `system.rebuild.enableNg` is a *removed* option, so there
is no other implementation to fall back to. Its `execute()` calls
`services.reexec()` for switch, boot and test **before** it reaches the
`--rollback` branch, in order to re-exec into a possibly-newer
`nixos-rebuild` built from the configuration. `reexec` resolves a flake
with `Flake.from_arg(args.flake, …)`, and with no `--flake` that falls
back to `/etc/nixos/flake.nix` when it exists, resolving symlinks:

- **If `/etc/nixos` points into the resident's configuration
  repository** — a common layout — the rollback unit evaluates that
  flake, which is a git fetch of a repository owned by the resident
  from a root process. Fixed by
  docs/tasks/0057-the-privileged-switch-cannot-read-the-repository.md,
  whose `safe.directory` grant is system-wide rather than per-unit and
  therefore covers this unit too.
- **If it does not exist**, `reexec` falls back to a classic
  `nix-build '<nixpkgs/nixos>' --attr config.system.build.nixos-rebuild`,
  which on a flake-only host has no `nixos-config` to evaluate.
  `run_wrapper` runs with `check=True`, so that failure propagates: the
  process exits before `nix-env --rollback` is ever called.

**Why it matters.** The rollback is the safety net under every
activation. `castle-activation-window.service` starts this unit when a
switch went unconfirmed, which is precisely the situation where the
resident may not be watching and may not be able to intervene — the
machine may be in the state that stopped them confirming. A rollback
that aborts in a re-exec step it has no use for leaves the unconfirmed
generation running and records a failure nobody is present to read.

**What we already know.** The fix is one flag: `--no-reexec` on the
rollback unit's `ExecStart` (present in the pinned `nixos-rebuild-ng`;
`--fast` is its deprecated spelling). A rollback needs no evaluation at
all — `nix-env --rollback` plus the previous generation's own
`switch-to-configuration` is the whole operation — so skipping the
re-exec is not a workaround but a removal of a step that should never
have been on this path.

**Why it was not just done.** Two reasons, both about who decides.
The `ExecStart` lines of the two privileged units *are* the standing
root grant a resident reads and accepts (0048 §H); changing their text
is a change to that grant, even when the change narrows what they do.
And this is a defect found by reading nixpkgs source, not by watching a
rollback fail — the 2026-09-05 failure that produced 0057 was in
`castle-activate.service`, and the rollback leg has never run on a real
machine at all. Confirming it before changing the grant is what
`docs/backlog/activation-is-not-proven-on-a-real-vm.md` exists for.

**Open questions.** Should `castle-activate.service` get `--no-reexec`
too? Its case is different: it must evaluate the flake regardless, so
the flag would only stop it from re-execing into a `nixos-rebuild`
built from the new configuration. There is an argument that a
privileged unit should run exactly the binary the resident's *current*
generation shipped, rather than one built from the configuration it is
about to switch to — but that is a judgment about the grant, not a bug
report, and it belongs with whoever decides the grant.
