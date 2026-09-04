# Task 0007 — VM harness cleanups

**Before starting:** read `CLAUDE.md`, `docs/vision.md`, and
`docs/backlog/harness-cleanups.md` (the source of this brief — it is
deleted in the same commit this brief lands in). Work on the
`harness-cleanups` branch; this brief rides it. PR to `main`.

**Context.** Review passes over tasks 0004–0006 surfaced a cluster of
small quality fixes in `test/vm-install/` and its CI workflow, parked in
the backlog rather than folded into unrelated diffs. The harness is the
project's regression net for installs; friction here is paid on every
iteration of every future install-related task, and duplication in a
test is duplication in the thing that is supposed to catch drift.

**Goal.** Six mechanical cleanups with no behavioral change to any
assertion: collapse the repeated phase blocks, use `lib.fileContents`,
cache CI's nix store, parallelize the serial `nix build` calls, clean
the workdir on success, and poll the serial log instead of a flat sleep.

## Verification plan

No human hands required anywhere. The harness is its own test: run it
on any KVM-capable Linux box locally, and it runs in CI on this PR
(the workflow's `paths` already includes `test/vm-install/**`). Shell
syntax is checkable with `bash -n` (and `shellcheck` if available); the
`.nix` edits are parseable without a full build. Record this PR's CI
runtime alongside the previous run's to evidence the cache and parallel
wins (0006 set the precedent for measured runtime deltas).

## Scope

1. **Repeated phase blocks.** Phases 2, 3 and 4 in `run.sh` repeat the
   same start-QEMU / wait-for-SSH / fail-or-log shape, differing only
   in phase name, user, and failure message. Add an `assert_boots`
   helper taking those three (and passing through `start_qemu`'s extra
   args), and have phase 1 use it too with its longer task-referencing
   message. Keep the per-phase PASS logs distinct. `stop_qemu_hard`
   calls stay where they are (phases 3 and 4 stop the previous boot
   before asserting).
2. **Pubkey boilerplate.** `installer.nix` and `vm-test-system.nix`
   each inline `lib.removeSuffix "\n" (builtins.readFile pubkeyFile)` —
   exactly nixpkgs' own `lib.fileContents`. Replace both; two copies
   could diverge and silently authorize different keys in the installer
   and the target, which is precisely the drift the harness exists to
   catch.
3. **No Nix cache in CI.** The workflow re-substitutes QEMU, OVMF,
   nixos-anywhere and the full closure on every run. Add
   `DeterminateSystems/magic-nix-cache-action` (same vendor as the
   `nix-installer-action` already there) right after it — it backs the
   store with GitHub's Actions cache, invalidating fine-grained by
   store path rather than by `flake.lock` hash.
4. **Serial `nix build` calls.** Four separate tool builds
   (`build_pkg` × qemu/OVMF/nixos-anywhere/openssh) become one
   `linkFarm` expression exposing the same outputs as symlinks — the
   pattern 0006 already used to collapse TOPLEVEL/DISKO — which
   evaluates `pkgs.nix` once and builds the four in parallel. The
   installer ISO and target-artifact builds are independent: run them
   concurrently (backgrounded with output to files, then `wait`).
5. **Workdir never cleaned.** `cleanup()` kills QEMU but leaves the 8G
   qcow2 behind even on success. Track success; on success remove the
   disk image, OVMF vars copy, and generated keys — and the whole
   workdir when the log dir lives outside it (CI always sets
   `CASTLE_HARNESS_LOG_DIR` outside). On failure keep everything;
   `fail()`'s "state preserved at" lines must stay truthful.
6. **Polling granularity.** `wait_for_ssh` sleeps a flat 3s while the
   serial log is already being captured per phase. Poll the serial log
   (getty's `login:` prompt) at sub-second cadence with the SSH attempt
   as the true gate; give `wait_for_ssh` the phase's serial log path.
   Apply the same cadence to phase 2b's `graphical.target` loop. This
   is the marginal item — verify the serial signal against a real
   captured log before trusting it; if it proves unreliable, keep the
   flat sleep and say so in the PR.

## Non-goals

No change to what any assertion checks; no changes under `modules/` or
`hosts/`; no new harness features; no other parked findings (0006's
boot-fallback dedup note stays parked).

## Acceptance

- All six items landed; the diff is confined to `test/vm-install/*` and
  `.github/workflows/vm-install-test.yml`.
- Harness green in CI on this PR; PR notes the runtime delta vs the
  previous run.
- `nix flake check` still green; `/code-review` run before the PR,
  scoped against `origin/main`.
- This brief is committed on the branch with the work; the backlog file
  `docs/backlog/harness-cleanups.md` is deleted in the same commit.

## Coordination

Live branches with unmerged work: `backlog-adoption-gaps`,
`backlog-installer-escape-hatch`, `backlog-password-seed`,
`fix-installer-private-layer-doc`, `fix-nmtui-tty`. None touch
`test/vm-install/` or the workflow; territory is clear. `git fetch`
first and scope reviews against `origin/main` per CLAUDE.md.
