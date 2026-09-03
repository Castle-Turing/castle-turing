# Task 0003 — Backup, then first install of the substrate

**Before starting:** read `CLAUDE.md`, `docs/vision.md`, and
`hosts/xps9370/README.md`. Prerequisite: PR #5 merged (the install
entrypoint is the private repo's flake). This task is interactive by
design — the human is at the XPS for the physical steps; ask them for
each one plainly and wait. Work on a branch; the brief, the captured
`hardware-configuration.nix`, and any runbook corrections ride it.

**Context.** The XPS 13 9370 currently runs an old Linux install with a
home partition worth keeping and Wi-Fi credentials worth carrying over.
The NVMe gets wiped entirely by disko. Nothing critical lives on this
machine, but the backup is the gate: **no install step may run until
Phase 1's verification passes.**

## Phase 1 — Backup

Runs on the XPS's current OS, via SSH from this Mac if reachable, else
with the human driving the XPS keyboard.

1. Inventory: sizes (`du -xsh`), then the irreplaceable classes —
   `~/.ssh`, `~/.gnupg`, documents/photos, browser profiles, `/etc`
   (small — take all of it, it includes
   `NetworkManager/system-connections`), and **local-only git work**:
   every repo under `~`, checked for uncommitted changes and unpushed
   branches; push or flag each.
2. Back up to the external drive with restic (encrypted, dedup); if
   restic can't be installed on the old OS, fall back to tar+zstd
   streamed to the drive. If the drive is too small, restic to S3
   instead (ask the human for bucket/credentials — which live in the
   shell environment, never in any repo).
3. **Verify before wipe:** `restic check`, then restore a real sample
   (an SSH key, a photo, one git repo) and open it. Report what was
   verified. The human explicitly confirms "wipe approved" — do not
   proceed on your own judgment.

## Phase 2 — Install

Runs from this Mac.

4. Create boot media: download the current NixOS graphical ISO, verify
   its checksum, write it to a USB stick the human plugs in. The
   stick's disk identifier is destructive-action territory on the Mac
   too: `diskutil list`, show the human, get explicit confirmation of
   the device before `dd`.
5. Human boots the XPS from the stick (F12 boot menu), joins Wi-Fi,
   sets `sudo passwd`, reads out the IP. **Dead-CMOS caveat:** the
   hardware clock may be wildly wrong, which breaks TLS during
   install — check `date` on the installer first and force an NTP sync
   before anything downloads.
6. Run nixos-anywhere from the private repo's flake (`#xps9370`), with
   `--generate-hardware-config` targeting the **public** checkout's
   `hosts/xps9370/hardware-configuration.nix` (machine facts are
   public; the private repo only holds the person). Use an input
   override so the install consumes the local public checkout with the
   fresh hardware config rather than the pinned GitHub rev.
7. First boot: human joins Wi-Fi once via `nmtui` (or restore the
   connection file from the backup — their call).
8. **Verify the loop that justifies everything:** a trivial change
   (e.g. add a package) committed to the appropriate repo,
   `nixos-rebuild switch --target-host` from the Mac, confirm it
   landed, then `nixos-rebuild --rollback` and confirm that landed
   too. The substrate claim — versioned, rollbackable, remotely
   operable — is only done when this round-trips.
9. Commit the hardware config; update the private repo's pin; fix
   every place the runbook diverged from reality — that drift is a
   first-class deliverable, not a footnote.

## Non-goals

sops-nix (still no credential in any repo), window manager, restoring
the old home onto the new system (the backup stays on the shelf;
things get pulled over as needed), CMOS battery.

## Acceptance

- Backup exists, `restic check` passes, a restored sample was opened,
  and the human approved the wipe in so many words.
- XPS boots NixOS from the flake-defined config; survives a
  power-cycle (the dead-CMOS fallback path actually exercised).
- The change-push-verify-rollback loop round-trips from a clean
  checkout on this Mac.
- `hardware-configuration.nix` committed publicly; private repo pin
  updated; runbook corrections merged.
- `nix flake check` green; `/code-review` run before the PR.

## Hints

The XPS's current OS may be SSH-reachable already — try that before
making the human type. If nixos-anywhere fails mid-install the machine
is still on the USB stick and nothing is lost; re-running is safe.
Keep the Wi-Fi psk out of every commit in both repos — it may
legitimately exist only in the backup and on the machine.
