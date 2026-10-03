Title: Expose the launch wrapper and assert the menu routes through it
Model: standard
Milestone: none — hygiene
Model-because: every design decision is made in this brief — the option
shape, the assertion's exact predicate and gate, which definition drops
to mkDefault and which deliberately does not — and the two assumptions
that could sink a smaller implementer (that the assertion can read the
merged home-manager value at all, and that it actually fires on an
unrouted override) are each guarded by a check this brief requires: the
negative eval check fails loudly if the assertion is wired to the wrong
attribute path or never fires. The terrain's documented treachery is
module *priorities*, and the one priority change here is the
option-value mkDefault pattern the same file already uses and annotates
(defaultWorkspace); deep would spend judgment where the checks supply
the verdict.

# A resident menu override silently drops launch scoping, because the wrapper has no public name

**What.** `modules/home` routes its default sway `menu` through the
`castle-launch` wrapper so menu picks land in their own transient
scope — but the wrapper is a module-internal `writeShellScript` with
no option exposing its path. A resident who overrides `menu` — a
legitimate private-layer choice the option exists for — first collides
with the framework's equal-priority definition, and after the natural fix
(`lib.mkForce`) their launches run unscoped in the session cgroup:
no per-launch oomd isolation, and the `castle.launch.menu` bounds
silently do not apply. Found 2026-10-03 while setting the private
layer's bounds — the collision was loud, but the post-mkForce scoping
loss is silent.

**Why it matters.** The menu class launches browsers — the application
class behind the 2026-09-15 session kill. A resident exercising a
documented customization point quietly loses exactly the protection
tasks 0084/0085 shipped, with nothing red anywhere: the app-scopes VM
test exercises the framework's own config, not a resident's override.

**How it would have been caught sooner.** The evaluation collision is
what caught the *conflict*; nothing catches the *loss*. The honest
check is host-side and ships with the fix: assert that whatever
command the final merged `menu` option execs routes through the
wrapper (a string check at eval time — cheap, and it turns a silent
downgrade into a build failure with a message naming the fix).

**What we already know.** The fix direction is small: expose the
wrapper — a read-only option (e.g. `castle.launch.wrapper`) or a
`home.packages` entry putting `castle-launch` on PATH. The PATH route
has a trap review caught before anyone fell in: the wrapper is built
with `pkgs.writeShellScript`, which produces one executable at the
derivation root, and package profiles only link executables from
`bin/` — so adding the existing derivation to `home.packages` exposes
no command, and a string assertion accepting a bare `castle-launch`
would pass while the menu fails at runtime with command-not-found.
That alternative means converting to `pkgs.writeShellScriptBin` (or an
equivalent derivation carrying `bin/castle-launch`). Either route adds
the eval-time assertion above, and one line in `docs/private-layer.md`
showing a custom pipeline ending in `swaymsg exec -- <wrapper> menu
--`. The framework's own `menu` definition may also warrant
`lib.mkDefault` so a resident override merges by priority rather than
colliding — but only once the assertion exists, since mkDefault alone
converts the loud collision into the silent loss.

**Open questions.** Option versus PATH exposure, and whether the
assertion belongs in the module or the VM test.

## Decisions, closing this entry's open questions

Both were put to the resident on 2026-10-03 and both answers are
recorded here so the implementer inherits decisions, not debates.

**Exposure: a read-only option, not PATH.** `castle.launch.wrapper`
exposes the wrapper's store path; the resident interpolates
`config.castle.launch.wrapper` into their override. This keeps the
launch independent of session PATH, needs no conversion of the
wrapper derivation, and gives the assertion a strong predicate: the
merged `menu` value must contain the very store path the option
exposes, not a bare name that could be anything. The PATH route
(`writeShellScriptBin` + `home.packages`) was considered and
rejected: it weakens the assertion to a name match and reintroduces
the resolution trap the review already caught.

**The assertion lives in the module, at eval time.** The VM test was
never the right home: it exercises the framework's own configuration,
which is exactly why it did not catch this. An assertion in
`modules/home` evaluates against the *resident's* merged
configuration on the resident's own `nixos-rebuild`, which is the
only place the loss can be seen. The VM test is not touched.

**The framework's `menu` drops to `lib.mkDefault`.** With the
assertion in place, an unrouted override fails the build with a
message naming the fix, which supersedes the collision error as the
guard. One failure mode (assertion message) replaces two (collision,
then silent loss after mkForce). `terminal` and the modal keybinding
deliberately do NOT demote: no assertion covers them yet, and
mkDefault without an assertion is precisely the silent-loss shape
this entry exists to close. If someone later wants those merged by
priority too, each needs its own assertion first.

## Spec

**1. The option.** In `options.castle.launch` (modules/home), add a
`wrapper` option alongside the mapAttrs-generated per-class sets —
merge it in with `//`, since `wrapper` is not a launch class and must
not acquire the per-class bounds options:

- `type = lib.types.path`, `readOnly = true`, `default = castleLaunch`,
  with a `defaultText` naming it as the module-internal wrapper.
- Description: the store path of `castle-launch`; what a resident
  interpolates into a custom `menu` (or any sway exec) so the launch
  still lands in its class's transient scope; usage is
  `<wrapper> <class> -- <command> [args...]`; point at
  docs/private-layer.md.

**2. The assertion.** In the module's existing `assertions` list
(config block), gated so headless imports are untouched:

- Gate: `!swayEnabled ||` — same `swayEnabled` the sway section's own
  `lib.mkIf` uses. Additionally gated on the opt-out option below.
- Predicate: `lib.hasInfix "${castleLaunch}"` over
  `config.home-manager.users.${adminCfg.username}.wayland.windowManager.sway.config.menu`
  — the merged value, which is the point: it sees the resident's
  override, not this module's definition.
- Message: states that the merged `menu` does not route through
  `castle-launch`, so menu picks would run unscoped in the session
  cgroup and the `castle.launch.menu` bounds would not apply; names
  the fix (end the pipeline in
  `swaymsg exec -- ''${config.castle.launch.wrapper} menu --`, see
  docs/private-layer.md) and the deliberate opt-out
  (`castle.launch.requireMenuScoping = false`).

**3. The opt-out.** `castle.launch.requireMenuScoping`
(`lib.types.bool`, default `true`), merged into `options.castle.launch`
beside `wrapper`. An assertion cannot be mkForce'd away, and a
framework written for strangers does not make scoping policy
unrefusable: a resident who genuinely wants an unscoped menu says so
in their own configuration, loudly, in one line. Judgment call made at
spec time, not in the backlog entry — flag it in review if it reads as
surface the project should not carry.

**4. The demotion.** The framework's `menu` definition gains
`lib.mkDefault`. The long comment above `terminal`/`menu` currently
argues that normal priority is deliberate and load-bearing; that
reasoning is superseded for `menu` only, and the comment must be
rewritten to carry the present tense: `menu` is mkDefault because the
scoping assertion guards the loss; `terminal` stays at normal priority
because nothing asserts its scoping yet, so the collision error
remains its only guard. Do not demote `terminal` or the modal
keybinding.

**5. The documentation.** docs/private-layer.md's launch-scoping
section ("Per-application memory bounds") gains a short subsection on
overriding the launcher: a resident replacing `menu` routes the final
exec through the wrapper, with one nix snippet whose pipeline ends in
`swaymsg exec -- ''${config.castle.launch.wrapper} menu --`, and one
sentence each on the assertion that catches an unrouted override and
the `requireMenuScoping = false` opt-out.

**6. The detector's detector.** A new eval-only flake check (the
`checks.x86_64-linux.password-reminder-states` shape is the precedent)
that extends `nixosConfigurations.example` with
`menu = lib.mkForce "fuzzel"` (any wrapper-free value) and asserts the
failed assertion is present in `config.assertions` with its message.
Without this, the assertion could be wired to a wrong attribute path —
or silently stop firing after a refactor — and every green build would
look like coverage. Also assert the positive case: the example config
evaluates with no failed castle.launch assertion. Eval only, no VM.

## Plan

1. Add `castle.launch.wrapper` (read-only) and
   `castle.launch.requireMenuScoping` to `options.castle.launch`.
2. Add the gated assertion to the module's `assertions` list.
3. Demote the `menu` definition to `lib.mkDefault`; rewrite the
   priority comment for the new split (menu mkDefault + assertion,
   terminal normal priority, and why).
4. Add the private-layer doc subsection.
5. Add the negative/positive eval check to the flake's `checks`.
6. `nix flake check`; run the outcome-row step; open the PR.

## Verification plan

All machine-verifiable, no human hands needed:

- `nix flake check` passes — this now includes the new eval check,
  which proves the assertion fires on an unrouted `mkForce` override
  and stays quiet on the framework's own config.
- `nix build .#nixosConfigurations.example.config.system.build.toplevel`
  (or the cheaper sway-config attribute CI already builds) still
  evaluates — proves the read-only option and the assertion introduce
  no evaluation regression.
- CI's existing sway-config-check and the app-scopes VM test are
  untouched and stay green — proves the framework's own menu still
  routes through the wrapper after the mkDefault demotion.

## Implementation prompt

Implement docs/tasks/<this task's number> in the castle-turing repo.
Read the brief in full first; it closes every open question, and the
Decisions section records the resident's own choices — do not reopen
them. Work on a branch, never on main. The files you touch:
`modules/home/default.nix` (option, assertion, mkDefault, comments),
`flake.nix` (the eval check), `docs/private-layer.md` (one
subsection). Keep the assertion's gate exactly as specced — headless
imports of modules/home must not evaluate home-manager sway config.
Verify with `nix flake check` and by reading the new check's failure
output once with the assertion deliberately broken (then restore it).
Report any judgment call where this brief was ambiguous.
