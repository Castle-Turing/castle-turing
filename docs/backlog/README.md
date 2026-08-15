# docs/backlog — deferred work, in plain text

Things worth doing that nobody is doing yet. One file per item,
`docs/backlog/<slug>.md`.

## Why here and not an issue tracker

A backlog in the repo is readable by anything that can read files —
no API, no auth, no network. It travels with a clone, versions
alongside the code that motivates it, and survives the hosting
platform. That is the same reasoning that put the system's
configuration in a flake instead of a machine's undocumented state
(see `docs/vision.md`), applied to intentions instead of packages.

One file per item rather than a single list is deliberate: parallel
agent sessions edit this repo concurrently, and separate files never
conflict where a shared list would.

## Lifecycle

A backlog entry states a **problem**. A task brief in `docs/tasks/`
states a **solution**. When an entry is specced, it becomes
`docs/tasks/NNNN-<slug>.md` and the backlog file is deleted in the same
commit — git history keeps the lineage, and the backlog stays a list of
things not yet decided rather than an archive.

Entries are not numbered. Numbers in `docs/tasks/` are sequential and
mean something (the order work was committed to); backlog order means
nothing, so slugs only.

## Shape of an entry

Keep it short enough that writing one is never a chore:

```markdown
# <Title>

**What.** One or two sentences on the change itself.

**Why it matters.** The cost of not doing it, or what it unblocks.

**What we already know.** Constraints, prior findings, relevant
history — so whoever specs this does not re-derive it.

**Open questions.** The decisions that speccing will have to make.
```

Nothing is committed by being listed here. An entry is a candidate,
not a promise.
