# The resident cannot speak unbidden

**What.** Read the record grammar as a conversation and an asymmetry
falls out. The system may speak on its own initiative — that is exactly
what `provenance: initiated` means. The resident may not. A resident can
open an errand (`request`) and answer a question the system posed
(`answer`), and that is the entire vocabulary available to them.

**There is no record a resident can file, unprompted, about the system's
own behavior.** "Stop bugging me when I'm watching Netflix" has nowhere
to land. Neither does "that was the right call," "you asked me that
already," or "never do that again without checking."

**Why it matters.** The vision's whole power structure is a resident who
delegates authority and can withdraw it — "force is the escalation of a
conversation," corrections during the weekly audit are "the training
signal." A grammar in which the system initiates and the resident only
responds inverts that, and it inverted it by accident, in a type enum,
without anyone deciding to.

It is also a practical loss, not only a philosophical one. Volunteered
corrections are the highest-signal feedback the system will ever
receive, precisely *because* they were unprompted: the resident thought
it important enough to interrupt the machine over. The architecture
currently discards exactly that class of input, or forces it through
`request` — where it reads as an errand to execute rather than a
judgment about how the system behaves.

**The shape of the fix (not yet decided).** A `correction` record type
looks right: resident-authored, arriving through the existing intake
surface (which already takes free text and adds no judgment), `refs`-ing
whatever it arrived attached to — usually the offending intervention's
decision record, which the delivering surface can supply automatically.

Three things worth arguing about before writing it:

- **Not an `answer` to a phantom question.** Modelling it that way is
  tidy and wrong: it erases the record's most valuable property, that it
  was volunteered, and `answer` closes a question where a correction
  often refs a decision or nothing at all.
- **Not a new seat.** Intake captures it; whichever seat processes
  corrections classifies it downstream. The resident must never have to
  know the taxonomy to use it.
- **It produces two artifacts, not three.** The correction record
  itself, and a resident-model entry citing it. The "rule for future
  decisions" is not a third thing — the router reads the resident model,
  so a preference entry *is* the policy. Do not invent a rules engine
  beside the model.

**Its one collision with Proposal 05.** A volunteered statement was
never elicited by a question, so the model's provenance vocabulary needs
`volunteered` alongside elicited. That is a clarification rather than a
breach: what Proposal 05 protects is resident *authorship*, not the
formality of having been asked. A volunteered statement is stronger
evidence of intent than an answer, not weaker.

**Note on generalization.** "Stop bugging me when I'm watching Netflix"
should be transcribed *narrowly* — that app, silence. Where the broader
reading tempts (all fullscreen video? all evening leisure?), the seat
opens a question rather than writing the broad rule. That is Proposal
05's grammar exactly: inference opens, the resident closes.

**Related.** `docs/architecture.md`'s Proposal 06 draft, which this is
the buildable half of. The other half — receipts, and what may be
inferred from how an intervention was received — needs a delivery
surface that can actually report reception, and should wait for one.
