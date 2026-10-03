#!/usr/bin/env bash
# test/delivery-shim/tenant-boundary.sh — the live half of task 0082's
# verification: the whole loop, against the tenant's real resume verb.
#
# WHY THIS IS NOT IN run.sh
#
# It needs the tenant installed, and the stock CI runner does not have it.
# A check that skips wherever it runs is a check that cannot fail, so this
# is a separate script invoked by hand on a host that has the tenant,
# rather than a conditional branch inside a suite that would quietly pass
# without it. What it produces is the capture in `fixtures/resumed/`, and
# `run.sh`'s check 25 reads that capture — so the property is demonstrated
# here and re-checked there.
#
# WHAT IT DEMONSTRATES, AND WHY EACH STEP IS LOAD-BEARING
#
#   1. An unanswered park makes the verb refuse before it journals
#      anything. This is what makes `resume`'s "nothing to spend" case
#      free rather than merely harmless.
#   2. An answered park, handed over by `castle-delivery-shim resume`,
#      re-runs the errand — the full loop (park, question, answer,
#      resumption) with no operator's hand in it.
#   3. Re-invoking the verb on a park it has already resolved dispatches
#      nothing and pays for no model. This is the property the write-ahead
#      ordering relies on: the crash window between "claim written" and
#      "invocation died" is closed at the tenant boundary, not by a
#      checkpoint on this side.
#
# The tenant runs with its dry-run adapter throughout, so no model is
# called and nothing is spent. That is not a weakening of the check: the
# adapter is the only thing stubbed, and every part of the verb this
# mechanism depends on — the park's file, `resolvable`, the selection
# loop, `resolve` before dispatch — is the real one.
#
#   EMCEE=/path/to/emcee test/delivery-shim/tenant-boundary.sh
#
# The corpus's dovetail park is the input, copied, with its one
# machine-local path rewritten. Nothing outside the work directory is
# touched, and the disposable repository the verb is pointed at is created
# here — never a real checkout.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SHIM="$REPO_ROOT/agent/castle-delivery-shim"
CASTLE="$REPO_ROOT/agent/castle"
FIX="$REPO_ROOT/test/delivery-shim/fixtures"
EMCEE="${EMCEE:-emcee}"

if ! command -v "$EMCEE" > /dev/null 2>&1 && [ ! -x "$EMCEE" ]; then
  echo "tenant-boundary: no tenant at '$EMCEE'. Set EMCEE to the tenant's" >&2
  echo "executable (a console script, or the one inside its virtualenv)." >&2
  echo "This script is the live exercise and has nothing to fall back on:" >&2
  echo "run.sh checks the capture it produced instead." >&2
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
pass=0
ok() { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
die() { printf '  FAIL %s\n' "$1" >&2; exit 1; }

RUN="$WORK/runs/dovetail/2026-09-05T01-45-45"
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

REPO="$WORK/target"
mkdir -p "$REPO/docs/tasks"
cp "$FIX"/dovetail-tasks/*.md "$REPO/docs/tasks/"
git -C "$REPO" init -q -b main
git -C "$REPO" -c user.email=t@example.invalid -c user.name=t add -A
git -C "$REPO" -c user.email=t@example.invalid -c user.name=t commit -qm briefs

export CASTLE_STATE_DIR="$WORK/state"
mkdir -p "$CASTLE_STATE_DIR/journal"
# The verb, with its dry-run adapter. Constructed here rather than read
# from the environment: a test must never invoke whatever resume command
# the host happens to have configured, because that one calls models.
export CASTLE_DELIVERY_RESUME_COMMAND="$EMCEE resume --dry-run"

seqs() { python3 -c "import json,sys;print(sum(1 for _ in open(sys.argv[1])))" "$1"; }
steps_after() {
  python3 - "$1" "$2" <<'PY'
import json, sys
recs = [json.loads(l) for l in open(sys.argv[1])]
after = int(sys.argv[2])
print(len([r for r in recs if r["seq"] > after and r["type"] == "step_started"]))
PY
}

echo "1. an unanswered park makes the verb refuse, before it journals anything"
before="$(seqs "$RUN/journal.jsonl")"
set +e
"$EMCEE" resume --run "$RUN" --repo "$REPO" --tasks "$REPO/docs/tasks" --dry-run \
  > "$WORK/unanswered.out" 2> "$WORK/unanswered.err"
rc=$?
set -e
[ "$rc" = "1" ] || die "an unanswered park did not refuse (exit $rc)"
grep -q 'still waiting on an answer' "$WORK/unanswered.err" \
  || die "the refusal does not say what it is waiting for"
[ "$(seqs "$RUN/journal.jsonl")" = "$before" ] \
  || die "the refused invocation journaled records"
ok "exit 1, nothing journaled, and it names the question file"

echo "2. an answered delivery question resumes the errand, with no relaunch by hand"
"$SHIM" fold --run-dir "$RUN" --tasks-dir "$REPO/docs/tasks" > /dev/null
Q="$(basename "$(grep -l '^type: question' "$CASTLE_STATE_DIR"/journal/*.md)" .md)"
python3 "$CASTLE" answer "$Q" \
  'Option B: the same budget the float step uses for its wait. Fix both paths.' > /dev/null
park_seq="$(python3 -c "
import json
print(next(r['seq'] for r in map(json.loads, open('$RUN/journal.jsonl')) if r['type']=='parked'))")"
"$SHIM" resume --run-dir "$RUN" --repo "$REPO" --tasks-dir "$REPO/docs/tasks" \
  > "$WORK/resume.out" 2>&1 || die "the resumption pass failed: $(cat "$WORK/resume.out")"
[ "$(steps_after "$RUN/journal.jsonl" "$park_seq")" = "1" ] \
  || die "the errand did not re-run exactly once after its park"
grep -q '^Status: resolved$' "$RUN/parked/README.md" \
  || die "the tenant did not resolve the park it resumed"
ok "the tenant re-ran the errand once, on an answer nothing but the journal carried"

echo "3. re-invoking the verb on a resolved park dispatches nothing"
mark="$(python3 -c "
import json
print(max(r['seq'] for r in map(json.loads, open('$RUN/journal.jsonl'))))")"
"$EMCEE" resume --run "$RUN" --repo "$REPO" --tasks "$REPO/docs/tasks" --dry-run \
  > "$WORK/reinvoke.out" 2>&1 || die "the re-invocation failed"
[ "$(steps_after "$RUN/journal.jsonl" "$mark")" = "0" ] \
  || die "the re-invocation dispatched a task, so the crash window is not closed"
ok "no task dispatched, no model called — the crash window closes at this boundary"

echo
echo "$pass checks passed against the real tenant verb ($($EMCEE --version 2>/dev/null || echo 'version unknown'))"
echo
echo "To refresh fixtures/resumed/, capture this run's journal.jsonl, its"
echo "parked/ file and the castle records from \$CASTLE_STATE_DIR/journal,"
echo "and apply the redaction fixtures/README.md describes. Never edit a"
echo "fixture in place."
