#!/usr/bin/env python3
"""Gate the hosted workflow against the portable one, step for step.

The CI job list exists twice, and only one of the two can be run on a laptop:

    .github/workflows/build-and-verify.yml   the hosted gate. Three jobs, a Windows runner we
                                             own, and everything that needs the full repository
                                             or a pinned binary somebody had to install.
    tools/ci/verify.yml                      the portable copy. Shipped, and PARSED by
                                             tools/ci/Invoke-LocalCI.ps1, which is the only
                                             thing anyone can run before pushing.

Neither may be deleted: the hosted one is what actually blocks a merge, and the portable one is
what a recipient gets and what a local run mirrors. So keep the copies, gate the copies -- the
same pattern and the same reason as check_lint_parity.py, check_guard_parity.py,
check_command_parity.py and check_eval_parity.py. TESTING-DISCIPLINE.md section 6.

WHY IT EXISTS AT ALL
    HANDOFF.md's fourth next action, written before this file: "Still no local command runs what
    CI runs. Invoke-LocalCI.ps1 drives verify.yml. build-and-verify.yml has more that nothing
    drives locally, and the gate list lives only in a handoff, which no check reads."

    Measured 2026-08-17, before this gate: build-and-verify.yml declared 42 `run:` steps and
    verify.yml declared 22, of which 17 commands were common to both. So 20 hosted steps had no
    portable counterpart, nothing anywhere recorded which of them were deliberate, and nothing
    detected the number growing. It grew that same morning, by one, when the pinned analyzer
    install was added -- a change nobody had to justify to anything, because the only record of
    the divergence was a sentence in a handoff document. This gate turns that sentence into a
    registry with reasons.

    Note what the fix is NOT. It is not "make the two files identical" -- most of the difference
    is real and should stay (a hosted runner can install a pinned scanner; a recipient's laptop
    cannot be asked to). It is "make every difference a decision somebody wrote down".

WHAT IT ASSERTS -- both halves matter
    1. every `run:` step in EITHER workflow is MIRRORED by an identical normalised command in the
       other, or registered in workflow-parity-exceptions.json with a reason;
    2. every registered entry still describes a difference that is REALLY THERE -- its recorded
       command still appears in the workflow it names, and that command is still NOT mirrored.
    The second half is not decoration. An entry whose command has since been mirrored is an
    exemption nobody granted, and it will silently absorb the next unmirrored step that happens
    to match it. A `variant` entry records BOTH sides, and both are compared against live text,
    so a flag added on either side fails rather than hiding under the entry written for the
    older difference.

    Plus one shape assertion that belongs nowhere else: every `run:` step in verify.yml declares
    `shell: pwsh`. That is what makes the file drivable -- Invoke-LocalCI.ps1 routes by the shell
    the workflow DECLARES rather than by sniffing the command text -- and until now nothing
    checked it. (verify.yml's other shape rule, "no `run: |` block scalars", is already covered
    by a control in Invoke-LocalCI.SelfTest.ps1, so it is deliberately not duplicated here.)

WHAT IT DELIBERATELY DOES NOT DO
    It does not key on the step NAME. The two files name the same command differently in three
    places -- "Nothing in the pack may leave the organisation" against "...may leave its
    organisation", "The shipped PowerShell is analysed, not merely conventional" against "...
    parses, is guarded, and is fully in scope" -- and a name-keyed gate would report drift on
    pairs that are byte-identical in the only field that executes.

    It does not require the hosted workflow to be a superset. Two of the four registered variants
    carry the EXTRA flag on the PORTABLE side (both parity checks there name their second half
    explicitly, because a distribution lays it out differently), so a gate written as "CI has
    more" would have been wrong on half its own data.

    It does not judge whether a difference is a good idea. It requires that somebody wrote down
    why. Which side is right is a scheduling and cost judgement about runners, and a tool that
    "fixed" parity by copying steps across would have moved a gitleaks download into a file a
    recipient runs offline.

    It does not read job structure, `if:`, `working-directory` or `uses:` steps. Only `run:`.
    A step that runs no command is not a gate, and an action pinned by SHA is a different
    contract with a different check.

NORMALISATION
    Compared after: backslashes to forward slashes, all whitespace collapsed to single spaces,
    and a leading `./` stripped. The first two are transport -- a `run: |` block scalar arrives
    with newlines that a single-line twin cannot have -- and the third is because the two files
    genuinely disagree on it in places. Nothing else is normalised: flags, paths and arguments
    are compared literally, because those are the content.

    A RECORDED command in the registry may additionally use `*`, which matches any run of
    characters. Two uses, both stated in the registry and neither casual: a multi-line install
    body, where transcribing the whole shell script would duplicate it rather than pin it (the
    VERSION, which is the part that matters, stays literal); and one leading path segment, where
    the live text names a repository directory this pack's own redaction gate forbids it to
    reproduce. Everything after the wildcard is still literal, so a flag change still fails.

USAGE
    python check_workflow_parity.py                # exit 0 = every step mirrored or registered
    python check_workflow_parity.py --self-test    # the negative controls; writes only to temp
    python check_workflow_parity.py --ci-workflow <path> --portable-workflow <path>
                                    --exceptions <path>

EXIT CONTRACT
    0  every step in both workflows is mirrored or registered, and every registration is still
       real.
    1  an unregistered difference, a stale entry, an entry with no reason, an entry pointing at
       a command that is in neither workflow, a verify.yml `run:` step with no `shell: pwsh`, or
       BOTH files present and ZERO steps compared. The last is INCONCLUSIVE, which is a failure:
       a parity gate that compares nothing passes for the wrong reason.
    2  the comparison does not apply here -- one of the two workflows is not in this tree. This
       is the DISTRIBUTION case and it is the common one: the share pack ships tools/ci/verify.yml
       and no .github/ at all, so on a recipient's tree the far side was never sent. A scope
       fact, not a defect, and not something to hand a recipient as a red gate on their first
       run. Nothing was compared; still never a pass.

    The 1-versus-2 split is the one the practice documents insist on: "this does not apply here"
    and "it ran and measured nothing" must not share an exit code.

STDLIB ONLY except PyYAML, which both workflows already install. Python 3.8+.
"""
from __future__ import annotations

import argparse
import functools
import json
import re
import sys
import tempfile
from pathlib import Path

import yaml

print = functools.partial(print, flush=True)  # noqa: A001

EXIT_OK, EXIT_DIVERGED, EXIT_SKIPPED = 0, 1, 2
EXIT_INCONCLUSIVE = 1  # ran and measured nothing -- a failure, same code as diverged

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent          # tools/ci/ is two deep

# The two sides, named logically rather than by filename. An entry says which workflow it is
# about; it does not repeat a path, because the paths are this gate's flags and a registry that
# hardcoded them would break the moment either file moved.
CI, PORTABLE = "ci", "portable"
SIDE_NAME = {
    CI: ".github/workflows/build-and-verify.yml",
    PORTABLE: "tools/ci/verify.yml",
}
KINDS = ("provisioning", "ci-only", "variant")


def norm(command: str) -> str:
    """The comparison key. See NORMALISATION in the module docstring."""
    text = re.sub(r"\s+", " ", (command or "").replace("\\", "/")).strip()
    return text[2:] if text.startswith("./") else text


def as_pattern(recorded: str):
    """A recorded command, compiled. Literal except for `*`, which matches anything."""
    return re.compile("".join(".*" if part == "*" else re.escape(part)
                              for part in re.split(r"(\*)", recorded)))


def load_steps(path: Path):
    """[(job, name, command, shell, multiline)] for every `run:` step, in workflow order.

    Parsed with PyYAML rather than a line regex for the reason check_command_parity.py gives:
    the two files use three different scalar styles for `run:` -- plain, folded `>-` and block
    `|` -- and a line-anchored regex reads the last two as ">-" and "|" and reports every one of
    them as a difference.
    """
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    steps = []
    if not isinstance(data, dict):
        return steps
    for job_name, job in (data.get("jobs") or {}).items():
        if not isinstance(job, dict):
            continue
        for step in (job.get("steps") or []):
            if not isinstance(step, dict) or "run" not in step:
                continue
            steps.append((job_name, step.get("name"), norm(step["run"]), step.get("shell"),
                          "\n" in str(step["run"]).strip()))
    return steps


def load_exceptions(path: Path):
    """Registered differences. Absent file = none registered, which is the healthy state for a
    pair that has not diverged and must not be an error."""
    if not path.exists():
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(data, dict):
        data = data.get("exceptions", [])
    return list(data or [])


def entry_sides(entry):
    """[(side, recorded_command)] for one entry, or None if its shape is wrong.

    A `variant` records BOTH commands and therefore has two sides; everything else has one. The
    two-sided form is the whole reason this is a function: it is what stops a flag added on the
    portable half from hiding under an entry written for the hosted half.
    """
    kind = entry.get("kind")
    if kind == "variant":
        ci, pt = entry.get("ci_command"), entry.get("portable_command")
        if not ci or not pt:
            return None
        return [(CI, norm(ci)), (PORTABLE, norm(pt))]
    if kind in ("provisioning", "ci-only"):
        side, command = entry.get("workflow"), entry.get("command")
        if side not in (CI, PORTABLE) or not command:
            return None
        return [(side, norm(command))]
    return None


def _label(entry, index):
    return entry.get("label") or entry.get("command") or entry.get("ci_command") or f"entry #{index}"


def _short(text, width=88):
    return text if len(text) <= width else text[:width] + "..."


def check(ci_workflow: Path, portable_workflow: Path, exceptions_path: Path, verbose=False):
    for path in (ci_workflow, portable_workflow):
        if not path.exists():
            print(f"SKIPPED: {path} is not in this tree -- nothing to compare. "
                  f"Not a pass; the comparison does not apply here. A distribution ships the "
                  f"portable workflow and no .github/, so this is the expected outcome there.")
            return EXIT_SKIPPED

    failures, notes = [], []

    try:
        steps = {CI: load_steps(ci_workflow), PORTABLE: load_steps(portable_workflow)}
    except yaml.YAMLError as exc:
        steps = {CI: [], PORTABLE: []}
        failures.append(f"a workflow will not parse ({exc}) -- it is present, so this is a defect, "
                        f"not a scope limit")

    commands = {side: {s[2] for s in steps[side]} for side in (CI, PORTABLE)}
    mirrored = commands[CI] & commands[PORTABLE]

    # ---- the registry, and whether every entry still describes something real -----------------
    entries = load_exceptions(exceptions_path)
    registered = {CI: {}, PORTABLE: {}}   # live command -> entry

    for i, entry in enumerate(entries):
        label = _label(entry, i)
        sides = entry_sides(entry)
        if sides is None:
            failures.append(
                f"{label}: entry shape is wrong -- `kind` must be one of {', '.join(KINDS)}, a "
                f"variant must carry `ci_command` AND `portable_command`, and anything else must "
                f"carry `workflow` ({CI} or {PORTABLE}) AND `command`. An entry this gate cannot "
                f"read is an exemption it cannot check.")
            continue
        if not str(entry.get("reason", "")).strip():
            failures.append(f"{label}: registered with no reason -- an exemption nobody justified "
                            f"is a silencer, not a decision")
            continue

        for side, recorded in sides:
            pattern = as_pattern(recorded)
            hits = sorted(c for c in commands[side] if pattern.fullmatch(c))
            if not hits:
                failures.append(
                    f"{label}: the recorded {side} command is no longer in "
                    f"{SIDE_NAME[side]} -- the exemption points at nothing; remove it, or fix it.\n"
                    f"      registered: {_short(recorded)}")
                continue
            for hit in hits:
                if hit in mirrored:
                    failures.append(
                        f"{label}: registered as a {entry['kind']} difference, but this command is "
                        f"now MIRRORED in both workflows -- the exemption outlived the difference "
                        f"it was written for and will absorb the next one silently; remove it.\n"
                        f"      command: {_short(hit)}")
                else:
                    registered[side][hit] = entry

    # ---- every step, both directions ----------------------------------------------------------
    for side in (CI, PORTABLE):
        other = PORTABLE if side == CI else CI
        for job, name, command, _shell, multiline in steps[side]:
            where = f"{SIDE_NAME[side]} [{job}] {name or '(unnamed step)'}"
            if multiline:
                # Informative, never an excuse. A `run: |` body cannot be mirrored into the
                # portable workflow at all -- its runner refuses a block scalar rather than
                # guessing at a multi-line shell body -- so the only honest resolution for one of
                # these is a registered entry, not a copy. It still has to have one.
                notes.append(f"{where}: multi-line `run:` body -- unmirrorable by construction, "
                             f"so it must be REGISTERED rather than copied across")
            if command in mirrored:
                if verbose:
                    print(f"  ok          {where}")
            elif command in registered[side]:
                if verbose:
                    print(f"  registered  {where}: {registered[side][command]['reason'][:110]}")
            else:
                failures.append(
                    f"{where}: this step has no counterpart in {SIDE_NAME[other]} and the "
                    f"difference is not registered.\n"
                    f"      run: {_short(command)}\n"
                    f"      Mirror it, or register it WITH ITS REASON in {exceptions_path.name}. "
                    f"A step only one of the two workflows runs is a gate a local run cannot "
                    f"prove it exercised.")

    # ---- verify.yml's own shape contract ------------------------------------------------------
    # This is what makes the portable file DRIVABLE, not merely valid: Invoke-LocalCI.ps1 routes
    # each step by the shell the workflow DECLARES. A step with no `shell:` is not routed to pwsh,
    # reaches the runner's completeness check as unaccounted, and fails the whole local run.
    # The companion rule -- no `run: |` block scalars -- already has a control in
    # Invoke-LocalCI.SelfTest.ps1, so it is deliberately NOT duplicated here.
    for job, name, command, shell, _multiline in steps[PORTABLE]:
        if shell != "pwsh":
            failures.append(
                f"{SIDE_NAME[PORTABLE]} [{job}] {name or '(unnamed step)'}: declares "
                f"`shell: {shell or '(none)'}`, not `shell: pwsh`. The portable runner routes by "
                f"the DECLARED shell, so this step is one it cannot execute and the local run "
                f"fails as a whole rather than skipping it.\n"
                f"      run: {_short(command)}")

    compared = len(steps[CI]) + len(steps[PORTABLE])
    for n in notes:
        print(f"  skipped     {n}")

    print("=" * 78)
    if failures:
        print(f"WORKFLOW PARITY: FAIL ({len(steps[CI])} hosted + {len(steps[PORTABLE])} portable "
              f"step(s), {len(mirrored)} mirrored command(s), {len(failures)} problem(s))")
        for f in failures:
            print(f"  - {f}")
        return EXIT_DIVERGED

    # The vacuous-pass guard. Both files are present, so the comparison APPLIES; comparing no step
    # means this gate measured nothing and must not report a pass.
    if compared == 0:
        print(f"WORKFLOW PARITY: INCONCLUSIVE -- both workflows are present and NOT ONE `run:` "
              f"step was compared. A parity gate that compares nothing passes for the wrong "
              f"reason.")
        return EXIT_INCONCLUSIVE

    print(f"WORKFLOW PARITY: PASS ({len(steps[CI])} hosted + {len(steps[PORTABLE])} portable "
          f"step(s) compared, {len(mirrored)} mirrored command(s), "
          f"{len(entries)} registered exception(s))")
    return EXIT_OK


# ── negative controls ─────────────────────────────────────────────────────────────────────────
def _write_workflow(path: Path, steps):
    """A minimal one-job workflow. `steps` is a list of (name, run, shell); shell None omits the
    key, which is the shape the portable-side shape check exists to catch."""
    lines = ["name: t", "on: [push]", "jobs:", "  verify:", "    runs-on: windows-latest",
             "    steps:", "      - uses: actions/checkout@v4"]
    for name, run, shell in steps:
        lines.append(f"      - name: {json.dumps(name)}")
        if shell:
            lines.append(f"        shell: {shell}")
        lines.append(f"        run: {json.dumps(run)}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


MIRROR = ("Practice gate", "./tools/Test-PracticeClaims.ps1", "pwsh")


def _tree(root: Path, ci_steps, portable_steps):
    _write_workflow(root / "build-and-verify.yml", ci_steps)
    _write_workflow(root / "verify.yml", portable_steps)


def self_test() -> int:
    import contextlib, io
    controls, failed = [], []

    def control(label, expect, build, exceptions=None):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            build(root)
            exc_path = root / "exceptions.json"
            if exceptions is not None:
                exc_path.write_text(json.dumps(exceptions), encoding="utf-8")
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                got = check(root / "build-and-verify.yml", root / "verify.yml", exc_path)
            ok = got == expect
            controls.append((label, ok, expect, got))
            if not ok:
                failed.append((label, expect, got, buf.getvalue()))

    def wrap(entry):
        return {"exceptions": [entry]}

    # A gate that only ever sees agreement has not been shown to fail.
    control("a mirrored pair passes", EXIT_OK,
            lambda r: _tree(r, [MIRROR], [MIRROR]))
    # The property the whole gate turns on: the KEY is the command, never the step name.
    control("step names may differ where the commands match", EXIT_OK,
            lambda r: _tree(r, [("Citations, figures, redaction", "./tools/T.ps1", "pwsh")],
                               [("The prose is honest", "./tools/T.ps1", "pwsh")]))
    control("a leading ./ and a backslash are transport, not a difference", EXIT_OK,
            lambda r: _tree(r, [("a", ".\\tools\\T.ps1  -Self", "pwsh")],
                               [("a", "./tools/T.ps1 -Self", "pwsh")]))

    # Both directions. The reverse one is the half a gate written from the hosted side forgets.
    control("an unregistered hosted-only step fails", EXIT_DIVERGED,
            lambda r: _tree(r, [MIRROR, ("extra", "python only/in/ci.py", "pwsh")], [MIRROR]))
    control("an unregistered portable-only step fails", EXIT_DIVERGED,
            lambda r: _tree(r, [MIRROR], [MIRROR, ("extra", "python only/in/portable.py", "pwsh")]))

    control("a registered hosted-only step passes", EXIT_OK,
            lambda r: _tree(r, [MIRROR, ("extra", "python only/in/ci.py", "pwsh")], [MIRROR]),
            exceptions=wrap({"kind": "ci-only", "workflow": CI,
                             "command": "python only/in/ci.py", "reason": "deliberate, for a test"}))
    control("a registered portable-only provisioning step passes", EXIT_OK,
            lambda r: _tree(r, [MIRROR], [MIRROR, ("dep", "python -m pip install PyYAML", "pwsh")]),
            exceptions=wrap({"kind": "provisioning", "workflow": PORTABLE,
                             "command": "python -m pip install PyYAML",
                             "reason": "deliberate, for a test"}))
    control("a registered entry with no reason fails", EXIT_DIVERGED,
            lambda r: _tree(r, [MIRROR, ("extra", "python only/in/ci.py", "pwsh")], [MIRROR]),
            exceptions=wrap({"kind": "ci-only", "workflow": CI,
                             "command": "python only/in/ci.py", "reason": "   "}))

    # The reverse half: an entry has to keep describing something that is really there.
    control("an entry for a command that is now MIRRORED fails as stale", EXIT_DIVERGED,
            lambda r: _tree(r, [MIRROR], [MIRROR]),
            exceptions=wrap({"kind": "ci-only", "workflow": CI,
                             "command": "tools/Test-PracticeClaims.ps1",
                             "reason": "no longer true"}))
    control("an entry whose command is in neither workflow fails", EXIT_DIVERGED,
            lambda r: _tree(r, [MIRROR], [MIRROR]),
            exceptions=wrap({"kind": "ci-only", "workflow": CI, "command": "python ghost.py",
                             "reason": "points at nothing"}))

    # Variants record BOTH sides, and both are compared against live text.
    def _variant_tree(ci_flag="-Gitleaks", pt_flag=""):
        def build(r):
            _tree(r, [MIRROR, ("scan", f"./tools/Scan.ps1 {ci_flag}".strip(), "pwsh")],
                     [MIRROR, ("scan", f"./tools/Scan.ps1 {pt_flag}".strip(), "pwsh")])
        return build

    VARIANT = {"kind": "variant", "label": "the scan",
               "ci_command": "tools/Scan.ps1 -Gitleaks", "portable_command": "tools/Scan.ps1",
               "reason": "deliberate, for a test"}
    control("a registered variant passes", EXIT_OK, _variant_tree(), exceptions=wrap(VARIANT))
    control("a variant whose hosted side gained a flag fails", EXIT_DIVERGED,
            _variant_tree(ci_flag="-Gitleaks -Deep"), exceptions=wrap(VARIANT))
    control("a variant whose portable side gained a flag fails", EXIT_DIVERGED,
            _variant_tree(pt_flag="-Shape"), exceptions=wrap(VARIANT))

    # The wildcard is a path escape, not a blanket: everything after it is still literal.
    control("a wildcard entry still pins the flags after it", EXIT_DIVERGED,
            lambda r: _tree(r, [MIRROR, ("gen", "python bundles/R.py --check --strict", "pwsh")],
                               [MIRROR]),
            exceptions=wrap({"kind": "ci-only", "workflow": CI,
                             "command": "python */R.py --check", "reason": "deliberate"}))

    # verify.yml's own shape contract, which nothing checked before this gate.
    control("a portable run step with no shell: pwsh fails", EXIT_DIVERGED,
            lambda r: _tree(r, [MIRROR], [("Practice gate", "./tools/Test-PracticeClaims.ps1", None)]))

    # scope versus vacuity -- the distinction the exit contract turns on
    control("an absent workflow is SKIPPED, not passed", EXIT_SKIPPED,
            lambda r: _write_workflow(r / "verify.yml", [MIRROR]))
    control("both workflows present with no run step at all is INCONCLUSIVE", EXIT_INCONCLUSIVE,
            lambda r: _tree(r, [], []))

    width = max(len(c[0]) for c in controls)
    for label, ok, expect, got in controls:
        print(f"  {'ok  ' if ok else 'FAIL'}  {label:<{width}}  expected {expect}, got {got}")
    print("=" * 78)
    if failed:
        print(f"SELF-TEST: FAIL ({len(failed)} of {len(controls)} controls)")
        for label, expect, got, out in failed:
            print(f"\n  --- {label}: expected {expect}, got {got}\n{out}")
        return EXIT_DIVERGED
    print(f"SELF-TEST: PASS ({len(controls)} controls)")
    return EXIT_OK


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--ci-workflow", type=Path,
                    default=REPO / ".github" / "workflows" / "build-and-verify.yml")
    ap.add_argument("--portable-workflow", type=Path, default=HERE / "verify.yml")
    ap.add_argument("--exceptions", type=Path, default=HERE / "workflow-parity-exceptions.json")
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--verbose", "-v", action="store_true")
    args = ap.parse_args(argv)

    if args.self_test:
        return self_test()
    return check(args.ci_workflow, args.portable_workflow, args.exceptions, verbose=args.verbose)


if __name__ == "__main__":
    sys.exit(main())
