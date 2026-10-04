Title: The memory kill lands on the build, not the session
Model: deep
Milestone: none — hygiene
Model-because: this brief transfers with its central decision open —
closing the high-to-max band versus a per-invocation sub-scope, and
whether PATH-shadowing `nix` host-wide is acceptable at all — so the
implementer is choosing an architecture, not following one. A
standard-tier implementer handed an unmade decision reliably picks
the nearest plausible shape and ships it without arguing the trade;
here the trade is the deliverable, and the wrong granularity
reproduces the incident on a later date with a bigger budget. Any
open question that needs the resident travels back up rather than
being answered in-branch.
Status: ready

# The memory kill takes the session, not the build

**What.** When a bounded terminal scope runs away, what dies is
everything in the scope, not the process that ran away. On
2026-10-03 a castle-turing session's local VM-test build loop pushed
its scope against its bounds (MemoryHigh=4G, MemorySwapMax=2G,
MemoryMax=6G — task 0085's options, values from the private layer);
the scope sat in the band between the throttle and the hard cap,
swap full, thrashing under reclaim, until systemd-oomd's slice
pressure rule killed all 42 processes in it — terminal, Claude
session, and every subagent — when the runaway was the nix
evaluation. The resident's direction (2026-10-03, in session):
descope the kill to the build, so a runaway evaluation dies alone
and the session survives to report it.

**Why it matters.** Losing a build costs a retry; losing the session
costs its context, its subagents, and the live diagnosis — the
surviving session is exactly the thing that could have named the
culprit while the pids still existed
([[a-crash-goes-uninvestigated]] is this cost, filed from an earlier
kill). As long as the kill lands on whole scopes, every eval storm
ends this way regardless of budget — a bigger budget only moves the
date.

**What we already know.** A hard cap alone demonstrably does not do
it: MemoryMax=6G was set on the killed scope and never fired,
because oomd wins the race — a scope throttled at MemoryHigh with
its swap allowance exhausted generates sustained reclaim pressure
long before RSS reaches the cap, and oomd kills leaf cgroups whole.
Closing the high-to-max band (MemoryHigh = MemoryMax) trades the
thrash window for the kernel's in-scope OOM kill, which takes the
cgroup's largest process by oom_score — usually the evaluation, but
a long-lived Claude process with a large heap could lose instead:
cheap, one private-layer line, not precise. The precise shape is a
sub-scope per nix invocation — wrap `nix` to run under
`systemd-run --user --scope` with its own MemoryMax, landing bound
and kill on exactly the build — but it has the same delivery problem
BASH_ENV solved for direnv (task 0083): nothing reaches an agent's
non-interactive bash unless the wrapper shadows `nix` on PATH for
every shell. Also load-bearing: evaluation runs in the client
process, inside the session scope; the build itself — VM boots
included — runs under nix-daemon's own system slice. The 2026-10-03
footprint was client-side evaluation, so the client half is the one
that matters here.

**Open questions.** Whether PATH-shadowing `nix` host-wide is
acceptable, and where the wrapper lives if so (beside the eval-storm
detector in modules/dev is the natural home). What bound a per-eval
sub-scope gets, and whether the parent scope keeps its own bounds
underneath it. Whether the cheap imprecise step — closing the
high-to-max band — is worth shipping while the wrapper is specced.
How a killed evaluation's death reaches the surviving session as
"your build hit its memory bound" rather than as a mysteriously
failed command.
