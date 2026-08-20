---
name: verification-before-claiming
description: >
  Establish whether something is actually true before reporting it, and pick a check whose
  mistakes are independent of the work being checked. Triggers: 'did that work', 'verify this',
  'is this actually passing', 'confirm the fix landed', 'prove it', 'check your own output',
  'how do I know this is right', 'why did that check pass', 'the suite is green — is it', 'what
  would prove this is right', 'write the assertion first', 'that check reported nothing'.
  Produces the check to run, the outcome vocabulary it must answer in, and a statement of what
  varies between the check and the work. Do NOT use it to choose between two branch comparisons
  or decide what a change added (use git-comparison-choice), to make a destructive step
  recoverable (use reversibility-before-destructive), or to write the status section of a
  handover document (use handoff-discipline).
metadata:
  # SET THESE BEFORE YOU ADOPT THE SKILL. They ship unassigned on purpose: a shipped skill
  # naming a stranger as its owner manufactures an accountability nobody agreed to, and a
  # governance field filled in by its author's habit is the costume rather than the thing.
  owner: unassigned — set this before you adopt it
  backup_owner: ""
  # CATALOGUE GOVERNANCE ONLY: the owner accepting that this belongs in the catalogue. It is not
  # a security review, not a sign-off on anything the skill reads, and it grants no authority.
  approved_by: unassigned — set this before you adopt it
  approval_date: "2026-08-19"
  review_date: "2026-11-17"
  sunset_date: ""
  # Scale, declared rather than assumed: 1 reads and recommends; 2 authors a step that changes
  # something, or writes a document a later reader will act on; 3 changes something itself.
  risk_tier: 1
  risk_factors: >
    It reads and recommends; it runs no check itself and changes nothing. The specific residual
    risk is that it is usually invoked by the session that produced the work, which is the
    weakest rung of its own independence ladder — so the failure available to it is narrating a
    verification rather than performing one, and narration is indistinguishable from the real
    thing in the transcript. The bounding mechanism is that it may not issue a verdict of its
    own: every outcome it reports has to be the printed result of a named command the reader can
    re-run, and PASS is unavailable wherever that command did not run. That contract is asserted
    by tools/claude-authoring-toolkit/check_pointer_file.py, whose self-test holds both
    polarities — an unreadable target and an empty target each exit 1, and a check that does not
    apply exits 2 — so no path through it reaches a pass without having measured something.
  pii_handling: >
    None — it reads only files and command output the caller already has open, and quotes a
    result rather than a record. It opens no mail, no ticket bodies and no personnel data.
  changelog_url: "https://example.invalid/verification-before-claiming/history"
  eval_pass_rate: TBD
  eval_last_run: TBD
---

# verification-before-claiming

Two things exist for every task: the work, and the thing that proves the work. Do both, never in
the same breath and never in the same medium. The reasoning this skill compresses is in
`tools/claude-dev-practice/CODING-WITH-CLAUDE-CODE.md`, sections 1 and 4.

## Ask for the assertion before the implementation

"What would prove this is right?" is a different question from "write tests for this", and it
produces a different answer: the second invites a test shaped like the code that was just written,
which passes for exactly as long as the code is wrong in the same way. If no failing input can be
stated, the problem is not understood yet, and that is cheap to discover now.

Plant the bad thing, run the real path, assert the bad thing is absent from the whole output — not
from the one field somebody remembered to scrub. The worked examples, and the anti-patterns that
look like tests and are not, are in `tools/claude-dev-practice/TESTING-DISCIPLINE.md`.

## Do not let it grade its own homework

A model asked "did you do that correctly?" will usually say yes, and that is not dishonesty: the
question is unanswerable from the inside, because the context that produced the error also produces
the evaluation of the error. Rank a reviewer by what actually **varies** between it and the work,
strongest first.

1. **A deterministic assertion** — an exit status, a row count, a diff, a hash. Nothing is shared,
   so there is nothing to correlate.
2. **A differently-authored implementation of the same measurement**, gated against the first.
   `tools/claude-permission-toolkit/check_interpreter_parity.py` is this rung, and it earned its
   place by being red on its first run (2026-08-15): two independently written detectors of one
   property disagreed, 10 versus 12, and each had found something the other missed. Neither gap was
   visible by reading either list.
3. **A different model** — different training, partially correlated errors.
4. **The same model on a clean slate** — the conversation's contamination is gone, the priors are
   identical.
5. **The same model in the same context** — the weakest, and the default.

Two implementations generated from one prompt sit at rung 4 wearing rung 2's clothes: they share
priors, so they agree with each other and are wrong together. Agreement is worth only as much as
the coverage behind it. And never gate on stated confidence — measured on one corpus, the
dimensions carrying the highest self-reported confidence were the least accurate; the ladder and
that measurement are in `tools/claude-dev-practice/GIT-AND-REVIEW.md`.

## A check that could not run is not a pass

This is the load-bearing rule and it has three outcomes, not two.

- **PASS** — it ran, it measured something, it found nothing wrong.
- **SKIPPED** — it was not run. A deliberate choice, and a distinct exit status.
- **INCONCLUSIVE** — it ran and measured nothing. A filter that matched no rows, a scan that
  resolved no files, an empty corpus. This is a failure, not a quiet success.

Never let a warning stand in for a gate. A generator that correctly detected an overflow, printed
the diagnosis and shipped anyway did so for weeks; the detection was never the problem. When you
add a check, make it change the output or fail. `tools/claude-authoring-toolkit/check_pointer_file.py`
shows the exit contract written down as a contract, and its `--self-test` proves it can be red.

## What it does not do

It does not tell you whether the check it recommended is good, only what it is independent of. It
does not credit an unenforced control — a policy document earns nothing, an enforced gate earns the
pass — and it does not fault an enforced one: the continued existence of a working guard is a PASS,
and re-reporting every guarded hazard as a defect wastes the review and tempts somebody to "fix"
the design. Both halves of that pair are in `tools/claude-dev-practice/GIT-AND-REVIEW.md`.
