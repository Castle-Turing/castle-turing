# Refuse a mechanism-targeted proposal before the resident decides it

**What.** A worker turn that proposes a change to the Castle Turing
framework checkout (`target: mechanism`) files an ordinary proposal
question, the resident is asked to approve it like any other change,
and the applier then refuses it — `refused-target-mechanism`. The
refusal is correct and named, but it arrives *after* an approval.
Check it at filing time instead, so nobody is asked to authorize
something that cannot be spent.

**Why it matters.** A small betrayal, but a real one, on the one screen
in this system where authority is granted. A resident reads a change,
decides it is right, presses approve — and is told afterwards that the
decision could never have had an effect. That is exactly the shape
`docs/tasks/0015-filed-not-in-progress.md` named as the defect this
project keeps rediscovering: a label that causes the inaction it
describes. The refusal is honest about it (the record says the approval
is still the record of what they thought, and the change is theirs to
carry upstream) but honesty after the fact is not the same as not
asking.

**What we already know.**

- `docs/tasks/0024-config-target.md` made `target` a two-value role and
  `docs/tasks/0025-approval.md` files a proposal question for any
  stamped target, stating in its own stop conditions
  (`:1087-1090`) that nothing distinguishes the two. That was
  deliberate there.
- `docs/tasks/0026-apply-validate.md` §G decided the refusal belongs at
  apply time *for that task*, because moving it is a change to
  0024/0025's writing path rather than to the applier's, and because it
  wanted `test/agent-loop/approval.sh`'s existing mechanism-target
  scenario to keep meaning what it means.
- `test/agent-loop/apply.sh` covers the apply-time refusal, including
  that the wording must not imply the change was proposed against the
  wrong layer.
- **The refusal must not decide where host modules live.** The original
  exhaustion pass proposed refusing any root containing
  `docs/principles/`, which would contradict 0024's own design rather
  than protect anything. Not adopted, and named here so nobody
  re-derives it.
- The two obvious filing-time shapes are: refuse to stamp
  `authorizes-apply` on a mechanism-targeted proposal (so it is still
  decidable, and deciding it still records what the resident thought,
  but the screen says plainly that approving authorizes nothing), or
  refuse to file the question at all (so it never appears). The first
  is almost certainly right — an opinion about a framework change is
  worth having in the journal — but it is a decision, not an obvious
  consequence.

**Open questions.** Which of the two shapes? What does the review
screen say for such a change, given that its boundary statement is the
thing that defines what approving means? Does this interact with
`docs/backlog/where-do-host-modules-live.md` — if hardware host modules
turn out to belong to the public layer after all, does a resident ever
have a legitimate reason to want a mechanism-targeted change applied
locally? And what happens to the several proposals of this shape that
may already be sitting in a journal, decided or not, since nothing may
rewrite them?
