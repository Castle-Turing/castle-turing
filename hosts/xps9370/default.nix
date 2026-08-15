# hosts/xps9370 — Dell XPS 13 9370, the reference host.
#
# Machine facts only: the resident (castle.admin) is supplied by the
# consuming private layer. The nixos-hardware and disko modules this
# host needs are bound by flake.nix's `nixosModules.host-xps9370`
# export, which is how this directory should be consumed.
{ ... }:

{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "xps9370";

  # This chassis's Killer/Atheros Wi-Fi card (ath10k_pci) needs a firmware
  # blob NixOS doesn't ship by default. Confirmed via journalctl on the
  # first real install: "could not fetch firmware files (-2)" — the
  # nixos-hardware dell-xps-13-9370 module does not set this itself.
  hardware.enableRedistributableFirmware = true;

  boot.loader.systemd-boot.enable = true;
  # This chassis's CMOS battery was replaced during task 0003, but treat
  # NVRAM as unreliable regardless — it's cheap insurance and this
  # config has no way to detect a future failure. On power loss with a
  # dead battery, the firmware forgets its NVRAM boot entries and falls
  # back to the ESP default path (EFI/BOOT/BOOTX64.EFI). `bootctl
  # install` is supposed to write a copy of systemd-boot to that
  # fallback path unconditionally — confirmed by reading the
  # systemd-boot module source in this flake's pinned nixpkgs, there is
  # no `installAsRemovable`-style option for systemd-boot to reach for
  # (that's a GRUB-only knob; nothing in
  # nixos/modules/system/boot/loader/systemd-boot/ matches "removable").
  # On the first real install this fallback copy did not survive to the
  # deployed ESP despite the install log claiming to have written it —
  # see docs/tasks/0003-findings.md finding #2 for the investigation and
  # finding #5 for how a clean redeploy (stale NVRAM entries removed,
  # firmware back in UEFI mode) produced a fallback file that did
  # survive, checksum-verified against the source binary.
  boot.loader.efi.canTouchEfiVariables = true;

  # 16GB RAM, no hibernation use-case on a project machine: compressed
  # RAM swap instead of a swap partition keeps the disk layout simpler.
  zramSwap.enable = true;

  # Wi-Fi is this chassis's network path; NetworkManager belongs here, not
  # in modules/base, since a headless/wired host wouldn't want it. Wi-Fi
  # credentials are entered on the machine and live in
  # /etc/NetworkManager/system-connections — private state that never
  # enters this repo. Secrets tooling may take this over later.
  networking.networkmanager.enable = true;

  # First installed from nixos-unstable ahead of the 26.11 release.
  # Never change this after install.
  system.stateVersion = "26.11";
}
