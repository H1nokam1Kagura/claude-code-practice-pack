---
name: incident-triage
description: >
  Decide what to do about an incident that is happening RIGHT NOW: how bad it is, who needs
  waking, and what the next action is. Triggers: 'is this a sev1', 'what severity is this',
  'should I page someone', 'the alert just fired, what now', 'triage this incident', 'how bad
  is this'. Produces a severity call, an owner, and one next action -- nothing else. Do NOT
  use it after the incident is over to write the review (use incident-writeup), or to write
  down a procedure for next time (use runbook-author).
metadata:
  owner: someone@example.invalid
  backup_owner: someone-else@example.invalid
  # CATALOGUE GOVERNANCE ONLY: the owner accepting that this belongs in the catalogue.
  # It is not a security or operational sign-off, and it grants this skill no authority.
  approved_by: someone@example.invalid
  approval_date: "2026-08-16"
  review_date: "2026-11-14"
  sunset_date: ""
  risk_tier: 2
  risk_factors: >
    Read-only across dashboards and logs; it recommends a page but never sends one, so the
    irreversible step stays with a person. The material risk is disclosure: it reads log lines
    while looking for the failing request, and log lines carry request bodies. Every quoted
    line therefore passes through one redact() chokepoint and is reported as source:line plus
    a field name, never a value -- asserted by test_redaction.py, which fails if any code path
    reaches the reporter without going through it.
  pii_handling: >
    Log lines only, and never quoted verbatim. It does not open ticket bodies, mail, or
    personnel records.
  changelog_url: "https://example.invalid/incident-triage/history"
  eval_pass_rate: TBD
  eval_last_run: TBD
---

# incident-triage

**This is an example skill, and the tool it describes is imaginary.** It exists so that the lint
and the triggering eval in this toolkit have something real to run against, and so the
frontmatter above can be pointed at as a worked example rather than described. The body is
deliberately thin; a real skill's body is where the substance goes, because it costs nothing
until the skill is actually used.

**The citation in `risk_factors` above names nothing in this repository.** The redact()
chokepoint and the test_redaction.py that asserts it belong to the imagined triage tool, not to
this toolkit — there is no such function and no such test here, and looking for them will not
find them. What the field is demonstrating is the *shape* of the citation: a specific residual
risk, one named mechanism that bounds it, and a named test with the condition it fails on. A
real skill substitutes its own three and they have to resolve. The same block appears in
`../../../SKILL-FRONTMATTER.md`, and `lint_skills.py --self-test` fails if the two diverge.

## What it does

Given a live alert, it produces exactly three things:

1. **A severity call**, with the one observation that decides it.
2. **An owner** -- the person, not the team.
3. **One next action.** Not a plan. The next thing to do.

## What it does not do

It does not page anyone, does not silence an alert, and does not touch the system it is
looking at. It reads, it recommends, and a person decides. Anything that cannot be undone
stays on the human side of the line, which is what keeps its risk tier honest.
