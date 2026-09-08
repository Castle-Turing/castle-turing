# Twelve studies nobody has run

**What.** Six literature reviews commissioned across 2026-09-05/06
(`docs/research/`: inter-task-handoff, operator-handover,
document-inspection, multi-agent-primer, measurement-methodology,
elicitation-papers) each reported its dry angles as findings, and a
pattern emerged: this pipeline's design keeps landing on measurements
with no literature behind them. The resident's direction on
2026-09-06: capture the list, because these are studies someone could
actually run — several of them as a byproduct of this pipeline
operating, some possibly with external research funding. Each entry
below names the study, the report that established the gap, and what
the pipeline contributes.

1. **Seeded defects in design documents, detection measured.** The
   seeded-bug design is standard for code (CriticGPT) and has never
   been run on specs, plans, or briefs. The pipeline's document
   probes are this study. (*document-inspection*, *measurement*.)
2. **Nocuous-ambiguity injection over design briefs.** No
   interpretation-divergence dataset exists at scale (~1,075
   instances worldwide, 200 downloadable, none a design brief);
   Orchid's labelled injections plus ClarifyCodeBench's deletion-only
   operator give the method, and the ground truth does not exist.
   (*elicitation-papers*, its strongest finding.)
3. **An interpretation-divergence dataset built from operation.**
   Every clarifying question asked, answered, and revealed as
   nocuous or innocuous by whether the answer changed the spec is a
   labeled instance; the pipeline's exhaust is the corpus nobody
   has. Semantic entropy over sampled implementations (SpecFix) is
   the annotation-free proxy to validate against.
   (*elicitation-papers*.)
4. **A requirements artifact that carries per-clause ambiguity
   forward.** Every published system resolves, asks, or silently
   commits; none records uncertainty and proceeds. Task 0061's
   stated-versus-inferred convention is this artifact; measuring its
   downstream effect is the study. (*elicitation-papers*.)
5. **Read-back as a human-confirmed exit criterion.** The
   machine-checkable half exists (faithfulness/coverage, Inter2US);
   the human-confirmation half is unstudied. Task 0062's closing act
   is the instrument. (*elicitation-papers*.)
6. **Human tolerance for clarification budgets.** No experiment
   varies question count against abandonment, satisfaction, or
   answer-quality decay; the one adjacent study simulated the
   human's answers. A single-resident version is weak but a
   multi-user version is fundable. (*elicitation-papers*.)
7. **Spend allocation as a workflow quality signal.** Cost appears
   in the literature only as a constraint on evaluation, never as a
   diagnostic; off-milestone spend share is unvalidated anywhere.
   (*measurement-methodology*.)
8. **Question-routing latency and loss in agent pipelines.**
   Escalation paths to the human are a named coordination property
   with zero measurement literature. (*measurement-methodology*.)
9. **Interrupted time series on an agentic workflow.** The only
   single-unit causal design that transfers, apparently never
   applied to one; requires the baseline logging to start before the
   interventions land. (*measurement-methodology*.)
10. **A multi-agent cost model.** No paper derives token cost as a
    function of worker count, context growth, and merge depth; the
    field runs on vendor multipliers and untraceable blog numbers.
    Tractable-looking and purely analytical. (*multi-agent-primer*.)
11. **Evaluation of a shipped clarification phase.** Spec Kit's
    `/clarify` is widely used and documents no budget, no artifact
    contract, no stopping rule, and no evaluation exists.
    (*elicitation-papers*.)
12. **Document-staleness detection.** "This state document was true
    three commits ago" has no measured detector outside the
    code-comment-inconsistency line; the same-PR patch rule makes
    the pipeline's history the labeled data. (*document-inspection*.)

**Why capture them here.** Grounding work in published prior art is
the workflow norm this project is adopting
(`reading-is-commissioned-never-curated.md`); where the prior art is
absent, the honest posture is to say so in the artifact that runs the
experiment anyway — and a list of absences is also a research agenda.
Several entries (1, 3, 4, 5, 9, 12) are generated as a byproduct of
the pipeline operating with its planned instrumentation; the rest
need deliberate design. The measurement review's discipline applies
to all of them: unvalidated measures are reported as instrumented
observations, and single-operator results are bets stated as bets —
publishable versions of most entries need more than one
subject or one repo, which is where external funding would change
what is possible.

**Open questions.** Which entries are worth writing up versus merely
operating; whether the operating-exhaust datasets (3, 12) can be
released given the private-layer boundary — the corpus is the
resident's own briefs and answers, so publication needs the same
scrubbing discipline as everything else; and prioritization, which is
the resident's.
