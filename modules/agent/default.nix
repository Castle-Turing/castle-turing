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

        Wired into the `CASTLE_STATE_DIR` environment variable via
        `environment.sessionVariables` (see this module's `config` for
        why that option and not `environment.variables` — the mechanism
        matters, `castle-modal` is spawned from a Sway keybinding, not a
        login shell) — the same variable the CI harness
        (test/agent-loop/run.sh) points at a throwaway temp directory,
        which is what makes that harness possible without touching a
        real resident's journal.

        Must not contain a literal `"` character: this module wires it
        (and `worker.command`/`notify.command` below) through
        `environment.sessionVariables`, which nixpkgs' own option
        description warns "due to limitations in the PAM format values
        may not contain the `\"` character" — see this module's `config`
        comment for what actually breaks if that's violated. Asserted
        below rather than left to fail silently on the host.
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

        Must not contain a literal `"` character — see `stateDir`'s
        description for why (this option is wired through
        `environment.sessionVariables` the same way).
      '';
    };

    worker.timeoutSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 900;
      description = ''
        How long `castle work` (agent/castle) lets the worker tenant
        run before killing its whole process group and writing a
        result with `outcome: timeout`
        (docs/tasks/0021-auto-dispatch.md). Wired into
        `CASTLE_WORKER_TIMEOUT`.

        Fifteen minutes is a chosen value, not derived from any
        measurement: long enough for a real `claude -p` errand, short
        enough that a hung tenant does not silently occupy the worker
        seat for the rest of the day. Raise it if your tenant
        legitimately takes longer.

        The guard lives in the tool, not as `RuntimeMaxSec=` on the
        dispatch unit, for one reason wearing two hats: a unit-level
        timeout would kill an entire *sweep* — possibly part-way
        through a second or third perfectly healthy errand — rather
        than the one hung turn, and a human running `castle work` by
        hand outside any unit deserves the identical guard. The
        timeout is a property of the worker contract, not of how the
        worker happened to be invoked.
      '';
    };

    worker.repoRoot = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        The repository the worker tenant operates on — wired into
        `CASTLE_REPO_ROOT`, which `castle work` puts in the tenant's
        environment (see `agent/castle-worker-claude`, which tells the
        model to diagnose the problem in the repository checked out
        there).

        Default `null`, and it cannot be otherwise: the private
        flake's actual checkout path on disk is resident data, which
        this repo may never guess (Principle 02, the same reasoning
        `stateDir` above documents).

        **Left unset, a dispatched worker is told its repo is your
        home directory.** `castle work` falls back to the current
        working directory, and the dispatch unit's working directory
        is `%h` — which is very unlikely to be the repo a real tenant
        needs to operate on. Set this whenever you enable
        `castle.agent.dispatch.enable`.

        Must not contain a literal `"` character — see `stateDir`'s
        description for why (this option rides
        `environment.sessionVariables` the same way, so a hand-run
        `castle work` in a terminal gets the same repo root a
        dispatched one does).
      '';
    };

    dispatch.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Start eligible resident-filed errands automatically, with no
        `castle work` or `castle route` typed by hand
        (docs/tasks/0021-auto-dispatch.md).

        Declares three `systemd.user` units — a path unit watching the
        journal directory, a `oneshot` service running
        `castle dispatch`, and a five-minute timer as a backstop for a
        missed inotify event. The sweep reaps interrupted turns, runs
        the configured worker tenant against every eligible request
        one at a time, and routes once at the end.

        **Default off, deliberately.** Turning this on is a standing
        authority decision about your own machine — it lets a model
        tenant start work, and spend money, without a human in the
        loop at the moment it happens. This framework will not make
        that decision for a resident; a private layer opts in
        (docs/private-layer.md).

        Requires `castle.agent.stateDir` (asserted below), and you
        almost certainly want `castle.agent.worker.repoRoot` too —
        see that option's description for what happens without it.

        Deliberately **no `loginctl enable-linger`**: without
        lingering, these units run only while you are logged in, which
        is the honest lifetime for a mechanism whose only externally
        visible output today is a desktop notification. Running
        dispatch between logins is a separate authority decision and
        is out of scope here.
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

        Must not contain a literal `"` character — see `stateDir`'s
        description for why (this option is wired through
        `environment.sessionVariables` the same way).
      '';
    };
  };

  config = {
    environment.systemPackages = [ castleCli ];
    # environment.sessionVariables, NOT environment.variables — confirmed
    # by reading this flake's pinned nixpkgs (rev in flake.lock) rather
    # than assumed, after the first real deploy showed CASTLE_STATE_DIR
    # correctly present in /etc/set-environment and *still* not reaching
    # castle-modal (docs/tasks/0013-first-deploy-findings.md, bug 2).
    #
    # environment.variables only ever lands in
    # `environment.etc.set-environment` (nixos/modules/config/
    # shells-environment.nix's `system.build.setEnvironment`), a file
    # that file's own comment says exists "for resetting environment
    # with `. /etc/set-environment` when needed" — it's sourced by
    # /etc/profile, i.e. by login shells. modules/desktop's
    # `services.greetd.settings.default_session.command` execs
    # tuigreet, which on a successful login execs `sway` directly; no
    # login shell, no /etc/profile, ever sits in that process's
    # ancestry, so /etc/set-environment is never read for it. This is
    # not new to this bug — test/desktop-loop/test.nix already
    # documents the identical gap for WLR_RENDERER and works around it
    # with a wrapper script instead, because that variable has no
    # config-time value to carry through PAM.
    #
    # environment.sessionVariables takes a different path that does
    # reach a greetd session: nixos/modules/config/system-environment.nix
    # writes it to `/etc/pam/environment` (PAM's own env-file format,
    # via `environment.etc."pam/environment"`), which is read by
    # `pam_env.so`. nixos/modules/security/pam.nix wires that module
    # into every PAM service's *session* stack by default — the "env"
    # rule, `enable = cfg.setEnvironment` (default `true`) — and its own
    # option description says outright: "Whether the service should set
    # the environment variables listed in environment.sessionVariables
    # using pam_env.so." `security.pam.services.login` (nixos/modules/
    # programs/shadow.nix) takes that default, so /etc/pam.d/login's
    # session stack includes pam_env. greetd's own PAM service
    # (nixos/modules/services/display-managers/greetd.nix) sets
    # `useDefaultRules = false` but its session rule is `session include
    # login` — PAM's `include` splices in login's *entire* session
    # stack, pam_env and all — so a greetd login still runs pam_env,
    # which is what actually populates the environment PAM hands to the
    # session command (tuigreet's `--cmd sway`) before it execs. This is
    # the whole reason a PAM-based login manager runs pam_open_session
    # at all, not an incidental detail. `environment.variables` is not
    # abandoned by switching: shells-environment.nix folds
    # sessionVariables into `environment.variables` itself
    # (`environment.variables = config.environment.sessionVariables;`),
    # so /etc/set-environment still carries these for a plain login
    # shell — this change is strictly additive.
    #
    # lib.optionalAttrs, not lib.mkIf, for the conditional pieces here:
    # mkIf tags a whole option *definition*, so it only composes
    # correctly when it's the entire right-hand side the module system
    # merges — not as an operand of a plain `//` alongside other attrs,
    # which is what the unconditional CASTLE_WORKER_COMMAND entry below
    # needs to sit next to.
    #
    # All three ride environment.sessionVariables together, not just
    # CASTLE_STATE_DIR: they were one environment.variables block before
    # this fix, all three are read by processes that can equally be
    # spawned inside the Sway session (not just castle-modal — a worker
    # or notify invocation triggered from a terminal inside that same
    # session hits the identical login-shell-only gap), and
    # agent/castle's own fallbacks for worker/notify (DEFAULT_WORKER_
    # COMMAND, plain notify-send) would otherwise silently substitute a
    # different command than the one configured — the same shape of
    # silent-wrong-behavior bug 2 was, just for a different value.
    #
    # CASTLE_WORKER_TIMEOUT and CASTLE_REPO_ROOT joined the block with
    # docs/tasks/0021-auto-dispatch.md, for the same reason the other
    # three are here rather than only on the dispatch unit below: a
    # `castle work` a resident runs by hand from a terminal inside the
    # Sway session must get the identical timeout guard and repo root
    # an automatically-dispatched worker gets, not a weaker version of
    # either. The timeout rides unconditionally (it always has a
    # value); the repo root only when one is actually configured.
    environment.sessionVariables =
      (lib.optionalAttrs (cfg.stateDir != null) { CASTLE_STATE_DIR = cfg.stateDir; })
      // { CASTLE_WORKER_COMMAND = cfg.worker.command; }
      // { CASTLE_WORKER_TIMEOUT = toString cfg.worker.timeoutSeconds; }
      // (lib.optionalAttrs (cfg.worker.repoRoot != null) { CASTLE_REPO_ROOT = cfg.worker.repoRoot; })
      // (lib.optionalAttrs (cfg.notify.command != null) { CASTLE_NOTIFY_COMMAND = cfg.notify.command; });

    # ---------------------------------------------------------------
    # Automatic dispatch (docs/tasks/0021-auto-dispatch.md), off by
    # default — see castle.agent.dispatch.enable's description.
    #
    # The first systemd.user.* units in this repo. Everything else
    # using this path-unit-plus-oneshot pattern (modules/base's
    # castle-password-reminder-check) is a *system* unit because its
    # job needs root; dispatch needs the opposite, for three reasons.
    # agent/castle's spool and lease directories resolve relative to
    # $XDG_RUNTIME_DIR, a per-login-session concept — a system unit
    # would use /tmp/castle-0 instead of the resident's real runtime
    # directory. `castle route`'s notify channel shells out to
    # notify-send, which needs the session's bus to reach mako; a
    # system unit has no session to reach. And a user unit needs no
    # username baked into this public repo (Principle 02):
    # systemd.user.* units are per-login-session by construction, with
    # no `User=` to set.
    #
    # Deliberately minimal hardening, with the reasoning here rather
    # than left implicit: the worker tenant needs network (to reach a
    # model API), $HOME (its own config and credentials), and the
    # configured state directory. ProtectHome, PrivateNetwork, or a
    # restrictive ReadOnlyPaths would break the seat outright.
    # `Type = "oneshot"` with no `Restart=` is the only meaningful
    # constraint applied, and it is a correctness property (a oneshot
    # that fails is a mechanism fault, not a retry candidate — see
    # `castle dispatch`'s exit-code contract) rather than a security
    # one. Hardening a unit whose entire job is running an
    # unconstrained model tenant would be theatre: the containment
    # this design actually relies on is a code fact — `cmd_work` has
    # no path that runs nixos-rebuild, git commit, or anything else
    # that touches a running system (Proposal 03's "the worker
    # proposes, it never deploys").
    #
    # `ConditionUser=!@system` on all three, found by running
    # test/desktop-loop's VM rather than reasoned out in advance:
    # `systemd.user.*` units are declared for EVERY user with a
    # systemd instance, and on a host that imports modules/desktop
    # that includes greetd's own `greeter` system account. Its
    # manager dutifully started castle-dispatch at the login screen,
    # where the sweep exited 1 on a journal it has no business reading
    # ("Permission denied: /home/resident/private/state/journal") and
    # left a failed unit sitting in a session nobody inspects. The
    # sweep's exit code is supposed to mean "dispatch itself broke,"
    # so a guaranteed-failing instance of it on every boot is exactly
    # the health signal a resident would learn to ignore. `!@system`
    # is nixpkgs' own idiom for this — the same condition
    # `nixos-activation.service` (the user-specific activation unit)
    # carries — and it needs no username baked into this repo
    # (Principle 02).
    # ---------------------------------------------------------------
    systemd.user.paths.castle-dispatch = lib.mkIf cfg.dispatch.enable {
      description = "Watch the castle journal for records that need dispatching";
      wantedBy = [ "default.target" ];
      unitConfig.ConditionUser = "!@system";
      pathConfig = {
        # The whole journal directory, not `*-request-*.md`
        # specifically. A request-shaped watcher would satisfy this
        # task completely while foreclosing the next one:
        # docs/backlog/errand-resume-after-answer.md needs dispatch to
        # notice an `answer` record too, and a watcher keyed to a
        # filename shape is structurally unable to fire on anything
        # else — broadening it later means touching this unit on every
        # host that has it deployed. Watching the directory and
        # deciding eligibility in code means the *predicate* (a pure
        # function over the journal) can grow without this file
        # changing at all. The wakeup is a hint; the fold is the
        # authority.
        PathChanged = "${toString cfg.stateDir}/journal";
        MakeDirectory = true;
      };
    };

    systemd.user.services.castle-dispatch = lib.mkIf cfg.dispatch.enable {
      description = "Run one castle dispatch sweep over the journal";
      wantedBy = [ "default.target" ];
      unitConfig.ConditionUser = "!@system";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${castleCli}/bin/castle dispatch";
        # %h — the resident's home directory. `castle work` falls back
        # to the working directory when CASTLE_REPO_ROOT is unset,
        # which is why worker.repoRoot's description says plainly that
        # an operator who leaves it null is telling the tenant its repo
        # is their home directory.
        WorkingDirectory = "%h";
        # Baked in at `nixos-rebuild switch` rather than inherited.
        # Not because environment.sessionVariables cannot reach a
        # systemd user unit — it can: nixos/modules/security/pam.nix
        # wires pam_env.so into the systemd-user PAM service's session
        # stack by default, against the same /etc/pam/environment the
        # greetd login path reads (docs/tasks/0013's bug 2), and
        # `systemctl --user show-environment` does show CASTLE_STATE_DIR
        # on a real login. The argument is determinism: a value baked
        # into the unit reaches it immediately, with no re-login
        # required (pam_env-set variables only take effect on the
        # *next* login), and the unit stops depending on nixpkgs' PAM
        # wiring staying exactly as it is today.
        Environment =
          [
            "CASTLE_STATE_DIR=${toString cfg.stateDir}"
            "CASTLE_WORKER_COMMAND=${cfg.worker.command}"
            "CASTLE_WORKER_TIMEOUT=${toString cfg.worker.timeoutSeconds}"
          ]
          ++ lib.optional (cfg.notify.command != null) "CASTLE_NOTIFY_COMMAND=${cfg.notify.command}"
          ++ lib.optional (cfg.worker.repoRoot != null) "CASTLE_REPO_ROOT=${cfg.worker.repoRoot}";
      };
    };

    systemd.user.timers.castle-dispatch = lib.mkIf cfg.dispatch.enable {
      description = "Backstop for the castle dispatch path unit";
      wantedBy = [ "default.target" ];
      unitConfig.ConditionUser = "!@system";
      # A backstop, not the primary trigger: the path unit above fires
      # within moments of a record landing, but a missed inotify event
      # — or a request filed while this user session was down — would
      # otherwise wait forever. This is scheduling *for this
      # lifecycle*, which is exactly what docs/tasks/0021's non-goals
      # carve out from "no scheduling."
      timerConfig = {
        OnStartupSec = "1min";
        OnUnitActiveSec = "5min";
      };
    };

    # /code-review caught this on the branch that introduced the switch
    # to sessionVariables above: nixos/modules/config/system-
    # environment.nix's own pamVariable writes `NAME   DEFAULT="value"`
    # into /etc/pam/environment with no escaping, and nixos/modules/
    # security/pam.nix wires pam_env.so in as a `required` (not
    # `optional`) session rule — the same rule bug 2's fix now routes
    # through for a greetd login (see the comment above). A value
    # containing a literal `"` would produce a malformed
    # /etc/pam/environment line; because the rule is `required`, that
    # can fail PAM session establishment for *every* login through
    # greetd (a full-host lockout risk), not just break castle's own
    # env var the way a malformed /etc/set-environment line would have
    # under the old, login-shell-only mechanism. Asserted here, loudly,
    # at eval time, rather than left to surface on a real host as a
    # login failure with no obvious cause.
    assertions = [
      {
        assertion = cfg.stateDir == null || !(lib.hasInfix "\"" cfg.stateDir);
        message = ''
          castle.agent.stateDir contains a literal `"` character, which
          the PAM environment-file format `environment.sessionVariables`
          writes to cannot represent (nixpkgs' own option description:
          "due to limitations in the PAM format values may not contain
          the `\"` character") — and this module wires stateDir through
          exactly that option so CASTLE_STATE_DIR reaches a greetd-
          launched Sway session (docs/tasks/0013-first-deploy-findings.md,
          bug 2). Remove the quote from the path.
        '';
      }
      {
        assertion = !(lib.hasInfix "\"" cfg.worker.command);
        message = ''
          castle.agent.worker.command contains a literal `"` character —
          see castle.agent.stateDir's identical assertion message for
          why that breaks environment.sessionVariables' PAM-format
          write, and here the PAM rule it breaks is `required`, so this
          can fail login for the whole host, not just castle-modal.
          Quote arguments inside the command differently (e.g. single
          quotes, or a wrapper script) instead.
        '';
      }
      {
        assertion = cfg.worker.repoRoot == null || !(lib.hasInfix "\"" cfg.worker.repoRoot);
        message = ''
          castle.agent.worker.repoRoot contains a literal `"` character —
          see castle.agent.stateDir's identical assertion message for
          why that breaks environment.sessionVariables' PAM-format
          write. Use a path without a quote in it.
        '';
      }
      {
        # docs/tasks/0021-auto-dispatch.md: automatic dispatch is
        # exactly the situation where the journal has to be the
        # durable, private-repo-tracked one. Left to the fallback
        # (~/.local/state/castle), the configured path and the
        # fallback coincide — the same blindness
        # test/desktop-loop/test.nix's testStateDir comment documents
        # for docs/tasks/0013's bug 2b, except live on a real host
        # instead of caught in a harness.
        assertion = !cfg.dispatch.enable || cfg.stateDir != null;
        message = ''
          castle.agent.dispatch.enable is true but castle.agent.stateDir
          is unset. Automatic dispatch writes claim, result, and
          decision records unattended; they must land in the durable,
          private-repo-tracked journal you chose, not in whatever
          per-user fallback the CLI resolves on its own
          (~/.local/state/castle). Set castle.agent.stateDir to your
          private repo's state/ directory — see docs/private-layer.md.
        '';
      }
      {
        assertion = cfg.notify.command == null || !(lib.hasInfix "\"" cfg.notify.command);
        message = ''
          castle.agent.notify.command contains a literal `"` character —
          see castle.agent.stateDir's identical assertion message for
          why that breaks environment.sessionVariables' PAM-format
          write. Quote arguments inside the command differently (e.g.
          single quotes, or a wrapper script) instead.
        '';
      }
    ];
  };
}
