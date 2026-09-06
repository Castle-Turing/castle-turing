# The host has no working out-of-memory defense

*The userspace half of this entry — systemd-oomd running with empty
watch lists — was promoted to task 0063 and fixed there
(`systemd.oomd.enableUserSlices` in the host module). What follows is
the remainder, deferred by the resident on 2026-09-06 as the more
involved half.*

**What remains.** The 2026-09-06 memory-exhaustion crash (see
`a-crash-goes-uninvestigated.md`) showed that with zram-only swap —
compressed swap living in RAM itself, no disk swap — the kernel OOM
killer effectively never trips: reclaim thrashes almost indefinitely
because the "swap" being consumed is the same RAM that is exhausted.
oomd now covers the user slices, but the kernel's own killer remains
without headroom, and anything that exhausts memory outside a watched
slice still reproduces the hang.

**The work.** A modest disk swap partition. More involved than it
sounds on this host: the disk layout is declared in
`hosts/xps9370/disko.nix`, so a swap partition means either a resize
of the existing layout on a machine already installed, or a
re-install against an amended layout — and the host module's
hibernation reasoning (`castle.power.criticalPowerAction` is
`PowerOff` precisely because there is nowhere to write a hibernation
image) gets revisited by the same change, deliberately or not.

**Open questions, carried from the incident.**

- Kill-target policy: whether watching user slices kills the right
  victim on a box whose compositor also lives in the user session —
  task 0063 accepts this risk explicitly; the swap work should
  confirm or fix it.
- Whether the agent layer should learn, via journal or notification,
  when oomd kills something it was running — a silent kill of an
  agent's work is a smaller version of the crash this entry comes
  from.
- Whether `systemd.oomd.enableUserSlices` should graduate from this
  host's fix to a `modules/` default for any host running agent
  workloads — the general policy argued once, not implied by an
  incident.
