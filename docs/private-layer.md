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
- **The agent's model of you** — accumulated context and the decision
  journal. Shape arrives with the agent tooling.

## Test

Hand this document to someone who has never seen your private repo. If
they cannot write their own from scratch this weekend, file the gap as a
bug here.
