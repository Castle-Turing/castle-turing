Title: The eval-storm notifier fires once per storm
Model: standard
Milestone: none — hygiene
Model-because: the mechanism is settled in the body — a transition
rule deduplicating notifyCommand delivery only, state in
$XDG_RUNTIME_DIR, the existing VM-test stub extended to assert one
notification per storm — so deep would mostly re-derive recorded
decisions. What keeps it off the cheap tier: two semantics transfer
open (re-arm after one quiet tick or only after the window drains;
whether an all-clear notification fires) and this module's own record
shows shell-plus-state edges here reversing under scrutiny (the
BASH_ENV re-entrancy guard took two rounds to get right); the
implementer decides the open points and records them in this brief
per the design-shift rule, which is judgment a cheap model follows
off a cliff rather than exercises.

# One eval storm raises seven notifications

**What.** `castle-eval-storm-check` (modules/dev/eval-storm.nix, task
0083) runs every two minutes over a ten-minute trailing window and
keeps no state between ticks, so a single storm notifies on every
tick it remains inside the window. Observed on 2026-10-03: one storm,
15:19–15:25 (peaking at 31 nix-daemon connections in the window),
tripped seven consecutive ticks from 15:20 to 15:33 — seven
notifications for one event, the last several arriving after the
storm had already ended.

**Why it matters.** The detector's first real firing read as a
malfunction: the resident's response to the notification stream was
to ask whether the detector was too aggressive, not what was
storming. A detector that spams on true positives trains its reader
to dismiss it, which is how it ends up ignored or disabled before
the storm it exists for — alert fatigue defeating the
"nothing has to opt in" default the module argues for.

**What we already know.** The check is a stateless oneshot by
design, so deduplication needs state across ticks. The standard
shape is a transition rule — notify on quiet→storm, stay silent
while the same storm persists in-window, re-arm once a quiet tick
comes in — with the marker in `$XDG_RUNTIME_DIR`, since it should
not survive a reboot. The dedup should apply to `notifyCommand`
delivery only: the per-tick nonzero exit stays, because the
visibly-failed unit is the headless host's entire floor
(systemd already collapses repeated failures into one failed unit
state, so that path has no spam problem to fix).
`test/eval-storm/test.nix` already stubs `notifyCommand` with a
file-touching script, so "one storm, one notification" is directly
assertable there — the regression check for this entry's own fix.

**Open questions.** Whether re-arming waits for one quiet tick or
for the full window to drain — a storm that dips under threshold for
one tick and resumes is arguably the same storm, and two
notifications for it would be the same defect at smaller scale.
Whether the all-clear is itself worth one notification ("storm
ended, N connections total"), which would also give the suppressed
ticks somewhere citable to land, or whether silence after the first
alert is fine.

**What shipped.** Both open questions resolved toward the smaller
mechanism:

- *Re-arm on one quiet tick*, not on the full window draining with
  no storm ticks at all. This is also the shape the "what we already
  know" section above already named, and it costs one `rm -f` on a
  marker file rather than tracking a last-tripped timestamp and
  comparing elapsed time against `windowMinutes` on every tick. The
  trade-off accepted: a storm whose rate flickers exactly at the
  threshold boundary could re-notify mid-storm if one tick's
  trailing-window count dips below threshold and the next recovers —
  the same defect this task fixes, just smaller. Left for a future
  entry if ever observed; the threshold's own calibration already
  carries headroom over both founding incidents' rates
  (`modules/dev/eval-storm.nix`'s `threshold` option doc), which makes
  a boundary flicker unlikely in practice.
- *No all-clear notification.* This task's own title is "fires once
  per storm" — a start notification plus an end notification is two,
  not one, and reopens the alert-fatigue failure mode this task
  exists to close. Silence after the first alert is the smaller
  mechanism; the next storm's own transition notification is the only
  other signal.

Mechanism: a marker file's bare existence under `$XDG_RUNTIME_DIR`
(always set for a `systemd.user.*` unit by the user manager itself).
A storm tick notifies and creates the marker only when the marker is
absent (the quiet→storm transition); while the marker exists, storm
ticks still `exit 1` but skip the notify call; a quiet tick removes
the marker unconditionally. `test/eval-storm/test.nix` gained a
fourth node (`rearm`) with a short (`1`-minute) window so a quiet
tick can be produced by actually waiting out the window, rather than
a test asserting a time jump it never took; its subtest asserts one
notification across two persisting-storm ticks, then a genuine quiet
tick with the notification count unchanged (no all-clear), then a
second storm raising a second notification (re-arm confirmed). The
stub `notifyCommand` now appends rather than overwrites, so a line
count is a direct invocation count.
