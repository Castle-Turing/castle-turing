# A Bash redirection can still write under a configured root

**What.** `agent/castle-worker-claude`'s `Edit(//<root>/**)` deny rule
(task 0047, "the item that had nothing behind it until the review
pass") only governs the Edit and Write tools. It is not consulted when
the tenant writes through Bash instead — for example
`cat some-file > "$CASTLE_PRIVATE_ROOT/resident.nix"`, which the file's
own `Bash(cat:*)` allow rule permits, because that rule matches on a
command-string prefix and does not parse the trailing shell
redirection. Both configured roots are also passed to `--add-dir`, so
they are already inside the tenant's Bash-writable working-directory
boundary; the `Edit` deny rule was the only thing standing between that
and an actual write, and it does not reach Bash.

**Why it matters.** §4 of 0047's contract calls "no writes under either
configured root" the central prohibition, and the deny rule exists
specifically because a resident's own `~/.claude/settings.json` cannot
be trusted to withhold that permission (0047, "The deny list exists for
one reason worth naming"). A gap that survives for exactly the tool the
deny list was built to route around defeats the reason the rule was
added, not just its coverage.

Worth being precise about the threat model the same way
[[env-stripping-defeats-write-guards]] is: the tenant is a model this
system chose to run, not an attacker hunting for the gap. The realistic
path is a model that reaches for an already-permitted command
(`cat`, `readlink -f`, one of the allowed `git`/`swaymsg` invocations)
and appends redirection because that is an ordinary way to write a
file, without the deny list ever entering its reasoning.

**What we already know.** Claude Code has a real, OS-level mechanism
for this — `sandbox.filesystem.denyWrite`, enforced by bubblewrap
(Linux/WSL2) or Seatbelt (macOS) against every Bash subprocess and its
children, immune to redirection syntax because the kernel enforces it
rather than a command-string pattern. It is not a drop-in fix here,
though:

- It is configured through `sandbox.filesystem` in `settings.json` (or
  an inline `--settings '<json>'` value), not through
  `--allowedTools`/`--disallowedTools`. This script deliberately avoids
  settings files for the flags it does control, because `claude -p`
  silently ignores a settings file that fails validation
  ("FLAGS, NOT A SETTINGS FILE" in this same script) — whether that
  same silent-ignore behavior applies to an inline `--settings` value
  is unverified.
- The sandbox itself is opt-in (`sandbox.enabled`) and, per its own
  docs, fails open by default when its dependencies (bubblewrap,
  socat) are missing — unless `failIfUnavailable` is also set, a
  resident host that lacks them would silently run this tenant
  unsandboxed rather than refuse, the same shape of failure 0039 and
  0047 both went to some trouble to avoid elsewhere.
- Whether bubblewrap/socat are present on the hosts `modules/agent`
  actually deploys to is unconfirmed.

No pattern-level fix inside `--disallowedTools` closes this
completely: shell redirection has too many spellings (`>`, `>>`, `1>`,
`&>`, `tee`, `dd of=`, …) for a deny list to enumerate, and this file's
own git-deny section already argues that kind of list "would quietly
stop being true."

**Open questions.** Should this tenant adopt `sandbox.enabled` at all,
given it changes the deployment's dependency footprint
(modules/agent would need to guarantee bubblewrap+socat on every host
that runs a worker tenant)? If so, does `--settings` accept inline JSON
reliably enough in `-p` mode to keep this script's existing
flags-not-files stance, or does adopting `sandbox.filesystem.denyWrite`
mean accepting a settings file after all? Does `failIfUnavailable`
belong on by default here, so a host missing the sandbox dependencies
refuses the errand instead of silently downgrading the guarantee? And
does the fix belong in this script at all, or in `modules/agent` as a
host-level precondition the way other hardware/dependency assumptions
are handled?
