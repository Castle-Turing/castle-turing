# Principle 01 says open source; the repo says all rights reserved

**What.** `docs/principles/01-open-by-construction.md` opens with:
"Everything built in this project is open source and reproducible by
others. Anyone with compatible hardware should be able to clone the
repo, supply their own private layer, and get *their* Castle Turing."

There is no `LICENSE` file in this repository, and `README.md` does not
name a license either. Under default copyright, a public repo without a
license grant is **all rights reserved** — no permission to use, modify,
or redistribute. The stated principle and the legal reality are
opposites.

**How it surfaced.** Task 0014 added the repo's first non-text artifact
(a wallpaper). The brief instructed the implementer to note in a README
that the image was "covered by the repo's existing LICENSE." The
implementer checked, found no such file, and wrote an honest README
saying so rather than inventing the claim. Worth recording that the
error was in the brief, not the implementation.

**Why it matters more than paperwork.** Principle 01's own test is
"could a stranger reproduce this system for themselves this weekend,
without ever seeing our private layer, and without us in the room?"
Legally, today, the answer is no — not because anything technical is
missing, but because they have no permission. Every adoption-path
document in `docs/` describes a thing a reader is not currently
licensed to do.

It also compounds now that binary artifacts are in the tree. Code with
an implicit "obviously they meant it to be usable" is one thing;
generated artwork with no grant is the kind of thing a cautious adopter
strips out, or avoids the project over.

**What needs deciding.**

- **Which license.** The project's values point toward something
  permissive (MIT/Apache-2.0) or copyleft (GPL/AGPL) depending on
  whether derivative private layers and forks should be obliged to stay
  open. Note the private-layer split makes this less binding than usual:
  a resident's own configuration is a separate repo and would not be a
  derivative work in most readings.
- **Whether artwork carries the same terms as code.** Many projects
  license code and assets separately — code under a software license,
  media under CC-BY or CC0. The wallpaper is generated, so provenance is
  clean, but "generated" is not a license.
- **Whether `chevaline` should match.** That repo *does* have a LICENSE.
  Two sibling repos under one org with different answers is a question
  someone will eventually ask.

**Not urgent, but cheap now and awkward later.** Adding a license to a
single-contributor repo is a one-file commit. Adding one after outside
contributions arrive requires every contributor's agreement.
