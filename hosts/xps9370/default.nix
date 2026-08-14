# hosts/xps9370 — Dell XPS 13 9370, the reference host.
{ inputs, ... }:

{
  imports = [
    inputs.nixos-hardware.nixosModules.dell-xps-13-9370
    ./disko.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "xps9370";

  boot.loader.systemd-boot.enable = true;
  # This chassis has a flaky CMOS battery history: on power loss the
  # firmware forgets its NVRAM boot entries and falls back to the ESP
  # default path (EFI/BOOT/BOOTX64.EFI). bootctl installs a copy of
  # systemd-boot there, so the machine still boots NixOS after a reset.
  boot.loader.efi.canTouchEfiVariables = true;

  # 16GB RAM, no hibernation use-case on a project machine: compressed
  # RAM swap instead of a swap partition keeps the disk layout simpler.
  zramSwap.enable = true;

  # TODO(private-layer): these values identify a person, not a machine.
  # They move to the private layer as soon as its shape is decided
  # (Principle 01, consequence 3). Adopters: replace with your own.
  castle.admin = {
    username = "resident";
    sshKeys = [
      "ssh-ed25519 REPLACE-WITH-YOUR-PUBLIC-KEY this-is-a-placeholder-not-a-key"
    ];
  };

  # First installed from nixos-unstable ahead of the 26.11 release.
  # Never change this after install.
  system.stateVersion = "26.11";
}
