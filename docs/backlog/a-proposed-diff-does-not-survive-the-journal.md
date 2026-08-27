# A proposed diff does not survive the journal byte-for-byte

**What.** A worker turn's proposed diff reaches the journal through at
least four lossy transforms, and the record body is its only durable
copy. So the bytes a later task would hand to `git apply` are not the
bytes the tenant produced, and for some inputs cannot be.

Verified on `main` at `f7ebd32`:

1. **`agent/castle:3680`** —
   `diff_path.read_bytes().decode("utf-8", errors="replace").strip()`.
   `errors="replace"` destroys any non-UTF-8 byte irreversibly. The
   `.strip()` removes the patch's **trailing newline**, which is
   precisely what makes `git apply` report "corrupt patch" on a last
   hunk.
2. **`agent/castle:1111`** — `path.write_text(render_record(...))` with
   no `encoding=`, so the write is locale-dependent.
3. **`agent/castle:338`** — `text = path.read_text()`, locale-dependent
   again on the way back in.
4. **`agent/castle:342` and `:367`** — `lines = text.splitlines()` and
   then `body = "\n".join(lines[i + 1:])`. `str.splitlines()` splits on
   about ten characters, not one. A diff of a CRLF file, or of any file
   containing `\f`, `\v`, U+2028 or U+2029, does not round-trip: those
   bytes come back as `\n`.

**The repository already knows about (4) and guards the wrong half.**
`_reject_line_breaking_fields` (`agent/castle:371` onward) exists
because a field value carrying a line break breaks this format, and its
docstring spells out that the test is "a round trip through
`str.splitlines()`, not a search" and lists what that function treats
as a boundary. That guard is applied to **frontmatter fields only**. The
body — which is where the diff lives — never goes through it.

**Hashing the record after the fact would not close this.** No such
mechanism exists today — there is no checksum field on `result`
records anywhere in `agent/castle` — but it is worth naming why one
would not help if added: it would prove "this record has not changed
since the proposal was filed," not "these are the bytes the tenant
produced," because the mangling described above happens **before** a
record exists. A tamper-evidence seal over an already-corrupted
artifact is still a valid seal.

**Why it matters.** Nothing applies a diff today, so nothing is broken
right now — this is a latent defect, filed before the task that would
trip over it. `docs/tasks/0026`, not yet specced, is expected to turn
an approved proposal into a real edit in the private layer, and an
applier would be exactly the consumer that needs byte fidelity. The
failure mode is quiet and bad: a diff that applies cleanly in the
common case and corrupts, or refuses, on a file with CRLF line
endings or a form feed — which is to say, on someone else's
configuration rather than ours. The "docs are written for strangers"
rule has an analogue here.

It is also the kind of defect that gets discovered as "the applier is
buggy". The applier will be fine. The artifact it was handed was already
wrong.

**What we already know.**

- The tenant's own `$CASTLE_DIFF_FILE` temp file — the one byte-exact
  copy that ever exists — is unlinked unconditionally in a `finally`
  (`agent/castle:3825`, `:4114-4119`). Whatever fixes this has to keep
  something, somewhere, that was never round-tripped through the
  record format.
- The record format is line-oriented by design and that is not a
  mistake: it is what makes a journal readable by anything that can
  read text, which is the project's whole premise. A fix that makes
  records binary-safe by making them unreadable trades away more than
  it buys.
- So the likely shape is a **separate artifact**: the diff written once
  as its own file, byte-exact, with its digest stamped in the record —
  rather than the diff living *inside* a body that a markdown-shaped
  format is entitled to normalise. That also fixes the nonce-boundary
  machinery's reason for existing, which is currently doing the job of
  saying where the diff starts and stops inside prose.
- `docs/tasks/0024-config-target.md` shipped the current shape
  deliberately and its brief should be read before anything changes:
  the fenced-diff-in-a-body was chosen for legibility, and the
  legibility argument is still right. This entry is not an argument for
  reversing it, only for not making it the *only* copy.

**Open questions.**

- Does the byte-exact artifact live in the journal directory, beside
  the record, or outside it? The journal is append-only and
  file-per-record; a sidecar file is a new kind of thing in it.
- If the record body keeps a rendered copy for a human to read, and a
  sidecar holds the exact bytes, what happens when they disagree? Two
  sources of truth is the failure this project has repeatedly paid to
  avoid — the honest answer may be that the body's copy is explicitly
  decorative and nothing may key on it, the way the ```diff fence is
  already explicitly decoration.
- Should `parse_record`/`render_record` be made round-trip-exact for
  bodies regardless — with an explicit `encoding="utf-8"` and a
  splitter that only splits on `\n`? That is a smaller change than a
  sidecar and fixes three of the four transforms, but it cannot fix
  `errors="replace"`, which is upstream of the record entirely.
- Is there any existing record in a real journal whose body has already
  been altered by (4)? Journals are append-only, so a fix cannot
  retroactively repair one — worth knowing whether the problem is only
  prospective before deciding how much to build.
