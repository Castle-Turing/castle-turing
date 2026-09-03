# Does a legible history produce calibrated trust, or just trust?

*A research question, not deferred implementation. Partly answered
already — see the last section.*

**What.** `docs/vision.md` states as a design principle: "Trust is built
through a legible history. Every triaged email, declined meeting, and
deferral is logged with its reasoning in a decision journal — not shown,
but always inspectable." The journal is built (task 0008). The
assumption that inspectability produces *appropriate* reliance is
nowhere argued, only asserted.

**The question.** Does the availability of inspectable reasoning make a
principal's trust track the system's actual reliability — or does the
mere presence of a legible rationale inflate trust while inspection
rates collapse?

**What the completed research already found — and it is against us.**
Two independent reviews converged on this without knowing about each
other:

- Bansal, Wu, Zhou, Fok, Nushi, Kamar, Ribeiro & Weld, "Does the Whole
  Exceed its Parts? The Effect of AI Explanations on Complementary Team
  Performance" (CHI 2021). Mixed-method studies across three datasets:
  **explanations increased the rate at which humans accepted the AI's
  recommendation regardless of whether it was correct.** Explanation
  without careful design increases over-reliance rather than improving
  joint accuracy.
- A separate review reports the XAI literature repeatedly finding that
  visible explanations inflate rather than calibrate trust, and that
  **placebic explanations work almost as well as real ones** — the root
  being Langer, Blank & Chanowitz's 1978 copy-machine study
  **[verify the XAI replication]**.

The salvage both reviews independently identified: **cited evidence is
the load-bearing half, not the reasoning prose.** Evidence a resident
can check against an external source restores an independent
verification path; fluent reasoning is an anchoring device, and a
capable agent will always produce plausible reasoning.

**What remains open.** Whether the effect holds for a *single* principal
with years of accumulated history and real stakes, rather than
study subjects judging unfamiliar outputs. And whether Lee & See's
calibration vocabulary ("calibration, resolution, specificity") should
simply be adopted wholesale — it looks directly reusable.

**Where the rest of the answer lives.** Lee & See, "Trust in Automation:
Designing for Appropriate Reliance" (2004) — the central reference.
Parasuraman & Riley (1997) on use, misuse, disuse. Poursabzi-Sangdeh et
al., "Manipulating and Measuring Model Interpretability." Judy Kay's
scrutable user modelling for evidence on whether subjects ever open an
inspectable model.

**What would change.** The journal's passive availability stops being
the trust mechanism, and the digest and audit take on an active
calibration job — leading with the decisions the system was least
confident in, surfacing its own error rate, making disagreement visible
rather than waiting to be read. "Not shown, but always inspectable" gets
demoted from trust mechanism to accountability floor, and the trust
mechanism needs designing separately. Measurement changes too: track
reliance behaviour, not felt trust.

**Priority: high.** The journal exists, the digest surface is shaped
(task 0009), and the audit ritual is the next design item. All three
inherit this assumption.

*Full review: see `docs/research/pressure-test.md` (landed after this entry was written).*
