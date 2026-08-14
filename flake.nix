{
  description = "Castle Turing — an AI-native personal computing environment (framework layer)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # nixos-hardware will provide the dell-xps-13-9370 module for hosts/xps9370.
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    # Secrets tooling (agenix or sops-nix) MUST be added here before the
    # first credential exists anywhere in the system. See Principle 01.
  };

  outputs = { self, nixpkgs, nixos-hardware }: {
    # Stub. hosts/xps9370 becomes the first nixosConfiguration once the
    # hardware scan lands. Until then this flake intentionally exports
    # nothing, so that nothing can pretend to work.
  };
}
