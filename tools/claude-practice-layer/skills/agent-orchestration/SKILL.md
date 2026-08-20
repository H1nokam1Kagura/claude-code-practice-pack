---
name: agent-orchestration
description: >
  Split work across agents so that something is genuinely removed from the reviewer's view, and
  state what each role may NOT see before assigning it. Triggers: 'set up a subagent', 'split this
  across agents', 'fan this out', 'orchestrate these agents', 'who reviews the agent output',
  'design an auditor role', 'my judge agrees with everything', 'should the reviewer see the
  reasoning', 'how many reviewers do I need', 'two agents edited the same file'. Produces the role
  table with each role's exclusion, the panel composition with what varies between seats, the
  stopping and escalation gates the dispatcher holds rather than the prompt, and a disjoint
  write-scope assignment. Do NOT
  use it to decide whether one claim is true or to pick the check for it (use
  verification-before-claiming), to choose between two branch comparisons (use
  git-comparison-choice), to make a destructive step recoverable (use
  reversibility-before-destructive), or to write up where a session got to (use
  handoff-discipline).
metadata:
  # SET THESE BEFORE YOU ADOPT THE SKILL. They ship unassigned on purpose: this skill hands out
  # roles, and a governance block that invents an accountable owner is the first role it would
  # have assigned to somebody who never agreed to it.
  owner: unassigned — set this before you adopt it
  backup_owner: ""
  # CATALOGUE GOVERNANCE ONLY: the owner accepting that this belongs in the catalogue. It is not
  # an approval of any decomposition the skill recommends, and it authorises no agent to run.
  approved_by: unassigned — set this before you adopt it
  approval_date: "2026-08-19"
  review_date: "2026-11-17"
  sunset_date: ""
  # Scale, declared rather than assumed: 1 reads and recommends; 2 authors a step that changes
  # something, or writes a document a later reader will act on; 3 changes something itself.
  risk_tier: 2
  risk_factors: >
    It plans and recommends: it dispatches no agent, runs no judge and writes no file other than
    the decomposition itself. Two specific residual risks, and both fail in the flattering
    direction. The first is that a split it recommends MANUFACTURES the appearance of
    independence — same-family seats, or an auditor handed the drafter's reasoning — after which
    the panel's agreement is a correlated failure that is undetectable from inside the pool and
    reads exactly like consensus. The second is that its write-scope table is the only thing
    standing between two concurrently dispatched agents and a silent partial overwrite, which
    errors nowhere. The bounding mechanism is that neither product may be emitted incomplete: a
    role without a stated exclusion is not a role and is refused, a seat without a stated varying
    property is not a seat, and an overlap in the write-scope table is a blocking finding rather
    than something to coordinate at run time. The load-bearing half of that — that a judge built
    out of the thing it judges goes blind on the case that matters — is asserted in both
    polarities by tools/claude-authoring-toolkit/compliance_test.py, whose --self-test holds a
    control requiring that facts taken from the artifact's own prescribed section names detect the
    real violation NOT AT ALL, alongside the control requiring the independent witness to catch
    it.
  pii_handling: >
    None — it reads task descriptions, file paths and rubric text, and produces a role and
    write-scope table. It opens no records, no mail and no personnel data, and it does not read
    the artifacts the roles it plans would go on to handle.
  changelog_url: "https://example.invalid/agent-orchestration/history"
  eval_pass_rate: TBD
  eval_last_run: TBD
---

# agent-orchestration

A second agent is worth having for what it is not allowed to see, not for the work it does. Split
tasks and you get a pipeline with no guarantees, because every stage still sees everything the
stage before it produced — and a reviewer that has read the reasoning is evaluating the reasoning
rather than the artifact. The full argument, with the incidents behind each rule, is
`tools/claude-dev-practice/ORCHESTRATION.md`.

## Give every role its exclusion

Assign each role three things and treat the third as load-bearing: inputs, outputs, and **what it
must not see**. Across the canonical five — planner, drafter, executor, auditor, approver — the
exclusions are one rule applied five times: *no role evaluates an artifact it can also see the
making of.* The planner does not score the output. The drafter does not see the held-out criteria,
because drafting to the rubric is optimising the proxy. The executor does not turn its results into
a verdict; it fetches, and the auditor judges. The approver gets verdicts and a dissent summary,
never the full transcript.

**A role with no exclusion is not a role.** It is a paragraph in somebody else's prompt, and you
have paid orchestration overhead for a single-agent result. Refuse to emit it, and say why. The
role table and the exclusion column are `tools/claude-dev-practice/ORCHESTRATION.md`, section 1.

## The auditor contract

Four hard rules, and the first carries most of the value:

1. **Cold scoring.** The auditor receives the input artifact, the final output and the rubric.
   Nothing else — not the drafter's reasoning, not intermediate drafts, not the executor's working.
2. **One criterion per call.** Never a multi-criterion form-fill: earlier ratings bias later ones,
   and asking the model not to do that does not fix it.
3. **At least one seat from a different model family.** A single-family panel overstates quality,
   and the effect amplifies wherever output is revised and re-scored.
4. **"Insufficient information" is always available**, and a judge that never uses it is
   uncalibrated rather than strict.

Two corollaries. With several candidate drafts the auditor **selects one** — merging them can
produce something weaker than the best single draft and hides which draft was good. And the
free-text rationale is worth capturing but must never be an input to control flow.

Rule 1 is the one that feels wrong to implement, because a reasoning trace looks like helpful
context. It is not context; it is the argument's advocate. Implement all four in the harness rather
than in the auditor's prompt: if the auditor *could* read the trace and was asked not to, you have
a request, not a contract — see the dispatcher section below. Sources and the published evidence
are in `tools/claude-dev-practice/ORCHESTRATION.md`, sections 2 and 9.

## Compose the panel, do not just add seats

A reviewer adds coverage only to the extent its mistakes are uncorrelated with what is already in
the pool. Rank reviewers by what actually varies, and never gate on stated confidence: the ladder
and the measurement behind it are
`tools/claude-practice-layer/skills/verification-before-claiming/SKILL.md` and
`tools/claude-dev-practice/GIT-AND-REVIEW.md`, which own that claim.

What is specific to a panel: cross-family is structural rather than a garnish, because if every
seat shares lineage the self-preference is systemic and no vote reveals it — the correlated failure
is what produced the majority. A diverse small panel beats one larger judge, which inverts the
instinct to reach for a stronger model. And two same-family seats must differ in their rubric, or
they are one seat with extra cost.

Tier the resolution by stakes rather than by confidence: a majority vote for low-stakes
categorisation, weighted aggregation of heterogeneous reviewers for scoring, a mandatory human for
a recommendation. Debate rather than voting earns its cost only on contested, evidence-weighted
questions — never on *is this number correct*, which has a cheaper answer higher up the ladder.
Written out in `tools/claude-dev-practice/ORCHESTRATION.md`, section 3.

**Write down what varies between each pair of seats before adding a seat.** If the answer is the
temperature, you have added cost and the appearance of a panel.

## Let the judge say "insufficient information"

Make the honest answer representable in the schema and in storage, so it cannot be coerced into a
number on the way to disk. This is the outcome vocabulary the rest of this layer already runs on,
arriving on a judged surface: it ran and found nothing wrong; it was not run; **it ran and measured
nothing.** The third is a failure, not a quiet success — `tools/Test-PracticeClaims.ps1` refuses to
let it pass as the first, keeps it on a different exit code from a check deliberately declined, and
carries a self-test for it, because a check that resolved no candidates and a clean tree produce
identical output.

The judged equivalent of that third state is *insufficient information*. Treat a zero rate of it
across a corpus as a finding about the harness, not as evidence the artifacts were complete: sample
the ones that got a full set of numbers and ask whether they deserved one. The mapping is a table
in `tools/claude-dev-practice/ORCHESTRATION.md`, section 4.

## Never build the judge out of the thing it judges

The strongest evidence in this layer, and it is unflattering.
`tools/claude-authoring-toolkit/COMPLIANCE-TESTS.md` records a detector being wrong five separate
times, each correction bought with a full revalidation. The first version counted the section names
the artifact under test prescribes — names the *rule* supplies — so it was blind in the control arm
and sighted in the treatment arm, and therefore biased towards finding the rule effective. It
reported the rule unearned while every response had violated it. The replacement had the same
defect one level down: it stopped depending on what sections were called and went on depending on
how they were spelled.

**All five errors leaned the same way: a violation read as a compliance, which makes a rule look
better than it is.** Three rules follow.

- **Build the discriminator from something neither side supplies.** The witness that resolved the
  hard case in `tools/claude-authoring-toolkit/compliance_test.py` takes its facts from a fixture
  identical across every arm, so no arm can move the number by obeying or disobeying a wording.
- **Start with a control and let it stop you.** If the run with no skill and no rule does not
  violate, the rule is unearned and the treatment arms should not run.
- **A judge is not reproducible by somebody who does not trust you**, and the first thing a change
  to the rule under test would move is the judge. Prefer a deterministic witness where one exists,
  and report a judged axis *beside* the score rather than folding it in — folding it in legislates
  a design question inside a detector, where nobody can see the decision being made.

Where disagreement is available, make it a test rather than a habit:
`tools/claude-permission-toolkit/check_interpreter_parity.py` and
`tools/claude-authoring-toolkit/check_lint_parity.py` gate two independent implementations of one
question against each other. Keep the copies, gate the copies —
`tools/claude-dev-practice/TESTING-DISCIPLINE.md`, section 6.

## Put the stop in the dispatcher, not the prompt

An instruction to stop, escalate or stay in budget, placed in an agent's prompt, is something the
model can reason past — and in a multi-agent run it will, because that instruction is competing
with a task the agent believes it is meant to finish. Anything you have to remember to say is not
configured, and orchestration is where that bites hardest because there is no single conversation
to say it in: `tools/claude-dev-practice/CODING-WITH-CLAUDE-CODE.md`, section 2.

So enforce outside the model. A hard cap on revision rounds. A similarity flag on adjacent outputs,
which is what step repetition looks like. A stopping predicate the orchestrator evaluates each turn
and that must pass before any exit. An audit of the tool call against the stated intent, which is
the only way a reasoning-and-action mismatch surfaces. A token budget the orchestrator holds rather
than one requested in a prompt. And a threshold above which the dispatcher **refuses to execute**
until a person clears it — an escalation begged for in a prompt with no gate anywhere is the
commonest form of this failure.

Two additions from measured experience, both in
`tools/claude-authoring-toolkit/COMPLIANCE-TESTS.md`. Do not let the pressure recite the rule: a
runner there refuses to start if a rung of its escalation ladder names the condition the rule
names, because an arm that then complies is being credited for obeying an instruction it was read
out. And assert the chain between turns rather than assuming it — a silently broken chain makes
every turn arrive fresh, and a rule that never accumulates pressure survives longer, so the run
reports deeper compliance than it measured. A broken link between agents flatters the result.

## Size the fan-out to triage, and distrust a branch that lost work

An agentic review produces a candidate list, not a defect list, and the count is an upper bound to
be triaged rather than a workload — `tools/claude-dev-practice/GIT-AND-REVIEW.md` owns that claim
and the reduction that demonstrates it. The orchestration consequence: **the constraint is triage
capacity, not agent capacity.** Adding agents multiplies candidates and does nothing to the hours
available to adjudicate them, and an undrained queue is indistinguishable from no review at all
within a quarter. Layer the cheapest signal first — deterministic pre-score, then a small
calibrated panel on what survives, then a person on the genuine residual.

**Any path that can drop a unit of work is a selection effect until proven otherwise, and it will
not favour you.** A harness that lost responses to a decoding fault banked them as unscoreable and
exited successfully, and the loss was not random: the responses carrying unusual characters were
disproportionately the violations, so the arm that shed them read as the obedient arm. Recorded, with
the split, in `tools/claude-authoring-toolkit/COMPLIANCE-TESTS.md`. Count harness losses separately
from genuine non-answers; name differential attrition and then refuse to read the rates; and treat
zero findings from an agent that crashed, timed out or was cut off as a failure rather than a pass.

## One file, one writer

The most reliable practical failure in a fan-out is mundane: two agents were given overlapping write
scope, both edited one file, and the second silently reverted part of the first. Nothing errors — the
tree is simply wrong in a way that reads as somebody's intent. Shared-state hazards across sessions
and the general fix of separate trees per task are
`tools/claude-dev-practice/GIT-AND-REVIEW.md` and `tools/claude-worktree-toolkit/README.md`.

The part that belongs to the decomposition: **write ownership is assigned up front, and a file has
exactly one writer.**

- **Assign paths, not topics.** A topic assignment ends with two agents editing the same prose.
  Name the paths each subtask may write and make the sets disjoint; where a shared registry must
  change from two directions, the narrow edit naming only its own document is what makes the
  concurrency survivable — the per-document, per-section shape in
  `tools/practice-gate/sourcing.json` is the worked form.
- **If two agents must genuinely produce the same artifact, gate it rather than merge it.** Keep
  both products and make their disagreement a finding.
- **One artifact, one owner, cross-checked in both directions.** Where two consumers read one
  table, prefer a single table read twice with a check that the readers agree over a copy per
  reader. `tools/Build-SharePack.ps1` was built that way deliberately: its staging step was lifted
  out of the gate that held the other copy rather than added beside it.
- **Do not plan to recover with a session rewind.** Its coverage limits are stated, dated and
  pinned in `tools/claude-dev-practice/REVERSIBILITY.md` and
  `tools/claude-dev-practice/VERIFIED-AGAINST.md`; read them there rather than from memory, and do
  not accept a restatement — including from this skill, which deliberately gives none. Restating an
  undated harness fact is how one of those claims went false on the page in the first place.

Produce the write-scope table before dispatching anything, and treat an overlap in it as a blocking
design finding. The discipline for the mutating step itself is
`tools/claude-practice-layer/skills/reversibility-before-destructive/SKILL.md`.

## What it does not do

It does not run agents, dispatch anything, or execute a judge — it produces the decomposition and
the gates, and a person or a harness acts on them. It cannot tell you whether a rubric is any good,
only whether it is scorable from the transcript and whether the roles around it can see too much.
It does not certify independence: it states what varies between two seats, and a stated difference
that happens to produce correlated errors anyway will still read as consensus. And most of the
research behind sections 1 to 4 of `tools/claude-dev-practice/ORCHESTRATION.md` was not measured in
this repository — that document marks the borrowed figures as its weakest-evidenced part and dates
when each arrived, which is the standard to hold this skill to as well.
