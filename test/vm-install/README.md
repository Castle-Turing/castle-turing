# test/vm-install — the install-loop test harness

What `docs/tasks/0004-install-test-harness.md` asked for: a way to
exercise the real install mechanism (`hosts/vm-test/` +
`modules/base` + `modules/disk-layout.nix` + `modules/installer.nix`)
end to end, unattended,
so a regression like task 0003's physical-shakedown findings goes red
in CI instead of costing a human a USB round-trip.
`docs/tasks/0006-installer-image.md` later pointed this same harness at
the real installer image (`flake.nixosModules.installer`) instead of a
one-off test fixture, and added the "installer itself is SSH-reachable
unattended" assertion below.

## What it asserts

Run in order, against one QEMU/OVMF VM:

1. The installer image itself — the real public mechanism,
   `flake.nixosModules.installer` (`docs/tasks/0006-installer-image.md`)
   — boots and comes up SSH-reachable by key **with zero console
   interaction**: no `nmtui`, no fetching a key at the console. This is
   the regression test for installer ephemerality
   (`docs/tasks/0003-findings.md` finding #3).
2. `nixos-anywhere` installs the real target (disko partitions the
   virtio disk, `nixos-install` runs) against that booted installer.
3. The VM reboots from its own disk with the installer media detached,
   and SSH comes up as the admin, by key, **with zero console
   interaction** — the regression test for the first-boot lockout
   (`docs/tasks/0003-findings.md` finding #1).
3b. On that same boot (`docs/tasks/0005-dogfooding-desktop.md`):
   `graphical.target` is reached, and Sway's IPC socket appears and
   answers `swaymsg -t get_version`. A GUI can't be driven headlessly,
   but this much can be checked with no human and no display —
   `vm-test-system.nix` imports the published `modules/desktop` and
   layers a test-only auto-login on top (never present in the real
   module — see that file's header comment) so Sway starts with, again,
   zero console interaction.
4. The VM survives a power-cycle: a hard stop (`kill -9` the QEMU
   process — no clean shutdown) followed by a restart with its NVRAM
   intact.
5. The VM survives an NVRAM wipe: its OVMF vars file is replaced with a
   pristine (blank) one and it's restarted again, forcing the firmware
   down the UEFI-standard fallback path `EFI/BOOT/BOOTX64.EFI` instead
   of any NVRAM boot entry. This is the dead-CMOS lesson from finding
   #2/#5 — a missing or non-surviving fallback file is exactly the bug
   that produced "No Boot Device Found" on the real XPS.

The `kill -9` in assertions 4 and 5 is deliberate, not a shortcut: an
ungraceful stop is the actual failure mode a power-cycle test exists to
cover, so `run.sh` never unmounts or syncs before those two. The one
exception is the phase 1 → phase 2 transition (detaching the installer
after a successful install) — that one *does* explicitly `umount` and
`sync` first, because it stands in for a normal reboot after install,
not a power loss, and phases 2-4 need the install's own writes (notably
`bootctl install`'s vfat ESP writes) to have actually landed on disk
before they can mean anything.

Each step is a hard assertion: the script exits non-zero the moment one
fails, and says which assertion failed and where its log is.

## Why a custom harness and not `nixos-anywhere --vm-test`

`nixos-anywhere --vm-test` builds the system and disko script and
partitions a scratch disk inside a VM to validate the disk
configuration — useful, but one-shot: it doesn't leave a persistently
bootable VM to test reboot, power-cycle, or NVRAM-fallback behavior
against, and it doesn't drive `nixos-anywhere`'s real remote-install
path (SSH into a running installer, over a network) the way an actual
deploy does. Since three of `docs/tasks/0004-install-test-harness.md`'s
four originally required assertions are specifically about what happens
on later boots, `--vm-test` can't express them; this harness drives
QEMU directly instead, and still uses
`nixos-anywhere` itself (via `--store-paths`) for the actual install
step, so the install path under test is the same one a real machine
gets.

## Running it locally

Needs: a KVM-capable **x86_64** Linux box (same architecture as the
reference host, `hosts/xps9370`) with `/dev/kvm` accessible, and Nix
with flakes enabled.

```sh
test/vm-install/run.sh
```

It builds its own tooling (qemu, OVMF, nixos-anywhere, openssh) from
this flake's pinned nixpkgs — nothing needs to be preinstalled beyond
Nix itself. A throwaway admin SSH keypair is generated fresh per run in
a temp directory and never touches this repo.

Useful environment variables:

- `CASTLE_HARNESS_LOG_DIR` — where serial console logs and the
  `nixos-anywhere` transcript are written. Defaults to a temp directory
  (printed at the end of the run, or in the `FAIL:` line if a phase
  fails).
- `CASTLE_HARNESS_SSH_PORT` — host-forwarded SSH port (default 10222).
- `CASTLE_HARNESS_BOOT_TIMEOUT` — seconds to wait for SSH on each boot
  (default 180).

## Reading a failure

Each phase writes two logs under the log directory:
`<phase>.serial.log` (the VM's console — kernel/systemd/boot-loader
output, the most useful one) and `<phase>.qemu.log` (QEMU's own
stderr/stdout, useful if QEMU itself failed to start). Phase 1 also
writes `phase1-nixos-anywhere.log`, the full `nixos-anywhere`
transcript.

Phase names map directly to the assertions above (`phase1-installer`
covers both assertion 1, the installer's own SSH reachability, and
assertion 2, the install itself — they share one boot of the installer
image):

- `phase1-installer` — either the installer image never came up
  SSH-reachable (check `phase1-installer.serial.log` — this is the
  finding #3 regression), or it came up fine but `nixos-anywhere` itself
  failed (disko/format/copy/`nixos-install` error) — check
  `phase1-nixos-anywhere.log` first in that case.
- `phase2-first-boot` — the freshly installed disk didn't boot on its
  own, or SSH as the admin needed something console/Wi-Fi/password
  shaped it shouldn't. Check `phase2-first-boot.serial.log` for where
  boot stalled.
- `phase2b` (no separate boot, same VM as phase 2) — either
  `graphical.target` never became active (check
  `phase2-first-boot.serial.log` for where greetd/sway stalled), or the
  IPC socket didn't appear or didn't answer `swaymsg` (check
  `phase2b-sway-ipc.log`). The latter is most often a Sway/wlroots
  startup failure — `WLR_BACKENDS=headless` should make that
  unconditional in a display-less VM, so a failure here usually means
  something changed in how `modules/desktop` or the test-only auto-login
  override (`vm-test-system.nix`) starts the session, not a real display
  problem.
- `phase3-power-cycle` — the system didn't come back cleanly after a
  hard stop (a filesystem that won't mount without an interactive fsck
  prompt is the classic cause — check the serial log for an `fsck`
  or emergency-shell line).
- `phase4-nvram-wipe` — the ESP fallback file
  (`EFI/BOOT/BOOTX64.EFI`) is missing or broken. This is the exact bug
  class task 0003 found by hand; see
  `docs/tasks/0003-findings.md` finding #2/#5 for the full story and
  `hosts/xps9370/default.nix` / `hosts/vm-test/default.nix` for the
  `boot.loader.efi.canTouchEfiVariables` mitigation this phase is
  guarding.

## Files here

- `run.sh` — the harness itself.
- `installer.nix` — instantiates the real `flake.nixosModules.installer`
  (`docs/tasks/0006-installer-image.md`) with the run's throwaway admin
  key, plus one test-only tweak (a serial console) so the ISO `run.sh`
  boots as its QEMU "target" is the same artifact a real install would
  use, not a parallel stand-in.
- `vm-test-system.nix` — the real `hosts/vm-test` `nixosConfiguration`
  under test (`modules/base` + `modules/desktop`), with the run's
  throwaway admin key and a test-only Sway auto-login override.
- `pkgs.nix` — this flake's own pinned nixpkgs, so harness tooling
  (qemu, OVMF, nixos-anywhere) stays on the revision the mechanism is
  tested against.
