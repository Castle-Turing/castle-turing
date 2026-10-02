Title: direnv as the fleet default, with an eval-storm detector
Model: standard
Model-because: the design is settled in this brief down to verified
option names (the pinned nixpkgs' `programs.direnv` module was read,
not recalled), so deep-tier judgment would mostly re-derive decisions
already recorded here. What keeps it off the cheap tier is the
verification surface: two VM tests with deliberate negative cases
(non-interactive delivery, authorization lifecycle), where a too-small
model historically writes tests that assert the happy path and call it
done. The brief's tests are specified below precisely so the
implementer's judgment is spent on making them honest, not inventing
them.
Status: ready

# A dev-shell entry costs a nixpkgs evaluation per command, and agents pay it in loops

**What.** `nix develop --command <cmd>` re-evaluates the project flake —
nixpkgs input and all, at roughly 2 GB peak (the figure the 2026-09-06
investigation measured for a nixpkgs evaluation, carried over from
`an-agent-workload-can-thrash-the-host.md` and not re-measured for the
flake in this incident — the detector thresholds below are therefore
calibration values, and the implementer measures before trusting them) —
on every invocation whose source tree changed since the last one,
because the evaluation cache keys on the whole dirty worktree, not on
`flake.nix`/`flake.lock`. An agent's edit-then-test loop changes a file
every iteration, and each Bash call is a fresh shell, so "enter the dev
shell" compiles to paying the full evaluation per command. On
2026-10-02 a session in a flake project elsewhere on this host — not
this repo, whose flake deliberately has no devShell (task 0029) — ran
`nix develop --command python ...` thirteen times in about seventeen
minutes against a tree it was actively editing, concurrent with a
second, unrelated session whose own load was ordinary; at 15:06
systemd-oomd found memory and swap past 90% and killed the resident's
session scope — 634 processes, both sessions, the whole desktop (the
kill-granularity problem `an-oomd-kill-takes-the-whole-desktop.md`
already carries).

**Why it matters.** This is the second memory-exhaustion incident with
the same root shape — per-command nixpkgs evaluation inside an agent
loop — after 2026-09-06's `nix shell nixpkgs#...` hang
(`an-agent-workload-can-thrash-the-host.md`). The first fix banned one
spelling and declared the missing tool; the trap itself survived under
a different spelling, and it will survive under the next one too,
because the defect is the default: on a host dedicated to embedding
agentic AI, the standard way to run a project command is one no agent
can use safely in a loop. The incident project's own agent guidance
says "`nix develop` provides the toolchain" — correct for a human with
a persistent terminal and a resource bomb for an agent. The resident's
direction (2026-10-02, in session, prompted by the incident): direnv
becomes the default for every host this project builds — dogfooding on
the xps9370 is not the scope. Stated against this entry's own criticism
of the first fix: direnv covers only the dev-shell spelling —
`nix shell nixpkgs#...` and `nix run` evaluate per command just the
same and stay guidance-banned, the identical one-spelling weakness.
What makes this round different is the detector, not the guidance: the
eval-storm check below watches nix-daemon connections and is
indifferent to which spelling raises the storm.

**How it would have been caught sooner.** The signal existed and
nothing read it: nix-daemon logged a fresh client connection roughly
every ninety seconds for seventeen minutes while memory pressure
climbed. An eval-storm check — more than N nix-daemon client
connections within M minutes — would have named the pattern before
exhaustion, and is the honest detector for recurrence under whatever
spelling comes next. The static regression check is a VM test in the
mold of `test/oomd-liveness`: assert that a host importing the dev
module has direnv with nix-direnv wired into the shell, so the default
cannot silently revert. The static check alone does not qualify as the
detector — it cannot see the storm recurring when delivery or guidance
fails — which is why both land, and land together.

**What we already know.** direnv with nix-direnv caches the evaluated
environment per project, re-evaluates only when `flake.nix` or
`flake.lock` change (source edits are ignored — exactly the hole the
loop fell into), loads the cache in milliseconds, and pins the dev
shell against garbage collection. Two constraints cross-model review
caught on this entry's own PR (#149), both load-bearing: the standard
direnv bash hook fires via `PROMPT_COMMAND`, which non-interactive
shells — including an agent's Bash calls — never evaluate, so enabling
direnv host-wide does not by itself reach the exact shells this entry
is about; and direnv refuses to load any `.envrc` until it is trusted,
on fresh clones and again after every `.envrc` edit, with the fallback
being a silent return to per-command evaluation. Task 0029's rejection
of a devShell for this repo's own tools ("a devShell only helps someone
who knows it exists") stands and is not reopened — host tools stay in
`systemPackages`; project-pinned environments are the case 0029 did not
cover, and direnv's automation answers its discoverability objection
there, once delivery and authorization are closed — which the spec
below does. The workload-side bounds (concurrency caps, `MemoryHigh=`)
remain `an-agent-workload-can-thrash-the-host.md`'s problem; this brief
only removes the per-command evaluation default.

## Decisions, closing this entry's open questions

Verified against the pinned nixpkgs (`flake.lock` rev `0e251e24a4f2…`'s
source was read, not recalled): nixpkgs ships a **system-level**
`programs.direnv` NixOS module — `enable`, `nix-direnv.enable`
(default-on once enabled), and `settings`, a TOML option written to
`/etc/direnv/direnv.toml` with `DIRENV_CONFIG=/etc/direnv` exported
system-wide. Its bash integration is `interactiveShellInit` only,
confirming the delivery gap.

- **Placement: `modules/dev`.** The dev-vs-home question closes
  because the upstream module is system-level, not per-user dotfile
  material: nothing per-person is involved (the hook is mechanism;
  git-identity precedent does not apply), and `modules/dev` is already
  "the tools this project's own development happens with". No new
  module code beyond option settings.
- **Authorization: whitelist, resident's decision (2026-10-02).** The
  mechanism is upstream `programs.direnv.settings.whitelist.prefix` —
  public, default empty, nothing added by this repo. The value (the
  resident's project roots) is private configuration set by the host
  or private layer, per Principle 01. Whitelisted prefixes cover fresh
  clones and `.envrc` edits with no ceremony, which is the point;
  per-project `direnv allow` was rejected because its failure mode is
  the silent fallback described above.
- **Non-interactive delivery: a guarded `BASH_ENV` script.** The host
  sets `BASH_ENV` (via `environment.variables`, so login sessions and
  the shells they spawn inherit it, while systemd services and build
  sandboxes do not) to a nix-store script that, when `direnv` is on
  PATH, `DIRENV_DIR` is unset, and an `.envrc` governs the current
  directory, runs `eval "$(direnv export bash)"`. direnv itself
  enforces the trust policy, so unauthorized directories load nothing.
  Considered and rejected: documenting `direnv exec <dir> <cmd>` as
  the required invocation (pure guidance — the compliance weakness
  this entry documents), and harness-native direnv integration (not
  verifiable or deliverable from this repo). `direnv exec` remains
  the documented explicit form for non-bash contexts.
- **Detector: `castle-eval-storm-check`, in `modules/dev`.** A
  systemd timer (every 2 minutes) runs a oneshot that counts
  nix-daemon "accepted connection" lines in the last window via
  `journalctl -u nix-daemon --since`; over threshold, it notifies
  through the existing `castle.agent.notify.command` channel
  (modules/agent; defaults to `notify-send`) and exits nonzero so the
  failed unit is visible to anything watching units. Spelling-agnostic
  by construction: it counts daemon connections, not subcommands.
  Public options `castle.evalStorm.{enable,threshold,windowMinutes}`,
  defaults `true`/`6`/`10` — calibration values: the 2026-10-02 storm
  ran ~0.8 connections/min (would trip ~7 in 10), the 2026-09-06 one
  2/min; an ordinary `nixos-rebuild` makes a handful. The implementer
  measures a rebuild and a quiet hour on the example configuration and
  adjusts the default threshold if either side is within 2 of it,
  recording the measurement in the PR.
- **nix-direnv cache location: upstream default.** Nothing in this
  repo depends on it; stating it would be an unsourced closure.
- **Other repos' `.envrc` and agent-guidance rewording: out of this
  repo's reach, tracked in the resident's profile, not here.** This
  brief's deliverable is the host default and the detector only.

## Plan

1. `modules/dev/default.nix`: set `programs.direnv.enable = true`
   (nix-direnv rides the default), `programs.direnv.silent = true`,
   and the `BASH_ENV` delivery script (a `pkgs.writeShellScript` plus
   `environment.variables.BASH_ENV`). Leave
   `programs.direnv.settings.whitelist` unset — hosts or the private
   layer declare their own prefixes; add one comment line saying
   exactly that and why (Principle 01).
2. `modules/dev/default.nix` (or a sibling `eval-storm.nix` imported
   by it, if the file is getting long): the
   `castle.evalStorm.*` options, the timer, and the oneshot script.
3. `test/direnv-delivery/test.nix`: VM test, oomd-liveness pattern
   (inject the real generated artifacts, do not re-type them). One
   node, a sample flake project with a devShell exporting a marker
   variable and a committed `.envrc` (`use flake`). Assert: (a) a
   **non-interactive** `bash -c 'echo $MARKER'` in a whitelisted
   project prints the marker; (b) the same in a non-whitelisted copy
   prints nothing; (c) after editing `.envrc` in the whitelisted
   project, the marker (or its successor) still loads with no manual
   `direnv allow`; (d) `direnv` and nix-direnv are wired into
   interactive bash init — the static regression half.
4. `test/eval-storm/test.nix`: VM test. Drive N synthetic nix-daemon
   connections (trivial `nix store ping`-class calls) above threshold
   within the window; assert the unit fails and the notify command
   fired (stub `castle.agent.notify.command` with a file-touching
   script, the repo's existing stub pattern). Below threshold: assert
   quiet.
5. Wire both tests into the flake's checks beside the existing ones.

## Verification plan

Unaided: `nix flake check` (both new VM tests plus existing ones);
the threshold measurement from the Decisions section. Resident's
hands: one switch on xps9370, then `cd` into a real whitelisted flake
project and confirm a fresh non-interactive `bash -c` sees the
environment; and the first week of eval-storm defaults in real use —
false positives are a redirect, not a code defect.

## Implementation prompt

Read this file end to end, then `modules/dev/default.nix`,
`modules/agent/default.nix` (the notify option), and
`test/oomd-liveness/test.nix` (the test pattern to follow, including
its header's reasoning about not importing `hosts/*`). Implement the
Plan above exactly; where reality contradicts this brief (an option
renamed in the pin, a test pattern that cannot inject what it needs),
argue with the spec in the PR and record the deviation rather than
silently complying. Do not touch `modules/base`, any `hosts/*`
module, or any file under `docs/` other than growing this brief's
record. The three scar-tissue rules in the resident's profile and this
repo's CLAUDE.md apply unreduced: no per-command `nix shell` while
building this, of all things.
