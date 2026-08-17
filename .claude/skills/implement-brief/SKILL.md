---
name: implement-brief
description: Implement a numbered task brief from docs/tasks/ in the Castle Turing repo. Loads the project context an implementer needs, the hard constraints, and the verification approach — so a cold agent does not re-derive them. Use when asked to implement, build, or start a numbered brief (e.g. "implement 0011", "build the brief on docs/tasks/0011-*"), or when briefing a subagent to do so.
---

# Implementing a Castle Turing task brief

This packages the preamble every implementer needs. The brief itself is
the spec — this is the context around it.

## First: is there a brief?

**Implementation work gets a numbered brief in `docs/tasks/`.** Not
"substantial" work — implementation work. `CLAUDE.md` states this
without a size threshold, and a small change is exactly where the
temptation to skip it bites.

If you are about to write code and no brief exists, **stop and ask for
one** rather than proceeding and explaining yourself in the PR
description. Two reasons, and the second is the real one:

1. The brief rides the branch that implements it, so spec and
   implementation merge and get audited together. A PR opened without
   one has nothing to audit the code *against*.
2. **A PR description is not in the repo.** It lives on a hosting
   service. This project's own conventions — the backlog in files, the
   RFCs in the tree — exist precisely so a clone contains the whole
   argument and nothing depends on a service being up. "The PR
   description carries the reasoning" moves the reasoning to the one
   place these conventions were written to avoid depending on.

This has been got wrong twice, both times by an orchestrator deciding a
change was too small to deserve a brief, and both times the code review
caught it. Proportionality is not the test; "is this implementation
work" is.

Docs-only changes — a proposal, a backlog entry, a correction to prose —
are not implementation work and need no brief.

## Read, in this order

1. **`CLAUDE.md`** — the hard rules. They are absolute.
2. **The brief you are implementing** (`docs/tasks/NNNN-*.md`). Read its
   reasoning sections before writing code, not after; briefs here argue
   for their design, and the argument is usually load-bearing.
3. **`docs/architecture.md`** — the agent layer's spec: seats, records,
   provenance, and the numbered Proposals. If the brief touches the
   agent layer, the Proposals constrain how.
4. **`docs/vision.md`** and `docs/principles/` — read once per session.
   Numbered principles are binding on architecture decisions.
5. **The code the brief extends**, plus the briefs that produced it (a
   brief's Coordination section names its territory).

## Hard constraints

- **No personal data, ever** — no usernames, emails, keys, hostnames,
  IPs, or any real person's stated preferences. Not in code, docs, test
  fixtures, or commit messages. Use the repo's placeholder conventions
  (`resident`, `<host-ip>`, `<you>`). Invented strings in fixtures.
- **Public repo only.** Never touch a private layer repo, never SSH
  anywhere, never run `nixos-rebuild`. Deployment is a resident action.
- **Never commit to `main`.** Work on the brief's branch; PRs are how
  merges happen. Do not merge.
- **Principle 01 test on every change**: public mechanism + private
  configuration. If a feature cannot split that way, say so rather than
  merging it.
- **No hardware assumptions in `modules/`** — machine facts belong in
  `hosts/<name>/`.

## Verification

There is **no `nix` on the development machine.** Correctness is proven
by CI, not locally:

```sh
gh workflow run check.yml --ref <branch>
gh run list --branch <branch>
gh run view <id> --log-failed
```

`vm-install-test.yml` is slow (several minutes) — trigger it, then poll
rather than blocking. Both workflows accept `workflow_dispatch`, so a
branch can be checked before a PR exists.

Never weaken or delete an existing check to make something pass.

### "CI green" is not always sufficient evidence

This has bitten the project twice, both times semantically rather than
syntactically:

- `nix flake check` proves the Nix options *evaluate*. It does not prove
  the generated config says the right thing.
- `sway --validate` accepted a config containing exactly one keybinding
  — valid Sway, and a session with no terminal and no way to exit.

**When a change generates an artifact, read the generated artifact.**
The CI jobs print them for exactly this reason. Assert on content, not
just exit status.

## Deliverables

- Logical commits on the brief's branch, pushed, CI green.
- Commit messages in the repo's style: imperative subject, body
  explaining *why* rather than restating the diff. End with the
  appropriate `Co-Authored-By:` trailer.
- **A decision log** in the session scratchpad: every judgment call a
  reviewer might have made differently, one line of rationale each, plus
  an honest section on anything faked, stubbed, or unverified. A human
  reads this.
- **`/code-review` before opening the PR**, scoped against
  `origin/main` after a `git fetch` — never a local branch ref. Then
  `tools/codex-review.sh` for the cross-model pass; post its output
  verbatim and put your dispositions in a separate comment underneath.
- **Push, then report — do not poll CI from inside the task.** The
  harness re-invokes you when work completes, so an agent that loops
  waiting on `gh run list` pays full freight to advance nothing. One
  agent burned ~88k tokens this way after its work was already pushed.
  Trigger the run, report, and let the orchestrator watch it.

## Conventions worth knowing before you trip on them

- **Briefs ride their branch.** A brief is committed on the branch that
  implements it, never separately, so spec and implementation are
  audited together.
- **Promoting a backlog entry deletes it** in the same commit that adds
  the brief. Check whether anything cites the deleted file by path —
  `docs/architecture.md` has done so before.
- **Records are append-only.** A bad reference written into the journal
  can never be validated clean again, so resolve every ref *before*
  writing anything. Reuse the existing pre-check pattern in
  `agent/castle`.
- **`hosts/vm-test` deliberately imports no agent module.** That is the
  anti-bricking regression test, not an oversight — leave it alone.

## If you get stuck

Make the smallest reasonable call, proceed, and log it. Do not stall
waiting for input. If a decision would change the shape of the work
rather than a detail, log it prominently and flag it in the report so
the human sees it at review rather than after merge.
