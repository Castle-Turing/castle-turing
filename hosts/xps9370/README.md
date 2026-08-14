# hosts/xps9370 — Dell XPS 13 9370 (reference host)

The project machine: 8th-gen i7, 16GB, touchscreen. Covered by the
`dell-xps-13-9370` module in nixos-hardware.

Contents:

- `default.nix` — the host module: boot loader, machine quirks. Machine
  facts only; the admin identity comes from the private layer
  (`docs/private-layer.md`).
- `disko.nix` — declarative disk layout, applied destructively at
  install time only.
- `hardware-configuration.nix` — generated in place during install (see
  below); a placeholder until then.

This directory is consumed through flake.nix's `nixosModules.host-xps9370`
export, which also binds the matching nixos-hardware and disko modules.
Nothing here may be imported by `modules/`. To adopt Castle Turing on
different hardware, copy this directory's shape as `hosts/<yourmachine>/`
and swap in your nixos-hardware module and disk device — the admin
identity is not part of a host and lives in your private layer.

## Installing (wipes the target disk)

1. Boot the target machine from a NixOS installer USB (the graphical ISO
   is easiest for Wi-Fi). In a terminal on the target: connect to Wi-Fi,
   set a root password with `sudo passwd`, and note the IP from `ip a`.
2. The installable configuration lives in your private flake, not here —
   this repo's `nixosConfigurations.example` is a CI stand-in with a
   placeholder resident. This first install still runs against the
   placeholder `hardware-configuration.nix` committed in this directory
   (fine — the `dell-xps-13-9370` nixos-hardware module already carries
   this chassis's known quirks); the real one is captured as a *side
   effect* of this same command for you to commit afterward, not
   consumed by it. From a machine with Nix and your private flake
   checked out (with this repo checked out as a sibling, so the
   generated file lands in the public tree where machine facts belong):

   ```sh
   nix run github:nix-community/nixos-anywhere -- \
     --flake .#xps9370 \
     --generate-hardware-config nixos-generate-config \
       ../castle-turing/hosts/xps9370/hardware-configuration.nix \
     root@<installer-ip>
   ```

   This partitions the disk per `disko.nix`, installs, and reboots.
3. Commit the freshly generated `hardware-configuration.nix` in this
   directory, bump your private flake's pin of this repo, and do one
   rebuild (below) so the real hardware facts take effect — the install
   itself ran without them.
4. On first boot, join Wi-Fi once with `nmtui`; the credential stays on
   the machine, not in this repo.

## Rebuilding after changes

From a machine with Nix and your private flake checked out:

```sh
nixos-rebuild switch --flake .#xps9370 --target-host root@<host-ip>
```

(run from the private flake's directory — the public repo has no
installable configuration), or run the same command locally on the host
itself (omit `--target-host`).
Every rebuild is a new boot-menu generation; rollback is selecting the
previous one.
