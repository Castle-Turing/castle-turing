# Device fact only: the layout mechanism lives in modules/disk-layout.nix.
# QEMU attaches this harness's disk as virtio-blk, which Linux names
# /dev/vda — the VM analogue of hosts/xps9370's /dev/nvme0n1.
{ ... }:

{
  castle.disk.device = "/dev/vda";
}
