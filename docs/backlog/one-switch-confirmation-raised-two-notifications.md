# One switch confirmation raised two notifications

**What.** On 2026-09-05, the resident's confirmation of an activation
("You confirmed the new configuration is working") produced two
separate desktop notifications for what reads as one event. Reported
from live use; not yet reproduced.

**What the journal says, and does not say.** The final confirmation
result carries exactly one router decision, so the duplication is not
two routing decisions for one record. Unverified candidates: the
result and a near-simultaneous sibling record both routing to notify
with similar prose seconds apart (the activation flow files several
records in quick succession); the notify waiter firing twice for one
decision; or something in the activation-window units notifying on
their own beside the router's channel. One false lead is disarmed
here so the eventual investigator does not take it: the confirmation
question's `refs` entry names the same result twice, which looks like
duplication but is deliberate self-anchoring — `agent/castle`
documents it where the record is written, and both positional refs
conventions depend on it. It is not this bug.

**Why it can wait.** Two notifications for one good event is noise,
not damage, and the notify path is due for attention anyway when the
ambient channel lands ([[nothing-ambient-says-items-are-waiting]]).
Whoever picks either up should reproduce this first and replace the
candidate list above with a diagnosis.
