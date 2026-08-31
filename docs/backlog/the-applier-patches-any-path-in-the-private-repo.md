# The applier will patch any path in the private repo, including the secrets ones

**What.** `castle apply`
(`docs/tasks/0026-apply-validate.md`) applies whatever paths the
approved patch touches, anywhere in the resident's configuration
checkout. There is no allow-list and no deny-list. A proposal that
edits `secrets.yaml` or `.sops.yaml` is applied exactly like one that
edits `resident.nix`.

**Why it matters.** `.sops.yaml` in particular deserves its own
sentence: **nothing in Nix reads it**, so a change to it is invisible to
every check this design can run — the flake still evaluates, the
toplevel still builds — while it silently changes which recipients
future encryptions target
(`docs/private-layer.md`, "Secrets"). A resident approving a diff they
read would still be approving that change, so this is not a hole in the
authorization; it is a hole in what the *machine* can tell them about
the consequences. Everything else the applier writes is a `.nix` file
whose breakage the optional evaluation check would surface.

**Why it was not built with 0026.** Not because the argument is weak —
it is good — but because there is nothing to ground a list on.
`docs/private-layer.md`'s own "minimum contents" listing predates
`docs/tasks/0031-secrets-tooling.md` and names four files; the secrets
files are documented elsewhere in the same page. Inventing an interface
quietly, inside an applier, is worse than not having one: the list
would immediately be the de facto definition of what a private layer
may contain, decided by whoever was writing a refusal predicate that
afternoon.

**What we already know.**

- 0031 put `secrets.yaml` and `.sops.yaml` in the private repo by name.
- The applier already refuses on the resident's own uncommitted work
  under the patch's paths, so the predicate hook exists; what is
  missing is the list, not the mechanism.
- The task prompt's exclusion "do not add secret management" does not
  forbid *refusing* to patch those files — a refusal predicate is not
  secret management — so this is genuinely deferred rather than out of
  scope.
- An allow-list and a deny-list fail in opposite directions. A deny-list
  is easy and leaves everything unlisted applyable, which is the status
  quo with two exceptions. An allow-list is safer and immediately
  wrong the first time a resident keeps something the framework has not
  heard of, which Principle 02 says is their business.

**Open questions.** Allow-list or deny-list? Where is the file
inventory it grounds on written down, and who owns it —
`docs/private-layer.md`, an option, or the module? Is the right answer
a refusal at all, or a louder review screen for a patch touching a file
whose consequences nothing can check? And is `flake.lock` in the same
category: nothing here proposes changes to it today, but a patch that
did would be repinning the resident's whole dependency set.
