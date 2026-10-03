# test/direnv-delivery/test.nix — docs/tasks/0083: proves direnv's
# project environment actually reaches a non-interactive bash in both
# ancestries that never source a login shell's /etc/profile — the
# ancestry a BASH_ENV-only probe can tell apart from the
# `environment.variables` mechanism task 0013's bug 2 regressed on —
# and proves the re-entrancy guard holds against a real cold-cache
# nix evaluation, not a synthetic one.
#
# One node, through the REAL greetd+tuigreet login path
# (test/desktop-loop/test.nix's own pattern, trimmed to the minimal
# subset: modules/base, home, desktop, dev — no modules/agent, nothing
# this file doesn't need). Not `su -`: `su -` is itself a login shell
# and sources /etc/profile, which also carries BASH_ENV (NixOS folds
# `environment.sessionVariables` into `environment.variables` too, for
# an ordinary re-login with no restart) — a probe run under `su -`
# would pass even if the PAM-delivery path (`environment.
# sessionVariables` via pam_env.so) were broken, because the
# login-shell path would quietly cover for it. Only a command run as a
# true descendant of the greetd-launched Sway process — nothing in its
# ancestry a login shell — can fail on exactly the bug 2 regression
# this exists to catch. That is why every probe below goes through
# `swaymsg exec`, not `su -`: sway itself is launched directly by
# tuigreet, with no shell anywhere in that chain, so anything it execs
# inherits sway's own environment, assembled by PAM alone.
#
# The fixture flakes point their `nixpkgs` input at `path:${pkgs.path}`
# — this test's own pinned nixpkgs, already present in the shared
# host/guest store — so a cold `use flake` evaluates for real with no
# network and no separate pin to keep in sync.
{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Same throwaway, VM-only credential test/desktop-loop/test.nix uses
  # (see that file's header for how it was generated) — reused
  # verbatim rather than re-derived, since it is exactly as disposable
  # here as it is there.
  testPassword = "castle-turing-harness-password";
  testPasswordHash = "$6$castleturingtest$zio0DohVCoFAZ/ByLr3cUIhPge5lXZ0O1ylANx36BtdkaeKzOqdKht4KBROWu5o3dVZNyIG7UDKROXEl6WVjx0";
  testPasswordHashFile = pkgs.writeText "castle-direnv-delivery-password-hash" testPasswordHash;

  # A minimal flake per fixture project: no build inputs, so
  # instantiating its devShell needs nothing beyond evaluating
  # nixpkgs itself — no package has to be built inside the guest for
  # `nix print-dev-env` to read its environment back out.
  sampleFlake =
    marker:
    pkgs.writeText "direnv-test-flake-${marker}" ''
      {
        description = "direnv-delivery test fixture";
        inputs.nixpkgs.url = "path:${pkgs.path}";
        outputs = { self, nixpkgs }:
          let p = nixpkgs.legacyPackages.x86_64-linux; in {
            devShells.x86_64-linux.default = p.mkShellNoCC {
              MARKER = "${marker}";
            };
          };
      }
    '';
  sampleEnvrc = pkgs.writeText "direnv-test-envrc" "use flake\n";

  # Reads $MARKER (direnv's doing) and $EDITED_MARKER (set directly in
  # project-a's own .envrc, appended mid-test — see the "edit .envrc"
  # subtest) from a *freshly started, non-interactive* bash, inheriting
  # whatever cwd it's given. BASH_ENV only fires once, at a shell's own
  # startup, before any of its own commands run — so the `cd` has to
  # happen in an outer shell that then spawns this one, not inside it,
  # or the hook would fire against the wrong directory.
  probeScript = pkgs.writeShellScript "direnv-test-probe" ''
    set -eu
    cd "$1"
    bash -c 'printf "%s %s\n" "''${MARKER:-}" "''${EDITED_MARKER:-}"' >"$2"
  '';
in
{
  name = "direnv-delivery";

  node.pkgsReadOnly = false;
  enableOCR = true;

  nodes.machine =
    { config, pkgs, ... }:
    let
      swayHeadless = pkgs.writeShellScript "sway-headless" ''
        exec ${pkgs.coreutils}/bin/env WLR_RENDERER=pixman ${config.programs.sway.package}/bin/sway
      '';
    in
    {
      imports = [
        self.nixosModules.base
        self.nixosModules.home
        self.nixosModules.desktop
        self.nixosModules.dev
      ];

      system.stateVersion = config.system.nixos.release;

      castle.admin = {
        username = "resident";
        sshKeys = [ "ssh-ed25519 REPLACE-WITH-YOUR-PUBLIC-KEY this-is-a-placeholder-not-a-key" ];
        hashedPasswordFile = "${testPasswordHashFile}";
      };
      castle.person = {
        gitUserName = "Resident";
        gitUserEmail = "resident@example.invalid";
      };
      # modules/desktop asserts upower's HybridSleep default cannot
      # stand on a swapless machine (task 0020) — this VM has no swap.
      castle.power.criticalPowerAction = "PowerOff";

      # The resident's trust decision (Principle 01): project-a and
      # project-b are whitelisted, "other" deliberately is not.
      programs.direnv.settings.whitelist.prefix = [
        "/home/resident/projects/project-a"
        "/home/resident/projects/project-b"
      ];

      virtualisation.qemu.options = [ "-vga none -device virtio-gpu-pci" ];
      virtualisation.memorySize = 4096;
      virtualisation.cores = 2;

      services.greetd.settings.default_session.command =
        lib.mkForce "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd ${swayHeadless}";
    };

  testScript =
    { nodes, ... }:
    ''
      import datetime as dt

      machine.start()
      machine.wait_for_unit("multi-user.target")

      with subtest("fixtures: three projects, two of them whitelisted"):
          machine.succeed(
              "mkdir -p /home/resident/projects/project-a "
              "/home/resident/projects/project-b /home/resident/projects/other"
          )
          machine.succeed("install -m644 ${sampleFlake "project-a-marker"} /home/resident/projects/project-a/flake.nix")
          machine.succeed("install -m644 ${sampleFlake "project-b-marker"} /home/resident/projects/project-b/flake.nix")
          machine.succeed("install -m644 ${sampleFlake "other-marker"} /home/resident/projects/other/flake.nix")
          for proj in ("project-a", "project-b", "other"):
              machine.succeed(f"install -m644 ${sampleEnvrc} /home/resident/projects/{proj}/.envrc")
          machine.succeed("chown -R resident:users /home/resident/projects")

      with subtest("log in for real: type at the unmodified tuigreet prompt"):
          machine.wait_until_succeeds("pgrep -x tuigreet", timeout=dt.timedelta(minutes=2))
          machine.wait_for_text("sername")
          machine.screenshot("01-tuigreet-username-prompt")
          machine.send_chars("resident\n")
          machine.wait_for_text("assword")
          machine.screenshot("02-tuigreet-password-prompt")
          machine.send_chars("${testPassword}\n")
          sway_sock = machine.wait_until_succeeds(
              "su - resident -c 'ls /run/user/*/sway-ipc.*.sock'",
              timeout=dt.timedelta(minutes=3),
          ).strip()
          machine.screenshot("03-sway-session")

      def probe(project, out_path):
          # swaymsg exec asks the compositor itself — a direct,
          # shell-free child of the greetd-launched session — to run
          # this, so the probe's ancestry never crosses a login shell.
          machine.succeed(
              f"su - resident -c 'SWAYSOCK={sway_sock} swaymsg exec \"${probeScript} "
              f"/home/resident/projects/{project} {out_path}\"'"
          )
          machine.wait_until_succeeds(f"test -s {out_path}")
          return machine.succeed(f"cat {out_path}").strip()

      with subtest("a whitelisted project's non-interactive bash sees the marker, with no manual `direnv allow`"):
          since = machine.succeed("date '+%Y-%m-%d %H:%M:%S'").strip()
          result = probe("project-a", "/tmp/probe-a-cold.out")
          assert result.split() == ["project-a-marker"], result
          storm_count = machine.succeed(
              f"journalctl -u nix-daemon --no-pager --since '{since}' "
              "| grep -c 'accepted connection' || true"
          ).strip()
          assert storm_count == "1", (
              f"cold-cache direnv load should evaluate exactly once; saw {storm_count} "
              "nix-daemon connections — the BASH_ENV re-entrancy guard regressed"
          )

      with subtest("a warm cache re-probe of the same project touches nix-daemon zero more times"):
          since = machine.succeed("date '+%Y-%m-%d %H:%M:%S'").strip()
          result = probe("project-a", "/tmp/probe-a-warm.out")
          assert result.split() == ["project-a-marker"], result
          warm_count = machine.succeed(
              f"journalctl -u nix-daemon --no-pager --since '{since}' "
              "| grep -c 'accepted connection' || true"
          ).strip()
          assert warm_count == "0", f"warm-cache direnv load should not touch nix-daemon; saw {warm_count}"

      with subtest("a non-whitelisted project loads nothing"):
          result = probe("other", "/tmp/probe-other.out")
          assert result.split() == [], result

      with subtest("a shell that loaded project-a still loads project-b"):
          result = probe("project-b", "/tmp/probe-b.out")
          assert result.split() == ["project-b-marker"], result

      with subtest("editing .envrc still auto-loads, with no manual `direnv allow`"):
          machine.succeed(
              "su - resident -c \"printf 'export EDITED_MARKER=yes\\n' "
              ">> /home/resident/projects/project-a/.envrc\""
          )
          result = probe("project-a", "/tmp/probe-a-edited.out")
          assert result.split() == ["project-a-marker", "yes"], result

      with subtest("a systemd user unit sees the same environment"):
          machine.succeed(
              "su - resident -c 'XDG_RUNTIME_DIR=/run/user/$(id -u resident) "
              "systemd-run --user --quiet --wait --pipe --unit=castle-direnv-probe "
              "${probeScript} /home/resident/projects/project-b /tmp/probe-systemd.out'"
          )
          result = machine.succeed("cat /tmp/probe-systemd.out").strip()
          assert result.split() == ["project-b-marker"], result

      with subtest("direnv and nix-direnv are wired into interactive bash init"):
          bashrc = machine.succeed("cat /etc/bashrc")
          assert "direnv hook bash" in bashrc, bashrc
    '';
}
