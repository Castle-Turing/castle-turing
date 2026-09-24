# The outcome log never records a question

**What.** `docs/measurement.md` defines `questions` as a per-attempt
cell, and `tools/outcomes/outcomes derive` never fills it — it reads
cost, turns, model and the pull request out of a harness journal and
stops there. Every row in `docs/log/task-outcomes.tsv` carries `-` in
that column, and always will.

**Why it matters.** The question economy is one of the few things this
project claims to be measuring rather than asserting, and the column
that would measure it has never held a number. A column that is
structurally always `-` is worse than one that is absent: it reads as
"this attempt asked nothing" to anyone who does not already know the
derivation never looks.

**What the fix is, and it is small.** The fact is in the same journal
`harness_facts` already reads: the tenant writes a `parked` record per
question. Counting them per task is a few lines beside the `usage` and
`pr` handling that is already there. `question_wait_h` is the harder
half and is a separate question — the tenant's `answered` record
carries a timestamp, so the wait is derivable, but only for questions
that were answered, and an unanswered one has no honest value yet.

**How this would have been caught sooner.** A check that every
non-immutable column has at least one writer would have named it the
day the schema landed. The weaker form — a column that is `-` in every
row of a log with sixty rows in it — is mechanical, cheap, and would
have caught this one specifically.
