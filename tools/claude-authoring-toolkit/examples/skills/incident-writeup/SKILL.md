---
name: incident-writeup
description: >
  Write the review of an incident that is already OVER: the timeline, what actually caused it,
  and the changes that follow. Triggers: 'write up the incident', 'post-incident review',
  'draft the postmortem', 'what should the writeup say', 'we resolved it, now what do I
  write'. Works from the incident record and the timeline, after resolution. Do NOT use it
  while an incident is still live (use incident-triage), or to turn the resulting actions into
  a repeatable procedure (use runbook-author).
metadata:
  owner: someone@example.invalid
  backup_owner: ""
  approved_by: someone@example.invalid
  approval_date: "2026-08-16"
  review_date: "2026-11-14"
  sunset_date: ""
  risk_tier: 1
  risk_factors: >
    Writes prose into a document you name and nothing else. The residual risk is a writeup that
    reads as a finding of fault; the bounding mechanism is that it names systems and decisions
    rather than people, and refuses to attribute cause to an individual.
  pii_handling: "None. It works from the incident record, and names roles rather than people."
  changelog_url: "https://example.invalid/incident-writeup/history"
  eval_pass_rate: TBD
  eval_last_run: TBD
---

# incident-writeup

**This is an example skill** -- see incident-triage in this directory for the fuller worked
frontmatter.

It produces a timeline, a cause, and the changes that follow from it. The cause is a statement
about a system, never about a person: an incident review that reads as an accusation is one
nobody writes honestly the next time.
