# Should Castle Turing ship a typeface?

**What.** Decide whether the framework ships an opinionated default
typeface — the way it already ships a default wallpaper — or whether a
typeface stays a resident's choice supplied from the private layer,
with the framework declaring only the option.

**Why it matters.** Task 0016 declares the mechanism (a font-family
option) and deliberately does not answer this: the resident's own face
lands in the private layer for now, so the decision is deferred rather
than made by default. But it is a real fork in what this project is.
The framework already ships a wallpaper — an aesthetic asset with a
`lib.mkDefault`, justified on the grounds that "a fresh desktop should
look like something" is a framework property. A typeface is the same
argument at ten times the disk cost and rather more taste. If the
answer is yes, `modules/desktop` grows an opinion about how the whole
system reads; if no, every new resident gets DejaVu until they know
enough to change it, which is a worse first impression than the
wallpaper decision accepted.

There is also a stated preference on the record, which is why this is a
backlog entry rather than a closed question: the resident wants some of
their own taste in the framework, not only in their private layer.
Whether that generalises to strangers is exactly what speccing has to
work out — `CLAUDE.md`'s "docs are written for strangers" cuts both
ways here, since a stranger inherits the taste along with the
mechanism.

**What we already know.**

- **Measured, not estimated: `iosevka-bin` with `variant = "Slab"` is
  434 MB unpacked in the store** (the `SGr-IosevkaTermSlab` variant is
  532 MB). That lands in the closure of every host importing
  `modules/desktop`. For scale, `dejavu_fonts` is already in that
  module's `fonts.packages` and costs single-digit megabytes. An
  earlier estimate of "~60 MB" in conversation was the download size
  recalled from memory and was wrong by roughly sevenfold — measure
  the store path, do not trust the release zip size.
- **One package covers three families.** The plain `variant = "Slab"`
  TTC bundles `Iosevka Slab`, `Iosevka Term Slab`, and `Iosevka Fixed
  Slab`. Verified with a clean fontconfig cache. The separate
  `SGr-IosevkaTermSlab` variant is redundant and larger.
- **`iosevka` and `iosevka-bin` are different packages.** The former
  builds from source and takes hours; anything specced here should name
  `iosevka-bin` explicitly.
- **The quasi-proportional cuts are not terminal fonts.** `Iosevka
  Aile` and `Iosevka Etoile` report no fontconfig `spacing` property
  (against `spacing=90` for the monospaced cuts), so a grid terminal
  forces them into a single cell width. They remain live candidates for
  the *UI* font (`castle.display.uiFontSize`'s family), where pairing
  Aile with a monospaced Iosevka in the terminal would make the desktop
  read as one system.
- **The wallpaper is the precedent to argue with, in both
  directions.** `modules/desktop` ships `castle-turing.jpg` and
  `mkDefault`s it, on reasoning recorded in task 0014 — a
  framework-owned asset with exactly one canonical default. A typeface
  fits that description; it just costs two orders of magnitude more
  disk and touches every application rather than the desktop
  background.
- Task 0016's split is the status quo this entry may overturn: the
  framework declares the font-family option with a `monospace` default
  (which resolves to DejaVu Sans Mono via fontconfig, already
  installed, zero added closure), and the resident's private layer
  supplies `Iosevka Slab Light Extended` at size 12.

**Open questions.** Does shipping a typeface serve strangers or impose
on them — and is that different from the wallpaper, which imposes
nothing a resident cannot ignore? If yes, which variant, and does the
434 MB matter enough to want a slimmer build (`iosevka` from source
with a custom glyph set is smaller but costs hours to build; a Nerd
Font variant is larger still)? Does an installer image carry it, where
size is a real constraint? Is there a middle path — an opt-in module
(`castle.display.typeface.iosevka.enable`) that ships the packaging but
not the closure, so a resident gets one line instead of a font
derivation? And does the answer here bind the UI font too, or can the
terminal and the chrome be decided separately?
