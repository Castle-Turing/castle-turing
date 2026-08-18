# Task 0022 — Answer questions in the UI

**Before starting:** read `CLAUDE.md`, `docs/vision.md` (especially the
founding sentence this task exists to serve — "its rarest output is a
small, well-timed question that exists to refine its model of your
priorities"), `docs/architecture.md` (the Seats section — Intake and
Router — and Proposals 05 and 06), `agent/README.md` (the `castle` CLI
section, the `castle-modal` section, and "The resident model"),
`docs/tasks/0010-correction-record.md` (the correction record, and
`file_correction()` as the precedent for "the modal is castle's
functions wearing a different hat") and
`docs/tasks/0015-filed-not-in-progress.md` (the "a label must not cause
the inaction it describes" rule this task applies a second time). Then
the code this task extends, closely: `agent/castle-modal` (the whole
file — 467 lines), `agent/castle`'s `write_record`,
`load_journal_record`, `append_model_entry`, `file_correction`,
`cmd_record`, `cmd_ask`, `cmd_answer`, `cmd_correct`, `_find_root_request`,
`_route_journal_locked` (including its notification call), and the
`build_parser` section at the end of the file. Also
`modules/home/default.nix`'s keybinding attrset and the long priority
comment above it (~200–340), and the `window.commands` floating rule
(~400–410); `.github/workflows/check.yml`'s expected-keybinding grep
list (~210–265); `flake.nix`'s `example-mod4` block and its two
keybinding assertions; `test/agent-loop/modal-headless-test.sh` (the
whole file — the pty driver, `read_until`, and the 0.2s cbreak-gap
sleep this task's new pty tests reuse); and `test/desktop-loop/test.nix`
(the whole file — the VM harness this task extends with one more
segment). Finally, `docs/backlog/README.md` (entry shape) and
`docs/backlog/errand-resume-after-answer.md` (the mechanism this task
deliberately does not build, and the honest sentence its confirmation
text has to say instead). Work on branch `sprint/0022-answer-in-ui`,
based on `sprint/0021-auto-dispatch` (this task reads dispatch's
`claim`/`outcome`/eligibility machinery and must not diverge from it).
This brief rides the branch. The PR this branch opens is stacked on
0021's own, still-open PR: its base is `sprint/0021-auto-dispatch`, not
`main`, and it must not be merged before 0021's PR is. It retargets to
`main` only if and when 0021 merges first — the human makes every merge
decision, including the order these two land in.

**Goal.** A resident who is told Castle needs input can read the actual
question and answer it from the same modal they already use for
compose and status — one chord, plain language, no record id, no
`castle answer` typed anywhere — while every invariant that makes the
journal an honest, append-only account stays intact.

## Why

The vision's founding sentence draws the shape of the whole system: the
agent's rarest output is "a small, well-timed question that exists to
refine its model of your priorities." A question economy built on that
premise is worthless if answering one requires the system's own internal
vocabulary — a record id copied out of a terminal, the word "seat," the
distinction between a journal and a spool. Today that is exactly what
answering requires: `docs/tasks/0009-ambient-intake.md` gave workers a
way to raise a `question` mid-errand and the router a way to deliver it,
and `docs/tasks/0021-auto-dispatch.md` (this branch's base) made the
whole loop up to that point automatic — a resident's request starts
itself, runs, and its question reaches a notification with no `castle
work` or `castle route` typed by hand. But closing that question still
means opening a terminal and typing `castle answer <id>`, where `<id>` is
a timestamp-prefixed string the resident has to find first. The modal
already carries the resident's two other kinds of speech — describing a
problem (compose), and volunteering feedback unbidden (compose's
classification step, `docs/tasks/0010-correction-record.md`) — and does
not yet carry the third: closing a question the system asked. This task
adds it.

Proposal 05 (`docs/architecture.md`) is explicit that only the resident
may close a question the system opened; Proposal 06 is explicit that
receipts (a window opened, a keypress made) and verdicts (what the
resident actually said) carry unequal authority, and that a delivery
surface may not manufacture the latter out of the former. Both bear
directly on this task's shape: the modal must make answering easy without
quietly widening what counts as an answer, and without the surface itself
starting to grade what it delivered.

**Invariants preserved, stated once so every section below can assume
them:** only the resident closes a question. The answer is an
append-only `answer` record referencing the exact question it closes.
A resident-model entry is written only where the existing fact rule
already calls for one — no new trigger for that write path. Questions
stay routed through the router; this task adds no second delivery
mechanism. Viewing or dismissing a question is never recorded as
answering it. Multiple pending questions are handled deterministically,
never by guessing which one a resident meant. Internal ids may appear in
diagnostic and script output — `castle answer`'s stdout, a `--question`
script invocation's stdout — but never as input the resident is required
to type or read to use the interactive surface.

## Scope

### 1. `file_answer()` — extracted in `agent/castle`

A new module-level function, alongside `file_correction()` and built on
the same reasoning: `file_correction()` was extracted from `cmd_correct`
specifically so `castle-modal` could reach the identical write path
rather than reimplementing it in its own words — "the modal is castle's
functions wearing a different hat" (`docs/tasks/0010`). `cmd_answer`
today has never been split that way; this task splits it, for the same
reason a second caller is about to exist.

```python
def file_answer(*, question_id: str, body: str, fact: str | None = None) -> tuple[str, str | None]:
```

It owns **every** pre-write check, so no caller — CLI or modal — can
skip one:

1. `body` non-empty after `.strip()`.
2. `question_id` resolves via `load_journal_record` — exists and parses.
3. The resolved record's `type` is `question`.
4. **New**: an immediate pendingness re-check, run right before the
   write — read every `*-answer-*.md` file in the journal and refuse if
   any one's `refs` already contains `question_id`.

   *(Corrected during implementation — review round 1, finding 8. This
   originally folded over `load_all`, which skips any file that fails to
   parse: one corrupt answer record would have silently re-opened the
   duplicate this guard exists to close. The scan is strict instead —
   each `*-answer-*.md` is parsed directly, and a file that does not
   parse raises rather than being passed over. The read surfaces keep
   using `load_all` and stay tolerant on purpose: a picker that renders
   nothing at all because of one bad record is worse than one that shows
   the rest, while a guard deciding whether to write has the opposite
   duty.)*

Every refusal raises one new module-level exception,
`AnswerRefused(Exception)`, carrying a machine-usable `kind` (a short
string: `"empty_body"`, `"no_such_record"`, `"wrong_type"`,
`"already_answered"`, `"unreadable_answer"`) plus whatever detail that
kind needs — for `already_answered`, the existing answer record's id;
for `unreadable_answer`, the path that would not parse. One exception type
with a `kind` field, not four exception classes, because every caller of
`file_answer` needs the same dispatch (map kind to wording) and a single
type with a discriminant is the smaller surface for that. Each caller —
`cmd_answer`, the modal — renders its own wording from `kind`; nothing
about the wording lives inside `file_answer` itself. `file_answer` prints
nothing, ever: that is what lets `cmd_answer` keep its existing internal
stderr line (the `recorded resident-model entry for fact '...'` line,
which names an internal fact key and must never reach the modal) while
the modal speaks a different, plain-language sentence over the identical
underlying write.

*(One deliberate exception, added during implementation — review round
1, finding 3. The `append_model_entry` call is wrapped in
`try/except OSError`, and on failure `file_answer` prints one stderr
diagnostic naming the filed answer id and returns `(record_id, None)`.
Letting that exception escape would cost the resident the answer they
just typed — the CLI never printing its id, the modal closing on a
traceback in zero frames — and, because the already-answered guard now
refuses a retry, would make it unrepeatable forever. The model is a
derived, regenerable view over the journal (`agent/README.md`), so the
entry can be re-derived from the question and answer records; the record
cannot be recovered. The rule this bends exists so no caller inherits
another surface's **wording**, and a mechanism fault is not surface
wording: neither caller can render this one — the CLI would have to
re-detect it, and the modal's vocabulary rule forbids it from saying it
at all, while neither may lie about what happened.)*

On success, `file_answer`:

- Writes the `answer` record exactly as `cmd_answer` does today —
  `type="answer"`, `provenance="requested"`, `seat="intake"`,
  `refs=[question_id]` — via `write_record`.
- Applies the existing Proposal 05 model rule verbatim, unchanged in
  every particular: `fact` is the explicit `fact` argument if given, else
  the question record's own `fact` field; if the resolved value is
  non-blank after `.strip()`, append the elicited resident-model entry
  (the literal `Q:`/`A:` body shape, `asked`/`answered` citing the
  question and the new answer's ids) via `append_model_entry`, and return
  that fact string. If blank, write no entry and return `None`.
- Returns `(answer_id, recorded_fact_or_None)`.

`cmd_answer` becomes a thin wrapper around it: resolve `body` from argv
or stdin exactly as today, call `file_answer`, and on `AnswerRefused` map
`kind` to a stderr message and return 1. Three of the four kinds keep the
**exact existing wording**, unchanged character for character —
`"castle answer: refusing to file an empty answer"`,
`"castle answer: no such record: {question_id}"`, and
`"castle answer: {question_id} is not a question record (type={type!r})"`
— because these are load-bearing habit for anyone who already knows this
CLI, and rewording them for no functional reason churns every script and
memory built against them for nothing. The fourth, `already_answered`,
is new; its message names the existing answer's id (CLI diagnostics may
freely carry ids — the no-ids rule in §2 binds the resident-facing modal
surface, not this one). Exit code stays 1 on any refusal, 0 on success,
unchanged. The existing
`"answer: recorded resident-model entry for fact '...'"` stderr line
moves out of `file_answer` and into `cmd_answer` itself, printed iff a
fact came back non-`None` — byte-for-byte what it prints today, just
printed by the wrapper instead of the function that used to do both jobs
at once.

**Behaviour change, stated explicitly because it is real and not purely
mechanical:** `castle answer` on an already-answered question changes
from silently appending a *second* answer record (and, for a
fact-carrying question, a duplicate resident-model entry) to a refusal.
Today's code has no such guard — nothing stops a second `castle answer
Q1 "..."` from writing a second `answer` record with the same `refs`.
The reason to add the guard now, in the shared function rather than only
in the modal: two answer records referencing the same question make
"pending" ambiguous for every later reader — including task 0023's
eventual errand-resumption mechanism, which will need to ask "is this
question still open" and get one answer. If the check lived only in the
modal, the CLI and the modal would disagree about what "pending" means —
exactly the two-surfaces failure `docs/tasks/0015` scope 3 already names
as worse than either surface being wrong alone. This is deliberately
**not** a lock. The journal is one file per record, so two writers can
never physically conflict — `flock` protects a shared *resource*, and
there is none here to protect. The realistic case this guard actually
catches is not two processes racing; it is a stale modal window left
open from an earlier session, reused after the question was already
answered elsewhere, which now produces a legible refusal instead of a
silent duplicate. The narrow race between the pendingness check and the
write — another writer answering the same question in the interval — is
accepted and documented in the function's own comment: at most one
duplicate answer could theoretically land, on a single-resident machine,
in a window measured in microseconds, and the cost of closing it (a lock
around a data model that was built specifically to need none) is larger
than the residual risk.

`castle answer --fact` stays exactly as it is today, CLI-only. The modal
exposes no way to supply or edit a fact name at answer time — see §2's
non-goal on this point; the reasoning is that the seat which raised the
question already declared, at write time, what it elicits (Proposal 05),
and a resident-typed fact name would make the model's key space free
text entered under neither of the two documented entry shapes
(`agent/README.md`'s "Two entry shapes exist... never both").

### 2. `castle-modal --mode answer` — a third mode

**Why a third mode, not folded into an existing one.** Compose mode's
whole premise is "describe a problem and walk away" — no picker, no
list, nothing between the keybinding and typing. Putting a question
picker in front of that would change the one flow that already works,
already has muscle memory, and has already absorbed two pty regressions
(the 0009 dismissal-hold fix and the 0010 classification-prompt cbreak
ordering fix) that a redesign risks reopening. Status mode is the wrong
home for the opposite reason: status is a *read* surface — "come back
and check in later" — and answering is a *write*. The status surface
does not grow an answer flow; it grows a pointer to this one (§3).

**The pending fold.** Scan `question` records directly — a flat pass
over `load_all(journal_dir())` filtered to `type == "question"` — **not**
the errand walk `run_status`'s `_collect_downstream` performs. This is
deliberate and narrower than it looks: `_collect_downstream` walks
`refs` transitively from a request, which means a `question` record
whose `refs` chain never reaches a root request — something
`castle record --type question` can legitimately produce by hand, with
no `--refs` at all, or with `--refs` pointing at something other than an
errand — would simply never appear in an errand-keyed walk. A surface
whose entire job is "nothing the resident is supposed to answer stays
silently unanswerable" cannot inherit a fold that can hide a record by
construction. Pending is instead the direct predicate: a question's id
is pending iff no `answer` record's `refs` contains it — the exact same
test `file_answer`'s new pendingness check applies, and the same
predicate `_errand_state`'s "waiting on you" overlay already uses
(pairing each question against the set of ids named in some answer's
`refs`). It is exact rather than heuristic because `cmd_answer`/
`file_answer` guarantee every answer's `refs` is exactly
`[question_id]` — there is no ambiguity to approximate around.

The fold is computed **first**, before deciding interactive vs. piped
behaviour, in both cases. When it is empty: print
`"Nothing is waiting on you."` and exit 0, with the dismissal pause
(§below) if interactive.

**Interactive flow** (`sys.stdin.isatty()`):

- Oldest-first, numbered `[1]` through at most `[9]` per page.

  *(Two corrections from review round 1. **Finding 7, the ordering
  claim:** this said ids are "chronologically sortable by construction",
  which is false within a single second — `make_id` appends a *random*
  suffix, so two questions filed in the same second sort by that suffix,
  not by which came first. What the full-id sort actually guarantees,
  and all the picker needs, is that the order is deterministic and
  identical on every invocation, so a number means the same thing for as
  long as the list is on screen; across seconds it is genuinely
  oldest-first. No schema change — the claim was wrong, not the
  mechanism. **Finding 1, the cap:** a hard nine-entry cap with no way
  past it made question ten unreachable — possibly the exact question a
  notification had just pointed the resident at — on a surface whose
  fold exists precisely so that nothing can be hidden by construction.
  It pages instead, inside the same one-keypress grammar: digits select
  on the current page, `m` shows the next nine and wraps to the first
  page after the last, any other key still closes. The prompt reads
  `"Press a number to answer, m for more, or any other key to close."`
  and the overflow line `"…and N more waiting — press m to see them."`,
  both only when more than nine are pending; with nine or fewer, the
  surface is exactly as it was. cbreak stays engaged across page
  redraws, so a page turn never reopens the swallowed-keypress gap.)*
- Each entry shows the first line of the question's body, and — when
  `_find_root_request` (already in `agent/castle`, walking `refs` back
  to an originating `request`) reaches one — an indented
  `about: <first line of the root request's body>` line underneath. When
  the walk does not reach a root request (the same "no chain to a
  request" case the pending fold above is built to not lose), the
  `about:` line is simply omitted — no placeholder, no error.
- Selection is a single keypress, read with the identical
  cbreak-before-print pattern `_classify_interactively` already
  documents and uses: `termios.tcgetattr`, `tty.setcbreak(fd)` engaged
  **before** the prompt is printed, restored in a `finally`. Reuse that
  function's own reasoning verbatim in the new code's comment — a
  keypress landing in the gap between "prompt printed" and "cbreak
  engaged" is held by the kernel's still-canonical line discipline until
  a newline arrives, which a bare digit keypress never sends, hanging the
  read forever. The resident never sees or types a record id to make a
  selection — a screen-relative index (`1`..`9`) is what satisfies "no
  internal identifiers as required input," and it is safe to treat as
  stable *because* the ordering is deterministic (oldest-first,
  recomputed once per invocation) rather than because the numbers mean
  anything durable.
- **Always the picker, even with exactly one pending question.** No
  auto-presenting the sole question and skipping straight to its body —
  see the rejected-alternatives list (§9) for why: a uniform grammar,
  with an explicit selection every single time, is what keeps "answering
  something you did not choose" from ever being possible by construction
  rather than by luck.
- **Any keypress that does not select a listed question closes the
  window immediately** — exit 0, no dismissal pause, nothing written to
  the journal, the model, or the spool. The keypress itself *is* the
  dismissal; there is no second "press Enter to confirm you meant to
  leave" step, because demanding one after a resident has already made a
  deliberate choice to not answer is exactly the kind of friction this
  surface exists to avoid. This is also the subject of the required
  dismissal test (§7.5): dismissal must write nothing, and the
  implementation should make that true structurally, not just by
  observed behaviour — the only call to `file_answer()` anywhere in this
  mode is on the submit path, after a question has been selected and a
  body typed. There is no code path from "pressed a non-selecting key"
  to a write.
- After a valid selection: print the full question body **verbatim, in
  full** — never truncated. The picker's first-line preview is a display
  convenience for choosing among several; truncating the *actual* text
  the resident is about to answer is a different thing entirely, and
  `docs/tasks/0010`'s stop condition ("no seat paraphrases... at write
  time or ever") extends naturally here even though this is a read, not
  a write: showing less than the full question and letting the resident
  answer on a truncated understanding of it is its own kind of dishonest
  surface. Print the `about:` line again for context, then read the
  answer with compose mode's **exact** input grammar — read stdin until
  a line containing exactly `.` or EOF, then `.strip()`. One surface,
  one text-entry grammar, reused rather than reinvented.
- **Empty body**: refuse to stderr using compose mode's existing
  vocabulary (`"castle-modal: empty request, nothing filed."` is
  compose's wording for the parallel case — the answer mode's version
  should read the same way, adjusted for "answer" in place of "request"),
  pause for dismissal, exit 1. No re-prompt loop: this is a state
  machine this surface does not need, and a hang risk on a pty-driven
  program for no benefit that outweighs it — the chord is one keypress
  away from trying again.
- **`AnswerRefused` with `kind="already_answered"`** (the raced case —
  the question was answered by another process, or another window, in
  the interval between the picker showing it and this keypress landing):
  a plain-language refusal naming no ids, pause, exit 1.
- **Success**: a confirmation that says only what is true. No record id
  — compose mode's `"Filed as {id}."` is the pattern being deliberately
  broken here, not copied; §2's no-internal-vocabulary rule below covers
  ids as much as it covers the word "seat." And no promise of
  resumption: until task 0023 exists, answering a question resumes
  nothing — `docs/backlog/errand-resume-after-answer.md` is explicit that
  no mechanism re-invokes the worker on the original request, so a
  confirmation implying otherwise would be exactly `docs/tasks/0015`'s
  defect re-committed one level up — a label causing the inaction (or
  false reassurance) it describes. Recommended text:
  `"Filed. Nothing picks this errand back up automatically yet."` — a
  blunt, true sentence, and one that becomes the literal line 0023
  deletes when it ships a resumption mechanism, which is the right shape
  for a sentence describing a known gap. Then, **iff** a resident-model
  entry was actually written (the fact rule fired), one additional plain
  line: `"Noted — I'll remember that."` A write into the resident's own
  model that the resident is never told about is authority exercised
  invisibly — Proposal 05's whole premise is that the model is built
  from explicit exchanges the resident can see, and a silent write would
  violate that in spirit even though the record itself is honest. One
  line is the minimum that makes the write real to the person it is
  about. When no entry was written, say nothing about it — silence is
  the honest report of "nothing else happened." The internal
  `"recorded resident-model entry for fact '...'"` line must never reach
  this surface — it names the internal fact key, which is exactly the
  vocabulary this mode exists to keep the resident away from. Then pause
  for dismissal, exit 0.

**Vocabulary rule for everything this mode prints, stated once and
binding on every string above:** no record ids, and none of `seat`,
`provenance`, `refs`, `journal`, `record`, `channel`, `evidence`, and no
fact names. This binds surface-*added* text only — the question and root
request bodies shown verbatim are the worker's or resident's own prose
and are shown exactly as written, unfiltered; the constraint is on what
the tool itself says around them.

**Non-interactive contract**, mirroring compose mode's `--kind` flag's
existing asymmetry on purpose: a new flag, `--question ID`, documented
in its own help text as "scripts and CI only, never shown to the
resident" — the same framing `--kind`'s help text already uses for
itself.

- A piped session (no tty) with one or more pending questions and **no**
  `--question` given: refused, exit 1, nothing written. Guessing the
  oldest pending question in a script context would be a silent
  wrong-record path with no resident present to notice — worse than
  refusing outright. With nothing pending and no `--question`, it prints
  the friendly line and exits 0, same as an interactive session.

  *(Corrected during implementation — review round 1, finding 2. The
  "compute the fold first, in both cases" rule above was implemented
  literally, as a short-circuit ahead of everything else, which quietly
  turned every documented `--question` refusal into exit 0 with prose on
  stdout: a bogus id, a request id, and an already-answered question all
  hit the empty-fold path, because answering a question is exactly what
  empties the fold. **A piped session with `--question` now goes
  straight to the write path regardless of the fold** — `file_answer`
  owns every check, so the refusals it raises are the contract — and the
  empty-fold exit-0 remains for interactive sessions and for piped
  sessions with no flag. The fold-first rule still holds for everything
  it was written to govern: no surface guesses which question was
  meant.)*
- A piped session **with** `--question ID`: reads the answer body from
  stdin using the same `.`/EOF grammar, calls `file_answer`, and on
  success prints the answer id on stdout — this is script output, meant
  to be asserted on by a caller, not resident-facing prose, so the
  no-ids rule above does not bind it (the same distinction `castle
  answer`'s own stdout already draws).
- **An interactive session always ignores `--question` and shows the
  picker regardless.** A flag that preselects a question in a session a
  human is actually looking at is precisely the "answering the wrong
  one" hazard this whole design exists to prevent — `--question` exists
  for a context with no human present to choose, and an interactive
  session is definitionally not that context.

**Exit codes.** `0` on: successfully filed, nothing pending, or a
deliberate dismissal without answering — dismissal is a *successful* use
of the surface (the resident looked and chose not to act), not a
failure, and giving it exit 1 would make "looked and declined" and "an
actual error occurred" indistinguishable to any script or test checking
the exit code. `1` on: empty answer body, an unresolvable or absent
`--question` where one was required, a target record that resolves but
is not type `question`, and an already-answered refusal.

**No new window rule, no resize.** The mode runs under the same
`castle-modal` app_id in the same floating, centered 720x480 window
`modules/home/default.nix`'s existing `window.commands` rule already
gives every `castle-modal` invocation, regardless of `--mode`.

**Two more places in `agent/castle-modal` itself need updating, beyond
the new functions.** The module's own docstring currently opens "Two
modes, both just callers of agent/castle's own record-writing and
record-reading functions" and goes on to enumerate `compose` and
`status` by name; it must describe three modes, in the same voice, once
`answer` exists — leaving it saying "two" after this task ships would be
exactly the kind of stale self-description this codebase's own review
passes keep catching (§4's chord-string history is one example).
`build_parser`'s `--mode` argument gains `"answer"` in its `choices` and
a clause in its help text alongside the existing `compose`/`status`
descriptions; the new `--question ID` flag gets its own help text
stating the "scripts and CI only, never shown to the resident" framing
this section already specifies, matching how `--kind`'s help text
already states the identical framing for itself.

### 3. `run_status` changes — narrow and deliberate

Two changes, and nothing else in `run_status` or `_errand_state`
changes.

**`_pause_for_dismissal` at both of status's exit paths.** Today,
`run_status` calls `_pause_for_dismissal` nowhere at all — neither on the
empty-journal message (`"No errands yet..."`, an immediate `return 0`)
nor after the normal listing. Without it, the instant anything binds
`castle-modal --mode status` to a chord (which nothing does today, but
this task's own new chord makes the same shape newly possible for the
*answer* mode, and status is one keystroke away from acquiring one
later), the window opens and closes in zero human-perceptible frames —
the exact 0009 review-pass finding-5 bug, re-created for a second mode.
Adding the pause now, at both exit paths, closes that possibility for
status before it is ever exercised, and gives answer mode's own pauses a
consistent sibling rather than an inconsistent one. `_pause_for_dismissal`
is already isatty-gated internally, so no piped caller — including every
existing CI assertion that runs status non-interactively — changes
behaviour.

**The waiting-overlay text grows the answer path.** Today the overlay
appended to an errand's state line is exactly `", waiting on you"` (or
standalone `"waiting on you"` with no base state). It becomes
`", waiting on you — press Mod4+Shift+a to answer"` (and the standalone
form correspondingly, `"waiting on you — press Mod4+Shift+a to answer"`).
Rationale: this is `docs/tasks/0015`'s rule, applied a second time — every
other non-`"done"` label this surface renders already names its remedy
(`"failed — castle work <id> to retry"` and its `outcome` siblings), and
`"waiting on you"` was the one label on this surface that named no path
forward. That gap is a real defect by 0015's own standard: a label that
tells the resident something is wrong but not what to do about it "causes
the inaction it describes" as surely as a label claiming something false.
The handful of existing `"waiting on you"` string assertions in
`test/agent-loop/modal-headless-test.sh` (grepped in the file discovery
above) are updated to match the new text.

**Nothing else in status changes.** The bracketed record id, the bare
`provenance` word, `"decided -> {channel}: {evidence}"`, `"noted:
{evidence}"`, and every `outcome`-derived retry label stay exactly as
`docs/tasks/0021-auto-dispatch.md` shipped them, unchanged in this task.
Say why plainly: those labels were rebuilt across four review passes
during 0021's own implementation, the retry hints carry ids
*deliberately* (a resident needs the exact id to type `castle work
<id>`, which is load-bearing 0015-grounded design, not an oversight), and
roughly twenty exact-match assertions in `modal-headless-test.sh` pin
today's exact strings. Discovery of a pending question no longer needs
to pass through status at all to be effective — dispatch (0021) starts
eligible errands automatically and this task's own notification change
(§4) names the answer chord directly at the moment a question is routed
— so status's remaining internal-vocabulary leak is real but no longer
on the path a resident actually needs for the common case. It is named,
not solved, in the new backlog entry
(`docs/backlog/status-surface-internal-vocabulary.md`, added by this
task — see §8).

### 4. The notification names the door

In `_route_journal_locked`, when a `question` record routes to the
`notify` channel, the notification body currently reads (via
`_fire_notification`) just the record's own first-line summary. It
gains one trailing plain-language sentence: `"Press Mod4+Shift+a to
answer."` Rationale: the notification is the only *push* channel this
system has — a resident who does not happen to open the status surface
or the modal on their own would otherwise learn a question exists but
not how to close it, and would fall back to `castle answer`, the exact
CLI dependency this whole task exists to remove. This is a text-only
change to what gets handed to `_fire_notification`, scoped to the
`question` branch only (a `result` routed to notify keeps its existing
notification text unchanged — there is nothing for a result to be
"answered," and adding an unconditional suffix to every notification
would be noise on the case it does not apply to). The decision record
itself — `channel`, `considered`, `propensity`, `evidence`, and the
routing rule that produced them — is completely untouched; only the
string handed to the notify command changes.

Deliberately **not** `notify-send -A` (action buttons). Mako and
libnotify support click-to-act notifications, and it would be tempting
to wire one straight to the answer chord instead of asking the resident
to press a key. It is out of scope on purpose: an action button's whole
value is *reporting reception* — the daemon can tell the caller which
action was clicked, or that the notification was dismissed unactioned —
and that is exactly Proposal 06's receipt infrastructure, which
`docs/architecture.md`'s sequencing paragraph defers until a delivery
surface exists that can report reception back into the journal. A UI
task quietly wiring one in as a convenience is precisely the back door
that sequencing decision exists to prevent; a plain sentence in the
notification body carries no such implicit receipt channel.

The chord string embedded in this notification (`Mod4+Shift+a`) is a
prose coupling to `modules/home`'s actual binding — the same kind of
coupling the modal's own status hint already carries (`run_status`'s
`"Press Mod4+Shift+Return and describe one."` line). That string went
stale once already: `docs/tasks/0019-sway-initial-workspace-and-modal-
chord.md` moved the compose chord from `Mod4+Shift+space` to
`Mod4+Shift+Return`, and two hardcoded mentions of the old chord were
left behind in `agent/castle-modal` until `docs/tasks/0021-auto-dispatch.md`
found and fixed them in passing. Mark the new string with a comment
pointing at `modules/home/default.nix`'s keybinding so the next chord
change is found by grep rather than repeating that miss.

### 5. The chord

```
"Mod4+Shift+a" = "exec foot --app-id=castle-modal -e castle-modal --mode answer";
```

added to the **same** `lib.mkOptionDefault` attrset in
`modules/home/default.nix` that already carries `"Mod4+Shift+Return"`
and the `XF86*` media-key bindings — never a second, separate
`keybindings` definition. The long comment already on that attrset
(~lines 246–296) explains why in detail: a second, unwrapped
`keybindings = { ... }` definition anywhere in this module would sit at
the module system's default priority (100), strictly below
home-manager's own spliced-in default bindings (1500,
`lib.mkOptionDefault`-wrapped internally), and `filterOverrides'` would
discard home-manager's *entire* default set before the per-key merge
ever runs — the exact 0009 review-pass finding-1 lockout that comment
exists to prevent from happening again. One attrset, one wrapping.

**Chord choice, and the residual risk it carries.** Verified against the
pinned home-manager `sway.nix` module's own default bindings at this
flake's lock: no stock binding under **any** modifier value uses the
`Shift+a` suffix, and `${modifier}+a` is not taken either, so the chord
displaces nothing whatever a resident sets `modifier` to.

*(Corrected during implementation — this paragraph originally claimed
"none of the move-window defaults is a letter key with a `Shift`
prefix", which is false at this pin and was worth getting right, because
it is the exact fact the residual below turns on. `sway.nix` binds
`${modifier}+Shift+${config.left|down|up|right}` to `move
left`/`down`/`up`/`right`, and those four options are **home-row
direction keys** defaulting to `h`/`j`/`k`/`l` — letters, with separate
arrow-key bindings alongside them. So the stock set does contain
`Shift`-prefixed letter chords; none of them is `a`, which is what makes
`Shift+a` safe by default and what makes the residual concrete rather
than hypothetical.)*

Record the residual in the chord's own comment, because it is the same
shape `docs/tasks/0019` defect 2 already found once for a different
chord: a resident who *both* sets a private-layer `config.left = "a"`
(or rebinds any of those four directions onto the letter `a`) **and**
sets `modifier = "Mod4"` produces a real `Mod4+Shift+a` move-window
binding, which this chord then eats silently, with no module-system
diagnostic of any kind — the identical cross-level shape-(b) collision
`modules/home/default.nix`'s existing long comment already documents for
the general mechanism. `Shift+Return` was immune to this specific
failure mode because `Return` is not a key a resident would ever remap a
direction onto; `Shift+a` is a letter, and is not immune. State the risk
plainly in the new chord's own comment rather than only inheriting the
general warning above it.

**`.github/workflows/check.yml`**: add
`'bindsym Mod4+Shift+a exec foot --app-id=castle-modal'` to the
existing expected-binding sample list (the loop that already asserts
`Mod4+Shift+Return`'s presence). `docs/tasks/0019`'s own precedent for
this list: fail loudly if the whole default keybinding set vanishes
again, and a second castle chord landing at the wrong priority is
exactly the shape that check exists to catch.

**`flake.nix`'s `example-mod4`**: add one more assertion, parallel to
the existing `Mod4+Shift+Return` one, that
`keybindings."Mod4+Shift+a"` equals the answer-mode exec command under
`modifier = "Mod4"` — proving the chord survives a resident's modifier
override the same way the existing assertion proves it for compose
mode's chord.

Same `app_id = "castle-modal"` on the new invocation means the existing
`window.commands` floating/center rule in `modules/home/default.nix`
applies to the answer mode's window with no change of any kind.

### 6. Durable data — the five questions, answered

**No new durable record type, no new required frontmatter field, no new
state file, no spool write.** Walking through
`docs/architecture.md`/`agent/README.md`'s five-question durable-data
test, the way every prior task's design sections do:

1. **Durable vs. ephemeral?** Neither — nothing new is durable, because
   nothing new is written beyond the existing `answer` record and the
   existing (conditionally-written) resident-model entry, both of which
   already had their durable-data case made in `docs/tasks/0008` and
   `docs/tasks/0009`. "Pending" itself is not a fact stored anywhere; it
   is a fold — `question` records minus those referenced by some
   `answer`'s `refs`.
2. **Reconstructable from anything else?** Exactly and totally — the
   fold *is* the pending set, recomputed identically on every
   invocation. A `status: pending` field, or an `answered: true` flag on
   the question record, would be a second source of truth sitting on top
   of an append-only log, and the instant a question needed to transition
   from pending to answered, that field would need editing — which
   directly violates "a record is never edited" (`docs/architecture.md`).
3. **Cold-tenant comprehensible without schema archaeology?** Yes, and
   arguably better than a stored field would be: the fold is a single
   sentence, stated plainly in `agent/README.md` once this task's docs
   changes land (see §8) — "a question is pending iff no answer's refs
   names it" — and a cold reader needs no history of how a `status`
   field's semantics might have shifted across tasks to understand it.
4. **Observation or judgment — and the receipts trap specifically.** The
   trap here is genuinely tempting and worth naming explicitly: "the
   modal was opened," "question X was shown to the resident," "question X
   was dismissed without an answer" are each, individually, exactly the
   shape of a **receipt** in Proposal 06's vocabulary — cheap,
   machine-observable, and exactly the kind of signal that proposal warns
   gets promoted into a verdict by systems that go wrong. `docs/architecture.md`'s
   sequencing paragraph defers **all** receipt infrastructure until a
   delivery surface exists that can report reception, and none is built
   here: no record of an open, a view, or a dismissal is ever written.
   The dismissal test in §7.5 is the structural proof of this — dismissal
   writes nothing, to the journal, the model, or the spool, full stop.
5. **Needed now, not speculative?** Every candidate field considered
   while designing this task (a `status` field, a `viewed` timestamp, a
   `dismissed-count`) was speculative — nothing in this task's own scope
   reads any of them. The one claim/lifecycle marker genuinely needed to
   answer "is this question still open" landed already, with
   `docs/tasks/0021`'s `answer.refs` convention; this task reads that
   convention and writes nothing new to the schema.

### 7. Test plan

All headless behaviours for this task go in
`test/agent-loop/modal-headless-test.sh`, **not** `run.sh`.
`tenant-swap.sh` diffs `run.sh`'s id-stripped journal fingerprint across
two different worker tenants, and modal-driven answer records inside
that fingerprint would buy nothing (the answer mode never touches which
tenant ran an errand) while risking confusing tenant-swap failures if the
fingerprint ever drifts for an unrelated reason. `dispatch-test.sh`,
`run.sh`, and `tenant-swap.sh` all stay untouched by this task: 0021's
own `dispatch-test.sh` already proves an `answer` record does not by
itself restore a request's eligibility (there is no such thing as
"eligibility" for a question in the first place — dispatch's fold is
over `request` records), so no new answer-vs-dispatch interaction test
is needed here. Reuse the existing pty driver pattern (`pty.openpty()`,
`read_until`, the documented 0.2s post-prompt sleep before sending a
keypress, for the same cbreak-timing reason `_classify_interactively`'s
own test already documents it) rather than inventing a second one.

Headless additions, enumerated:

1. **No pending question**: piped `--mode answer` (no `--question`)
   prints the friendly "nothing waiting" line, exits 0.
2. **One question, answered** (pty): the picker shows `[1]`, the
   question's first line, and an `about:` line sourced from the root
   request; pressing `1` shows the full body; typing an answer body plus
   `.` produces the resumption-honest confirmation text; "Press Enter to
   close" holds the window; Enter closes it; exit 0; the written answer
   record's `refs` equals exactly `[question_id]`; no resident-model
   entry is written (this question carries no `fact` field).
3. **Two questions, distinguishable bodies** (pty): pressing `2` writes
   an answer whose `refs` names the *second* question, and the first
   question is still pending afterward — a single-question test cannot
   fail the way this requirement is actually about (picking the wrong
   one out of several). Re-opening answer mode afterward shows only the
   remaining pending question.
4. **No internal vocabulary in interactive output**: assert that the ids
   of every record involved (the question, the answer just written) are
   absent from the picker text and the confirmation text — a positive
   assertion the surface prints only plain language, not merely that it
   doesn't crash.
5. **Dismissal** (pty): press a non-selecting key at the picker; exit 0;
   the journal's file count and `resident-model.md`'s byte length are
   both unchanged before and after; `castle validate` stays green.
6. **Empty answer** (pty): select a question, then immediately send `.`;
   stderr carries the refusal in the existing "nothing filed" vocabulary;
   exit 1; nothing written.
7. **`--question` script path** (piped): body on stdin files the answer
   and prints its id on stdout. A bogus `--question` (an id that does not
   resolve) exits 1, writing nothing. `--question` naming an
   already-answered question exits 1. A piped invocation with pending
   questions and **no** `--question` exits 1, writing nothing.
8. **Interactive ignores `--question`** (pty): launch with
   `--question <Q2>` on an interactive pty; the picker still appears
   (not a preselected question); pressing `1` writes an answer whose
   `refs` names `Q1`, not `Q2` — proving the flag was genuinely ignored,
   not merely that the picker rendered.
9. **Fact-carrying question** (pty): plant a question via
   `castle record --type question ... --fact <name>`; answer it through
   the modal; the resulting resident-model entry cites the right
   `asked`/`answered` ids and the right fact; the modal printed the
   plain `"Noted — I'll remember that."` line and did **not** print the
   internal `"recorded resident-model entry for fact '...'"` line or the
   fact name anywhere in its output.
10. **Already-answered via the CLI**: a second `castle answer` on an
    already-answered question is refused, exit 1, and exactly one
    `answer` record exists afterward.
11. **More than nine pending**: file ten questions; the picker shows
    nine numbered entries plus the "…and N more waiting." line.
12. **Status surface**: update the existing `"waiting on you"` string
    assertions to the new answer-hint text; add a pty test proving status
    mode now holds its window open until Enter, on both the normal
    listing path and the empty-journal path.

**VM extension** (`test/desktop-loop/test.nix`), exactly one new
segment appended after the existing flow, keystrokes only — no shell
plumbing invented specifically for the answer path, matching this file's
existing style of driving everything through the real Sway session: file
a second request through the modal (a distinct, hardware-neutral fixture
body from the existing `complaintBody`); wait for the second question
record the scripted worker's contract already produces once dispatch
picks the new request up automatically; press the new chord
(`machine.send_key("meta_l-shift-a")`, matching this file's existing
`"meta_l-shift-ret"` naming for the compose chord); wait for the modal
window (`has_modal()`, already defined in this file); screenshot the
picker — the one thing no headless test can show a human, and this
harness already screenshots the equivalent compose-mode moments; press
`2` (oldest-first ordering means the *second* filed request's question is
entry `[2]`); type a fixture answer body plus `.`; screenshot the
confirmation; press Enter to dismiss; assert the window closes; assert
the resulting answer record's `refs` equals exactly the second question's
id, the first question is still pending (no answer's `refs` names it),
the answer body landed verbatim in the journal, and `castle validate`
stays green. Fixture text is invented and hardware-neutral, following
this file's own existing convention (`complaintBody`,
`correctionBody`) — never anything resembling real resident data.

### 8. Docs surface

- **`agent/README.md`**: the `answer` bullet in the `castle` CLI section
  gains a sentence naming `file_answer()` as the shared write path and
  the new already-answered refusal. The `castle-modal` section gains the
  third mode, its flags (`--question`), and the chord that opens it —
  including updating the two-line `castle-modal --mode ...` usage block
  at the top of that section to show all three invocations, not just
  `compose` and `status`. The "The resident model" section gains one
  sentence noting the elicited write path now has two callers —
  `cmd_answer` and the modal's answer mode — both narrow, both reaching
  `append_model_entry` through the same `file_answer` function, same as
  the correction path's existing two callers reaching `file_correction`.
- **`docs/architecture.md`**: the Intake seat paragraph gains one
  sentence — intake now takes a third kind of resident speech through the
  modal (closing a question), in the same voice as the existing sentence
  about corrections ("The same surfaces also take a second kind of
  speech...").
- **`modules/home/default.nix`**: the new chord's own comment states why
  this chord (no stock collision under any modifier, verified against the
  pin), the `config.left`/Mod4 residual risk, and the same-attrset
  requirement — see §5.
- **`.github/workflows/check.yml`** and **`flake.nix`**: as in §5.
- **`docs/private-layer.md`**: **no change**, and the brief says so
  explicitly rather than leaving it to a reader to check — no new slot,
  no new state shape, nothing this task adds touches what a private
  layer configures or stores.
- **Backlog**: nothing deleted. Name both
  `docs/backlog/errand-resume-after-answer.md` (task 0023's territory —
  this task deliberately resumes nothing, and that file's four candidate
  resumption designs remain the most valuable thing written about the
  problem) and `docs/backlog/apprenticeship-has-no-mechanism.md` (about
  deciding *what* to ask, a different problem from this task's "make
  answering easy" — this task gives the question economy a surface, not
  a mechanism for what gets asked) as explicitly **not** resolved by this
  work. One new backlog entry is added:
  `docs/backlog/status-surface-internal-vocabulary.md` (see the sibling
  file this brief also adds, and §3's rationale for why status's leak is
  deferred rather than fixed here).

### 9. Considered and rejected

- **Folding answering into compose mode.** Rejected — see §2's opening
  paragraph. Compose's value is having no picker in front of it; adding
  one to accommodate answering would change the flow that already works
  for the sake of the flow that doesn't exist yet.
- **A `status:`/`answered:` field on question records.** Rejected — a
  second source of truth sitting on top of an append-only fold, and one
  that would need an edit (an append-only violation) the moment a
  question's status changed. See §6, question 2.
- **Receipt infrastructure of any kind, including `notify-send -A`
  action buttons.** Rejected — Proposal 06's sequencing paragraph defers
  all of it until a delivery surface can report reception; a UI task is
  exactly the back door that sequencing decision was written to close.
  See §4's closing paragraph.
- **De-duplicating identical pending questions.** Rejected — merging two
  question records that happen to read the same is a judgment call
  (are they *really* the same question, or a coincidence of phrasing?)
  on a surface whose entire design goal is staying judgment-free, and it
  is paraphrase-adjacent in the same way `docs/tasks/0010`'s "no seat
  paraphrases, ever" rule already forbids for corrections. In practice,
  duplicates can only arise from a resident's own retries under 0021's
  one-automatic-attempt rule, which is a narrow enough case not to be
  worth a merge mechanism.
- **Auto-presenting a single pending question without the picker.**
  Rejected — see §2's "always the picker" bullet: the hazard is
  answering something the resident did not deliberately choose, and a
  uniform grammar (always pick, even from a list of one) removes that
  hazard by construction rather than by relying on the count happening to
  be small.
- **Cleaning up status mode's ids/provenance/evidence lines in this
  task.** Deferred, not rejected outright — see §3 and the new backlog
  entry. The labels are freshly rebuilt and heavily pinned by 0021's own
  test suite, and discovery no longer routes through status now that
  dispatch and the notification carry the acceptance path.
- **A lock around the double-answer race.** Rejected — the append-only,
  one-file-per-record journal was built specifically so writers never
  physically conflict; adding a lock here would be new machine-local
  state solving a race this design otherwise has no need to solve. See
  §1's "deliberately not a lock" paragraph.
- **Letting the resident name a fact at answer time.** Rejected — see
  §1's closing paragraph on Proposal 05: the fact name is the declaring
  seat's to set, and a resident-typed name at answer time would make the
  model's key space free text entered under neither documented entry
  shape.
- **A status chord.** Rejected — status stays CLI/menu-invoked, as
  today; it is deliberately out of the acceptance path. The notification
  (§4) and the answer surface (§2) now carry discovery end to end without
  it. Noted here as a real option that was considered, not silently
  skipped.

## Non-goals

- **Automatic errand resumption.** Answering a question resumes
  nothing; the confirmation text says so out loud (§2). That mechanism
  is task 0023's, and `docs/backlog/errand-resume-after-answer.md`
  stays open, untouched, with its candidate designs intact.
- **Proposal approval, private-repo edits, deployment, onboarding.**
  Tasks 0025–0027's territory (and onboarding nobody's yet); nothing
  here reads or writes configuration, and the worker-proposes-never-
  deploys constraint is untouched.
- **A general-purpose chat surface.** The answer mode is a picker plus
  one text entry bound to one record type; it converses about nothing.
- **Deciding what gets asked.** This task gives the question economy a
  surface, not a mechanism for choosing questions —
  `docs/backlog/apprenticeship-has-no-mechanism.md` stays open.
- **Cleaning status mode's internal vocabulary.** Deferred explicitly
  (§3, §9) to `docs/backlog/status-surface-internal-vocabulary.md`,
  added by this task. The boundary: 0022 creates the plain-language
  property on the new answer surface and the notification, extends the
  waiting overlay with the answer path, and leaves every other status
  line exactly as 0021 shipped it.
- **A status chord.** Status stays CLI-invoked (§9).
- **Receipt infrastructure of any kind** — no record of a question
  being shown, opened, or dismissed, and no notification actions (§4,
  §6.4).

## Verification plan

**Agent-testable, no human required:**
`test/agent-loop/modal-headless-test.sh`, `run.sh`, `tenant-swap.sh`, and
`dispatch-test.sh` run locally (bash + python3 only, no Nix needed for
these); `nix flake check`; `nix build .#desktop-loop-test` (this is the
acceptance gate for the VM segment in §7 — roughly 67s on top of the
existing base run, per 0021's own measurement of the harness this task
extends).

**Human hands, genuinely needed:**

- Press the real chord (`Mod4+Shift+a`) on the reference host and judge
  the picker and confirmation wording in situ — whether it reads as
  intended is a taste call no automated assertion can make.
- The end-to-end honesty check this whole task exists to satisfy: have a
  scripted or otherwise harmless tenant ask one real question, answer it
  entirely through the modal with no `castle answer` typed anywhere, and
  verify by eye that no internal identifier — a record id, the word
  "seat," anything from the vocabulary list in §2 — ever appeared on
  screen during the interaction.
- Judge the notification's added hint sentence for wording and urgency —
  whether "Press Mod4+Shift+a to answer." reads as helpful or nagging is
  a taste call, same as the picker text above.

## Implementation prompt

Address a fresh implementing session working in this same worktree and
branch (`sprint/0022-answer-in-ui`, based on `sprint/0021-auto-dispatch`).

Read this brief in full and every file it names in "Before starting."
Implement §§1–5 in `agent/castle`, `agent/castle-modal`,
`modules/home/default.nix`, `.github/workflows/check.yml`, and
`flake.nix`. Extend the test suite per §7 — headless additions in
`test/agent-loop/modal-headless-test.sh`, exactly one new segment
appended to `test/desktop-loop/test.nix` — leaving
`test/agent-loop/run.sh`, `tenant-swap.sh`, and `dispatch-test.sh`
untouched, per that section's own reasoning. Update docs per §8.

Run all four `test/agent-loop/` harnesses locally, `nix flake check`,
and `nix build .#desktop-loop-test`, each in the background with output
redirected to a log file — never chain a background invocation with
`;`; use `&&`/`||` or separate tool calls, so a failure in an earlier
step is not silently swallowed by a later one running anyway.

Scope every diff and every review pass against `sprint/0021-auto-dispatch`,
never `origin/main` — this branch is based on 0021's branch, not on
`main`, and a diff against `origin/main` would show 0021's entire
(already-reviewed, separately landing) changeset as if it were this
task's own. `git fetch` first, and confirm the real scope with
`git diff sprint/0021-auto-dispatch...HEAD --stat` before trusting any
review output, per `CLAUDE.md`'s rule on stale-ref reviews.

Commit in reviewable slices, with this brief file itself committed
alongside the work rather than separately — the brief's owner will have
already committed it to this branch before implementation starts; do not
silently rewrite it. If implementation surfaces a genuine deviation from
what this brief specifies — a wrong assumption about the code, a design
decision that turns out not to hold once real code is written — declare
it prominently in the implementing session's own report and amend this
brief in the same PR, per `CLAUDE.md`'s rule that a brief overtaken by
the work it rides gets corrected in place, not left to quietly describe
an abandoned design.

Never touch `docs/principles/` or `CLAUDE.md`. Never write anything
resembling real resident data — a real complaint, a real correction, a
real name or preference — into a fixture, a test, or a code comment;
every example string in this brief and in the existing codebase it
extends is invented and hardware-neutral, and new ones must be too.
