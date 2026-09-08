#!/usr/bin/env python3
"""tools/handover-check.py — the claim-checker for a generated handover.

WHY THIS EXISTS AND WHY IT BLOCKS

`docs/tasks/0062-the-operator-handover.md` calls this the heart of the
task's verification, and states the rule it enforces: the handover makes
no completeness claims at all, and every claim it does make is derived
from artifact state with a citation the reader can follow. Both halves
are enforced here, mechanically, because neither survives as a
stylistic instruction. The confident-closure register ("done", "complete",
"successfully") is a trained default with a measurable signature that
model judges talk themselves out of (`docs/research/operator-handover.md`
§3), so an instruction not to use it is not a control. A lint is.

This is a blockable check, not a warning. The generator controls its own
output, so a violation is a generator bug — there is no third party whose
prose we are being strict about.

WHAT IT IS A PURE FUNCTION OF

(ledger JSON, handover markdown). Nothing else: no git, no `gh`, no
network, no reading of the working tree. That is what lets the golden
test in `test/handover/` keep meaning the same thing while the repo
underneath it moves — see the header of `tools/handover-ledger.py`.

WHAT IT CHECKS

  C-STRUCT   the six fields, spelled and ordered as the brief fixes them
  C-CITE     every citation resolves against the ledger
  C-GROUND   every claim carries a citation or an [unverified] marker
  C-STATE    a receipt phrase matches the artifact state it cites
             (a "merged" line whose PR is open; "checks green" whose
             checks failed; a journal id that does not resolve)
  C-CLAIM    no completion-assertion vocabulary in generated prose
  C-COVER    every coverage unit in the ledger is cited somewhere
  C-DEPENDS  every verdict request names what changes on the answer
  C-LENGTH   one screenful

USAGE

    tools/handover-check.py --ledger LEDGER.json HANDOVER.md
"""

import argparse
import datetime
import json
import pathlib
import re
import sys
import textwrap

SECTIONS = [
    "Intent",
    "Threats and drift",
    "What changed",
    "Unverified",
    "Verdicts requested",
    "Acknowledgment",
]

# Completion-assertion vocabulary. The first four are the brief's own
# list; the rest are the same register wearing different clothes, and
# each one was added because it says "this is finished" without evidence
# that could ground it. `merged`, `green`, `dispositioned` are
# deliberately absent: those are receipts, and the receipt vocabulary
# below is checked against the artifact rather than banned.
BANNED = [
    "done", "complete", "completed", "completes", "completing", "completion",
    "finish", "finished", "finishes", "success", "successful", "successfully",
    "delivered", "shipped", "achieved", "accomplished", "fully", "all set",
    "ready to ship", "wrapped up",
]
BANNED_RE = re.compile(
    r"(?<![\w-])(" + "|".join(re.escape(w) for w in BANNED) + r")(?![\w-])",
    re.I,
)

# Receipt phrases: a closed vocabulary, each mapping to a predicate over
# a cited artifact. Order matters — negations are tested before the
# positive they contain.
PR_RECEIPTS = [
    ("not merged", lambda pr: not pr["merged"], "is merged"),
    ("still open", lambda pr: pr["state"] == "OPEN", "is %(state)s, not open"),
    ("closed unmerged", lambda pr: pr["state"] == "CLOSED" and not pr["merged"],
     "is %(state)s"),
    ("merged", lambda pr: pr["merged"], "is %(state)s, not merged"),
    ("checks green", lambda pr: pr["checks"]["state"] == "green",
     "has checks %(checkstate)s"),
    ("checks red", lambda pr: pr["checks"]["state"] == "red",
     "has checks %(checkstate)s"),
    ("checks pending", lambda pr: pr["checks"]["state"] == "pending",
     "has checks %(checkstate)s"),
    ("checks skipped", lambda pr: pr["checks"]["state"] == "skipped",
     "has checks %(checkstate)s"),
    ("no checks", lambda pr: pr["checks"]["state"] == "absent",
     "has checks %(checkstate)s"),
    ("findings dispositioned", lambda pr: pr["review"]["state"] == "dispositioned",
     "review state is %(reviewstate)s"),
    ("findings undispositioned", lambda pr: pr["review"]["state"] == "undispositioned",
     "review state is %(reviewstate)s"),
    ("no review posted", lambda pr: pr["review"]["state"] == "no-review",
     "review state is %(reviewstate)s"),
]

TASK_RECEIPTS = [
    ("in the queue", lambda t: t["location"] == "queue", "sits in the %(location)s"),
    ("swept to the archive", lambda t: t["location"] == "archive",
     "sits in the %(location)s"),
]

BACKLOG_RECEIPTS = [
    ("filed", lambda b: b["added_in_window"], "was not filed in this window"),
    ("retired", lambda b: b["removed_in_window"], "was not retired in this window"),
]

CITATION_TOKEN = re.compile(
    r"""^(?:
        \#(?P<pr>\d+)
      | commit\s+(?P<commit>[0-9a-f]{7,40})
      | task\s+(?P<task>\d{4})
      | backlog:\s*(?P<backlog>[a-z0-9][a-z0-9._-]*)
      | journal\s+(?P<journal>[^\s\]]+)
      | state\s+(?P<state>[a-z0-9][a-z0-9-]*)
      | (?P<unverified>unverified)
    )$""",
    re.X | re.I,
)


class Report:
    def __init__(self):
        self.violations = []

    def add(self, code, line_no, message):
        self.violations.append((code, line_no, message))

    def ok(self):
        return not self.violations

    def render(self):
        out = []
        for code, line_no, message in sorted(self.violations, key=lambda v: (v[1], v[0])):
            where = "line %d" % line_no if line_no else "handover"
            out.append("  %-9s %-9s %s" % (code, where, message))
        return "\n".join(out)


# --- masking --------------------------------------------------------------
#
# Three spans are invisible to the claim lint, each for a stated reason.
# Blockquotes carry the resident's own words verbatim, and the brief
# exempts quoted resident verdicts by name — a verdict is theirs to
# render, including in the vocabulary this lint bans everywhere else.
# Inline code carries clause keys and paths (`docs/tasks/done/` contains
# a banned word and is not a claim). Citation spans carry ids.

CODE_SPAN = re.compile(r"`[^`]*`")
HTML_COMMENT_ONLY = re.compile(r"^\s*<!--.*-->\s*$", re.S)
CITE_SPAN = re.compile(r"\[[^\]\n]*\](?!\()")
LINK_SPAN = re.compile(r"\[[^\]\n]*\]\([^)\n]*\)")


LINK_URL = re.compile(r"(?<=\])\([^)\n]*\)")
ANY_BRACKET = re.compile(r"\[[^\]\n]*\]")


def blank(match):
    return " " * len(match.group(0))


def citation_tokens(inner):
    """Split a bracket span's contents into candidate citation tokens."""
    return [t.strip() for t in re.split(
        r"[,;]|\s{2,}|\s(?=[#]|commit\s|task\s|backlog:|journal\s|state\s)", inner)
        if t.strip()]


def is_citation_span(inner):
    tokens = citation_tokens(inner)
    return bool(tokens) and all(CITATION_TOKEN.match(t) for t in tokens)


def mask_code(text):
    """Blank inline code only, leaving citation spans readable.

    Citations must be parsed from this rather than from the raw text: a
    clause key or a path written in backticks is prose, and reading
    `[ex-done]` inside a code span as a citation rejected an honest line
    for an unrecognized token. And they must not be parsed from mask()
    either, which blanks the citations themselves.
    """
    if text.lstrip().startswith(">"):
        return " " * len(text)
    return CODE_SPAN.sub(blank, text)


def mask(line):
    """What the claim lint and the receipt matcher read.

    Blockquotes vanish — the format reserves them for the resident's own
    words, and a verdict is theirs to render in whatever register they
    like. Inline code vanishes, because a clause key or the path
    `docs/tasks/done/` is not a claim. A link's URL vanishes; its *text*
    does not, which is the fix for a real evasion — blanking whole
    `[text](url)` spans let `[is complete and was delivered
    successfully](https://…)` through the banned-vocabulary lint while
    rendering it in full to the reader. And a bracket span vanishes only
    if it actually parses as a citation, so ordinary bracketed prose
    stays visible to both checks.

    Every substitution is equal-length, so a position found here means
    the same position in mask_code() and in the raw text.
    """
    if line.lstrip().startswith(">"):
        return " " * len(line)
    masked = CODE_SPAN.sub(blank, line)
    masked = LINK_URL.sub(blank, masked)
    return ANY_BRACKET.sub(
        lambda m: blank(m) if is_citation_span(m.group(0)[1:-1].strip()) else m.group(0),
        masked)


def parse_citations(line, line_no, report):
    """Every citation span on a line, as resolved tokens.

    A bracketed span that is neither a markdown link nor a parseable
    citation is an error rather than prose: a reader cannot tell the two
    apart at a glance, and a citation that silently reads as decoration
    is the failure this whole surface exists to prevent.
    """
    found = []
    without_links = LINK_SPAN.sub(lambda m: " " * len(m.group(0)), line)
    for span in CITE_SPAN.finditer(without_links):
        inner = span.group(0)[1:-1].strip()
        if not inner:
            report.add("C-CITE", line_no, "empty citation span `[]`")
            continue
        for tok in citation_tokens(inner):
            m = CITATION_TOKEN.match(tok)
            if not m:
                report.add("C-CITE", line_no,
                           "unrecognized citation token %r (span %s)" % (tok, span.group(0)))
                continue
            kind = m.lastgroup
            found.append((kind, m.group(kind)))
    return found


def resolve(citations, ledger, line_no, report):
    """Resolve each citation against the ledger; unresolvable ones fail loudly."""
    resolved = {"pr": [], "commit": [], "task": [], "backlog": [],
                "journal": [], "state": [], "unverified": []}
    for kind, value in citations:
        if kind == "pr":
            pr = ledger["prs"].get(value)
            if pr is None:
                report.add("C-CITE", line_no,
                           "PR #%s is not in the ledger's window" % value)
            else:
                resolved["pr"].append(pr)
        elif kind == "commit":
            match = [c for sha, c in ledger["commits"].items()
                     if sha.startswith(value.lower()) or c["short"] == value.lower()]
            if not match:
                report.add("C-CITE", line_no,
                           "commit %s does not resolve in the ledger's window" % value)
            else:
                resolved["commit"].append(match[0])
        elif kind == "task":
            task = ledger["tasks"].get(value)
            if task is None:
                report.add("C-CITE", line_no, "task %s is not in the ledger" % value)
            else:
                resolved["task"].append(task)
        elif kind == "backlog":
            entry = ledger["backlog"].get(value)
            if entry is None:
                report.add("C-CITE", line_no,
                           "backlog entry %r is not in the ledger" % value)
            else:
                resolved["backlog"].append(entry)
        elif kind == "journal":
            journal = ledger["journal"]
            rec = journal.get("records", {}).get(value)
            if rec is None:
                detail = ("this machine had no journal to read: %s" % journal.get("reason")
                          if not journal.get("available")
                          else "no such record in the window")
                report.add("C-STATE", line_no,
                           "journal id %s does not resolve — %s" % (value, detail))
            else:
                resolved["journal"].append(rec)
        elif kind == "state":
            clause = ledger["state"]["clauses"].get(value)
            if clause is None:
                report.add("C-CITE", line_no,
                           "state clause [%s] does not exist in docs/state/" % value)
            else:
                resolved["state"].append(clause)
        elif kind == "unverified":
            resolved["unverified"].append(True)
    return resolved


def citation_groups(text):
    """Runs of adjacent citation spans, with their positions.

    A claim line routinely carries more than one receipt and more than
    one group — "checks green on [#64 #70], no checks on [#68 #97]" is
    one line making two opposite claims. Applying every phrase on the
    line to every citation on it read that as a contradiction and
    rejected an honest handover. So a group is a run of spans separated
    by nothing but whitespace and punctuation, and a phrase binds to one
    group rather than to the line.
    """
    spans = []
    without_links = LINK_SPAN.sub(lambda m: " " * len(m.group(0)), text)
    for m in CITE_SPAN.finditer(without_links):
        spans.append((m.start(), m.end(), m.group(0)))
    groups = []
    for start, end, raw in spans:
        if groups and re.fullmatch(r"[\s,;:.]*(?:and|plus|&)?[\s,;:.]*",
                                   text[groups[-1][1]:start], re.I):
            groups[-1] = (groups[-1][0], end, groups[-1][2] + [raw])
        else:
            groups.append((start, end, [raw]))
    return groups


ALL_RECEIPTS = (
    [("pr", p, f, c) for p, f, c in PR_RECEIPTS]
    + [("task", p, f, c) for p, f, c in TASK_RECEIPTS]
    + [("backlog", p, f, c) for p, f, c in BACKLOG_RECEIPTS]
)


def find_phrases(masked):
    """Receipt phrases and where they sit, longest first, non-overlapping.

    Longest first is what keeps "not merged" from also firing "merged".
    The word boundaries are what keep "merged" from firing inside
    "unmerged" — which inverted the check outright: "still open and
    unmerged [#13]" was rejected for claiming a merge.
    """
    taken = []
    found = []
    for kind, phrase, predicate, complaint in sorted(
            ALL_RECEIPTS, key=lambda r: -len(r[1])):
        pattern = r"(?<![\w-])" + re.escape(phrase) + r"(?![\w-])"
        for m in re.finditer(pattern, masked, re.I):
            if any(m.start() < e and s < m.end() for s, e in taken):
                continue
            taken.append((m.start(), m.end()))
            found.append((m.start(), m.end(), kind, phrase, predicate, complaint))
    return sorted(found)


def assign(phrases, groups, resolved_by_group):
    """Bind each receipt phrase to the citation group it governs.

    A single left-to-right walk, kind-aware at every step. Phrases
    accumulate until a group arrives that cites an artifact of their
    kind, so "sit in the queue [task 0058] though their PRs merged
    [#100 #101]" sends the brief phrase to the briefs and the merge
    phrase to the pull requests. A group arriving with nothing pending
    for it is an orphan, and a phrase that follows an orphan of its kind
    binds backwards to it — that is "[#102], checks green", and it is
    also "[#13] merged, and [#12] merged over a red gate", which under a
    forwards-only rule reported an open pull request as merged.

    Returns the bindings and the groups nothing ever governed. The
    caller refuses the latter: a line that makes receipt claims and
    cites a pull request under none of them is how the same evasion
    keeps coming back in a new position, most recently as a trailing
    "[#11], and [#13]" where every phrase bound to #11.

    A phrase that finds no group of its kind anywhere is dropped as
    prose. Receipt words are ordinary English — "a queue holding merged
    briefs" — and reading every occurrence as a claim rejected honest
    handovers while catching nothing. What keeps that gap small is
    C-GROUND: a *wrong* claim cites the artifact it is wrong about, so
    it binds. What escapes is a receipt about a kind of artifact the
    item never cites, which is unevidenced prose. Named, not hidden.
    """
    def cites(group, kind):
        return bool(resolved_by_group[group[:2]][kind])

    tokens = ([("phrase", p[0], p) for p in phrases]
              + [("group", g[0], g) for g in groups])
    tokens.sort(key=lambda t: t[1])

    bindings = []
    pending = []
    orphans = []
    governed = set()
    for token_kind, _, item in tokens:
        if token_kind == "group":
            still, bound = [], False
            for phrase in pending:
                if cites(item, phrase[2]):
                    bindings.append((phrase, item))
                    governed.add(item[:2])
                    bound = True
                else:
                    still.append(phrase)
            pending = still
            if not bound:
                orphans.append(item)
        else:
            hit = next((g for g in reversed(orphans) if cites(g, item[2])), None)
            if hit is not None:
                bindings.append((item, hit))
                governed.add(hit[:2])
                orphans.remove(hit)
            else:
                pending.append(item)
    for phrase in pending:
        hit = next((g for g in reversed(groups) if cites(g, phrase[2])), None)
        if hit is not None:
            bindings.append((phrase, hit))
            governed.add(hit[:2])

    ungoverned = [g for g in groups
                  if g[:2] not in governed
                  and any(resolved_by_group[g[:2]][k] for k in ("pr", "task", "backlog"))]
    return bindings, ungoverned


def check_receipts(text, code_masked, line_no, ledger, report):
    """A receipt phrase must match the state of the artifacts it governs."""
    groups = citation_groups(code_masked)
    phrases = find_phrases(mask(text))
    if not phrases or not groups:
        return
    resolved_by_group = {}
    for g in groups:
        cites = []
        for raw in g[2]:
            cites.extend(parse_citations(raw, line_no, Report()))
        resolved_by_group[g[:2]] = resolve(cites, ledger, line_no, Report())

    bindings, ungoverned = assign(phrases, groups, resolved_by_group)
    for group in ungoverned:
        report.add("C-STATE", line_no,
                   "this line makes receipt claims, but %s is cited under none of "
                   "them — say what is claimed about it, or cite it on a line that "
                   "claims nothing" % " ".join(group[2]))
    for (start, end, kind, phrase, predicate, complaint), group in bindings:
        for subject in resolved_by_group[group[:2]][kind]:
            if predicate(subject):
                continue
            if kind == "pr":
                who = "PR #%d" % subject["number"]
                fields = {
                    "state": subject["state"],
                    "checkstate": subject["checks"]["state"],
                    "reviewstate": subject["review"]["state"],
                }
            elif kind == "task":
                who = "task %s" % subject["id"]
                fields = subject
            else:
                who = "backlog entry %r" % subject["name"]
                fields = subject
            report.add("C-STATE", line_no,
                       "%r, but %s %s" % (phrase, who, complaint % fields))


def logical_items(lines, start, end):
    """A section's claims, as logical items rather than physical lines.

    A bullet that wraps is one claim, and so is its indented `Depends:`
    continuation. Checking per physical line reported every wrapped line
    as an uncited claim, and — worse — split a citation span across a
    wrap so that C-GROUND saw a citation C-COVER never counted.
    """
    items = []
    current = None
    for i in range(start, end):
        raw = lines[i]
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            current = None
            continue
        if re.match(r"^\s*[-*]\s+\S", raw) or current is None:
            items.append([i + 1, [raw]])
            current = items[-1]
        else:
            current[1].append(raw)
    return [(n, " ".join(l.strip() for l in ls)) for n, ls in items]


def split_sections(lines, report):
    """Map heading -> (start, end) line indices; report structural faults."""
    seen = []
    bounds = {}
    for i, line in enumerate(lines):
        m = re.match(r"^##\s+(.+?)\s*$", line)
        if m:
            seen.append((m.group(1), i))
    for idx, (title, start) in enumerate(seen):
        end = seen[idx + 1][1] if idx + 1 < len(seen) else len(lines)
        bounds[title] = (start, end)
    order = [t for t, _ in seen]
    if order != SECTIONS:
        report.add("C-STRUCT", 0,
                   "sections are %r; the brief fixes them as %r" % (order, SECTIONS))
    return bounds


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("handover")
    ap.add_argument("--ledger", required=True)
    ap.add_argument("--max-lines", type=int, default=60,
                    help="one screenful, measured after wrapping (default 60)")
    ap.add_argument("--width", type=int, default=100)
    args = ap.parse_args(argv)

    ledger = json.loads(pathlib.Path(args.ledger).read_text(encoding="utf-8"))
    if ledger.get("schema") != "castle-handover-ledger/1":
        print("handover-check: %s is not a castle-handover-ledger/1 document."
              % args.ledger, file=sys.stderr)
        return 2
    text = pathlib.Path(args.handover).read_text(encoding="utf-8")
    lines = text.splitlines()
    report = Report()

    # --- C-STRUCT ---------------------------------------------------------
    title = next((l for l in lines if l.startswith("# ")), "")
    since = ledger["window"]["since"]
    # The ledger's `until` is exclusive. Requiring it verbatim in the
    # title enforced an overstatement: a window ending 2026-09-06
    # exclusive covers through the 5th, and the title said "to
    # 2026-09-06" — a day the report says nothing about. The last day it
    # actually covers is what the reader needs.
    last = (datetime.date.fromisoformat(ledger["window"]["until"])
            - datetime.timedelta(days=1)).isoformat()
    for bound in (since, last):
        if bound not in title:
            report.add("C-STRUCT", 1,
                       "the title does not state the window bound %s (the window is "
                       "%s through %s inclusive)" % (bound, since, last))
    if ledger["window"]["until"] in title and ledger["window"]["until"] != last:
        report.add("C-STRUCT", 1,
                   "the title states %s, the window's exclusive upper bound — a day "
                   "the handover covers nothing of. Say %s."
                   % (ledger["window"]["until"], last))
    bounds = split_sections(lines, report)

    # --- the claim lint, per physical line --------------------------------
    # No exemption for fenced blocks. They were skipped by both this
    # lint and the grounding scan, and a fence *renders* — unlike an HTML
    # comment, whose exemption is justified by being invisible. A
    # handover has no use for one, so a fence is a structural error and
    # its contents are checked like any other prose.
    for i, line in enumerate(lines, 1):
        if line.startswith("```"):
            report.add("C-STRUCT", i,
                       "a fenced block in a handover: the format has no use for one, "
                       "and a fence that exempted its contents from these checks "
                       "would render to the reader unchecked")
        for m in BANNED_RE.finditer(mask(line)):
            report.add("C-CLAIM", i,
                       "completion-assertion vocabulary %r — the handover reports "
                       "receipts and asks for verdicts; it renders none"
                       % m.group(1))

    # --- grounding, receipts and coverage, per logical item ---------------
    #
    # Over the whole body, not over a list of named sections. Restricting
    # these to the five claim-bearing headings left two doors open that
    # the review walked through: a claim placed before `## Intent`, and
    # one under `## Acknowledgment` ("every pull request merged with green
    # checks"), both unchecked. Anything outside a heading is checked as
    # if it were a claim, because that is what it would be read as.
    GROUNDLESS_OK = ("Acknowledgment",)
    section_of = {}
    for title, (sec_start, sec_end) in bounds.items():
        for i in range(sec_start, sec_end):
            section_of[i] = title

    title_line = next((i for i, l in enumerate(lines) if l.startswith("# ")), None)
    cited_prs = set()
    for i, text in logical_items(lines, 0, len(lines)):
        first = i - 1
        if first == title_line:
            continue
        if HTML_COMMENT_ONLY.match(text):
            # Invisible in the rendered document, so it is not a claim
            # the resident could act on. The reject fixtures under
            # test/handover/ state their expected violation code this
            # way, and grounding them as claims made every one of them
            # report a spurious C-GROUND.
            continue
        section = section_of.get(first)
        code_masked = mask_code(text)
        citations = parse_citations(code_masked, i, report)
        resolved = resolve(citations, ledger, i, report)
        for pr in resolved["pr"]:
            cited_prs.add(str(pr["number"]))

        if section == "Acknowledgment":
            # The closing act asks the resident to write back. It is the
            # one section that makes no claims, so it may carry neither a
            # citation nor a receipt phrase — which is also how "every PR
            # merged, checks green" hidden down here gets caught without
            # demanding the closing sentence cite something.
            if citations or find_phrases(mask(text)):
                report.add("C-STRUCT", i,
                           "the closing act states a claim; it asks for a "
                           "written-back acknowledgment and nothing else")
            continue

        if not citations:
            report.add("C-GROUND", i,
                       "claim in %r carries no citation and no [unverified] marker"
                       % (section or "the handover's body, outside any section"))
        elif section == "Unverified" and not any(k == "unverified" for k, _ in citations):
            report.add("C-GROUND", i,
                       "a line under 'Unverified' must carry the [unverified] marker")

        if not text.lstrip().startswith(">"):
            check_receipts(text, code_masked, i, ledger, report)

    # --- C-DEPENDS --------------------------------------------------------
    if "Verdicts requested" in bounds:
        sec_start, sec_end = bounds["Verdicts requested"]
        # Top-level bullets only. An indented sub-bullet listing a
        # request's evidence is part of that request, and treating it as
        # a request of its own both demanded a `Depends:` it should not
        # have and cut short the scan for the real one.
        bullets = [i for i in range(sec_start + 1, sec_end)
                   if re.match(r"^[-*]\s+\S", lines[i])]
        for b in bullets:
            depends = None
            for j in range(b + 1, sec_end):
                if re.match(r"^[-*]\s+\S", lines[j]):
                    break
                if re.match(r"^\s*Depends:\s*\S", lines[j]):
                    depends = lines[j]
                    break
            if depends is None:
                report.add("C-DEPENDS", b + 1,
                           "a verdict request must carry a `Depends:` line naming "
                           "what changes depending on the answer; a request nothing "
                           "depends on is a defect")

    # --- C-COVER ----------------------------------------------------------
    if not ledger.get("forge", {}).get("read", True):
        report.add("C-COVER", 0,
                   "the ledger was built with --no-forge, so coverage cannot be "
                   "checked at all; regenerate it with the forge readable")
    missing = [u for u in ledger.get("coverage_units", []) if u["id"] not in cited_prs]
    for unit in missing:
        report.add("C-COVER", 0,
                   "%s #%s (%s) is in the ledger and cited nowhere"
                   % (unit["kind"], unit["id"], (unit["label"] or "")[:60]))

    # --- C-LENGTH ---------------------------------------------------------
    rendered = 0
    for line in lines:
        rendered += max(1, len(textwrap.wrap(line, args.width)) if line.strip() else 1)
    if rendered > args.max_lines:
        report.add("C-LENGTH", 0,
                   "the handover renders to %d lines at %d columns; one screenful "
                   "is %d. Comprehensiveness is the anti-goal — link, do not append."
                   % (rendered, args.width, args.max_lines))

    if report.ok():
        print("handover-check: %s passes against %s — %d coverage units, all cited."
              % (args.handover, args.ledger, len(ledger.get("coverage_units", []))))
        return 0
    print("handover-check: %s FAILED against %s (%d violations).\n"
          % (args.handover, args.ledger, len(report.violations)), file=sys.stderr)
    print(report.render(), file=sys.stderr)
    print("\nThis is a blocking check. The generator controls its own output, so "
          "each of these is a generator bug, not a style note.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
