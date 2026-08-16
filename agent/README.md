# agent/ — the agent layer's tooling

This directory holds the mechanism for the agent layer described in
`docs/architecture.md`: a plain-text record format, a journal those
records live in, and a small CLI (`castle`) that plays intake, router,
digest, and validator over them. Read `docs/architecture.md` first —
this file documents the concrete formats and the CLI; the architecture
doc explains why they're shaped this way. `docs/tasks/0008-agent-layer-skeleton.md`
is the brief that built this.

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
castle answer QUESTION_ID TEXT...
castle record --type T --provenance P --seat S [--refs id,id] [--evidence TEXT] [--body TEXT | --body-file PATH] [--spool]
castle route
castle digest [--since TIMESTAMP]
castle validate [--journal DIR]
castle show ID
```

- **`ask`** — the intake seat. Writes a `request` record with
  `seat: intake`. Provenance defaults to `requested`, since a human
  typing at this CLI is definitionally the resident asking directly;
  pass `--provenance initiated` for a script filing something on the
  system's own initiative (e.g. a future cron-triggered mail sweep).
- **`answer`** — also intake: the resident's word answering a
  previously-filed `question` record, entering the system the same way
  a request does.
- **`record`** — the generic writer underneath both of the above, and
  what a worker or router seat calls directly. Any seat, any type.
- **`route`** — the router. Reads every `result` and `question` record
  not yet referenced by a `decision` record, and for each one appends
  a `decision` deciding its channel from provenance alone (see below).
  Idempotent: run it again over an already-routed journal and it does
  nothing. There is no code path in `cmd_route` that picks a channel
  without also writing the decision record for it — "no routing
  without an appended decision record" isn't a rule the tool has to
  remember, it's the only thing the function does.
- **`digest`** — folds the journal into a report: one section per
  errand (a `request` and everything transitively `refs`-linked to
  it), in creation order. This *is* the digest surface from
  `docs/architecture.md` — invoked by hand in this skeleton, per
  `docs/tasks/0008`'s non-goals; scheduling it is later work.
- **`validate`** — schema-checks a journal: every required field
  present, `type` and `provenance` in their allowed sets, every
  `decision` record's `evidence` field non-empty, every `refs` entry
  pointing at a record that actually exists. This is what CI asserts
  with (`test/agent-loop/run.sh`).
- **`show`** — prints one record verbatim, checking the journal then
  the spool.

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
`validate` — `castle route` adds a `channel` field (`now` or `digest`)
to the decision records it writes, purely so `castle digest` doesn't
have to re-derive it from prose.

### Provenance, concretely

`castle route`'s entire rule set, today: a `result` or `question`
record with `provenance: requested` routes to channel `now`; one with
`provenance: initiated` routes to channel `digest`. No sensors, no
salience estimate — just the one fact the architecture doc identifies
as doing more channel-selection work than anything else, because it's
a fact rather than a judgment. A worker propagates the provenance of
the request it's fulfilling onto its result record — see
`test/agent-loop/scripted-worker.sh` for the reference
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

Not built by this task beyond its format and an empty slot — `castle`
has no subcommand that reads or writes it yet. It is prose, not a
`castle`-managed record type, living at `state/resident-model.md` in
the private repo (`docs/private-layer.md`) as a sequence of entries in
the same flat frontmatter style as records above, one entry per fact,
each carrying its own provenance per Proposal 05
(`docs/architecture.md`): what was asked, what was answered, when.
Behavioral signal may raise a question's priority or mark an entry
stale; it may never write one. An entry looks like this (values below
are an invented, obviously-fake example — nothing here describes any
real resident):

```
---
fact: cursor-fix-posture
asked: 20260816T130200Z-question-9f2a11
answered: 20260816T130700Z-answer-c04dd2
when: 2026-08-16T13:07:00Z
---

Prefers small perceptual fixes (e.g. cursor size) applied and reported
afterward rather than being walked through the diff first. Elicited
once, from one low-stakes errand — may not generalize to changes with
real consequences if reverted.
```

A private layer's `state/resident-model.md` ships as an empty file (or
absent entirely) until the first elicited answer gives it a first
entry — see `docs/tasks/0008-agent-layer-skeleton.md`'s real-errand
verification plan for how that first entry gets written on the
reference host.

## Testing

`test/agent-loop/run.sh` runs the whole loop — intake, router, a
scripted worker, router again, digest — with zero models and zero
network, wired into CI as the `agent-loop-test` job
(`.github/workflows/check.yml`). It's plain bash and stdlib Python; no
Nix involved, unlike `test/vm-install/`'s harness. Run it locally with
no setup beyond a `bash` and a `python3` on `$PATH`:

```
test/agent-loop/run.sh
```
