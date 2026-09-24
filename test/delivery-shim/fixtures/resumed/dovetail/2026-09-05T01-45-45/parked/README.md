Task: README
Asked: 2026-09-05T06:20:24+00:00
Session: 7adcf40c-5277-4f21-9c7c-83192daaa792
Status: resolved
Answered-by: agent:castle-delivery-shim for the resident (castle record 20260924T054418Z-answer-06a28b)

## Question

# Question: Launch failure detection scope and mechanism

**Context:** Backlog item "Launch failures are silent when the float step is skipped" has a real failure mode discovered by the cross-vendor gate on PR #6 (task 0005, P2 finding). The mechanism is clear: `launch.py` deliberately detaches the spawned terminal from stderr (this is necessary so the detachment doesn't block readers), but `_report_no_window` — which already distinguishes "terminal exited" from "window never mapped" — is only reached from the float step's window wait. On the skipped paths (when `--no-float` is given or the compositor is unreachable), nothing checks whether the child process dies.

**Open design questions that gate turning this into a brief:**

1. **Detection mechanism:** What should we watch on these paths to detect a failed terminal startup?
   - Option A: Short bounded poll of the child's liveness (lighter than window tree wait)
   - Option B: Same budget the float step uses for its wait
   - Option C: Something cheaper than either
   - Anything else?

2. **Socket case coverage:** Does `--print-socket`'s existing socket wait already cover enough of this case that the fix is only needed for the no-socket invocation, or should both paths be fixed?

3. **Scope of "failure":** Is a terminal that dies *after* mapping its window in scope for this fix, or should we consider only startup failures?

**What I'll do once decided:**
- Spec these answers into a numbered brief (0006-)
- Move the backlog item to done/
- Commit both

(The fix itself cannot simply inherit stderr; the detachment is there for a reason stated in the code.)

## Answer

Option B: the same budget the float step uses for its wait. Fix both paths — the socket wait does not cover enough on its own. Startup failures only; a terminal that dies after mapping its window is out of scope for this fix.

<!-- Transcribed from the castle journal: 20260924T054418Z-answer-06a28b. The resident's
     own words, verbatim; this comment is not part of them. -->

<!-- re-running the task with this answer -->
