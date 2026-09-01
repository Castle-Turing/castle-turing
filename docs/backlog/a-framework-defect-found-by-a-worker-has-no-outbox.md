# A framework defect found by a worker has no outbox

**What.** Three times on the first night of live dispatch
(2026-08-31/09-01), a worker turn correctly diagnosed something wrong
or missing in the *framework* — a feature with no option surface (LRU
workspace cycling), and two defects in the worker plumbing itself
(deliverable files it could not write; a stale state directory that
produced false anomalies) — and had nowhere to send the finding. The
contract's honest dead-end ("say so and stop, having proposed
nothing") puts the diagnosis in a result record's prose, where the
only reader is the resident, and the only way it reaches
`docs/backlog/` is a human carrying it there through a development
session. The resident's stated goal is the opposite: the system
absorbs what dogfooding finds, with the human approving rather than
chauffeuring.

**Why it can wait, briefly.** Each finding did reach the repo tonight
— but through the exact manual channel this project exists to retire,
and that channel does not scale past a patient founder.

**What speccing looks like.** Probably a `finding` output lane beside
the diff: the worker writes a draft backlog entry (already the shape
its reasoning naturally takes), the router routes it like a proposal
— the resident approves it in review mode — and an approved finding
becomes a file in the framework repo via a seat that owns a mechanism
checkout and a PR, keeping the existing rule that no worker touches
the development tree directly. What the outbox emits is settled separately —
[[work-leaves-the-os-in-a-boring-format]] — so this entry owes only the
lane, not the format. Overlaps deliberately with
[[mechanism-proposals-are-approvable-but-unapplyable]] (that entry is
about *diffs* targeting mechanism; this one is about *reports*), and
the two should probably be specced together.
