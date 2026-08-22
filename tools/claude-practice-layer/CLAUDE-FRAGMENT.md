# Always-on instructions — fragment

**Paste this into your own always-on project file, or keep it beside one.** It carries only the
always-on subset: rules that have to be in context before anything is opened, because they bite in
a session that never opens a matching file at all — in a second repository, in a scratch script, or
in a turn that only ever queries a tool and reads no file.

Nothing else belongs here. An always-on file is charged to every task including the ones it has
nothing to do with, so the table below is the deliverable and the four rules under it are the
exception that earned a place beside it.

**Why this file is named with an `.md` extension.** Content gates on this kind of tree are
extension-scoped, so a file whose extension is not in the scan list ships unexamined and reports
exactly like a clean one. A `.fragment` suffix would buy a tidier name and an unscanned file. The
registry note in `tools/practice-gate/share-pack.json` records the same lesson being learned once
already, on a template, and the resolution taken then: widen the scan rather than accept the hole.
Keep the extension in the scan list, and if you rename this file, rename it to something scanned.

---

## Where the substance lives

| What | Where | Loads when |
|---|---|---|
| Verifying a claim before making it | `tools/claude-practice-layer/skills/verification-before-claiming/SKILL.md` | the request is about whether something is actually true |
| Anything that destroys or overwrites | `tools/claude-practice-layer/skills/reversibility-before-destructive/SKILL.md` | the request names a delete, an overwrite or a bulk write |
| Ending a session cleanly | `tools/claude-practice-layer/skills/handoff-discipline/SKILL.md` | the request is to hand work over |
| Deciding what changed, and whether to keep it | `tools/claude-practice-layer/skills/git-comparison-choice/SKILL.md` | the request compares branches or asks what landed |
| Command authoring and the permission floor | `tools/claude-permission-toolkit/COMMAND-SHAPE.md` | you touch a settings file or author a shell call |
| The reasoning behind all of it | `tools/claude-dev-practice/CODING-WITH-CLAUDE-CODE.md` | read it once, then point at it |
| Any current count, threshold or percentage | nowhere in this file, deliberately | measure it, every time |

Domain knowledge belongs in a rules file scoped by path glob, not here. How that scoping behaves,
and the version it was last checked against, live in
`tools/claude-dev-practice/CODING-WITH-CLAUDE-CODE.md` and its dated entry beside it -- this file
deliberately does not restate either. A copied claim about the tool's own behaviour is a claim
nobody will find when the original is re-checked, so it goes stale silently while the copy that
is gated stays honest. By contrast a pointer that says "read this when relevant" is a judgement
call, and it misses without saying so.

---

## Command shape

Operational logic goes in a script file, invoked as one command with the interpreter and the path.
Never assemble a multi-statement body inside the call string: the approval you are granted is
recorded in the shape you asked for it, so a pasted body becomes a rule carrying a timestamp or a
local path, and it will not match anything again. Prefer the dedicated file tools — read, search,
glob, edit — over their shell equivalents, because they leave no rule behind at all.

Why this cannot live behind a gate: it applies to the first command of a session, before any file
has been opened, and its cost is invisible at the moment it is paid. The mechanism, the measured
consequence and the indirect way to check it are in `tools/claude-permission-toolkit/COMMAND-SHAPE.md`.

---

## Evidence before assertion

A statement about a named thing — a system, a file, a version, a figure — carries the source it came
from, or it does not go in the answer. Where a tool can answer the question, that tool is the only
authorised route; if it returns nothing, the fact does not exist for this turn. It is never
back-filled from recall or from a plausible neighbour.

What cannot be sourced still gets written down, in its own block, marked unverified. Moving it there
is the cheap outcome; asserting it is the expensive one. This rule outranks tone: being direct,
declining to hedge and pushing for a number are all instructions about style, and none of them
licenses a claim with no source behind it. Persona pressure is the failure path, which is why the
rule is here rather than in a file that loads later.

The independence ladder, and why a model asked to check its own work agrees with itself, are in
`tools/claude-practice-layer/skills/verification-before-claiming/SKILL.md`.

---

## Memory and context hygiene

Each kind of knowledge has exactly one home, and the wrong home fails without complaining. An
always-on rule here; domain knowledge in a path-scoped rules file; a procedure in a skill; a durable
lesson in memory, with the reason and the way to apply it. Before writing a memory, supersede the
one it replaces rather than settling beside it — a second entry on the same subject is the defect
that compounds fastest.

A volatile figure has no home. Never quote a count, a coverage percentage or a multiplier from
recall, and never a percentage without saying what it was measured over. Re-measure instead; a
remembered number is worse than no number, because it arrives with confidence attached. The curation
pass that keeps this true is `tools/claude-session-toolkit/MEMORY-TENDING.md`.

---

## Autonomous execution

Given a multi-step task, build the list of steps first, then work through it without stopping to ask
for permission to continue. Validate each step before marking it done, and validate on something
external: an exit status, a row count, a re-read of the thing that was supposed to change. A step is
not done because the command that performed it returned successfully.

Stop on a genuine failure, or on a decision only a person can take. Do not stop to narrate progress.
Where the step was destructive, the four-step shape in `tools/claude-dev-practice/REVERSIBILITY.md`
replaces this rule with a stricter one.

---

## Why this file stays short

An always-on file is usually host configuration: outside the tree it describes, unreadable by any
build, and impossible to compare against the system it documents. So a rule kept here drifts in
silence, and afterwards both copies read as authoritative with nothing between them. That is the
argument for the table at the top, and it is not an argument about tidiness.

Then check it, because a convention with nothing enforcing it decays:

```bash
python check_pointer_file.py CLAUDE.md --rules-dir <your gated rules directory>
```

`tools/claude-authoring-toolkit/check_pointer_file.py` holds three properties — every pointer
resolves, no line here restates a gated one, and the file is inside a budget you chose. It cannot
tell you whether a rule belongs here. Nothing can, and that judgement stays yours.
