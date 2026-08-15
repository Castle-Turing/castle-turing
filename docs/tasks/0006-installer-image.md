# Task 0006 — The agentic installer image

**Before starting:** read `CLAUDE.md`, `docs/vision.md`,
`docs/principles/01-open-by-construction.md`, and
`docs/tasks/0003-findings.md` — particularly findings #1 (first-boot
lockout) and #3 (installer ephemerality), which this task exists to
delete. Work on the `installer-image` branch; this brief rides it.
PR to `main`.

**Goal.** Boot a Castle Turing installer and the machine is
immediately SSH-reachable — no console login, no manual Wi-Fi join,
no curling keys from GitHub. The install stops requiring a human at
the target's keyboard.

**Why now.** Task 0003 needed five separate USB boots, each demanding
the same manual ceremony, because the stock NixOS ISO has no
persistence and no knowledge of its operator. That ceremony is the
single largest obstacle to an agent installing this system unattended.

## Verification plan

Fully agent-testable, no human hands: the task 0004 harness boots the
custom ISO in place of the stock installer and asserts that SSH by key
comes up on the *installer* with zero console interaction, then that
the full install loop still passes its existing four assertions.

## Scope

1. **The image.** A flake output building a custom installer ISO:
   - the admin SSH public key baked in (public mechanism, private
     contents — the key comes from the private layer, exactly as
     `castle.admin` does today),
   - sshd enabled and running at boot,
   - network provisioning so the machine reaches the LAN without a
     console (Wi-Fi credentials are private-layer data and must never
     enter this repo; design the slot, document it, and let the
     private layer fill it — a wired-Ethernet-only fallback is
     acceptable if Wi-Fi provisioning proves unreasonable, but say so
     explicitly rather than silently narrowing the goal).
2. **Harness integration.** Point the 0004 harness at the custom
   image; add the "installer is SSH-reachable unattended" assertion.
   Keep total CI runtime reasonable.
3. **Parked cleanup — the double evaluation.** `test/vm-install/run.sh`
   builds `TOPLEVEL` and `DISKO_SCRIPT` via two separate
   `nix build --impure --expr` calls with identical import
   expressions, so the full `nixosSystem` evaluation (including a
   self-referential `getFlake`) runs twice per harness run. Collapse
   to one evaluation with both outputs read from it. This directly
   speeds up every iteration of this very task.
4. **Documentation.** Rewrite the install flow in
   `hosts/xps9370/README.md` around the new image, superseding the USB
   ceremony. Written for strangers, per CLAUDE.md.

## Acceptance

- The ISO builds from a flake output and boots to an SSH-reachable
  state with no console interaction.
- Harness green in CI, including the new installer-reachability
  assertion and the existing four.
- Double-evaluation removed; note the measured runtime difference.
- `nix flake check` green; `/code-review` run before the PR, scoped
  against `origin/main`.
- README's install flow reflects reality and does not reference the
  retired ceremony.

## Non-goals

Secure Boot, netboot/PXE, changing what the installed system contains,
and — explicitly — the boot-fallback config deduplication parked from
the earlier review. That finding touches `hosts/xps9370/default.nix`,
which task 0005 owns right now; leave it parked and note it stays
open.

## Coordination

Other branches are live. **Do not touch `hosts/xps9370/default.nix`
or anything under `modules/` that task 0005 is building** (home,
desktop, dev). Your territory is `test/vm-install/*`, the new image
output, `flake.nix`'s outputs, and the host README's install section.

PRs #8, #10, and #11 may merge while you work. Rebase onto updated
`origin/main` before opening your PR, and scope every diff and review
against `origin/main` per CLAUDE.md.

## Precondition for the reinstall pass (record in the PR)

Before any from-scratch reinstall of the XPS, everything on that
machine must be committed and pushed — a wipe destroys uncommitted
work. State this in the README's install section as a checklist item,
not just in conversation.
