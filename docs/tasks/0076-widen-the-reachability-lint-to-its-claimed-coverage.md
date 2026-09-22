Title: Widen the reachability lint to the coverage it claims
Model: deep
Milestone: none — hygiene
Model-because: the spec was a set of AST-level detection-logic changes
whose correctness and false-positive/false-negative direction had to
be reasoned about against the lint's own stated philosophy (crude but
never falsely accusing), and — as the implementation showed — tracing
the real repository's call graph to disposition every newly-enumerated
tool required judgment a smaller model would have gotten wrong in the
direction that matters least safely: inventing a marker to make the
lint go quiet.

## Why

The `/code-review` of PR #137 (task 0072) found four latent defects in
`tools/reachability-check.py` and `tools/outcomes/outcomes` that
survived verification — none an active failure, so they were
dispositioned to `docs/backlog/the-reachability-detector-has-coverage-gaps.md`
rather than fixed under review. That entry is this brief's source; it
was promoted here and deleted in the same commit that landed this
file. Three of the four make the reachability detector — itself the
"incident ships its detector" artifact for the tool-wired-to-nothing
class — narrower or more false-positive-prone than its own header
claims. A detector that overclaims its coverage is the quiet-day
failure one level up.

## Change 1 — string-argument callers are invisible

`code_only()` in `tools/reachability-check.py` stripped every STRING
token from a Python file, so a caller of the form
`subprocess.run(["tools/outcomes/outcomes", "derive"])` had its path
and subcommand removed before `invokes()` saw them — the lint would
report `derive` as an orphan for a command genuinely called, the
false-positive direction the module header claims to avoid.

**Implemented as:** an AST pass (`call_argument_strings`) collects the
source positions of string constants that appear as a call's direct
arguments, or one level inside a list/tuple/set literal that is itself
an argument. `code_only` keeps only those string tokens and still
drops every other one — comments, docstrings, bare expression
statements — so the load-bearing exclusion from task 0072 (the
module's own worked example must not rescue itself) still holds.

Fixtures in `test/reachability/run.sh`, "string-argument callers
(change 1)": a `tools/`-under Python file calling the tool via a
subprocess string list rescues the subcommand; a file that only
*mentions* the same invocation in a docstring or comment does not.

## Change 2 — single-command tools are never enumerated

`find_tools()` kept only files containing `add_subparsers`, exempting
every single-command tool and every `.sh` tool. If one lost its only
caller the lint would still print "all reachable."

**Implemented as:** `is_executable_tool` now admits `.py`, `.sh`, and
extensionless files. `entrypoints()` only `ast.parse`s a file when
`is_python_tool` says its suffix or shebang is Python — a `.sh` script
can never reach the parser. A tool with an argparse subcommand tree
keeps today's behavior; every other tool gets one bare entrypoint
(`()`, the empty command path), keyed by its path alone via the new
`spec_key` helper — `f"{rel} {' '.join(command)}"` would leave a
trailing space on an empty command, which would never match a marker
written as `<!-- invokes: tools/x/x -->`.

Fixtures, "single-command tools are enumerated (change 2)": a
single-command tool with no caller is flagged; the same tool named
directly by a workflow is clean.

### Real-tree consequence — corrected from this brief's original draft

The original draft of this brief predicted the widened lint would
newly flag "the operator-run sweep tools — `tools/foot-setting-sweep.sh`
at least." Running the widened lint against the real tree found five,
not one, and one of them is a self-referential case the draft did not
anticipate:

- `tools/font-sweep.sh`, `tools/console-font-sweep.sh`,
  `tools/foot-setting-sweep.sh` — on-demand, operator-run tools. Their
  `tools/README.md` sections are reference documentation (design
  rationale, why-this-shape), not an operating runbook a resident
  follows step by step, so adding an `<!-- invokes: -->` marker there
  would be exactly the "pass-the-lint ritual" this brief forbids —
  `tools/README.md` is the file the lint's own header names as the
  disqualified case, on purpose, because it lists every command by
  construction. No other document instructs running them. **Real
  orphans — left flagged, for the resident to rule on.**
- `tools/handover.sh` — same shape and same reasoning. Its own
  `tools/handover-ledger.py` and `tools/handover-check.py` are *not*
  flagged, because `handover.sh` (another tool under `tools/`) calls
  both directly — Change 2 does not disturb that. `handover.sh`
  itself has no caller anywhere but a test wrapper and reference
  prose. **Real orphan.**
- `tools/reachability-check.py` — the lint newly finds that it cannot
  see a caller for *itself*. `.github/workflows/reachability-check.yml`
  invokes `test/reachability/run.sh`, never the tool directly (see the
  Change 3 correction below); `test/` does not count by design. This
  is not a tool that could quietly lose its caller and go unnoticed —
  deleting it would break `test/reachability/run.sh` immediately — but
  the lint has no way to know that; it only knows what calls what by
  name, and nothing outside a test calls this one by name. **Real
  orphan**, structurally identical to the CLAUDE.md-boundary case named
  in Change 2's original text below, and left flagged for the same
  reason: restructuring `reachability-check.yml` to call the tool
  directly (instead of, or alongside, the test wrapper) is a CI-shape
  decision outside this brief's scope, not a lint-detection fix.

One tool from the original list resolved cleanly:

- `tools/codex-review.sh` — its owning step lives in `CLAUDE.md`
  (`tools/codex-review.sh` for the cross-model pass), which this brief
  said must never be edited to make the lint pass. It also, already,
  genuinely lives in `.claude/skills/implement-brief/SKILL.md`'s
  "Deliverables" checklist — a runbook a session actually executes
  step by step when closing out a task, not a reference table, and a
  file this brief's constraint does not cover. The marker was added
  there. **Resolved, no CLAUDE.md edit.**

So `test/reachability/run.sh`'s first assertion — the lint over this
repository — **fails** as landed, with exactly these five problems and
no others. This is the disposition this brief's own text calls for
("a tool with no caller and no owning step is a real orphan — say so
in the PR for the resident to rule on rather than papering it"), not
an oversight: the alternative was inventing operating documentation
that does not otherwise exist, purely to satisfy the lint, which is
the ritual this brief exists to rule out. The resident's options, none
taken here: delete a tool that turns out to be dead, write a real
runbook for one that is not (and mark it there), or accept the gap and
adjust the lint's own scope. `reachability-check.yml` will report red
on this branch and on `main` after merge until one of those happens.

## Change 3 — standalone checker scripts are not recognized as gates

The armed-gate/feeder rule only recognized a gate whose checker is an
argparse subcommand named `check`, missing standalone checker scripts
run directly from a workflow.

**Implemented as:** `is_checker(tool, command)` — a checker is either
an argparse subcommand path ending in `check` (unchanged) or, for a
bare entrypoint, a tool whose filename stem is `check` or ends in
`-check`. The feeder-citation validation (entrypoint exists, cited
file exists, cited file carries the marker) is unchanged; only what
counts as "a checker being run" widened.

Fixtures, "standalone checkers are gates too (change 3)": a synthetic
`*-check.sh` script run by a workflow with no feeder line is flagged;
with a feeder line citing a marked document it is clean.

### Real-tree consequence — corrected from this brief's original draft

The original draft named `tools/handover-check.py` run "from
`.github/workflows/check.yml`, the repo's own established pattern" as
the real-tree case this widened rule would newly catch, and said
`check.yml` would need a `# feeder:` line as a result. That premise
does not hold: `check.yml` runs `test/handover/run.sh`
(a 150-line fixture harness), never `tools/handover-check.py` directly
— the same is true of `reachability-check.yml` running
`test/reachability/run.sh` rather than `tools/reachability-check.py`,
and of `clarify-check.yml` running `test/clarify/run.sh`. Every
standalone-shaped checker in this repository is reached only through a
test wrapper, which is exactly the module header's pre-existing
"A NAMED GAP" — deliberately out of this lint's reach. Widening Change
3 to recognize the shape therefore fires on **zero** real-tree cases
today; the rule is not dead code, since a future workflow that invokes
such a checker directly (the way `outcomes-check.yml` already invokes
`tools/outcomes/outcomes check` directly) will be caught, but nothing
in the current tree needed a new feeder line. `check.yml`,
`reachability-check.yml`, and `clarify-check.yml` are all unchanged.

## Change 4 — the redirect command pays the network before the static check

`cmd_redirect` in `tools/outcomes/outcomes` resolved the forge author
(a `gh api` round-trip) before the static validation that would reject
a statically doomed citation. The specific doomed shape: two
reassessments of the *same source*, cited with different `--wrong`
counts, produce two different tokens — so neither the idempotent-replay
check nor the redirects-vs-wrong count check catches it — and only
`parse_citations`, re-run on the full prospective citation list inside
`citation_counts()`, rejects the pair as "one citation states one
judgment." That rejection used to happen after `resolve_author`.

**Implemented as:** the prospective citation list
(`tokens + [token]`) is validated with `parse_citations` before
`resident_identity`/`resolve_author` are called, using the exact same
check `citation_counts()` was about to run. Behavior is otherwise
identical — this only moves *when* a doomed citation is discovered.

Test in `test/outcomes/run.sh`, "the static citation check runs before
the network boundary (change 4)": builds two redirects and one
reassessment, then attempts a second reassessment of the *same*
reassessed source with a different `--wrong` count, using a resolver
faked to fail unconditionally (standing in for a `gh` that cannot
succeed). Asserts the command still fails with "one citation states
one judgment," not the resolver's "does not resolve" — proving the
static check ran first.

## Change 5 — the documentation matches the coverage

`tools/reachability-check.py`'s module header now describes what it
actually checks: every executable under `tools/` (not just
argparse-based tools) needs a caller, either as a full subcommand tree
or as one bare entrypoint; a standalone `*-check` script run directly
by a workflow is a gate needing a feeder, same as a `check`
subcommand; a string passed as a call argument counts as naming a
tool. The test-wrapper gap is still named as out of reach, and now
names its own two real-tree instances (`handover-check.py`,
`reachability-check.py`) as evidence the widened Change 3 rule did not
have to invent a feeder for either.

`brief_headers()` in `tools/outcomes/outcomes` now carries a named
residual of the 0072 finding it already fixed: the `KNOWN_BRIEF_HEADERS`
whitelist stops a non-header continuation line from being mistaken for
a new header, but a continuation line that begins with a *real*
header's own key and a colon is still ambiguous. Closing that fully
needs a format change (indented continuations, RFC-822 style), not
another parser heuristic — the same class as emcee's
`a-wrapped-header-value-silently-voids-later-headers`.

## Verification

- `test/reachability/run.sh`: the synthetic-tree half passes in full,
  including all new fixtures for Changes 1–3. **The real-tree half —
  this repository's own entrypoints — fails**, with exactly the five
  problems named under Change 2's "Real-tree consequence" above and no
  others. This is a known, deliberate, and named outcome, not a defect
  in the implementation; see that section for why it was not papered
  over and what resolves it.
- `test/outcomes/run.sh` passes in full, including the Change 4
  ordering test.
- `tools/outcomes/outcomes check` passes over the real log.
- The task-outcome row is written per `docs/measurement.md`.

## Judgment calls for the resident

1. **The five real orphans above stay flagged rather than papered
   over.** This is the biggest deviation from the original draft, which
   predicted the real tree would still pass. It does not, and per this
   brief's own instruction ("say so in the PR... rather than papering
   it") that is the intended disposition, not a bug to fix before
   landing. `reachability-check.yml` will be red on `main` after merge
   until the resident disposes of each: delete, document for real, or
   scope the lint differently.
2. **`tools/codex-review.sh`'s marker went in
   `.claude/skills/implement-brief/SKILL.md`, not `CLAUDE.md`.** That
   file is committed to this repository (`.gitignore` says so
   explicitly) and already, independently, instructs running the tool
   as a checklist step — the marker formalizes an existing truth rather
   than inventing one.
3. **Change 3's real-tree prediction in the original draft was wrong**
   (see that section) — `check.yml` does not invoke
   `tools/handover-check.py` directly, so no feeder line was needed
   anywhere. Worth noting because it means every standalone checker in
   this repository is currently reached only through a test wrapper,
   which is the pre-existing named gap, not new.

## Review findings

`/code-review` (four findings, all fixed on this branch):

- Adjacent string literals inside a call argument —
  `["tools/outcomes/" "outcomes", "derive"]` — merge into one AST
  `Constant`; keeping only its start position left the second
  fragment's own STRING token still stripped. `call_argument_strings`
  now keeps a source *range* per constant and checks token membership
  against it, not equality against a single position.
- `entrypoints()` called `ast.parse` with no exception handling, and
  `find_tools()` no longer pre-filters `.py` files by the
  `add_subparsers` substring (that filter is the entire point being
  widened), so a syntactically invalid `.py` anywhere under `tools/`
  would crash the whole lint. Now caught, falling back to a bare
  entrypoint — the same conservative direction `code_only` already
  used for the identical failure.
- `code_only()` was being recomputed once per `(spec, caller file)`
  pair rather than once per file; Change 2 made the spec count much
  larger by giving every single-command tool its own entry. Now
  computed once per file before the per-spec loop.
- `cmd = [...]; subprocess.run(cmd)` — a list built and passed by name
  — is invisible to `call_argument_strings`, which walks each call's
  own argument expressions rather than tracing an assignment. Named as
  a residual gap in that function's own docstring rather than fixed;
  closing it needs data-flow analysis, out of this pass's scope.

`tools/codex-review.sh` (two findings):

- **[P1]** Restated the real-tree reachability-check failure already
  covered above under "Real-tree consequence" and "Judgment calls."
  No new information; not independently actioned.
- **[P2]** Fixed. `code_only()` was branching on `path.suffix == ".py"`
  rather than `is_python_tool()`, so an extensionless Python caller —
  `tools/outcomes/outcomes`, `tools/clarify/clarify`, exactly the
  tools most likely to call another one — fell into the shell/YAML
  branch, which only strips an unquoted `#` comment and leaves
  docstrings and bare prose intact. A mention in either file's own
  prose could have rescued an orphan the same way the module's own
  header once did, before task 0072. New fixtures added: an
  extensionless Python file's docstring does not rescue a subcommand
  it only mentions; a real call in one still does.
