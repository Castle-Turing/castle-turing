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
power cycle the failure makes inevitable.

## The mechanism

A new module surface, proposed name `castle.canary.storage` — "canary"
rather than "watchdog" deliberately, because the watchdog word is
already spoken for by the hardware-watchdog thread and a word doing
two jobs is a defect. Public mechanism, private enablement, per
Principle 01: the module ships the daemon and its options; the host
turns it on and sets policy.

One long-running daemon, started at boot, doing this forever:

1. Every `intervalSec` (default 60), for each watched mount (default
   `[ "/" ]`): open a fresh canary file under a per-mount directory
   (e.g. `<mount>/var/lib/castle-canary/` for `/`; for other mounts a
   dot-directory at their root), write the current timestamp, fsync,
   close, unlink. Record the cycle's completion time.
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
(RAM), prints to the console, and — verify this against the pinned
systemd's journald defaults (`ForwardToWall=yes`,
`MaxLevelWall=emerg`) — is walled to every logged-in terminal by a
journald that is itself still running from cache. On the night of the
incident that line would have been sitting on every foot terminal of
a still-working desktop at 01:25.

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
  and `/dev/kmsg`. No NSS lookups (no `getpwnam`, no DNS), no locale
  or timezone file loads after init — glibc reaches for files behind
  all of these.
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

**Escalation, default off.** `escalate.enable` (bool, default false)
and `escalate.afterFailures` (int, default 5): after N consecutive
failed cycles on the root filesystem, write `c` to
`/proc/sysrq-trigger`, converting the condition into a kernel panic
that pstore captures — task 0068 confirmed the pstore path is wired —
so the next boot carries a timestamped record of when the disk died
instead of a blank night. The option's doc must say plainly what it
costs: it trades the remains of the session (already unsavable — the
disk is gone) for evidence and a faster restart. Enabling it is the
resident's call in the private layer, not a default.

Options, under `castle.canary.storage`: `enable`, `mounts` (list of
str, default `[ "/" ]`), `intervalSec` (default 60), `deadlineSec`
(default 30), `escalate.enable`, `escalate.afterFailures`. Keep the
surface this small; everything else is mechanism.

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

Automatable, and the automation is most of the work of trusting this:
a NixOS VM test (`nix flake check`) with a second virtual disk,
formatted, mounted, watched by the canary alongside `/`.

1. Healthy path: canary runs two intervals, no alarm line in
   `/dev/kmsg`.
2. Write-error path: swap the second disk's device-mapper table to
   the `error` target (`dmsetup` inside the VM); assert the EMERG
   line for that mount appears in the kernel ring buffer within one
   interval plus deadline, and repeats.
3. Hang path: `dmsetup suspend` the device; assert the overdue alarm
   fires after `deadlineSec` and that the daemon's monitor thread
   keeps petting (unit stays active, no restart) while the worker is
   wedged.
4. Read-only path: remount the second disk `ro`; assert the alarm.
5. Escalation path: enable escalation with a low threshold against
   the *second* disk marked as escalation-eligible only if the brief's
   root-only rule is relaxed for the test — otherwise run the error
   target against a VM whose watched mount is root-equivalent — and
   assert the VM panics (test driver observes the crash; asserting
   pstore contents in qemu is optional, not required).
6. Residency receipts, asserted in the test: `VmLck` nonzero in
   `/proc/<pid>/status`; unit fails hard if `mlockall` is made to
   fail (e.g. a `MemoryDenyWriteExecute`-style sandbox conflict —
   whatever induces it — or drop this assertion with a stated reason
   if no clean inducement exists).

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
