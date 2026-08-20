# Task 0031 — Secrets tooling: sops-nix and the Wi-Fi PSK

**Before starting:** read `CLAUDE.md` in full; `docs/backlog/secrets-tooling.md`
(this task promotes it — delete it in the same commit, per that
directory's own README); `docs/backlog/declarative-wifi.md` in full —
this task only *partially* resolves that entry, so it is **edited in
place, not deleted**, and the edit is part of this task's own file list;
`docs/principles/01-open-by-construction.md` and
`02-the-resident-owns-the-configuration.md`; `docs/private-layer.md` in
full, not only the sections being rewritten — the surrounding sections'
tone and cross-references need matching, the same discipline
`docs/tasks/0030-state-outside-the-flake.md` asked of itself; `modules/base/default.nix`'s
`castle.admin.initialHashedPassword` option (~lines 36–64), its
`users.users.${cfg.username}.initialHashedPassword` consumer (~line 170),
and the password-reminder systemd unit that embeds the same value via
`lib.escapeShellArg` (~lines 208–240); `modules/installer.nix`'s header
comment and its Wi-Fi-not-baked-in reasoning; `hosts/xps9370/README.md`
in full, especially the install command (~line 143) and the two Wi-Fi
paragraphs (~109–115, ~192–202); `hosts/xps9370/default.nix`'s
`networking.networkmanager.enable` block and its comment ("Secrets
tooling may take this over later"); `test/vm-install/README.md`,
`run.sh`, `installer.nix`, and `vm-test-system.nix` in full; and
`docs/tasks/0030-state-outside-the-flake.md`'s "Why" section for the
store-exposure mechanism this task's motivation depends on — do not
re-derive it, cite it.

Work on branch `task/0031-secrets-tooling`, cut from `origin/main` at
`e157e85`. Scope every diff and review against `origin/main` (`git
fetch` first, per `CLAUDE.md`'s multi-agent conventions).

**Goal.** Bring `sops-nix` into the flake as the project's secrets
mechanism; give the private layer a documented, public-mechanism way to
declare an encrypted secrets file and the age key that decrypts it;
close the enrollment and re-enrollment story end to end (generate a key,
plant it at install with `nixos-anywhere --extra-files`, recover it
after a wipe); and land the first real secret — the Wi-Fi PSK — wired
through NetworkManager, so a from-scratch install of the *installed*
system can join a known network with nobody at the keyboard.

## Why

`docs/backlog/secrets-tooling.md` names the deadline this task is
already late for: Principle 01 consequence 1 says secret tooling enters
the repo *before the first credential exists*, and `docs/tasks/0030-state-outside-the-flake.md`'s
own non-goals section already recorded that the deadline has been
missed — the `resident.nix` template in `docs/private-layer.md` has
shipped a `castle.admin.initialHashedPassword` example since that
document's first version, and every Wi-Fi PSK and API token since has
been kept out of both repos only by hand: typed at a console, or (per
`modules/installer.nix`'s own header comment) deliberately deferred to
a guided `nmtui` join because there is nowhere else for it to live yet.
That is not a design flaw in what exists — it is the correct call under
the constraint that no secrets mechanism exists — but the constraint is
what this task removes.

Two things this task depends on and does not re-derive: `docs/tasks/0030`'s
proof that evaluating a path flakeref copies a flake's tracked git tree
into the world-readable Nix store, and Principle 01's public-mechanism /
private-configuration split. Both matter here for a specific reason —
an sops-nix **encrypted** file being copied into the store on every
evaluation is not the same hazard 0030 fixed. 0030's finding was about
*plaintext* (a resident's journal) landing somewhere world-readable by
accident. An sops-encrypted secrets file is ciphertext by construction,
and copying ciphertext into a shared, world-readable store is the
*intended* distribution mechanism for it — sops-nix's own module
(`sops.defaultSopsFile`, `nixosModules.sops`, verified below) is built
around exactly this, and its own `validateSopsFiles` option (default
`true`) requires the file to be readable at evaluation time for
precisely that reason. What must never be copied anywhere evaluation
can reach is the **decryption key** — the age key file — and that is
what stays out of both repos in this design, planted only at install
time, onto the target machine's own disk.

## The declarative-wifi challenge, answered

`docs/backlog/declarative-wifi.md` raises a fair challenge that this
brief has to answer rather than assume past: nixpkgs ships
`networking.networkmanager.ensureProfiles.environmentFiles`, which
references a PSK by an out-of-store file path — "public mechanism (the
option), private configuration (whatever keeps that file secret)."
That's Principle 01's split without sops-nix at all, and the entry is
right to ask whether declarative Wi-Fi was ever actually blocked on
secrets tooling.

Verified against this flake's pinned nixpkgs
(`0e251e24a4f24e036a084b6b4b2d2491af4167f4`,
`nixos/modules/services/networking/networkmanager.nix`), not assumed:

- `ensureProfiles.profiles.<name>` declares a NetworkManager connection
  profile as structured Nix, including a `wifi-security.psk` field that
  may hold a literal `$VARNAME` placeholder (line ~444 of that file, the
  option's own worked example does exactly this).
- `ensureProfiles.environmentFiles` (`types.listOf types.path`, example
  `[ "/run/secrets/network-manager.env" ]`) is wired as `serviceConfig.EnvironmentFile`
  on a real systemd unit, `NetworkManager-ensure-profiles.service`
  (~line 661). That unit's `script` runs `envsubst` over the generated
  profile file *before* handing it to NetworkManager, substituting
  `$VARNAME` from whatever the environment file supplied. The rendered,
  secret-bearing profile is written to `/run/NetworkManager/system-connections/`
  — a tmpfs, never the store.

So the entry's claim holds exactly as stated: this is Principle 01's
split, and it needs no `sops-nix`-specific code to *use*. What it does
need, and what the entry's own prose stops short of naming, is
something to put the real file at that out-of-store path in the first
place, keep it there across a reinstall, and do all of that without a
human typing it in at a console. That is the entire value this task
adds on top of `environmentFiles` — not a redesign of the mechanism the
entry already found, but the missing other half of it:

- The **encrypted** secret lives in the private repo — versioned,
  travels with the resident, survives a `git clone` onto a new machine,
  reviewable in a diff the same way every other private-layer change is
  (`docs/private-layer.md`'s whole premise).
- `nixos-anywhere --extra-files` (verified below, against the
  project's *own* pinned nixos-anywhere, not assumed) plants the one
  thing that must never be versioned — the age key — onto the target's
  disk during install, before the first activation.
- `sops-nix`'s own systemd unit (`sops-install-secrets` — the module
  is examined in full below) decrypts at every activation, writing the
  plaintext to a `/run`-scoped, non-store path — precisely the shape
  `environmentFiles` wants, produced automatically rather than by hand.

Without that, "public mechanism (the option), private configuration
(whatever keeps that file secret)" still leaves "whatever keeps that
file secret" undefined — and the entry's own account of why task 0006
rejected baking a PSK into the installer image is that a human typing
`nmtui` once was the *accepted trade-off against exactly that gap*, not
a preference. This task closes the gap the entry correctly identified
as still open.

**What this task does not resolve**, restated from the entry's own
still-open questions, because none of them are settled by landing
sops-nix: multiple networks (home, office, a phone hotspot) — the
worked example below declares one; whether there is a sane fallback
when no known network is in range; and whether the installer *image*
and the *installed* system end up sharing one mechanism. On the last
point: this task changes nothing about `modules/installer.nix`. The
installer image still has no disk to plant a key onto until after
`nixos-anywhere` has partitioned one, so its own guided-`nmtui`-join
stays exactly as documented. What changes is the **installed** system's
own first boot — see "Re-reading `hosts/xps9370/README.md`'s finding
#1" below.

## The design

### The three decisions already made, restated with their reasoning

Not reopened here — recorded so the design below reads as their
consequence, not as independent choices:

1. **sops-nix**, not agenix — per-key YAML/JSON granularity means a
   diff shows which key changed while values stay encrypted, matching
   this project's plain-text-everywhere posture.
2. **The Wi-Fi PSK is the first secret**, not the password hash — the
   hash is more security-relevant but is needed at account creation
   on first boot, where a wrong or missing secret bricks the login
   path; a missing or wrong PSK just means no network, which is
   loud and recoverable. See Non-goals for the full argument.
3. **The decryption key is a plain age key file**, planted at install
   by `nixos-anywhere --extra-files` — not derived from the SSH host
   key (a reinstalled machine gets a new host key, which is exactly
   the re-enrollment puzzle this design has to avoid), and not a
   hardware token (right end state, wrong cost today — see Considered
   and rejected).

### 1. The flake input and the module

`flake.nix` currently carries a placeholder comment (lines 23–24):
"Secrets tooling (agenix or sops-nix) MUST be added here before the
first credential exists anywhere in the system." That comment is
replaced with a real input:

```nix
sops-nix = {
  url = "github:Mic92/sops-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Verified against the pinned rev at spec time (`sops-nix`'s own
`flake.nix`): it exports `nixosModules.sops` (`default = self.nixosModules.sops;`),
which is the whole upstream mechanism — `sops.secrets.*`,
`sops.templates.*`, `sops.age.keyFile`, `sops.defaultSopsFile`, and the
activation-time decryption machinery. `flake.nix`'s `nixosModules` gains:

```nix
secrets = {
  imports = [
    sops-nix.nixosModules.sops
    ./modules/secrets.nix
  ];
};
```

`modules/secrets.nix` (new, single-file, matching the existing
`modules/installer.nix` / `modules/disk-layout.nix` convention rather
than a directory module) declares the public-mechanism slot:

```nix
{ config, lib, ... }:
let
  cfg = config.castle.secrets;
in
{
  options.castle.secrets = {
    sopsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        The private layer's encrypted secrets file. Wired to
        `sops.defaultSopsFile`. A Nix *path*, not a string, deliberately:
        copying this file into the Nix store at evaluation time is the
        intended distribution mechanism for it, because it is
        ciphertext — contrast docs/private-layer.md's warning about
        *plaintext* state under "The agent's state", which this is not.
        Supplied by the private layer; see docs/private-layer.md.
      '';
    };
    ageKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/sops-nix/key.txt";
      description = ''
        Where the age private key that decrypts sopsFile lives on this
        machine — never in either repo. Wired to `sops.age.keyFile`.
        The default matches the path this project's own enrollment
        steps plant it at with `nixos-anywhere --extra-files`; override
        only with a specific reason to use a different path.
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.sopsFile != null) { sops.defaultSopsFile = cfg.sopsFile; })
    {
      sops.age.keyFile = cfg.ageKeyFile;
      # Added during implementation — see "Amended during implementation",
      # item 1. Not in this brief as written.
      sops.age.sshKeyPaths = lib.mkDefault [ ];
    }
  ];
}
```

Two things worth stating about why this is thin. `sops.age.keyFile` is
set unconditionally (not gated on `cfg.sopsFile != null`) because it
costs nothing to declare a value nothing yet consumes, and it means the
enrollment path (§2) always targets the same, documented location
regardless of whether a resident has declared any secrets yet.
`sops.defaultSopsFile` is gated, because it is `lib.types.path` with
**no default of its own** upstream (verified: `modules/sops/default.nix`'s
`defaultSopsFile` option has no `default =` at all) — leaving it unset
when `cfg.sopsFile == null` is what keeps a resident who imports
`nixosModules.secrets` but declares no secrets yet from being asked for
a file that doesn't exist. Nothing in `sops-nix` demands
`defaultSopsFile` be set unless something actually reads it (a
`sops.secrets.<name>` with no per-secret `sopsFile` override), and
`cfg.secrets` defaults to `{}`.

### 2. Enrollment (first install)

Steps a resident follows once, adding to (not replacing)
`hosts/xps9370/README.md`'s existing install flow — this section is
what that file's file-by-file entry below expands into prose:

1. **Generate a machine age key**, on a workstation, before the
   install: `age-keygen -o key.txt`. This file — the raw output of that
   command — is the whole re-enrollment artifact. **Save its contents
   in a password manager**, labeled with the machine's hostname, before
   doing anything else with it.
2. **Record two age recipients, not one.** `age-keygen -y key.txt`
   prints the machine key's public recipient. Add it, *and* the
   resident's own separate personal age (or existing GPG-via-age)
   recipient, to a `.sops.yaml` creation-rules file in the private
   repo. This is the belt-and-suspenders step the design leans on: a
   secrets file encrypted for two independent recipients survives the
   loss of either one. Losing the machine key (a failed disk, a
   password-manager entry never saved) is recoverable by decrypting
   from the resident's own key and re-encrypting for a freshly
   generated machine key; losing *only* the machine's disk is the
   ordinary reinstall case in step 5 below and needs no re-encryption
   at all.
3. **Create and encrypt the secrets file**: `sops secrets.yaml` opens
   an editor with `.sops.yaml`'s recipients already applied on save.
   Add the Wi-Fi PSK under a plain key name, e.g. `wifi-psk: "..."`.
4. **Commit `secrets.yaml` (ciphertext) and `.sops.yaml` to the private
   repo.** Never commit `key.txt`.
5. **Point `castle.secrets.sopsFile` at it** in the private flake
   (`resident.nix` or a sibling file — see the `resident.nix` template
   addition in the file-by-file list below):
   `castle.secrets.sopsFile = ./secrets.yaml;`
6. **Before running `nixos-anywhere`, stage the key for `--extra-files`.**
   `--extra-files <path>` (verified against this project's own pinned
   `nixos-anywhere`, `docs/howtos/extra-files.md` and `docs/howtos/secrets.md`
   in its source tree — see "Verified against nixos-anywhere" below)
   recursively copies `<path>`'s contents onto the target's root,
   root-owned, preserving permissions:

   ```sh
   root=$(mktemp -d)
   install -d -m700 "$root/var/lib/sops-nix"
   cp key.txt "$root/var/lib/sops-nix/key.txt"
   chmod 600 "$root/var/lib/sops-nix/key.txt"
   ```

7. **Add `--extra-files "$root"` to the `nixos-anywhere` invocation**
   in `hosts/xps9370/README.md`'s existing install command (currently
   lines 143–149), immediately before `--phases disko,install`. This is
   the same flag and the same pattern that tool's own documentation
   uses for bootstrapping sops-nix and agenix specifically — not a
   novel use.

### Verified against nixos-anywhere

Read directly out of this task's pinned `nixos-anywhere` source
(`ad8fa24e11eef167fd72d49fafefa3f840312d71`), not assumed from its
prose docs alone — and **re-read during implementation** out of what
this flake actually resolves, which is `pkgs.nixos-anywhere` at version
`1.13.0` from the pinned nixpkgs (a release tarball, so a version
rather than a rev is what identifies it here). Every claim below held
against that source, unchanged:

- `--extra-files`'s copy (`src/nixos-anywhere.sh`, the `Copying extra
  files` step) runs via `tar -C "$extraFiles" ... | runSsh "tar -C /mnt
  -xf- --no-same-owner"` — **after disko has partitioned and mounted
  the target at `/mnt`, and before the `nixos-install` step that
  follows it in the same function.** So the key is on disk, at the path
  the installed system's own `sops.age.keyFile` will look for it, by
  the time the very first activation (which `nixos-install` triggers)
  runs — there is no window where activation could run without it.
- Ownership: `tar --no-same-owner` means everything lands owned by
  `root`, matching `--phases disko,install`'s target account and this
  design's own default (`sops-install-secrets`'s activation runs as
  root). Permissions from the local staging directory *are* preserved
  — hence `chmod 600` on `key.txt` in step 6 above, matching the exact
  precedent in `nixos-anywhere`'s own SSH-host-key bootstrapping
  example.
- This flag is independent of `--flake` vs. `--store-paths` — it is not
  coupled to how the system closure itself is specified, which matters
  for the verification plan below, since `test/vm-install/run.sh`
  drives `nixos-anywhere` with `--store-paths`, not `--flake`.

### 3. Consuming the secret: the Wi-Fi PSK through NetworkManager

Entirely private-layer configuration, using two upstream mechanisms
directly — `castle.secrets.*` from §1, and nixpkgs's own
`ensureProfiles`. No new Castle Turing module or option wraps this;
per `docs/private-layer.md`'s own precedent for
`wayland.windowManager.sway.config.keybindings`, a resident is expected
to reach for a real upstream option directly when one already exists
and a wrapper would add nothing. The worked example added to
`docs/private-layer.md`:

```nix
{ config, ... }:
{
  castle.secrets.sopsFile = ./secrets.yaml;

  sops.secrets."wifi-psk" = { };  # key "wifi-psk" in sopsFile, yaml format

  # ensureProfiles.environmentFiles wants KEY=value shape; a template
  # composes the bare secret value into that shape without ever writing
  # it to disk in between (config.sops.placeholder never touches disk —
  # it is a build-time indirection sops-install-secrets resolves at
  # activation).
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
        psk = "$HOME_WIFI_PASSWORD";
      };
      ipv4.method = "auto";
      ipv6.method = "auto";
    };
  };
}
```

`sops.templates.<name>` (verified in `sops-nix`'s own
`modules/sops/templates/default.nix`) renders to
`/run/secrets/rendered/<name>`, mode `0400`, owned by root by default —
never the store, never git. This is the idiomatic sops-nix pattern for
"a secret shaped the way one specific consumer wants it," not a
workaround; `sops.secrets."wifi-psk"` alone would place the *bare* PSK
value at `/run/secrets/wifi-psk`, which is not the `KEY=value` shape
`EnvironmentFile=` parses, hence the template.

### Re-reading `hosts/xps9370/README.md`'s finding #1

That file's existing step 6 states, correctly as of today, that the
*installed* system's first independent boot needs a human at the
keyboard running `nmtui` once, because "there is no password on the
admin account and no declarative Wi-Fi profile either." This task
closes the second half of that sentence for a resident who follows §2
and §3 above: with a `castle.secrets.sopsFile` and the `ensureProfiles`
wiring declared, the installed system's first boot decrypts the PSK at
activation (which, per "Verified against nixos-anywhere" above, has
already run once during the `nixos-install` step itself) and joins
`home-wifi` with nobody at the keyboard. The file-by-file list below
updates that paragraph accordingly. What it does **not** close: the
*installer image*'s own console still has no disk to plant a key onto
before disko runs, so `modules/installer.nix`'s guided-`nmtui` path for
reaching the installer over Wi-Fi is untouched by this task.

### What the resident sees when the key is absent or wrong

Traced through the verified mechanism above, not asserted:

- **Key file absent.** `sops-install-secrets` (run either as an
  activation script or a `systemd` unit depending on this nixpkgs
  pin's `useSystemdActivation` default — both paths verified in
  `modules/sops/default.nix`) fails with a nonzero exit naming the
  missing `sops.age.keyFile` path; that failure is visible in the
  activation log (`journalctl -b`, or the console during
  `nixos-rebuild`/`nixos-install` itself). `sops.templates."wifi.env"`
  is never rendered. `networking.networkmanager.ensureProfiles`'s own
  systemd unit, `NetworkManager-ensure-profiles.service`, has
  `EnvironmentFile` pointing at a file that does not exist and is
  **not** prefixed with `-` (the systemd syntax for "ignore if
  missing") — that unit fails to start too, visible under `systemctl
  --failed`. Net effect: no declarative profile is ever written, so
  NetworkManager has nothing to join. **No network** is the resident's
  actual symptom — obvious, and the recorded rationale for choosing the
  PSK as the first secret in the first place.
- **Key present but wrong** (doesn't match either `.sops.yaml`
  recipient the file was actually encrypted for). Same downstream
  consequence — no rendered template, no profile, no network — but the
  activation log names a *different*, more specific failure from
  `sops`/`age` itself (a decrypt error, not a missing-file error),
  which is what actually lets a resident tell "wrong key" from
  "no key" apart when diagnosing.
- Nothing in this task adds a bespoke diagnostic for this beyond what
  `systemctl --failed` and the activation log already surface — see
  Considered and rejected for why a dedicated check was weighed and
  set aside.

### The honest limitation: an unencrypted disk

`docs/backlog/disk-encryption.md` already names this laptop's disk as
unencrypted and names encryption as the thing that would make the
seeded login password "a real boundary instead of a speed bump." The
age key this task plants inherits exactly that limitation: it sits in
plaintext at `/var/lib/sops-nix/key.txt` on that same unencrypted disk.
This design protects the two things it was built to protect —
disclosure of the private repo (the committed file is ciphertext) and
store exposure (the store copy is also ciphertext, by design, per
"Why" above) — and protects **nothing** against someone with physical
possession of the laptop and a way to read its disk. That is not a new
weakness this task introduces; it is the same weakness
`disk-encryption.md` already documents, now also true of one more file.
Closing it is that entry's job, not this one's.

### What "an obviously-fake example" means here, and why nothing
permanent is committed

The scope for this task calls for an example that makes the shape
visible without contents. What ships is a worked **prose** example —
the `secrets.yaml`/`sops.templates`/`ensureProfiles` block above, in
`docs/private-layer.md` — plus `nixosConfigurations.example` importing
`nixosModules.secrets` with `castle.secrets.sopsFile` left at its
default (`null`) and zero `sops.secrets` declared, proving the
*module's own options* evaluate cleanly against a dummy resident (one
new assertion, `config.sops.age.keyFile == "/var/lib/sops-nix/key.txt"`,
alongside the existing `castle.display` assertion block).

What does **not** ship is a permanent, working example age keypair and
a matching sops-encrypted file committed to this repo. That was
considered and is argued against in Considered and rejected — the
short version: `sops.secrets.<name>` with the honest, unweakened
default `validateSopsFiles = true` requires a real, decryptable
ciphertext file to exist on disk at *evaluation* time (verified:
`modules/sops/default.nix`'s `sopsFileHash` calls `builtins.hashFile`
directly, gated only on that option), so proving the full
`ensureProfiles`/`sops.secrets` pattern in `nix flake check` would
require either committing a real, permanently-working keypair (a
standing secret-scanner and confused-future-reader hazard, in a repo
whose own `CLAUDE.md` treats "never write personal data" as a hard
rule) or turning that safety check off for the demo, which proves
nothing while looking like it proves something. The pattern is instead
proven for real, with a throwaway keypair and a throwaway ciphertext
file, neither ever committed, inside the `test/vm-install/` harness —
see Verification plan. That is a real, argued design choice, not an
oversight; flagged for the human's review rather than assumed.

## Considered and rejected

- **agenix instead of sops-nix.** Rejected on the record already
  (`docs/backlog/secrets-tooling.md`): agenix's per-file opaque blobs
  lose the per-key diff legibility sops-nix's YAML/JSON granularity
  gives, and that legibility is the specific thing this project's
  plain-text-everywhere posture was built to preserve. Restated here
  rather than re-argued.
- **Deriving the decryption key from the machine's SSH host key**
  (`sops.age.sshKeyPaths`, which sops-nix supports natively via
  `ssh-to-age` and which `services.openssh.enable` wires in as a
  fallback automatically if no `age.keyFile` is set). Rejected: a
  reinstalled machine gets a fresh host key by construction, which
  means a wipe destroys the ability to read every secret that existed
  before it — precisely the "re-enrollment puzzle" `docs/backlog/secrets-tooling.md`
  names as a requirement to avoid. ~~This task's module sets
  `sops.age.keyFile` unconditionally, which means sops-nix never falls
  through to the SSH-derived path at all — nothing needs to be
  disabled, only never enabled.~~ **Wrong as written; corrected during
  implementation.** `sops.age.sshKeyPaths` is not a fallback that a set
  `keyFile` suppresses: it defaults to the host's ed25519 keys and
  `sops-install-secrets` imports those *alongside* the key file, into
  one age keyring (verified in `pkgs/sops-install-secrets/main.go`,
  which writes both into a single `age-keys.txt`). Disabling it
  therefore does take a line, and `modules/secrets.nix` now carries it
  — see "Amended during implementation", item 1.
- **A hardware token** (a YubiKey or similar, via `age-plugin-yubikey`
  and `sops.age.plugins`). The right eventual end state — a key that
  cannot be exfiltrated by copying a file — but rejected for *this*
  task: it adds a plugin dependency this project would need to pin and
  test, and its own recovery story (what happens when the token is
  lost, or when installing without one present) reintroduces a key-file
  fallback underneath it anyway. Worth a future task once the plain-key
  version has been lived with.
- **`ensureProfiles.environmentFiles` with no sops-nix at all** — the
  challenge `docs/backlog/declarative-wifi.md` itself raises. Answered
  at length above: the option is real and needs no sops-nix code to
  *use*, but something still has to put a real file at that path,
  keep it there across a reinstall, and do so without a human typing
  it in — which is what this task actually adds. Not rejected as
  wrong, just incomplete on its own; sops-nix is the missing half, not
  a replacement for the half `declarative-wifi.md` already found.
- **The password hash as the first secret**, instead of the PSK. See
  Non-goals for the full argument (needed at account creation,
  semantics change, two store routes) — restated briefly here: a wrong
  or absent PSK produces "no network," loud and recoverable; a wrong or
  absent password hash at account-creation time produces a machine
  nobody can log into, which is a strictly worse failure mode to debut
  a new mechanism against.
- **`sops.age.generateKey = true`** (let sops-nix generate its own
  machine-local age key on first activation, instead of planting one).
  Rejected: a key generated on the machine never exists anywhere to
  save to a password manager *before* the machine is configured, which
  defeats the whole re-enrollment story this design is built around —
  the machine could always decrypt secrets encrypted *after* its key
  existed, but nothing could ever decrypt a secrets file prepared in
  advance (the actual sequence every enrollment in §2 depends on), and
  a wipe would generate an entirely new, unrecoverable key with no
  artifact anywhere to recover from.
- **A permanent, working example age keypair and encrypted file,
  committed to this repo, so `nix flake check` can prove the full
  Wi-Fi/`ensureProfiles`/`sops.secrets` pattern evaluates.** Argued in
  full above ("What 'an obviously-fake example' means here"). Rejected:
  `validateSopsFiles`'s honest default makes this require a real,
  standing, working keypair forever, which is a secret-scanner and
  future-reader hazard disproportionate to what it would prove, when
  the vm-install harness's throwaway fixture proves the same pattern
  for real with nothing permanent at risk.
- **A dedicated diagnostic** (a `castle secrets-doctor` or similar,
  checking whether `sops-install-secrets` succeeded and naming why if
  not) alongside the mechanism itself. Deferred, not built: `systemctl
  --failed` and the activation log already surface the failure loudly
  — nothing about it is silent — and decision #2's own accepted
  trade-off is "obvious and recoverable," not "instrumented." Building
  a bespoke surface for a failure the platform already reports loudly
  is unscoped mechanism this task does not need.
- **A dedicated `nixosConfigurations.example-secrets`**, mirroring
  `example-dispatch`'s precedent, to prove the Wi-Fi consumption
  pattern in CI. Rejected for the same `validateSopsFiles` reason as
  the permanent-keypair option above — a config declaring
  `sops.secrets` needs a real file on disk at eval time regardless of
  whether that config is itself "real."

## Hard constraints, restated

- **Never write personal data into this repo.** No real hostname, no
  real SSID, no real key material — every example in this brief and in
  the doc rewrite uses the same fixture-identity convention this repo
  already established (`resident.nix`'s own `<your-login>` placeholders,
  `test/agent-loop/config-target.sh`'s `fixture@example.invalid`).
- **Principle 01 test.** `castle.secrets.sopsFile`/`ageKeyFile` are the
  public mechanism; the encrypted file, the age key, and the actual PSK
  are private configuration. Nothing about the Wi-Fi network name or
  the secret's contents is inferable from anything this task adds to
  the public repo.
- **Principle 02.** `nixosConfigurations.example` compiles against a
  dummy resident with `castle.secrets.sopsFile` left at its default;
  nothing in this task requires a real secret to exist for the public
  repo's own CI to pass.
- **S2: never edit `CLAUDE.md`.** No exception, autonomy grant or not.

## File-by-file change list

- **`docs/backlog/secrets-tooling.md`** — deleted, in the same commit
  that adds this brief, per `docs/backlog/README.md`'s lifecycle rule.
- **`docs/backlog/declarative-wifi.md`** — **edited in place, not
  deleted.** This is a deliberate departure from the usual
  promote-and-delete lifecycle, stated because the entry is only
  *partly* resolved: remove the "Possibly not blocked on
  `secrets-tooling.md` after all" bullet's open framing (this task
  answers it — point at this brief instead) and the now-resolved half
  of the "Open questions" list (whether this waits on secrets tooling —
  it no longer does, for a single known network on the installed
  system). Sharpen and keep open: multiple networks, the no-known-network
  fallback, and whether the installer image and the installed system
  share a mechanism (they explicitly do not, per this task).
- **`flake.nix`** — the `sops-nix` input (replacing the placeholder
  comment at lines 23–24); `nixosModules.secrets`; `nixosConfigurations.example`
  gains `self.nixosModules.secrets` in its module list and one new
  assertion (`config.sops.age.keyFile == "/var/lib/sops-nix/key.txt"`).
- **`modules/secrets.nix`** (new) — `castle.secrets.sopsFile` and
  `castle.secrets.ageKeyFile`, per §1 above.
- **`docs/private-layer.md`** — the "Secrets" bullet under "Slots that
  exist but are still empty" is rewritten from a placeholder into a
  full section: the enrollment steps (§2), the Wi-Fi worked example
  (§3), re-enrollment after a wipe, the key-absent/key-wrong behavior,
  and the disk-encryption caveat. Cross-references updated: the
  "installer image" section's paragraph on Wi-Fi ("Once sops-nix (or
  equivalent) lands...") is corrected to say precisely what changed —
  the *installed* system, not the installer image itself, which is
  unaffected by this task. `resident.nix`'s template example gains a
  commented-out `castle.secrets.sopsFile` line matching the style of
  every other optional block already there.
- **`hosts/xps9370/README.md`** — the install command (~line 143) gains
  the `--extra-files "$root"` addition and a preceding step describing
  §2's key-staging; the two existing Wi-Fi paragraphs (~109–115,
  ~192–202) are updated per "Re-reading finding #1" above — the
  installed system's first boot can now be zero-touch *if* the resident
  declared the secret; the installer image's own console flow is
  unchanged and the text says so explicitly rather than leaving it
  ambiguous.
- **`hosts/xps9370/default.nix`** — the comment "Secrets tooling may
  take this over later" (in the `networking.networkmanager.enable`
  block) is stale the moment this task lands; update it to point at
  this brief and `docs/private-layer.md`'s Wi-Fi example, or remove it
  if it no longer adds information beyond that pointer. No functional
  change to this file — the Wi-Fi profile itself stays entirely in the
  private layer, never in this host module, per Principle 01
  (`networking.networkmanager.enable` is a machine fact; a specific
  network's SSID and PSK are not).
- **`test/vm-install/run.sh`, `test/vm-install/vm-test-system.nix`** —
  extended per Verification plan below: a throwaway age key and a
  throwaway sops-encrypted fixture generated per run, `--extra-files`
  added to the existing `nixos-anywhere` invocation (~line 337),
  `nixosModules.secrets` imported into the harness's test system, and a
  post-first-boot assertion that the fixture secret decrypted to the
  exact known value.
- **`test/vm-install/README.md`** — "What it asserts" gains the new
  assertion; "Files here" documents the new fixture-generation logic.
- **`.github/workflows/vm-install-test.yml`** — no change expected: its
  existing `paths:` filters (`modules/**`, `hosts/**`, `test/vm-install/**`,
  `flake.nix`, `flake.lock`) already cover every file this task adds or
  touches under those trees. Confirm this remains true during
  implementation rather than assuming it.
- **`docs/tasks/0031-secrets-tooling.md`** — this brief, committed on
  this branch per the tasks convention.

Nothing in `modules/base/default.nix` changes — see Non-goals. Nothing
*behavioural* in `modules/installer.nix` changes — see "Re-reading
finding #1" above — though two of its comments turned out to assert
that no secrets mechanism exists in this repo, and were corrected: see
"Amended during implementation", item 3, along with two further
stale-claim sites in `docs/architecture.md` and `docs/private-layer.md`
that the file-by-file list did not anticipate (item 4).

## Non-goals

- **The password hash.** Named here as the intended successor to this
  task, not built by it. Three reasons it is harder, not just
  "next in line":
  - It is needed at **account creation**, on first boot — a wrong or
    absent value fails closed on the login path itself, not on
    something recoverable like a network join.
  - Migrating it changes its **semantics**, not just its source.
    `castle.admin.initialHashedPassword` feeds NixOS's
    `initialHashedPassword`, which only seeds the account once, at
    creation (verified: `nixos/modules/config/users-groups.nix`'s own
    override-order documentation lists `initialHashedPassword` and
    `hashedPasswordFile` as *distinct* options in its precedence
    tables — there is no `initialHashedPasswordFile`). The
    file-based option every "put this behind sops" instinct reaches
    for, `hashedPasswordFile`, is the **always-applied** variant,
    re-asserted on every activation like `hashedPassword` is — not the
    seed-only one. Swapping in a sops-managed file is therefore not a
    mechanical substitution; it changes a resident's password on every
    rebuild instead of only at creation, and interacts directly with
    `docs/backlog/initial-password-is-seed-only.md`, which documents
    the surprising, currently-undocumented consequences of that
    seed-only behavior today.
  - It **already reaches the store by two routes**, not one:
    `users.users.${cfg.username}.initialHashedPassword` (`modules/base/default.nix`
    ~line 170), and the password-reminder systemd unit's `script`,
    which embeds the same value directly via `lib.escapeShellArg
    cfg.initialHashedPassword` (~lines 208–224) — a second, independent
    place the plaintext-adjacent hash lands in a generated, world-readable
    store path. Migrating the first route without the second would
    leave the hash published anyway; a real migration has to find and
    fix both.
- **Multi-network Wi-Fi, roaming, and the no-known-network fallback.**
  Left exactly as open as `docs/backlog/declarative-wifi.md` leaves
  them; this task edits that entry, it does not close it.
- **Disk encryption.** `docs/backlog/disk-encryption.md` is adjacent —
  stated plainly above, not hidden — and remains a separate task.
- **The agent layer's own credentials.** Out of scope entirely; not
  touched by this task's module, docs, or verification plan.
- **A `git push` credential story for the private repo.**
  `docs/architecture.md`'s "pushing stays manual" note, which names
  secrets tooling as its eventual unblocker, is not resolved by this
  task landing — it names a *future* use of the mechanism this task
  ships, not a consequence of shipping it.

## Verification plan

**Automatable, and built as part of this task:**

- `nix flake check` — evaluates `nixosModules.secrets`'s option
  plumbing against `nixosConfigurations.example`'s dummy resident (no
  real secrets file required, since `castle.secrets.sopsFile` stays at
  its `null` default and `sops.secrets` stays empty there — see "What
  'an obviously-fake example' means here" for why this is the right
  boundary rather than a gap), and the new assertion that
  `sops.age.keyFile` resolves to the framework's documented default.
  ~~This also pulls `sops-install-secrets`'s package build into the
  `nixosConfigurations.example` closure for the first time — a real,
  modest addition to `flake-check`'s build time, worth noting rather
  than hiding, not a blocker.~~ **Predicted wrong; measured during
  implementation.** `nix flake check` *evaluates* every
  `nixosConfiguration` (which is what forces the assertions) but does
  not build any of their `toplevel`s, so no sops package build enters
  that gate at all. Measured on the implementing machine, cold cache
  either side: 56.0s before this task's changes, 55.7s and 57.4s after
  — i.e. no detectable difference, well inside run-to-run noise.
- **`test/vm-install/`, extended.** This is the harness that actually
  proves an unattended install, and the brief does not hand-wave past
  it: it is extended to plant a key and assert a secret decrypts, not
  left as a narrower doc-only proof.
  - `run.sh` generates a throwaway age keypair per run (`age-keygen`,
    from this flake's pinned nixpkgs, added to the existing
    `pkgs.nix`/`TOOLS` linkFarm), exactly mirroring the existing
    throwaway-admin-SSH-keypair convention already in that file — never
    committed, regenerated every run.
  - It also generates a throwaway sops-encrypted fixture file at run
    time (`sops --encrypt --age <the throwaway recipient>`, no
    `.sops.yaml` needed for a one-off ad hoc encryption), containing
    one key whose plaintext value is a fixed, obviously-not-a-real-secret
    marker string chosen for this harness (e.g.
    `castle-turing-vm-install-harness-fixture`) — **this is what
    answers "what must an obviously-fake example secret satisfy so CI
    can assert it is not real": it is generated by the CI job itself,
    moments before use, and the CI job is the one asserting its own
    value came back unchanged through the whole pipeline. Nothing about
    it could be mistaken for a real credential, and nothing about it is
    ever committed.**
  - The throwaway key is staged into the existing `--extra-files`
    staging directory (`var/lib/sops-nix/key.txt`, mode 600) and that
    flag is added to the `nixos-anywhere` invocation at ~line 337 of
    `run.sh`, alongside the existing `--store-paths`/`--target-host`
    flags — `--extra-files` is independent of `--store-paths` vs.
    `--flake`, verified above.
  - `vm-test-system.nix` imports `flake.nixosModules.secrets`, takes a
    new `secretsFile` argument (matching the existing `pubkeyFile`
    argument's shape), sets `castle.secrets.sopsFile = secretsFile;`,
    and declares one fixture secret, `sops.secrets."harness-fixture" =
    { };`.
  - After phase 2 (first boot, already an existing phase with SSH
    reachability as the admin), `run.sh` adds one more assertion: SSH in
    and read `/run/secrets/harness-fixture`, compare byte-for-byte
    against the marker string chosen when the fixture was encrypted.
    This is the whole-pipeline proof — encrypt → `--extra-files` plant
    → first-activation decrypt → real file with the expected content,
    with nobody at any keyboard.
  - **What this does not prove, and why that is an accepted gap**: the
    VM has no simulated Wi-Fi radio (QEMU's `-nic user` is wired
    Ethernet-equivalent), so the `ensureProfiles`/NetworkManager
    consumption half of §3 cannot be exercised by this harness at all —
    only the secrets-decryption pipeline that feeds it. That half rests
    on nixpkgs's own `ensureProfiles` module (widely used upstream,
    not new code this task writes) plus the `sops.templates` mechanism
    (verified directly against `sops-nix`'s own source above); this
    task's own contribution — the plumbing that gets a real, decrypted
    file onto a real disk unattended — is exactly what the harness
    proves. This gap is named here rather than discovered later.
- `docs/private-layer.md`'s submodule-style claims elsewhere in this
  file (§ "Migrating state out of the flake") set a precedent this task
  follows: a claim about upstream Nix/nixos-anywhere behavior gets
  verified by hand once, against the pinned versions, and cited with
  its exact evidence rather than re-derived in CI forever. Everything
  in "Verified against nixos-anywhere" and the `ensureProfiles`
  source-reading above was done that way for this brief; the
  implementing session should re-confirm each once against its own
  checkout before asserting it as fact in the shipped docs, the same
  discipline `docs/tasks/0030`'s implementation prompt asked of its own
  submodule-exclusion claim.

**Genuinely needs human hands:** the physical enrollment on a real
machine — generating a real age key, saving it to a real password
manager, running a real `nixos-anywhere --extra-files` install against
real hardware, and confirming a real Wi-Fi network is actually joined
(the one thing no VM harness here can simulate, per the gap named
above). Nothing in this task's scope can do that on anyone's behalf.

## Amended during implementation

Written by the implementing session, per `CLAUDE.md`'s rule that a
design shift during implementation corrects its brief in the same PR.
Everything above is the brief as specced except where it points here.

1. **`sops.age.sshKeyPaths` had to be turned off explicitly; the brief
   said it did not.** The "Considered and rejected" bullet on
   SSH-derived keys asserted that setting `sops.age.keyFile` means
   sops-nix "never falls through to the SSH-derived path at all."
   Read against the locked rev (`a8627b21`), that is false in a way
   that matters: `sops.age.sshKeyPaths` has its own default —
   `config.services.openssh.hostKeys`'s ed25519 entries, and
   `modules/base` enables OpenSSH — and `sops-install-secrets` imports
   the SSH-derived identities *and* the key file into one keyring
   (`pkgs/sops-install-secrets/main.go`: both are appended to a single
   `age-keys.txt`, gated on `len(AgeSSHKeyPaths) != 0 || AgeKeyFile !=
   ""`). Nothing breaks either way — the planted key still decrypts —
   but a resident could encrypt a secret to the host key without
   noticing and lose it permanently at the next reinstall, which is the
   precise failure this design chose a planted key to avoid.
   `modules/secrets.nix` therefore sets `sops.age.sshKeyPaths =
   lib.mkDefault [ ]`: `mkDefault` rather than a bare definition so a
   resident who actually wants SSH-derived identities can still say so,
   and so the framework's posture sits at a priority their own
   configuration wins over.

2. **`nix flake check`'s cost did not move.** See the corrected
   Verification-plan bullet: the gate evaluates configurations, it does
   not build their toplevels, so `sops-install-secrets` never enters
   it. Measured, not assumed.

3. **`modules/installer.nix` did change, in comments only.** The
   file-by-file list said "Nothing in `modules/installer.nix` changes,"
   which was right about behaviour and wrong about truth: two comments
   there stated that "this repo has no secrets mechanism yet — sops-nix
   is explicitly out of scope," a claim this task falsifies the moment
   it lands. Both now say what is actually true — the installer image
   is unaffected *because it has no disk to plant a key onto yet*,
   which is a stronger statement than the one they used to make. No
   option, script, or guided-join behaviour in that file was touched.

4. **The stale-claim sweep found two more live sites than the brief
   named**, both about pushing rather than Wi-Fi:
   `docs/architecture.md`'s "until secrets tooling lands, commits may be
   local-only" and `docs/private-layer.md`'s "**Pushing stays manual**
   until secrets tooling gives this project a credential story." Both
   name this task's arrival as their unblocking condition, and both
   would have read as satisfied the moment it merged — while the
   Non-goals section here is explicit that a push credential is *not*
   what this ships. Both were rewritten to separate the two: the
   storage mechanism exists now; the authority question of what an
   unattended push may do has not been answered, and that is what still
   gates it. `README.md`'s "Secrets tooling enters the repo before the
   first credential exists" was checked and deliberately left alone —
   it states a standing rule, not a status.

5. **`nixosConfigurations.example` asserts three facts, not one.**
   The brief specced `config.sops.age.keyFile == "/var/lib/sops-nix/key.txt"`.
   The shipped assertion adds `!options.sops.defaultSopsFile.isDefined`
   (the gate in §1 is the reason the module is importable with no
   secrets declared, so it is worth pinning that it really is left
   undefined rather than set to something) and
   `config.sops.age.sshKeyPaths == [ ]` (item 1 above — a regression
   there is silent and only bites at a reinstall, which is the worst
   possible time to find out).

6. **The harness asserts the key's mode and ownership too.** The brief
   specced one post-first-boot assertion, on the decrypted value. The
   shipped harness checks `stat` on `/var/lib/sops-nix/key.txt` first
   (`600 root:root`), because "the key never arrived", "the key arrived
   world-readable" and "the key arrived but did not decrypt" are three
   different bugs and the value assertion alone cannot tell them apart.
   It is also the only automated check anywhere that
   `--extra-files`'s permission-preserving and `--no-same-owner`
   behaviour — which this brief verified by reading source — is really
   what happens.

7. **The fixture's plaintext never touches disk.** The brief's sketch
   was `sops --encrypt --age <recipient>` over a file. `run.sh` pipes
   the marker into `sops` on stdin instead, with
   `--filename-override harness-secrets.yaml` so sops still infers the
   YAML format, so the only plaintext copy of the fixture lives in a
   shell variable for the length of one pipeline.

8. **The backlog deletion rides the first implementation commit**, not
   the brief's own. `b059f47`'s message says it promotes and deletes
   `secrets-tooling.md` and edits `declarative-wifi.md` in place; its
   diff is the brief and nothing else. Both backlog changes landed on
   the next commit instead — same branch, same PR, same review, so
   `docs/backlog/README.md`'s lifecycle rule is satisfied in substance,
   and saying so here is cheaper than rewriting history to make one
   commit message literally true.

9. **`flake.nix` and `modules/installer.nix` are not `nixfmt`-clean,
   and were already not clean on `origin/main`** (verified by running
   the check against a stashed tree). They were left as they are: this
   task's edits introduce no new formatting divergence, and
   reformatting either file would bury a small diff inside a large one.
   `modules/secrets.nix` is clean.

## Implementation prompt

For the session that implements this brief: read `CLAUDE.md` in full,
this brief in full, and every file named in "Before starting" before
writing anything. Work on branch `task/0031-secrets-tooling`, already
checked out in this worktree — do not create a new branch or touch any
other checkout. Scope diffs and reviews against `origin/main` (`git
fetch` first).

Implementation order:

1. `docs/backlog/secrets-tooling.md` — delete, in the same commit this
   brief is added in.
2. `docs/backlog/declarative-wifi.md` — edit in place per the
   file-by-file entry above; do not delete it.
3. `flake.nix` — add the `sops-nix` input, `nixosModules.secrets`, and
   `nixosConfigurations.example`'s new module import and assertion.
   Run `nix flake check` after this step alone, before writing
   `modules/secrets.nix`'s body, to confirm the input itself resolves
   and `sops-nix.nixosModules.sops` is the correct attribute name —
   verified once already for this brief, but re-confirm it against
   whatever rev `nix flake lock` actually pins.
4. `modules/secrets.nix` — the module itself, per §1.
5. `docs/private-layer.md` — the full "Secrets" section rewrite, the
   `resident.nix` template addition, and the installer-image
   cross-reference correction.
6. `hosts/xps9370/README.md` and `hosts/xps9370/default.nix` — per the
   file-by-file list.
7. `test/vm-install/run.sh`, `vm-test-system.nix`, `README.md` — build
   the throwaway-key/throwaway-fixture generation and the new
   post-first-boot assertion. This is the part most worth iterating on
   against the real harness rather than writing blind against this
   spec — `docs/tasks/0023-resume-cold.md`'s own observation about
   fixture-writing applies here too.

Before opening a PR: run `nix flake check`; run
`test/vm-install/run.sh` locally if a KVM-capable machine is available,
or via `gh workflow run vm-install-test.yml` otherwise (per that
workflow's own `workflow_dispatch` escape hatch); re-verify every claim
in "Verified against nixos-anywhere" and the `ensureProfiles`/`sops-nix`
source-reading above against the actual pinned revisions this
implementation locks, not the ones this brief was written against, and
correct this brief in place per `CLAUDE.md`'s rule if anything drifted.
Then run `/code-review` scoped against `origin/main`, address its
findings, then run `tools/codex-review.sh` for a second opinion, posting
its findings verbatim with any disposition in a separate comment
underneath.
