# Wallpapers

`castle-turing.jpg` is this repo's first non-text artifact — everything
else here is source, config, or prose (`CLAUDE.md`: "if a tool choice
trades AI-legibility for features, flag it"; a binary image is exactly
that trade, made once and recorded here rather than made quietly).

## What it is

AI-generated artwork depicting the castle from *The Diamond Age* — the
project's namesake (see the top-level `README.md`). Generated at seven
resolutions as a PNG image pack; only this one file is kept here. See
`docs/tasks/0014-default-wallpaper.md` for the full record of that
generation.

## Why one file, this format

The source pack shipped the same artwork at seven resolutions (28 MB of
PNG, from a 1672x941 `original` — everything above that is upscaled and
carries no extra detail `swaybg` couldn't produce itself by scaling the
same base image). `swaybg` scales to fit any output, so six of the seven
are redundancy, not options; do not add them back.

3840x2160, JPEG, quality 85, 1.48 MB is what's committed. AVIF encodes
the same artwork at 0.54 MB — a third the size — but `swaybg` decodes
through gdk-pixbuf, and AVIF/WebP need loader packages this framework
does not wire in by default. An unreadable wallpaper fails silently (a
black desktop, no error dialog — Sway has nothing to report if a `bg`
line's decoder is just missing), which is a worse failure mode on
someone else's machine than 1 MB of extra JPEG. Do not "optimise" this
back to AVIF without first adding and proving out the gdk-pixbuf AVIF
loader in `modules/desktop`.

## Licensing

Covered by the repository's top-level MIT `LICENSE`, same as the code
around it — artwork is deliberately not licensed separately (see
`docs/tasks/0037-mit-license.md`). The image is AI-generated, so there
is no third-party rights holder behind it.

## Where it lands

Packaged as a derivation by `modules/desktop/default.nix`
(`wallpaperPackage`), not referenced as a bare source path, so
`castle.display.wallpaper` has a real store path to resolve to. See that
option's description for how the three layers (framework default, this
module's own `mkDefault`, private-layer override) resolve, and
`modules/home/default.nix` for how it reaches Sway's `bg` directive.
