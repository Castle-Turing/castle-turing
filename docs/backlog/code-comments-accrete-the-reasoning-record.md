# Code comments accrete the reasoning record

**What.** Raised by the resident 2026-09-06, reading the handoff
research: context is strewn across document kinds — brief material
shows up in code comments. A survey the same morning confirms it and
sizes it. In `modules/`, `hosts/`, `tools/`, `agent/`, and `test/`:
875 lines citing task numbers or brief paths; 91 comment blocks of
eight or more consecutive lines in nix files alone. Classification of
samples shows the pattern: blocks *start* as constraints the code
cannot show (the `modules/desktop` header's "this default is
load-bearing, not incidental" — exactly what house style wants) and
*accrete* narrative — the same header then spends twenty lines
retelling finding #1's history and why one word changed in task 0032.
That second part is a brief's reasoning record, duplicated into code.
The freshest instances are from the night before this entry: the
incident narratives in the task 0063 comments (`hosts/xps9370`,
`modules/dev`) mix a real constraint with a crash story the backlog
already records — written by the same session that then ran this
survey.

**Is it really a problem? The determination, honestly split.** On
*authority and rot* grounds: yes, proven. The same fact living in a
brief and a comment rots independently, and the citation-rot entry
(`tidying-a-brief-into-done-rots-its-citations.md`) already documents
140 of these 875 breaking on a single `done/` sweep. On *context*
grounds: plausible but unmeasurable here. The evidence says curated
context helps and unfiltered context has limited or negative value,
and that low-relevance content dominates agents' context budgets —
twenty lines of history read by every future agent that opens the
file is exactly that. But long-context robustness results cut the
other way for raw length, and the one factorial study of
guidance-file structure (1,650 sessions) detected no effect from
structural rearrangement — so a cleanup's benefit will not be
measurable at this project's scale, and the honest case for it is
maintenance and authority hygiene, not a promised accuracy win.
(Full citations: `docs/research/inter-task-handoff.md` §4,
`docs/research/measurement-methodology.md` §2.)

**The rule, if adopted.** A code comment states the constraint the
code cannot show, and cites the record by task number — one line, a
name, per the authority rule task 0061 proposes. The story of how the
constraint was learned lives in the brief or backlog entry the
citation names. This makes code comments a fourth document kind with
the same two-layer split as everything else: current truth in place,
history in the record.

**Retroactive cleanup.** Its own task, after 0061 lands (the
citation-as-name convention must exist first, or the cleanup writes
citations in a form the next convention change breaks again). The
work is judgment-per-block, not mechanical: each of the 91 blocks
splits into constraint lines that stay and record lines that
compress to a citation. Sized in the tens of files; the 875 citation
lines mostly stay (a citation is fine — it is narrative that goes).

**The linter, for after the cleanup.** Mechanically decidable and
blockable: brief *paths* in code (`docs/tasks/....md`) — citations in
code are names, and a path in code is wrong by convention. Warn-only,
per the precision discipline (indicators, not defects): date patterns
inside code comments (dates mark narrative — 10 instances today,
all recent); comment blocks over a threshold length; PR-number and
review references in comments. Warn-only because each has legitimate
uses; a blocking lint at indicator precision gets switched off.

**Open questions.** The threshold length; whether module-header
overview blocks (the first 15 lines of the desktop header are good)
get a carve-out or just stay under the threshold; and whether the
cleanup should also relocate the load-bearing *constraints* it finds
into `docs/state/` where later work cites them — which would make it
partially an extraction pass for 0061's layer, not just a deletion
pass.
