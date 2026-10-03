# Acceptance run — A row appears in the outcome log when a task lands (worked example)

Brief: tools/accept/oracle/brief.md
Commit: 92eec01
Base: (none declared — the frozen rule did not run)
Cycle: 1 of 3
Criteria: 4 — 3 with an executable check, 1 standing as a named manual step

## Criterion 1 — observed as the criterion states

> the gate that refuses an unlogged task runs in the invocation path CI
> uses, over the log this repository actually carries, and finds nothing
> wrong with it. A gate nobody can run is the shape of task 0070's miss.

    $ tools/outcomes/outcomes check --no-base
    exit: 0
    output:
    | ok: 80 rows, 80 briefs, schema 1

## Criterion 2 — observed as the criterion states

> the log carries a row for a task that has landed, with its landing date
> filled in. This is the clause itself — a row appears when a task lands —
> checked against the committed log rather than against a fixture, because
> a row that exists only in a fixture is a row the pipeline never wrote.

    $ awk -F'\t' '$2=="0072-wire-the-outcome-log-and-its-redirects" && $5!="-" {found=1} END {exit !found}' docs/log/task-outcomes.tsv
    exit: 0
    output: (none)

## Criterion 3 — observed as the criterion states

> the gate refuses a log with that row missing. The direction task 0070
> shipped without: a coverage check that cannot fail is indistinguishable
> from one that is not armed, so the demonstration has to be the refusal
> and not the pass.

    $ d=$(mktemp -d ./accept-oracle-XXXXXX) && trap 'rm -rf "$d"' EXIT && grep -v '	0072-wire-the-outcome-log-and-its-redirects	' docs/log/task-outcomes.tsv > "$d/log.tsv" && ! tools/outcomes/outcomes --log "$d/log.tsv" check --no-base
    exit: 0
    output:
    | docs/tasks/0072-wire-the-outcome-log-and-its-redirects.md: brief has no row in ./accept-oracle-MsYHvb/log.tsv; append one in this pull request — see docs/measurement.md
    | 
    | 1 problem(s). docs/measurement.md is the authority on every rule above.

## Criterion 4 — not exercised here; a named manual step stands in its place

> a sampled row reads true to the resident: the tier, the environment and
> the redirect columns say what the resident remembers of that task. No
> command can stand in for this — the columns record judgment, and whether
> the record matches the judgment is the judgment's owner's to say.

    manual: the resident picks a row from docs/log/task-outcomes.tsv, reads it against their own memory of the task, and says on the pull request whether the row is true. Divergence is this harness's falsifier, not the log's.

## What this run did not check

- criterion 4: not exercised here. The manual step named in the brief is what answers it, and a person has to take it — this run neither took it nor stands in for it
- the criteria were not compared against any earlier commit: no --base was declared, so nothing here would notice a criterion edited on the branch being measured against it
- whether each criterion would demonstrate the requirement it traces, rather than merely exercise code — item 2 of the slate-review checklist in docs/planning.md, and the resident's
- anything the criteria did not name. This run read the brief and ran its commands; it read no diff, no transcript and no reasoning, which is its isolation and also its blind spot
- repair cycles past 3: this is cycle 1, and the cap is a backstop rather than the design — the stopping rule the self-correction literature measures is error-introduction catching error-correction, which needs per-model rates this slice does not have (docs/research/decomposition-and-iteration-caps.md)

What this run observed is that the commands named above exited the way
the criteria said they would, in the invocation path each criterion
names, at one commit. That is a receipt: evidence that a mechanism
fired. It is not a judgment that the work is what the resident asked
for, and no run of this tool can be one — an agent exercising a
criterion is solid evidence the mechanism fired and weak evidence a
person is satisfied. The resident's verdict stays the only verdict
(Proposal 06), and this run exists so that it is spent on work that has
already survived its stated criteria.
