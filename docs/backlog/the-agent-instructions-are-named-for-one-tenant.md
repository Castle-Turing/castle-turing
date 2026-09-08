# The agent instructions are named for one tenant

**What.** Requested by the resident, 2026-09-06. The repo's
agent-facing conventions live in `CLAUDE.md` — a filename that names
the current tenant, in a project whose Proposal 03 commits that
intelligence is "a tenant, not a structural member." The file's
*content* is already tenant-agnostic (conventions, hard rules, the
delegation contract); only its name assumes who is reading. The
cross-vendor emerging convention is `AGENTS.md` (adopted across
Codex, Cursor, Gemini-family CLIs and others), and this repo already
runs a second vendor's reviewer over its diffs — a worker from that
vendor looking for its briefing today finds a file addressed to
someone else.

**The precedent is already in the family.** Dovetail was born with
the target shape: `AGENTS.md` is the real file, and its `CLAUDE.md`
is an eleven-byte pointer (`@AGENTS.md`) using the harness's own
include syntax — Claude Code reads it transparently, other harnesses
read `AGENTS.md` directly, and there is exactly one source of truth.

**The cost, measured.** 145 files in this repo reference `CLAUDE.md`
by name — briefs, comments, test scripts, the tasks README, the
implement-brief skill. This is the citation-strewing problem
(`code-comments-accrete-the-reasoning-record.md`,
`tidying-a-brief-into-done-rots-its-citations.md`) wearing another
face: most of those references are in *records*, which stay as
written per the authority rule, so the sweep is smaller than 145 —
but the load-bearing current-state references (README, skill,
workflow files, CLAUDE.md's own self-references) must move, and
which references are which is the actual work.

**Fix direction, none chosen.** Dovetail's shape, applied here:
rename to `AGENTS.md`, leave a `@AGENTS.md` pointer at `CLAUDE.md`,
update current-state references, leave records as records. At spec
time, verify the pointer syntax against the then-current Claude Code
behavior rather than assuming this entry's snapshot — and decide
scope: this repo alone first, with emcee and the Chevaline render
target (`~/.claude/CLAUDE.md`, which is harness-specific by nature
and may legitimately stay vendor-named) as separate decisions.

**Open questions.** Whether the conventions the file carries about
itself ("a CLAUDE.md change always needs explicit approval") rename
with it or gain an alias; and whether the harness's memory files and
skills that name CLAUDE.md follow in the same pass or lag as
records.
