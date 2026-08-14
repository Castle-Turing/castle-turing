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

  boot.loader.systemd-boot.enable = true;
  # This chassis has a flaky CMOS battery history: on power loss the
  # firmware forgets its NVRAM boot entries and falls back to the ESP
  # default path (EFI/BOOT/BOOTX64.EFI). `bootctl install` writes a copy
  # of systemd-boot to that fallback path by default (no extra option
  # needed — systemd-boot has no installAsRemovable, that is a GRUB
  # option), so the machine still boots NixOS after a reset.
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
