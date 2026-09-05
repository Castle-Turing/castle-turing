Title: Task 0059 — confirming a switch suggests what to check
Model: deep
Model-because: the deliverable is resident-facing text on the one
surface whose failure mode is training a reflex yes, and its breadth is
the whole point — a sentence that reads well and points at the wrong
thing ("check a binding or two") passes on the exact machine that
motivated this. The mapping from an approved change to a checkable
sentence is a judgment surface, not a template, and a standard-tier
implementer would produce plausible prose whose breadth is wrong in a
way no test can see. What is mechanical here — a `git show
--name-only` and four lines of string assembly — is not the part that
can be got wrong.

# Task 0059 — confirming a switch suggests what to check

**Before starting:** read `CLAUDE.md` and
`.claude/skills/implement-brief/SKILL.md`; both bind everything below.
Then `docs/tasks/done/0048-activation.md` §E, which designed the
question this task adds a paragraph to and states the asymmetry that
makes the window's default right; `docs/tasks/done/0025-approval.md`,
whose exact-wording discipline binds every word this task puts on that
screen; and
`docs/backlog/the-modal-could-choose-its-opening-view.md`, which is
where the line this task has to stay on the right side of was drawn.
This brief promotes
`docs/backlog/confirming-a-switch-suggests-nothing-to-check.md` and
deletes it in the same commit.

## Why

On 2026-09-05, minutes after the first end-to-end change in this
project's history, the resident confirmed a switch that had silently
discarded every Sway keybinding except the two the change added. The
health window was open, armed, and pointed at exactly that generation.
It closed unspent, because the one check that would have failed — "do
your chords still work?" — was never suggested and there was no reason
to think of it.

The window worked. Everything 0048 §E built worked. What failed is
that the question it files says only this:

> This machine has switched to the new configuration. Is it working?
> If nothing says so in time, Castle rolls back to the previous
> generation.

That invites a verdict and supplies no basis for one. A resident who
has just approved a change and watched it land has every reason to
believe the machine is fine, and nothing in front of them argues
otherwise. Left as it is, this surface teaches a reflex yes, which is
the same defect 0048 refused to build into the *approval* question
("a question a resident cannot meaningfully refuse is a question that
trains them to say yes") and then shipped one screen later.

The resident's own words on being shown the diagnosis: a confirmation
prompt that suggests what to check "was exactly what I was thinking."

## What this is allowed to do, and why that boundary holds

`docs/backlog/the-modal-could-choose-its-opening-view.md` records the
distinction the resident drew: a surface may act on information it was
*given*, and must not volunteer help nobody asked for. Intelligence in
the default is welcome; Clippy is not.

This lands on the right side of that line and it is worth saying
exactly why, because "suggest what to check" reads like the wrong side
at a glance. The suggestion is derived from **the change itself and
nothing else**: which files the approved change rewrote in the
resident's own configuration repository, or which framework revision
the pin bump adopted. Both are facts the mechanism was handed in the
course of doing what it was asked to do. It reads no history, models no
intent, guesses at nothing, and says nothing about any other change.
It is shown quietly, in the body of a question that was going to be
asked anyway, and it adds no keypress and no interruption.

## The design

### §A. Where the sentence goes

Into the health question's own **body**, composed at filing time —
exactly as an activation question's body is composed from
`ACTIVATION_QUESTION_BODY` plus `ACTIVATION_QUESTION_CAVEAT` today.
Not into `REVIEW_BOUNDARY_STATEMENT_HEALTH`.

That split is 0025's discipline and it is load-bearing here. A
boundary statement is the scope of the authority a resident spends;
this text is not about authority at all, and putting it there would
both dilute the statement and, worse, make a change to advisory prose
a change to the sentence a decision was made under. The body is also
what a digest renders and what `_fire_notification` carries, which is
where the caveat went for the same reason.

The question's existing first line is unchanged. It is the picker's
preview and the notification's line, and it still says the true and
most important thing.

### §B. What it says on the applied-change trigger

Below the existing first line, a blank line, then the naming
paragraph:

    Before you confirm, check something this switch did not add. It
    rewrote these files in your configuration repository:

        home/desktop.nix
        modules/keyboard.nix

    A change that adds one setting and silently discards the ones that
    were already there leaves its own setting working perfectly, so the
    new thing working is not evidence that the rest of it survived.

**The breadth sentence is the point of this task, not decoration.** In
the motivating incident the two added bindings were the only two that
worked. A suggestion that said "check a binding or two" would have
passed on a machine with one usable chord and no way to open a
terminal. So the text says what to check *against* — what the change
did not add — and says why the obvious check is worthless. That
sentence is fixed prose and is the same on every trigger.

**Naming files, not option paths.** The backlog entry's floor is
"naming the files or option paths that changed", and this takes the
files. Option paths would be better — `wayland.windowManager.sway
.config.keybindings` tells a resident what to go press — and getting
them means parsing Nix out of a diff, which is a parser this repo
would then own forever and which would be wrong on any expression it
did not anticipate. Files are what git will tell us exactly, and they
are enough to point attention at a neighbourhood. Per-option
suggestions can grow behind this same line later, on a mechanism that
is not a hand-rolled parser; the backlog entry already says so.

**Where the file list comes from: the applier's own commit.** The
build result names every apply result it accounts for (0048 §B — one
build can cover several), and an apply result that landed carries
`apply-commit`, which 0026 stamps only where exactly one commit was
verified to have landed. `git show --name-only --format= <sha>` in the
resident's configuration repository, unioned across those commits, in
the order the build named them, is the answer. That is the same
authority the applier itself used, and it needs no new record field
and no second parser.

`-c core.quotePath=false`, so an ordinary non-ASCII path reads as
itself. `_run_git` already decodes with `errors="replace"`, so what
comes back is safe to write into a UTF-8 record without going through
`_displayable`; nothing here is ever handed back to git.

**An incomplete list says so.** If any apply result the build named
could not be resolved to paths — no `apply-commit` on it, no
configured repository, git unavailable or refusing — the paragraph
gains one more line:

    Castle could not establish every file this change touched, so that
    list may be short.

This is not defensive verbosity. A short list read as complete narrows
attention, which is the precise failure this task exists to fix; a
suggestion that quietly under-reports is worse than the silence it
replaces.

If **no** paths could be established at all, the naming paragraph is
dropped and only the breadth sentence is shown, opening "Before you
confirm, check something this switch did not add." That sentence is
true of every switch and needs no derivation, so the degraded case is
still better than today.

### §C. What it says on the pin-bump trigger

A pin bump adopts a framework revision. Its commit touches
`flake.lock` and naming that file would be true and useless — the
change is in what the whole configuration evaluates to, not in one
file. So the naming paragraph is replaced:

    Before you confirm, check something this switch did not add. It
    adopted framework revision <rev>, which is not confined to any one
    file — it can change anything on this machine that your
    configuration takes from the framework.

Then the same fixed breadth sentence. The trigger is distinguished by
`build-target-rev` on the build result, which is present on exactly
this trigger and absent on the other (0048 §F).

### §D. When it is computed

**Before the switch is asked for, not after.** The facts are all
available at the top of `_activate_one` — the build record, the apply
results in `records`, the repository the pin bump is about to be
committed into — and computing them afterwards would mean running
`git` on a machine that has just moved and may be broken in exactly
the way this text exists to catch. A suggestion that disappears
precisely when it was needed is not a suggestion.

Best-effort throughout, and never fatal: a failure to derive anything
degrades to §B's last paragraph. The health question is more important
than the paragraph inside it, and `_file_health_question`'s existing
failure posture — printed, never raised, because the machine has
already switched — is unchanged.

## Non-goals

- **The window's posture.** Roll back unless confirmed, unchanged.
  This makes the confirmation a considered act; it does not move where
  the default falls.
- **The boundary statements.** None of the four is touched.
- **The activation (pre-switch) question.** It has its own body and its
  own caveat and is out of scope. What to check *afterwards* is not
  what a resident is deciding when they approve.
- **Per-option check suggestions**, and anything that reads a Nix
  expression. §B.
- **Any new record field or record type.** Everything this needs is
  already stamped.

## Considered and rejected

**Putting it in the boundary statement.** §A. It would make advisory
prose part of the sentence an authority was spent under.

**A new field on the build or apply result carrying the touched
paths.** It would put the same fact in the journal twice, and the
second copy could disagree with the commit. The commit is the fact.

**Naming the files from the patch sidecar instead of the commit.** The
sidecar is the proposal; the commit is what landed. Where they differ
the commit is right, and the commit is also the only one of the two
that exists for every applied change regardless of which seat produced
it.

**Suggesting a specific check ("try your keybindings").** That is the
per-option mapping §B defers, and improvised now it would be a
hardcoded guess about one incident dressed as a general mechanism.

**Saying nothing when the derivation fails.** §B: the generic breadth
sentence costs nothing, is always true, and is the whole of what the
motivating incident actually needed.

## File-by-file change list

- `docs/tasks/0059-confirming-a-switch-suggests-what-to-check.md` —
  this brief.
- `docs/backlog/confirming-a-switch-suggests-nothing-to-check.md` —
  deleted, promoted by this brief. Nothing else in the repository
  cites it by path (checked).
- `agent/castle` — the fixed prose constants beside
  `HEALTH_QUESTION_BODY`; `_switch_touched_paths`, deriving the file
  list from the apply commits a build accounted for;
  `_health_check_lines`, assembling the paragraph for either trigger;
  `_activate_one` computing them before the switch;
  `_file_health_question` taking them and composing the body.
- `test/agent-loop/activation.sh` — the assertions, and a fixture
  extension so a planted applied change makes a real commit and stamps
  `apply-commit` the way the applier does.

## Verification plan

Automated, no human: `test/agent-loop/activation.sh` in CI on every
push, extended with —

- the applied-change health question naming the file that change
  committed, and not naming a file it did not touch;
- the breadth sentence present, in the words that carry it, on both
  triggers;
- the pin-bump health question naming the adopted revision and *not*
  naming `flake.lock`;
- an applied change with no `apply-commit` degrading to the breadth
  sentence alone, with the health question still filed and still
  decidable.

**The activation tests pin the confirmation question's wording today,
and that is deliberate.** `test/agent-loop/activation.sh` §7 already
asserts on the health review's text, and this task adds more such
assertions. They exist so that a later change to this surface is a
change somebody made on purpose: the wording of a screen where
authority is spent, or where a resident is being told what to check
before it is spent, is not something a refactor may adjust in passing.
An implementer who finds one of these assertions failing has changed
resident-facing text and owes the change a reason in a brief — updating
the assertion is the second step, never the first.

`nix flake check` is unaffected: nothing here touches a module, an
option or a unit.

Human, on the reference host: none required for correctness. The
judgment this task is actually making — whether the sentence changes
what a resident does — is answerable only by the next real switch, and
the honest verification is that the resident reads the text on this
brief's PR and says whether it would have caught the incident that
produced it.

## Implementation prompt

Read `CLAUDE.md`, this brief in full, and the three documents its
preamble names. Then implement the file-by-file list. Do not touch any
of the four boundary statements. Do not add a record field. Do not
widen what the health question authorizes — it authorizes nothing, and
must keep carrying no `authorizes-activation`. Keep the question's
existing first line exactly as it is: it is the notification's line.
Record every judgment call in the session's decision log, and update
this brief in the same branch if the design shifts.
