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
findings. Codex reviews the PR itself as a second, cross-model opinion; the
human still makes every merge decision.
