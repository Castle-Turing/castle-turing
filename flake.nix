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
    # Secrets tooling (agenix or sops-nix) MUST be added here before the
    # first credential exists anywhere in the system. See Principle 01.
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-hardware,
      disko,
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
      # key is not valid key material, so nothing could authenticate to
      # a machine built from it even by mistake, but disko's disk wipe
      # still runs first. Real configurations live in private layers —
      # see docs/private-layer.md.
      nixosConfigurations.example = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.base
          self.nixosModules.host-xps9370
          {
            castle.admin = {
              username = "resident";
              sshKeys = [ "ssh-ed25519 REPLACE-WITH-YOUR-PUBLIC-KEY this-is-a-placeholder-not-a-key" ];
            };
          }
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

      formatter = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ] (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);
    };
}
