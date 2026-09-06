# An agent workload can thrash the host, and nothing bounds it

**What.** The workload that exhausted memory on 2026-09-06 (see
`a-crash-goes-uninvestigated.md`) was ordinary delegated research: a
session fanned out three concurrent research subagents, and at least
one extracted text from PDFs by invoking
`nix shell nixpkgs#poppler-utils` repeatedly — six nix-daemon
connections in under three minutes — each invocation evaluating
nixpkgs at roughly 2 GB peak. Three subagents plus concurrent nixpkgs
evaluations on a 16 GB machine is arithmetic, and nothing anywhere in
the stack — not the delegating session, not the subagent's brief, not
the host — stated or enforced a resource bound.

**Why it matters.** The project's direction is *more* fan-out, not
less: parallel sessions, research dives, an emcee queue keeping
multiple workers busy. Every layer currently assumes some other layer
is watching memory. The host-side net is its own entry
(`the-host-has-no-working-oom-defense.md`); this one is about the
workload side, because even a working oomd only converts a hang into
killed work — the crash this stems from destroyed in-flight tasks in
four sessions either way.

**What went wrong at the delegation layer, specifically.** The
subagent was never told the host's constraints, so it improvised —
and notably, an earlier dive the same night faced the identical
missing-tool problem (no `pdftotext` on PATH) and judged that
installing tooling was out of scope, taking two unverified markers as
the cost. Same gap, opposite judgment calls, and only one of them was
safe. A constraint that lives in a delegating prompt sometimes and in
an agent's judgment otherwise is not a constraint.

**Fix directions, none chosen.**

- The worker contract and delegation conventions state host resource
  discipline explicitly: no per-command `nix shell nixpkgs#...` in
  loops (evaluate once into a profile, or do without), and a stated
  cap on concurrent subagents per host, sized to its RAM.
- Tooling that research tasks predictably need (PDF text extraction)
  is either declared in the environment once, or declared unavailable
  — so no agent decides mid-task to summon it via nixpkgs
  evaluation. *Partially done in task 0063: `poppler-utils` is now
  declared in `modules/dev`, and the resident's agent profile gained
  an install-or-report-never-summon instruction. The general
  question — how a task learns what tools it may assume — stays
  open here.*
- Systemd-level resource caps (`MemoryHigh=`/`MemoryMax=`) on the
  slices agent sessions run in, so the bound is enforced rather than
  promised. Interacts with the oomd entry's kill-target question.

**Open questions.** Where the concurrency cap belongs — the
delegating session's judgment, the harness, or the host config — and
whether a subagent brief should carry a resources line the way task
files carry `Model:`, so the bound travels with the work instead of
depending on whoever wrote the prompt remembering it.
