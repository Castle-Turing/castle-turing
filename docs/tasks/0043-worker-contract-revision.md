# Task 0043 — worker contract: tiered options, quoted refusals, the finding lane

Promotes `docs/backlog/the-worker-cited-a-rule-its-contract-does-not-
contain.md`, deleted in the same commit per that directory's README.

**Before starting:** read `CLAUDE.md` in full. Then read
`agent/castle-worker-claude` END TO END — not the prompt alone. Its
parse hazards are documented inline, they are easy to reintroduce, and
every one of them has actually fired: the unquoted heredoc delimiter
(so a backtick pair in the prose is command substitution, and a bare
`$VAR` interpolates), the quote-pairing gotcha in the `:?` messages
above it, and the reason the prompt is written to a file rather than
captured in `$(...)`. Then read `docs/tasks/0023-resume-cold.md` §2 and
§7 — the blocking marker and the continuation packet — because the
tiered-options behaviour in §3 below is entirely a use of that
mechanism and adds none of its own. Then `docs/tasks/0042-finding-
outbox.md` §1 and its format paragraph, which is the lane §4 routes the
dead end into.

This task changes **prose only**, and only in one file. No option, no
record field, no CLI surface, no behaviour of `agent/castle`. That is
the point: the mechanism this contract rides on was finished by 0023
and 0042, and what remained wrong was what the contract *says*.

## The problem

On 2026-09-02 a worker turn was asked to install a specific program. It
refused, stating that "software-installation … falls outside what this
seat may propose configuration for" under "the contract's scope rule."

**There is no such rule.** `agent/castle-worker-claude` contains no
scope rule about software installation, and never has. The tenant
invented a restriction, attributed it to its own contract, and the
result record's confident citation made the fabrication invisible to
the resident — a refusal reads as discipline, and only an audit against
the contract text tells a real one from a manufactured one.

The refusal also sat badly against precedent the same turn had already
read. A package-list option with entries already in it sat one line
from where the proposal belonged, already carrying an agent CLI added
for exactly this reason, and the requested program was available
through the same pinned package set. The diff was one verifiable line.
(Contrast the foot-alpha errand, which correctly proposed a diff
through a pre-existing option surface of exactly that shape — the
contract does not distinguish the two cases, so the tenant's judgment
was the only thing standing between them.)

Behind that single incident sit three separate defects, and fixing only
the loud one would leave the other two.

1. **Nothing makes a refusal falsifiable.** The contract tells a tenant
   what it may do; it never tells it what a refusal has to be made of.
   A fabricated rule and a real one produce identical records.
2. **The contract's stated scope really is too narrow.** Item 7 says an
   errand is in scope "exactly when the symptom maps to one or more
   options under `castle.display.*`, `castle.input.*`, `castle.power.*`,
   or `castle.hardware.*`." A package list in the private layer is none
   of those. The tenant's citation was fabricated, but a tenant reading
   item 7 literally and refusing an install would have been *following*
   the contract. The invented rule was in the neighbourhood of a real
   one, which is worse than an obvious hallucination, not better.
3. **The right fix had nowhere to go.** The genuinely correct outcome —
   the framework should offer an option surface for developer CLIs
   rather than leaving every resident to hand-maintain a list — was a
   mechanism finding, on a turn whose contract said to state it in prose
   and stop. That is the fourth occurrence of the problem
   `docs/tasks/0042-finding-outbox.md` was written to close, and it
   arrived after that brief was specced. 0042 built the lane; this task
   is what tells a tenant to use it instead of stopping.

A fourth defect is not from this incident but from the same family, and
is included here because it is the same sentence being fixed. When a
request can be met *partly* today and *fully* only by new framework
work, the contract offers a tenant two moves, and both are wrong:
propose the partial fix silently (deciding, on the resident's behalf,
that half is what they wanted) or refuse the whole thing (deciding that
none of it is available). The resident's worked example of the shape
that is actually wanted:

> Sway doesn't have an LRU workspace cache, so that isn't available
> today. I can create a keyboard shortcut to cycle between two
> workspaces now. If you want, I can kick off a new castle-turing tool
> to keep track of LRU workspaces.

Three levels, three sentences, no jargon, and a decision left with the
person whose machine it is.

## The design

Four changes to the prompt in `agent/castle-worker-claude`, plus the
one-line consequence each has elsewhere in that file. Nothing else in
the repository changes.

### 1. Refusals must quote

A new contract item (numbered 10 — see §5 on numbering) stating that any
refusal or scope claim must quote, verbatim and in the reasoning on
stdout, the sentence of the contract it rests on. Not a paraphrase, not
a summary, not a name for a rule: the words themselves.

And the half that does the work, stated as flatly as the deploy
prohibition is stated: **a refusal that cannot quote its rule is not a
refusal this contract recognizes.** A tenant that goes looking for the
sentence and does not find it has its answer — the restriction does not
exist and the errand is in scope.

Two properties this has that a softer version does not.

- **It is checkable by a human in one reading.** The quote is either in
  the file or it is not. The 2026-09-02 record required an audit
  against the contract text to falsify; a record carrying a quotation
  falsifies itself.
- **It changes the tenant's own reasoning before the record exists.**
  The instruction to go find the sentence is the intervention. A model
  composing a plausible-sounding restriction and a model searching its
  prompt for that restriction are doing different work, and only the
  second one discovers there is nothing there.

The item names the incident that produced it, briefly and with no
personal data — an errand asked to install a program, a refusal
attributed to a scope rule that does not exist. Prompts in this file
already carry their motivating failures (0039's staged deliverables,
0024's three-state collapse) for the reason that a rule whose cost is
visible survives editing better than one that reads as ceremony.

Scope claims count as refusals for this purpose; so does "I cannot
propose this from here." Filing a question does not — a question is the
errand continuing, and nothing here should push a tenant toward
guessing to avoid a quotation requirement.

### 2. Software installation is in scope

Item 7's scope rule gains a second qualifying shape. An errand is in
scope for a configuration proposal when the symptom maps to an option
surface that already exists and that the tenant can read, and there are
two such surfaces:

- one of this framework's own options (`castle.display.*`,
  `castle.input.*`, `castle.power.*`, `castle.hardware.*`) — unchanged
  from what item 7 says today; and
- **an option surface the private layer already uses, with entries in
  it a resident put there.** The clearest case is a package list: if
  the private configuration already declares a list of installed
  packages, adding a package to that list is an ordinary configuration
  proposal and this seat may make it. Installing software is in scope.

Named by shape, not by incident: "a package-list option with prior
entries." The rule has to generalise to the next surface of that shape
— a list of enabled services, a set of shell aliases, anything a
resident has already demonstrated the pattern of. Writing it as
"installing programs is allowed" would fix one errand and leave the
next one to a tenant's improvisation.

**The honest limit, stated in the item rather than left to be
rediscovered as a reason to refuse.** A tenant cannot verify that a
package attribute exists: `nix search` is network access and `nix eval`
copies the tree into the world-readable store, both already forbidden
by item 4 and for reasons this task does not reopen. So the contract
says what to do instead — name where the package name came from, say
plainly in the reasoning that the attribute was not verified, and
propose the diff anyway. A wrong attribute fails at the resident's
rebuild, loudly, before anything is deployed. That is a cheap, visible,
correctable failure, and it is strictly better than a refusal, which
costs the errand and produces nothing to correct. Left unstated, "I
cannot verify this" is exactly the shape the next fabricated scope rule
takes.

### 3. Tiered options are the expected shape

A new contract item (numbered 9) for requests that admit more than one
level of fulfilment: part of it can be met now through an option that
already exists, and the rest only through framework work that does not
exist yet.

The instruction is to file a `--blocking` question laying out the
levels in plain language — what can be done now, what new work would
close the gap, or both — write no diff and no target, and let the
resumed turn act on the answer. The resident's worked example (quoted verbatim in
"The problem" above) is carried into the prompt as the form to copy,
with "LRU" spelled out as "least-recently-used" and "a new
castle-turing tool" written as "new Castle Turing work" — the
contract's reader is a model on a stranger's machine, not someone who
already shares this project's shorthand.

This adds **no mechanism**. It is `--blocking` (item 5) plus the
resumed-turn contract 0023 built, applied to a case the contract had no
name for. §2 of 0023 is explicit that `blocking: true` is a fact only
the question's writer can know at write time; this task widens the set
of turns where a tenant should conclude it, and touches nothing about
how the fold reads it.

Three constraints the item has to respect, each already stated
elsewhere in the contract and each easy to break by writing this item
carelessly.

- **The answer surface has no multiple choice** (item 6). The resident
  types free text and picks *which question* to answer, never which
  value from a set. So the levels must be describable in prose that a
  one-line answer selects among — "do the shortcut", "both" — and the
  question must never be phrased as though a candidate list were on
  screen. Numbering the levels to give them handles is fine; assuming
  a picker is not.
- **A blocking question stops this turn and only this turn.** Item 6
  already establishes the ask-first-diff-second shape and the "write NO
  diff and NO target" rule; this item points at it rather than
  restating it, so the two cannot drift apart.
- **The successor acts, and does not re-ask.** The resumed tenant has
  this turn's account and the answer in the packet, and proposes the
  level the resident chose. If that level is the one needing new
  framework work, that half is a finding; if they also asked for the
  interim change, that half is still a diff.

**The gap is a finding either way.** "Sway has no least-recently-used
workspace cache and this framework offers no option for one" is a
mechanism gap whether or not the resident wants the interim keybinding,
so the item says to file it on the turn that notices it rather than
saving it for a turn that may never come — with the matching caution
that a resumed tenant must not file a second copy of a finding its
predecessor's account already records. `castle work` reads
`$CASTLE_FINDING_FILE` back on every completed turn, independently of
whether a diff was produced (`run_worker_turn`, the read-back beside
the target file), so a turn that ends in a blocking question can carry
a finding out with it. That is checked, not assumed.

### 4. The finding lane replaces the dead end

The contract's honest dead end — "say so and stop, having proposed
nothing" — was correct when there was nowhere for a diagnosis to go.
0042 gave it somewhere. Three sites change:

- **Item 1a's mechanism branch** ("if none is configured, say so in
  your reasoning and stop, having proposed nothing"). Now: say so,
  propose nothing, and write the gap as a finding with `Destination:
  mechanism` per item 8's format. A missing option is precisely what
  that lane carries. And if part of the request *can* be met through an
  option that does exist, item 9 applies as well — offer the levels
  rather than stopping.
- **Item 7's scope dead end** ("say so honestly and propose nothing").
  Same treatment: a symptom that maps to no reachable option surface is
  a mechanism gap, and mechanism gaps have a lane.
- **The `mechanism_note` absent branch** ("say so in prose, propose
  nothing, and stop"). This is the text a host with no mechanism
  checkout renders, which is the normal case per
  `docs/tasks/0024-config-target.md` §3 — and therefore the branch on
  which the dead end was most often reached. It now points at the
  finding lane, which exists for exactly this: a framework gap noticed
  on a machine that cannot propose against the framework.

Item 8's closing paragraph ("THIS IS NOT A PLACE TO PUT WHAT DID NOT
FIT ELSEWHERE") is updated in the same pass, because its third clause —
"an errand that maps to no option is still 7 — say so honestly and
propose nothing" — is the sentence this change contradicts. What
replaces it keeps the restraint and adds the one this task needs:
**findings are for framework defects and gaps, and are never a
substitute for the private-layer half of an errand that has one.**
Filing a finding and calling the errand finished, with a one-line
configuration change sitting in front of you, is the failure mode this
lane must not acquire. It is the same failure as the 2026-09-02 refusal
wearing better clothes.

**Item 1b's dead end is deliberately left alone.** Its case is a
resident using a host module this framework ships, on a host with no
mechanism checkout configured. That is a misconfiguration of *this
machine* — the remedy is `castle.agent.repo.mechanism`, on the
resident's side — not a defect in the framework, and routing it to the
outbox would file a finding on every such errand describing a limitation
already known and already documented. Item 8's own warning against a
finding that is "really a complaint about the errand" applies. The item
instead keeps "say so and stop" and points at 1a for the case where the
real problem is that no option exists at all.

### 5. What does not change

Stated explicitly because this task is an extension and the temptation
in a prose revision is to tidy:

- The allowed and forbidden command lists (item 4) are untouched,
  including every `--no-optional-locks`, the Nix prohibition and its
  store-exposure reasoning, and the never-write-under-a-configured-root
  rule.
- The `--blocking` guidance in item 5 is untouched; item 9 cites it.
- The deploy prohibition, the nonce fencing, the sandbox declaration,
  the three-state mechanism channel and the three-branch `sweep_note`
  are untouched.
- `agent/castle` is not modified by this task at all.
- **Existing items keep their numbers.** New items are appended as 9
  and 10 rather than inserted near the rules they extend. Item 2 cites
  "8 below" and item 8 cites 5, 6 and 7 by number; renumbering to put
  the refusal rule beside the scope rule would edit five cross-
  references for a presentation gain, in a file where a stale
  cross-reference is a prompt that lies to its own reader.

## Verification plan

**Say plainly what cannot be checked: this task is prose in a prompt,
and prose in a prompt is mostly unprovable by CI.** No test can assert
that a tenant will quote its rule, offer the levels, or file the
finding — the only evidence for any of that is a live turn. Pretending
otherwise by writing an assertion that greps for a sentence and calling
it coverage would test that the sentence is present, which is a real
but much smaller claim, and it is the claim this task actually makes
below.

**What CI can assert, and does.**

- `test/agent-loop/run.sh` passes unchanged. The contract's mechanical
  interface did not move: the same three deliverable paths, the same
  boundary token, the same environment variables, the same exit codes.
  Every scripted-tenant fixture in `test/agent-loop/` is a stand-in for
  a tenant at that interface, so their passing unchanged is the
  evidence that this revision is prose-only.
- The prompt-render assertions in `test/agent-loop/config-target.sh`
  and `test/agent-loop/dispatch-test.sh` pass unchanged. Those grep the
  rendered prompt for strings the three-state mechanism channel, the
  0039 deliverable rule and the 0042 format paragraph key on. Any new
  prose that broke a state distinction — in particular by putting "no
  mechanism checkout is configured" into text that renders in all three
  states — fails there, which is the check that matters most for an
  edit of this shape.
- The file still parses and renders. `test/agent-loop/resume.sh` runs
  `agent/castle-worker-claude` for real against an oversized packet and
  against a token-less one, so a reintroduced backtick or an unescaped
  `$` in the prose is a test failure rather than a live-errand
  surprise. This is the check the inline comments exist for.

**What was actually run while implementing, and the one gap.**
`test/agent-loop/run.sh`, `dispatch-test.sh`, `resume.sh` and
`outbox.sh` all pass against this branch — those are the four suites
that exercise the worker seat, and `dispatch-test.sh` and `resume.sh`
between them render this file for real. `config-target.sh` **could not
be run in the implementation worktree**, for a reason that has nothing
to do with this change: its assertion 6 builds a "not a git working
tree" fixture under `$TMPDIR`, and every path the implementer could
write to was inside a git working tree, so `castle`'s pre-flight
correctly reported "inside the working tree rooted at …" instead of
the message the assertion expects. `GIT_CEILING_DIRECTORIES` does not
help: `_git_stripped_env` removes it before the probe, deliberately.
Its prompt-render assertions — the part of that file this change could
break — were therefore replicated by hand against all three rendered
states, and all of them hold: every pinned string present, "no
mechanism checkout is configured" in the absent state only, "NOT a
usable git working tree" in the invalid state only, the sweep-tool path
in the usable state only. CI runs the whole file on a runner where
`$TMPDIR` is outside any checkout, which is the authoritative result.

**No new test is added.** A grep for each new paragraph would pin
wording that is expected to be revised as live errands teach us how it
reads, and the existing render tests already cover the failure mode
that actually costs something (a prompt that will not render, or a
state distinction collapsed). The 0042 format paragraph is pinned
because it is the *only* documentation of a file format another program
parses; these paragraphs document nothing but themselves.

**The human steps, which are the real verification.** Each is the next
live errand of one shape on the reference host:

1. **An install errand.** Ask the worker for a program that belongs in
   a package list the private layer already carries. Expected: a
   one-line diff against that list, targeting `private`, with the
   reasoning naming the existing entries as precedent and saying the
   attribute name was not verified. A refusal here, quoted or not, is
   this task failing.
2. **A tiered errand.** Ask for something Sway cannot do today but
   whose interim approximation is a keybinding. Expected: a
   `--blocking` question offering the levels in plain language, no diff
   and no target on that turn, a finding filed for the gap, and — after
   an answer — a resumed turn that proposes the chosen level without
   re-asking.
3. **An out-of-scope errand.** Ask for something the framework genuinely
   has no option for. Expected: no diff, a finding with `Destination:
   mechanism` in the outbox, and reasoning that says so. If the tenant
   refuses in prose without a quotation, the refusal rule did not take.
4. **A refusal audit.** On the next turn that refuses anything at all,
   check the quoted sentence against this file. That check is now one
   `grep` rather than a reading of the whole contract, which is the
   entire point of §1.

Each of these produces a journal record the resident can read at their
own pace; none needs a harness built for it, and building one would
mean simulating a model's judgment, which is the thing under test.

## Judgment calls

Recorded per `CLAUDE.md`'s delegation rule — every place these
instructions were ambiguous and a call was made.

1. **Item 7 was widened, not merely annotated.** The instruction was
   "software installation is in-scope … name the shape." Item 7's
   existing sentence ("in scope *exactly when* the symptom maps to one
   or more options under `castle.*`") makes a package list out of scope
   by construction, so adding a permission without touching that
   sentence would have left the contract saying two things. The whole
   scope rule is restructured into two qualifying shapes. This is a
   larger edit than "add a paragraph" and it is the honest one: the
   backlog entry is right that the cited rule was fabricated, and also
   the narrow rule it was in the neighbourhood of was itself wrong.
2. **The unverifiable-package-name limit was added on my own
   initiative.** Nothing in the instructions mentions it. A tenant told
   "installing software is in scope" and forbidden from running `nix
   search` or `nix eval` will reach for a refusal at the first
   uncertainty, which reproduces this task's own failure through a
   different door. The contract now says what to do instead. Flagged
   because it is scope I added.
3. **New items are appended as 9 and 10 rather than inserted.** See §5.
   Presentation would prefer the refusal rule next to the scope rule;
   correctness prefers not editing five cross-references in a prompt.
4. **Tiered options is 9 and the refusal rule is 10.** Both orderings
   defensible. 9 continues the thread items 7 and 8 set up — what a
   turn does *instead* of stopping — and 10 is the meta-rule that
   closes the contract before the override block. The instructions
   listed refusals first; that ordering is the brief's, not
   necessarily the prompt's.
5. **Item 1b's dead end is not routed to the outbox.** See §4. The
   instruction named the "say so and stop, having proposed nothing"
   sentence, which is 1a's; 1b's nearby "say so and stop" is a
   different case — a misconfigured host, not a framework gap — and
   filing it as a finding would put resident-specific configuration
   advice into a public backlog on every occurrence.
6. **The tiered question files its finding on the questioning turn**,
   not on the resumed one, with an explicit instruction to the
   successor not to duplicate it. The alternative — wait for the answer
   — loses the finding entirely if the resident never answers, which is
   the failure the outbox exists to prevent. That the harness reads
   `$CASTLE_FINDING_FILE` back on a turn that produced no diff was
   checked in `run_worker_turn`, not assumed.
7. **No new CI assertion.** See the verification plan. A reviewer who
   wants the new paragraphs pinned the way 0039's and 0042's rules are
   pinned should say so — the argument against is that these paragraphs
   are expected to be reworded from live evidence, and a pinned wording
   quietly discourages exactly the revision this contract most needs.
8. **`config-target.sh` was verified by hand rather than run.** See
   the verification plan. The alternative was to weaken the fixture so
   it would pass inside a checkout, which `CLAUDE.md` forbids
   outright, and the assertion it fails on is about `castle`'s
   pre-flight rather than anything this task touches.
9. **`docs/tasks/0042-finding-outbox.md` §12 cites the promoted backlog
   entry by path**, and that path is deleted by this commit. Rather
   than leave a dead citation for a cold reader, a parenthetical was
   added at that citation naming this brief as where the entry went.
   The surrounding sentence — 0042's account of what 0042 did — is not
   otherwise touched; a merged brief is a record of a decision, not a
   document to keep current.

## Non-goals

- **No option surface for developer CLIs.** The genuinely right fix
  behind the motivating incident — a framework option for agent and
  developer command-line tools, so residents stop hand-maintaining a
  package list — is a separate piece of work. This task makes the
  contract stop refusing the interim configuration change and start
  filing the gap; it does not close the gap.
- **No change to `agent/castle`.** No record field, no CLI flag, no
  fold. The tiered-options behaviour is `--blocking` and 0023's resume
  path used as built.
- **No change to how findings are committed or routed.** 0042 owns
  that; this task only widens when a tenant should write one.
- **No rewrite of the contract's structure.** Items keep their numbers
  and their existing text except where §1 through §4 name it.
