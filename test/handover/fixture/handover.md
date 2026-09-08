# Handover — 2026-09-01 to 2026-09-06

## Intent

The milestone is a redesign of castle-modal's UX per the comps, produced by the pipeline itself
rather than by hand — the workflow pieces must prove themselves end to end [state m2-intent].
Its criteria: the resident states the complaint in the modal, work decomposes into small briefs,
questions route back automatically, emcee picks tasks up, handovers report where the plan
stands, and the resident approves PRs and the deployment [state m2-done]. Receipts stay
receipts on every reporting surface, this one included [state m2-constraints].

## Threats and drift

- [#78] merged, checks red, no review posted — the window's one red merge.
- Five PRs merged with findings undispositioned [#66 #92 #94 #96 #101]; the ritual expects
  each finding fixed or declined before the resident reads the PR.
- Baseline instrumentation is not started [state m2-now] while pipeline-changing briefs wait
  [task 0062] [task 0065]; landing them first forfeits the pre-period [state m2-constraints].
- Briefs 0058 and 0059 sit in the queue [task 0058] [task 0059] though their PRs merged
  [#100 #101]; the citation-rot hazard behind such moves is filed
  [backlog: tidying-a-brief-into-done-rots-its-citations].
- Host-pressure and sandbox gaps filed in-window:
  [backlog: an-agent-workload-can-thrash-the-host]
  [backlog: the-kernel-oom-killer-has-no-swap-headroom]
  [backlog: bash-redirection-defeats-root-write-deny].

## What changed

- Worker and proposal-pipeline briefs merged, checks green:
  [#71 #76 #79 #81 #83 #85 #90 #91 #93 #94].
- Activation and sandbox briefs merged, checks green: [#86 #87 #96 #100 #101].
- Desktop, host, license and CI briefs merged, checks green: [#63 #65 #66 #67 #69 #72 #73 #102].
- The review-findings handler and the queue convention merged, checks green: [#75 #84].
- Backlog, research and process PRs merged, checks skipped: [#64 #70 #74 #77 #80 #88 #95].
- Backlog entries and brief sweeps merged, no checks: [#68 #82 #89 #92 #97 #98 #99].

## Unverified

- No journal records were available to this ledger, so nothing here grounds runtime behavior —
  dispatch runs, switch confirmations, modal use in the window. [unverified]
- Whether the window's merges serve the milestone is ungrounded: the milestone clauses carry a
  stated date of 2026-09-06, after every merge above. [unverified]

## Verdicts requested

- Disposition or decline the review findings on [#66 #92 #94 #96 #101].
  Depends: whether these findings get fixes or written dispositions before the next sprint.
- Rule on the red merge [#78]: accept it as it stands, or reland the codex-followup work.
  Depends: whether a reland branch is queued and the failing check gets a cause.
- Waive or enforce baseline-before-intervention [state m2-constraints] for the queued
  pipeline-changing briefs [task 0062] [task 0065].
  Depends: whether instrumentation is specced first or those briefs land as unmeasured bets.

## Acknowledgment

Write back with the three verdicts, or an explicit "nothing needed". A handover satisfied by
generation alone is not the contract; unacknowledged, it resurfaces in the next one.
