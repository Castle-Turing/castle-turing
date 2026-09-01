# Chat mode implies a conversational turn contract

**What.** The resident already knows the unified modal (task 0034)
will eventually want a **chat** view alongside compose, answer, and
review: not "file a request and walk away" but a live exchange with
the intelligence in the OS. The current worker contract cannot carry
it: a turn is one-shot by design — a fresh tenant, everything it
needs re-fed cold from the journal (0023), one result record at the
end. A conversation needs either a tenant that stays resident for its
duration, or turns fast and cheap enough that the journal round-trip
*is* the conversation — and each option reopens settled questions:
what a claim/result pair means mid-conversation, what the journal
records (every exchange? a summary? — the byte-fidelity discipline of
0033 suggests the former), what a hung conversational tenant does to
the worker seat, and what it costs.

**Why it can wait.** Compose-and-notify covers the request-shaped
majority of interactions today, and the plumbing above is a
project-sized decision, not a modal view. Filed so the modal's view
architecture (0034) is built knowing a sibling is coming, not so
anyone builds it soon.
