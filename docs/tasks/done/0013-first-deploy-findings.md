# Task 0013 — Two bugs the first real deploy found

**Before starting:** read `CLAUDE.md`, `docs/tasks/0009-ambient-intake.md`
and `0010-correction-record.md` (the code this fixes), `modules/home`,
`hosts/xps9370/default.nix`, `modules/agent/default.nix`, and
`test/desktop-loop/test.nix`. Work on branch `first-deploy-findings`;
this brief rides it. PR to `main`.

**Context.** On 2026-08-17 the ambient intake ran on the reference host
for the first time. The keybinding fired, the modal took the resident's
words, and a `request` record landed verbatim — the loop works on
hardware. It also surfaced two bugs, one cosmetic and one that defeats
a design commitment.

## Bug 1 — the cursor size is double-scale-compensated

`hosts/xps9370` sets `castle.display.cursorSize = 48` alongside
`scale = 2.0`. Sway already multiplies cursor size by the output scale,
so `xcursor_theme <theme> 48` on a scale-2.0 output renders at roughly
96 physical pixels. On this 3840×2160 13" panel that is about 7mm of
cursor — reported on the real hardware as dramatically, unusably
oversized, consistent with the double-scaling math above.

The existing comment justifies 48 on the grounds that XWayland and some
GTK paths do not follow Sway's output scale for the pointer glyph. That
concern is real *for those clients* and wrong as a reason to inflate the
value Sway itself consumes — the compensation is applied twice.

**Fix.** Set `cursorSize` to **18**, calibrated by eye on this panel at
scale 2.0 (36 physical pixels, ~2.8mm). Rewrite the comment to say what
is actually true: Sway scales the cursor, so this value is pre-scale;
the XWayland gap is a separate problem this option does not solve, and
pretending otherwise is what produced the bug.

Note for whoever writes that comment: 18 is *below* the 24 default and
still larger than what the resident originally complained about, because
the panel previously ran unscaled. Say so, or the next reader will
"correct" it back.

## Bug 2 — `castle.agent.stateDir` does not reach the modal

`modules/agent` wires `castle.agent.stateDir` into `CASTLE_STATE_DIR`
via `environment.variables`, which lands in `/etc/set-environment` and
is sourced by **login shells**. Sway is launched by greetd → tuigreet,
which does not source it. So `castle-modal`, spawned from the Sway
keybinding, never sees the variable and falls back to
`$XDG_STATE_HOME/castle`.

Confirmed on the host: the variable is correctly set in
`/etc/set-environment`, and the first real record was nonetheless
written to `~/.local/state/castle/journal/`.

**Why this matters more than it looks.** The whole reason runtime state
lives in the private repo (`docs/architecture.md`, "Where runtime state
lives") is durability — the accumulated model and journal are the least
reproducible artifacts on the machine and must survive a reinstall and
move to the next one. Silently writing them to a machine-local fallback
defeats that, and defeats it *invisibly*: everything appears to work.

**Fix.** Make the variable reach processes launched from the compositor.
`environment.sessionVariables` and a systemd user-environment import are
both plausible; determine which actually works for a greetd-launched
Sway session rather than assuming, and say in a comment why the chosen
one is correct. Do not simply document the fallback as intended
behaviour — the resident's journal is meant to be versioned.

## Bug 2b — the harness cannot catch this, and must

`test/desktop-loop/test.nix` never sets `castle.agent.stateDir`, so the
configured path and the fallback are identical inside the VM and the
test passes either way. **A harness that cannot fail on this bug is not
evidence about it.**

Set a non-default `stateDir` in the test's machine config and assert the
record lands *there*, not at the fallback. Verify by pointing the
assertion at the fallback path and confirming the test goes red.

## Verification

Agent-testable: `nix flake check`, the extended `desktop-loop` VM test
(both the new stateDir assertion and the existing loop assertions), and
`sway-config-check` showing the corrected `xcursor_theme` line in the
generated config.

Human hands: the resident confirms the cursor looks right after a
re-login. That perceptual check is the only part no harness can make,
and 18 is already their answer — this is confirmation, not discovery.

## Non-goals

- The XWayland/GTK cursor-scale gap. Real, separate, needs its own
  investigation; do not widen this task into it.
- Any other `castle.display` value. `scale = 2.0` is confirmed correct
  for this panel (3840×2160, verified over IPC).
- Changing where state lives by default, or the fallback's existence —
  the fallback is correct behaviour when no `stateDir` is configured.
