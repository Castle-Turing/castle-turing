Title: Per-scope memory bounds for wrapped app launches
Model: standard
Requires: 0084-an-oomd-kill-takes-the-whole-desktop
Milestone: none — hygiene
Model-because: the design decisions are made in this brief (the option
surface, the zram caveat, the delegation trap), and the one assumption
that could sink a smaller implementer — whether memory properties
actually land on user scopes — is guarded by a VM assertion that reads
the cgroup file and fails loudly, so a wrong assumption cannot ship
silently; deep would spend judgment where the test already supplies the
verdict.
Requires-because: the bounds this task exposes are properties on the
per-app transient scopes that task creates; without the wrapper there
is no unit to bound — every desktop process shares one session scope
and a bound on it is a bound on the whole desktop.
Status: ready

# An agent workload can thrash the host, and nothing bounds it

**What.** The workload that exhausted memory on 2026-09-06 (see
`a-crash-goes-uninvestigated.md`) was ordinary delegated research: a
session fanned out three concurrent research subagents, and at least
one extracted text from PDFs by invoking
`nix shell nixpkgs#poppler-utils` repeatedly — six nix-daemon
connections in under three minutes — each invocation evaluating
nixpkgs at roughly 2 GB peak. Three subagents plus concurrent nixpkgs
evaluations on a 16 GB machine is arithmetic, and nothing anywhere in
the stack — not the delegating session, not the subagent's brief, not
the host — stated or enforced a resource bound. The same shape recurred
on 2026-10-02 under a different spelling — `nix develop --command` per
iteration against a flake worktree being edited — ending in an oomd
session kill; that incident, and the host-default fix it motivates, are
`a-dev-shell-entry-costs-a-nixpkgs-eval-per-command.md`'s to carry.

**Why it matters.** The project's direction is *more* fan-out, not
less: parallel sessions, research dives, an emcee queue keeping
multiple workers busy. Every layer currently assumes some other layer
is watching memory. The host-side net is its own entry
(the oomd half fixed by task 0063; the swap half in
`the-kernel-oom-killer-has-no-swap-headroom.md`); this one is about
the workload side, because even a working oomd only converts a hang
into killed work — the crash this stems from killed in-flight work
across all three Claude sessions then running (the delegating
castle-turing session with its three research subagents, plus
unrelated sessions in two other projects) and the castle timers that
had just started and never printed a first line.

**What went wrong at the delegation layer, specifically.** The
subagent was never told the host's constraints, so it improvised —
and notably, an earlier dive the same night faced the identical
missing-tool problem (no `pdftotext` on PATH) and judged that
installing tooling was out of scope, taking two unverified markers as
the cost. Same gap, opposite judgment calls, and only one of them was
safe. A constraint that lives in a delegating prompt sometimes and in
an agent's judgment otherwise is not a constraint.

**Fix directions considered.**

- The worker contract and delegation conventions state host resource
  discipline explicitly: no per-command `nix shell nixpkgs#...` in
  loops (evaluate once into a profile, or do without), and a stated
  cap on concurrent subagents per host, sized to its RAM.
- Tooling that research tasks predictably need (PDF text extraction)
  is either declared in the environment once, or declared unavailable
  — so no agent decides mid-task to summon it via nixpkgs
  evaluation. *Partially done in task 0063: `poppler-utils` is now
  declared in `modules/dev`, and the resident's agent profile gained
  an install-or-report-never-summon instruction. The general
  question — how a task learns what tools it may assume — stays
  open here.*
- Systemd-level resource caps (`MemoryHigh=`/`MemoryMax=`) on the
  slices agent sessions run in, so the bound is enforced rather than
  promised. Interacts with the oomd entry's kill-target question.

This brief takes the smallest concrete chunk of the third direction:
per-scope memory bounds, expressible once task 0084's per-app scopes
exist. The first direction is deliberately not taken here — see the
spec's "What this brief does not do".

## Spec

Where this sits in the defense stack, honestly: the direnv default
(the dev-shell task) removes the biggest known allocation storm at its
source; systemd-oomd (live since task 0073) is the backstop that kills;
this task is the middle layer — a single runaway scope throttles before
the host reaches crisis, instead of sprinting unimpeded from healthy to
oomd's 90% line.

**Mechanism (public, Principle 01).** Task 0084 wraps app launches in
per-class transient scopes via `systemd-run --user --scope`, and
defines the class interface this task extends: a launch class is a
named entry (`terminal`, `menu`, `modal`) with an `extraProperties`
list of `systemd-run --property=` strings, which `castle-launch
<class> -- <cmd>` renders onto the scope. This task adds three optional
typed resource options per class, which render into that list:

- `memoryHigh` — rendered as `--property=MemoryHigh=<value>` on the
  wrapped scope. Per systemd.resource-control(5), this is the
  throttling bound: usage may exceed it if unavoidable, but processes
  are heavily slowed and memory is reclaimed aggressively — runaway
  allocation becomes slow allocation, buying oomd and the resident
  time.
- `memorySwapMax` — rendered as `--property=MemorySwapMax=<value>`.
  Required as a companion on zram-only hosts, and the module comment
  must say why in present tense: MemoryHigh relieves pressure by
  pushing pages to swap, and on a host whose swap is zram, swap *is*
  RAM — reclaim converts a runaway's footprint at roughly the
  compression ratio rather than evicting it.
- `memoryMax` — rendered as `--property=MemoryMax=<value>`: the hard
  cap, above which the kernel OOM-kills within the scope. Cross-model
  review on this spec's PR (#150) caught the first draft calling
  `memoryHigh` + `memorySwapMax` an "aggregate bound" — they are not
  one: MemoryHigh is a throttle that usage may exceed indefinitely,
  and MemorySwapMax caps swap only. The module comment states the
  throttle-versus-cap distinction so nobody reads `memoryHigh` as a
  ceiling; a host that wants a hard ceiling sets `memoryMax`.

All three options are `nullOr str` (systemd size strings — "6G", "512M"),
default `null`, meaning: no property passed, exactly today's behavior.
The option surface follows wherever 0084 lands its per-class scope
config (`modules/home`, alongside the sway config, per that brief's
placement decision); this brief adds no new module.

**Values are private.** The repo ships `null` defaults and no numbers.
The resident's actual bounds are host or private-layer configuration —
what a browser deserves on a 16 GB machine is a per-machine judgment,
not framework policy.

**The delegation trap, named for the implementer.** Memory properties
on *user* scopes require the memory controller to be delegated to
`user@.service`. Recent systemd delegates it by default, but this brief
treats that as unverified on this flake's pin: the implementation must
confirm the property lands by reading the scope's cgroup file
(`memory.high`), not by trusting `systemd-run`'s exit status. If
delegation turns out to be absent, enabling it is in scope for this
task (it is one systemd setting), and the VM test below is what proves
either way.

**What this brief does not do.** No concurrency cap and no worker
contract line. Checked at spec time: the agent layer has no per-run
instruction surface a worker loads for host constraints —
`modules/agent` is deliberately a thin invoker (Proposal 03), and
`agent/README.md`'s seat contracts are developer documentation, not
runtime input. Inventing such a surface is its own design task; writing
the cap into a document nothing loads would be a constraint in name
only, the exact defect the delegation-layer section above records.
The cap question stays open below.

## How it would have been caught sooner

The 2026-09-06 storm's own detector — the eval-storm check on
nix-daemon connections — ships with the dev-shell task, which carries
that incident's root cause. This task's detector obligation is the
regression kind: the VM test below asserts that a wrapped scope
launched with bounds configured actually carries them in its cgroup
(`memory.high`, `memory.swap.max`), so the bounds cannot silently
become no-ops under a systemd upgrade or a delegation change — a
failure that would otherwise look exactly like a quiet day until the
next runaway.

## Plan

1. Extend 0084's per-class scope options with `memoryHigh`,
   `memorySwapMax`, and `memoryMax` (`nullOr str`, default `null`);
   thread them into the wrapper's `systemd-run` invocation as
   `--property=` arguments, only when set.
2. Write the module comment carrying the zram caveat and the
   delegation requirement, present tense, no incident narrative.
3. Extend 0084's VM test: configure a class with all three bounds,
   launch a wrapped scope, read `memory.high`, `memory.swap.max`, and
   `memory.max` from the scope's cgroup directory, assert the
   configured values; assert a class left at `null` produces a scope
   with `max` in all three files.
4. If the VM shows the memory controller is not delegated to the user
   manager, add the delegation setting to the same module and note it
   in the brief's PR (design shift lands in the brief, per convention).

## Verification plan

Agent-verifiable, no human hands: `nix flake check`; the extended VM
test (property lands, null stays null); a negative check that the
wrapper passes no `--property=Memory*` when options are unset. Human
step, deliberately manual: the resident sets real values in the
private layer after the switch and spot-checks one scope with
`systemctl --user show <scope> -p EffectiveMemoryHigh` — choosing the
numbers is the resident's judgment and no harness should guess them.

## Open questions (deferred, not blocking)

Where the concurrency cap belongs — the delegating session's judgment,
the harness, or the host config — and whether a subagent brief should
carry a resources line the way task files carry `Model:`, so the bound
travels with the work instead of depending on whoever wrote the prompt
remembering it. Both need the instruction-surface design this brief
declines to improvise.

## Implementation prompt

Read this brief in full, then `docs/tasks/0084-*` (the wrapper and VM
test you are extending), `modules/home/` as 0084 left it, and
systemd.resource-control(5) for MemoryHigh/MemorySwapMax semantics.
Implement per the Plan; the Spec's "delegation trap" paragraph is the
one place not to economize — read the cgroup file, do not trust exit
status. Keep the Principle 01 split: mechanism and null defaults in the
module, no numbers anywhere in this repo. Record in your PR any point
where this brief proved wrong, and update the brief in the same PR.
