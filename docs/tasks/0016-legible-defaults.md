# Task 0016 — Legible text by default

**Before starting:** read `CLAUDE.md`, `modules/desktop/default.nix`
(how `castle.display.*` options are declared, and how
`castle.display.wallpaper` is the one option the *framework* defaults
on its own with `lib.mkDefault` — this task extends that precedent),
`modules/home/default.nix` (where those options are consumed and how
every block is guarded on `swayEnabled`), `hosts/xps9370/default.nix`
(why `scale` and `cursorSize` live at the host layer), and
`docs/tasks/0013-first-deploy-findings.md` (the cursor-size
double-compensation bug — the cautionary tale for picking display
numbers by reasoning instead of by looking). Work on branch
`legible-defaults`; this brief rides it. PR to `main`.

**Goal.** A fresh Castle Turing desktop is readable without the
resident changing anything — from the boot console through the login
greeter to the terminal, the window chrome, and GTK applications — and
a resident can still set every one of those sizes from their private
layer.

## The problem, measured

Observed on `hosts/xps9370` (3840×2160, 13.3", ~331 PPI) running the
deployed system, not inferred:

| Surface | Current source of truth | What it renders |
|---|---|---|
| Console + tuigreet greeter | kernel built-in 8×16, `console.font` set nowhere | 3840×2160 framebuffer (`/sys/class/graphics/fb0/virtual_size`), so glyphs ~1.2 mm tall |
| foot terminal | foot's built-in `monospace:size=8`; `castle.display.terminalFontSize` is `null` and the private layer sets nothing, so no `foot.ini` is written at all | 8 pt |
| Sway titlebars + swaynag | home-manager default `font pango:monospace 8.000000` | 8 pt |
| swaybar | home-manager's default `bars` entry, `monospace 8.0` | 8 pt |
| GTK apps, Firefox chrome | nothing — no `~/.config/gtk-3.0/settings.ini`, `gtk.enable` never set | GTK's stock `Sans 10` |

`castle.display.scale = 2.0` is already correct and is **not** the
problem: it makes the panel present as 1920×1080 logical (~165 PPI
effective), which is the right density baseline. Everything above is
too small *on top of* correct scaling — five surfaces whose sizes the
framework never expresses an opinion about, four of which sit at 8 pt.

The console is the worst of them and the least visible in normal use:
it is what you read at boot, and it is the only thing you have in a
recovery fallback, which is exactly when you cannot afford unreadable
text.

## The design decision, and why

**Per-surface point sizes with opinionated framework defaults**, not a
single `textScale` multiplier and not a bigger output scale.

- *Not a `textScale` multiplier*: the five surfaces take three
  different units — Pango points, a pixel-grid console font name, and
  (for foot) a fontconfig size. Fanning one float out across them
  means the framework inventing a mapping and rounding it, which is
  guesswork wearing a knob.
- *Not raising `scale` to 2.5*: one line, but it shrinks usable area
  to 1536×864 on a 13" panel and does nothing at all for the console
  or the greeter, which never see `scale`.
- *Framework defaults rather than `null`*: "a fresh desktop is
  legible" is a property of the framework, not the resident's taste.
  `castle.display.wallpaper` already established that a framework
  module may `lib.mkDefault` a value of its own when there is exactly
  one sensible answer and the alternative is a broken-looking desktop;
  the alternative here is a stranger installing this repo and getting
  8 pt text on every surface. Principle 01 still holds: the mechanism
  (options + wiring) is public, the resident's numbers override at
  normal priority.

**One exception, and it is a real one.** `consoleFont` cannot be a
framework default the way the point sizes can. Point sizes are
density-independent *because* `castle.display.scale` normalizes
density; the console never sees `scale`, so a console font is a raw
pixel grid. `ter-v32n` is right on a 331 PPI panel and absurd on a
1080p one. That is precisely the argument that put `scale` and
`cursorSize` in `hosts/xps9370` rather than `modules/desktop`. So:
`consoleFont` is **declared** in `modules/desktop` with a `null`
default, and **set** in `hosts/xps9370` with `lib.mkDefault`, next to
`scale`. Do not "fix" this into a framework default for consistency
with its three siblings — the asymmetry is the point, and this
paragraph is the record of why.

## How the two point sizes were picked

Both were **calibrated by eye on the actual panel** during the spec
session, not reasoned to. This matters because 0013 is the record of
what happens when a display number is argued into place instead:

- **`terminalFontSize = 12`.** Three `foot` windows were opened
  side-by-side at `--font=monospace:size=11/12/13`, each showing the
  same sample (prose, a Nix snippet, a diff, and a dense `journalctl`
  line — the four things actually read in a terminal here). 12 won.
- **`uiFontSize = 11`.** Three `swaynag` bars at `-f 'DejaVu Sans
  11/12/13'`, stacked and compared the same way. 11 won.

**The two numbers differ on purpose, and 11 < 12 is not a mistake.**
They are different font families in different units: 11 pt
proportional sans renders visibly larger than 11 pt monospace, so
matching the digits would have made the UI chrome heavier than the
terminal, not equal to it. A future reader who "harmonises" these to a
single number will be undoing a measurement. If either genuinely needs
to change, re-run the sweep above and update this section with the new
result — do not just change the digit.

The reasoned starting guess for both was 11 (GNOME's default). One of
the two survived contact with the panel; the other did not, which is
the argument for keeping the sweep in this brief rather than treating
it as a one-off.

## Scope

1. **`castle.display.terminalFontSize`** (exists, `modules/desktop`) —
   change its default from `null` to `lib.mkDefault 12`. Its
   description currently says `null` means "foot's own built-in size
   applies"; rewrite it to describe the framework default and why the
   framework has an opinion, mirroring `wallpaper`'s description, and
   point at "How the two point sizes were picked" above.

2. **`castle.display.uiFontSize`** (new, `modules/desktop`) —
   `nullOr ints.positive`, framework-defaulted to `lib.mkDefault 11`.
   Drives both the GTK font size and Sway's own chrome, since they are
   the same "UI text" concept at the same density; a resident who
   wants them to differ can set the underlying home-manager options in
   their own layer.

3. **`castle.display.consoleFont`** (new, `modules/desktop`) —
   `nullOr str`, default `null` ("kernel built-in font"), named as a
   `console.font` value. Wire it to `console.font`, and add
   `pkgs.terminus_font` to `console.packages` so the option has
   something real to name — the same "ship the package so the option
   resolves" move `pkgs.bibata-cursors` makes for `cursorTheme` and
   `wallpaperPackage` makes for `wallpaper`. Set
   `consoleFont = lib.mkDefault "ter-v32n"` in `hosts/xps9370`, in the
   same `castle.display` block as `scale`, with a comment explaining
   the panel-density derivation.

   Verified available: `pkgs.terminus_font` ships
   `ter-v24n/v28n/v32n` (`share/consolefonts`). **32 px is the
   ceiling** — `fbcon` will not load a glyph taller than 32 — so this
   is as large as the console gets without a different mechanism
   (kmscon and friends), and at 32 px it is ~2.4 mm on this panel,
   which lands close to foot at 12 pt × scale 2.0. Say so in the
   comment; a future reader will otherwise try `ter-v40n` and get a
   silent fallback.

   Consider `console.earlySetup = true` so the font applies in the
   initrd rather than after stage 2 — decide and record which, since
   an unreadable early-boot console is half the problem this item
   exists to fix.

4. **GTK wiring** (`modules/home`) — `gtk.enable = true` with
   `gtk.font = { name = "DejaVu Sans"; size = uiFontSize; package =
   pkgs.dejavu_fonts; }`, guarded on `swayEnabled` like every other
   display block in that module, and omitted entirely when
   `uiFontSize` is null. Name a font the framework actually ships
   (`modules/desktop`'s `fonts.packages` has `dejavu_fonts`,
   `liberation_ttf`, `noto-fonts`) rather than `Sans` or `Cantarell` —
   `Cantarell` is not installed, and GTK silently falling back is how
   you end up debugging the wrong thing.

   Note this turns on home-manager's GTK module, which writes
   `gtk-3.0/settings.ini`, `gtk-4.0/settings.ini`, and dconf keys. That
   is more GTK surface than this repo has had; keep it to the font and
   resist adding a theme, in the same spirit as `modules/home`'s "not
   a ricing project" comment.

5. **Sway chrome** (`modules/home`) — set
   `wayland.windowManager.sway.config.fonts = { names = [ "DejaVu Sans" ];
   size = uiFontSize; }`, which covers window titles and swaynag. This
   is the exact pairing the `uiFontSize` sweep was run against.

6. **swaybar** (`modules/home`) — the bar carries its own font and is
   *not* covered by item 5. **Read this before implementing:**
   home-manager's `bars` option default is a fully-spelled-out
   single-element list (mode, hiddenState, position, workspaceButtons,
   workspaceNumbers, `statusCommand = i3status`, colors, trayOutput,
   fonts), while `barModule`'s own per-option defaults are `null` for
   `stateVersion >= 20.09`. So supplying `bars = [ { fonts = ...; } ]`
   does **not** merge with that default — it replaces the list, and the
   remaining fields come back null, silently costing the status line
   and the stock colors.

   Two honest ways out; pick one and record the choice in the
   implementation notes below: (a) restate home-manager's default bar
   entry with the font size swapped, accepting that this pins ~8 values
   that could drift when the home-manager input is updated; or (b)
   leave the bar at 8 pt in this task and file a backlog entry. (a) is
   preferred — a bar that stays at 8 pt while everything around it
   grows is a visibly half-finished job — but (a) must carry a comment
   naming the pin, so the next input bump has something to check
   against.

7. **`docs/private-layer.md`** — it currently says "four options" and
   enumerates `{scale,cursorTheme,cursorSize,terminalFontSize}` in
   three places (the commented example block, the option list, and
   "The display-preference slot"). Update all of them: the count, the
   two new options, and — importantly — the fact that the layering
   story is no longer uniform, since `terminalFontSize` and
   `uiFontSize` now resolve from a *framework* default while
   `consoleFont` resolves from a *host* default. The doc's claim that
   `null` means "leave that setting alone entirely" is no longer true
   for the two point sizes and must be corrected, not glossed.

8. **`flake.nix`'s `nixosConfigurations.example` assertion** — it
   currently proves the three-layer resolution for the existing
   options. Extend it to cover the new ones, including the asymmetry:
   a framework-defaulted option and a host-defaulted one resolve
   differently, and an assertion is the cheapest place to keep that
   honest.

## Verification

**Automated, no human needed** — extend the existing jobs in
`.github/workflows/check.yml` rather than adding new ones; it already
builds the generated configs, runs `sway --validate` over the
generated Sway config, greps that config for expected content (the
default keybindings, the wallpaper path), and runs `foot --check-config`:

- `nix flake check` — the `example` assertion from scope item 8.
- Grep the generated Sway config for `font pango:DejaVu Sans 11` at top
  level and inside the `bar {}` block. The wallpaper-path job is the
  precedent for "assert the generated config actually carries the value".
- `foot --check-config` over the generated `foot.ini`, plus a grep for
  `font=monospace:size=12` — today no `foot.ini` is generated at all,
  so this is a new file appearing, not a changed one.
- Build `nixosConfigurations.xps9370` and assert `console.font`
  resolves to `ter-v32n` and that the built system's console font file
  exists in the store.

**Needs human hands.** The two point sizes are already calibrated (see
above), so the remaining human step is narrower than it would have
been — but it is not zero, because the console font is the one value
that cannot be previewed from inside a running Wayland session:

- `nixos-rebuild switch`, log out and back in, and confirm the
  calibrated sizes survived the round trip into GTK and Sway chrome —
  a Firefox window, a file picker, a titlebar, the bar.
- **Reboot.** This is the step that actually tests item 3: the early
  console, then the tuigreet greeter. `ter-v32n` is a reasoned value,
  not a measured one, and 32 px is the ceiling — if it is still too
  small there is no larger font to reach for, and the finding is
  "the console needs a different mechanism", which belongs in
  `docs/backlog/`, not in a bigger number.

## Non-goals

- **Firefox web-content size.** Item 4 covers Firefox's *chrome* via
  GTK. Page text is a separate knob (`layout.css.devPixelsPerPx`, or
  the default-zoom preference) and is resident taste, not framework
  legibility — at scale 2.0 web content is already rendering at the
  same physical size it would on any 1080p 13" laptop.
- **The XWayland/GTK cursor-scale gap** documented in
  `modules/desktop` and `hosts/xps9370`. Still real, still unsolved,
  still needs its own investigation. Nothing in this task touches it,
  and no number here should be inflated to compensate for it — that
  reasoning is what produced 0013's bug 1.
- **A GTK theme, icon theme, or any further ricing.** Font size only.
- **Changing `castle.display.scale`.** It is correct; see "The
  problem, measured".
- **Per-application font overrides** (a different font for the
  terminal than for the editor, etc.). Sizes only, one font family
  each for mono and sans.

## Implementation notes (corrections to the above, discovered while building it)

*(to be filled in by the implementing session — per `CLAUDE.md`, if the
design shifts during implementation, this same PR updates this brief.
Item 6's (a)-or-(b) choice must be recorded here.)*
