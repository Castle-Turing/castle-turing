# The installer console must always have an escape hatch

**What.** The status/network console in `modules/installer.nix` is
installed as the login shell of the installer's only auto-login
account, on every virtual terminal. When that script misbehaves there
is no way to reach a real shell — switching VTs just runs it again.
Give the operator a guaranteed way out.

**Why it matters.** Demonstrated, not theorised: on the first
from-scratch boot of the custom image, `nmtui` rendered but ignored
every keypress (a `timeout` process-group bug, fixed separately). With
the console unusable and no shell reachable on any VT, the machine was
simply unusable — the operator could see a perfectly drawn menu and had
no way to do anything at all, including diagnose it. A recovery tool
whose failure mode is "no recovery" inverts its own purpose.

**What we already know.**

- The stock NixOS installer profile auto-logs-in the `nixos` account on
  every getty, not just tty1. Setting `users.users.nixos.shell` to the
  status script therefore captures all VTs at once. The module's
  comments assumed "a second VT as root" remained available; it does
  not.
- The immediate trigger was `timeout 300 nmtui` running the child
  outside the terminal's foreground process group, so it drew fine and
  could not read the keyboard. Fixed by `timeout --foreground`, but the
  fix is incidental — any future failure in this script reproduces the
  same trap.
- Escape routes that did exist, none discoverable from the console
  itself: a `systemd.unit=rescue.target` kernel argument at the boot
  menu, or plugging in Ethernet so the script stops blocking. Neither
  is mentioned on screen.
- The VM harness cannot catch this class at all: it asserts the
  installer is SSH-reachable with *zero* console interaction, so a
  console that renders but accepts no input passes every assertion.
- Related: `docs/backlog/headless-recovery.md` describes this same
  shape — every escape route depending on another — for the installed
  system. This is the installer's instance of it.

**Open questions.** Run the status display on tty1 only and leave the
other VTs as plain shells? Offer an explicit key ("press S for a
shell") and print it on screen? Both? Should the script be supervised
so a crash falls back to a shell rather than a respawn loop? Is there a
general rule worth adopting — that any Castle Turing component which
takes over a console must state, on that console, how to leave it?
