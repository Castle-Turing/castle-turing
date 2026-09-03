# 0019 — Two defaults the managed Sway config got wrong

**Before starting:** read `CLAUDE.md`, `modules/home/default.nix` in
full (especially the long comment on `keybindings` — this task rewrites
part of it and must not break the rest), `.github/workflows/check.yml`'s
`sway-config-check` job, and `test/desktop-loop/test.nix`. Background,
not to be edited: `docs/tasks/0009-ambient-intake.md` (which introduced
both defects) and `docs/tasks/0011-desktop-loop-harness.md`. Work on
branch `sway-defaults`; this brief rides it. PR to `main`.

## Why

The managed Sway config from 0009 has been deployed and lived in. Two
defaults in it are wrong, and both are the same shape: a value chosen
by reading home-manager's option list rather than by watching the
generated config, then never observed. Neither produces an error. Both
were found by a resident at a keyboard, not by CI.

They are batched into one task because they are one file, one CI job,
and one class of mistake — an unobserved default in the same option
block.

### Defect 1 — every Castle Turing desktop starts on workspace 10

Sway makes the **first workspace mentioned in the config** the initial
workspace. home-manager emits the `keybindings` attribute set sorted by
key name, so `bindsym Mod1+0 workspace number 10` is written to the file
before `bindsym Mod1+1 workspace number 1`, and workspace 10 wins. A
fresh session therefore opens on the last workspace, and `$mod+1` looks
like it moves *backwards*.

Evidence (gathered by the resident; not re-run while writing this
brief). A nested Sway started against the generated config —
`env -u SWAYSOCK sway -c ~/.config/sway/config` — came up on workspace
10. Prepending a single `workspace number 1` line to a copy of the same
file made the same Sway come up on workspace 1.

The framework bug is an omission: `modules/home` has never set
home-manager's `wayland.windowManager.sway.config.defaultWorkspace`. The
option exists for exactly this and defaults to `null`.

**How that option actually works — verified against the pinned source**,
home-manager rev `c8058ecc1329a71a3c99c4d0353dba4009a66152` (`flake.lock`),
read at its unpacked store path while writing this brief:

- `modules/services/window-managers/i3-sway/lib/options.nix` (~line 1014)
  declares `defaultWorkspace` as `types.nullOr types.str`, default
  `null`, described as "The default workspace to show when sway is
  launched. This must to correspond to the value of the keybinding of
  the default workspace." *(sic)* Its example is `"workspace number 9"`.
- `.../lib/functions.nix` (~line 18) splits the bindings in two:
  `keybindingDefaultWorkspace = filterAttrs (_n: v: defaultWorkspace != null && v == defaultWorkspace) keybindings`,
  and `keybindingsRest` is the exact complement.
- `.../sway.nix` (~line 470) emits `keybindingDefaultWorkspace`'s
  `bindsym` lines **before** `keybindingsRest`'s.

So the option emits no `workspace` command of its own. It works purely
by reordering: the binding whose *value* string-equals `defaultWorkspace`
is hoisted to the top of the bindsym block, so it becomes the first
workspace mention in the file.

Two consequences that decide the rest of this brief:

- **(a) The value must be exactly `"workspace number 1"`.** The match is
  string equality against the binding's action, so any other spelling
  (`"workspace 1"`, `"workspace number 1 "`) filters nothing, hoists
  nothing, and changes nothing — silently. A wrong value here is
  indistinguishable from not setting the option at all.
- **(b) The fix is modifier-agnostic.** Because the match is on value,
  not on key, it keeps working unchanged if a resident's private layer
  sets `modifier = "Mod4"` — the hoisted binding is then `Mod4+1`, and
  the option never had to know.

Consequence (a) is also why the existing CI guard cannot catch a
regression here. `sway-config-check` already asserts that
`bindsym Mod1+1 workspace number 1` is *present*; it is present today,
with the bug. Any new assertion must be **order-sensitive**.

### Defect 2 — the modal chord silently displaces a stock binding under Mod4

`modules/home` hardcodes the ambient-intake chord to `Mod4+Shift+space`.
home-manager's stock set includes `"${modifier}+Shift+space" = "floating toggle"`.
With the default modifier (`Mod1`) those are different keys and nothing
collides. A resident who sets `modifier = "Mod4"` — the Super/Windows
key, which residents will want — collides, and loses `floating toggle`.

Measured evidence (gathered by the resident; cited as given): 54
bindings emitted with `Mod1`, including `Mod1+Shift+space floating toggle`;
53 with `Mod4`, with `floating toggle` simply absent. No error, no
warning, no diagnostic of any kind.

**Why it is silent — verified.** This is *not* the collision shape the
existing comment in `modules/home/default.nix` describes, and getting
that distinction right is most of the work in scope item 3.

Reproduced with the flake's own nixpkgs lib (`lib.evalModules`, an
option of type `attrsOf (nullOr str)` shaped exactly like home-manager's:
option `default = mapAttrs (_: mkOptionDefault) {...}`, module definition
`mkOptionDefault { <colliding key> = "..."; }`). The module's value wins,
silently, with no conflict error. Mechanism, read out of nixpkgs
`lib/modules.nix` at this flake's pin:

- `evalOptionValue` (~line 1107) splices an option's `default` into its
  definition list wrapped in `mkOptionDefault` — priority 1500
  (`defaultOverridePriority = 100`, `mkOptionDefault = mkOverride 1500`,
  ~lines 1569–1571).
- `mergeDefinitions` runs `filterOverrides'` once over the **whole**
  option value (~line 1206). Both definitions sit at 1500, so both
  survive, and both have their outer wrapper stripped.
- `attrsOf` then merges **per key**, which runs `filterOverrides'` again
  at the element level. Here the two sides are no longer symmetric:
  home-manager's per-value `mkOptionDefault` puts *its* value at 1500,
  while this module's inner value is a bare string at 100. The lower
  number wins outright and the other is dropped — no error, because
  dropping a lower-priority definition is `filterOverrides'` doing its
  ordinary job.

So the actual collision is **cross-level** — a definition-level wrapper
on one side against a per-value wrapper on the other — and it resolves
silently in this module's favour. The parenthetical in the existing
comment ("Two same-priority definitions of the *same* key would still
throw the ambiguous-priority error") describes a **different** shape.
That shape is real and also verified: two *peer module* definitions of
the same key, whether both bare or both wrapped in a definition-level
`mkOptionDefault`, do throw a conflicting-definition error. It is just
not what happens when a module collides with home-manager's own default.

**The chosen chord: `Mod4+Shift+Return`.** Decided; do not relitigate.
Verified sound against the pinned source (`sway.nix` lines ~80–148, the
full stock keybinding set): **no stock binding uses `Shift+Return` under
any modifier value**, so `Mod4+Shift+Return` collides with nothing
whether `modifier` is `Mod1`, `Mod4`, or anything else. Note that
`${modifier}+Return` (launch terminal) *does* exist — `Shift` is exactly
what keeps the new chord clear of it.

## What to change

### 1. `modules/home/default.nix` — set the default workspace

Inside the existing `wayland.windowManager.sway.config` block:

```nix
defaultWorkspace = lib.mkDefault "workspace number 1";
```

`lib.mkDefault`, not a bare definition, for the same reason
`modules/desktop` supplies the wallpaper that way (0014): this is a
framework default a private layer should be able to override at normal
priority without reaching for `mkForce`. The string must be exactly
`"workspace number 1"` — see consequence (a) above — and the comment
next to it must say why, or the next person will "tidy" it to
`"workspace 1"` and silently reinstate the bug.

**Do not** harmonise this with the `keybindings` definition below it.
`keybindings` must keep `lib.mkOptionDefault` (1500); demoting it to
`mkDefault` (1000) would drop home-manager's entire default set at the
definition-level filter and reproduce the 0009 finding-1 lockout. The
two use different override levels on purpose.

### 2. `modules/home/default.nix` — move the chord

`"Mod4+Shift+space"` → `"Mod4+Shift+Return"`. The `lib.mkOptionDefault`
wrap on the `keybindings` definition stays exactly as it is; moving the
chord changes which key is defined, not the priority mechanics, and none
of 0009 finding 1's protection is in scope here.

### 3. `modules/home/default.nix` — rewrite the comment's opening, correct its parenthetical

The current opening paragraph says the chord "deliberately overrides
Sway/i3's stock 'toggle floating on the focused window' default on
mod+shift+space — a real trade, made once, on purpose", and that
`swaymsg floating toggle` still reaches the action by hand. **That
reasoning is false in both directions** and must not survive this PR:

- Under the default modifier it was never a trade at all —
  `Mod4+Shift+space` and `Mod1+Shift+space` are different keys, and
  `floating toggle` was never displaced.
- Under `modifier = "Mod4"` it *was* a displacement, but nobody chose
  it: it happened silently, in a configuration the author was not
  looking at.

Replace it with the actual reason for the new chord: `Shift+Return`
appears nowhere in home-manager's stock set under any modifier value
(cite `sway.nix` and the pinned rev), so the chord displaces nothing
whatever a resident sets `modifier` to, and the fixed `Mod4` prefix is a
deliberate choice recorded under "considered and rejected" below.

The `mkOptionDefault` mechanism paragraphs **stay** — they are correct
and were hard-won. Two edits only:

- Correct the parenthetical about the ambiguous-priority error, per the
  verified mechanism above: same-key collisions between *peer module
  definitions* throw; a same-key collision with **home-manager's own
  default** does not — it is cross-level and resolves silently in this
  module's favour. Say plainly that this second shape is what defect 2
  was, so the next reader does not conclude the module system would have
  told them.
- The sentence "since this chord shares no key with any Mod1-prefixed
  default" is now the *weaker* half of the claim. The chord shares no
  key with any default under **any** modifier.

This comment has been wrong once already (0009 review, finding 1) and
was corrected against source. A second wrong iteration would be worse
than none: assert only what the implementer has re-read at the pinned
paths named in this brief.

### 4. `.github/workflows/check.yml` — the keybinding assertions

In `sway-config-check`'s "Assert the generated Sway config still carries
the default keybindings" step:

**(a)** Update the expected entry `bindsym Mod4+Shift+space exec foot --app-id=castle-modal`
to `bindsym Mod4+Shift+Return exec foot --app-id=castle-modal`.

**(b)** Add `bindsym Mod1+Shift+space floating toggle` to the sample.
It is not the binding that broke — under `Mod1` it never did — but it
makes the displaced-binding *class* visible in CI at all, which it
currently is not, and it costs one line.

**(c)** Add an **order-sensitive** assertion for defect 1. Presence
cannot catch a `defaultWorkspace` no-op; the hoisted line is present
either way. Assert instead that the first workspace-switch binding in
the file is the workspace-1 one — something equivalent to:

```sh
FIRST_WS=$(grep -nE '^bindsym [^ ]+ workspace number [0-9]+$' "$SWAY_CONFIG" | head -n1)
case "$FIRST_WS" in
  *"workspace number 1") ;;
  *) echo "First workspace binding in the generated config is: $FIRST_WS"
     echo "Expected the 'workspace number 1' binding first. Sway takes the first"
     echo "workspace mentioned in the config as the initial workspace, and"
     echo "home-manager only hoists it when defaultWorkspace string-equals the"
     echo "binding's action exactly (modules/home/default.nix). A silent no-op"
     echo "there looks exactly like this."
     exit 1 ;;
esac
```

Written against the action, not the key, so it stays modifier-agnostic
like the fix itself. Two things the implementer must confirm rather than
assume: that the generated lines really begin `bindsym ` with no
`--to-code` argument (they should — `bindkeysToCode` is false here — and
the job already `cat`s the config, so read it), and that
`"workspace number 1"` as a suffix pattern cannot match the
`workspace number 10` line (it cannot; `10` ends in `0`).

**What CI still will not see, stated honestly:** `sway-config-check`
renders exactly one configuration, `nixosConfigurations.example`, whose
modifier is the `Mod1` default. Every assertion above is a `Mod1`
assertion. Scope item 5 closes that gap at eval time; nothing in this
task renders and parses a `Mod4` config with the real Sway binary, and
that residual is accepted.

### 5. `flake.nix` — one eval-only configuration with `modifier = "Mod4"`

Defect 2 only exists under a modifier this repo never evaluates. The
cheap fix is a second configuration that changes exactly that one thing
and asserts the two invariants:

```nix
# The Mod4 case defect 2 (docs/tasks/0019) was invisible in: a
# resident who switches the modifier to the Super key. Eval-only —
# nothing builds this system — but `nix flake check` forces its
# assertions, which is all that is needed to prove the modal chord
# displaces no stock binding under a modifier this repo does not
# otherwise exercise.
nixosConfigurations.example-mod4 = self.nixosConfigurations.example.extendModules {
  modules = [ ({ config, ... }: { /* set modifier, assert */ }) ];
};
```

The two assertions, read off
`config.home-manager.users.resident.wayland.windowManager.sway.config.keybindings`
after setting `...sway.config.modifier = "Mod4"`:

- `keybindings."Mod4+Shift+Return"` is the modal exec — the chord
  survives the modifier change;
- `keybindings."Mod4+Shift+space" == "floating toggle"` — the stock
  binding survives. **This is the defect-2 regression test**, and it is
  red on today's code.

Keep the message in the repo's house style: say what regressed and point
at this brief. Confirm `extendModules` is available on this nixpkgs pin
(it is a standard `nixosSystem` output attribute) — if for any reason it
is not, write the configuration out longhand rather than dropping the
check.

### 6. `test/desktop-loop/test.nix` — the chord, and a real initial-workspace assertion

This harness boots the real stack and presses the real key, and
`.github/workflows/desktop-loop-test.yml`'s path filter includes
`modules/**`, so it runs on this PR. Two changes:

- `machine.send_key("meta_l-shift-spc")` → `machine.send_key("meta_l-shift-ret")`.
  **This is required for the harness to keep passing**, and it is also
  the strongest automated evidence available that the new chord actually
  opens the modal in a live compositor.
- Add an initial-workspace assertion right after the existing
  `get_version` check, before any key is pressed: the `swaymsg` helper
  returns parsed JSON, so `swaymsg("get_workspaces")` gives the list, and
  the entry with `focused` true must be named `"1"`. This turns defect 1
  into something a VM proves rather than something a human has to notice.
  It is red on today's code (it would report `"10"`).
- The file header comment says "press the real `$mod+Shift+space`
  keybinding" — update it, and the same phrase in
  `desktop-loop-test.yml`'s header.

### 7. Documentation touch-ups

- `agent/README.md` (~line 152) names `Mod4+Shift+space` concretely —
  update to `Mod4+Shift+Return`.
- `docs/architecture.md` (~line 110) says `$mod+Shift+space` — update,
  and note it is a fixed `Mod4` chord rather than a `$mod`-relative one,
  since that is now a deliberate property (see rejected options).
- Leave `docs/tasks/0009` and `docs/tasks/0011` **unedited**. Briefs ride
  their branch and record what was decided at the time; this brief
  supersedes them, the same way 0016 superseded 0012 without rewriting
  it.
- `docs/private-layer.md` gains a short note under the Sway/display
  material: a private layer overriding `wayland.windowManager.sway.config.keybindings`
  must wrap its definition in `lib.mkOptionDefault`, exactly as
  `modules/home` does, or it will silently discard both home-manager's
  default set and the framework's modal binding. That is the same
  finding-1 lockout, reachable from the private side, and nothing in the
  repo currently warns about it.

## Considered and rejected

**Prepending a raw `workspace number 1` via `extraConfig`.** Rejected
twice over. `defaultWorkspace` is the purpose-built option and produces
the same effect through the mechanism upstream maintains. And
`extraConfig` would not work anyway: `sway.nix` appends `cfg.extraConfig`
as the **last** element of the generated file (verified — it is the final
`++ [ cfg.extraConfig ]` after modes, bars, window commands and startup),
so a `workspace` line placed there is mentioned after all ten workspace
bindings and hoists nothing. There *is* an `extraConfigEarly` emitted
first, which would positionally work — rejected on the same first
ground: raw config text where a typed option exists is exactly the kind
of thing this repo ends up re-deriving later.

**Keeping `Mod4+Shift+space` and only renaming it under `Mod4`.** A
conditional chord — one key under one modifier, another under a
different one — makes the documentation, the muscle memory, and the
desktop-loop harness all conditional on a setting most residents will
never look at. The collision is avoidable outright; avoid it outright.

**Binding the modal to `"${modifier}+Shift+Return"` instead of a fixed
`Mod4` chord.** Genuinely arguable, and the stronger argument on
principle: it would follow the resident's own modifier, so the modal
would sit under the same key as everything else in their muscle memory.
The human decided a fixed `Mod4+Shift+Return`. The reasoning that makes
it sound: the modal is not a window-management command, it is the door
into the agent layer, and giving it one stable chord that every doc,
README, and test can name literally is worth more here than
modifier-following — especially while `agent/README.md`,
`docs/architecture.md` and the desktop-loop harness all spell the chord
out. `Shift+Return` being unbound under *every* modifier is what makes
the fixed choice safe rather than lucky. Revisit if a resident ever
reports the fixed `Mod4` prefix fighting their layout.

**A Nix-level assertion in `modules/home` that the modal chord does not
collide with the stock set under the configured modifier.** The honest
version of this needs the stock key set to compare against, and the only
way to get it is to restate home-manager's ~50 defaults in this repo —
a copy that silently rots against the pin, which is the same failure
class as the bug. Scope item 5 gets most of the value at a fraction of
the cost: it does not prove "no collision with anything", it proves the
one binding that actually collided is still there, under the one
modifier that actually collides.

**Making the modal chord a `castle.*` option.** Not needed. A private
layer can already rebind it through
`wayland.windowManager.sway.config.keybindings` (with the
`lib.mkOptionDefault` caveat scope item 7 documents), which is the
mechanism home-manager already provides. Adding a framework option
would be a second way to do the same thing.

**Rebuilding `sway-config-check` to render both modifiers.** The job
builds real store paths and runs the real Sway binary; doubling it
doubles a slow job to catch one class of bug that an eval-time assertion
already catches. Rejected as scope creep; the residual is recorded in
scope item 4.

## Verification

**Automated, no human involved:**

1. `nix flake check` — must stay green, and now also forces the
   `example-mod4` assertions (scope item 5).
2. `sway-config-check` — `sway --validate` over the regenerated config,
   plus the amended keybinding sample and the new order-sensitive check
   (scope item 4).
3. `desktop-loop-test` — the real VM presses `Mod4+Shift+Return` and the
   modal opens; the session's focused workspace is `1` before any key is
   pressed (scope item 6).

**Prove each new assertion by breaking the code, not the test.** This
repo's standing rule (0014, 0016), and it applies to all three of the
new checks:

- Remove the `defaultWorkspace` line → the order-sensitive CI check and
  the desktop-loop workspace assertion must both go red. Restore.
- Set `defaultWorkspace = "workspace 1"` (a plausible wrong spelling) →
  the order-sensitive check must go red, since this is the silent-no-op
  case it exists for. Restore.
- Revert the chord to `Mod4+Shift+space` → `example-mod4`'s
  `floating toggle` assertion must go red. Restore.

Record all three observed failures in the implementing session's
decision log. An assertion never watched failing is not evidence.

**Human hands (~3 minutes, after deploy):**

- Log in. The session opens on workspace 1.
- Press `Mod4+Shift+Return`. The modal opens.
- Press `Mod4+Shift+space`. Under the default modifier: nothing happens,
  which is correct — it is now an unbound chord. Under a private layer
  that sets `modifier = "Mod4"`: the focused window floats and unfloats,
  which is the stock behaviour defect 2 was eating.

The nested-Sway trick that found defect 1 —
`env -u SWAYSOCK sway -c <config>` — remains the fastest way to check
config-ordering behaviour by hand without logging out, and is worth
keeping in mind even though scope item 6 now covers this specific case
in CI.

## Principle 01 and the hard rules

Pure public mechanism. Both changes are framework *defaults* — an
initial workspace and a chord — and both stay overridable from a private
layer: `defaultWorkspace` via `mkDefault`, the chord via
`keybindings` (wrapped in `mkOptionDefault`, per scope item 7). Neither
encodes anything about any particular resident, and the modifier-agnostic
form of both fixes is what keeps a resident's own `modifier` choice a
private-layer decision rather than a framework assumption.

No personal data: the evidence cited here is binding counts, workspace
numbers, and store paths. No hardware assumptions: nothing added to
`modules/` refers to a machine, a panel, or a keyboard layout — the
chord is a keysym combination Sway resolves, not a hardware fact.

## Non-goals

- Any further desktop configuration. 0009 said "a foothold, not a ricing
  project", and that still holds — this task fixes two wrong defaults and
  adds nothing.
- Media keys, brightness, lid/suspend behaviour. That is
  `docs/backlog/laptop-ergonomics.md` and stays there; this brief does
  **not** promote it.
- Making the modal chord or the modifier into `castle.*` options.
- Rewriting 0009's or 0011's briefs.
- Any change to `test/vm-install/`, `hosts/vm-test`, or the installer.

## Implementation prompt (for a separate, cold session)

> Implement `docs/tasks/0019-sway-initial-workspace-and-modal-chord.md`
> in the Castle Turing framework repo, on branch `sway-defaults`. Read
> `CLAUDE.md` first; it is binding. Read the brief in full before
> editing anything — it contains verified source-level claims you should
> re-check rather than trust, and it names the exact paths to check them
> at.
>
> The work is two one-line fixes in `modules/home/default.nix` plus the
> guards that make them stick: set `defaultWorkspace`, move the modal
> chord to `Mod4+Shift+Return`, rewrite the false opening paragraph of
> the long `keybindings` comment and correct its parenthetical about
> the ambiguous-priority error, amend `sway-config-check`'s assertions
> (including a new order-sensitive one), add an eval-only
> `nixosConfigurations.example-mod4`, update `test/desktop-loop/test.nix`
> for the new chord and add an initial-workspace assertion, and fix the
> chord's name where docs state it literally.
>
> Before asserting anything about home-manager's behaviour in a comment
> or a commit message, re-read the pinned source yourself:
> home-manager rev `c8058ecc1329a71a3c99c4d0353dba4009a66152` per
> `flake.lock`, files
> `modules/services/window-managers/i3-sway/{sway.nix,lib/options.nix,lib/functions.nix}`,
> and nixpkgs `lib/modules.nix` for `filterOverrides'` /
> `mkOptionDefault` / `defaultOverridePriority`. That comment has been
> wrong once before; a confidently wrong second version is worse than
> none.
>
> The `lib.mkOptionDefault` wrapper on the `keybindings` definition is
> load-bearing (0009 finding 1) — do not change its priority while
> changing the key it defines.
>
> Verification is not optional and not just "CI is green": break each of
> the three new assertions by reverting the code it guards, watch it go
> red, restore, and record all three in your decision log. Then run
> `/code-review` scoped against `origin/main`, address the findings, run
> `tools/codex-review.sh`, and post its output verbatim before opening
> the PR. `git fetch` first and confirm scope with
> `git diff origin/main...HEAD --stat`.
>
> If the design shifts while you build it, update this brief in the same
> PR.
