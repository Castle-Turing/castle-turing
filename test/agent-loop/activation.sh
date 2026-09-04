#!/usr/bin/env bash
# test/agent-loop/activation.sh — a build nobody authorized, a switch
# exactly one approval bought, and a window that rolls back what nothing
# confirmed (docs/tasks/0048-activation.md's verification plan, §K).
#
# **Its own file rather than more scenarios in apply.sh, because it
# inverts that file's closing assertion.** There, nothing may ever reach
# the running system: `assert_nothing_activated` holds after every
# scenario. Here asking the machine to move is the point, and what must
# not move is anything else — the framework checkout, the resident's own
# branch, and any repository on a path this seat was not given.
#
# Same conventions as apply.sh and outbox.sh otherwise: real git
# checkouts under $WORKDIR, a state repository beside them, a git
# identity scoped to this process, the notify stub, plain bash and
# stdlib python3, zero models, zero network. Every `nix`,
# `nixos-rebuild` and `systemctl` here is a stub that logs its own argv,
# and the argv comparison IS the assertion — nothing in this file builds
# anything, and nothing in it can change the machine it runs on.
#
# Nothing here is a real path, a real revision or a real configuration;
# every string is invented or reuses a placeholder this repo publishes.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CASTLE="$REPO_ROOT/agent/castle"
MODAL="$REPO_ROOT/agent/castle-modal"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/castle-activation.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT
WORKDIR="$(cd "$WORKDIR" && pwd -P)"

log() { printf '>>> %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

export GIT_AUTHOR_NAME="castle-activation-fixture"
export GIT_AUTHOR_EMAIL="fixture@example.invalid"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

# Isolation that survives `_run_git`'s GIT_* strip, for apply.sh's
# reason: this file commits, and a developer with `commit.gpgsign = true`
# set globally would otherwise watch every scenario fail for a reason
# unrelated to the code.
export HOME="$WORKDIR/nobody"
export XDG_CONFIG_HOME="$WORKDIR/nobody/.config"
mkdir -p "$XDG_CONFIG_HOME"

# ---------------------------------------------------------------------
log "1. the fixtures: a private layer, a framework checkout, a journal"
# ---------------------------------------------------------------------
PRIVATE="$WORKDIR/private"
mkdir -p "$PRIVATE"
cat > "$PRIVATE/flake.nix" <<'EOF'
# Synthetic private layer, harness fixture only. Never evaluated by
# anything in this file — every `nix` here is a stub.
{
  inputs.castle-turing.url = "github:Castle-Turing/castle-turing";
  outputs = { self, castle-turing, ... }: {
    nixosConfigurations.example-private = castle-turing.lib.placeholder;
  };
}
EOF
write_lock() {
  # $1 = target directory, $2 = revision
  cat > "$1/flake.lock" <<EOF
{
  "nodes": {
    "castle-turing": {
      "locked": {
        "owner": "Castle-Turing",
        "repo": "castle-turing",
        "rev": "$2",
        "type": "github"
      },
      "original": {
        "owner": "Castle-Turing",
        "repo": "castle-turing",
        "type": "github"
      }
    },
    "root": { "inputs": { "castle-turing": "castle-turing" } }
  },
  "root": "root",
  "version": 7
}
EOF
}
# The framework checkout. `origin/main` is a remote-tracking ref with no
# remote behind it, exactly as outbox.sh builds one: this seat reads that
# ref and never fetches, so a fixture with a real remote would be testing
# git rather than this code.
MECHANISM="$WORKDIR/mechanism"
mkdir -p "$MECHANISM"
git -C "$MECHANISM" init -q
echo "# a synthetic framework checkout" > "$MECHANISM/README.md"
git -C "$MECHANISM" add -A
git -C "$MECHANISM" commit -q -m "fixture: the framework, as this machine has it"
git -C "$MECHANISM" branch -q -M main
# Where the private layer is pinned to start with: current, so the pin
# trigger stays quiet until this fixture deliberately moves it.
git -C "$MECHANISM" update-ref refs/remotes/origin/main HEAD
OLD_REV="$(git -C "$MECHANISM" rev-parse HEAD)"
# And the framework work this machine has fetched but not adopted. It
# sits on `main` while `origin/main` still names the older commit, so
# nothing is behind yet.
echo "# and some work on top of it" >> "$MECHANISM/README.md"
git -C "$MECHANISM" commit -q -aqm "Teach the fixture something new"
NEW_REV="$(git -C "$MECHANISM" rev-parse HEAD)"
MECHANISM_AHEAD="$OLD_REV"
# The resident then goes and works on something else. No scenario here
# may move this.
git -C "$MECHANISM" checkout -q -b resident-work
git -C "$MECHANISM" commit -q --allow-empty -m "fixture: the resident is mid-something"
MECHANISM_BRANCH_HEAD="$(git -C "$MECHANISM" rev-parse HEAD)"

write_lock "$PRIVATE" "$OLD_REV"
git -C "$PRIVATE" init -q
git -C "$PRIVATE" add -A
git -C "$PRIVATE" commit -q -m "fixture: a synthetic private layer"
PRIVATE_BASE="$(git -C "$PRIVATE" rev-parse HEAD)"

STATE_REPO="$WORKDIR/private-state"
mkdir -p "$STATE_REPO"
git -C "$STATE_REPO" init -q
export CASTLE_STATE_DIR="$STATE_REPO"
export XDG_RUNTIME_DIR="$WORKDIR/runtime"
mkdir -p "$XDG_RUNTIME_DIR"
JOURNAL="$CASTLE_STATE_DIR/journal"

export CASTLE_NOTIFY_LOG="$WORKDIR/notify.log"
export CASTLE_NOTIFY_COMMAND="$REPO_ROOT/test/agent-loop/notify-stub.sh"
: > "$CASTLE_NOTIFY_LOG"

export CASTLE_PRIVATE_ROOT="$PRIVATE"
export CASTLE_MECHANISM_ROOT="$MECHANISM"
export CASTLE_ACTIVATION_WINDOW=60

# ---------------------------------------------------------------------
log "2. the stubs: every privileged or Nix-touching command logs its argv"
# ---------------------------------------------------------------------
STUB_BIN="$WORKDIR/stub-bin"
mkdir -p "$STUB_BIN"
export PATH="$STUB_BIN:$PATH"
NIX_ARGV="$WORKDIR/nix.argv"
SYSTEMCTL_ARGV="$WORKDIR/systemctl.argv"
: > "$NIX_ARGV"
: > "$SYSTEMCTL_ARGV"
export STUB_TOPLEVEL="/nix/store/0000000000000000000000000000000000000000-nixos-system-fixture"
export STUB_BUILD_RC=0
export STUB_SYSTEMCTL_RC=0
export STUB_UPDATE_REV="$NEW_REV"

cat > "$STUB_BIN/nix" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$@" >> "$NIX_ARGV"
printf -- '--\n' >> "$NIX_ARGV"
if [ "\${1:-}" = "flake" ] && [ "\${2:-}" = "update" ]; then
  # Where --flake points, write the lock this update would have
  # produced. The harness controls the revision it lands on, which is
  # what lets the "upstream and your checkout disagree" refusal be
  # tested at all.
  dir=""
  prev=""
  for arg in "\$@"; do
    if [ "\$prev" = "--flake" ]; then dir="\$arg"; fi
    prev="\$arg"
  done
  [ -n "\$dir" ] || { echo "stub nix: no --flake" >&2; exit 1; }
  sed -E "s/\"rev\": \"[0-9a-f]+\"/\"rev\": \"\$STUB_UPDATE_REV\"/" \
    "\$dir/flake.lock" > "\$dir/flake.lock.new"
  mv "\$dir/flake.lock.new" "\$dir/flake.lock"
  exit 0
fi
if [ "\${1:-}" = "build" ]; then
  if [ "\$STUB_BUILD_RC" != "0" ]; then
    echo "error: builder for '/nix/store/fixture.drv' failed" >&2
    exit "\$STUB_BUILD_RC"
  fi
  printf '%s\n' "\$STUB_TOPLEVEL"
  exit 0
fi
echo "stub nix: unexpected subcommand \$*" >&2
exit 1
STUB

cat > "$STUB_BIN/systemctl" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$SYSTEMCTL_ARGV"
exit "\$STUB_SYSTEMCTL_RC"
STUB

# Never invoked by castle — the privileged units hold it, and castle only
# ever names a unit. Present so that a regression which reached for it
# directly is caught as a logged invocation rather than as a missing
# binary somebody later "fixes" by installing one.
cat > "$STUB_BIN/nixos-rebuild" <<STUB
#!/usr/bin/env bash
printf 'nixos-rebuild %s\n' "\$*" >> "$WORKDIR/forbidden.log"
exit 0
STUB
chmod +x "$STUB_BIN/nix" "$STUB_BIN/systemctl" "$STUB_BIN/nixos-rebuild"
: > "$WORKDIR/forbidden.log"

# ---------------------------------------------------------------------
# Journal helpers, copied from apply.sh and outbox.sh rather than shared:
# these are plain bash harnesses with no library between them.
# ---------------------------------------------------------------------
newest_of() { xargs -r stat -c '%.Y	%n' 2>/dev/null | sort -k1,1n | tail -1 | cut -f2-; }
field_of() { sed -n "s/^$2: //p" "$1"; }
newest_with() {
  # $1 = "field: value", $2 = record type glob
  grep -l "^$1\$" "$JOURNAL"/*-"$2"-*.md 2>/dev/null | newest_of
}
id_of() { basename "$1" .md; }
assert_mechanism_untouched() {
  [ "$(git -C "$MECHANISM" rev-parse --abbrev-ref HEAD)" = "resident-work" ] \
    || fail "$1: the framework checkout is no longer on the resident's branch"
  [ "$(git -C "$MECHANISM" rev-parse HEAD)" = "$MECHANISM_BRANCH_HEAD" ] \
    || fail "$1: the framework checkout's branch moved"
  [ "$(git -C "$MECHANISM" rev-parse refs/remotes/origin/main)" = "$MECHANISM_AHEAD" ] \
    || fail "$1: origin/main in the framework checkout moved — something fetched"
  [ -z "$(git -C "$MECHANISM" status --porcelain)" ] \
    || fail "$1: the framework checkout has a dirty working tree"
}
assert_no_direct_rebuild() {
  [ ! -s "$WORKDIR/forbidden.log" ] \
    || fail "$1: something ran nixos-rebuild directly instead of naming a unit: $(cat "$WORKDIR/forbidden.log")"
}


# A complete applied-change chain, the shape the applier leaves behind:
# a worker result carrying the proposal, a question stamped as one, the
# resident's approval of it, and the applier's own account. Built here
# rather than by running the applier, so this file tests the activation
# seats and not that one — and held to the schema either way, because
# `castle validate` at the end reads all of it.
plant_applied_change() {
  local what="$1" proposal question answer
  proposal="$("$CASTLE" record --type result --provenance requested --seat worker \
    --refs "" --outcome completed --target private --body "$what")"
  question="$("$CASTLE" record --type question --provenance requested --seat worker \
    --refs "$proposal,$proposal" --body "A change to your configuration.")"
  python3 - "$JOURNAL" "$question" "$proposal" <<'PLANT'
import hashlib, pathlib, sys
journal, question, proposal = sys.argv[1:4]
digest = hashlib.sha256((pathlib.Path(journal) / f"{proposal}.md").read_bytes()).hexdigest()
path = pathlib.Path(journal) / f"{question}.md"
path.write_text(path.read_text().replace(
    "created:", f"authorizes-apply: true\nproposal-sha256: {digest}\ncreated:", 1))
PLANT
  answer="$("$CASTLE" answer --decision approve "$question" <<< "fixture approval")"
  python3 - "$JOURNAL" "$answer" "$question" <<'PLANT'
import pathlib, subprocess, sys
journal, answer, question = sys.argv[1:4]
out = subprocess.run(
    ["agent/castle", "record", "--type", "result", "--provenance", "requested",
     "--seat", "applier", "--refs", f"{answer},{question}", "--outcome", "completed",
     "--body", "The change you approved is now in your configuration repository."],
    capture_output=True, text=True, check=True,
)
rid = out.stdout.strip()
path = pathlib.Path(journal) / f"{rid}.md"
path.write_text(path.read_text().replace(
    "outcome: completed", "outcome: completed\napply-outcome: applied-validated", 1))
print(rid)
PLANT
}

# ---------------------------------------------------------------------
log "3. with no trigger, a build is not owed and nothing is written"
# ---------------------------------------------------------------------
"$CASTLE" build > "$WORKDIR/idle.txt" 2>&1 || fail "an idle build did not exit 0"
grep -q "the framework pin is already current" "$WORKDIR/idle.txt" \
  || fail "an idle build said something else: $(cat "$WORKDIR/idle.txt")"
[ "$(ls "$JOURNAL" 2>/dev/null | wc -l)" = "0" ] \
  || fail "an idle build wrote records"

# ---------------------------------------------------------------------
log "4. an applied private-layer change is a trigger, and needs no permission"
# ---------------------------------------------------------------------
# The shape the applier leaves behind: a question, an approving answer,
# and an apply result naming both. Built with the generic writer so this
# file tests the activation seats and not the applier.
APPLY_RESULT="$(plant_applied_change "A change to your configuration." | tail -1)"
[ -n "$APPLY_RESULT" ] || fail "the apply-result fixture was not written"

"$CASTLE" build > "$WORKDIR/build1.txt" 2>&1 || fail "the first build failed: $(cat "$WORKDIR/build1.txt")"
BUILD1="$(newest_with "build-outcome: built" result)"
[ -n "$BUILD1" ] || fail "no built result was written: $(cat "$WORKDIR/build1.txt")"
BUILD1_ID="$(id_of "$BUILD1")"
[ "$(field_of "$BUILD1" seat)" = "builder" ] || fail "the build result is not the builder seat's"
[ "$(field_of "$BUILD1" provenance)" = "initiated" ] \
  || fail "a build nobody asked for is not 'initiated'"
[ "$(field_of "$BUILD1" build-toplevel)" = "$STUB_TOPLEVEL" ] \
  || fail "the build result does not name the closure that was built"
grep -q "^refs: $APPLY_RESULT\$" "$BUILD1" \
  || fail "the build result does not name the apply result that triggered it"
grep -q -- "--print-out-paths" "$NIX_ARGV" \
  || fail "the build did not ask nix for the store path it records"
grep -q -- "--no-write-lock-file" "$NIX_ARGV" \
  || fail "the build could rewrite the resident's lock file"
grep -q -- "$PRIVATE#nixosConfigurations" "$NIX_ARGV" \
  || fail "the applied-change build did not build the resident's own checkout"
grep -q "flake" "$NIX_ARGV" && grep -q "^update$" "$NIX_ARGV" \
  && fail "the applied-change build updated a lock; nothing about the pin moves here"
assert_no_direct_rebuild "the build"

log "   ... and it files a question stamped as an activation authority"
ACT_Q="$(newest_with "authorizes-activation: true" question)"
[ -n "$ACT_Q" ] || fail "a clean build filed no activation question"
ACT_Q_ID="$(id_of "$ACT_Q")"
grep -q "^refs: $APPLY_RESULT,$BUILD1_ID\$" "$ACT_Q" \
  || fail "the activation question's refs are not [anchor, build result]: $(field_of "$ACT_Q" refs)"
[ -n "$(field_of "$ACT_Q" proposal-sha256)" ] \
  || fail "the activation question carries no proposal hash, so nothing can bind to it"
grep -q "^authorizes-apply:" "$ACT_Q" \
  && fail "the activation question also claims apply authority"
grep -q "^blocking:" "$ACT_Q" \
  && fail "the activation question is blocking, so approving it could start a worker turn"
grep -q "^fact:" "$ACT_Q" \
  && fail "the activation question elicits a fact, so approving it would write the resident model"
grep -q "kernel" "$ACT_Q" \
  || fail "the question's own body does not say what a switch cannot fully apply"

log "   ... and the same trigger does not fire twice"
"$CASTLE" build > "$WORKDIR/build2.txt" 2>&1 || fail "the second build did not exit 0"
grep -q "nothing to build" "$WORKDIR/build2.txt" \
  || fail "the applied-change trigger fired again: $(cat "$WORKDIR/build2.txt")"

# ---------------------------------------------------------------------
log "5. the review screen says what approving does, and says it exactly"
# ---------------------------------------------------------------------
printf 'x\n' | "$MODAL" --mode review --question "$ACT_Q_ID" > "$WORKDIR/review1.txt" 2>&1 \
  || fail "reviewing the activation question failed: $(cat "$WORKDIR/review1.txt")"
REVIEW="$(tr -d '\r' < "$WORKDIR/review1.txt")"
printf '%s\n' "$REVIEW" | grep -q "APPROVING SWITCHES THE RUNNING SYSTEM TO THE BUILD DESCRIBED BELOW" \
  || fail "the review does not say approving switches this machine: $REVIEW"
printf '%s\n' "$REVIEW" | grep -q "A SWITCH DOES NOT APPLY EVERYTHING" \
  || fail "the review does not say what a switch cannot apply: $REVIEW"
printf '%s\n' "$REVIEW" | grep -q "ROLL BACK ON" \
  || fail "the review does not warn that the window rolls back: $REVIEW"
printf '%s\n' "$REVIEW" | grep -q "NOTHING IS ACTIVATED AND NOTHING IS REBUILT" \
  && fail "the activation review printed the APPLY statement, which is a false promise here"
printf '%s\n' "$REVIEW" | grep -q "NOTHING ON THIS MACHINE IS EDITED" \
  && fail "the activation review printed the pre-apply statement"

# ---------------------------------------------------------------------
log "6. approving spends exactly one authorization and asks one unit to switch"
# ---------------------------------------------------------------------
printf 'a\n.\n' | "$MODAL" --mode review --question "$ACT_Q_ID" > "$WORKDIR/approve1.txt" 2>&1 \
  || fail "approving the activation failed: $(cat "$WORKDIR/approve1.txt")"
grep -q "This machine is switching now" "$WORKDIR/approve1.txt" \
  || fail "the confirmation does not say the machine is switching: $(cat "$WORKDIR/approve1.txt")"
[ ! -s "$SYSTEMCTL_ARGV" ] || fail "approving alone reached the system manager"

"$CASTLE" activate --sweep > "$WORKDIR/act1.txt" 2>&1 || fail "the sweep failed: $(cat "$WORKDIR/act1.txt")"
SWITCHED="$(newest_with "activation-outcome: switched" result)"
[ -n "$SWITCHED" ] || fail "no switched result: $(cat "$WORKDIR/act1.txt")"
SWITCHED_ID="$(id_of "$SWITCHED")"
[ "$(field_of "$SWITCHED" seat)" = "activation" ] || fail "the switch is not the activation seat's"
grep -qx "start castle-activate.service" "$SYSTEMCTL_ARGV" \
  || fail "the sweep did not start the activation unit: $(cat "$SYSTEMCTL_ARGV")"
[ "$(grep -c . "$SYSTEMCTL_ARGV")" = "1" ] \
  || fail "the sweep touched the system manager more than once: $(cat "$SYSTEMCTL_ARGV")"
grep -q "no-block" "$SYSTEMCTL_ARGV" \
  && fail "the switch did not wait for the unit, so its outcome is a guess"
grep -q "^activation-commit:" "$SWITCHED" \
  && fail "an applied-change activation stamped a commit it never made"
assert_no_direct_rebuild "the switch"
assert_mechanism_untouched "the switch"

log "   ... and re-sweeping does not spend it again"
"$CASTLE" activate --sweep > "$WORKDIR/act2.txt" 2>&1 || true
[ "$(grep -c . "$SYSTEMCTL_ARGV")" = "1" ] \
  || fail "a second sweep spent the same approval again: $(cat "$SYSTEMCTL_ARGV")"

# ---------------------------------------------------------------------
log "7. the switch opens a health window, and the screen says defer expires"
# ---------------------------------------------------------------------
HEALTH_Q="$(newest_with "confirms-activation: $SWITCHED_ID" question)"
[ -n "$HEALTH_Q" ] || fail "the switch filed no health question"
HEALTH_Q_ID="$(id_of "$HEALTH_Q")"
grep -q "^authorizes-activation:" "$HEALTH_Q" \
  && fail "the health question claims switching authority"
printf 'x\n' | "$MODAL" --mode review --question "$HEALTH_Q_ID" > "$WORKDIR/review2.txt" 2>&1 \
  || fail "reviewing the health question failed"
HREVIEW="$(tr -d '\r' < "$WORKDIR/review2.txt")"
printf '%s\n' "$HREVIEW" | grep -q "SETTING IT ASIDE DECIDES NOTHING, AND THE WINDOW STILL RUNS OUT" \
  || fail "the health review does not say deferring still rolls back: $HREVIEW"
printf '%s\n' "$HREVIEW" | grep -q "Nothing you press here switches" \
  || fail "the health review does not say the switch already happened: $HREVIEW"

log "   ... and confirming keeps the generation, with nothing privileged run"
BEFORE="$(grep -c . "$SYSTEMCTL_ARGV")"
printf 'a\n.\n' | "$MODAL" --mode review --question "$HEALTH_Q_ID" > "$WORKDIR/confirm.txt" 2>&1 \
  || fail "confirming failed: $(cat "$WORKDIR/confirm.txt")"
grep -q "keeps the configuration it switched to" "$WORKDIR/confirm.txt" \
  || fail "the confirmation line is wrong: $(cat "$WORKDIR/confirm.txt")"
"$CASTLE" activate --sweep > "$WORKDIR/act3.txt" 2>&1 || fail "the closing sweep failed"
CONFIRMED="$(newest_with "activation-outcome: confirmed" result)"
[ -n "$CONFIRMED" ] || fail "confirming wrote no closing record"
[ "$(grep -c . "$SYSTEMCTL_ARGV")" = "$BEFORE" ] \
  || fail "confirming ran a privileged command: $(cat "$SYSTEMCTL_ARGV")"

log "   ... and a closed window is not closed twice"
"$CASTLE" activate --close-window > "$WORKDIR/act4.txt" 2>&1 || fail "close-window failed"
grep -q "no health window is open" "$WORKDIR/act4.txt" \
  || fail "the window reopened: $(cat "$WORKDIR/act4.txt")"

# ---------------------------------------------------------------------
log "8. a build that fails files a result and asks nothing"
# ---------------------------------------------------------------------
echo "# another applied change" >> "$PRIVATE/resident.nix"
git -C "$PRIVATE" add -A
git -C "$PRIVATE" commit -q -m "fixture: another applied change"
PRIVATE_BASE="$(git -C "$PRIVATE" rev-parse HEAD)"
APPLY2="$(plant_applied_change "A second change to your configuration." | tail -1)"
QUESTIONS_BEFORE="$(ls "$JOURNAL"/*-question-*.md | wc -l)"
STUB_BUILD_RC=1 "$CASTLE" build > "$WORKDIR/build3.txt" 2>&1 && fail "a failed build exited 0"
FAILED="$(newest_with "build-outcome: build-failed" result)"
[ -n "$FAILED" ] || fail "a failed build wrote no result"
[ "$(field_of "$FAILED" outcome)" = "failed" ] || fail "a failed build is not outcome: failed"
[ "$(ls "$JOURNAL"/*-question-*.md | wc -l)" = "$QUESTIONS_BEFORE" ] \
  || fail "a failed build asked the resident to approve something"
grep -q "builder for" "$FAILED" || fail "the failed build kept no log tail"

# ---------------------------------------------------------------------
log "9. the pin trigger: behind by one, built in a throwaway worktree"
# ---------------------------------------------------------------------
# The applied-change trigger is now spent (the failed build named it).
# Now the resident fetches, and the pin is one commit behind.
git -C "$MECHANISM" update-ref refs/remotes/origin/main "$NEW_REV"
MECHANISM_AHEAD="$NEW_REV"
"$CASTLE" build > "$WORKDIR/build4.txt" 2>&1 || fail "the pin build failed: $(cat "$WORKDIR/build4.txt")"
PINBUILD="$(newest_with "build-target-rev: $NEW_REV" result)"
[ -n "$PINBUILD" ] || fail "the pin trigger did not fire: $(cat "$WORKDIR/build4.txt")"
PINBUILD_ID="$(id_of "$PINBUILD")"
[ "$(field_of "$PINBUILD" build-outcome)" = "built" ] || fail "the pin build did not build"
[ "$(field_of "$PINBUILD" build-base-commit)" = "$PRIVATE_BASE" ] \
  || fail "the pin build did not record which commit it was made against"
[ -n "$(field_of "$PINBUILD" lock-sha256)" ] \
  || fail "the pin build carries no byte digest for the lock it proposes"
grep -q "$NEW_REV" "$PINBUILD" || fail "the pin build's body does not carry the new lock"
grep -q "Teach the fixture something new" "$PINBUILD" \
  || fail "the pin build does not name the work it adopts, only its hash"
[ -z "$(git -C "$PRIVATE" status --porcelain)" ] \
  || fail "the pin build left the resident's checkout dirty"
[ "$(git -C "$PRIVATE" rev-parse HEAD)" = "$PRIVATE_BASE" ] \
  || fail "the pin build moved the resident's checkout"
grep -q "$OLD_REV" "$PRIVATE/flake.lock" \
  || fail "the pin build rewrote the resident's lock before anyone approved it"
git -C "$PRIVATE" worktree list | grep -q candidate \
  && fail "the pin build left its throwaway worktree registered"
assert_mechanism_untouched "the pin build"

# ---------------------------------------------------------------------
log "10. a repository that moved after the build refuses the switch"
# ---------------------------------------------------------------------
PIN_Q="$(newest_with "authorizes-activation: true" question)"
PIN_Q_ID="$(id_of "$PIN_Q")"
printf 'a\n.\n' | "$MODAL" --mode review --question "$PIN_Q_ID" > "$WORKDIR/approve2.txt" 2>&1 \
  || fail "approving the pin bump failed: $(cat "$WORKDIR/approve2.txt")"
git -C "$PRIVATE" commit -q --allow-empty -m "fixture: the resident lands something else"
MOVED="$(git -C "$PRIVATE" rev-parse HEAD)"
SYS_BEFORE="$(grep -c . "$SYSTEMCTL_ARGV")"
"$CASTLE" activate --sweep > "$WORKDIR/act5.txt" 2>&1 || true
STALE="$(newest_with "activation-outcome: refused-pin-stale" result)"
[ -n "$STALE" ] || fail "a moved repository did not refuse the switch: $(cat "$WORKDIR/act5.txt")"
[ "$(grep -c . "$SYSTEMCTL_ARGV")" = "$SYS_BEFORE" ] \
  || fail "a refused activation still asked the machine to switch"
grep -q "$OLD_REV" "$PRIVATE/flake.lock" \
  || fail "a refused activation rewrote the lock anyway"
[ "$(git -C "$PRIVATE" rev-parse HEAD)" = "$MOVED" ] \
  || fail "a refused activation committed something"

# ---------------------------------------------------------------------
log "11. a pin bump that does fit lands byte-exact in one commit, then switches"
# ---------------------------------------------------------------------
# The refusal spent that approval, so this builds and approves again —
# now against where the repository actually is.
"$CASTLE" build > "$WORKDIR/build5.txt" 2>&1 || fail "the second pin build failed: $(cat "$WORKDIR/build5.txt")"
PINBUILD2="$(newest_with "build-outcome: built" result)"
PINBUILD2_ID="$(id_of "$PINBUILD2")"
[ "$PINBUILD2_ID" != "$PINBUILD_ID" ] \
  || fail "the pin trigger did not fire again after its first attempt was refused"
PIN_Q2="$(newest_with "authorizes-activation: true" question)"
PIN_Q2_ID="$(id_of "$PIN_Q2")"
printf 'a\n.\n' | "$MODAL" --mode review --question "$PIN_Q2_ID" > "$WORKDIR/approve3.txt" 2>&1 \
  || fail "approving the second pin bump failed"
"$CASTLE" activate --sweep > "$WORKDIR/act6.txt" 2>&1 || fail "the pin activation failed: $(cat "$WORKDIR/act6.txt")"
SWITCHED2="$(newest_with "activation-outcome: switched" result)"
SWITCHED2_ID="$(id_of "$SWITCHED2")"
[ "$SWITCHED2_ID" != "$SWITCHED_ID" ] || fail "no second switch was recorded"
grep -q "$NEW_REV" "$PRIVATE/flake.lock" \
  || fail "the approved lock was not written to the resident's repository"
[ "$(git -C "$PRIVATE" rev-list --count "$MOVED"..HEAD)" = "1" ] \
  || fail "the pin bump landed more or fewer than one commit"
COMMIT="$(field_of "$SWITCHED2" activation-commit)"
[ "$COMMIT" = "$(git -C "$PRIVATE" rev-parse HEAD)" ] \
  || fail "the record's activation-commit is not the commit that landed"
git -C "$PRIVATE" log -1 --format=%an | grep -qx "Castle activation" \
  || fail "the pin-bump commit is not attributed to the seat that made it"
git -C "$PRIVATE" log -1 --format=%B | grep -q "Nothing was pushed" \
  || fail "the commit message does not say nothing was pushed"
git -C "$PRIVATE" show --stat --format= HEAD | grep -qx " flake.lock | 2 +-" \
  || git -C "$PRIVATE" show --name-only --format= HEAD | grep -qx "flake.lock" \
  || fail "the pin-bump commit touched something other than flake.lock"
[ -z "$(git -C "$PRIVATE" status --porcelain -- flake.lock)" ] \
  || fail "the working tree was not brought up to the commit"
grep -qx "start castle-activate.service" "$SYSTEMCTL_ARGV" \
  || fail "the pin activation did not ask the machine to switch"
assert_no_direct_rebuild "the pin activation"
assert_mechanism_untouched "the pin activation"

# ---------------------------------------------------------------------
log "12. a window nothing confirms rolls the machine back"
# ---------------------------------------------------------------------
HEALTH_Q2="$(newest_with "confirms-activation: $SWITCHED2_ID" question)"
[ -n "$HEALTH_Q2" ] || fail "the second switch filed no health question"
"$CASTLE" activate --sweep > "$WORKDIR/act7.txt" 2>&1 || true
grep -qx "start castle-rollback.service" "$SYSTEMCTL_ARGV" \
  && fail "the resident's own sweep rolled back a window nobody had decided"
# The deadline arrives. This is what the privileged system unit runs.
"$CASTLE" activate --close-window > "$WORKDIR/act8.txt" 2>&1 || fail "close-window failed: $(cat "$WORKDIR/act8.txt")"
ROLLED="$(newest_with "activation-outcome: rolled-back" result)"
[ -n "$ROLLED" ] || fail "an unconfirmed window did not roll back: $(cat "$WORKDIR/act8.txt")"
grep -qx "start castle-rollback.service" "$SYSTEMCTL_ARGV" \
  || fail "the rollback did not ask the rollback unit: $(cat "$SYSTEMCTL_ARGV")"
grep -q "costs you\|costs a re-approval\|costs a trip" "$ROLLED" \
  || fail "the rollback record does not state the trade it was made on"
assert_no_direct_rebuild "the rollback"

# ---------------------------------------------------------------------
log "13. a switch the machine refuses is recorded as one, and opens no window"
# ---------------------------------------------------------------------
# One more framework commit, so there is something to build and approve.
git -C "$MECHANISM" branch -q -f main "$NEW_REV"
THIRD_REV="$(git -C "$MECHANISM" commit-tree -p "$NEW_REV" -m "Teach the fixture one more thing" "$NEW_REV^{tree}")"
git -C "$MECHANISM" update-ref refs/heads/main "$THIRD_REV"
git -C "$MECHANISM" update-ref refs/remotes/origin/main "$THIRD_REV"
MECHANISM_AHEAD="$THIRD_REV"
STUB_UPDATE_REV="$THIRD_REV" "$CASTLE" build > "$WORKDIR/build6.txt" 2>&1 \
  || fail "the third build failed: $(cat "$WORKDIR/build6.txt")"
FAIL_Q="$(newest_with "authorizes-activation: true" question)"
FAIL_Q_ID="$(id_of "$FAIL_Q")"
printf 'a\n.\n' | "$MODAL" --mode review --question "$FAIL_Q_ID" > "$WORKDIR/approve4.txt" 2>&1 \
  || fail "approving the third build failed"
QUESTIONS_BEFORE="$(ls "$JOURNAL"/*-question-*.md | wc -l)"
STUB_SYSTEMCTL_RC=1 "$CASTLE" activate --sweep > "$WORKDIR/act9.txt" 2>&1 || true
SWFAIL="$(newest_with "activation-outcome: switch-failed" result)"
[ -n "$SWFAIL" ] || fail "a refused switch was not recorded: $(cat "$WORKDIR/act9.txt")"
[ "$(ls "$JOURNAL"/*-question-*.md | wc -l)" = "$QUESTIONS_BEFORE" ] \
  || fail "a failed switch opened a health window on a machine that never moved"
grep -q "still running what it was running before" "$SWFAIL" \
  || fail "the failed-switch record does not say the machine did not move"
# The pin bump was committed before the switch was asked for, so it is
# still there — and the record names the commit, so a resident can
# revert it. That is the honest state, not a hidden rollback.
[ -n "$(field_of "$SWFAIL" activation-commit)" ] \
  || fail "a failed switch that had already committed a pin bump did not name the commit"

log "   ... and an update landing somewhere else than the checkout said is refused"
git -C "$MECHANISM" update-ref refs/remotes/origin/main "$NEW_REV"
MECHANISM_AHEAD="$NEW_REV"
QUESTIONS_BEFORE="$(ls "$JOURNAL"/*-question-*.md | wc -l)"
STUB_UPDATE_REV="$THIRD_REV" "$CASTLE" build > "$WORKDIR/build7.txt" 2>&1 || true
DISAGREE="$(newest_with "build-outcome: refused-pin-unresolvable" result)"
[ -n "$DISAGREE" ] || fail "a lock update landing on the wrong revision was not refused"
grep -q "landed on a different revision" "$DISAGREE" \
  || fail "the refusal does not say the two disagree: $(cat "$DISAGREE")"
[ "$(ls "$JOURNAL"/*-question-*.md | wc -l)" = "$QUESTIONS_BEFORE" ] \
  || fail "a refusal it could not describe was still offered for approval"

# ---------------------------------------------------------------------
log "14. a worker turn cannot build or switch, whatever its prompt says"
# ---------------------------------------------------------------------
CASTLE_WORKER_CLAIM="20260301T000000Z-claim-fixture" "$CASTLE" build > "$WORKDIR/guard1.txt" 2>&1 \
  && fail "a worker turn was allowed to start a build"
grep -q "refusing to build anything from inside a worker turn" "$WORKDIR/guard1.txt" \
  || fail "the build guard said something else: $(cat "$WORKDIR/guard1.txt")"
CASTLE_WORKER_CLAIM="20260301T000000Z-claim-fixture" "$CASTLE" activate --sweep > "$WORKDIR/guard2.txt" 2>&1 \
  && fail "a worker turn was allowed to switch this machine"
grep -q "refusing to change this machine from inside a worker turn" "$WORKDIR/guard2.txt" \
  || fail "the activation guard said something else: $(cat "$WORKDIR/guard2.txt")"

# ---------------------------------------------------------------------
log "15. the journal validates, and nothing in it names this machine"
# ---------------------------------------------------------------------
"$CASTLE" validate || fail "the journal this run produced does not validate"
if grep -rIl "$HOME" "$JOURNAL" >/dev/null 2>&1; then
  fail "a record names this fixture's home directory"
fi
assert_mechanism_untouched "the end"
assert_no_direct_rebuild "the end"

log "activation.sh: all scenarios passed"
