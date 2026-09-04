# Task 0051 — the notification waiter leaves the dispatch unit's cgroup

There is no backlog entry behind this one. It comes from a finding
made on the reference host on 2026-09-04, reproduced in full below,
and the task file that carried it into the queue is this brief's
predecessor rather than a separate document.

## The finding

`castle-dispatch.service` is `Type=oneshot` with `KillMode=process`.
That setting is deliberate and correct (docs/tasks/0034, its findings
section): `_fire_notification` detaches its waiter with
`start_new_session=True`, which leaves the unit's *process group* but
not its *cgroup*, so the default control-group cleanup was killing
every notification's click handler the instant the sweep returned.
`KillMode=process` fixed that.

What it did not do is get the waiter out of the cgroup. So a sweep
that fires a notification leaves the waiter — and, once the resident
clicks, `foot` — parked in `castle-dispatch.service`'s cgroup until
the notification expires. The next sweep, two minutes later, finds
them there and systemd logs, once per leftover process:

    castle-dispatch.service: Found left-over process 819594 (python3) in control group while starting unit. Ignoring.
    castle-dispatch.service: This usually indicates unclean termination of a previous run, or service implementation deficiencies.

Observed on the reference host on 2026-09-04: six such lines in a
twenty-minute window covering two real errands, alongside "Unit
process N remains running after unit stopped" at each sweep's end.

Nothing is failing. Both errands completed and both notifications
fired. The cost is that a correct design emits, on a two-minute timer,
a systemd message asserting unclean termination and implementation
deficiencies — in the one log a resident or an agent reads first when
an errand appears to have gone missing. A log line that always appears
and never means anything is how the line that does mean something gets
skipped. That is the whole of the problem: legibility, not function.

## What this task builds

One helper in `agent/castle`, `_scope_wrapped`, and one call to it.

When the sweep firing the notification is itself running inside a
systemd service, the detached waiter is spawned through
`systemd-run --user --scope --quiet --collect --unit=... --description=... --`,
which registers a transient scope around the process and then execs
the waiter in place. The waiter is therefore in a cgroup of its own
from the moment it starts, the dispatch unit's cgroup is empty when
the sweep ends, and the next sweep finds nothing to complain about.
The scope is named `castle-notify-waiter-<record id>-<4 hex>.scope`;
the name is not decoration, and the section on stderr below is why.
When the sweep is *not* inside a unit — `castle route` typed at a
terminal — the helper returns the argv it was given, unchanged, and
nothing about the hand-run path moves.

Everything else in the notify path stays exactly as docs/tasks/0034
and docs/tasks/0038 left it: the same waiter, the same `--action`,
the same lock, the same `foot`. `foot` inherits the improvement for
free — launched by a waiter that is already in the scope, it lands
there too, which is the other half of what the finding observed.

### Why a scope and not a transient service

`systemd-run --user --unit=... --service-type=exec` would also move
the waiter out of the cgroup, and it has one genuine advantage: the
caller can wait a bounded moment on `systemd-run` and *know* whether
the unit started, so a fallback could be exact rather than gated. It
was rejected because it changes two things this task has no business
changing.

The first is the environment. A transient service is started by the
user manager with the manager's environment, not the caller's. The
waiter would lose `CASTLE_NOTIFY_COMMAND` (which the dispatch unit
sets, and which a resident may have set to something that is not
`notify-send`), and it would lose `WAYLAND_DISPLAY` and `SWAYSOCK` —
the two variables `_resolve_wayland_env` exists as a *fallback* for
precisely because a unit cannot be relied on to have them. Every one
of those could be passed through with `--setenv`, and each one passed
through by hand is a variable that silently stops travelling the day
someone adds another.

The second is stderr, which constraint 2 below is about. A scope
carries no `StandardError=` because there is nothing for it to apply
to: `systemd-run --scope` execs the command in the process it was
given, with the file descriptors it was given. A transient service
gets fresh ones pointed at its own journal identity.

`--scope` is therefore the option that fixes the cgroup and changes
the least else, which is what this task wants.

### What the stderr actually does, measured

This brief was drafted claiming the waiter's stderr would keep landing
under `_SYSTEMD_USER_UNIT=castle-dispatch.service`, on the reasoning
that journald attributes a stdout/stderr stream to the unit that
opened it. **That was wrong, and it was checked rather than shipped.**
A probe on the reference host — a transient oneshot service with
`KillMode=process` spawning a detached child, run once with the scope
hop and once without — settles it:

- Without the scope, the child's line reads
  `probe-control.sh[970153]: control-waiter: inherited stderr` and
  carries `_SYSTEMD_USER_UNIT=castle-0051-control.service`. The next
  start of that unit produces the finding's exact pair of lines,
  `Found left-over process 970124 (sleep) in control group while
  starting unit` and the sentence about implementation deficiencies.
- With the scope, the same line carries
  `_SYSTEMD_USER_UNIT=run-p969582-i969583.scope`, and the next start
  of the unit logs nothing at all beyond starting and finishing.

So journald files a line under the cgroup of the process that *wrote*
it, not under the unit that opened the stream. The file descriptor is
unchanged — the bytes still travel out on the sweep's own stderr, and
a hand-run `castle route` still prints to its terminal — but the name
they are filed under moves with the waiter.

That is what the scope's name is for. A warning filed under
`run-p969582-i969583.scope` is in the journal and nowhere a person
would look; filed under `castle-notify-waiter-<record id>-<hex>.scope`
it has a standing address, `journalctl --user -u
"castle-notify-waiter-*"`, and the record it concerns is in the unit
name. The random suffix is `make_id`'s trick, for `systemd-run`'s
sake: a name already taken is a hard failure, and a lost notification
would be a bad price for a tidier name.

### The gate, and what happens when it does not open

Three conditions, all cheap, none of them a subprocess:

1. `INVOCATION_ID` is set. systemd sets it on the processes of a unit
   it started and nothing else does, so it answers exactly the
   question being asked: is there an enclosing service whose cgroup we
   would be left behind in? A hand-run `castle route` sits in a
   session scope, which nothing re-runs and nothing sweeps.
2. `systemd-run` is on `$PATH`.
3. The user bus is reachable — `DBUS_SESSION_BUS_ADDRESS`, or
   `$XDG_RUNTIME_DIR/bus` existing as a socket, which is how sd-bus
   itself resolves it.

Fail any one and the caller gets its argv back and spawns the waiter
exactly as it did before this task: a working notification, and the
left-over-process line back with it. That is why `KillMode=process`
stays on the unit — see below.

The residual, stated rather than hidden: all three can hold and
`systemd-run` can still fail (a wedged manager, a refused scope). The
waiter then does not run, and that record's notification is lost.
It is not lost *silently* — `systemd-run` writes its own diagnosis to
the stderr it inherited, which is the sweep's journal. Closing that
gap properly would mean waiting on `systemd-run`'s exit status before
deciding whether to fall back, and not waiting is the one promise
`_fire_notification`'s docstring actually makes to the sweep. See the
judgment calls.

### `KillMode = "process"` stays

The brief this came from asked for an argument either way. The
argument for keeping it is that the fix is gated and the fallback is
real: when the gate does not open, the waiter is spawned into the
dispatch unit's cgroup exactly as it was before, and `KillMode` is
once again the only thing between it and a killed click handler.
Dropping it would make a fix that deliberately does not cover every
case load-bearing for every case. Its comment in
`modules/agent/default.nix` is rewritten rather than deleted: the
whole original argument is kept, with a new paragraph saying it is now
the fallback's safety net rather than the mechanism.

## The four constraints, and how each is met

1. **The hand-run path keeps working.** It is not merely preserved,
   it is untouched: with no `INVOCATION_ID` the helper is the identity
   function, and the argv `Popen` receives is byte-for-byte what it
   received before. No warning reaches the resident's terminal in the
   ordinary case, because in the ordinary case nothing is attempted.

2. **The waiter's stderr keeps travelling on the sweep's own file
   descriptor, and is filed in the journal under the waiter's own
   named scope.** That is the decision the source finding reserved,
   and it is two facts rather than one because the measurement above
   separates them: the descriptor cannot move (a scope has no
   `StandardError=` to move it with), and the journal name cannot
   stay (journald follows the writer's cgroup). Given that, the choice
   made here is to name the scope after the waiter and the record, so
   the message has an address a resident can be told:
   `journalctl --user -u "castle-notify-waiter-*"`. The cost, stated
   plainly: a warning that used to appear in the dispatch unit's log
   no longer does, and someone reading only that log will not see it.
   The alternative — a transient service with `--setenv` for
   everything the environment would otherwise lose, giving the same
   journal identity — is rejected in the section above for reasons
   that have nothing to do with stderr, and it would land the message
   in exactly the same place a named scope does.

3. **`test/desktop-loop/test.nix`'s notify assertion is updated so it
   still covers what it covered.** This is not hypothetical: the
   measurement above says the waiter's own warnings leave that unit's
   log, so the existing assertion would have kept passing while
   covering strictly less — the exact failure the source finding
   named. The existing unit-scoped assertion stays exactly as it is,
   guard included, because it still covers everything the sweep itself
   prints and it is the one with a positive `"dispatch: worked"`
   behind it. Added alongside it is the same absence question asked of
   the whole journal (`castle route:` and `castle notify-waiter:`,
   neither of which any healthy output contains), which is strictly
   stricter and is true wherever journald decides those bytes belong.

4. **An unclicked notification still costs one idle waiter until
   expiry.** Unchanged, and out of scope. This task moves that waiter
   into another cgroup; it does not shorten its life, and the notify
   channel is not redesigned.

## Verification plan

The deliverable of this task is the assertion, not the diff. The
behaviour change is a few lines; without a test, the regression
returns the next time someone reasons about this path.

`test/desktop-loop/test.nix` — the VM that boots the real desktop
stack and drives a real Sway session — gains, after its existing
notify block:

- **The waiter's scope, by name.** `journalctl --user -u
  'castle-notify-waiter-*'` must show the manager's "Started Castle
  notification waiter for <record>" line — the address this brief
  gives a resident for a waiter's own stderr, asserted rather than
  asserted-in-prose.
- **A live waiter, asserted first.** `pgrep -u resident -f 'castle
  notify-waiter'` must return at least one pid. This is the guard that
  keeps everything after it from being vacuous: with no waiter alive
  there is no left-over process for systemd to find either, and every
  "no such line" below would pass while covering nothing. It runs as
  root with a `-u resident` filter so the shell carrying the pattern
  in its own command line cannot match itself.
- **Each waiter's cgroup**, read from `/proc/<pid>/cgroup`: must not
  name `castle-dispatch.service`, must name a `.scope`. This is the
  behaviour change stated directly.
- **One more sweep, started synchronously** (`systemctl --user start
  castle-dispatch.service`), because the left-over check happens as a
  unit *starts* and finds the previous run's residue.
- **The user manager's own view of the unit**, read with
  `journalctl --user-unit=castle-dispatch.service` under `su`, because
  these lines are written by the manager *about* the unit
  (`USER_UNIT=`) and not by the unit's own processes
  (`_SYSTEMD_USER_UNIT=`), and because journalctl builds its
  user-unit matches around the calling uid. Two positive assertions
  guard the filter — one proving the unit's output is in view
  (`dispatch: worked`), one proving the manager's messages about it
  are (`Finished`) — and then: no `left-over process`.

What is deliberately *not* asserted is the finding's second line,
"Unit process N remains running after unit stopped". The manager logs
that when a unit stops with something still in its cgroup —
milliseconds after `_fire_notification` returns, in a real race with
`systemd-run` registering the scope. The fix wins that race in every
ordinary case and cannot be made to win it always without the sweep
waiting on the scope. Asserting on it would buy a rare, loud,
meaningless failure. `Found left-over process` carries no such race:
it is checked when the *next* sweep starts, two minutes later.

The no-Nix harnesses in `test/agent-loop/` exercise this path with
`CASTLE_NOTIFY_COMMAND` pointed at a stub, from a shell with no
`INVOCATION_ID` — so they take the identity path. `dispatch-test.sh`,
`run.sh` and `modal-headless-test.sh` were run against this change and
all three pass, which is evidence that the gate is closed where it
should be and no evidence at all about the scope.

The scope mechanism itself was checked directly, before the VM ever
runs it, with the probe recorded above: a transient user service with
`KillMode=process`, spawning a detached child with and without the
hop, on the reference host. That is where the `Found left-over
process` wording, the disappearance of it, and the journald
attribution result all come from. The reference host also has the
finding itself on record — fourteen `Found left-over process` lines in
three days, one of them naming `foot` rather than `python3`, which is
the click-handler half of the finding showing up exactly as described.

Human hands needed: one confirmation on the reference host after
deploy. Fire one errand that routes to notify, wait out two timer
ticks, and read `journalctl --user -u castle-dispatch.service`. What
should be gone is the pair of lines quoted at the top of this brief.
`systemctl --user list-units 'run-*.scope'` should show the waiter
under the description this task gives it.

## Judgment calls

Reported here because the source finding asked for them, and because
each is a place a reviewer could reasonably have chosen otherwise.

- **stderr stays inherited, and the journal entry moves anyway.**
  This is the decision constraint 2 reserved, and the honest version
  of it took a measurement to reach: the first draft of this brief
  asserted the entry would stay under `castle-dispatch.service`, which
  the probe recorded above disproves. What is chosen deliberately,
  once that is known, is to *accept* the move and spend a named scope
  making it addressable, rather than to fight it — by re-pointing
  stderr at a file, by having the waiter re-open the sweep's journal
  stream, or by giving up the scope and living with the finding. The
  accepted cost is stated in constraint 2: a reader of only the
  dispatch unit's log no longer sees a waiter's warning.

- **The gate is a precondition check, not an observed exit status.**
  A caller that waited ~0.5s on `systemd-run` could fall back exactly,
  and would cost the sweep half a second per notification on the
  healthy path to insure against a rare failure on the unhealthy one.
  `_fire_notification`'s contract is that it never blocks; buying
  robustness with the sweep's latency is the wrong trade, especially
  as the failure it insures against is loud in the journal rather than
  silent. A shell wrapper doing `systemd-run ... || exec ...` was also
  considered and is worse than either: the `sh` holding that `||`
  waits in the dispatch unit's cgroup, which is the exact process this
  task exists to remove.

- **`--quiet`, so nothing is logged on the happy path.** Without it
  `systemd-run` prints "Running scope as unit: run-pNNN-iNNN.scope" to the
  inherited stderr on every notification. Replacing two misleading
  lines per sweep with one uninformative one is not what this task is
  for, and the notify channel's documented shape is silence except on
  failure. The scope is still discoverable: `--description` gives it
  "Castle notification waiter for <record id>", which is what
  `systemctl --user list-units 'run-*.scope'` shows.

- **`--unit=`, with a random suffix, rather than letting systemd name
  the scope.** This one was decided the other way first, on the
  grounds that a name of our choosing has to be unique per waiter and
  a collision is a `systemd-run` failure — which is to say a lost
  notification in exchange for a prettier name. The measurement
  changed the weight on the other side: the name is where the waiter's
  stderr is filed, so an opaque `run-pNNN-iNNN.scope` means a warning
  nobody can be told how to find. Four hex characters of `os.urandom`
  make the collision impossible, which is the same answer `make_id`
  gives to the same question.

- **The scope's name is asserted, not just its existence.** The VM
  test reads `journalctl --user -u 'castle-notify-waiter-*'` and
  requires the description line to be there. That is a test of a
  documented address rather than of an implementation detail: if the
  naming scheme changes, the sentence in this brief telling a resident
  where to look is wrong, and the test should fail.

- **The whole-journal absence check is additive, not a replacement.**
  The unit-scoped assertion is kept because it is the one with a
  positive guard proving it read a real log; the wide one is kept
  because it is the one that stays true regardless of journald's
  attribution. Neither alone is both.

- **docs/tasks/done/0034's findings section is left alone.** It
  records what was true when that task landed, and it was: `KillMode`
  was needed and still is. The live comment in
  `modules/agent/default.nix` is where the current reasoning belongs,
  and it is rewritten there.
