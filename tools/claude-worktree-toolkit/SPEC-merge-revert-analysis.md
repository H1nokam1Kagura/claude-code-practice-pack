# Spec — revert analysis for `rwt -Merge`

**Status: proposed, not built.** This is a design decision, not a correction: the toolkit has never
claimed to do revert analysis. It is written down rather than built because the choice it forces —
refuse, or warn — changes what `rwt -Merge` does without asking, and that is the owner's call.

---

## The failure

`rwt -Merge` runs `gh pr merge --squash` and asks nothing about how far behind the branch is.

A squash-merge applies the **merge-base** diff. So if the branch touched a file that base has since
improved, merging replaces base's newer copy with the branch's older one. The branch does not have
to be malicious or even wrong — it just has to be old and to have touched a shared file.

Nothing in the sequence looks wrong while it happens. The commit subjects read like live work, CI is
green (it tests the merge result, which is internally consistent), and the reverted file is usually
one nobody diffs by eye — a generated catalog, a curated register, a config switch.

**This is not hypothetical.** It is the failure recorded in the branch-contribution work: triaging
18 worktrees on 2026-08-07, every branch initially assessed as carrying unlanded work was already on
base, and one
of them held a config flag whose merge would have reverted a completed cutover.

It also compounds with a limit already documented here. `Superseded=yes` means *every file the
branch touched now matches base*. A branch that is **superseded and behind on a file it touched** is
simultaneously "adds nothing" and "would revert something", and only the first is reported today.

---

## The signal

The precise set is **files the branch touched, that base has also changed since the fork**:

```powershell
$base   = "origin/$script:WtBase"
$own    = @(git -C $repo diff --name-only "$base...$Branch")          # three-dot: what this branch touched
$risky  = @($own | Where-Object { git -C $repo log --oneline "$Branch..$base" -- $_ })
```

`$risky` non-empty means: for each of these paths, the branch has a version and base has moved on
independently. A squash would install the branch's version.

Note the two comparison forms are doing different jobs and neither substitutes for the other —
three-dot to establish *scope* (what is this branch's business), then a log range to establish
*divergence* (did base move here too). Same split as `_Wt-BranchSuperseded`.

### The deeper check, and why it is not the default

`git merge-tree --write-tree $base $Branch` produces the actual merge result as a tree object with
no worktree touched. Diffing that tree against base shows exactly what the merge would change,
reverts included — it is authoritative where the heuristic above is indicative.

It requires **git ≥ 2.38**. This toolkit ships to other people's machines, and its stated floor is
lower. Proposal: use the portable heuristic as the always-on gate, and run `merge-tree` additionally
when the git version supports it, reporting the difference between the two rather than silently
preferring one.

---

## The decision to make

| | Refuse by default | Warn by default |
|---|---|---|
| Behaviour | `-Merge` stops, lists the paths, requires `-AcceptReverts` | `-Merge` prints the paths and proceeds |
| Cost when wrong | A safe merge is blocked; the operator adds a flag | A revert lands silently, as today |
| Fits | *unknown is not merged* — the toolkit's existing posture on destructive paths | The toolkit's "print-only, decisions are yours" posture for `swt` |

**Recommendation: refuse.** `-Merge` is the one verb here that writes to a shared base, and the
existing precedent on every other destructive path in this file is to fail closed and make the
operator say the second word. A branch old enough to revert something is also old enough to deserve
a rebase, so the refusal usually points at the right fix rather than at a flag.

The counter-argument is real and should be stated: this makes `-Merge` refuse on a class of merge
that is frequently *fine* — where base's change and the branch's change are to different regions of
the same file and git would merge them cleanly. The heuristic is path-granular, not hunk-granular,
so it will over-refuse. `merge-tree` is what would close that gap, and it is exactly the check that
is not portable.

An honest middle option: **refuse only when the branch is also `Superseded`** — adds nothing and
would revert something is unambiguously wrong, and needs no judgement. Warn in the mixed case.

---

## Scope if built

- `_Wt-MergeWouldRevert` returning `@{ Ran; Paths }`, with the same unknown-is-not-safe contract as
  `_Wt-BranchMerged`: an unresolvable base returns `Ran = $false` and must not read as "no reverts".
- Called from `Reap-InvestWorktree` before the `gh pr merge`, and surfaced in `swt` as a column so
  the report shows it without anyone having to attempt a merge.
- Tests, both polarities and the unknown state:
  - branch touches a file base changed since the fork → paths listed
  - branch touches only files base has not changed → empty
  - branch is behind but on files it never touched → empty (scope control, mirrors case 5)
  - superseded **and** would-revert → the unambiguous case
  - unresolvable base → `Ran = $false`, never an empty "no reverts"
- A `merge-tree` cross-check gated on git version, reporting disagreement rather than picking a
  winner.

Roughly 25 lines of implementation, 5 test cases. The implementation is the small part; the
refuse-versus-warn choice above is the whole of it.
