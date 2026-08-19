#!/usr/bin/env bash
# test/agent-loop/scripted-worker-self-answer.sh — a worker tenant that
# tries to close its own question, and must fail at every door
# (docs/tasks/0023-resume-cold.md §5).
#
# Not a pathological fixture, and that is the point. A tenant reaching
# for `castle answer` after filing a question is a perfectly natural
# thing for a model to do — it has the CLI, it has the question id, and
# answering looks like progress. What made it dangerous is what the
# answer buys: since 0023 an answered blocking question grants the
# errand one further automatic turn, so a tenant that could answer
# itself could file a fresh blocking question and its own answer every
# turn and never stop. Reproduced at five turns on one request before
# `write_record` refused the write.
#
# The deeper reason is not the loop. Proposal 05 (docs/architecture.md)
# says inference may open a question and only the resident may close
# one — an answer the system wrote itself satisfies the "waiting on
# you" fold on every surface, so the question stops being pending and
# nobody is ever told that the machine, not the person, decided. That
# would still be wrong if resumption did not exist.
#
# This fixture reports what happened on its own stdout, which
# `run_worker_turn` folds into the turn's result record — so the
# assertion the harness makes is against the journal, not against a
# transient exit code.
set -euo pipefail

: "${CASTLE_REQUEST_ID:?scripted-worker-self-answer.sh: CASTLE_REQUEST_ID must be set}"
: "${CASTLE_DIFF_FILE:?scripted-worker-self-answer.sh: CASTLE_DIFF_FILE must be set}"
: "${CASTLE_TEST_CASTLE_BIN:?scripted-worker-self-answer.sh: CASTLE_TEST_CASTLE_BIN must be set}"

cat > /dev/null  # drain the continuation packet: the contract still applies

question_id="$("$CASTLE_TEST_CASTLE_BIN" record \
  --type question \
  --provenance requested \
  --seat worker \
  --refs "$CASTLE_REQUEST_ID" \
  --blocking \
  --body "Self-answer fixture question for $CASTLE_REQUEST_ID: the errand cannot continue until this is answered.")"
printf 'self-answer: filed blocking question %s\n' "$question_id"

# Door one: the resident-facing subcommand. CASTLE_WORKER_CLAIM is in
# this script's environment because `castle work` put it there, and
# every `castle` invoked from here inherits it — the same inheritance
# that stamps a tenant-filed request, used to refuse this write.
if "$CASTLE_TEST_CASTLE_BIN" answer "$question_id" \
  "The tenant tries to close its own question." >/dev/null 2>"$CASTLE_DIFF_FILE.answer-err"; then
  printf 'self-answer: castle answer SUCCEEDED — a seat closed its own question\n'
else
  printf 'self-answer: castle answer was REFUSED\n'
  sed -n '1p' "$CASTLE_DIFF_FILE.answer-err" | sed 's/^/self-answer: /'
fi

# Door two: the generic writer, which refuses only `correction` on its
# own account and would otherwise pass any type straight through.
if "$CASTLE_TEST_CASTLE_BIN" record --type answer --provenance requested --seat intake \
  --refs "$question_id" --body "The tenant tries the back door instead." \
  >/dev/null 2>"$CASTLE_DIFF_FILE.record-err"; then
  printf 'self-answer: castle record --type answer SUCCEEDED — the back door is open\n'
else
  printf 'self-answer: castle record --type answer was REFUSED\n'
fi

rm -f "$CASTLE_DIFF_FILE.answer-err" "$CASTLE_DIFF_FILE.record-err"
printf 'self-answer: ending the turn with the question open, which is the only correct move\n'
