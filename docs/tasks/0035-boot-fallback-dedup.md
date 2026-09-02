# Task 0035 — Share the boot-loader fallback between hosts

**Goal.** Extract the two-line boot-loader invariant —
`boot.loader.systemd-boot.enable` plus
`boot.loader.efi.canTouchEfiVariables` — out of the host modules into a
shared `modules/boot.nix`, the way `modules/disk-layout.nix` was
extracted for partitioning. Promotes and deletes
`docs/backlog/boot-fallback-dedup.md`.

## Why

`hosts/xps9370/default.nix` and `hosts/vm-test/default.nix` each carry
the same stanza, each with its own copy of the ESP-fallback rationale. A
change to the fallback posture has to be remembered in both places — and
`hosts/vm-test` exists *specifically* to regression-test this posture
(`test/vm-install/run.sh` phase 4, the NVRAM-wipe assertion), so the
test fixture drifting from the thing it tests is a live failure mode,
not a cosmetic one. Not hypothetical either: `docs/tasks/0003-findings.md`
finding #2 records a real "No Boot Device Found" whose root cause was
the ESP fallback file being absent. Flagged by review during tasks 0004
and 0005, parked both times only because the files were owned by
in-flight work.

## Design decisions

**Its own `modules/boot.nix`, not `modules/base`.** This answers the
backlog entry's first open question with a fact already in the tree:
`modules/installer.nix` imports `./base`, and the live installer image
boots the ISO profile's own loader — folding systemd-boot plus
EFI-variable writes into base would push a second, wrong loader posture
onto that image (and onto any future host base cannot speak for;
`docs/backlog/base-assumes-a-real-host.md` already records base
over-reaching as a known problem).

**Bound in `flake.nix`'s per-host wrappers, the `diskLayout`
precedent.** `nixosModules.boot` is exported and added to the
`host-xps9370` and `host-vm-test` wrapper imports. Host modules stay
hardware facts only, and every consumer of the wrappers — including
`test/vm-install/vm-test-system.nix`, which composes
`flake.nixosModules.host-vm-test` — picks the mechanism up unchanged.

**No option surface, plain assignments.** The backlog's second open
question — should the option surface anticipate a host that genuinely
cannot touch NVRAM — is answered *rigid until a second case appears*.
Today every host shares one posture; an option with one consumer is
speculation, and this repo's convention is to carve the knob when the
second case arrives (the same restraint `modules/disk-layout.nix` shows:
one layout, one parameter, nothing anticipatory). Plain assignments
rather than `lib.mkDefault`, deliberately: this is a framework
invariant, not a taste default, so an override should be loud
(`lib.mkForce`) rather than silent.

**No assertion, and why that still honors the backlog's ask.**
`modules/disk-layout.nix` asserts because its mechanism is parameterized
by a host-supplied fact (`castle.disk.device`) that a host can forget.
`modules/boot.nix` takes no parameter — importing it *is* the whole
contract, and the wrapper binding in `flake.nix` makes that hold by
construction, which is stronger than an assertion checking after the
fact. A host that imports no loader module at all still fails loudly at
eval time on nixpkgs's own GRUB assertion (GRUB is the default loader
and demands a device) — verified during implementation, see the
verification plan.

**What moves, what stays.** The mechanism-level rationale moves: why the
ESP fallback path (`EFI/BOOT/BOOTX64.EFI`) is the thing being protected,
that `bootctl install` writes it unconditionally with no
`installAsRemovable`-style knob to reach for, and the pointer to 0003
findings #2/#5 and the phase-4 harness assertion. Host-specific evidence
stays in the host files as short pointers: the XPS's dead-CMOS history,
the VM's reason to exist. `hosts/vm-test`'s `boot.loader.timeout = 0` is
a host fact (nobody at that console) and stays put.

## Non-goals

- No `castle.boot.*` option surface (above).
- No change to the installer image's loader or to
  `test/vm-install/run.sh`.
- `docs/backlog/vm-fixture-never-shows-the-boot-menu.md` stays in the
  backlog; the timeout line it discusses is untouched.

## Changes

- **`modules/boot.nix`** — new: the two assignments plus the shared
  rationale.
- **`flake.nix`** — export `nixosModules.boot`; add it to the
  `host-xps9370` and `host-vm-test` wrapper imports.
- **`hosts/xps9370/default.nix`**, **`hosts/vm-test/default.nix`** —
  drop the stanza; keep host-specific commentary, pointed at
  `modules/boot.nix`.
- **`test/vm-install/README.md`** — the phase-4 troubleshooting entry
  points at the host files for the mitigation; repoint at
  `modules/boot.nix`.
- **`hosts/xps9370/README.md`**, **`hosts/vm-test/README.md`** — their
  one-line descriptions of `default.nix` say "boot loader", which moves
  out; adjust.
- **`docs/backlog/boot-fallback-dedup.md`** — deleted (promoted to this
  brief). Nothing else in the tree cites it by path (checked).

## Verification

All of it runs with no human hands:

- `nix flake check` passes locally.
- Read the evaluated config, not just the exit status:
  `nix eval` of `boot.loader.systemd-boot.enable` and
  `boot.loader.efi.canTouchEfiVariables` must return `true` for both
  `nixosConfigurations.example` and
  `nixosConfigurations.vm-test-example`.
- The forgot-to-import claim above: evaluate `vm-test-example` with the
  `boot` wrapper import temporarily removed and confirm eval fails
  loudly (nixpkgs's GRUB assertion), then restore it.

## Numbering note

0034 does not exist in `docs/tasks/`; this number was allocated by the
orchestrator before delegation (CLAUDE.md: numbers are allocated before
delegation, never chosen by the writer), with 0034 owned by parallel
in-flight work. The next free number is whatever the directory says at
allocation time, not 0034.

## Hard constraints

- No personal data (CLAUDE.md).
- No hardware assumptions in `modules/` — this module is a *posture*
  hosts opt into via the wrappers, exactly like `diskLayout`; the
  UEFI/systemd-boot choice remains per-host, made at the wrapper.
- Principle 01: public mechanism, no private configuration involved.
