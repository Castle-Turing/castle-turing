# A Castle-level office interface — not designed until a second one exists

**A word about the name.** "Office" is used throughout this entry in
preference to "department," because an office is the term a castle's
own running would actually use for a standing function with a defined
remit. Neither word is a settled decision — this entry names the thing
enough to talk about it, not enough to commit to what it's called.

**What.** Emcee, the agentic software-development harness now being
built, will be Castle Turing's first office: a detached run that takes
briefs in, produces artifacts plus escalations out, writes its
decisions in the journal format, notifies through the castle's
channels, and has no direct line to the resident. That shape sits
close to `docs/architecture.md`'s worker contract but is a distinct
question from it. `docs/backlog/worker-contract-generality.md` already
asks whether the diff-producing worker contract is the only shape a
Castle Turing *worker* should have; this entry asks the same kind of
question one layer up — whether Emcee's specific dispatch, parking,
journal-write, and channel-delivery pattern is itself the general
*office* contract, or one office among several with no shared shape at
all.

Proposal: a Castle-level office interface. Deliberately **not**
designed now — there is exactly one implementation to draw it from,
and one implementation cannot tell you which parts of its shape are
load-bearing and which are accidents of how it happened to get built.

**Why it matters.** If a second office is ever built (see
`docs/backlog/email-office.md`, the office most likely to be built
next) without a stated office contract, its author either reinvents
Emcee's plumbing from scratch or copies it ad hoc, and neither path
leaves behind a documented interface anyone can build a third office
against. Extracting the contract from a single case also risks
extracting it wrong — generalizing details that were really specific
to running an agentic dev harness against a git repo.

**What we already know.** Emcee does not exist as a committed spec at
the time of filing; its shape here is inferred from the design
discussion that produced this entry, not from code or a brief in
`docs/tasks/`. Nothing in this entry should be read as a specification
of Emcee itself, and this entry should not be cited as one.

**Promotion condition.** A second office's implementation begins
copying Emcee's dispatch, parking, journal-write, or channel-delivery
code — the copied set is the contract, extracted at that point per
`docs/backlog/extraction-by-repetition-principle.md`. An email office
(`docs/backlog/email-office.md`) is the likely trigger.

**Open questions.** Whether an office is a Castle-level primitive
distinct from the existing worker seat, or a convention layered on top
of it. Whether an office shares the worker record shape
(`docs/architecture.md`'s Worker section) or needs its own. What
"has no direct line to the resident" actually forbids, precisely, once
there's a second case to check it against. None of these are answered
here — they're what speccing this, when it's time, will have to
decide.
