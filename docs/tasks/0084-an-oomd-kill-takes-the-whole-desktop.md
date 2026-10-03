Title: Wrap desktop app launches in per-app transient scopes
Model: deep
Milestone: none — hygiene
Model-because: the diff is small but the terrain is documented-treacherous
and every failure is silent — home-manager's sway keybinding priority
dance (modules/home/default.nix's own comments around mkOptionDefault),
scope-versus-service environment inheritance, and a GUI VM test. A
standard-tier implementer following this spec literally would most
likely produce a desktop that works while the wrapping silently does
not — the exact silent revert the detector exists to catch — and this
task needs an implementer with the judgment to argue with the spec if
the pinned systemd or home-manager behaves differently than stated.

# An oomd kill takes the whole desktop, because every app shares one cgroup

**What.** On the xps9370, every GUI application runs in a single
cgroup. greetd's login lands sway in logind's session scope
(`/user.slice/user-1000.slice/session-N.scope`, verified 2026-09-16),
and everything launched from sway — wmenu picks, `exec` bindings,
terminals, and every process they spawn — inherits it by fork. The
systemd user manager (`user@1000.service`) manages only explicit user
units; castle's timers live there, but no app launch on this host is
wrapped into one. Firefox, qutebrowser, foot, and the Claude sessions
inside foot are one undifferentiated leaf cgroup as far as the
kernel's accounting and systemd-oomd's kill selection are concerned.

**Why it matters.** systemd-oomd kills leaf cgroups. Task 0073 wires
its swap rule so a runaway allocation finally gets killed instead of
livelocking the machine (the 2026-09-15 crash: Firefox loading Gmail,
per the resident's testimony — the journal never named it). But with
one leaf holding the whole desktop, the eligible victim *is* the whole
desktop: sway, terminals, and any in-flight agent work die alongside
the browser that misbehaved. A clean SIGKILL and a login prompt beat a
power button, which is why 0073 is right to land anyway — but the
kill-target risk task 0063 accepted ("the expectation is that the
runaway session's cgroup, not the compositor's, is what dies") turns
out to be optimistic in the concrete: there is no separate cgroup for
the expectation to be about. This is the same genus as the oomd
finding itself — an upstream default (minimal compositors do not wrap
app launches; GNOME and KDE do, via per-app `app-*.scope` units under
the user manager) that was never chosen, recorded, or tested against
this failure mode.

On 2026-10-02 the blast radius stopped being a prediction: oomd's first
live kill on this host took `session-N.scope` whole — 634 processes,
the compositor, two running Claude sessions and their in-flight work.
The storm was driven by one session's per-command flake evaluation loop
(`a-dev-shell-entry-costs-a-nixpkgs-eval-per-command.md`); the second
session was a casualty, contributing only ordinary load. Note what the
trigger was not: a browser. It was an agent in a terminal, which bears
directly on the wrapping-reach decision below — launcher-only wrapping
would not have contained it.

**How it would have been caught sooner.** The memory-exhaustion drill
already proposed in `the-kernel-oom-killer-has-no-swap-headroom.md` is
the honest detector: it measures which cgroup actually dies when a
rule fires, and on today's layout it would report "all of them". A
cheaper static probe — assert that a GUI app's cgroup differs from the
compositor's — only becomes a regression check *after* per-app scopes
exist; this brief lands it with the fix (see Verification plan) so the
layout cannot silently revert. The full drill stays with the
swap-headroom entry.

## Spec

The resident approved implementing this entry (2026-10-02, in session).
The former "fix directions, none chosen" are now chosen as follows; the
original open questions are each resolved or explicitly deferred at the
end.

**1. Mechanism: a launch wrapper around `systemd-run --user --scope`.**
A small wrapper (working name `castle-launch`; the implementer may
rename) that executes

    systemd-run --user --scope --collect --quiet -- "$@"

A *scope*, not a service: a scope's command runs as a child of the
caller, inheriting the full Wayland/session environment, while its
cgroup is registered under the user manager — so the app becomes its
own oomd-eligible leaf and the compositor keeps the environment
plumbing it already has. Verified live on the xps9370 (2026-10-02):
`systemd-run --user --scope --collect -- sleep 3` from a session-scope
shell produced a `run-*.scope` under `user.slice` while the invoking
shell stayed in `session-N.scope`. Two behaviors the implementer must
not "fix": the `systemd-run --scope` process stays in the foreground as
the command's parent (that is how scopes work — do not background it
with `&` inside the wrapper), and `--collect` is required so failed
launches do not leave dead scopes behind. Reference `systemd-run` by
absolute store path (`${pkgs.systemd}/bin/systemd-run`), not a bare
name — the same "no option pointing at nothing" rule the media-key
bindings in `modules/home` already follow. Scope naming: the default
`run-*` names are already unique per launch, which is all correctness
needs; an app-identifying name (the `app-<app>-<random>.scope` shape
GNOME and KDE use, which would make a future oomd kill message name its
victim) is nice-to-have only — do not spend complexity on it.

**Alternative considered and rejected: uwsm.** The universal Wayland
session manager implements exactly this XDG `app-*.scope` convention and
would be the "proper" answer. Rejected for this brief because uwsm takes
over session startup wholesale, and this repo's sway session is launched
by greetd+tuigreet (`modules/desktop`), not by a session manager —
adopting uwsm is a larger, riskier change than the failure justifies. If
a future need (real `app-*.scope` naming, XDG autostart integration)
earns it, that is its own backlog entry, not a dependency of this fix.

**Alternative considered and rejected: app2unit.** Post-merge review
surfaced that the pinned nixpkgs packages `app2unit` (v1.4.4, from
uwsm's author) — a standalone launcher that puts commands into XDG
`app-*.scope`/`.service` units without uwsm's session takeover, sitting
exactly between rejected-uwsm and a hand-rolled wrapper. Rejected
anyway, for scope-of-mechanism reasons rather than taste: app2unit is
Desktop-Entry-oriented (it resolves and launches `.desktop` entries,
with terminal handling via `xdg-terminal-exec`), while every call site
this brief wraps launches a raw command line; adopting it would add a
dependency and a desktop-entry indirection to get, today, the same
`systemd-run` call the three-flag wrapper makes directly. It is the
natural candidate if the future `app-*.scope`-naming entry (above) is
ever opened — record it there when that happens.

**2. Reach: terminals included, not launcher picks only.** The
2026-10-02 trigger was an agent session inside a terminal, not a
launcher pick, and launcher-only wrapping would not have contained it.
A terminal in its own scope also contains the agent sessions it hosts —
which both protects them from an unrelated app's kill and makes a
runaway agent session individually killable, the bound
`an-agent-workload-can-thrash-the-host.md` wants. So the wrapper applies
to every app-launch path the modules define:

- sway's `terminal` setting (home-manager
  `wayland.windowManager.sway.config.terminal`, today `foot`);
- sway's `menu`/launcher setting. With the pinned home-manager and no
  `config.menu` override in `modules/home`, the live launcher is
  home-manager's default `dmenu_path | dmenu | xargs swaymsg exec --`
  pipeline, not a wmenu one (wmenu is installed by `modules/desktop`
  but nothing selects it); verify against the pinned source;
- the castle-modal chord at
  `keybindings."Mod4+Shift+Return"` in `modules/home` (~line 320).

Prefer setting the `terminal`/`menu` options *through* the wrapper over
re-declaring the generated config, and check the pinned home-manager
source for their defaults the way `modules/home`'s own comments already
practice.

**Two hazards the implementer must clear, both already documented in
`modules/home`:**

- *The keybindings priority minefield.* The module's long comment block
  (~lines 286–333) explains that a second, unwrapped
  `keybindings = {…}` definition sits at normal priority and silently
  discards home-manager's entire default binding set (the 0009/0019
  lockouts). The castle-modal binding already lives inside the existing
  `lib.mkOptionDefault` attrset — keep the wrapped form in that same
  attrset; do not add a second definition. For home-manager-owned
  launches (the `terminal` default), override the option rather than
  re-declaring the binding, so the default set is not disturbed.
- *The menu's stdin.* The launcher (`dmenu` today, `wmenu` if ever
  selected) reads candidate items on stdin and writes the pick to
  stdout; it runs in a shell pipeline (`… | dmenu | …`), not as a
  standalone app. Do not wrap the menu *filter* as a scope — that
  would break the pipe. Wrap the *program the pick launches*, not the
  filter. If the launcher is a single command that both picks and execs,
  wrap only the exec half; if in doubt, leave the filter unscoped and
  scope the launched app, and record in the PR which you did and why.

**3. sway itself stays in the session scope.** The compositor must
survive a kill so the resident is left looking at a desktop (or at worst
a swaynag/login prompt) rather than a black screen — something has to
render what happened. Only app launches move to their own scopes; sway,
its bar, and its own helper processes stay where greetd puts them.

## Plan

All edits are public mechanism; no host-specific value appears
(Principle 01). The host-specific question "does this host run sway" is
already gated by `swayEnabled`/`programs.sway.enable`, so the wrapper
rides that same gate and no `hosts/<name>/` change is needed. Because
the mechanism holds for any sway host, it lives in `modules/home`
alongside the existing sway config, not in `hosts/xps9370`.

1. Define the `castle-launch` wrapper once (a `pkgs.writeShellScript` or
   `home.packages` shim) so the flag set lives in one place, with the
   class interface a follow-up extends: usage
   `castle-launch <class> -- <cmd…>`, and an option set with one entry
   per class (`terminal`, `menu`, `modal`), each carrying
   `extraProperties` (list of str, default `[]`) rendered as
   `--property=<p>` flags. No bounds are set here; a future
   `MemoryHigh=` is then a list entry, not a refactor.
2. Route the three app-launching paths (terminal, menu, castle-modal
   chord) through it, clearing the two hazards above.
3. Land the static VM regression probe (below) in the same PR.

## Verification plan

Automated, no human hands:

- **Static regression probe, as a VM test in the mold of
  `test/oomd-liveness/`**, landed as a `packages.x86_64-linux.*`
  output with its own path-filtered workflow in the mold of
  `.github/workflows/oomd-liveness-test.yml`. Post-merge review caught
  the earlier wording claiming `nix flake check` runs that shape — it
  deliberately does not (the flake's comments at `oomd-liveness-test`
  explain the fast-gate division), so without its workflow the probe
  would be a detector that never runs. Boot the real desktop stack in a NixOS VM (the
  `test/desktop-loop/` harness already logs in through the real
  greetd+tuigreet and presses real chords — extend or mirror it), launch
  an app through *each* wrapped path (the terminal, the menu's exec
  half and the castle-modal chord), and assert each one's cgroup path
  is a distinct `run-*.scope` under `user.slice` and **not** equal to
  the compositor's cgroup. The terminal path is mandatory: it is the
  incident's workload, and a probe that passes with only the modal
  chord wrapped detects nothing. This is the detector the incident ships: it turns
  "a GUI app's cgroup differs from the compositor's" from a hope into a
  check that fails if a future edit collapses the layout back.
- **`nix flake check`** stays green (module evaluation), and the
  `desktop-loop` acceptance test — built via its own workflow, `nix
  build .#desktop-loop-test -L` locally — still passes, i.e. the
  wrapped launches do not break the real chord that test asserts on.

Deliberately *not* in this brief: the full memory-exhaustion drill that
fires a real oomd rule and measures which cgroup dies. That is the
stronger, slower detector and it stays with
`the-kernel-oom-killer-has-no-swap-headroom.md`, where it is already
proposed. This brief's static probe is the cheap check that the topology
is right, which is all this brief changes.

## Open questions — resolved or deferred

- *Wrapping reach* — resolved: terminals included (Spec §2).
- *Does sway leave the session scope* — resolved: no (Spec §3).
- *Where the wrapper lives* — resolved: `modules/home`, gated by
  `swayEnabled`, for any sway host (Plan).
- *How an oomd kill becomes a notification the resident and agent layer
  see* — deliberately deferred and out of scope here. It remains with
  `the-kernel-oom-killer-has-no-swap-headroom.md`, which already carries
  it; per-app scopes make it more valuable (the kill message would
  finally name one app) but do not require it, and folding it in would
  widen this brief past the one property it is about.

## Implementation prompt

> Read this entire file, `modules/home/default.nix` (especially the
> `wayland.windowManager.sway` block and the keybindings priority
> comments around lines 286–333), `modules/desktop/default.nix`, and
> `test/oomd-liveness/test.nix` + `test/desktop-loop/test.nix` for the
> VM-test mold. Implement the Plan exactly: one `castle-launch` wrapper
> around `systemd-run --user --scope --collect --quiet --`, route the
> terminal, menu, and castle-modal launches through it without
> disturbing home-manager's default keybinding set or breaking the wmenu
> pipeline, and land the static VM regression probe in the same PR as a
> `packages.x86_64-linux.*` output with its own path-filtered workflow
> (the `oomd-liveness-test.yml` mold — not under `checks.*`). sway
> itself stays in the session scope. Everything is public mechanism —
> no host value belongs in these files. Verify with `nix flake check`
> (evaluation) plus `nix build .#<probe> -L` and
> `nix build .#desktop-loop-test -L`: the new probe passes and the
> desktop-loop test still does. Report any point where the keybinding
> wiring or the pinned systemd/home-manager behaviour forced a judgment
> call the spec did not cover — the priority behaviour in this module is
> subtle and the spec may have under-described your actual call site.
