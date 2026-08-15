# test/vm-install — the install-loop test harness

What `docs/tasks/0004-install-test-harness.md` asked for: a way to
exercise the real install mechanism (`hosts/vm-test/` +
`modules/base` + `modules/disk-layout.nix`) end to end, unattended,
so a regression like task 0003's physical-shakedown findings goes red
in CI instead of costing a human a USB round-trip.

## What it asserts

Run in order, against one QEMU/OVMF VM:

1. `nixos-anywhere` installs the real target (disko partitions the
   virtio disk, `nixos-install` runs) against a booted installer image.
2. The VM reboots from its own disk with the installer media detached,
   and SSH comes up as the admin, by key, **with zero console
   interaction** — the regression test for the first-boot lockout
   (`docs/tasks/0003-findings.md` finding #1).
3. The VM survives a power-cycle: a hard stop (`kill -9` the QEMU
   process — no clean shutdown) followed by a restart with its NVRAM
   intact.
4. The VM survives an NVRAM wipe: its OVMF vars file is replaced with a
   pristine (blank) one and it's restarted again, forcing the firmware
   down the UEFI-standard fallback path `EFI/BOOT/BOOTX64.EFI` instead
   of any NVRAM boot entry. This is the dead-CMOS lesson from finding
   #2/#5 — a missing or non-surviving fallback file is exactly the bug
   that produced "No Boot Device Found" on the real XPS.

Each step is a hard assertion: the script exits non-zero the moment one
fails, and says which assertion failed and where its log is.

## Why a custom harness and not `nixos-anywhere --vm-test`

`nixos-anywhere --vm-test` builds the system and disko script and
partitions a scratch disk inside a VM to validate the disk
configuration — useful, but one-shot: it doesn't leave a persistently
bootable VM to test reboot, power-cycle, or NVRAM-fallback behavior
against, and it doesn't drive `nixos-anywhere`'s real remote-install
path (SSH into a running installer, over a network) the way an actual
deploy does. Since three of this task's four required assertions are
specifically about what happens on later boots, `--vm-test` can't
express them; this harness drives QEMU directly instead, and still uses
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

Phase names map directly to the assertions above:

- `phase1-installer` — the installer never came up, or
  `nixos-anywhere` itself failed (disko/format/copy/`nixos-install`
  error) — check `phase1-nixos-anywhere.log` first.
- `phase2-first-boot` — the freshly installed disk didn't boot on its
  own, or SSH as the admin needed something console/Wi-Fi/password
  shaped it shouldn't. Check `phase2-first-boot.serial.log` for where
  boot stalled.
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
- `installer.nix` — the SSH-reachable installer image `run.sh` boots as
  its QEMU "target"; standing in for a human joining Wi-Fi and pasting
  a key at a physical console (`docs/tasks/0003-findings.md` finding
  #3).
- `vm-test-system.nix` — the real `hosts/vm-test` `nixosConfiguration`
  under test, with the run's throwaway admin key.
- `pkgs.nix` — this flake's own pinned nixpkgs, so harness tooling
  (qemu, OVMF, nixos-anywhere) stays on the revision the mechanism is
  tested against.
