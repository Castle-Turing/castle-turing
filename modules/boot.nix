# modules/boot.nix — the UEFI boot-loader posture every Castle Turing
# host currently shares: systemd-boot, allowed to write the firmware's
# EFI variables.
#
# Mechanism only, on the modules/disk-layout.nix precedent: hosts opt in
# through flake.nix's per-host wrappers (nixosModules.host-*), never via
# modules/base — modules/installer.nix imports base, and the live
# installer image boots the ISO profile's own loader, not systemd-boot,
# so this posture must stay a per-host decision rather than a
# base-wide one.
#
# Why these two lines are one invariant and not two independent
# settings: the thing being protected is the ESP fallback path
# (EFI/BOOT/BOOTX64.EFI). A firmware that loses its NVRAM boot entries —
# a dead CMOS battery, a fresh OVMF vars file — falls back to exactly
# that path, and `bootctl install` writes a copy of systemd-boot there
# unconditionally: there is no `installAsRemovable`-style option for
# systemd-boot to reach for (that's a GRUB-only knob; confirmed by
# reading nixos/modules/system/boot/loader/systemd-boot/ in this flake's
# pinned nixpkgs — nothing there matches "removable").
# docs/tasks/0003-findings.md finding #2 records the real "No Boot
# Device Found" this posture exists to prevent, finding #5 the clean
# redeploy that proved the fallback file survives, and
# test/vm-install/run.sh's phase-4 NVRAM-wipe assertion regression-tests
# it on every harness run.
#
# Host-specific evidence stays in the host files (the XPS's dead-CMOS
# history, the VM harness's reason to exist); only the shared mechanism
# and its rationale live here.
#
# Plain assignments, deliberately not lib.mkDefault: this is a framework
# invariant, not a taste default. No host today wants a different
# posture; if one ever genuinely cannot touch NVRAM, that second case is
# when an option gets carved (docs/tasks/0035-boot-fallback-dedup.md) —
# until then, overriding takes a loud lib.mkForce.
{ ... }:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
