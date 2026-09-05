Title: Task 0057 — the privileged switch cannot read the repository it rebuilds
Model: deep
Model-because: the file being edited is the one whose ExecStart line is
the resident's standing root grant, and the obvious fixes differ in how
much they widen it — one adds a scoped read permission, another reopens
a security decision 0048 §H settled deliberately. A standard-tier
implementer can make the error message go away; which way it goes away
is the deliverable, and choosing wrongly is invisible to every test.

# Task 0057 — the privileged switch cannot read the repository it rebuilds

**Before starting:** read `CLAUDE.md` and
`.claude/skills/implement-brief/SKILL.md`; both bind everything below.
Then `docs/tasks/done/0048-activation.md` — §H especially, which is the
authority record this task extends and must not widen — plus
`modules/agent/default.nix` around `systemd.services.castle-activate`,
and `docs/backlog/activation-is-not-proven-on-a-real-vm.md`, which
predicted this class of failure and which this task does **not** close.

## The finding

On 2026-09-05 the first real activation in this project's history
failed in under a second. The resident approved the activation
question; `castle-activate.service` started as root and ran its fixed
`ExecStart` — `nixos-rebuild switch --flake <repo.private>#<host>` —
which re-evaluates the resident's flake. Nix's git fetcher refused the
input:

    error: opening Git repository "/home/<resident>/<private-repo>":
    repository path '...' is not owned by current user (libgit2 error code = 7)

The unit exited 1, nothing was switched, and the seat recorded it
honestly: `outcome: failed`, `activation-outcome: switch-failed`, "It
is still running what it was running before." The recording half of
0048 worked. The switching half cannot read the repository it exists to
rebuild, because that repository belongs to the resident, the unit is
root, and git's ownership protection (the CVE-2022-24765 lineage,
enforced here by nix's libgit2 fetcher rather than by the git binary)
refuses that combination by default.

## §A. Why an interactive `sudo nixos-rebuild` succeeded the same day

The same command, against the same repository, on the same machine,
typed by hand under `sudo`, worked. A fix that does not explain that
discrepancy is a fix verified by coincidence, so here it is, read out
of the source this flake's `flake.lock` actually pins rather than
recalled.

`nixVersions.stable` in the pinned nixpkgs (rev
`0e251e24a4f24e036a084b6b4b2d2491af4167f4`) is nix **2.34.8**, and that
nix opens a local flake's repository with a plain
`git_repository_open` (`src/libfetchers/git-utils.cc:291`) and never
calls `git_libgit2_opts(GIT_OPT_SET_OWNER_VALIDATION, …)`. So libgit2's
ownership check runs. The pinned libgit2 is **1.9.4**, whose
`validate_ownership_path` (`src/libgit2/repository.c`) accepts a path
under any of three owner classes:

    GIT_FS_PATH_OWNER_CURRENT_USER | GIT_FS_PATH_USER_IS_ADMINISTRATOR |
    GIT_FS_PATH_OWNER_RUNNING_SUDO

The third is the whole discrepancy. `GIT_FS_PATH_OWNER_RUNNING_SUDO`
is satisfied when the effective uid is 0 **and** `$SUDO_UID` parses to
the uid that owns the path (`git_fs_path_owner_is` in
`src/util/fs_path.c`). `sudo` sets `SUDO_UID` to the resident's uid;
a systemd system unit has no `SUDO_UID` in its environment at all.
Interactive root is therefore not the same root as unit root, and the
difference is one environment variable that nothing in this repo sets
or should set.

That also disposes of the first tempting fix — setting
`Environment=SUDO_UID=<uid>` on the two units. It would work, and it
would be a lie about provenance that grants root the same trust over
*every* repository that uid owns, not over this one. Rejected in §D.

## §B. What to change, and why this spelling and no other

**Give root the scoped right to read exactly this repository**, using
git's own mechanism: one `safe.directory` entry naming
`castle.agent.repo.private`, declared in `modules/agent/default.nix`
beside the activation units so it is part of the same reviewable grant,
present only when `castle.agent.activation.enable` is on.

The brief this replaces asked for the spelling to be *verified* against
the deployed nix rather than assumed, because "a safe.directory nix
ignores reproduces this failure exactly". It was, and the verification
picks a winner:

- **`/etc/gitconfig` — works.** libgit2's
  `validate_ownership_config` calls `load_global_config`, which always
  includes the system config file; `git_config__find_system` resolves
  to `/etc` (`git_sysdir_guess_system_dirs` in
  `src/libgit2/sysdir.c` returns `"/etc"` on every non-Windows
  platform) plus `GIT_CONFIG_FILENAME_SYSTEM` = `gitconfig`. The
  pinned nixpkgs builds libgit2 with no `GIT_SYSDIR` override
  (`pkgs/by-name/li/libgit2/package.nix` sets only the regex, http,
  ssh and shared-lib flags), so the compiled-in path is the default.
  It is also read with no dependency on `$HOME`, which a system unit
  does not usefully have, and it is read by the `git` binary as well as
  by libgit2 — so the one file covers both, should nix ever shell out.

- **`GIT_CONFIG_*` environment on the units — does not work, silently.**
  libgit2 consults `GIT_CONFIG_SYSTEM`, `GIT_CONFIG_GLOBAL` and
  `GIT_CONFIG_NOSYSTEM` only when the repository was opened with
  `GIT_REPOSITORY_OPEN_FROM_ENV` (`config_path_system` /
  `config_path_global` are gated on `repo->use_env`), and nix's call
  site passes no flags at all. Worse, git's `GIT_CONFIG_COUNT` /
  `GIT_CONFIG_KEY_n` / `GIT_CONFIG_VALUE_n` protocol — the obvious way
  to scope a setting to two units — is a git-CLI feature that libgit2
  does not implement anywhere. Either spelling produces a grant that
  installs cleanly, reads correctly to a reviewer, and is invisible to
  the code it was written for. This is exactly the trap named in the
  task, and it is the reason the entry goes in a file rather than in a
  unit's environment.

**The exact value matters, and one detail of it is a trap of its own.**
`validate_ownership_cb` compares the configured value against the
repository's worktree path after appending a slash to it — and returns
without comparing anything if the value *already* ends in one:

    if (!data->tmp.size || data->tmp.ptr[data->tmp.size - 1] == '/')
            return 0;

So `safe.directory = "/home/r/private/"` is a grant that parses,
installs, and never matches. `castle.agent.repo.private` is a
free-text option, a resident can perfectly reasonably write a trailing
slash in it, and no test that only checks "the entry is present" would
catch it. This task therefore adds an eval-time assertion — activation
on, `repo.private` with a trailing slash, refuse — rather than letting
it surface on a live host as the identical failure this task is fixing.

Two further constraints on the value, stated because they are real and
neither is assertable at eval time in a pure evaluation:

- The path must be the git **worktree root**, not a subdirectory of the
  repository. libgit2 keys the allowlist on `repo->workdir`. In the
  layout this framework documents, `repo.private` *is* the repository
  root, so this holds by construction; a resident whose flake lives in
  a subdirectory of a larger repository needs the parent path here.
- libgit2 compares against the resolved worktree path, so a
  `repo.private` containing a symlinked component will not match the
  entry as written. Documented here rather than guarded, because
  detecting it requires reading the filesystem during evaluation.

**Mechanism: NixOS's `programs.git`, not a raw `environment.etc` write.**
`programs.git.config` (nixpkgs `nixos/modules/programs/git.nix`) renders
`/etc/gitconfig` via `lib.generators.toGitINI`, and its option type
merges across modules — a host that keeps its own system git config
gets the union rather than an evaluation conflict, which is what a raw
`environment.etc.gitconfig` definition in a framework module would
produce. The rendered line is `\tdirectory = "<path>"` under `[safe]`;
libgit2's parser dequotes it (`unescape_line` in
`src/libgit2/config_parse.c` drops quote characters) before the
comparison, so the quoting `toGitINI` adds is not a problem.

The cost, stated rather than buried: `programs.git.config` only takes
effect when `programs.git.enable` is true, so this module must set it,
and that puts `pkgs.git` in `environment.systemPackages` on any host
with activation enabled. Two things make that acceptable. It is not new
authority — `agent/castle` already calls `shutil.which("git")` in nine
places and cannot commit a pin bump, an applier change or a journal
record without it, so this makes an existing hard dependency explicit.
And the alternative — writing `/etc/gitconfig` directly, or setting
`programs.git.enable` with `lib.mkDefault` — either collides with a
host's own git config or lets a host silently switch the grant off,
and a grant that silently does not exist is the failure mode 0048's
polkit comment already warns about in the same module. A host that
explicitly sets `programs.git.enable = false` while enabling activation
gets a definition conflict at evaluation, which is loud and correct.

## §C. What this does *not* change, deliberately

**The no-arguments grant stands.** 0048 §H's reasoning is untouched:
the request channel is resident-writable, so the privileged units
accept nothing from it, and the whole grant is two fixed `ExecStart`
lines a resident can read. Nothing here hands the unit a path, a store
path, or an argument of any kind. What the resident gains is a third
readable line in their configuration — a `safe.directory` entry naming
one repository — and no new input to a root process.

**The `approved != running` drift note stands.** §H's recorded cost of
re-evaluation, and the seat's prose about it in `agent/castle`, are
unchanged and untouched by this task. The switch still re-evaluates;
this only lets it read what it is re-evaluating.

**The safe.directory entry grants root nothing it did not already
have.** Worth stating because "add root to safe.directory" reads like a
widening. What `safe.directory` suppresses is git's refusal to *trust
the contents* of a repository owned by somebody else — hooks, filters,
config in that repository — because that content can execute as the
reader. Here the reader is a unit whose entire purpose is to build and
activate that repository's configuration as root: the ExecStart line
already delegates far more to those bytes than any git hook could take.
The entry names exactly one path, so it says nothing about any other
repository the resident owns, which is precisely what the `SUDO_UID`
alternative could not manage.

## §D. Considered and rejected

- **`Environment=SUDO_UID=<uid>` on the two units.** Works, for the
  reason §A gives, and is wrong twice over: it claims a sudo session
  that does not exist, and its effect is "every repository owned by
  this uid" rather than "this repository". A scoped `safe.directory`
  entry is narrower and legible as what it is.
- **`safe.directory = *`.** libgit2 honours it
  (`validate_ownership_cb` returns safe for the literal `*`). It is the
  whole machine, for every path, forever, written in the module that
  every activation-enabled host imports. No.
- **Running the switch as the resident instead of as root.** Not
  available: `nixos-rebuild switch` needs root to set the system
  profile and run the activation script. This is the standing root
  grant 0048 recorded; it is not reopened here.
- **`GIT_CONFIG_*` on the units** — see §B. It is the design that looks
  most scoped and is in fact inert.
- **Handing the unit the store path the resident approved.** 0048 §H's
  load-bearing rejection, restated because this failure makes it
  tempting again: it would sidestep the fetch entirely. It also makes a
  resident-writable channel the security boundary. Out of scope for
  this task by construction — that decision belongs to the resident,
  not to a brief fixing a read permission.

## §E. `castle-rollback.service`: established, not assumed

The task asked whether the rollback unit is exposed to this failure
rather than treating it by symmetry. It is — by a path worth writing
down, and the answer changes nothing about the fix.

`castle-rollback.service` runs `nixos-rebuild switch --rollback` with
no `--flake`. In the pinned nixpkgs, `system.build.nixos-rebuild` is
the Python implementation (`nixos-rebuild-ng`; the bash one is gone and
`system.rebuild.enableNg` is a *removed* option). Its `execute()` calls
`services.reexec()` for any of switch/boot/test **before** the
`--rollback` branch is reached, and `reexec` calls
`Flake.from_arg(args.flake, …)`, which — given no `--flake` — falls
back to `/etc/nixos/flake.nix` if that path exists, resolving symlinks.
On the common deployment shape where `/etc/nixos` points into the
resident's private repository, the rollback unit therefore evaluates
that flake to build a possibly-newer `nixos-rebuild`, opens the same
git repository, and hits the identical ownership refusal.

Because the fix is a system-wide `/etc/gitconfig` entry rather than
per-unit environment, both units are covered by construction: there is
one grant, not two. That is another point in favour of the file over
the environment spelling — the environment spelling would have needed
the exposure question answered correctly to work at all.

One thing this investigation turned up that is **not** this task's to
fix: on a host where `/etc/nixos/flake.nix` does *not* exist, that same
`reexec` falls back to a classic `nix-build '<nixpkgs/nixos>'`, and
`run_wrapper` runs with `check=True`, so a failure there aborts the
process before `nix-env --rollback` is ever called — a rollback that
fails for a reason having nothing to do with rollback. The obvious
remedy is `--no-reexec` on the rollback unit's `ExecStart`, and that is
a change to the text of the standing grant a resident reads, on the
evidence of source reading rather than a reproduction. It goes to
`docs/backlog/rollback-may-die-before-it-rolls-back.md` for the
resident to decide, not into this diff.

## §F. Verification plan

**What CI proves, mechanically.** `nix flake check` already evaluates
`nixosConfigurations.example-activation`, which exists precisely so the
generated grant is *read* rather than trusted (its polkit assertion is
the precedent). Extend it:

- `programs.git.enable` is true, `/etc/gitconfig`'s rendered text
  carries a `[safe]` section, and it contains
  `directory = "<the configured repo path>"` exactly.
- There is exactly **one** `directory = "` entry in that file — the
  grant is scoped to one path, and an assertion that only checks
  presence would stay green if it ever grew a second.

And in `nixosConfigurations.example`, where activation is left at its
default, extend 0048's existing default-off assertion so the absence of
a `[safe]` section is proven the same way the absence of the units and
the polkit rule already is. A read permission that appears on hosts
that never asked to activate anything is the same defect class as a
unit that appears there.

The new eval-time assertion (trailing slash on `repo.private` while
activation is on) is proven by the module evaluating at all in the
normal case; nothing in this repo can hold a *negative* eval assertion
today, and inventing that harness for one string check is not this
task's job.

**What needs human hands, and cannot be faked.**
`test/agent-loop/activation.sh` stubs `nix`, `nixos-rebuild` and
`systemctl` and logs their argv, so it cannot see this defect class at
all — that is what
`docs/backlog/activation-is-not-proven-on-a-real-vm.md` is for, and
this task does not close that entry. Proof is one rebuild-and-switch on
the real machine followed by a re-run of the activation loop, which
landing this change provides for free: the deploy bumps the framework
pin, the pin trigger fires, and the next activation question is asked
and answered against a unit that can now read the repository. The thing
to look for in the record is `activation-outcome: switched` where
2026-09-05 recorded `switch-failed`.

## §G. File-by-file change list

- `modules/agent/default.nix` — a `programs.git` block under
  `lib.mkIf cfg.activation.enable`, sited immediately after the polkit
  grant so the three halves of the grant read together; one new
  assertion rejecting a trailing slash on `repo.private` when
  activation is enabled.
- `flake.nix` — the two assertions described in §F, in
  `nixosConfigurations.example-activation` and in the default-off
  assertion of `nixosConfigurations.example`.
- `docs/architecture.md` — the activation bullet names two units and a
  polkit rule as the whole grant. It gains the third component, in one
  sentence. 0048's own §H prose is left exactly as written; this brief
  is the amendment, which is the convention for a brief in
  `docs/tasks/done/`.
- `docs/backlog/rollback-may-die-before-it-rolls-back.md` — new, per
  §E.
- This brief.

## §H. Non-goals

Closing `activation-is-not-proven-on-a-real-vm.md`. Touching the
no-arguments grant, the drift note, or anything in `agent/castle`.
Adding `--no-reexec` to either unit. Widening `safe.directory` beyond
the one configured path, or making the entry unconditional on
`activation.enable`.
