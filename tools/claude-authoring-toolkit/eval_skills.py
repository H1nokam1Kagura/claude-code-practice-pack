#!/usr/bin/env python3
"""eval_skills.py -- measure whether each skill fires when it should, and only then.

WHAT THIS MEASURES, AND WHY LINTING DOES NOT COVER IT

    A lint proves a description exists and is inside budget. It says nothing about whether the
    description does its job -- and a skill's description has exactly one job: get the skill
    chosen at the right moment, and not chosen at the wrong one. That is a behavioural property
    of a model reading prose, so the only way to know is to ask a model and count.

    The failure this catches is not "the skill never fires". It is the skill firing on its
    NEIGHBOUR's work. Skills that describe adjacent tasks in shared vocabulary collide, one
    quietly claims the other's requests, and nothing in the tree looks wrong. Which is why the
    probe file's non-triggering half is aimed at siblings rather than at unrelated noise.

TWO HALVES, AND THE CHEAP ONE RUNS FIRST

    COVERAGE is a static property of the tree: every skill has probes, and every probe names a
    skill that exists. It needs no key, no network and no spend, so it runs BEFORE the API gate.
    That means a coverage regression fails on a fork or before any secret exists, it is testable
    offline, and you never spend a few hundred model calls to discover something that was
    knowable for free.

    ACCURACY is the model half, and it costs money: roughly (skills x probes) calls per run.

    Coverage is checked in BOTH directions. A probe naming a skill that no longer exists has
    always failed loudly. The reverse -- a SKILL that no probe covers -- did not, so a new skill
    scored nothing while the summary read all-green. That is the same asymmetry as any gate that
    accounts for what it found rather than for what exists.

WRITE-BACK
    --write-back records each measured rate in the skill's own frontmatter (eval_pass_rate,
    eval_last_run). Off by default: no flag, no mutation. Only those two lines are rewritten,
    byte-for-byte elsewhere, so the diff shows the measurement and nothing else.

USAGE
    python eval_skills.py <tree-root> --probes probes.json
    python eval_skills.py <tree-root> --probes probes.json --model <id> --threshold 0.80
    python eval_skills.py <tree-root> --probes probes.json --write-back
    python eval_skills.py <tree-root> --probes probes.json --coverage-only   # the free half
    python eval_skills.py --self-test        # offline controls; no API calls, no key needed

EXIT CONTRACT
    0  every skill was probed and every one met the threshold
    1  a skill scored below threshold, or coverage is incomplete, or the probe file is malformed
    2  the accuracy half could not run (no API key, or the SDK is not installed) -- SKIPPED

    2 is never a pass. A version of this exited 0 with a warning when the key was absent, so a
    repository with no secret reported a green eval forever while measuring nothing.

    --coverage-only runs the free half and stops, narrowing the contract to 0 or 1: it never
    reads the key, never imports the SDK, and never scores a probe. It is NOT a quieter way to
    get a green eval -- its 0 means "every skill is probed", never "the descriptions work", and
    it prints that on every run, red or green. The default is deliberately unchanged: a plain
    run with no key still exits 2.

REQUIRES PyYAML for the accuracy half, which is the only half that reads a description; the
anthropic SDK and an API key for the same half, which is why both imports are deferred rather
than made hard dependencies of a coverage check that needs neither.
"""
from __future__ import annotations

import argparse
import datetime as _dt
import functools
import io
import json
import os
import re
import sys
import tempfile
from pathlib import Path

print = functools.partial(print, flush=True)  # noqa: A001

# Runs on a Linux runner in CI and on a Windows console locally, where the default codepage
# cannot encode the status glyphs -- without this the script dies in the print rather than at
# the check it was reporting on, which is a maddening way to lose an hour.
if hasattr(sys.stdout, "buffer"):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

EXIT_OK, EXIT_FAIL, EXIT_SKIPPED = 0, 1, 2

# A default, not a recommendation. The judge answers a binary question about a short prompt,
# which is the shape a small fast model is for; a bigger one costs more per run without a
# measured accuracy gain here. It is a flag because the choice is the caller's, and because a
# model id pinned in a script is a model id that goes stale silently. Checked 2026-08-16.
DEFAULT_MODEL = "claude-haiku-4-5"
DEFAULT_THRESHOLD = 0.80

# Printed on EVERY --coverage-only run, red or green, and worded so it cannot be read as a
# pass for something that was not measured. The flag exists so the free half can be gated
# against a real tree in CI; the moment it starts reading like a full eval, it has become a way
# to make a red eval look green, which is the one thing this tool must never offer.
COVERAGE_ONLY_BANNER = (
    "[HALF] --coverage-only: the ACCURACY HALF WAS NOT ATTEMPTED. No key was read, no\n"
    "       model was called, no probe was scored. This run can only tell you that the\n"
    "       tree is fully probed -- it says nothing whatever about whether any\n"
    "       description gets its skill chosen. A 0 here is not a green eval."
)

JUDGE_SYSTEM = (
    "You are a precise evaluator of AI assistant skill invocation decisions. "
    "Reply with exactly YES or NO on the first line, then one sentence of rationale."
)

JUDGE_USER = """\
An AI coding assistant has a skill with this description:
---
{description}
---

The user sent this message: "{probe}"

Should the assistant invoke this skill in response to this message?
YES or NO, then one-sentence rationale."""


# ── probe file ────────────────────────────────────────────────────────────────────────────

def load_probes(path: Path) -> "tuple[dict, dict, list[str]]":
    """Return (probes, exempt, errors). Shape is checked here so a typo is a loud failure.

    A malformed probe file that still parses as JSON is the quiet way this gate stops working:
    an entry with an empty non_triggering list measures only half of what it claims to.
    """
    errors: "list[str]" = []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        return {}, {}, ["cannot read probe file %s -- %s" % (path, e)]

    probes = data.get("probes")
    if not isinstance(probes, dict) or not probes:
        return {}, {}, ["%s has no non-empty 'probes' object -- refusing to measure nothing" % path]

    exempt = data.get("exempt") or {}
    if not isinstance(exempt, dict):
        errors.append("'exempt' must be a map of skill name -> reason")
        exempt = {}
    for name, reason in sorted(exempt.items()):
        if not str(reason).strip():
            errors.append("exempt['%s'] has no reason -- an escape hatch without a reason is a "
                          "silencer, not a decision" % name)

    clean: dict = {}
    for name, entry in sorted(probes.items()):
        if not isinstance(entry, dict):
            errors.append("probes['%s'] is not an object" % name)
            continue
        # Keys starting with _ are notes for the reader (which neighbour each probe defends
        # against). They are data about the probes, not probes, and are skipped deliberately.
        kept = {}
        for half in ("triggering", "non_triggering"):
            vals = entry.get(half)
            if not isinstance(vals, list) or not vals:
                errors.append("probes['%s'] has no non-empty '%s' list -- a one-sided probe set "
                              "measures one direction and reports both" % (name, half))
                continue
            bad = [v for v in vals if not isinstance(v, str) or not v.strip()]
            if bad:
                errors.append("probes['%s'].%s contains an empty or non-string probe"
                              % (name, half))
                continue
            kept[half] = vals
        if len(kept) == 2:
            clean[name] = kept
    return clean, exempt, errors


# ── the tree ──────────────────────────────────────────────────────────────────────────────

def skills_on_disk(root: Path) -> "list[str]":
    return sorted(d.name for d in root.iterdir()
                  if d.is_dir() and (d / "SKILL.md").is_file())


def load_description(root: Path, skill: str) -> str:
    import yaml

    raw = (root / skill / "SKILL.md").read_text(encoding="utf-8", errors="replace").lstrip("﻿")
    parts = raw.split("---", 2)
    if len(parts) < 3:
        return ""
    fm = yaml.safe_load(parts[1]) or {}
    if not isinstance(fm, dict):
        return ""
    desc = fm.get("description", "")
    return (desc if isinstance(desc, str) else str(desc)).strip()


def check_coverage(root: Path, probes: dict, exempt: dict) -> "list[str]":
    """Both directions. Returns the failures; empty means full coverage."""
    failures: "list[str]" = []
    on_disk = set(skills_on_disk(root))

    orphaned = sorted(s for s in probes if s not in on_disk)
    if orphaned:
        failures.append(
            "%d probe key(s) name a skill with no directory: %s\n"
            "   Coverage was silently lost. Rename the key to match the skill, or delete the\n"
            "   entry deliberately if the skill is genuinely retired."
            % (len(orphaned), ", ".join(orphaned)))

    unprobed = sorted(s for s in on_disk if s not in probes and s not in exempt)
    if unprobed:
        failures.append(
            "%d skill(s) have no probes, so they were not measured at all:\n     %s\n"
            "   Add triggering and non-triggering probes, or an 'exempt' entry with a reason.\n"
            "   An unmeasured skill must not be counted as a passing one."
            % (len(unprobed), "\n     ".join(unprobed)))

    return failures


# ── the model half ────────────────────────────────────────────────────────────────────────

def judge(client, model: str, description: str, probe: str) -> bool:
    msg = client.messages.create(
        model=model,
        max_tokens=256,
        system=JUDGE_SYSTEM,
        messages=[{"role": "user",
                   "content": JUDGE_USER.format(description=description, probe=probe)}],
    )
    for block in msg.content:
        if getattr(block, "type", None) == "text":
            return block.text.strip().upper().startswith("YES")
    return False


# ── write-back ────────────────────────────────────────────────────────────────────────────

_EVAL_LINE = re.compile(r"^(\s*)(eval_pass_rate|eval_last_run):[ \t]*(.*?)([ \t]*\r?\n?)$")


def write_back(root: Path, skill: str, rate: str, when: str) -> bool:
    """Record the measurement in the skill's own frontmatter. True if the file changed.

    Rewrites ONLY the two eval_* lines and leaves every other byte alone. A YAML round-trip
    would reformat the whole block -- re-quoting, reordering, changing indentation -- and bury
    the one line that actually changed in a diff nobody can review. Written atomically, so an
    interrupted run cannot leave a half-written SKILL.md.
    """
    path = root / skill / "SKILL.md"
    with open(path, encoding="utf-8", newline="") as f:
        lines = f.readlines()

    # Bound the edit to the frontmatter, or a stray "eval_pass_rate:" in the body gets hit.
    fences = [i for i, ln in enumerate(lines) if ln.strip() == "---"]
    if len(fences) < 2:
        print("   !! %s: no frontmatter fence found -- not written back" % skill)
        return False
    lo, hi = fences[0] + 1, fences[1]

    values = {"eval_pass_rate": rate, "eval_last_run": when}
    changed = False
    for i in range(lo, hi):
        m = _EVAL_LINE.match(lines[i])
        if not m:
            continue
        indent, key, old, eol = m.groups()
        new = '"%s"' % values[key]
        if old.strip() == new:
            continue
        lines[i] = "%s%s: %s%s" % (indent, key, new, eol or os.linesep)
        changed = True

    if not changed:
        return False

    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".skillmd-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
            f.writelines(lines)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise
    return True


# ── run ───────────────────────────────────────────────────────────────────────────────────

def run(root: Path, probe_path: Path, model: str, threshold: float, do_write_back: bool,
        coverage_only: bool = False) -> int:
    # Only the accuracy half reads a description, so only the accuracy half needs a YAML parser.
    # Gating --coverage-only on PyYAML would give it a third exit for a dependency it does not
    # use, and the whole claim of the free half is that it runs anywhere, on anything.
    if not coverage_only:
        try:
            import yaml  # noqa: F401
        except ImportError:
            print("!! PyYAML is not installed, so no description could be read. "
                  "exit 2, not a pass.")
            return EXIT_SKIPPED

    if not root.is_dir():
        print("!! %s is not a directory. A check that cannot locate its subject must not pass."
              % root)
        return EXIT_FAIL

    probes, exempt, shape_errors = load_probes(probe_path)
    if shape_errors:
        for e in shape_errors:
            print("[FAIL] %s" % e)
        print("\n[FAIL] The probe file is malformed. Fix it before any score means anything.")
        return EXIT_FAIL

    print("")
    print("TRIGGERING EVAL -- %s%s" % (root, "  (COVERAGE ONLY)" if coverage_only else ""))
    if coverage_only:
        print("   probes: %s   accuracy half: NOT ATTEMPTED" % probe_path.name)
    else:
        print("   probes: %s   threshold: %.2f   judge: %s"
              % (probe_path.name, threshold, model))
    print("=" * 78)

    coverage_failures = check_coverage(root, probes, exempt)
    for f in coverage_failures:
        print("[FAIL] %s" % f)
    if exempt:
        print("[note] %d skill(s) deliberately exempt from probing:" % len(exempt))
        for s, why in sorted(exempt.items()):
            print("       %s: %s" % (s, why))
    if not coverage_failures:
        print("[ ok ] coverage: every skill has probes, and every probe names a skill")

    # Deliberately before the key gate: a coverage failure is a real failure, knowable for free,
    # and must not be masked by the SKIPPED below.
    if coverage_failures:
        print("\n[FAIL] Coverage is incomplete -- fix that before the scores mean anything.")
        if coverage_only:
            print(COVERAGE_ONLY_BANNER)
        return EXIT_FAIL

    # --coverage-only stops HERE: after the same coverage check every run makes, and before the
    # key is so much as read. One implementation of the check, two stopping points -- forking it
    # into a second "offline" routine is how the two would drift into disagreeing about what
    # coverage means.
    if coverage_only:
        print("")
        print(COVERAGE_ONLY_BANNER)
        print("=" * 78)
        print("  exit 0 -- coverage only: every skill has probes, and every probe names a skill")
        return EXIT_OK

    api_key = os.environ.get("ANTHROPIC_API_KEY", "").strip()
    if not api_key:
        print("\n[SKIP] ANTHROPIC_API_KEY is not set -- the accuracy half DID NOT RUN.")
        print("       Reported as SKIPPED, not as a pass: nothing was measured, so nothing")
        print("       is known. Coverage above did run, and passed.")
        return EXIT_SKIPPED
    try:
        import anthropic
    except ImportError:
        print("\n[SKIP] the anthropic SDK is not installed -- the accuracy half DID NOT RUN.")
        print("       `pip install anthropic`. SKIPPED, never a pass.")
        return EXIT_SKIPPED

    client = anthropic.Anthropic(api_key=api_key)
    summary: "dict[str, str]" = {}
    all_passed = True

    for skill, entry in probes.items():
        description = load_description(root, skill)
        if not description:
            print("[FAIL] %s: no description in its frontmatter, so there is nothing to judge "
                  "against" % skill)
            all_passed = False
            continue

        correct = total = 0
        misses: "list[str]" = []
        for probe in entry["triggering"]:
            total += 1
            if judge(client, model, description, probe):
                correct += 1
            else:
                misses.append('  MISS (should fire):   "%s"' % probe)
        for probe in entry["non_triggering"]:
            total += 1
            if not judge(client, model, description, probe):
                correct += 1
            else:
                misses.append('  FALSE POSITIVE:       "%s"' % probe)

        accuracy = correct / total
        passed = accuracy >= threshold
        print("[%s] %s: %d/%d (%.2f)" % (" ok " if passed else "FAIL", skill, correct, total,
                                         accuracy))
        for line in misses:
            print(line)
        summary[skill] = "%d/%d (%.2f)" % (correct, total, accuracy)
        if not passed:
            all_passed = False

    print("\nSummary: %s" % json.dumps(summary, indent=2))

    if do_write_back and summary:
        when = _dt.date.today().isoformat()
        written = [s for s in sorted(summary) if write_back(root, s, summary[s], when)]
        print("\nwrite-back: %d SKILL.md file(s) updated%s"
              % (len(written), (" -- " + ", ".join(written)) if written else " (all current)"))

    print("=" * 78)
    if not all_passed:
        print("  exit 1 -- at least one skill is below the %.2f threshold" % threshold)
        return EXIT_FAIL
    print("  exit 0 -- every skill is at or above the %.2f threshold" % threshold)
    print("            (this measures TRIGGERING only -- it says nothing about whether the")
    print("             skill does good work once it has fired)")
    return EXIT_OK


# ── self-test ─────────────────────────────────────────────────────────────────────────────
# Offline by construction: it exercises the half that needs no key, which is the half that
# fails silently. Nothing here makes an API call, so it is safe to run in CI on every push and
# on a fork with no secret.

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

    here = Path(__file__).parent
    example_tree = here / "examples" / "skills"
    example_probes = here / "probes.example.json"

    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        pf = tmp / "probes.json"

        def probe_file(obj) -> Path:
            pf.write_text(json.dumps(obj), encoding="utf-8")
            return pf

        def tree(names) -> Path:
            d = tmp / ("tree-%d" % len(list(tmp.glob("tree-*"))))
            for n in names:
                (d / n).mkdir(parents=True)
                (d / n / "SKILL.md").write_text(
                    "---\nname: %s\ndescription: Does the %s thing.\n---\n\nBody.\n" % (n, n),
                    encoding="utf-8")
            return d

        good = {"exempt": {}, "probes": {
            "alpha": {"triggering": ["do alpha"], "non_triggering": ["do beta"]}}}

        # No key is set in the controls, so a fully-covered tree stops at the API gate. 2 is the
        # correct answer there and proves coverage ran and passed without spending anything.
        os.environ.pop("ANTHROPIC_API_KEY", None)
        control("full coverage with no key is 2 (SKIPPED), never 0", EXIT_SKIPPED,
                run(tree(["alpha"]), probe_file(good), DEFAULT_MODEL, DEFAULT_THRESHOLD, False))

        control("a skill with NO probes fails coverage", EXIT_FAIL,
                run(tree(["alpha", "orphan"]), probe_file(good), DEFAULT_MODEL,
                    DEFAULT_THRESHOLD, False))

        control("a probe naming a skill that does not exist fails coverage", EXIT_FAIL,
                run(tree([]), probe_file(good), DEFAULT_MODEL, DEFAULT_THRESHOLD, False))

        exempted = {"exempt": {"orphan": "generated wrapper, has no description of its own"},
                    "probes": good["probes"]}
        control("...and an exempt entry WITH a reason passes", EXIT_SKIPPED,
                run(tree(["alpha", "orphan"]), probe_file(exempted), DEFAULT_MODEL,
                    DEFAULT_THRESHOLD, False))

        no_reason = {"exempt": {"orphan": ""}, "probes": good["probes"]}
        control("an exempt entry with NO reason is rejected", EXIT_FAIL,
                run(tree(["alpha", "orphan"]), probe_file(no_reason), DEFAULT_MODEL,
                    DEFAULT_THRESHOLD, False))

        one_sided = {"exempt": {}, "probes": {
            "alpha": {"triggering": ["do alpha"], "non_triggering": []}}}
        control("a probe set with an empty half is rejected", EXIT_FAIL,
                run(tree(["alpha"]), probe_file(one_sided), DEFAULT_MODEL,
                    DEFAULT_THRESHOLD, False))

        empty = {"exempt": {}, "probes": {}}
        control("an empty probe file is 1, never a pass", EXIT_FAIL,
                run(tree(["alpha"]), probe_file(empty), DEFAULT_MODEL, DEFAULT_THRESHOLD, False))

        (tmp / "broken.json").write_text("{not json", encoding="utf-8")
        control("an unparseable probe file is 1, never a pass", EXIT_FAIL,
                run(tree(["alpha"]), tmp / "broken.json", DEFAULT_MODEL,
                    DEFAULT_THRESHOLD, False))

        control("a missing tree is 1, never a pass", EXIT_FAIL,
                run(tmp / "nope", probe_file(good), DEFAULT_MODEL, DEFAULT_THRESHOLD, False))

        # --coverage-only is the one flag here that can turn a 2 into a 0, so it is controlled in
        # both directions. The first control is the feature; the two below it are the reason the
        # feature is allowed to exist -- it stops the accuracy half, it does not soften the half
        # it does run. A --coverage-only that passed an unprobed tree would be a switch for
        # making a red eval look green, which is the failure this whole exit contract is about.
        # The key is still unset here, and stays unset: the flag must never consult it.
        control("--coverage-only on a fully covered tree is 0, without a key", EXIT_OK,
                run(tree(["alpha"]), probe_file(good), DEFAULT_MODEL, DEFAULT_THRESHOLD, False,
                    coverage_only=True))

        control("--coverage-only still fails a skill with NO probes", EXIT_FAIL,
                run(tree(["alpha", "orphan"]), probe_file(good), DEFAULT_MODEL,
                    DEFAULT_THRESHOLD, False, coverage_only=True))

        control("--coverage-only still fails an unparseable probe file", EXIT_FAIL,
                run(tree(["alpha"]), tmp / "broken.json", DEFAULT_MODEL, DEFAULT_THRESHOLD,
                    False, coverage_only=True))

        # The default must not move. Same tree and same probe file as the coverage-only 0 above,
        # one flag apart: this is what stops --coverage-only becoming the way the tool is run.
        control("...and the DEFAULT on that same tree is still 2, not 0", EXIT_SKIPPED,
                run(tree(["alpha"]), probe_file(good), DEFAULT_MODEL, DEFAULT_THRESHOLD, False))

        # Write-back rewrites two lines and nothing else. Asserted byte-for-byte, because the
        # failure mode is a reformat that buries the measurement in an unreviewable diff.
        wb = tree(["alpha"])
        original = ("---\nname: alpha\ndescription: Does the alpha thing.\nmetadata:\n"
                    "  owner: someone@example.invalid\n  eval_pass_rate: TBD\n"
                    "  eval_last_run: TBD\n---\n\nBody with eval_pass_rate: not-a-field.\n")
        (wb / "alpha" / "SKILL.md").write_text(original, encoding="utf-8")
        write_back(wb, "alpha", "8/8 (1.00)", "2026-08-16")
        after = (wb / "alpha" / "SKILL.md").read_text(encoding="utf-8")
        control("write-back changes exactly the two eval_ lines", 2,
                sum(1 for a, b in zip(original.splitlines(), after.splitlines()) if a != b))
        control("write-back does not touch a lookalike line in the body", True,
                "Body with eval_pass_rate: not-a-field." in after)
        control("write-back is idempotent", False, write_back(wb, "alpha", "8/8 (1.00)",
                                                              "2026-08-16"))

    # Against the SHIPPED example tree and probe file, not a fixture. A self-test that never
    # touches the real data goes green while the two drift apart -- the example probes name
    # example skills, and a rename in one is exactly what this catches.
    if example_tree.is_dir() and example_probes.is_file():
        control("the SHIPPED example probes fully cover the SHIPPED example skills",
                EXIT_SKIPPED,
                run(example_tree, example_probes, DEFAULT_MODEL, DEFAULT_THRESHOLD, False))
        # The exact invocation CI makes against the shipped tree. Controlled here so the CI step
        # cannot be the first place anyone discovers it does not exit 0.
        control("...and --coverage-only over that same shipped tree is 0", EXIT_OK,
                run(example_tree, example_probes, DEFAULT_MODEL, DEFAULT_THRESHOLD, False,
                    coverage_only=True))
    else:
        print("  [note] example tree or probe file absent -- shipped-data control skipped")

    print("")
    if failed:
        print("SELF-TEST FAILED -- %d control(s) misbehaved: %s" % (len(failed), ", ".join(failed)))
        return EXIT_FAIL
    print("SELF-TEST PASSED -- every control behaved as specified (%d)" % passed)
    return EXIT_OK


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("root", nargs="?", help="directory holding the skill tree")
    ap.add_argument("--probes", help="probe file (see probes.example.json)")
    ap.add_argument("--model", default=DEFAULT_MODEL, help="judge model id")
    ap.add_argument("--threshold", type=float, default=DEFAULT_THRESHOLD,
                    help="minimum accuracy per skill")
    ap.add_argument("--write-back", action="store_true",
                    help="record the measured rate in each SKILL.md frontmatter")
    ap.add_argument("--coverage-only", action="store_true",
                    help="run only the free coverage half against the tree and stop: no key is "
                         "read, no model is called, exit 0 (fully probed) or 1 (incomplete or "
                         "malformed probe file). NOT a substitute for a run -- it measures no "
                         "accuracy at all and says so")
    ap.add_argument("--self-test", action="store_true",
                    help="run the offline controls and exit; makes no API calls")
    args = ap.parse_args(argv)

    if args.self_test:
        try:
            import yaml  # noqa: F401
        except ImportError:
            print("!! PyYAML is not installed, so the controls could not run. exit 2, not a pass.")
            return EXIT_SKIPPED
        return self_test()
    if not args.root or not args.probes:
        ap.error("a tree root and --probes are required (or use --self-test)")
    if args.coverage_only and args.write_back:
        ap.error("--coverage-only measures no accuracy, so there is no rate to write back")
    return run(Path(args.root), Path(args.probes), args.model, args.threshold, args.write_back,
               args.coverage_only)


if __name__ == "__main__":
    sys.exit(main())
