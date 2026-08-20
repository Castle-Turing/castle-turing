# The installer advertises itself; the installed system does not

**What.** `modules/installer.nix` enables Avahi and publishes an mDNS
name, so a freshly booted installer is reachable at
`castle-installer.local` with nothing to look up. `modules/base` does
not, so the *installed* system announces nothing and can only be
reached by an address someone found some other way. Decide whether the
installed system should be discoverable too, and on what terms.

**Why it matters.** It is backwards. The ephemeral, throw-away
environment is the discoverable one; the machine that is supposed to
host a resident's agent for years is the one you have to hunt for. For
a project whose premise is a machine an agent can reach and act on,
"find the IP first" is a real gap in the first step of every session.

Observed directly: after the first from-scratch reinstall, reaching the
installed host required guessing that DHCP had reissued the same lease
the installer had held. That guess happened to be right. Had it not
been, the options were reading a router's admin page or walking to the
machine — on a laptop with no Ethernet port, whose Wi-Fi association is
itself manual on first boot (see `docs/tasks/0003-findings.md` finding
#1, still open).

The installer module already contains the working mechanism, so this is
mostly a question of whether to extend it rather than how.

**Why it is not obvious, and why this is a backlog entry rather than a
brief.** mDNS broadcasts a hostname on every attached network,
continuously. That is a different exposure profile for a machine that
travels — cafés, conferences, client offices — than for an installer
that lives for twenty minutes on a bench. The questions worth settling
before writing a spec:

- Should it be on by default, or an option a private layer opts into?
  Principle 01 wants the mechanism public and the choice private, which
  suggests an option; the resident's convenience suggests a default.
- What name does it publish? `networking.hostName` is a host fact, but
  a hostname broadcast on public networks is arguably resident-adjacent
  information, which is a Principle 01 question, not a technical one.
- Should it be conditional on the network — advertise on a home LAN,
  stay quiet elsewhere? NetworkManager knows the connection; nothing
  currently consumes that.
- Does this overlap with what a private-layer Wi-Fi profile would want
  anyway? It no longer shares a blocker with one: the secrets mechanism
  both were waiting on landed in `docs/tasks/0031-secrets-tooling.md`,
  and a resident can now declare a Wi-Fi profile whose PSK comes from an
  encrypted file (`docs/private-layer.md`, "Secrets"). That makes this
  entry *more* pointed rather than less. A machine that joins a known
  network by itself on first boot, and still cannot be found on it
  without reading a router's lease table, is exactly the gap this
  describes — the first half of the unattended story now works and the
  second half does not. Whether the two should be declared together in
  one private-layer block, or stay separate mechanisms, is the open
  question that replaces the old shared-blocker one.

**What we already know.**

- `modules/installer.nix` enables `services.avahi` with `publish.addresses`
  and `openFirewall`, and prints the resulting `.local` name on the
  console. That is a working reference implementation.
- `modules/base` has no Avahi, no `nssmdns`, and no discovery mechanism
  of any kind.
- `docs/backlog/headless-recovery.md` and
  `docs/backlog/declarative-wifi.md` both touch reachability and should
  be read alongside this one; the three may collapse into a single
  spec.
