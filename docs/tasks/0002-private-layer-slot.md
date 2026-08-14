# Task 0002 — The private-layer slot

**Before starting:** read `CLAUDE.md`, `docs/vision.md`, and
`docs/principles/01-open-by-construction.md`. This task touches both repos
and rewrites two unmerged branches — read the whole brief before acting.
Commit this brief and the pending CLAUDE.md edit on your branch.

**Context.** `hosts/xps9370/default.nix` commits a real username and SSH
public key — Principle 01 consequence 1 ("nothing personal is ever
committed — including in history") is violated in history at `eca975d` and
its descendants on the two unmerged branches (`substrate/milestone-0` /
PR #1, `flake-eval-gate` / PR #4). The private layer that should hold
these values doesn't exist yet. This task creates it and remediates
history while remediation is still cheap.

**Goal.** The public repo contains no person: it exports modules and a
dummy-valued example configuration that CI checks. A new private repo owns
the real `nixosConfiguration` for xps9370. The interface between them is
documented for strangers. History on both unmerged branches is clean.

## Plan, in order (order matters)

1. **Capture the real values first.** Record the current `castle.admin`
   username and SSH key from the working tree before any rewriting. They
   must end up in the private repo, nowhere else.
2. **Create the private repo:**
   `gh repo create whharris/castle-turing-private --private`. Scaffold: a
   `flake.nix` with `castle-turing` as an input
   (`github:whharris/castle-turing`), defining
   `nixosConfigurations.xps9370` that imports the public repo's modules
   and supplies the real `castle.admin` values; a short README stating
   what belongs here (personal config; encrypted secrets later via
   sops-nix — **no plaintext credentials, ever, pending that tooling**).
   The private flake.lock pins the public repo's rev — that pin is an
   audit artifact.
3. **Scrub the public branches.** Rewrite `substrate/milestone-0` and
   `flake-eval-gate` so that no commit contains the real username or key
   (replace with the example values from step 4 at every point in history
   where they appear; preserve everything else, including PR #4's merge
   topology or an equivalent linear rebase). Force-push both. Verify:
   `git log -p --all | grep` for the key material and username finds
   nothing. Note honestly in the PR: GitHub-side remnants (old PR diff
   views, cached commits) can persist server-side; with a public key and
   a first name this residue is accepted — the scrub's purpose is that no
   *clone* of the repo carries it.
4. **Refactor the public flake** on a new branch based on post-scrub
   `flake-eval-gate`: export `nixosModules.base` and
   `nixosModules.host-xps9370` (the host module keeps hardware facts,
   loses person facts); replace `nixosConfigurations.xps9370` with
   `nixosConfigurations.example` using obviously-fake values
   (`username = "resident"`, a key string clearly labeled as a
   placeholder) so `nix flake check` still evaluates the whole stack;
   update `hosts/xps9370/README.md` — the rebuild command now points at
   the private flake.
5. **Document the interface** in `docs/private-layer.md`: what a
   stranger's private repo must define, file by file, to make the system
   theirs — including the slots that exist but are still empty
   (stated-priorities, authority taxonomy, secrets).
6. **Draft Principle 02** at
   `docs/principles/02-the-resident-owns-the-configuration.md` (adopted
   only when the human merges): the private layer is not data *consumed
   by* the public system — it is the top of the stack. The private repo
   instantiates the castle; the public repo cannot name any resident.
7. `nix flake check` green locally and in CI on the PR. `/code-review`
   before opening the PR, per convention.

## Non-goals

sops-nix wiring (no credential exists yet; the docs reserve its slot),
mail/WM/agent features, any change to what the host *does*, merging
anything — the human merges PR #1, #4, and this one, in that order.

## Acceptance

- `git log -p --all` in the public repo contains no real username/key on
  any branch.
- Public repo: `nix flake check` passes; `nixosConfigurations.example`
  evaluates; no file names a person.
- Private repo: `nix flake check` (or eval of the xps9370 toplevel
  drvPath) passes with the real values.
- `docs/private-layer.md` passes the stranger test: someone who has never
  seen our private repo knows exactly what to write.
- PRs #1 and #4 still open, rewritten, CI green on both.
