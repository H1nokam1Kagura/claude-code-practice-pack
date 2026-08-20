#!/usr/bin/env python3
"""Gate the two secret-guard implementations against each other.

The guard ships twice -- secret-guard.ps1 and secret_guard.py -- so that a recipient without pwsh
still gets the enforcement half of broad-allow-plus-hook-deny. Two copies of a security control
that are kept in step by hand are not a control; they are two controls that will disagree, quietly,
at the worst possible moment. So this is the thing that keeps them honest.

    Same pattern and same reason as check_interpreter_parity.py beside it: keep the copies, gate
    the copies. That gate found a real divergence on its first run -- 10 versus 12 -- with each
    side missing something the other caught. Neither gap was visible by reading either list.

WHAT IT ASSERTS -- both halves matter
    1. the two guards return the SAME verdict for every probe in guard-probes.json
    2. that verdict is the EXPECTED one
    Agreement alone is worthless: two implementations that agree with each other and disagree with
    guard-probes.json are just one wrong guard with a spare.

USAGE
    python check_guard_parity.py            # exit 0 = in parity

EXIT CONTRACT
    0  both guards ran over every probe and agreed with each other and with the expectation
    1  they diverged, OR a probe got the wrong verdict, OR pwsh is present and the PowerShell
       guard would not run. All three are failures; the last is INCONCLUSIVE, which is a failure,
       because it ran and measured nothing.
    2  pwsh is not on this machine, so half the comparison cannot be made. NOT APPLICABLE, which
       is a scope fact rather than a defect -- and still never a pass.

    The 1-versus-2 split is the one the practice documents insist on: "I could not run this here"
    and "it ran and measured nothing" must not share an exit code. Note which is which -- a
    missing pwsh is the scope case (2) because this toolkit is meant to be usable without it; a
    pwsh that is present and fails is the defect case (1).

STDLIB ONLY. Python 3.8+.
"""
from __future__ import annotations

import functools
import json
import shutil
import subprocess
import sys
from pathlib import Path

print = functools.partial(print, flush=True)  # noqa: A001

EXIT_OK, EXIT_DIVERGED, EXIT_SKIPPED = 0, 1, 2
EXIT_INCONCLUSIVE = 1  # ran and measured nothing -- a failure, same code as diverged

HERE = Path(__file__).resolve().parent
PROBES = HERE / "guard-probes.json"
PS_GUARD = HERE / "secret-guard.ps1"
PY_GUARD = HERE / "secret_guard.py"


def _payload(tool: str, command: str) -> str:
    return json.dumps({"tool_name": tool, "tool_input": {"command": command}})


def _blocks(stdout: str) -> bool:
    """A guard blocks by emitting a deny decision. Silence is an allow.

    Anything that is neither -- output that will not parse, or parses without a deny -- raises,
    because a guard whose output cannot be read is not a guard that allowed the command.
    """
    text = (stdout or "").strip()
    if not text:
        return False
    decision = json.loads(text)["hookSpecificOutput"]["permissionDecision"]
    if decision != "deny":
        raise ValueError("unexpected permissionDecision %r" % decision)
    return True


def _run(cmd: "list[str]", payload: str) -> bool:
    p = subprocess.run(cmd, input=payload, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError("guard exited %d: %s" % (p.returncode, (p.stderr or "").strip()[:200]))
    return _blocks(p.stdout)


def main() -> int:
    if not PROBES.exists():
        print("!! guard-probes.json is missing -- refusing to compare against nothing.")
        return EXIT_INCONCLUSIVE
    probes = json.loads(PROBES.read_text(encoding="utf-8"))["probes"]
    if not probes:
        print("!! guard-probes.json has no probes -- that would pass by checking nothing.")
        return EXIT_INCONCLUSIVE

    pwsh = shutil.which("pwsh") or shutil.which("powershell")
    if not pwsh:
        # NOT APPLICABLE, not FAILED. This toolkit is meant to be usable on a machine with no
        # PowerShell; handing such a recipient a red gate on first run teaches them to ignore it.
        print("-- not applicable here: no pwsh on PATH, so the PowerShell guard cannot be run.")
        print("   Only half the comparison exists on this machine. Nothing was compared;")
        print("   this is NOT a pass. Run test_secret_guard.py for the Python guard on its own.")
        return EXIT_SKIPPED

    for path in (PS_GUARD, PY_GUARD):
        if not path.exists():
            print("!! %s is missing while the other guard is present." % path.name)
            print("   Both should ship together. Nothing was compared. INCONCLUSIVE.")
            return EXIT_INCONCLUSIVE

    ps_cmd = [pwsh, "-NoProfile", "-File", str(PS_GUARD)]
    py_cmd = [sys.executable, str(PY_GUARD)]

    diverged, wrong, gaps = [], [], 0
    for probe in probes:
        payload = _payload(probe["tool"], probe["command"])
        try:
            ps = _run(ps_cmd, payload)
            py = _run(py_cmd, payload)
        except Exception as e:  # noqa: BLE001 -- present but unrunnable: it should have worked
            print("!! probe %r could not be run (%s: %s)" % (probe["id"], e.__class__.__name__, e))
            print("   Both guards are present, so this is a defect, not a scope limit.")
            print("   Nothing conclusive was measured. INCONCLUSIVE, never a pass.")
            return EXIT_INCONCLUSIVE

        expected = bool(probe["expect_block"])
        if ps != py:
            diverged.append((probe["id"], ps, py))
        elif ps != expected:
            wrong.append((probe["id"], expected, ps, probe.get("why", "")))
        if "gap" in probe:
            gaps += 1

    if diverged:
        print("!! %d probe(s) got DIFFERENT verdicts from the two guards" % len(diverged))
        print("   %-34s %-10s %s" % ("probe", "ps1", "py"))
        for pid, ps, py in diverged:
            print("   %-34s %-10s %s" % (pid, ps, py))

    if wrong:
        print("!! %d probe(s) got the WRONG verdict from BOTH guards" % len(wrong))
        print("   Agreement is not correctness. Both copies are wrong in the same direction.")
        print("   %-34s %-6s %s" % ("probe", "want", "got"))
        for pid, exp, got, why in wrong:
            print("   %-34s %-6s %s   %s" % (pid, exp, got, why[:60]))

    if diverged or wrong:
        print("\n!! Parity FAILED. Fix BOTH guards, or a recipient on one platform gets a")
        print("   different security posture from a recipient on the other, with nothing to")
        print("   tell either of them which.")
        return EXIT_DIVERGED

    print("ok  %d probes: both guards agree with each other and with guard-probes.json"
          % len(probes))
    print("ok  %d of those are recorded KNOWN GAPS -- they pass by NOT blocking, on purpose."
          % gaps)
    print("    If one of them starts blocking, this gate goes red and the gap entry (and the")
    print("    README) need updating. That is the intended way to find out.")
    print("\nok  exit 0 -- the two guards are in parity")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
