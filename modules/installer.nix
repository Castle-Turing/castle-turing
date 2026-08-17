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
  # here, and its `getty@`-specific behavior — see
  # nixos/modules/services/ttys/getty.nix's `autologinScript`, confirmed
  # by reading that source, not assumed — is exactly what's needed:
  # auto-login only the *first* tty (tty1) once per boot; every other
  # VT, and tty1 itself on any respawn, falls through to a plain agetty
  # login prompt. Only "root" (stock empty password, installation-
  # device.nix) gets a real shell there — "nixos" does not, its shell is
  # this very script (users.users.nixos.shell, below), so logging in as
  # "nixos" on a spare VT just re-runs statusScript and drops the
  # operator right back into the same nmtui loop. Confirmed the hard
  # way (docs/tasks/0016): two copies of this script running at once,
  # one on the intended tty1 autologin and one started by an operator
  # following what shellLoginHint told them. That also closes the
  # brief's item 3 for free: if this script ever crashes, getty@tty1
  # respawns under systemd's normal Restart=always, the one-time flag
  # file is already written, and the respawn lands at a login prompt
  # instead of looping back into the same broken script.
  #
  # `autologinOnce` is not scoped to `getty@`, though, and that's not
  # cosmetic: `serial-getty@` and `container-getty@` build their agetty
  # command from the same `baseArgs` `getty@`'s non-autologin branch
  # uses, but call it *directly*, with none of `getty@`'s tty1-once
  # conditional. `baseArgs` appends `--autologin` only when
  # `!cfg.autologinOnce` — so turning this on doesn't confine those
  # units' autologin to "once", it removes it *entirely*, every boot.
  # Left alone, that regresses the one console this task doesn't get to
  # ignore: `test/vm-install/` reaches this exact image over
  # `serial-getty@ttyS0` (`boot.kernelParams = [ "console=ttyS0" ]`),
  # and so does a real headless/IPMI operator per
  # docs/backlog/headless-recovery.md — both would silently lose the
  # network/SSH status banner entirely, worse than before this task,
  # not better. The `systemd.services."serial-getty@"` override below
  # restores it explicitly; `container-getty@` is left as-is, since a
  # bootable installer image is never run as an nspawn container.
  #
  # The alternative the brief also allows — leave autologin everywhere
  # and teach this script an explicit "press S for a shell" key — was
  # rejected on purpose: that escape would depend on this same script
  # correctly reading the keyboard, which is the exact mechanism that
  # failed in the incident this task exists to fix. tty1-only autologin
  # makes the escape route depend on nothing this script does; even a
  # future bug that reintroduces a SIGTTIN-style deaf read on tty1
  # leaves every other VT completely unaffected. Note that this script
  # can still *go deaf mid-session* without crashing at all — nothing
  # about a hung `nmcli`/`ip` call trips autologinOnce's respawn path —
  # so the VT switch below is the operator's route in that case too,
  # not just after a crash. This is the canonical explanation of the
  # tty1-only decision; every other comment on it in this file
  # (config.assertions, services.getty.autologinOnce) points back here
  # rather than repeating it.
  #
  # None of that matters if the way out isn't visible from the screen
  # the operator is actually staring at (also demonstrated: the
  # `systemd.unit=rescue.target` kernel argument and plugging in
  # Ethernet were both real escape routes during the incident, and
  # neither was ever displayed anywhere). shellLoginHint and
  # escapeBanner below exist to keep that promise without duplicating
  # the underlying facts as independent string literals that could
  # quietly drift apart — see their own comments.

  # The fact that could go stale without anyone noticing it drifted:
  # which account has a shell here at all, and that it needs no
  # password. Only "root" — see the comment above on why "nixos" isn't
  # a second answer here, however natural it looks (docs/tasks/0016
  # caught this file itself getting it wrong, in this exact string).
  # Shared, verbatim, between statusScriptText's banners (below) and
  # services.getty.helpLine (config, below) — two unrelated NixOS
  # surfaces (a script's stdout vs. agetty's issue file) that would
  # otherwise encode this as independent literals with nothing keeping
  # them in sync. A future change (a real password, a renamed account)
  # is one edit here instead of a search for every place this used to
  # say the same thing in different words. Per the incident above, a
  # stale copy of exactly this fact is worse than printing nothing: a
  # recovery console confidently giving directions that no longer work.
  shellLoginHint = "log in as root, no password";

  # The exact line statusScriptText (below) prints on *every* console
  # state it can be in. config.assertions (below) counts how many of
  # those states still carry this precise string, at eval time — "does
  # this text exist somewhere in the generated script" is a strictly
  # weaker claim that would still pass if one banner silently dropped
  # it, which is the actual property this task exists to guarantee
  # (docs/tasks/0012: "make the exit discoverable *on the console*").
  # Ctrl+Alt+F2 alone doesn't reach a VT on every keyboard -- laptops
  # commonly ship the F-row as media/brightness keys by default, needing
  # Fn held too (Ctrl+Alt+Fn+F2), and the incident this task fixes
  # happened on a real laptop. Naming only the chord that might not work
  # would repeat this task's own failure one step later: a console
  # confidently printing a direction that doesn't do anything on the
  # hardware in front of it. Mentioning both costs one clause.
  escapeBanner = "Stuck? Ctrl+Alt+F2 (Ctrl+Alt+Fn+F2 if F2 alone does nothing) for a real shell -- ${shellLoginHint}.";

  # Kept as its own binding, not inlined directly into
  # writeShellApplication below, so config.assertions can inspect the
  # text that becomes the generated script without building anything.
  # This is a legitimate substitute for grepping the built artifact,
  # not a shortcut: writeShellApplication doesn't parse or transform
  # `text`, it only wraps it in a shebang, `set -euo pipefail`, and a
  # PATH export and appends it verbatim, so a substring's presence (or
  # count) here is identical to its presence in the file that ships.
  # Cheaper, and it works without a Linux builder.
  statusScriptText = ''
    # docs/tasks/0016: this function used to compare against the literal
    # string "connected-global", on the theory that it was NetworkManager's
    # own signal for "real, non-link-local connectivity" without needing
    # the optional internet-reachability check configured. That theory was
    # never checked against a running NetworkManager, and it's wrong:
    # `connected-global` is the *enum constant* name
    # (NM_STATE_CONNECTED_GLOBAL), not a string `nmcli -t -f STATE general`
    # ever prints — terse mode prints "connected". The predicate was
    # therefore FALSE on every boot, on real hardware, over SSH, at the
    # same moment the machine was demonstrably reachable on the network.
    # Since this is the only condition in the script's main loop, the
    # connected banner below has never rendered anywhere, ever, and the
    # script relaunched nmtui forever even after the operator joined a
    # network and quit it.
    #
    # The fix asks a narrower, more honest question than the original
    # comment did. "Real, non-link-local connectivity" was standing in for
    # the actual requirement: can an operator on this LAN open an SSH
    # session to this machine. That needs a routable address, not an
    # internet route — an installer on an air-gapped bench network should
    # show its address, not claim to be offline. `connected*` matches
    # NetworkManager's "connected", "connected (site only)", and
    # "connected (local only)" states; requiring a non-empty global-scope
    # address (show_addrs, below) accepts the first two — a LAN with no
    # route out is entirely fine for this image's purpose — and rejects
    # the third (link-local only, not reachable from another host).
    #
    # show_addrs checks both IPv4 and IPv6 global-scope addresses, not
    # just v4: this predicate reuses show_addrs, which used to be purely
    # decorative (only ever fed into the connected banner's display
    # text), so nothing depended on which address families it covered.
    # Making it the gate for have_network() changes that — an IPv6-only
    # LAN (SLAAC/DHCPv6, no v4 at all) has NetworkManager correctly
    # reporting "connected" while an IPv4-only show_addrs would silently
    # never satisfy this predicate, repeating this task's own bug for a
    # narrower case (caught by a Codex CLI review of an earlier version
    # of this change, before it shipped). `ip ... scope global` for IPv6
    # includes ULA (fc00::/7) alongside true global unicast, which is
    # correct here too: ULA isn't internet-routable but is exactly as
    # LAN-reachable as the IPv4 case this predicate already accepts.
    #
    # Deliberately NOT `nmcli -t -f CONNECTIVITY general = full`: that
    # answers a different question (can NetworkManager reach its configured
    # check endpoint), returns "unknown" wherever connectivity checking
    # isn't configured — the exact fragility this predicate is trying to
    # avoid — and reports "limited" or "portal" on perfectly usable LANs
    # that happen to block the check.
    #
    # Also NOT inferred from the kernel routing table directly (`ip -4
    # route show default`): that can go true the instant a route appears,
    # which can precede NetworkManager finishing activation (DNS, etc.) —
    # a gap where this script would tell the operator "connected" before
    # the machine actually is. Asking NetworkManager keeps that ordering
    # honest; the enum-string typo above is what made this predicate wrong
    # in practice, not the decision to ask NetworkManager in the first
    # place.
    have_network() {
      case "$(nmcli -t -f STATE general 2>/dev/null)" in
        connected*) ;;
        *) return 1 ;;
      esac
      [ -n "$(show_addrs)" ]
    }

    # Both address families, not just v4 -- see have_network's comment
    # above for why this stopped being purely cosmetic. Two separate `ip`
    # calls rather than a single `ip -o addr show scope global` (which
    # would print both families unfiltered): `-4`/`-6` keep this function
    # able to be read as "the v4 list, then the v6 list", matching the
    # awk/cut pipeline below either family already used, and avoiding a
    # dependency on `ip`'s combined-output field order staying stable
    # across both families in one invocation.
    show_addrs() {
      {
        ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1
        ip -6 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1
      } | paste -sd', ' -
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
    echo "${escapeBanner}"

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
        # The pause after nmtui returns (below, in the still-disconnected
        # branch) is load-bearing, not cosmetic: if nmtui exits
        # immediately instead of blocking (no controlling TTY yet,
        # NetworkManager's D-Bus not up yet, or some other
        # startup-ordering hiccup) and connectivity still isn't up, this
        # branch would otherwise busy-spin -- clear, print, exec-fail,
        # repeat, as fast as the shell can fork -- pegging a core and
        # flooding the console/serial log for as long as the machine sits
        # unconnected.
        safe_clear
        # Quoted heredoc ('BANNER'): deliberate and load-bearing, not
        # the default nixpkgs style elsewhere in this file. This block
        # has no shell variables in it on purpose, so nothing pasted
        # into it later -- a literal $, a $HOME example, a backtick --
        # can ever be silently expanded or command-substituted. The
        # escape line is interpolated at the Nix level and printed
        # separately below rather than folded into this heredoc, so
        # that guard doesn't have to be given up to show it.
        cat <<'BANNER'
======================================================================
 Castle Turing installer -- no network yet.

 Ethernet: check the cable -- DHCP should just work, and this screen
 clears itself the moment it does.

 Wi-Fi: use the screen below to join a network. Once connected, quit
 (Esc) to return here.
======================================================================
BANNER
        echo "${escapeBanner}"
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

        # docs/tasks/0016, defect 3: nmtui exited (timed out, or the
        # operator backed out) and the top of the next iteration is about
        # to re-check have_network and, if it's still false, wipe this
        # screen and show the same "no network yet" banner again -- with
        # no way for whoever's watching to tell "NetworkManager genuinely
        # still reports disconnected" from "this script's predicate is
        # wrong" apart. That ambiguity is exactly what let defect 1 sit
        # unnoticed until a human was at the keyboard with a second
        # machine to SSH in and check by hand. Printing NetworkManager's
        # raw answer here means the same diagnosis takes one glance at
        # this screen instead. Display-only, adds no input path -- the
        # "considered and rejected" section in docs/tasks/0016 is explicit
        # that the VT escape (shellLoginHint/escapeBanner) must keep being
        # the only way out that doesn't depend on this script reading the
        # keyboard correctly.
        if ! have_network; then
          echo "NetworkManager reports: STATE=$(nmcli -t -f STATE general 2>/dev/null || echo '<nmcli failed>')  global addrs: $(show_addrs || true)"
          # Held longer than the bare busy-spin guard needs, so the line
          # above is actually readable before the screen clears again --
          # not just present in the (much larger) serial-log scrollback.
          sleep 4
        fi
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
      # Unquoted heredoc, pre-existing and unrelated to the escape
      # hint above: ${config.networking.hostName} is a Nix
      # interpolation and $addrs a shell one, both necessary to show a
      # real, current address, so this block can't be fully quoted.
      # The escape line still stays out of it, printed separately
      # below, so this isn't one more reason it has to stay unquoted.
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
      echo "${escapeBanner}"
      sleep 15
    done
  '';

  statusScript = pkgs.writeShellApplication {
    name = "castle-installer-status";
    runtimeInputs = [
      pkgs.iproute2
      pkgs.gawk
      pkgs.coreutils
      pkgs.ncurses
      config.networking.networkmanager.package
    ];
    text = statusScriptText;
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
      # docs/tasks/0012, configuration half of the escape-hatch
      # guarantee (the artifact half is the count assertion below).
      {
        assertion = config.services.getty.autologinOnce;
        message = ''
          services.getty.autologinOnce got turned off. Without it,
          every VT (tty1-6) auto-logs into statusScript, not just tty1
          -- see docs/tasks/0012 and the comment on statusScript
          (modules/installer.nix) for why that's a hard requirement.
        '';
      }
      # docs/tasks/0012: autologinOnce (above) has a side effect beyond
      # VTs -- see the long comment on statusScript for the mechanism
      # -- that silently strips autologin from serial-getty@ entirely,
      # not just tty2-6. The override below restores it; this checks
      # that the restoration actually landed in the final merged
      # config, not just that this file's own Nix source attempts it.
      {
        assertion =
          let
            execStart = lib.concatStringsSep " " config.systemd.services."serial-getty@".serviceConfig.ExecStart;
            autologinUser = config.services.getty.autologinUser;
          in
          autologinUser != null -> (lib.hasInfix "--autologin" execStart && lib.hasInfix autologinUser execStart);
        message = ''
          serial-getty@'s ExecStart no longer includes --autologin for
          services.getty.autologinUser. Without it, a serial console
          (test/vm-install/ reaches this image over serial-getty@ttyS0;
          a real headless/IPMI operator would too) gets a bare login
          prompt with no network/SSH status banner at all -- a
          regression, not the fix docs/tasks/0012 asks for. See the
          systemd.services."serial-getty@" override and the comment on
          statusScript, both in modules/installer.nix.
        '';
      }
      # docs/tasks/0012, artifact half: a check that escapeBanner
      # exists *somewhere* in statusScriptText would still pass if one
      # of the three banners above silently dropped it -- exactly the
      # class of check this repo has already shipped twice (`nix flake
      # check` proving options evaluate while the generated config
      # said the wrong thing; `sway --validate` accepting a config
      # with one keybinding and no way out). Counting is the
      # structural version: statusScriptText prints escapeBanner on
      # all three states it can be in (booting, no-network, connected),
      # so the count has to be exactly 3, not "at least 1".
      {
        assertion = (lib.length (lib.splitString escapeBanner statusScriptText)) - 1 == 3;
        message = ''
          The installer status script's escape-hatch line no longer
          appears exactly 3 times in the generated script (once per
          console state: booting, no-network, connected) -- see
          docs/tasks/0012. If a console state was deliberately added or
          removed, update the expected count (3) here to match;
          otherwise one of statusScriptText's banners
          (modules/installer.nix) lost its escape line, which is
          exactly the failure this assertion exists to catch.
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

    # docs/tasks/0012: confines VT autologin to tty1, once per boot, so
    # every other VT — and tty1 itself, after a crash or a respawn —
    # falls through to a real login prompt instead of re-running
    # statusScript. Full rationale (why this over an in-script escape
    # key, and why it also strips autologin from serial-getty@ as a
    # side effect the override below undoes) is on statusScript's own
    # comment, above; this is an existing upstream NixOS option, not
    # invented here.
    services.getty.autologinOnce = true;

    # Undoes the one part of autologinOnce (above) this module doesn't
    # want: see the long comment on statusScript for why serial-getty@
    # needs its own restoration rather than inheriting the tty1-once
    # behavior getty@ gets for free. This is a faithful reconstruction
    # of nixos/modules/services/ttys/getty.nix's own `baseArgs` /
    # `gettyCmd` — verified against that source directly, not from
    # memory — for the case that module's own private `let` bindings
    # aren't exposed to reuse: `--autologin` restored, everything else
    # (login program, issue file, login options, extraArgs) identical
    # to what serial-getty@ would otherwise render. mkForce because
    # getty.nix already sets this same option at normal priority (its
    # own `[ "" (gettyCmd ...) ]`), and ExecStart entries concatenate
    # across modules rather than simply overriding, so only a forced
    # definition reliably wins regardless of module ordering.
    systemd.services."serial-getty@".serviceConfig.ExecStart = lib.mkForce [
      ""
      (
        "${lib.getExe' pkgs.util-linux "agetty"} "
        + lib.escapeShellArgs (
          [
            "--login-program"
            config.services.getty.loginProgram
            "--issue-file"
            "/etc/issue:/etc/issue.d:/run/issue:/run/issue.d"
          ]
          ++ lib.optionals (config.services.getty.autologinUser != null) [
            "--autologin"
            config.services.getty.autologinUser
          ]
          ++ lib.optionals (config.services.getty.loginOptions != null) [
            "--login-options"
            config.services.getty.loginOptions
          ]
          ++ config.services.getty.extraArgs
        )
        + " %I --keep-baud $TERM"
      )
    ];

    # types.lines concatenates every module's contribution rather than
    # requiring exactly one definition (nixpkgs/lib/types.nix,
    # `separatedString`), so this adds to installation-device.nix's own
    # helpLine (the "accounts have empty passwords" text) rather than
    # replacing it. agetty prints /etc/issue (which carries helpLine)
    # before it decides whether to autologin, so this text can flash
    # briefly even on tty1's very first boot, before safe_clear wipes
    # it — deliberately worded to still be true if someone reads it
    # right then, rather than asserting "this isn't tty1" the way an
    # earlier draft of this comment did.
    services.getty.helpLine = ''

      Need a shell instead of the install-status screen? ${shellLoginHint}.
    '';

    # A discarded-at-EOL live image: build speed beats a tightly packed
    # download here. A private layer building an image meant to be
    # redistributed (rather than used once and thrown away) can
    # `lib.mkForce` a stronger compressor.
    isoImage.squashfsCompression = lib.mkDefault "gzip -Xcompression-level 1";
  };
}
