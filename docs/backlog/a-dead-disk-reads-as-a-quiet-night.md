# A dead disk reads as a quiet night

**What.** On 2026-09-16 at ~01:24 this host's NVMe stopped persisting
writes while everything else kept running. The system journal ends
mid-stream at 01:23:21; the last write that reached the disk is
01:24:18; not one file on the filesystem carries a modification time
between 01:26 and the 08:04 power cycle — six and a half hours during
which the machine stayed up, interactive, and silently unable to
record anything. The failure announced itself only the next morning,
as downstream wreckage: wifi gone (nothing could be respawned from
disk), SIGBUS in running programs as their pages failed to fault in,
a credentials read failing as a login prompt. Nothing on this host
watches for the failure itself: storage no longer serving I/O on a
machine that otherwise runs.

**Why it matters.** Every defense this repo has built or queued
assumes a failure that makes noise or stops the world. Task 0068
tightened journald's flush cadence — irrelevant when the disk ignores
writes. pstore capture waits for a panic — none happened. The
hardware-watchdog entry (`no-watchdog-forces-a-panic-on-a-hang`)
covers the scheduler dying — here systemd ran happily from page cache
all night and would have petted any watchdog on time. The oomd work
(task 0073) covers memory — memory was fine. This failure produced no
noise, stopped nothing, and therefore left no evidence: everything
that knew what happened was RAM-resident and died at the power cycle
the failure made inevitable. It is the second incident class in ten
days whose inquest starts from almost nothing
(`a-crash-goes-uninvestigated.md` is the standing complaint), and it
will recur: the suspect is the chassis NVMe's power-state behaviour,
which no amount of software hygiene retires.

**How it would have been caught sooner.** A storage canary: a
long-running, memory-locked daemon that periodically writes and
fsyncs a small file per watched filesystem and raises an alarm
through a channel that does not itself need the disk — an
EMERG-level line into `/dev/kmsg` (kernel ring buffer, console,
walled to every terminal), with optional escalation to a deliberate
sysrq panic so pstore preserves a timestamped record across the
power cycle. At 01:25 that alarm would have been on every terminal
of a still-working desktop; instead the incident was reconstructed
eight hours later from mtime archaeology. The detector's own shape
matters and is the hard part: anything that spawns a process at
failure time (a timer firing a script) dies of exactly the disease
it is meant to diagnose, because exec needs page-ins from the dead
disk.
