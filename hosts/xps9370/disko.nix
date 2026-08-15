# Device fact only, for the XPS 13 9370's single NVMe drive. The layout
# itself (GPT, 1G ESP, root filling the rest) is the shared mechanism in
# modules/disk-layout.nix — this file exists so that mechanism lives in
# modules/ and only the device path lives in hosts/, per docs/tasks/0004.
# Applied (destructively) by nixos-anywhere at install time; inert during
# normal rebuilds.
{ ... }:

{
  castle.disk.device = "/dev/nvme0n1";
}
