# The switch classifier over-approximates at one edge and is blind at another

**What.** `docs/tasks/0067` decides whether an approved switch runs
under the resident's live session by comparing the unit files of the
generation this machine is running against the generation it approved:
`<toplevel>/etc/systemd/system` and `<toplevel>/etc/systemd/user`,
entry by entry, by resolved store path (`agent/castle`,
`_unit_map`/`_changed_units`). A unit name whose path differs is
treated as a unit the switch would restart, and if it matches
`castle.agent.activation.sessionUnits` the switch is staged for the
next boot.

Two edges, in opposite directions.

**It over-approximates.** Store-path inequality does not prove a
restart. `switch-to-configuration` parses the unit and honours
`X-RestartIfChanged=false`, `X-StopIfChanged`, `RefuseManualStop` and
their neighbours; a unit whose file changed in a way it declares
irrelevant is left alone. Castle stages anyway. The cost is a reboot
the machine did not need, and it is the deliberate direction — every
uncertainty falls on the side that cannot break a session — but it is
not free, and a resident who watches it stage more than they like has
only the blunt instrument of shortening `sessionUnits`.

**It is blind to churn with no unit-file expression.** A
`systemd.tmpfiles` rule, an activation-script snippet, an
`environment.etc` file some running process re-reads: none of those
change a unit file, so none of them stage. Those switch live, exactly
as they did before 0067. The motivating incident rode
`home-manager-<user>.service`, which is a unit and is caught; nothing
says the next one will.

**Why it matters.** Both edges are the kind of thing that is invisible
until it costs something. The first shows up as "why does this need a
reboot", the second as a repeat of 2026-09-06 through a door 0067 did
not close.

**What we already know.** The oracle `switch-to-configuration
dry-activate` would close the first edge — it reports what would
actually be restarted rather than what changed — and 0067 §A.1 records
why it was not used: in this flake's pin, its system dry run exits at
`main.rs:2187`, before the loop that spawns the per-user switch, so it
never reports user-unit churn at all; and reaching it at all costs a
third privileged unit and a widening of the polkit grant, for a
read-only query. A design that used both — the plan where it is
informative, the comparison where the plan is blind — is available and
was scoped out rather than ruled out.

**What would decide it.** Watching the default stage real switches on
a real machine for a few weeks, which nothing has done yet
(`docs/backlog/activation-is-not-proven-on-a-real-vm.md`). If it
stages almost everything, the first edge is the problem and the plan is
worth the privilege. If it stages rarely and the right things, neither
edge is worth code.
