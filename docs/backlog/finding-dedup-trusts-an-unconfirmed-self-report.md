# Finding dedup in the worker contract trusts an unconfirmed self-report

**What.** `agent/castle-worker-claude` item 9 tells a resumed tenant not
to refile a gap finding if "the account in front of you says an
earlier turn on this errand already filed that finding." The account a
tenant can see is never the outbox's authoritative outcome — it is the
earlier worker turn's own result body, which item 8 tells every worker
to write ("say in your reasoning that you filed one") regardless of
what happens afterward. The outbox's real verdict is a separate
`finding-outcome` result (`_write_finding_result`,
`agent/castle:8118`) whose `refs` name the worker result, not the
request — so `render_continuation_packet` (`agent/castle:3805`), which
only folds results keyed on `refs[0] == request.id`
(`agent/castle:3991`), never renders it into a resumed tenant's stdin.
A tenant literally has no way to see whether the outbox actually filed
the finding, only whether an earlier worker *believed* it would.

**Why it matters.** If the outbox rejects a finding after the worker's
turn ends — checkout unconfigured, working tree dirty, any of
`_file_finding`'s other refusal paths — the worker's self-report still
says "I filed one," because that is what the contract instructs it to
write. A resumed tenant reading that account, per item 9's exception,
will skip refiling and the gap is gone for good: nothing else ever
notices it again, since item 9 also says not to save the finding for a
turn that may not come. A transient, fixable outbox fault (task 0043's
own commit "Keep an outbox fault from costing a turn its proposal"
addresses a sibling failure mode of the same feature) turns into a
silently and permanently dropped finding.

**What we already know.**

- Flagged by Codex's review of PR #81 (task 0043); confirmed by reading
  `_write_finding_result` and `render_continuation_packet` directly.
- Not fixable in prose alone. Task 0043 is deliberately prose-only in
  a single file ("This task changes prose only... No option, no record
  field, no CLI surface, no behaviour of `agent/castle`"), and the gap
  is structural: no contract wording can tell a tenant to check a
  record its own stdin never contains.
- Two shapes of fix seem plausible and neither is obviously right:
  making `render_continuation_packet` also fold `finding-outcome`
  results reached transitively through the worker result it refs, or
  changing the dedup instruction itself to not rely on confirmation
  the tenant structurally cannot get (e.g. duplicate filing is a
  cheaper failure than a silently lost one, so drop the exception and
  accept occasional duplicate findings on resumed turns).

**Open questions.**

- If the packet is taught to fold `finding-outcome` records, does it
  key off the worker result's own id (one more hop past `refs[0] ==
  request.id`), or does `_write_finding_result` need a second ref back
  to the request the way `_write_apply_result` was deliberately kept
  from doing? Its own docstring (`agent/castle:8131`) argues at length
  for *not* naming the request, for reasons tied to `closing_result`
  and the reaper — any fix has to not reopen that.
- Is silent duplicate filing (dropping the dedup exception entirely)
  actually cheap, or does a resumed errand with several turns produce
  enough repeat findings to itself become the kind of noise 0042's
  outbox was built to avoid?
- Should the worker's self-report instead be made honest about what it
  doesn't know — "wrote a finding to the outbox; outcome unconfirmed"
  — rather than "filed one," so the ambiguity in the prose disappears
  even before any mechanism change?
