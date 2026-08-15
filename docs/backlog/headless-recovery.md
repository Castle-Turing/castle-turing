# A designed recovery path for a machine that loses the network

**What.** Decide, deliberately, how a Castle Turing machine is reached
when its normal remote path is gone — no Wi-Fi, no display, or a
configuration that broke its own connectivity.

**Why it matters.** During task 0003 the installed system came up with
no working Wi-Fi firmware, and the machine became unreachable: SSH
needed the network, the network needed a console, and the console
needed a password that did not exist. Every escape route depended on
one of the others. The password lockout is now fixed, but the general
shape of that trap remains: a system designed to be operated remotely
needs a considered answer for when remote operation fails, or a small
misconfiguration turns into a USB-stick round trip.

**What we already know.**

- iPhone USB tethering was tried as a recovery route and does not work
  without `usbmuxd`, which the config does not include. Android
  tethering needs only in-kernel drivers and would have worked.
  `services.usbmuxd` is a one-line candidate.
- USB-C Ethernet works with in-kernel drivers, so a dongle is a
  zero-config recovery path — worth documenting even though it is
  hardware, not configuration.
- Rollback is the other half of this: a bad generation can be selected
  away at the boot menu, but only by someone physically present. That
  is the existing answer and it may be sufficient — the point is to
  decide rather than discover.
- Interacts with `disk-encryption.md`: an encrypted root makes every
  recovery path harder, because the disk cannot be read from a live USB
  without the key.

**Open questions.** Which paths are worth building versus documenting?
Does the machine need a "if you cannot reach me, do this" note that
lives outside the machine (in the README, where a stranger will look)?
Should the agent layer eventually notice it has lost its own remote
access and say so through another channel before it becomes a problem?
