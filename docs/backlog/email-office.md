# An email office — triage, draft, escalate, digest

**On the name:** see the note in
`docs/backlog/office-contract-extracted-by-repetition.md` — "office" is
used here in preference to "department" as the castle-appropriate
term, but the term itself is undecided.

**What.** A second Castle Turing office, alongside Emcee: a detached
run that triages the resident's maildir, drafts responses, files
messages and unsubscribes from senders autonomously where that's
clearly in scope, escalates only the messages that genuinely need the
resident's judgment, and lands a digest of what it did. Same contract
shape as Emcee — briefs in, artifacts and escalations out, decisions
written to the journal, notification through the castle's channels, no
direct line to the resident — minus everything specific to git: there
is no repo, no diff, nothing to propose-never-deploy.

**Why it matters.** Email triage is a plausible, high-value office on
its own terms. It is also the natural second data point for the
question `docs/backlog/office-contract-extracted-by-repetition.md`
raises and deliberately leaves open: whether Emcee's contract
generalizes, and if so to what. A single office proves nothing about
its own shape; a second one, built independently, is what would show
which parts of Emcee's plumbing were the contract and which were
incidental to running an agentic dev harness against a repo.

**What we already know.** This entry is explicitly the test case named
in `docs/backlog/office-contract-extracted-by-repetition.md`. If that
entry has already been promoted and an office contract exists by the
time this one is picked up, this office should be built against that
contract rather than growing its own bespoke dispatch, parking, and
journal-write plumbing from scratch — building it standalone first is
only the right move if the contract question is still unpromoted.

**Promotion condition.** Emcee has run real sprints and its escalation
calibration — what it chooses to hand to the resident versus handle
itself — has stabilized enough that the pattern looks worth
generalizing to a second, non-repo domain.

**Open questions.** Whether mail triage needs its own authority
boundary given that Emcee's "propose, never deploy" hard line
(Proposal 03) is specific to git and has no obvious analogue for
sending, filing, or unsubscribing — see
`docs/backlog/authority-taxonomy-prior-art.md` for what's already known
about getting that kind of boundary wrong. Where the escalation
threshold actually sits, and whether it can be inherited from Emcee's
calibration or has to be learned fresh for mail. None of this is
decided here.
