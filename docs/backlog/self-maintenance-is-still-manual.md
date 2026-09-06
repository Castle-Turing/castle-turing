# Self-maintenance is still manual, and the vision does not yet say otherwise

**What.** Stated as direction by the resident, 2026-09-06, on reading
the crash RCA follow-ups. The 2026-09-06 memory-exhaustion incident
was noticed by the resident, diagnosed by a session the resident
prompted, and repaired by a session the resident instructed. Every
step was correct and every step was manual. The direction: this class
of work belongs to castle itself. Castle Turing will be
self-assembling — and also **self-monitoring, self-updating, and
self-repairing**. Per the resident, these have been core to the
vision since the beginning, even though the vision does not yet name
them; adding them to the vision is the resident's writing to do, not
a seat's.

**This is a family, not a new list.** The backlog already holds its
instances, filed separately as they were tripped over:

- *Self-monitoring:* `a-crash-goes-uninvestigated.md` — the inquest
  that should have run itself.
- *Self-repairing:* task 0063's oomd fix and its deferred remainder
  `the-kernel-oom-killer-has-no-swap-headroom.md` (the fix was a
  session's act; the end state is castle proposing such fixes through
  its own proposal channel), `headless-recovery.md`,
  `rollback-may-die-before-it-rolls-back.md`.
- *Self-updating:* `upgrading-the-framework-is-still-a-manual-errand.md`.

What this entry adds is the claim that these are one capability with
one architecture: specialized agents fluent in the substrate (Nix,
systemd, the journal), operating under the authority taxonomy —
knowing exactly what they may do silently, what they do-then-report,
and when to escalate to an authority. The escalation judgment is the
product; the vision already says the taxonomy is the actual spec, and
self-maintenance is that claim applied to operations.

**A second half of this direction lives in the private layer.** The
resident recorded further reasoning about where this capability
leads, and deferred the decision about whether it belongs in the
public record; until that decision, it stays in the resident's own
layer, per the same split that governs everything else here.

**Open questions.** Which of the instance entries above is the right
first buildable piece — the crash inquest is the current
front-runner, since its evidence, mechanism, and motivating incident
are all already on file — and whether the desktop's dogfooding data
is yet rich enough to start specializing agents at these tasks, or
whether that comes only after the milestone-two pipeline has run for
a while.
