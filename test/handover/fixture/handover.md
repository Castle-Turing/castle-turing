# Handover — 2026-09-01 to 2026-09-06

## Intent

Milestone 2 redesigns castle-modal's UX per the comp in docs/comps/, produced by the pipeline
rather than by hand, so the workflow pieces prove themselves end to end [state m2-intent]. The
resident states the complaint in the modal; work decomposes into briefs; questions route back;
emcee dispatches; handovers report where the plan stands [state m2-done]. Binding constraints:
baseline logging before pipeline changes, and receipts, never verdicts [state m2-constraints].

## Threats and drift

- Pipeline-changing work merged while baseline instrumentation is recorded as not started
  [state m2-now]: the proposal-path rework [#90 #91 #93 #94] has no pre-period, which
  [state m2-constraints] says forfeits the time series unless the resident knowingly waives it.
- PR #78 merged, checks red — a handle-codex-review run reports FAILURE [#78]; related gaps are
  filed [backlog: the-codex-followup-cannot-push-workflow-fixes].
- Five merged PRs carry findings undispositioned [#66 #92 #94 #96 #101] — the ritual expects
  each finding answered before the resident reads the PR.
- Merges with no checks: [#68 #82 #89 #92 #97 #98 #99]; no review posted on much of the window,
  e.g. [#75 #76 #79 #83 #84 #85 #86 #87].
- Briefs for merged work sit in the queue [task 0058] [task 0059]; the citation-rot cost of the
  move is filed [backlog: tidying-a-brief-into-done-rots-its-citations].
- Not yet designed: milestone decomposition into briefs; question-routing wiring [state m2-now].

## What changed

- Sprint briefs 0034–0048 and 0051 merged [#63 #65 #66 #67 #69 #71 #72 #73], plus
  [#76 #78 #79 #81 #83 #85 #86 #87].
- Activation thread merged, checks green [#87 #96 #100 #101]: castle rebuilds its own machine,
  the privileged switch reads the repository, the sandbox and confirmation follow the contract.
- Proposal path: generated diffs, pre-offer checking, refusal taxonomy [#90 #91 #93 #94].
- Process machinery: codex-followup receipts [#78], the review-findings handler [#84],
  model-tier reasoning in task files [#88], operator paths scrubbed [#80].
- Backlog intake [#64 #68 #70 #74 #92 #95 #97 #98]; queue tidy sweeps [#75 #82 #89 #99];
  August research reports [#77]; a foot-setting sweep tool [#102], checks green.

## Unverified

- The journal was not read (built with --no-journal), so no runtime behavior is grounded here:
  whether dispatch, activation, or the modal behave on the real machine is [unverified].
- Whether any merged change runs on a deployed host is [unverified]; the ledger ends at the forge.

## Verdicts requested

- Does merging task 0061's work constitute approval of the clarifying-questions brief
  [task 0061] [task 0065], as [state m2-now] infers?
  Depends: whether 0065 dispatches to emcee or waits for an explicit approval.
- Backfill the ritual or accept the gap: findings undispositioned [#66 #92 #94 #96 #101],
  checks red [#78].
  Depends: whether dispositions get posted and the red run investigated, or the gap is recorded.
- Waive baseline-before-intervention for the merged pipeline changes [#90 #91 #93 #94], or hold
  further pipeline-changing briefs until outcome logging runs [state m2-constraints]?
  Depends: which brief emcee picks up next — instrumentation first, or the queue as it stands.

## Acknowledgment

Please write back — the three verdicts above, or an explicit "nothing needed". An
unacknowledged handover surfaces in the next one.
