# Task 0012 — The installer console must have an escape hatch

**Before starting:** read `CLAUDE.md`, `modules/installer.nix`,
`docs/tasks/0006-installer-image.md` (which built this console), and
`docs/backlog/installer-needs-an-escape-hatch.md` — the entry this
brief promotes and deletes. Work on branch `installer-escape-hatch`;
this brief rides it. PR to `main`.

**Goal.** An operator at the installer console can always reach a real
shell, and can see how from the console itself.

## Why

Demonstrated, not theorised. On the first from-scratch boot of the
custom image, `nmtui` rendered correctly and ignored every keypress.
The status script is the login shell of the installer's only auto-login
account, and the stock NixOS installer profile auto-logs-in on *every*
getty — so switching VTs just ran the same broken script again. The
operator could see a perfectly drawn menu and could do nothing at all,
including diagnose it.

A recovery tool whose failure mode is "no recovery" inverts its own
purpose. The `timeout --foreground` fix that unblocked that specific
bug is incidental: any future failure in this script reproduces the
trap.

Note the harness cannot catch this class — it asserts the installer is
SSH-reachable with *zero* console interaction, so a console that
renders and accepts no input passes every assertion. Whatever is built
here needs its own check.

## Scope

1. **Guarantee a shell.** Decide between running the status display on
   tty1 only and leaving other VTs as plain login shells, or keeping it
   everywhere with an explicit documented key that drops to a shell —
   or both. Argue the choice in the module's comments; the backlog
   entry lists these as open questions and either is defensible.
2. **Make the exit discoverable *on the console*.** The escape routes
   that existed — a `systemd.unit=rescue.target` kernel argument, or
   plugging in Ethernet — were undiscoverable from the screen the
   operator was looking at. Whatever the way out is, print it there.
3. **Survive a crash.** If the status script dies, the operator should
   land in a shell rather than a respawn loop.
4. **A check that would have caught this.** The existing harness cannot.
   At minimum, assert the generated configuration leaves a reachable
   shell — e.g. that not every getty is captured by the status script.
   Read the generated artifact, not just the exit status; this project
   has been bitten twice by checks that passed on configurations nobody
   could use.
5. **Promote the backlog entry** — delete
   `docs/backlog/installer-needs-an-escape-hatch.md` in the commit that
   adds this brief, and fix anything citing it by path.

## Verification

Agent-testable: `nix flake check`, the existing vm-install harness
staying green, and the new configuration assertion from (4).

Human hands: none required. A real from-scratch USB boot would prove
more, but the installer image is not being rebuilt tonight and the
config-level assertion is the honest substitute — say so in the PR
rather than implying hardware verification happened.

## Non-goals

- The installed system's recovery story — that is
  `docs/backlog/headless-recovery.md`, the same shape one layer up.
- Rebuilding or booting the real ISO.
- Wi-Fi provisioning, declarative or otherwise.
- Any change to `test/vm-install/`'s existing assertions. Add, do not
  alter — another agent is working in `test/` tonight.

## A question worth raising, not answering here

The backlog entry asks whether there is a general rule: that any Castle
Turing component taking over a console must state, on that console, how
to leave it. That may be principle-shaped. Note it in the PR for the
resident; do not adopt it unilaterally.
