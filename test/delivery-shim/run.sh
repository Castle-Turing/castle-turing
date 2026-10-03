#!/usr/bin/env bash
# test/delivery-shim/run.sh — the delivery record shim's harness
# (docs/tasks/0081-implement-the-delivery-record-shim.md).
#
# Every journal this runs against came out of the tenant's own writer on
# a real sprint. That is the point of the corpus and not an accident of
# how it was collected: a fixture written by hand encodes a belief about
# the schema, and a fixture written by emcee encodes the schema,
# including the quirks nobody would have thought to reproduce — a queued
# `README.md`, a `pr` record that lands before the step that opened it
# finishes, an attempt from before `model` became a required field.
# fixtures/README.md is the corpus's own account of itself: where each
# came from, which checklist shape it covers, and the one mechanical
# redaction applied to all of them.
#
# Plain bash and stdlib Python, like test/agent-loop and test/outcomes,
# so the stock CI runner needs nothing installed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SHIM="$REPO_ROOT/agent/castle-delivery-shim"
CASTLE="$REPO_ROOT/agent/castle"
FIX="$REPO_ROOT/test/delivery-shim/fixtures"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
ok() { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
die() { printf '  FAIL %s\n' "$1" >&2; exit 1; }

# A fresh castle journal per scenario. CASTLE_STATE_DIR is the same
# escape hatch test/agent-loop uses: a throwaway journal in a temp
# directory, never a real resident's state.
new_journal() {
  local dir="$WORK/state-$1"
  rm -rf "$dir"
  mkdir -p "$dir/journal"
  printf '%s' "$dir"
}

records_of() { ls "$1/journal" | wc -l | tr -d ' '; }
field() { sed -n "s/^$2: //p" "$1"; }

# ---------------------------------------------------------------------
echo "1. one errand folds to its claim and its result"
# castle-turing's own sprint of 2026-09-22, briefed by this repository's
# own docs/tasks — so this is the end-to-end case, not a stand-in.
STATE="$(new_journal pr)"
CASTLE_STATE_DIR="$STATE" "$SHIM" fold \
  --run-dir "$FIX/castle-turing/2026-09-22T09-09-47" \
  --tasks-dir "$REPO_ROOT/docs/tasks" > "$WORK/pr.out"

claim="$(grep -l '^type: claim' "$STATE"/journal/*.md | xargs grep -l '0076-widen-the-reachability-lint-to-its-claimed-coverage')"
[ -n "$claim" ] || die "no claim for 0076"
ok "a brief taken becomes a claim"

result="$(grep -l '^type: result' "$STATE"/journal/*.md | xargs grep -l '0076-widen-the-reachability-lint-to-its-claimed-coverage')"
[ -n "$result" ] || die "no result for 0076"
[ "$(field "$result" outcome)" = "completed" ] || die "outcome is not completed"
[ "$(field "$result" 'tenant-outcome')" = "pr_opened" ] || die "tenant-outcome is not pr_opened"
[ "$(field "$result" model)" = "claude-sonnet-5" ] || die "model not carried from the tenant's log"
[ "$(field "$result" provider)" = "claude" ] || die "provider not derived"
[ "$(field "$result" tenant)" = "emcee" ] || die "tenant not named"
grep -q '^pull-request: https://github.com/Castle-Turing/castle-turing/pull/139$' "$result" \
  || die "the pull request the seat opened is not on the result"
ok "a pull request opened becomes a result naming outcome, tenant, model and provider"

# The claim is written for the errand, the result for the same errand,
# and both carry the tenant's own event identity.
grep -q '^source-event: 0076-widen-the-reachability-lint-to-its-claimed-coverage@castle-turing/2026-09-22T09-09-47#3$' "$claim" \
  || die "the claim does not carry the tenant's per-event identity"
ok "each record carries the errand, the run and the tenant's own seq"

# ---------------------------------------------------------------------
echo "2. provenance is sourced on every record, and refs is empty on every record"
for f in "$STATE"/journal/*.md; do
  [ "$(field "$f" provenance)" = "requested" ] || die "$(basename "$f"): provenance not requested"
  src="$(field "$f" 'provenance-source')"
  [ -n "$src" ] || die "$(basename "$f"): provenance is not sourced"
  [ -f "$REPO_ROOT/docs/tasks/$src" ] || [ -f "$REPO_ROOT/docs/tasks/done/$src" ] \
    || die "$(basename "$f"): provenance-source $src names no brief"
  [ "$(field "$f" refs)" = "" ] || die "$(basename "$f"): refs is not empty"
done
ok "provenance reads back to a brief that exists; refs is left open (friction 2)"

# ---------------------------------------------------------------------
echo "3. a double run appends nothing"
before="$(records_of "$STATE")"
CASTLE_STATE_DIR="$STATE" "$SHIM" fold \
  --run-dir "$FIX/castle-turing/2026-09-22T09-09-47" \
  --tasks-dir "$REPO_ROOT/docs/tasks" > "$WORK/pr2.out"
after="$(records_of "$STATE")"
[ "$before" = "$after" ] || die "a replay appended $((after - before)) record(s)"
grep -q 'nothing new' "$WORK/pr2.out" || die "the replay did not say it found nothing new"
ok "the second pass over the same log writes nothing ($before records, unchanged)"

# ---------------------------------------------------------------------
echo "4. the hook is a doorbell, never the mail"
# The same fold, against a fresh journal, with a payload on stdin that
# lies about every fact it could lie about. If the records differ by one
# byte the shim read the payload, which is the one thing it must never do.
STATE_B="$(new_journal doorbell)"
printf '{"type":"step_started","step":"an-errand-that-never-existed","seq":9999,"model":"a-model-nobody-ran"}\n' \
  | CASTLE_STATE_DIR="$STATE_B" "$SHIM" fold \
      --run-dir "$FIX/castle-turing/2026-09-22T09-09-47" \
      --tasks-dir "$REPO_ROOT/docs/tasks" > "$WORK/doorbell.out"
[ "$(records_of "$STATE_B")" = "$after" ] || die "a lying payload changed what was written"
grep -q 'an-errand-that-never-existed' "$STATE_B"/journal/*.md && die "the payload reached a record"
ok "a hook payload that lies produces exactly the records the tenant's log describes"

# And the poll: the run above was invoked with no payload at all — no
# hook, no stdin, nothing but the log — and produced the same records.
# There is no second code path to test because the doorbell and the poll
# are the same command; that identity is the property.
# Compared field-by-field rather than file-by-file: `id` and `created`
# are stamped at write time and differ between any two runs by design.
summarise() { grep -h -E '^(type|source-event|outcome|tenant-outcome|model|provider|provenance): ' "$1"/journal/*.md | sort; }
diff <(summarise "$STATE") <(summarise "$STATE_B") > /dev/null \
  || die "the doorbell and the poll produced different records"
ok "a doorbell that never rings changes nothing the read finds"

# ---------------------------------------------------------------------
echo "5. a park folds to a blocking question carrying the tenant's own words"
# The tenant records its question as a file path. Paths are machine-local
# by construction, so the harness copies the run and rewrites that one
# absolute path to where the copy actually is; every other byte is the
# tenant's.
RUN="$WORK/dovetail/2026-09-05T01-45-45"
mkdir -p "$(dirname "$RUN")"
cp -r "$FIX/dovetail/2026-09-05T01-45-45" "$RUN"
python3 - "$RUN" <<'PY'
import json, pathlib, sys
run = pathlib.Path(sys.argv[1])
path = run / "journal.jsonl"
out = []
for line in path.read_text().splitlines():
    rec = json.loads(line)
    if rec.get("question_file"):
        rec["question_file"] = str(run / "parked" / pathlib.Path(rec["question_file"]).name)
    out.append(json.dumps(rec, sort_keys=True, separators=(",", ":")))
path.write_text("\n".join(out) + "\n")
PY
STATE_Q="$(new_journal park)"
CASTLE_STATE_DIR="$STATE_Q" "$SHIM" fold --run-dir "$RUN" \
  --tasks-dir "$FIX/dovetail-tasks" > "$WORK/park.out"
question="$(grep -l '^type: question' "$STATE_Q"/journal/*.md)"
[ -n "$question" ] || die "the park produced no question"
[ "$(field "$question" blocking)" = "true" ] || die "the question is not blocking"
[ "$(field "$question" 'tenant-session')" = "7adcf40c-5277-4f21-9c7c-83192daaa792" ] \
  || die "the question does not name the tenant's session"
grep -q 'Launch failure detection scope and mechanism' "$question" \
  || die "the resident cannot read the question the tenant actually asked"
ok "a park becomes a blocking question, verbatim, naming the tenant's session"

# The same park's step_finished is still a result: the *turn* ended, and
# the errand did not. Nothing in the fold claims otherwise.
grep -h '^tenant-outcome: parked$' "$STATE_Q"/journal/*.md > /dev/null \
  || die "the parked turn produced no result"
ok "the parked turn's own account is a result whose tenant-outcome says parked"

# ---------------------------------------------------------------------
echo "6. two attempts on one errand produce two records, not one"
# emcee's own sprint of 2026-08-20: 0007-greeting was parked, answered by
# the operator, and re-run in the same journal. Two step_started records
# for one errand — the case content-based dedup would collapse. The run
# is copied and its machine-local question path rewritten, exactly as
# case 5 does and for the same reason: the park's question must be
# sourceable, or its refusal (a behavior case 6b pins) would hide the
# per-errand-refusal property case 7 exists to test.
RUN_R="$WORK/emcee/2026-08-20"
mkdir -p "$(dirname "$RUN_R")"
cp -r "$FIX/emcee/2026-08-20" "$RUN_R"
python3 - "$RUN_R" <<'PY'
import json, pathlib, sys
run = pathlib.Path(sys.argv[1])
path = run / "journal.jsonl"
out = []
for line in path.read_text().splitlines():
    rec = json.loads(line)
    if rec.get("question_file"):
        rec["question_file"] = str(run / "parked" / pathlib.Path(rec["question_file"]).name)
    out.append(json.dumps(rec, sort_keys=True, separators=(",", ":")))
path.write_text("\n".join(out) + "\n")
PY
STATE_R="$(new_journal resume)"
set +e
CASTLE_STATE_DIR="$STATE_R" "$SHIM" fold --run-dir "$RUN_R" \
  --tasks-dir "$FIX/emcee-tasks" > "$WORK/resume.out" 2> "$WORK/resume.err"
rc=$?
set -e
[ "$rc" = "1" ] || die "a fold with refusals should exit 1, got $rc"
n="$(grep -c '0007-greeting' "$WORK/resume.out" || true)"
claims="$(grep -l '^type: claim' "$STATE_R"/journal/*.md | xargs grep -l '^errand: 0007-greeting$' | wc -l)"
[ "$claims" = "2" ] || die "expected 2 claims for the resumed errand, got $claims"
ok "one errand attempted twice produces two claims, keyed by the tenant's seq"

# ---------------------------------------------------------------------
echo "7. what cannot be sourced is refused, loudly, and nothing is written for it"
grep -q '0006-run-per-sprint: no brief' "$WORK/resume.err" \
  || die "an errand with no brief was not refused"
grep -h '^errand: 0006-run-per-sprint$' "$STATE_R"/journal/*.md > /dev/null \
  && die "a record was written for an errand whose provenance could not be sourced"
ok "no brief, no provenance, no record — and the refusal names the errand"

grep -q 'names no model for this attempt' "$WORK/resume.err" \
  || die "a result with no implementer was not refused"
grep -h '^tenant-outcome: pr_opened$' "$STATE_R"/journal/*.md > /dev/null \
  && die "a result was written without naming its implementer"
ok "a journal predating the tenant's required model field refuses its results"

# The refusals are per-errand: everything sourceable in the same journal
# still folded — the park's question is written, with the tenant's own
# words, despite two refusals on other errands in the same fold.
rquestion="$(grep -l '^type: question' "$STATE_R"/journal/*.md)" \
  || die "a refusal elsewhere in the journal suppressed a question it should not have"
grep -q 'address the operator by name' "$rquestion" \
  || die "the surviving question does not carry the tenant's own words"
ok "a refusal stops its own errand and nothing else"

# 6b. And the refusal the copy avoids is itself pinned: folding the
# fixture in place leaves its machine-local question path unreadable,
# which must refuse that event — named, retryable, nothing written —
# rather than write a placeholder the resident would answer into a
# stranded errand (the cross-vendor finding on the shim's first draft).
STATE_U="$(new_journal unreadable)"
set +e
CASTLE_STATE_DIR="$STATE_U" "$SHIM" fold --run-dir "$FIX/emcee/2026-08-20" \
  --tasks-dir "$FIX/emcee-tasks" > /dev/null 2> "$WORK/unreadable.err"
set -e
grep -q 'question file' "$WORK/unreadable.err" \
  || die "an unreadable question file was not refused by name"
grep -l '^type: question' "$STATE_U"/journal/*.md > /dev/null 2>&1 \
  && die "an unreadable question file still produced a question record"
ok "an unsourceable question refuses its own event and writes nothing"

# ---------------------------------------------------------------------
echo "8. giving up folds to a result that names the failure and its provider"
# emcee's own OpenCode stint of 2026-09-05: the tenant died on a
# provider error rather than finishing. It is also the one adapter that
# records its provider explicitly, so this covers both the give-up shape
# and the first of the two provider rules.
STATE_F="$(new_journal failed)"
CASTLE_STATE_DIR="$STATE_F" "$SHIM" fold --run-dir "$FIX/emcee/2026-09-05T13-22-37" \
  --tasks-dir "$FIX/emcee-tasks" > "$WORK/failed.out"
fresult="$(grep -l '^type: result' "$STATE_F"/journal/*.md)"
[ "$(field "$fresult" outcome)" = "failed" ] || die "a tenant error did not become a failed result"
[ "$(field "$fresult" 'tenant-outcome')" = "error" ] || die "tenant-outcome does not say error"
grep -q '^tenant-error: OpenCodeError:' "$fresult" \
  || die "the tenant's own account of the failure is not carried verbatim"
[ "$(field "$fresult" provider)" = "deepinfra" ] || die "the declared provider was not read"
[ "$(field "$fresult" 'provider-source')" = "tenant session_settings.provider" ] \
  || die "the provider's sourcing is not named"
ok "a give-up becomes a failed result carrying the tenant's error and its declared provider"

# ---------------------------------------------------------------------
echo "9. an attempt's facts belong to that attempt, not to the errand"
# SYNTHETIC — see fixtures/README.md. The corpus's one retry inside a
# single run predates the tenant making `model` required, so both of its
# results refuse and the misattribution this pins would be invisible. The
# fixture is that real journal with `model`/`model_source` added to its
# step_started records, differing between the two attempts, and nothing
# else changed.
STATE_A="$(new_journal attempts)"
set +e
CASTLE_STATE_DIR="$STATE_A" "$SHIM" fold --run-dir "$FIX/synthetic-retry/2026-08-20" \
  --tasks-dir "$FIX/emcee-tasks" > "$WORK/attempts.out" 2> "$WORK/attempts.err"
set -e
first="$(grep -l '^source-event: 0007-greeting@synthetic-retry/2026-08-20#14$' "$STATE_A"/journal/*.md)"
second="$(grep -l '^source-event: 0007-greeting@synthetic-retry/2026-08-20#19$' "$STATE_A"/journal/*.md)"
[ -n "$first" ] && [ -n "$second" ] || die "the two attempts did not both produce a result"
[ "$(field "$first" model)" = "claude-sonnet-5" ] || die "the first attempt's result names the wrong model"
[ "$(field "$second" model)" = "claude-haiku-4-5" ] || die "the second attempt's result names the wrong model"
[ "$(field "$first" 'tenant-outcome')" = "parked" ] || die "the first attempt's outcome moved"
[ "$(field "$second" 'tenant-outcome')" = "error" ] || die "the second attempt's outcome moved"
ok "two attempts on one errand each name their own model, not the last one seen"

# ---------------------------------------------------------------------
echo "10. the fold never waits on the doorbell's payload"
# The poll runs under a timer with no hook in sight, and inherits
# whatever stdin that timer had. A fold that reads stdin blocks there
# forever — the liveness half hanging on the payload it exists not to
# need. Proven by giving it a pipe nobody will ever close.
set +e
( sleep 45 ) | timeout 20 env CASTLE_STATE_DIR="$(new_journal stdin)" "$SHIM" fold \
  --run-dir "$FIX/castle-turing/2026-09-22T09-09-47" \
  --tasks-dir "$REPO_ROOT/docs/tasks" > "$WORK/stdin.out" 2>&1
rc=$?
set -e
[ "$rc" != "124" ] || die "the fold blocked on an stdin nobody closes"
grep -q ' claim ' "$WORK/stdin.out" || die "the fold wrote nothing with a pipe attached"
ok "an stdin nobody closes does not stop the fold"

# ---------------------------------------------------------------------
echo "11. concurrent folds do not both write the same event"
# The tenant fires its hook on a thread per record and serialises
# nothing, and a task's last records land milliseconds apart — so two
# folds at once is the ordinary case. Eight are started against one
# fresh journal here; the count must be what one fold produces.
STATE_C="$(new_journal concurrent)"
for _ in 1 2 3 4 5 6 7 8; do
  CASTLE_STATE_DIR="$STATE_C" "$SHIM" fold \
    --run-dir "$FIX/castle-turing/2026-09-22T09-09-47" \
    --tasks-dir "$REPO_ROOT/docs/tasks" > /dev/null 2>&1 &
done
wait
[ "$(records_of "$STATE_C")" = "$after" ] \
  || die "eight concurrent folds wrote $(records_of "$STATE_C") records, not $after"
ok "eight folds racing over one journal write what one fold writes"

# ---------------------------------------------------------------------
echo "12. a journal with no event identity refuses the whole pass"
STATE_N="$(new_journal noident)"
set +e
CASTLE_STATE_DIR="$STATE_N" "$SHIM" fold --run-dir "$FIX/no-identity" \
  --tasks-dir "$REPO_ROOT/docs/tasks" > "$WORK/noident.out" 2> "$WORK/noident.err"
rc=$?
set -e
[ "$rc" = "2" ] || die "a journal with no identity should refuse with 2, got $rc"
grep -q 'no stable per-event identity' "$WORK/noident.err" \
  || die "the refusal does not say what is missing"
[ "$(records_of "$STATE_N")" = "0" ] || die "records were written from an unidentifiable journal"
ok "no stable identity, no fold — the blocker surfaces instead of being papered"

# ---------------------------------------------------------------------
echo "13. everything written validates as a castle journal"
CASTLE_STATE_DIR="$STATE" python3 "$CASTLE" validate > "$WORK/validate.out" 2>&1 \
  || { cat "$WORK/validate.out"; die "the shim wrote records castle validate condemns"; }
CASTLE_STATE_DIR="$STATE_Q" python3 "$CASTLE" validate > /dev/null 2>&1 \
  || die "the blocking question does not validate"
ok "castle validate accepts the shim's records, including the blocking question"

# ---------------------------------------------------------------------
echo "14. the router can read them"
# The delivery seat's whole reason for writing records is that something
# downstream acts on them. notify-send is stubbed, as test/agent-loop
# stubs it, so the router's notify channel does not need a desktop.
mkdir -p "$WORK/bin"
printf '#!/bin/sh\nexit 0\n' > "$WORK/bin/notify-send"
chmod +x "$WORK/bin/notify-send"
PATH="$WORK/bin:$PATH" CASTLE_STATE_DIR="$STATE_Q" CASTLE_NOTIFY_SYNC=1 \
  python3 "$CASTLE" route > "$WORK/route.out" 2>&1 || true
grep -q 'notify' "$WORK/route.out" \
  || { cat "$WORK/route.out"; die "the router did not route the delivery records to notify"; }
ok "a sourced provenance routes the seat's blocking question to an interruption"

# ---------------------------------------------------------------------
echo "15. the outcome row refuses a checkout that is not the errand's branch"
set +e
"$SHIM" row --run-dir "$FIX/castle-turing/2026-09-22T09-09-47" \
  --task 0076-widen-the-reachability-lint-to-its-claimed-coverage \
  --checkout "$REPO_ROOT" --env e2 > "$WORK/row.out" 2> "$WORK/row.err"
rc=$?
set -e
[ "$rc" = "2" ] || die "row against the wrong branch should refuse with 2, got $rc"
grep -q 'refusing to mature' "$WORK/row.err" || die "the row refusal says nothing"
ok "a row matured on the wrong branch is a mechanical failure, not a caveat"

# =====================================================================
# THE INBOUND HALF — an answered delivery question resumes the errand
# (docs/tasks/0082-an-answered-delivery-question-resumes-the-errand.md)
#
# Everything below runs against a real captured park, answered through
# `castle answer`, with a stub standing in for the tenant's resume verb.
# The stub is deliberate and it is not a mock of the property these
# checks turn on: what they test is the shim's accounting — which answers
# are eligible, that a claim names the one it spends, that a replay
# spends nothing — and a stub is the only way to make an invocation *die*
# on purpose. The tenant's own side of the boundary is demonstrated
# against its real verb by `tenant-boundary.sh`, and the capture that run
# produced is what check 25 reads.
# ---------------------------------------------------------------------

# One tenant run directory, copied out of the corpus with its one
# machine-local path rewritten, at whatever stamp the caller names. The
# stamp is a directory name and nothing else — `run_key` reads it, so two
# copies of one captured journal give one castle journal two delivery
# questions, which is what the two-answers check needs and what no single
# captured run in the corpus carries.
stage_run() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  rm -rf "$dest"
  cp -r "$src" "$dest"
  python3 - "$dest" <<'PY'
import json, pathlib, sys
run = pathlib.Path(sys.argv[1])
path = run / "journal.jsonl"
out = []
for line in path.read_text().splitlines():
    rec = json.loads(line)
    if rec.get("question_file"):
        rec["question_file"] = str(run / "parked" / pathlib.Path(rec["question_file"]).name)
    out.append(json.dumps(rec, sort_keys=True, separators=(",", ":")))
path.write_text("\n".join(out) + "\n")
PY
}

# A disposable repository for the tenant's resume verb to be pointed at.
# Never the checkout this test runs in: `--repo` is where the tenant would
# do work, and a test must not hand it one.
stage_repo() {
  local dest="$1"
  mkdir -p "$dest/docs/tasks"
  cp "$FIX"/dovetail-tasks/*.md "$dest/docs/tasks/"
  git -C "$dest" init -q -b main
  git -C "$dest" -c user.email=t@example.invalid -c user.name=t add -A
  git -C "$dest" -c user.email=t@example.invalid -c user.name=t commit -qm briefs
}

# A stub tenant that records the argv it was handed and exits as told. The
# argv matters: the three arguments the shim appends are what say *which*
# park is being resumed, and a shim that dropped one would resume the
# wrong run — or whichever run the tenant calls latest — with nothing to
# say so.
stage_tenant() {
  local path="$1" code="$2"
  {
    printf '#!/bin/sh\n'
    printf 'printf "%%s\\n" "$@" > %s.argv\n' "$path"
    printf 'exit %s\n' "$code"
  } > "$path"
  chmod +x "$path"
}

question_id() {
  basename "$(grep -l '^type: question' "$1"/journal/*.md | head -1)" .md
}

answer_id() {  # the answer record naming this question
  basename "$(grep -l "^refs: $2$" "$1"/journal/*-answer-*.md)" .md
}

REPO_D="$WORK/target"
stage_repo "$REPO_D"
PARK="$FIX/dovetail/2026-09-05T01-45-45"
stage_tenant "$WORK/tenant" 0

# ---------------------------------------------------------------------
echo "16. an unanswered delivery question resumes nothing"
RUN_A="$WORK/runs/dovetail/2026-09-05T01-45-45"
stage_run "$PARK" "$RUN_A"
STATE_I="$(new_journal inbound)"
CASTLE_STATE_DIR="$STATE_I" "$SHIM" fold --run-dir "$RUN_A" \
  --tasks-dir "$FIX/dovetail-tasks" > /dev/null
folded="$(records_of "$STATE_I")"
CASTLE_STATE_DIR="$STATE_I" CASTLE_DELIVERY_RESUME_COMMAND="$WORK/tenant" \
  "$SHIM" resume --run-dir "$RUN_A" --repo "$REPO_D" > "$WORK/r0.out" 2>&1
[ "$(records_of "$STATE_I")" = "$folded" ] || die "an unanswered question was claimed"
[ ! -f "$WORK/tenant.argv" ] || die "an unanswered question invoked the tenant"
grep -q 'nothing to resume' "$WORK/r0.out" || die "the pass did not say it found nothing"
ok "no answer, no claim, no invocation — and the pass says so"

# ---------------------------------------------------------------------
echo "17. one answer produces exactly one resumption, and its claim cites it"
Q_A="$(question_id "$STATE_I")"
CASTLE_STATE_DIR="$STATE_I" python3 "$CASTLE" answer "$Q_A" \
  'Option B: the same budget the float step uses for its wait. Fix both paths.' > /dev/null
A_A="$(answer_id "$STATE_I" "$Q_A")"
CASTLE_STATE_DIR="$STATE_I" CASTLE_DELIVERY_RESUME_COMMAND="$WORK/tenant" \
  "$SHIM" resume --run-dir "$RUN_A" --repo "$REPO_D" --tasks-dir "$FIX/dovetail-tasks" \
  > "$WORK/r1.out" 2>&1
rclaim="$(grep -l "^resumes: $A_A$" "$STATE_I"/journal/*-claim-*.md || true)"
[ -n "$rclaim" ] || die "the answer was not claimed, so nothing spent it"
[ "$(printf '%s\n' "$rclaim" | wc -l)" = "1" ] || die "one answer produced more than one claim"
[ "$(field "$rclaim" refs)" = "$A_A,$Q_A" ] \
  || die "the claim's refs do not name the answer, then the question"
[ "$(field "$rclaim" 'resumed-by')" = "shim" ] || die "the claim does not say who resumed"
[ "$(field "$rclaim" errand)" = "README" ] || die "the claim does not name the errand"
[ "$(field "$rclaim" 'tenant-run')" = "dovetail/2026-09-05T01-45-45" ] \
  || die "the claim does not name the tenant's run"
ok "the answer is spent by exactly one claim, and refs chains it to the answer"

# The ordering's other half: reaching the tenant at all is only possible
# with a claim already on disk, so the argv below is the proof.
[ -f "$WORK/tenant.argv" ] || die "the tenant's resume verb was never invoked"
grep -qx -- "--run" "$WORK/tenant.argv" || die "the invocation does not name the run"
grep -qx -- "$RUN_A" "$WORK/tenant.argv" || die "the invocation names the wrong run"
grep -qx -- "$REPO_D" "$WORK/tenant.argv" || die "the invocation names the wrong repository"
grep -qx -- "$FIX/dovetail-tasks" "$WORK/tenant.argv" || die "the invocation drops --tasks"
ok "the verb is handed the run, the repository and the briefs — never a default"

# ---------------------------------------------------------------------
echo "18. the answer reaches the tenant verbatim"
# Byte-compared against the record, not grepped for a phrase. No seat
# paraphrases the resident, and this is the only place in the inbound path
# where a paraphrase would have nothing to catch it: the tenant injects
# this section into the resumed attempt's prompt, and the attempt has no
# other copy to compare it against.
python3 - "$STATE_I/journal/$A_A.md" "$RUN_A/parked/README.md" <<'PY'
import pathlib, re, sys
record, parked = (pathlib.Path(p).read_text() for p in sys.argv[1:3])
body = record.split("---\n", 2)[2].strip()
section = re.search(r"^##[^\S\n]+Answer[^\S\n]*$(.*?)(?=^##[^\S\n]+|\Z)",
                    parked, re.M | re.S).group(1)
section = re.sub(r"<!--.*?-->", "", section, flags=re.S).strip()
if section != body:
    raise SystemExit(f"the tenant's answer is not the record's body:\n{section!r}\n{body!r}")
PY
ok "the tenant's answer section is the answer record's body, byte for byte"
grep -q "^Answered-by: agent:castle-delivery-shim for the resident (castle record $A_A)$" \
  "$RUN_A/parked/README.md" \
  || die "the tenant would refuse this answer for having no provenance"
ok "Answered-by says an agent transcribed it, and cites the record"

# ---------------------------------------------------------------------
echo "19. a replay of the same answer produces none"
before="$(records_of "$STATE_I")"
rm -f "$WORK/tenant.argv"
CASTLE_STATE_DIR="$STATE_I" CASTLE_DELIVERY_RESUME_COMMAND="$WORK/tenant" \
  "$SHIM" resume --run-dir "$RUN_A" --repo "$REPO_D" > "$WORK/r2.out" 2>&1
[ "$(records_of "$STATE_I")" = "$before" ] || die "a replay claimed the same answer twice"
[ ! -f "$WORK/tenant.argv" ] || die "a replay invoked the tenant again"
ok "the second pass over a spent answer writes nothing and invokes nothing"

# ---------------------------------------------------------------------
echo "20. two answers closing two questions produce two resumptions"
# Both answers are filed before either is spent, and that ordering is the
# check rather than an incidental detail: a fold with no run-scoping at all
# passes a version of this that resumes run A first, because A's answer is
# already spent by the time the run-B pass could leak onto it. Here neither
# is, so a pass over run B that reaches run A's answer spends it — against
# run B's own park, since both runs are copies of one capture and the
# errand's name is the same in each.
#
# The second run is that same captured journal at a second stamp: the
# corpus carries no single run with two parks, and a stamp is a directory
# name this harness already rewrites. What it buys is one castle journal
# holding two delivery questions, which is where run-scoping can be wrong.
RUN_B="$WORK/runs/dovetail/2026-09-05T02-11-00"
stage_run "$PARK" "$RUN_B"
STATE_T="$(new_journal tworuns)"
for r in "$RUN_A" "$RUN_B"; do
  CASTLE_STATE_DIR="$STATE_T" "$SHIM" fold --run-dir "$r" \
    --tasks-dir "$FIX/dovetail-tasks" > /dev/null
done
Q_A2="$(basename "$(grep -l '^source-event: README@dovetail/2026-09-05T01-45-45#23$' \
  "$STATE_T"/journal/*-question-*.md)" .md)"
Q_B="$(basename "$(grep -l '^source-event: README@dovetail/2026-09-05T02-11-00#23$' \
  "$STATE_T"/journal/*-question-*.md)" .md)"
[ "$Q_A2" != "$Q_B" ] || die "two runs folded to one question"
CASTLE_STATE_DIR="$STATE_T" python3 "$CASTLE" answer "$Q_A2" 'Both paths.' > /dev/null
CASTLE_STATE_DIR="$STATE_T" python3 "$CASTLE" answer "$Q_B" 'Only the socket path.' > /dev/null
A_A2="$(answer_id "$STATE_T" "$Q_A2")"
A_B="$(answer_id "$STATE_T" "$Q_B")"

rm -f "$WORK/tenant.argv"
CASTLE_STATE_DIR="$STATE_T" CASTLE_DELIVERY_RESUME_COMMAND="$WORK/tenant" \
  "$SHIM" resume --run-dir "$RUN_B" --repo "$REPO_D" > "$WORK/r3.out" 2>&1
[ "$(grep -l "^resumes: $A_B$" "$STATE_T"/journal/*-claim-*.md | wc -l)" = "1" ] \
  || die "the run B answer did not produce exactly one claim"
[ "$(grep -l "^resumes: $A_A2$" "$STATE_T"/journal/*-claim-*.md 2>/dev/null | wc -l)" = "0" ] \
  || die "a pass over run B spent run A's answer"
grep -qx -- "$RUN_B" "$WORK/tenant.argv" || die "the resumption named the wrong run"
ok "a pass over one run leaves another run's answer alone"

rm -f "$WORK/tenant.argv"
CASTLE_STATE_DIR="$STATE_T" CASTLE_DELIVERY_RESUME_COMMAND="$WORK/tenant" \
  "$SHIM" resume --run-dir "$RUN_A" --repo "$REPO_D" > "$WORK/r4.out" 2>&1
[ "$(grep -l "^resumes: $A_A2$" "$STATE_T"/journal/*-claim-*.md | wc -l)" = "1" ] \
  || die "the run A answer did not produce exactly one claim"
grep -qx -- "$RUN_A" "$WORK/tenant.argv" || die "the second resumption named the wrong run"
ok "two answers, two claims, each invocation scoped to its own run"

# ---------------------------------------------------------------------
echo "21. claim-without-invoke recovers without double-spending"
# The crash window the write-ahead ordering leaves open: the claim is
# durable and the invocation died. A stub that exits non-zero is exactly
# that, and it is the one thing no real verb can be asked to do on demand.
RUN_C="$WORK/runs/dovetail/2026-09-05T03-22-00"
stage_run "$PARK" "$RUN_C"
STATE_X="$(new_journal crashwindow)"
CASTLE_STATE_DIR="$STATE_X" "$SHIM" fold --run-dir "$RUN_C" \
  --tasks-dir "$FIX/dovetail-tasks" > /dev/null
Q_C="$(question_id "$STATE_X")"
CASTLE_STATE_DIR="$STATE_X" python3 "$CASTLE" answer "$Q_C" 'Both paths.' > /dev/null
A_C="$(answer_id "$STATE_X" "$Q_C")"
stage_tenant "$WORK/dead-tenant" 137
set +e
CASTLE_STATE_DIR="$STATE_X" CASTLE_DELIVERY_RESUME_COMMAND="$WORK/dead-tenant" \
  "$SHIM" resume --run-dir "$RUN_C" --repo "$REPO_D" > "$WORK/crash.out" 2>&1
rc=$?
set -e
[ "$rc" != "0" ] || die "a dead invocation reported success"
grep -q 'exited 137' "$WORK/crash.out" || die "the tenant's exit status was not reported"
claimed="$(records_of "$STATE_X")"
[ "$(grep -l "^resumes: $A_C$" "$STATE_X"/journal/*-claim-*.md | wc -l)" = "1" ] \
  || die "the crashed pass left no claim, so the answer would be spent twice"
ok "the claim is durable even when the invocation is not"

# Inside the grace interval nothing is re-invoked: a verb that is still
# starting up must not be thrashed by a poll.
rm -f "$WORK/tenant.argv"
CASTLE_STATE_DIR="$STATE_X" CASTLE_DELIVERY_RESUME_COMMAND="$WORK/tenant" \
  "$SHIM" resume --run-dir "$RUN_C" --repo "$REPO_D" --grace-seconds 3600 \
  > "$WORK/grace.out" 2>&1
[ ! -f "$WORK/tenant.argv" ] || die "a fresh claim was re-invoked inside its grace interval"
ok "a claim inside its grace interval is left alone"

# Past it, with the tenant still showing the errand parked, re-invoking is
# legal — and writes no second claim.
rm -f "$WORK/tenant.argv"
CASTLE_STATE_DIR="$STATE_X" CASTLE_DELIVERY_RESUME_COMMAND="$WORK/tenant" \
  "$SHIM" resume --run-dir "$RUN_C" --repo "$REPO_D" --grace-seconds 0 \
  > "$WORK/recover.out" 2>&1
[ -f "$WORK/tenant.argv" ] || die "the recovery pass never re-invoked the verb"
grep -q "recover README $A_C" "$WORK/recover.out" || die "the recovery pass says nothing"
[ "$(records_of "$STATE_X")" = "$claimed" ] || die "the recovery pass wrote a second claim"
ok "past the grace interval it re-invokes, and the answer stays spent exactly once"

# ---------------------------------------------------------------------
echo "22. what cannot be resumed is refused, and nothing is claimed for it"
RUN_D="$WORK/runs/dovetail/2026-09-05T04-33-00"
stage_run "$PARK" "$RUN_D"
STATE_M="$(new_journal missingpark)"
CASTLE_STATE_DIR="$STATE_M" "$SHIM" fold --run-dir "$RUN_D" \
  --tasks-dir "$FIX/dovetail-tasks" > /dev/null
Q_D="$(question_id "$STATE_M")"
CASTLE_STATE_DIR="$STATE_M" python3 "$CASTLE" answer "$Q_D" 'Answered.' > /dev/null
rm -rf "$RUN_D/parked"
folded="$(records_of "$STATE_M")"
rm -f "$WORK/tenant.argv"
set +e
CASTLE_STATE_DIR="$STATE_M" CASTLE_DELIVERY_RESUME_COMMAND="$WORK/tenant" \
  "$SHIM" resume --run-dir "$RUN_D" --repo "$REPO_D" > "$WORK/missing.out" 2> "$WORK/missing.err"
rc=$?
set -e
[ "$rc" = "1" ] || die "a refusal should exit 1, got $rc"
grep -q 'has no question file' "$WORK/missing.err" || die "the refusal does not say what is missing"
[ "$(records_of "$STATE_M")" = "$folded" ] || die "a claim was written for a park that is gone"
[ ! -f "$WORK/tenant.argv" ] || die "the verb was invoked for a park that is gone"
ok "no park, no claim, no invocation — an impossible resumption is refused, not recorded"

# ---------------------------------------------------------------------
echo "23. an answer that did not come through the resident's own intake buys nothing"
RUN_E="$WORK/runs/dovetail/2026-09-05T05-44-00"
stage_run "$PARK" "$RUN_E"
STATE_P="$(new_journal impostor)"
CASTLE_STATE_DIR="$STATE_P" "$SHIM" fold --run-dir "$RUN_E" \
  --tasks-dir "$FIX/dovetail-tasks" > /dev/null
Q_E="$(question_id "$STATE_P")"
CASTLE_STATE_DIR="$STATE_P" python3 "$CASTLE" record --type answer \
  --provenance requested --seat worker --refs "$Q_E" \
  --body 'A tenant answering its own question.' > /dev/null
folded="$(records_of "$STATE_P")"
rm -f "$WORK/tenant.argv"
CASTLE_STATE_DIR="$STATE_P" CASTLE_DELIVERY_RESUME_COMMAND="$WORK/tenant" \
  "$SHIM" resume --run-dir "$RUN_E" --repo "$REPO_D" > "$WORK/impostor.out" 2>&1
grep -q 'nothing to resume' "$WORK/impostor.out" || die "a non-intake answer was spent"
[ "$(records_of "$STATE_P")" = "$folded" ] || die "a non-intake answer produced a claim"
[ ! -f "$WORK/tenant.argv" ] || die "a non-intake answer invoked the tenant"
ok "only an answer written the way file_answer writes one can buy a resumption"

# ---------------------------------------------------------------------
echo "24. a second answer to one park cannot buy a second resumption"
# `file_answer` refuses a second answer to a question, so this shape only
# arrives through the `castle record --type answer` back door — and it
# must not silently pick one. The tenant reads a single answer section;
# choosing between two would be a judgment this seat does not have.
rm -f "$WORK/tenant.argv"
CASTLE_STATE_DIR="$STATE_I" python3 "$CASTLE" record --type answer \
  --provenance requested --seat intake --refs "$Q_A" \
  --body 'And actually, do the opposite.' > /dev/null
before="$(records_of "$STATE_I")"
set +e
CASTLE_STATE_DIR="$STATE_I" CASTLE_DELIVERY_RESUME_COMMAND="$WORK/tenant" \
  "$SHIM" resume --run-dir "$RUN_A" --repo "$REPO_D" \
  > "$WORK/second.out" 2> "$WORK/second.err"
rc=$?
set -e
[ "$rc" = "1" ] || die "a second answer on one park should refuse with 1, got $rc"
grep -q 'has already bought a resumption' "$WORK/second.err" \
  || die "the refusal does not say what already spent this park"
[ "$(records_of "$STATE_I")" = "$before" ] || die "a second answer on one park was claimed"
[ ! -f "$WORK/tenant.argv" ] || die "a second answer on one park invoked the tenant"
ok "one park, one answer — a second refuses rather than overwriting the first"

# ---------------------------------------------------------------------
echo "25. an errand the operator already relaunched is recorded, not resumed again"
RUN_F="$WORK/runs/dovetail/2026-09-05T06-55-00"
stage_run "$PARK" "$RUN_F"
STATE_H="$(new_journal byhand)"
CASTLE_STATE_DIR="$STATE_H" "$SHIM" fold --run-dir "$RUN_F" \
  --tasks-dir "$FIX/dovetail-tasks" > /dev/null
Q_F="$(question_id "$STATE_H")"
CASTLE_STATE_DIR="$STATE_H" python3 "$CASTLE" answer "$Q_F" 'Answered.' > /dev/null
A_F="$(answer_id "$STATE_H" "$Q_F")"
# The tenant's own durable statement that this park is no longer open —
# the line `emcee resume` writes before it selects the task.
sed -i 's/^Status: open$/Status: resolved/' "$RUN_F/parked/README.md"
rm -f "$WORK/tenant.argv"
CASTLE_STATE_DIR="$STATE_H" CASTLE_DELIVERY_RESUME_COMMAND="$WORK/tenant" \
  "$SHIM" resume --run-dir "$RUN_F" --repo "$REPO_D" > "$WORK/byhand.out" 2>&1
obs="$(grep -l "^resumes: $A_F$" "$STATE_H"/journal/*-claim-*.md)"
[ "$(field "$obs" 'resumed-by')" = "operator" ] \
  || die "a resumption the operator made is attributed to the shim"
[ ! -f "$WORK/tenant.argv" ] || die "an already-resumed errand was resumed a second time"
ok "the answer is recorded spent by the operator's own relaunch, and nothing is invoked"

# ---------------------------------------------------------------------
echo "26. the tenant's real resume verb, as captured from the live exercise"
# EVIDENCE, not a live run — `tenant-boundary.sh` is the live one and it
# needs the tenant installed. What this checks is that the recorded run
# says what the write-ahead ordering relies on, and that this shim's
# reading of a tenant-written question file agrees with the tenant's.
RESUMED="$FIX/resumed/dovetail/2026-09-05T01-45-45"
python3 - "$RESUMED/journal.jsonl" <<'PY'
import json, pathlib, sys
recs = [json.loads(l) for l in pathlib.Path(sys.argv[1]).read_text().splitlines()]
answered = [r for r in recs if r["type"] == "answered"]
assert len(answered) == 1, f"expected one `answered` record, got {len(answered)}"
assert answered[0]["answered_by"].startswith("agent:castle-delivery-shim"), \
    "the tenant did not read the shim's own Answered-by"
park = next(r["seq"] for r in recs if r["type"] == "parked")
after = [r for r in recs if r["seq"] > park and r["type"] == "step_started"
         and r.get("step") == "README"]
assert len(after) == 1, f"the errand did not re-run exactly once: {after}"
# The re-invocation: the last `runner_started` in the file dispatched
# nothing, which is the whole of the idempotence property the write-ahead
# ordering and the recovery path both rely on.
last_start = max(r["seq"] for r in recs if r["type"] == "runner_started")
assert not [r for r in recs if r["seq"] > last_start and r["type"] == "step_started"], \
    "re-invoking the verb on a resolved park dispatched a task"
held = [r for r in recs if r["seq"] > last_start and r["type"] == "sentinel_held"]
assert held and held[0]["reason"] == "nothing_dispatched", \
    "the re-invocation did not record that it had nothing to read"
PY
ok "the captured run resumed the errand once, and re-invoking it dispatched nothing"

# The shim's own reader, against a question file the tenant itself wrote
# and then resolved. A live check on this repository's code: if the pinned
# header spelling ever drifts, an answer stops being visible to the tenant
# and this is what says so.
python3 - "$SHIM" "$RESUMED/parked/README.md" <<'PY'
import importlib.machinery, importlib.util, pathlib, sys
loader = importlib.machinery.SourceFileLoader("shim", sys.argv[1])
spec = importlib.util.spec_from_file_location("shim", sys.argv[1], loader=loader)
shim = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shim)
parked = shim.read_parked(pathlib.Path(sys.argv[2]))
assert parked is not None and parked.task == "README", "the errand is not readable"
assert not parked.is_open, "a resolved park reads as still open"
assert parked.is_answered, "the answer the shim wrote reads as absent"
assert parked.answered_by.startswith("agent:castle-delivery-shim"), parked.answered_by
PY
ok "the shim reads a tenant-written park exactly as the tenant does"

# ---------------------------------------------------------------------
echo "27. a stranded delivery question is a reported defect, not a quiet day"
# The detector task 0082 owes, and the rule
# docs/backlog/nothing-sweeps-the-pipeline-invariants.md gains. Ages come
# off the records, so the cutoff is moved rather than the fixture aged: a
# committed fixture cannot get older.
STATE_S="$(new_journal stranded)"
CASTLE_STATE_DIR="$STATE_S" "$SHIM" fold --run-dir "$RUN_A" \
  --tasks-dir "$FIX/dovetail-tasks" > /dev/null
Q_S="$(question_id "$STATE_S")"
CASTLE_STATE_DIR="$STATE_S" "$SHIM" stranded --older-than-days 3 > "$WORK/s0.out"
grep -q '^ok: 1 delivery question' "$WORK/s0.out" || die "a fresh park was reported stranded"
ok "a park minutes old is work in progress, not a defect"

set +e
CASTLE_STATE_DIR="$STATE_S" "$SHIM" stranded --older-than-days 0 > "$WORK/s1.out"
rc=$?
set -e
[ "$rc" = "1" ] || die "a stranded question should exit 1, got $rc"
grep -q 'with no answer' "$WORK/s1.out" || die "an unanswered park is not reported"
ok "an unanswered park past the cutoff is reported, and says nothing has closed it"

CASTLE_STATE_DIR="$STATE_S" python3 "$CASTLE" answer "$Q_S" 'Answered.' > /dev/null
set +e
CASTLE_STATE_DIR="$STATE_S" "$SHIM" stranded --older-than-days 0 > "$WORK/s2.out"
rc=$?
set -e
[ "$rc" = "1" ] || die "an unspent answer should exit 1, got $rc"
grep -q 'no claim names that answer' "$WORK/s2.out" \
  || die "an answered-but-unspent question is not reported as the machinery's defect"
grep -q 'castle-delivery-shim resume' "$WORK/s2.out" \
  || die "the report does not name what should have spent it"
ok "an answer nothing spent indicts the watcher, and the report names it"

rm -f "$WORK/tenant.argv"
CASTLE_STATE_DIR="$STATE_S" CASTLE_DELIVERY_RESUME_COMMAND="$WORK/tenant" \
  "$SHIM" resume --run-dir "$RUN_A" --repo "$REPO_D" > /dev/null 2>&1
CASTLE_STATE_DIR="$STATE_S" "$SHIM" stranded --older-than-days 0 > "$WORK/s3.out"
grep -q '^ok: 1 delivery question' "$WORK/s3.out" \
  || { cat "$WORK/s3.out"; die "a spent answer is still reported as stranded"; }
ok "once the claim exists the question has a resumption path and is not reported"

# ---------------------------------------------------------------------
echo "28. the resumption's records validate, and so do the captured run's"
CASTLE_STATE_DIR="$STATE_I" python3 "$CASTLE" validate > "$WORK/ivalidate.out" 2>&1 \
  || { cat "$WORK/ivalidate.out"; die "the inbound half wrote records castle validate condemns"; }
ok "castle validate accepts a resumption claim whose refs name an answer"

python3 "$CASTLE" validate --journal "$FIX/resumed/records" > "$WORK/fvalidate.out" 2>&1 \
  || { cat "$WORK/fvalidate.out"; die "the captured run's records do not validate"; }
ok "the captured run's own records validate as a castle journal"

echo
echo "$pass checks passed"
echo
echo "The tenant boundary above is read from the capture in fixtures/resumed/."
echo "test/delivery-shim/tenant-boundary.sh is the live exercise that produced"
echo "it, and needs the tenant installed; it is not part of this run."
