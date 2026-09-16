# test/oomd-liveness/test.nix — docs/tasks/0073: proves the liveness
# check (castle-oomd-liveness-check) actually distinguishes systemd-oomd
# watching cgroups under both rules from watching neither, against a
# real systemd-oomd daemon in two booted VMs. Not a guess about what
# `oomctl dump` prints, and not a re-implementation of the check
# script: the exact generated script from
# `nixosConfigurations.example.config.systemd.services.
# castle-oomd-liveness-check.script` is injected into both nodes
# unmodified — test/password-reminder/check.nix's own pattern
# ("read the generated artifact"), applied here against a live daemon
# instead of a `pkgs.runCommand` table.
#
# Two nodes rather than one system rebuilt mid-test: systemd-oomd's
# ManagedOOMSwap/ManagedOOMMemoryPressure slice properties are read
# once when the slice activates, and there is no supported way to
# toggle them live and have oomd re-enumerate — a rebuild-and-switch
# mid-test would exercise switch-time behaviour nobody is asking about
# here, not the check.
#
#   - `wired`: the exact two settings task 0073 adds
#     (`systemd.oomd.enableUserSlices` and the root slice's
#     `ManagedOOMSwap = "kill"`) — the check must pass.
#   - `unwired`: systemd-oomd running with its NixOS defaults (neither
#     option set) — the literal 2026-09-06/2026-09-15 gap, reproduced
#     directly rather than asserted about. The check must fail.
#
# Deliberately does not import `hosts/xps9370` (its disko and
# hardware-configuration modules assume a real disk and firmware
# nixosTest's virtual hardware doesn't have — test/desktop-loop/
# test.nix's own header explains why no test in this repo imports a
# `hosts/*` module) or `modules/base` et al: the mechanism under test
# is generic NixOS/systemd-oomd behaviour plus the check script, not
# anything about this chassis, so nothing here needs the desktop
# closure's cost.
{ self }:
{ pkgs, lib, ... }:
let
  # The whole real service, not a hand-copied approximation of its
  # wrapper fields: `script` is the part this file's header promises
  # to inject unmodified, but `description`/`after`/`wants`/
  # `serviceConfig.Type` are just as real, and re-typing them here
  # would let hosts/xps9370/default.nix's actual wiring drift from
  # what this test exercises with nothing to catch it.
  liveService =
    self.nixosConfigurations.example.config.systemd.services.castle-oomd-liveness-check;

  checkModule = {
    systemd.services.castle-oomd-liveness-check = {
      inherit (liveService) description after wants script;
      serviceConfig.Type = liveService.serviceConfig.Type;
    };
  };
in
{
  name = "oomd-liveness";

  nodes.wired = {
    imports = [ checkModule ];
    systemd.oomd.enableUserSlices = true;
    systemd.slices."-".sliceConfig.ManagedOOMSwap = "kill";
  };

  nodes.unwired = {
    imports = [ checkModule ];
    # No oomd wiring at all beyond systemd-oomd's own NixOS defaults —
    # the literal state every host in this repo shipped in before task
    # 0063, reproduced here rather than assumed.
  };

  testScript = ''
    start_all()

    wired.wait_for_unit("multi-user.target")
    wired.succeed("systemctl start castle-oomd-liveness-check.service")

    unwired.wait_for_unit("multi-user.target")
    unwired.fail("systemctl start castle-oomd-liveness-check.service")
  '';
}
