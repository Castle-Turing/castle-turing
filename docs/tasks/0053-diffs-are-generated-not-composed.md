# Task 0053 — a proposed diff is generated, never hand-composed

**Before starting:** read `CLAUDE.md` in full. Then, closely:
`agent/castle-worker-claude` around the prompt heredoc — step 2 and
rule 4's git paragraph are the subject of this task — and its
end-of-file permission grant; `agent/castle`'s `work_scratch_dir()`,
`prune_work_scratch()`, `run_worker_turn`'s scratch allocation and its
`finally`, and the block that reads `$CASTLE_DIFF_FILE` back and hashes
it; `docs/tasks/done/0039-worker-writable-deliverables.md` for why the
deliverable paths are shaped as they are, and
`docs/tasks/0047-tenant-permission-allowlist.md` for what the tenant is
actually permitted to run.

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

Git's own error was `corrupt patch at <file>:19`.

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
design, not bad luck.

**Not fixed by validation.** Adding a `git apply --check` gate and
keeping hand composition is `docs/backlog/` work of its own; it would
turn this defect from an unappliable patch into a refused turn — better,
and still not a proposal the resident can use.

## The shape

**The tenant edits a file; the harness generates the diff.** No model
ever writes a hunk header again.

The constraint that produced the old shape stays intact and is
strengthened rather than relaxed: nothing may write inside the
resident's configured checkouts. What changes is that the tenant is now
given somewhere it *may* write that stands in for the checkout.

### 1. `castle work` hands over a writable mirror

`run_worker_turn` allocates a fourth scratch path beside the three it
already allocates — a *directory*, `$CASTLE_EDIT_DIR`, under
`work_scratch_dir()`. Everything `work_scratch_dir()`'s docstring argues
for the three files carries to it unchanged: home-anchored on every
layout `docs/private-layer.md` documents, beside the journal and not in
it, deleted rather than kept.

Inside it, one subdirectory per configured checkout, named with exactly
the words `$CASTLE_TARGET_FILE` accepts:

    $CASTLE_EDIT_DIR/private/     mirrors $CASTLE_PRIVATE_ROOT
    $CASTLE_EDIT_DIR/mechanism/   mirrors $CASTLE_MECHANISM_ROOT

Each mirror is the checkout's **directory skeleton and nothing else** —
every directory that exists in the checkout, no files. `.git` is pruned,
symlinked directories are not followed, and the state directory is
pruned when it sits inside a configured root (which `0047` documents as
a real deployment).

**Directories, not a copy of the tree, and the reason is privacy.**
Copying the checkout would put a second copy of the resident's decision
history in the state directory once per errand. A skeleton is a few
hundred `mkdir`s and carries no content at all.

**The skeleton exists so the tenant never has to create a directory.**
Whether Claude Code's file-writing tool creates missing parents is a
property of a tool this repo does not control and cannot check from CI,
and a contract resting on it would be resting on a recollection. Every
directory the checkout has, the copy has; that is a fact this harness
establishes rather than hopes for.

The mirror is bounded (`EDIT_MIRROR_MAX_DIRS`). A checkout deep enough
to exceed it gets a truncated skeleton and a line on stderr; the effect
is that some directory is missing from the copy, which the contract
below already tells the tenant what to do about.

### 2. The tenant copies the file it wants to change, and edits the copy

To change `hosts/example/default.nix` in the private layer, the tenant
reads `$CASTLE_PRIVATE_ROOT/hosts/example/default.nix`, writes it to
`$CASTLE_EDIT_DIR/private/hosts/example/default.nix`, and edits that.
Reading under a configured root is already allowed; writing under
`$CASTLE_EDIT_DIR` is granted by the wrapper's permission block.

Multi-file changes need no new mechanism: two copies, two files in the
generated patch. A file absent from the mirror is a file this turn did
not change.

### 3. `castle work` generates the patch

After the tenant exits, for each role with a configured root, every
regular file under `$CASTLE_EDIT_DIR/<role>/` whose bytes differ from
`<root>/<same relative path>` — or whose original does not exist — is a
changed path. Those are staged into two scratch directories literally
named `a` and `b`, and one `git diff --no-index --no-prefix -- a b`
produces the patch. `--no-prefix` against directories named `a` and `b`
is what makes the headers read `a/<rel>` and `b/<rel>`: the conventional
form `git apply` strips with its default `-p1`, with no post-processing
of git's output anywhere.

`b`'s mode is set from `a`'s, so a copy the tenant's editor created
`0644` does not produce a spurious `old mode`/`new mode` pair against a
`0755` original. A new file is staged `0644`.

**Private git configuration is neutralized, and one line of it is
load-bearing.** The generation runs with `GIT_*` stripped
(`_git_stripped_env`), with `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM`
pointed at `/dev/null`, with `--no-ext-diff`, and with `diff.algorithm`,
`diff.context`, `core.autocrlf` and `diff.suppressBlankEmpty` pinned on
the command line. `diff.suppressBlankEmpty = true` in a resident's
`~/.gitconfig` makes git emit a blank context line as an empty line —
**defect 2 of the finding, reproduced by the mechanism itself, from
private configuration.** Measured, not inferred. Pinning it is
Principle 01 in one flag: the mechanism must not inherit its output
format from the private layer.

Binary content is refused by name rather than diffed: a path whose old
or new bytes contain a NUL is reported in the result body and no patch
is produced. `git diff` would emit `Binary files ... differ`, which is
not appliable, and a patch that cannot be applied is the defect this
task exists to remove.

### 4. What happens to `$CASTLE_DIFF_FILE`

**It stays, unchanged in name, direction and semantics, and is demoted
to a compatibility channel.** `castle work` still allocates it, still
hands it over, still reads it back the same way, and still does not
write it. What changes is that the reference tenant is told, in one
sentence, that it is not theirs to write.

Three reasons, and the second is the one that decided it:

- Its name is in `0039`'s refusal text, in `modules/agent`'s option
  descriptions, and in journal records that are append-only. A record
  that says "the worker tenant did not write one to `$CASTLE_DIFF_FILE`"
  must keep meaning what it meant.
- `castle.agent.worker.command` is configurable. Every scripted tenant
  in `test/agent-loop/` writes that file, and so may a tenant somebody
  else wrote — including one that generates its patch honestly by some
  other route (its own clone, its own worktree). Retiring the variable
  would break all of them, and break them *silently*: they would write a
  file nothing reads and produce a `completed` result with no proposal,
  which is the 0039 failure over again from a fourth cause.
- Nothing about hand composition is enforceable at this boundary anyway.
  What removes it is the reference prompt no longer asking for it.

**When both are non-empty, the generated patch wins and the discard is
stated.** A tenant that both edited the mirror and wrote a diff has
contradicted itself; the generated half is the mechanically derived one,
so it is what gets recorded, and the result body says in a sentence that
a hand-written `$CASTLE_DIFF_FILE` was discarded. Same posture as the
existing target-without-diff branch: nothing is silently dropped.

### 5. What the tenant is told when the change will not fit

`0043`'s quoted-refusal rule means a refusal is only recognized if the
tenant can quote the sentence it rests on. Three shapes cannot be
expressed as "a file in the mirror differs from its original", so the
prompt states each one as a sentence there is to quote, and names the
lane to use instead:

- **A deletion.** Absence from the mirror means "unchanged", so it
  cannot mean "delete". Not proposable from this seat.
- **A file in a directory the checkout does not have.** The mirror
  carries the directories that exist; a change needing a new one is not
  proposable from this seat.
- **A rename**, which is a deletion and an addition, and fails on the
  first half.

In each case: say so on stdout, quote the sentence, and — because each
is a gap in this framework rather than a fact about the resident's
configuration — file a finding (rule 8). The lane already exists; this
only points at it.

### 6. The sweep prunes directories as well as files

`prune_work_scratch()` calls `entry.unlink()`, which raises
`IsADirectoryError` on a directory — caught by its own `except OSError`
and skipped, forever. A leftover edit directory from a `SIGKILL`ed turn
would therefore be durable, which is exactly the accumulation `0039 §5`
added the prune to prevent. It now removes directories with
`shutil.rmtree`.

## Non-goals

- No `git apply --check` gate on the generated patch. It is worth doing
  and it is separate work; adding it here would mean this task's
  verification could pass on a gate rather than on the generation.
- No change to `$CASTLE_TARGET_FILE`'s contract. The tenant still writes
  the word. What is added is a cross-check: if the tenant edited under
  `private/` and stamped `mechanism`, the two disagree, no `target` is
  recorded, and the body says why — the same posture the existing
  unresolvable-target branch takes. A wrong stamp is how a resident's
  own file would end up committed to a public repository.
- No new Nix option and no change to `stateDir`'s type.
- No relaxation of any rule in the wrapper's forbidden list. The one
  thing added to the tenant's permissions is write access to a
  directory this harness created for it under the state directory.

## Rejected alternatives

**A full writable copy of the checkout.** The simplest possible contract
for the tenant — "here is a copy, edit it" — and it supports deletions
and new directories for free. Rejected on privacy and recursion: it puts
a second copy of the resident's private layer in the state directory
once per errand, and when `stateDir` is inside the private root (which
`0047` treats as a live configuration) the copy contains the directory
it is being written into.

**A manifest the tenant writes, pairing scratch files to checkout
paths.** Rejected because it is one more thing a model can get wrong,
and the failure mode is a patch against the wrong path — which is worse
than the one being fixed, since it may still apply.

**Post-processing git's `--- a/` and `+++ b/` header lines.** Works, and
was the first design. Rejected once `--no-prefix` against directories
named `a` and `b` was measured to produce exactly the wanted headers:
the whole point of this task is that nothing edits a patch's framing by
hand, and that includes this harness.

## Verification

Automated, and the bar is that a *generated* patch round-trips:

- `test/agent-loop/generated-diff.sh`, a new harness in the
  `dispatch-test` job: a real `castle work` turn against a real fixture
  checkout, whose scripted tenant edits its mirror copy, asserting the
  `.patch` sidecar in the journal is accepted by `git apply --check`
  against that checkout and that the checkout itself never moved.
  Scenarios: a one-line edit, a two-file edit, a new file, a
  `suppressBlankEmpty = true` global git config, a tenant that writes
  `$CASTLE_DIFF_FILE` as well (generated wins, discard stated), a role
  disagreement, and a turn that edits nothing.
- A regression fixture carrying the finding's two defects together,
  asserting `git apply --check` rejects it and accepts the generated
  patch for the same edit.
- The existing suites, all of which drive this code path:
  `dispatch-test.sh`, `resume.sh`, `config-target.sh`, `approval.sh`,
  `apply.sh`, `outbox.sh`, `run.sh`, `activation.sh`, `state-layout.sh`.
- One assertion that the *rendered* prompt carries the new rules, since
  a prompt rule nothing checks is a comment.
- `nix flake check`.

Human hands, on the reference host: one live errand whose fix is a real
edit, confirming the proposal applies rather than refuses. That is the
same test the resident already ran by accident. No harness here runs a
sandboxed tenant, so nothing in CI establishes that a headless `claude`
can write under `$CASTLE_EDIT_DIR` — only that the harness grants it and
that the generation is correct.
