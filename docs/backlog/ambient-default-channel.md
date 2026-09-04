# Silence is not a channel — the roster needs an ambient default

**What.** The router's channel roster is `notify` (a real
interruption) and `digest` (read at the next fold), with silence as
the implicit third option. Proposal 06's revision
(`docs/architecture.md`, Sequencing) points at this gap without
owning it: grading delivery only matters if there is a delivery
option worth choosing, and for most initiated-work signals neither
existing channel is that option — `notify` over-delivers, `digest`
makes the signal invisible until the next fold.

**The evidence.** Citations from memory; **[verify]** marks the
unconfirmed, per this directory's convention. A randomized trial of
smartphone notification handling (Fitz et al., *Computers in Human
Behavior* 2019 **[verify arm details]**) found batched delivery
improved well-being while the never-notify arm produced no measured
concentration benefit and *raised* anxiety, FoMO, and intentional
checking — pure suppression is strictly dominated, because the cost
of not knowing is paid in checking behavior whether or not anything
arrives. The direction this points: an ambient, glanceable,
zero-commitment surface — the vision's own "status bar turning
amber" — as the default resting place for most information, with
`notify` reserved for genuine interruptions and `digest` for the
durable account. Deep-focus suppression would then hide the ambient
surface, not silently drop what it carries.

**What it needs.** A compositor-side surface the router can drive
over IPC (a status bar segment or workspace cue — `modules/desktop`
or `modules/home` territory); a third channel value in the router's
decision records; no new sensors. The router's provenance rule gains
a genuinely different third output, which also makes its decision
records more informative for the audit.

**Priority: medium-high.** It blocks nothing, but until it lands
every routing decision for mildly time-relevant information chooses
between over-delivering and under-delivering — and the audit will be
grading channel choices from a roster with no good middle option.

*Full review: see `docs/research/pressure-test.md` (landed after this entry was written).*
