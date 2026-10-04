# modules/dev/nix-scope.nix — docs/tasks/0089: every nix *client*
# invocation runs in a transient scope of its own, so a memory kill
# lands on the build, not the session. The 2026-10-03 incident this
# answers had a hard cap on the terminal scope (castle.launch's
# MemoryMax, task 0085) and it never fired: a runaway evaluation
# throttled at MemoryHigh with its swap allowance exhausted generates
# sustained reclaim pressure long before RSS reaches the cap, and
# systemd-oomd — which kills leaf cgroups whole — won the race,
# taking 42 processes including the session that could have reported
# what happened. Giving each nix invocation its own scope changes who
# dies in both endgames: the kernel's cgroup OOM kill at this
# module's MemoryMax lands inside the invocation's scope, and even
# with no bound configured, oomd's leaf selection now finds the
# invocation generating the pressure rather than the terminal around
# it.
#
# Client, not daemon, deliberately: evaluation (`nix eval`,
# `nix build`'s eval phase, `nix print-dev-env`, the ~2 GB nixpkgs
# evaluations of tasks 0083/0085) runs in the client process, inside
# whatever scope the shell occupies. Builds themselves — VM boots
# included — already run under nix-daemon's own system slice and
# never threatened the session. The client half is the whole gap.
#
# Delivery is PATH shadowing: a lib.hiPrio package whose bin/ entries
# win the buildEnv collision against nix.package's own. The same
# compliance argument as task 0083's BASH_ENV hook — guidance
# ("remember to run nix under systemd-run") is exactly the
# one-spelling weakness both founding incidents walked through, and
# nothing else reaches an agent's non-interactive bash mechanically.
# The boundary that implies, stated rather than implied: only
# PATH-resolved invocations are covered. A caller that interpolates
# an absolute store path to the client (a unit ExecStart, a script
# carrying ''${nix}/bin/nix) bypasses the shadow and evaluates in its
# own cgroup, exactly as before this module.
# Guards keep the shadow honest, each with a visible reason in the
# script below: an explicit opt-out (CASTLE_NIX_SCOPE_DISABLE), and a
# fallback to direct exec wherever the user manager is unreachable —
# root (nixos-rebuild runs nix as root; breaking a switch would be
# the one unforgivable failure here), or any context without a
# running user manager. A nix invocation spawned from inside an
# already-scoped one gets a sibling scope of its own, deliberately:
# an inheritable in-scope marker was tried and rejected because any
# long-lived descendant of a scoped invocation (a --command-started
# tmux, an agent) would carry it forever and silently disable
# scoping for everything it spawned.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.castle.nixScope;

  nixBin = "${config.nix.package}/bin";

  # Same rule as modules/home's launch wrapper: the systemd-run that
  # talks to this system's user manager is this system's own systemd,
  # by absolute store path, not whatever a PATH lookup finds.
  systemdRun = "${config.systemd.package}/bin/systemd-run";

  # MemoryHigh is deliberately not offered. The incident this module
  # answers is precisely what the throttle does to a runaway: it
  # converts a fast kill into minutes of reclaim thrash that ends in
  # oomd taking the scope anyway. A per-invocation scope wants the
  # hard cap and nothing softening the path to it.
  memoryProperties =
    lib.optional (cfg.memoryMax != null) "--property=MemoryMax=${cfg.memoryMax}"
    ++ lib.optional (cfg.memorySwapMax != null) "--property=MemorySwapMax=${cfg.memorySwapMax}";

  # The five client entrypoints that evaluate: the new CLI and the
  # legacy quartet. nix-store, nix-copy-closure and friends are cheap
  # protocol clients with nothing to evaluate — shadowing them would
  # be scope churn with no kill worth descoping.
  wrappedCommands = [
    "nix"
    "nix-build"
    "nix-shell"
    "nix-instantiate"
    "nix-env"
  ];

  boundNote =
    if cfg.memoryMax != null then " (MemoryMax=${cfg.memoryMax})" else " (no MemoryMax configured)";

  mkWrapper =
    name:
    pkgs.writeShellScriptBin name ''
      # Direct exec, in the order the reasons bind:
      #  - CASTLE_NIX_SCOPE_DISABLE: the documented opt-out, same
      #    contract as CASTLE_DIRENV_DISABLE in modules/dev.
      #  - root: nixos-rebuild and the daemon's own helpers run nix as
      #    root with no user manager to register a scope with; a
      #    switch must never fail because of this wrapper.
      #  - no reachable user manager: $XDG_RUNTIME_DIR/systemd/private
      #    is the user manager's own socket; absent (cron-like
      #    contexts, stripped environments), systemd-run --user cannot
      #    work, and failing open to the old behavior beats failing
      #    the command.
      # Deliberately no in-scope guard: a nested nix call from inside
      # a scoped invocation gets its own sibling scope with its own
      # bound — see the header for why an inheritable marker was
      # rejected.
      if [ -n "''${CASTLE_NIX_SCOPE_DISABLE:-}" ] \
        || [ "''${EUID:-}" = 0 ] \
        || [ -z "''${XDG_RUNTIME_DIR:-}" ] \
        || [ ! -S "''${XDG_RUNTIME_DIR}/systemd/private" ]; then
        exec ${nixBin}/${name} "$@"
      fi
      # $EUID, not $(id -u): this script's own rule is absolute store
      # paths, and a PATH-resolved id in a stripped-PATH context would
      # print noise and silently void the root guard (review finding).

      ${lib.optionalString (name == "nix") ''
        # Interactive environments and arbitrary-duration payloads
        # stay unscoped: memoryMax is sized for one evaluation, and an
        # hours-long `nix develop` shell must not live under an
        # eval-sized ceiling; that would recreate the whole-session
        # kill this module exists to end (review finding on this
        # task's PR). `nix run` execs a payload of unknowable
        # duration, same reasoning. The founding incidents' spellings
        # stay covered: `nix develop --command` and `nix shell -c`
        # are non-interactive and get their scope. Two documented
        # heuristic boundaries: `nix --option a b develop` slips the
        # first-argument match and gets scoped — the strict
        # direction; and `nix develop --command bash` is classified
        # non-interactive (indistinguishable here from
        # `--command make`), so an interactive shell wanted under a
        # bound-free scope is spelled bare `nix develop`, or opted
        # out with CASTLE_NIX_SCOPE_DISABLE.
        #
        # `print-dev-env` is the capture invocation nix-direnv runs
        # for `use flake`, and it must NOT be scoped: its caller
        # consumes its output synchronously, and routing it through a
        # transient scope hangs that capture — measured on this task's
        # own direnv-delivery VM, where a scoped print-dev-env burned
        # 20s CPU, evaluated fully (466M peak, far under any bound),
        # then blocked on I/O for ~160s until the probe's timeout
        # killed it, leaving direnv with no environment. It belongs in
        # this exemption on its merits regardless: nix-direnv caches it
        # per flake.lock change rather than per command, so it is not
        # the edit-then-build loop surface 0089 targets, and it mirrors
        # the bare `nix develop` already exempted just above. The
        # consequence, recorded in the brief: a direnv-driven dev-env
        # evaluation is unbounded, while the loop-prone surfaces
        # (`nix build`, `nix flake check`, `nix eval`, `nix develop
        # --command`) stay scoped.
        case "''${1:-}" in
          repl | run | print-dev-env)
            exec ${nixBin}/${name} "$@"
            ;;
          develop | shell)
            interactive=1
            for a in "$@"; do
              case "$a" in
                -c | --command)
                  interactive=
                  break
                  ;;
              esac
            done
            if [ -n "$interactive" ]; then
              exec ${nixBin}/${name} "$@"
            fi
            ;;
        esac
      ''}
      ${lib.optionalString (name == "nix-shell") ''
        # Same exemption for the legacy spelling: bare nix-shell is an
        # interactive environment; --run/--command is the bounded,
        # loop-prone form. One more non-interactive shape carries
        # neither flag: a `#!/usr/bin/env nix-shell` script, whose
        # `#! nix-shell -i ...` directives live on line 2 of the
        # script file and are parsed only by the real nix-shell —
        # the wrapper sees just [script, args] (review finding). A
        # positional argument that is a file with nix-shell on its
        # second line is that shape, and it gets its scope.
        interactive=1
        for a in "$@"; do
          case "$a" in
            --run | --command)
              interactive=
              break
              ;;
            -*) ;;
            *)
              if [ -f "$a" ] && sed -n 2p "$a" 2>/dev/null | grep -q 'nix-shell'; then
                interactive=
                break
              fi
              ;;
          esac
        done
        if [ -n "$interactive" ]; then
          exec ${nixBin}/${name} "$@"
        fi
      ''}

      # A socket on disk is not a live manager: an uncleanly dead
      # systemd --user leaves $XDG_RUNTIME_DIR/systemd/private behind,
      # and a foreign XDG_RUNTIME_DIR (sudo with env kept) points at a
      # manager that will refuse us — either way systemd-run would
      # fail before nix ever ran, failing a workable invocation
      # closed (review finding). One no-op scope probes the real
      # thing; on any failure, fall open. The probe costs one
      # manager round-trip per scoped invocation — milliseconds,
      # against a client call that talks to nix-daemon anyway.
      if ! ${systemdRun} --user --scope --collect --quiet -- true 2>/dev/null; then
        exec ${nixBin}/${name} "$@"
      fi

      # --scope: the command stays a child of this process on this
      # terminal (interactive `nix develop` and `nix repl` keep their
      # tty), while its cgroup becomes an oomd-eligible leaf of its
      # own under the user manager — the same shape, for the same
      # reason, as modules/home's castle-launch. --collect so a killed
      # scope leaves no failed unit behind; --quiet so a successful
      # run prints nothing extra.
      #
      # Not `exec`: this process stays alive to translate the exit
      # status. A build killed at its memory bound must be
      # distinguishable from a mysteriously failed command — that
      # distinction is the one non-negotiable requirement in
      # docs/tasks/0089.
      # --expand-environment=no: systemd-run otherwise rewrites
      # ''${NAME} sequences inside the command's own arguments from
      # the environment — verified live: `systemd-run --user --scope
      # -- echo 'x ''${HOME} y'` prints the expansion. Nix expressions
      # are full of ''${...}; a wrapper that corrupts argv is worse
      # than no wrapper. (Cross-model review finding on this task's
      # PR; confirmed empirically before fixing.)
      #
      # Backgrounded with signals forwarded, not run foreground: a
      # harness that cancels a build kills the PID it spawned — this
      # wrapper — and a foreground child would survive that as an
      # orphan, still evaluating inside its scope (review finding,
      # confirmed live: the payload reparents to PID 1 and keeps
      # running). A non-interactive shell puts a background child in
      # the caller's own process group, so tty reads and ^C reach it
      # exactly as before; the traps cover the directed kill that
      # would otherwise orphan the evaluator. The wait loop re-waits
      # after a trap interrupts it, so the translated exit status is
      # the child's own.
      ${systemdRun} --user --scope --collect --quiet --expand-environment=no \
        ${lib.escapeShellArgs memoryProperties} \
        -- ${nixBin}/${name} "$@" &
      child=$!
      for sig in TERM INT HUP; do
        trap "kill -''${sig} ''${child} 2>/dev/null" "''${sig}"
      done
      wait "$child"
      rc=$?
      while kill -0 "$child" 2>/dev/null; do
        wait "$child"
        rc=$?
      done
      if [ "$rc" -eq 137 ]; then
        echo "castle-nix-scope: ${name} was killed by SIGKILL inside its own transient scope${boundNote} — most likely a memory kill: the kernel's cgroup OOM at the scope's MemoryMax, or systemd-oomd selecting the scope under pressure. An external kill -9 looks identical from here; the kill record, if it was memory, is in the system journal: \`journalctl -k\` for kernel cgroup kills, \`journalctl -u systemd-oomd\` for oomd's." >&2
      fi
      exit "$rc"
    '';
in

{
  options.castle.nixScope = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Shadow the nix client commands with wrappers that run each
        PATH-resolved invocation in its own transient user scope, so
        a memory kill lands on that invocation rather than on the
        terminal scope around it (docs/tasks/0089). PATH-resolved is
        the coverage boundary: a caller holding an absolute store
        path to the client bypasses the shadow entirely. Default on
        for the same reason castle.evalStorm is: nothing opted in to
        the incidents this answers. With no bounds configured below,
        the wrapper changes kill granularity only — each invocation
        becomes its own oomd-eligible leaf — and imposes no limit of
        any kind.
      '';
    };

    memoryMax = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "6G";
      description = ''
        `MemoryMax=` for each nix invocation's scope — the hard cap at
        which the kernel OOM-kills inside that scope, leaving the
        invoking shell alive to report it. A systemd size string.
        Binds one invocation, not a session: interactive environments
        (bare `nix develop`/`nix shell`/`nix repl`/`nix-shell`, and
        `nix run`'s arbitrary-duration payload) are exempt from
        scoping precisely so this value can be sized to a single
        evaluation without becoming the ceiling on an hours-long
        shell. The
        framework ships no number (Principle 01): what one evaluation
        deserves depends on the host's RAM and the resident's
        workload. Sized against the known cost of the workload this
        exists for — a nixpkgs evaluation peaks around 2 GB — a value
        below that turns every real evaluation into a kill, and a
        value above the host's RAM is no bound at all. There is
        deliberately no memoryHigh beside this: the throttle is what
        converted the founding incident's runaway into minutes of
        thrash that ended in a whole-scope oomd kill anyway.
      '';
    };

    memorySwapMax = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "1G";
      description = ''
        `MemorySwapMax=` for each nix invocation's scope. Same
        zram caveat as castle.launch's option of the same name
        (modules/home): on a zram-only host swap is RAM at the
        compression ratio, so an uncapped swap allowance lets a
        runaway keep converting its footprint instead of hitting
        memoryMax. Default `null`: no property passed.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # hiPrio so these win the /run/current-system/sw/bin collision
    # against nix.package's own binaries. The wrappers always exec the
    # real client by absolute store path, never through PATH, so the
    # shadow cannot recurse into itself.
    environment.systemPackages = [
      (lib.hiPrio (pkgs.symlinkJoin {
        name = "castle-nix-scope";
        paths = map mkWrapper wrappedCommands;
      }))
    ];
  };
}
