# No watchdog forces a panic on a hang

**What.** Nothing on this host turns a silent hang into a kernel
panic. `systemd.watchdog.runtimeTime` (`RuntimeWatchdogSec`, petting
a hardware watchdog device such as `/dev/watchdog`) is unset, so if
systemd itself stops being scheduled — the shape of the 2026-09-06
21:15–21:22 hang task 0068 investigated — nothing forces the kind of
crash that either journald's immediate CRIT/ALERT/EMERG sync or the
kernel's own pstore capture (`nixos/tests/systemd-pstore.nix`) could
actually catch. A hang that never panics leaves both mechanisms with
nothing to record.

**Why it matters.** Task 0068 tightened journald's own flush cadence
and confirmed pstore/`systemd-pstore.service` is already wired in by
NixOS's defaults for the case where the kernel *does* panic. Both are
now as good as they can be for their respective cases, and both are
still blind to a hang that produces no oops at all — which is what
actually happened here. A watchdog is the only mechanism that can
convert "nothing is scheduling anymore" into "something worth
capturing," and closing this gap is what would make a future
inquest (`a-crash-goes-uninvestigated.md`) actually have evidence for
*this* incident's shape, not just for panics and OOM kills.

**What we already know.** Verified against this flake's pinned
nixpkgs (`0e251e24a4f24e036a084b6b4b2d2491af4167f4`, systemd 261.1):
`systemd.watchdog.runtimeTime` maps to
`services.settings.Manager.RuntimeWatchdogSec`
(`nixos/modules/system/boot/systemd.nix`), and needs a real watchdog
device to do anything — `WatchdogDevice`, defaulting to
`/dev/watchdog`. Whether hosts/xps9370's chassis actually exposes a
usable one (an Intel ICH/PCH TCO watchdog via `iTCO_wdt` is common on
this class of hardware but is a firmware fact, not something this
framework may assume — Principle 01) is unverified; task 0068
deliberately did not guess at it. Enabling a runtime watchdog is not
free of risk either: a false-positive reboot during a legitimately
slow-but-not-hung operation is a real failure mode, and the interval
needs tuning against real behavior on this machine rather than a
default picked in the abstract.

**Open questions.** Whether `/dev/watchdog` (or an equivalent, e.g.
`wdt` on other chassis) exists on hosts/xps9370 at all; what
`RuntimeWatchdogSec` value avoids false positives on this machine's
real workload without leaving the window uselessly wide; whether a
forced panic should also trigger `kernel.panic` reboot behavior or
just sit long enough for pstore to capture it before the reboot
timer fires; and whether this belongs in `hosts/xps9370` (a
chassis-specific watchdog device) or could generalize once a second
host exists to test the assumption against.
