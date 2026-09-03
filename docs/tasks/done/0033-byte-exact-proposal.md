# Task 0033 — A proposed diff survives the journal byte-for-byte

**Before starting:** read `CLAUDE.md` in full;
`docs/backlog/a-proposed-diff-does-not-survive-the-journal.md` **in the
sibling `ct-diff-fidelity` checkout** — it does not exist on this
branch, because this brief promotes it and the promote-and-delete
convention normally fires in the same commit, but the entry lives on a
different, unmerged branch (PR #60). See "Superseding PR #60" below for
what to do about that instead of deleting a file that is not here.
Then, closely: `agent/castle`'s `run_worker_turn` from where the tenant
exits through `_write_worker_result` and `_file_proposal_question`
(the raw-bytes read and `.strip()` at ~4229, the single `finally` that
unlinks both scratch files at ~4251–4256, `diff_boundary_lines` at
~347, the `proposal-sha256` stamp at ~3442); `write_record` /
`render_record` / `parse_record` (the encoding-less `write_text` at
~1262 and `read_text` at ~489, the `splitlines()` round trip at
~493/~513); `_reject_line_breaking_fields` and its docstring (~522);
`cmd_validate`'s treatment of `diff-boundary`, `proposal-sha256`,
`target` (~5864–5948). Also `agent/README.md`'s "The record format",
"`diff-boundary`" and "`proposal-sha256` and `decision`" sections;
`docs/tasks/0024-config-target.md` §8; `docs/tasks/0025-approval.md`
§A; and `test/agent-loop/approval.sh` / `config-target.sh` for the
fixture conventions the new harness must follow.

**This branch stacks on `sprint/0025-approval` (PR #58), not yet
merged.** `diff-boundary` and `proposal-sha256` — the two fields this
task extends and distinguishes — are 0025's, and `_write_worker_result`
/ `_file_proposal_question` are the functions 0025 substantially wrote.
Scope every diff and review against `origin/sprint/0025-approval`, not
`origin/main`, until 0025 lands (`git fetch` first). Open the PR
against `sprint/0025-approval`, re-pointing to `main` only if 0025
merges first, and say so in the PR description if that happens.

Work on branch `task/0033-byte-exact-proposal` (already checked out in
this worktree, at `ce8272b`; do not create a new branch or touch any
other checkout).

## Why

`run_worker_turn` writes a tenant's proposed diff through four lossy
transforms before it ever reaches the record that is supposed to be
its durable copy, verified again on this branch (all line numbers as
of `ce8272b`; three of the four moved from the backlog entry's
citations against `main` at `f7ebd32`, noted below):

1. **`agent/castle:4229`** —
   `diff_path.read_bytes().decode("utf-8", errors="replace").strip()`.
   `errors="replace"` destroys any non-UTF-8 byte irreversibly, and
   `.strip()` removes the patch's trailing newline — precisely what
   makes `git apply` report "corrupt patch" on a last hunk. (Backlog
   entry cited `:3680`; moved.)
2. **`agent/castle:1262`** — `path.write_text(render_record(...))`,
   still with no `encoding=`, so the write is locale-dependent.
   (Backlog entry cited `:1111`; moved.)
3. **`agent/castle:489`** — `text = path.read_text()`, locale-dependent
   again on the way back in. (Backlog entry cited `:338`; moved.)
4. **`agent/castle:493` and `:513`** — `lines = text.splitlines()` and
   then `body = "\n".join(lines[i + 1:])`. `str.splitlines()` splits on
   about ten characters, not one; a diff of a CRLF file, or of any file
   containing `\f`, `\v`, U+2028 or U+2029, does not round-trip — those
   bytes come back as `\n`. (Backlog entry cited `:342` and `:367`;
   moved.)

**One structural detail also moved, worth noting because it is not
just a line number.** The backlog entry describes the tenant's scratch
file being unlinked at two separate sites (`:3825` and
`:4114–4119`). On this branch there is exactly one `finally` block,
at `agent/castle:4251–4256`, that unlinks both `diff_path` and
`target_path` in a loop. Whatever changed between `f7ebd32` and
`ce8272b` consolidated the two unlink sites into one; it does not
change this task's fix, which reads the bytes before that block runs
regardless of how many unlink call sites there are.

**`_reject_line_breaking_fields` already guards half of this
format**, and its own docstring (`agent/castle:522`, "the test is a
round trip through `str.splitlines()`, not a search") names exactly
transform 4 as the hazard it exists to close — but the guard applies
to frontmatter field values only. The diff lives in the body, which
never goes through it, and could not: a diff's meaning depends on its
leading whitespace, which is exactly the multi-line content the
guard's own docstring says belongs in the body because *it* has no
such restriction.

**`proposal-sha256` (docs/tasks/0025-approval.md §A) does not close
this.** Verified at `agent/castle:3442`: it hashes the result record
file's whole bytes, computed by `_file_proposal_question` *after*
`_write_worker_result` has already written the record — which is
after all four transforms above have already run. It proves "this
record has not changed since the proposal was filed." It cannot prove
"these are the bytes the tenant produced," because the corruption, if
any, happened before the hash was ever taken. A tamper-evidence seal
over an already-corrupted artifact is still a valid seal.

**Why it matters now, not later.** Nothing applies a diff today —
0026 is the task that will — so this is presently a latent defect. But
it is exactly the kind of defect that gets discovered as "the applier
is buggy" when 0026 lands: a diff that applies cleanly in the common
case and corrupts, or is refused, on a file with CRLF line endings or
a form feed, which is to say on someone else's configuration rather
than ours. The "docs are written for strangers" rule has an analogue
here, and it is cheaper to close before an applier exists to inherit
the bug than after.

### Superseding PR #60

`docs/backlog/a-proposed-diff-does-not-survive-the-journal.md` is the
entry this brief promotes. The promote-and-delete convention
(`docs/backlog/README.md`) normally deletes the backlog file in the
same commit as the brief that specs it — but that file was added on
PR #60, a different, unmerged branch, so this commit cannot delete it
without ever having it checked out. Two ways to resolve this, in
order of preference:

1. **Merge PR #60 first, then rebase this branch (or its eventual PR)
   onto the result, and let the rebase or a follow-up commit on 0033
   delete the file.** This keeps the promote-and-delete convention
   intact to the letter — the entry's deletion lands in the same
   history as (or immediately alongside) the brief that supersedes it.
   Recommended.
2. **Merge 0033 first and close PR #60 unmerged**, noting in the
   closure that 0033 supersedes it. The backlog file then never lands
   on `main` at all, which is a legitimate outcome (an entry is "a
   candidate, not a promise," per `docs/backlog/README.md`) but leaves
   the convention's letter unsatisfied — nothing in this history
   literally deletes a backlog file, because none was ever committed
   to the branch this problem is solved on.

The human decides which; this brief does not. Whichever happens,
0033's own commit does **not** attempt to touch a file that is not
present on this branch.

## The design

### 1. A byte-exact sidecar, written from the same bytes the boundary already gates on

In `run_worker_turn`, the tenant's diff is currently read once, at
`agent/castle:4229`:

```python
diff_text = diff_path.read_bytes().decode("utf-8", errors="replace").strip()
```

Change this to keep the raw bytes as well as the lenient decode:

```python
diff_bytes = diff_path.read_bytes()
diff_text = diff_bytes.decode("utf-8", errors="replace").strip()
```

(This also removes a double-read of `diff_path` that the current code
does not have — there was never a second read — so this is a pure
addition, not a behavior change to the read count. `OSError` handling
is unchanged: `diff_bytes` defaults to `b""` in the same `except`
branch that currently sets `diff_text = ""`.)

`diff_text`'s truthiness is **unchanged as the existing proposal
predicate** — this task does not touch when a proposal exists, only
what is preserved once one does. Every place that currently branches
on `if diff_text:` (the `diff_boundary` nonce at `:4299`, the
`if diff_text: ... else: (no diff produced ...)` body split at
`:4300–4307`) is untouched.

When `diff_text` is truthy, compute the digest before the record is
written:

```python
patch_sha256 = hashlib.sha256(diff_bytes).hexdigest() if diff_text else None
```

Pass it into `_write_worker_result` as a new keyword parameter,
alongside the existing `diff_boundary`, and have that function stamp
it into `extra` under a new field the same way it already stamps
`diff-boundary`:

```python
if patch_sha256:
    extra[PATCH_SHA256_FIELD] = patch_sha256
```

**After** `_write_worker_result` returns `result_id` (`:4474`), write
the sidecar:

```python
if patch_sha256:
    (journal_dir() / f"{result_id}.patch").write_bytes(diff_bytes)
```

This ordering — record first, sidecar second — is a judgment call this
brief is making explicitly, not one the owner's design dictated (see
"Smaller decisions" below).

The record body's rendered copy (boundary lines, ` ```diff ` fence) is
unchanged and stays exactly what `run_worker_turn` writes today. It is
hereby **explicitly decorative**, the same status the fence already
has per `diff_boundary_lines`'s own comment ("The markdown fence
stays... It is decoration now, not structure: nothing keys on it.")
— extended here to the *entire* body copy, not only the fence. Nothing
may key on the body's diff text for fidelity purposes; the sidecar and
its digest are the only artifact 0026 (or anything else) may trust.

### 2. The sidecar's durability: matching what `write_record` actually does, not what it might be assumed to do

Verified: `write_record` (`agent/castle:1262`) writes the record with
a single, non-atomic `path.write_text(...)` call. There is no
temp-file-then-rename, no `fsync`, no durability idiom of any kind
beyond whatever guarantee a single `write_text` call gets from the
OS and filesystem. **This means the owner's design item 2 — "write the
sidecar with the same care the journal gets... match whatever
durability idiom `write_record` already uses" — resolves to "no
special care," and this brief takes the design's own stated fallback:
"if it does less than this, mirror what it does and note it."**

The sidecar write is therefore a single, plain
`sidecar_path.write_bytes(diff_bytes)`, with a comment at the call site
saying explicitly that this matches `write_record`'s own lack of an
atomic-write idiom rather than inventing one for the sidecar alone.
Building temp-name-plus-fsync-plus-rename machinery for only the
sidecar, while the record it is stamped into stays a plain
`write_text`, would manufacture a durability guarantee that is false
for one half of the pair it is supposed to protect — a worse
inconsistency than having neither. If atomic writes are wanted for the
journal, that is a `write_record`-level task, filed separately (this
brief does not file it; see Non-goals), and it would then upgrade the
sidecar write to match, not the other way around.

### 3. `parse_record` / `write_record` gain explicit `encoding="utf-8"`

```python
# parse_record, ~:489
text = path.read_text(encoding="utf-8")
```
```python
# write_record, ~:1262
path.write_text(render_record(fields, body), encoding="utf-8")
```

This is a global change to record I/O, closing transforms 2 and 3 of
the four above. **State plainly in `agent/README.md`'s "The record
format" section that records are UTF-8 by definition from this task
onward** — not a new constraint invented for this task alone, but the
existing implicit assumption (every fixture, every example, every
piece of hand-written prose in this repo is already UTF-8) made
explicit and enforced by the one call site each direction passes
through.

This does **not** fix transform 1 (`errors="replace"` at `:4229`).
That decode happens in `run_worker_turn`, before any record exists, and
is upstream of `parse_record`/`write_record` entirely — no change to
either function can reach it. It is item 1 above, not this item, that
closes it, precisely because it works around the record format instead
of trying to make the record format itself binary-safe.

### 4. `splitlines()` body round-trip: untouched, deliberately

Do **not** change the `splitlines()` split at `:493` or the
`"\n".join(...)` reassembly at `:513`. Now that the body copy is
explicitly decorative (item 1), its normalisation no longer matters for
fidelity — the sidecar is what 0026 or any future applier reads.
Changing the record format's line semantics is a bigger decision
(it touches every record type, not only results with embedded diffs)
and is out of scope here; see Non-goals.

### 5. `cmd_validate` learns `patch-sha256`

New module-level constant, beside `DIFF_BOUNDARY_FIELD` (`:344`),
following that constant's own comment style:

```python
# The field name a proposal's sidecar digest is stamped under
# (docs/tasks/0033-byte-exact-proposal.md). Distinct from
# PROPOSAL_SHA256_FIELD by what each proves: proposal-sha256 is
# record-tamper evidence (has this record changed since the proposal
# was filed?); patch-sha256 is byte-fidelity evidence (are these the
# exact bytes the tenant produced, undisturbed by anything this
# format's own transforms do to a body?). A record can carry one,
# the other, both, or neither.
PATCH_SHA256_FIELD = "patch-sha256"
```

Added to `FIELD_ORDER` beside `"diff-boundary"` (`:411`), for the same
presentation-only reason every other addition there gives: it is
machine-readable structure about the body, not prose.

In `cmd_validate`, alongside the existing `diff-boundary` block
(`:5889–5905`): result-only, well-formed-if-present, same 64-lowercase-hex
shape check `proposal-sha256` already uses (`:5941–5948`). Then, only
when the field is both present and well-formed, a check neither
`diff-boundary` nor `proposal-sha256` needs, because neither of them
names a second file:

```python
elif patch_raw is not None:
    sidecar = path.parent / f"{rec.id}.patch"
    if not sidecar.exists():
        errors.append(
            f"{path.name}: '{PATCH_SHA256_FIELD}' is present but no sidecar "
            f"file exists at {sidecar.name} beside it."
        )
    else:
        actual = hashlib.sha256(sidecar.read_bytes()).hexdigest()
        if actual != patch_raw:
            errors.append(
                f"{path.name}: '{PATCH_SHA256_FIELD}' ({patch_raw!r}) does not "
                f"match the sidecar {sidecar.name}'s actual digest ({actual!r})."
            )
```

Both branches name both paths (the record's `path.name` and the
sidecar's `sidecar.name`) in the error text, per the design. When the
field is **absent**, no sidecar is expected at all — absent means
"this result embeds no diff," the identical reading `diff-boundary`
already gives absence, and `cmd_validate` must not scan the journal
directory for stray `.patch` files with no record naming them (that
is a different, weaker check this brief does not add — an orphaned
sidecar from a partially-written turn is not itself a validation
failure; only a *stamped-but-missing-or-wrong* sidecar is).

### 6. `proposal-sha256` is untouched

Its field, its stamping in `_file_proposal_question`, its
re-derivation in `file_answer` and in `castle-modal`'s review
renderer — none of it changes. Restated in one sentence each, because
the re-baselining pass that led to this task found reviewers
conflating the two fields:

- **`proposal-sha256`** is record-tamper evidence: has this exact
  record file changed since the proposal was filed?
- **`patch-sha256`** is byte-fidelity evidence: are these the exact
  bytes the tenant produced, unmangled by anything this record
  format's own transforms do to a body?

The two live on different record types, never the same file:
`patch-sha256` on the result, `proposal-sha256` on the question filed
for it. `patch-sha256` rides `diff-boundary`'s own gate — any turn
that embedded a diff, regardless of outcome — so a completed, targeted
turn producing both (the result with `patch-sha256`, the question with
`proposal-sha256`) is the normal case, not the rule: a turn that
embedded a diff but did not complete cleanly and land a resolvable
target gets a result and its sidecar and nothing else, because
`stamped_target` (`agent/castle:4425`) requires `diff_text and
finished_cleanly`, and `_file_proposal_question` (`agent/castle:4564`)
only ever fires on `stamped_target`. That sidecar is therefore
unreachable through the approval channel by construction — no
question, no approval, nothing for 0026's applier to spend — which is
the contract 0026 relies on. See `agent/README.md`'s "The byte-exact
sidecar" section for the fuller statement of this invariant.

### 7. Readers: unchanged

`castle-modal --mode review` continues rendering from `result.body` via
`_split_proposal_body` (`agent/castle-modal:773`) exactly as it does
today — display is unchanged, because the body copy, while now
explicitly decorative for fidelity purposes, is still the correct and
only thing a human reads on that surface. `castle digest` is unchanged
for the same reason. **0026 is named as the sidecar's consumer**: the
future applier reads `<result-id>.patch` beside the record, verifies
`patch-sha256` before touching anything, and applies those bytes —
never the body's copy.

### 8. State layout: no change needed

Verified: `_state_layout_finding` (`agent/castle:696`) operates over
`state_dir()`, walking its ancestry for the flake-in-store hazard
0030 closes. The sidecar lives at `journal_dir() / f"{id}.patch"` —
inside the journal directory, which is already inside `state_dir()` —
so 0030's layout rules cover it automatically, with no separate check
and no separate documentation. Confirmed by reading rather than
assumed: nothing in `_state_layout_finding` enumerates file
extensions or globs `*.md`; it reasons about directories only.

### 9. Why the sidecar cannot break any existing reader

*(Added at owner review.)* Every journal fold in the system loads
records through `load_all`, which globs `*.md` and nothing else
(`agent/castle:1129`). A `.patch` file in the journal directory is
therefore **invisible to every existing reader by construction** — no
fold, no status surface, no digest, no validator pass over records
will ever feed one to `parse_record`. This is the fact that makes
"put the sidecar beside the record" safe rather than merely tidy, and
it is a constraint on the future: any change that widens `load_all`'s
glob, or adds a second directory scan that does not filter on `.md`,
must account for sidecars existing. The implementer must verify this
claim once more at implementation time (one grep) rather than
inheriting it, and the verification plan's "all existing harnesses
stay green" is the executable form of the same claim.

## Considered and rejected

- **Fixing the four transforms in place, with no sidecar.** Rejected:
  `errors="replace"` (transform 1) happens in `run_worker_turn`,
  before any record exists — no change to `parse_record` or
  `write_record` can reach code that runs earlier than either of them.
  A lossless read-back requires a copy taken *before* that decode, and
  that copy is the sidecar.
- **Fixing only the `splitlines()` round trip (closing 3 of 4
  transforms) and calling that sufficient**, the backlog entry's own
  third open question. Rejected: it improves fidelity without
  guaranteeing it, since transform 1 still stands. 0026, the sidecar's
  first real consumer, needs a guarantee it can check mechanically
  (the digest), not an improvement it would have to trust.
- **The `.patch` sidecar living outside the journal directory** — the
  backlog entry's first open question, and the owner's design answers
  it, but the alternative is worth naming as considered. Rejected:
  the journal directory is already the one place 0030's layout rules
  audit; a second location would need its own layout-hazard reasoning
  duplicated for no benefit, and "beside the record it belongs to" is
  also the simplest possible naming scheme (`<result-id>.patch`
  resolves with no lookup table).
- **Making records binary-safe** (no `splitlines()`-based body
  parsing, arbitrary bytes anywhere in a record) so the record itself
  could be the byte-exact copy. Rejected, and the backlog entry
  already gives the reason: the record format is line-oriented by
  design, which is what makes `grep '^type: decision' journal/*.md` a
  completely valid way to query the journal with no tool at all
  (`agent/README.md`'s own "The record format" section states this
  cost explicitly). Trading that away to make records binary-safe pays
  for byte fidelity with the project's stated premise about what a
  journal is for.
- **Adding a full atomic-write idiom (temp file, `fsync`, rename) to
  the sidecar write**, since this task is already touching the code
  path next to it. Rejected here — see design item 2 — because
  `write_record` itself has no such idiom today, and giving the
  sidecar a stronger durability guarantee than the record it is
  stamped into would be internally inconsistent: a crash could still
  corrupt or lose the record with the digest in it, so a perfectly
  durable sidecar buys nothing the record can't already throw away.
  If wanted, this is a `write_record`-level task on its own, upgrading
  both together; not filed by this brief (Non-goals).
- **Writing the sidecar before the record**, with the record's id
  pre-generated by `run_worker_turn` and passed into `write_record`
  rather than generated inside it (`make_id`, `:1150`). This would let
  the sidecar exist, durable, before the record that names it is
  written — closing the crash window the chosen ordering leaves open
  (see "Smaller decisions" below) in the safer direction. Rejected for
  this task: it requires widening `write_record`'s signature with an
  optional pre-assigned id, a change with a larger blast radius (every
  caller, every record type) for a window this task's own
  `cmd_validate` addition already turns into a clean, legible
  validation failure rather than silent corruption. Worth revisiting
  if a future task needs pre-assigned ids for an unrelated reason.

## Hard constraints, restated

- **Principle 01 test.** Entirely public mechanism: a sidecar file, a
  digest, a validation rule, and a documentation update. No new
  private-layer configuration surface, no new option.
- **Never write personal data into this repo.** The new test fixture's
  scripted tenant writes synthetic diff content only — invented file
  paths and invented text carrying the specific byte sequences under
  test (CRLF, form feed, U+2028, an invalid UTF-8 byte, no trailing
  newline), never anything resembling a real configuration change.
  Same fixture-identity convention `test/agent-loop/config-target.sh`
  already established (`fixture@example.invalid`).
- **This branch stacks on `sprint/0025-approval` (PR #58); #58 merges
  first.** `_write_worker_result`, `_file_proposal_question`,
  `DIFF_BOUNDARY_FIELD` and `PROPOSAL_SHA256_FIELD` are 0025's; this
  task extends them rather than re-deriving them. Do not scope a
  review or a diff against `main` until #58 has landed.
- **`agent/castle` stays stdlib-only**, no third-party dependency,
  matching every prior task in this directory.
- **Records are never rewritten.** The sidecar, once written, is
  likewise never rewritten — an append-only journal gets an
  append-only sidecar directory to match. Nothing in this task adds a
  code path that opens an existing `.patch` file for writing.

## File-by-file change list

- **`agent/castle`**:
  - `PATCH_SHA256_FIELD` constant, beside `DIFF_BOUNDARY_FIELD` (~:344).
  - `FIELD_ORDER`: `"patch-sha256"` added beside `"diff-boundary"`
    (~:411).
  - `run_worker_turn` (~:4229 onward): capture `diff_bytes` alongside
    `diff_text`; compute `patch_sha256`; after `_write_worker_result`
    returns, write the sidecar.
  - `_write_worker_result` (~:3333): new `patch_sha256: str | None = None`
    keyword parameter, stamped into `extra` the same way
    `diff_boundary` already is.
  - `parse_record` (~:489) and `write_record` (~:1262): explicit
    `encoding="utf-8"`.
  - `cmd_validate` (~:5889 onward): new `patch-sha256` block per design
    item 5.
- **`agent/README.md`**:
  - "The record format" (~:624): one sentence stating records are
    UTF-8 by definition.
  - "Where a result's diff starts and stops: `diff-boundary`" (~:1155):
    extend the existing "decoration, not structure" language to state
    plainly that the *entire body copy*, not only the fence, is
    decorative as of this task, and that the sidecar plus
    `patch-sha256` is the only artifact fidelity may be checked
    against.
  - New subsection immediately after "`proposal-sha256` and
    `decision`" (~:1200), e.g. "The byte-exact sidecar:
    `patch-sha256`", stating: what it is, where it lives
    (`<result-id>.patch`, beside the record), how it is validated, and
    the one-sentence distinction from `proposal-sha256` (design item 6).
- **`test/agent-loop/config-target.sh`** — extended, see Verification
  plan for the case list and the choice-of-fixture justification.
- **`test/agent-loop/scripted-worker-byte-fidelity.sh`** (new) — a
  scripted tenant that writes exact, adversarial byte sequences to
  `$CASTLE_DIFF_FILE`, modeled on
  `scripted-worker-config-target.sh`'s environment contract.
- **`docs/tasks/0033-byte-exact-proposal.md`** — this brief, committed
  on this branch per the tasks convention.

Nothing in `agent/castle-modal` changes (design item 7, verified: its
review renderer's `DIFF_BOUNDARY_FIELD` and body-splitting logic are
untouched). Nothing in `modules/agent/default.nix` changes — this task
adds no option. Confirm both while reading and say so in the PR if
either has changed since this brief was written.

## Non-goals

- **Applying anything.** That is `docs/tasks/0026`, named throughout
  this brief as the sidecar's intended first consumer. This task makes
  the bytes trustworthy; it does not read or act on them.
- **Changing the body copy's line semantics.** The `splitlines()`
  round trip at `:493`/`:513` is untouched (design item 4). A
  binary-safe or `\n`-only record body is a bigger decision, touching
  every record type, and is explicitly out of scope.
- **Retroactive sidecars for existing records.** The journal is
  append-only; a result written before this task simply has no
  `patch-sha256` field and no sidecar, the same "absent means it
  predates the field" reading `diff-boundary` already established.
  Nothing in `cmd_validate` requires the field on old records.
- **Any signing or authorship mechanism.** `patch-sha256` (like
  `proposal-sha256`) is fidelity/tamper evidence, not an attestation of
  who produced the bytes.
- **An atomic-write idiom for `write_record` or the sidecar.** Design
  item 2 and "Considered and rejected" cover why: `write_record` has
  none today, and giving only the sidecar one would be inconsistent.
  If durability is wanted for the journal as a whole, that is a
  separate, future task.
- **Pre-assigned record ids in `write_record`.** Considered as a way
  to write the sidecar before the record; rejected for this task's
  scope (see "Considered and rejected").

## Smaller decisions this brief had to make

- **Sidecar-write ordering: record first, sidecar second, not the
  reverse.** The owner's design left this open ("write those raw
  bytes... to a sidecar file... and stamp the result record"; no
  explicit ordering given). Writing the record first is simpler — it
  needs no change to `write_record`'s signature — and the crash window
  it leaves (a `patch-sha256`-bearing record whose sidecar was never
  written, if the process dies between the two writes) is exactly the
  case `cmd_validate`'s new "sidecar file exists" check already turns
  into a legible, named validation failure rather than silent data
  loss. The rejected alternative (sidecar first, using a pre-generated
  id) closes the window in the safer direction but costs a
  `write_record` signature change with a larger blast radius; see
  "Considered and rejected."
- **The sidecar write is a single plain `write_bytes`, matching
  `write_record`'s own lack of atomicity**, rather than inventing new
  durability machinery for only the new file. This resolves the
  owner's design item 2 by its own stated fallback clause once the
  code was actually read (`write_record` does no temp-file/fsync/
  rename at all) — not a deviation from the design, but the design's
  own conditional firing.
- **Extending `test/agent-loop/config-target.sh` rather than
  `approval.sh`.** Both were offered by the design. `config-target.sh`
  already builds two real git checkouts specifically so a produced
  diff can be checked against a real repository, which is exactly what
  the `git apply --check` assertion (Verification plan) needs; the
  byte-fidelity property being tested belongs to `run_worker_turn`
  itself and is fully exercised by a completed turn, with no decision
  or approval step required. `approval.sh` already reuses
  `config-target.sh`'s fixture rather than building its own
  ("Same shape and same conventions as config-target.sh, whose fixture
  this reuses"), so extending the base fixture is also the one that
  keeps both harnesses in sync rather than letting a byte-fidelity
  fixture drift between two files.

## Verification plan

**Automatable, and built as part of this task**, in
`test/agent-loop/config-target.sh`, using a new
`scripted-worker-byte-fidelity.sh` tenant modeled on
`scripted-worker-config-target.sh`'s environment contract:

- **Byte-fidelity harness.** The scripted tenant writes a diff to
  `$CASTLE_DIFF_FILE` covering, across one or several cases as
  convenient: CRLF line endings, a form feed (`\f`), a U+2028 LINE
  SEPARATOR character, a byte sequence that is not valid UTF-8, and a
  patch with no trailing newline. After the turn completes:
  - `cmp` the sidecar file (`<journal>/<result-id>.patch`) against the
    exact bytes the scripted tenant wrote. They must be identical.
  - Separately assert the **record body is not** byte-identical to
    what the tenant wrote — the contrast is the point of this task and
    must be demonstrated, not assumed (e.g. read the record, extract
    the fenced diff section, and confirm it differs from the raw
    bytes for at least the CRLF and form-feed cases, where
    `splitlines()`'s divergence from `\n`-only splitting is
    observable).
  - For the CRLF case specifically: run `git apply --check` with the
    **sidecar's** bytes against a fresh clone of the fixture's private
    checkout, and assert it succeeds; then run the same check against
    the record body's extracted copy and assert it **fails** (or
    applies to different content) — proving the backlog entry's core
    claim mechanically rather than by inspection.
- **`castle validate` red/green matrix**:
  - Red on a tampered sidecar (flip a byte in `<id>.patch` after a
    successful turn, without touching the record).
  - Red on a deleted sidecar (remove `<id>.patch`, leave `patch-sha256`
    stamped in the record).
  - Red on a malformed `patch-sha256` (hand-edit the record to a
    non-hex or wrong-length value).
  - Green on a result with no `diff-boundary`/`patch-sha256` at all
    (a turn that proposed nothing) — absent means absent, no sidecar
    expected.
- Run the full existing `test/agent-loop/*.sh` suite afterward —
  nothing in this task should change any existing harness's behavior,
  since the body copy's rendering and the existing `diff-boundary`/
  `proposal-sha256` checks are untouched by design.
- `nix flake check` — this task adds no Nix option or module; run it
  anyway per `CLAUDE.md`'s standing rule.
- The desktop-loop VM harness (`test/agent-loop/`'s existing
  full-stack coverage, whichever entry point that repo currently uses)
  — a regression check, since this task adds no new host-visible
  surface, run per `CLAUDE.md`'s bias toward building what's cheap.

**Not automated:** nothing in this task's verification plan requires
human hands beyond the ordinary `/code-review` and
`tools/codex-review.sh` pass `CLAUDE.md` already requires before a PR.
There is no equivalent here to 0030's "migrate a real resident's real
directory" step — this task changes no documented resident-facing
procedure.

## Implementation prompt

For the session that implements this brief: read `CLAUDE.md` in full,
this brief in full, `agent/README.md`'s "The record format",
"`diff-boundary`" and "`proposal-sha256` and `decision`" sections in
full (not only the parts being edited — the surrounding tone and
cross-references need matching), and every file this brief names as
being modified, before writing anything. Work on branch
`task/0033-byte-exact-proposal` (already checked out in this worktree
at `ce8272b`; do not create a new branch or touch any other worktree).
This branch stacks on `sprint/0025-approval` (PR #58), not yet merged
— scope every diff and review against `origin/sprint/0025-approval`
(`git fetch` first), and open the PR against that branch, re-pointing
to `main` only if #58 merges first (say so in the PR description if
that happens). Keep `agent/castle` stdlib-only, no third-party
dependency, readable top to bottom, matching every prior task in this
directory.

Implementation order:

1. `agent/castle` — `PATCH_SHA256_FIELD` constant and its `FIELD_ORDER`
   entry first, so everything after references a name that exists.
2. `parse_record` / `write_record` — add `encoding="utf-8"` to both.
   Run the existing `test/agent-loop/*.sh` suite immediately after this
   one change, before touching anything else, to confirm it is a pure
   addition with no behavior change on this platform's default
   encoding.
3. `run_worker_turn` and `_write_worker_result` — the `diff_bytes`
   capture, the `patch_sha256` computation and parameter threading, and
   the sidecar write after `result_id` is known. Follow design item 1's
   ordering and item 2's "plain `write_bytes`, no invented atomicity"
   choice exactly; do not add `fsync`/temp-file/rename machinery here
   even if it looks like the natural next step — that is explicitly
   out of scope (Non-goals) and was rejected for a stated reason
   (Considered and rejected).
4. `cmd_validate` — the new `patch-sha256` block, modeled tightly on
   the existing `diff-boundary` block immediately above it.
5. `agent/README.md` — the three edits per the file-by-file list.
   Write the new `patch-sha256` subsection to read naturally beside
   the `proposal-sha256` section it follows; a reader going section by
   section should come away able to state the one-sentence distinction
   between the two fields without re-reading either.
6. `test/agent-loop/scripted-worker-byte-fidelity.sh` — write against
   the real `castle` binary and real `git`, iterating the fixture
   until each byte-fidelity case passes for the right reason (this is
   easier to get right iteratively than written blind against the
   spec, per `docs/tasks/0023-resume-cold.md`'s own observation about
   fixture-writing).
7. `test/agent-loop/config-target.sh` — wire the new scripted tenant
   in as additional scenarios, following the file's existing
   structure and `assert_checkouts_untouched`-style discipline.

Run `test/agent-loop/config-target.sh` directly, then the full
existing `test/agent-loop/*.sh` suite, then `nix flake check`, then the
desktop-loop VM harness, before opening a PR. Per `CLAUDE.md`'s
multi-agent conventions: run `/code-review` scoped against
`origin/sprint/0025-approval` and address its findings, then run
`tools/codex-review.sh` for a second, cross-model opinion, posting its
findings verbatim with any disposition in a separate comment
underneath. If implementation surfaces a genuine deviation from this
brief, say so prominently and amend this brief in the same PR, per
`CLAUDE.md`'s rule that a brief the work overtakes gets corrected in
place, not left stale.
