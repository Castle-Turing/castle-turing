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
    "$CASTLE" answer --decision defer "$id" >/dev/null \
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
grep -q 'Press Mod4+Shift+a to answer' "$CASTLE_NOTIFY_LOG" \
  || fail "the proposal notification does not tell the resident how to reach it"

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

log "  -- the status surface says approved, and says nothing was applied"
STATUS_APPROVED="$("$MODAL" --mode status --limit 40)"
printf '%s\n' "$STATUS_APPROVED" | grep -F "$REQ1" | grep -q 'approved — nothing applied yet' \
  || fail "an approved errand does not read as approved-but-unapplied: $(printf '%s\n' "$STATUS_APPROVED" | grep -F "$REQ1")"
printf '%s\n' "$STATUS_APPROVED" | grep -F "$REQ1" | grep -q 'waiting on you' \
  && fail "a decided change still reads as waiting on the resident"

log "  -- a second decision on the same change is refused"
if "$CASTLE" answer --decision reject "$Q1" >/dev/null 2>"$WORKDIR/second.err"; then
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
  answer="$("$CASTLE" answer --decision "$verdict" "$question")"
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
if "$CASTLE" answer --decision approve "$Q_STALE" >/dev/null 2>"$WORKDIR/stale.err"; then
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
"$CASTLE" answer --decision reject "$Q_STALE" >/dev/null \
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
if "$CASTLE" answer --decision approve "$Q_FACT_ID" >/dev/null 2>"$WORKDIR/fact.err"; then
  fail "a proposal that also elicits a fact was decided, writing a preference the resident never stated"
fi
grep -q 'resident model' "$WORKDIR/fact.err" \
  || fail "the fact-carrying refusal does not say what it prevented: $(cat "$WORKDIR/fact.err")"
[ "$(journal_file_count)" = "$FILES_BEFORE" ] || fail "the fact-carrying refusal wrote a record anyway"
[ "$(model_byte_count)" = "$MODEL_BEFORE" ] || fail "the fact-carrying refusal wrote into the resident model"

log "  -- and so is --fact supplied on the command line beside a decision"
# The other half of the same door, and the likelier one: the question's
# own field is not the only way a fact reaches the write path.
if "$CASTLE" answer --decision approve --fact "invented-preference-key" "$Q_DEF" \
  >/dev/null 2>"$WORKDIR/fact-flag.err"; then
  fail "--fact beside --decision wrote a resident-model entry as a side effect of a decision"
fi
[ "$(model_byte_count)" = "$MODEL_BEFORE" ] || fail "--fact beside --decision wrote into the resident model"

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
PATH="$GUARD_BIN:$PATH" "$CASTLE" answer --decision approve "$Q_GUARD" >/dev/null \
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
