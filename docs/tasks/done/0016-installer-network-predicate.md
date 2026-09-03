# 0016 — The installer's network predicate never matched

## Why

The installer image from 0006/0012 was booted from a USB stick on real
hardware for the first time. Three defects surfaced in the first ten
minutes. All three are in `modules/installer.nix`, and the first one
means a whole branch of that module has never executed anywhere.

### Defect 1 — `have_network()` compares against a string `nmcli` never emits

```sh
have_network() {
  [ "$(nmcli -t -f STATE general 2>/dev/null)" = "connected-global" ]
}
```

`nmcli` in terse mode prints `connected`. It does not print
`connected-global`. Measured on the booted image, over SSH, while the
machine was demonstrably on the network:

```
raw STATE:  [connected]
show_addrs: [<redacted — a routable LAN address was present>]
OLD predicate: FALSE
NEW predicate: TRUE
```

`connected-global` is the name of the *enum constant*
(`NM_STATE_CONNECTED_GLOBAL`), not the string the CLI renders. The
module's comment asserts otherwise, at length and with confidence, and
the assertion was never tested against a running NetworkManager.

The consequence is larger than a mis-drawn banner. `have_network()` is
the only condition in the script's main loop, so:

- the **connected** banner — the SSH address, the hostname, the whole
  point of the console — has never rendered on any machine, ever;
- the script has only ever lived in its no-network branch, so it
  relaunches `nmtui` forever, *including after the operator has
  successfully joined a network and quit*;
- the operator is told there is no network by a machine that is, at
  that moment, reachable over SSH from another host.

That last line is precisely the failure 0012 exists to prevent. From
this file's own comment: *"a recovery console confidently giving
directions that no longer work"* is worse than printing nothing.

### Defect 2 — the shell hint names an account that has no shell

```nix
shellLoginHint = "log in as root or nixos, no password";
```

But `users.users.nixos.shell = statusScriptPath`. Logging in as `nixos`
on a spare VT re-runs the status script — i.e. drops the operator back
into the same `nmtui` loop they were trying to escape. Only `root` gets
a real shell.

Confirmed on the booted image: two copies of the status script were
running, pid on `tty1` (the intended autologin) and a second on `tty2`,
which was the operator following the printed instructions.

This module already *knew* the `nixos` account has no shell — there is
an assertion a hundred lines below whose entire purpose is catching a
private layer that picks `castle.admin.username = "nixos"`, because
`ssh nixos@...` "would hang forever". The same fact, encoded correctly
in one place and incorrectly in another.

### Defect 3 — nothing bounds the relaunch loop, and nothing explains it

Even with defect 1 fixed, the script can sit in a `nmtui` → exit →
`nmtui` cycle with no indication of *why* it believes there is no
network. The operator has no way to tell "NetworkManager reports
disconnected" from "this script's predicate is wrong" — which is
exactly the ambiguity that made defect 1 take a human at the keyboard
to find.

## What to change

All three in `modules/installer.nix`.

**1. Fix the predicate.**

```sh
have_network() {
  case "$(nmcli -t -f STATE general 2>/dev/null)" in
    connected*) ;;
    *) return 1 ;;
  esac
  [ -n "$(show_addrs)" ]
}
```

Two conditions, and the second is not redundant. `connected*` also
matches `connected (site only)` and `connected (local only)`; requiring
a non-empty global-scope address accepts the first (a LAN with no route
out is entirely fine for this image's purpose) and rejects the second
(link-local only, not reachable).

This is deliberately **weaker than the original intent** and the
rewritten comment must say so. The original asked for "real,
non-link-local connectivity" as a proxy for readiness. The actual
requirement is narrower and more honest: *can an operator on this LAN
open an SSH session to this machine.* That needs a routable address, not
an internet route. An installer on an air-gapped bench network should
show its address, not claim to be offline.

Do **not** substitute `nmcli -t -f CONNECTIVITY general = full`. It
answers a different question (can NetworkManager reach its check
endpoint), returns `unknown` where connectivity checking is unconfigured
— the exact fragility the original comment was trying to avoid — and
reports `limited` or `portal` on perfectly usable LANs that block the
check.

**2. Fix the hint.** `shellLoginHint = "log in as root, no password"`.
One edit; both the console banners and `services.getty.helpLine` read
this binding, which is the one part of the original design that worked
as intended.

**3. Bound the loop and make it self-diagnosing.** When `nmtui` exits
and `have_network()` is still false, print what NetworkManager actually
reports — the raw `STATE`, and the global addresses seen, if any —
before looping. Hold long enough to be read.

An operator staring at `no network yet` directly above `STATE:
connected` diagnoses defect 1 in one second instead of needing a second
machine and an SSH session. This is the cheapest possible insurance
against the next predicate bug, and its value does not depend on the
predicate being right.

## Considered and rejected

**An in-script "press S for a shell" escape.** Rejected in 0012 and
rejected again here, for the same reason: that escape depends on this
script correctly reading the keyboard, which is the exact mechanism
that failed in the incident 0012 was written for. The VT escape must
keep depending on nothing this script does. The new diagnostic output
is display-only and adds no input path.

**Dropping `nmtui` in favour of a `nmcli`-driven prompt.** Larger
change, no evidence it is needed — `nmtui` worked correctly on hardware
once `--foreground` was fixed in 0012. The bug is in the predicate that
decides whether to *show* it.

**Retiring the status script for a systemd unit.** Out of scope. The
login-shell approach is working; only its logic was wrong.

## Verification

**This is the part that matters, because CI has been green through all
of this.** `test/vm-install/` cannot have been asserting on the
connected banner — that branch was unreachable, so any such assertion
would have failed from the day it was written. A check that could only
ever pass is the sixth instance of this failure mode in this project.

Required, in order:

1. **Add a runtime assertion to `test/vm-install/`** that the connected
   banner reaches the serial console in a VM that has a network — the
   hostname line and the `ssh root@` line specifically, not merely that
   the script produced output.
2. **Prove the new assertion by breaking the code, not the test.**
   Revert `have_network()` to the `connected-global` comparison, confirm
   the new assertion *fails*, then restore the fix. Record both results
   in the decision log. An assertion that has never been observed
   failing is not evidence.
3. Existing eval-time assertions still pass, including the escape-line
   count (still 3 — the states are unchanged; the new diagnostic text is
   additional output within the no-network state, not a fourth state).
   If the count changes, the assertion's expected value changes with it
   in the same commit, and the reason goes in the brief.

Already verified on hardware and **not** needing re-testing: SSH
reachability, mDNS resolution of the image's default hostname,
`autologinOnce` respawning `tty1` to a login prompt rather than the
script, and a spare VT reaching a root shell. Those all work.

## Non-goals

- Wi-Fi provisioning from the private layer. Still blocked on a secrets
  mechanism; see 0006.
- Any change to `hosts/vm-test`, which deliberately imports no agent
  module.
- Rewriting the escape-hatch design from 0012. Its VT mechanism was
  correct and is now confirmed on metal; only its printed instructions
  were wrong.

## Notes for the implementer

The long comment block above `statusScriptText` argues in detail for the
predicate this brief replaces. **Rewrite it rather than leaving it
contradicting the code.** A confident comment describing an abandoned
design is worse than no comment — the same rule this project applies to
briefs. Say plainly that the original reasoning was wrong, and why the
weaker predicate is the correct one, so the next reader does not
"restore" the bug.

No address, SSID, or hostname from the operator's own network goes into
the repository, in code, comments, fixtures, or commit messages. The
measured evidence in this brief is redacted for that reason.
