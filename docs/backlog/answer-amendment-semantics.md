# A question can only be answered once, and a wrong answer has no remedy

**What.** `file_answer` refuses a second answer to a question that
already has one (`agent/castle`'s `already_answered` guard): "a second
answer would leave two records." Nothing defines which answer would
govern if two existed, so the write path forbids the second rather than
answer the question. Decide the amendment semantics — whether an answer
can be superseded, which one governs the account afterward, and what
happens to work already done under the superseded one.

**Why it matters.** Task 0023 made an answered blocking question restart
its errand automatically, within seconds of the answer landing. So an
answer is no longer an inert note in the journal: it spends a worker
turn. A resident who answers wrongly now watches the system act on the
wrong instruction and has no way to stop or correct it — their only
remedy is a new request plus a `correction` recording that the system
was steered wrong. That was decided deliberately (0023 §6) and the
alternatives were weighed, but it leaves a real hole, and the hole gets
worse as more of the lifecycle runs on answers.

**What we already know.** This is the second deferral, not the first.
`docs/tasks/0022-answer-in-ui.md` §9 declined it and named the successor
task; `docs/tasks/0023-resume-cold.md` §6(b) declined it again and filed
this entry. Both declined for the same reason: "which answer governs" is
a genuine design question, and improvising an answer to it as a side
effect of shipping something else is how a second source of truth gets
built by accident.

Two adjacent facts a spec will need. First, `castle record --type
answer` is an unguarded back door — `cmd_record` refuses only
`correction` — so two answers to one question are already reachable
today, and 0023's eligibility fold deliberately tolerates them rather
than crashing. The invariant is enforced at one write path, not in the
schema. Second, 0023 considered and rejected a narrower version of this
— letting a second answer supersede while the first was still "unspent"
— because dispatch wakes within seconds of the answer file landing, so
the window is illusory and documenting it as an undo would be a label
that lies.

**Open questions.** Does a superseding answer re-open eligibility, and
if so is the errand's earlier resumed turn's output invalidated,
annotated, or left standing? Is the superseding record an `answer` with
a ref to the answer it replaces, or a new record type? Does the resident
model entry a `fact`-carrying question wrote get amended too, or is the
model's account allowed to diverge from the journal's? Should the
back-door second answer be closed at the same time, or does closing it
belong with the general `castle record --refs` gap? And is the honest
answer simply that amendment is out of scope for a system whose records
are append-only — in which case the remedy is a better-designed
*confirmation* before filing, which 0023 also considered and declined?
