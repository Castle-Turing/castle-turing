# The "what to check" paragraph cannot say which surface is now stale

**What.** `docs/tasks/done/0059` gives a health question a paragraph
naming the files an approved change rewrote, so a resident confirming a
switch knows where to look. It names files. It cannot say what the
2026-09-06 incident actually needed said: *the window you are looking
at will never show this — foot reads its config once, at startup, so
open a new terminal.*

The resident checked the padding in a terminal that could not have
shown the change, saw the old value, and rejected a generation that was
fine.

**Why it matters.** A suggestion to check something, given to somebody
whose only available check is guaranteed to return the wrong answer, is
worse than no suggestion: it produces a confident false negative, which
is exactly what happened. `docs/tasks/0067` moves the sharpest case out
of reach by staging session-affecting changes until a reboot — after
which every surface is new — but a live switch can still rewrite a
config file that only newly-started processes read.

**What we already know.** The seam exists. `_health_check_lines`
already receives the change's file list and the build record, and 0067
carries that paragraph across a reboot in the staged marker, so
whatever the derivation learns is delivered on both paths. What is
missing is the mapping from a changed file to the processes that
re-read it and the ones that do not.

**Why it was not just done.** The mapping is the hard part and it is
not obviously ownable. Doing it by pattern (`foot.ini` → foot) is a
table this repo would maintain forever and which is wrong on the first
program nobody anticipated — the same argument 0059 §B used to choose
files over Nix option paths. Doing it properly means asking which
running processes hold the old file open, which is a live-system probe
run at exactly the moment the machine may be broken.

**Open question.** Is there a version of this worth having that says
only the weak, always-true thing — "a program already running may still
be using the old version of these files; if what you are checking is
one of them, restart it first" — with no per-program knowledge at all?
It would have been enough on 2026-09-06.
