# test/vm-install — the install-loop test harness

What `docs/tasks/0004-install-test-harness.md` asked for: a way to
exercise the real install mechanism (`hosts/vm-test/` + `modules/base` +
`modules/disk-layout.nix` + `modules/installer.nix`) end to end,
unattended, so a regression like task 0003's physical-shakedown findings
goes red in CI instead of costing a human a USB round-trip.
`docs/tasks/0006-installer-image.md` later pointed this same harness at
the real installer image (`flake.nixosModules.installer`) instead of a
one-off test fixture, and added the "installer itself is SSH-reachable
unattended" assertion below.

Most assertions here go over the network (SSH by key), because that's
what CI can drive unattended — nobody, human or script, is watching the
QEMU VM's virtual console interactively in this harness. One exception
(`docs/tasks/0016`): phase 1 also greps the captured serial log for the
"connected" banner's hostname and `ssh root@` lines, because SSH
reachability alone doesn't prove that banner ever rendered — that gap
is exactly how `have_network()`'s connected branch went unreachable on
every boot, undetected, until a human read a real serial console by eye
(`docs/tasks/0016-installer-network-predicate.md`). That one check
stays narrow on purpose: a byte-level assertion on two specific lines,
not a parse of the console UX in general.

What this harness still does **not** cover: the interactive parts of
`modules/installer.nix`'s console UX — the auto-`nmtui`-on-no-connectivity
prompt, the VT escape hatch, and anything that needs a human actually
watching the screen update live. QEMU's `-nic user` (slirp) always
brings up its own DHCP server, so the VM is *never* without a network in
CI — which is exactly why only the connected path gets exercised here:
the no-network banner and diagnostic (`docs/tasks/0016` defect 3) have
no condition in this harness that would ever trigger them. That
interactive behavior needs a human's eyes at least once, on real
hardware, to confirm it reads the way it's supposed to; see
`hosts/xps9370/README.md`.

## What it asserts

Run in order, against one QEMU/OVMF VM:

1. The installer image itself — the real public mechanism,
   `flake.nixosModules.installer` (`docs/tasks/0006-installer-image.md`)
   — boots and comes up SSH-reachable by key **with zero console
   interaction**: no `nmtui`, no fetching a key at the console. This is
   the regression test for installer ephemerality
   (`docs/tasks/0003-findings.md` finding #3). The same boot also
   confirms `statusScript`'s connected banner (hostname + `ssh root@`
   line) actually reached the serial console — the regression test for
   `have_network()`'s connected branch having been unreachable on every
   boot (`docs/tasks/0016-installer-network-predicate.md`).
2. `nixos-anywhere` installs the real target (disko partitions the
   virtio disk, `nixos-install` runs) against that booted installer.
3. The VM reboots from its own disk with the installer media detached,
   and SSH comes up as the admin, by key, **with zero console
   interaction** — the regression test for the first-boot lockout
   (`docs/tasks/0003-findings.md` finding #1).
3b. On that same boot (`docs/tasks/0005-dogfooding-desktop.md`):
   `graphical.target` is reached, and Sway's IPC socket appears and
   answers `swaymsg -t get_version`. A GUI can't be driven headlessly,
   but this much can be checked with no human and no display —
   `vm-test-system.nix` imports the published `modules/desktop` and
   layers a test-only auto-login on top (never present in the real
   module — see that file's header comment) so Sway starts with, again,
   zero console interaction.
3c. Still that same boot (`docs/tasks/0031-secrets-tooling.md`): the age
   key `run.sh` generated *before* the install is on the installed disk
   at `/var/lib/sops-nix/key.txt`, mode `600`, owned by `root`; and a
   secret encrypted to that key before the machine existed has
   decrypted itself into `/run/secrets/harness-fixture`, byte-for-byte
   equal to the value `run.sh` encrypted. That is the whole secrets
   pipeline with nobody at a keyboard: encrypt, plant the key with
   `nixos-anywhere --extra-files`, decrypt at the installed system's
   own first activation. The key, the ciphertext and the marker value
   inside it are generated per run and never committed — the same
   convention as the throwaway admin SSH keypair, for the same reason.
   What this deliberately does **not** cover is the Wi-Fi half of that
   task: QEMU's `-nic user` is wired-Ethernet-equivalent, so there is
   no radio here to join a network with, and
   `networking.networkmanager.ensureProfiles` (nixpkgs's own module,
   not code this project wrote) goes untested. The half this project
   *did* write — getting a real decrypted file onto a real disk
   unattended — is the half asserted here.
3d. Still that same boot (`docs/tasks/0032-password-hash.md`): the
   `harness` account's password field in `/etc/shadow` is
   byte-for-byte equal to a *second* fixture value `run.sh` encrypted
   before the install started, delivered through
   `castle.admin.hashedPasswordFile` pointed at a sops-nix secret
   carrying `neededForUsers = true`.

   This is a strictly stronger claim than 3c, and the distinction is
   the entire reason it is a separate assertion. 3c proves a secret
   decrypted at *some* point during activation — all an ordinary
   `sops.secrets` entry promises. 3d proves one decrypted *before the
   admin account was created*, the ordering `neededForUsers` and
   sops-nix's own `users.deps = [ "setupSecretsForUsers" ]` exist to
   guarantee. Nothing about `/run` can be inspected afterwards to tell
   the two apart: a secret that decrypted a moment too late would sit
   there looking perfectly healthy while
   `update-users-groups.pl` had already written a locked (`"!"`)
   shadow entry — and, because that write only ever happens at *first*
   account creation, no later rebuild would repair it. That failure
   mode is a machine nobody can log into, which is why this task
   proves it on a disposable VM rather than on a resident's laptop.

   The fixture value is deliberately **not** shaped like a crypt hash
   (no `$6$`, no MCF structure). Nothing here authenticates with it —
   the harness auto-logs in and never types a password anywhere — so
   an opaque marker tests exactly what is under test, the survival of
   specific bytes through the pipeline, while making it impossible to
   mistake for a credential. There is no plaintext password anywhere
   in this process to have produced it.
4. The VM survives a power-cycle: a hard stop (`kill -9` the QEMU
   process — no clean shutdown) followed by a restart with its NVRAM
   intact.
5. The VM survives an NVRAM wipe: its OVMF vars file is replaced with a
   pristine (blank) one and it's restarted again, forcing the firmware
   down the UEFI-standard fallback path `EFI/BOOT/BOOTX64.EFI` instead
   of any NVRAM boot entry. This is the dead-CMOS lesson from finding
   #2/#5 — a missing or non-surviving fallback file is exactly the bug
   that produced "No Boot Device Found" on the real XPS.

The `kill -9` in assertions 4 and 5 is deliberate, not a shortcut: an
ungraceful stop is the actual failure mode a power-cycle test exists to
cover, so `run.sh` never unmounts or syncs before those two. The one
exception is the phase 1 → phase 2 transition (detaching the installer
after a successful install) — that one *does* explicitly `umount` and
`sync` first, because it stands in for a normal reboot after install,
not a power loss, and phases 2-4 need the install's own writes (notably
`bootctl install`'s vfat ESP writes) to have actually landed on disk
before they can mean anything.

Each step is a hard assertion: the script exits non-zero the moment one
fails, and says which assertion failed and where its log is.

## Why a custom harness and not `nixos-anywhere --vm-test`

`nixos-anywhere --vm-test` builds the system and disko script and
partitions a scratch disk inside a VM to validate the disk
configuration — useful, but one-shot: it doesn't leave a persistently
bootable VM to test reboot, power-cycle, or NVRAM-fallback behavior
against, and it doesn't drive `nixos-anywhere`'s real remote-install
path (SSH into a running installer, over a network) the way an actual
deploy does. Since three of `docs/tasks/0004-install-test-harness.md`'s
four originally required assertions are specifically about what happens
on later boots, `--vm-test` can't express them; this harness drives
QEMU directly instead, and still uses
`nixos-anywhere` itself (via `--store-paths`) for the actual install
step, so the install path under test is the same one a real machine
gets.

## Running it locally

Needs: a KVM-capable **x86_64** Linux box (same architecture as the
reference host, `hosts/xps9370`) with `/dev/kvm` accessible, and Nix
with flakes enabled. If `/dev/kvm` isn't accessible, `run.sh` falls back
to TCG (software) emulation automatically rather than refusing to run —
dramatically slower, but a working answer for a developer's machine.
That fallback is deliberately *not* mirrored in CI
(`.github/workflows/vm-install-test.yml`): there, a missing `/dev/kvm`
means the runner itself is broken, TCG would blow the job's time
budget, and the workflow fails the KVM-setup step outright instead of
letting `run.sh` quietly take the slow path.

```sh
test/vm-install/run.sh
```

It builds its own tooling (qemu, OVMF, nixos-anywhere, openssh, age,
sops) from this flake's pinned nixpkgs — nothing needs to be
preinstalled beyond Nix itself. A throwaway admin SSH keypair, a
throwaway age keypair, and a sops-encrypted fixture file are all
generated fresh per run in a temp directory, and none of them ever
touches this repo.

Useful environment variables:

- `CASTLE_HARNESS_LOG_DIR` — where serial console logs and the
  `nixos-anywhere` transcript are written. Defaults to a temp directory
  (printed at the end of the run, or in the `FAIL:` line if a phase
  fails).
- `CASTLE_HARNESS_SSH_PORT` — host-forwarded SSH port (default 10222).
- `CASTLE_HARNESS_BOOT_TIMEOUT` — seconds to wait for SSH on each boot
  (default 180).
- `CASTLE_HARNESS_CONNECTED_BANNER_TIMEOUT` — seconds to wait for the
  installer's connected banner on the serial console in phase 1 (default
  340). Deliberately not tied to `CASTLE_HARNESS_BOOT_TIMEOUT`: the
  banner can be delayed by up to a fixed 300s if the installer's own
  DHCP head start loses the race and it falls into `nmtui`
  (`docs/tasks/0016`) — see the constant's own comment in `run.sh`.

## Reading a failure

Each phase writes two logs under the log directory:
`<phase>.serial.log` (the VM's console — kernel/systemd/boot-loader
output, the most useful one) and `<phase>.qemu.log` (QEMU's own
stderr/stdout, useful if QEMU itself failed to start). Phase 1 also
writes `phase1-nixos-anywhere.log`, the full `nixos-anywhere`
transcript.

Phase names map directly to the assertions above (`phase1-installer`
covers both assertion 1, the installer's own SSH reachability, and
assertion 2, the install itself — they share one boot of the installer
image):

- `phase1-installer` — either the installer image never came up
  SSH-reachable (check `phase1-installer.serial.log` — this is the
  finding #3 regression); or SSH came up but the connected banner never
  reached the serial log (also check `phase1-installer.serial.log` —
  this is the `docs/tasks/0016` regression, `have_network()` gone wrong
  again); or it came up fine but `nixos-anywhere` itself failed
  (disko/format/copy/`nixos-install` error) — check
  `phase1-nixos-anywhere.log` first in that case.
- `phase2-first-boot` — the freshly installed disk didn't boot on its
  own, or SSH as the admin needed something console/Wi-Fi/password
  shaped it shouldn't. Check `phase2-first-boot.serial.log` for where
  boot stalled.
- `phase2b` (no separate boot, same VM as phase 2) — either
  `graphical.target` never became active (check
  `phase2-first-boot.serial.log` for where greetd/sway stalled), or the
  IPC socket didn't appear or didn't answer `swaymsg` (check
  `phase2b-sway-ipc.log`). The latter is most often a Sway/wlroots
  startup failure — `WLR_BACKENDS=headless` should make that
  unconditional in a display-less VM, so a failure here usually means
  something changed in how `modules/desktop` or the test-only auto-login
  override (`vm-test-system.nix`) starts the session, not a real display
  problem.
- `phase2c` (no separate boot either, same VM as phase 2) — the secrets
  pipeline. Three distinguishable failures, in the order the script
  checks them: the age key isn't on the disk at all (`--extra-files`
  didn't copy it, or copied it somewhere else — check
  `phase1-nixos-anywhere.log` for its "Copying extra files" step); the
  key is there with the wrong mode or owner (the staging in `run.sh`,
  or `--extra-files`'s own permission handling, changed); or the key is
  fine but `/run/secrets/harness-fixture` is missing or holds something
  else. That last one is a decryption failure — look in
  `phase2-first-boot.serial.log` for `sops-install-secrets` (it runs
  from an activation script on this nixpkgs pin, so its error lands in
  the boot's console output), and at `phase2c-secret-actual.od` for the
  byte dump if a file did appear with the wrong contents.
- `phase2d` (no separate boot either, same VM as phase 2) — the admin
  password reached `/etc/shadow`. Read the byte dumps first
  (`phase2d-shadow-expected.od` and `phase2d-shadow-actual.od`), because
  the actual value tells you which failure it is:
  - **A single `!`** — the secret had not decrypted when
    `update-users-groups.pl` created the account. This is the ordering
    guarantee breaking, and it is the failure this phase exists for:
    either `neededForUsers` stopped putting
    `setupSecretsForUsers` ahead of the `users` activation script, or
    it decrypted and failed. Look for `sops-install-secrets` in
    `phase1-nixos-anywhere.log` (the account is first created inside
    `nixos-enter` during `nixos-install`, so that transcript, not the
    first-boot serial log, is usually where the real error is) and then
    in `phase2-first-boot.serial.log`.
  - **The literal path string** — something wired the *hash* where a
    *path* belongs, the exact mistake
    `docs/tasks/0032-password-hash.md` §2 refuses to let
    `mkRenamedOptionModule` make.
  - **Anything else** — a value did arrive, but not the one this run
    encrypted; treat it like a phase 2c decryption mismatch.
  - **The read itself failing** (`phase2d-shadow.log`) — the account
    is missing from `/etc/shadow` entirely, which is a different and
    larger problem than a password one.
- `phase3-power-cycle` — the system didn't come back cleanly after a
  hard stop (a filesystem that won't mount without an interactive fsck
  prompt is the classic cause — check the serial log for an `fsck`
  or emergency-shell line).
- `phase4-nvram-wipe` — the ESP fallback file
  (`EFI/BOOT/BOOTX64.EFI`) is missing or broken. This is the exact bug
  class task 0003 found by hand; see
  `docs/tasks/0003-findings.md` finding #2/#5 for the full story and
  `hosts/xps9370/default.nix` / `hosts/vm-test/default.nix` for the
  `boot.loader.efi.canTouchEfiVariables` mitigation this phase is
  guarding.

## Files here

- `run.sh` — the harness itself.
- `installer.nix` — instantiates the real `flake.nixosModules.installer`
  (`docs/tasks/0006-installer-image.md`) with the run's throwaway admin
  key, plus one test-only tweak (a serial console) so the ISO `run.sh`
  boots as its QEMU "target" is the same artifact a real install would
  use, not a parallel stand-in.
- `vm-test-system.nix` — the real `hosts/vm-test` `nixosConfiguration`
  under test (`modules/base` + `modules/desktop` + `modules/secrets.nix`),
  with the run's throwaway admin key, the run's throwaway encrypted
  secrets file, two fixture secrets declared against it (one ordinary,
  one `neededForUsers` feeding `castle.admin.hashedPasswordFile`), and a
  test-only Sway auto-login override.
- `pkgs.nix` — this flake's own pinned nixpkgs, so harness tooling
  (qemu, OVMF, nixos-anywhere, age, sops) stays on the revision the
  mechanism is tested against.

The fixture-generation logic itself lives in `run.sh`, near the
throwaway-admin-key block it deliberately mirrors: `age-keygen` writes a
keypair into the run's temp directory, `sops --encrypt --age <that key's
recipient>` encrypts two known marker values into
`harness-secrets.yaml`, and the private key is staged into an
`--extra-files` directory as `var/lib/sops-nix/key.txt` (mode 600).
The markers reach `sops` on a pipe rather than through a temp file, and
the key and ciphertext are deleted with the workdir when the run
succeeds. It does **not** follow that the plaintext stays out of files,
and an earlier version of this paragraph said it did. Phase 2c writes
`FIXTURE_SECRET` to `$WORKDIR/expected-secret` and
`$WORKDIR/actual-secret` so `cmp` can compare bytes rather than shell
strings, and on a mismatch dumps it to `phase2c-secret-actual.od` in the
log directory — which CI uploads as an artifact with `if: always()`, so
a red run publishes it. Phase 2d does the same for
`FIXTURE_PASSWORD_HASH` (`expected-shadow`/`actual-shadow`, and
`phase2d-shadow-expected.od`/`phase2d-shadow-actual.od` on a mismatch),
and that value additionally reaches `/etc/shadow` inside the VM.

That is fine for what these fixtures are: marker strings invented by the
run itself, for a keypair discarded at the end of it, so there is no
credential anywhere to leak. It stops being fine the moment someone puts
a realistic value in `FIXTURE_SECRET` or `FIXTURE_PASSWORD_HASH`, and
those paths are what would have to change first. The claim is written
out here rather than left implicit precisely because a false invariant
is what would license that swap.

`FIXTURE_PASSWORD_HASH` carries one extra rule of its own: it must stay
something that could not be mistaken for a crypt hash. A realistic-looking
`$6$...` there would be worse than merely untidy — it would read as a
credential in a CI artifact, and it would invite the next person to
generate it from a plaintext password, which is the one thing
`docs/tasks/0032-password-hash.md` guarantees does not exist anywhere in
this process.
