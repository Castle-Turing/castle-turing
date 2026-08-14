# hosts/xps9370 — Dell XPS 13 9370 (reference host)

The project machine: 8th-gen i7, 16GB, touchscreen. Covered by the
`dell-xps-13-9370` module in nixos-hardware.

Contents:

- `default.nix` — the host module: hardware imports, boot loader, the
  admin identity (temporarily, until the private layer exists).
- `disko.nix` — declarative disk layout, applied destructively at
  install time only.
- `hardware-configuration.nix` — generated in place during install (see
  below); a placeholder until then.

Nothing here may be imported by `modules/`. To adopt Castle Turing on
different hardware, copy this directory's shape as `hosts/<yourmachine>/`
and swap in your nixos-hardware module, disk device, and admin identity —
that is the only hardware-specific work required.

## Installing (wipes the target disk)

1. Boot the target machine from a NixOS installer USB (the graphical ISO
   is easiest for Wi-Fi). In a terminal on the target: connect to Wi-Fi,
   set a root password with `sudo passwd`, and note the IP from `ip a`.
2. From any machine with Nix and this repo checked out:

   ```sh
   nix run github:nix-community/nixos-anywhere -- \
     --flake .#xps9370 \
     --generate-hardware-config nixos-generate-config ./hosts/xps9370/hardware-configuration.nix \
     root@<installer-ip>
   ```

   This partitions the disk per `disko.nix`, writes the real
   `hardware-configuration.nix` into this directory (commit it), installs,
   and reboots.
3. On first boot, join Wi-Fi once with `nmtui`; the credential stays on
   the machine, not in this repo.

## Rebuilding after changes

From a machine with Nix:

```sh
nixos-rebuild switch --flake .#xps9370 --target-host root@<host-ip>
```

or run the same command locally on the host itself (omit `--target-host`).
Every rebuild is a new boot-menu generation; rollback is selecting the
previous one.
