# Agent guidance — Castle Turing

You are working in the **public framework repo**. Read `docs/vision.md` once
per session if you haven't; it is the founding context. Numbered documents in
`docs/principles/` are formally adopted and binding on all architecture
decisions.

## Hard rules

- **Never write personal data into this repo.** No credentials, tokens, email
  addresses of real correspondents, calendar contents, stated priorities, or
  any artifact of the user's private layer — not in code, not in docs, not in
  test fixtures, not in commit messages. If a task seems to require it, stop
  and design the private-layer slot instead.
- **Principle 01 test on every change:** public mechanism + private
  configuration. If a feature can't split that way, the design is not done —
  say so rather than merging it.
- **No hardware assumptions in `modules/`.** Anything specific to a machine
  belongs in its `hosts/<name>/` module.
- **Docs are written for strangers**: a reader who is not us, on hardware
  that is not ours, with priorities that are not ours.

## Conventions

- Design principles are numbered sequentially (`01-`, `02-`, …) and are only
  added deliberately — a principle doc is a commitment, not a note. Drafts
  live in PRs, not in `docs/principles/`.
- Deferred work lives in `docs/backlog/`, one plain-text file per item,
  not in an issue tracker — see that directory's README. Speccing an
  entry promotes it to a numbered brief and deletes the backlog file in
  the same commit.
- Implementation work is specced as numbered briefs in `docs/tasks/`
  (`0001-`, `0002-`, …). A brief is committed on the branch that implements
  it, never separately — spec and implementation merge and get audited
  together.
- Prefer plain text and standard formats everywhere: they are the point of
  the project. If a tool choice trades AI-legibility for features, flag it.
- Keep the flake evaluating (`nix flake check`) once it is non-trivial.
  Rollbackability is a load-bearing promise.

## Multi-agent work

Parallel sessions use git worktrees, one branch per session. Do not commit
directly to `main` from an agent session; merges go through PRs so the human
can run the weekly-audit muscle on code the same way as on decisions.

Before opening a PR, run `/code-review` on the branch and address its
findings, then run `tools/codex-review.sh` for a second, cross-model
opinion. Codex's findings are posted verbatim — no seat summarises or
filters an independent reviewer before the human sees it — and any
disposition goes in a separate comment underneath, so a disagreement
between the two reviewers stays legible. The human still makes every
merge decision.

Codex's GitHub-integrated review is *not* what runs here: it requires a
ChatGPT Pro plan on org-owned repositories, which is why the review moved
to the CLI. See `docs/backlog/cross-model-review-is-paywalled.md`.

Scope every review and diff against `origin/main`, never a local branch
ref. Worktrees accumulate stale local branches, and a stale base produces
confident findings about code you never touched. `git fetch` first, then
confirm the real scope with `git diff origin/main...HEAD --stat` before
trusting any review output. The same rule holds for anything else derived
from a ref you did not just refresh — flake locks and path overrides
included.

**Start every session on a freshly pulled `main`.** Not `git fetch`
alone — the working tree too. A session opens on whatever branch the
last one left checked out, and that branch's `CLAUDE.md`, task
numbering, and conventions are exactly as stale as the branch is. This
has already bitten: a session began work against a `CLAUDE.md` with no
`## Delegation` section, days after that section landed on `main`, and
allocated a task number four short of the real next one. Before reading
anything else in the repo:

    git fetch --all --prune && git checkout main && git pull --ff-only

Branch or check out the working branch *after* that, so the conventions
you read are the current ones.

## Delegation

Work is handed off, not done by the session that receives it. The
session talking to the human passes the instruction to a **Fable**
sub-agent, which owns the job from spec through implementation:

1. Fable picks a model to write the brief, sized to the ask — down to
   Haiku when the ask is mechanical.
2. Fable reviews the returned brief and sends it back for revision
   until it is good. A brief nobody reviewed is not a brief.
3. Fable picks a model to implement, again down to Haiku.
4. Fable verifies the implementation itself before reporting up.

**Size the implementer to the risk that the brief is wrong, not to the
size of the diff.** A one-line config change specced wrongly is still a
wrong change, and a small model will follow a bad brief off a cliff
without noticing. Task 0017's brief instructed its implementer to use
`lib.mkDefault` where an `mkOption` default was correct — a priority
collision waiting to happen — and it was caught only because the
implementer had enough judgment to argue with the spec and record the
deviation. Mechanical work against an exact, already-verified spec is
Haiku work. Work where the brief itself might be wrong is not, however
small the edit looks.

**State why you chose that tier, in the file.** A task file carries
`Model-because:` beside `Model:` — one line on what about this task
makes that tier right, phrased against the tier you did not choose.
Every task file states both: routing is not optional, so a missing
`Model:` is a silent default rather than an absence, and the silent
ones are exactly the ones worth catching. A reason that would have
supported the opposite choice equally well is not a reason. Say what
breaks if the implementer is smaller, or what is mechanical enough
that nothing does.

This exists because on 2026-09-04 task 0051 was written with
`Model: deep` copied from the neighbouring task file being used as a
template, and its justification was assembled only when the human
asked for it — the agent could have argued either way and had argued
neither. The header recorded an answer with no evidence anyone had
chosen it, which is the same defect the dispositions rule closes for
review findings: silence must not be able to look like a decision.

The check this cannot be is a validator. A harness can only confirm
that some string is present, and a required free-text field with
nothing reading it produces ritual compliance rather than reasoning.
It is enforced by the agent writing the file and by whoever reads the
diff, which is why it lives here rather than in the harness.

What delegation does not relax:

- **Clarifying questions belong to the human.** No sub-agent can ask
  one. Questions travel back up the chain; a sub-agent must never
  invent an answer the spec workflow says to ask for.
- **Approval before a brief lands on disk.** Fable returns the draft
  and waits — unless the human granted autonomy for that task, the same
  suspension the spec workflow already describes.
- **Numbers are allocated before delegation**, never chosen by the
  writer: parallel writers all compute the same "next" number.
- **One worktree per branch**, and sub-agents are told explicitly not
  to touch the primary checkout.
- **Every report is a claim, not evidence.** Whoever delegated re-reads
  the diff and re-runs the check.

## Spec workflow

When asked to spec a feature: choose the smallest next chunk of useful
work, ask clarifying questions first, then draft a numbered brief in
`docs/tasks/` containing the spec, plan, and an implementation prompt
for a separate session. The brief is committed on the branch that
implements it, per the tasks convention.

**Every piece of implementation work gets a brief, however small.**
Proportionality decides a brief's length, never whether it exists: a
feature earns clarifying questions and a full spec, a mechanical change
earns fifteen lines committed alongside the work. What must not happen
is a change whose reasoning lives only in a PR description — that is on
a hosting service, not in the repo, and it is the one place these
conventions exist to avoid depending on. `docs/tasks/` is the log a
future agent reads cold to learn why the code is shaped as it is, and
especially what was considered and rejected; git history records only
what changed.

**If the design shifts during implementation, the same PR updates the
brief.** Briefs are written up front and ride their branch, so nothing
else corrects one the work has overtaken, and a brief confidently
describing an abandoned design is worse than none.

**Approval, and how autonomy overrides it.** Ask for explicit approval
before writing a brief to disk. That default is suspended for the scope
of an explicit instruction to work autonomously — then write the brief,
proceed, and record every judgment call that would otherwise have been
a question, so the approval happens in review rather than not at all.
Autonomy relaxes *when* the human is consulted; it never relaxes the
conventions themselves. Watch for this specifically: the two times a
brief has been skipped in this project, both were under an autonomy
grant, by an agent treating "work autonomously" as licence to decide a
change was too small to document.

**A CLAUDE.md change always needs explicit approval**, autonomy grant or
not. These are the rules the rest runs on; an agent must never quietly
rewrite the thing it is being held to.

Every brief states its verification plan: what the implementing agent
can test with no human involved (build it if cheap — a VM, a dry run,
CI), and which steps genuinely need human hands. Bias toward the
user's time when it's faster — a minute of manual work beats an hour
of harness-building for a one-off — but a step that will repeat
belongs in a harness before it repeats.
