# test/handover — the claim-checker, and what it must refuse

`docs/tasks/0062-the-operator-handover.md` calls the claim-checker the
heart of that task's verification, so this directory is mostly about
what the checker *refuses*, not what it accepts.

## The two fixtures, and why there are two

`ledger.json` and `handover.md` are the golden test the brief names: the
real week of 2026-09-01 through 2026-09-05, read out of git and the
forge by `tools/handover-ledger.py`, and the handover
`tools/handover.sh` generated from it. Both are frozen. The generating
half ran once, by hand, against a live forge and a model; nothing in CI
re-runs it, because CI has neither.

`synthetic-ledger.json` and `synthetic-handover.md` are invented. The
golden ledger happens to hold forty merged pull requests and not one
open, red-and-unmerged, or archived-brief case, so it cannot exercise
half the checker. The synthetic one is built to: an open pull request, a
merge over a failing gate, a brief in the queue and a brief in the
archive, a journal that resolves. Every file in `rejects/` is a
one-line mutation of `synthetic-handover.md`, which is why `run.sh`
checks that the unmutated version still passes first — if it did not,
every reject below it would be proving nothing.

## The rule the fixtures depend on

`tools/handover-check.py` is a pure function of (ledger, handover). It
reads no git, no forge, no working tree — `run.sh` asserts this by
running it from a temporary directory that is not a repository. That is
what lets a frozen fixture keep meaning the same thing while the repo
underneath it moves: briefs get swept into `docs/tasks/done/`, branches
get deleted, pull requests collect comments, and none of it disturbs a
test about whether a handover's claims matched a ledger.

## Adding a reject fixture

Mutate `synthetic-handover.md` minimally, and state the violation code
the mutation must provoke in an HTML comment on the first line:

    <!-- expect: C-STATE — a merged-PR line whose PR is open -->

`run.sh` asserts on that code, not merely on a nonzero exit. A fixture
that failed for some *other* reason would otherwise look exactly like a
working check, which is the failure mode this whole surface exists to
make impossible elsewhere.

## What is not tested here

`tools/handover-ledger.py`'s reading of the forge. It needs `gh`, the
network and a real repository's pull-request history; this harness has
none of those on purpose. Only its parseability is checked. The ledger's
own fidelity is instead established the way the brief asks — by the
resident reading the golden handover cold and trying to catch a claim
the checker passed that the ledger contradicts.
