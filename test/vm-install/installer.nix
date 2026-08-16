# The installer image the harness boots as its QEMU "target": the real
# public mechanism (flake.nixosModules.installer, docs/tasks/0006-
# installer-image.md), instantiated with the run's throwaway admin key.
# This is the same artifact a real install would use — not a parallel
# test-only stand-in — so this harness exercises the actual
# castle.admin.sshKeys + zero-console-interaction path that closes
# docs/tasks/0003-findings.md finding #3.
#
# --impure only for the getFlake self-reference (needed to pick up
# uncommitted working-tree changes under test, same as `nix flake check`
# would see) and the pubkey argument read from a file run.sh generates.
{
  pubkeyFile,
}:
let
  flake = builtins.getFlake (toString ../..);
  lib = flake.inputs.nixpkgs.lib;
  pubkey = lib.fileContents pubkeyFile;
in
flake.inputs.nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    flake.nixosModules.installer
    {
      castle.admin = {
        username = "harness";
        sshKeys = [ pubkey ];
      };
      # run.sh captures qemu's -serial as <phase>.serial.log for failure
      # diagnosis; without this the kernel only writes to the (discarded,
      # -display none) VGA console and that log is empty. Test-only: a
      # real, redistributed installer image keeps the stock VGA console.
      boot.kernelParams = [ "console=ttyS0" ];
    }
  ];
}
