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
  # The runaway: grow memory in ~8M chunks, accumulated so nothing
  # can be collected, far past the scope's MemoryMax. Chunked, not
  # one oversized genList: a single multi-gigabyte allocation in a
  # 2G guest is refused by the kernel's overcommit heuristic
  # (ENOMEM, exit 1) before the cgroup cap ever matters — observed
  # on this test's own first CI run — while chunks well under guest
  # RAM commit page by page until the cgroup kill fires, which is
  # also how a real evaluation's footprint actually grows on a host
  # whose RAM exceeds the cap. A real nix client killed by the real
  # kernel at the real bound — not a stub hog.
  # No apostrophes anywhere in the expression — it is interpolated
  # into a single-quoted shell argument in probeScript, and foldl's
  # primed name has already broken that once (writeShellScript's own
  # syntax check caught it).
  runawayExpr =
    "let cs = builtins.genList (i: builtins.genList (x: x) 1000000) 1000; in builtins.deepSeq cs (builtins.length cs)";

  # Parks a wrapped evaluator: readFile on stdin blocks until the
  # 60-second sleep upstream closes the pipe, leaving a live nix
  # process whose cgroup the driver can read at leisure. The script
  # exits immediately (the pipeline is backgrounded and orphaned);
  # the driver finds the evaluator by pid afterwards. `$!` after a
  # backgrounded pipeline is its last element — the `nix` wrapper —
  # recorded so the orphan subtest can kill exactly the pid a
  # harness would hold, with no comm/exe guesswork.
  parkScript = pkgs.writeShellScript "nix-scope-park" ''
    sleep 60 | nix eval --extra-experimental-features nix-command --impure \
      --expr 'builtins.readFile "/dev/stdin"' >/dev/null 2>&1 &
    echo $! > /tmp/nix-scope-wrapper-pid
  '';

  # Same parking trick for an interactive-class invocation: a repl on
  # a piped stdin blocks reading its first command. The wrapper must
  # have direct-exec'd this one (interactive exemption), so it stays
  # in the caller's cgroup rather than a transient scope.
  parkReplScript = pkgs.writeShellScript "nix-scope-park-repl" ''
    sleep 60 | nix repl --extra-experimental-features nix-command >/dev/null 2>&1 &
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

  # The wrapper bash's pid: the evaluator's parent. Not found via
  # pgrep -x nix — a shebang script's comm is its interpreter, not
  # the script name, so the wrapper is invisible to a comm match
  # (the evaluator, a real ELF, has comm `nix`). The evaluator's
  # PPid is the wrapper that backgrounded it, which is exactly the
  # pid a harness holds and would kill.
  findWrapperPid = pkgs.writeShellScript "nix-scope-find-wrapper" ''
    for p in $(pgrep -u tester -x nix); do
      if readlink -f "/proc/$p/exe" 2>/dev/null | grep -q 'bin/nix$'; then
        awk '{print $4}' "/proc/$p/stat"
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
    # The NixOS test guest defaults to vm.panic_on_oom=2, which
    # panics the whole kernel on *any* OOM — including a
    # cgroup-contained one, the very event under test. On a real
    # host panic_on_oom is 0 and a cgroup OOM kills only the
    # offending process inside its scope, leaving the box up; this
    # mirrors that regime so the descoping can be observed rather
    # than crashing the guest. Confirmed necessary: the cgroup kill
    # fired correctly (oom-killer named run-*.scope) and the guest
    # panicked anyway on the first chunked-runaway run.
    boot.kernel.sysctl."vm.panic_on_oom" = 0;
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
    # running OR degraded: is-system-running exits nonzero on
    # `degraded` forever, so the bare spelling burns the whole retry
    # timeout if any incidental user unit failed at linger startup —
    # the manager is up and usable either way (review finding; the
    # same latent flake exists verbatim in test/eval-storm/test.nix).
    machine.wait_until_succeeds(
        "systemctl --user --machine=tester@ is-system-running 2>/dev/null"
        " | grep -Eq '^(running|degraded)$'"
    )

    # Every tester probe needs the user manager reachable; runuser
    # alone does not set XDG_RUNTIME_DIR, so each probe states it.
    env = "XDG_RUNTIME_DIR=/run/user/1000"


    def parked_cgroup(park="${parkScript}", extra_env=""):
        """Park a wrapped nix process, return its cgroup, clean up."""
        machine.succeed(f"runuser -u tester -- env {env} {extra_env} {park}")
        cg = machine.wait_until_succeeds("${findEvaluator}")
        machine.succeed("pkill -u tester -x nix || true; pkill -u tester -x sleep || true")
        machine.wait_until_fails("pgrep -u tester -x nix")
        return cg


    with subtest("the wrapper wins PATH resolution over the real nix client"):
        # The property, not an implementation spelling (review
        # finding): what PATH resolves to must be a script — the real
        # client is an ELF whose first bytes are not a shebang.
        machine.succeed(
            "head -c 2 \"$(readlink -f \"$(command -v nix)\")\" | grep -q '#!'"
        )

    with subtest("a wrapped evaluation is transparent"):
        out = machine.succeed(
            f"runuser -u tester -- env {env} nix eval"
            " --extra-experimental-features nix-command --expr '1 + 1'"
        )
        assert out.strip() == "2", f"wrapped nix eval returned {out!r}, not 2"

    with subtest("argv survives the wrapper byte-for-byte (no environment expansion)"):
        # systemd-run expands ''${NAME} in command arguments unless
        # told not to; a nix expression is exactly where such bytes
        # live. The expr is the nix string escape \''${PATH}, whose
        # correct evaluation is the literal text ''${PATH} — any
        # expansion en route makes nix print the live PATH instead.
        out = machine.succeed(
            f"runuser -u tester -- env {env} nix eval"
            " --extra-experimental-features nix-command"
            + " --expr '\"\\''${PATH}\"'"
        )
        # nix re-escapes dollar-brace when printing string values, so
        # the correct output keeps the backslash (review finding —
        # the unescaped expectation fails even with a correct
        # wrapper). Expansion en route would substitute the live
        # PATH; either way the assertion distinguishes.
        assert out.strip() == "\"\\''${PATH}\"", (
            f"argument was rewritten in transit: {out!r}"
        )

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

    with subtest("killing the wrapper's own pid takes the scoped evaluator with it"):
        # The harness-cancellation shape: kill $! targets the wrapper
        # shell, and without signal forwarding the evaluator survives
        # as an orphan, still consuming inside its scope (review
        # finding, confirmed against the real systemd-run). The
        # wrapper pid is the one parkScript recorded.
        machine.succeed(f"runuser -u tester -- env {env} ${parkScript}")
        machine.wait_until_succeeds("${findEvaluator}")
        machine.succeed("kill -TERM \"$(cat /tmp/nix-scope-wrapper-pid)\"")
        machine.wait_until_fails("${findEvaluator}")
        machine.succeed("pkill -u tester -x sleep || true")
        machine.wait_until_fails("pgrep -u tester -x nix")

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

    with subtest("an interactive-class invocation (nix repl) is exempt from scoping"):
        cg = parked_cgroup(park="${parkReplScript}")
        assert "user@1000.service" not in cg, (
            f"interactive repl was scoped despite the exemption: {cg!r}"
        )
  '';
}
