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
