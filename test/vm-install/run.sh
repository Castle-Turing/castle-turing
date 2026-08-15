#!/usr/bin/env bash
# test/vm-install/run.sh — the install-loop test harness (docs/tasks/0004).
#
# Boots a QEMU/OVMF VM standing in for hosts/xps9370, runs the real
# nixos-anywhere install path against it, then re-boots it three more
# times to check the specific ways task 0003's physical shakedown found
# the mechanism broken:
#
#   1. install completes and the VM boots from its own disk, installer
#      detached;
#   2. SSH comes up as the admin, by key, with zero console interaction
#      (regression test for the first-boot lockout, finding #1);
#   3. survives a power-cycle (hard stop + restart);
#   4. survives an NVRAM wipe, forcing the firmware down the ESP fallback
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

QEMU_PID=""

log() { printf '>>> %s\n' "$*"; }
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  printf 'Logs and disk/OVMF state preserved at: %s\n' "$WORKDIR" >&2
  exit 1
}

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill -9 "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
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
build_pkg() {
  # Caller supplies the exact attribute path, including any output
  # selector needed (e.g. "openssh.out", or plain "OVMF.fd" — OVMF.fd is
  # already a specific output of the OVMF derivation, and appending
  # ".out" to it re-selects OVMF's plain "out" output instead, discarding
  # the ".fd" narrowing).
  build_expr "(import \"$HARNESS_DIR/pkgs.nix\").$1"
}

log "Building harness tooling (qemu, OVMF, nixos-anywhere, openssh) from this flake's pinned nixpkgs..."
QEMU=$(build_pkg qemu.out)
OVMF=$(build_pkg OVMF.fd)
NIXOS_ANYWHERE=$(build_pkg nixos-anywhere.out)
OPENSSH=$(build_pkg openssh.out)

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

log "Building the installer image (hosts/vm-test's SSH-reachable installer)..."
ISO_OUT=$(build_expr "(import \"$HARNESS_DIR/installer.nix\" { pubkeyFile = \"$ADMIN_PUB\"; }).config.system.build.isoImage")
ISO_PATH=$(find "$ISO_OUT/iso" -maxdepth 1 -name '*.iso' | head -n1)
[ -n "$ISO_PATH" ] || fail "installer ISO build produced no .iso file"

log "Building the target system (hosts/vm-test + a throwaway admin key)..."
TOPLEVEL=$(build_expr "(import \"$HARNESS_DIR/vm-test-system.nix\" { pubkeyFile = \"$ADMIN_PUB\"; }).config.system.build.toplevel")
DISKO_SCRIPT=$(build_expr "(import \"$HARNESS_DIR/vm-test-system.nix\" { pubkeyFile = \"$ADMIN_PUB\"; }).config.system.build.diskoScript")

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

# wait_for_ssh <user> <timeout-seconds>
wait_for_ssh() {
  local user="$1" timeout="$2"
  local deadline=$((SECONDS + timeout))
  while (( SECONDS < deadline )); do
    if "$SSH_BIN" "${SSH_OPTS[@]}" -p "$SSH_PORT" -i "$ADMIN_KEY" "$user@127.0.0.1" true 2>/dev/null; then
      return 0
    fi
    sleep 3
  done
  return 1
}

# --- Phase 1: boot the installer, run the real install path ---------------
log "[phase1] Booting installer image..."
start_qemu phase1-installer -cdrom "$ISO_PATH" -boot order=d
wait_for_ssh root "$BOOT_TIMEOUT" || fail "installer did not come up over SSH within ${BOOT_TIMEOUT}s"
log "[phase1] Installer reachable. Running nixos-anywhere (disko + install)..."
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
# actually landed. `;` (not `&&`) so sync still runs even if a sub-mount
# is reported busy.
"$SSH_BIN" "${SSH_OPTS[@]}" -p "$SSH_PORT" -i "$ADMIN_KEY" root@127.0.0.1 \
  "umount -R /mnt 2>&1 || true; sync" \
  || log "[phase1] WARNING: unmount/sync over SSH failed; proceeding to detach anyway"
log "[phase1] Detaching installer (hard stop from here on, same as every later transition)."
stop_qemu_hard

# --- Phase 2: first real boot, installer detached, zero console interaction
log "[phase2] Booting from the installed disk only (no installer media attached)..."
start_qemu phase2-first-boot -boot order=c
if ! wait_for_ssh harness "$BOOT_TIMEOUT"; then
  fail "assertion failed: SSH as admin, by key, with zero console interaction (first-boot lockout regression — see $LOG_DIR/phase2-first-boot.serial.log)"
fi
log "[phase2] PASS: SSH as admin came up with zero console interaction, installer detached."

# --- Phase 2b: graphical target reached, Sway IPC socket present ----------
# A GUI can't be driven headlessly, but "the compositor started and is
# controllable over IPC" can be checked — docs/tasks/0005-dogfooding-
# desktop.md. modules/desktop (vm-test-system.nix imports the published
# module) starts Sway with a test-only auto-login override, no console
# interaction either. This deliberately runs against the same still-
# booted VM as phase 2, not a fresh boot — nothing about this assertion
# needs another reboot cycle.
log "[phase2b] Waiting for graphical.target..."
GRAPHICAL_DEADLINE=$((SECONDS + BOOT_TIMEOUT))
GRAPHICAL_OK=""
while (( SECONDS < GRAPHICAL_DEADLINE )); do
  if "$SSH_BIN" "${SSH_OPTS[@]}" -p "$SSH_PORT" -i "$ADMIN_KEY" harness@127.0.0.1 \
      systemctl is-active graphical.target >/dev/null 2>&1; then
    GRAPHICAL_OK=1
    break
  fi
  sleep 3
done
[ -n "$GRAPHICAL_OK" ] || fail "assertion failed: graphical.target was not reached within ${BOOT_TIMEOUT}s (see $LOG_DIR/phase2-first-boot.serial.log)"
log "[phase2b] PASS: graphical.target reached."

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
start_qemu phase3-power-cycle -boot order=c
if ! wait_for_ssh harness "$BOOT_TIMEOUT"; then
  fail "assertion failed: survive a power-cycle (see $LOG_DIR/phase3-power-cycle.serial.log)"
fi
log "[phase3] PASS: survived a hard stop and restart."

# --- Phase 4: NVRAM wipe, forcing the ESP fallback boot path --------------
log "[phase4] Wiping NVRAM (fresh OVMF vars) and restarting — firmware must fall back to EFI/BOOT/BOOTX64.EFI..."
stop_qemu_hard
cp "$OVMF_VARS_TEMPLATE" "$OVMF_VARS"
chmod u+w "$OVMF_VARS"
start_qemu phase4-nvram-wipe -boot order=c
if ! wait_for_ssh harness "$BOOT_TIMEOUT"; then
  fail "assertion failed: survive an NVRAM wipe via the ESP fallback path (see $LOG_DIR/phase4-nvram-wipe.serial.log) — this is the dead-CMOS regression docs/tasks/0003-findings.md #2/#5 describes"
fi
log "[phase4] PASS: survived an NVRAM wipe via the ESP fallback path."

stop_qemu_hard
log "All assertions passed. Logs: $LOG_DIR"
