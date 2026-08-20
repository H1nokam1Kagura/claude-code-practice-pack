#!/usr/bin/env python3
"""Gate the two implementations of the skill frontmatter contract against each other.

The contract exists twice in this repository, and both copies are load-bearing:

    .github/scripts/lint_skills.py      the repo's own gate. Hardcoded constants, run by CI over
                                        the live skill catalogue and the marketplace plugin tree.
    tools/claude-authoring-toolkit/     the shipped, generalised contract as DATA, read by the
        skill-schema.json               toolkit's lint_skills.py beside it.

Neither may be deleted. The repo-side lint holds a working catalogue and re-baselining it would
change what CI enforces on real files; the schema is what a recipient gets, and it must be able to
say things about the platform that this repository's house style does not.

    Same pattern and same reason as check_guard_parity.py and check_interpreter_parity.py in the
    permission toolkit: keep the copies, gate the copies. TESTING-DISCIPLINE.md section 6.

WHY IT EXISTS
    Measured 2026-08-16, before this gate: three of the five compared properties already differed,
    and nothing anywhere recorded that any of them was a decision. The substantive one is `name` --
    the repo-side lint requires it at the top level, the schema deliberately does not, because in a
    personal or project skill the command comes from the DIRECTORY and `name` is a display label.
    Requiring it is a house rule. That is a fine thing to want and a bad thing to leave undeclared,
    because the next reader cannot tell a decision from a copy that stopped being maintained.

WHAT IT ASSERTS -- both halves matter
    1. every property compared either AGREES, or is registered in lint-parity-exceptions.json
       with a reason;
    2. every registered exception still describes a difference that is REALLY THERE, in the exact
       shape recorded.
    The second half is not decoration. An exception whose two sides have converged is an exemption
    nobody granted, and it will silently absorb the NEXT divergence on that property -- the mirror
    of the stale-`sweep_exclusions` rule the practice gate now enforces (Test-HarnessPins).

HOW IT READS THE REPO SIDE
    By `ast`, never by import. `.github/scripts/lint_skills.py` runs its entire lint at module
    scope: importing it would lint the repository as a side effect and can call sys.exit. So the
    module is parsed and the constants are literal-evaluated out of it. A constant that is absent,
    or present but not a literal, is a FAILURE and never a default -- a parity check that quietly
    compares four properties while believing it compared five is the exact defect this repository
    gates against everywhere else.

USAGE
    python check_lint_parity.py                  # exit 0 = in parity, or every difference registered
    python check_lint_parity.py --self-test      # the negative controls; writes only to temp
    python check_lint_parity.py --repo-lint <path> --schema <path> --exceptions <path>

EXIT CONTRACT
    0  the two agree, or every difference is registered and still real
    1  an unregistered difference, a stale exception, an exception with no reason, or an expected
       constant that could not be read. The last is INCONCLUSIVE, which is a failure, because it
       ran and measured less than it thinks it did.
    2  the comparison does not apply here -- the repo-side lint is not in this tree at all, which
       is what a distribution containing only this toolkit looks like. A scope fact, not a defect.
       Nothing was compared; still never a pass.

    The 1-versus-2 split is the one the practice documents insist on: "this does not apply here"
    and "it ran and measured nothing" must not share an exit code. Note which side is which -- an
    ABSENT repo-side file is the scope case (2), because this toolkit ships without it by design;
    a file that IS present and will not parse is the defect case (1).

STDLIB ONLY. Python 3.8+.
"""
from __future__ import annotations

import argparse
import ast
import functools
import json
import sys
import tempfile
from pathlib import Path

print = functools.partial(print, flush=True)  # noqa: A001

EXIT_OK, EXIT_DIVERGED, EXIT_SKIPPED = 0, 1, 2
EXIT_INCONCLUSIVE = 1  # ran and measured nothing -- a failure, same code as diverged

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
REPO_LINT = REPO / ".github" / "scripts" / "lint_skills.py"
SCHEMA = HERE / "skill-schema.json"
EXCEPTIONS = HERE / "lint-parity-exceptions.json"

# The top-level assignments the repo-side lint must still carry. Named here rather than discovered,
# so a constant that is RENAMED away fails loudly instead of dropping out of the comparison.
WANTED = ("REQUIRED_TOP", "REQUIRED_META", "REQUIRED_PLUGIN", "MAX_DESC")

# The placeholder list on the repo side is NOT a named constant -- it is a literal tuple inside the
# membership test that uses it. So it is found by shape: the one `x in (<literals>)` comparison in
# the module. Zero of them, or more than one distinct one, is unreadable rather than defaulted.
PLACEHOLDERS = "__placeholders__"

SET_VALUED = {"catalogue.required_top", "catalogue.required_metadata",
              "bundle.required_top", "placeholder_values"}


def _literal_collections(tree: ast.AST) -> "list[tuple]":
    """Every `x in (<literal collection>)` comparison in the module, as tuples."""
    out = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Compare):
            continue
        if len(node.ops) != 1 or not isinstance(node.ops[0], ast.In):
            continue
        comp = node.comparators[0]
        if not isinstance(comp, (ast.Tuple, ast.List, ast.Set)):
            continue
        try:
            out.append(tuple(ast.literal_eval(comp)))
        except (ValueError, TypeError):
            continue
    return out


def read_repo_constants(path: Path) -> "tuple[dict, list]":
    """Parse -- never import -- the repo-side lint and literal-eval its contract constants.

    Returns (values, problems). A non-empty `problems` means the comparison is INCOMPLETE, and the
    caller must fail rather than compare what it managed to find.
    """
    values, problems, label = {}, [], _short(path)
    try:
        tree = ast.parse(path.read_text(encoding="utf-8", errors="replace"), filename=str(path))
    except SyntaxError as e:
        return values, ["%s will not parse (%s) -- it is present, so this is a defect, not a "
                        "scope limit" % (label, e)]

    for node in tree.body:                      # TOP-LEVEL only: a constant inside a function is
        if not isinstance(node, ast.Assign):    # not the contract, it is an implementation detail
            continue
        for target in node.targets:
            if isinstance(target, ast.Name) and target.id in WANTED:
                try:
                    values[target.id] = ast.literal_eval(node.value)
                except (ValueError, TypeError):
                    problems.append(
                        "%s: %s is not a literal, so its value cannot be read without executing "
                        "the module -- and executing it runs the whole lint"
                        % (label, target.id))

    for name in WANTED:
        if name not in values and not any(name in p for p in problems):
            problems.append(
                "%s: no top-level %s -- it was renamed or removed. Refusing to compare four "
                "properties while reporting five; there is no safe default for a contract."
                % (label, name))

    found = sorted(set(_literal_collections(tree)))
    if len(found) == 1:
        values[PLACEHOLDERS] = list(found[0])
    elif not found:
        problems.append(
            "%s: no `x in (<literals>)` membership test -- the placeholder list is written inline "
            "there, and it is not there any more. Not defaulted: a guessed placeholder set would "
            "certify a template nobody completed." % label)
    else:
        problems.append(
            "%s: %d distinct literal membership tests, so which one is the placeholder list is "
            "ambiguous. Ambiguous is unreadable; unreadable is a failure." % (label, len(found)))

    return values, problems


def _profile(schema: dict, name: str, problems: list) -> dict:
    for p in schema.get("profiles", []):
        if p.get("name") == name:
            return p
    problems.append("skill-schema.json declares no '%s' profile -- the repo-side lint enforces a "
                    "contract the schema no longer has a home for" % name)
    return {}


def compare(repo: dict, schema: dict, problems: list) -> "list[tuple]":
    """Return [(property, repo_value, toolkit_value)] for the five compared properties."""
    cat = _profile(schema, "catalogue", problems)
    bun = _profile(schema, "bundle", problems)
    return [
        ("catalogue.required_top", repo.get("REQUIRED_TOP"), cat.get("required_top")),
        ("catalogue.required_metadata", repo.get("REQUIRED_META"), cat.get("required_metadata")),
        ("description_max_chars", repo.get("MAX_DESC"), schema.get("description_max_chars")),
        ("placeholder_values", repo.get(PLACEHOLDERS), schema.get("placeholder_values")),
        ("bundle.required_top", repo.get("REQUIRED_PLUGIN"), bun.get("required_top")),
    ]


def _same(prop: str, a, b) -> bool:
    """Order is not contract for a required-field list; membership is."""
    if a is None or b is None:
        return False
    if prop in SET_VALUED:
        return set(a) == set(b)
    return a == b


def _short(p: Path) -> str:
    """Enough path to be unambiguous. Both sides are called lint_skills.py, which is the whole
    point of this gate and would make a bare basename in an error message actively misleading."""
    return "/".join(p.parts[-3:])


def _show(v) -> str:
    if isinstance(v, (list, tuple)):
        return "[%s]" % ", ".join(repr(x) for x in v)
    return repr(v)


def run(repo_lint: Path = REPO_LINT, schema_path: Path = SCHEMA,
        exceptions_path: Path = EXCEPTIONS) -> int:
    # NOT APPLICABLE is a different outcome from FAILED TO RUN, and only one of them is a defect.
    # A distribution holding only tools/claude-authoring-toolkit/ has no repo-side lint -- it was
    # never shipped, not lost. Handing that recipient a red gate on first run teaches them to
    # ignore it.
    if not repo_lint.is_file():
        print("-- not applicable here: %s is not in this tree." % _short(repo_lint))
        print("   This gate compares two implementations of one contract and only the schema half")
        print("   ships with this toolkit. NOTHING WAS MEASURED -- no property was compared, and")
        print("   this is NOT a pass. Run it from the full repository.")
        return EXIT_SKIPPED

    try:
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        print("!! cannot read %s (%s)" % (schema_path, e))
        print("   One side of the comparison will not load. Nothing was compared. INCONCLUSIVE.")
        return EXIT_INCONCLUSIVE

    # The registry is required, not optional. An ABSENT registry and an EMPTY one are different
    # claims -- "no exception was ever granted" versus "the file went missing" -- and defaulting a
    # missing file to the empty list makes them indistinguishable.
    try:
        registry = json.loads(exceptions_path.read_text(encoding="utf-8"))
        entries = registry["exceptions"]
    except (OSError, ValueError, KeyError, TypeError) as e:
        print("!! cannot read the exception registry %s (%s)" % (exceptions_path.name, e))
        print("   A missing registry is not an empty one. Refusing to treat every divergence as")
        print("   unregistered, or every registration as absent. INCONCLUSIVE.")
        return EXIT_INCONCLUSIVE

    repo, problems = read_repo_constants(repo_lint)
    rows = compare(repo, schema, problems)

    failures = []
    by_prop = {}
    for i, e in enumerate(entries):
        if not isinstance(e, dict):
            failures.append("exception #%d is not an object" % i)
            continue
        missing = [k for k in ("property", "repo_side", "toolkit_side", "reason") if k not in e]
        if missing:
            failures.append(
                "exception #%d (%r) is missing %s -- a divergence registered without a stated "
                "reason is an oversight, not a decision"
                % (i, e.get("property", "<unnamed>"), ", ".join("'%s'" % m for m in missing)))
            continue
        if not str(e["reason"]).strip():
            failures.append("exception '%s' has an empty reason -- an escape hatch without a "
                            "reason is a silencer" % e["property"])
            continue
        if e["property"] in by_prop:
            failures.append("exception '%s' is registered twice" % e["property"])
            continue
        by_prop[e["property"]] = e

    compared = {p for p, _, _ in rows}
    for prop in sorted(set(by_prop) - compared):
        failures.append(
            "exception '%s' names a property this gate does not compare -- the property was "
            "renamed or dropped and the exemption outlived it, so the next thing to land on that "
            "name inherits an exemption nobody granted it" % prop)

    agreed, registered = [], []
    for prop, a, b in rows:
        differs = not _same(prop, a, b)
        exc = by_prop.get(prop)
        if differs and exc is None:
            failures.append(
                "UNREGISTERED DIVERGENCE on %s\n"
                "       repo    %s\n"
                "       toolkit %s\n"
                "       Register it in %s with the reason, or make the two agree. An undeclared\n"
                "       difference is not a decision -- nobody can tell it from a copy that\n"
                "       stopped being maintained."
                % (prop, _show(a), _show(b), exceptions_path.name))
        elif differs:
            # The registration has to describe the divergence that is actually there. Without
            # this, one entry absorbs every FUTURE change to the same property.
            if not _same(prop, exc["repo_side"], a) or not _same(prop, exc["toolkit_side"], b):
                failures.append(
                    "STALE REGISTRATION on %s -- the two still differ, but not in the shape the\n"
                    "       exception records, so it is exempting something nobody read.\n"
                    "       recorded repo    %s   measured %s\n"
                    "       recorded toolkit %s   measured %s"
                    % (prop, _show(exc["repo_side"]), _show(a),
                       _show(exc["toolkit_side"]), _show(b)))
            else:
                registered.append((prop, exc))
        elif exc is not None:
            failures.append(
                "STALE EXCEPTION on %s -- the two sides AGREE (%s) but a registered exception\n"
                "       still claims they differ. An exemption for a divergence that no longer\n"
                "       exists will silently absorb the next one. Delete the entry."
                % (prop, _show(a)))
        else:
            agreed.append(prop)

    print("")
    print("LINT PARITY -- %s  vs  %s" % (_short(repo_lint), schema_path.name))
    print("=" * 78)
    print("  %-30s %-30s %s" % ("property", "repo side", "toolkit side"))
    for prop, a, b in rows:
        mark = "=" if _same(prop, a, b) else ("~" if prop in by_prop else "!")
        print("  %s %-28s %-30s %s" % (mark, prop, _show(a), _show(b)))
    print("    =  agree    ~  differ, registered with a reason    !  differ, UNREGISTERED")
    print("=" * 78)

    if problems:
        for p in problems:
            print("!! %s" % p)
        print("")
        print("!! The repo-side contract could not be read in full, so this run compared LESS than")
        print("   it reports. That is INCONCLUSIVE, which is a failure -- exit 1, never a pass.")
        return EXIT_INCONCLUSIVE

    if failures:
        for f in failures:
            print("!! %s" % f)
        print("")
        print("!! Parity FAILED. Two implementations of one contract, disagreeing with nothing")
        print("   recording that anyone chose it, is how a catalogue and the schema it ships")
        print("   drift apart with both sides reading as authoritative.")
        return EXIT_DIVERGED

    print("ok  %d propert(ies) agree outright: %s" % (len(agreed), ", ".join(agreed) or "none"))
    print("ok  %d registered as DELIBERATE, each with a reason and each still real:"
          % len(registered))
    for prop, exc in registered:
        print("      %-28s %s" % (prop, str(exc["reason"]).split(". ")[0][:78]))
    print("    A registered difference is not a passing grade for that property -- it is a")
    print("    decision somebody wrote down. Read the registry, not this line.")
    print("")
    print("ok  exit 0 -- the two implementations are in parity")
    return EXIT_OK


# ---------------------------------------------------------------------------------------------
# SELF-TEST -- a gate that has never been red is not evidence.

def _repo_source(required_top, required_meta, required_plugin, max_desc, placeholders,
                 drop=(), nonliteral=(), drop_placeholders=False) -> str:
    """A stand-in for the repo-side lint: the same constant SHAPES, none of the behaviour."""
    lines = ["import os", ""]
    for name, value in (("REQUIRED_TOP", required_top), ("REQUIRED_META", required_meta),
                        ("REQUIRED_PLUGIN", required_plugin), ("MAX_DESC", max_desc)):
        if name in drop:
            continue
        if name in nonliteral:
            lines.append("%s = int(os.environ['X'])" % name)
        else:
            lines.append("%s = %r" % (name, value))
    lines += ["", "def check(val):"]
    if drop_placeholders:
        lines.append("    return bool(val)")
    else:
        lines.append("    return not val or val in %r" % (tuple(placeholders),))
    return "\n".join(lines) + "\n"


def self_test() -> int:
    passed, failed = 0, []

    def control(name, expected, actual):
        nonlocal passed
        ok = expected == actual
        print("  [%s] %-64s expected %s, got %s"
              % ("ok  " if ok else "FAIL", name, expected, actual))
        if ok:
            passed += 1
        else:
            failed.append(name)

    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    cat = next(p for p in schema["profiles"] if p["name"] == "catalogue")
    bun = next(p for p in schema["profiles"] if p["name"] == "bundle")

    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        sch = tmp / "schema.json"
        sch.write_text(json.dumps(schema), encoding="utf-8")

        # Every fixture gets its OWN filename. Reusing one path made two controls read a later
        # control's file and pass for the wrong reason -- the first thing this self-test caught
        # was itself, which is the argument for writing the controls before believing the tool.
        seq = [0]

        def _next(suffix: str) -> Path:
            seq[0] += 1
            return tmp / ("fixture%02d%s" % (seq[0], suffix))

        def write_repo(**kw):
            p = _next(".py")
            kw.setdefault("required_top", list(cat["required_top"]))
            kw.setdefault("required_meta", list(cat["required_metadata"]))
            kw.setdefault("required_plugin", list(bun["required_top"]))
            kw.setdefault("max_desc", schema["description_max_chars"])
            kw.setdefault("placeholders", list(schema["placeholder_values"]))
            p.write_text(_repo_source(**kw), encoding="utf-8")
            return p

        def write_exc(entries):
            p = _next(".json")
            p.write_text(json.dumps({"exceptions": entries}), encoding="utf-8")
            return p

        # 1. the baseline the whole gate is aimed at: two sides that agree, nothing registered.
        same = write_repo()
        none_registered = write_exc([])
        control("two sides that agree, no exceptions, is 0", EXIT_OK,
                run(same, sch, none_registered))

        # 2/3. the pair that is the point of the exercise.
        drifted = write_repo(required_top=["name", "description"])
        control("an UNREGISTERED difference is 1", EXIT_DIVERGED,
                run(drifted, sch, none_registered))

        good_entry = {"property": "catalogue.required_top",
                      "repo_side": ["name", "description"],
                      "toolkit_side": list(cat["required_top"]),
                      "reason": "house rule, recorded on purpose"}
        control("...and 0 once it is registered with a reason", EXIT_OK,
                run(drifted, sch, write_exc([good_entry])))

        # 4. the mirror-image rule: an exemption for a divergence that no longer exists.
        control("a STALE exception (the sides now agree) is 1", EXIT_DIVERGED,
                run(same, sch, write_exc([good_entry])))

        # 5. ...and one whose sides still differ, but not in the recorded shape. Without this, one
        #    entry absorbs every future change to the same property.
        control("an exception recording the WRONG shape of a real difference is 1", EXIT_DIVERGED,
                run(write_repo(required_top=["name", "description", "invented"]), sch,
                    write_exc([good_entry])))

        # 6. an escape hatch without a reason is a silencer.
        no_reason = dict(good_entry)
        no_reason.pop("reason")
        control("an exception with no 'reason' is 1", EXIT_DIVERGED,
                run(drifted, sch, write_exc([no_reason])))
        control("an exception with an EMPTY 'reason' is 1", EXIT_DIVERGED,
                run(drifted, sch, write_exc([dict(good_entry, reason="   ")])))

        # 7. the exemption that outlived the property it named.
        control("an exception naming a property nothing compares is 1", EXIT_DIVERGED,
                run(same, sch, write_exc([{"property": "catalogue.required_gone",
                                           "repo_side": [], "toolkit_side": [],
                                           "reason": "renamed away"}])))

        # 8/9/10. a constant that cannot be read must FAIL, never fall back to a default -- a gate
        #         that compares four properties while reporting five is the defect, not the guard.
        control("a MISSING constant is 1, not a default", EXIT_DIVERGED,
                run(write_repo(drop=("MAX_DESC",)), sch, none_registered))
        control("a NON-LITERAL constant is 1, not a default", EXIT_DIVERGED,
                run(write_repo(nonliteral=("MAX_DESC",)), sch, none_registered))
        control("a missing inline placeholder list is 1, not a default", EXIT_DIVERGED,
                run(write_repo(drop_placeholders=True), sch, none_registered))

        # 11. field ORDER is not the contract; membership is. Without this the gate cries wolf on
        #     a reordering and gets registered around, which is how an exception list stops meaning
        #     anything.
        control("a REORDERED required-field list still agrees (order is not contract)", EXIT_OK,
                run(write_repo(required_plugin=list(reversed(bun["required_top"]))), sch,
                    none_registered))

        # 12. the schema losing a profile the repo side still enforces.
        noprof = tmp / "no-bundle.json"
        noprof.write_text(json.dumps(
            dict(schema, profiles=[p for p in schema["profiles"] if p["name"] != "bundle"])),
            encoding="utf-8")
        control("a schema with no matching profile is 1", EXIT_DIVERGED,
                run(same, noprof, none_registered))

        # 13. a missing registry is not an empty one.
        control("an ABSENT exception registry is 1, not an empty list", EXIT_DIVERGED,
                run(same, sch, tmp / "no-such-registry.json"))

        # 14. THE CONTROL THE EXIT CONTRACT EXISTS FOR. A distribution with only this toolkit in it
        #     must not report parity it could not measure.
        control("an ABSENT repo-side lint is 2 (NOT APPLICABLE), never 0", EXIT_SKIPPED,
                run(tmp / "does-not-exist.py", sch, none_registered))

        # 15. present but unparseable is the OTHER side of that split: it should have worked.
        broken = tmp / "broken.py"
        broken.write_text("REQUIRED_TOP = [\n", encoding="utf-8")
        control("a present-but-unparseable repo-side lint is 1, not 2", EXIT_DIVERGED,
                run(broken, sch, none_registered))

    # Against the SHIPPED pair, not a fixture: a parity check that never touches the real files
    # goes green while the two things it guards drift apart.
    # In a distribution with no repo-side lint the expectation is 2, not a free pass -- the control
    # has to be real in both worlds, or it evaporates exactly where the exit contract matters most.
    print("")
    control("the SHIPPED pair is in parity, or 2 where the repo side does not ship",
            EXIT_OK if REPO_LINT.is_file() else EXIT_SKIPPED,
            run(REPO_LINT, SCHEMA, EXCEPTIONS))

    print("")
    if failed:
        print("SELF-TEST FAILED -- %d control(s) misbehaved: %s" % (len(failed), ", ".join(failed)))
        return EXIT_DIVERGED
    print("SELF-TEST PASSED -- every control behaved as specified (%d)" % passed)
    return EXIT_OK


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--repo-lint", default=str(REPO_LINT),
                    help="the repo-side lint to parse (absent => exit 2, not applicable)")
    ap.add_argument("--schema", default=str(SCHEMA), help="the shipped contract, as data")
    ap.add_argument("--exceptions", default=str(EXCEPTIONS),
                    help="the registry of deliberate differences")
    ap.add_argument("--self-test", action="store_true",
                    help="run the negative controls and exit; writes only to a temp directory")
    args = ap.parse_args(argv)

    if args.self_test:
        return self_test()
    return run(Path(args.repo_lint), Path(args.schema), Path(args.exceptions))


if __name__ == "__main__":
    sys.exit(main())
