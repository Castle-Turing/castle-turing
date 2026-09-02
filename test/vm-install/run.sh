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
#      (regression test for the first-boot lockout, finding #1), and on
#      that same boot a secret encrypted before the install decrypted
#      itself into /run/secrets — the whole sops-nix pipeline, key
#      planted by --extra-files and all
#      (docs/tasks/0031-secrets-tooling.md) — and a second such secret
#      reached /etc/shadow, proving it decrypted *before* the admin
#      account was created rather than merely at some point during
#      activation (docs/tasks/0032-password-hash.md);
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
# docs/tasks/0041: CASTLE_HARNESS_LOG_DIR is a fixed path CI reuses
# across a retried invocation (test/ci/retry-on-known-transient.sh runs
# this script up to twice in the same job); `mkdir -p` alone would
# leave a discarded first attempt's per-phase logs sitting alongside a
# differently-scoped second attempt's, misleading whoever reads the
# uploaded artifact about how far the run that actually failed got.
# Every invocation of this harness — retried or not — starts from a
# clean log directory. This makes CASTLE_HARNESS_LOG_DIR fully
# harness-owned, not merely a write target: see README.md's own
# warning on this variable before pointing it at a directory that
# holds anything else.
rm -rf "$LOG_DIR"
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
    rm -f "$DISK" "$OVMF_VARS" "$ADMIN_KEY" "$ADMIN_PUB" \
      "$AGE_KEY" "$SECRETS_FILE" "$WORKDIR/expected-secret" "$WORKDIR/actual-secret" \
      "$WORKDIR/expected-shadow" "$WORKDIR/actual-shadow"
    rm -rf "$EXTRA_FILES"
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

log "Building harness tooling (qemu, OVMF, nixos-anywhere, openssh, age, sops) from this flake's pinned nixpkgs..."
# One linkFarm build, not six sequential `nix build --impure --expr`
# calls: this evaluates pkgs.nix once and builds the derivations in
# parallel inside a single nix invocation, turning a sum of build times
# into a max. The output selectors are the same attribute accesses the
# per-package calls used ("OVMF.fd" is already a specific output of the
# OVMF derivation — appending ".out" to it would re-select OVMF's plain
# "out" output instead, discarding the ".fd" narrowing).
#
# age and sops joined the list with docs/tasks/0031-secrets-tooling.md:
# this harness now generates its own throwaway age keypair and its own
# throwaway encrypted fixture per run, following exactly the
# never-committed convention the throwaway admin SSH keypair below
# already set. Both come from this flake's pinned nixpkgs for the same
# reason every other tool here does.
TOOLS=$(build_expr "let pkgs = import \"$HARNESS_DIR/pkgs.nix\"; in pkgs.linkFarm \"harness-tools\" { qemu = pkgs.qemu.out; \"OVMF.fd\" = pkgs.OVMF.fd; nixos-anywhere = pkgs.nixos-anywhere.out; openssh = pkgs.openssh.out; age = pkgs.age.out; sops = pkgs.sops.out; }")
QEMU=$(readlink -f "$TOOLS/qemu")
OVMF=$(readlink -f "$TOOLS/OVMF.fd")
NIXOS_ANYWHERE=$(readlink -f "$TOOLS/nixos-anywhere")
OPENSSH=$(readlink -f "$TOOLS/openssh")
AGE=$(readlink -f "$TOOLS/age")
SOPS=$(readlink -f "$TOOLS/sops")

QEMU_BIN="$QEMU/bin/qemu-system-x86_64"
QEMU_IMG_BIN="$QEMU/bin/qemu-img"
SSH_BIN="$OPENSSH/bin/ssh"
SSH_KEYGEN_BIN="$OPENSSH/bin/ssh-keygen"
NIXOS_ANYWHERE_BIN="$NIXOS_ANYWHERE/bin/nixos-anywhere"
AGE_KEYGEN_BIN="$AGE/bin/age-keygen"
SOPS_BIN="$SOPS/bin/sops"

OVMF_CODE="$OVMF/FV/OVMF_CODE.fd"
OVMF_VARS_TEMPLATE="$OVMF/FV/OVMF_VARS.fd"

log "Generating a throwaway admin key for this run only (never committed)..."
ADMIN_KEY="$WORKDIR/admin_key"
"$SSH_KEYGEN_BIN" -q -t ed25519 -N "" -C "castle-turing-harness" -f "$ADMIN_KEY"
ADMIN_PUB="$ADMIN_KEY.pub"

# --- The secrets fixture (docs/tasks/0031-secrets-tooling.md) -------------
# Everything about this fixture is made here, seconds before it is used,
# and destroyed with the workdir afterwards: the age keypair, the
# ciphertext, and the plaintext marker inside it. That is the answer to
# "what must a fake example secret satisfy so CI can assert it is not
# real" — the job that asserts the value came back unchanged is the same
# job that invented it, and nothing about it is ever committed.
#
# **Where the plaintext marker reaches disk, stated rather than
# glossed.** It is not confined to memory, and an earlier version of
# this comment claimed it was — which is the more dangerous kind of
# error, because someone could swap in a realistic fixture on the
# strength of that sentence. Three places, all of them under $WORKDIR
# or $LOG_DIR:
#
#   * $WORKDIR/expected-secret and $WORKDIR/actual-secret, written by
#     phase 2c so `cmp` can compare bytes rather than shell strings;
#   * $LOG_DIR/phase2c-secret-actual.od, an `od -c` dump written only
#     when that comparison fails — and $LOG_DIR is what CI uploads as
#     an artifact, with `if: always()`;
#   * inside the VM, at /run/secrets/harness-fixture, which is the
#     whole point.
#
# The second fixture (docs/tasks/0032-password-hash.md, the admin
# password hash) reaches disk in the same three kinds of place, plus one
# the first one does not:
#
#   * $WORKDIR/expected-shadow and $WORKDIR/actual-shadow, phase 2d's
#     equivalents of the two files above;
#   * $LOG_DIR/phase2d-shadow-expected.od and
#     $LOG_DIR/phase2d-shadow-actual.od, written only on a mismatch and
#     uploaded by CI the same way;
#   * inside the VM at /run/secrets-for-users/harness-admin-password-hash
#     — a different runtime directory, because neededForUsers moves it;
#   * and, unlike any other secret here, inside the VM at /etc/shadow,
#     which is the whole point of phase 2d and the one place that
#     survives a reboot.
#
# Everything below about why that is acceptable applies to it
# identically, and one thing more: it is deliberately not shaped like a
# crypt hash, so it could not be mistaken for a credential even by
# someone who found it out of context.
#
# That is acceptable for *these* fixtures and only because of what they
# are: marker strings this script invented moments earlier, for a
# keypair that is deleted when the run ends, meaning nothing about them
# is a credential anywhere. **If you ever put a realistic value here,
# those places are what you have to fix first** — the CI artifacts
# especially, since a red run publishes them.
#
# There is deliberately no permanent example keypair anywhere in this
# repo; see nixosConfigurations.example's own comment in flake.nix for
# the argument, which is about what a committed artifact would cost
# rather than about what evaluation requires.
#
# The marker string is what phase 2c compares byte-for-byte, which is
# what makes this an end-to-end proof rather than a "some file appeared"
# check: encrypt here -> plant the key with --extra-files -> decrypt at
# the installed system's first activation -> read it back over SSH.
log "Generating a throwaway age key and encrypting the fixture secret for this run only (never committed)..."
AGE_KEY="$WORKDIR/age-key.txt"
SECRETS_FILE="$WORKDIR/harness-secrets.yaml"
FIXTURE_SECRET="castle-turing-vm-install-harness-fixture"
# The second fixture (docs/tasks/0032-password-hash.md): the value
# castle.admin.hashedPasswordFile points at, which NixOS writes into
# /etc/shadow when it creates the `harness` account. Deliberately **not**
# shaped like a crypt hash — no `$6$`, no MCF structure — so nobody can
# mistake it for one, and so no plaintext password exists anywhere in
# this process to have produced it. Nothing here ever authenticates with
# it: phase 2d asserts on its exact bytes, which is a claim about the
# pipeline, not about login. An opaque marker is strictly better for
# that than a real hash would be, because a real hash would tempt a
# future reader into believing a password lives here.
FIXTURE_PASSWORD_HASH="castle-turing-vm-install-harness-not-a-real-hash"
"$AGE_KEYGEN_BIN" -o "$AGE_KEY" 2>"$LOG_DIR/age-keygen.log" ||
  fail "could not generate the throwaway age key (see $LOG_DIR/age-keygen.log)"
chmod 600 "$AGE_KEY"
AGE_RECIPIENT=$("$AGE_KEYGEN_BIN" -y "$AGE_KEY")
# The marker goes to sops on stdin rather than through a temp file, so
# this step writes only ciphertext — but see the block above for the
# three later places the plaintext *does* reach disk. This line is not
# the whole story and must not be read as one.
# --filename-override tells sops which format to parse stdin as, since
# there is no filename to infer it from.
if ! printf 'harness-fixture: %s\nharness-admin-password-hash: %s\n' \
  "$FIXTURE_SECRET" "$FIXTURE_PASSWORD_HASH" |
  "$SOPS_BIN" --encrypt --age "$AGE_RECIPIENT" \
    --input-type yaml --output-type yaml \
    --filename-override harness-secrets.yaml /dev/stdin \
    >"$SECRETS_FILE" 2>"$LOG_DIR/sops-encrypt.log"; then
  fail "could not encrypt the harness fixture with sops (see $LOG_DIR/sops-encrypt.log)"
fi

# The one thing that must never be versioned, staged where
# nixos-anywhere --extra-files will copy it: recursively onto the
# target's root, after disko has mounted it at /mnt and before
# nixos-install runs, root-owned (tar --no-same-owner) with permissions
# preserved from here. Hence the modes below — 700 on the directory and
# 600 on the key, exactly what docs/private-layer.md tells a resident to
# stage by hand, and 755 on /var and /var/lib because tar applies these
# modes to those directories on the target too.
EXTRA_FILES="$WORKDIR/extra-files"
install -d -m 755 "$EXTRA_FILES" "$EXTRA_FILES/var" "$EXTRA_FILES/var/lib"
install -d -m 700 "$EXTRA_FILES/var/lib/sops-nix"
install -m 600 "$AGE_KEY" "$EXTRA_FILES/var/lib/sops-nix/key.txt"

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
build_expr "let system = import \"$HARNESS_DIR/vm-test-system.nix\" { pubkeyFile = \"$ADMIN_PUB\"; secretsFile = \"$SECRETS_FILE\"; }; pkgs = import \"$HARNESS_DIR/pkgs.nix\"; in pkgs.linkFarm \"vm-test-artifacts\" { toplevel = system.config.system.build.toplevel; diskoScript = system.config.system.build.diskoScript; }" >"$ARTIFACTS_FILE" &
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
# --extra-files is independent of --store-paths vs. --flake: it is
# handled inside nixos-anywhere's install phase, between the closure
# copy and nixos-install, regardless of how the closure was specified
# (verified in src/nixos-anywhere.sh's nixosInstall(), in the
# nixos-anywhere pkgs.nix resolves to). So the harness plants the age
# key by exactly the same
# flag, in exactly the same place in the sequence, that
# docs/private-layer.md tells a resident to use on real hardware.
if ! "$NIXOS_ANYWHERE_BIN" \
    --store-paths "$DISKO_SCRIPT" "$TOPLEVEL" \
    --target-host "root@127.0.0.1" \
    -p "$SSH_PORT" \
    -i "$ADMIN_KEY" \
    --extra-files "$EXTRA_FILES" \
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

# --- Phase 2c: the planted key decrypted a real secret --------------------
# docs/tasks/0031-secrets-tooling.md. Same still-booted VM as phase 2 —
# this needs no reboot of its own, only a machine that has activated
# once. Two assertions, in the order a failure is easiest to read:
# first that the key survived the install with the ownership and mode
# --extra-files promises (a key readable by anyone, or lost entirely, is
# a different bug from a key that failed to decrypt), then that the
# secret behind it came back byte-for-byte.
#
# Over root's SSH session rather than the admin's: sops writes
# /run/secrets/<name> as root-owned mode 0400 by default, and this
# harness is asserting the mechanism's own default rather than
# configuring an owner to make the check convenient.
log "[phase2c] Checking the age key landed with the ownership and mode --extra-files promises..."
KEY_STAT=$("$SSH_BIN" "${SSH_OPTS[@]}" -p "$SSH_PORT" -i "$ADMIN_KEY" root@127.0.0.1 \
  'stat -c "%a %U:%G" /var/lib/sops-nix/key.txt' 2>"$LOG_DIR/phase2c-key-stat.log") ||
  fail "assertion failed: /var/lib/sops-nix/key.txt is not present on the installed system — nixos-anywhere --extra-files did not plant the age key where castle.secrets.ageKeyFile expects it (see $LOG_DIR/phase2c-key-stat.log)"
if [ "$KEY_STAT" != "600 root:root" ]; then
  fail "assertion failed: /var/lib/sops-nix/key.txt is '$KEY_STAT', expected '600 root:root' — --extra-files preserves the staged permissions and forces root ownership (tar --no-same-owner), so this means the staging in this script, or that behavior, changed"
fi
log "[phase2c] PASS: age key present, mode 600, owned by root."

log "[phase2c] Asserting the fixture secret decrypted at first activation..."
printf '%s' "$FIXTURE_SECRET" >"$WORKDIR/expected-secret"
if ! "$SSH_BIN" "${SSH_OPTS[@]}" -p "$SSH_PORT" -i "$ADMIN_KEY" root@127.0.0.1 \
    'cat /run/secrets/harness-fixture' >"$WORKDIR/actual-secret" 2>"$LOG_DIR/phase2c-secret.log"; then
  fail "assertion failed: /run/secrets/harness-fixture does not exist on the installed system — the secrets pipeline (docs/tasks/0031) broke somewhere between encrypting the fixture and activation decrypting it; check the activation log in $LOG_DIR/phase2-first-boot.serial.log for sops-install-secrets, and $LOG_DIR/phase2c-secret.log"
fi
# cmp, not a shell string comparison: `$(...)` strips trailing newlines
# from both sides, which would let a mechanism that helpfully appended
# one pass a test whose whole point is that the value survives unchanged.
if ! cmp -s "$WORKDIR/expected-secret" "$WORKDIR/actual-secret"; then
  od -c "$WORKDIR/actual-secret" >"$LOG_DIR/phase2c-secret-actual.od" 2>&1 || true
  fail "assertion failed: /run/secrets/harness-fixture did not decrypt to the exact fixture value this run encrypted (byte dump: $LOG_DIR/phase2c-secret-actual.od)"
fi
log "[phase2c] PASS: the fixture secret decrypted byte-for-byte, with nobody at any keyboard."

# --- Phase 2d: the admin account was seeded from an encrypted secret ------
# docs/tasks/0032-password-hash.md. Still the same booted VM as phase 2,
# and a strictly stronger claim than phase 2c's: 2c proves a secret
# decrypted at *some* point during activation, which is all a plain
# sops.secrets entry promises. This proves one decrypted *before the
# admin account was created* — the ordering `neededForUsers` and
# sops-nix's `users.deps = [ "setupSecretsForUsers" ]` exist to
# guarantee, and the one that cannot be checked after the fact by
# looking at /run alone. If it had decrypted a moment too late,
# update-users-groups.pl would have created `harness` with a locked
# ("!") password and nothing else about this run would look different.
#
# It is also the assertion that makes the whole task safe to ship: get
# this wrong on real hardware and the failure mode is a machine nobody
# can log into. Nothing here is a password. The value under test is the
# opaque marker $FIXTURE_PASSWORD_HASH, invented by this script minutes
# ago and deliberately not shaped like a crypt hash.
#
# Reads /etc/shadow directly rather than via `getent shadow`: the claim
# is literally about that file's second field, and going through NSS
# would add a way for this assertion to fail (or, worse, pass) for
# reasons that have nothing to do with the pipeline under test. It is
# also exactly the read modules/base's own password-reminder check does.
# `tr -d '\n'` strips only the line terminator `cut` emits, so what
# `cmp` sees on both sides is the field's own bytes and nothing else.
log "[phase2d] Asserting the admin account's shadow entry came from the encrypted secret..."
printf '%s' "$FIXTURE_PASSWORD_HASH" >"$WORKDIR/expected-shadow"
if ! "$SSH_BIN" "${SSH_OPTS[@]}" -p "$SSH_PORT" -i "$ADMIN_KEY" root@127.0.0.1 \
    "grep -m1 '^harness:' /etc/shadow | cut -d: -f2 | tr -d '\n'" \
    >"$WORKDIR/actual-shadow" 2>"$LOG_DIR/phase2d-shadow.log"; then
  fail "assertion failed: could not read the harness account's /etc/shadow entry on the installed system (see $LOG_DIR/phase2d-shadow.log)"
fi
if ! cmp -s "$WORKDIR/expected-shadow" "$WORKDIR/actual-shadow"; then
  od -c "$WORKDIR/expected-shadow" >"$LOG_DIR/phase2d-shadow-expected.od" 2>&1 || true
  od -c "$WORKDIR/actual-shadow" >"$LOG_DIR/phase2d-shadow-actual.od" 2>&1 || true
  fail "assertion failed: the harness account's /etc/shadow password field is not the fixture value this run encrypted — castle.admin.hashedPasswordFile did not reach account creation (docs/tasks/0032-password-hash.md). A field of '!' means the secret had not decrypted when update-users-groups.pl ran, i.e. the neededForUsers ordering broke; anything else means something rewrote it. Byte dumps: $LOG_DIR/phase2d-shadow-expected.od and $LOG_DIR/phase2d-shadow-actual.od; check $LOG_DIR/phase2-first-boot.serial.log and $LOG_DIR/phase1-nixos-anywhere.log for sops-install-secrets"
fi
log "[phase2d] PASS: the admin account's password came from the encrypted secret, byte-for-byte, with nobody at any keyboard."

# --- Phase 2e: the seeded-password reminder reaches a real shell ----------
# docs/tasks/0036-reminder-banner-states.md. Same booted VM. The fixture
# secret always decrypts (phase 2d just proved it reached the account)
# and nobody has run passwd, so the installed system is
# deterministically in the reminder's "seeded" state:
# castle-password-reminder-check is wanted by multi-user.target, which
# this boot already reached, and must have left neither marker, so an
# interactive shell prints the seeded message naming the harness
# account. Asserted against a real interactive bash over SSH rather
# than by reading the generated /etc/bashrc, for the same reason the
# connected-banner check reads the serial console: the flake check
# (test/password-reminder/check.nix) already pins the wording, and the
# claim left for this harness is the *wiring* — that
# environment.interactiveShellInit actually reaches the shell a
# resident gets. `bash -ic true` has no tty, which interactive bash
# tolerates (job-control warnings at worst), and stderr is captured
# with stdout so the assertion cannot pass or fail on which stream the
# banner used. The grep string deliberately stops before the styled
# "passwd" so no escape bytes are part of the match.
log "[phase2e] Asserting the reminder check ran, then that its banner prints in an interactive shell..."
# First that the classifier actually ran and succeeded: "neither
# marker" is also what a crashed or never-started check leaves behind,
# and the seeded message would then print for the wrong reason,
# turning this assertion into a rubber stamp. `Result` alone does not
# prove invocation -- systemd initialises it to "success" before a
# unit has ever run, and this oneshot has no RemainAfterExit, so
# ActiveState is "inactive" both before its first run and after a
# successful one. `ExecMainStartTimestamp` is only set once the main
# process actually starts, so pairing it with `Result` catches the
# never-started case Result alone would rubber-stamp.
if ! "$SSH_BIN" "${SSH_OPTS[@]}" -p "$SSH_PORT" -i "$ADMIN_KEY" root@127.0.0.1 \
    "systemctl show -p Result,ExecMainStartTimestamp --value castle-password-reminder-check.service" \
    >"$WORKDIR/reminder-result" 2>"$LOG_DIR/phase2e-service.log"; then
  fail "assertion failed: could not read castle-password-reminder-check's unit state on the installed system (see $LOG_DIR/phase2e-service.log)"
fi
reminder_result="$(sed -n '1p' "$WORKDIR/reminder-result" | tr -d '\n')"
reminder_start_ts="$(sed -n '2p' "$WORKDIR/reminder-result" | tr -d '\n')"
if [ "$reminder_result" != "success" ] || [ -z "$reminder_start_ts" ]; then
  fail "assertion failed: castle-password-reminder-check did not run to success on the installed system (Result: $reminder_result, ExecMainStartTimestamp: $reminder_start_ts; see $LOG_DIR/phase2e-service.log)"
fi
if ! "$SSH_BIN" "${SSH_OPTS[@]}" -p "$SSH_PORT" -i "$ADMIN_KEY" harness@127.0.0.1 \
    "bash -ic true" >"$LOG_DIR/phase2e-banner.out" 2>&1; then
  fail "assertion failed: could not start an interactive bash as the harness account over SSH (see $LOG_DIR/phase2e-banner.out)"
fi
if ! grep -q "the harness account is still using its seeded initial password" "$LOG_DIR/phase2e-banner.out"; then
  fail "assertion failed: an interactive shell did not print the seeded-password reminder for the harness account (docs/tasks/0036-reminder-banner-states.md; output: $LOG_DIR/phase2e-banner.out). Either castle-password-reminder-check misclassified a freshly seeded account, or environment.interactiveShellInit never reached the shell."
fi
log "[phase2e] PASS: the check succeeded and the banner rendered in a real interactive shell, in the seeded state, naming the account."

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
