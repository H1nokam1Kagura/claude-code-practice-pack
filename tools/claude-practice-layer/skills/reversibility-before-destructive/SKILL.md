---
name: reversibility-before-destructive
description: >
  Make an operation that deletes, overwrites or bulk-writes safe to run, by design rather than by
  care: dry-run first, stamp a run identifier, read the result back, and keep a one-query
  rollback. Triggers: 'delete these', 'clean up the old ones', 'drop that table', 'overwrite the
  file', 'bulk update', 'reset the branch', 'prune what is unused', 'back this up first', 'is
  this recoverable', 'can I undo it', 'the backup says it worked', 'write a cleanup script', 'how
  do I roll this back'. Produces the four-step shape, the readback that proves the change, and
  the recovery available for the store actually being touched. Do NOT use it to choose which
  branch comparison decides a keep-or-delete (use git-comparison-choice), to pick a reviewer for
  a claim (use verification-before-claiming), or to end a session and write the work up
  (use handoff-discipline).
metadata:
  # SET THESE BEFORE YOU ADOPT THE SKILL. They ship unassigned on purpose — see the note in the
  # body under "Adopting this". A field filled in by its author's habit is governance theatre.
  owner: unassigned — set this before you adopt it
  backup_owner: ""
  # CATALOGUE GOVERNANCE ONLY: the owner accepting that this belongs in the catalogue. It is not
  # an authorisation for anything the skill goes on to recommend.
  approved_by: unassigned — set this before you adopt it
  approval_date: "2026-08-19"
  review_date: "2026-11-17"
  sunset_date: ""
  # Scale, declared rather than assumed: 1 reads and recommends; 2 authors a step that changes
  # something, or writes a document a later reader will act on; 3 changes something itself.
  risk_tier: 2
  risk_factors: >
    Print-only: it composes the destructive command and never runs one, so the irreversible step
    stays with a person. The specific residual risk runs the other way from timidity — its
    product is the exact command with dry-run evidence attached beside it, and evidence adjacent
    to a command reads as authorisation, so the plausible failure is the command being pasted on
    the strength of the preview rather than the readback. The bounding mechanism is ordering: the
    rollback predicate is a precondition of the execute step, so no destructive command is
    emitted before the run identifier that reverses it exists, and no step may be called done on
    a return value. The readback shape that requirement depends on is asserted by
    tools/claude-memory-toolkit/tests/safety_test.py, which compares a hash of every file before
    and after a run rather than the run's exit status, and fails if any byte moved.
  pii_handling: >
    None — it inspects counts, names and hashes of the objects being changed, and does not read
    their contents. Where a readback needs a count, it takes the count and not the rows.
  changelog_url: "https://example.invalid/reversibility-before-destructive/history"
  eval_pass_rate: TBD
  eval_last_run: TBD
---

# reversibility-before-destructive

If the only thing standing between you and data loss is having read the command carefully, there is
no control. Reversibility is a property of the design, not of the operator's attention. The full
argument, with the incidents behind each rule, is `tools/claude-dev-practice/REVERSIBILITY.md`.

## The four-step shape

Every mutating operation takes the same form, and skipping a step is itself the finding.

```
dry-run  ->  execute  ->  verify  ->  rollback by run identifier
```

**Dry-run is what happens with no flag.** An opt-in preview gets forgotten; an opt-in execute
cannot be. The preview prints what *would* change, with counts, never just an acknowledgement.
**Execute stamps an identifier** on every row, node or file it writes, generated once and printed on
completion where a person will find it. **Verify reads the thing back.** **Rollback is then a query
with a predicate on that identifier** rather than an archaeology project — which works only because
the execute step made it work. The same discipline applied to a memory store, including the guard
rails, is in `tools/claude-session-toolkit/MEMORY-TENDING.md`.

## Verify contents, never the exit status

The most expensive failure class available, because the tool reports success while having done
nothing.

- **An archive that protects nothing.** Archive a directory reached through a link and the archive
  holds the link: one entry, about a kilobyte, successful exit, no warning. The archive then
  licenses the risky operation that follows. Count the entries in it and compare against a live
  count of the source — never against a number written into a procedure, because the corpus grows
  and "looks about right" is precisely how a one-entry archive gets accepted.
- **A scan that scanned nothing.** A scanner that cannot resolve its own subject can report clean
  and exit successfully in milliseconds. Assert its preconditions before believing a clean result,
  and assert that the count of things it examined is non-zero.
- **A filter that matched nothing.** A predicate matching no rows produces a smaller result, not an
  error, so "successful run over a smaller scope" and "silently dropped half the scope" are the same
  output. Assert that every requested component contributed at least one row.

Which is the same rule as `tools/claude-practice-layer/skills/verification-before-claiming/SKILL.md`
states for checks in general: a step that could not run must not report success.

## Idempotency is a safety property

Re-running writes zero. That is what makes a partial failure survivable — when a batch dies part
way through, you re-run the whole thing instead of reasoning about where it stopped. It has to be
demonstrated rather than asserted: run once for N changes, run again for zero changes and a
byte-identical artifact. Two mechanics break it quietly. **Hash the content, never the run** — take
a timestamp or the run identifier into the key and every re-run is a fresh row, which is duplicating
politely. **Stamp provenance only on create**, because updating it on match replaces the origin with
the latest touch and loses the one fact provenance exists to hold. Both are worked in
`tools/claude-dev-practice/REVERSIBILITY.md`.

## Know the recovery before you rely on it

Recovery is a property of the store, and it differs by store, so establish which one you are in
**before** the destructive step. A version-controlled file is cheap to recover and its deleted
pointer survives in the reference log for a while — echo the identifier before any forced delete. A
versioned table has time travel, so read its history and name the version you would return to. A
write to a store with no versioning is recoverable only if you stamped an identifier. An untracked
or ignored directory — a local database, an export folder, a scratch tree — has **no** recovery at
all, and a delete there is final; the archive discipline above is the only control that exists, which
is exactly why verifying the archive matters. The session-level undo is narrower than it looks and
is worth reading about before it is relied on: `tools/claude-dev-practice/REVERSIBILITY.md`, in the
section on what is actually recoverable.

## Prove the set before the destructive step

A cross-store difference is the usual prelude to a cleanup, and it fails in the direction that
deletes things.

- **Complete both sides first.** A row that was never fetched reads as "absent, safe to delete"
  rather than "not fetched".
- **Name the question before choosing the comparison.** Which comparison answers a keep-or-delete
  decision is its own problem, and it belongs to
  `tools/claude-practice-layer/skills/git-comparison-choice/SKILL.md`.
- **Under-claim.** Where the evidence is sufficient but not necessary, report the weaker verdict;
  "unknown" collapsing into "no" is how a false negative gets manufactured.
- **Report the identifier** of whatever you are about to remove, so the recovery window is usable.

## Adopting this

Prefer a design that removes the need for a confirmation prompt over one that adds a better prompt:
gate what is unrecoverable, ask about what is reversible but outward-facing, and allow the rest
broadly. A reporter that prints the command for a person to run beats an automatic actor with a
confirmation, because the second grows a suppress-the-prompt flag the first time somebody scripts
it. Set the owner and approver fields in the frontmatter above before you put this in a catalogue;
they ship unassigned so that adopting it is a decision somebody makes rather than one it arrives
carrying. The convention those fields answer to is
`tools/claude-authoring-toolkit/SKILL-FRONTMATTER.md`.
