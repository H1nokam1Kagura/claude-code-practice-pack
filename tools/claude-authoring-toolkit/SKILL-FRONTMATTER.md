# SKILL-FRONTMATTER.md

The contract for the top of a `SKILL.md`, why each field is there, and the two checks that
keep it from becoming decoration.

---

## What the frontmatter is actually doing

A skill's **body** loads only when the skill is used, so a long procedure with reference
material costs nothing until somebody needs it. The **frontmatter** is the opposite: a listing
of every skill's name and description is loaded up front so the model knows what exists. That
asymmetry is the whole design, and it decides where effort goes — detail belongs in the body,
and the description is a routing decision written in prose.

Three consequences follow, and none of them is obvious from looking at a skill file.

**The description is competing for a budget, not sitting in a fixed slot.** The listing has a
character budget that scales with the model's context window — the default is 1% of it — and
when the listing overflows, entries are shortened: descriptions get **dropped**, starting with
the skills you invoke least. A skill can therefore be present, correctly written, and
*invisible*, because its description was the one cut to make room. Separately, each entry's
combined description text is truncated at 1,536 characters regardless of budget. Both figures
are configurable, and both are the platform's, not yours. _Verified 2026-08-16._

So the budget in `skill-schema.json` is deliberately **tighter than the platform's cap and
labelled a convention**, not a limit. A number you set and can defend is worth more than a
number copied from a document, because the copied one goes wrong quietly when the document
changes. The check prints the budget it held you to, so a reader can see which one it was.

**`name` is a display label, and the command comes from the directory name** — in a personal
or project skill. That means a `name` disagreeing with its directory does not break invocation
the way it looks like it should; it just labels the thing confusingly. Requiring `name` at all
is a house rule. This toolkit therefore checks it *when present* and does not demand it, and
the schema says so in its own words rather than leaving a reader to infer a platform rule from
a script. In a **plugin skill** the field does set the last segment of the command, and there a
mismatch is exactly as bad as it looks — which is why the `bundle` profile requires it. (The
documentation's term is *plugin skill*; `bundle` is only what this schema calls the profile.)

**Governance fields must be nested under `metadata`, or the file stops being portable.** The
same `SKILL.md` distributed outside the CLI is validated against a fixed field list, and an
unrecognised *top-level* key is rejected outright with an error rather than ignored — only six
frontmatter fields survive that trip. `metadata` is the sanctioned free-form map, so a
governance block nested there travels intact while the same fields hoisted to the top level
break the file everywhere else. One more trap: a `metadata` value that is not a map is
**dropped**, so every field under it silently ceases to exist. That failure has no error
message anywhere, which is why the lint gives it one.

---

## The fields

Every one of these lives under `metadata`. The table is the human copy; `skill-schema.json` is
the machine copy, and `lint_skills.py --self-test` fails if the two ever name different fields.

| Field | What it is for |
|---|---|
| `owner` | The person answerable for the skill. A name, not a team, so "who decides?" has one answer. |
| `backup_owner` | Who answers when the owner cannot. Empty is honest; absent is not. |
| `approved_by` | Who accepted this into the catalogue. **Catalogue governance only** — see the warning below. |
| `approval_date` | When that acceptance happened. |
| `review_date` | When it must be looked at again. Past this date, it is a claim nobody has re-checked. |
| `sunset_date` | When it stops being current. Empty while live. |
| `risk_tier` | How much it can do, on a scale you define. |
| `risk_factors` | The specific residual risk, the mechanism that bounds it, and the test that asserts the mechanism. |
| `pii_handling` | What personal data it touches and what it does with it. "None" is a valid answer and must still be stated. |
| `changelog_url` | Where its history can be read. |
| `eval_pass_rate` | Measured triggering accuracy. Written back by the eval; never hand-edited. |
| `eval_last_run` | When that measurement was taken. |

> **Two senses of "approved", kept apart.** `approved_by` records an owner accepting a skill
> into a catalogue and answering for it. It is not a security review, not a legal sign-off, and
> it transfers nothing to anything the skill goes on to touch. A governance field that is
> allowed to blur into an authorisation is worse than no field, because it manufactures an
> approval nobody granted. Say which sense you mean, in a comment, in the file.

**Sunset by banner, never by deletion.** When a skill stops being current, set `sunset_date`
and put a deprecation notice at the top of the body saying what replaced it. Leave the file in
place. It is a deliberate record of what was once advised, and someone reading an old artefact
produced by that skill needs to be able to find out what it used to say. Deleting it turns a
superseded answer into an unexplained one.

---

## `risk_factors` is where this stops being a ritual

Most governance metadata is a field somebody filled in once. `risk_factors` is the one that can
carry real information, and it does that only if it holds **three** things:

1. the **specific** residual risk — not "handles data", but the thing that could actually go
   wrong given what this skill does;
2. the **mechanism** that bounds it — the chokepoint, the read-only boundary, the human step
   that cannot be automated away;
3. the **test that asserts the mechanism** — because a mechanism nobody checks is a claim.

A risk field that cites its own test is the difference between governance and its costume. The
block below was adapted from a real one written for a credential scanner. The subject was
replaced with a fictional incident-triage tool; what survived the swap is the three-part
structure, not the example. So the chokepoint it names, redact(), and the test it cites,
test_redaction.py, belong to that imagined tool — neither exists in this toolkit, and what is
being demonstrated is the *shape* of the citation rather than the citation itself:

```
  risk_tier: 2
  risk_factors: >
    Read-only across dashboards and logs; it recommends a page but never sends one, so the
    irreversible step stays with a person. The material risk is disclosure: it reads log
    lines while looking for the failing request, and log lines carry request bodies. Every
    quoted line therefore passes through one redact() chokepoint and is reported as
    source:line plus a field name, never a value -- asserted by test_redaction.py, which
    fails if any code path reaches the reporter without going through it.
```

Read it against the three properties: the risk is *disclosure via the thing the skill exists to
do*, the mechanism is *a single chokepoint with a stated output shape*, and the assertion is
*a named test with the condition it fails on*. Change any one of those to a generality —
"handles sensitive data carefully" — and the field has told the reader nothing they could act
on. Being fictional costs the demonstration nothing, because the property on show is whether the
three parts are *nameable* — and a field that cannot name them fails the same way whatever tool
it describes.

The same block, wrapped differently, is the live `risk_factors` value in
`examples/skills/incident-triage/SKILL.md`, which is what the lint and the eval in this directory
run against. The two copies are gated against each other: `lint_skills.py --self-test` compares
them with whitespace collapsed and fails if they have diverged. A block written down twice with
nothing comparing it is how one copy goes stale while both still read as authoritative — the
failure this pack names elsewhere, and had not applied to itself.

---

## The two checks, and the question each one cannot answer

`lint_skills.py` holds the tree to `skill-schema.json`: required fields present and not
placeholders, description inside budget, `name` and the invocation command agreeing with the
directory where the profile asks for it. It also refuses to report zero coverage as success —
a profile whose containers exist but whose files do not is an error, not a quiet pass.

What it cannot tell you is whether a description is any **good**: whether it would get the
skill chosen at the right moment and left alone at the wrong one. That is a behavioural
property of a model reading prose, so `eval_skills.py` asks a model and counts, over a probe
set you write.

**The non-triggering probes are the hard half.** A skill almost never fires on an unrelated
request; it fires on its *neighbour* — the skill next to it describing adjacent work in shared
vocabulary. Probing with easy negatives reports an accuracy the skill has not earned, because
it measures a confusion nobody was going to make. Every non-triggering probe in
`probes.example.json` is aimed at a sibling and says which one. If you cannot name the
neighbour a probe defends against, that probe is decoration.

Neither check will tell you whether the skill does good work once it has fired. Nothing here
measures that, and a green run must not be read as though it did.

---

## Files

```
skill-schema.json        the contract, as data -- profiles, required fields, the budget you set
SKILL-FRONTMATTER.md     this file; gated against the schema by the lint's self-test
lint_skills.py           holds a tree to the contract, incl. --self-test
eval_skills.py           measures triggering accuracy against a probe file, incl. --self-test
probes.example.json      a worked probe set: three neighbours, negatives aimed at each other
examples/skills/         three example skills the two checks run against
```

`lint_skills.py` needs PyYAML. `eval_skills.py` needs PyYAML always, and the Anthropic SDK plus
an API key only for the half that calls a model — its coverage half and its whole self-test run
offline, with no key and no spend.
