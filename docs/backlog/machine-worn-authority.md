# What does a machine-authored "no" do to the resident's name?

*Research done 2026-08-17. This entry now records findings rather than
posing the question. Citations verified at the level stated; where the
reviewer read only an abstract or a summary it says so.*

**What.** `docs/vision.md`: "When the agent declines a meeting, someone
on the other end is being told no by a machine wearing the user's
authority; the failure modes there are social, not technical."

**The headline: that configuration is the expensive one, and it is
optional.**

Schilke & Reimann, "The transparency dilemma: How AI disclosure erodes
trust" (*Organizational Behavior and Human Decision Processes* 188,
2025) — 13 preregistered experiments, 4,093 observations, pooled
disclosure penalty θ=0.81 [0.66, 0.96].

- **Human delegation is socially free.** Four studies carried
  human-delegation controls: disclosing that a *person* did the work
  produced no significant penalty (d = 0.06–0.17, ns). Disclosing *AI*
  produced d = 0.77–1.11 in the same designs. The penalty attaches to
  machine authorship wearing the principal's identity, not to delegating.
- **An agent that signs as itself escapes most of it.** Study 10: an
  email from an openly autonomous AI agent was trusted *more* (M=5.61)
  than one from a human disclosing AI help (M=4.94, d=0.64), and was
  indistinguishable from a human disclosing nothing (M=5.72, ns). The
  proposed mechanism is role ambiguity — the blended human-AI author is
  the least legitimate configuration because nobody clearly holds
  responsibility.

**Concealment-then-discovery is the worst outcome, and it is measured.**
Study 13: exposure by a third party (M=2.49) < self-disclosure (M=3.15)
< undetected non-disclosure (M=4.02); exposure vs non-disclosure d=1.66.
Non-disclosure wins *only* conditional on never being found out, and for
an always-on agent P(discovery) → 1. Cardon & Coman (*International
Journal of Business Communication*, 2025, n=1,158): at high AI
assistance only **25%** of readers attributed authorship to the named
human, versus 93% at low assistance.

**The harm is to the resident's standing, not the third party's
welfare.** No study measures whether the declined party was worse off —
only whether they now think less of the decliner. That reframes this row
from an ethics question about strangers into a reputation question about
the resident, which is a far more durable enforcement mechanism.

**Other findings worth carrying:**

- *Norm-relative.* Jakesch et al. (CHI 2019): when *all* profiles were
  AI-generated, trust was equal to all-human. The penalty appeared only
  in mixed environments. A stable published convention converges toward
  no penalty; a per-message confession pays the tax every time.
- *Disclosure buys blame-absorption* when things go wrong (Hohenstein &
  Jung 2020) — insurance, not pure cost. Do **not** conflate this with
  Elish's "moral crumple zone" (2019), which runs the opposite
  direction: there the human absorbs blame to protect the system.
- *Valence asymmetry, with a real tension.* Khadpe et al. (AIES 2025):
  AI labels cost warmth on thanks (5.59→4.76) and apologies (5.83→4.75)
  but not on bragging or blaming. Yet Schilke's Study 6 found the
  penalty *stronger* on a termination letter. Reconciliation offered:
  on a face-threatening act disclosure costs legitimacy and competence
  but not warmth. Do not cite Khadpe alone to license auto-declines.
- *Legal floor.* EU AI Act Article 50 applies from 2 August 2026. It
  does not reach private correspondence, but a conversational agent
  arguably falls under 50(1), and regulation ratchets one way.

**What remains open.** The reviewer identified the empty cell: nobody
has tested a colleague in an *ongoing relationship* receiving a decline,
later learning an agent sent it, with the **relationship** measured
rather than the sender rating. Schilke's Study 13 is exposure but swift
trust; Study 5 is a coworker but self-disclosure. It is a vignette
study, not a lab — cheap to run if the project ever wants evidence
rather than inference for this row.

**Also open, and for the resident:** does this change `docs/vision.md`?
The passage states the problem as machine-worn authority; the evidence
says that framing describes an avoidable configuration rather than an
inherent one.

*Full review: see `docs/research/delegation-papers.md` (landed after this entry was written).*
