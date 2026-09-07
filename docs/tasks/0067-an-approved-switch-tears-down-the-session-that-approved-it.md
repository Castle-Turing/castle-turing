Title: Task 0067 — an approved switch tears down the session that approved it
Model: deep
Model-because: the deliverable is a policy decision — when a machine
may change under its resident — coupled to the health-window safety
story 0048 §E built and the approval-wording discipline 0025 binds.
A standard implementer would satisfy the letter with "defer when a
session is active" while quietly orphaning the window's rollback
semantics, or would move the choice onto the approval screen without
noticing what that screen's discipline forbids. The judgment is the
deliverable; the diff is small whichever way the judgment goes.

# Task 0067 — an approved switch tears down the session that approved it

**Before starting:** read `CLAUDE.md` and
`.claude/skills/implement-brief/SKILL.md`; both bind everything below.
Then `docs/tasks/done/0048-activation.md` — §D (what an approval
buys), §E (the health window, and why its timer never opens at boot),
§F (the outcome fields) and §H (the privileged units take no
arguments); `docs/tasks/done/0025-approval.md`, whose exact-wording
discipline binds every sentence this task puts on the approval screen;
`docs/tasks/0059-confirming-a-switch-suggests-what-to-check.md`, whose
check paragraph this task reuses on a second kind of result; and the
activation half of `modules/agent/default.nix` (the two privileged
units, the polkit rule) together with `agent/castle`'s `_activate_one`
and `cmd_activate`.

No backlog entry precedes this brief. The record of what happened is
below, taken from the journal of the previous boot on 2026-09-06.

## What happened

At 20:32:15 the resident approved a switch. At 20:32:16–38
`castle-activate.service` ran `nixos-rebuild switch` on the live
machine. switch-to-configuration reloaded PID 1, then re-executed and
reloaded the resident's *user* manager, restarted the user units whose
definitions had changed, and restarted `home-manager-wesley.service`
and the user activation units — under the resident's running desktop.

The session degraded immediately: running clients held dead
session-bus connections, the castle-modal chords stopped answering,
and binaries stopped resolving in already-open terminals. At 20:32:38
the switch filed its health question; at 20:33:12 the resident
answered that the machine was not working — a correct answer, and one
*caused by the asker*. The machine asked "is it working?" down the
wire it had just cut. The rollback that reject triggered then failed
(task 0066's defect), but note that even a working rollback would have
been a second live switch under the same session. The evening ended on
the power button.

One fact sharpens it: the switched-to generation was closure-identical
to the one running — `nix store diff-closures` between generations 24
and 25 is empty. All of that risk bought nothing.

## §A The finding, stated once

**A live `nixos-rebuild switch` is not a background act on a machine
somebody is using.** It is, by design, a restart of the units a
session is made of. Read in nixpkgs 26.11,
`pkgs/by-name/sw/switch-to-configuration-ng/src/main.rs`:

- after the system-side work, `do_system_switch` walks
  `logind.list_users()`, and for every user whose `/run/user/<uid>`
  exists — that is, every user with a live user manager — re-executes
  itself as that user against that runtime directory (the `list_users`
  loop, around line 2382);
- the per-user pass reloads that user manager and reloads, restarts
  and starts the user units whose definitions changed (the
  post-activation blocks around lines 1660–1720);
- and it restarts `nixos-activation.service` for that user
  unconditionally — it is removed from the skip map by name and
  restarted with no condition (around lines 1498 and 1599).

None of that is a bug. It is what "activate this configuration now"
means. The mistake is asking for it on a machine whose resident is
sitting in front of it, and then asking that resident, through the
session it just restarted, whether everything is all right.

## §B The decision

**When anybody is logged in, an approved activation is staged for the
next boot instead of switched into the running machine.** Staging is
`nixos-rebuild boot`: it builds, installs the bootloader entry and
makes the new generation the boot default, and it touches no running
unit. That last clause is evidence rather than reputation — in the
same file, `Action::Boot` calls `std::process::exit(0)` immediately
after the bootloader installation and the `/nix/store` sync, before
any unit is stopped, started or reloaded and before the user fanout
above exists to be reached (around line 1859).

A live switch happens only where nothing is logged in — or where a
private layer says otherwise, with
`castle.agent.activation.whenSessionActive = "switch"`.

Principle 01 holds: the mechanism is public (ask logind, pick one of
two privileged units, record which one ran), and what is private is
the policy value and the account it is granted to.

The word for the staged path is **"staged"**, and it is chosen rather
than inherited. "Defer" is taken: the review surface's three decision
keys are approve / reject / **defer**, where defer means *decide
later*. A second axis on the same screen whose values were "now" and
"later" would put two meanings of later in front of one resident.
"Staged" already carries exactly this meaning in the wording this
project publishes — `ACTIVATION_QUESTION_CAVEAT` has said since 0048
that a kernel change "is staged into the new generation and takes
effect at the next boot instead".

## §C What was weighed and not chosen

**Carrying the choice on the approval screen** — "switch now, or at
next boot?" — is refused for three reasons, and the first is
mechanical rather than aesthetic.

1. The activation question is filed by the *builder*, when the build
   finishes, and is spent by the *activation* seat whenever the
   resident gets to it. The screen therefore cannot know whether a
   session will be open at the moment the approval is spent. It would
   be asking the resident to predict a state the mechanism can simply
   observe.
2. It spends the one screen in this system where authority over the
   running machine is granted. 0048 §E refused a defaulted question
   for the health window because a question with a default trains a
   reflex; a second axis on the approval screen makes that screen
   busier and each yes cheaper, which is the same defect one layer
   out.
3. The vocabulary collision above.

Nothing here forecloses it. If the resident later wants the choice, it
is an extra answer key on a question filed at *spend* time, and the
two units this brief declares are exactly what it would drive.

**Narrowing what a live switch may restart** is refused on evidence,
which §A is: there is no such knob. The user fanout is unconditional
over `logind.list_users()`; `nixos-activation.service` is explicitly
removed from the skip map and restarted, so it is not reachable by the
`restartIfChanged`/`stopIfChanged` machinery at all; and the units
that would have to carry those properties are declared by nixpkgs and
by home-manager, not by this repo. Suppressing session churn would
mean shipping per-unit overrides against units this project does not
own, for a desktop it does not define — a host assumption in
`modules/`, and one that would break silently on the next nixpkgs
bump, in the direction of tearing the session down again.

**Doing nothing, and warning on the screen**, is refused because the
machine has every fact it needs to avoid the incident and a warning
would move the cost onto the resident's memory.

## §D What counts as a session, and how it is detected

One call, `loginctl list-sessions --json=short`, parsed as JSON. A
session counts as interactive when its `class` begins with `user` —
which covers `user`, `user-early` and `user-incomplete`.

- No username appears anywhere in the test. switch-to-configuration's
  fanout is over *every* user with a live manager, so the question is
  "is anybody logged in", not "is the resident logged in", and
  `castle.agent.activation.user` has no business being consulted.
- `manager` is deliberately excluded. logind reports a second session
  of that class for a running `user@.service`; on the incident's own
  host, `loginctl` listed session 3 (`class=user`, the desktop) and
  session 4 (`class=manager`). Counting the manager class would make
  any host with lingering enabled look permanently occupied, which is
  the one configuration where a live switch is safe.
- `greeter` is excluded for the same reason it is a different class:
  nobody is working in it.
- The `State` property is not consulted, and this is a choice.
  `list-sessions` does not carry it, so using it costs one
  `show-session` per session, and the only thing it could buy is
  treating a `closing` session as absent — a second call whose only
  possible effect is to choose the dangerous path more often. A
  session that is closing still has a live user manager.

**Every fault is conservative.** `loginctl` missing from PATH, a
non-zero exit, output that is not JSON, or a shape this code does not
recognise all mean *stage*, and the result says which fault produced
that. The opposite default — assume the machine is empty, switch live
— is the exact failure this task exists to remove.

## §E The health window, and what a staged change gets instead

A staged change **opens no window, files no health question and arms
no timer.** Three reasons, in order of weight:

1. There is nothing to confirm. The running machine is untouched; a
   question asking whether the new configuration works would be asked
   of a machine that is not running it.
2. The window's timer deliberately never opens at boot — "a window
   that opened at boot would roll a machine back for not confirming
   something it never did" — and this task does not touch that. It
   also must not work around it: a window opened after the reboot
   would, at its deadline, run `nixos-rebuild switch --rollback` on a
   live machine under a fresh session, which is the very act this
   brief removes.
3. The rollback the window performs is itself a live switch. Staging
   has no equivalent to perform.

What replaces it is the bootloader menu. The generation running when
the change was staged is still in that menu and is still the one
`/run/current-system` points at until the reboot; choosing the older
entry undoes the staged change with no working desktop required. That
trade is stated in both directions rather than sold: it is weaker in
that nothing acts on its own, and a resident who reboots into a broken
machine must choose the older entry themselves; it is stronger in that
it does not depend on a session being alive to ask a question through
— which is the failure mode that produced this task.

**Nothing is silently dropped.** The staged result says, in its own
body, that the change is not live, that no window is open and nothing
will roll back on its own, and what to do at the next boot if the
machine comes up wrong. It also carries 0059's check paragraph, which
is derived before anything moves and is exactly as useful for "when
you reboot, check this" as it was for "before you confirm, check
this".

The existing gate — nothing is spent while a health window is still
open — is unchanged and applies to staging too. A stage rewrites the
boot default, and doing that underneath an unconfirmed live switch
would leave the resident's own rollback ambiguous.

## §F Records and wording

- Two new `activation-outcome` values, `staged` and `stage-failed`,
  beside `switched` and `switch-failed`. A new value in an existing
  field: what happened to the machine is exactly what this field is
  for, and a staged change is a different thing from a switched one.
  Their first lines join `ACTIVATION_FIRST_LINES` in the same voice.
- `staged` counts as success for a hand-run `castle activate
  <answer-id>`'s exit code. A resident who typed the command got the
  conclusion the policy names, and the record says which one it was.
  The policy is not overridden by the hand path: running it from a
  terminal is running it from a session, which is the case that stages.
- The approval question's body changes, because the sentence a
  resident approves under must be true of what approving does (0025).
  It gains the fork — switched now if nobody is logged in, staged for
  the next boot if somebody is — and a second caveat sentence saying
  why. The first line stays the notification and picker preview, so it
  stays one paragraph.
- **Approvals already in a journal were granted under the old
  sentence.** Spending one by staging is inside what that sentence
  granted: it authorized changing this machine to that configuration
  now, and staging does strictly less to the running machine while
  leaving the rest to a boot the resident performs. Nothing widens; it
  is recorded here rather than left to be found.
- The activation in-flight marker gains a `mode:` line, and the
  reconciliation reads it. Without it, an attempt that crashed
  mid-stage is reconciled with prose written for a switch — "those
  differ, so the switch did not take effect" — which is false of a
  stage that may well have completed. Absent `mode:`, a marker is read
  as a switch, which is what every marker written before this change
  was.

## §G The module surface

- `castle.agent.activation.whenSessionActive`, an enum of `"stage"`
  and `"switch"`, default `"stage"`, wired to the CLI through
  `CASTLE_ACTIVATION_WHEN_SESSION_ACTIVE` on both the user unit and
  `environment.sessionVariables` — the latter for the reason the
  window and timeout already ride there: a hand-run `castle activate`
  must obey the same policy the unit does rather than the CLI's own
  fallback.
- A third privileged unit, `castle-stage.service`, carrying one fixed
  command — `nixos-rebuild boot --flake <repo>#<host>` — with no
  `ExecStartPre` snapshot and no `ExecStartPost` arming, because it
  opens no window. §H's rule is kept exactly: the ExecStart line is
  the grant, and nothing reaches it from a session.
- The polkit rule grants the resident's account that third unit name
  by name. This widens the standing grant by one command, and the
  command is strictly weaker than the one already granted: `boot` is
  what `switch` does minus everything that touches a running unit,
  against the same repository, the same flakeref and the same account.
- `CASTLE_STAGE_UNIT` on the user unit beside the two existing unit
  names, overridable so the harness can point it at a stub and never
  so a caller can widen the grant — polkit scopes by unit name.

## §H The consequence, stated rather than discovered

Castle deliberately does not enable lingering, so the resident's user
manager — and therefore `castle activate --sweep` — exists only while
a session does. With the default, **on a single-user desktop host
every approved activation stages**, and the live path is reached only
by a host that enables lingering, a headless one, or a private layer
that sets `whenSessionActive = "switch"`. That is the intended end
state, not a side effect: the machine does not rebuild itself
underneath the person using it. 0048's title now reads with a clause
attached — Castle rebuilds the machine it is running on, at that
machine's next boot.

The cost is real and belongs in the PR: a change the resident approved
is not live until they reboot. Whether that trade is right is a
preference only the resident can state; this brief takes the
reversible side, which is the one where an approved change waits and
nothing that was working stops working. Flipping it is one option in
the private layer.

## §I Verification plan

Agent-verifiable, and the agent runs all of it:

- `test/agent-loop/activation.sh` gains a `loginctl` stub whose output
  the harness controls, and three scenarios: an eligible approval met
  by an active session stages (the stage unit is asked, the activate
  unit is not, no health question is filed and no window is open
  afterwards); an eligible approval with no session switches, exactly
  as today; and a `loginctl` that cannot answer stages. The existing
  scenarios keep their meaning by declaring no session, which is what
  they have always assumed.
- `test/agent-loop/run.sh` in full, and `nix flake check`.

Needs human hands: experiencing a staged change on the real machine —
approve, see the record say it is not live, reboot, see it come up on
the new generation. A full VM session test stays out of scope for the
reason `docs/backlog/activation-is-not-proven-on-a-real-vm.md`
records; this task adds a second path to what that entry already says
is unproven on a real VM, and does not pretend to close it.
