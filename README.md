# Castle Turing

An AI-native personal computing environment: an agent living at the operating
system level, customizing the whole system — and every application — to its
user. NixOS as the declarative substrate, a tiling window manager as the
agent's hands, text-native tools (maildir, direct APIs) as its interfaces,
Claude Code as the acting layer.

The name is from *The Diamond Age*: the castle where the Primer teaches Nell
computation, and escape comes through understanding the machine.

**Status: pre-alpha.** Nothing here runs yet. The design documents are the
most finished artifact in the repo; start with [`docs/vision.md`](docs/vision.md).

## The split

Per [Design Principle 01](docs/principles/01-open-by-construction.md), the
system divides into two layers:

- **The framework (this repo, public):** flake and module structure, window
  manager glue, mail/calendar machinery, the decision journal format, the
  escalation ladder, agent tooling, and all design documents. The castle.
- **The person (your repo, private):** stated priorities, the configured
  authority taxonomy, credentials, mail filters, host secrets, and the agent's
  accumulated model of its user. The resident.

This repo defines the *slot* for each private artifact; it never contains the
contents. The test for every merge: could a stranger reproduce this system for
themselves this weekend, without ever seeing our private layer?

## Layout

```
docs/            Design documents. vision.md is the founding context;
                 principles/ are numbered, formally adopted, and binding.
hosts/           One module per machine. hosts/xps9370/ is the reference
                 target (Dell XPS 13 9370). No hardware assumptions may
                 leak into shared modules.
modules/         Shared NixOS/home-manager modules — the framework proper.
agent/           Agent tooling: prompts, glue scripts, journal machinery.
test/            Automated harnesses, e.g. test/vm-install/ — the
                 install mechanism exercised end to end in CI.
flake.nix        Entry point: exports the framework's modules and a
                 CI-only example configuration with a placeholder
                 resident. Real configurations live in private layers.
```

## Reproducing this (eventually)

The intended adoption path: clone this repo, write one host module for your
hardware, supply your own private layer in the documented shape, and get
*your* Castle Turing — not a copy of ours. The private-layer interface is
documented in [`docs/private-layer.md`](docs/private-layer.md).

## Non-negotiables

1. Secrets tooling enters the repo before the first credential exists.
   Nothing personal is ever committed to this tree, including in history.
2. A feature that can't split into public mechanism + private configuration
   is a design smell; its design is not done.

## License

Everything in this repo is [MIT-licensed](LICENSE), artwork included.
