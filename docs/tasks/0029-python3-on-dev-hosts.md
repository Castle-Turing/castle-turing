# Task 0029 — Add python3 to the dev host

**Goal.** The agent-loop test harnesses run `agent/castle` (a `#!/usr/bin/env python3` script) directly from the checkout. On a Castle Turing dev host, python3 is not on `$PATH`, so they fail immediately with `env: python3: No such file or directory`. Add python3 to `modules/dev` so the harnesses work out of the box.

## The problem, with scope

`test/agent-loop/` contains five bash harnesses that invoke `CASTLE="$REPO_ROOT/agent/castle"` directly, resolving the shebang against `$PATH`. NixOS puts nothing on `$PATH` implicitly — the system contains exactly what its configuration lists. This gap bit twice in a single session (2026-08-19): one `/code-review` agent running the harnesses to verify its own findings, and the orchestrating session running them to verify an implementer's report. Both worked out `nix shell nixpkgs#python3` as a workaround. That tax falls on every future verification step as well as implementation until it is fixed.

The deployed system is not affected: `modules/agent/default.nix` wraps the CLI with `makeWrapper ${pkgs.python3}/bin/python3`, so `castle` as a *product* carries its own interpreter. The gap is only in the *development* path — running harnesses from a checkout. CI is unaffected: `ubuntu-latest` ships python3, and the agent-loop job deliberately skips Nix because the harnesses are plain bash and stdlib Python.

Scope is verified: the harnesses also use grep, sed, find, diff, timeout, flock, setsid, script, xargs, wc, tr, head, tail, sort and mktemp — all in NixOS's base system path. Only python3 fails; supplying it alone made all five harnesses pass.

## The fix

Add `python3` to `environment.systemPackages` in `modules/dev/default.nix`. One line.

`modules/dev` is the right home: its header comment states "the tools this project's own development happens with"; it already ships emacs, git, gh, ripgrep, fd, claude-code — same class of tool. `docs/tasks/0005-dogfooding-desktop.md` committed to the project hosting its own development. The module is optional (a private layer composes it in), so this affects only machines that opt into developing Castle Turing.

`modules/dev` and `modules/agent` both draw `pkgs.python3` from the same flake pin, so the interpreter on `$PATH` and the one `castle` is wrapped with are the same build. No ambiguity.

## Two alternatives, both rejected

1. **A flake `devShell`**: provides tools in `nix develop` only. Rejected: a devShell only helps someone who knows it exists. The failure this task fixes was two agents not knowing — they ran the harnesses directly, as anyone would. Putting the tool on the machine fixes it whether or not anyone knows to look.

2. **`modules/base`**: would put python3 on every Castle Turing machine. Rejected: that is a framework-wide decision about all residents rather than about machines that develop the framework. `docs/backlog/base-assumes-a-real-host.md` already records base over-reaching as a known problem.

## Changes

- **`modules/dev/default.nix`**: add `python3` to `environment.systemPackages`.
- **`agent/README.md`** Testing section: add a line saying the harnesses need `python3` on `$PATH`, that `modules/dev` provides it, and what to do without it (`nix shell nixpkgs#python3 --command ...`).

## Verification

- `nix flake check` must pass. The CI stand-in host includes the dev module, exercising the change.
- Confirm python3 appears in the built system path for a host importing `modules/dev`. Build the CI stand-in's `system.path` and grep for a python3 binary.
- Nothing here needs human hands.

## Implementation

Make two changes:

1. **`modules/dev/default.nix`**: add `python3` to the `environment.systemPackages` list. The list is `emacs, git, gh, ripgrep, fd, claude-code` — grouped by kind rather than alphabetized, so append `python3` at the end rather than sorting it in. Do not reorder the existing entries.

2. **`agent/README.md`** Testing section: add guidance after the harness list (five harnesses since 0023 added `resume.sh`). Say that the harnesses need `python3` on `$PATH`, that `modules/dev` provides it for dev hosts, and that without it you can use `nix shell nixpkgs#python3 --command bash test/agent-loop/run.sh` (or the other harness name).

Both changes are one-line edits. This brief rides the implementing branch; commit it with the code changes in a single commit. Before opening a PR, run `nix flake check` to confirm the flake still evaluates, and run `/code-review` on the branch to check for any issues. Do not edit `CLAUDE.md`, `docs/principles/`, or any other file. Do not write personal data anywhere. When done, report the commit hash and a `git diff origin/main..HEAD --stat` summary.

## Numbering note

This brief is numbered 0029 although 0024–0028 do not exist yet. Numbers in `docs/tasks/` are sequential and mean something: *the order work was committed to* (`docs/backlog/README.md`). Commitment order, not completion order. CLAUDE.md adds the allocation side: numbers are allocated before delegation, so parallel writers compute the same "next" number. 0024–0028 were allocated on 2026-08-17 to a planned sequence of tasks that has not been implemented yet. Renumbering them was considered and rejected: their allocation lives in a pre-registered planning record, and rewriting a pre-registration to tidy a numbering gap is a bad trade. Consequence: the next free number after this task is 0030, not 0024.

## Hard constraints

- No personal data (CLAUDE.md).
- No hardware assumptions in `modules/`.
- Principle 01: this is public mechanism with no configuration knob.
