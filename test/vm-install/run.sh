#!/usr/bin/env bash
# test/vm-install/run.sh — the install-loop test harness (docs/tasks/0004).
#
# Boots a QEMU/OVMF VM standing in for hosts/xps9370, runs the real
# nixos-anywhere install path against it, then re-boots it three more
# times to check the specific ways task 0003's physical shakedown found
# the mechanism broken:
#
#   1. the installer image itself is SSH-reachable by key with zero
#      console interaction (regression test for finding #3, installer
#      ephemerality — docs/tasks/0006-installer-image.md);
#   2. install completes and the VM boots from its own disk, installer
#      detached;
#   3. SSH comes up as the admin, by key, with zero console interaction
#      (regression test for the first-boot lockout, finding #1);
#   4. survives a power-cycle (hard stop + restart);
#   5. survives an NVRAM wipe, forcing the firmware down the ESP fallback
#      path EFI/BOOT/BOOTX64.EFI (finding #2/#5, the dead-CMOS lesson).
#
# Requires: Nix (flakes enabled) and a KVM-capable Linux box. See
# test/vm-install/README.md for how to read a failure.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HARNESS_DIR="$REPO_ROOT/test/vm-install"

WORKDIR="$(mktemp -d /tmp/castle-vm-install.XXXXXX)"
LOG_DIR="${CASTLE_HARNESS_LOG_DIR:-$WORKDIR/logs}"
mkdir -p "$LOG_DIR"

SSH_PORT="${CASTLE_HARNESS_SSH_PORT:-10222}"
BOOT_TIMEOUT="${CASTLE_HARNESS_BOOT_TIMEOUT:-180}"
# docs/tasks/0016: deliberately its own budget, not BOOT_TIMEOUT plus a
# margin. BOOT_TIMEOUT covers "how long until sshd answers," which tracks
# the network coming up more or less immediately; the installer's
# connected banner can additionally be delayed by up to a *fixed* 300s if
# statusScript's own 20s DHCP head start loses the race and it commits to
# `timeout --foreground 300 nmtui` before the lease lands (real under
# this harness's own TCG fallback, or a loaded runner — not
# theoretical). Deriving this from BOOT_TIMEOUT would under-size it if
# someone shortens BOOT_TIMEOUT for a fast box, and stacking a second
# full BOOT_TIMEOUT on top of what wait_for_ssh already spent would risk
# vm-install-test.yml's own job-level timeout-minutes in exactly the
# regression case this assertion exists to catch. 340s = 20 (head start)
# + 300 (nmtui) + margin.
CONNECTED_BANNER_TIMEOUT="${CASTLE_HARNESS_CONNECTED_BANNER_TIMEOUT:-340}"

QEMU_PID=""
SUCCESS=""

log() { printf '>>> %s\n' "$*"; }
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  # Logs and disk/OVMF state live in different places whenever
  # CASTLE_HARNESS_LOG_DIR is set to something other than $WORKDIR/logs —
  # which CI always does (a workspace path the "Upload harness logs" step
  # actually picks up), so reporting only $WORKDIR here would send anyone
  # debugging a red CI run to a directory with nothing useful in it.
  printf 'Logs preserved at: %s\n' "$LOG_DIR" >&2
  printf 'Disk/OVMF state preserved at: %s\n' "$WORKDIR" >&2
  exit 1
}

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill -9 "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  if [ -n "$SUCCESS" ]; then
    # Success: the harness is done with the heavy state, so drop the 8G
    # disk image, the mutable NVRAM copy, and the throwaway keys —
    # repeated local runs would otherwise accumulate disk images.
    # Logs always survive: fail() and the runbook both point at
    # $LOG_DIR. When the log dir lives outside the workdir (CI always
    # sets CASTLE_HARNESS_LOG_DIR to a workspace path), the workdir has
    # nothing worth keeping and goes wholesale; when the logs live
    # inside it (the local default), keep the directory.
    rm -f "$DISK" "$OVMF_VARS" "$ADMIN_KEY" "$ADMIN_PUB"
    case "$LOG_DIR/" in
      "$WORKDIR"/*) ;;
      *) rm -rf "$WORKDIR" ;;
    esac
  fi
}
trap cleanup EXIT

NIX_BUILD_ARGS=(--extra-experimental-features "nix-command flakes" --no-link --print-out-paths)

build_expr() {
  # Attribute access (not the CLI's ATTR^output syntax) so Nix's own
  # output-selection sugar resolves the path exactly once: some packages
  # (e.g. openssh) have more than one default output (out, man, ...),
  # and --print-out-paths would print one line per output otherwise,
  # breaking the single-path assumption every caller here makes.
  nix build --impure "${NIX_BUILD_ARGS[@]}" --expr "$1" | head -n1
}

log "Building harness tooling (qemu, OVMF, nixos-anywhere, openssh) from this flake's pinned nixpkgs..."
# One linkFarm build, not four sequential `nix build --impure --expr`
# calls: this evaluates pkgs.nix once and builds the four derivations in
# parallel inside a single nix invocation, turning a sum of build times
# into a max. The output selectors are the same attribute accesses the
# per-package calls used ("OVMF.fd" is already a specific output of the
# OVMF derivation — appending ".out" to it would re-select OVMF's plain
# "out" output instead, discarding the ".fd" narrowing).
TOOLS=$(build_expr "let pkgs = import \"$HARNESS_DIR/pkgs.nix\"; in pkgs.linkFarm \"harness-tools\" { qemu = pkgs.qemu.out; \"OVMF.fd\" = pkgs.OVMF.fd; nixos-anywhere = pkgs.nixos-anywhere.out; openssh = pkgs.openssh.out; }")
QEMU=$(readlink -f "$TOOLS/qemu")
OVMF=$(readlink -f "$TOOLS/OVMF.fd")
NIXOS_ANYWHERE=$(readlink -f "$TOOLS/nixos-anywhere")
OPENSSH=$(readlink -f "$TOOLS/openssh")

QEMU_BIN="$QEMU/bin/qemu-system-x86_64"
QEMU_IMG_BIN="$QEMU/bin/qemu-img"
SSH_BIN="$OPENSSH/bin/ssh"
SSH_KEYGEN_BIN="$OPENSSH/bin/ssh-keygen"
NIXOS_ANYWHERE_BIN="$NIXOS_ANYWHERE/bin/nixos-anywhere"

OVMF_CODE="$OVMF/FV/OVMF_CODE.fd"
OVMF_VARS_TEMPLATE="$OVMF/FV/OVMF_VARS.fd"

log "Generating a throwaway admin key for this run only (never committed)..."
ADMIN_KEY="$WORKDIR/admin_key"
"$SSH_KEYGEN_BIN" -q -t ed25519 -N "" -C "castle-turing-harness" -f "$ADMIN_KEY"
ADMIN_PUB="$ADMIN_KEY.pub"

log "Building the installer image (flake.nixosModules.installer, docs/tasks/0006) and the target system (hosts/vm-test + a throwaway admin key) in parallel..."
# Two independent evaluations, so one backgrounded nix invocation each,
# then wait — the sum becomes a max. The two artifacts of the target
# system (TOPLEVEL and DISKO_SCRIPT) come from a single linkFarm
# expression: they used to come from two separate `nix build --impure
# --expr` calls that each independently imported vm-test-system.nix, so
# the full nixosSystem evaluation (including its self-referential
# getFlake) ran twice per harness run — docs/tasks/0006-installer-
# image.md's parked-cleanup item. The linkFarm evaluates
# vm-test-system.nix exactly once and exposes both outputs as named
# symlinks in one derivation; the artifacts are then resolved to their
# real store paths (readlink -f) rather than passed to nixos-anywhere as
# symlinks living inside the linkFarm's own output.
ISO_OUT_FILE="$WORKDIR/iso-out.txt"
ARTIFACTS_FILE="$WORKDIR/artifacts-out.txt"
build_expr "(import \"$HARNESS_DIR/installer.nix\" { pubkeyFile = \"$ADMIN_PUB\"; }).config.system.build.isoImage" >"$ISO_OUT_FILE" &
ISO_BUILD_PID=$!
build_expr "let system = import \"$HARNESS_DIR/vm-test-system.nix\" { pubkeyFile = \"$ADMIN_PUB\"; }; pkgs = import \"$HARNESS_DIR/pkgs.nix\"; in pkgs.linkFarm \"vm-test-artifacts\" { toplevel = system.config.system.build.toplevel; diskoScript = system.config.system.build.diskoScript; }" >"$ARTIFACTS_FILE" &
ARTIFACTS_BUILD_PID=$!
ISO_STATUS=0
ARTIFACTS_STATUS=0
wait "$ISO_BUILD_PID" || ISO_STATUS=$?
wait "$ARTIFACTS_BUILD_PID" || ARTIFACTS_STATUS=$?
# On failure the build's stderr is already on the terminal; name which
# one died rather than letting the exit status alone tell the story.
[ "$ISO_STATUS" -eq 0 ] || fail "installer ISO build failed (see output above)"
[ "$ARTIFACTS_STATUS" -eq 0 ] || fail "target system build failed (see output above)"
ISO_OUT=$(head -n1 "$ISO_OUT_FILE")
ISO_PATH=$(find "$ISO_OUT/iso" -maxdepth 1 -name '*.iso' | head -n1)
[ -n "$ISO_PATH" ] || fail "installer ISO build produced no .iso file"
ARTIFACTS=$(head -n1 "$ARTIFACTS_FILE")
TOPLEVEL=$(readlink -f "$ARTIFACTS/toplevel")
DISKO_SCRIPT=$(readlink -f "$ARTIFACTS/diskoScript")

log "Preparing disk image and OVMF NVRAM vars..."
DISK="$WORKDIR/disk.qcow2"
"$QEMU_IMG_BIN" create -f qcow2 "$DISK" 8G >/dev/null
OVMF_VARS="$WORKDIR/OVMF_VARS.fd"
cp "$OVMF_VARS_TEMPLATE" "$OVMF_VARS"
chmod u+w "$OVMF_VARS"

if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
  ACCEL="kvm"
  CPU="host"
else
  echo "WARNING: /dev/kvm not accessible — falling back to TCG emulation." >&2
  echo "This will be dramatically slower and may exceed CI's time budget." >&2
  ACCEL="tcg"
  CPU="max"
fi

SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o GlobalKnownHostsFile=/dev/null
  -o ConnectTimeout=5
  -o BatchMode=yes
  -o LogLevel=ERROR
)

# start_qemu <phase-name> [-cdrom <path>]
# Boots the shared disk under the shared (mutable) OVMF_VARS, on
# $SSH_PORT. Sets QEMU_PID.
start_qemu() {
  local phase="$1"
  shift
  local args=(
    -machine "q35,accel=$ACCEL"
    -cpu "$CPU"
    -m 2048
    -smp 2
    -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE"
    -drive "if=pflash,format=raw,file=$OVMF_VARS"
    -drive "file=$DISK,format=qcow2,if=virtio"
    # hostaddr must be explicit (127.0.0.1): slirp binds an empty one to
    # 0.0.0.0, exposing the installer's/target's key-only sshd to the
    # whole network for the run's duration. Every caller in this script
    # already dials 127.0.0.1, so nothing is lost by restricting it.
    -nic "user,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22,model=virtio-net-pci"
    -display none
    -serial "file:$LOG_DIR/$phase.serial.log"
    "$@"
  )
  "$QEMU_BIN" "${args[@]}" >"$LOG_DIR/$phase.qemu.log" 2>&1 &
  QEMU_PID=$!
  log "[$phase] qemu pid $QEMU_PID, serial log: $LOG_DIR/$phase.serial.log"
}

stop_qemu_hard() {
  # Simulates power loss, not a clean shutdown — the point of the
  # power-cycle and NVRAM-wipe assertions.
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill -9 "$QEMU_PID"
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  QEMU_PID=""
  # Let the host free the forwarded port before the next qemu binds it.
  sleep 1
}

# wait_for_ssh <user> <timeout-seconds> <serial-log>
# Polls SSH by key until it answers or the deadline passes. The SSH
# attempt itself is the only signal that counts; the phase's serial log
# (already being captured by qemu) is watched to pace the polling —
# once getty prints its login prompt the boot has progressed far enough
# that sshd can be up, so poll tightly; before that, poll loosely.
wait_for_ssh() {
  local user="$1" timeout="$2" serial_log="$3"
  local deadline=$((SECONDS + timeout))
  while (( SECONDS < deadline )); do
    if "$SSH_BIN" "${SSH_OPTS[@]}" -p "$SSH_PORT" -i "$ADMIN_KEY" "$user@127.0.0.1" true 2>/dev/null; then
      return 0
    fi
    if [ -f "$serial_log" ] && grep -q "login:" "$serial_log"; then
      sleep 0.5
    else
      sleep 1
    fi
  done
  return 1
}

# poll_until <timeout-seconds> <command...>
# Repeats <command...> (a full command line -- typically a small wrapper
# function, since redirections don't survive being passed as argv) once a
# second until it exits 0 or <timeout-seconds> pass. Shared by every
# plain "keep checking until this condition holds, no special pacing"
# assertion below (graphical.target, the connected-banner check) instead
# of each hand-rolling its own SECONDS-deadline loop -- a timeout or
# pacing fix then lands in one place, not three. wait_for_ssh (above)
# deliberately keeps its own separate loop rather than routing through
# this: it paces off the serial log (loose before a login prompt appears,
# tight after), a genuine behavioral difference this helper doesn't try
# to absorb, not an oversight -- folding it in here would risk the one
# poll loop in this file that's been relied on the longest, for a save of
# one more copy.
poll_until() {
  local timeout="$1"
  shift
  local deadline=$((SECONDS + timeout))
  while (( SECONDS < deadline )); do
    if "$@"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

# assert_boots <phase> <user> <fail-message> <pass-message> [qemu args...]
# The shared shape of every boot assertion: start QEMU for the phase,
# wait for SSH by key, fail with the caller's message or log its PASS.
# Callers that must stop the previous boot first (phases 3 and 4) do
# that themselves before calling.
assert_boots() {
  local phase="$1" user="$2" msg="$3" passmsg="$4"
  shift 4
  start_qemu "$phase" "$@"
  if ! wait_for_ssh "$user" "$BOOT_TIMEOUT" "$LOG_DIR/$phase.serial.log"; then
    fail "$msg"
  fi
  log "[$phase] PASS: $passmsg"
}

# --- Phase 1: boot the installer, run the real install path ---------------
log "[phase1] Booting installer image..."
assert_boots phase1-installer root \
  "assertion failed: the installer image is SSH-reachable by key with zero console interaction within ${BOOT_TIMEOUT}s (see $LOG_DIR/phase1-installer.serial.log) — docs/tasks/0003-findings.md finding #3, closed by docs/tasks/0006-installer-image.md" \
  "installer SSH-reachable by key with zero console interaction." \
  -cdrom "$ISO_PATH" -boot order=d

# docs/tasks/0016: the harness being SSH-reachable (above) doesn't prove
# statusScript's own "connected" banner ever printed -- that's exactly
# the gap that let the connected branch of modules/installer.nix's
# have_network() sit unreachable, undetected by this harness, until a
# human read a real serial console by eye. installer.nix (this
# directory) puts `console=ttyS0` on the kernel command line and
# modules/installer.nix restores --autologin on serial-getty@ for
# exactly this reason (see that file's header comment), so statusScript
# runs on ttyS0 too and its output lands in this same serial log --
# nothing extra to wire up, just something to actually assert on.
#
# Checked for the two lines the brief calls out specifically, not "the
# script produced output": the hostname line and the `ssh root@` line
# from the connected-state banner. Read out of the same build rather
# than hardcoded as a second copy of modules/installer.nix's
# networking.hostName default -- shellLoginHint (that file's own
# comment, lines 127-141) argues at length against exactly that pattern,
# and a hardcoded copy here would be the identical mistake in the
# harness written to catch it: a rename would silently stop this check
# matching anything, either a false failure or, worse, an unnoticed dead
# assertion if the pattern were ever loosened in response. A single
# `nix eval` of one string attribute is cheap (no build, and the flake's
# already evaluated once for the ISO build above).
log "Reading the installer's networking.hostName for the connected-banner check..."
INSTALLER_HOSTNAME=$(nix eval --extra-experimental-features "nix-command flakes" --impure --raw \
  --expr "(import \"$HARNESS_DIR/installer.nix\" { pubkeyFile = \"$ADMIN_PUB\"; }).config.networking.hostName")

connected_banner_present() {
  grep -q "reachable at:.*${INSTALLER_HOSTNAME}\.local" "$LOG_DIR/phase1-installer.serial.log" 2>/dev/null \
    && grep -q "ssh root@${INSTALLER_HOSTNAME}\.local" "$LOG_DIR/phase1-installer.serial.log" 2>/dev/null
}

log "[phase1] Confirming the connected banner (hostname + ssh line) reached the serial console..."
if poll_until "$CONNECTED_BANNER_TIMEOUT" connected_banner_present; then
  log "[phase1] PASS: connected banner (hostname + ssh root@ line) reached the serial console."
else
  fail "assertion failed: the installer's connected banner (hostname line + ssh root@ line) never reached the serial console within ${CONNECTED_BANNER_TIMEOUT}s (see $LOG_DIR/phase1-installer.serial.log) — docs/tasks/0016-installer-network-predicate.md, defect 1"
fi

log "[phase1] Running nixos-anywhere (disko + install)..."
if ! "$NIXOS_ANYWHERE_BIN" \
    --store-paths "$DISKO_SCRIPT" "$TOPLEVEL" \
    --target-host "root@127.0.0.1" \
    -p "$SSH_PORT" \
    -i "$ADMIN_KEY" \
    --phases disko,install \
    2>&1 | tee "$LOG_DIR/phase1-nixos-anywhere.log"; then
  fail "nixos-anywhere install failed — see $LOG_DIR/phase1-nixos-anywhere.log"
fi
log "[phase1] Install completed. Unmounting the installed filesystems and syncing before detaching the installer..."
# --phases disko,install deliberately excludes nixos-anywhere's own
# "reboot" phase (we need to swap boot media, not just reboot in place),
# so nothing has unmounted /mnt or flushed the writes bootctl just made
# to the vfat ESP — those are the two things phases 2-4 depend on having
# actually landed.
#
# This is a hard assertion, not a warning: qcow2/virtio-blk isn't
# write-through by default, so a flush that silently fails here, right
# before the deliberate kill -9 below, can lose the ESP write outright —
# and phase 2/3/4 would then fail for a completely different, confusing
# reason (looking exactly like a bootloader-fallback regression) instead
# of reporting the actual problem, which is that this step never
# confirmed the flush happened.
#
# The remote command runs sync unconditionally (even if umount fails on
# a busy sub-mount, still worth flushing whatever can be flushed) but
# now genuinely requires *both* to succeed for the assertion to pass:
# an earlier version used `umount ... || true`, which swallowed umount's
# exit status entirely and left the whole check gated on sync alone —
# sync succeeds almost unconditionally, so that version could never
# actually catch the busy-sub-mount case its own comment described.
# Single-quoted so `$?` etc. reach the remote shell, not this one.
#
# Several attempts over ~30s, not one retry: this runs immediately after
# disko+install on a CI runner (or under TCG locally), and a single
# 2-second-spaced retry doesn't give a loaded box enough headroom to
# reconnect — that would trade the original silent-warning flake for an
# impatient false-negative that gates every PR instead, which is a worse
# failure mode than the one this hard assertion was added to catch.
# Still fails hard at the end; it's the timing budget that was wrong,
# not the decision to assert.
unmount_sync_ok=0
attempt=0
deadline=$((SECONDS + 30))
while (( SECONDS < deadline )); do
  attempt=$((attempt + 1))
  if "$SSH_BIN" "${SSH_OPTS[@]}" -p "$SSH_PORT" -i "$ADMIN_KEY" root@127.0.0.1 \
      'umount -R /mnt 2>&1; u=$?; sync; s=$?; [ "$u" -eq 0 ] && [ "$s" -eq 0 ]'; then
    unmount_sync_ok=1
    break
  fi
  log "[phase1] unmount/sync attempt $attempt failed, retrying..."
  sleep 5
done
[ "$unmount_sync_ok" = 1 ] || fail "could not confirm the installed filesystems were unmounted and synced before detaching the installer — phases 2-4 need bootctl install's ESP writes to have actually landed on disk, and this harness won't guess that they did"
log "[phase1] Detaching installer (hard stop from here on, same as every later transition)."
stop_qemu_hard

# --- Phase 2: first real boot, installer detached, zero console interaction
log "[phase2] Booting from the installed disk only (no installer media attached)..."
assert_boots phase2-first-boot harness \
  "assertion failed: SSH as admin, by key, with zero console interaction (first-boot lockout regression — see $LOG_DIR/phase2-first-boot.serial.log)" \
  "SSH as admin came up with zero console interaction, installer detached." \
  -boot order=c

# --- Phase 2b: graphical target reached, Sway IPC socket present ----------
# A GUI can't be driven headlessly, but "the compositor started and is
# controllable over IPC" can be checked — docs/tasks/0005-dogfooding-
# desktop.md. modules/desktop (vm-test-system.nix imports the published
# module) starts Sway with a test-only auto-login override, no console
# interaction either. This deliberately runs against the same still-
# booted VM as phase 2, not a fresh boot — nothing about this assertion
# needs another reboot cycle.
graphical_target_active() {
  "$SSH_BIN" "${SSH_OPTS[@]}" -p "$SSH_PORT" -i "$ADMIN_KEY" harness@127.0.0.1 \
    systemctl is-active graphical.target >/dev/null 2>&1
}

log "[phase2b] Waiting for graphical.target..."
if poll_until "$BOOT_TIMEOUT" graphical_target_active; then
  log "[phase2b] PASS: graphical.target reached."
else
  fail "assertion failed: graphical.target was not reached within ${BOOT_TIMEOUT}s (see $LOG_DIR/phase2-first-boot.serial.log)"
fi

log "[phase2b] Checking for Sway's IPC socket and querying it..."
SWAY_IPC_CHECK='
set -e
sockfile="$(ls /run/user/*/sway-ipc.*.sock 2>/dev/null | head -n1)"
[ -n "$sockfile" ] || { echo "no sway-ipc socket found" >&2; exit 1; }
SWAYSOCK="$sockfile" swaymsg -t get_version
'
if ! "$SSH_BIN" "${SSH_OPTS[@]}" -p "$SSH_PORT" -i "$ADMIN_KEY" harness@127.0.0.1 "$SWAY_IPC_CHECK" \
    >"$LOG_DIR/phase2b-sway-ipc.log" 2>&1; then
  fail "assertion failed: Sway's IPC socket did not appear or did not answer swaymsg (see $LOG_DIR/phase2b-sway-ipc.log)"
fi
log "[phase2b] PASS: Sway IPC socket present and answered swaymsg."

# --- Phase 3: power-cycle (hard stop + restart), NVRAM intact -------------
log "[phase3] Power-cycling (hard stop, then restart with NVRAM intact)..."
stop_qemu_hard
assert_boots phase3-power-cycle harness \
  "assertion failed: survive a power-cycle (see $LOG_DIR/phase3-power-cycle.serial.log)" \
  "survived a hard stop and restart." \
  -boot order=c

# --- Phase 4: NVRAM wipe, forcing the ESP fallback boot path --------------
log "[phase4] Wiping NVRAM (fresh OVMF vars) and restarting — firmware must fall back to EFI/BOOT/BOOTX64.EFI..."
stop_qemu_hard
cp "$OVMF_VARS_TEMPLATE" "$OVMF_VARS"
chmod u+w "$OVMF_VARS"
assert_boots phase4-nvram-wipe harness \
  "assertion failed: survive an NVRAM wipe via the ESP fallback path (see $LOG_DIR/phase4-nvram-wipe.serial.log) — this is the dead-CMOS regression docs/tasks/0003-findings.md #2/#5 describes" \
  "survived an NVRAM wipe via the ESP fallback path." \
  -boot order=c

stop_qemu_hard
SUCCESS=1
log "All assertions passed. Logs: $LOG_DIR"
