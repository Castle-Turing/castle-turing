# Passing tests are not acceptance, and nothing here asserts reachability

**What.** A brief's verification plan says what the implementer can
test. It does not say what would make the resident agree the thing was
built. Those came apart on task 0070: the tool worked, its tests were
thorough, its CI gate was green, and the implementer's reading of
"task-level outcome logging is running" was honest — while the
resident's reading, that rows get written as work happens and a
redirect is loggable, was unmet. Every check passed and the feature was
not reachable by anyone who would actually use it. Acceptance criteria
should have to assert **reachability**, not only correctness: who
invokes this, from where, in the flow they are already in.

**Why it matters.** The gap is invisible by construction. A correctness
test is written by the person who built the thing, against their own
reading of what it is for, and it therefore cannot catch a wrong
reading — it ratifies one. That is the same structure as
self-asserted completion, which is false in 45–76% of measured cases
(`docs/research/`), and it is why this project's other verification
rules insist on artifact state rather than an agent's account of its own
work. Here the artifact state was real and still said nothing, because
"the code is correct" and "the feature is reachable" are different
claims and only one was being made.

The cost compounds where the unreachable thing is behind a gate. 0070
armed a required CI check against a pipeline nothing fed, so the miss
would have surfaced as every later task pull request failing for a
reason none of them caused.

**What we already know.** Task 0072 built the mechanical half —
`tools/reachability-check.py` flags a tool subcommand nothing calls and
a gate that names no feeder — and its brief is explicit that this is the
silhouette of the problem and not the problem. No lint reads intent. The
two exclusions that lint needed (a test is not a caller, a synopsis is
not a caller) are worth keeping in front of whoever specs this: they are
the shapes "it is reachable" took while being false.

The weekly audit is the only thing in this project that currently reads
for intent, and it reads a sample. `docs/backlog/weekly-audit-vigilance.md`
is the entry about whether that scales.

**Open questions.**

- Does this become a required section in a brief — "how the resident
  reaches this" — or a question the delivery seat asks before opening a
  pull request? A section risks the ritual-compliance failure that a
  free-text field with nothing reading it always produces; the CLAUDE.md
  `Model-because:` rule chose the section anyway, and said why.
- Can a reachability claim be made falsifiable the way a decision's
  falsifier is (Proposal 06)? "The resident reaches this by X" is
  checkable by doing X once, which is a cheap acceptance test and a very
  different artifact from a unit test.
- Who writes it — the resident, at speccing time, when the intent is
  theirs and unambiguous? That is the only point at which the reading
  being tested is the right one.
