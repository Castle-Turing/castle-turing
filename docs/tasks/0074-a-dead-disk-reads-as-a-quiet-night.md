Title: A storage canary turns a dead disk into an alarm
Model: standard
Milestone: none — hygiene
Model-because: the design decisions are made in this brief — the daemon
shape, the residency rules, the alarm channel, the test harness — so the
work is a small program plus NixOS wiring, not design. What rules out the
cheap tier is that the brief's central constraint (nothing in the alarm
path may touch the disk at failure time) is easy to violate in ways that
look correct and test green on a healthy machine: a convenient
subprocess, a lazy library load, a log line to a file. The implementer
must audit their own work against that constraint and argue back where
this spec itself trips over it, not transcribe. What rules out the deep
tier is that there is no open design question left to spend judgment on.

# Task 0074 — a dead disk reads as a quiet night

## Why, from the incident

On 2026-09-16 at ~01:24 this host's NVMe stopped persisting writes
while the machine kept running. The evidence, reconstructed the next
morning: the system journal ends mid-stream at 01:23:21 (a routine
timer tick, no shutdown, no error); the last write that reached the
disk is 01:24:18; zero files anywhere on the filesystem carry a
modification time between 01:26 and the 08:04 power cycle. The system
ran on from page cache all night — no suspend, no hang — and the
resident met the failure only as downstream wreckage: wifi gone
(nothing could be respawned once exec needed the dead disk), SIGBUS
in running programs as pages failed to fault in, a failed credentials
read presenting as a login prompt, a TUI dying without restoring the
terminal. fsck on the next boot recovered the ext4 journal and
cleared a column of orphaned inodes. The root cause is suspected but
not yet confirmed (the chassis NVMe's power-state behaviour; SMART
tooling was declared in the private layer the same morning); this
task is not the root-cause fix — it is the detector the incident
ships, per the convention in CLAUDE.md.

Why nothing existing catches this shape: task 0068's journald flush
cadence assumes writes succeed; pstore capture assumes a panic; the
hardware-watchdog backlog entry (`no-watchdog-forces-a-panic-on-a-hang`)
assumes the scheduler stops — here systemd ran all night and would
have petted any watchdog on time; task 0073's oomd work assumes the
resource is memory. Each defense waits for noise or for the world to
stop. A dead disk under a live machine produces neither, and every
byte of evidence about its onset is RAM-resident and lost at the
power cycle the failure makes inevitable. It is the second incident
class in ten days whose inquest starts from almost nothing —
`docs/backlog/a-crash-goes-uninvestigated.md` is the standing
complaint, and this detector is one concrete answer to it.

## The mechanism

A new module surface, proposed name `castle.canary.storage` — "canary"
rather than "watchdog" deliberately, because the watchdog word is
already spoken for by the hardware-watchdog thread and a word doing
two jobs is a defect. Public mechanism, private enablement, per
Principle 01: the module ships the daemon and its options; the host
turns it on and sets policy.

One long-running daemon, started at boot, doing this forever:

1. Every `intervalSec` (default 60), for each watched mount (default
   `[ "/" ]`): open a fresh canary file under `<mount>/.castle-canary/`
   — the same scheme for every watched mount, `/` included; a
   `/var`-based path would probe the wrong disk on any host where
   `/var` is its own filesystem, which is the exact silent miss this
   detector exists to kill. At startup, verify with `stat` that each
   canary directory's `st_dev` equals its watched mount point's, and
   fail the unit if not. Write the current timestamp, fsync, close,
   unlink. Record the cycle's completion time.
2. Independently, check `/proc/mounts` for any watched mount having
   gone `ro` — a read-only remount is the same disease with a
   politer face, and reading procfs touches no disk.
3. A monitor thread — which never touches any watched filesystem —
   watches the worker's completion times. If a cycle's write+fsync
   has not completed within `deadlineSec` (default 30, matching the
   NVMe controller-timeout order of magnitude), or completed with an
   error, or a watched mount is `ro`: raise the alarm, and keep
   raising it once per interval while the condition holds.

**The alarm path must need nothing from the disk.** The alarm is one
EMERG-level line written to `/dev/kmsg`
(`<0>castle-canary: fsync on / overdue since <timestamp>` — tag,
mount, condition, onset time). That lands in the kernel ring buffer
(RAM) and prints to the console, and is the durable-within-the-boot
record the inquest reads. It is NOT, on its own, reliably
human-visible on this desktop: journald's wall forwarding cannot be
leaned on at failure time, both because journald fsyncs the dying
disk every 30 seconds (task 0068's `SyncIntervalSec`) and can wedge
before forwarding, and because wall targets utmp-registered ttys,
which Wayland terminal ptys (foot) are not. So the daemon delivers
the human-visible copy itself: on each alarm, best-effort write of
the same line to every pty under `/dev/pts/` — devpts is RAM-virtual,
so enumerating and opening those touches no disk. On the night of
the incident that puts the alarm inside every open foot terminal of
a still-working desktop at 01:25, with the kmsg line behind it as
the record.

**Residency is the crux, not a hardening flourish.** At failure time,
any demand page-in from the dead disk hangs or kills the faulting
process. Therefore, enforced by the implementation and stated in the
module docs:

- The daemon calls `mlockall(MCL_CURRENT | MCL_FUTURE)` at startup
  and treats failure as fatal to the unit — an unlocked canary is the
  quiet-day lie this repo's conventions exist to kill. Log `VmLck`
  from `/proc/self/status` at startup as the receipt.
- After startup, the daemon must never exec, fork, dlopen, or open
  any file outside the watched mounts' canary directories, `/proc`,
  `/dev/kmsg`, and `/dev/pts` (the alarm path's pty writes — devpts
  is RAM-virtual, so these opens touch no disk, which is why they
  are compatible with this rule at all). No NSS lookups (no
  `getpwnam`, no DNS), no locale or timezone file loads after init —
  glibc reaches for files behind all of these.
- A systemd timer firing a script is the forbidden shape: it execs at
  exactly the moment exec stops working. This is why the daemon is
  long-running.
- Language: a single small C source, built in the module the way this
  repo already builds module-shipped programs (follow precedent in
  `modules/`; if there is none, `pkgs.runCommandCC` on one file is
  boring and sufficient). A dynamic-language runtime makes the locked
  set large and unauditable. If the implementer believes another
  choice meets the residency rules better, that is an argument to
  make in the PR, not a silent substitution.

**The canary's own liveness** (task 0073's doctrine: a dead defense
reads as a quiet day). `Restart=on-failure` covers crashes in normal
times. `WatchdogSec` with `sd_notify` petting covers a wedged daemon —
but the pet must come from the monitor thread, never the worker: when
the disk dies, the worker thread wedges in uninterruptible sleep by
design, and if that stopped the petting, systemd would kill and
restart the unit into an exec that no longer works, silencing the
alarm at the exact moment it matters. The monitor thread stays
healthy, keeps petting, keeps alarming. Use the `NOTIFY_SOCKET`
protocol directly (one `sendmsg` to an already-connected unix socket;
no library load at failure time).

**Escalation, default off.** `escalate.enable` (bool, default false),
`escalate.mounts` (list of str, default `[ "/" ]`), and
`escalate.afterFailures` (int, default 5): after N consecutive
*failed intervals* on an escalation mount, write `c` to
`/proc/sysrq-trigger`, converting the condition into a kernel panic
for pstore to capture, so the next boot can carry a timestamped
record of when the disk died instead of a blank night. "Failed
interval" is counted by the monitor thread and includes the hang
case — an interval during which no cycle completed successfully —
not only cycles that returned an error; a literal
completed-with-error counter never trips on a wedged disk, which is
the incident's own shape. Two honesty requirements on the option
docs: (1) a bare panic does not reboot — `kernel.panic` defaults to
0 and nothing in this repo sets it — so when `escalate.enable` is on
the module also sets `boot.kernel.sysctl."kernel.panic"` (30 is
reasonable) and the stated trade is "the remains of the session
(already unsavable — the disk is gone) for evidence and an automatic
reboot"; (2) task 0068 confirmed only that the pstore *units* are
present — whether this chassis's EFI NVRAM usably captures a panic
is, in 0068's own words, a runtime hardware fact needing a human
test crash, still unperformed. The option doc carries that caveat,
and the first real enablement should be preceded by 0068's
test-crash step. Enabling escalation is the resident's call in the
private layer, not a default.

Options, under `castle.canary.storage`: `enable`, `mounts` (list of
str, default `[ "/" ]`), `intervalSec` (default 60), `deadlineSec`
(default 30), `escalate.enable`, `escalate.mounts`,
`escalate.afterFailures`. Keep the surface this small; everything
else is mechanism.

## What this task is not

- Not the root-cause fix for the NVMe dropout. If SMART confirms the
  power-state suspicion, the `nvme_core.default_ps_max_latency_us`
  workaround is a chassis fact and belongs in `hosts/xps9370`, in its
  own change citing the evidence.
- Not the hardware watchdog. That backlog entry stays open; it covers
  the failure this one cannot (the scheduler dying — a dead scheduler
  runs no monitor thread).
- Not a general health/metrics framework. One failure shape, one
  detector, one alarm.

## Verification plan

Automatable, and the automation is most of the work of trusting
this: a NixOS VM test following the repo's existing precedent —
`test/oomd-liveness/test.nix` is the closest sibling (also a
liveness-shaped daemon test). Note flake.nix's deliberate, documented
rule that VM-booting tests live in `packages.*` and run via their own
workflow, NOT in `checks.*` — so the invocation is
`nix build .#<test-name>`, and `nix flake check` alone does not run
it; wire it wherever the two existing VM tests are wired. The test
VM carries a second virtual disk wrapped in a dm-linear device
(`dmsetup create` over `/dev/vdb` *before* formatting and mounting —
a directly-mounted disk has no dm table to swap later), formatted,
mounted, and watched by the canary alongside `/`.

1. Healthy path: canary runs two intervals, no alarm line in
   `/dev/kmsg`.
2. Write-error path: swap the dm device's table to the `error`
   target; assert the EMERG line for that mount appears in the
   kernel ring buffer within one interval plus deadline, and
   repeats, and that the same line reached a pty (open one in the
   test, read it back).
3. Hang path: `dmsetup suspend` the device; assert the overdue alarm
   fires after `deadlineSec` and that the daemon's monitor thread
   keeps petting (unit stays active, no restart) while the worker is
   wedged.
4. Read-only path: remount the second disk `ro`; assert the alarm.
5. Escalation path: set `escalate.mounts` to the second disk's mount
   with a low `escalate.afterFailures`, swap its table to `error`,
   and assert the VM panics (the test driver observes the crash;
   asserting pstore contents in qemu is optional, not required —
   the chassis-side pstore question is 0068's, per the caveat
   above).
6. Residency receipts: assert `VmLck` nonzero in
   `/proc/<pid>/status`. For the fail-hard-on-mlockall-failure
   branch, the inducement is `RLIMIT_MEMLOCK`: run the binary as an
   unprivileged user (no `CAP_IPC_LOCK` — a root daemon bypasses
   the rlimit) under `LimitMEMLOCK=0` and assert it exits nonzero.
   `MemoryDenyWriteExecute` is not an inducement — it restricts
   `PROT_EXEC` mappings and does not affect `mlockall`.

Shorten the intervals in the test via the options; that is what they
are for. No human steps beyond enabling the module on the host in the
private layer.

## Implementation prompt

Read this brief in full, then `docs/backlog/README.md` and CLAUDE.md
for the conventions that bind you. Implement `castle.canary.storage`
as specified: the C daemon, the NixOS module, the VM test. The
residency rules and the alarm-path rules are the acceptance criteria,
not suggestions — audit every line of the failure path against "does
this touch the disk?" before claiming done. Where this brief is wrong
or self-contradictory, argue in the PR and record the deviation in
this file in the same PR; where it is ambiguous, report the judgment
call you made. Do not widen scope into the hardware watchdog, the
NVMe workaround, or any metrics surface.
