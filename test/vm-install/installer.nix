# The installer image the harness boots as its QEMU "target": the stock
# NixOS minimal installer profile, plus SSH reachable by the same
# throwaway key run.sh generates for the run — standing in for a human
# typing `nmtui` and fetching a key by hand at the console, which is
# exactly the manual step docs/tasks/0003-findings.md (finding #3) says
# doesn't scale to an agent retrying an install. Test-only: never built or
# published outside a harness run.
{
  pubkeyFile,
}:
let
  flake = builtins.getFlake (toString ../..);
  nixpkgs = flake.inputs.nixpkgs;
  lib = nixpkgs.lib;
  pubkey = lib.removeSuffix "\n" (builtins.readFile pubkeyFile);
in
nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
    {
      # Faster/smaller image; CI time budget matters more than a tight
      # image for a disk that's discarded at the end of the job.
      isoImage.squashfsCompression = "gzip -Xcompression-level 1";
      # The ISO profile sets its own default (10s, for a human at a real
      # console); this harness is never at a console.
      boot.loader.timeout = lib.mkForce 0;

      # run.sh captures qemu's -serial as <phase>.serial.log for failure
      # diagnosis; without this the kernel only writes to the (discarded)
      # VGA console and that log is empty.
      boot.kernelParams = [ "console=ttyS0" ];

      services.openssh.enable = true;
      services.openssh.settings.PermitRootLogin = "prohibit-password";
      users.users.root.openssh.authorizedKeys.keys = [ pubkey ];
    }
  ];
}
