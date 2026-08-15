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
  socket as the documented control surface a future agent layer will
  drive), foot, fonts, XDG portals, PipeWire, Firefox, and greetd +
  tuigreet for login. Deliberately no auto-login — see the module's own
  comments for why. Asserts `castle.admin.initialHashedPassword` is set,
  since a login prompt with no password behind it is a lockout, not
  security. Optional: skip it on a headless host.
- `nixosModules.dev` — this project's own development tools (Emacs, git,
  gh, ripgrep, fd, claude-code). No private data, no assertions.
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

## The installer image (optional, per host)

`castle-turing.nixosModules.installer` (`docs/tasks/0006-installer-image.md`)
is a bootable NixOS ISO that's immediately SSH-reachable — no console
login, no manual Wi-Fi join, no fetching a key by hand — closing
`docs/tasks/0003-findings.md` finding #3. It needs no new private file
or format: it reuses the same `castle.admin` values `resident.nix`
already supplies, the same way `nixosModules.host-xps9370` does. Add a
second `nixosConfiguration` to your private flake:

```nix
nixosConfigurations.xps9370-installer = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    castle-turing.nixosModules.installer
    ./resident.nix
  ];
};
```

Build it and write the result to a USB stick:

```sh
nix build .#nixosConfigurations.xps9370-installer.config.system.build.isoImage
# result/iso/*.iso -> dd to a USB stick
```

Boot the target machine from it over Ethernet (see
`hosts/xps9370/README.md`) and it comes up reachable at
`ssh root@castle-installer.local` (or whatever `networking.hostName` you
set — override it per host in the block above if you'll ever have more
than one installer image live on the same LAN segment at once) using
the same key `resident.nix` already grants.

**Wi-Fi is not provisioned by this mechanism**, and that is a deliberate
scope limit, not an oversight: a Wi-Fi PSK is private-layer data, and
baking one into a NetworkManager connection profile at ISO-build time
would mean writing it in plaintext into a private-layer Nix file —
exactly the "private repo is access control, not encryption" problem
the Secrets slot below exists to eventually close. Until this repo has
a secrets mechanism (sops-nix or equivalent — not yet in scope), wire
the target machine to Ethernet for installs, or join Wi-Fi by hand with
`nmtui` on the installer image, same as the stock installer requires.

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
- **The agent's model of you** — accumulated context and the decision
  journal. Shape arrives with the agent tooling.

## Test

Hand this document to someone who has never seen your private repo. If
they cannot write their own from scratch this weekend, file the gap as a
bug here.
