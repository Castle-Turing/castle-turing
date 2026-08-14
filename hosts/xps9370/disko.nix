# Declarative disk layout for the XPS 13 9370's single NVMe drive.
# Applied (destructively) by nixos-anywhere at install time; inert during
# normal rebuilds.
#
# The disko.devices.* options used below are defined by disko's own NixOS
# module (disko.nixosModules.disko), not by this file — it's pulled in as
# a sibling top-level module in flake.nix's `modules` list.
{ ... }:

{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/nvme0n1";
    content = {
      type = "gpt";
      partitions = {
        esp = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
