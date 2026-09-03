# 0040 — `castle validate` should notice a stray state directory

Promotes `docs/backlog/validate-should-notice-a-stray-state-directory.md`
(deleted by this commit).

## What happened

On 2026-09-01, a resident's private checkout carried two directories
shaped like a journal: the real one, at the configured state dir, and an
old `state/journal/` left over from migrating state out of the flake
(docs/tasks/0030-state-outside-the-flake.md). A worker turn, asked about
a recent errand, read the stale copy — the private root, not
`castle.agent.stateDir` — took its single ancient record for the whole
journal, and reported confident anomalies ("the journal is missing the
errand that produced this diff") that were artifacts of reading the
wrong directory. Nothing in the system noticed the machine had two
things shaped like journals.

## Why this is a different hazard than `_warn_state_layout` already covers

`castle validate` and `castle digest` already warn (docs/tasks/0030) when
the *configured* state directory sits inside a git repository that
carries a `flake.nix` and is actually tracked there — a store-publishing
hazard. That check is silent about this incident's failure mode on
purpose: it asks whether the configured directory is safe, never whether
a *second*, unconfigured one exists and could be mistaken for it. A
resident who copied their journal to its new home and then deleted the
old directory with `git rm --cached` but not `rm` (or who never ran `git
add` on it at all, so it was never tracked) clears the layout check
completely while the stray copy is still sitting on disk, still
journal-shaped, still readable by anything that goes looking under
`CASTLE_PRIVATE_ROOT` instead of respecting `CASTLE_STATE_DIR`. The two
checks are independent and this task adds the second, not a duplicate of
the first.

## Fix

**1. `castle validate` / `castle digest`: a second, unconditional warning.**

A new finding, `_stray_journal_finding()`, alongside the existing
`_state_layout_finding()`: when `$CASTLE_PRIVATE_ROOT/state/journal`
exists as a directory and its resolved path differs from the resolved,
configured journal directory (`state_dir() / "journal"`), print a
`WARNING:` naming both paths and pointing at
docs/private-layer.md's "Migrating state out of the flake". Silent when
`CASTLE_PRIVATE_ROOT` is unset, when no such directory exists, or when it
resolves to the same directory the resident actually configured (the
undocumented-but-real layout where `castle.agent.stateDir` is pointed
directly at `$CASTLE_PRIVATE_ROOT/state`, which `_state_layout_finding`
already owns warning about on its own terms).

Called from the same two sites as `_warn_state_layout()`
(`cmd_validate`, `cmd_digest`), right after it, on stderr, never
affecting the exit code — same reasoning `_warn_state_layout` already
documents: an environment fact is not a malformed record, and no edit to
any journal record could fix it. Not wired into `castle dispatch`, for
the same log-spam reason `_warn_state_layout` is not (it runs once a
minute).

**2. The worker prompt: name the one real journal.**

`agent/castle-worker-claude` already tells a tenant that the journal
lives somewhere under `$CASTLE_PRIVATE_ROOT` without saying exactly
where. One line added: the resolved configured journal directory
(computed the same way `agent/castle`'s `state_dir()` does —
`CASTLE_STATE_DIR`, else `XDG_STATE_HOME/castle`, else
`~/.local/state/castle`) is named explicitly, and a lookalike directory
elsewhere under the private root is called out as not the journal. This
is strictly cheaper than the validate/digest warning and does not
replace it: a tenant is not guaranteed to be running under a checkout
where `castle validate` was ever run, and the prompt is the only lever
this project has over what a tenant trusts (see this file's own header
comment on that point).

### Non-goal: no content-based journal detection

The stray-directory check tests only whether
`$CASTLE_PRIVATE_ROOT/state/journal` exists as a directory — not whether
anything inside it parses as a journal record. A resident who happens to
have an unrelated directory at that exact path gets a false-positive
warning pointing at a migration doc that doesn't apply to them; that
costs a paragraph of reading, which is the same trade
`_state_layout_finding`'s own docstring already argues for elsewhere in
this file. Scanning contents to reduce false positives would need to
parse partial or foreign files without crashing, for a directory this
check does not otherwise touch — not worth it for a warning that never
gates anything.

## Verification

- `test/agent-loop/stray-state-dir.sh` (new, alongside
  `test/agent-loop/state-layout.sh` in the same CI job): builds a clean
  layout (configured journal only, `CASTLE_PRIVATE_ROOT` unset or with no
  `state/journal`) and asserts silence for both `validate` and `digest`;
  builds a stray layout (a real configured journal elsewhere, plus a
  `state/journal` directory under `CASTLE_PRIVATE_ROOT`) and asserts a
  `WARNING:` naming both paths, on stderr, exit code unaffected; asserts
  silence when the stray path resolves to the same directory as the
  configured one (a symlink case); asserts `castle dispatch
  --watermark-only` stays silent, matching `_warn_state_layout`.
- Wired into `.github/workflows/check.yml`'s `agent-loop-test` job, next
  to `state-layout.sh`.
- `nix flake check`.
