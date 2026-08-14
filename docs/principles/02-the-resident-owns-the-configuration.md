# Design Principle 02: The resident owns the configuration

*Castle Turing — design principles series. Draft: adopted only when
merged by the human.*

## The principle

The private layer is not data consumed by the public system — it is the
top of the stack. The private repo instantiates the castle; the public
repo cannot name any resident.

## What this inverts

The obvious architecture is a public system that reads private values: a
framework repo holding `nixosConfigurations`, with a hole where the
personal data goes. That puts the person inside the machine's structure —
the public repo decides what a resident is, and the private layer fills
in blanks at the machine's convenience. History already showed where that
leads: the reference host committed a real username and SSH key, because
the configuration lived where the person's values had nowhere else to be.

Inverted, the dependency points one way only. The public repo exports
mechanism — modules, options, documented slots — and compiles against a
dummy resident in CI. The private repo is the flake that gets built: it
takes the public repo as an input, pins it, and supplies the person. The
resident is the root of the dependency tree, not a leaf.

## Consequences (binding on the architecture)

1. **The public repo has no installable configuration.** Its
   `nixosConfigurations` exist only to prove in CI that the exported
   mechanism evaluates end to end, and their resident values are
   obviously fake (`resident`, a labeled placeholder key). Anything a
   person would actually boot lives in a private flake.
2. **Nothing person-shaped may be required at evaluation time by the
   public repo itself.** If a public module cannot evaluate with dummy
   values, its interface is wrong.
3. **The pin is the audit artifact.** A private flake.lock records
   exactly which public rev a resident runs; updating the pin is the
   deliberate act of adopting new mechanism. The weekly audit reads
   diffs of that pin the same way it reads the decision journal.
4. **Remediation is part of the principle.** When a person leaks into
   the public tree, the fix is not only removing it from the tip but
   from history, while history is still cheap to rewrite — unmerged
   branches now, never after they carry other people's work.

## Test

Search the public repo — every file, every commit, every branch — for
any string that identifies a person. The result must be empty, and the
system must still build someone's actual machine the same day, from
their private flake.
