# Design Principle 01: Open by construction, personal by configuration

*Castle Turing — design principles series. This is the first formally adopted principle; it constrains all architecture decisions that follow.*

## The principle

Everything built in this project is open source and reproducible by others. Anyone with compatible hardware should be able to clone the repo, supply their own private layer, and get *their* Castle Turing — not a copy of ours.

## The split this forces

The system divides cleanly into two layers:

**The framework (public).** The flake and module structure, window manager glue, mail and calendar machinery, the decision journal format, the escalation ladder, the interruption grammar, all agent tooling, and all design documents. This is the castle.

**The person (private).** The stated-priorities document, the configured authority taxonomy, account credentials and secrets, mail filters, hardware host modules, and the agent's accumulated model of its user. This is the resident. The public repo defines the *slot* for each of these; it never contains the contents.

The Primer is the reference: one artifact, built once, that becomes a different book for every reader. Customization is not a fork of the code. It is the contents of the private layer.

## Consequences (binding on the architecture)

1. **Secrets management is foundational, not retrofitted.** Secret/private-state tooling (agenix, sops-nix, or equivalent) enters the repo before the first credential exists, so nothing personal is ever committed to the public tree — including in history.
2. **Hosts are modules.** The XPS 13 9370 is `hosts/xps9370/`, one entry among possible hosts, with no hardware assumptions leaking into shared modules. Adopting the project on other hardware means writing one host module.
3. **The person is a documented interface.** The shape of the private layer — what files it contains, their formats, what the agent reads from where — is specified in public docs, so someone else knows exactly what to write to make the system theirs.
4. **Docs are written for strangers.** Every design document assumes a reader who is not us, on hardware that is not ours, with priorities that are not ours.
5. **A feature that can't split is a design smell.** If something can't be expressed as public mechanism plus private configuration, its design is not done.

## Test

Could a stranger reproduce this system for themselves this weekend, without ever seeing our private layer, and without us in the room? Every merge should keep the answer yes.