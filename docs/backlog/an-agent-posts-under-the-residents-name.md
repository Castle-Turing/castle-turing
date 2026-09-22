# An agent posts under the resident's name

**What.** Agents working on this repository reach the forge through the
resident's own credential. A pull-request comment written by an agent
and one written by the resident carry the same author. There is no
mechanical way, from the forge's record, to tell which of them said a
thing.

**Why it matters.** Task 0072 made `outcomes redirect` verify that a
cited comment was written by the configured resident, so that a verdict
in the outcome log points at a judgment the resident actually made.
That check does real work — it rules out citing a reviewer's comment, a
bot's, or anyone else's. It does not rule out citing the agent's own,
which is the fabrication that matters: an agent could write a comment
asserting a redirect and then cite it, and every mechanical check in
the chain would pass. PR #120 carries one comment of each kind, so this
is not hypothetical, it is the state of the archive the first verdict
datum was drawn from.

The same weakness reaches further than the log. Dispositions comments,
review findings and the handover ledger all rest on "who said this",
and all of them read the same undifferentiated author.

**What closes it.** A distinct machine identity for agent-authored
forge activity. The resident's profile already specifies one — an
organization-owned GitHub App whose installation token the workflows
mint per run, so that machine commits, pushes and comments attribute to
the app's own `[bot]` login rather than to the resident. Once agent
comments carry that login, the authorship check in `outcomes redirect`
separates the two cases rather than merely narrowing them, and the
residue left to the weekly audit shrinks to what it should be: whether
the cited text says what the row claims.

**How this would have been caught sooner.** By writing down, at the
point the check was designed, what the check actually excludes. Task
0072 did that in the command's help text — the boundary is stated where
the person using it will read it, rather than only in a brief. The
mechanical detector, once a bot identity exists: `outcomes check`
refuses a citation whose author is the bot, which turns "an agent may
not originate a verdict" from a sentence in a help text into a rule the
checker enforces offline. That check cannot be written until the
identity exists, and this entry is the record of why it is owed.

**Open questions.** Whether the distinction belongs in the log itself —
a citation recording *who* it resolved to, rather than only that it
resolved — so that a clone can re-check authorship without the forge.
That would make the log self-verifying on this axis at the cost of
putting a login in a file the project otherwise keeps content-free, and
the environment-key precedent suggests the answer is a key rather than
a name.
