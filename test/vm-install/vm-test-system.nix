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
# It also imports the published modules/secrets
# (docs/tasks/0031-secrets-tooling.md) and declares one fixture secret,
# so phase 2c can prove the whole encrypted-secrets pipeline on a real
# machine: run.sh encrypts the fixture to a throwaway age key, plants
# that key with `nixos-anywhere --extra-files`, and the installed
# system's own first activation decrypts it with nobody at any keyboard.
# The Wi-Fi half of that task cannot be tested here — QEMU's `-nic user`
# is wired-Ethernet-equivalent, there is no radio to join anything with
# — so what this harness proves is the plumbing underneath it, which is
# the half this project actually wrote.
#
# --impure only because of the getFlake self-reference (needed to pick up
# uncommitted working-tree changes under test, same as `nix flake check`
# would see) and the pubkey/secrets arguments read from files run.sh
# generates. The framework mechanism itself — modules/base,
# modules/desktop, modules/secrets.nix, hosts/vm-test,
# modules/disk-layout.nix — is evaluated exactly as published.
{
  pubkeyFile,
  secretsFile,
}:
let
  flake = builtins.getFlake (toString ../..);
  lib = flake.inputs.nixpkgs.lib;
  pubkey = lib.fileContents pubkeyFile;
  # A Nix *path* built from the string run.sh passes in, not the string
  # itself: sops-nix's manifest refuses a secrets file that is not in
  # the Nix store (short of turning validateSopsFiles off, which this
  # harness will not do — see flake.nix's own comment on why that
  # option's honest default is the reason nothing permanent is
  # committed), and a path value is what gets it copied there. Copying
  # *ciphertext* into a world-readable store is the intended
  # distribution mechanism, per modules/secrets.nix's option
  # description; the age key that opens it is the thing that never goes
  # near an evaluation.
  secretsPath = /. + secretsFile;
in
flake.inputs.nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    flake.nixosModules.base
    flake.nixosModules.desktop
    flake.nixosModules.host-vm-test
    flake.nixosModules.secrets
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

      # The public slot, filled the same way a private layer fills it.
      # castle.secrets.ageKeyFile is deliberately left at its default:
      # run.sh stages the key at exactly that path, and a harness that
      # overrode it here would stop testing the agreement between the
      # documented default and the documented install step, which is
      # the pair most likely to drift apart.
      castle.secrets.sopsFile = secretsPath;

      # One secret, whose plaintext value run.sh knows because run.sh
      # invented it moments earlier. `{ }` takes every default: key
      # "harness-fixture" out of the YAML, rendered to
      # /run/secrets/harness-fixture, root-owned, mode 0400.
      sops.secrets."harness-fixture" = { };
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
