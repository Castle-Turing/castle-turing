# The example profile has no work section

**What.** `docs/tasks/0042-finding-outbox.md` shipped the outbox and
the boring work-item format it emits, and deliberately left half of
the entry it promoted undone. That half: the same pattern this repo
already uses for machine configuration
(`nixosConfigurations.example`, a placeholder resident) extends to the
resident's *profile*. Ship a `chevaline-example/` with a placeholder
resident whose work section points at the conventional locations — a
`docs/backlog/` for deferred items, a task queue directory for
actionable ones — for a new resident to fork and fill.

**Why it matters.** The outbox now lands a finding as a file in a
checkout, and which harness tends a resident's queues, and where they
live, is *her* declaration in *her* profile. This repo never names
one. Without an example to copy, a brand-new resident's floor is
reading `docs/tasks/0042` to work out what shape the thing she is
supposed to declare has — which is the same "installed system is not
discoverable" problem one layer up.

**Why it can wait.** It costs a resident who already has a profile
nothing, and there is exactly one of those. The pressure arrives with
the second resident, which is also the pressure that would promote
the format paragraph to something specced.

**What speccing looks like.** An example to copy, never a default that
silently applies — public mechanism demonstrating the shape, private
configuration always authored by the person. Same rule
`nixosConfigurations.example` already follows. See
[[installed-system-is-not-discoverable]] for the neighbouring version
of this problem.
