# Task 0003 — Findings from the first install

Written during the first real run of `hosts/xps9370`'s install path
(2026-08-14/15), for whoever runs this next — on this chassis or another.
These are drift/gaps discovered by doing the thing the runbook describes,
not yet all fixed. Some need a follow-up task; some are just runbook
corrections. Both kinds are recorded here per repo convention: spec and
findings ride the branch that produced them.

## 1. First-boot lockout (design gap — needs a task)

No user password exists in any config layer at first boot. This is a
chicken-and-egg problem:

- Console login is impossible without a password (or a passwordless-login
  config, which nothing here sets).
- SSH access requires the machine to be on the network.
- Joining the network (`nmtui`, since Wi-Fi is this chassis's only path)
  requires console login.

On this install, the loop was broken by dumb luck: nixos-anywhere's own
run happens *before* first boot, while the machine is still SSH-reachable
as the installer's `root`, so the actual `xps9370` config was never
exercised for first-boot login at all. The private repo's own
`resident.nix` needs to supply *some* way in — the two candidates:

- An `initialHashedPassword` (or `initialPassword` for a first pass) on
  the admin account. This is person-data — a secret, or secret-adjacent —
  so it belongs in the private repo, never here.
- A declarative Wi-Fi connection profile (private layer supplies the
  psk-bearing config; the public mechanism is just "read
  `networking.networkmanager.ensureProfiles` or equivalent from a private
  option"), so SSH works at first boot without ever touching the console.

Either closes the loop; the second also helps with finding #3 below.
Whichever direction is chosen, it needs a numbered task of its own — this
repo shouldn't ship a host module that strands its own admin.

## 2. "No Boot Device Found" after install (root cause TBD)

After the nixos-anywhere run reported success (see exit-status note
below) and the machine rebooted, the human pulled the USB stick per the
brief's normal first-boot sequence — and the XPS came up to a firmware
"No Boot Device Found" screen instead of NixOS. Investigation is in
progress (through `main`, over SSH once the installer is back up); this
section is a placeholder for the root cause, not a diagnosis. Known facts
worth carrying into that investigation, pulled from the install log so
they don't have to be re-derived:

- The install log shows `bootctl` copying the systemd-boot binary to
  *both* `/boot/EFI/systemd/systemd-bootx64.efi` and the UEFI fallback
  path `/boot/EFI/BOOT/BOOTX64.EFI`. The fallback file that
  `hosts/xps9370/default.nix` documents as the mechanism (see finding #5)
  does appear to have been written.
- Immediately before that, the log shows: `Not booted with EFI or
  running in a container, skipping EFI variable modifications.` This is
  nixos-anywhere's normal chroot-install behavior — `canTouchEfiVariables
  = true` never gets a chance to act during this kind of install, because
  the installing process has no access to `/sys/firmware/efi/efivars`
  from inside the target's chroot. In other words: **no NVRAM boot entry
  was ever created**, by design of how nixos-anywhere installs, not as a
  bug in this run. The system was always going to depend entirely on the
  firmware's own fallback-path scanning (or the ESP's ordering vs. the
  wiped-away Ubuntu partition table) working correctly on this chassis.
- Whether that's the actual cause (vs. e.g. an ESP that didn't get marked
  bootable, a GPT issue from disko, or something chassis-specific) is
  what the current investigation is for. Fill in above this line once
  known.

## 3. Installer ephemerality blocks agent-driven repeatability

Every boot of the stock NixOS graphical ISO starts from zero: Wi-Fi has
to be joined by hand (`nmtui`, since the installer has no saved
profiles), and SSH access requires fetching the admin's public key fresh
each time (`github:whharris.keys` or equivalent) since the live image
has no persistence. That's two rounds of human-at-the-keyboard work per
attempt, which is fine once but doesn't scale to "agent retries the
install after a failure" — the stated design goal of this whole
substrate.

Fix direction: a custom installer image, built as a flake output in this
repo (public mechanism), with the admin's public key baked in from a
private-layer option (private configuration) — same public-mechanism /
private-configuration split as everything else here (Principle 01). The
installer itself becomes a Castle Turing artifact instead of a stock ISO
downloaded fresh each time. Wi-Fi still can't be baked in generically
(no psk exists yet at ISO-build time for an unknown network), but the
SSH-key round-trip disappears entirely, and combined with finding #1's
declarative-Wi-Fi option, the nmtui step could disappear too for anyone
willing to pre-declare their home network's profile in the private
layer.

## 4. nixos-anywhere has no `--override-input`

Documented here because it cost real time to discover during this run:
`nixos-anywhere --help` exposes a generic `--option <key> <value>` (nix
store settings) but nothing for overriding a flake input on the command
line. Getting a private flake to consume a local, uncommitted public
checkout (rather than its pinned GitHub rev) has to happen a layer down,
in the *consuming* flake, before invoking nixos-anywhere at all:

```sh
# from the private repo:
nix flake lock --override-input castle-turing path:/abs/path/to/local/public/checkout
```

This rewrites that flake's `flake.lock` (locally, uncommitted) to point
the input at the local path. Revert it afterward
(`git checkout -- flake.lock`) — it's a transient override for one
install run, not the real pin bump. The real pin bump (to the actual
published rev, after `hardware-configuration.nix` is committed and
pushed publicly) is a separate, deliberate step per
`hosts/xps9370/README.md` step 3, not this override.

Runbook implication: `hosts/xps9370/README.md`'s install instructions
should say this explicitly rather than leaving it implied by "use an
input override."

## 5. Dead-CMOS reality and the ESP fallback path

This chassis's CMOS battery history means NVRAM boot entries can't be
trusted — a power loss forgets them, and the firmware's F12 one-time-boot
menu is the only reliably reachable path to the installer USB.
`hosts/xps9370/default.nix` already documents the intended mitigation for
the *installed system*: systemd-boot has no GRUB-style
`installAsRemovable` option, but `bootctl install` writes a copy to the
UEFI-standard fallback path (`EFI/BOOT/BOOTX64.EFI`) unconditionally, so
the machine should boot from the ESP even with an empty NVRAM boot entry
list. Whether that mitigation is actually sufficient on this hardware is
exactly what finding #2 is investigating — this finding is the design
intent it's being checked against, not a claim that it worked.

## 6. Sudo-over-SSH and `!` shell can't carry interactive passwords

Agent-workflow note, not a system config finding. Both Claude Code's `!`
shell and a plain non-interactive SSH exec can't answer a sudo password
prompt — there's no TTY for it, and piping a password through defeats
the point of it being a secret. Concretely on this task: reading
root-only paths (e.g. `/etc/NetworkManager/system-connections` for a
Wi-Fi psk) on a machine reachable only by SSH key required either a
workaround that avoids sudo entirely, or routing the step to the human
at the physical keyboard. Runbook implication: any step in a task brief
that needs `sudo` on a machine the operator doesn't have interactive
access to should be written as an explicit human-at-keyboard step, not
assumed to be scriptable — this applies beyond this one task.

## 7. Cosmetic HFS+ driver error on the backup drive (Phase 1)

Not a Phase 2 finding, but worth carrying forward since it'll resurface
the next time this backup drive is used from Linux. Linux's native
`hfsplus` kernel driver throws `ENODATA` ("No data available") from `ls`
when listing directories on the WD backup drive used for this task's
Phase 1 restic backup — looks like a failed extended-attribute
(Finder-info) read. It's cosmetic: verified harmless with a 10MB
write/rename/checksum round-trip (checksums matched throughout, `dmesg`
showed no I/O errors) before trusting the drive with the real backup.
Anyone who next mounts this drive on Linux and sees scary `ls` output
should know it's expected, not a sign of corruption.
