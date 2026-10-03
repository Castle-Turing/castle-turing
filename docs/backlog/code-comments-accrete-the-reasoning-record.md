Title: Code comments carry constraints, not chronicle
Model: standard
Model-because: the judgment — where the constraint/narrative razor
falls, which rules warn and which block — is settled in this spec and
was settled in the entry's own analysis before it; what remains is a
scanner, fixtures, and a drafted CLAUDE.md diff, all in the
reachability-check mold. A deep implementer would re-litigate settled
boundaries; the risk this brief carries is under-following it, which
review catches, not out-thinking it.
Milestone: none — hygiene

# Code comments carry constraints, not chronicle

## Where this came from

Raised by the resident 2026-09-06, reading the handoff research:
context is strewn across document kinds — brief material shows up in
code comments. A survey the same morning confirmed and sized it. In
`modules/`, `hosts/`, `tools/`, `agent/`, and `test/`: 875 lines
citing task numbers or brief paths; 91 comment blocks of eight or
more consecutive lines in nix files alone. Classification of samples
shows the pattern: blocks *start* as constraints the code cannot show
(the `modules/desktop` header's "this default is load-bearing, not
incidental" — exactly what house style wants) and *accrete*
narrative — the same header then spends twenty lines retelling a
finding's history and why one word changed in task 0032. That second
part is a brief's reasoning record, duplicated into code.

The rule exists in the resident's profile (instruction hygiene:
contract, not chronicle) and in emcee's agent guidance, but was never
adopted as this repository's own convention — task 0072's review
included a one-time de-lore sweep of one PR's surfaces, with no
standing rule and no check behind it. The mechanism of recurrence is
the profile's own observation: sessions copy the register of what
they read, so a repo saturated with lore comments teaches every
implementer that lore is the house style. The 2026-09-24 sprint added
fresh instances, including by the session that grew this spec.

## Is it really a problem? The determination, honestly split

On *authority and rot* grounds: yes, proven. The same fact living in
a brief and a comment rots independently, and a single `done/` sweep
broke 140 of the 875 citation lines. On *context* grounds: plausible
but unmeasurable here. The evidence says curated context helps and
low-relevance content dominates agents' context budgets — but the one
factorial study of guidance-file structure detected no effect from
structural rearrangement, so a cleanup's benefit will not be
measurable at this project's scale, and the honest case is
maintenance and authority hygiene, not a promised accuracy win.
(Full citations: the inter-task-handoff and measurement-methodology
research reviews, docs/research/.)

## The rule

A code comment states the constraint the code cannot show, and cites
the record by task number — a name, one line, per the
citation-as-name convention (task 0061, landed). The story of how the
constraint was learned lives in the brief or backlog entry the
citation names. Code comments become a fourth document kind with the
same two-layer split as everything else: current truth in place,
history in the record.

The boundary, stated so nobody over-applies it: task-number citations
in briefs, backlog entries, and `docs/state/` are the convention, not
the defect — records cite records. The rule binds surfaces an agent
loads in order to act: code comments, README operating sections, tool
headers, workflows.

## What lands

1. **The CLAUDE.md paragraph** — two or three sentences under
   Conventions stating the rule and the razor, drafted as a diff in
   the implementing PR so approving it is reading it. **A CLAUDE.md
   change always needs the resident's explicit approval at review,
   and this task's ready mark does not supply it** — if the resident
   declines the paragraph, the lint below still lands (its rules are
   its own documentation) and only the obligation's placement is
   lost.
2. **`tools/comment-lore-check.py`** — a lint over comments in
   `modules/`, `hosts/`, `tools/`, `agent/`, `test/`, and
   `.github/workflows/`, two tiers per the precision discipline the
   clarify checker already applies (indicators warn, defects block):
   - **Blocking, once armed:** a brief *path* in a comment
     (`docs/tasks/…`, `docs/backlog/…`) — citations in code are
     names, and a path is wrong by convention and breaks on every
     sweep. **Lands warn-only**, because the current tree carries
     these by the hundreds; the retroactive cleanup (below) flips it
     to blocking in the same PR that makes the tree clean, so the
     gate is never armed against a tree that cannot pass it — the
     0070 lesson, applied in advance.
   - **Warn-only, permanently:** date patterns inside comments (dates
     mark narrative), PR-number and review references, and comment
     blocks over 15 consecutive lines (the desktop header's good
     first 15 lines are the calibration; module-header overviews get
     no carve-out — the threshold is the carve-out). Warn-only
     because each has legitimate uses, and a blocking lint at
     indicator precision gets switched off.
   Every run prints its warning counts by rule; the run that lands
   with this task commits the baseline counts in the lint's own
   documentation, so drift is a diff against a recorded number, not
   an impression.
3. **Fixtures** (`test/comment-lore/run.sh`): each rule fires on a
   seeded fixture and stays silent on a clean one; a brief path
   blocks (in the armed configuration); a task-number citation alone
   never fires anything; the real tree passes in the shipping
   (warn-only) configuration.
4. **Reachability:** a CI workflow with a feeder line; invokes
   markers at the documented steps; the lint green on its own PR.

## Retroactive cleanup — its own task, deliberately

Judgment-per-block over ~91 blocks and tens of files: constraint
lines stay, narrative compresses to a citation. Stays a separate
backlog item because it is a different kind of work (editorial
judgment at volume, standard-tier, mechanical to verify) and because
its one open design question — whether relocated constraints should
be extracted into `docs/state/` rather than merely trimmed in place —
deserves its own spec rather than a rider here. That item also owns
flipping the path rule to blocking. Until it runs, the lint's
baseline counts are the measure of whether the rule is at least
holding the line.

## Verification plan

Automated: the fixture suite in CI (each rule demonstrably fires and
demonstrably stays silent); the real tree green under the shipping
configuration; reachability and outcomes-check green. The committed
baseline counts are the honest statement of what the tree carries at
landing. Needs the resident: the CLAUDE.md paragraph's explicit
approval at review — by construction — and nothing else.
