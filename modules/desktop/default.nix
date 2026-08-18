# modules/desktop — the graphical session.
#
# Sway (a tiling Wayland compositor) is this project's display surface
# — see docs/vision.md ("a tiling window manager driven over IPC is its
# display surface... the window manager is the agent's hands"). Its IPC
# socket ($SWAYSOCK, exposed to every process in the session, queryable
# and drivable with `swaymsg` or the same protocol directly) is exactly
# that mechanism: the concrete answer to "how does the agent layer talk
# to the window manager." Sway starts with it enabled unconditionally —
# there is no config option to turn it off — and nothing here restricts
# it; that default is load-bearing, not incidental.
#
# Also configured here: foot (terminal emulator), fonts, XDG desktop
# portals (the screen-share/file-picker plumbing GUI apps expect on
# Wayland), PipeWire audio, Firefox, and greetd+tuigreet for login.
#
# Deliberately **no auto-login**. Every host that imports this module is
# assumed to have an unencrypted disk (true of hosts/xps9370 today), so
# a login prompt is the only thing between a lost or stolen machine and
# its contents — see CLAUDE.md and docs/tasks/0005-dogfooding-desktop.md.
# That login prompt is useless without a working password, which is
# exactly the first-boot lockout docs/tasks/0003-findings.md (finding
# #1) hit: no config layer supplied one, so console login was
# impossible on a Wi-Fi-only machine that also couldn't be reached over
# SSH yet. The assertion below closes that loop — see
# castle.admin.initialHashedPassword in modules/base.
{ config, lib, pkgs, ... }:

let
  # Packaged as a derivation, not referenced as a source path at
  # runtime, for the same reason agent/default.nix's castleCli is: a
  # bare `./wallpapers/castle-turing.jpg` interpolated straight into
  # generated config text still lands in the store (Nix copies any
  # local path it interpolates), but wrapping it in a derivation gives
  # the option a stable `$out/share/backgrounds/...` path to resolve
  # to and a place to hang provenance (`meta.description`) — the same
  # "something real to point at" role pkgs.bibata-cursors plays for
  # castle.display.cursorTheme below. See
  # modules/desktop/wallpapers/README.md for what the artwork is and
  # why it's one JPEG rather than seven PNGs or an AVIF.
  wallpaperPackage = pkgs.stdenvNoCC.mkDerivation {
    pname = "castle-turing-wallpaper";
    version = "1.0.0";
    src = ./wallpapers;
    dontBuild = true;
    installPhase = ''
      install -Dm444 castle-turing.jpg $out/share/backgrounds/castle-turing.jpg
    '';
    meta.description = "Default Castle Turing desktop wallpaper";
  };
in

{
  options.castle.display = {
    scale = lib.mkOption {
      type = lib.types.nullOr lib.types.float;
      default = null;
      description = ''
        Sway output scale (a float — `2.0` doubles logical pixel
        density). `null` means "framework default": no output scale is
        set at all, and Sway's own auto-detection applies. Three layers
        can supply a value, in ascending priority: this module's `null`
        default; a host module (`hosts/<name>/default.nix`) supplying a
        hardware-derived value with `lib.mkDefault`, since a panel's
        physical DPI is a machine fact, not personal data
        (Principle 01 consequence 2) — see hosts/xps9370 for a worked
        example; and the private layer, which may override outright for
        taste. Consumed by modules/home's `wayland.windowManager.sway`
        (docs/tasks/0009-ambient-intake.md item 1).
      '';
    };
    cursorTheme = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Name of an X cursor theme (e.g. `"Bibata-Modern-Classic"`),
        wired into home-manager's `home.pointerCursor.name` — one
        option that covers Sway's own seat, GTK, and XWayland
        coherently, since all three read the same `XCURSOR_THEME`/
        `XCURSOR_SIZE` session variables that option sets. `null` means
        "framework default": home.pointerCursor is left unset, so
        whatever the cursor theme package (or GTK) defaults to applies.
        modules/desktop ships `pkgs.bibata-cursors` so this option has
        something real to point at — set it to one of that package's
        theme names (e.g. `Bibata-Modern-Classic`,
        `Bibata-Modern-Ice`) unless a private layer supplies its own
        cursor theme package too.
      '';
    };
    cursorSize = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = ''
        Cursor size in **pre-scale** pixels, wired into
        `home.pointerCursor.size`. `null` means "framework default"
        (currently 24, home-manager's own default, applied only when
        `cursorTheme` is also set — an unset theme leaves the whole
        pointer-cursor slot alone). Pre-scale, not "unscaled": Sway
        itself multiplies this value by the output scale when it emits
        `seat * xcursor_theme <name> <size>`, the same way a font point
        size gets multiplied — this option is an input to that
        multiplication, not a value already compensated for it. Setting
        it larger to counter a HiDPI panel double-compensates on top of
        `scale` (docs/tasks/0013-first-deploy-findings.md, bug 1: 48
        alongside `scale = 2.0` rendered at roughly 96 physical pixels,
        confirmed on a real deploy as dramatically, unusably oversized);
        see hosts/xps9370 for a worked, eye-calibrated example of
        picking a correct pre-scale value instead.

        Separately, real problem: XWayland and some GTK cursor
        rendering paths do not reliably follow Sway's own output scale
        for the pointer glyph itself, so those clients specifically can
        still show a native-resolution, comparatively tiny cursor even
        with this value correct for Sway's own seat. This option does
        not solve that gap — it only controls what Sway itself (and,
        via the same `XCURSOR_SIZE` variable, GTK/X11 clients that *do*
        follow it) renders — and treating a bigger number here as the
        fix for it is exactly the reasoning that produced the bug
        above. The gap is real but unsolved; it needs its own
        investigation, not a larger value on this option.
      '';
    };
    terminalFont = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "monospace";
      description = ''
        Terminal typeface: a fontconfig family (or full pattern, e.g.
        `"Iosevka Slab:style=Light Extended"`), composed with
        `terminalFontSize` into home-manager's
        `programs.foot.settings.main.font` as `<font>:size=<n>`.

        The default is the *generic* family `monospace` rather than a
        specific face, deliberately. A fontconfig family name only
        means something if a package providing it is installed; naming
        a real face here would make the framework's default silently
        fall back to something else on any machine that lacks it,
        which is a confusing failure to debug. `monospace` always
        resolves — on a stock Castle Turing desktop, to DejaVu Sans
        Mono from this module's own `fonts.packages`, at no added
        closure cost.

        This option exists so the framework does **not** have to decide
        what typeface a Castle Turing looks like. A resident who wants
        a real face sets it here from their private layer, and supplies
        the font package alongside it. Whether the framework should
        ever ship an opinionated typeface of its own is deliberately
        open — see `docs/backlog/shipping-a-default-typeface.md`; don't
        settle it by quietly adding a font package to this module.
      '';
    };
    terminalFontSize = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = 12;
      description = ''
        foot's font point size, composed with `terminalFont` into
        home-manager's `programs.foot.settings.main.font`.

        Unlike `scale` or `cursorTheme`, this does **not** default to
        `null`/"leave it alone": foot's own built-in default is 8 pt,
        which is too small to read on any modern panel and is what
        made a fresh desktop unusable for development
        (`docs/tasks/0017-legible-defaults.md`). "A fresh desktop is
        legible" is a framework property, not resident taste — the
        same argument that makes `wallpaper` the other option this
        module has an opinion about.

        12 was calibrated by eye on a 331 PPI panel at `scale = 2.0`,
        by opening candidate sizes side by side rather than deriving a
        number from DPI — see that brief's "How the sizes and the
        typeface were picked", and `tools/font-sweep.sh` to re-run the
        comparison rather than editing this digit on a hunch. Point
        sizes are density-independent because `scale` already
        normalizes density, so this one number is right on every host;
        that is exactly why it lives here and `consoleFont` does not.

        `null` is still accepted and now means "set no font at all,
        leave foot to its own default" — an explicit opt-out rather
        than the absence of an opinion.
      '';
    };
    uiFont = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "sans-serif";
      description = ''
        Typeface for UI chrome — GTK applications (including Firefox's
        chrome and file pickers), Sway window titles, swaynag, and the
        bar. A family name, optionally carrying a weight
        (`"Iosevka Aile Medium"`).

        The weight rides *inside the family string* rather than in a
        separate option, because the two consumers disagree about
        units: home-manager's `gtk.font` takes family and size as
        separate fields, while Sway wants a single Pango description.
        Both accept a weight word inside the name, so a `uiFontWeight`
        option would only have to be reassembled into this string.

        Generic default, for the same reason as `terminalFont` — see
        that option. `sans-serif` resolves to DejaVu Sans on a stock
        desktop.
      '';
    };
    uiFontSize = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = 11;
      description = ''
        Point size for everything `uiFont` covers. Framework default
        11, calibrated the same way `terminalFontSize` was.

        Note that a size is only right *paired with a weight*: the
        reference resident runs 10, because `Iosevka Aile Medium`'s
        heavier stems buy back what the smaller size costs. Against
        this module's own lighter default sans, 10 reads thin — which
        is why the framework keeps 11 and the resident's 10 lives in
        their private layer next to the face it belongs with. If you
        change one, re-check the other by looking.

        `null` means "set no UI font at all", leaving GTK and Sway to
        their own defaults.
      '';
    };
    consoleFont = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Font for the virtual console — the boot log, the tuigreet
        greeter, and the emergency shell. A `console.font` value: the
        name of a PSF bitmap font available in `console.packages`
        (this module ships `pkgs.spleen`, so its `spleen-16x32`,
        `spleen-32x64` and siblings resolve out of the box).

        **This is the one `castle.display` font setting that is not
        density-independent, and the reason it defaults to `null`
        here while the point sizes above have framework defaults.**
        The console never sees `castle.display.scale`: it is a raw
        pixel grid, so a font that is correct on a 331 PPI panel is
        absurd on a 1080p one. That is the same argument that puts
        `scale` and `cursorSize` in `hosts/<name>/` rather than this
        module — so a host module supplies this value
        (`hosts/xps9370` sets `spleen-16x32` with `lib.mkDefault`),
        and the framework declares the slot without filling it.

        Do not "fix" this into a framework default for consistency
        with its three siblings. The asymmetry is the design.

        Setting this also turns on `console.earlySetup`, so the font
        applies from the initrd rather than only after stage 2 —
        an unreadable early-boot console is half of what this option
        exists to fix. `null` leaves both alone, and the kernel's
        built-in 8x16 font applies.
      '';
    };
    wallpaper = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Path to an image file, wired into home-manager's
        `wayland.windowManager.sway.config.output."*".bg` (Sway's own
        `bg <path> <mode>` directive, scaled with `fill` — see
        modules/home's comment on that binding for why). `null` at
        *this* layer means "no wallpaper set, whatever the compositor
        does" — the same declared-default convention as
        `cursorTheme` above.

        Unlike `cursorTheme`, though, this option does not stay null in
        practice: this module's own `config` (not a host module) sets
        it via `lib.mkDefault` to the framework's shipped image: this
        module's own `wallpaperPackage` derivation, built from
        `modules/desktop/wallpapers/castle-turing.jpg` — see that
        directory's README for what it is and why it's the one
        non-text asset in this repo. That is a deliberate difference
        from `scale`/`cursorTheme`'s three layers, where the middle
        layer is a *host* module supplying a hardware- or
        machine-specific value: a wallpaper is neither, it is a
        framework-owned asset with exactly one canonical default, so
        the framework module itself is the right place to default it
        on. The three layers that remain are: this option's own `null`
        declaration (irrelevant once modules/desktop is imported, since
        the layer below always fires); modules/desktop's `mkDefault` of
        the shipped image (what a fresh desktop actually gets); and the
        private layer, which may set a different path outright, or set
        `null` explicitly to turn wallpaper off entirely — both at
        normal priority, both beating `mkDefault`.
      '';
    };
  };

  config = {
    # The one non-`mkOption`-default value this module sets for itself
    # rather than leaving to a host or the private layer — see
    # `wallpaper`'s description above for why. `mkDefault` (not a plain
    # assignment) so a private layer's own choice, or an explicit
    # `null` to turn wallpaper off, still wins at normal priority.
    castle.display.wallpaper = lib.mkDefault "${wallpaperPackage}/share/backgrounds/castle-turing.jpg";

    assertions = [
      {
        assertion = config.castle.admin.initialHashedPassword != null;
        message = ''
          modules/desktop requires castle.admin.initialHashedPassword to
          be set: this module deliberately configures no auto-login (see
          the module's header comment), so a login prompt with no
          password behind it is the exact console lockout
          docs/tasks/0003-findings.md finding #1 describes. Generate a
          hash with `mkpasswd -m sha-512`; it belongs in the private
          layer, never this repo — see docs/private-layer.md.
        '';
      }
    ];

    # The virtual console. Unlike every other castle.display setting,
    # this one is a NixOS-level option rather than something modules/home
    # wires into a user's session: the console exists before any user
    # logs in, which is exactly when it matters most (boot log, greeter,
    # emergency shell).
    #
    # `console.packages` is set unconditionally, even when consoleFont is
    # null, for the same reason this module ships pkgs.bibata-cursors for
    # cursorTheme: an option that names a font is useless unless
    # something provides that name, and a host or private layer setting
    # `consoleFont = "spleen-32x64"` should not also have to know which
    # package to add. Spleen is a few hundred kilobytes.
    console = {
      packages = [ pkgs.spleen ];
    } // lib.optionalAttrs (config.castle.display.consoleFont != null) {
      # lib.mkDefault on both, not bare assignments. These are opinions
      # this module holds, exactly like the wallpaper default above, and
      # a resident must be able to override an opinion at normal
      # priority rather than reaching for lib.mkForce. Without it,
      # `console.earlySetup = false;` in a private layer is not an
      # override but a conflict: "The option 'console.earlySetup' has
      # conflicting definition values". The larger initrd this costs is
      # named below as a cost, which makes declining it a legitimate
      # thing for a resident to want.
      font = lib.mkDefault config.castle.display.consoleFont;
      # Apply the font from the initrd rather than after stage 2.
      # Without this the early-boot console — the part you read when
      # something has gone wrong — keeps the kernel's 8x16 default even
      # though the option is set, which is half the problem this option
      # exists to solve. Costs a slightly larger initrd.
      earlySetup = lib.mkDefault true;
    };

    programs.sway = {
      enable = true;
      wrapperFeatures.gtk = true;
    };

    environment.systemPackages = [
      pkgs.foot
      pkgs.firefox
      # The router's real interruption channel (docs/tasks/0009 item 5):
      # mako is the notification daemon that actually renders a
      # notify-send call on screen, and libnotify is what provides the
      # notify-send binary itself. modules/agent's
      # castle.agent.notify.command defaults to plain `notify-send` on
      # $PATH, which is what installing it here makes real; a private
      # layer or CI stub can still override the command entirely.
      pkgs.mako
      pkgs.libnotify
      # Gives castle.display.cursorTheme something real to name — see
      # that option's description above.
      pkgs.bibata-cursors
      # Gives castle.display.wallpaper something real to point at, and
      # makes the artwork independently discoverable at a stable path
      # (/run/current-system/sw/share/backgrounds/castle-turing.jpg)
      # rather than only reachable through the option's resolved
      # value. See that option's description above.
      wallpaperPackage
    ];

    fonts.packages = with pkgs; [
      dejavu_fonts
      liberation_ttf
      noto-fonts
      noto-fonts-color-emoji
    ];

    xdg.portal = {
      enable = true;
      wlr.enable = true;
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    };

    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd sway";
          user = "greeter";
        };
        # No `initial_session` — that is precisely what auto-login would
        # set, and this module deliberately does not. See header comment.
      };
    };
  };
}
