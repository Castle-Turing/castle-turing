# Task 0011 — Run the loop for real, in a VM

**Before starting:** read `CLAUDE.md`, `docs/architecture.md`, and the
briefs for the code you are exercising — `docs/tasks/0008`, `0009`,
`0010`. Then read `test/vm-install/` (the existing QEMU harness, shell-
driven) and `test/agent-loop/` (the scripted-tenant harness, no VM).
Work on branch `desktop-loop-harness`; this brief rides it. PR to `main`.

**Goal.** Boot the real desktop stack in a VM, press the keybinding,
type a complaint, and assert the record landed — the whole ambient
intake, driven end to end, with no human and no hardware.

## Why this, and why now

**Nothing in the agent layer has ever processed a real interaction.**
The modal has never been pressed. The router has never routed. No
correction has been filed, no digest read; the resident model is empty.
Every existing test is a fixture written to satisfy an assertion
written alongside it. `test/agent-loop/` proves the record plumbing in
isolation with no compositor; `test/vm-install/` proves a machine
installs, and deliberately imports no desktop and no agent module.

Between them sits the thing the project is actually for, and the only
way to exercise it today is to deploy to the resident's laptop — which
is why it has not happened. This task removes that as the only path.

It is also the honest test of everything built on top. If the loop is
awkward in a VM it will be awkward on hardware, and better to learn
that here than after another proposal is written about it.

## Verification plan

This task **is** the verification — there is no separate proof that it
worked. It passes when CI boots a VM, drives the keybinding, and
asserts on records the journal actually contains.

Human hands: none. That is the point.

## Scope

1. **A VM that boots the real stack.** A NixOS VM importing
   `nixosModules.base`, `home`, `desktop`, `dev`, and `agent` with a
   placeholder resident — the same composition `nixosConfigurations.example`
   already proves *evaluates*, now proven to *boot*. nixpkgs' own
   `nixos/tests/sway.nix` is the closest template; read it before
   inventing an approach. Prefer the `nixosTest` framework (a Python
   driver with `wait_for_unit`, `send_key`, `wait_for_window`,
   `screenshot`, OCR) over extending the shell-driven `test/vm-install/`
   harness — that one exists to exercise *installation*, which is a
   different job.
2. **Reach a graphical session.** `modules/desktop` runs greetd +
   tuigreet with no auto-login, so the test must log in as the
   placeholder resident using `castle.admin.initialHashedPassword`.
   Assert Sway is actually running — the compositor's own IPC socket
   (`swaymsg -t get_version`) is a better signal than a screenshot.
3. **Press the key.** Send `$mod+Shift+space`, wait for the modal
   window (`app_id=castle-modal` — assert via `swaymsg -t get_tree`
   rather than pixels), type a complaint, and terminate the input.
4. **Assert the loop.** A `request` record exists in the journal with
   the typed text verbatim; `castle route` writes a decision citing
   evidence; `castle digest` renders the errand. Then file a
   `correction` through the modal's other path and assert the record
   and its resident-model entry.
5. **Wire into CI** as its own workflow or job. It will be slow — treat
   `vm-install-test`'s existing path-filtering and caching as the
   precedent for keeping it affordable.

## Non-goals

- **Not the worker's real tenant.** `castle work` shells out to
  `claude -p`, which needs network and credentials a VM test must not
  have. Use the scripted-worker convention `test/agent-loop/` already
  established.
- **Not replacing `test/vm-install/`.** That harness proves installation
  and must stay green and untouched.
- **Not deployment.** Nothing here touches the reference host.
- **Not fixing what it finds.** If driving the loop exposes bugs in the
  modal, router, or Sway config — likely, since none has run — record
  them precisely and fix only what blocks the harness itself. Separate
  brief for the rest.
- Not screenshot/OCR assertions where a structured query exists. Sway's
  IPC and the journal's own files are the ground truth; pixels are a
  fallback, not a first resort.

## Acceptance

- CI boots the VM, reaches a Sway session, opens the modal by
  keybinding, and asserts a verbatim `request` record — cold, with no
  human.
- The correction path asserted the same way.
- `nix flake check` green; existing workflows unaffected.
- `/code-review` against `origin/main`, then `tools/codex-review.sh`
  for the cross-model pass, per `CLAUDE.md`.

## The honest failure mode

This may not work. Driving a Wayland compositor in a headless VM is
genuinely harder than the shell-driven install harness, greetd may
resist automation, and the whole thing may prove too slow for CI.

**A clean negative result is a successful outcome for this task.** If
it cannot be made to work, say so precisely — what was tried, where it
broke, whether a narrower version (Sway with no greetd, or the modal
driven without a compositor) would still be worth having. Do not fake a
pass, do not weaken an assertion until it goes green, and do not leave
a test that boots a VM and asserts nothing. A harness that always
passes is worse than no harness, and this project has already been
bitten once by a check that accepted a configuration nobody could use.
