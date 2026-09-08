# Seed record — cursor-too-small

Floor-coverage: 1.0
Ceiling-redundancy: 0.0
Registered: 2026-09-08
Class: first-contact statement, no authority touched

**This file is the probe's ground truth and is never copied into a run
directory.** `clarify probe build` writes only the seeded statement; the
phase runs against that and never sees this. The floor and the ceiling
above were declared before the first run, per Proposal 06's third salt
discipline — a floor chosen after seeing a score is not a floor — and
changing either is a decision somebody has to make on the record, not a
tuning step.

## Why this statement

"The cursor is too small" is a real past request from this repo's own
history: it is the complaint behind
`docs/tasks/done/0013-first-deploy-findings.md`, whose fix
`docs/tasks/done/0017-legible-defaults.md` then generalised. It is small,
it is real, and — unusually for a probe — its true requirements are now
known history, so a phase that gets it wrong can be shown to be wrong
rather than merely disagreed with.

`source.md` is that request written out *completely*: every question a
competent phase would have had to ask, already answered. The seeds below
delete answers out of it. **Deletion only, never contradiction** — the
ClarifyCodeBench discipline, because deletion cannot accidentally
manufacture an inconsistency while aiming for an ambiguity. `clarify
probe build` proves the discipline held rather than trusting it: the
seeded statement must be a subsequence of `source.md`.

Both seeds are goal-level on purpose. Goal clarification is the one kind
whose measured value collapses if it is not asked early, so it is the
kind a probe should be able to tell whether the phase reaches.

## seed S1
expect-tag: vagueness
expect-level: goal
expect-terms: big enough, how will you know, how do you know, looked at, by eye, acceptance, done

Deleting the acceptance criterion leaves "too small" with no test
attached. Nothing in the remaining statement says how anyone would know
the cursor had become big enough — by eye on the hardware, or by
reaching some number — and the two answers produce different work: one
of them ends in a sweep the resident looks at, the other in an
arithmetic the resident never sees. That is the vagueness category:
"too small" is a degree word with no scale behind it.

```delete

Done means I have looked at the cursor on the real hardware and said it
is right. A number reasoned out from the panel's resolution and never
looked at does not count, whatever it computes to.
```

## seed S2
expect-tag: semantic
expect-level: goal
expect-terms: which cursor, sway, xwayland, gtk, console, which surface

Deleting the scoping paragraph leaves "the mouse cursor" spanning at
least three surfaces that are drawn by different code and fixed by
different changes: the one the compositor draws, the one XWayland and
GTK clients draw at their own scale, and the console cursor before a
graphical session exists. A phase that picks one silently produces a
clean, plausible artifact aimed at the wrong surface, which is the
named primary failure this whole phase exists to prevent.

```delete

I mean the cursor Sway itself draws. The XWayland and GTK cursor-scaling
gap is a separate problem and is not part of this.
```
