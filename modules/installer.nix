# modules/installer.nix — the agentic installer image (docs/tasks/0006).
#
# Mechanism only, per Principle 01. This module turns the stock NixOS
# installer media into a Castle Turing artifact: bootable, and
# immediately SSH-reachable with zero console interaction. It does this
# by composing two things that already exist rather than inventing a
# parallel identity mechanism:
#
#   - nixpkgs's own minimal installer profile (the live environment
#     itself: kernel, squashfs, boot menu, NetworkManager);
#   - modules/base, which already turns castle.admin.sshKeys into a
#     hardened, key-only sshd and an authorized root account.
#
# The private layer supplies exactly the same castle.admin values it
# already supplies for the installed system (docs/private-layer.md) —
# one key, declared once, reused here unchanged. That is what "the key
# comes from the private layer, exactly as castle.admin does today"
# (docs/tasks/0006-installer-image.md) means in practice: no new
# private-layer file or format, just a second nixosConfiguration in the
# private flake that imports this module instead of (or alongside) a
# host module. See docs/private-layer.md for the worked example.
#
# This closes docs/tasks/0003-findings.md finding #3 (installer
# ephemerality): no more per-boot nmtui-then-curl-a-key-from-GitHub
# ceremony. Finding #1 (first-boot lockout) is closed by the *installed*
# system being SSH-reachable, which this module doesn't touch — see
# modules/base and hosts/xps9370/README.md.
{ modulesPath, lib, ... }:
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    ./base
  ];

  config = {
    # Nobody is ever at this console by design — don't sit at a boot
    # menu waiting for a keypress that will never come. (0 disables the
    # timeout entirely for both the BIOS/syslinux and EFI/grub menus
    # this profile generates; confirmed against nixpkgs's
    # installer/cd-dvd/iso-image.nix, which reads this same option.)
    boot.loader.timeout = lib.mkForce 0;

    # Advertise over mDNS so an operator (human or agent) can reach the
    # machine without ever reading its IP off a console or a router's
    # admin page: `ssh root@castle-installer.local`. A private layer
    # composing this module can override networking.hostName per host
    # (e.g. "xps9370-installer") if it builds more than one installer
    # image and needs them distinguishable on the same LAN segment.
    networking.hostName = lib.mkDefault "castle-installer";
    services.avahi = {
      enable = true;
      openFirewall = true;
      publish = {
        enable = true;
        addresses = true;
      };
    };

    # Network provisioning, and the one place this task's goal is
    # deliberately narrower than "no manual network step, ever":
    #
    # The installation-device profile this image is built on already
    # enables NetworkManager (nixos/modules/profiles/installation-device.nix),
    # which auto-connects a wired interface over DHCP with zero
    # interaction — asserted explicitly here (rather than left as an
    # inherited default) because it's the supported unattended path this
    # mechanism is built around. Plug the target into Ethernet before
    # powering it on and the machine reaches the LAN, and is
    # SSH-reachable, with nobody ever touching its keyboard.
    #
    # Wi-Fi is intentionally NOT provisioned by this module. A Wi-Fi PSK
    # is private-layer data (Principle 01), and this repo has no secrets
    # mechanism yet — sops-nix is explicitly out of scope for this task
    # (docs/tasks/0006-installer-image.md). Baking a PSK into a
    # NetworkManager connection profile at ISO-build time would mean
    # writing it in plaintext into a private-layer Nix file, which is
    # exactly the kind of plaintext-credential-in-a-repo Principle 01 and
    # docs/private-layer.md rule out even for the private repo ("a
    # private repo is access control, not encryption"). Rather than
    # invent a hack or silently narrow the goal, this falls back to the
    # honest answer: Ethernet is the unattended path; Wi-Fi still needs a
    # human at this image's console running `nmtui`, same as the stock
    # installer, until sops-nix (or equivalent) lands and the PSK can be
    # encrypted instead of baked in cleartext. See
    # docs/private-layer.md and hosts/xps9370/README.md.
    networking.networkmanager.enable = lib.mkDefault true;

    # A discarded-at-EOL live image: build speed beats a tightly packed
    # download here. A private layer building an image meant to be
    # redistributed (rather than used once and thrown away) can
    # `lib.mkForce` a stronger compressor.
    isoImage.squashfsCompression = lib.mkDefault "gzip -Xcompression-level 1";
  };
}
