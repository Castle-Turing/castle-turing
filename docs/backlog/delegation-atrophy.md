# Silent competence and the auditor: what the research found

*Research done 2026-08-17. Records findings rather than posing the
question. The reviewer flagged its own verification level per source;
the weakest items are omitted here and the contested ones are marked.*

**What.** `docs/vision.md` describes an assistant to whom "executive
function itself can be offloaded," and commits to owing only the lowest
comprehension altitude by default — "by stated preference, calibrated to
demonstrated competence rather than maximized." It also says an audit
the resident "can't meaningfully evaluate is oversight in name only."

**The design therefore requires the resident to retain evaluative
competence while delegating away the practice that maintains it.** That
assumption was never examined. It does not survive examination.

## The assumption is inverted

**Casner, Geven, Recker & Schooler, *Human Factors* 56 (2014).** 16
airline pilots, systematically varied automation. Manual control was
"surprisingly resistant to forgetting, even after four months of
inactivity." What collapsed was cognition: **44% error identifying
missed approach points, 38% on missed approach headings**, plus failures
to cross-check instruments and diagnose abnormal indications.

**Execution is sticky. Judgment is fragile.** The design assumes the
reverse. Judgment — reconstructing state, predicting next steps,
recognising that something is off — is the entire content of an audit.

Ebbatson et al. (*Ergonomics* 2010) adds the decay constant: pilots who
had flown more sectors *in the prior week* showed smaller heading error.
Dose-response with recency at a one-week timescale.

## The auditor cannot self-assess

**METR (2025), arXiv 2507.09089.** 16 experienced developers, 246 tasks,
repos they had worked ~5 years. Forecast +24%, self-reported +20%,
**measured −19%**. Experts could not detect a large negative effect on
their own performance. Caveats: small N, early-2025 tooling.

**Fisher, Goddu & Keil (*JEP: General* 2015), 9 experiments.** Searching
the internet for explanations *inflates* estimates of one's own internal
knowledge. Access is mistaken for understanding.

**Lee et al. (CHI 2025), 319 knowledge workers.** Confidence in GenAI
associated with *less* critical thinking; self-confidence with *more*.
The two move against each other — so as the agent improves and trust
rises, audit effort falls, and the thing that would sustain it is
exactly what atrophies.

## The competence-gating clause is a positive feedback loop

Widening authority in a domain is what stops the resident practising in
it, so the calibration signal decays as a consequence of acting on it,
fastest where authority is widest. No damping term.

Worse, Buçinca et al. (*CSCW* 2021, N=199) found the interventions that
reduce overreliance are the ones users **rate less favorably**, and they
help people with high need for cognition **most**. A preference-gated
safeguard self-selects for those who least need it; gating it on
demonstrated competence makes this strictly worse, because the resident
whose competence has decayed both stops asking and stops qualifying.

**If depth must be rationed, ration by consequence of the decision, not
revealed appetite.** Better: a floor that preference can raise and never
lower.

## The checklist trap

**Hodges et al., *Academic Medicine* 74 (1999).** Clerks, residents and
family physicians on the same encounters, scored by binary checklist and
global rating. The experienced clinicians scored **significantly better
on global ratings and significantly worse on checklists** — experts skip
steps they have already ruled out, and a checklist reads that as
omission.

So the instrument that makes a non-expert reliable **inverts the
expertise ordering**. Any comprehension-level audit aid will
systematically flag a well-performing agent taking expert shortcuts and
pass an agent that is thorough and wrong. If one is built, pair binary
checks with a global judgment and expect them to disagree in exactly the
informative cases.

## What the evidence supports doing about it

1. **Guardrail the interface, not the access.** Bastani et al. (*PNAS*
   122(26), 2025) — ~1,000 students, randomized. Unrestricted GPT: 17%
   *worse* on later unaided exams. A tutor-configured GPT that withheld
   answers and gave hints: harm eliminated. Honest ceiling — it reached
   parity, not above. Guardrails prevent damage; they do not build
   capacity.
2. **Make the audit structural rather than judgmental.** Professional
   auditing works, and not by making auditors competent performers: it
   scopes to assertions checkable against explicit standards, requires
   the *auditee* to produce evidence in prescribed form, samples rather
   than reviews holistically, and attaches external liability. **This
   project has none of the four.** That, not better explanations, is the
   route by which a non-performing resident can audit.
3. **Prefer state transparency to answer justification.** Bansal et al.
   (CHI 2021): explanations increase acceptance of AI recommendations
   *regardless of correctness*. Show what the agent is doing, on what
   inputs, with what uncertainty — do not default to explaining why an
   answer is right.
4. **Currency requirements on the cognitive skills specifically.**
   Aviation's answer, and note the FAA had to reissue the same advisory
   four years later (SAFO 13002 → 17007), which is evidence that
   *voluntary* currency guidance is not followed. The Castle Turing
   form: periodic unassisted reconstruction — "given this log, what did
   the agent do and why, and what would you have done?" — scored against
   the actual trace. It doubles as the instrument for (7).
5. **Cognitive forcing at decision time, sparingly**, on a small
   high-stakes subset, and *not* gated on preference.
6. **Do not gate depth on demonstrated competence.** The one place the
   reviewer called an outright bug rather than a tradeoff.
7. **Measure the resident, not just the system.** The design has an
   oversight dependency with no observability on the dependency.

## Contested, and flagged as such

The "lumberjack effect" (Onnasch et al. 2014 — higher automation
improves routine performance and worsens failure response) is **an
active dispute**: Jamieson & Skraaning found the opposite in a
full-scope nuclear simulator with licensed crews, and four papers have
gone back and forth without resolution. Robust in lab microworlds,
unproven in complex realistic work — which is nearer this setting. Cite
as hypothesis, never as settled.

Sparrow et al.'s "Google effects" (2011) **failed to replicate** twice.
Do not build on it; build on Fisher/Goddu/Keil and Risko & Gilbert.

Dahmani & Bohbot's GPS/hippocampus longitudinal arm is **N=13**.
Directionally consistent, evidentially thin.

## The gap that is itself a finding

The reviewer searched specifically and **could not find a direct
empirical literature on whether assessment competence survives loss of
production competence in cognitive or knowledge work.** Everything above
is indirect — motor-domain (Aglioti et al. 2008, where expert coaches
and journalists were *outpredicted* by athletes), assessors' own beliefs
(Berendonk 2013), or code review (Bacchelli & Bird 2013: "code and
change understanding is the key aspect of code reviewing").

The project's most load-bearing oversight assumption sits exactly where
the science has not gone.

*Full review: see `docs/research/delegation-papers.md` (landed after this entry was written).*
