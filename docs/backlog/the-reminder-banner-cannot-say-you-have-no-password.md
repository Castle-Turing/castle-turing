# The reminder banner cannot say "you have no password"

*Found while fixing a worse version of the same thing in
`docs/tasks/0032-password-hash.md`. The code now behaves correctly; the
message it produces is still not literally true.*

**What.** The password-reminder banner has exactly two states: absent,
and "this account is still using its seeded initial password. Run
`passwd` to set your own." There is a third real state it cannot
express — **the account has no password at all**, because the seed
never decrypted at account creation.

Since 0032 the check leaves the marker untouched when the shadow field
is `!`, `!!`, `*` or empty (`modules/base/default.nix`). That is the
right behaviour: the previous code concluded "the resident ran
`passwd`" from the hash merely differing from the seed, and silenced
the banner forever on precisely the machine that most needed it. But
"leave the marker alone" means the banner shows, and what it shows says
the resident has a seeded password when they have none.

**Why it matters.** The state is reachable and is not exotic: a first
install with a missing or wrong age key creates the account locked, and
because `users.mutableUsers` is true, fixing the key and rebuilding
never repairs an account that already exists. A resident in that state
has to recover over SSH — which is the one thing the banner does not
mention, because it is written for someone who *has* a password and
should change it.

So the resident most in need of instruction gets the instruction
written for someone else. `passwd` is genuinely the remedy, which is
why the current wording was chosen over silence and why this is a
backlog entry rather than a defect: the message points the right way
while describing the situation wrongly. `docs/tasks/0015-filed-not-in-progress.md`'s
rule — a label must not cause the inaction it describes — is satisfied.
Its spirit is only half satisfied.

**What we already know.**

- The check already distinguishes the state; it just exits rather than
  saying anything. The information is available at exactly the point
  where a third message would be emitted, so this is a wording and
  scope question, not a detection problem.
- A third banner is a new resident-facing surface, which this project
  does not add casually — that is why 0032 declined to add one rather
  than inventing it under an autonomy grant.
- The recovery path already exists in prose:
  `docs/tasks/0032-password-hash.md`'s "The lockout story" documents
  SSH-and-`passwd`. Nothing links a resident sitting at the banner to
  it.
- **CI cannot reach this branch.** `test/vm-install/`'s fixture secret
  always decrypts, so the harness never creates a locked account, and
  the negative-path install that would exercise it was weighed and
  rejected in 0032's own "Considered and rejected". Whatever lands here
  needs to decide whether that stays true — the fix's entire value is
  in a failure mode CI never enters, which is the least safe place to
  leave something unproven.

**Open questions.**

- Is a third message right, or should the existing one simply be
  reworded to cover both cases honestly ("this account is not using a
  password you chose") — one string, no new surface, and true in both
  states?
- If it is a third message, does it name SSH recovery, and how does it
  do that without assuming SSH is reachable, which on a Wi-Fi-only
  machine with an undecrypted secret it may not be? That is
  `docs/tasks/0003-findings.md` finding #1's territory again.
- Does anything else read the marker's absence as "seeded password"?
  If a future surface does, it inherits this same wrong inference, and
  the honest fix may be to record *why* the marker is absent rather
  than only that it is.
