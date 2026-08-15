# Share the boot-loader fallback config between hosts

**What.** Extract the two-line boot-loader invariant —
`boot.loader.systemd-boot.enable` plus
`boot.loader.efi.canTouchEfiVariables` — out of the host modules and
into shared mechanism, the way `modules/disk-layout.nix` was extracted
for partitioning.

**Why it matters.** `hosts/xps9370/default.nix` and
`hosts/vm-test/default.nix` currently carry the same stanza, each with
its own comment re-explaining the same ESP-fallback rationale. A change
to the fallback posture has to be remembered in both places, and
nothing asserts a host has set it — while `hosts/vm-test` exists
*specifically* to regression-test that boot-loader behaviour. A test
fixture drifting from the thing it tests is the failure this repo has
already been bitten by once.

**What we already know.**

- Confirmed by two independent review passes during tasks 0004 and
  0005. Parked both times for a good reason, not neglect: the file it
  touches was owned by another in-flight task each time.
- `modules/disk-layout.nix` is the precedent to copy — shared mechanism
  parameterized by a host-supplied fact, with an assertion so a host
  that forgets fails loudly.
- Host-specific commentary (the XPS's dead-CMOS history, the VM's
  reasons) should stay in the host files; only the mechanism moves.
- Not purely cosmetic: `docs/tasks/0003-findings.md` records a real
  boot failure whose root cause was the ESP fallback file being absent.

**Open questions.** Does this fold into `modules/base`, or earn its own
`modules/boot.nix`? Is there a host type that legitimately wants a
different posture (something that genuinely cannot touch NVRAM), and
should the option surface anticipate that or stay rigid until a second
case appears?
