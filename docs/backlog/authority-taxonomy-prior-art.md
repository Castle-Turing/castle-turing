# Test the authority taxonomy against the levels-of-automation record

*A research question, not deferred implementation. Citations here are
from memory and marked **[verify]** where unconfirmed.*

**What.** `docs/vision.md` says: "Decide the authority taxonomy early.
Which categories of decision are made silently, which are
made-then-reported, and which are queued for explicit approval. …This
taxonomy, more than any model capability, is the actual spec."
`docs/architecture.md` already carries its first entry — private-repo
commits as standing made-then-reported authority — and defers
autonomous deployment as "a real authority-taxonomy question for a
later task."

Human-factors engineering has worked this exact problem since 1951,
under the names *function allocation*, *levels of automation*, and
*adjustable autonomy*. We have not read any of it.

**The question.** Is a static, category-based, three-tier taxonomy the
right structure for delegated authority — or does the record show that
fixed allocations by decision category mispredict, that the dangerous
failures happen at *transitions* between authority levels (mode
confusion, automation surprise), and that what must be designed early
is the transition mechanics with the categories left mobile?

Answerable wrongly in both directions: the literature could endorse
fixed tiers for low-tempo domestic decisions even while rejecting them
for cockpits.

**Where the answer likely lives.** Sheridan & Verplank's ten levels of
automation (1978); Parasuraman, Sheridan & Wickens on types and levels
(2000); Fitts (1951) function allocation and its critique in Dekker &
Woods, "MABA-MABA or Abracadabra?" (2002); Billings, *Aviation
Automation* (1997); Sarter & Woods on mode confusion. Adjustable
autonomy: USC's Electric Elves **[verify]**. And most directly, Pattie
Maes, "Agents that Reduce Work and Information Overload" (CACM 1994) —
her interface agents implemented these exact three tiers as *learned
confidence thresholds* (do-it / tell-me / ask) rather than a written
document. That is the closest thing to a prior Castle Turing, thirty
years early, and it is worth reading whatever this brief concludes.

**What would change.** If fixed categories lose: the taxonomy document
gets restructured around per-domain thresholds plus explicitly designed
*promotion and demotion events* — a category changing tier is itself a
reported decision. "Decide early" gets reinterpreted as *freeze the
transition grammar early, not the assignments*. The vision's
competence-gating paragraph already points this way.

**Priority: high.** The architecture says the taxonomy will soon exist
as its own document, and autonomous deployment — its highest-stakes
entry — is explicitly queued. The cheapest moment to learn the field's
failure catalogue is before the document exists.
