# modules/home — home-manager wired in as a NixOS module: the resident's
# per-user environment (dotfile-equivalent config), as opposed to
# modules/base's system-wide state.
#
# Mechanism only. This module is consumed through flake.nix's
# `nixosModules.home` export, which binds this flake's home-manager
# input so consumers need not add it themselves — same pattern as
# `nixosModules.host-xps9370` binding nixos-hardware and disko.
#
# The one thing this module currently configures — git's commit
# identity — is a direct instance of Principle 01: home-manager's
# `programs.git` needs a name and email to be useful, and both are
# personal data (CLAUDE.md's hard rule, Principle 01). They are never
# defaulted or invented here; a private layer that leaves them unset
# fails this module's assertions instead of silently committing as
# nobody or as a name we made up.
{ config, lib, pkgs, ... }:

let
  cfg = config.castle.person;
  adminCfg = config.castle.admin;

  # castle.display is declared in modules/desktop (docs/tasks/0009 item
  # 1). `or` here — rather than a bare `config.castle.display` — is the
  # standard nixpkgs idiom for "read an option that may not exist
  # because the module that declares it might not be imported": since
  # module non-existence means the attribute path is genuinely absent
  # from the merged config (not a thrown value), `or` catches it safely
  # without forcing anything. That is what keeps this module importable
  # on a host that skips modules/desktop entirely.
  displayCfg = config.castle.display or {
    scale = null;
    cursorTheme = null;
    cursorSize = null;
    terminalFontSize = null;
  };

  # `programs.sway.enable` is a plain NixOS option (from nixpkgs' own
  # Sway module, not one this repo defines) that only modules/desktop
  # ever turns on. Gating every Sway/display block below on it is what
  # "guarded so it's inert if the desktop module isn't imported" means
  # concretely (docs/tasks/0009 item 2) — a headless host that imports
  # modules/home for git identity alone gets none of this.
  swayEnabled = config.programs.sway.enable or false;
in
{
  options.castle.person = {
    gitUserName = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Git commit author name, wired into home-manager's
        `programs.git.settings.user.name`. Personal data — supplied by
        the private layer, never this repo. See docs/private-layer.md.
      '';
    };
    gitUserEmail = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Git commit author email, wired into home-manager's
        `programs.git.settings.user.email`. Personal data — supplied by
        the private layer, never this repo. See docs/private-layer.md.
      '';
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.gitUserName != "";
        message = ''
          castle.person.gitUserName is unset. modules/home wires this
          into home-manager's git config, so a resident's private layer
          must supply it — see docs/private-layer.md. (This is exactly
          the personal data CLAUDE.md forbids defaulting or inventing:
          it must come from the private layer, not from this module.)
        '';
      }
      {
        assertion = cfg.gitUserEmail != "";
        message = ''
          castle.person.gitUserEmail is unset — see docs/private-layer.md.
        '';
      }
    ];

    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    # The private layer names the admin (castle.admin.username,
    # modules/base); the same person is who home-manager is managing a
    # home for, so this module reads that option rather than defining
    # its own username slot.
    home-manager.users.${adminCfg.username} = {
      # Pinned once, like system.stateVersion in hosts/<name> — not
      # bumped casually after first deploy. See home-manager's own
      # release.json for what the current framework nixpkgs pin expects.
      home.stateVersion = "26.11";

      programs.git = {
        enable = true;
        # `userName`/`userEmail` are renamed as of this flake's pinned
        # home-manager; use the current option path so this doesn't
        # start life already deprecated.
        settings.user = {
          name = cfg.gitUserName;
          email = cfg.gitUserEmail;
        };
      };

      # The first Sway configuration this repo owns (docs/tasks/0009
      # item 2) — before this, a desktop host ran whatever stock config
      # ships with the sway package. Kept deliberately minimal: the
      # ambient-intake keybinding, the modal's window rules, and the
      # castle.display settings from modules/desktop. This is a
      # foothold for a future, more deliberate desktop config, not a
      # ricing project — resist the urge to grow it here.
      wayland.windowManager.sway = lib.mkIf swayEnabled {
        enable = true;
        wrapperFeatures.gtk = true;
        config = {
          # mako (installed by modules/desktop) is the notification
          # daemon that renders the router's `notify` channel on
          # screen (docs/tasks/0009 item 5); it has to actually be
          # running for notify-send to have anywhere to deliver to.
          startup = [ { command = "mako"; } ];

          # $mod+Shift+space opens the ambient intake: a floating foot
          # terminal running castle-modal in compose mode
          # (docs/tasks/0009 item 3 — "press a key, describe a problem
          # in your own words, walk away"). `foot`/`castle-modal` are
          # resolved on $PATH rather than hardcoded store paths
          # deliberately, so this module stays decoupled from
          # modules/agent at the Nix level — the binding does nothing
          # useful without it, but building this module never requires
          # it. Mod4 (the Super/Windows key) is Sway's own stock
          # modifier; this chord deliberately overrides Sway/i3's stock
          # "toggle floating on the focused window" default on
          # mod+shift+space — a real trade, made once, on purpose (the
          # pre-made decision behind docs/tasks/0009-ambient-intake.md).
          # `swaymsg floating toggle` still reaches the same action by
          # hand if it's ever missed.
          #
          # MUST be wrapped in lib.mkOptionDefault — the previous version
          # of this comment claimed the opposite and was wrong (0009
          # review pass, finding 1). Confirmed against home-manager's
          # actual module source (modules/services/window-managers/i3-sway/
          # sway.nix, this flake's pinned rev) and nixpkgs's module-system
          # source (lib/modules.nix, same pin) rather than assumed:
          #
          # home-manager declares its ~50 default bindings as this
          # option's `default`, each value individually wrapped in
          # `lib.mkOptionDefault` (priority 1500). `default` is not a
          # pure fallback used only when nothing else sets the option —
          # nixpkgs's evalOptionValue splices it into the option's
          # definitions list unconditionally, at priority 1500, next to
          # whatever every other module contributes. Before an attrsOf
          # option's definitions ever reach its per-key merge, though,
          # mergeDefinitions runs filterOverrides' across the *whole*
          # option value: it keeps only the definitions at the single
          # lowest priority number present and drops every other
          # definition entirely, no matter its keys.
          #
          # A plain, unwrapped `keybindings = { ... }` here sits at the
          # default priority (100) — strictly lower-numbered than home-
          # manager's spliced-in default (1500) — so filterOverrides'
          # discarded home-manager's *entire* default-bindings
          # definition before attrsOf's per-key merge ever ran, leaving
          # only this module's one binding. That is the lockout CI
          # actually generated and finding 1 caught. Wrapping this value
          # in `lib.mkOptionDefault` puts it at the same priority (1500)
          # as home-manager's defaults, so both definitions survive
          # filterOverrides' and reach attrsOf's per-key merge — which
          # unions them by key with no conflict, since this chord shares
          # no key with any Mod1-prefixed default. (Two same-priority
          # definitions of the *same* key would still throw the
          # ambiguous-priority error the old comment warned about — that
          # risk is real, just per-key, not a reason to avoid
          # mkOptionDefault altogether.) Confirmed by reading the
          # generated config CI actually produces: the full default set
          # (Mod1+Return, Mod1+Shift+q, Mod1+Shift+e, workspace bindings,
          # the `resize` mode) is present alongside this binding.
          keybindings = lib.mkOptionDefault {
            "Mod4+Shift+space" = "exec foot --app-id=castle-modal -e castle-modal --mode compose";
          };

          # The modal is a small, centered dialog, not a tiled pane —
          # this is the one window this config gives special treatment.
          window.commands = [
            {
              criteria.app_id = "castle-modal";
              command = "floating enable, resize set 720 480, move position center";
            }
          ];

          # castle.display.scale (modules/desktop) — see that option's
          # description for the three-layer resolution story. Omitted
          # entirely (rather than set to some placeholder) when null,
          # so Sway's own output auto-detection applies untouched.
          output = lib.optionalAttrs (displayCfg.scale != null) {
            "*".scale = toString displayCfg.scale;
          };
        };
      };

      # foot's font size is the one castle.display setting that isn't a
      # Sway-config concern — home-manager owns foot's config file
      # directly. Guarded the same way as the Sway block above: no
      # desktop, no managed foot config, and modules/desktop's own
      # `pkgs.foot` systemPackage still provides a usable, unmanaged
      # binary either way.
      programs.foot = lib.mkIf swayEnabled {
        enable = true;
        settings = lib.optionalAttrs (displayCfg.terminalFontSize != null) {
          main.font = "monospace:size=${toString displayCfg.terminalFontSize}";
        };
      };

      # home.pointerCursor is the one option that covers Sway's own
      # seat, GTK, and XWayland coherently (docs/tasks/0009 item 1) —
      # see castle.display.cursorTheme's description in modules/desktop
      # for why. Left entirely unset when cursorTheme is null so the
      # cursor theme package's (or GTK's) own default applies.
      home.pointerCursor = lib.mkIf (swayEnabled && displayCfg.cursorTheme != null) {
        name = displayCfg.cursorTheme;
        package = pkgs.bibata-cursors;
        size = if displayCfg.cursorSize != null then displayCfg.cursorSize else 24;
        # All three backends, explicitly, because a Wayland pointer is
        # drawn by whoever owns the surface and there is no single knob
        # that covers them: gtk writes the gsettings/ini keys GTK apps
        # read, x11 writes the XCURSOR_* session variables XWayland
        # clients read, and sway emits `seat * xcursor_theme <name>
        # <size>` — the compositor's *own* pointer, the one over the
        # desktop and Wayland-native surfaces. Omitting the last one is
        # a silent half-fix: GTK and XWayland windows get the requested
        # size while the pointer you see most of the time stays at the
        # default, which is exactly the symptom this option exists to
        # cure (docs/tasks/0008's cursor errand). CI's sway-config-check
        # job prints the generated config, so the `seat` block landing
        # is visible evidence rather than an assumption.
        enable = true;
        gtk.enable = true;
        x11.enable = true;
        sway.enable = true;
      };
    };
  };
}
