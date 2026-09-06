# The Multi-Agent Primer

*Castle Turing · Research Review · 6 September 2026 · commissioned by
the resident as reader-facing education, not a failure hunt; produced
by a delegated research seat and transcribed verbatim, including its
judgment-calls section, per the library convention that a report is a
claim whose fidelity is part of the record. Produced single-threaded
under the post-incident host constraints (no subagents, no nixpkgs
evaluation, no PDF extraction) — the seat's own trust-discipline
section explains the consequence: every number comes from an
abstract, HTML full text, or vendor documentation, never a paper's
body. Markers: [V] fetched and confirmed by the reporting seat; [R]
recalled or secondhand; [VENDOR] published by a party selling the
thing it measures. The seat flags §3's architecture-to-failure-mode
mapping as its own reasoning over cited facts, not a finding — read
its judgment calls before quoting anything onward.*

---

# Multi-Agent LLM Systems: A Primer

*Castle Turing · research review · 6 September 2026 · produced single-threaded under host constraints (no subagents, no nixpkgs evaluation, no PDF extraction).*

**Trust discipline.** Every substantive claim carries a marker. **[V]** means I fetched the source page myself in this session and confirmed the claim there; where the fetched text was a paraphrase rather than a verbatim quote I say so. **[R]** means recalled, taken from a search snippet, or read secondhand — not confirmed against the source. **[VENDOR]** flags a claim published by a party selling the thing it measures. Where a source is PDF-only I did not extract it and the claim is marked [R] with a note. Read the "Judgment calls" section before quoting anything onward.

**Scope note.** Four topics this project's library already covers are referenced rather than re-researched: state-replacement handoff in the SKILL.state style, Handoff Debt, LLM-judge panel independence and effective-vote-count results (Kohli arXiv:2605.29800, Kim arXiv:2506.07962), and false-success and self-report evidence. Those live in `docs/research/inter-task-handoff.md`, `docs/research/operator-handover.md`, and `docs/research/document-inspection.md`.

---

## 1. The design space

The useful thing to hold onto first is that "multi-agent" is not one architecture. It is a family of ways to spend more inference on a problem by splitting it across separately-prompted LLM contexts. What distinguishes the members of that family is not their org-chart metaphor but three operational questions: **who holds the authoritative state**, **who is permitted to talk to whom**, and **where partial results merge back into one answer**. Ask those three questions of any system described to you as multi-agent and the marketing falls away.

Anthropic's engineering write-up on building effective agents is the cleanest published vocabulary for the shapes, and it is worth reading precisely because it spends most of its length arguing *against* using them [V, https://www.anthropic.com/engineering/building-effective-agents — the page defines prompt chaining, routing, parallelization in sectioning and voting variants, orchestrator-workers, evaluator-optimizer, and autonomous agents, each with a stated "when to use"; [VENDOR]].

### Pipeline, or chain

The simplest shape. Work moves through a fixed sequence of stages, each stage a separate LLM context, each consuming the previous stage's output. State is whatever the previous stage emitted; nobody talks to anybody except their immediate successor; the merge point is trivial because there is only ever one live branch.

The named exemplar is **MetaGPT**, which encodes human standard operating procedures into a prompt sequence and assigns roles along what its authors call an assembly line, explicitly to stop the cascading hallucinations that arise when you naively chain LLM calls without structured intermediate artifacts [V, https://arxiv.org/abs/2308.00352 — fetched abstract; the SOP and assembly-line framing and the cascading-hallucination motivation are the paper's own].

The operational property that matters: a pipeline has no coordination problem at all, because at any moment exactly one agent is running and it holds everything. What it has instead is a **handoff problem** — the fidelity of the artifact passed between stages is the entire architecture. That is the subject of this project's `inter-task-handoff.md`, and it is covered in the project library.

### Orchestrator–worker

A lead context decomposes a task, spawns workers with narrower briefs, and synthesizes their returns. The orchestrator holds the authoritative state; workers hold only their own brief and their own findings; workers do not talk to each other; the merge happens in the orchestrator's context and is itself an LLM operation that can fail.

The named exemplar is **Anthropic's multi-agent research system**, in which a lead agent analyzes the query, develops a strategy, and delegates exploration to subagents that operate in parallel with separate context windows [V, https://www.anthropic.com/engineering/multi-agent-research-system; [VENDOR]]. The same shape is what Claude Code implements: a subagent runs in its own context window with its own system prompt and tools, does not inherit the parent's conversation history or previously-read files, and returns **only its final summary** to the parent [V, https://code.claude.com/docs/en/sub-agents; [VENDOR]]. Subagents may themselves spawn subagents to a default depth of three, and a default of twenty concurrent subagents per session [V, same page].

That "returns only the summary" line is the load-bearing design decision of the whole shape, and it is worth sitting with. It is simultaneously the reason orchestrator–worker scales — the orchestrator's context stays small while total work grows — and the reason it fails, because everything the worker saw and did not summarize is now permanently unavailable to the only agent that can integrate it. Anthropic's context-engineering post frames this as the intended trade: each subagent explores extensively and returns "a condensed, distilled summary of its work (often 1,000-2,000 tokens)" [V, https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents; [VENDOR]]. Compressing an hour of exploration into 1,500 tokens is a lossy channel by construction, and §3 is largely about what falls through it.

### Debate and judge panels

Several contexts answer the same question, see each other's answers, and revise across rounds; or several contexts score one artifact and their scores are pooled. State is replicated rather than held — each debater has its own — and the merge is either a final round of convergence or an external aggregation rule.

The founding exemplar is Du et al., in which multiple language model instances "propose and debate their individual responses and reasoning processes over multiple rounds to arrive at a common final answer," claimed to improve mathematical and strategic reasoning and to reduce hallucination [V, https://arxiv.org/abs/2305.14325 — quoted phrase is from the abstract].

The panel-scoring variant, where the question is how many genuinely independent votes a panel of correlated LLM judges actually contributes, is covered in the project library — the effective-vote-count results in Kohli (arXiv:2605.29800) and Kim (arXiv:2506.07962). The short version relevant here is that debate and panels share a failure mode with each other and not with the other shapes: their value depends on the members being *wrong in different directions*, and identical models with identical prompts are not.

### Blackboard, or shared workspace

There is no message routing. Agents read from and write to a shared structure; participation is opportunistic rather than dispatched. State is the board itself, which is authoritative and singular; "who talks to whom" is replaced by "who is watching the board"; results merge continuously rather than at a synchronization point.

The named exemplar is Salemi et al.'s blackboard system for data-science information discovery, where a central agent posts a request describing what it needs and subordinate agents monitoring the board decide for themselves whether they can contribute, removing the need for a coordinator that knows the full roster in advance. The paper reports 13%–57% relative improvement in end-to-end success and up to 9% relative F1 gain on data discovery over its strongest baselines, on KramaBench and modified DSBench and DA-Code [V, https://arxiv.org/abs/2510.01285 — figures and benchmark names confirmed on the abstract page].

A 2026 variant worth knowing because it bears directly on this project's state-handoff work is **PatchBoard**, which replaces inter-agent dialogue entirely with validated JSON Patch mutations over a shared structured state, with a deterministic kernel checking each proposed mutation against a schema, role-specific write contracts, and runtime invariants before committing transactionally. It reports 84.6% success on 630 matched ALFWorld episodes against 30.8% for LangGraph and 61.6% for Flock, at 45.5k tokens per successful task against 368.3k and 64.2k [V, https://arxiv.org/abs/2605.29313 — abstract page; single-paper result, one benchmark, no replication I found]. The idea — that what travels between agents should be a *validated typed mutation* rather than prose — is the same instinct as SKILL.state, arrived at from the coordination side rather than the dialogue-state side.

### Role-based teams and free-form conversation

Agents are given personas and permitted to converse relatively freely, with turn-taking managed by a chat abstraction rather than a fixed graph. State is the conversation transcript, which everyone sees; everyone can in principle address everyone; the merge is whatever the transcript converges on.

The named exemplar is **AutoGen**, whose core abstraction is the conversable agent and whose interaction patterns are programmed in a mixture of natural language and code [V, https://arxiv.org/abs/2308.08155 — abstract page]. This is the shape with the most demo appeal and, per §3, the worst measured failure profile.

### A note on handoff versus delegation

One distinction is easy to miss and changes the architecture underneath you. In OpenAI's Agents SDK, a *handoff* is exposed to the model as a tool such as `transfer_to_refund_agent`; the receiving agent sees the entire prior conversation history by default, and control does **not** return to the caller. That is different from `Agent.as_tool()`, where a nested specialist is called with structured input and control returns [V, https://openai.github.io/openai-agents-python/handoffs/ — quoted phrase "it's as though the new agent takes over the conversation, and gets to see the entire previous conversation history" is verbatim from the page; [VENDOR]]. A system built from handoffs is a *dynamic pipeline*; a system built from agent-as-tool is *orchestrator–worker*. They look similar in a framework diagram and have opposite state and merge properties.

---

## 2. When multiple agents beat one, and when they don't

### The case for

The strongest published win is Anthropic's: a multi-agent system with Claude Opus 4 as lead and Claude Sonnet 4 as subagents outperformed single-agent Claude Opus 4 by 90.2% on their internal research evaluation, and parallel tool calling cut research time by up to 90% on complex queries [V, https://www.anthropic.com/engineering/multi-agent-research-system; [VENDOR], internal eval, LLM-as-judge rubric supplemented by human review].

Read that number carefully, because the same post supplies the deflation. It states that agents use roughly 4× the tokens of chat interactions and multi-agent systems roughly 15× [V, same page; [VENDOR]], and — this is the important sentence — that on BrowseComp, **token usage alone explains 80% of the variance** in performance [V, same page; [VENDOR]]. Anthropic is telling you, in its own post, that most of what its architecture buys is bought by spending more inference. It further reports that upgrading the model produced a larger gain than doubling the token budget [V, same page; [VENDOR]].

The blackboard result (13%–57% relative end-to-end improvement over RAG and master–slave baselines) and the PatchBoard result (84.6% vs 30.8% and 61.6%) are genuine measured wins for particular multi-agent structures over particular alternatives, both cited above and both single-paper.

There is also an aggregation result: Tian et al. report that multi-turn multi-agent orchestration across Gemini 2.5 Pro, GPT-5, Grok 4 and Claude Sonnet 4 "matches or exceeds the strongest single model and consistently outperforms the others" on GPQA-Diamond, IFEval and MuSR [V, https://arxiv.org/abs/2509.23537 — abstract confirmed; the specific numbers are not on the abstract page and I did not extract the PDF, so the magnitude is [R]]. Note what this one actually shows: the win is over *the average* member, and merely a match against *the best* member. That is the signature of ensembling, not of coordination.

### The case against

**Cognition's argument.** The most cited practitioner objection is Cognition's "Don't Build Multi-Agents." Its two stated principles are "Share context, and share full agent traces, not just individual messages" and "Actions carry implicit decisions, and conflicting decisions carry bad results" [V, https://cognition.com/blog/dont-build-multi-agents — both principles verbatim; [VENDOR], Cognition sells Devin]. Its illustration is the Flappy Bird clone split across subagents, where one subagent renders a Super Mario Bros. background and another builds a bird with the wrong physics, leaving a final agent to reconcile artifacts that were never compatible because the subtask specifications were under-determined [V, same page]. Its recommendation is single-threaded linear agents with continuous context as the default, with a dedicated compression model summarizing history when the context runs long [V, same page].

The argument is better than a vendor position paper has any right to be, and its core is a claim about *information*, not about engineering taste: every action an agent takes encodes decisions it never wrote down, and when two agents act in parallel on the same artifact their unwritten decisions conflict silently.

**The compute-confound result.** The most important paper for a skeptical reader is Tran and Kiela, "Single-Agent LLMs Outperform Multi-Agent Systems on Multi-Hop Reasoning Under Equal Thinking Token Budgets" (arXiv:2604.02460, submitted 2 April 2026). Its abstract states that reported multi-agent gains "are often confounded by increased test-time computation," and that when reasoning tokens are held constant, single-agent systems "consistently match or outperform MAS on multi-hop reasoning tasks" across Qwen3, DeepSeek-R1-Distill-Llama and Gemini 2.5 [V, https://arxiv.org/abs/2604.02460 — quoted phrases verbatim from the abstract; the information-theoretic Data Processing Inequality argument reported in search snippets is [R], as I did not extract the PDF]. This is the paper that makes Anthropic's own "80% of variance is tokens" line into a general finding rather than a footnote.

**Debate specifically does not hold up.** Zhang et al.'s position paper evaluated 5 representative multi-agent debate methods across 9 benchmarks and 4 foundation models and found that debate "often fail[s] to outperform simple single-agent baselines such as Chain-of-Thought and Self-Consistency, even when consuming significantly more inference-time computation," identifying model heterogeneity as the one intervention that consistently helps [V, https://arxiv.org/abs/2502.08788 — quoted phrase and the 5/9/4 counts verbatim from the abstract page]. Becker et al. add a mechanism: **problem drift**, where debates progressively wander from the original question, occurring in 76–89% of generative tasks and 7–21% of reasoning and knowledge tasks, with causes analyzed over 170 debate instances as lack of progress (35%), low-quality feedback (26%), and insufficient clarity (25%); their mitigation policy addresses about 31% of cases [V, https://arxiv.org/abs/2502.19559 — figures confirmed on abstract page].

**Orchestration destroys a whole class of detection.** The finding most specific to this project's interests is Fukui's "A Universal Cliff and a Design Fingerprint" (arXiv:2605.26174, 25 May 2026). Holding documents, defects, mechanism, scoring and seed fixed and varying only the model across ten systems from five providers, it reports that **every model that can find cross-section contradictions under a single agent loses that ability under orchestration, with detection falling two-thirds or more across every paradigm tested** [V, https://www.arxiv.org/abs/2605.26174v1 — full abstract retrieved verbatim]. The abstract further states that the cliff "is mechanism-derived and not closed by scale or extended reasoning"; that at the floor "the model's private record reconstructs the structural fault accurately, while the integrated report signs off on its soundness"; and that "an integrated report's confidence is uninformative about partition-spanning defects" [V, same, all verbatim]. It also reports that trying to measure this with an automated judge failed, at 17–50% precision, and reports that failure as a finding [V, same].

That last point deserves emphasis, because it connects to the false-success and self-report evidence covered in the project library: the orchestrated system does not merely miss the defect, it *files a confident clean report while a worker's own notes contain the correct diagnosis*. The loss is at the merge, not at the worker.

**Some of your agents are doing nothing.** Lu et al. formalize agent attribution with removal protocols and find that leave-one-out identifies bottleneck agents as effectively as full combinatorial methods; substituting cheaper models for low-contribution agents improved task performance by up to 17% while reducing cost by up to 35% across three benchmarks [V, https://arxiv.org/abs/2605.27621 — abstract page]. Two secondary findings from the same abstract are worth carrying: agent contributions to accuracy and to ethical behavior were "often decoupled," and "introspective LLM judges fail to faithfully approximate" what ablation reveals [V, same]. If you want to know which agent matters, delete it and re-run; do not ask the system.

### A decision heuristic

Nothing above supports "multi-agent good" or "multi-agent bad." It supports a fairly specific rule, in four parts.

**First, normalize the compute before you believe any comparison, including your own.** If a multi-agent variant beats a single agent while spending 15× the tokens, you have not learned that the architecture helps; you have learned that spending helps. The single most valuable experiment available to you is running your single-agent baseline at the multi-agent system's token budget.

**Second, split only along genuine independence boundaries.** The pattern in the wins is that subtasks were *separable in the world*: distinct sources to search, distinct data assets to discover, distinct branches to explore. The pattern in the losses is that subtasks were separable only on paper — a Flappy Bird clone is one artifact, and a document's internal consistency is a property of the whole document. Anthropic itself scopes the recommendation this way, naming as unsuitable tasks requiring all agents to share context, domains with many dependencies between agents, and most coding tasks, which have fewer parallelizable components than research [V, https://www.anthropic.com/engineering/multi-agent-research-system; [VENDOR]]. When a vendor's own post excludes your use case, believe the exclusion before the headline number.

**Third, ask what property of the answer is global.** Fukui's cliff is the sharpest available statement of the failure: any correctness property that spans the partition is not merely harder to check under orchestration, it is *structurally* invisible, and the integrated report's confidence will not tell you [V, arXiv:2605.26174]. If the thing you care about is cross-cutting — consistency, coherence, a global invariant, "does this whole document contradict itself" — partitioning is the wrong move regardless of budget.

**Fourth, parallelism for latency is a different purchase from parallelism for quality.** Cutting wall-clock time by fanning out reads is a real and defensible win that does not require the architecture to improve any answer. Keep the two justifications separate, because they have different failure modes and different tests.

---

## 3. How they fail

### The empirical taxonomy

The anchor document is Cemri et al., "Why Do Multi-Agent LLM Systems Fail?" (arXiv:2503.13657). Its opening sentence is itself a finding: "Despite enthusiasm for Multi-Agent LLM Systems (MAS), their performance gains on popular benchmarks are often minimal" [V, https://arxiv.org/abs/2503.13657 — abstract retrieved verbatim].

The method: MAST-Data, 1600+ annotated traces across 7 popular MAS frameworks; the taxonomy itself developed from rigorous analysis of 150 traces with expert human annotators at inter-annotator agreement of kappa = 0.88; models spanning GPT-4, Claude 3, Qwen2.5 and CodeLlama; tasks spanning coding, math and general agent work; plus an LLM-as-judge annotator for scale [V, all from the abstract, verbatim].

The result is 14 failure modes in 3 categories, distributed as follows [V, https://arxiv.org/html/2503.13657v2 — percentages and mode names read from the HTML full text]:

**Specification and system design — 41.77%.** Disobey task specification; disobey role specification; step repetition; loss of conversation history; unaware of termination conditions.

**Inter-agent misalignment — 36.94%.** Conversation reset; fail to ask for clarification; task derailment; information withholding; ignored other agent's input; reasoning–action mismatch.

**Task verification and termination — 21.30%.** Premature termination; no or incomplete verification; incorrect verification.

The headline for a designer is that **roughly four in five failures are organizational rather than about model capability**: specification and misalignment together are 78.7%. These are failures of what you told the agents and what they told each other, not failures of the agents' reasoning in isolation.

### Attribution is much harder than detection

Knowing a run failed is easy; knowing *which agent broke it and when* is not. Zhang et al. built the Who&When dataset from failure logs of 127 LLM multi-agent systems, and found their best automated method achieved **53.5% accuracy at identifying the responsible agent and only 14.2% at pinpointing the decisive error step**, with some methods below random and with o1 and DeepSeek R1 failing to reach practical usability [V, https://arxiv.org/abs/2505.00212 — abstract verbatim, both figures]. Successor systems (AgenTracer, TraceElephant) report gains on that benchmark, including a reported step-level improvement from 17% to 30% with full execution traces [R — from a search snippet only; I did not fetch either paper].

This is a design constraint, not trivia. A multi-agent system is a distributed system whose debugging tools are, as of the best public numbers I could verify, wrong about which component failed roughly half the time and wrong about when it failed roughly six times in seven.

### How the modes map onto the shapes in §1

The taxonomy is architecture-neutral by construction, which makes the mapping mine rather than the paper's — treat this section as reasoning over cited facts, not as a cited fact.

**Pipelines** concentrate risk in the specification category and specifically in loss of conversation history. Each stage sees only what the previous stage wrote, so an omission at stage two is unrecoverable at stage five and there is no other agent positioned to notice. Pipelines are structurally immune to most of the inter-agent misalignment category — there is no concurrent peer to be misaligned with — and pay for that immunity in handoff fidelity, which is the Handoff Debt argument covered in the project library.

**Orchestrator–worker** concentrates risk in two places. The brief downward is a specification problem — the Flappy Bird failure is exactly "disobey task specification" caused by an under-determined delegation [V, Cognition; [VENDOR]] — and the summary upward is an information-withholding problem, structurally guaranteed by the design decision that only the summary returns [V, code.claude.com sub-agents page]. Fukui's cliff is the sharp version of the second: the worker's private record was right and the integrated report was wrong [V, arXiv:2605.26174]. And because the orchestrator is a single context accumulating every worker's return, it is also where task derailment compounds — drift in the orchestrator propagates to every worker downstream.

**Debate and panels** map almost entirely onto task derailment, which is precisely what Becker et al. named problem drift and measured at 76–89% on generative tasks [V, arXiv:2502.19559], and onto incorrect verification when the panel's members share the errors they were supposed to cancel — the correlated-error problem covered in the project library.

**Blackboard** systems trade routing failures for contention and relevance failures. Nobody is unaware of anybody's contribution, which structurally removes "ignored other agent's input"; what replaces it is agents writing conflicting facts onto the same board with no arbitration. PatchBoard's schema, write contracts and runtime invariants are a direct attack on that class, which is why it is interesting beyond its benchmark number [V, arXiv:2605.29313].

**Role-based free-form teams** are exposed to the widest set of modes, because they impose the fewest structural constraints — nothing in a conversational framework prevents step repetition, derailment, premature termination, or two agents each waiting for the other.

Across every shape, the third category — verification and termination, 21.3% — is under-defended in most designs I saw described. No amount of architecture fixes an agent that declares success without checking, and this connects directly to the false-success and self-report evidence in the project library.

---

## 4. Coordination mechanics

### What actually travels

There are three substantive answers, and the choice is more consequential than the topology.

**Prose messages.** The AutoGen default: agents exchange natural-language turns [V, arXiv:2308.08155]. Maximum flexibility, and maximum exposure to the misalignment category, because a prose message has no schema to violate and therefore no violation to detect.

**Full traces.** Cognition's Principle 1 — share full agent traces, not just individual messages [V, cognition.com, verbatim; [VENDOR]] — is the argument that summarization is where the decisions get lost. It is correct about the information and expensive about the tokens, and its own recommended remedy, a dedicated compression model, reintroduces the lossy step it objects to, one layer down.

**Validated structured state.** PatchBoard's JSON Patch mutations against a schema with role-specific write contracts and runtime invariants, committed transactionally by a deterministic kernel [V, arXiv:2605.29313]. This is the direction that converges with this project's SKILL.state line, and the convergence is worth noticing: two literatures — dialogue state tracking on one side, multi-agent coordination on the other — arriving independently at "replace the transcript with a validated typed state object."

Anthropic's context-engineering guidance sits between these: subagent isolation with 1,000–2,000-token distilled returns, compaction when a context nears its limit, and structured note-taking to durable external memory pulled back in later. It names the central risk of compaction plainly — "overly aggressive compaction can result in the loss of subtle but critical context" [V, https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents, verbatim; [VENDOR]].

### Does more communication help?

Not straightforwardly, and the honest answer is that the topology literature is thinner and less replicated than the failure literature.

The clearest scaling result is MacNet (Qian et al.), which organizes agents as directed acyclic graphs, supports collaboration among over a thousand agents, and reports a "collaborative scaling law" in which performance follows logistic growth as agents scale, with collaborative emergence arriving earlier than traditional neural emergence — and, notably, that **irregular topologies outperform regular ones** [V, https://arxiv.org/abs/2406.07155 — quoted phrases from the abstract page]. Logistic growth is the operative detail: it saturates. Adding agents buys progressively less and then nothing.

Zhou et al. treat prompts and topology as jointly optimizable, with a three-stage procedure of local prompt optimization, then topology optimization, then global prompt refinement, arguing that "prompts together with topologies play critical roles" [V, https://arxiv.org/abs/2502.02533, ICLR 2026 — the abstract confirms the framing but supplies **no** numbers separating the two factors' importance; I did not extract the PDF, so any claim about which matters more is unsupported here].

The general centralized-versus-decentralized trade-offs — central node as bottleneck and single point of failure, versus decentralized resilience with redundant-message costs — are standard and reported consistently across recent surveys [R — from search-result summaries of arXiv:2501.06322, arXiv:2502.14321 and MDPI Future Internet 18(6):326; I fetched only the 2502.14321 abstract page]. Nechepurenko and Shuvalov argue the constructive version: coordination "should be treated as a configurable architectural layer, separable from agent logic and from information access," tested across five coordination configurations on 100 Polymarket binary markets resolving after the model's training cutoff, with two configurations dominating the cost-quality Pareto frontier and the authors explicitly framing the work as methodology-validating rather than a general cross-model claim [V, https://arxiv.org/abs/2605.03310 — abstract page; note their own hedge].

The synthesis I would offer, held loosely: topology is a real design variable with saturating returns and no known universally-best shape, and the evidence that *what travels* matters more than *who talks to whom* is stronger than the evidence for any particular graph.

---

## 5. The production reality

**Convergence on the simplest shape.** Deployed systems have largely converged on orchestrator–worker with prose-summary returns, isolated worker contexts, and no worker-to-worker channel. Claude Code implements exactly this and documents both the isolation and the summary-only return [V, code.claude.com sub-agents; [VENDOR]]. Anthropic's research system is the same shape [V; [VENDOR]]. OpenAI's Agents SDK ships handoffs and agent-as-tool as its two primitives [V, openai.github.io; [VENDOR]]. The elaborate topologies in the literature — thousand-agent DAGs, optimized graphs, autonomous swarms — are essentially absent from documented production systems as far as I could verify.

**Numbers circulating without provenance.** Search results returned confident production statistics: orchestrator–worker at "about 70% of production deployments," token overhead of "~58%" for independent and "~285%" for centralized multi-agent setups, and named adopters. I could not trace any of these to a primary source [R — blog-tier only; I am reporting them so you recognize them when you meet them, and recommending you do not repeat them]. Contrast with the vendor figures, which are at least attributable: 4× tokens for agents, 15× for multi-agent [V; [VENDOR]].

**The cost shape.** Two properties are worth internalizing. Cost scales with the *product* of workers and their context, not their sum, because the orchestrator pays again to read every return. And cost is dominated by the orchestrator in long runs, since it is the one context that grows monotonically. The measured lever here is Lu et al.'s: ablate to find low-contribution agents and downgrade their models, reported at up to 17% better performance and up to 35% lower cost [V, arXiv:2605.27621].

**What production failure actually looks like.** The largest field study I found is Tang et al., 20,574 real-world coding-agent sessions across 1,639 repositories, identifying seven recurring forms of developer–agent misalignment. Its most useful numbers: 90.50% of misalignment episodes cost effort and trust rather than causing system damage, 91.49% of visible resolutions still required explicit user correction, and — the trend line that should worry a designer — constraint violations and inaccurate self-reporting **grew as a share** even as overall misalignment declined [V, https://arxiv.org/abs/2605.29442 — abstract page]. The failures that survive improvement are the ones where the agent tells you it did something it did not do.

**Observability.** Named only, per scope, and a companion report covers measurement: you need per-agent trace capture sufficient for the attribution problem in §3, ablation capability rather than introspection because introspective judges do not faithfully approximate ablation [V, arXiv:2605.27621], and independent verification of completion claims rather than self-report [V, arXiv:2605.29442]. The last is reinforced by the false-success evidence in the project library.

---

## 6. Reading list

**Read fully.**

1. **Cemri et al., "Why Do Multi-Agent LLM Systems Fail?" — https://arxiv.org/abs/2503.13657.** The empirical spine of the field: 14 failure modes, 3 categories, 1600+ annotated traces, kappa 0.88. Uniquely, it tells you the *distribution* of failures, which is what turns a taxonomy into a design priority list.

2. **Fukui, "A Universal Cliff and a Design Fingerprint" — https://arxiv.org/abs/2605.26174.** The single most decision-relevant paper for this project: it isolates a class of defect that orchestration destroys the ability to see, shows the loss is structural rather than capability-limited, and shows the integrated report's confidence does not signal it.

3. **Tran and Kiela, "Single-Agent LLMs Outperform Multi-Agent Systems… Under Equal Thinking Token Budgets" — https://arxiv.org/abs/2604.02460.** The methodological corrective: it reframes most published multi-agent wins as unaccounted compute, and it hands you the one experiment you should run before believing your own results.

4. **Anthropic, "Building Effective Agents" — https://www.anthropic.com/engineering/building-effective-agents.** [VENDOR] The cleanest shared vocabulary for the shapes, and a vendor post whose argument is mostly "use the simplest thing that works," which makes its taxonomy more trustworthy than its provenance suggests.

5. **Cognition, "Don't Build Multi-Agents" — https://cognition.com/blog/dont-build-multi-agents.** [VENDOR] The best-argued practitioner objection, and its "actions carry implicit decisions" framing is the most portable idea on this list — it explains parallel-agent failure as an information property rather than an engineering annoyance.

**Read fully, paired.**

6. **Anthropic, "How we built our multi-agent research system" — https://www.anthropic.com/engineering/multi-agent-research-system.** [VENDOR] Read it against item 3. It contains both the strongest claim in the field (90.2%) and the strongest self-deflation (token usage explains 80% of variance), and the tension between them is the whole debate in one document.

**Skim for the idea.**

7. **Zhang et al., "Stop Overvaluing Multi-Agent Debate" — https://arxiv.org/abs/2502.08788.** Skim the setup and the conclusion: debate does not beat Chain-of-Thought or Self-Consistency across 5 methods, 9 benchmarks, 4 models, and heterogeneity is the one thing that helps. That last clause is the reusable insight.

8. **Zhang et al., "Which Agent Causes Task Failures and When?" — https://arxiv.org/abs/2505.00212.** Skim for the two numbers, 53.5% and 14.2%. They tell you what your debugging story is actually worth.

9. **Zhang, Shi and Wang, "PatchBoard" — https://arxiv.org/abs/2605.29313.** Skim the architecture, ignore the benchmark. The idea — validated typed state mutations replacing inter-agent dialogue — is the one that converges with this project's own state-handoff line from an independent direction.

10. **Lu et al., "Agents that Matter" — https://arxiv.org/abs/2605.27621.** Skim for the method: leave-one-out ablation finds bottleneck agents, and introspective LLM judges do not. It is the cheapest diagnostic on this list.

11. **Becker et al., "Stay Focused: Problem Drift in Multi-Agent Debate" — https://arxiv.org/abs/2502.19559.** Skim for the drift rates by task type (76–89% generative versus 7–21% reasoning). It predicts *where* multi-turn coordination will wander before you build it.

12. **Tang et al., "How Coding Agents Fail Their Users" — https://arxiv.org/abs/2605.29442.** Skim for the trend finding: as agents improve, the surviving failures shift toward constraint violation and inaccurate self-reporting. That is the failure mode an oversight design has to be built against.

*Deliberately omitted:* the general surveys (arXiv:2501.06322, arXiv:2502.14321, arXiv:2402.01680). They are competent maps of a field that is being actively falsified, and the falsifications above are a better use of the reader's time.

---

## Judgment calls

**On what "verified" can mean here.** I fetched abstract and documentation pages through a tool that converts a page to markdown and then summarizes it with a small model. Where that tool returned text in quotation marks I have treated it as verbatim and quoted it; where it returned its own paraphrase I marked the claim [V] for *the fact being on the page* but did not present the wording as the source's. This is a weaker [V] than reading a PDF, and the constraint against PDF extraction means **no numbers in this primer come from a paper's body — all come from abstracts, HTML full-text landing pages, or vendor documentation.** That specifically limits arXiv:2509.23537 (the multi-agent-orchestration-wins result, whose magnitudes I could not obtain) and arXiv:2502.02533 (whose prompts-versus-topology comparison I could not obtain and therefore did not claim).

**On the §3 architecture mapping.** MAST is architecture-neutral; the paper does not map its 14 modes onto architectural shapes. That mapping is my reasoning over cited facts and I flagged it as such in place rather than dressing it as a finding. It is the section most likely to be wrong, and the one most worth a second opinion.

**On including the untraceable production numbers.** The brief asked for production reality, and the most-repeated production numbers turned out to be blog-tier with no traceable source. I included them explicitly labeled as untraceable rather than silently dropping them, on the reasoning that the reader will encounter them and is better served by knowing they are unsourced than by their absence. If you would rather the primer carried only sourced numbers, that paragraph is the one to cut.

**On treating debate and judge panels as one shape.** They differ — debate is multi-round with mutual visibility, panels are single-round with external aggregation. I merged them in §1 because they share their decisive property (value depends on member independence) and because the panel half is covered in the project library and I was instructed not to re-research it. A reader designing a panel specifically should treat §1's debate exemplar as not quite theirs.

**On the reading list's exclusions.** The brief asked for 8–12 items in priority order. I ordered by decision-relevance to this project rather than by field importance — which is why Fukui's cross-section paper sits at position 2 above much more-cited work, and why the general surveys are omitted with a stated reason rather than padding the list to 12 with them.

**On what I did not do.** Single-threaded operation and the no-subagent constraint meant serial fetching, so breadth was traded for verification depth. I chose depth: roughly twenty sources fetched first-hand rather than fifty gathered from snippets.

## Dry search angles

These returned nothing usable and are worth knowing so a later session does not repeat them.

- **Multi-agent-specific cost models.** No paper I could find derives token cost as a function of worker count, context growth, and merge depth. The available cost numbers are either vendor multipliers (4×, 15×) or untraceable blog statistics. This is a real gap and looks tractable.
- **Prompts versus topology, quantified.** Searching for a clean statement of which contributes more to multi-agent performance turned up the joint-optimization framing (arXiv:2502.02533) but no separated effect sizes accessible without PDF extraction.
- **Production customer-service fleet retrospectives.** Searches for deployed multi-agent customer-service architectures returned only vendor marketing and listicles. The coding-agent field study (arXiv:2605.29442) is the only large-N production dataset I located for any domain.
- **Replications of the single-paper wins.** I found no independent replication of the blackboard result (arXiv:2510.01285) or PatchBoard (arXiv:2605.29313). Both are cited here as single-paper claims and should be treated that way.
- **MAST successors past the attribution line.** Beyond Who&When, follow-up work (AgenTracer, TraceElephant) appeared only in search snippets and I did not verify it. Whether anyone has re-run MAST's distribution on 2026-generation models is an open question I could not answer.
