# The contract names a read the sandbox refuses

**What.** The worker contract instructs the tenant, in its
layer-decision steps: "WHICH HOST MODULE IS THIS MACHINE'S? Read
/proc/sys/kernel/hostname" (`agent/castle-worker-claude`, the prompt
heredoc). The same script grants the tenant's file access as its
inherited working-directory surface plus the `permission_dirs`
additions — `$HOME/.config`, `/etc/pam`, `/sys/class/graphics/fb0`,
the private root, the edit mirror, the mechanism root when configured
— plus each deliverable's parent directory. Nothing in any of that
covers `/proc`. The contract therefore documents as allowed a read
its own enforcement refuses.

**Provenance.** Found live by a worker turn on 2026-09-05: the tenant
attempted the read the contract names, was refused by the sandbox, and
filed it through the finding lane. The turn was not blocked — the
private flake defines a single host, so nothing needed disambiguating
— which is exactly why this would not have surfaced from a test. The
host had no `castle.agent.repo.mechanism` configured, so the outbox
preserved the finding verbatim in the result under
`refused-destination-unconfigured` (task 0042's designed refusal —
0044 only routes mechanism diffs into the same lane), and
this entry is the manual transcription that refusal asks for.

**Why it matters.** The contract's authority rests on being checkable
against enforcement — 0047's lesson was that a permission the
contract promises and the harness withholds makes the documented
behavior a fiction, and every fiction in the contract teaches the
tenant to discount the rest. The failure is also silent on any
one-host machine, and one-host machines are the common case: the first
multi-host resident meets it as "the worker picked no host and filed a
question the contract says it should not have needed to."

**The fix is small but not one line.** A `permission_dirs` entry is a
read-*and-write* grant over its subtree under the harness's permission
model, which is why the script pairs its other readable roots with
explicit write-deny rules — so adding `/proc/sys/kernel` means adding
the matching deny beside it, not just the path (writable sysctls live
in that subtree; the pairing is the script's own established shape).
The alternative is changing the contract to derive the hostname
another allowed way. Whichever is chosen, contract text and grant
list must move together — they are one artifact in two places, which
is the actual defect here.
