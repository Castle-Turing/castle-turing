# Task 0034 — One chord, one surface: the modal becomes an inbox

## Context

The first live dispatched errand (2026-08-31, request
`20260831T232114Z-request-5530bf`) exercised the whole loop — chord,
compose, dispatch, worker turn, result, notify — and the resident's
review of the experience found the loop complete but the *surfaces*
fragmented:

- Three modes, three entry points, unevenly wired: compose is bound
  (`Mod4+Shift+Return`), answer is bound (`Mod4+Shift+a`), review and
  status are bound to nothing and reachable only by typing an
  invocation into a terminal.
- The notify channel fired correctly (mako displayed "Castle Turing —
  result"), but the notification is a dead end: clicking dismisses it,
  the body does not say which request it answers, and there is no
  gesture from the announcement to the answer.
- The resident's explicit direction: **one chord for everything**, not
  a chord per function. This system has one user; muscle memory for
  the old chords is not a constraint.

This brief makes the modal a single surface with an inbox at its
center, and makes the notification a deep link into it.

## The design

### 1. One chord, one modal, views within it

`Mod4+Shift+Return` remains the only Castle chord. `Mod4+Shift+a` is
removed. The chord opens `castle-modal` in a new **inbox** layout with
two views:

- **Compose view** — what the chord opens into, because the most
  common act is speaking (the resident's call: the chord carries no
  information about *why* it was pressed, so it opens the thing most
  often wanted; contrast the notification, below, which does know).
  Identical to today's compose mode, plus one static line above the
  prompt when items are waiting: `N ready — Tab to view`. A count and
  a key, nothing else — no summaries, no suggestions. (The line is
  static information, not initiative; where the boundary to
  Clippy-territory lies is recorded in
  docs/backlog/the-modal-could-choose-its-opening-view.md.)
- **Inbox view** — `Tab` from compose (and `Tab` back). A list,
  ordered by what the journal can derive with no new state:
  1. blocking questions with no `answer` record (the turn is
     suspended on you);
  2. proposals with no `decision` record (a worker is done and
     waiting on your verdict);
  3. results the read cursor (below) has not seen;
  4. nothing else — closed items belong to `castle digest`, not to an
     inbox. An empty inbox says so and offers compose.

  `Enter` on an item opens the view that item needs: a question opens
  today's answer flow, a proposal opens today's review flow, a result
  renders its record body (which since 0023/0033 already carries
  everything a cold reader needs). `Esc` backs out one level;
  `Esc` at the top closes the modal, preserving compose's existing
  discard semantics.

Existing modes stay available as flags (`--mode compose|status|answer|
review`) for scripts and tests; the *chords* are what this brief
unifies. `--mode status` is unchanged by this brief (its vocabulary
problems are already filed:
docs/backlog/status-surface-internal-vocabulary.md).

### 2. The read cursor: new state, owned by the surface

"Unread result" is a notion the journal deliberately cannot hold —
records are append-only and nothing about a result changes when the
resident reads it. Precedent for surface-owned state already exists:
the dispatch watermark records "dispatch began here" without editing
any request it excludes.

The inbox keeps a cursor file, `$CASTLE_STATE_DIR/inbox-seen`, one
record id per line, appended when a result's body is actually rendered
(not when the list containing it is shown). Questions and proposals
never touch the cursor: their pending-ness is derivable (no answer
record, no decision record), and deriving beats recording wherever
possible. The file lives beside `journal/`, not inside it — it is
state, not a record; it syncs with the state repo, which is correct
for a one-resident system (seen-ness follows the resident, not the
machine); and losing it costs a few once-read results reappearing as
unread, which is the cheap direction to fail in.

### 3. The notification: an announcement that deep-links

The notify channel currently execs `notify-send <summary> <body>` and
moves on. Three changes:

- **Body carries the request's own words.** The router already holds
  the originating request when it routes a result; the notification
  becomes `Castle: your request has an answer` / first line of the
  request, truncated. The resident should never have to remember what
  they asked from a bare "result".
- **`--app-name=castle`**, so notification daemons and their
  configuration can address Castle's notifications as a class.
- **A click opens the item.** `notify-send --action=open,Open`
  implies `--wait`: it blocks until the notification is activated,
  dismissed, or expires, and prints the chosen action name to stdout.
  The notify invocation therefore detaches a small waiter (setsid,
  output to the journal directory's logs? no — stdout read via pipe;
  see implementation prompt) whose whole job is: if `open` is
  printed, exec
  `foot --app-id=castle-modal -e castle-modal --mode inbox --focus <record-id>`;
  on dismiss/expiry, exit silently. The dispatch sweep must never
  block on this — the waiter is detached before the sweep continues,
  and a waiter that outlives interest costs one idle process per
  un-clicked notification until expiry.
- `--focus <id>` opens the inbox view scrolled to and expanded on
  that record — the one case where the surface knows why it was
  opened, so it opens there rather than in compose.
- **If the modal is already open when the notification is clicked**,
  the waiter must not spawn a second instance: two modals means two
  compose buffers and a read cursor written from two processes. The
  waiter asks Sway first (`swaymsg -t get_tree`, match
  `app_id=castle-modal`) and, if a modal exists, focuses that window
  instead of launching — accepting that the *running* instance stays
  on whatever view it was on rather than jumping to the clicked item.
  Reaching into a live instance to redirect it (a control socket, a
  signal) is more machinery than the case earns today; the focused
  modal's inbox is one `Tab` away and shows the item at the top. If
  in-flight redirection ever matters, that is the same plumbing chat
  mode needs (see the chat backlog entry) and should be designed
  there, once. The headless harness covers the decision logic (a
  fake `swaymsg` on `$PATH`); the two real-window behaviors are part
  of the one human verification click.

This is daemon-agnostic: any freedesktop-compliant daemon supports
actions; mako's default `on-button-1=invoke-default-action` makes a
plain click fire it. No mako-specific configuration is required, which
keeps the mechanism portable (Principle 01: the private layer may run
a different daemon).

### 4. Wording: intake stops presuming a grievance

The compose prompt currently reads "Describe the problem in your own
words." The first real request through the system was a feature wish,
not a problem, and the resident flagged the framing. The prompt
becomes: **"What do you need? Describe it in your own words."** — same
free-text, no-category-picker discipline (0009's decision stands),
minus the presumption. The record type (`request`) was always neutral;
only the surface language lagged.

## Considered and rejected

- **A chord per view** (status chord, review chord…): rejected by the
  resident directly — one chord for everything. The removed
  `Mod4+Shift+a` is not kept as an alias; a one-user system does not
  need compatibility with its own three-week-old habits.
- **Notification click opens compose-default like the chord**:
  rejected — the click carries provenance the chord lacks. Symmetry
  here would discard information.
- **`seen` as a journal record type**: rejected — one record per
  read result doubles journal noise to record something no other seat
  ever consults. The watermark earns record status because dispatch
  *decisions* depend on it; seen-ness is private to one surface.
- **mako `on-button-1=exec` criteria instead of freedesktop actions**:
  works, but binds the mechanism to mako specifically and cannot carry
  the record id (mako's `$id` is the daemon's notification id). The
  action-waiter is portable and id-precise.
- **Intelligent choice of opening view**: deliberately out — filed as
  backlog with the resident's Clippy boundary noted.

## Non-goals (filed as backlog in this same change)

- Whether `Mod4+Shift+Return` is even the right chord —
  `Mod4+Space` may have cross-tool precedent worth copying rather
  than inventing UX (docs/backlog/the-modal-chord-may-be-the-wrong-default.md,
  a research brief).
- A **chat mode** — implies a conversational turn contract the
  one-shot worker seat does not have
  (docs/backlog/chat-mode-implies-a-conversational-turn-contract.md).
- An **ambient waiting indicator** in the swaybar
  (docs/backlog/nothing-ambient-says-items-are-waiting.md).
- The modal choosing its opening view intelligently
  (docs/backlog/the-modal-could-choose-its-opening-view.md).

## Hard constraints

- `castle-modal` stays stdlib-python, terminal-first, in `foot` — the
  substrate argument in its own header comment is unchanged.
- The journal remains append-only; nothing in this brief edits or
  reinterprets an existing record. The cursor is a new file, never a
  mutation.
- No personal data in the public repo: examples in code and tests use
  the CI harness's synthetic records, never the reference host's real
  journal.
- Public mechanism / private configuration: everything here is
  mechanism; the only private-layer surface is the existing
  keybinding override point (a resident can rebind the chord in
  `resident.nix`, which is how the backlogged chord research will be
  cheap to act on).

## File-by-file

- `agent/castle-modal` — inbox layout (compose + inbox views, Tab
  toggle, Enter-dispatch to answer/review/read, `--focus`), read
  cursor, prompt rewording.
- `agent/castle` — notify invocation: app-name, request-words body,
  detached action-waiter.
- `modules/home/default.nix` — `Mod4+Shift+Return` → inbox modal;
  remove `Mod4+Shift+a`.
- `test/agent-loop/modal-headless-test.sh` (+ `pty-drive.py`) — inbox
  ordering, cursor append-on-read, focus, Tab/Enter/Esc flows.
- `test/desktop-loop/test.nix` — the binding change; assert the
  notification carries the request words and an action.
- `agent/README.md` — surfaces section rewritten around one chord.

## Verification plan

Agent-verifiable, no human needed:
- `test/agent-loop/modal-headless-test.sh` drives every keyboard path
  over the PTY harness: ordering of a mixed journal (question +
  proposal + unread result + read result), cursor written only on
  render, `--focus` landing, prompt wording asserted literally.
- `test/desktop-loop/test.nix` asserts the single binding exists, the
  removed one is gone, and a routed result produces a notification
  with `app-name=castle`, the request's words, and exactly one action.
- `nix flake check` and the existing agent-loop suites stay green.

Genuinely human:
- One real click on one real notification on the reference host — the
  action-to-modal handoff crosses mako, foot, and Sway focus in a way
  no headless test faithfully reproduces. One minute, once.

## Implementation prompt

You are implementing task 0034 in the Castle Turing public repo. Read
this brief in full, then `agent/castle-modal`'s header comment,
`agent/castle`'s notify/route sections, and
`test/agent-loop/modal-headless-test.sh`'s harness conventions before
writing anything. Work on the branch this brief rides; do not touch
the primary checkout. The four backlog entries named under Non-goals
are committed alongside this brief — do not implement any of them.
Constraints that are load-bearing: stdlib-only Python, append-only
journal, detached waiter (the dispatch sweep must be strace-provably
non-blocking on notification interaction), and the compose prompt's
exact new wording. The read cursor is append-only too: never rewrite
`inbox-seen`, only add lines. If any part of this brief conflicts
with what you find in the code, stop and say so in your report rather
than resolving it silently; record every judgment call this brief
left you to make.

## Implementation deviations (recorded by the implementing session)

- `notify-send`'s action flag is spelled `--action=open=Open`, not
  `--action=open,Open` as this brief wrote: the real syntax is
  `[NAME=]Text` (verified against notify-send 0.8.8's own help). The
  mechanism is otherwise exactly as designed.
- "`Enter` on an item" is realized as the established one-keypress
  digit grammar: the list is numbered and a digit opens an item. A
  bare Enter deliberately opens nothing — opening a result spends the
  read cursor, and a reflex key must not mark something read.
- Inbox category 1 lists every unanswered non-proposal question,
  blocking ones first, not blocking questions alone: a non-blocking
  question the answer picker offers must not be absent from the inbox,
  or the surface could hide a question by construction.
- Question notifications keep the question's own words as the body
  (they are the actionable text; the request's words sit behind the
  click) plus a hint naming the one remaining chord; the request-words
  body applies to results, as specified.
- The request-words body for a result is scoped to `seat: worker`
  results, not every result: this brief's §3 wording ("a result
  carries the request's own words") did not anticipate an applier-seat
  result, whose own first line is not a fallback but the entire point
  of `APPLY_FIRST_LINES` (docs/tasks/0026-apply-validate.md §H) —
  harness prose drafted specifically to be what the resident is told an
  approval did. Applied unscoped, an apply notification silently became
  the ORIGINAL request's first line again (an apply result's `refs`
  chain reaches the same root request its earlier worker result did) —
  the words the resident already saw once when the worker finished,
  standing in for a completely different event ("your change was
  applied") they were then told nothing about. Caught by
  `test/agent-loop/apply.sh`'s own notification assertion once fixed to
  poll for the detached waiter instead of reading the log immediately
  (the immediate read was racy on its own, and fixing that race is what
  let the assertion actually run long enough to catch this). Every
  other seat's result (today: only the applier) keeps using its own
  body — the pre-0034 behavior `_write_apply_result`'s own docstring
  already documented as the contract.
