# hosts/xps9370 — Dell XPS 13 9370, the reference host.
#
# Machine facts only: the resident (castle.admin) is supplied by the
# consuming private layer. The nixos-hardware and disko modules this
# host needs are bound by flake.nix's `nixosModules.host-xps9370`
# export, which is how this directory should be consumed.
{ lib, ... }:

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

  # This chassis's touchscreen option is the 3840x2160 (4K UHD) panel at
  # 13.3" — about 331 PPI, roughly double a "normal" ~160 PPI laptop
  # display (docs/vision.md: "Dell XPS 13 9370 ... touchscreen", which
  # on this model only ever shipped paired with the 4K panel, never the
  # 1080p one). Sway's own auto-detection leaves everything at 1x, which
  # is what task 0008's real errand ("the cursor is too small") actually
  # was: not a cursor-theme bug, a panel-density fact this host module
  # is exactly the right layer for (Principle 01 consequence 2 — a
  # panel's DPI identifies no one). `lib.mkDefault` so a private layer
  # can still override for taste, per castle.display.scale's own
  # description in modules/desktop.
  #
  # cursorSize is set explicitly alongside scale, but NOT to compensate
  # for scale — Sway itself already multiplies the cursor size it's
  # given by the output scale (that's what `seat * xcursor_theme <name>
  # <size>`, wired from home.pointerCursor.size, feeds into), so this
  # value is pre-scale, the same way a font point size is. Doubling it
  # here on top of a 2.0 output scale was tried first (48, reasoning
  # from the real XWayland/GTK gap below) and double-compensated: Sway
  # rendered it at roughly 96 physical pixels, about 7mm on this panel —
  # confirmed on the first real deploy, resident's own words "the cursor
  # is freaking gigantic" (docs/tasks/0013-first-deploy-findings.md).
  # 18 is the corrected, eye-calibrated value on this panel at scale
  # 2.0 (36 physical pixels, ~2.8mm) — below the 24px unscaled default,
  # and still visibly larger than what task 0008's original "too small"
  # complaint was about, because that complaint predates `scale` being
  # set at all: at 1x the pointer was genuinely native-resolution-tiny
  # on a 331 PPI panel, not just under-sized relative to a 2.0-scaled
  # UI. Don't "fix" this back toward 24 or higher on the assumption that
  # a below-default number must be a regression; it isn't, and 0013 is
  # the record of why.
  #
  # The real, separate problem: XWayland and some GTK cursor-rendering
  # paths do not reliably follow Sway's own output scale for the
  # pointer glyph itself (a commonly reported Sway+XWayland gap), so
  # those clients can still show a native-resolution, comparatively
  # tiny cursor even with this value correct for Sway's own seat. This
  # option does not solve that — it only controls what Sway itself
  # (and, via the same XCURSOR_SIZE variable, GTK/X11 clients that *do*
  # follow it) renders. Treating 48 as "the fix for the XWayland gap"
  # is exactly the reasoning that produced the double-scaled bug; the
  # gap is real but out of scope here (0013's non-goals) and needs its
  # own investigation, not a bigger number on this option.
  #
  # modules/home only wires home.pointerCursor at all when
  # castle.display.cursorTheme is non-null (an unset theme name leaves
  # the whole pointer-cursor slot untouched, by design — see that
  # option's description in modules/desktop), so cursorSize alone would
  # otherwise be a silent no-op on this host. modules/desktop ships
  # pkgs.bibata-cursors specifically so a theme name has something real
  # to resolve to; naming one of its themes here is an aesthetic
  # default, not personal data (Principle 01 consequence 2 — nothing
  # about a cursor theme identifies a resident), and a private layer's
  # own taste still overrides it.
  #
  # castle.display is declared by modules/desktop, not by this file —
  # this host module assumes any consumer pairing it with
  # nixosModules.host-xps9370 also imports nixosModules.desktop, the way
  # every nixosConfiguration in this repo's own flake.nix does. An
  # earlier version of this block tried to guard that assumption away
  # with `lib.optionalAttrs (options.castle ? display) { ... }`, so a
  # from-scratch headless pairing of this host without desktop would
  # still evaluate — but reading the `options` module argument to decide
  # which keys *this same module* returns is a real infinite-recursion
  # trap in Nix's module system (config for a still-being-assembled
  # module set depending on the fully-assembled options tree), not
  # just an edge case; `nix flake check` caught it immediately. Reverted
  # in favor of this honest, documented coupling instead: if you ever
  # write a private layer that imports host-xps9370 without desktop,
  # override castle.display back out (or drop this whole block) in your
  # own resident.nix.
  castle.display = {
    scale = lib.mkDefault 2.0;
    cursorTheme = lib.mkDefault "Bibata-Modern-Classic";
    cursorSize = lib.mkDefault 18;
  };
}
