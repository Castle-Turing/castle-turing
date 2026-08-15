# Task 0005 — The dogfooding desktop

**Before starting:** read `CLAUDE.md`, `docs/vision.md`,
`docs/principles/01-open-by-construction.md`, and the install history in
`docs/tasks/0003-findings.md`. Work on the `dogfooding-desktop` branch;
this brief rides it. PR to `main`.

**Goal.** The XPS can host its own development — this project's
conversations, edits, and commits could all happen on the machine
itself. Milestone 1's acceptance is a human sitting down at it and
doing real work.

## Verification plan

**Agent-testable, no human:** the config evaluates and builds
(`nix flake check`); the VM harness from task 0004 extended to assert
that the graphical target is reached and Sway's IPC socket appears on
boot. A GUI cannot be driven headlessly, but "the compositor started
and is controllable over IPC" can be.

**Needs a human:** the actual sit-down pass — does it feel usable,
does Claude Code work, does Emacs behave. The resident does this after
deployment.

## Scope

1. **home-manager** as a flake input, wired as a NixOS module. Public
   mechanism lives in `modules/home/`; the private repo supplies the
   person. Note carefully: git `user.name` / `user.email` are personal
   data and MUST come from the private layer, never this repo
   (Principle 01, and CLAUDE.md's hard rule).
2. **`modules/desktop/`** — Sway, with IPC explicitly enabled and
   documented as the agent's control surface (it is mechanism the
   agent layer will depend on, not decoration). Plus: a terminal
   emulator (foot), fonts, XDG desktop portals, PipeWire audio, and
   `greetd` + `tuigreet` for login. **No auto-login** — the disk is
   unencrypted, so a login prompt is the only thing between a stolen
   laptop and its contents.
3. **`modules/dev/`** — Emacs, git, gh, ripgrep, fd, and `claude-code`.
   Verify `claude-code` exists in the pinned nixpkgs; if it does not,
   document the correct install path in the module's comments rather
   than improvising a wrapper.
4. **Firefox.**
5. **First-boot password fix** — the private layer supplies
   `initialHashedPassword` (a hash, never a plaintext password, and
   never in this repo). Closes finding #1 in `0003-findings.md`: no
   future install should hit the console-lockout chicken-and-egg.
6. **Deploy to the XPS** via `nixos-rebuild switch --target-host` —
   no USB, no installer boot. This is also a live re-test of the
   change/rollback loop proven in task 0003.
7. Update the private repo as needed for the new option surface;
   report before committing anything there.

## Acceptance

- `nix flake check` green; harness assertions (graphical target, Sway
  IPC socket) pass in CI.
- Deployed to the XPS and it boots to a login prompt, Sway starts,
  a terminal opens, Emacs and Firefox run.
- The resident can run Claude Code (after authenticating themselves),
  clone both repos, and make a real commit from the machine.
- No personal data in this repo; the private layer holds the person.
- `/code-review` run before the PR, scoped against `origin/main`.

## Non-goals

Laptop ergonomics — brightness/volume keys, suspend/resume, audio
tuning, trackpad gestures — deliberately deferred; some arrives free
via nixos-hardware, and whatever does not becomes its own small task.
Mail, the agent layer, secrets tooling (sops-nix). Credentials are the
resident's to install by hand (`gh auth login`, Claude Code login); the
agent must not handle, request, or store them.

## Coordination

Other branches are live. **This task owns
`hosts/xps9370/default.nix`** — task 0006 has been told not to touch
it. Do not touch `test/vm-install/*` beyond adding the two new
assertions, and do not touch the installer image work.

PRs #8 (task 0003 close-out), #10, and #11 may merge while you work.
Rebase onto updated `origin/main` before opening your PR, and scope
every diff and review against `origin/main` per CLAUDE.md.
