# A convention carries no falsifier and cannot die

**What.** Conventions in this project accumulate and never retire.
Each is adopted deliberately — a principle doc is a commitment, a
CLAUDE.md section is a rule the rest runs on — but nothing about an
adopted convention states how anyone would later know it is working,
or that it has outlived its purpose. So the corpus of rules only
grows, and an unmeasured convention cannot be shown to have failed;
it can only be argued away. This is the keystone the
[[the-corpus-is-never-swept-against-the-conventions]] entry
deliberately left as its own problem: that entry sweeps the corpus
against the rules; this one asks the rules to carry the measurement
that lets them be swept against reality — and retired when reality
says so.

**Why it matters.** Two live concerns converge here, both named
during the 2026-09-10 design discussion.

- *Where new conventions come from.* Conventions are invented
  continuously through practice and research. Practice surfaces them
  through the feedback-routing seat
  ([[feedback-routing-is-an-unnamed-seat]]): a correction that
  recurs is a convention trying to be born — the "no-op is not
  fulfillment" rule was exactly a one-off correction promoted to
  standing guidance. Research surfaces them through sweeps whose
  syntheses each end in a "what the spec should say" list of
  proto-conventions (`docs/research/aci-for-gui-building.md`,
  `docs/research/automated-approval.md`). Both paths already
  converge on one human gate: a convention becomes real only by
  landing in a numbered principle, a CLAUDE.md section, or
  `docs/state/`, each of which requires the resident's explicit
  approval. Convention *creation* is divergent — it proposes a rule
  the system will be held to — and is therefore the one step the
  norm-gaveling razor keeps human. The lifecycle is not missing; it
  is implicit, and this entry makes it explicit.
- *Measurement, automatically, and ROI.* Sweep- and
  harness-based conventions cost tokens against uncertain yield. The
  concern that teams doing this well spend heavily is unverified as a
  figure, but the principle stands: a convention that costs resources
  must name the yield it buys, or its cost is invisible and
  permanent.

**The mechanism.** Extend the non-emptiness rule this project
already enforces in two places — Proposal 06 makes a decision name
its falsifier, and a task header makes `Model-because:` name why the
tier is right, both unfasifiable-if-blank by design. Add one step to
the birth of a convention: **at adoption, a convention states the
signal that would show it is working and the signal that would show
it should be retired, and that signal names a metric the outcome
baseline already collects or can** (`docs/log/`-style task-outcome
data; emcee's ledger for cost). This does three things at once:

1. It kills unmeasurable conventions before they calcify — if you
   cannot say what would falsify it, you are adding ritual, the exact
   defect `Model-because:` exists to catch.
2. It makes ROI structural rather than dependent on someone
   remembering to ask: a token-costing convention must name its yield,
   checked against the baseline.
3. It gives conventions a retirement path the project currently
   lacks. A convention with a named retirement signal can be swept
   *against its own metric* by the conformance machinery — the
   sibling of the corpus sweep: one checks the corpus against the
   rules, this one checks the rules against their stated payoff.

**How this would have been caught sooner.** It is not an incident but
a standing structural gap, surfaced by the resident asking where new
conventions come from and how measurement joins their lifecycle. The
detector the eventual brief owes is a check at adoption time: a
convention landing without a working-signal and a retirement-signal
is rejected the way a task file with no `Model-because:` is a flagged
default — and, because a validator can only confirm a string is
present, the real enforcement is the resident's spec gate and the
audit reading the diff, exactly as `Model-because:` is enforced by
people, not the harness. The retirement sweep is the mechanical half:
a scheduled pass that reports each convention against its own stated
metric, whose empty result ("all conventions still clear their
working-signal") is a receipt, not silence.

**The limit, stated so the spec keeps it.** This measures conventions
against their own stated payoff; it does not measure whether the
payoff was the right thing to want. Sweeps check corpus against
rules; this checks rules against their metric; only the resident's
gavel checks the metric against the vision. Automating the first two
must not create the impression the third is covered — the compass
stays human.

**Constraint at promotion time.** Pipeline-changing;
[m2-constraints] applies.

**Open questions.** Whether the working/retirement signal is a new
required field on principle docs and CLAUDE.md sections, or a
companion record keyed to each convention. What a convention whose
retirement signal has tripped actually triggers — an automatic
proposal to the resident, never an automatic removal, since retiring
a rule is as much a norm-gavel as adopting one. Whether the
feedback-router's recurrence signal (the same correction routing N
times) should auto-draft a proto-convention with a suggested
falsifier for the resident to ratify. And how conventions adopted
before this rule are retrofitted with falsifiers — itself a first
job for [[the-corpus-is-never-swept-against-the-conventions]].
