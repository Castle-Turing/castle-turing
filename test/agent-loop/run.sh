#!/usr/bin/env bash
# test/agent-loop/run.sh — the scripted-tenant agent-loop harness
# (docs/tasks/0008-agent-layer-skeleton.md, extended by
# docs/tasks/0009-ambient-intake.md).
#
# Proposal 03's hardening test taking its first steps: exercises the
# full record loop — intake -> router -> worker -> router -> digest —
# with a scripted worker holding the worker seat and nothing else in
# the loop but this script and `castle` itself. Zero models, zero
# network, no Nix (agent/castle is stdlib Python; this harness runs
# anywhere bash + python3 do, unlike test/vm-install's harness).
#
# Two canned errands run through the loop so the router's provenance
# rule is checked in both directions: a `requested` errand must route
# to "notify" and an `initiated` one must route to "digest" — a single
# errand would leave the *other* branch of that rule completely
# unexercised. Both errands' scripted worker now also raises a
# mid-errand `question` record before its `result` (docs/tasks/0009
# item 7's third gap: nothing previously produced one in CI, even
# though worker-questions-route-through-the-router is a central claim
# of the architecture) — the requested errand's question is answered
# for real via `castle answer`, exercising Proposal 05's write path
# into the resident model end to end.
#
# The worker script itself is overridable via
# CASTLE_AGENT_LOOP_WORKER — test/agent-loop/tenant-swap.sh runs this
# whole script twice with two differently-shaped scripted workers and
# diffs a normalized summary of the resulting journals, which this
# script writes to CASTLE_AGENT_LOOP_SUMMARY_OUT when that variable is
# set.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CASTLE="$REPO_ROOT/agent/castle"
WORKER="${CASTLE_AGENT_LOOP_WORKER:-$REPO_ROOT/test/agent-loop/scripted-worker.sh}"
CHECK="$REPO_ROOT/test/agent-loop/check_assertions.py"
NORMALIZE="$REPO_ROOT/test/agent-loop/normalize_journal.py"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/castle-agent-loop.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

# CASTLE_STATE_DIR is the env var docs/tasks/0008 calls out as what
# makes this harness possible: it points a real journal at a throwaway
# temp directory instead of a resident's actual state/ dir.
export CASTLE_STATE_DIR="$WORKDIR/state"
export XDG_RUNTIME_DIR="$WORKDIR/runtime"
mkdir -p "$CASTLE_STATE_DIR" "$XDG_RUNTIME_DIR"

# CASTLE_NOTIFY_COMMAND (docs/tasks/0009 item 5): CI has no notification
# daemon and no display session, so `castle route`'s attempt to fire a
# real notification on the `notify` channel is pointed at a stub that
# logs each call instead of failing (harmlessly) against a missing
# notify-send. This is the same pattern CASTLE_STATE_DIR already uses:
# the Nix module (modules/agent) wires a Nix option into this
# environment variable for a real deployment; this plain-bash harness
# sets the variable directly, bypassing Nix entirely.
export CASTLE_NOTIFY_LOG="$WORKDIR/notify.log"
export CASTLE_NOTIFY_COMMAND="$REPO_ROOT/test/agent-loop/notify-stub.sh"
: > "$CASTLE_NOTIFY_LOG"

log() { printf '>>> %s\n' "$*"; }
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  printf 'Journal preserved would have been at: %s (already cleaned up on exit)\n' "$CASTLE_STATE_DIR/journal" >&2
  exit 1
}

log "using worker tenant: $WORKER"

log "intake: filing a resident-requested errand"
REQ1="$("$CASTLE" ask "Test errand alpha: resident-requested, should surface via notify.")"
log "  -> $REQ1"

log "intake: filing a system-initiated errand"
REQ2="$("$CASTLE" ask --provenance initiated "Test errand beta: system-initiated, should fold into the digest.")"
log "  -> $REQ2"

log "router pass before any result exists — must be a no-op, not a crash"
ROUTE1_OUT="$("$CASTLE" route)"
echo "$ROUTE1_OUT"
case "$ROUTE1_OUT" in
  *"nothing unrouted"*) ;;
  *) fail "router routed something before any result/question record existed: $ROUTE1_OUT" ;;
esac

log "scripted worker seat: request alpha (raises a question, then a result)"
RES1="$("$WORKER" "$CASTLE" "$REQ1")"
log "  -> $RES1"

log "scripted worker seat: request beta (raises a question, then a result)"
RES2="$("$WORKER" "$CASTLE" "$REQ2")"
log "  -> $RES2"

# `|| true` on every grep-into-a-variable below (finding 7, 0009 review
# pass): under `set -euo pipefail`, a `grep` that matches nothing exits
# non-zero, and that failure — piped through `head -n1` or not — kills
# the script right here, before the `[ -n ... ] || fail "..."` on the
# next line ever runs. The operator then sees a bare grep error instead
# of the descriptive diagnostic this script was written to give them.
# `|| true` lets the assignment fall through to empty, so the actual
# check on the next line is the thing that fails loudly.
QUESTION1="$(grep -l "^refs: $REQ1\$" "$CASTLE_STATE_DIR"/journal/*-question-*.md | head -n1 || true)"
[ -n "$QUESTION1" ] || fail "expected the alpha worker to raise a question referencing $REQ1; none found"
QUESTION1="$(basename "$QUESTION1" .md)"
QUESTION2="$(grep -l "^refs: $REQ2\$" "$CASTLE_STATE_DIR"/journal/*-question-*.md | head -n1 || true)"
[ -n "$QUESTION2" ] || fail "expected the beta worker to raise a question referencing $REQ2; none found"
QUESTION2="$(basename "$QUESTION2" .md)"
log "  -> question alpha: $QUESTION1, question beta: $QUESTION2"

log "router pass: must append a decision record for each result and question, nothing silent"
"$CASTLE" route

DECISION_COUNT_1="$(find "$CASTLE_STATE_DIR/journal" -name '*-decision-*.md' | wc -l | tr -d ' ')"
[ "$DECISION_COUNT_1" -eq 4 ] || fail "expected exactly 4 decision records after routing both questions and both results, got $DECISION_COUNT_1"

log "router pass: idempotent — a fully-routed journal produces zero new decisions"
ROUTE3_OUT="$("$CASTLE" route)"
echo "$ROUTE3_OUT"
case "$ROUTE3_OUT" in
  *"nothing unrouted"*) ;;
  *) fail "a second route pass over an already-routed journal routed something again: $ROUTE3_OUT" ;;
esac
DECISION_COUNT_2="$(find "$CASTLE_STATE_DIR/journal" -name '*-decision-*.md' | wc -l | tr -d ' ')"
[ "$DECISION_COUNT_2" -eq "$DECISION_COUNT_1" ] || fail "idempotency check failed: decision count went from $DECISION_COUNT_1 to $DECISION_COUNT_2"

log "validate: every record in the journal must pass the schema check"
"$CASTLE" validate

log "independent structural assertions (evidence non-empty, nothing routed silently)"
"$CHECK" "$CASTLE_STATE_DIR/journal"

log "notify channel: the requested errand's question+result must have actually fired the (stubbed) notify command"
NOTIFY_COUNT="$(wc -l < "$CASTLE_NOTIFY_LOG" | tr -d ' ')"
[ "$NOTIFY_COUNT" -eq 2 ] || fail "expected exactly 2 notify-command invocations (question+result for the requested errand), got $NOTIFY_COUNT"

log "digest: fold the journal and check both errands render"
DIGEST_OUT="$("$CASTLE" digest)"
echo "$DIGEST_OUT"
echo "$DIGEST_OUT" | grep -q "Test errand alpha" || fail "digest did not render errand alpha's request body"
echo "$DIGEST_OUT" | grep -q "Test errand beta" || fail "digest did not render errand beta's request body"
echo "$DIGEST_OUT" | grep -q "channel: notify" || fail "digest did not show a 'notify'-channel decision anywhere"
echo "$DIGEST_OUT" | grep -q "channel: digest" || fail "digest did not show a 'digest'-channel decision anywhere"

log "checking the channel landed on the RIGHT errand, not just present somewhere"
# Same `|| true` reasoning as above (finding 7): each assignment below
# has no `[ -n ... ]` check of its own, but a `grep -l` that matches
# nothing would still kill the script via set -e before the `grep -q
# ... || fail "..."` on the following line ever ran. With `|| true`,
# a no-match assignment instead leaves the variable empty, `grep -q
# pattern ""` fails to open a file named "" and returns non-zero, and
# the intended `fail "..."` diagnostic fires as designed.
DECISION_FOR_RES1="$(grep -l "^refs: $RES1\$" "$CASTLE_STATE_DIR"/journal/*-decision-*.md || true)"
grep -q '^channel: notify$' "$DECISION_FOR_RES1" || fail "the requested errand's result did not route to 'notify': $DECISION_FOR_RES1"
DECISION_FOR_RES2="$(grep -l "^refs: $RES2\$" "$CASTLE_STATE_DIR"/journal/*-decision-*.md || true)"
grep -q '^channel: digest$' "$DECISION_FOR_RES2" || fail "the initiated errand's result did not route to 'digest': $DECISION_FOR_RES2"
DECISION_FOR_Q1="$(grep -l "^refs: $QUESTION1\$" "$CASTLE_STATE_DIR"/journal/*-decision-*.md || true)"
grep -q '^channel: notify$' "$DECISION_FOR_Q1" || fail "the requested errand's question did not route to 'notify': $DECISION_FOR_Q1"
DECISION_FOR_Q2="$(grep -l "^refs: $QUESTION2\$" "$CASTLE_STATE_DIR"/journal/*-decision-*.md || true)"
grep -q '^channel: digest$' "$DECISION_FOR_Q2" || fail "the initiated errand's question did not route to 'digest': $DECISION_FOR_Q2"

log "propensity fields: every decision castle route writes must carry considered + propensity, well-formed"
# Bottou et al. (JMLR 14, 2013): off-policy evaluation needs the
# considered set and the selection propensity on every logged decision.
# Checked on all four decisions from this pass (two results, two
# questions) rather than just one, since cmd_route writes them in a
# single loop body and a check on only one instance would miss a bug
# that only showed up on, say, the digest-channel branch.
for DECISION_FILE in "$DECISION_FOR_RES1" "$DECISION_FOR_RES2" "$DECISION_FOR_Q1" "$DECISION_FOR_Q2"; do
  grep -q '^considered: notify,digest$' "$DECISION_FILE" || fail "$DECISION_FILE: expected considered=notify,digest (today's router always weighs both channels)"
  grep -q '^propensity: 1\.0$' "$DECISION_FILE" || fail "$DECISION_FILE: expected propensity=1.0 (today's rule is deterministic — see agent/README.md)"
done

log "resident-model write path (Proposal 05): answering the alpha question, fact name read from the question record itself"
ANSWER1="$("$CASTLE" answer "$QUESTION1" "Fix small perceptual issues like this one and tell me afterward.")"
log "  -> $ANSWER1"
MODEL_FILE="$CASTLE_STATE_DIR/resident-model.md"
[ -f "$MODEL_FILE" ] || fail "castle answer --fact (auto-detected) did not create $MODEL_FILE"
grep -q '^fact: scripted-worker-test-fact$' "$MODEL_FILE" || fail "resident-model.md missing the expected fact entry"
grep -q "^asked: $QUESTION1\$" "$MODEL_FILE" || fail "resident-model.md entry does not cite the question it was asked from"
grep -q "^answered: $ANSWER1\$" "$MODEL_FILE" || fail "resident-model.md entry does not cite the answer record that closed it"

log "finding 3 regression (0009 review pass): castle answer must refuse a question id that doesn't resolve, before writing anything"
JOURNAL_COUNT_BEFORE="$(find "$CASTLE_STATE_DIR/journal" -name '*.md' | wc -l | tr -d ' ')"
if "$CASTLE" answer "20260101T000000Z-question-000000" "This should never be written." \
    >"$WORKDIR/bad-answer-missing-out" 2>"$WORKDIR/bad-answer-missing-err"; then
  fail "castle answer accepted an answer for a question id that does not exist"
fi
grep -q "no such record" "$WORKDIR/bad-answer-missing-err" || fail "castle answer's missing-record rejection message changed unexpectedly"
JOURNAL_COUNT_AFTER="$(find "$CASTLE_STATE_DIR/journal" -name '*.md' | wc -l | tr -d ' ')"
[ "$JOURNAL_COUNT_AFTER" -eq "$JOURNAL_COUNT_BEFORE" ] || fail "castle answer wrote a journal record even though the question it referenced does not exist"

log "finding 3 regression: castle answer must refuse a refs id that resolves but isn't type=question"
if "$CASTLE" answer "$REQ1" "This should also never be written." \
    >"$WORKDIR/bad-answer-wrongtype-out" 2>"$WORKDIR/bad-answer-wrongtype-err"; then
  fail "castle answer accepted an answer whose id resolved to a non-question record ($REQ1 is a request)"
fi
grep -q "not a question record" "$WORKDIR/bad-answer-wrongtype-err" || fail "castle answer's wrong-type rejection message changed unexpectedly"
JOURNAL_COUNT_AFTER_2="$(find "$CASTLE_STATE_DIR/journal" -name '*.md' | wc -l | tr -d ' ')"
[ "$JOURNAL_COUNT_AFTER_2" -eq "$JOURNAL_COUNT_BEFORE" ] || fail "castle answer wrote a journal record even though the id it referenced wasn't a question"

log "finding 3 regression: castle ask --refs must refuse a refs id that doesn't resolve, before writing anything"
if "$CASTLE" ask --refs "20260101T000000Z-request-000000" "This request should never be filed." \
    >"$WORKDIR/bad-ask-out" 2>"$WORKDIR/bad-ask-err"; then
  fail "castle ask accepted --refs pointing at a record that does not exist"
fi
grep -q "don't exist" "$WORKDIR/bad-ask-err" || fail "castle ask's --refs rejection message changed unexpectedly"
JOURNAL_COUNT_AFTER_3="$(find "$CASTLE_STATE_DIR/journal" -name '*.md' | wc -l | tr -d ' ')"
[ "$JOURNAL_COUNT_AFTER_3" -eq "$JOURNAL_COUNT_BEFORE" ] || fail "castle ask wrote a journal record even though --refs pointed at nothing"

log "finding 3 regression: the journal must still validate clean after every rejected write above"
"$CASTLE" validate || fail "journal failed to validate after finding-3's rejected writes — one of them left a partial or corrupt record behind"

log "finding 6 regression (0009 review pass): a field value containing a newline must be rejected, not silently corrupt the journal"
JOURNAL_COUNT_BEFORE_NL="$(find "$CASTLE_STATE_DIR/journal" -name '*.md' | wc -l | tr -d ' ')"
if "$CASTLE" record --type decision --provenance initiated --seat router --refs "$REQ1" \
    --evidence "$(printf 'line one\nline two')" \
    >"$WORKDIR/bad-newline-out" 2>"$WORKDIR/bad-newline-err"; then
  fail "castle record accepted an --evidence value containing a newline"
fi
grep -q "newline" "$WORKDIR/bad-newline-err" || fail "castle record's newline-rejection message changed unexpectedly"
JOURNAL_COUNT_AFTER_NL="$(find "$CASTLE_STATE_DIR/journal" -name '*.md' | wc -l | tr -d ' ')"
[ "$JOURNAL_COUNT_AFTER_NL" -eq "$JOURNAL_COUNT_BEFORE_NL" ] || fail "castle record wrote a journal file despite rejecting the newline-bearing value"
"$CASTLE" validate || fail "journal failed to validate after the rejected newline write — a partial file may have been left behind"

log "propensity fields: backward compatibility — a decision record written with neither considered nor propensity must still validate"
# The journal is append-only, so every decision record written before
# this schema addition existed is permanent and must stay valid
# forever (agent/README.md's "why these are optional, not required").
# castle record (unlike castle route) never sets considered/propensity
# on its own, so this is exactly that pre-existing shape, produced for
# real rather than hand-written as a fixture.
OLD_STYLE_DECISION="$("$CASTLE" record --type decision --provenance initiated --seat router --refs "$REQ1" \
  --evidence "backward-compatibility fixture: a decision with no considered/propensity fields, the pre-schema-addition shape")"
OLD_STYLE_DECISION_FILE="$CASTLE_STATE_DIR/journal/$OLD_STYLE_DECISION.md"
grep -q '^considered:' "$OLD_STYLE_DECISION_FILE" && fail "$OLD_STYLE_DECISION_FILE unexpectedly has a considered field — this fixture is supposed to lack one"
grep -q '^propensity:' "$OLD_STYLE_DECISION_FILE" && fail "$OLD_STYLE_DECISION_FILE unexpectedly has a propensity field — this fixture is supposed to lack one"
"$CASTLE" validate || fail "a decision record with neither considered nor propensity failed to validate — backward compatibility is broken"

log "propensity fields: validate must reject a present-but-malformed propensity, considered, or channel-not-in-considered value"
JOURNAL_COUNT_BEFORE_PROPENSITY="$(find "$CASTLE_STATE_DIR/journal" -name '*.md' | wc -l | tr -d ' ')"
# castle record has no --considered/--propensity flags (only castle
# route writes them), so a malformed value is planted by hand-writing a
# journal file directly — the same technique the router-bug regression
# above uses for FAKE_DECISION. validate must catch it independent of
# which code path produced the bad file.
BAD_PROPENSITY_FILE="$CASTLE_STATE_DIR/journal/20260101T000000Z-decision-bad0c1.md"
cat > "$BAD_PROPENSITY_FILE" <<EOF
---
id: 20260101T000000Z-decision-bad0c1
type: decision
provenance: initiated
refs: $REQ1
seat: router
created: 2026-01-01T00:00:00Z
evidence: propensity malformed-value regression fixture (propensity out of range)
considered: notify,digest
propensity: 1.5
---

Malformed propensity fixture: 1.5 is not in [0,1].
EOF
if "$CASTLE" validate >"$WORKDIR/bad-propensity-out" 2>"$WORKDIR/bad-propensity-err"; then
  fail "castle validate accepted a decision record with propensity=1.5 (out of [0,1])"
fi
grep -q "propensity" "$WORKDIR/bad-propensity-err" || fail "castle validate's propensity-range rejection message changed unexpectedly"
rm -f "$BAD_PROPENSITY_FILE"

BAD_CONSIDERED_FILE="$CASTLE_STATE_DIR/journal/20260101T000000Z-decision-bad0c2.md"
cat > "$BAD_CONSIDERED_FILE" <<EOF
---
id: 20260101T000000Z-decision-bad0c2
type: decision
provenance: initiated
refs: $REQ1
seat: router
created: 2026-01-01T00:00:00Z
evidence: propensity malformed-value regression fixture (considered empty)
considered:
propensity: 1.0
---

Malformed considered fixture: present but empty, not a non-empty flat list.
EOF
if "$CASTLE" validate >"$WORKDIR/bad-considered-out" 2>"$WORKDIR/bad-considered-err"; then
  fail "castle validate accepted a decision record with an empty considered field"
fi
grep -q "considered" "$WORKDIR/bad-considered-err" || fail "castle validate's considered rejection message changed unexpectedly"
rm -f "$BAD_CONSIDERED_FILE"

BAD_MEMBERSHIP_FILE="$CASTLE_STATE_DIR/journal/20260101T000000Z-decision-bad0c3.md"
cat > "$BAD_MEMBERSHIP_FILE" <<EOF
---
id: 20260101T000000Z-decision-bad0c3
type: decision
provenance: initiated
refs: $REQ1
seat: router
created: 2026-01-01T00:00:00Z
evidence: propensity malformed-value regression fixture (channel not in considered)
considered: digest
propensity: 1.0
channel: notify
---

Malformed membership fixture: the chosen channel isn't among what was considered.
EOF
if "$CASTLE" validate >"$WORKDIR/bad-membership-out" 2>"$WORKDIR/bad-membership-err"; then
  fail "castle validate accepted a decision record whose channel is not a member of its considered list"
fi
grep -q "not among 'considered'" "$WORKDIR/bad-membership-err" || fail "castle validate's channel-membership rejection message changed unexpectedly"
rm -f "$BAD_MEMBERSHIP_FILE"

"$CASTLE" validate || fail "journal failed to validate clean once all three malformed propensity fixtures were removed"
JOURNAL_COUNT_AFTER_PROPENSITY="$(find "$CASTLE_STATE_DIR/journal" -name '*.md' | wc -l | tr -d ' ')"
[ "$JOURNAL_COUNT_AFTER_PROPENSITY" -eq "$JOURNAL_COUNT_BEFORE_PROPENSITY" ] || fail "propensity malformed-value fixtures were not fully cleaned up"

log "castle correct: write-path discipline, the same finding-3 regressions cmd_ask/cmd_answer already guard against (docs/tasks/0010-correction-record.md)"
JOURNAL_COUNT_BEFORE_CORRECT="$(find "$CASTLE_STATE_DIR/journal" -name '*.md' | wc -l | tr -d ' ')"
if "$CASTLE" correct "" >"$WORKDIR/bad-correct-empty-out" 2>"$WORKDIR/bad-correct-empty-err"; then
  fail "castle correct accepted an empty body"
fi
grep -q "empty correction" "$WORKDIR/bad-correct-empty-err" || fail "castle correct's empty-body rejection message changed unexpectedly"
JOURNAL_COUNT_AFTER_CORRECT_EMPTY="$(find "$CASTLE_STATE_DIR/journal" -name '*.md' | wc -l | tr -d ' ')"
[ "$JOURNAL_COUNT_AFTER_CORRECT_EMPTY" -eq "$JOURNAL_COUNT_BEFORE_CORRECT" ] || fail "castle correct wrote a journal record despite an empty body"

if "$CASTLE" correct --refs "20260101T000000Z-request-000000" "This correction should never be filed." \
    >"$WORKDIR/bad-correct-refs-out" 2>"$WORKDIR/bad-correct-refs-err"; then
  fail "castle correct accepted --refs pointing at a record that does not exist"
fi
grep -q "don't exist" "$WORKDIR/bad-correct-refs-err" || fail "castle correct's --refs rejection message changed unexpectedly"
JOURNAL_COUNT_AFTER_CORRECT_REFS="$(find "$CASTLE_STATE_DIR/journal" -name '*.md' | wc -l | tr -d ' ')"
[ "$JOURNAL_COUNT_AFTER_CORRECT_REFS" -eq "$JOURNAL_COUNT_BEFORE_CORRECT" ] || fail "castle correct wrote a journal record even though --refs pointed at nothing"

"$CASTLE" validate || fail "journal failed to validate after castle correct's rejected writes"

log "castle correct: --refs pointing at a real record is accepted and survives round-trip"
CORRECTION_WITH_REFS="$("$CASTLE" correct --refs "$REQ1" "Round-trip check: this correction is about request $REQ1.")"
CORRECTION_WITH_REFS_FILE="$CASTLE_STATE_DIR/journal/$CORRECTION_WITH_REFS.md"
[ -f "$CORRECTION_WITH_REFS_FILE" ] || fail "castle correct --refs $REQ1 produced no journal record"
grep -q "^refs: $REQ1\$" "$CORRECTION_WITH_REFS_FILE" || fail "$CORRECTION_WITH_REFS_FILE did not carry the --refs id through to the written record"
"$CASTLE" validate || fail "journal failed to validate after a correction with a real --refs id"

log "router bug regression (docs/tasks/0009 item 7): a non-router decision referencing a result must not suppress routing"
REQ3="$("$CASTLE" ask --provenance initiated "Test errand gamma: only exists to exercise the router-bug regression test.")"
RES3="$("$CASTLE" record --type result --provenance initiated --seat worker --refs "$REQ3" --body "Errand gamma result, for the regression test only.")"
FAKE_DECISION="$("$CASTLE" record --type decision --provenance initiated --seat worker --refs "$RES3" --evidence "not a real router decision: seat=worker, not router — this is the exact shape docs/tasks/0009 item 7's bug fix guards against")"
log "  -> a decision from seat=worker (not router) now references $RES3: $FAKE_DECISION"
"$CASTLE" route
ROUTER_DECISIONS_FOR_RES3="$(grep -l "^refs: $RES3\$" "$CASTLE_STATE_DIR"/journal/*-decision-*.md | xargs grep -l '^seat: router$' || true)"
[ -n "$ROUTER_DECISIONS_FOR_RES3" ] || fail "router bug regressed: a non-router decision referencing $RES3 suppressed its routing — no router decision was appended for it"
grep -q '^channel: digest$' "$ROUTER_DECISIONS_FOR_RES3" || fail "errand gamma's result did not route to 'digest' (provenance=initiated): $ROUTER_DECISIONS_FOR_RES3"

log "filing-time context capture (docs/tasks/0010-correction-record.md scope 2), populated branch: a fresh notify-channel decision, then a correction citing it"
REQ4="$("$CASTLE" ask "Test errand delta: only exists to exercise filing-time context capture.")"
RES4="$("$CASTLE" record --type result --provenance requested --seat worker --refs "$REQ4" --body "Errand delta result, for the context-capture test only.")"
"$CASTLE" route
DECISION_FOR_RES4="$(grep -l "^refs: $RES4\$" "$CASTLE_STATE_DIR"/journal/*-decision-*.md | xargs grep -l '^channel: notify$' || true)"
[ -n "$DECISION_FOR_RES4" ] || fail "expected errand delta's result to route to notify (provenance=requested)"
DECISION_FOR_RES4_ID="$(basename "$DECISION_FOR_RES4" .md)"

CORRECTION1="$("$CASTLE" correct "Filing-time context test: you pinged me right after that last notification.")"
CORRECTION1_FILE="$CASTLE_STATE_DIR/journal/$CORRECTION1.md"
[ -f "$CORRECTION1_FILE" ] || fail "castle correct printed an id with no journal record at $CORRECTION1_FILE"
grep -q '^type: correction$' "$CORRECTION1_FILE" || fail "$CORRECTION1_FILE is not a correction record"
grep -q '^seat: intake$' "$CORRECTION1_FILE" || fail "$CORRECTION1_FILE should carry seat=intake, same as every other intake write"
grep -q '^provenance: requested$' "$CORRECTION1_FILE" || fail "$CORRECTION1_FILE should carry provenance=requested — a correction is resident speech through intake"
grep -q '^surface: cli$' "$CORRECTION1_FILE" || fail "$CORRECTION1_FILE should carry surface=cli"
# The most recent notify decision in the journal is, by construction,
# the one this correction's context should cite: ids are sortable
# timestamps, and DECISION_FOR_RES4 was just appended, so nothing
# newer exists yet.
grep -q "^context-last-notify: $DECISION_FOR_RES4_ID\$" "$CORRECTION1_FILE" || fail "$CORRECTION1_FILE's context-last-notify did not cite the freshest notify-channel decision ($DECISION_FOR_RES4_ID)"
NOTIFIES_1H="$(sed -n 's/^context-notifies-1h: //p' "$CORRECTION1_FILE")"
[ "${NOTIFIES_1H:-0}" -ge 1 ] || fail "$CORRECTION1_FILE's context-notifies-1h should be >= 1 (a notify decision was just filed), got '${NOTIFIES_1H:-}'"
NOTIFIES_24H="$(sed -n 's/^context-notifies-24h: //p' "$CORRECTION1_FILE")"
[ "${NOTIFIES_24H:-0}" -ge 1 ] || fail "$CORRECTION1_FILE's context-notifies-24h should be >= 1, got '${NOTIFIES_24H:-}'"
LOCAL_CREATED="$(sed -n 's/^context-local-created: //p' "$CORRECTION1_FILE")"
python3 -c "import datetime, sys; datetime.datetime.strptime(sys.argv[1], '%Y-%m-%dT%H:%M:%S%z')" "$LOCAL_CREATED" \
  || fail "$CORRECTION1_FILE's context-local-created ('$LOCAL_CREATED') does not parse as a timestamp carrying a UTC offset"
grep -q "^stated: $CORRECTION1\$" "$MODEL_FILE" || fail "resident-model.md is missing a volunteered entry citing correction $CORRECTION1"
grep -q '^provenance: volunteered$' "$MODEL_FILE" || fail "resident-model.md is missing a provenance: volunteered entry"

log "filing-time context capture, empty-journal branch: a correction filed where no router decision has ever existed"
EMPTY_CONTEXT_STATE="$(mktemp -d)"
EMPTY_CORRECTION="$(CASTLE_STATE_DIR="$EMPTY_CONTEXT_STATE" "$CASTLE" correct "Empty-journal context test: nothing has happened yet.")"
EMPTY_CORRECTION_FILE="$EMPTY_CONTEXT_STATE/journal/$EMPTY_CORRECTION.md"
[ -f "$EMPTY_CORRECTION_FILE" ] || fail "castle correct against an empty journal produced no record at $EMPTY_CORRECTION_FILE"
grep -q '^context-last-notify:' "$EMPTY_CORRECTION_FILE" && fail "$EMPTY_CORRECTION_FILE should carry no context-last-notify field at all when no notify decision exists"
grep -q '^context-notifies-1h: 0$' "$EMPTY_CORRECTION_FILE" || fail "$EMPTY_CORRECTION_FILE's context-notifies-1h should be 0 against an empty journal"
grep -q '^context-notifies-24h: 0$' "$EMPTY_CORRECTION_FILE" || fail "$EMPTY_CORRECTION_FILE's context-notifies-24h should be 0 against an empty journal"
CASTLE_STATE_DIR="$EMPTY_CONTEXT_STATE" "$CASTLE" validate || fail "the empty-journal correction did not validate cleanly"
rm -rf "$EMPTY_CONTEXT_STATE"

log "the router must never route a correction (docs/tasks/0010-correction-record.md scope 4): re-routing must leave $CORRECTION1 and $CORRECTION_WITH_REFS untouched"
NOTIFY_COUNT_BEFORE_CORRECTION_ROUTE="$(wc -l < "$CASTLE_NOTIFY_LOG" | tr -d ' ')"
DECISION_COUNT_BEFORE_CORRECTION_ROUTE="$(find "$CASTLE_STATE_DIR/journal" -name '*-decision-*.md' | wc -l | tr -d ' ')"
ROUTE_AFTER_CORRECTIONS_OUT="$("$CASTLE" route)"
echo "$ROUTE_AFTER_CORRECTIONS_OUT"
case "$ROUTE_AFTER_CORRECTIONS_OUT" in
  *"nothing unrouted"*) ;;
  *) fail "castle route routed something after only corrections were left unrouted: $ROUTE_AFTER_CORRECTIONS_OUT" ;;
esac
DECISION_COUNT_AFTER_CORRECTION_ROUTE="$(find "$CASTLE_STATE_DIR/journal" -name '*-decision-*.md' | wc -l | tr -d ' ')"
[ "$DECISION_COUNT_AFTER_CORRECTION_ROUTE" -eq "$DECISION_COUNT_BEFORE_CORRECTION_ROUTE" ] || fail "castle route appended a decision record after only corrections were unrouted — corrections must never be routed"
for CID in "$CORRECTION1" "$CORRECTION_WITH_REFS"; do
  DECISIONS_REFERENCING_CORRECTION="$(grep -l "^refs: $CID\$" "$CASTLE_STATE_DIR"/journal/*-decision-*.md 2>/dev/null || true)"
  [ -z "$DECISIONS_REFERENCING_CORRECTION" ] || fail "a decision record references correction $CID: $DECISIONS_REFERENCING_CORRECTION — corrections must never be routed"
done
NOTIFY_COUNT_AFTER_CORRECTION_ROUTE="$(wc -l < "$CASTLE_NOTIFY_LOG" | tr -d ' ')"
[ "$NOTIFY_COUNT_AFTER_CORRECTION_ROUTE" -eq "$NOTIFY_COUNT_BEFORE_CORRECTION_ROUTE" ] || fail "the notify stub fired again after filing corrections and re-routing — corrections must never trigger a notification"

log "digest: renders corrections too (scope 7) — verbatim first line and created time, at minimum"
DIGEST_OUT_2="$("$CASTLE" digest)"
echo "$DIGEST_OUT_2" | grep -q "## Corrections" || fail "digest output has no Corrections section even though corrections exist in the journal"
echo "$DIGEST_OUT_2" | grep -q "Filing-time context test: you pinged me right after that last notification." || fail "digest did not render correction $CORRECTION1's verbatim first line"
CORRECTION1_CREATED="$(sed -n 's/^created: //p' "$CORRECTION1_FILE")"
echo "$DIGEST_OUT_2" | grep -q "$CORRECTION1_CREATED" || fail "digest did not render correction $CORRECTION1's created time"

# A correction is rendered in exactly ONE place — its own section, never
# the errand fold. $CORRECTION_WITH_REFS was filed with --refs $REQ1, which
# is legal, so _collect_downstream's refs walk reaches it from that errand;
# without an explicit type filter it printed twice, contradicting both the
# Corrections preamble ("Not an errand") and cmd_digest's own docstring.
# Asserting only "the text appears somewhere" is what let that through, so
# assert the count and the section it lands in.
CORRECTION_WITH_REFS_HEADINGS="$(echo "$DIGEST_OUT_2" | grep -c "### correction $CORRECTION_WITH_REFS" || true)"
[ "$CORRECTION_WITH_REFS_HEADINGS" -eq 0 ] || fail "correction $CORRECTION_WITH_REFS (filed with --refs $REQ1) was folded into an errand as '### correction ...'; corrections belong only in the Corrections section"
CORRECTION_WITH_REFS_LINES="$(echo "$DIGEST_OUT_2" | grep -c "Round-trip check: this correction is about request" || true)"
[ "$CORRECTION_WITH_REFS_LINES" -eq 1 ] || fail "correction $CORRECTION_WITH_REFS rendered $CORRECTION_WITH_REFS_LINES times in the digest, expected exactly 1"

log "independent structural assertions, re-run over the final journal (evidence non-empty, nothing routed silently, no decision routes a correction)"
"$CHECK" "$CASTLE_STATE_DIR/journal"

if [ -n "${CASTLE_AGENT_LOOP_SUMMARY_OUT:-}" ]; then
  log "writing normalized journal summary to $CASTLE_AGENT_LOOP_SUMMARY_OUT (test/agent-loop/tenant-swap.sh)"
  "$NORMALIZE" "$CASTLE_STATE_DIR/journal" > "$CASTLE_AGENT_LOOP_SUMMARY_OUT"
fi

log "all assertions passed"
