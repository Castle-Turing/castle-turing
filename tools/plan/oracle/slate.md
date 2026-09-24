# Slate — the cursor is too small (worked example)

Requirements: ../../clarify/probes/cursor-too-small/oracle/requirements.md
Brief-budget: 3
Tasks: tasks

**This is a worked example, not approved work.** It decomposes a probe
artifact — the requirements document
`tools/clarify/probes/cursor-too-small/oracle/requirements.md`, which
carries `Probe:` in its own header — and its briefs have never been
transferred anywhere. Nothing here is eligible: no brief in any slate is
until the resident approves the slate, and no resident has read this one.
The label is the whole defence, because a slate is shaped exactly like a
slate that *has* been approved (Proposal 06's third salt discipline,
which is also why the clarify probe it decomposes carries its own).

Why this document and not an invented one: the format has to be
demonstrated on the artifact shapes it will actually meet.
`docs/planning.md` describes the slate; this is one, produced by running
the planner procedure in that document over a requirements document
another part of this repository already ships. The statement behind it
is milestone 1's — "my cursor is too small" — which is why every brief
here carries `Milestone: none`: that milestone is achieved and its
history lives in the records, not in `docs/state/MILESTONE.md`. A slate
for real work cites a live clause key from that file instead.

Two briefs against a declared budget of three. The unspent one is
printed by `plan check` on every run, where a reader can see the slack:
no rule can tell a generous budget from a right one, and pretending
otherwise is what item 1 of the slate-review checklist exists to catch.
The requirements document has four clauses and this slate has two
briefs, which is the direction the evidence says to expect trouble from
the other way round — an automated splitter would have produced more
briefs than this and implemented fewer of them
(`docs/research/decomposition-and-iteration-caps.md`).

Every criterion carries a disposition — `Check:` with the command that
exercises it, or `Manual:` with the step a person takes instead — because
a criterion the acceptance harness can neither run nor hand to somebody is
a verification plan that passes review and then verifies nothing
(`tools/accept/accept`). Two of the five are executable and three are not,
which is what work judged by eye looks like honestly accounted for. One of
the commands carries `<the other host>` as a placeholder rather than a
name: `[cursor-target-host]`'s ambiguity is open on the record, and a
check that quietly named a host would settle it.

This slate defers nothing, and that is deliberate. The `Deferred:` form
is in `docs/planning.md` and every rule about it is exercised in
`test/plan/run.sh`; deferring a clause this decomposition can perfectly
well carry would demonstrate the syntax by teaching the wrong thing.

## The briefs

### The cursor's size is chosen by looking at candidates on the panel [0002]

Model: cheap
Model-because: every judgment this work needs has already been spent in
    the requirements document — it names the mechanism (the sweep), the
    surface (the compositor's own pointer) and the arbiter (the
    resident's eye), and the one ambiguity left open on
    [cursor-value-by-sweep] is resolved in this brief's body by naming
    the tool rather than left for the implementer to pick. A deeper tier
    would arrive with nothing to decide. What would make a cheap tier
    wrong here is the brief being wrong about which sweep to run, and
    that is the sentence below rather than a question the implementer is
    asked to answer.
Milestone: none — worked example, not work
Traces: cursor-surface, cursor-value-by-sweep
Criterion: running the documented sweep command puts the candidate
    compositor cursor sizes on the internal panel at the same time, and
    restores the host's configured size when it exits. A run that prints
    the candidates, or shows them one after another, does not satisfy
    this: [cursor-visible-size] asks for a comparison, and a comparison
    needs both things visible at once.
Manual: run the sweep on the host, look at the candidates side by side,
    and press Enter; then confirm the pointer is back to the size the host
    is configured for. Nothing can look on the resident's behalf, which is
    the clause's own point.
Criterion: the pointer the candidates change is the one the compositor
    draws. If the sweep only moves an XWayland or GTK client's cursor,
    it is sweeping the surface [cursor-surface] excludes and the run
    fails however good the resulting number looks.
Manual: with the sweep open, move the pointer across a Wayland-native
    surface and an XWayland one; the candidates change the pointer on
    both, and the one that stops changing when the compositor's own
    setting is reverted is the one under test.
Criterion: the chosen number, and the fact that it was chosen by
    looking, are recorded in this brief's own pull request. A number
    that turns out to equal the panel scale times a constant is not
    evidence of anything either way — the clause rules out *deriving* it,
    not the value a derivation would have produced, so the receipt is
    the record of the look.
Check: gh pr view --json body --jq .body | grep -qiE 'cursor size.*(chosen|picked) by looking'

The tool is `tools/font-sweep.sh`'s cursor-size counterpart, invoked
against the internal panel at its default scale. `[cursor-value-by-sweep]`
records a lexical ambiguity here — "the sweep tool" names one of several
in this repository — held innocuous at the document's tolerance because
every sampled reading resolved it to the cursor-relevant one. Naming it
in this brief is transcription of that finding, not a decision on top of
it.

**The console cursor is not in this brief, and must not be quietly added
to it.** `[cursor-surface]` carries an open semantic ambiguity: whether
the cursor drawn on the console before a graphical session starts is
also in scope. The resident settled the compositor pointer and said
explicitly they had not thought about the console one. An implementer
who includes it has decided something the phase deliberately did not,
and one who writes "console cursor: out of scope" has decided the same
thing in the other direction. See the question below.

### The chosen size is what the compositor draws on that host [0003]

Model: standard
Model-because: the brief cannot name the host. `[cursor-target-host]`'s
    ambiguity is deferred on the record precisely because "this laptop's
    panel" names none, so the implementer reads the host off the
    deployment — and must stop and ask if more than one host answers to
    the description. A cheap tier following this brief would edit the
    first host module it found and record nothing about having chosen;
    not doing that is what the clause is about, so the tier has to be
    one that can notice the gap rather than fill it. It is not the deep
    tier either: once the host is identified the change is one value in
    one module.
Milestone: none — worked example, not work
Traces: cursor-visible-size, cursor-target-host
Requires: 0002
Requires-because: the value this brief commits is 0002's output. Run in
    the other order it would commit a number nobody had looked at, which
    is the one thing [cursor-visible-size] refuses by name — "a size
    derived by arithmetic and never looked at does not satisfy this
    clause even if it computes to the same number". The edge is the
    clause's, not a scheduling preference.
Criterion: after a rebuild and a switch on the host, the compositor's
    pointer on the internal panel at default scale is the size chosen in
    0002, shown in a screenshot of the running session. The configured
    value appearing in the module is not the criterion: task 0013 shipped
    a cursor size that was correct in the file and unusable on the panel,
    and this is the criterion that would have caught it.
Manual: rebuild and switch on the host, then photograph the pointer on the
    internal panel at default scale beside the candidate the sweep chose.
    A screenshot is the artifact; a person comparing them is the check.
Criterion: the value lives in that host's own module and nothing changes
    for a second host with a different panel. Checked by building the
    other host's configuration and finding the cursor size unchanged —
    [cursor-target-host] is a claim about where the value lives, so the
    demonstration has to be somewhere it does not.
Check: ! nix eval --json
    ".#nixosConfigurations.<the other host>.config.environment.sessionVariables"
    | grep -q XCURSOR_SIZE

## Questions

**Is the console cursor before a graphical session starts in scope?**
`[cursor-surface]`'s semantic ambiguity is `state=open` at
certainty 0.45 — asked as Q2 and answered only in part, the resident
having said they had not thought about it. No brief in this slate
includes or excludes it, because either would settle a question that is
the resident's, and a planner that settles one has stopped proposing.

In this slice a question travels through the session or the pull request
that carries the slate, file-native, exactly as the clarifying-questions
phase's do. Routing it to the modal is the question-routing work and is
deliberately not part of this seat.

## Coverage

All four clauses of the requirements document are carried by a brief's
`Traces:`, so this section declares no deferrals. The clause-to-brief
index is not written here either: `plan check` derives it from the
briefs' own `Traces:` lines and prints it, because two authored copies
of one mapping drift and the drift is silent.
