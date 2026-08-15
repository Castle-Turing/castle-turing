# Secrets tooling (sops-nix or agenix)

**What.** Bring encrypted-secret management into the flake, so the
private layer can hold credentials — not just plaintext personal
configuration.

**Why it matters.** Principle 01 consequence 1 says secret tooling
enters the repo *before the first credential exists*, so nothing
personal is ever committed. That deadline has not been missed yet only
because every credential so far has been kept out of both repos by
hand: Wi-Fi PSKs typed at the machine, GitHub and agent logins done
interactively by the resident. Each of those is a manual step that
blocks unattended reinstall, and the workarounds get less tenable as
the mail and agent layers arrive with API tokens that must live
somewhere.

**What we already know.**

- Two viable choices. `sops-nix` keeps secrets in YAML/JSON with
  per-key granularity — more AI-legible, which matters here. `agenix`
  is simpler but stores opaque per-file blobs. Both sit on `age` keys.
- Secrets live in the **private** repo, encrypted; the public repo
  defines only the slot. Encrypted-at-rest means even a private-repo
  access mistake leaks nothing.
- Blocked on this: declarative Wi-Fi provisioning
  (`declarative-wifi.md`), and any future mail/calendar/Slack
  credentials.
- Host key vs. resident key is a real decision: unlocking secrets at
  boot usually uses the machine's SSH host key, which means a
  reinstalled machine cannot read old secrets until re-enrolled.

**Open questions.** sops-nix or agenix? Where does the master key live
(hardware token, password manager, both)? What is the re-enrollment
story after a wipe — the reinstall flow must not become a puzzle. Does
the public repo ship an example encrypted file so a stranger can see
the shape without seeing contents?
