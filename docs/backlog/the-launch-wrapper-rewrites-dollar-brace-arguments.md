# The launch wrapper rewrites dollar-brace arguments

**What.** `systemd-run` expands `${VAR}` sequences inside the command
arguments of a transient unit by default (`--expand-environment`,
present and default-on in the pinned systemd 261.1), and
`castle-launch` (modules/home/default.nix, the `exec ${systemdRun} …
-- "$@"` case arms) does not pass `--expand-environment=no`. Any
launched argv carrying a literal `${…}` — a `sh -c` one-liner meant
to expand in the *child* shell, a URL or template string containing
`${` — reaches the application rewritten against the user manager's
environment, or silently emptied where the variable is unset. Found
by review on the 0089 branch, whose own nix wrapper hit the same
behavior empirically in its VM test and ships the flag — in its new
copy only, so the repo's two scope-runners have already diverged on
a correctness flag.

**Why it matters.** Every launch class corrupts this argv shape
silently: the command runs, just not the command that was given, and
nothing anywhere says so. The wrapper's contract is
exec-what-you-were-given — nothing in this repo uses systemd-run's
expansion deliberately — so the current behavior is pure defect, and
the kind that surfaces as an inexplicable application-side bug
nobody attributes to the launcher.

**What we already know.** The fix is one flag on the exec line,
available in the pin. The 0089 branch's `modules/dev/nix-scope.nix`
carries both the flag and the regression probe shape to mirror: pass
a literal `${PATH}` through the wrapper and assert it arrives as
bytes, not as an expansion — `test/app-scopes` is where that probe
belongs for this wrapper. Before flipping the flag, verify no
existing sway binding or menu entry depends on the expansion
(expected: none; the bindings quote for the child shell, not for
systemd-run).

**Open questions.** Whether the fix is the one-line flag in each
scope-runner or the shared scope-runner factoring the 0089 review
also suggested — the flag is urgent and tiny, the factoring is not,
and they need not travel together. Whether `--expand-environment=no`
interacts with any `extraProperties` a private layer sets (expected:
no — it governs argv expansion only).
