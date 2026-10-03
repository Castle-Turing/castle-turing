Title: A brief that already exists
Model: cheap
Model-because: it is a fixture, not work; nothing about it is a judgment.
Milestone: none — fixture

# A brief that already exists

Not work. This file exists so that the oracle slate's `numbers` rule is
checked against a directory with something in it: a number-allocation
check run against an empty directory cannot fail, and a rule that cannot
fail is the shape of defect `tools/reachability-check.py` exists for.

The oracle slate beside this directory therefore starts at 0002, and
`test/plan/run.sh` mutates a brief back to 0001 to watch the collision
get caught.

This directory is the oracle slate's `Tasks:` target rather than the
repository's real `docs/tasks/`, for one reason: numbers under
`docs/tasks/` keep being allocated, so a worked example checked against
them would start failing CI the day a real task reached its number — an
armed gate failing for a reason that is not the pull request's, which is
the incident `docs/tasks/0072-wire-the-outcome-log-and-its-redirects.md`
shipped a detector for.
