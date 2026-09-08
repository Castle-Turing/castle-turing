# The workflow interventions have no outcome measures

**What.** The night of 2026-09-05/06 produced a set of workflow
designs — a current-state layer and milestone document (task 0061
draft), a generated operator handover (task 0062 draft), per-kind
document guidelines with mechanical checkers, review criteria for
prose artifacts — each justified from literature. The resident's
closing question: how do we *measure* any of it? The honest answer is
pieces, not a program. Each design carries its own falsifier (0061:
can the milestone doc alone answer "would the padding tool have been
queued?"; 0062: does the operator catch errors in a golden handover),
and emcee's PR-review brief contains a complete measurement ladder
for the quality gate (disposition capture, seeded-bug benchmark,
revert-rate accounting with a randomized holdout). But nothing
measures whether the interventions *work* — whether direction-as-
artifact actually reduces misdirected work, or the handover actually
reduces operator time without reducing error detection.

**Why it matters.** The literature this all rests on says unmeasured
process discipline decays into ritual (the surgical-checklist
ethnography; SBAR's classroom-to-clinic fidelity collapse), and the
requirements-quality field spent decades writing rules whose
downstream impact was never determined empirically — 30% of its
primary studies report no impact evidence at all. Adopting its
techniques without its measurement failure means inheriting both.

**What is already measurable from the ledgers, with no new
instruments.** The repo's own text is the instrument: share of spend
and merged PRs serving no milestone clause (drift); how often the
resident redirects work after seeing it (misalignment caught late);
rework rate — PRs that amend a prior merge's work; question-routing
latency from a question arising to the resident answering;
per-task cost from the attempt ledger emcee already keeps. Tonight's
ledger is the baseline, and interventions landing one at a time is
what makes before/after readable.

**What needs building.** Seeded-defect probes for documents — plant a
known constraint-deactivation or stale citation in a brief or state
doc and measure whether review catches it (no one has done this for
this artifact class; the pipeline would be running the experiment the
field hasn't) — under exactly Proposal 06's salt discipline:
pre-registered rate and floor, labeled in the journal, never
masquerading as a real record. And the operator-side measures the
handover brief already names: catch rate on planted errors, reliance
behavior rather than felt trust.

**Honest limits.** One resident, no control group: this is
instrumentation plus before/after, not experiments. Where volume
allows, the randomized-holdout shape from the auto-merge plan (a
slice of eligible items still routed to the operator) is the one
clean design that transfers. The n=1 limit is designed-for, not
accepted forever: see
`measurement-is-designed-for-one-resident.md` (2026-09-06) for the
four requirements that keep the multi-installation door open —
versioned public metric definitions, content-free-by-construction
shareable measures, infrastructure facts as first-class variables,
and a pre-registered clustered analysis plan.

**Current consumer:** `docs/state/MILESTONE.md` [m2-constraints]
first clause states this entry's baseline-before-intervention
substance as a binding constraint — revise the two together, and a
brief that finally specs the logging promotes this entry and cites
that clause.

**Where it lands.** A measurement section belongs in each
intervention's brief as it is implemented (0061 and 0062 drafts
already carry falsifiers; the ledger metrics above should be added
when they land), and the milestone document is the natural place for
the drift measures to report against.

**Postscript, 2026-09-06 morning: the methodology review landed and
corrects this entry in four places.** Full report:
`docs/research/measurement-methodology.md`, whose design implications
were written against exactly the measures listed above. The
corrections: (1) redirect rate must never be reported alone — it is a
detection rate, and measured conditional miscorrection rates run
53–94%, so every redirect count needs the fraction of redirects later
judged wrong beside it; (2) the honest power ceiling at this
project's task volume is roughly a twenty-point effect — smaller
intervention decisions are bets, not findings, and should be written
as such; (3) the only single-unit causal design that transfers is an
interrupted time series, which needs task-level outcome logging to
start *now* and a stable pre-period — in direct tension with
milestone two's plan to change the workflow continuously, so the
baseline capture has to precede the interventions or the ITS is
forfeit; (4) off-milestone spend share and question-routing latency
have no literature at all — report them as instrumented observations,
never as validated quality measures, and say so in the documents that
carry them. The seeded-defect design gains a concrete shape: Orchid's
four ambiguity categories as the taxonomy, with an oracle
demonstration that each seed is catchable and hard isolation of the
seed record, per the Agentic Benchmark Checklist.
