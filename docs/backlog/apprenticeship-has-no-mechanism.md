# The apprenticeship has no mechanism

**What.** `docs/vision.md` promises a system "deliberately chatty during
an initial apprenticeship period, asking the priority questions, then
going quiet as the model fills in." Nothing in the repo asks the
resident anything at first run. There is no onboarding flow, no place
one would live, and no decision about what it would ask. The reference
machine's clock reading UTC is the instance that surfaced this.

**Why it matters.** `time.timeZone` is set nowhere — not in `modules/`,
not in `hosts/`, not in the private layer — so NixOS falls back to UTC,
which is what `timedatectl` reports. NTP is active and the clock is
otherwise correct: the time is right, the zone is missing. The one-line
fix is not the point.
The point is that timezone is the first setting that fits neither
pattern this repo has: it is not worth failing a build over, defaulting
it is what produced the bug, and getting it right means asking. Every
setting like it that follows will be stuck in the same gap.

**What we already know.**

- **The two existing patterns, and why neither fits.** *Hard-asserted:*
  `castle.person.gitUserName`/`gitUserEmail` (`modules/home/default.nix`,
  assertions ~L70-88) and `castle.admin.initialHashedPassword`
  (`modules/desktop/default.nix`, assertion ~L177) fail the build until
  the private layer supplies them. *Silently defaulted:* `castle.display.*`
  and `castle.display.wallpaper` (`lib.mkDefault`,
  `modules/desktop/default.nix` ~L173) — the framework picks something
  sensible and says nothing. Failing the build over a timezone would be
  obnoxious; defaulting it produced this bug.
- **Detection is a network-privacy question, not a convenience one.**
  The pinned nixpkgs ships `services.automatic-timezoned` and
  `services.localtimed` (both geoclue-based, both documented as
  conflicting with an explicitly set timezone) over `services.geoclue2`,
  whose default `geoProviderUrl` is `https://api.beacondb.net/v1/geolocate`
  — a third-party service. Every automatic option resolves the resident's
  location through the network. A machine that changes its own clock
  because it inferred where you are is at best made-then-reported in the
  vision's authority taxonomy, arguably queued-for-approval. The resident
  has said they would want detection *with* approval.
- **Proposal 05 already settles the grammar, and only the grammar.**
  `docs/architecture.md`: inference may open a question; only the
  resident may close it, and the closure carries provenance (what was
  asked, what was answered, when). So "detection with approval" is
  decided in principle. What it does not give: any flow — when questions
  are asked, in what order, on what surface. And a real wrinkle — its
  write path lands in the resident *model* (`state/`, per task 0009),
  while a timezone must land in the private layer's Nix configuration to
  take effect and survive a rebuild. An approved answer that must become
  configuration is a case the current write path does not cover.
- **A surface exists nearby but cannot ask.** Task 0009
  (`docs/tasks/0009-ambient-intake.md`) built `castle-modal`, a floating
  dialog on a Sway keybinding. Read honestly, it handles only
  resident-*initiated* intake: compose a request or a correction, view
  errand status. It has no mode for a system-initiated question put to
  the resident; questions flow through the router, and the resident-model
  write path is the `castle answer` CLI (0009 scope item 7).
- Principle 01 splits cleanly — the mechanism for asking and applying is
  framework, the resident's actual zone is private configuration — so the
  split is not what is missing here.

**Open questions.** Where does an onboarding flow run — build time,
first boot, first login? What belongs in it besides timezone: locale,
keyboard layout, hostname, Wi-Fi (`docs/backlog/declarative-wifi.md` is
adjacent, and has the same "last manual step" shape)? Is geolocation's
network cost worth paying at all when the resident could just type a
zone — Proposal 05 permits detection as a question-opener, but permitting
is not requiring. How does an answered-once setting get recorded so it
is never asked again: the decision journal's job, the resident model's,
or the private layer's Nix config, given they are three different places
and only the third takes effect? And the question under all of them —
does this need a mechanism of its own, or is it the first real consumer
of the authority taxonomy that has not been built yet?
