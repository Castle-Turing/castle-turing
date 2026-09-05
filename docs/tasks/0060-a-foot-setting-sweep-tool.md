Title: Task 0060 — a foot setting sweep tool
Model: standard
Model-because: the pattern is proven twice in-tree — this brief applies
`tools/font-sweep.sh`'s established shape (dedicated workspace, tiled
panes, shared sample, tear-down-on-Enter) to another foot setting.
Nothing here decides authority, record semantics, or contract text; a
wrong call costs a tool that needs a second pass, not a wrong grant.

# What this implements

`docs/backlog/no-sweep-tool-for-previewing-foot-appearance-settings-like-padding.md`
(promoted and deleted by this commit) named padding as the motivating
case but wrote "settings like padding" — this brief settles that as a
scope question before writing any code.

## The gap

`tools/font-sweep.sh` compares font specs side by side on a live panel,
and `tools/console-font-sweep.sh` does the same for the virtual
console. Padding has no equivalent: a resident who wants to compare a
few `pad` values has no way to preview them live, and is left guessing
a number or hand-running throwaway `foot -o pad=...` instances.

This matters for the same reason the two existing sweep tools exist.
`tools/font-sweep.sh`'s own header names the precedent directly: a
cursor size was once argued into place instead of looked at, and
shipped dramatically wrong (`docs/tasks/0013-first-deploy-findings.md`).
Padding is exactly this class of value — a perceptual appearance
setting with no answer derivable from a spec sheet — so it gets a
sweep tool rather than a guess, the same way font sizes did.

## Scope decision: one tool, generalized over the override key

Padding is not the only foot setting in this category. foot exposes a
generic override flag, confirmed against the installed build on this
machine:

```
$ foot --help
  -o,--override=[section.]key=value        override configuration option
$ man foot
     -o,--override=[SECTION.]KEY=VALUE
         Override an option set in the configuration file. If SECTION is
         not given, defaults to main.
$ man foot.ini
     pad
         Padding between border and glyphs, in pixels (subject to output
         scaling), in the form
             XxY [center | center-when-fullscreen | ...]
         or
             RIGHTxTOPxLEFTxBOTTOM [center | ...]
```

Any single-value `[main]` setting foot exposes this way —
`letter-spacing`, `resize-delay-ms`, `pad` itself — is the same
one-flag, one-surface, eyeball-it problem. A tool hardcoded to `pad`
would need to be re-forked, nearly verbatim, for the next one; the
backlog entry's own title said "settings like padding," not "padding."

So this implements **one tool, `tools/foot-setting-sweep.sh`, that
takes the override key as its first argument** and one foot pane per
remaining argument as the candidate values:

```
tools/foot-setting-sweep.sh pad 5x5 15x15 30x30
tools/foot-setting-sweep.sh pad "10x20x10x5 center"
tools/foot-setting-sweep.sh letter-spacing 0 1 2
```

Each pane launches as `foot -o "$key=$val" ...`. No validation of
`key` against a known list — foot itself rejects a bad key or a
malformed value when the pane launches, the same way `font-sweep.sh`
lets `foot --font=` fail on a bad spec rather than pre-validating fonts
it doesn't understand.

**Non-goal: the UI-chrome surface.** `font-sweep.sh` has a `ui` mode
because a typeface question spans foot, GTK, and Sway chrome, all
readable through the same Pango description. Padding and its siblings
are foot-only settings — swaynag and GTK have no `pad` equivalent — so
this tool has no second mode. If a future setting needs a second
surface, that is a reason to extend this tool then, not to speculate
about it now.

**Non-goal: a `castle.display` option.** There is currently no
padding option in `modules/desktop/default.nix` (unlike
`terminalFontSize`, which `font-sweep.sh` was built to re-calibrate for
an option that already existed). This tool does not add one. It only
gives a resident who wants to pick a padding value — or add the option
in a later task — a way to look before choosing, the same
mechanism/configuration split Principle 01 draws between
`font-sweep.sh` and `terminalFontSize`'s own value. Wiring a chosen
value into a module option is separate work for whoever picks a number
after using this tool.

# Design

`tools/foot-setting-sweep.sh` follows `tools/font-sweep.sh`'s terminal
mode structure directly, with the font-dir/fontconfig machinery
dropped (irrelevant here — no font is being loaded from outside the
system):

- **Usage-as-header.** Same `usage()` that reads the script's own
  leading comment block up to the first non-comment line, for the same
  reason documented in `font-sweep.sh`: a hardcoded line range drifts
  and silently truncates `--help`.
- **`hold()`**, verbatim pattern: block on Enter when stdin is a
  terminal; when it isn't (an agent driving this non-interactively),
  print instructions and sleep-and-wait in a loop rather than a bare
  `sleep`, so a delivered `SIGTERM` tears the sweep down immediately
  instead of being swallowed until the sleep returns.
- **Named workspace** (`foot-setting-sweep`), tiled panes, one per
  value, `sleep 0.4` between spawns (matches font-sweep.sh — avoids a
  burst of `--app-id` windows landing before Sway can tile them).
- **Origin-workspace capture and restore**, same `awk`/`sed` parse of
  `swaymsg -t get_workspaces`, same `|| true` tolerance for a parse
  miss degrading to "does not switch back" rather than aborting under
  `set -o pipefail` before any pane opens.
- **Guarded `cleanup()` trap** on `EXIT INT TERM`, idempotent via a
  `cleaned` flag, same as both existing tools.
- **Sample text**: shorter than `font-sweep.sh`'s (that one is tuned to
  expose letterform ambiguity; padding is a spacing question, so the
  sample only needs to fill the pane and report its own column/row
  count so a resident can see how much text a given padding leaves
  room for).
- Each pane's label is the literal `key=value` string passed to `-o`,
  printed by the sample script, so what's on screen names exactly what
  produced it.

Argument handling:

- `--help`/`-h` prints usage and exits 0, checked before anything else.
- First positional argument is the override key (bare, e.g. `pad`, not
  `main.pad` — `[SECTION.]` is optional and defaults to `main` per
  `man foot`, and no setting this tool is for lives outside `[main]`).
- At least one value required after the key.
- Preflight checks, each a distinct `die` message: `foot` on `$PATH`,
  `swaymsg` on `$PATH`, and `swaymsg -t get_version` reachable (needs a
  running Sway session).

# Verification

Done without hands, on this machine:

- `shellcheck tools/foot-setting-sweep.sh` — clean (exit 0), same as
  `tools/font-sweep.sh` and `tools/console-font-sweep.sh` run alongside
  it for comparison.
- `tools/foot-setting-sweep.sh --help` prints the header and exits 0.
- Argument-handling `die` paths exercised directly, each with the
  intended message and exit 1: no key given; a key with no values; a
  scratch `$PATH` containing every normal binary except `foot`; a
  scratch `$PATH` containing every normal binary except `swaymsg`.
  (Excluding just one binary from `$PATH` took a purpose-built scratch
  directory rather than a shorter `$PATH` — `foot` and `swaymsg` live
  in the same directory on this machine, so a naive "drop that
  directory" test silently removed both and proved nothing.)
- The `-o [section.]key=value` override flag and the `pad` option's
  syntax confirmed against `man foot` / `man foot.ini` on the dev
  machine, not from memory (quoted verbatim above) — installed foot is
  1.27.0.

This development machine turned out to have a live Sway session
reachable from the sandbox, so the one step this brief expected to be
human-only ran anyway: `tools/foot-setting-sweep.sh pad 5x5 20x20
"10x20x10x5 center"` opened three tiled panes on a workspace named
"foot-setting-sweep", each labelled with the exact `key=value` string
passed to `-o`, and pressing through teardown (via a bounded `timeout`,
standing in for Enter) closed all three panes and returned focus to the
original workspace with nothing left behind. That is a real run, not a
substitute for one — but it is not the calibration step. Nobody has
looked at these panes and judged which padding *reads well*; that
judgment, on the panel it's meant for, is still the one thing left for
a human, the same as it was for `terminalFontSize` and
`docs/tasks/0013-first-deploy-findings.md`'s cursor size before it.

# File-by-file change list

- `tools/foot-setting-sweep.sh` — new, executable.
- `docs/backlog/no-sweep-tool-for-previewing-foot-appearance-settings-like-padding.md`
  — deleted, promoted into this brief.
- This brief.

# Non-goals

Adding a `castle.display` padding option. A `ui`-surface mode (no
GTK/swaynag equivalent exists for `pad`). Validating override keys or
values against a known list — foot's own rejection at pane-launch time
is the validation, the same as `font-sweep.sh` for a bad font spec.
