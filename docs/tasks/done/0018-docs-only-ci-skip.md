# Task 0018 — Don't run the build gate on documentation-only changes

**Before starting:** read `CLAUDE.md`, `.github/workflows/check.yml`,
and the long `paths-ignore` comment block in
`.github/workflows/claude-code-review.yml` — that comment is the
decision this task partially reverses, and the reasons it gives are
why the change is narrower than it first looks. Work on branch
`ci-skip-docs-only`; this brief rides it. PR to `main`.

**Goal.** A pull request that changes only prose stops spending ~5
minutes of CI, without ever skipping a check on a change that can
actually alter the built system.

## What is actually broken, measured

PR #42 changed exactly two files, both under `docs/backlog/`, and still
ran four jobs:

| Job | Duration |
|---|---|
| `flake-check` | 4m 9s |
| `sway-config-check` | 53s |
| `agent-loop-test` | 11s |
| `modal-headless-test` | 5s |

**The expensive workflows behaved correctly and are not the problem.**
`vm-install-test` and `desktop-loop-test` did not run — their allowlist
`paths:` filters matched nothing — and `claude-code-review` did not run
either, because its `paths-ignore` already covers `docs/**`. Only
`check.yml`, which has no path filter at all, fired. Verified with
`gh pr checks 42`, not inferred from the YAML.

**The recorded reason for leaving `check.yml` unfiltered no longer
holds.** The comment in `claude-code-review.yml` says those jobs "spend
no model tokens, finish in under a minute, and are the gate." Two of
those three are still true. "Under a minute" is wrong by roughly 4× —
`flake-check` alone is over four minutes.

**And the other half of that reason does not apply today.** The comment
warns that "path-filtering a would-be required check is how a docs PR
ends up blocked forever on a status that never reports." That is a real
hazard, but `main` currently has **no branch protection at all** —
`GET /repos/Castle-Turing/castle-turing/branches/main/protection`
returns 404, so there are no required status checks to strand.

## Scope

1. **`.github/workflows/check.yml`** — add `paths-ignore` to both the
   `pull_request` and `push` triggers:

   ```yaml
   paths-ignore:
     - "docs/**"
     - "*.md"
   ```

   `workflow_dispatch` is unaffected and stays the escape hatch for
   forcing a run by hand.

2. **Do NOT use `**/*.md`.** This is the trap, and it is specific to
   this repo. Two READMEs live *inside derivation sources*:

   - `agent/README.md` — `modules/agent` sets `src = ../../agent`
   - `modules/desktop/wallpapers/README.md` — `modules/desktop` sets
     `src = ./wallpapers`

   Editing either changes a store path. Demonstrated rather than
   assumed, by hashing the directory before and after a one-line edit:

   ```
   before: sha256-Dlu/MuV7gIcMw5f0o5kRrKtZL79umKwfhS2b0gEGbWc=
   after:  sha256-xQ/mv6NiZy0IdH1sIfsgNcXeHYWQHuDsHmO1HwdmaN8=
   ```

   `*.md` matches only top-level files (`README.md`, `CLAUDE.md`)
   because `*` does not cross `/`, so the two build-relevant READMEs
   still trigger the gate. `**/*.md` would skip the build for a change
   that alters the system, which is the one outcome this task must not
   produce.

3. **Correct the stale comment** in `claude-code-review.yml`. It
   currently argues against exactly this change using the "under a
   minute" figure. Replace that reasoning with what is now true: the
   gate *is* filtered, the filter is deliberately narrower than that
   workflow's own `**/*.md`, and the difference is the derivation-source
   READMEs. Leave `claude-code-review.yml`'s own `paths-ignore`
   unchanged — `**/*.md` is correct there, because skipping a *review*
   on a docs change is harmless in a way that skipping a *build* is not.
   Say that explicitly, so the asymmetry does not read like an
   oversight.

4. **Record the branch-protection dependency** in a comment next to the
   new `paths-ignore`. If `check` is ever made a required status, this
   filter turns docs PRs into permanently-pending PRs. The fix at that
   point is not to revert this — it is the always-report shim (keep the
   workflow triggering on everything, gate the *jobs* internally so the
   check still reports success). Naming the mitigation now saves the
   next person rediscovering it during an outage.

## Non-goals

- **Hardening the two expensive workflows' allowlists.** They watch
  `modules/**`, `hosts/**`, and `agent/**`, which do match prose files
  like `modules/README.md` and `hosts/xps9370/README.md`. So a docs-only
  PR touching *those* would still fire the VM jobs. That is real, but it
  is latent — it did not happen on #42 and has not happened yet. Doing
  it here would mean `!**/*.md` negations plus re-including the two
  derivation-input READMEs in each of four `paths:` lists, which is a
  lot of fiddly YAML for a hypothetical. File it if it bites.
- **Adding branch protection or required checks.** Orthogonal, and a
  repo-governance decision rather than a CI one.
- **A documentation standards check.** If one is ever added (a link
  checker, a formatter), it wants the *inverse* filter — `paths:` on
  `docs/**` — and would be its own workflow, not a job bolted onto this
  one. Noted because it is the obvious next thought, and because the
  filter added here is deliberately easy to invert.

## Verification

**Automated:** none is possible in the meaningful sense — a path filter
is evaluated by GitHub, not by anything runnable locally, so
`nix flake check` proves nothing about it.

**Needs a real PR, and this is the honest test:**

1. Confirm the YAML parses and the workflow is still recognised:
   `gh workflow list` should still show `check` after the change lands.
2. On the PR that carries this brief — which touches both
   `.github/workflows/**` and `docs/**` — `check` **must still run**.
   A mixed PR is not a docs-only PR, and `paths-ignore` only skips when
   *every* changed file matches. If `check` does not run on this PR, the
   filter is wrong.
3. After merge, the next prose-only PR should show `check` skipped
   while nothing else regresses. Confirm with `gh pr checks <N>` rather
   than by eye — the PR page renders a skipped required check and an
   absent one similarly enough to fool a glance.

Step 2 is the load-bearing one: it is the test that this change did not
accidentally disable the gate.
