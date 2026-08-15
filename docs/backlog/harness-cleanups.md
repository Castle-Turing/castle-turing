# VM harness cleanups

**What.** A cluster of small quality fixes in `test/vm-install/` and its
CI workflow, surfaced by review passes over tasks 0004–0006 and parked
rather than folded into unrelated diffs.

**Why it matters.** The harness is the project's regression net for
installs; friction here is paid on every iteration of every future
install-related task, and duplication in a test is duplication in the
thing that is supposed to catch drift.

**What we already know.** Each item below was confirmed by review, with
the reasoning already worked out:

- **Repeated phase blocks.** Phases 2, 3 and 4 in `run.sh` repeat the
  same start-QEMU / wait-for-SSH / fail-or-log shape, differing only in
  setup and message. An `assert_boots` helper removes ~20 lines and the
  risk of the three copies drifting (one losing its guard, say).
- **Pubkey boilerplate.** `installer.nix` and `vm-test-system.nix` each
  inline `lib.removeSuffix "\n" (builtins.readFile pubkeyFile)`, which
  is exactly nixpkgs' own `lib.fileContents`. Two copies could diverge
  and silently authorize different keys in the installer and the target
  — precisely the drift the harness exists to catch.
- **No Nix cache in CI.** The workflow re-substitutes QEMU, OVMF,
  nixos-anywhere and the full closure on every run. A cache step keyed
  on `flake.lock` would cut the dominant cost.
- **Serial `nix build` calls.** Tools are built one subprocess at a
  time, and the installer ISO and target system build sequentially
  despite being independent. Batching or backgrounding turns a sum into
  a max.
- **Workdir never cleaned.** `cleanup()` kills QEMU but leaves the 8G
  qcow2 behind even on success, so repeated local runs accumulate
  disk images.
- **Polling granularity.** `wait_for_ssh` sleeps a flat 3s rather than
  watching the serial log that is already being captured.

**Open questions.** Which of these are worth the churn at all — the
cache step and the parallel builds are clear wins, the polling one is
marginal. Should they land as one cleanup PR or ride along with
whatever next touches the harness?
