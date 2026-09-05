# Task 0053 — a proposed diff is generated, never hand-composed

**Before starting:** read `CLAUDE.md` in full. Then, closely:
`agent/castle-worker-claude` around the prompt heredoc — step 2 and
rule 4's git paragraph are the subject of this task — and its
end-of-file permission grant; `agent/castle`'s `work_scratch_dir()`,
`prune_work_scratch()`, `run_worker_turn`'s scratch allocation and its
`finally`, and the block that reads `$CASTLE_DIFF_FILE` back and hashes
it; `docs/tasks/done/0039-worker-writable-deliverables.md` for why the
deliverable paths are shaped as they are, and
`docs/tasks/done/0047-tenant-permission-allowlist.md` for what the
tenant is actually permitted to run.

## The finding

On 2026-09-05 the first errand ever to produce a real proposal produced
one that could not be applied. The approval it earned was spent on a
refusal.

The diff's *content* was correct — the right one-line change, with a
comment explaining it. Its *framing* was wrong in two independent ways:

1. The hunk header declared seven old lines and thirteen new ones while
   the hunk carried seven old lines and fourteen new ones. The new-line
   count was off by one.
2. The blank context line inside the hunk was written as an empty line
   rather than as a single space, which unified diff requires.

Measured, not inferred: restoring the space alone still fails to parse,
correcting the count alone still fails to parse, and with both
corrected `git apply --check` returns 0. Git's own error was
`corrupt patch at <file>:19`.

## Why this is a design finding rather than a bad turn

The contract asked for exactly this. Step 2 of the prompt said to
produce a unified diff and write it to `$CASTLE_DIFF_FILE`, and rule 4's
git paragraph said, in as many words, that the tenant COMPOSES the
unified diff — with the reasoning that `git diff` prints nothing on a
clean tree, so using git to form the patch would mean editing a tracked
file in the resident's real checkout, which the allowed-command list
forbids outright.

That reasoning is sound and its conclusion is not. It asks a language
model to hand-compute line arithmetic and preserve significant
whitespace in a format where both are load-bearing and neither is
visible in the thing it is looking at. The two errors observed are not
unusual mistakes; they are the two characteristic ones for this task. A
first proposal that fails to parse is the expected outcome of the old
design, not bad luck, and the same design keeps producing them at
whatever rate the model happens to miscount.

**Not fixed by validation.** Adding a `git apply --check` gate and
keeping hand composition is separate work; it would turn this defect
from an unappliable patch into a refused turn — better, and still not a
proposal the resident can use.

## The shape

**The tenant edits a file; the harness generates the diff.** No model
ever writes a hunk header again.

The constraint that produced the old shape stays intact and is
strengthened rather than relaxed: nothing may write inside the
resident's configured checkouts. What changes is that the tenant is now
given somewhere it *may* write that stands in for the checkout, and
that place is a copy.

### 1. `castle work` hands over a writable copy of each checkout

`run_worker_turn` allocates one more scratch path beside the three it
already allocates — a per-turn *directory* under `work_scratch_dir()`,
holding two mirrors:

    <turn>/edit/private/     handed over as $CASTLE_EDIT_DIR
    <turn>/edit/mechanism/
    <turn>/base/private/     the pristine copy, never named to the tenant
    <turn>/base/mechanism/

Everything `work_scratch_dir()`'s docstring argues for the three files
carries to it unchanged: home-anchored on every layout
`docs/private-layer.md` documents, beside the journal and not in it,
deleted rather than kept. One subdirectory per configured checkout,
named with exactly the words `$CASTLE_TARGET_FILE` accepts, so the
role a change targets is a fact about *where the tenant wrote* rather
than a claim it makes afterwards.

**The mirror carries file contents, not just directories.** Each
mirror is populated from `git ls-files -z` in the checkout: tracked
regular files only. That excludes `.git`, every untracked build
artefact, and — the case that matters — a state directory sitting
inside a configured root, which `0047` documents as a live deployment
and which `git ls-files` never lists (untracked, or a gitlink if it is
a submodule). Symlinks are skipped rather than copied: a symlink inside
the tenant's one writable directory is a way out of it, and the whole
sandbox story here is about where writes land.

**Contents, because the alternative is asking a model to retype a
file.** A directory skeleton with no files in it would be cheaper and
would leak nothing, but a tenant working in it can only produce its
edited copy by writing out every byte of the original from what it read
— which is the same defect this task exists to remove, moved from the
patch's framing to the file's body, and worse in one way: a
mis-transcribed line still applies. With the original bytes in the copy
the tenant edits in place, and every byte it did not touch is the byte
that was there.

The copy is bounded (`EDIT_MIRROR_MAX_FILES`, `EDIT_MIRROR_MAX_BYTES`).
A checkout past either bound gets a truncated mirror and a line on
stderr, which lands in the result record; the effect is that some file
is missing from the copy, which the contract in §5 already tells the
tenant what to do about.

### 2. The tenant edits the copy, and only the copy

To change `hosts/example/default.nix` in the private layer, the tenant
opens `$CASTLE_EDIT_DIR/private/hosts/example/default.nix` — the same
relative path, already carrying the same bytes — and edits it. Reading
under a configured root stays allowed; writing under `$CASTLE_EDIT_DIR`
is granted by the wrapper's permission block, and writing under a
configured root stays forbidden by the rule that already forbids it.

Multi-file changes need no new mechanism and are **supported**: two
edited copies, two files in the generated patch. That is not a new
capability — `docs/tasks/done/0026-apply-validate.md`'s harness already
applies a two-file patch — and refusing it here would narrow the
contract to fix a defect that has nothing to do with it. What stays
refused is a change spanning *both* mirrors: rule 2's "ONE DIFF, ONE
TARGET" is now enforced by the harness rather than asked of the model.

A file absent from the mirror is a file this turn did not change. It is
never read as a deletion — see §5.

### 3. `castle work` generates the patch

After the tenant exits, every regular file under `edit/<role>/` whose
bytes differ from `base/<role>/<same relative path>`, or which has no
counterpart under `base/`, is a changed path. Those are staged into two
scratch directories literally named `a` and `b` — the base bytes into
`a`, the edited bytes into `b` — and one

    git diff --no-index --no-prefix -- a b

run with `a` and `b` as relative paths produces the patch. `--no-prefix`
against directories named `a` and `b` is what makes the headers read
`a/<rel>` and `b/<rel>`: the conventional form `git apply` strips with
its default `-p1`, with no post-processing of git's output anywhere.
Measured against a real checkout: `git apply --check` accepts it, for a
modification and for a creation alike.

**Against the base copy, not against the checkout.** They are the same
bytes at the moment the turn starts and can differ by the time it ends,
because a resident may edit their own repository while an errand runs.
A patch computed against the live checkout would then quietly carry
their edit away as part of the proposal, and would apply cleanly while
doing it; one computed against the base carries only what the tenant
changed, and fails to apply loudly if the resident's edit overlaps it.
That is `0026`'s failure path doing its job rather than a silent revert.

`b`'s mode is set from `a`'s, so a copy the tenant's editor rewrote
`0644` does not produce a spurious `old mode`/`new mode` pair against a
`0755` original. A new file is staged `0644`.

**Private git configuration is neutralized, and one line of it is
load-bearing.** The generation runs with `GIT_*` stripped
(`_git_stripped_env`), with `GIT_CONFIG_GLOBAL` and `GIT_CONFIG_SYSTEM`
pointed at `/dev/null`, with `GIT_CEILING_DIRECTORIES` set so no
enclosing repository's config or attributes is discovered — the state
directory is itself a git repository in the recommended layout — with
`--no-ext-diff --no-textconv`, with `GIT_ISOLATION_ARGS`, and with
`diff.suppressBlankEmpty`, `diff.algorithm`, `diff.context`,
`diff.mnemonicPrefix`, `diff.noprefix` and `core.autocrlf` pinned on the
command line. `diff.suppressBlankEmpty = true` in a resident's
`~/.gitconfig` makes git emit a blank context line as an empty line —
**defect 2 of the finding, reproduced by the mechanism itself, out of
private configuration.** Measured, not inferred. Pinning it is
Principle 01 in one flag: the mechanism must not inherit its output
format from the private layer.

Binary content is refused by name rather than diffed: if either side of
a changed path holds a NUL byte, no patch is produced and the result
body says which path and why. `git diff` would emit
`Binary files ... differ`, which is not appliable, and an unappliable
patch is the defect this task exists to remove.

### 4. What happens to `$CASTLE_DIFF_FILE`, and to `$CASTLE_TARGET_FILE`

**`$CASTLE_DIFF_FILE` stays, unchanged in name, direction and
semantics, and is demoted to a compatibility channel.** `castle work`
still allocates it, still hands it over, still reads it back the same
way, and still does not write it. What changes is that the reference
tenant is told, in one sentence, that it is not theirs to write.

Three reasons, and the second is the one that decided it:

- Its name is in `0039`'s refusal text, in the contract, and in journal
  records that are append-only. A record that says "the worker tenant
  did not write one to `$CASTLE_DIFF_FILE`" must keep meaning what it
  meant.
- `castle.agent.worker.command` is configurable. Every scripted tenant
  in `test/agent-loop/` writes that file, and so may a tenant somebody
  else wrote — including one that generates its patch honestly by some
  other route, from its own clone or its own worktree. Retiring the
  variable would break all of them, and break them *silently*: they
  would write a file nothing reads and produce a `completed` result
  with no proposal, which is the 0039 failure over again from a fourth
  cause.
- Nothing about hand composition is enforceable at this boundary
  anyway. What removes it is the reference prompt no longer asking for
  it.

**When both are non-empty, the generated patch wins and the discard is
stated.** A tenant that both edited the mirror and wrote a diff has
contradicted itself; the generated half is the mechanically derived
one, so it is what gets recorded, and the result body says in a
sentence that a hand-written `$CASTLE_DIFF_FILE` was discarded. Same
posture as the existing target-without-diff branch: nothing is silently
dropped.

**`$CASTLE_TARGET_FILE` stays too, and stops being authoritative for a
generated patch.** The tenant is still asked for the word, because the
word is the boundary's contract and a tenant that hand-writes a diff
has no other way to say what it is against. But when the patch was
generated, which mirror the tenant edited *is* the answer, and a
derived fact beats a claim: the role is taken from the mirror, and a
tenant whose word disagrees gets the derived role recorded and a
sentence in the body naming the disagreement. This is the one place the
contract's own worry — "the two checkouts can legitimately hold the same
relative paths, and nothing downstream can tell them apart on your
behalf" — stops being true, and it is worth having. A wrong stamp is how
a resident's own file ends up committed to a public repository.

### 5. What the tenant is told when the change will not fit

`0043`'s quoted-refusal rule means a refusal is only recognized if the
tenant can quote the sentence it rests on. Three shapes cannot be
expressed as "a file in the mirror differs from its original", so the
prompt states each one as a sentence there is to quote, and names the
lane to use instead:

- **A deletion.** Absence from the mirror means "unchanged", so it
  cannot also mean "delete". Deliberate: a mirror that fell short —
  a bound hit, a copy that failed — would otherwise generate a patch
  deleting a resident's files, which is the worst thing this generator
  could emit. Not proposable from this seat.
- **A file the mirror does not carry**, because the checkout does not
  have it (a new directory, an untracked file) or because a bound in §1
  cut it. Not proposable from this seat.
- **A rename**, which is a deletion and an addition, and fails on the
  first half.

In each case: say so on stdout, quote the sentence, and — because each
is a gap in this framework rather than a fact about the resident's
configuration — file a finding (rule 8). The lane already exists; this
only points at it.

### 6. The sweep prunes directories as well as files

`prune_work_scratch()` calls `entry.unlink()`, which raises
`IsADirectoryError` on a directory — caught by its own `except OSError`
and skipped, forever. A leftover mirror from a `SIGKILL`ed turn would
therefore be durable, which is exactly the accumulation `0039 §5` added
the prune to prevent. It now removes directories with `shutil.rmtree`.

## Non-goals

- No `git apply --check` gate on the generated patch. It is worth doing
  and it is separate work; adding it here would mean this task's
  verification could pass on a gate rather than on the generation.
- No new Nix option and no change to `stateDir`'s type.
- No relaxation of any rule in the wrapper's forbidden list, and no new
  command in its allowed list. The one thing added to the tenant's
  permissions is write access to a directory this harness created for
  it under the state directory. In particular the tenant is *not*
  granted `cp`, `mkdir` or `rm`: a bash write is not covered by the
  `Edit(...)` deny that keeps it out of the resident's checkout
  (`docs/backlog/bash-redirection-defeats-root-write-deny.md`), so
  every one of those would widen the hole that entry is about in order
  to save a copy the harness can make itself.
- No change to `exec claude` at the end of the wrapper. The generation
  happens in `castle work` after the tenant exits, so all four
  properties that comment defends are untouched.

## Rejected alternatives

**A directory skeleton instead of a copy** — every directory the
checkout has, no files — with the tenant writing the file it wants to
change into place itself. Cheaper, and it puts nothing of the
resident's in the scratch directory. Rejected because the tenant's only
way to produce that file is to emit every byte of it from what it read,
and a model retyping a two-hundred-line file is the same hand-transcription
this task is removing, with a quieter failure: a mis-copied line
becomes a hunk that applies. The copy's own exposure is small and
argued about above: transient, under the private state directory that
already holds the journal, and deleted in the same `finally` as the
other three scratch paths.

**A full writable copy of the checkout including untracked files.**
Rejected for the recursion `git ls-files` avoids for free: with
`stateDir` inside the private root, the copy would contain the
directory it is being written into.

**A manifest the tenant writes, pairing scratch files to checkout
paths.** Rejected because it is one more thing a model can get wrong,
and the failure mode is a patch against the wrong path — worse than the
one being fixed, since it may still apply.

**Post-processing git's `--- a/` and `+++ b/` header lines.** Works,
and was the obvious first design. Rejected once `--no-prefix` against
directories named `a` and `b` was measured to produce exactly the
wanted headers: the whole point of this task is that nothing edits a
patch's framing by hand, and that includes this harness.

**Generating the diff in `agent/castle-worker-claude` instead.** It is
the seat's own harness and Proposal 03 leaves a seat's insides free, so
this would have changed no boundary at all. Rejected on two counts: it
would have to stop `exec`ing its tenant to get a chance to run
afterwards, giving up the four properties that line's comment defends;
and the git-configuration neutralization above is exactly the kind of
thing `agent/castle` already does correctly in one place
(`_git_stripped_env`, `GIT_ISOLATION_ARGS`) and a bash reimplementation
would have to get right a second time.

## Verification

Automated, and the bar is that a *generated* patch round-trips:

- `test/agent-loop/generated-diff.sh`, a new harness in the CI job list:
  real `castle work` turns against a real fixture checkout, with a
  scripted tenant that edits its mirror copy, asserting the `.patch`
  sidecar in the journal is accepted by `git apply --check` against
  that checkout and that the checkout itself never moved. Scenarios: a
  one-line edit; a two-file edit; a new file in an existing directory;
  a hostile global git configuration (`diff.suppressBlankEmpty = true`)
  that reproduced the finding's second defect; a tenant that writes
  `$CASTLE_DIFF_FILE` as well (generated wins, discard stated); a role
  disagreement between the mirror and the stamped word; a turn that
  edits nothing; and a symlink in the checkout, asserting it is not
  mirrored.
- A regression fixture carrying the finding's two defects together,
  asserting `git apply --check` rejects it, rejects each half-fix, and
  accepts the patch the new mechanism generates for the same edit.
- The existing suites, all of which drive this code path:
  `dispatch-test.sh`, `resume.sh`, `config-target.sh`, `approval.sh`,
  `apply.sh`, `outbox.sh`, `run.sh`, `activation.sh`, `state-layout.sh`,
  `tenant-swap.sh`, `record-order.sh`, `stray-state-dir.sh`.
- One assertion that the *rendered* prompt carries the new rules, since
  a prompt rule nothing checks is a comment.
- `nix flake check`.

Human hands, on the reference host: one live errand whose fix is a real
edit, confirming the proposal applies rather than refuses. That is the
same test the resident already ran by accident. No harness here runs a
sandboxed tenant, so nothing in CI establishes that a headless `claude`
can write under `$CASTLE_EDIT_DIR` — only that the harness grants it
and that the generation is correct.
