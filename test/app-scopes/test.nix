# test/app-scopes/test.nix — docs/tasks/0084: boot the real desktop
# stack in a NixOS VM, log in through the real greetd+tuigreet prompt,
# launch an application down each of the three real app-launch paths,
# and assert that each one lands in a transient scope cgroup of its own
# rather than sharing the compositor's.
#
# This is the detector the incident ships. Before task 0084 every GUI
# application inherited Sway's cgroup by fork, so logind's session
# scope held the whole desktop as one leaf — and systemd-oomd kills
# leaf cgroups, which is why the first live kill on this project's own
# machine took the compositor and two running agent sessions with it.
# The fix is a topology change, and a topology silently collapsing back
# to one leaf looks, from the outside, exactly like a quiet day. Only a
# check outlives the memory of the incident.
#
# What this test is NOT: it never fires an oomd rule and never measures
# which cgroup actually dies under memory pressure. That is the full
# memory-exhaustion drill, and it stays with
# docs/backlog/the-kernel-oom-killer-has-no-swap-headroom.md where it
# is already proposed. This is the cheap static probe that the topology
# is right, which is all task 0084 changes.
#
# Deliberately a `packages.*` output with its own path-filtered
# workflow, not a `checks.*` one: `nix flake check` is the fast gate
# that runs unfiltered on every pull request, and it must never boot a
# VM. Same division of labor test/desktop-loop/ and test/oomd-liveness/
# already established — see flake.nix's own comments at those outputs.
# The *cheap* half of this detector does run on every pull request:
# check.yml's sway-config-check greps the generated Sway config for all
# three wrapped bindings. Neither half replaces the other. That one
# would stay green if systemd-run stopped producing scopes at all;
# this one is far too slow to run on every push.
#
# Mirrors test/desktop-loop/test.nix rather than extending it. The
# login sequence, the WLR_RENDERER wrapper and the Sway-over-IPC
# assertions are that file's, copied because they are proven; what is
# deliberately not copied is its closure (no modules/dev, no Emacs, no
# claude-code) and its subject matter. A detector folded into a
# seventy-five-minute test that already carries five other tasks is a
# worse detector: slower to answer, and silent whenever that test is
# red for an unrelated reason.
#
# The two departures from a real deployment are desktop-loop's own, for
# the same single reason (there is no GPU in this VM) and nothing else:
# a virtio-gpu KMS device via `virtualisation.qemu.options`, and
# `WLR_RENDERER=pixman` injected by wrapping the exact `sway` binary
# tuigreet is told to launch. Read that file's header for why a
# system-wide `environment.variables` does not reach a greetd session.
{ self }:
{ pkgs, lib, ... }:
let
  # The same obviously-synthetic, published VM-only credential
  # test/desktop-loop/test.nix uses, and the same reasoning: see that
  # file's comment on testPassword. Generated with
  #   openssl passwd -6 -salt castleturingtest 'castle-turing-harness-password'
  # and kept as a literal so this file needs no openssl at eval time.
  testPassword = "castle-turing-harness-password";
  testPasswordHash = "$6$castleturingtest$zio0DohVCoFAZ/ByLr3cUIhPge5lXZ0O1ylANx36BtdkaeKzOqdKht4KBROWu5o3dVZNyIG7UDKROXEl6WVjx0";
  testPasswordHashFile = pkgs.writeText "castle-app-scopes-password-hash" testPasswordHash;

  # castle-modal reads its journal out of this directory, and the
  # window the Castle chord opens has to actually stay up for the test
  # to read its cgroup. Supplied the same way test/desktop-loop/ does
  # (tmpfiles, not an activation script) because a real host's private
  # repo is a clone the resident made — see that file's comment.
  testStateDir = "/home/resident/private/state";

  # The payload the launcher's pick executes. A test-only program, the
  # same way test/desktop-loop/'s scripted worker is: what is under
  # test here is the launch *path*, not the thing launched, and the
  # path needs a payload that is uniquely findable by name and does not
  # exit. `dmenu_path` lists basenames off $PATH, so putting this in
  # environment.systemPackages is what makes it selectable in the real
  # launcher.
  #
  # It reports its own pid into a file rather than being found with
  # `pgrep`, and that is not fussiness: every process in the launch
  # chain carries the app's name on its command line — the `swaymsg
  # exec` that sends the pick, the `sh -c` Sway spawns for it,
  # `castle-launch`, and `systemd-run` — so `pgrep -f` reliably
  # matched one of those instead, and they are all gone moments later.
  # The pid file names exactly one process and cannot race.
  #
  # `exec` preserves the pid, so the number written before it is the
  # pid of the live `sleep`, and reading its cgroup reads the scope.
  probePidFile = "/tmp/castle-scope-probe-app.pid";
  probeApp = pkgs.writeShellScriptBin "castle-scope-probe-app" ''
    echo $$ > ${probePidFile}
    exec ${pkgs.coreutils}/bin/sleep infinity
  '';
in
{
  name = "app-scopes";

  # Same escape hatch and same reason as test/desktop-loop/test.nix and
  # nixpkgs' own nixos/tests/sway.nix: the driver's mypy pass cannot
  # narrow this script's `swaymsg` and tree-walking helpers.
  skipTypeCheck = true;

  # Only for the two tuigreet prompts, which are the one moment in a
  # headless compositor login with no structured signal to wait on.
  # Everything after Sway starts asserts over Sway's own IPC socket,
  # /proc, or systemd — never pixels.
  enableOCR = true;

  nodes.machine =
    { config, pkgs, ... }:
    let
      # Departure 2 — see this file's header, and
      # test/desktop-loop/test.nix's much longer note on why this is a
      # wrapper script rather than an `env ...` string threaded through
      # greetd's and tuigreet's two separate parsers.
      swayHeadless = pkgs.writeShellScript "sway-headless" ''
        exec ${pkgs.coreutils}/bin/env WLR_RENDERER=pixman ${config.programs.sway.package}/bin/sway
      '';
    in
    {
      # modules/dev is deliberately absent (nothing here needs Emacs or
      # claude-code), and no hosts/* module is imported — nixosTest
      # supplies its own virtual hardware profile. modules/agent is
      # here for one reason: it installs `castle-modal`, without which
      # the Castle chord's foot window exits immediately and there is
      # no third launch path to measure.
      imports = [
        self.nixosModules.base
        self.nixosModules.home
        self.nixosModules.desktop
        self.nixosModules.agent
      ];

      system.stateVersion = "26.11";

      # This node imports modules/desktop but no host module, so nothing
      # else states what a swapless machine should do at critical
      # battery, and modules/desktop asserts that upower's HybridSleep
      # default cannot stand there (task 0020). Inert in a VM with no
      # battery; declared to satisfy the same honesty the assertion
      # enforces everywhere else.
      castle.power.criticalPowerAction = "PowerOff";

      castle.admin = {
        username = "resident";
        sshKeys = [ "ssh-ed25519 REPLACE-WITH-YOUR-PUBLIC-KEY this-is-a-placeholder-not-a-key" ];
        hashedPasswordFile = "${testPasswordHashFile}";
      };
      castle.person = {
        gitUserName = "Resident";
        gitUserEmail = "resident@example.invalid";
      };

      # No `castle.agent.dispatch.enable` here: this test never files a
      # record, so nothing should be watching for one. castle-modal
      # only needs its state directory to exist to open its inbox.
      castle.agent.stateDir = testStateDir;
      systemd.tmpfiles.rules = [
        "d /home/resident/private 0755 resident users -"
        "d ${testStateDir} 0755 resident users -"
      ];

      environment.systemPackages = [ probeApp ];

      # Departure 1 — see this file's header.
      virtualisation.qemu.options = [ "-vga none -device virtio-gpu-pci" ];
      # Sway, XWayland (the launcher is an X11 program), two terminals
      # and a Python modal. Lighter than test/desktop-loop/'s full
      # desktop closure, so a smaller budget than its 4096 — but not so
      # small that an OOM inside the VM becomes the thing this test
      # reports, which would be a particularly confusing way for a
      # test about memory kills to fail.
      virtualisation.memorySize = 3072;
      virtualisation.cores = 2;

      # Departure 2 — see this file's header. Otherwise byte-for-byte
      # modules/desktop's own `default_session.command`: the
      # `--time --remember --cmd` flags are unchanged, only what
      # `--cmd` resolves to differs.
      services.greetd.settings.default_session.command =
        lib.mkForce "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd ${swayHeadless}";
    };

  testScript = ''
    import datetime as dt
    import json
    import re

    start_all()
    machine.wait_for_unit("multi-user.target")

    # --- Log in for real: type at the real, unmodified tuigreet -------
    machine.wait_until_succeeds("pgrep -x tuigreet", timeout=dt.timedelta(minutes=2))
    machine.wait_for_text("sername")
    machine.screenshot("01-tuigreet-username-prompt")
    machine.send_chars("resident\n")
    machine.wait_for_text("assword")
    machine.send_chars("${testPassword}\n")

    SWAYSOCK = machine.wait_until_succeeds(
        "su - resident -c 'ls /run/user/*/sway-ipc.*.sock'",
        timeout=dt.timedelta(minutes=3),
    ).strip()
    machine.screenshot("02-sway-session")


    def swaymsg(query_type):
        shell = f"SWAYSOCK={SWAYSOCK} swaymsg -t {query_type}"
        return json.loads(machine.succeed(f"su - resident -c '{shell}'"))


    version = swaymsg("get_version")
    assert "sway" in json.dumps(version).lower(), f"get_version did not look like Sway: {version}"
    print(f"OK: Sway session confirmed live over its own IPC socket: {version}")

    NODE_GROUPS = ["nodes", "floating_nodes"]


    def walk(tree):
        yield tree
        for group in NODE_GROUPS:
            for node in tree.get(group, []):
                yield from walk(node)


    def window_pid(app_id):
        """The pid of the client owning the window with this app_id, if any.

        Sway reports it in its own tree, so nothing here has to guess at
        a process name or race `pgrep` against a window that has not
        mapped yet."""
        for node in walk(swaymsg("get_tree")):
            if node.get("app_id") == app_id and node.get("pid"):
                return node["pid"]
        return None


    def cgroup_of(pid):
        # The whole v2 line, "0::<path>" — not just the path — so a
        # host that somehow produced v1 controller lines here would
        # fail the format assertions below rather than silently pass a
        # substring match.
        return machine.succeed(f"cat /proc/{pid}/cgroup").strip()


    # --- Where the compositor lives, and the sanity of the comparison -
    # Task 0084 §3: sway itself deliberately stays in logind's session
    # scope, so a kill leaves something able to render what happened.
    # Asserting that here is not decoration — it is what makes every
    # "different from the compositor's cgroup" assertion below mean
    # something. If sway had been moved into a run-*.scope too, those
    # comparisons would still pass while proving nothing.
    sway_pid = machine.succeed("pgrep -x sway").strip().splitlines()[0]
    compositor_cgroup = cgroup_of(sway_pid)
    assert re.fullmatch(r"0::/user\.slice/user-\d+\.slice/session-\d+\.scope", compositor_cgroup), (
        "the compositor is not in logind's session scope, which is where task 0084 "
        f"says it stays: {compositor_cgroup}"
    )
    print(f"OK: the compositor is in the session scope: {compositor_cgroup}")

    # Every app-launch path, each one driven by the real chord a
    # resident presses. The terminal path is the one that matters most
    # and is NOT optional: the kill this task comes from was triggered
    # by an agent session inside a terminal, not by a browser, so a
    # probe that only covered the Castle chord would detect nothing
    # about the incident it ships with.
    launched = {}

    # 1. The launcher, modifier+d — `dmenu_path | dmenu | xargs swaymsg
    #    exec -- castle-launch menu --`. Driving the real pipeline is
    #    the point: only the exec half is wrapped, and a future edit
    #    that wrapped the filter instead would leave systemd-run
    #    between the two pipes and break the pick entirely. That shows
    #    up here as no probe app ever starting.
    #
    #    FIRST, before any other window exists. The launcher is an
    #    override-redirect X11 client under XWayland, and with a foot
    #    window already open and focused this test's own keystrokes
    #    went to that terminal's shell instead — which still started
    #    the probe app, in the terminal's cgroup, and so read as the
    #    menu path sharing a scope. With nothing else mapped there is
    #    nowhere else for them to land.
    machine.send_key("alt-d")
    machine.wait_until_succeeds("pgrep -x dmenu", timeout=dt.timedelta(minutes=2))
    # Alive a moment later, not merely spawned: every member of a shell
    # pipeline starts at once, so `pgrep` finds dmenu before it has
    # even tried to open a display. A launcher that exited for want of
    # one would otherwise be indistinguishable from a launcher waiting
    # for input.
    machine.sleep(2)
    machine.succeed("pgrep -x dmenu")
    machine.screenshot("03-launcher")
    machine.send_chars("castle-scope-probe-app\n")
    launched["menu"] = int(
        machine.wait_until_succeeds(
            "cat ${probePidFile}", timeout=dt.timedelta(minutes=2)
        ).strip()
    )

    # 2. The terminal, home-manager's own modifier+Return binding. The
    #    default modifier is Mod1 (alt); this test does not override it,
    #    so the chord under test is exactly the one a stock config has.
    machine.send_key("alt-ret")
    retry(lambda last: window_pid("foot") is not None)
    launched["terminal"] = window_pid("foot")
    machine.screenshot("04-terminal")

    # 3. The Castle chord, Mod4+Shift+Return — the one launch path with
    #    no home-manager option behind it, wrapped at the binding.
    machine.send_key("meta_l-shift-ret")
    retry(lambda last: window_pid("castle-modal") is not None)
    launched["modal"] = window_pid("castle-modal")
    machine.screenshot("05-modal")

    # --- The assertion this whole file exists for ---------------------
    cgroups = {}
    for path, pid in launched.items():
        cgroup = cgroup_of(pid)
        assert re.fullmatch(r"0::/user\.slice/.*/run-[^/]+\.scope", cgroup), (
            f"the {path} launch did not land in a transient scope under user.slice "
            f"(pid {pid}): {cgroup}. An app sharing one cgroup with the rest of the "
            "session is what makes systemd-oomd's only eligible victim the whole "
            "desktop — see docs/tasks/0084-an-oomd-kill-takes-the-whole-desktop.md."
        )
        assert cgroup != compositor_cgroup, (
            f"the {path} launch is in the compositor's own cgroup ({cgroup}); "
            "an oomd kill against it would take Sway down too."
        )
        cgroups[path] = cgroup

    assert len(set(cgroups.values())) == len(cgroups), (
        "two app-launch paths share one cgroup, so a kill against either takes "
        f"both: {cgroups}"
    )

    for path, cgroup in sorted(cgroups.items()):
        print(f"OK: the {path} launch has its own scope: {cgroup}")
  '';
}
