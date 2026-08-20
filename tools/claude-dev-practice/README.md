# claude-dev-practice

The documents on **coding with Claude Code** — the harness, the model, and the habits that keep
both honest.

They sit in `tools/` beside `claude-memory-toolkit` and `claude-worktree-toolkit` because that is
where this repo keeps things written to be useful outside it. Prose rather than code, so there is
nothing to install.

| Read | For |
|---|---|
| **[CODING-WITH-CLAUDE-CODE.md](CODING-WITH-CLAUDE-CODE.md)** | The front door. Deciding what the model writes vs what checks it; configuring the harness instead of the conversation; context as a resource; making output checkable; where knowledge goes; and the tool surface, which is the input that fails quietly |
| **[TESTING-DISCIPLINE.md](TESTING-DISCIPLINE.md)** | What makes a test worth having. Assert properties, not implementations |
| **[REVERSIBILITY.md](REVERSIBILITY.md)** | Making a destructive operation safe to run — dry-run → execute → verify → rollback-by-run-id, and the ways a tool reports success having done nothing |
| **[GIT-AND-REVIEW.md](GIT-AND-REVIEW.md)** | Deciding what changed, and whether it is right. Which diff answers which question; merges that report success and land nothing; why "independent reviewer" means uncorrelated errors, not a fresh window |
| **[ORCHESTRATION.md](ORCHESTRATION.md)** | Splitting work across agents. Why a second agent earns its keep for what it is not allowed to see; the auditor contract and cold scoring; panel composition; and one file, one writer |
| **[PRIOR-ART.md](PRIOR-ART.md)** | The work this sits next to, read and dated. Why the workflow layer and the verification layer are complementary; where separately-authored projects reached the same rule, and what that agreement is worth; and the one difference, which is claim hygiene rather than correctness |

---

## The thesis

One idea connects them all:

> **A check that could not run must never report PASS, and a guarantee that depends on remembering
> to apply it is not a guarantee.**

Everything else is that idea applied to a different surface — the permission floor, the redaction
chokepoint, the freshness gate, the completeness check, the backup you verified by contents rather
than by exit code.

## What these are not

**Not aspirational.** Every claim points at code in this repo, with the path. If a document says a
thing is enforced, you can go and read the enforcement — and if you cannot, that is a bug in the
document. That promise is now executed rather than asserted: `../Test-PracticeClaims.ps1` resolves
every citation on every run, and **checks that every section has one** — the sections that
genuinely cannot are listed in `../practice-gate/sourcing.json` with the reason, so an unsourced
claim is a decision on the record rather than an oversight. Citations pointing outside this
repository are registered the same way. The script also dates the figures and pins the harness
claims — see [VERIFIED-AGAINST.md](VERIFIED-AGAINST.md).

**Not general software-engineering advice.** There is plenty of that elsewhere and it is mostly
better. These cover the parts that are specific to working with an agentic coding tool, or that
this stack learned the expensive way.

**Not finished.** Each was written from failures that had already happened. New ones will arrive.

## A note on the examples

Several are unflattering, and they are separate incidents rather than one — an allow-list of 2,673
rules that bounded nothing (2026-08-10); a backup that archived a single symlink and exited 0
(2026-08-07); a generator that detected its own overflow correctly, printed the diagnosis, and
shipped anyway for weeks; a teardown command that announced a branch "patch-id-verified" when the
check had not passed, for as long as the tool had existed; and a correction in the front door
(`CODING-WITH-CLAUDE-CODE.md`) that was itself wrong, which is why `VERIFIED-AGAINST.md` exists.

They are kept deliberately. A practice document with only successes in it teaches nothing, because
the reader cannot tell which advice is load-bearing.
