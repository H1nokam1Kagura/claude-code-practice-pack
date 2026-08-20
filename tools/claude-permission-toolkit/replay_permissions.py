#!/usr/bin/env python3
"""replay_permissions.py -- validate a Claude Code permission floor by REPLAY, not by reading.

A permission ruleset cannot be reviewed by looking at it. Every rule reads as reasonable in
isolation; what matters is what the whole set does to the commands you actually run, and that is
an interaction between wildcard shapes, per-tool spelling, compound-command splitting and
first-match-wins ordering. Reading finds none of it.

So: take a corpus of invocations that were previously approved, replay it against a CANDIDATE
ruleset, and treat any DENY as a regression. This is a before/after diff on real traffic.

    Four rules that all looked correct written down, and all broke a real workflow:

      Bash(rm -rf /*)          under Git Bash EVERY absolute path begins with '/', so this denies
                               ordinary scratch deletes, not just root
      Bash(git push --force*)  the no-space wildcard also swallows --force-with-lease, the SAFE form
      Read(**/*secret*)        blocks reading hooks/secret-guard.ps1, i.e. the guard itself
      Read(**/.env.*)          blocks .env.example, which is a template, not a secret

    Each was found by replay in seconds. None was visible by inspection.

    A fifth sat here until 2026-08-16 -- Read(**/.env) "says nothing about `cat .env`" -- and it
    has been retired rather than reworded, because it stopped being true. See UNDER-PREDICTION
    below, which is the same fact stated as a limit of this tool instead of as a lesson.

USAGE
    python replay_permissions.py --candidate settings.json --corpus settings.local.json.bak
    python replay_permissions.py --candidate settings.json --corpus approved.txt --format json
    python replay_permissions.py --candidate settings.json --corpus c.json --explain "rm -rf /tmp/x"

EXIT CONTRACT
    0  every corpus entry replayed; nothing denied
    1  at least one previously-approved invocation is now DENIED  (a regression)
    2  replayed, but at least one entry could not be PARSED -- SKIPPED, never a pass

    A corpus entry that could not be parsed is reported as SKIPPED and downgrades the exit to 2.
    Coverage you did not measure must never be reported as coverage you have.

SEMANTICS ARE OBSERVED, NOT AUTHORITATIVE.  See MATCHING_MODEL below. They are gathered in one
place precisely so that when the harness changes, there is exactly one thing to correct -- and so
that a reader can disagree with the model rather than with the verdicts it produced.

STDLIB ONLY. Python 3.8+.
"""
from __future__ import annotations

import argparse
import functools
import io
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

# The report uses middots and em-dashes. On a Windows console the default codepage mangles them,
# which makes a security report look broken for a reason that has nothing to do with its content.
if hasattr(sys.stdout, "buffer"):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

print = functools.partial(print, flush=True)  # noqa: A001 -- block buffering hides progress

EXIT_OK, EXIT_REGRESSION, EXIT_SKIPPED = 0, 1, 2

DENY, ASK, ALLOW, UNMATCHED = "DENY", "ASK", "ALLOW", "UNMATCHED"

# Most restrictive first. Used to combine per-segment verdicts for a compound command.
SEVERITY = {DENY: 0, ASK: 1, UNMATCHED: 2, ALLOW: 3}

MATCHING_MODEL = """\
1. Lists are evaluated deny -> ask -> allow. FIRST MATCH WINS; specificity is ignored, so a
   broad deny beats a narrow allow.
2. Rules are PER TOOL. Bash(...) places no constraint on the PowerShell tool, a Write(path) rule
   is accepted and never consulted, and no file rule reaches a script that opens the file itself.
   A floor written in one spelling is half a floor.
   BUT NOTE WHAT THIS MODEL DOES NOT COVER, verified 2026-08-16: the live harness also applies
   Read and Edit DENY rules to the file commands it recognises in Bash -- cat, head, tail, sed.
   This tool models the rules literally and per tool, so it does NOT model that layer and will
   report `cat .env` as ALLOW where the harness blocks it. It can therefore MISS a denial; it
   still cannot invent one, so a reported regression is real and a clean run is a lower bound.
   Read a DENY here as certain and an ALLOW as "not denied by the rules as written".
3. A rule with no parentheses -- "PowerShell", "WebSearch" -- matches every use of that tool.
4. For command tools (Bash, PowerShell) the invocation is split on ; | && || and EVERY segment
   must match independently for the command to be allowed. One denied segment denies the whole.
5. In command patterns, * matches any run of characters INCLUDING spaces. This is why
   `git push --force*` also swallows `--force-with-lease`, and why the safe form must be
   written with the space: `git push --force *`.
6. For path tools (Read, Edit, Write, Glob, Grep, NotebookEdit) the pattern is a PATH glob:
   ** crosses directory separators, * does not, ? is one non-separator character.
7. deny and ask survive defaultMode:auto and bypassPermissions. allow is noise reduction only.
"""

COMMAND_TOOLS = {"Bash", "PowerShell", "Shell"}
PATH_TOOLS = {"Read", "Edit", "Write", "Glob", "Grep", "NotebookEdit", "MultiEdit"}

# Longest operators first: '||' must be tried before '|', or '||' splits into two empty segments.
_SPLIT = re.compile(r"\s*(?:\|\||&&|;|\|)\s*")

# An allow rule that hands over an interpreter concedes everything any narrower rule withheld.
#
# BASE names only, lowercase; a trailing ".exe" is stripped before lookup. Listing both spellings
# turns this into a set of filenames rather than of programs, and then one spelling goes missing --
# which is exactly how `Bash(wsl.exe *)` slipped past the sibling implementation.
#
# Gated against skills/build-compliance/scripts/checks/harness.py by check_interpreter_parity.py.
# The two were written independently and each caught something the other missed; the gate is there
# because "keep these two lists in sync by hand" is not a control.
_INTERPRETERS = frozenset({
    "sh", "bash", "zsh", "dash", "ksh", "fish",
    "pwsh", "powershell", "cmd", "wsl",
    "python", "python2", "python3", "py", "perl", "ruby", "php", "lua", "rscript",
    "node", "nodejs", "npx", "bun", "deno", "uv", "uvx",
    # Not interpreters, but each runs a command you did not name:
    "env",   # `env VAR=x <anything>`
    "ssh",   # runs an arbitrary command on another host
    "eval",
})


# ── rule parsing ──────────────────────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class Rule:
    raw: str
    tool: str
    pattern: str | None          # None == the bare-tool form, matches every invocation

    @property
    def is_bare(self) -> bool:
        return self.pattern is None


def parse_rule(raw: str) -> Rule | None:
    """"Bash(git push *)" -> Rule('Bash', 'git push *').  "PowerShell" -> Rule('PowerShell', None).

    Split on the FIRST '(' and the LAST ')' rather than with a regex, because patterns legitimately
    contain parentheses -- Bash(echo "(x)") is a real rule shape and a lazy regex truncates it.
    """
    s = (raw or "").strip()
    if not s:
        return None
    if s.endswith(")") and "(" in s:
        i = s.index("(")
        tool, pattern = s[:i].strip(), s[i + 1:-1]
        if not tool:
            return None
        return Rule(raw=s, tool=tool, pattern=pattern)
    return Rule(raw=s, tool=s, pattern=None)


@functools.lru_cache(maxsize=4096)
def _command_regex(pattern: str) -> re.Pattern:
    """Command-pattern glob: * is any run of characters, including spaces. Anchored."""
    return re.compile("".join(".*" if ch == "*" else re.escape(ch) for ch in pattern) + r"\Z")


@functools.lru_cache(maxsize=4096)
def _path_regex(pattern: str) -> re.Pattern:
    """Path glob: ** crosses separators, * does not, ? is one non-separator character.

    '**/x' must also match a bare 'x' at the root, so the leading '**/' is optional -- otherwise
    Read(**/.env) would fail to match '.env' in the working directory, which is the very file
    the rule exists to protect.
    """
    out, i = [], 0
    while i < len(pattern):
        ch = pattern[i]
        if pattern.startswith("**/", i):
            out.append("(?:.*/)?")
            i += 3
        elif pattern.startswith("**", i):
            out.append(".*")
            i += 2
        elif ch == "*":
            out.append("[^/]*")
            i += 1
        elif ch == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(ch))
            i += 1
    return re.compile("".join(out) + r"\Z")


def _norm_path(s: str) -> str:
    return s.replace("\\", "/")


def _norm_token(tok: str) -> str:
    """Reduce one command token to a bare program name: path, quotes, case, .exe, leading *."""
    tok = tok.strip().strip("\"'")
    tok = tok.replace("\\", "/").rsplit("/", 1)[-1].lower()
    if tok.endswith(".exe"):
        tok = tok[:-4]
    return tok.lstrip("*")      # `Bash(*python.exe *)` -- a venv interpreter allowed by suffix


def _grants_execution(pattern: str) -> bool:
    """Does this command pattern hand over an interpreter?

    Scans the COMMAND portion -- every token up to the first flag -- rather than only the first
    token. A single-token head misses an interpreter behind a space-containing path, and
    `C:/Program Files/PowerShell/7/pwsh.exe` is exactly where pwsh lives on Windows: the head
    would read "C:/Program". Stopping at the first flag keeps `git commit -m "run python"` from
    being flagged on its argument text.
    """
    for tok in re.split(r"[\s(]+", pattern.strip().lstrip("&. ")):
        if not tok:
            continue
        if tok.startswith("-"):
            break
        if _norm_token(tok) in _INTERPRETERS:
            return True
    return False


def rule_matches(rule: Rule, tool: str, payload: str) -> bool:
    if rule.tool != tool:
        return False
    if rule.is_bare:
        return True
    if tool in PATH_TOOLS:
        return bool(_path_regex(_norm_path(rule.pattern)).match(_norm_path(payload)))
    return bool(_command_regex(rule.pattern).match(payload))


# ── the ruleset ───────────────────────────────────────────────────────────────────────────────

class Ruleset:
    def __init__(self, deny, ask, allow):
        self.deny = [r for r in map(parse_rule, deny) if r]
        self.ask = [r for r in map(parse_rule, ask) if r]
        self.allow = [r for r in map(parse_rule, allow) if r]
        self.hits: dict[str, int] = {}     # rule.raw -> times it was the deciding match

    @classmethod
    def from_settings(cls, paths: "list[Path] | Path") -> "Ruleset":
        """Load and MERGE one or more settings files, in the order given.

        Claude Code layers settings.json with settings.local.json, so measuring only one of them
        understates what is actually in effect. Found by cross-checking against an independent
        implementation that read both: it saw 111 allow rules where this tool saw 109, and the
        two extra were real. Measuring one file and calling it "the ruleset" is the same class of
        error as scanning an empty commit range and calling it clean.
        """
        if isinstance(paths, Path):
            paths = [paths]
        deny, ask, allow = [], [], []
        for path in paths:
            data = json.loads(path.read_text(encoding="utf-8"))
            p = data.get("permissions", data)
            if not isinstance(p, dict):
                raise SystemExit(f"{path}: no 'permissions' object found")
            # Absent keys are the finding, not an error -- a floor that does not exist is the
            # single most common state, and it must be visible rather than silently defaulted.
            deny += p.get("deny") or []
            ask += p.get("ask") or []
            allow += p.get("allow") or []
        return cls(deny, ask, allow)

    def _first(self, rules, tool, payload) -> Rule | None:
        for r in rules:
            if rule_matches(r, tool, payload):
                return r
        return None

    def decide_segment(self, tool: str, payload: str) -> tuple[str, Rule | None]:
        for verdict, rules in ((DENY, self.deny), (ASK, self.ask), (ALLOW, self.allow)):
            hit = self._first(rules, tool, payload)
            if hit:
                self.hits[hit.raw] = self.hits.get(hit.raw, 0) + 1
                return verdict, hit
        return UNMATCHED, None

    def decide(self, tool: str, payload: str) -> tuple[str, Rule | None, str]:
        """Returns (verdict, deciding rule, the segment it applied to)."""
        segments = [s for s in _SPLIT.split(payload) if s.strip()] if tool in COMMAND_TOOLS \
            else [payload]
        if not segments:
            segments = [payload]
        worst, worst_rule, worst_seg = ALLOW, None, payload
        for seg in segments:
            v, r = self.decide_segment(tool, seg)
            if SEVERITY[v] < SEVERITY[worst]:
                worst, worst_rule, worst_seg = v, r, seg
        return worst, worst_rule, worst_seg

    def arbitrary_execution_grants(self) -> list[Rule]:
        """allow rules that concede an interpreter, i.e. everything a narrower rule withheld.

        This is the measurement that makes a long allow-list legible: if any of these is present,
        the list's LENGTH tells you nothing about its blast radius.
        """
        out = []
        for r in self.allow:
            if r.tool not in COMMAND_TOOLS:
                continue
            if r.is_bare or r.pattern.strip() in ("*", "", ":*"):
                out.append(r)
                continue
            if _grants_execution(r.pattern):
                out.append(r)
        return out


# ── the corpus ────────────────────────────────────────────────────────────────────────────────

@dataclass
class Entry:
    tool: str
    payload: str
    raw: str
    representative: bool = False   # reconstructed from a wildcard rule, not a literal invocation


@dataclass
class Result:
    entry: Entry
    verdict: str
    rule: Rule | None
    segment: str


@dataclass
class Corpus:
    entries: list[Entry] = field(default_factory=list)
    unparsed: list[str] = field(default_factory=list)


_PROBE = "REPLAYPROBE"


def load_corpus(path: Path, literals_only: bool = False) -> Corpus:
    """Read approved invocations from a settings-shaped JSON, or a plain list of Tool(payload).

    An accumulated `settings.local.json` is the best corpus available: every literal in it is a
    command that actually ran and was actually approved. It is a regression suite nobody had to
    write. Entries that carry a wildcard are GENERALIZATIONS rather than invocations, so they are
    replayed as a representative concrete command with the wildcard filled by a probe token, and
    labelled as such -- coverage with a caveat beats a silent coverage hole.
    """
    c = Corpus()
    text = path.read_text(encoding="utf-8")
    raws: list[str]
    if path.suffix.lower() == ".json" or text.lstrip().startswith("{"):
        data = json.loads(text)
        p = data.get("permissions", data)
        raws = list(p.get("allow") or []) if isinstance(p, dict) else []
        if not raws:
            raise SystemExit(
                f"{path}: no permissions.allow entries -- refusing to report a replay of nothing "
                f"as a pass.")
    else:
        raws = [ln.strip() for ln in text.splitlines()
                if ln.strip() and not ln.lstrip().startswith("#")]

    for raw in raws:
        r = parse_rule(raw)
        if r is None:
            c.unparsed.append(raw)
            continue
        if r.is_bare:
            # "PowerShell" as a corpus entry records that the tool was approved wholesale; there
            # is no invocation to replay. Not an error, and not coverage either.
            continue
        if "*" in r.pattern:
            if literals_only:
                continue
            c.entries.append(Entry(r.tool, r.pattern.replace("*", _PROBE), raw, representative=True))
        else:
            c.entries.append(Entry(r.tool, r.pattern, raw))
    return c


# ── reporting ─────────────────────────────────────────────────────────────────────────────────

def render(results: list[Result], rs: Ruleset, corpus: Corpus, code: int,
           show: int, literals_only: bool) -> str:
    counts = {v: sum(1 for r in results if r.verdict == v) for v in (DENY, ASK, ALLOW, UNMATCHED)}
    lits = sum(1 for r in results if not r.entry.representative)
    reps = len(results) - lits

    L = ["", "PERMISSION FLOOR REPLAY", "=" * 78, ""]
    L.append(f"  candidate : {len(rs.deny)} deny · {len(rs.ask)} ask · {len(rs.allow)} allow")
    L.append(f"  corpus    : {len(results)} replayed ({lits} literal, {reps} representative)"
             + (" [--literals-only]" if literals_only else ""))
    if corpus.unparsed:
        L.append(f"              {len(corpus.unparsed)} UNPARSED -- skipped, not passed")
    L.append("")

    if not rs.deny and not rs.ask:
        L.append("  !! No deny and no ask list. There is no floor: `allow` is noise reduction,")
        L.append("     and nothing here holds under defaultMode:auto or bypassPermissions.")
        L.append("")

    L.append(f"  {DENY}: {counts[DENY]}   {ASK}: {counts[ASK]}   "
             f"{UNMATCHED}: {counts[UNMATCHED]}   {ALLOW}: {counts[ALLOW]}")
    L.append("")

    regressions = [r for r in results if r.verdict == DENY]
    if regressions:
        L.append("-" * 78)
        L.append("REGRESSIONS -- previously approved, now DENIED")
        L.append("-" * 78)
        for r in regressions[:show]:
            tag = " (representative)" if r.entry.representative else ""
            L.append(f"  {r.entry.tool}: {r.entry.payload}{tag}")
            L.append(f"      denied by  {r.rule.raw}")
            if r.segment != r.entry.payload:
                L.append(f"      on segment  {r.segment!r}")
        if len(regressions) > show:
            L.append(f"  … and {len(regressions) - show} more (--show N)")
        L.append("")

    asks = [r for r in results if r.verdict == ASK]
    if asks:
        L.append("-" * 78)
        L.append("NOW PROMPTS (ask) -- intended for outward-facing actions; check none is routine")
        L.append("-" * 78)
        by_rule: dict[str, int] = {}
        for r in asks:
            by_rule[r.rule.raw] = by_rule.get(r.rule.raw, 0) + 1
        for raw, n in sorted(by_rule.items(), key=lambda kv: -kv[1])[:show]:
            L.append(f"  {n:>5}x  {raw}")
        L.append("")

    unmatched = [r for r in results if r.verdict == UNMATCHED]
    if unmatched:
        L.append("-" * 78)
        L.append("UNMATCHED -- no allow rule covers these (they prompt unless defaultMode:auto)")
        L.append("-" * 78)
        seen: dict[str, str] = {}
        for r in unmatched:
            head = " ".join(r.entry.payload.split()[:2]) or r.entry.payload
            seen.setdefault(f"{r.entry.tool}: {head}", r.entry.payload)
        for k in list(seen)[:show]:
            L.append(f"  {k}")
        if len(seen) > show:
            L.append(f"  … and {len(seen) - show} more distinct heads (--show N)")
        L.append("")

    arb = rs.arbitrary_execution_grants()
    if arb:
        L.append("-" * 78)
        L.append("BLAST RADIUS -- allow rules that concede arbitrary code execution")
        L.append("-" * 78)
        for r in arb:
            L.append(f"  {r.raw}")
        L.append("")
        L.append(f"  {len(arb)} such rule(s). Any ONE of them makes the other "
                 f"{len(rs.allow) - len(arb)} allow rules")
        L.append("  redundant as a security boundary: whatever they exclude is reachable through")
        L.append("  an interpreter. Judge this list by its FLOOR, never by its length.")
        L.append("")

    unused = [r for r in rs.allow if r.raw not in rs.hits]
    if unused:
        L.append("-" * 78)
        L.append(f"NOT EXERCISED BY THIS CORPUS -- {len(unused)} allow rule(s)")
        L.append("-" * 78)
        L.append("  Candidates for removal, but only if the corpus is representative. A rule for")
        L.append("  something you do rarely is not a dead rule.")
        for r in unused[:show]:
            L.append(f"  {r.raw}")
        if len(unused) > show:
            L.append(f"  … and {len(unused) - show} more (--show N)")
        L.append("")

    if corpus.unparsed:
        L.append("-" * 78)
        L.append("UNPARSED corpus entries -- SKIPPED, never counted as passes")
        L.append("-" * 78)
        for raw in corpus.unparsed[:show]:
            L.append(f"  {raw!r}")
        L.append("")

    L.append("=" * 78)
    L.append({
        EXIT_OK: "  exit 0 — no previously-approved invocation is denied by this candidate",
        EXIT_REGRESSION: "  exit 1 — REGRESSION: this candidate would block work that already ran",
        EXIT_SKIPPED: "  exit 2 — replayed WITH SKIPPED entries; coverage is incomplete",
    }[code])
    L.append("")
    return "\n".join(L)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--candidate", required=True, action="append", metavar="SETTINGS",
                    help="settings file holding a candidate permissions block. Repeat to MERGE "
                         "layers in order, e.g. --candidate settings.json "
                         "--candidate settings.local.json. Measuring only one understates what "
                         "is actually in effect.")
    ap.add_argument("--corpus", required=True,
                    help="approved invocations: a settings.local.json (or its .bak), or a text "
                         "file of Tool(payload) lines")
    ap.add_argument("--literals-only", action="store_true",
                    help="replay only wildcard-free entries; skip reconstructed representatives")
    ap.add_argument("--explain", metavar="CMD",
                    help="explain one invocation against the candidate and exit")
    ap.add_argument("--tool", default="Bash", help="tool for --explain (default: Bash)")
    ap.add_argument("--show", type=int, default=25, help="max lines per report section")
    ap.add_argument("--format", choices=["text", "json"], default="text")
    ap.add_argument("--print-model", action="store_true",
                    help="print the matching model this tool implements, and exit")
    args = ap.parse_args(argv)

    if args.print_model:
        print(MATCHING_MODEL)
        return EXIT_OK

    rs = Ruleset.from_settings([Path(c) for c in args.candidate])

    if args.explain:
        verdict, rule, seg = rs.decide(args.tool, args.explain)
        print(f"\n  {args.tool}: {args.explain}")
        print(f"  verdict : {verdict}")
        print(f"  rule    : {rule.raw if rule else '(no rule matched)'}")
        if seg != args.explain:
            print(f"  segment : {seg!r}")
        print("")
        return EXIT_OK if verdict != DENY else EXIT_REGRESSION

    corpus = load_corpus(Path(args.corpus), literals_only=args.literals_only)
    rs.hits.clear()

    results = []
    for e in corpus.entries:
        v, rule, seg = rs.decide(e.tool, e.payload)
        results.append(Result(e, v, rule, seg))

    code = EXIT_OK
    if any(r.verdict == DENY for r in results):
        code = EXIT_REGRESSION
    elif corpus.unparsed:
        code = EXIT_SKIPPED

    if args.format == "json":
        print(json.dumps({
            "candidate": args.candidate,
            "corpus": args.corpus,
            "exit_code": code,
            "counts": {v: sum(1 for r in results if r.verdict == v)
                       for v in (DENY, ASK, ALLOW, UNMATCHED)},
            "unparsed": corpus.unparsed,
            "arbitrary_execution_grants": [r.raw for r in rs.arbitrary_execution_grants()],
            "not_exercised": [r.raw for r in rs.allow if r.raw not in rs.hits],
            "regressions": [
                {"tool": r.entry.tool, "invocation": r.entry.payload, "denied_by": r.rule.raw,
                 "segment": r.segment, "representative": r.entry.representative}
                for r in results if r.verdict == DENY],
        }, indent=2))
    else:
        print(render(results, rs, corpus, code, args.show, args.literals_only))
    return code


if __name__ == "__main__":
    sys.exit(main())
