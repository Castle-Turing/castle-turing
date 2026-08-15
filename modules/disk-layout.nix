# modules/disk-layout.nix — the single-disk GPT layout every Castle Turing
# host currently uses: a 1G ESP plus a root partition filling the rest.
#
# Mechanism only: *which* disk this applies to is a hardware fact, supplied
# by the host module through castle.disk.device (e.g. "/dev/nvme0n1" on real
# hardware, "/dev/vda" for a virtio-disk VM). Consumers still need to import
# disko's own module (disko.nixosModules.disko) alongside this one — that's
# done once, in flake.nix's per-host wrappers, so host modules stay hardware
# facts only.
{ config, lib, ... }:

let
  cfg = config.castle.disk;
in
{
  options.castle.disk.device = lib.mkOption {
    type = lib.types.str;
    default = "";
    description = ''
      Block device path for this host's single-disk GPT layout (ESP +
      root). A hardware/virtualization fact — supplied by the host
      module, never by modules/. Example: "/dev/nvme0n1" on the XPS,
      "/dev/vda" for a virtio-disk QEMU VM.
    '';
  };

  config = {
    # Defaults to empty (rather than left undefined) so a host module that
    # forgets to set this fails here, with this message, instead of on
    # disko's generic "device is required" error.
    assertions = [
      {
        assertion = cfg.device != "";
        message = ''
          castle.disk.device is unset. Every host built on
          modules/disk-layout.nix must declare which block device this
          layout applies to — see hosts/xps9370/disko.nix for the
          shape.
        '';
      }
    ];

    disko.devices.disk.main = {
      type = "disk";
      device = cfg.device;
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
  };
}
