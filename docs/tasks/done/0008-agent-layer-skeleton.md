# Task 0008 — The agent-layer skeleton, proved by one real errand

**Before starting:** read `CLAUDE.md`, `docs/vision.md`, both docs in
`docs/principles/`, and — closely — `docs/architecture.md`, which
rides this branch and is the spec this task implements. Work on the
`agent-layer-skeleton` branch; this brief rides it. PR to `main`.

**Goal.** The agent layer exists: records, journal, router, resident
model, intake, and digest — built for real, thin everywhere it can
afford to be — and one real errand has traversed all of it end to end
on the reference host. The errand is small on purpose: the resident's
cursor is too small. The architecture is the deliverable; the cursor
is the proof.

**Why now.** Every merged task so far is substrate. The vision's
central bet — an agent safely modifying a declaratively-configured
machine, with a legible decision history — has never once been
exercised. This task exercises it at the smallest possible scale,
and forces the record schema, the provenance rule, the router's
evidence obligation, and the runtime-state home to stop being prose
and become checked artifacts. Per `docs/architecture.md`, "built for
real" means the artifacts and contracts; the seats may be held by
whatever is available, including a human.

## Verification plan

**No human needed (CI):**

- A scripted-tenant run: a canned `request` record goes through
  intake → router → a scripted worker (a shell script emitting a
  canned `result` and diff) → digest. Assertions: every record
  validates against the schema; every decision record has a non-empty
  `evidence` field; the digest fold renders the errand; the router
  refused to route anything without appending a decision record. Zero
  models, zero network — this is Proposal 03's hardening test taking
  its first steps.
- The existing vm-install harness stays green with the vm-test host
  importing **no** agent module — the anti-bricking clause as a
  regression test. Keep `nix flake check` green throughout.

**Human hands (the real errand, on the xps9370):**

1. The resident files the request through the intake CLI: the cursor
   is too small.
2. The worker seat — a Claude Code session driven by a human, which
   Proposal 03 makes a legitimate tenant — picks up the request:
   diagnoses via `swaymsg -t get_outputs` (is this one small cursor,
   or an unscaled HiDPI panel?), decides which layer the fix lands in
   and defends the choice in the result record, produces the diff.
3. Mid-errand, the worker appends a `question` record — the posture
   question: "fix it and tell you, or hand you the line and explain?"
   The router routes it; the answer becomes the resident model's
   first entry, with full provenance. This elicitation is a required
   step, not an optional flourish: it is Proposal 05's write path
   being exercised once for real.
4. Deploy, re-login (the cursor change only takes effect on a fresh
   session), and the resident judges the result perceptually — the
   one assertion no harness can make — then keeps or rolls back.
   Either verdict is appended to the journal.
5. **The acceptance artifact is the journal afterward**: read cold,
   it must be a complete, honest account of the episode — request,
   diagnosis, question, answer, decision with evidence, result,
   verdict — with nothing important living only in a chat scrollback.

## Scope

1. **Record schema and tooling** (`agent/`). The record format from
   `docs/architecture.md` (one file per record, YAML frontmatter +
   markdown body, required fields including `provenance` and, on
   decisions, `evidence`), plus a small CLI — working name `castle` —
   with at minimum: `castle ask` (intake: write a request record),
   `castle route` (router: process unrouted records, append decision
   records), `castle digest` (fold the journal for a period). Plain
   shell or similarly boring tooling; no daemon — the router is a
   distinct invocable, not a resident process. Rewrite `agent/README.md`
   around the seat/record architecture.
2. **Journal and spool mechanics.** Journal records under the private
   layer's `state/` directory; spool under a machine-local runtime
   dir, never committed. The private repo checkout on the host is the
   journal's home; the agent commits journal records locally on a
   cadence, and **pushing stays manual** until secrets tooling
   provides a credential story (see architecture doc).
3. **The Nix slot** (`modules/agent/`, exported as
   `nixosModules.agent`). Thin: install the CLI, declare the
   state-directory option(s) the tooling reads. Optional import, like
   `desktop` — and deliberately not imported by the vm-test host.
   Document the new slot and module in `docs/private-layer.md`
   (the "agent's model of you" slot stops being empty).
4. **Resident model format.** One entry per fact, provenance per
   entry (question asked, answer given, when), per Proposal 05.
   Ships nearly empty; the errand writes the first entry.
5. **CI harness** (`test/agent-loop/`). The scripted-tenant run
   described above, wired into CI next to the existing checks.
6. **The errand itself**, run per the verification plan. Which layer
   the cursor fix lands in (host module, private layer, or shared
   mechanism with an override) is the worker's decision to make and
   defend *during the errand* — that live routing judgment is part of
   what this task exists to observe. Note: `hosts/xps9370/README.md`
   or the private layer may need a line documenting the outcome,
   wherever it lands.

## Acceptance

- CI: scripted-tenant loop green; schema and evidence assertions in
  place; vm-install harness green with no agent module; `nix flake
  check` green.
- The real errand completed end to end: cursor perceptibly fixed (or
  rolled back — a clean rollback with an honest journal is also a
  pass), journal reading as a complete account, resident model
  holding its first elicited entry.
- `docs/private-layer.md` updated; `agent/README.md` rewritten.
- `/code-review` run before the PR, scoped against `origin/main`.

## Non-goals

- The compositor keybinding / modal intake (a later slice; note that
  the cursor fix itself will likely introduce managed Sway/home
  config, paving that road).
- A harnessed or autonomous worker — the tenant stays human-driven.
- Any sensor. The router's first rule set runs on provenance alone.
- Capability-tier configuration (documented as deliberately deferred
  in the architecture doc).
- Digest scheduling or delivery — `castle digest` is invoked by hand.
- Automated pushing of the private repo's state.

## Coordination

Open PRs #16–#20 are docs/backlog-only; collision risk is low but
rebase onto `origin/main` before opening the PR and scope every diff
and review against `origin/main`, per CLAUDE.md. Territory:
`agent/`, `modules/agent/`, `test/agent-loop/`, `docs/`,
`flake.nix` outputs. The errand's own fix touches whatever layer the
worker decides it touches — that decision is journaled, not
pre-assigned here.
