# modules/base — the minimal substrate every Castle Turing host shares.
#
# Mechanism only: this module defines *what* every host provides (a
# remotely-operable, flake-managed NixOS with an admin who can rebuild it).
# *Who* the admin is comes from option values supplied outside this module.
{
  config,
  lib,
  pkgs,
  ...
}:

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
    initialHashedPassword = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Hashed (never plaintext) password for the admin account,
        generated with e.g. `mkpasswd -m sha-512`. Wired into
        `users.users.<name>.initialHashedPassword`, so it only seeds the
        account at first creation and is never overwritten by later
        rebuilds — a resident who changes their password with `passwd`
        keeps that change.

        Optional at this layer: a host with no interactive console (the
        vm-test harness, a headless server with SSH-key-only admin) has
        no use for one. A host with a login prompt does — see
        modules/desktop, which asserts this is set, and
        docs/tasks/0003-findings.md finding #1 for why (an unset
        password and a login prompt is a chicken-and-egg console
        lockout). Secret-adjacent data — supplied by the private layer,
        never this repo. See docs/private-layer.md.

        Whatever value is seeded here, a resident who wants a real
        password should change it with `passwd` after first login — see
        the login-reminder mechanism below, which nags exactly until
        that happens and never locks the account to force it (no
        `chage`-style forced expiry: that interacts badly with
        greetd/tuigreet and risks recreating finding #1 from the other
        direction).
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
      initialHashedPassword = cfg.initialHashedPassword;
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

    # Seeded-password reminder. Deliberately NOT forced password expiry
    # (`chage -d 0`/`passwordExpiry`-style options): that makes PAM
    # demand a change *during* login, which tuigreet/greetd handle badly
    # enough to risk recreating finding #1 (docs/tasks/0003-findings.md)
    # from the opposite direction — a "change your password" prompt
    # nobody can get past instead of no password at all. This can never
    # lock anyone out: worst case, a resident ignores it forever and
    # keeps the seeded password.
    #
    # Mechanism: a root-run check compares the account's *current*
    # shadow hash against the configured `initialHashedPassword` — root
    # already needs to read /etc/shadow for this, so it runs as a
    # systemd service rather than in each interactive shell (which runs
    # as the resident, with no shadow access). It leaves a marker file
    # behind once they differ, i.e. once `passwd` has actually been run;
    # the marker (not the hash) is what the unprivileged shell-startup
    # banner checks, so nagging genuinely stops the moment the password
    # changes rather than running forever. The check re-runs at boot and
    # (via the path unit below) immediately whenever /etc/shadow is
    # touched, so it catches a same-session `passwd` too, not just the
    # next reboot.
    systemd.services.castle-password-reminder-check = lib.mkIf (cfg.initialHashedPassword != null) {
      description = "Note whether the admin account still has its seeded initial password";
      wantedBy = [ "multi-user.target" ];
      serviceConfig.Type = "oneshot";
      script = ''
        marker=/var/lib/castle-turing/password-changed
        mkdir -p "$(dirname "$marker")"
        current="$(${pkgs.gnugrep}/bin/grep -m1 -E ${
          lib.escapeShellArg ("^" + cfg.username + ":")
        } /etc/shadow | ${pkgs.coreutils}/bin/cut -d: -f2)"
        if [ "$current" = ${lib.escapeShellArg cfg.initialHashedPassword} ]; then
          rm -f "$marker"
        else
          touch "$marker"
        fi
      '';
    };
    systemd.paths.castle-password-reminder-check = lib.mkIf (cfg.initialHashedPassword != null) {
      description = "Re-run the password-reminder check whenever /etc/shadow changes";
      wantedBy = [ "multi-user.target" ];
      pathConfig.PathModified = "/etc/shadow";
    };

    # The banner itself: generic on purpose (no mention of what the
    # seeded password actually is) and only shown to interactive shells.
    # NixOS sources `environment.interactiveShellInit` for bash and zsh;
    # a private layer that swaps in a different shell needs to wire this
    # itself.
    environment.interactiveShellInit = lib.mkIf (cfg.initialHashedPassword != null) ''
      if [ ! -e /var/lib/castle-turing/password-changed ]; then
        printf '\n\033[1;33mNote:\033[0m this account is still using its seeded initial password. Run \033[1mpasswd\033[0m to set your own.\n\n'
      fi
    '';
  };
}
