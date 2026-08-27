# Full-disk encryption

**What.** Encrypt the root filesystem (LUKS2), declared in the disk
layout so it is part of the reproducible install rather than a manual
step.

**Why it matters — and this changed in kind, not just degree, with
`docs/tasks/0031-secrets-tooling.md`.** A laptop is a stolen-laptop
risk. As of that task the reference host does not merely *hold* secrets
eventually; it holds, right now, a plaintext **age master key** at a
fixed and publicly documented path — `/var/lib/sops-nix/key.txt`, mode
`600`, root-owned — and that one file decrypts *every* secret in the
resident's private repo: the Wi-Fi PSK today, and whatever tokens and
credentials the mail and agent layers add later. Anyone holding this
machine and able to read its disk gets the key, and with it a
private-repo history's worth of credentials rather than one machine's
worth. `600` and root ownership are protections against other *logged-in
users*; they are worth nothing against physical possession.

**And as of `docs/tasks/0032-password-hash.md` that same key opens the
admin account's login password too**, not only the Wi-Fi PSK. The
sentence below about the login password being decoration was already
true; that task makes it circular as well as true. The password that
guards the console is now seeded from a secret whose key sits, in the
clear, on the disk the console is guarding — so an attacker holding the
machine does not have to defeat the login at all, and would not bother
trying. This is one more reason the stakes named here keep growing:
0032 was a real improvement (the hash no longer lands in the
world-readable Nix store, where every account and process on a *running*
machine could read it), and it moves nothing at all against physical
possession.

That is a deliberate, argued trade — see that task's "The honest
limitation" and `docs/private-layer.md`'s section of the same name —
not an oversight, and it is the correct trade only for as long as this
entry stays open. Without encryption the login password is decoration
and the age key is in the clear; encryption is also what makes the
seeded login password (see `modules/base`) a real boundary instead of a
speed bump. The eventual arrival of GitHub tokens and the resident's
own priorities and correspondence raises the stakes further, but the
stakes are already real today.

**What we already know.**

- `disko` supports LUKS natively, so the layout stays declarative and
  the install stays one command.
- The hard tension: an encrypted root needs a key at boot, and two
  properties this project depends on are unattended boot after power
  loss and SSH reachability with nobody at the keyboard. Naive FDE
  breaks both.
- Three known ways out, none free:
  - **TPM2 unlock** (`systemd-cryptenroll`). The XPS 13 9370's chipset
    has TPM 2.0. Boots unattended; binds the key to firmware state, so
    a firmware update can lock you out, and an attacker with physical
    possession and patience is not stopped.
  - **initrd SSH unlock** (`boot.initrd.network.ssh`). Unlock remotely
    over the network at boot. Fits this project's remote-operation
    posture well, but means a machine that reboots is unreachable until
    someone unlocks it.
  - **Console passphrase.** Simplest and strongest; ends unattended
    boot entirely.
- **The key-planting step is now part of the install flow this would
  change.** `docs/tasks/0031` plants the age key with `nixos-anywhere
  --extra-files`, which writes into `/mnt` after disko has partitioned
  *and mounted* the target — so on an encrypted root the key lands
  inside the encrypted volume without any change to that step, which is
  the good case. What does need thought is the unlock path chosen
  below: a TPM2-bound key means the disk unlocks for whoever powers the
  machine on, which protects the age key against a pulled drive but not
  against a booted laptop; an initrd-SSH or console unlock protects it
  against both and costs unattended boot.
- Ripple effects: `modules/disk-layout.nix`, the installer flow, and
  the VM harness's power-cycle and NVRAM-wipe assertions (an encrypted
  target changes what "boots successfully" means in
  `test/vm-install/`).
- The dead-CMOS history on this chassis (see
  `docs/tasks/0003-findings.md`) is relevant: anything that makes
  unattended boot more fragile compounds a machine that already had
  trouble booting itself.

**Open questions.** Which unlock path, or a combination (TPM2 with a
passphrase fallback is common)? Does the harness grow an encrypted
variant of the VM test, or does encryption become a host-level opt-in
that the harness covers separately? Does the private layer hold
anything unlock-related, or is the key material purely on-machine?
