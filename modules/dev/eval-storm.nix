# modules/dev/eval-storm.nix — docs/tasks/0083: a spelling-agnostic
# detector for the per-command nixpkgs-evaluation storm that
# OOM-killed a resident's session on 2026-10-02 (`nix develop --command
# ...` in an edit-then-test loop) and, under the different spelling
# `nix shell nixpkgs#...`, hung a host on 2026-09-06
# (docs/tasks/0085-an-agent-workload-can-thrash-the-host.md). Both
# incidents talk to nix-daemon once per evaluation no matter what
# subcommand asked for it, so this counts nix-daemon client
# connections in a trailing window rather than parsing any one
# subcommand's invocation — direnv closes today's spelling (this
# module's default.nix); the next spelling still trips this.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.castle.evalStorm;

  # `set -euo pipefail` with journalctl's own stderr left unredirected
  # is deliberate: if this user lacks permission to read the system
  # journal, the script must fail loudly (a visibly failed unit) rather
  # than silently report zero connections — a missing grant reading as
  # "all quiet" would be the exact silent failure this task's own
  # "an incident ships its detector" convention exists to rule out.
  # Verified on a real host built from this flake's pin, not assumed:
  # `getfacl /var/log/journal/*` shows systemd's own upstream tmpfiles
  # rule already grants the `wheel` group read+execute on the journal
  # directory, and modules/base unconditionally puts the admin account
  # in `wheel` — so no additional group grant is needed here, and none
  # is added. If a future systemd drops that default ACL, this script
  # fails loudly rather than reporting a false "quiet", and the VM
  # test's notification-delivery assertion (not just unit success) is
  # what would catch the regression.
  #
  # One residual risk this script cannot close on its own: `grep -c
  # "accepted connection"` matches today's nix-daemon log wording
  # literally. A future nix-daemon that rewords or drops that phrase
  # degrades silently to a permanent "0 connections" (`|| true`
  # neutralizes grep's own nonzero exit on no match, by design, for
  # the ordinary quiet-window case) — unlike the permissions gap
  # above, there is no loud-failure path for a wording change,
  # because the script has no independent way to tell "quiet" from
  # "the string stopped matching." Catching that drift is scoped to
  # whichever future task bumps the nixpkgs pin far enough to trip it.
  # docs/tasks/0088: deduplicate notifyCommand delivery across a single
  # storm. Without this, a storm that remains inside the trailing
  # window for several consecutive two-minute ticks fires one
  # notification per tick — observed as seven notifications for one
  # storm on 2026-10-03. The per-tick nonzero exit (below) is
  # deliberately untouched: systemd already collapses repeated failures
  # into one failed-unit state, so that path has no spam problem to
  # fix, and the visibly-failed unit stays the headless host's floor
  # with no notifier configured at all.
  #
  # State is a marker file's mere existence under $XDG_RUNTIME_DIR —
  # always set for a `systemd.user.*` unit by the user manager itself,
  # so no fallback is needed — deliberately not tmpfs-persisted or
  # written anywhere that survives a reboot, since a storm marker
  # outliving the session it describes would silently suppress the
  # next real storm's first notification.
  #
  # Two semantics the brief left open, decided here:
  #
  # 1. Re-arm waits for exactly one quiet tick (count below threshold),
  #    not for the full ten-minute window to drain with no storm
  #    ticks at all. The smaller rule is also the one the brief's own
  #    "what we already know" section already named as the standard
  #    shape, and it costs one `rm -f` rather than tracking a
  #    last-tripped timestamp and comparing elapsed time against
  #    `windowMinutes` on every tick. The trade-off this accepts: a
  #    storm whose rate flickers exactly at the threshold boundary
  #    could re-notify mid-storm if one tick's trailing-window count
  #    dips below threshold and the next recovers. That edge case is
  #    the same shape as the regression this task fixes, just smaller,
  #    and is left for a future entry if it is ever observed — the
  #    threshold's own calibration (see `threshold`'s description) was
  #    already chosen with headroom over both founding incidents'
  #    rates, which makes a boundary flicker unlikely in practice.
  # 2. No all-clear notification. The task's own title is "fires once
  #    per storm" — a start notification plus an end notification is
  #    two, not one, and would reopen the exact alert-fatigue failure
  #    mode this task exists to close. Silence after the first alert,
  #    with the next storm's own transition notification as the only
  #    other signal, is the smaller mechanism.
  checkScript = pkgs.writeShellScript "castle-eval-storm-check" ''
    set -euo pipefail

    marker="$XDG_RUNTIME_DIR/castle-eval-storm-active"

    output=$(journalctl -u nix-daemon --no-pager --since "-${toString cfg.windowMinutes} minutes")
    # `grep -c` always prints a count (0 included) and exits 1 on no
    # match; `|| true` neutralizes that exit status inside the command
    # substitution so `set -e` doesn't abort on an ordinary quiet
    # window — the count itself is still correct either way.
    count=$(printf '%s\n' "$output" | grep -c "accepted connection" || true)
    echo "castle-eval-storm-check: $count nix-daemon connection(s) in the last ${toString cfg.windowMinutes} minute(s) (threshold ${toString cfg.threshold})"

    if [ "$count" -ge ${toString cfg.threshold} ]; then
      echo "castle-eval-storm-check: at or above threshold" >&2
      if [ ! -e "$marker" ]; then
        # Quiet-to-storm transition: this tick is the first to see the
        # marker absent, so it is the one that notifies.
        ${lib.optionalString (cfg.notifyCommand != null) ''
          ${cfg.notifyCommand} "Eval storm detected" "$count nix-daemon connections in the last ${toString cfg.windowMinutes} minutes (threshold ${toString cfg.threshold})" || true
        ''}
        touch "$marker"
      fi
      exit 1
    else
      # A quiet tick re-arms the notifier for the next storm (see this
      # script's header comment for why one tick, not a full window).
      rm -f "$marker"
    fi
  '';
in

{
  options.castle.evalStorm = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Run `castle-eval-storm-check` every two minutes, failing loudly
        when nix-daemon has accepted an unusual number of client
        connections recently — the signature of an agent loop paying a
        full nixpkgs evaluation per command (docs/tasks/0083). Default
        on: the whole point is that nothing has to opt in to get the
        warning, the way nothing opted in to the two incidents that
        motivated it.
      '';
    };

    threshold = lib.mkOption {
      type = lib.types.ints.positive;
      default = 6;
      description = ''
        Trip the check at this many nix-daemon client connections
        within `castle.evalStorm.windowMinutes` — `count >= threshold`,
        deliberately inclusive so a run that exactly equals the
        threshold still trips it.

        A calibration value, not a derived one: the 2026-10-02 incident
        this task answers logged roughly 0.8 connections/minute (about
        7 in a 10-minute window), and the 2026-09-06
        `nix shell`-flavoured incident logged roughly 2/minute. Both
        must stay at or above whatever this is set to — a detector its
        own founding incidents cannot trip is not a detector. If an
        ordinary `nixos-rebuild` turns out to make a comparable number
        of connections, narrow what gets counted rather than raising
        this past either incident's rate.
      '';
    };

    windowMinutes = lib.mkOption {
      type = lib.types.ints.positive;
      default = 10;
      description = ''
        The trailing window `castle-eval-storm-check` counts nix-daemon
        client connections over. See `castle.evalStorm.threshold` for
        how the default pairs with this one.
      '';
    };

    notifyCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        A `notify-send`-compatible command, run with a title and a body
        appended as two more arguments when the check trips. Deliberately
        this module's own option rather than a read of
        `castle.agent.notify.command`: that option's contract belongs to
        the agent layer's blocking notify-waiter (modules/agent), and
        reading it here would make this detector's behaviour depend on
        whether a host happens to import `modules/agent` at all — this
        module must work alone.

        Default `null`: on a headless host, or one with no session
        notifier wired up, the floor is the check's own loud nonzero
        exit — a visibly failed user unit, on every host, with no
        notification required for the regression to be noticeable. A
        host with a session notifier sets this to it (the resident's
        own choice, in a host or private-layer module, per Principle
        01).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.castle-eval-storm-check = {
      description = "Detect a nixpkgs-evaluation storm via nix-daemon's own connection count";
      unitConfig.ConditionUser = "!@system";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${checkScript}";
      };
      # Every unit the user manager starts inherits BASH_ENV from
      # modules/dev's own DefaultEnvironment — including this one, and
      # bash sources $BASH_ENV for any non-interactive invocation (a
      # shebang-exec'd script included), not only `bash -c`. This unit
      # sets no WorkingDirectory, so it defaults to the resident's
      # home; if that happens to be a whitelisted, direnv-managed
      # checkout (a private-layer dotfiles repo is a plausible one),
      # every two-minute tick would pay its own `direnv export` and
      # potentially its own nix-daemon connection — folding the
      # detector's own operation into the exact count it exists to
      # watch. CASTLE_DIRENV_DISABLE is this module's own documented
      # opt-out for precisely this shape of case.
      environment.CASTLE_DIRENV_DISABLE = "1";
    };

    systemd.user.timers.castle-eval-storm-check = {
      description = "Run castle-eval-storm-check on a schedule";
      wantedBy = [ "default.target" ];
      unitConfig.ConditionUser = "!@system";
      timerConfig = {
        OnStartupSec = "2min";
        OnUnitActiveSec = "2min";
      };
    };
  };
}
