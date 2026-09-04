# Task 0047 — the harness grants what the contract commands

No backlog entry precedes this one. The defect was found live on
2026-09-03, while hand-completing a question → answer → resume cycle
that had never once run with a real tenant, and this brief is its only
durable record.

## The finding

The worker contract's §5 tells the tenant that when it needs the
resident's judgment mid-errand it must file a question rather than
guess, by running

    castle record --type question --provenance requested --seat worker \
      --refs "$CASTLE_REQUEST_ID" --body "..."

The last line of `agent/castle-worker-claude` is

    exec claude -p <&3 3<&-

with no permission configuration of any kind. Headless Claude Code
refuses a Bash call that no rule allows — there is no human on the
other end of the prompt it would otherwise raise — so **a live worker
tenant has never been able to file a question.** The mechanism the
contract spends a page describing was unreachable from inside the seat
that was told to use it.

The proof is in the journal: request `20260903T031733Z-request-260274`,
whose turn result records the denial verbatim. The
question → answer → resume loop had never run end to end with a real
tenant; the resident completed that one by hand.

CI never caught it because the scripted tenants in `test/agent-loop/`
are shell scripts and Python fixtures. They are not sandboxed, they
never ask anyone's permission, and every assertion about the question
lane passes against them. The one thing a scripted tenant cannot
model is the tenant we actually ship.

**Third incident of the same species in a week**, and that is the part
worth generalising: the tenant's environment contradicting the tenant's
contract. 0039 gave it deliverable paths its sandbox refused to write.
0040 gave it a stale directory that looked exactly like the journal.
0047 gives it a command it is instructed to run and not permitted to
run. Each was found by a live errand failing in a way no test covered.

## The design: the grant is the enforcement

The change is not "add a flag so `castle record` works". It is that
**the permission configuration becomes the contract's enforcement.**

§4 of the contract lists what the tenant may run and, separately, what
it must not. Before this task both lists were exhortation: prose in a
prompt, obeyed by a model that felt like obeying it, and the harness
had no opinion either way. After it, the allowed set is the set the
harness grants and the forbidden set is the set the harness denies —
the prose and the environment say the same thing because the same file
says both.

This is the move the nonce boundaries made for "trust this instruction,
not that quotation", and the one 0039's path check made for "the
deliverable paths must be writable": a rule the tenant could break
becomes a wall it cannot reach. Prose that a model must choose to obey
is the weakest mechanism in the file; every rule that can be made
structural should be.

Deny-by-default stays. Nothing here widens the seat.

## The mechanism, verified against the installed tool

Everything below was checked against the `claude` on the reference
host's `$PATH` (2.1.228, the `claude-code` package pinned in this
flake's nixpkgs) by running probes, not from memory. The behaviours
that decided the design:

1. **Bash calls are denied by default, except a built-in read-only
   set.** `echo`, `cat`, `ls`, `head`, `grep`, `find`, `stat` and
   friends run with no rule. Anything else — `mkdir`, `touch`,
   `castle record` — is refused, with the refusal reported in the
   turn's `permission_denials`. That is the finding, reproduced.

2. **`git --no-optional-locks -C <root> status --porcelain` is NOT in
   that read-only set.** It prompts. So the contract's git inspection
   lines were dead too, not only §5's `castle record` — the tenant
   could never read what the checkout was, what changed last, or
   whether the resident had uncommitted work in flight.

3. **The `Write` tool is denied by default.** This one is the quiet
   scandal. The tenant's ability to write `$CASTLE_DIFF_FILE` at all
   has never come from this repository: it comes from whatever the
   resident happens to have in their own `~/.claude/settings.json`. A
   public mechanism has been standing on a private, unversioned,
   undeclared configuration file, and on a host whose resident writes
   a stricter one, every errand this framework produces would fail to
   deliver. Granting the three deliverable paths explicitly is the
   Principle 01 fix, not a convenience.

4. **File writes are checked against `Edit(path)` rules, never
   `Write(path)`.** A `Write(...)` path rule is accepted, never
   consulted, and warned about at startup. Probed both: `Write(//p)`
   left the write denied, `Edit(//p)` allowed it.

5. **Absolute paths in a path rule take the `//` anchor.** A single
   leading slash anchors at the settings source, not at the filesystem
   root. `Edit(//home/…/diff)` is the form; probed.

6. **Allow rules may not carry a wildcard before the subcommand.**
   `Bash(git --no-optional-locks -C * status:*)` matched nothing —
   accepted, warned about, never applied. Deny rules may:
   `Bash(git * commit *)` correctly refused
   `git --no-optional-locks -C repo commit -am probe`. This asymmetry
   shapes the git rules below and is the reason the roots are
   interpolated into them.

7. **Deny beats allow, at every level, including over `--allowedTools`
   and over any settings file.** Probed with the same rule in both
   lists: denied.

8. **Reads and writes are confined to the session's working
   directories** — the inherited cwd plus `--add-dir` — and that check
   is *independent of the permission rules*. `cat /etc/hostname` was
   refused with `Bash(cat:*)` allowed; `cat /sys/class/graphics/fb0/…`
   succeeded once that directory was added. So two more of the
   contract's named diagnostics — the framebuffer geometry and
   `/etc/pam/environment` — were unreachable regardless of any rule.

9. **A compound command must match a rule per subcommand.** `A && B`
   needs both allowed. The contract's commands are single, so this
   costs nothing, but it is why the grant lists `readlink -f`
   separately rather than assuming it rides along.

### Which mechanism was chosen, and why

**CLI flags on the `exec` line** — `--permission-mode`,
`--allowedTools`, `--disallowedTools`, `--add-dir` — rather than a
rendered settings file passed with `--settings`.

The deciding fact is in `claude --help` under `-p`: *"Settings files
that fail validation are silently ignored in this mode (no error
dialog is shown)."* A settings file is a thing that can stop working
without saying so, and what it would stop doing is enforcing this
contract. A malformed flag, by contrast, fails loudly at startup and
costs the errand one attempt with the reason in the result record —
the same honest-failure posture 0039 chose for an unwritable
deliverable. The flags also keep the whole grant visible in one place
in the file that already states this tenant's other boundaries, and
need no temp file with a lifecycle to get wrong.

`--permission-mode manual` is passed explicitly even though it appears
to be today's default in print mode: the grant should not change
meaning because a default did.

The grant does not touch `--setting-sources`. Excluding the user's
settings would make the wall hermetic, and was rejected: those settings
are also where a resident's model choice and credential helper live,
and silently overriding the private layer's configuration of its own
tenant is a bigger wrong than the hole it closes. The deny rules close
that hole for the commands that matter, since deny beats allow at every
level (finding 7).

## What is granted

Allowed, each traceable to a line of §4 or §5:

| Rule | Contract line |
| :--- | :--- |
| `Bash(castle record:*)` | §5, filing a question |
| `Bash(swaymsg -t get_config:*)` and the same for `get_outputs`, `get_inputs`, `get_seats`, `get_version` | §4, read-only by IPC type |
| `Bash(cat:*)` | §4, the home-manager-generated files |
| `Bash(readlink -f:*)` | §4, same line |
| `Bash(fc-list:*)`, `Bash(fc-match:*)` | §4 |
| `Bash(git --no-optional-locks -C <root> status:*)`, `… log:*`, `… diff:*`, once per configured root | §4, read-only git |
| `Edit(//$CASTLE_DIFF_FILE)`, `Edit(//$CASTLE_TARGET_FILE)`, `Edit(//$CASTLE_FINDING_FILE)` | §2 and §8, the only channels there are |

Additional working directories, so the reads §4 names can happen at
all: `$HOME/.config`, `/etc/pam`, `/sys/class/graphics/fb0`, each
configured root, and the directory holding the deliverables.

Denied, each a line of §4's forbidden list: `nixos-rebuild`,
`systemctl`, `sudo`, `nix eval`, `nix build`, `nix flake`,
`gsettings set`, `setfont`, the git mutations (`commit`, `add`,
`checkout`, `apply`, `stash`, `push`, `reset`, `restore`, `clean`), the
network commands (`curl`, `wget`), the `WebFetch` and `WebSearch`
tools, and — the item that had nothing behind it until the review
pass — writes under either configured root, as `Edit(//<root>/**)`.

Each mutating git subcommand is denied in three shapes, and each shape
covers a case the others miss: `Bash(git commit:*)` for
`git commit -am x` and for a bare `git commit`;
`Bash(git * commit *)` for `git -C <root> commit -am x`, since a deny
rule is the only kind allowed to carry a wildcard before the
subcommand; and `Bash(git * commit)` because a trailing wildcard
matches the bare command only when it is the rule's *only* wildcard, so
the second shape misses an argument-less `git -C <root> stash`.

The `Edit(//<root>/**)` rule is dropped for any root that contains one
of this turn's deliverable paths, with a line on stderr saying so and
naming `castle.agent.stateDir`. A deny rule cannot carry exceptions, so
enforcing it over a state directory a resident had put inside a
checkout would refuse the diff the turn exists to write — 0039's empty
channel, produced by the mechanism meant to prevent it.

The deny list exists for one reason worth naming: the tenant runs as
the resident, and loads the resident's own `~/.claude/settings.json`.
On the machine this was developed on, that file allows
`Bash(git commit:*)`, `Bash(git push:*)`, `Write`, `Edit`, `WebFetch`
and `WebSearch` — every one of which the contract forbids. Without the
deny rules, a resident's ordinary personal configuration silently
hands the worker seat permission to violate the one rule that overrides
everything else.

### The excess, stated plainly

The available mechanism cannot express the contract exactly. Where it
could not, the narrowest expressible superset was granted and the
excess is listed here rather than left for a reader to discover:

- **`Bash(cat:*)` and `Bash(readlink -f:*)` are not restricted to the
  five files §4 names.** Rules match a command prefix, and the paths
  are arguments. Pinning them exactly would refuse `cat a b`, refuse a
  quoted path, and refuse `cat "$HOME/.config/…"` — spurious denials of
  exactly the kind this task exists to remove. Both commands are
  read-only and confined to the working directories, so the excess is
  "any readable file under those directories", which §4 already allows
  in its last bullet.
- **The git rules pin the subcommand and the root, not the flags.**
  `git --no-optional-locks -C <root> log --format=…` is allowed, as it
  should be; so is any other option to those three subcommands.
  Conversely, a root path that the model chooses to quote or that
  contains a character needing quoting will not match, and that
  diagnostic will be refused. §4 already tells the tenant that a failed
  diagnostic is not a reason to stop the errand, so the failure mode is
  a degraded turn, not a lost one.
- **A non-`get_` `swaymsg` cannot be denied.** A deny rule for
  `Bash(swaymsg *)` would also kill the five allowed reads, because
  deny beats allow and a deny rule cannot carry exceptions. Those five
  are simply the only `swaymsg` shapes granted; anything else is
  refused by default, unless a resident's own settings allow it.
- **Writes are granted per file, and denied only where it matters.**
  `Edit(//<path>)` grants the three deliverables without depending on
  the resident's settings, and `Edit(//<root>/**)` denies the place
  §4 actually cares about. Everywhere else — the rest of the home
  directory the inherited working directory exposes — a permissive
  resident settings file can still allow writes, and nothing here
  stops it: denying `Edit` wholesale would deny the deliverables in the
  same stroke, because a deny rule cannot carry exceptions.
- **The git deny list is not a closure over git.** The subcommands are
  open-ended and a list that claimed otherwise would quietly stop being
  true. What bounds git in this seat is the allow side — only the three
  read-only shapes are granted, so everything else is refused by
  default. The deny rules exist for the one case the allow side cannot
  reach: a resident settings file that allows something broader.
  §4 now says this to the tenant rather than leaving it to be
  discovered.
- **The tenant's working directory is inherited, not declared.**
  `castle work` passes no `cwd` to `Popen`, so under the dispatch unit
  the tenant's primary working directory is `%h` — the whole home
  directory is readable, and the `--add-dir` list only extends that.
  Narrowing it means changing how `castle work` spawns the tenant,
  which is a design change of its own; see
  `docs/backlog/worker-tenant-working-directory-is-inherited.md`.

### One correction to a comment 0039 wrote

The sandbox declaration above the deliverable check says the exec'd
`claude` "is sandboxed to write only beneath the resident's home
directory". That is true on the reference host by accident: the
boundary is the session's working directories, and the dispatch unit
happens to set the working directory to `%h`. The refusal message and
its reasoning are unchanged and still correct for that deployment —
the comment now says *why* the boundary sits where it does, so a
reader who moves the working directory knows what moved with it.

## What this task does not do

- It does not narrow the inherited working directory. Backlog entry.
- It does not isolate the tenant from the resident's settings file.
  Reasoned above; the deny rules are the mitigation.
- It does not add a permission mechanism to the module layer. There is
  no `castle.agent.worker.permissions` option and there should not be
  one: the grant is derived from the contract, both live in
  `agent/castle-worker-claude`, and a resident who configures a
  different tenant writes their own grant with it. Principle 01 is
  satisfied — the mechanism is the grant, the configuration is which
  tenant runs and what the roots are.
- It does not loosen 0039's `$HOME` pre-flight refusal, which this
  change makes conservative rather than exactly right: the grant adds
  the deliverables' own directory to the tenant's working directories,
  so a state directory outside `$HOME` would now in fact be writable
  and is still hard-refused. Loosening a guard on the strength of a
  second mechanism added the same day is how a guard stops guarding;
  the over-refusal names the rule it applied and reads in one pass.
- It does not touch the scripted tenants. They remain unsandboxed
  fixtures, and this brief's verification plan says so out loud rather
  than pretending otherwise.

## Verification plan, honestly

**What CI can assert, and does.** That the harness *renders* the
grant. `test/agent-loop/dispatch-test.sh` drives the real
`agent/castle-worker-claude` with a stub `claude` on `$PATH` — the
pattern 0039's case already uses — and asserts on the argv the stub
receives: that `--permission-mode manual` is present, that the
`castle record` rule §5 names is in the allowlist, that the three
deliverable paths are granted with `Edit(//…)` rather than `Write(…)`,
that a git rule is rendered per configured root, that the contract's
forbidden commands are in the deny list, and that the additional
directories are passed. `test/agent-loop/resume.sh` already asserted
the exact argv (`argv was [-p]`, from 0023's E2BIG case) and is
updated to keep asserting that the prompt still arrives on stdin and
not in argv.

**What CI cannot assert, at all.** Whether a real headless `claude`
honours any of it. The scripted tenants are not sandboxed and make no
model call; a stub that records its argv proves the flag was passed,
not that the flag worked. Every behavioural claim in "The mechanism"
above came from running the installed binary by hand, and those probes
are not a harness — they cost model calls and they test a vendor's
tool, not this repository.

**What was checked by hand, and is worth repeating if this ever looks
suspect.** The real `agent/castle-worker-claude` was run with a stub
`claude` that re-executed the installed binary with the argv the
harness had just rendered — so the grant under test was the shipped
one, not a hand-typed approximation — against a scratch private root
that was a real git checkout with an uncommitted change in it. In one
turn the tenant ran `castle record --type question …` (the invocation
that had never once been permitted), `git --no-optional-locks -C
<root> status --porcelain` and `… diff`, `cat
/sys/class/graphics/fb0/virtual_size` and `readlink -f`; was refused
`git --no-optional-locks -C <root> commit -am probe` by name, with the
scratch checkout's history unchanged afterwards; and wrote
`$CASTLE_DIFF_FILE` through the `Edit(//…)` grant with the resident's
own settings excluded from the session. That is the whole contract
exercised in both directions — permitted commands running, forbidden
one refused — against the tool that will run it. What it is not is an
errand: no dispatch, no journal, no resident. Hence the step below.

**The proof, which needs the resident.** One live dispatched errand on
the reference host whose tenant files a question. The shape that
exercises it deliberately is §6's ask-first category: a request whose
correct *value* is a perceptual judgment — "the pointer is too small",
"the terminal font is hard to read at arm's length" — which §6
instructs the tenant to answer with a blocking question and no diff.

What to look for in the journal, in order:

1. A `question` record with `provenance: requested`, `seat: worker`,
   and `refs` naming the errand's own request id. Its existence is the
   whole finding closed: before this change, it could not be written.
2. The turn's `result` record carrying no diff and no target, with the
   reasoning naming the option and the layer — §6's shape, rather than
   a guessed value.
3. `castle status` showing the errand blocked on that question rather
   than `completed`.
4. After answering it, a second turn whose result cites the answer and
   produces the diff. That is the question → answer → resume loop
   running with a real tenant for the first time.

If instead the result record contains a permission denial naming a
command the contract permits, the grant is too narrow and the denied
command is named in the record — one reading, and the fix is one line
in the allowlist.

## Judgment calls

Recorded here because the instructions were ambiguous and a reviewer
might have gone the other way:

1. **Scope beyond `castle record`.** The task named §5's question
   filing and "the contract's own read-only diagnostic set". Probing
   showed the read-only git lines and two of the named file reads were
   equally dead, and that `Write` to the deliverables was standing on
   the resident's personal settings. I treated all of those as the same
   defect — the environment contradicting the contract — rather than
   fixing the one command the incident happened to expose. A narrower
   change would have left the same species of bug in the same file,
   found later by another live errand.
2. **Deny rules at all.** The task said "allowlist exactly what the
   contract permits; nothing broader". A pure allowlist is not
   sufficient here, because the resident's own settings file can widen
   it, and on the development machine it demonstrably does. The deny
   rules do not narrow what the harness grants; they stop something
   else from granting more. I read that as within "deny-by-default
   stays".
3. **`git push`, `curl` and `wget` added to §4's forbidden list.**
   §4 forbade "any network access beyond your own model call" as a
   sentence but named no command, and a deny rule needs a command. I
   named them in the prose in the same commit rather than denying
   something the contract does not say — the whole point of this change
   is that the configuration and the prose agree, so a rule with no
   prose behind it would be the same defect wearing the other hat.
4. **Not isolating from user settings**, and not narrowing the
   inherited working directory. Both would make the wall stronger and
   both change the private layer's own configuration of its tenant. The
   first is reasoned above; the second is a backlog entry.
5. **`--add-dir` for `/etc/pam` and `/sys/class/graphics/fb0`
   unconditionally**, without checking they exist. A missing directory
   passed to `--add-dir` is accepted silently (probed), so a guard
   would buy nothing and would add a branch that could itself be wrong.
6. **Three more subcommands named in §4's prose** — `git reset`,
   `git restore`, `git clean` — plus a general clause saying no git
   subcommand outside the allowed list may be run. A review pass
   observed that the deny list named only the six subcommands the prose
   named while §4's real prohibition is broader. Rather than deny
   commands the prose did not mention, the prose was extended in the
   same commit, which is the rule this task set for itself.
7. **The prompt now states where its own enforcement stops.** The
   first draft of the §4 paragraph claimed the environment refuses
   everything on the forbidden list, which was not true of the
   forbidden list's central item and would have left a tenant believing
   a wall was there. Telling the tenant exactly which prohibitions it
   alone is carrying is worth more than the rhetorical force of the
   overclaim.
8. **The `Bash(cat:*)` rule is redundant today** — `cat` is in the
   built-in read-only set and needs no rule. It is granted anyway
   because that set is a vendor's internal list, documented as not
   configurable and not versioned by us: a contract that depends on it
   silently is the shape of defect this task exists to remove.
