# Task 0041 — CI retries its own recognizable flakes

PR #63's `desktop-loop-test` failed twice in one afternoon
(2026-09-01) with the code green both times; a human read the logs and
clicked re-run both times
(`docs/backlog/ci-flakes-deserve-retries-not-vigilance.md`, promoted
and deleted by this commit). One of those failures carried an
unambiguous signature: `determinate-nixd` returned `Login failure:
Transient authentication mechanism error` logging in to FlakeHub, and
the GitHub Actions cache backing `magic-nix-cache-action` then
rate-limited narinfo lookups into `HTTP error 418`s (run
`33508413473`, confirmed via `gh run view --log`). That is a class CI
can recognize and clear itself.

The backlog entry's second class — a runner without KVM slipping past
the workflow's own fail-fast and crawling under TCG emulation until
the time budget killed it — turned out, on inspection, to already be
closed. See "KVM audit" below.

## Fix: a bounded, signature-matched retry

`test/ci/known-transient-ci-failure.sh` is the one commented place
holding the signature list (per the backlog entry's own instruction to
keep it in one place, since GitHub Actions has no cross-file YAML
anchor — `vm-install-test.yml` already documents that limitation).
Given a log file, it exits 0 if the log matches a known-transient
signature and 1 otherwise. Signatures land here only once actually
observed and confirmed transient; a real regression that happens to
print a similar string must not get a free retry.

`test/ci/retry-on-known-transient.sh` is the loop itself, shared by
both jobs rather than duplicated inline in each workflow file (an
earlier draft inlined a near-identical ~12-line loop separately in
`vm-install-test.yml` and `desktop-loop-test.yml`; `/code-review`
caught the duplication — see "Judgment calls and course corrections"
below). `vm-install-test.yml`'s "Run the install-loop harness" step
and `desktop-loop-test.yml`'s "Build and run the desktop-loop test"
step now just call it: run once, and only if it fails AND the
failure's log matches the signature script above, run exactly once
more. A second failure — matched or not — is surfaced as the step's
real exit code; nothing retries twice. These are the two jobs the
incident actually hit and the two slow enough (30–40 minute budgets)
that a wasted run is expensive; `check.yml`'s nix-using jobs
(`flake-check`, `sway-config-check`) touch the same cache and could in
principle hit the same signature, but they finish in under a minute,
so a human's own manual re-run costs little, and pointing them at the
same shared script is a one-line mechanical follow-up, not something
this brief scopes in.

The script's `--stdout FILE` option covers `desktop-loop-test.yml`'s
special case: `nix build --print-out-paths` writes a store path to
stdout that the next step trusts unconditionally (see that step's own
comment, added after a real incident where a masked build failure
turned an empty out-path file into `cp -r "$OUT"/.` copying the
runner's entire filesystem). With `--stdout` given, only the command's
stderr — the `-L` log — is captured and grepped for a signature match;
stdout is redirected straight to the named file, untouched by the
retry's own bookkeeping. Verified locally end to end against a mock
command standing in for both `run.sh` and `nix build`: success on the
first try; fail + signature match + succeed on retry (including that
`--stdout`'s file ends up holding only the successful attempt's
output, not the failed attempt's); fail + match twice, still surfaces
the real exit code with no third attempt; fail with no signature
match, gives up immediately.

**A subtlety that cost real iteration:** GitHub's default shell for a
`run:` step with no `shell:` key is `bash -e {0}` — `-e` only, no
`pipefail` — confirmed empirically by a comment already in
`desktop-loop-test.yml` from an earlier incident. `-e` does not abort
on a command that is the test-part of an `if`/`while`/`until`, but it
does abort on a bare pipeline statement. A first draft of the retry
loop (before it was factored into the shared script) wrote the
pipeline as a bare statement before checking `${PIPESTATUS[0]}` on the
next line, which meant the *first* transient failure would `exit` the
whole script (via `-e`) before the retry logic on the next line ever
ran — no error message, just the job going red on attempt one, retry
code dead on arrival. The shared script's loop puts the pipeline
directly inside the `if` condition instead, which both keeps `-e` from
firing and (with `pipefail` set) makes the `if`'s own truthiness
reflect the real command's exit code rather than `tee`'s.

## KVM audit

The brief that produced this task expected to find at least one
KVM-dependent path still missing the fail-fast the backlog entry
describes losing 44 minutes to. Enumerating every job that could
plausibly touch `/dev/kvm`:

- `vm-install-test.yml` (`vm-install-test` job) — has an "Enable KVM
  access" step since the workflow's first commit (task 0004).
- `desktop-loop-test.yml` (`desktop-loop-test` job) — has the
  identical step since its first commit (task 0011); its own comment
  already says "Same fix, same reasoning as vm-install-test.yml."
- `check.yml`'s four jobs (`flake-check`, `agent-loop-test`,
  `dispatch-test`, `modal-headless-test`, `sway-config-check`) — none
  boots a VM. `flake-check` runs bare `nix flake check`, which only
  builds `checks.x86_64-linux.password-reminder-states`
  (`flake.nix:834`), and that check is deliberately pure shell over
  fixture files — the two VM tests are `packages.*` outputs precisely
  so `nix flake check` never builds them (see `flake.nix`'s own
  comment at that output). `sway-config-check` builds Nix-generated
  config files and runs `sway --validate` / `foot --check-config`
  under `xvfb-run`, no QEMU. `agent-loop-test`, `dispatch-test`, and
  `modal-headless-test` are plain bash/Python with no Nix VM involved.
- `claude.yml`, `claude-code-review.yml`, `claude-codex-followup.yml`
  — no Nix, no VM.

No path was found lacking the fail-fast. This audit is the actual
deliverable of that half of the task; it produced no code change
because there was nothing to fix. If a future job adds a new
nixosTest-based check or another QEMU-driven harness, it needs the
same "Enable KVM access" step — there is no shared mechanism enforcing
that today, which is a real gap, but a different one than this task
was asked to close (adding a repo-wide lint for "every QEMU-touching
job has a KVM check" is out of scope here; flagged for a future
backlog entry if it recurs).

## Non-goals

- No retry for `check.yml`'s fast jobs (see above).
- No change to how many times a job can be *manually* re-run — this
  bounds the *automatic* retry to one, per the backlog entry's own
  "never twice."
- No handling of failures that aren't in the signature list; those are
  triage, and per the backlog entry, triage needing judgment stays in
  the coding harness, not this repo.
- No `workflow_run`-triggered re-run job (the backlog entry's other
  suggested mechanism). A `workflow_run` workflow only ever executes
  the copy of itself committed on the repository's default branch, so
  it could not be exercised by a CI run on this PR's own branch before
  merge — the in-step retry chosen here can be, which matters given
  this repo's verification plan below.

## Judgment calls and course corrections

`/code-review` (scoped against `origin/main`, per this repo's
convention) ran on an earlier version of this branch where the retry
loop was written inline, separately, in each of the two workflow
files. It found two things, both fixed in this version:

1. The retry-notice line (`echo "$msg" | tee -a
   "$GITHUB_STEP_SUMMARY"`) was a bare pipeline, not the test-part of
   an `if`/`while`, so — under the same `-e`+`pipefail` combination
   this task's whole design has to work around — a failure to write
   `$GITHUB_STEP_SUMMARY` (disk pressure, a GH runner quirk, anything)
   would abort the step via `tee`'s own exit code instead of
   proceeding to the retry the task exists to guarantee. Fixed by
   switching to a plain `>>` redirect guarded by `[ -n
   "${GITHUB_STEP_SUMMARY:-}" ]` and `|| true`, in
   `test/ci/retry-on-known-transient.sh`.
2. The ~12-line loop was duplicated near-verbatim between the two
   workflow files, unlike the signature list, which already lived in
   one script. Fixed by factoring the loop itself into
   `test/ci/retry-on-known-transient.sh` and having both workflow
   steps call it (with a `--stdout FILE` option covering
   `desktop-loop-test.yml`'s need to keep the build's stdout clean of
   the retry's own capture/logging).

A second review pass (same command, after the fixes above) found a
third problem the first two fixes didn't touch: `run.sh`'s
`CASTLE_HARNESS_LOG_DIR` is a single fixed path CI reuses across a
retried invocation, and `mkdir -p` alone left a discarded attempt's
per-phase log files sitting in it alongside the differently-scoped
attempt that actually failed and got surfaced — the uploaded artifact
could then show, say, a `phase2d-*.od` file from the discarded attempt
next to `phase1-*` files from the real failure, implying the failing
run got further than it did. Fixed in `run.sh` itself: `rm -rf
"$LOG_DIR"` before the existing `mkdir -p`, so every invocation —
retried or not — starts from a clean directory. The same class of
problem exists for `desktop-loop-test.yml`'s `--keep-failed` build
directory (a discarded attempt's directory could survive to be
copied into the failure artifact alongside the real attempt's, by the
existing "Collect artifacts from a failed run" step's glob) — fixed
at the call site, since `nix build` has no equivalent "clear my own
scratch dir first" hook to edit: the command passed to
`retry-on-known-transient.sh` now runs `sudo rm -rf
/tmp/nix-build-*desktop-loop*` immediately before each attempt,
including the first (a no-op then).

`tools/codex-review.sh`'s cross-model pass (also scoped against
`origin/main`) ran after the fixes above and returned one finding,
reproduced here verbatim (raw output, `/tmp/codex-review-output.fcjXzn`
at review time) per this repo's convention — no PR exists yet for this
branch to comment on, since the harness opens it, so the disposition
below stands in for the usual separate PR comment:

> The retry mechanism appears functionally sound, but the harness now
> destructively removes an externally configured log directory,
> potentially deleting unrelated files.
>
> Review comment:
>
> - [P2] Avoid deleting the entire configured log directory —
>   /home/wesley/.local/share/emcee/runs/castle-turing/2026-09-02T18-18-51/wt-0041-ci-transient-retries-1/test/vm-install/run.sh:45-45
>   When `CASTLE_HARNESS_LOG_DIR` points to an existing directory that
>   contains anything besides this harness's artifacts, every
>   invocation now recursively deletes all of its contents. The
>   variable is documented merely as where logs are written, so local
>   callers can reasonably select a shared logging directory; clean
>   only the harness-owned files or use a per-attempt subdirectory
>   instead.

**Disposition: fixed, by documenting the contract rather than by
either alternative Codex offered.** A partial clean (deleting only
recognized filenames) is fragile in the wrong direction — the harness
writes over a dozen distinct log filenames today (`age-keygen.log`,
`phase1-nixos-anywhere.log`, `phase2c-secret-actual.od`, and more,
plus arbitrary `$phase.serial.log`/`$phase.qemu.log` pairs), and a
whitelist would silently stop cleaning up the moment a new one is
added, quietly reintroducing this exact staleness bug in a harder-to-
notice form. A per-attempt subdirectory is the more thorough fix but
touches every one of those log paths throughout `run.sh` for a risk
that, on inspection, is narrow: CI always sets
`CASTLE_HARNESS_LOG_DIR` to a path freshly created inside that run's
own checkout (`vm-install-test.yml`'s `env:`), never a directory that
predates or outlives the job, so the destructive-`rm` risk is entirely
a local-development concern — a developer setting this variable by
hand to a directory that also holds something else. `README.md` and
`run.sh`'s own comment now say plainly that this directory is fully
harness-owned and is wiped on every run, converting an undocumented
surprise into a stated contract, which is proportionate to a risk that
only exists at all when someone deliberately points this variable
somewhere `run.sh` doesn't fully control.

Codex's GitHub-integrated review (PR #73, review 5096277203, triggered
automatically on open) found three more things once the branch had a
PR to comment on. All three have a correct fix; only the first is
actually on this branch, for a reason worth recording rather than
working around: the session responding to this review authenticates
as a GitHub App installation with no `workflows` write permission, so
`git push` was rejected outright for the commit that touched
`.github/workflows/*.yml` — `refusing to allow a GitHub App to create
or update workflow ... without workflows permission`. That is GitHub's
own boundary on what an app credential can silently change about CI,
not a bug to route around, so findings 2 and 3 below are fixed as an
unstaged local diff and reproduced verbatim in the PR comment
responding to this review for a human (who pushes from their own,
differently-scoped credentials) to apply.

1. **Whole-log matching, not tied to what actually failed.**
   `known-transient-ci-failure.sh` grepped the *entire* captured log,
   but `vm-install-test.yml`'s own comment on `magic-nix-cache-action`
   documents ~140 tolerated "rate limit exceeded"/"throttled Magic Nix
   Cache" responses on a perfectly successful run — noise, not
   failure. If a later, unrelated part of the same run then failed for
   a real reason (a genuine regression), the stale noise earlier in
   the log would still match `HTTP error 418` or `GitHub Actions Cache
   throttled Magic Nix Cache`, so the whole run got misclassified as
   transient: the real regression's attempt-1 log gets discarded, and
   a nondeterministic regression could even pass on the free retry.
   Fixed by checking only the log's last 40 lines rather than the
   whole file — whatever actually failed reports its own error at or
   near the end (`run.sh`'s `fail()`, or nix's own error summary under
   `-L`), so a tail match ties the signature to the failure that
   happened instead of to anything earlier in a long log.
2. **Job timeout didn't budget for a second attempt.** Both
   `timeout-minutes` values were sized for exactly one run of the
   retried step; a matched failure late into a near-full-length first
   attempt could let the job's own timeout kill a legitimate,
   healthy second attempt before it finished, silently defeating the
   retry. Fix (unstaged, see above): bump `vm-install-test.yml` 30→55
   and `desktop-loop-test.yml` 40→75 — each roughly doubles the step
   budget the retried command now needs while adding the fixed,
   non-retried overhead (checkout, `nix-installer`, KVM setup) only
   once.
3. **`test/ci/**` wasn't in either workflow's path filters.** A change
   to only `retry-on-known-transient.sh` or
   `known-transient-ci-failure.sh` wouldn't trigger either of their
   two consumers, so a broken retry-loop change could merge unexercised
   by the one thing that runs it end to end. Fix (unstaged, see above):
   add `test/ci/**` to both workflows' `pull_request` and `push` path
   lists.

## Verification

Nix workflow YAML cannot be fully proven locally — this development
machine has no `nix` (see this repo's `CLAUDE.md`) and no `actionlint`
or `pyyaml` were available in this environment either. What was done
locally:

- Careful manual review of both edited workflow files for YAML
  structure (consistent indentation, no tabs, `run: |` blocks read
  correctly with `cat -A`).
- `bash -n` on both `test/ci/known-transient-ci-failure.sh` and
  `test/ci/retry-on-known-transient.sh`.
- `known-transient-ci-failure.sh` run directly against a matching and
  a non-matching fixture log, confirming exit 0 / exit 1 respectively.
- `retry-on-known-transient.sh` run end to end under `bash -e {0}` —
  the exact shell invocation GitHub Actions uses for a `run:` step —
  against a mock command covering all four attempt/outcome
  combinations described above, in both its plain and `--stdout` modes
  (the latter confirmed to leave the out-path file holding only the
  successful attempt's output, not a failed attempt's).
- The KVM audit above: read every job in every workflow file and
  traced which ones can reach `/dev/kvm`.
- `/code-review` against `origin/main`, findings addressed above.
- `tools/codex-review.sh` (cross-model pass), finding and disposition
  above.
- Codex's GitHub-integrated review on PR #73, three findings with a
  correct fix identified for each (tail-restricted signature matching,
  doubled `timeout-minutes` budgets, `test/ci/**` path filters), but
  only the first landed on this branch — the other two are blocked on
  a human pushing the workflow-file diff by hand, per the `workflows`
  permission gap recorded above. This session's sandbox also refused
  to execute any script (`bash -n`, running the script directly, even
  `tail`/`printf` to a scratch file all required an approval this
  headless review-response flow had no human available to grant), so
  the tail-matching change was verified by careful manual reading only
  — `tail -n "$tail_lines" "$log_file" | grep -qF "$pattern"` is a
  small, standard pipeline with no new edge case beyond what the
  earlier whole-file `grep -qF` already had. A future session with
  script execution available should still run the fixture tests the
  original implementation describes above, against the tail-restricted
  version.

What only a real CI run on this PR proves, and what a reviewer should
look for:

- That `vm-install-test` and `desktop-loop-test` still pass end to end
  with the retry wrapper in place (the common case: attempt 1 succeeds,
  the loop exits 0 immediately, behavior unchanged from before this
  task).
- That a *real* non-transient failure (a genuine test regression) still
  goes red on the first attempt with no retry and no delay — this
  needs either a deliberately broken throwaway commit or waiting for a
  real regression to land; not forced in this PR.
- The actual transient-retry path (attempt 1 hits a real FlakeHub/cache
  outage, attempt 2 clears it) cannot be manufactured on demand — it
  depends on GitHub's infrastructure being flaky at the moment the job
  runs. The evidence to look for, if it happens: a run whose log shows
  the "retrying once" message from `$GITHUB_STEP_SUMMARY` followed by a
  green job, instead of a human re-clicking "Re-run failed jobs."
