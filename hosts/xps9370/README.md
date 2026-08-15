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

Task `docs/tasks/0003-findings.md` is the detailed shakedown log for
everything below — read it if a step here doesn't match reality on your
hardware; several things that looked right on paper weren't, on this
chassis.

1. Boot the target machine from a NixOS installer USB (the graphical ISO
   is easiest for Wi-Fi). In a terminal on the target: connect to Wi-Fi,
   set a root password with `sudo passwd`, and note the IP from `ip a`.
   **Check `date` before doing anything else.** A dead or wrong hardware
   clock breaks TLS for every download the install needs; force an NTP
   sync (or set the date by hand) first if it's off.
2. The installable configuration lives in your private flake, not here —
   this repo's `nixosConfigurations.example` is a CI stand-in with a
   placeholder resident. This first install still runs against whatever
   `hardware-configuration.nix` is currently committed in this directory
   (fine even if it's still the placeholder — the `dell-xps-13-9370`
   nixos-hardware module already carries this chassis's known quirks);
   the real one is captured as a *side effect* of this same command for
   you to commit afterward, not consumed by it.

   If you're working from a local checkout of this repo that isn't the
   exact rev your private flake has pinned (a worktree, an
   uncommitted fix, anything not yet pushed), point the private flake's
   `castle-turing` input at it first — **this is a one-shot snapshot, not
   a live link, and it must be redone after every commit you want the
   build to actually pick up** (see finding #9 in the findings doc if
   that sentence doesn't sound alarming enough on its own):

   ```sh
   # from your private flake's directory:
   nix flake lock --override-input castle-turing path:/abs/path/to/your/checkout
   ```

   Then, from that same private flake directory, with Nix installed:

   ```sh
   nix run github:nix-community/nixos-anywhere -- \
     --flake .#xps9370 \
     --generate-hardware-config nixos-generate-config \
       /abs/path/to/your/checkout/hosts/xps9370/hardware-configuration.nix \
     root@<installer-ip>
   ```

   (Point `--generate-hardware-config`'s path at wherever your public
   checkout actually lives — it doesn't have to be a sibling directory
   named `castle-turing`, just a real path on disk.) This partitions the
   disk per `disko.nix`, installs, and by default reboots automatically.

   **Before trusting a reboot, verify the boot actually landed** — don't
   just watch the log. `bootctl install`'s log output claiming it wrote
   the UEFI fallback file (`EFI/BOOT/BOOTX64.EFI`) is not proof that it
   did; check the mounted ESP directly (`ls`/`sha256sum` against
   `EFI/systemd/systemd-bootx64.efi`) before pulling the USB stick. This
   bit us for real on this chassis's first install — see findings #2 and
   #5. If you need to redeploy onto a disk that already has real data on
   it (not a from-scratch wipe), do **not** use the default phases —
   `--phases disko,install --disko-mode mount` mounts the existing,
   already-partitioned filesystems without touching their contents;
   plain `--phases install` if something has already mounted the target
   at `/mnt` for you.
3. Commit the freshly generated `hardware-configuration.nix` in this
   directory, bump your private flake's pin of this repo to the real
   published rev (replacing the local-path override from step 2 — that
   override was only ever a one-shot local build aid, never meant to be
   committed), and do one rebuild (below) so the real hardware facts
   take effect — the install itself ran without them.
4. On first boot, join Wi-Fi once with `nmtui`; the credential stays on
   the machine, not in this repo. (As of this writing there's no
   password on the admin account at first boot and no declarative
   Wi-Fi profile either, which is its own chicken-and-egg problem — see
   finding #1. Until that's fixed, plan for a human at the physical
   keyboard for this step.)

## Rebuilding after changes

From a machine with Nix and your private flake checked out:

```sh
nixos-rebuild switch --flake .#xps9370 --target-host root@<host-ip> --build-host root@<host-ip>
```

`--build-host` matters if your workstation can't build `x86_64-linux`
itself (e.g. an Apple Silicon Mac) — it builds the closure on the target
instead of trying (and failing) to build it locally.

(run from the private flake's directory — the public repo has no
installable configuration), or run the same command locally on the host
itself (omit `--target-host`/`--build-host`).
Every rebuild is a new boot-menu generation; rollback is selecting the
previous one, either from the boot menu or with:

```sh
nixos-rebuild switch --rollback --flake .#xps9370 --target-host root@<host-ip>
```

`--flake .#xps9370` is required on the rollback invocation too, not just
the forward switch — dropping it sends at least one `nixos-rebuild`
implementation down a legacy non-flake config path that doesn't exist
here, and it fails outright rather than silently doing the wrong thing
(small mercy). See finding #11 for the exact failure if you hit it.
