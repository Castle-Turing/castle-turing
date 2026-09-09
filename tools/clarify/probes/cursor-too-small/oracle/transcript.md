# Transcript — cursor-too-small (oracle run)

The conversation a phase running the discipline over the seeded
statement would produce. It exists to demonstrate that both seeds are
catchable — a seeded probe nothing could catch measures the seeder, not
the phase — and it doubles as the worked example the checks are
regression-tested against.

## utterance U1
speaker: resident
date: 2026-09-08

The mouse cursor is too small to find on this laptop's panel.

The value belongs in the host module rather than the shared desktop
module, because the right size depends on which panel is in front of me.

## question Q1
clause: cursor-visible-size
tag: vagueness
type: discriminating

How will you know the cursor is big enough? I sampled two readings of
"too small" and they build different things: one ends with a sweep you
look at on the hardware and keep whichever size reads best, the other
ends with a size computed from the panel's scale that nobody ever
looked at. Is the acceptance test your own eye, a number you want it to
reach, or some other thing entirely?

## utterance U2
speaker: resident
date: 2026-09-08
answers: Q1

My eye. Put candidate sizes up side by side, I pick one. A computed
number that nobody looked at is how it got this wrong in the first
place.

## question Q2
clause: cursor-surface
tag: semantic
type: discriminating

Which cursor is this about? Sampling implementations of the statement
gives me three that all satisfy it and share no code: the pointer Sway
itself draws, the pointer XWayland and GTK clients draw at their own
scale, and the console cursor before a graphical session exists. Which
surface is the one you are looking at when it is too small — and is it
only that one, or some other as well?

## utterance U3
speaker: resident
date: 2026-09-08
answers: Q2

The one I use all day, in the compositor. Whether the console one at
boot matters I genuinely have not thought about — leave it noted and
we can find out.

## question Q3
type: clearinghouse

What have I not asked about that matters here? I have what the target
is and which surface it lives on; anything I have missed that would
change what gets built?

## utterance U4
speaker: resident
date: 2026-09-08
answers: Q3

Only that the sweep tool already exists for this and should be the way
the number gets picked. Do not reason a value into place; run the sweep
and look.

## utterance U5
speaker: resident
date: 2026-09-08
substantive: no
reason: closing acknowledgement, carries no requirement

That is all of it, thanks.

## stop
reason: below-threshold
best-remaining: 0.06
leading-weight: 0.68
alpha: 0.25

The leading interpretation — enlarge the compositor's own pointer to a
size chosen by sweeping candidates and looking, with the value at host
level — carries 0.68 of the sampled weight. The best remaining
question (whether the console cursor at boot is in scope) is worth 0.06
against a redundancy penalty for having already touched that clause in
Q2, which is below 0.25 x 0.68 = 0.17. It is not dropped: it is carried
into the requirements document as an open semantic ambiguity, which is
what the phase does with a question not worth the resident's attention
right now.
