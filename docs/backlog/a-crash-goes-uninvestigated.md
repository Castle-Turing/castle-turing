# A crash goes uninvestigated unless the resident plays detective

**What.** On 2026-09-06 the machine crashed hard mid-session, killing
running processes — including a background research agent whose work
had to be noticed as missing and manually resumed. Nothing in castle
noticed the crash, investigated it, or said anything about it. The
resident discovered it, reported it to a session, and the session's
recovery was limited to checking what survived. Root cause: unknown,
because nobody looked.

**Why it matters.** The vision's whole premise is an agent at the
operating-system level whose second most common output is "a completed
action you only notice if you go looking." An unclean shutdown is the
purest possible case: the substrate is NixOS, so the evidence is
legible text the agent already speaks — the previous boot's journal,
coredump records, OOM-killer traces, thermal events — and the
follow-up actions (a config change proposal, a rollback suggestion)
are exactly the moves the plumbing already supports. Today that
evidence expires quietly while the resident restarts things by hand.
A resident-operated inquest is also the posture this project keeps
finding insufficient: vigilance where a mechanism should be.

**The shape of a fix, none of it decided.** Detection is cheap and
declarative: systemd knows a boot followed an unclean shutdown. On
such a boot, a seat runs a bounded, read-only inquest over the
previous boot's journal and coredump/OOM/thermal evidence, journals a
finding with the evidence cited (and a falsifier, per Proposal 06),
and routes it like any other decision — a digest line for a one-off,
something louder for a recurrence or a diagnosable cause with a
proposed remedy. Read-only investigation sits in the silent tier of
the authority taxonomy; anything it proposes goes through the normal
proposal channel.

**Boundaries worth keeping.** Recovering in-flight *work* after a
crash is the harness's problem (emcee's cheap-restart contract and
salvage already own it); castle's job is the machine-level inquest.
And kernel panics may leave no journal at all without
pstore/kdump-style capture, which is host configuration — the
mechanism should degrade gracefully to "crashed, cause not captured,
here is what capturing it would take," and any capture config belongs
in the host module, not `modules/`.

**Open questions.** Whether the inquest runs at boot or at the next
agent activation; what "recurrence" means concretely before the
pattern earns a louder channel; and whether the finding should feed
the same outbox that files findings from worker turns, so a
diagnosable systemic cause can become backlog work without a human
courier.

**Postscript, same day.** The motivating crash *was* root-caused —
manually, the next morning, by a session the resident prompted. The
full diagnosis came from exactly the sources this entry proposes the
inquest read (previous boot's journal: memory-pressure log flood from
00:39:51 to the power-button press at 00:42:22, nix-daemon connection
timeline, timer units that never printed a first line), which proves
the inquest is buildable from the journal alone, on this host, today.
What the manual run cost is the argument for the mechanism: the
evidence sat unread until a human asked, and the answer surfaced two
distinct config defects that had been silently latent — see
`the-kernel-oom-killer-has-no-swap-headroom.md` (its oomd sibling was
specced and fixed directly by task 0063) and
`an-agent-workload-can-thrash-the-host.md`, both filed from that
diagnosis.
