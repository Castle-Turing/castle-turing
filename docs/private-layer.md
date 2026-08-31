# The private layer

*What you must write, file by file, to make Castle Turing yours. This
repo — the public one — is the castle: mechanism only. Your private repo
is the resident. This document is the complete interface between them; if
you find yourself needing something not listed here, that is a bug in the
framework's design, not in your configuration.*

## Shape

One private git repository (do not fork this one — Principle 01:
customization is the contents of the private layer, not a fork of the
code). Minimum contents:

```
flake.nix       Assembles your machine from this repo's exported modules.
flake.lock      Pins the exact rev of the public repo — an audit artifact.
resident.nix    Who you are: the castle.admin values.
README.md       Optional but recommended: what lives here and what must not.
```

## `flake.nix`

Take this repo as an input and instantiate a `nixosConfiguration` from
its exported modules:

```nix
{
  inputs = {
    castle-turing.url = "github:Castle-Turing/castle-turing";
    nixpkgs.follows = "castle-turing/nixpkgs";
  };

  outputs =
    { nixpkgs, castle-turing, ... }:
    {
      nixosConfigurations.<yourhost> = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          castle-turing.nixosModules.base
          castle-turing.nixosModules.host-xps9370 # or your own host module
          castle-turing.nixosModules.home # optional: home-manager + git identity
          castle-turing.nixosModules.desktop # optional: Sway desktop session
          castle-turing.nixosModules.dev # optional: Emacs, git, gh, ripgrep, fd, claude-code, python3
          castle-turing.nixosModules.agent # optional: the agent-layer CLI + state dir
          castle-turing.nixosModules.secrets # optional: encrypted secrets, via sops-nix
          ./resident.nix
        ];
      };
    };
}
```

The exported modules:

- `nixosModules.base` — the substrate every host shares: flakes enabled,
  SSH hardened, the admin user declared from `castle.admin.*` options.
  It asserts that you supplied an identity; an empty resident does not
  build.
- `nixosModules.host-xps9370` — the reference machine (Dell XPS 13 9370),
  with its nixos-hardware and disko modules already bound. On other
  hardware, write your own host module in your private repo (or better,
  PR it here — hosts are public, machine facts identify no one) following
  `hosts/xps9370/`'s shape.
- `nixosModules.home` — home-manager, wired in with its own input already
  bound, plus your git commit identity from `castle.person.*`. Optional:
  a headless host has no use for a per-user environment.
- `nixosModules.desktop` — the graphical session: Sway (with its IPC
  socket as the documented control surface the agent layer drives —
  `modules/home`'s Sway config is the first thing that actually drives
  it, docs/tasks/0009), foot, fonts, XDG portals, PipeWire, Firefox,
  mako (the notification daemon behind the agent layer's `notify`
  channel) + libnotify, a cursor theme package, and greetd + tuigreet
  for login. Also declares the `castle.display.*` options — see "The
  display-preference slot" below. Deliberately no auto-login — see the
  module's own comments for why. Asserts `castle.admin.hashedPasswordFile`
  is set, since a login prompt with no password behind it is a lockout,
  not security. Optional: skip it on a headless host.
- `nixosModules.dev` — this project's own development tools (Emacs, git,
  gh, ripgrep, fd, claude-code, python3). No private data, no assertions.
- `nixosModules.agent` — the agent layer's CLI (`castle`, plus
  `castle-modal` and the default `castle-worker-claude` worker tenant)
  and ten options: `castle.agent.stateDir` (wired into
  `CASTLE_STATE_DIR`), `castle.agent.worker.command` (wired into
  `CASTLE_WORKER_COMMAND` — which tenant holds the worker seat),
  `castle.agent.worker.timeoutSeconds` (`CASTLE_WORKER_TIMEOUT`),
  `castle.agent.repo.private` and `castle.agent.repo.mechanism`
  (`CASTLE_PRIVATE_ROOT`/`CASTLE_MECHANISM_ROOT` — which checkouts the
  tenant operates on; the old name `castle.agent.worker.repoRoot` still
  works, with a deprecation warning naming the new one),
  `castle.agent.notify.command`
  (wired into `CASTLE_NOTIFY_COMMAND` — what the router's `notify`
  channel actually runs), `castle.agent.dispatch.enable` (whether
  filed errands start themselves), and the three that decide what
  happens to a change you approve — `castle.agent.apply.enable`,
  `castle.agent.apply.evaluateFlake` and
  `castle.agent.apply.timeoutSeconds`. See "The agent's state" and
  "What happens to a change you approve" below, and
  `agent/README.md`. An unset `stateDir`/`notify.command` just falls
  back to a per-user or built-in default rather than failing
  evaluation, since the agent layer is optional the way `desktop`/`dev`
  are, and the two `repo.*` options do not fail evaluation either — the
  refusal they carry happens at errand time instead, when a worker turn
  with no private checkout writes a `failed` result naming the option
  rather than guessing a directory; `worker.command` and
  `worker.timeoutSeconds` always have a usable default (a headless
  `claude -p`, and fifteen minutes) since the worker seat needs
  *something* to default to.
  Three assertions beyond the "no literal `"` in the value" check
  every string option here carries: `dispatch.enable` requires
  `stateDir`, because unattended writing is exactly when the journal
  has to be the durable one you chose rather than a per-user fallback;
  and each of `repo.private`/`repo.mechanism`, when set at all, must
  be an **absolute** path, since a relative one names a different
  place depending on who invoked the worker turn.
- `nixosModules.installer` — the agentic installer image: bootable NixOS
  media, SSH-reachable with zero console interaction, using the same
  `castle.admin` values as everything else here. See "The installer
  image" below.
- `nixosModules.secrets` — encrypted secrets. Two options,
  `castle.secrets.sopsFile` (which encrypted file of yours holds them)
  and `castle.secrets.ageKeyFile` (where on the machine the key that
  opens it lives), plus the whole of sops-nix's own module bound in
  behind them — `sops.secrets.*`, `sops.templates.*`, and the
  activation-time decryption that writes plaintext to `/run` and
  nowhere else. Optional and inert until you declare something: a
  configuration that imports it and sets neither option evaluates and
  boots exactly as before. See "Secrets" below, which is worth reading
  end to end before you generate your first key, because the order of
  the steps is what makes a reinstall survivable.

`nixpkgs.follows = "castle-turing/nixpkgs"` keeps your system on exactly
the package set the framework is tested against. Omit it only if you know
why.

## `resident.nix`

The values this repo may never contain:

```nix
{ ... }:
{
  castle.admin = {
    username = "<your-login>";
    sshKeys = [ "<your-openssh-public-key>" ];
    # Optional — only needed if you use nixosModules.desktop (or any
    # other host with an interactive console). Deliberately not shown
    # here: it takes a *path on the machine*, not a hash, and the path
    # worth using is an encrypted secret's — which needs this file's
    # header to be `{ config, ... }:` rather than `{ ... }:`. See the
    # worked example under "Secrets" below and copy it whole.
    # hashedPasswordFile = ...;
  };

  # Optional — only needed if you use nixosModules.home.
  castle.person = {
    gitUserName = "<your-name>";
    gitUserEmail = "<your-email>";
  };

  # Optional — only meaningful if you use nixosModules.agent. Points the
  # `castle` CLI at a durable, git-tracked directory rather than a
  # per-user default under $XDG_STATE_HOME. Deliberately a *sibling* of
  # this repo and not a directory inside it: everything committed in
  # this repo is copied into the world-readable /nix/store every time
  # the flake is evaluated, and a journal is the last thing that should
  # be. See "The agent's state" below, which is worth reading before
  # you pick a path.
  castle.agent.stateDir = "/home/<your-login>/private-state";

  # Optional — override the worker tenant (default: a headless
  # `claude -p`, see agent/castle-worker-claude) or the router's notify
  # command (default: notify-send on $PATH). Most residents on
  # nixosModules.desktop need neither.
  # castle.agent.worker.command = "/path/to/your/own/worker/tenant";
  # castle.agent.notify.command = "";  # e.g. to no-op on a headless host
  # castle.agent.worker.timeoutSeconds = 900;  # how long a hung tenant may run

  # Which checkouts the worker tenant is given. repo.private is this
  # repository's own path on the machine — set it whenever you enable
  # dispatch below, or every dispatched errand fails saying it has
  # nowhere to work. repo.mechanism is a checkout of the public Castle
  # Turing framework, and leaving it unset is the normal case: you
  # consume that framework as a flake input, not as a working tree.
  # The old name castle.agent.worker.repoRoot still works and still
  # means repo.private, with a deprecation warning.
  # castle.agent.repo.private = "/home/<your-login>/private";
  # castle.agent.repo.mechanism = "/home/<your-login>/src/castle-turing";

  # Optional — only meaningful if you use nixosModules.secrets. Names
  # the *encrypted* file in this repo that holds your credentials; the
  # key that decrypts it never lives in any repo, and is planted on the
  # machine at install time instead. Read "Secrets" below before you
  # create either. castle.secrets.ageKeyFile has a working default
  # (/var/lib/sops-nix/key.txt) that the documented install step plants
  # to, so most residents set only this one line.
  # castle.secrets.sopsFile = ./secrets.yaml;

  # Optional, and the one authority decision in this file: let filed
  # errands start themselves, with no `castle work` typed by hand.
  # Off unless you turn it on — see "Automatic dispatch" below before
  # you do, and set repo.private with it.
  # castle.agent.dispatch.enable = true;

  # Optional — taste, only meaningful if you use nixosModules.desktop.
  # hosts/xps9370 already supplies hardware-derived scale/cursor/console
  # defaults for that chassis, and the module itself supplies legible
  # framework defaults for the two point sizes and generic families for
  # the two typefaces; override any of these here to your own
  # preference regardless of host — see "The display-preference slot"
  # below for which layer is actually supplying each value today, and
  # what setting one to `null` does (not the same thing for every
  # option).
  castle.display = {
    # scale = 1.5;
    # cursorTheme = "Bibata-Modern-Ice";  # or your own cursor package
    # cursorSize = 32;
    # terminalFont = "Fira Code";  # illustrative — needs pkgs.fira-code
    # uiFont = "Inter";            # illustrative — needs pkgs.inter
    # terminalFontSize = 11;
    # wallpaper = "/home/you/Pictures/my-wallpaper.jpg";
    # wallpaper = null;  # no wallpaper
  };
}
```

- `castle.admin.username` — login name of the human administrator.
- `castle.admin.sshKeys` — OpenSSH public key strings granted admin
  access (both to your user and to root, for remote rebuilds). Public
  keys are not secrets, but they identify a person — that is why they
  live here.
- `castle.admin.hashedPasswordFile` — **a path on the machine**, not a
  hash. It names a file holding one line: the hashed (never plaintext)
  password, as `mkpasswd -m sha-512` produces it. The documented way to
  put a file there is the encrypted-secret example under "Secrets"
  below; nothing in this repo, and nothing your flake evaluates, ever
  reads that file — NixOS does, at activation, on the machine itself.
  That is the whole point (`docs/tasks/0032-password-hash.md`): the hash
  used to be a string in this option, which meant a copy of it in the
  world-readable Nix store on every rebuild.

  Only required if you import `nixosModules.desktop`, which asserts it
  is set — see that module for why
  (`docs/tasks/0003-findings.md` finding #1, the first-boot console
  lockout).

  **It seeds, it does not rotate.** Because this project leaves
  `users.mutableUsers` at its NixOS default (`true`), the file's
  contents are applied only at the moment the account is *first
  created*. Editing the secret and rebuilding changes nothing about an
  account that already exists — no error, no warning, no change. If you
  want your live password to match the file, run `passwd` yourself. The
  same property is what makes a `passwd` change permanent: no rebuild
  will ever revert it. (This is not new with the option's change of
  shape; it was equally true of the hash-string option this replaces,
  and `docs/backlog/initial-password-is-seed-only.md` is the record of
  it surprising someone.)

  Whatever seeds the account — even a deliberately weak,
  known-to-you-only default — `nixosModules.base` nags an interactive
  shell to run `passwd` until the live hash actually differs from the
  file's, and stops the moment it does. It never forces the change (no
  PAM-level expiry): that risks a tuigreet/greetd lockout of its own.
  If the file cannot be read at all, the nag says nothing rather than
  guessing, and leaves whatever it last said standing.

  The option is typed as a plain string rather than a Nix path on
  purpose, the same as `castle.secrets.ageKeyFile` below: it names a
  place on the target's disk, and nothing about evaluating your flake
  should require that place to exist, let alone copy what is in it.
- `castle.person.gitUserName` / `castle.person.gitUserEmail` — your git
  commit identity, wired into home-manager's `programs.git`. Only
  required if you import `nixosModules.home`, which asserts both are
  set.
- `castle.agent.stateDir` — where the `castle` CLI's journal (and the
  resident model) live. Optional even if you import
  `nixosModules.agent`: unset, the CLI falls back to
  `$XDG_STATE_HOME/castle`, a reasonable per-user default but not the
  durable, git-tracked location the architecture calls for. Where you
  point it matters for more than durability — a path inside this
  repo's tracked tree publishes your journal to the Nix store on every
  rebuild. Read "The agent's state" below before choosing one.
- `castle.agent.worker.command` — which tenant holds the worker seat
  (docs/architecture.md's Proposal 03). Defaults to a headless
  `claude -p` (`agent/castle-worker-claude`); override only if you're
  running a different tenant. Whatever holds this seat, it never
  deploys — see `agent/README.md`.
- `castle.agent.worker.timeoutSeconds` — how long the worker tenant
  may run before `castle work` kills its whole process group and
  records `outcome: timeout`. Default 900 (fifteen minutes), a chosen
  value rather than a measured one; raise it if your tenant
  legitimately takes longer.
- `castle.agent.repo.private` — your own configuration repository, the
  one this file lives in (`$CASTLE_PRIVATE_ROOT`). No default this repo
  could supply: your checkout path is your data, not the framework's.
  **Unset, a worker turn refuses**: it writes a `failed` result naming
  this option rather than guessing a directory, which is what it used
  to do — and the directory it guessed under automatic dispatch was
  your home folder. Set this whenever you enable dispatch, and note
  that each errand which fails this way has spent its one automatic
  attempt for good. Must be an absolute path. Renamed from
  `castle.agent.worker.repoRoot`, which still works and prints a
  deprecation warning.
- **The worker checks your private checkout before every turn, and
  git has to be able to use it.** Beyond existing and being absolute,
  the path must be the **root** of a git working tree — not a
  subdirectory of one, since a diff produced there would carry paths
  relative to the wrong root. Where `git` is on the worker's `$PATH`
  it is asked directly; where it is not (it arrives via
  `nixosModules.dev`, which is optional) the check falls back to
  looking for `.git` and says so rather than claiming more.

  One failure here is worth knowing in advance because the fix is not
  obvious: if your checkout was cloned by `root` during install, or
  lives on a mount owned by a different uid, git refuses it with
  "detected dubious ownership" and the turn writes a `failed` result.
  That refusal is deliberate — a repository git will not touch is not
  one this can work in reliably — and the result record names the fix
  in place. It is either taking ownership of the directory, or:

      git config --global --add safe.directory /home/<you>/private

- `castle.agent.repo.mechanism` — a checkout of the *public* Castle
  Turing framework, if you happen to keep one
  (`$CASTLE_MECHANISM_ROOT`). **Leaving this unset is the normal
  case**, not a misconfiguration: you consume the framework as a flake
  input pinned in `flake.lock`, and only someone developing it keeps a
  working tree around. What it costs you is stated rather than hidden —
  a worker on such a host cannot propose a change to the framework's
  own `modules/` at all, because there is nowhere on disk to diff
  against, and it will say so and stop rather than fabricate one. A
  path here that is not a usable git working tree never refuses a
  turn; it degrades that checkout for the turn and says so in every
  result the turn writes, so a typo cannot go quiet.
- **Your real checkout path may appear in the journal, and must never
  appear in the public repo.** A path in a result body is fine — the
  journal is yours, wherever you keep it. (It is deliberately *not*
  inside this repository any more, since
  `docs/tasks/0030-state-outside-the-flake.md`; the sentence that used
  to say otherwise here predated that task and was missed by its sweep.
  See "The agent's state" below.) A path pasted out of
  a journal into a framework PR, a test fixture, a doc or a commit
  message is not — that is the hard rule in the public repo's own
  `CLAUDE.md`, and the placeholders it publishes (`/home/resident/...`)
  exist so nobody has to invent one.
- **`stateDir` and both `repo.*` values land in
  `/etc/pam/environment`, which is world-readable.** They ride
  `environment.sessionVariables`, which is how they reach a
  greetd-launched Sway session at all. On a single-user laptop this is
  not a problem; on a machine with other login accounts, those accounts
  can read the *paths* (never the contents) you configured here. Worth
  knowing before you decide where your private repo lives.
- `castle.agent.dispatch.enable` — whether filed errands start
  themselves. Default `false`. See "Automatic dispatch" below.
- `castle.agent.apply.enable` — whether a change **you have approved**
  gets made in this repository, with no command typed by hand. Default
  `false`. It never activates anything and never pushes anything; see
  "What happens to a change you approve" below before turning it on.
  Requires `stateDir` and `repo.private`, both asserted at evaluation
  time — unlike dispatch, which only warns you at errand time, because
  what an unconfigured root costs here is an approval you gave rather
  than an errand that can simply be re-run.
- `castle.agent.apply.evaluateFlake` — whether, after making such a
  change, `castle` checks that the configuration it produces still
  evaluates and builds. Default `false`. This is the only thing in the
  agent layer that ever evaluates your flake, which is why it is named
  for evaluation and gated separately: evaluating copies this
  repository's whole tracked tree into the world-readable Nix store.
  That is safe as long as your journal is not in that tree — and
  `castle` checks exactly that before evaluating, declining rather than
  publishing your decision history.
- `castle.agent.apply.timeoutSeconds` — how long that check may run
  before its whole process group is killed. Default 1800 (thirty
  minutes), deliberately much longer than the worker's: that one bounds
  a model call, this one bounds a build that may compile a kernel. The
  change is already made and committed by the time the clock starts, so
  a timeout costs you the check, never the change.
- `castle.agent.notify.command` — what the router's `notify` channel
  actually runs (docs/architecture.md). Defaults to plain `notify-send`
  on `$PATH`, which is real once `nixosModules.desktop` is imported
  (it installs mako + libnotify); set to `""` on a headless host to
  no-op the attempt outright.
- `castle.secrets.sopsFile` — the encrypted file in this repo that
  holds your credentials, as a Nix path (`./secrets.yaml`). Only
  meaningful with `nixosModules.secrets`, and only *needed* once you
  declare a `sops.secrets.<name>`. Unset, nothing about the mechanism
  fails: it stays a declared slot with nothing in it.
- `castle.secrets.ageKeyFile` — where on this machine the age private
  key that decrypts that file lives. Defaults to
  `/var/lib/sops-nix/key.txt`, which is exactly where the install step
  in "Secrets" below plants it; change it only if you have a reason,
  and change the install step to match, or the first activation fails
  saying it cannot read the key.
- `castle.display.{scale,cursorTheme,cursorSize,terminalFont,
  terminalFontSize,uiFont,uiFontSize,consoleFont,wallpaper}` — taste, only
  meaningful with `nixosModules.desktop`. They do not all resolve the
  same way: four (`scale`, `cursorTheme`, `cursorSize`, `consoleFont`)
  still need a host module to supply the real value, five carry a
  non-null framework default of their own — see "The display-preference
  slot" below for which is which and why `null` no longer means the
  same thing everywhere in this set.

## The display-preference slot

`modules/desktop` declares nine options under `castle.display`:
`scale`, `cursorTheme`, `cursorSize`, `terminalFont`,
`terminalFontSize`, `uiFont`, `uiFontSize`, `consoleFont`, and
`wallpaper`.

All nine are `nullOr`, but **`null` no longer means the same thing
for each of them**, and an earlier version of this document was wrong
to say it always means "framework default: leave that setting alone
entirely." That is still true for `scale`, `cursorTheme`, `cursorSize`,
and `consoleFont` — nothing is set, and whatever Sway, GTK, or the
kernel does on its own applies. For `terminalFont`, `terminalFontSize`,
`uiFont`, `uiFontSize`, and `wallpaper`, the framework has a real
default (see the table below), so setting one of these five to `null`
is an **explicit opt-out** — you are turning a default off, not
declining to state one.

Which layer actually supplies each option's value differs, and that
asymmetry is itself the substance of this update, not an inconsistency
to smooth over in the retelling:

| Option(s) | Resolved by | Why |
|---|---|---|
| `scale`, `cursorTheme`, `cursorSize`, `consoleFont` | three layers, ascending priority: this module's `null` default → a host module's `lib.mkDefault` → your `resident.nix` | each is a hardware/machine fact, not personal data (Principle 01 consequence 2) — only a host module can know a panel's physical DPI, a cursor size to match it, or (see below) a console font that fits a real pixel grid; `hosts/xps9370` sets all four this way |
| `terminalFontSize`, `uiFontSize` | this module's own non-null default (12, 11) | a point size is density-independent because `scale` already normalizes density, so one number is right on every host — no host-specific layer is needed |
| `terminalFont`, `uiFont` | this module's own default, but deliberately the *generic* family `monospace`/`sans-serif` — meant to be overridden from `resident.nix` | the framework does not decide what typeface a Castle Turing looks like; a generic family always resolves, where naming a specific face would fail silently on any machine missing it |
| `wallpaper` | this module's own `lib.mkDefault` | a wallpaper is a framework-owned asset with one canonical default, not a machine fact — the framework module itself supplies it (the shipped image), and a resident can override with a different path or set `null` to disable it |

`nix flake check` proves this resolution via an assertion in this
repo's `nixosConfigurations.example` (`flake.nix`) — read it if you
want to see the exact layering the check guarantees, including the
non-uniform cases above and not just the original three-layer ones.

Of the first row, `cursorSize` and `scale` are simple values (an
integer and a float — Sway's own output-scale unit). `cursorTheme` is
a *name*, and it only means something paired with a package that ships
a theme by that name: `modules/desktop` installs `pkgs.bibata-cursors`
so the option has something real to point at out of the box
(`hosts/xps9370` defaults to its `"Bibata-Modern-Classic"` theme) — if
you want a different cursor theme, add its package to your own
private-layer config and set `cursorTheme` to one of *its* theme
names. Note the dependency this creates: `cursorSize` only takes effect
once `cursorTheme` is non-null anywhere in the stack (an unset theme
leaves the whole `home.pointerCursor` slot untouched, by design — see
`modules/desktop`'s option description) — on `hosts/xps9370` that's
already satisfied by the host's own default, but if you override
`cursorTheme` to `null` explicitly to opt back out of a managed cursor
theme, `cursorSize` goes inert with it.

Still in the first row, `consoleFont` shares its layering with
`scale`/`cursorTheme`/`cursorSize` but for a different reason: the
virtual console never sees `castle.display.scale` at all — it is a
raw pixel grid, so a font sized correctly on a 331 PPI panel is
absurd on a 1080p one, the same argument that keeps `scale` and
`cursorSize` out of this module in the first place. Unlike
`cursorSize`, though, there is no sane cross-host number to fall back
to if no host module sets one, so this module's own default stays
`null` with nothing implied behind it — `hosts/xps9370` sets
`"spleen-16x32"` via `lib.mkDefault`, and a host with no display
module at all just gets the kernel's built-in 8x16 font, which is
exactly what "leave it alone" means for this option.

`terminalFont` and `uiFont` are names too, and carry the same
dependency in reverse: the framework's generic defaults always
resolve because `modules/desktop` ships plain `dejavu_fonts`, but a
real face you name from your own private layer is only real once you
also add the package that provides it — the framework deliberately
does not guess which one you mean or install it for you. `terminalFontSize`
and `uiFontSize` compose with their matching font name into a single
value (foot's `<font>:size=<n>`, or a Pango string for Sway's chrome),
and the two should be judged together, not separately: a size that
reads correctly against one weight of a face can read thin or heavy
against another.

None of these are values to derive by reasoning about DPI —
`docs/tasks/0013-first-deploy-findings.md` is the record of that
going wrong (a cursor size "corrected" for `scale` that was actually
double-compensating, and shipped dramatically oversized).
`tools/font-sweep.sh` opens candidate terminal/UI fonts and sizes side
by side on the real panel so you can pick by looking instead;
`tools/console-font-sweep.sh` does the same for `consoleFont` on a
spare virtual console, the one surface here you cannot preview from
inside a running Wayland session at all.

If your own config touches
`wayland.windowManager.sway.config.keybindings` — to rebind the modal
chord, add your own, or anything else — wrap your definition in
`lib.mkOptionDefault`, exactly as `modules/home` does, rather than
defining it bare. home-manager supplies its ~50 stock bindings as this
option's own `default`, at the same priority `mkOptionDefault` writes
at; a bare definition sits at a lower priority number and silently
discards that *entire* default set the moment your module's definition
is merged in, not just the keys you named. This is the same finding-1
lockout `modules/home/default.nix`'s long comment on `keybindings`
documents, reachable from the private-layer side instead — see
docs/tasks/0019 for how it was found and verified.

## Laptop ergonomics (optional)

`nixosModules.desktop` binds the media and brightness keys for you —
there is nothing to configure for those, and nothing to opt into. Four
options exist for the parts that are taste or that only your machine
knows. All default to doing nothing, so a private layer that sets none
of them gets a working desktop with stock behaviour.

```nix
  # Touchpad. Pure taste, so the framework picks neither direction:
  # unset means Sway's own default (natural scrolling off, tap off).
  castle.input.touchpad = {
    naturalScroll = true;   # content follows your fingers
    tapToClick = true;
  };

  # Blank the screen after N seconds idle. Unset means no idle handling
  # at all — no swayidle runs and the screen never blanks by itself.
  castle.display.idleBlankSeconds = 600;
```

- `castle.input.touchpad.naturalScroll` / `.tapToClick` — booleans,
  wired to Sway's `input type:touchpad`. Held strongly in both
  directions by different people, which is exactly why the framework
  declines to choose; `null` writes no `input` stanza at all.
- `castle.display.idleBlankSeconds` — seconds of inactivity before the
  outputs power off, via swayidle. **There is deliberately no default,
  and deliberately no screen lock.** Idle policy belongs to the
  attention-management work `docs/vision.md` describes (deep-focus
  mode, graduated interventions), which would have to renegotiate any
  policy set now — so the framework ships the mechanism with the policy
  slot empty. If you want a blanking screen, this is the option; if you
  want a lock, nothing here provides one yet.

Two more are **machine facts, not preferences** — a host module is
normally the right place for them, and `hosts/xps9370` already sets
both. Override in your own layer only if you know better than your host
module does:

- `castle.hardware.hasEthernet` — whether the chassis has a wired port.
  Declared in `nixosModules.base`, so a headless host can state it too.
  When `false`, the status bar drops its ethernet entry, which would
  otherwise show a permanent red fault for hardware that does not
  exist. Defaults `true`, because a desktop with an unplugged cable
  *should* show that fault.
- `castle.power.criticalPowerAction` — what upower does at critical
  battery. Unset leaves upower's own default (`HybridSleep`), which
  needs somewhere to write a hibernation image; `nixosModules.desktop`
  asserts against that combination on a machine with no swap rather
  than letting it fail at the moment the battery dies. On a
  zram-only host, `"PowerOff"` is the honest answer.

## The agent's state

`docs/architecture.md` and `agent/README.md` (the mechanism itself)
are the full spec; this section is the private-layer half of it — what
you actually add to make the "agent's model of you" slot real instead
of a placeholder.

`nixosModules.agent` installs the `castle` CLI but creates no state
anywhere — Principle 02 again: a rebuild never contains a person, so
the journal and resident model can't live in the derivation path. You
create the directory yourself, and it holds two things:

```
journal/            One file per record — requests, decisions,
                     results, questions, answers, and corrections (the
                     resident volunteering how the system is doing,
                     unprompted — docs/tasks/0010-correction-record.md).
                     Append-only in spirit: nothing is ever edited,
                     only added to.
resident-model.md    A derived, regenerable view over the journal, not
                     a second source of truth: one entry per fact,
                     each carrying its own provenance — either
                     elicited (question asked, answer given, when) or
                     volunteered (which correction it came from,
                     when). See agent/README.md for the entry formats
                     and worked (fake) examples. Starts empty, or
                     absent entirely, until the first elicited answer
                     or volunteered correction.
```

Point `castle.agent.stateDir` at that directory (an absolute path,
since it's wired straight into an environment variable — see
`resident.nix` above) and every `castle` invocation in your session
reads and writes there instead of a throwaway per-user default.

Keep it in git. That is where every property this directory is
supposed to have comes from: it survives a reinstall, moves to new
hardware, and survives a change of which model or harness holds the
worker seat, because a `git clone` puts it back exactly as it was
(`docs/architecture.md`'s "Where runtime state lives"). One commit per
turn is the audit trail.

**Which repository, though, is the question this section exists to
answer** — and there is one wrong answer, which is the obvious one.

### Not inside the repo you build the machine from

Do not put `state/` inside your private flake repo's tracked tree.
Earlier versions of this document told you to; they were wrong, and
here is the mechanism, because you should not have to take this on
trust.

Nix keeps everything it builds from, and everything it builds, in
`/nix/store`: one directory, owned by `root`, in which every file is
mode `r--r--r--`. There are no per-path permissions in the store and
no way to add any. If a file is in there, every account and every
process on that machine can read it. That is not a flaw — it is what
makes the store a shareable cache — but it means the store is the
wrong place for anything private, without exception.

`nixos-rebuild --flake /path/to/private#yourhost` — the documented way
to build your machine — has to hand Nix your flake before it can
evaluate it, and the way it does that is by **copying the flake's
directory into the store**. What it copies is the repository's tracked
git tree: everything you have committed, whether or not the build ever
looks at it. Your `flake.nix` and `resident.nix` are the point of the
exercise. A journal committed at `state/journal/` in the same
repository goes along with them.

So the old advice published every request, decision, question, answer
and correction you had ever filed to every account on the machine, on
every rebuild. Nothing about typing `nixos-rebuild` looks like it does
that, which is exactly why it needs saying out loud.

You can watch it happen, on any machine with Nix, in well under a
minute. `nix flake metadata` prints the store path Nix copied the
flake to, so there is no need to go looking for it:

```console
$ mkdir -p /tmp/demo/state/journal && cd /tmp/demo
$ echo '{ outputs = { self }: { }; }' > flake.nix
$ echo 'a private thing' > state/journal/rec.md
$ git init -q && git add -A && git commit -qm 'a fixture'
$ nix flake metadata /tmp/demo | grep Path
Path:           /nix/store/<hash>-source
$ cat /nix/store/<hash>-source/state/journal/rec.md
a private thing
$ ls -l /nix/store/<hash>-source/state/journal/rec.md
-r--r--r-- 1 root root 16 Jan  1  1970 /nix/store/<hash>-source/state/journal/rec.md
```

No build, no `nixos-rebuild`, no root — a single `nix eval` was
enough. Three things make it worse than a one-off slip:

- **Store paths are immutable.** Deleting the file from your repo
  later removes nothing that is already in the store.
- **They persist until garbage collection.** `nix-collect-garbage` is
  the only thing that removes them, and only once nothing still refers
  to them.
- **Each distinct content gets its own store path.** So you accumulate
  a version history of your own private records, in a place you had no
  reason to think held any.

Only the *tracked* tree is copied. An untracked or `.gitignore`d
`state/` is not published this way — but a journal you never commit is
a journal you lose at the next reinstall, which is the whole reason it
lives in git. (One exception worth knowing if you ever write flakerefs
by hand: the explicit `path:` scheme — `path:/path/to/private` rather
than the plain `/path/to/private` — copies the directory as it stands
on disk, untracked files included. Everything here assumes the plain
form, which is what `nixos-rebuild --flake` documents and what these
docs use throughout.)

If your reaction is "no one else uses this machine": possibly not
today, and possibly not this machine. Principle 01's premise is that
strangers adopt this framework on hardware this project cannot see — a
shared VPS with other tenants, a work laptop with a managed monitoring
agent, a desktop with a second account for someone else in the house.
And the store is readable by every *process*, not only every person,
which on a machine running an agent layer is a distinction worth
keeping in view.

### Recommended: a sibling git repository

Give `state/` its own repository, beside your config repo rather than
inside it:

```
~/private/               your flake repo — flake.nix, flake.lock, resident.nix
~/private-state/         a second, separate git repository
  journal/                 same contents, same schema, same append-only
                            discipline as before
  resident-model.md
```

```nix
castle.agent.stateDir = "/home/<your-login>/private-state";
```

Nothing is lost by splitting them. Every durability property above
comes from git, not from cohabiting with the flake, and a `git clone`
restores this repository exactly as it restores the config one. The
cost is real and small: two repositories to `git commit` in — and, per
"pushing stays manual" below, two to push.

This is the recommendation because its safety does not depend on
anything: no flake evaluates this directory, so no invocation of
anything can copy it into the store.

### Documented alternative: a git submodule at `state/`

If you would rather keep one clone and one everyday workflow, wire
`state/` in as a git **submodule** of your config repo:

```console
$ cd ~/private
$ git submodule add <url-of-your-state-repo> state
$ git commit -m 'state as a submodule'
```

`castle.agent.stateDir` then points where it always did
(`/home/<your-login>/private/state`), `git status` inside `state/`
behaves normally, and the store copy of your flake contains **no
`state/` directory at all** — verified against a real `nix eval`, not
assumed. The reason is that a plain path flakeref does not fetch
submodule content: Nix copies the `.gitmodules` file and the gitlink,
and stops there.

**And that is also the catch, so read this before choosing it.** The
exclusion holds *only* because of how the flake is referenced. A
flakeref carrying the `?submodules=1` query parameter fetches the
submodule's content and puts it straight back into the store copy:

```console
# do NOT do this — it puts state/ back in the store:
$ nixos-rebuild switch --flake "/path/to/private?submodules=1#host"
```

Nothing about that command looks alarming, and nothing warns you. If
you choose this layout, the rule is: **never add `?submodules=1` to
any flakeref naming this flake, anywhere** — not in a `nixos-rebuild`
invocation, not in a CI job, not in another flake's `inputs`. That is
a rule you have to keep remembering, months later, possibly on a
different machine. The sibling repository has no equivalent rule to
forget, which is why it is the recommendation and this is the
alternative.

### If you set nothing at all

Leaving `castle.agent.stateDir` unset is safe. The CLI falls back to
`$XDG_STATE_HOME/castle` (or `~/.local/state/castle`), which is
outside any flake and therefore never copied anywhere. It is a
reasonable per-user default and a poor durable one — nothing about it
survives a reinstall — so it is a fine place to try the tool and the
wrong place to keep two years of elicited preferences.

### `castle` will tell you if you get this wrong

`castle validate` and `castle digest` each check where the state
directory actually resolved, and print a `WARNING:` naming both it and
the repository if it is committed inside a repository that carries a
`flake.nix`. It asks three questions in order, and stops at the first
one that clears you:

1. **Is the state directory inside a git repository at all?** It walks
   upward looking for a `.git`, and stops at the first one it finds.
   If there is none, nothing evaluates the directory and nothing can
   copy it.
2. **Does that repository carry a `flake.nix`?** If not, it is not a
   flake, so nobody is going to evaluate it.
3. **Is anything under the state directory actually tracked there?**
   This is `git ls-files`, asking git rather than guessing: an
   untracked or `.gitignore`d directory is never copied into the
   store, so it is not the hazard. This is also why the check does not
   fire on the common case of a home directory that happens to be a
   dotfiles flake with `castle.agent.stateDir` left unset — your
   `~/.local/state/castle` is not in that repository's index.

A `state/` wired in as a submodule is cleared by question 3, not by
question 2: the walk goes past the submodule's own `.git` to the flake
repository above it and asks that repository the tracked-ness question,
where a submodule shows up as a single reference to another repository
rather than as content. That distinction is why the check can still
catch a half-finished migration — a `git init` inside `state/` without
the `git rm` that takes it out of the config repo's index leaves your
journal committed in the flake repo, and still published, even though
`state/` now looks like a repository of its own.

**If `git` is not installed, question 3 cannot be asked**, and the
check warns on questions 1 and 2 alone rather than staying quiet. The
message says so explicitly and names untracked content as the case it
could not rule out — so if you see that wording and your `state/` is
ignored or uncommitted, the warning does not apply to you. Warning
with a caveat is the deliberate direction to fail in: reading an extra
paragraph is cheap, and a published journal is not.

It is advisory **for `validate` and `digest`**: their exit codes do not
change and neither refuses to run. The copy is made by `nixos-rebuild`,
not by `castle`, so refusing there would prevent nothing and would
withhold the two commands most likely to bring you the news.
Deliberately not wired into `castle dispatch`, which a timer runs once
a minute.

There is now one place where the same finding is a **refusal** rather
than a warning, and the difference is who would be making the copy.
With `castle.agent.apply.evaluateFlake` on, `castle apply` evaluates
your flake itself — so here the check is not reporting on somebody
else's rebuild, it is deciding whether to publish your journal. It
declines, quotes this finding in the record, and points at "Migrating
state out of the flake" below. The change is still made; only the check
is skipped.

One case it does **not** catch: a repository whose `flake.nix` lives in
a subdirectory, evaluated as `git+file:///your/repo?dir=nix`. That
publishes the whole tracked tree exactly as a root-level flake does,
but question 2 finds no `flake.nix` at the repository root and calls it
safe. It is not a layout this document describes, and closing it would
mean searching your whole repository for flakes on every `validate` —
which would then fire on a sibling state repository that happens to
contain an unrelated flake. If you keep your flake in a subdirectory,
this check will not help you; the rest of this section still does.

### Two things worth repeating

Both are from `docs/architecture.md`, and both hold for whichever
repository ends up holding `state/`:

- Committing to it is a standing, made-then-reported authority — the
  diff is the audit trail, not a thing to approve in advance.
- **Pushing stays manual.** Encrypted secrets exist now
  (`docs/tasks/0031-secrets-tooling.md`, and "Secrets" below), so the
  *mechanism* a push credential would live in is no longer missing —
  but nothing has designed what that credential is, what it may push
  to, or what an unattended push is allowed to do without you. Until
  something does, don't wire a cron job or a service to `git push` your
  state repository.

## Migrating state out of the flake

If you already followed the old advice, here is the move. It is four
steps and three caveats, and the caveats matter more than the steps.

**Copy first, delete last, and never in the other order.** Your
journal is the least reproducible thing on the machine. Every sequence
below is written so that nothing is removed until the new copy exists
somewhere else and you have looked at it. `git rm -r state` deletes
the working copy off disk as well as from the index; run it before the
content is safely elsewhere and the only surviving copy of your
decision history is inside git history, which is precisely the
artifact you least want to be relying on.

1. **Copy the content into its new home, and check that it arrived.**

   Both layouts start the same way. Note the `/.` on the source and
   the explicit `mkdir -p`: `cp -r a b` means "copy *into* b" when `b`
   already exists and "copy *as* b" when it does not, so the plain
   form silently produces `~/private-state/state/journal/…` for anyone
   who created the directory first — a shape that commits cleanly,
   passes a careless check, and leaves `castle` creating a second,
   empty `journal/` beside your real one. `cp -r <src>/. <dst>/` means
   the same thing either way.

   ```console
   $ mkdir -p ~/private-state
   $ cp -r ~/private/state/. ~/private-state/
   $ cd ~/private-state && git init && git add -A && git commit -m 'journal'
   ```

   Then check it arrived, with a comparison rather than a count you
   have to eyeball:

   ```console
   $ before=$(ls ~/private/state/journal | wc -l)
   $ after=$(ls ~/private-state/journal | wc -l)
   $ [ "$before" = "$after" ] && echo "OK: $after records" || echo "MISMATCH: $before -> $after"
   ```

   `MISMATCH` — or an `ls:` error naming a directory that does not
   exist — means the copy did not land where you meant it to, most
   likely one level too deep. **Stop there.** Nothing has been removed
   yet, so fix the copy and re-run this check before going on; that is
   the entire reason this step comes first.

   For the **submodule** layout, do the above and then give the new
   repository somewhere to be cloned from, because `git submodule add`
   clones *from* it rather than into it:

   ```console
   $ cd ~/private-state
   $ git remote add origin <url> && git push -u origin HEAD   # if it has a remote
   ```

   If you want the sibling repository to carry the journal's *history*
   rather than a snapshot, `git filter-repo --subdirectory-filter
   state` on a fresh clone of the config repo is the thorough route.
   It is optional: the journal itself is append-only, so a snapshot
   loses no records, only the commit-by-commit account of when each
   arrived.

2. **Only now remove the old directory.** In the config repo, with the
   copy confirmed in step 1:

   ```console
   $ cd ~/private && git rm -r state && git commit -m 'state moved out of the flake'
   ```

   For the submodule layout, that removal is what makes room for the
   reference, so it comes first and the `add` clones your content back
   into place:

   ```console
   $ git -c protocol.file.allow=always submodule add <url> state
   $ git commit -m 'state as a submodule'
   $ ls state/journal | wc -l    # the same count as step 1
   ```

   The `protocol.file.allow=always` is needed whenever `<url>` is a
   local path — `~/private-state`, with no remote — because git has
   refused the `file` transport for submodules since 2.38 (the
   CVE-2022-39253 mitigation) and fails with `fatal: transport 'file'
   not allowed`. A local path is the ordinary case here: this project
   has no credential story yet, so "pushing stays manual" and the
   remote in the step above is optional. Do not delete the flag as
   noise; without it this command does not run at all.

   If you hit that error before adding the flag, nothing is lost: your
   content is already committed in `~/private-state` from step 1, and
   that is what copy-first buys you. Add the flag and re-run.

3. **Repoint `castle.agent.stateDir`** at the new location and
   rebuild. Run `castle validate`; the warning above should be gone.
   (For the submodule layout the path does not change — the directory
   is in the same place, holding the same files, by a different
   mechanism.)
4. **Run `nix-collect-garbage`** once the move is committed and
   rebuilt, or wait for the host's normal GC schedule.

And now the parts that are less satisfying than they should be:

- **Old store copies persist until garbage collection actually
  runs.** Removing `state/` from the repository removes nothing
  already in `/nix/store` — store paths are immutable by design.
  `nix-collect-garbage` deletes them only once nothing still refers to
  them, and an older system generation that points at a build
  containing the old source path keeps it alive. Removing stale
  generations (`nix-collect-garbage -d`, or
  `nix-env --delete-generations`) may be needed first, which is a
  decision about your rollback history and therefore yours.
- **Your config repo's git history still contains the journal.** A
  `git rm` and a commit do not erase the blobs; every earlier commit's
  tree still holds them. That is not a store exposure — evaluation
  publishes the tracked tree at a revision, not the history — but it
  becomes one the moment that repository is pushed anywhere, cloned by
  anyone, or made public. Rewriting history (`git filter-repo` or
  equivalent) on a repository that has not been shared is the standard
  remedy, and the same reasoning Principle 02's fourth consequence
  gives for a leak into a public repo applies here. Whether it is
  worth doing is your call; this document is not going to pretend
  there is a tidy answer.
- **If you never committed `state/`, nothing was ever exposed.** Only
  the tracked tree is copied. A `state/` that was untracked or
  `.gitignore`d the whole time never reached the store, and moving it
  now is tidying rather than remediation. Check before assuming either
  way — `git log --oneline -- state` in your config repo answers it.

## Automatic dispatch (optional, off by default)

Out of the box, a filed request sits in the journal until you run
`castle work <id>` yourself. `castle.agent.dispatch.enable = true`
changes that: four `systemd.user` units — a path unit watching your
journal directory, a `oneshot` service running `castle dispatch`, a
one-minute backstop timer, and a second `oneshot` that marks the
dispatch boundary when your session starts — notice new work, run the
configured worker tenant against one eligible errand at a time, and
route the results (`docs/tasks/0021-auto-dispatch.md`).

**This is an authority decision, which is why it is yours and not the
framework's.** Turning it on means a model tenant can start work, and
spend money, with nobody watching at the moment it happens. What the
mechanism promises in exchange:

- **One automatic attempt per request, ever.** A request with any
  result at all — succeeded, failed, timed out, interrupted — is
  permanently ineligible. That bound is structural, not a counter that
  could be misconfigured or reset. Retrying is `castle work <id>`,
  typed by you.
- **Nothing before you opted in.** A watermark record is written the
  moment your first dispatch-enabled session starts, before you have a
  desktop to file anything from; requests filed before that instant are
  never auto-started, are named in the record by id, and the record
  says so in plain English. Anything the watermark excluded still shows
  up in `castle-modal --mode status` with the `castle work <id>` that
  runs it by hand.

  **This promise assumes your journal is already on the machine when
  that session starts, so put it there first.** Either have the private
  checkout in place before your first login with dispatch enabled, or
  leave `dispatch.enable = false` until the first restore has finished
  and rebuild afterwards. If the journal instead arrives *during* a
  dispatch-enabled session, the first sweep to notice it writes the
  watermark — a backstop, and a real one, but not the same guarantee:
  a restore that copies files one at a time can be caught partway
  through, and the boundary then freezes around whatever had landed.
  History arriving after it is not excluded, and a request whose result
  file has not been copied yet looks unfinished and can be picked up.
  Nothing is lost either way — every attempt is one attempt, recorded —
  but an errand you considered closed months ago could get a model call
  spent on it. Getting the checkout in place first costs nothing and
  removes the whole question.
- **Nothing is hidden.** Every turn leaves a `claim` record when it
  starts and a `result` carrying an `outcome` when it ends, including
  when it ends badly — and `castle-modal --mode status` shows you
  which errands are running, which are waiting on you, and which
  failed and need retrying.
- **The worker still proposes and never deploys.** Automatic
  invocation changes nothing about that: no `nixos-rebuild`, no `git
  commit`, no applying a diff. You review and apply, exactly as
  before.

**Clone this repo onto the machine before you turn dispatch on.** The
sweep will not create `castle.agent.stateDir` for you: it checks
whether that directory exists and, if it does not, says so and does
nothing until the next timer tick. That refusal is deliberate. A sweep
that created the directory would both break the clone you were about
to do into it and — worse — write its watermark declaring that nothing
predates automatic dispatch, minutes before your real journal arrived.
Every request in that restored history would then look new.

Two settings to get right when you enable it. `castle.agent.stateDir`
is required (evaluation fails without it). And
`castle.agent.repo.private` must name the repository you actually want
worked on. Without it, every dispatched errand ends in a `failed`
result saying there is nowhere to work — honest, but each one has
spent that errand's single automatic attempt, and configuring the path
afterwards does not give any of them back. `castle work <id>` by hand
still runs them.

**Your `nixosConfigurations` attribute should match your
`networking.hostName`.** This has always been the shape every template
here uses, and since `docs/tasks/0024-config-target.md` a worker
follows it: to find which host module applies to the machine it is
running on, it reads `/proc/sys/kernel/hostname` and looks for the
`nixosConfigurations` entry of that name in your `flake.nix`, then
follows its imports. Read from the running kernel rather than declared
as a third option that could silently drift from the truth. If your
attribute is named something else the worker says what it looked for
and asks you, rather than guessing at a near match — so a mismatch
costs you a question, not the errand.

**The worker never evaluates your flake, and this is deliberate.** It
reads the files. Evaluating a local flake copies its whole tracked
tree into `/nix/store`, which is world-readable. Reading a file copies
nothing. The cost of that choice is that the worker learns what each
file *says* rather than which definition Nix would actually pick, so
where the two could differ — an `mkForce`, a numbered `mkOverride`, a
computed value — it asks you instead of guessing. (Your
`nixos-rebuild` still evaluates the flake, and still publishes that
tree — which is why "The agent's state" above tells you to keep the
journal out of it. This rule is the other half of the same defence,
and it holds whatever layout you chose.)

**One host per journal.** If you sync your state repository between
machines, turn dispatch on for only one of them. The lease that keeps
a single worker per errand is machine-local — it lives in the runtime
directory, not in the journal — so two dispatch-enabled hosts sharing
one journal would each start the same request, and each write
`interrupted` results about the other's live turns. Nothing reconciles
two dispatchers over a synced journal yet, and this task does not
pretend to; it is work for whatever design gives the journal a sync
story.

The same instruction covers `castle.agent.apply.enable`, for a sharper
reason: two enabled hosts would make the same approved change in two
different checkouts, and only one of them is the one you meant. Turn
applying on for the same single host you turned dispatch on for, or for
none.

The units run only while you are logged in: this repo deliberately
does **not** enable `loginctl` lingering, since a mechanism whose only
visible output today is a desktop notification has nothing useful to
do while nobody is at the keyboard. Running dispatch between logins is
a further authority decision, and it is yours to make separately.

## What happens to a change you approve (optional, off by default)

`castle.agent.apply.enable = true` (`docs/tasks/0026-apply-validate.md`)
is the second opt-in on this page, and it is a larger one than the
first. Automatic dispatch lets a tenant start work and spend money.
This lets Castle change **this repository**.

Here is exactly what appears, and what does not.

**What appears.** For each change you approve, and once for each: the
files that change are edited here, and one commit is made on whatever
branch you have checked out. Its author and committer are
`Castle applier <applier@castle.invalid>` — the seat, never a person,
at an address RFC 2606 guarantees can never be real — so `git log`
answers "who made this" in the vocabulary the journal uses. Its message
names the errand, the change, your decision, the proposal and the
patch's digest, and says in as many words that nothing was activated.
No file paths, no prose from the tenant, nothing that could be your
data. To undo one: `git revert <sha>`, which is what the record says
too.

**What does not appear.** No push, anywhere, ever — not built, not
configurable, not left a seam for. No `nixos-rebuild`, no `switch`, no
new generation, no change to the machine you are using. Switching to
the new configuration stays yours to do, by hand. Nothing writes a
checkout of the Castle Turing framework itself: a change proposed
against it is refused by name, your approval is still recorded, and
carrying it upstream is yours if you want it.

**What it refuses, and what each refusal means.** The refusals are the
part worth reading, because they are what makes this safe to leave on:

- Your approval was granted before this existed. Permanently inert, and
  deliberately: what you were told at the moment you approved is the
  scope of what you approved, and no later wording reaches backwards.
  Approve the change again if you still want it.
- The proposal, or the exact copy of the change kept beside it, is not
  what it was when you approved. Nothing here rewrites a record, so
  there is no version to prefer and it refuses rather than guessing.
- No exact copy was kept at all. The rendered diff in the record is for
  reading, not for applying.
- The change no longer fits: the files moved since it was proposed. It
  is applied exactly or not at all — nothing merges, fuzzes or
  recounts, because the result of that would be a change you never saw.
- You have uncommitted edits to the same files. It will not write over
  them. The record says how many paths and what kind of edit, never
  which files — that record is durable and your file names are yours.
  Uncommitted work *elsewhere* in the repository does not stop it, and
  neither does an ignored file: a check that refused forever on a
  perfectly ordinary layout would be worse than no check.

**Your git hooks do not run on its commits.** Not `pre-commit`, not
`post-commit`, not any of them — they are disabled for exactly the
commands Castle runs, and they still run on every commit you make
yourself. This is not tidiness: the commit message records the digest
of the exact bytes you approved, and a formatting hook that rewrites
them would leave that record asserting a digest for content it no
longer describes.

**The commit is built, not taken from your working files.** Castle
assembles it from your repository's history plus the exact bytes you
approved, in a scratch area of its own, and only then moves your branch
to it. Two things follow that are worth knowing.

If you (or your editor, or a formatter on save) change one of those
files while this is happening, **your edit cannot get into the commit**
— the commit was already assembled from what you approved. And your
edit is not thrown away either: Castle notices the file is no longer as
it found it, leaves it exactly as you left it, and says so in the
record. Your change sits on top of the approved commit as ordinary
uncommitted work, and `git status` shows it.

If your repository runs a `.gitattributes` content filter, that filter
also cannot reach the commit. That is usually what you want — you
approved specific bytes, and those are what get committed. It does mean
git may report the file as modified afterwards, because your filter
would store it in a different form than the one you were shown. Castle
does not pick between the two: it commits what you approved, tells you
which files git will keep flagging, and leaves the choice to you.

Nothing signs these commits, whatever your `commit.gpgsign` says. The
author on them is `Castle applier`, not you, and signing them with your
key would claim you wrote them. Afterwards it checks what actually landed — one
commit, parented where it started, nothing left uncommitted — and if
the repository is not in that state it says so and names **no** commit
sha, rather than printing a `git revert` for a commit it cannot vouch
for.

**When something goes half-right.** There is no longer a state where
the change is in your files but not committed — the commit is built
before anything moves, so it either happened or it did not. What can
still be left half-done is the mild opposite: the commit is there and
your working files have not caught up to it yet. The record says so and
names the commit, because the change is durable and only the files on
disk are behind. **Nothing is rolled back** on its own, ever: rewinding
your history is a larger authority than adding one commit you asked
for.

**And if it could not act at all** — no usable checkout, git not
answering — the change is untouched and the status surface says
`could not be applied — castle apply <id> to try again`, naming the
command. It will not try again by itself: one automatic attempt per
approval, whatever happened. Fix whatever was in the way and run that.

**The check, if you turn it on.** With
`castle.agent.apply.evaluateFlake = true`, one `nix build --no-link` of
this machine's own `system.build.toplevel` runs afterwards,
unprivileged, with your `flake.lock` explicitly not written or updated.
It says the configuration evaluates and builds. It does not say the
change did what it claimed — nothing anywhere declares that — it does
not say your secrets will decrypt, and it does not say the
configuration will activate. If it fails, the change stays where it is
and the record says the check failed; nothing repairs it, re-proposes
it or asks again. The remedy is a fresh `castle ask`.

One thing it cannot check at all, and says so rather than guessing: if
this repository's own path contains a `#` or a `?`, Nix reads those as
flakeref syntax rather than as part of the path, so there is no way to
name the repository to it. Your change is still made and committed;
only the check is skipped, and the record names the character. There is
no escaping rule for them — moving the checkout is the only fix.

**One host, and one attempt.** Turn this on for at most one machine per
journal, for the reason "Automatic dispatch" above gives. And each
approval is applied automatically at most once, whatever the outcome —
if you want another attempt after fixing whatever was in the way, run
it yourself:

    castle apply <the id of the decision that approved it>

That hand path is deliberately unbounded, exactly as `castle work <id>`
is for an errand.

## The installer image (optional, per host)

`castle-turing.nixosModules.installer` (`docs/tasks/0006-installer-image.md`)
is a bootable NixOS ISO that's immediately SSH-reachable — no fetching a
key by hand, no reading an IP off a router's admin page — closing
`docs/tasks/0003-findings.md` finding #3. It needs no new private file
or format: it reuses the same `castle.admin` values you already supply,
the same way `nixosModules.host-xps9370` does.

**Split your private values across two files first.** An installer needs
an admin identity — a key to accept, an account to seed — but has no use
for `castle.person`, and the options for that are defined by
`nixosModules.home`, which an installer does not import. Passing it a
file containing `castle.person` fails evaluation with an unhelpful
"option does not exist" error. So keep `castle.admin` in its own file:

```nix
# admin.nix — who may log into and operate this machine
{ ... }:
{
  castle.admin = {
    username = "<your-login>";
    sshKeys = [ "<your-openssh-public-key>" ];
  };
}

# resident.nix — everything an installed system needs
{ config, ... }:
{
  imports = [ ./admin.nix ];
  castle.person = { ... };
  # Not in admin.nix, on purpose — see below.
  castle.admin.hashedPasswordFile =
    config.sops.secrets."admin-password-hash".path;
}
```

**Keep `castle.admin.hashedPasswordFile` out of `admin.nix`**, for the
same reason `castle.person` is out of it and one more. The installer
image imports `nixosModules.base` but not `nixosModules.secrets`, so a
line reading `config.sops.secrets."…"` in a file the installer imports
fails evaluation with an "option does not exist" error, exactly as
`castle.person` does. And it would have nothing to point at anyway: the
installer is running before there is a partitioned disk to have planted
an age key onto. An installer needs a key to accept and an account name;
it never needs a password, and `nixosModules.installer` asserts nothing
about one.

Then add a second `nixosConfiguration` to your private flake, importing
`admin.nix` rather than `resident.nix`:

```nix
nixosConfigurations.xps9370-installer = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    castle-turing.nixosModules.installer
    ./admin.nix
  ];
};
```

Build it and write the result to a USB stick:

```sh
nix build .#nixosConfigurations.xps9370-installer.config.system.build.isoImage
# result/iso/*.iso -> dd to a USB stick
```

Boot the target machine from it (see `hosts/xps9370/README.md`) and its
own console tells you what to do next: if it's on Ethernet, DHCP just
works and the console shows you're reachable at
`ssh root@castle-installer.local` (or whatever `networking.hostName`
you set — override it per host in the block above if you'll ever have
more than one installer image live on the same LAN segment at once)
within a few seconds, no interaction needed. If it isn't, the console
notices and walks you straight into `nmtui` to join Wi-Fi — there's no
step to remember, the machine asks.

**Wi-Fi credentials are not baked into the image**, and that's a
deliberate design choice, not a gap: a Wi-Fi PSK is private-layer data,
and baking one into a NetworkManager connection profile at ISO-build
time would mean writing it in plaintext into a private-layer Nix file —
exactly the "private repo is access control, not encryption" problem
the Secrets section below closes for the *installed* system. Rather than
invent a way around that, this mechanism accepts one guided, one-time
Wi-Fi join at the console as a better trade than a plaintext credential
anywhere — and makes sure that step is unmissable (a persistent
on-console prompt, not a manual `nmtui` ritual you have to already know)
rather than apologizing for it.

**This did not change when sops-nix landed, and the distinction is
worth being precise about.** `docs/tasks/0031-secrets-tooling.md` gives
the *installed* system a declarative Wi-Fi profile — see "Secrets"
below — so its own first boot needs nobody at the keyboard. The
installer *image* is a different machine at a different moment: there
is no disk to have planted a key onto yet, because `nixos-anywhere`
has not partitioned one. So the image still joins Wi-Fi the way it
always has, one guided console join per installer boot, and that is
where it stays until something changes about how the image itself
carries an identity.

## Secrets

`castle-turing.nixosModules.secrets` (`docs/tasks/0031-secrets-tooling.md`)
is how a credential gets onto your machine without ever being committed
anywhere in plaintext. It binds [sops-nix](https://github.com/Mic92/sops-nix)
and adds the two-option slot this framework owes you: which encrypted
file is yours, and where the key that opens it lives.

Three artifacts, and the whole design is in which repo each one is
allowed to touch:

| Artifact | Lives in | Why there |
|---|---|---|
| `secrets.yaml` — your credentials, **encrypted** | your private repo, committed | it travels with a `git clone`, survives a wipe, and shows up in diffs per changed key rather than as one opaque blob |
| `.sops.yaml` — which recipients may decrypt it | your private repo, committed | it is a list of public keys; publishing it costs nothing and losing it costs a re-derivation |
| `key.txt` — the age private key | **neither repo**, ever | it is the one thing that turns ciphertext back into a credential; it lives on the machine and in your password manager, and nowhere else |

The encrypted file *is* copied into the world-readable Nix store every
time your flake is evaluated, and that is intended rather than a leak —
it is ciphertext, and putting ciphertext where the activation can read
it is how sops-nix works. Contrast "The agent's state" above, where the
same store copy is a real hazard: a journal is plaintext. The rule was
never "keep your files out of the store" — it is "keep *plaintext* out
of the store," and everything below is how you get a credential onto
the machine without breaking it.

You will want `age` and `sops` for the steps below. If they are not on
your workstation already, `nix shell nixpkgs#age nixpkgs#sops` is
enough — nothing here needs them installed permanently.

### Enrolling a machine (once per machine)

Do this **before** you install, in this order. Step 2 is the one people
skip and regret.

1. **Generate the machine's age key.**

   ```console
   $ age-keygen -o key.txt
   Public key: age1...
   ```

   That file is the entire re-enrollment artifact for this machine.
   **Put its contents in your password manager now**, labeled with the
   machine's hostname, before you do anything else with it. It is not
   in any repo and it never will be, so a copy you did not make is a
   copy that does not exist.

2. **Record two recipients, not one.** `age-keygen -y key.txt` prints
   the machine key's public recipient. Put it, *and a personal age key
   of your own that lives somewhere else entirely*, in a `.sops.yaml`
   in your private repo:

   ```yaml
   creation_rules:
     - path_regex: secrets\.yaml$
       key_groups:
         - age:
             - age1...   # this machine
             - age1...   # you, from your password manager / another machine
   ```

   A file encrypted to two independent recipients survives the loss of
   either one. This is what makes every recovery story below finite:
   lose the machine and its key together, and your own key still opens
   the file; lose your own key, and the machine's copy still does.
   Encrypt to one recipient and you have built a single point of
   failure whose failure mode is "the credential is gone."

3. **Create the encrypted file.** `sops secrets.yaml` opens your editor
   and applies `.sops.yaml`'s recipients when you save. Put the secret
   under a plain key name:

   ```yaml
   wifi-psk: "<your-network-password>"
   ```

   What lands on disk is ciphertext with a readable key name beside it
   — the reason this project chose sops over agenix. `sops secrets.yaml`
   again is how you edit it later; never edit the ciphertext by hand.

4. **Commit `secrets.yaml` and `.sops.yaml`.** Never `key.txt`. Add it
   to your `.gitignore` while you are thinking about it.

5. **Point the slot at it**, in `resident.nix`:

   ```nix
   castle.secrets.sopsFile = ./secrets.yaml;
   ```

6. **Stage the key for the install.** `nixos-anywhere --extra-files
   <dir>` copies `<dir>`'s contents onto the target's root after the
   disk is partitioned and mounted and before `nixos-install` runs, so
   the key is in place before the machine's very first activation. It
   arrives owned by `root`, carrying whatever permissions it had here —
   which is why the modes below are load-bearing rather than tidy:

   ```sh
   # A named directory rather than `mktemp -d`, because the install
   # command that consumes it lives in another document and, most
   # likely, another shell: a temp path held only in a variable is gone
   # by the time you get there.
   root=~/castle-key-staging
   rm -rf "$root"
   install -d -m 755 "$root" "$root/var" "$root/var/lib"
   install -d -m 700 "$root/var/lib/sops-nix"
   install -m 600 key.txt "$root/var/lib/sops-nix/key.txt"
   ```

   `/var/lib/sops-nix/key.txt` is `castle.secrets.ageKeyFile`'s default.
   If you changed that option, change this path with it — they have to
   agree or activation fails with a missing-key error.

Then add `--extra-files "$root"` to the `nixos-anywhere` invocation in
`hosts/xps9370/README.md`'s install step — **with the guard that step
puts in front of it**, not on its own:

```sh
ls -l "${root:?stage the age key first}/var/lib/sops-nix/key.txt" &&
nix run github:nix-community/nixos-anywhere -- ... --extra-files "$root" ...
```

That guard is not ceremony. `nixos-anywhere` tests `--extra-files`'s
argument for emptiness and silently skips the copy if it is empty, so
an unset `$root` — a new terminal, a `cd`, a lost variable — installs a
machine with no key on it and reports success. On a chassis with no
Ethernet port, what you get is a laptop that boots, cannot decrypt its
Wi-Fi PSK, joins no network, and cannot be reached at all. Refusing to
start is much cheaper than that.

Delete `$root` when the install is done.

### Using the secret: a declarative Wi-Fi profile

This is the payoff, and the reason the Wi-Fi PSK was the first
credential this project put behind the mechanism: with it declared,
a freshly installed machine joins your network on its own first boot,
with nobody at the keyboard.

It is entirely your configuration — no Castle Turing option wraps it.
Two upstream mechanisms meet: sops-nix renders the secret into a file
under `/run`, and nixpkgs's own
`networking.networkmanager.ensureProfiles` reads that file when it
writes the connection profile. The same reason `modules/home` expects
you to reach for `wayland.windowManager.sway.config.keybindings`
directly: where a real upstream option already exists, a wrapper would
only add a name to learn.

```nix
{ config, ... }:
{
  castle.secrets.sopsFile = ./secrets.yaml;

  # The key "wifi-psk" out of that file. Decrypted at activation to
  # /run/secrets/wifi-psk, root-owned, mode 0400.
  sops.secrets."wifi-psk" = { };

  # ensureProfiles.environmentFiles wants KEY=value shape, and the bare
  # secret above is just the value. A template composes the two without
  # the plaintext ever existing anywhere in between:
  # config.sops.placeholder.* is a build-time stand-in that
  # sops-install-secrets substitutes at activation, so what is in the
  # Nix store is the placeholder, not your PSK.
  sops.templates."wifi.env".content = ''
    HOME_WIFI_PASSWORD=${config.sops.placeholder."wifi-psk"}
  '';

  networking.networkmanager.ensureProfiles = {
    environmentFiles = [ config.sops.templates."wifi.env".path ];
    profiles.home-wifi = {
      connection = {
        id = "home-wifi";
        type = "wifi";
      };
      wifi = {
        mode = "infrastructure";
        ssid = "<your-network-name>";
      };
      wifi-security = {
        key-mgmt = "wpa-psk";
        # Literally this string, not an interpolation: NetworkManager's
        # generated profile is run through envsubst at activation, with
        # the environment file above supplying the value.
        psk = "$HOME_WIFI_PASSWORD";
      };
      ipv4.method = "auto";
      ipv6.method = "auto";
    };
  };
}
```

The rendered profile is written to
`/run/NetworkManager/system-connections/` — a tmpfs, gone at every
reboot and never on disk. Your SSID *is* in your private repo in
plaintext here, which is a deliberate line: a network name is not a
credential, and the framework repo never sees either one.

### Using the secret: your login password

`castle.admin.hashedPasswordFile` (`docs/tasks/0032-password-hash.md`)
is the second thing this mechanism carries, and the one with the most
at stake — get it wrong and the machine's *next* fresh install has no
console login. It needs one thing the Wi-Fi PSK does not:
`neededForUsers`.

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
  # because neededForUsers moves it there.
  castle.admin.hashedPasswordFile =
    config.sops.secrets."admin-password-hash".path;
}
```

The value that goes into `secrets.yaml` under that key is what
`mkpasswd -m sha-512` prints, exactly as before this option existed —
nothing changes about how the hash is produced, only about where it
lives before it reaches the machine:

```yaml
wifi-psk: "<your-network-password>"
admin-password-hash: "<the output of mkpasswd -m sha-512>"
```

Two things about this are worth knowing before you rely on it, and
both are consequences of `users.mutableUsers` being left at its NixOS
default of `true`:

- **This seeds an account; it does not rotate a password.** Changing
  the secret and rebuilding does nothing to an account that already
  exists — see the option's own entry under `resident.nix` above. So
  adopting this on a machine you already run is *safe by
  construction*: it cannot change the password you are currently
  logged in with. What it changes is what the next fresh install gets.
- **Which means you should verify the mechanism, not the password.**
  After rebuilding, `sudo cat
  /run/secrets-for-users/admin-password-hash` and check it matches what
  you put in `secrets.yaml`. If it is missing or wrong, fix it now —
  you are not locked out while you do, because nothing about your
  working login depends on that file yet. That is the entire migration
  check, and it is the honest one; "I can still log in" proves nothing
  either way.

If you are moving from the older `castle.admin.initialHashedPassword`,
remove that line in the same change. Leaving it fails the build the
moment you bump your `flake.lock` past
`docs/tasks/0032-password-hash.md`, with a message naming the fix —
which is deliberate, and much better than a machine that builds fine
and locks itself on the next wipe. **Do not paste your old hash string
into the new option**: it takes a path, and NixOS would go looking for
a file by that name, not find one, and leave the next freshly created
account locked.

Removing the option and rebuilding does not erase the old hash: it
only stops the *next* generation from embedding one.
`initialHashedPassword` put that string in the world-readable store by
two routes (`docs/tasks/0032-password-hash.md`'s "Why" names both), and
every earlier generation that still boots is a GC root keeping its own
copy of both — as world-readable as everything else under
`/nix/store`. This project's automatic GC (`modules/base`'s
`nix.gc`) only deletes generations older than 30 days, so the string
you just removed from `resident.nix` can legitimately still be sitting
on disk a month from now. If that exposure window matters to you more
than the rollback it buys you, delete the old generations yourself
(`nix-env --delete-generations old --profile /nix/var/nix/profiles/system`
as root, or `nix-collect-garbage -d` to also drop generations from
other profiles) and collect garbage before you consider the migration
done — the same tradeoff between rollback history and store exposure
that the agent-state move above asks you to make explicitly, not one
this project can make for you.

### When the key is missing or wrong

Both failures are loud, which is exactly why a Wi-Fi PSK went first
rather than a password hash. The symptom is **no network** — obvious
within seconds, and recoverable by plugging in Ethernet or joining by
hand with `nmtui`, the way you did before any of this existed.

Since `docs/tasks/0032-password-hash.md` the same key also opens your
login password, and that case reads differently enough to state
separately — different ordering, different symptom, different urgency:

- **It fails earlier.** `neededForUsers` puts this secret's decryption
  ahead of account creation (sops-nix sets
  `users.deps = [ "setupSecretsForUsers" ]`), so by the time NixOS
  writes `/etc/shadow` the answer is already yes or no.
- **The symptom is a locked account, not a missing file.**
  `update-users-groups.pl` warns that the password file does not exist
  and carries on — this is not fatal, and nothing else about the
  account is affected: the uid, home directory, groups, and SSH
  `authorizedKeys` are all set up normally. What you get is a shadow
  entry of `!`: no password login for that account.
- **Only a *fresh* account is affected.** An account that already
  exists keeps whatever password it already had; a failed decryption
  cannot take a working login away from you. This bites a new install
  or a wipe.
- **You are not actually locked out**, and this is worth knowing before
  it happens rather than after. Key-based SSH does not consult
  `/etc/shadow` at all, and `nixosModules.base` installs your
  `castle.admin.sshKeys` into both your account and `root`'s. So
  `ssh root@<host>` still works. Run `passwd <your-login>` there and
  you have a real password back immediately and permanently — `passwd`
  is exactly what `users.mutableUsers = true` protects from any future
  rebuild. Then diagnose the secret at your leisure: `ls -l
  /var/lib/sops-nix/key.txt`, `ls -l
  /run/secrets-for-users/admin-password-hash`, `journalctl -b | grep -i
  sops`. Fixing it changes nothing about the account you just
  recovered; it matters for the *next* account creation.

The two causes below apply to both secrets identically.

- **Key file absent.** `sops-install-secrets` fails at activation,
  naming the path it could not read. That is on the console during
  `nixos-install` or `nixos-rebuild`, and in `journalctl -b` afterwards.
  At *install* time it does not stop anything: `nixos-enter` runs
  activation as `"$system/activate" || true`, so the line goes by and
  the install still reports success. On the machine's own **first
  boot** the failure is loud in the way you want, because nothing
  downstream runs: no template is rendered, and
  `NetworkManager-ensure-profiles.service` then fails too (its
  `EnvironmentFile` points at a file that does not exist), which
  `systemctl --failed` shows you.
- **Key present but wrong** — not one of the recipients the file was
  actually encrypted for. The same downstream silence, but the
  activation log names a decryption failure rather than a missing file.
  That difference is the whole diagnostic: it tells you whether you
  planted no key or the wrong one.

There is no dedicated Castle Turing check for this, deliberately. The
platform already reports it in two places a resident will be looking
anyway, and a bespoke surface for a loud failure is mechanism nobody
asked for.

### Re-enrollment: what a wipe costs you

Three cases, in increasing order of annoyance.

- **Reinstalling the same machine.** Nothing to re-encrypt. You still
  have `key.txt` in your password manager; stage it exactly as in step
  6 above and the new install reads the same `secrets.yaml` your
  private repo already carries. This is the ordinary case, and the
  reason this design plants a key file rather than deriving one from
  the machine's SSH host key — a wipe gives the machine a new host key,
  which would leave every existing secret unreadable.
- **Losing the machine's key** (a dead disk, a password-manager entry
  never saved). Decrypt `secrets.yaml` with your *personal* key from
  step 2, generate a fresh machine key, swap the recipient in
  `.sops.yaml`, and `sops updatekeys secrets.yaml` re-encrypts to it.
  Annoying, entirely survivable, and only because you recorded two
  recipients.
- **Losing both.** The credentials are gone; rotate them at their
  sources. Nothing in any repo can help, by construction — that is the
  same property that makes committing the ciphertext safe.

### The honest limitation

The age key sits in plaintext at `/var/lib/sops-nix/key.txt`, on a disk
this project does not yet encrypt (`docs/backlog/disk-encryption.md`).
This mechanism protects against disclosure of your private repo and
against store exposure — both are ciphertext. It protects against
**nothing** if someone has the laptop and can read its disk. That is
not a new weakness introduced here; it is the one that backlog entry
already describes, now true of one more file.

`docs/tasks/0032-password-hash.md` sharpens it rather than changing it:
that one key now also opens your login password. There is a circularity
worth naming plainly — the login password is what a stolen laptop's
console asks for, and the key that seeds it is on the same unencrypted
disk. Someone with the machine does not need to defeat the password;
they can read the disk directly. Nothing about moving the hash out of
the Nix store claims otherwise: that move closes disclosure to *other
accounts and processes on a running machine*, which is a real boundary
and not this one. Closing this one is the backlog entry's job.

## `flake.lock`

Commit it. The pin of `castle-turing` records precisely which public
mechanism your private configuration was built against; updating it is
the deliberate act of adopting new framework behavior, and the diff of
the pin is part of your audit trail.

## Slots that exist but are still empty

These are part of the interface by design; the framework will consume
them from the private layer as the corresponding features land. Reserve
the space, do not invent formats yet:

- **Stated priorities** — the document the agent triages against (see
  `docs/vision.md`). Format not yet specified.
- **Authority taxonomy** — which decision categories are silent,
  made-then-reported, or queued for approval. Format not yet specified.

Two entries are no longer on this list. The agent's model of you left
it with `docs/tasks/0008-agent-layer-skeleton.md` — see "The agent's
state" above. **Secrets** left it with
`docs/tasks/0031-secrets-tooling.md`: sops-nix is in the flake,
`castle.secrets.*` is a real slot, and "Secrets" above is the whole
interface. The rule that entry carried still holds and always will —
**no plaintext credentials anywhere**, the private repo included, since
a private repo is access control and not encryption. What changed is
that there is now somewhere else for them to go.

## Test

Hand this document to someone who has never seen your private repo. If
they cannot write their own from scratch this weekend, file the gap as a
bug here.
