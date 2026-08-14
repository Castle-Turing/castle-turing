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
      description = ''
        Login name of the human administrator. Supplied by the private
        layer (or, until that exists, by the host module).
      '';
    };
    sshKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = ''
        SSH public keys granted admin access. Public keys are not secrets,
        but they identify a person, so they are configuration — not
        framework.
      '';
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.username != "";
        message = ''
          castle.admin.username is unset. Every host built on modules/base
          must supply an admin identity — set it in hosts/<name>/ (or the
          private layer, once its shape is decided).
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
