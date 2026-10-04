Title: The memory kill lands on the build, not the session
Model: deep
Milestone: none — hygiene
Model-because: this brief transfers with its central decision open —
closing the high-to-max band versus a per-invocation sub-scope, and
whether PATH-shadowing `nix` host-wide is acceptable at all — so the
implementer is choosing an architecture, not following one. A
standard-tier implementer handed an unmade decision reliably picks
the nearest plausible shape and ships it without arguing the trade;
here the trade is the deliverable, and the wrong granularity
reproduces the incident on a later date with a bigger budget. Any
open question that needs the resident travels back up rather than
being answered in-branch.

# The memory kill takes the session, not the build

**What.** When a bounded terminal scope runs away, what dies is
everything in the scope, not the process that ran away. On
2026-10-03 a castle-turing session's local VM-test build loop pushed
its scope against its bounds (MemoryHigh=4G, MemorySwapMax=2G,
MemoryMax=6G — task 0085's options, values from the private layer);
the scope sat in the band between the throttle and the hard cap,
swap full, thrashing under reclaim, until systemd-oomd's slice
pressure rule killed all 42 processes in it — terminal, Claude
session, and every subagent — when the runaway was the nix
evaluation. The resident's direction (2026-10-03, in session):
descope the kill to the build, so a runaway evaluation dies alone
and the session survives to report it.

**Why it matters.** Losing a build costs a retry; losing the session
costs its context, its subagents, and the live diagnosis — the
surviving session is exactly the thing that could have named the
culprit while the pids still existed
([[a-crash-goes-uninvestigated]] is this cost, filed from an earlier
kill). As long as the kill lands on whole scopes, every eval storm
ends this way regardless of budget — a bigger budget only moves the
date.

**What we already know.** A hard cap alone demonstrably does not do
it: MemoryMax=6G was set on the killed scope and never fired,
because oomd wins the race — a scope throttled at MemoryHigh with
its swap allowance exhausted generates sustained reclaim pressure
long before RSS reaches the cap, and oomd kills leaf cgroups whole.
Closing the high-to-max band (MemoryHigh = MemoryMax) trades the
thrash window for the kernel's in-scope OOM kill, which takes the
cgroup's largest process by oom_score — usually the evaluation, but
a long-lived Claude process with a large heap could lose instead:
cheap, one private-layer line, not precise. The precise shape is a
sub-scope per nix invocation — wrap `nix` to run under
`systemd-run --user --scope` with its own MemoryMax, landing bound
and kill on exactly the build — but it has the same delivery problem
BASH_ENV solved for direnv (task 0083): nothing reaches an agent's
non-interactive bash unless the wrapper shadows `nix` on PATH for
every shell. Also load-bearing: evaluation runs in the client
process, inside the session scope; the build itself — VM boots
included — runs under nix-daemon's own system slice. The 2026-10-03
footprint was client-side evaluation, so the client half is the one
that matters here.

**Open questions.** Whether PATH-shadowing `nix` host-wide is
acceptable, and where the wrapper lives if so (beside the eval-storm
detector in modules/dev is the natural home). What bound a per-eval
sub-scope gets, and whether the parent scope keeps its own bounds
underneath it. Whether the cheap imprecise step — closing the
high-to-max band — is worth shipping while the wrapper is specced.
How a killed evaluation's death reaches the surviving session as
"your build hit its memory bound" rather than as a mysteriously
failed command.

## Decisions, closing this entry's open questions

Made at implementation (the brief transferred with its architecture
deliberately open — its own `Model-because:` says choosing it is the
implementer's deliverable); each is the resident's to overturn at
review.

- **The per-invocation sub-scope, delivered by PATH shadowing —
  `modules/dev/nix-scope.nix`.** A `lib.hiPrio` package shadows the
  five evaluating client commands (`nix`, `nix-build`, `nix-shell`,
  `nix-instantiate`, `nix-env`); each wrapper runs the real client —
  by absolute store path, so the shadow cannot recurse — under
  `systemd-run --user --scope --collect --quiet` with this module's
  bounds. PATH shadowing is accepted for the same reason task 0083
  rejected guidance-only delivery: nothing else reaches an agent's
  non-interactive bash mechanically, and both founding incidents
  walked through exactly the gap guidance leaves. Three guards keep
  the shadow honest: `CASTLE_NIX_SCOPE_DISABLE` (documented opt-out,
  the `CASTLE_DIRENV_DISABLE` contract), `CASTLE_NIX_IN_SCOPE` (one
  scope per top-level invocation — a `nix develop` shell's own nix
  calls stay in their develop scope rather than stacking siblings),
  and a fail-open direct exec for root or any context with no
  reachable user manager (`$XDG_RUNTIME_DIR/systemd/private` absent)
  — `nixos-rebuild` runs nix as root, and breaking a switch is the
  one unforgivable failure available here.
- **Band-closing is rejected as the mechanism, not just deferred.**
  It is pure private-layer arithmetic, so there is nothing for this
  repo to ship; and the incident evidence above already shows the
  shape of its weakness — the kill race is decided by reclaim
  pressure, which a scope at its cap with swap allowance still
  generates, so oomd can still take the whole scope first. The
  sub-scope wins both endgames: a kernel cap kill lands inside the
  invocation's scope, and an oomd pressure kill now selects the leaf
  actually generating the pressure.
- **The framework ships no bound values (Principle 01).** Options are
  `castle.nixScope.{enable,memoryMax,memorySwapMax}`, the memory pair
  defaulting `null`. `memoryHigh` is deliberately not offered: the
  throttle is what converted the founding incident's runaway into
  minutes of thrash ending in a whole-scope kill anyway. Even with
  no bounds set, the wrapper changes kill granularity — each
  invocation is its own oomd-eligible leaf — which is why
  `enable` defaults `true`, on the eval-storm rationale that nothing
  opted in to the incidents.
- **The parent scope keeps its own bounds, unchanged — with one
  consequence stated plainly:** a transient user scope is registered
  under the user manager, not nested in the caller's cgroup, so a
  wrapped evaluation's memory no longer counts against the terminal
  scope's `castle.launch` budget at all. That is the point (the
  terminal budget stops paying for builds), but a resident sizing
  budgets should know the nix client moved out from under them.
- **The death report is the wrapper's own stderr line.** The wrapper
  does not `exec` its final step; it stays resident, and when the
  scoped client exits 137 (SIGKILL) it prints
  `castle-nix-scope: <cmd> was killed … almost certainly a memory
  kill`, naming the configured `MemoryMax` and where the kill record
  lives (`journalctl -k` for kernel cap kills, `journalctl --user`
  for oomd). The surviving shell — and the agent reading its output —
  gets the distinction between "my build hit its bound" and a
  mysteriously failed command in-band, which was this entry's one
  non-negotiable requirement.

Amendments from this task's own review passes, each a real defect in
the design above rather than a style point:

- **There is no in-scope marker.** The first design exported
  `CASTLE_NIX_IN_SCOPE` into the scoped payload so nested nix calls
  would not stack scopes — and review showed the marker is
  inheritable forever: any long-lived descendant of one scoped
  invocation (a `--command`-started tmux or agent) would silently
  disable scoping for everything it ever spawned, recreating the
  founding incident with no sign the guard was off. Nested
  invocations now get sibling scopes of their own, each bounded,
  which is the better behavior anyway.
- **A wrapper death takes the evaluator with it.** The scoped client
  is backgrounded with TERM/INT/HUP forwarded and the exit status
  re-waited: a harness that cancels a build kills the PID it spawned
  — the wrapper — and without forwarding, the evaluator survived as
  an orphan, still consuming inside its scope (confirmed against the
  real systemd-run).
- **`nix-shell` shebang scripts are scoped.** Their `#! nix-shell`
  directives live on line 2 of the script file, invisible in argv,
  so they classified as interactive and escaped unscoped — exactly
  a bounded eval-then-run workload. A positional file argument with
  nix-shell on its second line is now detected.
- **`castle-apply` opts out.** The agent module's apply unit resolves
  nix via PATH for its optional flake check; a sibling scope would
  move that evaluation outside the unit's cgroup, where
  `systemctl --user stop` and the unit's accounting no longer reach
  it. The unit sets `CASTLE_NIX_SCOPE_DISABLE=1` — it already
  manages its own children.
- **The coverage boundary is stated.** Only PATH-resolved
  invocations are shadowed; a caller holding an absolute store path
  to the client bypasses the mechanism, and the module header and
  `enable` description now say so instead of claiming "every"
  invocation.
- **One classification limit documented, not fixed:**
  `nix develop --command bash` is indistinguishable from
  `--command make` in argv and is scoped; an interactive shell that
  must not live under an eval-sized bound is spelled bare
  `nix develop`, or opted out.
- **`print-dev-env` is exempt, and direnv loads are therefore
  unbounded.** The resident's challenge caught a deterministic
  regression the first draft shipped: `direnv-delivery-test` failed
  its core "a whitelisted project's non-interactive bash sees the
  marker" assertion on three consecutive runs. The mechanism, from
  the VM's own scope accounting: nix-direnv runs `nix print-dev-env`
  for `use flake` and consumes its stdout synchronously, and routing
  that through a transient scope hung the capture — the scoped
  `print-dev-env` burned 20s CPU, evaluated fully (466M peak, far
  under any bound), then blocked on I/O for ~160s until the probe's
  180s timeout killed it, leaving direnv with no environment. The
  fix direct-execs `print-dev-env` alongside the interactive
  exemptions. It earns the exemption on its merits, not only to
  unbreak the test: nix-direnv caches it per `flake.lock` change
  rather than per command, so it is not the edit-then-build loop
  surface this task targets, and it mirrors the bare `nix develop`
  already exempt. The honest cost: a direnv-driven dev-env
  evaluation runs unbounded. Acceptable because it is cached and
  infrequent and the loop-prone surfaces (`nix build`,
  `nix flake check`, `nix eval`, `nix develop --command`) stay
  scoped — but a resident who wants even that capture bounded has
  no knob for it here, which is the residual this records rather
  than closes. `test/nix-scope/test.nix` grows a subtest asserting
  the capture returns (the faithful inverse of the hang), and
  `direnv-delivery-test` — which caught this — is the end-to-end
  detector on every `modules/dev` change.

- **Interactive environments are exempt from scoping.** Bare
  `nix develop`/`nix shell`/`nix repl`/`nix-shell`, and `nix run`'s
  arbitrary-duration payload, direct-exec: a memoryMax sized for one
  evaluation must not become the ceiling on an hours-long dev-shell
  session — that would have recreated the whole-session kill inside
  every dev shell, likelier than before. The founding incidents'
  spellings
  (`nix develop --command`, `nix shell -c`, every `nix build`/
  `eval`/`flake` call) stay scoped. Subcommand detection is a
  first-argument heuristic that errs toward scoping.
- **The manager is probed live, not inferred from a socket on
  disk.** An uncleanly dead `systemd --user` leaves its socket
  behind, and a foreign `XDG_RUNTIME_DIR` points at a manager that
  refuses the caller — both made the wrapper fail a workable nix
  invocation closed. A no-op scope probe precedes the real one; any
  probe failure falls open to direct exec.
- **The kill report is calibrated.** An external `kill -9` is
  indistinguishable from a memory kill at the wrapper ("most
  likely", not "almost certainly"), and the pointers name where
  records actually land: `journalctl -k` for kernel cgroup kills,
  `journalctl -u systemd-oomd` for oomd's — not `journalctl --user`,
  where a `--collect`ed scope leaves nothing.

## How it would have been caught sooner, and the detector this ships

The incident's detector half already exists (`castle-eval-storm-check`
named the storm 18 minutes before the kill); what nothing checked is
the kill *granularity*. The detector landing here is
`test/nix-scope/test.nix` (a `packages.x86_64-linux.nix-scope-test`
VM, workflow `.github/workflows/nix-scope-test.yml`): a real
evaluation driven past a real 192M `MemoryMax` must die by SIGKILL in
a transient scope of its own while the invoking shell survives,
keeps executing, and holds the wrapper's stderr explanation — plus
the PATH-resolution, transparency, root-fallback, and opt-out
assertions. CI confirms the kill lands as `CONSTRAINT_MEMCG` inside
the invocation's own `run-*.scope` with the shell surviving (eight
subtests green on run 37177001312). One half remains not
mechanically testable and is stated rather than faked: the
oomd-versus-kernel race under slow realistic thrash (the VM test's
kill is the kernel's cap, near-instant). The claim that oomd's leaf
selection prefers the sub-scope rests on oomd's documented
leaf-cgroup behavior, not on a test.

Two VM-fixture facts the test node carries, each found the hard way
on CI rather than reasoned up front: `vm.panic_on_oom = 0` (the
NixOS test default is 2, which panics the whole guest even on a
cgroup-contained kill — the event under test), and a runaway that
commits memory in ~8M chunks rather than one multi-gigabyte
allocation (a single oversized `mmap` in a 2 GB guest is refused by
the overcommit heuristic with ENOMEM, exit 1, before the cgroup cap
can fire). Both are the small-guest regime diverging from a real
host whose RAM exceeds the cap, not the mechanism — a real host runs
`panic_on_oom = 0` and the chunked growth touches pages until the
cgroup OOM kills only the evaluator.

## Verification plan

Unaided: `nix flake check` via check.yml (module evaluates);
`nix-scope-test` on CI — via its pull-request path trigger, since
`workflow_dispatch` only works once a workflow exists on the default
branch, which a brand-new workflow does not until this merges.
Resident's hands:
one switch on a real host, then — in a terminal they are willing to
lose if this is wrong — `nix eval --expr` something enormous and
confirm the shell survives with the `castle-nix-scope:` line on
stderr; and the first week of real use, watching specifically for a
context where the wrapper's fail-open conditions misfire (a workable
nix invocation refused, or a switch misbehaving), which is a
redirect, not a code defect.
