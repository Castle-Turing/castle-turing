# A resident who wants "the secret *is* my password" has no way to say so

**What.** Decide, deliberately and on its own terms, whether this
project should offer `users.mutableUsers = false` — and if so, as what:
a framework default, a host-level choice, or a documented thing a
private layer sets for itself with the consequences written down.

**Why it matters.** `castle.admin.hashedPasswordFile`
(`docs/tasks/0032-password-hash.md`) reads like a declarative password
and is not one. It seeds an account at first creation and is ignored
forever after, because `users.mutableUsers` is left at its NixOS default
of `true`. A resident who wants the honest declarative version — "the
encrypted secret is my password, full stop; I change it by editing the
secret and rebuilding" — can have it today only by setting
`users.mutableUsers = false` themselves, and nothing anywhere tells them
that trade exists or what it costs.

Note the framing, because this entry started life as a different and
wrong one. It is **not** "fix a revert bug." There is no revert bug:
`mutableUsers = true` is precisely what makes a `passwd` change
permanent, and 0032 verified against the pinned nixpkgs that no rebuild
ever overwrites an existing account's shadow entry. The gap is an
*absent capability*, not a broken one.

**What we already know.**

- **What flipping it actually does.** NixOS's own description is blunt:
  "you cannot change user passwords, they will always be set according
  to the password options." So `passwd` fails loudly and immediately
  rather than appearing to work — which, on this project's usual
  instincts, is the *better* failure. A surface that reports success for
  something that does not persist is the class of defect this project
  exists to remove. There just isn't one here to remove yet.
- **The blast radius is much larger than one password.**
  `users.mutableUsers` governs whether **every** account and group on
  the machine is managed declaratively, or left to
  `useradd`/`groupadd`/`passwd` at will. Deciding it as a side effect of
  a password task would have been deciding far more than a password.
  That is why 0032 declined to, and why this is a separate question with
  its own clarifying questions rather than a paragraph in someone
  else's brief.
- **It silently neuters the password-reminder machinery**, and this is
  the consequence most likely to be missed. `modules/base`'s
  `castle-password-reminder-check` compares the account's live shadow
  hash against the seed file's contents and nags until they differ. The
  only thing that lets them differ is the write-to-shadow gate that
  `!mutableUsers` removes — so with `mutableUsers = false` the two can
  never diverge, the check becomes permanently inert, and its banner's
  advice ("run `passwd` to set your own") becomes advice for a command
  that no longer works. Whatever this question decides has to decide
  what happens to that mechanism too: retire it, gate it on
  `mutableUsers`, or replace its message.
- **sops-nix has a constraint here worth checking before designing.**
  Its `secrets-for-users` module asserts that `neededForUsers` plus
  `systemd.sysusers.enable` requires `users.mutableUsers` to be *true*
  (upstream issue 475). This project sets neither `systemd.sysusers` nor
  `services.userborn`, so the assertion does not bite today — but any
  design that flips `mutableUsers` should know the combination exists
  and is refused.
- **`docs/backlog/initial-password-is-seed-only.md` is the same
  territory from the other side**: it asks whether the seed-only
  behaviour should be *detected and reported*. If this entry is answered
  with "offer immutable users," that one may partly dissolve; if it is
  answered with "no, stay mutable," that one becomes more important, not
  less. They should probably be specced together or in a deliberate
  order.

**Open questions.** Is this a framework default, a host module's
choice, or purely private-layer with documentation? What happens to the
reminder machinery under it — retired, gated, or reworded? Does a
machine with immutable users still want a recovery path that does not
depend on rebuilding (the SSH-as-root route 0032 documents assumes
`passwd` works)? And is "declarative passwords" even the right unit of
the question, or is the real one "does this project want declarative
accounts at all," of which the password is one field?
