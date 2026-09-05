# Confirming a switch suggests nothing to check

**What.** After an activation, Castle asks whether the machine is
working, and rolls back if nothing says so within the window (task
0048). The question invites a verdict but suggests no basis for one.
On 2026-09-05 the resident — minutes after the first end-to-end
change in the project's history, in their own words exuberant —
confirmed a switch that had silently discarded every Sway keybinding
except the two the change added. The rollback window was open, armed,
and pointed at exactly this generation; it closed unspent because the
one check that would have failed ("do your chords still work?") was
never suggested, and the resident had no reason to think of it.

**Why this is the mechanism's to fix, within a boundary already
drawn.** The system knows what the change touched — the applied diff
names the files and options it modified, and the builder knows both
generations. A confirmation that says "this switch changed
`wayland.windowManager.sway.config.keybindings` — check a binding you
did *not* just add before confirming" acts on information it was
given — and the breadth matters: in the motivating incident the two
added bindings were the only ones that worked, so "check a binding or
two" would have passed on the broken machine. which is the
right side of the Clippy boundary the resident drew in
[[the-modal-could-choose-its-opening-view]]: shown quietly, derived
from the change itself, volunteering nothing about anything else.
Filed at the resident's direction, same day: a confirmation prompt
that suggests what to check "was exactly what I was thinking."

**What it needs, roughly.** A cheap mapping from the diff's touched
options to a human-checkable sentence — even just naming the files or
option paths that changed would beat the current silence. Anything
smarter (per-option check suggestions) can grow behind the same line.
The window's default posture — roll back unless confirmed — is
untouched; this only makes the confirmation a considered act instead
of a reflex.

**Why it can wait.** The window itself works, and a resident burned
once now checks. But that is scar tissue doing a mechanism's job, and
the entry exists so the scar gets replaced before a subtler breakage
— one whose check nobody would improvise — meets the same reflex.
