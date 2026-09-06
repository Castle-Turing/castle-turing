# docs/state — what is true now

The documents in this directory are the repo's current truth:
maintained, authoritative, and safe to build on. Everything else
under `docs/` — task briefs, backlog entries, research reports, the
journal — is **record**: what was decided, found, or considered, and
when. The split exists because the two kinds age differently: a
record is finished the day it lands and only gains value by staying
exactly as written, while current truth is only worth reading if
something keeps it current. Task 0061 is the reasoning; the rules
below are its remainder, stated for a stranger.

## The rules

1. **Authority is a link; history is a name.** When work needs a
   *current* fact, it links into this directory. When it cites how a
   decision was reached, it names the record ("task 0048") and never
   links a path — records move to `done/`, and 140 rotted path
   citations are the scar that taught this. When later work finds
   itself citing a brief *as authority*, that is the signal to
   extract the load-bearing content into this directory in the same
   PR.
2. **The same-PR patch.** A pull request that changes what is true —
   completes milestone work, makes a design decision, retires a
   constraint — updates this directory in the same PR, and the
   reviewer reads the state diff as part of the review. A deletion
   here gets explicit review attention: premature deletion is the
   measured dominant failure of machine-maintained state.
3. **Deriving work cites clauses.** Documents here carry bracketed
   clause keys (`[m2-intent]`). A task derived from a clause cites
   its key, so a revision to the clause identifies exactly the tasks
   it invalidates.
4. **Deliberate accommodation.** Adding a document or a top-level
   section here is a deliberate act, recorded with one line of why in
   the PR that does it. Automatic schema induction is explicitly out
   of scope; an agent that repeatedly finds content with no slot may
   *propose* one, citing the recurring instances — only the resident
   closes that question.

## How state documents are written

Small structured prose — headings and clause keys, never an invented
schema language. Constraints that bind carry four fields in prose:
what must hold (prerequisite), who may waive it (authority), what to
do when it cannot hold (fallback), and what breaks when violated
(consequence). Constraint language is explicit, never hedged.
Clauses distinguish `[stated <date>]` — the resident's words — from
`[inferred]` — the system's reading, held until confirmed or
corrected; an unresolved ambiguity is tagged in place, cleared only
by a cited answer, and never resolved by silent choice. The evidence
behind every one of these rules is in
`docs/research/inter-task-handoff.md` and
`docs/research/elicitation-papers.md`; task 0061 compresses it.
