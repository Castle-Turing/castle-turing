# The real nixosConfiguration one harness run installs: the published
# mechanism (modules/base + hosts/vm-test) plus one throwaway admin key
# generated fresh by run.sh for this run only — never committed, never a
# real resident. Same shape a private layer would supply
# (docs/private-layer.md), for test purposes only.
#
# Also imports the published modules/desktop (docs/tasks/0005), so
# run.sh's phase 2 can assert the two things a GUI can't be driven
# headlessly but its startup can: the graphical target is reached and
# Sway's IPC socket appears. The one deliberate departure from the real
# module is test-only auto-login (below) — modules/desktop itself never
# auto-logs in (see its header comment); a harness VM nobody can steal
# has no equivalent of that threat model, and "zero console interaction"
# is this whole harness's point (docs/tasks/0003-findings.md finding
# #1), so the assertion needs a session to start without anyone typing a
# password at tuigreet. `WLR_BACKENDS=headless` is the standard way to
# run a wlroots compositor with no real display or GPU present.
#
# --impure only because of the getFlake self-reference (needed to pick up
# uncommitted working-tree changes under test, same as `nix flake check`
# would see) and the pubkey argument read from a file run.sh generates.
# The framework mechanism itself — modules/base, modules/desktop,
# hosts/vm-test, modules/disk-layout.nix — is evaluated exactly as
# published.
{
  pubkeyFile,
}:
let
  flake = builtins.getFlake (toString ../..);
  lib = flake.inputs.nixpkgs.lib;
  pubkey = lib.fileContents pubkeyFile;
in
flake.inputs.nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    flake.nixosModules.base
    flake.nixosModules.desktop
    flake.nixosModules.host-vm-test
    {
      castle.admin = {
        username = "harness";
        sshKeys = [ pubkey ];
        # "!" (locked/no-password shadow syntax) rather than a real
        # hash: modules/desktop asserts this is set (see its header
        # comment on finding #1), but the harness never types a
        # password at any prompt — see the auto-login override below —
        # so the value only needs to exist, not to work.
        initialHashedPassword = "!";
      };
    }
    (
      { config, pkgs, ... }:
      {
        # Test-only auto-login: sway starts on the console the moment
        # greetd comes up, no credentials typed anywhere. See the file
        # header for why this override belongs here and not in
        # modules/desktop. Full store paths (not bare `env`/`sway`,
        # relying on $PATH) because greetd spawns this directly, with
        # whatever minimal environment its own service unit has.
        services.greetd.settings.initial_session = {
          command = "${pkgs.coreutils}/bin/env WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 ${config.programs.sway.package}/bin/sway";
          user = config.castle.admin.username;
        };
      }
    )
  ];
}
