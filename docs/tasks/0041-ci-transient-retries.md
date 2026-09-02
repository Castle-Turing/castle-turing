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

`vm-install-test.yml`'s "Run the install-loop harness" step and
`desktop-loop-test.yml`'s "Build and run the desktop-loop test" step
each wrap their real work in a two-attempt loop: run once, and only if
it fails AND the failure's log matches the script above, run exactly
once more. A second failure — matched or not — is surfaced as the
step's real exit code; nothing retries twice. These are the two jobs
the incident actually hit and the two slow enough (30–40 minute
budgets) that a wasted run is expensive; `check.yml`'s nix-using jobs
(`flake-check`, `sway-config-check`) touch the same cache and could in
principle hit the same signature, but they finish in under a minute,
so a human's own manual re-run costs little and extending the same
script to them is a mechanical follow-up, not something this brief
scopes in.

**A subtlety that cost real iteration:** GitHub's default shell for a
`run:` step with no `shell:` key is `bash -e {0}` — `-e` only, no
`pipefail` — confirmed empirically by a comment already in
`desktop-loop-test.yml` from an earlier incident. `-e` does not abort
on a command that is the test-part of an `if`/`while`/`until`, but it
does abort on a bare pipeline statement. A first draft of the retry
loop wrote the pipeline as a bare statement before checking
`${PIPESTATUS[0]}` on the next line, which meant the *first* transient
failure would `exit` the whole script (via `-e`) before the retry
logic on the next line ever ran — no error message, just the job going
red on attempt one, retry code dead on arrival. Both loops now put the
pipeline directly inside the `if` condition, which both keeps `-e`
from firing and (with `pipefail` set) makes the `if`'s own truthiness
reflect the real command's exit code rather than `tee`'s. Verified
locally with a mock command run under `bash -e` for all four
transitions (succeeds first try; fails once + matches + succeeds on
retry; fails twice + matches, still surfaces the real code; fails once
+ doesn't match, gives up immediately) — see the brief's Verification
section for what wasn't and couldn't be checked this way.

`desktop-loop-test.yml`'s step additionally groups the `nix build`
invocation in `{ ...; }` so `--print-out-paths`'s stdout still lands in
its own clean file untouched by the retry's pipe (the next step trusts
that file unconditionally — see its own comment, added after a real
incident where a masked build failure turned an empty out-path file
into `cp -r "$OUT"/.` copying the runner's entire filesystem). Only the
group's stderr — the `-L` log — flows through the pipe to `tee`, which
is what gets grepped for a signature match.

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

## Verification

Nix workflow YAML cannot be fully proven locally — this development
machine has no `nix` (see this repo's `CLAUDE.md`) and no `actionlint`
or `pyyaml` were available in this environment either. What was done
locally:

- Careful manual review of both edited workflow files for YAML
  structure (consistent indentation, no tabs, `run: |` blocks read
  correctly with `cat -A`).
- `bash -n` on `test/ci/known-transient-ci-failure.sh`, plus direct
  execution against a matching and a non-matching fixture log,
  confirming exit 0 / exit 1 respectively.
- The `-e`/`if`-condition control flow (the subtlety above) was proven
  against a mock command run under `bash -e {0}` — the exact shell
  invocation GitHub Actions uses — covering all four attempt/outcome
  combinations described above.
- The KVM audit above: read every job in every workflow file and
  traced which ones can reach `/dev/kvm`.

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
