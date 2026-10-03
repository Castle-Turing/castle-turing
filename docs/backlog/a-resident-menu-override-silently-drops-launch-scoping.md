# A resident menu override silently drops launch scoping, because the wrapper has no public name

**What.** `modules/home` routes its default sway `menu` through the
`castle-launch` wrapper so menu picks land in their own transient
scope — but the wrapper is a module-internal `writeShellScript` with
no option exposing its path. A resident who overrides `menu` (a
legitimate private-layer choice; the xps9370 pins a Wayland-native
picker to its panel for recorded reasons) first collides with the
framework's equal-priority definition, and after the natural fix
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
`home.packages` entry putting `castle-launch` on PATH — plus the
eval-time assertion above, and one line in `docs/private-layer.md`
showing a custom pipeline ending in `swaymsg exec -- <wrapper> menu
--`. The framework's own `menu` definition may also warrant
`lib.mkDefault` so a resident override merges by priority rather than
colliding — but only once the assertion exists, since mkDefault alone
converts the loud collision into the silent loss.

**Open questions.** Option versus PATH exposure, and whether the
assertion belongs in the module or the VM test.
