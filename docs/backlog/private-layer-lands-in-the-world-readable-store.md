# A private layer's whole tracked tree lands in the world-readable Nix store

**What.** `/nix/store` is a single global directory whose every file is
mode `r--r--r--`, readable by every process on the machine. Evaluating a
path flakeref copies that flake's entire *tracked* tree into it. So any
`nixos-rebuild --flake /path/to/private#host` — the documented way to
use Castle Turing — publishes the resident's private repo to the store.

That tree is not incidental. `docs/private-layer.md` documents it as
holding `resident.nix` (with `castle.admin.initialHashedPassword`,
`castle.admin.sshKeys`, `castle.person.gitUserName` and
`castle.person.gitUserEmail`) and, when `stateDir` points inside the repo
as the same document recommends, `state/journal/` — every request,
decision, question, answer and correction — plus `state/resident-model.md`,
one entry per fact about the resident.

Separately and additionally: NixOS's own `users.users.*.hashedPassword`
reaches the store through the activation script. `hashedPasswordFile` is
the standard escape hatch and this project does not use it.

**Why it matters.** The framework's whole premise is strangers adopting
it (Principle 01: "anyone with compatible hardware should be able to
clone the repo, supply their own private layer, and get *their* Castle
Turing"). So the threat model is not the reference host, which has one
account and one user. It is every machine an adopter runs this on — a
work laptop with an IT agent, a shared VPS with hostile neighbours, any
box where "another local process" is not a hypothetical.

"No one else uses this machine" is also weaker than it sounds even when
true, because the store is readable by every *process*, not every
*person*: a browser extension, a transitive npm dependency, or — the
sharp case for this project specifically — any AI agent with shell
access. Tasks 0023 and 0024 spend real effort controlling what a worker
tenant may see: a curated continuation packet of one errand's records,
with per-turn nonce boundaries so a previous turn cannot forge resident
speech. A tenant that can read the whole journal off the store makes that
machinery decorative.

Store paths are immutable and persist until garbage collection, so this
cannot be undone by deleting anything from the repo. And because each
distinct tree content is a distinct store path, a resident accumulates a
version history of their own private records in a place they have no
reason to think holds any.

**What we already know.** Principle 01 consequence 1 says secret tooling
enters the repo *before the first credential exists*.
`docs/backlog/secrets-tooling.md` is the standing entry for that and has
not been specced. The first credential already exists: the password hash
is in the documented `resident.nix` template. So this entry is partly
evidence that the secrets entry is more urgent than its position in an
unordered directory suggests — but it is not the same problem. Secrets
tooling answers "how does a credential get onto the machine safely";
this asks "what may an adopter's flake contain at all, given evaluating
it publishes it".

The exposure is pre-existing and independent of any one task.
`docs/tasks/0024-config-target.md` surfaced it: an early draft had the
worker run `nix eval` against the private flake on every errand, which
would have added a fresh journal snapshot per errand on top of the
per-rebuild copy. 0024 dropped that step rather than accept it, and reads
configuration files directly instead — so 0024 adds no new exposure, but
it did not and could not remove the one that was already there.

Note also that `modules/agent/default.nix` already argues this exact
hazard in miniature, as the reason `castle.agent.repo.private` is typed
`str` and never `path`: a Nix path literal "would publish every journal
entry and stated priority in that checkout to any local user who can read
the store." That reasoning is correct and was applied to one option while
the tree containing the same data goes to the store by another route.

**Open questions.** Can a private layer be structured so evaluating it
does not publish it — state and secrets outside the flake's tracked tree,
with the flake referring to them by runtime path rather than by Nix path?
What does that cost the "it survives a reinstall and travels with your
config" property the journal's current placement was chosen for? Is
`hashedPasswordFile` the right fix for the credential half, and what
supplies the file on a fresh install before any secrets tooling exists?
Should the framework refuse to evaluate, or warn loudly, when it can tell
that a resident's state directory is inside the flake it is evaluating?
And is any of this fixable at all without the secrets story landing
first, or is this entry simply the strongest available argument for
speccing `secrets-tooling.md` next?
