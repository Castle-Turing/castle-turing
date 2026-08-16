#!/usr/bin/env bash
# test/agent-loop/scripted-worker.sh — a worker seat held by a shell script.
#
# Stands in for a real worker under Proposal 03 (docs/architecture.md):
# "any intelligence that can read and write [the artifacts] can hold the
# seat." This one reads a `request` record, does no actual work (there is
# no repo to diff against in the CI sandbox — this harness is zero
# models, zero network, per docs/tasks/0008), and writes back a `result`
# record whose body clearly says the diff inside it is synthetic. What it
# does exercise for real: reading the request's own provenance and
# propagating it onto the result, which is what lets the router's
# provenance-alone rule produce a different channel for each of the two
# canned errands in run.sh.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: scripted-worker.sh <castle-bin> <request-id>" >&2
  exit 2
fi

CASTLE="$1"
REQUEST_ID="$2"

# Extract the request's own provenance rather than assuming one — a real
# worker has to read this too, since the whole point of the field is
# that the router can't be handed a guess.
provenance="$("$CASTLE" show "$REQUEST_ID" | sed -n 's/^provenance: //p' | head -n1)"
if [ -z "$provenance" ]; then
  echo "scripted-worker: could not read provenance from $REQUEST_ID" >&2
  exit 1
fi

# A quoted heredoc (no expansion at all) written straight to a temp
# file, rather than captured via $(cat <<'EOF' ... ) — bash tracks
# backtick pairing for command substitution across a whole $(...)
# nesting even when the heredoc inside it is quoted, so a body that mixes
# a literal backtick with a later apostrophe (both appear below, for the
# markdown code fence and "hardening test's") breaks that form with an
# "unexpected EOF" parse error. Writing to a file first sidesteps it.
tmpfile="$(mktemp)"
trap 'rm -f "$tmpfile"' EXIT
cat <<'BODY_EOF' > "$tmpfile"
Errand `%s` complete.

This result was produced by test/agent-loop/scripted-worker.sh, a
scripted worker tenant with zero model and zero network involvement
(docs/tasks/0008's hardening test for Proposal 03). The diff below is
synthetic — a fixed string, not a real repo change — since this harness
never touches a working tree:

```diff
--- a/docs/backlog/example-item (synthetic, harness fixture only)
+++ b/docs/backlog/example-item (synthetic, harness fixture only)
@@ -1 +1 @@
-placeholder before
+placeholder after
```
BODY_EOF
body="$(sed "s/%s/$REQUEST_ID/" "$tmpfile")"

"$CASTLE" record \
  --type result \
  --provenance "$provenance" \
  --seat worker \
  --refs "$REQUEST_ID" \
  --body "$body"
