# Inter-task Handoff

*Castle Turing · Research Review · 5 September 2026 · commissioned
during the workflow-design conversation of that date; produced by a
delegated research seat and transcribed verbatim, including its
judgment-calls section, per the library convention that a report is a
claim whose fidelity is part of the record. The commissioning session
verified none of the citations independently except SKILL.state
itself, which it had read first-hand. Trust discipline: per-claim
markers — [V] the reporting seat fetched the source (or an
authoritative host) and confirmed the wording or number; [R] recalled
or taken from search snippets only. Vendor-published claims are
additionally marked. Read the judgment-calls section before quoting
anything onward. The single most load-bearing citation in §5 (the
Hill SSRN study) was [R] at transcription; it was verified first-hand
against the resident-supplied paper on 2026-09-06 — see the dated
addendum at the end of this report, which confirms every carried
figure and corrects the transfer-to-this-project reading in four
places. The original §5 text stands unchanged as the record.*

*Companion report: `operator-handover.md`, commissioned the same
night. The vocabulary is deliberate and should stay disciplined:
**handoff** is agent-to-agent (this report); **handover** is
system-to-resident (that one).*

---

# The Textual Interface Between Tasks in a Chain

## Scope note

Everything below is positioned against SKILL.state's architecture (immutable spec `P` + validated mutable JSON state `Σ` + latest observation, traces discarded, O(1) prompt). SKILL.state itself is not re-summarized. Its Semantic Scholar reference list confirms its intellectual lineage is dialogue state tracking, not agent memory: it cites TripPy, SimpleTOD, TRADE, the Schema-Guided Dialogue dataset, and both Dialog State Tracking Challenges, plus ReAct, AutoGen and *Lost in the Middle* — and it cites **none** of the agent-memory literature in Question 1 below [V, https://api.semanticscholar.org/graph/v1/paper/arXiv:2608.26263/references]. That gap is itself a finding: SKILL.state is a dialogue-state-tracking idea transplanted into an agent runtime, and it is unaware of the parallel line of work that arrived at similar conclusions from the memory side.

---

## 1. Replacing accumulated context with explicit structured state

**The strongest independent convergence on SKILL.state's core move is InfiAgent, which reaches the same bounded-context conclusion with the filesystem as the state store rather than a JSON object.** InfiAgent externalizes long-term state into a file-centric representation and has the agent reconstruct context at each step from "a workspace state snapshot plus a fixed window of recent actions," giving bounded context regardless of task duration; a 20B open-source model under this scheme is reported competitive with larger proprietary systems on DeepResearch and an 80-paper literature review, with "substantially higher long-horizon coverage than context-centric baselines" [V, https://arxiv.org/abs/2601.03204]. This is SKILL.state's thesis with a different substrate: a directory of files instead of a validated JSON document. The substrate difference matters for a repo-based SDLC, because a git repository already *is* a file-centric workspace, and the state SKILL.state would put in `Σ` is in a repo naturally distributed across tracked files.

**A second, weaker file-as-context proposal exists but is largely architectural rather than empirical.** "Everything is Context: Agentic File System Abstraction for Context Engineering" adapts the Unix "everything is a file" principle to knowledge, memory, tools and human input via uniform mounting, metadata and access control, and demonstrates it through an agent with persistent memory and a GitHub assistant, but reports no comparative accuracy or token numbers [V, https://arxiv.org/abs/2512.05470]. Treat it as a design vocabulary, not evidence.

**The compaction line of work is the genuine competitor to state replacement, and it now has validated variants that SKILL.state's "discard the trace" position does not address.** Slipstream runs compaction asynchronously, generating a candidate summary and the agent's next steps independently from the same pre-compaction state so that the next steps serve as a validation signal independent of the summary; a judge then checks that the summary "preserves both the agent's forward intent and the key facts and constraints it depends on," yielding up to 8.8 percentage points on SWE-bench Verified and up to 39.7% lower end-to-end latency [V, https://arxiv.org/abs/2605.08580]. Note the criterion it validates against — forward intent plus the facts and constraints that intent depends on — which is a field-level specification of a handoff document arrived at independently of SKILL.state.

**SelfCompact shows that *when* to compact is a separable and learnable decision, and that the tool alone is insufficient.** A compaction tool plus a lightweight rubric (compact when a sub-task resolves or a trajectory converges; suppress during derivation or when stuck) improves math tasks by up to 18.1 points and agentic search by 5–9 points across six benchmarks and seven models, at 30–70% lower per-question cost than fixed-interval summarization; the paper is explicit that "the tool alone is unevenly used across open-weight models, often invoked at unhelpful moments or not at all; the rubric alone cannot act" [V, https://arxiv.org/abs/2606.23525]. This maps onto SKILL.state's own open-model failure mode — open models mishandle *when* to mutate state, and an explicit rubric is a cheap partial fix that requires no fine-tuning.

**StateMem is the closest thing to a direct empirical test of "structure itself helps," and it isolates the contribution.** StateMemBench comprises 234 multi-session scenarios with closed-pool grading that classifies answers as reflecting current state, superseded state, or other failure; StateMem gives 1.8x over the strongest baseline on DeepSeek-V4-Flash (0.205 to 0.363) and 1.6x on Qwen-3.5-9B (0.149 to 0.233), and applied as a wrapper adds +32 to +67 points across six backends, **of which +15 to +32 points are attributable to state structure alone** [V, https://arxiv.org/abs/2608.19652]. That last clause is the single most useful number in this report for justifying a structured handoff over a prose one: roughly half the benefit comes from structure rather than from the retrieval or wrapper machinery around it.

**Classical external-memory systems solve a different problem and should not be cited as precedent for SKILL.state.** MemGPT provides OS-style virtual context management, paging between memory tiers to give the appearance of a larger context [V, https://arxiv.org/abs/2310.08560]; Agent Workflow Memory induces and stores reusable *workflows* from past experience, gaining 24.6% relative on Mind2Web and 51.1% relative on WebArena [V, https://arxiv.org/abs/2409.07429]; A-MEM builds a Zettelkasten-style linked note network where new memories trigger updates to the attributes of existing ones [V, https://arxiv.org/abs/2502.12110]. All three *add* a retrievable store alongside the growing history. SKILL.state *replaces* the history. A-MEM's memory-evolution mechanism is the only one of the three that anticipates the schema question in Section 3.

**Vendor guidance has converged on the same three primitives but supplies no controlled evidence.** Anthropic's context-engineering guidance (vendor claim) recommends compaction that preserves "architectural decisions, unresolved bugs, and implementation details while discarding redundant tool outputs," structured note-taking persisted outside the context window, and sub-agent architectures where a sub-agent may burn tens of thousands of tokens and return only 1,000–2,000 tokens of distilled summary [V, vendor, https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents]. Manus (vendor claim) reports rewriting `todo.md` continuously so as to "recite" objectives into the end of the context across roughly 50 tool calls per task, deliberately leaving failed actions and stack traces in context, and treating the filesystem as restorable compression — dropping content while preserving the reference needed to restore it [V, vendor, https://manus.im/blog/Context-Engineering-for-AI-Agents-Lessons-from-Building-Manus]. Manus's "keep the errors in context" directly contradicts SKILL.state's discarding of reasoning traces; neither side has run the controlled comparison.

**Cognition's position is the sharpest dissent from any state-replacement architecture and deserves to be treated as a live objection rather than a footnote.** Its two stated principles are "share context, and share full agent traces, not just individual messages" and "actions carry implicit decisions, and conflicting decisions carry bad results"; it concedes that long tasks need a compression model that condenses "a history of actions & conversation into key details, events, and decisions," but calls this "hard to get right," requiring a fine-tuned model and real domain expertise, and it recommends defaulting to single-threaded linear agents [V, vendor, https://cognition.com/blog/dont-build-multi-agents]. The objection that matters for a repo-based SDLC is the second principle: a structured state document records the decisions someone thought to write a field for, and the *implicit* decisions — the ones embedded in an action but never named — are exactly what a schema cannot capture in advance.

**Two 2026 surveys frame the field but add no evidence.** "Externalization in LLM Agents" organizes the space into memory, skills, protocols and harness engineering, arguing agents are increasingly built by reorganizing the runtime rather than the weights [V, https://arxiv.org/abs/2604.08224]. "A Survey of Agent Memory in the Second Half" organizes memory along substrate, cognitive mechanism and subject [V, https://arxiv.org/abs/2602.06052]. Neither taxonomy has a slot for "the handoff artifact between two tasks," which is a gap in the literature rather than in the surveys.

---

## 2. What belongs in a minimal inter-task handoff

**The best evidence in this entire review is a controlled ablation showing that a handoff can retain all the *content* and still destroy its *binding force*, and that four specific fields fix it.** "When 'Must' Becomes 'Maybe'" studies safety blockers passed between workflow stages, conditioning on correct upstream identification and varying only the handoff transformation, with an executor restricted to the resulting artifact. Across 1,296 controlled synthetic episodes, direct handoff preserves every blocker, while compression, plan assimilation, convergence, ownership deferral and precedent substitution turn binding state into non-binding caveats: normal handoff compression produces **100.0% deactivation and 54.2% forbidden action**, whereas restoring all four state fields — **prerequisite, authority, fallback, and execution consequence** — raises preservation to 100.0% and drops forbidden action to 0.0% [V, https://arxiv.org/abs/2608.24569]. The paper's own summary of the mechanism is the sentence to carry forward: "Semantic availability does not guarantee operational preservation." A handoff that *mentions* a constraint has not thereby transmitted it.

**A second 2026 paper finds the same asymmetry independently and quantifies how fast it degrades with a token budget.** "Facts Without Rules" shows that summaries "preferentially preserve operational facts while weakening the boundary metadata that governs how those facts may be used," with boundary-marker survival σ_b ≈ 0.80 uncompressed falling to ≈ 0.57 under a 25-word budget; vaguely worded constraints leaked in 73% of GPT cases and 50% of DeepSeek cases, while explicitly worded constraints cut leakage below 15% across all models [V, https://arxiv.org/abs/2608.29028]. Facts and rules survive compression at nearly uncorrelated rates. The practical corollary is that constraints must be written in explicit rather than hedged language, and must be budgeted separately from facts, because a shared budget will spend itself on facts.

**The one study that directly compares handoff artifact *formats* for coding agents finds large efficiency gains from any context-bearing handoff and, importantly, no reliable advantage for structured notes over prose summaries.** "Handoff Debt" interrupts a coding agent at deterministic points, freezes the repository, and evaluates successor agents under four views — repository state only, raw trace, summary notes, and structured notes — across 75 source tasks yielding 181 handoff-point tasks and 724 takeover runs per successor model. Context-bearing handoffs reduce median agent events by 20–59% and cumulative prompt tokens by 42–63% versus repository-only takeover [V, https://arxiv.org/abs/2606.02875]. In the detail: raw trace gives the strongest solved-rate gains (+6.1 to +14.9 points) but carries a median 87k characters, while summary and structured notes are about 10k characters and recover most of the efficiency gain; structured notes reduce agent events 20–46%, and raw trace 57–59%. Structured versus summary on solved rate is a wash — 50.8% versus 51.4% for Qwen-to-Qwen — and note-based gains are not statistically significant at α=0.05 for Qwen and Gemma successors, though significant for Devstral (+9.4 to +10.5 points) [V, https://arxiv.org/html/2606.02875v2].

**That same paper is the only source giving a field list for a structured coding handoff, and it splits the fields by who fills them.** Deterministic fields, auto-populated from logs and metadata: changed source files; non-source artifacts observed; latest validation command and its evidence; a continuation-state label. Model-generated fields, filled by the predecessor: problem understanding; work completed; evidence observed; observed failures; remaining uncertainty; rollback notes; recommended next action. The paper describes this as "a bounded continuation contract rather than a free-form narrative," finds structured notes most valuable at handoff points that carry validation evidence — "where the repository alone cannot convey what the predecessor tested, what failed, and how it responded" — and explicitly reports the failure mode of bounded records, where "structured records leaves validation status unclear, showing the cost of a bounded record when it weakens a crucial clue" [V, https://arxiv.org/html/2606.02875v2]. Its recommendation is that successors treat handoff text "as evidence to verify rather than as ground truth."

**Anthropic's sub-agent delegation guidance names four fields that map cleanly onto the constraint-weakening result, and reports a concrete underspecification failure.** Each sub-agent task description should carry "an objective, an output format, guidance on the tools and sources to use, and clear task boundaries"; without detailed descriptions "agents duplicate work, leave gaps, or fail to find necessary information," illustrated by three sub-agents given "research the semiconductor shortage" where two duplicated 2025 supply-chain work (vendor claim) [V, vendor, https://www.anthropic.com/engineering/multi-agent-research-system]. The mapping is worth stating: objective ≈ prerequisite/goal, task boundaries ≈ authority, output format ≈ the schema the next stage will parse. What Anthropic's list lacks relative to the constraint-weakening four is *execution consequence* — what happens if the constraint is violated — which is exactly the field whose absence turns a "must" into a "maybe."

**Two conceptual papers argue for fields that no empirical work has yet tested.** "Confidence Laundering" defines the failure where "fragile upstream states are repackaged as procedurally valid artifacts that downstream agents over-trust," and argues that a decision handoff needs an attached uncertainty-bearing carrier so downstream components can calibrate; the paper reports no experiments [V, https://arxiv.org/abs/2606.20662]. "Reasoning Provenance for Autonomous AI Agents" argues for normalized, queryable records of why an agent chose each action, what it concluded from each observation, and which evidence supports its verdict [V, https://arxiv.org/abs/2603.21692]. Both are position papers; cite them for the field names, not for evidence that the fields pay off.

**On whether goals or history belong in a handoff, the evidence points at goals plus the *dependency* between a plan and the records it was derived from — not at history.** PlanFence names "stale-plan execution": a planner derives an action from requirement r₃, another agent commits r₄, and the executor receives r₄ without replacing the r₃-derived plan; state freshness alone does not establish that the plan authorizing an action is still valid. Its fix is that "plans cite the exact public records they used," and the executor validates only the records that can affect the pending external action. Across 30 controlled live workflows a freshness-only executor acted on the obsolete plan in *every* task, while PlanFence completed all 30 with no invalid action [V, https://arxiv.org/abs/2609.03340]. For an SDLC this says the implementation brief must cite the specific spec clauses each task derives from, so that a spec revision can be scoped to the tasks it invalidates.

**A theoretical result exists on lossy handoff interfaces, but it is not directly applicable.** "Learning to Hand Off" gives a finite-sample convergence bound for neural Q-learning under decentralized partial observability, decomposing error into function-approximation error, an *interface representation gap* quantifying information loss at the handoff, and a mixing-time residual [V, https://arxiv.org/abs/2605.19140]. The "interface representation gap" is the right concept for what a minimal handoff loses, but the setting is reinforcement learning with one scalar per handoff, not documents.

---

## 3. Schema evolution during the run

**The most direct answer to SKILL.state's admitted failure mode #1 is SCG-MEM, which models schema change with Piagetian assimilation and accommodation and gives a decoding-level guarantee against inventing state keys.** SCG-MEM reformulates memory access as schema-constrained generation, maintaining a dynamic Cognitive Schema and constraining LLM decoding to emit only valid memory keys, which the authors present as "a formal guarantee against structural hallucinations"; updates proceed via "assimilation (grounding inputs into existing schemas) and accommodation (expanding schemas with novel concepts)," with an associative graph for multi-hop activation, evaluated on LoCoMo with improvements "across all categories over retrieval-based baselines" but no numbers in the abstract [V, https://arxiv.org/abs/2604.20117]. Two things transfer to SKILL.state directly: constrained decoding is a stronger mechanism than post-hoc patch validation, because it prevents an invalid key rather than rejecting it after generation; and separating assimilation from accommodation gives an explicit, auditable moment when the schema itself changes.

**The pre-LLM-agent literature on inducing a state schema from scratch is mature and SKILL.state does not cite it, even though it cites the neighboring dialogue-state-tracking work.** GenDSI trains a model to generate slot names and values summarizing key dialogue information "with no prior task knowledge," then clusters the slot-value candidates into unified schemas that align well with human-authored ones, beating prior state of the art on MultiWOZ and SGD [V, https://arxiv.org/abs/2408.01638]. Given that SKILL.state's references include TripPy, TRADE, SimpleTOD and the Schema-Guided Dialogue dataset [V, Semantic Scholar reference list], the omission of slot schema induction is a real gap: the field it borrowed from had already worked on the failure mode it lists as open.

**Two 2026 systems tackle schema-shaped state evolution for agents, one for GUI agents and one as a survey-adjacent proposal, but neither is a clean solution.** HyMEM couples discrete symbolic nodes with continuous trajectory embeddings in a graph, supporting multi-hop retrieval and self-evolution through node update operations plus working-memory refresh during inference [R, https://arxiv.org/abs/2603.10291 — abstract seen only via search snippet, not fetched]. Continuum Memory Architectures specifies architectural requirements for systems that maintain and update internal state through "persistent storage, selective retention, associative routing, temporal chaining, and consolidation into higher-order abstractions," but explicitly declines to disclose implementation specifics and reports only "empirical probes" [V, https://arxiv.org/abs/2601.09913]. The latter is a single-author preprint with no released implementation; treat it as unreliable.

**The adjacent and better-evidenced problem is not schema discovery but knowing when an existing entry is superseded — and this is where open models fail in a way that matches SKILL.state's 68% premature-overwrite finding.** Supersede shows that on LongMemEval's knowledge-update subset, GPT-5.4 with full context reaches 92% while the same model with bounded self-maintained memory reaches 77% (p < 0.005), locating the bottleneck in "memory maintenance, not comprehension"; when conversations expanded 24x, accuracy fell from 68% to 28%, and granting proportionally more memory produced no recovery at all (28% to 28%, n=25). Fine-tuning Qwen2.5-3B with GRPO nearly doubled held-out supersession accuracy from 9.0% to 16.7%, showing the gap is trainable [V, https://arxiv.org/abs/2606.27472]. The "more memory yields no recovery" result is the important one: SKILL.state's premature-overwrite failure will not be fixed by giving `Σ` a larger budget.

**STALE isolates the harder version of the same problem — implicit invalidation with no explicit negation.** STALE is 400 expert-validated conflict scenarios and 1,200 queries across contexts up to 150K tokens, probing State Resolution, Premise Resistance and Implicit Policy Adaptation; it propagates updates through an LLM adjudicator over a *predefined* schema, and its CUPMem prototype strengthens write-time revision through structured state consolidation [R, https://arxiv.org/abs/2605.06527 — details from search snippets, abstract page not fetched]. The predefined-schema caveat is exactly SKILL.state's limitation, restated by a different group.

---

## 4. Context length and multi-step coding agents

**The clearest degradation result for multi-step coding agents measures code quality decay over iterations rather than accuracy versus context length, which is a different and arguably more relevant failure.** SlopCodeBench evaluates 15 coding agents on 36 problems with 196 checkpoints, finding structural erosion rising in 77% of trajectories and verbosity in 75.5%, agent code 2.3x more verbose and 2.0x more eroded than human repositories, the best agent passing only 14.8% of checkpoints, no agent completing any problem end to end, and human codebases degrading less often and by smaller magnitude across version histories; quality guidance interventions reduce initial verbosity and erosion by up to a third [V, https://arxiv.org/abs/2603.24755]. For a repo-based SDLC this reframes the question: the thing that degrades over a long chain is not only the agent's recall but the artifact it is producing, and a checkpointed handoff that re-states quality invariants is a cheap intervention with measured effect.

**Evidence that pruning context *improves* coding-agent success is stronger than evidence that raw length *causes* failure, and the distinction is worth keeping.** SWE-Pruner uses a 0.6B skimmer to select relevant lines given the goal, reporting 23–54% token reduction on SWE-bench Verified *while improving* success rates and up to 14.84x compression on LongCodeQA with minimal performance loss [V, https://arxiv.org/abs/2601.16746]. This is consistent with context length hurting, but it does not isolate length from relevance — the pruner removes irrelevant lines, so what it demonstrates is that irrelevance costs accuracy.

**SWE Context Bench separates those two effects and reports the sign of each.** Across 1,100 base tasks plus 376 related tasks from real GitHub dependencies over 51 repositories and 9 languages, "accurately summarized and retrieved previous experience can significantly improve resolution accuracy and reduce runtime and token cost, particularly on harder tasks," while "unfiltered or incorrectly selected context provides limited or negative benefits" [V, https://arxiv.org/abs/2602.08316]. Prior context is not free: it is positively valued when curated and negatively valued when not, which is precisely the argument for a curated handoff document over a raw trace.

**The evidence is not unanimous, and the dissent should be recorded.** LoCoBench-Agent, an interactive long-context software-engineering benchmark, reports that "agents exhibit remarkable long-context robustness," alongside a comprehension-efficiency trade-off where thorough exploration raises comprehension but reduces efficiency [V, https://arxiv.org/abs/2511.13998]. Anyone arguing from context rot to a bounded-state architecture should expect this counter-citation. My reading is that these are compatible — robustness to *length* is not robustness to *irrelevance* — but that reconciliation is my inference, not a claim either paper makes.

**One frequently repeated concrete number could not be verified and should not be used.** Multiple secondary sources attribute to Sourcegraph a benchmark in which agents given a 100K-token codebase summary performed worse than agents given 5K tokens of targeted retrieval, along with precision@5 rising from 0.140 to 0.478 over a grep baseline and 65% of enterprise agent failures attributed to context drift [R, secondary, https://sourcegraph.com/blog/context-engineering returned HTTP 403 to the fetcher; numbers seen only in search snippets and third-party blogs]. It is also a vendor claim about a vendor's own retrieval product. Do not put it in the library at [V].

**A supporting instrumentation result on where coding-agent context actually goes.** Tokalator, from a structured survey of 50 developers, identifies instruction-file injection and low-relevance open tabs as the two dominant invisible consumers of the context budget, and characterizes conversation cost as growing O(T²) with conversation length [V, https://arxiv.org/abs/2604.08290]. The O(T²) framing is the cost argument for a bounded handoff, independent of any accuracy argument.

---

## 5. Spec-driven artifact chains as inter-task interfaces

**All three named tools pass essentially the same three-document chain, and none of them passes state — they pass intent.** GitHub Spec Kit produces `constitution.md` (project governing principles, established once), then per feature `spec.md` (requirements and user stories), `plan.md` (technical strategy and stack choices), `tasks.md` (actionable task list), then implementation, with a `converge.md` assessing the codebase against spec/plan/tasks and identifying remaining work; supporting commands `/speckit.clarify`, `/speckit.analyze` and `/speckit.checklist` handle underspecification and cross-artifact consistency [V, vendor, https://github.com/github/spec-kit]. AWS Kiro produces `requirements.md` (user stories and acceptance criteria in structured notation), `design.md` (system architecture, sequence diagrams and data flow, error handling and testing strategy), and `tasks.md` (discrete executable tasks with clear outcomes and real-time status) [V, vendor, https://kiro.dev/docs/specs/]; Kiro's use of EARS notation ("WHEN [condition] THE SYSTEM SHALL [behavior]") for requirements is well attested in secondary sources and Kiro's feature-specs page but was not on the page fetched [R, https://kiro.dev/docs/specs/feature-specs/ not fetched]. OpenSpec uses `openspec/changes/<change-name>/` containing `proposal.md` (why and what is changing), `design.md` (technical approach), `tasks.md` (implementation checklist), and `specs/` holding requirements as WHEN/THEN scenarios, archived to `changes/archive/[date]-[name]/` on completion [V, vendor, https://github.com/Fission-AI/OpenSpec].

**Read against Section 2, every one of these chains is missing the fields the ablation says matter.** None of the three has a slot for authority (who may decide what), for execution consequence (what happens if a requirement is violated), for fallback, for remaining uncertainty, or for validation evidence carried forward from the previous phase. Kiro's EARS `WHEN/THEN` encodes a prerequisite and an expected behavior but not a consequence-of-violation; OpenSpec's WHEN/THEN scenarios are the same shape. The constraint-weakening result predicts that a `tasks.md` derived by an LLM from a `spec.md` will retain the requirement's topic while dropping its binding force [V, https://arxiv.org/abs/2608.24569], and nothing in these chains is designed to prevent that.

**The one large-scale independent evaluation of whether spec-driven development delivers on its claims found the opposite of the vendor position.** Brenn Hill's study of 100,247 pull requests across 119 open-source repositories, using SZZ defect tracing and within-author fixed effects, tested five hypotheses drawn from vendor claims and supported none: within-author, specifications were associated with *higher* defect rates (+1.4pp, p = 0.056) and higher rework (+5.0pp, p < 0.001), specification quality had zero effect on rework (p = 0.997), and the authors conclude specification artifacts proxy for task complexity rather than for quality improvement [R, https://papers.ssrn.com/sol3/papers.cfm?abstract_id=6515898 — SSRN returned HTTP 403 to the fetcher; figures consistent across two independent search retrievals of the SSRN abstract page]. This is the most important result in Section 5 and it is the one the reporting seat could not verify first-hand, which is an uncomfortable combination. The within-author design partly addresses the obvious confound (people write specs for harder tasks), so the "proxy for complexity" reading is the authors' own concession rather than an easy dismissal — but the effect sizes are small and the defect-rate result sits at p = 0.056.

**The corpus needed to do better independent evaluation now exists.** SpecMine provides 470,795 `spec.md` files across 73,030 repositories from 17 named tools, plus a Kiro-specific census of 98,574 files with the distinct requirements/design/tasks layout across 12,910 repositories, along with repository metadata, commit histories, parsed document structure, and 5,992 pull requests across 581 repositories linking specifications to code [V, https://arxiv.org/abs/2608.25202]. The abstract frames this as enabling study "for the first time," which is a fair implicit statement that no prior independent evaluation of these artifact chains existed. Note the sample sizes: Spec Kit and OpenSpec adoption is dwarfed by Kiro's, so any evaluation of the *chain* rather than the *presence of a spec* will mostly be an evaluation of Kiro.

**The remaining academic treatment is a literature review, not an evaluation.** "The Productivity-Reliability Paradox" is a multivocal literature review of 67 sources (2022–2026) plus a four-month pilot of two specification-governance instantiations (Spec Kit and TDAD), concluding that "specification discipline, not model capability, is the binding constraint on AI-assisted software dependability" [V, https://arxiv.org/abs/2605.01160]. That conclusion is directly contradicted by the Hill defect study, and the paradox paper's design — a literature review plus an uncontrolled pilot — is much weaker than Hill's. Cite it for the framing, not the verdict.

**Practitioner reports converge on spec drift as the dominant failure of these chains, which is the same failure PlanFence formalizes.** The recurring complaint about OpenSpec is that specs do not self-update during implementation, so an agent that diverges leaves a stale spec that misleads the next agent without flagging anything [R, secondary, https://codemyspec.com/blog/openspec-explained and https://dev.to/willtorber/spec-kit-vs-bmad-vs-openspec-choosing-an-sdd-framework-in-2026-d3j — practitioner blogs, not measured]. Spec Kit's `/speckit.converge` is a vendor response to exactly this [V, vendor, https://github.com/github/spec-kit]. PlanFence's requirement that plans cite the exact records they derive from is the principled version of the same fix [V, https://arxiv.org/abs/2609.03340].

---

## Format: an unresolved tension worth flagging

**Two 2026 results warn that "make it structured" is not uniformly good, and both cut against a heavily schematized handoff document.** "Structure for Reading, Prose for Writing" reports that rendering documents as structural markup rather than flat prose improves extraction, but that converting *instruction* material from prose to XML dropped answer quality from 74% to 48%, with 68% of shortcomings traced to missing source information rather than writing quality; its conclusion is that "structure belongs where the model reads; prose and self-applied tests belong where it writes" [V, https://arxiv.org/abs/2608.20786]. Separately, a 14-model, 8,560-trial replication found natural-language tool descriptions beat structured JSON tool calling by 14.9 points overall (62.3% versus 47.4%) with 93% fewer critical errors, though "heavily optimized frontier models (GPT-5, Gemini 2.5 Pro) show smaller or reversed advantages" while weaker models gain +24.0 to +43.1 points [V, https://arxiv.org/abs/2607.03953]. Taken with Handoff Debt's finding that structured notes did not beat summary notes on solved rate [V, https://arxiv.org/html/2606.02875v2], the honest reading is that structure buys *auditability and completeness checking*, and that the evidence it buys *accuracy* rests mainly on StateMem's +15 to +32 points from state structure alone [V, https://arxiv.org/abs/2608.19652] — a different task family from document handoff.

---

## Design implications

1. Make the handoff a **bounded continuation contract with named fields, not a narrative**, because Handoff Debt found the structured form recovers most of the 20–59% event reduction at roughly 10k characters versus 87k for a raw trace [V, https://arxiv.org/html/2606.02875v2].
2. Carry the four fields that provably preserve binding force — **prerequisite, authority, fallback, execution consequence** — for every constraint the next task must not violate, since restoring all four moved forbidden action from 54.2% to 0.0% [V, https://arxiv.org/abs/2608.24569].
3. **Budget constraints separately from facts and never let compression touch them**, because boundary-marker survival falls from ≈0.80 to ≈0.57 under a shared 25-word budget while facts survive intact [V, https://arxiv.org/abs/2608.29028].
4. **Write constraints in explicit rather than hedged language**, since vague phrasing leaked in 73% of GPT and 50% of DeepSeek cases against under 15% for explicit phrasing [V, https://arxiv.org/abs/2608.29028].
5. **Require each task to cite the specific spec clauses it derives from**, so a spec revision can be scoped to the tasks it invalidates — freshness-only executors acted on obsolete plans in 30 of 30 workflows [V, https://arxiv.org/abs/2609.03340].
6. Include a **validation-evidence field naming the last command run, its output, and what failed**, because that is where structured notes beat the repository alone and where the repository cannot speak for itself [V, https://arxiv.org/html/2606.02875v2].
7. Include a **remaining-uncertainty field**, because handoffs otherwise repackage fragile decisions as procedurally valid artifacts that the next task over-trusts [V, https://arxiv.org/abs/2606.20662], and instruct the next task to treat the handoff as evidence to verify rather than ground truth [V, https://arxiv.org/html/2606.02875v2].
8. **Allow the schema to grow via an explicit, logged accommodation step** rather than fixing it up front, since the assimilation/accommodation split is the only mechanism in the literature that addresses SKILL.state's unknown-schema failure without abandoning validation [V, https://arxiv.org/abs/2604.20117].
9. **Do not expect a larger state budget to fix stale or prematurely overwritten fields** — accuracy stayed flat at 28% when memory was scaled proportionally with a 24x longer conversation — so invest in supersession rules and write-time revision instead [V, https://arxiv.org/abs/2606.27472].
10. **Keep the structure for what the next task reads and keep prose for what it writes**, and do not claim the structure itself buys accuracy in a document handoff, since prose-to-XML conversion of instruction material dropped quality from 74% to 48% [V, https://arxiv.org/abs/2608.20786] and structured notes tied prose summaries on solved rate [V, https://arxiv.org/html/2606.02875v2].

---

## Judgment calls

**I treated the SKILL.state reference list as in-scope even though you told me not to re-research the paper.** Fetching its references is not re-summarizing its contribution, and the absence of any agent-memory citation turned out to be one of the more useful findings. If you consider this a violation of the instruction, discount Section 0's framing paragraph; nothing else depends on it.

**I marked the Brenn Hill SSRN study [R] despite retrieving identical figures twice from independent searches.** SSRN returns HTTP 403 to the fetcher, so I never saw the abstract page myself. The figures are internally consistent and specific, which is weak evidence of fidelity, but your marker discipline says fetched-or-not, and I did not fetch. It is the single most load-bearing citation in Section 5, so this is the defect most worth someone else closing — a browser or an authenticated fetch would settle it in a minute.

**I flagged Sourcegraph's 100K-vs-5K result as unusable rather than including it at [R] with a caveat.** It is both unverified *and* a vendor claim about the vendor's own retrieval product, and it is being laundered through third-party blogs that cite each other. Two independent reasons to distrust it seemed like enough to recommend against putting it in the library at all, which is a stronger action than the instructions asked for.

**I split Question 4's evidence into "length hurts" and "irrelevance hurts" because the papers do not cleanly support the former.** You asked for evidence that context *length* hurts multi-step coding agents beyond context rot. What exists is mostly evidence that *unfiltered* context hurts and that pruning helps, plus LoCoBench-Agent asserting the opposite of length-sensitivity. I chose to report that distinction rather than assemble a one-sided case, and I flagged the reconciliation as my inference rather than a finding.

**I added an unrequested section on structured-versus-prose format.** It was not one of your five questions, but three separate results bear on whether the handoff should be schematized at all, and omitting them would have made the design implications look better supported than they are.

**I did not chase the SKILL.state citation graph past the point of diminishing returns.** Semantic Scholar's citations endpoint returned an empty array [V] and search surfaced only blog commentary, which is expected for a paper posted 26 August 2026 with v3 on 2 September. I treated "nothing cites it yet" as the answer rather than hunting Google Scholar.

**Dry angles, reported as findings.** Semantic Scholar has zero citing papers indexed for SKILL.state [V]. Searching for a study comparing spec→implement handoff artifact contents specifically inside OpenSpec or Spec Kit found nothing academic — SpecMine is a corpus with no evaluation, and the Hill study measures spec *presence*, not artifact-chain design. Searching for ablations on which handoff fields matter found exactly two papers, both from August 2026 and both about *constraints* rather than about goals or decisions-with-reasons; there appears to be no study at all on whether including the *reason* for a decision helps the next task, only position papers arguing it should. `kiro.dev/docs/specs/concepts/` returns 404, and the page fetched does not mention EARS or steering files, so Kiro's EARS usage is [R] here despite being widely reported. No 2026 work was found that competes with SKILL.state on its own terms — bounded state as a *runtime* replacement for history — other than InfiAgent, which arrived first (January 2026) and by a different route.

---

## Addendum, 2026-09-06: the Hill study, read first-hand

*The original report's §5 carried the Hill SSRN study at [R] — its most
load-bearing citation, unverified because SSRN blocks automated
fetching — and its judgment calls named that the defect most worth
closing. The resident downloaded the paper the next morning
(ssrn-6515898, "Does Spec-Driven Development Reduce Defects? An
Empirical Test of Industry Claims Across 119 Open-Source
Repositories," Brenn Hill, Working Paper, April 2026) and this session
read all seventeen pages. The [R] is closed; everything below is [V]
against the paper itself. The original §5 text stands as the record of
what was claimed on secondhand evidence; this addendum is the
correction layer.*

**Every figure the report carried is confirmed.** 100,247 merged PRs,
119 repositories, 11,291 authors; SZZ defect tracing (100 of 119
repos, 64,649 blame links); within-author fixed effects via full
demeaning with clustered standard errors. Five vendor-derived
hypotheses, none supported: within-author, specified PRs show +1.4pp
defect introduction (p = 0.056, from 915 authors with treatment
variation) and +5.0pp rework (p < 0.001, from 1,006); specification
quality on rework is zero to four decimal places (p = 0.997); the AI
scope-constraint claim is null (p = 0.617). Four robustness checks
(alternative outcomes, JIT-feature incremental validity — spec
presence adds ΔPseudo-R² = 0.000014 — individual quality dimensions,
repo-level aggregation) all confirm. The paper's own reading is
confounding by indication: harder tasks get specs and independently
produce more defects, the clinical-medicine pattern by name.

**What the abstract-level reading missed, and it matters for this
project — four things.**

First, **the construct is far broader than SDD-tool artifacts.** A PR
counts as "specified" if it links an issue or tracking ticket,
references a spec/RFC/design doc, or has structured requirements
content in its description — deliberately generous, 8.5% of PRs. A
linked Jira ticket and a refined design document are classified
identically (the paper's own construct-validity section says so). So
the null is about *upfront specification artifacts in general*, mostly
not about disciplined spec chains. The paper anticipates the
objection and tests top-quartile and top-decile LLM-scored specs:
top-quartile shows −2.2pp (p = 0.049) but fails the cleanest
comparison (high-quality vs. no-spec-at-all, p = 0.154), violates
dose-response (top-decile is *weaker*), would not survive correction,
and still *increases* rework. The objection does not rescue the
vendor claims — but it does mean the study is weak evidence about
briefs of this project's kind specifically.

Second, **the cell closest to this project's regime is directionally
favorable and unstable.** AI-tagged PRs with high-quality specs show
−4.8pp bugs (p = 0.044) — from 42 identifying authors. The paper
calls it "the closest test to the agentic SDD workflow vendors are
selling... suggestive but not robust," and its external-validity
section concedes most of the data predates agentic workflows and
"cannot rule out that true agentic workflows — where the agent reads
the spec as its primary input — would produce different results."
That is this project's exact regime, unmeasured.

Third, **the discussion's direction-versus-quality distinction is the
sharpest available statement of what this project's documents are
for.** Verbatim: "SDD vendors conflate two distinct functions:
*directing* the AI (telling it what to build) and *ensuring quality*
... The specification tells the AI *what* to build. It does not tell
the AI *what it forgot to specify*." The five nulls are all about the
quality claim. This project's state layer and briefs are
direction-and-alignment instruments, and its clarifying-questions
phase exists precisely for the forgot-to-specify gap — the one
mechanism Hill identifies as the actual hard part that specs
"merely relocate."

Fourth, **§6.4 independently derives this library's authority/record
split.** The paper argues specifications create value *after* code
ships — audit trail, durable documentation, comprehensibility for
future maintainers — "real benefits, but not the benefits being
sold," and separately flags the untested distinction between
specification-as-input (a structured guess written before code) and
specification-as-output (a record of what was validated). The
same-PR state-patch rule in task 0061 makes this project's state
documents specification-as-output by construction.

**One more convergence worth recording:** Hill traces the "50% error
reduction" figure through its citation chain to a Red Hat blog post
and an InfoQ article containing no study, naming the pattern
"citation laundering" — the same figure, from a different source
paper, that this library's measurement review independently declined
to carry after fetching its citations (see
`measurement-methodology.md`, judgment call 5). Two independent
verification passes, same verdict.

**Standing caveats, the paper's own:** a working paper by an
independent researcher, not peer-reviewed; a convenience sample of
open-source repositories; no multiple-comparison correction across
the five hypotheses (self-flagged: ~0.25 false positives expected at
α = 0.05); SZZ's known attribution limits; AI-tagging by voluntary
co-author tags with unknown false-negative rate.

**Net effect on this report's conclusions:** §5's verdict softens in
one direction only. "The one independent evaluation found no support
for vendor claims" stands, now at [V]. But the transfer to this
project weakens on both edges: the study mostly measured artifacts
looser than this project's briefs, and the one cell resembling this
project's pipeline leans favorable on far too few authors to mean
anything. The honest position: the SDD *quality* claims remain
unsupported; the *direction*, *audit-trail*, and *forgot-to-specify*
functions — the three this project actually builds on — are ones the
study explicitly does not reject, and two of them it argues for.
