# Document that the admin password option seeds only once

**What.** Record — in `docs/private-layer.md`, next to the option
itself — that `castle.admin.hashedPasswordFile` applies only when the
account is first created, and cannot be used to change or rotate the
password of a machine that already has one.

**Since `docs/tasks/0032-password-hash.md`, this entry is about a
differently-named option and exactly the same behaviour.** That task
replaced `castle.admin.initialHashedPassword` (a hash string) with
`castle.admin.hashedPasswordFile` (a path read at activation), and
verified against the pinned nixpkgs that the seed-only property carries
over verbatim: `hashedPasswordFile`'s own description says the file "is
read on each system activation," which is true and easy to misread as
"and re-applied." `update-users-groups.pl` only writes the freshly-read
value into `/etc/shadow` for an account it is *creating*; for one that
already exists, both write paths are gated on `!mutableUsers`, and this
project has never set `users.mutableUsers` anywhere. So the surprise
this entry describes is unchanged in kind, and slightly worse in
availability: a file whose contents visibly change on every rebuild
looks even more like something that takes effect.

Everything below predates 0032 and is left as written; substitute the
new option name throughout.

**Why it matters.** This is a non-obvious property of an option the
project built a whole feature around, and the natural assumption is the
opposite one: that editing the hash in the private layer and
redeploying changes the machine's password. It does not, and nothing
warns you — the deploy succeeds, reports no error, and the password is
unchanged. A future resident or agent will lose time to this, and
"changed the config, the machine ignored it, no error" is exactly the
class of silent divergence between declared and actual state that this
project exists to eliminate.

**What we already know.**

- Observed on the reference host: the deployed system's shadow entry
  used yescrypt (`$y$`, what `passwd` produces) while the seeded value
  was sha-512 (`$6$`). The account had been given a password
  interactively during the install sessions, so NixOS correctly left it
  alone.
- The login-reminder mechanism in `modules/base` behaved correctly
  throughout — it compares the live shadow hash against the seeded one
  and stays quiet when they differ, which is the right behaviour but
  also means nothing surfaces the divergence.
- Consequence worth stating in the same place: after a from-scratch
  reinstall the seed *does* apply, so the password reverts to whatever
  the private layer declares and the reminder appears on first login.
  That is correct, but surprising if unexpected.

- **0032 wrote part of the doc note this entry asks for**, in
  `docs/private-layer.md`'s `castle.admin.hashedPasswordFile` bullet and
  in the option's own description. That does not close this entry: the
  open question below is about *detection*, not documentation, and
  nothing detects anything yet.

**Open questions.** Is a doc note sufficient, or should something
detect the divergence and say so — an activation-time warning when the
live hash differs from the declared seed, distinguishing "resident
changed their password" (fine, expected) from "someone edited the seed
expecting it to take effect" (not fine)? Those two look identical from
the outside, which may mean the distinction cannot be made and the doc
note is the whole answer.
