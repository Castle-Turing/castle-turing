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
  # Deliberately a *removal*, not a rename, even though
  # modules/agent/default.nix's mkRenamedOptionModule is the precedent a
  # reader arrives here expecting. A rename copies the old value onto
  # the new name unmodified, and these two options take differently
  # *shaped* values: the old one a hash string, the new one a path to a
  # file holding that string. See docs/tasks/0032-password-hash.md §2.
  imports = [
    (lib.mkRemovedOptionModule [ "castle" "admin" "initialHashedPassword" ] ''
      Replaced by castle.admin.hashedPasswordFile
      (docs/tasks/0032-password-hash.md). This is not a rename: the old
      option took a hash STRING; the new one takes a FILE PATH, read at
      every activation (wired to NixOS's own
      users.users.<name>.hashedPasswordFile). Pasting your old hash
      string in verbatim will not work — NixOS will try to open a file
      literally named by that string, fail to find it, and (per
      update-users-groups.pl) leave the account locked ("!") the next
      time it is created fresh, rather than seeded with what you meant.

      Point the new option at a *path* instead: the documented pattern
      is an sops-nix secret's own `.path`, with `neededForUsers = true`
      so it decrypts before accounts are created. See
      docs/private-layer.md's "Secrets" section and
      docs/tasks/0032-password-hash.md's migration steps before you
      touch this on a machine you don't want to break.
    '')
  ];

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
    hashedPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Path, on THIS machine, to a file holding the admin account's
        hashed password (`mkpasswd -m sha-512` generates the hash; the
        file holds exactly that one line). Wired to
        `users.users.<name>.hashedPasswordFile`, which NixOS reads at
        every activation — verified against this flake's pinned nixpkgs,
        `nixos/modules/config/users-groups.nix` and
        `update-users-groups.pl`.

        A Nix *string*, not a path, deliberately — the same reasoning
        `castle.secrets.ageKeyFile` uses (modules/secrets.nix): this
        names a location on the target's own disk, resolved at runtime,
        never a file this repo's own evaluation should read, copy into
        the store, or even require to exist. The documented pattern
        points this at an sops-nix secret's own `.path` — see
        docs/private-layer.md's "Secrets" section.

        Optional at this layer for the same reason the option it
        replaces was: a host with no interactive console (a headless
        server with SSH-key-only admin) has no use for one. A host with
        a login prompt does — see modules/desktop, which asserts this is
        set, and docs/tasks/0003-findings.md finding #1 for why (an
        unset password and a login prompt is a chicken-and-egg console
        lockout).

        **Read this before setting it.** Because this project leaves
        `users.mutableUsers` at its NixOS default (`true`), this option —
        like the one it replaces — only takes effect the moment the
        account is *first created*. Editing the file (or the secret
        behind it) and rebuilding does **not** change an
        already-existing account's password; a resident who wants their
        live password to track this file has to run `passwd` by hand,
        exactly as before. See docs/tasks/0032-password-hash.md's
        "mutableUsers" and "The lockout story" sections for the full
        reasoning and the recovery path if a wrong or missing secret
        locks a fresh account out of password login.

        Whatever value seeds the account, a resident who wants a real
        password should change it with `passwd` after first login — see
        the login-reminder mechanism below, which nags exactly until
        that happens and never locks the account to force it (no
        `chage`-style forced expiry: that interacts badly with
        greetd/tuigreet and risks recreating finding #1 from the other
        direction).
      '';
    };
  };

  # Chassis composition facts, declared here rather than in
  # modules/desktop even though today's only consumer is the desktop's
  # status bar (task 0020 item 3): castle.display is named for its
  # consumer, but castle.hardware is named for the *fact*, and a
  # headless host must be able to state the same fact — 0003 finding
  # #10 reasons about recovery exactly in terms of "does this machine
  # have a non-Wi-Fi network path", a plausible second consumer.
  options.castle.hardware = {
    hasEthernet = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether the chassis has a wired ethernet port. A machine fact,
        set `false` with `lib.mkDefault` by host modules for portless
        chassis (hosts/xps9370). Consumed by modules/home's status-bar
        config: a machine that has a port should show its state — an
        unplugged cable is real information — while a machine that
        cannot have one must not render a permanent fault for hardware
        that does not exist (task 0020 item 3). Default `true` because
        showing a wired port's state is correct wherever one exists;
        declaring the absence is the host's job, not the framework's
        guess.
      '';
    };
  };

  # Declared here rather than in modules/desktop, even though
  # modules/desktop is what consumes it (services.upower): whether a
  # machine can complete a hibernate is a fact about its disk layout,
  # which a headless host knows just as well as a graphical one — and
  # hosts/vm-test proved it, being unable to state the fact at all
  # while the option lived in a module it does not import.
  options.castle.power = {
    criticalPowerAction = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "PowerOff"
          "Hibernate"
          "HybridSleep"
          "Suspend"
          "Ignore"
        ]
      );
      default = null;
      description = ''
        What upower does when the battery reaches its action level,
        wired to `services.upower.criticalPowerAction`. `null` leaves
        upower's own default (`HybridSleep` at this nixpkgs pin)
        alone. The framework deliberately picks no value: whether a
        machine can hibernate is a fact about its disk layout, so a
        host module supplies this with `lib.mkDefault` (hosts/xps9370
        sets `PowerOff` — zram-only swap, nowhere to write a
        hibernation image) and the private layer may still override.
        The assertion below refuses the hibernate-family actions on a
        swapless machine, whichever layer asked for them.
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
      hashedPasswordFile = cfg.hashedPasswordFile;
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
    # shadow hash against the seed in `hashedPasswordFile` — root
    # already needs to read /etc/shadow for this, so it runs as a
    # systemd service rather than in each interactive shell (which runs
    # as the resident, with no shadow access). It leaves a marker file
    # behind once they differ *and the account actually has a password*
    # — i.e. once `passwd` has genuinely been run; the marker (not the
    # hash) is what the unprivileged shell-startup banner checks, so
    # nagging genuinely stops the moment the password changes rather
    # than running forever. "Differ" alone is not enough to conclude
    # that, and the `case` in the script below is where that is
    # enforced — read its comment before simplifying it away.
    # The check re-runs at boot and
    # (via the path unit below) immediately whenever /etc/shadow is
    # touched, so it catches a same-session `passwd` too, not just the
    # next reboot.
    #
    # The seed is *dereferenced at check time*, never embedded: this
    # script used to interpolate the hash itself
    # (`lib.escapeShellArg cfg.initialHashedPassword`), which put it in
    # the world-readable store by a second route independent of
    # users.users.<name> — docs/tasks/0032-password-hash.md's "Why".
    # Embedding the *path* is not the same thing and not a regression:
    # only a location is disclosed, and the contents are read at runtime
    # by a root-run service, never by the Nix evaluator.
    #
    # Ordering is a guarantee rather than a hope, traced through this
    # project's own boot path (0032 §4): stage-2-init.sh runs
    # `$systemConfig/activate` to completion — including sops-nix's
    # `setupSecretsForUsers`, which `users.deps` puts ahead of account
    # creation — before it execs systemd at all, so multi-user.target
    # cannot be reached until the secret has resolved one way or the
    # other.
    systemd.services.castle-password-reminder-check = lib.mkIf (cfg.hashedPasswordFile != null) {
      description = "Note whether the admin account still has its seeded initial password";
      wantedBy = [ "multi-user.target" ];
      serviceConfig.Type = "oneshot";
      script = ''
        marker=/var/lib/castle-turing/password-changed
        mkdir -p "$(dirname "$marker")"
        seed_file=${lib.escapeShellArg cfg.hashedPasswordFile}
        if [ ! -r "$seed_file" ]; then
          # The seed hasn't decrypted -- yet, or ever, per this task's
          # missing/wrong-key case (docs/tasks/0032-password-hash.md,
          # "The lockout story"). Say nothing rather than guess: leave
          # the marker exactly as it was, so the banner keeps whatever
          # state it last had.
          exit 0
        fi
        seed="$(${pkgs.coreutils}/bin/cat "$seed_file")"
        current="$(${pkgs.gnugrep}/bin/grep -m1 -E ${
          lib.escapeShellArg ("^" + cfg.username + ":")
        } /etc/shadow | ${pkgs.coreutils}/bin/cut -d: -f2)"
        # Two guards, and they answer different questions. Neither is
        # redundant; a future simplifier that removes either reopens a
        # different bug, so both are spelled out.
        #
        # FIRST, the lock prefix, because it is not part of any hash.
        # shadow(5): "If the password field begins with an exclamation
        # mark !, the password is locked. The remaining characters on
        # the line represent the password hash." So `!` is a *prefix on
        # a hash*, and comparing a prefixed field against an unprefixed
        # seed makes the `!` itself look like a password change. That is
        # the bug this strip fixes: a resident who ran `passwd -l`
        # without ever changing their password had shadow read
        # `!$6$seed` against a seed of `$6$seed`, which "differs", so
        # the marker was touched and the banner went quiet while they
        # were still on the shipped seed -- and `passwd -u` would put
        # them straight back on it with nothing ever having said so.
        #
        # Stripping TWO is load-bearing, not defensive, and the second
        # one is the whole reason this is not a one-liner: `!!` (what
        # some tools write for "locked, never had a password") strips
        # once to `!`, which is not empty, so with a single strip it
        # falls past the guard below and compares `!` against the seed
        # -- differs, marker touched, banner silenced. Exactly the class
        # of bug being fixed, reintroduced for one value. Two strips
        # take `!!` to empty, where the guard below catches it.
        stripped=$current
        stripped=''${stripped#!}
        stripped=''${stripped#!}
        case "$stripped" in
          "" | '*')
            # SECOND, and only now that any lock prefix is gone: is
            # there a password behind the lock at all? Empty means no
            # hash (either the field was empty, or it was `!`/`!!` and
            # the strip above emptied it); `*` means password access is
            # disallowed outright, per shadow(5) -- "no password can
            # produce a hash like this". These are what
            # update-users-groups.pl leaves when the seed did not
            # resolve at account creation.
            #
            # Say nothing, exactly as the unreadable-seed branch above
            # does. Without this the check reads "no password" as "the
            # resident changed their password" -- the field is
            # readable, the seed is readable, they differ -- and
            # silences the banner forever on the one machine that most
            # needs it. That inference was sound only while the seed was
            # a build-time string, where shadow always equalled it at
            # creation. It stopped being sound the moment the seed
            # became a runtime file that can fail to decrypt: a first
            # install with a missing or wrong age key creates the
            # account locked, and (because mutableUsers leaves an
            # existing account's shadow entry alone) fixing the key and
            # rebuilding never repairs it. See
            # docs/tasks/0032-password-hash.md "The lockout story",
            # whose SSH-and-passwd recovery is the path a resident here
            # actually needs.
            #
            # The consequence, stated rather than glossed: the marker is
            # left alone, so the banner claims the account "is still
            # using its seeded initial password" when in truth it has
            # none. That is imprecise and it is the right trade -- it
            # points at `passwd`, the actual remedy. Asserting "password
            # changed" from the absence of evidence is the failure shape
            # docs/tasks/0015-filed-not-in-progress.md names: a label
            # that causes the inaction it describes. The residual
            # wording problem is filed as
            # docs/backlog/the-reminder-banner-cannot-say-you-have-no-password.md.
            exit 0
            ;;
        esac
        if [ "$stripped" = "$seed" ]; then
          rm -f "$marker"
        else
          touch "$marker"
        fi
      '';
    };
    systemd.paths.castle-password-reminder-check = lib.mkIf (cfg.hashedPasswordFile != null) {
      description = "Re-run the password-reminder check whenever /etc/shadow changes";
      wantedBy = [ "multi-user.target" ];
      pathConfig.PathModified = "/etc/shadow";
    };

    # The banner itself: generic on purpose (no mention of what the
    # seeded password actually is) and only shown to interactive shells.
    # NixOS sources `environment.interactiveShellInit` for bash and zsh;
    # a private layer that swaps in a different shell needs to wire this
    # itself.
    environment.interactiveShellInit = lib.mkIf (cfg.hashedPasswordFile != null) ''
      if [ ! -e /var/lib/castle-turing/password-changed ]; then
        printf '\n\033[1;33mNote:\033[0m this account is still using its seeded initial password. Run \033[1mpasswd\033[0m to set your own.\n\n'
      fi
    '';
  };
}
