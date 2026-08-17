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

## Spec workflow

When asked to spec a feature: choose the smallest next chunk of useful
work, ask clarifying questions first, then draft a numbered brief in
`docs/tasks/` containing the spec, plan, and an implementation prompt
for a separate session. Always ask for explicit approval before writing
the brief — or any CLAUDE.md change — to disk. The brief is committed on
the branch that implements it, per the tasks convention.

Every brief states its verification plan: what the implementing agent
can test with no human involved (build it if cheap — a VM, a dry run,
CI), and which steps genuinely need human hands. Bias toward the
user's time when it's faster — a minute of manual work beats an hour
of harness-building for a one-off — but a step that will repeat
belongs in a harness before it repeats.
