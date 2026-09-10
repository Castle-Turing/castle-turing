# GUI surfaces have no convention

**What.** The castle will eventually need graphical surfaces, and
nothing says what they are made of. The resident's proposal
(2026-09-09): castle GUIs are local web applications whose backends
are agent-friendly, shown to the resident through the chromeless
qutebrowser window shell that Mediatron (the castle's document
viewer, its own repo) already carries — and never operated by the
agent through the frontend. This entry records the proposal and what
a live prototyping session verified, so whoever specs it does not
re-derive either.

**Why it matters.** The TUI record argues the current path taxes
exactly what our models are worst at. [[an-arrow-key-is-three-dismissals]]
is a hand-written escape-sequence parser failing at input handling
browsers solved decades ago, and the planned Shift+Enter fix means
adopting the kitty keyboard protocol — more bespoke input plumbing
([[the-modal-is-only-just-usable-enough-to-test-with]]). Models
write HTML/CSS fluently, and scrolling, focus, text input,
typography, and live updates come with the engine instead of being
implemented one complaint at a time. The founding objection to GUIs
(`docs/vision.md`: an agent driving pixels and simulated clicks)
does not apply here, because the browser is the resident's viewport
only; the agent operates the backend. The proposal generalizes
castle-modal's own invariant — every flow drivable non-interactively
— from stdin/stdout to HTTP, so it extends a rule the project
already holds rather than adding a new one.

**What we already know.** Verified 2026-09-09 in a live session on
the project machine (sway; qutebrowser 3.7.0 on QtWebEngine 6.11.2,
Chromium 140, from the Mediatron flake):

- One qutebrowser instance per basedir already is the daemon: later
  invocations hand URLs and commands to it over its IPC socket, and
  `--target window` attaches a new window, so another surface costs
  one renderer process rather than another engine. Two caveats: there
  is no windowless mode — the instance exits with its last window, so
  "warm" means one persistent window or an accepted cold start — and
  the IPC socket lives under `<basedir>/runtime/`, so a long basedir
  path breaks startup against the 107-byte unix-socket limit
  (observed, misdiagnosed twice before the path was shortened).
- Per-URL-pattern settings cover the document/application split
  inside one shared instance: 57 settings accept patterns, including
  `content.javascript.enabled` — JS off for rendered documents, on
  for declared app origins.
- WebAssembly works: an empty module instantiated in-window; the
  engine is stock Chromium and qutebrowser disables nothing.
- Window chrome is entirely sway's job. A fictional modal-inbox mock
  became a centered, undecorated, translucent floating window with
  one rule's worth of commands (`floating enable, resize set,
  move position center, opacity 0.93, border none`). Per-pixel
  transparency is not available — qutebrowser never requests a
  translucent window surface, so page CSS transparency dies at an
  opaque backing and uniform sway opacity is the entire palette.
  Dark pages at 0.93–0.96 read well over a workspace; light pages
  go hazy.
- Cross-application opening needs no desktop environment. Backends
  are unsandboxed local processes that can spawn windows and speak
  sway IPC directly; `xdg-open` plus the freedesktop MIME database
  (already used by Mediatron's `mediatron-external:` scheme handler)
  is the free fallback; and a small `castle-open` resolver verb
  consulting a declared association map — public mechanism, resident
  overrides as private configuration — would put opening policy in
  one place, where agent judgment can eventually sit.

Rules the session concluded are load-bearing, recorded here so the
spec starts from them — and which must land in the brief or
`docs/state/` when this entry is promoted, rather than vanish with
the file:

- **The frontend is a pure view.** Every action the UI offers exists
  first as a backend verb, and frontend state is never authoritative.
  The concrete test is reload-safety: a refresh at any moment
  reproduces the view from backend truth. A web app that fails this
  has rebuilt the illegible desktop inside the castle.
- **localhost is not a private channel.** Any local process — and
  outside pages, via DNS rebinding or blind cross-origin POSTs — can
  reach a local port. These backends carry the private layer, so
  authentication (per-app token, Host validation) is foundational,
  not retrofitted: Principle 01's secrets consequence at the
  application layer.
- **Activations that leave the web world are backend verbs or a
  registered scheme, never raw `file://` links** — from an http(s)
  app origin the browser blocks the navigation outright, and from a
  rendered `file://` document (the session's case) it displays the
  target itself; in neither path does anything resolve it.
- **"qutebrowser-friendly" is written down, not assumed**: semantic
  clickable elements so hints work, no capturing of normal-mode
  keys, honors `prefers-color-scheme`, reload-safe.

**Where the design discussion took it (amended 2026-09-09).** A
resident–agent design discussion the same day extended the proposal
well past the window shell. Decisions are the resident's; proposals
are marked as such and bind nothing until a spec ratifies them.

- *The platform is the real work.* The chromeless browser is the
  easy, already-derisked part. The substantial system is the backend
  that lets agents dynamically create and serve web applications
  with mediated filesystem access (resident). Nothing in that
  mechanism is castle-specific: it must not depend on Castle Turing,
  and the castle is its first tenant (resident) — Principle 01 with
  the private layer arriving entirely through deployment
  configuration.
- *Mediatron takes the role, and the name* (resident's decision). A
  document is one medium among the media it serves; the existing
  renderer stays as the first medium, and the growth is a deliberate
  re-founding of Mediatron's vision in its own repo, not an
  amendment. `mediatron serve <dir>` is the intended agentic verb.
  This resolves the naming question below differently than posed: no
  separate shell name — renderer, viewport, server, and kit are
  named components of Mediatron re-founded.
- *Apps are data, not processes* (proposed in discussion; the spec's
  first fork to ratify). One declared, audited backend owns ports,
  auth, and all filesystem access, exposing capability-scoped verbs;
  an agent "creates an app" by authoring frontend artifacts plus a
  manifest naming the verbs and scopes it needs. Creating an app is
  writing files — reviewable, rollbackable — and no dynamically
  created privileged process ever exists.
- *Serving and granting are different axes.* The resident's file
  browser counterexample: its assets are kilobytes, its data scope
  is the home directory, so the served directory cannot double as
  the grant. Manifests *request* scopes; grants are a separate act
  recorded in resident-side configuration, never self-asserted by
  the manifest's author. Enforcement needs real path containment
  (openat2/RESOLVE_BENEATH semantics, not string prefixes). The OS
  uid is the ceiling; grants only narrow within it.
- *The resident authenticates zero times* (resident's requirement).
  Auth is provenance, not login: per-app token carried once in the
  launch URL (the Jupyter pattern), exchanged for a SameSite cookie
  so reload-safety survives, custom-header requirement on
  state-changing verbs, Host validation, loopback binding. The
  agent's path is a unix socket with kernel peer credentials — no
  tokens at all. Noted at amendment time: the engine (Chromium 140
  via QtWebEngine) predates Chromium 142's Local Network Access
  protections, so server-side defenses stand alone today and remain
  primary after any engine upgrade.
- *The verb schema is the application; every surface is a derived
  view* (discussion). GUI, TUI, CLI — and the agent's own tool
  interface — are renderings of one schema. The resident endorsed
  the reverse implication: derived CLIs (the AWS CLI / kubectl
  precedent) make CLI consistency structural too.
- *A Castle UI Kit replaces raw HTML as what agents author*
  (resident's proposal): a small, highly opinionated component
  vocabulary, so house style and reload-safety are properties of
  the kit's runtime rather than findings of a checker. A missing
  widget is a kit change with review, never an inline exception.
  The kit renders to multiple targets — web via the viewport, TUI
  via a bought engine (resident) — and TUI renderability is the
  abstraction-level test: a component that cannot render in the
  terminal is specified too low.
- *Derive a default* (proposed in discussion; resident confirmed).
  The platform derives a working default surface from a verb schema
  alone — the Django-admin/Swagger precedent — so no app starts from
  a blank page and agent design effort is spent only above the
  floor.
- *The agent experience is verbs, all non-interactive*: schema
  discovery, scaffold, fixture-posed serving (the pure-view
  invariant makes every UI state a committed, reproducible pose),
  `inspect` returning the kit tree as text (perception in the
  authoring grammar), executable contract checks, logs. This
  generalizes castle-modal's every-flow-drivable-non-interactively
  invariant and matches the published ACI lessons; a research round
  on ACIs for GUI-building specifically is a candidate, since the
  literature covers only repo-editing.
- *Founding order, from walking the castle-modal story*: the first
  Mediatron slice is serve + token handoff + a generic unix-socket
  bridge + window identity — no filesystem verbs until an app
  demands them. Castle-side, the modal's operations decouple onto a
  socket so TUI and GUI become two clients of one verb layer. And
  the convention itself must land before the pipeline is handed a
  GUI task: today a competent worker could build a bespoke local
  server without violating anything on `main`, and this entry
  merging is what makes that the improvise path rather than an
  open option.

**Open questions.** The display-authority boundary: backends that
spawn windows and speak sway IPC are the agent driving the display
one layer above pixels. `docs/vision.md` grants exactly that — the
window manager is the agent's hands — but the line between driving
the window manager (granted) and operating an application's
frontend (excluded by this proposal) is not stated anywhere and the
spec must draw it. Window identity: every window of the shared
instance carries app_id `org.qutebrowser.qutebrowser`, and sway
rules plus the agent's window management need per-app identity — a
title-tag convention is the leading candidate, undecided. Crash
domain: the shared browser process takes every castle window down
together (renderer crashes stay isolated); whether that is
acceptable is a decision, not a default. Service lifecycle: ports,
systemd user units, and who declares them — a NixOS module shape
suggests itself. Naming: the window shell is not
Mediatron-the-renderer; the renderer is one client of the shell,
and the shell needs its own name before "mediatron" quietly means
both. And whether this hardens as a numbered principle or only as
the first application's brief.
