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
{ config, pkgs, ... }:

{
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
