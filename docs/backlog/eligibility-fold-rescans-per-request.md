# The eligibility fold rescans the whole journal once per request

**What.** `_eligible_requests` (`agent/castle`) calls
`_resumable_answers` once for every request that already carries a
result, and each of those calls walks all records again — once to find
blocking questions, once for claims, once for answers. The cost is
requests × records per dispatch sweep, where every other part of the
fold is linear.

**Why it matters.** Nothing else in this system runs on a timer *and*
grows monotonically. Dispatch sweeps on every journal write plus a
one-minute backstop (`modules/agent`), so this cost is paid constantly,
forever, on a journal that only ever appends — the append-only property
that makes the records trustworthy is the same one that makes a
quadratic fold over them a slow leak rather than a one-off. It is also
invisible while it is small: nothing reports how long a sweep took, so
the first symptom would be a resident noticing their machine is busy
every minute.

**What we already know.** Measured, not estimated, during task 0023's
implementation: **117 ms for a synthetic journal of 2000 records / 500
errands**, all of them already resulted, which is the worst case for the
short-circuit (`rec.id not in answered or _resumable_answers(...)` skips
the call entirely for an unworked request). Method: build the journal
with `render_record`, `load_all` it, and time `_eligible_requests` alone.
Scaling is requests × records, so ~20k records with ~5k errands lands in
the seconds-per-sweep range.

**One cheap half of this was already taken, and the measurement above is
now pessimistic for the case it described.** A later review pass in the
same task moved the two dict-lookup exclusions — the watermark's `refs`
and the `filed-during-turn` stamp — *ahead* of `_resumable_answers` in
the `and` chain, so a request excluded by either never reaches the scan.
That was worth doing precisely because the scenario that made the
original number alarming is a restored pre-dispatch history, where every
request carries a result **and** is named in the watermark's refs: the
fold used to run for all of them and discard the answer, once a minute,
forever. Re-measured on the identical 2000-record journal: **1 ms when
the watermark excludes every request, 130 ms when it excludes none.**
So the debt that remains is the honest one — a journal of live errands,
each with a result and none excluded, still pays requests × records per
sweep — and the pathological restored-history case is gone. `lease_is_held`
deliberately stays last: it is the only condition costing a syscall.

Two things keep this from being urgent. `load_all` already re-parses
every file in the journal on every sweep, so at the sizes where this
fold hurts, file I/O and parsing dominate anyway — this is not a
uniquely new cliff, and fixing it alone would not make a large journal
fast. And 0021's own precedent applies: it declined a concurrency knob
"before any evidence that serial dispatch is actually a bottleneck," and
117 ms on a journal larger than the reference host will see for years is
not that evidence.

The remaining fix, if it is ever wanted, is already modelled in the same
function: hoist the blocking-question-to-root-request map and the spent
set out of the per-request call and compute them once per sweep, the way
`_requests_with_results` is already hoisted. Reordering bought what
reordering could; hoisting is what is left. That changes
`_resumable_answers`'s signature, which `run_worker_turn` also calls
(deliberately, so a hand-run `castle work` resumes exactly what a
dispatched turn would — `docs/tasks/0023-resume-cold.md` §7), so the two
callers have to stay on one fold whatever shape it takes.

**Open questions.** Is the answer an index built per sweep, or a read
cache over the journal that every fold shares — and if the latter, what
invalidates it, given the journal is written by other processes? At what
journal size does this stop being theoretical, and should a sweep report
its own duration so that size is observable rather than guessed at? Does
a journal that has grown past that point want archival (a `castle`
notion of a closed errand whose records no fold walks) instead of a
faster fold — which is a records question, not a performance one?
