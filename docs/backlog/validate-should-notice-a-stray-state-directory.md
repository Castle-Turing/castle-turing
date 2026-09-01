# `castle validate` should notice a stray state directory

**What.** After a resident migrates their journal out of the private
flake (task 0030's layout), the old `state/` directory can linger in
the private checkout — and on 2026-09-01 one did, with real
consequences: a worker turn, asked about a recent errand, found the
stale copy inside `CASTLE_PRIVATE_ROOT`, took its single ancient
record for the whole journal, and reported two confident anomalies
("the journal is missing the errand that produced this diff") that
were artifacts of reading the wrong directory. Nothing in the system
noticed the machine had two things shaped like journals.

**Fix direction.** `castle validate` (and `castle digest`, which
already warns about state-inside-the-flake) knows both
`CASTLE_STATE_DIR` and `CASTLE_PRIVATE_ROOT`: when a
`state/journal/`-shaped directory exists under the private root and
is not the configured state dir, warn, naming both paths and the
migration doc. The worker prompt could carry the same fact one line
cheaper: name the configured state dir as the *only* journal, so a
tenant never trusts a lookalike it happens across.
