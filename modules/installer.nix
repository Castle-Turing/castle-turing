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
  # unit or TTY plumbing needed. root's own shell is untouched, so a real
  # shell is always still reachable (a second virtual console, e.g.
  # Alt+F2, logging in as root with its stock empty password; or
  # `ssh root@...` once the network is up) for anyone who needs to debug
  # the image itself rather than just get it on a network.
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

      safe_clear
      echo "Castle Turing installer -- booting, checking for a network connection..."

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
          cat <<'BANNER'
======================================================================
 Castle Turing installer -- no network yet.

 Ethernet: check the cable -- DHCP should just work, and this screen
 clears itself the moment it does.

 Wi-Fi: use the screen below to join a network. Once connected, quit
 (Esc) to return here.
======================================================================
BANNER
          timeout 300 nmtui || true
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

    # A discarded-at-EOL live image: build speed beats a tightly packed
    # download here. A private layer building an image meant to be
    # redistributed (rather than used once and thrown away) can
    # `lib.mkForce` a stronger compressor.
    isoImage.squashfsCompression = lib.mkDefault "gzip -Xcompression-level 1";
  };
}
