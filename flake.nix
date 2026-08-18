{
  description = "Castle Turing — an AI-native personal computing environment (framework layer)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Declarative disk layout, consumed by nixos-anywhere at install time.
    # The partition table is a checked-in artifact, not tacit knowledge.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # The resident's per-user environment (modules/home). Bound into
    # nixosModules.home below so consumers need not add this input
    # themselves, same pattern as nixos-hardware/disko above.
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Secrets tooling (agenix or sops-nix) MUST be added here before the
    # first credential exists anywhere in the system. See Principle 01.
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-hardware,
      disko,
      home-manager,
    }:
    {
      # The mechanism, exported for private layers to assemble
      # (Principle 02: the private repo instantiates the castle; this
      # repo cannot name any resident).
      nixosModules = {
        base = ./modules/base;
        # The single-disk GPT layout (ESP + root) every host currently
        # uses; host modules declare only their device path
        # (castle.disk.device) — see modules/disk-layout.nix.
        diskLayout = ./modules/disk-layout.nix;
        # The resident's per-user environment (git identity today; more
        # to come). The wrapper binds this flake's home-manager pin so
        # consumers need neither input nor its own nixosModule import.
        home = {
          imports = [
            home-manager.nixosModules.home-manager
            ./modules/home
          ];
        };
        # The graphical session: Sway, a terminal, fonts, portals, audio,
        # login. Hardware-independent — see modules/desktop for what it
        # assumes and what it deliberately does not (auto-login).
        desktop = ./modules/desktop;
        # This project's own development tools (Emacs, git, gh, ripgrep,
        # fd, claude-code) — see docs/tasks/0005-dogfooding-desktop.md.
        dev = ./modules/dev;
        # The agent layer's CLI and state-dir option — see
        # docs/architecture.md and docs/tasks/0008-agent-layer-skeleton.md.
        # Optional, like desktop/dev, and deliberately not imported by
        # host-vm-test below: the install harness proves the machine
        # builds and boots with no agent layer at all.
        agent = ./modules/agent;
        # The agentic installer image (docs/tasks/0006): stock NixOS
        # installer media plus modules/base, so it's SSH-reachable by the
        # same castle.admin.sshKeys key a private layer already supplies
        # for the installed system — no console interaction, no separate
        # identity mechanism. See modules/installer.nix.
        installer = ./modules/installer.nix;
        # Hardware facts only. The wrapper binds this flake's
        # nixos-hardware and disko pins so consumers need neither input.
        host-xps9370 = {
          imports = [
            nixos-hardware.nixosModules.dell-xps-13-9370
            disko.nixosModules.disko
            self.nixosModules.diskLayout
            ./hosts/xps9370
          ];
        };
        # A fully-virtual QEMU/OVMF machine, not a real host — it exists
        # so test/vm-install/ can exercise the install mechanism in CI.
        # See docs/tasks/0004-install-test-harness.md.
        host-vm-test = {
          imports = [
            disko.nixosModules.disko
            self.nixosModules.diskLayout
            ./hosts/vm-test
          ];
        };
      };

      # CI stand-in only — do not point nixos-anywhere or nixos-rebuild
      # at this. A dummy resident, so `nix flake check` evaluates the
      # full stack without this repo naming a person; the placeholder
      # key and hash are not valid credential material, so nothing could
      # authenticate to a machine built from it even by mistake, but
      # disko's disk wipe still runs first. Includes home/desktop/dev so
      # CI proves the whole dogfooding-desktop stack
      # (docs/tasks/0005-dogfooding-desktop.md) composes end to end, the
      # same modules a real private layer assembles for hosts/xps9370 —
      # plus agent, so CI also proves the agent-layer slot
      # (docs/tasks/0008-agent-layer-skeleton.md) composes with the rest,
      # even though hosts/vm-test below deliberately omits it —
      # see docs/private-layer.md. Real configurations live in private
      # layers.
      nixosConfigurations.example = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.base
          self.nixosModules.host-xps9370
          self.nixosModules.home
          self.nixosModules.desktop
          self.nixosModules.dev
          self.nixosModules.agent
          (
            { config, lib, ... }:
            {
              castle.admin = {
                username = "resident";
                sshKeys = [
                  "ssh-ed25519 REPLACE-WITH-YOUR-PUBLIC-KEY this-is-a-placeholder-not-a-key"
                ];
                initialHashedPassword = "REPLACE-WITH-A-REAL-HASH-this-is-a-placeholder-not-a-hash";
              };
              castle.person = {
                gitUserName = "Resident";
                gitUserEmail = "resident@example.invalid";
              };
              # Simulates the private layer's own override of the
              # castle.display slot (docs/tasks/0009-ambient-intake.md
              # item 1) — the third of its three layers, alongside this
              # module's own null default and host-xps9370's
              # lib.mkDefault. Deliberately leaves `scale` and
              # `wallpaper` untouched so the assertion below can prove
              # their respective mkDefaults survive when nothing
              # overrides them, while cursorTheme and terminalFontSize
              # prove an explicit override wins.
              castle.display = {
                cursorTheme = "Bibata-Modern-Ice";
                terminalFontSize = 14;
                # A resident-supplied typeface, the case
                # castle.display.terminalFont exists for
                # (docs/tasks/0017-legible-defaults.md). Not a real
                # font package here — this configuration never renders
                # anything — but it proves the private layer wins over
                # the framework's generic default.
                terminalFont = "Example Mono";
              };
              # A regression test for the three-layer resolution itself,
              # not just "the flake evaluates": docs/tasks/0009's
              # verification plan asks for the display-preference
              # options to evaluate at all three layers in
              # `nix flake check`, and an assertion that checks the
              # resolved values is a stronger proof of that than
              # evaluation succeeding by itself would be.
              assertions = [
                {
                  assertion =
                    config.castle.display.scale == 2.0
                    && config.castle.display.cursorTheme == "Bibata-Modern-Ice"
                    && config.castle.display.cursorSize == 18
                    && config.castle.display.terminalFontSize == 14
                    && config.castle.display.terminalFont == "Example Mono"
                    # Framework defaults, surviving because nothing here
                    # or in the host overrides them.
                    && config.castle.display.uiFont == "sans-serif"
                    && config.castle.display.uiFontSize == 11
                    # Host default, NOT a framework default — the
                    # asymmetry docs/tasks/0017 argues for. If this ever
                    # starts resolving from modules/desktop instead,
                    # someone has "fixed" the inconsistency and broken
                    # the reasoning behind it.
                    && config.castle.display.consoleFont == "spleen-16x32"
                    && lib.hasSuffix "/share/backgrounds/castle-turing.jpg" config.castle.display.wallpaper;
                  message = ''
                    castle.display three-layer resolution regressed in
                    nixosConfigurations.example: expected hosts/xps9370's
                    lib.mkDefault values (scale=2.0, cursorSize=18 — see
                    that host module's comment for why 18 and not some
                    other number, docs/tasks/0013-first-deploy-findings.md)
                    to survive untouched since nothing here overrides them,
                    this module's own overrides (cursorTheme,
                    terminalFont, terminalFontSize) to win over both the
                    framework default and the host default, and
                    modules/desktop's own mkDefault (docs/tasks/0014) to
                    resolve castle.display.wallpaper to the shipped
                    image's store path since nothing here overrides
                    that either.

                    Since docs/tasks/0017 the layering is no longer
                    uniform, and this assertion pins that too: uiFont
                    and uiFontSize must resolve from *framework*
                    defaults (a point size is density-independent
                    because scale normalizes it, so one value is right
                    everywhere), while consoleFont must resolve from
                    the *host* (a console font is a pixel grid, and the
                    virtual console never sees scale at all). Three
                    different layers now answer for different options
                    in this same attrset; that is deliberate, and this
                    is where it stays honest.
                  '';
                }
                {
                  # docs/tasks/0021-auto-dispatch.md: this
                  # configuration imports nixosModules.agent and leaves
                  # castle.agent.dispatch.enable at its default, so no
                  # castle-dispatch user unit may exist. The middle
                  # case between "no agent module at all" (proven by
                  # test/vm-install's harness, which imports none) and
                  # "dispatch explicitly on"
                  # (nixosConfigurations.example-dispatch, below):
                  # default-off has to be provably off, not merely
                  # documented as off, because turning it on is a
                  # standing authority decision this framework must
                  # never make on a resident's behalf.
                  #
                  # Written as an implication ("dispatch off ⇒ no
                  # units") rather than a flat "no units", because
                  # `nixosConfigurations.example-dispatch` below
                  # extends *this* configuration and inherits its
                  # assertions — a flat form would go red there for
                  # the one configuration that is supposed to have the
                  # units. The antecedent holds here (this
                  # configuration never sets the option), so the check
                  # still bites exactly where it is aimed.
                  assertion =
                    config.castle.agent.dispatch.enable
                    || (
                      !(config.systemd.user.services ? castle-dispatch)
                      && !(config.systemd.user.paths ? castle-dispatch)
                      && !(config.systemd.user.timers ? castle-dispatch)
                    );
                  message = ''
                    nixosConfigurations.example generates a castle-dispatch
                    systemd user unit even though castle.agent.dispatch.enable
                    is left at its default. Automatic dispatch is opt-in
                    (docs/tasks/0021-auto-dispatch.md): importing
                    nixosModules.agent must never start errands on its own.
                  '';
                }
              ];
            }
          )
        ];
      };

      # Same role as .example, for hosts/vm-test: proves the mechanism
      # evaluates without naming a person. The install-loop test harness
      # (test/vm-install/) builds its own instantiation with a real,
      # throwaway per-run key instead of using this one directly.
      nixosConfigurations.vm-test-example = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.base
          self.nixosModules.host-vm-test
          {
            castle.admin = {
              username = "resident";
              sshKeys = [ "ssh-ed25519 REPLACE-WITH-YOUR-PUBLIC-KEY this-is-a-placeholder-not-a-key" ];
            };
          }
        ];
      };

      # Proves the installer mechanism evaluates without this repo naming
      # a person, same role as .example/.vm-test-example. The real
      # installer image (with a real admin key) is built from the
      # private layer, exactly like the real xps9370 nixosConfiguration
      # is — see docs/private-layer.md.
      nixosConfigurations.installer-example = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.installer
          {
            castle.admin = {
              username = "resident";
              sshKeys = [ "ssh-ed25519 REPLACE-WITH-YOUR-PUBLIC-KEY this-is-a-placeholder-not-a-key" ];
            };
          }
        ];
      };

      # The Mod4 case defect 2 (docs/tasks/0019) was invisible in: a
      # resident who switches the modifier to the Super key. `extendModules`
      # is a standard `nixosSystem` output attribute on this nixpkgs pin
      # (evaluated below, not merely assumed) — it re-evaluates
      # `nixosConfigurations.example` with one extra module layered on top,
      # rather than duplicating that whole configuration's module list a
      # second time. Eval-only: nothing builds this system (no CI job
      # forces `.config.system.build.toplevel`), but `nix flake check`
      # already forces every nixosConfiguration's `assertions`, which is
      # all that's needed to prove the modal chord displaces no stock
      # binding under a modifier `sway-config-check` (check.yml) never
      # renders — see docs/tasks/0019's scope item 4 for the residual this
      # closes and scope item 5 for why a second rendered-and-validated
      # job was rejected as redundant.
      nixosConfigurations.example-mod4 = self.nixosConfigurations.example.extendModules {
        modules = [
          (
            { config, lib, ... }:
            let
              # Same attribute path sway-config-check (check.yml) reads
              # off `nixosConfigurations.example` — `resident` is this
              # flake's own placeholder admin username
              # (castle.admin.username, set on `.example` and inherited
              # here), not a real person; see that job's own comment for
              # why the literal is spelled out rather than derived.
              keybindings =
                config.home-manager.users.resident.wayland.windowManager.sway.config.keybindings;
            in
            {
              home-manager.users.resident.wayland.windowManager.sway.config.modifier = "Mod4";

              assertions = [
                {
                  # The chord survives the modifier change: modules/home's
                  # `keybindings` definition is written against a literal
                  # "Mod4+..." key, not "${modifier}+...", so it is
                  # unaffected by the override above by construction — this
                  # assertion is a regression guard on that construction,
                  # not a live risk today.
                  assertion =
                    (keybindings."Mod4+Shift+Return" or null)
                    == "exec foot --app-id=castle-modal -e castle-modal --mode compose";
                  message = ''
                    nixosConfigurations.example-mod4: keybindings."Mod4+Shift+Return"
                    is not the ambient-intake exec command. modules/home/default.nix
                    hardcodes the modal chord under a literal Mod4 prefix
                    (docs/tasks/0019) specifically so it keeps working
                    regardless of a resident's own `modifier` setting — this
                    means that guarantee broke.
                  '';
                }
                {
                  # This is the defect-2 regression test (docs/tasks/0019)
                  # and is red on the code this brief starts from: home-
                  # manager's stock keybinding set includes
                  # "${modifier}+Shift+space" = "floating toggle", which
                  # only collides with the old "Mod4+Shift+space" modal
                  # chord once `modifier` is set to Mod4 — a configuration
                  # sway-config-check never renders (it only ever builds
                  # `nixosConfigurations.example`, whose modifier is the
                  # Mod1 default). The collision was silent: no eval error,
                  # no CI failure, just a missing binding — see the brief's
                  # "Why it is silent" section for the cross-level priority
                  # mechanism.
                  assertion = (keybindings."Mod4+Shift+space" or null) == "floating toggle";
                  message = ''
                    nixosConfigurations.example-mod4: keybindings."Mod4+Shift+space"
                    is not "floating toggle". Under modifier = "Mod4", Sway/i3's
                    stock floating-toggle binding lives at this exact key, and
                    modules/home/default.nix's ambient-intake chord displaced it
                    silently before docs/tasks/0019 moved the chord to
                    Mod4+Shift+Return. If this assertion is red, the chord (or
                    something else) is colliding with a stock Mod4 binding again.
                  '';
                }
              ];
            }
          )
        ];
      };

      # The other half of the default-off proof (docs/tasks/0021-auto-
      # dispatch.md): `nixosConfigurations.example` asserts that no
      # castle-dispatch unit exists when dispatch is left alone; this
      # variant turns it on and asserts the three units exist and carry
      # the environment the sweep needs. Same `extendModules` precedent
      # as example-mod4 above, and eval-only for the same reason —
      # nothing builds or boots this configuration, but `nix flake
      # check` forces every nixosConfiguration's `assertions`, which is
      # all it takes to prove the wiring. A dummy stateDir, because the
      # module (rightly) refuses to enable dispatch without one and
      # this repo may never name a real resident's path.
      nixosConfigurations.example-dispatch = self.nixosConfigurations.example.extendModules {
        modules = [
          (
            { config, lib, ... }:
            let
              dummyStateDir = "/home/resident/private/state";
              dummyRepoRoot = "/home/resident/private";
              unit = config.systemd.user.services.castle-dispatch or null;
              # The unit-level `environment` attrset, not a raw
              # serviceConfig.Environment list — see modules/agent's
              # comment on why the distinction is load-bearing (systemd
              # splits an unquoted Environment= value on whitespace;
              # the option's toJSON rendering is what quotes it).
              environment = if unit == null then { } else unit.environment;
            in
            {
              castle.agent = {
                dispatch.enable = true;
                stateDir = dummyStateDir;
                worker.repoRoot = dummyRepoRoot;
              };

              assertions = [
                {
                  assertion =
                    (config.systemd.user.services ? castle-dispatch)
                    && (config.systemd.user.paths ? castle-dispatch)
                    && (config.systemd.user.timers ? castle-dispatch);
                  message = ''
                    nixosConfigurations.example-dispatch: castle.agent.dispatch.enable
                    is true but modules/agent did not declare all three
                    systemd.user units (path, service, timer). The path unit is
                    the prompt trigger and the timer is the backstop for a missed
                    inotify event — losing either silently degrades automatic
                    dispatch to something slower or to nothing at all
                    (docs/tasks/0021-auto-dispatch.md §1).
                  '';
                }
                {
                  # Asserted on the option values, not on a built unit
                  # file: this is an eval-only check, and the attrs are
                  # what modules/agent actually promises.
                  assertion =
                    unit != null
                    && unit.serviceConfig.Type == "oneshot"
                    && unit.serviceConfig.WorkingDirectory == "%h"
                    # Pinned because losing it is silent and ugly:
                    # systemd.user units are declared for every user
                    # with a systemd instance, greetd's `greeter`
                    # included, and without this the sweep runs — and
                    # fails — at the login screen on every boot. Found
                    # by running test/desktop-loop's VM, not by
                    # reasoning (docs/tasks/0021 §1).
                    && unit.unitConfig.ConditionUser == "!@system"
                    # The service is activated BY the path unit and the
                    # timer, never wanted by default.target itself: a
                    # oneshot in the activation path would hold a login
                    # open for the length of a sweep
                    # (docs/tasks/0021 §1).
                    && unit.wantedBy == [ ]
                    && config.systemd.user.paths.castle-dispatch.wantedBy == [ "default.target" ]
                    && config.systemd.user.timers.castle-dispatch.wantedBy == [ "default.target" ]
                    && config.systemd.user.paths.castle-dispatch.unitConfig.ConditionUser
                      == "!@system"
                    && config.systemd.user.timers.castle-dispatch.unitConfig.ConditionUser
                      == "!@system"
                    && environment.CASTLE_STATE_DIR or null == dummyStateDir
                    # Without a PATH the default tenant (`claude -p`)
                    # and the notify channel (`notify-send`) are both
                    # unreachable from the unit — see modules/agent's
                    # comment; the VM test caught this one too.
                    && lib.hasPrefix "/run/current-system/sw/bin" (environment.PATH or "")
                    && environment.CASTLE_WORKER_TIMEOUT or null == "900"
                    && environment.CASTLE_REPO_ROOT or null == dummyRepoRoot
                    && (environment.CASTLE_WORKER_COMMAND or "") != ""
                    && config.systemd.user.paths.castle-dispatch.pathConfig.PathChanged
                      == "${dummyStateDir}/journal"
                    # Asserted absent, not merely unset by accident: a
                    # MakeDirectory here would create the resident's
                    # state directory before their private repo is
                    # restored into it (docs/tasks/0021 §1/§2.2).
                    && !(config.systemd.user.paths.castle-dispatch.pathConfig ? MakeDirectory)
                    && config.systemd.user.timers.castle-dispatch.timerConfig.OnUnitActiveSec
                      == "5min";
                  message = ''
                    nixosConfigurations.example-dispatch: the castle-dispatch units
                    do not carry what the sweep needs. Expected a oneshot service
                    running from %h with CASTLE_STATE_DIR, CASTLE_WORKER_COMMAND,
                    CASTLE_WORKER_TIMEOUT and CASTLE_REPO_ROOT baked in
                    (determinism, not an inheritance gap — see modules/agent's own
                    comment), a path unit watching the configured journal
                    directory rather than a filename pattern, and a five-minute
                    backstop timer (docs/tasks/0021-auto-dispatch.md §1).
                  '';
                }
              ];
            }
          )
        ];
      };

      # docs/tasks/0011: the real desktop stack, booted in a NixOS VM and
      # driven end to end — modal keybinding, request, router, digest,
      # correction — via nixosTest. Deliberately a `packages.*` output,
      # not `checks.*`: `checks` is what bare `nix flake check` builds
      # (check.yml's flake-check job runs it unfiltered on every PR),
      # and this test is exactly the kind of slow, path-filtered job
      # test/vm-install/'s own vm-install-test.yml already keeps out of
      # that fast gate by running as its own workflow with its own
      # trigger, rather than folding into `nix flake check` — see this
      # test's own file header for what it does and does not change
      # about the mechanism under test.
      packages.x86_64-linux.desktop-loop-test =
        nixpkgs.legacyPackages.x86_64-linux.testers.runNixOSTest (
          import ./test/desktop-loop/test.nix { inherit self; }
        );

      formatter = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ] (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);
    };
}
