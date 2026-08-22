# Reversibility

How to make a destructive operation safe to run. Not "careful" — *reversible*, which is a property
of the design rather than of the operator's attention.

> **If the only thing standing between you and data loss is that you read the command carefully,
> you have no control.**

---

## 1. The four-step shape

Every mutating operation on this stack takes the same form. Skipping a step is the finding.

```text
dry-run  →  execute  →  verify  →  rollback-by-run-id
```

- **Dry-run is the default.** No flag, no mutation. `-DryRun` as an opt-in gets forgotten; `-Execute`
  as an opt-in cannot be. The dry-run must print what *would* change, with counts, not just "OK".
- **Execute stamps a run id.** Every row, node or file written carries it.
- **Verify reads back.** Not the exit code — the thing. Row counts, a re-query, a diff.
- **Rollback is a query, not an archaeology project.** `WHERE run_id = '<id>'` is the whole recovery
  plan, and it works because step 2 made it work.

The run id is what turns "undo" from a hope into a `DELETE`. Generate it once, log it where a human
will find it, and print it on completion.

---

## 2. Idempotency is a safety property, not a convenience

**Re-running writes zero.** This is the property that makes a partial failure survivable: when a
batch dies at item 400 of 900, you re-run the whole thing rather than reasoning about where it
stopped.

It has to be tested, not asserted. The pattern used throughout this repo:

```text
run once  → N changes
run again → 0 changes, and the artifact is byte-identical
```

`eval_skills.py --write-back` returns `False` on the second call and the file is untouched.
`rebuild_memory_index.py` does not even rewrite its output when nothing moved. Both have that
verified explicitly rather than claimed.

Two mechanics that get this wrong quietly:

- **Content-hash your key, not your run.** Hash over the *content*, never over `retrieved_at` or a
  run id, or every re-run is a fresh row and "idempotent" becomes "duplicating politely".
- **Stamp provenance `ON CREATE` only.** Updating a provenance field on match overwrites the origin
  with the latest touch — you lose the one fact provenance exists to record.

---

## 3. Verify contents, never exit codes

The most expensive failure class here, because the tool reports success.

**The backup that protects nothing.** The canonical case: a memory store reached through junctions
from every worktree. Run `tar -czf backup.tgz -C <a junctioned dir> memory` and tar archives **the
symlink itself** — one entry, about 1 KB, **exit 0, no warning**. The backup then licenses the risky
fold that follows. Verified failing-then-passing on 2026-08-07, while backing up the memory store
this document's own lessons live in: 1 entry from a junctioned directory versus 534 from the
canonical one.

```bash
tar -tzf backup.tgz | wc -l          # what the archive actually contains
ls <source>/*.md | wc -l             # what it should contain
# the two must agree
```

Compare against a **live count**, never a remembered one. "Looks about right" is exactly how a
1-entry archive gets accepted, and any number written into a runbook rots as the corpus grows. The
same hazard applies to `cp -r`, `rsync` without `-L`, and zip.

**The scan that scanned nothing.** A secret scanner in a git worktree: `.git` is a file, the
container cannot resolve it, and the scanner prints "no leaks found" and exits 0 in ~14 ms
(recorded 2026-08-10). Guard
it with three assertions before believing any clean result — a real `.git` *directory* exists, the
base commit is present, and the commit count in range is **non-zero**.

**The filter that matched nothing.** A scope predicate that matches no rows produces a smaller
table, not an error. Assert that every requested filter component contributed at least one row and
fail the build if one did not — otherwise "successful build of a smaller scope" and "silently
dropped half the scope" are indistinguishable.

The general rule: **a check that could not run must never report PASS.** Give it a distinct status
(`SKIPPED`) and a distinct exit code, and go one better where you can — "I chose not to run this"
(skip) and "it ran and measured nothing" (`INCONCLUSIVE`) are different states and should not share
an outcome.

---

## 4. Know what is actually recoverable before you rely on it

Reversibility is a property of the *store*, and it differs by store. Establish which one you are in
**before** the destructive step, not after:

| Store | Recovery |
|---|---|
| Git-tracked file | Cheap. Reflog holds a deleted branch tip ~90 days — echo the SHA before any force-delete |
| Delta table | Time travel: `DESCRIBE HISTORY`, then `SELECT … VERSION AS OF <n>`. The pre-incident version is usually the second-most-recent |
| Graph write | Only if you stamped a run id (§1). Otherwise there is no undo |
| Session checkpoint | **Narrower than it looks.** Covers the agent's own file edits. Does *not* cover changes made by shell commands or symlinked/hard-linked paths. Subagent edits are usually not covered either -- the exception is a **foreground** forked skill, whose edits are restored; a background fork, the default, is not |
| Untracked / gitignored dir | **None.** Treat a delete as final |

Two rows surprise people.

**The session checkpoint**, because it is the one that feels like a safety net and is reached for
first. The exclusions are not edge cases — they are the normal path. Push operational logic into
scripts and have the agent run them (which is the right shape for auditability) and the resulting
changes are outside the checkpoint entirely; the rewind reports success and restores almost none of
it. The symlink exclusion is the §3 junction hazard again, arriving through a second tool: a
restore over a junctioned path skips the files and says so only in a count.

**The untracked directory**, because a store excluded from version control — a memory directory, a
local database, an export folder — has no safety net at all. The backup discipline in §3 is the
*only* control there, which is precisely why verifying it matters.

---

## 5. Gate the irreversible, not the routine

Confirmation fatigue is a real failure mode: prompt on everything and the prompts stop being read.
Reserve friction for what earns it.

- **Deny** what is unrecoverable: root-scoped recursive deletes, true force-push, secret writes.
- **Ask** for what is reversible-but-outward-facing: pushes, merges, releases, sends, uploads,
  deletes on a shared service. Publishing is not reversible the way a local edit is.
- **Allow** the rest broadly, and put the bound in the floor rather than in a long allow-list.

Write deny rules in **exact** forms, because a deny cannot carry exceptions: `git push --force*`
also swallows `--force-with-lease`, which is the safe form.

And prefer a design that removes the need for the gate. A print-only reporter that suggests commands
(`swt` printing `rwt -Branch x` lines, in `tools/claude-worktree-toolkit/wt.ps1`) is safer than an
automatic reaper with a confirmation
prompt — because the second one gets `-Yes` added to it the first time someone scripts it.

---

## 6. Before the destructive step, prove the set

Cross-store set-diffs are the standard prelude to a cleanup, and they fail in the direction that
deletes things.

- **Complete both sides first.** A missing row on one side reads as "absent, safe to delete" rather
  than "not fetched".
- **Name the question before choosing the comparison.** *"What did this branch change?"* and *"what
  does main already have?"* need different diffs, and the wrong pairing silently inverts a
  keep-or-delete decision in either direction.
- **Under-claim.** Where the evidence is only sufficient rather than necessary, report the weaker
  verdict. `_Wt-BranchSuperseded` in `tools/claude-worktree-toolkit/wt.ps1` returns `null` for an
  unresolvable ref rather than `false`,
  because "unknown" collapsing into "no" is how a false negative is manufactured.
- **Report the tip SHA** on any delete, so the reflog window is usable.
