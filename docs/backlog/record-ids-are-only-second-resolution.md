# Record ids sort by a random suffix within the same second

**What.** `make_id` builds an id as `<UTC stamp>-<type>-<random suffix>`
with the stamp at **one-second** resolution. Sorting records by id is
therefore chronological only across seconds; within one second the type
name and then the random suffix decide, which is to say the order is
arbitrary and not reproducible between runs. Every surface that folds
the journal sorts by id somewhere.

**Why it matters.** This is not hypothetical and it is not rare. It has
now produced a defect in **four separate tasks**:

- 0023 — two records written in the same second by a scripted caller
  ordered by suffix, not by which was written first.
- 0024 — the same, in a different fold.
- 0025's own harness — two proposals filed inside one second made
  "press 1 and get the older one" a coin flip; handled there by
  computing the index from the pendingness fold and asserting it,
  rather than by hardcoding.
- 0025's status overlay — `_errand_state` sorts an errand's proposals
  by full id and takes `proposals[-1]` as "newest"
  (`agent/castle-modal`). Two turns finishing on one errand within a
  second make that a coin flip, so the overlay can print the verdict
  belonging to the *other* proposal. Found by the cross-model review,
  round 3. Accepted as a documented limit there rather than patched,
  because it is this problem and not that line.

Each was fixed where it was found. None fixed the cause, and the fixes
do not compose: `_errand_state` already contains a careful, correct
workaround for this exact hazard **twelve lines above** the line that
then falls into it — it compares the timestamp half of the id rather
than the whole, and documents why at length, and then the adjacent
selection sorts by the whole id. A hazard that defeats an author who
has just finished writing a paragraph about it is a hazard in the id
format, not in the author.

**What we already know.**

- The suffix exists for uniqueness, not ordering, and it succeeds at
  that. Nothing here is an argument for removing it.
- Sub-second resolution in the stamp would fix the common case and not
  the general one: two records genuinely written in the same
  microsecond, or by two processes, still tie. What a fold usually
  wants is not wall-clock precision but a **total order the journal
  itself defines**.
- The journal is append-only and file-per-record, so there is no
  natural sequence number today. Adding one is a schema change and
  interacts with `castle record`'s unguarded write path, which can
  already produce records the write path would not.
- Lineage is *not* a substitute. `refs` gives a partial order — a
  decision comes after the change it decides — and several of the
  four defects above were in folds where lineage was exactly what was
  being reconstructed. Where a `refs` edge exists it should be
  preferred to any timestamp comparison, and 0025's decision-versus-
  result tie-break already reasons this way ("a decision can only
  exist after the change it decides, so when the two share a second,
  the decision is the later event"). That reasoning is right and does
  not generalise to two siblings with no edge between them.
- A cheap partial mitigation, if the format is left alone: a single
  shared helper for "order these records" that folds may not bypass,
  so the correct comparison is written once instead of rediscovered
  per surface. That would have prevented the 0025 overlay defect
  outright.

**Open questions.**

- Is the fix a finer stamp, a monotonic sequence in the id, a
  tie-break rule applied consistently, or a shared ordering helper
  that makes the question moot at every call site?
- If a sequence number is added, what assigns it, given the journal
  has no writer of record and `castle record` is a back door? A
  counter derived from the directory listing re-introduces the same
  race it is meant to fix.
- Do existing records need to remain sortable alongside new ones? An
  append-only journal cannot be migrated, so whatever lands has to
  read a mixed directory correctly and forever.
- Should a fold that genuinely cannot order two records say so rather
  than pick? Several of the four defects were surfaces confidently
  reporting one of two possibilities; "two changes finished at once"
  may be the honest rendering, and it is cheaper than a format change.
