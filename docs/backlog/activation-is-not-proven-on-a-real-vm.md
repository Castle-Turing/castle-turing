# Nothing boots a machine and watches it switch itself

**What.** `docs/tasks/0048-activation.md` proves the whole activation
cycle in `test/agent-loop/activation.sh` — both triggers, the question
and its exact wording, the approval spent once, the pin bump landing
byte-exact, the confirmation, and the rollback — with `nix`,
`nixos-rebuild` and `systemctl` stubbed to log their argv. What no
harness proves is that a real NixOS machine, running the units that
task declares, actually switches when told to, and actually rolls back
when nothing confirms it.

**Why it matters.** The stubs prove the seats reason correctly. They
cannot prove the three things that only a running system has: that the
polkit rule permits the start from a live session, that
`nixos-rebuild switch --flake` from a privileged oneshot unit reaches a
new generation, and that `nixos-rebuild switch --rollback` restores the
previous one. Those are exactly the steps whose failure is most
expensive, because their failure mode is a machine left on a
configuration nobody confirmed.

**Why it is not in `test/vm-install`.** That harness boots
`hosts/vm-test`, which **deliberately imports no agent module** — the
anti-bricking regression test `docs/tasks/0008` asks for: losing the
agent layer must never mean losing the machine. Giving that fixture an
agent layer to prove activation would delete the guarantee it exists
for. This is a different fixture's job.

**What we already know.**

- `test/desktop-loop` is the right family: it is a `nixosTest`, it
  boots a machine that does import the agent layer, and a `nixosTest`
  can build a second system closure inside the VM and switch to it.
- A `nixosTest` VM has no network and a small store, so the "second
  generation" it switches to has to be a trivial derivation of the
  first (one changed `environment.etc` entry is enough to prove a new
  generation was activated) rather than a real framework bump.
- The rollback leg needs the window to expire, so either the window is
  configured down to a few seconds for the fixture or the test starts
  `castle-activation-window.service` by hand. The second is closer to
  what the timer does and does not make the fixture's timing
  load-bearing.
- The polkit leg is the one a `nixosTest` proves least well, because
  the test driver runs commands as root by default. Proving it needs
  `su - resident -c 'systemctl start castle-activate.service'` and an
  assertion that the *negative* case — some other unit, or some other
  user — is refused. The negative case is the more valuable half.
- Interacts with `vm-fixture-never-shows-the-boot-menu.md`, but only
  loosely: this rollback path never touches the bootloader.

**Open questions.** Does this go in `test/desktop-loop`'s existing test
or a new one beside it — the existing one already has screenshot-order
assertions a reboot would disturb? Is a switch to a trivially-different
closure a convincing proof, or does it want a closure that differs in
something a resident would notice?
