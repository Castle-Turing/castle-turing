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
  # One definition for the reminder machinery's state directory: the
  # check script's default (its $2 test seam) and the banner's
  # hardcoded reads are derived from this, so they cannot drift apart
  # -- the table test always passes explicit paths and could never
  # notice the default and the banner disagreeing.
  reminderStateDir = "/var/lib/castle-turing";
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
    # Mechanism: a root-run check classifies the account's *current*
    # shadow field against the seed in `hashedPasswordFile` — root
    # already needs to read /etc/shadow for this, so it runs as a
    # systemd service rather than in each interactive shell (which runs
    # as the resident, with no shadow access). It records what it found
    # as at most one of two empty marker files, which are all the
    # unprivileged shell-startup banner reads
    # (docs/tasks/0036-reminder-banner-states.md):
    #
    #   password-changed — the field is a real hash differing from the
    #     seed, i.e. `passwd` has genuinely been run. Banner: silent,
    #     from the moment the password changes. "Differ" alone is not
    #     enough to conclude this, and the `case` in the script below
    #     is where that is enforced — read its comment before
    #     simplifying it away.
    #   password-absent — the field carries no usable password at all
    #     (`!`, `!!`, `*` or empty), the state a seed that failed to
    #     decrypt at account creation leaves behind.
    #   neither — still on the seeded password, or never decidable.
    #
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
        # Test seams, not configuration
        # (docs/tasks/0036-reminder-banner-states.md): systemd starts
        # this with no arguments, so a real machine always uses the
        # real paths; the flake check
        # (test/password-reminder/check.nix) runs this same generated
        # script -- not a copy -- against fixture files.
        shadow_file="''${1:-/etc/shadow}"
        state_dir="''${2:-${reminderStateDir}}"
        seed_file="''${3:-}"
        if [ -z "$seed_file" ]; then
          seed_file=${lib.escapeShellArg cfg.hashedPasswordFile}
        fi
        changed_marker="$state_dir/password-changed"
        absent_marker="$state_dir/password-absent"
        mkdir -p "$state_dir"
        # The shadow field is read and classified *before* the seed is
        # ever consulted, because the no-password state is knowable
        # from the field alone: on the machine that most needs that
        # message, a missing age key makes the seed unreadable *and*
        # the account passwordless, and an order that checked the seed
        # first exited before ever looking (the pre-0036 shape of this
        # script).
        # The grep's own exit status matters: a shadow file with *no
        # line for the account at all* (a renamed admin username, a
        # mid-rewrite copy of the file) is not evidence about
        # passwords, and must not be conflated with an account whose
        # field is empty. A bare pipeline into cut would swallow
        # grep's failure and classify "no line" as "no password",
        # rewriting markers over a state this script knows nothing
        # about -- so bail out first, touching nothing.
        if ! shadow_line="$(${pkgs.gnugrep}/bin/grep -m1 -E ${
          # escapeRegex so a username containing ERE metacharacters
          # (legal: `.`, `+`) cannot match some *other* account's line
          # and classify the wrong password.
          lib.escapeShellArg ("^" + lib.escapeRegex cfg.username + ":")
        } "$shadow_file")"; then
          exit 0
        fi
        current="$(printf '%s' "$shadow_line" | ${pkgs.coreutils}/bin/cut -d: -f2)"
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
            # resolve at account creation: a first install with a
            # missing or wrong age key creates the account locked, and
            # (because mutableUsers leaves an existing account's shadow
            # entry alone) fixing the key and rebuilding never repairs
            # it. See docs/tasks/0032-password-hash.md "The lockout
            # story".
            #
            # Before 0036 this branch said nothing, and the banner --
            # whose only vocabulary was password-changed's absence --
            # claimed the account was "still using its seeded initial
            # password" when in truth it had none. Now the state is
            # recorded as its own marker and the banner says what is
            # actually true, including the remedy that actually works
            # here: `sudo passwd <user>`, because plain `passwd` cannot
            # authenticate an account with no password.
            #
            # Removing password-changed is a deliberate, argued
            # deviation from 0032's leave-it-alone
            # (docs/tasks/0036-reminder-banner-states.md): 0032 could
            # not act because any write to a boolean whose absence
            # means "seeded" lied in one direction or the other. With a
            # word for the state, acting is honest -- the field is
            # positive evidence that no chosen password exists *now*,
            # and a surviving password-changed would silence the banner
            # on an account with no password, the exact silencing class
            # 0032 fixed. Remove-then-touch, in that order: if the
            # script dies between the two writes, the surviving state
            # is "neither marker", which nags (safely, if with the
            # wrong message) until the next run -- the reverse order
            # could strand *both* markers, and both markers read as
            # silence, the one permanent state this machinery must
            # never fail into. A shell racing the pair sees at worst
            # one momentarily wrong nag.
            rm -f "$changed_marker"
            touch "$absent_marker"
            exit 0
            ;;
        esac
        # A real hash exists, so "no password at all" is over --
        # whatever the seed comparison below turns out to say, or
        # whether it can run at all.
        if [ ! -r "$seed_file" ]; then
          # The seed hasn't decrypted -- yet, or ever, per 0032's
          # missing/wrong-key case ("The lockout story"). Whether the
          # hash above is the seed or a chosen password cannot be
          # decided by comparison, so as a rule say nothing rather
          # than guess: leave both markers exactly as they were, and
          # the banner keeps whatever state it last had.
          #
          # One transition IS decidable without the seed, and skipping
          # it left the recovery path ending in a false banner (caught
          # by cross-model review): the account demonstrably had no
          # usable password at the last check, and now a real hash
          # exists while the seed has still never been readable. The
          # hash cannot be the seed -- only account creation writes
          # the seed into shadow, and creation with an unresolved seed
          # writes a lock (0032 §5) -- so someone set this password by
          # hand. Record it as changed; otherwise `sudo passwd <user>`
          # on a machine whose key was never fixed would clear
          # password-absent into the *seeded* message, which is false,
          # on exactly the machine this task is for.
          if [ -e "$absent_marker" ]; then
            touch "$changed_marker"
            rm -f "$absent_marker"
          fi
          exit 0
        fi
        seed="$(${pkgs.coreutils}/bin/cat "$seed_file")"
        # Each branch clears password-absent itself, *after* its own
        # decisive write, so the recovery transition (absent, then the
        # resident runs `sudo passwd`) never has a window -- or a
        # crash-persisted state -- in which neither marker exists and
        # the banner wrongly nags with the seeded message.
        if [ "$stripped" = "$seed" ]; then
          rm -f "$changed_marker"
          rm -f "$absent_marker"
        else
          touch "$changed_marker"
          rm -f "$absent_marker"
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
    # Three states, read from the check's markers, and the wording of
    # each -- escape codes included -- is pinned literally by
    # test/password-reminder/check.nix
    # (docs/tasks/0036-reminder-banner-states.md): password-changed
    # silences everything; password-absent means the account has no
    # password at all, the state 0032's check could detect but not
    # express; neither means still on the seed. The messages name the
    # account rather than saying "this account" because every
    # interactive shell shows them, root's included, and in the
    # no-password state a shell that is *not* the admin's is exactly
    # who is likely to be reading. That is also why the no-password
    # remedy is `sudo passwd <user>`: plain `passwd` cannot
    # authenticate an account with no password, while wheel's
    # passwordless sudo (set above) works from every shell that can
    # display the message. No test seams here, deliberately -- the
    # marker paths stay hardcoded so a user's environment cannot
    # change what the banner reports; the flake check pins this block
    # textually instead.
    # NixOS sources `environment.interactiveShellInit` for bash and zsh;
    # a private layer that swaps in a different shell needs to wire this
    # itself.
    environment.interactiveShellInit = lib.mkIf (cfg.hashedPasswordFile != null) ''
      if [ ! -e ${reminderStateDir}/password-changed ]; then
        if [ -e ${reminderStateDir}/password-absent ]; then
          printf '\n\033[1;33mNote:\033[0m the %s account has no password at all: most likely its seed never decrypted when the account was first created, and a rebuild will not repair an existing account. Set one now with \033[1msudo passwd %s\033[0m.\n\n' ${lib.escapeShellArg cfg.username} ${lib.escapeShellArg cfg.username}
        else
          printf '\n\033[1;33mNote:\033[0m the %s account is still using its seeded initial password. Run \033[1mpasswd\033[0m to set your own.\n\n' ${lib.escapeShellArg cfg.username}
        fi
      fi
    '';
  };
}
