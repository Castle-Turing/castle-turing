# Task 0049 — the research library

**Motivation.** The August 2026 literature reviews — four synthesis
reports behind roughly a dozen backlog entries — existed only as
private rendered artifact pages on a hosting service. That is exactly
the dependence the tasks convention was written against: reasoning the
repo runs on, living somewhere the repo cannot reach. The resident
asked (2026-09-03) for them to live in the tree as markdown.

**What was done.** `docs/research/` created with faithful markdown
transcriptions of the four surviving reports — `pressure-test.md`
(16 Aug), `staying-fluent.md` (15 Aug), `delegation-papers.md`
(17 Aug), `competence-as-an-end.md` (17 Aug) — plus a README stating
the directory's contract: full historical reports here, compressed
decision-relevant versions in `docs/backlog/`, per-claim verification
levels preserved. The raw per-review working reports behind these
syntheses lived only in session transcripts and are not recoverable;
the syntheses are the complete surviving record. Seven backlog entries
gained a one-line pointer to the full report behind them.

**Scrub rule applied.** No personal data enters this repo: one line in
`staying-fluent.md` quoting the resident's own description of their
expertise was generalized ("a resident supervising agent work in a
domain they have barely begun learning"); artifact URLs were not
carried over. Nothing else person-identifying was found.

**Verification.** Files render as plain markdown; a grep across
`docs/research/` for personal strings (names, email fragments) comes
back empty; transcription fidelity was checked against the source
pages during transcription — prose is verbatim except the one
generalized line, with layout-only elements (styling, chips) rendered
as markdown equivalents.
