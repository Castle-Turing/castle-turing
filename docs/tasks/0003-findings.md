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

## 2. "No Boot Device Found" after install (root cause confirmed)

After the nixos-anywhere run reported success and the machine rebooted,
the human pulled the USB stick per the brief's normal first-boot
sequence — and the XPS came up to a firmware "No Boot Device Found"
screen instead of NixOS. Confirmed by direct inspection of the deployed
ESP (over SSH, from the reboot-into-installer path): **the fallback file
`EFI/BOOT/BOOTX64.EFI` was not on the disk**, despite the install log's
own "Copied ... to /boot/EFI/BOOT/BOOTX64.EFI" line claiming it had been
written. The log line and the on-disk reality disagreed — the log is not
trustworthy evidence of what actually landed on the ESP for this kind of
chroot install; the two facts recorded in the previous version of this
entry (the "Copied" log line, and `canTouchEfiVariables` being
graceful-skipped inside the chroot) turned out to be a red herring for
the "Copied" half — the file genuinely didn't survive, for reasons not
fully root-caused beyond "don't trust the log, verify the ESP directly."

Two more contributing/compounding factors, found during the same
inspection:

- The firmware also carried **stale NVRAM boot entries** from the wiped
  Ubuntu install (Ubuntu's own boot entry, and a leftover rEFInd entry) —
  removed as part of the live fix.
- Separately, the boot attempt that produced "No Boot Device Found" was
  compounded by the firmware being switched to **Legacy boot mode**
  (needed transiently for the USB stick) instead of UEFI — human error at
  the keyboard, not a config bug, but it stacked with the missing
  fallback file to produce a worse symptom than either alone. Confirmed
  back in UEFI mode; Secure Boot was already off and uninvolved.
- The CMOS battery itself was replaced during this task (separately from
  the software fix), removing the underlying reason NVRAM entries were
  untrustworthy in the first place — see finding #5 for why the config
  still treats NVRAM as unreliable regardless.

**Live fix applied** (through `main`, over SSH, on the booted-from-USB
installer with the target's filesystems mounted): copied
`systemd-bootx64.efi` to `EFI/BOOT/BOOTX64.EFI` by hand, removed the
stale Ubuntu/rEFInd NVRAM entries. Machine then booted NixOS
successfully from the internal disk. That direct fix is necessarily
non-declarative (a hand-edit of a live ESP); task 0003's redeploy step
re-runs `nixos-install` against the same (already-partitioned, not
reformatted) disk to confirm the fallback file survives a real
`bootctl install` pass this time, now that the stale NVRAM confusion and
Legacy-mode issue are out of the picture. Result of that redeploy: see
finding #5.

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

This chassis's CMOS battery history meant NVRAM boot entries couldn't be
trusted — a power loss forgets them, and the firmware's F12 one-time-boot
menu is the only reliably reachable path to the installer USB. The
battery was replaced during this task, but `hosts/xps9370/default.nix`
still treats NVRAM as unreliable on principle — a working battery today
isn't a guarantee, and the config has no way to detect a future failure.

`hosts/xps9370/default.nix` documents the intended mitigation for the
*installed system*: `bootctl install` is supposed to write a copy of
systemd-boot to the UEFI-standard fallback path (`EFI/BOOT/BOOTX64.EFI`)
unconditionally, so the machine boots from the ESP even with an empty
NVRAM boot entry list. Verified (per this flake's pinned nixpkgs source):
systemd-boot genuinely has no GRUB-style `installAsRemovable` option to
configure — there's nothing to turn on, the fallback write is supposed
to just happen as part of `bootctl install`.

On the *first* install it didn't — see finding #2. After main's live fix
(manual copy + stale NVRAM cleanup) got the machine booting once, task
0003's redeploy re-ran `nixos-install` against the same disk (not
reformatted) specifically to check whether a real `bootctl install` pass
reproduces the fallback file on its own now that the confounding factors
(stale NVRAM entries, Legacy boot mode) are gone:

**Redeploy result:** [fill in after the redeploy in this session —
whether `EFI/BOOT/BOOTX64.EFI` was present on the ESP immediately after
`nixos-install` completed, verified before reboot.]

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

## 8. Missing Wi-Fi firmware (root cause confirmed, fixed)

Separate from the boot failure: once the machine *did* boot NixOS
successfully, it had no working Wi-Fi. `journalctl` on the installed
system showed:

```
ath10k_pci: could not fetch firmware files (-2)
```

The chassis's Killer/Atheros wireless card needs a redistributable
firmware blob that NixOS does not ship by default, and the
`dell-xps-13-9370` module from nixos-hardware does not turn this on for
you (it covers the chassis's other quirks, not this one). Fixed by
adding `hardware.enableRedistributableFirmware = true;` to
`hosts/xps9370/default.nix` — a hardware fact about this chassis, so it
belongs in the host module rather than `modules/base`. This is now part
of the config being redeployed alongside the boot-loader fix; the
provisioned Wi-Fi connection profile itself (interface `wlp2s0`, no
`permissions=` restriction) was confirmed fine independently — it was
purely a missing-firmware problem, not a bad connection file.
