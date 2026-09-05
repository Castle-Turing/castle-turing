# The modal is only just usable enough to test with

**What.** `castle-modal` carried its first real round of work on
2026-09-05, and the resident's verdict on the surface afterwards: it
has never done any useful work yet, the UX is generally very bad, and
it is only just usable enough to test with. One instance is recorded
concretely in [[an-arrow-key-is-three-dismissals]]; the rest of the
complaint list will be written from real use rather than speculation.
The direction for the fix is a real TUI, not another pass over the
line printer.

**The comps.** `docs/comps/castle-modal-design-comps.png` — produced
by an outside model that was given only a functional description of
the surface (its six jobs and its invariants) and knows nothing else
about Castle. The comps exist to demonstrate design ideas: a sectioned
inbox, scrollable result reading, a fixed review layout, an
always-available key guide. They are not a contract. Verbs, id
formats, timestamps, key chords and content in them are fiction, and
nothing may be derived from those details.

**Directions the resident has stated (2026-09-05).**

- **Shift+Enter submits** in compose and answer. Legacy terminal
  encoding cannot distinguish Shift+Enter from Enter, so this implies
  the kitty keyboard protocol (foot supports it) — the same key-input
  layer whose absence causes [[an-arrow-key-is-three-dismissals]]. One
  layer serves both.
- **The TUI is durable work.** A chat view may be added to this same
  TUI later — [[chat-mode-implies-a-conversational-turn-contract]]
  holds that question, and nothing about it is settled — so full-TUI
  investment is not throwaway even if the surface later shares the
  window with a conversational mode.
- **No agent signs its work.** The comp's signature line under the
  reasoning quote is rejected as a pattern: the label above quoted
  text says whose words they are, and that is all the attribution a
  surface adds.

**What any redesign keeps.** The invariants of the current surface,
per `agent/README.md`: no reflex keypress authorizes, decides, or
marks read — which [[an-arrow-key-is-three-dismissals]] extends with a
consequence the README does not yet state: one physical keypress must
become one logical keypress;
quoted content (diffs, questions, results, the resident's own words)
rendered verbatim and never truncated; the vocabulary rule — no
journal internals on the surface, except the exact id inside a retry
command, which is load-bearing; quiet by default — the surface shows
facts it was given and never volunteers; every flow drivable
non-interactively over stdin/stdout with flags, so CI needs no
compositor, no display, and no model; deterministic — no model in the
loop on this surface.

**Why it can wait.** The resident's stated gate (2026-09-05): Castle
completes one request end to end before any surface is refined.
Speccing this entry promotes it to a numbered brief and deletes it in
the same commit, per convention.
