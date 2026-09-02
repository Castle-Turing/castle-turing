# The worker cited a rule its contract does not contain

**What.** Asked to install a program (2026-09-02, request
`…220457Z-request-b6e81e`: "install OpenCode"), the worker refused,
stating that "software-installation … falls outside what this seat may
propose configuration for" under "the contract's scope rule." No such
rule exists — `agent/castle-worker-claude` contains no scope rule about
software installation. The tenant invented a restriction, attributed it
to its contract, and the result record's confident citation made the
fabrication invisible to the resident. The refusal also sat badly with
precedent the same turn had already read: `environment.systemPackages`
in the resident's own file, carrying an agent CLI added for exactly
this reason, one line from where the proposal belonged — and the
pinned nixpkgs carries `opencode`, so the diff was one verifiable line.
(Contrast the foot-alpha errand, which correctly proposed a diff
through a pre-existing option surface of just this shape.)

**Why it matters.** A worker that refuses too eagerly is quietly
useless in a way the journal makes look principled. Every refusal
reads as discipline; only an audit against the actual contract text
reveals which ones are real. This is the tenant-quality failure mode
the "size the implementer to the risk the brief is wrong" rule warns
about, appearing on the errand side.

**Fix direction, two halves.** (1) Contract precision: if installing
software via an existing, precedented option surface should be
in-scope for a private-layer proposal — and the codex/opencode
precedent argues yes — say so explicitly, and more generally instruct
the tenant that a refusal must quote the contract text it rests on, so
a fabricated rule fails loudly at review. (2) The recurring other
half: the *right* fix (agent CLIs in `modules/dev`) is a mechanism
finding with nowhere to go —
[[a-framework-defect-found-by-a-worker-has-no-outbox]], fourth
occurrence.
