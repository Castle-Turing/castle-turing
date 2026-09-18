Title: Task 0072 — wire the outcome log, and its redirects
Model: deep
Milestone: m2-constraints
Model-because: the deliverable changes what a write-once measurement
instrument will accept, and adds the one command in this repository
that writes a resident's judgment into it. Every decision here is about
what a mechanism may claim on the resident's behalf: whether a count
may stand without its miscorrection rate, what makes a citation proof
of authorship rather than proof of existence, and where the mechanical
check stops and the audit's reading begins. A standard implementer
against an exact spec would produce a working subcommand and a passing
lint; what breaks is a rule that lets an agent's own words enter the
log wearing the resident's name, and that failure reads as a green
diff. The reachability lint underneath it is mechanical, but it is the
smaller half.

# Task 0072 — wire the outcome log, and give redirects a hand that isn't the resident's

## Where this came from

Task 0070 built the log, its checker, and a coverage gate. It did not
wire row-writing to anything and left verdict cells to be written "by
hand, or not at all." The resident's review of PR #120 found the
consequence and recorded it as a citable redirect on 2026-09-14: the
coverage gate would be armed against a pipeline that feeds it nothing,
and the verdict columns would have no invocation path a resident who
will not hand-edit a TSV would ever use. The measurement would exist
and stay empty.

**One fact about sequencing has changed since that redirect, and it
matters.** The redirect asked that #120 be held open until this task
landed. It was not: #120 merged on 2026-09-16. So the coverage gate is
armed *now*, against an unfed pipeline, on a repository whose next task
pull request is this one. This task is no longer a companion landing
alongside 0070; it is the repair of a live gap, and the fact that this
branch had to append its own row by hand before CI would go green is
the gap demonstrating itself.

This is a specimen of the failure
`docs/backlog/passing-tests-are-not-acceptance.md` names. "Logging is
running" passed every test and satisfied the implementer's honest
reading, while the resident's reading — rows get written as work
happens, and a redirect is loggable — was unmet. The fix is
reachability, and a detector so the class does not recur.

## What lands

### 1. Row-writing, named and owned at the moment the pull request opens

**The mechanism chosen is a documented one-command step, owned by the
session that opens the task pull request** — not a delivery seat, and
not CI. Both alternatives were considered and both are wrong here, for
reasons worth stating because they will be proposed again.

*Why not the delivery seat (0070's own named successor).* The delivery
seat is a seat in `docs/architecture.md`; the thing occupying it today
is emcee, a separate repository. Nothing in this checkout opens a pull
request, so there is no code here to wire. Teaching emcee to run
`outcomes derive` is real work in a real place — it is filed as
`docs/backlog/the-outcome-row-is-written-by-hand.md`, which is the debt
this interim owes, per the convention that an interim which will repeat
must be filed as debt toward the wired version.

*Why not CI, which could push the row itself.* `env` and `tier` are
immutable cells. Only the session that ran the attempt knows which
environment it ran in and at what tier it was routed; CI knows neither
and would have to guess. An immutable cell guessed wrong is the one
defect this log has no mechanism to repair — the row cannot be deleted
and the cell cannot be rewritten. A gate that can only fail is
therefore the right gate, and the writer has to be the party holding
the facts. This is the same argument `docs/measurement.md` already
makes for why coverage fails at the cheap moment rather than
reconstructing later.

So: the step is one command, it is named in agent guidance beside
`/code-review` and `tools/codex-review.sh` where a session already
looks before opening a pull request, and it is

    tools/outcomes/outcomes derive --env <key> --fill

The bar the brief sets — a pull request that would fail the coverage
gate cannot reach the resident — is met from both ends. The step puts
the row there, and where the step was skipped, `outcomes-check` is red
on the branch while the facts are still in someone's head. What this
task adds beyond 0070 is that the step now has an owner named in the
place the owner reads, and a lint (§3) that fails if that naming is
ever removed.

### 2. `outcomes redirect` — a verdict logger the agent invokes

    tools/outcomes/outcomes redirect <task> --ref <citation> [--wrong N]

It counts **distinct cited redirect events**. Every invocation requires
`--ref`. A citation already recorded is an idempotent replay: exit
zero, change nothing, touch no network. A new citation is resolved,
its author verified, and appended.

**Citations live in `verdict_ref`, which becomes an append-only list.**
This is the schema-1 change that makes the rest possible, and it is
described in `docs/measurement.md` as a fourth cell class rather than
smuggled in as a loosening of the third. A citation is a token:

- `r/<source>` — one redirect, cited where the resident made it.
- `w<n>/<source>` — a reassessment that judged `n` of this task's
  redirects wrong. `n` may be `0`, which is how "reassessed, none
  wrong" gets recorded with a citation behind it rather than defaulted.

`<source>` is the citation's own address, normalised: `pr<num>/ic<id>`
for a pull-request comment, `pr<num>/rc<id>` for a review comment,
`rec/<id>` for a journal record. Tokens are comma-separated, which the
existing `verdict_ref` validator already admits, so no column changes
shape.

**The counts are derived from the citations, and `check` enforces the
equality.** `redirects` must equal the number of `r` tokens;
`redirects_wrong` must equal the sum over `w` tokens. This is what
makes the brief's integrity rule mechanical rather than aspirational: a
count can only move because a citation was added, and a bare edit of
the number is caught by a checker with no network, no forge and no
model in it. The append-only comparison holds `verdict_ref`'s base
value as a *prefix* of its current value, so a citation may be added
and none may be removed or reordered.

**`redirects_wrong` stays pending until the resident reassesses**, and
this forces a change to one of 0070's rules. That checker refused
`redirects` without `redirects_wrong` beside it, on the ground that a
detection rate without its conditional miscorrection rate is
uninterpretable. The ground is right and the rule was in the wrong
place. Writing `0` at redirect time would record the absence of a
judgment as a judgment of correctness and bias the miscorrection rate
downward — the same silence-reads-as-a-decision defect this project
keeps paying for. So the pairing moves from a *storage* rule to a
*reporting* rule: the log may hold `redirects` with `redirects_wrong`
pending, and `docs/measurement.md` now requires that any redirect rate
read out of this log be reported with the count of redirects not yet
reassessed beside it, because that count is the unknown denominator.
`redirects_wrong` without `redirects`, and `redirects_wrong` exceeding
`redirects`, both remain errors.

**What `--ref` proves, and what it does not.** Proposal 06 says no
automation may author a verdict. This command does not author one; it
**transcribes** one, and `--ref` is the proof of authorship. The
resolver verifies two things mechanically: the citation resolves to a
real comment or record, and its author is the configured resident
identity. Existence alone is not enough — a reference to a real comment
the *agent* wrote would pass an existence check while carrying no
resident judgment at all.

**And the author check is weaker in this installation than it looks.**
Agents here post pull-request comments through the resident's own `gh`
credential, so a comment written by an agent and a comment written by
the resident carry the same login. PR #120 holds one of each. The
mechanical check therefore rules out a citation to *someone else's*
comment and does not today rule out a citation to the agent's own. The
mitigation exists and is not this task's to install: the review-bot
GitHub App gives machine work its own `[bot]` identity, after which the
check separates the two. Until then the residue is larger than the
command's help text would otherwise imply, so the help text says so,
and `docs/backlog/an-agent-posts-under-the-residents-name.md` carries
the debt. The remaining semantic residue — whether the cited text
actually states the claimed verdict — is the weekly audit's sampled
read and always will be. An agent may transcribe; it may never
originate.

**The resident identity is private configuration.** The mechanism is
public: verify the citation's author against a configured identity.
The identity is not in this repository and never will be — it comes
from `--resident`, else `OUTCOMES_RESIDENT`, else
`$XDG_CONFIG_HOME/castle-turing/resident`. With none of them set the
command refuses rather than degrading to an existence check, because a
verification that silently stops verifying is worse than one that was
never claimed. The slot is named in `docs/measurement.md`'s operating
section rather than in `docs/private-layer.md`: that document is the
private *NixOS* configuration a stranger writes to deploy the
framework, and this is configuration for the tooling that measures the
framework's own development. Putting it there would have been filing it
under the right word and the wrong reader.

### 3. `tools/reachability-check.py` — the detector

An incident ships its detector. The incident is "functionality was
added with no invocation path, behind an armed gate," and the
mechanical half is a lint in CI with two rules.

**Orphan entrypoint.** Every subcommand of every tool under `tools/`
must have an *operational* caller. Three kinds count: a workflow under
`.github/`, another executable under `tools/`, or a documented step
that declares itself with an `invokes:` marker — an HTML comment naming
the entrypoint — in the document that owns it. Two kinds deliberately do not. A test
does not count, because the 0070 miss was precisely a command that
worked, was tested, and was reachable by nobody; letting a test satisfy
reachability would have let 0070 through this lint. A usage synopsis
does not count either — `tools/README.md` lists every command by
construction, so a lint that accepted a mention there would accept
everything. The explicit marker is what separates a step someone owns
from a line in a reference table, which is the same distinction §1 is
making with a different instrument.

**Armed gate with no feeder.** A workflow that runs a `check`
entrypoint must carry a `# feeder: <entrypoint> (<location>)` line, and
the lint verifies the citation the way `outcomes redirect` verifies
its own: the named entrypoint must exist, and the named location must
be a file that actually carries an `invokes:` marker for it. A marker
naming an entrypoint no tool exposes fails too, which is how the lint's
own documentation stays honest — and it caught this brief's first draft
citing a placeholder. A feeder
line naming something imaginary fails; blank fails. This is the
non-emptiness rule the conventions already apply to a decision's
falsifier and a task's `Model-because:`.

**What the lint cannot do, stated so nobody mistakes the one for the
other.** It catches the mechanical shape of the 0070 miss — a callable
nothing calls, a gate nothing feeds. It cannot catch the semantic
cause, which is that a feature satisfied its implementer's reading of
the requirement and not the resident's. That is acceptance, it is
`docs/backlog/passing-tests-are-not-acceptance.md`, and no lint will
ever be it. The lint is a floor under the diff, not a substitute for
reading it.

Three existing entrypoints gain markers rather than being flagged:
`clarify check`, `clarify probe build`, `probe score` and `probe
oracle` are all genuinely operated from `docs/clarifying-questions.md`'s
"Running it" section, which is exactly the documented-step case the
marker is for. `outcomes derive` is the one true orphan on the tree
this task starts from, and the lint fails on it before §1 lands — the
detector demonstrably detecting, which is this task's own first test.

### 4. The agent instruction — needs the resident's explicit approval

`CLAUDE.md` gains two short paragraphs and `docs/measurement.md` gains
the operating section they point at: the session that opens a task pull
request appends its row, and an agent that is redirected by the
resident transcribes the redirect with a citation and never invents
one. **A `CLAUDE.md` change always needs explicit approval, autonomy
grant or not, and this task's dispatch does not supply it.** The text
is drafted as a diff so that approving it is reading it, and it is the
one piece of this pull request that should be reverted rather than
merged if the resident does not want it.

Be exact about what reverting costs, because it is easy to overstate.
Everything else stands: the commands work, the operating section in
`docs/measurement.md` still names both steps, and the reachability lint
still passes, because the lint's question is whether a step is named
somewhere an operator reads, not whether an agent is obliged to take
it. What is lost is the obligation — the steps would be documented in a
file agents consult and absent from the file agents load. That is
close to the state task 0070 was already in, which is the argument for
the paragraphs rather than a reason to pretend the lint would catch
their absence.

## The inaugural datum

The first real use of the command logs the redirect that created this
task:

    tools/outcomes/outcomes redirect 0070-the-task-outcome-log \
        --ref https://github.com/Castle-Turing/castle-turing/pull/120#issuecomment-5659322373

Task 0070's row matures to `redirects=1`, `verdict_ref=r/pr120/ic5659322373`,
with `redirects_wrong` pending. That row, green under `outcomes check`,
is this task's acceptance test: the first verdict in the log is the
redirect that produced the mechanism for logging verdicts.

**A discrepancy the resident should settle.** That comment's last
paragraph says the redirect was "a correct redirect, not a wrong one,"
which is an explicit resident statement that would license
`--wrong 0 --ref <the same comment>` and mature `redirects_wrong` to
`0`. This brief's own instruction is that `redirects_wrong` stays
pending because the measure is defined over redirects *later judged*
wrong, and a judgment made in the same breath as the redirect is not a
later reassessment of it. The pending value is what landed, because
that is what the brief says and because pending is the weaker claim.
Maturing it is one command if the resident disagrees.

## Verification

Automated, no human, in CI:

1. `test/reachability/run.sh` — the lint against synthetic trees: an
   orphan entrypoint is caught, a test-only caller does not rescue it,
   a synopsis does not rescue it, a marker does, a gate with no feeder
   line is caught, and a feeder line citing a non-existent entrypoint
   or an unmarked location is caught. Plus the real tree, which must
   pass.
2. `test/outcomes/run.sh` gains the redirect half: a first citation
   matures a row, a replay of the same citation changes nothing and
   exits zero, a second distinct citation increments, a `w<n>` citation
   matures `redirects_wrong`, a missing `--ref` is refused, an
   unresolvable one is refused, a comment authored by someone other
   than the configured resident is refused, a missing resident
   configuration is refused, and the checker rejects a count edited
   without a citation, a citation removed, a citation reordered, a
   `redirects_wrong` exceeding `redirects`, and a `w` citation on a
   task with no `r` citation. Resolution is faked through an injected
   resolver so the test keeps `check`'s no-network property.
3. `tools/outcomes/outcomes check` over the real log, which now
   includes 0070's matured row and this task's own row.

Needs a human:

- **Approving §4.** By construction.
- **Whether the transcription is faithful** — that the cited comment
  says what the row claims. The weekly audit's sampled read, forever.

## Judgment calls made where the spec was silent or has been overtaken

1. **0070 had already merged.** The dispatching brief says #120 stays
   open until this lands; it merged on 2026-09-16. The sequencing
   section is rewritten above rather than followed.
2. **The mechanism for §1 is the interim, not the preferred option,**
   because the preferred one has no code in this repository to attach
   to. Argued above; debt filed.
3. **0070's redirect-pairing rule is relaxed,** which is a change to a
   rule another brief called load-bearing. The reasoning it was
   protecting is preserved and moved to the reporting rule in
   `docs/measurement.md`.
4. **`--wrong N` is kept as the dispatching brief specifies** rather
   than being split into a per-redirect reassessment flag, and is
   encoded as a summing `w<n>` citation so that the per-citation
   append-only discipline holds for it too.
5. **The author check's real strength is documented as weaker than the
   spec implies,** rather than described as the spec describes it. See
   §2; backlog entry filed.
6. **Tests do not satisfy the reachability lint.** The spec did not say;
   counting them would have let the incident this lint exists for pass
   it.
7. **No sub-agent was delegated to.** The delegation convention
   describes a session talking to the resident handing work down; this
   session was dispatched by a harness with no resident in the loop and
   its environment does not permit spawning agents. The sizing in the
   header is the sizing that applies.
