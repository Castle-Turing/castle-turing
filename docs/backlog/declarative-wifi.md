# Declarative Wi-Fi provisioning

**What.** Let a host's wireless networks be declared in configuration
so a freshly installed machine joins the network by itself, with no
human at the keyboard.

**Why it matters.** This is the last manual step in an otherwise
unattended install. Task 0006's installer image prompts the operator to
join a network when it has no connectivity — a real improvement over
sitting silently — but it is still a human typing a password, once per
installer boot and again on the installed system. On a chassis with no
Ethernet port (the XPS 13 9370), that step cannot be skipped.

**What we already know.**

- **Possibly not blocked on `secrets-tooling.md` after all.** A PSK is a
  credential and cannot be committed to either repo in plaintext, which
  is why task 0006 deliberately did not bake one into the image. But
  nixpkgs ships
  `networking.networkmanager.ensureProfiles.environmentFiles`, which
  references a PSK by an out-of-store file path — public mechanism (the
  option), private configuration (whatever keeps that file secret).
  That is Principle 01's split without any secrets tooling, and it
  deserves evaluating before assuming this waits on sops-nix.
  Surfaced by review during task 0006, after the manual-join decision
  was already made deliberately; recorded here rather than reopening
  that decision.
- NetworkManager profiles are declarable in NixOS, and the PSK can be
  referenced from a secrets file rather than inlined once the tooling
  exists.
- A rejected alternative worth recording: injecting the PSK at
  image-build time from a file outside both repos. It works and leaks
  nothing into git, but it puts the secret in a physical artifact and
  adds a build-time input; the resident preferred one guided manual
  join instead.

**Open questions.** Does this belong to the installer image, the
installed system, or both — and are they the same mechanism? How are
multiple networks (home, office, phone hotspot) expressed? Is there a
sane fallback when no known network is in range, so the machine still
tells a human what it needs?
