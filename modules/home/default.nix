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
    terminalFont = null;
    terminalFontSize = null;
    uiFont = null;
    uiFontSize = null;
    consoleFont = null;
    idleBlankSeconds = null;
    wallpaper = null;
  };

  # The UI font is consumed three times below (GTK, Sway chrome, the
  # bar) and every consumer wants both halves, so both being non-null is
  # the single condition for wiring any of them. Kept as one predicate
  # rather than repeated inline so the three cannot drift apart and
  # leave, say, a bar font set while titlebars are not.
  uiFontSet = displayCfg.uiFont != null && displayCfg.uiFontSize != null;

  # Sway wants a Pango description built from a family list plus a
  # size; the weight (if any) rides inside the family string. See
  # castle.display.uiFont's description in modules/desktop for why
  # there is no separate weight option.
  swayFonts = {
    names = [ displayCfg.uiFont ];
    # Sway's own config takes a float here; home-manager renders it as
    # `10.000000`, which is what the generated config carries.
    size = displayCfg.uiFontSize * 1.0;
  };

  # Same or-fallback idiom for the namespaces task 0020 added: every
  # key each namespace declares must be listed here, or a headless
  # host that skips the declaring module fails at eval instead of
  # getting the inert default. castle.input/castle.power live in
  # modules/desktop; castle.hardware lives in modules/base (see its
  # comment there for why), so its fallback only fires on a host
  # assembled without modules/base at all.
  inputCfg = config.castle.input or {
    touchpad = {
      naturalScroll = null;
      tapToClick = null;
    };
  };
  hardwareCfg = config.castle.hardware or {
    hasEthernet = true;
  };

  # Sway's input options take the words enabled/disabled, but a bool is
  # what these settings *are* — the castle.input options take a bool
  # and this module does the rendering, so a stranger cannot write
  # "true" and get a config Sway rejects at load (task 0020 item 5).
  swayBool = b: if b then "enabled" else "disabled";

  touchpadCfg = inputCfg.touchpad;
  touchpadConfigured = touchpadCfg.naturalScroll != null || touchpadCfg.tapToClick != null;

  # The control tool must match the daemon it drives: the same
  # wireplumber package services.pipewire runs, not a bare
  # pkgs.wireplumber a private layer's daemon override would silently
  # diverge from. The option path exists whether or not pipewire is
  # enabled (it is a stock nixpkgs module), and the reference is only
  # rendered inside the swayEnabled-gated block below.
  wpctl = "${config.services.pipewire.wireplumber.package}/bin/wpctl";

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

          # Sway makes the first workspace *mentioned* in the config its
          # initial workspace, and home-manager's own `keybindings`
          # attrset is emitted sorted by key name — so `Mod1+0`'s
          # `workspace number 10` binding was written before `Mod1+1`'s
          # `workspace number 1`, and every session opened on workspace
          # 10 (docs/tasks/0019, defect 1). `defaultWorkspace` fixes this
          # by hoisting the one binding whose *value* string-equals this
          # setting to the front of the bindsym block — it emits no
          # `workspace` command of its own, it only reorders.
          #
          # The match is exact string equality against the binding's
          # action, not a semantic comparison: it MUST be
          # "workspace number 1", verbatim. Any other spelling
          # ("workspace 1", a trailing space, ...) matches nothing,
          # hoists nothing, and silently reproduces the bug — there is
          # no error, because from the option's point of view an
          # unmatched value is indistinguishable from not setting it at
          # all. Resist "simplifying" this string.
          #
          # lib.mkDefault, not lib.mkOptionDefault: this is a framework
          # default a private layer should be able to override at normal
          # priority (same reasoning as modules/desktop's wallpaper
          # default, docs/tasks/0014) — not the definition-level-priority
          # trick the keybindings binding below needs. Demoting
          # keybindings to mkDefault would drop home-manager's entire
          # default set (see that comment below); do not harmonise the
          # two.
          defaultWorkspace = lib.mkDefault "workspace number 1";

          # Mod4+Shift+Return opens the ambient intake: a floating foot
          # terminal running castle-modal in compose mode
          # (docs/tasks/0009 item 3 — "press a key, describe a problem
          # in your own words, walk away"). `foot`/`castle-modal` are
          # resolved on $PATH rather than hardcoded store paths
          # deliberately, so this module stays decoupled from
          # modules/agent at the Nix level — the binding does nothing
          # useful without it, but building this module never requires
          # it.
          #
          # The chord is fixed rather than $mod-relative on purpose: this is the door
          # into the agent layer, not a window-management command, and
          # agent/README.md, docs/architecture.md and the desktop-loop
          # harness all name it literally, so one stable spelling is
          # worth more here than following a resident's modifier.
          #
          # Shift+Return specifically because it appears in NO stock
          # binding under ANY modifier value (home-manager sway.nix at
          # this flake's pin), so the chord displaces nothing whatever a
          # resident sets `modifier` to. That property is load-bearing.
          # The previous chord was Mod4+Shift+space, and the comment here
          # claimed it "deliberately overrides" Sway's stock floating
          # toggle as "a real trade, made once, on purpose". That was
          # false in both directions: under the default Mod1 modifier it
          # displaced nothing at all, because Mod4+Shift+space and
          # Mod1+Shift+space are different keys; and under
          # `modifier = "Mod4"` it DID displace `floating toggle`, but
          # nobody chose that — it happened silently, in a configuration
          # nobody was looking at (docs/tasks/0019, defect 2).
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
          # unions them by key with no conflict, since Shift+Return is not a
          # key any stock binding uses under any modifier.
          #
          # Two collision shapes exist here and they behave DIFFERENTLY;
          # the previous version of this parenthetical described only the
          # first and implied it covered both. (a) Two peer *module*
          # definitions of the same key do throw the ambiguous-priority
          # error — that risk is real and per-key. (b) A collision with
          # home-manager's OWN default does not throw: it is cross-level,
          # and it resolves silently in this module's favour. The
          # definition-level mkOptionDefault above is consumed by
          # filterOverrides at the definition level, leaving this value
          # bare at priority 100 per key, which beats home-manager's
          # per-value 1500 outright and drops it without a word. That is
          # exactly how the old Mod4+Shift+space chord ate `floating
          # toggle` under `modifier = "Mod4"` with no diagnostic of any
          # kind (docs/tasks/0019, defect 2). Do not read the module
          # system as a safety net here: for shape (b) it is silent.
          #
          # Confirmed by reading the generated config CI actually
          # produces: the full default set
          # (Mod1+Return, Mod1+Shift+q, Mod1+Shift+e, workspace bindings,
          # the `resize` mode) is present alongside this binding.
          keybindings = lib.mkOptionDefault {
            "Mod4+Shift+Return" = "exec foot --app-id=castle-modal -e castle-modal --mode compose";

            # Media and brightness keys (task 0020 item 1). Sway has no
            # built-in handling for these: an XF86 keysym does nothing
            # until something binds it.
            #
            # They land in this same attrset on purpose. A second,
            # unwrapped `keybindings` definition would sit at normal
            # priority and silently discard home-manager's entire
            # default set — the 0009 finding-1 lockout the long comment
            # above describes. XF86 keysyms collide with nothing
            # home-manager ships (its defaults are all Mod-prefixed
            # chords), so the per-key merge is a clean union.
            #
            # Absolute store paths, NOT bare names on $PATH — a
            # deliberate difference from the castle-modal binding above,
            # which stays bare to keep this module decoupled from
            # modules/agent at the Nix level. No such decoupling applies
            # here, and a media key that silently does nothing because a
            # binary is missing from $PATH is exactly the "option
            # pointing at nothing" failure 0014 item 5 exists to avoid.
            "XF86MonBrightnessUp" = "exec ${pkgs.brightnessctl}/bin/brightnessctl set 5%+";
            "XF86MonBrightnessDown" = "exec ${pkgs.brightnessctl}/bin/brightnessctl set 5%-";

            # wpctl comes from the *configured* wireplumber package
            # rather than a bare pkgs.wireplumber, so a private layer
            # overriding the daemon does not end up driving it with a
            # mismatched control tool.
            #
            # `-l 1.0` caps the ceiling: without it a held volume-up key
            # pushes the sink into software boost, which distorts rather
            # than getting louder.
            "XF86AudioRaiseVolume" = "exec ${wpctl} set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+";
            "XF86AudioLowerVolume" = "exec ${wpctl} set-volume @DEFAULT_AUDIO_SINK@ 5%-";
            "XF86AudioMute" = "exec ${wpctl} set-mute @DEFAULT_AUDIO_SINK@ toggle";
            "XF86AudioMicMute" = "exec ${wpctl} set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
          };

          # Touchpad. Emitted only when the private layer actually asked
          # for something: both options default to null (pure taste, held
          # strongly in both directions — see their descriptions in
          # modules/desktop), and an empty `input` stanza would be noise
          # in the generated config.
          #
          # `type:touchpad` rather than a device identifier, so this
          # survives a hardware change without anyone reading
          # `swaymsg -t get_inputs`.
          input = lib.optionalAttrs touchpadConfigured {
            "type:touchpad" =
              (lib.optionalAttrs (touchpadCfg.naturalScroll != null) {
                natural_scroll = swayBool touchpadCfg.naturalScroll;
              })
              // (lib.optionalAttrs (touchpadCfg.tapToClick != null) {
                tap = swayBool touchpadCfg.tapToClick;
              });
          };

          # Window titles *and* swaynag — one setting in Sway, not two
          # (home-manager's own description for this option reads "Font
          # configuration for window titles, nagbar..."). That is why
          # docs/tasks/0017 could calibrate this value using swaynag
          # bars: they render the very setting being measured.
          #
          # The bar is NOT covered by this and needs `bars` below.
          fonts = lib.mkIf uiFontSet swayFonts;

          # swaybar carries its own font, so the setting above does not
          # reach it. This is the trap: `bars` is a listOf submodule
          # whose *option default* is a fully-spelled-out single-element
          # list (mode, hiddenState, position, workspaceButtons,
          # workspaceNumbers, statusCommand = i3status, colors,
          # trayOutput, fonts), while barModule's own per-option
          # defaults are null for stateVersion >= 20.09. Defining `bars`
          # at all therefore REPLACES that list rather than merging into
          # it, and every field not restated comes back null — silently
          # taking the status line with it.
          #
          # docs/tasks/0017 item 6 posed this as (a) restate the default
          # entry with the font swapped, pinning those values, or (b)
          # leave the bar at 8pt and file it. (a) was chosen: a bar
          # stuck at 8pt while every other surface grows is a visibly
          # half-finished job. The pin is the cost — if a home-manager
          # input bump changes its default bar, this block will not
          # follow, and CI's sway-config-check prints the generated
          # config so the difference is at least visible.
          bars = lib.mkIf uiFontSet [
            {
              fonts = swayFonts;
              # Restated from home-manager's own default bar entry. Do
              # not trim these as "redundant": each one is null without
              # this line, not inherited.
              mode = "dock";
              hiddenState = "hide";
              position = "bottom";
              workspaceButtons = true;
              workspaceNumbers = true;
              statusCommand = "${pkgs.i3status}/bin/i3status";
              trayOutput = "primary";
            }
          ];

          # The modal is a small, centered dialog, not a tiled pane —
          # this is the one window this config gives special treatment.
          window.commands = [
            {
              criteria.app_id = "castle-modal";
              command = "floating enable, resize set 720 480, move position center";
            }
          ];

          # castle.display.scale and castle.display.wallpaper
          # (modules/desktop) both land on the same output stanza, so
          # they're merged into one attrset rather than two separate
          # `optionalAttrs "*" = {...}` calls — two definitions of the
          # same key ("*") in one attribute set is a genuine collision
          # in Nix (the second would silently replace the first, not
          # merge with it), not something `//` or two list entries
          # would catch. Each half is still omitted independently when
          # its option is null, so a host that sets neither gets no
          # `output "*" {...}` block at all, same as before this option
          # existed.
          output = lib.optionalAttrs (displayCfg.scale != null || displayCfg.wallpaper != null) {
            "*" =
              (lib.optionalAttrs (displayCfg.scale != null) {
                scale = toString displayCfg.scale;
              })
              // (lib.optionalAttrs (displayCfg.wallpaper != null) {
                # "fill": scale-and-crop to cover the whole output,
                # cropping any overflow, rather than letterboxing
                # (swaybg's other modes: stretch, fit, center, tile).
                # The usual desktop-wallpaper default, and the shipped
                # image (3840x2160, modules/desktop/wallpapers) is
                # large enough that fill never has to upscale on any
                # output this framework currently targets (hosts/xps9370
                # is exactly that resolution).
                bg = "${displayCfg.wallpaper} fill";
              });
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
        # castle.display.terminalFont and .terminalFontSize compose into
        # foot's single `font` string as `<font>:size=<n>`. The family
        # half may itself be a full fontconfig pattern carrying a style
        # (`Iosevka Slab:style=Light Extended`), which is why it is
        # interpolated verbatim rather than quoted or escaped — foot
        # hands the whole string to fontconfig.
        #
        # Both halves must be non-null: a size with no family, or a
        # family with no size, would produce a malformed pattern. Either
        # being null means "don't manage foot's font at all", leaving
        # foot's own default in place.
        settings = lib.optionalAttrs
          (displayCfg.terminalFont != null && displayCfg.terminalFontSize != null)
          {
            main.font = "${displayCfg.terminalFont}:size=${toString displayCfg.terminalFontSize}";
          };
      };

      # GTK applications — which on a stock desktop means Firefox's
      # chrome, its file picker, and the xdg-desktop-portal-gtk dialogs.
      # Enabling home-manager's gtk module writes gtk-3.0/settings.ini,
      # gtk-4.0/settings.ini and the matching dconf keys; deliberately
      # only the font is set here. Themes and icon themes are a
      # different decision with a much larger surface — resist growing
      # this, in the same spirit as the Sway block's own comment.
      #
      # No `package`: the framework's default family is generic
      # (`sans-serif`, resolved by fontconfig from fonts.packages), and
      # a resident naming a real face supplies its package in the same
      # private layer that names it.
      # `enable` is gated only on the session existing, NOT on the font
      # options being set. Enabling home-manager's gtk module is what
      # writes gtk-3.0/settings.ini at all — and `home.pointerCursor`
      # below feeds gtk-cursor-theme-name/-size into that same file.
      # Gating `enable` on uiFontSet therefore coupled two unrelated
      # things: a resident taking castle.display.uiFont's documented
      # `null` opt-out silently lost their GTK *cursor* configuration
      # too, leaving GTK apps on the XCURSOR_* env-var fallback. Only
      # the font itself is conditional.
      gtk = lib.mkIf swayEnabled {
        enable = true;
        font = lib.mkIf uiFontSet {
          name = displayCfg.uiFont;
          size = displayCfg.uiFontSize;
        };
      };

      # The status bar's contents (task 0020 item 3). modules/home
      # already names i3status as the bar's statusCommand but never
      # configured it, so every desktop got i3status's compiled-in
      # defaults — which report two non-faults as faults: `ethernet
      # _first_` renders a permanent red error on a chassis with no
      # wired port, and `ipv6` renders red whenever the network has no
      # IPv6. A status surface that cries wolf about non-faults is the
      # wrong foundation for the "status bar turning amber"
      # intervention channel docs/vision.md names: the bar's idle state
      # has to be quiet before colour can mean anything.
      #
      # This writes the user-level config file, which i3status reads
      # ($XDG_CONFIG_HOME/i3status/config) before its compiled-in
      # fallback — so the `bars` block above is left completely alone.
      #
      # ipv6 is dropped unconditionally, ethernet only when the chassis
      # says it has no port. That asymmetry is the point: IPv6 presence
      # is a property of the *network environment*, false-alarming on
      # every host, so it is a framework-level fix; a missing ethernet
      # port is a hardware fact only a host module can state, and a
      # desktop with an unplugged cable SHOULD show that fault.
      # Encoding "no ethernet" in modules/ would be exactly the
      # hardware assumption CLAUDE.md forbids.
      programs.i3status = lib.mkIf swayEnabled {
        enable = true;
        enableDefault = true;
        modules = {
          "ipv6".enable = false;
          "ethernet _first_".enable = hardwareCfg.hasEthernet;
        };
      };

      # Idle blanking (task 0020 item 4). Mechanism only: this runs at
      # all only when the private layer sets a number, and there is no
      # framework or host default — castle.display.idleBlankSeconds is
      # null everywhere by design.
      #
      # Do NOT "finish" this by adding a sensible-looking default
      # timeout, and do not add a lock. Idle policy belongs to the
      # attention-management work docs/vision.md describes (deep-focus
      # mode, graduated interventions), which would have to renegotiate
      # any policy written here first. See task 0020's non-goals.
      services.swayidle = lib.mkIf (swayEnabled && displayCfg.idleBlankSeconds != null) {
        enable = true;
        timeouts = [
          {
            timeout = displayCfg.idleBlankSeconds;
            command = "${config.programs.sway.package}/bin/swaymsg 'output * power off'";
            resumeCommand = "${config.programs.sway.package}/bin/swaymsg 'output * power on'";
          }
        ];
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
