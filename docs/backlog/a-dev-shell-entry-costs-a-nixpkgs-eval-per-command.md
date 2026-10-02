# A dev-shell entry costs a nixpkgs evaluation per command, and agents pay it in loops

**What.** `nix develop --command <cmd>` re-evaluates the project flake —
nixpkgs input and all, roughly 2 GB peak — on every invocation whose
source tree changed since the last one, because the evaluation cache
keys on the whole dirty worktree, not on `flake.nix`/`flake.lock`. An
agent's edit-then-test loop changes a file every iteration, and each
Bash call is a fresh shell, so "enter the dev shell" compiles to paying
the full evaluation per command. On 2026-10-02 a session in a flake
project ran `nix develop --command python ...` thirteen times in about
twenty minutes against a tree it was actively editing, concurrent with
a second session; at 15:06 systemd-oomd found memory and swap past 90%
and killed the resident's session scope — 634 processes, both sessions,
the whole desktop (the kill-granularity problem
`an-oomd-kill-takes-the-whole-desktop.md` already carries).

**Why it matters.** This is the second memory-exhaustion incident with
the same root shape — per-command nixpkgs evaluation inside an agent
loop — after 2026-09-06's `nix shell nixpkgs#...` hang
(`an-agent-workload-can-thrash-the-host.md`). The first fix banned one
spelling and declared the missing tool; the trap itself survived under
a different spelling, and it will survive under the next one too,
because the defect is the default: on a host dedicated to embedding
agentic AI, the standard way to run a project command is one no agent
can use safely in a loop. Project guidance that says "`nix develop`
provides the toolchain" is correct for a human with a persistent
terminal and a resource bomb for an agent. The resident's direction
(2026-10-02, in session, prompted by the incident): if direnv is the
right mechanism, it becomes the default for every host this project
builds — dogfooding on the xps9370 is not the scope — or else
`nix develop` comes off the table for agent work entirely.

**How it would have been caught sooner.** The signal existed and
nothing read it: nix-daemon logged a fresh client connection roughly
every ninety seconds for seventeen minutes while memory pressure
climbed. An eval-storm check — more than N nix-daemon client
connections from interactive sessions within M minutes — would have
named the pattern before exhaustion, and is the honest detector for
recurrence under whatever spelling comes next. Once the fix lands, the
cheap static regression check is a VM test in the mold of the oomd
liveness check: assert that a host importing the dev module has direnv
with nix-direnv wired into the shell, so the default cannot silently
revert.

**What we already know.** direnv with nix-direnv caches the evaluated
environment per project, re-evaluates only when `flake.nix` or
`flake.lock` change (source edits are ignored — exactly the hole the
loop fell into), loads in milliseconds in every fresh shell including
each agent Bash call, and pins the dev shell against garbage
collection. The mechanism split per Principle 01 is clean: enabling
direnv + nix-direnv (package plus shell hook) is public `modules/dev`
material with no hardware assumptions and nothing per-person; a
project opts in with a one-line `.envrc` (`use flake`) in its own
repo, which is outside this repo's reach, as is rewording each
project's agent guidance from "`nix develop` provides the toolchain"
to "the environment loads via direnv; never invoke
`nix develop --command` per command". The workload-side bounds
(concurrency caps, `MemoryHigh=`) remain
`an-agent-workload-can-thrash-the-host.md`'s problem; this entry is
only about removing the per-command evaluation default.

**Open questions.** Whether the shell hook belongs in `modules/dev` or
`modules/home` (direnv's hook is per-shell, and git identity precedent
puts per-person config in home — but this is mechanism, not identity);
whether `nix-direnv`'s cache location needs stating or the default is
fine; whether the eval-storm detector is worth building now or noted
as the recurrence check and deferred; and where the guidance for
*other* repos' `.envrc` + CLAUDE.md changes gets tracked, since this
repo can fix the host default but not the projects that sit on it.
