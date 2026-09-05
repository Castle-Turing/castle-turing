# Tidying a brief into done/ rots every citation of it

**What.** Briefs cite each other, and code cites briefs, by path:
`docs/tasks/0048-activation.md` appears in `agent/castle`, in
`modules/agent/default.nix`, in the agent-loop tests, in
`docs/architecture.md`. When a brief's work merges and the brief moves
to `docs/tasks/done/`, every one of those paths is left pointing one
directory above where the file now is.

The 2026-09-05 sweep moved nine briefs and left 140 such citations
across 25 files. None of them is a broken markdown link — they are bare
paths in prose and comments, so nothing renders wrong and no check
fails. They are simply, quietly, no longer correct.

**Why it was not fixed in that sweep.** Rewriting 140 lines across
`agent/castle`, the applier, and the whole agent-loop suite turns a
bookkeeping move into a diff that touches most of the codebase, and it
would have collided head-on with three sprint branches then being cut
against the same files. The sweep stayed a sweep. That is a deferral,
not a judgment that the rot is acceptable.

**Why it will keep happening.** This was the second sweep in three
days. Every merged brief eventually moves, and the citation count grows
with the corpus, so the cost of the eventual fix rises the longer it is
deferred while the value of each individual citation falls as it ages.

**Fix directions, none chosen.**

- *Cite by number, not path.* `task 0048` rather than
  `docs/tasks/0048-activation.md`. Immune to the move by construction,
  and loses the ability to click through. The bulk of existing
  citations already read naturally this way in prose.
- *Stop moving files.* Mark completion in the brief's own header
  instead and let the queue loader read it — which is emcee task 0043's
  territory (a file without the task header is not a task) approached
  from the other end. Trades a directory convention for a field.
- *Fix them on each sweep, mechanically.* Cheap per sweep, and it makes
  every sweep a repo-wide diff, which is exactly what this entry
  records as the reason not to.
- *A CI check that a cited brief path exists.* Turns silent rot into a
  failure, and says nothing about which of the above should follow.

Whoever specs this should decide whether a citation is meant to be a
link or a name, because that question decides the rest of it.
