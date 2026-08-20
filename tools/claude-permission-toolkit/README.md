# claude-permission-toolkit

A stdlib-only toolkit for **validating a Claude Code permission floor by replay rather than by
reading** — because a ruleset cannot be reviewed by looking at it. It ships a floor to start from
and the guard that enforces what rule syntax cannot express, alongside the validators, the parity
checks that hold the duplicated pieces to each other, and the suites that hold all of it to its
claims.

---

## The problem it solves

Every permission rule reads as reasonable in isolation. What matters is what the whole set does to
the commands you actually run, and that is an interaction between wildcard shapes, per-tool
spelling, compound-command splitting and first-match-wins ordering. Reading finds none of it.

Four rules that all looked obviously correct written down, and each broke a real workflow:

| Rule | What it actually did |
|---|---|
| `Bash(rm -rf /*)` | Under Git Bash **every** absolute path begins with `/`, so this denies ordinary scratch deletes, not just root |
| `Bash(git push --force*)` | The no-space wildcard also swallows `--force-with-lease`, the *safe* form |
| `Read(**/*secret*)` | Blocks reading the secret-guard hook itself, i.e. the guard |
| `Read(**/.env.*)` | Blocks `.env.example`, which is a template, not a secret |

Each was found by replay in seconds. None was visible by inspection.

A fifth sat in that table until 2026-08-16: `Read(**/.env)` says nothing about `cat .env`. It no
longer holds — a `Read` deny now reaches the file commands Claude Code recognises in Bash — so it
has been retired from the list rather than restated. The principle it illustrated survives, the
worked example died, and the case is kept in `test_replay.py` as what it has become: a statement
about what the matcher models, not about a floor that fails to bind.

The companion insight, and the one that reorders the whole problem: **a long `allow` list is not a
security boundary.** One `Bash(pwsh *)` entry makes the list equivalent to `Bash(*)`, so every
narrow literal beside it excludes nothing. Measured on one real host, 2026-08-10: 2,673 allow
rules, 87% frozen literals with no wildcard, and **no `deny` or `ask` key at all** — the keys were
absent, not short. Maximum blast radius, minimum quiet, no floor. Judge a config by its floor.

---

## What's in it

### `replay_permissions.py`

Takes a corpus of invocations that were previously approved, replays it against a **candidate**
ruleset, and treats any DENY as a regression. A before/after diff on real traffic.

```
python replay_permissions.py --candidate settings.json --corpus settings.local.json.bak
python replay_permissions.py --candidate settings.json --corpus approved.txt --format json
python replay_permissions.py --candidate settings.json --corpus c.json --explain "rm -rf /tmp/x"
```

Your own `settings.local.json` backup is the corpus you already have: it is a record of commands
somebody approved, which is exactly the traffic a new floor must not break.

**Exit contract**

```
0  every corpus entry replayed; nothing denied
1  at least one previously-approved invocation is now DENIED  (a regression)
2  replayed, but at least one entry could not be PARSED -- SKIPPED, never a pass
```

Exit 2 is the load-bearing one. A corpus that failed to parse and reported success would be a
validator that validated nothing, which is worse than not running it.

> **It models the rules literally and per tool, so it now UNDER-predicts denials.** As of
> 2026-08-16 a `Read` deny also reaches the file commands Claude Code recognises in Bash — `cat`,
> `head`, `tail`, `sed` — and the matcher does not model that layer: it reports `cat .env` as
> ALLOW where the live harness blocks it. That is the safe direction for a regression detector,
> whose job is to catch traffic a candidate floor would break — it can miss a denial, it cannot
> invent one — but it is a limit, not a feature. Two things follow. An `ALLOW` here is not
> permission to leave the shell spelling out of the floor, because the coverage you would be
> relying on is the harness's and not your rule's. And a floor that replays clean can still deny
> something in production, so read this tool as a lower bound on denials rather than a complete
> account of them.

### `check_interpreter_parity.py`

Gates two independently written detectors of *"does this rule grant arbitrary execution?"* against
each other. On its first run, 2026-08-15, against a 111-rule allow-list taken from a live host
settings file, one found 10 interpreter grants and the other 12 — and **each had found something
the other missed**. Neither gap was visible by reading either list.

This is the cheapest high-value test available wherever duplication is deliberate: keep the copies,
gate the copies.

> **It needs both copies, and only one of them is in this toolkit.** The second detector lives in a
> separate skill in the source repository. Run from a distribution containing just this directory,
> the script exits **2** and says it did not apply — it will not report a parity it could not
> measure. Exit **1** is reserved for the two real failures: the detectors diverged, or both files
> were present and one would not import.

### `test_replay.py`

Includes `TestKnownWorkflowBreakers` — the four rules above, each now a named test with its story in
the docstring. If any of them starts passing, the matcher has drifted toward intuition and away from
the harness. The retired fifth case sits in the same class, inverted: its assertion is unchanged and
its docstring records why it is no longer evidence of a floor that fails to bind.

```
python -m unittest discover -s . -p "test_*.py"
```

---

## Mechanics these tools model

Each of these is a dated claim about the harness, and the dates are **not kept here** -- they live
once, in [`../claude-dev-practice/VERIFIED-AGAINST.md`](../claude-dev-practice/VERIFIED-AGAINST.md),
with the source each was last read against. A date copied to a second page is a date nobody
updates: this list carried 2026-08-10 for nine days after two of the claims below had been
re-read and one of them corrected.

- Order is `deny` → `ask` → `allow`. **First match wins; specificity is ignored.**
- `deny` and `ask` survive `defaultMode: auto` **and** `bypassPermissions`. They are the only
  durable constraint; `allow` is noise reduction.
- **Rules are per-tool.** A floor written in one tool's spelling is half a floor: a `Write(path)`
  rule is accepted and never consulted, and no file rule reaches a Python or Node script that opens
  the file itself. Two refinements read 2026-08-16, both of which cut against the intuition: a
  `Read` deny *does* reach the file commands Claude Code recognises in Bash — `cat`, `head`,
  `tail`, `sed` — and it also blocks Edit and Write on the same path, including creating a file
  there. It does not block NotebookEdit, which is why the shipped floor now spells the secret paths
  out in `Edit(...)` as well.
- **`deny` cannot carry exceptions.** Write exact forms: `git push --force*` also swallows
  `--force-with-lease`, which is the *safe* form.
- Compound commands split on `&&` `||` `;` `|` `|&` `&` and newlines -- **seven separators, not the
  four this list used to name** -- and **every segment must match independently**, so a deny
  spanning a pipe is unreliable. Cross-segment patterns belong in a `PreToolUse` hook, which sees
  the raw string.
- A `PreToolUse` hook can only **tighten**. The working pattern is broad allow + hook-enforced deny.
- Every approval is recorded as a rule shaped like the command approved, so an inline multi-statement
  body becomes a literal that can never match twice. See [`COMMAND-SHAPE.md`](COMMAND-SHAPE.md) —
  that is the authoring convention this floor assumes.

---

### `settings.template.json`

A floor to start from, because a toolkit that can only *measure* a floor and ships none is half a
toolkit. Derived from a floor running on a real host, then de-identified — not invented for the
occasion.

It carries `permissions.deny`, `permissions.ask`, and the hook wiring. It carries **no
`mcpServers` block, no `env`, no credentials, and no working directories** — those are exactly
where a live settings file keeps its secrets, and a template that ships them once will ship them
always.

**`allow` is empty, on purpose, and that is the argument rather than an omission.** A starter
allow-list would contradict the paragraph above: one interpreter entry makes the whole list
equivalent to `Bash(*)`, so length buys nothing and a curated list mostly buys false confidence.
What you want from someone else's config is their floor. Build your allow-list from your own
measured traffic, and check it with `replay_permissions.py`.

Two edits before it will run:

1. `<<HOOKS_DIR>>` in the hook command — point it at wherever you put the guard.
2. Decide your own `defaultMode`. The template omits it deliberately: the floor is what makes a
   permissive mode survivable, so that choice should be made after you have replayed your own
   corpus, not inherited from a stranger.

Deny entries are written in **both tool spellings** throughout. That is not thoroughness, it is
the minimum: rules are per-tool, and a floor written in one spelling is decorative. `git push
--force` is spelled out longhand rather than as `--force*`, because the no-space wildcard also
swallows `--force-with-lease`, which is the safe form.

Every secret path is denied twice for the same reason, once to `Read` and once to `Edit`. A `Read`
deny already covers the Edit and Write tools on that path, including creating a file there, but it
does not cover NotebookEdit — so without the `Edit` line the key material a floor exists to protect
is unreadable and still writable, which is a gap nobody would write down on purpose.

Some of what a real floor needs cannot be shipped: the host this came from also denies a specific
container prefix, promoting a prose instruction into an enforced one. That trick generalises and
the instance does not — add your own.

### `secret-guard.ps1` and `secret_guard.py`

The enforcement half of broad-allow-plus-hook-deny, which this toolkit had until now described and
not shipped. It is a `PreToolUse` hook that blocks commands which would leak a secret: an inlined
vendor PAT, `put-secret --string-value <literal>`, an emit verb next to a secret-named variable,
and PowerShell's value-emitting `($var = ...)`.

The reason enforcement lives in a hook at all is structural. Compound commands split on `&&` `||` `;` `|`
`|&` `&` and newlines, and every segment is matched independently, so no permission rule can
express a pattern that spans a pipe. A hook is handed the raw string before any of that happens.

Both copies refuse a command by writing `hookSpecificOutput.permissionDecision` to stdout and then
**exiting 0**. The exit code is not the refusal channel — a non-zero exit also blocks, but it
reports through stderr and throws away the structured reason, which is the part the user reads.
Every failure path exits 0 and allows the call, so a broken guard is a silent one; that is what
`check_guard_parity.py` is for.

**Its limits are on its face, in its header, and in `guard-probes.json` as executable facts** —
six of them, led by the one that stings most: **pipe-to-shell is not covered.** `curl … | sh`
passes. That is precisely the shape a hook *could* catch and a permission rule cannot; this guard
is scoped to secret leakage and stops there. Recording each gap as a passing probe rather than as
a sentence means the day one closes, the gate goes red and somebody has to come and say so.

It ships **twice** — PowerShell because that is where it was written and proven, Python because a
recipient without `pwsh` should still get the enforcement half. `check_guard_parity.py` runs every
probe through both and requires them to agree **and** to be right, because two implementations
that agree with each other and disagree with the specification are one wrong guard with a spare.

> **One correction travelled with the lift.** The original told the user, in its own block message,
> to emit `.Length` or `[bool]$env:X` instead of a value — and blocked both. Its
> `(?!\.(Length|Count))` lookahead sat after a greedy character class, so the engine gave back one
> character of the variable name and matched anyway; _measured 2026-08-16_, `Write-Host
> $env:DB_PASSWORD.Length` was denied. A guard that blocks its own remediation advice teaches one
> lesson only — reach for the override — so this copy strips the provably-safe uses before testing
> instead. It is the kind of defect no amount of reading finds and one probe finds immediately.

## What's intentionally left out

- **Any real ruleset.** A live `settings.json` carries endpoints and credentials. Bring your own —
  and `settings.template.json` is a floor, not a ruleset.
- **Pipe-to-shell detection**, and the five other guard gaps. Stated above, and asserted in
  `guard-probes.json` rather than only described.

## Files

```
COMMAND-SHAPE.md              why how you spell a command decides whether it can be audited
settings.template.json        a floor to start from -- deny/ask + hooks, no secrets, no allow
secret-guard.ps1              the PreToolUse guard, PowerShell
secret_guard.py               the same guard, portable
guard-probes.json             one shared specification for both, incl. the known gaps
replay_permissions.py         the replay validator
check_interpreter_parity.py   two arbitrary-execution detectors, gated against each other
check_guard_parity.py         the two guards, gated against each other
test_replay.py                the matcher suite, incl. the four workflow breakers
test_secret_guard.py          the guard suite
test_template_floor.py        the template's acceptance test, run in both polarities
corpus/approved.example.txt   ordinary traffic the floor must not break
```

Run everything:

```
python test_replay.py && python test_secret_guard.py && python test_template_floor.py
python check_guard_parity.py        # 0 agree · 1 diverge or wrong · 2 no pwsh, so not measured
python check_interpreter_parity.py  # needs the full source repository; 2 says so plainly
```

### A limit worth knowing about this directory

The `.md` files here are swept for undated claims about the harness. `settings.template.json`,
the two guards and `guard-probes.json` are **not** — they are not markdown, and widening that
sweep to code produced far more false alarms than findings. So the harness behaviour they depend
on is pinned through the prose above rather than through the files themselves. If you change what
the template or the guards assume about Claude Code, the pin to update is in the practice
documents' `VERIFIED-AGAINST.md`, not here.

Requires Python 3.8+, matching what `replay_permissions.py` declares. Stdlib only, no network.
(The memory toolkit states 3.6+ — a lower floor, because it uses no f-strings. Each toolkit states
the floor its own code actually needs rather than one number for the set.)
