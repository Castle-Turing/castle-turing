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
# for one errand — the case content-based dedup would collapse.
STATE_R="$(new_journal resume)"
set +e
CASTLE_STATE_DIR="$STATE_R" "$SHIM" fold --run-dir "$FIX/emcee/2026-08-20" \
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
# still folded.
grep -l '^type: question' "$STATE_R"/journal/*.md > /dev/null \
  || die "a refusal elsewhere in the journal suppressed a question it should not have"
ok "a refusal stops its own errand and nothing else"

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
echo "9. a journal with no event identity refuses the whole pass"
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
echo "10. everything written validates as a castle journal"
CASTLE_STATE_DIR="$STATE" python3 "$CASTLE" validate > "$WORK/validate.out" 2>&1 \
  || { cat "$WORK/validate.out"; die "the shim wrote records castle validate condemns"; }
CASTLE_STATE_DIR="$STATE_Q" python3 "$CASTLE" validate > /dev/null 2>&1 \
  || die "the blocking question does not validate"
ok "castle validate accepts the shim's records, including the blocking question"

# ---------------------------------------------------------------------
echo "11. the router can read them"
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
echo "12. the outcome row refuses a checkout that is not the errand's branch"
set +e
"$SHIM" row --run-dir "$FIX/castle-turing/2026-09-22T09-09-47" \
  --task 0076-widen-the-reachability-lint-to-its-claimed-coverage \
  --checkout "$REPO_ROOT" --env e2 > "$WORK/row.out" 2> "$WORK/row.err"
rc=$?
set -e
[ "$rc" = "2" ] || die "row against the wrong branch should refuse with 2, got $rc"
grep -q 'refusing to mature' "$WORK/row.err" || die "the row refusal says nothing"
ok "a row matured on the wrong branch is a mechanical failure, not a caveat"

echo
echo "$pass checks passed"
