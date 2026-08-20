#!/usr/bin/env python3
"""check_pointer_file.py -- keep an always-on CLAUDE.md a POINTER, mechanically.

THE ARCHITECTURE THIS ENFORCES

    An always-on instruction file is loaded in full, every turn, for every task. So the working
    pattern is to keep the substance in gated files -- rules that load on a path glob, skills,
    memory -- and let the always-on file say only where those are.

    The reason is not tidiness, and it is not token budget. It is that the always-on file is
    typically host configuration: outside the repository it describes, unreadable by CI, and
    impossible to diff against the system it documents. A rule kept there drifts silently, and
    BOTH copies read as authoritative afterwards. Nothing compares them, so nobody finds out.

    Which is the whole problem with the convention "keep it a pointer": it is advice, and advice
    is what drifted in the first place. This is the check.

WHAT IT ASSERTS -- three properties a script can actually hold

    1. EVERY POINTER RESOLVES.     A pointer at a file that does not exist is worse than no
                                   pointer: it reads as a promise that the detail is somewhere.
    2. NOTHING IS DUPLICATED.      No substantive line in the always-on file restates a line from
                                   a gated rules file. This is the drift itself, caught at the
                                   moment somebody copies content up.
    3. IT IS INSIDE ITS BUDGET.    A budget YOU set -- this tool does not know or claim any
                                   platform limit, and inventing one would be exactly the kind of
                                   undated harness assertion the rest of this pack exists to stop.

    What it cannot assert is whether a given rule BELONGS in the always-on file. That is a
    judgement about where a rule bites, and no script will ever make it. Stated here rather than
    implied, so a green run is not mistaken for the file being well designed.

USAGE
    python check_pointer_file.py CLAUDE.md --rules-dir .claude/rules
    python check_pointer_file.py CLAUDE.md --rules-dir .claude/rules --max-lines 120
    python check_pointer_file.py --self-test        # the negative controls; writes only to temp

EXIT CONTRACT
    0  every check ran and passed
    1  a check FAILED, or a check ran and measured nothing (INCONCLUSIVE), or the target file
       could not be read
    2  --rules-dir was not given or holds no rules files, so the duplication check does not apply
       here. That is a scope fact, not a defect -- and still never a pass.

    "I could not run this" and "it ran and found nothing" must not share an exit code, so the
    empty-rules-dir case is 2 while an empty always-on FILE is 1: one is an architecture you are
    not using, the other is a check with nothing to check.

STDLIB ONLY. Python 3.8+.
"""
from __future__ import annotations

import argparse
import difflib
import functools
import re
import sys
import tempfile
from pathlib import Path

print = functools.partial(print, flush=True)  # noqa: A001

EXIT_OK, EXIT_FAIL, EXIT_NOT_APPLICABLE = 0, 1, 2

# The line default is the documented TARGET (see README.md and the pin behind it), not a limit:
# an always-on file is loaded in full however long it is, so nothing truncates and the cost is
# adherence rather than a cliff. The byte default is a convention with no source, and is called
# that here rather than dressed up -- a number invented in this file and quoted as a platform
# limit would be exactly the undated harness claim the rest of this pack exists to stop.
DEFAULT_MAX_LINES = 200      # documented target
DEFAULT_MAX_BYTES = 16_000   # a convention, not a limit; override it

# A line short enough to be boilerplate ("## Setup", "- yes") will collide across any two
# documents. Only lines with real substance are compared, or the duplication check becomes noise
# and gets ignored -- which is worse than not running it.
MIN_SUBSTANTIVE_CHARS = 45
SIMILARITY = 0.90

# Path-shaped tokens inside backticks. Four shapes are excluded, and each exclusion was earned by
# a false positive on a real file rather than guessed at:
#   <angle brackets>  a placeholder is the whole point of a template
#   * or ?            a glob describes a SET of paths; `stacks/**` names no file to resolve
#   a bare extension  "`.sql`, `.py`" in prose names file TYPES, not files
#   ~ $ http(s)://    host config, variables and URLs, none of which a path check can resolve
# Over-flagging here is not a harmless default: a check that cries wolf about prose is one people
# learn to skim, and then it is worth less than nothing.
_BACKTICKED = re.compile(r"`([^`\n]+)`")
_LOOKS_LIKE_PATH = re.compile(r"[/\\]|\.(md|py|ps1|json|ya?ml|txt|sql|toml|cfg|ini)$")
_BARE_EXTENSION = re.compile(r"^\.\w+$")


def _norm(line: str) -> str:
    """Collapse away everything that changes when a sentence is copied and lightly reworded."""
    s = line.strip().lower()
    s = re.sub(r"^[\s>\-*\d.#|]+", "", s)          # list bullets, headings, table pipes
    s = re.sub(r"[`*_~]", "", s)                    # inline markdown emphasis
    s = re.sub(r"\s+", " ", s)
    return s.strip()


def substantive_lines(text: str) -> "list[tuple[int, str, str]]":
    out = []
    for i, raw in enumerate(text.splitlines(), start=1):
        n = _norm(raw)
        if len(n) >= MIN_SUBSTANTIVE_CHARS:
            out.append((i, raw.strip(), n))
    return out


def pointer_tokens(text: str) -> "list[tuple[int, str]]":
    out = []
    for i, raw in enumerate(text.splitlines(), start=1):
        # A fenced-code line is an invocation example, not a promise about the tree.
        for tok in _BACKTICKED.findall(raw):
            tok = tok.strip()
            if not tok or "<" in tok or ">" in tok:
                continue
            if tok.startswith(("http://", "https://", "~", "$")):
                continue
            if "*" in tok or "?" in tok:
                continue
            tok = tok.split("#")[0].split()[0].rstrip(",.;:").strip("'\"")
            if not tok or _BARE_EXTENSION.match(tok):
                continue
            if _LOOKS_LIKE_PATH.search(tok):
                out.append((i, tok))
    return out


def resolution_bases(target: Path, rules_dir: "Path | None", base: "Path | None") -> "list[Path]":
    """Where a pointer may legitimately resolve from.

    An always-on file routinely lives OUTSIDE the tree it points at -- that is the normal case for
    host configuration, and it is half the reason the architecture exists. Resolving only against
    the file's own directory would therefore report every correct pointer as broken, which is the
    same over-flagging failure as above wearing a different hat.
    """
    bases = [target.resolve().parent]
    if base:
        bases.append(base.resolve())
    if rules_dir:
        rd = rules_dir.resolve()
        bases.append(rd)
        # `<repo>/.claude/rules` -> `<repo>`, so a pointer written repo-relative resolves.
        for parent in rd.parents:
            bases.append(parent)
            if parent.name == ".claude":
                bases.append(parent.parent)
    seen, out = set(), []
    for b in bases:
        if b not in seen:
            seen.add(b)
            out.append(b)
    return out


class Result:
    def __init__(self, name: str):
        self.name, self.failures, self.candidates, self.status = name, [], 0, "PASS"

    def fail(self, msg: str):
        self.failures.append(msg)
        self.status = "FAIL"

    def seal(self):
        if self.candidates == 0 and self.status == "PASS":
            self.status = "INCONCLUSIVE"
        return self


def check_pointers_resolve(text: str, bases: "list[Path]") -> Result:
    r = Result("PointersResolve")
    for lineno, tok in pointer_tokens(text):
        r.candidates += 1
        if not any((b / tok).exists() for b in bases):
            r.fail("line %d: `%s` resolves from none of %d base(s) -- a pointer at nothing reads "
                   "as a promise that the detail is somewhere"
                   % (lineno, tok, len(bases)))
    return r.seal()


def check_no_duplication(text: str, rules: "list[Path]") -> Result:
    """Coverage is counted on the RULES side, and getting that backwards was a real bug.

    Counting comparisons made the candidate total the product of the two files -- so a file with
    nothing substantive in it scored zero candidates and reported INCONCLUSIVE. That is exactly
    backwards: a file with nothing to duplicate is a PERFECT pointer, and the check was hardest on
    the outcome it exists to encourage. Caught by the self-test's clean fixture, which is what the
    controls are for.

    What this check is guarding against is the gated content, so that is what is counted: if there
    are rules lines to compare against, the check ran, whatever the always-on file happens to hold.
    """
    r = Result("NoDuplication")
    mine = substantive_lines(text)
    for rf in rules:
        try:
            theirs = substantive_lines(rf.read_text(encoding="utf-8", errors="replace"))
        except OSError as e:
            r.fail("could not read %s (%s)" % (rf, e))
            continue
        r.candidates += len(theirs)
        for my_no, my_raw, my_norm in mine:
            for their_no, _their_raw, their_norm in theirs:
                if my_norm == their_norm:
                    ratio = 1.0
                elif my_norm in their_norm or their_norm in my_norm:
                    ratio = 1.0
                else:
                    ratio = difflib.SequenceMatcher(None, my_norm, their_norm).ratio()
                    if ratio < SIMILARITY:
                        continue
                r.fail("line %d duplicates %s:%d (%.0f%%) -- move it down or point at it; two "
                       "copies both read as authoritative and nothing compares them\n"
                       "        %s" % (my_no, rf.name, their_no, ratio * 100, my_raw[:100]))
                break
    return r.seal()


def check_budget(text: str, max_lines: int, max_bytes: int) -> Result:
    r = Result("Budget")
    r.candidates = 1
    n_lines = len(text.splitlines())
    n_bytes = len(text.encode("utf-8"))
    if n_lines > max_lines:
        r.fail("%d lines, over the %d-line budget you set" % (n_lines, max_lines))
    if n_bytes > max_bytes:
        r.fail("%d bytes, over the %d-byte budget you set" % (n_bytes, max_bytes))
    return r


def run(target: Path, rules_dir: "Path | None", max_lines: int, max_bytes: int,
        base: "Path | None" = None) -> int:
    try:
        text = target.read_text(encoding="utf-8")
    except OSError as e:
        print("!! cannot read %s (%s). A check that cannot locate its subject must not pass."
              % (target, e))
        return EXIT_FAIL
    if not text.strip():
        print("!! %s is empty. Nothing was checked; that is not a pass." % target)
        return EXIT_FAIL

    rules: "list[Path]" = []
    if rules_dir and rules_dir.is_dir():
        rules = sorted(p for p in rules_dir.rglob("*.md") if p.resolve() != target.resolve())

    results = [check_pointers_resolve(text, resolution_bases(target, rules_dir, base)),
               check_budget(text, max_lines, max_bytes)]
    scoped_out = False
    if rules:
        results.append(check_no_duplication(text, rules))
    else:
        scoped_out = True

    print("")
    print("POINTER FILE CHECK -- %s" % target)
    print("=" * 78)
    for res in results:
        print("  %-18s %-14s %d candidate(s)" % (res.name, res.status, res.candidates))
        for f in res.failures:
            print("      - %s" % f)
    if scoped_out:
        print("  %-18s %-14s no rules files under %s"
              % ("NoDuplication", "NOT APPLICABLE",
                 rules_dir if rules_dir else "(--rules-dir not given)"))
    print("=" * 78)

    if any(r.status == "FAIL" for r in results):
        print("  exit 1 -- FAILED")
        return EXIT_FAIL
    if any(r.status == "INCONCLUSIVE" for r in results):
        print("  exit 1 -- INCONCLUSIVE: a check ran and measured nothing, which is not a pass")
        return EXIT_FAIL
    if scoped_out:
        print("  exit 2 -- the duplication check, which is the load-bearing one, did not apply")
        print("            here. Point --rules-dir at your gated rules, or this tool has only")
        print("            told you that your links work.")
        return EXIT_NOT_APPLICABLE
    print("  exit 0 -- pointers resolve, nothing is duplicated, inside budget")
    print("            (it cannot tell you whether a rule BELONGS here -- that is still yours)")
    return EXIT_OK


def self_test() -> int:
    """Negative controls. A check that has never been red is not evidence."""
    passed, failed = 0, []

    def control(name: str, expected, actual):
        nonlocal passed
        ok = expected == actual
        print("  [%s] %-58s expected %s, got %s"
              % ("ok  " if ok else "FAIL", name, expected, actual))
        if ok:
            passed += 1
        else:
            failed.append(name)

    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        rules = tmp / "rules"
        rules.mkdir()
        (rules / "data.md").write_text(
            "# data rules\n\n"
            "Never sum the allocation column directly, because it is line-item grain times "
            "every amendment state and the raw total is badly inflated.\n",
            encoding="utf-8")
        (tmp / "real-target.md").write_text("x\n", encoding="utf-8")

        clean = tmp / "clean.md"
        clean.write_text(
            "# Project\n\nThis file is a pointer, not a rule book.\n\n"
            "| What | Where |\n|---|---|\n"
            "| the data rules | `rules/data.md` |\n",
            encoding="utf-8")
        control("a clean pointer file passes", EXIT_OK,
                run(clean, rules, DEFAULT_MAX_LINES, DEFAULT_MAX_BYTES))

        dup = tmp / "dup.md"
        dup.write_text(
            "# Project\n\n| What | Where |\n|---|---|\n| the data rules | `rules/data.md` |\n\n"
            "Never sum the allocation column directly, because it is line-item grain times "
            "every amendment state and the raw total is badly inflated.\n",
            encoding="utf-8")
        control("a line copied up from a gated rule FAILS", EXIT_FAIL,
                run(dup, rules, DEFAULT_MAX_LINES, DEFAULT_MAX_BYTES))

        reworded = tmp / "reworded.md"
        reworded.write_text(
            "# Project\n\n| What | Where |\n|---|---|\n| the data rules | `rules/data.md` |\n\n"
            "Never sum the allocation column directly, since it is line-item grain times "
            "every amendment state and the raw total is badly inflated.\n",
            encoding="utf-8")
        control("a LIGHTLY REWORDED copy still fails (the drift is the point)", EXIT_FAIL,
                run(reworded, rules, DEFAULT_MAX_LINES, DEFAULT_MAX_BYTES))

        broken = tmp / "broken.md"
        broken.write_text(
            "# Project\n\n| What | Where |\n|---|---|\n| the rules | `rules/gone.md` |\n",
            encoding="utf-8")
        control("a pointer at a missing file FAILS", EXIT_FAIL,
                run(broken, rules, DEFAULT_MAX_LINES, DEFAULT_MAX_BYTES))

        placeholder = tmp / "tpl.md"
        placeholder.write_text(
            "# Project\n\n| What | Where |\n|---|---|\n| <domain> | `<path/to/rules.md>` |\n"
            "| the data rules | `rules/data.md` |\n",
            encoding="utf-8")
        control("a <placeholder> is a shape, not a broken pointer", EXIT_OK,
                run(placeholder, rules, DEFAULT_MAX_LINES, DEFAULT_MAX_BYTES))

        # The three controls below are each a false positive this tool produced against a real
        # always-on file on its first run. Kept as controls so they cannot come back: an
        # over-flagging check is not a safe default, it is a check people stop reading.
        globs = tmp / "globs.md"
        globs.write_text(
            "# Project\n\n| What | Where | Loads when |\n|---|---|---|\n"
            "| the data rules | `rules/data.md` | you touch `stacks/**` or `scripts/**` |\n",
            encoding="utf-8")
        control("a glob names a SET, not a file to resolve", EXIT_OK,
                run(globs, rules, DEFAULT_MAX_LINES, DEFAULT_MAX_BYTES))

        exts = tmp / "exts.md"
        exts.write_text(
            "# Project\n\n| What | Where |\n|---|---|\n| the data rules | `rules/data.md` |\n\n"
            "Loads on any `.sql`, `.py` or `.ps1` file.\n",
            encoding="utf-8")
        control("a bare extension in prose names a TYPE, not a file", EXIT_OK,
                run(exts, rules, DEFAULT_MAX_LINES, DEFAULT_MAX_BYTES))

        # The normal case: host config outside the tree it describes.
        repo = tmp / "repo"
        (repo / ".claude" / "rules").mkdir(parents=True)
        # Substantive on purpose: a rules file with nothing in it makes the duplication check
        # report INCONCLUSIVE, and this control is about pointer RESOLUTION, not about coverage.
        (repo / ".claude" / "rules" / "domain.md").write_text(
            "# domain\n\nAlways dedupe to the current amendment state before counting, because "
            "the view repeats one row per amendment and a raw count is inflated.\n",
            encoding="utf-8")
        (repo / "scripts").mkdir()
        (repo / "scripts" / "guard.py").write_text("# guard\n", encoding="utf-8")
        elsewhere = tmp / "elsewhere.md"
        elsewhere.write_text(
            "# Project\n\n| What | Where |\n|---|---|\n"
            "| the domain rules | `.claude/rules/domain.md` |\n"
            "| the guard | `scripts/guard.py` |\n",
            encoding="utf-8")
        control("a pointer resolves from the described repo, not just the file's own dir",
                EXIT_OK,
                run(elsewhere, repo / ".claude" / "rules", DEFAULT_MAX_LINES, DEFAULT_MAX_BYTES))

        control("over budget FAILS", EXIT_FAIL,
                run(clean, rules, 2, DEFAULT_MAX_BYTES))

        control("no rules dir is NOT APPLICABLE (2), never a pass", EXIT_NOT_APPLICABLE,
                run(clean, tmp / "nope", DEFAULT_MAX_LINES, DEFAULT_MAX_BYTES))

        empty = tmp / "empty.md"
        empty.write_text("   \n", encoding="utf-8")
        control("an EMPTY always-on file is 1, not 2 -- nothing was checked", EXIT_FAIL,
                run(empty, rules, DEFAULT_MAX_LINES, DEFAULT_MAX_BYTES))

        control("an unreadable target is 1, never a pass", EXIT_FAIL,
                run(tmp / "does-not-exist.md", rules, DEFAULT_MAX_LINES, DEFAULT_MAX_BYTES))

    print("")
    if failed:
        print("SELF-TEST FAILED -- %d control(s) misbehaved: %s" % (len(failed), ", ".join(failed)))
        return EXIT_FAIL
    print("SELF-TEST PASSED -- every control behaved as specified (%d)" % passed)
    return EXIT_OK


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("target", nargs="?", help="the always-on file, e.g. CLAUDE.md")
    ap.add_argument("--rules-dir", help="directory of gated rules files to compare against")
    ap.add_argument("--base", help="extra root to resolve pointers from, for the normal case "
                                   "where the always-on file lives outside the tree it describes")
    ap.add_argument("--max-lines", type=int, default=DEFAULT_MAX_LINES)
    ap.add_argument("--max-bytes", type=int, default=DEFAULT_MAX_BYTES)
    ap.add_argument("--self-test", action="store_true",
                    help="run the negative controls and exit; writes only to a temp directory")
    args = ap.parse_args(argv)

    if args.self_test:
        return self_test()
    if not args.target:
        ap.error("a target file is required (or use --self-test)")
    return run(Path(args.target),
               Path(args.rules_dir) if args.rules_dir else None,
               args.max_lines, args.max_bytes,
               Path(args.base) if args.base else None)


if __name__ == "__main__":
    sys.exit(main())
