# The worker cannot write its own deliverables

**What.** `castle work` allocates `$CASTLE_DIFF_FILE` and
`$CASTLE_TARGET_FILE` under `/tmp`, but the reference worker tenant
(`castle-worker-claude`, a headless `claude -p`) runs under a sandbox
that permits writes only beneath the resident's home directory. On the
first live dispatched errand that actually produced a diff
(2026-09-01, the foot `[colors]` deprecation), the tenant could not
write either file: it diagnosed correctly, drafted a correct diff, and
then — honestly, and in prose — staged both deliverables as loose
files in `$HOME` instead. The official channel stayed empty, so the
result record carries "(no diff produced)", review mode has nothing to
show, and the entire 0025/0026 approve-and-apply chain is unreachable
for exactly the change it was built to carry. A second worker turn
then spent a whole errand explaining the stranded files to the
resident.

**Why it matters more than its size.** This is the single mechanical
blocker between today's system and the loop the vision wants: request
→ proposal → resident approval → applied by the system. Everything
downstream of the diff file exists and is tested; the handoff into it
is what is broken.

**Fix direction, for the brief to argue.** Allocate the output files
somewhere the tenant can provably write — beside the journal under
`$CASTLE_STATE_DIR` (a `work/` scratch area, cleaned by the sweep) is
the natural candidate, since the state dir is already required,
already private, and already home-anchored on every real layout. An
alternative is for the worker wrapper to declare its sandbox to
`castle work` and refuse the turn early when the paths are unwritable
— loud beats improvised. Whatever is chosen: the degraded behavior
must never again be "deliverables scattered in `$HOME`, channel
empty, result says completed."
