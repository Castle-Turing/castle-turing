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
(`castle answer --fact`).

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
castle answer QUESTION_ID [--fact NAME] TEXT...
castle correct [--refs id,id] TEXT...
castle record --type T --provenance P --seat S [--refs id,id] [--evidence TEXT] [--fact NAME] [--body TEXT | --body-file PATH] [--spool]
castle route
castle work REQUEST_ID
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
  an entry to `state/resident-model.md` alongside the journal `answer`
  record — see "The resident model" below.
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
  automatically. `castle-modal`'s compose mode reaches the same write
  path (`file_correction()` in `agent/castle`) after asking, in plain
  language, whether what was just typed is something to fix or
  feedback about how the system is doing — see "`castle-modal`" below.
- **`record`** — the generic writer underneath the above, and what a
  worker or router seat calls directly. Any seat, any type. `--fact` is
  honored here too so a worker raising a `question` record can name the
  fact it's eliciting up front.
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
  `$CASTLE_REPO_ROOT` in its environment, and folds the command's
  stdout (reasoning) and `$CASTLE_DIFF_FILE` (a diff, or nothing) into
  a `result` record. The contract sits at the errand boundary
  (Proposal 03): what runs inside the command is free, but a result
  record with the diff embedded is the only thing that gets to matter
  to the rest of the system. **The worker proposes; it never deploys**
  — this function has no code path that runs `nixos-rebuild`, `git
  commit`, or anything else that touches a running system or this
  repo's history.
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
  as a non-empty flat list, and (when both `channel` and `considered`
  are present) `channel` actually being a member of `considered` — a
  general invariant ("you can't choose what you didn't consider") kept
  in the permanent schema gate rather than only in the test harness,
  since it holds for any future router policy, not just today's
  two-channel rule. This is what CI asserts with
  (`test/agent-loop/run.sh`).
- **`show`** — prints one record verbatim, checking the journal then
  the spool.

## `castle-modal` — the ambient intake

A floating `foot` terminal (bound to `Mod4+Shift+space` in
`modules/home`'s Sway config — see that module for why this chord and
not another) running `agent/castle-modal`, a second stdlib-only Python
script that imports `agent/castle` in-process rather than shelling out
to it. Two modes:

```
castle-modal --mode compose [--limit N] [--kind request|correction]
castle-modal --mode status  [--limit N]
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
  from the journal into a compact listing: what was asked, whether it's
  in progress, waiting on the resident, or done, and what the router
  most recently decided and why. The "come back later and check" half
  of the design. Corrections never appear here: they aren't errands,
  and there's nothing about one to "come back and check" on.

Headless by construction: both modes only ever read `sys.stdin` and
write `sys.stdout`/`sys.stderr`, with no `curses` and no compositor
dependency anywhere in the control flow — the only place `sys.stdin.isatty()`
is even checked is to decide whether to print a couple of purely
cosmetic prompts in compose mode. That's what lets CI pipe canned
input at it and assert on the request record it produces with zero
Sway, zero foot, and zero display server involved.

## `agent/castle-worker-claude` — the default worker tenant

A plain bash script, the reference implementation of
`castle.agent.worker.command`'s contract (see `castle work` above):
reads the request body on stdin, builds a prompt that states the
errand, the repo location, and — unmissably — that this seat must not
deploy anything, then execs `claude -p` with it. Read the script itself
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

### Required fields (every record)

| Field        | Meaning                                                              |
|--------------|-----------------------------------------------------------------------|
| `id`         | `YYYYMMDDTHHMMSSZ-<type>-<6 hex chars>` — sortable, greppable, collision-safe enough. Must match the filename. |
| `type`       | One of `request`, `decision`, `result`, `question`, `answer`, `correction`. |
| `provenance` | `requested` (the resident asked for this) or `initiated` (the system undertook it on its own). |
| `refs`       | Comma-separated ids of the records this one responds to. Empty for a root request. |
| `seat`       | Which seat wrote this record (`intake`, `router`, `worker`, `digest`, or a specific worker's own name). |
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
- **The spool** — ephemeral, machine-local, never committed — lives
  under `$XDG_RUNTIME_DIR/castle/spool/`, falling back to
  `/tmp/castle-$UID/spool/` if no runtime dir is set. Same record
  format; `castle record --spool` writes there instead of the journal.
  Delete it any time; nothing durable is ever spool-only.
- **`modules/agent`** (this flake's `nixosModules.agent`) installs the
  `castle` CLI and declares `castle.agent.stateDir`, which — when set
  by a private layer — is wired into `CASTLE_STATE_DIR` via
  `environment.sessionVariables`, i.e. PAM-set for every session, not
  just a login shell — see that module's `config` comment for why the
  distinction is load-bearing (docs/tasks/0013-first-deploy-findings.md:
  a greetd-launched Sway session, and `castle-modal` spawned from it,
  never sourced the login-shell-only variant). See
  `docs/private-layer.md` for what a resident actually points that at
  (the private repo's own `state/` directory, so the journal survives a
  reinstall).
- `CASTLE_STATE_DIR` is also what makes `test/agent-loop/run.sh`
  possible without touching a real resident's journal: it points every
  `castle` invocation in that harness at a throwaway temp directory.

## The resident model

Living at `state/resident-model.md` in the private repo
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
  in `agent/castle` is called from `cmd_answer`, which only ever runs
  because a human typed an answer at this CLI (or at `castle-modal`,
  which calls the same code). The fact name comes from the `question`
  record's own `fact` field by default (the seat that raised the
  question is the one that knows what it's eliciting), or from
  `castle answer --fact NAME` explicitly. The entry's body is the
  literal question and answer text, not a summary.
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

A private layer's `state/resident-model.md` ships as an empty file (or
absent entirely) until the first elicited answer or volunteered
correction gives it a first entry — see
`docs/tasks/0008-agent-layer-skeleton.md`'s real-errand verification
plan for how that first entry gets written on the reference host.

## Testing

Four harnesses, all plain bash and stdlib Python — no Nix involved,
unlike `test/vm-install/`'s harness — runnable locally with nothing
beyond `bash` and `python3` on `$PATH`:

```
test/agent-loop/run.sh                  # the full loop, both channels, the router-bug regression, Proposal 05's write path
test/agent-loop/tenant-swap.sh           # runs run.sh twice with two differently-shaped workers, diffs the outcome
test/agent-loop/modal-headless-test.sh   # drives castle-modal with canned stdin, zero compositor
```

- **`run.sh`** (the `agent-loop-test` CI job) runs the whole loop —
  intake, router, a scripted worker, router again, digest — with zero
  models and zero network. Both canned errands now also raise a
  mid-errand `question` before their `result` (docs/tasks/0009 item 7's
  third gap: nothing previously produced one in CI); the requested
  errand's question is answered for real via `castle answer`, and the
  script asserts the resulting `state/resident-model.md` entry cites
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
  canned stdin at `castle-modal` in both modes and asserts on the
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
