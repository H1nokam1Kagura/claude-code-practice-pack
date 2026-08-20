# Command shape

**How you spell a command decides whether anyone can ever audit it.** That reads like style advice.
It is not: it falls directly out of the matching model in `replay_permissions.py`, and it is the
convention the floor in `settings.template.json` assumes.

---

## The mechanism

Compound commands split on `&&` `||` `;` `|` `|&` `&` and newlines -- seven separators -- and
every segment must match independently; PowerShell splits through its AST. Two
consequences, and the second is the one nobody sees coming:

1. A rule cannot span a pipe. Cross-segment patterns belong in a `PreToolUse` hook, which is handed
   the raw string before any of this happens — that is what `secret-guard.ps1` is.
2. **Every approval you grant is recorded as a rule shaped like the command you approved.** Approve
   a three-statement one-liner and you have added a three-statement literal to your config.

Rule 2 is where configs go to die. A pasted script body is a rule that **can never match twice** —
it contains a timestamp, a path, an inline variable, something. So the next near-identical command
prompts again, and adds another literal. The list grows without ever getting quieter, and nothing
in it is reviewable.

_Measured on one host, 2026-08-10:_ the PowerShell tool alone had generated 1,235 permission
literals — 44% compound, 43% over 120 characters, the longest 800, and 341 of them opening on the
`&` call operator. None of those can match a second command. None is auditable by reading.

---

## The rules

**Operational logic goes in a script file**, invoked `pwsh -NoProfile -File <path> -Args …` or
`python <path> …`. One segment, one stable prefix, one rule that matches every future run. Never
paste a multi-statement body into the command string. Write the file first, then invoke it — this
is also the only version of the work that a reviewer can read in a diff.

**One command per call.** No `$var=…;` preamble followed by a second statement. Both halves are
recorded as standalone rules, and a rule that is nothing but somebody's local path
(`PowerShell($m='C:/Users/you/some-repo')` — a real recorded rule, with the path changed) will
never match anything again. Use the literal value inline.

**No call operator, and no decorative tail.** `&`, and trailing `| Select-Object` / `| Format-Table`
/ `2>&1` when the value is already being returned, add segments that must each match. They buy
formatting and cost matchability.

**Prefer the dedicated tools.** Read / Grep / Glob / Edit over `Get-Content`, `Select-String`,
`Get-ChildItem`, `cat`, `grep`, `sed`. They generate no permission rules at all, so the cheapest
command shape is the one that never touches the shell.

**Never inline a secret-bearing variable.** The guard blocks the obvious forms, and an 800-character
body is precisely where the unobvious ones hide. This is the rule the other four exist to make
enforceable: a guard can only inspect what it can parse, and nobody — human or otherwise — parses
an 800-character line.

---

## What it actually buys

**Auditability, not quiet.** This is worth being blunt about, because the intuitive reason to adopt
the convention is the wrong one. If your config grants a command tool broadly — and the argument in
[`README.md`](README.md) is that a long allow-list has already granted it, whether or not it says so
— then shape buys you no reduction in prompts at all. The floor is doing the safety work. Shape is
what keeps the broad grant **reviewable**, so that six months later somebody can read the list and
form a judgement about it.

A permission list nobody can survey is a security weakness in its own right. You cannot audit what
you cannot read, and a list the size of the one measured above is not a thing anyone reads.

---

## The check

There is no script for this one, and that is worth stating rather than leaving you to notice.
Command shape is a property of how commands are *authored*, and the artifact it damages — an
accumulating local settings file — is the same artifact `replay_permissions.py` treats as a corpus.

So measure it the indirect way: run your accumulated approvals through the replay validator and read
the **NOT EXERCISED** section. A rule that never fires, in a corpus drawn from your own traffic, is
usually a rule shaped like a command that could not recur. Count how many. That number is this
document's real metric.

```
python replay_permissions.py --candidate settings.template.json --corpus your-settings.local.json
```
