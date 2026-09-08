# A no-op switch looks exactly like a deploy

**What.** On 2026-09-06 the resident merged the OOM-defense fix
(task 0063), then rebuilt the machine to adopt it. The rebuild
succeeded — and adopted nothing: the private layer's `flake.lock`
still pinned the public repo 21 commits back, so the switch
re-produced the running generation byte for byte and re-pointed the
profile at it. Success output, zero change, discovered only because
the resident asked a session to verify (`oomctl` watch lists still
empty, the new package absent, the pin stale). The private layer's
own README carries the warning in prose — "updating the pin is the
moment new public mechanism is adopted" — and prose was not enough
at the moment of use.

**Why it matters.** This is the self-maintenance family
(`self-maintenance-is-still-manual.md`) in its subtlest form: not a
crash, a silent success. A resident who believes a fix is deployed
stops watching for the failure it fixes — strictly worse than
knowing it is not deployed. And the intended adoption was of an OOM
defense: the gap this hid was the machine's hang-on-exhaustion
window staying open while looking closed.

**Fix directions, none chosen.**

- The cheapest: `nixos-rebuild` wrappers or the eventual
  castle-driven deploy compare the built system path against the
  running one and say plainly "this switch changes nothing" —
  turning the silent no-op into a sentence at the moment it helps.
- The right home eventually: the framework-upgrade errand
  (`upgrading-the-framework-is-still-a-manual-errand.md`) subsumes
  this — an upgrade the system itself proposes would bump the pin,
  build, diff the closure, and present the change for approval,
  making the stale-pin state impossible to reach silently.
- The inquest angle: the crash-inquest design
  (`a-crash-goes-uninvestigated.md`) reads the previous boot's
  journal; a deploy-inquest reading "generation unchanged after a
  switch the operator initiated" is the same shape, cheaper.

**Open question.** Whether pin-freshness belongs on the status
surface ("running: main@8ae8756, 0 behind") — a one-line ambient
answer to "am I running what I merged?", which is the question the
resident actually asked.
