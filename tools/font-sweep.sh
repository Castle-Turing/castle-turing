#!/usr/bin/env bash
# tools/font-sweep.sh — compare fonts side by side on the actual panel.
#
# WHY THIS EXISTS (read this before touching the script)
#
# Every display number in docs/tasks/0017-legible-defaults.md was picked
# by looking at this panel, not by reasoning about DPI. That was a
# deliberate reaction to docs/tasks/0013-first-deploy-findings.md, where
# a cursor size was argued into place (48, to "compensate" for a 2.0
# output scale that Sway already applies) and shipped dramatically wrong
# — a mistake no amount of further reasoning would have caught, and that
# thirty seconds of looking did.
#
# So 0017 tells its reader to re-run the sweep rather than edit a digit.
# That instruction is worthless if the sweep only ever existed as
# throwaway commands in somebody's session, which is exactly what
# CLAUDE.md means by "a step that will repeat belongs in a harness
# before it repeats."
#
# Principle 01 split: the mechanism (open N panes, same sample, one
# variable) is here in public; the faces and sizes you sweep are
# arguments, and whichever wins belongs in your private layer or a host
# module, never hardcoded below.
#
# USAGE
#
#   tools/font-sweep.sh terminal 'monospace:size=11' 'monospace:size=12'
#   tools/font-sweep.sh terminal 'Iosevka Slab:style=Light Extended:size=12'
#   tools/font-sweep.sh ui 'DejaVu Sans 11' 'Iosevka Aile 11'
#
#   # a font that is not installed system-wide (a store path is fine):
#   tools/font-sweep.sh --font-dir "$(nix build --no-link --print-out-paths \
#       nixpkgs#iosevka-bin)/share/fonts" terminal 'Iosevka:size=12'
#
# `terminal` opens one foot pane per spec, tiled, each printing the same
# sample and labelling itself. `ui` stacks one swaynag bar per spec —
# that is the surface Sway titlebars, swaynag, and (via the same Pango
# description) GTK chrome are judged on.
#
# Everything is torn down when you press Enter: panes closed, bars
# dismissed, original workspace restored. Nothing is written to your
# home — fonts passed with --font-dir are exposed through a scratch
# XDG_DATA_HOME, so fontconfig sees them for these panes only and no
# `fc-cache` runs against ~.
#
# NOT for the virtual console. The VT cannot render an outline font at
# all; see tools/console-font-sweep.sh for that half.
set -euo pipefail

die() { printf 'font-sweep: %s\n' "$*" >&2; exit 1; }

# Keep the sweep on screen until the human is done looking. With a
# terminal on stdin that means "press Enter"; without one it means "wait
# to be killed". The second case is not hypothetical — an agent driving
# this from a non-interactive shell gets EOF on `read` instantly, which
# tore the whole sweep down before anything could be seen.
hold() {
  if [ -t 0 ]; then
    printf '%s\n\n' "$1"
    read -r _ || true
  else
    printf 'stdin is not a terminal; leaving this up. Ctrl-C, or kill %s, to tear down.\n\n' "$$"
    # `sleep &` + `wait`, not a bare `sleep`: bash defers trap delivery
    # until the running foreground *external* command returns, so a plain
    # `while :; do sleep 3600; done` swallows SIGTERM for up to an hour
    # and the teardown trap never fires. `wait` is interruptible, so the
    # trap runs immediately. Observed for real — a killed sweep left its
    # windows on screen and the next sweep stacked on top of them.
    while :; do sleep 3600 & wait $! || break; done
  fi
}

font_dirs=()
while [ $# -gt 0 ]; do
  case "$1" in
    --font-dir) [ $# -ge 2 ] || die "--font-dir needs a directory"
                font_dirs+=("$2"); shift 2 ;;
    --help|-h)  sed -n '2,45p' "$0"; exit 0 ;;
    *)          break ;;
  esac
done

mode="${1:-}"; shift || true
case "$mode" in
  terminal|ui) ;;
  *) die "first argument must be 'terminal' or 'ui' (got '${mode:-nothing}'); --help for usage" ;;
esac
[ $# -ge 1 ] || die "give at least one font spec to compare"

command -v swaymsg >/dev/null || die "swaymsg not found — this needs a running Sway session"
swaymsg -t get_version >/dev/null 2>&1 || die "cannot reach Sway's IPC socket (\$SWAYSOCK unset?)"

work="$(mktemp -d)"
pids=()

# Expose any --font-dir to fontconfig for child processes only. fontconfig's
# stock config includes <dir prefix="xdg">fonts</dir>, i.e. $XDG_DATA_HOME/fonts,
# so pointing XDG_DATA_HOME at a scratch tree with symlinks in it adds those
# fonts for exactly the processes we launch and nothing else on the system.
fontenv=()
if [ ${#font_dirs[@]} -gt 0 ]; then
  mkdir -p "$work/xdg/fonts"
  i=0
  for d in "${font_dirs[@]}"; do
    [ -d "$d" ] || die "--font-dir '$d' is not a directory"
    ln -sfn "$(realpath "$d")" "$work/xdg/fonts/dir$i"
    i=$((i + 1))
  done
  fontenv=(env "XDG_DATA_HOME=$work/xdg")
fi

# The sample. Deliberately not lorem ipsum: these are the four things
# actually read on this machine, and the letter pairs that decide whether
# a coding face is legible (Il1|, O0o, rn/m, cl/d) rather than pretty.
cat > "$work/sample.sh" <<'SAMPLE'
#!/usr/bin/env bash
printf '\n  \033[1m=== %s ===\033[0m\n\n' "$1"
cat <<'EOF'
  # prose
  The quick brown fox jumps over the lazy dog. 0123456789

  # the letters that actually decide a coding face
  Il1| O0o rn/m cl/d ,.;: `'" -_= {}[]()<> a@ 8B 5S 2Z 9g
  hash: 3f8a2c1e9b7d4056  path: /nix/store/wq3x-foo-1.2.tar.gz

  # code
  castle.display = {
    scale            = lib.mkDefault 2.0;
    terminalFontSize = lib.mkDefault 12;
  };

  # diff
  - font pango:monospace 8.000000
  + font pango:DejaVu Sans 11

  # dense log
  Aug 17 16:13:02 hostname sway[1843]: [sway/config.c:842] Loading config
EOF
printf '\n  columns: %s   rows: %s\n\n' "$(tput cols)" "$(tput lines)"
# Hold the pane open. The sweep script closes it on teardown.
while :; do sleep 3600; done
SAMPLE
chmod +x "$work/sample.sh"

# Remember where we came from so teardown can put you back. Parsed with
# awk rather than `grep -B`: "name" and "focused" are not a fixed number
# of lines apart in Sway's JSON, so a fixed -B window silently matched
# nothing — and under `set -o pipefail` a silent no-match killed this
# script before it opened a single window. Tolerate failure explicitly
# (`|| true`) so a parsing change degrades to "does not switch back"
# rather than "sweep mysteriously does nothing".
origin="$(swaymsg -t get_workspaces \
          | tr ',' '\n' \
          | awk '/"name"/ { n = $0 } /"focused": *true/ { print n; exit }' \
          | sed 's/.*"name": *"\([^"]*\)".*/\1/')" || true

# Guarded: the trap is armed on INT/TERM *and* EXIT, so a Ctrl-C would
# otherwise run this twice.
cleaned=0
cleanup() {
  [ "$cleaned" = 1 ] && return 0
  cleaned=1
  for p in "${pids[@]:-}"; do kill "$p" 2>/dev/null || true; done
  [ -n "${origin:-}" ] && swaymsg "workspace $origin" >/dev/null 2>&1 || true
  rm -rf "$work"
  return 0
}
trap cleanup EXIT INT TERM

if [ "$mode" = terminal ]; then
  # A named workspace, so a sweep never lands on top of real work.
  swaymsg 'workspace font-sweep' >/dev/null
  for spec in "$@"; do
    "${fontenv[@]}" foot --font="$spec" --app-id=font-sweep \
      -e "$work/sample.sh" "$spec" &
    pids+=($!)
    sleep 0.4
  done
  printf '\n%s pane(s) open on workspace "font-sweep".\n' "$#"
else
  for spec in "$@"; do
    "${fontenv[@]}" swaynag -f "$spec" -s 'close' \
      -m "$spec — the quick brown fox jumps over the lazy dog 0123456789. Titlebars, swaynag, GTK and Firefox chrome all read at this size." &
    pids+=($!)
    sleep 0.4
  done
  printf '\n%s bar(s) stacked at the top of the screen.\n' "$#"
fi

hold "Compare, then press Enter here to tear everything down."
