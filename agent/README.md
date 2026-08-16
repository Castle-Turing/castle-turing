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
  a request does. Also the resident model's only write path
  (Proposal 05, `docs/tasks/0009`): if the question record carries a
  `fact` field (or one is passed with `--fact`), answering it appends
  an entry to `state/resident-model.md` alongside the journal `answer`
  record — see "The resident model" below.
- **`record`** — the generic writer underneath both of the above, and
  what a worker or router seat calls directly. Any seat, any type.
  `--fact` is honored here too so a worker raising a `question` record
  can name the fact it's eliciting up front.
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
  has to remember, it's the only thing the function does.
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
  it), in creation order. This *is* the digest surface from
  `docs/architecture.md` — invoked by hand in this skeleton, per
  `docs/tasks/0008`'s non-goals; scheduling it is later work.
  `castle-modal`'s status mode is a compact, "recent errands only"
  variant of the same fold.
- **`validate`** — schema-checks a journal: every required field
  present, `type` and `provenance` in their allowed sets, every
  `decision` record's `evidence` field non-empty, every `refs` entry
  pointing at a record that actually exists. This is what CI asserts
  with (`test/agent-loop/run.sh`).
- **`show`** — prints one record verbatim, checking the journal then
  the spool.

## `castle-modal` — the ambient intake

A floating `foot` terminal (bound to `Mod4+Shift+space` in
`modules/home`'s Sway config — see that module for why this chord and
not another) running `agent/castle-modal`, a second stdlib-only Python
script that imports `agent/castle` in-process rather than shelling out
to it. Two modes:

```
castle-modal --mode compose [--limit N]
castle-modal --mode status  [--limit N]
```

- **compose** (the default) — reads multi-line free text from stdin
  until a line containing exactly `.` or EOF, and files it as a
  `request` record exactly like `castle ask` would. No category
  picker, no priority field: the whole premise is that the resident
  describes a symptom in their own words and doesn't know (or shouldn't
  need) the system's vocabulary for it.
- **status** — folds the `--limit` most recent errands (default 10)
  from the journal into a compact listing: what was asked, whether it's
  in progress, waiting on the resident, or done, and what the router
  most recently decided and why. The "come back later and check" half
  of the design.

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
| `type`       | One of `request`, `decision`, `result`, `question`, `answer`.         |
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

### Provenance, concretely

`castle route`'s entire rule set, today: a `result` or `question`
record with `provenance: requested` routes to channel `notify`; one
with `provenance: initiated` routes to channel `digest`. No sensors, no
salience estimate — just the one fact the architecture doc identifies
as doing more channel-selection work than anything else, because it's
a fact rather than a judgment. A worker propagates the provenance of
the request it's fulfilling onto its result (and any `question`) record
— see `test/agent-loop/scripted-worker.sh` for the reference
implementation of that propagation.

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
  by a private layer — is wired into `CASTLE_STATE_DIR` for every login
  shell. See `docs/private-layer.md` for what a resident actually
  points that at (the private repo's own `state/` directory, so the
  journal survives a reinstall).
- `CASTLE_STATE_DIR` is also what makes `test/agent-loop/run.sh`
  possible without touching a real resident's journal: it points every
  `castle` invocation in that harness at a throwaway temp directory.

## The resident model

Living at `state/resident-model.md` in the private repo
(`docs/private-layer.md`) as a sequence of entries in the same flat
frontmatter style as records above (though the file itself is not a
`castle`-managed record: no `id`/`type`/`refs`, just `fact`/`asked`/
`answered`/`when`), one entry per fact, each carrying its own
provenance per Proposal 05 (`docs/architecture.md`): what was asked,
what was answered, when. Behavioral signal may raise a question's
priority or mark an entry stale; it may never write one.

`docs/tasks/0008-agent-layer-skeleton.md` shipped the format with zero
tooling — the errand's posture question ended in a hand edit.
`docs/tasks/0009-ambient-intake.md` built the write path, and it is
narrow on purpose: `append_model_entry()` in `agent/castle` is called
from exactly one place, `cmd_answer`, which only ever runs because a
human typed an answer at this CLI (or at `castle-modal`, which calls
the same code). No code path from `cmd_route` or `cmd_work` — router
and worker — ever touches it. The fact name comes from the `question`
record's own `fact` field by default (the seat that raised the
question is the one that knows what it's eliciting), or from
`castle answer --fact NAME` explicitly. The entry's body is the literal
question and answer text, not a summary — this tool has no
interpretive capability to summarize with, and per Proposal 05 it
should not gain one; the honest account of what was asked and what was
said is the whole entry. An entry looks like this (values below are an
invented, obviously-fake example — nothing here describes any real
resident):

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

This is `append_model_entry()`'s actual rendered format (`castle
answer`'s literal `Q:`/`A:` lines), not a paraphrase of it — the second
sentence of the answer above is exactly what the resident typed, kept
verbatim rather than summarized, per Proposal 05.

A private layer's `state/resident-model.md` ships as an empty file (or
absent entirely) until the first elicited answer gives it a first
entry — see `docs/tasks/0008-agent-layer-skeleton.md`'s real-errand
verification plan for how that first entry gets written on the
reference host.

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
  compositor that will normally launch it.
