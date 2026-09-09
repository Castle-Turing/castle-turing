#!/usr/bin/env python3
"""tools/handover-ledger.py — read the ledgers, emit artifact state as JSON.

WHY THIS IS A SEPARATE SCRIPT (read before touching it)

`docs/tasks/0062-the-operator-handover.md` puts one rule above every
other: a handover's claims are derived from artifact state — merge
status, checks, review dispositions, where a brief file sits — and
never from any agent's account of its own work. Self-asserted
completion is false in 45-76% of measured cases and no model reliably
detects it (`docs/research/operator-handover.md` §3).

That rule only has teeth if the artifact state is read by something
with no model in it. This script is that something: `git`, `gh`, and
the working tree, into one JSON document. The generating agent reads
its output and may cite nothing that is not in it; the claim-checker
(`tools/handover-check.py`) resolves every citation against the same
document and never touches git, the network, or the tree.

That split is deliberate and is what makes the golden test possible.
The checker being a pure function of (ledger, handover) means a frozen
ledger fixture keeps checking the same way forever, while the repo
underneath it moves — briefs get swept into `docs/tasks/done/`,
branches get deleted, PRs get more comments. A checker that re-derived
truth from the live repo would fail the golden test for reasons that
have nothing to do with the handover it is checking.

Stdlib only, like `agent/castle` and for the same reason: this has to
keep working on someone else's machine in ten years with nothing
installed but a python3 binary. `jq` in particular is NOT assumed —
`gh --json` output is parsed here, not piped through a filter that may
not be present (it was not present on the machine this was written on).

USAGE

    tools/handover-ledger.py [--since DATE] [--until DATE]
                             [--repo-root DIR] [-o FILE]

`--since`/`--until` bound the window in the git and forge senses both;
`--until` is exclusive, so a week is `--since 2026-09-01 --until
2026-09-08`. Defaults to the last seven days.
"""

import argparse
import datetime
import json
import os
import pathlib
import re
import subprocess
import sys

SCHEMA = "castle-handover-ledger/1"

# A comment carrying a cross-vendor / cross-model review's findings. The
# chevaline gate's HTML marker is the reliable one (it is invisible in
# rendered markdown and stable across changes to the comment's prose —
# the profile's own scar tissue); the heading forms are the older
# hand-posted shapes this repo's history actually contains, from
# `tools/codex-review.sh --post` and its OpenCode successor.
REVIEW_MARKERS = (
    re.compile(r"<!--\s*chevaline-gate:\s*cross-vendor-review\s*-->"),
    re.compile(r"^\s{0,3}#{1,6}\s*Cross-(?:vendor|model)\s+review\b", re.M | re.I),
)

# The answering comment. There is no machine marker on this one — the
# handler workflow confirms only that *a* comment appeared — so this
# matches the heading convention the repo has actually used. Recorded as
# a known soft spot rather than papered over: a dispositions comment
# written under some other heading reads here as absent, which fails
# closed (a "findings dispositioned" claim is rejected), not open.
DISPOSITION_MARKER = re.compile(r"^\s{0,3}#{1,6}\s*Disposition", re.M | re.I)

CLAUSE_TEXT_LIMIT = 1600

CHECK_GREEN = {"SUCCESS", "NEUTRAL", "SKIPPED"}
CHECK_PENDING = {"PENDING", "EXPECTED", "QUEUED", "IN_PROGRESS", "WAITING", ""}
CHECK_RED = {"FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE", "STALE"}


def run(cmd, cwd=None, check=True):
    proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if check and proc.returncode != 0:
        raise RuntimeError(
            "handover-ledger: command failed (%d): %s\n%s"
            % (proc.returncode, " ".join(cmd), proc.stderr.strip())
        )
    return proc


def progress(msg):
    print("handover-ledger: %s" % msg, file=sys.stderr)


# --- git -----------------------------------------------------------------


def git_commits(root, since, until):
    """Commits in the window, by full sha, with their subjects."""
    out = run(
        [
            "git", "log",
            "--since=%s" % since, "--until=%s" % until,
            "--format=%H%x1f%h%x1f%cI%x1f%s",
        ],
        cwd=root,
    ).stdout
    commits = {}
    for line in out.splitlines():
        if not line.strip():
            continue
        full, short, date, subject = line.split("\x1f", 3)
        commits[full] = {"sha": full, "short": short, "date": date, "subject": subject}
    return commits


def git_path_events(root, since, until, paths):
    """Adds, deletes and renames under `paths` in the window.

    Returned as a list of (status, path, newpath) with the *effective*
    status: git reports a rename as R<score>, which for the queue is how
    a brief moving into `docs/tasks/done/` actually looks.
    """
    out = run(
        [
            "git", "log",
            "--since=%s" % since, "--until=%s" % until,
            "--diff-filter=ADR", "--name-status", "--format=%x1e", "-M",
            "--", *paths,
        ],
        cwd=root,
    ).stdout
    events = []
    for line in out.splitlines():
        line = line.strip("\x1e").strip()
        if not line or "\t" not in line:
            continue
        parts = line.split("\t")
        status = parts[0][0]
        if status == "R":
            events.append(("R", parts[1], parts[2]))
        else:
            events.append((status, parts[1], None))
    return events


# --- the queue and the backlog -------------------------------------------

TASK_FILE = re.compile(r"^(\d{4})-(.+)\.md$")


def read_tasks(root, events):
    """Every numbered brief, where it sits, and what moved in the window."""
    tasks = {}

    def note(path, location):
        name = pathlib.PurePosixPath(path).name
        m = TASK_FILE.match(name)
        if not m:
            return None
        num = m.group(1)
        entry = tasks.setdefault(
            num,
            {
                "id": num,
                "path": path,
                "location": location,
                "title": None,
                "added_in_window": False,
                "archived_in_window": False,
            },
        )
        entry["path"] = path
        entry["location"] = location
        return entry

    for sub, location in (("", "queue"), ("done", "archive")):
        d = root / "docs" / "tasks" / sub if sub else root / "docs" / "tasks"
        if not d.is_dir():
            continue
        for f in sorted(d.iterdir()):
            if not f.is_file() or not TASK_FILE.match(f.name):
                continue
            rel = f.relative_to(root).as_posix()
            entry = note(rel, location)
            if entry is not None:
                entry["title"] = first_title(f)

    for status, path, newpath in events:
        if not path.startswith("docs/tasks/"):
            continue
        if status == "A":
            e = tasks.get(pathlib.PurePosixPath(path).name[:4])
            if e:
                e["added_in_window"] = True
        elif status == "R" and newpath and newpath.startswith("docs/tasks/done/"):
            e = tasks.get(pathlib.PurePosixPath(newpath).name[:4])
            if e:
                e["archived_in_window"] = True
    return tasks


def first_title(path):
    """A brief's title: its first `# ` heading, or its `Title:` header."""
    try:
        with path.open(encoding="utf-8") as fh:
            for line in fh:
                if line.startswith("# "):
                    return line[2:].strip()
                if line.lower().startswith("title:"):
                    return line.split(":", 1)[1].strip()
    except OSError:
        return None
    return None


def read_backlog(root, events):
    backlog = {}
    d = root / "docs" / "backlog"
    if d.is_dir():
        for f in sorted(d.iterdir()):
            if f.is_file() and f.suffix == ".md" and f.name != "README.md":
                backlog[f.stem] = {
                    "name": f.stem,
                    "path": f.relative_to(root).as_posix(),
                    "present": True,
                    "added_in_window": False,
                    "removed_in_window": False,
                }
    for status, path, newpath in events:
        if not path.startswith("docs/backlog/"):
            continue
        stem = pathlib.PurePosixPath(path).stem
        if status == "A":
            entry = backlog.setdefault(
                stem,
                {"name": stem, "path": path, "present": False,
                 "added_in_window": False, "removed_in_window": False},
            )
            entry["added_in_window"] = True
        elif status in ("D", "R"):
            entry = backlog.setdefault(
                stem,
                {"name": stem, "path": path, "present": False,
                 "added_in_window": False, "removed_in_window": False},
            )
            entry["removed_in_window"] = True
    return backlog


# --- the state layer ------------------------------------------------------

def read_state(root, events):
    """Clause keys in `docs/state/`, and which state files moved in the window.

    Clause keys are what deriving work cites (`docs/state/README.md` rule
    3), so a handover's restatement of intent cites one and the checker
    can tell whether it named a clause that exists.
    """
    docs = []
    keys = {}
    d = root / "docs" / "state"
    if d.is_dir():
        for f in sorted(d.glob("*.md")):
            rel = f.relative_to(root).as_posix()
            text = f.read_text(encoding="utf-8")
            # Only headings. `docs/state/README.md` rule 3 says clause
            # keys live on the headings deriving work cites; scanning the
            # whole body for bracketed lowercase words also harvests the
            # provenance markers (`[inferred]`), and a handover citing
            # `[state inferred]` would resolve against nothing meaningful.
            found = {}
            headings = list(re.finditer(
                r"^(#{2,6})\s*(.+?)\s*\[([a-z0-9][a-z0-9-]*)\](?:\s.*)?$", text, re.M))
            for idx, h in enumerate(headings):
                end = headings[idx + 1].start() if idx + 1 < len(headings) else len(text)
                body = text[h.end():end].strip()
                # The clause's own words, not just its key. Field 1 of the
                # handover restates the milestone in two or three
                # sentences, and the first generated draft said outright
                # that it could not: the ledger handed it keys with no
                # text behind them. A report that cannot restate intent
                # fails the one field the evidence is strongest about —
                # trained humans acting on remembered intent matched it
                # 34% of the time.
                #
                # This is public framework direction by construction:
                # docs/state/README.md draws the line explicitly and keeps
                # the resident's own life out of these documents. Nothing
                # else in docs/ is quoted into the ledger.
                found[h.group(3)] = {
                    "heading": h.group(2),
                    "text": body[:CLAUSE_TEXT_LIMIT],
                    "truncated": len(body) > CLAUSE_TEXT_LIMIT,
                }
            docs.append({"path": rel, "clauses": sorted(found)})
            for k, v in found.items():
                keys.setdefault(k, dict(v, key=k, path=rel))
    changed = sorted({p for _, p, _ in events if p.startswith("docs/state/")})
    return {"documents": docs, "clauses": keys, "changed_in_window": changed}


# --- the forge ------------------------------------------------------------


def gh_json(args, cwd):
    proc = run(["gh", *args], cwd=cwd)
    return json.loads(proc.stdout or "null")


def classify_checks(rollup):
    if not rollup:
        return {"state": "absent", "runs": []}
    runs = []
    for c in rollup:
        name = c.get("name") or c.get("context") or "?"
        conclusion = (c.get("conclusion") or c.get("state") or "").upper()
        # A CheckRun carries `status`; a StatusContext carries only
        # `state`, so defaulting a missing `status` to COMPLETED read a
        # genuinely pending commit status as a finished one and dropped
        # it into "skipped" — a false receipt of the same family as the
        # docs-only "checks green" bug this file already fixed once.
        status = c.get("status")
        if not status:
            status = "PENDING" if conclusion in CHECK_PENDING else "COMPLETED"
        runs.append({"name": name, "status": status, "conclusion": conclusion})
    if any(r["conclusion"] in CHECK_RED for r in runs):
        state = "red"
    elif any(r["status"] not in ("COMPLETED", "") or r["conclusion"] in CHECK_PENDING
             for r in runs):
        state = "pending"
    elif not any(r["conclusion"] == "SUCCESS" for r in runs):
        # Runs exist and not one of them did anything. This is the shape
        # a docs-only pull request has here — check.yml's paths-ignore
        # skips the build gate on prose by design — and reading it as
        # green was a false receipt of exactly the kind this surface
        # exists to prevent: seven merges in the golden window claimed a
        # build gate that never ran. Kept distinct from "absent" (no run
        # was ever created) because the difference is visible to the
        # reader and worth their seeing.
        state = "skipped"
    elif all(r["conclusion"] in CHECK_GREEN for r in runs):
        state = "green"
    else:
        state = "pending"
    return {"state": state, "runs": runs}


def classify_reviews(comments, reviews):
    """Every review round answered, not merely some disposition somewhere.

    Reducing this to two counts — any gate comment, any disposition —
    let a second review round posted *after* the first disposition read
    as answered when nothing had answered it, and the ledger then
    permitted a false "findings dispositioned" receipt. The handler
    workflow explicitly serializes multiple gate comments on one PR, so
    the multi-round case is supported, not hypothetical. A PR is
    dispositioned only when every gate comment has a disposition posted
    strictly after it. Timestamps fail closed: a gate whose timestamp is
    missing counts as unanswered, and a disposition whose timestamp is
    missing answers nothing — the checker then rejects the claim rather
    than passing it unverified.
    """
    events = [((c.get("createdAt") or ""), (c.get("body") or ""))
              for c in (comments or [])]
    events += [((r.get("submittedAt") or r.get("createdAt") or ""),
                (r.get("body") or ""))
               for r in (reviews or [])]
    gates = [t for t, b in events if any(m.search(b) for m in REVIEW_MARKERS)]
    disps = [t for t, b in events if DISPOSITION_MARKER.search(b)]
    if not gates:
        state = "no-review"
    elif all(g and any(d and d > g for d in disps) for g in gates):
        state = "dispositioned"
    else:
        state = "undispositioned"
    return {"state": state, "review_comments": len(gates),
            "disposition_comments": len(disps)}


def read_prs(root, since, until):
    """Every PR that either merged inside the window or is open right now.

    Those two sets are exactly the handover's coverage units: what
    changed (merged) and what is still in flight (open, which is where
    drift shows up). A PR closed unmerged outside the window is neither,
    and is deliberately not carried.
    """
    limit = 500
    listing = gh_json(
        [
            "pr", "list", "--state", "all", "--limit", str(limit),
            "--json", "number,title,state,url,createdAt,mergedAt,closedAt,headRefName,isDraft",
        ],
        cwd=root,
    ) or []
    if len(listing) >= limit:
        # Silent truncation here is the worst failure this file has
        # available: coverage units the handover never had to account
        # for, and a checker that then reports "all cited". Loud, and a
        # hard stop, for the same reason tools/codex-review.sh refuses
        # to be quiet about its own failure modes.
        raise RuntimeError(
            "handover-ledger: `gh pr list` returned %d results, its own limit, so "
            "the listing is truncated and coverage would be silently incomplete. "
            "Raise the limit in read_prs()." % limit
        )
    wanted = []
    for pr in listing:
        merged = pr.get("mergedAt")
        if merged and since <= merged[:10] < until:
            wanted.append(pr)
        elif pr.get("state") == "OPEN":
            wanted.append(pr)
    prs = {}
    for i, pr in enumerate(sorted(wanted, key=lambda p: p["number"]), 1):
        n = pr["number"]
        progress("reading PR #%d (%d/%d)" % (n, i, len(wanted)))
        detail = gh_json(
            [
                "pr", "view", str(n),
                "--json", "number,state,mergedAt,mergeCommit,comments,reviews,"
                          "statusCheckRollup,files,title,url,headRefName,createdAt,isDraft",
            ],
            cwd=root,
        )
        files = [f["path"] for f in (detail.get("files") or [])]
        merge_commit = (detail.get("mergeCommit") or {}).get("oid")
        prs[str(n)] = {
            "number": n,
            "title": detail.get("title"),
            "url": detail.get("url"),
            "state": detail.get("state"),
            "merged": detail.get("state") == "MERGED",
            "draft": bool(detail.get("isDraft")),
            "createdAt": detail.get("createdAt"),
            "mergedAt": detail.get("mergedAt"),
            "headRefName": detail.get("headRefName"),
            "mergeCommit": merge_commit,
            "checks": classify_checks(detail.get("statusCheckRollup")),
            "review": classify_reviews(detail.get("comments"), detail.get("reviews")),
            # The full file list is deliberately not carried. Nothing
            # resolves a citation against it, it is the bulk of a
            # committed fixture, and the one question this surface asks
            # of a diff — did it move current truth, which the brief
            # routes to deliberate review always — is answered by the
            # two fields below.
            "file_count": len(files),
            "state_files": [f for f in files if f.startswith("docs/state/")],
            "touches_state": any(f.startswith("docs/state/") for f in files),
            "merged_in_window": bool(
                detail.get("mergedAt") and since <= detail["mergedAt"][:10] < until
            ),
        }
    return prs


# --- the journal ----------------------------------------------------------


def read_journal(root, since, until, enabled=True):
    """The agent layer's own records, if this machine has a journal.

    Two rules govern what comes back, and both are load-bearing.

    Absence is recorded, never smoothed over: the checker rejects any
    `[journal <id>]` citation it cannot resolve here, so a machine with
    no journal produces a handover that cannot cite one, rather than one
    that cites ids nobody checked.

    And only record *ids* come back — never paths, never bodies, never
    the journal root. A real journal is the private layer: its records
    are the resident's own correspondence and decisions, and its
    directory names their home. CLAUDE.md's hard rule bans every one of
    those from this repo, and a ledger is a file an agent may be about
    to commit. The first run of this script wrote 308 real record ids
    and their absolute paths into a fixture, which is why this docstring
    is longer than the function. `--no-journal` exists for the case that
    matters most — building a fixture that gets committed.
    """
    if not enabled:
        return {"available": False,
                "reason": "journal reading was disabled with --no-journal",
                "records": {}}
    state_dir = os.environ.get("CASTLE_STATE_DIR")
    candidates = []
    if state_dir:
        candidates.append(pathlib.Path(state_dir) / "journal")
    private_root = os.environ.get("CASTLE_PRIVATE_ROOT")
    if private_root:
        candidates.append(pathlib.Path(private_root) / "state" / "journal")
    for c in candidates:
        if c.is_dir():
            records = {}
            for f in sorted(c.rglob("*.md")):
                rid = f.stem
                # Record ids stamp as YYYYMMDDThhmmssZ (`agent/castle`),
                # not as a dashed date. Matching the dashed form instead
                # silently matched nothing, and the window filter below
                # then carried every record the journal had ever held.
                m = re.match(r"^(\d{4})(\d{2})(\d{2})T", rid)
                stamp = "-".join(m.groups()) if m else None
                if stamp is None or not (since <= stamp < until):
                    continue
                records[rid] = {"id": rid, "date": stamp}
            return {"available": True, "records": records}
    return {
        "available": False,
        "reason": "no journal directory found (set CASTLE_STATE_DIR or "
                  "CASTLE_PRIVATE_ROOT to point at one)",
        "records": {},
    }


# --- coverage -------------------------------------------------------------


def coverage_units(prs):
    """What the handover must account for, or be told it omitted.

    A coverage unit is a pull request: merged inside the window, or open
    now. The brief's rule is that every substantive ledger event is
    reflected in some line, so omission is as detectable as fabrication
    — and in this repo every substantive event arrives *as* a pull
    request. Briefs, backlog entries and state patches ride one, so
    counting them separately would demand the same event be narrated
    three times, which fights the one-screenful bound for no gain in
    what the reader can catch.
    """
    units = []
    for n, pr in sorted(prs.items(), key=lambda kv: int(kv[0])):
        if pr["merged_in_window"]:
            kind = "merged-pr"
        elif pr["state"] == "OPEN":
            kind = "open-pr"
        else:
            continue
        units.append({"kind": kind, "id": n, "label": pr["title"]})
    return units


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    today = datetime.date.today()
    # Six days back through today inclusive is seven days. Seven back
    # with an exclusive bound of tomorrow was eight — the documented
    # "last seven days" covered an extra day, and the mirrored default
    # in tools/handover.sh did the same.
    ap.add_argument("--since", default=str(today - datetime.timedelta(days=6)))
    ap.add_argument("--until", default=str(today + datetime.timedelta(days=1)),
                    help="exclusive upper bound (default: tomorrow)")
    ap.add_argument("--repo-root", default=None)
    ap.add_argument("--no-journal", action="store_true",
                    help="do not read the journal at all. Use this whenever the "
                         "ledger is going to be committed: journal records are "
                         "private-layer artifacts and this repo may not carry them")
    ap.add_argument("--no-forge", action="store_true",
                    help="skip `gh` entirely; the ledger then carries no PRs "
                         "and no coverage units, which the checker will say so about")
    ap.add_argument("-o", "--output", default="-")
    args = ap.parse_args(argv)

    root = pathlib.Path(
        args.repo_root
        or run(["git", "rev-parse", "--show-toplevel"]).stdout.strip()
    ).resolve()

    events = git_path_events(
        root, args.since, args.until,
        ["docs/tasks", "docs/backlog", "docs/state"],
    )
    progress("reading git history %s..%s" % (args.since, args.until))
    commits = git_commits(root, args.since, args.until)
    prs = {} if args.no_forge else read_prs(root, args.since, args.until)

    ledger = {
        "schema": SCHEMA,
        "window": {"since": args.since, "until": args.until},
        "generated_from": {
            "head": run(["git", "rev-parse", "HEAD"], cwd=root).stdout.strip(),
            "branch": run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=root).stdout.strip(),
        },
        "forge": {"read": not args.no_forge},
        "state": read_state(root, events),
        "tasks": read_tasks(root, events),
        "backlog": read_backlog(root, events),
        "commits": commits,
        "prs": prs,
        "journal": read_journal(root, args.since, args.until,
                                 enabled=not args.no_journal),
    }
    ledger["coverage_units"] = coverage_units(prs)

    text = json.dumps(ledger, indent=2, sort_keys=True) + "\n"
    if args.output == "-":
        sys.stdout.write(text)
    else:
        pathlib.Path(args.output).write_text(text, encoding="utf-8")
        progress("wrote %s (%d PRs, %d coverage units)"
                 % (args.output, len(prs), len(ledger["coverage_units"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
