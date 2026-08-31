# The one VM fixture built to test boot never shows the boot menu

**What.** `hosts/vm-test/default.nix:33-34` sets
`boot.loader.timeout = 0`, so systemd-boot selects the default entry
immediately and the menu is never presented. That fixture exists
specifically to regression-test booting a freshly installed machine
(`test/vm-install/`), and the boot menu — the route to a previous
generation — is the one boot-time surface it cannot demonstrate.

**Why it matters.** Rollbackability is a load-bearing promise in this
project: `CLAUDE.md` states it, `docs/vision.md` rests on it, and the
practical form of it on a machine that will not boot is *choosing an
older generation from the bootloader menu*. Nothing anywhere proves that
menu appears. The harness proves the machine boots, which is the case
where you do not need the menu.

It gets sharper with `docs/tasks/0027`. That task owns activation — the
first time this system produces a new generation — and its rollback
story leans on exactly this menu. A fixture that cannot show the menu
cannot be extended to prove "the previous generation is still
selectable after an activation", which is the assertion 0027 will most
want. Better to know that now than to discover it while writing 0027's
verification plan.

Found during the 0027 re-baselining pass, and independent of anything
0027 decides.

**What we already know.**

- The comment on the line gives the reason, and it is a good one for
  what it was written for: "Nobody is ever at this console; don't sit at
  a boot menu." `test/vm-install/run.sh` boots this host unattended and
  a menu that waits would just cost wall-clock time on every run.
- `modules/installer.nix:542` sets the same thing with `lib.mkForce 0`,
  and that one is not in question: an installer ISO genuinely has
  nothing to choose between.
- The probable fix is one line — a small non-zero timeout on the
  vm-test host, with the harness driving past it — but it is **not**
  free: it changes boot timing for every VM harness that uses this
  host, and both `test/vm-install/run.sh` and `test/desktop-loop` have
  timeouts and screenshot ordering tuned against today's timing. That
  is why this is filed rather than fixed inside a review-heavy PR.
- An alternative worth weighing first: leave the fixture at 0 and prove
  the menu somewhere else — a second host, or an assertion on the
  generated `loader.conf` rather than on the rendered screen. The
  cheapest honest check may be that the bootloader is *configured* to
  present a menu with more than one entry, which needs no boot at all.
  Whether that is enough depends on what 0027 actually wants to claim.

**Open questions.** Fix the fixture, or prove the menu another way? If
the fixture changes, what is the smallest timeout that is reliably
observable in a VM screenshot, and does the existing NVRAM-wipe
assertion still hold across it? Does 0027 need the menu *rendered*, or
only the previous generation *present and selectable* — those are very
different tests, and only the first needs a timeout at all.

**What to re-run when it changes.** `test/vm-install/run.sh` (the host's
own harness, and the one whose timing the change moves) and
`test/desktop-loop` (which boots the same fixture family and has
screenshot-ordering assertions that a boot-menu pause would shift).
Both need a human or a machine with KVM; neither runs in the
`dispatch-test` CI job.
