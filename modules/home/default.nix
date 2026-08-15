# modules/home — home-manager wired in as a NixOS module: the resident's
# per-user environment (dotfile-equivalent config), as opposed to
# modules/base's system-wide state.
#
# Mechanism only. This module is consumed through flake.nix's
# `nixosModules.home` export, which binds this flake's home-manager
# input so consumers need not add it themselves — same pattern as
# `nixosModules.host-xps9370` binding nixos-hardware and disko.
#
# The one thing this module currently configures — git's commit
# identity — is a direct instance of Principle 01: home-manager's
# `programs.git` needs a name and email to be useful, and both are
# personal data (CLAUDE.md's hard rule, Principle 01). They are never
# defaulted or invented here; a private layer that leaves them unset
# fails this module's assertions instead of silently committing as
# nobody or as a name we made up.
{ config, lib, ... }:

let
  cfg = config.castle.person;
  adminCfg = config.castle.admin;
in
{
  options.castle.person = {
    gitUserName = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Git commit author name, wired into home-manager's
        `programs.git.userName`. Personal data — supplied by the
        private layer, never this repo. See docs/private-layer.md.
      '';
    };
    gitUserEmail = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Git commit author email, wired into home-manager's
        `programs.git.userEmail`. Personal data — supplied by the
        private layer, never this repo. See docs/private-layer.md.
      '';
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.gitUserName != "";
        message = ''
          castle.person.gitUserName is unset. modules/home wires this
          into home-manager's git config, so a resident's private layer
          must supply it — see docs/private-layer.md. (This is exactly
          the personal data CLAUDE.md forbids defaulting or inventing:
          it must come from the private layer, not from this module.)
        '';
      }
      {
        assertion = cfg.gitUserEmail != "";
        message = ''
          castle.person.gitUserEmail is unset — see docs/private-layer.md.
        '';
      }
    ];

    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    # The private layer names the admin (castle.admin.username,
    # modules/base); the same person is who home-manager is managing a
    # home for, so this module reads that option rather than defining
    # its own username slot.
    home-manager.users.${adminCfg.username} = {
      # Pinned once, like system.stateVersion in hosts/<name> — not
      # bumped casually after first deploy. See home-manager's own
      # release.json for what the current framework nixpkgs pin expects.
      home.stateVersion = "26.11";

      programs.git = {
        enable = true;
        # `userName`/`userEmail` are renamed as of this flake's pinned
        # home-manager; use the current option path so this doesn't
        # start life already deprecated.
        settings.user = {
          name = cfg.gitUserName;
          email = cfg.gitUserEmail;
        };
      };
    };
  };
}
