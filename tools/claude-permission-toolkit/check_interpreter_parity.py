#!/usr/bin/env python3
"""Gate the two arbitrary-execution detectors against each other.

Two tools in this repo independently answer the same question -- "does this allow rule hand over
an interpreter?" -- and they must not disagree:

    tools/claude-permission-toolkit/replay_permissions.py   _INTERPRETERS
    skills/build-compliance/scripts/checks/harness.py       _INTERPRETERS

WHY A GATE RATHER THAN A SHARED MODULE
    Neither tool may import the other. `build-compliance` ships as a self-contained skill and the
    permission toolkit ships as a standalone bundle; a shared import would break both on the way
    out the door. So the duplication is deliberate, and this is the control that makes it safe.
    Same pattern, same reason, as the `via` vocabulary parity checker on the sibling stack: keep
    the copies, gate the copies.

WHY IT EXISTS AT ALL
    Measured 2026-08-15, before this gate: run against the same 111 allow rules, one tool found 10
    interpreter grants and the other 12. The two it missed were `Bash(env *)` (env runs any command
    you name after it) and `Bash(wsl.exe *)` (the list held "wsl" but not the ".exe" spelling).
    Neither was visible by reading either list. "Keep these in sync by hand" is not a control --
    it is the absence of one.

    The root cause of the second was enumerating SPELLINGS instead of programs, so both sides now
    store base names and strip a trailing ".exe" before lookup. This gate also checks that
    normalisation, because a matching pair of lists proves nothing if the lookup differs.

USAGE
    python check_interpreter_parity.py          # exit 0 = in parity

EXIT CONTRACT
    0  the two sets and their normalisation agree
    1  they diverge -- the divergence is named -- OR both files are present and one would not
       import, which is INCONCLUSIVE: it ran and measured nothing, which is a failure
    2  the other detector is not in this tree at all, so this gate does not apply here. That is a
       scope fact, not a defect. Nothing was compared; still never a pass.

    The 1-versus-2 split is the one the practice documents insist on: "I chose not to run this" and
    "it ran and measured nothing" must not share an exit code. NOTE WHICH SIDE IS WHICH HERE --
    a missing sibling is the scope case (2), because this toolkit ships without it by design; an
    unimportable sibling that IS present is the failure case (1).

REQUIRES THE FULL REPOSITORY. The second detector lives in the build-compliance skill, not in this
toolkit. Distributed on its own, this file exits 2 and says so -- it does not report parity it did
not measure.
"""
from __future__ import annotations

import argparse
import functools
import importlib
import importlib.util
import sys
from pathlib import Path

print = functools.partial(print, flush=True)  # noqa: A001

EXIT_OK, EXIT_DIVERGED, EXIT_SKIPPED = 0, 1, 2
EXIT_INCONCLUSIVE = 1  # "it ran and measured nothing" is a failure, not a skip -- same code as diverged

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
HARNESS = REPO / "skills" / "build-compliance" / "scripts" / "checks" / "harness.py"
REPLAY = HERE / "replay_permissions.py"

# Probes that must classify identically on both sides. Each is a spelling that has actually
# appeared in a real allow-list on this host, plus the negatives that must stay negative.
PROBES = [
    ("Bash(pwsh *)", True),
    ("Bash(powershell *)", True),
    ("Bash(wsl.exe *)", True),          # the ".exe" spelling that slipped through
    ("Bash(env *)", True),              # runs any command named after it
    ("Bash(/usr/bin/python3 -m x)", True),
    ("Bash(C:/Program Files/PowerShell/7/pwsh.exe -File x)", True),
    ("PowerShell", True),               # bare tool == the whole tool
    ("Bash(*python.exe *)", True),      # venv interpreter allowed by path
    ("Bash(ls *)", False),
    ("Bash(git *)", False),             # broad, but not an interpreter
    ("Bash(docker *)", False),
    ("Read(**/.env)", False),           # not a command tool at all
    ("mcp__x__query", False),
]


def _load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load {path}")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0] if __doc__ else None)
    # The second side is named, not discovered. A distribution lays the compliance half out
    # differently from this repository, and a gate that GUESSED where it might be would report
    # "not applicable" on a tree that actually has it -- exit 2 for the wrong reason, which reads
    # identically to exit 2 for the right one. An explicit path makes the miss a typo you can see.
    ap.add_argument("--harness", default=str(HARNESS),
                    help="the other detector to compare against (absent => exit 2, not applicable)")
    args = ap.parse_args(argv)
    harness_path = Path(args.harness)

    # NOT APPLICABLE is a different outcome from FAILED TO RUN, and only one of them is a defect.
    #
    # This gate compares two independently written detectors. The other one lives in the
    # build-compliance skill, OUTSIDE this toolkit -- so in a distribution that contains only
    # `tools/claude-permission-toolkit/`, the second side is not missing, it was never shipped.
    # That is a scope fact, not a fault: exit 2, said plainly, so a recipient is not handed a red
    # gate on first run and taught to ignore it.
    #
    # An import that fails while the file IS present is the opposite: it should have worked. That is
    # INCONCLUSIVE -- it ran and measured nothing -- which the practice docs assign to 1, not 2.
    # Collapsing the two is how "coverage you did not measure" gets reported as coverage you have.
    if not harness_path.exists():
        print(f"-- not applicable here: {harness_path.name} is not in this tree.")
        print("   This gate compares two detectors and only one of them ships with this toolkit.")
        print("   Run it from the full repository. Nothing was compared; this is NOT a pass.")
        return EXIT_SKIPPED

    try:
        # harness.py opens with `from . import ...`, so it must be imported AS PART OF its package
        # (`checks`) -- loading the file standalone raises "attempted relative import with no known
        # parent package". Put scripts/ on the path and import by dotted name instead.
        sys.path.insert(0, str(harness_path.parent.parent))
        harness = importlib.import_module("checks.harness")
        replay = _load(REPLAY, "_parity_replay")
    except Exception as e:  # noqa: BLE001 -- present but unimportable: it should have worked
        print(f"!! could not import both sides ({e.__class__.__name__}: {e})")
        print("   Both files are present, so this is a defect, not a scope limit.")
        print("   Nothing was compared. INCONCLUSIVE, never a pass.")
        return EXIT_INCONCLUSIVE

    a = set(harness._INTERPRETERS)
    b = set(replay._INTERPRETERS)
    failed = False

    if a != b:
        failed = True
        print("!! interpreter sets diverge")
        for name, extra in (("harness.py only", a - b), ("replay_permissions.py only", b - a)):
            if extra:
                print(f"   {name}: {', '.join(sorted(extra))}")
    else:
        print(f"ok  interpreter sets agree ({len(a)} entries)")

    # A matching pair of lists proves nothing if the two lookups normalise differently.
    mismatches = []
    for rule, expected in PROBES:
        h = harness.is_arbitrary_execution(*harness.parse_rule(rule))
        r = bool(replay.Ruleset([], [], [rule]).arbitrary_execution_grants())
        if h != r or h != expected:
            mismatches.append((rule, expected, h, r))

    if mismatches:
        failed = True
        print(f"!! {len(mismatches)} probe(s) classified inconsistently")
        print(f"   {'rule':<52} {'want':<6} {'harness':<8} replay")
        for rule, exp, h, r in mismatches:
            print(f"   {rule:<52} {str(exp):<6} {str(h):<8} {r}")
    else:
        print(f"ok  {len(PROBES)} probes classify identically on both sides")

    if failed:
        print("\n!! Parity FAILED. Update BOTH lists, or the two tools will report different")
        print("   blast radii for the same settings file and neither reader will know which to")
        print("   believe.")
        return EXIT_DIVERGED

    print("\nok  exit 0 -- the two detectors are in parity")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
