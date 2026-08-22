# Wording tests

How to find out whether a sentence you are about to add to an instruction file does anything. Every
number below was produced by [`wording_test.py`](wording_test.py) beside this file, on the
experiment in [`wording-test-example.json`](wording-test-example.json), and the run is re-readable
without paying for it again: `python wording_test.py --replay wording-test-result-2026-08-17.json`.

The one-line version:

> **Measure against a no-guidance control, or you are measuring the control's silence.** A rule that
> does nothing, a rule that helps, and a rule that makes things worse are indistinguishable in
> review. They are trivially distinguishable in a run of five.

---

## 1. Start with the control, and let it stop you

Run the task with no guidance at all, several times, and count the failure. **If the control does
not exhibit the failure, there is nothing to fix — stop.** Any wording you add will now look like an
improvement, because the improvement is the control's silence.

This is not advice in the runner, it is the exit path: a control that scores zero on every rep
returns 1 with *"nothing to fix"*, and the other arms are never run.

---

## 2. Read your task line for instructions hiding as context

The first version of the worked example below did not use a bare task. It asked for a summary
*"for a programme officer who funds this team and has never opened the repository"* — and that
audience clause **is** the instruction under test, wearing task framing as a disguise. The control
scored zero on every one of seven reps. Every arm would have tied at the floor, and the tie would
have read as agreement.

The control-first rule caught its own experiment before it caught anything else. When you copy the
example file, this is the line to re-read.

---

## 3. Five reps minimum, and report the spread

One rep is a single draw. The spread is a result in its own right: an arm with a wide range is
unreliable *even when its median is better*, and that is a property you want to know before you ship
the sentence, not after.

Report the counts, not a summary of them. The runner prints every rep.

---

## 4. Ask the two questions separately

**"Does guidance help?"** and **"which form of guidance is better?"** are different questions, and an
arm can answer the first decisively while saying nothing about the second. Compare each arm to the
control *and* the arms to each other.

If two arms both beat the control and neither beats the other, the second question **did not
resolve**. When both are sitting near zero, that is a floor effect: the failure was too easy, so the
task cannot discriminate between forms. Pick a harder task and run it again.

---

## 5. Match the form to the failure — but do not assume you know which way

The two forms an author actually chooses between are a **prohibition** (forbid the bad output) and a
**recipe** (describe the good one). They are not equivalent, and which one wins is not something to
reason about from an armchair.

---

## The worked example, in full

The failure under test is one this repository's own always-on instruction file already forbids: a
deliverable written for a reader who never saw the machinery should not name the machinery. The rule
exists and nothing measured whether any phrasing of it worked.

The metric is a count of fourteen fixed strings in the response — deterministic, and reproducible by
someone who does not trust us. A model scoring model output would put the measurement and its
subject in the same family, and the first thing a wording change would move is the judge.

*Measured 2026-08-17, seven reps per arm, one model held constant across arms.*

| arm | counts | median | range |
|---|---|---|---|
| control (no guidance) | 13, 7, 14, 14, 14, 14, 14 | 14 | 7–14 |
| prohibition | 0, 0, 1, 0, 1, 0, 0 | 0 | 0–1 |
| recipe | 1, 0, 0, 0, 1, 0, 0 | 0 | 0–1 |

**What it establishes.** Both forms separate from the control decisively, in the good direction. On
this task, saying anything at all was worth a great deal, and the control's own range shows why
reps matter — one draw came in well below the other six for no reason visible in the output.

**These are the second numbers, and the first ones were wrong.** The metric summed each banned
string independently, and the list contains both a file name and its own extension, so a single
mention scored twice. The error was found by reading the responses rather than the totals — and it
would never have been found by watching the verdict, because the arms separated just as cleanly
before the fix as after. That is the argument for storing the raw responses and not only the
counts: `--replay <file> --rescore` recounts them under the current list, so a metric can be
corrected without paying for the run again. The original totals are kept in the result file
alongside the corrected ones.

**What it does not establish, and this is the more useful half.** The two treatment arms **do not
separate from each other** — after the correction their ranges are identical. Both sit at the floor,
so this experiment cannot tell you whether a prohibition or a recipe is the better form; only that
the failure was easy enough for either to fix. Reporting that as a win for whichever arm had the
lower median would have been the exact error this document exists to prevent, and the first version
of the runner would have done it: it compared each arm only against the control, so it never asked
the question.

**On the result that prompted this document.** A prohibition arm producing *more* unwanted content
than a recipe arm, trending worse than no guidance at all, is a claim we took from another project's
own writing, read 2026-08-17, and it is **second-hand and not reproduced here**. Our run points the
other way on direction and does not resolve the form question at all. Treat their result as a reason
to measure, not as a finding to cite — which is the same standing this document asks you to give
its own table.

---

## What this does not do

- **It does not judge quality.** It counts one property of the output. A summary can score zero and
  be useless, and the runner will not notice.
- **It does not pick a winner when the arms overlap.** Overlapping ranges mean the experiment did
  not resolve. That is a result, not a tie to be broken by preference.
- **It does not measure whether a skill is obeyed once it fires.** That gap is still open and is
  named as such in [`README.md`](README.md).
- **It is not a substitute for a test.** It measures a tendency across reps; a gate asserts a
  property on every run. See [`TESTING-DISCIPLINE.md`](../claude-dev-practice/TESTING-DISCIPLINE.md).

The runner needs an interactive-auth CLI, so it exits 2 where that is absent — a scope fact, not a
defect. In continuous integration it runs `--self-test` only: the live arms are non-deterministic by
construction, and a gate whose verdict depends on a model's mood is not a gate.
