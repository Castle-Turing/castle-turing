# test/eval-storm/test.nix — docs/tasks/0083: proves
# castle-eval-storm-check (modules/dev/eval-storm.nix) actually counts
# nix-daemon client connections and trips at the inclusive boundary
# (`count >= threshold`), against a real systemd --user instance and a
# real nix-daemon, driven by real `nix store ping` calls — not a
# re-implementation of the counting logic, and not a guess about what
# `journalctl -u nix-daemon` prints.
#
# Three nodes, each importing the real `modules/dev/eval-storm.nix`
# module directly (not a frozen config pulled from
# `nixosConfigurations.example`, unlike test/oomd-liveness/test.nix's
# own pattern): this module's options — threshold, windowMinutes,
# notifyCommand — are exactly what each scenario below needs to vary,
# so the thing under test *is* the module's response to different
# option values, not a single fixed artifact. The generated check
# script itself is still the real one `pkgs.writeShellScript` produces
# from the module's own source, never hand-copied.
#
# No graphical login anywhere in this file: `castle-eval-storm-check`
# is a `systemd.user.*` unit, and the established NixOS test idiom for
# driving one without a desktop session is `loginctl enable-linger` +
# `systemctl --user --machine=<user>@ <verb> <unit>` (confirmed against
# nixpkgs' own nixos/tests/systemd-user-tmpfiles-rules.nix, which uses
# exactly this to control lingering users' systemd instances from the
# test driver) plus `runuser -u <user> -- <command>` to act as that
# user. Deliberately does not import modules/base, modules/dev's own
# default.nix, or any hosts/* module: the mechanism under test is this
# one file's options and generated units, not the dev-tools closure or
# any host's hardware facts — test/oomd-liveness/test.nix's own header
# gives the identical reasoning for the same omission.
#
# No `{ self }:` outer wrapper, unlike the other two VM tests in this
# repo: this one needs nothing from the flake's own evaluated outputs
# (it imports the module source directly), so `runNixOSTest` is handed
# this file's module directly in flake.nix rather than a call through
# an intermediate function.
{ lib, pkgs, ... }:
let
  # The stub notifyCommand: records that it ran, and with what
  # arguments, rather than actually raising a desktop notification —
  # the same file-touching stub shape this repo already uses to
  # observe a fired side effect without a real notifier
  # (test/agent-loop's worker/notify stand-ins).
  stubNotify = pkgs.writeShellScript "castle-eval-storm-test-notify" ''
    printf '%s\n' "$1: $2" > /tmp/castle-eval-storm-notified
  '';

  testerModule = {
    users.users.tester = {
      isNormalUser = true;
      uid = 1000;
    };
    imports = [ ../../modules/dev/eval-storm.nix ];
  };

  # A small threshold and a window generously longer than this test's
  # own runtime — the point is the boundary arithmetic
  # (`count >= threshold`), not reproducing either founding incident's
  # real rate, which test/oomd-liveness-equivalent calibration numbers
  # (recorded in modules/dev/eval-storm.nix's own option docs) already
  # cover.
  threshold = 3;
  windowMinutes = 5;
in
{
  name = "eval-storm";

  nodes.over = {
    imports = [ testerModule ];
    castle.evalStorm = {
      inherit threshold windowMinutes;
      notifyCommand = "${stubNotify}";
    };
  };

  nodes.under = {
    imports = [ testerModule ];
    castle.evalStorm = {
      inherit threshold windowMinutes;
      notifyCommand = "${stubNotify}";
    };
  };

  nodes.nullNotify = {
    imports = [ testerModule ];
    castle.evalStorm = {
      inherit threshold windowMinutes;
      # The shipped default — deliberately left unset here rather than
      # stubbed, so this node proves the floor every host gets: a
      # loud, nonzero unit exit with no notifier configured at all.
    };
  };

  testScript = ''
    import time

    for m in (over, under, null_notify):
        m.start()
        m.wait_for_unit("multi-user.target")
        m.succeed("loginctl enable-linger tester")
        m.wait_until_succeeds("systemctl --user --machine=tester@ is-system-running")

    with subtest("count >= threshold trips the check and fires the notifier"):
        for _ in range(threshold):
            over.succeed("runuser -u tester -- nix store ping")
        over.fail("systemctl --user --machine=tester@ start castle-eval-storm-check.service")
        over.succeed(
            "journalctl --user-unit=castle-eval-storm-check.service | grep -q 'at or above threshold'"
        )
        over.succeed("runuser -u tester -- cat /tmp/castle-eval-storm-notified")

    with subtest("count below threshold stays quiet and fires nothing"):
        for _ in range(threshold - 1):
            under.succeed("runuser -u tester -- nix store ping")
        under.succeed("systemctl --user --machine=tester@ start castle-eval-storm-check.service")
        under.fail("runuser -u tester -- test -e /tmp/castle-eval-storm-notified")

    with subtest("the shipped default (notifyCommand unset) still fails loudly, and the script itself does not crash"):
        for _ in range(threshold):
            null_notify.succeed("runuser -u tester -- nix store ping")
        null_notify.fail("systemctl --user --machine=tester@ start castle-eval-storm-check.service")
        # "does not crash" means the script ran to its own `exit 1`,
        # not that it died earlier (a missing binary, a syntax error) —
        # the count line on stdout only appears if it got that far.
        null_notify.succeed(
            "journalctl --user-unit=castle-eval-storm-check.service "
            + f"| grep -q '{threshold} nix-daemon connection'"
        )
  '';
}
