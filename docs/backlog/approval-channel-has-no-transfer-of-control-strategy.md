# The approval channel has no transfer-of-control strategy

*Filed by `docs/tasks/0025-approval.md` §L, which built the approval
channel and deliberately did not build any part of this. A finding, not
a solved problem.*

**What.** A proposed configuration change waits for the resident
indefinitely. Nothing expires it, nothing auto-approves it, nothing
auto-cancels it, and nothing re-asks. That is the right default for
this channel and it is not a strategy — it is one fixed posture, chosen
once, for a case where doing nothing happens to be defensible.

**Why it matters.** `docs/backlog/authority-taxonomy-prior-art.md`
records USC's Electric Elves running exactly this experiment for seven
months and producing four named catastrophes, **every one of them a
transition failure**, in both directions. Before their system had a
timeout, an agent waited indefinitely for a user who never answered and
miscoordinated with everyone else. After they added one, a timeout
forced an autonomous choice and cancelled the weekly research meeting.
The authors' own conclusion: "rigidly transferring control to one agent
(user) failed. Furthermore, using a time-out that rigidly transferred
control back to the agent… also failed."

Castle's config-commit case sits in the regime where the *first*
posture is safe: nobody else is waiting, the wait cost is about zero,
and the change is reversible by design. So 0025 waits, forever, on
purpose. The risk is not in that decision. The risk is that the posture
gets copied — to mail, to a meeting decline, to anything with a third
party on the other end — without anyone re-deriving whether the wait
cost and the response probability still make "just wait" correct there.
Those are precisely the parameters E-Elves' own boundary condition
names, and precisely the ones that swing hardest in a channel where the
resident is sometimes deliberately unreachable, which is the product.

**What we already know.**

- The two catastrophe directions are symmetric, and adding a timeout is
  not the fix for either. It is the second one.
- E-Elves' actual fix was a *transfer-of-control strategy*: a
  pre-defined conditional sequence of control transfers and coordination
  changes, rather than a single rule. After it shipped, "the agents have
  never repeated any of the catastrophic mistakes."
- The missing move in Castle's current vocabulary is the **fourth**
  one — not act, not hand control back, but **change the coordination
  constraints**: buy time, stall cheaply, de-escalate, lower the stakes.
  An auto-reply saying "let me check and come back to you" is not a
  decision at any tier; it is what lets an approval channel survive an
  unreachable resident. It fixed two of the four E-Elves catastrophes.
- **That move is router work, not approval-surface work.** An approval
  surface can show a change and take a verdict. Deciding to stall, to
  de-escalate, or to lower the stakes of a pending item is a decision
  about a channel's coordination with something outside the machine, and
  it belongs where channel decisions already live.
- Two cheap things that do **not** transfer authority in either
  direction are already built by 0025 and should not be mistaken for a
  strategy: the status surface says a change is waiting and how many,
  and `defer` gives the resident an attributable, recorded way to say
  "not now" — distinguishable, unlike silence, from never having looked.

**Open questions.**

- Which channels does this actually bite for? Mail and calendar are the
  obvious candidates and neither exists yet, so the honest answer today
  is "none" — which is why this is filed rather than specced.
- Is the strategy per channel, or one mechanism the channels
  parameterize? E-Elves used one mechanism with per-decision parameters,
  and Principle 01 would want the mechanism public and the parameters in
  the private layer.
- What records a stall? A coordination change made on the resident's
  behalf is a thing the system did, and the journal has no vocabulary
  for it. Inventing one is the part that needs care: `docs/backlog/
  authority-taxonomy-prior-art.md` warns specifically against
  introducing new authority vocabulary casually.
- Does any of it touch the approval channel this entry came out of? The
  argument above says no — the wait cost there is genuinely zero — and
  that answer should be re-derived rather than inherited if anything
  ever proposes to change it.
