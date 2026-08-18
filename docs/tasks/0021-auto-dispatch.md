# Task 0021 — Newly filed requests start themselves

**Before starting:** read `CLAUDE.md`, `docs/vision.md`, `docs/architecture.md`
in full (especially Records, The journal and the spool, Seats,
Provenance, Where runtime state lives, and Proposals 03/04/06/07),
`agent/README.md`, `docs/principles/01-open-by-construction.md` and
`02-the-resident-owns-the-configuration.md`. Then, closely: `agent/castle`
(the whole file, especially `cmd_work`, `cmd_route`, `cmd_validate`,
`RECORD_TYPES`, `FIELD_ORDER`, `write_record`, `spool_dir`),
`agent/castle-modal` (`_errand_state`, `run_status`),
`agent/castle-worker-claude`, `modules/agent/default.nix` in full, and
`modules/base/default.nix`'s password-reminder path-unit-plus-oneshot
(around the `systemd.services.castle-password-reminder-check` /
`systemd.paths.castle-password-reminder-check` pair). Also read
`test/agent-loop/run.sh`, `test/agent-loop/scripted-worker.sh`,
`test/agent-loop/modal-headless-test.sh`, `test/desktop-loop/test.nix`,
`.github/workflows/check.yml`, `.github/workflows/desktop-loop-test.yml`,
`docs/tasks/0015-filed-not-in-progress.md`,
`docs/tasks/0013-first-deploy-findings.md` (bug 2),
`docs/tasks/0008-agent-layer-skeleton.md`, `docs/tasks/0009-ambient-intake.md`,
and `docs/backlog/errand-resume-after-answer.md` (stays open — see
Non-goals). Work on branch `sprint/0021-auto-dispatch`; this brief rides
it. PR to `main`.

**Goal.** An eligible resident-requested errand begins on its own, with
no `castle work` or `castle route` typed by hand: the smallest reliable
mechanism that notices new work, invokes the configured worker tenant
exactly once at a time, and runs the existing router over whatever comes
back.

## Why

0009 built every piece of the loop except the one that starts it.
Intake writes a `request` record; a worker, if invoked, writes a
`result`; the router, if invoked, decides a channel. Both invocations
are, today, a human typing a command. `docs/tasks/0015-filed-not-in-progress.md`
found this the hard way: the status surface's fallthrough label read
"in progress" for errands nothing had ever touched, because on the
reference host nothing has ever touched them automatically. That task's
own non-goals named the deferred fix — "a started/claimed record type…
belongs with the first asynchronous worker" — and this is that task.

`docs/backlog/fire-and-forget-lives-in-the-harness.md` is the backlog
entry this brief promotes. Its complaint: the resident can fire off
work and be told only when it's done inside a vendor's coding-agent
session, and nowhere else — not because Castle Turing's architecture
forbids it, but because nothing in this repo currently dispatches. The
plumbing (`request` → worker → `result` → router → notify/digest)
already carries the promise; this task is what fulfils it for the one
worker contract that exists today (a `request` in, a diff and a
`result` out). The backlog entry's other open question — whether that
diff-producing contract is the general shape of a worker, given that
"many tasks a resident would fire off are not diffs" — is explicitly
not this task's to answer; it is refiled narrower in
`docs/backlog/worker-contract-generality.md`.

Three things have to be true for automatic dispatch to be safe rather
than merely convenient, and each drives a piece of the design below.
First, invoking the worker tenant is not free — it is a real model
call with real latency and, per `docs/architecture.md`'s Proposal 07,
a real cost multiplier if it ever runs concurrently with itself on the
same errand — so "once at a time" has to be a structural guarantee, not
a convention a future caller might forget. Second, a process that
starts a turn and dies before it finishes (a reboot, an
`XDG_RUNTIME_DIR` wipe, a crashed unit) must leave a legible trace, or
the resident loses the one thing this whole layer promises: a journal
that reads cold as a complete account. Third, whatever chooses which
request runs next has to be reconstructable from the journal alone —
Proposal 06's "the system may grade its own delivery; it may never
grade its own judgment" extends naturally to "the system may not
silently accumulate a dispatch policy nobody wrote down."

## Scope

### 1. The trigger — a user-level systemd path unit and timer backstop

New Nix option `castle.agent.dispatch.enable` (`modules/agent`,
`lib.types.bool`, **default `false`**). When enabled, `modules/agent`
declares four `systemd.user` units. The **path unit, the timer, and
the watermark oneshot** are `wantedBy = [ "default.target" ]`; the
**sweep service deliberately is not** — the path unit and timer
activate it. (The first version of this design wanted the sweep in
default.target too, and that was wrong: a `Type=oneshot` in
default.target's own activation path holds the user manager's startup
open for the entire sweep, up to `worker.timeoutSeconds` per eligible
errand, and buys nothing the 5s `OnStartupSec` timer does not already
deliver without blocking a login. The watermark oneshot added later is
in default.target precisely because that objection does not reach it:
one journal read and at most one record write is not a sweep.)

- **`systemd.user.paths.castle-dispatch`** — `pathConfig.PathChanged =
  "${cfg.stateDir}/journal"`, and **no `MakeDirectory`** (the first
  version of this design said `MakeDirectory = true`; see §2.2's
  state-directory guard for why that was wrong). systemd watches the
  nearest existing parent of a path that does not exist yet and fires
  when the path appears, so nothing is lost by not creating it. Fires
  on *any* new record landing in the journal, not just requests — see
  "Why a request-shaped watcher was rejected," below.
- **`systemd.user.services.castle-dispatch`** — no `wantedBy` (see
  above), `Type = "oneshot"`,
  `ExecStart` runs `castle dispatch` (the new subcommand, §2),
  `WorkingDirectory = "%h"`, and an `Environment=` block carrying
  `CASTLE_STATE_DIR`, `CASTLE_WORKER_COMMAND`, `CASTLE_NOTIFY_COMMAND`
  (if set), `CASTLE_WORKER_TIMEOUT`, and `CASTLE_REPO_ROOT` (if set) —
  see "Where the environment comes from," below. No `Restart=`: a
  oneshot that fails is a mechanism fault, not a retry candidate (§2.7).
- **`systemd.user.timers.castle-dispatch`** — `OnStartupSec = "5s"`,
  `OnUnitActiveSec = "1min"`. A backstop, not the primary trigger: the
  path unit should fire within moments of a request landing, but a
  missed inotify event (or a request filed while the user session was
  down) would otherwise wait forever. `OnStartupSec` is five seconds
  rather than a minute because a timer whose interval has already
  elapsed fires immediately on activation, so this value is really
  "how long after the user manager starts before the first sweep
  runs" — and a first sweep that soon is worth having for what it
  actually does: reap the turns a crash or a logout interrupted, and
  surface a waiting backlog promptly after login, without holding the
  login open while it happens. It has **nothing to do with the
  watermark any more**; see the watermark unit below and the
  correction recorded at the end of §2.2.
  `OnUnitActiveSec` is one minute, not five. This tick is the only
  thing that ever runs when an inotify event is missed, or when a
  request was filed while the session was down, and the price of
  either is total silence until the next tick. Five minutes of that
  reads badly against a mechanism whose whole promise is "filing is
  enough" — and it is what the VM test raced and lost, timing out at
  300s while waiting for a 5-minute backstop. A tick with nothing to
  do costs one journal read, one lock, and one log line; no model call
  is reachable without an eligible request.
- **`systemd.user.services.castle-dispatch-watermark`** — `Type =
  "oneshot"`, `wantedBy = [ "default.target" ]`,
  `ExecStart` runs `castle dispatch --watermark-only`,
  `WorkingDirectory = "%h"`, and an `Environment=` block carrying
  `CASTLE_STATE_DIR` and nothing else: this path runs no tenant and
  fires no notification, so it needs neither the worker environment
  nor the sweep service's `PATH` line (`castleCli` wraps its own
  python3). **It establishes §2.2's watermark at the instant the user
  manager starts**, which is what makes the boundary "filed before
  this dispatch-enabled session existed" rather than "filed before the
  first sweep happened to run." It runs before any compositor exists,
  so there is no window in which a human could file anything — there
  is nothing yet to file it with. The guarantee is a margin, not a
  systemd ordering edge: greetd launches the compositor as the session
  process, not as a user unit, so no `Before=` can be written against
  the thing that must lose. Milliseconds against seconds, plus a soft
  and visible failure mode if it ever lost anyway (§2.2).

**The service also sets `PATH`** — the second correction the VM test
forced. A systemd user manager hands its units a bare PATH containing
neither binary this sweep actually needs: the default tenant
(`agent/castle-worker-claude`) execs `claude` from `$PATH`, and
`castle route`'s notify channel shells out to `notify-send`. Both live
in the system profile on a host importing `modules/dev` and
`modules/desktop` respectively. Without it, enabling dispatch with the
*default* worker command writes a result saying the tenant could not
be run, and every notification the router fires is lost to a
non-fatal warning nobody reads — which would have quietly gutted the
one resident-facing half of this whole feature. The value is
`/run/current-system/sw/bin:/etc/profiles/per-user/%u/bin:%h/.nix-profile/bin`;
`%u`/`%h` are systemd specifiers, so no username is baked into this
repo. The VM test asserts the dispatch unit's journal carries no
"notify command … failed" warning — which proves `notify-send` was
found and ran, *not* that mako rendered anything a human saw; that
distinction is Proposal 06's receipt half, still unbuilt.

**All three carry `ConditionUser=!@system`** — a correction to this
design found by running `test/desktop-loop`'s VM against the first
implementation of it, not reasoned out in advance. `systemd.user.*`
units are declared for *every* user with a systemd instance, and on a
host importing `modules/desktop` that includes greetd's own `greeter`
system account: its manager started `castle-dispatch` at the login
screen, where the sweep exited 1 on a journal it has no business
reading (`Permission denied: …/state/journal`) and left a failed unit
in a session nobody inspects. Since §2.7 makes the sweep's exit code
mean "dispatch itself broke," a guaranteed-failing instance of it on
every boot is precisely the health signal a resident learns to ignore.
`!@system` is nixpkgs' own idiom here — the user-specific
`nixos-activation.service` carries the identical condition — and it
needs no username baked into this repo (Principle 02). Pinned by an
assertion in `flake.nix`'s dispatch variant, since losing it again
would be silent.

This is the first `systemd.user.*` unit in this repo — everything else
that uses the path-unit-plus-oneshot pattern
(`modules/base`'s `castle-password-reminder-check`) is a system unit,
because its job (reading `/etc/shadow`) needs root. Dispatch needs the
opposite: a **user** unit, for three reasons. `agent/castle`'s
`spool_dir()` resolves relative to `$XDG_RUNTIME_DIR`, which is a
per-login-session concept — a system unit would spool to
`/tmp/castle-0/spool` instead of the resident's real runtime directory.
`castle route`'s notify channel shells out to `notify-send`, which
needs the session's D-Bus/Wayland session bus to reach mako; a system
unit has no session to reach. And a user unit needs no username baked
into the public repo (Principle 02) — `systemd.user.*` units are
per-login-session by construction, with no `User=` to set.

**Deliberately no `loginctl enable-linger`.** Without lingering, the
user's systemd instance — and therefore these four units — runs only
while the resident is logged in, which is the honest lifetime for a
mechanism whose only externally visible output (today) is a desktop
notification: there is nothing for it to do while nobody is at the
keyboard to receive one. Enabling lingering so dispatch also runs
between logins is a separate authority decision (it changes what the
machine does when nobody is watching) and is out of scope — see
Non-goals.

**Where the environment comes from.** The service's `Environment=`
values are wired directly from the same `cfg.stateDir` /
`cfg.worker.command` / `cfg.notify.command` / `cfg.worker.timeoutSeconds`
/ `cfg.worker.repoRoot` this module already exposes, in parallel with
(not instead of) the existing `environment.sessionVariables` wiring —
sessionVariables still needs to reach interactive shells and anything
launched from inside the Sway session (a terminal, a manually-run
`castle work`). Concretely: the existing `environment.sessionVariables`
block (today carrying `CASTLE_STATE_DIR`, `CASTLE_WORKER_COMMAND`, and
`CASTLE_NOTIFY_COMMAND`) gains two more entries in this task —
`CASTLE_WORKER_TIMEOUT` (the stringified `cfg.worker.timeoutSeconds`,
unconditional, the same way `worker.command` already is) and, when
`cfg.worker.repoRoot` is non-null, `CASTLE_REPO_ROOT` — so a
`castle work` invoked by hand from a terminal inside the Sway session
gets the identical timeout guard (§3.3) and repo root that a dispatched
worker gets, not a weaker version of either. An earlier version of this
design assumed
`environment.sessionVariables` could not reach a systemd user unit at
all; that claim is **false** on this stack. `nixos/modules/security/
pam.nix` wires `pam_env.so` into the `systemd-user` PAM service's
session stack by default, and that module runs against
`/etc/pam/environment` the same way the greetd login path does (the
mechanism `docs/tasks/0013-first-deploy-findings.md`'s bug 2 fix
already established) — `systemctl --user show-environment` does show
`CASTLE_STATE_DIR` on a real login. The actual argument for `Environment=`
on the unit is **determinism**, not an inheritance gap: a value baked
in at `nixos-rebuild switch` reaches the unit immediately, with no
re-login required (PAM-set variables only take effect on the *next*
login that runs `pam_env`), and the unit stops depending on nixpkgs'
PAM-module wiring staying exactly as it is today. Say this in the code
comment; do not repeat the false "sessionVariables can't reach systemd
units" claim as the rationale — a future reader who checks it against
the PAM chain will find it wrong and distrust the rest of the comment
with it.

**New options** (`modules/agent`):

- `castle.agent.worker.timeoutSeconds` — `lib.types.ints.positive`,
  default `900`. A chosen value, not derived from anything — fifteen
  minutes is long enough for a real `claude -p` errand and short enough
  that a hung tenant does not silently occupy the worker seat for the
  rest of the day. Wired into `CASTLE_WORKER_TIMEOUT`.
- `castle.agent.worker.repoRoot` — `lib.types.nullOr lib.types.str`,
  default `null`. Wired into `CASTLE_REPO_ROOT`. The private flake's
  actual checkout path on disk is resident data (Principle 02) — this
  repo cannot guess it, the same reasoning `stateDir` already documents
  — so it cannot default to anything real here. Left `null`, a
  dispatched worker's `cmd_work` invocation still falls back to
  `pathlib.Path.cwd()` (the unit's `WorkingDirectory`, `%h` — the
  resident's home directory), which is very unlikely to be the repo a
  real tenant needs to operate on. Say this plainly in the option's own
  description, not just in this brief: an operator who enables dispatch
  without setting `repoRoot` is told the repo is their home directory.

**New assertion:** `castle.agent.dispatch.enable` requires
`castle.agent.stateDir != null`. Automatic dispatch is exactly the
situation where the journal has to be the durable, private-repo-tracked
one — the fallback path (`~/.local/state/castle`) would reproduce the
"configured path and fallback happen to coincide, so a test can't tell
them apart" blindness `test/desktop-loop/test.nix`'s `testStateDir`
comment already documents for bug 2b, except live on a real host instead
of caught in a harness. `castle.agent.worker.repoRoot` gets the same
literal-`"`-character assertion the existing three options already
carry (it rides `environment.sessionVariables` too, for the interactive
case) — copy the existing assertion's message shape.

**Minimal unit hardening**, with the reasoning in a comment rather than
left implicit: the worker tenant needs network (to reach the model
API), `$HOME` (its own config, credentials, whatever a real tenant
needs to read the repo), and the configured state directory. Anything
resembling `ProtectHome`, `PrivateNetwork`, or a restrictive
`ReadOnlyPaths` breaks the seat outright. `Type = "oneshot"` with no
`Restart=` is the only meaningful constraint applied, and it is a
correctness property (§2.7's exit-code contract), not a security one.
Over-hardening a unit whose entire job is running an unconstrained
model tenant is theatre: the actual containment this design relies on
is a code fact, not a systemd directive — `cmd_work` has no code path
that runs `nixos-rebuild`, `git commit`, or anything else that touches
a running system (Proposal 03's "the worker proposes, it never
deploys").

**Rejected alternatives:**

- **Intake spawning a worker inline** (i.e., `castle ask` or the
  modal's compose mode invoking `castle work` itself once it returns).
  Rejected because intake is deliberately judgment-free — "an intake
  adds no judgment; it captures the request and its provenance"
  (`docs/architecture.md`) — and deciding to spend a model call is
  judgment. It would also only cover the two intakes that exist today;
  `castle ask` from a script, a future mail intake, and a hand-written
  request record dropped straight into the journal would all still
  need a second, separate mechanism to notice them, defeating the point
  of having one.
- **A long-running daemon.** This is a pre-made decision from 0008,
  still quoted at the top of `modules/agent/default.nix`: "the router
  is a distinct invocable, not a resident process." The same argument
  applies to dispatch — a daemon is one more thing that can wedge,
  leak, or drift from what a human could reproduce by hand.
- **Timer-only, no path unit.** Costs latency for no benefit: the path
  unit is the house style for "notice a change, react promptly, with a
  timer as backstop" (`modules/base`'s password-reminder check already
  pairs the two), and a thirty-second-average delay between filing a
  request and it starting (with the one-minute backstop interval this
  design settled on) is a worse resident experience than the seconds a
  path unit gives for free.
- **Watching `*-request-*.md` specifically, instead of the whole
  journal directory.** This is the rejection most worth recording,
  because a request-shaped watcher would satisfy *this* task completely
  while quietly foreclosing the next one. `docs/backlog/errand-resume-
  after-answer.md` — filed as task 0023's territory, not this one's —
  is about to need dispatch to notice an `answer` record too, once
  something exists to resume an errand on. A watcher keyed to the
  filename shape `*-request-*.md` is structurally unable to fire on
  anything else; broadening it later means touching the systemd unit
  again, on every host that has it deployed. Watching the whole
  directory and deciding eligibility in code (§2.4) means 0023 can
  extend the *eligibility predicate* — a pure function over the
  journal — without touching the unit at all. The wakeup is a hint; the
  fold is the authority, and that split is what makes the predicate
  extensible later.

### 2. `castle dispatch` — a new subcommand in `agent/castle`

A subcommand, not a shell script embedded in the systemd unit. This
keeps it testable by the existing no-Nix harness
(`test/agent-loop/`), readable top to bottom the way every other seat's
hands are (`agent/README.md`'s framing of `castle`'s subcommands), and
runnable by hand by a human holding the dispatch seat, which is the
same "any seat can be held by a human" property every other subcommand
already has.

**One flag: `--watermark-only`.** It runs every guard below,
establishes §2.2's watermark if this journal has never had one, prints
that it is not sweeping, and returns 0 — no reaping, no worker turn,
no routing. It exists so §1's `castle-dispatch-watermark` unit can put
the dispatch boundary down at user-manager start without any of the
cost that keeps the sweep service out of `default.target`. It is
deliberately a flag on `dispatch` rather than a subcommand of its own:
it is the same fold over the same journal behind the same guards,
stopping early, and a separate subcommand would invite the two to
drift apart on exactly the question they must agree on.

The sweep, in order:

**2.0 — Two refusals before any of this runs.** The sweep declines to
start at all in two states, both added after review, both exiting
before anything is created or written. First, when
`castle.agent.stateDir` does not exist on disk (§2.2's restore-order
guard) — exit **0**, the machine is simply not ready. Second, when
`runtime_dir()` resolved to its `/tmp/castle-$UID` last resort (no
`XDG_RUNTIME_DIR`, no `/run/user/$UID`) — exit **1**, because an
unattended sweep must not make liveness decisions on locks in a
world-writable directory. Any local user can create that path first
and hold the sweep lock, at which point dispatch reports "another
sweep is already running" and exits 0 forever, staying green in
`systemctl --user status` while nothing ever runs; squatting a
per-request lease instead makes the reaper decline to reap, or makes a
sweep read a live turn's lease as free. A hand-run `castle work` keeps
the `/tmp` fallback deliberately — a human is present to notice
something strange — and nobody is watching a timer.

**2.1 — Global sweep lock.** `flock(LOCK_EX | LOCK_NB)` on
`$XDG_RUNTIME_DIR/castle/dispatch.lock`. If held, print a short message
and exit `0` — another sweep is already running, this is not an error.
The lost-hint window this leaves (a request filed after the running
sweep's last fold but before it exits) is bounded by the timer
backstop (§1), and the docstring says so. **Why this lock has to
exist**, spelled out because it is easy to think the per-request lease
in §3 already covers it: the lease plus the eligibility fold (§2.4)
together guarantee a given request is worked *at most once by a live
process at a time* — they do not guarantee two concurrent sweeps can't
both decide, in the same instant, that the same request is eligible
and both start racing for its lease. One would win the lease and run;
the other would lose it and skip — the *result* is still correct
(§3.1's lease is exclusive), but the two sweeps would otherwise
duplicate work re-scanning and re-deciding the same fold concurrently
for no benefit, and — importantly — `castle work` itself deliberately
has no built-in refusal to run twice on a request that already has a
`result`: **that IS the hand-retry path** (a resident typing
`castle work <id>` again after a failure). Without a sweep-level lock,
two dispatch sweeps racing at the boundary between "sweep A just wrote
a result" and "sweep B's fold snapshot was taken before that write"
could both dispatch the same request as its own separate turn. The
sweep lock removes that race by construction: sweeps are serialized,
full stop.

**2.2 — Watermark.** If no `decision` record with `seat: dispatch` and
a `watermark:` field exists anywhere in the journal, write one. The
*normal* writer is §1's `castle-dispatch-watermark`, running
`castle dispatch --watermark-only` at user-manager start; a full sweep
does the same find-or-write as a backstop, for a journal that appears
mid-session. Either way the record is identical:
`type: decision`, `seat: dispatch`, `provenance: initiated`, and —
this is the load-bearing part — **`refs` listing, by id, every
`request` record with no `result` at that instant**. *Not* "and
nothing running on it": the first implementation skipped
currently-leased requests, which left a hole in the watermark's own
promise — a pre-dispatch request a resident happened to be working by
hand during the very first sweep was omitted from the exclusion list,
and if that hand turn then died before writing a result, the request
passed every eligibility condition afterwards and was started
automatically. Naming it costs nothing in the other direction: a
hand-worked request that finishes has a result, and a result bars an
automatic attempt regardless of any list. `evidence` names the timestamp and that count; a
machine-readable `watermark: <timestamp>` field (UTC, `CREATED_FMT`)
rides along as the thing `_find_watermark` recognises the record by,
and as an honest statement of when dispatch began. The body explains,
in prose, that the requests named in its own `refs` are the ones not
auto-dispatched, and that they remain runnable by hand with
`castle work <id>`.

**The sweep refuses to run at all until the state directory exists.**
Before anything else — before `journal_dir()` can create it — the
sweep checks `castle.agent.stateDir` on disk, and if it is absent
prints `state dir <path> does not exist yet (private repo not
restored?); nothing to do` and exits **0**, leaving the timer to try
again. This closes a restore-order hazard the first version of this
design walked straight into: a resident enables dispatch and rebuilds,
the units start within seconds, and the private repo holding their
journal has not been cloned onto the machine yet. The sweep would
create `<stateDir>/journal` itself (the path unit's `MakeDirectory`,
and `journal_dir()`'s own mkdir), write a watermark with **empty
refs** — nothing outstanding, because nothing exists — and then the
real journal restored ten minutes later would arrive into a world
where dispatch had already declared that nothing predates it. Every
request in that restored history becomes eligible: the exact outcome
§2.2 exists to prevent, produced by §2.2 itself. The pre-created
directory also breaks the clone that was about to happen. Exit 0 and
not 1 because a machine that is not ready yet is not a mechanism
fault. An existing state directory is the documented resident contract
(`docs/private-layer.md`: `stateDir` points into an already-cloned
private checkout), and `test/desktop-loop` now supplies one via
`systemd.tmpfiles.rules` rather than relying on a unit to conjure it.

*Exclusion is by name, not by timestamp, and the first version of this
design got that wrong.* It said eligibility rule (d) was
`created >= watermark`. `created` has whole-second granularity, so a
request filed at 12:00:00.9 whose arrival woke the very first sweep at
12:00:01.0 landed on the wrong side of its own watermark and was
excluded **forever**, with no explanation anywhere — and on a fresh
host that is the single most likely thing to happen, since the first
sweep is usually triggered by the first request. Naming the excluded
set removes the class of bug instead of narrowing the window: anything
not on the list is eligible, however close to the boundary it was
filed.

*Where the boundary actually sits, and the correction that put it
there.* The boundary is **"filed before this dispatch-enabled session
existed,"** established at user-manager start by
`castle-dispatch-watermark` (§1) — before any compositor exists, so
before the resident has anything to file a request *with*. The sweep's
own find-or-write stays as the backstop for the one case that unit
cannot cover: a private repo restored mid-session, into a state
directory the unit found absent and rightly declined to touch. The
path unit fires the moment that journal lands, so the sweep's write
follows the restore by moments.

*The mid-session backstop is a convenience, not a guarantee, and
saying otherwise would be the same overclaim this section already had
to retract once.* The path unit fires on the **first file** to land,
and a restore is not atomic: git checking out objects, or rsync
walking a tree, populates `journal/` incrementally. A watermark
written partway through freezes its `refs` around whatever had arrived
by then, with two consequences. History that lands afterwards is not
excluded by it. And a `request` file copied before its own `result`
file reads as outstanding at that instant, so a long-closed errand can
look eligible and be picked up. A `stateDir` pre-created outside the
documented contract has the same shape one step earlier: the
session-start unit finds an empty journal, writes an empty-refs
watermark, and every record restored afterwards arrives on the wrong
side of it.

**Quiescence gating was considered and rejected.** Waiting for the
journal directory to be quiet for N seconds before writing the
boundary trades one bug for a worse one: the wait runs exactly while a
resident may be actively filing, so a request filed during it lands
before the watermark and is excluded by name — the filed-then-excluded
failure this entire section exists to close, reintroduced in the
restore path. Checking a manifest for completeness instead needs a
journal-sync design (what a complete journal *is*, who publishes that
fact) that this task deliberately does not do, and inventing half of
one here would be worse than naming the limit. So the limit is named,
and the fix is an order of operations documented where a resident
meets it (`docs/private-layer.md`): have the private checkout in place
before the first dispatch-enabled login, or leave dispatch off until
the first restore has finished.

The residual is therefore two shapes, both narrow, both soft. The
partial-restore one above; and the out-of-contract one where
`stateDir` is absent at session start (so the watermark unit exits 0
with nothing to mark) and the first-ever record in that journal is a
request the resident files by hand in a way that itself creates the
directory tree. Neither is silent: an excluded request is named in the
watermark's `refs` and appears on the status surface labelled "not
started automatically (predates dispatch) — `castle work <id>` to run
it", and an errand picked up wrongly still gets exactly one attempt,
recorded, routed, and visible. Nothing is lost or deleted; what is at
stake is a model call spent on an errand the resident had considered
finished.

*What was considered and rejected in moving that boundary:*

- **Comparing each request's `created` against the user manager's
  start time.** Reintroduces the whole-second-granularity timestamp
  comparison this same section already invalidated once — the exact
  bug that made exclusion by name necessary — and derives the boundary
  from a systemd internal, which is an illegible mechanism for a
  journal whose premise is that a cold reader can reconstruct every
  decision from the records themselves.
- **Writing the watermark from the filing path** (`castle-modal`,
  `castle request`). The filing path cannot know whether dispatch is
  enabled on this host — the option lives in the module, the filer
  runs from a session that never reads it — and a dispatch-seat
  decision does not belong in the filing seat's code regardless.
- **Making the VM test wait for the watermark before filing.** This
  was the tempting one, and it is the failure this task exists to
  stop: it pins the bug as intended behaviour and turns a check that
  caught a real product defect into a check that verifies nothing. The
  test's fast filing is the mechanism under test.
- **Claiming a structural `Before=` ordering against the compositor.**
  There is nothing to order against: greetd launches the compositor as
  the session process, not as a user unit, so no ordering edge exists
  between it and a `systemd.user` service. The honest statement is a
  margin — a oneshot at user-manager start against a human login plus
  a keystroke, milliseconds against seconds — plus the soft, visible
  failure mode above.

*This section's earlier "the residual shrinks to nothing in practice"
claim was falsified by the VM test, and the same PR that ran it moved
the boundary.* The numbers, from the run that failed: user manager up
at ~50.4s, the resident's request filed at ~51.7s, the first sweep at
~56.4s. A graphical login plus one modal keystroke beats a 5s
`OnStartupSec` comfortably, so on every fresh-journal run the request
that woke dispatch was named in the watermark's own refs and excluded
by name forever; the sweep printed `dispatch: nothing eligible`, the
path unit had no future event to fire on, and the test timed out
racing the (then five-minute) timer backstop. That is a product defect
on any fresh host, not a test artifact. Briefs ride their branch and
nothing else corrects one the work has overtaken, so the correction is
recorded here rather than left in a PR description.

This is journal-resident, not a
machine-local marker file, because a machine-local watermark is
invisible to a cold reader of the journal — the entire premise of this
layer — and would be silently lost on a reinstall, which is exactly
the failure the architecture doc's "Where runtime state lives" section
exists to prevent for everything else durable.

*The five durable-data questions, for the watermark decision:*
(1) **Durable?** Yes — it is the one fact nothing else in the system
can ever recover: the instant dispatch started existing on this
journal. (2) **Reconstructable from anything else?** No — once written
it is the *only* record of that boundary; a later reader has no other
way to tell "filed before automatic dispatch existed" from "filed
after but somehow never picked up." (3) **One record, prose body,
readable cold?** Yes — a single decision record with a plain-English
body. (4) **Observation or judgment?** An observation: "dispatch began
existing at this moment, and these exact requests were outstanding
when it did." It judges nothing about those requests. (5) **Needed now?** Yes — every
subsequent sweep's eligibility fold (§2.4) depends on it existing.

**2.3 — Reap interrupted turns.** For every `claim` record no result
accounts for — where "accounts for" has two clauses, both in the
shared `closing_result` helper: (a) a result whose `refs` name the
claim (every worker result and every reaped result does), or (b) a
result that names the claim's *request*, names no claim of that
request at all, and is newer than the claim. Clause (b) is the
human-seat-holder shape, added after review: a resident whose
`castle work R` crashed finishes the errand with
`castle record --type result --refs R` — the spelling the CLI implies
— and without it the next sweep wrote a permanent `interrupted`
contradicting the result the resident had just filed, fired a second
notification about it, and the status surface masked that closure
forever. It also covers every result written before this task. The
exclusion inside (b) is what keeps per-turn accounting intact, and the
counterexample is concrete: a reaper's own `interrupted` for old claim
A lands with the newest id in the journal, and must not thereby close
a still-open claim B.

*Which claims that exclusion is drawn from is derived inside
`closing_result`, not supplied by the caller, and a review pass is why.*
Both were caller-supplied, and the two callers supplied different
sets — the reaper every claim in the journal, `castle-modal` only the
claims in one errand's transitive fold. A resident closing a crashed
errand with `castle record --type result --refs R1,C2`, where `C2` is
some other errand's claim (an easy copy-paste), then landed on
opposite sides of the exclusion: the modal showed the errand closed,
the reaper wrote a permanent `interrupted` over it. That is exactly
the disagreement this helper's existence is supposed to make
impossible, so the narrowing moved inside it — only claims of *this
claim's own request* count, keyed by `refs[0]` the way the reaper
keys claims to errands. Callers may now pass any superset and get the
same answer. Then: probe the per-request lease
(`$XDG_RUNTIME_DIR/castle/leases/<request-id>.lock`,
`flock(LOCK_NB)`). Lock held → a worker is running right now; skip it.
Lock acquirable, or the file is simply absent (the normal case after a
reboot — `$XDG_RUNTIME_DIR` is wiped) → the turn was interrupted:
**under the acquired lock**, re-check that no `result` has appeared in
the meantime (a benign race with a turn finishing between the probe
and the acquisition), then write a `result` record with
`outcome: interrupted`, `seat: dispatch`, provenance inherited from the
original request, `refs: <request-id>,<claim-id>`, and a body stating
the claim's recorded start time and that no process ever completed the
turn.
**Leave the stale lease file where it is** — an earlier version of this
design said to remove it, and that was wrong: unlink is not atomic
against an acquirer that already opened the old path, so it
reintroduces exactly the race the rest of this design avoids (one
process holding a lock on an unlinked inode while the next creates a
fresh file and locks that). An unheld lease file means nothing on its
own, and the runtime directory is wiped at reboot regardless. The journal is the authority
here; the lease is only ever a liveness probe, never the record of
what happened.

*A second accepted limit, inherited rather than introduced:* the lease
is **machine-local**, so dispatch assumes **one host per journal**. Two
dispatch-enabled machines sharing a synced private repo would work the
same request twice and write false `interrupted` results at each
other, because nothing reconciles two dispatchers over one journal.
Not solved here and deliberately not papered over with a mechanism:
journal sync does not exist yet, and whatever task designs it inherits
this. Said in the option description and in `docs/private-layer.md`
where a resident will actually meet it — enable on at most one host.

*One accepted limit, stated rather than engineered around:* a worker
deliberately outliving its login session (`nohup castle work …`, or
one left running in tmux after logout) loses its lease without losing
its life — systemd removes `/run/user/$UID` at session end, taking the
lock file with it — so a later sweep can write `interrupted` for a
turn that is still working. It is accepted because surviving logout is
outside this mechanism's stated lifetime: the units are
`WantedBy=default.target` with no lingering (§1), which draws the same
boundary on purpose. And the live turn still writes its own result
when it finishes, so the journal carries both accounts rather than
losing one — two visible, contradictory records a resident can read
beat one confident wrong one.

**A note on what "probing" actually means**, since both this reaper and
`_errand_state`'s live-lease check (§4) do it: a probe is a nonblocking
acquire immediately followed by a release, purely to test whether the
lease is currently held by someone else — which means the probe itself
briefly *holds* the lock while it checks. That opens a narrow window
where a probe (a reaping sweep, or the modal's status fold) could
contend with a hand-run `castle work` launched at almost exactly the
same instant, and the human's `castle work` could lose that race and
see the lease as momentarily held. This is accepted, not engineered
around: the resulting refusal is loud (`castle work`'s existing
"already holds this errand's lease" message, §3.1), an immediate retry
succeeds because the probe released the lock in microseconds, and a
second locking protocol solely to make probes non-contending is not
worth the complexity for a window this narrow. Say so in the code
comment — an implementer who doesn't will be tempted to invent
something more elaborate than this design calls for.

**2.4 — Eligibility fold.** This is the authority the wakeup (§1) is
only a hint for. A request is eligible iff:

- (a) `type: request`;
- (b) no `result` record references it (this is what makes the whole
  design idempotent, and the retry bound structural rather than
  counted — see §3's "Retry policy");
- (c) no `claim` record referencing it currently holds a live lease
  (i.e., it is not running right now). *Implemented as a probe of the
  request's own lease rather than a walk over claim records: the lease
  is acquired strictly before the claim is written (§3.2), so a held
  lease is the earlier and strictly stronger signal — it also catches
  the sliver of a turn between "lease taken" and "claim written," which
  a claim-keyed check would read as eligible.*
- (d) it is not named in the watermark record's `refs` (§2.2 — the
  exclusion is a list of ids, deliberately not a timestamp comparison);
- (e) it carries no `filed-during-turn` field — i.e. no worker tenant
  filed it while its own turn was running.

*(e) is the one condition here that bounds spend rather than
correctness, and it was added during implementation because the sweep
turned out not to terminate without it.* The one-automatic-attempt
rule (b) is per request, and that bounds unattended spend only while
the **supply** of requests is outside the tenant's control. It isn't: a
tenant that notices a second problem while fixing the first files it
the sanctioned way — `castle ask`, the same intake any seat uses — and
each filed request is a fresh errand with its own fresh automatic
attempt. Observed, not theorised: one sweep ran five turns off a single
resident request, holding the global dispatch lock throughout.

The stamp is applied in `write_record` rather than in `cmd_ask`,
because a tenant files with whatever hands it has (`castle ask`,
`castle record --type request`, anything else that ends up writing a
record) and a stamp at one entry point is simply avoided by using
another; `write_record` is the choke point every written record
passes through. Its value is the running turn's `claim` id, carried to
the tenant in `CASTLE_WORKER_CLAIM` on the tenant's environment only —
never on the dispatcher's own — and inherited by anything the tenant
runs. The tenant neither sets it nor knows it exists.

It is a **mechanical observation, not a judgment**: "this request was
filed while that turn was running" is a fact about who was executing
at write time, and it says nothing about whether the work is worth
doing. So the request stays an ordinary request — it appears in the
status surface like any other, and `castle work <id>` runs it. What
the stamp removes is only the *automatic* attempt: the chain is
severed at generation one, and whether a tenant's follow-up work
happens goes back to being a human decision, which is where a
cost-and-authority question of that shape belongs.

Deliberately **not** conditions on eligibility, each recorded here with
its reason so a future reader does not "fix" the omission:

- **Provenance.** An `initiated` request is still work that needs
  doing — provenance decides the delivery *channel*, never whether the
  errand runs (`docs/architecture.md`'s Provenance section is explicit
  that this field is the router's input, not the worker's).
- **An unanswered `question` on the errand.** This is exactly the
  errand-resume problem `docs/backlog/errand-resume-after-answer.md`
  names and task 0023 owns. Dispatch does not resolve it; see Non-goals.
- **Age beyond the watermark, in the other direction** — i.e., there is
  no upper bound or staleness cutoff. A request filed a week ago that
  nothing has yet picked up is exactly as eligible as one filed a
  minute ago; the dispatch loop (§2.5) processes oldest-first, so it
  gets there.

**2.5 — Dispatch loop.** Oldest eligible request first (ids sort
chronologically by construction), one at a time, with no concurrency
cap — see the rejected alternative below. Each dispatch calls the same
in-process worker-turn function `cmd_work` uses (refactored so
`castle dispatch` and `castle work <id>` share the actual turn logic
rather than one shelling out to the other); if the per-request lease
(§3.1) is already held by the time this particular request is reached
— a narrow race with a human running `castle work` by hand
concurrently — that is a skip, not an error. The loop **re-checks the
eligible set and keeps going until it is empty** before returning
control to the sweep's tail step, rather than processing one static
snapshot: a request filed *during* a sweep (the path unit re-fires, but
this sweep is still running and holds the sweep lock) is caught by this
loop on its next iteration instead of being stranded until the next
wakeup.

*Rejected: a concurrency option* (e.g., "dispatch up to N errands at
once"). A frontier-model tenant makes parallelism a cost multiplier,
not a throughput win the way it would be for cheap deterministic work.
Adding a knob for it now, before any evidence that serial dispatch is
actually a bottleneck, fails durable-data question 5 (`agent/README.md`'s
own standard for `considered`/`propensity`: don't add a field, or here
a knob, before there's a real use for it) — and per Proposal 07, "the
seat holds the simplest tenant that suffices," escalation to more
machinery is a justified choice, never a default.

**2.6 — Tail: exactly one `castle route` invocation**, over the whole
journal, once, after the dispatch loop empties. *Routing now runs
under a blocking lock on `route.lock`* — added after review, and it is
this task that makes it necessary: the router had exactly one invoker
(a human typing the command) until a sweep began running it
unattended, so nothing could race it before. A resident typing
`castle route` at the wrong instant would otherwise have their fold
and the sweep's both see a record as unrouted, both append a decision
for it, and both fire a notification. Blocking rather than skipping,
because the fold is fast and idempotent and a person who typed the
command wants it to have run when it returns. **Lock order, stated
once:** the sweep takes `dispatch.lock` first and `route.lock` second,
and nothing anywhere takes them in the other order. `cmd_route` is already
a whole-journal, idempotent fold (`agent/README.md`: "run it again over
an already-routed journal and it does nothing") — invoking it once per
dispatched errand would buy nothing beyond N times the work. A useful
side effect worth stating explicitly, since it is easy to read the
design as "dispatch only routes what it just worked": because the path
unit fires on *any* journal change (§1), a result written by a
hand-run `castle work` invocation (a human holding the worker seat
directly) also gets routed by the very next dispatch sweep, with no
special-casing anywhere. Corrections remain unrouted by construction —
`cmd_route`'s existing refusal to walk `correction` records is
untouched — and the new dispatch test suite asserts this stays true
under automatic triggering, not just under a hand-run `castle route`.

**2.7 — Exit code.** `0` whenever the sweep ran and recorded outcomes
for whatever it found — including errands that themselves failed
(failure is visible via the `outcome` field, §3.5, the router, and the
status surfaces, §4; it is not a *mechanism* failure). Nonzero is
reserved for mechanism faults: an unreadable journal, a watermark that
cannot be written or read back, **and a worker tenant that cannot be
started at all** (§3.4's three paths — empty command, unparseable
command, `OSError` on exec). That last one was added after review, and
it also *stops the sweep*: the errand it was attempting still gets its
bounded `outcome: failed` result, but the fault is in the environment
rather than the errand, and it is the same environment every other
eligible request would meet. A sweep that shrugged and carried on
would spend the one automatic attempt of the entire queue on a single
transient fault — a store path swapped mid-rebuild, a broken `PATH` —
and exit 0 while doing it. Aborting caps the damage at one errand per
sweep and makes the unit's health signal say what is actually wrong.

*The abort runs the router before it returns, and that is load-bearing
rather than tidy.* Review caught this path leaving by a door that
skipped the sweep's tail `route_journal()`, so the one record that
says "your tenant is broken" sat in the journal unrouted and
unnotified — while the timer came back a minute later and burned the
next request's single automatic attempt in the same silence. The burn
itself is by design and is bounded (one attempt per request, ever);
being *quiet* about it is not, and the two together turn a broken
tenant into a queue that de-automates itself with nothing to show for
it. Routing here makes every burn produce its notification
immediately, so a misconfigured tenant nags within minutes instead.
The routing is best-effort and cannot change the exit code: a router
failure must not overwrite the mechanism fault this path exists to
report, and `route_journal` is an idempotent whole-journal fold, so
anything it misses the next sweep picks up. Note that
an unparseable `watermark:` *timestamp* is no longer one of them —
once exclusion moved to `refs`, nothing reads that field except
`_find_watermark`, so a cosmetically mangled value is not a reason to
refuse to start anything. This is what keeps the unit's own
`systemd --user status` failed-state meaning "dispatch itself broke,"
never "an errand the tenant attempted didn't go well" — conflating the
two would train the resident to distrust the unit's health signal
within the first bad model response.

**2.8 — Self-retrigger, and why it terminates.** The sweep writes
records (the watermark on first run, results, decisions) into the very
directory the path unit watches, so finishing a sweep re-triggers the
unit. The second cycle finds the eligibility fold empty (every request
it just worked now has a `result`) and writes nothing — so there is no
third cycle. The dispatch test suite (§7) asserts this directly: run
two sweeps back to back and assert record counts are stable after the
second, not just "the process exits."

**2.9 — No per-errand decision record.** This will read, to a reviewer
who has internalized Proposal 04 ("every decision any seat makes is an
appended, inspectable record"), as a gap — surely *choosing* to
dispatch request X is a decision? It is deliberately not treated as
one, and the argument has to be made explicitly or the omission looks
like an oversight. Dispatch chooses nothing: which request runs next
is a **total function of the journal** (§2.4's fold plus §2.5's
oldest-first order), reconstructable exactly by re-running the fold
over the same journal snapshot. A decision record's entire value is
carrying reasoning and evidence that could have gone another way; a
record that would carry identical evidence text on every single
invocation, forever, is exactly the "ritual" `docs/architecture.md`'s
Proposal 06 weak-point paragraph already warns about for the router's
own provenance-only decisions ("a required field with one constant
value is still ritual on those records"). The one exception is the
watermark (§2.2): it records a fact — the instant dispatch began
existing — that genuinely cannot be recovered any other way, which is
exactly the durable-data test a routine "I picked X because the fold
said X" record would fail.

### 3. Changes to `castle work` (`cmd_work`, `agent/castle`)

**3.1 — Per-request lease.** Immediately after request validation
(record exists, is type `request`) and before anything else,
`cmd_work` acquires `flock(LOCK_EX | LOCK_NB)` on
`$XDG_RUNTIME_DIR/castle/leases/<request-id>.lock`. If held, print "a
worker already holds this errand's lease" and return `1` **without
writing any record** — nothing began, so nothing should look like it
did. The lease file's content is informational only (start timestamp,
request id, the tenant command string) — the durable account of what
happened lives in the `claim` record (§3.2), not here. This lives in
`cmd_work` itself, not only in `castle dispatch`, because a guarantee
that only holds for callers who remember to take it is not a
guarantee — a human running `castle work <id>` by hand, concurrently
with a dispatch sweep reaching the same request, must be refused the
same way a second dispatch sweep would be.

*Which directory that is matters more than it looks, and the first
implementation got it wrong.* `spool_dir()`'s existing resolution falls
straight from `$XDG_RUNTIME_DIR` to `/tmp/castle-$UID`, and copying it
here meant the lock's **namespace** depended on the caller's
environment: `XDG_RUNTIME_DIR` is unset in exactly the contexts most
likely to run `castle work` beside a dispatch unit — ssh, cron, `su` —
so a hand-run turn took a lock in `/tmp` while the unit took one under
`/run/user`, and the two did not exclude each other at all. Reproduced:
a sweep wrote a false `interrupted` result over a turn that was still
running. The resolution is now `$XDG_RUNTIME_DIR`, then
`/run/user/$UID` **if it exists** (the path systemd's own user manager
sets `XDG_RUNTIME_DIR` to, so every caller on a host with a user
manager lands in one namespace), then `/tmp/castle-$UID` — and if
`/run/user/$UID` does not exist there is no user manager, hence no unit
to diverge from.

`flock` on a plain file, not a PID file with a manual staleness check:
a stale `flock` is detectable race-free by the next acquirer (the
kernel releases it the instant the holding process exits or dies, for
any reason, including a crash) — a PID file needs a second mechanism
(check `/proc/<pid>`, race against PID reuse) to answer the same
question. The lease lives in `leases/`, a new sibling of `spool/` under
`$XDG_RUNTIME_DIR/castle/`, and is explicitly **not** a spool record
and **not** a `RECORD_TYPES` entry: `RECORD_TYPES` is schema forever —
every entry is a durable commitment about what the journal can contain
— and the fact "a worker currently holds this lease" is an ephemeral
liveness fact with the lifetime of a login session, not a message any
seat is communicating to any other. It is a lock, not a record.

**3.2 — Durable `claim` record.** New, seventh entry in `RECORD_TYPES`.
Written immediately after the lease is acquired, before the tenant
command is even resolved or run: `type: claim`, `seat: worker`,
provenance inherited from the request, `refs: <request-id>`, body
naming the tenant command string and the start time. No new required
frontmatter field beyond the six every record already carries — the
tenant/start information lives in the body, same as any other record's
account of itself.

Because the lease is acquired *before* the claim is written, there is
no window during a healthy turn where a claim exists with no live
lease behind it. That ordering is what makes three states cleanly
distinguishable across a restart: **claim + live lease** = a worker is
running this errand right now; **claim + no live lease + no result** =
the turn was interrupted and is recoverable (this is exactly what §2.3
reaps); **no claim at all** = nothing has ever touched this errand.
This is 0015's deferred question — "a started/claimed record type…
belongs with the first asynchronous worker" — answered in the
affirmative; cite that task's non-goals line directly in the code
comment so a reader of 0015 who followed the pointer here finds the
answer immediately. The reason for the record is **observability
across a restart, not mutual exclusion** — the lease already provides
exclusion, cheaply and for free from `flock`'s own semantics. A
lease-only design (no durable record at all) was considered and
rejected on exactly this point: the lease dies with `$XDG_RUNTIME_DIR`
at reboot, so an interrupted errand would become **indistinguishable
from an untouched one** — silently eligible again, an unlogged second
automatic attempt at the exact failure mode this whole task exists to
avoid, and the "interrupted" state a resident needs to see in the
status surface (§4) would simply not exist to show.

*The five durable-data questions, for the `claim` record:*
(1) **Durable?** Yes — once the lease dies (reboot, crash, a wiped
`XDG_RUNTIME_DIR`), the claim is the *only* surviving evidence a turn
ever began. (2) **Reconstructable from anything else?** No — nothing
else in the journal or on disk records that a worker started this
errand at this time. (3) **One record, prose body, readable cold?**
Yes. (4) **Observation or judgment?** An observation — "a turn began at
timestamp T, running command C" — never a claim about whether that was
the right thing to do. (5) **Needed now?** Yes — §2.3's reaper reads it
on the very next sweep after any interruption; without it, reaping has
nothing to reap.

`castle record --type claim` is **explicitly permitted** through the
generic writer — unlike `correction`, which `cmd_record` refuses
outright (see the existing comment in `cmd_record` for why correction
is special: it is verbatim resident speech with guarantees only
`file_correction()` can honor). A claim is a mechanical observation,
not resident speech, so none of that reasoning applies: a human holding
the worker seat by hand must be able to write one the same way any
other seat's hands can, and the new dispatch test harness plants one
directly to simulate an interrupted turn (§7) without needing a real
process to actually crash mid-flight.

**3.3 — Timeout.** Read from `CASTLE_WORKER_TIMEOUT` (seconds); an
unparseable value warns on stderr and falls back to the 900-second
default (same tolerant-parse-with-a-warning shape `CASTLE_NOTIFY_COMMAND`
already uses for `shlex.split` failures). Implemented with
`subprocess.Popen(..., start_new_session=True)` followed by
`communicate(timeout=...)`; on `TimeoutExpired`, kill the **entire
process group** with `os.killpg(pgid, signal.SIGKILL)`, not just the
direct child — `claude -p` and similar tenants spawn their own
subprocesses, and killing only the immediate child leaves those running
with the diff file potentially still being written. After the kill,
write the result as usual with `outcome: timeout` (§3.5), reading
whatever is in `$CASTLE_DIFF_FILE` as-is and noting in the body that it
may be partial.

**`CASTLE_REQUEST_BODY` is removed from the tenant's environment.** A
contract cleanup, found by review and verified: the variable has been
listed since 0009 and is read by nothing — the body's channel is
stdin, which every tenant in this repo actually uses — while putting
it in the environment silently capped a request at the kernel's
`MAX_ARG_STRLEN`. A body around 200KB made `execve` fail `E2BIG`,
which `cmd_work` then recorded as "check that the command exists and
is executable", the wrong cause entirely, while consuming that
request's one automatic attempt. A channel nothing reads is not worth
a size limit nobody documented. `$CASTLE_REQUEST_ID`,
`$CASTLE_DIFF_FILE` and `$CASTLE_REPO_ROOT` are unchanged.

**A tenant's output encoding is not part of the contract.** Both
decoding paths — `Popen(text=True)` and the read of
`$CASTLE_DIFF_FILE` — are lenient (`errors="replace"`). Found by
review, verified by execution: one byte that is not valid UTF-8 (a
tenant that `cat`s a binary file once) raised `UnicodeDecodeError` out
of `communicate()`, or out of `read_text()` past an `except OSError`
that could not catch it, and escaped the turn entirely — `castle work`
died with a traceback, `castle dispatch` exited 1 (the code §2.7
reserves for *mechanism* faults), no result was written, and the next
sweep reaped the dangling claim into a permanent, false
`outcome: interrupted` while the diff the tenant had actually produced
was discarded. A replacement character in a result body is honest; that
was a lie.

Two details found while implementing this, both about the same fact —
`start_new_session` puts the tenant outside this process's group, and
that cuts both ways:

- **The timeout keys on the process, not on the pipes.**
  `communicate(timeout=...)` fires on pipe EOF, and a tenant that
  spawns a detached helper inheriting its stdout/stderr — which
  `claude`-style CLIs do routinely — keeps those pipes open after
  exiting 0. Read as "the tenant hung," that recorded a completed
  errand as `outcome: timeout` with a body claiming its process group
  had been killed. The handler now checks `proc.poll()` first: only a
  still-running process is a timeout (kill the group, drain bounded);
  an already-exited one is drained bounded and its outcome decided by
  its exit code as usual.

  *Checking is not enough on its own, which a later review pass
  caught.* A single `communicate(timeout=CASTLE_WORKER_TIMEOUT)` still
  **waits** the whole timeout before there is anything to check — the
  default is fifteen minutes — with the global dispatch lock held and
  the tenant long since finished. The wait is now sliced: the same
  deadline (`timeout` from the moment the tenant started, unchanged for
  a tenant that really is running), asked in five-second increments,
  with `poll()` between them, so an exited tenant is noticed within a
  slice instead of at the deadline. `input` rides only the first
  slice; the subprocess module keeps unwritten input and collected
  output on the `Popen` across a `TimeoutExpired`, which is exactly
  what retried communication is documented to support.
- **The post-kill drain is bounded** (five seconds). The kill goes to
  the tenant's process group; a descendant that called `setsid()` is no
  longer in it and may still hold the pipes, so an unbounded
  `communicate()` after the kill waits on a process nothing will ever
  kill — wedging the sweep while it holds the global dispatch lock. On
  expiry the result is written with empty output and a body line
  saying exactly that, because a sweep is worth more than a killed
  tenant's last words.

  *And the group is killed on the exited path too, which it was not.*
  `_kill_tenant_group` ran only where `poll()` was `None`, so a tenant
  that exited leaving a child of **its own group** holding the pipes
  had that child survive the turn unconditionally — recorded
  `completed`, with a process still alive and still able to write into
  `$CASTLE_REPO_ROOT` after the journal's account of the turn was
  final. A turn's account being final and its processes still running
  is the one combination this design cannot allow. The exited path now
  drains once, and if the pipes are still held, kills the group and
  drains once more: an in-group straggler dies and its output is
  recovered, and only a genuine `setsid()` escapee reaches the
  give-up branch. That also makes the "could not be collected" body
  line exact rather than presumptive — by the time it is written, the
  group has always been killed, so the holder really is outside it.

  *A second bug inside the first, found by the test written for it.*
  `_kill_tenant_group` resolved the group with
  `os.getpgid(proc.pid)` — which works only while the tenant is
  alive. `poll()` reaps it, and a reaped pid has no process group, so
  on the exited path the lookup raised and the kill silently became a
  no-op: precisely where the kill had just been added, and where it
  matters most. The group id is now captured at spawn, where
  `start_new_session=True` guarantees it equals the tenant's pid.
- **The invoker's own death kills the tenant too.** The same detach
  that makes group-killing possible also means the terminal's SIGINT
  never reaches the tenant: a hand-run `castle work` abandoned with
  Ctrl-C would leave a model tenant running, billing, with nothing left
  alive to write its result. Every exit from the region where a tenant
  is alive — including `BaseException` — now kills the group on the way
  out. SIGTERM needs one extra step, since Python's default action for
  it is to die on the spot with no unwinding at all: a handler that
  raises `SystemExit` is installed for exactly the span of the tenant's
  life and restored after. The systemd case never needed this (the unit
  is a cgroup and systemd kills all of it); the terminal case is the
  one this covers, and it is the case a human is actually in. This lives in the tool, not as `RuntimeMaxSec=` on the
systemd unit, for two reasons stated together because they're really
one reason: a unit-level timeout would kill an entire *sweep* (possibly
mid-way through a second or third legitimate errand) rather than just
the one hung turn, and a human running `castle work` by hand outside
any unit deserves the identical guard — the timeout is a property of
the worker contract, not of how it happens to be invoked.

**3.4 — The three recordless tenant-failure paths become recorded
failures.** This is a fix to a present-tense defect in `cmd_work`
today, not new behavior invented for this task — worth saying plainly
so a reviewer doesn't read it as scope creep. Today, an empty
`CASTLE_WORKER_COMMAND`, a `CASTLE_WORKER_COMMAND` that fails to
`shlex.split`, and an `OSError` on `subprocess.run` (the command names
a binary that doesn't exist, isn't executable, etc.) all `return 1`
with a message on stderr and **no journal record at all**. Under a
human typing `castle work` by hand this is a minor inconvenience — the
error is right there on the terminal. Under a timer or path unit
retriggering `castle dispatch` every few minutes against the same
misconfigured tenant, it is an **unbounded, silent retry loop**: the
request stays eligible forever (no result was ever written), so every
sweep tries again, forever, with nothing in the journal to show a
resident why nothing is happening. Each of these three paths now
writes a `result` record with `outcome: failed` whose body names the
unrunnable command and the specific `OSError`/parse error. This does
two things at once: it makes the request **ineligible** going forward
(§2.4(b)), bounding the retry to exactly one automatic attempt, and it
tells the resident through the ordinary router path — "seat empty, and
the resident is told," per `docs/architecture.md`'s occupancy language
— instead of leaving them to notice a growing pile of nothing. *That
second half was aspirational until review made it true on the
dispatched path:* the sweep's abort returned before its routing tail,
so on the very path where nobody is watching a terminal, the result
was written and never delivered. The abort now routes before it
returns (§2.7).

These three paths also **raise** after writing their result
(`TenantNotRunnable`, carrying the result's id). `cmd_work` catches it
and returns 1 with the message it already printed, so hand-run
behavior is byte-for-byte what it was; `cmd_dispatch` catches it and
stops the sweep — see §2.7 for why one broken exec environment must
not consume every eligible request's single automatic attempt.

*A review finding, dispositioned rather than fixed:* these three now
write a `result` for a **hand-run** `castle work` too, not only for a
dispatched one, and that is deliberate. The obvious alternative — gate
the record on some is-automatic flag — buys nothing and costs
something. It buys nothing because the record is not noise: the
failure is real, the resident hears about it through the ordinary
router path rather than only on a terminal they may have walked away
from, and §4's label names the retry command, so a misconfigured
tenant is *more* visible than the bare stderr line it replaces, not
less. It costs something because the claim record is already written
by then (§3.2), so a suppressed result would leave a dangling claim
that §2.3's reaper would later close as `interrupted` — a worse
account of what happened than "failed, and here is the command that
could not run." One shape of record for one shape of event, whoever
invoked it.

The two remaining failure paths in `cmd_work` — "no such request" and
"not a request record" — **stay recordless**, unchanged. Both are
caller errors: something passed a request id that doesn't exist or
doesn't resolve to a request. No dispatcher can ever produce either
condition (§2.4's fold only ever hands `cmd_work` a real request id it
just read from the journal), so there is no silent-retry-loop risk to
fix, and writing a record for a caller's typo would just be more
journal noise with nothing to say.

**3.5 — `outcome` field on result records.** A closed vocabulary —
`completed | failed | timeout | interrupted` — written on every result
`cmd_work` or `castle dispatch`'s reaper produces from this task
forward.

A distinction worth stating precisely here, because an implementer
could easily blur it and it decides which code path writes which
value: **`outcome: failed` is written by the invoker that watched the
tenant die.** `cmd_work` observed a nonzero exit, an unparseable
command, an `OSError`, or — new in this task — a tenant killed by a
signal (`SIGKILL`, an OOM kill, a crash while `castle work` itself
keeps running), and lived long enough to write the result itself, same
as any other failure. **`outcome: interrupted` is reserved for the
case where the invoker itself died** — the process running `cmd_work`
(or the sweep running it) never returned, so nothing ever wrote a
result, and only §2.3's reaper can retroactively supply one on a later
sweep, from the surviving `claim` record. A tenant dying by a signal
while its invoker survives to see the exit is `failed`; only an
invoker that never got the chance to write anything produces
`interrupted`.

Two surface obligations that come with a *named* vocabulary, both
added after review. `castle record` takes `--outcome` (choices are the
closed set), so a human holding the worker seat by hand can state the
fact rather than leaving a failed errand to read as done — the same
"by convention" shape `--fact` already has for question records. And
`_errand_state` renders an **unrecognised** non-empty value verbatim
with the retry hint rather than folding it into "done": this field is
a contract tasks 0026/0027 extend, so a value from the future will
reach an older surface eventually, and reporting it as success because
it was not understood is the prose-versus-field failure this field
exists to end, one level up. Absent and `completed` still mean done.

`cmd_validate` treats it exactly like `considered`/
`propensity`: **validated when present, checked for membership in the
closed set, never required** — the journal is append-only, and every
result written before this field existed is already permanent; a
validator that suddenly demanded a field no writer at the time could
supply would fail the entire pre-existing journal retroactively (the
exact reasoning `agent/README.md` already gives for `considered`/
`propensity`, cited directly in the new code comment). This is a
named, documented **cross-task contract**: tasks 0026 and 0027 are
expected to reuse this exact field name and exact four-value enum
rather than each inventing a sibling field, and 0028 (rendering the
errand lifecycle) reads from it directly. **No surface may ever infer
failure by grepping body prose for a word like "FAILED"** — the exit
code is the fact, and it lives in this field; the body is the
reasoning, never the machine-readable signal. This fixes a real
present-tense defect stated explicitly: today a failed errand's result
body says "FAILED" in prose (see `cmd_work`'s existing `body_lines`
branch), and `_errand_state` (§4) has no way to read that and reports
the errand as plain `"done"` — a resident who trusts the status
surface has no idea the worker actually failed.

*The five durable-data questions, for `outcome`:* (1) **Durable?**
Yes — it is the account of what happened to this specific turn.
(2) **Reconstructable from anything else?** No — the process's exit
code exists nowhere else once the process is gone, and grepping "FAILED"
out of a prose body is not a schema (a body's wording can and does
change without the field mattering). (3) **One record, prose body,
readable cold?** Yes — one word from a documented, closed vocabulary,
sitting beside the same prose body that already existed. (4)
**Observation or judgment?** An observation — "the process exited
non-zero" or "the process was killed on timeout" — never a judgment of
whether the *work itself* was good; that stays with the resident, per
Proposal 06. (5) **Needed now?** Yes — each of the four values is
produced by a specific, named code path built in this task, not a
speculative future one.

**Explicitly rejected fields**, considered and dropped for the same
reason each time — durable-data question 5, "needed now": `attempts`
(the retry policy below is structural, not counted, so nothing reads
this), `duration` (nothing in this task's scope renders a timing
view), `exit-code` (the four-value `outcome` enum already carries every
distinction any current caller needs; the raw integer would be one
more thing to keep in sync with the enum for no consumer).

**Retry policy.** `castle work`'s behavior on a request that already
carries a `result` is **deliberately unchanged** beyond the lease
check: a human re-running `castle work <id>` by hand on an already-
worked request **is** the explicit retry path, and stays exactly that
— nothing here disables it. What this task adds is: **one automatic
attempt, and no automatic retry of any outcome, ever.** Boundedness is
a property of the eligibility rule itself (§2.4(b): any `result` at all
makes a request permanently ineligible, regardless of its `outcome`),
not a counter anywhere that could be reset or misconfigured. Automatic
re-invocation of a model tenant after a failure is a cost-and-authority
decision this task deliberately reserves to the human — see Non-goals.

**Every worker-written result names the claim it closes** —
`refs: <request-id>,<claim-id>` — which the first implementation got
wrong by keeping `refs: <request-id>` alone. The accounting has to be
per *turn*, not per errand, because §2.3's reaper asks "is this claim
closed?" and can only answer it from a result that names the claim.
With request-only refs, a failed errand that a resident retried by hand
— whose retry then died mid-turn — looked closed by the *first* turn's
result: the second claim was never reaped, and the errand sat showing a
stale `failed` forever with its real last turn unrecorded. Eligibility
stays per request (any result at all still bars an automatic attempt);
only the reaping is per turn. The `claim` record already carries its own
`refs: <request-id>`, so the transitive-downstream fold
(`_collect_downstream`, used by both `cmd_digest` and `castle-modal`'s
`run_status`) picks both up for free with no change to that walk.

### 4. Status surfaces (task 0015's scope-3 rule: the two must agree)

**`_errand_state` (`agent/castle-modal`).** **The errand's state is
the state of its newest *turn*, not of its newest result** — a
correction to the first implementation, which keyed on results and got
two real cases backwards, in opposite directions. Since §3 makes every
worker result name the `claim` it closes, "which turn are we talking
about" is answerable (via the same two-clause `closing_result` helper
§2.3 describes, so the reaper and this surface can never disagree
about whether a turn was accounted for — see §2.3 for the review
finding that made that promise true rather than merely stated), and it
has to be asked: an errand whose retry
completed and whose older abandoned turn was reaped *afterwards*
carries an `interrupted` result newer than its `completed` one, so
keyed on results it reads as interrupted forever though it is
finished; and an errand whose second turn died leaves a claim no
result closes, which an older result masks entirely. Older turns'
accounts — reaped ones included — are history; the newest turn is the
current truth. An errand with no `claim` records at all (every journal
written before this task) keeps the newest-result behavior unchanged.

*Which records count as this errand's turns is keyed to the request,
and a review pass is why.* `_collect_downstream` is transitive over
`refs` with no keying by type or errand — correct for the fold as a
whole, and wrong as the input to a turn-state decision.
`castle ask --refs R1` is the documented way to file a follow-up, so
R2 lands in R1's downstream and brings its own claims and results with
it: a cleanly finished R1 could be labelled from R2's abandoned turn,
"interrupted — `castle work R1` to retry", about a turn R1 never had.
Claims are now selected by `refs[0] == this request` (the reaper's own
keying) and results by naming this request (what `closing_result`
uses, and what lets `--refs R,C` close a turn by hand). The watermark
branch is keyed the same way — the watermark excludes **by name**, so
a watermark reachable through a follow-up must not make this errand
claim it predates dispatch. Questions and answers deliberately stay
transitive: a question raised anywhere on the chain is still the
resident's to answer.

*The "waiting on you" overlay pairs answers with questions.* It used
to ask whether the fold contained a question and no answer, which
never paired the two, so the first answer on an errand silenced every
question raised after it — on the one surface whose entire job is to
say when a worker is blocked on the resident. It now collects the
question ids that some answer names, and overlays if any question in
the fold is not among them.

The newest turn's account is read with its `outcome` field:

- `outcome: completed`, **or `outcome` absent entirely** → `"done"`.
  Absence has to keep meaning `"done"`, because that is every result
  record written before this task — the journal is append-only, and
  cannot be backfilled. State plainly in the code comment that
  pre-existing "FAILED in prose, no `outcome` field" results will
  continue to read as `"done"` forever, deliberately — the same
  backward-compatibility posture `considered`/`propensity` already
  established, applied here on purpose rather than by oversight.
- `outcome: failed` → a label that names the retry command, e.g.
  `"failed — castle work <id> to retry"`.
- `outcome: timeout` → `"timed out — castle work <id> to retry"`.
- `outcome: interrupted` → `"interrupted — castle work <id> to retry"`.

The exact wording of these three is the implementer's call, but each
**must** name the retry command explicitly — this is 0015's own lesson,
restated so it isn't relearned: "the label must not cause the inaction
it describes." A label that just says "failed" with no next step
repeats exactly the mistake 0015 fixed for the opposite case (a label
implying action where none had happened); here the risk is a label
that's honest about failure but leaves the resident not knowing what to
do about it.

A `claim` with a **live** lease → `"in progress (started HH:MM)"`,
checked **before** any result rather than only when no result exists.
The first implementation gave results absolute precedence, and the
errand that exposes the difference is the one these labels exist for:
a failed errand the resident is retrying *right now* rendered
`"failed — castle work <id> to retry"` — advice to run a command that
was already running, and that would be refused the lease if taken. A
live turn is the most specific true thing about an errand; the last
turn's account is merely the most recent one. — the honest version of the state 0015 explicitly
refused to fake (its non-goals: "the fallthrough… is not a claim that a
worker is running"). This is now backed by real evidence: a held
`flock`, checked live, not an absence-of-evidence guess (§2.3's note on
probe mechanics covers the narrow, accepted race this live check
shares with the reaper's own probe). A `claim` with
a **dead** lease and no result reads as interrupted (the same case
§2.3's reaper is racing to write a `result` for — between "the lease
died" and "the next sweep reaps it," the honest label is "interrupted,"
not "in progress," since nothing is actually running). A request the watermark excluded (§2.2), with no claims and no results
→ `"not started automatically (predates dispatch) — castle work <id>
to run it"`. The watermark names its excluded requests in its own
`refs`, so it is already in that errand's downstream fold and the
explanation is right there; `"awaiting a worker"` on an errand
automatic dispatch has permanently declined to touch is 0015's failure
again, in a third costume.

A request carrying `filed-during-turn` (§2.4(e)) with no claims and no
results → `"filed during a worker turn — castle work <id> to run it"`.
Added with that stamp, and for the same reason the fallthrough was
fixed in the first place: dispatch deliberately never starts these, so
`"awaiting a worker"` would be 0015's exact failure — a label
promising a start that is never coming. Say what is true, and what the
resident can do about it.

The existing
`", waiting on you"` overlay for an unanswered `question` composes
exactly as it does today — no change to that logic.

**`cmd_digest`** renders the `outcome` value inline wherever a result
carries one (next to the existing `channel`/`evidence` rendering for
decisions), and **does not grow a lease reader**. State the asymmetry
explicitly in a comment so it doesn't read as the two surfaces
disagreeing: the digest is a historical account of a period that has
already happened, not a live view of what's running right this second
— rendering "in progress" in a digest for an errand that finished
between the digest's fold and the resident reading it would be exactly
the kind of stale claim 0015 fixed the modal for. `_errand_state`'s
live-lease check belongs only on the surface that's actually read live.

**Both surfaces also learn to render a decision that routed nothing.**
Putting the excluded requests in the watermark's `refs` (§2.2) pulls
that decision into every excluded request's transitive-downstream fold
— which is a feature, not an accident: an excluded request's status
entry is exactly where the resident wants the explanation for why
nothing is happening on its own. But both surfaces previously assumed
every decision carries a `channel`, and would have rendered the
watermark as `channel: ?` / `decided -> ?` — inventing a routing that
never happened. The digest now prints the channel line only when the
field is present, and the modal prints `noted: <evidence>` for a
channel-less decision instead of `decided -> ?`. This is a small,
resident-visible rendering change beyond the original design, adopted
during implementation because the refs-based watermark made a
channel-less decision reachable for the first time.

**In passing** (`agent/castle-modal` is already being edited): fix the
two stale `$mod+Shift+space` strings still in the file — one in a
comment, one in the empty-status hint printed by `run_status` — to the
real chord, `Mod4+Shift+Return`, per `docs/tasks/0019-sway-initial-
workspace-and-modal-chord.md`, which moved the binding but missed these
two strings.

### 5. Provenance is not changed by automatic starting

One sentence, but load-bearing enough to state as its own scope item so
it isn't silently gotten wrong during implementation: **provenance
records who *wanted* the work, never who *started* it.** A resident-
requested errand that dispatch starts automatically keeps
`provenance: requested` on its result, unchanged, exactly as if a human
had typed `castle work` themselves. Flipping auto-started requested
work to `initiated` would silently reroute every one of its results
from the `notify` channel to `digest` — the resident asked for
something, and automating *how it started* would make the answer
invisible until the next digest read. Provenance answers "who wanted
this," and automatic dispatch changes nothing about who wanted it.

### 6. The `dispatch` seat value

Records written by the reaper (§2.3) and the watermark (§2.2) carry
`seat: dispatch`. Document this explicitly, in both `agent/README.md`
and `docs/architecture.md`, as **plumbing, not a reasoning seat** — the
`seat` field already means "which component wrote this record," and
`digest` is already listed as a non-reasoning surface seat, so this is
not a new category, just a new value in the existing one. Add a short
paragraph to `docs/architecture.md`'s Seats section placing dispatch as
the mechanism that invokes the worker seat on the journal's behalf,
holding no judgment of its own and choosing no tenant — which is
exactly what stops a future agent from "completing" it into a reasoning
seat later (e.g., giving it a policy for *which* eligible request to
run next, or a say in whether to run one at all). §2.9's "no per-errand
decision record" argument is the same point from the record-schema
side; this paragraph is the architecture-doc side of the same
guarantee.

### 7. Test plan

**New fixture family, `test/agent-loop/`**, conforming to the *real*
`castle.agent.worker.command` contract for the first time — request
body on stdin, reasoning on stdout, a diff or nothing written to
`$CASTLE_DIFF_FILE`, `$CASTLE_REQUEST_ID`/`$CASTLE_REPO_ROOT` present in
the environment. This matters because **that contract is currently
exercised nowhere**: both `test/agent-loop/run.sh` and
`test/desktop-loop/test.nix` call `scripted-worker.sh` with two
positional arguments (`<castle-bin> <request-id>`), bypassing
`cmd_work` entirely — a real gap this task's changes to `cmd_work`
(lease, claim, timeout, `outcome`) would otherwise ship with zero
coverage. New fixtures:

- `contract-worker.sh` — succeeds, writes a diff. *It also honors an
  optional `CASTLE_TEST_WORKER_SLEEP` (default 0), which is how the
  concurrency assertion below widens its race window — a knob on the
  happy path rather than a fifth near-identical fixture file.*
- `contract-worker-fail.sh` — exits nonzero, writes to stderr, no diff.
- `contract-worker-hang.sh` — sleeps far longer than any test's
  configured timeout.
- `contract-worker-die.sh` — kills itself with `SIGKILL` mid-turn, to
  exercise a signal death distinctly from a clean nonzero exit (see
  §3.5's `failed`-versus-`interrupted` distinction).
- `contract-worker-filer.sh` — *added during implementation, with
  §2.4(e)*: files one follow-up request with `castle ask` during its
  own turn. Not a pathological tenant — this is what a reasonable one
  does — which is exactly why the sweep has to stay bounded in its
  presence. It also proves the inheritance path the stamp depends on:
  the fixture never sets `filed-during-turn` and does not know it
  exists, it just runs `castle ask`.
- `contract-worker-detach.sh` — *added with the pass-3 review finding
  above*: writes its diff, exits 0, and leaves a `setsid` helper
  holding the inherited stdout and stderr. The shape a `claude`-style
  CLI produces routinely, and the one that made pipe-EOF and process
  exit diverge.
- `contract-worker-straggler.sh` — *added with the pass-4 review
  finding above*: the same shape without the `setsid`, so the child
  stays in the tenant's own process group. It is the case a turn can
  and must end, and until that pass nothing did: the pid it leaves in
  `$CASTLE_REPO_ROOT` is how the harness asserts the child did not
  outlive the turn whose result already accounts for it.

The existing `scripted-worker.sh` and `scripted-worker-alt.py` stay
**byte-for-byte untouched** — they hold the worker seat for `run.sh`
and `tenant-swap.sh` today, and changing their positional-argument
shape would weaken Proposal 03's re-tenanting proof (`tenant-swap.sh`
diffs a normalized journal fingerprint between two differently-shaped
workers; that comparison is only meaningful if neither harness's
existing behavior moved out from under it).

*One housekeeping consequence of this task's harnesses, recorded
because it bit during implementation:* running them locally leaves an
`agent/__pycache__/` behind — `castle-modal` imports `castle` as a
module, so Python writes bytecode next to it — and one of those `.pyc`
files was committed by an over-broad `git add -A` before being caught.
`.gitignore` now carries `__pycache__/`. It matters slightly more here
than ordinary tidiness: `modules/agent`'s `castleCli` derivation takes
`agent/` as its `src`, so a stray `.pyc` changes a store path for
nothing.

**New `test/agent-loop/dispatch-test.sh`** — no Nix, plain bash and
python3 like every other harness in this directory, its own CI job in
`.github/workflows/check.yml` next to `agent-loop-test` and
`modal-headless-test`. Proves:

- the watermark is written exactly once — by whichever of the two
  writers gets there first — and a request created before it stays
  un-dispatched;
- `castle dispatch --watermark-only`, what §1's session-start unit
  runs, establishes that boundary on a fresh journal and does nothing
  else: it names the outstanding request in the watermark's `refs`,
  says in its output that it is not sweeping, and writes no `claim`
  and no `result` (asserted on record counts). Running it a second
  time leaves the journal byte-identical in record count, and a
  subsequent *full* sweep honours the boundary it laid down — the
  pre-watermark request stays un-dispatched while one filed after it
  is claimed and resolved;
- an eligible request gets exactly one turn, and its result is routed
  by the same sweep's tail step;
- a second sweep over an already-worked journal changes nothing — the
  no-self-retrigger proof (§2.8), asserted on record counts, not just
  "the process exits 0";
- two concurrent `castle dispatch` invocations against the same request
  produce exactly one `claim` and one `result` (use a worker fixture
  that sleeps briefly to widen the race window enough to catch a
  regression);
- a failing tenant (`contract-worker-fail.sh`) yields `outcome: failed`
  and is not re-dispatched on the next sweep;
- a tenant killed by a signal (`contract-worker-die.sh`) also yields
  `outcome: failed`, not `outcome: interrupted` — the invoker survived
  to observe the death and write the account, so this is not the
  reaper's case (see §3.5);
- a hanging tenant (`contract-worker-hang.sh`) under
  `CASTLE_WORKER_TIMEOUT=2` yields `outcome: timeout` within a few
  seconds, not the fixture's full sleep duration;
- a tenant that exits 0 leaving its pipes held (`-detach.sh`, escapee;
  `-straggler.sh`, in-group) is `completed`, and the sweep returns in
  seconds **under a deliberately large `CASTLE_WORKER_TIMEOUT` (600)**
  — the timeout is what the old single-`communicate` wait would have
  spent, so a small one made this assertion prove nothing. For the
  in-group fixture the harness additionally asserts its child is dead
  once the sweep returns, and that the tenant's stdout survived (the
  kill is what closes the pipes, so the drain after it succeeds);
- a hand-written closure whose `--refs` also names an unrelated
  errand's claim still closes its own turn, and the sweep does not
  reap it — the reaper and the status surface reading one shared
  `closing_result`, asserted rather than assumed (§2.3);
- a planted `claim` record with a stale or absent lease file yields a
  reaped `outcome: interrupted` result on the next sweep, and that
  result gets routed;
- a planted second `claim` on an errand that already carries a `failed`
  result — the hand-retry-then-died case — is *also* reaped, which is
  what proves the reaper's ledger is per turn rather than per request;
- an `answer` record filed against a `question` on an already-worked
  errand does **not** make the request eligible again — asserted as an
  explicit non-behavior, since this is precisely task 0023's
  territory and a regression here would silently widen this task's
  scope into that one;
- an empty `CASTLE_WORKER_COMMAND` yields `outcome: failed` on the very
  first sweep, not a silent, unbounded retry loop across several
  sweeps;
- a request a tenant filed during its own turn carries
  `filed-during-turn` naming that turn's claim, the sweep that ran the
  tenant terminates promptly, and two further sweeps never dispatch the
  follow-up — while `castle work <id>` on it by hand still works,
  because the stamp bounds automatic spend rather than forbidding the
  work (§2.4(e));
- `correction` records are never routed, even when dispatch is what
  triggers `castle route` (reusing `run.sh`'s existing assertion shape
  under automatic triggering rather than a hand-run `castle route`);
- `castle validate` passes on the resulting journal throughout, not
  just at the end.

**`test/agent-loop/modal-headless-test.sh` additions:** a result with
each of the four `outcome` values produces the matching `_errand_state`
label; a `claim` with a live lease produces `"in progress"`; a live
lease *plus* an existing `failed` result still produces `"in progress"`
(the precedence case above); every pre-existing state assertion in the
file stays unchanged.

**`test/desktop-loop/test.nix`:** enable `castle.agent.dispatch.enable`
and set `castle.agent.worker.command` to a contract-conforming scripted
tenant **in the same commit** — this is a safety floor, not an
incidental config choice. *`castle.agent.worker.repoRoot` is pinned to
a non-default path in the same block, for the same reason
`testStateDir` is non-default: the scripted tenant prints its own
`$CASTLE_REPO_ROOT` back, and asserting that string lands in the result
record is what proves the unit's `Environment=` actually reached the
worker process rather than the `%h` fallback quietly standing in.* `castle.agent.worker.command` currently
defaults to `castle-worker-claude` (a real `claude -p` invocation), and
this VM already imports `modules/dev`, which installs the `claude`
binary; without pinning the command to a scripted stand-in, enabling
dispatch in this test would make CI attempt a real, networked model
call with real credentials the CI environment does not have. The
modal-filed request errand's existing **manual** worker/route steps
(`bash /tmp/scripted-worker.sh …` followed by `castle route`, both run
by hand in the current test) are removed and replaced with waiting for
the auto-produced result and routing decision to appear under
`testStateDir` — this also proves the systemd user unit actually saw
the configured `CASTLE_STATE_DIR` (bug 2b's shape, now proven for the
dispatch unit specifically rather than just for the modal). This makes
the VM test into exactly the feature's acceptance condition: filing one
request through the modal produces a routed outcome with no subsequent
resident CLI action at all. The correction-filing flow and the file's
other existing assertions are unchanged.

*Two additions made while implementing that, both to keep coverage the
swap would otherwise have removed or left thin.* The scripted tenant
**raises a `question` before doing its work**: pinning
`worker.command` to the contract fixtures took away the only thing in
this VM that ever produced a question record, leaving
worker-raises-a-question-and-the-router-delivers-it — a central claim
of `docs/architecture.md`, and exactly what
`agent/castle-worker-claude`'s prompt instructs a real tenant to do —
with no coverage inside a booted systemd session at all. The test
asserts the question exists, references the request, and was routed to
`notify` by the same sweep. And the notify health assertion matches on
`castle route:` rather than on `notify command`: `_fire_notification`
has two warning variants and only one of them says "notify command",
while both carry that prefix — and the router's ordinary reports print
`route: …` and the sweep's print `dispatch: …` without it, so the
substring covers both failures without matching healthy output.

*A third addition, forced by this VM failing.* Two assertions run
after the end-to-end flow: that the watermark record's `refs` are
**empty** (this journal starts empty, so the resident's request must
not be named in it — the direct regression assertion for the race
§2.2 records), and that `castle-dispatch-watermark` really ran. *That
second one is asserted on three properties, not on `Result` alone, and
the reason is worth recording: `systemctl show -p Result` reports
`success` for a unit that does not exist and for one that exists but
never started, so a check on `Result` alone would stay green through a
typo in the unit name, a lost `wantedBy`, or a `ConditionUser` that
excluded the resident — every failure it was meant to catch.
`LoadState=loaded` proves the unit exists, a non-empty
`ExecMainStartTimestamp` proves its `ExecStart` actually ran, and
`Result=success` then proves it did not fail. `is-active` is no help
either: this oneshot sets no `RemainAfterExit`, so a finished run and
a never-started one both read `inactive`.* Deliberately **no
wait or sleep before the modal files its request**: the test's fast
filing is exactly what exercised the defect, and slowing it down would
turn the regression assertion into a check that verifies nothing.

Remember to check the path
filters in `.github/workflows/desktop-loop-test.yml` if this adds any
new fixture file paths that need triggering the workflow.

**Eval-level checks in `flake.nix`:**

- `nixosConfigurations.example` (which already imports `nixosModules.agent`
  with dispatch left at its default) gains an assertion that no
  `castle-dispatch` user unit is generated — the middle case between
  "no agent module at all" (already proven by `test/vm-install`'s
  harness) and "dispatch explicitly on." *Written as an implication
  ("dispatch off ⇒ no units") rather than a flat "no units": the
  `extendModules` variant below inherits this configuration's own
  assertions, so a flat form would go red on the one configuration
  that is supposed to have the units. The antecedent holds on
  `.example`, so the check still bites exactly where it is aimed.*
- A new `extendModules` variant, following the `example-mod4` precedent
  already in `flake.nix`, with `castle.agent.dispatch.enable = true`
  and a dummy `stateDir` set, asserting the four units exist and carry
  the expected `Environment=` values — including that
  `castle-dispatch-watermark` is in `default.target`, runs the
  `--watermark-only` path, and carries `CASTLE_STATE_DIR`. Eval-only, exactly like
  `example-mod4` — nothing builds or boots this configuration; `nix
  flake check` forcing every `nixosConfiguration`'s `assertions` is
  what proves it.

`nix flake check` must stay green throughout.

### 8. Documentation surface

- **`agent/README.md`** — the `castle dispatch` subcommand in the
  subcommand list; the `claim` record type in the record-format
  section; the `outcome` field, documented explicitly as the contract
  tasks 0026/0027 must reuse; the lease and the new `leases/` directory
  alongside the existing `spool/` description; the watermark decision
  record; the new harness. In passing, fix the "Four harnesses" line in
  the Testing section, which currently lists three
  (`run.sh`/`tenant-swap.sh`/`modal-headless-test.sh`) — adding
  `dispatch-test.sh` finally makes that count true.
- **`docs/architecture.md`** — `claim` added to the Records section's
  type list; the dispatch paragraph in Seats (§6, above); a sentence in
  the Worker section noting invocation is now automatic when opted in,
  and restating that the seat still proposes, never deploys, regardless
  of who or what invoked it; a third bullet added to the "Where runtime
  state lives" consequences list: automatic dispatch of resident-
  requested errands is a new standing authority, opt-in and
  default-off, with its taxonomy classification (silent / made-then-
  reported / queued-for-approval) explicitly deferred to the
  authority-taxonomy task
  (`docs/backlog/authority-taxonomy-prior-art.md`), the same way the
  existing two bullets defer the private-repo-commit authority.
- **`docs/private-layer.md`** — the agent options section (the
  `castle.agent.*` bullet list and `resident.nix` example) gains
  `dispatch.enable`, `worker.timeoutSeconds`, and `worker.repoRoot`
  next to the existing three options, in the same style.
- **This brief itself** notes, in its Why section, that 0015's deferred
  "started/claimed record type" question is answered by §3.2 — a
  reader who followed 0015's pointer here should find the answer
  without hunting further.

## Non-goals

- **Answer-driven resumption.** An `answer` record does not make its
  question's errand re-eligible; nothing here resumes a stalled turn.
  Task 0023 inherits this as a **deliberate non-behavior**, proven by a
  test (§7), not an accident this task happened to leave unhandled.
  `docs/backlog/errand-resume-after-answer.md` stays open — it is
  0023's problem to solve, not deleted or narrowed by this task.
- **Question answering in the resident's own language, timing, or
  register.** That is task 0022's territory.
- **Proposal approval, configuration mutation, or deployment from any
  automatically-invoked seat.** Tasks 0025–0027. `cmd_work` still has
  no deploy path, invoked automatically or by hand.
- **Sensors.** Nothing here reads window focus, calendar state, or any
  other ambient signal to decide *when* to dispatch beyond the
  path-unit/timer trigger itself.
- **Committing or pushing the journal to the private repo.** 0008
  already deferred pushing; the credential story for it still doesn't
  exist. The consequence — the journal grows uncommitted on disk
  between manual commits — is named here, not solved.
- **Scheduling unrelated to this lifecycle.** Note explicitly that the
  timer backstop in §1 *is* related scheduling — a backstop for
  exactly this lifecycle — so a reviewer doesn't read this bullet as
  contradicting §1's own timer and flag it as scope creep.
- **New intake channels.** Nothing here adds a way to file a request;
  it only makes filed requests self-starting.
- **Enabling dispatch on any real host.** That is the resident's
  authority decision to make on their own machine, in their own
  private layer; this task ships the option **default off**, and turns
  nothing on anywhere.
- **`loginctl` lingering.** See §1 — a separate authority decision
  about whether dispatch runs while nobody is logged in.
- **Automatic retry of any outcome.** See §3's retry-policy paragraph —
  one automatic attempt, always, by construction of the eligibility
  rule, never a counter to misconfigure.
- **Worker-contract generality** — whether the diff-producing contract
  `cmd_work` implements is the general shape of a Castle Turing worker,
  or one worker among several a resident might fire off very different
  kinds of task to. Refiled as its own, narrower backlog entry,
  `docs/backlog/worker-contract-generality.md`, since this task answers
  "how does *this* contract start itself," not "is this the only
  contract there should be."

## Verification plan

**Agent-testable, no human involved:** everything in §7 — the shell
harnesses (`dispatch-test.sh`, the extended `modal-headless-test.sh`,
the untouched `run.sh`/`tenant-swap.sh`) and `nix flake check` all run
locally with nothing beyond `bash` and `python3` on `$PATH` (plus Nix
for the flake check). The extended `test/desktop-loop/test.nix` VM test
builds locally (`nix build .#desktop-loop-test`) or in CI
(`.github/workflows/desktop-loop-test.yml`), and is the acceptance
condition for the whole feature: file one request through the modal,
watch a routed outcome appear with no further resident action.

**Human hands, genuinely needed:** enabling
`castle.agent.dispatch.enable` on the reference host — this is exactly
the resident authority decision this task deliberately does not make
on their behalf (see Non-goals), so it cannot be automated away.
Separately, sanity-checking the 900-second default timeout against how
long a real `claude -p` errand actually takes on the reference host —
the chosen value is not derived from any measurement, and only a real
run tells whether it's in the right neighborhood.

## Implementation prompt

For the session that implements this brief: read `CLAUDE.md` in full,
this brief in full, `docs/architecture.md`, `agent/README.md`, and
every file this brief names as being modified, before writing any code.
Work on branch `sprint/0021-auto-dispatch` (already created; this brief
rides it). Keep `agent/castle` stdlib-only, no third-party dependency of
any kind, and readable top to bottom — this is a hard constraint
carried over from 0008, not new to this task. Run
`test/agent-loop/*.sh` and `nix flake check` locally before opening a
PR; the desktop-loop VM test can be built locally with `nix build
.#desktop-loop-test` if the machine has the resources, or triggered in
CI via `gh workflow run desktop-loop-test.yml` if not. Per CLAUDE.md's
multi-agent conventions, run `/code-review` scoped against
`origin/main` and address its findings, then run `tools/codex-review.sh`
for a second opinion, before opening the PR. If the design in this
brief turns out to be wrong or incomplete once real code is written
against it — a race the sweep lock doesn't actually close, a field
that turns out to need a different shape — update this brief in the
same PR rather than letting the PR description carry reasoning the
brief should hold; that is the whole point of specs riding their
branch.
