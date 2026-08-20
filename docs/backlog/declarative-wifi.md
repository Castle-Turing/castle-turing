# Declarative Wi-Fi provisioning

**What.** Let a host's wireless networks be declared in configuration
so a freshly installed machine joins the network by itself, with no
human at the keyboard.

**Partly done, deliberately still open.**
`docs/tasks/0031-secrets-tooling.md` closed the single-known-network
case for the *installed* system: a resident declares an encrypted PSK,
`sops.templates` renders it into the `KEY=value` file
`networking.networkmanager.ensureProfiles.environmentFiles` wants, and
NetworkManager writes the profile at activation with nobody present.
The worked example is in `docs/private-layer.md`'s "Secrets" section.
This entry stays for everything that example does not cover.

**Why it matters.** What is left is still a human typing a password.
The installer image (task 0006) prompts for a network join once per
boot, and a laptop that leaves the house meets networks nothing has
declared. On a chassis with no Ethernet port (the XPS 13 9370), a
machine that cannot join a network cannot be reached at all.

**What we already know.**

- **The mechanism question is settled, and it was two halves rather
  than one.** `networking.networkmanager.ensureProfiles` was always the
  right option — public mechanism, private configuration, and it needs
  no sops-nix-specific code to *use*. What it could not do on its own
  was put a real file at the out-of-store path it reads, keep it there
  across a reinstall, and do that without a human typing it in. That is
  the half `docs/tasks/0031-secrets-tooling.md` built; read its "The
  declarative-wifi challenge, answered" section before reopening any of
  it. The question was raised here by review during task 0006 and has
  now been answered rather than left hanging.
- **The installer image and the installed system do *not* share a
  mechanism**, and that is a decision now, not an open question. The
  installed system decrypts with an age key planted on its own disk by
  `nixos-anywhere --extra-files`; the installer image runs before any
  such disk exists, so it keeps its guided `nmtui` join. Making the
  image declarative needs a different idea — one about how the ISO
  itself carries an identity — not an extension of this one.
- A rejected alternative worth recording: injecting the PSK at
  image-build time from a file outside both repos. It works and leaks
  nothing into git, but it puts the secret in a physical artifact and
  adds a build-time input; the resident preferred one guided manual
  join instead.

**Open questions.** How are multiple networks (home, office, phone
hotspot) expressed — a list of profiles is the obvious shape, but which
secrets file holds which PSK, and does every machine get every network?
Is there a sane fallback when no known network is in range, so a
machine that cannot get online still tells a human what it needs
instead of sitting silently? And does the installer image ever get a
declarative join, given that it has no disk to plant a key onto — or is
one guided console join per installer boot simply the end state?
