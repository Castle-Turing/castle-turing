# Automated approval: what production practice and the judge literature establish

*Research done 2026-09-10: two sweeps — production merge-automation
prior art, and LLM verdicts as merge gates, the latter run as a
delta over emcee's `docs/research/agentic-pr-review.md` — toward the
verdict-authorized-merge spec. Joins the completed 2026-08-17 castle
research recorded in the authority-taxonomy and
competence-measurement backlog entries. Second-hand figures are
flagged in place.*

## The qualified principle that survives everything

The strict hypothesis — production systems automate merging on
mechanical evidence alone, never model opinion — holds for the
classical systems and is refuted by the best modern one. Kubernetes
Tide merges on a pure conjunction of OWNERS-authorized labels and
green checks; bors, Zuul, and Chromium's commit queue add "green
against the actual merge state"; in all of them the human yes is a
precondition the bot checks, never something it produces. Meta's
RADAR (arXiv:2605.30208, May 2026; their production system, 535K+
diffs reviewed, 331K+ auto-landed) puts an LLM confidence score
inside the yes for human-authored diffs — but never alone: the
judgment sits inside envelopes earned from track record (per-source
risk-percentile thresholds, sixty days incident-free, bounded revert
rates, daily caps that expand with evidence), with a time-boxed
human veto window before every landing and automatic pausing on
incidents. Outcomes: RADAR-landed diffs revert at one-third the
human-landed rate and cause production incidents at one-fiftieth,
and Meta's experts judged none of its misses human-catchable either.
The refined principle: **judgment may enter the gate only inside an
envelope that mechanical evidence earned and can revoke.**

Mechanical evidence has its own integrity problem: the Codecov
(2021) and tj-actions (2025) compromises show a green check is only
as trustworthy as the supply chain producing it. Pinned SHAs and
provenance are part of the gate's foundation.

## Raw LLM verdicts are not gate-grade

On the one benchmark scoring merge-readiness directly (MathlibPR,
arXiv:2605.07147, formal-math domain), models and agents "struggle
to distinguish merge-ready PRs from build-passing PRs" [headline
accuracy second-hand]. On real PRs, eight frontier models detect
15–31% of human-flagged issues, degrading as context grows
(SWE-PRBench, arXiv:2603.26130); two heterogeneous frontier judges
agreed ~79% (kappa 0.616) on a small real-PR sample. Judge gaming is
quantified: self-play against a reference-free judge drove reported
pass rates 0.72 to 0.94 while true accuracy stayed at 0.20
(arXiv:2607.05904) — and the one cheap mitigation that works is
having the judge **commit its own assessment before seeing the
candidate's** (false positives 0.72 to 0.01). Same-family bias is
real and worst in small models (arXiv:2604.16790).

## Abstention works under one condition

Three independent 2026 groups converged on the conformal/PAC recipe
(arXiv:2407.18370, arXiv:2608.17994, arXiv:2607.04430): calibrate an
abstention threshold externally and precision on ruled cases becomes
provably controllable, trading coverage for reliability. The
boundary: models asked to self-decide when to escalate produce
miscalibrated, model-specific thresholds (arXiv:2604.08588), and
majority voting suppresses abstention on genuinely ambiguous cases
(arXiv:2606.07834). External calibration against labeled history;
aggregation that preserves "unclear." Nobody has run this recipe on
code review — an unrun experiment this project is positioned for,
since gate verdicts are journaled facts (emcee task 0047).

## Merge outcomes are not ground truth

Hand-coding of 717 agentic-PR rejections (MSR 2026,
arXiv:2605.22534): only 35.7% reflect genuine agent failure; 31.2%
are workflow artifacts; 33.1% show no observable rationale. Merge
outcome alone is not a valid quality label — a constraint on any
measurement built here (the cheap-slate review measurement, the
trend detector's labels), and independent support for retiring
resident approval as a quality signal: quality labels come from
dispositioned verdicts, acceptance checks, and operational outcomes
(reverts, incidents), not from merges.

## Graduated authority is the pattern; the line moved this month

Renovate's automerge tiers are the best written risk policy anywhere
(dependency type x semver bump x test coverage, plus a release-age
delay added explicitly after the npm supply-chain incidents).
Google's Rosie pattern-matches shards against committee-vetted
codemods; Macroscope and Greptile publish hard path exclusions no
judgment can override (auth, billing, secrets, CI, their own
config). Practitioner autonomy ladders stop short of unattended
merge — and on 2026-09-01 GitHub shipped Copilot approval counting
toward required-approvals rules (opt-in, path-scoped, dismissed on
new commits). The prior castle research composes directly: Electric
Elves says fixed category-to-tier assignments fail at transitions,
arguing for earned, revocable envelopes over a static table; the
competence-measurement identifiability wall (one operator cannot
infer both competence and difficulty from outcomes) is answered by
pinning difficulty externally via change-class tiers.

## What the spec should say

1. The yes is a conjunction with a bounded judgment term: checks
   green (pinned integrity), gate verdict clear, dispositions
   complete, change-class allowlisted, hard path exclusions
   untouched; model judgment only inside an earned envelope.
2. Envelopes earned per source-and-class from the journal, and
   revocable; the ledger, journaled verdicts, and the trend detector
   are the existing machinery.
3. Approval is a time-boxed default-open veto window, not an instant
   merge, with a per-source kill switch.
4. The judge is cross-family, commits its assessment before reading
   the review, and may abstain — thresholds calibrated externally,
   aggregation preserving "unclear."
5. Revert gets practiced, not assumed; a landing that cannot be
   cheaply reverted is ineligible for automated approval.
6. Pilot in emcee, last in castle.

## Method note

Two sweeps, ~90 tool calls, both refutation-instructed. One
retraction inside the sweep is preserved deliberately: figures
attributed to an Anthropic agent-autonomy paper by an intermediate
summary do not appear in the source and were withdrawn — numbers
from that paper in secondary sources deserve suspicion. Full sweep
reports live in the session transcripts of 2026-09-10.
