# A tenant can strip the environment variable both write guards depend on

**What.** Two guards in `agent/castle` key off `CASTLE_WORKER_CLAIM`
being present in the environment: the `filed-during-turn` stamp on a
request written mid-turn (task 0021), and the outright refusal of an
`answer` written mid-turn (task 0023). Both are applied inside
`write_record`, the single choke point every record passes through.
Neither survives a tenant that runs `env -u CASTLE_WORKER_CLAIM castle
...`, or that clears the variable any other way before invoking the CLI.

**Why it matters.** When the stamp was the only guard, the stake was
spend: a tenant that stripped it could file requests that started
themselves, wasting model calls. Task 0023 raised the stake. The answer
refusal is now the mechanism enforcing a Proposal 05 guarantee — that
inference may open a question but only the resident may close one — and
a guarantee that a tenant can opt out of by unsetting a variable is a
convention, not a boundary. A seat that answers its own question retires
it before the resident ever sees it, and every surface then reports the
question as closed.

Worth being precise about the threat model rather than alarmed: the
tenant is a model this system chose to run, not an attacker. The realistic
path is not malice but a model that reads something — a repo file, a
fetched page, its own earlier output — and concludes that clearing an
environment variable is a reasonable way to accomplish what it was asked.
The design's own answer to that shape of problem elsewhere (the packet's
nonce boundaries, task 0023) was to make the guarantee hold by
construction rather than by the tenant's cooperation.

**What we already know.** The guards are correctly placed for what they
can do: `write_record` is the one function every writer reaches, which is
why 0021 put the stamp there rather than in `cmd_ask`, and 0023 put the
refusal beside it. The gap is not the location, it is that process
environment is inherited state a child can edit. The claim id has to reach
the tenant somehow, because the tenant legitimately needs it to attribute
its own writes.

Note also that stripping the variable is not free to the tenant: its
own records lose the claim attribution the environment carries, so a
stripped write is visible in the journal as a record with no claim link
where its siblings have one. Nothing looks for that today.

**Open questions.** Is there a channel for the claim id that a child
cannot edit — a file descriptor passed to the tenant, a lease the CLI
re-derives from `$XDG_RUNTIME_DIR` rather than being told, or the CLI
inferring "I am inside a turn" from the live lease instead of from the
environment? Would deriving it from the lease actually close the hole, or
just move it? Should the journal gain a check that flags records written
during a turn with no claim attribution — turning an unenforceable
prohibition into a detectable one, which the weekly audit could read? And
is detection the honest goal here rather than prevention, given the
resident owns the machine and any guard is ultimately advice to a process
running as them?
