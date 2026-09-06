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

**The work.** A modest disk swap partition. More involved than it
sounds on this host: the disk layout is declared in
`hosts/xps9370/disko.nix`, so a swap partition means either a resize
of the existing layout on a machine already installed, or a
re-install against an amended layout — and the host module's
hibernation reasoning (`castle.power.criticalPowerAction` is
`PowerOff` precisely because there is nowhere to write a hibernation
image) gets revisited by the same change, deliberately or not.

**Open questions, carried from the incident and task 0063.**

- Kill-target policy: whether watching user slices kills the right
  victim on a box whose compositor also lives in the user session —
  task 0063 accepts this risk explicitly; the swap work should
  confirm or fix it.
- Whether the agent layer should learn, via journal or notification,
  when oomd kills something it was running — a silent kill of an
  agent's work is a smaller version of the crash this entry comes
  from.
- Whether `systemd.oomd.enableUserSlices` should graduate from task
  0063's host-module fix to a `modules/` default for any host running
  agent workloads — the general policy argued once, not implied by an
  incident.
