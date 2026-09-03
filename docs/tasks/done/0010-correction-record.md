# Task 0010 — The correction record: the resident speaks unbidden

**Before starting:** read `CLAUDE.md`, `docs/vision.md`, both docs in
`docs/principles/`, `docs/architecture.md` closely (the Records section,
the intake and router seats, and Proposal 06 — this task builds its
verdict half), and `docs/backlog/resident-cannot-speak-unbidden.md`,
the backlog entry this brief promotes (and deletes — see Scope 8). Then
the code this task extends: `agent/castle`, `agent/castle-modal`,
`agent/README.md`, `modules/agent/default.nix`, and everything in
`test/agent-loop/`. Work on a branch named `correction-record`, cut
from `outcomes-and-corrections` (stacked on `agent-layer-skeleton`) —
that branch carries Proposal 06 and the backlog entry this brief
depends on; confirm both are present before starting. This brief rides
the branch. PR to `main`.

**Goal.** The resident can speak unbidden. Today the record grammar
lets the system act on its own initiative (`provenance: initiated`)
while the resident may only open errands or answer questions the
system posed — "stop bugging me when I'm watching Netflix" has nowhere
to land. After this task: the resident types into the same modal they
already use, one keypress says whether it is *something to fix* or
*telling the system how it's doing*, and in the second case the words
land twice — as a durable `correction` record in the journal, stamped
with a mechanical snapshot of what the system had just done, and as a
verbatim resident-model entry, carrying `volunteered` provenance and
citing the correction, that the router reads.

**Why now.** Proposal 06 (docs/architecture.md) splits outcomes into
receipts and verdicts and rules that only verdicts may settle. Its
sequencing section is explicit: the receipt half waits for a delivery
surface that can report reception; the verdict half is buildable now,
because intake already takes free text. Volunteered corrections are
the highest-signal feedback the system will ever receive — the
resident thought it worth interrupting the machine over — and the
architecture currently discards exactly that input, or forces it
through `request`, where it reads as an errand to execute rather than
a judgment about behavior. This task closes the grammar asymmetry and
gives Proposal 06's hardening test ("at least one volunteered
correction has traversed correction → model entry → routing, cited end
to end") its first two legs.

## Three decisions already made — spec'd here, not to be relitigated

1. **Classification happens in the modal, in plain language.** After
   the resident finishes typing, one keypress answers one question:
   *something to fix*, or *telling you how you're doing*. Intake stays
   judgment-free — the resident classifies, the system never guesses —
   and the resident learns no jargon (the words "correction record"
   appear nowhere on the surface). Not a downstream classifier seat,
   not a second keybinding.
2. **The slice ships both artifacts.** The `correction` record *and*
   the resident-model entry citing it, so a correction lands in the
   artifact the router actually reads. The narrow/broad questioning
   move (transcribe the narrow reading, open a question where a
   broader one tempts) is explicitly a later slice — see Non-goals.
3. **Transcription is verbatim; judgment is deferred.** No seat
   interprets a correction at write time — not into a paraphrased
   fact, not into a scope, not into a rule. The argument for this is
   the load-bearing design rationale of the whole task and is spelled
   out in "Why verbatim" below.

## Verification plan

**No human needed (CI is the bar):**

- **Headless modal, correction path** (extend
  `test/agent-loop/modal-headless-test.sh` or add a sibling): piped
  canned input plus the headless classification flag produces a valid
  `correction` record (`type: correction`, `seat: intake`,
  `provenance: requested`, `surface: modal`, verbatim body) and a
  resident-model entry with `provenance: volunteered`, `stated:`
  citing the correction record id, and the correction's full text
  verbatim in the entry body. `castle validate` stays green over the
  result.
- **Headless modal, backward compatibility:** piped input with no
  classification flag still files a plain `request` — the existing
  piped tests must pass unmodified.
- **Interactive classification** (the pty pattern already used by the
  dismissal-hold test): drive compose mode on a pty; after the `.`
  terminator, assert the plain-language prompt appears with both
  labels; send the feedback key and assert a correction was filed; in
  a second run send the fix key (and, in a third, bare Enter) and
  assert a request was filed.
- **Context capture, both branches** (extend
  `test/agent-loop/run.sh`): (a) file a requested errand, produce its
  result, run `castle route` so a notify-channel decision exists,
  then file a correction via `castle correct` — assert
  `context-last-notify` cites exactly that decision id, the window
  counts are ≥ 1, `surface: cli`, and `context-local-created` parses
  as a timestamp with a UTC offset. (b) In a fresh state dir, file a
  correction against an empty journal — assert the counts are `0`,
  `context-last-notify` is absent, and the record still validates.
- **The router must not route corrections:** after filing the
  corrections above, run `castle route` and assert zero new decision
  records reference them and the notify stub did not fire again. A
  correction is *from* the resident, not addressed to them; routing
  one would be the system answering back. Add the corresponding check
  to `check_assertions.py`: no router decision may reference a
  correction record.
- **Write-path discipline, same regressions as 0009's findings:**
  `castle correct` with an empty body is refused with nothing
  written; `--refs` pointing at a nonexistent id is refused *before*
  anything is written (the finding-3 pattern — reuse
  `load_journal_record` pre-checks); `--refs` pointing at a real
  record (e.g. a router decision) is accepted and survives
  round-trip. Journal validates clean after every rejected write.
- **Digest renders it:** `castle digest` output includes the
  correction (its created time and verbatim first line at minimum),
  so the journal read cold through the digest is a complete account.
- Existing checks all stay green: `test/agent-loop/run.sh`,
  `tenant-swap.sh`, the vm-install harness (vm-test still imports no
  agent module), `nix flake check`.

**Human hands (~2 minutes, on the reference host):** press the
keybinding, type "you pinged me about something that could have
waited", press the *telling you how you're doing* key, then open the
journal record and `state/resident-model.md` and read them cold. The
acceptance bar is 0008's: the record and the entry are a complete,
honest, verbatim account — the resident's words, uninterpreted, with
provenance and filing-time context intact.

## Scope

1. **The `correction` record type** (`agent/castle`). Add
   `correction` to `RECORD_TYPES` and to the README's type table.
   Required frontmatter is the standard set — no new *required*
   fields. `provenance: requested` and `seat: intake`, the same
   convention `answer` records already use: provenance's job is
   routing, a correction is resident speech entering through intake,
   and the router ignores it (see 4). The `volunteered` vocabulary
   belongs to the *resident model's* provenance, not the journal's —
   keep the two changes separate. `refs` is optional and
   resident-supplied only: it is the record's one *causal* claim
   ("this correction is about that record"), and only the resident
   may make it. One new mechanical field: `surface` — which intake
   surface captured the words (`cli` or `modal`). The elicitation
   procedure is itself evidence (preference-construction research:
   how a preference was elicited shapes what was expressed), it is
   known only at write time, and nothing else records it.
2. **Filing-time context capture** (`agent/castle`, the shared write
   path). Deferred judgment preserves optionality only if the record
   carries what a later judge needs, and the words alone are not
   enough: work on learning from human interventions (Spencer et al.,
   *Autonomous Robots* 2022) shows that *when* someone chooses to
   correct — and what the system had just been doing — is itself a
   label, not incidental detail. So at write time, the correction
   write path reads the journal it is about to append to and stamps
   flat, mechanical context fields:

   - `context-local-created` — local wall-clock time with UTC offset
     at filing (`created` stays UTC; time-of-day meaning — evening,
     morning — is unrecoverable from UTC once the machine's timezone
     history is forgotten).
   - `context-last-notify` — id of the most recent notify-channel
     router decision in the journal, absent when none exists. Always
     resolvable by construction, since it is read from the same
     journal in the same process.
   - `context-notifies-1h` and `context-notifies-24h` — counts of
     notify-channel router decisions created within each window
     before filing, always present, `0` when none. (Window sizes are
     the implementer's to adjust; one short and one day-scale window
     must both exist and be documented in the README.)

   These fields make **no causal claim**: they state what the journal
   shows at the moment of filing — what the system had just done, how
   recently, how often — and nothing about why the resident typed.
   Asserting causality stays with the resident, via `refs`. Honest
   limit, recorded in the README: a notify-channel decision proves a
   notification was *attempted*, not that it was seen — delivery
   success is the receipts half of Proposal 06 and waits for a
   surface that can report it.
3. **`castle correct`** — the CLI write path, exactly parallel to
   `castle answer`: body from argv or stdin, refuse empty, resolve
   every `--refs` id before writing anything, write the `correction`
   record (with `surface: cli` and the context fields from 2), then
   append the resident-model entry (see 5) and print both ids.
   Implement the record-plus-entry-plus-context write as one shared
   function so the modal calls the same code path rather than
   reimplementing it — the modal's established pattern of being
   `castle`'s functions wearing a different hat.
4. **The router ignores corrections** (`agent/castle`, `cmd_route`).
   Today `cmd_route` only routes `result` and `question` types, so no
   code change may be needed — but the property is now load-bearing,
   so pin it with the CI regression above and a comment at the
   routing-types line saying why `correction` must never join that
   tuple: resident speech is never "addressed to the resident."
5. **The volunteered resident-model entry** (`agent/castle`,
   `agent/README.md`). Extend the model-entry format with two fields:
   `provenance` (`volunteered` here; absence continues to mean
   elicited, so every existing entry stays valid) and `stated` (the
   correction record id, playing the role `asked`/`answered` play for
   elicited entries). The transcription is **mechanical and
   verbatim**: `fact` is the correction's first line truncated to 80
   characters, the body is the correction's full text unchanged, and
   no seat rewrites, summarizes, or normalizes a single word. Example:

   ```
   ---
   fact: You pinged me about something that could have waited
   provenance: volunteered
   stated: 20260816T210412Z-correction-3f9c2a
   when: 2026-08-16T21:04:12Z
   ---
   You pinged me about something that could have waited until the
   digest.
   ```

   The entry is deliberately minimal — a future judge follows
   `stated:` to the correction record, where the context fields live.
   Every correction writes exactly one entry, praise included. A
   model that accumulates verbatim verdicts of mixed generality is
   accepted; curating them is the later normalization slice's job.

   **Frame this correctly in code comments and the README: the model
   entry is a derived view, not a second source of truth.** It is
   regenerable from the correction record it cites — trivially so in
   this slice, since it is a near-copy — and that framing is what
   makes a future normalization pass *legitimate* rather than a
   violation of append-only. The journal is immutable and holds every
   word the resident said; the model is a cache over resident speech
   that a better judge may one day rebuild. (This is already true of
   elicited entries, which derive from question + answer records in
   the journal — the README's resident-model section should be
   reframed to say so: source of truth is the journal; the model is
   append-only in day-to-day operation but rebuildable from journal
   records without loss, and rebuilding it breaks no proposal.)
6. **The modal's classification step** (`agent/castle-modal`). After
   the body is captured (the `.` terminator or EOF), interactive
   sessions get one plain-language prompt — `something to fix` /
   `telling you how you're doing` — answered with a single keypress
   (termios cbreak under `isatty()`, or equivalent stdlib mechanics;
   bare Enter defaults to *something to fix*, the common case).
   Non-interactive invocations take a flag (suggest
   `--kind request|correction`, defaulting to `request` so every
   existing piped caller is untouched); flag names are for scripts
   and CI, never shown to the resident. The correction path calls the
   shared write function from (3), passing `surface: modal`.
   Corrections do not appear in status mode — status folds errands,
   and a correction is not an errand awaiting anything.
7. **Digest** (`agent/castle`, `cmd_digest`). A small corrections
   section — each correction in the period, created time, verbatim
   first line, refs if any. Exact rendering is the implementer's
   call; the requirement is only that the digest read cold accounts
   for corrections too.
8. **Docs and the backlog promotion.** Delete
   `docs/backlog/resident-cannot-speak-unbidden.md` in the same
   commit that adds this brief (the backlog convention in
   `CLAUDE.md`), and fix `docs/architecture.md`'s Proposal 06
   sequencing paragraph, which cites that file, to point at this
   brief instead. Update `docs/architecture.md`'s Records type list
   and intake-seat paragraph to include corrections; update
   `agent/README.md` (subcommand table, record format including the
   `surface` and context fields, resident-model section with the
   volunteered entry shape and the derived-view reframing); touch
   `docs/private-layer.md` only if it restates the model-entry
   format. `modules/agent/default.nix` needs no change — the new
   subcommand rides the existing wrappers; say so in the PR rather
   than touching the module.

## Why verbatim — the argument this task is built on

The temptation at write time is to classify: decide whether "stop
bugging me when I'm watching Netflix" is a general preference or a
moment's irritation, and store the classification. The two possible
errors are not symmetric. **Classifying at write time destroys the
information needed to reclassify: verbatim storage keeps the door
open.** If judgment is baked into storage and it was wrong, the
system is more or less forever committed to the wrong reading — the
words, the moment, the surrounding state that would support a
different reading are gone. If judgment is postponed, a later pass
can still be wrong, but a better judge on another pass can get it
right, because everything the resident actually said and did is still
there. This is also Proposal 03 applied to data: intelligence is a
tenant, so anything a tenant *decided* is provisional and anything
the resident *said* is durable — a classification baked into storage
is a structural member built out of a tenant's opinion.

Two research results sharpen the same instinct. People do not carry
complete preference orderings waiting to be read out; they construct
preferences at the moment of elicitation, and the elicitation
procedure shapes the answer (Lichtenstein & Slovic, *The Construction
of Preference*, 2006) — so the resident may genuinely not *have* a
scope for "Netflix" when they type it, and no write-time judge,
however smart, can recover a fact that does not exist yet. And people
cannot give corrections that cleanly isolate what they meant: a
correction intended to fix one thing perturbs several, and a system
that updates everything the correction touches learns things the
human never intended (Bajcsy, Losey, O'Malley & Dragan, HRI 2018) —
one more reason no seat gets to guess at write time.

Deferred judgment has one obligation, and Scope 2 is it: optionality
is only preserved if the record carries what the later judge will
need. The same sentence typed after the third interruption in an hour
and typed calmly on a quiet Tuesday are different evidence, and the
distinguishing state must be captured mechanically at filing time or
it is never captured at all — Proposal 04 makes any gap permanent by
construction.

The line that must hold in this slice: **no seat paraphrases a
correction, ever.** If an implementation shortcut tempts toward a
summarized or normalized fact, that is the erosion edge — stop and
leave it verbatim.

Honest limit, stated so nobody oversells the PR: today's router rule
set is provenance alone, so a correction changes what the router
*reads*, not yet how it *routes*. "Both artifacts" is satisfied
structurally — the verdict is durable and sits in the router's read
set with provenance intact. Visibly changed routing is Proposal 06's
hardening test and waits for a router tenant with judgment.

## Acceptance

- CI green: all existing checks, plus the headless correction path,
  the pty classification test, the context-capture assertions (both
  the populated and empty-journal branches), the
  router-ignores-corrections regression, the write-path refusal
  regressions, and the digest rendering check.
- `castle validate` accepts `correction` records and the journal
  stays clean through every negative test.
- The resident-model entry is verbatim, carries
  `provenance: volunteered`, and cites its correction record;
  existing elicited entries still parse; the README frames the model
  as a derived, regenerable view over the journal.
- The backlog file is deleted in this brief's commit and
  `docs/architecture.md`'s reference to it is updated; README and
  architecture docs reflect the new type and its context fields.
- The human check completed: one real correction filed from the
  keybinding, record and model entry read cold as a verbatim, honest
  account with filing-time context intact.
- `/code-review` run before the PR, scoped against `origin/main`
  after a `git fetch`, per `CLAUDE.md`.

## Non-goals

- **The narrow/broad questioning move.** No generalization, no
  normalization, no paraphrase — verbatim entries only. And a design
  note for whoever builds that slice: per the constructed-preference
  result above, the clarifying question will not *discover* a
  pre-existing boundary, it will cause one to be constructed — that
  slice is negotiated construction with the resident, not elicitation
  of a fact, and should be designed as such.
- **Causal linking.** The context fields state temporal facts only.
  Automatically asserting "this correction is about that
  notification" — auto-populating `refs`, or any equivalent — is
  interpretation, and stays out. `refs` is the resident's claim to
  make.
- **Receipts** — Proposal 06's other half waits for a delivery
  surface that can report reception (mako cannot distinguish
  dismissed from expired). Until then, notify-channel decisions are
  attempt records, and the context counts inherit that limit.
- **Retro-labeling past decisions** from a correction beyond whatever
  `refs` the resident supplied.
- **Router behavior changes.** The provenance-only rule set stands;
  consuming model entries in routing judgment is a later tenant's
  work.
- **Audit tooling** (`castle audit`, falsifier sampling) — a separate
  task, blocked on the falsifier question architecture.md leaves
  open.
- **Journal-wide schema additions.** `surface` and local-time context
  would arguably improve *every* resident-authored record (requests,
  answers), but this slice adds them to corrections only; extending
  the base schema is a separate task with its own compatibility
  questions.
- No new Nix options, no new keybindings, no new seats.

## Coordination

Territory: `agent/castle`, `agent/castle-modal`, `agent/README.md`,
`test/agent-loop/`, `docs/architecture.md`, `docs/backlog/` (one
deletion), `docs/tasks/0010-*`, possibly `docs/private-layer.md`.
`modules/`, `hosts/`, and `flake.nix` should be untouched. Rebase
onto a freshly fetched `origin/main` before opening the PR and scope
every diff and review against `origin/main`, never a local ref, per
`CLAUDE.md`.
