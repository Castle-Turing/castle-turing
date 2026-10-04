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
# Three guards keep the shadow honest, each with a visible reason
# in the script below: an explicit opt-out (CASTLE_NIX_SCOPE_DISABLE),
# an in-scope marker so a wrapped nix that spawns nix (a `nix develop`
# shell) does not stack scopes per call, and a fallback to direct
# exec wherever the user manager is unreachable — root (nixos-rebuild
# runs nix as root; breaking a switch would be the one unforgivable
# failure here), or any context without a running user manager.
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
      #  - CASTLE_NIX_IN_SCOPE: this invocation is already inside a
      #    scope this wrapper made (a `nix develop` shell's own nix
      #    calls land here) — one scope per top-level invocation, not
      #    one per descendant.
      #  - root: nixos-rebuild and the daemon's own helpers run nix as
      #    root with no user manager to register a scope with; a
      #    switch must never fail because of this wrapper.
      #  - no reachable user manager: $XDG_RUNTIME_DIR/systemd/private
      #    is the user manager's own socket; absent (cron-like
      #    contexts, stripped environments), systemd-run --user cannot
      #    work, and failing open to the old behavior beats failing
      #    the command.
      if [ -n "''${CASTLE_NIX_SCOPE_DISABLE:-}" ] \
        || [ -n "''${CASTLE_NIX_IN_SCOPE:-}" ] \
        || [ "$(id -u)" = 0 ] \
        || [ -z "''${XDG_RUNTIME_DIR:-}" ] \
        || [ ! -S "''${XDG_RUNTIME_DIR}/systemd/private" ]; then
        exec ${nixBin}/${name} "$@"
      fi

      export CASTLE_NIX_IN_SCOPE=1

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
      ${systemdRun} --user --scope --collect --quiet --expand-environment=no \
        ${lib.escapeShellArgs memoryProperties} \
        -- ${nixBin}/${name} "$@"
      rc=$?
      if [ "$rc" -eq 137 ]; then
        echo "castle-nix-scope: ${name} was killed by SIGKILL inside its own transient scope${boundNote} — almost certainly a memory kill: the kernel's cgroup OOM at the scope's MemoryMax, or systemd-oomd selecting the scope under pressure. The kill record is in \`journalctl -k\` (kernel cgroup kills) or \`journalctl --user\` (oomd kills)." >&2
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
        invocation in its own transient user scope, so a memory kill
        lands on that invocation rather than on the terminal scope
        around it (docs/tasks/0089). Default on for the same reason
        castle.evalStorm is: nothing opted in to the incidents this
        answers. With no bounds configured below, the wrapper changes
        kill granularity only — each invocation becomes its own
        oomd-eligible leaf — and imposes no limit of any kind.
      '';
    };

    memoryMax = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "6G";
      description = ''
        `MemoryMax=` for each nix invocation's scope — the hard cap at
        which the kernel OOM-kills inside that scope, leaving the
        invoking shell alive to report it. A systemd size string. The
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
