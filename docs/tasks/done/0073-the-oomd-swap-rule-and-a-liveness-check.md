Title: The oomd swap rule is wired, and a liveness check keeps both rules honest
Model: standard
Milestone: none — hygiene
Model-because: the design decisions are already made in this brief against
the systemd man pages and the deployed units — which slice, which trigger,
where the check lives — so what remains is NixOS wiring plus a small
parser, not design. What rules out the cheap tier is that the brief's
central lesson is "an unverified claim about oomd looked like a fix": the
implementer must compare the rendered units and the live oomctl output
against what this brief asserts, and argue back if they disagree, rather
than transcribe. What rules out the deep tier is that there is no open
design question left for it to spend judgment on.

# Task 0073 — the oomd swap rule, and a liveness check for both rules

## Why, from the incident

On 2026-09-15 at ~22:55 this host (xps9370, 16 GB, zram-only swap)
hard-hung from memory exhaustion and had to be power-buttoned — the
second occurrence of the failure mode first seen 2026-09-06. The
previous boot's journal shows normal operation through 22:53:20, then
`systemd-journald` logging "Under memory pressure, flushing caches"
from 22:55:17 until the journal goes silent at 22:56:49. Whatever
allocated the memory never logged a line; neither the kernel OOM
killer nor systemd-oomd killed anything, so no process was ever named.
The culprit is unidentified and the evidence is exhausted — which is
itself the argument for `docs/backlog/a-crash-goes-uninvestigated.md`,
not for this task.

What this task fixes is what the post-crash inquest found about the
defenses:

1. **systemd-oomd's swap-based kill rule watches zero cgroups.** Task
   0063 (`docs/tasks/done/0063-oomd-watches-user-slices.md`) enabled
   the *pressure* rule on the user slices via
   `systemd.oomd.enableUserSlices`. The NixOS module behind that
   option sets only `ManagedOOMMemoryPressure=kill`; no NixOS option
   anywhere sets `ManagedOOMSwap=` (verified against the module
   source, `nixos/modules/system/boot/systemd/oomd.nix` — even
   `enableRootSlice` is pressure-only). So `oomctl` prints
   "Swap Used Limit: 90.00%" while its "Swap Monitored CGroups:" list
   is empty: the rule reads as armed and is inert. The 2026-09-06
   diagnosis had observed both watch lists empty; 0063 fixed and
   verified the pressure list only, and the swap list was never
   assigned to either its "fixed" or its "deferred" column. This task
   is that finding, finally owned.

2. **The pressure rule alone demonstrably loses the race.** On
   2026-09-15 there were ~90 seconds of visible memory pressure and no
   kill. The pressure rule needs its 80% limit sustained over a 30 s
   average; a fast allocator on a zram-only host livelocks the machine
   before that average trips. `systemd-oomd.service(8)` says this in
   as many words: swap gives oomd time to react, and swap-based action
   is the trigger matched to swap-backed exhaustion. The zram swap
   filling toward full is precisely the early warning this host emits
   before it livelocks — and nothing subscribes to it.

3. **A dead defense reads as a quiet day.** From install until 0063,
   oomd watched nothing; from 0063 until now, its swap rule watched
   nothing; in both cases every surface (service active, config
   printing limits) looked healthy. Per the incident-ships-its-
   detector convention, this task lands the check that makes that
   state visible.

## Change 1 — wire the swap rule

In `hosts/xps9370/default.nix`, next to the existing
`systemd.oomd.enableUserSlices = true`:

    systemd.slices."-".sliceConfig.ManagedOOMSwap = "kill";

**Placement, argued.** The root slice is the upstream recommendation,
verbatim from `systemd-oomd.service(8)`: "ManagedOOMSwap= works with
the system-wide swap values, so setting it on the root slice -.slice,
and allowing all descendant cgroups to be eligible candidates may make
the most sense." When system-wide swap use crosses the 90% default,
oomd kills the descendant leaf cgroup using the most swap — which on
this host is the runaway workload's cgroup, wherever it lives. The
same mechanism the NixOS module itself uses for its pressure options
(`systemd.slices.<name>.sliceConfig`) is used here, so the setting
survives module refactors the way the module's own settings do. It
lands in the host module, not `modules/`, for 0063's reason: the
zram-only-swap pairing is this host's observed configuration, and the
graduate-to-modules question already lives in
`docs/backlog/the-kernel-oom-killer-has-no-swap-headroom.md`.

The 90% `SwapUsedLimit` default stands untouched: on 7.7 GiB of zram
that leaves ~0.8 GiB of headroom at trigger time, and no data exists
yet to argue a different number. Tune it when the drill (below,
deferred) produces data.

## Change 2 — the liveness check

A small oneshot service plus timer on the host — declared in
`hosts/xps9370/default.nix` beside the settings it guards — that
fails, loudly, unless systemd-oomd is actually watching cgroups for
*both* of its rules:

- Runs shortly after boot (give oomd time to enumerate; order after
  `systemd-oomd.service` and add a modest delay or retry) and daily
  thereafter.
- Asserts, via `oomctl` output or equivalent, that at least one cgroup
  appears under "Swap Monitored CGroups" **and** at least one under
  "Memory Pressure Monitored CGroups". The implementer should run
  `oomctl` on a deployed system (or the VM check below) and parse what
  it actually prints, not what this brief remembers it printing. If a
  property query (`systemctl show`, D-Bus) is sturdier than parsing
  `oomctl`'s human-facing output, prefer it — but whatever is probed
  must reflect oomd's *runtime* view, not merely the unit files, since
  "configured but not watching" is the exact state this check exists
  to catch.
- On failure the unit fails: visible in `systemctl --failed`, in the
  journal, and thereby to whatever machinery later reads either (the
  crash-inquest seat, when it exists). No new notification channel is
  invented here.

This check is this incident's detector: it would have flagged the gap
the day 0063 deployed, and it catches the config regressing silently
in any future NixOS upgrade that changes what these options render to.

## Change 3 — the falsified comment

The comment block above `systemd.oomd.enableUserSlices` in
`hosts/xps9370/default.nix` claims "a runaway workload gets its cgroup
killed by memory pressure before the whole machine starves." The
2026-09-15 crash falsified that as written. Rewrite the block to say
what is now true: the swap rule is the primary trigger for this host's
exhaustion mode, the pressure rule is the backstop, the liveness check
guards both, and the 2026-09-15 recurrence is the citation.

## Change 4 — the backlog entry keeps the remainder

Amend `docs/backlog/the-kernel-oom-killer-has-no-swap-headroom.md`, in
the same commit that wires the rule:

- Record the 2026-09-15 recurrence in one short paragraph (second
  occurrence; pressure rule live but did not fire; culprit unlogged).
- Note that the userspace swap rule is now wired by this task, so the
  entry's remaining scope is the disk swap partition itself.
- Add the open question this incident surfaced: a defense that has
  never been exercised is only a claim. A deliberate memory-exhaustion
  drill in a VM — proving oomd actually kills the runaway cgroup, and
  measuring which trigger fires first — belongs with the disk-swap
  work, which changes the dynamics the drill would measure.

## Considered and rejected

- **Shortening `ManagedOOMMemoryPressureDurationSec`.** Tempting after
  a race lost by 30 s of averaging, but there is no data to pick a
  number, and the swap rule is the trigger actually matched to this
  failure mode. Revisit with drill data rather than guess twice.
- **A NixOS `assertion` instead of a runtime check.** Assertions see
  the evaluated config, and the failure mode on record is precisely a
  config that evaluates fine while the daemon watches nothing.
- **Placing the liveness check in `modules/`.** The generalization
  question ("any host running agent workloads") is real and already
  parked in the backlog entry; deciding it is not this task.

## Verification

Machine-checkable by the implementer:

- `nix flake check` stays green.
- `nix eval` on the example configuration shows the root slice's
  `sliceConfig` carrying `ManagedOOMSwap = "kill"` and the liveness
  units present.
- If a NixOS VM test is cheap to add for the liveness check (boot the
  VM, expect the check unit to *fail* when oomd watches nothing, or
  pass under the full config), add it; if it is not cheap, say so in
  the PR rather than building a harness for a one-off — but note the
  check itself then remains unproven until deploy, and say that too.

Human steps (the resident's, after deploy — deployment stays the
resident's act):

- `oomctl` shows non-empty lists for **both** rules — the exact probe
  that found them empty on 2026-09-06 and half-empty on 2026-09-15.
- `systemctl status` on the liveness unit shows a clean pass.

## Non-goals

The disk swap partition (stays in the backlog entry, deliberately
deferred with its disko and hibernation entanglements), the
memory-exhaustion drill (recorded there by Change 4), and any change
to `modules/` (the graduation question stays parked).
