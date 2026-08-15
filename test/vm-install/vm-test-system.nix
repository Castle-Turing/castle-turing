# The real nixosConfiguration one harness run installs: the published
# mechanism (modules/base + hosts/vm-test) plus one throwaway admin key
# generated fresh by run.sh for this run only — never committed, never a
# real resident. Same shape a private layer would supply
# (docs/private-layer.md), for test purposes only.
#
# --impure only because of the getFlake self-reference (needed to pick up
# uncommitted working-tree changes under test, same as `nix flake check`
# would see) and the pubkey argument read from a file run.sh generates.
# The framework mechanism itself — modules/base, hosts/vm-test,
# modules/disk-layout.nix — is evaluated exactly as published.
{
  pubkeyFile,
}:
let
  flake = builtins.getFlake (toString ../..);
  lib = flake.inputs.nixpkgs.lib;
  pubkey = lib.removeSuffix "\n" (builtins.readFile pubkeyFile);
in
flake.inputs.nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    flake.nixosModules.base
    flake.nixosModules.host-vm-test
    {
      castle.admin = {
        username = "harness";
        sshKeys = [ pubkey ];
      };
    }
  ];
}
