# A design principle: extract contracts from the second implementation, not before

**What.** Draft a numbered design principle for `docs/principles/`
stating that contracts and abstractions in this project are extracted
only once a second real implementation makes code demonstrably repeat
— never designed ahead of one. DRY as the trigger, not foresight; no
big design up front for interfaces nobody has needed twice yet.

Per this repo's own conventions, a principle doc is a commitment
drafted and adopted in a PR, not something a backlog entry can write
into existence. This entry records the intent and the argument for it;
it is not the principle, and does not pre-empt what the principle PR
would actually say.

**Why it matters.** The project already reasons this way ad hoc.
`docs/backlog/worker-contract-generality.md` treats the diff-producing
worker contract as provisional, explicitly deferring generalization
until more non-diff errands have been tried by hand. Stating that
reasoning as a principle would let the next few contract-shaped
questions — the office contract in
`docs/backlog/office-contract-extracted-by-repetition.md` among them —
get decided by a standing rule instead of re-litigated individually
each time, and would give a future PR reviewer something to check a
premature abstraction against besides taste.

**What we already know.** One piece of supporting evidence, from
outside this repo: the Chevaline repo initially framed itself as an
open standard ahead of any implementation, and had to be reframed as a
config format once real use showed what it actually needed to be. A
principle of this shape, if it had existed first, would have given
that framing something to be checked against before it shipped.

**Promotion condition.** The next time a contract-or-abstraction
decision actually arises — `docs/backlog/office-contract-extracted-by-
repetition.md` reaching its own promotion condition would qualify —
draft the principle PR first, and decide that case under it rather
than deciding the case and writing the principle after the fact to
match.

**Open questions.** How this principle should be worded to interact
with Principle 01's public-mechanism/private-configuration split,
which is itself a standing abstraction adopted before a second
implementation existed — whether that's a justified exception or a
precedent this principle would have to explain away. What counts as
"a second real implementation" precisely enough to stop the principle
itself from being litigated case by case. Neither is resolved here;
both belong to the principle PR when it's drafted.
