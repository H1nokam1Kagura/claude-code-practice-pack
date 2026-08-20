---
name: git-comparison-choice
description: >
  Decide which comparison answers the question you actually have before running one, and treat a
  successful command as no evidence that anything moved. Triggers: 'what changed on this branch',
  'what does this add', 'has this landed', 'is it merged', 'can I delete this branch', 'why does
  the diff look wrong', 'the two diffs disagree', 'is this commit in the base branch', 'it says
  new branch', 'the push succeeded but nothing is there', 'did the merge actually take', 'reconcile
  these file counts'. Produces the question written in words, the comparison that answers it, and
  the assertion that proves the target now differs. Do NOT use it to design the check for a
  non-git claim (use verification-before-claiming), to make the delete itself recoverable
  (use reversibility-before-destructive), or to write up where a session got to
  (use handoff-discipline).
metadata:
  # SET THESE BEFORE YOU ADOPT THE SKILL. They ship unassigned on purpose: an owner is the one
  # answer to "who decides?", and inventing one for a recipient answers it wrongly.
  owner: unassigned — set this before you adopt it
  backup_owner: ""
  # CATALOGUE GOVERNANCE ONLY: the owner accepting that this belongs in the catalogue. It is not
  # a sign-off on any keep-or-delete decision the skill informs.
  approved_by: unassigned — set this before you adopt it
  approval_date: "2026-08-19"
  review_date: "2026-11-17"
  sunset_date: ""
  # Scale, declared rather than assumed: 1 reads and recommends; 2 authors a step that changes
  # something, or writes a document a later reader will act on; 3 changes something itself.
  risk_tier: 1
  risk_factors: >
    Read-only across history and refs; it recommends comparisons and runs no destructive command.
    The specific residual risk is that the comparisons it recommends answer confidently and can
    invert a keep-or-delete verdict in either direction — measured from where a branch diverged,
    already-landed work reads as this branch's contribution; compared directly against the base,
    other people's newer commits read as a revert — and neither errors, so the wrong pairing ends
    in a deleted branch that was the only copy. The bounding mechanism is that a delete decision
    requires both comparisons plus reconciliation of the gap, and that an unresolvable reference
    must return unknown rather than no. That polarity is asserted by
    tools/claude-worktree-toolkit/Test-WorktreeMergedness.ps1, whose case 4 requires a null and
    not a false for a reference it cannot resolve, and whose case 9 supplies the other polarity so
    the suite cannot pass by always answering unknown.
  pii_handling: >
    None — it reads commit metadata, refs, file names and counts. Author names and addresses in
    history are not extracted, aggregated or reported on.
  changelog_url: "https://example.invalid/git-comparison-choice/history"
  eval_pass_rate: TBD
  eval_last_run: TBD
---

# git-comparison-choice

A tool that answers the wrong question answers it just as confidently as the right one. Almost none
of this is caught by a build, because none of it is a known check — which is why it keeps being
rediscovered. The source is `tools/claude-dev-practice/GIT-AND-REVIEW.md`, sections 1 and 2.

## Name the question before you choose the comparison

Every "what changed?" has more than one defensible answer, and the wrong choice produces a number
rather than an error. Two questions that look identical and are not:

- *What did this author change?* — the branch's own commits, measured from the point where it
  diverged from the base.
- *What would merging this add that the base does not already have?* — a direct comparison against
  the base as it stands right now.

Ask the first when reviewing authorship. Ask the second when deciding keep or delete. They fail in
**opposite** directions, which is why one cannot stand in for the other: measured from the divergence
point, work that has already landed elsewhere is counted as this branch's contribution; compared
directly, somebody else's newer commits read as this branch reverting them.

**A worked instance, recorded 2026-08-15.** The same branch, at one moment, under two comparisons:
one reported 24 files and 3,815 insertions, the other 13 files and 1,225. The second was right. The
first was counting content that had already landed under a different commit, because the request
carrying it had been squash-merged. The pairing and the reconciliation are worked at length in
`tools/claude-dev-practice/GIT-AND-REVIEW.md`, section 1.

## Squash-merge breaks the cheapest check

That last point earns its own heading, because it invalidates the test people reach for first.

> After a squash-merge, *"is this commit an ancestor of the base?"* and *"is this commit's content in
> the base?"* have different answers. The first says no. The content is there.

Patch comparison does not rescue it either. Comparing patches works per commit, and a squash collapses
a branch into one commit whose patch is the union of all of them — so it matches in exactly one case:
the branch held a single commit. Two things are therefore invisible to it, and neither is exotic: a
multi-commit branch squashed as itself, and content squashed into a *different* change alongside other
work. Either way the branch reports unmerged forever although every line of it has landed. That
failure is safe — it keeps a dead tree rather than deleting a live one — but it must be stated, or the
verdict gets trusted past its range. The polarities are held apart by
`tools/claude-worktree-toolkit/Test-WorktreeMergedness.ps1`.

## What to do

Write the question in words before running anything. On a keep-or-delete decision run **both**
comparisons and reconcile the gap: a disagreement is the finding, not noise. Where the evidence is
only sufficient and not necessary, report the weaker verdict — an unresolvable reference returns
unknown, never no, because "unknown" collapsing into "no" is how a false negative gets manufactured.
The general form of that rule, and the ladder of reviewers behind it, is
`tools/claude-practice-layer/skills/verification-before-claiming/SKILL.md`.

## A successful operation is not evidence that anything moved

Separate *the command exited successfully* from *the target now differs*. Almost every expensive
failure here is an operation that honestly reported doing what it was asked, where what it was asked
was not what was meant.

- **The empty change.** Creating a branch pointer does not switch to it. Commits keep landing on
  whatever is checked out, and the push then ships the stale pointer — a no-op that prints nothing
  alarming. Each subsequent change re-proposes the previous one's content, checks pass, the merge
  reports success, and nothing lands. The tell is several squashed commits on the base sharing one
  title, because the title is derived from identical content.
- **The absorbed commit.** Branching from a local default that is behind the remote, or merging while
  a local default is ahead of it, lets a squash quietly swallow work that was never pushed. Nothing
  conflicts, because there is nothing to conflict with.
- **The vanished branch.** A merge configured to delete its branch removes the remote reference. A
  later push to that name reports a new branch and succeeds, creating a resurrection rather than
  adding to the thing you thought was still open.

Prevent the first two by construction rather than by care — create every branch from the fetched
remote reference rather than from whatever the local default happens to be, and when the fetch that
keeps it current fails, say so and name the consequence instead of proceeding against a stale
reference. That is what `tools/claude-worktree-toolkit/wt.ps1` does, and a guard that degrades loudly
is the difference between a known risk and a silent one.

For the rest, assert the delta and not the return value: after a push, that the remote reference
equals local head; after a merge, that the content is reachable from the base — content, not ancestry;
before proposing a change, that both comparisons agree on what it adds. Treat an unexpected new-branch
line, or an unexpected *absence* of conflict, as a full stop: those are the two places the system tells
you your model of the world is wrong, and both read as success. Where the next step is a delete, the
recovery window and the identifier to record first are in
`tools/claude-practice-layer/skills/reversibility-before-destructive/SKILL.md`.

## The working tree is shared state

This applies the moment more than one session, or more than one tree, touches a repository. Parallel
sessions share one tree, so files change under you mid-task and anything destructive that assumes the
tree is as you last saw it can discard another session's uncommitted work — re-read immediately
before, not once at the start. A stale checkout manufactures confident false absences: an old tree or
a default branch behind the remote will report a file missing, work unfinished, or a fix about to be
reintroduced, all of them wrong and all of them plausible, so fetch first and suspect the checkout
whenever a validator reports *everything except one thing*. And version-controlled build outputs
follow the checked-out branch, so any publisher reading from a path rather than a reference will ship
whichever vintage is on disk. Reduce all three by construction: separate trees per task, and settings
that enforce what you would otherwise have to remember. The workflow this assumes is
`tools/claude-worktree-toolkit/README.md`.
