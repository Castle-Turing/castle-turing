# Task 0014 — A default desktop wallpaper

**Before starting:** read `CLAUDE.md`, `modules/desktop/default.nix`
(especially how `castle.display.cursorTheme` is declared and how
`pkgs.bibata-cursors` is shipped so that option has something real to
point at — this task mirrors it), `modules/home/default.nix` (where
`castle.display.*` is consumed), and `docs/tasks/0009-ambient-intake.md`
for the three-layer resolution story. Work on branch
`wallpaper-default`; this brief rides it. PR to `main`.

**Goal.** A fresh Castle Turing desktop has a wallpaper instead of a
grey void, and a resident can choose it or turn it off from their
private layer.

## Why a small fun feature still gets a brief

Because every implementation does (`CLAUDE.md`), and because this one
introduces the repo's **first non-text artifact**. That is worth a
deliberate record rather than a quiet commit — `CLAUDE.md` asks that a
choice trading AI-legibility for features be flagged, and this is one.
The mechanism around it stays plain text; the image does not.

## What is already prepared

`modules/desktop/wallpapers/castle-turing.jpg` — 3840×2160, JPEG q85,
**1.48 MB**, already in your worktree. Do not add other formats or
resolutions.

The decisions behind that file, so you do not relitigate them:

- **One image, not seven.** The source pack shipped the same artwork at
  seven resolutions, 28 MB of PNG. `swaybg` scales, so the extra six are
  redundancy. Note also that the pack's own `original` was 1672×941 —
  everything above that is upscaled and carries no additional detail.
- **JPEG, not AVIF or WebP**, despite AVIF being 0.54 MB against JPEG's
  1.48 MB. `swaybg` decodes through gdk-pixbuf, and AVIF/WebP need
  loader packages that are not wired in by default. The smallest file is
  the one most likely to produce a black desktop and a confusing
  debugging session on someone else's setup. Do not "optimise" this back
  to AVIF without first proving the loader is present.

## Scope

1. **`castle.display.wallpaper`** in `modules/desktop` — `nullOr str`,
   default `null` meaning "no wallpaper set, whatever the compositor
   does." Mirror `cursorTheme`'s option documentation, including the
   three-layer resolution note.
2. **Package the image as a derivation** rather than referencing a
   source path at runtime, so it lands in the store. `bibata-cursors`
   being shipped by `modules/desktop` is the precedent for *why* the
   framework ships an asset at all: an option needs something real to
   resolve to.
3. **Consume it in `modules/home`**, wiring to
   `wayland.windowManager.sway.config.output."*".bg`, guarded the same
   way the other `castle.display` settings are — a host that skips
   `modules/desktop` must be unaffected. Choose and document a scaling
   mode (`fill` is the usual default; say why in a comment).
4. **A README in `modules/desktop/wallpapers/`** recording that the
   artwork is generated, that it is covered by the repo's existing
   LICENSE, and — briefly — the format reasoning above, so the next
   person does not repeat the AVIF analysis.
5. **Extend `sway-config-check`** so it asserts the generated Sway
   config's `bg` line names a file that actually exists in the store.
   A wallpaper option that silently points at nothing is precisely the
   class of bug this repo keeps finding.

## Verification

Agent-testable: `nix flake check`; `sway-config-check` printing the
generated config and asserting the `bg` line resolves. **Verify that
assertion by pointing it at a non-existent file and confirming the check
goes red**, then restore — three real bugs have been caught this week by
checks that were watched failing, and at least three others slipped
through checks that were not.

Human hands: the resident confirms it looks right after a re-login.
Perceptual, and not something a harness can judge.

## Non-goals

- Multiple wallpapers, a picker, or per-output backgrounds. One image,
  one option.
- Any other image format or resolution. See above.
- Committing the original zip or the other six PNGs — they are archived
  outside the repo and must not land in git history, where they would be
  permanent.
- Light/dark variants, theming, or anything touching `castle.display`'s
  other options.
