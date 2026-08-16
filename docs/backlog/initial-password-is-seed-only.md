# Document that initialHashedPassword seeds only once

**What.** Record — in `docs/private-layer.md`, next to the option
itself — that `castle.admin.initialHashedPassword` applies only when the
account is first created, and cannot be used to change or rotate the
password of a machine that already has one.

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

**Open questions.** Is a doc note sufficient, or should something
detect the divergence and say so — an activation-time warning when the
live hash differs from the declared seed, distinguishing "resident
changed their password" (fine, expected) from "someone edited the seed
expecting it to take effect" (not fine)? Those two look identical from
the outside, which may mean the distinction cannot be made and the doc
note is the whole answer.
