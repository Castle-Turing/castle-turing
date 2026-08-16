# The ISO build has a bootstrap problem

**What.** Document (and where possible remove) the chicken-and-egg in
getting a first Castle Turing machine installed: building the
personalized installer image requires an x86_64 Linux machine running
Nix, which a new adopter may not have yet — the machine they are trying
to install being the obvious candidate.

**Why it matters.** This is the first thing a stranger hits, before any
of the project's actual ideas. Principle 01's test is whether someone
could reproduce this system for themselves over a weekend without us in
the room; an unstated prerequisite of "already own a working Linux box"
fails that test quietly, at the worst possible moment.

**What we already know.**

- Confirmed the hard way while building the reference host's own image:
  an aarch64 macOS machine cannot build an `x86_64-linux` ISO. Nix
  refuses with "Required system: x86_64-linux, Current system:
  aarch64-darwin".
- `nix build --builders 'ssh-ng://<host> x86_64-linux'` is the
  documented escape, but it silently does nothing unless the local user
  is a *trusted* Nix user — it fell back to a local build and failed,
  with no message explaining why the remote builder was ignored.
- What actually worked: copying the private flake to an existing
  x86_64 NixOS machine, building there, and copying the ISO back. Fine
  when you already have such a machine; useless for a first install.
- The workable answer for a true first install is probably: use a stock
  NixOS ISO for install #1 exactly as `docs/tasks/0003-first-install.md`
  describes, then build your own personalized image afterward, once the
  machine that can build it exists. Nothing says this today.
- Alternatives worth weighing: publishing prebuilt generic images
  (which cannot contain an adopter's key, so they lose the whole point),
  or a documented remote-builder recipe including the trusted-user
  requirement, or binary-cache hosting so the build is mostly a
  download.

**Open questions.** Is documenting the two-phase path
(stock ISO first, personalized image after) sufficient, or should the
framework do something? Is there a cross-compilation or emulation route
worth the complexity? Should the ISO build fail loudly with a helpful
message when it detects a system mismatch, rather than Nix's generic
error?
