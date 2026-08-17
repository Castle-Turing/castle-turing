# Should font-sweep propose its own candidates?

**What.** Teach the agent to propose the font specs a sweep compares,
rather than requiring the resident to already know the typographic
landscape well enough to type `fc-list`-shaped strings by hand.
`tools/font-sweep.sh` stays dumb — it opens whatever specs it is
given — but something upstream of it would generate a shortlist worth
looking at.

**Why it matters.** The harness only helps a resident who can already
name candidates. Task 0016's actual sweep needed a second, unplanned
round because the first round only varied size on the framework's
incumbent font — nobody had proposed a family change until the agent
did, mid-session. Formalizing that step turns a one-off insight into
something every future sweep gets by default, instead of depending on
an agent happening to think of it that day.

**What we already know.**

- **This already happened once, informally, and it worked.** During
  task 0016's UI-font sweep, the agent proposed `Iosevka Aile` as the
  quasi-proportional companion to the terminal face
  (`Iosevka Slab`), and separately flagged that `Iosevka Etoile` — the
  quasi-proportional *slab-serif* cut of the same superfamily — is
  arguably the closer stylistic match to a slab terminal face, even
  though the resident had asked for "a sans." The resident swept both
  and chose `Iosevka Aile Medium` at size 10. See "How the sizes and
  the typeface were picked" in
  `docs/tasks/0016-legible-defaults.md`. That is the behaviour worth
  making repeatable rather than depending on an agent noticing again.
- **Classic pairing heuristics are the obvious starting content**, not
  a novel algorithm: sans for titles/UI paired with serif for body is
  the canonical example; pairing cuts from within one superfamily (as
  Iosevka's Slab, Aile, and Etoile do) is a reliable way to guarantee
  coherence; and weight trades against size — 0016 found Medium at 10
  reads about as solid as Regular at 11 — so a suggestion has to be a
  *pairing plus sizes*, not two family names on their own.
- **Candidate generation is partly mechanizable, not purely taste.**
  `fc-list` exposes installed families along with `spacing` and
  `style` metadata. That is exactly how 0016 established that `Aile`
  and `Etoile` report no `spacing` property (against `spacing=90` for
  the monospaced cuts), which rules them out for a grid terminal. A
  suggester has to treat that as a hard constraint it checks, not a
  preference it might override.
- **Principle 01 applies cleanly.** How candidates get generated and
  presented is public mechanism; which pairing a resident actually
  picks after looking is private configuration, exactly as
  `tools/font-sweep.sh` already keeps the sweep mechanism public and
  the winning specs private.

**Open questions.** Where does the suggesting live — a static
heuristic table inside the shell script, or the agent layer, where a
model can reason about an installed font list and a stated face?
`tools/README.md` already records an unresolved boundary about
whether `font-sweep.sh` belongs in `tools/` (repo tooling) or
eventually on a deployed system as a `castle-` command; this entry
sharpens that question rather than settling it, since "who proposes
candidates" and "where the tool lives" may not have the same answer.
How does the agent avoid substituting its own taste for the
resident's — `docs/vision.md`'s "Serve stated preferences, not just
revealed ones" is the relevant principle, and a suggester that quietly
narrows the options before the resident sees them is a feed algorithm
for fonts. Should a suggestion carry its reasoning inline ("Etoile is
the slab-serif cut of your terminal face's superfamily") or leave that
for the resident to ask — `docs/vision.md`'s paragraph on comprehension
having an altitude argues the default owed here is a legible map, not
a forced explanation, so silence is not obviously wrong. And does a
rejected-but-recorded suggestion (Etoile, in 0016) belong anywhere
after the sweep ends, or is the sweep itself the whole record?
