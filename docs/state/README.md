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

## The public/private line, drawn explicitly

CLAUDE.md's hard rule bans the resident's *stated priorities* from
this repo, and a milestone document is exactly the kind of file that
could drift across that line — so the line is stated rather than
assumed, per Principle 01's test. What belongs here: the public
framework's own direction — what the castle is building next, which
is mechanism anyone deploying this repo inherits and every worker
must read. What must never appear here: the resident's life — email
priorities, calendar shape, people, plans, the stated-priorities
document the vision describes, which lives in the private layer and
nowhere else. The test for a milestone clause is the same as for any
file: would this sentence be true and appropriate for a stranger's
deployment of the framework to contain about *its* development? "The
modal's UX gets redesigned by the pipeline" passes; anything about
what the resident does with their days does not.

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

## Requirements documents

A second kind of document is admitted to this directory, deliberately
and under rule 4 above: the output of the clarifying-questions phase.
One per statement the resident makes, promoted into or superseded by
the milestone file as the resident decides. The reason it belongs here
rather than in the records is that it is the definition of work not yet
done — a thing later work must read as *current*, and must re-read when
it changes, which is exactly the property that separates this directory
from `docs/tasks/`. Task 0065 is the brief;
`docs/clarifying-questions.md` is the mechanism, including the exact
grammar.

It is the same small structured prose as everything else here, with the
clause keys and the `[stated <date>]`/`[inferred]` marks already
described above, plus three additions that carry the unresolved part
forward instead of losing it:

- `Level:` on each clause — `goal`, `input` or `constraint`. What kind
  of thing the clause fixes, which decides what may be asked late and
  what may not be asked at all.
- `Traces:` on each clause — the utterances behind it. A `[stated]`
  clause that traces to nothing is either an invention or an
  `[inferred]` clause that has not admitted it.
- `Ambiguity:` lines — one per unresolved reading, with the category,
  the share of sampled interpretations holding the leading reading, and
  a state of `open`, `deferred` or `cleared`. `cleared` cites the
  answer that cleared it. Nothing is closed by silent choice.

Three rules bind these documents beyond the four above.

**A requirements document declares its own thresholds** in its header —
the nocuity threshold, the stopping fraction, the question budget —
before the phase runs against it. A threshold chosen after seeing where
the phase landed is not a threshold, and `tools/clarify/clarify`
refuses a document that declares none.

**A probe artifact may never sit in this directory.** A probe run
produces a document shaped exactly like one of these, and nothing but
its `Probe:` header distinguishes the two. The checker enforces the
separation in both directions: a document here carrying that header
fails, and a probe run whose document omits it fails. This is Proposal
06's salt discipline in a second medium.

**Open ambiguities are a feature of a finished document, not a defect
in it.** A requirements document with nothing open is not necessarily
better than one with three; it may simply be one whose author decided
rather than asked. A deletion of an open ambiguity gets the same
scrutiny rule 2 gives any deletion here, and for the same reason.
