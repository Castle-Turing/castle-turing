# Task 0020 — Laptop ergonomics for the reference host

**Before starting:** read `CLAUDE.md`; `docs/vision.md`, specifically the
attention-management material (deep-focus mode, the graduated
intervention ladder, "a status bar turning amber", and the standing
claim that the agent will eventually have opinions about the screen);
`modules/desktop/default.nix` and `modules/home/default.nix` — how
`castle.display.*` is declared in one and consumed in the other behind
`swayEnabled`, and the long comment above `keybindings` explaining the
`lib.mkOptionDefault` priority trap; `hosts/xps9370/default.nix`;
`docs/tasks/0003-findings.md`, findings #2, #5, #10 and #11, which are
why suspend is the risky item here; and
`docs/tasks/0014-default-wallpaper.md` for the option-plus-CI-check
pattern this mirrors, including its habit of watching a new check fail
once before trusting it. Work on branch `laptop-ergonomics`; this brief
rides it. PR to `main`.

**In-flight collision, known at spec time:** this brief is written
against `origin/main` at `d6ea1fd`. Task 0017 (branch
`legible-defaults`, unmerged) rewrites the `bars` block in
`modules/home` and the display section of `docs/private-layer.md`;
another in-flight branch also touches `modules/home`. Before
implementing, `git fetch` and re-establish what those files actually
contain (CLAUDE.md's stale-base rule). If a `bars` definition has
landed, remember home-manager's semantics: defining `bars` *replaces*
the default bar rather than merging with it, so `statusCommand`
silently vanishes unless restated. Expect a merge conflict there and
treat whatever has landed as the base; items 3 and 6 note the specific
touchpoints.

**Goal.** The reference host stops being a machine that boots a
compositor and becomes one someone can use on a couch for an evening:
brightness and volume keys work, the lid does something sane that has
actually been tested, the battery is visible, the status bar stops
reporting non-faults as faults, low battery does not end the session by
surprise, the screen *can* be told to blank, and the touchpad settings
the resident currently hand-writes as raw Sway config have a `castle.*`
slot to move into.

## Why

This promotes the `laptop-ergonomics` backlog entry, deferred as an
explicit non-goal of `docs/tasks/0005-dogfooding-desktop.md` to keep
that milestone focused on whether the machine could host its own
development. It could. What it still cannot do is be picked up and used
without thinking about it, and that gap — between a demo and a machine
someone lives in — is the whole of this task.

The entry asked two questions this brief answers rather than inherits.
*Where does the option surface sit?* Per item, below, with the
`modules/` ↔ `hosts/` line argued each time. *Does idle/lock belong
here or with the future attention-management work?* The mechanism here,
the policy there — see scope item 4 and the non-goal that guards it.

## What already arrives free — establish it, do not rebuild it

Verified at spec time against the pinned inputs (`flake.lock`: nixpkgs
`0e251e24…`, home-manager `c8058ec…`, nixos-hardware `2dda192…`).
Re-verify before relying on any of it — pins move, and this repo has
been bitten by trusting a snapshot (0003 finding #9).

- **Nothing in `modules/` or `hosts/` mentions any of this yet.** A
  grep across both for `natural_scroll`, `input type`, `brightnessctl`,
  `wpctl`, `XF86`, `touchpad`, `lidSwitch`, `logind`, `upower` and
  `idle` returns nothing. Genuinely unimplemented, not
  half-implemented.
- **nixos-hardware `dell-xps-13-9370` does less than its reputation
  suggests.** It sets `mem_sleep_default=deep`, blacklists `psmouse`
  (the touchpad is i2c), `services.thermald.enable = true` (a hard
  `true`, not `mkDefault` — undoing it needs `mkForce`),
  `services.throttled.enable = lib.mkDefault true`, i915 parameters and
  Intel microcode, and via `common/pc/laptop` sets `services.tlp.enable
  = lib.mkDefault (!config.services.power-profiles-daemon.enable)` with
  no TLP tunables at all. It touches nothing for media keys,
  brightness, lid handling, upower, or idle. The backlog entry's
  "sensible power management" is already here and is not this task's
  job: do not re-add it, and do not start configuring TLP.
- **`brightnessctl`, `swayidle` and `swaylock` are already installed.**
  `programs.sway.enable` (set by `modules/desktop`) brings
  `programs.sway.extraPackages`, defaulting to `[ brightnessctl foot
  grim pulseaudio swayidle swaylock wmenu ]`; nixpkgs'
  `wayland-session.nix` also turns on `security.polkit` and registers
  `security.pam.services.swaylock`. Confirm before adding any of those
  packages yourself.
- **`wpctl` is already on PATH.** The wireplumber submodule (on by
  default whenever pipewire is) adds `pkgs.wireplumber`, whose output
  includes `bin/wpctl`, to `environment.systemPackages`.
- **A status bar already exists, and it shows the battery.**
  home-manager's Sway module defaults `config.bars` to a single bottom
  bar with `statusCommand = "${pkgs.i3status}/bin/i3status"`, and
  `modules/home` on this base says nothing about bars. With no user
  config, i3status falls back to the config compiled into its own store
  path, ordering `ipv6`, `wireless _first_`, `ethernet _first_`,
  `battery all`, `disk /`, `load`, `memory`, `tztime local` (`_first_`
  means no interface name is hardcoded). Item 3 fixes what that default
  gets wrong on this chassis.
- **The lid mechanism already exists too, untested.** The pinned
  `services.logind` module writes only `KillUserProcesses=false`; every
  `Handle*` setting is left to systemd's compiled-in defaults, which on
  systemd 261 are `HandleLidSwitch=suspend`,
  `HandleLidSwitchDocked=ignore`, `HandlePowerKey=poweroff`, and — the
  non-obvious one — `HandleLidSwitchExternalPower` ignored entirely
  unless explicitly set, so closing the lid on AC suspends as well. A
  compositor holding the `handle-lid-switch` inhibitor lock would make
  these irrelevant; Sway takes no such lock by default, and
  home-manager's `bindswitches` defaults to `{}`.

Two option-shape facts that will otherwise cost time: on this nixpkgs
pin the flat `services.logind.lidSwitch`-style options are renamed into
`services.logind.settings.Login.*` (old names warn); and
`hardware.brightnessctl` was removed outright, the removal message
stating that current brightnessctl no longer needs udev rules because
it can use the systemd-logind API.

## Where the `modules/` ↔ `hosts/` line falls

`CLAUDE.md`'s "no hardware assumptions in `modules/`" is the rule this
task tests hardest, so place each item deliberately:

- **`modules/`** — XF86 keysym bindings and the commands they run, the
  touchpad option surface, the idle mechanism, the status-bar mechanism
  and its fact-driven filtering, `services.upower.enable` and the
  option naming its critical action. None assume a chassis: a machine
  with no backlight just has a binding that does nothing, and upower
  with no battery reports no battery.
- **`hosts/xps9370`** — two values only: the upower critical action
  (item 3, constrained by this machine's disk layout) and the
  no-ethernet-port fact (item 3, a property of the chassis).
- **nixos-hardware** — the S3 forcing and everything else
  chassis-specific is already there and stays there. Do not fork or
  patch it.

Principle 01's split, stated once: which keysym runs which command,
which options exist, and what the mechanism can do are framework. The
resident's keybinding layout, chosen idle timeout, scroll direction and
tap preference are private-layer, each reachable by overriding an
option rather than editing this repo.

## Scope

### 1. Media and brightness keys

Bind `XF86MonBrightnessUp`/`Down` to `brightnessctl`, and
`XF86AudioRaiseVolume`/`LowerVolume`/`Mute`/`MicMute` to `wpctl`. Cap
the volume ceiling (`wpctl set-volume -l 1.0 …`) so a held key cannot
push the sink into software boost.

The bindings go into `modules/home`'s **existing** `keybindings`
attrset, inside the existing `lib.mkOptionDefault` wrapper — read the
comment above it first. Do not add a second `keybindings` definition:
an unwrapped one silently discards home-manager's entire default set
(the 0009 finding-1 lockout), and two same-priority definitions of the
same key throw. XF86 keysyms collide with nothing home-manager ships —
its defaults are all Mod-prefixed chords — so the per-key merge is a
clean union.

Reference the binaries by absolute store path, not bare names on
`$PATH` — a deliberate difference from the `castle-modal` binding
directly above them, which uses bare names to keep `modules/home`
decoupled from `modules/agent` at the Nix level. No such decoupling
applies here, and a keybinding that silently does nothing because a
binary is missing from `$PATH` is the "option pointing at nothing"
class 0014's item 5 exists for. Say so in a comment. For `wpctl`,
reference `config.services.pipewire.wireplumber.package`, not a bare
`pkgs.wireplumber`, so a private layer overriding the daemon does not
end up driving it with a mismatched control tool.

Establish which permission path brightnessctl takes rather than
assuming. On this pin it should be the logind one: built with systemd
support, it falls back to `org.freedesktop.login1.Session.SetBrightness`
when the sysfs file is not writable — no group membership, no udev
rules, only an active logind session on the seat, which greetd gives.
(The package ships udev rules, but nothing adds them to
`services.udev.packages`.) If the logind path does not work, the fix is
`services.udev.packages` plus `video` group membership, and that
membership belongs in `modules/desktop` — not `modules/base`, where it
would land on headless hosts with no backlight.

`bindsym --locked`: considered and rejected. It only matters while a
session-lock client holds the screen, and this task ships no lock (item
4); home-manager's renderer also has no per-binding flag, so obtaining
it would cost the clean `mkOptionDefault` merge. Revisit when a lock
policy is actually decided — which is not here.

### 2. Lid close, suspend and resume — included, and tested deliberately

**First establish, then decide, then probably change nothing.** Report
in the PR what the effective `HandleLidSwitch` /
`HandleLidSwitchExternalPower` / `HandlePowerKey` actually are on this
pin with nothing set (the section above is the starting point; verify
it). If the stock defaults are what is wanted, add no
`services.logind.settings` at all — a declaration that merely restates
upstream is config noise that will drift and imply a decision nobody
made. "Verified the default is correct" is a real deliverable for this
item.

Do **not** move lid handling into Sway's `bindswitches`: logind's
handling also covers the greeter and a bare TTY, and two handlers for
one switch is how a machine suspends twice. Record that choice. Also
record, without changing it: `HandlePowerKey=poweroff` means an
accidental power-key press ends the session with no confirmation.
Whether that should change is a real question and explicitly not this
task's to answer — note it for the resident.

**The risk is specific and not hypothetical.** The pinned
nixos-hardware module forces S3 over the firmware's default s2idle via
`mem_sleep_default=deep`; its own `README.wiki` says the manufacturer's
s2idle default is intentional and that forcing S3 "might cause
lockups", with the module author reporting no personal issues. One
person's anecdote is the entire evidence base standing between this
machine and a resume that never comes, and this chassis already has a
documented boot-path history (0003 findings #2 and #5).

Add one cheap regression check: assert that `hosts/xps9370`'s evaluated
`boot.kernelParams` still contains `mem_sleep_default=deep` — not
because the value must never change, but because a future nixos-hardware
bump that drops or flips it would change this machine's sleep behaviour
with nothing in this repo mentioning it. Same shape as `flake.nix`'s
existing three-layer `castle.display` assertion.

**The ladder. Human hands, in this order, no skipping:**

1. On the deployed machine, `cat /sys/power/mem_sleep` — confirm `deep`
   is the *bracketed* selection, not merely listed. If not, the S3
   forcing is not in effect and everything below tests something else.
2. Open an SSH session from another machine and leave it open. This is
   the observation post: it distinguishes "hung" from "resumed" from
   "off".
3. `systemctl suspend` from the keyboard, lid open. Wake with a key.
   Confirm from the SSH side that the session survived, and read
   `journalctl -b -u systemd-suspend.service` and `journalctl -b |
   grep -i 'PM: suspend'` for a matched entry/exit pair.
4. Only then close the lid. Confirm it suspends, and resumes on open.
5. Repeat 3 and 4 once on battery and once on AC —
   `HandleLidSwitchExternalPower` is a separate setting, and testing
   one power source proves half the behaviour.
6. Record what actually happened — including resume timings if slow —
   in a Findings section appended to this brief in the same PR, the way
   0014 appended its implementation notes. A pass is a result; so is a
   hang.

**Recovery path, known before the first suspend, not discovered during
a hang:**

- Force power-off: hold the power button ~10s. Safe here — the disk is
  unencrypted and the root filesystem journalled, so a dirty shutdown
  costs an fsck, not the install.
- If it will not boot afterwards, 0003 findings #2 and #5 are the map:
  F12 is the reliably reachable one-time boot menu on this chassis, the
  custom installer image (`modules/installer.nix`, tasks 0006/0012) is
  SSH-reachable, and `EFI/BOOT/BOOTX64.EFI` on the ESP is the first
  thing to check.
- **Rollback is not the remedy for a resume hang.** If this item
  changes no sleep-related option, no generation behaves differently.
  The real escape is the S3 forcing itself, in two forms — know both
  before starting. At runtime, as root: `echo s2idle >
  /sys/power/mem_sleep`, effective immediately, surviving nothing.
  Declaratively: append `mem_sleep_default=s2idle` in `hosts/xps9370`
  and *verify by reading `/sys/power/mem_sleep`* rather than trusting
  the kernel's handling of a duplicated parameter; if appending does
  not win, the fallback is `lib.mkForce` over the whole
  `boot.kernelParams` list, which means re-listing nixos-hardware's
  i915 parameters explicitly — read that closure before doing it.
- If this machine ends up on s2idle, that is a finding worth writing up
  and probably reporting upstream. Do not leave it living on a
  hand-typed sysfs value.

### 3. Battery status, the bar's false faults, and low-battery handling

**Battery visibility is already there** — the default bar's i3status
shows `battery all` (see above). Confirm on the real machine rather
than infer; a private layer that replaced `bars` would change the
answer.

**But the same stock config reports non-faults as faults.** On a
Wi-Fi-only chassis with no ethernet port, `ethernet _first_` renders a
permanent red fault; `ipv6` renders red whenever the network has no
IPv6. Both display as errors; neither is one on this machine. A status
surface that cries wolf about non-faults is exactly the wrong
foundation for the "status bar turning amber" intervention channel
`docs/vision.md` names — the bar's idle state must be quiet so that
color can eventually mean something.

The fix must not become "the framework drops the ethernet entry" —
"this machine has no ethernet port" is precisely a hardware assumption,
and a desktop host with an unplugged port *should* show that fault.
Split it:

- **Mechanism in `modules/`**: take ownership of the status
  configuration via home-manager's `programs.i3status` (guarded by
  `swayEnabled`), keeping its `enableDefault` block set — verify at the
  pin that this reproduces the compiled-in default set, and that the
  default bar's `statusCommand` picks up the user-level config file
  without touching the `bars` block at all (i3status reads
  `$XDG_CONFIG_HOME/i3status/config` before its compiled-in fallback;
  leaving `bars` alone also minimizes the 0017 collision noted in the
  preamble). Disable the `ethernet _first_` module when the chassis
  declares no wired port, and drop the `ipv6` module unconditionally.
- **The ipv6 entry is a different case from ethernet**, so its
  treatment gets its own argument: IPv6 presence is a property of the
  *network environment*, not of any machine, and a persistent red error
  for a perfectly normal environment is a false alarm on every host —
  a framework-level fix, not a chassis fact. Rejected alternative: a
  per-host knob for it, which would encode a network environment into a
  host module — the wrong layer twice over.
- **Fact in `hosts/xps9370`**: declare the chassis fact through a new
  option, `castle.hardware.hasEthernet` (bool, default `true`,
  declared in `modules/desktop` beside the other `castle.*` surfaces),
  set `false` with `lib.mkDefault` by the host — whose own comment
  already states Wi-Fi is this chassis's only network path. Default
  `true` because showing a wired port's state is correct wherever one
  exists. Rejected shape: a "which bar entries" UI knob — that would
  have the host module reaching into presentation, when what the host
  actually knows is what hardware exists; the framework owns the
  mapping from fact to presentation.
- Do **not** go further than removing the false faults: no colors,
  fonts, reordering, or replacing i3status with a richer status
  program. A replacement was considered and rejected — it would force
  rewriting the `bars` block (the exact surface 0017 is rewriting in
  flight) and buys nothing this task needs. `modules/home`'s own
  comment says this config is a foothold, not a ricing project, and the
  bar's contents are precisely what the graduated-intervention work
  will want to renegotiate. (One known cosmetic nit to check while
  there: home-manager's default bar emits `tray_output primary`, an
  X11 concept Sway warns about.)

**Low battery: enable `services.upower` in `modules/desktop`.** Generic,
and `modules/desktop` already owns the graphical session's daemons.

**The trap is real and is the reason this half-item exists.** upower's
`criticalPowerAction` defaults to `HybridSleep` on this nixpkgs pin
(enum: `PowerOff`, `Hibernate`, `HybridSleep`, `Suspend`, `Ignore`; the
last two additionally require `allowRiskyCriticalPowerAction = true`).
`hosts/xps9370` runs zram-only swap with no swap partition and its own
comment says there is no hibernation use-case — so the default action
has nowhere to write an image and cannot complete, at exactly the
moment the machine is about to die. Re-verify in
`nixos/modules/services/hardware/upower.nix`; do not take this brief's
word for it. Split:

- **`modules/desktop` declares `castle.power.criticalPowerAction`**,
  `nullOr` the same enum, default `null` meaning "leave upower's own
  default alone" — the declared-null convention `cursorTheme`
  established. The framework must not pick a value: a host with a real
  swap partition may legitimately want `Hibernate`, and hardcoding
  `PowerOff` in a shared module is exactly the hardware assumption
  `CLAUDE.md` forbids.
- **`hosts/xps9370` sets it with `lib.mkDefault`.** "This machine
  cannot hibernate" is a property of its disk layout, the same
  reasoning that puts `scale` there. `PowerOff` is the only action that
  reliably completes with no swap and needs no risky-action flag;
  `Suspend` at a critical percentage merely postpones an unclean death.
  State the choice in the host module's comment.
- **`modules/desktop` also carries an assertion**: error if the
  resolved action is in the hibernate family (`Hibernate`,
  `HybridSleep`) while `config.swapDevices == []`. Generic — it reads
  configuration, not hardware — and it is the layer this repo keeps
  wishing it had: a check that refuses a configuration nobody can run.
  nixpkgs' own assertion covers the risky actions but not this case.
- **Leave upower's thresholds alone** (`percentageLow` 20,
  `percentageCritical` 5, `percentageAction` 2). A threshold is a taste
  judgment about a specific battery, not a framework default. Say in
  the PR that this was a decision, not an oversight.

### 4. Idle: screen blank only — mechanism, with the policy slot empty

Declare `castle.display.idleBlankSeconds` in `modules/desktop`:
`nullOr ints.positive`, default `null`. `null` means no idle handling
at all — swayidle is not enabled, no unit runs, the screen never blanks
on its own. **That is the framework's shipped behaviour, deliberately.**
See the non-goal below before "improving" it.

Consume it in `modules/home` behind `swayEnabled` via home-manager's
`services.swayidle`: one `timeouts` entry whose `command` powers the
outputs off and whose `resumeCommand` powers them back on. Two traps:

- swayidle's generated user unit sets `Environment=PATH=` to bash
  alone, and commands run under `sh -c` — every command must be an
  absolute store path. A bare `swaymsg` fails silently at exactly the
  moment the screen was supposed to blank.
- Verify that `output * power off` / `power on` is the spelling the
  pinned Sway accepts; `dpms` is the older form. Read `sway(5)` at the
  pin rather than copying a blog.

Nothing here is chassis-specific, so all of it is `modules/`; the
number is private-layer. The greeter's own idle behaviour is out of
scope — a different session with a different owner.

### 5. Touchpad option surface

The resident currently sets `natural_scroll` and `tap` for
`type:touchpad` directly in their private layer as raw Sway config,
because no `castle.*` option exists. Provide the option so that
collapses into framework mechanism plus private preference — that
migration is what this item is *for*; say so in the PR.

Declare `castle.input.touchpad.naturalScroll` and
`castle.input.touchpad.tapToClick` in `modules/desktop`, and consume
them in `modules/home`'s Sway block — wired to
`wayland.windowManager.sway.config.input."type:touchpad"`, guarded by
`swayEnabled`, omitted entirely when null, exactly the shape
`castle.display.scale` uses on the `output` stanza.

Both `nullOr bool`. home-manager's `input` option is
`attrsOf (attrsOf str)`, so render the bool to Sway's
`enabled`/`disabled` words in `modules/home` — but take a bool at the
option surface, because a bool is what the setting *is*, and
`nullOr str` would invite a stranger to write `"true"` and get a config
Sway rejects at load.

**A new `castle.input` namespace, not more `castle.display`.** The repo
already namespaces by concern (`castle.admin`, `castle.person`,
`castle.display`, `castle.agent`, `castle.disk`): `castle.display` is
how the session looks, `castle.input` is how it is driven,
`castle.power` (item 3) is what happens when energy runs out,
`castle.hardware` (item 3) is what the chassis physically has. Folding
them together would make `castle.display` mean nothing in particular.
`idleBlankSeconds` stays under `castle.display` because it names what
happens — the screen goes dark — rather than why; `castle.power` is
defensible too, so state the choice.

**Judgment call, argued because it needs arguing: these are
null-by-default private preferences, not framework defaults.**
`castle.display.wallpaper` is the one option this repo defaults *on*,
for specific reasons — the alternative looks broken, and there is
exactly one canonical shipped asset. Neither holds here: a touchpad
with tap and natural scrolling off (Sway's own defaults) is not broken,
it is a different working preference people hold strongly in both
directions. Defaulting either on would be the framework making a taste
decision on a stranger's behalf — what Principle 01's split exists to
prevent; `cursorTheme`, defaulting `null`, is the closer precedent. The
counter-argument — most laptops ship tap on, match the crowd — was
considered and rejected: nothing is lost by defaulting null, since the
value the resident wants already exists in their private layer and this
is a move, not a re-decision. **And no host default either**: nothing
about "this chassis has a touchpad" implies a scroll direction; leave
`hosts/xps9370` out of this item entirely.

**Trap in `modules/home`:** `displayCfg` uses the
`config.castle.display or { … }` idiom with every key enumerated, so
the module stays importable on a headless host that never imports
`modules/desktop`. Each new namespace (`castle.input`, `castle.power`,
`castle.hardware`) needs its own fallback attrset listing *every* key
it declares, or a headless host fails at eval. No `nixosConfiguration`
in this flake currently imports `modules/home` without
`modules/desktop`, so that guard is asserted by comment rather than by
CI; adding one eval-only configuration that does is cheap and would
make the claim real — do it if it stays cheap, and say plainly in the
PR if you did not.

### 6. Promote the backlog entry

Delete `docs/backlog/laptop-ergonomics.md` in the commit that adds this
brief, and fix anything citing it by path (at spec time: nothing does).

Document the new slots (`castle.input`, `castle.power`,
`castle.hardware`, `idleBlankSeconds`, `criticalPowerAction`) in
`docs/private-layer.md`, in the same "what you actually write in
`resident.nix`" voice as the rest of that file — its own test is that a
stranger can write their private layer from it alone. **Add new
material only; do not rewrite the existing display-preference section
or its option counts** — task 0017 rewrites that section on another
in-flight branch, and touching the same lines here buys a conflict for
no gain. Its staleness is 0017's to fix; note the handoff in the PR.

## Verification

**Agent-testable:**

- `nix flake check`.
- `sway-config-check` (`.github/workflows/check.yml`) extended in the
  style of its existing steps, which already print the generated config
  and grep it. Assert: each new `bindsym XF86…` line is present; the
  sample of home-manager defaults the job already checks is *still*
  present (the `mkOptionDefault` merge is the thing most likely to
  break here, and it has broken before); an `input type:touchpad` block
  appears when the options are set and is absent when null; the
  generated i3status config exists, contains `battery`, and omits
  `ipv6` and (given `hasEthernet = false`) `ethernet`; and the swayidle
  user unit is generated when `idleBlankSeconds` is set and absent when
  null.
- To exercise the non-null side, extend the placeholder module in
  `nixosConfigurations.example` — it already simulates a private layer
  overriding `castle.display` — and extend its **existing** three-layer
  assertion rather than writing a second one beside it.
- Assert that the binaries named in the new bindings exist at the paths
  named. Cheap, and precisely the bug class 0014 item 5 exists for.
- Assert `hosts/xps9370`'s evaluated `boot.kernelParams` still contains
  `mem_sleep_default=deep` (item 2).
- The upower/no-swap assertion (item 3), **watched failing once**:
  point the action at `HybridSleep` on a swapless configuration,
  confirm `nix flake check` goes red with the message you wrote, then
  restore. 0014 established this habit for good reason.
- `test/desktop-loop/` (task 0011) can drive real keys in a real Sway
  session, but check what its `send_key` can actually emit before
  promising anything: it goes through QEMU's key-name table, not the X
  keysym list, and brightness keys may have no QEMU code at all. A VM
  also has no backlight and no battery, so a brightness keypress cannot
  be *proved* to do anything there. If volume keys are sendable,
  asserting a press changes `wpctl`'s reported sink volume is worth
  having. If not, say so and stop — do not add a step that presses a
  key and asserts nothing.

**Human hands** (unavoidable, in this order):

1. The suspend/resume ladder in item 2. The genuinely risky part, and
   it cannot be simulated: the VM has no firmware, and firmware is the
   entire question.
2. Brightness keys visibly change the panel, at a usable granularity.
   (Not testable over SSH — brightnessctl's logind path needs an active
   session on the seat.)
3. Volume and mute keys, with audio actually playing.
4. The status bar on the real machine: battery reading present and
   correct against `/sys/class/power_supply/BAT*/capacity`, and no red
   ethernet/ipv6 faults.
5. Touchpad tap and natural scroll behave exactly as before the
   migration — the point of item 5 is that nothing changes for the
   resident except where the setting is written.

Draining the machine to a critical percentage to watch the low-battery
action fire is deliberately **not** on that list: an hour of waiting
for one bit of information, when the assertion plus reading the
generated `UPower.conf` is the honest substitute. Say that in the PR
rather than implying it was observed.

## Non-goals

### No idle policy, and no screen lock — on purpose

Item 4 ships the mechanism with the policy slot empty: an option that
*can* blank the screen, defaulting to never doing it, and no lock at
all. This is not an oversight and not a half-finished feature, and it
must not be "finished" by a later reader adding a sensible-looking
300-second default or a swaylock binding because laptops usually have
one. The pieces are already sitting on the machine — swaylock and
swayidle ship with `programs.sway`, and swaylock's PAM service is
registered — so leaving them unwired is a decision, not an omission.

`docs/vision.md` puts the screen under attention management, not
desktop configuration. Deep-focus mode arranges the workspace and
suppresses communication surfaces; the intervention ladder runs from
ambient cue through nudge to forced context switch; the document says
outright that the agent will eventually have opinions about what is on
screen and when. An idle timeout is a decision about when the
resident's attention is presumed gone; a lock is a decision that
re-entry costs something. Both are inputs to that ladder. Any number
written now would have to be renegotiated the moment the agent has a
view — and a default that has sat in the config for months acquires the
authority of a decision it never earned.

A plainer reason to be careful with a lock specifically:
`modules/desktop` ships no auto-login precisely because a lost machine
with an unencrypted disk has only the login prompt between it and its
contents (see that module's header). A lock screen sits next to that
reasoning and belongs with the disk-encryption decision
(`docs/backlog/disk-encryption.md`), not bolted onto an ergonomics
task.

A future reader who wants idle policy should set
`castle.display.idleBlankSeconds` in their private layer — that is what
it is for — and file the framework-level question as its own brief.

### Everything else deliberately left out

- **Media transport keys** (play/pause/next/previous). They need
  `playerctl` and an MPRIS-speaking client — a different dependency and
  a different question from "make the volume rocker work".
- **Audio device switching / an output picker.** Named in the backlog
  entry and left: a UI question, not a keybinding, and PipeWire already
  routes to a sensible default.
- **Touchpad gestures.** Also from the backlog entry: they need a
  gesture daemon or Sway's `bindgesture` *and* a workspace layout worth
  being opinionated about, which this config deliberately does not have
  yet.
- **Any further touchpad tuning** — pointer acceleration, scroll
  method, click method, disable-while-typing. Two options, matching the
  two settings that exist in a real private layer today; a third gets
  added when a second resident needs one, not speculatively.
- **Bar contents beyond the false-fault fix** — colors, fonts,
  reordering, richer status programs. See item 3.
- **Power-management tuning**: TLP settings, charge thresholds, CPU
  governors, `power-profiles-daemon`. nixos-hardware turns TLP on and
  configures nothing; leave it that way. Battery-longevity charge
  thresholds are a good idea and a separate brief.
- **Changing `HandlePowerKey`.** Record what it is; do not change it.
- **Anything on the greeter session**, and **external displays,
  docking, or output hotplug.**

## Implementation notes (corrections discovered while building it)

**Item 2's establish step, which was itself the deliverable.** Nothing
in this repo sets any `services.logind.settings`, so upstream defaults
apply. Queried from the running reference host over the logind bus
rather than read out of a config file:

```
HandleLidSwitch               "suspend"
HandleLidSwitchExternalPower  ""
HandlePowerKey                "poweroff"
```

Closing the lid suspends, and the power button powers off — which is
what was wanted. **So no `services.logind.settings` is added**, per the
item's own instruction that a declaration merely restating upstream is
config noise implying a decision nobody made. The empty
`HandleLidSwitchExternalPower` is systemd's "follow `HandleLidSwitch`"
sentinel, so the machine also suspends on lid close while on AC; noted
rather than changed, since nobody asked for the on-AC case to differ.

**Two options moved to `modules/base`, and the second move was forced
by a failure rather than a review.** `castle.hardware.hasEthernet` was
specced for `modules/desktop`; it went to `modules/base` instead,
because a namespace named for a *fact* must be stateable by a host that
has no graphical session (`0003` finding #10 reasons about recovery in
exactly those terms). `castle.power.criticalPowerAction` then had to
follow it for a blunter reason: with the option declared in
`modules/desktop`, `hosts/vm-test` could not set it at all — the module
that declares it is one that host does not import — and the error said
so. Whether a machine can complete a hibernate is a disk-layout fact, so
`modules/base` is where it belongs; `modules/desktop` still owns the
wiring to `services.upower` and the assertion.

**The upower assertion found two real misconfigurations inside this
repo the moment it existed**, which is the best evidence it is worth
having: `hosts/vm-test` and the `test/desktop-loop` node both import a
desktop, both have no swap, and both would therefore have inherited
upower's `HybridSleep` default and been unable to complete it. Both now
declare `PowerOff`.

**But the assertion is broader than the problem, and this is recorded
as a known sharp edge rather than fixed.** It fires on *any* swapless
host importing `modules/desktop`, including VMs that have no battery
and will never reach a critical-battery event. That is why two of its
three current consumers are test machines declaring a value that is
inert for them. A narrower predicate — assert only where a battery
exists — would need a fact nothing in the module system knows at
evaluation time, so the honest options are the present over-broad check
or none. Left as-is deliberately; if the ceremony spreads to more test
nodes, revisit.

**Verification actually performed**, beyond `nix flake check` passing:

- Generated Sway config carries six `XF86` bindings, each pointing at
  an absolute store path (`brightnessctl`, and `wpctl` from the
  *configured* wireplumber package, not a bare `pkgs.wireplumber`).
- Generated `i3status/config` on the reference host: `ipv6` gone,
  `ethernet _first_` gone, `battery all` still present.
- The ethernet conditional was proved in **both** directions, not just
  the one that matters here: flipping `hosts/xps9370`'s
  `hasEthernet` to `true` brings `ethernet _first_` back, confirming
  the framework maps a hardware fact to presentation rather than
  hard-coding a chassis assumption.

**Not verified, and outstanding.** Nothing here has been deployed. The
media keys have not been pressed on real hardware, so the brightnessctl
permission path (item 1 predicts the logind one) is still a prediction;
the lid has not been closed and no resume has been observed, which is
item 2's whole point and the risk `docs/tasks/0003-findings.md` warns
about on this chassis; and `services.swayidle` has never run, because
`idleBlankSeconds` is null everywhere by design and no private layer
has set it yet.

### Post-review additions

Review found the shipped branch had no agent-testable guard layer at
all beyond the upower assertion, while this brief's Verification
section confidently described one. That is the failure this repo's
update-the-brief rule exists to prevent, and the honest fix was to
build the guards rather than to quietly narrow the plan:

- `check.yml` gains an ergonomics step asserting, against the **real
  generated artifacts**, that all six `XF86` bindings are present, that
  the volume ceiling (`-l 1.0`) survives, that home-manager's default
  bindings are still there alongside them (the finding-1 lockout guard
  restated for this task's additions), and that the generated i3status
  config keeps `battery all` while `ipv6` and `ethernet _first_` stay
  gone.
- Both directions were watched failing before being trusted: flipping
  `hasEthernet` to `true` brings the ethernet entry back and the check
  goes red; deleting the `XF86AudioMicMute` binding makes that
  assertion go red. Neither is visible to `sway --validate` or to
  `nix flake check`, which is the whole reason the step exists.
- `docs/private-layer.md` gains a "Laptop ergonomics" section covering
  the five new resident-facing options. `idleBlankSeconds` in
  particular had a policy story that pointed residents at an option no
  document mentioned.

**Still not built, and deliberately not:** the `mem_sleep_default=deep`
kernelParams regression assertion this brief's verification plan asks
for. It guards against a nixos-hardware bump silently changing suspend
depth — a real risk the brief names — but nothing in this branch sets
that parameter, so there is no current value to pin and an assertion
would encode an expectation about an upstream module rather than about
this repo's own configuration. Left for whoever first observes suspend
behaviour on real hardware, which is also the person who will know what
the right value is.

**One duplicate removed.** `pkgs.brightnessctl` had been added to
`environment.systemPackages` with a comment claiming it was there "so
the command also exists for a human at a shell". Verified false:
nixpkgs' Sway module already puts brightnessctl in
`programs.sway.extraPackages`, which lands in the same list — it
evaluated to two copies. This brief's own "establish what arrives free"
section said to confirm that before adding anything, and that step was
skipped.

**One latent sharp edge, recorded not fixed.** The swayidle commands
interpolate `config.programs.sway.package`, which nixpkgs declares
`nullOr`. Setting it `null` is the documented arrangement for a
home-manager-managed Sway; a private layer doing that *and* setting
`idleBlankSeconds` would get a Nix evaluation error rather than a clean
message. Unreachable in-repo today, since `modules/desktop` leaves the
default in place.
