# modules/base assumes things a minimal host does not have

**What.** Two instances of the same shape: shared mechanism in
`modules/base` presumes capabilities that only a full workstation host
actually provides, so minimal and test hosts inherit references to
things they never enable.

**Why it matters.** `modules/base` is the substrate every host imports
— it is supposed to hold what is true of *all* Castle Turing machines.
Each assumption that quietly requires a desktop-shaped host narrows
that claim, and the failures are silent: nothing breaks loudly, the
configuration just describes a machine that does not exist. The harness
host exists precisely to catch drift between mechanism and reality, so
mechanism drifting away from the harness host is the wrong direction.

**What we already know.**

- **The networkmanager group.** `modules/base` unconditionally adds the
  admin to `extraGroups = [ "wheel" "networkmanager" ]`, but only
  `hosts/xps9370` enables NetworkManager. `hosts/vm-test` therefore
  references a group its system never creates.
- **SSH hardening in the installer.** `modules/installer.nix` sets
  `PermitRootLogin = "prohibit-password"` but omits
  `PasswordAuthentication = false` and
  `KbdInteractiveAuthentication = false`, both of which every real host
  inherits from `modules/base`. An installer is the most exposed thing
  this project produces — it sits on an untrusted network with root
  reachable — so it should be at least as hardened as an installed
  system, not less.
- Both were surfaced by review during task 0005 and left alone
  correctly: the files belonged to other in-flight tasks at the time.

**Open questions.** Is the fix to make `modules/base` conditional (add
the group only when NetworkManager is enabled), or to make the option
surface explicit so a host declares what it wants? Should the installer
simply import more of `modules/base` rather than re-deriving a subset —
and if so, what in `base` is genuinely inappropriate for an installer?
Is there a general test worth having: does every host module evaluate
cleanly without a desktop?
