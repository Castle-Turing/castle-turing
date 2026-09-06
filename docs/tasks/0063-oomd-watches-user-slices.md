Title: Task 0063 — systemd-oomd watches the user slices
Model: deep
Model-because: the diff is one line and the tier question is nearly
moot — this brief is implemented directly by the session holding the
full crash context, not queued. What earns the deliberate tier is the
placement call (host module beside the zram decision it repairs,
rather than a modules/ default) and the honesty about residual risk;
a smaller implementer following a one-line instruction could not have
argued either.

# Task 0063 — systemd-oomd watches the user slices

## Why, from the incident

On 2026-09-06 at 00:42 this host hard-hung from memory exhaustion —
three concurrent research subagents plus repeated nixpkgs evaluations
(~2 GB peak each) on 16 GB — and had to be power-buttoned. The
diagnosis from the previous boot's journal: with zram-only swap (the
compressed swap lives in RAM), reclaim thrashes almost indefinitely
without the kernel OOM killer's threshold tripping; and systemd-oomd,
the userspace killer built for exactly this, was running with empty
watch lists — `oomctl` showed no swap and no memory-pressure cgroups
monitored, because NixOS sets `ManagedOOMMemoryPressure=kill` on no
slice by default. It logged 71 pressure warnings and killed nothing.
Both safety nets absent; the resident was the safety net. Full record:
`docs/backlog/a-crash-goes-uninvestigated.md` (the missing inquest)
and `docs/backlog/an-agent-workload-can-thrash-the-host.md` (the
workload side).

## The change

`systemd.oomd.enableUserSlices = true;` in `hosts/xps9370/default.nix`,
placed directly beside `zramSwap.enable` — the two lines are one
decision now: zram-only swap is only livable with a userspace killer
watching the slices the workload runs in. On this host every agent
session runs in a user slice, so pressure from a runaway workload gets
its cgroup killed instead of starving the machine.

**Placement, argued.** The failure pairing (zram-only swap plus
oomd-watching-nothing) is this host's observed configuration, so the
fix lands in the host module. Whether `enableUserSlices` should become
a `modules/` default for any host running agent workloads is a real
question this brief deliberately does not answer — it stays in the
backlog entry with the swap work, where the general policy can be
argued once rather than implied by an incident fix.

**Residual risk, accepted.** oomd kills the highest-pressure cgroup
within the watched slice; the expectation (asserted by the diagnosing
session, untested here) is that the runaway session's cgroup, not the
compositor's, is what dies. If that expectation is wrong the failure
mode is a killed Sway session — worse than a killed agent, far better
than a power button. Revisit with the swap work, which changes the
pressure dynamics anyway.

## A second fix from the same incident

The tool whose absence the runaway improvised around is now declared:
`poppler-utils` (for `pdftotext`) joins `modules/dev`'s packages, per
the resident's direction on 2026-09-06. Placement, argued both ways:
not the host module, because needing PDF text extraction is a fact
about research workloads, not about this chassis; and `modules/dev`
rather than `modules/agent`, because the improvising agents were
subagents of an interactive development session — `modules/dev` is
where those sessions and their tools (claude-code itself) live, while
`modules/agent` is the castle seat runtime, which does no PDF
research today. If the castle workers ever do, that is the moment to
revisit. The tooling fix-direction in
`docs/backlog/an-agent-workload-can-thrash-the-host.md` is addressed
in part by this change and says so inline; its concurrency-cap and
worker-contract directions stay open. The
companion instruction — install or report missing tools, never
per-command nixpkgs invocations — went to the resident's agent
profile, which is outside this repo and noted here so the pairing is
findable.

## What this specs, and what it defers

The incident's OOM-defense finding splits in two, and this brief
specs the userspace half directly from the diagnosis — no
pre-existing backlog entry is promoted for it; the finding went from
the resident's root-cause report straight to this brief. The kernel
half — disk-swap headroom, more involved (disko layout, resize),
which the resident explicitly deferred — is recorded alongside this
brief as a fresh entry,
`docs/backlog/the-kernel-oom-killer-has-no-swap-headroom.md`,
which also carries the open questions this task leaves behind
(kill-target policy among them; see the entry for the full list).

## Verification

Machine-checkable now: `nix eval
.#nixosConfigurations.example.config.systemd.oomd.enableUserSlices`
returns `true` (the example configuration imports this host module),
and `nix flake check` stays green. Human-checkable after the resident
deploys (deployment stays the resident's act): `oomctl` shows
non-empty memory-pressure watch entries for the user slices — the
exact probe the incident diagnosis used to find them empty.
