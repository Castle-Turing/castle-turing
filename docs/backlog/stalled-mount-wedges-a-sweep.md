# A stalled mount can wedge a dispatch sweep before any timeout applies

**What.** `castle dispatch` can block indefinitely inside an ordinary
`stat()` on a resident's configured checkout, while holding the global
dispatch lock. Nothing in the agent layer bounds a filesystem call, and
the one timeout near this code — `CHECKOUT_PROBE_SECONDS` in
`agent/castle` — bounds only a subprocess, which runs *after* the calls
that can hang.

**Why it matters.** The sweep holds `dispatch_lock_path()` for its whole
run, so a wedged sweep does not merely fail one errand: it stops every
later sweep on that machine, silently, until the mount recovers or
something kills the process. The timer keeps firing and finding the
lock held. There is no result record, no notification, and no
`outcome` — the failure mode the `claim` record and the reaper were
built to make visible (`docs/tasks/0021-auto-dispatch.md` §3.2) does
not cover this one, because the process is alive and has not yet
written a claim.

**What we already know.**

- The unbounded calls are `pathlib.Path.exists()` and
  `.is_dir()` in `_checkout_fault` (`agent/castle`), reached for
  `castle.agent.repo.private` and, when configured, for
  `castle.agent.repo.mechanism`, on **every** turn. Both are plain
  `stat()` syscalls.
- On a hung NFS mount (hard-mounted, the default) or an autofs mount
  whose server is unreachable, `stat()` blocks in uninterruptible
  sleep. `SIGTERM` does not land, so systemd stopping the unit does not
  end it either; only the mount recovering does.
- `CHECKOUT_PROBE_SECONDS` (10s) bounds the `git rev-parse
  --show-toplevel` probe and nothing else. Its comment used to claim
  it protected against exactly this scenario; that claim was corrected
  in `docs/tasks/0024-config-target.md`'s branch rather than left
  standing, and this entry is where the real gap went.
- A `subprocess` timeout is the wrong instrument. `subprocess.run(...,
  timeout=)` works because the work happens in another process that
  can be killed; a blocking `stat()` in *this* process has no such
  seam. Bounding it needs a different mechanism — a worker thread
  whose result is waited on with a timeout (the thread stays stuck but
  the sweep proceeds), a `fork()`ed probe process, or a
  filesystem-level guard such as checking `/proc/self/mountinfo` for
  the mount and its liveness before touching the path.
- This is not specific to the checkout roots. `state_dir()` and the
  journal reads have the same exposure if a resident puts their
  private repo on a network mount, which `docs/private-layer.md` does
  not forbid.

**Open questions.**

- Is a thread-with-timeout acceptable, given that each timed-out probe
  leaks a stuck thread for the life of the process? A sweep is a
  short-lived `oneshot`, so the leak may be bounded in practice.
- Should the sweep instead refuse to start at all when a configured
  root is on a mount it can cheaply identify as unhealthy, rather than
  bounding every call?
- Does this deserve fixing before a resident is documented as able to
  keep their private repo on network storage, or is "do not do that"
  a legitimate answer written into `docs/private-layer.md`?
- The dispatch lock's own semantics are worth revisiting alongside
  this: a lock with no liveness check turns any hang into a permanent
  outage of the whole mechanism.
