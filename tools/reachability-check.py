#!/usr/bin/env python3
"""tools/reachability-check.py — the detector task 0072 owes (an incident
ships its detector, CLAUDE.md).

THE INCIDENT

Task 0070 built the task-outcome log, its checker, and a coverage gate
that fails any task pull request whose brief has no row. It shipped
`derive` — the thing that writes rows — with no caller. Every test
passed. The gate was armed against a pipeline nothing fed, so the next
task's pull request would have failed CI for a reason having nothing to
do with that task.

Two mechanical shapes fell out of it, and this lint is both:

  ORPHAN ENTRYPOINT      a subcommand a tool exposes that nothing calls
                         — or, for a tool with no subcommand tree at
                         all (every `.sh` script, every single-command
                         Python tool), the tool itself that nothing
                         calls.
  ARMED GATE, NO FEEDER  a CI check over an artifact that no named step
                         produces — whether the checker is an argparse
                         `check` subcommand or a standalone script a
                         workflow runs directly.

WHAT COUNTS AS A TOOL, AND WHAT COUNTS AS A CALLER

Every executable under `tools/` is a tool: `.py`, `.sh`, and
extensionless files with a Python shebang all get read for an argparse
subcommand tree; anything without one — most of them — gets a single
bare entrypoint, keyed by its path alone, so it still needs a caller.

Operational callers: a workflow under `.github/`, another executable
under `tools/` (a string passed to a call — `subprocess.run(["tools/x/x",
"sub"])` — counts the same as a bare name), or a documented step that
declares itself with

    <!-- invokes: tools/outcomes/outcomes derive -->

in the document that owns the step.

A **test** does not count. The 0070 miss was precisely a command that
worked, was covered by tests, and was reachable by nobody; if a test
satisfied reachability this lint would have passed the very incident it
exists for. A **usage synopsis** does not count either — `tools/README.md`
lists every command by construction, so accepting a mention there would
accept everything. Nor does a tool's own prose: a docstring or comment
that merely names an invocation is not a call to it. The explicit marker
is what separates a step somebody owns from a line in a reference table.

WHAT THIS LINT IS NOT

It catches the mechanical shape of the 0070 miss. It cannot catch the
cause, which is that a feature satisfied its implementer's reading of
the requirement and not the resident's. That is acceptance —
`docs/backlog/passing-tests-are-not-acceptance.md` — and no lint will
ever be it. This is a floor under reading the diff, not a substitute.

A NAMED GAP

The feeder rule fires on a workflow that invokes a checker directly —
an argparse `check` subcommand, or a standalone script whose filename
stem is `check` or ends `-check`. A gate reached only through a test
wrapper is out of its reach either way: the wrapper's own fixture
checks are indistinguishable, from here, from a check over the
repository's committed artifacts. Naming the gap rather than papering
it: a gate hidden behind a wrapper is still an unfed gate, and this
lint will not say so. (This repository's own `handover-check.py` and
`reachability-check.py` are both this shape today — each reached only
through `test/*/run.sh` — which is why widening the rule to standalone
checkers did not, on its own, newly arm either of them.)

Stdlib only, no network, no model — same contract as everything else in
this directory.
"""

import ast
import pathlib
import re
import sys

# Directories whose files may satisfy reachability. `test/` is absent on
# purpose; see the header.
OPERATIONAL_DIRS = (".github", "tools")

# Files a caller could plausibly be, anywhere under those directories.
CALLER_SUFFIXES = (".yml", ".yaml", ".sh", ".py", "")

INVOKES_RE = re.compile(r"<!--\s*invokes:\s*(.+?)\s*-->")

# Directories whose markdown is a *record* rather than an instruction
# surface, and so cannot make anything reachable. A brief describes what
# was built on one branch at one time; nobody operates from it, and a
# marker copied into one — from the brief that introduced the marker, say
# — would satisfy the orphan rule for a command nothing runs. That is
# the exact shape this lint exists to catch, arriving through the lint's
# own mechanism.
RECORD_DIRS = ("docs/tasks", "docs/backlog", "docs/research")
FEEDER_RE = re.compile(r"#\s*feeder:\s*(.+?)\s*\((.+?)\)\s*$")


def is_executable_tool(path):
    return (path.is_file() and path.suffix in (".py", ".sh", "")
            and not path.name.startswith("."))


def is_python_tool(path, text):
    """Would `ast.parse` plausibly succeed? Checked before parsing so a
    shell script's syntax never reaches the parser — `entrypoints`
    crashing on a `.sh` file would take the whole lint down with it.
    """
    if path.suffix == ".py":
        return True
    if path.suffix:
        return False
    first_line = text.splitlines()[0] if text else ""
    return first_line.startswith("#!") and "python" in first_line


def find_tools(root):
    """Every executable under tools/. What each exposes is decided later
    by `entrypoints`: a tool with an argparse subcommand tree keeps its
    subcommands, everything else — including every single-command tool
    and every `.sh` script — gets one bare entrypoint (task 0076). A
    tool skipped here is invisible to the lint entirely, so this list
    must not be narrower than "every tool a resident could run."
    """
    out = []
    for path in sorted((root / "tools").rglob("*")):
        if not is_executable_tool(path):
            continue
        try:
            path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        out.append(path)
    return out


def entrypoints(path, text):
    """The subcommand paths a tool exposes, read out of its argparse tree.

    Read with `ast` rather than a regular expression because the nesting
    is the part that matters: `clarify probe build` is one entrypoint
    and `clarify probe` is a group, and a lint that flagged the group
    would demand a caller for something nobody can call.

    Nodes are processed in source order — `ast.walk` is breadth-first,
    which would see a parser used before the assignment that named it.

    A tool with no argparse subcommand tree — every `.sh` script, and
    every single-command Python tool like `handover-ledger.py` — gets
    one bare entrypoint instead: `()`, the empty command path. That is
    what lets `main` key it by the tool's path alone, with nothing to
    call it demands the tool itself be named by a caller. A `.py` file
    that fails to parse gets the same bare fallback rather than crashing
    the lint outright (task 0076: `find_tools` no longer pre-filters by
    `add_subparsers`, so this is reached by every `.py` under `tools/`,
    not just tools already known to be argparse-shaped).
    """
    if not is_python_tool(path, text):
        return [()]
    try:
        tree = ast.parse(text, filename=str(path))
    except (SyntaxError, ValueError):
        return [()]
    parsers = {}       # variable -> the command path it holds
    groups = {}        # variable -> the command path its parsers hang under
    seen = set()       # every command path added
    grouped = set()    # every command path that turned out to be a group

    nodes = sorted(
        (n for n in ast.walk(tree)
         if isinstance(n, (ast.Assign, ast.Call)) and hasattr(n, "lineno")),
        key=lambda n: (n.lineno, n.col_offset),
    )
    for node in nodes:
        call = node.value if isinstance(node, ast.Assign) else node
        if not isinstance(call, ast.Call):
            continue
        target = None
        if isinstance(node, ast.Assign) and len(node.targets) == 1 \
                and isinstance(node.targets[0], ast.Name):
            target = node.targets[0].id
        func = call.func
        name = func.attr if isinstance(func, ast.Attribute) else \
            (func.id if isinstance(func, ast.Name) else None)
        if name == "ArgumentParser":
            if target:
                parsers[target] = ()
        elif name == "add_subparsers" and isinstance(func, ast.Attribute) \
                and isinstance(func.value, ast.Name):
            owner = parsers.get(func.value.id)
            if owner is None:
                continue
            grouped.add(owner)
            if target:
                groups[target] = owner
        elif name == "add_parser" and isinstance(func, ast.Attribute) \
                and isinstance(func.value, ast.Name) and call.args:
            arg = call.args[0]
            if not isinstance(arg, ast.Constant) or not isinstance(arg.value, str):
                continue
            prefix = groups.get(func.value.id)
            if prefix is None:
                continue
            command = prefix + (arg.value,)
            seen.add(command)
            if target:
                parsers[target] = command
    commands = sorted(seen - grouped)
    return commands if commands else [()]


def logical_lines(text):
    """Lines, with shell/YAML backslash continuations joined."""
    out = []
    buf = ""
    for line in text.splitlines():
        if line.rstrip().endswith("\\"):
            buf += line.rstrip()[:-1] + " "
            continue
        out.append(buf + line)
        buf = ""
    if buf:
        out.append(buf)
    return out


def aliases(text, relpath, name):
    """Every spelling this file uses to name the tool.

    A test or a script almost always binds the path to a variable first
    (`OUTCOMES="$REPO_ROOT/tools/outcomes/outcomes"`), so matching the
    literal path alone would miss every real caller.
    """
    found = {relpath, name}
    for line in text.splitlines():
        m = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)=(.+)$", line.strip())
        if m and (relpath in m.group(2) or f"/{name}" in m.group(2)):
            found.add(f"${m.group(1)}")
            found.add(f"${{{m.group(1)}}}")
    return found


def call_argument_strings(tree):
    """Source ranges of string constants that name a call's arguments.

    Direct arguments, and strings one level inside a list/tuple/set
    literal that is itself an argument — the shape of
    `subprocess.run(["tools/outcomes/outcomes", "derive"])`. Anything
    deeper, or a string that is not part of a call at all (a docstring,
    a bare expression statement, comment prose), is not collected here
    and so stays stripped by `code_only` below.

    A *range*, not a single position: Python merges adjacent string
    literals — `"tools/outcomes/" "outcomes"` — into one `Constant`
    spanning both, so keeping only the constant's own start position
    would still let `code_only` strip the second fragment's own STRING
    token. Any token whose start falls inside a kept range counts.

    A NAMED GAP: `cmd = ["tools/outcomes/outcomes", "derive"];
    subprocess.run(cmd)` — the list built in one statement and passed
    by name in the next — is invisible here. This walks each call's
    own argument expressions; it does not trace what a variable was
    last assigned. Closing that needs data-flow, not another AST
    pattern, and is out of this pass's scope.
    """
    keep = []

    def literal(node):
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            keep.append(((node.lineno, node.col_offset),
                         (node.end_lineno, node.end_col_offset)))
        elif isinstance(node, (ast.List, ast.Tuple, ast.Set)):
            for elt in node.elts:
                literal(elt)

    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            for arg in node.args:
                literal(arg)
            for kw in node.keywords:
                literal(kw.value)
    return keep


def code_only(path, text):
    """The file with its comments removed, and its string literals
    removed except where they name a call's argument.

    Without the comment/docstring exclusion a tool's own prose counts as
    a call: this lint's header names `tools/outcomes/outcomes derive` as
    its worked example, and on the first run that example alone rescued
    the very orphan the example is about. A lint that can be satisfied
    by describing the problem is not a lint.

    But blanket-stripping every string also hides a real caller: a
    `subprocess.run(["tools/outcomes/outcomes", "derive"])` has its path
    and subcommand tokens removed before `invokes()` ever sees them,
    which is the false-positive direction the module header says this
    lint avoids. `call_argument_strings` keeps exactly the strings a
    call could plausibly be naming and drops the rest, so a docstring or
    a comment mentioning the same invocation still does not count.
    """
    if path.suffix == ".py":
        try:
            tree = ast.parse(text, filename=str(path))
        except (SyntaxError, ValueError):
            tree = None
        keep = call_argument_strings(tree) if tree is not None else []
        try:
            import io
            import tokenize as tk
            out = []
            for tok in tk.generate_tokens(io.StringIO(text).readline):
                if tok.type == tk.COMMENT:
                    continue
                if tok.type == tk.STRING and not any(
                        start <= tok.start < end for start, end in keep):
                    continue
                out.append((tok.start[0], tok.string))
        except (tk.TokenError, IndentationError, SyntaxError):
            return text
        lines = {}
        for lineno, piece in out:
            lines.setdefault(lineno, []).append(piece)
        return "\n".join(" ".join(v) for _, v in sorted(lines.items()))
    # Shell and YAML: a comment runs from an unquoted `#` to end of line,
    # and that is close enough — the cost of being crude here is a
    # missed orphan, never a false accusation.
    out = []
    for line in text.splitlines():
        cut = re.search(r"(?:^|\s)#", line)
        out.append(line[:cut.start()] if cut else line)
    return "\n".join(out)


def tokens(line):
    for ch in "\"'":
        line = line.replace(ch, " ")
    return line.split()


def invokes(text, relpath, name, command):
    """Does this file call `<tool> <command...>`?

    Deliberately loose about what sits between the tool and its
    subcommand: flags, their values, and `python3` in front are all
    normal. The failure direction is chosen — a false match makes the
    lint miss an orphan, a false miss would make it demand a caller for
    something already called, and only the second one stops the tree
    building for a reason that is not true.
    """
    names = aliases(text, relpath, name)
    for line in logical_lines(text):
        toks = tokens(line)
        for i, tok in enumerate(toks):
            bare = tok.strip("${}")
            if not (tok in names or f"${bare}" in names
                    or tok == relpath or tok.endswith("/" + name) or tok == name):
                continue
            rest = [t for t in toks[i + 1:] if not t.startswith("-")]
            it = iter(rest)
            if all(any(t == word for t in it) for word in command):
                return True
    return False


def spec_key(rel, command):
    """The string a marker or feeder line has to match exactly.

    A bare entrypoint (`command == ()`) keys as the path alone, with no
    trailing space — `' '.join(())` is `''`, and `f"{rel} "` would leave
    one, which would never match a marker written as
    `<!-- invokes: tools/x/x -->` (rendering strips it, but the spec
    string this lint compares against does not).
    """
    return rel if not command else f"{rel} {' '.join(command)}"


def caller_files(root):
    for d in OPERATIONAL_DIRS:
        base = root / d
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*")):
            if path.is_file() and path.suffix in CALLER_SUFFIXES:
                yield path


def marked_invocations(root):
    """Every `invokes:` marker on an instruction surface, as {spec: [paths]}.

    Records are excluded; see RECORD_DIRS.
    """
    out = {}
    for path in sorted(root.rglob("*.md")):
        if ".git" in path.parts:
            continue
        rel = path.relative_to(root).as_posix()
        if any(rel.startswith(d + "/") for d in RECORD_DIRS):
            continue
        for m in INVOKES_RE.finditer(path.read_text(encoding="utf-8")):
            out.setdefault(" ".join(m.group(1).split()), []).append(path)
    return out


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    root = pathlib.Path(argv[0] if argv else ".").resolve()
    problems = []

    specs = {}
    for tool in find_tools(root):
        text = tool.read_text(encoding="utf-8")
        rel = str(tool.relative_to(root))
        for command in entrypoints(tool, text):
            specs[spec_key(rel, command)] = (tool, rel, command)
    if not specs:
        print("no tool entrypoints found; is this the repository root?",
              file=sys.stderr)
        return 2

    markers = marked_invocations(root)
    for spec, paths in sorted(markers.items()):
        if spec not in specs:
            for path in paths:
                problems.append(
                    f"{path.relative_to(root)}: `invokes: {spec}` names no "
                    "entrypoint any tool exposes; a citation that resolves to "
                    "nothing is worse than none"
                )

    callers = {spec: [] for spec in specs}
    files = list(caller_files(root))
    # code_only's output depends only on the file, never on which spec
    # is being checked against it — computed once per file rather than
    # once per (spec, file) pair, which Change 2 made a much bigger
    # product by giving every single-command tool its own spec.
    stripped = {}
    for path in files:
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        stripped[path] = code_only(path, text)
    for spec, (tool, rel, command) in sorted(specs.items()):
        for path, code in stripped.items():
            if path == tool:
                continue
            if invokes(code, rel, tool.name, command):
                callers[spec].append(path)
        for path in markers.get(spec, []):
            callers[spec].append(path)
        if not callers[spec]:
            label = " ".join(command) if command else rel
            noun = "subcommand" if command else "tool"
            problems.append(
                f"{rel}: `{label}` has no operational caller — no "
                "workflow, no other tool, and no documented step declaring "
                f"`<!-- invokes: {spec} -->`. A {noun} nothing invokes is "
                "the shape of task 0070's miss; give it a caller or delete it."
            )

    # The second rule: a gate that runs a checker must name what feeds it.
    # A checker is either an argparse subcommand named `check` (the
    # original shape) or a standalone tool — the bare entrypoint Change
    # 2 above gives every non-argparse tool — whose filename says the
    # same thing: stem `check`, or a stem ending `-check`
    # (`handover-check.py`, `reachability-check.py`). Task 0076: the
    # armed-gate rule used to see only the first shape, which is the
    # repo's own `tools/handover-check.py` run straight from a workflow.
    def is_checker(tool, command):
        if command:
            return command[-1] == "check"
        return tool.stem == "check" or tool.stem.endswith("-check")

    for path in sorted((root / ".github").rglob("*.y*ml")) if (root / ".github").is_dir() else []:
        text = path.read_text(encoding="utf-8")
        code = code_only(path, text)
        gated = [spec for spec, (tool, rel, command) in sorted(specs.items())
                 if is_checker(tool, command)
                 and invokes(code, rel, tool.name, command)]
        if not gated:
            continue
        feeders = [m for m in (FEEDER_RE.search(line) for line in text.splitlines()) if m]
        if not feeders:
            problems.append(
                f"{path.relative_to(root)}: runs {', '.join('`' + g + '`' for g in gated)} "
                "and names nothing that feeds it. Add a `# feeder: <tools/x/x sub> "
                "(<path>)` line naming the step that produces what this gate "
                "checks — an armed gate with no feeder fails every pull request "
                "for a reason that is not the pull request's."
            )
            continue
        for m in feeders:
            spec, location = " ".join(m.group(1).split()), m.group(2).strip()
            if spec not in specs:
                problems.append(
                    f"{path.relative_to(root)}: feeder `{spec}` is not an "
                    "entrypoint any tool exposes"
                )
                continue
            target = root / location
            if not target.is_file():
                problems.append(
                    f"{path.relative_to(root)}: feeder cites {location}, which "
                    "is not a file here"
                )
            elif target not in markers.get(spec, []):
                problems.append(
                    f"{path.relative_to(root)}: feeder cites {location}, which "
                    f"carries no `<!-- invokes: {spec} -->` marker; the citation "
                    "has to resolve to the step, not merely to a document"
                )

    if problems:
        for p in problems:
            print(p, file=sys.stderr)
        print(f"\n{len(problems)} problem(s). tools/reachability-check.py's "
              "header says what each rule is for.", file=sys.stderr)
        return 1
    print(f"ok: {len(specs)} entrypoints, every one of them reachable")
    return 0


if __name__ == "__main__":
    sys.exit(main())
