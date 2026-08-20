#!/usr/bin/env python3
"""Measure a wording change against a no-guidance control before shipping it.

WHY IT EXISTS AT ALL
    Instructions in this repository are written, reviewed and shipped on intuition. Nothing here
    measures whether a sentence added to a skill, a CLAUDE.md or a command file actually moves the
    behaviour it was written for -- so a rule that does nothing and a rule that makes things worse
    are indistinguishable from a rule that works, and all three survive review.

    Measured 2026-08-17 with this tool, on the example experiment beside it: the PROHIBITION arm
    ("do not mention any tool, script or file name") did not separate from the no-guidance control,
    while the RECIPE arm ("refer to each step by what it achieved") did. Numbers, model and spread
    are in WORDING-TESTS.md, which is where the result is interpreted.

WHAT IT ASSERTS -- both halves matter
    1. the control arm EXHIBITS the failure. If it does not, there is nothing to fix and the run
       stops there, reporting that: a wording change measured against a control that never had the
       problem will always look like an improvement.
    2. the arms are separated by more than their own spread. A single rep is one draw from a
       distribution; two means compared across overlapping ranges is a coin toss with a decimal
       point on it.

WHAT IT DELIBERATELY DOES NOT DO
    It does not judge quality. The metric is a count of banned strings, chosen because it is
    deterministic and reproducible by anyone -- an LLM judge would put the thing being measured and
    the thing doing the measuring in the same family. It measures ONE property of the output, and
    says so.

    It does not pick a winner when the arms overlap. Overlapping distributions mean the experiment
    did not resolve, which is a result, not a tie to be broken.

EXIT CONTRACT
    0  the experiment ran and every arm was measured
    1  the control did not exhibit the failure (nothing to fix -- stop), an arm produced no
       usable rep, or the experiment file is malformed. All of these are "ran and measured
       nothing", which is a failure and not a skip.
    2  the runner is not available on this machine -- no `claude` executable on PATH. A scope
       fact, not a defect: this tool needs an interactive-auth CLI that a recipient may not have.

    The 1-versus-2 split is the one the practice documents insist on: "I could not run this here"
    and "it ran and measured nothing" must not share an exit code.

    STDLIB ONLY. Python 3.8+.
"""
from __future__ import annotations

import argparse
import functools
import json
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
from pathlib import Path

print = functools.partial(print, flush=True)  # noqa: A001

EXIT_OK, EXIT_INCONCLUSIVE, EXIT_SKIPPED = 0, 1, 2

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent


# ── scoring ─────────────────────────────────────────────────────────────────────────────────────

def score(text: str, banned: list) -> int:
    """Occurrences of the banned strings in one response, counted WITHOUT double-counting.

    Case-insensitive substring counting, not word-boundary matching: the tokens are file names and
    flags full of dots, hyphens and slashes, and \\b around a dot matches in places no reader would
    call a word.

    LONGEST TOKEN FIRST, AND MATCHES ARE CONSUMED. The naive version of this summed each token's
    count independently, and the token list it was first pointed at contained `.ps1` and
    `Test-ScriptQuality.ps1`, and `verify.yml` and `build-and-verify.yml`. One mention of the long
    name scored two. Found 2026-08-17 by reading the responses rather than the totals -- the
    separation held either way, which is exactly why nobody would have looked.
    """
    low = text.lower()
    total = 0
    for b in sorted(banned, key=len, reverse=True):
        b = b.lower()
        if not b:
            continue
        total += low.count(b)
        low = low.replace(b, "\x00" * len(b))  # consume, so a shorter token cannot re-count it
    return total


def separated(a: list, b: list) -> bool:
    """True when the two sets of per-rep counts do not overlap at all.

    The strict form on purpose. A difference in means with overlapping ranges is the shape that
    reads as a finding and reproduces as noise, and this whole tool exists because that shape has
    been shipped as a rule before.
    """
    return max(a) < min(b) or max(b) < min(a)


# ── the runner ──────────────────────────────────────────────────────────────────────────────────

def run_once(prompt: str, model: str, timeout: int) -> str:
    proc = subprocess.run(
        ["claude", "-p", prompt, "--max-turns", "1", "--model", model],
        capture_output=True, text=True, timeout=timeout,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"claude exited {proc.returncode}: {proc.stderr.strip()[:300]}")
    return proc.stdout.strip()


def build_prompt(exp: dict, guidance: str) -> str:
    return exp["template"].format(fixture=exp["fixture"], guidance=guidance).strip()


def experiment(exp: dict, reps: int, model: str, timeout: int, runner=None, verbose=False) -> dict:
    """Run every arm `reps` times and return {arm: [count, ...]}."""
    runner = runner or (lambda p: run_once(p, model, timeout))
    results = {}
    for arm in exp["arms"]:
        counts, samples = [], []
        for i in range(reps):
            out = runner(build_prompt(exp, arm["guidance"]))
            n = score(out, exp["banned"])
            counts.append(n)
            samples.append(out)
            if verbose:
                print(f"  {arm['name']:<12} rep {i + 1}: {n}")
        results[arm["name"]] = {"counts": counts, "samples": samples}
    return results


# ── report ──────────────────────────────────────────────────────────────────────────────────────

def report(exp: dict, results: dict, control_name: str) -> int:
    print("=" * 78)
    print(f"{'arm':<14} {'n':>3}  {'median':>6}  {'range':>9}   counts")
    for name, r in results.items():
        c = r["counts"]
        if not c:
            print(f"{name:<14} -- no usable rep")
            print("=" * 78)
            print("WORDING TEST: INCONCLUSIVE -- an arm produced no usable rep, so nothing was compared.")
            return EXIT_INCONCLUSIVE
        print(f"{name:<14} {len(c):>3}  {statistics.median(c):>6}  "
              f"{min(c):>4}-{max(c):<4}  {c}")

    control = results[control_name]["counts"]
    print("=" * 78)

    # STEP ONE OF THE METHOD, enforced rather than advised. A control that never exhibits the
    # failure makes every arm look like an improvement, and the improvement is the control's
    # silence rather than the wording's effect.
    if max(control) == 0:
        print(f"WORDING TEST: INCONCLUSIVE -- the control arm '{control_name}' never exhibited the "
              f"failure (every rep scored 0). There is nothing to fix here; a change measured "
              f"against this control would be measuring nothing. Pick a task where the failure is "
              f"real, or stop.")
        return EXIT_INCONCLUSIVE

    treatments = [n for n in results if n != control_name]
    for name in treatments:
        c = results[name]["counts"]
        verdict = "SEPARATED from control" if separated(control, c) else "overlaps the control -- did not resolve"
        direction = ""
        if separated(control, c):
            direction = " (better)" if max(c) < min(control) else " (WORSE than no guidance at all)"
        print(f"  {name:<14} {verdict}{direction}")

    # THE QUESTION vs-control CANNOT ANSWER. "Does guidance help?" and "which FORM of guidance is
    # better?" are different questions, and an arm can beat the control decisively while telling
    # you nothing about the second. Added 2026-08-17 after the first live run of the example
    # experiment: both treatments separated from the control and neither separated from the other,
    # and the report said only that both had won. Two arms at the floor is a floor effect, not a
    # tie -- the failure was too easy, so the task cannot discriminate between forms.
    if len(treatments) > 1:
        print("  ---")
        for i, a in enumerate(treatments):
            for b in treatments[i + 1:]:
                ca, cb = results[a]["counts"], results[b]["counts"]
                if separated(ca, cb):
                    win = a if max(ca) < min(cb) else b
                    print(f"  {a} vs {b}: SEPARATED -- {win} is better")
                else:
                    floor = " Both sit at the floor, so this task cannot tell the forms apart." \
                        if max(ca) <= 2 and max(cb) <= 2 else ""
                    print(f"  {a} vs {b}: overlap ({min(ca)}-{max(ca)} against {min(cb)}-{max(cb)}) "
                          f"-- the FORM question did not resolve.{floor}")

    print("=" * 78)
    print(f"WORDING TEST: MEASURED ({len(results)} arms x {len(control)} reps)")
    return EXIT_OK


# ── negative controls ───────────────────────────────────────────────────────────────────────────

def _exp(banned=None):
    return {
        "template": "{fixture}\n{guidance}",
        "fixture": "FIX",
        "banned": banned if banned is not None else ["widget"],
        "arms": [{"name": "control", "guidance": ""}, {"name": "recipe", "guidance": "do it well"}],
    }


def self_test() -> int:
    controls, failed = [], []

    def control(label, expect, got):
        ok = expect == got
        controls.append((label, ok, expect, got))
        if not ok:
            failed.append((label, expect, got))

    # scoring
    control("counts every occurrence, not just the first", 3,
            score("widget widget WIDGET", ["widget"]))
    control("case-insensitive", 2, score("Widget wIdGeT", ["widget"]))
    control("a clean response scores zero", 0, score("nothing here", ["widget"]))
    control("counts a dotted file name as one token", 2,
            score("ran Foo.ps1 then foo.ps1 again", ["Foo.ps1"]))
    # the defect this metric shipped with for one run
    control("a token inside a longer token is not counted twice", 1,
            score("ran Foo.ps1", ["Foo.ps1", ".ps1"]))
    control("...and the shorter token still counts on its own", 2,
            score("ran Foo.ps1 and Bar.ps1", ["Foo.ps1", ".ps1"]))
    control("three-deep nesting still counts once", 1,
            score("build-and-verify.yml", ["build-and-verify.yml", "verify.yml", ".yml"]))

    # separation
    control("disjoint ranges are separated", True, separated([3, 4, 5], [0, 1]))
    control("touching ranges are NOT separated", False, separated([3, 4, 5], [5, 6]))
    control("overlapping ranges are NOT separated", False, separated([1, 5], [2, 3]))
    control("identical ranges are NOT separated", False, separated([2, 2], [2, 2]))

    # the method's first step, which is the whole point
    import io, contextlib

    def run_report(exp, results, control_name="control"):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            code = report(exp, results, control_name)
        return code, buf.getvalue()

    code, out = run_report(_exp(), {"control": {"counts": [0, 0, 0], "samples": []},
                                    "recipe": {"counts": [0, 0, 0], "samples": []}})
    control("a control that never fails is INCONCLUSIVE, not a pass", EXIT_INCONCLUSIVE, code)
    control("...and says there is nothing to fix", True, "nothing to fix" in out)

    code, out = run_report(_exp(), {"control": {"counts": [3, 4, 5], "samples": []},
                                    "recipe": {"counts": [0, 1, 1], "samples": []}})
    control("a real control with a separated arm is MEASURED", EXIT_OK, code)
    control("...and names the arm as separated", True, "SEPARATED from control" in out)

    # The direction matters as much as the separation. An arm can be separated and WORSE, which is
    # the result that makes this tool worth running -- a rule that reliably makes things worse
    # reads, in review, exactly like a rule that works.
    code, out = run_report(_exp(), {"control": {"counts": [3, 4, 5], "samples": []},
                                    "prohibition": {"counts": [6, 7, 9], "samples": []}})
    control("an arm that is separated and WORSE is named as worse", True,
            "WORSE than no guidance" in out)
    # ...and an arm that is worse but OVERLAPPING is not named at all. Written after the first
    # version of this control asserted [4,5,9] against [3,4,5] and expected "worse": those ranges
    # overlap, so "did not resolve" was the right answer and the control was wrong, not the code.
    code, out = run_report(_exp(), {"control": {"counts": [3, 4, 5], "samples": []},
                                    "prohibition": {"counts": [4, 5, 9], "samples": []}})
    control("a worse-looking arm that overlaps is not called worse", False,
            "WORSE than no guidance" in out)

    code, out = run_report(_exp(), {"control": {"counts": [3, 4, 5], "samples": []},
                                    "recipe": {"counts": [2, 4, 6], "samples": []}})
    control("an overlapping arm did not resolve, and is not a win", True,
            "did not resolve" in out)

    code, out = run_report(_exp(), {"control": {"counts": [], "samples": []}})
    control("an arm with no usable rep is INCONCLUSIVE", EXIT_INCONCLUSIVE, code)

    # two treatments that both beat the control but not each other
    both = {"control": {"counts": [16, 17, 17], "samples": []},
            "prohibition": {"counts": [0, 1, 0], "samples": []},
            "recipe": {"counts": [2, 0, 0], "samples": []}}
    code, out = run_report(_exp(), both)
    control("both arms beating the control is still MEASURED", EXIT_OK, code)
    control("...but the FORM question is reported as unresolved", True,
            "the FORM question did not resolve" in out)
    control("...and two arms at the floor are named as a floor effect", True,
            "cannot tell the forms apart" in out)

    apart = {"control": {"counts": [16, 17, 17], "samples": []},
             "prohibition": {"counts": [8, 9, 9], "samples": []},
             "recipe": {"counts": [0, 1, 0], "samples": []}}
    code, out = run_report(_exp(), apart)
    control("treatments that DO separate name the winner", True,
            "SEPARATED -- recipe is better" in out)

    # the runner is injectable, so the whole loop is exercised with no CLI and no network
    exp = _exp()
    res = experiment(exp, reps=2, model="stub", timeout=1,
                     runner=lambda p: "widget widget" if "do it well" not in p else "clean")
    control("the arm loop runs both arms at the requested reps", [2, 2], res["control"]["counts"])
    control("...and the guidance actually reaches the prompt", [0, 0], res["recipe"]["counts"])

    # a malformed experiment must refuse rather than measure a subset
    ok = False
    try:
        build_prompt({"template": "{fixture} {nope}", "fixture": "x"}, "")
    except KeyError:
        ok = True
    control("a template naming an unknown field raises, never renders blank", True, ok)

    width = max(len(c[0]) for c in controls)
    for label, ok, expect, got in controls:
        print(f"  {'ok  ' if ok else 'FAIL'}  {label:<{width}}  expected {expect}, got {got}")
    print("=" * 78)
    if failed:
        print(f"SELF-TEST: FAIL ({len(failed)} of {len(controls)} controls)")
        for label, expect, got in failed:
            print(f"  - {label}: expected {expect}, got {got}")
        return EXIT_INCONCLUSIVE
    print(f"SELF-TEST: PASS ({len(controls)} controls)")
    return EXIT_OK


# ── entry ───────────────────────────────────────────────────────────────────────────────────────

def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--experiment", type=Path, default=HERE / "wording-test-example.json")
    ap.add_argument("--reps", type=int, default=7)
    ap.add_argument("--model", default="claude-sonnet-5")
    ap.add_argument("--timeout", type=int, default=180)
    ap.add_argument("--control-arm", default="control")
    ap.add_argument("--out", type=Path, default=None, help="write raw counts and samples here")
    ap.add_argument("--only-control", action="store_true",
                    help="run ONLY the control arm -- step one of the method")
    ap.add_argument("--replay", type=Path, default=None,
                    help="re-report a saved --out file instead of running anything. A measurement "
                         "nobody else can re-read is a number, not a result.")
    ap.add_argument("--rescore", action="store_true",
                    help="with --replay, recount the stored responses under the CURRENT banned "
                         "list instead of trusting the recorded totals")
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--verbose", "-v", action="store_true")
    args = ap.parse_args(argv)

    if args.self_test:
        return self_test()

    if args.replay:
        saved = json.loads(args.replay.read_text(encoding="utf-8"))
        exp = json.loads(args.experiment.read_text(encoding="utf-8"))
        mode = "rescore" if args.rescore else "replay"
        print(f"WORDING TEST -- {mode} of {args.replay.name}")
        print(f"  model: {saved.get('model', 'unrecorded')}   reps: {saved.get('reps', '?')}")
        if args.rescore:
            # Recount the STORED responses under the current banned list. This is why the samples
            # are kept: a metric can be wrong, and a run that can only be replayed at its recorded
            # totals cannot be corrected without paying for it again -- so it would not be.
            if not any(saved.get("samples", {}).values()):
                print("=" * 78)
                print("WORDING TEST: INCONCLUSIVE -- this file holds no responses to rescore.")
                return EXIT_INCONCLUSIVE
            results = {k: {"counts": [score(s, exp["banned"]) for s in v], "samples": v}
                       for k, v in saved["samples"].items()}
        else:
            results = {k: {"counts": v, "samples": []} for k, v in saved["counts"].items()}
        return report(exp, results, args.control_arm)

    if not shutil.which("claude"):
        print("SKIPPED: no `claude` executable on PATH, so no arm can be run. This tool needs an "
              "interactive-auth CLI that a recipient may not have -- a scope fact, not a defect.")
        return EXIT_SKIPPED

    exp = json.loads(args.experiment.read_text(encoding="utf-8"))
    if args.only_control:
        exp = dict(exp, arms=[a for a in exp["arms"] if a["name"] == args.control_arm])

    print(f"WORDING TEST -- {args.experiment.name}")
    print(f"  model: {args.model}   reps: {args.reps}   banned tokens: {len(exp['banned'])}")
    results = experiment(exp, args.reps, args.model, args.timeout, verbose=args.verbose)

    if args.out:
        args.out.write_text(json.dumps(
            {"model": args.model, "reps": args.reps,
             "counts": {k: v["counts"] for k, v in results.items()},
             "samples": {k: v["samples"] for k, v in results.items()}},
            indent=2), encoding="utf-8")

    if args.only_control:
        c = results[args.control_arm]["counts"]
        print("=" * 78)
        if max(c) == 0:
            print(f"CONTROL ONLY: the failure did not appear in {args.reps} reps {c}. "
                  f"Nothing to fix -- stop here.")
            return EXIT_INCONCLUSIVE
        print(f"CONTROL ONLY: the failure is real -- {c}, median "
              f"{statistics.median(c)}. Proceed to the other arms.")
        return EXIT_OK

    return report(exp, results, args.control_arm)


if __name__ == "__main__":
    sys.exit(main())
