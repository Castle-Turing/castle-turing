# Requirements — the cursor is too small (oracle run)

Probe: cursor-too-small
Transcript: transcript.md
Nocuity-threshold: 0.7
Stop-alpha: 0.25
Question-budget: 2

**This is a probe artifact, not current truth.** The `Probe:` header
above is what says so, and `clarify` refuses to accept a document
carrying it under `docs/state/`. Probe records are labelled and never
masquerade — Proposal 06's third salt discipline, applied here because
this file is shaped exactly like a document that *is* truth.

What it is: the read-back a phase running the discipline over the
seeded `cursor-too-small` statement would produce. It restates what the
system now believes it is building. It is not the transcript, and the
resident's verdict on this restatement — not on the conversation — is
the phase's exit gate.

## What is being built

### The cursor's visible size at the panel's default scale [cursor-visible-size]

Level: goal

[stated 2026-09-08] The compositor's pointer must be large enough for
the resident to find on the internal panel at its default scale, with
the size chosen by putting candidates side by side and looking at them
on the real hardware. A size derived by arithmetic and never looked at
does not satisfy this clause even if it computes to the same number.
Traces: U1, U2
Ambiguity: vagueness certainty=0.35 state=cleared ref=U2 — "too small" carried no scale: sampled readings split between a swept-and-looked-at value and a value computed from the panel scale, which build different work. The resident's answer settles it on the eye.

### The surface the cursor is drawn on [cursor-surface]

Level: goal

[stated 2026-09-08] The cursor in scope is the one the compositor
itself draws. The pointer XWayland and GTK clients draw at their own
scale is a separate surface and is not this clause.
Traces: U1, U3
Ambiguity: semantic certainty=0.45 state=open — whether the console cursor before a graphical session starts is also in scope. Asked as Q2 and answered only in part: the resident settled the compositor pointer and said explicitly that they had not thought about the console one. Carried forward rather than decided — an implementer meeting this clause must treat the console cursor as unsettled and must not quietly include or exclude it.

### How the value is picked [cursor-value-by-sweep]

Level: input

[stated 2026-09-08] The number is produced by running the existing
sweep tool over candidate values and choosing by eye, not reasoned into
place. The sweep, not the reasoning, is the mechanism.
Traces: U4
Ambiguity: lexical certainty=0.85 state=open — "the sweep tool" names one tool among several sweeps in the repo. Innocuous at this document's tolerance: every sampled reading resolves it to the cursor-relevant one, so it was not worth a question, and it is recorded rather than dropped so a later reader can see the phase considered it.

## Where it lands

### Which host the value belongs to [cursor-target-host]

Level: constraint

[inferred] The value is host-level configuration rather than shared
desktop configuration, because the right size depends on the panel. The
statement says so; which host's module it lands in is read off the
deployment rather than stated here.
Ambiguity: semantic certainty=0.50 state=deferred — "this laptop's panel" names no host, and the statement's own reasoning ("the right size depends on which panel") makes the host a variable rather than a fact. Deferred rather than asked: it is constraint-level, the implementer reads it off the host being deployed to, and asking would spend the resident's attention on something no reading of it changes about what gets built.

## What this phase did not settle

The console cursor at boot is open, deliberately and on the record —
see `[cursor-surface]`. The XWayland and GTK cursor-scaling gap is out
of scope by the resident's own words and is not an open ambiguity; it
is a different problem with its own future statement.
