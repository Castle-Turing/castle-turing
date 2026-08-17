# The only machine that can build the system is the one being wiped

**What.** This project has exactly one host capable of evaluating Nix:
the reference host itself. Every install, rescue, and image build
therefore depends on the target machine already being healthy. Decide
whether that is acceptable, and if not, what the second path is.

**Why it matters.** It is a single point of failure sitting underneath
the recovery story, and it is invisible until the day it matters. The
documented install procedure (`hosts/xps9370/README.md`, step 4) says to
run `nixos-anywhere` "from a machine with Nix and your private flake
checked out" — and quietly assumes such a machine exists besides the
target. On the first from-scratch reinstall it did not. The workaround
was to run the install from inside the booted installer environment,
which has Nix, but that only works because the installer image was
already built and written *before* the wipe.

Follow the dependency chain and it closes on itself: building an
installer image requires Nix; the only Nix host is the reference host;
so a reference host that will not boot cannot produce the image needed
to repair it. Today that was survivable because the machine was
healthy and we built the image first. A failed disk, a bad generation
that will not boot, or a firmware problem would leave nothing to build
with.

Rollback covers a bad *generation*, not a machine that cannot start.
`docs/vision.md` treats rollbackability as a load-bearing promise; this
is the case that promise does not reach.

**What we already know.**

- The install was performed by running `disko` and `nixos-install`
  directly inside the installer environment rather than driving
  `nixos-anywhere` from a controller. It worked, and the four-phase
  flow the README describes (`kexec,disko,install,reboot`) reduces to
  the middle two when there is no controller to run them from.
- The installer image itself was built on the reference host, from a
  one-shot `--override-input` pointing at an unmerged branch, and
  written to USB from that same host. That is a second instance of the
  same dependency, in the same session.
- The generated `hardware-configuration.nix` came back identical to the
  committed one, so the install did not depend on regenerating it.

**Options not yet weighed.** A second Nix host (another machine, a VM,
a cheap always-on box); a periodically-built rescue image kept on the
USB stick and refreshed on a schedule rather than per-install; building
images in CI and publishing them as artifacts, so a working image is
always downloadable without any local Nix; or accepting the gap
explicitly and documenting the manual path back (boot stock NixOS
installer media, install a minimal system, use it to build). The last
is free and may be enough — but it should be a decision that was made,
not one that was defaulted into.

**Non-goal for now.** Nothing here argues for changing how the install
works when the machine *is* healthy. That path is documented and now
exercised twice.
