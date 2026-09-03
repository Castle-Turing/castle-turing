# Task 0032 — The admin password hash: out of the store, into sops

**Before starting:** read `CLAUDE.md` in full; `docs/tasks/0031-secrets-tooling.md`
in full, especially its "Non-goals" entry on the password hash (it names
this task as its successor and gives the three reasons it was deferred —
cited, not re-derived, below) and its "Verified against nixos-anywhere"
/ "Enrollment" sections, whose facts about `--extra-files` and the age
key this task depends on without re-proving; `docs/private-layer.md` in
full, not only the "Secrets" section — the surrounding sections' tone
and cross-references need matching, the same discipline
`docs/tasks/0030-state-outside-the-flake.md` and `0031` asked of
themselves; `modules/base/default.nix`'s `castle.admin.initialHashedPassword`
option (lines 36–64), its `users.users.${cfg.username}.initialHashedPassword`
consumer (line 170), and the password-reminder systemd service, path
unit, and shell banner (lines 196–240); `modules/desktop/default.nix`'s
assertion on `castle.admin.initialHashedPassword` (~lines 349–358);
`modules/agent/default.nix`'s `mkRenamedOptionModule` precedent (~lines
75–79) and its unrelated comment naming `castle-password-reminder-check`
as a design analogy (~line 486); `flake.nix`'s `nixosConfigurations.example`
admin block (~lines 178–184); `docs/backlog/initial-password-is-seed-only.md`
in full; `docs/backlog/disk-encryption.md` in full; `docs/principles/01-open-by-construction.md`
and `02-the-resident-owns-the-configuration.md`; `hosts/xps9370/README.md`'s
install command and its "no password on the admin account" prose (its
step 6, near the end of the file); and `test/vm-install/README.md`,
`run.sh`, `vm-test-system.nix` in full — this is the harness that
proves an unattended install and is where this task's central claim
gets tested against a real machine, not just read.

Work on branch `task/0032-password-hash`, cut from `origin/main` at
`f7ebd32`. Scope every diff and review against `origin/main` (`git
fetch` first, per `CLAUDE.md`'s multi-agent conventions).

**Goal.** Stop putting the admin account's password hash in the
world-readable Nix store. Move `castle.admin`'s password mechanism from
`initialHashedPassword` (a hash string, embedded in the store by two
separate routes) to `hashedPasswordFile` (a runtime file path, read at
activation, never embedded anywhere this repo's evaluation touches),
sourced from an sops-nix secret with `neededForUsers = true`. Remove the
old option outright rather than rename it. Fix the password-reminder
machinery to read its seed from that same runtime file instead of a
string frozen into the store — the second of the two exposure routes
this task closes — rather than deleting a feature that turns out to
still be correct once the mechanism it depends on is understood
properly (see "What `hashedPasswordFile`'s semantics actually are" and
§4). Prove the whole thing against a real installed machine in
`test/vm-install/`, because this is the highest-risk task in the repo:
get it wrong and the failure mode is a machine nobody can log into.

## Why

`docs/tasks/0031-secrets-tooling.md`'s own Non-goals section named this
task and gave three reasons it was deferred rather than folded into
that one, and this brief does not re-derive them, only restates them:
the hash is needed at **account creation**, on first boot, where a
wrong or absent value fails on the login path itself rather than on
something as recoverable as a network join; migrating it changes its
**source**, and (0031 believed) its **semantics**; and it already
reaches the store by **two independent routes**, not one — `users.users.${cfg.username}.initialHashedPassword`
(`modules/base/default.nix` line 170), and the password-reminder
service's `script`, which embeds the same value via `lib.escapeShellArg
cfg.initialHashedPassword` (lines 208–224). Fixing the first route and
leaving the second would still publish the hash; a real fix has to find
both, and this task does.

One correction to that inherited framing, load-bearing enough that it
changes how several sections below are written, is recorded in full in
"What `hashedPasswordFile`'s semantics actually are" — read it before
the design below, because it is not the semantics 0031 assumed and not
what a first reading of nixpkgs's own option summaries suggests either.

## The decision

**There is no seed-only-from-a-file option.** Verified against this
flake's pinned nixpkgs (`0e251e24a4f24e036a084b6b4b2d2491af4167f4`,
`nixos/modules/config/users-groups.nix`): the five password options are
`initialHashedPassword`, `initialPassword`, `hashedPassword`,
`password`, and `hashedPasswordFile` — there is no
`initialHashedPasswordFile`. `hashedPasswordFile`'s own description
says "The password file is read on each system activation," while
`initialHashedPassword`'s says it is "the hashed password assigned if
the user does not already exist… the password can be changed
subsequently using the `passwd` command."

**The chosen design: move to `hashedPasswordFile`.** The encrypted
secret becomes the source the account is seeded from — the same seed
concept the framework already had, now sourced from a file decrypted at
runtime instead of a string frozen into the store at eval time. Two
alternatives were considered and declined, recorded here with their
reasoning because both are real designs, not straw men:

- **Keep the seed, accept the hash in the store.** No behavior change,
  and the honest outcome if the store-exposure risk were judged
  tolerable. Rejected because it means this task does nothing it set
  out to do — the two routes 0031 named stay exactly as exposed as they
  are today.
- **A bespoke first-boot-only seeding step**, reading the secret once
  during account creation and never again, built to preserve exactly
  today's `passwd`-survives semantics without going through
  `hashedPasswordFile` at all. Rejected: this would be original code in
  the authentication path, which is the worst place in this system to
  be original. `hashedPasswordFile` is upstream, maintained, and used
  by every other project that puts a password behind sops; a
  hand-rolled equivalent buys nothing this task needs and adds a
  surface nobody but this project has ever hardened.

`hashedPasswordFile`, wired the way the rest of this brief specifies, is
the chosen mechanism. That part is not reopened by anything below.

### What `hashedPasswordFile`'s semantics actually are, verified directly against source

This is the correction referenced above. Read the whole subsection
before "The lockout story" and "mutableUsers" further down — those
sections are written to match what is here, not to what a first reading
of the option descriptions alone would suggest.

`hashedPasswordFile`'s own one-line description ("read on each system
activation") is true, and easy to misread as "always re-applied, unlike
the seed-only options." It is not that, and nixpkgs says so directly
one paragraph later in the same file — `passwordDescription`, shared by
all five password options:

> If the option `users.mutableUsers` is true, the password defined in
> one of the above password options will only be set when the user is
> created for the first time. After that, you are free to change the
> password with the ordinary user management commands. If
> `users.mutableUsers` is false, you cannot change user passwords, they
> will always be set according to the password options.

`users.mutableUsers` defaults to `true` (`nixos/modules/config/users-groups.nix`'s
own `mkOption`), and this project has never set it anywhere — verified
by grepping every `.nix` file in this repo for `mutableUsers` at spec
time: zero hits. So the default applies, and the paragraph above applies
to `hashedPasswordFile` exactly as it applies to `initialHashedPassword`
today.

Traced through the actual activation mechanism
(`nixos/modules/config/update-users-groups.pl`, the script
`system.activationScripts.users` runs), not just the doc prose:

- The file **is** read every activation, unconditionally, into
  `$u->{hashedPassword}` (lines 241–247 at the pinned rev — the "read on
  each activation" part is real).
- Writing that value into `/etc/shadow` is not unconditional. For an
  account **already present** in `/etc/shadow` (i.e., every rebuild
  after the first that created it), the write is gated:
  ```perl
  $sp_pwdp = "!" if !$spec->{mutableUsers};
  $sp_pwdp = $u->{hashedPassword} if defined $u->{hashedPassword} && !$spec->{mutableUsers}; # FIXME
  ```
  Both lines fire only when `mutableUsers` is **false**. With it at its
  (unset, default) `true`, neither fires, and the existing shadow entry
  — whatever it currently is, including whatever a resident set with
  `passwd` — is carried forward untouched. The freshly-read file's
  value is computed and then never used for that account.
- For an account being **created for the first time** (not yet in
  `/etc/shadow`), the gate does not exist — the freshly-read value (or
  `"!"` if the file was unreadable) is written unconditionally:
  ```perl
  my $hashedPassword = "!";
  $hashedPassword = $u->{hashedPassword} if defined $u->{hashedPassword};
  ```

The consequence, stated plainly because it changes what this task
actually achieves: **with `users.mutableUsers` left at this project's
current default, `hashedPasswordFile` behaves exactly like
`initialHashedPassword` in every way that matters to a resident** —
applied once, at account creation, and never again. A `passwd` change
survives forever; editing the secret and rebuilding does nothing to an
account that already exists. This is not a new fact this task
introduces — it is the same fact `docs/backlog/initial-password-is-seed-only.md`
already documents for `initialHashedPassword`, now shown to apply
verbatim to its replacement. See the "mutableUsers" section of the
design below for what this changes about this task's scope, and the
note at the end of this brief's originating report for the judgment
call this correction produced.

What **is** achieved, unconditionally, regardless of `mutableUsers`:
the hash stops being a string this repository's evaluation ever touches
or copies into the store, by either of the two routes 0031 named. That
is the actual, load-bearing fix this task ships. "The encrypted file
becomes the source of truth on every rebuild" is not — see above — and
this brief does not claim it is anywhere below.

## The design

### 1. The option: `castle.admin.hashedPasswordFile`

New option on `castle.admin`, in `modules/base/default.nix`, replacing
`initialHashedPassword`:

```nix
hashedPasswordFile = lib.mkOption {
  type = lib.types.nullOr lib.types.str;
  default = null;
  description = ''
    Path, on THIS machine, to a file holding the admin account's
    hashed password (`mkpasswd -m sha-512` generates the hash; the
    file holds exactly that one line). Wired to
    `users.users.<name>.hashedPasswordFile`, which NixOS reads at
    every activation — verified against this flake's pinned nixpkgs,
    `nixos/modules/config/users-groups.nix` and
    `update-users-groups.pl`.

    A Nix *string*, not a path, deliberately — the same reasoning
    `castle.secrets.ageKeyFile` uses (modules/secrets.nix): this
    names a location on the target's own disk, resolved at runtime,
    never a file this repo's own evaluation should read, copy into
    the store, or even require to exist. The documented pattern
    points this at an sops-nix secret's own `.path` — see
    docs/private-layer.md's "Secrets" section.

    Optional at this layer for the same reason the option it replaces
    was: a host with no interactive console (a headless server with
    SSH-key-only admin) has no use for one. A host with a login
    prompt does — see modules/desktop, which asserts this is set.

    (As shipped, this parenthetical no longer cites the vm-test
    harness as an example of a host with no use for one: since the
    §-Verification-plan phase-2d assertion, that harness sets this
    option with a real fixture secret behind it, and citing it here
    would have been immediately falsified by the same PR.)

    **Read this before setting it.** Because this project leaves
    `users.mutableUsers` at its NixOS default (`true`), this option —
    like the one it replaces — only takes effect the moment the
    account is *first created*. Editing the file (or the secret behind
    it) and rebuilding does **not** change an already-existing
    account's password; a resident who wants their live password to
    track this file has to run `passwd` by hand, exactly as before.
    See docs/tasks/0032-password-hash.md's "mutableUsers" and "The
    lockout story" sections for the full reasoning and the recovery
    path if a wrong or missing secret locks a fresh account out of
    password login.
  '';
};
```

Consumer, replacing the `initialHashedPassword = cfg.initialHashedPassword;`
line at `modules/base/default.nix` line 170:

```nix
users.users.${cfg.username} = {
  isNormalUser = true;
  extraGroups = [ "wheel" "networkmanager" ];
  openssh.authorizedKeys.keys = cfg.sshKeys;
  hashedPasswordFile = cfg.hashedPasswordFile;
};
```

**`modules/desktop/default.nix`'s assertion must change with it**
(~lines 349–358 at the pinned rev) — it currently asserts
`config.castle.admin.initialHashedPassword != null`, and left alone
that assertion would either never fire (if a private layer sets nothing
at all, `nix flake check` still passes some other way) or fire wrongly
against an option that no longer exists. Update it in place:

```nix
{
  assertion = config.castle.admin.hashedPasswordFile != null;
  message = ''
    modules/desktop requires castle.admin.hashedPasswordFile to be
    set: this module deliberately configures no auto-login (see the
    module's header comment), so a login prompt with no password
    behind it is the exact console lockout
    docs/tasks/0003-findings.md finding #1 describes. Point it at a
    decrypted secret's runtime path — see docs/private-layer.md's
    "Secrets" section and docs/tasks/0032-password-hash.md. This is a
    *file path*, read at activation, never the hash itself.
  '';
}
```

### 2. Removing `initialHashedPassword`: `mkRemovedOptionModule`, not a rename

`modules/agent/default.nix` already has a rename precedent
(`mkRenamedOptionModule [ "castle" "agent" "worker" "repoRoot" ] [ "castle"
"agent" "repo" "private" ]`, ~line 75) for exactly this situation on its
face — an old option name replaced by a new one, a private layer
somewhere still using the old spelling. A reader who has seen that
precedent will reasonably expect the same tool here. It is wrong here,
for a sharper reason than "the behavior changed" — a straight rename
cannot even preserve the *shape* of the value:

`mkRenamedOptionModule` copies whatever value the old option held onto
the new option name, unmodified. `initialHashedPassword`'s value is a
**hash string** (`$6$...`). `hashedPasswordFile` expects a **file
path**. A rename would take a private layer's existing
`castle.admin.initialHashedPassword = "$6$abc...";`, leave it
untouched, and reassign it as `castle.admin.hashedPasswordFile =
"$6$abc...";` — NixOS would then try to open a file literally named
`$6$abc...` (relative to `/`, where activation scripts run), fail to
find it, and — per "What `hashedPasswordFile`'s semantics actually
are" above — treat that exactly like any other missing-file case: a
warning at activation, and (only for an account being created fresh)
a locked (`"!"`) shadow entry instead of the resident's intended
password. A resident who trusted the rename to "just work" gets a
silently different, silently worse outcome the next time they wipe the
machine, discovered only when they try to log in and cannot.

`mkRemovedOptionModule`, in `modules/base/default.nix`:

```nix
imports = [
  (lib.mkRemovedOptionModule [ "castle" "admin" "initialHashedPassword" ] ''
    Replaced by castle.admin.hashedPasswordFile
    (docs/tasks/0032-password-hash.md). This is not a rename: the old
    option took a hash STRING; the new one takes a FILE PATH, read at
    every activation (wired to NixOS's own
    users.users.<name>.hashedPasswordFile). Pasting your old hash
    string in verbatim will not work — NixOS will try to open a file
    literally named by that string, fail to find it, and (per
    update-users-groups.pl) leave the account locked ("!") the next
    time it is created fresh, rather than seeded with what you meant.

    Point the new option at a *path* instead: the documented pattern
    is an sops-nix secret's own `.path`, with `neededForUsers = true`
    so it decrypts before accounts are created. See
    docs/private-layer.md's "Secrets" section and
    docs/tasks/0032-password-hash.md's migration steps before you
    touch this on a machine you don't want to break.
  '')
];
```

A resident who has not yet migrated gets a build-time failure naming
the exact fix, in the exact place they would look — not a machine that
builds fine and locks itself on the next wipe.

### 3. The secret: `neededForUsers` and `/run/secrets-for-users`

sops-nix's own description for `sops.secrets.<name>.neededForUsers`:
"causes the secret to be decrypted before users and groups are
created. This can be used to retrieve user's passwords from sops-nix.
Setting this option moves the secret to `/run/secrets-for-users` and
disallows setting owner and group to anything else than root."

Verified directly against the pinned rev
(`a8627b21b9107c5711c96b84f32a9a4b3d45295f`), not trusted from the
description alone — this project's own default runs
`system.activationScripts.setupSecretsForUsers`, not the systemd-unit
variant (`systemd.sysusers.enable` and `services.userborn.enable` are
both unset here, verified by grep), and that activation script:

```nix
system.activationScripts.setupSecretsForUsers =
  lib.stringAfter ([ "specialfs" ] ++ ...) "...sops-install-secrets ...";
users.deps = [ "setupSecretsForUsers" ];
```

`users.deps = [ "setupSecretsForUsers" ]` is the load-bearing line: it
makes the standard `users` activation script (the one that runs
`update-users-groups.pl`, per §1) depend on `setupSecretsForUsers`
having already run — so a `neededForUsers` secret is guaranteed
decrypted (or to have visibly failed trying) before account creation
happens, on every boot including the very first. The path itself:

```nix
path = if config.neededForUsers then
  "/run/secrets-for-users/${config.name}"
else
  "/run/secrets/${config.name}";
```

`neededForUsers`'s own assertion in the same file requires the secret
be root-owned (`owner`/`group` may not be set to anything but root) —
sops-nix's own defaults (owner unset, mode `0400`) already satisfy
this; no override is needed or allowed.

The worked example, for `docs/private-layer.md`'s "Secrets" section,
mirroring the existing `wifi-psk` example's shape and voice:

```nix
{ config, ... }:
{
  castle.secrets.sopsFile = ./secrets.yaml;

  # neededForUsers decrypts this *before* users.users.<name> is
  # created — the ordering the admin password specifically needs,
  # since an ordinary sops.secrets entry (no neededForUsers) decrypts
  # *after* accounts already exist, too late to seed one.
  sops.secrets."admin-password-hash".neededForUsers = true;

  # /run/secrets-for-users/admin-password-hash at activation — a
  # different runtime directory than every other secret in this file,
  # because neededForUsers moves it there. See
  # docs/tasks/0032-password-hash.md if that path surprises you.
  castle.admin.hashedPasswordFile =
    config.sops.secrets."admin-password-hash".path;
}
```

`mkpasswd -m sha-512` still generates the value that goes *into*
`secrets.yaml` under that key — nothing about how the hash itself is
produced changes; only where it lives before it reaches the machine.

### 4. The password-reminder machinery: kept, and fixed to close its own exposure route

An earlier draft of this brief instructed deleting
`castle-password-reminder-check` (the systemd service, its path unit,
the `interactiveShellInit` banner, and the marker file at
`/var/lib/castle-turing/password-changed`, lines 196–240 at the pinned
rev), on the reasoning that "the shadow hash always equals the file's
hash after activation, so the check never fires, and 'run `passwd` to
set your own' is no longer true." "What `hashedPasswordFile`'s
semantics actually are" above shows that reasoning is false: for an
already-existing account, the shadow hash is left alone regardless of
what the file currently says, so it can still legitimately diverge from
it exactly the way it diverges from `initialHashedPassword` today
(`docs/backlog/initial-password-is-seed-only.md`'s whole subject). Both
halves of the original argument fail together — the check still tells
a resident something true (have they moved off the seeded password?),
and "run `passwd`" is still exactly the right advice, for the same
reason it always was: `mutableUsers = true` is what makes `passwd`
durable in the first place.

**So the machinery is kept**, and what changes is narrower: how the
check script gets its seed value. Today it embeds
`cfg.initialHashedPassword` — the hash itself — directly into the
generated script via `lib.escapeShellArg` (line ~218), which is exactly
the *second* store-exposure route named in "Why." That route has to
close the same way the first one does, not survive this task untouched.
The fix reads the seed from `cfg.hashedPasswordFile` **at check time**,
the identical runtime path NixOS's own activation already reads,
instead of freezing the file's *contents* into the store at build time.
Embedding the *path itself* in the generated script is not a
regression — it is exactly the same shape of thing
`castle.secrets.ageKeyFile`'s own path is, harmless because only a
*location* is disclosed; the file's contents, which are the actual
secret, are dereferenced only at runtime, by a script running as root,
never by the Nix evaluator.

**Ordering, verified rather than assumed.** The check needs the secret
already decrypted (or to have definitively failed to decrypt) by the
time it runs, on every boot, with no race. Traced through this
project's own boot path, not general NixOS folklore:
`nixos/modules/system/boot/stage-2-init.sh` (pinned rev) runs
`$systemConfig/activate` — the same activation script that runs §3's
`setupSecretsForUsers` and then `users` — and only *after* it returns
does it `exec @systemdExecutable@ "$@"` to start systemd at all. That
sequencing applies whenever `IN_NIXOS_SYSTEMD_STAGE1` is not set, i.e.
whenever `boot.initrd.systemd.enable` is unset — verified by grepping
every `.nix` file in `modules/` and `hosts/` at spec time: nothing in
this project sets it. So on every boot this project produces, **all**
activation completes strictly before systemd itself starts, which means
strictly before `multi-user.target` is ever reached. `castle-password-reminder-check`'s
`wantedBy = [ "multi-user.target" ]` is therefore guaranteed — not
merely likely — to run after the secret has resolved one way or the
other. (A `nixos-rebuild switch`, as opposed to a fresh boot, runs
activation directly and re-triggers the check via the existing
path-unit-on-`/etc/shadow`-change design, unchanged by this task.)

**What happens on the boot where it does not resolve** (a missing or
wrong key, per §5): `cfg.hashedPasswordFile` will not exist or will not
be readable at check time. The script must not crash or, worse,
misreport. It doesn't: an unreadable seed file makes the check exit
without touching the marker, leaving the banner in whatever state it
already had — nagging, since the marker starts absent — rather than
guessing. This is the same "never lock anyone out, worst case nag
forever" posture the surrounding code already committed to; the fix
only extends it to a new way the seed can be temporarily or permanently
unreadable.

```nix
systemd.services.castle-password-reminder-check = lib.mkIf (cfg.hashedPasswordFile != null) {
  description = "Note whether the admin account still has its seeded initial password";
  wantedBy = [ "multi-user.target" ];
  serviceConfig.Type = "oneshot";
  script = ''
    marker=/var/lib/castle-turing/password-changed
    mkdir -p "$(dirname "$marker")"
    seed_file=${lib.escapeShellArg cfg.hashedPasswordFile}
    if [ ! -r "$seed_file" ]; then
      # The seed hasn't decrypted -- yet, or ever, per this task's
      # missing/wrong-key case (docs/tasks/0032-password-hash.md,
      # "The lockout story"). Say nothing rather than guess: leave the
      # marker exactly as it was, so the banner keeps whatever state it
      # last had.
      exit 0
    fi
    seed="$(${pkgs.coreutils}/bin/cat "$seed_file")"
    current="$(${pkgs.gnugrep}/bin/grep -m1 -E ${
      lib.escapeShellArg ("^" + cfg.username + ":")
    } /etc/shadow | ${pkgs.coreutils}/bin/cut -d: -f2)"
    if [ "$current" = "$seed" ]; then
      rm -f "$marker"
    else
      touch "$marker"
    fi
  '';
};
systemd.paths.castle-password-reminder-check = lib.mkIf (cfg.hashedPasswordFile != null) {
  description = "Re-run the password-reminder check whenever /etc/shadow changes";
  wantedBy = [ "multi-user.target" ];
  pathConfig.PathModified = "/etc/shadow";
};
environment.interactiveShellInit = lib.mkIf (cfg.hashedPasswordFile != null) ''
  if [ ! -e /var/lib/castle-turing/password-changed ]; then
    printf '\n\033[1;33mNote:\033[0m this account is still using its seeded initial password. Run \033[1mpasswd\033[0m to set your own.\n\n'
  fi
'';
```

Only the service's `script` and all three `lib.mkIf` gates change (from
`cfg.initialHashedPassword != null` to `cfg.hashedPasswordFile != null`,
tracking the option replacement in §1/§2 — deliberately not called a
"rename" here either, per §2's own argument); the path unit and the
banner text are otherwise unchanged from what exists today.

**The `script` above is the specced version, and the shipped one has two
more guards.** Read `modules/base/default.nix` for what actually runs;
this block is kept as written because the reasoning that produced the
two additions only makes sense against it. Both came from review, both
are in the comparison, and both were bugs this brief introduced by
treating "the shadow hash differs from the seed" as equivalent to "the
resident ran `passwd`" — an equivalence that held while the seed was a
build-time string and stopped holding the moment it became a runtime
file:

- **No password at all.** If the seed never decrypted at account
  creation, `update-users-groups.pl` writes `!` (or the field is `!!`,
  `*`, or empty). The seed file may later become perfectly readable —
  fixing the key and rebuilding does not repair an account that already
  exists, per §6 — so the check reads a good seed against a locked
  field, calls it "changed", and silences the banner forever on the one
  machine that most needs it. Those four values now leave the marker
  alone, exactly as the unreadable-seed branch does. (Overtaken by
  `docs/tasks/0036-reminder-banner-states.md`: that state is now
  recorded as its own marker so the banner can say it — this
  paragraph describes the 0032-era behaviour it replaced.)
- **A lock prefix is not a password change.** `shadow(5)`: "If the
  password field begins with an exclamation mark `!`, the password is
  locked. The remaining characters on the line represent the password
  hash." So `!$6$seed` is *the seed, locked* — and comparing it against
  an unprefixed `$6$seed` makes the `!` itself look like a change. A
  resident who ran `passwd -l` without ever changing their password got
  the banner silenced, and `passwd -u` would put them back on the
  shipped seed with nothing ever having said so. The shipped script
  strips leading `!` before comparing, twice — `!!` strips once to `!`,
  which is not empty, and would otherwise walk past the no-password
  guard into exactly the comparison it must not reach.

Neither is reachable by `test/vm-install/`, whose fixture secret always
decrypts, so both are verified by table-testing the *generated* unit
across every shadow-field shape rather than by CI. The residual — that
the banner's wording still describes a seeded password when the account
has none — was filed as
`docs/backlog/the-reminder-banner-cannot-say-you-have-no-password.md`,
since promoted to and fixed by
`docs/tasks/0036-reminder-banner-states.md`.

Nothing else needs editing as a consequence of keeping this machinery.
`modules/agent/default.nix`'s comment citing `castle-password-reminder-check`
as a design analogy, and `docs/tasks/0021-auto-dispatch.md`'s references
to the same unit, both stay accurate exactly as written — checked, not
edited, because the unit they describe still exists and still means
what they say it means.

### 5. The lockout story

This is the section to read twice. Everything in it is traced against
source (`update-users-groups.pl` and `secrets-for-users/default.nix`,
both cited above), not assumed.

**What NixOS actually does when the file is absent at activation.**
`update-users-groups.pl` (lines 241–247) checks `-e
$u->{hashedPasswordFile}`. If the file does not exist, it prints a
warning (`warn "warning: password file '...' does not exist\n"`) and
leaves `$u->{hashedPassword}` undefined. This is **not fatal**:
`warn` does not abort a Perl program, and none of the script's four
`die`s can be reached by a password file that failed to resolve. Each,
at the pinned rev, and why not:

| Line | `die` | Why the password path cannot reach it |
|---|---|---|
| 23 | `write_file(...) or die` | inside `updateFile`, which writes `/etc/passwd`, `/etc/shadow` and the declarative-users list. Reached only by an I/O failure on those writes — a different fault entirely, and one that fires whatever the password resolved to. |
| 66 | `die "$0: out of free UIDs or GIDs\n"` | `allocUid`, exhausted uid space. Independent of any password option. |
| 209 | `$u->{gid} = $groupsOut{$u->{group}}->{gid} // die` | the user names a group that does not exist. Independent of any password option. |
| 322 | `chown(...) || die "Failed to change ownership..."` | the block immediately after `updateFile("/etc/shadow", ...)`, handing `/etc/shadow` to `root:shadow`. The *nearest* `die` to this task's subject, and still not on its path: it fires on a failed `chown` of a file that has by then already been written, whatever the password field in it says. |

So the claim this section rests on is not "there are few `die`s" — the
count is not what makes it safe, and stating a count was the wrong
argument to make. It is that **the missing-password-file branch's only
effect is a `warn` and an undefined `$u->{hashedPassword}`**, which the
shadow-writing code further down already has a defined behaviour for
(`"!"` on creation, untouched otherwise). Activation continues, and the
account exists.

(Successive drafts of this brief said "exactly one" `die`, then "two".
Both were wrong; there are four. That this sits inside the section the
Hard constraints below single out as traced against pinned source
rather than assumed is exactly why the argument has been rewritten to
name them individually — a count is a claim nobody can check without
recounting, and recounting is what caught it twice.)
- For an account **created fresh at this activation** (a brand-new
  install, or a wipe): the account's shadow entry becomes `"!"` —
  locked, no password-based login possible for that account, but the
  account **does exist** (its uid, home directory, group memberships,
  and SSH `authorizedKeys` are all set up normally; nothing else in
  `update-users-groups.pl` depends on the password having resolved).
- For an account that **already exists** from a previous activation:
  nothing happens to its password at all — see "mutableUsers" below.
  This failure mode is confined to first-account-creation.

**What NixOS does when the file is present but the wrong content, or
decryption failed.** Two distinguishable causes upstream of
`update-users-groups.pl` ever running, both producing the same
downstream symptom (no file at `/run/secrets-for-users/admin-password-hash`,
hence the "absent" case above): the age key at
`castle.secrets.ageKeyFile` (default `/var/lib/sops-nix/key.txt`) is
missing entirely, or it is present but is not one of the recipients
`secrets.yaml` was actually encrypted for. `sops-install-secrets`
itself fails in `setupSecretsForUsers` in either case, and (per §3's
`users.deps`) does so *before* `update-users-groups.pl` runs, and does
not stop it from running anyway — this project's existing activation
behavior (`docs/private-layer.md`'s "When the key is missing or wrong",
and `hosts/xps9370/README.md`'s note that `nixos-install` reaches
activation via `nixos-enter`, which runs it as `"$system/activate" ||
true`) already establishes that one failed activation snippet does not
abort the rest — that behavior is not new to this task, only exercised
by a second secret now. The activation log names which of the two it
was: a missing-file error, or an age/sops decryption error — the same
diagnostic distinction `docs/private-layer.md` already documents for
the Wi-Fi PSK.

**Key-based SSH survives independently of all of this, verified.**
`modules/base/default.nix` sets `services.openssh.settings.PasswordAuthentication
= false`, `KbdInteractiveAuthentication = false`, and
`PermitRootLogin = "prohibit-password"`, and installs `cfg.sshKeys` into
**both** `users.users.${cfg.username}.openssh.authorizedKeys.keys` and
`users.users.root.openssh.authorizedKeys.keys`. None of that is gated
on, or reads from, `/etc/shadow` at all — public-key authentication is
a separate PAM/sshd path that never consults the password field, locked
or not. A resident holding the SSH key declared in `castle.admin.sshKeys`
can always reach the machine as root (which exists and is
key-authorized regardless of anything in this task) even in the total
failure case above, where the admin account itself was created with a
locked password.

**Recovery, written for someone already locked out of the console:**

1. `ssh root@<host>` (or `ssh <admin-username>@<host>`, if that account
   exists — it does, even in the locked-password case above). This
   works regardless of the secret's state; see the previous paragraph.
2. **Fix the login immediately, without waiting for a rebuild:**
   `passwd <admin-username>` sets a real, working password right now.
   This is not a workaround that will be reverted later — per
   "mutableUsers" below, `passwd` is exactly the mechanism that
   `mutableUsers = true` (this project's unchanged default) protects
   from being reverted by any future rebuild. You are back in
   immediately and durably.
3. Diagnose the underlying secret at your leisure, now that step 2 has
   removed the urgency: `ls -l /var/lib/sops-nix/key.txt` (present?
   mode `600`, owned by root?), `ls -l /run/secrets-for-users/admin-password-hash`
   (present at all?), `journalctl -b | grep -i sops` or `systemctl
   --failed` for the specific decryption error. A missing key means
   `nixos-anywhere --extra-files` didn't plant it (or planted it to the
   wrong path — check it matches `castle.secrets.ageKeyFile`); a
   present-but-wrong key means the machine's age recipient isn't
   actually one of the ones `secrets.yaml` was encrypted for (re-encrypt
   with `sops updatekeys` after fixing `.sops.yaml`, per
   `docs/private-layer.md`'s re-enrollment steps).
4. Once the secret is fixed and you rebuild, nothing changes about the
   account you already recovered in step 2 (mutableUsers again — its
   shadow entry is now whatever `passwd` set, and stays that way). The
   fix in step 3 only matters for the *next* fresh account creation —
   a future wipe, or a second admin account — which is exactly the
   scenario this whole section is about not letting go wrong twice.

### 6. `mutableUsers`: what actually happens on rebuild, and this task's recommendation

Restated from "What `hashedPasswordFile`'s semantics actually are"
above, because it is the section the original framing of this task got
backwards: with `users.mutableUsers` at its current, unset (`true`)
default, there is no "silent revert" defect to design around.
`passwd` changes are never reverted by a rebuild — that is precisely
what `mutableUsers = true` guarantees, for `hashedPasswordFile` exactly
as it already does for `initialHashedPassword`. Nothing about this
task's migration puts a currently-working password at risk of being
silently overwritten.

Flipping `users.mutableUsers` to `false` would change that: NixOS's own
description is direct about it — "you cannot change user passwords,
they will always be set according to the password options" — meaning
`passwd` would fail immediately and honestly (an explicit, loud error at
the moment it's run) instead of appearing to succeed and doing nothing.
That is a real, legitimate design this project's own instincts favor —
a surface that reports success for something that silently doesn't
persist is exactly the class of defect this project exists to remove —
but there is no such surface here to remove, because nothing currently
reports success and then reverts.

**This makes `users.mutableUsers` load-bearing for this design in a way
it was not before this task.** Everything above — the seed-only
behavior in §1, the lockout recovery in §5, and the kept (not deleted)
reminder machinery in §4 — is true *because* `mutableUsers` is `true`.
A private layer that sets `users.mutableUsers = false` silently
converts `castle.admin.hashedPasswordFile` from a one-time seed into an
always-applied password (`passwd` then fails outright, per the NixOS
description quoted above) — and, as a direct consequence, makes the
reminder check in §4 permanently inert (the write-to-shadow gate that
lets the shadow hash and the file diverge is exactly what
`!mutableUsers` removes, so they can never differ again) and its
banner's advice wrong (there is no longer a working `passwd` to run).
None of this is new risk this task introduces — `initialHashedPassword`
had the identical dependency on `mutableUsers` before today — but it
was never written down anywhere, and this brief is the first place that
traces it.

**Recommendation: do not flip `mutableUsers` in this task.** Not
because the honesty argument is wrong, but because there is no bug to
trade it against right now, and `mutableUsers` is not scoped to the
password at all — it governs whether **every** account and group on
the machine is managed declaratively or left to `useradd`/`groupadd`/
`passwd` at will, a decision with a blast radius far larger than one
option's semantics. Making that call as a side effect of a
password-hash task would be exactly the kind of decision this project's
own conventions ask to be made deliberately and separately, with its
own clarifying questions, not folded silently into an unrelated brief.

Two follow-on actions this task does take, both small and both
non-destructive:

- **Edit `docs/backlog/initial-password-is-seed-only.md` in place**
  (not delete — it is not resolved by this task, only shown to apply
  more broadly than its title currently suggests) to record that the
  same seed-only behavior now applies verbatim to
  `castle.admin.hashedPasswordFile`, not only to the option this task
  removes. See the file-by-file list.
- **File a fresh backlog entry** — `docs/backlog/mutableusers-false-for-declarative-passwords.md`
  or similar — naming the actual, real motivation for revisiting
  `mutableUsers`: a resident who genuinely wants "the encrypted secret
  is my password, full stop, changed only by editing it" gets that
  today only by accepting `mutableUsers = false` for the whole machine,
  and nothing currently tells them that trade exists. This is a
  different, larger, and more honest framing of the question than "fix
  a revert bug," because — per above — there isn't one to fix. Record
  the load-bearing dependency from the paragraph above in the same
  entry: flipping the option doesn't only change the password's
  semantics, it also silently neuters the reminder machinery §4 keeps —
  a second, previously invisible consequence a future decision on this
  needs to weigh.

### 7. Migration for the existing machine

Safer than it might sound, precisely because of "mutableUsers" above:
this migration **cannot change the password of an account that already
exists** — the write-to-shadow gate that protects a `passwd` change
from being reverted protects the current seeded password from being
retroactively rewritten by this migration too. Nothing here risks the
machine you are currently holding a working login to. What it does risk
is the **next** account creation — a wipe, a reinstall, a new admin
account — going wrong if the secret is set up incorrectly, which is why
step 4 verifies the mechanism before you rely on it, without ever
touching your live password.

Written as steps someone follows while holding a working system they do
not want to break:

1. **Generate the hash**: `mkpasswd -m sha-512`, exactly as before —
   nothing about how the hash itself is produced changes.
2. **Add it to `secrets.yaml`**: `sops secrets.yaml`, add
   `admin-password-hash: "$6$..."` under a new key. Commit
   `secrets.yaml` (never a plaintext password, never `key.txt`).
3. **Wire it in `resident.nix`**, per §3's worked example:
   `sops.secrets."admin-password-hash".neededForUsers = true;` and
   `castle.admin.hashedPasswordFile = config.sops.secrets."admin-password-hash".path;`.
   Remove `castle.admin.initialHashedPassword` from the same file in
   the same change — leaving both set is harmless (the removed option
   fails the build with the message from §2 the moment you bump your
   `flake.lock` pin to a rev carrying this task, which is the intended
   forcing function), but do not leave a stale seed value sitting next
   to the new mechanism.
4. **Deploy, and check the mechanism, not the password.** Rebuild the
   machine normally. **Your current login is unaffected either way** —
   confirm this is genuinely true for your own peace of mind by not
   changing anything else and logging in exactly as before. Then verify
   the *new* mechanism actually works, independent of your current
   password: `sudo cat /run/secrets-for-users/admin-password-hash` and
   confirm it matches the hash you put in `secrets.yaml`. If that file
   is missing or wrong, fix it now (per "The lockout story"'s diagnosis
   steps) — you are not locked out while you do, because nothing about
   your working login depends on this file yet.
5. **Only once step 4 is confirmed**, treat the old option as fully
   retired. The `mkRemovedOptionModule` message from §2 is your
   backstop if a stale `initialHashedPassword` line is still present
   somewhere at this point — the build fails loudly rather than
   silently ignoring it.
6. **Prove it for real, if you want certainty before the next wipe**:
   the only way to actually exercise the account-creation path this
   secret feeds is to create a fresh account or do a real reinstall.
   Most residents will reasonably skip this and trust step 4's direct
   read of the decrypted file instead — the same trust this project
   already asks for the Wi-Fi PSK, which nobody re-proves by rejoining
   the network on every deploy either. `test/vm-install/`'s extension
   (see Verification plan) is where this path gets proven against a
   real, disposable machine so no resident has to risk their own.

## Considered and rejected

- **`mkRenamedOptionModule` instead of `mkRemovedOptionModule`.** Argued
  in full in §2. Restated briefly: the two options take differently
  *shaped* values (a hash string vs. a file path), so a rename doesn't
  merely change behavior, it produces a value the new option cannot use
  — a private layer that trusted the rename discovers this only when an
  account it created afterward can't log in.
- **Deleting the password-reminder machinery outright**, this brief's
  own first instinct. Rejected on reread: the reasoning that motivated
  it — "the shadow hash always equals the file's hash after activation,
  so the check never fires" — is exactly the claim "What
  `hashedPasswordFile`'s semantics actually are" shows to be false
  under this project's `mutableUsers = true`. With that premise gone,
  both halves of the deletion argument go with it: the check is still
  meaningful, and "run `passwd`" is still correct advice. The coupling
  cost that looked like it would justify deleting rather than fixing —
  `modules/base` having to learn a sops-nix secret's internal path —
  turned out not to exist: the path is already `cfg.hashedPasswordFile`,
  a value `modules/base` already owns and already hands to NixOS
  itself; the check only needed to dereference it at runtime instead of
  embedding its build-time string. See §4.
- **Flipping `users.mutableUsers = false`** as part of this task.
  Argued in full in §6: the honesty argument for it is real, but there
  is no revert bug in the current design to weigh it against, and the
  option's blast radius (every account on the machine, not just this
  password) is a separate decision this task should not make in
  passing. A backlog entry replaces it.
- **A dedicated activation-time diagnostic** ("did the admin account
  actually get a usable password") beyond what `systemctl --failed` and
  the activation log already surface. Rejected for the same reason
  0031 rejected the equivalent for the Wi-Fi PSK: the platform already
  reports this loudly, in the two places a resident who cares would
  already be looking; a bespoke surface for an already-loud failure is
  mechanism nobody asked for.
- **A negative-path (missing/wrong key) phase in `test/vm-install/`**,
  mirroring the positive-path assertion this task does add. Considered
  and rejected: the failure mode is already traced precisely against
  source in "The lockout story," rather than inferred from behavior a
  harness run would have to reproduce, and a second full VM install
  (disko, `nixos-install`, first boot) roughly doubles the harness's
  runtime to prove something already provable by reading three lines of
  Perl. 0031 made the same call for the Wi-Fi PSK's missing/wrong-key
  case, for the same reason — "nothing about it is silent" was true
  then and is true here.
- **`initialPassword` / `password`** (the plaintext-in-the-store
  variants). Not seriously considered — they reintroduce exactly the
  store-exposure problem this task exists to remove, only with the
  plaintext password itself instead of its hash.
- **`hashedPassword`** (the non-seed, always-in-the-store-string
  sibling of `initialHashedPassword`). Rejected trivially: it is still
  a literal string option, so it still lands in the store — it does not
  solve the problem this task is scoped to solve regardless of its
  `mutableUsers` behavior.

## Hard constraints, restated

- **Never write personal data into this repo.** No real hash, no real
  password, no real machine's `secrets.yaml` contents. Every example in
  this brief and in the doc rewrite is either a placeholder
  (`REPLACE-WITH-...`, matching `flake.nix`'s existing convention) or an
  obviously-fake harness fixture generated fresh per test run.
- **Principle 01 test.** `castle.admin.hashedPasswordFile` is the
  public mechanism; the secret it points at, and the hash inside it,
  are private configuration. Nothing about a real resident's password
  is inferable from anything this task adds to the public repo.
- **Principle 02.** `nixosConfigurations.example` must keep compiling
  against a dummy resident with no real secret anywhere — `castle.admin.hashedPasswordFile`
  is a plain string, never required to resolve to a real file at
  evaluation time, which is exactly why it is typed `str` and not
  `path` (see §1).
- **This is the highest-risk task in the repo.** Every claim in "The
  lockout story" is traced against the actual pinned source, not
  assumed — an implementer who finds a claim here doesn't match what
  the pinned `nixpkgs`/`sops-nix` actually does must stop and correct
  this brief in place before shipping, per `CLAUDE.md`'s rule that a
  brief the implementation overtook gets corrected in the same PR, not
  left wrong.
- **S2: never edit `CLAUDE.md`.** No exception, autonomy grant or not.

## File-by-file change list

- `modules/base/default.nix` — remove `initialHashedPassword` (option +
  consumer only); add the `mkRemovedOptionModule` import (§2); add
  `hashedPasswordFile` (option + consumer, §1); **keep** the
  password-reminder service, path unit, banner, and marker file exactly
  as they are structurally, changing only the service's `script` to
  read its seed from `cfg.hashedPasswordFile` at runtime instead of
  embedding `cfg.initialHashedPassword` at build time, and all three
  `lib.mkIf` gates from `cfg.initialHashedPassword != null` to
  `cfg.hashedPasswordFile != null` (§4).
- `modules/desktop/default.nix` — update the assertion at ~lines
  349–358 from `initialHashedPassword != null` to `hashedPasswordFile
  != null`, with the corrected message (§1).
- `flake.nix` — `nixosConfigurations.example`'s admin block (~lines
  178–184): replace `initialHashedPassword = "REPLACE-WITH-A-REAL-HASH-this-is-a-placeholder-not-a-hash";`
  with `hashedPasswordFile = "/run/secrets-for-users/REPLACE-WITH-A-REAL-SECRET-NAME-this-is-a-placeholder-path";`
  — a plain string placeholder, matching the existing convention, that
  needs no real file to exist for `nix flake check` to pass (Principle
  02).
- `docs/private-layer.md` — in the `resident.nix` template: remove the
  `initialHashedPassword = "<your-password-hash>";` line, and either
  reference the new "Secrets" worked example or add a short inline one;
  update the `castle.admin.initialHashedPassword` bullet immediately
  below the template to describe `hashedPasswordFile` instead, folding
  in the corrected seed-only-under-mutableUsers behavior (§1's option
  description is the source text to adapt); add the §3 worked example
  to the "Secrets" section, positioned near the existing Wi-Fi PSK
  example; extend "When the key is missing or wrong" with the
  password-specific case (different ordering — decrypts before
  accounts exist, not after — and different observable symptom — a
  locked account, not a missing network profile) rather than adding a
  disconnected new section.

  **One edit this list did not foresee, and it is a real design
  consequence rather than a wording fix.** That document's "The
  installer image" section tells a resident to split `castle.admin`
  into its own `admin.nix`, imported by both the installed system and
  the installer image — and its example put the password line in that
  shared file. Under the old option that worked, because
  `modules/base` defines the option and the installer imports
  `modules/base`. Under the new one it does not: the value a resident
  is told to use is `config.sops.secrets."…".path`, and the installer
  image imports `nixosModules.base` but **not** `nixosModules.secrets`,
  so that line fails evaluation with the same "option does not exist"
  error the section already warns about for `castle.person`. It would
  also have nothing to point at — the installer runs before there is a
  partitioned disk to have planted an age key onto. So the password
  line moves out of `admin.nix` and into `resident.nix`, with the
  reasoning stated where a reader hits it. Verified against
  `nixosConfigurations.installer-example`, which sets only `username`
  and `sshKeys` and asserts nothing about a password.
- `docs/backlog/initial-password-is-seed-only.md` — small in-place
  edit (not deleted, not resolved by this task): note that the same
  seed-only behavior, verified in `docs/tasks/0032-password-hash.md`,
  now applies verbatim to `castle.admin.hashedPasswordFile`, and that
  the open question about detecting the divergence is unchanged by the
  option rename.
- `docs/backlog/disk-encryption.md` — small in-place edit: note that as
  of this task, the age key at `/var/lib/sops-nix/key.txt` also
  decrypts the admin account's login password, not only the Wi-Fi PSK
  and whatever else 0031 already put behind it — one more reason the
  stakes named in that entry's "Why it matters" section keep growing
  rather than shrinking.
- `docs/backlog/mutableusers-false-for-declarative-passwords.md` (new)
  — the follow-on entry from §6: the real, correctly-framed motivation
  for someday setting `users.mutableUsers = false`, not the "fix a
  revert bug" framing this task's own premise started from and
  corrected.
- `hosts/xps9370/README.md` — **corrected during implementation.** The
  original claim ("checked, no change required") was defensible but
  incomplete: the file never names `initialHashedPassword`, and its "no
  password on the admin account" prose (step 6) does describe a symptom
  rather than a mechanism, so nothing there became *false*. What became
  true is more specific than what it says. Before this task, "no Wi-Fi
  profile" and "no password" were two independent omissions a resident
  could make separately; after it, a single missing age key produces
  both, and the recovery path (SSH as root, which never consults
  `/etc/shadow`) is worth naming right where a reader is about to
  attempt a from-scratch install on a portless chassis. Three sentences
  added to step 6, no restructuring.
- `test/desktop-loop/test.nix` — **missing from this list entirely, and
  found by grep during implementation.** It sets
  `castle.admin.initialHashedPassword = testPasswordHash` (line ~284)
  and it is not a decorative consumer the way `test/vm-install`'s old
  `"!"` was: this VM types `testPassword` at a real, unmodified
  tuigreet prompt (line ~464), so the hash has to genuinely reach the
  account or the whole desktop-loop test fails at login. Migrated to
  `hashedPasswordFile` pointed at a `pkgs.writeText` store path holding
  the same already-committed fixture hash. A store path is the right
  answer *here specifically* and would be the wrong answer in a private
  layer — the file says so out loud, since a reader who copies the
  pattern without that caveat reintroduces exactly what this task
  removes. The value is a published fixture whose plaintext sits three
  lines above it in the same file, so nothing about putting it in the
  store discloses anything the repo does not already commit.

  Worth noting for whoever writes the next brief of this kind: the
  option-consumer list in "Before starting" was assembled from
  `modules/`, `flake.nix`, `docs/`, and `test/vm-install/` — a plausible
  set that happened to omit the one consumer with a *functional*
  dependency on the value rather than a structural one.
- `test/vm-install/vm-test-system.nix` — replace
  `castle.admin.initialHashedPassword = "!";` with a real (fixture)
  `hashedPasswordFile`, wired to a new `sops.secrets."harness-admin-password-hash"`
  with `neededForUsers = true`, per §3's pattern.
- `test/vm-install/run.sh` — extend the existing fixture-generation
  block (`FIXTURE_SECRET`, `harness-secrets.yaml`) with a second key,
  `harness-admin-password-hash`, holding a fixed, obviously-fake
  placeholder string (not shaped like a real crypt hash, so it cannot
  be mistaken for one) — same file, same throwaway age key, generated
  the same way and never committed, mirroring 0031's own
  `harness-fixture` exactly. Add the new phase-2d assertion (see
  Verification plan).
- `test/vm-install/README.md` — document the new phase-2d assertion in
  "What it asserts" and "Reading a failure," matching the existing
  phase2c entry's structure and level of detail.
- `docs/tasks/0032-password-hash.md` — this brief.

## Non-goals

- **Disk encryption.** `docs/backlog/disk-encryption.md` remains
  separate — and, per the file-by-file entry above, gains one more
  named reason to matter: this task puts a second credential (the login
  password, not only the Wi-Fi PSK) behind the same unencrypted-disk
  age key.
- **Multi-user password management.** This task touches `castle.admin`
  only; a machine with more than one declaratively-managed human
  account is out of scope, exactly as it was before.
- **The agent layer's own credentials.** Untouched, as in 0031.
- **Changing `users.mutableUsers`.** Argued at length in §6; the
  follow-on backlog entry in the file-by-file list is this task's
  entire response to the question, not a decision.

## Verification plan

**Automatable, and built as part of this task:**

- `nix flake check` — evaluates `modules/base`'s new option and the
  `mkRemovedOptionModule` against `nixosConfigurations.example`'s dummy
  resident (`hashedPasswordFile` stays a placeholder string, never
  required to resolve to a real file, per Principle 02) and
  `modules/desktop`'s updated assertion.
- **`test/vm-install/`, extended with a new phase-2d assertion.** This
  is where the central claim actually gets proven against a real
  machine, not described: after the installed system's first boot (the
  same boot phase2c already checks), assert that `/etc/shadow`'s
  password field for the `harness` account matches, byte-for-byte, the
  fixture hash placeholder `run.sh` encrypted before the install ever
  started — proof that the secret actually reached the account through
  `hashedPasswordFile` + `neededForUsers`, with nobody at any keyboard,
  and with no real password or hash anywhere in the process. This needs
  no plaintext password at all: the fixture value is never meant to be
  a working crypt hash, only an opaque marker whose exact bytes are
  checkable.
  - Retrieve the shadow field over the same SSH connection every other
    phase-2 assertion uses. **Implemented as a direct read of
    `/etc/shadow`** (`grep -m1 '^harness:' /etc/shadow | cut -d: -f2 |
    tr -d '\n'`) rather than this brief's originally-specified `getent
    shadow harness`: the claim under test is literally about that file's
    second field, and routing it through NSS adds a way for the
    assertion to fail — or, worse, to pass — for reasons unrelated to
    the pipeline. It is also exactly the read `modules/base`'s own
    reminder check performs. The `tr -d '\n'` strips only the line
    terminator `cut` emits, so `cmp` compares the field's own bytes and
    nothing else.
  - Compare against the exact fixture string `run.sh` encrypted,
    written to a workdir file the same way `expected-secret` /
    `actual-secret` already work for phase2c, so the comparison is
    `cmp` on bytes, not a shell string comparison.
  - On mismatch, dump both values to the log directory the same way
    phase2c's `phase2c-secret-actual.od` does, so a red CI run publishes
    the diagnostic as an artifact.
  - **One thing this brief did not anticipate about *when* the
    assertion is satisfied**, recorded because it is the mechanism the
    whole phase depends on and it is not the obvious one. The `harness`
    account is not created on the installed system's first boot: it is
    created earlier, inside `nixos-enter` during `nixos-install`, in
    phase 1. So the secret has to decrypt *there*, in a chroot on
    `/mnt`, for phase 2d to pass — and if it did not, phase 2d fails
    with a locked `"!"` even though the boot itself and every other
    assertion look perfectly healthy, because by first boot the account
    already exists and §1's write-to-shadow gate leaves it alone
    forever. That is the same seed-only property this task documents,
    seen from an angle that makes it a hazard rather than a
    reassurance. It works (the age key is planted by `--extra-files`
    before `nixos-install` runs, and `sops-install-secrets` mounts its
    ramfs happily inside `nixos-enter`'s private mount namespace), and
    the harness is what proves it works rather than the reasoning
    above. `test/vm-install/README.md`'s phase-2d entry sends a reader
    to `phase1-nixos-anywhere.log` first for this reason.
- **What a wrong or missing key produces is described, not additionally
  proven in the harness** — see "Considered and rejected" for why a
  second, negative-path VM install was weighed and set aside. The
  positive-path harness run already implicitly exercises the
  "activation continues past a failed snippet" behavior this section's
  reasoning depends on, because 0031's own harness already tolerates
  that same shape of non-fatal activation warning for the Wi-Fi secret.
- **The reminder machinery's corrected script (§4) is not separately
  exercised by the harness.** `vm-test-system.nix`'s account is created
  fresh every run and the harness never runs `passwd` against it, so no
  boot in this suite reaches the check's "seed differs from current"
  branch — only, implicitly, "seed matches current" (the marker stays
  absent right after creation) and, if the fixture secret is ever
  deliberately broken, the "seed unreadable" branch added in §4. This
  is fine to leave as a described-not-proven gap, matching the standard
  the rest of this plan already sets, but it means the one branch that
  actually depends on a resident's own behavior — noticing the nag,
  running `passwd`, seeing it stop — is confirmed by reading the script
  and the ordering proof in §4, not by CI.

**Needs human hands:**

- Confirming, on the real reference host (`hosts/xps9370`), that the
  migration steps in §7 actually leave a currently-working login
  untouched — the harness proves fresh-account creation; only a human
  running the migration on their own already-provisioned machine proves
  the "your existing password survives" half of this task's central
  safety claim. Bias toward doing this rather than building a second
  harness for it: it is a one-time check on a machine that already
  exists, not a repeating one.
- Logging into the reference host after that migration and confirming
  the reminder banner still shows (seeded password, not yet changed)
  and clears after running `passwd` — the one end-to-end confirmation
  of §4's fix that no automated check in this plan provides.

## Implementation prompt

For the session that implements this brief: read `CLAUDE.md` in full,
this brief in full, and every file named in "Before starting" before
writing anything. Work on branch `task/0032-password-hash`, already
checked out in this worktree — do not create a new branch or touch any
other checkout. Scope diffs and reviews against `origin/main` (`git
fetch` first).

**Before writing any code**, re-verify the three load-bearing claims
this brief's safety argument depends on, against whatever `nixpkgs` and
`sops-nix` revs this implementation's `flake.lock` actually pins (they
may have moved since this brief was written): (1) that
`users.mutableUsers` still defaults to `true` and this project still
sets it nowhere, and that an existing account's shadow entry is still
left untouched by `hashedPasswordFile` under that default
(`update-users-groups.pl`'s `$sp_pwdp` gating, quoted in "What
`hashedPasswordFile`'s semantics actually are"); (2) that
`neededForUsers` still decrypts via `system.activationScripts.setupSecretsForUsers`
with `users.deps = [ "setupSecretsForUsers" ]`, still ahead of account
creation, at the path `/run/secrets-for-users/<name>` (`secrets-for-users/default.nix`,
quoted in §3); (3) that `stage-2-init.sh` still runs
`$systemConfig/activate` to completion before `exec`-ing systemd on a
boot without `boot.initrd.systemd.enable` set, which is what makes §4's
`wantedBy = [ "multi-user.target" ]` ordering claim for the kept
reminder check a guarantee rather than a hope. If any of the three has
changed, **stop and correct this brief in place** before implementing
against it — per `CLAUDE.md`'s rule that a brief the implementation
overtook gets fixed in the same PR, and per this brief's own "Hard
constraints" entry naming this the highest-risk task in the repo.

Implementation order:

1. `modules/base/default.nix` — the option, the consumer, the
   `mkRemovedOptionModule`, and the reminder machinery's seed-source fix
   (kept, not deleted), per §1, §2, §4.
2. `modules/desktop/default.nix` — the assertion update, per §1. Run
   `nix flake check` after these first two steps, before touching
   anything else, to confirm the option plumbing evaluates cleanly
   against the dummy resident.
3. `flake.nix` — the placeholder update in `nixosConfigurations.example`,
   per the file-by-file list.
4. `docs/private-layer.md` — the template edit, the bullet rewrite, the
   new worked example, and the "When the key is missing or wrong"
   extension, per the file-by-file list.
5. `docs/backlog/initial-password-is-seed-only.md`,
   `docs/backlog/disk-encryption.md` — the small in-place edits.
6. `docs/backlog/mutableusers-false-for-declarative-passwords.md` — the
   new entry, per §6, including the reminder-machinery consequence.
7. `test/vm-install/run.sh`, `vm-test-system.nix`, `README.md` — the
   fixture extension and the new phase-2d assertion. This is the part
   most worth iterating on against the real harness rather than writing
   blind against this spec — `docs/tasks/0023-resume-cold.md`'s own
   observation about fixture-writing applies here too, and it is the
   part of this task that actually proves the central claim rather than
   just asserting it.

Before opening a PR: run `nix flake check`; run `test/vm-install/run.sh`
locally if a KVM-capable machine is available, or via `gh workflow run
vm-install-test.yml` otherwise; re-verify the three claims named above
one more time against whatever actually got locked; if a private layer or
the reference host's own config needs the §7 migration run for real,
flag that as the one step in the Verification plan that needs human
hands rather than attempting it from this worktree. Then run
`/code-review` scoped against `origin/main`, address its findings, then
run `tools/codex-review.sh` for a second opinion, posting its findings
verbatim with any disposition in a separate comment underneath.
