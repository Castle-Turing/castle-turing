Title: Task 0068 — the journal loses the minutes before a hang
Model: standard
Model-because: the change is bounded configuration with one
documented tradeoff (flush cadence against SSD wear, and what capture
belongs host-side), and the evidence for why it matters is already
written here rather than left to be re-derived. What a deep
implementer would add is judgment this file has already spent — the
Principle 01 split of which piece lands in `modules/` and which in
`hosts/` is stated below, and the failure mode of getting the knob
wrong is visible in review.

# Task 0068 — the journal loses the minutes before a hang

## Why, from the incident

The machine hung and was power-cycled at roughly 21:22 on 2026-09-06.
The previous boot's journal ends at 21:15:29 with routine wifi
chatter: no power-key event, no shutdown target, no stop-job
messages, none of the console warnings the resident watched during
the hang. Roughly seven minutes of exactly the evidence a post-crash
investigation needs was never persisted. The next boot's journald
confirmed the loss: "File .../system.journal corrupted or uncleanly
shut down, renaming and replacing."

This is journald working as configured, not a bug. Verified against
this flake's pinned nixpkgs (`github:NixOS/nixpkgs`, locked rev
`0e251e24a4f24e036a084b6b4b2d2491af4167f4`, nixos-unstable branch,
systemd 261.1) — its `journald.conf(5)` source
(`man/journald.conf.xml`) states plainly: "the timeout before
synchronizing journal files to disk... syncing is unconditionally done
immediately after a log message of priority CRIT, ALERT or EMERG has
been logged. This setting hence applies only to messages of the
levels ERR, WARNING, NOTICE, INFO, DEBUG. The default timeout is 5
minutes." A machine that degrades and then hangs — the common shape
of a bad night — loses up to that full interval, and loses it
precisely when it matters, because nothing at INFO/NOTICE/WARNING
severity forces a sync.

`docs/backlog/a-crash-goes-uninvestigated.md` is the sibling entry —
it proposes an inquest that *reads* crash evidence. This task is
about the evidence existing to read at all, and does not touch that
entry.

## The change: `castle.journald.syncInterval`

This nixpkgs pin exposes no dedicated NixOS option for
`SyncIntervalSec` — `nixos/modules/system/boot/systemd/journald.nix`
declares `storage`, `rateLimitInterval`, `rateLimitBurst`, `audit`,
`console`, `forwardToSyslog`, and a catch-all `extraConfig` (raw
`journald.conf` lines), and nothing else. `SyncIntervalSec` has to go
through `extraConfig`, so `modules/base` declares its own option
rather than hardcoding a line, so a host or private layer can still
argue for a different tradeoff without editing the framework.

Added to `modules/base/default.nix`, alongside the module's other
framework-wide policy (`nix.gc`, `nix.settings.experimental-features`):

```nix
options.castle.journald = {
  syncInterval = lib.mkOption {
    type = lib.types.str;
    default = "30s";
    description = ''
      How often journald flushes buffered log entries to disk
      (`SyncIntervalSec` in journald.conf(5)), independent of the
      immediate sync journald already does for CRIT/ALERT/EMERG
      messages. The upstream default is 5 minutes, which is the
      window task 0068 lost: a machine that degrades and then hangs
      persists nothing logged in the final interval before the
      hang, at exactly the severities (INFO/NOTICE/WARNING) most
      post-crash investigation depends on.

      30 seconds trades an up-to-10x more frequent metadata sync
      for a 10x-smaller loss window. Each sync is a lightweight
      fsync of already-written, already-mmap'd journal pages, not a
      rewrite — this is not comparable in write volume to a
      database checkpoint — but on an SSD it is still wear this
      framework did not have on the default policy, so this is a
      deliberate choice rather than an obviously-free one. A host
      with a specific reason to prefer the upstream cadence (or a
      tighter one) can override with `lib.mkDefault` or a plain
      assignment.
    '';
  };
};
```

wired into the module's `config`:

```nix
services.journald.extraConfig = ''
  SyncIntervalSec=${config.castle.journald.syncInterval}
'';
```

`services.journald.extraConfig` is `types.lines`, which concatenates
every module's contribution rather than picking one winner, so this
composes cleanly with anything a private layer adds later.

**Placement, argued.** `modules/base`, not a host module: durability
of the final minutes of evidence is a framework stance ("what does
`journald` sync do here"), not a chassis fact, and `modules/base` is
already where this project's other blanket policy lives (`nix.gc`,
password-reminder). Every real `nixosConfiguration` in this flake
imports it — including the installer image — so the posture is
uniform rather than something each host has to remember to opt into.

**What this does not touch**, per the task's explicit scope: journal
`Storage=` (still `persistent`, the NixOS default — no
`volatile`-adjacent tuning) and no size/retention policy
(`SystemMaxUse` etc.). Only the sync cadence.

## Kernel-side capture: assessed, not changed

The incident's boot also showed `modprobe@efi_pstore.service` being
skipped by condition. Read against the pinned systemd source
(`units/modprobe@.service`, `units/systemd-pstore.service.in`,
`src/pstore/pstore.conf`):

- `modprobe@efi_pstore.service` carries
  `ConditionKernelModuleLoaded=!efi_pstore` — it is *designed* to
  no-op whenever `efi_pstore` is already active, which on most x86_64
  EFI kernels is because the driver is built directly into the
  kernel (`CONFIG_EFI_VARS_PSTORE=y`) rather than shipped as a
  loadable module. A skip here is the expected shape of "the backend
  is already there," not evidence it is missing.
- `systemd-pstore.service` (which archives any pstore-captured crash
  dump into `/var/lib/systemd/pstore`) is already unconditionally
  `wantedBy sysinit.target` on this NixOS pin
  (`nixos/modules/system/boot/systemd.nix`, tagged "see #81138") and
  gates only on `ConditionDirectoryNotEmpty=/sys/fs/pstore` — i.e. it
  runs every boot and is a no-op except right after a real oops/panic
  that left a record. NixOS's own `systemd-pstore` test
  (`nixos/tests/systemd-pstore.nix`) confirms this exact behavior
  with a real triggered crash.

**Conclusion: no host-side Nix change for pstore itself.** The
mechanism this project would want — kernel crash capture surviving to
the next boot — is already wired in by NixOS's defaults through
`modules/base` → the standard systemd unit set. There is nothing
disabled to turn on. Whether `/sys/fs/pstore` and
`/sys/firmware/efi/efivars` genuinely have usable NVRAM space on this
chassis is a runtime hardware fact no `nix flake check` can settle
(the NixOS test proves the mechanism in a VM, not this machine's real
firmware); confirming it needs a human running a real, disruptive
test crash (`echo c > /proc/sysrq-trigger`) on hardware, which is out
of scope for an unattended change.

**The gap pstore does not close.** Pstore only captures what the
kernel writes at an oops/panic. The 21:15–21:22 incident was a hang —
the journal shows no panic, no OOM kill, no stop-job, nothing — and a
plain hang produces no crash dump for pstore to catch regardless of
NVRAM headroom, because nothing in the kernel ever decided to panic.
The mechanism that would cover *that* case is a hardware watchdog
(`systemd.watchdog.runtimeTime` / `RuntimeWatchdogSec`, petting
`/dev/watchdog`) forcing a panic once systemd itself stops being
scheduled — turning an otherwise-silent hang into something pstore
(or a serial/netconsole capture) can see.

That is not a cheap, clean change to make blind: it needs confirming
this chassis actually exposes a `/dev/watchdog` device
(Intel ICH/PCH chassis commonly do via `iTCO_wdt`, but it is a
firmware fact, not a framework assumption — Principle 01), and it
carries real risk of its own (a false-positive reboot during a
legitimately slow but not-hung operation) that deserves testing on
real hardware before it becomes a standing default. Filed instead as
`docs/backlog/no-watchdog-forces-a-panic-on-a-hang.md`, alongside
`a-crash-goes-uninvestigated.md`, rather than guessed at here.

## Verification

Agent-verifiable now: `nix flake check`, plus a new assertion on
`nixosConfigurations.example` (flake.nix) reading
`config.environment.etc."systemd/journald.conf".text` and asserting
it contains `SyncIntervalSec=30s` — the same "read the generated
artifact, not the option value" pattern this flake already uses for
the activation grant and the password-reminder banner, so the check
proves the drop-in actually renders rather than only that the option
evaluates.

Needs human hands: proving this setting actually saves the final
minutes of a *real* hang is not cheaply testable — it would require
reproducing an unclean shutdown on real hardware and comparing what
survives. Nothing here pretends otherwise; the honest claim this
brief can back is "the interval journald honors is now 30s instead of
5 minutes," verified by reading the rendered config, not "this would
have saved 0906's boot," which nothing can prove without another
hang.
