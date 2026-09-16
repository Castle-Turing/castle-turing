# hosts/xps9370 — Dell XPS 13 9370, the reference host.
#
# Machine facts only: the resident (castle.admin) is supplied by the
# consuming private layer. The nixos-hardware and disko modules this
# host needs are bound by flake.nix's `nixosModules.host-xps9370`
# export, which is how this directory should be consumed.
{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "xps9370";

  # This chassis's Killer/Atheros Wi-Fi card (ath10k_pci) needs a firmware
  # blob NixOS doesn't ship by default. Confirmed via journalctl on the
  # first real install: "could not fetch firmware files (-2)" — the
  # nixos-hardware dell-xps-13-9370 module does not set this itself.
  hardware.enableRedistributableFirmware = true;

  # Bar the NVMe from its deepest autonomous power state (PS4). On
  # 2026-09-16 at ~01:24 this chassis's PC401 stopped serving I/O
  # while the machine ran on from page cache for 6.5 hours — task
  # 0075's brief carries the evidence chain, task 0074 the detector
  # the incident shipped. SMART afterwards: healthy media, and a
  # controller that logged nothing because the commands never
  # reached it — the link/power-state dropout shape reported for
  # this drive in this chassis, not media failure. The drive's APST
  # table was programmed to enter PS4 (7 mW, 5 ms exit) after 100 ms
  # of idle from every operational state, and the pinned kernel
  # carries no NO_DEEPEST_PS quirk for it (the programmed table is
  # the proof: a quirked kernel never selects ITPS=4).
  #
  # 5500 rather than 0: the kernel admits a non-operational state
  # only when its entry+exit latency fits this budget, so 5500 µs
  # bars PS4 (1000+5000) and keeps PS3 (1000+1000, 70 mW) as the
  # floor — roughly 60 mW of idle cost against APST off entirely,
  # which would hold the drive at operational-idle watts. Probable
  # cause, not proven (the proving kernel messages died with the
  # unpersisted journal), so the falsifier is explicit: a dropout
  # recurring with this parameter in place refutes the PS4 theory,
  # and the next step is 0. Task 0074's canary is what makes such a
  # recurrence visible rather than another blank night.
  boot.kernelParams = [ "nvme_core.default_ps_max_latency_us=5500" ];

  # The boot loader (systemd-boot + the ESP fallback posture) comes from
  # modules/boot.nix, bound by flake.nix's nixosModules.host-xps9370
  # wrapper alongside diskLayout. This chassis is why that posture
  # exists: its CMOS battery was replaced during task 0003, and on power
  # loss with a dead battery the firmware forgets its NVRAM boot entries
  # and falls back to the ESP default path. On the first real install
  # the fallback copy did not survive to the deployed ESP despite the
  # install log claiming to have written it — see
  # docs/tasks/0003-findings.md finding #2 for the investigation and
  # finding #5 for how a clean redeploy (stale NVRAM entries removed,
  # firmware back in UEFI mode) produced a fallback file that did
  # survive, checksum-verified against the source binary. Treat NVRAM as
  # unreliable regardless of the new battery — it's cheap insurance and
  # this config has no way to detect a future failure.

  # 16GB RAM, no hibernation use-case on a project machine: compressed
  # RAM swap instead of a swap partition keeps the disk layout simpler.
  zramSwap.enable = true;

  # The cost of zram-only swap, learned the hard way (2026-09-06, task
  # 0063; recurred 2026-09-15, task 0073): with no disk swap the kernel
  # OOM killer effectively never trips — under exhaustion the machine
  # thrashes in reclaim until someone holds the power button. Disk-swap
  # headroom for the kernel killer is the deferred second half — see
  # docs/backlog/the-kernel-oom-killer-has-no-swap-headroom.md.
  # systemd-oomd is this host's actual defense, and it needs both of
  # its rules wired to do anything:
  #
  #   - The swap rule (`ManagedOOMSwap=kill`, set here on the root
  #     slice per systemd-oomd.service(8)'s own recommendation — it
  #     "works with the system-wide swap values", so setting it on
  #     `-.slice` makes every descendant cgroup an eligible kill
  #     candidate) is the primary trigger for this host's exhaustion
  #     mode. The zram swap filling toward its 90% default limit is the
  #     early warning this host emits before it livelocks, and this
  #     rule fires on system-wide swap pressure regardless of which
  #     cgroup is responsible.
  #   - The pressure rule (`enableUserSlices`, below) is the backstop
  #     for pressure that never shows up as swap. It is not sufficient
  #     alone: on 2026-09-15 it saw roughly 90 seconds of visible
  #     memory pressure and never fired, because its 80%-over-30s
  #     sustained average is exactly the kind of threshold a fast
  #     allocator on a zram-only host can outrun before it trips.
  #
  # Neither rule is any use if oomd isn't actually watching cgroups
  # under it. Task 0063 wired the pressure rule alone, and its swap
  # counterpart sat unassigned — no NixOS option sets `ManagedOOMSwap=`
  # anywhere — from that day until task 0073 wired it here. The
  # liveness check below (castle-oomd-liveness-check) is what would
  # have caught that gap the day 0063 shipped: it fails loudly,
  # against oomd's own runtime state, whenever either rule's watch
  # list comes up empty.
  systemd.oomd.enableUserSlices = true;
  systemd.slices."-".sliceConfig.ManagedOOMSwap = "kill";

  # A rule that reads as configured while the daemon watches nothing is
  # exactly the failure that went unnoticed from install until task
  # 0063 (pressure) and from 0063 until task 0073 (swap) — evaluating
  # fine and `systemctl status` looking healthy the whole time. This
  # unit fails loudly (visible in `systemctl --failed` and the journal)
  # unless systemd-oomd is actually watching at least one cgroup under
  # BOTH rules above, checked shortly after boot and once a day.
  #
  # oomctl's dump is the only introspection surface systemd-oomd
  # exposes — confirmed via `busctl introspect org.freedesktop.oom1
  # /org/freedesktop/oom1`: its one interface,
  # org.freedesktop.oom1.Manager, has a single method
  # (DumpByFileDescriptor, what `oomctl dump` calls) and no queryable
  # properties. So this parses the same human-facing text a resident
  # would read by hand, not the unit files: `systemctl show` on a slice
  # would only echo back the *configured* ManagedOOMSwap/
  # ManagedOOMMemoryPressure values, which is precisely the "looks
  # armed" half of the gap this check exists to catch, not the "is it
  # watching" half.
  systemd.services.castle-oomd-liveness-check = {
    description = "Assert systemd-oomd is watching cgroups under both its swap and pressure rules";
    after = [ "systemd-oomd.service" ];
    wants = [ "systemd-oomd.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -eu

      oomctl=${config.systemd.package}/bin/oomctl
      awk=${pkgs.gawk}/bin/awk

      # oomctl dump prints one "Path: ..." line per monitored cgroup,
      # under two section headers, in this fixed order (oomctl(1);
      # confirmed against a live system, 2026-09-15). A short retry
      # loop, not just a boot delay, because how long oomd takes to
      # enumerate the slices above after its own unit starts isn't
      # documented and shouldn't be guessed at as a single number --
      # and the retry has to survive `oomctl` itself failing (e.g. its
      # D-Bus call landing before systemd-oomd has registered its
      # name), not just an empty watch list, so the command substitution
      # sits in the `if`'s own test rather than a bare assignment: under
      # `set -e` a bare `dump="$(oomctl dump)"` would abort the whole
      # script on the first transient failure, defeating the retry
      # entirely (test/ci/retry-on-known-transient.sh's header comment
      # notes the same `set -e`-in-a-test-position exemption).
      attempt=0
      max_attempts=6
      while true; do
        attempt=$((attempt + 1))
        if dump="$("$oomctl" dump 2>&1)"; then
          # One awk pass, not two: both counters are derived from the
          # same section-tracking state machine, so a single scan
          # keeps the "which line ends which section" logic in one
          # place. The pressure section's own terminator
          # (`/^[^[:space:]]/`) exists even though it is the last
          # section `oomctl dump` prints today, so a future oomd
          # release adding a further section after it can't silently
          # get counted as pressure-monitored cgroups.
          counts="$(printf '%s\n' "$dump" | "$awk" '
            /^Swap Monitored CGroups:/ { section = "swap"; next }
            /^Memory Pressure Monitored CGroups:/ { section = "pressure"; next }
            section == "swap" && /^[[:space:]]+Path:/ { swap_n++ }
            section == "pressure" && /^[[:space:]]+Path:/ { pressure_n++ }
            section == "pressure" && /^[^[:space:]]/ { section = "" }
            END { print swap_n + 0, pressure_n + 0 }
          ')"
          set -- $counts
          swap_count=$1
          pressure_count=$2
          if [ "$swap_count" -gt 0 ] && [ "$pressure_count" -gt 0 ]; then
            echo "systemd-oomd is watching $swap_count cgroup(s) under its swap rule and $pressure_count under its memory-pressure rule."
            exit 0
          fi
        else
          swap_count=0
          pressure_count=0
        fi
        if [ "$attempt" -ge "$max_attempts" ]; then
          break
        fi
        sleep 5
      done

      echo "systemd-oomd's watch lists came up empty after $max_attempts attempts (swap=$swap_count, pressure=$pressure_count; last 'oomctl dump' output follows) -- a rule that reads as configured but is not watching any cgroup is exactly the regression docs/tasks/0073-the-oomd-swap-rule-and-a-liveness-check.md exists to catch." >&2
      printf '%s\n' "$dump" >&2
      exit 1
    '';
  };

  systemd.timers.castle-oomd-liveness-check = {
    description = "Run the systemd-oomd liveness check shortly after boot, then daily";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # OnBootSec gives a couple of minutes' grace, on top of the
      # check's own retry loop, for every boot. OnCalendar is the
      # actual daily cadence — deliberately not OnUnitActiveSec=1d,
      # which is a *monotonic* timer and, per systemd.timer(5),
      # `Persistent=` "only has an effect on timers configured with
      # OnCalendar=": paired with OnUnitActiveSec, `Persistent=true`
      # silently does nothing, so a laptop asleep at the daily mark
      # would just wait out the remaining monotonic uptime instead of
      # catching up on wake as this unit's own description promises.
      # OnCalendar + Persistent is the combination that actually does
      # that.
      OnBootSec = "2min";
      OnCalendar = "daily";
      Persistent = true;
      Unit = "castle-oomd-liveness-check.service";
    };
  };

  # Wi-Fi is this chassis's network path; NetworkManager belongs here, not
  # in modules/base, since a headless/wired host wouldn't want it.
  #
  # No network is named here, and none will be: running the daemon is a
  # machine fact, an SSID and a PSK are the resident's (Principle 01).
  # Joined by hand, those credentials live in
  # /etc/NetworkManager/system-connections and never enter any repo.
  # Declared instead — which is what secrets tooling made possible, via
  # networking.networkmanager.ensureProfiles fed from an encrypted
  # secret (docs/tasks/0031-secrets-tooling.md; worked example in
  # docs/private-layer.md's "Secrets" section) — they live in the
  # private layer. Either way, not in this file.
  networking.networkmanager.enable = true;

  # First installed from nixos-unstable ahead of the 26.11 release.
  # Never change this after install.
  system.stateVersion = "26.11";

  # This chassis's touchscreen option is the 3840x2160 (4K UHD) panel at
  # 13.3" — about 331 PPI, roughly double a "normal" ~160 PPI laptop
  # display (docs/vision.md: "Dell XPS 13 9370 ... touchscreen", which
  # on this model only ever shipped paired with the 4K panel, never the
  # 1080p one). Sway's own auto-detection leaves everything at 1x, which
  # is what task 0008's real errand ("the cursor is too small") actually
  # was: not a cursor-theme bug, a panel-density fact this host module
  # is exactly the right layer for (Principle 01 consequence 2 — a
  # panel's DPI identifies no one). `lib.mkDefault` so a private layer
  # can still override for taste, per castle.display.scale's own
  # description in modules/desktop.
  #
  # cursorSize is set explicitly alongside scale, but NOT to compensate
  # for scale — Sway itself already multiplies the cursor size it's
  # given by the output scale (that's what `seat * xcursor_theme <name>
  # <size>`, wired from home.pointerCursor.size, feeds into), so this
  # value is pre-scale, the same way a font point size is. Doubling it
  # here on top of a 2.0 output scale was tried first (48, reasoning
  # from the real XWayland/GTK gap below) and double-compensated: Sway
  # rendered it at roughly 96 physical pixels, about 7mm on this panel —
  # confirmed on the first real deploy as dramatically, unusably
  # oversized (docs/tasks/0013-first-deploy-findings.md). 18 is the
  # corrected, eye-calibrated value on this panel at scale
  # 2.0 (36 physical pixels, ~2.8mm) — below the 24px unscaled default,
  # and still visibly larger than what task 0008's original "too small"
  # complaint was about, because that complaint predates `scale` being
  # set at all: at 1x the pointer was genuinely native-resolution-tiny
  # on a 331 PPI panel, not just under-sized relative to a 2.0-scaled
  # UI. Don't "fix" this back toward 24 or higher on the assumption that
  # a below-default number must be a regression; it isn't, and 0013 is
  # the record of why.
  #
  # The real, separate problem: XWayland and some GTK cursor-rendering
  # paths do not reliably follow Sway's own output scale for the
  # pointer glyph itself (a commonly reported Sway+XWayland gap), so
  # those clients can still show a native-resolution, comparatively
  # tiny cursor even with this value correct for Sway's own seat. This
  # option does not solve that — it only controls what Sway itself
  # (and, via the same XCURSOR_SIZE variable, GTK/X11 clients that *do*
  # follow it) renders. Treating 48 as "the fix for the XWayland gap"
  # is exactly the reasoning that produced the double-scaled bug; the
  # gap is real but out of scope here (0013's non-goals) and needs its
  # own investigation, not a bigger number on this option.
  #
  # modules/home only wires home.pointerCursor at all when
  # castle.display.cursorTheme is non-null (an unset theme name leaves
  # the whole pointer-cursor slot untouched, by design — see that
  # option's description in modules/desktop), so cursorSize alone would
  # otherwise be a silent no-op on this host. modules/desktop ships
  # pkgs.bibata-cursors specifically so a theme name has something real
  # to resolve to; naming one of its themes here is an aesthetic
  # default, not personal data (Principle 01 consequence 2 — nothing
  # about a cursor theme identifies a resident), and a private layer's
  # own taste still overrides it.
  #
  # castle.display is declared by modules/desktop, not by this file —
  # this host module assumes any consumer pairing it with
  # nixosModules.host-xps9370 also imports nixosModules.desktop, the way
  # every nixosConfiguration in this repo's own flake.nix does. An
  # earlier version of this block tried to guard that assumption away
  # with `lib.optionalAttrs (options.castle ? display) { ... }`, so a
  # from-scratch headless pairing of this host without desktop would
  # still evaluate — but reading the `options` module argument to decide
  # which keys *this same module* returns is a real infinite-recursion
  # trap in Nix's module system (config for a still-being-assembled
  # module set depending on the fully-assembled options tree), not
  # just an edge case; `nix flake check` caught it immediately. Reverted
  # in favor of this honest, documented coupling instead: if you ever
  # write a private layer that imports host-xps9370 without desktop,
  # override castle.display back out (or drop this whole block) in your
  # own resident.nix.
  # consoleFont sits here rather than in modules/desktop for the same
  # reason `scale` does, and the reason is worth not forgetting: a
  # console font is a raw pixel grid, and the virtual console never sees
  # castle.display.scale at all. The point sizes (terminalFontSize,
  # uiFontSize) are density-independent *because* scale normalizes
  # density, so the framework can default those for every host; a
  # console font cannot be defaulted that way. spleen-16x32 gives a
  # 240x67 grid on this 3840x2160 panel — roughly 2.4mm glyphs, against
  # the kernel default 8x16's ~1.2mm, which is what made the greeter and
  # any recovery shell effectively unreadable here.
  #
  # Chosen by looking, not derived: ter-v32n (identical metrics),
  # spleen-32x64 (twice the size, 120x33) and a generated 24x48 were all
  # loaded onto spare VTs and compared — see
  # docs/tasks/0017-legible-defaults.md and tools/console-font-sweep.sh
  # to re-run that comparison. Note especially that there is NO 32px
  # ceiling in fbcon; an early draft of that brief claimed one, and it
  # was false.
  castle.display = {
    scale = lib.mkDefault 2.0;
    cursorTheme = lib.mkDefault "Bibata-Modern-Classic";
    cursorSize = lib.mkDefault 18;
    consoleFont = lib.mkDefault "spleen-16x32";
  };

  # Chassis facts consumed by the desktop's ergonomics (task 0020).
  #
  # No wired ethernet port: this chassis's only network path is Wi-Fi,
  # as the networkmanager comment above already says. modules/home uses
  # this to drop i3status's `ethernet _first_` entry, which otherwise
  # renders a permanent red fault for hardware that does not exist. The
  # framework cannot assume this — a desktop with an unplugged cable
  # should show that fault — so the fact is stated here and the mapping
  # from fact to presentation stays in modules/.
  castle.hardware.hasEthernet = lib.mkDefault false;

  # zramSwap only (see above): compressed RAM swap, no swap partition,
  # so there is nowhere to write a hibernation image. upower's own
  # default critical action is HybridSleep, which needs one — on this
  # machine that would mean a battery-critical event doing nothing
  # useful, or worse. PowerOff is the honest action for a swapless
  # host. modules/desktop asserts the hibernate-family actions are
  # refused on a machine with no swapDevices, whichever layer asked.
  castle.power.criticalPowerAction = lib.mkDefault "PowerOff";
}
