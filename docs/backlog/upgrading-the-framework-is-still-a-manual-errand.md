# Upgrading the framework is still a manual errand

**What.** On 2026-09-05 the machine was brought from framework revision
`61bfdce` to `2ac3ac3` — seven merged pull requests, including fixes
the resident was actively waiting on — and every step happened outside
the system: an agent session edited `flake.lock` in the private
checkout and committed it by hand, pre-built the closure by hand, and
the resident typed `nixos-rebuild switch` at a prompt. No journal
entry was written, no question was filed, no approval was spent. The resident's
direction, stated the same day: **they should never have to run the
rebuild command themselves.** Entering a password somewhere along the
way is acceptable; typing the command is not.

**What already exists, and what is missing.** This is deliberately not
a re-ask of `docs/tasks/done/0048-activation.md`, which built the whole
downstream cycle: a framework pin bump is one of its two rebuild
triggers, the build happens silently, activation is offered as a
question through the review flow, the switch runs from a privileged
oneshot under a scoped grant, and an unconfirmed switch rolls back.
What 0048 activates is a pin bump that has already landed. Nothing
anywhere *produces* that pin bump: no seat watches the framework's
main branch, notices the deployed revision has fallen behind, and
proposes the upgrade. The loop has a motor for its second half and no
ignition for its first — so the first half keeps being done by hand,
and a hand-made bump in a working tree bypasses the journal entirely.
That is why today's upgrade left nothing on the books: it took the
manual path whose downstream half 0048 already retired, and so never
reached the half that would have journaled it.

**Why it matters.** An upgrade is the change most likely to carry the
fixes the resident is waiting on, so it is the change most often
performed impatiently, by hand, off the books — today's instance
included the agent layer's own bug fixes. Every manual upgrade is a
missed rehearsal of the activation cycle, and the activation cycle is
the piece that most needs rehearsals:
[[activation-is-not-proven-on-a-real-vm]] records that no real machine
has ever run it end to end. The two gaps feed each other — the cycle
stays unproven because upgrades keep going around it, and upgrades
keep going around it because nobody trusts an unproven cycle with the
machine.

**What it needs, roughly.** An initiator: something periodic (the
dispatch timer's shape, or `emcee tend`'s) that compares the pinned
framework revision against upstream main and, on a gap, files the pin
bump through the existing lanes — as a proposal the resident approves,
riding 0048's own framework-pin trigger from there. Judgment about
*when* to propose (every commit? weekly? on request?) is private-layer
configuration; the mechanism is public. The resident's password
boundary maps onto what 0048 already built: the polkit-gated start of
the privileged unit is an acceptable place for a password, the
terminal is not an acceptable place for a command.

**Why it can wait, barely.** The pieces compose today with one manual
act instead of four: a resident (or session) can bump the pin as an
ordinary journaled change and let 0048 carry it from there — worth
doing on the very next upgrade, both as rehearsal and as the habit
this entry wants to make structural. And
[[activation-is-not-proven-on-a-real-vm]] is the honest prerequisite:
an initiator that files upgrades into an unproven activation cycle
just automates the queue in front of an untested door.
