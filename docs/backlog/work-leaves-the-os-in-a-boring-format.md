# Work leaves the OS in a boring format

**What.** When the finding outbox exists (see
[[a-framework-defect-found-by-a-worker-has-no-outbox]]), what it emits
is a contract with whatever agentic coding harness the resident runs —
and the 2026-09-01 deliberation settled the contract's character
before its contents: **boring, and a preference rather than a
standard.** A work item is a file — a `Key: value` header (`Title:` at
minimum), a blank line, a markdown body that becomes the working
agent's brief — landing in the target repo's conventional layout
(`docs/backlog/` for deferred items, a task queue directory for
actionable ones). Boring enough that a bare Claude Code session
reading the directory is a valid harness; that is the floor a brand-new
resident starts from before she has any harness at all. Which harness
tends a resident's queues, and where they live, is *her* declaration
in *her* Chevaline profile — this repo never names one.

**The example-profile half.** The same pattern this repo already uses
for machine configuration (`nixosConfigurations.example`, placeholder
resident) extends to the profile: ship a `chevaline-example/` with a
placeholder resident whose work section points at the conventional
locations, for a new resident to fork and fill — an example to copy,
never a default that silently applies. Public mechanism demonstrating
the shape; private configuration always authored by the person.

**What speccing looks like.** One paragraph of format documentation at
the outbox's emission site, the example profile, and restraint: no
schema document, no versioning, no registry. If a second resident's
harness ever chokes on the format, that adoption pressure — not an RFC
— is what promotes the paragraph to something specced.
