Title: A row appears in the outcome log when a task lands (worked example)
Model: cheap
Model-because: the criteria below were written against a mechanism that
    already exists and whose invocation path is written down, so the work
    of turning each one into a command is transcription. A deeper tier
    would arrive with nothing to decide. What would make a cheap tier
    wrong is the criteria themselves being wrong, and they are not this
    example's to choose — they are read off task 0072's clause.
Milestone: none — worked example, not work
Criterion: the gate that refuses an unlogged task runs in the invocation
    path CI uses, over the log this repository actually carries, and
    finds nothing wrong with it. A gate nobody can run is the shape of
    task 0070's miss.
Check: tools/outcomes/outcomes check --no-base
Criterion: the log carries a row for a task that has landed, with its
    landing date filled in. This is the clause itself — a row appears
    when a task lands — checked against the committed log rather than
    against a fixture, because a row that exists only in a fixture is a
    row the pipeline never wrote.
Check: awk -F'\t' '$2=="0072-wire-the-outcome-log-and-its-redirects" && $5!="-" {found=1} END {exit !found}' docs/log/task-outcomes.tsv
Criterion: the gate refuses a log with that row missing. The direction
    task 0070 shipped without: a coverage check that cannot fail is
    indistinguishable from one that is not armed, so the demonstration
    has to be the refusal and not the pass.
Check: d=$(mktemp -d ./accept-oracle-XXXXXX) && trap 'rm -rf "$d"' EXIT &&
    grep -v '	0072-wire-the-outcome-log-and-its-redirects	'
    docs/log/task-outcomes.tsv > "$d/log.tsv" &&
    ! tools/outcomes/outcomes --log "$d/log.tsv" check --no-base
Criterion: a sampled row reads true to the resident: the tier, the
    environment and the redirect columns say what the resident remembers
    of that task. No command can stand in for this — the columns record
    judgment, and whether the record matches the judgment is the
    judgment's owner's to say.
Manual: the resident picks a row from docs/log/task-outcomes.tsv, reads
    it against their own memory of the task, and says on the pull request
    whether the row is true. Divergence is this harness's falsifier, not
    the log's.

# A row appears in the outcome log when a task lands (worked example)

**This is a worked example, not approved work.** Its criteria are
post-hoc: task 0072 landed before this harness existed, so nobody
pre-committed anything here, and a receipt over these criteria is
evidence about the mechanism in the repository today rather than evidence
about how that task was accepted. The label is the whole defence,
because a brief carrying criteria is shaped exactly like a brief whose
criteria *were* frozen before implementation — the same salt discipline
the clarify probe and the oracle slate carry, for the same reason
(Proposal 06).

Why this task and not an invented one: task 0070 built the outcome log's
coverage gate and shipped the thing that writes rows with no caller at
all. Every test passed. The criterion that would have caught it is "a row
appears when a task lands", which is a statement about an invocation
path and not about a function, and it is the exact criterion nobody had
written down. Running it here demonstrates the format on the shape of
failure the format exists for.

The fourth criterion is the one that matters most and the one no command
answers. It is named rather than omitted, which is what
`docs/planning.md` requires of a criterion that cannot compile to a
check: blank is not an answer, and a brief whose criteria are all
executable is usually a brief that quietly dropped the criterion a
person had to take.
