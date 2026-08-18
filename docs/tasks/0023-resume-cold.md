# Task 0023 — An answered blocking question resumes the errand, cold

**Before starting:** read `CLAUDE.md` in full, `docs/architecture.md`
(Records, The journal and the spool, Seats — especially Worker,
Dispatch, and Intake's third-kind-of-speech paragraph — Provenance,
Where runtime state lives, Proposals 03, 04, 05, and 06),
`agent/README.md` in full (the `castle` CLI section, the record-format
tables — especially "The claim record, and the `outcome` field" — and
the Testing section), `docs/tasks/0021-auto-dispatch.md` and
`docs/tasks/0022-answer-in-ui.md` in full (this task reads both tasks'
machinery closely and must not diverge from it), and
`docs/backlog/errand-resume-after-answer.md` (the entry this task
promotes and deletes in the same commit). Then, closely: `agent/castle`
— `RECORD_TYPES`, `FIELD_ORDER`, `write_record`, `file_answer`,
`cmd_record`, `_write_worker_result`, `run_worker_turn`, `cmd_work`,
`closing_result`, `_reap_interrupted`, `_eligible_requests`,
`cmd_dispatch`, `_collect_downstream`, `cmd_validate`'s `outcome`
block — `agent/castle-modal` (`_errand_state`, `run_answer`,
`_pending_questions`), `agent/castle-worker-claude`,
`modules/agent/default.nix` in full, `test/agent-loop/dispatch-test.sh`
(especially the non-behavior test at its "answering a question on an
already-worked errand" section), `test/agent-loop/run.sh`,
`test/agent-loop/contract-worker.sh` and its siblings,
`test/agent-loop/scripted-worker.sh` and `scripted-worker-alt.py`,
`test/agent-loop/tenant-swap.sh`, `test/agent-loop/modal-headless-test.sh`,
and `test/desktop-loop/test.nix` in full. Work on branch
`sprint/0023-resume-cold`, cut from `main`. This brief rides it. PR to
`main`.

**Goal.** An answered *blocking* question automatically resumes the
errand that raised it, exactly once, with a fresh worker tenant that
receives enough journal context to continue cold — no warm session, no
vendor resume token, no hidden transcript. A *non*-blocking question,
which is today's common shape, resumes nothing, exactly as before.

## Why

Today a worker that needs the resident's judgment mid-errand appends a
`question` record and ends its turn. The router delivers the question,
the resident answers with `castle answer` or the modal's answer mode
(`docs/tasks/0022-answer-in-ui.md`), and the answer lands in the
journal — where nothing picks it up. `_eligible_requests`'s own
docstring says so (`agent/castle:2509-2512`): "an unanswered `question`
on the errand… that is the errand-resume problem
`docs/backlog/errand-resume-after-answer.md` names and task 0023 owns —
an `answer` must not make a worked errand eligible again." That last
clause remains true after this task for the common case; what changes
is the *uncommon* one, where a worker explicitly said it could not
proceed without the resident's word.

`docs/backlog/errand-resume-after-answer.md` is the entry this task
promotes and deletes in the same commit (per `CLAUDE.md`'s backlog
lifecycle). It names four candidates for "who resumes" — the router
acting rather than deciding, a separate watcher seat, an explicit
`castle resume <id>`, or a new errand referencing the old one — and
says the decision is "worth deciding deliberately rather than
defaulting into whichever is easiest to code." A fifth candidate exists
now that did not when that entry was written: `docs/tasks/0021-auto-
dispatch.md`'s dispatch seat. §1, below, is why dispatch wins over all
four, and it is the load-bearing decision this whole task rests on.

The backlog entry's closing note is also this task's actual center of
gravity: "Resolving this likely also wants the `question`/`answer` pair
to carry enough context that a *fresh* tenant can pick the errand up
cold — which is Proposal 03's 'no harness feature may be load-bearing'
applied to errand continuity. A resumption that only works because the
same session is still warm would not count." Everything in §7 exists to
make that true.

Three things this task must not accidentally become, stated up front
because each is a real temptation the design below closes off
structurally rather than by convention: automatic resumption must not
turn into automatic *retry* (§3 — the failure mode 0021's whole retry
policy exists to bound); it must not turn into a second, quieter way
for something other than the resident to close a question (§6 —
Proposal 05's whole point); and it must not turn into permission for a
resumed tenant to *apply* what it now has the resident's word on (§6's
closing constraint) — an explicit answer is exactly the context in
which "the resident already said yes, so I can deploy it" becomes
tempting, and the worker-proposes-never-deploys line does not bend for
it.

## The design

### 1. Who resumes: widen dispatch's eligibility predicate

**Dispatch, not the router, not a new watcher seat, not a resident
command, not a new-errand-per-answer scheme.** `_eligible_requests`
(`agent/castle:2499-2543`) is already a pure fold over the journal —
"the authority the wakeup is only a hint for," per its own docstring —
and its docstring already names this task as the owner of the one
omission it does not yet cover. The systemd path unit backing it
watches the *whole* journal directory, not `*-request-*.md`
specifically, and `modules/agent/default.nix`'s comment on that
decision (lines 403-414) says outright that it was written that way
*so that* an `answer` record landing would wake dispatch for exactly
this task:

> `docs/backlog/errand-resume-after-answer.md` needs dispatch to
> notice an `answer` record too, and a watcher keyed to a filename
> shape is structurally unable to fire on anything else.

`docs/tasks/0021-auto-dispatch.md`'s own "Rejected alternatives" list
for the trigger makes the same point from the other direction: a
request-shaped watcher "would satisfy *this* task completely while
quietly foreclosing the next one… the wakeup is a hint; the fold is the
authority, and that split is what makes the predicate extensible
later." This task is that extension, exercised for the first time.

Reject the backlog entry's other three candidates, carrying its own
reasoning forward since the backlog file is deleted in this commit and
this brief becomes the only durable record of why:

- **The router, acting rather than deciding.** The backlog entry frames
  this candidate honestly: "makes the router an actor rather than
  purely a decider, which is a meaningful widening of that seat."
  Dispatch avoids that widening entirely. Dispatch already chooses
  nothing — `docs/tasks/0021-auto-dispatch.md` §2.9 and
  `docs/architecture.md`'s Dispatch paragraph both establish that
  "which request runs next is a total function of the journal,"
  which is exactly why dispatch writes no per-errand decision record.
  Widening its eligibility predicate keeps that property intact:
  resumption after this task is still a total function of the
  journal, reconstructable exactly by re-running the same fold over
  the same snapshot. Widening the *router* instead would hand a seat
  whose entire job is "decide channel and timing" a second job,
  "decide whether to re-run a worker turn" — a strictly larger kind of
  judgment than anything the router does today.
- **A separate watcher seat.** Keeps the router a pure decider at the
  cost of another moving part — another systemd unit, another lock,
  another place the "one turn at a time" guarantee has to be
  independently re-established. Dispatch already *is* that watcher for
  every other reason a worker turn starts; giving resumption its own
  parallel mechanism means two sweep loops racing over the same
  journal, needing to agree with each other about which one owns a
  given request at a given instant — exactly the sweep-lock problem
  `docs/tasks/0021-auto-dispatch.md` §2.1 solved once already, solved
  again for no reason.
- **`castle resume <request-id>`, explicit and human-invoked.** The
  backlog entry calls this "smallest and most honest," and it is
  cheap — but it reintroduces the exact gap 0021 exists to close for
  everything else: a resident has to remember to type a command after
  answering, which is the same "a human types `castle work`" failure
  0021's Why section already diagnosed for the original loop.
  `docs/tasks/0015-filed-not-in-progress.md`'s lesson generalizes here
  too — a mechanism whose whole promise is "answering is enough" that
  actually requires a second typed command is not that mechanism.
- **A new errand spawning, referencing the old one.** The backlog entry
  calls this "arguably the most faithful to append-only records," and
  it has a real appeal: nothing about an existing request record ever
  needs to change. But it does not resume the *original* errand's
  worker turn — it starts a second, formally distinct one, which means
  every downstream consumer that already understands "one request, one
  errand, a fold over its `refs`" (the status surface, the digest, the
  reaper) needs to learn a new kind of chaining it does not otherwise
  need. Continuing the *same* errand, by resuming work against the same
  request id, is the smaller change and matches what a resident
  actually experiences: the same problem, continued.

### 2. The blocking marker: a new optional `blocking` field on `question` records

A new field, `blocking: true`, written on a `question` record only when
true; its absence means false. This is the mechanism a worker uses to
say "this specific question, unlike an ordinary one, genuinely stops
the errand" — and it has to be a field the *question's own writer*
sets, at write time, because nothing else in the journal could
reconstruct that fact afterward.

**Why it must be new vocabulary, not something reused.** Checked: there
is no existing field or convention that already distinguishes "this
question stops the errand" from "this question rides alongside a
result the worker still produced." `make_id` (`agent/castle:303-309`)
gives every record a timestamp with **one-second resolution** plus a
random suffix — not causal ordering — so "was the `result` written
after the `question`" is not a reliable signal: a worker that finishes
its diagnosis and files both a question and a result in the same
second (a common shape, since both come from one process's tail end)
produces two records whose *relative* id ordering is effectively
arbitrary. Building a heuristic on it would pass in development and
tie in CI. And today's worker prompt (`agent/castle-worker-claude`,
read closely in §9) actively produces *both* shapes on purpose — a
question filed **alongside** a result ("complete what you can, file the
question alongside your result rather than stopping"), and, more
rarely, a question **instead of** a result, when nothing further can be
done without the resident's word. Only the writer knows, at write time,
which of those two shapes this is; nothing downstream can infer it.

**How this differs from what 0022 already rejected for `question`
records.** `docs/tasks/0022-answer-in-ui.md` §9 rejected "a
`status:`/`answered:` field on question records" as "a second source of
truth sitting on top of an append-only fold" that would need editing —
an append-only violation — the moment a question's status changed.
`blocking` is not that shape. It is written exactly once, at question
creation, by the same seat that is already the sole authority on the
question's own content, and it is never mutated afterward — no writer
ever goes back and flips it. It does not duplicate anything the answer
fold already derives (whether a question is *answered* stays exactly
the fold `file_answer`/`_pending_questions` already compute: no answer
record names it). `blocking` answers a different question entirely —
not "is this still open" but "does this question's own writer consider
the errand unable to proceed without an answer" — and that is a fact
about the writer's own turn, observable only by the writer, at the
moment it decides whether to keep working or stop. It is the writer's
report about its own turn, the same epistemic shape `outcome` already
has (`docs/tasks/0021-auto-dispatch.md` §3.5: "an observation… never a
judgment of whether the work itself was good").

**The five durable-data questions, for `blocking`:**

1. **Durable?** Yes — whether a worker considered itself stopped is a
   fact about that turn, permanently true of it, not a live status that
   changes.
2. **Reconstructable from anything else?** No. `created` timestamps
   cannot reliably order a question against its own errand's result (a
   one-second collision is not a corner case here, it is the normal
   shape of a worker's final second), and no other field records the
   writer's own judgment about whether it could proceed.
3. **One record, prose body, readable cold?** Yes — one word,
   `true`, alongside a question whose body already explains, in prose,
   what is being asked; a cold reader needs no separate schema
   archaeology to understand what `blocking: true` means for a given
   question.
4. **Observation or judgment?** An observation about the writer's own
   turn — "I could not continue past this point" — never a judgment
   about the resident, the question's importance, or how it should be
   answered.
5. **Needed now?** Yes — condition (b) of the eligibility fold (§4)
   reads it on every sweep from the moment this task ships; it is not
   speculative vocabulary waiting for a future consumer.

**Rejected alternative: resume on *every* answered worker question, and
let the resumed tenant no-op if there is nothing left to do.** This
was the design before the blocking distinction was drawn, and it is
wrong on cost grounds alone. The common shape today — per
`agent/castle-worker-claude`'s own prompt — is a question filed
*alongside* a completed result, precisely because the worker prompt
tells tenants to finish what they can rather than stop. Resuming on
every one of those would spend a full model turn per non-blocking
question, for an errand the resident and the journal both already
consider complete, to produce a second result record over work that
needed none. It also corrupts the "done" signal: an errand's newest
turn is its truth (`docs/tasks/0021-auto-dispatch.md` §4), so a
no-op resumption would either have to write a second `completed` result
saying nothing new (noise, and a second thing for the reaper and the
status surface to account for) or contrive some way to avoid writing
one at all, quietly re-introducing exactly the "unaccounted-for turn"
failure `claim`/`outcome` exist to prevent. `blocking` is the field
that lets the fold discriminate the two shapes without guessing.

### 3. The spend token is the claim record, not the result

This is the subtlest part of the task, and it decides whether
resumption stays bounded the way 0021 bounds ordinary dispatch.

**The rule: an answer is spent iff some `claim` record in the errand
names that answer's id in its `refs`.** Not the result. An earlier
version of this design said the result, and it is wrong, for a
concrete, checked reason: `_write_worker_result`
(`agent/castle:1672-1702`) hardcodes `refs=[request.id, claim_id]`, and
the reaper's own result-writer, `_reap_interrupted`
(`agent/castle:2389-2496`), hardcodes `refs=[request_id, claim.id]`
(line 2459). **Neither writer can know an answer id.** `_write_worker_result`
is called from deep inside `run_worker_turn` with no visibility into
which answers, if any, this particular turn was resuming beyond what it
is explicitly given; the reaper reads only the dead turn's `claim`
record, which was written *before* the turn ran and therefore before
any resumed context existed to name. If the result were the spend
token, a resumed turn that is then itself interrupted, times out, or
hits a misconfigured tenant would write a result that does not — cannot
— name the answer it was resuming. The answer would stay "unspent" by
that definition, the next sweep would see the same unspent blocking
answer and the same eligible request, and dispatch would resume it
*again*. That is an unbounded, silent retry loop at one model call per
timer tick — precisely the failure `docs/tasks/0021-auto-dispatch.md`
§3.4 exists to close for the ordinary case, reopened here for the
resumed one.

**Why the claim works instead.** `run_worker_turn` writes the `claim`
record at `agent/castle:1759-1780` — immediately after the lease is
acquired (`agent/castle:1739`) and strictly *before* the tenant command
is even resolved or validated. Every turn that starts leaves a claim,
full stop: this is true for a healthy completed turn, for
`TenantNotRunnable`'s three failure paths (empty command, unparseable
command, `OSError` on exec — all three write their `outcome: failed`
result only *after* the claim already exists), for a timeout, for a
signal death, and for a turn that is interrupted mid-flight and
reaped later. There is no code path through `run_worker_turn` that
starts a turn without writing its claim first. So the claim is the one
record that is guaranteed to exist, and to have been written by the
turn that actually consumed a given answer, regardless of how that
turn ended.

**What changes, precisely.** The claim's `refs` becomes
`[request.id, <answer-id>, <answer-id>, …]` — the request id first,
exactly as today, followed by the id of every answer this turn is
resuming (§4 defines which those are), in id order. Nothing else about
the claim record changes: no new frontmatter field, no change to how
the claim is written on a first turn (its `refs` is simply
`[request.id]` with nothing appended, byte-identical to today).
**Result `refs` are untouched** — `_write_worker_result` and
`_reap_interrupted` keep writing exactly `[request.id, claim.id]` (or
`[request_id, claim.id]`), unchanged in every particular.

**The payoff, stated because it is the whole reason this shape was
chosen over the more obvious-looking one:**

- `closing_result`'s per-turn accounting (`agent/castle:2184-2258`)
  keeps working with **zero changes**. It reasons entirely about
  results referencing claims and claims referencing requests; it never
  reads a claim's `refs` beyond `refs[0]` (`request_id = claim.refs[0]
  if claim.refs else ""`, line 2236) and never inspects what else a
  claim's `refs` might carry. Appending answer ids after `refs[0]` is
  invisible to it by construction.
- `test/agent-loop/dispatch-test.sh:598`'s existing assertion —
  `grep -q "^refs: $REQ1,$(basename "$(referencing claim "$REQ1")" .md)\$"`
  against `$RESULT1` — checks a **result's** `refs`, anchored with a
  trailing `$`, and is untouched by this task: result `refs` stay
  exactly `[request.id, claim.id]` in every case (§3's "result `refs`
  are untouched"). It is cited here as the sibling fact worth having in
  view alongside the claim change: a careless implementation that
  reached for the more obvious-looking design — appending answer ids to
  the *result's* `refs` instead of the claim's — would have broken this
  exact anchored assertion the first time it ran against an ordinary,
  non-resuming turn.
- The reaper needs **no new knowledge**. `_reap_interrupted` keys claims
  to requests by `refs[0]` (line 2430: `request_id = refs[0]`) — the
  same key it always used — so a claim carrying extra answer ids after
  that first entry reaps exactly as it always did.
- **Retry stays bounded the same structural way 0021 bounds it.** One
  automatic resumption attempt, ever, per unspent blocking answer, and
  no automatic retry of any outcome — because the moment a turn starts
  (successfully or not), its claim is written and spends the answer(s)
  it was given, permanently. A resumed turn that then fails writes an
  ordinary `outcome: failed` result exactly as any other turn does;
  the *answer* is already spent by the claim regardless, so the next
  sweep sees no unspent blocking answer on this request and does not
  resume it again. `castle work <id>` by hand remains the unbounded
  escape hatch, unchanged: a resident who wants to retry a failed
  resumed turn types `castle work <id>` exactly as they would for any
  other failed errand, and it behaves identically because
  `run_worker_turn` writes the claim — and therefore spends whatever
  is unspent at that moment — on both the dispatched and hand-run
  paths, by construction (§7).

**Verified: every existing consumer keys claims by `refs[0]`, so this
change is invisible to all of them.** The reaper
(`request_id = refs[0]`, `agent/castle:2430`); `closing_result`
(`request_id = claim.refs[0] if claim.refs else ""`, line 2236);
`castle-modal`'s `_errand_state` (`rec.refs and rec.refs[0] ==
request_id`, `agent/castle-modal:654-656`, selecting which claims
belong to this errand's turn-state fold). None of the three ever reads
past index 0. Appending answer ids after it changes nothing any of them
observe.

### 4. The eligibility fold

**A new module-level function, `_resumable_answers`, beside
`_eligible_requests` in `agent/castle` — not in `castle-modal`.**

```python
def _resumable_answers(records: dict[str, Record], request_id: str) -> list[Record]:
```

It returns every unspent answer to a blocking question this specific
request's own worker turn(s) raised, sorted by answer id (oldest
first), or an empty list if there is nothing to resume. The definition,
precisely:

1. Every `question` record with `blocking` non-blank (any truthy
   spelling `castle record --blocking` can produce — see §9) whose
   `refs` lineage resolves to this request via `_find_root_request`
   (`agent/castle:1265-1280`) — **not** strict direct `refs ==
   [request_id]` keying, and not `_collect_downstream`. Both of those
   alternatives are wrong, and the reasoning for rejecting each is
   worth carrying explicitly rather than leaving the choice to look
   arbitrary:

   - **Strict direct keying (`refs == [request_id]`) is unsound**
     because it assumes every worker files its question with `--refs`
     pointed straight at the request, and that assumption is false for
     the one tenant that will actually run in production. The scripted
     test tenants do it that way — `test/agent-loop/scripted-worker.sh`
     and `scripted-worker-alt.py` both write
     `--refs "$REQUEST_ID"`/`--refs=request_id`, and the desktop-loop
     VM's fixture does too (`test/desktop-loop/test.nix:109`) — but
     `agent/castle-worker-claude` never invokes `castle record` itself
     at all. It builds a prompt and hands the whole decision to a
     model; its instruction for filing a question
     (`agent/castle-worker-claude:66-76`) reads "append a question
     record instead of guessing — e.g. via a `castle record --type
     question ...` invocation," with the actual `--refs` argument
     elided behind that `...` and left entirely to the model's own
     judgment. `CASTLE_REQUEST_ID` appears in that file only as a
     comment, a guard, and interpolated prose (lines 7, 26, 45) —
     never as a mandated CLI argument a model is instructed to pass. A
     model that quite reasonably files its question against its own
     `result` record, rather than the root request, would under strict
     direct keying produce a blocking question that no fold can ever
     attribute to its errand: the resident answers it, and nothing
     resumes, silently, forever — the exact failure this whole task
     exists to remove, reintroduced through the one tenant that
     matters.
   - **`_collect_downstream` is wrong for the reason §7 already gives
     it** — transitive over `refs` with no type or errand keying, it
     would pull a follow-up request `R2`'s (`castle ask --refs R1`) own
     blocking questions into `R1`'s eligibility check, resuming the
     wrong request or contaminating one errand's turn accounting with
     another's.
   - **`_find_root_request` is the function that already exists to
     answer exactly this question,** used elsewhere in this codebase
     for the identical purpose (`castle-modal`'s `_about_line`, and
     `route_journal`'s evidence text) — walking `refs[0]` repeatedly
     until a `request` record is reached, or returning `None` if the
     chain dangles or is empty. Three properties matter here, verified
     against the actual implementation rather than assumed:
     - **It follows `refs[0]` only** — the same lineage edge 0021
       already tightened claim and result keying to. This is not a
       looser key than direct `refs[0]`-matching; it is the *same* key,
       applied through as many hops as the chain actually has, rather
       than assuming there is exactly one.
     - **It resolves `question → request` and `question → result →
       request` identically.** `_write_worker_result` and
       `_reap_interrupted` both hardcode a result's `refs[0]` to the
       request id, always — so a question refs'd against its own
       result walks exactly one extra hop (`question` → `result`,
       `refs[0]` = the request) and lands on the same request a
       directly-refs'd question would. Traced by hand against the
       actual loop: a question with `refs=[result_id]` sets `current =
       result`, whose `type` is not `"request"`, so the loop continues
       with `nxt_id = result.refs[0]` — the request id by construction
       — and the next iteration returns it.
     - **It cannot contaminate a sibling.** The walk *stops at the
       first request it reaches* — it does not keep walking a request's
       own `refs` looking for some more distant ancestor. A question
       filed against follow-up `R2` (`refs=[R2.id]`) resolves to `R2`
       on the very first hop, before the walk could ever notice that
       `R2` itself carries `refs=[R1.id]`; it never reaches `R1`. And a
       question filed against `R1` or anything in `R1`'s own turn
       history never reaches `R2` either, because nothing in `R1`'s
       records refs `R2` — the lineage edge only ever points backward,
       from a follow-up to its parent, never the other way. Verified by
       tracing the loop by hand for both directions, not merely
       asserted.
   - **A blocking question with empty or dangling `refs` resolves to
     `None`** — `_find_root_request` returns `None` immediately when
     `refs` is empty, and again if the next id in the chain does not
     exist in the journal. Such a question is simply not attributable
     to any request, ever, and would sit as a permanent, silent dead
     end — the resident could answer it and no fold would ever find the
     errand to resume. §9 closes this at write time rather than leaving
     it as a residual trap the new flag itself creates.

   This is a narrower key than `_errand_state`'s "waiting on you"
   overlay deliberately uses for *display*
   (`agent/castle-modal:626-629`: "unlike the turn state below they are
   deliberately NOT keyed to this request id" — because showing a
   resident every pending question anywhere on an errand chain is the
   right thing for a status surface to do). Eligibility is not a status
   surface; it decides which single request gets a worker turn next,
   and it needs the tighter, non-transitive resolution `_find_root_
   request` gives — one specific owning request, never an errand-wide
   set — for the same contamination reason claims and results are
   already keyed tightly.
2. For each such question, every `answer` record anywhere in the
   journal whose `refs` contains that question's id (`file_answer`
   guarantees this is normally exactly one, per-question, but see §5
   for why the fold tolerates more than one).
3. Of those answers, the ones **not already spent** — i.e., no `claim`
   record with `refs[0] == request_id` names that answer's id anywhere
   in its own `refs` (§3).

**The eligibility fold, widened.** `_eligible_requests`
(`agent/castle:2499-2543`) keeps every existing condition —
`rec.type == "request"`; not in the watermark's excluded set; carries
no `filed-during-turn` stamp; no live lease held — and relaxes exactly
condition (b), "no result references it":

```python
eligible = [
    rec
    for rec in records.values()
    if rec.type == "request"
    and (rec.id not in answered or _resumable_answers(records, rec.id))
    and rec.id not in excluded
    and not rec.fields.get(FILED_DURING_TURN_FIELD, "").strip()
    and not lease_is_held(rec.id)
]
```

Every other condition applies completely unchanged, including the
watermark exclusion — a request the watermark named as predating
dispatch (`agent/castle:2523-2528`) stays excluded even if a blocking
question on it is later answered. **Historical journals are inert by
construction, and this is worth stating as its own guarantee rather
than leaving it to be inferred:** absent `blocking` means not
blocking, so `_resumable_answers` returns an empty list for every
question written before this task, and no pre-0023 errand — however
old, however many answered questions it carries — is ever spontaneously
resumed. That is the only safe default: the alternative is a resident's
private journal, accumulated over months, suddenly producing worker
turns on errands the resident had long since considered finished, the
first time this task's code runs against it.

**The skip-set comment `cmd_dispatch` carries must be revisited, not
just the predicate.** `agent/castle:2781-2786` reads:

> Belt and braces against an unterminating sweep: every path through
> `run_worker_turn` writes a result, so the request cannot still be
> eligible — but if that ever stopped being true, this loop would
> spend a model call per iteration forever.

This task is exactly the change that makes "every path through
`run_worker_turn` writes a result, so the request cannot still be
eligible" **no longer reliably true**. `run_worker_turn` recomputes
`_resumable_answers` once, at turn start (§7), and its claim spends
everything unspent *at that instant* — so a request with, say, two
already-answered blocking questions pending at fold time is fully
drained in one turn and is correctly ineligible again afterward. But a
worker can raise more than one blocking question across the life of an
errand, and nothing stops a resident from answering a *second*,
previously-unanswered blocking question on the same errand while the
*first* resumed turn is still running — a turn can legitimately take
up to `CASTLE_WORKER_TIMEOUT` (900s by default). That second answer did
not exist when this turn's claim was written, so it is not spent by
this turn's account. The moment this turn's result lands, the very
same sweep's *next* loop iteration re-reads the journal
(`cmd_dispatch`'s `while True: records = load_all(...)`) and finds this
request newly eligible again — a result now exists, but
`_resumable_answers` is non-empty because of the second, still-unspent
answer. The `skip` set (added to the same loop for exactly this belt-
and-braces reason) is what stops that from being worked a second time
inside the *same* sweep: every request id worked in this sweep is added
to `skip` regardless of outcome, so the newly-eligible-again request is
deferred to the *next* sweep — the next path-unit firing or timer tick
— rather than looped on immediately. The comment must be updated to say
so explicitly: the `skip` set is no longer only a defensive belt for a
bug that should never happen; after this task it is load-bearing for a
real, expected case (a resident answering a second blocking question
while the errand's resumed turn for the first is still in flight). This
is a required edit, not an optional cleanup — an implementer who only
touches the predicate and leaves this comment as-is will ship code
whose own explanatory comment is now wrong about what makes the sweep
terminate.

### 5. Multiple answers to one question

`file_answer` refuses a second answer to an already-answered question
(`AnswerRefused("already_answered", …)`, `agent/castle:822-825`) — but
`castle record --type answer` is an **unguarded back door**:
`cmd_record` (`agent/castle:1057-1108`) refuses only `--type
correction` outright (line 1076); `claim` and every other type,
including `answer`, pass straight through to `write_record` with
whatever `--refs` the caller supplies, no pendingness check at all.

`_resumable_answers` therefore tolerates multiple answers to the same
question rather than assuming `file_answer`'s guarantee holds
universally: it collects **every** answer naming a given blocking
question, and treats each independently for spending purposes (an
earlier answer already spent by a claim does not make a later,
unrelated answer to the same question spent). A resumed turn's claim
spends **all** currently-unspent answers it is given in one write, and
the continuation packet (§7) carries all of them, in id order, under
their shared question.

This is one line of insurance against a crash-shaped surprise —
a hand-planted or scripted `castle record --type answer` landing twice
on one question must not desynchronize the claim/answer accounting or
produce an unbounded resumption loop — and explicitly **not** an
endorsement of the back door itself. `castle record --refs`'s failure
to resolve its refs before writing (unlike `castle ask`/`castle
answer`/`castle correct`, which all validate first) is a separate,
real gap, filed as its own backlog entry in §10.

### 6. Exactly-once is resident-facing, and there is no undo

**The human decided this, and the reasoning is recorded here because a
future reader will otherwise assume it was an oversight.**

After this task, answering a blocking question immediately starts real
work: the path unit fires on the answer file landing, within seconds —
not at the next one-minute timer tick. `docs/tasks/0022-answer-in-ui.md`
already refuses a second answer to the same question
(`AnswerRefused("already_answered", …)`). Put together: a wrongly-
answered blocking question runs to a result within moments, and the
resident's only remedy is a *new* request plus a `correction` record
recording that the system was steered wrong — there is no way to
un-resume, or to supersede the answer before the resumed turn starts.

Three alternatives were offered and declined; recording all three, not
just the chosen one, is the point of this section:

- **(a) Let a second answer supersede the first while still unspent.**
  Rejected. Dispatch wakes within seconds of the first answer landing,
  so the window in which a second answer could arrive before the turn
  starts is illusory in practice — and documenting a window that is
  effectively never open as though it were a real safety margin would
  be exactly the honesty failure `docs/tasks/0015-filed-not-in-
  progress.md` already cost this project twice (a label, here a
  *feature*, whose real behavior does not match what it implies).
- **(b) Full answer-amendment semantics, built inside this task.**
  Deferred, not rejected outright. It widens this task well past
  resumption itself, and "which answer governs, and what happens to
  work already done under a superseded one" is its own design question
  with its own tradeoffs — improvising an answer to it as a side effect
  of shipping resumption is exactly how a second source of truth gets
  built by accident, the same shape `docs/tasks/0022-answer-in-ui.md`
  §9 already declined for a `status`/`answered` field. Filed as its own
  backlog entry (§10).
- **(c) A confirmation step in the modal before filing a blocking
  answer.** Considered and declined. Recorded explicitly so a later
  reader knows it was weighed, not overlooked: it would add friction to
  every answer (the modal cannot know at answer time which questions
  are "important" beyond the `blocking` flag itself, so a confirmation
  gate would either fire on every blocking answer, training the
  resident to click through it, or need a second tier of judgment this
  task has no basis for adding), and it does not actually close the
  underlying gap — a resident who confirms wrongly is in exactly the
  same unrecoverable position as one who never had to confirm at all.

**Consequence for documentation:** `agent/README.md` and the modal's
answer surface must not imply, anywhere, that an answer is revisable.
§10 lists the exact lines this constrains.

**Consequence for authority.** A resumed turn is still propose-only —
this is restated as its own hard constraint below because it is the
one place this task could most easily erode it by accident. The
resumed tenant arrives holding an explicit resident answer, closing a
question the resident was asked. That is exactly the context in which
"the resident already said yes, so I can apply it now" becomes
tempting, for a tenant or for a future implementer reading this brief
loosely. **The answer closes a question; it does not grant authority.**
Nothing in `run_worker_turn`'s contract changes for a resumed turn: no
`nixos-rebuild`, no `git commit`, no applying anything to a running
system, from this seat, on this or any other turn. The containment is
the same code fact `docs/tasks/0021-auto-dispatch.md` already
establishes it as — `cmd_work`/`run_worker_turn` has no code path that
touches a running system, resumed or not — and this task adds no such
path.

**Also forbidden, named explicitly because it is the shortcut this
task's own existence makes newly tempting:** nothing may let anything
other than the resident close a question — no default, no timeout, no
second model judging an answer's sufficiency. In particular, no
mechanism may resume an **unanswered** blocking question "so the errand
doesn't hang." An unanswered blocking question is not an interrupted
turn; it is a turn correctly waiting on the one party allowed to close
it. `_eligible_requests`' relaxed condition (b) only ever fires on an
**answered**, unspent blocking question — `_resumable_answers` returns
nothing for a question with no answer at all, by construction, and no
part of this design adds a staleness clock, a timeout, or any other
path that would make an unanswered question eligible on its own.

### 7. The continuation packet

Rendered by a new function in `agent/castle`, called from
`run_worker_turn` — **not** from `cmd_work`. `cmd_work`
(`agent/castle:2113-2183`) only validates the request and delegates;
today's stdin is written from inside `run_worker_turn` itself
(`pending_input: str | None = request.body`, `agent/castle:1969`), and
`cmd_dispatch` calls `run_worker_turn` directly
(`agent/castle:2729`), never through `cmd_work`. Putting the packet
builder in `cmd_work` would give a hand-run turn and a dispatched turn
different stdin on a resumed errand, breaking the "same code path by
construction" property `run_worker_turn`'s own docstring claims
(`agent/castle:1709-1714`: "Shared in-process by `castle work <id>` and
`castle dispatch`… so a hand-held worker seat and an automatically-
dispatched one are the same code path by construction"). The packet
therefore has to live where the stdin is actually assembled.

**`run_worker_turn` recomputes what it is resuming, itself, at turn
start.** Immediately after the lease is acquired
(`agent/castle:1739`) and before the claim is written
(`agent/castle:1759`) — the same ordering slot the lease/claim
sequencing already occupies, for the same reason: a fact this turn
depends on has to be pinned as close as possible to the moment the turn
actually begins holding exclusive access to the errand. It calls
`_resumable_answers(records, request.id)` against a fresh read of the
journal and keeps the result for the rest of the turn. This is
deliberately **not** a parameter `cmd_work`/`cmd_dispatch` compute and
pass in separately: `_eligible_requests` (used by dispatch to decide
*whether* to start a turn) and `_resumable_answers` (used by
`run_worker_turn` to decide *what* a turn resumes) share the identical
fold, called from the one place that is about to act on its answer, so
a hand-run `castle work <id>` — which never consults
`_eligible_requests` at all — still resumes exactly the answers that
are actually unspent at the moment it starts, with no separate code
path to keep in sync. The narrow race this leaves (an answer becomes
spent by some other process between dispatch's eligibility check and
this recomputation) is the same accepted shape as every other narrow
probe-then-act race already documented in this codebase
(`agent/castle`'s `lock_is_held` docstring, `docs/tasks/0021-auto-
dispatch.md` §2.3's "note on what 'probing' actually means") — a single
resident's machine, a window measured in the time it takes to acquire a
lease, no lock built around it for the same reason none was built
around those.

**Contents, in this order, each rendered verbatim — nothing paraphrased
or summarised:**

1. The root request's body, under a heading identifying it as the
   original request.
2. Every prior `result` record's body in this errand, in id order —
   reasoning and any embedded diff, unabridged.
3. Every `question` record in this errand, in id order, each flagged
   blocking or not and answered or not.
4. Every `answer` to a question, verbatim, immediately under the
   question it answers.

**Rendered on every turn — one code path, no branch for "is this a
first turn."** On a first turn, this degenerates to a single section
holding exactly today's request body — no prior results, no questions,
nothing to resume — which is what keeps this a single function rather
than two (`_resumable_answers` returning empty is a completely ordinary
case for it, not a special one). Codex's stated requirement — every
replaceable worker tenant receives the same record-level context, not
a tenant-specific shortcut — is what this uniformity is for.

**Cost, stated plainly rather than absorbed silently:** first-turn
stdin now carries a heading around the request body where it previously
carried the bare body text, so `agent/castle-worker-claude`'s prompt
changes with it (§9 gives the exact text). This is safe for the other
two tenants this repo ships: both `test/agent-loop/scripted-worker.sh`
and `scripted-worker-alt.py` are invoked positionally, bypass `cmd_work`
entirely, and never read stdin at all — they are unaffected regardless
of what `run_worker_turn` writes to it, because `run_worker_turn` is
not their entry point. `castle-worker-claude` reads with
`request_body="$(cat)"` (line 30) and folds the whole thing into its
own prompt template unmodified, so a heading arriving as part of that
text changes nothing structurally about how it is consumed.

**Which records belong to "this errand," precisely — and why not
`_collect_downstream`.** Do **not** build the packet from
`_collect_downstream` (`agent/castle:2806-2820`). It is transitive over
`refs` with no keying by record type or by errand boundary, and using
it here would pull in exactly the things that must not leak: the
watermark decision record (which names this request only if it
predates dispatch, and even then carries nothing a worker tenant should
ever read), any `correction` a resident filed against this request
(the resident judging the *system*, not instructing the errand — see
below), and — the sharpest case — a follow-up request's **entire**
subtree, if the follow-up was filed with `castle ask --refs
<this-request>`. Write a selective fold instead, keyed the same way §4
already keys eligibility: results via `request_id in rec.refs` (a
result names the request directly, per `_write_worker_result`), claims
via `refs[0] == request_id` (direct — a claim is always written by
`run_worker_turn` itself, a trusted writer, never a tenant, so there is
no `_find_root_request` ambiguity to resolve for it), and questions via
`_find_root_request` resolving to this request — the identical
resolution §4 uses for eligibility, not the looser direct-`refs[0]`
key. This has to match §4 exactly, not merely resemble it: if the
packet builder used strict direct keying while eligibility used
`_find_root_request`, a request could become eligible from a question
the packet then failed to render — a resumed tenant handed
`CASTLE_RESUME_ANSWER_IDS` naming an answer whose own question is
missing from its own stdin, which is precisely the two-surfaces-
disagree failure `docs/tasks/0015-filed-not-in-progress.md` scope 3
already names as worse than either surface being wrong alone.
`_errand_state` (`agent/castle-modal:572-727`) already solved a closely
related problem for a different purpose — deciding an errand's display
state rather than its worker context — and its keying is the template
this whole task follows, not a coincidence to rediscover independently.

**Excluded, each with its reason, stated because a silent omission here
would look like an oversight rather than a decision:**

- **Everything outside the errand.** Refs-connectivity to this specific
  request *is* the errand boundary — the selective fold above cannot
  reach anything that is not linked to this request the way its own
  errand's records are, so cross-errand leakage is impossible by
  construction rather than by filtering something out after the fact.
  This is the strongest available answer to "how do you know a resumed
  tenant never sees another errand's context": there is no code path
  that could hand it one.
- **`correction` records.** A correction is the resident judging the
  *system's* behavior, not instructing the errand
  (`docs/architecture.md`'s Router paragraph: routing one "would mean
  the system answering back to a judgment about itself," Proposal 06).
  Feeding a correction to a worker tenant would make a verdict about
  the system an input to the very work being judged. `cmd_digest`
  already filters corrections out of its errand fold for a closely
  related reason (`agent/castle:2856-2865`); this packet does the same.
- **`decision` records.** These carry the router's channel-and-timing
  reasoning — when and how the resident was interrupted. Handing that
  to a worker tenant invites it to reason about the resident's own
  attention and availability, which is not information an errand's
  work needs and is exactly the kind of resident-facing judgment this
  layer keeps away from worker tenants by design.

**No truncation, and no size limit, anywhere in this packet.** A limit
would be an invented constant with no measurement behind it — the same
"needed now" durable-data failure mode this codebase's own conventions
already flag elsewhere — and silently withholding the very context this
task exists to deliver would be a worse failure than an occasionally
long prompt. An errand with many turns and many questions produces a
correspondingly long packet; that is the honest cost of "no harness
feature may be load-bearing" (Proposal 03) applied to continuity.

**Resident-model entries are deliberately NOT in the packet.** This is
a real gap — a resumed tenant, like every first-turn tenant today,
never sees the resident model at all — but it is a different feature
(workers reading the resident model, at any point, not just on
resumption), it applies identically to first turns as to resumed ones,
and folding it into this task's diff would make this change about
something it is not scoped to be. Name it plainly as deferred and file
a backlog entry (§10) rather than letting it stay an implicit,
undocumented omission.

### 8. `CASTLE_RESUME_ANSWER_IDS`

A new environment variable, set on the tenant's environment only when
this turn is resuming at least one answer — **absent, not empty,** on
every first turn, exactly the same "absent means nothing to signal"
convention `FILED_DURING_TURN_FIELD` already uses on the record side.
Built alongside the rest of the tenant environment inside
`run_worker_turn` (`agent/castle:1838-1858`), the same block that
already sets `CASTLE_REQUEST_ID`, `CASTLE_DIFF_FILE`, and
`CASTLE_WORKER_CLAIM`. Its value is every resuming answer's id, in id
order, in the same comma-separated flat-list convention `refs` already
uses (`split_refs`-compatible) — a single id when there is exactly one,
which is the overwhelmingly common case, and more than one only in the
rare shapes §5 and §4's multi-question note describe.

**Naming a consumer is not optional.** `docs/tasks/0021-auto-dispatch.md`
§3.3 *deleted* `CASTLE_REQUEST_BODY` outright, with the reasoning
stated plainly: "a channel nothing reads is not worth a size limit
nobody documented." Shipping `CASTLE_RESUME_ANSWER_IDS` with no consumer
would be the identical anti-pattern one task later. Its consumer is
`agent/castle-worker-claude`, updated in this task (§10): the prompt
checks whether it is set and, if so, tells the tenant plainly that this
is a resumed turn and that the continuation packet on stdin (§7) —
not this variable — is where the actual prior context lives. The
variable itself carries no prose; it exists so a tenant (or a future
one) can detect "this is a resumed turn" mechanically, without parsing
the packet's own heading text, the same way `CASTLE_WORKER_CLAIM`
exists so a tenant's own follow-up writes can be attributed to the
right turn without parsing anything.

**The name is plural because the value can genuinely hold more than
one id, and a singular name here would be exactly the kind of quiet
misdescription this project keeps paying to fix** — the same "no
surface may infer failure by grepping a body" discipline
`docs/tasks/0021-auto-dispatch.md` insists on for `outcome`, and the
same honesty standard `docs/tasks/0015-filed-not-in-progress.md` exists
to hold labels to generally. §5 requires the multi-answer case to work
(the back door through `castle record --type answer`), and §4's
multi-question note describes a second, legitimate way more than one
id can be present. Documented as comma-separated, `split_refs`-
compatible, with the note that it is normally a single id — `file_answer`
refuses a second answer to the same question, so the common case stays
one id — but a consumer must not assume exactly one.

### 9. Small mechanics

**`--blocking` flag on `castle record`,** modelled exactly on
`--fact` (`agent/castle:3113-3117`) — a bare boolean flag
(`action="store_true"`), documented as "question records only, by
convention" and *not* refused on any other `--type`, the same way `--outcome`
already documents itself as result-records-only-by-convention without
a hard refusal (`agent/castle:3118-3129`). No hard refusal on a
non-question type is needed here either: `_resumable_answers` reads
`blocking` only on records whose `type` is `question`, so the field on
any other type is inert — nothing acts on it and nothing is corrupted —
consistent with how `--fact` already behaves on a non-question record
today. (The field itself is emphatically *not* cosmetic; §2 is entirely
about the work it does on a question record. What is presentation-only
is its `FIELD_ORDER` placement, described in the next paragraph.)

**`castle record --blocking` refuses to write when `--refs` is
empty.** This is a hard refusal, unlike the softer non-question-type
case above, because the failure it prevents is not cosmetic: §4
establishes that a blocking question `_find_root_request` cannot
attribute to any request — empty `refs`, or `refs` that dangle — is
simply unresumable, forever, and looks exactly like a working one from
the outside. The resident answers it, the journal records the answer,
and no fold anywhere can ever find the errand it was meant to unblock —
a permanent, silent dead end, produced at the exact moment a tenant
reaches for the one flag this task adds specifically to make resumption
happen. Refusing at write time is this codebase's established posture
for exactly this shape of hazard: `cmd_record` already refuses `--type
correction` outright for a different but structurally similar reason
(`agent/castle:1075`), and the three resident-facing writers —
`cmd_ask`, `file_answer`, `cmd_correct` — all resolve every `--refs` id
against the journal *before* writing anything, precisely because the
journal is append-only and a bad reference, once written, is
permanent. The check here is deliberately narrower than what those
three do: refuse only when `--refs` is **empty**, not when it is
non-empty but dangling or does not actually resolve to a request via
`_find_root_request`. **This is not the same gap as `castle record
--refs` not resolving its refs before writing** — the backlog entry
filed in §10 for that gap is about the generic writer's total absence
of ref-validation across every type and every caller, tenant or
resident; this check is the one, narrow case the **new flag itself**
introduces, and it should not ship carrying a fresh trap of its own
just because the general gap is being deferred. A `--blocking` question
with a non-empty but dangling ref is still possible after this check —
that residual is exactly what the deferred backlog entry is for.

**`FIELD_ORDER` gains `blocking`,** placed immediately after
`filed-during-turn` (`agent/castle:174`, itself request-only and
already positioned "next to `outcome`… because it is the machine-
readable half of what the record says about its own circumstances").
`blocking` is question-only in the same spirit. This placement is
**presentation-only** — `render_record` (`agent/castle:288-300`) skips
any `FIELD_ORDER` key not present on a given record, and parsing never
consults field order at all — so this is cosmetic consistency with how
`docs/tasks/0021-auto-dispatch.md` positioned `outcome`, not a
correctness requirement. Say so in the code comment, the same way the
existing `FIELD_ORDER` comment already explains why `channel` sits
where it does.

**Validator: checked when present, never required.** Copy the
`outcome` block in `cmd_validate` (`agent/castle:2972-2985`) exactly,
including its comment on *why*: the journal is append-only, so a
validator that suddenly required a field no prior writer could have
supplied would fail every pre-existing question record retroactively.
`blocking`'s own check is narrower than `outcome`'s closed-vocabulary
membership test — there is no vocabulary to check membership against,
only "is this question record, and if `blocking` is present, is its
value one of the truthy/falsy spellings `--blocking`'s own writer
produces" (in practice: present at all, from `write_record`'s literal
`"true"`, versus absent). Do not invent a broader boolean-parsing rule
here than the one writer this task adds actually needs.

**No turn cap.** Every additional resumption requires a fresh resident
answer to a fresh blocking question — the resident is the rate limiter
on this loop by construction, the same way `docs/tasks/0021-auto-
dispatch.md`'s Non-goals section already declines to add a concurrency
knob "before any evidence that serial dispatch is actually a
bottleneck." A cap here would be an invented constant solving a problem
that does not exist: nothing about this design can loop without a human
choosing, each time, to answer another question.

**`_errand_state` needs no fix.** Its errand-level "waiting on you"
bug — pairing each question against the set of ids some answer names,
rather than asking only "does this fold contain an answer of any kind"
— was already fixed by `docs/tasks/0021-auto-dispatch.md`
(`agent/castle-modal:630-633`: "unlike the turn state below they are
deliberately NOT keyed to this request id"). Say this plainly in the
brief so nobody re-fixes an already-fixed bug while implementing this
task; `_errand_state` needs no code change here at all — a resumed
turn's newest claim/result already flows through its existing,
correct turn-state logic with no modification.

### 10. Documentation changes

- **`agent/README.md`.** The record-format table gains `blocking` next
  to `outcome`/`filed-during-turn` in "The claim record, and the
  `outcome` field" section (`agent/README.md:490-587`) — or a short new
  subsection immediately after it, matching that section's own voice.
  The `record`/`work`/`answer` CLI bullets (`agent/README.md:53-151`)
  each gain one sentence: `record` documents `--blocking`;
  `work`/`dispatch` document that a resumed turn is now a real outcome
  of a worker turn, not only a first one; `answer` states, explicitly,
  that answering a **blocking** question resumes the errand
  automatically, and that an answer — once filed, blocking or not —
  cannot be revised or superseded (§6). A new subsection, after "The
  claim record, and the `outcome` field," documents the continuation
  packet's contents and ordering (§7) and the widened eligibility fold
  (§4), in the same register that section already uses for `claim`
  and `outcome`. The Testing section (`agent/README.md:812-823`) gains
  a fifth harness line for `test/agent-loop/resume.sh` and its own
  bullet, matching the existing four's depth (§11 gives the content).
  **Lines 163-168 and 320-324 currently assert the non-behavior this
  task removes** — the `dispatch` CLI bullet's "neither is [eligibility
  condition] an unanswered question (errand resumption is
  `docs/backlog/errand-resume-after-answer.md`'s problem)" language, and
  a second mention in the same neighborhood — and must be rewritten to
  state the *narrowed* non-behavior precisely: an unanswered question,
  or an answered **non**-blocking one, still does not affect
  eligibility; an answered **blocking** one now does.
- **`docs/architecture.md`.** Exactly **one paragraph**, in the Worker
  seat's description (`docs/architecture.md:165-184`). Its contract
  sentence — "a `request` record in; a `result` record, a diff against
  the relevant repo, and journal entries out" — described one errand
  producing exactly one such account; after this task it describes one
  **turn**, and an errand whose worker raised a blocking question may
  have more than one turn, each producing its own account, chained by
  the answer that resumed the next one. State this as a one-paragraph
  addition to the existing prose, in the same voice as the sentence
  already there about automatic invocation from
  `docs/tasks/0021-auto-dispatch.md`. **Do not touch any Proposal's
  statement, teeth, or hardening test** — altering a Proposal's
  substance is a commitment-level act this brief does not have standing
  to make; that is reserved for the human, per `CLAUDE.md`.
- **`modules/agent/default.nix:101-141`.** `worker.command`'s
  description documents the tenant contract verbatim (lines 114-121:
  "the request body is piped to the command's stdin…"). That sentence
  must move with the change it now describes: the *first* thing piped
  to stdin is still the request body, but as of this task it may be
  preceded by prior-turn context on a resumed turn, and the description
  should say so in one added sentence rather than leaving the contract
  text silently stale relative to what `run_worker_turn` actually does.
- **`agent/castle-worker-claude:65-75`** (item 4 of the numbered
  contract list). Today's text: *"Nothing re-invokes you when that
  question is answered: the answer lands in the journal for a later
  errand (or a human) to pick up."* This is now **false** and must be
  rewritten, preserving everything around it that is still true.
  Replacement text, in the same voice:

  > If you need the resident's own judgment mid-errand (a genuine
  > posture question, not something inferrable from the repo), append a
  > question record instead of guessing:
  >
  > `castle record --type question --provenance requested --seat worker --refs "${CASTLE_REQUEST_ID}" --body "..."`
  >
  > if the castle CLI is on `$PATH` in this environment — always with
  > `--refs "${CASTLE_REQUEST_ID}"` naming this errand's own request, so
  > whatever picks the question up later can find its way back to this
  > errand. Mark it `--blocking` only if the errand genuinely cannot
  > proceed without an answer: an answered blocking question **does**
  > re-invoke this seat, automatically, with a fresh tenant and no
  > memory of this turn — everything your successor needs will be in
  > the records you write, not in anything you remember. A non-blocking
  > question does not resume anything, so if the rest of the errand can
  > be completed without the answer, complete it and file the question
  > alongside your result rather than stopping — an errand that halts
  > on a question the resident may not read for hours has spent their
  > time to buy nothing.

  This is a **change in kind**, not only in wording, from the current
  prompt: today's text leaves the `--refs` argument elided behind a
  bare `...`, entirely the model's own call (see the false-claim
  correction in §4 point 1 for exactly why that mattered). The
  rewritten prompt states the argument explicitly, in full, as part of
  the command the tenant is told to run.

  **Belt and braces, and the brief should say plainly which is
  which.** §4's `_find_root_request`-based keying is what makes the
  *mechanism* robust to a tenant that files its question some other
  way — against its own result, or (per §5) through the unguarded
  `castle record` back door in some other shape entirely — so
  resumption does not silently fail to attribute a question just
  because a particular tenant's judgment differed from this prompt's
  advice on a given turn. The prompt mandate above is what makes the
  *canonical* shape (`--refs` naming the request directly) the *usual*
  one in practice, which matters independently: every scripted test
  fixture and every existing worker already produces that exact shape,
  and keeping the real tenant aligned with it keeps a resumed errand's
  continuation packet (§7) reading the same way a cold auditor examining
  the journal by hand would expect, rather than requiring a reader to
  trace a `_find_root_request` walk to understand why a given question
  belongs to a given errand. A future reader of this brief should not
  conclude that the prompt mandate is redundant because the mechanism
  already tolerates its absence — the mechanism's tolerance is a safety
  net for a tenant that does something unexpected, not a reason to stop
  telling tenants the expected shape.

  Note in the surrounding comment, for the implementer, that a real
  `claude -p` tenant is never told about `--blocking` beyond what this
  prompt text says — there is no separate flag or setting steering the
  model toward or away from using it, so in production it will be set
  only when the model itself decides, from this prompt alone, that a
  question is genuinely blocking. Flag this plainly rather than silently
  relying on it: the prompt is the only lever this task has over how
  often `blocking` actually gets set. The same is true of `--refs`: the
  prompt mandate above is advice a model can still fail to follow
  exactly (a wrong id typo'd into the command, for instance) — which is
  precisely why §4's mechanism-level robustness exists as a second,
  independent line of defense rather than being the only one.
- **`agent/castle-modal:506-507`.** The comment above the confirmation
  line — *"When `docs/backlog/errand-resume-after-answer.md` is finally
  built, the second sentence below is the line that gets deleted."* —
  and the line itself, *"Filed. Nothing picks this errand back up
  automatically yet."*, are both addressed by this task exactly as that
  comment anticipated. Delete the second sentence; the confirmation
  becomes just `"Filed."` on the non-resuming path. This string is
  asserted verbatim at `test/agent-loop/modal-headless-test.sh:858` (per
  that test's own line) and must be updated there in the same commit.
  Do **not** add a new sentence claiming resumption happened — per §6,
  the modal cannot know at answer-filing time whether the question it
  just closed was blocking (that is a fact about the *question*
  record, readable, but adding a differentiated confirmation string
  for the blocking case is new scope this brief does not ask for and
  risks implying more certainty about *when* resumption happens than
  is honest from inside the modal process, which never itself triggers
  dispatch). A bare `"Filed."` is true on every path.
- **`docs/private-layer.md`.** **No change.** No new slot, no new
  option, no new configuration surface — resumption rides
  `castle.agent.dispatch.enable`'s existing gate entirely (see Hard
  constraints, below). State this plainly in the PR rather than leaving
  a reviewer to check it themselves.
- **Delete `docs/backlog/errand-resume-after-answer.md`** in the same
  commit as this brief, per `CLAUDE.md`'s backlog lifecycle rule.
- **File three new backlog entries**, in the same commit, in
  `docs/backlog/README.md`'s documented shape:
  1. **Answer-amendment semantics** — which answer governs when a
     question receives more than one, and what happens to work already
     done under a superseded one. `docs/tasks/0022-answer-in-ui.md`'s
     own log already named this as owed (§9's "left to a future task
     deliberately"); this task's §6(b) is the second time it was
     deferred rather than the first, and the entry should say so.
  2. **`castle record --refs` does not resolve refs before writing.**
     `castle ask`, `castle answer`, and `castle correct` each resolve
     every `--refs` id before writing anything
     (`agent/castle:1116-1130`, `agent/castle:770-776`,
     `agent/castle:1209-1221`); `castle record` — the generic writer —
     does not, and it is the one writer a **tenant**, not only a
     resident, actually uses, which makes it the least trustworthy
     caller to leave unchecked. §5 of this task documents living with
     this gap for `answer` specifically; the entry generalizes it to
     the whole subcommand.
  3. **Workers do not read the resident model, on any turn.**
     `docs/architecture.md` calls the resident model "an artifact the
     router and workers read," and no code passes it to a worker. §7
     defers it deliberately: it is a different feature, it applies
     equally to first turns, and folding it in would have made this
     diff about something other than resumption. The entry should say
     that a resumed tenant is the case that makes it most visible — it
     arrives holding the resident's verbatim answer to one question
     while knowing nothing else the resident has ever stated.

### 11. Verification plan

Model-free and zero-network throughout, matching every existing harness
in this directory (`test/agent-loop/run.sh`'s own header). Agent-testable
without any human involved:

**New harness, `test/agent-loop/resume.sh`,** wired into the same CI
job `dispatch-test.sh` already runs in
(`.github/workflows/check.yml`), following `dispatch-test.sh`'s exact
shape — a throwaway `CASTLE_STATE_DIR`/`XDG_RUNTIME_DIR`, the same
`notify-stub.sh`/`CASTLE_NOTIFY_LOG` pattern, the same
`records_of_type`/`referencing`/`count_referencing` helpers reused
rather than reinvented. Do **not** rewrite `run.sh`'s existing errands
to go through `castle work` — that would change what
`test/agent-loop/tenant-swap.sh` fingerprints and risks losing 0021's
own fresh coverage for no benefit; `resume.sh` is additive.

The resume tests **must** go through `castle work` / `castle dispatch`,
never `castle record` alone constructing the whole scenario by hand,
because the continuation packet, `CASTLE_RESUME_ANSWER_IDS`, and the
claim's widened `refs` all live inside `run_worker_turn`, which only
those two entry points reach.

**A third scripted tenant, `test/agent-loop/scripted-worker-blocking.sh`,**
conforming to the real `castle.agent.worker.command` contract (like
`contract-worker.sh` and its siblings — reads `$CASTLE_REQUEST_ID`,
`$CASTLE_DIFF_FILE`, `$CASTLE_REPO_ROOT` from its environment, the
request body on stdin). On its **first** invocation for a given
request, it files a `--blocking` question and writes **no** result
(the "question instead of a result" shape §2 names). On a **resumed**
invocation — detected via `CASTLE_RESUME_ANSWER_IDS` being set — it
reads the full continuation packet from stdin and echoes proof, on
stdout, that it actually saw: the original request's own text, the
blocking question's own text, and the answer's own text, each as a
distinct grepped line so the harness can assert on each independently.
That stdin-reading half is the test that actually proves cold
resumption, as opposed to merely asserting that a second turn ran — a
fixture that only checked "a second `claim`/`result` exists" could pass
even if the packet were empty or malformed. Leave the two existing
tenants, `scripted-worker.sh` and `scripted-worker-alt.py`, byte-for-
byte untouched, per the same reasoning `docs/tasks/0021-auto-dispatch.md`
§7 already gives for `contract-worker.sh`'s existence: `tenant-swap.sh`
diffs their normalized journals, and that comparison only means
something if neither harness's existing behavior moved out from under
it.

**Coverage, enumerated:**

- **Question → answer → resumed result, end to end.** File a request,
  run `castle dispatch` (the blocking tenant raises its question, no
  result yet), answer the question via `castle answer`, run `castle
  dispatch` again — assert exactly one new claim and one new result
  appear, the new claim's `refs` names the answer's id after the
  request id, and the new result's body (via the echoed proof) shows
  the packet actually carried the original request, the question, and
  the answer.
- **Fold idempotence across cold re-invocation after every step.** The
  honest version of "process restart between every step," since
  `castle` is one-shot by construction: re-run `castle dispatch` after
  the question is filed but before it is answered (asserts no
  resumption — the fold correctly finds nothing to resume from an
  unanswered blocking question); re-run it again after the answer is
  filed but interleave with a second, independent `castle dispatch`
  invocation back to back (asserts running the dispatcher twice
  produces exactly one new result, not two — the second sweep's fold
  finds the answer already spent by the first sweep's claim).
- **Duplicate triggers.** Two `castle dispatch` invocations racing
  against the same unspent blocking answer (widen the race the way
  `dispatch-test.sh`'s own concurrency assertion does, via
  `CASTLE_TEST_WORKER_SLEEP`) produce exactly one new claim and one new
  result — the same per-request lease `docs/tasks/0021-auto-dispatch.md`
  §3.1 already provides is what closes this race; the test proves it
  holds for a resumed turn exactly as it does for a first one.
- **A non-blocking question alongside a completed result must NOT
  resume.** File a request, let it complete with an ordinary (non-
  `--blocking`) question raised alongside its result (this is
  `dispatch-test.sh:602-614`'s existing fixture shape — a plain
  `castle record --type question` with no `--blocking`), answer that
  question, run `castle dispatch` again: assert no new claim, no new
  result. This is the direct, positive proof that the opt-in field
  actually gates resumption rather than resumption firing on any
  answered question.
- **A failed resumed turn must NOT auto-retry.** Resume a turn with a
  tenant that then fails (reuse `contract-worker-fail.sh`'s shape for
  the resumed invocation, or extend the blocking fixture with a
  `CASTLE_TEST_WORKER_FAIL_ON_RESUME` knob in the same style
  `CASTLE_TEST_WORKER_SLEEP`/`CASTLE_TEST_WORKER_BINARY` already use on
  `contract-worker.sh`): assert the resulting result carries `outcome:
  failed`, the claim's `refs` still names the answer (it is spent
  regardless of the turn's outcome, per §3), and a further `castle
  dispatch` sweep does **not** produce a second automatic attempt on
  the same errand.
- **A tenant swap between the first and resumed turns.** Run the first
  turn with `scripted-worker-blocking.sh` and the resumed turn with
  `scripted-worker-alt.py` (adapted, or driven via a per-turn
  `CASTLE_WORKER_COMMAND` override between the two `castle dispatch`
  invocations) — this satisfies Proposal 03's re-tenanting claim
  *within a single errand*, which is a stronger form of the property
  `tenant-swap.sh` already proves *across* whole runs: the errand
  boundary, not the tenant, is what makes resumption possible, so
  swapping the tenant mid-errand must not break it.
- **Route after the resumed turn, and reuse `check_assertions.py`
  unchanged.** It already asserts every `result`/`question` has a
  `decision` citing it — a free, strong assertion that a resumed
  result is routed exactly like a first-turn one, never treated as
  second-class.
- **`test/agent-loop/dispatch-test.sh:601-614`'s existing non-behavior
  test keeps passing, unmodified, and that is itself a real validation
  of the opt-in design.** Its fixture question is filed with no
  `--blocking` — under this task's field, that means it is
  structurally incapable of triggering resumption, so the test's
  existing assertions (`count_referencing result "$REQ1"` stays 1,
  `count_referencing claim "$REQ1"` stays 1) continue to hold with zero
  changes to that file. Add a **blocking sibling** to the same file
  (or to `resume.sh` — either is defensible; keeping it in
  `dispatch-test.sh` beside the existing non-behavior test makes the
  contrast between the two cases easiest to read in one place) proving
  the opposite: the same shape, but with `--blocking`, **does** trigger
  resumption once answered. State this pairing explicitly in the PR —
  a reviewer should see both the non-behavior test staying green
  unmodified and its blocking twin going the other way, in the same
  diff.
- **`castle validate` passes on the resulting journal throughout**, not
  only at the end — the same standard every other harness in this
  directory already holds itself to.

**`test/desktop-loop/test.nix` extension**, proving an answer filed
through the real UI causes continuation with no manual command
anywhere. Follow `docs/tasks/0022-answer-in-ui.md`'s own answer-flow
path exactly (§7 of that brief, and lines 594-654 of the current file):
send the chord `meta_l-shift-a`, wait on screen with
`machine.wait_for_text("aiting on you")` before pressing a digit — this
wait is load-bearing, not decorative: `tty.setcbreak` defaults to
`TCSAFLUSH`, which **discards** anything already queued on the pty, so
a digit sent before cbreak is engaged is not mistimed, it is thrown
away, and the picker text becoming visible is the only proof that has
already happened — then a bare digit selecting the question by its
screen-relative index, a `.`-terminated body, and Enter to dismiss.
Concretely: extend the VM's `dispatchWorker` fixture (or add a third,
Nix-level scripted worker beside it, mirroring
`scripted-worker-blocking.sh`) so it raises its question with
`--blocking`; answer it through the modal exactly as 0022's existing
segment already does; then wait, with `machine.wait_until_succeeds`
and a multi-minute timeout matching the existing claim/result waits, for
a **second** claim and a **second** result to appear on the same
request — proving the resumed turn ran with no `castle work` or
`castle route` typed anywhere, the acceptance condition this whole task
exists to satisfy end to end.

**Two things the implementer must be warned about explicitly, both
found by reading the existing file closely rather than by running it
first:**

- `test/desktop-loop/test.nix:387-389`, `:408-411`, and `:417-420` each
  run `ls .../journal/*-<type>-*.md` and `.strip()` the single-line
  result into one path, then `.rsplit`/`cat` it directly. They pass
  today only because they run **before** a second claim or result of
  that type could ever exist on this journal. A resumed turn adds a
  **second** `claim` and a **second** `result` to the same errand these
  lines already inspect — so any fixture this task adds **earlier** in
  the script than those existing assertions will make `ls` return two
  lines and break `.strip()`'s single-path assumption non-obviously (a
  Python exception on a multi-line string being sliced as a path, not a
  clean assertion failure naming what went wrong). The new resumption
  segment must be appended strictly **after** every existing assertion
  that globs `*-claim-*.md` or `*-result-*.md` against the first
  errand's request id, or those existing lines must be re-scoped to the
  specific claim/result they mean (e.g. via `grep -l` against the exact
  request id the way the question/decision lookups on lines 447-450 and
  588-590 already do, rather than a bare `ls` of the whole journal).
  State a preference for the latter fix in the PR if it turns out to be
  the cleaner one to make once real code is in front of the
  implementer — this brief specifies the hazard, not necessarily the
  exact line-level remedy.
- **The VM's tenant raises a question on every turn, unconditionally**
  (`test/desktop-loop/test.nix:104-114`, `dispatchWorker`'s own body).
  A resumed turn driven by the *same* fixture therefore raises a
  **third** question in this VM run (the first errand's question, the
  second errand's question from 0022's existing segment, and now the
  resumed turn's own new one) — which must be routed, and which the new
  segment's own assertions must account for explicitly rather than
  leaving an unrouted or uncounted question sitting in the journal at
  the point the test finishes. If the blocking-question fixture used
  for this task's segment is a *separate* scripted worker from
  `dispatchWorker` (recommended, to keep the two segments' fixtures
  independently readable), it should raise its blocking question once,
  on its first turn, and **not** raise a further question on its
  resumed turn — keeping this task's segment self-contained rather than
  compounding 0022's existing question count.

**What is agent-testable versus what genuinely needs human hands.**
Everything above — `resume.sh`, the extended `dispatch-test.sh`, the
`test/desktop-loop/test.nix` segment (buildable locally with `nix build
.#desktop-loop-test` or via CI) — runs with nothing beyond `bash` and
`python3` on `$PATH` (plus Nix for the VM build), exactly like every
existing harness in this directory. Nothing in this task's scope
requires a human: there is no new UI surface being judged for wording
or taste (§6 explicitly declines the one candidate — a confirmation
step — that would have needed one), and no new option whose default
value needs sanity-checking against real usage the way
`docs/tasks/0021-auto-dispatch.md`'s 900-second timeout did. The one
place human judgment genuinely enters is downstream of this task
entirely: whether a real `claude -p` tenant, given
`agent/castle-worker-claude`'s rewritten prompt (§10), actually sets
`--blocking` at appropriate moments and not others — that is a
statement about model behavior this brief cannot verify with a script,
and it is not part of this task's own acceptance condition (the
mechanism must work correctly *given* a `blocking: true` question,
regardless of how well-calibrated any particular tenant is about
setting it).

## Considered and rejected

Gathered here, once, for a reader who wants the full list without
re-deriving it from the sections above:

- **Who resumes:** the router acting rather than deciding, a separate
  watcher seat, an explicit `castle resume <id>`, and a new errand
  spawned per answer — all rejected in favor of widening dispatch's
  existing eligibility predicate. See §1 for each candidate's specific
  reason, carried forward from the backlog entry this task deletes.
- **The blocking marker:** resuming on every answered worker question
  and letting the resumed tenant no-op — rejected on cost grounds (a
  model turn per non-blocking question, the common shape today) and
  because it corrupts the "an errand's newest turn is its truth"
  invariant `docs/tasks/0021-auto-dispatch.md` §4 already establishes.
  See §2.
- **The spend token:** the `result` record — rejected because neither
  `_write_worker_result` nor `_reap_interrupted` can name an answer id
  in their hardcoded `refs`, so a result-keyed spend token reopens the
  unbounded-retry failure `docs/tasks/0021-auto-dispatch.md` §3.4 exists
  to close, for every resumed turn that fails, times out, or is
  interrupted. See §3.
- **Which questions belong to a given request, for eligibility and for
  the packet:** strict direct `refs == [request_id]` keying — rejected
  because `agent/castle-worker-claude`, the one tenant that actually
  runs in production, never mandates that shape (it hands the `--refs`
  choice entirely to the model, today), so direct keying would leave a
  model-filed question against its own result permanently
  unattributable; and `_collect_downstream` — rejected for the same
  follow-up-contamination reason given for the packet's own source
  fold, below. `_find_root_request`, already used elsewhere in this
  codebase for the identical purpose, is used instead — the same
  `refs[0]` lineage edge, walked through as many hops as the chain
  actually has rather than assuming exactly one. See §4.
- **Exactly-once, resident-facing, with no undo:** a superseding second
  answer while still unspent (the window is illusory — dispatch wakes
  in seconds); full answer-amendment semantics built into this task
  (deferred to its own backlog entry, §10); a confirmation step before
  filing a blocking answer (adds friction without closing the real
  gap). See §6.
- **The continuation packet's source fold:** `_collect_downstream` —
  rejected because it is transitive with no type or errand keying and
  would leak the watermark decision, any correction on the request, and
  a follow-up request's whole subtree into a worker tenant's stdin. A
  selective fold, modelled on `_errand_state`'s existing keying, is used
  instead. See §7.
- **What the packet excludes:** resident-model entries (a real gap,
  deferred as its own, differently-scoped feature — reading the
  resident model at all, which applies equally to first turns);
  `correction` records (the resident judging the system, not
  instructing the errand); `decision` records (the router's own
  channel/timing reasoning about the resident's attention). See §7.
- **A hard turn cap on resumption.** Rejected — every additional
  resumption already requires a fresh resident answer, which is the
  rate limiter; a cap would be an invented constant against a loop that
  cannot run without a human choosing to feed it, each time. See §9.
- **A timeout that resumes an unanswered blocking question "so the
  errand doesn't hang."** Rejected outright, and named explicitly as
  forbidden rather than merely unbuilt — see the closing paragraph of
  §6. Nothing may close a question except the resident.
- **A hard refusal on `castle record --blocking` for a non-question
  type**, mirroring `cmd_record`'s hard refusal of `--type correction`.
  Rejected in favor of the softer, existing `--fact`/`--outcome`
  precedent — the eligibility fold reads `blocking` only on question
  records, so a misapplied flag is inert rather than corrupting, and a
  hard refusal would be new, unrequested rigor beyond what this repo's
  own precedent already established for structurally identical fields.
  See §9.

## Hard constraints, restated

- **Never write personal data into this repo.** Every fixture in §11
  uses obviously invented, hardware-neutral content, matching the
  existing convention in `test/agent-loop/*` and
  `test/desktop-loop/test.nix`. The resumption path handles the
  resident's verbatim words by design — that is the entire point of
  the continuation packet — so no sample of a real answer, real
  question, or real request body may ever be committed anywhere in this
  diff.
- **Principle 01: public mechanism, private configuration.**
  Resumption inherits `castle.agent.dispatch.enable`'s existing gate
  for free, by living entirely inside dispatch's own eligibility fold:
  it adds no new Nix option, no new environment variable a resident
  configures, and no new authority decision beyond the one
  `docs/tasks/0021-auto-dispatch.md` already shipped (default off,
  opt-in, "the resident's authority decision to make on their own
  machine"). State this explicitly in the PR rather than leaving it
  implicit — a reviewer will reasonably ask whether resumption needs
  its own option, and the answer is that it structurally cannot need
  one: there is no code path in this design that resumes anything
  without going through the same dispatch sweep every other automatic
  turn already goes through.
- **A resumed turn is still propose-only.** No `nixos-rebuild`, no
  `git commit`, no applying anything to a running system, from this
  seat, on this or any other turn. See §6's closing paragraphs for the
  specific temptation this task creates and why the design does not
  yield to it.
- **Nothing may let anything other than the resident close a
  question.** No default, no timeout, no second model judging
  sufficiency. See §6.
- **No `nixos-rebuild`, no real `CASTLE_STATE_DIR`, no model tenant in
  any test.** Every fixture in §11 is scripted, deterministic, and
  model-free, following every existing harness in `test/agent-loop/`.

## Non-goals

- **Answer-amendment semantics.** Which answer governs when a question
  receives more than one, and what happens to work already done under
  a superseded one. Filed as its own backlog entry (§10); §6(b)
  explains why building it here would widen this task past resumption
  itself.
- **A confirmation step before filing a blocking answer.** Considered
  and declined (§6(c)) — it adds friction without closing the
  underlying no-undo gap.
- **Any change to how questions are routed, delivered, or displayed.**
  `docs/tasks/0021-auto-dispatch.md`'s router paragraph and
  `docs/tasks/0022-answer-in-ui.md`'s answer-mode picker are untouched;
  a blocking question routes and displays exactly like a non-blocking
  one, distinguished only by the fold this task adds underneath both.
- **Workers reading the resident model, on any turn, first or
  resumed.** A real, named gap (§7's closing paragraph) — different
  feature, filed as its own backlog entry (§10).
- **`castle record --refs` resolving its refs before writing.** A real,
  separate gap this task documents living with for `answer` records
  specifically (§5) and generalizes into its own backlog entry (§10).
- **Any change to `castle.agent.dispatch.enable`'s meaning, default, or
  gating.** Resumption rides the existing option entirely; no new
  option is added (see Hard constraints).
- **Proposal approval, configuration mutation, or deployment from any
  automatically-invoked seat.** Unchanged from `docs/tasks/0021-auto-
  dispatch.md`'s own non-goals — this task adds no new authority beyond
  the worker seat's existing, unchanged propose-only contract (§6).
- **Sensors, or any new signal deciding *when* to resume beyond the
  existing path-unit/timer trigger.** An answered blocking question is
  the only new eligibility signal this task adds; nothing here reads
  window focus, calendar state, or any other ambient input.
- **A staleness clock or timeout on an unanswered blocking question.**
  Explicitly forbidden, not merely unbuilt — see §6's closing
  paragraph.
- **New intake channels, or any change to how questions are filed in
  the first place** beyond the addition of the `--blocking` flag
  itself. Everything about `castle ask`/`castle-modal`'s compose mode
  is untouched.

## Implementation prompt

For the session that implements this brief: read `CLAUDE.md` in full,
this brief in full, `docs/architecture.md`, `agent/README.md`,
`docs/tasks/0021-auto-dispatch.md`, `docs/tasks/0022-answer-in-ui.md`,
and every file this brief names as being modified, before writing any
code. Work on branch `sprint/0023-resume-cold` (already created and
carrying this brief; do not rewrite the brief silently — if
implementation surfaces a genuine deviation from what it specifies, say
so prominently in your own report and amend this brief in the same PR,
per `CLAUDE.md`'s rule that a brief overtaken by the work it rides gets
corrected in place). Keep `agent/castle` stdlib-only, no third-party
dependency of any kind, readable top to bottom — a hard constraint
carried over from every prior task in this directory, not new to this
one.

Implementation order that matches the design's own dependency chain:
(1) the `blocking` field, `FIELD_ORDER`, the validator block, and
`--blocking` on `castle record` (§2, §9) — the smallest, most isolated
piece, and everything else reads it; (2) `_resumable_answers` (§4) as a
standalone function, tested against a hand-built journal before it is
wired into anything; (3) the claim `refs` change and the packet
builder inside `run_worker_turn` (§3, §7), together, since they share
the same `_resumable_answers` call and the same turn-start
recomputation point; (4) `CASTLE_RESUME_ANSWER_IDS` (§8); (5) the
`_eligible_requests` widening and the `cmd_dispatch` skip-set comment
fix (§4); (6) documentation (§10); (7) the test suite (verification
plan, above) — write `resume.sh` and `scripted-worker-blocking.sh`
alongside the code they exercise rather than entirely after, since the
fixture's stdin-echoing behavior is the actual proof the packet builder
works and is easiest to get right iteratively against a real fixture
rather than written blind against a spec.

Run `test/agent-loop/*.sh` (all five harnesses after this task) and
`nix flake check` locally before opening a PR; build
`test/desktop-loop/test.nix` locally with `nix build
.#desktop-loop-test` if the machine has the resources, or trigger it in
CI via `gh workflow run desktop-loop-test.yml` if not. Per `CLAUDE.md`'s
multi-agent conventions: run `/code-review` scoped against
`origin/main` and address its findings, then run
`tools/codex-review.sh` for a second, cross-model opinion, posting its
findings verbatim with any disposition in a separate comment
underneath, before opening the PR. `git fetch` first and confirm the
real diff scope with `git diff origin/main...HEAD --stat` before
trusting any review output.

Never touch `docs/principles/` or `CLAUDE.md`. Never write anything
resembling real resident data — a real question, a real answer, a real
request body, a real complaint — into a fixture, a test, or a code
comment; every example string in this brief and in the existing
codebase it extends is invented and hardware-neutral, and new ones must
be too.
