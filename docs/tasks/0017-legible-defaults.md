# Task 0017 — Legible text by default

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
pixel grid. `spleen-16x32` is right on a 331 PPI panel and absurd on a
1080p one. That is precisely the argument that put `scale` and
`cursorSize` in `hosts/xps9370` rather than `modules/desktop`. So:
`consoleFont` is **declared** in `modules/desktop` with a `null`
default, and **set** in `hosts/xps9370` with `lib.mkDefault`, next to
`scale`. Do not "fix" this into a framework default for consistency
with its three siblings — the asymmetry is the point, and this
paragraph is the record of why.

## How the sizes and the typeface were picked

All of it was **calibrated by eye on the actual panel** during the spec
session, not reasoned to. This matters because 0013 is the record of
what happens when a display number is argued into place instead:

- **`terminalFontSize = 12`.** Three `foot` windows were opened
  side-by-side at `--font=monospace:size=11/12/13`, each showing the
  same sample (prose, a Nix snippet, a diff, and a dense `journalctl`
  line — the four things actually read in a terminal here). 12 won,
  and 12 was re-confirmed afterwards against the chosen typeface
  rather than assumed to transfer across faces.
- **`uiFontSize = 10`, `uiFont = Iosevka Aile Medium`.** This one took
  two passes, and the first pass produced a number that did not
  survive the second. Round one swept `DejaVu Sans` at 11/12/13 and
  picked 11 — but only the *size* was chosen there; DejaVu Sans was
  the framework's existing font, not a decision. Round two swept the
  family (`Iosevka Aile` / `Iosevka Etoile` / `DejaVu Sans`), then
  Aile's weights, then size again at the winning weight, landing on
  **Medium 10**.

  The size moved from 11 to 10 because **weight and size trade against
  each other**: Medium restores the visual solidity that dropping a
  point costs, so Medium 10 reads about as substantial as Regular 11
  while taking less vertical space in titlebars and the bar. Do not
  "restore" this to 11 on the assumption that a smaller number is a
  regression — it is the same pattern as `cursorSize = 18` in
  `hosts/xps9370`, a below-expectation value that is correct because
  it was measured rather than derived.
  A note on authority, because the record should be unambiguous about
  who chose what: an earlier draft of this brief named `DejaVu Sans` in
  the scope items as though it were a resident choice. It was not — it
  was the framework's incumbent font, defaulted to by the author of
  that draft. The resident chose `Iosevka Aile Medium 10`. Everything
  else DejaVu-shaped in this brief is a *framework default*, and the
  two are labelled as such below.

- **The terminal typeface: `Iosevka Slab Light Extended`.** Reached by
  successive elimination in the same live-preview harness — DejaVu
  Sans Mono against Iosevka; Iosevka against Iosevka Slab and Term
  Slab; then weight (Light / Regular / Medium / Semibold) and width
  (normal vs Extended) at fixed size; then size again at the winning
  weight and width. It lives in the **private layer**, not here — see
  scope item 9 and `docs/backlog/shipping-a-default-typeface.md`.

  Two facts that fell out of that sweep and are worth not re-deriving:
  `Iosevka Aile` and `Iosevka Etoile` report no fontconfig `spacing`
  property (the monospaced cuts report `spacing=90`), so a grid
  terminal forces them into one cell width and they are not terminal
  candidates — only UI-font candidates. And `iosevka-bin` with
  `variant = "Slab"` is **434 MB unpacked**, which is the whole reason
  the typeface question got deferred to the backlog instead of being
  answered here.

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

   **The framework default is 11, not the resident's 10.** 10 is
   correct *paired with `Iosevka Aile Medium`*, whose weight buys back
   what the smaller size costs; against the framework's own default
   sans it would be too light. This is the clearest case in the brief
   of a value that is only right in combination — the resident's 10
   goes in their private layer next to the face it belongs with, and
   the framework keeps the size that suits the font the framework
   actually ships.

3. **`castle.display.consoleFont`** (new, `modules/desktop`) —
   `nullOr str`, default `null` ("kernel built-in font"), named as a
   `console.font` value. Wire it to `console.font`, and add
   `pkgs.spleen` to `console.packages` so the option has
   something real to name — the same "ship the package so the option
   resolves" move `pkgs.bibata-cursors` makes for `cursorTheme` and
   `wallpaperPackage` makes for `wallpaper`. Set
   `consoleFont = lib.mkDefault "spleen-16x32"` in `hosts/xps9370`, in
   the same `castle.display` block as `scale`, with a comment
   explaining the panel-density derivation.

   **Correction to an earlier draft of this brief: there is no 32 px
   ceiling.** That draft claimed `fbcon` will not load a glyph taller
   than 32 px, and used it to argue Terminus was as large as the
   console could get. It was asserted, not tested, and it is false —
   `sudo setfont -C /dev/tty6 spleen-32x64.psfu` loads without
   complaint on this kernel. The claim is recorded here because it
   very nearly capped the console at half its useful size for no
   reason.

   That reopened the choice, and it was then settled by looking — each
   candidate loaded onto a spare VT with `setfont -C /dev/ttyN` and
   compared by switching between them, showing a sample built from what
   a console is actually for (a login prompt, a boot log line, an
   emergency-mode message):

   | Font | Package | Grid at 3840×2160 | Glyph height | |
   |---|---|---|---|---|
   | `ter-v32n` | `pkgs.terminus_font` | 240×67 | ~2.4 mm | |
   | **`spleen-16x32`** | **`pkgs.spleen`** | **240×67** | **~2.4 mm** | **chosen** |
   | `spleen-32x64` | `pkgs.spleen` | 120×33 | ~4.9 mm | |
   | `spleen-24x48` | *generated* | 160×45 | ~3.7 mm | rejected |

   Two notes for anyone reopening this. **Spleen was preferred over
   Terminus at identical metrics** — same 16×32 grid, so this was a
   choice of design, not size. And the fourth row was an experiment
   worth not repeating blindly: nothing in nixpkgs sits between 32 px
   and 64 px tall (Terminus stops at 32, `uw-ttyp0` at 30, Cozette at
   26, Tamsyn at 20, and Spleen jumps straight from 16×32 to 32×64), so
   a 24×48 intermediate was manufactured by pixel-doubling Spleen's
   `12x24` through `psf2txt` → awk → `txt2psf`. It loads fine, but it
   is a doubled 12×24, not a face drawn at 24×48, and it lost. Building
   it would also have meant this repo carrying a generated-font
   derivation — real machinery for a surface seen at boot and in
   recovery. Naming a stock font is the cheaper, more legible answer.

   Consider `console.earlySetup = true` so the font applies in the
   initrd rather than after stage 2 — decide and record which, since
   an unreadable early-boot console is half the problem this item
   exists to fix.

4. **GTK wiring** (`modules/home`) — `gtk.enable = true` with
   `gtk.font = { name = uiFont; size = uiFontSize; }`, guarded on
   `swayEnabled` like every other display block in that module, and
   omitted entirely when either option is null. `uiFont` is the new
   family option from item 9; its framework default names a font
   `modules/desktop` actually ships (`fonts.packages` has
   `dejavu_fonts`, `liberation_ttf`, `noto-fonts`) rather than
   `Cantarell`, which is *not* installed and would silently fall back —
   that is a debugging session nobody should have to have.

   Leave `gtk.font.package` unset: the framework's default family is
   already installed system-wide, and a resident supplying their own
   family supplies its package in the same private layer.

   Note this turns on home-manager's GTK module, which writes
   `gtk-3.0/settings.ini`, `gtk-4.0/settings.ini`, and dconf keys. That
   is more GTK surface than this repo has had; keep it to the font and
   resist adding a theme, in the same spirit as `modules/home`'s "not
   a ricing project" comment.

5. **Sway chrome** (`modules/home`) — set
   `wayland.windowManager.sway.config.fonts = { names = [ uiFont ];
   size = uiFontSize; }`. This covers window titles **and swaynag** —
   they are one setting in Sway, not two (home-manager's own
   description for this option reads "Font configuration for window
   titles, nagbar..."), which is why the `uiFontSize` sweep used
   `swaynag` bars as its instrument: they render the very setting being
   measured.

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
   four new options (`uiFontSize`, `consoleFont`, `terminalFont`,
   `uiFont`), and — importantly — the fact that the layering story is
   no longer uniform. Three different layers now supply values:

   | Option | Resolved by | Why |
   |---|---|---|
   | `terminalFontSize`, `uiFontSize` | framework default | density-independent, `scale` normalizes them |
   | `consoleFont` | host module | a pixel grid; the console never sees `scale` |
   | `terminalFont`, `uiFont` | resident's private layer | taste, and the package cost is theirs to choose |

   The doc's claim that `null` means "leave that setting alone
   entirely" is no longer true for the two point sizes and must be
   corrected, not glossed. The commented example block is also the
   right place to show real `terminalFont`/`uiFont` values, since item
   9's whole point is that these are the options a resident is
   *expected* to set.

8. **`flake.nix`'s `nixosConfigurations.example` assertion** — it
   currently proves the three-layer resolution for the existing
   options. Extend it to cover the new ones, including the asymmetry:
   a framework-defaulted option and a host-defaulted one resolve
   differently, and an assertion is the cheapest place to keep that
   honest.

9. **`castle.display.terminalFont` and `castle.display.uiFont`** (new,
   `modules/desktop`) — `nullOr str` family names, each pairing with
   the size option beside it.

   `terminalFont` is a fontconfig pattern wired into the same
   `programs.foot.settings.main.font` string as `terminalFontSize`, so
   the two compose into one `<family>:size=<n>` value. Framework
   default: **`monospace`**, which fontconfig already resolves to
   DejaVu Sans Mono from `modules/desktop`'s existing `fonts.packages`
   — zero added closure.

   `uiFont` is a family name consumed by items 4, 5 and 6 (GTK, Sway
   chrome, the bar). Framework default: **`sans-serif`**, for the same
   reason — a generic fontconfig family is guaranteed to resolve to
   something installed, where a specific name is a silent-fallback
   trap. Note the unit difference between its two consumers: GTK takes
   family and size as separate fields, while Sway wants a Pango
   description; a weight like `Medium` therefore rides *in the family
   string* (`Iosevka Aile Medium`) rather than in a separate option.
   That is why there is no `uiFontWeight` — Pango and fontconfig both
   accept the weight inside the name, and a third option would only
   have to be reassembled into the same string.

   **These options exist so the framework does *not* have to answer the
   typeface question.** The resident's choices — `Iosevka Slab Light
   Extended` at 12 for the terminal, `Iosevka Aile Medium` at 10 for
   the chrome — live in their private layer along with the two
   `iosevka-bin` packages that provide them, and the framework ships
   neither. Whether Castle Turing should ship an opinionated typeface
   of its own is deliberately deferred to
   `docs/backlog/shipping-a-default-typeface.md`; do not quietly settle
   it by adding a font package here.

   That the resident's pair is Slab (terminal) plus Aile (chrome) is
   not incidental: they are two cuts of one typeface, chosen together
   so the desktop reads as one system. If the backlog question is ever
   answered "yes, ship it", it is that *pairing* that would ship, and
   it costs two font packages, not one.

   Two traps for the implementer, both found the hard way during
   speccing. A fontconfig family name is not enough on its own: the
   package providing it has to be installed or the name silently falls
   back to something else, which is why the framework default is
   `monospace` (guaranteed to resolve) rather than a specific face.
   And `pkgs.iosevka` builds from source and takes hours — anything
   touching this must name **`iosevka-bin`**, whose `variant = "Slab"`
   TTC bundles `Iosevka Slab`, `Iosevka Term Slab`, and `Iosevka Fixed
   Slab` together (verified with a clean fontconfig cache), so one
   package covers all three families.

10. **The calibration harness** — `tools/font-sweep.sh` and
    `tools/console-font-sweep.sh`, committed on this branch alongside
    a `tools/README.md` section.

    Every value in this brief was picked by opening N panes, bars, or
    VTs with one variable changed and looking. That worked, and it is
    the reason this brief tells its reader to *re-run the sweep* rather
    than edit a digit. An instruction to re-run something that only
    ever existed as throwaway commands in one session is worthless —
    which is exactly `CLAUDE.md`'s "a step that will repeat belongs in
    a harness before it repeats", and this step repeated four times
    inside a single spec session.

    Principle 01 split: the mechanism (open N, same sample, one
    variable, restore on exit) is public; the faces and sizes are
    arguments, and the winner goes to a private layer or host module.

    **Three bugs were found by using these scripts, not by reading
    them**, and each is commented at its fix site because each is a
    trap the next author would re-enter:

    - A focused-workspace lookup with a fixed `grep -B2` window that
      never matched. Under `set -euo pipefail` the failed pipeline
      killed the script *silently*, before a single window opened.
    - `read` on a non-TTY stdin returns EOF immediately, tearing the
      sweep down before anything could be seen — which made the tool
      undrivable by an agent session, the exact caller it needs to
      support.
    - `while :; do sleep 3600; done` defers SIGTERM until the sleep
      returns, so teardown never ran: killed sweeps left windows on
      screen and the next sweep stacked on top of them. Fixed with
      `sleep & wait $!`, which is interruptible. In the console script
      this one is worse than cosmetic — a swallowed TERM leaves the VTs
      carrying the swept font instead of the kernel default.

    **One open question the implementer should not settle silently.**
    `tools/README.md` currently scopes that directory to "tooling for
    people and agent sessions editing the repo itself... no reason to
    exist on a resident's actual machine." A font sweep does not fit
    that description: a resident re-runs it whenever they want to
    change how their machine looks, long after this repo stops
    changing. Either the README's charter widens, or this eventually
    belongs on a deployed system as a real command (a
    `castle-font-sweep` on `$PATH` from `modules/desktop`), which is a
    product decision about the framework's surface, not a tooling
    tidy-up. Put it in `tools/` for now, say plainly in the README that
    the boundary is unresolved, and file the packaging question if it
    starts to bite.

## Verification

**Automated, no human needed** — extend the existing jobs in
`.github/workflows/check.yml` rather than adding new ones; it already
builds the generated configs, runs `sway --validate` over the
generated Sway config, greps that config for expected content (the
default keybindings, the wallpaper path), and runs `foot --check-config`:

- `nix flake check` — the `example` assertion from scope item 8.
- Grep the generated Sway config for `font pango:sans-serif 11` at top
  level and inside the `bar {}` block. The wallpaper-path job is the
  precedent for "assert the generated config actually carries the value".
  As with `foot.ini` below, CI asserts the **framework defaults**
  (`sans-serif`, 11) — the resident's `Iosevka Aile Medium 10` comes
  from a private layer this repo cannot see, so a test expecting it
  would fail for every stranger.
- `foot --check-config` over the generated `foot.ini`, plus a grep for
  `size=12` — today no `foot.ini` is generated at all, so this is a new
  file appearing, not a changed one. Note the family in that file comes
  from the private layer (item 9), so CI must assert the *framework
  default* (`monospace`), not the resident's Iosevka.
- Build `nixosConfigurations.xps9370` and assert `console.font`
  resolves to `spleen-16x32` and that the built system's console font
  file exists in the store.

**Needs human hands.** Every value in this brief was calibrated by eye
before it was written down (see "How the sizes and the typeface were
picked"), including the console font — so unlike a normal first deploy,
the remaining human work is confirming the numbers *survive the round
trip through Nix*, not discovering what they should be:

- `nixos-rebuild switch`, log out and back in, and confirm the
  calibrated sizes survived into GTK and Sway chrome — a Firefox
  window, a file picker, a titlebar, the bar.
- **Reboot.** This is the step that actually tests item 3, and it is
  the one thing a live session cannot preview: `setfont` on a spare VT
  proves a font *loads*, but not that `console.font` reaches the early
  console and the tuigreet greeter through the initrd. If the font is
  right on a switched-to VT and wrong at boot, the bug is in
  `earlySetup`, not in the choice.

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
- **A GTK theme or icon theme.** Fonts only — no colours, no widget
  styling, in the spirit of `modules/home`'s "not a ricing project".
- **Shipping a typeface with the framework.** Item 9 declares both
  family options and defaults them to the generic `monospace` and
  `sans-serif`; it adds no font package to `modules/desktop`, and the
  resident's Iosevka pair stays in their private layer. That question
  is open, not answered-in-the-negative — see
  `docs/backlog/shipping-a-default-typeface.md`.
- **Packaging the sweep harness for deployed systems.** Item 10 puts
  it in `tools/`; whether a resident should get it as a command on
  `$PATH` is a product question, flagged there and deliberately not
  settled here.
- **Changing `castle.display.scale`.** It is correct; see "The
  problem, measured".
- **Per-application font overrides** (a different font for the
  terminal than for the editor, etc.). Sizes only, one font family
  each for mono and sans.

## Implementation notes (corrections to the above, discovered while building it)

**Item 6's choice: (a).** `bars` is restated in `modules/home` with
home-manager's own default values (mode, hiddenState, position,
workspaceButtons, workspaceNumbers, statusCommand, trayOutput) and the
font swapped. A bar left at 8 pt while every surface around it grew
would have been a visibly half-finished job. The cost is the pin: if a
home-manager input bump changes its default bar entry, this block will
not follow. CI now asserts both the bar font *and* the presence of
`status_command`, which is the field that silently disappears if the
restatement is ever trimmed as "redundant".

**Deviation from scope items 1–2: framework defaults are declared as
`mkOption` `default`s, not as config-level `lib.mkDefault`.** The brief
said "change its default from `null` to `lib.mkDefault 12`", by analogy
with how `wallpaper` defaults itself. That analogy is wrong for these
options, and using it would have planted a trap:

- An `mkOption` `default` sits at priority 1500. A host's
  `lib.mkDefault` (1000) beats it, and a private layer's plain
  assignment (100) beats both. Clean three-layer resolution.
- A config-level `lib.mkDefault` also sits at 1000 — the *same*
  priority a host module uses. The moment any host set
  `terminalFontSize` with `lib.mkDefault`, that would be an
  ambiguous-priority conflict rather than an override.

`wallpaper` gets away with the config-level form because no host sets
it. Since `consoleFont` is explicitly designed to be host-supplied, and
nothing stops a host from wanting its own point sizes, `mkOption`
`default` is the correct layer here. Recorded rather than silently
done, per `CLAUDE.md`.

**`console.earlySetup` decision (item 3's open question): enabled,
conditionally.** It is set whenever `consoleFont` is non-null, in the
same `modules/desktop` block. Without it the font applies only after
stage 2, leaving the early-boot console — the part you read when
something has gone wrong — at the kernel's 8x16 default despite the
option being set. That is half the problem the option exists to solve.
The cost is a slightly larger initrd.

**`console.packages` is set unconditionally**, even when `consoleFont`
is `null`. Same reasoning as shipping `pkgs.bibata-cursors` for
`cursorTheme`: a host or private layer setting `consoleFont =
"spleen-32x64"` should not also have to know which package provides
that name. Spleen is a few hundred kilobytes.

**Item 9 gained a second option.** The brief specced `terminalFont`;
implementation added `uiFont` alongside it, because items 4–6 otherwise
had to hardcode a family name in three places. The two are documented
together, and the brief text above was updated to match rather than
left describing a single option.

**No `uiFontWeight` option.** The reference resident's chrome face is
`Iosevka Aile Medium` — a weight, not just a family. Sway wants a
single Pango description while home-manager's `gtk.font` takes family
and size separately; both accept the weight *inside* the family string,
so a separate weight option would only have to be reassembled into that
string. The weight rides in `uiFont`.

**What is verified, and what is not.** `nix flake check` passes; the
extended `example` assertion pins all three layers including the
asymmetry; the new CI steps were run locally against the real generated
configs before being committed (foot: `Example Mono:size=14` — the
example config's deliberate override; Sway: `font pango:sans-serif
11.000000` in *both* the top-level config and the bar block;
`console.font` resolving to `spleen-16x32` and that name really existing
inside `pkgs.spleen`). **Not** verified: nothing here has been deployed
to a real machine through these options — the reference resident is
still running the equivalent settings written directly against
home-manager, because their private layer pins the framework from
GitHub. The Verification section's reboot step remains outstanding, and
until it happens `earlySetup` in particular is untested in anger.
