Title: Allow github-actions through claude-review's bot guard
Model: standard
Model-because: a one-line YAML edit against the resident's explicit
instruction, done in the session that diagnosed it — no delegation, so
the tier is the session's own. Nothing here is judgment beyond what the
diagnosis already settled; a smaller model could have made the edit,
but routing a one-line change to a sub-agent would cost more than it
saves.
Milestone: none — hygiene

# 0078 — Allow github-actions through claude-review's bot guard

On PR #139 the `claude-review` check failed without reading the diff:
`anthropics/claude-code-action` refuses runs initiated by a bot actor
not on its `allowed_bots` list, and the triggering event was a fix
commit pushed by the review-findings handler under the default
workflow token, which attributes to `github-actions`. The list said
only `claude`, so the handler's own push made the review gate report
failure on every PR it touched.

The resident's ruling (2026-09-24): add `github-actions` to
`allowed_bots`. The alternative — moving the handler's pushes to the
org review-bot App identity, which the resident's profile already
specifies for a related reason (default-token pushes do not re-run
checks) — remains open and is noted in the workflow comment; this
change unblocks review on handler-touched PRs today without deciding
that.

Verification: the change is config read only by GitHub Actions, so the
check is the next PR whose head was pushed by `github-actions` —
claude-review should run rather than refuse. No local test exists;
`.github/workflows/**` edits fire the reachability workflow, which
must stay green.
