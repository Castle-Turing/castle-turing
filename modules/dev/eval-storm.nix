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
  checkScript = pkgs.writeShellScript "castle-eval-storm-check" ''
    set -euo pipefail

    output=$(journalctl -u nix-daemon --no-pager --since "-${toString cfg.windowMinutes} minutes")
    # `grep -c` always prints a count (0 included) and exits 1 on no
    # match; `|| true` neutralizes that exit status inside the command
    # substitution so `set -e` doesn't abort on an ordinary quiet
    # window — the count itself is still correct either way.
    count=$(printf '%s\n' "$output" | grep -c "accepted connection" || true)
    echo "castle-eval-storm-check: $count nix-daemon connection(s) in the last ${toString cfg.windowMinutes} minute(s) (threshold ${toString cfg.threshold})"

    if [ "$count" -ge ${toString cfg.threshold} ]; then
      echo "castle-eval-storm-check: at or above threshold" >&2
      ${lib.optionalString (cfg.notifyCommand != null) ''
        ${cfg.notifyCommand} "Eval storm detected" "$count nix-daemon connections in the last ${toString cfg.windowMinutes} minutes (threshold ${toString cfg.threshold})" || true
      ''}
      exit 1
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
