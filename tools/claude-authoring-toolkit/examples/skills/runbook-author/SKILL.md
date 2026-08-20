---
name: runbook-author
description: >
  Write or update the runbook for a procedure somebody will follow again: the steps, the
  checks between them, and what to do when one fails. Triggers: 'write a runbook', 'document
  this procedure', 'turn this into a runbook', 'update the runbook for X', 'what should the
  steps be'. Produces a procedure for a future reader who has none of today's context. Do NOT
  use it to handle a live incident (use incident-triage) or to write the review of one that
  has finished (use incident-writeup).
metadata:
  owner: someone@example.invalid
  backup_owner: ""
  approved_by: someone@example.invalid
  approval_date: "2026-08-16"
  review_date: "2026-11-14"
  sunset_date: ""
  risk_tier: 1
  risk_factors: >
    Writes a document; runs nothing. The residual risk is a runbook that goes stale and is
    followed anyway, which is worse than no runbook. The bounding mechanism is that every step
    carries the check that proves it worked, so a step that has stopped working fails visibly
    at the check rather than silently at the next step.
  pii_handling: "None."
  changelog_url: "https://example.invalid/runbook-author/history"
  eval_pass_rate: TBD
  eval_last_run: TBD
---

# runbook-author

**This is an example skill** -- see incident-triage in this directory for the fuller worked
frontmatter.

Every step gets a check that proves it worked, and every check gets the thing to do when it
does not. A runbook without checks is a list of hopes, and it is followed most confidently
exactly when it has gone stale.
