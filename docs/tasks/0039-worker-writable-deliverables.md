# Task 0039 — the worker can write its own deliverables

Promotes `docs/backlog/the-worker-cannot-write-its-own-deliverables.md`,
deleted in the same commit per that directory's README.

**Before starting:** read `CLAUDE.md` in full. Then, closely:
`agent/castle`'s `state_dir()`, `journal_dir()`,
`apply_in_flight_dir()` (the closest precedent — a non-record
directory beside the journal, with its own argument for being in the
state dir rather than the runtime one), `run_worker_turn`'s scratch
allocation and its `finally`, `worker_timeout_seconds()`,
`TenantNotRunnable` and its call sites in `run_worker_turn`,
`cmd_dispatch`'s two pre-flight refusals, and `runtime_dir()`'s
docstring for the house style of a "which directory, and why that
one" argument. Then `agent/castle-worker-claude` end to end — the
whole file, because its parse hazards (unquoted heredoc, backticks,
apostrophes) are documented inline and are easy to reintroduce. Then
`modules/agent/default.nix`'s `stateDir` option and the
"Deliberately minimal hardening" comment above the systemd user
units, and `docs/private-layer.md`'s "The agent's state".

## The problem

`run_worker_turn` allocates both of the worker seat's output files
with a bare `tempfile.mkstemp()`, so they land under `$TMPDIR` — in
practice `/tmp`. The reference worker tenant is
`agent/castle-worker-claude`, which `exec`s `claude -p`, and that
process runs under Claude Code's own sandbox, which permits writes
only beneath the resident's home directory. The tenant is therefore
handed two paths it cannot write.

It has now happened twice on the reference host. On 2026-09-01 the
first live dispatched errand that produced a real diff diagnosed
correctly, drafted a correct diff, and — finding both handed-over
paths unwritable — staged the two deliverables as loose files in
`$HOME` and explained that in prose on stdout. The result record
therefore says `outcome: completed` and "(no diff produced)", review
mode has nothing to show, and the 0025/0026 approve-and-apply chain
is unreachable for exactly the change it was built to carry. On
2026-09-02 a second worker turn reported the same refusal against
both `/tmp` output files. This is the single mechanical blocker
between the deployed system and the request → proposal → approval →
apply loop: everything downstream of the diff file exists and is
tested, and the handoff into it is what is broken.

## The one hard requirement

The degraded behaviour must never again be "deliverables scattered in
`$HOME`, channel empty, result says `completed`." A turn that could
not write its deliverables must produce a record that says so.

## Why this needs three changes and not one

The backlog entry sketched three directions. They are not
alternatives; each closes a gap the others cannot reach, and the
argument for that turns on one fact that is easy to miss.

**`castle work` is not inside the tenant's sandbox, and the tenant's
wrapper is not either.** `castle-worker-claude` is an ordinary bash
script; only the `claude` process it `exec`s is sandboxed. This is
directly observable in the 2026-09-01 failure: the wrapper's own
`mktemp` for the prompt file succeeded under `/tmp` in the same turn
where the tenant could not write `/tmp`. So a writability *probe* —
whether run by `castle work` or by the wrapper before it execs —
proves only that an unsandboxed process can write there. It proves
nothing about the process that actually has to.

That fact decides the shape of everything below. A probe is still
worth doing, because it catches a real and different fault; it just
cannot be the guard that satisfies the hard requirement. For that,
something must state the sandbox's rule rather than test around it,
and the only file that knows which sandbox is in play is the wrapper
that chose the tenant.

### 1. Allocate the scratch files where the sandbox permits writes

Both output files move from `mkstemp()`'s default to
`state_dir() / "work"`. The state directory is already required by
every path that reaches `run_worker_turn`, is already the private
side of the layout, and is home-anchored on every layout
`docs/private-layer.md` documents — the recommended sibling
repository, the submodule variant, and the unset-`stateDir` fallback
to `~/.local/state/castle` alike.

`apply_in_flight_dir()` is the precedent to copy and its argument
transfers: a scratch file that must outlive nothing and be deleted is
not a record, so it lives *beside* the journal and not in it. The
allocation stays `tempfile.mkstemp(dir=...)` so the files keep mode
`0600` and collision-free names; only the directory changes. The
existing `finally` that unlinks both is untouched.

### 2. `castle work` verifies that directory rather than assuming it

`castle.agent.stateDir` is an unconstrained `nullOr str`. Nothing
stops a deployment from pointing it at a path this process cannot
write, and inheriting "the state dir is under home" as an invariant
is how this bug is reproduced somewhere else. So `run_worker_turn`
proves its own access before it starts a tenant: create the
directory, allocate the two files, and on `OSError` refuse the turn
through the existing `TenantNotRunnable` path — an `outcome: failed`
result naming the directory, the `OSError`, and
`castle.agent.stateDir`, with nothing spent and the errand still
re-runnable by hand. This is the same posture as the four refusals
already in that function: nothing ran, here is why, here is the
command that retries.

What this check is honest about: it establishes that the invoking
process can write there. Per the fact above, it does not establish
that a sandboxed tenant can, and the message must not claim it does.

It is also deliberately *not* a check that the directory sits under
`$HOME`. `castle work` does not know which tenant it is about to run
or whether that tenant is sandboxed at all, and the agent-loop
harnesses legitimately point `CASTLE_STATE_DIR` at a temp directory
outside home with scripted tenants that have no sandbox. A refusal
there would break correct configurations to guard against a property
`castle work` cannot see.

### 3. The wrapper declares its sandbox and refuses early

`castle-worker-claude` is the file that knows it runs `claude -p`,
and therefore the only file in this repo that can state what that
tenant's sandbox permits. Before it execs, it checks that both
`$CASTLE_DIFF_FILE` and `$CASTLE_TARGET_FILE` resolve to paths
beneath `$HOME`. If either does not, it prints a diagnosis on stderr
naming both paths and `$HOME`, and exits nonzero.

That is a *declaration*, not a probe, and the distinction is the
point: the wrapper asserts the precondition its tenant needs rather
than testing a condition it is on the wrong side of. The cost of the
declaration going stale — Claude Code widening or narrowing its
sandbox — is a wrong refusal with an explicit message naming the rule
it applied, which is diagnosable in one reading. The cost of no
declaration is the 2026-09-01 failure, which took two errands to
diagnose.

The result is `outcome: failed` with the wrapper's stderr in the
record body, one automatic attempt spent, and the fault visible on
every surface the resident already uses. That is what makes the hard
requirement hold: the empty channel can no longer be reported as
`completed`.

With change 1 in place this refusal should never fire on a correct
deployment. It fires on a deployment where `stateDir` points outside
home while the sandboxed reference tenant is configured — precisely
the combination change 2 cannot see and change 1 cannot fix.

### 4. The prompt forbids the improvisation that actually happened

Changes 1–3 address the mechanism. The observed *behaviour* — staging
the deliverables in `$HOME` and explaining it in prose — was a model
improvising a channel when the contract's channel failed, and no rule
in the prompt told it not to. Even with the three changes above, a
write can fail for reasons none of them cover (a full disk, a
read-only mount), and the same improvisation is available.

So the wrapper's contract block gains one rule: if you cannot write
`$CASTLE_DIFF_FILE`, do not stage the diff anywhere else — not in
your home directory, not in either checkout, not anywhere. Say so in
your account on stdout and stop. A deliverable outside the two files
this harness hands you is invisible to every surface the resident
uses, so a file written elsewhere is not a partial success; it is a
lost errand plus a mess for a later turn to explain.

### 5. The dispatch sweep prunes the scratch directory

Moving the scratch out of `/tmp` moves it out of a directory
something else eventually cleans. `run_worker_turn`'s `finally`
unlinks both files on every ordinary and exceptional exit, but not
across a `SIGKILL` or a power loss — and under the state directory a
leftover is durable, accumulating one pair of files per killed turn
forever, in the private directory whose contents
`docs/backlog/validate-should-notice-a-stray-state-directory.md`
already worries about.

So `cmd_dispatch` prunes `state_dir() / "work"` once per sweep,
unlinking entries older than a fixed 24 hours. The threshold is an
absolute floor rather than a multiple of `worker_timeout_seconds()`
deliberately: that value is read per-process from the environment, so
a sweep and a hand-run `castle work` can disagree about it, and a
prune that computes its own safety margin from a number the process
being protected did not use is not safe. No turn survives its own
timeout — `run_worker_turn` kills the tenant's process group and
unlinks — so 24 hours cannot reach a live turn's files by any
configuration of that option a resident would set.

Pruning is best-effort: an `OSError` on any entry is ignored and
never fails a sweep. A scratch file this cannot delete is untidy; a
sweep that exits nonzero means "dispatch itself broke", and a
leftover temp file is not that.

## Rejected alternatives

**`claude --add-dir <scratch dir>`.** The CLI does accept
`--add-dir`, and passing the scratch directory is superficially the
smallest possible fix. Rejected: `--add-dir` is documented as
widening the directories the *tools* may work in, and whether it also
widens the OS-level sandbox's write allowlist is not something this
repo can establish without a live run against a version of a tool it
does not control. Building the fix on it would replace one unverified
assumption about an external sandbox with another, which is the
defect this task exists to remove. It is recorded here rather than
silently skipped: if a resident does confirm it works, it is a
one-line simplification to the wrapper, not a redesign.

**Putting the scratch under `runtime_dir()`.** `/run/user/$UID/castle`
is where the spool and the leases live and is the natural home for
per-turn ephemera. Rejected because it is not under the resident's
home, so it reproduces the exact failure this task fixes. The
durability cost of choosing the state directory instead is what
change 5 pays for.

**Making an empty diff file an error.** It would satisfy the hard
requirement mechanically and it is wrong: the wrapper's own contract
has a whole category of errand — rule 6, the perceptual-judgment
case — whose correct turn writes no diff and no target and files a
blocking question instead. An empty channel is a legitimate outcome;
what must never be legitimate is an empty channel that nobody could
have filled.

## Non-goals

- No change to the two output files' contract, names, or environment
  variables. A tenant that works today keeps working.
- No systemd unit hardening. The "Deliberately minimal hardening"
  argument in `modules/agent` is unaffected: the sandbox in question
  is Claude Code's, not systemd's.
- No new Nix option, and no constraint added to `stateDir`'s type.
  Evaluation must not stat a resident's disk; the check belongs in the
  CLI, exactly as `docs/tasks/0030-state-outside-the-flake.md` argued
  for the layout warning.
- Not `docs/backlog/validate-should-notice-a-stray-state-directory.md`,
  which change 5 touches the neighbourhood of and does not close.

## Verification

Automated, and all of it must pass before this is proposed:

- `test/agent-loop/run.sh`, `dispatch-test.sh`, `resume.sh`,
  `config-target.sh`, `approval.sh`, `apply.sh`, `tenant-swap.sh`,
  `state-layout.sh` — every harness that drives `castle work` or
  reads a result record. The scratch relocation is on the path all of
  them take.
- New coverage in `dispatch-test.sh`, since it is the harness that
  already owns `castle work`'s refusal paths and the contract-worker
  tenants: (a) a turn allocates its scratch under
  `$CASTLE_STATE_DIR/work` and leaves nothing behind afterwards; (b)
  an unwritable state directory refuses before the tenant runs and
  writes a `failed` result naming the directory; (c) the sweep's
  prune removes a planted stale entry and leaves a fresh one alone.
- New coverage for change 3 in the same harness: run
  `agent/castle-worker-claude` directly with `CASTLE_DIFF_FILE`
  pointed outside `$HOME` and assert it exits nonzero with the
  sandbox rule on stderr, without invoking `claude`. This is a bash
  test of the wrapper's pre-exec guard; it needs no model.
- `nix flake check`.

**Read the artifacts, not the exit statuses.** Change 4 edits the
generated prompt: render it and read the rule in place, confirming
also that the added prose introduces no backtick and no unbalanced
apostrophe — the two parse hazards that file documents inline and has
been bitten by. Change 2 and change 3 both write prose into a result
record: read the record bodies, not just the `outcome` fields.

**The step that needs the human, on live hardware.** None of the
above proves the thing this task is actually about, because no
harness in this repo runs a sandboxed tenant. Only a real dispatched
errand on the reference host, with `castle.agent.worker.command` at
its default and a request that produces a diff, establishes that
`claude -p`'s sandbox permits writing to a scratch file under the
configured state directory. The pass condition is a `result` record
carrying a non-empty diff and a `patch_sha256`, with the
corresponding `.patch` sidecar in the journal. Do not simulate this
step; the whole failure being fixed is one an unsandboxed simulation
cannot reproduce.

If that live run instead produces the wrapper's refusal from change
3, the mechanism worked as designed and the assumption underneath
change 1 is what is wrong: the sandbox does not permit the configured
state directory. That outcome is a finding, not a regression, and it
is loud — which is the whole point.
