# Decide where a stranger's host module lives

**What.** Resolve a contradiction between two of this project's own
documents about whether hardware host modules belong to the public
framework or the private layer — and then make the docs, the repo
layout, and the adoption path agree.

**Why it matters.** This determines what "adopting Castle Turing"
means for someone who is not us. It is a Principle-level question, not
an implementation detail: it decides whether adopters send pull
requests describing their laptops, or keep their machine definitions
to themselves, and therefore whether this project accumulates a library
of supported hardware or stays a framework that each person
instantiates privately.

**What we already know.**

- `docs/principles/01-open-by-construction.md` lists "hardware host
  modules" under **the person (private)** — the layer the public repo
  defines a slot for but never contains.
- `hosts/xps9370/README.md` says the opposite in practice: "To adopt
  Castle Turing on different hardware, copy this directory's shape as
  `hosts/<yourmachine>/`" — which reads as an instruction to add a
  directory to *this* repo.
- Both readings are defensible. Public host modules build a shared
  hardware library and let strangers benefit from each other's quirk
  hunting (the XPS's dead-CMOS and ath10k firmware findings are
  genuinely reusable). Private host modules avoid every adopter forking
  the framework just to describe their own laptop, which Principle 01
  explicitly says customization must not require.
- A third position exists and may be the right one: the reference host
  is public *as a worked example*, while adopters' hosts are private —
  with the framework's job being to make a private host module easy to
  write. `modules/disk-layout.nix` already points that way, since it
  takes the device as a parameter rather than assuming one.
- Nothing currently stops an adopter's private repo from defining its
  own host module inline; it just isn't documented, so nobody would
  know it is allowed.

**Open questions.** Which of the three positions? If host modules stay
public, what stops the repo becoming a hardware database with no
maintainer? If they go private, does `hosts/xps9370/` move out, stay as
a documented example, or get replaced by a template? Does Principle 01
need amending, or was the README always the thing that drifted?
