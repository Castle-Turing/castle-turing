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
    return CODE_SPAN.sub(lambda m: " " * len(m.group(0)), text)


def mask(line):
    # Equal-length, so a position found in one mask means the same
    # position in the other and in the raw text.
    if line.lstrip().startswith(">"):
        return " " * len(line)
    masked = CODE_SPAN.sub(lambda m: " " * len(m.group(0)), line)
    masked = LINK_SPAN.sub(lambda m: " " * len(m.group(0)), masked)
    masked = CITE_SPAN.sub(lambda m: " " * len(m.group(0)), masked)
    return masked


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
        for raw in re.split(r"[,;]|\s{2,}|\s(?=[#]|commit\s|task\s|backlog:|journal\s|state\s)",
                            inner):
            tok = raw.strip()
            if not tok:
                continue
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
        if groups and re.fullmatch(r"[\s,;:.]*", text[groups[-1][1]:start]):
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

    A single left-to-right walk, and the ordering rule is the whole of
    it: phrases accumulate until a group arrives and then bind to it, so
    "merged, checks green, findings dispositioned [#63 #65]" binds three
    phrases to one group. A group that arrives with nothing pending is
    an orphan, and a phrase immediately following an orphan binds
    backwards to it — that is "[#102], checks green", and it is also
    "[#13] merged, and [#12] merged over a red gate", which under the
    earlier rule ("always bind forwards") had its first phrase bind to
    #12 and let an open pull request be reported as merged. That was the
    review finding this walk exists for.

    A phrase whose bound group cites nothing of the phrase's kind is
    treated as prose and dropped. Receipt words are ordinary English —
    "a queue holding merged briefs", "backlog entries filed via merged
    PRs" — and reading every occurrence as a claim rejected honest
    handovers while catching nothing. What keeps that gap small is
    C-GROUND: a *wrong* claim carries a citation to the artifact it is
    wrong about, so it does bind. What escapes is a receipt asserted
    about a kind of artifact the item never cites, which is unevidenced
    prose. Named rather than hidden: this is one control among several.
    """
    tokens = ([("phrase", p[0], p) for p in phrases]
              + [("group", g[0], g) for g in groups])
    tokens.sort(key=lambda t: t[1])
    bindings = []
    pending = []
    last_group = None
    last_group_used = True
    for kind, _, item in tokens:
        if kind == "group":
            if pending:
                bindings.extend((p, item) for p in pending)
                pending = []
                last_group_used = True
            else:
                last_group_used = False
            last_group = item
        elif last_group is not None and not last_group_used:
            bindings.append((item, last_group))
            last_group_used = True
        else:
            pending.append(item)
    if pending and last_group is not None:
        bindings.extend((p, last_group) for p in pending)
    return [(phrase, group) for phrase, group in bindings
            if resolved_by_group[group[:2]][phrase[2]]]


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

    for (start, end, kind, phrase, predicate, complaint), group in assign(
            phrases, groups, resolved_by_group):
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


def body_lines(lines):
    """Line indices outside fenced code blocks."""
    out = []
    fenced = False
    for i, line in enumerate(lines):
        if line.startswith("```"):
            fenced = not fenced
            continue
        if not fenced:
            out.append(i)
    return out


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
    for bound in (ledger["window"]["since"], ledger["window"]["until"]):
        if bound not in title:
            report.add("C-STRUCT", 1,
                       "the title does not state the window bound %s" % bound)
    bounds = split_sections(lines, report)

    # --- the claim lint, per physical line --------------------------------
    keep = set(body_lines(lines))
    for i, line in enumerate(lines, 1):
        if i - 1 not in keep:
            continue
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
        if first not in keep or first == title_line:
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
