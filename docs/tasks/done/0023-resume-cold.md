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

**A stated limit, not an oversight: an errand excluded by any other
condition can never resume, even after a hand-run turn raises a
blocking question on it.** Two shapes are excluded — a request the
watermark names as predating dispatch, and a request carrying
`filed-during-turn`, which a tenant wrote mid-errand — and resumption
is ANDed with both, so this sequence ends in silence either way: the
request is excluded; the resident runs it by hand with `castle work
<id>`; that turn files a `--blocking` question and stops; the resident
answers it — and nothing happens. `_resumable_answers` finds
the unspent answer, and the watermark clause rejects the request
anyway. The modal says only "Filed.", so there is no surface saying
why.

Kept deliberately, for the reason those exclusions exist at all. Each
is a promise about what will not start itself — errands predating
dispatch (`docs/tasks/0021` §2.2), and work a tenant generated rather
than a resident (§2.4(e)) — and letting either begin producing
automatic turns because a resident hand-ran it once would turn a single
manual start into a standing permission. A restored journal's history,
or a tenant's own follow-up queue, would gain a second route into
unattended work, which is precisely what both exclusions close. The conservative direction is also the safe one: the cost of
this limit is a turn that has to be started by hand, and the cost of
the alternative is unattended spend on errands a resident considered
finished months ago.

What is *not* acceptable is leaving the interaction undocumented, so a
resident meets a silent dead end this very task exists to remove and
nothing anywhere explains it. It is stated here and in
`agent/README.md`'s "Resuming an errand" subsection, in both cases with
the remedy, which is the same command that started the turn in the
first place: **`castle work <id>` by hand** continues the errand,
because `run_worker_turn` resumes whatever is unspent on any path,
dispatched or hand-run (§7), and never consults the watermark.

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

**Corrected during implementation: this section asked the wrong
question about "who else writes an answer," and the omission was a
high-severity defect.** Everything above reasons about a *hand-planted*
duplicate — a resident or a script writing a second answer to one
question — and concludes the fold should tolerate it. It never asks
who else has hands on `castle` at all, and the answer is: a worker
tenant, on every turn, through the same CLI, with `CASTLE_WORKER_CLAIM`
in its environment. `write_record` stamped `filed-during-turn` only on
`type == "request"`; nothing on the answer path read the claim at all;
`cmd_record` refuses only `correction`; and `file_answer` never
consulted it either. So a tenant could file a fresh blocking question
**and its own answer** on the same turn — its own claim spends only
what existed when the turn began, so the new answer was unspent, and
the errand was eligible on the very next sweep. Reproduced at five
claims and five results on one request, across five sweeps, through
both `castle answer` and `castle record --type answer`.

`docs/tasks/0021` §2.4(e) severed exactly this chain for requests; this
task opened a second way for a journal write to authorise an unattended
turn and did not sever it.

**The fix is a refusal, not a narrower fold, and the reason matters
more than the loop does.** Making a tenant-written answer merely
non-resuming is the smaller change and it is wrong: the answer would
still land in the journal, still satisfy the "is this question
answered" fold every surface uses, and so still retire a question the
resident was supposed to see — the system closing its own question,
which Proposal 05 forbids outright and which this brief's own stop
conditions name as the erosion edge. So `write_record` refuses
`type == "answer"` outright whenever a claim id is present in the
environment: one choke point, covering `castle answer`, `castle record
--type answer`, the modal, and any writer added later, exactly where
the request stamp already lives rather than per-subcommand. It is safe
for every legitimate writer because `run_worker_turn` sets
`WORKER_CLAIM_ENV` on the child's env dict and never on `os.environ` —
so the dispatching process's own claim, result and decision writes
never see it. The refusal says why in Proposal 05's terms, because a
tenant that meets it should be told what it just tried to do.

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
or summarised.** (Implementation note, added after review: what this
section calls a "heading" is, as built, a boundary line carrying a
per-turn nonce. A `result` body is model-authored and is quoted into
the next turn's packet, so a plain markdown heading is forgeable by the
very text it is supposed to attribute — see the As-built section at the
end of this brief. Everything below about *what* each section holds and
*in what order* is unchanged.)

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

**Amended during implementation (pass 8): the validator also scopes
`blocking` to question records, reversing this section's own
instruction to leave the field unscoped so a future seat might find a
use for it.** That instruction was written when nothing enforced the
field's record type anywhere, and it was reasonable then: an inert
field on an unrelated record cost nothing, and refusing it would have
been rigor this repo's own `--fact`/`--outcome` precedent did not ask
for. It stopped being reasonable when pass 7 added the write-time
refusal of `--blocking` on any type but `question`. From that point the
validator was laxer than the writer — `castle record` refused to write
`blocking: true` on a result while `castle validate` called the same
hand-written record clean — and the backstop must not be weaker than
the door, precisely because the records it exists for are the ones the
CLI never touched: hand-written, restored from a backup, or produced by
some later tool. The original reasoning stays above rather than being
edited away; what changed is the world it described.

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
- **Moving the tenant-runnability checks above the claim write, or
  omitting the answer refs on those three branches** — proposed by the
  ninth review pass on correct facts, and rejected. The facts: the
  claim is written before `CASTLE_WORKER_COMMAND` is checked at all, so
  a host with an empty or unrunnable tenant spends the resident's
  answer on a turn in which no process ever started. Both proposed
  remedies leave the answer unspent, and that is strictly worse. Work
  it through: the request already carries a `failed` result, so
  eligibility runs through `_resumable_answers`; the answer is unspent,
  so it comes back; the request is eligible again on the next timer
  tick; the tenant is still misconfigured; and it loops at one attempt
  per minute, forever. That is exactly `docs/tasks/0021` §3.4's
  unbounded silent retry, reached from a direction 0021 did not have to
  consider. Spending the answer is what bounds it, and the ordering
  that spends it — claim first, runnability second — is the same
  ordering that guarantees every turn which starts leaves a claim (§3).
  What the finding correctly identified was a *prose* defect rather
  than a mechanism one: the claim asserted a turn had "begun" and
  printed an empty tenant command, and the `failed` result never told
  the resident their answer had been spent or that a hand run would
  still use it. Both fixed; the mechanism is unchanged. See the
  As-built section.
- **A hard refusal on `castle record --blocking` for a non-question
  type**, mirroring `cmd_record`'s hard refusal of `--type correction`.
  Rejected in favor of the softer, existing `--fact`/`--outcome`
  precedent — the eligibility fold reads `blocking` only on question
  records, so a misapplied flag is inert rather than corrupting, and a
  hard refusal would be new, unrequested rigor beyond what this repo's
  own precedent already established for structurally identical fields.
  See §9.

  **REVERSED during implementation, at the seventh review pass, and the
  original reasoning above is kept rather than edited because a
  reversal that erases what it reversed teaches nobody anything.** The
  argument was sound when it was made and stopped being sound because
  of this task's own later work, not because anyone re-weighed it. It
  rested on `--blocking` resembling `--fact` and `--outcome`: flags that
  name their record type by convention and enforce nothing at write
  time. `--blocking` no longer resembles them. It acquired a write-time
  guard two passes earlier (first refusing empty `--refs`, then
  refusing refs whose first entry reaches no request), and once a flag
  is enforced at write time, "this flag is unenforced by precedent" is
  no longer a description of it. What remained was a line nobody could
  defend: refusing a question that could never be attributed to an
  errand, while accepting `blocking: true` on a `result` — a record
  that writes cleanly, validates cleanly, reads as meaningful to any
  human skimming the journal, and does nothing at all. Both are the
  same mistake by a writer: believing it has stopped an errand when it
  has not. The refusal was added, with the same shape as the two guards
  beside it, and `resume.sh` asserts a `--type result --blocking` write
  is refused.

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

## As built — where the implementation departed from this brief

Written by the implementing session, per `CLAUDE.md`'s rule that a brief
overtaken by the work it rides gets corrected in place rather than left
describing something that was not built. Nothing in the design above
changed; these are the places the code is narrower, wider, or differently
shaped than the text specifies, each with the reason.

- **`blocking` is tested for the literal `true` everywhere, in the fold
  as well as the validator.** §4 defines the fold's test as "`blocking`
  non-blank (any truthy spelling `castle record --blocking` can
  produce)" and §9 leaves the validator equally loose. Both are built
  strict instead, through one shared predicate (`_is_blocking`), and the
  reason is which way an unrecognised value fails. Under
  non-blank-means-blocking, a hand-planted `blocking: false` — or
  `blocking: maybe`, or a typo — **resumes an errand** while its own
  text says otherwise: a surface acting on a value it did not
  understand, which is the failure `outcome`'s "render an unknown value
  verbatim, never as done" rule already exists to prevent
  (`docs/tasks/0021` §3.5). Under an exact test the same record is
  simply inert.

  Putting the strictness only in `cmd_validate` would not have been
  enough, and the first version of this work made that mistake:
  `castle validate` is advisory and nothing invokes it automatically —
  `cmd_dispatch` reaps, folds, works and routes, and never validates —
  so on a real host the record would still have resumed the errand,
  with the guard firing only if a human happened to run the validator.
  The two checks are kept, doing different jobs: the fold decides
  behaviour and declines, the validator reports the record so an inert
  value is visible rather than merely harmless. `render_continuation_
  packet` uses the identical predicate, so the packet can never describe
  a question as blocking that the fold treated as not, or the reverse.
  `resume.sh` plants a `blocking: false` question, answers it, and
  asserts no turn runs; `dispatch-test.sh` asserts `castle validate`
  rejects the same record.
- **A resumed turn's `claim` body carries one extra paragraph.** §3 says
  "nothing else about the claim record changes." A first turn's claim is
  byte-identical to before, as specified; a resuming one gains a sentence
  saying it is a resumption and that the ids after the request id are the
  answers it spent. Without it a cold reader meets an unexplained second
  ref in a record whose prose describes only a turn beginning. No
  frontmatter field was added and no reader's keying changed.
- **`CASTLE_RESUME_ANSWER_IDS` is explicitly removed from a non-resuming
  tenant's environment.** §8 says "absent, not empty," which the brief
  treats as a matter of not setting it. The tenant's environment starts
  as a copy of the dispatching process's, so a stale value — exported by
  hand, or inherited by a tenant that itself runs `castle work` — would
  be passed through. Absence has to be made rather than assumed.
- **`agent/castle-worker-claude`'s prompt lost the line "The resident's
  request, in their own words."** §10 specifies the rewrite of item 4
  only, and §7 notes the packet arrives where the request body used to.
  Left alone, that label would introduce a resumed turn's prior results
  and the resident's answer as though all of it were the request. The
  replacement says what the text now is: the errand's records, verbatim
  from the journal.
- **The mid-errand tenant swap uses a new fixture rather than an
  adapted `scripted-worker-alt.py`.** §11 offers "adapted, or driven via
  a per-turn override," but adapting that file is not available —
  `tenant-swap.sh` fingerprints its behavior and the brief also requires
  it stay byte-for-byte untouched. `scripted-worker-blocking-alt.py` is
  a new, differently-shaped (Python) contract tenant that holds the
  resumed turn while the bash fixture holds the first.
- **`resume.sh` covers three cases beyond the enumerated list**, each
  because the design rests on it: a blocking question filed against its
  own `result` rather than the request (the shape §4 says strict keying
  would strand), a follow-up request's blocking question resuming the
  follow-up and never its parent (the contamination §4 rejects
  `_collect_downstream` over), and a `correction` planted against the
  errand's request before the answer, which the resumed tenant refuses
  outright if it ever reaches its stdin (§7's exclusion, enforced rather
  than hoped for).
- **The desktop-loop VM extends `dispatchWorker` rather than adding a
  third Nix-level worker.** §11 recommends a separate fixture for
  readability, but `castle.agent.worker.command` is one option for the
  whole VM, so a second fixture would need the command swapped
  mid-session — machinery worth more than the readability it buys. The
  existing fixture instead branches on `CASTLE_RESUME_ANSWER_IDS`,
  raising its blocking question only on a non-resumed turn, which
  satisfies §11's "should not raise a further question on its resumed
  turn" requirement directly. It also refuses its own resumed turn if
  the resident's answer is missing from the packet.
- **`test/desktop-loop/test.nix`'s existing single-path `ls` assertions
  were left as they are.** §11 offers re-scoping them with `grep -l` as
  the possibly-cleaner remedy. Appending the new segment strictly after
  all of them was enough, and re-scoping assertions this task does not
  otherwise touch would have widened the diff for no behavioral gain.
  The constraint is now recorded in the new segment's own comment, where
  the next person to add a segment will meet it.
- **`test/agent-loop/modal-headless-test.sh` had two occurrences of the
  deleted confirmation string, not one.** §10 names line 858; the piped-
  stdout assertion later in the same file carried it too. Both were
  updated.
- **Three sentences this task falsified were rewritten where they
  stood, and one of them is a record a resident actually reads.** The
  reaper's `interrupted` result body said "Nothing is re-run
  automatically: one automatic attempt per request, always" — routed to
  notify, permanent in an append-only journal, and false in a case
  reachable *within the same sweep that writes it* (a turn dies after
  filing a blocking question, the resident answers, and the loop below
  the reaper re-folds and starts another turn seconds later). It now
  states the rule that is true unconditionally: this *turn* is not
  retried, an answer to a blocking question starts one further turn,
  otherwise `castle work <id>`. Deliberately not made conditional on
  `_resumable_answers` at write time — the answer may not have arrived
  when the reaper runs, so a conditional sentence would be right
  sometimes and wrong the rest, which is worse than a flat one.
  `cmd_work`'s docstring ("automatic dispatch never re-runs anything by
  construction of its eligibility fold") was corrected the same way, and
  `_requests_with_results` keeps its sentence — still true of what that
  function returns — with a pointer to the one caller-level override and
  a note that the spend-on-claim rule is what keeps the bound
  structural through it.
- **The packet no longer claims every request is the resident's own
  words.** §7 specifies the heading as "identifying it as the original
  request," and the first implementation hardcoded "in the resident's
  own words." Two shapes make that false — `castle ask --provenance
  initiated`, and a tenant-filed follow-up carrying `filed-during-turn`,
  which is never auto-started but is hand-runnable and so reaches this
  function. The heading is now keyed off what the record actually
  carries, with no new vocabulary invented, and
  `agent/castle-worker-claude`'s prompt says the headings are what tell
  a tenant whose words it is reading. This is the one turn where
  everything else in this task insists an answer grants no authority;
  attributing machine-authored text to the resident pushes precisely
  the other way.
- **Results were the last surface still matching a request anywhere in
  a record's refs** — the cross-model pass again, on the tree that fixed
  its first finding. Questions went through `_find_root_request`, claims
  were keyed `refs[0]`, `_collect_downstream` was narrowed a round
  earlier; `render_continuation_packet`'s result selection and
  `had_prior_turn` were the two that never got converted. Since `castle
  record --type result --refs <B>,<A>` is permitted, errand B's output
  could be rendered into A's packet as "an earlier turn on this errand"
  — another errand's work quoted to a tenant as its own history — while
  the same broad test set `CASTLE_RESUME_ANSWER_IDS` and narrated a
  resumption whose account the packet did not contain. Both key on
  `refs[0]` now, which is invisible to every result this repo writes:
  `_write_worker_result` writes `[request.id, claim_id]` and the reaper
  `[request_id, claim.id]`, checked rather than assumed.

  **`_requests_with_results` deliberately keeps the broad test, and the
  two folds now each point at the other saying why.** An unexplained
  inconsistency between two folds is what several of these findings
  have been, so this one is argued rather than left: same records, same
  ambiguous input, opposite risk. For eligibility, guessing wrong
  withholds an automatic turn and costs a resident one typed command —
  and the broad test is what keeps 0021 §2.4(b)'s bound intact,
  including for a resident who hand-closed an errand as `--refs
  <claim>,<request>` and would otherwise have it silently reopened. For
  the packet, guessing wrong hands a tenant another errand's output;
  there is no benign side. Bounds fail toward not spending, context
  fails toward not fabricating. The one residual that reasoning leaves
  is named in `_requests_with_results`'s own docstring rather than left
  to be found: a stray secondary ref written before dispatch ever ran
  keeps a request off the watermark's exclusion list, so a blocking
  answer could later resume an errand that predates dispatch — four
  things that must line up, against an alternative that needs only two
  refs typed in the order that reads more naturally.

  Two fixture mistakes of my own on the way here, both the same shape
  as ones this task has already paid for: the first version let the
  sweep work the errand that was supposed to have no turn of its own
  (making a correct resumption narrative look like the bug), and the
  second used a tenant whose first-turn branch never echoes the packet,
  so a broadened packet fold passed unnoticed until the mutation test
  said so. The case now runs a tenant that dumps its stdin and asserts
  both directions — the stray result absent, this errand's own request
  present.
- **One answer could still buy two turns, and it took the cross-model
  pass to see it.** Ten review passes of the same family cleared the
  spend bound repeatedly — including a pass that specifically probed
  for a constructible unbounded loop and found none. Codex, run once on
  the finished tree, found the hole: the bound is global (an answer,
  not an errand) but the mutual exclusion around it was per-request.
  Two `castle work` invocations on two different requests take two
  different leases, exclude each other not at all, and can both read
  the journal before either writes its claim — so with one answer
  naming blocking questions on both errands, both see it unspent and
  both spend it. That is the exact shape `resume.sh` already builds for
  the sequential case, which passed because dispatch works one errand
  at a time.

  **Worth a sentence about why the family missed it**, in a repo that
  pays for a second reviewer precisely to catch what the first cannot:
  the comment directly above that recomputation already reasons about a
  race — dispatch's fold against a hand-run turn — and closes it with
  `require_resumable`. But that guard fires when the recomputation
  comes back *empty*, and this race is the opposite shape, where both
  racers see it *non-empty* and both act. A guard written for one
  direction of a race reads, to a reviewer working down the same file,
  as though the race is handled. That is not a failure of care; it is
  what a second, differently-trained reader is for.

  Fixed with the idiom already here: a blocking global lock
  (`spend_lock_path`, beside `route_lock_path` and
  `dispatch_lock_path`), held across the recomputation and the claim
  write and released the moment the claim exists. Deliberately not held
  across the tenant call, which can run 900 seconds — that would turn
  "one turn at a time per errand" into "one at a time per machine", a
  behavioural change rather than a fix. Blocking rather than
  try-and-skip, for the reason routing already gives: a lease conflict
  means there is nothing left to do, while a spend-lock conflict means
  another turn is microseconds from finishing its accounting, after
  which this one has a correct answer to compute from. The lock
  ordering — sweep lock → per-request lease → spend lock — is written
  where the lock is defined, because the next person adding one is who
  could break it. `require_resumable` stays: it covers the other
  direction and is still needed.

  **Tested in two parts, because the interleaving cannot be forced.**
  The window between the fold and the claim write is microseconds
  inside one process with no hook in it, so a wall-clock race would
  pass with or without the lock — a test that cannot fail on the
  defect. Instead: a holder process takes the spend lock and asserts
  `castle work` does not reach its claim until the lock is released
  (deterministic, and it fails when the lock is removed); and a
  source-level check that no release sits between the acquisition and
  the claim write, which is the half the behavioural test cannot see —
  releasing early passes the first test while reopening the race.
  The source check is written to survive an honest `with`-block
  refactor and was verified not to fire on one.
- **The narrowed walk left two surfaces contradicting each other, and
  three documentation lines still described the old rules** — the tenth
  review pass, which found no correctness defect in the resumption
  mechanism itself.

  The behavioural one was this branch's own doing, one round old.
  `_errand_state` derived "which of this errand's questions are
  answered" from the errand walk, so once that walk was narrowed to the
  lineage edge, an answer written as `--refs Q_A,Q_B` (generic writer
  only) was missing from errand B's fold: B's status line said "waiting
  on you — press Mod4+Shift+a to answer" permanently, while the picker,
  folding every answer record flat, correctly declined to offer Q_B
  because it is answered. A resident sent to a surface that will not
  show them what they were sent for is `docs/tasks/0015` scope 3
  exactly. The previous round's docstring called this "a display
  imprecision", which understated it — two surfaces do not disagree
  imprecisely, they disagree.

  Fixed by making the three folds agree rather than by reverting the
  narrowing, which closes a real leak. `file_answer`'s duplicate guard
  and `_pending_questions` both already asked "does any answer record
  name this question"; `_errand_state` now asks the same, from the same
  flat pass, while still taking *which* questions belong to the errand
  from the walk. `_pending_questions`' docstring has asserted all three
  agree since before this branch — a sentence that was false for one
  round and is true again. `_collect_downstream`'s own docstring is
  amended, since the residual it documents is now only about which
  digest section an answer is listed under.

  The three documentation lines: `agent/README.md` still called
  `--blocking` "question-records-by-convention in the same way" as
  `--fact` and `--outcome` — contradicted fifteen lines later in its own
  bullet and by three hard refusals in the code; the `blocking` section
  described the validator as a value check with no mention of the type
  scoping added in this same branch, which a resident restoring a
  hand-edited journal would meet as an unexplained failure; and the
  eligibility fold's ordering comment claimed the expensive case was the
  restored-history one the watermark excludes, when this branch's own
  backlog entry measures the steady state — ordinary completed errands,
  neither excluded nor stamped — as the case that pays. That last one
  mattered most: a future reader deciding whether to optimise the fold
  would have read it and concluded the cost cannot recur. It now carries
  both numbers (1 ms excluded, 130 ms not) and says plainly that the
  reorder removed one case and left the other standing.
- **One errand's fold reached into another's, and three statements
  about this task's own mechanism were wrong** — the ninth review pass,
  which also proposed one change that was rejected on the merits (see
  the considered-and-rejected list; taking it would have traded a burned
  answer for an unbounded retry loop).

  `_collect_downstream` predates this task and followed *any* ref,
  which was harmless while every record's later refs pointed inside its
  own errand. A resuming claim naming the answers it spends ended that:
  with one answer naming blocking questions on two requests — the shape
  `resume.sh` itself builds — errand A's fold reached the shared answer,
  then B's claim (`refs: B, <answer>`), then B's result and decisions,
  so `castle digest` printed B's records under A and
  `castle-modal --mode status` listed B's decisions as A's. It now
  follows the lineage edge, with a second clause for records naming the
  root directly — which is what keeps the watermark visible in *every*
  errand it excluded rather than only the one at its `refs[0]`. Both
  walks were compared over a journal built from every shape this repo
  writes rather than assumed equivalent; they agree everywhere, and the
  only divergences are records the generic writer alone can produce
  (documented in the function's own docstring, including the residual
  where a two-errand answer sits in the fold of the question it names
  first).

  That second clause turned out to be unasserted anywhere:
  `modal-headless-test.sh` planted a watermark naming exactly one
  request, where `refs[0]` and "names this errand" are the same thing.
  It now plants one naming two, and asserts the second gets the
  predates-dispatch label — a coverage gap this repo had before this
  task, made load-bearing by it.

  Three statements were also false. The claim record said a turn
  "began" and printed `Tenant command: ``` `` ``` before the command was
  known to be runnable — worded now for what is true at write time
  ("took this errand", "will spend"), the same discipline the reaper's
  sentence needed. `agent/README.md` still documented the spend rule as
  per-request after the fold went global, so a reader implementing from
  it would have built the version the code deliberately rejects. And
  both the README and `render_continuation_packet`'s docstring claimed
  a first turn's packet "degenerates to the request body", which is
  false for the case the code supports and `resume.sh` tests: a
  blocking question filed and answered before any turn ran gives a
  first turn a question and an answer section. What distinguishes a
  first turn is the absence of an earlier turn's *account* — which is
  exactly what the narrative gate keys on.
- **The choke point was closing the narrower of two doors** — the
  eighth review pass, and the finding that mattered most in it. With
  `CASTLE_WORKER_CLAIM` set, `castle answer` was refused and `castle
  correct` succeeded: a tenant could file a `correction` carrying
  `seat: intake, provenance: requested`, plus the
  `provenance: volunteered` resident-model entry `file_correction`
  writes alongside it. An answer closes a question the resident never
  saw; a correction invents an opinion the resident never held and
  files it where the router reads it afterward. The larger harm was the
  unguarded one.

  Fixing it decided no policy: `cmd_record` has refused `--type
  correction` since `docs/tasks/0010-correction-record.md`, with a
  comment giving exactly this reason, so the prohibition already
  existed and `cmd_correct` was simply a second door onto it. The
  refusal now covers both types at the one point every writer passes,
  with a message that distinguishes the two harms rather than
  flattening them. Confirmed a sweep cannot trip it, the same two ways
  the answer refusal was confirmed: nothing in `agent/castle` or
  `agent/castle-modal` ever assigns into `os.environ` (there is no
  `os.environ[...] =` in either file), so the variable is present only
  in a process descended from a tenant; and the records a sweep writes
  for itself are `claim`, `result` and `decision` — `file_answer` and
  `file_correction` are reached from the CLI and the modal only.
  `castle-modal`'s compose path learned to report the refusal, as its
  answer paths already did.

  Three smaller gaps came with it. **The validator called clean the
  exact record the writer refuses** (`blocking: true` on a result) —
  scoped to questions now, which reverses this brief's own §9
  instruction; that section records the reversal and keeps the original
  reasoning. **`--blocking`'s `--help` contradicted the code in three
  places**, still describing the flag as convention-only, requiring
  merely that `--refs` be present, and saying nothing about `--spool`;
  it is the only place besides the worker prompt where a tenant can
  learn the rule, so it now states all three refusals. **And one answer
  could buy two turns**: `spent` was drawn from claims whose
  `refs[0]` matched this request, so an answer naming blocking
  questions on two errands was unspent from each errand's point of view
  and both resumed — while `agent/README.md` states the bound as
  "exactly one, per answer, ever". The spend set is global now, because
  the bound is a property of the answer rather than of the errand
  reading it; a normally-written answer refs one question and cannot
  tell the difference.
- **Three more ways `--blocking` could mean nothing, one false sentence
  in a routed record, and one ordering fix** — the seventh review pass,
  recorded together because four of the five are the same question:
  what happens when a writer believes it has stopped an errand and has
  not.

  `--spool` defeated the reachability guard outright: the guard resolves
  refs against the journal, the record goes to the spool, so
  `--blocking --refs "$CASTLE_REQUEST_ID" --spool` passed on a ref that
  really did reach a request and landed the question somewhere no fold
  reads and logout deletes. Refused as a combination rather than
  resolved against the spool, because the incoherence is prior to the
  unreadability: a blocking question is a durable claim that an errand
  has stopped until the resident answers, and the spool is the store
  that promises to forget (docs/architecture.md).

  `--blocking` on a non-question type is now refused too, which
  **reverses** this brief's own considered-and-rejected entry — see that
  entry, which keeps its original reasoning and records why the
  precedent it rested on stopped applying.

  The reaper's account said "if this errand raised a blocking question,
  the resident's answer to it starts one further turn on its own",
  unconditionally, in a permanent record routed to the resident. False
  exactly when the crashed turn *was* the resumption: its claim already
  spent the answer. Reworded to be true in both cases rather than
  computed — a fold at write time would be correct at the instant it ran
  and wrong by the time anyone read the record, which §3's own reasoning
  about conditional sentences already rejected. It now says an answer to
  a blocking question the errand "has not already resumed on" makes it
  eligible for one further turn. *Eligible* rather than *starts* is a
  small deliberate strengthening beyond the wording the review
  suggested: a watermarked or `filed-during-turn` errand is never
  started automatically whatever is answered, and "starts" would have
  been the same class of overclaim one exclusion further out.

  `_resumable_answers` also moved behind the two dict-lookup exclusions
  in `_eligible_requests`. Pure ordering, no behaviour change, and it
  removes the case that made the scan expensive in the first place: a
  restored pre-dispatch history where every request has a result and is
  named in the watermark's refs, folded in full and discarded once a
  minute forever. Re-measured on the same 2000-record journal as the
  original 117 ms figure: **1 ms when the watermark excludes everything,
  130 ms when it excludes nothing.** `docs/backlog/eligibility-fold-
  rescans-per-request.md` is amended to say what reordering bought and
  what hoisting is still owed, so the entry does not overstate the debt.

  And `agent/castle-worker-claude` no longer invents a boundary token
  when the packet declares none. The fallback fenced the harness's
  instructions with a token the packet's boundaries do not carry, while
  the prompt tells the tenant one token marks both — a prompt whose
  stated rule is false, reachable only if `castle`'s packet format ever
  changed underneath that file, which is exactly when nobody would be
  looking for it. It exits nonzero naming the mismatch: the errand
  spends its one automatic attempt and the result record says why, which
  is a better failure than a tenant that cannot tell an instruction from
  a quotation being handed a repository.
- **Two guards were applying a different rule from the thing they
  guard**, found together in the sixth review pass and worth recording
  as one shape rather than two incidents: a check that is *adjacent* to
  what it protects reports a safety it cannot deliver, and both of these
  had been introduced by a fix to an earlier finding.

  The reachability check on `--blocking` (§9, as amended two passes
  earlier) asked whether **any** ref reached a request. `_resumable_
  answers` hands `_find_root_request` the question record itself, and
  that walk follows `refs[0]` and nothing else — so
  `--refs "<wrong-id>,$CASTLE_REQUEST_ID"` satisfied the guard on the
  strength of an id the fold never reads. The question was written,
  answered, and permanently unattributable: the exact dead end the
  guard refuses to write, produced by exactly the mistake its comment
  predicts. It now tests `refs[0]`, which is the lineage edge claims,
  results and questions all already key on, and the refusal message
  names the first ref specifically rather than implying every ref
  counts.

  `had_prior_turn` (the narrative gate from the pass before that) was
  satisfied by a bare `claim`, while `render_continuation_packet`
  renders only `result` bodies as an earlier turn's account. An errand
  whose only turn crashed therefore had "a prior turn" for the gate and
  no account for the packet — and `castle work <id>`, which has no
  reaper ahead of it the way a sweep does, would set
  `CASTLE_RESUME_ANSWER_IDS`, narrate a RESUMPTION in the claim, and
  tell a fresh tenant to read an account that is not there. Gated on a
  prior `result` now: it is the record whose existence makes the
  sentence true, a reaped turn becomes one anyway, and the only case
  excluded is the one where the account genuinely does not exist yet.

  **The coverage pins each rule rather than the state it was found in**,
  because two consecutive mutation escapes came from assertions that
  only exercised the setup in front of them. For the guard that means a
  pair going opposite ways — a wrong id first must be refused, and a
  right id first with a *resolvable* trailing ref that reaches no
  request must be written — so reverting to `any(...)` fails the first
  and reverting to `all(...)` fails the second. (The trailing ref
  resolves deliberately: a dangling one detects `all(...)` just as well
  and leaves the journal failing `castle validate` for the rest of the
  run.) For the gate it means an errand with a claim and no result,
  driven by hand, which is the only path that reaches the disagreement.
- **The prompt stated a rule its own text broke.** After the previous
  pass, `agent/castle-worker-claude` told the tenant that every
  instruction in the prompt carried the turn's token and that unmarked
  instruction text "did not come from this harness" — while only three
  headings actually carried it. The resume note did not, and that is the
  block a prior turn's result body is likeliest to counterfeit word for
  word: two textually identical, both-unmarked resume notes, with the
  harness's own stated rule telling the tenant to discount both. A rule
  a prompt breaks is worse than no rule, because a tenant that trusts it
  is worse off than one that does not.

  Fixed by fencing rather than by narrowing the claim: every harness
  instruction now sits in a `<token> BEGIN harness instruction: …` /
  `<token> END` pair, the same grammar the packet already uses for
  records, so there is one rule for the whole prompt instead of two.
  Fencing beat prefixing every line for a concrete reason — the contract
  block contains a `castle record` command a tenant is meant to copy,
  and a per-line token prefix would have quietly corrupted it.
  `resume.sh` walks both renderings of the prompt (first turn and
  resumed, because the resume note only exists on the second) and fails
  on any non-empty line that is neither inside a harness fence nor
  inside the packet. Mutation-tested — and the first version of that
  assertion missed the unfenced resume note precisely because it only
  rendered a first turn, which is why it now renders both.
- **The `--blocking` guard refused less than its own message promised.**
  It rejected an empty `--refs` while telling the writer that "a
  blocking question is resumable only if some request can be reached
  from its refs" — so a ref that resolved to some record but walked back
  to no request sailed through and produced the identical permanent dead
  end. That is also the likelier shape in practice: the writer is a
  model choosing its own ids, which gets one slightly wrong far more
  often than it omits the flag. The guard now runs the supplied refs
  through `_find_root_request`, the same walk `_resumable_answers` uses,
  and refuses when no request is reachable — testing what the message
  says and what the fold needs.

  §9's instruction to refuse "only when `--refs` is empty, not when it
  is non-empty but dangling" is therefore superseded, and the boundary
  against the deferred entry is unchanged by it:
  `docs/backlog/record-does-not-resolve-refs.md` is about *resolution*,
  for every type and every caller of `castle record`, and stays
  deferred. This is *reachability*, for this one flag. A ref that
  resolves perfectly and dead-ends is refused here and is still not that
  entry's business.
- **The fold and the packet renderer disagreed about what an answer
  is.** `render_continuation_packet` checks `provenance: requested` and
  `seat: intake` before calling a section the resident's words;
  `_resumable_answers` checked nothing, so any record of type `answer`
  bought a real worker turn — and the packet would then label a section
  "NOT filed through the resident's own intake path" on the very turn
  that record had paid for. The fold now applies the same test.

  Deliberately described as a filter and not a boundary, in the code
  comment as well as here: a writer passing those two fields satisfies
  it exactly. What it buys is that the *spend* half of the self-answer
  guard survives the case
  `docs/backlog/env-stripping-defeats-write-guards.md` describes, where
  a tenant clears `CASTLE_WORKER_CLAIM` and `write_record`'s refusal
  never fires — a mislabelled answer then still cannot quietly grant a
  worker turn. No existing fixture wrote answers through a non-intake
  path, so nothing asserted behaviour this now forbids; checked before
  adding it.

  It also surfaced a residual, filed rather than fixed:
  `file_answer`'s duplicate guard still counts *any* answer record, so a
  mislabelled one makes its question look closed to `castle answer` and
  to the modal's picker while buying no turn — leaving that question
  neither closable nor resumable
  (`docs/backlog/mislabelled-answer-strands-a-question.md`). Found by
  this task's own new test case, which originally assumed the resident
  could still answer such a question and could not.
- **The packet outgrew what a single kernel argument can hold, and the
  errand it happened to would have died permanently.** §7's
  "no truncation and no size limit, anywhere" is right, and it made
  `agent/castle-worker-claude`'s `exec claude -p "$prompt"` a time
  bomb: Linux caps one `argv` entry at `MAX_ARG_STRLEN` (32 pages,
  131072 bytes on a 4 KiB-page machine), which a human-typed request
  never approached and four or five turns of model-authored diffs do.
  Past the cap `exec` fails `E2BIG`, bash exits 126 printing only
  "Argument list too long", and the turn is recorded `outcome: failed`
  — with the answer already spent by that turn's claim, so §4's fold
  finds nothing to resume and the errand is finished for good, its
  journal blaming the tenant for a limit nobody wrote down.

  Fixed by opening the prompt file, unlinking it, and exec'ing with
  stdin on the surviving descriptor. `exec` is kept deliberately rather
  than replaced with a pipeline: it is what makes the tenant the same
  pid, in the same process group, that `run_worker_turn` captured at
  spawn — 0021's timeout kill and straggler sweep both depend on that —
  and it keeps the exit code the tenant's own with no `PIPESTATUS`
  handling. The privacy property the old comment protected comes out
  stronger, not weaker: the file is unlinked before the handoff as
  before, and the resident's verbatim words no longer sit in
  `/proc/<pid>/cmdline` for the length of the turn. `resume.sh` covers
  both halves — an errand whose first turn pads its account past the
  cap still resumes, and the shipped tenant itself is driven with a
  stub `claude` on `$PATH` and an oversized packet, which is the half
  that would actually have caught this, since nothing in `castle` ever
  used argv.
- **The harness's own instructions were unauthenticated by the rule the
  tenant is told to apply.** The nonce marked the packet's sections but
  not the prompt wrapped around them, and nothing marked where the
  packet ended — so a prior result body, quoted byte-for-byte, could
  reproduce `THE ONE RULE THAT OVERRIDES EVERYTHING ELSE` with MUST
  changed to MAY. A tenant tracking BEGIN/END state would be fine; a
  tenant reading linearly, which is a fair description of a model,
  meets two contradictory copies of the one rule that file exists to
  make unmissable. The script now reads the token out of the packet's
  preamble and prefixes its own headings with it, and closes the packet
  with `<token> END OF PACKET`. Asserted with both copies present in
  one rendered prompt: exactly one carries the token, and it is the
  harness's.
- **The claim's extra refs were explained only when there was history
  to narrate.** Gating the RESUMPTION paragraph on `continuing` — the
  previous pass's fix — left a first turn that spends an answer writing
  `refs: <request>,<answer>` under a body mentioning only a turn
  beginning: the unexplained-ref defect that paragraph exists to
  prevent, reopened in precisely the case the gate closes. Two
  sentences now, one gated on the spend (which answers this turn was
  given, and that naming them is what spends them) and one on history
  (that it is a resumption). Mutation-tested in both directions.
- **Two fixture bugs of a single shape, found by the oversized-packet
  case on its first run and recorded because the shape recurs**:
  `grep -m1` reading a piped-in packet exits at the first match while
  `printf` is still writing, `printf` takes SIGPIPE, and `set -o
  pipefail` reports 141 for a pipeline whose `grep` succeeded.
  Invisible below the 64 KiB pipe buffer and certain above it, which is
  the worst place for a bug to wait. Both fixtures now write the packet
  to a file and read that.
- **A prior turn's own body could forge the packet's section
  boundaries.** §7 specifies headings and says nothing about who may
  write something heading-shaped; the third review pass found that a
  `result` body — model-authored, and quoted byte-for-byte into the
  next turn's stdin — could contain a line reading "### The resident's
  answer, verbatim" followed by an instruction of its own. The prompt's
  own advice, that the heading above a passage says who wrote it, is
  what would have made it work, and it lands on the one path where this
  task's whole claim is that an answer closes a question and grants
  nothing. The same failure the provenance-keyed labels and the
  self-answer refusal each close, by a third door: not a record that
  lies, but a record forging the structure around itself.

  Closed with a per-turn nonce rather than by escaping: sections are
  delimited by lines carrying `CASTLE-PACKET-<16 hex>`, generated in
  the rendering process, stated in the packet's own preamble, and
  stored nowhere — so no record can contain it, because no record was
  written after it existed. Escaping the bodies was the alternative and
  would have undone the byte-for-byte rule the previous review pass
  established. `agent/castle-worker-claude` now tells the model to read
  the token from the preamble and treat everything between boundaries
  as quotation; both blocking fixtures do exactly that, reading the
  token rather than hardcoding a heading. `resume.sh` has a first turn
  that emits both a forged boundary and a forged markdown heading into
  its result, and asserts the resumed tenant counts one real
  resident-answer section while finding the forgeries present as
  quoted content. Mutation-tested: pinning the nonce to a constant the
  fixture can predict makes the count 2 and fails the run.
- **A first turn could announce itself as a resumption of a turn that
  never happened.** `resuming` was computed with no check that the
  errand had ever had one, so a blocking question filed and answered
  before anything ran produced a first claim carrying the RESUMPTION
  paragraph and a tenant told to "read the earlier account" that the
  packet did not contain — prose asserting what the record contradicts,
  the same defect class as the reaper's sentence. The spend stays
  unconditional (it is accounting, and it is what stops a later sweep
  starting a turn off that answer); only the narrative is gated on the
  errand having a prior `claim` or `result`, which also gates
  `CASTLE_RESUME_ANSWER_IDS`, since what that variable tells a tenant is
  that there is earlier work of its own to read. The divergence is
  commented at the gate, because it will look inconsistent otherwise.
- **A worker tenant could answer its own blocking question, and so
  grant itself unbounded automatic turns.** The most serious defect
  found in this task, caught by a second review pass over the tree.
  §5's own analysis is what missed it — it reasoned about a
  hand-planted duplicate answer and never about a tenant-authored one —
  so the correction is written into §5 itself rather than only here.
  Fixed by refusing `type == "answer"` in `write_record` whenever a
  claim id is in the environment, not by making tenant answers
  non-resuming: an answer that lands and merely fails to resume still
  retires a question the resident never saw, which is the Proposal 05
  violation and is worse than the spend loop. `castle-modal` learned to
  report `RecordError` on both of its answer paths, so a tenant that
  reached for that window meets the same sentence rather than a
  traceback — the policy stays in the one choke point; only the
  reporting is local. Covered in `resume.sh` by a tenant that tries
  both CLI doors and is refused at both, with the errand still at one
  turn after further sweeps, and then the resident's own answer
  resuming it normally.
- **An automatic turn that lost the fold-to-lease race would have run
  anyway.** §7 called that window "the same probe-then-act shape
  `lock_is_held` documents and accepts," which understated it: if a
  hand-run `castle work` took the lease and spent the answer in
  between, dispatch's recomputation came back empty and the turn
  proceeded as an ordinary non-resuming one — a real model call, a
  claim naming no answer, a packet resuming nothing, and a second
  automatic attempt on an errand whose single authorisation somebody
  else had already used. `run_worker_turn` now takes
  `require_resumable`, which `castle dispatch` passes for the one shape
  where resumption is the *only* thing that made the request eligible
  (it already carries a result), and raises `ResumptionLost` before
  writing anything if the answer is gone. Dispatch treats it as a skip,
  exactly like `LeaseHeld`. Hand-run behaviour is untouched by
  construction — `cmd_work` never passes the flag, so retrying a
  resulted errand with nothing to resume remains the deliberate
  unbounded escape hatch.
- **The packet emits every body byte-for-byte; the first
  implementation stripped them.** §7 says each record is rendered
  "verbatim — nothing paraphrased or summarised," and the first version
  wrote `body.strip()` at all four sites, which is a contradiction the
  word "verbatim" was already supposed to have closed. The cross-model
  review caught it, and the codebase makes the case stronger than the
  finding did: `parse_record` removes only the single blank line after
  the closing fence and carries a comment saying why — "so a body that
  starts with real whitespace-sensitive markdown (a code block) is not
  mangled" — so the parser was deliberately preserving exactly what the
  renderer then discarded. It costs most on this task's own path: a
  `result` body carries an embedded unified diff whose leading spaces
  are its meaning, and a resumed tenant reads that diff to work out
  what the earlier turn already did. It also silently changed first-turn
  behaviour, which used to hand a tenant an unmodified `request.body`.

  Fixed by making the separation the renderer's own rather than the
  body's: sections are assembled as chunks, and each writes its heading,
  a blank line, the body exactly as parsed, and then its own `\n\n`.
  A body ending mid-line and a body ending in three blank lines both
  leave the next heading at the start of its own line, with neither
  body edited to arrange it — deliberately not an `rstrip()`, which
  would have made the output tidy while still editing the record. Both
  halves are asserted: `resume.sh` files its first request through
  stdin with an indented first line and no trailing newline, and checks
  the indentation survives into the tenant's stdin; the fixtures
  themselves refuse the turn if a section heading is not a whole line
  of its own, which is the only way to see that the blank line came
  from the renderer rather than from whatever the body happened to end
  with. Both were mutation-tested — restoring the strip fails the
  first, removing the separator fails the second.
- **The answer heading is attributed off the record too, not only the
  request's.** The same function that took trouble to stop calling a
  system-initiated request the resident's words was still labelling
  every answer "The resident's answer, verbatim" with no check on who
  wrote it. Narrowed to near-nothing by the refusal above, but the
  asymmetry would have been wrong to leave in place: an answer carrying
  `provenance: requested` and `seat: intake` — what `file_answer`
  always writes, and the only path a resident's answer takes — keeps
  that heading; anything else gets one that names what the record
  actually says and claims nothing about its author.
- **Two more descriptions of the old stdin contract were corrected**:
  `agent/README.md`'s `castle-worker-claude` section, which still said
  the script "reads the request body on stdin" with no later
  correction — a stranger building a conforming tenant from that
  paragraph would have treated a resumed turn's prior results and the
  resident's answer as the request text — and
  `test/agent-loop/contract-worker.sh`, whose "the request said: …"
  line had been printing the packet's own first line into every result
  body it writes, including the VM's journal. No assertion depended on
  it, which is precisely why it could go on being wrong; the reference
  fixture for the contract now reports what it actually received.
- **Three comments describing behaviour this branch changed were
  corrected**, each of which also cited the backlog file this branch
  deletes: `file_answer`'s note that resumption "still defers" to it,
  `modules/agent`'s path-unit comment predicting that dispatch would
  one day need to notice an `answer` record (it does now, and the unit
  needed no change to allow it — worth saying, since that was the
  comment's own argument), and `dispatch-test.sh`'s section header for
  the non-behavior test, which is now the *narrowed* non-behavior. The
  0021 and 0022 briefs' references to the same file are historical and
  were left alone.
- **A stated limit was added to §4 and to `agent/README.md`, and it
  covers two shapes rather than one: neither a watermarked errand nor a
  tenant-filed one can resume.** Behaviour unchanged and
  deliberately so (the reasoning is in §4). Verified empirically rather
  than reasoned about: a pre-watermark request, hand-run until its
  tenant filed a blocking question, then answered, is untouched by two
  further sweeps — and a second `castle work <id>` resumes it, spends
  the answer in its claim, and delivers the packet, which is why the
  documented remedy is that command. The same sequence was then run
  against a `filed-during-turn` request, with the same result, before
  the second shape was documented alongside the first.
- **One cost this task adds is deferred rather than paid, and is filed
  rather than left in a review thread:
  `docs/backlog/eligibility-fold-rescans-per-request.md`.** §4's
  widened predicate calls `_resumable_answers` once per already-resulted
  request, and each call rescans every record, so the fold is now
  requests × records per sweep where it was linear. Measured at 117 ms
  for a synthetic 2000-record, 500-errand journal. Not optimized here,
  on this repo's own precedent (`docs/tasks/0021`'s refusal to add a
  concurrency knob before evidence of a bottleneck) and because
  `load_all` already re-parses every file each sweep, so this is not a
  uniquely new cliff. The entry carries the measurement, the method, and
  the shape of the fix.
