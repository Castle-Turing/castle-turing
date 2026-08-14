# Task 0001 — Flake evaluation gate (local + CI)

**Before starting:** read `CLAUDE.md` and `docs/vision.md`. Work on a new
branch; open a PR to `main`; never commit to `main` directly. Commit this
brief as part of the branch.

**Context.** The `substrate/milestone-0` work added the first
`nixosConfiguration` (`xps9370`), but it has never been evaluated — the
authoring machine had no Nix. CLAUDE.md commits this repo to keeping the
flake evaluating; this task makes that enforced rather than aspirational.

**Goal.** `nix flake check` passes, `flake.lock` is committed, and CI runs
the check on every PR and push to `main`.

**Scope.**

1. Run `nix flake check`. If Nix is missing locally, stop and ask the user
   to install it — do not work around it.
2. Fix any evaluation errors in `flake.nix`, `modules/base/`,
   `hosts/xps9370/` with the smallest possible diff. No refactors, no new
   features.
3. Commit the generated `flake.lock` — the lockfile is a rollbackability
   artifact and belongs in the repo.
4. Add `.github/workflows/check.yml`: on `pull_request` and `push` to
   `main`, install Nix (DeterminateSystems/nix-installer-action) and run
   `nix flake check`.
5. Optional, only if trivial: add a `formatter` output
   (`nixfmt-rfc-style`) and run `nix fmt` once.

**Non-goals.** Secrets tooling, window manager, disk layout changes, new
principle docs, any change to what the host configuration *means*.

**Acceptance.**

- `nix eval .#nixosConfigurations.xps9370.config.system.build.toplevel.drvPath`
  succeeds — this is the definitive evaluation test (on macOS, evaluation
  without building is expected and sufficient).
- `nix flake check` exits 0 locally and the CI workflow is green on the PR.
- Diff is otherwise minimal.

**Hints.** If `nixos-hardware.nixosModules.dell-xps-13-9370` fails to
resolve, look up the exact attribute name in the nixos-hardware repo rather
than guessing.
