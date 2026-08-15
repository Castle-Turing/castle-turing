# hosts/vm-test — QEMU/OVMF test double

Not a real host. This module exists so the install mechanism can be
exercised end to end, unattended, in CI — see
[`docs/tasks/0004-install-test-harness.md`](../../docs/tasks/0004-install-test-harness.md)
and [`test/vm-install/`](../../test/vm-install/) for the harness that
builds and boots it.

Contents:

- `default.nix` — the host module: boot loader, virtio kernel modules,
  DHCP networking. Machine facts only, same shape as `hosts/xps9370/`;
  the admin identity comes from the harness, generated fresh per run and
  never committed.
- `disko.nix` — the device fact (`/dev/vda`) for the shared disk layout
  in `modules/disk-layout.nix`.

Consumed through `flake.nix`'s `nixosModules.host-vm-test` export, which
also binds disko. `flake.nix`'s `nixosConfigurations.vm-test-example`
evaluates this host with a placeholder resident, the same role
`nixosConfigurations.example` plays for `hosts/xps9370` — both exist so
`nix flake check` proves the mechanism evaluates without either host
naming a real person.
