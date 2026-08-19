#!/usr/bin/env bash
# test/agent-loop/resume.sh — errand resumption after an answer
# (docs/tasks/0023-resume-cold.md §11).
#
# Same shape as dispatch-test.sh, whose helpers and conventions this
# file reuses rather than reinventing: plain bash and stdlib python3,
# no Nix, zero models, zero network, a throwaway CASTLE_STATE_DIR and
# XDG_RUNTIME_DIR, the same notify stub.
#
# Everything here goes through `castle dispatch` or `castle work`,
# never `castle record` assembling a scenario by hand. That is not
# stylistic: the continuation packet, CASTLE_RESUME_ANSWER_IDS and the
# claim's widened `refs` all live inside `run_worker_turn`, and those
# two entry points are the only things that reach it. A test that built
# the journal by hand could assert the fold and still miss every part
# of the mechanism the fold exists to drive.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CASTLE="$REPO_ROOT/agent/castle"
CHECK="$REPO_ROOT/test/agent-loop/check_assertions.py"
WORKER_BLOCKING="$REPO_ROOT/test/agent-loop/scripted-worker-blocking.sh"
WORKER_BLOCKING_ALT="$REPO_ROOT/test/agent-loop/scripted-worker-blocking-alt.py"
WORKER_OK="$REPO_ROOT/test/agent-loop/contract-worker.sh"
WORKER_SELF_ANSWER="$REPO_ROOT/test/agent-loop/scripted-worker-self-answer.sh"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/castle-resume-test.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

export CASTLE_STATE_DIR="$WORKDIR/state"
export XDG_RUNTIME_DIR="$WORKDIR/runtime"
mkdir -p "$CASTLE_STATE_DIR" "$XDG_RUNTIME_DIR"
JOURNAL="$CASTLE_STATE_DIR/journal"

export CASTLE_NOTIFY_LOG="$WORKDIR/notify.log"
export CASTLE_NOTIFY_COMMAND="$REPO_ROOT/test/agent-loop/notify-stub.sh"
: > "$CASTLE_NOTIFY_LOG"

export CASTLE_REPO_ROOT="$WORKDIR/repo"
mkdir -p "$CASTLE_REPO_ROOT"
# The tenants file their question with this rather than a `castle` on
# $PATH, which no-Nix CI does not have.
export CASTLE_TEST_CASTLE_BIN="$CASTLE"
export CASTLE_WORKER_COMMAND="$WORKER_BLOCKING"

log() { printf '>>> %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# The same three helpers dispatch-test.sh uses, tolerating "nothing of
# that type yet" rather than letting a non-matching glob kill the script
# under `set -e` before the assertion that would have explained it.
records_of_type() { find "$JOURNAL" -name "*-$1-*.md" 2>/dev/null || true; }
count_of_type() { records_of_type "$1" | grep -c . || true; }
referencing() {
  local rtype="$1" id="$2"
  grep -l "^refs: .*$id" "$JOURNAL"/*-"$rtype"-*.md 2>/dev/null || true
}
count_referencing() { referencing "$1" "$2" | grep -c . || true; }

# The blocking question this errand's own turn raised: a question record
# carrying `blocking: true` whose refs name the request. Returned as an
# id, not a path, since every assertion below wants the id.
blocking_question_for() {
  local request_id="$1" path
  path="$(grep -l "^refs: .*$request_id" "$JOURNAL"/*-question-*.md 2>/dev/null \
    | xargs -r grep -l '^blocking: true$' | head -1 || true)"
  [ -n "$path" ] || return 0
  basename "$path" .md
}

# The marker string the fixtures grep for out of the continuation
# packet. Invented, hardware-neutral, and nothing like anything a real
# resident would say — this repo never puts real resident words in a
# fixture (CLAUDE.md's hard rule), and the resumption path is the one
# that carries them by design.
REQUEST_MARKER="RESUME-FIXTURE-REQUEST-MARKER"
ANSWER_MARKER="RESUME-FIXTURE-ANSWER-MARKER"

# The watermark first, on an empty journal, so nothing below is
# accidentally excluded by it (docs/tasks/0021 §2.2).
"$CASTLE" dispatch --watermark-only >/dev/null
"$CASTLE" validate >/dev/null

# ---------------------------------------------------------------------
log "a blocking question stops the errand, and an ANSWER to it resumes exactly one further turn"
# ---------------------------------------------------------------------
# Filed through stdin rather than as an argument so the body keeps a
# shape a packet builder could plausibly damage: an indented first line
# (an obviously-fake code block, invented like everything else here),
# and a last line with no trailing newline at all. `parse_record`
# preserves both deliberately — it strips only the single blank line
# after the closing fence, and says why in its own comment — so the
# renderer must too. A worker result carries an embedded unified diff,
# where leading spaces ARE the content, and a resumed tenant reads that
# diff to work out what an earlier turn already did.
REQ1="$(printf '%s\n%s\n\n%s' \
  "    $REQUEST_MARKER — indented first line, an invented code block" \
  "        placeholder deeper line" \
  "Resume test: an invented errand the tenant cannot finish alone." \
  | "$CASTLE" ask)"
log "  -> $REQ1"
"$CASTLE" dispatch >/dev/null
[ "$(count_referencing claim "$REQ1")" -eq 1 ] || fail "the first sweep did not run a turn on $REQ1"
[ "$(count_referencing result "$REQ1")" -eq 1 ] || fail "the first turn wrote no result for $REQ1"
Q1="$(blocking_question_for "$REQ1")"
[ -n "$Q1" ] || fail "the tenant filed no blocking question on its first turn"
log "  -> blocking question $Q1"
grep -q '^blocking: true$' "$JOURNAL/$Q1.md" || fail "$Q1 does not carry blocking: true"
"$CASTLE" validate >/dev/null

log "  -- and an unanswered blocking question resumes NOTHING, however many sweeps run"
"$CASTLE" dispatch >/dev/null
"$CASTLE" dispatch >/dev/null
[ "$(count_referencing claim "$REQ1")" -eq 1 ] || fail "an UNANSWERED blocking question started a second turn on $REQ1 — nothing but the resident may close a question"
[ "$(count_referencing result "$REQ1")" -eq 1 ] || fail "an unanswered blocking question produced a second result on $REQ1"

log "  -- a correction against this very request is planted BEFORE the answer"
# `_collect_downstream` would have pulled this into the errand's fold
# and handed it to the tenant: the resident's verdict about the system
# becoming an input to the work being judged. Planted here, before the
# resumption, so the resumed tenant's own refusal (it exits 6 on this
# marker) is what proves the selective fold excludes it — an assertion
# made after the turn could only ever prove the leak did not happen to
# be echoed.
CORRECTION="$("$CASTLE" correct --refs "$REQ1" "Resume test: RESUME-FIXTURE-MUST-NOT-REACH-A-TENANT — the resident says how the system is doing.")"
log "  -> planted correction $CORRECTION against $REQ1"

log "  -- the resident answers, and the next sweep resumes the errand"
A1="$("$CASTLE" answer "$Q1" "Resume test: $ANSWER_MARKER — the resident's invented word on the matter.")"
log "  -> answer $A1"
"$CASTLE" dispatch >/dev/null
[ "$(count_referencing claim "$REQ1")" -eq 2 ] || fail "the answered blocking question did not start a second turn: $(count_referencing claim "$REQ1") claim(s) on $REQ1"
[ "$(count_referencing result "$REQ1")" -eq 2 ] || fail "the resumed turn wrote no result of its own"

log "  -- the resuming claim names the answer it spent, after the request id"
RESUME_CLAIM_FILE="$(grep -l "^refs: $REQ1,$A1\$" "$JOURNAL"/*-claim-*.md 2>/dev/null || true)"
[ -n "$RESUME_CLAIM_FILE" ] || fail "no claim record carries 'refs: $REQ1,$A1' — the answer was never spent, which is the unbounded-retry loop"
RESUME_CLAIM="$(basename "$RESUME_CLAIM_FILE" .md)"
# The FIRST turn's claim must be untouched: byte-for-byte the shape it
# always had, request id and nothing else.
FIRST_CLAIM_FILE="$(grep -l "^refs: $REQ1\$" "$JOURNAL"/*-claim-*.md 2>/dev/null || true)"
[ -n "$FIRST_CLAIM_FILE" ] || fail "the first turn's claim no longer carries exactly 'refs: $REQ1' — a non-resuming turn's claim must be unchanged"

log "  -- and the resumed RESULT's refs are still exactly request,claim (0021's shape, untouched)"
RESUME_RESULT_FILE="$(grep -l "^refs: $REQ1,$RESUME_CLAIM\$" "$JOURNAL"/*-result-*.md 2>/dev/null || true)"
[ -n "$RESUME_RESULT_FILE" ] || fail "the resumed turn's result does not reference exactly its request and its claim: $(grep -h '^refs:' $(referencing result "$REQ1"))"
grep -q '^outcome: completed$' "$RESUME_RESULT_FILE" || fail "the resumed turn did not complete: $(grep '^outcome:' "$RESUME_RESULT_FILE")"

log "  -- the tenant proves it actually READ the packet: request, question and answer all reached its stdin"
grep -q "packet carried the request: .*$REQUEST_MARKER" "$RESUME_RESULT_FILE" \
  || fail "the resumed tenant did not see the original request in its continuation packet"
# And saw it unmodified. The fixture echoes the matched line verbatim
# after a one-space separator, so the expected string is that space
# plus the body's own four — which exist only if nothing stripped the
# body on the way to stdin. A `.strip()` anywhere in the packet builder
# collapses this to a single space and fails here.
EXPECTED_INDENT="$(printf 'packet carried the request:     %s' "$REQUEST_MARKER")"
grep -qF "$EXPECTED_INDENT" "$RESUME_RESULT_FILE" \
  || fail "the packet mangled the request body's leading whitespace: $(grep -n 'packet carried the request' "$RESUME_RESULT_FILE")"
grep -q "packet carried the question: .*the errand cannot continue until this is answered" "$RESUME_RESULT_FILE" \
  || fail "the resumed tenant did not see the blocking question in its continuation packet"
grep -q "packet carried the answer: .*$ANSWER_MARKER" "$RESUME_RESULT_FILE" \
  || fail "the resumed tenant did not see the resident's answer in its continuation packet"
grep -q "RESUMED with $A1" "$RESUME_RESULT_FILE" \
  || fail "the resumed tenant did not receive CASTLE_RESUME_ANSWER_IDS naming $A1"
"$CASTLE" validate >/dev/null

log "  -- and the correction planted before the turn never reached the tenant (it would have exited 6)"
grep -q "leaked a record this seat must never read" "$RESUME_RESULT_FILE" \
  && fail "the continuation packet carried the correction filed against $REQ1"
[ "$(count_of_type correction)" -eq 1 ] || fail "the correction fixture did not land"

# ---------------------------------------------------------------------
log "the same answer never resumes twice: two more sweeps, back to back, add nothing"
# ---------------------------------------------------------------------
"$CASTLE" dispatch >/dev/null
"$CASTLE" dispatch >/dev/null
[ "$(count_referencing claim "$REQ1")" -eq 2 ] || fail "a spent answer resumed the errand again: $(count_referencing claim "$REQ1") claims on $REQ1"
[ "$(count_referencing result "$REQ1")" -eq 2 ] || fail "a spent answer produced a third result on $REQ1"
"$CASTLE" validate >/dev/null

# ---------------------------------------------------------------------
log "a NON-blocking question, answered, resumes nothing — the field is what gates this, not the answer"
# ---------------------------------------------------------------------
# Deliberately the same shape as dispatch-test.sh's existing
# non-behavior fixture, on an errand this file worked itself: a plain
# `castle record --type question` with no --blocking.
REQ2="$("$CASTLE" ask "Resume test: $REQUEST_MARKER — a second invented errand, completed in one turn.")"
CASTLE_WORKER_COMMAND="$WORKER_OK" "$CASTLE" dispatch >/dev/null
[ "$(count_referencing result "$REQ2")" -eq 1 ] || fail "the ordinary tenant did not complete $REQ2"
Q2="$("$CASTLE" record --type question --provenance requested --seat worker --refs "$REQ2" \
  --body "Resume test: an ordinary question filed alongside a completed result.")"
A2="$("$CASTLE" answer "$Q2" "Resume test: the resident answers a non-blocking question.")"
log "  -> answered non-blocking $Q2 with $A2"
"$CASTLE" dispatch >/dev/null
"$CASTLE" dispatch >/dev/null
[ "$(count_referencing claim "$REQ2")" -eq 1 ] || fail "an answered NON-blocking question started a second turn on $REQ2"
[ "$(count_referencing result "$REQ2")" -eq 1 ] || fail "an answered NON-blocking question produced a second result on $REQ2"
"$CASTLE" validate >/dev/null

# ---------------------------------------------------------------------
log "two sweeps racing the same unspent answer produce ONE resumption between them, not one each"
# ---------------------------------------------------------------------
REQ3="$("$CASTLE" ask "Resume test: $REQUEST_MARKER — a third invented errand, for the race.")"
"$CASTLE" dispatch >/dev/null
Q3="$(blocking_question_for "$REQ3")"
[ -n "$Q3" ] || fail "no blocking question was raised on $REQ3"
A3="$("$CASTLE" answer "$Q3" "Resume test: $ANSWER_MARKER — the resident's word, for the race.")"
# Widened the same way dispatch-test.sh widens its concurrency window,
# so the two sweeps genuinely overlap rather than passing in sequence.
CASTLE_TEST_WORKER_SLEEP=2 "$CASTLE" dispatch >"$WORKDIR/race-a.out" 2>&1 &
RACE_A=$!
CASTLE_TEST_WORKER_SLEEP=2 "$CASTLE" dispatch >"$WORKDIR/race-b.out" 2>&1 &
RACE_B=$!
wait "$RACE_A" || fail "racing sweep A exited nonzero: $(cat "$WORKDIR/race-a.out")"
wait "$RACE_B" || fail "racing sweep B exited nonzero: $(cat "$WORKDIR/race-b.out")"
[ "$(count_referencing claim "$REQ3")" -eq 2 ] || fail "two racing sweeps resumed $REQ3 twice: $(count_referencing claim "$REQ3") claims"
[ "$(count_referencing result "$REQ3")" -eq 2 ] || fail "two racing sweeps wrote $(count_referencing result "$REQ3") results for $REQ3"
grep -q "^refs: $REQ3,$A3\$" "$JOURNAL"/*-claim-*.md || fail "the racing resumption did not spend $A3"
"$CASTLE" validate >/dev/null

# ---------------------------------------------------------------------
log "a resumed turn that FAILS is not tried again — the claim spent the answer whatever the outcome"
# ---------------------------------------------------------------------
REQ4="$("$CASTLE" ask "Resume test: $REQUEST_MARKER — a fourth invented errand whose resumption fails.")"
"$CASTLE" dispatch >/dev/null
Q4="$(blocking_question_for "$REQ4")"
[ -n "$Q4" ] || fail "no blocking question was raised on $REQ4"
A4="$("$CASTLE" answer "$Q4" "Resume test: $ANSWER_MARKER — the resident's word on the errand that will fail.")"
CASTLE_TEST_WORKER_FAIL_ON_RESUME=1 "$CASTLE" dispatch >/dev/null
FAILED_RESULT_FILE="$(grep -l '^outcome: failed$' $(referencing result "$REQ4") 2>/dev/null || true)"
[ -n "$FAILED_RESULT_FILE" ] || fail "the failing resumed turn did not produce an outcome: failed result for $REQ4"
grep -q "^refs: $REQ4,$A4\$" "$JOURNAL"/*-claim-*.md || fail "the failing resumed turn's claim does not name $A4 — a failed resumption must still spend its answer"
CLAIMS_AFTER_FAIL="$(count_referencing claim "$REQ4")"
"$CASTLE" dispatch >/dev/null
"$CASTLE" dispatch >/dev/null
[ "$(count_referencing claim "$REQ4")" -eq "$CLAIMS_AFTER_FAIL" ] || fail "a failed resumption was retried automatically — resumption must not become retry"
"$CASTLE" validate >/dev/null

log "  -- and the resident can still retry it by hand, exactly like any other failed errand"
CASTLE_TEST_WORKER_FAIL_ON_RESUME= "$CASTLE" work "$REQ4" >/dev/null 2>&1 || true
[ "$(count_referencing claim "$REQ4")" -eq $(( CLAIMS_AFTER_FAIL + 1 )) ] || fail "a hand-run castle work on a failed resumed errand did not start a turn"
"$CASTLE" validate >/dev/null

# ---------------------------------------------------------------------
log "the tenant can be SWAPPED between an errand's first turn and its resumed one"
# ---------------------------------------------------------------------
# Proposal 03's re-tenanting claim inside a single errand, which is a
# stronger form of what tenant-swap.sh proves across whole runs: the
# errand boundary is what makes continuation possible, so nothing about
# it may depend on the same harness being on both sides of the answer.
REQ5="$("$CASTLE" ask "Resume test: $REQUEST_MARKER — a fifth invented errand, re-tenanted mid-flight.")"
"$CASTLE" dispatch >/dev/null   # bash tenant raises the blocking question
Q5="$(blocking_question_for "$REQ5")"
[ -n "$Q5" ] || fail "no blocking question was raised on $REQ5"
A5="$("$CASTLE" answer "$Q5" "Resume test: $ANSWER_MARKER — the resident's word, answered to a different tenant.")"
CASTLE_WORKER_COMMAND="$WORKER_BLOCKING_ALT" "$CASTLE" dispatch >/dev/null
[ "$(count_referencing claim "$REQ5")" -eq 2 ] || fail "the swapped-in tenant did not resume $REQ5"
ALT_RESULT_FILE="$(grep -l 'scripted-worker-blocking-alt' $(referencing result "$REQ5") 2>/dev/null || true)"
[ -n "$ALT_RESULT_FILE" ] || fail "no result came from the python tenant — the resumed turn ran the wrong one"
grep -q "packet carried the answer: .*$ANSWER_MARKER" "$ALT_RESULT_FILE" \
  || fail "a tenant that never saw the first turn did not receive the answer in its packet — resumption depends on the harness, which is exactly what it must not do"
grep -q '^outcome: completed$' "$ALT_RESULT_FILE" || fail "the re-tenanted resumption did not complete"
"$CASTLE" validate >/dev/null

# ---------------------------------------------------------------------
log "a blocking question filed against its own RESULT, not the request, still resumes the errand"
# ---------------------------------------------------------------------
# The shape the production tenant can actually produce: castle-worker-
# claude hands the --refs choice to a model, and a question refs'd
# against the turn's own result is a reasonable thing for one to write.
# Strict direct keying would leave it permanently unattributable —
# answered, and resuming nothing, silently, forever.
REQ6="$("$CASTLE" ask "Resume test: $REQUEST_MARKER — a sixth invented errand, questioned through its result.")"
CASTLE_WORKER_COMMAND="$WORKER_OK" "$CASTLE" dispatch >/dev/null
RESULT6="$(basename "$(referencing result "$REQ6")" .md)"
Q6="$("$CASTLE" record --type question --provenance requested --seat worker --refs "$RESULT6" \
  --blocking --body "Resume test: a blocking question filed against its own result, not the request.")"
A6="$("$CASTLE" answer "$Q6" "Resume test: $ANSWER_MARKER — the resident's word on the indirect question.")"
"$CASTLE" dispatch >/dev/null
[ "$(count_referencing claim "$REQ6")" -eq 2 ] || fail "a blocking question refs'd through its own result did not resume $REQ6"
grep -q "^refs: $REQ6,$A6\$" "$JOURNAL"/*-claim-*.md || fail "the resumption of $REQ6 did not spend $A6"
"$CASTLE" validate >/dev/null

# ---------------------------------------------------------------------
log "a FOLLOW-UP request's blocking question resumes the follow-up, never its parent"
# ---------------------------------------------------------------------
# The contamination case `_collect_downstream` would have produced.
# The follow-up carries filed-during-turn only if a tenant filed it, and
# this one is the resident's own, so it is ordinarily eligible.
REQ7="$("$CASTLE" ask "Resume test: $REQUEST_MARKER — a seventh invented errand, the parent.")"
CASTLE_WORKER_COMMAND="$WORKER_OK" "$CASTLE" dispatch >/dev/null
CLAIMS_PARENT_BEFORE="$(count_referencing claim "$REQ7")"
REQ7B="$("$CASTLE" ask --refs "$REQ7" "Resume test: $REQUEST_MARKER — the follow-up, filed against its parent.")"
"$CASTLE" dispatch >/dev/null   # blocking tenant works the follow-up
Q7B="$(blocking_question_for "$REQ7B")"
[ -n "$Q7B" ] || fail "no blocking question was raised on the follow-up $REQ7B"
A7B="$("$CASTLE" answer "$Q7B" "Resume test: $ANSWER_MARKER — the resident's word on the follow-up.")"
"$CASTLE" dispatch >/dev/null
[ "$(count_referencing claim "$REQ7")" -eq "$CLAIMS_PARENT_BEFORE" ] || fail "answering the follow-up's blocking question resumed its PARENT $REQ7 as well"
[ "$(count_referencing claim "$REQ7B")" -eq 2 ] || fail "the follow-up $REQ7B was not resumed by its own answer"
"$CASTLE" validate >/dev/null

# ---------------------------------------------------------------------
log "a prior turn cannot forge a section boundary and put words in the resident's mouth"
# ---------------------------------------------------------------------
# The third door into the same attack the provenance-keyed labels and
# the self-answer refusal close: not writing a record that lies, but
# writing a record whose BODY forges the structure around it. A result
# body is model-authored and is quoted byte-for-byte into the next
# turn's packet, so under fixed markdown headings turn one could emit
# "### The resident's answer, verbatim" plus an instruction, and turn
# two would read it as the resident speaking. Boundaries carry a
# per-turn nonce instead, which no record can contain because no record
# was written after it existed.
REQ10="$("$CASTLE" ask "Resume test: $REQUEST_MARKER — a tenth invented errand, whose first turn forges a boundary.")"
CASTLE_TEST_WORKER_FORGE=1 "$CASTLE" dispatch >/dev/null
FORGE_RESULT1="$(referencing result "$REQ10")"
grep -q "FORGED-ANSWER-MARKER" "$FORGE_RESULT1" || fail "the forging fixture did not write its forged boundary into its result"
grep -q "FORGED-HEADING-MARKER" "$FORGE_RESULT1" || fail "the forging fixture did not write its forged heading into its result"
Q10="$(blocking_question_for "$REQ10")"
[ -n "$Q10" ] || fail "no blocking question was raised on $REQ10"
A10="$("$CASTLE" answer "$Q10" "Resume test: $ANSWER_MARKER — the resident's only real word on this errand.")"
"$CASTLE" dispatch >/dev/null
FORGE_RESULT2="$(grep -l "real resident-answer sections" $(referencing result "$REQ10") 2>/dev/null || true)"
[ -n "$FORGE_RESULT2" ] || fail "the resumed turn on $REQ10 produced no packet report at all"
# Exactly one section really is the resident answering — the forged one
# is in the packet, quoted, and is not counted.
grep -q "real resident-answer sections: 1" "$FORGE_RESULT2" \
  || fail "the resumed tenant counted a forged boundary as a real resident answer: $(grep 'real resident-answer sections' "$FORGE_RESULT2")"
grep -q "a forged boundary is present as quoted content" "$FORGE_RESULT2" \
  || fail "the forged text never reached the packet — this case is proving nothing"
grep -q "a forged heading is present as quoted content" "$FORGE_RESULT2" \
  || fail "the forged markdown heading never reached the packet — this case is proving nothing"
# And the real answer is the one the tenant acted on.
grep -q "packet carried the answer: .*$ANSWER_MARKER" "$FORGE_RESULT2" \
  || fail "the resumed tenant did not see the resident's real answer"
"$CASTLE" validate >/dev/null

# ---------------------------------------------------------------------
log "a FIRST turn that spends an answer is not announced as a resumption of a turn that never happened"
# ---------------------------------------------------------------------
# A blocking question can be filed and answered before anything runs.
# The answer is still spent — that is what stops a later sweep starting
# a turn off it — but there is no earlier account for a packet to carry,
# so the claim must not narrate one and the tenant must not be told to
# read one. The spend is accounting; the narrative is a claim about
# history, and only the second one is gated.
REQ11="$("$CASTLE" ask "Resume test: $REQUEST_MARKER — an eleventh invented errand, questioned before any turn ran.")"
Q11="$("$CASTLE" record --type question --provenance requested --seat worker --refs "$REQ11" \
  --blocking --body "Resume test: a blocking question filed before this errand had a turn.")"
A11="$("$CASTLE" answer "$Q11" "Resume test: $ANSWER_MARKER — answered before any turn existed.")"
# The blocking fixture, deliberately: it is the one that reports
# whether CASTLE_RESUME_ANSWER_IDS reached it, so the assertion below
# is about the mechanism rather than about a fixture that never
# mentions the variable either way.
"$CASTLE" dispatch >/dev/null
[ "$(count_referencing claim "$REQ11")" -eq 1 ] || fail "the first turn on $REQ11 did not run, or ran twice"
FIRST_CLAIM11="$(grep -l "^refs: $REQ11,$A11\$" "$JOURNAL"/*-claim-*.md 2>/dev/null || true)"
[ -n "$FIRST_CLAIM11" ] || fail "the first turn did not spend $A11 — a later sweep would resume off it forever"
grep -q "RESUMPTION" "$FIRST_CLAIM11" \
  && fail "a first turn's claim announced itself as a resumption of a turn that never happened"
FIRST_RESULT11="$(referencing result "$REQ11")"
grep -q "RESUMED with" "$FIRST_RESULT11" \
  && fail "the tenant was told this was a resumed turn on an errand that had never had one"
grep -q "filed blocking question" "$FIRST_RESULT11" \
  || fail "the first turn did not run the fixture that reports resumption — this case proves nothing"
# Spent means spent: no further sweep starts another turn off that answer.
"$CASTLE" dispatch >/dev/null
"$CASTLE" dispatch >/dev/null
[ "$(count_referencing claim "$REQ11")" -eq 1 ] || fail "the answer spent by the first turn resumed $REQ11 anyway"
"$CASTLE" validate >/dev/null

# ---------------------------------------------------------------------
log "a worker tenant cannot answer its own question — by any path it has"
# ---------------------------------------------------------------------
# Only the resident may close a question (docs/architecture.md,
# Proposal 05). Before this refusal existed a tenant could file a
# blocking question and its own answer on the same turn, and the errand
# was eligible again on the very next sweep — five turns off one
# request, unattended. The refusal lives in `write_record`, so every
# path a tenant has reaches the same wall; the fixture below tries the
# two CLI ones and reports what happened on stdout, where the result
# record captures it.
REQ9="$("$CASTLE" ask "Resume test: $REQUEST_MARKER — a ninth invented errand, whose tenant tries to answer itself.")"
CASTLE_WORKER_COMMAND="$WORKER_SELF_ANSWER" "$CASTLE" dispatch >/dev/null
SELF_RESULT_FILE="$(referencing result "$REQ9")"
[ -n "$SELF_RESULT_FILE" ] || fail "the self-answering tenant's turn produced no result at all"
grep -q "self-answer: castle answer was REFUSED" "$SELF_RESULT_FILE" \
  || fail "a tenant answered its own question through castle answer: $(cat "$SELF_RESULT_FILE")"
grep -q "self-answer: castle record --type answer was REFUSED" "$SELF_RESULT_FILE" \
  || fail "a tenant answered its own question through castle record: $(cat "$SELF_RESULT_FILE")"
grep -q "Proposal 05" "$SELF_RESULT_FILE" \
  || fail "the refusal did not say why in Proposal 05's terms: $(cat "$SELF_RESULT_FILE")"
# No answer record naming the tenant's own question exists, so nothing
# is resumable and no further turn runs however many sweeps happen.
Q9="$(blocking_question_for "$REQ9")"
[ -n "$Q9" ] || fail "the self-answering tenant filed no blocking question"
[ -z "$(referencing answer "$Q9")" ] || fail "an answer record naming $Q9 exists — the refusal did not hold"
"$CASTLE" dispatch >/dev/null
"$CASTLE" dispatch >/dev/null
[ "$(count_referencing claim "$REQ9")" -eq 1 ] || fail "a self-answering tenant granted itself $(count_referencing claim "$REQ9") turns on $REQ9"
[ "$(count_referencing result "$REQ9")" -eq 1 ] || fail "a self-answering tenant produced more than one result on $REQ9"
"$CASTLE" validate >/dev/null

log "  -- and the resident answering that same question still resumes it, exactly once"
A9="$("$CASTLE" answer "$Q9" "Resume test: $ANSWER_MARKER — the resident closes the question the tenant could not.")"
CASTLE_WORKER_COMMAND="$WORKER_BLOCKING" "$CASTLE" dispatch >/dev/null
[ "$(count_referencing claim "$REQ9")" -eq 2 ] || fail "the resident's own answer did not resume $REQ9 — the refusal caught more than it should"
grep -q "^refs: $REQ9,$A9\$" "$JOURNAL"/*-claim-*.md || fail "the resumption of $REQ9 did not spend $A9"
"$CASTLE" validate >/dev/null

# ---------------------------------------------------------------------
log "an automatic turn whose answer was spent between the fold and the lease writes NOTHING"
# ---------------------------------------------------------------------
# The interleaving itself cannot be produced from outside the process —
# the window is between dispatch's fold and `acquire_lock`, with no
# hook in between — so this drives the guard directly, in the state the
# race leaves behind: a resulted request, its answer already spent by
# somebody else's claim, and a turn that dispatch authorised on the
# strength of that answer. `require_resumable` is the flag dispatch
# passes for exactly that shape. What must happen is nothing: no claim,
# no result, no spend, and the exception dispatch treats as a skip.
#
# The hand path is asserted in the same breath, because the constraint
# is symmetric: `castle work <id>` on the same request, with the same
# nothing to resume, is the deliberate unbounded retry path and must
# still run a full turn.
CLAIMS_BEFORE_RACE="$(count_referencing claim "$REQ1")"
RESULTS_BEFORE_RACE="$(count_referencing result "$REQ1")"
python3 - "$CASTLE" "$REQ1" <<'RACE_PY' || fail "the lost-resumption guard did not behave as specified"
import importlib.machinery, importlib.util, sys

castle_path, request_id = sys.argv[1], sys.argv[2]
loader = importlib.machinery.SourceFileLoader("castle_under_test", castle_path)
spec = importlib.util.spec_from_loader("castle_under_test", loader)
castle = importlib.util.module_from_spec(spec)
loader.exec_module(castle)

records = castle.load_all(castle.journal_dir())
request = records[request_id]
if castle._resumable_answers(records, request_id):
    print("fixture is wrong: this request still has something to resume", file=sys.stderr)
    raise SystemExit(1)
try:
    castle.run_worker_turn(request, require_resumable=True)
except castle.ResumptionLost:
    print("guard: an automatic turn with nothing left to resume was refused")
else:
    print("guard: the turn ran anyway — the bound is open", file=sys.stderr)
    raise SystemExit(1)
RACE_PY
[ "$(count_referencing claim "$REQ1")" -eq "$CLAIMS_BEFORE_RACE" ] || fail "the refused turn wrote a claim anyway"
[ "$(count_referencing result "$REQ1")" -eq "$RESULTS_BEFORE_RACE" ] || fail "the refused turn wrote a result anyway"

log "  -- while a hand-run castle work on the same request still runs a full turn (the retry path is unchanged)"
CASTLE_WORKER_COMMAND="$WORKER_OK" "$CASTLE" work "$REQ1" >/dev/null 2>&1 || true
[ "$(count_referencing claim "$REQ1")" -eq $(( CLAIMS_BEFORE_RACE + 1 )) ] || fail "castle work refused a hand retry — the unbounded escape hatch must not change"
"$CASTLE" validate >/dev/null

# ---------------------------------------------------------------------
log "a question whose blocking value is not the one spelling any writer produces resumes NOTHING"
# ---------------------------------------------------------------------
# The direction an unrecognised value has to fail in. `blocking: false`
# is not something `castle record --blocking` can write — it can only be
# hand-planted or written by some future tool — and the danger is not
# that it exists but that a fold reading "is this field non-blank" would
# resume an errand off a record whose own text says not to. The fold
# tests for the literal `true`, so this is inert; `castle validate`
# reports it separately, which is asserted in dispatch-test.sh rather
# than here (this journal has to stay valid for the assertions below).
REQ8="$("$CASTLE" ask "Resume test: $REQUEST_MARKER — an eighth invented errand, questioned in a spelling nothing writes.")"
CASTLE_WORKER_COMMAND="$WORKER_OK" "$CASTLE" dispatch >/dev/null
CLAIMS8_BEFORE="$(count_referencing claim "$REQ8")"
Q8="20260101T000000Z-question-fa1se0"
cat > "$JOURNAL/$Q8.md" <<EOF
---
id: $Q8
type: question
provenance: requested
refs: $REQ8
seat: worker
created: 2026-01-01T00:00:00Z
blocking: false
---

Resume test: a hand-planted question whose blocking value is not the one spelling any writer here produces.
EOF
A8="$("$CASTLE" answer "$Q8" "Resume test: the resident answers it anyway.")"
log "  -> answered $Q8 (blocking: false) with $A8"
"$CASTLE" dispatch >/dev/null
"$CASTLE" dispatch >/dev/null
[ "$(count_referencing claim "$REQ8")" -eq "$CLAIMS8_BEFORE" ] || fail "a question with 'blocking: false' resumed $REQ8 — an unrecognised spelling must fail toward doing nothing"
[ "$(count_referencing result "$REQ8")" -eq 1 ] || fail "a question with 'blocking: false' produced a second result on $REQ8"
# The whole fixture comes back out, the same way dispatch-test.sh
# withdraws its malformed-`outcome` record: this file holds itself to
# "castle validate passes throughout," and a record the validator is
# meant to reject cannot stay in the journal the later assertions fold
# over. The rejection itself is asserted in dispatch-test.sh, where it
# is the only thing that section is doing.
#
# Three files, not one: the answer would dangle without its question,
# and the sweeps above routed the question like any other, so the
# decision citing it would dangle too.
rm -f "$JOURNAL/$Q8.md" "$JOURNAL/$A8.md"
grep -l "^refs: $Q8\$" "$JOURNAL"/*-decision-*.md 2>/dev/null | xargs -r rm -f
"$CASTLE" validate >/dev/null || fail "the journal did not validate clean once the blocking: false fixture was withdrawn"

# ---------------------------------------------------------------------
log "nothing in any packet leaked a correction, a decision, or another errand's records"
# ---------------------------------------------------------------------
# Belt and braces over the whole journal rather than one errand: every
# resumed tenant refuses the marker outright (exit 6), so a leak
# anywhere shows up as a failed turn whose result says so.
LEAKED="$(grep -l "leaked a record this seat must never read" "$JOURNAL"/*-result-*.md 2>/dev/null || true)"
[ -z "$LEAKED" ] || fail "a continuation packet leaked a record a worker tenant must never read: $LEAKED"

# ---------------------------------------------------------------------
log "final sweep, then independent structural assertions over the whole journal"
# ---------------------------------------------------------------------
"$CASTLE" dispatch >/dev/null
"$CASTLE" validate
# Free and strong: every result and question, resumed ones included,
# has to carry a decision citing it. A resumed result routed as
# second-class would fail here without this file asserting it directly.
"$CHECK" "$JOURNAL"

log "all assertions passed"
