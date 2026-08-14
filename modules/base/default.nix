# modules/base — the minimal substrate every Castle Turing host shares.
#
# Mechanism only: this module defines *what* every host provides (a
# remotely-operable, flake-managed NixOS with an admin who can rebuild it).
# *Who* the admin is comes from option values supplied outside this module.
{ config, lib, ... }:

let
  cfg = config.castle.admin;
in
{
  options.castle.admin = {
    username = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Login name of the human administrator. Supplied by the private
        layer — see docs/private-layer.md.
      '';
    };
    sshKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        SSH public keys granted admin access. Public keys are not secrets,
        but they identify a person, so they are configuration — not
        framework. Supplied by the private layer — see
        docs/private-layer.md.
      '';
    };
  };

  config = {
    # Both fields default to empty (rather than being left without a
    # default) so a missing private layer fails here, with this message,
    # instead of on NixOS's generic "option used but not defined" error.
    assertions = [
      {
        assertion = cfg.username != "";
        message = ''
          castle.admin.username is unset. Every host built on
          modules/base must be given an admin identity by its private
          layer — see docs/private-layer.md.
        '';
      }
      {
        assertion = cfg.sshKeys != [ ];
        message = ''
          castle.admin.sshKeys is empty. Without at least one key,
          nothing can authenticate to this host over SSH (password auth
          is disabled) — supply one from the private layer, see
          docs/private-layer.md.
        '';
      }
    ];

    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };

    # Both the admin user and root trust the same key set: nixos-anywhere
    # installs as root, and remote rebuilds may target either account.
    # Kept together deliberately so rotating a key is one edit, not two.
    users.users.${cfg.username} = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "networkmanager"
      ];
      openssh.authorizedKeys.keys = cfg.sshKeys;
    };
    users.users.root.openssh.authorizedKeys.keys = cfg.sshKeys;
    # Remote `nixos-rebuild --target-host` needs non-interactive sudo.
    security.sudo.wheelNeedsPassword = false;

    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        # Key-only root access: nixos-anywhere installs as root, and
        # remote rebuilds target root@host.
        PermitRootLogin = "prohibit-password";
      };
    };
  };
}
