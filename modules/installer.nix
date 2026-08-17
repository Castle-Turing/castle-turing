# modules/installer.nix — the agentic installer image (docs/tasks/0006).
#
# Mechanism only, per Principle 01. This module turns the stock NixOS
# installer media into a Castle Turing artifact: bootable, and
# immediately SSH-reachable with zero console interaction whenever a
# network is already reachable (Ethernet, auto-DHCP). It does this by
# composing two things that already exist rather than inventing a
# parallel identity mechanism:
#
#   - nixpkgs's own minimal installer profile (the live environment
#     itself: kernel, squashfs, boot menu, NetworkManager);
#   - modules/base, which already turns castle.admin.sshKeys into a
#     hardened, key-only sshd and an authorized root account.
#
# The private layer supplies exactly the same castle.admin values it
# already supplies for the installed system (docs/private-layer.md) —
# one key, declared once, reused here unchanged. That is what "the key
# comes from the private layer, exactly as castle.admin does today"
# (docs/tasks/0006-installer-image.md) means in practice: no new
# private-layer file or format, just a second nixosConfiguration in the
# private flake that imports this module instead of (or alongside) a
# host module. See docs/private-layer.md for the worked example.
#
# This closes docs/tasks/0003-findings.md finding #3 (installer
# ephemerality): no more per-boot nmtui-then-curl-a-key-from-GitHub
# ceremony. Finding #1 (first-boot lockout) is closed by the *installed*
# system being SSH-reachable, which this module doesn't touch — see
# modules/base and hosts/xps9370/README.md.
{
  modulesPath,
  lib,
  pkgs,
  config,
  ...
}:
let
  # The console's one job: get a human onto a network, then hand off to
  # the agent driving the install over SSH. Not a limitation being
  # apologized for — Wi-Fi provisioning genuinely can't be baked in
  # without a secrets mechanism this repo doesn't have yet (see the
  # networking.networkmanager.enable comment below), so this script
  # makes the one remaining manual step impossible to miss instead of
  # requiring the operator to already know NixOS's own `nmtui` ritual.
  #
  # Runs as the "nixos" account's login shell (see users.users.nixos.shell
  # below), so it takes over the console through the *existing* getty
  # autologin that nixos/modules/profiles/installation-device.nix already
  # sets up (services.getty.autologinUser = "nixos") — no custom systemd
  # unit or TTY plumbing needed.
  #
  # docs/tasks/0012 (read its "Why" section for the incident report):
  # this module used to claim, right here, that root's own shell was
  # untouched and a second virtual console was therefore always
  # reachable. That was wrong, and demonstrated wrong on the first
  # from-scratch boot of the custom image: installation-device.nix sets
  # `services.getty.autologinUser`, and NixOS's getty module applies that
  # to the getty@ *template* unit, not just getty@tty1 — every VT
  # auto-logs in as "nixos" and therefore runs this same script. When
  # `nmtui` hit an unrelated bug (a `timeout` foreground-process-group
  # issue, fixed above) and stopped reading the keyboard, switching VTs
  # didn't reach a shell at all: it just launched a second, equally
  # deaf, copy of the same script. A perfectly drawn menu, and no way to
  # do anything, including diagnose it.
  #
  # `services.getty.autologinOnce = true` (set below, in `config`) is the
  # fix: it's an existing, upstream NixOS option, not something invented
  # here, and it does exactly what's needed — auto-login only the
  # *first* tty (tty1) once per boot; every other VT, and tty1 itself on
  # any respawn, falls through to a plain agetty login prompt where
  # "root" (stock empty password, installation-device.nix) or "nixos"
  # (same) gets a real shell. That also closes the brief's item 3 for
  # free: if this script ever crashes, getty@tty1 respawns under
  # systemd's normal Restart=always, the one-time flag file is already
  # written, and the respawn lands at a login prompt instead of looping
  # back into the same broken script — see
  # nixpkgs/nixos/modules/services/ttys/getty.nix's autologinScript,
  # which is exactly what makes this true rather than a hope.
  #
  # The alternative the brief also allows — leave autologin everywhere
  # and teach this script an explicit "press S for a shell" key — was
  # rejected on purpose: that escape would depend on this same script
  # correctly reading the keyboard, which is the exact mechanism that
  # failed in the incident this task exists to fix. tty1-only autologin
  # makes the escape route depend on nothing this script does; even a
  # future bug that reintroduces a SIGTTIN-style deaf read on tty1
  # leaves every other VT completely unaffected.
  #
  # The escape route above is only real if it's discoverable from the
  # screen the operator is actually looking at, not just from a comment
  # in this file — see the ESCAPE_HINT banner line below, printed on
  # every state this script can be in.
  statusScript = pkgs.writeShellApplication {
    name = "castle-installer-status";
    runtimeInputs = [
      pkgs.iproute2
      pkgs.gawk
      pkgs.coreutils
      pkgs.ncurses
      config.networking.networkmanager.package
    ];
    text = ''
      # Ask NetworkManager whether it considers itself connected, rather
      # than inferring readiness from the kernel routing table directly.
      # `ip -4 route show default` can go true the instant a route
      # appears, which can precede NetworkManager finishing activation
      # (DNS, etc.) — a gap where this script would tell the operator
      # "connected" before the machine actually is, which is exactly the
      # kind of console-lies-to-the-operator failure this feature exists
      # to prevent. "connected-global" is NetworkManager's own signal
      # for "has real, non-link-local connectivity" and doesn't require
      # its optional internet-reachability check to be configured.
      have_network() {
        [ "$(nmcli -t -f STATE general 2>/dev/null)" = "connected-global" ]
      }

      show_addrs() {
        ip -4 -o addr show scope global 2>/dev/null \
          | awk '{print $4}' | cut -d/ -f1 | paste -sd', ' -
      }

      # `clear`'s exit status depends on TERM/terminfo being usable on
      # this tty; writeShellApplication runs everything under
      # `set -euo pipefail`, so an unguarded `clear` that happens to fail
      # (unset TERM, a terminfo entry this tty's driver doesn't have)
      # would abort the whole script right there -- landing a dead,
      # blank console exactly where this feature promises the opposite.
      # Never load-bearing, so never allowed to take the script down.
      safe_clear() { clear 2>/dev/null || true; }

      # Printed on every screen this script ever shows (below), including
      # the very first line, so it's on-screen no matter which state the
      # operator's console froze in. This is the actual fix for
      # docs/tasks/0012, not the tty1-only autologin config alone: an
      # escape route nobody can see from the console they're staring at
      # might as well not exist (that's what happened with the
      # `systemd.unit=rescue.target` kernel argument and plugging in
      # Ethernet during the incident this task documents -- both real,
      # neither ever displayed anywhere). This line names no port
      # number, hostname, or credential -- it's the same three words for
      # every boot of every host, so it stays put across edits to
      # anything below it.
      ESCAPE_HINT="Stuck? Ctrl+Alt+F2 for a real shell (log in as root or nixos, no password)."

      safe_clear
      echo "Castle Turing installer -- booting, checking for a network connection..."
      echo "$ESCAPE_HINT"

      # Give DHCP a head start before assuming nobody's on a network yet
      # (the common case: Ethernet, already plugged in, needs no prompt
      # at all).
      deadline=$((SECONDS + 20))
      while (( SECONDS < deadline )) && ! have_network; do
        sleep 1
      done

      # One loop, not two: re-checking have_network every iteration --
      # including the "connected" branch below -- is what makes this
      # loop back into the join prompt if the network drops after the
      # status block was already showing, instead of sitting there
      # confidently repeating a now-false "connected" claim with a stale
      # address forever. A console that lies about connectivity is worse
      # than one that says nothing, and that's the exact failure this
      # feature exists to replace.
      while true; do
        if ! have_network; then
          # Never sit here silently unconnected: take over the console
          # with nmtui until something changes. `timeout` bounds each
          # attempt so an unattended machine (nobody at the keyboard at
          # all, e.g. this repo's own CI harness) can't get stuck in an
          # interactive prompt forever -- it just loops back and
          # re-checks (nmtui itself displays live connection state, so a
          # human watching it would normally just back out the moment
          # they see it connected).
          #
          # The `sleep 2` after nmtui returns is load-bearing, not
          # cosmetic: if nmtui exits immediately instead of blocking (no
          # controlling TTY yet, NetworkManager's D-Bus not up yet, or
          # some other startup-ordering hiccup) and connectivity still
          # isn't up, this branch would otherwise busy-spin -- clear,
          # print, exec-fail, repeat, as fast as the shell can fork --
          # pegging a core and flooding the console/serial log for as
          # long as the machine sits unconnected.
          safe_clear
          cat <<BANNER
======================================================================
 Castle Turing installer -- no network yet.

 Ethernet: check the cable -- DHCP should just work, and this screen
 clears itself the moment it does.

 Wi-Fi: use the screen below to join a network. Once connected, quit
 (Esc) to return here.

 $ESCAPE_HINT
======================================================================
BANNER
          # --foreground is load-bearing, not a style choice: without it
          # `timeout` runs nmtui in its own process group, which is not
          # the terminal's foreground group. nmtui still *renders*
          # (writing to the tty is allowed) but every attempt to *read*
          # the keyboard raises SIGTTIN and stops it -- so the operator
          # sees a perfectly drawn menu that ignores every keypress,
          # with no error anywhere. Observed on real hardware, and
          # invisible to the CI harness, which has nobody at the
          # keyboard to notice.
          timeout --foreground 300 nmtui || true
          sleep 2
          continue
        fi

        # Connected: this is the persistent, prominent status block
        # finding #3's own account of task 0003 was missing -- no more
        # running `ip a` by hand and reading the address back to
        # yourself every boot. Refreshed periodically in case DHCP hands
        # out a new lease, and re-verified at the top of this same loop
        # on every refresh -- see the comment above.
        safe_clear
        addrs=$(show_addrs)
        cat <<BANNER
======================================================================
 Castle Turing installer -- network: connected
   reachable at:  ${config.networking.hostName}.local  ($addrs)
   ssh root@${config.networking.hostName}.local
     (key-only -- already authorized with the same admin key your
     private flake supplies for the installed system)
   waiting for install...

   $ESCAPE_HINT
======================================================================
BANNER
        sleep 15
      done
    '';
  };
  statusScriptPath = "${statusScript}/bin/castle-installer-status";
in
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    ./base
  ];

  config = {
    # users.users.nixos.shell (below) repoints the stock installer's own
    # "nixos" account at the status script instead of a real shell. If a
    # private layer ever picks castle.admin.username = "nixos" — a
    # natural-looking choice, it's literally the stock installer's own
    # account name — modules/base would authorize that same account's
    # SSH keys, and `ssh nixos@... <cmd>` would hang forever (the status
    # script never exits) with no error at all: root access is
    # unaffected, so nothing else would look broken. Catch it at eval
    # time with a real message instead of leaving that trap silent.
    assertions = [
      {
        assertion = config.castle.admin.username != "nixos";
        message = ''
          castle.admin.username is "nixos", which collides with this
          installer image's own built-in "nixos" account — its shell is
          repointed at the console status/prompt script (see
          modules/installer.nix), not a real shell. SSHing in as
          nixos@... would hang forever instead of giving you a session;
          root@... is unaffected but the failure mode for the "nixos"
          account itself is silent otherwise. Pick a different
          castle.admin.username for any private-layer configuration that
          imports nixosModules.installer.
        '';
      }
      # docs/tasks/0012's own check (this repo's flake.nix `checks`
      # output) reads the generated status script for the escape-hatch
      # banner text; this assertion reads the generated *configuration*
      # for the getty behavior half of the same guarantee — the pairing
      # the brief asks for, not evaluation succeeding by itself.
      {
        assertion = config.services.getty.autologinOnce;
        message = ''
          services.getty.autologinOnce got turned off (or overridden)
          somewhere. Without it, installation-device.nix's
          `services.getty.autologinUser = "nixos"` auto-logs in on every
          virtual console, not just tty1 — so every VT runs
          statusScript, and if that script ever stops reading the
          keyboard there is no shell reachable anywhere on the console.
          See the comment on services.getty.autologinOnce below and
          docs/tasks/0012 for the incident that made this a hard
          requirement, not a preference.
        '';
      }
    ];

    # Nobody is ever at a *boot menu* by design — don't sit there waiting
    # for a keypress that will never come. (0 disables the timeout
    # entirely for both the BIOS/syslinux and EFI/grub menus this
    # profile generates; confirmed against nixpkgs's
    # installer/cd-dvd/iso-image.nix, which reads this same option.)
    # This is distinct from the *console*, once booted, which is exactly
    # where a human may need to act once — see statusScript above.
    boot.loader.timeout = lib.mkForce 0;

    # Advertise over mDNS so an operator (human or agent) can reach the
    # machine without ever reading its IP off a router's admin page —
    # `ssh root@castle-installer.local`, also printed on the console
    # itself once connected. A private layer composing this module can
    # override networking.hostName per host (e.g. "xps9370-installer")
    # if it builds more than one installer image and needs them
    # distinguishable on the same LAN segment.
    networking.hostName = lib.mkDefault "castle-installer";
    services.avahi = {
      enable = true;
      openFirewall = true;
      publish = {
        enable = true;
        addresses = true;
      };
    };

    # Network provisioning, and the one place this task's goal is
    # deliberately narrower than "no manual step, ever":
    #
    # The installation-device profile this image is built on already
    # enables NetworkManager (nixos/modules/profiles/installation-device.nix,
    # a plain assignment, not mkDefault) — auto-connecting a wired
    # interface over DHCP with zero interaction is already what a stock
    # installer does. `mkForce` here doesn't change that; it guarantees
    # it: everything above (mDNS, the console status/prompt script) is
    # built on NetworkManager actually running, so this line exists to
    # keep that true even against a private layer's own modules, not to
    # merely restate nixpkgs's current default. Plug the target into
    # Ethernet before powering it on and the machine reaches the LAN,
    # and is SSH-reachable, with nobody ever touching its keyboard.
    #
    # Wi-Fi is intentionally NOT provisioned by this module — that's a
    # deliberate scope decision, not a gap this module tries to paper
    # over. A Wi-Fi PSK is private-layer data (Principle 01), and this
    # repo has no secrets mechanism yet — sops-nix is explicitly out of
    # scope for this task (docs/tasks/0006-installer-image.md). Baking a
    # PSK into a NetworkManager connection profile at ISO-build time
    # would mean writing it in plaintext into a private-layer Nix file,
    # which is exactly the kind of plaintext-credential-in-a-repo
    # Principle 01 and docs/private-layer.md rule out even for the
    # private repo ("a private repo is access control, not encryption").
    # One manual Wi-Fi join, guided and impossible to miss (statusScript
    # above), is a better trade than inventing a hack around that. See
    # docs/private-layer.md and hosts/xps9370/README.md.
    networking.networkmanager.enable = lib.mkForce true;

    # The console's whole job now: get the machine onto a network (with
    # help if it needs it), then display how to reach it and hand off to
    # whoever's driving the actual install over SSH. See statusScript's
    # own comment above for why this is a login-shell swap rather than a
    # custom systemd unit.
    users.users.nixos.shell = statusScriptPath;
    environment.shells = [ statusScriptPath ];

    # docs/tasks/0012: guarantee a shell. installation-device.nix (this
    # module's own base profile) sets `services.getty.autologinUser =
    # "nixos"` as a plain assignment, and NixOS's getty module applies
    # that to the getty@ *template* unit — every virtual console, not
    # just tty1 — so without this, every VT runs statusScript above, and
    # if that script ever stops reading the keyboard (as it did on the
    # incident this task documents) there is no console anywhere that
    # reaches a shell. `autologinOnce` is an existing upstream NixOS
    # option (nixos/modules/services/ttys/getty.nix) built for exactly
    # this: auto-login happens once, on tty1, per boot; every other VT —
    # and tty1 itself, on any respawn after this script exits or crashes
    # — gets a plain agetty login prompt instead. "root" and "nixos"
    # both have the stock installer's empty password there (see
    # installation-device.nix), so that prompt is a real shell, not a
    # dead end.
    #
    # The comment on statusScript above argues why this — tty1-only,
    # with the escape route printed on the console itself — was chosen
    # over teaching the status script its own "press a key for a shell"
    # exit: that alternative's escape would depend on the same script
    # correctly reading the keyboard, which is precisely the mechanism
    # that failed here.
    services.getty.autologinOnce = true;

    # types.lines concatenates every module's contribution rather than
    # requiring exactly one definition (nixpkgs/lib/types.nix,
    # `separatedString`), so this adds to installation-device.nix's own
    # helpLine (the "accounts have empty passwords" text) rather than
    # replacing it. Shown in /etc/issue on every non-autologin getty
    # prompt — i.e. tty2 upward, and tty1 after a respawn — which is
    # exactly the escape route above; this makes it discoverable from
    # that prompt too, not only from statusScript's own banners.
    services.getty.helpLine = ''

      This is a real login prompt, not the install-status screen (that's
      tty1, which auto-logs in once per boot) -- log in as "root" or
      "nixos" for a shell.
    '';

    # A discarded-at-EOL live image: build speed beats a tightly packed
    # download here. A private layer building an image meant to be
    # redistributed (rather than used once and thrown away) can
    # `lib.mkForce` a stronger compressor.
    isoImage.squashfsCompression = lib.mkDefault "gzip -Xcompression-level 1";
  };
}
