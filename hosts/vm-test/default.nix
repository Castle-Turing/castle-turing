# hosts/vm-test — a fully-virtual QEMU/OVMF machine. Not a real host
# anyone deploys to: it exists so the install mechanism (modules/base,
# modules/disk-layout.nix, the boot loader posture) can be exercised
# unattended in CI, per docs/tasks/0004-install-test-harness.md. Machine
# facts only, same shape as hosts/xps9370 — the resident (castle.admin)
# comes from outside this module; the harness (test/vm-install/) supplies
# a throwaway key generated fresh per run, never committed here.
{ ... }:

{
  imports = [ ./disko.nix ];

  networking.hostName = "vm-test";

  # This "hardware" is a fixed virtual machine shape (QEMU's virtio disk
  # and NIC, OVMF firmware), not a real machine to be probed — so unlike
  # hosts/xps9370 there is no generated hardware-configuration.nix; the
  # boot-critical modules are just declared directly.
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_scsi"
    "virtio_blk"
    "ahci"
    "sd_mod"
  ];
  boot.kernelModules = [
    "virtio_balloon"
    "virtio_console"
    "virtio_rng"
  ];

  boot.loader.systemd-boot.enable = true;
  # Nobody is ever at this console; don't sit at a boot menu.
  boot.loader.timeout = 0;
  # test/vm-install/run.sh captures qemu's -serial as the diagnostic log
  # for boot failures; without this the kernel only writes to the
  # (discarded, -display none) VGA console and that log is empty.
  boot.kernelParams = [ "console=ttyS0" ];
  # Same fallback-boot posture as hosts/xps9370, and the reason this host
  # exists: docs/tasks/0003-findings.md (finding #2/#5, first-install
  # branch) traced a real "No Boot Device Found" failure to the ESP
  # fallback file (EFI/BOOT/BOOTX64.EFI) not surviving install. This
  # harness's NVRAM-wipe assertion (test/vm-install/run.sh) exists
  # specifically to catch a regression here before it costs a physical
  # USB round-trip again.
  boot.loader.efi.canTouchEfiVariables = true;

  # SCRATCH — task 0004 scope item 4: intentional-breakage proof that the
  # harness catches a real regression. Deletes the ESP fallback file on
  # every boot, reproducing docs/tasks/0003-findings.md finding #2 (the
  # fallback copy not surviving) by hand. Phases 1-3 (NVRAM intact) still
  # pass; phase 4 (NVRAM wiped, relies on this exact file) should go red.
  # Reverted in the next commit once that's confirmed.
  #
  # `sync` matters: the harness deliberately hard-kills qemu right after
  # SSH answers (that's the power-cycle assertion), and this unit already
  # finishes well before sshd starts (verified in phase2's serial log) —
  # but on a vfat ESP, `rm` alone can still leave the directory-entry
  # write sitting in the page cache, unflushed to the disk image, so the
  # very next hard-kill silently discarded it and phase4 stayed green.
  systemd.services.harness-scratch-break-fallback = {
    description = "SCRATCH (task 0004): delete the ESP fallback bootloader";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    serviceConfig.Type = "oneshot";
    script = "rm -f /boot/EFI/BOOT/BOOTX64.EFI && sync";
  };

  # QEMU's usermode networking (SLiRP) hands out an address over DHCP;
  # this must work with zero console interaction — the harness's whole
  # point is proving SSH comes up on its own (docs/tasks/0003-findings.md
  # finding #1, the first-boot lockout).
  networking.useDHCP = true;
  networking.useNetworkd = false;

  # Never a real machine anyone upgrades in place; pinned to match the
  # framework's current nixpkgs so the harness stays boring.
  system.stateVersion = "26.11";
}
