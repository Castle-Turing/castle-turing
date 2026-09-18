# The reachability detector and redirect logger have hardening gaps

**What.** The `/code-review` of PR #137 (task 0072) found four latent
defects that survived verification — none an active failure on the
current tree (both test suites and the real-tree lint pass), so they
were dispositioned here rather than fixed under review, where changing
a careful, well-tested implementation risks regression. Finding 1 of
that review was fixed on the branch (a known-header whitelist in
`tools/outcomes/outcomes` `brief_headers`); these are its siblings:

- **`tools/reachability-check.py` `code_only` strips string literals,
  so a string-arg caller is invisible** (~line 208). A future
  `subprocess.run(['tools/outcomes/outcomes','derive'])` has its path
  and subcommand tokens removed before `invokes()` sees them, so the
  lint reports `derive` as an orphan and fails CI for a command that
  is genuinely called — the false-positive direction the module header
  claims to avoid. Verified by the reviewer against the real function.
- **The orphan-entrypoint rule only inspects tools containing
  `add_subparsers`** (~line 97), exempting every single-command tool —
  `tools/handover-ledger.py` (the row-writer the module header cites as
  its own analogy), `tools/handover-check.py`, and all `.sh` tools. If
  one lost its only caller, the lint would still print "all reachable."
- **The armed-gate/feeder rule only recognises gates whose checker is
  an argparse subcommand named `check`** (~line 338), missing standalone
  checker scripts run directly from a workflow (e.g.
  `tools/handover-check.py`, the repo's own established pattern) — so an
  armed-gate-with-no-feeder of that shape passes the lint. The module
  header names only the test-wrapper gap, so its coverage claim reads
  broader than the code delivers.
- **`cmd_redirect` does the forge author lookup before the final static
  citation check** (~line 1228, a nit — correctness is fine). A
  statically-doomed reassessment (`--wrong` against an
  already-reassessed citation) spends a `gh api` round-trip before the
  "one citation, one judgment" check rejects it; the check could run
  before the network boundary.
- **Residual of the fixed finding 1:** the whitelist stops non-header
  continuation lines from becoming spurious keys, but a continuation
  line beginning with a literal *recognised* key + colon
  (`Model:`/`Milestone:`) is still ambiguous. Closing it fully needs a
  format change (indented continuations, RFC-822 style), not a parser
  heuristic — the same class as emcee's
  `a-wrapped-header-value-silently-voids-later-headers`.

**Why it matters.** Three of these make the reachability detector —
itself the "incident ships its detector" artifact for the
tool-wired-to-nothing class — narrower or more false-positive-prone
than its own documentation claims. A detector that overclaims its
coverage is the quiet-day failure one level up: it reports "all
reachable" while blind to shapes it never inspects. The redirect nit
is cost, not correctness.

**How this would have been caught sooner.** These are gaps in a
detector, found by review of the detector — which is the mechanism
working. The fix is to widen the lint's caller-recognition (string
args), tool-enumeration (single-command tools), and gate-recognition
(standalone checkers) to match the incident class it guards, and to
narrow its header comment to what it actually checks until then.
