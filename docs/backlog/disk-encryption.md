# Full-disk encryption

**What.** Encrypt the root filesystem (LUKS2), declared in the disk
layout so it is part of the reproducible install rather than a manual
step.

**Why it matters.** A laptop is a stolen-laptop risk, and this one will
hold GitHub tokens, agent credentials, and eventually the resident's
private layer — priorities, correspondence, the agent's model of its
user. Without encryption the login password is decoration: anyone
holding the machine can read the disk directly. Encryption is also what
makes the seeded login password (see `modules/base`) a real boundary
instead of a speed bump.

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
