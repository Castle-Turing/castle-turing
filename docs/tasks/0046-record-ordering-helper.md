# Task 0046 — one shared ordering helper for journal records

Promotes `docs/backlog/record-ids-are-only-second-resolution.md`
(deleted by this commit). Everything that entry records is the reason
for this task; what follows is the part of it this task builds, and the
much larger part it deliberately does not.

## The hazard

`make_id` builds a record id as `<UTC stamp>-<type>-<random suffix>`
with the stamp at **one-second** resolution. Sorting records by the
whole id is therefore chronological only across seconds. Within one
second the type name decides, and then the random suffix does — which
is to say the order is arbitrary, and not even reproducible between
runs of the same journal.

Every surface that folds the journal sorts records somewhere, and
before this task every one of them sorted by the whole id. The backlog
entry counts four separate defects this has already produced (0023,
0024, 0025's approval harness, 0025's status overlay), each fixed where
it was found and none of them fixing the cause.

**The motivating pairing, and the reason this is a hazard in the format
rather than in any author.** `_errand_state` in `agent/castle-modal`
contains a careful, correct workaround for this exact problem —
comparing only the timestamp half of two ids, because comparing them
whole made an `answer` written in the same second as the `result` it
decides look *older* than it, by alphabet — and documents at length why.
Twelve lines above that comparison, the same function selects "the
newest proposal" by sorting proposals on the whole id and taking the
last, which is the hazard the paragraph below it is about. A hazard that
defeats an author who has just finished writing a paragraph about it is
not going to be fixed by a fifth local workaround.

## What this task builds

One shared comparison, in `agent/castle`, that every fold uses and none
re-derives. Five thin entry points over a single rule:

- `record_is_before(earlier, later)` — the rule itself, pairwise.
- `order_records(records)` — a deterministic total order, oldest first.
- `newest_record(records)` / `oldest_record(records)` — the ends of it.
- `tied_for_newest(records)` — the honest answer, below.

### The rule

Given two records, in this order:

1. **A `refs` edge between them wins, over any timestamp.** A record
   can only name one that already exists, so `B refs A` is direct
   evidence that A was written first — stronger evidence than a stamp,
   and the only evidence that survives clock skew, a restored journal,
   or two processes disagreeing about the time. This is 0025's
   decision-versus-result tie-break generalised rather than repeated:
   an answer deciding a proposed change refs `[question, result]`
   (0025 §B), so the edge is *already there*, and "a decision can only
   exist after the change it decides" stops being a special case
   written into one comparison and becomes what the shared rule says
   about every pair of records with an edge between them.
2. **Otherwise the timestamp half of the id**, never the whole id. The
   type name and the random suffix are not evidence about time and are
   never consulted as if they were.
3. **Otherwise the two records genuinely tie**, and `record_is_before`
   says so by returning `False` in both directions.

Only a *direct* edge counts, not a transitive path. Reachability
through the whole journal is a different and much more expensive
question, and no call site swept here asks it; a fold that needs it
should say so rather than have this quietly answer something else.

### Ties, and who gets to pick

`record_is_before` refuses to order a tie. The two callers who cannot
refuse get different tools:

- `order_records` must return a list, so it returns a total order:
  timestamp, then refs edges, then — for records nothing distinguishes
  — the whole id, **arbitrary and documented as arbitrary**. What it
  buys is that the arbitrary choice is identical on every invocation
  and identical across every surface, which is what a picker needs (the
  number a resident presses must mean the same thing for as long as the
  list is on screen) and what a reviewer needs (two surfaces can no
  longer disagree about one errand).
- `tied_for_newest` returns the run at the end of the order that
  nothing distinguishes. A caller that wants to say "two changes
  finished at once" — which the backlog entry names as a legitimate
  rendering, and a better one than confidently reporting one of two
  possibilities — can ask. It is defined as a *tail* of `order_records`
  rather than as "every record with no direct edge to the newest",
  which is what it was first written as and which was wrong: on a
  same-second chain `C refs B refs A` the direct-edge version called A
  tied with C while excluding the B between them, contradicting the
  order the same input produces. Each candidate is tested against the
  whole run, not against `ordered[-1]` alone.

Implementation note: `order_records` is a Kahn topological sort over the
`refs` edges among the records being ordered, with the ready set
prioritised by `(timestamp, whole id)`. That is exactly "timestamp
order, except that a record is held back until everything it names has
been emitted." A cycle is impossible in an append-only journal and would
mean a hand-edited one; it is broken deterministically rather than
raised, because a status surface that crashes on a malformed journal is
worse than one that orders it oddly.

## Explicitly not in scope

The backlog entry's open questions stay open. This task changes **no
record format and no schema**:

- **Not a finer stamp.** It would fix the common case and not the
  general one, and it is a format change.
- **Not a sequence number.** The journal has no writer of record and
  `castle record` is an unguarded back door; a counter derived from the
  directory listing re-introduces the race it exists to remove.
- **No migration, ever.** The journal is append-only, so every record
  ever written stays exactly as it is. The helper has to read today's
  mixed directory correctly and forever, which is precisely why it
  reads only what ids already carry.

This is the entry's own "cheap partial mitigation," built as the entry
describes it and no further.

## The sweep

Every by-id ordering of *records* in `agent/castle` and
`agent/castle-modal` now goes through the helper. Sorts of file paths
(`journal_dir().glob(...)`) and of Wayland sockets by mtime are not
record orderings and are untouched.

In `agent/castle`: the notify-context "last notify decision"
(`cmd_ask`), the router's `to_route` sweep, the worker packet's earlier
results / questions / answers, `closing_result`'s two `max` selections
and its "newer than the claim" test, the dispatch watermark's "earliest
one ever written", the reaper's claim sweep, `_resumable_answers`,
`_eligible_requests`, `_eligible_approvals`, the digest's requests /
corrections / downstream, and `cmd_validate`'s two whole-journal passes.

In `agent/castle-modal`: `_pending_questions`, the inbox's questions and
unread results, and in `_errand_state` the results, claims, proposals,
answers, and apply-attempt selections, plus `run_status`'s request list
and per-errand decisions.

`closing_result`'s clause (b) is the one place where the tie semantics
had to be chosen rather than inherited. `rec.id > claim.id` meant "a
result newer than this claim closes it", and on a tie the old code said
*yes* — by alphabet, since `claim` sorts before `result`, entirely by
luck. It is now written as `not record_is_before(rec, claim)`, which
says yes on a tie deliberately: the shape clause (b) exists for is a
resident finishing a crashed errand by hand, and the cost of getting a
tie wrong in the other direction is the reaper writing a permanent
`interrupted` over a result the resident just filed. That was the exact
regression clause (b) was added to prevent.

Two `_stamp_of`-style helpers are collapsed into one: `castle_modal`'s
private `_stamp_of` is deleted and its reasoning moved into
`agent/castle` beside the rule it belongs to.

**"Folds may not bypass" is enforced, not asked for.** A CI check reads
both scripts with `ast` and fails, with a pointer to the helper, on any
`key=` argument that reaches a record's `id` — a lambda, a composite
tuple key, `operator.attrgetter("id")` — or on any direct `a.id < b.id`
comparison. Without it this task lands a helper that the next fold is
free to not know about, which is the failure mode the backlog entry is
a record of.

It reads the syntax tree rather than grepping lines for a specific
reason: the shape most likely to bring id-ordering back is the one
removed from `_inbox_items` here — a composite key wrapped over several
lines by the repo's own formatting, with `q.id` alone on one of them. A
line-oriented grep does not see it, and a guard that passes on the
exact case it exists to catch is worse than no guard, because two other
files advertise this one as load-bearing.

### What did not get better

Two sibling proposals filed on one errand inside the same second still
have no edge between them and still tie, so `_errand_state` still picks
one arbitrarily to read a verdict off. What changed is that the pick is
deterministic, centrally documented, and — this is the part that
matters — now *representable*: `tied_for_newest` will say there are two.
Rendering that tie to the resident would mean inventing a new
resident-facing label with its own remedy sentence (docs/tasks/0015's
rule), which is a different change from the one this task was asked to
make. The accepted-limit comments in `_errand_state` are rewritten to
say this rather than deleted.

## Verification

`test/agent-loop/record-order.sh`, wired into `check.yml` as its own
job, in the shape the other agent-loop tests use: plain bash and
stdlib Python, no Nix, no journal on disk (the helper is pure, so the
fixtures are `Record` objects built inline).

It pins:

- Two records in one second **with** a `refs` edge — the edge wins,
  both in `order_records` and in `record_is_before`, and the tie is
  gone from `tied_for_newest`.
- Two records in one second **without** an edge — `record_is_before` is
  `False` both ways, `tied_for_newest` returns both, and
  `order_records` is stable across repeated calls and across input
  permutations.
- **The 0025 decision-versus-result case**: a `result` and the `answer`
  that decides it, written in the same second. Sorting whole ids puts
  the answer first, by alphabet; the helper puts the result first, via
  the edge the answer already carries. This is the regression that
  would have caught the original defect.
- **A chain inside one second** (`C refs B refs A`): the edges order it,
  and only its end is newest. This is the regression for the
  direct-edge `tied_for_newest` described above, and it also pins that
  the two helpers cannot contradict each other — the tie is always a
  tail of the order the same input produces.
- A `refs` edge that contradicts the stamps (clock skew / restored
  journal) — the edge still wins.
- Cross-second ordering, the empty and single-record cases, and a
  hand-forged cycle producing a deterministic order rather than an
  exception.
- The bypass guard itself: zero record-id sort keys remain in
  `agent/castle` and `agent/castle-modal`. Verified by reintroducing
  each of the four shapes it claims to catch and watching it fail, not
  only by watching it pass on a clean tree.

Every existing agent-loop assertion must pass unchanged. None was
asserting the buggy order — `test/agent-loop/apply.sh` deliberately
`sleep 1`s between two apply attempts precisely to avoid depending on
it, and that sleep stays (a test that leans on the helper to separate
two records in one second would be testing the helper, not the
applier). No human steps.

## Judgment calls

- **Five entry points, not one.** "A single shared helper" is one
  *comparison*; `newest_record(x)` spelled as `order_records(x)[-1]` at
  every call site is the same rediscovery-per-surface this task exists
  to end. All five are ten lines of delegation to one rule.
- **The refs edge beats the stamp even across seconds**, not only on a
  tie. The entry says "where a `refs` edge exists it should be
  preferred to any timestamp comparison"; taken literally that also
  makes the helper correct on a journal whose clock moved, which a
  tie-only rule would not be.
- **Direct edges only** — see above.
- **`tied_for_newest` ships with no production caller**, only tests.
  The instruction to expose an honest tie is explicit and the entry
  endorses the rendering; wiring it into a surface would change what
  the resident reads, which is out of this task's scope.
- **`closing_result` swept even though the backlog entry does not name
  it.** It compares record ids for recency, which is the hazard, and
  the bypass guard would have flagged it. Its tie behaviour is
  preserved deliberately rather than changed — argued above.
- **`cmd_validate`'s two passes swept for uniformity**, though only
  the order of error messages depends on them.
- **`_pending_questions` gained a `castle` parameter.** It was the one
  fold in `castle-modal` with no handle on the `castle` module, since it
  needed nothing from it; it does now. First-parameter `castle` is what
  every other helper in that file already does, so the alternative —
  reaching for a module-level global that file deliberately does not
  have — would have been the novel thing.
- **`_errand_state` reads the answers naming the proposal, not the
  whole journal in order.** The line swept was `for rec in
  sorted(records.values(), ...)` with a two-clause `continue` at the
  top; keeping that shape put a whole-journal ordering inside a loop
  that runs once per errand on an interactive surface, measured at
  ~10ms per call over 3000 records against 0.76ms for the old sort. The
  filter moved into the fold, which is both cheaper and what every
  other selection in the function already does.
- **`agent/README.md` gained an "Ordering records" section**, and its
  answer-picker paragraph lost a sentence that is now false ("ordering
  is by full record id … chronological only to one-second
  granularity"). Not scope creep: that paragraph described the old
  behaviour, and the repo's rule is that docs are written for a
  stranger. A stranger reading it after this change would have been
  told the wrong thing.
- **Old briefs' citations repointed.** `docs/tasks/0025-approval.md`,
  `docs/tasks/0026-apply-validate.md`, `test/agent-loop/apply.sh` and
  `agent/castle` all cite the backlog entry by path; a promoted entry
  that leaves nine dangling paths behind is worse for a cold reader
  than the edit. 0026's "what I read while writing this" list keeps the
  original filename and notes where it went, because that list is a
  record of what was true then.
