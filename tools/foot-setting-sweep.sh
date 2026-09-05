#!/usr/bin/env bash
# tools/foot-setting-sweep.sh — compare one foot setting side by side on
# the real panel.
#
# WHY THIS EXISTS (read this before touching the script)
#
# tools/font-sweep.sh compares font specs the same way, for the reason
# its own header gives: a cursor size was once argued into place instead
# of looked at, and shipped dramatically wrong
# (docs/tasks/0013-first-deploy-findings.md). Padding is the same class
# of value — a perceptual appearance setting with no answer derivable
# from a spec sheet — and had no comparable tool
# (docs/backlog/no-sweep-tool-for-previewing-foot-appearance-settings-like-padding.md,
# promoted into docs/tasks/0060-a-foot-setting-sweep-tool.md).
#
# Generalized over the override key rather than hardcoded to `pad`: foot
# exposes any [main] setting through the same `-o key=value` flag, so
# `letter-spacing`, `resize-delay-ms` and the next single-value setting
# someone wants to eyeball are the identical problem. See
# docs/tasks/0060-a-foot-setting-sweep-tool.md for why one generalized
# tool was chosen over a padding-only one.
#
# Principle 01 split: the mechanism (open N panes, same sample, one
# overridden setting) is here in public; which value wins belongs in
# your private layer or a host module, never hardcoded below. This tool
# does not itself wire a chosen value into any `castle.display` option —
# there isn't one for padding yet — it only lets you look before you
# pick one.
#
# USAGE
#
#   tools/foot-setting-sweep.sh pad 5x5 15x15 30x30
#   tools/foot-setting-sweep.sh pad "10x20x10x5 center"
#   tools/foot-setting-sweep.sh letter-spacing 0 1 2
#
# One foot pane per value, tiled on a dedicated workspace, each launched
# with `-o <key>=<value>` (foot's own override flag; SECTION defaults to
# `main` when omitted, per `man foot`) and printing the same sample,
# labelled with the exact `key=value` string that produced it.
#
# Everything is torn down when you press Enter: panes closed, original
# workspace restored. Nothing is written to any config file — this never
# touches foot.ini, only launches panes with a command-line override.
#
# NOT for GTK/Sway chrome. Padding and its siblings are foot-only
# settings with no swaynag/GTK equivalent, unlike a typeface question —
# see tools/font-sweep.sh's `ui` mode for that surface.
set -euo pipefail

die() { printf 'foot-setting-sweep: %s\n' "$*" >&2; exit 1; }

# Print the header comment as usage. Reads until the first non-comment
# line rather than a hardcoded line range — see tools/font-sweep.sh's
# `usage()` for why a fixed range drifts and silently truncates --help.
usage() { awk 'NR == 1 { next } /^#/ { print; next } { exit }' "$0"; }

# Keep the sweep on screen until the human is done looking. See
# tools/font-sweep.sh's `hold` for the non-TTY branch's reasoning: an
# agent driving this from a non-interactive shell gets EOF on `read`
# instantly, which would tear the whole sweep down before anything could
# be seen, and a bare `sleep` inside the loop would swallow SIGTERM for
# up to an hour instead of tearing down immediately.
hold() {
  if [ -t 0 ]; then
    printf '%s\n\n' "$1"
    read -r _ || true
  else
    printf 'stdin is not a terminal; leaving this up. Ctrl-C, or kill %s, to tear down.\n\n' "$$"
    while :; do sleep 3600 & wait $! || break; done
  fi
}

case "${1:-}" in --help|-h) usage; exit 0 ;; esac

key="${1:-}"; shift || true
[ -n "$key" ] || die "give a foot setting key (e.g. 'pad'); --help for usage"
[ $# -ge 1 ] || die "give at least one value to compare for '$key'"

command -v foot >/dev/null || die "foot not found"
command -v swaymsg >/dev/null || die "swaymsg not found — this needs a running Sway session"
swaymsg -t get_version >/dev/null 2>&1 || die "cannot reach Sway's IPC socket (\$SWAYSOCK unset?)"

work="$(mktemp -d)"
pids=()

cat > "$work/sample.sh" <<'SAMPLE'
#!/usr/bin/env bash
printf '\n  \033[1m=== %s ===\033[0m\n\n' "$1"
cat <<'EOF'
  The quick brown fox jumps over the lazy dog. 0123456789
  ,.;: `'" -_= {}[]()<>
EOF
printf '\n  columns: %s   rows: %s\n\n' "$(tput cols)" "$(tput lines)"
# Hold the pane open. The sweep script closes it on teardown.
while :; do sleep 3600; done
SAMPLE
chmod +x "$work/sample.sh"

# Remember where we came from so teardown can put you back. Same
# awk/sed parse and same `|| true` tolerance as tools/font-sweep.sh's
# `origin=` — see that script's comment for why a fixed -B window on
# `grep` broke this under `set -o pipefail`.
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

# A named workspace, so a sweep never lands on top of real work.
swaymsg 'workspace foot-setting-sweep' >/dev/null
for val in "$@"; do
  label="$key=$val"
  foot -o "$label" --app-id=foot-setting-sweep -e "$work/sample.sh" "$label" &
  pids+=($!)
  sleep 0.4
done
printf '\n%s pane(s) open on workspace "foot-setting-sweep".\n' "$#"

hold "Compare, then press Enter here to tear everything down."
