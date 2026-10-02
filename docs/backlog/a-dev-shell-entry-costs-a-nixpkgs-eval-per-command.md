# A dev-shell entry costs a nixpkgs evaluation per command, and agents pay it in loops

**What.** `nix develop --command <cmd>` re-evaluates the project flake —
nixpkgs input and all, at roughly 2 GB peak (the figure the 2026-09-06
investigation measured for a nixpkgs evaluation, carried over from
`an-agent-workload-can-thrash-the-host.md` and not re-measured for the
flake in this incident — a brief sizing a detector threshold or a
memory bound off it measures first) — on every invocation whose source
tree changed since the last one, because the evaluation cache keys on
the whole dirty worktree, not on `flake.nix`/`flake.lock`. An agent's
edit-then-test loop changes a file every iteration, and each Bash call
is a fresh shell, so "enter the dev shell" compiles to paying the full
evaluation per command. On 2026-10-02 a session in a flake project
elsewhere on this host — not this repo, whose flake deliberately has no
devShell (task 0029) — ran `nix develop --command python ...` thirteen
times in about seventeen minutes against a tree it was actively
editing, concurrent with a second, unrelated session whose own load was
ordinary; at 15:06 systemd-oomd found memory and swap past 90% and
killed the resident's session scope — 634 processes, both sessions, the
whole desktop (the kill-granularity problem
`an-oomd-kill-takes-the-whole-desktop.md` already carries).

**Why it matters.** This is the second memory-exhaustion incident with
the same root shape — per-command nixpkgs evaluation inside an agent
loop — after 2026-09-06's `nix shell nixpkgs#...` hang
(`an-agent-workload-can-thrash-the-host.md`). The first fix banned one
spelling and declared the missing tool; the trap itself survived under
a different spelling, and it will survive under the next one too,
because the defect is the default: on a host dedicated to embedding
agentic AI, the standard way to run a project command is one no agent
can use safely in a loop. The incident project's own agent guidance
says "`nix develop` provides the toolchain" — correct for a human with
a persistent terminal and a resource bomb for an agent. The resident's
direction (2026-10-02, in session, prompted by the incident): if direnv
is the right mechanism, it becomes the default for every host this
project builds — dogfooding on the xps9370 is not the scope — or else
`nix develop` comes off the table for agent work entirely. Stated
against this entry's own criticism of the first fix: direnv covers only
the dev-shell spelling — `nix shell nixpkgs#...` and `nix run` evaluate
per command just the same and stay guidance-banned, the identical
one-spelling weakness. What makes this round different is the detector,
not the guidance: the eval-storm check below watches nix-daemon
connections and is indifferent to which spelling raises the storm.

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
loop fell into), loads the cache in milliseconds, and pins the dev
shell against garbage collection. One claim an earlier draft of this
entry got wrong, caught by cross-model review on its PR: the standard
direnv bash hook fires via `PROMPT_COMMAND`, which interactive shells
evaluate and non-interactive ones — including an agent's Bash calls —
do not. Enabling direnv host-wide therefore does not, by itself, load
the environment in the exact shells this entry is about. The cache is
still the fix; the delivery into non-interactive shells is a design
decision the spec must make: `direnv exec <dir> <cmd>` as the stated
invocation, an `eval "$(direnv export bash)"` line in shell init that
non-interactive agent shells actually source, or whatever direnv
integration the agent harness itself offers — verified against a real
agent Bash call, not assumed. A second gap the same review round
surfaced: direnv has a mandatory authorization step — on a fresh clone,
and again whenever `.envrc` changes, nothing loads until someone runs
`direnv allow`; neither the shell hook nor `direnv exec` bypasses it.
So a checked-in `.envrc` does not by itself opt a project in, and the
failure it leaves is silent in exactly the dangerous direction: an
agent in an unauthorized project falls back to whatever it would have
done anyway, which is the per-command evaluation this entry exists to
end. The spec must treat the authorization lifecycle as a constraint
with its own test — whether via `direnv allow` as a stated bootstrap
step, direnv's `whitelist` configuration for the resident's project
roots (a trust decision that belongs to the resident, per Principle
01), or something else verified to cover fresh clones and `.envrc`
edits. The mechanism split per Principle 01 is clean: enabling
direnv + nix-direnv (package plus shell hook) is public module material
with no hardware assumptions and nothing per-person — which module is
an open question below; a project opts in with a one-line `.envrc`
(`use flake`) in its own repo, which is outside this repo's reach, as
is rewording each project's agent guidance from "`nix develop` provides
the toolchain" to "the environment loads via direnv; never invoke
`nix develop --command` per command". One precedent to reconcile rather
than silently pass: task 0029 rejected a devShell for delivering this
repo's own tools because "a devShell only helps someone who knows it
exists", and that decision stands — host tools stay in
`systemPackages`. Project-scoped environments are the case 0029 did not
cover: every project pins its own package set, so `systemPackages`
cannot carry them, and direnv's automation answers 0029's
discoverability objection for this case — the environment loads without
the agent knowing to look, once the delivery and authorization
constraints above are actually closed. The workload-side bounds
(concurrency caps, `MemoryHigh=`) remain
`an-agent-workload-can-thrash-the-host.md`'s problem; this entry is
only about removing the per-command evaluation default.

**Open questions.** How the cached environment reaches non-interactive
agent shells (see the cross-model finding above) — the one question the
spec cannot leave open, since it is the incident's exact shape; whether
the shell hook belongs in `modules/dev` or `modules/home` (direnv's
hook is per-shell, and git identity precedent puts per-person config in
home — but this is mechanism, not identity);
whether `nix-direnv`'s cache location needs stating or the default is
fine; which detector the fixing brief lands — not whether: the
eval-storm check is mechanically possible, so under this repo's
incident-ships-its-detector rule the brief lands it or a detector at
least as strong, and the static direnv assertion alone does not
qualify, since it cannot see the storm recurring when delivery or
guidance fails; and where the guidance for
*other* repos' `.envrc` + CLAUDE.md changes gets tracked, since this
repo can fix the host default but not the projects that sit on it.
