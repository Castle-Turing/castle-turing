# An errand that asks a question has no way to be resumed

**What.** A worker that needs the resident's judgment mid-errand appends
a `question` record and ends its turn. The router delivers the question,
the resident answers with `castle answer`, and the answer lands in the
journal — where nothing picks it up. No mechanism re-invokes the worker
on the original request. The errand simply stops, permanently, with its
question answered and its work unfinished.

**Why it matters.** Mid-errand questions are load-bearing in this
design, not an edge case: `docs/architecture.md` routes worker questions
through the router precisely so the question economy becomes plumbing
rather than policy. An economy where every question kills the errand
that asked it teaches workers not to ask — which is exactly the failure
mode the design exists to prevent.

Task 0009 shipped with `agent/castle-worker-claude`'s prompt telling the
tenant to answer-and-stop, which was a promise the system could not
keep; the prompt has since been softened to tell the truth (complete
what you can, file the question alongside the result). That is honest,
but it is a workaround for a missing mechanism, not the mechanism.

**The real question this defers.** *Who* resumes an errand. Candidates,
each with a different theory of the system:

- The router, when it sees an `answer` referencing a `question` whose
  errand is unfinished — makes the router an actor rather than purely a
  decider, which is a meaningful widening of that seat.
- A separate watcher seat, keeping the router a pure decider at the cost
  of another moving part.
- The resident, explicitly (`castle resume <request-id>`) — smallest and
  most honest, and it keeps a human in the loop on work that was already
  blocked on a human.
- Nothing: errands are single-shot, and an answered question spawns a
  *new* errand referencing the old one. Arguably the most faithful to
  append-only records, and it makes the journal's lineage explicit.

The last two are cheap; the first two are architecture. Worth deciding
deliberately rather than defaulting into whichever is easiest to code.

**Note.** Resolving this likely also wants the `question`/`answer` pair
to carry enough context that a *fresh* tenant can pick the errand up
cold — which is Proposal 03's "no harness feature may be load-bearing"
applied to errand continuity. A resumption that only works because the
same session is still warm would not count.
