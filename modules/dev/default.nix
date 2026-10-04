# modules/dev — the tools this project's own development happens with:
# Emacs, git, gh, ripgrep, fd, claude-code, python3 (so the test
# harnesses can run agent/castle from a checkout), and poppler-utils
# (PDF text extraction for research work done in dev sessions — see
# the note at its entry). System packages only
# (no private data, no host assumptions) — the point of
# docs/tasks/0005-dogfooding-desktop.md is that this project can host its
# own development, so this module is deliberately boring: install the
# tools, nothing to configure per-person here (git's *identity* is
# personal data and lives in modules/home instead, per Principle 01).
#
# `claude-code` is confirmed present in this flake's pinned nixpkgs
# (checked at the time this module was written — if a future pin bump
# ever drops it, that is a nixpkgs packaging fact worth noting here, not
# a reason to improvise a wrapper: prefer bumping back or waiting for it
# to return over hand-rolling an install path in this module).
#
# docs/tasks/0083-a-dev-shell-entry-costs-a-nixpkgs-eval-per-command.md
# adds direnv as this project's standing default, so a dev-shell entry
# (`nix develop`, `use flake` in a project's `.envrc`) is evaluated once
# per `flake.nix`/`flake.lock` change rather than once per command in an
# edit-then-test loop — see that brief for the incident and the design
# this answers. The eval-storm detector it also specifies lives in
# ./eval-storm.nix, imported below.
{
  lib,
  pkgs,
  ...
}:

let
  # The BASH_ENV hook that gives direnv's project environment to
  # non-interactive bash — every agent Bash call, every systemd unit,
  # every script — which direnv's own shell integration
  # (`programs.direnv.enableBashIntegration`'s `bash.interactiveShellInit`,
  # firing through PROMPT_COMMAND) never reaches (docs/tasks/0083's PR
  # #149 review). direnv itself enforces the trust decision
  # (`programs.direnv.settings.whitelist`, left unset below — a host or
  # the private layer's own prefixes, per Principle 01): this script
  # only has to ask direnv, never decide on its own whether a directory
  # is trusted.
  #
  # CASTLE_DIRENV_BASH_ENV_GUARD breaks a recursion that is real, not
  # hypothetical — verified against this flake's pinned direnv
  # (2.37.1) rather than assumed. direnv evaluates a project's .envrc
  # by running a second, nested `bash -c` (internal/cmd/rc.go's
  # `RC.Load`), and that nested process's environment is a copy of the
  # *caller's* environment (`newEnv = previousEnv.Copy()`) with nothing
  # that strips BASH_ENV — confirmed by reading rc.go and the
  # IgnoredKeys list in env_diff.go, which does not mention it. So the
  # nested bash also reads BASH_ENV, also runs this script, and would
  # also call `direnv export bash` again, forking a new direnv and a
  # new nested bash each time. DIRENV_IN_ENVRC does not break this: it
  # is exported by a line *inside* the nested script body
  # (direnv's `stdlib.sh`), which only runs once that bash's own
  # BASH_ENV sourcing has already finished — so it reads empty at
  # exactly the point this hook would need it, at every recursion
  # depth. Measured directly: an unguarded version of this script,
  # pointed at a cold-cache `.envrc`, forked dozens of direnv/bash
  # pairs in under five seconds before being killed — the exact
  # eval-storm shape this task exists to stop, self-inflicted by the
  # fix. Exporting our own marker *before* calling direnv, and checking
  # it first, works because that export happens in *this* process,
  # before direnv forks the nested one — so the nested bash inherits it
  # already set and skips straight through. Confirmed empirically
  # (hook invocation log across the recursion): exactly two invocations
  # per cold-cache load — this process, then the one nested bash's own
  # BASH_ENV sourcing — not an unbounded chain.
  #
  # CASTLE_DIRENV_DISABLE is the opt-out docs/tasks/0083 asks for: any
  # script that must see the ambient environment exactly as it is
  # (a deploy script, a git hook) sets it and this hook is a no-op.
  #
  # Known limitation, inherent to BASH_ENV rather than fixable here:
  # it is read once, at a shell's own startup, before any of that
  # shell's own commands run. `bash -c 'cd other-project && nix
  # develop --command X'` sees the environment for whatever directory
  # the shell *started* in, never `other-project` — the hook has
  # already run and returned by the time `cd` executes. This is why
  # every probe in test/direnv-delivery/test.nix is already sitting in
  # its target directory before spawning the bash that reads the
  # result (see that file's own probeScript), and it is the same
  # reason direnv's *interactive* hook exists as a PROMPT_COMMAND
  # re-run on every prompt instead of a one-shot: there is no
  # non-interactive equivalent of "re-run on every cd" to borrow here.
  direnvBashEnv = pkgs.writeShellScript "castle-direnv-bash-env" ''
    if [ -n "''${CASTLE_DIRENV_DISABLE:-}" ] || [ -n "''${CASTLE_DIRENV_BASH_ENV_GUARD:-}" ]; then
      return 0 2>/dev/null || exit 0
    fi

    if command -v direnv >/dev/null 2>&1; then
      export CASTLE_DIRENV_BASH_ENV_GUARD=1
      eval "$(direnv export bash)"
      # Exported variables are inherited by every later child this
      # shell spawns, not just direnv's own nested one — left set,
      # the guard would wrongly skip a second, unrelated non-
      # interactive bash started later from the same shell (e.g. a
      # script that `cd`s into a project only after already starting
      # once in another directory). Unset once direnv's own nested
      # evaluation has returned, so the guard only lives for the
      # window it has to.
      unset CASTLE_DIRENV_BASH_ENV_GUARD
    fi
  '';
in

{
  imports = [
    ./eval-storm.nix
    # docs/tasks/0089: per-invocation scopes for the nix client, so a
    # memory kill lands on the build rather than the session. Sibling
    # of eval-storm.nix on purpose: the detector names the storm, the
    # scope decides who dies when one wins anyway.
    ./nix-scope.nix
  ];

  # claude-code is packaged under an unfree license in nixpkgs; scoped to
  # just this package rather than a blanket `allowUnfree`, so adding it
  # doesn't silently normalize unfree software project-wide.
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "claude-code" ];

  environment.systemPackages = with pkgs; [
    emacs
    git
    gh
    ripgrep
    fd
    claude-code
    python3
    # PDF text extraction is a predictable need of research tasks, and
    # its absence is worse than a missing feature: on 2026-09-06 an
    # agent improvised it via repeated `nix shell nixpkgs#poppler-utils`
    # invocations, whose concurrent nixpkgs evaluations exhausted
    # memory and hung the host (task 0063). A tool agents will
    # predictably want is declared here once, not summoned per-command.
    poppler-utils
  ];

  programs.direnv = {
    enable = true;
    # nix-direnv rides `programs.direnv.nix-direnv.enable`'s own
    # default (true once direnv itself is enabled — confirmed by
    # reading this flake's pinned nixos/modules/programs/direnv.nix),
    # so nothing to set here.
    #
    # Silences direnv's own "loading .../.envrc" / "export +FOO" lines.
    # Those are harmless on an interactive terminal but land on stderr
    # of every non-interactive bash this module's BASH_ENV hook
    # touches — an agent's Bash tool call included — where they read
    # as unexplained noise ahead of a command's real output.
    silent = true;

    # Deliberately NO `settings.whitelist` here. The prefixes that
    # actually get through direnv's trust check are the resident's own
    # project roots — private configuration, not public mechanism
    # (Principle 01) — so a host or the private layer declares
    # `programs.direnv.settings.whitelist.prefix` itself. Left unset,
    # this module authorizes nothing, and every `.envrc` everywhere
    # keeps needing an explicit `direnv allow`.
    #
    # One path a prefix list can never cover, noted rather than
    # worked around here: the agent layer's worker seat
    # (modules/agent, docs/tasks/0053) copies each configured checkout
    # into a fresh `tempfile.mkdtemp` scratch directory every turn
    # (`CASTLE_EDIT_DIR`). That mirror's own path is never any
    # resident's whitelisted project root, however the original
    # checkout is configured, so a worker-seat bash sees no project
    # environment inside its own copy. Giving the worker seat the
    # same benefit this module gives an interactive session is a
    # question for whatever task touches CASTLE_EDIT_DIR's own
    # lifecycle, not this one.
  };

  # The pinned direnv module's own `environment.variables.DIRENV_CONFIG
  # = "/etc/direnv";` (nixos/modules/programs/direnv.nix) is how direnv
  # finds the whitelist above — and it rides `environment.variables`,
  # which (docs/tasks/0013-first-deploy-findings.md's bug 2,
  # modules/agent's own comment on the identical gap) only reaches
  # login shells via /etc/set-environment. Forwarded here through
  # `environment.sessionVariables` (PAM, via pam_env.so) for the same
  # reason BASH_ENV is: a shell launched by greetd→tuigreet→sway, or a
  # systemd user unit, crosses no login shell and would otherwise never
  # see it — and without it, direnv cannot find the whitelist at all,
  # silently falling back to requiring `direnv allow` everywhere.
  environment.sessionVariables = {
    BASH_ENV = "${direnvBashEnv}";
    DIRENV_CONFIG = "/etc/direnv";
  };

  # PAM session variables (environment.sessionVariables above) reach
  # the login-session ancestry only. A systemd *user* unit — castle's
  # own dispatch workers (modules/agent), and any headless agent path
  # that runs the same way — crosses no PAM, so it needs BASH_ENV and
  # DIRENV_CONFIG delivered a second way: `DefaultEnvironment` in the
  # user manager's own config (/etc/systemd/user.conf's [Manager]
  # section), which nixpkgs' own hyprland module uses for exactly this
  # ("pass PATH to every unit the user manager starts" —
  # nixos/modules/programs/wayland/hyprland.nix). Every unit the user
  # manager starts gets these two unless it sets its own
  # Environment=/EnvironmentFile= — castle-eval-storm-check
  # (./eval-storm.nix) does not, so it inherits them too, though it has
  # no use for either.
  systemd.user.settings.Manager.DefaultEnvironment = "BASH_ENV=${direnvBashEnv} DIRENV_CONFIG=/etc/direnv";
}
