#!/usr/bin/env bash
# test/agent-loop/approval.sh — the resident decides a proposed change
# (docs/tasks/0025-approval.md's verification plan).
#
# Same shape and same conventions as config-target.sh, whose fixture
# this reuses rather than reinventing: two real git checkouts under
# $WORKDIR, a state repository beside them rather than inside either,
# the same scoped git identity, the same notify stub, and — the
# assertion this whole task turns on — the same
# `assert_checkouts_untouched`, called after every scenario. Plain bash
# and stdlib python3, no Nix, zero models, zero network.
#
# What it proves, in one sentence: a completed turn with a real diff
# files exactly one change for the resident to decide, the resident can
# approve, reject or set it aside through either write path, every way
# of getting that wrong is refused with nothing written, and NOTHING ON
# DISK MOVES in any of those cases. Applying an approved change is
# docs/tasks/0026 and activating one is 0027; if either ever starts
# happening here, `assert_checkouts_untouched` is what says so.
#
# Nothing in here is a real path, a real complaint or a real decision:
# every string is invented or reuses a placeholder this repo already
# publishes.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CASTLE="$REPO_ROOT/agent/castle"
MODAL="$REPO_ROOT/agent/castle-modal"
WORKER="$REPO_ROOT/test/agent-loop/contract-worker.sh"
PTY_DRIVE="$REPO_ROOT/test/agent-loop/pty-drive.py"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/castle-approval.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

log() { printf '>>> %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Committing needs an identity, and a developer's own git config must
# not decide whether this test passes. Scoped to this process only.
export GIT_AUTHOR_NAME="castle-approval-fixture"
export GIT_AUTHOR_EMAIL="fixture@example.invalid"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

# This harness is not about window geometry, and a review driven on a
# pty here has two real ttys, so `_resize_for_review`'s double-tty gate
# does not exclude it (that is deliberate — see the modal harness,
# which asserts the shell-out really is attempted there). Opting out
# explicitly, the documented "don't even try" spelling, so a developer
# running this on a machine that genuinely has Sway cannot have their
# session poked by a test about approvals.
export CASTLE_REVIEW_RESIZE_COMMAND=""

# ---------------------------------------------------------------------
log "building the two checkouts"
# ---------------------------------------------------------------------
# `git archive` rather than `cp -r`, the same choice and for the same
# two reasons config-target.sh gives: only committed content, so no
# untracked scratch file from a developer's live worktree leaks into a
# fixture, and what the fixture holds is the real current module
# surface rather than a synthetic stand-in free to drift.
MECHANISM="$WORKDIR/mechanism"
mkdir -p "$MECHANISM"
git -C "$REPO_ROOT" archive HEAD | tar -x -C "$MECHANISM"
git -C "$MECHANISM" init -q
git -C "$MECHANISM" add -A
git -C "$MECHANISM" commit -q -m "fixture: this framework at HEAD"

# Synthetic, and every literal in it is one this repo already
# publishes: nixosConfigurations.example's "resident" admin username
# and its placeholder key string.
PRIVATE="$WORKDIR/private"
mkdir -p "$PRIVATE"
cat > "$PRIVATE/flake.nix" <<'EOF'
# Synthetic private flake, harness fixture only.
{
  inputs.castle-turing.url = "github:Castle-Turing/castle-turing";
  outputs = { self, castle-turing, ... }: {
    nixosConfigurations.example-private = castle-turing.lib.placeholder;
  };
}
EOF
cat > "$PRIVATE/resident.nix" <<'EOF'
# Synthetic private layer, harness fixture only.
{
  castle.admin.username = "resident";
  castle.admin.sshKeys = [
    "ssh-ed25519 REPLACE-WITH-YOUR-PUBLIC-KEY this-is-a-placeholder-not-a-key"
  ];
}
EOF
git -C "$PRIVATE" init -q
git -C "$PRIVATE" add -A
git -C "$PRIVATE" commit -q -m "fixture: a synthetic private layer"

PRIVATE_HEAD="$(git -C "$PRIVATE" rev-parse HEAD)"
MECHANISM_HEAD="$(git -C "$MECHANISM" rev-parse HEAD)"

# Beside the private checkout, never inside it: a state directory in
# the tracked tree of a repo carrying a flake.nix is exactly what
# `castle validate` warns about (docs/tasks/0030-state-outside-the-
# flake.md), and this fixture would otherwise spend its CI run
# demonstrating the layout the docs tell a resident not to use.
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

export CASTLE_WORKER_COMMAND="$WORKER"
export CASTLE_TEST_CASTLE_BIN="$CASTLE"
export CASTLE_PRIVATE_ROOT="$PRIVATE"
# Exported, which it was not before: `assert_checkouts_untouched` asserts
# the mechanism checkout is unmutated after every scenario, and with this
# unset `castle` never learned the path, so no code under test could have
# touched it and half that assertion had no failure mode at all — a
# whole-repo `git archive` per run buying nothing. Exporting it makes the
# assertion real, and it is what lets the `target: mechanism` scenario
# below exist: until it did, nothing anywhere covered a proposal against
# the framework checkout.
export CASTLE_MECHANISM_ROOT="$MECHANISM"

referencing() {
  local rtype="$1" id="$2"
  grep -l "^refs: .*$id" "$JOURNAL"/*-"$rtype"-*.md 2>/dev/null || true
}
count_referencing() { referencing "$1" "$2" | grep -c . || true; }
# The newest result for an errand, by MTIME and not by filename — ids
# carry a one-second timestamp and a random suffix, so two records
# written inside the same second sort by chance. `%.Y` and not `%Y`,
# for the same reason one second is not enough: whole-second mtimes tie
# and fall back to filename order again.
newest_result_for() {
  local id="$1"
  referencing result "$id" \
    | xargs -r stat -c '%.Y	%n' 2>/dev/null \
    | sort -k1,1n \
    | tail -1 \
    | cut -f2-
}
# The proposal question for an errand: the one question in its fold
# carrying the stamp. Found by the field, never by its wording — the
# same discipline the code itself follows.
proposal_question_for() {
  local request_id="$1" path
  path="$(grep -l "^refs: $request_id," "$JOURNAL"/*-question-*.md 2>/dev/null \
    | xargs -r grep -l '^proposal-sha256: ' | head -1 || true)"
  [ -n "$path" ] || return 0
  basename "$path" .md
}
answers_naming() { grep -l "^refs: $1[,$]" "$JOURNAL"/*-answer-*.md 2>/dev/null || true; }
pending_proposals() {
  local path id
  for path in $(grep -l '^proposal-sha256: ' "$JOURNAL"/*-question-*.md 2>/dev/null || true); do
    id="$(basename "$path" .md)"
    [ -n "$(answers_naming "$id")" ] || printf '%s\n' "$id"
  done
}
# Every interactive assertion below needs a fold it fully controls: an
# interactive review ignores --question and chooses for itself, exactly
# as answer mode does and for the same reason, so a change left pending
# by an earlier scenario is a silent off-by-one in a later one's picker
# — the same discipline modal-headless-test.sh already keeps for its
# own section. Deferring is the honest way to clear one: it is a real
# decision a resident can make, and it leaves the journal in a state
# this harness then re-asserts.
clear_pending_proposals() {
  local id
  for id in $(pending_proposals); do
    "$CASTLE" answer --decision defer "$id" </dev/null >/dev/null \
      || fail "could not clear pending change $id before an interactive scenario"
  done
  [ -z "$(pending_proposals)" ] || fail "changes are still pending after clearing: $(pending_proposals)"
}
journal_file_count() { find "$JOURNAL" -name '*.md' | wc -l | tr -d ' '; }
model_byte_count() {
  if [ -f "$CASTLE_STATE_DIR/resident-model.md" ]; then
    wc -c < "$CASTLE_STATE_DIR/resident-model.md" | tr -d ' '
  else
    echo 0
  fi
}
# Independent of the tool under test, deliberately: `castle` computes
# the stamp with hashlib and this reads it back with coreutils, so a
# bug in one cannot hide behind the same bug in the other.
sha256_of() { sha256sum "$1" | cut -d' ' -f1; }

drive_modal() {
  # Usage: drive_modal <transcript-path> <modal-arg>... -- <step>...
  local transcript="$1"; shift
  python3 "$PTY_DRIVE" "$MODAL" "$@" > "$transcript" || {
    cat "$transcript" >&2
    fail "pty driver failed (see the transcript above)"
  }
}
transcript_rc() { sed -n 's/^RC=//p' "$1"; }

# Both checkouts, every time, with no exclusions. This is the whole
# task's central negative claim given teeth: a decision is a decision
# and nothing else, so if any scenario below ever edits a file, moves a
# HEAD, or leaves so much as an untracked scratch file behind, this
# says so by name. Copied from config-target.sh rather than shared:
# these are plain bash harnesses with no library between them, and the
# duplication is the price of each being readable start to finish.
assert_checkouts_untouched() {
  local where="$1"
  [ -z "$(git -C "$PRIVATE" status --porcelain)" ] \
    || fail "$where: the private checkout was MUTATED — $(git -C "$PRIVATE" status --porcelain)"
  [ -z "$(git -C "$MECHANISM" status --porcelain)" ] \
    || fail "$where: the mechanism checkout was MUTATED — $(git -C "$MECHANISM" status --porcelain)"
  [ "$(git -C "$PRIVATE" rev-parse HEAD)" = "$PRIVATE_HEAD" ] \
    || fail "$where: the private checkout's HEAD moved"
  [ "$(git -C "$MECHANISM" rev-parse HEAD)" = "$MECHANISM_HEAD" ] \
    || fail "$where: the mechanism checkout's HEAD moved"
}

"$CASTLE" dispatch --watermark-only >/dev/null
"$CASTLE" validate >/dev/null

# ---------------------------------------------------------------------
log "a completed, targeted turn files exactly one change to decide"
# ---------------------------------------------------------------------
REQ1="$("$CASTLE" ask "APPROVAL-FIXTURE-ONE: an invented complaint whose fix is a one-line change.")"
log "  -> $REQ1"
"$CASTLE" dispatch >/dev/null
R1="$(newest_result_for "$REQ1")"
[ -n "$R1" ] || fail "the sweep wrote no result for $REQ1"
grep -q '^outcome: completed$' "$R1" || fail "$REQ1 did not complete"
grep -q '^target: private$' "$R1" || fail "$R1 carries no target, so no change would be proposed from it"
R1_ID="$(basename "$R1" .md)"

Q1="$(proposal_question_for "$REQ1")"
[ -n "$Q1" ] || fail "a completed, targeted turn filed no change for the resident to decide"
[ "$(grep -l '^proposal-sha256: ' "$JOURNAL"/*-question-*.md | grep -c .)" -eq 1 ] \
  || fail "one turn filed more than one change to decide"

log "  -- it is NOT blocking: approving it must never start another worker turn"
# The single sharpest failure available to this task. A blocking
# proposal question would resume the errand the moment it was
# answered, so approving a change would silently run the worker again
# and produce a second, unauthorized change — in a task whose entire
# promise is that it applies nothing. Asserted on the record, and then
# asserted again on behaviour after the approval below.
grep -q '^blocking:' "$JOURNAL/$Q1.md" \
  && fail "the proposal question is blocking — approving it would re-run the worker"

log "  -- it carries no fact: no rejection may write into the resident model"
grep -q '^fact:' "$JOURNAL/$Q1.md" \
  && fail "the proposal question elicits a fact — deciding it would write a stated preference"

log "  -- its refs are the errand and the exact result it is about"
grep -q "^refs: $REQ1,$R1_ID\$" "$JOURNAL/$Q1.md" \
  || fail "the proposal question's refs are not <request>,<result>: $(grep '^refs:' "$JOURNAL/$Q1.md")"
grep -q '^seat: worker$' "$JOURNAL/$Q1.md" || fail "the proposal question is not seat: worker"

log "  -- and its stamp is the SHA-256 of the result file's own bytes, computed independently"
STAMP="$(sed -n 's/^proposal-sha256: //p' "$JOURNAL/$Q1.md")"
[ "$STAMP" = "$(sha256_of "$R1")" ] \
  || fail "the stamped hash $STAMP is not sha256sum's $(sha256_of "$R1") of the result file"

log "  -- the notification a resident receives says what it is and that nothing was applied"
grep -q 'Nothing has been applied' "$CASTLE_NOTIFY_LOG" \
  || fail "no notification carried the proposal's own first line: $(cat "$CASTLE_NOTIFY_LOG")"
# "answer" names the wrong act on a proposed change, on the only push
# channel this system has and the one surface bound hardest by "no
# internal vocabulary" — the same defect `_show_picker`'s `action`
# parameter and `_errand_state`'s three-way verb already fix one screen
# over. The chord itself is unchanged and must stay unchanged:
# `Mod4+Shift+a` is a real binding in the `modules/home` keybindings
# attrset — CHORD COUPLING, same as the two in `agent/castle`.
grep -q 'Press Mod4+Shift+a to review' "$CASTLE_NOTIFY_LOG" \
  || fail "the proposal notification does not tell the resident how to reach it, in the right verb: $(cat "$CASTLE_NOTIFY_LOG")"
grep -q 'Press Mod4+Shift+a to answer' "$CASTLE_NOTIFY_LOG" \
  && fail "the proposal notification still tells the resident to ANSWER a change: $(cat "$CASTLE_NOTIFY_LOG")"

"$CASTLE" validate >/dev/null || fail "the journal does not validate after a proposal is filed"
assert_checkouts_untouched "after the first proposal was filed"

# ---------------------------------------------------------------------
log "an ordinary answer against it is refused — a proposal must not dead-end"
# ---------------------------------------------------------------------
# Without this, a script or a careless caller closes the change with
# plain prose: the already-answered guard then treats it as answered
# forever, with no decision recorded anywhere, and nothing can say
# whether it was approved, rejected or never looked at.
FILES_BEFORE="$(journal_file_count)"
if "$CASTLE" answer "$Q1" "Just some words, no decision." >/dev/null 2>"$WORKDIR/ordinary.err"; then
  fail "an ordinary answer closed a proposed change with no decision recorded"
fi
grep -q 'needs approve\|--decision' "$WORKDIR/ordinary.err" \
  || fail "the ordinary-answer refusal does not name the way to close it: $(cat "$WORKDIR/ordinary.err")"
[ "$(journal_file_count)" = "$FILES_BEFORE" ] || fail "the refused ordinary answer wrote a record anyway"

log "  -- and the same refusal reaches castle-modal's scripted path, pointing at review mode"
if printf 'Words.\n.\n' | "$MODAL" --mode answer --question "$Q1" >/dev/null 2>"$WORKDIR/ordinary-modal.err"; then
  fail "the modal's scripted answer path closed a proposed change"
fi
grep -q -- '--mode review' "$WORKDIR/ordinary-modal.err" \
  || fail "the modal's refusal does not point at review mode: $(cat "$WORKDIR/ordinary-modal.err")"
[ "$(journal_file_count)" = "$FILES_BEFORE" ] || fail "the modal's refusal wrote a record anyway"

# ---------------------------------------------------------------------
log "castle record refuses to write a decision at all"
# ---------------------------------------------------------------------
# Not a security boundary — a tenant running as the resident could
# write the file directly — but the difference between a decision made
# through the one path that verifies what it is deciding and one that
# does not.
if "$CASTLE" record --type answer --provenance requested --seat intake \
  --refs "$Q1,$R1_ID" --decision approve --body "Around the door." >/dev/null 2>"$WORKDIR/record.err"; then
  fail "castle record wrote a decision-bearing answer, bypassing every check that makes one mean anything"
fi
grep -q 'byte-hash and staleness' "$WORKDIR/record.err" \
  || fail "the castle record refusal does not say what it is protecting: $(cat "$WORKDIR/record.err")"
[ "$(journal_file_count)" = "$FILES_BEFORE" ] || fail "the refused castle record wrote a record anyway"

# ---------------------------------------------------------------------
log "approve: the decision is written, bound to the exact change, and applies nothing"
# ---------------------------------------------------------------------
MODEL_BEFORE="$(model_byte_count)"
A1="$("$CASTLE" answer --decision approve "$Q1" "Yes, that is the right shape.")"
[ -n "$A1" ] || fail "castle answer --decision approve printed no record id"
grep -q '^decision: approve$' "$JOURNAL/$A1.md" || fail "$A1 carries no 'decision: approve'"
grep -q "^refs: $Q1,$R1_ID\$" "$JOURNAL/$A1.md" \
  || fail "the decision's refs are not <question>,<result>: $(grep '^refs:' "$JOURNAL/$A1.md")"
grep -q "^proposal-sha256: $STAMP\$" "$JOURNAL/$A1.md" \
  || fail "the decision does not carry the hash it was bound to"
grep -q 'Yes, that is the right shape.' "$JOURNAL/$A1.md" \
  || fail "the resident's own comment was not stored verbatim"
[ "$(model_byte_count)" = "$MODEL_BEFORE" ] || fail "approving wrote into the resident model"
"$CASTLE" validate >/dev/null || fail "the journal does not validate after an approval"
assert_checkouts_untouched "after approving"

log "  -- and no sweep resumes the errand on the strength of that approval"
# The behavioural half of the non-blocking assertion above. Two full
# sweeps: if the proposal question were resumable, the answer would buy
# this errand another turn and a second result would appear.
BEFORE_RESULTS="$(count_referencing result "$REQ1")"
"$CASTLE" dispatch >/dev/null
"$CASTLE" dispatch >/dev/null
[ "$(count_referencing result "$REQ1")" -eq "$BEFORE_RESULTS" ] \
  || fail "approving a change started another worker turn — the proposal question is resumable after all"
assert_checkouts_untouched "after two sweeps following an approval"

log "  -- the control for the notification's verb: an ORDINARY question still says 'answer'"
# Without this, the "review" assertion above is satisfied by a change
# that says "review" on every question in the system, including the
# ones this task never touched. Filed here, after the last sweep of the
# run, and on an errand of its own: nothing else in this file asserts
# anything about it, and no dispatch follows to give it a worker turn
# and a change of its own.
REQ_ORDINARY="$("$CASTLE" ask "APPROVAL-FIXTURE-ORDINARY: an invented complaint whose question is an ordinary one.")"
ORDINARY_Q="$("$CASTLE" record --type question --provenance requested --seat worker \
  --refs "$REQ_ORDINARY" --body "APPROVAL-FIXTURE-ORDINARY-QUESTION: an invented ordinary question, not a change.")"
"$CASTLE" route >/dev/null
grep -q 'APPROVAL-FIXTURE-ORDINARY-QUESTION.*Press Mod4+Shift+a to answer' "$CASTLE_NOTIFY_LOG" \
  || fail "an ordinary question's notification no longer names answering: $(cat "$CASTLE_NOTIFY_LOG")"
"$CASTLE" answer "$ORDINARY_Q" "An invented reply." >/dev/null

log "  -- the status surface says approved, and says nothing was applied"
STATUS_APPROVED="$("$MODAL" --mode status --limit 40)"
printf '%s\n' "$STATUS_APPROVED" | grep -F "$REQ1" | grep -q 'approved — nothing applied yet' \
  || fail "an approved errand does not read as approved-but-unapplied: $(printf '%s\n' "$STATUS_APPROVED" | grep -F "$REQ1")"
printf '%s\n' "$STATUS_APPROVED" | grep -F "$REQ1" | grep -q 'waiting on you' \
  && fail "a decided change still reads as waiting on the resident"

log "  -- a second decision on the same change is refused"
if "$CASTLE" answer --decision reject "$Q1" </dev/null >/dev/null 2>"$WORKDIR/second.err"; then
  fail "a second decision was written on a change already decided"
fi
grep -q 'already answered' "$WORKDIR/second.err" \
  || fail "the second-decision refusal said something unexpected: $(cat "$WORKDIR/second.err")"

# ---------------------------------------------------------------------
log "reject and defer write the same shape with the other two values"
# ---------------------------------------------------------------------
decide_a_fresh_change() {
  # Usage: decide_a_fresh_change <marker> <decision>; echoes "<question-id> <answer-id>"
  local marker="$1" verdict="$2" request question answer
  request="$("$CASTLE" ask "APPROVAL-FIXTURE-$marker: another invented complaint with a one-line fix.")"
  "$CASTLE" work "$request" >/dev/null
  question="$(proposal_question_for "$request")"
  [ -n "$question" ] || fail "$marker: the turn filed no change to decide"
  answer="$("$CASTLE" answer --decision "$verdict" "$question" </dev/null)"
  printf '%s %s %s\n' "$request" "$question" "$answer"
}

MODEL_BEFORE="$(model_byte_count)"
read -r REQ_REJ Q_REJ A_REJ <<<"$(decide_a_fresh_change TWO reject)"
grep -q '^decision: reject$' "$JOURNAL/$A_REJ.md" || fail "the rejection carries no 'decision: reject'"
# The empty body is the point, not an oversight: a decision is a
# complete answer on its own, and demanding prose alongside it would
# train a resident to type "ok" before every approval — the exact
# click-through habituation Proposal 06 warns against.
[ -z "$(sed -n '/^---$/,$p' "$JOURNAL/$A_REJ.md" | sed '1,/^---$/d' | tr -d '[:space:]')" ] \
  || fail "the empty-bodied rejection stored something in its body"

read -r REQ_DEF Q_DEF A_DEF <<<"$(decide_a_fresh_change THREE defer)"
grep -q '^decision: defer$' "$JOURNAL/$A_DEF.md" || fail "the deferral carries no 'decision: defer'"

[ "$(model_byte_count)" = "$MODEL_BEFORE" ] \
  || fail "rejecting or deferring wrote into the resident model"
"$CASTLE" validate >/dev/null || fail "the journal does not validate after a rejection and a deferral"
assert_checkouts_untouched "after rejecting and deferring"

log "  -- and each reads as itself on the status surface, never as 'done'"
STATUS_DECIDED="$("$MODAL" --mode status --limit 40)"
printf '%s\n' "$STATUS_DECIDED" | grep -F "$REQ_REJ" | grep -q 'you declined this' \
  || fail "a rejected change reads as something else: $(printf '%s\n' "$STATUS_DECIDED" | grep -F "$REQ_REJ")"
printf '%s\n' "$STATUS_DECIDED" | grep -F "$REQ_DEF" | grep -q 'you set this aside' \
  || fail "a deferred change reads as something else: $(printf '%s\n' "$STATUS_DECIDED" | grep -F "$REQ_DEF")"

log "  -- and castle digest renders which decision it was, not a blank record"
# A decision answer's body is usually empty (defer never invites a
# comment, approve/reject only make one optional), so without a
# 'decision:' line the digest for the one record type that carries an
# authorization prints a bare '### answer <id> (seat: intake)' and
# nothing else — a resident reading a period's account cold cannot
# tell an approval from a rejection from a deferral.
DIGEST_DECIDED="$("$CASTLE" digest)"
errand_section() {
  # Everything from "## Errand <id>" up to (not including) the next
  # "## " heading. Second arg selects which digest output to read;
  # defaults to $DIGEST_DECIDED for the callers above that never pass
  # one.
  local digest="${2:-$DIGEST_DECIDED}"
  awk -v id="$1" '
    $0 == "## Errand " id { found=1; print; next }
    found && /^## / { exit }
    found { print }
  ' <<<"$digest"
}
printf '%s\n' "$(errand_section "$REQ1")" | grep -q '^- decision: approve$' \
  || fail "the digest does not render 'decision: approve' for the approved change: $(errand_section "$REQ1")"
printf '%s\n' "$(errand_section "$REQ_REJ")" | grep -q '^- decision: reject$' \
  || fail "the digest does not render 'decision: reject' for the rejected change: $(errand_section "$REQ_REJ")"
printf '%s\n' "$(errand_section "$REQ_DEF")" | grep -q '^- decision: defer$' \
  || fail "the digest does not render 'decision: defer' for the deferred change: $(errand_section "$REQ_DEF")"

# ---------------------------------------------------------------------
log "and a resumed tenant's packet says which decision it was, and who asked"
# ---------------------------------------------------------------------
# The same defect as the digest one above, one surface further in and
# with far more at stake. `render_continuation_packet` rendered an
# answer as `section(label, answer.body)`, and a decision answer's body
# is normally empty by design — so a tenant on any later turn of a
# decided errand was handed a blank section labelled "the resident's
# answer to that question, verbatim", directly under a question asking
# the resident to approve, reject or set aside. Readable as assent, or
# as no answer at all, on the authority path.
#
# And the question's own label said "a question this errand raised",
# which is false for a proposal: the harness raised it
# (`_file_proposal_question`), not the errand's tenant. That function
# refuses to let machine-authored text be presented as the resident
# speaking everywhere else, and this was the one place it did.
#
# Asserted against the real packet bytes a real tenant really receives
# — a fixture that dumps its whole stdin — rather than against the
# renderer's source, which is what makes it a claim about what a model
# reads.
PACKET_TENANT="$WORKDIR/packet-tenant.sh"
cat > "$PACKET_TENANT" <<'TENANT'
#!/usr/bin/env bash
set -euo pipefail
cat > "$CASTLE_PACKET_DUMP"
printf 'packet tenant: wrote the packet it was handed out to disk\n'
TENANT
chmod +x "$PACKET_TENANT"
# A further turn on an already-decided errand, which is exactly how a
# decision reaches a tenant: the packet is rendered on every turn, and a
# proposal question is never blocking, so nothing about this resumes on
# the strength of the approval (asserted separately above).
packet_for() {
  local request="$1" dump="$WORKDIR/packet-$2.txt"
  CASTLE_WORKER_COMMAND="$PACKET_TENANT" CASTLE_PACKET_DUMP="$dump" \
    "$CASTLE" work "$request" >/dev/null
  cat "$dump"
}
# The section between a named BEGIN boundary and the END that follows
# it, found by this packet's own nonce — the same rule the packet's
# preamble tells a tenant to read it by, so this harness cannot be
# fooled by a body that spells a boundary either.
packet_section() {
  local packet="$1" needle="$2" nonce
  nonce="$(printf '%s\n' "$packet" | sed -n 's/^\(CASTLE-PACKET-[0-9a-f]*\) BEGIN .*/\1/p' | head -1)"
  [ -n "$nonce" ] || fail "the packet carries no boundary nonce at all"
  printf '%s\n' "$packet" | awk -v n="$nonce" -v needle="$needle" '
    index($0, n " BEGIN") == 1 && index($0, needle) > 0 { found = 1; next }
    found && $0 == n " END" { exit }
    found { print }
  '
}
packet_label() {
  printf '%s\n' "$1" | grep -F "BEGIN" | grep -F "$2" | head -1
}

PACKET_APPROVE="$(packet_for "$REQ1" approve)"
PACKET_REJECT="$(packet_for "$REQ_REJ" reject)"
PACKET_DEFER="$(packet_for "$REQ_DEF" defer)"

log "  -- each verdict is stated on the boundary line, where no record body can reach"
printf '%s\n' "$PACKET_APPROVE" | grep -q "BEGIN the resident's decision on that proposed change: APPROVED" \
  || fail "an approved proposal is not stated as APPROVED in the packet: $(packet_label "$PACKET_APPROVE" 'decision on that proposed change')"
printf '%s\n' "$PACKET_REJECT" | grep -q "BEGIN the resident's decision on that proposed change: REJECTED" \
  || fail "a rejected proposal is not stated as REJECTED in the packet: $(packet_label "$PACKET_REJECT" 'decision on that proposed change')"
printf '%s\n' "$PACKET_DEFER" | grep -q "BEGIN the resident's decision on that proposed change: SET ASIDE" \
  || fail "a deferred proposal is not stated as SET ASIDE in the packet: $(packet_label "$PACKET_DEFER" 'decision on that proposed change')"

log "  -- an approval does not read as an application: the packet says nothing was applied"
printf '%s\n' "$PACKET_APPROVE" | grep -q 'nothing has been applied on the strength of that authorization' \
  || fail "the packet lets APPROVED read as already applied: $(packet_label "$PACKET_APPROVE" 'decision on that proposed change')"

log "  -- the two decisions whose bodies are empty still say what they were"
# The whole point. Without a verdict on the boundary line these two
# sections are blank, and a model reading only the packet has nothing
# at all to distinguish a rejection from a deferral from silence.
[ -z "$(packet_section "$PACKET_REJECT" 'decision on that proposed change' | tr -d '[:space:]')" ] \
  || fail "the rejection fixture typed a comment, so the empty-body case is not being tested"
[ -z "$(packet_section "$PACKET_DEFER" 'decision on that proposed change' | tr -d '[:space:]')" ] \
  || fail "the deferral fixture typed a comment, so the empty-body case is not being tested"

log "  -- and a comment the resident DID type is still there, verbatim, as their words"
packet_section "$PACKET_APPROVE" 'decision on that proposed change' \
  | grep -q 'Yes, that is the right shape.' \
  || fail "the resident's own comment is missing from the packet's decision section"

log "  -- the proposal question is not presented as something the errand's tenant asked"
for PACKET_NAME in APPROVE REJECT DEFER; do
  PACKET_VAR="PACKET_$PACKET_NAME"
  PACKET="${!PACKET_VAR}"
  printf '%s\n' "$PACKET" | grep -q 'BEGIN a proposed change this system filed for the resident to decide' \
    || fail "the $PACKET_NAME packet does not label the proposal as machine-authored: $(printf '%s\n' "$PACKET" | grep -F 'BEGIN' || true)"
  printf '%s\n' "$PACKET" | grep -q 'BEGIN a question this errand raised' \
    && fail "the $PACKET_NAME packet still attributes a harness-written proposal question to the errand"
  # The invariant the label's parenthetical carries, unchanged: the
  # packet never describes a question differently from how resumption
  # treated it, and a proposal question is never blocking.
  printf '%s\n' "$PACKET" | grep -q 'the resident to decide — machine-authored by the harness, not the errand.s tenant speaking (not blocking, answered below)' \
    || fail "the $PACKET_NAME packet lost the blocking/answered parenthetical: $(printf '%s\n' "$PACKET" | grep -F 'BEGIN' || true)"
done
"$CASTLE" validate >/dev/null || fail "the journal does not validate after the packet turns"
assert_checkouts_untouched "after the packet-rendering turns"

# ---------------------------------------------------------------------
log "stale: a change altered since it was proposed is refused, not guessed at"
# ---------------------------------------------------------------------
REQ_STALE="$("$CASTLE" ask "APPROVAL-FIXTURE-STALE: an invented complaint whose result will be tampered with.")"
"$CASTLE" work "$REQ_STALE" >/dev/null
Q_STALE="$(proposal_question_for "$REQ_STALE")"
R_STALE="$(newest_result_for "$REQ_STALE")"
[ -n "$Q_STALE" ] || fail "the stale-case turn filed no change to decide"
# One byte, appended, over a copy kept so the exact original can come
# back. Nothing in this system rewrites a record, so a result whose
# bytes moved was hand-edited or corrupted, and there is no version for
# a decision to prefer.
cp "$R_STALE" "$WORKDIR/stale-original"
printf ' ' >> "$R_STALE"
FILES_BEFORE="$(journal_file_count)"
if "$CASTLE" answer --decision approve "$Q_STALE" </dev/null >/dev/null 2>"$WORKDIR/stale.err"; then
  fail "a change altered on disk since it was proposed was approved anyway"
fi
grep -q 'has changed on disk' "$WORKDIR/stale.err" \
  || fail "the stale refusal does not say what is wrong: $(cat "$WORKDIR/stale.err")"
[ "$(journal_file_count)" = "$FILES_BEFORE" ] || fail "the stale refusal wrote a record anyway"
[ -z "$(answers_naming "$Q_STALE")" ] || fail "the stale refusal left an answer behind"
assert_checkouts_untouched "after the stale refusal"

log "  -- and restoring the exact bytes makes it decidable again: the check is about the bytes"
# The control. Without it the refusal above is satisfied by a check
# that simply never lets anything through once it has been near a file.
cp "$WORKDIR/stale-original" "$R_STALE"
"$CASTLE" answer --decision reject "$Q_STALE" </dev/null >/dev/null \
  || fail "a change whose bytes are exactly what was proposed is still refused"

# ---------------------------------------------------------------------
log "a hand-planted proposal that also elicits a fact is refused"
# ---------------------------------------------------------------------
# The harness never writes one — but a hand-written record, a restore,
# or a future bug could, and deciding it would launder an approval into
# a durable stated preference the resident never stated. Planted by
# hand precisely because no supported writer can produce it.
REQ_FACT="$("$CASTLE" ask "APPROVAL-FIXTURE-FACT: an invented complaint behind a hand-planted proposal.")"
"$CASTLE" work "$REQ_FACT" >/dev/null
R_FACT="$(basename "$(newest_result_for "$REQ_FACT")" .md)"
Q_FACT_ID="20260201T000900Z-question-planted"
{
  echo "---"
  echo "id: $Q_FACT_ID"
  echo "type: question"
  echo "provenance: requested"
  echo "refs: $REQ_FACT,$R_FACT"
  echo "seat: worker"
  echo "created: 2026-02-01T00:09:00Z"
  echo "fact: invented-preference-key"
  echo "proposal-sha256: $(sha256_of "$JOURNAL/$R_FACT.md")"
  echo "---"
  echo
  echo "A hand-planted change that also tries to elicit something about the resident."
} > "$JOURNAL/$Q_FACT_ID.md"
FILES_BEFORE="$(journal_file_count)"
MODEL_BEFORE="$(model_byte_count)"
if "$CASTLE" answer --decision approve "$Q_FACT_ID" </dev/null >/dev/null 2>"$WORKDIR/fact.err"; then
  fail "a proposal that also elicits a fact was decided, writing a preference the resident never stated"
fi
grep -q 'resident model' "$WORKDIR/fact.err" \
  || fail "the fact-carrying refusal does not say what it prevented: $(cat "$WORKDIR/fact.err")"
[ "$(journal_file_count)" = "$FILES_BEFORE" ] || fail "the fact-carrying refusal wrote a record anyway"
[ "$(model_byte_count)" = "$MODEL_BEFORE" ] || fail "the fact-carrying refusal wrote into the resident model"

log "  -- and so is --fact supplied on the command line beside a decision"
# The other half of the same door, and the likelier one: the question's
# own field is not the only way a fact reaches the write path. This is
# the guard the implementation deviated from the brief to write (§C
# guard 3 checks the question's field alone, which `castle answer
# --fact NAME --decision approve` walks straight past), so it is the
# one that most needs a test that can fail.
#
# A FRESH, UNDECIDED change, and the exact refusal asserted by name.
# This case used to target an already-decided question, so
# `file_answer`'s already-answered scan refused it before the proposal
# half ever ran — and the assertions, a non-zero exit and an unchanged
# resident-model byte count, were both satisfied by the wrong refusal.
# The guard had no coverage at all.
REQ_FACT_FLAG="$("$CASTLE" ask "APPROVAL-FIXTURE-FACT-FLAG: an invented complaint decided with a fact name pushed in from the command line.")"
"$CASTLE" work "$REQ_FACT_FLAG" >/dev/null
Q_FACT_FLAG="$(proposal_question_for "$REQ_FACT_FLAG")"
[ -n "$Q_FACT_FLAG" ] || fail "the --fact-flag case's turn filed no change to decide"
[ -z "$(answers_naming "$Q_FACT_FLAG")" ] \
  || fail "the --fact-flag case's change is already decided, so this proves nothing about the guard"
grep -q '^fact:' "$JOURNAL/$Q_FACT_FLAG.md" \
  && fail "the --fact-flag case's question carries its own fact, so the flag is not what is being tested"
FILES_BEFORE="$(journal_file_count)"
if "$CASTLE" answer --decision approve --fact "invented-preference-key" "$Q_FACT_FLAG" \
  </dev/null >/dev/null 2>"$WORKDIR/fact-flag.err"; then
  fail "--fact beside --decision wrote a resident-model entry as a side effect of a decision"
fi
grep -q "it is a proposal and it also elicits a 'fact', so deciding it would write into the resident model" \
  "$WORKDIR/fact-flag.err" \
  || fail "--fact beside --decision was refused by something other than the fact guard: $(cat "$WORKDIR/fact-flag.err")"
grep -q 'already answered' "$WORKDIR/fact-flag.err" \
  && fail "the --fact-flag case is being refused as already answered, which tests the wrong guard"
[ "$(model_byte_count)" = "$MODEL_BEFORE" ] || fail "--fact beside --decision wrote into the resident model"
[ "$(journal_file_count)" = "$FILES_BEFORE" ] || fail "the --fact-flag refusal wrote a record anyway"
[ -z "$(answers_naming "$Q_FACT_FLAG")" ] || fail "the --fact-flag refusal closed the change anyway"

log "  -- and the control: the same change, decided with no --fact, goes through"
# Without this the refusal above is satisfied by a guard that simply
# never lets a decision through once a fact name has been near it.
"$CASTLE" answer --decision approve "$Q_FACT_FLAG" </dev/null >/dev/null \
  || fail "the same change is refused even with no --fact, so the guard is refusing the wrong thing"
[ "$(model_byte_count)" = "$MODEL_BEFORE" ] || fail "an ordinary approval wrote into the resident model"

# `castle validate` is asked separately here: the planted record is
# exactly what the validator's own permanent gate must catch.
if "$CASTLE" validate >/dev/null 2>"$WORKDIR/validate-fact.err"; then
  fail "castle validate accepted a question carrying both a proposal stamp and a fact"
fi
grep -q "carries 'fact'" "$WORKDIR/validate-fact.err" \
  || fail "the validator does not name the fact-carrying proposal: $(cat "$WORKDIR/validate-fact.err")"
rm -f "$JOURNAL/$Q_FACT_ID.md"
"$CASTLE" validate >/dev/null || fail "the journal does not validate once the planted record is removed"

# ---------------------------------------------------------------------
log "a diff full of markdown fences survives the round trip whole"
# ---------------------------------------------------------------------
# The writer half of the boundary this task's code review found missing
# (finding 1). The rendering half is asserted in
# modal-headless-test.sh against a planted body; this proves the real
# `castle work` path stamps a boundary and wraps the real tenant's
# real diff in it, for the diff shape that broke the old fence scan: a
# change to a file that itself contains a fenced code block, whose
# context lines strip to exactly the fences a scanner looks for.
FENCED_TENANT="$WORKDIR/fenced-tenant.sh"
cat > "$FENCED_TENANT" <<'TENANT'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
printf 'fenced tenant: this change touches a file containing a code fence\n'
cat > "$CASTLE_DIFF_FILE" <<'DIFF'
--- a/README.md
+++ b/README.md
@@ -1,7 +1,7 @@
 Prose above a fenced block.
 
 ```diff
-FENCED-BEFORE-INSIDE
+FENCED-AFTER-INSIDE
 ```
 
-FENCED-BEFORE-AFTER
+FENCED-AFTER-AFTER
DIFF
printf 'private\n' > "$CASTLE_TARGET_FILE"
TENANT
chmod +x "$FENCED_TENANT"
REQ_FENCED="$("$CASTLE" ask "APPROVAL-FIXTURE-FENCED: an invented complaint about a file that contains a code fence.")"
CASTLE_WORKER_COMMAND="$FENCED_TENANT" "$CASTLE" work "$REQ_FENCED" >/dev/null
R_FENCED="$(newest_result_for "$REQ_FENCED")"
grep -q '^outcome: completed$' "$R_FENCED" || fail "the fenced-diff turn did not complete"

log "  -- the result stamps a boundary, and it is sixteen hex characters of it"
BOUNDARY="$(sed -n 's/^diff-boundary: //p' "$R_FENCED")"
[ -n "$BOUNDARY" ] || fail "a turn that embedded a diff stamped no boundary"
printf '%s' "$BOUNDARY" | grep -qE '^[0-9a-f]{16}$' \
  || fail "the stamped boundary is not sixteen lowercase hex characters: $BOUNDARY"

log "  -- the boundary lines wrap the whole diff, and the diff's own fences are inside them"
grep -qF "CASTLE-DIFF-$BOUNDARY BEGIN" "$R_FENCED" || fail "no BEGIN boundary in the result body"
grep -qF "CASTLE-DIFF-$BOUNDARY END" "$R_FENCED" || fail "no END boundary in the result body"
# Everything the tenant wrote, still there and still between the two
# boundary lines. `sed` between the markers is the same slice the modal
# takes, done by a different tool.
INSIDE="$(sed -n "/^CASTLE-DIFF-$BOUNDARY BEGIN\$/,/^CASTLE-DIFF-$BOUNDARY END\$/p" "$R_FENCED")"
for NEEDLE in FENCED-BEFORE-INSIDE FENCED-AFTER-INSIDE FENCED-BEFORE-AFTER FENCED-AFTER-AFTER; do
  printf '%s\n' "$INSIDE" | grep -q -- "$NEEDLE" \
    || fail "$NEEDLE is not inside the boundary — the diff was split by its own fences"
done
# And the boundary is not something the diff could have produced: the
# nonce is made after the tenant exits, so it appears nowhere in what
# the tenant wrote.
grep -qF "$BOUNDARY" "$WORKDIR/fenced-tenant.sh" \
  && fail "the fixture tenant contains the boundary — this run proves nothing about forgeability"
"$CASTLE" validate >/dev/null || fail "the journal does not validate after a fenced diff"
assert_checkouts_untouched "after the fenced-diff turn"

log "  -- castle digest strips the nonce boundary lines but keeps the deliberate diff fence"
# Review mode strips CASTLE-DIFF-<nonce> BEGIN/END before showing a
# resident anything (_split_proposal_body); the digest printed
# rec.body.strip() verbatim instead, so a resident's digest carried a
# bare sixteen-hex-character token twice per proposal.
DIGEST_FENCED="$("$CASTLE" digest)"
FENCED_SECTION="$(errand_section "$REQ_FENCED" "$DIGEST_FENCED")"
printf '%s\n' "$FENCED_SECTION" | grep -qF "CASTLE-DIFF-$BOUNDARY BEGIN" \
  && fail "the digest leaked the diff's nonce BEGIN line: $FENCED_SECTION"
printf '%s\n' "$FENCED_SECTION" | grep -qF "CASTLE-DIFF-$BOUNDARY END" \
  && fail "the digest leaked the diff's nonce END line: $FENCED_SECTION"
printf '%s\n' "$FENCED_SECTION" | grep -qF '```diff' \
  || fail "the digest dropped the deliberate diff fence along with the boundary: $FENCED_SECTION"
for NEEDLE in FENCED-BEFORE-INSIDE FENCED-AFTER-INSIDE FENCED-BEFORE-AFTER FENCED-AFTER-AFTER; do
  printf '%s\n' "$FENCED_SECTION" | grep -q -- "$NEEDLE" \
    || fail "$NEEDLE is missing from the digest — stripping the boundary must not touch the diff itself"
done

# ---------------------------------------------------------------------
log "a change proposed against the MECHANISM checkout is decided the same way"
# ---------------------------------------------------------------------
# Every scenario above proposes against the private layer, so the whole
# `target: mechanism` route — the one that would edit this framework
# itself — was uncovered. It is also the half of
# `assert_checkouts_untouched` that could not fail until
# CASTLE_MECHANISM_ROOT was exported: now `castle` knows the path, a
# tenant is handed it, a change is proposed against it, and the
# assertion that nothing moved is a claim about a checkout the code
# under test can actually reach.
MECHANISM_TENANT="$WORKDIR/mechanism-tenant.sh"
cat > "$MECHANISM_TENANT" <<'TENANT'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
# Asserted, not assumed: a tenant that tolerated a missing mechanism
# root would let this whole scenario pass while proving nothing.
: "${CASTLE_MECHANISM_ROOT:?mechanism-tenant.sh: CASTLE_MECHANISM_ROOT must be set}"
printf 'mechanism tenant: this one belongs in the framework checkout, not the private layer\n'
cat > "$CASTLE_DIFF_FILE" <<'DIFF'
--- a/modules/example (synthetic, harness fixture only)
+++ b/modules/example (synthetic, harness fixture only)
@@ -1 +1 @@
-MECHANISM-PLACEHOLDER-BEFORE
+MECHANISM-PLACEHOLDER-AFTER
DIFF
printf 'mechanism\n' > "$CASTLE_TARGET_FILE"
TENANT
chmod +x "$MECHANISM_TENANT"
REQ_MECH="$("$CASTLE" ask "APPROVAL-FIXTURE-MECHANISM: an invented complaint whose fix belongs in the framework, not the private layer.")"
CASTLE_WORKER_COMMAND="$MECHANISM_TENANT" "$CASTLE" work "$REQ_MECH" >/dev/null
R_MECH="$(newest_result_for "$REQ_MECH")"
grep -q '^outcome: completed$' "$R_MECH" || fail "the mechanism-target turn did not complete"
grep -q '^target: mechanism$' "$R_MECH" \
  || fail "the mechanism-target turn did not stamp target: mechanism: $(grep '^target:' "$R_MECH" || true)"
# The proof that the export is real rather than decorative: the resolved
# path in the body is the fixture checkout this harness built.
grep -qF "This diff targets the **mechanism** checkout, which on this host resolved to \`$MECHANISM\`." "$R_MECH" \
  || fail "the result does not name the resolved mechanism path — castle never learned it"
Q_MECH="$(proposal_question_for "$REQ_MECH")"
[ -n "$Q_MECH" ] || fail "a completed turn targeting the mechanism checkout filed no change to decide"
A_MECH="$("$CASTLE" answer --decision approve "$Q_MECH" </dev/null)"
grep -q '^decision: approve$' "$JOURNAL/$A_MECH.md" \
  || fail "approving a mechanism-targeted change did not record an approval"
"$CASTLE" validate >/dev/null || fail "the journal does not validate after a mechanism-targeted decision"
# The whole point of the section, and of the fixture the export makes
# meaningful: approving a change against this framework's own checkout
# still applies nothing to it.
assert_checkouts_untouched "after approving a change targeting the mechanism checkout"

# ---------------------------------------------------------------------
log "castle record refuses an --outcome it would then fail to validate"
# ---------------------------------------------------------------------
# The writer half of the type scoping this task gave the validator. Both
# ends were lax before; closing only the validator would have left the
# door laxer than the backstop, in an append-only journal where the
# record `castle record` wrote could never be withdrawn.
if "$CASTLE" record --type answer --provenance requested --seat intake \
  --refs "$Q1" --outcome completed --body "placeholder" >/dev/null 2>"$WORKDIR/outcome.err"; then
  fail "castle record wrote --outcome on an answer record, which castle validate then rejects"
fi
grep -q 'only meaningful on a result record' "$WORKDIR/outcome.err" \
  || fail "the --outcome refusal says something unexpected: $(cat "$WORKDIR/outcome.err")"
# The control: on a result it is still accepted, so the guard refuses a
# type rather than the flag.
OUTCOME_OK="$("$CASTLE" record --type result --provenance requested --seat worker \
  --refs "$REQ1" --outcome failed --body "An invented hand-written result.")"
grep -q '^outcome: failed$' "$JOURNAL/$OUTCOME_OK.md" \
  || fail "the --outcome guard now refuses a perfectly good result record"
"$CASTLE" validate >/dev/null || fail "the journal does not validate after the --outcome cases"

# ---------------------------------------------------------------------
log "a follow-up errand's verdict never relabels the errand it was filed against"
# ---------------------------------------------------------------------
# `_collect_downstream` is transitive over refs, so a follow-up filed
# with `castle ask --refs R1` drags its own change into R1's fold.
# Without keying the decision overlay to the request the way its
# neighbours are keyed, rejecting the FOLLOW-UP's change printed
# "[R1] requested — you declined this" about an errand the resident
# declined nothing on.
NO_PROPOSAL_TENANT="$WORKDIR/no-proposal-tenant.sh"
cat > "$NO_PROPOSAL_TENANT" <<'TENANT'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
printf 'no-proposal tenant: nothing here needed changing\n'
TENANT
chmod +x "$NO_PROPOSAL_TENANT"
REQ_PARENT="$("$CASTLE" ask "APPROVAL-FIXTURE-PARENT: an invented complaint whose turn proposes nothing.")"
CASTLE_WORKER_COMMAND="$NO_PROPOSAL_TENANT" "$CASTLE" work "$REQ_PARENT" >/dev/null
[ -z "$(proposal_question_for "$REQ_PARENT")" ] \
  || fail "the parent errand proposed something, so this case proves nothing"
REQ_CHILD="$("$CASTLE" ask --refs "$REQ_PARENT" "APPROVAL-FIXTURE-CHILD: an invented follow-up whose turn does propose something.")"
"$CASTLE" work "$REQ_CHILD" >/dev/null
Q_CHILD="$(proposal_question_for "$REQ_CHILD")"
[ -n "$Q_CHILD" ] || fail "the follow-up errand proposed nothing"
"$CASTLE" answer --decision reject "$Q_CHILD" </dev/null >/dev/null
STATUS_FOLLOWUP="$("$MODAL" --mode status --limit 40)"
printf '%s\n' "$STATUS_FOLLOWUP" | grep -F "$REQ_CHILD" | grep -q 'you declined this' \
  || fail "the follow-up errand does not carry its own verdict: $(printf '%s\n' "$STATUS_FOLLOWUP" | grep -F "$REQ_CHILD")"
printf '%s\n' "$STATUS_FOLLOWUP" | grep -F "$REQ_PARENT" | grep -q 'you declined this' \
  && fail "a verdict on the follow-up's change relabelled the errand it was filed against"
printf '%s\n' "$STATUS_FOLLOWUP" | grep -F "$REQ_PARENT" | grep -q 'done' \
  || fail "the parent errand lost its own state: $(printf '%s\n' "$STATUS_FOLLOWUP" | grep -F "$REQ_PARENT")"
"$CASTLE" validate >/dev/null || fail "the journal does not validate after the follow-up case"

# ---------------------------------------------------------------------
log "a verdict never masks a newer turn, or the retry command that turn needs"
# ---------------------------------------------------------------------
# This block's own rule is that an errand's state is the state of its
# newest turn. An unconditional override broke it: approve, run another
# turn by hand, have it fail, and the surface went on reading
# "approved — nothing applied yet" while the failure and its
# `castle work <id> to retry` remedy vanished.
REQ_RETRY="$("$CASTLE" ask "APPROVAL-FIXTURE-RETRY: an invented complaint whose second turn fails after a decision.")"
"$CASTLE" work "$REQ_RETRY" >/dev/null
Q_RETRY="$(proposal_question_for "$REQ_RETRY")"
[ -n "$Q_RETRY" ] || fail "the retry-case turn proposed nothing"
"$CASTLE" answer --decision approve "$Q_RETRY" </dev/null >/dev/null
STATUS_APPROVED_ONLY="$("$MODAL" --mode status --limit 40)"
printf '%s\n' "$STATUS_APPROVED_ONLY" | grep -F "$REQ_RETRY" | grep -q 'approved — nothing applied yet' \
  || fail "the approved errand does not read as approved before its retry"
FAILING_TENANT="$WORKDIR/failing-tenant.sh"
cat > "$FAILING_TENANT" <<'TENANT'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
printf 'failing tenant: this turn does not finish\n' >&2
exit 3
TENANT
chmod +x "$FAILING_TENANT"
# A whole second, because record ids are chronological only to one, and
# the overlay's tie-break deliberately favours the DECISION: a decision
# and the result it is about routinely share a second (a scripted
# caller always does; a resident approving straight off a notification
# can), and there the decision really is the later event. A decision
# and a turn run afterwards sharing a second is coincidence, not
# structure, and is not worth inverting the rule for — so the harness
# separates them the way a human's hands would.
sleep 1
CASTLE_WORKER_COMMAND="$FAILING_TENANT" "$CASTLE" work "$REQ_RETRY" >/dev/null 2>&1 || true
STATUS_AFTER_FAIL="$("$MODAL" --mode status --limit 40)"
printf '%s\n' "$STATUS_AFTER_FAIL" | grep -F "$REQ_RETRY" | grep -q "failed — castle work $REQ_RETRY to retry" \
  || fail "a newer failed turn is masked by an older verdict: $(printf '%s\n' "$STATUS_AFTER_FAIL" | grep -F "$REQ_RETRY")"
printf '%s\n' "$STATUS_AFTER_FAIL" | grep -F "$REQ_RETRY" | grep -q 'approved — nothing applied yet' \
  && fail "the surface still reports a verdict older than the errand's newest turn"
"$CASTLE" validate >/dev/null || fail "the journal does not validate after the retry case"
assert_checkouts_untouched "after the overlay-keying cases"

# ---------------------------------------------------------------------
log "review mode on a pty: dismissal writes nothing, and the change stays waiting"
# ---------------------------------------------------------------------
clear_pending_proposals
REQ_DISMISS="$("$CASTLE" ask "APPROVAL-FIXTURE-DISMISS: an invented complaint the resident will look at and leave.")"
"$CASTLE" work "$REQ_DISMISS" >/dev/null
Q_DISMISS="$(proposal_question_for "$REQ_DISMISS")"
[ -n "$Q_DISMISS" ] || fail "the dismissal-case turn filed no change to decide"
FILES_BEFORE="$(journal_file_count)"
MODEL_BEFORE="$(model_byte_count)"
drive_modal "$WORKDIR/review-dismiss.txt" --mode review --question "$Q_DISMISS" -- \
  "wait:any other key closes this" "key:x"
[ "$(transcript_rc "$WORKDIR/review-dismiss.txt")" = "0" ] \
  || fail "dismissing a review did not exit 0 — looking and declining to decide is a successful use of this surface"
[ "$(journal_file_count)" = "$FILES_BEFORE" ] || fail "dismissing a review wrote a journal record"
[ "$(model_byte_count)" = "$MODEL_BEFORE" ] || fail "dismissing a review wrote into the resident model"
[ -z "$(answers_naming "$Q_DISMISS")" ] || fail "dismissing a review closed the change anyway"
assert_checkouts_untouched "after a dismissal"

log "  -- bare Enter dismisses too: no key a resident reaches for by reflex decides anything"
drive_modal "$WORKDIR/review-enter.txt" --mode review --question "$Q_DISMISS" -- \
  "wait:any other key closes this" "key:\n"
[ "$(transcript_rc "$WORKDIR/review-enter.txt")" = "0" ] || fail "bare Enter on a review did not exit 0"
[ "$(journal_file_count)" = "$FILES_BEFORE" ] || fail "bare Enter on a review wrote a record"

# ---------------------------------------------------------------------
log "altered mid-review: the write re-derives from disk, not from what it displayed"
# ---------------------------------------------------------------------
# The restart-between-display-and-response case, in its reachable
# shape: the change is rendered, the file moves underneath it, and only
# then does the keypress land. There is no state held between the two —
# both ends re-read the same bytes — so this is refused for exactly the
# same reason the stale case above is, and proving that is the point.
R_DISMISS="$(newest_result_for "$REQ_DISMISS")"
cp "$R_DISMISS" "$WORKDIR/dismiss-original"
FILES_BEFORE="$(journal_file_count)"
drive_modal "$WORKDIR/review-altered.txt" --mode review --question "$Q_DISMISS" -- \
  "wait:any other key closes this" "run:printf ' ' >> '$R_DISMISS'" "key:a" \
  "wait:End with a line containing just" "send:.\n" "wait:Nothing filed" "send:\n"
[ "$(transcript_rc "$WORKDIR/review-altered.txt")" = "1" ] \
  || fail "approving a change altered between display and keypress did not fail: $(cat "$WORKDIR/review-altered.txt")"
grep -q 'not what it was when it was proposed' "$WORKDIR/review-altered.txt" \
  || fail "the mid-review refusal does not say the change moved: $(cat "$WORKDIR/review-altered.txt")"
[ "$(journal_file_count)" = "$FILES_BEFORE" ] || fail "the mid-review refusal wrote a record anyway"
[ -z "$(answers_naming "$Q_DISMISS")" ] || fail "the mid-review refusal wrote a decision anyway"
assert_checkouts_untouched "after the mid-review refusal"
# Put the bytes back, so the change this scenario tampered with is
# decidable again and the next scenario starts from a fold it controls.
cp "$WORKDIR/dismiss-original" "$R_DISMISS"

# ---------------------------------------------------------------------
log "review mode on a pty: approve, with the optional comment actually typed"
# ---------------------------------------------------------------------
clear_pending_proposals
REQ_PTY="$("$CASTLE" ask "APPROVAL-FIXTURE-PTY: an invented complaint decided through the window.")"
"$CASTLE" work "$REQ_PTY" >/dev/null
Q_PTY="$(proposal_question_for "$REQ_PTY")"
R_PTY="$(basename "$(newest_result_for "$REQ_PTY")" .md)"
drive_modal "$WORKDIR/review-approve.txt" --mode review --question "$Q_PTY" -- \
  "wait:any other key closes this" "key:a" "wait:End with a line containing just" \
  "send:Fine by me.\n.\n" "wait:Press Enter to close" "send:\n"
REVIEW_OUT="$(cat "$WORKDIR/review-approve.txt")"
[ "$(transcript_rc "$WORKDIR/review-approve.txt")" = "0" ] || fail "approving through the window did not exit 0"
printf '%s\n' "$REVIEW_OUT" | tr -d '\r' | grep -qx 'Approved.' \
  || fail "the confirmation is not a bare 'Approved.': $REVIEW_OUT"
# The boundary statement's own account of what "setting it aside" does
# must not promise a way back to it — defer is as terminal as reject,
# and this text used to say the opposite outright ("Setting it aside
# leaves it exactly as it is... if you never come back to it"), drawing
# the contrast against "Rejecting ends this one" that made the promise
# explicit. Three independent reviewers found it and the task's own
# verification did not, which is why the assertion is here rather than
# left to reading.
#
# Both halves are asserted, because each fixes a different defect. That
# setting aside is final is the correction itself. That the two words
# still mean different things — reject is a verdict, setting aside is a
# refusal to reach one — is what keeps a third option from collapsing
# into a synonym for the second now that both are terminal.
printf '%s\n' "$REVIEW_OUT" | grep -q 'Both close it for good' \
  || fail "the boundary statement no longer says setting a change aside also ends it: $REVIEW_OUT"
printf '%s\n' "$REVIEW_OUT" | grep -q 'Setting it aside says you are not' \
  || fail "the boundary statement no longer distinguishes setting aside from rejecting: $REVIEW_OUT"
printf '%s\n' "$REVIEW_OUT" | grep -qi 'come back' \
  && fail "the boundary statement still promises a way back to a deferred change: $REVIEW_OUT"
A_PTY="$(basename "$(answers_naming "$Q_PTY" | head -1)" .md)"
[ -n "$A_PTY" ] || fail "approving through the window wrote no decision"
grep -q '^decision: approve$' "$JOURNAL/$A_PTY.md" || fail "the window's decision is not an approval"
grep -q "^refs: $Q_PTY,$R_PTY\$" "$JOURNAL/$A_PTY.md" \
  || fail "the window's decision is not bound to the change it decided"
grep -q 'Fine by me.' "$JOURNAL/$A_PTY.md" || fail "the typed comment was not stored"
"$CASTLE" validate >/dev/null || fail "the journal does not validate after a decision made in the window"
assert_checkouts_untouched "after approving through the window"

# ---------------------------------------------------------------------
log "multiple pending: each is decided on its own, and deciding one leaves the other"
# ---------------------------------------------------------------------
# Two changes waiting at once, which is the case a resident actually
# meets. Nothing batches: one invocation decides exactly one.
clear_pending_proposals
REQ_M1="$("$CASTLE" ask "APPROVAL-FIXTURE-MULTI-A: the first of two invented complaints.")"
"$CASTLE" work "$REQ_M1" >/dev/null
# A whole second between the two turns, because record ids carry a
# one-second timestamp and a random suffix: two changes filed inside
# the same second sort by that suffix, which is exactly the coin flip a
# test about "press 1 and get the older one" must not contain. Observed
# flaking before this line existed, not theorised.
sleep 1
REQ_M2="$("$CASTLE" ask "APPROVAL-FIXTURE-MULTI-B: the second of two invented complaints.")"
"$CASTLE" work "$REQ_M2" >/dev/null
Q_M1="$(proposal_question_for "$REQ_M1")"
Q_M2="$(proposal_question_for "$REQ_M2")"
[ -n "$Q_M1" ] && [ -n "$Q_M2" ] || fail "the two-change fixture did not produce two changes"
# And the ordering asserted before it is relied on, so a shift in the
# picker's sort fails here with a sentence rather than by silently
# deciding the wrong change two lines below.
[ "$(pending_proposals | head -1)" = "$Q_M1" ] \
  || fail "the older change is not first in the pending order: $(pending_proposals | tr '\n' ' ')"

log "  -- both are offered, oldest first, and the surface says how many are left"
drive_modal "$WORKDIR/review-multi.txt" --mode review -- \
  "wait:Press a number to review" "key:1" "wait:any other key closes this" "key:d" \
  "wait:Press Enter to close" "send:\n"
MULTI_OUT="$(cat "$WORKDIR/review-multi.txt")"
[ "$(transcript_rc "$WORKDIR/review-multi.txt")" = "0" ] || fail "deciding one of two changes did not exit 0"
printf '%s\n' "$MULTI_OUT" | grep -q '1 more proposed change waiting' \
  || fail "the surface did not say another change is still waiting: $MULTI_OUT"
[ -n "$(answers_naming "$Q_M1")" ] || fail "pressing 1 did not decide the older change: $MULTI_OUT"
[ -z "$(answers_naming "$Q_M2")" ] \
  || fail "deciding one change decided the other as well — one invocation must decide exactly one"
grep -q '^decision: defer$' "$(answers_naming "$Q_M1" | head -1)" \
  || fail "the older change was not deferred"
# Same false-promise check as the approval case above, against the
# actual confirmation a resident sees after pressing 'd': it must say
# the change is closed, not that it can be revisited from the list.
printf '%s\n' "$MULTI_OUT" | tr -d '\r' | grep -qx 'Set aside — it will not be offered again.' \
  || fail "the defer confirmation is not the honest one: $MULTI_OUT"
printf '%s\n' "$MULTI_OUT" | grep -qi 'come back' \
  && fail "the defer confirmation still promises a way back to the deferred change: $MULTI_OUT"
"$CASTLE" validate >/dev/null || fail "the journal does not validate with one of two changes decided"

log "  -- and the one left is still offered afterwards, on its own"
drive_modal "$WORKDIR/review-multi-2.txt" --mode review -- \
  "wait:any other key closes this" "key:x"
MULTI2_OUT="$(cat "$WORKDIR/review-multi-2.txt")"
printf '%s\n' "$MULTI2_OUT" | grep -q 'Press a number to review' \
  && fail "a picker was shown for a single remaining change"
assert_checkouts_untouched "after the multiple-pending cases"

# ---------------------------------------------------------------------
log "deciding a change runs nothing that could apply or activate one"
# ---------------------------------------------------------------------
# `assert_checkouts_untouched` proves nothing MOVED. This proves
# nothing was even reached for, which is the stronger and more durable
# claim: a decision path that shelled out to a builder and happened to
# fail would pass the first check and fail this one. Stubs that record
# the call and exit 0 shadow the real tools for exactly one decision —
# so a future change that starts applying an approval here does not
# quietly succeed, it lands in this log.
#
# Behavioural rather than a grep over the source, deliberately: a grep
# cannot tell a command named in a comment explaining why it is never
# run from one that is actually run, and both files are full of the
# former.
GUARD_BIN="$WORKDIR/guard-bin"
GUARD_LOG="$WORKDIR/guard.log"
mkdir -p "$GUARD_BIN"
: > "$GUARD_LOG"
for tool in nixos-rebuild switch-to-configuration systemctl sudo git nix patch; do
  cat > "$GUARD_BIN/$tool" <<GUARD
#!/usr/bin/env bash
printf '%s %s\n' "$tool" "\$*" >> "$GUARD_LOG"
exit 0
GUARD
  chmod +x "$GUARD_BIN/$tool"
done
Q_GUARD="$(pending_proposals | head -1)"
[ -n "$Q_GUARD" ] || fail "no change is pending to make the no-subprocess proof against"
PATH="$GUARD_BIN:$PATH" "$CASTLE" answer --decision approve "$Q_GUARD" </dev/null >/dev/null \
  || fail "approving under the shadowed PATH failed"
[ ! -s "$GUARD_LOG" ] \
  || fail "deciding a change ran something that could apply or activate one: $(cat "$GUARD_LOG")"
assert_checkouts_untouched "after the no-subprocess proof"

# ---------------------------------------------------------------------
log "the validator's permanent gate: every new field, and every way of getting it wrong"
# ---------------------------------------------------------------------
# Planted into a throwaway journal via --journal, so the main one above
# stays clean and every case below can be genuinely malformed. These
# are the records a hand edit, a restore, or a future tool could
# produce; `castle record` refuses several of them at the door, and
# this is the backstop for the ones that never went through a door.
PLANT="$WORKDIR/plant"
plant_reset() { rm -rf "$PLANT"; mkdir -p "$PLANT"; }
plant() {
  # Usage: plant <id> <type> <refs> [extra frontmatter lines...]
  local id="$1" rtype="$2" refs="$3"; shift 3
  {
    echo "---"
    echo "id: $id"
    echo "type: $rtype"
    echo "provenance: requested"
    echo "refs: $refs"
    echo "seat: intake"
    echo "created: 2026-02-01T00:00:00Z"
    local line
    for line in "$@"; do echo "$line"; done
    echo "---"
    echo
    echo "A planted record, harness fixture only."
  } > "$PLANT/$id.md"
}
plant_base() {
  plant_reset
  plant 20260201T000000Z-request-aaaaaa request ""
  plant 20260201T000001Z-result-bbbbbb result 20260201T000000Z-request-aaaaaa \
    "outcome: completed" "target: private"
  plant 20260201T000002Z-question-cccccc question \
    "20260201T000000Z-request-aaaaaa,20260201T000001Z-result-bbbbbb" \
    "proposal-sha256: $VALID_HASH"
}
VALID_HASH="$(printf 'anything at all' | sha256sum | cut -d' ' -f1)"

expect_valid() {
  "$CASTLE" validate --journal "$PLANT" >/dev/null 2>"$WORKDIR/plant.err" \
    || fail "$1: the validator rejected a well-formed journal: $(cat "$WORKDIR/plant.err")"
}
expect_invalid() {
  local label="$1" needle="$2"
  if "$CASTLE" validate --journal "$PLANT" >/dev/null 2>"$WORKDIR/plant.err"; then
    fail "$label: the validator accepted it"
  fi
  grep -q -- "$needle" "$WORKDIR/plant.err" \
    || fail "$label: the validator complained about something else: $(cat "$WORKDIR/plant.err")"
}

log "  -- the well-formed shape validates (the control: without it every case below is vacuous)"
plant_base
plant 20260201T000003Z-answer-dddddd answer \
  "20260201T000002Z-question-cccccc,20260201T000001Z-result-bbbbbb" \
  "decision: approve" "proposal-sha256: $VALID_HASH"
expect_valid "the well-formed decision"

log "  -- a decision on a record that is not an answer is a fabricated authorization"
plant_base
plant 20260201T000003Z-result-eeeeee result 20260201T000000Z-request-aaaaaa \
  "outcome: completed" "decision: approve"
expect_invalid "a decision on a result" "fabricated authorization"

log "  -- a decision outside the vocabulary"
plant_base
plant 20260201T000003Z-answer-dddddd answer \
  "20260201T000002Z-question-cccccc,20260201T000001Z-result-bbbbbb" \
  "decision: probably" "proposal-sha256: $VALID_HASH"
expect_invalid "an unknown decision value" "is not one of approve, reject, defer"

log "  -- a proposal stamp on a record that reads it nowhere"
plant_base
plant 20260201T000003Z-decision-ffffff decision 20260201T000000Z-request-aaaaaa \
  "evidence: an invented decision" "proposal-sha256: $VALID_HASH"
expect_invalid "a stamp on a decision record" "belongs on the question"

log "  -- a stamp that is not a digest"
plant_base
plant 20260201T000003Z-answer-dddddd answer \
  "20260201T000002Z-question-cccccc,20260201T000001Z-result-bbbbbb" \
  "decision: approve" "proposal-sha256: NOTAHASH"
expect_invalid "a malformed stamp" "64 lowercase hex"

log "  -- a decision with nothing to say which bytes it authorized"
plant_base
plant 20260201T000003Z-answer-dddddd answer \
  "20260201T000002Z-question-cccccc,20260201T000001Z-result-bbbbbb" \
  "decision: approve"
expect_invalid "a decision with no stamp" "authorizes nothing checkable"

log "  -- a decision whose second ref is not the result it decides"
plant_base
plant 20260201T000003Z-answer-dddddd answer \
  "20260201T000002Z-question-cccccc,20260201T000000Z-request-aaaaaa" \
  "decision: approve" "proposal-sha256: $VALID_HASH"
expect_invalid "a decision pointing at a request" "second ref must be the result"

log "  -- a decision with only one ref"
plant_base
plant 20260201T000003Z-answer-dddddd answer "20260201T000002Z-question-cccccc" \
  "decision: approve" "proposal-sha256: $VALID_HASH"
expect_invalid "a decision with one ref" "fewer than two"

log "  -- two decisions on one change, the race the write path cannot lock against"
plant_base
plant 20260201T000003Z-answer-dddddd answer \
  "20260201T000002Z-question-cccccc,20260201T000001Z-result-bbbbbb" \
  "decision: approve" "proposal-sha256: $VALID_HASH"
plant 20260201T000004Z-answer-eeeeee answer \
  "20260201T000002Z-question-cccccc,20260201T000001Z-result-bbbbbb" \
  "decision: reject" "proposal-sha256: $VALID_HASH"
expect_invalid "two decisions on one change" "a second decision on"

log "  -- a diff boundary on a record that embeds no diff to bound"
plant_base
plant 20260201T000003Z-answer-dddddd answer \
  "20260201T000002Z-question-cccccc,20260201T000001Z-result-bbbbbb" \
  "decision: approve" "proposal-sha256: $VALID_HASH" "diff-boundary: 0123456789abcdef"
expect_invalid "a boundary on an answer" "'diff-boundary' is a result-record field"

log "  -- a diff boundary that is not the nonce shape, so it names a boundary no reader can find"
plant_base
plant 20260201T000003Z-result-eeeeee result 20260201T000000Z-request-aaaaaa \
  "outcome: completed" "diff-boundary: NOT-A-NONCE"
expect_invalid "a malformed boundary" "16 lowercase hex"

log "  -- and the correction this task made in passing: an outcome on a record that is not a result"
plant_base
plant 20260201T000003Z-answer-dddddd answer "20260201T000002Z-question-cccccc" \
  "outcome: completed"
expect_invalid "an outcome on an answer" "'outcome' is a result-record field"

# ---------------------------------------------------------------------
log "nothing this whole run did touched either checkout, or the running system"
# ---------------------------------------------------------------------
assert_checkouts_untouched "at the end of the run"

# ---------------------------------------------------------------------
log "no home-shaped path in anything this fixture commits to the repo"
# ---------------------------------------------------------------------
# CLAUDE.md's hard rule, checked mechanically rather than trusted.
LEAKED_PATHS="$(grep -nE '(/home/|\$HOME)' "${BASH_SOURCE[0]}" | grep -v '/home/resident' || true)"
[ -z "$LEAKED_PATHS" ] || fail "a home-shaped path leaked into a committed fixture file:
$LEAKED_PATHS"

log "all assertions passed"
