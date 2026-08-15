# Laptop ergonomics

**What.** The hardware affordances a laptop is expected to have:
brightness and volume keys, battery status and low-battery handling,
suspend/resume on lid close, trackpad gestures, audio device switching,
and sensible power management.

**Why it matters.** Explicitly deferred as a non-goal of task 0005
(`docs/tasks/0005-dogfooding-desktop.md`) to keep that milestone
focused on whether the machine can host its own development. It is the
difference between "boots and runs a compositor" and "usable on a couch
for an evening" — which is the difference between a demo and a machine
someone actually lives in.

**What we already know.**

- Some of this arrives free from the `dell-xps-13-9370` nixos-hardware
  module and from PipeWire; the remainder is Sway keybindings plus a
  handful of NixOS options.
- Sway has no built-in handling for media keys — they need explicit
  bindings to `brightnessctl`/`wpctl` or equivalent.
- Suspend/resume is the risky one on this chassis: it interacts with
  the firmware, and this machine already has a documented history of
  boot-path trouble (`docs/tasks/0003-findings.md`). Worth testing
  deliberately rather than assuming.
- Public/private split is clean here: the mechanism (which keys do
  what) is framework; the resident's preferences (keybinding layout,
  idle timeouts) belong in the private layer.

**Open questions.** How much is configuration versus per-resident
preference — where exactly does the option surface sit? Does idle/lock
behaviour belong here or with the future attention-management work,
given the agent will eventually have opinions about the screen?
