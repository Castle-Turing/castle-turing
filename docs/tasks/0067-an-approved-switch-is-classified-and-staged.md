Title: Task 0067 — an approved switch is classified by what it would churn, and staged accordingly
Model: deep
Model-because: the direction was resident-decided, but the brief owns
three couplings a standard implementer would get individually right and
jointly wrong: which oracle actually answers "would this disturb the
session" (the obvious one is blind to half of it), what a staged switch
does to 0048 §E's never-open-at-boot rule, and what the review screen's
boundary statement must now say so that the sentence a resident spends
authority under stays true. A smaller model would ship a classifier
against a remembered output format and a window that either never
confirms a staged switch or rolls a machine back for not confirming
something it never activated.

# Task 0067 — an approved switch is classified by what it would churn, and staged accordingly

## Provenance

A first attempt ran on 2026-09-06 under an earlier framing ("weigh
options for deferring when a session is active") and was superseded
mid-run when the resident refined the direction to the fine-grained one
below. **A blanket defer-on-active-session is the abandoned design and
is explicitly not what this builds.** No backlog entry precedes this
file; it is the authoritative record.

## What happened, from the journals of 2026-09-06

Two switches ran on the same machine, on the same day, under the same
logged-in session — and only one hurt.

At 17:32 the resident ran `sudo nixos-rebuild switch` by hand. Its
activation restarted polkit, SIGHUP-reloaded both D-Bus brokers, and
re-executed the resident's user manager. The session survived, as it had
survived every routine switch before it.

At 20:32 `castle-activate.service` switched to a generation whose entire
delta was one home-manager-carried config file (`foot.ini` — terminal
padding). Because the delta rode through home-manager, this was the
day's only switch that restarted `home-manager-wesley.service` —
relinking home files and reloading user units under the live session.

What is proven, and what is not, both matter here:

- **The switch invalidated the resident's verification surface.** foot
  terminals read their config once, at startup; no existing window could
  ever show the padding change, and a freshly opened one raced the
  22-second build-and-activate. The resident checked, saw old padding,
  and rejected the health question at 20:33:12 — a reject that was right
  about the evidence and wrong about the machine. The generation was
  good; a reboot later proved it.
- **The catastrophic end-state is not proven to be the switch's doing.**
  The session verifiably worked through the reject at 20:33:12, user
  timers ran normally until 21:14:26, and the journal's final minutes
  are lost (task 0068). A second memory-thrash event is a live rival
  hypothesis for the terminal wreckage. The false reject alone justifies
  this task; nothing here claims more.

## The direction, decided by the resident

An approved switch is classified by what its activation would actually
do, and the session-affecting ones do not go through until the machine
next boots. Not a blanket policy on "a session exists"; a per-switch
classification of the churn.

- A change that touches nothing session-load-bearing → live switch,
  exactly today's behaviour.
- A change that would restart or reload the resident's home-manager
  unit, the user manager, dbus, logind or the display manager → the
  switch is **staged**, not executed: the new generation becomes the
  boot default with zero runtime churn, and the resident is told it
  takes effect at the next reboot.
- The classification set is mechanism with a configurable option and a
  conservative default in `modules/` (Principle 01); nothing hardcodes
  this machine or this resident's username.

## §A. What was verified rather than assumed

The brief was told to check two things before designing against them.
Both checks changed the design.

### A.1 What `switch-to-configuration dry-activate` actually reports

This flake pins nixpkgs at `0e251e2` (26.11), whose
`switch-to-configuration` is the Rust `switch-to-configuration-ng`
0.1.0. Its source is readable at
`/nix/store/nwygz16qa3fcn7krmwmb3xbiz9jfwwhb-switch-to-configuration-ng/src/main.rs`
on any machine running that generation. Read, not remembered:

The system dry run prints, on stderr, in this order (`main.rs`
2044–2187):

    would stop the following units: <names, comma-separated>
    would NOT stop the following changed units: <names>
    would activate the configuration...
    <the activation script's own dry-run output>
    would restart systemd
    would reload the following units: <names>
    would restart the following units: <names>
    would start the following units: <names>

The format is stable and easy to parse. **It is also, in this pin,
structurally blind to exactly half of what this task needs to know.**
`do_system_switch`'s dry-run branch ends in `std::process::exit(0)` at
`main.rs:2187`. The loop that enumerates logind's users and spawns the
per-user `switch-to-configuration` — the code that prints `would restart
the following user units:` — is at `main.rs:2381`, after that exit. A
system `dry-activate` therefore never reports user-unit churn at all.
The `would … the following user units:` strings exist in
`do_user_switch` (`main.rs:1509–1520`) and are unreachable from a system
dry run.

So the oracle the direction named is not unstable; it is incomplete.
The direction anticipated this outcome and named the fallback —
"comparing the generations' unit sets directly" — which is what §B
builds. Two further costs of the dry-activate route, recorded because
they are the rest of the argument and not the whole of it:

- It requires **a third privileged unit** (`switch-to-configuration` and
  `nixos-rebuild` both refuse to run as anyone but root) and a widening
  of the polkit rule that 0048 §H treats as this project's most serious
  authority record — for a read-only query.
- Its output would have to be routed back to an unprivileged reader
  through a file in `/run`, adding a staleness question the direct
  comparison does not have.

**The judgment call, recorded as one:** the classifier does not run
`dry-activate`. It compares the two generations' unit trees. This is the
reversible side — it adds no privilege, parses no program's prose, and
can be replaced by the dry-activate oracle later without changing any
record this task writes.

### A.2 Whether a logout tier can exist

It cannot, in this repository's layout, and the direction's own
conditional applies: the logout tier degrades to the reboot tier.

`modules/home/default.nix` wires home-manager as a **NixOS** module
(`flake.nix:65`, `home-manager.nixosModules.home-manager`) and does not
set `home-manager.startAsUserService`. Under that default
(home-manager's `nixos/default.nix:73–120`, at the pinned revision
`c8058ec`), each resident gets a **system** unit
`home-manager-<user>.service`, `wantedBy = [ "multi-user.target" ]`. The
resident's home generation is therefore linked by a system unit at boot
or at switch — never by logging in. Logging out and back in gives fresh
processes reading the *already-linked* files; after a staged switch
those files are still the old ones, because nothing has run
`home-manager-<user>.service`.

A logout tier would be a promise the layout cannot keep. There is one
tier below "switch now", and it is "next boot".

## §B. The classifier

Two store paths, both world-readable, both facts about closures rather
than about a program's output:

- **the running generation**, `os.path.realpath("/run/current-system")`
  — what `_running_system()` already reads;
- **the approved generation**, the build result's `build-toplevel`.

For each of them, castle reads two directories:

    <toplevel>/etc/systemd/system      (a symlink to a `system-units` store path)
    <toplevel>/etc/systemd/user        (a symlink to a `user-units` store path)

Every entry in those directories is itself a symlink into the store (or,
for generated units, a regular file; for drop-ins, a `<unit>.d`
directory). `os.path.realpath` of each entry is compared between the two
generations. A name present on one side only, or whose realpath differs,
is a **changed unit**; a `<unit>.d` name is attributed to `<unit>`.

Store-path equality is exact in the direction that matters: equal paths
prove byte-identical content, so a unit this reports as unchanged
*cannot* be restarted by the switch. The converse is an
over-approximation — a differing path does not prove systemd would
restart the unit, since `switch-to-configuration` compares the parsed
unit and honours `X-RestartIfChanged=false` and friends. **That
over-approximation is the design, not a defect of it:** it lands every
uncertainty on the staging side, which is the side that cannot break a
live session.

The changed set is then matched against a configured list of
**session-load-bearing unit patterns** (`fnmatch`, so `home-manager-*`
needs no username). A non-empty intersection means stage.

**Why this catches the incident exactly.** `home-manager-<user>.service`
has `ExecStart=<setup-env> <activationPackage>`; the activation package's
store path changes with any change to the resident's home content,
`foot.ini` included. The 20:32 switch would have been classified as
staging on its first line.

**What it is blind to, said out loud.** The resident's *own* user units
— everything home-manager writes into `~/.config/systemd/user` — are not
in either tree. They are covered transitively: nothing changes them
without changing `home-manager-<user>.service`, which is in the tree.
What is genuinely not covered is churn with no unit-file expression at
all: a `systemd.tmpfiles` rule, an activation-script snippet, an
`environment.etc` file some running process re-reads. Those switch live,
as they do today. `docs/backlog/the-switch-classifier-over-approximates.md`
records both edges.

### The option

    castle.agent.activation.sessionUnits :: listOf str

Default, conservative, and every entry earns its place from the incident
report or the direction:

    home-manager-*.service      the resident's home generation, relinked live
    user@*.service              the user manager itself
    dbus.service
    dbus-broker.service
    systemd-logind.service
    display-manager.service
    greetd.service

Wired to `CASTLE_SESSION_UNITS` as a comma-separated list (unit names
cannot contain commas). **An empty list turns classification off** and
restores 0048's behaviour exactly — which is the escape hatch for a
resident who finds the default stages too much, and is why the option is
a list of patterns rather than a boolean.

The glob in `home-manager-*.service` is deliberate. The module knows
`activation.user` and could interpolate it, but that would need
home-manager's own `escapeSystemdPath` reimplemented here to stay
correct for unusual usernames, and a pattern that also matches another
resident's unit errs toward staging — the safe direction.

## §C. Staging

A new privileged unit, and it is the only privilege this task adds:

    castle-activate-boot.service
      ExecStart = nixos-rebuild boot --flake <private>#<host>

Same fixed-command discipline as 0048 §H: one flakeref this module
already knows, no arguments from any session, readable whole in
`/etc/systemd/system`. It is strictly weaker than
`castle-activate.service`, which the same resident may already start:
`boot` sets the system profile and installs the bootloader and runs no
activation script at all.

It is added to the polkit rule's unit allowlist. It has **no
`ExecStartPost`**: staging opens no health window, because nothing has
been activated to be healthy or not.

`_activate_one` gains one branch, taken after the pin bump and before
anything is asked to move:

1. classify (a pure read of two store paths);
2. **churn-free** → `castle-activate.service`, today's path, untouched;
3. **session-load-bearing** → `castle-activate-boot.service`, and a
   result stamped `activation-outcome: staged` naming which units
   matched, saying the machine has not moved, and saying it takes effect
   at the next reboot.

The pin bump still happens first in both branches: the staged generation
is built from the flakeref, so the repository has to carry the lock the
resident approved before the boot default is set.

### The staged marker

Staging leaves a marker under `state_dir()/activation-staged/<answer-id>`
— `activation_in_flight_dir()`'s sibling, in the same place and for the
same cross-privilege reason. It must survive a reboot, so it cannot live
in `/run`. It carries, as `Key: value` lines followed by a blank line
and a body:

    answer:      the approving answer's id
    result:      the `staged` result's id
    build:       the build result's id
    toplevel:    the generation staged as the boot default
    boot-id:     /proc/sys/kernel/random/boot_id at staging time

and, as the body, **0059's check paragraph, derived at staging time**.
This is 0059 §D's own reasoning extended across the reboot: the
paragraph is computed while the repository is readable and the machine
is known good, so the question filed after the reboot carries it even
though the reboot has moved everything the derivation depends on.

## §D. The health window, and the rule it must not break

0048 §E's rule is that `castle-activation-window.timer` is started by
the activation and is never `wantedBy` a target, because *a window that
opened at boot would roll a machine back for not confirming something it
never did*.

**The rule is kept verbatim.** The timer gains no `wantedBy`. What
changes is that one more thing may start it, and only on a positive
identification.

`castle activate --sweep` — the resident's own user unit, once a minute
— gains a resolution pass that runs before everything else. For each
staged marker, exactly one of three things is true:

1. **`realpath(/run/current-system)` equals the marker's `toplevel`, and
   the current boot id differs from the marker's.** This boot *is* the
   staged activation. Castle writes an ordinary `switched` result
   anchored to the same build and caused by the same answer, files the
   health question carrying the marker's stored check paragraph, starts
   `castle-activation-window.timer`, and clears the marker. From here on
   every existing mechanism applies unchanged — `_open_windows`,
   `_close_window`, `_health_decision`, the review surface, the
   privileged closer.

2. **`realpath(/nix/var/nix/profiles/system)` no longer equals the
   marker's `toplevel`.** Something else moved the profile — a hand-run
   `nixos-rebuild`, a rollback — so the staged generation is no longer
   what this machine would boot into. Castle writes a
   `staging-superseded` result saying so and clears the marker. Nothing
   is silently dropped, and the marker cannot wedge the seat forever.

3. **Neither.** The machine has not been rebooted yet. Castle does
   nothing at all and says so.

Why the boot-id clause is load-bearing: without it, a machine whose
running generation *already* equals the staged one (a staging that
changed nothing) would open a window in the same breath as staging.
With it, the window opens only in a boot other than the one that staged
it.

Why this does not reintroduce the hazard §E exists for: the timer is
still not pulled in by any target, and the one thing that starts it
after a reboot has positively established that the machine is running
the exact closure castle staged. A boot into any other generation —
including the previous one, chosen at the boot menu — matches clause 1
on neither side and opens nothing.

**One authority is added to the polkit rule and it must be argued
rather than noticed:** the resident may now start
`castle-activation-window.timer`. 0048's own comment says granting this
would be "a widening with no purpose", and `flake.nix`'s check asserts
its absence. That comment and that assertion are both reversed here,
deliberately, and the argument is that the widening is strictly smaller
than one the resident already has. What arming the window can do is end
in a rollback; the resident can already start `castle-rollback.service`
directly, which *is* that rollback with no countdown in front of it.

### While a staging is unresolved, nothing else is spent

`cmd_activate --sweep` refuses to spend a further approval while any
staged marker remains, printing which one and why — the same shape and
the same reasoning as the existing "nothing is spent while a health
window is still open" guard. Stacking a live switch on top of a staged
boot default would leave two generations and one rollback between them,
which is the arithmetic that guard exists to prevent.

Unlike the window guard, this one does not clear itself on a timer, so
its escapes are named: the resident reboots (clause 1), something else
moves the profile (clause 2), or the resident runs `castle activate
<answer-id>` by hand — the deliberately-unbounded path 0048 already
documents as the retry path.

## §E. What the review screen must now say

`REVIEW_BOUNDARY_STATEMENT_ACTIVATION` currently promises "APPROVING
SWITCHES THE RUNNING SYSTEM TO THE BUILD DESCRIBED BELOW — this machine,
now, without asking again." After this task that sentence can be false,
and a boundary statement is the sentence a resident spends authority
under. It is amended to say that approving authorizes the switch, and
that where the switch would disturb the running session Castle stages it
for the next reboot instead and asks the health question after that
reboot.

0026 §A's rule is that a proposal offered under a statement is decided
under that statement forever, and that no later wording reaches
backwards. That rule guards against *narrowing* — against a resident
discovering they authorized more than the screen said. This amendment
moves the other way: every question it now covers authorizes strictly
less immediate effect than the old wording claimed. Saying so is what
keeps the screen true.

`ACTIVATION_QUESTION_CAVEAT` — the same fact in the question's own body,
where a digest renders it — gets the same amendment.

## §F. The records this task adds

Two values join `activation-outcome`'s closed vocabulary:

- **`staged`** — the new generation is this machine's boot default and
  nothing on it has moved. Written by `_activate_one`.
- **`staging-superseded`** — a staged generation stopped being the boot
  default before any reboot reached it. Written by the resolution pass.

No new record *type*, no new stamp, no new surface. The post-reboot
activation writes a `switched` result and a `confirms-activation`
question, both exactly as a live switch does — which is the whole reason
the window, the closer, the review screen and the digest need no changes
at all.

`agent/README.md`'s vocabulary list is extended with both, and with the
one sentence that says a `staged` result opens no window.

## §G. What the 0059 seam gets, and what it does not

0059 §B's "what to check" paragraph rides the marker across the reboot,
so a staged switch's health question is as specific as a live one's.
That is the seam the direction asked for, and it is built.

What is scoped out, explicitly: teaching that paragraph to say *why* the
obvious check will not work — "existing terminals will not show this;
open a new one" — from a derivation over which files changed. The staged
result's own body says the reboot-shaped version of it in fixed prose,
which is the part the incident needed. Mapping changed files to the
processes that re-read them is its own piece of work and is filed as
`docs/backlog/the-check-paragraph-cannot-name-a-stale-surface.md`.

## §H. What this does not do

- It does not touch the rollback unit's invocation (task 0066, PR #106).
- It does not implement a blanket defer-on-active-session.
- It does not ask whether a session exists. A machine with nobody logged
  in stages a home-manager change exactly as one with a resident at the
  keyboard does, because the classification is about the change and the
  option is about the machine. Making it conditional on a live session
  would mean the same approval behaves differently depending on when the
  sweep happened to run, which is the kind of non-determinism this
  project's records exist to keep out.

## §I. Judgment calls made under the autonomy grant

Recorded here rather than asked, per the spec workflow's autonomy
clause. Each names the reversible side and why it was taken.

1. **The classifier compares unit trees; it does not run
   `dry-activate`.** §A.1. The named oracle is blind to user-unit churn
   in this pin and costs a privileged unit to reach. Reversible: the
   records, the option and the staging path are all independent of which
   oracle produced the changed set.
2. **`dbus.service` and `systemd-logind.service` are in the default
   set**, which means an ordinary nixpkgs bump will stage rather than
   switch. The direction named them. The 17:32 switch shows a session
   surviving a dbus reload, so this default is stricter than the
   evidence requires — and the option is a list precisely so a resident
   can shorten it after watching it for a week.
3. **A staged switch blocks further activations until it resolves.** The
   alternative — letting a live switch land on top of a staged boot
   default — is the two-generations-one-rollback arithmetic 0048 already
   refuses. Its escapes are named in §D.
4. **The window opens at the first sweep after the reboot, not at boot.**
   That means a machine nobody logs into never opens a window, which is
   correct: there is nobody to answer it and nothing watching would help.

## §J. Verification plan

Agent-verifiable, and all of it in the existing harness:

- `test/agent-loop/activation.sh` gains scenarios:
  - a churn-free plan switches live — the existing scenarios, which must
    keep passing unchanged with a `CASTLE_SESSION_UNITS` set;
  - a change touching a session-load-bearing unit **stages**: the
    staging unit is the one named to `systemctl`, the switch unit is
    not, the result carries `activation-outcome: staged` and names the
    unit that matched, no `confirms-activation` question is filed, and
    **no window timer is started** — the staging moment must open
    nothing;
  - after a simulated reboot onto the staged generation, the next sweep
    writes `switched`, files the health question carrying the check
    paragraph the marker stored, and starts the window timer;
  - a profile that moved out from under a staged marker yields
    `staging-superseded` and unblocks the seat;
  - a staged marker blocks a second approval from being spent.
- `castle validate` over the resulting journal, which the file already
  runs at the end — the new outcome values have to be in the closed
  vocabulary or this fails.
- `nix flake check`, including the `example-activation` assertions,
  which are extended to cover the boot unit, the widened polkit rule and
  the `CASTLE_SESSION_UNITS` environment.

Needs human hands: experiencing a staged switch end to end on a real
machine — approve a home-manager change, watch nothing move, reboot,
watch the health question arrive. Cite
`docs/backlog/activation-is-not-proven-on-a-real-vm.md` rather than
building a VM harness here; this task does not close that entry and does
not pretend to.

## §K. File-by-file change list

- `docs/tasks/0067-an-approved-switch-is-classified-and-staged.md` —
  this file.
- `agent/castle` — the classifier, the staging branch, the marker, the
  resolution pass, two outcome values, the amended caveat.
- `agent/castle-modal` — the amended activation boundary statement.
- `agent/README.md` — the two new outcome values and what `staged` does
  not open.
- `modules/agent/default.nix` — `activation.sessionUnits`,
  `castle-activate-boot.service`, the widened polkit rule, three new
  environment variables on the activation user unit.
- `flake.nix` — the `example-activation` assertions.
- `test/agent-loop/activation.sh` — the scenarios above.
- `docs/backlog/the-switch-classifier-over-approximates.md`,
  `docs/backlog/the-check-paragraph-cannot-name-a-stale-surface.md` —
  the two residuals, filed rather than absorbed.
