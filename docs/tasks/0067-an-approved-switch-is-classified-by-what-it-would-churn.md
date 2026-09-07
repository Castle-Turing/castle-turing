Title: Task 0067 — an approved switch is classified by what it would churn, and staged accordingly
Model: deep
Model-because: the mechanism direction is resident-decided, but the
judgment is in the coupling — what the classifier is allowed to believe
about an activation plan, which default set is conservative without
being useless, and how 0048 §E's "the window never opens at boot" rule
gains a carve-out that does not reintroduce the hazard it exists for. A
standard implementer would get the happy path right and ship a window
that either never confirms a staged switch or rolls a machine back for
not confirming something it never activated. The pieces are individually
easy; only the seam between them is not.

# Task 0067 — an approved switch is classified by what it would churn, and staged accordingly

**Before starting:** `CLAUDE.md`, then `docs/tasks/done/0048-activation.md`
in full — especially §E (the health window and the asymmetry that makes
automatic rollback right), §F (the record vocabulary), and §H (why the
privileged units take no arguments). Then
`docs/tasks/0059-confirming-a-switch-suggests-what-to-check.md` for the
surface this feeds, and `modules/agent/default.nix`'s activation half.

## Provenance

A first attempt ran under an earlier framing — "weigh options for
deferring when a session is active" — and was superseded mid-run on
2026-09-06 when the resident refined the direction to the fine-grained
one below. **A blanket defer-on-active-session is the abandoned design
and is explicitly not what this builds.** No backlog entry precedes
this file; this file is the record.

## Why

Two switches ran on the same machine on 2026-09-06, under the same
logged-in session, and only one hurt.

At 17:32 the resident ran `sudo nixos-rebuild switch` by hand. Its
activation restarted polkit, SIGHUP-reloaded both D-Bus brokers, and
re-executed the resident's user manager. The session survived, as it had
survived every routine switch before it.

At 20:32 `castle-activate.service` switched to a generation whose entire
delta was one home-manager-carried config file — `foot.ini`, terminal
padding. Because the delta rode through home-manager, this was the day's
only switch that restarted `home-manager-<resident>.service`, relinking
home files and reloading user units under the live session.

What is proven, and what is not, both matter:

- **The switch invalidated the resident's verification surface.** foot
  reads its config once, at startup. No existing window could ever show
  the padding change, and a freshly opened one raced the 22-second
  build-and-activate. The resident checked, saw old padding, and
  rejected the health question at 20:33:12 — a rejection that was right
  about the evidence and wrong about the machine. The generation was
  good; a later reboot proved it.
- **The catastrophic end-state is not proven to be the switch's doing.**
  The session verifiably worked through the rejection at 20:33:12 and
  user timers ran normally until 21:14:26; the journal's final minutes
  are lost (task 0068), and a second memory-thrash event is a live rival
  hypothesis for the terminal wreckage. Nothing below rests on it. The
  false rejection alone justifies this task.

## The direction, decided by the resident

An approved switch is classified by what its activation would actually
do, and the session-affecting ones do not go through until reboot. Not a
blanket policy on "a session exists"; a per-switch classification of the
churn.

- A change that touches nothing session-load-bearing switches live —
  exactly today's behaviour.
- A change that would restart `home-manager-<resident>.service`, disturb
  the user manager, or restart or reload dbus, logind, the display
  manager or the resident's graphical session units is **staged**:
  `nixos-rebuild boot` moves the system profile and the bootloader
  default with zero runtime churn, and the resident is told it takes
  effect at the next reboot.
- The classification set is mechanism with a configurable option and a
  conservative default in `modules/` (Principle 01). Nothing hardcodes
  this machine or this resident's username.

## §A. What was verified, against the pinned tree

The brief-spec required these to be checked rather than remembered. They
were checked against the nixpkgs this repo pins
(`0e251e24a4f24e036a084b6b4b2d2491af4167f4`, whose
`switch-to-configuration` is the Rust `switch-to-configuration-ng`) and
against the home-manager input it pins.

**1. `dry-activate`'s output format is stable and parseable.** It writes
prose lines to stderr, one per verb, comma-joined and sorted
case-insensitively: `would stop the following units: …`, `would NOT stop
the following changed units: …`, `would reload the following units: …`,
`would restart the following units: …`, `would start the following
units: …`, plus `would restart systemd` and `would stop swap device: …`.
`nixos-rebuild dry-activate` reaches it through `systemd-run --pipe`, so
that output does come back to the caller.

**2. `dry-activate` cannot see user-scope churn at all.** This is the
finding that reshaped the design. In `switch-to-configuration-ng`, the
dry-run branch of `do_system_switch` ends in `std::process::exit(0)`;
the per-user fan-out that calls `do_user_switch` for every logged-in
user sits *after* that exit. The `would stop the following user units:`
strings exist in the binary but are only reachable on a live switch. So
`dry-activate` is silent about exactly the half of the machine this task
is about.

**3. `dry-activate` requires root.** It creates and writes under
`/run/nixos` (including, in the dry branch, `record_unit(RELOAD_LIST_FILE…)`)
and runs the new configuration's `$out/dry-activate` script.

**4. `home-manager-<user>.service` is a *system* unit here.** This repo
wires home-manager through `home-manager.nixosModules.home-manager`
(`flake.nix`), and that module defines
`systemd.services."home-manager-${escapeSystemdPath username}"` with
`wantedBy = [ "multi-user.target" ]`. So a home-manager delta changes a
file under `<toplevel>/etc/systemd/system` and is visible to any
comparison of the two generations' system unit directories.

**5. The logout tier does not exist in this layout, and degrades to the
reboot tier.** home-manager's NixOS module has a
`home-manager.startAsUserService` option that would activate a user's
environment at login instead of at boot; this repo does not set it, so
the default (boot-time system-unit activation) applies. Even with it
set, the user service would live in the *new* generation's
`etc/systemd/user`, which nothing reads until that generation is
activated — and after `nixos-rebuild boot`, `/etc` and
`/run/current-system` still point at the old one. **A home-manager-only
delta cannot be picked up by logging out and back in.** The two-tier
design the direction sketched collapses to one tier: live, or reboot.
Say so on the screen rather than offering a logout that would do
nothing.

## §B. The classifier, and why it is not `dry-activate`

**The mechanism is a direct comparison of the two generations' unit
files, in both scopes.** For each unit name in the configured
session-load-bearing set, compare
`<approved-toplevel>/etc/systemd/system/<unit>` against
`/run/current-system/etc/systemd/system/<unit>`; and separately compare
the whole of `<approved-toplevel>/etc/systemd/user` against
`/run/current-system/etc/systemd/user`. Differing bytes, or a unit
present on one side only, means the switch would churn it.

This is a deliberate departure from the direction's named oracle, and
the argument for it is §A rather than taste:

- `dry-activate` is blind to user-scope churn (§A.2), so a second,
  unprivileged signal is needed *regardless*. Once that signal exists,
  the same technique covers system units, and using one technique for
  both is smaller than using two.
- `dry-activate` needs root (§A.3), which would mean a third
  polkit-granted privileged unit and a second flake evaluation on every
  approval — and the unit could not take the store path as an argument
  for 0048 §H's reason (running `<attacker-path>/bin/switch-to-configuration`
  as root is the same escalation as activating it), so it would have to
  re-evaluate the flake itself.
- The comparison is a **conservative superset** of what `dry-activate`
  would report: `switch-to-configuration` decides what changed by
  comparing exactly these two directories, and only then narrows by
  `X-RestartIfChanged` and friends. Anything it would restart or reload,
  this flags; the reverse is not guaranteed. Over-staging is the
  reversible side.
- It depends on no output format, so it cannot be silently broken by a
  nixpkgs bump that rewords a line — which is the failure mode the
  brief-spec asked to be avoided.

What it concedes, stated rather than hidden: a unit whose file changed
but which NixOS marks `restartIfChanged = false` will still be treated
as churn. On the default set that is a small, correct-leaning error —
`dbus.service` is `reloadIfChanged`, and a SIGHUP to the session's bus
broker is on the direction's own list.

**Where classification is impossible** — no readable approved toplevel,
no readable `/run/current-system` — the answer is to **stage, and say
so loudly in the record**. Staging changes nothing now and is undone by
a reboot; a mechanism that silently kept switching live when it could
not tell would defeat the task. The record names the cause, so this can
never be a quiet no-op.

## §C. The staged path, end to end

1. The seat classifies, as the resident, in their session, before
   anything is asked to move. `_health_check_lines` is derived at the
   same moment and for the same reason 0059 §D gives.
2. Live: `castle-activate.service`, unchanged. Nothing in 0048's switch
   path is touched.
3. Staged: `castle-stage.service` — a **new** privileged unit whose
   whole `ExecStart` is `nixos-rebuild boot --flake <repo>#<host>`, the
   existing unit's line with one word changed, added to the same polkit
   allowlist and scoped the same way. It moves the system profile and
   the bootloader default and activates nothing.
4. The seat writes an `activation-outcome: staged` result naming every
   unit that would have churned, and writes a **marker** under the
   state directory recording the staged toplevel (read back from
   `/nix/var/nix/profiles/system` after the unit ran, not assumed from
   the build), the id of that result, and the check-lines derived in
   step 1.
5. **No health window opens.** Nothing has been activated; there is
   nothing to confirm and nothing a rollback would undo.
6. At the next boot, `castle-staged-boot.service` runs
   `castle activate --staged-boot` as root. It consumes the marker —
   once, whatever booted — and if `/run/current-system` is the staged
   toplevel it writes an `activation-outcome: switched` result, files
   the ordinary health question with the check-lines the marker
   carried, and starts the staged window timer. If the machine booted
   something else, it writes a result saying so and opens nothing.

Step 6 is what keeps the rest of 0048 untouched: `_open_windows`,
`_close_window`, the health question, the boundary statement and the
rollback unit all key off a `switched` result, and after a staged boot
that is exactly what exists.

## §D. The carve-out in 0048 §E's rule, and why it is still safe

0048 §E: the window timer is started by the activation, never wanted by
a target, because "a window that opened at boot would roll a machine
back for not confirming something it never did."

The carve-out is not "the window may open at boot". It is: **the window
opens at a boot that this mechanism can prove is the activation of a
generation it staged and nobody has confirmed.** Both halves are
checked in one place, against a marker this mechanism itself wrote, and
the marker is consumed on the first boot after staging so it cannot
fire twice or fire late.

The hazard the rule exists for is a window with nothing behind it. Here
there is: the boot *is* the activation the resident approved. What
0048 §E's asymmetry then says applies verbatim — a good generation
rolled back costs one cheap re-approval, a bad one left running costs a
trip to the machine — and it applies with more force here, because the
failure this whole task is about is a change that makes the resident's
session unusable. If a staged generation breaks the display manager, the
resident can never log in to confirm, the window expires, and the
machine rolls itself back. That is the case the boot-time window exists
for, and it is the reason the window must **not** instead be armed by
the resident's own session seat: a window that only opens when the
session comes up is useless exactly when the session does not.

**The window is longer at boot, and that is a separate option.** The
live window (`activation.windowSeconds`, 900) is measured from a
keypress the resident just made. A staged window is measured from
power-on and has to cover the boot, the login and the noticing.
`activation.stagedWindowSeconds` defaults to 1800 and has its own timer
unit firing the same window-closing service.

## §E. What the resident is told

The activation question is filed at build time, before classification,
so its boundary statement has to be true of both outcomes. It gains one
paragraph: approving authorizes the change to take effect, and Castle
first works out whether activating it would disturb the logged-in
session — if it would, it makes the change the boot default instead of
switching now, and says so.

This is a widening of a sentence residents decide under, so it is worth
being explicit: **staging is strictly less than switching.** A question
already open under the old wording, which promised a live switch, may
now be staged instead. The resident gets less than the sentence
promised, never more, and the result record says exactly what happened.
That is the direction 0026 §A's rule is safe in.

The `staged` result names the units that would have churned, in the
resident's own words rather than as a unit dump: this is the seam 0059
asked for, and it is now carrying the fact that motivated the whole
task — that a change of this kind is not visible in a process that was
already running.

## §F. Scope, and what is deliberately not here

- **The rollback unit's invocation is untouched** (task 0066, PR #106).
- **`castle-activate.service` is untouched.** Staging is a new unit
  beside it, not a change to it.
- **0059's full plan-to-prose mapping is out of scope.** The staged
  result names the units and the reboot; teaching the health question to
  say "existing terminals will not show this" from the churn set is a
  follow-up. The seam is the marker's check-lines field, which already
  travels from the staging moment to the health question.
- **No logout tier**, for §A.5's reason, and the screen says reboot
  rather than offering something that would not work.

## §G. Judgment calls a reader should be able to argue with

1. **Direct unit comparison instead of `dry-activate`.** §B. The
   brief-spec authorised the narrower signal if the plan was unreliable;
   what was found is not instability but blindness (§A.2) plus a
   privilege cost. Recorded here in full so nobody re-runs the
   investigation.
2. **`stageOnUserUnitChange` defaults to true.** The NixOS-managed user
   unit tree includes castle's own seats, so a change to the agent layer
   will usually stage rather than switch live. That is the direction's
   own "re-execute the user manager" clause taken seriously, and
   restarting the seat that is spending the approval is genuinely
   session-load-bearing. The cost — that castle's self-updates land at
   the next reboot — is real, is documented on the option, and `false`
   is the escape.
3. **Unclassifiable stages.** §B. The alternative, switching live when
   we cannot tell, is the failure this task exists to stop.
4. **The marker is consumed on the first boot after staging, whatever
   booted.** Leaving it for a later matching boot would mean a window
   opening on a generation the resident chose from the boot menu weeks
   later, with no memory of having approved it. Bounded and legible
   beats complete.
5. **A staged switch does not block the next approval.** 0048's
   "one unconfirmed generation at a time" guard keys off open windows,
   and a staged switch opens none. Two stagings before a reboot simply
   compose — the last generation staged is the one that boots. Stacking
   is only dangerous when a rollback has to choose between them.

## §H. Verification plan

**Agent-verifiable, in `test/agent-loop/activation.sh`:**

- a churn-free plan switches live — `castle-activate.service` in the
  stub `systemctl` argv, no marker, a health window open as today;
- a plan naming a session-load-bearing unit stages instead —
  `castle-stage.service` in the argv, `castle-activate.service` absent,
  an `activation-outcome: staged` result that names the unit and says
  the change takes effect at the next boot;
- a staged switch opens no window at the staging moment — no health
  question, no window timer started, and the sweep does not consider
  itself blocked;
- `--staged-boot` on a matching boot writes a `switched` result, files
  the health question and starts the staged window timer; on a
  non-matching boot it writes a result saying so and opens nothing;
- the marker is consumed either way.

**`nix flake check`** for the new options, the new units and the widened
polkit rule.

**Needs human hands:** experiencing a staged switch end to end on a real
machine — approve a home-manager-carried change, watch it stage, reboot,
and meet the health question after login. Cited rather than built:
`docs/backlog/activation-is-not-proven-on-a-real-vm.md`.
