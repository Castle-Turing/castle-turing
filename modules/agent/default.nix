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

  # The window-closer's environment, snapshotted from *this* generation
  # by `castle-activate.service`'s `ExecStartPre` before it runs
  # `nixos-rebuild switch`, and read back by `castle-activation-window
  # .service` via `EnvironmentFile` — caught by Codex's review of this
  # task's PR. `nixos-rebuild switch` reloads unit files before that
  # `ExecStartPre`/`ExecStart`/`ExecStartPost` sequence finishes, so if
  # the approved switch also changes `castle.agent.stateDir`, the
  # window-closer that later fires is the *new* generation's unit and
  # reads `CASTLE_STATE_DIR` baked from the *new* value — the wrong
  # journal, with nothing in it to confirm or roll back. This file is
  # what lets it read the journal the switch that opened the window was
  # actually using instead.
  activationWindowSnapshot = pkgs.writeText "castle-activation-window.env" ''
    CASTLE_STATE_DIR=${toString cfg.stateDir}
    CASTLE_ACTIVATION_WINDOW=${toString cfg.activation.windowSeconds}
    CASTLE_ROLLBACK_UNIT=castle-rollback.service
  '';
in
{
  # docs/tasks/0024-config-target.md §1. `castle.agent.worker.repoRoot`
  # shipped in docs/tasks/0021-auto-dispatch.md, is named in
  # docs/private-layer.md's own `resident.nix` template, and is
  # therefore a value a real private layer may already be setting —
  # one this repo cannot see, audit, or migrate on anyone's behalf
  # (Principle 02). Splitting it into `repo.private`/`repo.mechanism`
  # by deletion would fail that private layer's evaluation the next
  # time its owner bumped their flake.lock pin, with no warning and no
  # forwarding address. nixpkgs' own answer to this shape of change is
  # what is used here: the old path stays declared as an alias for the
  # new one, so the old spelling keeps evaluating and prints a
  # deprecation warning naming where it moved to.
  imports = [
    (lib.mkRenamedOptionModule
      [ "castle" "agent" "worker" "repoRoot" ]
      [ "castle" "agent" "repo" "private" ]
    )
  ];

  options.castle.agent = {
    stateDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Where the `castle` CLI's journal (and the resident model) live
        — see docs/architecture.md's "Where runtime state lives" and
        docs/private-layer.md. A `work/` subdirectory appears here too,
        holding a worker turn's two output files while it runs: they
        have to sit somewhere the worker tenant can write, and the
        default tenant is sandboxed to the resident's home directory
        (docs/tasks/0039-worker-writable-deliverables.md). It is
        scratch, not records — emptied as each turn ends, and swept of
        anything a killed turn left behind. This is a path to a durable, git-tracked
        directory on the host, never a value this repo can guess
        correctly, so the default is `null`: the CLI then falls back to
        its own `$XDG_STATE_HOME/castle` / `~/.local/state/castle`
        resolution (see agent/castle's `state_dir()`), which is a
        reasonable per-user default but not the durable, git-tracked
        location the architecture doc calls for.

        **Not a subdirectory of the private flake repo**, which is what
        this description recommended until
        docs/tasks/0030-state-outside-the-flake.md: evaluating a path
        flakeref copies that flake's whole tracked tree into
        /nix/store, where every file is world-readable, so a journal
        committed there is published on every `nixos-rebuild`.
        docs/private-layer.md's "The agent's state" documents the two
        layouts that avoid it — a sibling repository (recommended) or a
        git submodule at `state/`. Nothing here can check which one a
        resident chose; evaluation must not stat a resident's disk, so
        the check lives in the CLI (`castle validate` and `castle
        digest` warn) rather than in this option.

        Set from the private layer, e.g.:

          castle.agent.stateDir = "/home/<you>/private-state";

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
        `$CASTLE_DIFF_FILE`, `$CASTLE_TARGET_FILE`,
        `$CASTLE_FINDING_FILE`, and — when
        configured and usable — `$CASTLE_PRIVATE_ROOT` and
        `$CASTLE_MECHANISM_ROOT` are set in its environment; reasoning
        goes to stdout, a diff (or nothing) goes to
        `$CASTLE_DIFF_FILE`, and the one word naming which checkout
        that diff targets (`private` or `mechanism`) goes to
        `$CASTLE_TARGET_FILE`, from where `castle work` folds it into
        the result record's `target` field
        (docs/tasks/0024-config-target.md). One finding about the
        framework itself (or nothing) goes to `$CASTLE_FINDING_FILE`,
        from where the outbox commits it as a backlog entry on a new
        branch in the mechanism checkout, if one is configured — it is
        never pushed (docs/tasks/0042-finding-outbox.md).
        Since docs/tasks/0023-resume-cold.md the request body arrives
        under a heading, and on an errand this seat has already worked
        it is followed by that errand's own prior results, the
        questions it raised, and the resident's answers to them —
        everything a fresh tenant needs to continue cold, since no
        tenant remembers an earlier turn. A turn resuming an answered
        blocking question also carries `$CASTLE_RESUME_ANSWER_IDS` in
        its environment; the variable is absent on every other turn.
        See
        agent/castle-worker-claude for the reference implementation of
        that contract and test/agent-loop/contract-worker.sh for a
        model-free stand-in that satisfies it. *Not*
        test/agent-loop/scripted-worker.sh, which this description used
        to name: that fixture predates the worker contract, takes two
        positional arguments, reads nothing from stdin, and is invoked
        by harnesses that bypass `castle work` entirely — pointed at
        this option it exits 2 on every errand, and since one failed
        result is all it takes to make a request permanently
        ineligible, following that pointer would burn each request's
        single automatic attempt. THE WORKER MUST NOT DEPLOY — no
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
        legitimately takes longer — but not to 24 hours or beyond:
        `castle work` clamps the value below the worker scratch
        retention window (with a warning on stderr), because a turn
        that outlived the dispatch sweep's age-based prune would have
        its own output files deleted out from under it
        (docs/tasks/0039-worker-writable-deliverables.md §5).

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

    repo.private = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Your own private configuration repository — the checkout that
        holds `resident.nix`, any host module you wrote yourself, and
        (under `stateDir`) the journal. Wired into
        `CASTLE_PRIVATE_ROOT`, which `castle work` puts in the worker
        tenant's environment; see `agent/castle-worker-claude`, which
        tells the model this is the checkout its configuration changes
        are proposed against.

        **Renamed from `castle.agent.worker.repoRoot`**
        (docs/tasks/0024-config-target.md). The old name still
        evaluates and still works, printing a deprecation warning that
        names this one — see this module's `imports` for why a rename
        rather than a break.

        Default `null`, and it cannot be otherwise: the private
        flake's actual checkout path on disk is resident data, which
        this repo may never guess (Principle 02, the same reasoning
        `stateDir` above documents). There is deliberately no
        "must be non-null" assertion either, for `stateDir`'s reason:
        the agent layer is optional the way `desktop`/`dev` are, and
        Principle 02 consequence 2 forbids requiring anything
        person-shaped at evaluation time.

        **The refusal that matters happens at errand time instead.**
        `castle work` no longer guesses a directory when this is
        unset — the old fallback was the process's working directory,
        which under the dispatch unit is `%h`, so an unconfigured
        dispatched worker was unconditionally told its repo was your
        home directory. It now writes a `result` record with
        `outcome: failed` naming this option and runs no tenant at
        all. Per docs/tasks/0021's one-automatic-attempt rule that
        result also makes the errand permanently ineligible for
        automatic dispatch, so set this whenever you enable
        `castle.agent.dispatch.enable` — before, not after, the first
        errand is filed.

        A `str`, never a `path`, and the type is load-bearing rather
        than stylistic. Beyond `stateDir`'s own reason (a `path` would
        coerce to a store path in an environment-variable slot), a Nix
        `path` literal is **copied into the world-readable
        `/nix/store` at evaluation time** — so writing
        `castle.agent.repo.private = ./private;` would publish every
        journal entry and stated priority in that checkout to any
        local user who can read the store. A string cannot do that:
        Nix has no way to read "please copy this directory in" out of
        one.

        Must be an absolute path, and must not contain a literal `"`
        character — both asserted below. See `stateDir`'s description
        for what the quote breaks (this option rides
        `environment.sessionVariables` the same way, so a hand-run
        `castle work` in a terminal gets the same roots a dispatched
        one does).
      '';
    };

    repo.mechanism = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        A checkout of the **public** Castle Turing framework repo —
        `modules/`, `hosts/`, the option declarations themselves.
        Wired into `CASTLE_MECHANISM_ROOT`, the second half of the
        Principle 01 split `repo.private` names the first half of
        (docs/tasks/0024-config-target.md).

        **Null is the normal case, not a misconfiguration, and nothing
        in this framework treats it as one.** Principle 02 consequence
        1: the public repo has no installable configuration. A
        resident consumes it as a flake input pinned in `flake.lock`,
        not as a working tree they keep on disk — see
        docs/private-layer.md's `flake.nix` template, which names it
        only as `inputs.castle-turing.url`. A checkout exists on the
        machine this framework is *developed* on; that is a fact about
        that machine, not about Castle Turing.

        What it costs to leave unset is stated plainly rather than
        hidden: a worker on such a host cannot propose a change to
        `modules/` at all, because there is nowhere on disk to diff
        against — the flake input resolves to a read-only store path,
        and a diff against a store path is not something you can
        apply. The tenant is told to say so and stop, rather than
        fabricate a diff or silently do nothing (Proposal 03's
        degradation rule, applied one layer down from a seat to a
        checkout).

        Unlike `repo.private`, a broken value here never refuses a
        turn. If this names something that is not a usable git working
        tree, `castle work` treats the mechanism checkout as
        unavailable for that turn, passes the configured path to the
        tenant in `CASTLE_MECHANISM_ROOT_INVALID` instead so the
        tenant can name the real reason, and appends one sentence
        saying so to **every** result it writes that turn — including
        errands that never needed a mechanism checkout, which is the
        only way a typo here stays visible at all (docs/tasks/0024
        §16).

        Same `str`-not-`path`, same two assertions, same reasons as
        `repo.private` above.
      '';
    };

    dispatch.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Start eligible resident-filed errands automatically, with no
        `castle work` or `castle route` typed by hand
        (docs/tasks/0021-auto-dispatch.md).

        Declares four `systemd.user` units — a path unit watching the
        journal directory, a `oneshot` service running
        `castle dispatch`, a one-minute timer as a backstop for a
        missed inotify event, and a second `oneshot` that establishes
        the dispatch watermark at session start. The sweep reaps
        interrupted turns, runs the configured worker tenant against
        every eligible request one at a time, and routes once at the
        end.

        **Default off, deliberately.** Turning this on is a standing
        authority decision about your own machine — it lets a model
        tenant start work, and spend money, without a human in the
        loop at the moment it happens. This framework will not make
        that decision for a resident; a private layer opts in
        (docs/private-layer.md).

        Requires `castle.agent.stateDir` (asserted below), and you
        want `castle.agent.repo.private` too — without it every
        dispatched errand ends in a `failed` result that says so, and
        each one spends that errand's single automatic attempt. See
        that option's description.

        **Enable this on at most one host per journal.** The lease that
        guarantees one turn at a time is machine-local, and nothing yet
        reconciles two dispatchers over a synced journal: two enabled
        hosts sharing one private repo would work the same request
        twice and write false `interrupted` results at each other.

        Deliberately **no `loginctl enable-linger`**: without
        lingering, these units run only while you are logged in, which
        is the honest lifetime for a mechanism whose only externally
        visible output today is a desktop notification. Running
        dispatch between logins is a separate authority decision and
        is out of scope here.
      '';
    };

    apply.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Make changes you have approved, in your own configuration
        repository, with no `castle apply` typed by hand
        (docs/tasks/0026-apply-validate.md).

        Declares three `systemd.user` units of its own — a path unit
        watching the journal directory, a `oneshot` service running
        `castle apply --sweep`, and a one-minute timer as a backstop
        for a missed inotify event. Deliberately its own trio rather
        than a step inside the dispatch sweep: an apply may run a
        build, and a build inside that sweep would hold the global
        dispatch lock — or the dispatch unit itself — for as long as it
        took, so one slow check would stop every errand on the machine.

        **What turning this on authorizes, exactly.** For each change
        you approve from here on, and once each: edit those files in
        `castle.agent.repo.private` and make one commit there naming
        your approval. It **pushes nothing anywhere**, it **activates
        nothing** — no `nixos-rebuild`, no `switch`, no new generation,
        no change to the running system — and it never writes a
        checkout of this framework. Switching to a new configuration
        stays yours to do, by hand.

        **It cannot reach an approval you gave before this existed.**
        Every proposal is stamped at filing time with whether approving
        it authorizes an apply, and the applier honours only that stamp
        — because the sentence you read while deciding is the scope of
        what you decided, and no later change of wording reaches
        backwards. There is no migration and there will not be one.

        **Default off, deliberately**, and this is a larger authority
        decision than `dispatch.enable`'s: that one lets a model tenant
        spend money, this one lets the agent layer change your
        configuration. This framework will not make that decision for a
        resident; a private layer opts in (docs/private-layer.md). The
        undecided taxonomy that would let this be described more
        precisely is docs/backlog/authority-taxonomy-prior-art.md.

        Requires `castle.agent.stateDir` and
        `castle.agent.repo.private`, both asserted below.

        **Enable this on at most one host per journal**, for a sharper
        version of the reason `dispatch.enable` gives: two enabled
        hosts would apply the same approved change to two different
        checkouts, and only one of them is the one you mean.
      '';
    };

    apply.evaluateFlake = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        After making an approved change, check that the configuration it
        produces still evaluates and builds
        (docs/tasks/0026-apply-validate.md §E). Wired into
        `CASTLE_APPLY_EVALUATE_FLAKE`.

        Named for **evaluation** rather than for "validation" generally,
        because evaluation is what is actually being authorised here.
        This is the first thing in the agent layer that evaluates your
        flake at all, and evaluating a path flakeref copies the
        repository's whole tracked tree into `/nix/store`, where every
        file is readable by every account and every process on the
        machine, immutably until garbage collection.

        That is safe exactly because docs/tasks/0030–0032 made that tree
        publish-safe: the rule is "keep *plaintext* out of the store",
        your journal has lived outside the flake since 0030, and
        `secrets.yaml` is ciphertext by design. It is not safe if your
        state directory is still inside the flake's tracked tree — so
        the applier asks that question first and declines to evaluate
        rather than publishing your decision history. The change is
        still made either way; only the check is gated.

        What it runs, once, unprivileged, is
        `nix build --no-link --no-write-lock-file --no-update-lock-file`
        on this machine's own `system.build.toplevel`. Never as root,
        never `nix flake check`, never a lock-file update, and it
        activates nothing. The exact command line is recorded whether it
        ran or not, so you can paste it yourself.

        **What "checked" does and does not mean**: the configuration
        evaluates and its toplevel builds. Not that the change did what
        it said it would — nothing anywhere declares that — not that
        secrets will decrypt, and not that it will activate.
      '';
    };

    apply.timeoutSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1800;
      description = ''
        How long `castle apply` lets that check run before killing its
        whole process group and recording `outcome: timeout`
        (docs/tasks/0026-apply-validate.md). Wired into
        `CASTLE_APPLY_TIMEOUT`.

        Thirty minutes is chosen, not derived, and it is deliberately
        much longer than `worker.timeoutSeconds`: that one bounds a
        model call, this one bounds a *build*, and the only Nix-capable
        host this ever runs on is your own machine, which may
        legitimately compile a kernel. The change is already made and
        committed by the time this clock starts; what a timeout costs is
        the check, never the change.
      '';
    };

    activation.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Let this machine build, and — on your say-so, one switch at a
        time — activate its own configuration
        (docs/tasks/0048-activation.md).

        **This is the first standing root grant in this project, and
        turning it on is a larger decision than anything else in this
        module.** `dispatch.enable` lets a model tenant spend money;
        `apply.enable` lets the agent layer change your configuration
        *files*; this one lets it change the machine you are using.

        **What turning it on authorizes, exactly.** Two things, and they
        are deliberately unequal:

        - *Building, freely and with no question asked.* Whenever your
          configuration repository has moved, or the framework revision
          it pins has fallen behind the one your framework checkout last
          fetched, Castle builds the configuration that produces. A
          build changes nothing, and a question whose only honest answer
          is yes is a question that teaches you to stop reading
          questions.
        - *Switching, once per approval.* A clean build files a question
          on the review screen. Approving it switches this machine, and
          nothing else does. There is no standing, autonomous or batched
          activation tier and this task deliberately does not add one.

        **The root grant, and its scope.** Two system units are
        declared, carrying exactly two commands:

            nixos-rebuild switch --flake <your repo>#<this host>
            nixos-rebuild switch --rollback

        and a polkit rule lets `castle.agent.activation.user` start
        those two units and nothing else. No argument reaches them from
        your session, so there is nothing for a process running as you
        to forge. What that costs is stated rather than hidden: the
        privileged step rebuilds from your repository rather than
        activating a store path it was handed, so the closure that ends
        up running is not *by construction* the one you were shown. It
        is in practice, and where it is not, the record says so — every
        activation records what you approved beside what
        `/run/current-system` says afterwards.

        **The health window.** After a switch, Castle asks whether this
        machine is working. If nothing says so within
        `castle.agent.activation.windowSeconds`, it rolls back to the
        previous generation on its own. That is the one thing in this
        system that decides without you, and the asymmetry is the
        argument: a good generation rolled back costs you one keypress,
        a bad one left running costs you a trip to the machine with a
        USB stick.

        **What a switch cannot fully apply.** A kernel, initrd or
        firmware change is staged into the new generation and takes
        effect at the next boot. The review screen says so before you
        approve.

        **It cannot reach an approval you gave before this existed**,
        and there is no migration — see `apply.enable`'s identical
        paragraph for why a change of wording never reaches backwards.

        Requires `castle.agent.stateDir`, `castle.agent.repo.private`
        and `castle.agent.activation.user`, all asserted below. Enable
        it on at most one host per journal, for the sharpest version of
        the reason `apply.enable` gives.

        It pushes nothing anywhere. `docs/architecture.md`'s push bullet
        is untouched by this.
      '';
    };

    activation.user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        The one account whose session may start the two privileged units
        `castle.agent.activation.enable` declares
        (docs/tasks/0048-activation.md §H). Written into a polkit rule
        that permits `org.freedesktop.systemd1.manage-units` on exactly
        those two unit names, for exactly this user, and nothing else.

        Principle 01's split, in its plainest form: the units, the rule
        and the sweep are public mechanism; *who* holds the grant is
        private configuration, and this framework has no business
        guessing it. Null by default, and asserted non-null only inside
        the branch a resident opted into.

        This is normally the same account as `castle.admin.username`,
        but it is a separate option on purpose — the account that
        administers a machine and the account a resident's agent layer
        runs as need not be the same one, and conflating them here would
        hand the grant to whichever a host happened to name first.
      '';
    };

    activation.windowSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 900;
      description = ''
        How long a health confirmation has to arrive after a switch
        before Castle rolls this machine back
        (docs/tasks/0048-activation.md §E). Wired into
        `CASTLE_ACTIVATION_WINDOW` and into the system timer that
        enforces it.

        Fifteen minutes is chosen, not derived: long enough to notice a
        machine is fine and click a notification, short enough that a
        machine which lost its network or its display is not left that
        way for an afternoon. Raise it if you routinely switch and then
        walk away; lower it if you would rather find out sooner.

        What this bounds is the *confirmation*, never the switch. A
        switch that is still running when this expires has not finished
        being asked for, and the window starts when the privileged unit
        starts, not when it ends.
      '';
    };

    activation.timeoutSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3600;
      description = ''
        How long `castle build` lets one `nix` invocation run before
        killing it and recording the failure
        (docs/tasks/0048-activation.md). Wired into
        `CASTLE_ACTIVATION_TIMEOUT`.

        An hour, and deliberately longer than
        `castle.agent.apply.timeoutSeconds`' thirty minutes: that one
        bounds a check of a configuration that has just been changed by
        a few lines, this one may be building the whole system after a
        framework bump moved nixpkgs, which is a kernel and a desktop
        from source in the worst case.
      '';
    };

    activation.frameworkInput = lib.mkOption {
      type = lib.types.str;
      default = "castle-turing";
      description = ''
        What your private flake calls this framework in its `inputs`
        (docs/tasks/0048-activation.md §B). Wired into
        `CASTLE_FRAMEWORK_INPUT`, and read out of your `flake.lock` to
        decide whether the pin is behind.

        The default is the name `docs/private-layer.md`'s own template
        publishes. A resident who called it something else says so here
        rather than having the pin trigger silently never fire — which
        is what an unrecognised name produces, with a record saying so.

        The pin trigger also needs `castle.agent.repo.mechanism`. Castle
        compares your lock against `origin/main` in that checkout and
        **never fetches**, because a fetch is network run unattended
        with nobody watching; what `origin/main` means here is exactly
        what your last fetch saw. A host with no framework checkout gets
        the applied-change trigger only.
      '';
    };

    notify.command = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        The notification command for the router's `notify` channel
        (docs/tasks/0009-ambient-intake.md item 5). Since
        docs/tasks/0034-inbox-modal.md §3 it is no longer invoked
        directly by `castle route`: the router spawns a detached
        waiter (`castle notify-waiter`) and returns immediately, and
        the *waiter* runs this command with `--app-name=castle`,
        `--action=default=Open`, the title, and the body appended — so
        the value must be a `notify-send`-compatible command, not an
        arbitrary `<command> <title> <body>` sink. The waiter blocks
        on the notification's fate: a click focuses an existing
        castle-modal window or launches one deep-linked to the
        record; dismissal or expiry ends the waiter silently. Wired
        into `CASTLE_NOTIFY_COMMAND`. Default `null`: the waiter's
        own fallback (`notify-send` on `$PATH`) applies instead,
        which is real on any host that also imports `modules/desktop`
        (which installs mako + libnotify). A missing notify binary is
        silent since 0034 (the waiter is best-effort in every branch);
        only an unparseable value or a failed waiter spawn still warns
        on `castle route`'s stderr. Set explicitly to `""` on a
        headless host to skip even spawning the waiter.

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
    # CASTLE_WORKER_TIMEOUT and the repo roots joined the block with
    # docs/tasks/0021-auto-dispatch.md, for the same reason the other
    # three are here rather than only on the dispatch unit below: a
    # `castle work` a resident runs by hand from a terminal inside the
    # Sway session must get the identical timeout guard and repo roots
    # an automatically-dispatched worker gets, not a weaker version of
    # either. The timeout rides unconditionally (it always has a
    # value); each root only when one is actually configured.
    #
    # Two roots, not one, since docs/tasks/0024-config-target.md: the
    # tenant has to be able to tell the resident's private
    # configuration checkout from a checkout of this framework, which
    # is exactly the Principle 01 split it is asked to decide a fix's
    # layer against. A single CASTLE_REPO_ROOT could not name both,
    # and is retired rather than kept alongside them — one renamed
    # alias would just relocate the ambiguity under a new name.
    #
    # The two apply variables joined with
    # docs/tasks/0026-apply-validate.md for the same reason the timeout
    # did: a `castle apply <answer-id>` a resident runs by hand from a
    # terminal inside the Sway session must behave exactly as the unit
    # does, not evaluate when the unit would not or run to a different
    # bound. Both ride unconditionally — each always has a value — and
    # `apply.enable` itself is deliberately NOT among them: it declares
    # units, it is not something the CLI reads.
    environment.sessionVariables =
      (lib.optionalAttrs (cfg.stateDir != null) { CASTLE_STATE_DIR = cfg.stateDir; })
      // { CASTLE_WORKER_COMMAND = cfg.worker.command; }
      // { CASTLE_WORKER_TIMEOUT = toString cfg.worker.timeoutSeconds; }
      // (lib.optionalAttrs (cfg.repo.private != null) { CASTLE_PRIVATE_ROOT = cfg.repo.private; })
      // (lib.optionalAttrs (cfg.repo.mechanism != null) { CASTLE_MECHANISM_ROOT = cfg.repo.mechanism; })
      // { CASTLE_APPLY_EVALUATE_FLAKE = lib.boolToString cfg.apply.evaluateFlake; }
      // { CASTLE_APPLY_TIMEOUT = toString cfg.apply.timeoutSeconds; }
      // (lib.optionalAttrs (cfg.notify.command != null) { CASTLE_NOTIFY_COMMAND = cfg.notify.command; })
      # docs/tasks/0048-activation.md, for the apply variables' own
      # reason above: a `castle build` or `castle activate <answer-id>`
      # a resident runs by hand must read the same timeout, window and
      # framework input the automatic unit does, not silently fall back
      # to agent/castle's own defaults (caught by Codex's review of
      # this task's PR). All three ride unconditionally — each always
      # has a value, exactly like the two apply variables above.
      // {
        CASTLE_ACTIVATION_TIMEOUT = toString cfg.activation.timeoutSeconds;
        CASTLE_ACTIVATION_WINDOW = toString cfg.activation.windowSeconds;
        CASTLE_FRAMEWORK_INPUT = cfg.activation.frameworkInput;
      };

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
    # `ConditionUser=!@system` on all four, found by running
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
        # specifically. A request-shaped watcher would have satisfied
        # docs/tasks/0021 completely while foreclosing the next task,
        # and that is no longer hypothetical:
        # docs/tasks/0023-resume-cold.md needs dispatch to notice an
        # `answer` record too — an answered blocking question makes its
        # errand eligible for one further turn — and a watcher keyed to
        # a filename shape is structurally unable to fire on anything
        # else. Broadening it later would have meant touching this unit
        # on every host that had it deployed; because it was written
        # this way, 0023 shipped without changing a line here. Watching the directory and
        # deciding eligibility in code means the *predicate* (a pure
        # function over the journal) can grow without this file
        # changing at all. The wakeup is a hint; the fold is the
        # authority.
        PathChanged = "${toString cfg.stateDir}/journal";
        # Deliberately NO MakeDirectory. systemd watches the nearest
        # existing parent of a path that does not exist yet and fires
        # when the path appears, so nothing is lost by not creating it
        # — and creating the resident's state directory from a unit is
        # exactly the restore-order hazard `castle dispatch`'s own
        # guard closes: on a machine where dispatch is enabled before
        # the repository holding the journal is cloned — the state
        # repository, which since
        # docs/tasks/0030-state-outside-the-flake.md is deliberately
        # not the config repo — a unit that
        # helpfully mkdir'd the path would both break that clone and
        # let castle-dispatch-watermark (or, failing that, the first
        # sweep) write a watermark declaring that nothing predates it,
        # minutes before the real history arrived. Left uncreated, the
        # restore is what makes this path appear, this unit fires on
        # it, and the sweep it triggers writes the watermark itself —
        # the backstop for a journal that lands mid-session, after the
        # session-start unit below has already found nothing to mark.
      };
    };

    systemd.user.services.castle-dispatch = lib.mkIf cfg.dispatch.enable {
      description = "Run one castle dispatch sweep over the journal";
      # Deliberately NO wantedBy: the path unit and the timer above and
      # below activate this service, and they are the ones default.target
      # wants. A Type=oneshot pulled directly into default.target holds
      # the user manager's activation open for the whole sweep — up to
      # `worker.timeoutSeconds` per eligible errand, so a queue of them
      # could keep a login "starting" for a very long time — and buys
      # nothing, because the 5s OnStartupSec timer already delivers the
      # first sweep of the session without blocking anything. The one
      # thing that genuinely had to happen before a login could race it
      # — putting the watermark down — is castle-dispatch-watermark's
      # job below, and that unit IS in default.target: a journal read
      # plus at most one record write is not a sweep.
      unitConfig.ConditionUser = "!@system";
      serviceConfig = {
        Type = "oneshot";
        # The default KillMode (control-group) kills every process left
        # in this unit's cgroup the moment the oneshot's ExecStart
        # process exits — not just on an explicit `systemctl stop`, but
        # on the ordinary transition out of "active" that follows a
        # completed sweep. `agent/castle`'s notify path deliberately
        # detaches a waiter (setsid) precisely so it can outlive the
        # sweep and block on a notification for as long as the daemon
        # keeps it up, but `start_new_session=True` only leaves the
        # unit's *process group* — it stays in the unit's *cgroup*,
        # which is what control-group cleanup acts on, so every waiter
        # spawned by an automatic (systemd-triggered) sweep was killed
        # out from under it the instant `castle dispatch` returned,
        # silently discarding the notification's click handler. `process`
        # confines the kill to the tracked main process — already exited
        # by the time this matters — leaving the waiter to run to its
        # own completion, exactly as a manually invoked `castle route`
        # (with no enclosing unit at all) already does. Nothing else in
        # this sweep depends on control-group's wider net: a runaway
        # worker tenant is reined in by `castle work`'s own
        # start_new_session=True + os.killpg on timeout, not by systemd.
        KillMode = "process";
        ExecStart = "${castleCli}/bin/castle dispatch";
        # %h — the resident's home directory. It used to be load-
        # bearing in the worst way: `castle work` fell back to its
        # working directory when no repo root was configured, so an
        # unconfigured dispatched worker was told its repo was the
        # resident's home folder. docs/tasks/0024-config-target.md
        # deleted that fallback outright — an unconfigured turn now
        # refuses honestly instead — so this is once again nothing but
        # a defined place for the sweep to start from.
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
      };
      # The unit-level `environment` option, NOT a raw
      # serviceConfig.Environment list, and the difference is
      # load-bearing: systemd's Environment= splits an unquoted value
      # on whitespace, so a raw list entry like
      # "CASTLE_WORKER_COMMAND=claude -p" silently becomes
      # CASTLE_WORKER_COMMAND=claude with the "-p" dropped — a
      # silent-wrong-value bug of exactly the shape docs/tasks/0013's
      # bug 2 was, waiting for the first resident whose tenant command
      # carries an argument. The `environment` option renders every
      # entry through toJSON (nixos/lib/systemd-lib.nix, the
      # `Environment=${toJSON ...}` line), producing
      # Environment="NAME=value with spaces" — one quoted assignment,
      # exactly what systemd's own syntax wants. The existing
      # `"`-character assertions on these options are what keep that
      # quoting always representable. A null value is simply omitted
      # (same systemd-lib line), so notify and the two repo roots need
      # no optionalAttrs dance here.
      environment = {
        # A systemd user manager hands its units a bare PATH that
        # contains neither of the two binaries this sweep actually
        # needs, which the VM test caught doing exactly that: the
        # default worker tenant (agent/castle-worker-claude) execs
        # `claude` from $PATH, and `castle route`'s notify channel
        # shells out to `notify-send`. Both live in the system
        # profile on a host that imported modules/dev and
        # modules/desktop respectively — so without this line,
        # enabling dispatch with the *default* tenant produces a
        # result record saying the tenant could not be run, and
        # every notification the router fires is silently lost to a
        # non-fatal warning nobody reads. `%u` and `%h` are systemd
        # specifiers (Environment= expands specifiers), so the
        # resident's own profile paths are reachable with no username
        # baked into this repo (Principle 02). mkForce because
        # nixpkgs' user.nix already gives every user service a stock
        # PATH (coreutils, grep, sed, systemd) at normal priority;
        # this value replaces it rather than merging, and loses
        # nothing by doing so — /run/current-system/sw/bin carries all
        # of those on any NixOS host.
        PATH = lib.mkForce "/run/current-system/sw/bin:/etc/profiles/per-user/%u/bin:%h/.nix-profile/bin";
        CASTLE_STATE_DIR = toString cfg.stateDir;
        CASTLE_WORKER_COMMAND = cfg.worker.command;
        CASTLE_WORKER_TIMEOUT = toString cfg.worker.timeoutSeconds;
        CASTLE_NOTIFY_COMMAND = cfg.notify.command;
        CASTLE_PRIVATE_ROOT = cfg.repo.private;
        CASTLE_MECHANISM_ROOT = cfg.repo.mechanism;
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
        # 5s, not a minute: an OnStartupSec timer whose interval has
        # already elapsed fires immediately on activation, so this
        # value is really "how long after the user manager starts
        # before the first sweep runs." It no longer has anything to
        # do with the watermark — castle-dispatch-watermark below owns
        # that boundary, and owns it at an instant no login can beat.
        # Five seconds is still worth having for what a first sweep
        # actually does: reap the turns a crash or a logout interrupted
        # and surface whatever backlog is waiting, promptly after
        # login, without holding the login open while it happens.
        OnStartupSec = "5s";
        # A minute, not five. This tick is the only thing that ever
        # runs when an inotify event is missed, or when a request was
        # filed while this session was down — and the price of either
        # is total silence until the next tick. Five minutes of that
        # sits badly against a mechanism whose whole promise to a
        # resident is "filing is enough"; the VM test raced that
        # backstop and lost. The tick is cheap when there is nothing to
        # do: one journal read, one lock, one log line, no model call.
        OnUnitActiveSec = "1min";
      };
    };

    # The watermark is put down here, at the instant the user manager
    # starts, and not by whichever sweep happens to run first.
    #
    # test/desktop-loop caught the difference by failing: the timer's
    # OnStartupSec is measured from user-manager start, and a
    # graphical login plus one modal keystroke beats five seconds
    # comfortably. In the VM the resident's very first request was
    # filed a second after the user manager came up and roughly five
    # seconds before the first sweep — so on a fresh journal that
    # request was outstanding when the sweep wrote the watermark, was
    # named in the watermark's own refs, and was therefore excluded
    # from automatic dispatch by name, permanently. The sweep printed
    # "nothing eligible" and nothing ever triggered again. That is a
    # product defect on any fresh host, not a test artifact: a request
    # filed in the first seconds after login was silently and
    # permanently excluded.
    #
    # Moving the write here changes the boundary from "filed before
    # the first sweep happened to run" to "filed before this
    # dispatch-enabled session existed," which is the boundary
    # §2.2 always meant. This unit runs before any compositor exists —
    # there is no window in which a human could file anything, because
    # there is nothing yet to file it with.
    #
    # It is `wantedBy = default.target` where the sweep service
    # deliberately is not, and the distinction is the cost of the
    # oneshot: the objection to putting the *sweep* in a login's
    # activation path is that it can hold the user manager open for
    # `worker.timeoutSeconds` per eligible errand. This does one
    # journal read and at most one record write, and then it is done.
    #
    # Be honest about the guarantee: it is a margin, not a systemd
    # ordering edge. greetd launches the compositor as the session
    # process, not as a user unit, so there is no `Before=` that can
    # be written against the thing that must lose the race — the
    # claim is milliseconds against seconds, not an enforced order.
    # The failure mode if it ever did lose is soft and visible, which
    # is what makes the margin acceptable: the request lands in the
    # watermark's refs, appears on the status surface with its
    # `castle work <id>` label, and runs by hand.
    systemd.user.services.castle-dispatch-watermark = lib.mkIf cfg.dispatch.enable {
      description = "Establish the dispatch watermark at session start";
      wantedBy = [ "default.target" ];
      unitConfig.ConditionUser = "!@system";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${castleCli}/bin/castle dispatch --watermark-only";
        WorkingDirectory = "%h";
      };
      # Only the state directory. This path runs no tenant and fires
      # no notification, so it needs neither the worker environment
      # (command, timeout, repo root) nor the PATH line the sweep
      # service carries for `claude` and `notify-send` — castleCli
      # wraps its own python3 at a store path, so `castle` itself
      # needs nothing on PATH to run.
      environment = {
        CASTLE_STATE_DIR = toString cfg.stateDir;
      };
    };

    # ---------------------------------------------------------------
    # Applying an approved change (docs/tasks/0026-apply-validate.md),
    # off by default — see castle.agent.apply.enable's description.
    #
    # Its own trio, modelled line for line on the dispatch units above
    # and watching the same directory, rather than a step inside the
    # dispatch sweep. Three things that buys, none of them cosmetic:
    #
    # A validation may legitimately run for half an hour
    # (apply.timeoutSeconds), and inside the sweep that would either
    # hold the global dispatch lock — escalating
    # docs/backlog/stalled-mount-wedges-a-sweep.md from "one errand
    # hangs" to "the whole mechanism stops, silently" — or hold the
    # dispatch *unit* busy, which stops the next sweep at the systemd
    # level even with the lock free.
    #
    # Dispatch learns nothing about applies: its eligibility fold, its
    # one-attempt bound and its "the wakeup is a hint, the fold is the
    # authority" doctrine are all untouched. A second watcher on the
    # same directory is that doctrine applied twice rather than bent
    # once.
    #
    # And `castle dispatch`'s exit-code contract keeps meaning what it
    # means. An apply refusal is not a dispatch mechanism fault, and
    # folding one into that unit's health signal would blur the one
    # signal a resident is asked to trust.
    #
    # **No watermark unit, and none is needed.** Dispatch needs a
    # boundary because "has this request been worked" cannot be answered
    # about a restored history; the applier's bound is per-answer and an
    # approval granted before this task lacks `authorizes-apply`
    # entirely, so a restored journal is invisible to its fold with no
    # boundary to put down.
    # ---------------------------------------------------------------
    systemd.user.paths.castle-apply = lib.mkIf cfg.apply.enable {
      description = "Watch the castle journal for approved changes to make";
      wantedBy = [ "default.target" ];
      unitConfig.ConditionUser = "!@system";
      pathConfig = {
        # The whole journal directory, for the reason the dispatch path
        # unit gives at length: the wakeup is a hint and the fold is the
        # authority, so a watcher keyed to a filename shape would
        # foreclose the next predicate for no gain. Here the record that
        # matters is an `answer`, which a request-shaped watcher would
        # have missed outright.
        PathChanged = "${toString cfg.stateDir}/journal";
        # Deliberately no MakeDirectory, same as dispatch: creating the
        # resident's state directory from a unit is the restore-order
        # hazard `castle apply`'s own guard closes.
      };
    };

    systemd.user.services.castle-apply = lib.mkIf cfg.apply.enable {
      description = "Make every approved change that has not been made yet";
      # No wantedBy, same as castle-dispatch and for the same reason: the
      # path unit and the timer activate this, and a Type=oneshot pulled
      # into default.target would hold the user manager's activation
      # open for the whole run — here potentially a whole build.
      unitConfig.ConditionUser = "!@system";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${castleCli}/bin/castle apply --sweep";
        WorkingDirectory = "%h";
      };
      # The unit-level `environment` option and never a raw
      # serviceConfig.Environment list — see the dispatch service's own
      # comment for the whitespace-splitting bug that choice avoids.
      environment = {
        # `git` for the apply itself and `nix` for the optional check,
        # both of which reach a session only through modules/dev, plus
        # `notify-send` for the sweep's routing tail. A systemd user
        # manager's bare PATH has none of them. mkForce for the same
        # reason dispatch gives: nixpkgs' user.nix already sets a stock
        # PATH at normal priority and this replaces it.
        PATH = lib.mkForce "/run/current-system/sw/bin:/etc/profiles/per-user/%u/bin:%h/.nix-profile/bin";
        CASTLE_STATE_DIR = toString cfg.stateDir;
        # The private root and nothing else. There is deliberately no
        # CASTLE_MECHANISM_ROOT here: the applier refuses a
        # mechanism-targeted change by name and never needs a path to
        # that checkout, so it is not given one.
        CASTLE_PRIVATE_ROOT = cfg.repo.private;
        CASTLE_APPLY_EVALUATE_FLAKE = lib.boolToString cfg.apply.evaluateFlake;
        CASTLE_APPLY_TIMEOUT = toString cfg.apply.timeoutSeconds;
      }
      # optionalAttrs, not a bare assignment, for hygiene rather than
      # necessity — and the distinction was settled by building it, not
      # by trusting the review that flagged it. Codex round 5 claimed a
      # bare null here fails module evaluation; it does not at this
      # pin: the toplevel builds and the generated unit simply carries
      # no CASTLE_NOTIFY_COMMAND line, which is also exactly what this
      # spelling produces. What the bare assignment leant on was the
      # unit serializer silently dropping nulls — undocumented
      # behaviour that a nixpkgs bump could change into either an eval
      # error or, worse, an empty string, and CASTLE_NOTIFY_COMMAND=""
      # is a documented, meaningful value (notifications off) where
      # unset means "default notify-send". The session environment at
      # the top of this file already spells this option with
      # optionalAttrs; now both sites agree.
      // (lib.optionalAttrs (cfg.notify.command != null) {
        CASTLE_NOTIFY_COMMAND = cfg.notify.command;
      });
    };

    systemd.user.timers.castle-apply = lib.mkIf cfg.apply.enable {
      description = "Backstop for the castle apply path unit";
      wantedBy = [ "default.target" ];
      unitConfig.ConditionUser = "!@system";
      timerConfig = {
        # 15s rather than dispatch's 5s, and the difference is
        # deliberate: nothing is ever eligible here until a resident has
        # approved something, so there is no backlog worth racing to at
        # login, and starting a possible build fifteen seconds after the
        # user manager comes up is politer than five.
        OnStartupSec = "15s";
        # A minute, matching dispatch: this tick is the only thing that
        # runs when an inotify event is missed or when an approval was
        # made while this session was down, and the price of either is
        # total silence until the next one. It is cheap when there is
        # nothing to do — one journal read, one lock, one log line.
        OnUnitActiveSec = "1min";
      };
    };

    # ---------------------------------------------------------------
    # The activation seats (docs/tasks/0048-activation.md).
    #
    # Three user units and four system ones. The split down the
    # privilege boundary is the design rather than a packaging choice:
    # everything that reads the journal, builds, decides eligibility and
    # writes records runs as the resident, and the only things that run
    # as root are two fixed commands and the timer that may need to run
    # the second of them.
    # ---------------------------------------------------------------
    systemd.user.paths.castle-activation = lib.mkIf cfg.activation.enable {
      description = "Watch the castle journal for builds to make and switches to spend";
      wantedBy = [ "default.target" ];
      unitConfig.ConditionUser = "!@system";
      pathConfig = {
        # The whole journal directory, for the reason the dispatch and
        # apply path units both give: the wakeup is a hint and the fold
        # is the authority. Here the records that matter are an apply
        # result (a build is owed) and an answer (a switch is
        # authorized), which no single filename shape covers.
        PathChanged = "${toString cfg.stateDir}/journal";
      };
    };

    systemd.user.services.castle-activation = lib.mkIf cfg.activation.enable {
      description = "Build what this machine is owed, then spend one approved switch";
      # No wantedBy, same as castle-dispatch and castle-apply: the path
      # unit and the timer activate this, and a Type=oneshot pulled into
      # default.target would hold the user manager's activation open for
      # a whole system build.
      unitConfig.ConditionUser = "!@system";
      serviceConfig = {
        Type = "oneshot";
        # Two ExecStart lines, in this order, and the `-` on the first
        # is load-bearing: a build that fails is an ordinary, recorded
        # outcome, and it must not stop an approval the resident already
        # granted from being spent. They are one unit rather than two
        # because they are one seat's concern and serialize naturally on
        # one lock — the applier's argument for its own separate trio
        # (a build inside the *dispatch* sweep would stall every errand)
        # does not apply between these two.
        ExecStart = [
          "-${castleCli}/bin/castle build --sweep"
          "${castleCli}/bin/castle activate --sweep"
        ];
        WorkingDirectory = "%h";
      };
      environment = {
        # `nix` for the build, `git` for the worktree and the pin-bump
        # commit, `systemctl` for the one privileged step, and
        # `notify-send` for the routing tail. mkForce for the reason
        # dispatch gives.
        PATH = lib.mkForce "/run/current-system/sw/bin:/etc/profiles/per-user/%u/bin:%h/.nix-profile/bin";
        CASTLE_STATE_DIR = toString cfg.stateDir;
        CASTLE_PRIVATE_ROOT = cfg.repo.private;
        CASTLE_ACTIVATION_TIMEOUT = toString cfg.activation.timeoutSeconds;
        CASTLE_ACTIVATION_WINDOW = toString cfg.activation.windowSeconds;
        CASTLE_FRAMEWORK_INPUT = cfg.activation.frameworkInput;
        CASTLE_ACTIVATE_UNIT = "castle-activate.service";
        CASTLE_ROLLBACK_UNIT = "castle-rollback.service";
      }
      # The framework checkout is passed here and NOT to the applier,
      # and the asymmetry is deliberate in both directions: the applier
      # refuses a mechanism-targeted change by name and never needs a
      # path to that checkout, while the pin trigger's whole question is
      # what that checkout's `origin/main` says. It is read, never
      # written and never fetched.
      // (lib.optionalAttrs (cfg.repo.mechanism != null) {
        CASTLE_MECHANISM_ROOT = cfg.repo.mechanism;
      })
      // (lib.optionalAttrs (cfg.notify.command != null) {
        CASTLE_NOTIFY_COMMAND = cfg.notify.command;
      });
    };

    systemd.user.timers.castle-activation = lib.mkIf cfg.activation.enable {
      description = "Backstop for the castle activation path unit";
      wantedBy = [ "default.target" ];
      unitConfig.ConditionUser = "!@system";
      timerConfig = {
        # 30s rather than apply's 15s and dispatch's 5s, and the
        # ordering is the point: at login this is the unit most likely
        # to start a long build and the least likely to have anything
        # urgent to do, so it goes last.
        OnStartupSec = "30s";
        OnUnitActiveSec = "1min";
      };
    };

    # ---------------------------------------------------------------
    # The privileged half. Two units, two fixed commands, no arguments
    # from anywhere (docs/tasks/0048-activation.md §H).
    # ---------------------------------------------------------------
    systemd.services.castle-activate = lib.mkIf cfg.activation.enable {
      description = "Switch this machine to its configured system configuration";
      # No wantedBy anywhere: this runs when, and only when, a resident's
      # session starts it through the polkit rule below. A unit pulled
      # into a target would switch this machine at boot on its own,
      # which is the standing authority this task explicitly does not
      # grant.
      serviceConfig = {
        Type = "oneshot";
        # Snapshot this generation's window context to a tmpfs path
        # before switching to a possibly-different one — see
        # `activationWindowSnapshot`'s comment.
        ExecStartPre = "${pkgs.coreutils}/bin/install -m0644 ${activationWindowSnapshot} /run/castle-activation-window.env";
        # `nixos-rebuild switch --flake`, and nothing configurable
        # beyond the flakeref this module already knows. This line IS
        # the grant: a resident can read it in /etc/systemd/system and
        # see the whole of what they gave away.
        ExecStart = "${config.system.build.nixos-rebuild}/bin/nixos-rebuild switch --flake ${cfg.repo.private}#${config.networking.hostName}";
        # Arming the window from inside the unit that opened it, rather
        # than from the resident's session, so the deadline exists even
        # if that session dies in the same instant the switch lands —
        # which is one of the failure modes the window is for.
        ExecStartPost = "${pkgs.systemd}/bin/systemctl start --no-block castle-activation-window.timer";
        Environment = [ "PATH=/run/current-system/sw/bin" ];
      };
    };

    systemd.services.castle-rollback = lib.mkIf cfg.activation.enable {
      description = "Roll this machine back to its previous generation";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${config.system.build.nixos-rebuild}/bin/nixos-rebuild switch --rollback";
        Environment = [ "PATH=/run/current-system/sw/bin" ];
      };
    };

    systemd.timers.castle-activation-window = lib.mkIf cfg.activation.enable {
      description = "The health window a switch has to be confirmed within";
      # Started by castle-activate.service, never wanted by a target:
      # a window that opened at boot would roll a machine back for not
      # confirming something it never did.
      timerConfig = {
        # Relative to when this timer is activated, which is the moment
        # the switch was asked for.
        OnActiveSec = "${toString cfg.activation.windowSeconds}s";
        Unit = "castle-activation-window.service";
        # One shot: the service it fires either finds a confirmation or
        # rolls back, and either way the window is closed for good.
        RemainAfterElapse = false;
      };
    };

    systemd.services.castle-activation-window = lib.mkIf cfg.activation.enable {
      description = "Close the health window: confirm, or roll back";
      serviceConfig = {
        Type = "oneshot";
        # **The only `castle` invocation on this machine that runs as
        # root**, and it is root because what it may have to do is roll
        # back. It writes records into the resident's journal and hands
        # each one back to that journal's owner immediately (agent/castle's
        # `_chown_to_journal_owner`), so a window that closed while
        # nobody was logged in does not leave root-owned files in a
        # git-tracked state repository.
        ExecStart = "${castleCli}/bin/castle activate --close-window";
        Environment = [
          "PATH=/run/current-system/sw/bin"
          # Notifications off on this one unit, and it is the option's
          # own documented spelling for it rather than an omission: a
          # notification waiter spawned by root from a system unit has
          # no session bus to talk to and no window to open. The record
          # is durable either way, and the resident's own sweep — which
          # routes on every tick — is what announces it, from a session
          # that can.
          "CASTLE_NOTIFY_COMMAND="
        ];
        # Two files, in this order: systemd merges `EnvironmentFile`
        # entries in list order, a later one overriding an earlier one
        # for the same name. The first is this *generation's* own
        # `CASTLE_STATE_DIR`/`CASTLE_ACTIVATION_WINDOW`/`CASTLE_ROLLBACK_UNIT`
        # — the ordinary case, and what applies when nothing about them
        # changed. The second is `castle-activate.service`'s own
        # snapshot of whatever generation actually opened this window,
        # taken before it switched away from itself; it overrides the
        # first when the switch changed one of these settings, which is
        # the case this pair of files exists for (see
        # `activationWindowSnapshot`'s comment). The leading `-`
        # tolerates the runtime file being absent, which is the
        # ordinary case for the first activation this mechanism ever
        # runs.
        EnvironmentFile = [
          activationWindowSnapshot
          "-/run/castle-activation-window.env"
        ];
      };
    };

    # The grant itself. `org.freedesktop.systemd1.manage-units` scoped
    # to two unit names and one user, in polkit's own rule language,
    # which is what makes it reviewable as a rule rather than as a
    # program's argument handling.
    #
    # **Read `action.lookup("unit")` and not `action.lookup("verb")`
    # alone.** systemd puts the unit name in the action's `unit`
    # detail; a rule that checked only the action id would grant this
    # user start/stop/restart over *every* unit on the machine, which
    # is the widening this whole design exists to avoid.
    #
    # `security.polkit.enable` is turned on here rather than assumed:
    # it defaults false in nixpkgs, and a rule installed into a polkit
    # that is not running is a grant that silently does not exist —
    # which surfaces as an activation that always fails, a long way
    # from its cause.
    security.polkit = lib.mkIf cfg.activation.enable {
      enable = true;
      extraConfig = ''
        // Castle Turing: the activation grant (docs/tasks/0048-activation.md).
        // Scope: starting exactly two units, for exactly one user.
        polkit.addRule(function(action, subject) {
          if (action.id != "org.freedesktop.systemd1.manage-units") {
            return polkit.Result.NOT_HANDLED;
          }
          if (subject.user != "${toString cfg.activation.user}") {
            return polkit.Result.NOT_HANDLED;
          }
          var unit = action.lookup("unit");
          if (unit == "castle-activate.service" || unit == "castle-rollback.service") {
            return polkit.Result.YES;
          }
          return polkit.Result.NOT_HANDLED;
        });
      '';
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
        assertion = cfg.repo.private == null || !(lib.hasInfix "\"" cfg.repo.private);
        message = ''
          castle.agent.repo.private contains a literal `"` character —
          see castle.agent.stateDir's identical assertion message for
          why that breaks environment.sessionVariables' PAM-format
          write. Use a path without a quote in it.
        '';
      }
      {
        # New with docs/tasks/0024-config-target.md, and deliberately
        # narrower than it could be: stateDir carries no equivalent
        # check today and widening it to match is a separate, easy
        # follow-up rather than something folded in here just because
        # the pattern became visible. A relative path in this option
        # would be resolved against whatever directory the tenant
        # happened to start in — which is precisely the guessing this
        # task removed from `castle work`, reintroduced one layer up.
        assertion = cfg.repo.private == null || lib.hasPrefix "/" cfg.repo.private;
        message = ''
          castle.agent.repo.private is not an absolute path. It is
          wired straight into CASTLE_PRIVATE_ROOT and handed to a
          worker tenant whose working directory this repo does not
          control, so a relative path names a different place
          depending on who invoked the turn. Give the full path to
          your private checkout.
        '';
      }
      {
        assertion = cfg.repo.mechanism == null || !(lib.hasInfix "\"" cfg.repo.mechanism);
        message = ''
          castle.agent.repo.mechanism contains a literal `"` character —
          see castle.agent.stateDir's identical assertion message for
          why that breaks environment.sessionVariables' PAM-format
          write. Use a path without a quote in it.
        '';
      }
      {
        assertion = cfg.repo.mechanism == null || lib.hasPrefix "/" cfg.repo.mechanism;
        message = ''
          castle.agent.repo.mechanism is not an absolute path — see
          castle.agent.repo.private's identical assertion for why a
          relative one names a different place depending on who
          invoked the turn.
        '';
      }
      {
        # docs/tasks/0021-auto-dispatch.md: automatic dispatch is
        # exactly the situation where the journal has to be the
        # durable, git-tracked one. Left to the fallback
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
          git-tracked journal you chose, not in whatever per-user
          fallback the CLI resolves on its own (~/.local/state/castle).
          Set castle.agent.stateDir to that directory — and not to a
          subdirectory of your flake repo, which would publish the
          journal to the world-readable Nix store on every rebuild. See
          docs/private-layer.md's "The agent's state".
        '';
      }
      {
        # docs/tasks/0026-apply-validate.md §K, mirroring the dispatch
        # assertion above it verbatim and for the same reason: an
        # applier writes result records unattended, and they must land
        # in the durable, git-tracked journal the resident chose rather
        # than in whatever per-user fallback the CLI resolves on its
        # own.
        assertion = !cfg.apply.enable || cfg.stateDir != null;
        message = ''
          castle.agent.apply.enable is true but castle.agent.stateDir is
          unset. Applying an approved change writes a durable record of
          what it did to your configuration repository; that record must
          land in the journal you chose, not in a per-user fallback
          (~/.local/state/castle) that nothing backs up. Set
          castle.agent.stateDir — and not to a subdirectory of your
          flake repo. See docs/private-layer.md's "The agent's state".
        '';
      }
      {
        # **This one deviates from the neighbouring precedent, and the
        # deviation is deliberate.** `dispatch.enable` has no matching
        # assertion on `repo.private`, on the argument that the
        # errand-time refusal is the right place for it — and that is
        # right there, where what an unconfigured root burns is one
        # errand's automatic attempt. Here what it burns is *a
        # resident's granted authorization*, which is costlier and less
        # repeatable: any apply result at all, `failed` included, bars a
        # second automatic attempt on that approval forever.
        #
        # Principle 02 consequence 2 is not violated. Nothing
        # person-shaped is required to evaluate this module; the
        # requirement exists only inside a branch the resident opted
        # into, exactly like the stateDir assertion above.
        assertion = !cfg.apply.enable || cfg.repo.private != null;
        message = ''
          castle.agent.apply.enable is true but castle.agent.repo.private
          is unset, so there is no configuration repository for an
          approved change to be made in. Unlike a dispatched errand,
          which can simply be re-run, an approval that gets spent on a
          failed apply is not automatically retried — the record bars a
          second attempt. Set castle.agent.repo.private to the absolute
          path of your own configuration checkout before turning this
          on.
        '';
      }
      {
        # docs/tasks/0048-activation.md §K, mirroring the apply
        # assertion above it and for a sharper version of its reason:
        # an activation writes a durable record of a change to the
        # running machine, and it is the record a rollback decision is
        # read out of.
        assertion = !cfg.activation.enable || cfg.stateDir != null;
        message = ''
          castle.agent.activation.enable is true but castle.agent.stateDir
          is unset. Switching this machine writes a durable record of
          what it did — including which generation it switched to, which
          is what a rollback is expressed against. That record must land
          in the journal you chose, not in a per-user fallback
          (~/.local/state/castle) that nothing backs up. See
          docs/private-layer.md's "The agent's state".
        '';
      }
      {
        # The privileged unit's ExecStart interpolates this path
        # directly, so an unset value would produce
        # `nixos-rebuild switch --flake #<host>`, which is not a
        # flakeref. Asserted at eval time rather than left to fail on a
        # live host as a switch that never works.
        assertion = !cfg.activation.enable || cfg.repo.private != null;
        message = ''
          castle.agent.activation.enable is true but castle.agent.repo.private
          is unset, so there is no configuration for this machine to be
          switched to. That path is written straight into the privileged
          unit's command line. Set castle.agent.repo.private to the
          absolute path of your own configuration checkout before
          turning this on.
        '';
      }
      {
        # The one assertion in this module about a *person*, and it sits
        # inside a branch the resident opted into — Principle 02
        # consequence 2 is not violated, exactly as the apply
        # assertions' own comment argues. Without it the polkit rule
        # would interpolate to `subject.user != ""`, which matches
        # nobody: a grant that silently does not exist, surfacing as an
        # activation that always fails a long way from its cause.
        assertion = !cfg.activation.enable || cfg.activation.user != null;
        message = ''
          castle.agent.activation.enable is true but castle.agent.activation.user
          is unset, so the polkit rule this declares would name no
          account and permit nobody. This is the one thing about
          activation that this framework cannot guess and will not:
          which account's session may tell this machine to switch is
          yours to say. Set it to that user name — normally the same as
          castle.admin.username, though deliberately a separate option.
        '';
      }
      {
        # A quote here would break the polkit rule's JavaScript string
        # literal, and the failure mode is not a syntax error a resident
        # would see: polkit logs a rule it could not parse and carries
        # on, so the grant simply does not exist. Same class of defect
        # as the PAM-format assertions above, one language over.
        assertion = cfg.activation.user == null || !(lib.hasInfix "\"" cfg.activation.user);
        message = ''
          castle.agent.activation.user contains a literal `"` character,
          which would end the string in the polkit rule this module
          generates. polkit does not fail loudly on a rule it cannot
          parse — it logs and carries on — so the result would be an
          activation grant that silently does not exist. Use a user name
          without a quote in it.
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
