# A deferred proposal cannot be revisited

*Found by the cross-model review of `docs/tasks/0025-approval.md`
(Codex CLI, pass 1), which caught the surface promising the opposite.
The false promise was fixed on that branch; the design question it
exposed was not, and is what this entry is for.*

**What.** `defer` is terminal. Pressing `d` on a proposed change writes
an answer carrying `decision: defer`; `_pending_questions`
(`agent/castle-modal`) excludes every question named by any answer's
refs, so the change leaves the review list; and `file_answer`'s
`already_answered` guard (`agent/castle`) refuses a second answer to
that question forever. A resident who sets a change aside and later
wants it has no route back to it. Their only remedy is to file the
complaint again and let a worker re-propose.

**Why it matters.** The terminality is coherent and was not an
accident — `reject` says *this change is wrong*, `defer` says *I am not
deciding this now*, and both are closed states that read differently to
a later reader and to `docs/tasks/0026`, which must honour approvals
only. `docs/backlog/approval-channel-has-no-transfer-of-control-strategy.md`
grounds `defer`'s value in exactly that: it is "an attributable,
recorded way to say 'not now' — distinguishable, unlike silence, from
never having looked." Attribution, not revisitability.

But the word does not mean that to a resident. To defer something in
ordinary English is to postpone it, and postponing implies it comes
back. 0025 shipped a confirmation that said so out loud — "you can come
back to it from the same list later" — which was false, and which no
reviewer inside the model family caught across the task's own
verification. That a competent writer produced that sentence *from the
implementation* is the finding: the vocabulary invites the reading, so
the next surface built on `defer` will invite it again.

**What we already know.**

- Making `defer` non-terminal is not a small change. It needs a way to
  record a non-decision **without consuming the one answer slot**,
  because the one-answer rule is load-bearing:
  `docs/backlog/answer-amendment-semantics.md` is the standing entry on
  it, and 0022 and 0023 each declined to reopen it for the same stated
  reason — "which answer governs" is a real design question and
  improvising it as a side effect of shipping something else is how a
  second source of truth gets built by accident. This entry does not
  reopen it either.
- The obvious shape, if it is ever wanted: a deferral is not an
  `answer` at all but some other record refing the question, leaving the
  question genuinely pending and the eventual approve/reject still the
  one and only answer. That is a record-model change and it partly
  departs from the human's decision that this task reuse `question` +
  `answer` rather than grow the record-type tuple
  (`docs/tasks/0025-approval.md`, and the decision log for 2026-08-20).
  It should be decided deliberately, by the resident whose authority
  vocabulary it is, not folded into an unrelated task.
- The cheap alternative is to leave the mechanism alone and fix the
  **word**. If `defer` is permanently a closed state, a name that does
  not promise a return trip ("set aside", "pass", "not this one") costs
  one string and no design. 0025 already moved the status-surface label
  in this direction — it reads "you set this aside" rather than
  "deferred" — so half of this has been done once already, which is
  itself evidence the word was pulling the wrong way.
- Do not treat "add a way to list closed proposals" as the fix. Being
  able to *see* a deferred change is not being able to *decide* it, and
  a list that shows an undecidable item next to decidable ones is the
  more confusing surface, not the less.

**Open questions.**

- Is terminal `defer` actually the wrong behaviour, or only the wrong
  name? Nobody has asked a resident. The whole case for changing the
  mechanism rests on a reading of the word rather than on an observed
  need to un-defer something.
- If a deferred change should come back, what brings it back — the
  resident going looking for it, a re-proposal triggered by the same
  complaint recurring, or a timer? The third is a transfer-of-control
  strategy and belongs with
  `docs/backlog/approval-channel-has-no-transfer-of-control-strategy.md`,
  which argues that channel-level move is router work rather than
  approval-surface work.
- Does 0026 need to care? An applier that honours approvals only is
  unaffected by any of this. It becomes relevant only if a deferred
  proposal can later become approved, which is precisely the change in
  question.
