# Task 0037 — The repo's license matches Principle 01: MIT

Promotes `docs/backlog/the-repo-has-no-license.md` (deleted in this
commit). Principle 01 opens with "everything built in this project is
open source"; with no `LICENSE` file, the legal default is all rights
reserved — the stated principle and the legal reality were opposites.

**Decision (resident, 2026-09-01): MIT.** Permissive fits "open by
construction": a stranger adopting the framework this weekend should
face no obligation beyond preserving the copyright and license notices
in copies or substantial portions they redistribute. Copyleft (GPL/AGPL) was the
considered alternative and was not chosen — the private-layer split
already makes a resident's own configuration a separate repo, not a
derivative work in most readings, so copyleft's leverage over the case
we care about is weak anyway. Artwork is not licensed separately: the
repo-root MIT grant covers the wallpaper too, and the honest "no
license yet" note in `modules/desktop/wallpapers/README.md` is updated
to say so. Whether the `chevaline` sibling repo should match is out of
scope here — that question stays with the resident.

Verification: `nix flake check` (untouched by a docs/LICENSE change),
plus a repo-wide grep for license/copyright claims to reconcile.
