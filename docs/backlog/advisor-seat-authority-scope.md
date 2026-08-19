# A standing authority scope for advisor-seat sessions

**What.** A standing, constrained role for interactive thinking-partner
sessions — the kind that reads and discusses the repo with the
resident rather than executing a brief. The scope: read the whole
repo; write only to `docs/backlog/` (and draft briefs); work in its
own worktree on a branch off `origin/main`; merge only via PR, never
directly to `main`; scope all reasoning against `origin/main`, never a
local or stale ref. This entry itself was produced by a session
operating under exactly this scope, given by ad hoc instruction rather
than anything standing.

**Why it matters.** The scope already gets re-specified by hand each
time an advisor-seat session is started, which means it can also be
gotten wrong or left out by hand each time. Naming it once means a
future session — or a future person setting one up — starts from a
known-good default instead of reconstructing it from memory of how the
last one was framed. It is also, concretely, the first authority scope
of the kind the Chevaline profile schema exists to express: read
access, a narrow write allowlist, and a merge gate, stated once and
attached to a seat rather than typed into a prompt per session.

**What we already know.** `docs/backlog/authority-taxonomy-prior-art.md`
surveys when a fixed, category-based authority tier is defensible
versus when it needs to be computed per decision. Its verdict: a fixed
tier holds up where nobody is waiting, wait cost is near zero, and the
action is reversible by design. This scope is exactly that case — the
advisor seat's only externally visible output goes through a PR, and
nothing it does is irreversible or blocks anyone. That's why this
entry records the scope directly rather than waiting on the broader
taxonomy question to be settled first.

**Promotion condition.** The Chevaline loader/enforcement layer exists
within Emcee (or whatever ends up running an office-shaped seat) to
actually attach a profile-declared scope to a session and enforce it —
not merely document it in a prompt the way this scope has been applied
so far.

**Open questions.** Whether "advisor" is one profile or a family — a
session doing research and a session drafting backlog entries may
warrant different write allowlists even though both are read-everything,
write-narrowly. Left for whoever specs this against a real Chevaline
loader.
