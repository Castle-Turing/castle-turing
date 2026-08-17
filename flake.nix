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
            { config, ... }:
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
              # lib.mkDefault. Deliberately leaves `scale` untouched so
              # the assertion below can prove the host's mkDefault
              # survives when nothing overrides it, while cursorTheme
              # and terminalFontSize prove an explicit override wins.
              castle.display = {
                cursorTheme = "Bibata-Modern-Ice";
                terminalFontSize = 12;
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
                    && config.castle.display.cursorSize == 48
                    && config.castle.display.terminalFontSize == 12;
                  message = ''
                    castle.display three-layer resolution regressed in
                    nixosConfigurations.example: expected hosts/xps9370's
                    lib.mkDefault values (scale=2.0, cursorSize=48) to
                    survive untouched since nothing here overrides them,
                    and this module's own overrides (cursorTheme,
                    terminalFontSize) to win over both the framework
                    default and the host default.
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

      # docs/tasks/0012: the harness in test/vm-install/ structurally
      # cannot catch a console that renders but eats every keypress — it
      # asserts SSH-reachability with zero console interaction, so that
      # console passes every one of its assertions untouched (that's
      # exactly what shipped and locked an operator out on the first
      # from-scratch boot). And this repo has already been burned twice
      # by checks that pass on an evaluated *option* or a syntactically
      # *valid* config while the thing a human would actually see is
      # still wrong (`nix flake check` proving options evaluate;
      # `sway --validate` accepting a session with one keybinding and no
      # way out — see check.yml's sway-config-check job for the second
      # one). So this check does what that job does: build the actual
      # store path systemd will exec, and read it, rather than trust
      # that the source above compiled to what it says.
      #
      # modules/installer.nix's own assertions cover the *configuration*
      # half of the guarantee (services.getty.autologinOnce staying on,
      # so not every getty auto-logs into the status script); this check
      # covers the other half — that the escape hint modules/installer.nix
      # adds to the status script's banners actually survived into the
      # generated artifact, not just the Nix source.
      checks.x86_64-linux.installer-escape-hatch =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          # config.users.users.nixos.shell is a plain string with Nix
          # store context (modules/installer.nix builds it as
          # "${statusScript}/bin/castle-installer-status"), so passing
          # it straight through as a derivation attribute below makes
          # this build depend on — and this command can directly cat —
          # the exact file agetty will exec into on tty1.
          statusScript = self.nixosConfigurations.installer-example.config.users.users.nixos.shell;
        in
        pkgs.runCommand "installer-escape-hatch-check"
          {
            inherit statusScript;
          }
          ''
            echo "--- generated installer status script ($statusScript) ---"
            cat "$statusScript"
            echo "--- end generated script ---"

            if ! grep -q "Ctrl+Alt+F2" "$statusScript"; then
              echo
              echo "FAIL: the generated installer status script no longer prints its"
              echo "escape-hatch hint (expected to find \"Ctrl+Alt+F2\" somewhere in it)."
              echo "docs/tasks/0012-installer-escape-hatch.md: the way out has to be"
              echo "readable on the console the operator is actually staring at, not"
              echo "just documented in a source comment nobody stuck at a dead console"
              echo "can read. If the wording changed deliberately, update this check's"
              echo "expected string (flake.nix, checks.x86_64-linux.installer-escape-hatch)"
              echo "to match."
              exit 1
            fi

            touch "$out"
          '';

      formatter = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ] (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);
    };
}
