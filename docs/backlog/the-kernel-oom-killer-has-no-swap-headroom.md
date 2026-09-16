# The kernel OOM killer has no swap headroom

**What.** The 2026-09-06 memory-exhaustion crash (see
`a-crash-goes-uninvestigated.md`) revealed two absent OOM defenses on
the host (16 GB, the xps9370). The userspace half — systemd-oomd
running but watching zero cgroups — was specced and fixed directly by
task 0063 (`systemd.oomd.enableUserSlices` in the host module). This
entry records the half that task deferred as the more involved: with
only zram swap — compressed swap living in RAM itself, no disk swap —
the kernel can thrash in reclaim almost indefinitely without the
kernel OOM killer's threshold tripping, because the "swap" being
consumed is the same RAM that is exhausted. In the incident it never
tripped at all; the machine hung until the resident held the power
button. oomd now covers the user slices, but anything that exhausts
memory outside a watched slice still reproduces the hang.

**2026-09-15 recurrence.** The failure mode recurred — this host's
second hard hang from memory exhaustion, ~22:55, again requiring the
power button. Task 0063's pressure rule was live this time (unlike
2026-09-06) and still did not fire: roughly 90 seconds of visible
memory pressure preceded the hang with no kill logged, and the
culprit process was never identified either way — the journal goes
silent with nothing naming what allocated the memory (see
`a-crash-goes-uninvestigated.md`). The same inquest also found that
0063's own fix had a gap nobody had checked: the userspace *swap*
rule — the trigger actually matched to this exhaustion mode, per
`systemd-oomd.service(8)` — was never wired by any NixOS option, so
it had watched zero cgroups from the day 0063 shipped until now. Task
0073 (`docs/tasks/0073-the-oomd-swap-rule-and-a-liveness-check.md`)
wires that rule and adds a liveness check that fails loudly if either
rule's watch list is ever empty again. This entry's remaining scope
narrows to the disk swap partition below.

**The work.** A modest disk swap partition. More involved than it
sounds on this host: the disk layout is declared in
`hosts/xps9370/disko.nix`, so a swap partition means either a resize
of the existing layout on a machine already installed, or a
re-install against an amended layout — and the host module's
hibernation reasoning (`castle.power.criticalPowerAction` is
`PowerOff` precisely because there is nowhere to write a hibernation
image) gets revisited by the same change, deliberately or not.

**Open questions, carried from the incident and tasks 0063 and 0073.**

- Kill-target policy: whether watching user slices kills the right
  victim on a box whose compositor also lives in the user session —
  task 0063 accepts this risk explicitly; the swap work should
  confirm or fix it.
- Whether the agent layer should learn, via journal or notification,
  when oomd kills something it was running — a silent kill of an
  agent's work is a smaller version of the crash this entry comes
  from.
- Whether `systemd.oomd.enableUserSlices` and the root slice's
  `ManagedOOMSwap = "kill"` (task 0073) should graduate from
  host-module fixes to a `modules/` default for any host running
  agent workloads — the general policy argued once, not implied by an
  incident.
- Whether a defense that has never been exercised is more than a
  claim. Both oomd rules are now wired and watched (task 0073's
  liveness check confirms the watching), but neither has ever been
  proven to actually kill the right cgroup under real exhaustion — a
  deliberate memory-exhaustion drill in a VM, proving oomd kills the
  runaway cgroup and measuring which trigger (swap vs. pressure) fires
  first, belongs with this disk-swap work, which changes the dynamics
  the drill would measure.
