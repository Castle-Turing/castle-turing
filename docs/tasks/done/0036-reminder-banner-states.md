# Task 0036 — The reminder banner says what is actually true

**Before starting:** read `CLAUDE.md` in full; then
`docs/tasks/0032-password-hash.md` §4 ("The password-reminder
machinery"), §5 ("The lockout story") and §6 ("mutableUsers") — this
task edits the code those sections argue for, and every deliberate
decision in them survives; then the password-reminder block of
`modules/base/default.nix` (the check service, its path unit, and the
`interactiveShellInit` banner), whose comments carry 0032's reasoning
inline. This brief promotes and deletes
`docs/backlog/the-reminder-banner-cannot-say-you-have-no-password.md`
in the commit that adds it, per the backlog convention.

Work on branch `emcee/0036-reminder-banner-truthful`, in its own
worktree. Do not touch `agent/`, `modules/agent/`, `modules/home/`, or
`.github/workflows/check.yml` — PR #63 owns those files.

## Why

The password-reminder banner has exactly two states: absent, and "this
account is still using its seeded initial password. Run `passwd` to
set your own." There is a third real state it cannot express: **the
account has no password at all**, because the seed never decrypted at
account creation. Since 0032, the check *detects* that state — the
`case` guard leaves the marker untouched when the shadow field is `!`,
`!!`, `*` or empty — but the only vocabulary it has is a boolean
marker whose absence means "seeded", so the banner tells a resident
with no password that they have a seeded one.

The state is reachable and not exotic: a first install with a missing
or wrong age key creates the account locked, and because
`users.mutableUsers` is `true`, fixing the key and rebuilding never
repairs an account that already exists (0032 §5, §6). The resident
most in need of instruction currently gets the instruction written for
someone else — and worse, the instruction is insufficient in their
state: plain `passwd`, run as an account with no password, cannot
authenticate the current password and fails. The remedy that actually
works is a root-privileged `passwd <user>`.

Two facts, both verified against `modules/base/default.nix`, make the
honest message short:

1. **Anyone reading the banner already has a shell.** The banner is
   `environment.interactiveShellInit`; with no password there is no
   console login, so the only way to reach an interactive shell is
   key-based SSH (as the admin or as root — `cfg.sshKeys` is installed
   for both). The message therefore never needs to explain how to get
   in; whoever sees it is in.
2. **`security.sudo.wheelNeedsPassword = false`**, and the admin is in
   `wheel`. So `sudo passwd <user>` works from the admin's own
   key-authenticated shell with no password set, and works trivially
   from root's. One command, true for every viewer. This answers the
   backlog entry's open question about naming SSH recovery: the banner
   does not need to mention SSH at all.

## The design

### The states, enumerated

The check classifies the admin account into exactly one of four
states, and the first three each have a defined banner:

| # | Evidence | State files | Banner |
|---|---|---|---|
| 1 | shadow field (after stripping up to two leading `!`) is a hash equal to the seed | neither file | "the `<user>` account is still using its seeded initial password. Run `passwd` to set your own." |
| 2 | stripped field is a hash differing from the seed | `password-changed` | silent |
| 3 | stripped field is empty or `*` — no usable password exists | `password-absent` | "the `<user>` account has no password at all: most likely its seed never decrypted when the account was first created, and a rebuild will not repair an existing account. Set one now with `sudo passwd <user>`." |
| 4 | a real hash exists but the seed file is unreadable | markers left as they were — except that a hash appearing *after* `password-absent` is proof of a hand-set password (the seed never reached shadow), so that one transition records `password-changed` | whatever the recorded state says |

The literal strings (including the `printf` escape sequences around
them) are pinned by the flake check below; the table gives the prose.

State 3's wording, clause by clause: "has no password at all" is
literally true for every field shape the guard groups (`!`, `!!`, `*`,
empty — none carries a usable password); "most likely its seed never
decrypted" is hedged because `passwd -d` produces the same evidence
and the check cannot tell them apart; "a rebuild will not repair an
existing account" is 0032 §6's trap, stated because it is exactly the
fix a resident would otherwise reach for; and `sudo passwd <user>` is
the one remedy that works from every shell that can display the
message. The banner does not cite documentation: the machine showing
it may be nowhere near a checkout of this repo.

Both messages now name the account instead of saying "this account".
Every interactive shell shows the banner — root's included — and in
state 3 a shell that is *not* the admin's is precisely who is likely
to be reading it. "This account" was a second, smaller falsehood of
the same species this task exists to remove. Naming the username in
the generated shell init discloses nothing: it is already in
`/etc/passwd` and in the store via `users.users.<name>`.

### The vocabulary: a second marker, not a replacement state file

`/var/lib/castle-turing/password-changed` keeps its exact 0032
meaning: present if and only if the resident demonstrably has a
password they chose. A new sibling,
`/var/lib/castle-turing/password-absent`, means the shadow field
demonstrably carries no usable password. The check maintains the
invariant that at most one exists; the banner reads `password-changed`
first (silent), then `password-absent` (state 3's message), else
state 1's message — so a reader racing the check between its two file
operations sees at worst a momentarily stale banner, never a wrong
silence becoming permanent.

A single state *file* (one path holding `changed`/`seeded`/`absent`)
was rejected: it would rename the artifact 0032 named and reason
about, break the marker an already-deployed machine has on disk until
the check next runs, and buy nothing — the two-marker form encodes the
same three-plus-unknown states.

### What changes in the check script

The script reads `/etc/shadow` and runs the strip-and-classify guard
**before** touching the seed, because state 3 is knowable from shadow
alone. This matters for the headline scenario: with a missing age key,
the seed is unreadable *and* the account has no password, and the old
order exited at the unreadable-seed guard before ever looking at
shadow — so the one machine the fix is for would have kept showing the
seeded-password lie. New order:

1. Read the shadow field; strip up to two leading `!` (both strips are
   0032 review findings and keep their comments).
2. Empty or `*` → touch `password-absent`, remove `password-changed`,
   exit. Removing `password-changed` here is a deliberate, argued
   deviation from 0032's leave-it-alone: 0032 could not act because
   its only vocabulary was a boolean whose absence means "seeded", so
   any write was a lie in one direction or the other. With a word for
   the state, acting is honest — the field is positive evidence that
   no chosen password exists *now*, and leaving `password-changed` in
   place would silence the banner on an account with no password,
   which is the exact silencing class 0032 fixed.
3. Otherwise a real hash exists. If the seed is unreadable, mostly
   say nothing (0032's branch, unchanged in meaning) — with one
   decidable exception, caught by cross-model review: if
   `password-absent` is on disk, this hash cannot be the seed
   (creation with an unresolved seed writes a lock, never the seed),
   so the transition is proof of a hand-set password and records
   `password-changed` even seedless. Without it, `sudo passwd` on a
   machine whose key was never fixed cleared `password-absent` into
   the *seeded* message — a fresh falsehood on exactly the machine
   this task is for.
4. Seed readable → compare and set/remove `password-changed` exactly
   as before; each branch clears `password-absent` after its own
   decisive write. Marker writes are ordered so that a crash between
   any pair leaves either a correct state or one that nags — never a
   wrong silence.

Two non-states are also guarded: a shadow file with *no line for the
account at all* (a renamed username, a mid-rewrite copy) is not
evidence and touches nothing, and a stale crash-persisted double
marker heals on the next decidable run — both pinned in the table
test.

Everything 0032 settled stays settled: the check never locks anything,
never forces expiry, runs as the same root oneshot plus
`/etc/shadow` path unit, dereferences the seed at check time, and no
hash material reaches the store or any world-readable path — the new
marker, like the old, is an empty flag file.

### Test seams

The script's three external paths (`/etc/shadow`, the state directory,
the seed file) become positional parameters defaulting to the real
values. systemd invokes the script with no arguments, so a real
machine always uses the real paths; the flake check invokes the same
generated script — not a copy — against fixtures. The banner snippet
gets no seam: its paths stay hardcoded, and its logic is pinned
textually instead, keeping user environment out of what it prints.

## Considered and rejected

- **One reworded string covering both states** ("this account is not
  using a password you chose") — the backlog entry's own suggestion.
  True in both states, but it forfeits the whole value: state 3's
  reader needs to know they have *no* password, that plain `passwd`
  will not work for them, and that rebuilding will not fix it. A
  message honest in the aggregate and unhelpful in the one state that
  matters is the current defect with better grammar.
- **Naming SSH in the message.** Unnecessary (see "Why": every viewer
  already has a shell) and it would re-enter
  `docs/tasks/0003-findings.md` finding #1's territory about assuming
  SSH reachability on a Wi-Fi-only machine.
- **A negative-path VM install to reach state 3 in CI.** Weighed and
  rejected in 0032's "Considered and rejected"; nothing here changes
  that arithmetic. Instead the state machine itself is table-tested
  against the generated script (below), which covers exactly the logic
  a negative-path install would exercise, minus the
  `update-users-groups.pl` behavior 0032 already traced against
  source.
- **Gating the banner to the admin's own shells.** Root reading the
  banner is a feature — in state 3, root over SSH is the recovery
  path's actor. Naming the account fixes the falsehood without hiding
  the information.

## Verification plan

Automated, in bare `nix flake check` (so `check.yml`'s existing
flake-check job runs it on every PR, untouched):

- **`checks.x86_64-linux.password-reminder-states`**
  (`test/password-reminder/check.nix`): takes the *generated* check
  script and the *generated* `interactiveShellInit` text from
  `nixosConfigurations.example`, per the read-the-generated-artifact
  rule. It (a) runs the script across a table of shadow-field ×
  seed-readability × prior-marker combinations — including `!` with an
  unreadable seed, the missing-key machine — asserting the resulting
  marker pair for each; and (b) pins the banner's exact three-way
  block, messages and escape sequences included, with a fixed-string
  whole-block match, so the precedence (`password-changed` silences,
  `password-absent` outranks the seeded message) is part of the pin.

Automated, in the slow VM-install workflow (`vm-install-test.yml`,
also untouched — only `test/vm-install/run.sh` gains a phase):

- **Phase 2e** asserts a real interactive bash over SSH prints the
  state-1 message naming the fixture account. The fixture secret
  always decrypts and nobody runs `passwd`, so the installed system is
  deterministically in state 1. This proves the wiring — that
  `interactiveShellInit` actually reaches the shell a resident gets —
  which no string pin can.

Not automated, stated honestly: no CI run ever *boots a machine into*
state 3 (the 0032 rejection, kept). The claim that a locked account
plus this script yields this banner rests on the table test driving
the real generated script, plus 0032's source-traced account of what
`update-users-groups.pl` writes.

## File-by-file change list

- `docs/backlog/the-reminder-banner-cannot-say-you-have-no-password.md`
  — deleted (promoted to this brief, same commit).
- `docs/tasks/0032-password-hash.md` — one citation of the deleted
  backlog path updated to point here (same commit; the promote
  convention says to check citations of the deleted path).
- `modules/base/default.nix` — the check script restructure, the
  second marker, the three-state banner, and the comment blocks
  updated to match (including the module's own citation of the deleted
  backlog path).
- `test/password-reminder/check.nix` — new; the table test and banner
  pin described above.
- `flake.nix` — wires the new check as
  `checks.x86_64-linux.password-reminder-states`.
- `test/vm-install/run.sh` — phase 2e.
- `test/vm-install/README.md` — phase 2e added to the assertion and
  troubleshooting lists.
