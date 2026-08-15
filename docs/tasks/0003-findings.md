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
each time (`github:resident.keys` or equivalent) since the live image
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
input override." **See finding #9 — this override has a sharp edge that
bit us later in this same task.**

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

**Redeploy result:** fixed. With the stale NVRAM entries removed and the
firmware back in UEFI mode, a redeploy via `nixos-install --root /mnt`
(nixos-anywhere `--phases install`, disk left mounted from the earlier
manual fix, not reformatted) produced a fallback file that actually
survived this time — verified directly on the ESP, not by trusting the
install log:

```
$ sha256sum /mnt/boot/EFI/BOOT/BOOTX64.EFI /mnt/boot/EFI/systemd/systemd-bootx64.efi
71b27b28854dee4663685a46b1f6c07761c373990581564b0ed2b6130591e2a2  BOOTX64.EFI
71b27b28854dee4663685a46b1f6c07761c373990581564b0ed2b6130591e2a2  systemd-bootx64.efi
```

This run also created proper NVRAM entries ("Linux Boot Manager",
"Fallback Linux Boot Manager") — unlike the first install, there was no
"skipping EFI variable modifications" line this time, and no stale
Ubuntu/rEFInd entries came back. The firmware's own generic
"UEFI: ...Partition 1" fallback entry (auto-managed by the firmware
itself, not by NixOS) also points at the same now-present file, so even
that path independently works now. Best available read: the original
failure was some combination of the stale competing NVRAM entries and
the Legacy-boot-mode detour confusing the firmware's own boot selection
during the *original* install/reboot sequence, rather than a single
clean root cause in `bootctl` itself — the exact mechanism by which the
first install's fallback copy failed to persist despite its log claim
remains not fully explained, but the fix and the reproduction-under-fixed-
conditions are both directly verified.

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

**Correction, added after further investigation:** the redeploy that
was supposed to ship this fix (the one referenced in finding #5's
"Redeploy result") did not actually ship it. See finding #9 — the fix
was correct, but the deploy that was meant to carry it consumed a stale
snapshot of the worktree that predated the fix's own commit. The
firmware config was correct in the repo the whole time; it just hadn't
reached the machine yet as of that redeploy.

## 9. `path:` flake-input overrides lock silently — a redeploy trap

The single most expensive mistake in this task, and worth a numbered
finding of its own because it's a general agentic-workflow hazard, not
a one-off slip.

Finding #4 documented using `nix flake lock --override-input castle-turing
path:/abs/path/to/local/checkout` in the private repo so nixos-anywhere
would build from a local, uncommitted public checkout instead of its
pinned GitHub rev. What wasn't obvious at the time: **that command
doesn't create a live pointer to the directory — it takes a content
snapshot (a `narHash`) of whatever is in that directory *at the moment
the lock command runs*, and writes that snapshot into `flake.lock`.**
Every subsequent `nix build`/`nix run` against that flake re-evaluates
against the *locked* snapshot, not the directory's current contents,
even though the directory keeps changing underneath it and even though
`path:` inputs are exactly the kind of thing that looks like it should
always be "live."

What happened here: the override lock was created once, early in this
task's Phase 2, before the `hardware.enableRedistributableFirmware`
commit existed. A redeploy was later run (to ship that exact firmware
fix) without re-running `nix flake lock --override-input` first. The
redeploy evaluated the *stale* pre-firmware-fix snapshot, built a
closure that never included `linux-firmware`, deployed it, and reported
success — because from Nix's perspective, nothing was wrong: it
faithfully built and deployed exactly the input it was told to use. The
symptom on the machine (`ath10k_pci` still couldn't find firmware after
the "fix" was "deployed") was the first sign anything was off, and it
took direct evidence from the machine's own console — not the deploy
log — to catch it. The tell that should have been caught sooner: the
redeploy finished in well under a minute, ludicrously fast for a build
that was supposed to newly pull in `linux-firmware` (a large package
this connection could never fetch and unpack that quickly). A near-instant
"successful" rebuild after a source change is itself a red flag worth
stopping on, not just a nice performance surprise.

**The fix, and the rule going forward:** re-run
`nix flake lock --override-input castle-turing path:<checkout>` in the
consuming (private) flake *every single time* the overridden public
checkout gets a new commit that needs to reach the deploy — there is no
way to make a `path:` override "just stay live" once it's been locked;
re-locking is the only refresh mechanism. Better still, before trusting
any redeploy that's supposed to carry a specific change: positively
assert the change is in the evaluated config or build closure ahead of
time, rather than inferring success from a clean exit code and a
plausible-looking log. Two cheap assertions that would have caught this
immediately, and are worth making a standing habit for this kind of
override-then-deploy flow:

```sh
# 1. The option evaluates the way you expect:
nix eval .#nixosConfigurations.xps9370.config.hardware.enableRedistributableFirmware
# → should print `true`

# 2. The package you expect is actually in the build closure — instantiate
#    the derivation (cheap, no building) and query its requisites:
nix-store --query --requisites \
  "$(nix eval --raw .#nixosConfigurations.xps9370.config.system.build.toplevel.drvPath)" \
  | grep linux-firmware
```

Runbook implication for `hosts/xps9370/README.md` and any future
install/redeploy tooling built on this pattern: treat "re-lock the
override, then assert the expected delta is present" as two mandatory
steps of the redeploy sequence, not optional diligence — an agent (or a
human moving fast) will otherwise trust a fast, clean, wrong deploy.

**Addendum:** the very next redeploy in this same task re-demonstrated
the hazard from the other side. After committing one more docs-only
change (this finding, ironically) *after* refreshing the override lock
but *before* the next `nix build`, that build failed outright with
`error: NAR hash mismatch in input 'path:...'` rather than silently
using either version. That's Nix noticing the on-disk directory no
longer matches what the lockfile recorded and refusing to guess — a
much better failure mode than finding #9's original silent-stale-build,
but it only triggers when the *invoking* command relies on the
already-written lockfile entry without re-passing
`--override-input` itself. The practical rule this confirms: treat
"refresh the override lock" as the *last* step before the build/deploy
command that consumes it, not an early one-time setup step — any commit
to the overridden checkout after refreshing, including a docs commit,
reopens the gap.

## 10. iPhone USB tethering isn't a working recovery path (yet)

Considered as a way to get the XPS on the network without Wi-Fi/firmware
at all — plug in an iPhone, tether over USB, get a wired-ish interface
with no `ath10k` dependency, SSH in over that. It doesn't work on the
config as it stands: iPhone USB tethering on Linux goes through
`usbmuxd`, which isn't installed (`services.usbmuxd` is off, and nothing
pulls it in transitively).

This is worth more than a one-line config toggle. The broader lesson
(feeds `docs/tasks/0005`, whatever that turns out to be): a machine
whose only network path is Wi-Fi has exactly one thing standing between
"reachable" and "needs a human physically present with a keyboard and a
USB stick" — this task hit that wall directly when the Wi-Fi firmware
gap took the network down after an otherwise-successful boot. A
deliberately-designed headless recovery path — `services.usbmuxd`
enabled as cheap insurance, and/or a wired-Ethernet-first policy, and/or
the declarative-Wi-Fi-profile direction from finding #1 — deserves to be
a first-class design decision for this host, not something reached for
ad hoc mid-incident.

## 11. The change → push → verify → rollback → verify loop (milestone 0's acceptance test)

This is the substrate claim task 0003 exists to check: versioned,
rollbackable, remotely operable. Run once the machine was up on its own
Wi-Fi with a working `resident@` login, from this Mac:

1. Added `pkgs.htop` to `environment.systemPackages` in
   `hosts/xps9370/default.nix` — a trivial, obviously-reversible
   one-line change. Committed on `first-install`.
2. Refreshed the private repo's `path:` override lock (finding #9's
   habit — this was its first real test on a genuine content change, not
   a docs-only one) and asserted `htop-3.5.2.drv` was actually present in
   the new closure's requisites *before* deploying.
3. `nixos-rebuild switch --flake .#xps9370 --target-host root@192.168.2.54
   --build-host root@192.168.2.54` (building on the XPS itself — this
   Mac is aarch64-darwin and cannot build the x86_64-linux target
   locally). Landed as generation 3. Verified over SSH: `which htop`
   resolved, `htop --version` printed `3.5.2`.
4. Rolled back. First attempt
   (`nixos-rebuild switch --rollback --target-host root@192.168.2.54`,
   *without* `--flake`) failed outright — this particular
   `nixos-rebuild` (the newer Python/"-ng" implementation, going by its
   `--elevate`/`--json`/`--ask-elevate-password` flags) falls back to a
   legacy `NIX_PATH`-based config lookup when `--rollback` is given
   without `--flake`, and errors because there's no `nixos-config` in
   `$NIX_PATH` on a flake-only setup like this one. **`--flake .#xps9370`
   is required on the rollback invocation too, not just the forward
   switch** — easy to drop by mimicking the brief's shorthand
   (`nixos-rebuild --rollback --target-host ...`) too literally. Retried
   with `nixos-rebuild switch --rollback --flake .#xps9370
   --target-host root@192.168.2.54`: exit 0.
5. Verified the rollback landed, not just that the command exited clean:
   `readlink /nix/var/nix/profiles/system` → `system-2-link`;
   `nixos-rebuild list-generations` shows generation 2 marked Current,
   generation 3 (the htop change) present but not current; `which htop`
   → not found.

Runbook implication for `hosts/xps9370/README.md`'s rebuild section:
the rollback example should include `--flake .#xps9370` explicitly,
not just `--target-host`, to avoid this exact trap.

(The `htop` line itself was reverted out of `hosts/xps9370/default.nix`
after this verification — it was always a throwaway test vehicle, and
the machine's own current generation already doesn't have it; the
evidence lives here, not in the committed config.)
