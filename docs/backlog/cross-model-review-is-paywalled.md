# The second reviewer is gone, and only one model reviews now

**What.** `CLAUDE.md` describes the review process as two models: "Before
opening a PR, run `/code-review` on the branch and address its findings.
Codex reviews the PR itself as a second, cross-model opinion; the human
still makes every merge decision."

The second half of that stopped being true on 2026-08-16, when this repo
moved under the `Castle-Turing` organization. Codex code review on an
**organization-owned** repository requires a ChatGPT Pro plan; on a
personal repository it does not. The repo did not change, the config did
not change — the owner did.

**How it presents, which is worse than the limitation itself.** Nothing
fails. There is no error, no warning, and no entry in Codex's own
analytics — reviews simply stop being *attempted*. Everything a person
would check looks correct: the GitHub App is installed on the org with
the repo explicitly selected and read/write on pull requests, the
connector reports connected, the repository is enabled for code review
with `On PR open`, and the weekly usage limit is 86% unspent. The only
visible symptom is a `Review all PRs` option that renders greyed out,
and the reason for that is in a tooltip.

Diagnosis took roughly an hour and ended at a tooltip. Codex, asked
directly, could not say why it had stopped.

**Why it matters more than a missing convenience.** The value of the
second reviewer was never that it found more bugs. It was that it found
*different* ones. Chevaline's own RFC conventions state the principle
this repo now violates:

> Agreement between reviewers is not evidence. Models trained on
> overlapping data make overlapping mistakes. Five reviews converging on
> the same point is one point, not five, and may be one shared blind
> spot.

What remains is Claude reviewing Claude's work — the automated
`claude-review` workflow, plus `/code-review` run by the same family of
model that wrote the code. Whatever both are blind to now ships. The
loss is not throughput; it is independence, and independence is the only
thing a second reviewer was ever for.

There is a related gap this exposed rather than caused: the
`claude-codex-followup.yml` workflow closes the loop on *Codex's*
findings — judging each one, fixing the valid ones, replying to the rest.
Nothing does that for Claude's own review comments. Before the move that
did not matter much, because the findings that mattered came from the
other model. Now every finding comes from Claude and none of them are
automatically addressed. Task 0010's PR carried a real bug for hours for
exactly this reason.

**Options, none taken yet.**

- **Pay for Pro.** Rejected for now — the limitation is arbitrary enough
  that rewarding it grates, and the repo is public, which makes the gate
  harder to justify.
- **Move the repo back under a personal account.** Restores the reviewer
  and gives up the org, which exists for good reasons (the project is
  meant to outlive one person's account, and `chevaline` lives there
  too). Not obviously wrong, but a large lever for a small gain.
- **Mirror to a personal fork and review there.** A fork in the private
  layer, kept in sync, with Codex reviewing PRs against the mirror and
  findings copied back. Technically possible and genuinely gnarly:
  two-way sync, comment provenance, and a second place for the audit
  trail to live. Deliberately parked rather than built.
- **Replace the second opinion with a different model entirely.** The
  seat is what matters, not the tenant — Proposal 03's argument applied
  to reviewers. Any model that can read a diff and write findings to a
  PR can hold it. This is probably the right answer and the one most
  consistent with the project's own architecture.
- **Close the loop on Claude's own findings** — a follow-up workflow for
  `claude-review` comments, mirroring the Codex one. Cheaper than any of
  the above and orthogonal to which model reviews.

**Until something is decided,** `CLAUDE.md`'s review paragraph describes
a process that no longer runs. Either it should be corrected to say one
model reviews, or the second reviewer should be restored — but it should
not keep asserting a cross-model check that is not happening.
