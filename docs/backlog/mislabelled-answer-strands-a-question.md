# A mislabelled answer record strands the question it names

**What.** `file_answer` treats a question as closed if *any* record of
type `answer` names it in `refs`, whatever seat or provenance that
record carries. Since `docs/tasks/0023-resume-cold.md`,
`_resumable_answers` is narrower: only an answer carrying
`provenance: requested` and `seat: intake` — the pair `file_answer`
itself always writes — buys the errand a further worker turn. The two
folds now disagree about what an answer is, and a record that satisfies
the first but not the second leaves the question in a state with no
exit: `castle answer` refuses it as already answered, and no sweep will
ever resume the errand on the strength of it.

**Why it matters.** It is small and it is reachable. Nothing in the
system writes such a record — `file_answer` is the only answer path a
resident has, and `write_record` refuses an answer written from inside
a worker turn — so producing one takes a hand-written `castle record
--type answer` with an odd seat, or a tenant that defeated the
environment guard (`docs/backlog/env-stripping-defeats-write-guards.md`,
which is the world where this matters most). But the resulting state is
exactly the silent dead end task 0023 exists to remove, arrived at from
the other side: a question the resident is shown as closed, an errand
that will never continue, and no surface saying why.

**What we already know.** The narrowing was deliberate and should stay:
without it, a record the continuation packet honestly labels "NOT filed
through the resident's own intake path" could be the very record that
paid for the turn rendering it, and the spend half of the self-answer
guard would fall with the environment variable. The question is not
whether the fold should be strict but whether *pendingness* should use
the same test — and pendingness has more readers than resumption does:
`file_answer`'s duplicate guard, `castle-modal`'s answer picker, and
`_errand_state`'s "waiting on you" overlay all fold answers the loose
way today, and they were written before there was any reason to care
who wrote one.

**Open questions.** Should "is this question answered" mean "some intake
answer names it" everywhere, so a mislabelled record stops hiding a
question from the resident's picker — and if so, does that weaken the
duplicate guard it also powers, by letting a resident answer over a
planted record? Is the right fix instead at write time: refuse
`castle record --type answer` outright the way `--type correction` is
already refused, on the grounds that `castle answer` is the only
legitimate path and the back door has now cost two findings? And should
`castle validate` flag an `answer` record whose seat is not `intake`,
turning an unwritable-by-design shape into a detectable one?
