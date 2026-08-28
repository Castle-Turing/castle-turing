# agent/ — the agent layer's tooling

This directory holds the mechanism for the agent layer described in
`docs/architecture.md`: a plain-text record format, a journal those
records live in, a small CLI (`castle`) that plays intake, router,
worker-invoker, digest, and validator over them, a modal intake surface
(`castle-modal`), and the default worker tenant
(`castle-worker-claude`). Read `docs/architecture.md` first — this file
documents the concrete formats and the tooling; the architecture doc
explains why they're shaped this way.
`docs/tasks/0008-agent-layer-skeleton.md` built the record schema, the
CLI's ask/answer/record/route/digest/validate/show core, and the
journal/spool split. `docs/tasks/0009-ambient-intake.md` added the
modal intake, the worker seat's real tenant (`castle work`), the
router's `notify` channel, and the resident-model write path
(`castle answer --fact`). `docs/tasks/0021-auto-dispatch.md` added
`castle dispatch` — the sweep that lets a filed errand start itself —
along with the per-request lease, the `claim` record, and the
`outcome` field on results.

Nothing here is a model, and nothing here decides anything a human
couldn't decide by hand-writing the same record with a text editor.
Per Proposal 03 in the architecture doc, a **seat** is defined entirely
by the records it reads and writes — `castle`'s subcommands are just
the hands a seat uses, not the judgment. `castle route`'s "router"
logic is nine lines of provenance comparison, not a model call: replace
it with a smarter tenant later and every artifact it produces still has
to be a `decision` record with the same required fields, because that's
the actual contract.

## The `castle` CLI

Standard library Python 3 only — no PyYAML, no third-party dependency
of any kind. That's a deliberate constraint (`docs/tasks/0008`), not an
oversight: this tool needs nothing installed beyond a python3 binary to
keep working in ten years, on somebody else's machine, in a CI runner,
or piped through by a shell script pretending to be a worker. It's one
file, `agent/castle`, meant to be read top to bottom.

```
castle ask [--provenance requested|initiated] [--refs id,id] TEXT...
castle answer QUESTION_ID [--fact NAME] [--decision approve|reject|defer] TEXT...
castle correct [--refs id,id] TEXT...
castle record --type T --provenance P --seat S [--refs id,id] [--evidence TEXT] [--fact NAME] [--outcome VALUE] [--target private|mechanism] [--blocking] [--body TEXT | --body-file PATH] [--spool]
castle route
castle work REQUEST_ID
castle dispatch
castle digest [--since TIMESTAMP]
castle validate [--journal DIR]
castle show ID
```

- **`ask`** — the intake seat. Writes a `request` record with
  `seat: intake`. Provenance defaults to `requested`, since a human
  typing at this CLI is definitionally the resident asking directly;
  pass `--provenance initiated` for a script filing something on the
  system's own initiative (e.g. a future cron-triggered mail sweep).
  `castle-modal`'s compose mode (below) is the same seat through a
  different surface — both end up calling the same `write_record`.
- **`answer`** — also intake: the resident's word answering a
  previously-filed `question` record, entering the system the same way
  a request does. Also the resident model's only *elicited* write path
  (Proposal 05, `docs/tasks/0009`): if the question record carries a
  `fact` field (or one is passed with `--fact`), answering it appends
  an entry to `resident-model.md` alongside the journal `answer`
  record — see "The resident model" below. Both the record and that
  entry are written by `file_answer()` in `agent/castle`, which this
  subcommand and `castle-modal`'s answer mode both call rather than
  each performing the write in their own words
  (`docs/tasks/0022-answer-in-ui.md`; the same shape `file_correction()`
  already has). It owns every pre-write check, including one that is
  new: **a question already closed by an answer is refused**, rather
  than silently gaining a second `answer` record naming it. Two answers
  on one question make "is this still open" unanswerable for every
  later reader, and the refusal names the existing answer's id so the
  first one is easy to find. Answering a question the worker marked
  **blocking** also resumes its errand: the next `castle dispatch`
  sweep gives that request one more worker turn, automatically, exactly
  once (`docs/tasks/0023-resume-cold.md`, and "Resuming an errand"
  below). An answered *non*-blocking question resumes nothing, which is
  the common shape. The cost, stated plainly: an answer cannot be
  revised or superseded — a resident who answered wrongly can file a
  `correction` referencing it, which preserves the account, but nothing
  reopens the question and the resident-model entry it elicited stands
  as written; amendment semantics on an append-only log are
  deliberately left to a future task rather than improvised here
  (`docs/backlog/answer-amendment-semantics.md`). Since a blocking
  answer starts real work within seconds of landing, there is no window
  in which a wrong one could be taken back: the remedy is a new
  request, not an undo.
  `--decision approve|reject|defer` is the other thing an answer can
  be, since `docs/tasks/0025-approval.md`: the resident's verdict on a
  **proposed configuration change**. Valid only against a question the
  harness itself filed to propose one (see "Proposing a change, and
  deciding it," below), and refused on anything else. The body is
  optional here and only here — a decision is a complete answer on its
  own, and demanding prose beside it would train a resident to type
  "ok" before every approval. Whatever they do type is stored
  verbatim, unparsed, and no authorization path ever reads it.
  **Nothing is activated by any of the three values**, and rejecting or
  setting aside does nothing at all. Approving a change offered since
  `docs/tasks/0026-apply-validate.md` — one whose question carries
  `authorizes-apply: true` — authorizes the applier to make it in the
  resident's own configuration checkout and commit it there; approving
  one offered before that authorizes the record and nothing more,
  permanently. Activating is still `docs/tasks/0027` and still the
  resident's alone.
- **`apply`** — the applier seat's hands
  (`docs/tasks/0026-apply-validate.md`). `castle apply <answer-id>`
  spends one approval by hand; `castle apply --sweep` spends every
  approval nothing has applied yet, at most once each. See "Applying an
  approved change," below.
- **`correct`** — also intake, and a second, different kind of speech:
  the resident volunteering how the system is doing, unbidden, rather
  than asking for anything or answering a question it posed
  (`docs/tasks/0010-correction-record.md`, Proposal 06's verdict half).
  Writes a `correction` record — `provenance: requested`, `seat:
  intake`, like `answer` — stamped with mechanical filing-time context
  (see "Filing-time context," below), then appends the resident
  model's *volunteered* write path: an entry citing the correction,
  verbatim, no seat paraphrasing a word of it. `--refs` here is the
  record's one causal claim ("this correction is about that record")
  and only the resident may make it — nothing populates it
  automatically. Refused outright when invoked from inside a worker
  turn, at the same choke point that refuses an answer there
  (`write_record`, keyed on `CASTLE_WORKER_CLAIM`): `castle record
  --type correction` has been refused since
  `docs/tasks/0010-correction-record.md` so that no seat can fabricate
  verbatim resident speech, and this is the same prohibition applied to
  the other door — a tenant filing one would not merely speak for the
  resident once, it would install an opinion they never held where the
  router reads it (`docs/tasks/0023-resume-cold.md`). `castle-modal`'s compose mode reaches the same write
  path (`file_correction()` in `agent/castle`) after asking, in plain
  language, whether what was just typed is something to fix or
  feedback about how the system is doing — see "`castle-modal`" below.
- **`record`** — the generic writer underneath the above, and what a
  worker or router seat calls directly. Any seat, any type. `--fact` is
  honored here too so a worker raising a `question` record can name the
  fact it's eliciting up front, and `--outcome` likewise for a
  `result` — **a human holding the worker seat by hand should pass
  `--outcome failed` when an errand failed**, because no surface may
  read failure out of prose: a result with no `outcome` field reads as
  done, forever (see "The claim record, and the `outcome` field").
  `--outcome` is **enforced at write time too**, refused on any
  `--type` but `result` — since `docs/tasks/0025-approval.md` gave the
  validator that same scoping, and a validator stricter than the writer
  it backstops is the worse half of the asymmetry it was fixing: the
  record would be written, print an id, exit 0, and be condemned
  afterwards by an advisory command nothing runs automatically, in a
  journal whose only remedy is editing history the design says is never
  edited.
  `--target` names which checkout a result's diff is against
  (`private` or `mechanism`) — the automatic path fills it in from what
  the tenant wrote to `$CASTLE_TARGET_FILE`, and this flag is the same
  lever for a human holding the seat by hand or a fixture building a
  result directly. It is **enforced at write time**, like `--blocking`
  and unlike `--fact`: refused on any `--type` but
  `result`, and refused blank. Not because it carries `--blocking`'s
  dangling-reference hazard — it does not — but for the reason stated
  just below about that flag, running the other way. `cmd_validate`
  rejects `target` on a non-result record and rejects a blank one, so
  a writer permitted to produce either would be a door laxer than its
  own backstop, and in an append-only journal the record it wrote
  could never be withdrawn: `castle record` would print an id and exit
  0, and only `castle validate` — advisory, invoked automatically by
  nothing — would later call it malformed. What is deliberately *not*
  enforced is the vocabulary: a third checkout role should not need a
  schema migration (`docs/tasks/0024-config-target.md`).
  `--blocking` is **not** convention-only like `--fact` — it is
  enforced at write time, and the refusals are listed below — and it
  says that this question stopped the errand — the one thing no later
  reader could reconstruct, since a question filed *alongside* a result
  and one filed *instead of* one are indistinguishable afterward. It is
  the only one of the three with a hard refusal attached: a `--blocking`
  question whose **first** `--refs` entry does not walk back to a
  `request` record is rejected outright, because a blocking question no
  fold can attribute to an errand is unresumable forever and looks
  exactly like a working one. The first ref is the test because it is
  the only one resumption reads — `_find_root_request` follows `refs[0]`
  and ignores the rest, so a correct id in second place buys nothing.
  Two further combinations are refused for the same reason, that a
  record which looks meaningful and does nothing is worse than one that
  was never written: `--blocking` with `--spool` (the spool is
  ephemeral by design and no fold reads it, so a durable claim that an
  errand has stopped does not belong there) and `--blocking` on any
  `--type` but `question` (nothing reads the field anywhere else)
  (`docs/tasks/0023-resume-cold.md`).
  `--decision` exists here only so this writer can refuse it **by
  name**: `castle record` never writes a `decision` field, on any type,
  ever. The posture is `--type correction`'s, for the same reason —
  what makes an approval mean anything is the set of checks
  `file_answer` runs before writing one (this really is a change the
  harness proposed, it elicits no fact, its second ref really is the
  result, and that result's bytes still hash to what was proposed), and
  this writer runs none of them. Not a security boundary: a tenant
  running as the resident could write the file by hand. The difference
  is between a decision made through the one path that verifies what it
  is deciding and one that does not
  (`docs/tasks/0025-approval.md`).
- **`route`** — the router. Reads every `result` and `question` record
  not yet referenced by a `decision` record **written by the router
  seat itself** — filtering on `seat: router`, not just record type, is
  a `docs/tasks/0009` bug fix: before it, any decision record
  referencing a result (from any seat) would have permanently
  suppressed that result's routing, since nothing distinguished "the
  router looked at this" from "some record merely points at this." For
  each unrouted record it appends a `decision` deciding its channel
  from provenance alone (see below) — `requested` routes to **notify**
  (a real interruption: `castle route` shells out to
  `CASTLE_NOTIFY_COMMAND`, default `notify-send` on `$PATH`, best-effort
  and non-fatal if it fails or isn't installed), `initiated` routes to
  **digest**. Idempotent: run it again over an already-routed journal
  and it does nothing. There is no code path in `cmd_route` that picks
  a channel without also writing the decision record for it — "no
  routing without an appended decision record" isn't a rule the tool
  has to remember, it's the only thing the function does. `correction`
  records are never in the set `route` walks, on purpose, forever: a
  correction is the resident speaking *to* the system, not something
  *addressed to* the resident, and routing one would be the system
  answering back to a judgment about itself
  (`docs/tasks/0010-correction-record.md` scope 4; pinned by a CI
  regression in `test/agent-loop/run.sh` and `check_assertions.py`, not
  just this sentence). Every decision it writes also carries
  `considered` and `propensity` — the channels weighed and the
  probability of the choice made, for later off-policy evaluation (see
  "The considered set and the selection propensity," below, for what
  that does and does not buy today).
- **`work`** — the worker seat's hands (`docs/tasks/0009`). Reads a
  `request` record, runs `CASTLE_WORKER_COMMAND` (default: a headless
  `claude -p` via `agent/castle-worker-claude`) with the request body
  on its stdin and `$CASTLE_REQUEST_ID`/`$CASTLE_DIFF_FILE`/
  `$CASTLE_TARGET_FILE` in its environment, and folds the command's
  stdout (reasoning), `$CASTLE_DIFF_FILE` (a diff, or nothing) and
  `$CASTLE_TARGET_FILE` (one word, or nothing) into a `result` record.
  **Which repository the tenant works in is configuration, not a
  guess** (`docs/tasks/0024-config-target.md`). Two roots, either of
  which may be absent: `$CASTLE_PRIVATE_ROOT` is the resident's own
  configuration checkout and `$CASTLE_MECHANISM_ROOT` a checkout of
  this framework. A turn with no usable private root refuses before it
  runs anything, writing a `failed` result that names the option
  (`castle.agent.repo.private`) rather than falling back to the
  working directory — which under the dispatch unit is the resident's
  home folder, and used to be exactly what an unconfigured worker was
  told its repository was. "Usable" is checked in layers: absolute,
  exists, is a directory — then, when `git` is on `$PATH`, `git
  rev-parse --show-toplevel` — run with every `GIT_*` variable
  stripped, since an inherited `GIT_DIR` or `GIT_WORK_TREE` otherwise
  makes git answer about a different repository than the one being
  checked. It catches both a directory git
  cannot use at all (an empty `.git`, a dangling worktree link) and a
  path that is a *subdirectory* of a checkout rather than its root,
  where a diff would carry paths relative to the wrong root. Where
  `git` is not reachable — it arrives only via `modules/dev`, which is
  optional — the check degrades to testing that `.git` exists and says
  so rather than claiming more than it verified, because a tenant can
  still write a diff by hand on a host with no git. A mechanism root
  that is configured but is not a usable git working tree does *not*
  refuse the turn: it is
  reported to the tenant in a third variable,
  `$CASTLE_MECHANISM_ROOT_INVALID`, and named in one sentence appended
  to every result the turn writes — see "The claim record" below for
  why that sentence is written by the harness and not left to the
  tenant's own prose. The contract sits at the errand boundary
  (Proposal 03): what runs inside the command is free, but a result
  record with the diff embedded is the only thing that gets to matter
  to the rest of the system. **The worker proposes; it never deploys**
  — this function has no code path that runs `nixos-rebuild`, `git
  commit`, or anything else that touches a running system or this
  repo's history. Before anything else it takes an exclusive `flock`
  on that errand's lease (see "Where state lives") and writes a
  `claim` record; a second `castle work` on an errand somebody is
  already working is refused outright, with nothing written. Re-running
  it on an errand that already has a result is *not* refused — that is
  the retry path, and it stays exactly that
  (`docs/tasks/0021-auto-dispatch.md`). An errand can take more than
  one turn: what goes on the tenant's stdin is the errand's whole
  continuation packet — the request verbatim under a heading, then
  every prior turn's account, every question raised, and every answer
  given — and a turn resuming an answered blocking question also
  carries `$CASTLE_RESUME_ANSWER_IDS`. Both are assembled here rather
  than in `castle dispatch`, so a hand-run turn and a dispatched one
  are handed identical context by construction. That variable means
  "there is an earlier turn of yours in the packet, and these are the
  answers you are continuing from" — so a *first* turn that happens to
  spend an answer (a blocking question filed and answered before
  anything ran) leaves it absent, and its claim narrates no resumption,
  while still naming the answers it spent. The spend is accounting; the
  narrative is a claim about history, and only the second one needs a
  history to be true.
- **`dispatch`** — one sweep of the journal, and the only subcommand
  a machine runs unprompted (`docs/tasks/0021-auto-dispatch.md`). In
  order: take a global sweep lock (one sweep at a time, machine-wide);
  write the watermark if this journal has never had one — a backstop,
  since on a host running `modules/agent` the normal writer is the
  `castle-dispatch-watermark` unit at session start, and what is left
  for a sweep is a journal restored mid-session; give every
  interrupted turn a result; work every eligible request, oldest
  first, one at a time; run `route` exactly once at the end. A request
  is eligible iff nothing has produced a `result` for it, nothing is
  running on it, it is not named in the watermark record's own `refs`,
  and it carries no `filed-during-turn` stamp — a fold over the
  journal, nothing else — **or** it has an answered, unspent blocking
  question, which is the one exception to the first clause and buys
  exactly one further turn (see "Resuming an errand" below).
  Provenance is deliberately *not* an eligibility condition (it decides
  the channel, never whether the errand runs), and neither is an
  *unanswered* question, nor an answered **non**-blocking one: only an
  answered question whose writer marked it blocking affects
  eligibility, and nothing anywhere resumes an unanswered one — no
  default, no timeout, nothing but the resident closes a question. Exit code 0 whenever the sweep ran, *including* when an
  errand it attempted failed: failure is visible in `outcome`, and a
  nonzero exit here means dispatch itself broke. On a host that opts
  into `castle.agent.dispatch.enable` (`modules/agent`), a systemd
  user path unit and a one-minute backstop timer run this; a human
  holding the dispatch seat can run it by hand, exactly like every
  other subcommand here. `--watermark-only` runs the guards, puts the
  watermark down if this journal has never had one, and returns
  without sweeping: that is what the session-start unit runs, so the
  boundary is "filed before this dispatch-enabled session existed"
  rather than "filed before the first sweep happened to run" — a
  distinction the VM test made concrete by losing that race to a
  resident's first keystroke.

  `seat: dispatch` appears on exactly two kinds of record — the
  watermark decision and any `result` the reaper had to supply — and
  it is **plumbing, not a reasoning seat**, a new value in the
  existing category `digest` already occupies rather than a new
  category. Dispatch holds no judgment and chooses no tenant: which
  request runs next is a total function of the journal, which is also
  why it writes no decision record per errand (a record whose evidence
  text would be identical on every invocation forever is ritual, not
  accountability). Giving it a policy for *which* eligible request to
  run, or a say in whether to run one at all, would make it a
  reasoning seat — see `docs/architecture.md`'s Seats section, which
  exists partly to stop a later agent "completing" it into one.
- **`digest`** — folds the journal into a report: one section per
  errand (a `request` and everything transitively `refs`-linked to
  it), in creation order, plus a trailing **Corrections** section
  listing every correction in the period (created time, verbatim first
  line, `refs` if any) — corrections aren't errands, so they get their
  own section rather than going missing from a "read the journal cold"
  account (`docs/tasks/0010-correction-record.md` scope 7). This *is*
  the digest surface from `docs/architecture.md` — invoked by hand in
  this skeleton, per `docs/tasks/0008`'s non-goals; scheduling it is
  later work. `castle-modal`'s status mode is a compact, "recent
  errands only" variant of the errand fold (it never shows corrections
  at all — see below).
- **`validate`** — schema-checks a journal: every required field
  present, `type` and `provenance` in their allowed sets, every
  `decision` record's `evidence` field non-empty, every `refs` entry
  pointing at a record that actually exists, and — when present, not
  required — `propensity` parsing as a float in `[0,1]`, `considered`
  as a non-empty flat list, `target` being non-blank and on a `result`
  record, and (when both `channel` and `considered` are present)
  `channel` actually being a member of `considered` — a
  general invariant ("you can't choose what you didn't consider") kept
  in the permanent schema gate rather than only in the test harness,
  since it holds for any future router policy, not just today's
  two-channel rule. This is what CI asserts with
  (`test/agent-loop/run.sh`).
- **`show`** — prints one record verbatim, checking the journal then
  the spool.

## `castle-modal` — the ambient intake

A floating `foot` terminal (bound to `Mod4+Shift+Return` for compose
and `Mod4+Shift+a` for answer in `modules/home`'s Sway config — see that
module for why these chords and not others) running
`agent/castle-modal`, a second stdlib-only Python script that imports
`agent/castle` in-process rather than shelling out to it. Four modes,
though only three have a chord — review is reached from answer's own
picker:

```
castle-modal --mode compose [--limit N] [--kind request|correction]
castle-modal --mode status  [--limit N]
castle-modal --mode answer  [--question ID]
castle-modal --mode review  [--question ID]
```

- **compose** (the default) — reads multi-line free text from stdin
  until a line containing exactly `.` or EOF. No category picker, no
  priority field while typing: the whole premise is that the resident
  describes what's on their mind in their own words and doesn't know
  (or shouldn't need) the system's vocabulary for it. Once the body is
  captured, an *interactive* session asks exactly one plain-language
  question — something to fix, or telling the system how it's doing —
  answered with a single keypress (bare Enter defaults to "something to
  fix," the common case); a non-interactive caller supplies `--kind`
  instead (default `request`, so every piped caller predating this flag
  is unaffected). "Something to fix" files a `request` record exactly
  like `castle ask` would; "telling the system how it's doing" calls
  `agent/castle`'s `file_correction()` — the same write path
  `castle correct` uses — with `surface: modal`
  (`docs/tasks/0010-correction-record.md` scope 6). Classification
  itself adds no judgment either: the resident answers one question,
  the tool never guesses, and the word "correction" — this document's
  word, not the resident's — never appears on anything the modal
  prints; `--kind`'s two values are for scripts and CI, not shown to a
  human.
- **status** — folds the `--limit` most recent errands (default 10)
  from the journal into a compact listing: what was asked, what state
  it's in, and what the router most recently decided and why.
  "Awaiting a worker" is still the fallthrough, and still says only
  that nothing has touched the errand yet
  (`docs/tasks/0015-filed-not-in-progress.md`; see `_errand_state`) —
  but the other states are now *earned* rather than guessed
  (`docs/tasks/0021-auto-dispatch.md`): "in progress (started HH:MM)"
  requires both a `claim` record and a live `flock` on that errand's
  lease, checked at read time and checked *first*, ahead of any result
  — an errand whose failed turn is being retried at this moment must
  not be labelled with advice to run the command that is already
  running. A claim whose lease is dead reads as interrupted, because
  nothing is actually running. The state is that of the errand's
  **newest turn**: the result naming the newest `claim` is the one that
  labels it, so an old turn reaped after a newer one completed does not
  make a finished errand read as interrupted, and a second turn that
  died is not masked by an older turn's result. A request a tenant
  filed during its own turn reads "filed during a worker turn — `castle
  work <id>` to run it", and one the watermark excluded reads "not
  started automatically (predates dispatch) — `castle work <id>` to run
  it": nothing will ever start either of them on its own, so neither
  may claim to be awaiting a worker. A result's
  `outcome` supplies the rest — `done`, or "failed / timed out /
  interrupted — castle work `<id>` to retry". Every non-done label
  names the retry command on purpose: 0015's lesson was that a label
  must not cause the inaction it describes, and "failed" with no next
  step is that mistake in the other direction. `castle digest`
  deliberately grows no lease reader to match: a digest is a
  historical account of a period that already happened, not a live
  view, so "in progress" has no business appearing in one. The "come
  back later and check" half of the design. Corrections never appear
  here: they aren't errands, and there's nothing about one to "come
  back and check" on.

- **answer** (`Mod4+Shift+a`) — the questions the system is waiting on,
  and one of them answered (`docs/tasks/0022-answer-in-ui.md`). A
  question is **pending iff no `answer` record's `refs` names it** —
  a fold recomputed on every invocation, not a stored flag, which is
  why nothing about a question is ever edited when it gets answered.
  Nothing pending prints one plain line and exits. Otherwise the
  pending questions are listed `[1]` through `[9]` a page at a time,
  each showing the question's first line and, when its refs chain
  reaches an originating request, an indented `about:` line naming that
  errand. Past nine, a trailing "…and N more waiting — press m to see
  them." names the rest and `m` turns the page, wrapping to the first
  after the last: a cap with no way past it would make question ten
  unreachable, on a surface whose fold exists so that nothing can be
  hidden. Ordering is by full record id, which is **deterministic and
  identical on every invocation** — that is what makes a screen-relative
  number safe to press — and chronological only to one-second
  granularity, since ids carry a random suffix and same-second questions
  sort by it. One keypress picks one; **any key that selects nothing
  closes the window immediately, writing nothing anywhere** — the
  keypress is the dismissal, and there is no code path from it to a
  write. A picked question is then shown in full, verbatim and never
  truncated, and answered in compose mode's own `.`-terminated grammar.
  The answer goes through `file_answer()`, so the record and any
  elicited resident-model entry are byte-identical to what
  `castle answer` writes.

  What this surface prints is bound by one rule: **no record ids, and
  none of the words `seat`, `provenance`, `refs`, `journal`, `record`,
  `channel`, `evidence`, and no fact names.** That binds the text the
  tool adds — question and request bodies are shown exactly as their
  authors wrote them. So the confirmation carries no id, and says only
  what is true: a bare `"Filed."` — and nothing more, in either
  direction. It no longer says nothing resumes the errand, because
  since `docs/tasks/0023-resume-cold.md` an answered blocking question
  does; and it does not claim a resumption either, because this process
  cannot see whether dispatch is enabled or running on this host and
  never triggers one itself. Both would be `docs/tasks/0015`'s defect,
  from opposite sides. Plus `"Noted — I'll remember that."` if and only if an
  entry really was written to the resident model. A write into the
  resident's own model that the resident is never told about is
  authority exercised invisibly; the CLI's `recorded resident-model
  entry for fact '...'` line, which names the internal fact key, never
  reaches this surface.

  `--question ID` is the non-interactive contract, exactly parallel to
  compose's `--kind`: scripts and CI only, never shown to the resident.
  A piped session with questions pending and no `--question` **refuses**
  (exit 1) rather than guessing which one was meant, and prints the
  answer's id on stdout when given one. A piped `--question` is answered
  against the journal whatever the pending fold says, so its refusals
  are the same ones `castle answer` gives — an empty fold is not a
  reason to stop checking the id a script actually named. **An interactive session always
  ignores `--question` and shows the picker** — preselecting a question
  for a human who is looking at the screen is the answering-the-wrong-
  one hazard the picker exists to remove. Exit 0 on filed, nothing
  pending, or a deliberate dismissal (looking and declining is a
  success, not an error); exit 1 on an empty body, an unresolvable or
  missing `--question`, a target that is not a question, and an
  already-answered question. One further refusal since
  `docs/tasks/0025-approval.md`: a question that turns out to be a
  **proposed configuration change** is not answerable in prose at all,
  on either the scripted or the interactive path — the interactive one
  branches into review mode, and the scripted one refuses with a
  pointer to `--mode review --question ID`.

- **review** (no chord of its own) — the first place a resident grants
  Castle anything (`docs/tasks/0025-approval.md`). A question the
  harness filed to propose a configuration change appears in answer
  mode's picker like any other — that fold has never cared what a
  question is about — and picking it branches here instead of into the
  free-text grammar. No second chord, deliberately: a resident who
  pressed the "what is waiting on me" chord should not have needed to
  know in advance which of two kinds of waiting it was.

  Four things are shown, in this order and for this reason: **where
  the change applies** (the harness's own resolved-path sentence,
  quoted rather than re-derived), **what approving does and does not
  do**, **Castle's own account of why** under a label saying whose
  words those are, and **the diff, last, verbatim, never truncated**,
  with a line pointing at `foot`'s scrollback for a long one. Evidence
  before reasoning; the diff always available and always last. No
  checklist, and no "reversible? y/n" line asserting a property
  nothing here checked.

  The boundary statement is printed **beside the keys**, not under the
  diff, and it is the load-bearing part of this surface: *nothing on
  this machine is edited, committed, or applied by approving*. An
  "Approve" that silently has no effect is `docs/tasks/0015`'s defect
  in its sharpest form — a label causing the inaction it describes —
  so the sentence lives where the keypress is offered rather than in a
  footnote. Three distinct, labelled keys: `[a]pprove`, `[r]eject`,
  `[d]efer`. **Any other key, bare Enter included, closes without
  deciding and writes nothing** — no key a resident reaches for by
  reflex authorizes anything. Approve and reject then invite an
  optional comment in compose mode's `.`-terminated grammar; defer
  invites nothing, since asking for a reason before letting someone
  leave is the friction deferring exists to avoid.

  Nothing tenant-authored is parsed. The rendering recognises exactly
  two things in the result body, and both are the harness's own
  writing: the fenced diff block and the resolved-path sentence. Two
  more of the harness's own lines are dropped rather than shown under
  Castle's account — the turn header, which carries a record id and
  the tenant's store path, and the worker-proposes note, whose content
  the boundary statement already says in this surface's own words.
  Everything else is quoted whole.

  The window resizes itself on entry when it has a terminal on both
  ends, best-effort, `swaymsg` with `[app_id="castle-modal"]` criteria
  — scoped rather than focus-relative, because a bare `resize set` is
  correct at the instant of the keypress and not a moment after.
  `CASTLE_REVIEW_RESIZE_COMMAND` overrides the whole command line and
  the empty string opts out, the same convention
  `CASTLE_NOTIFY_COMMAND` has. A host with no Sway gets a harmless
  failed exec and a review that works at whatever size the window
  already is.

  This mode's vocabulary rule is answer mode's plus three words:
  `question`, `answer` and `proposal` are also absent from anything it
  adds, and the resident-facing noun for what is being decided is
  **"a change"** — chosen once, here, so a later surface does not
  invent a third word. `--question` is the scripted contract, read
  under the same rule answer mode applies and for a larger reason: a
  preselected guess here would be an authorization.

Headless by construction: every mode only ever reads `sys.stdin` and
writes `sys.stdout`/`sys.stderr`, with no `curses` and no compositor
dependency anywhere in the control flow — `sys.stdin.isatty()` is
checked only to decide whether to print a couple of purely cosmetic
prompts, whether to hold the window open for a dismissal, whether there
is a human present to show a picker to (answer and review mode), and
whether there is a window worth asking Sway to resize (review mode).
That's what lets CI pipe canned
input at it and assert on the request record it produces with zero
Sway, zero foot, and zero display server involved.

## `agent/castle-worker-claude` — the default worker tenant

A plain bash script, the reference implementation of
`castle.agent.worker.command`'s contract (see `castle work` above):
reads the errand's continuation packet on stdin — the request, and on
an errand that has already had a turn, every prior result, question and
answer, each quoted inside boundaries carrying a token generated for
that turn — builds a prompt that states the errand, the two
checkouts it was given (and which of the mechanism checkout's three
states this host is in),
that only those boundaries say who wrote what, and — unmissably — that
this seat must not deploy anything, then execs `claude -p` with the
prompt **on stdin**. The script names its own variable `errand_records`
for that reason: a tenant that treats the first line of stdin as the
resident's text is reading the packet's preamble, and on a resumed turn
would read an earlier turn's output and the resident's answer as the
request.

Two details of that handoff are load-bearing rather than incidental, and
a conforming tenant of your own should copy both. **The prompt goes on
stdin, never in an argument.** Linux caps a single `argv` entry at
`MAX_ARG_STRLEN` — 32 pages, 131072 bytes on a 4 KiB-page machine — and
a packet carrying several turns' worth of diffs passes that. Past it
`exec` fails `E2BIG` and the turn records `outcome: failed`; since that
turn's claim has already spent the answer, the errand can never
auto-resume, so it would die permanently for having gone on too long.
The script opens the prompt file, unlinks it, and execs with stdin on
the surviving descriptor: the file is gone before the handoff, `exec`
keeps the tenant in the process group `castle work` captured at spawn,
and the exit code stays the tenant's own. **And the harness's own instructions are
fenced with the packet's boundary token**, every one of them — the
`BEGIN harness instruction:` / `END` pair is the same grammar the packet
uses for records, so a tenant learns one rule and applies it to the
whole prompt. Marking only the headings was not enough: the block a
prior result body is likeliest to counterfeit is the resumed-turn note,
which is prose, and two unmarked copies of it would make the prompt's
own rule discount them both. The packet ends at an explicit
`<token> END OF PACKET` line.

Since `docs/tasks/0024-config-target.md` the prompt's contract list is
where the layer-decision rule lives: an ordered four-step test with one
override, written to be checked against the repository rather than
merely agreed with. The tenant answers it by **reading** the candidate
files — `resident.nix`, the host module the private flake imports, the
option's declaration under a mechanism checkout — and never by
evaluating the resident's flake: a path flakeref copies the whole
tracked tree into the world-readable store, and that tree holds the
journal and the resident model. Reading is textual inference where
evaluation would have been authoritative, so where the winning layer
is not clear from the text the prompt sends the tenant to a question
rather than a guess. Plus the read-only command list, the two coupling
rules that make a configuration diff silently inert, and the
ask-first-diff-on-resumption policy described under "Resuming an
errand" below. Read the script itself
for the exact prompt; it is short and meant to be audited, not
summarized. `test/agent-loop/scripted-worker.sh` is the model-free
stand-in CI actually runs — nothing in CI executes a real model.

Run any subcommand with no journal configured and it falls back to
`~/.local/state/castle` — fine for poking at the tool by hand, but see
"Where state lives" below for what a real deployment should set.

## The record format

One file per record, named `<id>.md`, holding a strict, flat
frontmatter block followed by a markdown body:

```
---
id: 20260816T130000Z-request-4e13ec
type: request
provenance: requested
refs:
seat: intake
created: 2026-08-16T13:00:00Z
---

The cursor is too small on the laptop screen.
```

**The frontmatter subset is deliberately not YAML.** It is:

- A line containing exactly `---`, opening the block.
- Zero or more `key: value` lines — one field per line, split on the
  *first* colon, both sides trimmed of surrounding whitespace.
- A line containing exactly `---`, closing the block.
- Everything after that (skipping one blank separator line) is the
  body: free-form markdown prose.

No nesting, no anchors, no multi-line values, no block scalars. A
field that needs more than one value (`refs`) is a single line of
comma-separated ids: `refs: id-one,id-two`. This is what lets the whole
parser fit in about a page of stdlib Python (`parse_record` /
`render_record` in `agent/castle`) instead of a YAML dependency, and
what keeps `grep '^type: decision' journal/*.md` a completely valid way
to query the journal without running any tool at all. The cost is real:
nobody is putting a paragraph of structured metadata in a frontmatter
field. That trade is intentional — prose belongs in the body.

**Records are UTF-8 by definition.** `parse_record` and `write_record`
both pass `encoding="utf-8"` explicitly (docs/tasks/0033-byte-exact-
proposal.md) — not a new constraint, but the assumption every fixture,
example and piece of hand-written prose in this repo already made,
now enforced at the one call site each direction passes through
instead of left to whatever the host's locale happened to be.

### Required fields (every record)

| Field        | Meaning                                                              |
|--------------|-----------------------------------------------------------------------|
| `id`         | `YYYYMMDDTHHMMSSZ-<type>-<6 hex chars>` — sortable, greppable, collision-safe enough. Must match the filename. |
| `type`       | One of `request`, `decision`, `result`, `question`, `answer`, `correction`, `claim`. |
| `provenance` | `requested` (the resident asked for this) or `initiated` (the system undertook it on its own). |
| `refs`       | Comma-separated ids of the records this one responds to. Empty for a root request. |
| `seat`       | Which seat wrote this record (`intake`, `router`, `worker`, `digest`, `dispatch`, or a specific worker's own name). |
| `created`    | UTC timestamp, `YYYY-MM-DDTHH:MM:SSZ`.                                 |

`decision` records require one more, non-empty field:

| Field      | Meaning |
|------------|---------|
| `evidence` | The concrete fact the decision rests on — not an impression. `castle route` states the provenance fact itself, e.g. *"result `…` carries provenance=requested, inherited from originating request `…`: the resident asked for this directly…"* This is Proposal 04 (`docs/architecture.md`) given a mechanically-checked teeth: `castle validate` fails the journal if any decision record's `evidence` is missing or blank. |

Extra fields beyond this minimum set are allowed and ignored by
`validate` — `castle route` adds a `channel` field (`notify` or
`digest`) to the decision records it writes, purely so `castle digest`
doesn't have to re-derive it from prose.

### The considered set and the selection propensity

`castle route` also writes two more fields on every decision it
appends:

| Field         | Meaning |
|---------------|---------|
| `considered`  | The channels the router evaluated before choosing, comma-separated in the same flat-list convention as `refs` (e.g. `notify,digest`). Today this is always both entries in `CHANNELS` (`agent/castle`) — the rule has no early-out, so it genuinely weighs both every time. |
| `propensity`  | A float in `[0,1]`: the probability this policy would choose the recorded `channel` in this context — how likely the policy was to make this choice, **not** how sure anyone is that the choice was right. Today's rule is a deterministic function of `provenance` alone, so the honest value is `1.0` on every record — there is no other branch it could have taken. |

**Why these exist, stated exactly as far as it goes and no further.**
Bottou et al., *Counterfactual Reasoning and Learning Systems* (JMLR
14, 2013), is the argument: what makes logged interaction data reusable
for *off-policy evaluation* — "would a different routing policy have
done better last month?" — is not the raw record of what happened, but
the **considered set** (what alternatives existed) and the **selection
propensity** (the probability the actual choice was made). Without
both, importance-sampling estimators can't be built at all; the
question isn't merely harder, it's unidentified. Records here are
append-only, and Proposal 04 (`docs/architecture.md`) already discards
the raw sensor stream that would otherwise substitute — so a field not
written now can never be reconstructed later, and the loss would be
silent: nothing would tell a future reader that the corpus was missing
something, only that off-policy questions about today's decisions
quietly can't be answered.

**What this does *not* buy today, stated just as plainly.** With a
deterministic provenance-only rule, `considered` is the same two
entries and `propensity` is `1.0` on every single decision record.
Importance-sampling weights computed from constant propensities carry
no information — there is no variance to explain, nothing to
reweight against. **The real and sufficient argument for adding these
fields now is corpus continuity, not present-day analytical power**:
records written from this point on carry the field, so when the router
eventually gains a rule with real branches (multiple plausible channels,
a learned or probabilistic policy), there is no discontinuity in the
journal — no era of decisions whose `considered`/`propensity` were
simply never captured and can never be recovered. Claiming more than
that — that today's fields already let anyone estimate what a
different policy would have done — would be false, and this document
says so on purpose rather than implying it by omission.

Like `evidence`, these are decision-only. Unlike `evidence`, they are
**not required on all decision records** — see the comment in
`cmd_validate` (`agent/castle`) for why: the journal is append-only, so
every decision written before this schema addition is already
permanent, and a validator that started requiring a field no writer at
the time could have supplied would fail the entire pre-existing journal
retroactively. `castle validate` instead checks them **when present**:
`propensity` must parse as a float in `[0,1]`, `considered` must be a
non-empty flat list, and — when both `channel` and `considered` are on
the same record — `channel` must actually be a member of `considered`.
That last check is a general invariant rather than an assumption about
today's specific two-channel vocabulary, which is why it lives in the
permanent schema gate and not only in the test harness. A decision
record from before this change, with none of these fields, still
validates clean.

### The claim record, and the `outcome` field

Two additions from `docs/tasks/0021-auto-dispatch.md`, both driven by
the same fact: once errands start themselves, nobody is watching the
terminal when one goes wrong.

A **`claim`** record is written the moment `castle work` takes an
errand — after the lease, before the tenant command is even resolved.
It needs no new frontmatter field: `refs` points at the request, the
body names the tenant command and the start time, same as any other
record's account of itself. Its job is *observability across a
restart*, not exclusion — the lease already provides exclusion, for
free, from `flock`'s own semantics. What the lease cannot do is
survive a reboot, and that is exactly the case that matters: without a
durable record, an interrupted turn would be indistinguishable from an
untouched one, silently eligible again, and the resident's status
surface would have no "interrupted" state to show because nothing
would know one had happened. `castle record --type claim` is
permitted, unlike `--type correction`: a claim is a mechanical
observation, not resident speech, so none of the reasoning that makes
corrections special applies.

A **`filed-during-turn`** field on `request` records, whose value is a
`claim` id. `write_record` stamps it on any request written while a
worker tenant's turn is running — the tenant carries
`CASTLE_WORKER_CLAIM` in its environment, and anything it invokes
(`castle ask`, `castle record --type request`) inherits it. Dispatch
never auto-starts a request carrying the stamp.

The reason is spend, not correctness. "One automatic attempt per
request" bounds unattended work only while the *supply* of requests is
outside the tenant's control, and it isn't: a tenant that spots a
second problem while fixing the first files it the sanctioned way, and
each new request is a fresh errand with a fresh attempt. One sweep ran
five turns off a single resident request before this existed. The
stamp is a mechanical observation — "filed while that turn was
running," a fact about who was executing, never a claim about the
request's worth — so the request stays an ordinary request: it appears
in the status fold like any other and `castle work <id>` runs it. Only
the automatic attempt is withheld, which puts "should this follow-up
happen?" back where a cost-and-authority question belongs.

An **`outcome`** field on `result` records, from a closed vocabulary:

| Value         | Written when |
|---------------|--------------|
| `completed`   | the tenant exited 0. |
| `failed`      | the invoker watched the tenant die — a nonzero exit, a signal, an unparseable or unrunnable command, or no command configured at all. |
| `timeout`     | the tenant outlived `CASTLE_WORKER_TIMEOUT` and its whole process group was killed. |
| `interrupted` | the *invoker itself* died before writing anything, and a later `castle dispatch` sweep supplied the account from the surviving claim record. |

Every result a worker turn writes references **both** the request and
the `claim` it closes (`refs: <request-id>,<claim-id>`). That is what
makes the reaper's ledger per *turn* rather than per errand: it asks
"does any result name this claim?", so a failed errand a resident
retried by hand — whose retry then died — still gets an account of that
second turn. With request-only refs the first turn's result closed the
second turn's claim and the interruption was never recorded at all.
Eligibility is still per request: any result at all bars an automatic
attempt.

The `failed`/`interrupted` boundary is exactly "did anything survive to
write the account": a tenant killed by a signal while `castle work` is
still running is `failed`; only a turn nobody ever finished is
`interrupted`.

**This is a named cross-task contract.** Tasks 0026 and 0027 are
expected to reuse this field name and these four values rather than
each inventing a sibling field, and 0028 (rendering the errand
lifecycle) reads it directly. **0026 honoured that**, and how it did is
worth stating because the shape generalises: it kept `outcome` meaning
exactly what it means here — an observation about the writer's own run
— and added `apply-outcome` for the different observation it needed, an
account of what happened to the *change*. The two compose without
either widening: a validation killed at its bound is `outcome: timeout`
with `apply-outcome: validation-failed`, and a refusal correctly
reached is `outcome: completed`, because the applier ran to a recorded
conclusion and a conclusion is not a failure of the run. **No surface may ever infer failure by
grepping a body for a word like "FAILED."** The exit code is the fact
and it lives in this field; the body carries the reasoning. That is
not hypothetical hygiene — before this field existed, a failed errand's
result body said "FAILED" in prose and `castle-modal`'s status fold,
having no way to read it, reported the errand as plain "done."

A surface meeting a value it does not recognise — a later task
extending this vocabulary, a hand-written record, a typo — renders it
**verbatim, with the retry hint**, never as "done". Defaulting an
unknown member of a named contract to success would be the same
prose-versus-field failure the field was added to end, one level up.
Absent and `completed` keep meaning done, which is the append-only
compatibility promise.

Like `considered`/`propensity`, and for the identical reason,
`outcome` is validated **when present** and never required: the
journal is append-only, every result written before the field existed
is permanent, and a validator that suddenly demanded it would fail the
entire pre-existing journal retroactively. A result with no `outcome`
therefore keeps reading as "done" on every surface, forever, on
purpose.

A **`target`** field on `result` records, from
`docs/tasks/0024-config-target.md`, saying which checkout the diff
embedded in that result is meant to be applied to. Two values today,
`private` and `mechanism`, written from whatever the tenant put in
`$CASTLE_TARGET_FILE`.

It exists because nothing else in a result record names a repository,
and a unified diff cannot supply the answer: its `a/`/`b/` paths are
relative and can be identical in both checkouts — a private layer
legitimately carries its own `flake.nix` and its own `hosts/`
directory. So which repo a proposal is against is a judgment made once,
at write time, by the only party that knows, and 0025's approval
binding and 0026's applier both need it against that exact proposal.
The applier reads exactly this field to decide what it may do: `private`
is the one value it acts on, and `mechanism` gets its own named refusal
(`refused-target-mechanism`) rather than an error, because an
approved-but-unapplyable change is a terminal state and not a fault.

The field carries a **role**, not a path. A role reads correctly to a
human or a cold tenant years later; an absolute path reads correctly
today and is a lie the first time the checkout moves or the machine is
reinstalled. The resolved path is stated in the body prose beside the
diff, where nothing keys on it and its staleness is obvious.

**Written only alongside a diff, and its absence beside one is said
out loud.** A target means "the checkout this diff applies to," so a
result with no diff carries no `target` — a tenant that stamps one
anyway has the field discarded, with a sentence in the body saying so
rather than a silent swallow. Recording it would make the result read,
to anything keying on this field to decide where to apply a proposal,
as an applicable proposal with nothing to apply.

The mirror gets a sentence too, and it is the one that matters more.
A stamp with no diff is incoherent but inert; a **diff with no
target** is a real, applyable artifact whose destination is missing,
which is exactly what a consumer routing on this field cannot handle.
It is also the likelier slip — forgetting the second output file is
ordinary, stamping a target while producing nothing is odd. Such a
result keeps its diff and gains a note saying the tenant declared no
target and that a proposal without one cannot be routed to a checkout.
Neither case is a failure; neither is allowed to be silent.

Validated **when present**, like `outcome`, for the identical
append-only reason, and scoped to `result` records the way `blocking`
is scoped to questions. But **not** a closed vocabulary, and that
difference from `outcome` is deliberate rather than an inconsistency:
`outcome`'s four values are a named cross-task contract several
surfaces branch on, while `target` has two values today and obvious
room for a third checkout role, so a membership check would turn adding
one into a schema migration in exchange for safety nobody needs. The
validator asks only "non-blank, and on a result." The known values are
documented here, not enforced in code.

One sentence a *turn* may add to a result body regardless of what its
tenant said: when `castle.agent.repo.mechanism` is configured but does
not name a usable git working tree, every result that turn writes says
so. That is harness-level on purpose. A tenant working a private-layer
errand has no occasion to mention a mechanism-root typo it never
touched, so leaving the disclosure to the model would make the
misconfiguration silent on every errand except the rare one that needed
it — while the errands that *did* need it are refused nothing: the
mechanism checkout degrades, the turn does not.

Fields considered for this record and deliberately dropped, each
failing the "needed now" test: `attempts` (the retry bound is
structural — any result at all makes a request ineligible — so nothing
would read a counter), `duration` (nothing renders a timing view yet),
and `exit-code` (the four-value enum already carries every distinction
a caller makes today).

### Resuming an errand, and the `blocking` field

From `docs/tasks/0023-resume-cold.md`. A worker that needs the
resident's judgment mid-errand usually files its question *alongside* a
result it has already produced — that is what the worker prompt asks
for, and answering such a question changes nothing. Sometimes it
genuinely cannot proceed, and files a question *instead of* a result.
Nothing downstream can tell those two apart afterward: ids carry
one-second resolution and a random suffix, so a question and a result
written in the same final second of a turn have no reliable order. Only
the writer knows, at write time, which shape it wrote.

A **`blocking`** field on `question` records says so. Written once, by
that writer, with the literal value `true`, and never mutated; absent
means false, which is what keeps every question written before this
field existed permanently non-resuming. It is not a status field —
whether a question is *answered* stays the fold it always was (does any
`answer` record name it) — and it is not a judgment about the question's
importance. It is an observation about the writer's own turn, the same
epistemic shape `outcome` has. Like `outcome`, `castle validate` checks
it when present and never requires it; unlike `outcome` there is no
vocabulary to test membership against, so the check is that the value is
the one spelling any writer produces — the literal `true`. The validator
also refuses the field on any record that is not a `question`, which
matters to anyone hand-editing or restoring a journal: `castle record`
will not write `blocking: true` onto a result, and `castle validate`
will not accept one either. The two were briefly out of step, with the
writer refusing what the validator called clean; the backstop must not
be laxer than the door, since the records it exists for are precisely
the ones the CLI never touched.

**What resumption does.** When the resident answers a blocking question,
the next `castle dispatch` sweep finds that request eligible again —
the one exception to "any result at all bars an automatic attempt" — and
runs one more worker turn. Exactly one, per answer, ever. **The spend
token is the `claim` record, not the result**: a resuming turn's claim
names every answer it was given, after the request id
(`refs: <request-id>,<answer-id>`), and an answer named by **any claim
anywhere in the journal** is spent forever — not merely by this
request's own claims. The bound is a property of the answer rather than
of the errand reading it: an answer naming blocking questions on two
errands would otherwise look unspent to each of them in turn and buy a
turn on both, which is not "exactly one, per answer, ever". A
normally-written answer refs one question and cannot tell the two rules
apart.

Because that bound is global, the check that reads it and the write that
spends it are taken under a **global lock** (`spend.lock` in the runtime
directory), held from the recomputation through the claim write and
released immediately after — never across the tenant call. A per-request
lease cannot do this job: two `castle work` invocations on two different
requests take two different leases, so with one answer naming questions
on both they can each read the journal before either writes its claim,
each see the answer unspent, and each spend it. The lock ordering, for
anyone adding another: sweep lock → per-request lease → spend lock, in
that order, always. That has to be the claim, because
`castle work` writes it before the tenant command is even resolved, so
every turn that starts leaves one however it ends — while the two paths
that write results for turns nobody survived (the tenant-fault branches
and the reaper) hardcode `refs: <request-id>,<claim-id>` and cannot name
an answer at all. Spending on the result would leave every crashed
resumed turn eligible forever: one model call per timer tick. Result
`refs` are unchanged by this, and every existing reader of a claim keys
it by `refs[0]`, so the extra ids are invisible to all of them.

Which questions belong to a request is resolved by walking `refs[0]`
back to the first `request` record reached — the same lineage edge
claims and results are keyed by, through as many hops as the chain has.
A question filed against its own result therefore lands on the same
errand a directly refs'd one does, which matters because the tenant that
runs in production is a model deciding its own `--refs`. A question on a
follow-up request resolves to the follow-up and never contaminates its
parent.

**The continuation packet.** A resumed tenant is a fresh process that
remembers nothing, so `castle work` renders the errand's own records
onto its stdin, in this order and each verbatim: the request body under
a heading; every prior result body, in id order; every question the
errand raised, in id order, flagged blocking or not and answered or not;
and each answer immediately under the question it answers. Rendered on
every turn, with no branch for "is this a first turn" — the fold simply
finds whatever the errand has. On the ordinary first turn that is the
request alone, which is what a tenant received before this task; but a
first turn is not *defined* by carrying only the request, and a
blocking question filed and answered before any turn ran (possible, and
tested) gives one a question section and a resident-answer section with
no prior result between them. What distinguishes a first turn is the
absence of an earlier turn's account, not the absence of everything
else. Nothing is truncated and nothing is capped.

**Section boundaries are unforgeable, and nothing else in the packet
is structure.** Each section is delimited by lines carrying a token
generated for that turn alone — `CASTLE-PACKET-<16 hex chars>` — stated
in the packet's own opening paragraph and stored nowhere. A record
cannot contain it, because no record was written after it existed, so a
`result` body (model-authored, quoted byte-for-byte into the next
turn's packet) cannot spell a boundary claiming the resident said
something. Only the boundary line above a section says what that
section is or who wrote it; a heading-shaped line inside one is that
record's own text. A conforming tenant reads the token from the
preamble and trusts nothing else — `agent/castle-worker-claude` says so
in its prompt, and both blocking fixtures in `test/agent-loop/` do it.

**Verbatim there means byte-for-byte.** No body is stripped, rstripped
or reflowed on its way to a tenant: `parse_record` removes only the
single blank line after a record's closing fence, precisely so a body
that begins with whitespace-sensitive markdown survives, and this
renderer keeps what the parser kept. It matters most on exactly this
path — a result body carries an embedded unified diff, whose leading
spaces are its content, and a resumed tenant reads that diff to work out
what an earlier turn already did. What separates one section from the
next is the renderer's own blank line, never the body's trailing
whitespace, so a body that ends mid-line still leaves the following
boundary on a line of its own. The single newline before each `END`
line is the renderer's, which the preamble says out loud so a consumer
extracting a section knows whose byte it is.

Three things are deliberately kept out of it. `correction` records: a
correction is the resident judging the *system*, and feeding a verdict
about the system into the work being judged is backwards (`castle
digest` filters them out of its errand fold for the same reason).
`decision` records: the router's reasoning about when to interrupt the
resident is not something an errand's work needs. And anything outside
the errand, which is impossible by construction rather than by
filtering — the fold can only reach records linked to this request.
Resident-model entries are absent too, but that is a gap rather than a
decision about this packet: no worker reads the resident model on any
turn (`docs/backlog/workers-do-not-read-the-resident-model.md`).

**An answer can be spent by a turn that never ran, and the remedy is the
same command.** The claim naming an answer is written before the tenant
command is checked for runnability, so a host with an empty or
unrunnable `castle.agent.worker.command` spends the answer on a turn in
which no process started. That ordering is deliberate and is what bounds
the failure: with the answer left unspent, the request would carry a
`failed` result *and* an unspent blocking answer, so the fold would find
it eligible again on the next timer tick against the same broken tenant,
forever — 0021's unbounded silent retry, reached from a new direction.
The `failed` result says so, and says what to do: fix the tenant and run
`castle work <id>` by hand. A hand-run turn re-renders that answer into
the packet exactly as an automatic resumption would (the errand's
records are rendered on every turn, spent or not), so nothing about the
resident's answer is lost — only the automatic attempt is.

**Two kinds of errand can never resume, and the remedy for both is a
command.** Every other eligibility condition still applies alongside
resumption, so a request excluded by one of them stays excluded however
many blocking questions on it get answered. Two shapes are excluded:
a request filed *before* dispatch existed on this journal, which the
watermark names in its own `refs`, and a request carrying
`filed-during-turn` — one a worker tenant filed mid-errand, which
dispatch never starts on its own account (see above).

Both produce the same reachable dead end. A resident hand-runs such an
errand with `castle work <id>`, its tenant marks a question blocking and
stops, the resident answers — and no sweep will ever pick it up, because
the watermark or the stamp rejects the request whatever
`_resumable_answers` found. The modal says only "Filed.", so nothing on
screen explains the silence.

That is deliberate rather than an oversight, and for one reason in both
cases: each exclusion is a promise about what will not start itself —
errands predating dispatch, and work a tenant generated rather than a
resident — and letting either begin producing automatic turns because it
was hand-run once would turn a single manual start into a standing
permission. **The remedy is the same command that started it: `castle
work <id>` again.** A hand-run turn resumes whatever
is unspent on the errand — it goes through the same `run_worker_turn`
and the same fold as a dispatched one, and never consults the watermark
— so the answer is picked up, spent by that turn's claim, and delivered
in its continuation packet exactly as an automatic resumption would.

**Only an answer that came through the resident's own intake path buys
a turn.** `_resumable_answers` requires `provenance: requested` and
`seat: intake` — the pair `file_answer` always writes, from the CLI and
the modal alike — so a record of type `answer` that reached the journal
some other way is rendered in the packet (honestly labelled as not
resident-filed) but pays for nothing. That keeps the fold and the
renderer agreeing about what an answer is. It is a filter rather than a
boundary: a writer that passes those two fields satisfies it, and the
guard that actually forbids a tenant answering — `write_record`'s
refusal — rests on an environment variable a tenant could unset
(`docs/backlog/env-stripping-defeats-write-guards.md`; that refusal
covers `correction` as well as `answer`). One consequence
is filed rather than fixed here: a mislabelled answer still makes its
question look closed to `castle answer` and to the picker, so the
question ends up neither closable nor resumable
(`docs/backlog/mislabelled-answer-strands-a-question.md`).

**What resumption is not.** It is not retry — a resumed turn that fails
writes an ordinary `outcome: failed` result and is not attempted again,
because its claim spent the answer the moment the turn started. It is
not a second way to close a question: nothing but the resident's answer
ever closes one, and no timeout or staleness clock resumes an
*unanswered* blocking question, which is a turn correctly waiting rather
than an interrupted one. And it is not authority: the resumed tenant
arrives holding an explicit resident answer, which closes a question and
grants nothing else. The worker proposes and never deploys, on a resumed
turn exactly as on a first.

**Ask first, diff second — resumption doing something concrete.**
Everything above describes the machinery; this is the first errand
shape built on it, and it is a policy stated in the worker prompt
rather than any new code (`docs/tasks/0024-config-target.md`).

A resident says a pointer is hard to see. The layer rule answers the
structural half deterministically — which option, and which of the
private checkout, the host module or the framework it belongs in — and
then stops at the half nothing on disk can answer: how big it should
actually be. That is a perceptual judgment. A tenant that guesses a
number produces a proposal nothing stands behind, and a resident cannot
tell a guess from a derived value by reading it.

So turn one diagnoses, names the option and the layer, says plainly why
the value cannot be derived, files a `--blocking` question, and
**writes no diff and no target**.

What that question may point *at* depends on the host, and the prompt
makes it conditional rather than assuming. The sweep tools
(`tools/font-sweep.sh`, `tools/console-font-sweep.sh`) live in the
public framework repo, which `tools/README.md` is explicit is
developer tooling rather than anything a deployed system installs — so
on a host with no mechanism checkout they exist nowhere the resident
could run them, and that is the normal host. Naming one there would
stop the errand and then hand the resident a path that is not on their
machine. Where a mechanism checkout is configured the tenant names the
real absolute path; where it is not, the question describes what would
settle the value instead. Packaging those tools for a deployed host is
a separate decision this task does not take.

The resident runs the sweep, answers with a number, and
one further turn — a fresh tenant handed that account and that answer —
writes the diff around their number and stamps its target.

This costs two model calls where one would have done, and an errand
nobody answers yields no proposal at all, ever. Both are accepted: the
alternative is a system that proposes values it does not stand behind.

**An empty diff means two different things, and the journal already
tells them apart.** Ordinarily an empty `$CASTLE_DIFF_FILE` means "no
change was warranted" — a considered conclusion. Turn one above also
produces one, meaning something else entirely: the worker asked instead
of concluding. No new field distinguishes them, deliberately, because
the existing pendingness fold already does: an errand whose latest
result carries an empty diff **and** an open, unanswered blocking
question is waiting on the resident, and `castle-modal --mode status`
says so. One with an empty diff and no open question is a considered
no-change.

Anything reading these records to decide whether an errand produced
something to approve **must check for an open blocking question before
concluding it produced nothing** — `docs/tasks/0025` in particular. A
consumer that skips that check silently discards exactly the errands
this shape exists to turn into real proposals later.

### Where a result's diff starts and stops: `diff-boundary`

From `docs/tasks/0025-approval.md`. A `result` record embeds the diff
its turn produced, and something has to be able to say where that diff
ends — the review surface shows the diff as its own section, last and
whole, and shows everything else as the machine's reasoning.

**A markdown fence cannot be that boundary.** The diff is arbitrary
bytes a tenant produced, and a unified diff of a file that itself
contains a fenced code block carries context lines that strip to
exactly ```` ``` ```` and ```` ```diff ````. A reader scanning for a
fence finds one *inside* the diff, closes the block early, and prints
the remainder — real `-`/`+` lines included — as prose. That is not a
rendering wobble on the approval surface: the resident is shown less
than the change they are approving, with the missing part relabelled as
reasoning, on the one screen in this system where authority is granted.

So the boundary is a **nonce**, the same answer `render_continuation_
packet` gives to the same problem (`docs/tasks/0023-resume-cold.md`:
section boundaries are unforgeable, body text is not trusted to be
structure). Eight random bytes, generated when the result is written —
which is *after* the tenant has finished producing every byte of that
diff — so no diff content can contain, spell, move or close it. The
diff is wrapped in `CASTLE-DIFF-<nonce> BEGIN` / `... END` lines and the
nonce is stamped in the frontmatter, where a body cannot reach. The
frontmatter's copy is the only thing that makes a line in the body a
boundary.

The difference from the packet's nonce is that this one has to be
**stored**: the packet is a stream rendered and consumed in one
process, while a record is written once and read months later, so the
token must travel with it.

The markdown fence stays, *inside* the boundary, so the record still
renders as a diff wherever a journal is read as markdown. It is
decoration now, not structure: nothing keys on it.

**As of `docs/tasks/0033-byte-exact-proposal.md`, that "decoration, not
structure" status extends to the entire body copy of the diff, not
only the fence around it.** The body is read through a lenient decode
(`errors="replace"`) and a `splitlines()`-based round trip that both
lose information a real patch can depend on: a stray non-UTF-8 byte, a
CRLF line ending, a form feed, a Unicode line separator, or a missing
trailing newline. None of that matters for what the body is *for* —
showing a human what changed — but it means the body must never be
read back for fidelity. The byte-exact copy is a sidecar file next to
the record; see "The byte-exact sidecar" below.

Validated **when present**, result-only, and shape-checked as sixteen
lowercase hex characters — `blocking`'s and `target`'s treatment, for
the same reasons. Absent means "this result embeds no diff", which is
true of every turn that proposed nothing and of every result written
before the field existed. A reader that meets a proposal whose result
carries no boundary **shows that body whole** rather than guessing:
nothing is hidden, and what is given up is the split, not the content.

### Proposing a change, and deciding it: `proposal-sha256` and `decision`

From `docs/tasks/0025-approval.md`. A worker turn that finishes
`completed`, with a real diff and a resolved `target`, has produced
something the resident could authorize — and until this task, nothing
in the journal distinguished "the resident has authorized this exact
artifact" from "the resident has not looked at it yet."

Two fields close that, and no new record type. A **`question`** is
what proposes; an **`answer`** is what decides. Everything about
lineage, immutability, authorship and routing already works for that
pair, and the one genuine gap — no mechanical way to tell an approval
from a sentence containing the word "yes" — is a field problem, not a
type problem.

**The proposal question is written by the harness, immediately after
the result, and never by the tenant.** `refs` is
`<request-id>,<result-id>`: the request stays `refs[0]`, so every
existing walk attributes it to its errand with no change anywhere, and
the result is `refs[1]`, the same "first ref is lineage, later refs
are context" split `claim` and `result` already use. Its body is one
fixed, harness-authored sentence, which is also what makes it visually
distinct in the answer picker and what a resident reads in the
notification. `seat: worker`, like the claim and the result for the
same turn — a seat is what reads and writes, not who or what produced
a particular record (Proposal 03).

Two properties of that question are **guarantees rather than
conventions**, which is the whole reason the harness writes it:

- **Never `blocking`.** Resumption filters on `_is_blocking` alone, so
  a question that never carries the field cannot enter the resumable
  set, so answering it cannot buy the errand another turn. Were it
  blocking, approving a change would silently re-run the worker and
  produce a second, unauthorized proposal — the sharpest failure
  available in a task that applies nothing.
- **Never `fact`.** `file_answer`'s `resolved_fact` therefore sees
  `None`, so no approve and no reject can write a stated preference
  into the resident model. `file_answer` re-checks anyway, against
  both the question's field *and* a caller-supplied `--fact`, and
  `castle validate` refuses a question carrying both a stamp and a
  fact permanently.

**`proposal-sha256`** is the SHA-256 of the result record's file bytes,
exactly as written — no canonicalization, no field selection, because
field order is stable and records are never rewritten. It is stamped
on the question, re-derived from disk by `file_answer` at write time,
and copied onto the answer. It buys tamper-evidence and nothing more:
under append-only semantics the id already identifies the proposal, and
what the hash adds is that "append-only in spirit" becomes something a
machine can check at the one moment it will matter — a future applier
reading those bytes to mutate a configuration. It is also what lets the
check hold with **no state carried between processes**: the window that
displayed the change and the process that writes the decision both
re-derive the same comparison from disk, so a crash, a closed window,
or a reboot in between costs nothing.

**`decision`** is a closed vocabulary on `answer` records:
`approve`, `reject`, `defer`. Three and not two: without `defer`, a
resident who is not ready either has to reject something they might
want or leave it pending with no recorded signal that they looked —
indistinguishable from never having opened the window. That
distinction is not decoration; `docs/backlog/authority-taxonomy-prior-
art.md` records residents laundering socially costly refusals through
an agent's autonomous tier precisely because the vocabulary gave them
nowhere else to put "not now."

A decision-bearing answer carries `refs:
<question-id>,<result-id>` — the question stays the lineage edge every
closure fold keys on, and the result is carried forward as the thing
actually decided. `castle validate` checks the shape `refs` is now
responsible for: two entries, the second resolving to a `result`, a
stamp present alongside any `decision`, `decision` only on an
`answer`, a stamp only on a `question` or an `answer`, and at most one
decision per question — the last being an honest backstop for the
scan-then-write race `file_answer`'s duplicate guard documents about
itself, not a claim that the race cannot happen.

**`authorizes-apply`** is a second field on the proposal *question*,
from `docs/tasks/0026-apply-validate.md`, and it is what makes an
approval spendable. The literal `true`, stamped by
`_file_proposal_question` on every proposal it files from that task
onward and by nothing else; absent everywhere else, forever.

Absence is not "unknown" — it is a positive fact. Every proposal filed
before that task was decided under a review screen saying in capitals
that approving edits, commits and applies nothing, so approving one
authorized a record and nothing more, and no later change to that
wording reaches backwards. The applier's fold therefore honours only
questions carrying the stamp, and because the journal is append-only
there is no migration, no backfill, and nothing that could ever make an
old approval applyable. That is the point rather than a limitation.

Drawing the same line by comparing timestamps against the commit that
changed the wording would be wrong twice over: record ids are
one-second resolution, and a restored or synced journal has no
defensible relationship between its stamps and this repository's
history. The field travels with the record that was shown.

`castle validate` treats it exactly as `blocking`: question-only, the
one spelling or nothing. A hand-written `authorizes-apply: false` is
inert — the fold is strict in the other direction — but it is not
*visible*, and that check is what names it.

**A pending change waits indefinitely.** No expiry, no auto-approve,
no auto-cancel, no re-ask. That is defensible in this one channel —
nobody else is waiting, the wait cost is about zero, the change is
reversible by design — and it is a posture rather than a strategy;
see `docs/backlog/approval-channel-has-no-transfer-of-control-
strategy.md` before copying it anywhere a third party is on the other
end.

### Applying an approved change: `castle apply` and `apply-outcome`

From `docs/tasks/0026-apply-validate.md`. `castle apply` is the first
thing in this system that changes a resident's configuration. It spends
**exactly one `answer` record** per apply, writes the resident's own
private checkout and nothing else, commits once, optionally builds the
resulting host configuration, and writes one `result` saying which of
those happened. It activates nothing — no `nixos-rebuild`, no `switch`,
no new generation. It pushes nothing, ever. It never touches a checkout
of this framework.

Two forms, mirroring `castle work` and `castle dispatch` deliberately.
`castle apply <answer-id>` is the hand path and is **not** bounded:
re-running it is the retry, exactly as `castle work <id>` is for an
errand. `castle apply --sweep` is what the `castle-apply` systemd user
unit runs, and it is bounded — an approval any result already names is
never applied automatically again, whatever that result said.

The argument is the **answer** id, never the question's: the
authorization is the answer, a proposal authorizes nothing on its own,
and naming the thing being spent is the discipline `refs` already
follows.

**`seat: applier`** — a new value in the existing category, as
`dispatch` was. Not `worker`: a seat is what reads and writes, and this
one reads decisions and sidecars and writes a resident's checkout,
which is a different set. Keeping the names distinct is what lets a
reader ask "which seat touched my repository" and get an answer. Like
dispatch it is plumbing, not a reasoning seat: what it does is a total
function of the journal and the tree, and a policy about which
approvals are worth applying is exactly the authority it must never
acquire.

**What it checks before it touches anything**, in order, each failure
recorded and stopping: that `CASTLE_PRIVATE_ROOT` names a usable
checkout; that the result on disk still hashes to what the *answer*
recorded when authority was granted; that the byte-exact sidecar exists
and matches `patch-sha256`; that `target` says `private`; that the
resident has no uncommitted work under the paths the patch touches; and
that `git apply --check` accepts it. **No fuzz, ever** — no `-3`, no
`--recount`, no `patch(1)`. A patch that does not apply exactly is not
the change the resident approved, and a three-way merge would produce a
change nobody authorized.

Then a working-tree edit and exactly one commit on the current branch,
made with `-c user.name`/`-c user.email` so the resident's `.git/config`
is never written, and with a `:(literal)` pathspec so the commit
contains exactly the patch's paths — not a glob match on one of them —
and their own staged work is neither swept in nor lost. The message
names only ids and the patch digest — no paths, no tenant prose,
nothing that could be resident data — and says in as many words that
nothing was activated.

**The resident's git hooks do not run on that commit**, via
`--no-verify` and `core.hooksPath=/dev/null` (both, since the first
covers only `pre-commit` and `commit-msg`). A formatting `pre-commit`
would otherwise rewrite the very bytes the commit message records a
digest for, and a `post-commit` can commit again — making `rev-parse
HEAD` name a commit the applier never made, with `git revert <sha>`
printed beside it. Their hooks still run on commits they make
themselves. Afterwards the landing is verified rather than assumed:
one commit, parented at the pre-apply head, nothing left uncommitted
under the patch's paths. If it is not, the record is `outcome: failed`
with no `apply-outcome` and no sha — naming an unverified commit beside
a revert command is worse than naming none.

**Nothing is ever rolled back.** No `git reset --hard`, no auto-revert
of a change whose check failed. A hard reset would destroy uncommitted
work the applier did not put there — provably possible, since the
dirty check is scoped to the patch's own paths — rewinding a resident's
history is a larger authority than adding one commit they authorized,
and nothing is activated anyway, so a bad commit is inert until their
own rebuild. "Recovered" is honoured by naming the commit and the
`git revert` for it, not by acting again unbidden.

An **`apply-outcome`** field on the `result` it writes, from a closed
vocabulary, saying what happened to the change:

| Value                      | `outcome`               | The tree | Meaning |
|----------------------------|-------------------------|----------|---------|
| `applied-validated`        | `completed`             | one commit | applied, committed, and the host configuration builds |
| `applied-unvalidated`      | `completed`             | one commit | applied and committed; no evaluation attempted — the body says which of the three gates stopped it |
| `validation-failed`        | `completed` / `timeout` | one commit | applied and committed; the build failed or outlived its bound |
| `applied-uncommitted`      | `failed`                | edited, not committed | the patch applied and the commit did not; the body gives both ways out |
| `refused-target-mechanism` | `completed`             | untouched | the change is to this framework, which this seat has no authority over |
| `refused-artifact-changed` | `completed`             | untouched | a digest no longer matches |
| `refused-no-patch`         | `completed`             | untouched | no sidecar, so no exact bytes to apply |
| `refused-patch-stale`      | `completed`             | untouched | `git apply --check` refused it |
| `refused-tree-dirty`       | `completed`             | untouched | the resident has uncommitted work under those paths |

An **`apply-commit`** field beside it, also result-only, carrying the
commit the apply made — stamped **only** where the landing was verified,
so its meaning is not "a commit happened" but "exactly one commit
landed, parented where this started, nothing left uncommitted, and this
is it." Absent on every refusal and every attempt that reached no
conclusion, matching the body prose, which names no sha there either.
`castle validate` accepts 40 **or** 64 lowercase hex characters: git's
sha256 object format is real, and condemning a resident's own
sha256-format repository would be a validator lying about a perfectly
good journal.

It exists because the body already said this in prose, and a body is not
where a machine may read a fact — this file's own rule, stated for
`outcome` above. `docs/tasks/0027` is the surface that will need it
mechanically. The prose stays for the resident, beside the `git revert`
they would actually type.

Several shapes carry `outcome: failed` and **no `apply-outcome` at
all**, because none of them says anything about the change: an
environment fault, a `target` naming a role this applier has no
checkout for, a `git apply` git never finished, and a commit that
reported success while leaving the repository in a state that
contradicts it. Those records still name the answer, so they still bar
it from a second automatic attempt — which is why `castle-modal --mode
status` renders them as `could not be applied — castle apply
<answer-id> to try again` rather than leaving the errand reading as
though something were still coming. The automatic bar is deliberate;
what the label owes the resident is the hand path.
`castle validate` holds every result written by this seat to one
cross-record rule, whether it carries `apply-outcome` or not: its first
ref must resolve to an `answer` carrying `decision: approve`. An apply
spends exactly one authorization and names it first, so a record that
names something else is claiming one that does not exist. The check is
refs-shape only and deliberately stays that way — it cannot tell a
forged suppressor from a legitimate dead attempt, because in an
append-only journal both look identical, and the status fold already
renders both with the hand-retry remedy. What it owes is that a
malformed one is *named*.

`interrupted` is never written here and never will be — that value is
supplied retroactively by a reaper reading a surviving `claim`, and the
applier deliberately **writes no claim record**, because the reaper
would then offer `castle work <request-id>` as the retry for an apply
that died. An applier killed before it writes anything leaves no record,
and the next sweep finds the approval still eligible and tries once
more. That is the honest behaviour: nothing was written, so nothing was
attempted as far as the journal is concerned.

**`refs: [answer-id, question-id]`, and deliberately not the request.**
`closing_result`'s second clause treats any result naming a claim's
request, newer than the claim and naming no claim of that request, as
the account closing it — so an apply result naming the request would
silently close a genuinely dangling worker claim, and an errand whose
hand-run retry died would be labelled with the *apply's* outcome and
never reaped. Leaving the request out makes the apply invisible to both
that fold and `_errand_state`'s result selection, which is right: an
apply is not a turn of the errand. Lineage still works —
`_find_root_request` walks `refs[0]` transitively and reaches the
request through the answer and the question — so `castle digest`'s
grouping and the router's evidence sentence need no change.

**Validation, when it runs, means exactly two things**: the flake
evaluates and `system.build.toplevel` builds. Not that the change did
what the proposal claimed — nothing anywhere declares that — not that
secrets will decrypt, and not that the configuration will activate. It
is gated on `castle.agent.apply.evaluateFlake` (off by default), on the
state directory not sitting inside the evaluated flake's tracked tree,
and on `nix` existing at all. The exact command line is recorded
whether it ran or not; the full output goes to the ephemeral spool and
forty lines go in the body.

**The forged-approval hole, stated.** `write_record`'s refusal to write
an `answer` from inside a worker turn keys on an environment variable a
tenant can unset (`docs/backlog/env-stripping-defeats-write-guards.md`),
and `castle apply`'s own guard keys on the same variable and is defeated
the same way. Until this task a forged approval was inert; this is the
thing that makes it mutate a configuration. Three things bound it, none
of which is a fix: the tenant is a model this system chose to run rather
than an attacker, nothing is activated, and a stripped write is visible
in the journal as a record with no claim link where its siblings have
one.

### The byte-exact sidecar: `patch-sha256`

From `docs/tasks/0033-byte-exact-proposal.md`. A result's body embeds
the tenant's diff for a human to read, but getting there costs four
lossy transforms: a lenient UTF-8 decode with `errors="replace"` that
destroys any non-UTF-8 byte irreversibly, a `.strip()` that drops the
patch's trailing newline, locale-dependent I/O on both the read and
the write back (no `encoding=` at either `path.read_text()` or
`path.write_text()`), and a `splitlines()`-based round trip that
treats CR, form feed and the Unicode line separators as line breaks
the same way `\n` is. None of that is a defect in what the body is
*for*; it is a defect in trusting the body for anything else. Once an
applier exists (`docs/tasks/0026`), "anything else" is exactly what it
needs: the tenant's exact bytes, undisturbed. This task closes the
locale-dependent I/O transform outright — `parse_record` and
`write_record` now pass `encoding="utf-8"` explicitly, see "Records
are UTF-8 by definition" above — and routes around the other two
(the lenient decode/strip and the `splitlines()` round trip) rather
than fixing them: the sidecar below is read from the raw bytes before
either ever runs, so an applier that reads the sidecar instead of the
body never meets them.

So a turn that embeds a diff writes a second file beside the record,
`<result-id>.patch`, holding the tenant's diff exactly as it wrote it
to `$CASTLE_DIFF_FILE` — read once, before the lenient decode ever
runs, and never modified afterward. `patch-sha256`, stamped on the
result alongside `diff-boundary`, is that sidecar's SHA-256, and it
rides the same gate `diff-boundary` already does: any turn whose
tenant wrote a diff gets one, not only a turn that finished cleanly
and named a resolvable target. Completed-and-targeted is the normal
case, not the rule — a turn killed at `CASTLE_WORKER_TIMEOUT` with a
diff already on disk gets a sidecar too, deliberately: the sidecar
mirrors the body's own diff treatment (a timed-out turn embeds its
possibly-partial diff in the body, labelled as such), and the exact
bytes of a partial diff are precisely what you want when diagnosing a
timeout. `castle validate` checks it regardless of outcome: the
sidecar a stamped record names must exist and must hash to the
stamped value. Absent means "this result embeds no diff," the same
reading `diff-boundary` already gives absence, and `castle validate`
does not go looking for a sidecar nothing names.

**A sidecar from a turn that did not complete cleanly can never reach
the approval channel.** `stamped_target` (`agent/castle:4425`) is set
from `target_text if (diff_text and finished_cleanly) else ""` — a
strictly narrower gate than the sidecar's own — and
`_file_proposal_question` (`agent/castle:4564`) is only ever called
when `stamped_target` is truthy. So a timed-out or otherwise
not-cleanly-finished turn's sidecar sits in the journal with a valid
`patch-sha256`, but no `target` field, no question filed for it, and
therefore nothing for a resident to approve and nothing for 0026's
applier to spend: this is the contract 0026 relies on, not an
incidental consequence.

The sidecar lives inside the journal directory, so `docs/tasks/0030`'s
state-layout rules already cover it with no separate check, and it is
invisible to every existing reader: `load_all` and `cmd_validate` both
glob `*.md` only, so a `.patch` file is never fed to `parse_record` by
anything that walks the journal today.

**The one-sentence distinction from `proposal-sha256`:**
`proposal-sha256` is record-tamper evidence — has this exact record
file changed since the proposal was filed? `patch-sha256` is
byte-fidelity evidence — are these the exact bytes the tenant
produced, unmangled by anything this record format's own transforms do
to a body? The two live on different record types, never the same
file: `patch-sha256` is stamped on the result, `proposal-sha256` on
the question filed for it, so a given result carries `patch-sha256`,
possibly-neither, never `proposal-sha256` itself. A completed, targeted
turn is the only case that produces both records — the result with
`patch-sha256` and the question with `proposal-sha256` — of the
journal entries a single turn can write; a turn that embedded a diff
but was not cleanly completed-and-targeted produces the result and its
sidecar alone, no question, ever.

Like `proposal-sha256`, this is tamper/fidelity evidence only — not a
signature, not an attestation of authorship, and not anything that
applies a change. **`castle apply` is the consumer it was written for,
and it is here now** (see "Applying an approved change," above): the
applier reads the sidecar's bytes and never the body's rendered copy,
re-derives this digest from disk before it touches the tree, and
refuses with `refused-artifact-changed` if the two disagree or
`refused-no-patch` if there is no sidecar at all. `castle validate`
proves the pair for a whole journal on demand; the applier proves it
again for the one record it is about to act on, because "validate was
run at some point" is not the same claim.

### Corrections and filing-time context

A `correction` record (`docs/tasks/0010-correction-record.md`) needs no
new *required* fields — it's `provenance: requested`, `seat: intake`,
same as any other resident word entering through intake — but
`file_correction()` (`agent/castle`, the write path shared by
`castle correct` and `castle-modal`) always stamps a handful of extra
ones, mechanically, at write time:

| Field                     | Meaning |
|---------------------------|---------|
| `surface`                 | Which intake surface captured the words: `cli` or `modal`. The elicitation procedure is itself evidence (preference-construction research: how a preference was elicited shapes what was expressed) and is knowable only at write time — nothing else records it. |
| `context-local-created`   | Local wall-clock time with a UTC offset at filing, e.g. `2026-08-16T21:04:12-0400`. `created` stays UTC, always; time-of-day meaning (evening, morning) is unrecoverable from UTC alone once the machine's timezone history is forgotten. |
| `context-last-notify`     | The id of the most recent notify-channel router `decision` in the journal at filing time — absent (not blank) when none exists. Always resolvable by construction: it's read from the same journal, in the same process, immediately before the write. |
| `context-notifies-1h`     | Count of notify-channel decisions created in the hour before filing. Always present, `0` when none. |
| `context-notifies-24h`    | Count of notify-channel decisions created in the day before filing. Always present, `0` when none. |

Two window sizes, one short and one day-scale, chosen (not derived) to
distinguish "this is the second notification in the last few minutes"
from "today has been a noisy day" even when no single hour looks
unusual; neither claims to be the *right* window for whatever a later
judge does with it.

**These fields make no causal claim.** They record what the journal
showed at the instant of filing — what the system had just done, how
recently, how often — never *why* the resident chose that moment to
speak. Asserting "this correction is about that notification" is the
one causal claim this format allows, and only the resident may make
it, via `--refs`. Honest limit: a notify-channel decision proves a
notification was *attempted*, not that it was seen — delivery
confirmation is Proposal 06's receipt half, and it waits for a surface
that can report reception (`docs/architecture.md`'s sequencing
paragraph).

Transcription into the record body, and into the resident-model entry
below, is mechanical and verbatim — no seat paraphrases a correction,
ever. See `docs/tasks/0010-correction-record.md`'s "Why verbatim" for
the argument.

### Provenance, concretely

`castle route`'s entire rule set, today: a `result` or `question`
record with `provenance: requested` routes to channel `notify`; one
with `provenance: initiated` routes to channel `digest`. No sensors, no
salience estimate — just the one fact the architecture doc identifies
as doing more channel-selection work than anything else, because it's
a fact rather than a judgment. A worker propagates the provenance of
the request it's fulfilling onto its result (and any `question`) record
— see `test/agent-loop/scripted-worker.sh` for the reference
implementation of that propagation. `correction` records are never
part of this rule set — see `castle route`'s bullet above for why that
has to hold forever, not just today.

## Where state lives

- **The journal** — the durable log — lives under
  `$CASTLE_STATE_DIR/journal/` if that environment variable is set,
  else `$XDG_STATE_HOME/castle/journal/`, else
  `~/.local/state/castle/journal/`. Flat directory, one file per
  record: folds are cheap at this scale, and a flat directory keeps
  `grep`/`ls` working as the primary way to look at it, per
  `docs/tasks/0008`'s pre-made decision.
- **The runtime directory** — everything machine-local and
  session-lifetime resolves through one place: `$XDG_RUNTIME_DIR/castle`
  if that variable is set, else `/run/user/$UID/castle` if that
  directory exists, else `/tmp/castle-$UID`. The middle branch matters
  because `$XDG_RUNTIME_DIR` is unset in exactly the contexts most
  likely to run `castle work` beside a dispatch unit — ssh, cron, `su`
  — and `/run/user/$UID` is where systemd's user manager points that
  variable, so preferring it puts every caller on one host in one
  place. For the spool that is tidiness; for the locks below it is
  correctness (a lock in a different directory is not a lock at all).
- **The spool** — ephemeral, machine-local, never committed — lives
  under `<runtime>/spool/`. Same record format; `castle record --spool`
  writes there instead of the journal. Delete it any time; nothing
  durable is ever spool-only.
- **Leases** — `<runtime>/leases/<request-id>.lock`, plus two siblings:
  `dispatch.lock` for the global sweep and `route.lock` serializing the
  router's fold (`docs/tasks/0021-auto-dispatch.md`). Not records and not spool
  entries: `RECORD_TYPES` is schema forever, and "a worker currently
  holds this errand" is an ephemeral liveness fact with the lifetime
  of a login session, not a message one seat is sending another. A
  lock, not a record. `flock` on a plain file rather than a PID file
  with a staleness check, because the kernel releases a flock the
  instant its holder exits — for any reason, including a crash — so a
  stale lock is detectable race-free by the next acquirer. Two callers
  that resolve the runtime directory differently are not excluding each
  other at all — one would reap the other's live turn as interrupted —
  which is why that resolution is shared and why `castle dispatch`
  refuses to run unattended when it lands on the world-writable `/tmp`
  branch (any local user could squat a lock there and wedge the sweep
  silently green). A hand-run `castle work` still accepts it: a human
  is present to notice. The file's
  contents (start time, request id, tenant command) are informational
  only; nothing reads them back. A leftover, unheld lease file means
  nothing on its own — the journal says what happened, and a `claim`
  with no live lease and no result is what `castle dispatch` reaps.
  The lease is **machine-local by design**, which carries one honest
  limit: enable dispatch on at most one host per journal. Two
  dispatch-enabled machines sharing a synced state directory would work
  the same request twice and write false `interrupted` results at each
  other, because nothing reconciles two dispatchers over one journal —
  that belongs to whatever task designs journal sync, and nothing here
  pretends to solve it.
- **`modules/agent`** (this flake's `nixosModules.agent`) installs the
  `castle` CLI and declares `castle.agent.stateDir`, which — when set
  by a private layer — is wired into `CASTLE_STATE_DIR` via
  `environment.sessionVariables`, i.e. PAM-set for every session, not
  just a login shell — see that module's `config` comment for why the
  distinction is load-bearing (docs/tasks/0013-first-deploy-findings.md:
  a greetd-launched Sway session, and `castle-modal` spawned from it,
  never sourced the login-shell-only variant). See
  `docs/private-layer.md` for what a resident actually points that at
  (a durable, git-tracked directory, so the journal survives a
  reinstall — deliberately *not* a subdirectory of the flake repo,
  whose tracked tree is copied into the world-readable Nix store on
  every rebuild; docs/tasks/0030-state-outside-the-flake.md).
- `CASTLE_STATE_DIR` is also what makes `test/agent-loop/run.sh`
  possible without touching a real resident's journal: it points every
  `castle` invocation in that harness at a throwaway temp directory.

## The resident model

Living at `resident-model.md` in the state directory
(`docs/private-layer.md`) as a sequence of entries in the same flat
frontmatter style as records above (though the file itself is not a
`castle`-managed record: no `id`/`type`/`refs`), one entry per fact,
each carrying its own provenance per Proposal 05 (`docs/architecture.md`).

**The journal is the source of truth; this file is a derived,
regenerable view over it — not a second source of truth.** Every entry
today is a near-copy of the journal records it cites (a question and
its answer, or a correction), which is what makes that framing more
than a slogan: nothing is lost if the file is ever rebuilt from the
journal by a better judge, because the journal already holds everything
the entry does. That's also what makes a future normalization pass
*legitimate* — collapsing several verbatim entries about the same
thing into one is rebuilding the view, not editing an authoritative
record — rather than an append-only violation. Day to day, though, the
file is append-only, same as the journal, for the same reason: nothing
here is ever edited in place.

Two entry shapes exist, distinguished by which pair of fields they
carry — never both:

- **Elicited** (`asked`/`answered`) — the system asked, the resident
  answered. `docs/tasks/0008-agent-layer-skeleton.md` shipped the
  format with zero tooling; `docs/tasks/0009-ambient-intake.md` built
  the write path, and it is narrow on purpose: `append_model_entry()`
  in `agent/castle` is reached only through `file_answer()`, which has
  exactly two callers — `cmd_answer` (a human typed an answer at this
  CLI) and `castle-modal`'s answer mode (a human picked a question and
  typed an answer at the modal). Both are narrow, and both reach the
  same function rather than each performing the write, exactly as the
  correction path's own two callers both reach `file_correction()`
  (`docs/tasks/0022-answer-in-ui.md`). The fact name comes from the
  `question` record's own `fact` field by default (the seat that raised
  the question is the one that knows what it's eliciting), or from
  `castle answer --fact NAME` explicitly — a CLI-only override, because
  the fact is the declaring seat's to name and a resident typing one at
  answer time would make the model's key space free text under neither
  documented entry shape. The entry's body is the literal question and
  answer text, not a summary.
- **Volunteered** (`provenance: volunteered` / `stated`) — the resident
  spoke unbidden; nobody asked (`docs/tasks/0010-correction-record.md`).
  `stated` plays the role `asked`/`answered` play above: it's the id of
  the `correction` record this entry came from. Absence of `provenance`
  continues to mean elicited, so every entry written before this second
  shape existed still parses as exactly what it always was.
  `append_model_entry()`'s *other* caller, `file_correction()`, is just
  as narrow: reachable only from `castle correct` and `castle-modal`'s
  classification step, never from `cmd_route` or `cmd_work`.

No entry, of either shape, is ever a summary. This tool has no
interpretive capability to summarize with, and per Proposal 05 (and,
for corrections specifically, `docs/tasks/0010`'s load-bearing "no seat
paraphrases a correction, ever") it should not gain one; the honest
account of what was asked/said, or what was volunteered, is the whole
entry. Behavioral signal may raise a question's priority or mark an
entry stale; it may never write one, of either shape.

Two worked examples (values below are invented, obviously-fake — nothing
here describes any real resident):

```
---
fact: cursor-fix-posture
asked: 20260816T130200Z-question-9f2a11
answered: 20260816T130700Z-answer-c04dd2
when: 2026-08-16T13:07:00Z
---

Q: Fix it and tell you afterward, or hand you the line and explain it
first?
A: Fix small perceptual issues like this one and tell me afterward.
Elicited once, from one low-stakes errand — may not generalize to
changes with real consequences if reverted.
```

```
---
fact: You pinged me about something that could have waited
provenance: volunteered
stated: 20260816T210412Z-correction-3f9c2a
when: 2026-08-16T21:04:12Z
---

You pinged me about something that could have waited until the digest.
```

Both are `append_model_entry()`'s actual rendered format, not a
paraphrase of it — every word after the frontmatter fence in each
example is exactly what the resident typed (the elicited entry's
literal `Q:`/`A:` lines; the volunteered entry's correction text
unchanged), kept verbatim rather than summarized. For the volunteered
shape, `fact` is nothing more than the correction's own first line,
mechanically sliced to 80 characters — not a generated label, not a
classification, just less of the same verbatim text.

A private layer's `resident-model.md` ships as an empty file (or
absent entirely) until the first elicited answer or volunteered
correction gives it a first entry — see
`docs/tasks/0008-agent-layer-skeleton.md`'s real-errand verification
plan for how that first entry gets written on the reference host.

## Testing

Seven harnesses, all plain bash and stdlib Python — no Nix involved,
unlike `test/vm-install/`'s harness — runnable locally with nothing
beyond `bash`, `python3` and `git` on `$PATH`:

```
test/agent-loop/run.sh                   # the full loop, both channels, the router-bug regression, Proposal 05's write path
test/agent-loop/tenant-swap.sh           # runs run.sh twice with two differently-shaped workers, diffs the outcome
test/agent-loop/modal-headless-test.sh   # drives castle-modal with canned stdin, zero compositor
test/agent-loop/dispatch-test.sh         # the automatic-dispatch sweep: watermark, lease, claim, reaper, outcomes
test/agent-loop/resume.sh                # an answered blocking question resumes its errand, cold, exactly once
test/agent-loop/config-target.sh         # two real checkouts: which one a diff targets, and what happens when one is missing or broken
test/agent-loop/approval.sh              # the resident approves, rejects or defers a proposed change — and nothing moves
```

`test/agent-loop/pty-drive.py` is not a harness: it is the shared pty
driver `modal-headless-test.sh` and `approval.sh` both use to type at
an interactive program and read what it printed back.

**`git` is a real prerequisite, not just python3.** Four of the seven
need it: `config-target.sh` and `approval.sh` build their fixture
checkouts with `git init` and `git archive`, and `dispatch-test.sh`
and `resume.sh` each `git init` the private root the target pre-flight
now requires (`docs/tasks/0024-config-target.md`). On a host without
it those four die with `git: command not found` rather than failing an
assertion.
`modules/dev` supplies it, exactly as it supplies python3 — the same
shape `docs/tasks/0029-python3-on-dev-hosts.md` fixed for the
interpreter, and named here in the same breath so the next person
reading this paragraph learns both prerequisites at once.

On a dev host importing `modules/dev`, python3 is on `$PATH`. Without
that module, use `nix shell --inputs-from . nixpkgs#python3 --command bash
test/agent-loop/run.sh` (or another harness name) — the `--inputs-from .`
resolves python3 through the repo's locked nixpkgs, ensuring the same
interpreter as the deployed CLI.

- **`run.sh`** (the `agent-loop-test` CI job) runs the whole loop —
  intake, router, a scripted worker, router again, digest — with zero
  models and zero network. Both canned errands now also raise a
  mid-errand `question` before their `result` (docs/tasks/0009 item 7's
  third gap: nothing previously produced one in CI); the requested
  errand's question is answered for real via `castle answer`, and the
  script asserts the resulting `resident-model.md` entry cites
  the right question/answer ids — Proposal 05's write path, exercised
  end to end rather than just documented. It also plants a decision
  record from a non-router seat referencing an unrouted result and
  asserts the router still routes it — the regression test for
  `docs/tasks/0009` item 7's router bug fix. `CASTLE_AGENT_LOOP_WORKER`
  overrides which script holds the worker seat;
  `CASTLE_AGENT_LOOP_SUMMARY_OUT`, if set, gets a normalized summary of
  the resulting journal written to it before the script exits.
  `docs/tasks/0010-correction-record.md` added: `castle correct`'s
  write-path-discipline regressions (empty body, a nonexistent `--refs`
  id, a real one surviving round-trip); both filing-time context
  branches (a fresh notify-channel decision, then a correction citing
  it via `context-last-notify`, with `context-notifies-1h`/`-24h` ≥ 1
  and `context-local-created` parsing as a UTC-offset timestamp; and a
  correction filed against an empty journal, where the counts are `0`
  and `context-last-notify` is absent); a proof that re-routing after
  filing corrections appends no decisions, cites none of them, and
  fires no new notification; and a check that `castle digest` renders
  the corrections filed above. This task (adding `considered`/
  `propensity`) added: every decision `castle route` writes carries
  `considered: notify,digest` and `propensity: 1.0`; a decision written
  the pre-existing way (via `castle record`, with neither field) still
  validates clean, proving backward compatibility for real rather than
  just asserting it; and `castle validate` rejects a hand-planted
  decision with `propensity` out of `[0,1]`, an empty `considered`, or
  a `channel` that isn't a member of `considered`.
- **`tenant-swap.sh`** (also wired into the `agent-loop-test` job) is
  Proposal 03's hardening test, second half: it runs `run.sh` twice —
  once with `scripted-worker.sh` (bash), once with
  `scripted-worker-alt.py` (a deliberately different shape) — and
  diffs `normalize_journal.py`'s id-stripped fingerprint of each run's
  journal. An exact match proves the worker seat was re-tenanted with
  no structural change, without running a real model in CI.
- **`modal-headless-test.sh`** (the `modal-headless-test` CI job) pipes
  canned stdin at `castle-modal` in every mode and asserts on the
  request record compose mode produces and the fold status mode
  renders — no `foot`, no Sway, no display server anywhere in the
  script, proving the modal's logic is driveable independent of the
  compositor that will normally launch it. `docs/tasks/0010-correction-
  record.md` added: `--kind correction` filing a correction record plus
  its volunteered resident-model entry; the no-flag path still filing a
  plain request (backward compatibility for every pre-existing piped
  caller); status mode never showing a correction; and, on the same pty
  pattern the dismissal-hold regression already used, an interactive
  run proving the plain-language classification prompt appears with
  both labels and that the feedback key files a correction while the
  fix key and bare Enter both file a request.
  `docs/tasks/0021-auto-dispatch.md` added: each of the four `outcome`
  values producing its own `_errand_state` label; a planted `claim`
  reading as "in progress" while a helper process holds a real `flock`
  on the errand's lease, and as interrupted the moment that holder
  dies; and the `", waiting on you"` overlay still composing with an
  outcome label (that overlay now reads `", waiting on you — press
  Mod4+Shift+a to answer"`, and the assertions were updated with it —
  docs/tasks/0022). Two more came from a later review pass: an errand
  never takes its state from a follow-up filed against it with
  `castle ask --refs` (the fold is transitive, the turn state is keyed
  to the request), and answering one question does not silence the
  next one raised on the same errand. Every pre-existing state
  assertion in the file is unchanged — in particular that a result
  with no `outcome` field still reads as "done".
  `docs/tasks/0022-answer-in-ui.md` added twelve more, all of answer
  mode, driven on the same pty pattern through one reusable driver:
  nothing pending printing its friendly line; a question picked,
  answered, and its record's `refs` naming exactly that question; two
  pending questions with `2` answering the second and leaving the first
  waiting; a positive assertion that no record id and none of the
  journal's vocabulary appears in what the resident saw; a dismissal
  leaving the journal's file count and the resident model's byte length
  untouched; an empty answer refused; the `--question` script path and
  each of its refusals; an interactive session ignoring `--question`;
  a fact-carrying question producing the elicited entry while the modal
  says only "Noted — I'll remember that."; the CLI refusing a second
  answer; ten pending questions showing nine and naming the rest; and
  status mode holding its window open on both of its exit paths. That
  section runs against its own state directory with every question
  planted at an explicit id, because a picker keyed to screen position
  cannot be asserted on against a journal the tests above it are still
  accumulating.
  `docs/tasks/0025-approval.md` added a review-mode section, planted
  by hand into a state directory of its own for the same reason: a
  rendering assertion needs a body whose every line is known. It
  proves a change picked out of the *answer* picker branches into
  review rather than into free text; that the four sections appear in
  the order the design turns on, checked by line number rather than by
  presence, since four greps in any order prove no ordering at all;
  that no record id and none of the internal vocabulary appears in the
  text the tool itself adds, nor the store path and record id the
  result body's own harness-written header carries; and — the part
  that would otherwise be prose nobody checks — that the window-resize
  shell-out really is attempted on the interactive path, really is not
  on a piped one, and really is skipped when the environment variable
  is set to the empty string.
- **`dispatch-test.sh`** (the `dispatch-test` CI job,
  `docs/tasks/0021-auto-dispatch.md`) drives `castle dispatch` — the
  sweep a systemd path unit and timer trigger on a real host — by hand.
  It proves: the watermark is written exactly once and a request filed
  before it is never auto-started; `castle dispatch --watermark-only`
  — what the session-start unit runs — establishes that boundary
  without claiming, working, or routing anything, writes it exactly
  once however often it runs, and a later full sweep honours it; an
  eligible request gets exactly one turn whose result the same sweep
  routes; a second sweep over an
  already-worked journal writes nothing (asserted on record counts, not
  on the process exiting, since the sweep writes into the directory the
  path unit watches and must not retrigger itself forever); two
  concurrent sweeps produce exactly one claim and one result; a
  hand-run `castle work` is refused, silently writing nothing, while
  another turn holds the lease; a failing tenant, a signal-killed
  tenant, an empty `CASTLE_WORKER_COMMAND`, and a command that isn't a
  real binary all produce `outcome: failed` and are never retried
  automatically; a hanging tenant under `CASTLE_WORKER_TIMEOUT=2`
  produces `outcome: timeout` in seconds rather than its full sleep; a
  planted claim with an absent or stale lease is reaped into an
  `outcome: interrupted` result that then gets routed; a request a
  tenant filed mid-turn is stamped, never auto-started, and still
  runnable by hand; an `answer`
  filed against a **non-blocking** question on an already-worked errand
  does **not** make it eligible again, while the same shape marked
  `--blocking` **does** — the two sit side by side in the file
  deliberately, since the contrast is the whole proof that resumption is
  opt-in rather than firing on any answered question
  (`docs/tasks/0023-resume-cold.md`); corrections stay unrouted even when dispatch is what
  triggers the router; and `castle validate` passes throughout, not
  just at the end. Its `contract-worker*.sh` fixtures are also the
  only place the *real* `castle.agent.worker.command` contract — body
  on stdin, reasoning on stdout, a diff to `$CASTLE_DIFF_FILE` — is
  exercised: `run.sh`'s scripted workers are invoked positionally and
  bypass `cmd_work` entirely, and they stay that way so
  `tenant-swap.sh`'s comparison keeps meaning what it means.
- **`resume.sh`** (also in the `dispatch-test` CI job,
  `docs/tasks/0023-resume-cold.md`) drives errand resumption end to end
  through `castle dispatch`, never by hand-building the journal with
  `castle record` — the continuation packet, `CASTLE_RESUME_ANSWER_IDS`
  and the claim's widened `refs` all live inside `run_worker_turn`, and
  only a real turn reaches them. Its tenant,
  `scripted-worker-blocking.sh`, files a `--blocking` question and
  produces nothing else on its first invocation, and on a resumed one
  echoes back what it found on stdin — the original request's text, the
  question's text and the resident's answer, each as its own greppable
  line, so an empty or malformed packet fails the run instead of passing
  it on the strength of a second claim existing. It proves: an answered
  blocking question produces exactly one new claim and one new result,
  with the answer named in that claim's `refs`; an *unanswered* one
  produces nothing, however many sweeps run; two sweeps back to back,
  and two racing under `CASTLE_TEST_WORKER_SLEEP`, produce one
  resumption between them rather than one each; an answered
  **non-blocking** question resumes nothing; a resumed turn that fails
  is not retried automatically, and its answer stays spent; the tenant
  can be swapped between the first turn and the resumed one without
  breaking resumption, which is Proposal 03's re-tenanting claim inside
  a single errand rather than across whole runs; and the resumed
  result is routed like any other, with `castle validate` and
  `check_assertions.py` passing throughout.
- **`config-target.sh`** (also in the `dispatch-test` CI job,
  `docs/tasks/0024-config-target.md`) is the first harness here to
  build the worker two *real* checkouts rather than one bare `mkdir`:
  a mechanism one exported from this repository's own tracked content
  at `HEAD` with `git archive` (committed content only, so no
  untracked file from a developer's worktree can leak into a fixture,
  and the module surface a tenant reads is the current one), and a
  synthetic private one whose every literal is a placeholder this repo
  already publishes. `CASTLE_STATE_DIR` points inside the private
  checkout, making the documented state-dir-inside-the-private-repo
  relationship real rather than asserted in prose.

  It proves: a private-layer errand's diff lands in the result body
  with `target: private` in the frontmatter and the resolved path in
  the prose beside it; a turn with no private root configured, and one
  whose private root exists but is not a git working tree, both refuse
  with an `outcome: failed` result that names the option and leaves a
  claim the result closes; a configured-but-unusable *mechanism* root
  does **not** refuse — the turn completes, targets private, and
  carries the harness-level mechanism-unusable note anyway — while a
  mechanism-shaped errand under the same configuration proves the
  tenant received `$CASTLE_MECHANISM_ROOT_INVALID` and described a
  misconfiguration as one rather than as an absence; a mechanism
  errand with a usable root stamps `target: mechanism`; the
  sibling-coupling rule, checked against a second private checkout
  with no `cursorTheme`, where a `cursorSize`-only diff would be a
  silent no-op; the ask-first-diff-on-resumption path end to end, with
  turn one writing no diff and no target and the resumed turn's diff
  built around the resident's own number; that turn one's empty diff
  reads as "waiting on you" through `castle-modal`'s own status fold
  while a completed errand in the same listing does not, which is the
  concrete proof that no new field was needed to tell the two meanings
  of an empty diff apart; and, after every turn, that both checkouts'
  working trees and both `HEAD`s are unchanged — the worker's
  no-deploy boundary as a check rather than a comment.

- **`approval.sh`** (also in the `dispatch-test` CI job,
  `docs/tasks/0025-approval.md`) reuses that fixture shape for the
  same reason it exists: `assert_checkouts_untouched` after every
  single scenario, because a task whose whole promise is that it
  applies nothing has to say so with a check.

  It proves: a completed, targeted turn files exactly one change to
  decide, non-blocking, carrying no fact, with `refs` naming the
  errand and the exact result and a stamp `sha256sum` independently
  agrees is that result file's hash; all three verdicts through both
  write paths, the CLI and a pty-driven `--mode review`; and every
  refusal — an ordinary answer against a change from either surface,
  `castle record --decision`, a second decision, a change altered on
  disk (with, as the control, the same change becoming decidable again
  once its exact bytes come back), a change altered *between* being
  rendered and the keypress landing, a hand-planted change that also
  elicits a fact, and `--fact` supplied beside `--decision`. Ten
  planted records exercise the validator's permanent gate, each with a
  control that would catch a validator refusing everything.

  Two of its proofs are behavioural rather than structural, and both
  matter more than the assertions around them. After an approval it
  runs two full dispatch sweeps and requires that no further turn
  happened — the record-shape check for "not blocking" would not
  notice a future change making answers to it resumable. And one
  decision runs under a `$PATH` where `nixos-rebuild`, `systemctl`,
  `sudo`, `git` and friends are stubs that log their own invocation:
  nothing may be *reached for*, not merely nothing moved. A grep over
  the source was tried first and is the wrong tool — both files are
  full of those commands named in comments explaining why they are
  never run.
