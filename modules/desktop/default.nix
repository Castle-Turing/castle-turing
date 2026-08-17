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
    terminalFontSize = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = ''
        foot's font point size, wired into home-manager's
        `programs.foot.settings.main.font`. `null` means "framework
        default": foot's own built-in size applies.
      '';
    };
  };

  config = {
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
