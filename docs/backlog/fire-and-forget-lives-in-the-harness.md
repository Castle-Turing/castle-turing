# Fire-and-forget lives in the harness, not in the system

**What.** The resident wants to hand off a task, stop thinking about
it, and hear back only when it is finished — for *any* task, not only
repo feature work. In their words: "The `/btw` affordance in claude
code solves the basic problem that I want to fire off lots of tasks
and usually only hear back when they are finished. We are solving that
by delegating feature work, but really it should be for any task." The
pattern is real and observed — feature work dispatched to background
sub-agents that reported on completion, so the resident kept issuing
new instructions without waiting — but it is a property of the tool
that session ran in, not of Castle Turing.

**Why it matters.** `docs/vision.md`'s core inversion is close to a
restatement of it: "The agent's default output is nothing. Its second
most common output is a completed action you only notice if you go
looking." A system whose founding document comes that close to naming
dispatch-and-be-told-later as its central pattern cannot currently do
it, and the resident gets it anyway from a vendor's session UI —
available only inside that session, only for work shaped like a repo
diff, gone with a harness change.

**What we already know.**

- **The vision states the inversion and names no mechanism.** Every
  concrete instance it goes on to give — mail handled, Slack
  prioritized, attention defended, open loops swept — is work the
  system initiates for itself. Resident-dispatched work being
  fire-and-forget too is implied there and specified nowhere.
- **Task 0009 built this pattern for one narrow channel.** Its goal is
  literally "press a key, describe a problem in your own words, walk
  away, and come back later to find out what happened." Read honestly,
  what exists is the front and back of that sentence and not the
  middle. Intake (`castle ask`, the modal's compose mode), the modal's
  status fold, a router with `notify` and `digest` channels, and a
  worker seat with a real tenant all exist. **Nothing dispatches.**
  `castle work REQUEST_ID` is invoked by hand;
  `docs/tasks/0015-filed-not-in-progress.md` records the resident
  discovering that no worker has ever run automatically on the
  reference host, via a status label reading "in progress" over
  untouched errands. `castle digest` is by hand too — scheduling
  deferred since 0008's non-goals (`agent/README.md`).
  File-and-forget exists; fire-and-forget does not: the plumbing can
  carry the promise, and nothing fulfils it.
- **Where the resident does have it sits badly with Proposal 03.**
  `docs/architecture.md` holds that no harness feature may be
  load-bearing, and its cost clause anticipates this case: "convenient
  harness capabilities must be reproduced as artifacts even when a
  harness offers them natively." That proposal's subject is seats and
  structure, so this is no literal violation — no record or schema
  depends on the harness. It is the same reasoning one level up, about
  an interaction pattern the vision calls the core inversion and the
  worker tenant's harness currently supplies.
- **The worker contract may not generalize.** It sits at the errand
  boundary — a `request` in; a `result` record, a diff against the
  relevant repo, and journal entries out — and proposes, never
  deploys. Many tasks a resident would fire off are not diffs.
- **How this differs from its neighbours.**
  `errand-resume-after-answer.md` is one break in the lifecycle: an
  answered question resumes nothing.
  `apprenticeship-has-no-mechanism.md` is the system asking the
  resident things — the opposite direction. This is resident-initiated
  dispatch, upstream of both: neither matters if nothing starts.

**Open questions.** What counts as a task the resident can fire and
forget — anything the agent layer can hold, or a narrower class? Is
the diff-producing worker contract the general shape, or one worker
among several? Who or what invokes a worker when a request lands, and
is dispatch a router decision, a new seat, or plumbing (a timer, a
watcher)? How does the resident see what is in flight without being
interrupted by it — is the modal's status fold enough? How do results
come back, and is the existing provenance rule (requested work must
reach the resident through a channel they will actually encounter)
already that answer? When a dispatched task needs a decision partway,
Proposal 05 says inference may open a question and only the resident
may close it — so does a blocked task wait, escalate, or abandon?
(`errand-resume-after-answer.md` holds part of that, to read alongside
rather than re-answer here.) And under all of them: does this extend
the errand model in `docs/architecture.md`, or replace it?
