# The worker tenant's working directory is inherited, not declared

**What.** `castle work` spawns the worker tenant with `subprocess.Popen`
and passes no `cwd`, so the tenant inherits whatever directory `castle
work` itself was started in. Under the dispatch unit that is `%h`, the
resident's home directory.

That directory is not a detail of tidiness. A headless `claude`
confines every file read and every file write to its session's working
directories — the primary working directory plus anything passed with
`--add-dir` — and applies that check independently of the permission
rules, so no allow rule can reach outside it and no deny rule is needed
inside it. The tenant's read surface is therefore the whole home
directory, set by an inherited value nothing states on purpose.

Task 0047 made the *additions* to that surface explicit: the harness
now passes `--add-dir` for each directory the contract names it must
read. It deliberately did not touch the inherited base, because
narrowing it means deciding what the tenant's working directory should
be and changing how `castle work` spawns it — a design question, not a
flag.

**Why it matters.** Two things follow from the base being accidental.
The obvious one is breadth: a seat whose contract names six files and
two checkouts can read every file the resident owns. The subtler one is
that the boundary moves without warning. A resident who runs `castle
work` by hand from inside a checkout gives that turn a different, much
narrower surface than the same errand gets from the dispatch unit —
including, potentially, one that cannot reach the deliverable paths at
all. The refusal 0039 installed catches that case loudly, which is the
only reason it is not already a live bug.

**What a fix would have to decide.** Whether the tenant's working
directory is the mechanism checkout, the private checkout, an empty
scratch directory it owns, or the state directory; what happens on a
turn where the relevant root is unconfigured; and whether the sandbox
declaration 0039 wrote should then name the working directory rather
than `$HOME`, since that is what it has always really meant. Any of
those is a smaller surface than today's; picking one is the work.
