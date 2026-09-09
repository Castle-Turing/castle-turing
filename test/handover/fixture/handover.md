# Handover — 2026-09-01 to 2026-09-05

## Intent
Milestone 2 rebuilds castle-modal's UX through the pipeline itself, forcing the workflow pieces
to prove themselves end to end [state m2-intent]. Its criteria: the complaint stated in the modal,
work decomposed into small briefs, clarifying questions routed back automatically, emcee
dispatching, handovers reporting, merging the resident's throughout [state m2-done, state m2-out].

## Threats and drift
- [#78] merged, checks red, and no review posted — the task meant to prove the codex followup's
  receipts rode over a red handle-codex-review run.
- Findings undispositioned on five merged PRs [#66 #92 #94 #96 #101] — each carries a review
  comment no disposition answered, silence posing as a decision.
- Checks skipped on seven merges [#64 #70 #74 #77 #80 #88 #95] and no checks on seven more
  [#68 #82 #89 #92 #97 #98 #99] — nothing marks which were exempt by design.
- Baseline outcome logging has not started while pipeline-changing work landed all window;
  [state m2-constraints] forfeits every measure without a pre-period unless knowingly waived, and
  [state m2-now] names it the unmet prerequisite.
- Briefs 0058 and 0059 sit in the queue [task 0058 task 0059] though their PRs merged, checks
  green [#100 #101]; the rot is filed [backlog: tidying-a-brief-into-done-rots-its-citations].
- Gaps filed in-window [backlog: bash-redirection-defeats-root-write-deny]
  [backlog: the-kernel-oom-killer-has-no-swap-headroom]
  [backlog: activation-is-not-proven-on-a-real-vm]: redirection bypasses the root write-deny,
  the OOM killer lacks swap headroom, and activation is unproven on a real VM.

## What changed
- Worker and proposal pipeline: finding outbox, contract revision, mechanism-finding routing,
  tenant allowlist, generated and pre-checked diffs, refusal taxonomy — merged, checks green
  [#71 #72 #76 #81 #83 #85 #90 #91 #93 #94].
- Activation: castle rebuilds its own machine, the privileged switch reads the repository, the
  sandbox allows the contract's read, confirmation suggests what to check, the waiter leaves
  the dispatch cgroup — merged, checks green [#86 #87 #96 #100 #101].
- Desktop and product surface: inbox modal, boot-fallback dedup, truthful reminder banner, MIT
  license, notification action key, foot-setting sweep tool — merged, checks green
  [#63 #65 #66 #67 #69 #102].
- Review and CI machinery: transient-flake retries, the shared record-ordering helper, the
  review-findings handler repair — merged, checks green [#73 #79 #84].
- Backlog intake from live use merged [#64 #68 #70 #74 #92 #95 #97 #98].
- Docs and queue housekeeping: research reports, operator-path scrub, the `Model-because:`
  rule, brief sweeps into `done/` — merged [#75 #77 #80 #82 #88 #89 #99].

## Unverified
- The ledger was built with `--no-journal`; no line here is grounded in a journal record, and
  runtime behavior between merges is invisible to this report [unverified].
- Whether any spend served or missed a milestone clause — the ledger carries no spend figures
  [unverified].

## Verdicts requested
- Findings undispositioned on [#66 #92 #94 #96 #101]: answer each now, or record a knowing waiver?
  Depends: whether a dispositions pass gets queued ahead of new milestone briefs.
- The red check on [#78]: let it stand as recorded, or spec a follow-up on the receipts lane?
  Depends: whether the codex followup is trusted on the next PR it runs against.
- The baseline clause [state m2-constraints] against [state m2-now]: waive knowingly, or hold
  pipeline-changing work until outcome logging runs?
  Depends: whether queued briefs 0062 and 0065 [task 0062 task 0065] proceed now or afterwards.

## Acknowledgment
Write back with the three verdicts above, or an explicit "nothing needed". This handover stays
open until you do, and the next one will say whether it was acknowledged.
