# An arrow key is three dismissals

**What.** Pressing the up-arrow while reading a rendered result in
`castle-modal` closes the window. The resident's reflex — scroll up to
see the top of a result too long for the screen — is read as a
dismissal, verified 2026-09-05 by driving the modal under a pty: the
process exits 0 on the keypress.

The mechanism is byte-at-a-time key reading. The modal's cbreak reader
takes `sys.stdin.read(1)`, and an arrow key arrives as a three-byte
escape sequence (`ESC [ A`). The first byte is indistinguishable from
a bare `Esc`, so one physical keypress becomes three logical ones: the
`ESC` backs out of the rendered result to the inbox list, the `[` is
"any other key" at the list and closes the window, and the `A` is left
in the terminal's input buffer for whatever reads it next. Every
navigation key a terminal emits — arrows, PgUp/PgDn, Home/End — is an
escape sequence, so every scroll-shaped reflex hits this.

**The aggravator.** Rendering a result spends the read cursor at
render time (task 0034, by design), so by the time the stray `ESC`
lands back on the list, the list already says nothing is waiting. The
accidental close therefore leaves no ambient trace of the record: the
resident saw the bottom of a result, lost the window trying to read
the top, and the inbox no longer offers it. `castle show <id>` and
`castle digest` still reach it, but only for a resident who knows to
go looking — the situation
[[nothing-ambient-says-items-are-waiting]] describes, entered through
a single reflex keypress. Scrollback is no workaround: the window the
scrollback belonged to is the thing that closed.

**Why it matters.** The dismissal-is-success posture — any key that
selects nothing closes, writing nothing — is load-bearing and correct:
no reflex keypress may authorize anything. But it currently cannot
tell a dismissal from the first byte of a navigation key, which
inverts its purpose at exactly one spot: the key a resident presses
*in order to keep reading* is the one that ends the reading. This is
the first UX complaint recorded from real use (the resident hit it
reading the first real proposal's records).

**Direction, not design.** After reading an `ESC`, the reader could
poll stdin briefly for continuation bytes and consume the whole
sequence, then treat unrecognized sequences as no-ops rather than
dismissals — bare `Esc` keeps its meaning, and arrow keys do nothing
(or eventually, scroll). Whether rendered-result reading should page
instead of relying on the terminal's scrollback is a separate, larger
question and deliberately not decided here.

**Why it can wait.** The project's gate, set by the resident
2026-09-05: Castle completes one request end to end before any surface
is refined. And the larger question of whether this surface stays the
front door at all is open (see
[[chat-mode-implies-a-conversational-turn-contract]]). Filed so the
complaint survives outside the conversation that found it.
