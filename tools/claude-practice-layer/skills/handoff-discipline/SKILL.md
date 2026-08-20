---
name: handoff-discipline
description: >
  Close a long session deliberately instead of letting it compact at a cliff: refuse while
  anything is half-finished, assemble the document from what the session already holds, present it
  before writing it, and say what was not done. Triggers: 'hand this off', 'write a handoff',
  'I am running low on context', 'wrap this up for a fresh session', 'pick this up tomorrow',
  'summarise where we got to', 'note this down for whoever continues', 'start a clean window',
  'what is left to do here'. Produces objective, verified-versus-in-flight status with named
  evidence, decisions and their reasons, the tree and commit to return to, and the work
  deliberately dropped. Do NOT use it as a mid-task progress report, to prove a claim in the
  status section (use verification-before-claiming), to decide whether work has landed on the
  base branch (use git-comparison-choice), or to make a cleanup step recoverable
  (use reversibility-before-destructive).
metadata:
  # SET THESE BEFORE YOU ADOPT THE SKILL. They ship unassigned deliberately: an owner field
  # naming somebody who never agreed to answer for it is worse than an empty one.
  owner: unassigned — set this before you adopt it
  backup_owner: ""
  # CATALOGUE GOVERNANCE ONLY: the owner accepting that this belongs in the catalogue. It says
  # nothing about the accuracy of any document the skill produces.
  approved_by: unassigned — set this before you adopt it
  approval_date: "2026-08-19"
  review_date: "2026-11-17"
  sunset_date: ""
  # Scale, declared rather than assumed: 1 reads and recommends; 2 authors a step that changes
  # something, or writes a document a later reader will act on; 3 changes something itself.
  risk_tier: 2
  risk_factors: >
    It writes one document and runs nothing else. The specific residual risk is that the document
    is nobody's dependency — no test covers it, no citation check reads it, and no build has it in
    scope — so a sentence in it that has gone false will sit there indefinitely being read as
    current state, and the next session acts on it. The bounding mechanism is that the skill
    refuses while a build is half-applied, splits status into done-with-named-evidence versus
    in-flight, and requires every measured figure to carry its date inline where a reader sees it;
    that turns rot from invisible into visible, which is the only property a document with no gate
    can have. The dating half is mechanised for this repository's own prose by
    tools/Test-PracticeClaims.ps1, which fails any measurement-shaped literal whose paragraph
    carries no date and whose -SelfTest proves the check can be red. Nothing gates a handoff
    document itself, and this skill says so on its face rather than implying otherwise.
  pii_handling: >
    None beyond what the session already holds — it names files, branches, commits and commands,
    and quotes no record contents. It reads nothing new to write the document.
  changelog_url: "https://example.invalid/handoff-discipline/history"
  eval_pass_rate: TBD
  eval_last_run: TBD
---

# handoff-discipline

A long session ends one of two ways: compacted, in a window that has quietly lost things, or written
down and replaced by a clean one. This is how to do the second well, and the source is
`tools/claude-session-toolkit/HANDOFF-PRACTICE.md`.

A handoff is a planning step, not a build step. It is assembled from what is already known, approved
before it is written, and it is the least trustworthy document in the tree.

## Never hand off mid-build

The first rule is a refusal. If an edit, a build, a test run or a multi-step task is half-finished,
stop and say so instead of writing the document. A handoff taken at an arbitrary moment records an
inconsistent state, and the next session cannot tell which half of it is real.

Offer the choice out loud: finish the current unit of work first, or hand off with the in-flight item
named as in-flight. Both are fine. What is not fine is a document that describes a half-applied
change as though it were a decision.

This is a refusal rather than a warning for a reason worth stating: the moment you most want to hand
off is the moment the window is nearly full, which is also the moment you are least able to notice
that something is unfinished. The rule has to fire before the judgement it depends on has degraded.
Proceed only at a boundary — a step verified, a suite green, a decision point. What counts as
verified is `tools/claude-practice-layer/skills/verification-before-claiming/SKILL.md`.

## Assemble from context you already have

A handoff should cost almost nothing to produce: build it from what the session knows, with a few
targeted reads to confirm an exact path or the current test result. Never sweep the tree again.

This is not only about spend. A handoff written by re-reading the repository describes *the
repository*; one written from the session describes *the work*, which is the only part the next
session cannot reconstruct. The first is the worse document and it costs more to make. Needing large
reads to write it is the signal that you passed the right handoff point some time ago; the habit that
prevents it is in `tools/claude-dev-practice/CODING-WITH-CLAUDE-CODE.md`, section 3.

## Present it, then write it

Show the assembled document for approval before writing any file. The person who has to live with it
should sign it off while the session that wrote it is still available to be asked what it meant.

On approval, write the file, say the one-line resume command, and stop. Do not start on the next
actions: a session that hands off and then keeps working has invalidated the document it just wrote,
and nothing will tell the next session that. The equivalent rule for a destructive step — do not act
on your own preview — is `tools/claude-practice-layer/skills/reversibility-before-destructive/SKILL.md`.

## The shape

A fixed skeleton, so the reader knows where to look and the writer notices an empty section. Omit
one only when it is genuinely empty. Objective, in one line. Status, split explicitly into
done-and-verified versus in-flight. Key decisions **with their reasons**. A file inventory, one line
each. How to verify, with the exact commands and their last known result. Next actions, ordered and
each independently startable. Traps and open questions. A resume block.

Two of those carry most of the weight. **Key decisions** is what stops the next session reopening a
settled question, spending a window on it and landing somewhere different — write the reason, because
a decision without one reads as arbitrary and is overturned by the first mild preference. **Status**
is where handoffs lie. State it by contents, never by a return value: "the merge command succeeded"
and "the change is on the base branch" are different claims, and the gap between them is where a
handoff most often goes false. Which of the two comparisons settles the second is
`tools/claude-practice-layer/skills/git-comparison-choice/SKILL.md`.

## Uncommitted work is bound to the tree that holds it

A handoff continues a branch, but uncommitted changes live only in the working tree holding them. A
fresh session started anywhere else will not see them and will not be told they exist — it will find
work missing that the document says is done. So record the branch and the current commit, and either
commit the loose work or say plainly that it is uncommitted and tree-bound. Prefer committing: a
commit is visible from any checkout, a dirty tree from exactly one directory on one machine. Name the
tree the resume goes back into, and give the next session a command whose output it can compare
against what the document claims — on a mismatch the correct response is to stop, not to carry on in
the wrong tree. The worktree conventions this assumes are in `tools/claude-worktree-toolkit/README.md`.

## Say what you did not do

The next-actions section fails in the opposite direction from status: not false confidence but silent
omission. Work descoped, blocked or abandoned mid-thought vanishes from the record, and its absence
is indistinguishable from never having been considered. Write it down — as a next action with the
reason it stopped, or as an open question. "Considered and rejected, because X" is one of the most
valuable lines a handoff can carry: it is the only thing standing between the next session and a
rediscovery that costs a whole window. The same principle applied to a durable store, where the
temptation is to keep everything instead, is `tools/claude-session-toolkit/MEMORY-TENDING.md`.
