The codex connector's reviews have no dispositioner

Discovered 2026-09-08, when sprint PRs #112–#114 sat with
chatgpt-codex-connector reviews and no dispositions. The chain that
used to close this loop is disconnected: task 0052 installed the
chevaline handle-review-findings workflow and the old
claude-codex-followup.yml was removed with that transition — but the
installed handler fires only on the cross-vendor gate's marker
comment, and nothing posts a gate comment on sprint PRs (the codex
GitHub connector reviews them instead, as GitHub reviews, which carry
no marker). So findings arrive and nothing downstream owns them: the
review's cost is spent and its receipts rule — every finding fixed
with the commit named, or declined with reasoning — is not applied.
The failure is silent and looks exactly like "no findings today",
which is the failure mode the marker convention exists to prevent.
For the record, the removed workflow's own run history ended the same
way its predecessor's did: cancelled and skipped runs, none finishing.

Running the chevaline gate on these PRs as well would be the wrong
fix: the gate's reviewer is codex too, and a second codex round per
PR reproduces the 2026-09-02 duplicate-review collision (competing
fixes for the same finding, reconciled by hand on PR #71).

The fix space, for whoever specs this:

- Extend or accompany the handler so a connector review triggers a
  dispositions round — a workflow on `pull_request_review` filtered
  to the connector's login, applying the same judge → fix → single
  dispositions comment contract, with the concurrency and permission
  scar-tissue rules from the chevaline template carried over intact.
- Or retire the connector on this repository and have sprint launches
  post the chevaline gate instead, as dovetail and emcee do — one
  review round, one handler, one convention across the ecosystem, at
  the cost of losing the connector's inline-comment placement.

Interim practice until either lands: after a castle sprint, a session
agent dispositions the connector reviews by hand — done for #112–#114
on the day this was filed.
