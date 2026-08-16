# Task 0009 — The ambient intake: a keybinding, a modal, and a working worker

**Before starting:** read `CLAUDE.md`, `docs/vision.md`, both docs in
`docs/principles/`, `docs/architecture.md` (the spec this implements),
and `docs/tasks/0008-agent-layer-skeleton.md` plus the code it produced —
this task consumes 0008's records, journal, and router directly. Work on
the `agent-layer-skeleton` branch; this brief rides it. PR to `main`.

**Goal.** The feature the resident actually asked for: press a key,
describe a problem in your own words, walk away, and come back later to
find out what happened. Concretely — a Sway keybinding opens a modal
that both composes a new request and shows the state of recent ones; a
worker seat with a real tenant executes the errand; the router surfaces
the outcome through a channel it chose and logged.

**Why now.** 0008 built the skeleton and proved it with scripted tenants
in CI. Everything in it is invoked by hand from a terminal, which is
exactly the ergonomic the resident said they did not want: *"I shouldn't
need to open up Claude Code or god forbid a web browser."* This task
makes the loop ambient. It is also the first time a seat is held by a
real, non-scripted tenant — the second half of Proposal 03's hardening
test.

## Verification plan

**No human needed (CI):**

- The modal is a script reading stdin and writing records; drive it
  headlessly with canned input and assert the request record it produces.
  No compositor required.
- Worker-tenant swap: run `test/agent-loop/` twice, once with the
  scripted tenant and once with a second scripted tenant of a different
  shape, asserting identical record-level outcomes. This is Proposal 03's
  "at least one seat re-tenanted with no structural change" — proven
  structurally rather than by burning tokens in CI.
- The display-preference options evaluate at all three layers (module
  default, host-supplied, private override) in `nix flake check`.
- Existing vm-install harness stays green; vm-test still imports no
  agent module.

**Human hands (morning, ~5 minutes):** deploy, press the keybinding,
type "the cursor is too small", walk away, come back, read what the
system decided, keep or roll back. This is 0008's deferred errand run
through the real intake rather than a CLI.

## Scope

1. **Display preferences as a three-layer slot** (`modules/desktop`).
   This answers the layer question 0008's brief deliberately left to the
   errand — and answers it the Principle 01 way, with mechanism public
   and value private:
   - `castle.display.scale`, `.cursorTheme`, `.cursorSize`,
     `.terminalFontSize` — options defined in shared mechanism, all
     defaulting to null meaning "framework default".
   - `hosts/xps9370/` may supply hardware-derived values (its panel is a
     machine fact, and machine facts identify no one — they belong in the
     public host module per Principle 01 consequence 2).
   - The private layer overrides for taste, and wins.
   Wire them through home-manager: `home.pointerCursor` (which covers
   Sway's seat, GTK, and XWayland coherently in one option), foot's font
   size, and Sway output scale. Ship a cursor theme package so the
   setting has something to point at.
2. **Managed Sway configuration** (`modules/home`). The first Sway config
   this repo owns — today the desktop runs stock defaults. Keep it
   minimal and obviously extensible: the keybinding, the modal's window
   rules (floating, centered, sized), and the display settings from (1).
   Do not redesign the desktop; this is a foothold, not a ricing project.
3. **The modal** (`agent/castle-modal`, or a subcommand). A floating
   `foot` terminal running a small TUI with two modes:
   - **Compose** — multi-line free-text description of the problem, plus
     nothing else. No category picker, no priority dropdown; the whole
     premise is that the resident describes a symptom in their own words
     and does not know the vocabulary.
   - **Status** — recent errands folded from the journal: what was asked,
     what state it's in, what the system decided and why. This is the
     "come back and check in later" surface.
   Bind it to a Sway keybinding (suggest `$mod+Shift+space`; pick
   something with no stock Sway conflict and document the choice).
4. **The worker seat gets a real tenant.** `castle work <request-id>`
   invokes a worker command that is a **Nix option**
   (`castle.agent.worker.command`), defaulting to a headless
   `claude -p` invocation — `modules/dev` already installs claude-code.
   The contract stays at the errand boundary per Proposal 03: request
   record in; result record, diff, and journal entries out. The tenant
   receives the request body and repo context, and must produce its
   reasoning into the result record — the journal, not a scrollback, is
   where the account lives. CI overrides the option with a script.
   **The worker proposes a diff; it does not deploy.** Applying a
   configuration change to the running system stays a resident action in
   this slice (see Non-goals).
5. **A real interruption channel.** Add `mako` to `modules/desktop` and
   give the router a `notify` channel alongside `digest`. Now the
   router's provenance rule has two genuinely different outputs and its
   decision records mean something. The channel chosen and why goes in
   the decision record, per Proposal 04.
6. **Docs.** `docs/private-layer.md` gains the display-preference slot
   and the worker-command option. `docs/architecture.md` gains the modal
   and notify channel to the seats/surfaces list. `hosts/xps9370/README.md`
   documents any hardware-derived display values it supplies.

7. **Three gaps 0008 left open**, found reviewing its output — all
   small, all on the critical path for the real errand:
   - **The resident model has a documented format and zero tooling.**
     0008 ships `state/resident-model.md`'s shape in prose only, so the
     errand's posture question currently ends in a hand edit. Add the
     write path: `castle answer` (or a sibling) turning a question and
     its answer into a model entry carrying full provenance — the
     question asked, the answer given, when. This is Proposal 05's only
     write path and it should not be a text editor.
   - **Router bug: `castle route` treats *any* decision record's `refs`
     as proof that the referenced record was routed**, without checking
     the decision came from the router seat. A decision written by any
     other seat referencing a result would permanently suppress that
     result's routing. Not triggered today (only the router writes
     decisions); fix before something else does. Filter on
     `seat == "router"`.
   - **No `question`/`answer` record ever flows through CI.**
     `check_assertions.py` already supports asserting on them; nothing
     produces one. Since worker-questions-route-through-the-router is a
     central claim of the architecture, the scripted tenant should raise
     a question mid-errand and CI should assert it routed. This closes
     the gap 0008's own decision log flagged.

## Acceptance

- CI green: existing checks, plus headless modal test, tenant-swap test,
  and three-layer option evaluation.
- Pressing the keybinding on a real Sway session opens the modal;
  composing a request produces a valid request record; the status view
  renders it. (Human-verified in the morning, but the mechanism is
  CI-proven up to the compositor boundary.)
- The cursor errand runs end to end through the real intake, and the
  journal afterward reads as a complete, honest account — 0008's
  acceptance artifact, now reached through the ergonomic that motivated
  the whole design.
- `/code-review` run before the PR, scoped against `origin/main`.

## Non-goals

- **The worker does not deploy.** No `nixos-rebuild` from an agent seat
  in this slice. The resident reviews the diff and applies it. Autonomous
  deployment is a genuine authority-taxonomy question and deserves its
  own task, not a side effect of this one.
- Sensors. The router still runs on provenance alone; "defer to a visible
  moment" (the session-restart-aware timing discussed in design) needs a
  session sensor and waits for a later slice.
- Local/offline model fallback. The worker command is *an option*, which
  is the structural work; actually configuring a local tenant is a
  separate task with its own hardware questions.
- Desktop ricing beyond the minimum, mail/calendar intakes, digest
  scheduling.

## Coordination

Rides the same branch as 0008 and depends on its records/CLI. Territory:
`agent/`, `modules/desktop/`, `modules/home/`, `modules/agent/`,
`hosts/xps9370/`, `test/agent-loop/`, `docs/`. Rebase onto updated
`origin/main` before opening the PR and scope every diff and review
against `origin/main`, per CLAUDE.md.
