# Handing off a session

A long session ends one of two ways: you compact it and keep going in a context window that has
quietly lost things, or you write down what matters and start a clean one. This document is about
doing the second well.

The short version:

> **A handoff is a plan phase, not a build step. It is assembled from what you already know, it is
> approved before it is written, and it is the least trustworthy document in the repository.**

That last clause is the part most handoff templates leave out, and it is the one that costs.

---

## 1. Never hand off mid-build

The first rule is a refusal. If a build, an edit, a test run or a multi-step task is half-finished,
stop and say so rather than writing the handoff. A handoff taken at an arbitrary moment captures an
inconsistent state, and the next session cannot tell which half of it is real.

Offer the choice explicitly: finish the current unit of work first, or hand off with the in-flight
item named as in-flight. Both are fine. What is not fine is a document that describes a half-applied
change as though it were a decision.

Proceed only at a natural boundary — a step verified, tests green, a decision point, a clean
stopping place.

**Why this is a refusal and not a warning.** The moment you most want to hand off is the moment the
context window is nearly full, which is also the moment you are least able to notice that something
is half-done. The rule has to fire before the judgement it depends on has degraded.

## 2. Assemble from context you already have

A handoff should cost almost nothing to produce. Build it from what the session already knows, with
a few targeted reads to confirm exact paths or the current test state — never a fresh sweep of the
tree.

This is not only about tokens. A handoff written by re-reading the repository describes *the
repository*; a handoff written from the session describes *the work*, which is the thing the next
session cannot reconstruct. The former is a worse document that costs more to make.

If you find yourself needing large reads to write it, that is a signal you have already passed the
point where you should have handed off.

## 3. Present it, then write it

Show the assembled handoff for approval before writing any file. A handoff is a plan for the next
session, and the person who has to live with it is the one who should sign it off — while the
session that wrote it is still available to be asked what it meant.

On approval, write the file, say the one-line resume command, and stop. Do not start on the next
actions. A session that hands off and then keeps working has invalidated the document it just
wrote, and nothing will tell the next session that.

## 4. The skeleton

A fixed shape, so the reader knows where to look and the writer notices an empty section. Omit one
only when it is genuinely empty.

| Section | What it holds |
|---|---|
| **Objective** | One line: what this session set out to do |
| **Status** | Split explicitly into DONE-and-verified versus IN-FLIGHT. Cite the evidence for anything called verified |
| **Key decisions and why** | The choices already made, with rationale, so the fresh session does not re-litigate them |
| **File inventory** | Every file created or changed, one line each: `path — purpose` |
| **How to verify** | The exact commands to re-check, and their last known result |
| **Next actions** | Ordered, concrete, each independently startable |
| **Gotchas and open questions** | Traps, unknowns, anything that bit |
| **Resume block** | The exact steps to continue |

Two of those carry most of the weight.

**Key decisions** is what stops the next session re-opening a settled question, spending a
context window on it, and arriving somewhere different. Write the *reason*, not just the choice —
a decision without its rationale reads as arbitrary and gets overturned by the first person with a
mild preference.

**Status** is where handoffs lie, and §6 is about why.

## 5. Uncommitted work is bound to the tree that holds it

A handoff continues a *branch*, but uncommitted changes live only in the working tree that holds
them. A fresh session started anywhere else will not see them, and will not be told they exist — it
will simply find work missing that the handoff says is done.

So: record the branch and the current commit, and either commit the loose work or state plainly
that it is uncommitted and tree-bound. Prefer committing. A commit is visible from any checkout of
the branch; a dirty working tree is visible from exactly one directory on one machine.

The resume block should name the tree to return to and say that the resume goes *back into that
same tree* rather than forking a new one. If you use a worktree helper — this repo ships one in
`../claude-worktree-toolkit/` — name the exact command, and check that it does what you think for
the tree you are in. A resume command that silently resolves against a different repository fails
in the most alarming possible way: it reports that the branch does not exist, which reads as *the
work is gone*.

Give the next session something to verify against before it acts, too. A recorded branch name is
only useful if somebody compares it: `git rev-parse --abbrev-ref HEAD` should print what the
handoff says it will, and on a mismatch the correct response is to stop, not to carry on in the
wrong tree.

## 6. A handoff document is the fastest-rotting thing you will write

Everything else in a well-gated repository has something watching it. Code has tests. Prose claims
have a citation check. Figures have a date and an expiry. A handoff has nothing — it is nobody's
dependency, so no check has it in scope, and a false sentence in it will sit there indefinitely
being read as current.

And it rots *fast*, because it describes a moving target. On the session this document was written
from, three claims in the previous handoff were false within a day of being written: work it said
was still to do had been done, and a pull request it said needed opening was already open and
green.

Three habits follow, and they are cheap:

- **State status by contents, never by an exit code.** "The merge command succeeded" is not the
  same claim as "the changes are on the main branch", and the gap between them is where a handoff
  most often goes false. Verify the second and write that down. This is the same rule the
  reversibility document makes for destructive operations, and it applies here for the same reason
  — see `../claude-dev-practice/REVERSIBILITY.md`.
- **Date every measured figure, inline, where a reader sees it.** A count in a handoff reads as
  current state. With a date beside it, a reader can weigh it; without one, they cannot tell a
  measurement from a memory.
- **Let "verified" mean named evidence.** If the handoff says something was verified, the next
  sentence should say how. A status section where everything is verified and nothing says by what
  is a status section nobody can act on.

None of that makes a handoff true. It makes staleness *visible*, which is the only property a
document with no gate can have.

## 7. Say what you did not do

The failure mode of the next-actions section is the opposite of the status section's: not false
confidence, but silent omission. Work that was descoped, blocked, or abandoned mid-thought vanishes
from the record entirely — and its absence is indistinguishable from it never having been
considered.

Write it down as a next action with the reason it stopped, or as an open question. "Considered and
rejected, because X" is one of the most valuable lines a handoff can carry: it is the only thing
standing between the next session and a rediscovery that costs a context window.
