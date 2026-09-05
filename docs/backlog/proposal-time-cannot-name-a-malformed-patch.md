# A refused proposal cannot say the patch was malformed

**What.** `PROPOSAL_OUTCOME_VALUES` has one refusal,
`refused-patch-stale`, and it covers both halves of what `git apply`
refuses at filing time: bytes git cannot read as a patch at all, and a
patch git reads fine and declines against this tree. The applier's own
vocabulary stopped conflating those on 2026-09-05
(`docs/tasks/0055-a-malformed-patch-is-not-a-stale-one.md`), and the
comment above `PROPOSAL_OUTCOME_VALUES` said this one would follow when
that landed. It did not.

**Why it matters.** It is the same defect 0055 removed from the
applier, one seat further in. A worker turn that produces an
unparseable patch writes a result saying "This change does not apply to
that checkout", and a resident reading it goes looking for what moved
in their repository — where nothing moved, because the patch was never
a patch. The record is also the *only* thing they get: a refused
proposal is not filed as a question, so this prose is the whole account
of a turn that produced nothing usable.

The two facts also want different things to happen next. Stale means
the world moved and the errand can simply be asked again. Malformed
means the turn did not do its job, and asking again without changing
anything produces the same bytes. Only one of those is worth a
resident's time.

**What we already know.** The applier's split is built and its prose is
written (`APPLY_FIRST_LINES`, `_APPLY_REFUSAL_REASONS` in
`agent/castle-modal`, the `apply-outcome` table in `agent/README.md`),
so the wording problem is largely solved once. `_patch_paths` now
distinguishes malformed bytes from an environment fault in separate
return slots (`docs/tasks/0056-an-environment-fault-is-not-a-malformed-
patch.md`), which is the mechanism a proposal-time split needs and does
not have to invent.

**Open questions.** Does the new value keep the applier's spelling
(`refused-patch-malformed`) verbatim, as `refused-patch-stale` does
today, and is that reuse still what keeps the two vocabularies from
drifting? Does a malformed proposal deserve a different filing decision
from a stale one — both are refusals that file no question, but only
one of them is evidence about the worker rather than about the world,
and `docs/tasks/0042-finding-outbox.md`'s lane exists for exactly that
kind of observation. And does the check need a second git call to tell
the two apart, or is `_patch_paths`' answer on the bytes `--check`
already refused enough?
