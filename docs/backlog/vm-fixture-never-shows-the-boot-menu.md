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

It was filed expecting to get sharper with the activation task, on the
expectation that its rollback story would lean on exactly this menu.

**It did not, and that is now settled.** `docs/tasks/0048-activation.md`
landed and its rollback is `nixos-rebuild switch --rollback` on a
running machine, which never reaches a bootloader at all: the previous
generation is selected by the system profile, not by a menu. The menu is
the recovery path for a generation that will not *boot*, which is
`headless-recovery.md`'s territory, and this entry stays filed against
that rather than against activation. The condition it set for changing
`hosts/vm-test`'s timeout — a consumer that needs the menu rendered —
has not arrived.

Found during the re-baselining pass for the task that became 0048, and
independent of anything that task decided.

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
- 0048 also found that the other half of this — proving the previous
  generation is present and selectable *after* an activation — cannot
  live in `test/vm-install` at all, for a reason unrelated to the
  timeout: `hosts/vm-test` deliberately imports no agent module, and
  that is the anti-bricking regression test rather than an oversight.
  See `docs/backlog/activation-is-not-proven-on-a-real-vm.md`.

**Open questions.** Fix the fixture, or prove the menu another way? If
the fixture changes, what is the smallest timeout that is reliably
observable in a VM screenshot, and does the existing NVRAM-wipe
assertion still hold across it? And now that no task needs the menu
rendered, is this worth doing at all before something does?

**What to re-run when it changes.** `test/vm-install/run.sh` (the host's
own harness, and the one whose timing the change moves) and
`test/desktop-loop` (which boots the same fixture family and has
screenshot-ordering assertions that a boot-menu pause would shift).
Both need a human or a machine with KVM; neither runs in the
`dispatch-test` CI job.
