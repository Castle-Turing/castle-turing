# The modal chord may be the wrong default

**What.** Task 0034 collapsed every Castle surface onto one chord and
kept `Mod4+Shift+Return` because it was already there — an
incumbency argument, not a design one. The resident suspects
`Mod4+Space` (or similar) has real precedent: a single
modifier-plus-Space chord summoning "the place where you type what
you want" is an established pattern across other tools, and copying an
established UX pattern is arguably better than teaching a new one,
even to a one-user system. Nobody has actually surveyed the
precedent: which tools, which chords, what they summon, and what
`Mod4+Space` (and nearby candidates) already collide with in stock
Sway, in this framework's own bindings, and in common applications.

**Why it can wait.** The chord is one line in `modules/home` with an
existing private-layer override point; changing the default later
costs a rebuild and (for a one-user system) nothing else. Getting it
wrong now costs equally little, which is exactly why the research
should happen once, calmly, rather than the default churning on
instinct.

**What speccing looks like.** This is a research brief, not an
implementation brief: enumerate the precedent, enumerate the
collisions, recommend a default, and only then change one line. See
[[the-modal-could-choose-its-opening-view]] for the adjacent question
of what the chord opens into.
