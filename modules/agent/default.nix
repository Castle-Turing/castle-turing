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

  # A plain wrapper around agent/castle, pinned to this flake's own
  # python3 rather than relying on `#!/usr/bin/env python3` finding
  # whatever happens to be on $PATH. No build-time linting (e.g.
  # nixpkgs' pkgs.writers.writePython3Bin) is used here on purpose: this
  # module has no way to know today whether a future CI environment has
  # the extra tooling that requires, and a wrapped stdlib script needs
  # none of it.
  castleCli = pkgs.stdenvNoCC.mkDerivation {
    pname = "castle-agent";
    version = "0.1.0";
    src = ../../agent;
    nativeBuildInputs = [ pkgs.makeWrapper ];
    dontBuild = true;
    installPhase = ''
      mkdir -p $out/libexec $out/bin
      install -Dm755 castle $out/libexec/castle
      makeWrapper ${pkgs.python3}/bin/python3 $out/bin/castle \
        --add-flags $out/libexec/castle
    '';
    meta.description = "Castle Turing agent-layer CLI (record schema, router, digest)";
  };
in
{
  options.castle.agent = {
    stateDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Where the `castle` CLI's journal (and, later, the resident
        model) lives — see docs/architecture.md's "Where runtime state
        lives" and docs/private-layer.md. This is a path into the
        private repo's checkout on the host (its `state/` directory),
        never a value this repo can guess correctly, so the default is
        `null`: the CLI then falls back to its own
        `$XDG_STATE_HOME/castle` / `~/.local/state/castle` resolution
        (see agent/castle's `state_dir()`), which is a reasonable
        per-user default but not the durable, private-repo-tracked
        location the architecture doc calls for.

        Set from the private layer, e.g.:

          castle.agent.stateDir = "/home/<you>/private/state";

        Wired straight into the `CASTLE_STATE_DIR` environment variable
        every login shell sees — the same variable the CI harness
        (test/agent-loop/run.sh) points at a throwaway temp directory,
        which is what makes that harness possible without touching a
        real resident's journal.
      '';
    };
  };

  config = {
    environment.systemPackages = [ castleCli ];
    environment.variables = lib.mkIf (cfg.stateDir != null) {
      CASTLE_STATE_DIR = cfg.stateDir;
    };
  };
}
