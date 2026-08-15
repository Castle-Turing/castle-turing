# Generalize the host IP in the findings doc

**What.** Replace the four literal `192.168.2.54` occurrences in
`docs/tasks/0003-findings.md` with the `<host-ip>` placeholder the rest
of the repo uses.

**Why it matters.** Small, but it is an inconsistency in exactly the
place this project claims to be careful: `hosts/xps9370/README.md` uses
`<host-ip>` everywhere for the same value, while the findings doc
records a real address from the resident's home network. Nothing is
exposed — it is a non-routable RFC1918 address in an evidence log — but
the repo's own convention should hold uniformly, and a reader
copy-pasting from the findings doc gets a command that silently targets
nothing.

**What we already know.**

- Flagged by a conventions review over merged `main`; judged acceptable
  at the time as evidence, then judged inconsistent on a second look.
  Both readings are defensible, which is why it is here rather than
  fixed in a hurry.
- The lines are in finding #11's verification transcript, where the
  address is incidental — the evidence is the generation numbers and
  the round-trip, not the host.
- Worth doing as a ride-along with the next docs change rather than its
  own PR.

**Open questions.** Does the evidence value of a real transcript
outweigh the convention? (Probably not — the transcript reads the same
with a placeholder.)
