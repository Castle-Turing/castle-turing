#!/usr/bin/env bash
# tools/console-font-sweep.sh — compare virtual-console fonts by looking.
#
# WHY THIS EXISTS (read this before touching the script)
#
# The console is the surface you cannot preview from inside a Wayland
# session, and it is the one you need most when things are broken: the
# boot log, the greeter, and the emergency shell. On a HiDPI panel the
# kernel's built-in 8x16 font renders at roughly a millimetre — legible
# in principle, useless in the situation it exists for.
#
# It is also where reasoning failed hardest during
# docs/tasks/0017-legible-defaults.md. An early draft of that brief
# asserted that fbcon will not load a glyph taller than 32 pixels, and
# used it to argue Terminus was as large as the console could go. The
# claim was never tested and is false — spleen-32x64 loads fine. One
# `setfont` on a spare VT settled in seconds what a confident paragraph
# had got wrong, which is the entire argument for this script.
#
# HOW IT WORKS, AND WHAT IT TOUCHES
#
# Console fonts are PSF bitmaps loaded per virtual terminal, so this
# loads one candidate onto each spare VT and you compare by switching
# between them (Ctrl+Alt+F3, F4, ...). A sample is reprinted every few
# seconds on each, because activating a VT can start a getty whose login
# prompt would otherwise clear the screen — the prompt itself is a fair
# sample too.
#
# **This needs sudo and it changes VT state.** `setfont` is privileged.
# The script restores the kernel default on every VT it touched when you
# press Enter, including on Ctrl-C — but if it is killed outright, reset
# by hand with `sudo setfont -C /dev/ttyN` (no font argument) or reboot.
# It deliberately never touches the VT your graphical session is on.
#
# USAGE
#
#   tools/console-font-sweep.sh /path/to/font.psfu ...
#
#   # resolve from nixpkgs by attribute, then name the font inside it:
#   tools/console-font-sweep.sh spleen:spleen-16x32 spleen:spleen-32x64 \
#                               terminus_font:ter-v32n
#
# The `attr:name` form runs `nix build nixpkgs#<attr>` against your
# ambient nixpkgs registry, NOT this flake's pin. For a sweep that only
# has to answer "which of these do I like", that difference does not
# matter; if you are chasing a version-specific rendering difference,
# pass an explicit store path instead.
#
# Principle 01 split: the mechanism (load N fonts, compare, restore) is
# public; which font wins is a host-module or private-layer value —
# a console font is a pixel grid, so it is panel-density-dependent and
# usually belongs in hosts/<name>/, next to castle.display.scale.
set -euo pipefail

die() { printf 'console-font-sweep: %s\n' "$*" >&2; exit 1; }

# See tools/font-sweep.sh's `hold` for why the non-TTY branch exists.
# It matters more here: an instant teardown would restore the default
# font before anyone had switched VTs to look at anything.
hold() {
  if [ -t 0 ]; then
    printf '%s\n\n' "$1"
    read -r _ || true
  else
    printf 'stdin is not a terminal; leaving this up. Ctrl-C, or kill %s, to restore.\n\n' "$$"
    # See tools/font-sweep.sh's `hold` for why this is `sleep &` + `wait`
    # rather than a bare `sleep`. Here the consequence is worse than a
    # stray window: a swallowed SIGTERM means the VTs keep the swept font
    # instead of being restored to the kernel default.
    while :; do sleep 3600 & wait $! || break; done
  fi
}

# Print the header comment as usage. Reads to the first non-comment line
# rather than a hardcoded range — see the same helper in font-sweep.sh
# for why: the range here was `2,50p` against a header that ran to 52,
# so --help cut the Principle 01 note off mid-sentence.
usage() { awk 'NR == 1 { next } /^#/ { print; next } { exit }' "$0"; }

case "${1:-}" in --help|-h) usage; exit 0 ;; esac
[ $# -ge 1 ] || die "give at least one font (path, or attr:name); --help for usage"

command -v setfont >/dev/null || die "setfont not found (pkgs.kbd)"
sudo -v || die "this needs sudo: setfont on a VT is privileged"

# Never touch the VT the graphical session is on.
#
# A user owns more than one session — on a systemd/greetd host there is
# the graphical one (Type=wayland, a real VTNr) *and* a long-lived
# `manager` session whose VTNr is 0. Taking simply the first session
# this user owns is wrong: `loginctl` orders by session ID, so after any
# logout/login cycle the graphical session gets the higher ID and the
# manager sorts first. That yields session_vt=0 — and `${session_vt:=1}`
# does NOT rescue it, because "0" is a non-empty string. The skip loop
# below then never fires, and on a host whose session sits on VT 7 this
# script would `setfont` the very VT it promises to leave alone.
# So: walk this user's sessions and take the first with a nonzero VTNr.
session_vt=""
while read -r s; do
  [ -n "$s" ] || continue
  v="$(loginctl show-session "$s" -p VTNr --value 2>/dev/null || true)"
  if [ -n "$v" ] && [ "$v" != 0 ]; then session_vt="$v"; break; fi
done <<< "$(loginctl list-sessions --no-legend 2>/dev/null \
            | awk -v u="$(id -un)" '$3==u {print $1}' || true)"
: "${session_vt:=1}"

resolve() {
  local spec="$1"
  if [ -e "$spec" ]; then printf '%s\n' "$spec"; return; fi
  case "$spec" in
    *:*) local attr="${spec%%:*}" name="${spec##*:}" out
         out="$(nix build --no-link --print-out-paths "nixpkgs#$attr" 2>/dev/null | tail -1)" \
           || die "could not build nixpkgs#$attr"
         local hit
         # `-print -quit` rather than `| head -1`: under `set -o pipefail`
         # head exiting first hands find a SIGPIPE, the pipeline reports
         # 141, and `set -e` kills the script *before* the `|| die` below
         # can say why. Small font packages happen to buffer inside the
         # pipe and hide it; a large one would not. Same silent-abort
         # class as the bug documented in font-sweep.sh's `origin=`.
         hit="$(find "$out" \( -name "$name.psf*" -o -name "$name" \) -print -quit 2>/dev/null)"
         [ -n "$hit" ] || die "no font named '$name' inside nixpkgs#$attr"
         printf '%s\n' "$hit" ;;
    *)   die "'$spec' is neither an existing path nor attr:name" ;;
  esac
}

touched=()
pids=()
# Guarded because the trap is armed on INT/TERM *and* EXIT, so a
# Ctrl-C runs it twice — harmless for setfont, but it printed the
# "Restored..." line twice, which reads like something went wrong.
cleaned=0
cleanup() {
  [ "$cleaned" = 1 ] && return 0
  cleaned=1
  for p in "${pids[@]:-}"; do kill "$p" 2>/dev/null || true; done
  for t in "${touched[@]:-}"; do sudo setfont -C "/dev/tty$t" >/dev/null 2>&1 || true; done
  [ ${#touched[@]} -gt 0 ] && printf 'Restored the kernel default font on VT: %s\n' "${touched[*]}"
  return 0
}
trap cleanup EXIT INT TERM

vt=2
printf '\n'
for spec in "$@"; do
  vt=$((vt + 1))
  while [ "$vt" = "$session_vt" ]; do vt=$((vt + 1)); done
  [ "$vt" -le 12 ] || die "ran out of spare VTs"

  font="$(resolve "$spec")"
  sudo setfont -C "/dev/tty$vt" "$font" \
    || die "kernel refused '$spec' on tty$vt (too large? wrong format?)"
  touched+=("$vt")

  # Reprint on a loop so a getty appearing cannot leave a blank screen.
  (
    while :; do
      {
        printf '\n=== %s ===\n\n' "$spec"
        printf 'The quick brown fox jumps over the lazy dog. 0123456789\n'
        printf 'Il1| O0o rn/m cl/d ,.;: 3f8a2c1e9b7d4056\n\n'
        printf '%s login: _\n\n' "$(hostname)"
        printf '[    3.812] EXT4-fs (nvme0n1p2): mounted filesystem ro\n'
        printf '[FAILED] Failed to start Network Manager Wait Online.\n'
        printf 'You are in emergency mode. After logging in, type\n'
        printf '"journalctl -xb" to view system logs.\n\n'
        # `sudo` stty, not bare stty: a spare VT is crw--w---- root:tty
        # and GNU stty opens it O_RDONLY, so an unprivileged call fails
        # with EACCES even for tty-group members. Every other write here
        # goes through `sudo tee`; this one was missed, and the symptom
        # was a silently blank `grid:` line — the exact number this
        # comparison exists to report.
        printf 'grid: %s\n' "$(sudo stty -F "/dev/tty$vt" size 2>/dev/null | awk '{print $2 "x" $1}')"
      } | sudo tee "/dev/tty$vt" >/dev/null
      sleep 4
    done
  ) &
  pids+=($!)
  printf '  Ctrl+Alt+F%-2s  %s\n' "$vt" "$spec"
done

printf '  Ctrl+Alt+F%-2s  (back to your session)\n\n' "$session_vt"
hold "Compare, then press Enter here to restore the default console font."
