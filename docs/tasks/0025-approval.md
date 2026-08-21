# Task 0025 — The resident approves a proposal

**Before starting:** read `CLAUDE.md` in full; `docs/architecture.md`
(Records, Seats — especially Worker — and Proposals 03–06);
`docs/principles/01-open-by-construction.md` and
`02-the-resident-owns-the-configuration.md`;
`docs/backlog/authority-taxonomy-prior-art.md` in full — the Electric
Elves findings are load-bearing for this task's non-goals and its
"no timeout" decision; `agent/README.md` in full, especially "The
record format," "The claim record, and the `outcome` field," "Resuming
an errand, and the `blocking` field," and "Testing." Then, closely:
`agent/castle` — `file_answer`, `_write_worker_result`,
`run_worker_turn` (all of it, especially the tail after
`_write_worker_result` is called), `cmd_answer`, `cmd_record`,
`write_record`'s `WORKER_CLAIM_ENV` refusal, `cmd_validate`'s
`blocking`/`target`/`outcome` blocks, `FIELD_ORDER`, `AnswerRefused`.
Then `agent/castle-modal` in full — `_pending_questions`,
`_show_picker`, `run_answer`, `_errand_state`, `build_parser`. Then
`docs/tasks/0024-config-target.md` (skim; it produced the `target`
field and the two-checkout worker contract this task keys on) and
`modules/home/default.nix`'s `keybindings` and `window.commands`
blocks. Work on branch `sprint/0025-approval`, cut from `origin/main`
at `f7ebd32` — 0021 through 0024 are merged to `main`; this task rides
on top of them, not a stacked sibling branch.

## Why

Nothing today lets a resident authorize a specific proposed
configuration change and have that authorization mean something a
later task can act on. `castle work`/`castle dispatch` already produce
a `result` record carrying a unified diff and a `target` field
(`private` or `mechanism`, naming which checkout the diff is against —
docs/tasks/0024-config-target.md) whenever a worker turn finishes
cleanly with something to propose. That record sits in the journal,
notified or digested like any other result, and nothing distinguishes
"the resident has authorized this exact artifact" from "the resident
has not looked at it yet." Tasks 0026 (apply) and 0027 (activate) are
both explicit that they need such a signal to exist before they can
be written at all — `docs/architecture.md`'s worker contract already
promises them one: *"target: a role, not a path... 0025's approval
binding and 0026's applier will both need it against that exact
proposal."*

This task builds that signal: a resident-authored, mechanically
distinguishable, cold-readable **decision** — approve, reject, or
defer — bound to one exact, byte-identified proposal, reachable
without the resident ever typing or reading a record id, and honest on
its face that nothing on the machine changes yet. It does not apply
anything, activate anything, or decide who may skip this step. Those
are explicit non-goals below.

### Where this task starts from, and why it differs from the exhaustion pass

`/home/wesley/castle-sprint/exhaustion/0025-decisions.md` (referred to
below as "the decision pass") did a thorough NOW/CONTINGENT/stop-
condition exhaustion against this problem on 2026-08-17, one day
before 0021–0024 merged. Its reasoning is carried forward through this
brief wherever it still applies — its arguments for reusing `question`
+ `answer` rather than a new record type, for `defer` as an
attributable non-decision, for no timeout ever, for keeping this task
out of the decision-record business, and for the resident-facing
vocabulary rule are all adopted essentially as written, and this brief
cites them by their own labels (N1, N9, …) rather than re-deriving
them. Where the merged code changed the ground under a conclusion, this
brief says so explicitly rather than silently inheriting a stale
premise:

- **There is no proposal *question* today, and this task introduces
  one.** The decision pass wrote as if a `question` already existed
  asking "may I proceed" — verified against the merged code, it does
  not. A proposal exists only as a `result` record carrying a diff and
  a `target`, written once, by `_write_worker_result`, with no question
  attached. §"The design" below is this task's answer to that gap, and
  it is the single biggest way this brief's mechanism differs from the
  decision pass's assumed shape.
- **Answering a `--blocking` question resumes the errand — a
  `question` this task writes must be non-blocking, or approving
  silently re-runs the worker and produces a second, unauthorized
  proposal.** Confirmed by reading `_resumable_answers`,
  `_eligible_requests`, and `_errand_state`: resumption is keyed
  strictly on `_is_blocking(rec)`, so a question that never sets
  `blocking: true` cannot resume anything, by construction, with no
  runtime check required. This closes the decision pass's C3 finding
  (its highest-confidence risk) as a design property rather than a
  convention.
- **A question already closed by an ordinary, undecided answer is a
  permanent dead end for a proposal**, which the decision pass did not
  consider (it predates the mechanism that makes it possible). §"The
  design" adds a guard for it.
- **`_errand_state`'s per-question fold is already fixed.** The
  decision pass's V4/C9 named a bug where one answer anywhere silenced
  every pending question on an errand. Reading the merged
  `_errand_state`: `answered` is now a flat, journal-wide pass keyed by
  "does some answer's `refs` name this question," computed once and
  shared by every question in the fold — the bug is gone. Nothing in
  this task needs to touch it for that reason; it does need one small,
  additive change of its own (§"Errand state after a decision," below).
- **The answer-mode UI, the no-record-id-shown rule, `file_answer` as
  the shared write path, and the `castle-modal` picker are all merged,
  tested, and load-bearing** (docs/tasks/0022-answer-in-ui.md). This
  task extends that surface; it does not build a first one.

## The design

### Overview

1. A worker turn finishes with `outcome: completed`, a non-empty diff,
   and a resolved `target` — the existing gate `_write_worker_result`
   already computes (`stamped_target`). Immediately after that result
   is written, **the harness itself** — still inside `run_worker_turn`,
   never the tenant — writes a second record: a `question`, non-
   blocking, carrying no `fact`, whose `refs` are `[request.id,
   result.id]` and whose one new field, `proposal-sha256`, is the
   SHA-256 of the result record's own file bytes as just written.
2. That question is an ordinary `question` record in every other
   respect: it routes through `castle route` exactly like any other
   requested-provenance question, notifies the resident, and shows up
   in `castle-modal --mode answer`'s existing picker next to any
   ordinary elicited question, because nothing about the picker's fold
   cares what a question is *about*.
3. Picking it in the picker (or invoking a new `castle-modal --mode
   review [--question ID]` directly) does not drop into the ordinary
   free-text answer grammar. It renders the proposal — the harness's
   own boundary statement, the tenant's diagnosis (attributed), and
   the full diff, last, never truncated — and offers three distinct,
   labelled keys: approve, reject, defer. Any other key, including
   bare Enter, closes without deciding and writes nothing.
4. A decision is one `answer` record: `refs: <question-id>,<result-id>`,
   a new closed-vocabulary field `decision` (`approve` | `reject` |
   `defer`), and the same `proposal-sha256` re-verified against the
   result's *current* bytes at write time. It is written through
   `file_answer` — the one function every other resident-authored
   write in this system already goes through — extended, not
   replaced.
5. `castle record` refuses outright to write an `answer` carrying
   `--decision`, mirroring the existing `correction` refusal. Nothing
   downstream is applied, committed, or activated. The rendering
   states this in a sentence the tenant cannot write.

### A. Vocabulary: `DECISION_VALUES`, and identifying the exact proposal

New module-level constant in `agent/castle`, beside `OUTCOME_VALUES`
and `CHANNELS`, following the exact pattern those two already set:

```python
# The resident's decision on a proposed configuration change
# (docs/tasks/0025-approval.md). Written by a keypress on
# `castle-modal --mode review` or the `castle answer --decision` CLI
# flag, never parsed out of prose — the body still carries whatever
# the resident typed, verbatim, unparsed, and no authorization path
# ever consults it. `defer` is deliberately the third value: the
# attributable form of "not now," argued in the task brief's
# considered-and-rejected section against the alternative of two
# buttons.
DECISION_VALUES = ("approve", "reject", "defer")

# The field name a proposal's byte-hash is stamped under, on both the
# question that proposes it and the answer that decides it. Named for
# the algorithm, not `hash`, so a future migration to a different
# digest is legible in the field name itself rather than requiring a
# comment to disambiguate which hash a bare `hash:` ever meant
# (docs/tasks/0025-approval.md, following the decision pass's N3).
PROPOSAL_SHA256_FIELD = "proposal-sha256"
```

**Identifying the exact proposal is `refs`, not a `proposal:` field.**
The question's `refs` are `[request-id, result-id]` — the request
stays `refs[0]`, the lineage edge every existing walk
(`_find_root_request`, `_resumable_answers`, `_about_line`) already
follows through as many hops as the chain has, so this question is
attributed to its errand with no code change anywhere that reads
`refs[0]`. The result id is `refs[1]`, exactly the "first ref is
lineage, later refs are context" split `claim` and `result` records
already use for their own second ref. The answer mirrors it:
`refs: [question-id, result-id]` — `refs[0]` stays the lineage edge
`file_answer`'s duplicate-answer scan and every question-closure fold
already key on, `refs[1]` is the same result, carried forward as
context on the record that actually decides it.

*Alternative considered: a named `proposal:` field on both records,*
*as the decision pass's N3 recommended.* Rejected here because `refs`
already resolves, already validates (every `refs` entry must point at
an existing record, checked in `cmd_validate`'s ref-existence pass),
and already has an established two-slot convention this task's shape
fits exactly. A new field would duplicate what `refs[1]` already says,
for no reader anywhere that does not already walk `refs`.

**The hash.** SHA-256 over the exact bytes of the result record's file
as read from disk — no canonicalization, no field selection — computed
once by the harness right after `_write_worker_result` returns (so it
is hashing the file it just wrote, not a reconstruction), and
independently re-derived, never trusted from memory, by `file_answer`
at write time (§C) and by `castle-modal`'s review renderer at display
time (§G). Field ordering in `render_record` is stable and records are
never rewritten, so byte-hashing needs no normalization rules to get
wrong. This buys tamper-evidence, not more: under append-only
semantics the id alone already identifies the proposal, and the honest
argument for the hash (following the decision pass's N3 and N17.5) is
that it converts "this journal is append-only in spirit" into
something a machine can actually check, at the one moment — 0026's
future apply step reading bytes out of this record to mutate a
configuration — where a silent, unnoticed change would have a real
consequence.

### B. The harness writes the proposal question, never the tenant

In `run_worker_turn`, immediately after the existing call

```python
result_id = _write_worker_result(
    request, outcome=outcome, body_lines=body_lines,
    claim_id=claim_id, target=stamped_target,
)
```

(today this call's return value is passed straight to the function's
own `return`; it needs to be captured in a local first), if
`stamped_target` is non-empty — the same condition
`_write_worker_result` already required to record a `target` at all,
i.e. a completed turn with a real, routable diff — the harness reads
the just-written result file's bytes, hashes them, and writes a
`question`:

```python
result_bytes = (journal_dir() / f"{result_id}.md").read_bytes()
proposal_hash = hashlib.sha256(result_bytes).hexdigest()
try:
    write_record(
        journal_dir(),
        type="question",
        provenance=request.fields.get("provenance", "requested"),
        seat="worker",
        refs=[request.id, result_id],
        body=PROPOSAL_QUESTION_BODY.format(target=stamped_target),
        extra={PROPOSAL_SHA256_FIELD: proposal_hash},
    )
except OSError as exc:
    print(
        f"castle work: result {result_id} was written, but its proposal "
        f"question could not be filed ({exc}). The diff is durable in the "
        "journal; nothing will prompt you to review it until this is "
        "investigated.",
        file=sys.stderr,
    )
```

`PROPOSAL_QUESTION_BODY` is a module-level constant, one short,
harness-authored sentence — never tenant prose, never model-generated
— e.g. *"This errand produced a proposed change to your {target}
configuration. Nothing has been applied. Review it to approve, reject,
or set it aside."* It is what the picker's first-line preview shows,
which is also what makes a proposal question visually distinct from an
ordinary elicited one in that list with no extra code: an ordinary
question's body is the worker's or the resident's own words; this
one's is always this one sentence.

**Why not `write_record` directly with no failure handling, and why
not raise.** The result is already durable by the time this runs — the
turn's actual, hard-won output. A failure writing the *second* record
(disk full, permissions) must not look like the whole turn failed, and
must not throw away the result to satisfy some rollback fantasy an
append-only journal was never designed to support. This mirrors
`file_answer`'s own handling of a resident-model write failure after
its answer record is already durable — print, don't raise, and say
plainly what is and is not lost.

**Why `seat: worker`, not a new seat.** The claim record and the result
record for this same turn are both `seat: worker` already, written by
the harness rather than the tenant, per Proposal 03's own framing: a
seat is defined by what it reads and writes, not by whether a human,
a rule, or a model produced this particular record. The proposal
question is exactly that shape — a mechanical observation the harness
makes about its own completed turn — so it takes the same seat.

**Never `blocking: true`.** This question is never passed
`--blocking` and the harness never sets `BLOCKING_FIELD`. This is
what closes the decision pass's C3 finding: `_resumable_answers`'s
`blocking_questions` list is built by filtering on `_is_blocking(rec)`
alone, so a question that never carries that field can never enter it,
so no answer to it can ever spend against `_eligible_requests`'s
resumption clause. Approving, rejecting, or deferring this question
therefore never starts another worker turn, never produces a second
proposal, and needs no runtime guard beyond simply never writing the
field — the guarantee is structural, not policed.

**Never `fact`.** The harness never passes `--fact` and the constant
body carries no elicitation. This closes the decision pass's N4/V2
directly: `file_answer`'s existing rule (`resolved_fact = fact or
question.fields.get("fact")`) can only ever see `None` for a proposal
question, so no approve or reject can write a resident-model entry
through the existing path. §C adds a second, defensive check for the
case where a hand-written or corrupted question smuggles a `fact` in
anyway.

*Alternative considered: the tenant files its own proposal question,*
*as `agent/castle-worker-claude` item 4 already instructs it to file*
*a mid-errand question.* Rejected. A model asked to honour "never
blocking, never carrying a fact" is a convention, and this is the
first mechanism that grants Castle's proposals standing to be acted
on later (0026) — the two properties above have to be guarantees, not
requests a well-behaved tenant happens to satisfy. `write_record`
already refuses an `answer` or `correction` from inside a worker turn
for exactly this reason (Proposal 05); the same posture belongs here.
A tenant also cannot compute the byte-hash of its own result record
before that record exists — the hash necessarily comes after the
write, which only the harness can sequence correctly. And a tenant-
authored boundary statement was already rejected on separate grounds
in §G (N7): the same actor should not both write the proposal and
attest to what it does and does not authorize.

### C. `file_answer` extended: `decision`, staleness, and the two guards

`file_answer`'s signature grows one new keyword-only parameter:

```python
def file_answer(
    *, question_id: str, body: str, fact: str | None = None,
    decision: str | None = None,
) -> tuple[str, str | None]:
```

Every existing check runs unchanged and first (empty body — see below
for the one exception — question resolves and is type `question`, not
already answered). Then, only when `decision is not None`:

1. **The empty-body refusal is skipped.** A decision is a complete,
   meaningful answer on its own; demanding prose in addition would
   train a resident to type "ok" before every approval, which is
   exactly the habituation Proposal 06 and Akhawe & Felt (cited there)
   warn against. `body` is still stored, verbatim, whatever the
   resident typed or left empty.
2. **The question must carry `proposal-sha256`.** If not, this is not
   a question this mechanism ever proposed, and `--decision` on it is
   refused (`AnswerRefused("not_a_proposal", ...)`) — a decision can
   only ever be about a change the harness itself filed.
3. **No `fact` may reach the resident-model path.** Defense in depth
   against N4/V2 beyond "the harness never writes one": if some other
   writer ever produces a `question` carrying both `proposal-sha256`
   and `fact` — hand-written, restored, a future bug — this refuses
   rather than silently laundering an approval into a resident-model
   write (`AnswerRefused("proposal_carries_fact", ...)`).

   **Corrected during implementation.** This item originally said the
   check was on the question's own field alone, on the grounds that
   `file_answer`'s `resolved_fact = fact or question.fields.get("fact")`
   "can only ever see `None` for a proposal question." That is false:
   the `fact` *parameter* is supplied from the command line by
   `castle answer --fact NAME`, so `--fact NAME --decision approve`
   would have walked straight past a question-field-only check and
   written exactly the resident-model entry this guard exists to
   prevent — the likelier of the two routes, and the only one
   reachable without a corrupted journal. The implemented check tests
   the whole expression the resident-model path computes,
   `fact or question.fields.get("fact")`, so both doors close. Both
   are covered in `test/agent-loop/approval.sh`.
4. **The referenced result must resolve.** `question.refs[1]` must
   exist and be `type: result` (`AnswerRefused("proposal_unresolvable",
   ...)`) — the proposal this decision would bind to has to actually
   be there to bind to.
5. **The hash must still match.** Read `question.refs[1]`'s file bytes
   fresh from disk, right now, and compare their SHA-256 to the
   question's own stamped `proposal-sha256` — not to anything the
   caller passed in, because the question's own field is the one
   value nothing after proposal time can have legitimately changed. A
   mismatch means the file was altered since the proposal was filed —
   hand-edited or corrupted, since nothing in this system rewrites a
   record — and this refuses (`AnswerRefused("proposal_stale", ...)`)
   rather than guessing which version is authoritative. This is what
   makes the whole check work with **no state held across processes**
   (the decision pass's N13): a crash or a closed window between
   display and response leaves nothing in memory that mattered,
   because both "at display" and "at response" independently re-derive
   the same comparison from disk.
6. On success, the write gains `refs=[question_id, refs[1] of the
   question]` (not just `[question_id]`) and
   `extra={"decision": decision, PROPOSAL_SHA256_FIELD: <the hash that
   just matched>}`.

**A sixth guard, found while designing this, not in the decision
pass:** an *ordinary*, non-decision answer against a proposal question
must be refused too. Without this, a script or a careless future
caller could close a proposal question with plain text and no
`decision` — `file_answer`'s pre-existing already-answered check would
then treat it as answered forever, with no decision ever recorded, a
silent permanent dead end for a proposal nobody rejected, approved, or
deferred. Added as check 2 above's mirror, run whenever
`decision is None`: if the target question carries `proposal-sha256`,
refuse (`AnswerRefused("proposal_needs_decision", ...)`) and name
`--mode review` (or `castle answer --decision`) as the way to close it.
This is the write-side half of the same discipline N12 asks for on the
read side (§H).

`AnswerRefused` gains the five new `kind` values above, following its
existing `kind`-discriminant shape exactly — no new exception classes,
one more spot in `_answer_refusal_message` (the CLI's wording, ids
freely named) and one more spot in `castle-modal`'s `_answer_refusal`
(plain language, no ids, matching the existing five).

### D. `castle answer --decision` — the CLI path exists too

`castle answer` gains `--decision {approve,reject,defer}`, wired
straight through to `file_answer`'s new parameter — the same shape
`--fact` already has. This is not optional polish: it is what lets
this whole mechanism be exercised, tested, and used by a resident with
no working display exactly the way every other write path in this
tool already can be, and it is what the headless test harness (§
Verification) drives for most of its cases, reserving the desktop-loop
VM for the one real end-to-end path.

Because `castle answer` is a single, non-interactive call, "display
time" and "response time" are the same instant — the CLI does not
hold anything across a human's reading pause, so `file_answer`'s own
internal re-derivation (§C.5) is the only staleness check that runs,
and it is sufficient: nothing between the CLI's own read of the
question and `file_answer`'s read of the result, microseconds apart in
one process, is going to legitimately change either file.

### E. `cmd_record` refuses `--decision` outright

`p_record` gains `--decision`, `choices=DECISION_VALUES`, `default=
None` — and `cmd_record` refuses immediately if it is set, mirroring
the existing `--type correction` refusal in shape and in the comment
explaining why:

```python
if getattr(args, "decision", None):
    print(
        "castle record: refusing to write an answer record carrying a "
        "decision field. Approving, rejecting, or deferring a proposal "
        "must go through `castle answer --decision` or castle-modal's "
        "review mode — the one path with the byte-hash and staleness "
        "checks an authorization requires (docs/tasks/0025-approval.md). "
        "`castle record` bypasses all of them.",
        file=sys.stderr,
    )
    return 1
```

This is the same "make the honest path the only easy path" posture
`cmd_record`'s correction refusal already states plainly for itself:
not a security boundary (a tenant running as the resident could still
write the file directly), but the difference between a decision made
through the one path that verifies what it is deciding and one that
does not. Stated once, honestly, rather than implied.

### F. `cmd_validate` — the new fields, well-formed-if-present, never required

Following the exact pattern `blocking`/`target`/`outcome` already
established (checked when present, never required, because the
journal is append-only and no pre-existing record could have carried
a field that did not exist yet):

- `decision`, if present, must be a member of `DECISION_VALUES`, **and
  the record's `type` must be `answer`** — a `decision` on any other
  type is a fabricated authorization and is rejected outright.
- `proposal-sha256`, if present, must be 64 lowercase hex characters,
  **and the record's `type` must be `question` or `answer`** — nothing
  reads it anywhere else, so a copy on any other type would validate,
  read as meaningful, and do nothing (the exact reasoning `blocking`'s
  and `target`'s own scoping checks already give).
- **A question carrying `proposal-sha256` must not also carry
  `fact`** — the permanent-schema-gate form of §C's guard 3, so the
  invariant does not depend solely on `file_answer` catching it at
  write time.
- **An answer carrying `decision` must carry `proposal-sha256`.**
- **An answer carrying `decision` must have at least two `refs`
  entries, and the second must resolve to a record of type
  `result`.** This is the structural half of "identify the proposal by
  refs, not a field" (§A): if refs is going to carry the meaning a
  `proposal:` field would have carried, the validator has to check the
  shape refs is now responsible for, exactly as the decision pass's
  V13 warns ("existing refs provide a complete cold-readable
  authorization chain" is true for *existence*, not *shape*, until
  something checks the shape).
- **At most one `answer` carrying `decision` per question id.**
  `file_answer`'s already-answered scan already prevents this at write
  time for its own callers, and `cmd_record` now refuses to write a
  decision-bearing answer at all — but the already-answered check is a
  scan-then-write race (documented honestly in `file_answer`'s own
  comment on why it is not a lock), so two concurrent `castle-modal
  --mode review` sessions can both pass the check before either
  writes. This is the validator's backstop for that narrow window, and
  it is stated as exactly that — a race the validator catches
  afterward, not one this task prevents from ever happening.

**Also, in scope, corrected in the same pass: `outcome` gains the type
scoping `blocking` and `target` already have.** Verified against the
merged code: `cmd_validate`'s `outcome` block checks membership in
`OUTCOME_VALUES` but never checks that the record carrying it is a
`result` — an `answer` record with `outcome: completed` writes, exits
0, and validates clean today. This is the exact asymmetry 0023 closed
for `blocking` and 0024 closed for `target`, and it survives on the
field that is `decision`'s closest structural precedent — the same
shape of "a closed-vocabulary, closed-scope, optional field on results
only" this task is about to add a second instance of. Leaving it open
invites a future reader copying the `blocking`/`target` pattern to
copy the one instance that forgot the scoping instead. The fix is one
line, added to the existing block:

```python
if outcome_raw is not None and rtype != "result":
    errors.append(
        f"{path.name}: 'outcome' is a result-record field and this is a "
        f"{rtype!r} record. Nothing reads it here, so it would validate, "
        "read as meaningful, and do nothing (docs/tasks/0021-auto-dispatch.md)."
    )
elif outcome_raw is not None and outcome_raw not in OUTCOME_VALUES:
    ...  # existing check, unchanged
```

### G. `castle-modal --mode review` — what the resident sees, and how they decide

**No new keybinding.** The review surface is reached from the existing
`Mod4+Shift+a` answer picker: `_pending_questions` already folds every
unanswered `question` regardless of what it is about, so a proposal
question already appears in that list with no change to the fold
itself. What changes is what happens after it is picked.

In `run_answer`, after `question = _show_picker(...)` returns a
selection, branch on whether the picked question is a proposal
(`question.fields.get(castle.PROPOSAL_SHA256_FIELD)` is truthy). If
so, call a new `run_review_for(castle, question, out)` instead of
falling into the existing `.`-terminated free-text grammar. The
scripted (`--question ID`, non-interactive) path gets the identical
branch: `_run_answer_scripted` refuses with a plain message pointing
at `--mode review --question ID` if the named question turns out to be
a proposal, rather than silently writing an ordinary answer that
`file_answer`'s new guard 6 (§C) would refuse anyway — refusing early,
with the right pointer, is a better message than the generic one.

`--mode review` is a fourth top-level mode, parallel to
`compose`/`status`/`answer`: `castle-modal --mode review [--question
ID]`. Interactively with nothing named, it shows the oldest pending
proposal (reusing the same picker machinery, filtered to proposals
only, when more than one is pending — see "multiple pending" below);
non-interactively it requires `--question` and behaves like the other
modes' scripted paths.

**The window grows itself; no second `app_id`.** 720×480 (the fixed
size every `castle-modal` window opens at, `modules/home`'s
`window.commands`) cannot show a diff plus explanation (V10 in the
decision pass, confirmed: nothing about that geometry changed).
`run_review_for`, gated on `sys.stdin.isatty() and
sys.stdout.isatty()` — the same double-tty gate `_pause_for_dismissal`
already uses, for the identical reason: a piped caller has no window
to resize — shells out, best-effort and non-fatal, to resize itself:

```python
REVIEW_RESIZE_ARGV = [
    "swaymsg",
    '[app_id="castle-modal"] resize set 1100 760, move position center',
]


def _resize_for_review() -> None:
    if not (sys.stdin.isatty() and sys.stdout.isatty()):
        return
    raw = os.environ.get(REVIEW_RESIZE_ENV)
    if raw is None:
        argv = list(REVIEW_RESIZE_ARGV)
    elif not raw.strip():
        return
    else:
        argv = shlex.split(raw)          # ... guarded, see the code
    try:
        subprocess.run(
            argv, check=False, timeout=5,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.SubprocessError):
        pass
```

**Corrected during implementation.** An earlier draft of this snippet
made the environment variable the *argument to `swaymsg`* rather than
the whole command line — which contradicted this brief's own
verification plan two sections down, where the test is specified as
pointing `CASTLE_REVIEW_RESIZE_COMMAND` at a stub script. A variable
that can only ever be a swaymsg argument cannot be pointed at a stub
without also stubbing `swaymsg` on `$PATH`, so the test as specified
could not have been written. The implemented form is
`_fire_notification`'s idiom properly: the variable is a whole command
line, `shlex.split` like `CASTLE_NOTIFY_COMMAND`, and the *default* is
a literal argv rather than a string to be split, so the criteria's
quoting reaches swaymsg exactly as written instead of surviving a
shlex round-trip.

**Scoped by `app_id` criteria, not "whatever Sway has focused right
now."** An earlier version of this design used a bare `resize set …`
with no criteria, reasoning that the window was "already focused,
since a keypress just landed in it." That is true at the instant of
the keypress and not a moment later — a workspace switch, a focus-
stealing window, or a resident who alt-tabbed while reading the
proposal leaves a focus-relative command resizing and re-centring
whatever the resident switched *to*, silently, from a tool whose whole
subject is not acting without permission. `swaymsg` takes criteria the
same way `modules/home`'s own `window.commands` does
(`[app_id="castle-modal"] resize set …`), which targets the modal
specifically, whatever is focused. **Known, accepted edge case:** if a
resident has two `castle-modal` windows open at once (two keybinding
presses, or a review left open while another compose window is
opened), the criteria matches both, and both resize. Harmless —
neither window's *content* changes, only its geometry — and not worth
the heavier fix (capturing this window's own container id from
`swaymsg -t get_tree` at entry and targeting `[con_id=N]` instead), so
this brief accepts it rather than building the more precise version.

This mirrors `_fire_notification`'s exact idiom in `agent/castle`:
best-effort, environment-overridable, silent on failure — a host with
no Sway, no `swaymsg`, or a resident on some other compositor gets a
harmless failed exec and a review that still works at whatever size
the window already is. `CASTLE_REVIEW_RESIZE_COMMAND=""` opts out
explicitly, the same "empty string means don't even try" convention
`CASTLE_NOTIFY_COMMAND` already has.

**What actually keeps this inert in CI, stated precisely rather than
assumed.** The double-tty gate excludes every *non-interactive* test
case (the piped `--question ID` scripted path) — those never attempt
the shell-out at all, full stop. It does **not** exclude the
*interactive* pty-driven test cases (approve/reject/defer/dismiss),
because `test/agent-loop/modal-headless-test.sh`'s existing pty
driver (`pty.openpty()`, the same pattern `_show_picker`'s cbreak
tests already use) genuinely puts a tty on both ends to exercise the
real interactive code path — `sys.stdin.isatty()` and
`sys.stdout.isatty()` are both true there, on purpose, and the resize
call does fire. What makes that safe is the criteria scoping just
added: the pty test's own controlling terminal is never a real
`foot --app-id=castle-modal` window (nothing in the test opens `foot`
at all), so on a developer's machine that actually runs Sway and has
`swaymsg` on `$PATH`, the criteria matches zero windows and the
command no-ops — it does **not** fall through to resizing the
developer's own terminal, which the unscoped version would have done.
On the GitHub-hosted CI runner, `swaymsg` is not installed at all (no
`modules/dev`, no Sway, per this job's existing stock-runner
reasoning), so the call fails with `FileNotFoundError` and is
swallowed the same way a missing `notify-send` already is. §Verification
adds a test that proves the call is *attempted* on the interactive
path (pointing `CASTLE_REVIEW_RESIZE_COMMAND` at a marker script and
asserting the marker was written) and a second proving it is *not*
attempted on the non-interactive path (the same marker, asserted
absent) — this is what actually backs the claim in this paragraph,
rather than leaving it as prose nobody checks.

*Alternative considered: a second `app_id` (`castle-review`) with its*
*own `window.commands` entry, matching the decision pass's N14*
*recommendation.* This is a real, defensible design and the brief
records the deviation plainly: N14 reasoned from "no new chord," which
this design keeps, but assumed the size fix had to live in
`modules/home` as a second static geometry rule, which requires a
second `foot --app-id=castle-review` process to be spawned and handed
off to from inside the running modal, and a `window.commands` entry a
private layer's own Sway customization would need to know about.
Review mode runs *inside* a window that is already open and already
mapped — it is not launching a new one — so giving it a second
`app_id` means spawning a second process and handing off to it, not
just adding a Nix rule. Resizing the window that is already open
reaches the identical outcome — a bigger window for the review — with
a smaller diff (no `modules/home` change at all, no second process
spawn, no second app_id for a private layer's own window rules to
collide with), at the cost of one more best-effort, criteria-scoped
shell-out, which is a cost this codebase already accepts for
notifications. If review turns out to need Sway-level treatment that a
self-resize genuinely cannot provide — e.g. a private layer running a
tiling-only Sway config with floating disabled — `window.commands`
remains available as a fallback in a later task; this brief does not
close that door, it just does not open it before there is a reason
to.

**What is rendered, in order.** The decision pass's N20 asked for eight
sections in a specific order and, separately, argued the ordering
principle "evidence before reasoning, diff always available, never a
checklist." That principle is kept; the eight-way *section* breakdown
is not, because it assumes the tenant's stdout is structured into
parseable pieces ("current state," "what will be run to check it," "how
to reverse it," …), and nothing mandates that. Verified against
`agent/castle-worker-claude`'s actual prompt: the only instruction
about the tenant's account is "explain the reasoning on stdout" — no
required headings, and the record format's own constraint rules out
inventing a body-heading parser (`agent/README.md`: "nobody is putting
a paragraph of structured metadata in a frontmatter field… prose
belongs in the body," and nothing says the body's prose is structured
either). A parser built against headings the tenant was never told to
write would work today and break silently the first time a tenant
phrases its account differently — a false promise of structure. This
is the honest resolution of the decision pass's C5, which is
contingent exactly on this question and now settles: 0024 does not
mandate sections, so this task does not pretend one exists.

What survives, mechanically available without inventing any parsing:

1. **Where this applies.** The `target` role and the resolved path
   sentence `_write_worker_result` already writes into the result
   body verbatim (*"This diff targets the **private** checkout, which
   on this host resolved to `/path`."*) — quoted, not re-derived, since
   it is already exactly this fact in the harness's own words.
2. **The mechanism's boundary statement** — a module-level constant in
   `castle-modal`, printed identically on every review, never
   model-generated:

   > *Approving this records your authorization for this exact change.
   > **Nothing on this machine is edited, committed, or applied by
   > approving it** — no file changes, no `git commit`, no rebuild, no
   > new generation. That is true for every proposal shown here today.
   > Rejecting ends this proposal. Deferring leaves it exactly as it
   > is — nothing expires, and nothing decides on your behalf if you
   > never come back to it.*

   This is Proposal 06's "the system may grade its own delivery, never
   its own judgment" and the decision pass's N7 given code: the same
   actor that produced the diff does not get to assert what approving
   it does. It is also the direct fix for V9 — as of this task the
   honest answer to "does approving edit configuration or activate a
   generation" is *neither*, and the surface says so in the same
   breath as offering the keypress, not as a footnote.
3. **Castle's diagnosis.** The full result body's reasoning — the
   tenant's own stdout, quoted verbatim minus the target sentence
   above and minus the diff fence (shown next) — under a fixed,
   unmissable label: *"Castle's own account of why (its words, not
   verified by a person):"*. Printing it whole, unparsed, is the
   direct extension of docs/tasks/0010's "no seat paraphrases,"
   applied to a read rather than a write: summarizing it here would be
   exactly the paraphrase that rule forbids, one surface over.

   **Two more exclusions, added during implementation, both for the
   same reason as the target sentence: they are the *harness's* prose,
   not the tenant's account, so quoting them under a label that says
   "its words" misattributes them.** The first is `run_worker_turn`'s
   own opening line — *"Errand `<id>` completed by worker tenant
   `<command>`"* — which additionally carries the two things this
   surface may never print: a record id, and on a real host a
   `/nix/store` path nobody typed. The second is
   `WORKER_PROPOSES_NOTE`, whose content ("the worker proposes; it
   does not deploy") the boundary statement above now says in this
   surface's own words and without the internal vocabulary. Nothing
   tenant-authored is touched by either; both are matched against
   `agent/castle`'s own constants and shapes, never against a heading
   a tenant was never told to write.
4. **The diff, last, verbatim, never truncated.** Immediately before
   it, one line: *"Full diff below — scroll up in this window
   (Shift+Page Up in `foot`) if it runs past what's on screen."* This
   is the direct fix for V10/N14's other half: the window resize (item
   above) buys headroom, not a guarantee, and `foot` has real
   scrollback that nothing currently tells a resident exists. No
   pager is invoked — that would be new machinery (a `$PAGER`
   subprocess, its own failure modes, its own headless-incompatibility)
   to solve a problem `foot`'s own scrollback already solves for free;
   this task's job is to say so, not to build a second solution beside
   the one already installed.

No checklist, anywhere — the decision pass's N20 names this
explicitly (Hodges et al., cited in `docs/backlog/legible-history-
calibrated-trust.md`, on checklists inverting the expertise ordering)
and this design has nothing that could become one: four sections, no
checkboxes, no "reversible? y/n" summary line asserting a property
nothing here checked.

**The keypress contract.** Following the decision pass's N21: three
distinct, labelled, non-adjacent keys — `[a]pprove`, `[r]eject`,
`[d]efer` — printed in that order beside the boundary statement, not
beside the diff. Any other key, including bare Enter, closes the
window without deciding (dismissal — §H) and writes nothing, using
`_show_picker`'s existing cbreak-before-print discipline verbatim (the
same reasoning: a keypress in the gap between print and `tty.setcbreak`
is swallowed by the still-canonical line discipline and hangs the
read forever). On approve or reject, an optional one-line-or-more
comment is invited in the existing `.`-terminated grammar
(`_read_typed_body`) — genuinely optional this time, since `file_answer`
no longer refuses an empty body when a decision is present (§C.1). On
defer, no comment is invited at all: deferring is "not now," and
asking for a reason before letting the resident leave is exactly the
friction `defer` exists to avoid paying.

*Confirming keypress for approve, left open.* The decision pass's S8
names this a stop condition — a genuine ergonomics/safety trade between
Akhawe & Felt's click-through-habituation finding and this project's
stated posture against "confirmation prompts sprayed across the day" —
and defers it to the human. This brief keeps it open: a single,
distinct, never-Enter keypress per N21's recommended default, with no
second confirmation step. If the human wants one added, it is a
small, isolated change to this one function.

**Multiple pending proposals.** The picker already orders pending
questions deterministically, oldest-id-first (`_pending_questions`'s
existing sort) — a proposal question sorts into that same order with
no special casing. `run_review_for` decides exactly one proposal per
invocation and never batches a keypress across more than one, matching
N11/S8. After a decision (or a dismissal), if more proposals remain
pending, the surface says so in one line — *"N more proposed changes
are waiting — press Mod4+Shift+a again to see them."* — and exits,
rather than looping into the next one automatically: looping would be
exactly the "spray of decisions" this project's own posture (cited
just above) warns against, and re-opening the picker is one chord
away.

**A second proposal on one errand is left pending, never
auto-superseded.** Possible today only via a resident's own manual
`castle work <id>` retry after a decision (automatic resumption is
foreclosed — §B), so this is a known, low-frequency case rather than
a theoretical one, and it is handled correctly with zero new code: the
picker lists both proposal questions independently, oldest first, and
a decision on one never touches the other. What is deliberately not
built is a `supersedes` marker linking them — see Non-goals.

**Resident-facing vocabulary.** Following N22: the resident-facing
noun is **"a change"**, chosen once and stated here so a later surface
does not invent a third word (0022's chosen noun for a question stays
"a question" in that surface; this is the sibling choice for this
one). No record id, and none of `record`, `refs`, `seat`, `provenance`,
`journal`, `question`, `answer`, `proposal`, appears in anything this
mode prints to an interactive resident — the tenant's own prose and
the diff are shown verbatim and are not bound by this rule, exactly
as `castle-modal`'s existing doc comment already carves out for
question and request bodies. Confirmations: *"Approved."* /
*"Declined."* / *"Set aside — you can come back to it from the same
list later."* — nothing more, in either direction, matching
`castle-modal`'s existing bare `"Filed."` precedent.

### H. Errand state after a decision (N15)

`_errand_state` currently derives its label from the newest turn's
claim/result, then overlays `", waiting on you — press Mod4+Shift+a to
answer"` when an unanswered question exists in the errand's downstream
fold. A decided proposal clears the overlay (the fold already sees the
new answer), but the *base* label underneath is still the plain
outcome label — "done" — which is precisely the word N15 says must
never describe a rejected proposal.

Add, after the existing `waiting` computation and before the final
`if waiting: ... return`: find every proposal question in `downstream`
(`rec.type == "question" and rec.fields.get(castle.PROPOSAL_SHA256_FIELD)`),
take the newest by id, and check whether some answer in `records`
names it with a `decision` field. If one exists, its `decision` value
overrides `base` before the `waiting` overlay is considered (waiting
will be false for this question by construction once it is answered,
so the two paths never fight over the same line):

```python
"approve": "approved — nothing applied yet",
"reject":  "you declined this",
"defer":   "you set this aside",
```

(The keys are `DECISION_VALUES`, so the first one is `approve`; this
brief wrote `approved`, which would have matched nothing. `defer`'s
label reads "set this aside" rather than "deferred" so that the status
surface and the review surface's own confirmation use one word for one
act — the resident-facing vocabulary rule §G states, applied to itself.
An unrecognised value renders verbatim rather than collapsing into any
of the three, the same way `_outcome_label` treats an outcome from
outside its own vocabulary.)

`"approved — nothing applied yet"` is deliberately not `"approved"`
alone — the same discipline V9/§G.2's boundary statement states to the
resident at decision time, restated where the status surface would
otherwise let "approved" read as "handled." When 0026 exists and can
apply an approved proposal, this label is exactly the sentence that
task must come back and change — which is the point: it is wrong to
leave true by accident.

### I. The notification's first line

`_fire_notification` takes the first line of whatever body it is
handed. A `result` record's own first line is model-authored prose or,
worse, a store path (`agent/castle`'s existing routing renders "Errand
`<id>` completed by worker tenant `/nix/store/.../claude -p`" when a
result has no better first line) — exactly the internal-vocabulary
leak the decision pass's V5/N22 warn against, on the one surface bound
hardest by "no seat paraphrases, no internal vocabulary." This task's
proposal question controls its own first line by construction
(`PROPOSAL_QUESTION_BODY`, §B) and routes through the existing
`requested`-provenance path exactly like any other question, so the
notification a resident actually receives for a new proposal already
reads *"This errand produced a proposed change to your private
configuration. Nothing has been applied. Review it to approve,
reject, or set it aside."* with no code change to `_fire_notification`
or `cmd_route` — stated here as a fix earned for free by writing the
question the way §B specifies, not as separate work.

### J. `castle digest` learns to print `target`

`cmd_digest`'s errand fold currently never surfaces a result's
`target` field, even though this task makes `target` the field 0026
will route an apply step on. Cheap, in scope: one line added to the
result-rendering branch of the digest fold, printing `target: <role>`
when present, mirroring how `channel`/`evidence` are already surfaced
for decision records in the same fold. This is presentation only —
`castle validate` already checks the field's shape (§F); `digest` just
stops hiding it from a resident reading a period's account cold.

### K. Two comments already promise this task

`agent/castle` carries two comments (in `_write_worker_result`'s
target-stamping logic) that name `docs/tasks/0025` and state it "keys
on this field" (`target`) and reads it as "an applicable proposal."
Both are honoured exactly as written by this design: the harness-
written question is filed only when `stamped_target` is set (§B), and
the proposal's checkout comes from the *result's* `target` field,
never re-derived or re-guessed by this task's own code. No correction
needed to either comment; note this in the PR so a reviewer does not
go looking for a mismatch that is not there.

### L. No timeout, ever — and a backlog entry, not code

Adopted from the decision pass's N9 without escalation, because it is
a finding rather than a fork: **a pending proposal stays pending
indefinitely.** No expiry, no auto-cancel, no auto-approve, no re-ask
loop. Both Electric Elves catastrophe classes
(`docs/backlog/authority-taxonomy-prior-art.md`) come from a *rigid*
transfer of control in one direction or the other; Castle's config-
commit case is the regime where doing nothing is actually defensible
(wait cost ≈ 0, reversible by design, nobody else waiting on the
answer) — which is exactly why this posture must not be quietly
copied into a mail or meeting channel later without re-deriving
whether *that* regime's wait cost and response probability still make
"just wait" the right default.

The two cheap moves that do not transfer authority in either direction
are already built above: the status surface shows waiting is
happening (§G's "N more proposed changes are waiting" line, and
`_errand_state`'s existing overlay, both derived from data already in
the journal — no new field), and `defer` is the attributable non-
decision (§A, §G) that gives a resident a recorded way to say "not
now" instead of a dismissal nobody can distinguish from "never saw
it."

**File `docs/backlog/approval-channel-has-no-transfer-of-control-
strategy.md`** as part of this task's implementation (one plain-text
file, per `docs/backlog/README.md`'s convention) — content: the
Electric Elves finding above, the two catastrophe directions, and the
observation that the missing fourth move (change the coordination
constraints — de-escalate the channel, buy time, lower the stakes,
rather than either wait forever or hand control back) is router work,
not something an approval surface can do on its own. This is a filed
finding, not a solved problem — nothing in this task builds any part
of a transfer-of-control strategy.

### M. Principle 01: nothing new in the private layer

Following the decision pass's N16: this task adds no option to
`modules/agent/default.nix`, no private-layer slot, no way to
configure which changes need approval. The rule this task ships is a
**floor** — every configuration change with a target requires an
explicit, per-proposal decision — not a setting. `docs/private-layer.md`
already reserves the authority-taxonomy slot ("Format not yet
specified"); this task does not fill it, narrow it, or imply a shape
for it. A floor with no dial cannot be gamed and costs nothing to
widen later once there is evidence a dial is warranted — see Stop
conditions.

## Stop conditions — decisions this brief does not make

Carried forward from the decision pass's S1–S11, restated for this
task's actual shape rather than the assumed one:

- **Whether any change may ever bypass this approval, whether an
  approval may be standing/blanket/class-scoped, and whether approval
  history may calibrate future authority.** Untouched. Every proposal
  gets its own decision, forever, in this task's design.
- **Whether inaction, dismissal, or notification delivery may ever be
  read as consent.** No — §H.dismissal writes nothing, ever, and
  nothing times out into a decision.
- **Whether the private repo's standing made-then-reported commit
  authority extends to agent-authored configuration patches.** Not
  addressed and not implied: this task's boundary statement (§G.2)
  says plainly that approving commits nothing. Describing approval as
  "authorizing a commit" anywhere in code or docs would settle a
  question that belongs to 0026 and the human, not this task.
- **Whether approval records may feed the resident model, the audit's
  verdict corpus, or any learned policy.** No code here reads a
  `decision` into anything but the record itself and the one status
  label in §H.
- **The approve-confirmation-step and multi-select ergonomics trade**
  (S8). A default is implemented (§G); the human may override it.
- **Whether Castle may ever propose changes to the public framework
  repo through this same path.** Out of scope; nothing here
  distinguishes `target: mechanism` proposals from `target: private`
  ones except which checkout the result names — that symmetry already
  existed in 0024 and this task does not add or remove it.
- **Any change to `CLAUDE.md`.** None made.

## Considered and rejected

- **A new `approval` record type**, instead of extending `question`/
  `answer`. Rejected for the reasons the decision pass's N1 already
  gives at length: lineage, immutability, authorship, and routing all
  already work for `question`/`answer`; the one genuine gap — no
  mechanical way to distinguish an approval from a sentence containing
  "yes" — is a field problem, not a type problem, and a new type would
  ripple into `RECORD_TYPES`, `cmd_route`'s `to_route` tuple, `cmd_digest`,
  and `agent/README.md`'s record vocabulary for no benefit a field
  addition does not already buy. Also, a new type is exactly the "new
  authority vocabulary" both Codex's own review-prompt history and
  `docs/backlog/authority-taxonomy-prior-art.md` warn against
  introducing casually.
- **Two outcomes (approve/reject) instead of three.** Rejected —
  `defer` earns its cost on the Electric Elves laundering finding
  (`docs/backlog/authority-taxonomy-prior-art.md`: residents "routed
  decisions into the autonomous tier so refusals would be attributed
  to the agent," discovered only after the project ended). Without
  `defer`, a resident who is not ready to decide either has to reject
  something they might actually want, or leave it pending with no
  recorded signal that they looked and chose to wait — indistinguishable
  from having never opened the window at all.
- **A `proposal:` named field**, instead of the second `refs` entry.
  Covered in §A.
- **The tenant files its own proposal question.** Covered in §B.
- **A dedicated `castle-review` app_id and window geometry entry in
  `modules/home`.** Covered in §G; this brief deviates from the
  decision pass's N14 here and states why.
- **Parsing the tenant's stdout into N20's five prose sections**
  (current state, proposed state, what will be run to check it, how to
  reverse it). Covered in §G; rejected because 0024 mandates no such
  structure and the record format's own philosophy rules out
  inventing one.
- **A confirming second keypress before approve takes effect.** Left
  as an open, human-decidable question per S8 rather than decided here
  either way; §G implements the single-keypress default and names the
  alternative.
- **Writing a `decision`-shaped `decision` *record*** (the type, not
  the field) to log "this was shown to the resident." Rejected per the
  decision pass's N19: a "shown" decision record is a receipt wearing
  a judgment's clothes, every `decision` record requires non-empty
  `evidence`, and Proposal 06's `falsifier` field is documented but
  unimplemented (`cmd_validate` never checks it) — this task stays out
  of the decision-record business entirely rather than inheriting an
  obligation Proposal 06 has not built the teeth for yet.
- **A durable receipt for "dismissed" (viewed and walked away from).**
  Rejected per the decision pass's N8: dismissal writes nothing, ever.
  Proposal 06 names a receipt's observation window as something "the
  deciding record declared in advance," which nothing here does, and
  its own Sequencing section says receipt infrastructure "stays
  unbuilt until a delivery surface that can actually report reception
  exists" — this task is arguably that surface, and building the
  receipt half anyway would be answering a question (S4, adjacent) the
  brief does not have standing to answer. Named cost, stated rather
  than hidden: the journal cannot distinguish "shown four times and
  walked away from" from "never opened."
- **A `supersedes` field linking a second proposal on the same errand
  to the first.** Deferred — see Non-goals. Both proposals stay
  independently pending and reviewable with zero new code; the marker
  is a legibility nicety, not a correctness requirement, for a case
  this task's own design makes low-frequency (only a manual retry
  after a decision produces it).
- **A timeout, expiry, or any scheduled re-notification on a pending
  proposal.** Rejected outright — §L, and this is a stop condition
  (S3), not a judgment call this brief is free to make either way.
- **Piping the diff through `$PAGER`/`less` inside the review render.**
  Rejected in §G in favor of pointing at `foot`'s own scrollback: a
  subprocess pager is new machinery with its own failure modes (missing
  binary, a pager that eats the keypress this mode still needs to read
  afterward, headless-incompatibility) to solve a problem the terminal
  emulator already solves.

## Hard constraints, restated

- **Never write personal data into this repo.** Every id, path, and
  example in this brief and in the code it specifies is either a
  placeholder already used elsewhere in this repo or a literal record
  shape with invented content — nothing here names a real person,
  repository, or credential.
- **Principle 01 test.** Public mechanism only: the approval surface,
  the two new fields, the validator rules, the harness's write path.
  No new private-layer option, no new `modules/agent` surface — §M.
- **Principle 02.** No assertion, default, or evaluation-time check of
  a resident's filesystem is added by this task.
- **S1 (worker never evaluates the resident's flake).** Unchanged;
  this task never reads a private checkout's contents beyond the diff
  the worker already produced and embedded in the result body.
- **S2 (never edit `CLAUDE.md` without explicit approval).** No
  exception taken.
- **The worker still never deploys.** Nothing added by this task runs
  `nixos-rebuild`, `git commit`, or touches a running system or either
  checkout's working tree — approving a proposal records an
  authorization and nothing else, stated in the record's own rendering
  (§G.2) and proved in the verification plan.

## File-by-file change list

- **`agent/castle`**
  - New constants: `DECISION_VALUES`, `PROPOSAL_SHA256_FIELD`,
    `PROPOSAL_QUESTION_BODY`; `import hashlib` added to the existing
    import block.
  - `AnswerRefused`: five new `kind` values
    (`not_a_proposal`, `proposal_carries_fact`, `proposal_unresolvable`,
    `proposal_stale`, `proposal_needs_decision`).
  - `file_answer`: new `decision` parameter and the checks in §C.
  - `run_worker_turn`: capture `result_id`, write the proposal
    question when `stamped_target` is set (§B).
  - `cmd_answer` / `p_answer`: `--decision` flag (§D).
  - `cmd_record` / `p_record`: `--decision` flag and its refusal (§E).
  - `cmd_validate`: the new field checks, the cross-record checks, and
    the `outcome` type-scoping fix (§F).
  - `cmd_digest`: print `target` when present (§J).
  - `FIELD_ORDER`: `decision` and `proposal-sha256` added
    (presentation only).
  - `_answer_refusal_message`: five new branches.
- **`agent/castle-modal`**
  - `import os`, `import shlex`, `import subprocess` added.
  - New `--mode review` and its `--question` flag on `build_parser`.
  - `run_review_for` (new): rendering (§G), keypress contract,
    `_resize_for_review` (new).
  - `run_answer`: branch to `run_review_for` on a proposal selection;
    `_run_answer_scripted`: refuse a proposal id with a pointer to
    `--mode review`.
  - `_answer_refusal`: five new branches, plain language, no ids.
  - `_errand_state`: the decision-override addition (§H).
  - `main`: dispatch `--mode review`.
  - `_show_picker`: one new `action` parameter, defaulting to
    `"answer"`, which review mode passes as `"review"`. Not in this
    brief's original list and small, but not cosmetic: the picker is
    reused verbatim when more than one change is pending, and "press a
    number to answer" names the wrong act on a surface whose whole
    subject is keeping the resident exact about what they are doing.
- **`docs/backlog/approval-channel-has-no-transfer-of-control-
  strategy.md`** (new) — §L.
- **`agent/README.md`** — new subsections for the `decision`/
  `proposal-sha256` fields (mirroring the existing `target`/`blocking`
  write-ups), the `castle-modal --mode review` mode, and one line in
  the CLI usage block for `castle answer --decision`.
- **`test/agent-loop/approval.sh`** (new) — §Verification.
- **`test/agent-loop/modal-headless-test.sh`** — new `--mode review`
  cases (§Verification).
- **`.github/workflows/check.yml`** — one new step in the
  `dispatch-test` job running `test/agent-loop/approval.sh` (same job
  `config-target.sh` runs in, same git prerequisite).
- **`test/desktop-loop/test.nix`** — one end-to-end approve path
  (§Verification); the existing `dispatchWorker` fixture already
  produces a `target: private` completed result, so no new fixture
  worker is needed.
- **`docs/tasks/0025-approval.md`** — this brief, committed on this
  branch per the tasks convention.

### Files this brief did not list, and had to change anyway

Every one of these is a *premise* an existing harness stated that this
task made false. None is a relaxed assertion; each is the same claim
made against the shape the journal now has.

- **`test/agent-loop/config-target.sh`** contrasted "waiting on you"
  against `$REQ1` — a completed errand with a real diff and a resolved
  target — to prove the overlay is not satisfied by everything. Since
  §B that errand genuinely *is* waiting on the resident, and correctly
  says so. The contrast moved to the errand that completed and
  proposed nothing, and `$REQ1` gained the opposite assertion.
- **`test/agent-loop/dispatch-test.sh`** counted notifications in a
  window to prove a raced record was not notified twice. A targeted
  turn now produces two routable records and notifies twice by design,
  so the count is per record — once for the result, once for the
  change — asserted from both sides.
- **`test/agent-loop/pty-drive.py`** (new) is
  `modal-headless-test.sh`'s inline pty driver, extracted because
  `approval.sh` needed the same one. Two copies would be two places
  for a timing subtlety to be fixed once, and every subtlety in it was
  found the hard way. It gains a `run:` step, which is what lets a
  harness change a file while the program under test sits at a prompt
  — the "altered mid-review" case cannot be written without it.
- **`test/desktop-loop/test.nix`** needed more than "one end-to-end
  approve path." Three of its existing assertions `ls`'d a
  single-element glob and sliced the result as a path, which a second
  question per turn turns into a Python exception rather than a
  legible failure; its picker index was a literal `2` that now means a
  different record; and its "exactly two questions" assertion counted
  a category that has legitimately grown. All are now selected by
  `refs` shape or by the presence of the stamp, and the picker index
  is computed from the same pendingness fold the picker itself
  applies and asserted before it is pressed. Its `dispatchWorker`
  fixture also gains a one-second sleep, so that the question it files
  and the change the turn proposes sort in a knowable order — record
  ids carry a one-second timestamp and a random suffix, and a picker
  driven by pressing a number must mean the same thing on every run.

### Smaller decisions the implementation had to make

- **An out-of-vocabulary `decision` reaching `file_answer` raises
  `RecordError`, not a sixth `AnswerRefused` kind.** Both doors onto
  the parameter close the set already — argparse `choices=` on the
  CLI, a literal keypress map in the modal — so a value from outside
  it is a caller bug with no resident-facing wording to render. It is
  refused rather than written for the reason `cmd_record`'s `--target`
  guard already states: the validator rejects it, the journal is
  append-only, and a writer must not be able to produce a record its
  own validator condemns. `RecordError` because `main` already funnels
  write-path faults of that shape into one clean message and both
  castle-modal write paths already catch it.
- **`run_review`'s branch order mirrors answer mode's exactly**: a
  scripted caller naming a change goes straight to it whatever the
  fold says (0022's review-round-1 finding 2 — an empty fold is
  precisely when a script hits a documented refusal, and letting the
  friendly "nothing waiting" exit come first turns every one of them
  into exit 0 with prose), *then* the empty-fold line, *then* the
  refusal for a piped caller with changes pending and no `--question`.
- **An interactive review ignores `--question`**, which this brief did
  not state either way. Answer mode's rule and its reasoning apply
  unchanged, and the stakes are higher: a preselected guess here would
  be an authorization. With exactly one change pending there is
  nothing to choose between, so it is shown directly; with more, the
  picker.
- **cbreak is held across the whole render, not just the keypress.**
  §G says to reuse `_show_picker`'s cbreak-before-print discipline
  verbatim, and this is what that means for a render this long: both
  hazards the discipline exists for — a keypress swallowed by the
  still-canonical line discipline, and `tty.setcbreak`'s default
  TCSAFLUSH *discarding* what is already queued — have wide windows
  here rather than microscopic ones, because a resident reading a diff
  is exactly the person who presses a key before the program asks.
- **§G's vocabulary list is stricter than the merged code it extends.**
  It adds `question`, `answer` and `proposal` to answer mode's seven
  banned words, but `_answer_refusal`'s four pre-existing spellings
  already say "question" and "answered" on interactive paths. The five
  new refusals honour the fuller list; the four existing ones are left
  exactly as they are, since rewording load-bearing habit for no
  functional reason is what 0022 already declined to do.
- **`test/agent-loop/approval.sh` carries two proofs beyond the ones
  this brief specified**, both because the specified ones are
  structural where the risk is behavioural. After an approval it runs
  two full dispatch sweeps and requires that no further turn happened
  — asserting the *absence* of `blocking:` on the question record
  would not notice a future change that made answers to it resumable
  some other way. And one decision runs under a `$PATH` where
  `nixos-rebuild`, `switch-to-configuration`, `systemctl`, `sudo`,
  `git`, `nix` and `patch` are stubs that log their own invocation:
  nothing may be *reached for*, not merely nothing moved. A grep over
  the two source files was written first and deleted — both are full
  of those commands named in comments explaining why they are never
  run, which is exactly what a grep cannot tell apart from a call.

## Non-goals

- **Applying an approved proposal to a checkout** (0026) and
  **activating a new system generation** (0027). This task's own
  boundary statement (§G.2) says so to the resident directly.
- **A `supersedes` field or any other superseding mechanism** for a
  second proposal on one errand. Deferred — see Considered and
  rejected; both proposals remain independently reviewable today with
  no new field.
- **Any transfer-of-control strategy for an unanswered proposal.**
  Filed as a backlog entry (§L), not built.
- **Any private-layer configuration surface** for which changes need
  approval. §M; the rule is a floor, not a setting.
- **A confirming second keypress before approve, or any batch/
  approve-all interaction.** Open per S8; a single-keypress default is
  implemented and named as a default, not a final answer.
- **A durable receipt for dismissal, or any change to Proposal 06's
  receipt-window mechanism.** Not built; see Considered and rejected.
- **Any change to `agent/castle-worker-claude`'s prompt** — the
  worker's contract, and what it is told about its own output, is
  unchanged by this task. It already produces exactly what the
  harness needs (a completed result with a diff and a stamped
  `target`); nothing here asks it to write differently.
- **Any change to `_resumable_answers`, `_eligible_requests`, or the
  dispatch sweep's eligibility fold.** Unnecessary by construction —
  see §B's non-blocking argument — and this task does not touch any of
  the three functions.
- **Any change to `modules/home/default.nix`.** See §G's deviation
  from the decision pass's N14; no Sway module config changes.

## Verification plan

**`test/agent-loop/approval.sh`** (new, wired into the `dispatch-test`
CI job beside `config-target.sh`, whose fixture it reuses rather than
rebuilding: the same two real git checkouts under `$WORKDIR`
(`git archive`'d mechanism checkout, synthetic private checkout), the
same scoped `GIT_AUTHOR_*`/`GIT_COMMITTER_*` identity, and the same
`assert_checkouts_untouched` helper copied in and called after every
scenario below — the exact "nothing changed" proof this task needs,
already built and already proven correct). Drives `castle work`/
`castle dispatch` with `scripted-worker-config-target.sh` (or a small
variant of it) to produce a real `outcome: completed`, diffed,
targeted result, then exercises the approval layer through `castle
answer --decision` and `castle-modal --mode review --question ID`
(both write paths, per §D):

- A completed, targeted turn produces exactly one proposal question,
  non-blocking, no `fact`, correct `refs`, a `proposal-sha256` that
  matches an independently-computed SHA-256 of the result file's
  bytes.
- **Approve**: `castle answer --decision approve` succeeds, the answer
  record carries `decision: approve`, `refs: <question>,<result>`, and
  the same hash; `castle validate` passes; `assert_checkouts_untouched`
  after.
- **Reject**, **defer**: same shape, correct `decision` value, no
  resident-model entry written in either case (`resident-model.md`
  byte length unchanged — the same assertion 0022's test suite already
  uses for its own dismissal case).
- **Dismiss**: `castle-modal --mode review` driven on a pty with a key
  that is not `a`/`r`/`d` and not Enter — nothing written, the question
  still pending afterward, journal file count unchanged.
- **Stale**: hand-alter one byte of the result file after the
  proposal question is filed, then attempt `--decision approve` —
  refused with `proposal_stale`, nothing written.
- **Altered mid-review** (the "restart between display and response"
  case, and the decision pass's own honest reduction of it): a helper
  script mutates the result file's bytes between the picker showing
  the proposal and the pty's write-time keypress landing — the write
  is refused for the identical reason, proving the check re-derives
  from disk rather than trusting anything read at display time.
- **Multiple pending**: two completed, targeted turns on two different
  errands (or one errand retried by hand after a first decision, per
  §G's "second proposal on one errand" case) — both surface
  independently in the picker, deciding one leaves the other exactly
  as it was, oldest-first ordering holds.
- **`--fact` refusal**: hand-plant a proposal question that also
  carries `fact` (simulating corruption or a future bug) — `--decision`
  against it is refused with `proposal_carries_fact`.
- **Ordinary-answer refusal**: attempt an ordinary (no `--decision`)
  `castle answer` against a proposal question — refused with
  `proposal_needs_decision`.
- **`castle record` refusal**: `castle record --type answer --decision
  approve ...` refused, nothing written.
- **`castle validate` regression coverage**: every new field validates
  when well-formed; a hand-planted `decision` on a non-`answer` record,
  a `proposal-sha256` on a non-`question`/`answer` record, an `outcome`
  on a non-`result` record, a `decision`-bearing answer with no
  `proposal-sha256`, one whose second `refs` entry does not resolve to
  a `result`, and two `decision`-bearing answers against the same
  question, are all rejected with the errors named in §F.

**`test/agent-loop/modal-headless-test.sh`** additions, same pty
pattern the file already uses for answer mode: `--mode review`
rendering shows the boundary statement, the diagnosis attribution
label, and the diff, in that order, with no record id or internal
vocabulary word anywhere in the interactive output (the same positive
assertion 0022's suite already runs for answer mode); the picker marks
a proposal question distinctly from an ordinary one; selecting a
proposal from `--mode answer`'s picker branches into review rather
than the free-text grammar.

Two more, specifically backing §G's claim about `_resize_for_review`
rather than leaving it as unverified prose: point
`CASTLE_REVIEW_RESIZE_COMMAND` at a small stub (e.g. `sh -c 'echo hit
>>"$MARKER_FILE"'`, `$MARKER_FILE` an empty temp file the test
creates first) and drive `--mode review` on the pty driver through a
dismissal — assert the marker file is non-empty afterward, proving the
call really is attempted on the interactive path (the double-tty gate
does not, and is not claimed to, exclude it). Then run the identical
scenario through the non-interactive `--question ID` path with the
same marker armed — assert the marker file is still empty, proving
the double-tty gate does its actual job of excluding the piped
callers. Neither test needs `swaymsg` or Sway present; the stub
stands in for it, exactly as `CASTLE_NOTIFY_COMMAND` already lets
`run.sh` assert routing without a real notification daemon.

**`test/desktop-loop/test.nix`**: one end-to-end approve, through the
real compositor, since this harness is slow and carries one
representative path rather than the matrix. The existing
`dispatchWorker` fixture already produces a `target: private`
completed result (confirmed in the current test — `assert "target:
private" in result_record`), so this task's addition is: send
`Mod4+Shift+a`, assert the proposal question appears in the tree/
journal, send the key sequence to approve it, assert the resulting
answer record's fields, and assert — the same discipline
`config-target.sh` already applies — that neither checkout's working
tree nor `HEAD` changed and that no `nixos-rebuild`/`switch-to-
configuration` process ran.

**`nix flake check`** — this task adds no Nix option or module; run as
a regression check per `CLAUDE.md`'s standing rule.

**Genuinely needs human hands:** nothing beyond the standard
`/code-review` and `tools/codex-review.sh` passes this project already
requires before any PR. Every functional claim in this brief is
covered by one of the two automated harnesses above.

## Implementation prompt

You are implementing `docs/tasks/0025-approval.md` in the Castle
Turing repository, on branch `sprint/0025-approval` (already checked
out, carrying this brief — do not rewrite it silently; if
implementation surfaces a genuine deviation, correct this brief in the
same PR and say so prominently, per `CLAUDE.md`'s rule that a brief
the work overtakes gets corrected in place).

Read, in order: `CLAUDE.md`, `docs/architecture.md`'s Records/Seats/
Proposal 03–06 sections, `agent/README.md` in full, then this brief in
full. Then read the actual code this brief specifies changes against
— `agent/castle`'s `file_answer`, `_write_worker_result`,
`run_worker_turn`, `cmd_record`, `cmd_answer`, `cmd_validate`,
`write_record`, `AnswerRefused`, `FIELD_ORDER`, and `agent/castle-modal`
in full — before writing anything, since this brief cites exact
function names and existing patterns you need to match precisely
(mirror `blocking`'s and `target`'s validator scoping shape exactly;
mirror the `correction` refusal's shape in `cmd_record`; mirror
`_fire_notification`'s best-effort-subprocess idiom for the window
resize).

Implement in this order, each step leaving the journal format and
existing tests unbroken:

1. `agent/castle`: the new constants, `AnswerRefused`'s new kinds,
   `file_answer`'s extension (§C), `run_worker_turn`'s proposal-question
   write (§B), `cmd_answer`/`cmd_record`'s new flags (§D, §E),
   `cmd_validate`'s new and corrected checks (§F), `cmd_digest`'s
   `target` line (§J), `FIELD_ORDER`.
2. Run `test/agent-loop/run.sh`, `test/agent-loop/dispatch-test.sh`,
   `test/agent-loop/resume.sh`, and `test/agent-loop/config-target.sh`
   to confirm nothing existing regressed before writing anything new.
3. `agent/castle-modal`: `--mode review`, `run_review_for`,
   `_resize_for_review`, the `run_answer`/`_run_answer_scripted`
   branches, `_errand_state`'s decision override, the new
   `_answer_refusal` branches.
4. `test/agent-loop/approval.sh`, reusing `config-target.sh`'s fixture
   pattern (§Verification) — write this against the real code, not
   against this brief's prose, and if a described behavior does not
   match what you implemented, fix the code or fix the brief, but do
   not let the two silently diverge.
5. `test/agent-loop/modal-headless-test.sh` additions.
6. `docs/backlog/approval-channel-has-no-transfer-of-control-
   strategy.md`.
7. `agent/README.md` updates.
8. `.github/workflows/check.yml`'s new step.
9. `test/desktop-loop/test.nix`'s end-to-end addition — build and run
   the VM test locally if the environment supports it; if not, say so
   explicitly in the PR rather than claiming coverage you did not run.
10. `nix flake check`.

Before opening a PR: run `/code-review` on the branch and address its
findings, then `tools/codex-review.sh` for the second opinion, and
post Codex's findings verbatim per `CLAUDE.md`'s rule — do not
summarize or filter them. Scope both against `origin/main`
(`git fetch` first), not a local ref. The human makes the merge
decision; this brief's job ends at a green, reviewed PR with every
verification-plan item actually run and its output checked, not
assumed.
