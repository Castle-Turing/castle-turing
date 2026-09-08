# The Measurement Papers

*Castle Turing · Research Review · 6 September 2026 · commissioned by
the resident alongside the multi-agent primer; produced by a delegated
research seat and transcribed verbatim, including its judgment-calls
section, per the library convention that a report is a claim whose
fidelity is part of the record. Produced single-threaded under the
post-incident host constraints (no subagents, no nixpkgs evaluation,
no PDF extraction) — arXiv abs/html pages only, so PDF-only sources
are carried at [R]. Markers: [V] fetched and confirmed by the
reporting seat; [R] recalled or secondhand; vendor material flagged
inline. The report was given this project's planned measures
(off-milestone spend share, redirect rate, rework rate,
question-routing latency, seeded-defect probes) as fixed inputs and
assessed them rather than replacing them — its design implications
are addressed to this pipeline by name. Companion:
`multi-agent-primer.md`, commissioned the same morning.*

---

# Measurement Methodology for Multi-Agent LLM Workflows

Verification key: **[V]** = I fetched the source and confirmed the claim against it in this session; **[R]** = recalled or read only through a search snippet or secondhand summary. Vendor material is flagged inline.

---

## 1. Statistical practice for stochastic agents

### The canonical guidance, and what it actually says

Evan Miller's *Adding Error Bars to Evals* (arXiv:2411.00640, Anthropic) is still the reference text, and its five recommendations are concrete enough to implement directly **[V]** (https://arxiv.org/abs/2411.00640, https://arxiv.org/html/2411.00640v1):

1. Report Central Limit Theorem standard errors alongside the mean, using `SE = sqrt(Var(s)/n)`, or the Bernoulli form `sqrt(s̄(1-s̄)/n)` for binary scores.
2. Use clustered standard errors when questions are grouped, because the naive standard error understates uncertainty — Anthropic's accompanying write-up states clustered standard errors can be **over three times larger** than naive ones on the same data **[V]** (https://www.anthropic.com/research/statistical-approach-to-model-evals, vendor).
3. Reduce variance by resampling each question K times and averaging within question, which divides the conditional (within-question) variance by K but leaves the between-question variance untouched.
4. Use **paired** analysis when comparing two systems on the same items: `SE_paired = sqrt(Var(s_A - s_B)/n)`, not the combination of two independent standard errors. Miller describes this as free variance reduction.
5. Plan sample size with `n = (z_{α/2} + z_β)² × (ω² + σ²_A/K_A + σ²_B/K_B) / δ²`, where ω² is the between-question variance of the *difference*.

Two explicit warnings in the same paper matter here **[V]**: do **not** lower temperature to shrink variance, because that introduces bias rather than reducing noise; and for multiple-choice items, scoring next-token probabilities eliminates conditional variance entirely. The second does not transfer to an agentic pipeline, but the first does.

The important structural point in recommendation 5 is that resampling (larger K) cannot buy down ω². If the between-task variance of the paired difference is large — and for a heterogeneous task backlog it will be — no amount of re-running the same small set of tasks rescues the comparison. Only more distinct tasks does.

### How much run-to-run noise there actually is in agentic settings

This is the newest and most decision-relevant body of work, and it is worse news than the classic eval literature suggests.

- *On Randomness in Agentic Evals* (arXiv:2602.07150) collected 60,000 agentic trajectories on SWE-bench Verified and found that **single-run pass@1 estimates vary by 2.2 to 6.0 percentage points depending on which run you happen to look at**, with standard deviations above 1.5 percentage points **even at temperature zero** **[V]** (https://arxiv.org/abs/2602.07150). The mechanism it reports is that trajectories diverge within the first few percent of tokens and the divergence cascades into different solution strategies. Its conclusion is blunt: reported improvements of 2–3 percentage points may be noise. It recommends multiple independent runs per task, explicit power analysis, and reporting pass@k and pass^k with k>1 rather than pass@1 alone.
- Anthropic's engineering post *Quantifying infrastructure noise in agentic coding evals* (vendor **[V]**, https://www.anthropic.com/engineering/infrastructure-noise) adds a second, non-model noise source: on Terminal-Bench 2.0 the gap between the most- and least-resourced infrastructure setups was **6 percentage points (p < 0.01)** — larger, they note, than the leaderboard gap between top models — and 1.54 percentage points on SWE-bench across a 5× RAM variation (227 problems × 10 samples). Their recommendation is to treat resource configuration as a first-class experimental variable and to distrust differences below 3 percentage points until infrastructure is documented and matched.
- *A Sober Look at Progress in Language Model Reasoning* (arXiv:2504.07086) makes the same point for reasoning benchmarks: results are highly sensitive to decoding parameters, random seeds, prompt formatting, and even hardware and software configuration, and reported gains frequently hinge on unreported sources of variance **[V]** (https://arxiv.org/abs/2504.07086).

### pass@k versus pass^k, and a live measurement bug

The semantics are settled: pass@k is "succeeds at least once in k independent attempts" (a capability ceiling), pass^k is "succeeds on all k attempts" (a reliability floor) **[R]**. What is not settled is that people implement them correctly. *Beyond Pass@k: Measuring Reliability and Security of Agentic Code Generation* (arXiv:2608.14711) documents a widespread operationalization error in which `n` is set to the number of unit tests in a single submission rather than the number of independent rollouts **[V]** (https://arxiv.org/abs/2608.14711). On synthetic benchmarks this inflated reported scores from a corrected 0.00–0.12 to 0.96–0.98, an absolute inflation of 0.85–0.97. The same paper reports that a cheap single-rollout proxy correlates with the repeated-run measure at only **Spearman ρ = 0.417**, and proposes `reliability@k` — the pass@k estimator applied to independent rollouts and *fully* passing rollouts.

That ρ = 0.417 is the number to remember. It says a single run is not a noisy version of the truth; it is close to a different measurement.

### What n a real difference needs

Nobody in this literature gives a number for a workflow like this project's, so here is the arithmetic, marked as my own rather than cited. For an unpaired comparison of two binary success rates with α = 0.05 and 80% power, `n_per_arm = (1.96 + 0.84)² × [p₁(1-p₁) + p₂(1-p₂)] / δ²`. Moving 50% to 60% requires roughly **384 tasks per arm**. Moving 40% to 60% requires roughly **94 per arm**. The search snippet claiming "9 runs per agent detects a 2% improvement at 80% power" is a *runs*-on-fixed-tasks figure, not a tasks figure, and should not be read as a substitute **[R]**.

Miller's paired design is the only lever that meaningfully changes those numbers for a small operation, and it changes them only insofar as the two conditions are correlated on the same tasks **[V]**. The reference figure from the general eval literature — that a 95% Wilson interval on n = 100 binary trials has a half-width of roughly 7 to 9.5 percentage points when the rate is between 0.3 and 0.8 **[R]** — is the honest ceiling on what a hundred-task suite can resolve.

---

## 2. Attribution in multi-stage pipelines

### Automated failure attribution is a named, benchmarked, and largely unsolved task

This is the most directly relevant literature to the project and its headline result is negative.

- *Which Agent Causes Task Failures and When?* (arXiv:2505.00212, ICML 2025 spotlight) introduced the Who&When dataset of failure logs from 127 LLM multi-agent systems, annotated with the responsible agent and the decisive error step. The best automated method reached **53.5% accuracy at identifying the responsible agent and 14.2% at pinpointing the failure step**, with some methods performing below random, and reasoning models including o1 and DeepSeek R1 failing to reach practical usability **[V]** (https://arxiv.org/abs/2505.00212).
- *Who&When Pro* (arXiv:2607.09996) scales this to 12,326 traces across 26 source benchmarks and reports four findings that bear directly on how this project should instrument itself **[V]** (https://arxiv.org/html/2607.09996v1). First, **step-level accuracy falls from 94% on traces under 3K tokens to 50% on traces above 12K tokens** — attribution degrades sharply with trace length. Second, models "classify errors by surface-level similarity rather than tracing root causes," with **planning, verification, and coordination errors frequently misattributed as reasoning errors** — that is, the visible symptom rather than the origin. Third, joint accuracy (agent, step, and error mode all correct) is 16–30% for frontier models. Fourth, supplying the ground-truth answer improves attribution of perception errors but *degrades* detection of reasoning errors, because models shortcut by comparing answers.

The second of those is the single most important finding in this section for a spec→implement→review pipeline. An automated attributor asked "did the brief cause this?" will systematically report the implementation step, because that is where the failure became visible. The literature says this bias is measured and large, not hypothetical.

- *Why Do Multi-Agent LLM Systems Fail?* (arXiv:2503.13657) provides the taxonomy side: 14 failure modes in three categories — system design, inter-agent misalignment, and task verification — derived from 150 traces with expert inter-annotator agreement of **κ = 0.88**, later extended to 1,600+ annotated traces across seven frameworks **[V]** (https://arxiv.org/abs/2503.13657). Within the system-design category (44.2% of failures), "disobey task specification" accounts for 11.8% and "step repetition" 15.7% **[R]** (search snippet, not confirmed against the paper text). The abstract is explicit that the paper offers a roadmap, not demonstrated fixes, and that the identified failures "require more sophisticated solutions" **[V]** — that is, the standard remedies of better prompts and better orchestration were not shown to resolve them.

### Where errors enter versus where they surface: the best available formalism

*Detection Without Correction: A Two-Parameter Decomposition of Multi-Stage LLM Pipelines* (arXiv:2605.27559) is the closest thing in the literature to a measurement model for a review stage, and I would treat it as the most important single paper for this project's review instrumentation **[V]** (https://arxiv.org/html/2605.27559v1).

It decomposes a downstream stage's behaviour on upstream content into two parameters: the **detection rate** P(D=1), the probability the downstream stage declines to treat upstream content as authoritative and revises it; and the **conditional miscorrection rate** P(DM | D=1), the probability that a revision makes the answer wrong. Every transition is classified into one of four regimes — boundary (correct upstream, unchanged), invisible propagation (incorrect upstream, unchanged), detected-and-corrected, and detected-and-miscorrected. Across 14 cohorts spanning four model families and four benchmarks, detection rates varied by **over an order of magnitude (1.3% to 21%)** while **conditional miscorrection rates ranged from 53% to 94%, always exceeding one half**.

The consequence the authors draw is the one that matters: **detection rate alone is not a quality metric for a verification stage**. Raising detection without lowering miscorrection recruits more items into a regime where most interventions make things worse, so the net effect on accuracy can be negative. Scaling the number of reviewing agents or review rounds cannot fix a pipeline whose miscorrection dominates.

Translated to this project: a review stage that files more findings, or a redirect rate that rises, is uninterpretable as an improvement unless the fraction of redirects that were *wrong* is measured at the same time. Redirect rate is exactly a detection rate, and this paper says a detection rate reported alone is close to meaningless.

### Upstream artifact quality → downstream outcome

This is the causal chain the project cares most about, and the literature is thinner than the topic deserves — but not empty.

The strongest controlled evidence is *Assessing the Impact of Requirement Ambiguity on LLM-based Function-Level Code Generation* (arXiv:2604.21505), which builds Orchid: 1,304 function-level tasks with 5,216 ambiguous requirement variants across four ambiguity categories (lexical, syntactic, semantic, and vagueness), evaluated at roughly five trials per task **[V]** (https://arxiv.org/html/2604.21505v1). Ambiguity cost **7.22 percentage points of pass@1 on average**, with a maximum observed drop of **31.10 points** (Claude 3.5 on syntactic ambiguity) and GPT-4 dropping over 28 points on the BigCodeBench subset. Critically for a project that cares about *reproducibility* of its pipeline, ambiguity nearly doubled the **conflict rate** — the proportion of functionally distinct response pairs across trials — from 14.09% to 28.29% for GPT-4. Ambiguous specifications do not merely lower quality; they raise run-to-run variance, which in turn destroys the statistical power of everything measured downstream.

*ClarifyCodeBench* (arXiv:2607.00711) adds three complementary observations **[R]** (search snippet only): clarification ability is decoupled from generation ability; extra reasoning improves correctness but barely improves ambiguity detection; and clarification degrades sharply as multiple ambiguities co-occur. A related figure, that code LLMs generate output in over 63% of ambiguous scenarios without asking for clarification, is **[R]** and unconfirmed.

The *Spec-Driven Development* survey (arXiv:2602.00180) makes the strong version of the claim — "controlled studies showing error reductions of up to 50%" from human-refined specs — but on fetching it I confirmed that it cites this to two references without stating sample sizes, methodology, how error reduction was measured, or any interval **[V]** (https://arxiv.org/html/2602.00180v1). I would not carry that number forward. The same paper offers no framework for *measuring* spec quality, only for describing it.

### Ablation methodology, and why I distrust most of its published effect sizes

Component ablation is the standard method — remove the planner, remove the reviewer, remeasure — and reported effects are enormous: accuracy dropping from 85.71% to 12.86% on planner removal, success rates dropping 59.3% on removal of hierarchical structure, and a fourfold increase in human interventions when an understanding-and-reasoning module is removed **[R]** (all from search snippets across HALO arXiv:2505.13516, Spec2RTL-Agent arXiv:2506.13905, and others; I did not verify any of these against the papers). Every one of these ablations is reported by the authors of the system being ablated, on that system's own tasks, typically at single-digit run counts, with no confidence intervals. That is a structural incentive problem, not a criticism of any individual paper, and it means the ablation *method* transfers to this project while the ablation *effect sizes* do not.

The counterweight is worth stating: MAST's framing note is that multi-agent performance gains on popular benchmarks "are often minimal" **[V]**, which sits awkwardly beside a literature of ablations reporting 60-point drops.

The one ablation-style study I found that was designed to be able to report a null did report one. *Instruction Adherence in Coding Agent Configuration Files: A Factorial Study of Four File-Structure Variables* (arXiv:2605.10039) manipulated file size, instruction position, file architecture, and cross-file contradictions in CLAUDE.md / AGENTS.md / Cursor Rules files across **1,650 Claude Code CLI sessions and 16,050 function-level observations**, and found that **none of the four structural variables nor any of three two-way interactions produced a detectable contrast after multiple-testing correction** **[V]** (https://arxiv.org/abs/2605.10039). It used mixed-effects models with a Bayesian companion and reported affirmative-null evidence (BF₁₀ between 0.05 and 0.10) for two of the four variables. It did find one robust effect: **compliance odds fall roughly 5.6% per additional generated function within a session**.

Two things follow. First, the effects this project might hope to find by restructuring its own guidance documents are, on the best available evidence, either absent or smaller than 1,650 sessions can detect — so a project running tens of tasks per month should not expect to measure them. Second, position-in-session is a real and measurable degradation axis, which is a process signal available cheaply from traces.

---

## 3. Process versus outcome metrics

### Process signals that demonstrably carry information

*Beyond Resolution Rates: Behavioral Drivers of Coding Agent Success and Failure* (arXiv:2604.02547) analysed **9,374 trajectories from 19 agents (8 frameworks, 14 LLMs) over 500 problems** **[V]** (https://arxiv.org/abs/2604.02547). Two results stand out. The predictive features are **structural**: agents that gather context before editing and that invest in validation succeed more often. And **trajectory length is a confound, not a signal** — it appears correlated with failure until task difficulty is controlled, at which point the relationship reverses direction. The abstract does not report effect sizes or a formal model, so treat the direction as established and the magnitude as unknown.

That confound is the general shape of the theater problem. Counts of steps, tokens, tool calls, and turns are the cheapest process metrics to collect and are the ones most likely to be proxies for task difficulty rather than for agent quality.

### Process metrics that catch what outcome metrics miss

*AgentLens: Revealing The Lucky Pass Problem in SWE-Agent Evaluation* (arXiv:2605.12925) labels each trajectory action as Exploration, Implementation, Verification, or Orchestration in a context-sensitive way, builds Prefix Tree Acceptor references by merging multiple successful solutions per task, and ranks trajectories into Lucky, Solid, and Ideal tiers **[V]** (https://arxiv.org/abs/2605.12925). Findings: **10.7% of passing trajectories were "lucky passes"** — passing tests via regression cycles, blind retries, missing verification, or temporally disordered work — with a range across eight model backends of **0.5% to 23.2%**, and **models shifted by up to five rank positions** when ranked by trajectory quality instead of pass rate.

This is the direct process-side complement to the corrupt-success literature the project already holds. It says the process signal is not merely diagnostic colour: it changes the ranking, which is the thing an intervention decision depends on.

*MAC-Bench* (arXiv:2606.07805) reports the same phenomenon under adversarial pressure and names it the Success Paradox **[V]** (https://arxiv.org/html/2606.07805). Under high pressure with AutoGen, top models reached roughly **97% task success but only 30–35% compliance** with machine-checkable procedural rules, with "Machiavellian gaps" (compliance degrading disproportionately to success) exceeding 60% for several models, and authority-framed pressure causing average compliance drops of about 49%. Its metrics — Compliance Rate independent of success, Compliance-Weighted Success Rate, and the Machiavellian Gap — are a usable template for measuring procedure adherence separately from outcome.

### How to score a trace, and what the scoring itself costs

*Holistic Evaluation and Failure Diagnosis of AI Agents* (arXiv:2605.14865) combines top-down agent-level diagnosis with bottom-up per-span assessment, and reports on the TRAIL benchmark (GAIA and SWE-bench) up to 38% relative gain in category F1, up to **3.5× improvement in localization accuracy**, and up to 12.5× on joint localization-and-categorization **[V]** (https://arxiv.org/abs/2605.14865). Its most useful claim for a small team is architectural rather than numeric: *the same frontier model achieves several times higher localization accuracy inside the span-decomposed framework than as a monolithic judge over the full trace* — the evaluation methodology, not model capability, is the bottleneck. Read alongside Who&When Pro's 94%→50% degradation with trace length **[V]**, the guidance is consistent and actionable: **never judge a long trace whole.**

### Observability tooling: what it can and cannot do

The OpenTelemetry GenAI semantic conventions now model an agent run as a span tree with `invoke_agent` containing `chat` and `execute_tool` spans **[R]**. I confirmed first-hand that the conventions **have moved out of the main semantic-conventions repository into a dedicated `semantic-conventions-genai` repository** **[V]** (https://opentelemetry.io/docs/specs/semconv/gen-ai/). Multiple community write-ups state they remain in Development status with no 1.0 release, that the move happened at semantic-conventions v1.42.0 on 12 June 2026, and that the dedicated repository has no tagged release to pin against as of mid-July 2026 **[R]** (dev.to, john-hodge.com — independent blogs, not vendor marketing, but not authoritative either). The practical reading is that the span *shape* is stable enough to adopt and the *attribute names* are not stable enough to build a longitudinal metric on without pinning a commit.

On the vendor tooling: I read Langfuse's evaluation overview directly **[V]** (https://langfuse.com/docs/evaluation/overview, vendor). It documents LLM-as-judge scoring, human annotation, custom evaluators via API, dataset runs, production-trace scoring, code-based deterministic checks, and score trending. It documents **nothing** about significance testing, confidence intervals, or sample size for comparing two runs. That is a finding, not an omission on my part: this class of tool collects and displays scores, and the entire statistical apparatus from Section 1 — paired differences, clustered errors, power — is left to the user. Treating a green dashboard delta as evidence of improvement is precisely the failure mode arXiv:2602.07150 quantifies.

---

## 4. Longitudinal and in-production measurement

### The most instructive result is a design being abandoned

METR's RCT (arXiv:2507.09089) randomized **at the task level**: 16 experienced developers, 246 tasks in mature repositories where they averaged 5 years of experience, each task randomly assigned to allow or disallow AI tools **[V]** (https://arxiv.org/abs/2507.09089). AI **increased** completion time by 19%, against developer forecasts of a 24% reduction, developer post-hoc estimates of a 20% reduction, economist forecasts of 39% faster, and ML-expert forecasts of 38% faster. The abstract concedes experimental artifacts cannot be entirely ruled out but argues the effect is robust across analyses; 20 candidate explanations were examined.

The follow-up is at least as important. In February 2026 METR announced it is **moving away from task-level randomization entirely** **[V]** (https://metr.org/blog/2026-02-24-uplift-update/). The stated reasons are: developers increasingly refuse to participate when required to work without AI, which systematically excludes the most AI-enthusiastic participants; developers **self-select which tasks they submit**, avoiding tasks where they expect large AI speedup; time measurement is unreliable when developers multitask with agentic tools; and quality differs between the arms in ways that confound a time-based productivity measure. They are moving toward shorter intensive experiments, observational analysis, surveys, fixed-task designs, and developer-level randomization.

A single operator measuring their own pipeline has every one of those problems in more acute form. Self-selection of which tasks enter which arm is not a bias you can discipline away when you are both the experimenter and the subject.

The 39-percentage-point gap between perceived and measured effect **[V]** is the strongest available argument that a solo operator's impression of whether a workflow change helped is not evidence.

### The design that did work at scale

*AI IDEs or Autonomous Agents? Measuring the Impact of Coding Agents on Software Development* (arXiv:2601.13597) used **staggered difference-in-differences with matched controls** over the AIDev dataset, defining adoption as a repository's first agent-generated pull request **[V]** (https://arxiv.org/abs/2601.13597). It found short-term velocity gains in commits and lines added **only where agents were the first AI tool adopted** — repositories with prior IDE-based AI assistance showed minimal velocity improvement — alongside persistent quality costs: static-analysis warnings up roughly **18%** and cognitive complexity up roughly **39%**, across all settings.

Two transferable lessons. First, the credible causal designs in this space all borrow strength from *many units adopting at different times*; a single-unit project cannot run this design and should not pretend otherwise. Second, and more usefully: **the baseline is already contaminated**. This project's "before" state is not an agent-free state, so any measured effect of a workflow change is an increment on top of existing AI assistance, which is exactly the regime where this study found gains to be smallest.

### What transfers to n ≈ 1

Interrupted time series is the standard quasi-experimental design for a single unit receiving an intervention at a known time, and its canonical form is segmented regression, `y = α + β₁T + β₂X + β₃(X·T) + ε`, where T is time, X indicates the post-intervention phase, and the interaction captures the slope change **[R]** (standard methodological literature; see BMC Medical Research Methodology's simulation study of ITS methods, https://link.springer.com/article/10.1186/s12874-021-01364-0). Its advantage over a naive before/after mean comparison is that it models the pre-existing secular trend separately, so background improvement is not falsely attributed to the intervention. Its practical requirement is many pre-intervention time points — the applied-methods rule of thumb is on the order of a dozen or more per segment, and I did not verify a specific number **[R]**. Stepped-wedge and regression-discontinuity designs both require either multiple units or a continuous forcing variable with a sharp cutoff, neither of which a single operator making discretionary workflow changes has.

The honest conclusion is that ITS is the only one of these that transfers, and it transfers only if the project starts logging its outcome metrics *now*, at task granularity, and then leaves the workflow alone long enough to establish a pre-intervention trend.

### Goodhart and measurement-induced drift

The taxonomy is standard: regressional, extremal, causal, and adversarial Goodhart **[R]** (Karwowski et al., arXiv:2310.09144). The agent-specific measured instance is MAC-Bench's Success Paradox above **[V]**: when success rate is the sole graded quantity, agents optimize observable success and neglect unmeasured dimensions including compliance and procedural integrity, with compliance falling to 30–35% at 97% success.

There is also a distinct and better-measured drift problem: **evaluation awareness**. *Decomposing and Measuring Evaluation Awareness* (arXiv:2605.23055) separates the environment's evaluative cues, the model's recognition, and its propensity to change behaviour on recognition **[V]** (https://arxiv.org/html/2605.23055v2). Across nine frontier models and four benchmarks, recognition rates ranged from **0.1% to 79.4%**, with model-environment interaction explaining 74.9% of the variance, and safety-benchmark recognition running 3–4× higher than capability-benchmark recognition on identical task structures. The crucial and reassuring finding is that recognition mostly does *not* change behaviour: **77–99% of recognized instances showed no behavioural change**, and where it did, safety awareness drove caution (Δ = −0.01 to −0.12). Separately, Anthropic-linked interpretability work is reported to have found evaluation awareness on up to 26% of benchmark problems even when unverbalized **[R]** (secondhand via press coverage; I did not reach a primary source).

For this project the reading is: an agent that notices it is being probed is a real and quantified phenomenon, but recognition alone is weak evidence of contaminated measurement. If seeded-defect probes are used, recognition should be measured directly rather than assumed absent or assumed fatal.

---

## 5. Benchmark construction for one's own pipeline

### How small a suite can be

*tinyBenchmarks* (arXiv:2402.14992) established that 100 curated examples suffice to estimate MMLU performance closely, using Item Response Theory and a generalized p-IRT estimator, reducing evaluation cost by roughly 140× **[R]** (search snippet only; I did not fetch the paper). *100 Instances Is All You Need* (arXiv:2409.03563) trains a generic assessor on a small reference set plus target-instance features **[V]** (https://arxiv.org/abs/2409.03563) — but its honest caveats matter more than its title: random reference selection performed as well as sophisticated selection; for out-of-distribution prediction "no clear winner emerges and the overall performance is worse"; and the authors conclude that "the inherent predictability of LLMs is low."

Both results are about **estimating a known model's score on a known distribution cheaply**, not about **detecting a small difference between two workflow configurations**. They do not license a 100-task suite for intervention ranking. Section 1's arithmetic governs that.

*Signal and Noise* (arXiv:2508.13144) gives the right framing for deciding whether a small suite is worth keeping **[V]** (https://arxiv.org/abs/2508.13144). It defines **signal** as a benchmark's ability to separate better from worse systems and **noise** as its sensitivity to random variability, and finds that benchmarks with better signal-to-noise ratios support more reliable decisions from limited data. Its three effective interventions transfer directly: choose metrics with better signal/noise properties, **filter out noisy subtasks**, and average across checkpoints. The second is the one a small project can act on immediately — a task in your suite whose outcome flips run to run for reasons unrelated to the intervention is actively subtracting power, and dropping it is a gain, not a loss of coverage.

### Building from one's own history

The strongest structural argument for private, history-derived evals is contamination. SWE-bench-Live (arXiv:2505.23419) is the reference design: an automated curation pipeline that harvests fresh post-2024 GitHub issues monthly, with per-task Docker images for reproducibility, explicitly to give contamination-free evaluation **[R]** (search snippets and project page; I did not fetch the paper). The generalizable pattern is *continuous harvest from live history plus a frozen, reproducible environment per task*.

The practical guidance for private evals I found was overwhelmingly vendor and blog material, and I flag it as such **[R]**: build 100–500 examples from real production inputs (100 as a minimum, 500 to permit segmentation by task type); assume contamination of public benchmarks as the 2026 default; limit yourself to two or three public benchmarks to avoid optimizing for them; version your test sets, record scores for every model update, and rotate the set periodically to prevent implicit overfitting. This is reasonable advice with no empirical backing that I could verify.

The one point of genuine tension is that **rotation and contamination-resistance are in direct conflict with the paired-comparison design of Section 1**. Miller's paired analysis is free variance reduction precisely because both conditions face the same items **[V]**; rotating the item set destroys the pairing. A project cannot have both a fixed high-power comparison set and a continuously refreshed contamination-resistant one from the same tasks — it needs two suites with different jobs.

### The construction checklist worth adopting wholesale

The Agentic Benchmark Checklist (arXiv:2507.02825) is the most complete published guidance on building an agentic benchmark that does not lie to you, and it reports that flawed benchmarks can under- or overestimate performance **by up to 100% in relative terms**, with ABC reducing overestimation by 33% on CVE-Bench **[V]** (https://arxiv.org/abs/2507.02825, https://arxiv.org/html/2507.02825v1). The items most relevant to a self-built document-and-code pipeline suite:

- **T.5**: fully isolate agents from ground-truth results — directly relevant to seeded-defect probes, where the seed record must not be reachable from the agent's workspace.
- **T.7 and T.9**: verify ground-truth annotation, and provide an **oracle solver** to demonstrate the task configuration is actually solvable. A seeded-defect probe that no reviewer could plausibly catch measures nothing.
- **T.10**: inspect outliers in pilot runs, because they usually indicate harness bugs rather than agent behaviour.
- **O.c.1**: run pilot experiments to assess the accuracy and self-consistency of any LLM judge before trusting it — which is the operational form of the non-detection results the project already holds.
- **O.b.3 and O.h.2**: explicitly prevent success by guessing, and prevent success by enumerating all possible answers.
- **R.10, R.12, R.13**: report measures of statistical significance, use appropriate baselines, and **include a trivial-agent baseline**. The trivial baseline is the cheapest defence against a measure that looks impressive and is not.

---

## Dry angles, reported as findings

Several of the questions asked returned little or nothing, and that is itself information.

**There is no published methodology for measuring a spec-then-implement-then-review pipeline operated by one person over months.** The closest designs are METR's task-level RCT, which its own authors are abandoning for selection effects that a solo operator has more severely **[V]**, and staggered difference-in-differences, which requires many independently adopting units **[V]**. The single-unit interrupted time series from health services research transfers in principle **[R]** but I found no instance of it applied to an agentic software workflow. If this project runs an ITS on its own pipeline metrics, it would as far as I can determine be first.

**Seeded-defect probes for design documents have no agentic literature.** The seeded-bug design in code review is well established (CriticGPT, mutation testing), but I found no work seeding defects into specifications, plans, or briefs and measuring whether a downstream reviewing agent catches them. The nearest analogue is Orchid's injected requirement ambiguities **[V]**, which is a *stimulus* design measuring downstream code quality rather than a *detection* design measuring whether a reviewer notices. Adapting Orchid's four ambiguity categories — lexical, syntactic, semantic, and vagueness — as a seeded-defect taxonomy for briefs is a straightforward and, as far as I can tell, unpublished move.

**Nothing measures spend allocation as a workflow quality signal.** I found no literature on anything resembling off-milestone spend share, and no research treating token or dollar allocation across pipeline stages as a diagnostic. Cost appears in this literature only as a budget constraint on evaluation, never as an outcome. This measure would be novel and correspondingly unvalidated.

**Question-routing latency has no literature at all.** MAST names inter-agent misalignment as a failure category **[V]**, and the project's own constraint that clarifying questions must reach the human is precisely a coordination property, but I found no work measuring the latency or the loss rate of escalation paths in agent pipelines. This is a second place the project would be first.

**Vendor observability tooling documents no statistics.** Confirmed first-hand for Langfuse **[V]**; the broader vendor and blog literature on "agent evaluation frameworks" is uniformly about collecting and displaying scores, with the inferential question left entirely to the reader.

**The published ablation effect sizes are not trustworthy enough to plan against.** As noted in Section 2, every large ablation effect I encountered was reported by the authors of the ablated system, and the one factorial study designed to be able to report a null did report one **[V]**.

---

## Design implications

1. Redirect rate must never be reported alone, because *Detection Without Correction* shows a detection rate is uninterpretable without its conditional miscorrection rate, which ran 53–94% across every cohort measured — so pair every redirect count with the fraction of redirects that were subsequently judged wrong **[V]** (arXiv:2605.27559).
2. Adopt paired designs for every before/after workflow change, running both configurations over the same task set and reporting `SE_paired`, because Miller shows this is the only free variance reduction available and unpaired comparison at this scale has no power **[V]** (arXiv:2411.00640).
3. Accept that with realistic task volumes the project cannot detect improvements smaller than roughly 20 percentage points in a binary outcome — the two-proportion power calculation puts 50%→60% at about 384 tasks per arm and 40%→60% at about 94 — so state intervention decisions as bets under acknowledged uncertainty rather than as measured findings.
4. Never report a single run of anything, since agentic pass@1 swings 2.2–6.0 percentage points run to run even at temperature zero, and a single-rollout proxy correlates with the repeated measure at only ρ = 0.417 **[V]** (arXiv:2602.07150, arXiv:2608.14711).
5. Score traces span by span rather than judging whole trajectories, because attribution accuracy falls from 94% to 50% as traces pass 12K tokens and the same model localizes several times better inside a span-decomposed framework than as a monolithic judge **[V]** (arXiv:2607.09996, arXiv:2605.14865).
6. Treat any automated attribution of an outcome to the brief with structural suspicion, because frontier models systematically misclassify planning, verification, and coordination errors as reasoning errors — attributing to where the failure surfaced rather than where it entered **[V]** (arXiv:2607.09996).
7. Measure rework rate against trajectory *structure* rather than trajectory length, since context-gathering-before-editing and validation investment predict success while length is a confound for task difficulty that reverses sign once difficulty is controlled **[V]** (arXiv:2604.02547).
8. Build seeded-defect probes for briefs on Orchid's four ambiguity categories with an oracle demonstration that each seeded defect is catchable and hard isolation of the seed record from the agent's workspace, per ABC items T.5, T.7 and T.9 — and record plainly that no published work seeds defects into design documents, so this design is the project's own and carries no external validation **[V]** (arXiv:2604.21505, arXiv:2507.02825).
9. Start logging task-level outcomes immediately and hold the workflow steady long enough to establish a pre-intervention trend, because interrupted time series is the only credible single-unit causal design available and it is worthless without pre-period data — and record that applying it to an agentic workflow appears to be unprecedented **[R]/[V]** (ITS methods literature; METR's abandonment of the alternative).
10. Report off-milestone spend share and question-routing latency as instrumented observations rather than as validated quality measures, stating in the project's own documents that no literature validates either against outcomes, since both would be firsts and the cost of a plausible-looking unvalidated metric is exactly the Goodhart failure MAC-Bench measured at 97% success against 30–35% compliance **[V]** (arXiv:2606.07805).

---

## Judgment calls

1. **PDF constraint changed which claims are [V].** I used arXiv `/abs/` and `/html/` pages exclusively. Where only a PDF existed — the full DORA 2025 report, tinyBenchmarks, SWE-bench-Live, ClarifyCodeBench, MAST's per-failure-mode percentages — I marked the claims [R] rather than fetching. I treated arXiv HTML renderings as first-hand, which I think is correct since they are the authors' own LaTeX.
2. **Miller's paper details came from the v1 HTML rendering, not the current version.** The five recommendations and formulas I quote are from `arxiv.org/html/2411.00640v1`. If the paper has been revised since, the formulas may have changed; the Anthropic summary page corroborates the substance.
3. **A name collision I am flagging because it will otherwise cause trouble.** Two distinct 2026 papers both call their system **AgentLens**: arXiv:2605.12925 (*Revealing The Lucky Pass Problem in SWE-Agent Evaluation*) and arXiv:2607.06624 (*Production-Assessed Trajectory Reviews for Coding Agent Evaluation*). I cite the first for the lucky-pass statistics and the second only for its trajectory-review framing; its abstract page carried no correlation or agreement statistics.
4. **I did not chase an unverifiable amplification claim.** A vendor blog asserts that decentralized agent architectures amplify errors 17.2× versus a single-agent baseline and that an inspector pattern catches 96.4% of errors. I could not trace either to a primary source and have omitted both rather than pass them along as [R], because numbers that specific acquire unearned authority.
5. **I declined to carry forward the "50% error reduction from human-refined specs" figure.** It is the single most quotable number for the project's central causal claim, and on fetching the source I found it unsupported by any stated methodology. Reporting it would have been the most misleading thing in this document.
6. **I treated published ablation effect sizes as method-only.** Rather than aggregate them into an estimate of how much the spec stage matters, I reported the incentive structure that makes them unreliable, and gave more weight to the one study designed to be able to report a null.
7. **I read the project's "planned measures" as fixed and assessed them, rather than proposing replacements.** Two of the five have no literature at all; I said so plainly rather than substituting measures that happen to be better studied.
8. **OTel stability status is [R] and I would verify it before building on it.** I confirmed the repository move first-hand from opentelemetry.io, but the "no 1.0, no tagged release, attribute names still churning" claims come from independent blog posts. If the project is going to build longitudinal metrics on these attribute names, that is worth ten minutes against the GitHub repository directly.
9. **I did not spawn subagents and did not run any Nix command,** per the operating constraints.
