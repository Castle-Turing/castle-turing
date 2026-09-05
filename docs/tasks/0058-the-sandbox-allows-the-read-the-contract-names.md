Title: Task 0058 — the sandbox allows the read the contract names
Model: deep
Model-because: the file being edited defines the worker tenant's
permission surface, and the two available fixes differ in what they
grant — one widens the sandbox (and must carry its paired write-deny,
per the script's own design), the other rewrites contract text a
tenant reasons from. Choosing between them, and keeping grant and
contract moving as one artifact, is the deliverable; a smaller
implementer can make the refusal disappear either way without weighing
which way was right.

# Task 0058 — the contract names a read the sandbox refuses

**A note on this file's name.** It is the task id the queue allocated,
and the queue derived that id from the backlog entry by stating the
goal as "the sandbox allows the read the contract names" — which
presumes one of the two fixes. §A chooses the other one, so the
heading above is the finding rather than the queue's phrasing of the
remedy. The `Title:` line is left exactly as the queue wrote it: what
was asked for is part of the record, and quietly editing it would hide
that the answer moved.

**Before starting:** read `CLAUDE.md` and
`.claude/skills/implement-brief/SKILL.md`. Then
`docs/tasks/done/0047-tenant-permission-allowlist.md`, which is the
authority record this task extends and must not widen, plus
`agent/castle-worker-claude` around the WHICH-HOST paragraph of the
contract and the `permission_dirs` block at the end of the file. This
brief promotes `docs/backlog/the-contract-names-a-read-the-sandbox-
refuses.md`, which is deleted in the commit that adds this file.

## The finding

The worker contract instructs the tenant, in the layer-decision steps
of its prompt: "WHICH HOST MODULE IS THIS MACHINE'S? Read
/proc/sys/kernel/hostname". The same script declares the tenant's file
access as the inherited working directory plus the `permission_dirs`
additions — `$HOME/.config`, `/etc/pam`, `/sys/class/graphics/fb0`,
the private root, the edit copy, the mechanism root when configured,
and each deliverable's parent. Nothing in that list covers `/proc`.
A headless session confines every file read to its working
directories, so the read the contract orders is refused however the
Bash rules are written.

Found live by a worker turn on 2026-09-05: the tenant attempted the
read, was refused, and filed it as a finding. The turn was not blocked,
because the private flake defines a single host and nothing needed
disambiguating — which is exactly why no test would have surfaced it.
The host had no `castle.agent.repo.mechanism` configured, so the outbox
preserved the finding verbatim under `refused-destination-unconfigured`
(0042's designed refusal), and the backlog entry this brief promotes was
the manual transcription that refusal asks for.

Why it matters is 0047's own argument turned around: the contract's
authority rests on being checkable against enforcement. A permission
the contract promises and the harness withholds makes the documented
behaviour a fiction, and every fiction in the contract teaches the
tenant to discount the rest. The failure is also silent on any one-host
machine, and one-host machines are the common case — so the first
multi-host resident meets it as "the worker picked no host and filed a
question the contract says it should not have needed to."

## §A. The decision: the harness reads it, and hands the tenant the name

The backlog entry framed two candidate fixes, and the choice between
them is this task's deliverable. **Neither is what lands.** The fix is
a third shape, and the reasoning for preferring it over both is below.

**What lands.** `agent/castle-worker-claude` reads
`/proc/sys/kernel/hostname` **itself**, before it execs the tenant, and
interpolates the name into the contract. The WHICH-HOST step stops
being an errand — "read this file" — and becomes a fact plus the work
that actually needed doing: *this machine's hostname is `X`; find the
`nixosConfigurations` entry of that name and follow its imports*. The
tenant's sandbox is not widened by one path, and the contract no longer
names a read at all.

This is legitimate under the entry's second option — "changing the
contract to derive the hostname another allowed way" — and it is the
most allowed way there is: not deriving it in the tenant.

**Why not option one, widening `permission_dirs`.** The narrowest
honest form of that grant is the directory `/proc/sys/kernel`, since a
`permission_dirs` entry is a working *directory*. That subtree is the
kernel's tunables, and the entry is right that the grant is
read-*and*-write under the harness's permission model — so it would
have to carry a paired `Edit(/proc/sys/kernel/**)` deny beside it, the
shape this script already uses for its other readable roots. That is
a subtree of writable sysctls granted and then half-revoked, to fetch a
string the parent process can read for free. 0047's whole discipline is
that nothing is granted beyond what the prose names; this would grant a
great deal more than the prose names, and the deny would be the
admission of it.

**Why not a command grant either** — `Bash(hostname:*)` or
`Bash(uname:*)` added to the allowlist. It is a smaller widening than
the directory, but it is still a widening for information the harness
already holds, and it makes the answer depend on a binary being present
in the tenant's PATH on a minimal NixOS host. Same objection, quieter.

**Why handing over the fact does not undercut "look, do not decide."**
The contract is emphatic that the prompt must not settle where host
modules live — "Nothing in this prompt decides where host modules ought
to live, and you must not decide it either — look." That injunction is
about a *design* question the tenant must resolve against the
repository. A hostname is not a design question. It is a fact of the
running machine, which the harness can obtain unambiguously and the
tenant cannot obtain at all. Everything the injunction is about is
untouched: the tenant still opens `flake.nix`, still matches the
attribute, still follows the imports, still reports which files it read.

**The derivation rule must stay identical to the applier's.**
`agent/castle`'s `_hostname()` reads `HOSTNAME_PATH`
(`/proc/sys/kernel/hostname`) and falls back to `os.uname().nodename`;
that is the name `castle apply` builds its flake attribute from. The
worker's read uses the same file and the same fallback, so the host the
tenant proposes against and the configuration the resident's applier
later validates are the same host by construction. Two rules that
happened to agree would be a coincidence one edit could end.

**Judgment call recorded.** The backlog entry's analysis is the
starting position, not the decision, and this brief departs from both
of its options. If a reviewer disagrees, the disagreement is with §A
and not with a detail: option one is a working fix and it is rejected
on grant-hygiene grounds alone.

## §B. What changes

Three files, and they are one artifact in three places.

1. **`agent/castle-worker-claude`.** Before the prompt heredoc,
   alongside `mechanism_note` and `edit_dirs_note`, assemble a
   `hostname_note` from a `castle_hostname` read of
   `/proc/sys/kernel/hostname` with a `uname -n` fallback. Two states,
   not one — the same three-state honesty `mechanism_note` applies to
   the mechanism checkout:

   - **A name was read.** The note states it, says where it came from,
     and says it is the same name the applier will use.
   - **No name could be read** (both the file and `uname` failed —
     which should not happen on a Linux host and is a fact about the
     machine, not the errand). The note says so plainly and sends the
     tenant to 1d, a filed question, rather than leaving it to guess or
     to attempt a read that would be refused. A prompt that silently
     interpolated an empty string would be the same defect as the one
     being fixed, wearing the other hat.

   The WHICH-HOST paragraph interpolates `${hostname_note}` in place of
   "Read /proc/sys/kernel/hostname." The rest of the paragraph — the
   `nixosConfigurations` convention, following the imports, refusing a
   near match and filing a question — is unchanged and still carries
   the work.

   **No change to `permission_dirs`, `permission_allow` or
   `permission_deny`.** That is the point of the choice, and the test
   in §C pins it.

2. **`docs/private-layer.md`**, the paragraph beginning "Your
   `nixosConfigurations` attribute should match your
   `networking.hostName`". It currently tells a resident that the
   worker "reads `/proc/sys/kernel/hostname`". After this change the
   harness reads it and hands the worker the name; the sentence must
   say so, because a resident reasoning about what their worker can
   reach is reasoning from this paragraph. The claim that follows it —
   read from the running kernel rather than declared as a third option
   that could drift — stays true and stays.

3. **`test/agent-loop/dispatch-test.sh`**, per §C.

## §C. Verification

No new harness. The grant case in `test/agent-loop/dispatch-test.sh`
("the reference tenant grants its own permission allowlist") already
drives the real tenant with a stub `claude` that records its argv, and
already renders the prompt by rewriting `^exec claude.*` to a `cat`.
Both halves of this change are observable there, and the case that
pins the decision asserts both:

- **The prompt hands over a hostname and orders no read.** The
  rendered prompt contains this machine's actual name — computed in the
  test from `/proc/sys/kernel/hostname` with the same fallback, at run
  time, never a literal, so no hostname is written into the repository.
  It must also carry the sentence saying the tenant could not have read
  the name itself, since a wall the contract omits is the same defect
  as a permission it promises.

  The negative half greps for the **order**, `Read
  /proc/sys/kernel/hostname`, not for the path: the prompt still names
  the file as provenance — where the harness got the name, and that it
  is the same file `castle apply` uses — and that sentence is worth
  keeping. Checked by mutation both ways, including a prompt that
  hands the name over and re-adds the order beside it, which is the
  realistic regression.
- **The sandbox was not widened to compensate.** No entry of the
  tenant's `--add-dir` list is under `/proc`, and no `/proc` path
  appears in the allow or deny sections. This is the assertion that
  pins §A's choice rather than merely the symptom: a later change that
  fixed the same finding by granting `/proc/sys/kernel` would pass the
  first assertion and fail this one, and the failure message says which
  decision it is contradicting. Confirmed by mutation: adding
  `/proc/sys/kernel` to `permission_dirs` fails this assertion and
  nothing else.

Run `test/agent-loop/dispatch-test.sh` directly — plain bash and
python3, no Nix, no models, no network — and the CI check that already
runs it. `config-target.sh`, `resume.sh` and `apply.sh` also start the
real tenant and are the other three that could notice this edit; all
four pass.

**What this cannot prove**, stated for the same reason 0047 states it:
that a live headless `claude` honours the grant is not observable from
here at any price. What is newly true is that this particular question
no longer needs a live turn to answer, because the refusal it was about
has been removed rather than permitted.

## Non-goals

- **Not narrowing the inherited working directory.** The tenant's base
  surface is still whatever `castle work` was started in, which
  `docs/backlog/worker-tenant-working-directory-is-inherited.md` still
  owns. This task adds nothing to that surface and removes nothing from
  it.
- **Not auditing the whole contract for other unreachable reads.** The
  `/proc` read was the one found live and is the one closed here. A
  general sweep is a different piece of work and would deserve its own
  entry.
- **No new environment variable in the worker contract.** The hostname
  is read by the script, not passed to it. `castle work` is unchanged.

## Principle 01

Public mechanism: the harness reads the running kernel's hostname and
states it in the contract. Private configuration: the name itself, and
the `nixosConfigurations` entry it selects, both of which live in the
resident's own flake and never in this repository.
