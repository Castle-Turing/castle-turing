# Task 0004 — Automated install-loop test harness (QEMU + CI)

**Before starting:** read `CLAUDE.md`, `docs/vision.md`,
`docs/principles/01-open-by-construction.md`, and — for the failure
history this harness exists to prevent — `docs/tasks/0003-findings.md`
on the unmerged `first-install` branch (`git show
origin/first-install:docs/tasks/0003-findings.md`). Work on the
`install-test-harness` branch; this brief and the pending CLAUDE.md
edit ride it. PR to `main`.

**Context.** Task 0003's physical shakedown surfaced mechanism bugs —
missing fallback bootloader, first-boot console lockout, unprovisioned
network — that each cost a human USB round-trip to discover. The
install mechanism is public and hardware-independent (Principle 01);
it must be testable unattended. Hardware residue (Wi-Fi firmware,
chassis quirks) stays out of scope: one physical shakedown per host is
the design; zero is not achievable.

**Goal.** A GitHub Actions job (KVM-enabled runner) that exercises the
full install loop against a QEMU/OVMF VM and goes red when the
mechanism regresses.

**Verification plan** (per the Spec workflow): everything in scope is
agent-testable — the harness is its own test, runnable in CI and on
any KVM-capable Linux box. No human hands required anywhere in this
task. (The harness deliberately cannot verify hardware-specific
residue; that stays a per-host physical step by design.)

## Scope

1. A `hosts/vm-test/` host module: virtio disk, the same
   `modules/base`, throwaway per-run admin SSH key. Parameterize
   disko's device path so host modules declare their own disk
   (`/dev/vda` here, `/dev/nvme0n1` on the XPS) — mechanism in
   `modules/`, device fact in `hosts/`.
2. The harness: boot the installer in QEMU and run the real install
   path. Evaluate `nixos-anywhere --vm-test` first — it ships VM test
   tooling; use it if it can express the assertions below, custom
   QEMU/OVMF scripting only if it can't. Assertions:
   - install completes and the VM boots from its own disk with the
     installer detached;
   - SSH comes up as the admin, by key, **with zero console
     interaction** (regression test for the first-boot lockout);
   - survives a power-cycle (hard stop + restart);
   - survives **NVRAM wipe** — delete the OVMF vars file and boot
     again, forcing the firmware down the ESP fallback path
     (`EFI/BOOT/BOOTX64.EFI`). This encodes the dead-CMOS lesson
     permanently.
3. CI wiring: a workflow triggered by PRs touching `flake.nix`,
   `flake.lock`, `modules/`, `hosts/`, or the harness/workflow files.
   Target runtime under ~20 minutes.
4. Prove the harness catches real breakage: intentionally break the
   fallback-loader step in a scratch commit, confirm the job goes red,
   revert, confirm green. Document the red run's link in the PR.
5. Docs: a section explaining how an agent (or stranger) runs the
   harness locally on a KVM-capable Linux box and how to read its
   failures.

## Non-goals

Wi-Fi/firmware emulation, the agentic installer image (task 0005 —
built against this harness next), install performance tuning, changes
to what `hosts/xps9370` deploys (the `first-install` branch owns that;
avoid touching files it changes, to keep the merge trivial).

## Acceptance

- Harness green in CI on the PR; demonstrated red on intentional
  breakage (with link); local-run runbook present.
- `nix flake check` green; `/code-review` run before the PR.
- No file conflicts with the `first-install` branch.
