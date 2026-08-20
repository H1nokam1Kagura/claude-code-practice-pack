#!/usr/bin/env python3
"""lint_skills.py -- hold every SKILL.md in a tree to a frontmatter contract you declare.

WHAT IT IS FOR

    A skill's frontmatter is the only part of it that is read before anyone decides to use it.
    The body can be as long as it likes and costs nothing until invoked; the frontmatter is
    loaded up front, for every skill, in every session. So it is the one part worth gating --
    and the one part a generator, a copy-paste, or a half-finished template will quietly break.

    The contract itself is NOT in this file. It is in skill-schema.json, because a contract
    hardcoded in a script is a contract only its author can change. This script is the
    mechanism; the schema is the policy.

WHAT IT ASSERTS

    1. Every file the profile claims has parseable frontmatter.
    2. Every required field is present AND not a placeholder. 'TBD' is not a filled field.
    3. `description` is inside the budget you set, and is not empty.
    4. `name` and `slash_command`, WHERE THE PROFILE ASKS FOR THEM, match the directory.
       `slash_command` is a LOCAL EXTENSION, not one of the frontmatter fields accepted outside
       the CLI, so no profile demands it -- a schema that required it would mandate a top-level
       key that fails packaging with a hard error. Carried, it is checked; absent, it passes.
    5. A profile whose containers exist but whose files do not is an ERROR, not a pass.
       Zero coverage reported as success is the failure this whole class of gate exists for.
    6. --self-test only: the worked exemplar in SKILL-FRONTMATTER.md and the live one in the
       example skill's `risk_factors` still say the same thing, compared with whitespace
       collapsed. Two copies of a block with nothing comparing them is how prose goes stale.

    What it cannot assert is whether the description is any GOOD -- whether it would actually
    get the skill invoked at the right moment, and only then. No regex will tell you that.
    That is what eval_skills.py measures, and the two are not substitutes for each other.

USAGE
    python lint_skills.py <tree-root>
    python lint_skills.py <tree-root> --schema my-schema.json --profile catalogue
    python lint_skills.py --self-test        # the negative controls; writes only to temp

EXIT CONTRACT
    0  every profile that applies ran and passed
    1  a check FAILED, or a profile's containers exist with no SKILL.md in them
    2  no profile matched anything here, or PyYAML is not installed -- NOT APPLICABLE or
       COULD NOT RUN. Never a pass: nothing was measured, so nothing is known.

REQUIRES PyYAML. Frontmatter is YAML, and a hand-rolled parser that disagrees with the real
one on a quoted colon is worse than a missing check -- it would pass files the platform
rejects. Python 3.8+.
"""
from __future__ import annotations

import argparse
import fnmatch
import functools
import json
import re
import sys
import tempfile
from pathlib import Path

print = functools.partial(print, flush=True)  # noqa: A001

EXIT_OK, EXIT_FAIL, EXIT_NOT_APPLICABLE = 0, 1, 2

DEFAULT_SCHEMA = Path(__file__).with_name("skill-schema.json")
DOC = Path(__file__).with_name("SKILL-FRONTMATTER.md")
EXEMPLAR_SKILL = Path(__file__).parent / "examples" / "skills" / "incident-triage" / "SKILL.md"

# Rows in the prose table look like:  | `owner` | ... |
_DOC_FIELD_ROW = re.compile(r"^\|\s*`([a-z_]+)`\s*\|")


def load_schema(path: Path) -> dict:
    schema = json.loads(path.read_text(encoding="utf-8"))
    for key in ("description_max_chars", "placeholder_values", "fields", "profiles"):
        if key not in schema:
            raise ValueError(
                "%s has no '%s' -- refusing to lint against a half-declared contract" % (path, key))
    if not schema["profiles"]:
        raise ValueError("%s declares no profiles -- that would pass by checking nothing" % path)
    known = set(schema["fields"])
    for prof in schema["profiles"]:
        unknown = [f for f in prof.get("required_metadata", []) if f not in known]
        if unknown:
            raise ValueError(
                "profile '%s' requires metadata field(s) %s that 'fields' does not describe -- "
                "a field nobody wrote down is a field nobody can fill correctly"
                % (prof.get("name", "?"), ", ".join(unknown)))
    return schema


def read_frontmatter(path: Path) -> "tuple[dict | None, str]":
    """Return (frontmatter, error). Exactly one of the two is meaningful."""
    import yaml  # deferred: --self-test still needs it, but the import error is reported once

    raw = path.read_text(encoding="utf-8", errors="replace")
    if not raw.lstrip("﻿").startswith("---"):
        return None, "no frontmatter block (file does not open with ---)"
    parts = raw.lstrip("﻿").split("---", 2)
    if len(parts) < 3:
        return None, "malformed frontmatter (no closing --- fence)"
    try:
        fm = yaml.safe_load(parts[1])
    except yaml.YAMLError as e:
        return None, "YAML parse error -- %s" % str(e).replace("\n", " ")
    if fm is None:
        return {}, ""
    if not isinstance(fm, dict):
        return None, "frontmatter is a %s, not a mapping" % type(fm).__name__
    return fm, ""


class Result:
    def __init__(self, name: str):
        self.name, self.failures, self.candidates, self.status = name, [], 0, "PASS"

    def fail(self, msg: str):
        self.failures.append(msg)
        self.status = "FAIL"

    def seal(self):
        if self.candidates == 0 and self.status == "PASS":
            self.status = "NOT APPLICABLE"
        return self


def _is_placeholder(value, placeholders: "list[str]") -> bool:
    if value is None:
        return True
    s = str(value).strip()
    return s == "" or s in placeholders


def check_profile(root: Path, profile: dict, schema: dict) -> Result:
    r = Result(profile["name"])
    placeholders = schema["placeholder_values"]
    max_desc = schema["description_max_chars"]

    paths = sorted(p for p in root.glob(profile["glob"]) if p.is_file())
    containers = sorted(p for p in root.glob(profile.get("container_glob") or "") if p.is_dir())

    # Containers with no files is a stale glob or a moved tree, and it is the one outcome that
    # must never read as success -- "I found nothing" and "there is nothing wrong" are different
    # results and the whole point of this gate is that they do not share an exit code.
    if containers and not paths:
        r.fail("profile '%s': %d container(s) exist but no file matches '%s' -- the glob is stale "
               "or the tree moved; refusing to report zero coverage as success"
               % (profile["name"], len(containers), profile["glob"]))
        return r

    for path in paths:
        r.candidates += 1
        label = path.parent.name
        dirname = path.parent.name

        fm, err = read_frontmatter(path)
        if fm is None:
            r.fail("%s: %s" % (label, err))
            continue

        for field in profile.get("required_top", []):
            if _is_placeholder(fm.get(field), placeholders):
                r.fail("%s: top-level '%s' is missing or a placeholder" % (label, field))

        desc = fm.get("description")
        if desc is not None:
            desc_str = (desc if isinstance(desc, str) else str(desc)).strip()
            if desc_str and len(desc_str) > max_desc:
                r.fail("%s: description is %d chars, over the %d-char budget you set"
                       % (label, len(desc_str), max_desc))

        if profile.get("name_matches_directory") and fm.get("name") not in (None, ""):
            if str(fm["name"]) != dirname:
                r.fail("%s: name='%s' does not match its directory '%s'"
                       % (label, fm["name"], dirname))

        if profile.get("slash_command_matches_directory") and fm.get("slash_command"):
            want = "/%s" % dirname
            if str(fm["slash_command"]) != want:
                r.fail("%s: slash_command='%s' should be '%s' -- the command a user types and the "
                       "skill that answers have drifted apart"
                       % (label, fm["slash_command"], want))

        required_meta = profile.get("required_metadata", [])
        if not required_meta:
            continue
        meta = fm.get("metadata")
        if meta is None:
            r.fail("%s: no 'metadata' block, so none of the %d required governance field(s) can "
                   "be present" % (label, len(required_meta)))
            continue
        if not isinstance(meta, dict):
            # Worth its own message: a non-map metadata value is DROPPED rather than rejected,
            # so this fails silently everywhere else and the fields simply cease to exist.
            r.fail("%s: 'metadata' is a %s, not a mapping -- a non-map value is dropped, so every "
                   "field under it silently disappears" % (label, type(meta).__name__))
            continue
        for field in required_meta:
            if _is_placeholder(meta.get(field), placeholders):
                r.fail("%s: metadata.%s is missing or a placeholder" % (label, field))

    return r.seal()


def check_doc_parity(schema: dict, doc: Path) -> "Result | None":
    """The prose table and the schema must name the same governance fields.

    Returns None when the document is not present -- a recipient who copied only the two code
    files has nothing to compare, and reporting that as a failure would be a check complaining
    about its own packaging.
    """
    if not doc.is_file():
        return None
    r = Result("doc-parity")
    documented = set()
    for line in doc.read_text(encoding="utf-8", errors="replace").splitlines():
        m = _DOC_FIELD_ROW.match(line.strip())
        if m:
            documented.add(m.group(1))
    declared = set(schema["fields"])
    r.candidates = len(declared)
    for f in sorted(declared - documented):
        r.fail("schema declares '%s' but %s does not describe it -- a governance field with no "
               "stated purpose gets filled with whatever the author guessed" % (f, doc.name))
    for f in sorted(documented - declared):
        r.fail("%s describes '%s' but the schema does not declare it -- the prose is asking for a "
               "field nothing checks" % (doc.name, f))
    return r.seal()


def _collapse(text) -> str:
    """Whitespace-insensitive form, so line-wrapping is not mistaken for divergence."""
    return " ".join(str(text).split())


def _fenced_blocks(text: str) -> "list[str]":
    blocks, cur, inside = [], [], False
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            if inside:
                blocks.append("\n".join(cur))
                cur, inside = [], False
            else:
                inside = True
            continue
        if inside:
            cur.append(line)
    return blocks


def check_exemplar_parity(doc: Path, skill: Path) -> "Result | None":
    """The worked exemplar in the prose and the live one in the example skill must agree.

    The same risk_factors block is written twice: once in SKILL-FRONTMATTER.md as the shape being
    argued for, once in the example skill as the thing the lint and the eval actually read. Two
    copies with nothing comparing them is the exact failure this pack names elsewhere -- correct
    one, and the other keeps asserting the old text with no error anywhere. The two are wrapped
    differently on purpose, so the comparison is on collapsed text, not byte-for-byte.

    Returns None when either file is absent: a recipient who copied only the code has nothing to
    compare, and reporting that as a failure would be a check complaining about its own packaging.
    """
    import yaml

    if not doc.is_file() or not skill.is_file():
        return None
    r = Result("exemplar-parity")
    r.candidates = 1

    blocks = [b for b in _fenced_blocks(doc.read_text(encoding="utf-8", errors="replace"))
              if "risk_factors:" in b]
    if not blocks:
        r.fail("%s has no fenced block containing 'risk_factors:' -- the prose stopped showing the "
               "shape it argues for, so there is nothing left to hold the example skill to"
               % doc.name)

    quoted = None
    if blocks:
        try:
            parsed = yaml.safe_load(blocks[0])
            quoted = parsed.get("risk_factors") if isinstance(parsed, dict) else None
        except yaml.YAMLError as e:
            r.fail("%s: the exemplar block is not parseable YAML -- %s"
                   % (doc.name, str(e).replace("\n", " ")))
        if blocks and quoted is None and not r.failures:
            r.fail("%s: the exemplar block parses but carries no 'risk_factors' value" % doc.name)

    live = None
    fm, err = read_frontmatter(skill)
    if fm is None:
        r.fail("%s: %s" % (skill.name, err))
    else:
        meta = fm.get("metadata")
        live = meta.get("risk_factors") if isinstance(meta, dict) else None
        if live is None:
            r.fail("%s: no metadata.risk_factors, so the prose exemplar is quoting a field the "
                   "example skill no longer carries" % skill.name)

    if quoted is not None and live is not None and _collapse(quoted) != _collapse(live):
        r.fail("the exemplar in %s and metadata.risk_factors in %s have diverged (compared with "
               "whitespace collapsed, so this is not a wrapping difference) -- one was edited and "
               "the other kept asserting the old text" % (doc.name, skill.name))
    return r


def run(root: Path, schema_path: Path, only: "list[str] | None", doc: Path = DOC) -> int:
    try:
        import yaml  # noqa: F401
    except ImportError:
        print("!! PyYAML is not installed, so no frontmatter could be parsed.")
        print("   exit 2 -- COULD NOT RUN. That is not a pass. `pip install PyYAML`.")
        return EXIT_NOT_APPLICABLE

    try:
        schema = load_schema(schema_path)
    except (OSError, ValueError, json.JSONDecodeError) as e:
        print("!! cannot use schema %s: %s" % (schema_path, e))
        print("   A gate whose contract will not load must not report PASS.")
        return EXIT_FAIL

    if not root.is_dir():
        print("!! %s is not a directory. A check that cannot locate its subject must not pass."
              % root)
        return EXIT_FAIL

    profiles = [p for p in schema["profiles"] if not only or p["name"] in only]
    if only:
        missing = [n for n in only if n not in {p["name"] for p in schema["profiles"]}]
        if missing:
            print("!! no such profile(s): %s" % ", ".join(missing))
            return EXIT_FAIL

    results = [check_profile(root, p, schema) for p in profiles]
    parity = check_doc_parity(schema, doc)

    print("")
    print("SKILL FRONTMATTER LINT -- %s" % root)
    print("   contract: %s (description budget %d chars)"
          % (schema_path.name, schema["description_max_chars"]))
    print("=" * 78)
    for res in results:
        print("  %-18s %-16s %d file(s)" % (res.name, res.status, res.candidates))
        for f in res.failures:
            print("      - %s" % f)
    if parity is None:
        print("  %-18s %-16s %s not present beside the schema"
              % ("doc-parity", "NOT APPLICABLE", doc.name))
    else:
        print("  %-18s %-16s %d field(s)" % (parity.name, parity.status, parity.candidates))
        for f in parity.failures:
            print("      - %s" % f)
    print("=" * 78)

    checked = results + ([parity] if parity else [])
    if any(r.status == "FAIL" for r in checked):
        print("  exit 1 -- FAILED")
        return EXIT_FAIL
    if all(r.status == "NOT APPLICABLE" for r in results):
        print("  exit 2 -- no profile matched a single file under %s. Point it at the tree that" % root)
        print("            holds your skills, or add a profile whose glob reaches them. Nothing")
        print("            was measured here, so this is not a pass.")
        return EXIT_NOT_APPLICABLE
    print("  exit 0 -- every field the contract requires is present and inside budget")
    print("            (it cannot tell you whether the descriptions are any good -- that is")
    print("             what eval_skills.py measures, and it is a different question)")
    return EXIT_OK


# ---------------------------------------------------------------------------------------------
# SELF-TEST -- a gate that has never been red is not evidence.

def _skill(root: Path, name: str, front: str, body: str = "Body.\n") -> None:
    d = root / name
    d.mkdir(parents=True, exist_ok=True)
    (d / "SKILL.md").write_text("---\n%s---\n\n%s" % (front, body), encoding="utf-8")


GOOD_FRONT = (
    "name: alpha\n"
    "description: Does the alpha thing when someone asks for the alpha thing.\n"
    "metadata:\n"
    "  owner: someone@example.invalid\n"
    "  risk_tier: 1\n"
    "  approved_by: someone@example.invalid\n"
    '  review_date: "2026-11-01"\n'
)

# The bundle profile's shape: an invocation name and a description, no governance block. A
# generated file carries no metadata, which is why that profile requires none.
BUNDLE_FRONT = (
    "name: alpha\n"
    "description: Does the alpha thing when someone asks for the alpha thing.\n"
)


def _status(res: "Result | None") -> str:
    return res.status if res else "NOT APPLICABLE"


def self_test() -> int:
    passed, failed = 0, []

    def control(name: str, expected, actual):
        nonlocal passed
        ok = expected == actual
        print("  [%s] %-62s expected %s, got %s"
              % ("ok  " if ok else "FAIL", name, expected, actual))
        if ok:
            passed += 1
        else:
            failed.append(name)

    schema = json.loads(DEFAULT_SCHEMA.read_text(encoding="utf-8"))

    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        sch = tmp / "schema.json"

        def write_schema(mutate=None):
            s = json.loads(json.dumps(schema))
            if mutate:
                mutate(s)
            sch.write_text(json.dumps(s), encoding="utf-8")

        write_schema()

        clean = tmp / "clean"
        _skill(clean, "alpha", GOOD_FRONT)
        control("a complete skill passes", EXIT_OK, run(clean, sch, ["catalogue"], tmp / "none.md"))

        # Each of the next four is a way a real file goes wrong without looking wrong.
        missing = tmp / "missing"
        _skill(missing, "alpha", GOOD_FRONT.replace("  owner: someone@example.invalid\n", ""))
        control("a missing required governance field FAILS", EXIT_FAIL,
                run(missing, sch, ["catalogue"], tmp / "none.md"))

        tbd = tmp / "tbd"
        _skill(tbd, "alpha", GOOD_FRONT.replace("someone@example.invalid", "TBD", 1))
        control("a placeholder ('TBD') is not a filled field", EXIT_FAIL,
                run(tbd, sch, ["catalogue"], tmp / "none.md"))

        nomap = tmp / "nomap"
        _skill(nomap, "alpha",
               "name: alpha\ndescription: Does the alpha thing.\nmetadata: not-a-mapping\n")
        control("metadata that is not a mapping FAILS (it is dropped, not rejected)", EXIT_FAIL,
                run(nomap, sch, ["catalogue"], tmp / "none.md"))

        mismatch = tmp / "mismatch"
        _skill(mismatch, "alpha", GOOD_FRONT.replace("name: alpha", "name: beta"))
        control("name that disagrees with its directory FAILS", EXIT_FAIL,
                run(mismatch, sch, ["catalogue"], tmp / "none.md"))

        # ...and the inverse control, which is the one this tool got wrong first: 'name' is a
        # display label in a personal or project skill and the platform does not require it.
        # Demanding it is a house rule, so an absent name must PASS unless the schema asks for it.
        noname = tmp / "noname"
        _skill(noname, "alpha", GOOD_FRONT.replace("name: alpha\n", ""))
        control("an ABSENT name passes -- the platform does not require it", EXIT_OK,
                run(noname, sch, ["catalogue"], tmp / "none.md"))

        write_schema(lambda s: s["profiles"][0]["required_top"].append("name"))
        control("...and FAILS once the schema asks for it", EXIT_FAIL,
                run(noname, sch, ["catalogue"], tmp / "none.md"))
        write_schema()

        # The same pair for the bundle profile's 'slash_command', which used to be in required_top
        # and should never have been: it is not one of the six frontmatter fields accepted outside
        # the CLI, so demanding it made the schema mandate a top-level key that fails packaging
        # with a hard error. It is a local extension now -- checked when present, never demanded --
        # and both halves of that have to hold or the field is either unenforced or unportable.
        nocmd = tmp / "nocmd"
        _skill(nocmd, "plugin-a/skills/alpha", BUNDLE_FRONT)
        control("an ABSENT slash_command passes -- a local extension is not demanded", EXIT_OK,
                run(nocmd, sch, ["bundle"], tmp / "none.md"))

        badcmd = tmp / "badcmd"
        _skill(badcmd, "plugin-a/skills/alpha", BUNDLE_FRONT + "slash_command: /beta\n")
        control("...and a PRESENT one disagreeing with its directory still FAILS", EXIT_FAIL,
                run(badcmd, sch, ["bundle"], tmp / "none.md"))

        # The worked exemplar is written twice -- prose and example skill -- and until now nothing
        # compared them. Wrapping differs between the two by design, so a byte comparison would
        # fail forever and get deleted; the collapsed comparison is the one that can stay on.
        ex_skill = tmp / "ex-skill"
        _skill(ex_skill, "alpha",
               "name: alpha\ndescription: Does the alpha thing.\nmetadata:\n"
               "  risk_factors: >\n    One chokepoint, one named test,\n"
               "    and the condition it fails on.\n")
        ex_live = ex_skill / "alpha" / "SKILL.md"

        ex_ok = tmp / "ex-ok.md"
        ex_ok.write_text("Prose.\n\n```\n  risk_tier: 2\n  risk_factors: >\n"
                         "    One chokepoint, one named test, and the\n    condition it fails on.\n"
                         "```\n", encoding="utf-8")
        control("a re-wrapped exemplar copy passes -- wrapping is not divergence", "PASS",
                _status(check_exemplar_parity(ex_ok, ex_live)))

        ex_drift = tmp / "ex-drift.md"
        ex_drift.write_text("Prose.\n\n```\n  risk_tier: 2\n  risk_factors: >\n"
                            "    One chokepoint and a test.\n```\n", encoding="utf-8")
        control("an exemplar copy whose WORDS changed FAILS", "FAIL",
                _status(check_exemplar_parity(ex_drift, ex_live)))

        ex_gone = tmp / "ex-gone.md"
        ex_gone.write_text("Prose with no fenced block at all.\n", encoding="utf-8")
        control("prose that stopped showing the exemplar FAILS", "FAIL",
                _status(check_exemplar_parity(ex_gone, ex_live)))

        longd = tmp / "longd"
        _skill(longd, "alpha", GOOD_FRONT.replace(
            "Does the alpha thing when someone asks for the alpha thing.", "x" * 2000))
        control("a description over budget FAILS", EXIT_FAIL,
                run(longd, sch, ["catalogue"], tmp / "none.md"))

        broken = tmp / "broken"
        _skill(broken, "alpha", "name: alpha\ndescription: [unclosed\n")
        control("unparseable YAML FAILS", EXIT_FAIL,
                run(broken, sch, ["catalogue"], tmp / "none.md"))

        nofront = tmp / "nofront"
        (nofront / "alpha").mkdir(parents=True)
        (nofront / "alpha" / "SKILL.md").write_text("# alpha\n\nNo frontmatter here.\n",
                                                    encoding="utf-8")
        control("a file with no frontmatter at all FAILS", EXIT_FAIL,
                run(nofront, sch, ["catalogue"], tmp / "none.md"))

        # The control this whole exit contract exists for.
        empty = tmp / "empty"
        empty.mkdir()
        control("an empty tree is 2 (NOT APPLICABLE), never 0", EXIT_NOT_APPLICABLE,
                run(empty, sch, ["catalogue"], tmp / "none.md"))

        stale = tmp / "stale"
        (stale / "alpha" / "nested").mkdir(parents=True)   # a container, but no SKILL.md
        control("containers with no SKILL.md is 1, not 2 -- the glob went stale", EXIT_FAIL,
                run(stale, sch, ["catalogue"], tmp / "none.md"))

        control("a missing tree is 1, never a pass", EXIT_FAIL,
                run(tmp / "does-not-exist", sch, ["catalogue"], tmp / "none.md"))

        bad = tmp / "bad-schema.json"
        bad.write_text('{"fields": {}}', encoding="utf-8")
        control("a half-declared schema is 1, not a pass", EXIT_FAIL,
                run(clean, bad, None, tmp / "none.md"))

        # Doc/schema parity, in both directions.
        doc_ok = tmp / "doc-ok.md"
        doc_ok.write_text("| Field | Purpose |\n|---|---|\n" + "".join(
            "| `%s` | %s |\n" % (f, p) for f, p in schema["fields"].items()), encoding="utf-8")
        control("prose table matching the schema passes parity", EXIT_OK,
                run(clean, sch, ["catalogue"], doc_ok))

        doc_short = tmp / "doc-short.md"
        doc_short.write_text("| Field | Purpose |\n|---|---|\n| `owner` | who answers |\n",
                             encoding="utf-8")
        control("a schema field the prose never describes FAILS parity", EXIT_FAIL,
                run(clean, sch, ["catalogue"], doc_short))

        doc_extra = doc_ok.read_text(encoding="utf-8") + "| `invented_field` | nothing checks me |\n"
        (tmp / "doc-extra.md").write_text(doc_extra, encoding="utf-8")
        control("prose asking for a field nothing checks FAILS parity", EXIT_FAIL,
                run(clean, sch, ["catalogue"], tmp / "doc-extra.md"))

    # Against the SHIPPED pair, not a fixture: a parity check that never touches the real files
    # goes green while the two things it guards drift apart.
    live = check_doc_parity(json.loads(DEFAULT_SCHEMA.read_text(encoding="utf-8")), DOC)
    control("the SHIPPED schema and prose table agree", "PASS", _status(live))
    if live and live.failures:
        for f in live.failures:
            print("      - %s" % f)

    shipped_exemplar = check_exemplar_parity(DOC, EXEMPLAR_SKILL)
    control("the SHIPPED exemplar and the example skill's risk_factors agree", "PASS",
            _status(shipped_exemplar))
    if shipped_exemplar and shipped_exemplar.failures:
        for f in shipped_exemplar.failures:
            print("      - %s" % f)

    print("")
    if failed:
        print("SELF-TEST FAILED -- %d control(s) misbehaved: %s" % (len(failed), ", ".join(failed)))
        return EXIT_FAIL
    print("SELF-TEST PASSED -- every control behaved as specified (%d)" % passed)
    return EXIT_OK


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("root", nargs="?", help="directory holding the skill tree")
    ap.add_argument("--schema", default=str(DEFAULT_SCHEMA), help="the contract to lint against")
    ap.add_argument("--profile", action="append", help="only this profile (repeatable)")
    ap.add_argument("--self-test", action="store_true",
                    help="run the negative controls and exit; writes only to a temp directory")
    args = ap.parse_args(argv)

    if args.self_test:
        try:
            import yaml  # noqa: F401
        except ImportError:
            print("!! PyYAML is not installed, so the controls could not run. exit 2, not a pass.")
            return EXIT_NOT_APPLICABLE
        return self_test()
    if not args.root:
        ap.error("a tree root is required (or use --self-test)")
    return run(Path(args.root), Path(args.schema), args.profile)


if __name__ == "__main__":
    sys.exit(main())
