# `castle record --refs` writes references it never checks

**What.** `castle ask`, `castle answer`, and `castle correct` each
resolve every `--refs` id against the journal before writing anything.
`castle record` — the generic writer underneath them — does not. It
writes whatever ids it is given.

**Why it matters.** The journal is append-only, so a dangling reference
is permanent: nothing can edit the record to fix it, and the remedy is
another record explaining the mistake. That is precisely the reasoning
the three resident-facing writers cite for validating first. `record` is
the one writer a **tenant** uses rather than a resident, which makes it
the least trustworthy caller in the system and the one left unchecked.

**What we already know.** Task 0023 raised the stakes without closing
the gap. It gives tenants a new reason to write refs at specific ids,
and its eligibility fold reads refs to decide which errand resumes. It
closed one narrow case at write time — `castle record --blocking`
refuses an empty `--refs`, because a blocking question nothing can
attribute to a request is a permanent silent dead end — and deliberately
did not generalize, to keep that diff about resumption. A `--blocking`
question with a non-empty but *dangling* ref is still writable today.

`castle validate` does check that every ref resolves, so the damage is
detectable after the fact. It is just not preventable at write time, and
nothing runs `validate` automatically.

**Open questions.** Does `record` resolve refs the way the other three
do, or is there a reason a tenant writing a forward reference should be
allowed? (No current caller needs one.) Should the check be a hard
refusal or a warning, given a tenant's stderr may go unread? Is this
better solved by making `validate` run as part of dispatch's sweep,
turning a write-time check into a continuous one — and if so, what does
the sweep do when it finds a bad record it cannot edit?
