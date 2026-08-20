# Git and review

Two halves of one problem: deciding **what changed**, and deciding **whether it is right**. Both
are places where a tool answers confidently and the answer inverts on a detail nobody looked at.

> **A tool that answers the wrong question answers it just as confidently as the right one.**

Almost none of this is CI/CD. CI tells you whether a known check passed; nothing here is a known
check, which is why these keep being rediscovered.

---

## 1. Name the question before you choose the comparison

Every "what changed?" has more than one defensible answer, and picking the wrong one produces a
number rather than an error.

Two questions that look identical and are not:

| Question | What it needs |
|---|---|
| *What did this author change?* | The branch's own commits, measured from where it diverged |
| *What would merging add that base does not already have?* | A direct comparison against base as it stands now |

Ask the first when reviewing authorship. Ask the second when deciding **keep or delete** — and note
that they fail in *opposite* directions. Measured from where a branch diverged, already-landed work
reads as this branch's contribution; compared directly, other people's newer commits read as a
revert by this branch. Neither errors.

**Worked instance, 2026-08-15.** The same branch at the same moment: one comparison reported 24
files and 3,815 insertions, the other 13 files and 1,225. The second was correct — the first was
counting content that had already landed under a different commit, because the PR carrying it had
been **squash-merged**, and a squashed branch is not an ancestor of the base it landed in.

That last point deserves its own line, because it breaks the cheapest check people reach for:

> After a squash-merge, *"is this commit an ancestor of base?"* and *"is this commit's content in
> base?"* have different answers. The first says no. The content is there.

**What to do.** Write the question in words before running anything. On a keep-or-delete decision,
run both comparisons and reconcile the gap — a disagreement is the finding, not noise. Where
evidence is only sufficient and not necessary, report the weaker verdict:
`_Wt-BranchSuperseded` in `tools/claude-worktree-toolkit/wt.ps1` returns `null` rather than `false`
for a ref it cannot resolve, because "unknown" collapsing into "no" is how a false negative gets
manufactured.

And know what your merged-ness test cannot see. Patch-id matching compares **per-commit** patches,
and a squash collapses the branch into one commit whose patch is the union of all of them — so it
matches in exactly one case: **the branch held a single commit**. Two things are therefore invisible
to it, and neither is exotic: a multi-commit branch squashed as itself, and content squashed into a
*different* change alongside other work. Either way the patch-ids never match, so the branch reports
unmerged forever even though every line of it has landed.

That failure is safe — it keeps a dead tree rather than deleting a live one — but it must be stated,
or the verdict gets trusted past its range. It is worth being precise about *which* case works,
because "it catches a whole-branch squash" is the intuitive summary and it is wrong in the
reassuring direction: a whole-branch squash of a multi-commit branch is exactly what it misses.

---

## 2. A successful operation is not evidence that anything moved

Separate *"the command exited 0"* from *"the target now differs."* Almost every expensive failure
here is an operation that honestly reported doing what it was asked, where what it was asked was
not what you meant.

**The empty change.** Creating a branch pointer does not switch to it. Commits keep landing on
whatever is checked out; the push then ships the stale pointer, which is a no-op that prints
nothing alarming. Each subsequent change re-proposes the previous one's content: checks pass, the
merge reports success, and **nothing lands.** It ran for three cycles before anyone noticed. The
tell is several squashed commits on base sharing one title, because the title is derived from
identical content.

**The absorbed commit.** Branching from a local default that is *behind* origin, or merging while a
local default is *ahead*, lets a squash quietly swallow work you had not pushed. Nothing conflicts,
because there is nothing to conflict with.

**The vanished branch.** A merge configured to delete its branch removes the remote ref. A later
push to that name reports `[new branch]` and succeeds — creating a *resurrection* rather than
adding to the thing you thought was still open. Seen twice in one session, 2026-08-15; the
`[new branch]` line was the only signal either time.

**Prevent the first two by construction rather than by care.**
`tools/claude-worktree-toolkit/wt.ps1` creates every branch from `origin/<base>` rather than from
whatever the local default happens to be, which removes the absorbed-commit trap entirely — there
is no stale local pointer to branch from. And when the fetch that keeps `origin/<base>` current
fails, it *says so* and names the consequence rather than proceeding quietly against a stale ref.
A guard that degrades loudly is the difference between a known risk and a silent one.

**What to do about the rest.** Assert the delta, not the exit code:

```
after a push    remote ref == local HEAD?
after a merge   is the content reachable from base?  (content, not ancestry -- see §1)
before a PR     do both comparisons agree on what this adds?
```

Treat an unexpected `[new branch]`, or an unexpected *absence* of conflict, as a full stop. Those
are the two places the system tells you your model of the world is wrong, and both read as success.

---

## 3. The working tree is shared state

Any of this applies the moment more than one session, or more than one tree, touches a repository.

- **Parallel sessions share one tree.** Files change under you mid-task. Anything destructive that
  assumes the tree is as you last saw it — a checkout over a modified file, a reset — can discard
  another session's uncommitted work. Re-read immediately before, not once at the start.
- **A stale checkout manufactures confident false absences.** An old worktree or a default branch
  behind origin will report a file "missing", work "unfinished", or a fix "about to be
  reintroduced" — all of them wrong, all of them plausible. Fetch first. Suspect the checkout when
  a validator reports *"everything except one thing."*
- **Version-controlled build outputs follow the checked-out branch.** Any publisher that reads from
  a path rather than from a ref will happily ship whichever vintage happens to be on disk.

Reduce this by construction rather than by care: separate trees per task, and settings that enforce
what you would otherwise have to remember — prune on fetch, fast-forward-only pulls, delete the
branch on merge. See `tools/claude-worktree-toolkit/README.md` for the workflow this assumes.

---

## 4. Independence means uncorrelated errors, not a fresh window

The review half, and the distinction the phrase "second opinion" hides.

Two checks are worth gating against each other **only to the extent their mistakes are
independent.** A fresh context removes contamination from the conversation that produced the work.
It does nothing about correlation in the reviewer itself: two implementations from the same model
share priors, so they agree — confidently, and sometimes wrongly. You get the comfort of agreement
without the coverage that makes agreement mean anything.

Rank reviewers by what actually varies between them:

| Strength | Reviewer | What varies |
|---|---|---|
| Strongest | A deterministic assertion | Nothing is shared — there is no judgement to correlate |
| | A differently-*authored* implementation | Independent reasoning, independent blind spots |
| | A different model | Different training, partially correlated |
| | The same model, fresh context | Contamination removed, priors identical |
| Weakest | The same model, same context | The context that made the error evaluates the error |

`tools/claude-permission-toolkit/check_interpreter_parity.py` is the second row, and it earned its
keep by being **red on its first run**: two independently written detectors of the same property
disagreed, and each had found something the other missed. That result is a property of them having
been written separately. Two generated from one prompt would very likely have agreed with each
other and been wrong together.

**Confidence is not accuracy, and is sometimes inversely related.** Measured on one extraction
corpus, the two dimensions carrying the *highest* self-reported confidence were the least accurate.
So never gate a promotion on a model's stated confidence — gate on **measured per-dimension
reliability** against a labelled sample. See `skills/eval-harness-domain/SKILL.md` for the panel and
calibration design, and `skills/eval-harness-code/SKILL.md` for the same applied to pipelines.

**Layer the cheapest signal first.** Deterministic pre-score, then a small calibrated panel on what
survives, then a human on the genuine residual only. Done this way, one queue of 730 provisional
items reduced to 54 needing human judgement (2026-07-10), with every remaining item traceable to
why it was still ambiguous.

---

## 5. Budget for inflation before you read the findings

An agentic review does not produce a defect list. It produces a **candidate** list, and the two
differ by more than people plan for.

Two effects, and they compound:

- **Most surfaced defects are not defects.** The reviewer does not know which hazards the project
  has already guarded, so it re-reports them. The continued existence of a working guard is a PASS.
- **Where the finding is real, the magnitude overstates the fixable part** — by one to two orders of
  magnitude in a measurement taken 2026-07-30. A scan sums across sub-populations with different
  semantics; only a fraction is deterministically remediable.

**What to do.** Treat the count as an upper bound to be triaged, never as a workload. Validate every
finding against the project's own documented guards before reporting it, and distinguish *guard
valid, hazard latent* (a pass) from *guard bypassed in live code* (real). State the remediable
subset separately from the raw count — they are different numbers and only one is a plan.

This is the exact complement of *never credit theatre* in
[CODING-WITH-CLAUDE-CODE.md](CODING-WITH-CLAUDE-CODE.md) §4. Present them as a pair: **do not credit
an unenforced control, and do not fault an enforced one.** Both are failures of the same kind —
scoring the artifact instead of the behaviour.

---

## 6. A register carries its own proof

Any findings, gap, risk or remediation register stores **the query that proves each row**, beside
the value observed and the time it was observed.

Without it a register becomes folklore inside a quarter: the rows are still there, nobody can say
which are still true, and re-deriving them costs more than the original review. With it, the
register is re-runnable and a stale row announces itself.

`skills/build-compliance/scripts/scan.py` does the enforcement version of this — `known_controls()`
parses the catalog so a finding *cannot* cite a control that does not exist. The registers beside
this document do the lighter version: every exemption in `tools/practice-gate/sourcing.json` states
why no path can be given, because an exemption without a reason is a silencer rather than a
decision.

Two traps sit next to this one:

- **Circular evidence.** A figure offered as independent support for a claim, but arithmetically
  derived from it, cannot disconfirm anything — and the circularity hides because the derived
  number looks plausible and specific. Before citing a figure as evidence, trace whether it comes
  from the thing it is supposed to test.
- **A process stamp is not a data state.** `was_reviewed`, `was_normalised`, `was_migrated` record
  what happened to a row, not whether the row is correct. Filtering on one while meaning the other
  is a silent no-op that looks like diligence.
