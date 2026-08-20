# Orchestration

Splitting work across more than one agent. Not the capability half — the routing half: who may see
what, who is allowed to score whom, and what a second agent's output is worth before anybody reads
it.

> **A second agent earns its keep for what it is not allowed to see, not for the work it does.**

The rest of this pack assumes one agent and builds checks around it. The failures here are different
in kind. They are almost all failures of **information routing** rather than of reasoning, and they
present as agreement — which is the one signal a reviewer is least likely to interrogate.

Deeper dives: [CODING-WITH-CLAUDE-CODE.md](CODING-WITH-CLAUDE-CODE.md) ·
[GIT-AND-REVIEW.md](GIT-AND-REVIEW.md) · [TESTING-DISCIPLINE.md](TESTING-DISCIPLINE.md)

---

## 0. Where this document ends and the review document begins

These two overlap on purpose and must not restate each other. The repo's standing rule is that
where a claim travels in two documents, **one is the source and the other points** — the same rule
`tools/claude-permission-toolkit/check_interpreter_parity.py` enforces on duplicated *code*, and the
same reason: two copies agree until somebody edits one of them.

| Claim | Owner | This document's part |
|---|---|---|
| Independence means uncorrelated errors; the reviewer ladder | [GIT-AND-REVIEW.md](GIT-AND-REVIEW.md) §4 | How to compose a panel so that something actually varies between the seats (§3) |
| Confidence is not accuracy, and can invert | [GIT-AND-REVIEW.md](GIT-AND-REVIEW.md) §4 | Nothing. Read it there |
| An agentic review's finding count is an upper bound, not a workload | [GIT-AND-REVIEW.md](GIT-AND-REVIEW.md) §5 | The budgeting consequence, and the attrition trap beside it (§7) |
| The working tree is shared state across sessions | [GIT-AND-REVIEW.md](GIT-AND-REVIEW.md) §3 | Write ownership at assignment time (§8) |
| Role separation, the auditor contract, cold scoring | **Here** (§§1–5) | — |
| What a session rewind does and does not restore | [REVERSIBILITY.md](REVERSIBILITY.md) §4, dated and pinned in [VERIFIED-AGAINST.md](VERIFIED-AGAINST.md) | Nothing. Deliberately not restated here — see §8 |

The pointer is one-directional today: this document names the review document as the source of the
independence ladder, and that document still sends a reader to the harness skill rather than here.
Recorded rather than quietly left, because an unstated asymmetry in a cross-reference is how two
documents start drifting.

---

## 1. A role is a decomposition of what may be seen, not of labour

The instinct when splitting work is to split *tasks* — one agent researches, one writes, one checks.
That produces a pipeline and no guarantees, because every stage still sees everything the previous
stage produced, and a reviewer that has read the reasoning is evaluating the reasoning rather than
the artifact.

The design that holds up assigns each role three things and treats the third as the load-bearing
one: its inputs, its outputs, and **what it must not see**. The five-role decomposition — planner,
drafter, executor, auditor, approver — is worked out with the exclusion for each in
`skills/eval-harness-domain/SKILL.external.md`, Procedure 1. The exclusions are the interesting
column:

| Role | Must not see, or must not do |
|---|---|
| Planner | Must not score the output. The planner never judges its own plan |
| Drafter | Must not see the held-out scoring criteria. Drafting to the rubric is optimising the proxy |
| Executor | Must not interpret its results as a verdict. It fetches; the auditor judges |
| Auditor | Must not see the drafter's reasoning or its intermediate drafts (§2) |
| Approver | Must not see the full transcript — verdicts and a dissent summary only |

Read down that column and the pattern is one rule applied five times: **no role evaluates an
artifact it can also see the making of.** It is the same rule as *do not let it grade its own
homework* in [CODING-WITH-CLAUDE-CODE.md](CODING-WITH-CLAUDE-CODE.md) §1, moved from the reviewer to
the plumbing — and moving it is the point, because a reviewer can be reminded and plumbing cannot
forget.

**What to do.** Before assigning any subtask, write the exclusion. If a role has none, it is not a
role, it is a paragraph in somebody else's prompt, and you have bought orchestration overhead for a
single-agent result.

---

## 2. The auditor contract is the highest-leverage part, and the first rule is most of it

Four hard rules, quoted as constraints rather than advice, from
`skills/eval-harness-domain/SKILL.external.md` Procedure 1 (R4). Get these right and downstream
quality follows; get them wrong and everything downstream is laundered — it scores well and means
nothing.

1. **Cold scoring.** The auditor receives the input artifact, the final output, and the rubric.
   Nothing else. Not the drafter's reasoning, not intermediate drafts, not the executor's working.
2. **One criterion per call.** Each rubric dimension is scored in a separate call. Never a
   multi-criterion form-fill, because earlier ratings in a sequence bias later ones and asking the
   model nicely not to do that does not fix it.
3. **At least one seat from a different model family.** A single-family panel overstates quality,
   and the effect amplifies in any loop where the output is revised and re-scored.
4. **"Insufficient information" is always available.** The auditor must never manufacture a score
   to complete a form (§4).

Rule 1 carries most of the weight and it is the one that feels wrong to implement, because the
reasoning trace looks like helpful context. It is not context, it is the argument's advocate. The
published result behind it is in §9; the version of it this repository has actually *measured* is in
§5, and it points the same way.

Two corollaries worth having as rules of their own:

- **Selection beats synthesis.** With several candidate drafts, the auditor **picks one**. Merging
  them can produce an output weaker than the best single draft, and the merge hides which draft was
  good. Same source, Procedure 1.
- **Separate the rationale channel from the score.** Free-text reasoning is worth capturing and must
  not be an input to control flow. A judge that reasons its way to a number in the same field tends
  to collapse the distribution.

**What to do.** Implement the exclusion in the harness, not in the auditor's prompt. If the auditor
*could* read the drafter's trace and is asked not to, you have a request; if it was never passed,
you have a contract. That distinction is the whole of §6.

---

## 3. Independence is a property of the panel, not of the seat

Adding a reviewer adds coverage only to the extent its mistakes are uncorrelated with the mistakes
already in the pool. The ladder, and the measurement that two independently *authored* checks
disagree on first run where two generated from one prompt would have agreed, belong to
[GIT-AND-REVIEW.md](GIT-AND-REVIEW.md) §4 and are not restated here. What that section does not
cover is composition — how to build a pool of several judges rather than choose one reviewer.

Three composition rules, all from `skills/eval-harness-domain/SKILL.external.md` Procedures 3 and 4:

- **Cross-family is structural, not a garnish.** If every seat shares lineage, self-preference is
  systemic and *undetectable from inside the pool* — there is no vote that reveals it, because the
  correlated failure is what produced the majority.
- **A diverse small panel beats one larger judge.** Which inverts the intuition that the way to a
  better verdict is a stronger model.
- **Vary the rubric between same-family seats.** Two seats of one model on one rubric are one seat
  with extra cost.

And one rule about the shape of the disagreement, which matters more than the count: tier the
resolution by stakes. Majority vote for low-stakes categorisation; weighted aggregation of
heterogeneous reviewers for scoring; a mandatory human for a recommendation, regardless of
confidence. Debate rather than voting earns its cost only on contested, evidence-weighted questions
— never on *is this number correct*, which has a cheaper answer at the top of the ladder in
[GIT-AND-REVIEW.md](GIT-AND-REVIEW.md) §4.

**What to do.** Write down what varies between each pair of seats before you add a seat. If the
answer is "the temperature", you have added cost and the appearance of a panel.

---

## 4. "Insufficient information" is a verdict, and this repo already enforces its twin

A judge asked to score a dimension the artifact does not address will usually produce a number
anyway. The fix is to make the honest answer *representable*, in the schema and in the storage —
`skills/eval-harness-domain/SKILL.external.md` Procedure 8 makes the score column nullable
specifically so the verdict cannot be coerced into a number on the way to disk.

This is the same rule the rest of this pack already runs on, arriving on a judged surface. The
outcome vocabulary in `tools/claude-practice-layer/skills/verification-before-claiming/SKILL.md` has
three values, not two: it ran and found nothing wrong; it was not run; it ran and measured nothing.
`tools/Test-PracticeClaims.ps1` refuses to let the third pass as the first — zero candidates is a
failure there, deliberately, and "I chose not to run this" and "it ran and measured nothing" are
given different exit codes because they are different states. It carries a self-test for that case,
because a check that resolved no candidates and a clean tree produce identical output.

The mapping is exact, and worth stating because it means the judged case needs no new principle:

| Deterministic check | Judged dimension |
|---|---|
| It ran and found nothing wrong | A score, with evidence references |
| It was deliberately not run | Dimension out of scope for this artifact |
| It ran and measured nothing | **Insufficient information** |

A judge that never returns the third value is not a strict judge, it is an uncalibrated one, and the
symptom is a suspiciously complete scorecard. Sample the artifacts that got a full set of numbers
and check whether they deserved one.

**What to do.** Make the verdict expressible before you tune the prompt, and treat a zero rate of
"insufficient information" across a corpus as a finding about the harness.

---

## 5. Never build the auditor out of the thing it audits

This is the section with the strongest in-repo evidence in this document, and it is unflattering.

`tools/claude-authoring-toolkit/COMPLIANCE-TESTS.md` §6 records a detector — the judge in a
behavioural harness — being wrong **five separate times**, each correction bought with a full
revalidation. The first version counted the section names the skill under test prescribes. Those
names are what the *skill* supplies, so a run without the skill wrote the same artifact under names
of its own and scored zero: **blind in the control arm, sighted in the treatment arm, and therefore
biased towards finding the rule effective.** It reported the rule as unearned while all seven
responses had in fact violated it.

The replacement had the same defect one level down — it stopped depending on what the sections were
called and went on depending on how they were *spelled*. Then a third correction, a fourth, a fifth,
the fifth introduced by a correction, in the arm whose whole job was to be unflattering.

The line to take from it is in that document and is more useful than the individual bugs:

> **All five errors leaned the same way — a violation read as a compliance, which makes a rule look
> better than it is.**

Three transferable rules follow, all sourced to the same document:

- **Build the discriminator from something neither side supplies.** The third witness in
  `tools/claude-authoring-toolkit/compliance_test.py` takes its facts from a fixture that is
  byte-identical across every arm, so no arm can move the number by obeying or disobeying a wording
  — only by reproducing or withholding the state.
- **Start with a control and let it stop you.** If the run with no skill and no rule does not
  violate, the rule is unearned and the treatment arms should never run. That is an exit path in the
  runner, not a paragraph of advice.
- **A judge is not reproducible by somebody who does not trust you**, and the first thing a change
  to the rule under test would move is the judge. Where a deterministic witness is available, prefer
  it and report the judged axis *beside* the score rather than folding it into the score — because
  folding it in legislates a design question inside a detector, where nobody can see the decision
  being made.

There is a stronger form of the last one that costs almost nothing when disagreement is available:
make it a test. `tools/claude-authoring-toolkit/check_lint_parity.py` and
`tools/ci/check_workflow_parity.py` gate two independent implementations of one contract against
each other, and `tools/claude-permission-toolkit/check_interpreter_parity.py` earned its keep by
being red on run one. The general argument is [TESTING-DISCIPLINE.md](TESTING-DISCIPLINE.md) §6:
**keep the copies, gate the copies.**

---

## 6. Control is architectural; a prompt asking for it is a suggestion

An instruction to stop, escalate or stay in budget, placed in an agent's prompt, is a thing the model
can reason past — and in a multi-agent run it will, because the prompt is competing with a task the
agent believes it is supposed to finish. The published failure taxonomy attributes most multi-agent
failure to system design and inter-agent misalignment rather than to capability (§9), which is the
same conclusion in aggregate.

This pack's own version of it is [CODING-WITH-CLAUDE-CODE.md](CODING-WITH-CLAUDE-CODE.md) §2:
**anything you have to remember to say is not configured.** Orchestration is where that bites
hardest, because there is no single conversation to say it in.

So enforce at the dispatcher, outside the model. The mechanisms, from
`skills/eval-harness-domain/SKILL.external.md` Procedure 6:

| Failure mode | What you will see | Enforcement, not instruction |
|---|---|---|
| Step repetition | Adjacent outputs nearly identical; the same tool call re-issued | Similarity flag (cosine above 0.95) plus a hard cap of three revision rounds |
| Unaware of the stopping condition | The agent continues past the goal, or asks what is next | A termination predicate the orchestrator evaluates each turn and that must return a pass before any exit |
| Reasoning-and-action mismatch | The stated plan and the executed tool call diverge | Audit the tool call against the stated intent, not just the prose |
| Unbounded spend | Nothing, until the bill | A token budget the orchestrator holds; never one requested in a prompt |
| Escalation that never happens | "If unsure, escalate to a human" in a prompt and no gate anywhere | The dispatcher refuses to execute above-threshold work until a human clears it |

Two additions from this repository's own experience with the same shape:

- **Do not let the pressure recite the rule.** `tools/claude-authoring-toolkit/COMPLIANCE-TESTS.md`
  §8 records a multi-turn runner that *refuses to run* if a rung of the escalation ladder names the
  condition the rule names — because an arm that then complies is being credited for obeying an
  instruction the user read out to it. The same trap is available to any orchestrator that passes
  the rubric to the drafter.
- **Assert the chain rather than assuming it.** In the same section, a silently broken conversation
  chain would have made every turn arrive as a fresh first turn — and a rule that never accumulates
  pressure survives longer, so the run would have reported *deeper* compliance than it measured. A
  broken link between agents flatters the result.

Aim for an escalation rate inside a band rather than at zero. Both ends carry information: too high
and the reviewers are rubber-stamping, too low and errors are passing. The source names a band; the
number matters less than having one.

---

## 7. Budget the output before you read it, and distrust any path that drops a finding

An agentic review produces a candidate list, not a defect list, and the gap between the two is
larger than people plan for. That claim, its two compounding causes and the measured reduction of one
triage queue are owned by [GIT-AND-REVIEW.md](GIT-AND-REVIEW.md) §5 and are not restated here. Two
things belong to orchestration specifically.

**The constraint is triage capacity, not agent capacity.** Adding agents multiplies candidates and
does nothing to the human hours available to adjudicate them, so a fan-out sized to what the agents
can produce produces a queue nobody drains — and an undrained queue is indistinguishable from no
review at all after a quarter. Layer the cheapest signal first: a deterministic pre-score, then a
small calibrated panel on what survives, then a person on the genuine residual. The layering, and a
worked reduction, are in [GIT-AND-REVIEW.md](GIT-AND-REVIEW.md) §4.

**Any path that can drop a unit of work is a selection effect until proven otherwise, and it will
not favour you.** This one is measured here rather than borrowed.
`tools/claude-authoring-toolkit/COMPLIANCE-TESTS.md` §7 records a harness that lost responses to a
decoding fault and banked them as unscoreable, exiting successfully. The loss was not random: on an
aborted run, none of 20 control responses were lost against 3 of the first 5 in a treatment arm,
because the responses carrying unusual characters were disproportionately the *documents* — that is,
the violations. An arm that quietly sheds its violations reads as the obedient arm.

Three rules follow, and they generalise to any fan-out where a subagent can fail to return. The
first two are that document's own; the third belongs to the gate beside this one:

- **Count harness losses separately from genuine non-answers.** In one bin, "three units unusable"
  describes your plumbing while sounding like it describes the model.
- **Name differential attrition and then refuse to read the rates.** If the branches did not lose
  the same number of units, the between-branch comparison is untrustworthy whatever it says.
- **A returned-nothing is not a returned-no.** Zero findings from an agent that crashed, timed out
  or was cut off is not a pass. `tools/Test-PracticeClaims.ps1` treats zero candidates as a failure
  rather than a clean run for exactly this reason, and has a self-test for it.

---

## 8. Two agents writing one file is a design defect, not a merge problem

The most reliable practical failure in a fan-out is mundane: two agents were given overlapping write
scope, both edited the same file, and the second silently reverted part of the first — or the run
ended with a file neither agent's plan describes. Nothing errors. The tree is simply wrong in a way
that reads as somebody's intent.

Multi-session shared-state hazards, and the general fix of separate trees per task, are
[GIT-AND-REVIEW.md](GIT-AND-REVIEW.md) §3 and `tools/claude-worktree-toolkit/README.md`. The
orchestration-specific half is narrower and belongs here: **write ownership is assigned at
decomposition time, and a file has exactly one writer.**

- **Assign files, not topics.** "You handle the citations registry" is a topic and two agents will
  both edit prose. Name the paths each subtask may write, and make the sets disjoint. Where the
  registries beside this document need changes from two directions, the narrow edit that names only
  its own document — as `tools/practice-gate/sourcing.json` records per document and section — is
  what makes concurrent edits survivable.
- **If two agents genuinely must produce the same artifact, do not merge it — gate it.** That is the
  parity pattern in §5 turned into a work assignment: keep the two products and make their
  disagreement a finding. `tools/claude-permission-toolkit/check_interpreter_parity.py` is the
  worked form.
- **One artifact, one owner, cross-checked in both directions.** Where two consumers must read one
  table, the safe shape is a single table read twice with a check that the readers agree, rather
  than a copy per reader. `tools/Build-SharePack.ps1` was built this way deliberately: its staging
  step was *lifted out of* the gate that used to hold a second copy, rather than added beside it.
- **Do not plan to recover with a session rewind.** Its coverage limits are stated, dated and pinned
  in [REVERSIBILITY.md](REVERSIBILITY.md) §4 and [VERIFIED-AGAINST.md](VERIFIED-AGAINST.md), and
  this document deliberately does not restate them — restating a harness fact without its date is
  how one of them went false on a neighbouring page. **Go and read the answer for the kind of
  change your agents actually make before you rely on it**, and note that nothing in this document
  will tell you what it is: an undated restatement here would be invisible to the check that dates
  these claims, which is worse than an absence.

**What to do.** Produce the write-scope table before dispatching anything, and treat an overlap in
it as a blocking design finding rather than something to coordinate around at run time. The rest of
the discipline for a mutating step — dry run, run identifier, readback, rollback — is
`tools/claude-practice-layer/skills/reversibility-before-destructive/SKILL.md`, and the proof shape
it depends on is `tools/claude-memory-toolkit/tests/safety_test.py`.

---

## 9. What is borrowed here and not measured here

Sections 1–4 and 6 rest substantially on published research transcribed into
`skills/eval-harness-domain/SKILL.external.md`, whose reference list names each result. **None of
those figures was re-measured in this repository, and this section is the weakest-evidenced part of
this document — hold it to that standard**, exactly as
[CODING-WITH-CLAUDE-CODE.md](CODING-WITH-CLAUDE-CODE.md) §6 asks for its own unsourced section.

The dates below are when each figure entered this repository, **not** when it was measured; the
measurement dates belong to the papers, which the source file cites and this one does not re-cite.

| Figure | About | In this repository since |
|---|---|---|
| 48% → 76% judge accuracy | Showing a judge only the argument, never the private reasoning — the evidence for cold scoring (Khan et al., ICML 2024) | 2026-06-19 |
| 22–61% of judgments shift | Irrelevant anchors in sequential rating; the evidence for one criterion per call | 2026-06-19 |
| ~25% inflation | A panel judging its own family; the evidence for a cross-family seat | 2026-06-19 |
| 41–87% failure, ~42% of it from system design | Multi-agent failure taxonomy; the evidence that §6 is governance rather than capability | 2026-06-19 |
| 78% precision | Detecting gaming via rotated prompts and injected distractors | 2026-06-19 |
| 9.4% and 15.6% | Gains from role-spec clarity and from adding an objective verifier — the two things worth spending effort on | 2026-06-19 |

Three further limits, stated rather than left for a reader to infer:

- **Model tiering is a real lever and its specifics rot fastest.** Which model belongs on the
  planner, the executor and the panel is worked out in the source file, and every identifier in that
  table has a shelf life. Resolve it there against current model information rather than carrying a
  remembered assignment — the standing rule about never quoting a volatile figure from memory
  applies to model names too.
- **No orchestrator runs in this repository.** §§1–4 describe a shape; what is *implemented* here is
  the single-agent behavioural harness of §5 and §7. Where a claim in this document has an in-repo
  path beside it, that path is the evidence; where it does not, the evidence is the source file and
  the paper behind it.
- **The two calibration disciplines this document does not cover** — a held-out adversarial corpus,
  and periodic human scoring of a random sample with an agreement statistic — are the parts that
  tell you whether any of the above is working on your material. They are Procedures 4 and 7 of
  `skills/eval-harness-domain/SKILL.external.md`. Omitted here because a summary of a calibration
  programme is worse than a pointer to one: it reads as sufficient.
