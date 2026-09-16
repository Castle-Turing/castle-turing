# An oomd kill takes the whole desktop, because every app shares one cgroup

**What.** On the xps9370, every GUI application runs in a single
cgroup. greetd's login lands sway in logind's session scope
(`/user.slice/user-1000.slice/session-N.scope`, verified 2026-09-16),
and everything launched from sway — wmenu picks, `exec` bindings,
terminals, and every process they spawn — inherits it by fork. The
systemd user manager (`user@1000.service`) manages only explicit user
units; castle's timers live there, but no app launch on this host is
wrapped into one. Firefox, qutebrowser, foot, and the Claude sessions
inside foot are one undifferentiated leaf cgroup as far as the
kernel's accounting and systemd-oomd's kill selection are concerned.

**Why it matters.** systemd-oomd kills leaf cgroups. Task 0073 wires
its swap rule so a runaway allocation finally gets killed instead of
livelocking the machine (the 2026-09-15 crash: Firefox loading Gmail,
per the resident's testimony — the journal never named it). But with
one leaf holding the whole desktop, the eligible victim *is* the whole
desktop: sway, terminals, and any in-flight agent work die alongside
the browser that misbehaved. A clean SIGKILL and a login prompt beat a
power button, which is why 0073 is right to land anyway — but the
kill-target risk task 0063 accepted ("the expectation is that the
runaway session's cgroup, not the compositor's, is what dies") turns
out to be optimistic in the concrete: there is no separate cgroup for
the expectation to be about. This is the same genus as the oomd
finding itself — an upstream default (minimal compositors do not wrap
app launches; GNOME and KDE do, via per-app `app-*.scope` units under
the user manager) that was never chosen, recorded, or tested against
this failure mode.

**How it would have been caught sooner.** The memory-exhaustion drill
already proposed in `the-kernel-oom-killer-has-no-swap-headroom.md` is
the honest detector: it measures which cgroup actually dies when a
rule fires, and on today's layout it would report "all of them". A
cheaper static probe — assert that a GUI app's cgroup differs from the
compositor's — only becomes a regression check *after* per-app scopes
exist; land it with the fix so the layout cannot silently revert.

**Fix directions, none chosen.**

- Wrap app launches in per-app transient scopes under the user
  manager: `systemd-run --user --scope` (or the equivalent uwsm-style
  session integration) in the launcher path and the sway `exec`
  bindings, following the XDG convention GNOME and KDE already
  implement. A runaway app is then its own leaf and dies alone.
- Decide the wrapping's reach deliberately: launcher picks only, or
  also terminals — a terminal in its own scope contains the agent
  sessions it hosts, which both protects them from a browser's kill
  and makes them individually killable when they are the runaway,
  which is what `an-agent-workload-can-thrash-the-host.md` wants
  bounded anyway.
- Once apps have their own scopes, per-app `MemoryHigh=` becomes
  expressible for known-hungry classes (browsers), turning the OOM
  defense from post-hoc killing into throttling-before-crisis. Slot
  design per Principle 01: the mechanism (wrapped launches) is public
  module material; any per-app numbers are the resident's.

**Open questions.** Whether sway's own process should also leave the
session scope (probably not — something must survive a kill to show
the user what happened); how an oomd kill becomes a notification the
resident and the agent layer actually see, which
`the-kernel-oom-killer-has-no-swap-headroom.md` already carries as an
open question and which per-app scopes make more valuable (the kill
message would finally name one app); and whether the wrapper belongs
in `modules/desktop` for any sway host or stays with the xps9370
until a second desktop host exists.
