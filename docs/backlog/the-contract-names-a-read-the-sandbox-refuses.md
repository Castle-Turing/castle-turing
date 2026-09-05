# The contract names a read the sandbox refuses

**What.** The worker contract instructs the tenant, in its
layer-decision steps: "WHICH HOST MODULE IS THIS MACHINE'S? Read
/proc/sys/kernel/hostname" (`agent/castle-worker-claude`, the prompt
heredoc). The same script's sandbox confines reads to
`permission_dirs` — `$HOME/.config`, `/etc/pam`,
`/sys/class/graphics/fb0`, the private root, the edit mirror, and the
mechanism root when configured — and no entry covers `/proc`. The
contract therefore documents as allowed a read its own enforcement
refuses.

**Provenance.** Found live by a worker turn on 2026-09-05: the tenant
attempted the read the contract names, was refused by the sandbox, and
filed it through the finding lane. The turn was not blocked — the
private flake defines a single host, so nothing needed disambiguating
— which is exactly why this would not have surfaced from a test. The
host had no `castle.agent.repo.mechanism` configured, so the outbox
preserved the finding verbatim in the result under
`refused-destination-unconfigured` (task 0044's designed refusal), and
this entry is the manual transcription that refusal asks for.

**Why it matters.** The contract's authority rests on being checkable
against enforcement — 0047's lesson was that a permission the
contract promises and the harness withholds makes the documented
behavior a fiction, and every fiction in the contract teaches the
tenant to discount the rest. The failure is also silent on any
one-host machine, and one-host machines are the common case: the first
multi-host resident meets it as "the worker picked no host and filed a
question the contract says it should not have needed to."

**The fix is one line either way.** Add the path to
`permission_dirs` (a single file's directory, read-only, no secrets
live under `/proc/sys/kernel`), or change the contract to derive the
hostname another allowed way. The first preserves the contract as
written; whichever is chosen, contract text and allowlist must move
together — they are one artifact in two places, which is the actual
defect here.
