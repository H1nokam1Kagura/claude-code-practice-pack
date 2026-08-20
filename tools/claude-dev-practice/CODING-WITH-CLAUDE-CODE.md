# Coding with Claude Code

The front door. Everything here was learned by getting it wrong first, and every claim points at
code in this repo you can go and read.

One idea runs through all of it:

> **A check that could not run must never report PASS, and a guarantee that depends on remembering
> to apply it is not a guarantee.**

Deeper dives: [TESTING-DISCIPLINE.md](TESTING-DISCIPLINE.md) ·
[REVERSIBILITY.md](REVERSIBILITY.md) · [GIT-AND-REVIEW.md](GIT-AND-REVIEW.md)

---

## 1. Decide what the model writes, and what checks it

The single highest-leverage habit. For any task, there is **the work** and **the thing that proves
the work**. Have the model do both, but never in the same breath and never in the same medium.

The pattern that holds up: **a deterministic check the model did not author at the moment it
authored the code.** `build-compliance` splits its scan exactly this way — Phase 2 is a
stdlib Python scan producing `findings.json` with no model judgement at all, so it is reproducible
and diffable; Phase 3 is the model reading for things regex cannot see. The split is what lets a
reviewer trust the numbers, and the skill says so in its own docstring.

Practically:

- **Ask for the assertion before the implementation.** "What would prove this is right?" produces a
  better test than "write tests for this," because the second invites tests shaped like the code
  that was just written.
- **Prefer a check that fails loudly over a check that reports.** A warning is not a gate — see §4.
- **If the model cannot state a failing input, it does not understand the problem yet.** That is
  cheap to ask for and it surfaces confusion immediately.

### Do not let it grade its own homework

An LLM asked "did you do that correctly?" will usually say yes. That is not dishonesty, it is the
question being unanswerable from the inside: the same context that produced the error produces the
evaluation of the error.

What works instead, in rough order of strength:

1. **A deterministic assertion** — exit codes, row counts, a diff, a hash. No judgement involved.
2. **An independent implementation.** Two implementations of the same measurement, gated against
   each other. This repo does it for arbitrary-execution detection:
   `tools/claude-permission-toolkit/check_interpreter_parity.py` gates two independently written
   detectors. When first run, 2026-08-15, they disagreed — 10 grants versus 12 — and *each had
   found something the other missed*. Neither was visible by reading either list.
3. **A fresh context.** If a model must review model output, give the reviewer the artifact and the
   spec, not the conversation that produced it.

**What makes rank 2 work is that the two were written separately** — and that is the part the word
"independent" quietly carries. Two implementations generated from one prompt share priors, so they
agree with each other and are wrong together: you get the comfort of agreement without the coverage
that makes agreement mean anything. A fresh context removes contamination from the conversation; it
does nothing about correlation in the reviewer. So rank reviewers by what actually *varies* between
them, and never gate on a model's own stated confidence — measured on one corpus, the dimensions
carrying the highest self-reported confidence were the least accurate. The full ladder, the
calibration rule, and why an agentic review's finding count is an upper bound rather than a
workload: [GIT-AND-REVIEW.md](GIT-AND-REVIEW.md) §§4–5.

### Treat everything the model reads as untrusted input

Documents, emails, web pages, file names, tool output, another model's output. Any of it can carry
instructions. The question is never "is this content hostile" but **"what could a hostile
instruction here achieve?"** If the answer is "act beyond what the caller is authorised to do," the
fix is at the tool/permission layer, not in the prompt — a prompt cannot defend itself.

---

## 2. Configure the harness, not the conversation

Anything you have to remember to say is not configured. Four surfaces, most durable first.

| Surface | Fires when | Use for |
|---|---|---|
| `settings.json` `deny` / `ask` | Always. Survives `defaultMode: auto` **and** `bypassPermissions` | The floor: unrecoverable and outward-facing actions |
| `PreToolUse` hook | Every matching tool call | Enforcement the rule syntax cannot express. Can only **tighten** |
| `.claude/rules/*.md` with `paths:` | The model reads a file matching the glob | Domain knowledge that only bites in one area |
| `CLAUDE.md` | Every session | The small always-on subset — and nothing else |

**The permission list is not the security boundary; the floor is.** A long `allow` list reads as
caution and usually is not: one `Bash(pwsh *)` entry makes it equivalent to `Bash(*)`, so every
narrow literal beside it excludes nothing. Measured on one real host, 2026-08-10: **2,673 allow
rules, 87% frozen literals, and no `deny` or `ask` key at all** — maximum blast radius, minimum
quiet, no floor. That host has a floor now; the figures are what the *before* looked like, which is
the only reason they are worth quoting. Judge a permission config by its floor, never by its length.

Four mechanics that are easy to get wrong, each of which has bitten:

- Order is `deny → ask → allow`. **First match wins; specificity is ignored.**
- **Rules are per-tool.** A `Write(path)` rule is accepted and never consulted, and no file rule
  reaches a Python or Node script that opens the file itself. A floor in one spelling is half a
  floor. Two refinements read 2026-08-16: a `Read` deny does reach the file commands Claude Code
  recognises in Bash — `cat`, `head`, `tail`, `sed` — and it blocks Edit and Write on that path
  too, but not NotebookEdit, so a path no tool may change needs its own `Edit` deny.
- **`deny` cannot carry exceptions**, so use exact forms. `git push --force*` also swallows
  `--force-with-lease`, which is the *safe* form.
- Compound commands split on `&&` `||` `;` `|` `|&` `&` and **newlines** -- seven separators, not
  the four this line used to name -- and every segment must match independently, so a deny
  spanning a pipe is unreliable. PowerShell splits through its AST. Cross-segment rules belong in a hook, which sees the raw string.

**Validate a floor by replay, not by reading.** `tools/claude-permission-toolkit/` replays a corpus
of previously-approved commands against a candidate ruleset and treats any DENY as a regression.
That caught four rules that all read as obviously correct — including `Bash(rm -rf /*)`, which under
Git Bash denies every absolute path, and `Read(**/*secret*)`, which blocks reading the secret-guard
hook itself. A fifth was retired on 2026-08-16 rather than reworded: `Read(**/.env)` no longer
leaves `cat .env` open to the shell. The bullet above still holds; that particular example of it
does not, which is the ordinary way a harness claim dies.

---

## 3. Context is a resource you spend

Not a container you fill. Three habits, in order of payoff:

- **Load files directly.** `@src/auth/login.ts` costs one read; "find the login function" costs a
  search round-trip plus its output, and the output stays in context.
- **Start fresh at task boundaries.** Carrying a schema dump from an unrelated task into the next
  one inflates every subsequent turn for no benefit.
- **Hand off at a natural boundary rather than compacting at a cliff.** A handoff you write
  deliberately — objective, verified-vs-in-flight status, decisions and why, next actions — beats a
  summary produced under pressure. Keep it as a standing template rather than composing one under
  duress each time. The discipline, starting with the refusal that has to come before any of it, is
  [HANDOFF-PRACTICE.md](../claude-session-toolkit/HANDOFF-PRACTICE.md) §1.

Measure rather than guess. A status line reporting context runway turns "feels slow" into a number,
and a number can have a threshold.

> **Know what the rewind actually restores.** `Esc` twice on an *empty* prompt opens the rewind
> menu; with text in the box it clears the box instead. What it does **not** cover is the part
> worth knowing: **file changes made by shell commands are not tracked**, subagent edits are
> usually not restored, and symlinked or hard-linked paths are **skipped** on restore. The
> subagent half has one exception, added here on 2026-08-19 when re-reading the source found the
> flat version had gone false: a **foreground** forked skill edits during your own turn and its
> changes *are* restored. A background fork is the default, and is not. Put real work in scripts
> the agent then runs — as you should — and rewind covers almost none of your actual mutations. A
> session convenience, not version control. See [REVERSIBILITY.md](REVERSIBILITY.md) §4.

---

## 4. Make the model's output checkable, not just plausible

Fluent wrong output is the characteristic failure, so bias every artifact toward being falsifiable.

- **Cite or don't claim.** `build-compliance` enforces this in code: `scan.py`'s `known_controls()`
  parses the catalog so a finding *cannot* cite a control that does not exist, and anything without
  a source goes to a separate `Unsourced observations` block rather than the verdict table.
- **Say what you did not check.** Every gate here reports SKIPPED as a distinct outcome, and the
  local-CI runner [`Invoke-LocalCI.ps1`](../ci/Invoke-LocalCI.ps1) goes further with
  `INCONCLUSIVE` — "I chose not to run this" (skip) and "it ran and measured nothing" (failure)
  are different states and must not share an exit code. Worth knowing how long that took to land
  everywhere: the distinction was written down, adopted by six tools over the following weeks, and
  the two that kept the skip half without the sharper one were the two whose *whole subject* is
  refusing to call unmeasured coverage clean. A principle spreads by being applied, one file at a
  time, and the files that look like they must already have it are the ones nobody checks.
- **A warning is not a gate.** The sharpest lesson in this repo: a memory-index generator *correctly
  detected* an overflow, printed the diagnosis, and shipped anyway — for weeks. When you add a
  check, make it change the output or fail. Narration is not enforcement.
- **Never credit theatre.** A `SECURITY.md` earns nothing; an enforced gate earns the pass. Its
  mirror image matters just as much: **the continued existence of a valid guard is a PASS, not a
  finding** — an audit that re-flags every guarded hazard as a defect wastes the review and tempts
  someone to "fix" the design.
- **Cost your suggestions, and let them be declined.** `build-compliance` tags each remediation
  `ux_cost: none | low | real`, and a `real` cost must say what it costs. An unstated cost gets
  adopted, degrades the workflow, and teaches the reader to ignore the next suggestion. **Declining
  on cost grounds is a closed outcome**, not an item that reappears every run — a finding that
  cannot be closed by a reasoned "no" is a nag, and nags get muted.

### Assistive by default

Everything above pushes toward enforcement, so be explicit about what is enforced *on whom*. A tool
you build to check your own work should be **assistive**: verdicts name the force of the **rule**,
not the power of the tool ("meets the requirement as written", never "compliant"); a non-binding
source cannot produce a blocking finding; it reports to you, not upward. Build it the other way and
the first person it surprises stops running it, which costs more than the gap it found.

The one thing to stay strict on is the thesis: **a check that could not run must never report
PASS.** That is not in tension with being assistive — an honest SKIPPED is worth more to the person
holding the tool than a green tick.

---

## 5. Write it down where it will be read

Knowledge has exactly one right home, and the wrong home fails silently.

| Kind | Home |
|---|---|
| Always-on rule | `CLAUDE.md` — keep it small; everything here is charged to every session |
| Domain knowledge | `.claude/rules/*.md` with a `paths:` glob — deterministic, file-anchored |
| Procedure | A skill — deterministic *when the skill fires*, and that clause is the whole problem. Triggering is a judgement call, so treat the description as the load-bearing part and measure it: probes that should fire and probes that should **not**, run on a schedule |
| A tool's grain and coverage | The tool itself — see §6. Not your client config |
| Durable lesson | Auto-memory, with **why** and **how to apply** |
| A current count | **Nowhere.** Measure it. A remembered figure is worse than none |

That last row is not fussiness. On one stack a memorised multiplier moved by more than 100× inside
a quarter while the written rule stayed put, and the stale number kept being quoted with confidence.

Two failure modes to design against:

- **An un-gated mirror drifts, silently.** A file outside version control that restates a source of
  truth will diverge, and nothing will tell you. Either gate it in CI or make it a pointer.
- **"Read this when relevant" misses.** It is a judgement call, so it fails quietly. Path globs and
  skill descriptions are hard triggers; prefer them.

---

## 6. The tool surface is an input, and it is the one that fails quietly

Sections 1–5 constrain what the model *writes*. This one constrains what it is allowed to
*believe*, and the failure has no stack trace: a query tool answers the question you asked, so if
the table underneath is at a finer grain than you assumed, the sum is inflated and the tool did
nothing wrong. A plausible number goes into a document and gets quoted for a quarter.

- **Ship the semantic layer with the server, not in your client config.** Grain, coverage and
  join-key rules kept in your own always-on file protect exactly one person. Everyone else who
  connects inherits none of it and cannot know it existed. Put them in the server's `instructions`
  and in a per-tool contract on each tool's metadata, so they travel with the tool.
- **`undeclared` is an honest value.** Declaring grain for the few tools whose numbers can be wrong
  beats claiming all of them were audited — that converts "I should check this" into "someone
  already did", which is *never credit theatre* on a different surface.
- **Advise, don't gate, on the generic escape hatch.** The one tool that can express any query is
  the one that can express the wrong aggregation, so it should carry the grain warning. Gating it
  just teaches people to route around it.

> **This is the only section here with no path to follow.** There is no server in this repository,
> so nothing above can be read as code the way §§1–5 can. Treat it as the weakest-evidenced part of
> the document and hold it to that standard — it is here because the failure it names is expensive
> and absent from the rest, not because it is proven.
