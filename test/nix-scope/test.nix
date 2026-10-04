# test/nix-scope/test.nix — docs/tasks/0089: proves the nix-client
# scope wrapper (modules/dev/nix-scope.nix) actually descopes a memory
# kill — a real nix evaluation driven past a real MemoryMax dies
# alone, by SIGKILL, inside a transient scope of its own, while the
# shell that invoked it survives, keeps executing, and receives the
# wrapper's explanation on stderr. Not a re-implementation of the
# wrapper's logic: every probe goes through PATH resolution against
# the real merged system profile, exactly the way an agent's bash
# call would.
#
# One node, importing modules/dev/nix-scope.nix directly — the same
# reasoning as test/eval-storm/test.nix's header: the thing under
# test is this one module's options and generated wrapper, not the
# dev-tools closure or any host's facts, so modules/base, the rest of
# modules/dev, and hosts/* stay out. The one fact a real host gets
# from elsewhere and this fixture reproduces by hand: a normal user
# with a lingering user manager (the wrapper needs a reachable
# `systemd --user` to register scopes with; `loginctl enable-linger`
# plus `systemctl --user --machine=<user>@` is the established
# driver-side idiom, per eval-storm's header).
#
# Scope placement is observed, not inferred: a wrapped evaluation is
# parked on a blocking stdin read, and the driver reads that live
# process's /proc/<pid>/cgroup. (Not `builtins.readFile
# "/proc/self/cgroup"` from inside the evaluator — procfs files
# stat as zero-length, which readFile-style primops are entitled to
# take at face value.)
{ pkgs, ... }:
let
  # The runaway: force a list far larger than the scope's MemoryMax
  # allows. 400M elements would want gigabytes; the cap below kills
  # the evaluator long before that. A real nix client being killed by
  # the real kernel at the real bound — not a stub hog.
  runawayExpr = "builtins.length (builtins.genList (x: x) 400000000)";

  # Parks a wrapped evaluator: readFile on stdin blocks until the
  # 60-second sleep upstream closes the pipe, leaving a live nix
  # process whose cgroup the driver can read at leisure. The script
  # exits immediately (the pipeline is backgrounded and orphaned);
  # the driver finds the evaluator by pid afterwards.
  parkScript = pkgs.writeShellScript "nix-scope-park" ''
    sleep 60 | nix eval --extra-experimental-features nix-command --impure \
      --expr 'builtins.readFile "/dev/stdin"' >/dev/null 2>&1 &
  '';

  # The wrapper script's own comm is also `nix` (a shebang script
  # carries its script name), so pgrep alone is ambiguous between the
  # wrapper shell and the real evaluator. The real one is the ELF
  # whose /proc/<pid>/exe ends in bin/nix; the wrapper's exe is bash.
  findEvaluator = pkgs.writeShellScript "nix-scope-find-evaluator" ''
    for p in $(pgrep -u tester -x nix); do
      if readlink -f "/proc/$p/exe" 2>/dev/null | grep -q 'bin/nix$'; then
        cat "/proc/$p/cgroup"
        exit 0
      fi
    done
    exit 1
  '';

  # Driven as the tester user with the user manager reachable. The
  # wrapper's own fallback conditions are exactly what the env here
  # satisfies (non-root, XDG_RUNTIME_DIR pointing at a live manager) —
  # and what the root probe below deliberately does not.
  probeScript = pkgs.writeShellScript "nix-scope-probe" ''
    set -u
    nix eval --extra-experimental-features nix-command \
      --expr '${runawayExpr}' \
      > /tmp/nix-scope-probe-out 2> /tmp/nix-scope-probe-err
    rc=$?
    # These lines are the point: they only run if this shell survived
    # the kill that just happened one scope over.
    echo "rc=$rc" > /tmp/nix-scope-probe-result
    echo "survived" >> /tmp/nix-scope-probe-result
  '';
in
{
  name = "nix-scope";

  nodes.machine = {
    imports = [ ../../modules/dev/nix-scope.nix ];
    users.users.tester = {
      isNormalUser = true;
      uid = 1000;
    };
    # `nix eval` needs the nix-command feature — normally on via
    # modules/base, which this test deliberately does not import.
    nix.settings.experimental-features = [ "nix-command" ];
    castle.nixScope = {
      # Small enough that the runaway dies in moments, large enough
      # that the evaluator starts up and begins allocating. A
      # calibration value for this fixture only — hosts set their own
      # (Principle 01).
      memoryMax = "192M";
      memorySwapMax = "64M";
    };
    virtualisation.memorySize = 2048;
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("loginctl enable-linger tester")
    machine.wait_until_succeeds("systemctl --user --machine=tester@ is-system-running")

    # Every tester probe needs the user manager reachable; runuser
    # alone does not set XDG_RUNTIME_DIR, so each probe states it.
    env = "XDG_RUNTIME_DIR=/run/user/1000"


    def parked_cgroup(extra_env=""):
        """Park a wrapped evaluation, return the evaluator's cgroup, clean up."""
        machine.succeed(f"runuser -u tester -- env {env} {extra_env} ${parkScript}")
        cg = machine.wait_until_succeeds("${findEvaluator}")
        machine.succeed("pkill -u tester -x nix || true; pkill -u tester -x sleep || true")
        machine.wait_until_fails("pgrep -u tester -x nix")
        return cg


    with subtest("the wrapper wins PATH resolution over the real nix client"):
        # Content-based, not name-based: the wrapper's store path is
        # also named `nix`, so resolve the symlink chain and look for
        # the wrapper's own marker in the script text.
        machine.succeed(
            "grep -q CASTLE_NIX_IN_SCOPE \"$(readlink -f \"$(command -v nix)\")\""
        )

    with subtest("a wrapped evaluation is transparent"):
        out = machine.succeed(
            f"runuser -u tester -- env {env} nix eval"
            " --extra-experimental-features nix-command --expr '1 + 1'"
        )
        assert out.strip() == "2", f"wrapped nix eval returned {out!r}, not 2"

    with subtest("the evaluator runs in a transient scope of its own under the user manager"):
        cg = parked_cgroup()
        assert "user@1000.service" in cg and "run-" in cg and ".scope" in cg, (
            f"evaluator cgroup is not a user-manager transient scope: {cg!r}"
        )

    with subtest("a runaway evaluation dies alone; the invoking shell survives and is told why"):
        machine.succeed(f"runuser -u tester -- env {env} ${probeScript}")
        result = machine.succeed("cat /tmp/nix-scope-probe-result")
        assert "rc=137" in result, (
            f"expected the runaway to die by SIGKILL (rc=137): {result!r}"
        )
        assert "survived" in result, f"probe shell did not survive: {result!r}"
        machine.succeed("grep -q 'castle-nix-scope:' /tmp/nix-scope-probe-err")
        # The kill was the kernel's cgroup OOM at the scope's
        # MemoryMax, on record — not an incidental crash.
        machine.succeed("journalctl -k | grep -qi 'memory cgroup out of memory'")

    with subtest("root falls back to direct exec and still works"):
        # nixos-rebuild runs nix as root, where no user manager is
        # reachable (user@0 is not running here) — so mere success
        # proves the wrapper took the direct path: the scope path
        # would have failed to connect before nix ever ran.
        out = machine.succeed(
            "nix eval --extra-experimental-features nix-command --expr '1 + 1'"
        )
        assert out.strip() == "2", f"root nix eval returned {out!r}, not 2"

    with subtest("CASTLE_NIX_SCOPE_DISABLE opts a single invocation out"):
        cg = parked_cgroup(extra_env="CASTLE_NIX_SCOPE_DISABLE=1")
        assert "user@1000.service" not in cg, (
            f"opted-out evaluation still landed in a user-manager scope: {cg!r}"
        )
  '';
}
