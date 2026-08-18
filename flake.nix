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
