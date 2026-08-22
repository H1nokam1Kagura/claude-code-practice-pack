# claude-authoring-toolkit

Two contracts for the files that tell Claude what to do, and **the checks that keep each one
honest**: a skeleton for the always-on instruction file, and a frontmatter contract for skills.

They are here together because they are the same problem seen twice. Both files are read before
anyone decides anything; both are usually written once and never re-read; and both fail by
drifting rather than by breaking, so nothing surfaces the moment they stop being true.

| Part | Contract | Checked by |
|---|---|---|
| Always-on instruction file | stays a pointer; the substance lives behind gates | `check_pointer_file.py` |
| Skill frontmatter | declared in `skill-schema.json`, explained in `SKILL-FRONTMATTER.md` | `lint_skills.py`, `eval_skills.py` |
| The same contract, implemented twice | the shipped schema and the source repository's own hardcoded lint | `check_lint_parity.py` |

---

## The problem it solves

An always-on `CLAUDE.md` is loaded in full at the start of every session, however long it is.
Nothing truncates it, so it never fails loudly — it just gets more expensive and, per the
documentation, less well followed. That alone would only argue for brevity.

The sharper problem is that it is usually **ungated**. A personal one lives outside every
repository it describes: CI cannot read it, nothing can diff it against the system it documents,
and no test will ever run against it. So a rule written there is a rule nothing can check.

Put those together and the working architecture is forced:

- **Substance goes behind a gate** — a rules file scoped with a `paths:` glob so it loads when a
  matching file is read, a skill for a whole procedure, memory for a durable lesson.
- **The always-on file keeps only the subset that bites where no gated file will load** — in
  another repository, in a scratch script, in a session that never opens a matching file at all.
- **Every current count, threshold and percentage stays out entirely**, because a figure copied
  upward is a figure that goes wrong later with nothing to catch it.

And then the failure this toolkit actually exists for: **the architecture decays by being useful.**
Somebody copies a paragraph up because it was needed once in a session where the gated file did not
load. Now there are two copies. Both read as authoritative, neither is marked, and nothing compares
them — so when the gated one is corrected, the always-on one keeps asserting the old thing, silently
and with total confidence.

That is not hypothetical. Run against the always-on pointer file on the machine this was written on
— a file whose own opening line says it is a pointer, not a rule book — `check_pointer_file.py`
found **eight duplicated lines**, and one of them restated a conclusion the gated file had since
recorded as superseded. The always-on copy was still asserting the old reading, and inverting the
advice that followed from it. The convention was written down, agreed, and believed. It still rotted.
A convention nobody enforces is a convention that decays.

---

## What's in it

### `CLAUDE.md.template`

The skeleton. Every line is structure; none is content. It carries the pointer table, the
always-on-subset section with the test for what earns a place in it, and — deliberately — the
paragraph explaining *why* the file is a pointer, so the next person to add something sees the
reason before they add it.

Two mechanics it uses rather than just describes: block-level HTML comments are stripped before the
file is injected into context, so maintainer notes there cost nothing; and a project-root file is
re-injected after a `/compact` while path-scoped rules and nested files are not, which is one of the
few genuine claims a rule can make on always-on space.

### `check_pointer_file.py`

Three properties, and it is explicit about the fourth it cannot hold.

| Asserts | Why |
|---|---|
| Every pointer resolves | A pointer at nothing is worse than no pointer: it reads as a promise that the detail is somewhere. |
| Nothing is duplicated | The drift itself, caught at the moment somebody copies content up. Matches reworded copies too, because that is how it actually happens. |
| It is inside its budget | The line default is the documented target; the byte budget is a convention you set. |
| **Not**: whether a rule *belongs* there | A judgement about where a rule bites. No script will make it, and a green run must not be mistaken for a well-designed file. |

```bash
python check_pointer_file.py CLAUDE.md --rules-dir .claude/rules
python check_pointer_file.py CLAUDE.md --rules-dir .claude/rules --base ../the-repo-it-describes
python check_pointer_file.py --self-test
```

**Exit contract**

```text
0  every check ran and passed
1  a check FAILED, or a check ran and measured nothing (INCONCLUSIVE), or the target is unreadable
2  no rules directory, so the duplication check -- the load-bearing one -- does not apply here
```

Exit 2 is the one to read carefully. Without a rules directory this tool has only told you that
your links work, and reporting that as a pass would overstate it by the entire point of the
exercise.

`--self-test` runs twelve negative controls and writes only to a temp directory. Three of them are
false positives this tool produced on its first real run — a glob, a bare file extension in prose,
and a pointer resolving from the repo rather than from the file's own directory. They are controls
now because an over-flagging check is not a safe default; it is a check people learn to skim.

A fourth control caught something worse, in the tool's own design: coverage was being counted as
comparisons made, so a file with nothing substantive in it scored zero candidates and reported
INCONCLUSIVE. A file with nothing to duplicate is a *perfect* pointer, and the check was hardest on
the outcome it exists to encourage. Coverage is now counted on the side being guarded against.

---

## What's intentionally left out

- **Any judgement about content.** The tool cannot tell you whether a rule belongs in the always-on
  file, and says so on every green run rather than letting the absence of complaint imply approval.
- **A byte limit presented as a platform limit.** The line target is documented and sourced; the
  byte budget is a convention with no source, and is labelled as one.

---

## The skill frontmatter half

A skill's body loads only when it is used, so length there is nearly free. Its frontmatter is
loaded up front for every skill, and a description that loses its budget fight is simply not
there when the model chooses. That asymmetry is why the frontmatter is the part worth gating.

`SKILL-FRONTMATTER.md` is the contract in prose — what each field is for, why the governance
block has to be nested rather than hoisted, and why `risk_factors` is the only field in it that
can carry real information. `skill-schema.json` is the same contract as data, so a recipient
changes policy by editing a registry rather than by editing a script. The two are gated against
each other: the lint's self-test fails if the prose table and the schema ever name different
fields, which is the pack's standing answer to a rule written down in two places.

### `lint_skills.py` — the contract, mechanically

Required fields present and not placeholders (`TBD` is not a filled field), description inside
the budget **you** set, and the invocation name agreeing with the directory *where the profile
asks for it*. Profiles exist because one tree is rarely one contract — a curated catalogue wants
an owner and a review date, while a generated tree of plugin skills carries none and would fail
every file.

**No profile demands a top-level key the spec does not allow.** Outside the CLI a `SKILL.md` is
validated against a fixed field list and an unrecognised top-level key is a hard error, not an
ignored line. So a house field like `slash_command` is a **local extension**: the schema checks
it against the directory when a tree carries it, and never requires it. The trade-off — a local
convenience bought with portability — is written into the profile rather than left latent in a
required-field list. The schema shipped requiring it, which made it mandate the one thing the
prose beside it says never to do; both directions are controls now.

It also refuses to report zero coverage as success: containers that exist with no `SKILL.md`
under them is a stale glob, and stale globs are how a gate quietly stops checking anything.

`--self-test` additionally holds the pack to its own doctrine. The worked `risk_factors` exemplar
is written twice — once in `SKILL-FRONTMATTER.md` as the shape being argued for, once in
`examples/skills/incident-triage/SKILL.md` as the thing the checks read — and until it was gated,
nothing compared them. The comparison collapses whitespace, so the two can stay wrapped for their
own contexts and only a change in wording is a failure.

```bash
python lint_skills.py <tree-root>
python lint_skills.py <tree-root> --schema my-schema.json --profile catalogue
python lint_skills.py --self-test
```

`0` pass · `1` a check failed, or containers exist with no files · `2` no profile matched
anything, or PyYAML is missing — **not applicable, or could not run. Never a pass.**

### `check_lint_parity.py` — the contract is implemented twice, so the copies are gated

Two implementations of one contract, kept in step by hand, are not one contract. They are two that
agree until somebody edits one, and the disagreement surfaces as a skill that passes one gate and
fails the other with nothing to say which is right.

That had already happened here. The source repository gates its own catalogue with a separate,
hardcoded lint — `.github/scripts/lint_skills.py` — while `skill-schema.json` is the generalised
contract that ships. Compared on 2026-08-16, two of the five properties agreed and **three did
not**, and nothing anywhere recorded that any of the three was a decision. The substantive one:
the repo-side lint requires a top-level `name`, and the schema deliberately does not, because in a
personal or project skill the command comes from the directory and `name` is a display label.
Requiring it is a house rule. A catalogue may reasonably want one — but a house rule presented as a
platform rule is the thing this toolkit exists to stop, and an undeclared difference cannot be told
apart from a copy that stopped being maintained.

Retiring one copy was the cleaner-looking option and was rejected: the repo-side lint holds a
working catalogue, and re-baselining it would change what CI enforces on live files as a side
effect of a documentation cleanup. So instead — keep the copies, gate the copies
([TESTING-DISCIPLINE.md](../claude-dev-practice/TESTING-DISCIPLINE.md) section 6).

Every difference must be registered in `lint-parity-exceptions.json` with a `reason`. Two rules
make the registry a decision record rather than a silencer:

| Fails | Why |
|---|---|
| An unregistered difference | The default outcome, so drift surfaces the day it lands. |
| A registered exception whose sides have converged | An exemption for a divergence that no longer exists is one nobody granted, and it will absorb the *next* divergence on that property. |
| A registered exception whose sides differ in a shape it does not record | Same failure, one step subtler: one entry would otherwise cover every future change to the same field. |
| An exception with no reason | An escape hatch without a reason is a silencer. |

It reads the repo side by parsing it, never by importing it: that file runs its whole lint at
module scope, so importing it would lint the repository as a side effect. A constant that is
absent, or present but not a literal, is a failure and **never a default** — a check that compares
four properties while reporting five is the defect it exists to catch.

```bash
python check_lint_parity.py
python check_lint_parity.py --self-test
python check_lint_parity.py --repo-lint <path> --schema <path> --exceptions <path>
```

**Exit contract**

```text
0  the two agree, or every difference is registered and still real
1  an unregistered difference, a stale exception, an exception with no reason, or a
   constant that could not be read -- the last is INCONCLUSIVE, which is a failure
2  the repo-side lint is not in this tree, so nothing was compared
```

> **It needs both copies, and only one of them is in this toolkit.** The repo-side lint lives in
> the source repository's workflow scripts, not here. Run from a distribution containing just this
> directory, the script exits **2** and says plainly that nothing was measured — it will not report
> a parity it could not make. Exit **1** is reserved for the real failures, including a repo-side
> file that is present and will not parse.

`--self-test` runs seventeen negative controls against fixtures in a temp directory. The first two
findings were in the controls themselves: two fixtures shared a filename, so each read a later
control's file and passed for the wrong reason. That is the argument for writing the controls
before trusting the tool.

### `eval_skills.py` — whether the description actually works

A lint proves a description exists. It cannot tell you whether it would get the skill chosen at
the right moment and left alone at the wrong one, because that is a behavioural property of a
model reading prose. So this asks a model and counts, over a probe set you write.

**The non-triggering probes are the hard half, and this is the part worth copying.** A skill
almost never fires on an unrelated request; it fires on its *neighbour* — the skill beside it
describing adjacent work in shared vocabulary. Probing with easy negatives reports an accuracy
the skill has not earned, because it measures a confusion nobody was going to make. Every
negative in `probes.example.json` is aimed at a sibling and names which one.

Two halves, and the cheap one runs first. **Coverage** — every skill has probes, every probe
names a skill that exists — is a static property of the tree, so it needs no key, no network
and no spend, and it runs before the API gate. That makes a coverage regression fail on a fork
or before any secret exists, and it avoids spending a few hundred model calls to discover
something that was knowable for free. **Accuracy** is the half that costs money.

Coverage is checked in *both* directions. A probe naming a skill that no longer exists always
failed loudly; the reverse — a skill no probe covers — did not, so a new skill scored nothing
while the summary read all-green. That is the same asymmetry as any gate that accounts for what
it found rather than for what exists.

```bash
python eval_skills.py <tree-root> --probes probes.json
python eval_skills.py <tree-root> --probes probes.json --write-back
python eval_skills.py <tree-root> --probes probes.json --coverage-only  # the free half only
python eval_skills.py --self-test        # offline: no key, no API calls, no spend
```

`0` pass · `1` below threshold, or coverage incomplete, or the probe file is malformed ·
`2` the accuracy half could not run (no key, or no SDK) — **SKIPPED, never a pass**. An earlier
version exited `0` with a warning when the key was absent, so a repository with no secret
reported a green eval forever while measuring nothing.

`--coverage-only` runs the free half against a real tree and stops, narrowing the contract to `0`
or `1`: it never reads the key, never imports the SDK and never scores a probe. It exists because
a plain run always reaches the accuracy half, so until the flag existed there was no invocation
that exercised the coverage check against the shipped example skills and returned `0` — the eval
was only ever run against fixtures it builds itself, which is exactly the gap the lint's live run
exists to close. It is **not** a cheaper way to run the eval and is not allowed to become one: its
`0` means *every skill in this tree is probed*, never *the descriptions work*, and it says so on
every run, green or red. `--coverage-only --write-back` is refused outright, because there is no
measured rate to write back. The default is unchanged — a plain run with no key still exits `2`.

`--write-back` records the measured rate in each skill's own frontmatter. Off by default, and
it rewrites only the two `eval_` lines — a YAML round-trip would reformat the whole block and
bury the one line that changed in a diff nobody can review.

### What neither of them can tell you

Whether the skill does good work once it has fired. Nothing here measures **quality**, and a green
run must not be read as though it did.

Whether the skill is **obeyed** once it has fired now has a baseline, and it is a narrower claim
than the one above: [`COMPLIANCE-TESTS.md`](COMPLIANCE-TESTS.md) and
[`compliance_test.py`](compliance_test.py) measure whether a *rule inside* a skill survives a user
pushing back on it, against a control that has no skill loaded at all. The control comes first for
the reason it always does — if the model already behaves with no rule present, the rule is
**unearned**, and the runner exits without comparing anything and says so. Like the wording runner
it is a measurement, not a gate; only its offline controls run in continuous integration.

Nor whether any particular *phrasing* inside it earns its place. That one has a tool too:
[`WORDING-TESTS.md`](WORDING-TESTS.md) and [`wording_test.py`](wording_test.py) measure a candidate
sentence against a no-guidance control across repeated runs, and refuse to compare anything if the
control never exhibited the failure the sentence was written for. It is a measurement, not a gate —
the live arms are non-deterministic, so only its controls run in continuous integration.

Measured 2026-08-18 with the compliance runner, on the `handoff` skill's own never-mid-build rule:
its **prohibition half does nothing** — indistinguishable from having no rule at all — while the
half that describes the boundary and offers the alternative separates from the control decisively.
An emphatic sentence can be shipped, correct, and carried entirely by the clause after it.

Re-measured 2026-08-18 under a harder pressure, where the rule fails outright: the shipped guardrail
is **indistinguishable from having no rule at all** (p = 1.000, reproduced across two batches at 14 of
14 and 20 of 20). The obvious repair — delete the escape clause its responses kept quoting — was
measured and **does not work** (p = 0.48), so it was not shipped. A plausible wording change with a
visible mechanism, stopped by the only thing that could stop it.

**What does hold, measured the same day: a rule aimed at the ACT rather than the boundary.** Every arm
until then named a condition the model already identifies unprompted; the one that forbids *producing
the artifact* — including its shortened, provisional and labelled forms, which is what the shipped
rule's escape clause licenses — violated **0 of 20** against the shipped text's 20 of 20 (p =
1.5e-11). It is not an edit to the skill yet: it is single-turn, one model, and it drops a clause
the real workflow sometimes wants. **Four detector defects and one non-random rep loss were found on
the way there, every one of them by reading responses rather than by watching a verdict**, and every
one of them had been flattering the rule.

### The example skills describe tools that do not exist

The three skills under `examples/skills/` are fixtures. They are real files with real
frontmatter, so the lint and the eval have something to run against and the contract can be
pointed at rather than described — but the incident tooling they govern is imagined, and so is
every mechanism and test their `risk_factors` cites. Each is labelled an example on its own face,
and the one carrying the worked citation says plainly that the chokepoint and the test it names
are not in this repository — because a worked example of *not dressing an unverifiable claim as
evidence* must not be the first thing to do it. Substitute your own three parts; yours have to
resolve.

## Files

```text
CLAUDE.md.template       the always-on skeleton -- structure only, no content
check_pointer_file.py    the check that keeps it one, incl. --self-test
SKILL-FRONTMATTER.md     the frontmatter contract in prose, and why each field is there
skill-schema.json        the same contract as data -- profiles, required fields, your budget
lint_skills.py           holds a tree to the contract, incl. --self-test
check_lint_parity.py     gates the schema against the source repo's own hardcoded lint
lint-parity-exceptions.json
                         the deliberate differences between those two, each with its reason
eval_skills.py           measures triggering accuracy, incl. an offline --self-test
probes.example.json      a worked probe set: three neighbours, negatives aimed at each other
examples/skills/         three example skills the lint and the eval actually run against
WORDING-TESTS.md         how to measure a sentence before you ship it, with a worked result
wording_test.py          the runner: arms, reps, spread, incl. an offline --self-test
wording-test-example.json
                         the worked experiment -- fixture, banned strings, three arms
wording-test-result-2026-08-17.json
                         that experiment's raw counts and responses, replayable
COMPLIANCE-TESTS.md      how to find out whether a rule inside a skill is obeyed, with a baseline
compliance_test.py       the runner: arms, reps, isolation, incl. an offline --self-test
compliance-test-handoff-midbuild.json
                         the worked experiment -- mid-build fixture, three pressures, five arms
compliance-test-result-2026-08-17.json
                         that experiment's baseline: raw scores and every response, replayable
compliance-test-arms-2026-08-18.json
                         the five-arm run: control, the shipped rule, and three variants
compliance-test-handoff-midbuild-hard.json
                         the harder variant -- a fourth pressure that closes the refusal's escape
compliance-test-hard-2026-08-18.json
                         that run: the shipped rule failing 14 of 14, and the fix that did not work
compliance-test-handoff-midbuild-hard-act.json
                         the act-arm experiment -- same task and detectors, byte-identical and
                         asserted so; adds a rule that forbids PRODUCING the artifact
compliance-test-act-2026-08-18.json
                         that run: 20 reps an arm, the reps declared before buying them
compliance_test_multiturn.py
                         the same question under CUMULATIVE pressure: one conversation per rep,
                         scored by the RUNG it folded on. Imports both detectors rather than
                         copying them, incl. an offline --self-test
compliance-test-handoff-ladder.json
                         the five-rung ladder -- request, premise, close-escape, authority, and
                         the one a single message cannot send: settle for a partial
compliance-test-ladder-2026-08-18.json
                         that run. Its control arm's LIVE scores are known wrong -- read it with
                         --rescore, which is why every response is stored
compliance-test-handoff-midbuild-hard-escape.json
                         the clause pair: withhold against withhold WITH each half of guardrail 1's
                         escape clause restored. Generated from the act file, not retyped, so the
                         identity of task and detectors is asserted rather than claimed
compliance-test-handoff-ladder-escape.json
                         the same five arms on the ladder -- the instrument that answers it, because
                         on a rate withhold is at the floor and can only tie
compliance-test-escape-2026-08-18.json
                         that run: the offer-to-finish clause costs nothing, the labelled hand-off
                         costs the stop
compliance-test-ladder-escape-2026-08-18.json
                         the same on five rungs. Live scores reproduce exactly under --rescore
```

Every stored result file is **replayable and rescorable**. `--replay` re-reports one at its recorded
scores; `--rescore` re-detects the stored responses under the current rules, including reps a
previous rule discarded. **Five** detector defects have been corrected that way, none of them costing
a re-run — which is the only reason the corrections were made at all rather than deferred.

A **sixth** was found, measured, and deliberately left in place: `SECTION_RE` caps a bold run at 60
characters, so a longer document title contributes no structure line. Widening it across all 360
stored responses changes 6 scores and **0 verdicts**, so it has never decided an arm — and a detector
already corrected five times does not get re-tuned mid-experiment for something that changes nothing.
`COMPLIANCE-TESTS.md` §9 carries the measurement.

Scoring uses **three witnesses, and only the first is the score.** Form (`sections`) is the score;
explicit delivery and the substance hand-over are reported beside it. Where they disagree, the arm has
not resolved — that is the point of having more than one, since a single detector cannot tell you it
is wrong.

Python 3.8+. `check_pointer_file.py` and `check_lint_parity.py` are stdlib only — the parity gate
reads one side as text and the other as JSON, so it runs wherever Python does. The two skill
checks need PyYAML, because
frontmatter is YAML and a hand-rolled parser that disagrees with the real one about a quoted
colon would pass files the platform rejects. `eval_skills.py` additionally needs the Anthropic
SDK and an API key **only** for the half that calls a model; its coverage half and its entire
self-test run offline.
