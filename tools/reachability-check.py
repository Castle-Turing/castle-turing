#!/usr/bin/env python3
"""tools/reachability-check.py — the detector for task 0072.

WHAT THIS CATCHES, AND WHAT IT CANNOT

The incident: task 0070 shipped a working tool, a full test suite, and a
required CI gate, and every one of them passed — while nothing in the
repository ever *called* the half of the tool that writes rows. The gate
was armed against a pipeline that fed it nothing. "Logging is running"
was true of the code and false of the system.

Two mechanical shapes of that failure are checkable, and this checks
them:

  1. **Orphan entrypoint.** A subcommand of a tool under `tools/` that
     nothing outside the tool's own source and its own tests ever
     invokes. Two exclusions carry most of the weight, and both were
     chosen by running this lint against the tree 0070 left behind:

     *Tests do not count.* The 0070 miss had thorough tests for `derive`
     and no caller. A lint that accepted a test would have passed the
     exact tree that produced the incident.

     *A synopsis does not count.* `tools/README.md` listed `derive`'s
     usage the whole time, placeholders and all. A caller is a line
     someone could paste and run — so a line carrying an unfilled
     `[optional]` or a bare `FILE`/`DIR`/`KEY` placeholder is
     documentation of the interface, not a use of it, and a mention in
     running prose is neither.

  2. **Armed gate with no named feeder.** A workflow that runs one of
     those tools is a gate on some artifact; it must say, in a `Feeder:`
     line in its header comment, what produces that artifact — and the
     path it names must exist. A gate whose feeder cannot be named is
     one nobody has checked is fed.

     The check stops at the path. Whether the *subcommand* a feeder line
     names is real is already rule 1's job — every subcommand needs a
     caller — and going further here would mean deciding whether the
     word after a tool path is a subcommand or the next word of an
     English sentence, which is a guess. The declaration is the point:
     a gate whose author could not name a feeder has told you something
     before any path is resolved.

WHAT THIS IS NOT

It is not acceptance. The 0070 miss was not really "a function with no
caller" — it was "a feature that did not do, for the resident, the thing
the resident meant". No lint reads intent. Whether a shipped thing is
reachable *in the way its user needs* is
`docs/backlog/passing-tests-are-not-acceptance.md`'s problem, and its
answer is acceptance criteria that assert reachability rather than only
correctness. This catches the mechanical silhouette of that miss, which
is worth catching because it is free, and stops there.

Stdlib only, no network, no model, and a pure function of the working
tree — the same contract `tools/outcomes/outcomes check` holds, for the
same reason: a check that consulted the live world would go red for
reasons that have nothing to do with what it checks.

USAGE

    tools/reachability-check.py [--repo-root DIR]

Exits non-zero having printed every problem it found.
"""

import argparse
import pathlib
import re
import sys

# Where a caller may live. `test/` is absent on purpose — see the header.
# So is the tool's own source file, which is excluded per-tool below.
CALLER_ROOTS = (
    ".github/workflows",
    "docs",
    "tools",
    "agent",
    "modules",
    "hosts",
    "scripts",
    ".claude",
)

# Text files only. A caller hiding in a binary is not a caller anyone
# can read, and this repository has no compiled artifacts anyway.
CALLER_SUFFIXES = {".yml", ".yaml", ".md", ".sh", ".py", ".nix", ".json",
                   ".toml", ".txt", ""}

# A subcommand named here is declared unreachable on purpose, with the
# reason as the value. The reason is the point: a bare allowlist would
# let the next 0070 be silenced by adding one line, whereas a sentence
# someone had to write is a thing review can disagree with. Keep it
# empty if you can.
DECLARED_UNREACHABLE = {}

ADD_PARSER_RE = re.compile(r"""add_parser\(\s*["']([a-z][a-z0-9-]*)["']""")

# `Feeder:` in a comment, anywhere in the file's first 60 lines.
FEEDER_RE = re.compile(r"^\s*#\s*Feeder:\s*(.+?)\s*$")

# What a Feeder line may name: a path in the repository, or an
# invocation of a tool. Either way it has to resolve to something real.
PATH_RE = re.compile(r"(?<![\w./-])((?:\.github|docs|tools|test|agent|modules|hosts|scripts)/[\w./-]+)")

NONE_PREFIX = "none —"
NONE_REASON_MIN = 30


def is_python_tool(path):
    if not path.is_file():
        return False
    if path.suffix not in ("", ".py"):
        return False
    try:
        first = path.open("rb").readline().decode("utf-8", "replace")
    except OSError:
        return False
    return first.startswith("#!") and "python" in first


def tools_under(root):
    """Every argparse-based Python tool under tools/, and its subcommands."""
    found = {}
    base = root / "tools"
    if not base.is_dir():
        return found
    for path in sorted(base.rglob("*")):
        if not is_python_tool(path):
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        subs = sorted(set(ADD_PARSER_RE.findall(text)))
        if subs:
            found[path] = subs
    return found


def caller_files(root, exclude):
    for rel in CALLER_ROOTS:
        d = root / rel
        if not d.is_dir():
            continue
        for path in sorted(d.rglob("*")):
            if not path.is_file() or path in exclude:
                continue
            if path.suffix not in CALLER_SUFFIXES:
                continue
            yield path


# What disqualifies a line from being a caller: it is describing the
# interface rather than using it. `[--env KEY]` is a synopsis; `--env e1`
# is a command.
# `$SHOUTY` is a shell variable in a real command; a bare `SHOUTY` is a
# hole the reader is meant to fill.
PLACEHOLDER_RE = re.compile(r"\[|(?<![$\w{])[A-Z][A-Z0-9_]{2,}\b|\.\.\.")

# A command starts a line, or follows something that starts a command.
# A path introduced by a backtick mid-sentence is prose about the tool.
COMMAND_LEAD_RE = re.compile(r"(?:^|[$;|(]|&&|\brun:\s*|^\s*[-*]\s+)\s*$")


def callers_of(root, tool, sub):
    """Lines that invoke `<tool-path> … <sub>` as a runnable command.

    The tool is matched by its repository path, not its basename: a
    workflow called `clarify-check` otherwise "calls" `clarify check` on
    its own `name:` line, which is how a lint quietly starts passing
    everything.

    A runbook sentence that says to run
    `tools/outcomes/outcomes derive --fill --env e1` counts, and so does
    a shell line in a workflow — "a workflow, hook, runbook, or other
    script", per the brief. Both look the same to this, which is why one
    rule covers both.
    """
    rel_tool = str(tool.relative_to(root))
    pattern = re.compile(
        rf"(?P<lead>.*?){re.escape(rel_tool)}[^\n]{{0,160}}?\b{re.escape(sub)}\b"
    )
    hits = []
    for path in caller_files(root, exclude={tool, root / "tools/reachability-check.py"}):
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for n, line in enumerate(text.splitlines(), start=1):
            m = pattern.search(line)
            if not m:
                continue
            if not COMMAND_LEAD_RE.search(m.group("lead")):
                continue
            if PLACEHOLDER_RE.search(line[m.start():]):
                continue
            hits.append(f"{path.relative_to(root)}:{n}")
    return hits


def check_orphans(root, tools, problems, notes):
    for tool, subs in sorted(tools.items()):
        rel = tool.relative_to(root)
        for sub in subs:
            declared = DECLARED_UNREACHABLE.get(f"{tool.name} {sub}")
            hits = callers_of(root, tool, sub)
            if hits:
                if declared:
                    problems.append(
                        f"{rel}: `{sub}` is declared unreachable and is called at "
                        f"{hits[0]}; delete the declaration rather than keeping a "
                        "stale reason next to a live caller"
                    )
                else:
                    notes.append(f"{rel} {sub}: called from {hits[0]}"
                                 + (f" (+{len(hits) - 1} more)" if len(hits) > 1 else ""))
                continue
            if declared:
                notes.append(f"{rel} {sub}: declared unreachable — {declared}")
                continue
            problems.append(
                f"{rel}: subcommand `{sub}` has no caller outside its own source "
                "and its own tests. Wire it to a workflow, a hook, a runbook step "
                "or another script, or declare it unreachable with a reason in "
                "DECLARED_UNREACHABLE. See docs/tasks/0072-wire-the-outcome-log-"
                "and-its-redirects.md."
            )


def gate_workflows(root, tools):
    """Workflows that run a tool under tools/. Those are the armed gates."""
    wf_dir = root / ".github" / "workflows"
    if not wf_dir.is_dir():
        return {}
    stems = {t.name for t in tools}
    found = {}
    for path in sorted(wf_dir.glob("*.yml")):
        text = path.read_text(encoding="utf-8")
        named = {s for s in stems if re.search(rf"tools/[\w/-]*{re.escape(s)}\b", text)}
        if named:
            found[path] = sorted(named)
    return found


def check_feeders(root, tools, problems, notes):
    for path, named in sorted(gate_workflows(root, tools).items()):
        rel = path.relative_to(root)
        head = path.read_text(encoding="utf-8").splitlines()[:60]
        declared = [m.group(1) for m in (FEEDER_RE.match(l) for l in head) if m]
        if not declared:
            problems.append(
                f"{rel}: runs {', '.join(named)} but names no `# Feeder:` in its "
                "header comment. A gate must say what produces the artifact it "
                "gates; an unfed gate fails every pull request after the first."
            )
            continue
        for value in declared:
            if value.startswith(NONE_PREFIX):
                reason = value[len(NONE_PREFIX):].strip()
                if len(reason) < NONE_REASON_MIN:
                    problems.append(
                        f"{rel}: `Feeder: none —` with no reason after it. "
                        "Blank is not an answer (CLAUDE.md)."
                    )
                else:
                    notes.append(f"{rel}: gates nothing fed — {reason}")
                continue
            paths = PATH_RE.findall(value)
            if not paths:
                problems.append(
                    f"{rel}: `Feeder: {value}` names no path in this repository. "
                    "Name the file or command that writes what this gate checks, "
                    "or say `Feeder: none — <why>`."
                )
                continue
            missing = [p for p in paths if not (root / p).exists()]
            if missing:
                problems.append(
                    f"{rel}: `Feeder:` names {', '.join(missing)}, which "
                    "does not exist"
                )
            else:
                notes.append(f"{rel}: fed by {', '.join(paths)}")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--repo-root", default=".",
                    help="repository to read (default: the current directory)")
    ap.add_argument("-q", "--quiet", action="store_true",
                    help="print problems only")
    args = ap.parse_args(argv)
    root = pathlib.Path(args.repo_root).resolve()

    tools = tools_under(root)
    problems, notes = [], []
    check_orphans(root, tools, problems, notes)
    check_feeders(root, tools, problems, notes)

    if not args.quiet:
        for note in notes:
            print(note)
    if problems:
        print(file=sys.stderr)
        for p in problems:
            print(p, file=sys.stderr)
        print(f"\n{len(problems)} problem(s): something was built that nothing "
              "calls, or a gate nothing feeds.", file=sys.stderr)
        return 1
    total = sum(len(s) for s in tools.values())
    print(f"ok: {total} subcommand(s) across {len(tools)} tool(s) reachable; "
          f"{len(gate_workflows(root, tools))} gate(s) name a feeder")
    return 0


if __name__ == "__main__":
    sys.exit(main())
