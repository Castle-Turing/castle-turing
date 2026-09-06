# The Elicitation Papers

*Castle Turing · Research Review · 6 September 2026 · commissioned by
the resident during the workflow-design conversation (the
clarifying-questions phase and, by name, the dataset question);
produced by a delegated research seat and transcribed verbatim,
including its judgment-calls section, per the library convention that
a report is a claim whose fidelity is part of the record. Produced
single-threaded under the post-incident host constraints (no
subagents, no nixpkgs evaluation, no PDF extraction). Markers: [V]
fetched and confirmed by the reporting seat; [R] recalled or
secondhand; vendor material flagged. Dataset hosting pages were
fetched directly (Zenodo, GitHub, Hugging Face) per the commission.
Note the seat's own caveats: it upgraded ClarifyCodeBench from the
[R] this library previously carried after fetching its HTML and
repository; its identification of ReqEval 2020 with this library's
"~200 anaphoric instances" [R] entry is probable but unconfirmed —
reconcile before treating them as one artifact; and several fetched
sources postdate the seat's knowledge cutoff, making those [V]
markers "I read the page," not "I can sanity-check the claim."
Companion reports: `inter-task-handoff.md`, `operator-handover.md`,
`document-inspection.md`, `multi-agent-primer.md`,
`measurement-methodology.md` — all commissioned the same night.*

---

# The clarifying-questions phase: literature dive

## What this changes about the position given

Three things in the brief's given context need updating before the findings make sense. **ClarifyCodeBench can be upgraded from [R] to [V]**: the paper has an arXiv HTML rendering and its dataset is really released, so it should stop being a recalled citation. **Orchid is released** under Apache-2.0 on Hugging Face, which makes it usable as a probe seed today rather than a paper to cite. And **the nocuous-ambiguity construct has a hosted, downloadable descendant** the project library appears not to hold — the ReqEval 2020 shared-task dataset — which is the only corpus I could verify whose ground truth *is* interpretation divergence between annotators.

---

## RQ1. Datasets, exhaustively

### (a) Nocuous ambiguity with interpretation-divergence ground truth

This is the thinnest area in the entire dive, and the operator's suspicion is correct: **no interpretation-divergence dataset exists at anything resembling scale.** The three that exist total well under 1,100 annotated instances between them, and only one of the three has a hosting page I could reach.

**ReqEval 2020 (NLP4RE shared task)** is the one to actually use. [V] I fetched the task page at https://nlp4re.github.io/2020/reqeval.html and it states the construct precisely: 200 sentences across six domains, 102 marked ambiguous, annotated by five annotators with software-engineering or computational-linguistics backgrounds, split two-thirds train and one-third test. The ground-truth rule is the nocuous construct made operational — a sentence is marked nocuous if an ambiguous referential case is acknowledged by at least one annotator *or* if the annotators disagree on the interpretation of that ambiguity. [V] The data is deposited on Zenodo at https://doi.org/10.5281/zenodo.4471411; I fetched record 4471411 and confirmed it is release V2.0 of the ReqEval dataset, a single 21.4 kB archive, license listed as "Other (Open)" with a license file added in this version. The license string is vague enough that I would read the archive's own LICENSE before building anything redistributable on it. This is almost certainly the "~200 anaphoric instances" the project library already holds at [R] grade; it is now located, sized, and hosted.

**DAMIR (Dataset for Anaphoric aMbiguity In Requirements)**, from Ezzini et al.'s ICSE 2022 multi-solution study, is the largest of the three. [R] Per search snippets that I could not corroborate from a fetched primary page: 737 pronoun occurrences drawn from 22 industrial requirements specifications spanning eight domains (satellite communications, medicine, aerospace, security, digitization, automotive, railway, defence), with 342 of 737 (about 46%) judged ambiguous by two trained third-party annotators, and roughly 87% of the ambiguous cases being *unacknowledged* ambiguity — annotators believed the pronoun was unambiguous yet held two different interpretations of it. That last statistic is the single most important number in this section for the project's purposes and it deserves first-hand verification, because if it holds, self-reported confidence about a clause is nearly uncorrelated with whether readers actually agree on it.

**I could not find DAMIR released anywhere.** [V] I fetched the Zenodo deposit the TAPHSIR paper points to (https://zenodo.org/records/5902117) and it contains only the tool: `taphsir.zip` at 390 MB, an installation PDF, a readme PDF, and a license file, with no dataset mentioned. [V] I fetched https://github.com/SNTSVV/taphsir and it likewise contains only trained models under `./artifact/` and a single-sentence `Example.txt`, is licensed AGPL-3.0, and makes no statement at all about dataset availability or industrial confidentiality. Given the corpus is drawn from 22 industrial specifications, the likely explanation is that it cannot be released, but nobody says so. Treat DAMIR as citable, not obtainable, unless someone emails the authors.

**Chantree's coordination corpus** is the original, and it appears unreleased. [R] Search results consistently report 138 coordination instances drawn from requirements documents with associated human interpretation judgements, of which 118 (85.5%) are noun-compound conjunctions. [V] I attempted the Open University repository record at https://oro.open.ac.uk/90165/ and received HTTP 403, and I found no Zenodo, GitHub, or institutional download for the data itself in any search. The ASE 2010 and REJ papers are PDF-only, so I did not extract them per constraints; the size and composition figures stay [R].

**The plain statement the operator asked for:** across all three corpora there are at most roughly 1,075 instances with interpretation-divergence ground truth, only 200 of them are downloadable, all three are restricted to a single narrow ambiguity phenomenon (pronouns and conjunctions), and none of them contains a *design brief* — they are sentence-level requirements fragments. If Castle Turing wants interpretation-divergence data over realistic design briefs, it would be building something that does not exist. That is a genuine "the project would be first" finding, and it is the strongest one in this report.

There is, however, a **cheap synthetic substitute for human divergence annotation** that the project should know about. [V] SpecFix (arXiv:2505.07270, HTML fetched) measures a requirement's ambiguity by sampling many programs from the same prompt, partitioning them into semantic clusters via differential testing, and computing semantic entropy over the clusters — "high semantic entropy implies a high number of different interpretations." This replaces "do two humans read it differently?" with "do two samples of the model implement it differently?", which is exactly the divergence signal the nocuous construct is after, at zero annotation cost. It evaluates on HumanEval+ (164 problems) and MBPP+ (378 problems) and reports a 4.3% pass@1 improvement with substantially reduced semantic entropy across GPT-4o, DeepSeek-V3 and Qwen2.5-Coder. Notably [V] the paper does *not* address asking clarifying questions or carrying ambiguity forward — it repairs the requirement automatically, which is the resolve-by-guess behavior the project wants to avoid. The measurement technique is the transferable part, not the method.

### (b) Ambiguity-injected requirements and code

This category is healthy, and it is where the project's probe seeds should come from.

**Orchid is released.** [V] I fetched both https://arxiv.org/abs/2604.21505 and the dataset card at https://huggingface.co/datasets/SII-YDD/Orchid. The card confirms Apache-2.0, three subsets — Orchid-HEval (164 rows), Orchid-BCB (164 rows), Orchid-BCB-Expand (976 rows), totalling the 1,304 tasks the paper claims — and, critically for probe construction, each row carries the original `prompt` plus four *separate* injected variants with paired explanations: `Lexical_prompt`/`Lexical_ambiguity_explanation`, and the same pairing for `Semantic_`, `Syntactic_` and `Vagueness_`. Rows also carry `solution` and `test_case`. This is the single most directly reusable artifact I found: it is a seeded-ambiguity probe set with the injected defect labelled and a functional oracle attached, under a permissive license.

**ClarifyCodeBench is released under MIT.** [V] I fetched https://arxiv.org/html/2607.00711 and https://github.com/fangz-cs/ClarifyCodeBench. The benchmark is 419 tasks in `data/ClarifyCodeBench.jsonl`, sourced from LiveCodeBench v6 and made ambiguous by *deletion-only editing* — information is removed, never contradicted — with two PhD students independently annotating missing information and building clarification question-answer pairs by cross-checking to consensus. The distribution is 199 single-ambiguity, 169 dual-ambiguity and 51 triple-ambiguity tasks, over a ten-type taxonomy (Terminology, Behavior, Edge Cases, Indices & Ranges, Ordering & Atomicity, Output Format, Comparison Rules, Units, Collection Semantics, Numerical Precision). Note the license split the repo states: MIT for the benchmark, but the underlying problems and test suites remain governed by LiveCodeBench's terms.

**HumanEvalComm** [V] (https://arxiv.org/html/2406.00215, TOSEM 2025; repo at https://github.com/jie-jw-wu/human-eval-comm, mirrored at `jie-jw-wu/HumanEvalComm` on Hugging Face) contains 762 modified problem descriptions derived from HumanEval's 164 problems, perturbed manually along three axes drawn from requirements engineering — ambiguity, inconsistency (test examples contradicting the prose), and incompleteness (roughly 50% of the description removed at random) — with 270 of the 762 being combined perturbations. [V] The repo page states no license explicitly, which is a real obstacle to reuse; the paper is TOSEM but the artifact's terms are unstated.

**Ambig-SWE** [V] (https://arxiv.org/html/2502.13069, accepted ICLR 2026, code and data at https://github.com/sani903/InteractiveSWEAgents, CC BY 4.0) extends SWE-Bench Verified's 500 real GitHub issues with a GPT-4o-generated underspecified variant of each. One caveat the paper reports on itself, which matters for anyone copying the recipe: the synthetic summaries remove code snippets and error messages *more aggressively* than naturally occurring underspecified issues do, so the injected distribution is harsher than reality.

**Ambig-DS** [V] (arXiv:2605.09698, abstract fetched) is small but conceptually the closest to a design brief: 112 tasks split into Ambig-DS-Target (51, from DSBench) and Ambig-DS-Objective (61, from MLE-bench), targeting *task-framing* ambiguity rather than sentence-level ambiguity — which prediction target, which evaluation metric. Its framing of the failure is the one the project should adopt: agents "quietly commit to plausible but unintended task framings, producing clean, executable artifacts that hide their incorrect assessment of the task."

**The general requirements corpora do not carry ambiguity labels, and this is worth stating plainly.** [V] PURE (https://zenodo.org/records/1414117, DOI 10.5281/zenodo.1414117) is 79 public requirements documents and 34,268 sentences, 34 MB, CC-BY-4.0 — genuinely well-licensed and reusable, but the dataset paper itself says it "can be further annotated to work as a benchmark for other tasks, such as ambiguity detection," which is an admission that it is not one. [V] QuRE (arXiv:2508.08868) is 2,111 industrial requirements from Mercedes-Benz specifications annotated through a real five-year industrial review process; the abstract does not disclose the label scheme, and [R] search snippets describe the categories as requirements *smells* — weak words, passive voice, ambiguous references. That distinction is load-bearing for the project: QuRE labels are reviewer-flagged defect candidates, not evidence that two readers understood the clause differently. A smell label answers "did a reviewer dislike this?", not "did it change what got built?", and the project's given 30-59% requirements-smell precision figure is exactly what you would expect from conflating the two. I found no ambiguity-labelled release of Dronology.

### (c) Clarification-question datasets

**ClariQ** [V] (https://github.com/aliannejadi/ClariQ) is the reference point: 187 training topics plus 50 validation topics, classified as 141 faceted, 57 ambiguous and 39 single; 891 facets; 3,929 clarifying questions; roughly 18K single-turn and 1.8M multi-turn conversations. Its most transferable feature is the **clarification-need label on a 1-4 scale**, where 1 is self-contained and needs no clarification and 4 is absolutely ambiguous — a graded need signal rather than a binary one. The README does not state a license; it builds on Qulac and came out of the ConvAI3 challenge.

**AmbigQA / AmbigNQ** [R] (https://huggingface.co/datasets/sewon/ambig_qa, https://nlp.cs.washington.edu/ambigqa) is 14,042 annotations over NQ-open, split 10,036 / 2,002 / 2,004, where each ambiguous question is paired with a set of disambiguated question-answer rewrites, one per interpretation, and over half of dev and test examples carry multiple pairs. I did not fetch the dataset card, so size and license stay [R]. Conceptually this is the closest QA analogue to interpretation divergence, since the rewrites *are* the enumerated interpretations.

**CLAM** [R] is 200 paired ambiguous and unambiguous questions derived from TriviaQA (arXiv:2212.07769). **ClarifyDelphi** [R] released δ-CLARIFY, crowdsourced clarification questions over social and moral situations from Social-Chem-101 and the Commonsense Norm Bank, enriched with GPT-3 generations (arXiv:2212.10409). Both are small and off-domain; I mention them for completeness rather than usefulness.

**CLAMBER** [V] (https://aclanthology.org/2024.acl-long.578/) is 12,000 samples built on a taxonomy of ambiguous information needs — by far the largest clarification benchmark I verified — though the ACL page does not surface a dataset URL.

**AskBench** [V] (https://arxiv.org/html/2602.11199) is 800 multi-turn instances in two halves of 400 (AskMind and AskOverconfidence), sampled from Math500, MedQA, BBH and GPQA-d, and constructed *automatically* from existing datasets via dataset-agnostic prompt templates rather than manual annotation. Its metric design is the part worth stealing: **Coverage**, the fraction of rubric criteria resolved before answering, where a rubric decomposes an incomplete query into itemized missing elements; and **Unq.**, an explicit *redundant-questioning rate* measuring questions asked after all criteria were already satisfied. No public repository URL is stated.

**ClarifyBench** [V] (arXiv:2511.08798) is 716 multi-turn samples across five domains — documents, vehicle control, stocks, travel, file systems — with LLM-based dynamic user simulation and three query types: explicit, ambiguous, and infeasible. The third category is unusual and useful; most benchmarks have no notion of a request that cannot be satisfied however many questions you ask.

**ReqElicitGym / ReqElicitBench** [V] (https://arxiv.org/html/2602.18306, https://github.com/jdm4pku/ReqElicitBench, CC BY 4.0) is the most Castle-Turing-shaped dataset I found: 101 website requirements-elicitation scenarios across 10 application types, with **632 annotated implicit requirements** categorized as interaction, content, or style, and a GPT-5.1-based oracle user validated against real user behavior at Cohen's κ = 0.73. This is a design-brief-shaped elicitation benchmark with per-requirement ground truth, permissively licensed.

**Could these seed nocuous-ambiguity injection probes?** Yes, and the pattern is already established across four independent papers, each using a different injection operator: Orchid injects four labelled ambiguity types into complete prompts; ClarifyCodeBench uses deletion-only editing so nothing is contradicted, only withheld; HumanEvalComm perturbs manually along ambiguity, inconsistency and incompleteness axes; Ambig-SWE summarizes real issues into underspecified ones with an LLM. The project can take Orchid's labelled variants directly for lexical, syntactic, semantic and vagueness probes, and ClarifyCodeBench's deletion-only discipline as the method for seeding its own design briefs — deletion-only is the safer operator because it cannot accidentally create an *inconsistency* while trying to create an ambiguity.

---

## RQ2. When do LLMs ask good clarifying questions?

The measured answer across every benchmark I verified is consistent and unflattering, and it decomposes into a recognition failure and a *behavior* failure that are not the same thing.

**The recognition-behavior gap is the central finding.** [V] "Knowing but Not Showing: LLMs Recognize Ambiguity but Rarely Ask Clarifying Questions" (arXiv:2605.25284, CC-BY-4.0) tests three settings — standard QA, explicit ambiguity judgment, and behavioral classification of responses by a judge — and reports that models "often identify ambiguity when explicitly asked to judge it, yet in the QA setting they overwhelmingly default to direct answers." It also reports a result that should worry anyone building a retrieval-backed brief pipeline: **retrieved context makes this worse**, improving answerability while simultaneously reducing the likelihood of asking for clarification. The abstract does not give the numeric gap, and I did not fetch the HTML body, so the magnitude stays [R] while the direction is [V].

**The under-asking rates.** [V] HumanEvalComm reports that over 60% of responses generate code despite flawed requirements, with pass@1 dropping 35-52% and test pass rate 17-35% under perturbation; incompleteness triggers the most questions yet still yields the worst code. [V] ClarifyCodeBench finds clarification quality low across all six models tested, with turn-discounted key-question rate between 0.07 and 0.30 and optimal-round adherence between 0.13 and 0.50, and — the finding most relevant to a design brief, which is never singly ambiguous — performance "degrades sharply" with multiple ambiguities, with models rarely identifying all required clarifications. [V] CLAMBER concludes LLMs have "limited practical utility in identifying and clarifying ambiguous user queries" and that chain-of-thought and few-shot prompting produce only "marginal enhancements" while potentially inducing overconfidence. [V] ReqElicitGym reports that even top models reach only 0.32 implicit-requirement elicitation ratio, uncovering under a third of what a human analyst would, and "consistently underuse clarification questions."

**Asking behavior varies enormously between models, which means it is not a stable property to build on.** [V] "Ask Early, Ask Late, Ask Right" (arXiv:2605.07937, PwC) ran a natural-ask protocol over 300 TheAgentCompany sessions and found GPT-5.2 asked in 52% of sessions at a mean 43% through the trajectory, Claude Sonnet 4.5 asked in 23% at a mean 50%, and Gemini 3 Flash never asked at all (0%). A phase design that assumes the model will volunteer a question is depending on a model-specific behavior with a 0-to-52% range.

**Detection is easier than asking.** [V] Ambig-SWE reports Claude Sonnet 4 reaching 89% accuracy at distinguishing underspecified from complete tasks when prompted strongly, while most models struggle — and separately reports that interaction recovers up to 74% of the performance lost to underspecification, with models asking between 3.49 and 6.02 questions on average and Claude Sonnet 4 extracting comparable information to Qwen 3 Coder with 50% fewer questions. The gap between 89% detection and the low asking rates above is the recognition-behavior gap measured in a software-engineering setting.

**Reasoning does not fix it.** [V] ClarifyCodeBench finds reasoning models improve code generation under complete requirements but deliver "marginal gains in identifying ambiguities" — clarification is a different capability from reasoning, not a weaker form of it.

**On question quality when questions are asked**, the evidence is more positive. [V] "Curiosity by Design" (arXiv:2507.21285) built a three-stage coding assistant — a DistilBERT intent-clarity classifier at 73% accuracy trained on 4,161 synthetic examples, a fine-tuned Gemma-3-1B-IT question generator, and a code module — and ran a study with 10 undergraduate research assistants over 100 interactions. Users preferred its clarification questions in 68% of pairwise comparisons on precision and focus (mean 3.9/5, p<0.001 across all metrics), and preferred its final answers in 82% of cases for precision/focus and 80% for faithfulness (Cohen's d > 1.2). Two caveats the paper is honest about and that should temper the result: **the users' answers to the clarification questions were simulated by GPT-4o-mini rather than given by the humans**, so this measures perceived question quality and not the cost of answering; and question generation added an average 133 seconds of latency per prompt.

**On user tolerance for being asked, the literature is thin and mostly indirect.** [V] The UAI 2024 paper "On Overcoming Miscalibrated Conversational Priors in LLM-based Chatbots" (arXiv:2406.01633) names the failure mode precisely — chatbots faced with under-specified requests "make incorrect assumptions, hedge with a long response, or refuse to answer" — and attributes it to single-turn annotation practice in fine-tuning, which is a structural explanation rather than a prompting one. But it derives improved policies rather than measuring user tolerance. [R] Search snippets surfaced the argument that "for some users, the marginal improvement in expected utility may not outweigh the cognitive cost associated with having to answer questions," and that when interaction is made cheap agents ask more and achieve higher progress but lower efficiency per question. **I found no study that directly measures human tolerance for a clarification budget** — no experiment varying the number of questions and measuring abandonment, satisfaction, or answer quality degradation over turns. That is a dry angle and I am reporting it as one.

---

## RQ3. Question selection and stopping criteria

This is the best-developed area technically and the most directly transferable, because the field converged on Bayesian experimental design and several papers give explicit, implementable stopping rules.

**Explicit information-gain question selection.** [V] "Active Task Disambiguation with LLMs" (arXiv:2502.04485, Kobalczyk, Astorga, Liu and van der Schaar, ICLR 2025) frames clarification as Bayesian experimental design and makes an argument the project should adopt directly: the gain comes from **shifting the reasoning from the space of questions into the space of solutions**. Instead of asking a model "what is a good question to ask?", you sample multiple candidate solutions consistent with the current brief and then choose the question that best discriminates between them. The paper reports this beats "approaches relying on reasoning solely within the space of questions." That is the same move SpecFix makes for measurement, applied to selection.

**A concrete, trainable information-gain reward with a built-in abstention.** [V] "Uncertainty-Aware Clarification in LLM Agents with Information Gain" (arXiv:2606.03135, code at github.com/Demi-deng2/IG-clarifier) defines the reward for a clarification exchange as the pointwise mutual information between the user's answer and the ground-truth goal, `R_t = log P(G*|x,Q,A) − log P(G*|x)`. The stopping mechanism falls straight out of the reward: the clarifier can emit a "No need to ask" token, which yields exactly zero reward, so a question is only worth asking when its expected information gain exceeds zero net of interaction cost. Trained on 2,676 step-level instances from 500 τ-Bench retail trajectories and evaluated on 115 in-distribution retail and 50 out-of-distribution airline tasks, it delivers a 3.7% average success-rate improvement while adding only 0.3 interaction steps on average, and **the learned clarifier asks 1.2 questions where general-purpose models ask 2.6** — a better than 2× reduction in questions with better outcomes. That ratio is the clearest quantitative evidence that off-the-shelf models over-ask *and* under-target simultaneously.

**A stopping rule with an explicit redundancy penalty.** [V] "Structured Uncertainty guided Clarification for LLM Agents" (arXiv:2511.08798) models the problem as a POMDP over structured beliefs about tool-parameter domains rather than over unstructured text, and selects `q*(t) = argmax_q [EVPI(q, B(t)) − Cost(q,t)]` where the cost term `Cost(q,t) = λ Σ_a n_a(t)` penalizes re-asking about aspects already targeted. Questioning terminates when `max_q [EVPI(q) − Cost(q)] < α · max_i π_i(t)` or the question budget is exhausted — that is, when the best remaining question is worth less than α times the current best hypothesis, which is precisely the "next question worth less than proceeding with stated uncertainty" rule the brief asks about. It reports 7-39% coverage improvement on ambiguous tasks with 1.5-2.7× fewer clarifications, and a GRPO-trained 3B model going from 36.5% to 65.2% on When2Call accuracy. Licensed CC BY-NC-SA 4.0, which is a constraint worth noting if code is reused.

**Timing turns out to matter more than budget, and the profile depends on what is missing.** [V] "Ask Early, Ask Late, Ask Right" uses a forced-injection framework delivering ground-truth clarifications at 10%, 30%, 50%, 70% and 90% of a trajectory across 84 task variants on MCP-Atlas, TheAgentCompany and SWE-Bench Pro, deliberately isolating timing from the agent's ability to detect ambiguity. Its headline is that there is no universal "earlier is better": **goal clarification is extremely front-loaded and loses nearly all its value after 10% of execution** (pass@3 falls from 0.78 to a 0.40 baseline), **input clarification decays gradually and retains value through roughly 50%**, and **constraint clarification shows minimal benefit at any point** because reconciliation costs offset late gains. Timing profiles are task-intrinsic rather than model-dependent (Kendall τ = 0.78-0.87 across models). The cost side is measured as wasted compute — pre-injection actions absent from the oracle trace, rising linearly with delay from 0% to 21.7% on TheAgentCompany — and the paper explicitly does *not* measure latency or interruption penalties. It also finds no sharp point of no return; benefit declines continuously.

**A budget-shaped metric.** [V] ClarifyCodeBench's ORA (Optimal Round Adherence) is a Gaussian-shaped penalty on deviation from an ideal question count, which penalizes under-asking and over-asking symmetrically, and its TKQR uses normalized DCG to reward identifying key questions *early*. Its protocol caps interaction at six rounds with one question per turn. AskBench's Unq. metric measures redundant questions after all rubric criteria are met.

**Other work in the vein I did not verify first-hand:** [R] BED-LLM (arXiv:2508.21184) iteratively maximizes expected information gain using a probabilistic model derived from the LLM's predictive distributions, with robust estimators and sample-then-filter belief updates; CA-BED (arXiv:2606.01182) and an amortised sequential BED paper (arXiv:2607.03426) extend the same framework.

**The dry angle here:** a general search for clarification-specific stopping criteria and diminishing-returns rules returned mostly engineering blog posts and generic multi-turn-reasoning budget papers rather than measured clarification results. The rules above (PMI-with-zero-abstention, EVPI-minus-redundancy, ORA's Gaussian) are the only three principled ones I found, and none has been evaluated on requirements or design briefs — all three were evaluated on tool-calling and QA.

---

## RQ4. The phase's output artifact

**What the 15 LLM4RE elicitation studies produce.** [V] I fetched https://arxiv.org/html/2509.11446v1. Elicitation is 15 of 74 studies (20%), tied with validation as the largest category, in an 11-category taxonomy running elicitation and validation at 20% each, SE tasks 15%, modeling 12%, classification 11%, tracing 7%, documentation 5%, defect detection and legal analysis 4% each, retrieval and terminology extraction 1% each. The review's framing is that this is a **reversal** from the earlier NLP4RE era, which emphasized detection and classification; LLM-era work has moved to the human-intensive front end. The artifacts produced are, per the review: user profiles and personas (4 studies), interview scripts and questionnaires (1 study), requirements specifications (multiple), and regulatory/compliance documents. The gaps it reports are severe for anyone hoping to inherit a validated design: 75% of studies are laboratory experiments with little industry or field validation, 39% do not document how prompts were selected or refined, 38% are zero-shot with RAG at 7% and interactive prompting at only 4%, and **only 16% use public datasets**. There is no measured comparison of elicitation-artifact *forms* in the review — nobody has tested user stories against structured specs against annotated transcripts for downstream outcome.

**The most artifact-relevant primitive I found is grounding, not form.** [V] "Automated Alignment between Elicitation Interviews and Requirements" (arXiv:2510.08622) defines the Inter2US task — matching transcript chunks to user stories — and two metrics that are directly reusable as exit criteria for a clarifying-questions phase. **Requirements faithfulness** is the proportion of user stories supported by at least one transcript chunk, and **interview coverage** is the proportion of transcript chunks covered by at least one story. Evaluated over 17 datasets (15 private student projects plus 2 public), with four manually annotated at roughly 1,283 chunk-story pairs and inter-annotator agreement of only κ = 0.470 — moderate, and the paper notes this shows the task is hard for humans too. LLM judges do best: Qwen3-32B and Llama3.3-70B exceed 0.80 macro-F1 on all datasets, averaging 0.841 and 0.859. Faithfulness stays consistently high across LLM-generated stories while coverage rises monotonically with generator size. The paper is careful to say coverage is *not* completeness, since requirements can legitimately come from outside the interview.

**Traceability from clause back to utterance is the emerging convention.** [R] LENS (arXiv:2606.25867), an industrial preliminary-results paper on discovering latent requirements from stakeholder conversations, represents both extracted and inferred requirements as user stories **linked to transcript excerpts to ensure traceability**, and distinguishes explicitly between requirements the stakeholder stated and requirements the system inferred. That explicit stated-versus-inferred split is the closest thing in the literature to the project's "carry unresolved ambiguity forward" ambition, and I found it only at [R] grade.

**On carrying unresolved ambiguity forward explicitly, the literature is close to silent, and where it speaks it argues the project's position.** [V] Ambig-DS names three response modes and identifies **"silent commitments" as the primary failure mode** — not execution failures, but clean executable artifacts that hide an incorrect reading of the task — and distinguishes agents that explicitly acknowledge ambiguity in reasoning or code from those that implicitly hedge and those that silently proceed. It reports that allowing a single clarifying question recovers much of the loss under idealized conditions, while agents remain bad at knowing when to ask, over-asking on clear tasks and silently defaulting on ambiguous ones. [R] Search snippets from the same cluster put the normative claim plainly: models should "convert awareness of ambiguity into clarification behavior by making uncertainty visible, either by asking clarifying questions or explicitly refusing to answer... rather than silently committing to one assumed interpretation." But **I found no paper that produces, evaluates, or even specifies a requirements artifact carrying per-clause ambiguity annotations forward into implementation.** Every system I verified either resolves the ambiguity (SpecFix, ClarifyGPT), asks about it (all the clarification benchmarks), or measures that the agent failed to (Ambig-DS, ClarifyCodeBench). Nobody writes it down and proceeds. That is the second "project would be first" finding.

**Two adjacent things worth knowing.** [V] SpecBench (arXiv:2605.30314, https://github.com/kevins981/SpecBench) evaluates specification-level reasoning by taking RFCs from Kubernetes, React, Rust, TVM and vLLM and asking agents to predict the specification gaps — omissions, ambiguities, inconsistencies, incorrect assumptions — that expert maintainers later raised in review, scoring core items at twice the weight of extended ones under a bounded prediction budget. The best agent reaches 44.4% and all agents fall below 45%. This is the closest available proxy for "did the phase find the questions a competent human would have asked." And [V] GitHub's Spec Kit (https://github.com/github/spec-kit, MIT) is the industrial precedent: its pipeline is `/speckit.constitution` → `specify` → `clarify` → `plan` → `tasks` → `implement`, where `/speckit.clarify` is described as "Clarify underspecified areas (recommended before `/speckit.plan`; formerly `/quizme`)". This is a **vendor artifact with no published evaluation** — I fetched the repository and confirmed the README documents neither a question count, nor which artifact the answers update, nor any stopping rule. It establishes that the phase exists in shipped tooling and that nobody has measured it.

---

## RQ5. Human elicitation practice that measurably transfers

The operator's wariness about bolting human discovery ritual onto an agentic pipeline is well founded, and the RE literature actually supplies evidence on both sides of it.

**What transfers, with measurement behind it: the mistake taxonomy.** [R] Bano, Zowghi et al., "Teaching requirements elicitation interviews: an empirical study of learning from mistakes" (Requirements Engineering 24(3), 2019) derived **34 unique mistakes in seven high-level themes** — question formulation, question omission, interview order, communication skills, analyst behaviour, customer interaction, and teamwork/planning — from 110 students in 28 groups conducting three interviews each, replicated with 138 students in 34 groups. The replication found students struggled most with question formulation, question omission and interview order, and **did not improve across three interviews**. Two things make this the most transferable item in the RE literature. First, it is a *negative* checklist — a list of specific defects to detect in a generated question — rather than a positive method. Second, the fact that human novices do not improve with practice suggests these are not skills that emerge from experience, which argues for encoding them as an explicit check rather than hoping a model absorbs them.

**That taxonomy has already been ported to an LLM interviewer, with results.** [V] LLMREI (arXiv:2507.02564) ran **33 interviews with real human participants** acting as stakeholders (CS students aged 20-30, ~30 minutes each) across two scenarios — a salon appointment system with 8 ground-truth requirements and a ski resort booking platform with 12. Scored against Bano's five relevant mistake categories, LLMREI "performed comparably to trained human interviewers in reducing common mistakes while achieving significantly better communication skills ratings," and elicited up to 73.7% of requirements (60.94% fully, 12.76% partially). Replication package at https://doi.org/10.5281/zenodo.14988928. The honest reading is that an LLM interviewer is already at rough parity with a trained novice human on the mistakes-avoided axis while leaving a quarter of the requirements on the table.

**What is ceremony, measured.** [V] "How to Elicit Explainability Requirements? A Comparison of Interviews, Focus Groups, and Surveys" (arXiv:2505.23684) ran all three at a German IT consulting firm: two focus groups of 6, 18 interviews, and a survey with 188 valid responses, measuring distinct needs per participant per unit time. Interviews (delayed-taxonomy condition) yielded 133 distinct needs at 14.78 per participant and an efficiency of 0.43; surveys yielded 364 distinct needs but only 1.94 per participant at efficiency 0.17, with 20-22% redundancy; focus groups yielded 27 needs at 4.50 per participant and efficiency 0.10. **Focus groups are the least efficient technique by a factor of four against interviews**, which is a direct measured argument against the group-workshop ceremonies that dominate human discovery practice. But the paper's most important finding cuts the other way too: **only 1-2 explanation needs appeared across all three methods**, meaning each technique surfaces a substantially disjoint set. Coverage is not a property of the best technique; it is a property of using more than one.

**Experience is a weak predictor, which undercuts the "seniority" framing of discovery.** [V] "Effect of Requirements Analyst Experience on Elicitation Effectiveness: A Family of Empirical Studies" (arXiv:2408.12538, TSE 49(4) 2023) ran quasi-experiments with students and professionals using open interviews in familiar and unfamiliar domains. In **unfamiliar domains no type of experience showed significant influence**. In familiar domains the result splits: interview experience has a strong positive effect while **professional experience has a moderate negative effect**. The authors conclude experience does not explain the variance. For an agentic pipeline this is genuinely useful: the thing that helps is domain familiarity plus specific interviewing skill, both of which can be supplied by context and by an explicit question grammar, and general seniority is not what is doing the work.

**Structured beats unstructured for novices.** [R] From search snippets I could not fetch behind paywalls: a structured usability-requirements method (UREM) significantly outperformed unstructured interviews on elicitation effectiveness without reducing analyst efficiency or satisfaction, and novices using structured interviews beat both novices and experienced analysts using unstructured ones, with statistical significance. A separate family of experiments compared Joint Application Design, paper prototyping, and unstructured interviews. A systematic review found unstructured interviews more effective and more complete than introspective, sorting and laddering techniques. All of this is [R]; ScienceDirect and Wiley pages were not fetchable and the arXiv-hosted ones were PDF-only.

**A question grammar exists in the RE literature.** [R] Liaskos et al., "Towards a typology of questions for requirements elicitation interviews" (RE 2021), is a typology of elicitation question types; the only copy I located is a PDF at yorku.ca, so it stays [R] per the PDF constraint. It is worth someone reading it against Proposal-05's grammar, since it is the nearest prior art.

**Prototyping-as-elicitation:** I found paper prototyping only as one arm of the JAD comparison [R] and no measured evidence isolating prototyping's elicitation value in a form I could verify. Dry angle.

---

## Dry angles, reported as findings

Five things I went looking for and did not find, each of which is a gap rather than a search failure.

There is **no measured study of human tolerance for clarification budgets** — nothing varying question count against abandonment or satisfaction. The closest is Curiosity by Design, and it simulated the user's answers.

There is **no artifact in the literature that carries per-clause ambiguity annotations forward into implementation**. Every system resolves, asks, or fails; none records and proceeds.

There is **no measured comparison of elicitation-artifact forms** — user stories versus structured specs versus annotated transcripts — either in the LLM4RE review's 15 elicitation studies or anywhere I searched.

There is **no published evaluation of a shipped clarification phase**. Spec Kit's `/clarify` is MIT-licensed, widely used, and documents no question budget, no artifact contract, and no stopping rule.

**Read-back as an exit criterion is unstudied.** A direct search returned tool-call verification, memory extraction and agent-failure evaluation, none of it about summarizing a requirements understanding back to a human for confirmation. The nearest measurable analogue is Inter2US's faithfulness-and-coverage pair, which is a machine-checkable read-back over a transcript rather than a human-confirmed one.

---

## Judgment calls

I upgraded ClarifyCodeBench from the [R] grade the brief assigned it, because an arXiv HTML rendering exists and the GitHub repository is real; I judged that fetching both was within the constraint against PDF extraction and that leaving a verifiable source at [R] would be worse than the small scope expansion.

I treated the ReqEval 2020 dataset as very probably the "~200 anaphoric instances" the project library holds at [R] grade under the Chantree/Yang heading, since it is 200 sentences with interpretation-divergence ground truth in the same research line. I did not confirm this identification against the project's own notes, so if the library's [R] entry is actually Chantree's 138 coordination instances or Yang's separate anaphoric corpus, the two should be reconciled — they are different artifacts with different availability.

I did not fetch the AmbigQA dataset card despite the brief's instruction to fetch hosting pages for datasets, because AmbigQA is well outside the project's domain and I judged the fetch budget better spent on the software-engineering and requirements datasets. Its figures are marked [R] accordingly.

I stopped chasing DAMIR after three independent negative results (Zenodo deposit, GitHub repo, targeted search) rather than emailing authors or reading the ICSE 2022 PDF, which the constraints forbid. I state the absence rather than the impossibility; the data may exist somewhere I did not look.

Several sources are dated after my May 2026 knowledge cutoff and reference models I have no independent knowledge of (GPT-5.1, GPT-5.2, Gemini 3 Flash, Claude Sonnet 4.5). I fetched and report those pages as written and marked them [V] for "I read this page," but I have no basis to sanity-check their model claims, which is a weaker guarantee than [V] carries elsewhere in this report.

I have flagged Spec Kit as a vendor artifact. I would also flag "Ask Early, Ask Late, Ask Right" as industry-authored (PricewaterhouseCoopers) — the methodology looked sound to me and it reports against its own interest in places, but it is not academically peer-reviewed as far as I could establish.

**A naming collision worth acting on:** ClarifyCodeBench and ReqElicitGym both define a metric named **TKQR (Turn-discounted Key Question Rate)**, and they are not the same metric — ClarifyCodeBench's is normalized-DCG over annotated key questions in a code-generation protocol, ReqElicitGym's sits alongside an implicit-requirement elicitation ratio in an interview protocol. If the project adopts either, it should qualify the name.

---

## Design implications

1. Seed the phase's probe suite from **Orchid's four labelled ambiguity variants** (Apache-2.0, 1,304 tasks with paired explanations and functional oracles) and adopt **ClarifyCodeBench's deletion-only editing** discipline for injecting ambiguity into the project's own design briefs, because deletion cannot accidentally manufacture an inconsistency while aiming for an ambiguity.

2. Measure the requirements state document by **semantic entropy over sampled implementations** rather than by human divergence annotation, following SpecFix, since no interpretation-divergence corpus exists at scale over design briefs and building one would make the project first — an option worth costing, but not a prerequisite.

3. Make the phase's contract "the system may ask, only the human closes" **structurally enforced rather than behaviorally hoped for**, because natural asking rates across frontier models range from 0% to 52% on the same tasks and are therefore not a property to build on.

4. Require every question to cite the clause and ambiguity it resolves, and select among candidate questions by **sampling multiple briefs-consistent interpretations and choosing the question that best discriminates between them** (Active Task Disambiguation's solution-space reasoning), rather than asking a model to propose good questions directly.

5. Implement the stopping rule as **EVPI minus a redundancy penalty against a question budget**, terminating when the best remaining question's net value falls below a fraction of the current best interpretation's weight (arXiv:2511.08798), and give the phase an explicit "no clarification needed" exit that scores zero rather than negative (IG-clarifier) — this is the only place the literature offers a directly implementable rule.

6. Order questions so that **goal-level ambiguities are asked first and constraint-level ones may be deferred or dropped**, since goal clarification loses nearly all value after 10% of a trajectory while constraint clarification shows minimal benefit at any point.

7. Budget the phase toward roughly **one to two well-targeted questions rather than three to six**, since a trained clarifier achieved better outcomes at 1.2 questions where general models needed 2.6, and untrained agents ask 3.49-6.02 — the failure is simultaneously over-asking and under-targeting.

8. Score the phase on both **coverage of seeded ambiguities and a redundant-question rate** (AskBench's Coverage and Unq., ClarifyCodeBench's ORA), because a metric that only rewards asking will produce an interrogation and one that only penalizes asking will reproduce silent commitment.

9. Implement read-back as a **machine-checkable faithfulness-and-coverage pair over the conversation** — every clause in the state document traceable to a human utterance, and every substantive utterance reflected in some clause (Inter2US) — while noting the literature has never evaluated read-back as a human-confirmed exit criterion, so the human-confirmation half is territory the project would be first into.

10. Carry unresolved ambiguity forward as **explicitly tagged clauses distinguishing stated from inferred content**, accepting that no published system does this — Ambig-DS names silent commitment as the primary agent failure mode and LENS links stories to transcript excerpts, but nobody writes ambiguity down and proceeds, so this is the project's clearest opportunity to be first and its clearest obligation to measure rather than assume.

---

## Addendum, 2026-09-06: TR2005/03 read first-hand

*The resident supplied Chantree, Nuseibeh, De Roeck and Willis,
"Nocuous Ambiguities in Requirements Specifications," Open University
Technical Report 2005/03 (3 March 2005) — the origin document of the
nocuous-ambiguity line, predating the RE'06 paper. This session read
it in full; everything below is [V] against the report itself. It
closes some of RQ1's [R]s, resolves part of the corpus-lineage
confusion the dive flagged, and adds design material the 2026
descendants never surfaced.*

**The construct, verbatim from the source.** Innocuous ambiguity has
a *single reading* — "they are generally only read in one way";
nocuous ambiguity has *multiple readings* — "ambiguities which
people read in different ways." Nocuous splits again into
**acknowledged** (a reader realises the ambiguity is present) and
**unacknowledged** — "two or more readers can interpret a passage of
text in different ways and each assume that their own interpretation
is the only obvious one." The report equates unacknowledged ambiguity
with "unrecognised disambiguation, one of Gause's five most important
sources of requirements failure," and calls it especially dangerous
because it is "carried over into future stages of the system
development process." So the construct behind DAMIR's (still
unverified) 87%-unacknowledged statistic is not a 2022 discovery — it
is the founding distinction of the 2005 report.

**The corpus, and the lineage untangled.** TR2005/03's dataset is
**52 sentences** containing coordination ambiguities, drawn from a
requirements-specifications corpus and judged by **17 participants in
two surveys** (coordination-first, coordination-last, or ambiguous).
This resolves the reconciliation the dive's judgment calls asked for:
the library now holds three distinct corpora in this line — this
origin set (52 coordination sentences × 17 judges, unreleased); the
later expanded coordination corpus (the "138 instances" figure, still
[R], ASE-2010-era); and the anaphora branch (Yang et al. →
ReqEval 2020's 200 sentences, the only released one). The "76.25%
accuracy on 200 anaphoric instances" the report carries at [R]
belongs to the anaphora branch and stays [R]; TR2005/03's own number
is different and now [V]: **75% accuracy (39 of 52) against a 59.6%
majority baseline**, with innocuous-prediction precision 71.4% and
recall 96.8%, from four heuristics (distributional similarity via
Sketch Engine, WordNet semantic similarity, noun number, phrase-length
difference) combined by memory-based learning with leave-one-out
validation. Two small results with modern echoes: distributional
similarity alone carried most of the signal (precision 76.5%, the
highest information gain), and adding lexical part-of-speech
heuristics *dropped* accuracy to 63.5% — more features hurting a
small-data judgment task, in 2005.

**The operationalizations are directly reusable for the project's
probes.** Acknowledged ambiguity: judged ambiguous by participants at
least as often as each specific reading. Unacknowledged ambiguity: the
least popular non-ambiguous judgment's share of all non-ambiguous
judgments, with above-average share marking the requirement
unacknowledged-ambiguous. These are computable rules over a panel of
interpretations — exactly what the pipeline's clarifying-question
exhaust produces, and what SpecFix's semantic-entropy proxy
approximates with sampled implementations instead of human judges.

**Two design positions in the 2005 report anticipate this project's
grammar, and one sharpens it.** §3.3, titled "Notification rather
than Disambiguation," argues that automatic disambiguation "has never
met with complete success" and the right design is "to notify users
of potential ambiguities and to then leave them to perform
disambiguation" — the system may flag, only the human closes:
Proposal 05's shape, twenty-one years early. And the report's
asymmetric error-cost argument is the missing principle for tuning
the clarifying phase's thresholds: "judging nocuous ambiguities to be
innocuous is dangerous, whereas including some innocuous ambiguities
with the nocuous ones is merely time wasting" — they weight their
f-measure at α = 0.9 toward precision of *innocuous* prediction for
exactly this reason. Held together with the 2026 over-asking evidence
(attention is the scarce resource), this gives the phase a two-sided
tuning rule rather than a one-sided one: silent commitment is the
expensive error, wasted questions are the cheap one, and the budget
bounds the cheap error while the seeded probes measure the expensive
one. Finally, §2.1 notes that inspection techniques — including
perspective-based reading — "merely ask the question 'is the
requirement ambiguous?'" without revealing the extent of possible
misinterpretation, which is a 2005 statement of the same PBR
skepticism the inspection review reached through the replication
record.

**What stays open.** The 138-instance expanded corpus, the anaphora
branch's 76.25%, and DAMIR's 87% remain [R]; the 52-sentence corpus
itself appears in the report's appendix (not transcribed here), which
means the origin dataset is partially recoverable from this PDF if
the project ever wants it.

---

## Addendum 2, 2026-09-06: the PDF-constraint retry

*At the resident's direction, this session re-attempted the sources
the original dive skipped under the post-incident no-PDF-extraction
constraint, using the now-installed local tooling. Three primaries
were fetched from open repositories (the ICSE 2022 Ezzini paper from
the University of Luxembourg's ORBilu, Yang et al.'s COLING 2010
paper from the ACL Anthology, and the Zaremba–Liaskos RE 2021
typology from the author's York University page) and read in full.
Fetching note: TLS verification failed for some hosts and the
fallback disabled it; integrity is assessed by internal consistency
with the published records, not by transport. One load-bearing [R]
was NOT closed and is downgraded below — the honest outcome of the
retry.*

**DAMIR's frame is confirmed; its most-quoted statistic is not in the
paper.** Ezzini, Abualhaija, Arora and Sabetzadeh (ICSE 2022), read
cover to cover: DAMIR is 22 industrial requirements specifications
from eight domains, 1,251 unique sentences, 737 pronoun occurrences —
**342 ambiguous, 395 unambiguous (46.4%)** — annotated by two
third-party annotators over 44 and 56 declared hours, at Fleiss
κ = 0.54, with the paper noting that for ambiguity analysis moderate
agreement "is to be expected... disagreements are indicators for
ambiguous cases." All of that moves to [V]. Best detection is
supervised ML at ≈60% average precision and 100% recall (F2 87.5 on
the evaluation split); best resolution is fine-tuned SpanBERT at
≈98% success; per-pronoun handling runs 1.5–14.5 seconds. Two
corpus-accounting notes: the ICSE paper's "ReqEval" is an adapted
subset (98 requirements, 109 pronouns: 62 ambiguous, 47 unambiguous)
— distinct from the 200-sentence ReqEval 2020 shared-task release,
so the two must not be conflated when sizing probes. And the
**"~87% unacknowledged" statistic attributed to DAMIR in the original
dive's search snippets does not appear anywhere in this paper.** It
is hereby downgraded from [R] to *unlocated*: do not repeat it until
someone finds its primary. The construct it describes is real
(TR2005/03's unacknowledged ambiguity; the ICSE paper's
disagreement-type (ii), where both annotators pick different
antecedents each believing the pronoun unambiguous), but the number
has no source the project has seen.

**The Yang COLING 2010 methodology paper closes the coordination
corpus and adds the missing parameter.** Now [V]: the Chantree 2006
coordination corpus is **138 instances**, 85.5% (118) noun-compound
conjunctions, judged by 17 computing professionals choosing high
attachment, low attachment, or ambiguous. The anaphora corpus is
**200 instances from requirements documents, judged by 38 computing
professionals at no fewer than 13 judges per instance** — which
strengthens the identification of this line with ReqEval 2020's 200
sentences. The conceptual addition the 2026 descendants dropped: the
**ambiguity threshold τ**. An interpretation's *certainty* is the
percentage of readers who hold it; an instance is nocuous if no
interpretation's certainty exceeds τ — making nocuity explicitly
relative to a tolerance level, with the paper noting safety-critical
domains should set τ high and tolerant domains low. That is the
tunable knob the clarifying phase needs for per-document-class
strictness, with SpecFix-style semantic entropy as its samplable
estimator. Results, honestly: ≈21% accuracy over naive baselines at
the coordination crossover threshold, +3.4 F points for anaphora,
precisions of 0.3–0.6 — and the explicit stance, citing Berry, that
ambiguity detection "should emphasise recall even at the expense of
some precision." The 76.25% anaphora accuracy stays [R] (it belongs
to the RE'10/REJ line this paper cites as in press), now corroborated
at "≈76%" by the ICSE 2022 paper's [V] citation of the same work.

**The Zaremba–Liaskos question typology moves from [R] to [V], and it
is the question grammar the phase design was missing.** RE 2021,
cross-disciplinary review (software engineering, psychology,
sociology, health care, journalism, judicial investigation), offering
a first-cut typology over dimensions of time, content, form, style,
probing style, and objective — explicitly not yet reliability-
validated, by its own framing. Four pieces transfer directly. Derr's
content grammar: any object of inquiry can be questioned on
existence, identity, properties, relations, number, time, location,
and action — a per-clause question generator that composes with the
ambiguity tags. The *clearinghouse probe* ("what have I not asked
that is important?") is a named question type aimed exactly at the
forgot-to-specify gap. *Check-reflect*, *echo*, and *restatement*
probing are the interview literature's read-back primitives,
anticipating the phase's exit ritual. And the *content-maneuvering*
types — forced-choice, leading, declarative, negative-balance
questions, which steer the answer — are flagged as detrimental to
requirement validity in the RE context: a ready-made negative
checklist for generated questions, complementing the Bano mistake
taxonomy. The paper also carries the "ample questions early, rigid
questions late" guidance (converging with the goal-first timing
evidence from a different literature) and names *interviewing
efficiency* — useful information per question — as the construct the
phase's budget metrics operationalize.

**Still open after the retry:** the Bano mistake-taxonomy primary
(Springer/ResearchGate walls; the typology paper pins its venues —
RE'18 pp. 182–193 and REJ 24(3) 2019 — for a future attempt); the
White Rose REJ anaphora PDF; and the 87% figure's primary, if it has
one.
