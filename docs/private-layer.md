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
          castle-turing.nixosModules.dev # optional: Emacs, git, gh, ripgrep, fd, claude-code
          castle-turing.nixosModules.agent # optional: the agent-layer CLI + state dir
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
  module's own comments for why. Asserts `castle.admin.initialHashedPassword`
  is set, since a login prompt with no password behind it is a lockout,
  not security. Optional: skip it on a headless host.
- `nixosModules.dev` — this project's own development tools (Emacs, git,
  gh, ripgrep, fd, claude-code). No private data, no assertions.
- `nixosModules.agent` — the agent layer's CLI (`castle`, plus
  `castle-modal` and the default `castle-worker-claude` worker tenant)
  and three options: `castle.agent.stateDir` (wired into
  `CASTLE_STATE_DIR`), `castle.agent.worker.command` (wired into
  `CASTLE_WORKER_COMMAND` — which tenant holds the worker seat), and
  `castle.agent.notify.command` (wired into `CASTLE_NOTIFY_COMMAND` —
  what the router's `notify` channel actually runs). See "The agent's
  state" below and `agent/README.md`. No assertions: an unset
  `stateDir`/`notify.command` just falls back to a per-user or built-in
  default rather than failing evaluation, since the agent layer is
  optional the way `desktop`/`dev` are; `worker.command` always has a
  runnable default (a headless `claude -p`) since the worker seat needs
  *something* to default to.
- `nixosModules.installer` — the agentic installer image: bootable NixOS
  media, SSH-reachable with zero console interaction, using the same
  `castle.admin` values as everything else here. See "The installer
  image" below.

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
    # other host with an interactive console). Generate with
    # `mkpasswd -m sha-512`; never a plaintext password.
    initialHashedPassword = "<your-password-hash>";
  };

  # Optional — only needed if you use nixosModules.home.
  castle.person = {
    gitUserName = "<your-name>";
    gitUserEmail = "<your-email>";
  };

  # Optional — only meaningful if you use nixosModules.agent. Points the
  # `castle` CLI at this private repo's own state/ directory rather than
  # a per-user default under $XDG_STATE_HOME — see "The agent's state"
  # below.
  castle.agent.stateDir = "/home/<your-login>/private/state";

  # Optional — override the worker tenant (default: a headless
  # `claude -p`, see agent/castle-worker-claude) or the router's notify
  # command (default: notify-send on $PATH). Most residents on
  # nixosModules.desktop need neither.
  # castle.agent.worker.command = "/path/to/your/own/worker/tenant";
  # castle.agent.notify.command = "";  # e.g. to no-op on a headless host

  # Optional — taste, only meaningful if you use nixosModules.desktop.
  # hosts/xps9370 already supplies hardware-derived scale/cursor
  # defaults for that chassis; override any of the four here to your
  # own preference regardless of host — see "The display-preference
  # slot" below.
  castle.display = {
    # scale = 1.5;
    # cursorTheme = "Bibata-Modern-Ice";  # or your own cursor package
    # cursorSize = 32;
    # terminalFontSize = 11;
  };
}
```

- `castle.admin.username` — login name of the human administrator.
- `castle.admin.sshKeys` — OpenSSH public key strings granted admin
  access (both to your user and to root, for remote rebuilds). Public
  keys are not secrets, but they identify a person — that is why they
  live here.
- `castle.admin.initialHashedPassword` — hashed (never plaintext)
  password seeded at first account creation only; later `passwd` changes
  are never overwritten by a rebuild. Only required if you import
  `nixosModules.desktop`, which asserts it is set — see that module for
  why (`docs/tasks/0003-findings.md` finding #1, the first-boot console
  lockout). Whatever you seed here — even a deliberately weak,
  known-to-you-only default — `nixosModules.base` nags an interactive
  shell to run `passwd` until the hash actually changes, and stops the
  moment it does. It never forces the change (no PAM-level expiry): that
  risks a tuigreet/greetd lockout of its own.
- `castle.person.gitUserName` / `castle.person.gitUserEmail` — your git
  commit identity, wired into home-manager's `programs.git`. Only
  required if you import `nixosModules.home`, which asserts both are
  set.
- `castle.agent.stateDir` — where the `castle` CLI's journal (and the
  resident model) live. Optional even if you import
  `nixosModules.agent`: unset, the CLI falls back to
  `$XDG_STATE_HOME/castle`, a reasonable per-user default but not the
  durable, git-tracked location the architecture calls for. See "The
  agent's state" below.
- `castle.agent.worker.command` — which tenant holds the worker seat
  (docs/architecture.md's Proposal 03). Defaults to a headless
  `claude -p` (`agent/castle-worker-claude`); override only if you're
  running a different tenant. Whatever holds this seat, it never
  deploys — see `agent/README.md`.
- `castle.agent.notify.command` — what the router's `notify` channel
  actually runs (docs/architecture.md). Defaults to plain `notify-send`
  on `$PATH`, which is real once `nixosModules.desktop` is imported
  (it installs mako + libnotify); set to `""` on a headless host to
  no-op the attempt outright.
- `castle.display.{scale,cursorTheme,cursorSize,terminalFontSize}` —
  taste, only meaningful with `nixosModules.desktop`. See "The
  display-preference slot" below.

## The display-preference slot

`modules/desktop` declares four options — `castle.display.scale`,
`.cursorTheme`, `.cursorSize`, `.terminalFontSize` — all `nullOr`,
defaulting to `null` ("framework default": leave that setting alone
entirely). Three layers can resolve a value, in ascending priority:
this module's `null` default; a host module's hardware-derived default
via `lib.mkDefault` (`hosts/xps9370` sets `scale`, `cursorTheme`, and
`cursorSize` this way, since a panel's physical DPI is a machine fact —
Principle 01 consequence 2, "hosts are modules"); and your own
`resident.nix`, which overrides outright and always wins. `nix flake
check` proves all three layers resolve correctly via an assertion in
this repo's `nixosConfigurations.example` (`flake.nix`) — read it if
you want to see the exact resolution the layering guarantees.

Two of the four are simple values (`cursorSize`, `terminalFontSize` are
plain integers; `scale` is a float — Sway's own output-scale unit).
`cursorTheme` is a *name*, and it only means something paired with a
package that ships a theme by that name: `modules/desktop` installs
`pkgs.bibata-cursors` so the option has something real to point at out
of the box (`hosts/xps9370` defaults to its `"Bibata-Modern-Classic"`
theme) — if you want a different cursor theme, add its package to your
own private-layer config and set `cursorTheme` to one of *its* theme
names. Note the dependency this creates: `cursorSize` only takes effect
once `cursorTheme` is non-null anywhere in the stack (an unset theme
leaves the whole `home.pointerCursor` slot untouched, by design — see
`modules/desktop`'s option description) — on `hosts/xps9370` that's
already satisfied by the host's own default, but if you override
`cursorTheme` to `null` explicitly to opt back out of a managed cursor
theme, `cursorSize` goes inert with it.

## The agent's state

`docs/architecture.md` and `agent/README.md` (the mechanism itself)
are the full spec; this section is the private-layer half of it — what
you actually add to make the "agent's model of you" slot real instead
of a placeholder.

`nixosModules.agent` installs the `castle` CLI but creates no state
anywhere — Principle 02 again: a rebuild never contains a person, so
the journal and resident model can't live in the derivation path. They
live in this repo, your private one, under a `state/` directory you
create:

```
state/
  journal/            One file per record — requests, decisions,
                       results, questions, answers. Append-only in
                       spirit: nothing is ever edited, only added to.
  resident-model.md    Accumulated facts about you, one entry per
                       fact, each carrying its own provenance (question
                       asked, answer given, when). See agent/README.md
                       for the entry format and a worked (fake)
                       example. Starts empty, or absent entirely, until
                       the first elicited answer.
```

Point `castle.agent.stateDir` at this directory (an absolute path,
since it's wired straight into an environment variable — see
`resident.nix` above) and every `castle` invocation in your session
reads and writes there instead of a throwaway per-user default.
Because it's an ordinary directory in a git repo you already commit
and control, it survives a reinstall, a move to new hardware, and a
change of which model or harness holds the worker seat — which is the
entire point (`docs/architecture.md`'s "Where runtime state lives").

Two things `docs/architecture.md` is explicit about and worth
repeating here: committing to this directory is a standing,
made-then-reported authority — the diff is the audit trail, not a
thing to approve in advance — and **pushing stays manual** until
secrets tooling gives this repo a credential story for doing it
unattended. Don't wire a cron job or a service to `git push` this
repo's state until that lands.

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
    initialHashedPassword = "<your-password-hash>";
  };
}

# resident.nix — everything an installed system needs
{ ... }:
{
  imports = [ ./admin.nix ];
  castle.person = { ... };
}
```

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
the Secrets slot below exists to eventually close. Rather than invent a
way around that, this mechanism accepts one guided, one-time Wi-Fi join
at the console as a better trade than a plaintext credential anywhere —
and makes sure that step is unmissable (a persistent on-console prompt,
not a manual `nmtui` ritual you have to already know) rather than
apologizing for it. Once sops-nix (or equivalent) lands, a private layer
will be able to supply a real declarative Wi-Fi profile and skip even
that; until then, this is the honest unattended-by-default story.

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
- **Secrets** — encrypted via sops-nix, once that tooling enters the
  public flake. Until then: **no plaintext credentials anywhere**, the
  private repo included. A private repo is access control, not
  encryption.

The agent's model of you is no longer on this list — its shape landed
with `docs/tasks/0008-agent-layer-skeleton.md`. See "The agent's
state" above.

## Test

Hand this document to someone who has never seen your private repo. If
they cannot write their own from scratch this weekend, file the gap as a
bug here.
