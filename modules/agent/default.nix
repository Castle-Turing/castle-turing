# modules/agent — the agent layer's Nix slot.
#
# Deliberately thin, per docs/architecture.md's Proposal 03 (intelligence
# is a tenant, not a structural member): all this module does is install
# the `castle` CLI (agent/castle — stdlib Python, no third-party deps,
# see agent/README.md for why) and declare where it should look for its
# journal. It contains no model, no daemon, no judgment. The router,
# digest, and validate logic all live in the CLI itself, as plain
# invocables — "the router is a distinct invocable, not a resident
# process" (docs/tasks/0008-agent-layer-skeleton.md).
#
# Optional import, exactly like modules/desktop or modules/dev: a host
# that doesn't want the agent layer yet just doesn't import this.
# Deliberately NOT imported by hosts/vm-test (flake.nix's
# host-vm-test/vm-test-example) — test/vm-install's harness proves the
# install mechanism works with no agent layer at all, the anti-bricking
# regression test docs/tasks/0008 asks for: losing the agent layer must
# never mean losing the machine.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.castle.agent;

  # A plain wrapper around agent/castle (and its siblings castle-modal,
  # castle-worker-claude), pinned to this flake's own python3 rather
  # than relying on `#!/usr/bin/env python3` finding whatever happens
  # to be on $PATH. No build-time linting (e.g. nixpkgs'
  # pkgs.writers.writePython3Bin) is used here on purpose: this module
  # has no way to know today whether a future CI environment has the
  # extra tooling that requires, and a wrapped stdlib script needs none
  # of it. castle-worker-claude is plain bash, wrapped the same way but
  # with no interpreter override needed beyond its own shebang; it's
  # installed alongside the two Python entry points because
  # `castle.agent.worker.command`'s default (below) names it by its
  # installed path, and `castle work` (agent/castle's cmd_work) execs
  # whatever that option names — see docs/tasks/0009-ambient-intake.md.
  castleCli = pkgs.stdenvNoCC.mkDerivation {
    pname = "castle-agent";
    version = "0.1.0";
    src = ../../agent;
    nativeBuildInputs = [ pkgs.makeWrapper ];
    dontBuild = true;
    installPhase = ''
      mkdir -p $out/libexec $out/bin
      install -Dm755 castle $out/libexec/castle
      install -Dm755 castle-modal $out/libexec/castle-modal
      install -Dm755 castle-worker-claude $out/bin/castle-worker-claude
      makeWrapper ${pkgs.python3}/bin/python3 $out/bin/castle \
        --add-flags $out/libexec/castle
      makeWrapper ${pkgs.python3}/bin/python3 $out/bin/castle-modal \
        --add-flags $out/libexec/castle-modal
    '';
    meta.description = "Castle Turing agent-layer CLI (record schema, router, digest, modal, worker wrapper)";
  };
in
{
  options.castle.agent = {
    stateDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Where the `castle` CLI's journal (and the resident model) live
        — see docs/architecture.md's "Where runtime state lives" and
        docs/private-layer.md. This is a path into the private repo's
        checkout on the host (its `state/` directory), never a value
        this repo can guess correctly, so the default is `null`: the
        CLI then falls back to its own `$XDG_STATE_HOME/castle` /
        `~/.local/state/castle` resolution (see agent/castle's
        `state_dir()`), which is a reasonable per-user default but not
        the durable, private-repo-tracked location the architecture
        doc calls for.

        Set from the private layer, e.g.:

          castle.agent.stateDir = "/home/<you>/private/state";

        Wired straight into the `CASTLE_STATE_DIR` environment variable
        every login shell sees — the same variable the CI harness
        (test/agent-loop/run.sh) points at a throwaway temp directory,
        which is what makes that harness possible without touching a
        real resident's journal.
      '';
    };

    worker.command = lib.mkOption {
      type = lib.types.str;
      default = "${castleCli}/bin/castle-worker-claude";
      description = ''
        The command `castle work <request-id>` (agent/castle's
        `cmd_work`) execs to hold the worker seat — the tenant, not the
        structure (Proposal 03, docs/architecture.md). Wired into the
        `CASTLE_WORKER_COMMAND` environment variable; unlike
        `stateDir`/`notify.command` this one is not `nullOr`, because
        the worker seat needs *something* runnable to default to, per
        docs/tasks/0009-ambient-intake.md item 4 — "defaulting to a
        headless `claude -p` invocation."

        The contract, whatever holds this option: the request body is
        piped to the command's stdin; `$CASTLE_REQUEST_ID`,
        `$CASTLE_REQUEST_BODY`, `$CASTLE_DIFF_FILE`, and
        `$CASTLE_REPO_ROOT` are set in its environment; reasoning goes
        to stdout, a diff (or nothing) goes to `$CASTLE_DIFF_FILE`. See
        agent/castle-worker-claude for the reference implementation of
        that contract and test/agent-loop/scripted-worker.sh for a
        model-free stand-in. THE WORKER MUST NOT DEPLOY — no
        `nixos-rebuild`, no `git commit`, no applying anything to a
        running system, from this seat, ever, in this slice. CI
        overrides this option's effect by setting
        `CASTLE_WORKER_COMMAND` directly (test/agent-loop/run.sh),
        bypassing Nix entirely, the same pattern `CASTLE_STATE_DIR`
        already uses there.
      '';
    };

    notify.command = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        The command `castle route` runs to fire a real interruption on
        the router's `notify` channel (docs/tasks/0009-ambient-intake.md
        item 5) — invoked as `<command> <title> <body>`. Wired into
        `CASTLE_NOTIFY_COMMAND`. Default `null`: agent/castle's own
        fallback (`notify-send` on `$PATH`) applies instead, which is
        real on any host that also imports `modules/desktop` (which
        installs mako + libnotify) and a harmless failed exec anywhere
        else. Set explicitly to `""` on a headless host to no-op the
        attempt outright rather than let every `castle route` warn on
        stderr about a missing `notify-send`.
      '';
    };
  };

  config = {
    environment.systemPackages = [ castleCli ];
    # lib.optionalAttrs, not lib.mkIf, for the conditional pieces here:
    # mkIf tags a whole option *definition*, so it only composes
    # correctly when it's the entire right-hand side the module system
    # merges — not as an operand of a plain `//` alongside other attrs,
    # which is what the unconditional CASTLE_WORKER_COMMAND entry below
    # needs to sit next to.
    environment.variables =
      (lib.optionalAttrs (cfg.stateDir != null) { CASTLE_STATE_DIR = cfg.stateDir; })
      // { CASTLE_WORKER_COMMAND = cfg.worker.command; }
      // (lib.optionalAttrs (cfg.notify.command != null) { CASTLE_NOTIFY_COMMAND = cfg.notify.command; });
  };
}
