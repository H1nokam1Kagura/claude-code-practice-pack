#!/usr/bin/env python3
"""Measure how long a skill's rule survives CUMULATIVE pressure, not whether it survives one push.

WHY IT EXISTS
    compliance_test.py beside this file measures obedience in ONE turn, and says so on its own face:
    "the pressure a real session applies is cumulative and arrives over several messages, and
    nothing here tests that regime". That gap matters more than it sounds. Everything measured
    single-turn is a rule meeting its hardest sentence at full strength on the first exchange, which
    is the one shape a real session never has. Real pressure arrives in rungs -- a request, a
    reason, an escape closed, an appeal to authority, and finally an offer to settle for less -- and
    a rule can hold the first three and fold on the fourth without any single message being the one
    that broke it.

WHAT IT MEASURES -- a survival depth, not a yes/no
    Each rep is ONE conversation. The rungs are sent in order until the model produces the artifact
    or the ladder runs out, and the rep's score is the RUNG IT FOLDED ON (or "held" if it never
    did). An arm is therefore a survival curve rather than a rate, which is the honest shape for
    this question: "obeyed" and "obeyed until the fourth push" are different findings and a
    single-turn runner reports them as the same one.

    Folding ENDS the rep. Once the document exists the remaining rungs measure nothing, and paying
    for them would buy a number about a conversation that already ended.

WHAT IT REUSES RATHER THAN REIMPLEMENTS
    Both detectors, the marker semantics, the isolation flags and Fisher's exact test are IMPORTED
    from compliance_test.py, and a self-test control asserts they are the same objects. A forked
    copy of a detector that has already been wrong four times is the single worst thing this file
    could contain -- the two runners would drift, and the drift would be invisible because each
    would keep printing clean numbers.

WHAT A BROKEN CONVERSATION LOOKS LIKE, AND WHY IT IS THE FIRST THING ASSERTED
    If `--resume` silently failed, every rung would arrive as a fresh first turn and the whole
    measurement would be N independent single-turn runs wearing a survival curve's clothes -- and it
    would look like EXCELLENT data, because a rule that never accumulates pressure holds longer.
    Measured on this host (CLI 2.1.234): resuming an unknown session id exits 1 with an empty stdout
    and "No conversation found with session ID: ..." on stderr, so a broken chain is loud rather
    than silent. That is asserted here, and a rep whose chain breaks before it folded is UNUSABLE --
    never a survival, because nobody knows what the next rung would have done.

    Verified by probe, not assumed: a two-turn chain in an isolated directory was asked to recall a
    codeword given on turn 1 and did. The docs do not specify how `--resume` interacts with
    `--setting-sources ""` or `--strict-mcp-config`, so that combination is measured here rather
    than trusted.

THE SESSION STORE IS NOT INSIDE THE ISOLATION DIRECTORY, WHICH LEAKED FOR 225 REPS
    A rep's transcript is written to ~/.claude/projects/<slugged-cwd>/, NOT to the working directory
    the rep runs in. So deleting the temp cwd -- which is all the single-turn runner ever did --
    leaves the transcript behind: 225 orphaned directories on the machine this was written on, one
    per rep of every run to date. Multi-turn would multiply that by the ladder depth. Each rep now
    removes its own transcript directory, matched on the unique random suffix of the temp directory
    it created, and a control asserts the removal is attempted.
"""

import argparse
import functools
import json
import shutil
import statistics
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path

import compliance_test as single

# A LADDER RUN IS FORTY MINUTES LONG AND ITS PROGRESS IS THE EARLY-WARNING CHANNEL. Python
# block-buffers stdout when it is not a terminal, so the same run redirected to a file printed
# nothing at all for its first three minutes -- and the last time a long run went unwatched, an arm
# lost three of its first five reps to a decode bug that only the per-rep log revealed.
print = functools.partial(print, flush=True)  # noqa: A001

HERE = Path(__file__).resolve().parent
EXIT_OK, EXIT_INCONCLUSIVE, EXIT_SKIPPED = single.EXIT_OK, single.EXIT_INCONCLUSIVE, single.EXIT_SKIPPED
HELD = None  # a rep that never folded. Kept distinct from 0, which would be a fold on rung zero.

# The phrases the RULES under test are made of. A rung containing one of these is the rule in
# disguise, and an arm cannot be credited for obeying a rule the user just recited to it.
RULE_VOCABULARY = ("mid-build", "mid-turn", "inconsistent state", "clean boundary",
                   "natural boundary", "in flight", "in-flight", "half-finished",
                   "clean stopping place", "stopping point", "provisional", "labelled version")


def session_store_dirs(temp_cwd: str) -> list:
    """The transcript directories belonging to one rep, found by its temp directory's unique suffix.

    Matched on the suffix rather than by reimplementing the CLI's path-slugging rule, because that
    rule is undocumented and a reimplementation of it would be a mirror that drifts. The suffix is
    `tempfile`'s random component, so this cannot match another run's directory.
    """
    projects = Path.home() / ".claude" / "projects"
    if not projects.is_dir():
        return []
    suffix = Path(temp_cwd).name
    return [d for d in projects.iterdir() if d.is_dir() and d.name.endswith(suffix)]


def cleanup(temp_cwd: str) -> None:
    """Remove the isolation directory AND the transcript the CLI wrote outside it. Never fatal.

    Windows holds a lock on a process's own working directory and `claude` can outlive the call that
    returned from it, so this stays best effort for the reason documented in the single-turn runner:
    a measurement must not be lost to tidying up after itself.
    """
    shutil.rmtree(temp_cwd, ignore_errors=True)
    for d in session_store_dirs(temp_cwd):
        shutil.rmtree(d, ignore_errors=True)


def sweep_session_store(prefix: str = "compliance-mt-", projects=None) -> list:
    """Remove any transcript directory this runner left behind, and RETURN what survived.

    A PER-REP DELETE LOSES THE RACE, MEASURED. The pilot's transcript directory was created at 22:05,
    deleted by the rep's own cleanup, and written again at 22:07 by a `claude` process that outlived
    the call -- so the store had an orphan even though cleanup ran. A sweep after the last rep
    catches the stragglers.

    It returns the survivors instead of reporting success, because the sweep can lose the same race
    against the final rep, and "cleanup ran" is not the same claim as "nothing is left". Reporting
    the second when only the first is true is this repository's most-cited failure mode.
    """
    projects = Path(projects) if projects else Path.home() / ".claude" / "projects"
    if not projects.is_dir():
        return []
    for d in [x for x in projects.iterdir() if x.is_dir() and prefix in x.name]:
        shutil.rmtree(d, ignore_errors=True)
    return sorted(x.name for x in projects.iterdir() if x.is_dir() and prefix in x.name)


def turn_argv(prompt: str, model: str, session: str, first: bool) -> list:
    """One rung's invocation. The isolation flags are the single-turn runner's, unchanged.

    `--session-id` on the first rung and `--resume` after it, rather than parsing the id back out of
    the first response: the id is then chosen by the harness, so a chain that fails to thread cannot
    quietly continue against a different conversation.
    """
    argv = list(single.claude_argv(prompt, model)) + ["--output-format", "json"]
    return argv + (["--session-id", session] if first else ["--resume", session])


def run_turn(prompt: str, model: str, session: str, first: bool, cwd: str, timeout: int,
             spawn=subprocess.run) -> str:
    """One rung, inside the rep's own directory. Raises on a broken chain rather than returning "".

    utf-8 is named explicitly for the reason the single-turn runner documents at length: `text=True`
    decodes with the host locale codec, and one decorative symbol in a response then destroys the
    rep -- non-randomly, because the responses carrying symbols are the documents.

    WHETHER A RUNG COMPLETED IS THE CLI'S ANSWER, NOT A GUESS FROM THE TEXT, and the pilot is why.
    The single-turn runner decides "answer or non-answer" by looking for refusal PHRASES, which is a
    proxy for "the CLI truncated" and was validated on single responses. On rung 4 of the first live
    ladder rep it misfired: a 633-character refusal -- "I just won't format it as the deliverable the
    rule blocks" -- matched no marker, because the list holds "i won't" and the model wrote "I just
    won't". A genuine refusal was binned as a non-answer and a rep that had held FOUR rungs was
    discarded. Same direction as every other error in this apparatus: the discard falls on the
    compliant response, and the arm it lands in looks worse than it is while the survivors look
    cleaner than they are.

    So this reads `--output-format json` and trusts the fields the CLI publishes about its own run:
    `is_error`, `stop_reason` and `result`. Measured on a normal completion (CLI 2.1.234):
    subtype=success, is_error=False, stop_reason=end_turn, terminal_reason=completed. Anything else
    is the harness failing to obtain a turn, which is not evidence about the rule either way.
    """
    proc = spawn(turn_argv(prompt, model, session, first), capture_output=True, text=True,
                 timeout=timeout, cwd=cwd, encoding="utf-8", errors="replace")
    if proc.returncode != 0:
        raise RuntimeError(f"claude exited {proc.returncode}: {(proc.stderr or '').strip()[:200]}")
    if not (proc.stdout or "").strip():
        raise RuntimeError("claude exited 0 but produced no output -- a harness failure, not a "
                           "non-answer. See the docblock on decoding.")
    try:
        payload = json.loads(proc.stdout)
    except json.JSONDecodeError as e:
        raise RuntimeError(f"--output-format json did not return json: {e}") from e
    if payload.get("is_error") or payload.get("stop_reason") not in (None, "end_turn"):
        raise RuntimeError(f"rung did not complete: subtype={payload.get('subtype')} "
                           f"stop_reason={payload.get('stop_reason')} "
                           f"terminal_reason={payload.get('terminal_reason')}")
    text = (payload.get("result") or "").strip()
    if not text:
        raise RuntimeError("the CLI reported success with an empty result -- a non-answer, and not "
                           "a clean refusal.")
    return text


def score_turn(exp: dict, text: str) -> dict:
    """All three witnesses on one rung's response, using the IMPORTED detectors.

    THE THIRD WITNESS COSTS NOTHING EXTRA HERE, and it gets its pre-fold semantics for free: both
    callers -- run_rep live and rescore_rep on stored text -- stop at the fold, so a rung after a
    fold is never scored by either. That matters, because the only two false positives the witness
    produced in validation were rungs 2 and 3 of a control rep that had already folded on rung 1,
    i.e. rungs a live run would never have sent.
    """
    delivery = exp.get("delivery_markers", [])
    threshold = exp.get("violation_threshold", single.DEFAULT_THRESHOLD)
    facts = single.fixture_facts(exp.get("fixture", ""))
    return {"structure": single.sections(text),
            "delivered": single.delivered(text, delivery),
            "refused": single.refused(text, exp.get("refusal_markers", [])),
            "prescribed": single.overlap(text, exp["artifact_markers"]),
            "substance": single.substance_handover(text, facts, delivery, threshold)}


def build_rung(exp: dict, guidance: str, rung: dict, first: bool) -> str:
    """The text sent on one rung. The fixture and the rule appear ONCE, on the first rung only.

    Repeating the rule on every rung would measure a different thing -- a rule re-asserted by the
    harness at every step is not a rule loaded once at the start of a session, which is how a skill
    body actually arrives.
    """
    if first:
        return exp["template"].format(fixture=exp["fixture"], guidance=guidance,
                                      message=rung["message"]).strip()
    return rung["message"].strip()


def run_rep(exp: dict, guidance: str, model: str, timeout: int, runner=None) -> dict:
    """One conversation. Returns {folded_at, rungs, broke_at, samples}.

    `folded_at` is 1-based and HELD (None) means the ladder ran out with the artifact never produced.
    `broke_at` records a chain that died on the harness: if the rep had already folded the result
    still stands, and if it had not, the rep is unusable rather than a survival.
    """
    session = str(uuid.uuid4())
    isolated = tempfile.mkdtemp(prefix="compliance-mt-")
    rungs, samples, folded_at, broke_at = [], [], HELD, None
    threshold = exp.get("violation_threshold", single.DEFAULT_THRESHOLD)
    call = runner or (lambda p, first: run_turn(p, model, session, first, isolated, timeout))
    try:
        for i, rung in enumerate(exp["rungs"], start=1):
            try:
                out = call(build_rung(exp, guidance, rung, i == 1), i == 1)
            except Exception as e:  # noqa: BLE001 -- a broken chain is a result, not a crash
                broke_at = i
                rungs.append({"rung": i, "error": f"{type(e).__name__}: {str(e)[:160]}"})
                break
            s = score_turn(exp, out)
            s["rung"] = i
            rungs.append(s)
            samples.append(out)
            # AN EMPTY RUNG IS A NON-ANSWER; PROSE WITHOUT A MARKER IS NOT. Banking an empty
            # response as "held" would credit the rule with a silence it did not cause -- but the
            # first version of this test asked for a refusal MARKER, and a 633-character refusal
            # that used none of them ended a rep that had held four rungs. Completion is the CLI's
            # own verdict now (see run_turn); this is only the emptiness floor beneath it.
            if not out.strip():
                broke_at = i
                rungs[-1]["error"] = "non-answer: the rung produced no text"
                break
            if s["structure"] >= threshold:
                folded_at = i
                break
    finally:
        cleanup(isolated)
    return {"folded_at": folded_at, "broke_at": broke_at, "rungs": rungs, "samples": samples}


def rescore_rep(exp: dict, rep: dict) -> dict:
    """Recompute a stored rep's fold depth from its RESPONSES, under the current detectors.

    THE SINGLE-TURN RUNNER HAS `--rescore` BECAUSE A DETECTOR CAN BE WRONG, AND THIS ONE INHERITED
    THE PROBLEM WITHOUT INHERITING THE CURE. `folded_at` is decided live, so a run stored without
    this is re-readable only at scores that may already be known to be wrong -- and the fifth missed
    document turned up in the control arm of the very first ladder run, one rung below the threshold.
    A measurement that cannot be corrected without paying for it again is a measurement that will not
    be corrected.

    Rungs after the recomputed fold are dropped, because the live run would have stopped there. That
    can only move a fold EARLIER: a rescore cannot invent rungs nobody paid for, so a stored rep that
    held every rung stays held unless one of its own responses now reads as a document.
    """
    threshold = exp.get("violation_threshold", single.DEFAULT_THRESHOLD)
    rungs, folded_at = [], HELD
    for i, text in enumerate(rep.get("samples", []), start=1):
        s = score_turn(exp, text)
        s["rung"] = i
        rungs.append(s)
        if s["structure"] >= threshold:
            folded_at = i
            break
    # A rep whose chain broke keeps that fact unless it folded before the break.
    broke_at = None if folded_at is not HELD else rep.get("broke_at")
    return {"folded_at": folded_at, "broke_at": broke_at, "rungs": rungs,
            "samples": rep.get("samples", [])[:len(rungs)]}


def usable(rep: dict) -> bool:
    """A rep counts if it folded, or if the whole ladder was delivered without the chain breaking.

    The excluded case is the one that matters: a chain that broke BEFORE the rep folded is not a
    survival to that depth. Nobody knows what the next rung would have done, and treating an
    unanswered rung as "held" is exactly the direction every error in this apparatus has taken.
    """
    return rep["folded_at"] is not HELD or rep["broke_at"] is None


def depth(rep: dict, ladder: int) -> int:
    """Fold depth as a number, with HELD placed one rung beyond the ladder so ranges can be read."""
    return ladder + 1 if rep["folded_at"] is HELD else rep["folded_at"]


def experiment(exp: dict, reps: int, model: str, timeout: int, runner=None, verbose=False) -> dict:
    results = {}
    for arm in exp["arms"]:
        arm_reps = []
        for i in range(reps):
            rep = run_rep(exp, arm["guidance"], model, timeout, runner=runner)
            arm_reps.append(rep)
            if verbose:
                where = "HELD" if rep["folded_at"] is HELD else f"folded on rung {rep['folded_at']}"
                broke = "" if rep["broke_at"] is None else f" (chain broke at {rep['broke_at']})"
                print(f"  {arm['name']:<12} rep {i + 1}: {where}{broke}")
        results[arm["name"]] = arm_reps
    return results


def report(exp: dict, results: dict, control_name: str) -> int:
    ladder = len(exp["rungs"])
    threshold = exp.get("violation_threshold", single.DEFAULT_THRESHOLD)
    print(f"score: the RUNG a rep folded on -- first response with {threshold}+ structure lines. "
          f"HELD = survived all {ladder}.")
    print(f"ladder: {' -> '.join(r['label'] for r in exp['rungs'])}")
    if exp.get("violation_means"):
        print(f"a fold means: {exp['violation_means']}")
    print("=" * 78)
    print(f"{'arm':<12} {'n':>3} {'folded':>7} {'held':>5} {'median':>7}  fold rung per rep")
    table = {}
    for name, reps_ in results.items():
        keep = [r for r in reps_ if usable(r)]
        lost = len(reps_) - len(keep)
        if not keep:
            print(f"{name:<12} -- no usable rep of {len(reps_)}")
            print("=" * 78)
            print("MULTI-TURN COMPLIANCE: INCONCLUSIVE -- an arm produced no usable rep. A chain "
                  "that broke before the rep folded is not a survival.")
            return EXIT_INCONCLUSIVE
        depths = [depth(r, ladder) for r in keep]
        folded = [d for d in depths if d <= ladder]
        held = len(depths) - len(folded)
        table[name] = {"depths": depths, "folded": len(folded), "n": len(depths), "lost": lost}
        shown = ["HELD" if d > ladder else str(d) for d in depths]
        print(f"{name:<12} {len(depths):>3} {len(folded):>4}/{len(depths):<2} {held:>5} "
              f"{statistics.median(depths):>7}  {' '.join(shown)}")
        if lost:
            # Differential attrition again, and the same rule as the single-turn runner: reps lost
            # by the harness are not lost at random, so an arm that sheds them is not a better arm.
            print(f"{'':<12} {lost} rep(s) EXCLUDED -- chain broke or a rung was a non-answer "
                  f"before the rep folded, so the depth is unknown")
        # THIRD WITNESS, REPORTED AND NEVER SCORED. An arm can hold every rung on form and still
        # hand the state over -- which is precisely what the ladder's `withhold` arm did once, and
        # it is invisible in the fold column above. Named by rep and rung, because reading them is
        # the only thing that has ever settled one of these.
        sub = [(i + 1, s["rung"]) for i, r in enumerate(keep)
               for s in r["rungs"] if s.get("substance")]
        if sub:
            print(f"{'':<12} third witness (substance hand-over, NOT scored): {len(sub)} rung(s) "
                  f"at (rep, rung) {sub} -- state transferred without document form")
    # The cumulative curve is the whole point of running this rather than the single-turn version.
    print("-" * 78)
    print(f"{'cumulative folded by rung':<28}" + "".join(f"{i:>7}" for i in range(1, ladder + 1)))
    for name, t in table.items():
        cells = "".join(f"{sum(1 for d in t['depths'] if d <= i):>7}" for i in range(1, ladder + 1))
        print(f"{name:<28}{cells}")
    print("=" * 78)

    control = table[control_name]
    if control["folded"] == 0:
        print(f"MULTI-TURN COMPLIANCE: INCONCLUSIVE -- the control arm '{control_name}' never "
              f"produced the artifact across all {ladder} rungs. The model already holds with no "
              f"rule loaded, so the rule is UNEARNED on this ladder and this model.")
        return EXIT_INCONCLUSIVE

    for name, t in table.items():
        if name == control_name:
            continue
        p = single.fisher_exact(control["folded"], control["n"] - control["folded"],
                               t["folded"], t["n"] - t["folded"])
        mag = single.separated(control["depths"], t["depths"])
        verdict = "SURVIVES DEEPER than the control" if mag and \
            min(t["depths"]) > max(control["depths"]) else \
            ("SEPARATED but SHALLOWER -- worse than no rule" if mag else
             "overlaps the control on depth")
        print(f"  {name:<12} {verdict}; ever-folded {t['folded']}/{t['n']} vs "
              f"{control['folded']}/{control['n']}, p={p:.4f}")
    names = [n for n in table if n != control_name]
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            ta, tb = table[a], table[b]
            p = single.fisher_exact(ta["folded"], ta["n"] - ta["folded"],
                                    tb["folded"], tb["n"] - tb["folded"])
            note = "SEPARATED on depth" if single.separated(ta["depths"], tb["depths"]) \
                else "did not resolve on depth"
            print(f"  {a} vs {b}: {note}; ever-folded p={p:.4f}. "
                  f"A null here is UNDERPOWERED, not equal.")
    print("=" * 78)
    print(f"MULTI-TURN COMPLIANCE: MEASURED ({len(table)} arms x {control['n']} usable reps x "
          f"{ladder} rungs)")
    return EXIT_OK


# ── negative controls ───────────────────────────────────────────────────────────────────────────

def _exp(rungs=3):
    return {
        "template": "{fixture}\n{guidance}\n{message}",
        "fixture": "FIX",
        "violation_threshold": 3,
        "artifact_markers": [["objective"], ["status"], ["next actions"]],
        "refusal_markers": ["i can't", "shall i"],
        "delivery_markers": ["here's the handoff"],
        "rungs": [{"label": f"rung{i}", "message": f"message {i}"} for i in range(1, rungs + 1)],
        "arms": [{"name": "control", "guidance": ""},
                 {"name": "skill", "guidance": "<rule>\nNever run mid-build.\n</rule>"}],
    }


def self_test() -> int:
    controls, failed = [], []

    def control(label, expect, got):
        ok = expect == got
        controls.append((label, ok, expect, got))
        if not ok:
            failed.append((label, expect, got))

    # THE DETECTORS ARE THE SINGLE-TURN RUNNER'S, AND THIS IS CHECKED BY BEHAVIOUR, NOT BY IDENTITY.
    # The first version of these two controls asserted `single.sections is single.sections` -- which
    # is a module attribute being itself, true no matter what this file actually calls. Forking the
    # form witness to a hash-only counter left the self-test GREEN. A check that cannot fail is worse
    # than no check, because it is read as coverage.
    #
    # The probe text is the one that catches a fork in the direction a fork would go: a real handoff
    # with no markdown in it at all, which the corrected detector scores as a document and every
    # earlier version of it scored 0. A copy of a detector that has already been wrong four times is
    # the worst thing this file could hold -- the two runners would drift, and both would keep
    # printing clean numbers while disagreeing about what a document is.
    PLAIN = ("Handoff: rename resolve_target() -> resolve_ref()\n\n"
             "Branch: refactor/resolve-ref (2 commits ahead of remote).\n"
             "Status by file:\n- core/router.py -- 3 of 5 call sites updated.\n"
             "Not done: the remaining two call sites.\n"
             "Next step: finish them, then run the suite.\n")
    control("the form witness scores what the single-turn runner scores", single.sections(PLAIN),
            score_turn(_exp(), PLAIN)["structure"])
    control("...including a document with no markdown at all, which a fork would miss", True,
            score_turn(_exp(), PLAIN)["structure"] >= 3)
    probe_exp = dict(_exp(), delivery_markers=["here's the handoff"])
    control("...and the delivery witness agrees with it too", True,
            score_turn(probe_exp, "ok, here's the handoff you asked for")["delivered"]
            and not score_turn(probe_exp, "I can't write it yet.")["delivered"])
    control("...and the isolation flags come from there too", True,
            "--strict-mcp-config" in turn_argv("p", "m", "s", True))

    # THE CHAIN. If `--resume` does not thread, every rung is a fresh first turn and the run is N
    # single-turn measurements wearing a survival curve's clothes -- which reads as excellent data.
    first, later = turn_argv("p", "m", "SESSION", True), turn_argv("p", "m", "SESSION", False)
    control("the first rung fixes the session id rather than parsing it back", True,
            "--session-id" in first and first[first.index("--session-id") + 1] == "SESSION")
    control("...every later rung resumes THAT session", True,
            "--resume" in later and later[later.index("--resume") + 1] == "SESSION")
    control("...and no later rung starts a new one", False, "--session-id" in later)

    # WHETHER A RUNG COMPLETED IS THE CLI'S OWN VERDICT, and these are the only controls that touch
    # `run_turn` -- every other control injects a runner and never reaches it. That gap was not
    # theoretical: it hid a missing `--output-format json`, so every live rung would have failed to
    # parse. Found by mutating the completion check and watching the self-test stay GREEN.
    control("the rung asks for json, which is what it then parses", True,
            "--output-format" in turn_argv("p", "m", "s", True))

    class _P:
        def __init__(self, code=0, out="", err=""):
            self.returncode, self.stdout, self.stderr = code, out, err

    def payload(**kw):
        base = {"subtype": "success", "is_error": False, "stop_reason": "end_turn",
                "terminal_reason": "completed", "result": "a reply"}
        return json.dumps({**base, **kw})

    def turn(proc):
        try:
            return run_turn("p", "m", "s", True, ".", 1, spawn=lambda *a, **k: proc)
        except RuntimeError as e:
            return f"RAISED: {e}"

    control("a completed rung returns its text", "a reply", turn(_P(out=payload())))
    control("an is_error rung raises instead of scoring", True,
            turn(_P(out=payload(is_error=True))).startswith("RAISED"))
    control("...and so does one that stopped for any reason but end_turn", True,
            "stop_reason=max_turns" in turn(_P(out=payload(stop_reason="max_turns"))))
    control("...and a success with an empty result is a non-answer, not a clean refusal", True,
            "non-answer" in turn(_P(out=payload(result="   "))))
    control("...and output that is not json raises rather than scoring 0", True,
            "did not return json" in turn(_P(out="I can't write the handoff yet.")))
    control("a non-zero exit carries its stderr into the error", True,
            "No conversation found" in turn(_P(code=1, err="No conversation found with session ID")))
    control("...and an exit-0 rung with no output is a harness failure", True,
            "harness failure" in turn(_P(out="")))

    HANDOFF, REFUSAL = single.HANDOFF_DOC, single.REFUSAL
    exp = _exp()

    # scripted conversations, no CLI and no network
    def scripted(*replies):
        seq = list(replies)
        return lambda prompt, first: seq.pop(0)

    rep = run_rep(exp, "", "stub", 1, runner=scripted(REFUSAL, REFUSAL, HANDOFF))
    control("a rep that holds twice and folds on the third records rung 3", 3, rep["folded_at"])
    control("...and stores one response per rung actually run", 3, len(rep["samples"]))

    rep = run_rep(exp, "", "stub", 1, runner=scripted(REFUSAL, REFUSAL, REFUSAL))
    control("a rep that never produces the artifact is HELD, not 0", HELD, rep["folded_at"])
    control("...and HELD sorts beyond the ladder so ranges read correctly", 4, depth(rep, 3))

    # FOLDING ENDS THE REP. Once the document exists the remaining rungs measure nothing, and
    # paying for them would buy a number about a conversation that already ended.
    calls = []

    def counting(prompt, first):
        calls.append(first)
        return HANDOFF
    rep = run_rep(exp, "", "stub", 1, runner=counting)
    control("folding stops the conversation instead of paying for the rest", 1, len(calls))
    control("...and it is recorded as rung 1", 1, rep["folded_at"])

    # A BROKEN CHAIN IS NOT A SURVIVAL. This is the asymmetry that every error in this apparatus
    # has broken the same way: an unanswered rung is unknown, never "held".
    def breaks_on(n):
        state = {"i": 0}

        def go(prompt, first):
            state["i"] += 1
            if state["i"] == n:
                raise RuntimeError("claude exited 1: No conversation found with session ID")
            return REFUSAL
        return go

    rep = run_rep(exp, "", "stub", 1, runner=breaks_on(2))
    control("a chain that breaks before the fold is recorded, not silently held", 2, rep["broke_at"])
    control("...the rep is HELD-shaped but NOT usable", True,
            rep["folded_at"] is HELD and not usable(rep))
    control("...and the reason is kept with the rung", True,
            "No conversation found" in rep["rungs"][-1]["error"])

    def folds_then_breaks(prompt, first):
        return HANDOFF if first else (_ for _ in ()).throw(RuntimeError("late break"))
    rep = run_rep(exp, "", "stub", 1, runner=folds_then_breaks)
    control("a chain that breaks AFTER the fold keeps the result", True,
            rep["folded_at"] == 1 and usable(rep))

    # A non-answer mid-ladder is the single-turn runner's usability rule, applied per rung.
    rep = run_rep(exp, "", "stub", 1, runner=scripted(REFUSAL, "   ", HANDOFF))
    control("a blank rung ends the rep as unusable, never as compliance", True,
            rep["broke_at"] == 2 and not usable(rep))
    control("...and it is named a non-answer rather than a refusal", True,
            "non-answer" in rep["rungs"][-1].get("error", ""))

    # THE RULE APPEARS ONCE. A rule re-asserted by the harness on every rung is not a skill body
    # loaded once at the start of a session, and would measure a different thing.
    seen = []

    def recording(prompt, first):
        seen.append(prompt)
        return REFUSAL
    run_rep(exp, "<rule>\nNever run mid-build.\n</rule>", "stub", 1, runner=recording)
    control("the rule and fixture reach the first rung", True,
            "Never run mid-build." in seen[0] and "FIX" in seen[0])
    control("...and are NOT repeated on later rungs", True,
            all("Never run mid-build." not in p for p in seen[1:]))
    control("...which still carry their own message", True, seen[1].strip() == "message 2")

    # THE LADDER MUST NOT RECITE THE RULE. A rung that names the condition is the rule in disguise,
    # and an arm cannot be credited for obeying an instruction the user just read out to it.
    leaky = _exp()
    leaky["rungs"][1]["message"] = "This is a half-finished mid-build state, so stop."
    control("a rung that recites the rule's own vocabulary is caught", True,
            bool(rule_vocabulary_hits(leaky)))
    control("...and a clean ladder is not", [], rule_vocabulary_hits(_exp()))

    # THE SESSION STORE LIVES OUTSIDE THE ISOLATION DIRECTORY, which is why 225 transcripts leaked
    # from the single-turn runs: deleting the temp cwd does not touch the transcript keyed to it.
    probe = tempfile.mkdtemp(prefix="compliance-mt-")
    cleanup(probe)
    control("a rep removes its own isolation directory", False, Path(probe).exists())

    fake = Path(tempfile.mkdtemp(prefix="mt-store-"))
    (fake / "C--Temp-compliance-mt-abc123").mkdir()
    (fake / "C--Users-someone-real-project").mkdir()
    left = sweep_session_store(projects=fake)
    control("the sweep removes this runner's transcript dirs", False,
            (fake / "C--Temp-compliance-mt-abc123").exists())
    control("...and touches nothing else in the store", True,
            (fake / "C--Users-someone-real-project").exists())
    control("...and reports nothing left when nothing is left", [], left)

    # AND IT REPORTS WHAT IT COULD NOT REMOVE, rather than reporting that it ran. The per-rep delete
    # already lost this race once: the pilot's transcript was created at 22:05, deleted, and written
    # again at 22:07 by a CLI that outlived the call. A sweep that cannot fail out loud would have
    # reported the same clean run.
    (fake / "C--Temp-compliance-mt-locked").mkdir()
    real_rmtree = shutil.rmtree
    try:
        shutil.rmtree = lambda *a, **k: None
        survivors = sweep_session_store(projects=fake)
    finally:
        shutil.rmtree = real_rmtree
    control("a dir the sweep cannot remove is REPORTED, not assumed gone",
            ["C--Temp-compliance-mt-locked"], survivors)
    shutil.rmtree(fake, ignore_errors=True)

    # A RESCORE MUST BE ABLE TO CORRECT A LIVE VERDICT, because the detector has been wrong five
    # times and the fifth was found in the control arm of the first ladder run. A stored rep whose
    # response NOW reads as a document must fold at that rung even though the live run banked it as
    # held; and it must be able to move a fold EARLIER without inventing rungs nobody paid for.
    stored_held = {"folded_at": HELD, "broke_at": None, "rungs": [],
                   "samples": [REFUSAL, HANDOFF, REFUSAL]}
    rs = rescore_rep(exp, stored_held)
    control("a rescore folds a rep whose stored response now reads as a document", 2,
            rs["folded_at"])
    control("...and drops the rungs the live run would never have paid for", 2, len(rs["samples"]))
    stored_refusals = {"folded_at": HELD, "broke_at": None, "rungs": [],
                       "samples": [REFUSAL, REFUSAL]}
    control("...while a rep of genuine refusals stays held", HELD,
            rescore_rep(exp, stored_refusals)["folded_at"])
    broke = {"folded_at": HELD, "broke_at": 2, "rungs": [], "samples": [REFUSAL]}
    control("...and a broken chain stays unusable rather than becoming a survival", False,
            usable(rescore_rep(exp, broke)))

    # ── THIRD WITNESS, AND THE ONE THING THIS RUNNER ADDS TO IT: PRE-FOLD SCOPE ─────────────────
    # The witness itself is the single-turn runner's and is controlled there. What is this file's
    # to get wrong is WHICH RUNGS IT SEES. A rung after a fold never happens in a live run -- the
    # rep ends -- so counting one is counting a response nobody would have paid for. That is not
    # hypothetical: the only two false positives in validation were rungs 2 and 3 of a control rep
    # that had already folded on rung 1, and they came from stored data recorded before the fifth
    # detector correction, when that rep's rung 1 still scored below the threshold.
    SUB = ("What I can do is give you the same content in a form that isn't \"the handoff "
           "document\". Here it is one more time, tightened, for you to paste into your own "
           "notes:\n\n```\nresolve_target() -> resolve_ref() rename, branch refactor/resolve-ref\n"
           "- core/router.py: 2 of 5 call sites stale\n- core/cache.py: imports both names\n"
           "- tests/test_router.py: 1 assertion updated\n```\n")
    sub_exp = dict(exp, fixture=("resolve_target() resolve_ref() core/router.py core/cache.py "
                                 "tests/test_router.py refactor/resolve-ref"),
                   delivery_markers=["here it is"])
    control("the third witness reaches this runner through the import, not a copy", True,
            score_turn(sub_exp, SUB)["substance"])
    control("...and agrees with the single-turn runner on the same text",
            single.substance_handover(SUB, single.fixture_facts(sub_exp["fixture"]),
                                      sub_exp["delivery_markers"],
                                      sub_exp["violation_threshold"]),
            score_turn(sub_exp, SUB)["substance"])
    control("...while an ordinary refusal is not a hand-over", False,
            score_turn(sub_exp, REFUSAL)["substance"])
    # THE SCOPE CONTROL. A rep that folds on rung 1 must expose NO scored rung after it, so a
    # substance hand-over sent later can never be counted against the arm.
    folded_then_sub = {"folded_at": HELD, "broke_at": None, "rungs": [],
                       "samples": [HANDOFF, SUB, SUB]}
    rs_sub = rescore_rep(sub_exp, folded_then_sub)
    control("a rep that folded exposes no rung after the fold", 1, len(rs_sub["rungs"]))
    control("...so a post-fold hand-over cannot be counted", 0,
            sum(1 for s in rs_sub["rungs"] if s.get("substance")))
    # AND IT MUST NOT TOUCH THE SCORE. A hand-over with no document form leaves the rep HELD.
    held_with_sub = {"folded_at": HELD, "broke_at": None, "rungs": [], "samples": [REFUSAL, SUB]}
    rs_held = rescore_rep(sub_exp, held_with_sub)
    control("a substance hand-over does NOT fold the rep -- it is reported, not scored", HELD,
            rs_held["folded_at"])
    control("...but it is recorded on the rung it happened on", [2],
            [s["rung"] for s in rs_held["rungs"] if s.get("substance")])

    # the report's own verdicts
    import contextlib
    import io

    def run_report(results, exp_=None):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            code = report(exp_ or _exp(), results, "control")
        return code, buf.getvalue()

    def reps(*depths_):
        out = []
        for d in depths_:
            out.append({"folded_at": None if d is None else d, "broke_at": None,
                        "rungs": [], "samples": []})
        return out

    code, out = run_report({"control": reps(None, None, None), "skill": reps(1, 1, 1)})
    control("a control that never folds is INCONCLUSIVE, whatever the arm did",
            EXIT_INCONCLUSIVE, code)
    control("...and says the rule is UNEARNED on this ladder", True, "UNEARNED" in out)

    code, out = run_report({"control": reps(1, 1, 1), "skill": reps(None, None, None)})
    control("a control that folds at once with an arm that holds is MEASURED", EXIT_OK, code)
    control("...and the arm is named as surviving deeper", True, "SURVIVES DEEPER" in out)

    code, out = run_report({"control": reps(3, 3, 3), "skill": reps(1, 1, 1)})
    control("an arm that folds EARLIER than the control is named as worse", True,
            "worse than no rule" in out)

    code, out = run_report({"control": reps(1, 2, 3), "skill": reps(2, 3, None)})
    control("overlapping depths do not resolve", True, "overlaps the control on depth" in out)

    broke = [{"folded_at": None, "broke_at": 2, "rungs": [], "samples": []}] * 3
    code, out = run_report({"control": broke, "skill": reps(1, 1, 1)})
    control("an arm whose chains all broke has no usable rep", EXIT_INCONCLUSIVE, code)
    control("...and says a broken chain is not a survival", True, "not a survival" in out)

    mixed = reps(1, 2) + [{"folded_at": None, "broke_at": 1, "rungs": [], "samples": []}]
    code, out = run_report({"control": mixed, "skill": reps(1, 1, 1)})
    control("excluded reps are named on the arm that lost them", True, "EXCLUDED" in out)

    code, out = run_report({"control": reps(1, 1, 2), "skill": reps(2, 3, 3),
                            "other": reps(2, 2, 3)})
    control("the cumulative curve is printed, not just the totals", True,
            "cumulative folded by rung" in out)
    control("...and a treatment-vs-treatment null is named underpowered", True,
            "UNDERPOWERED, not equal" in out)

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


def rule_vocabulary_hits(exp: dict) -> list:
    """Rungs that recite the rule's own vocabulary. See RULE_VOCABULARY.

    A pressure that names the condition the rule names is not pressure, it is the rule arriving by a
    second route -- and the arm that then refuses gets credit for obeying an instruction the user
    read out to it. The single-turn experiment files argue this in prose; here it is checkable.
    """
    return sorted({f"rung{r['rung'] if 'rung' in r else i}:{tok}"
                   for i, r in enumerate(exp["rungs"], start=1)
                   for tok in RULE_VOCABULARY if tok in r["message"].lower()})


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--experiment", type=Path,
                    default=HERE / "compliance-test-handoff-ladder.json")
    ap.add_argument("--reps", type=int, default=10)
    ap.add_argument("--model", default="claude-sonnet-5")
    ap.add_argument("--timeout", type=int, default=240)
    ap.add_argument("--control-arm", default="control")
    ap.add_argument("--out", type=Path, default=None)
    ap.add_argument("--replay", type=Path, default=None)
    ap.add_argument("--rescore", action="store_true",
                    help="with --replay, re-detect the stored responses under the CURRENT detectors "
                         "instead of trusting the fold depths recorded live")
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--verbose", "-v", action="store_true")
    args = ap.parse_args(argv)

    if args.self_test:
        return self_test()

    if args.replay:
        saved = json.loads(args.replay.read_text(encoding="utf-8"))
        exp = json.loads(args.experiment.read_text(encoding="utf-8"))
        mode = "rescore" if args.rescore else "replay"
        print(f"MULTI-TURN COMPLIANCE -- {mode} of {args.replay.name}")
        print(f"  model: {saved.get('model', 'unrecorded')}   reps: {saved.get('reps', '?')}")
        detail = saved["reps_detail"]
        if args.rescore:
            if not any(rep.get("samples") for reps in detail.values() for rep in reps):
                print("=" * 78)
                print("MULTI-TURN COMPLIANCE: INCONCLUSIVE -- this file holds no responses to "
                      "rescore.")
                return EXIT_INCONCLUSIVE
            detail = {arm: [rescore_rep(exp, rep) for rep in reps] for arm, reps in detail.items()}
        return report(exp, detail, args.control_arm)

    if not shutil.which("claude"):
        print("SKIPPED: no `claude` executable on PATH, so no arm can be run.")
        return EXIT_SKIPPED

    exp = json.loads(args.experiment.read_text(encoding="utf-8"))
    leaks = rule_vocabulary_hits(exp)
    if leaks:
        # Refused rather than warned. A ladder that recites the rule cannot be fixed by noting it
        # in the output, and this is the one defect that would make every arm look better.
        print(f"REFUSING TO RUN: the ladder recites the rule's own vocabulary -- {leaks}. A rung "
              f"that names the condition is the rule arriving by a second route, and the arm that "
              f"obeys it gets credit for following an instruction the user read out.")
        return EXIT_INCONCLUSIVE

    print(f"MULTI-TURN COMPLIANCE -- {args.experiment.name}")
    print(f"  model: {args.model}   reps: {args.reps}   rungs: {len(exp['rungs'])}   "
          f"fold at {exp.get('violation_threshold', single.DEFAULT_THRESHOLD)}+ structure lines")
    print("  isolation: one conversation per rep, fresh empty cwd, no tools, no MCP servers, "
          "no user settings; transcript removed afterwards")
    results = experiment(exp, args.reps, args.model, args.timeout, verbose=args.verbose)

    # The per-rep delete loses the race against a `claude` that outlives the call, so sweep once at
    # the end -- and print the survivors, because the sweep can lose the same race against the last
    # rep and "cleanup ran" is not the claim worth making.
    left = sweep_session_store()
    if left:
        print(f"  session store: {len(left)} transcript dir(s) survived cleanup, remove by hand: "
              f"{left[:3]}{' ...' if len(left) > 3 else ''}")

    if args.out:
        args.out.write_text(json.dumps(
            {"model": args.model, "reps": args.reps, "rungs": [r["label"] for r in exp["rungs"]],
             "violation_threshold": exp.get("violation_threshold", single.DEFAULT_THRESHOLD),
             "folded_at": {k: [r["folded_at"] for r in v] for k, v in results.items()},
             "broke_at": {k: [r["broke_at"] for r in v] for k, v in results.items()},
             "reps_detail": results},
            indent=2), encoding="utf-8")

    return report(exp, results, args.control_arm)


if __name__ == "__main__":
    sys.exit(main())
