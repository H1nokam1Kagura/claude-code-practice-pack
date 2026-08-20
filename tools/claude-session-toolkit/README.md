# claude-session-toolkit

Two documents on **ending a session well** — handing work to a fresh context window, and curating
the memory that survives the handover.

They sit in `tools/` beside `claude-dev-practice` and `claude-memory-toolkit` because that is where
this repo keeps things written to be useful outside it. Prose rather than code, so there is nothing
to install.

| Read | For |
|---|---|
| **[HANDOFF-PRACTICE.md](HANDOFF-PRACTICE.md)** | Handing a session's work to a fresh one. Why a handoff is a plan phase and never a build step; the skeleton; and why a handoff document rots faster than anything else you write |
| **[MEMORY-TENDING.md](MEMORY-TENDING.md)** | Deciding what deserves to be a durable memory, at which tier, and when to fold. The judgement pass that sits on top of the index-ordering mechanics in `../claude-memory-toolkit/README.md` |

---

## The pair

They run at the same moment — the end of a session — and are constantly confused with each other,
including by the model. The split is worth stating once:

> **A handoff moves WORK STATE so the next session keeps building. Memory tending curates DURABLE
> KNOWLEDGE that should outlive the work entirely.**

A handoff is disposable by design: it describes a branch at a moment, and it is worthless a week
later. A memory is the opposite — it is written precisely because it should still be true when
nobody remembers writing it. Anything filed in the wrong one of those decays badly. Work state
written as a memory becomes a confident, stale assertion about a build that finished; durable
knowledge written only into a handoff dies with the branch.

## What these are not

**Not runnable.** These are practice documents. In the repository they were written in there are
executable versions, carried as skills, and those are deliberately a *different genre* — a
procedure bound to one host, with its real paths and commands in it. Neither is
generated from the other, and nothing gates them against each other, because forcing an essay and
a procedure to converge would spoil both. What they do share is the set of claims about the
harness, and those are gated: every one is pinned in
`../claude-dev-practice/VERIFIED-AGAINST.md` with the date it was last checked.

**Not neutral about failure.** Both documents were written from things that had already gone wrong
— a handoff whose claims were false within a day of being written, an index that lost its tail in
silence, a backup that archived a single symlink and exited 0. The incidents are kept because a
practice document with only successes in it teaches nothing: the reader cannot tell which advice is
load-bearing.
