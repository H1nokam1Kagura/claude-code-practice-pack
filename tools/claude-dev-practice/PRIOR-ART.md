# Prior art

This pack is not the first serious attempt at disciplined agentic coding, and publishing it without
saying so would be the one claim in it that nobody could check. So: what already exists, what this
pack takes from the same conclusions, and the one place it deliberately differs.

The rule the rest of the pack applies to claims about the harness applies here too, and it is the
whole reason this page can be trusted a year from now. **A claim about somebody else's work is a
claim about a moving artifact.** Their repository gets a release the week after this is written;
their guidance gets corrected; a skill gets renamed. So every statement below carries the version
or state it was read at and the date it was read, exactly as
[VERIFIED-AGAINST.md](VERIFIED-AGAINST.md) demands of claims about Claude Code. An undated
description of another project is not a citation, it is a memory.

---

## 1. What was read, and when

Only works actually fetched and read are named. Each has an entry in
`../practice-gate/prior-art.json`, which is checked in both directions: a work named here without an
entry fails, and an entry naming a document that no longer cites it fails as stale.

| Work | What it is | Version / state read | Read |
|---|---|---|---|
| [obra/superpowers](https://github.com/obra/superpowers) | "An agentic skills framework & software development methodology that works" — a workflow methodology shipped as auto-triggering skills through a plugin marketplace. MIT. Widely adopted: 274,133 stars at the time of reading | Release **v6.3.0**, published 2026-08-12. Its plugin manifest reads `6.3.0` and the default branch was level with that tag — zero commits ahead — so the release and the tip were the same artifact | 2026-08-19 |
| [Best practices for Claude Code](https://code.claude.com/docs/en/best-practices) | Anthropic's own guidance on working with the tool: verification, plan-then-code, prompt specificity, configuring the environment, parallel sessions | A living documentation page. It carries **no version and no date**, which is worth stating rather than glossing — it is the same hazard this pack pins against, met in the vendor's own material | 2026-08-19 |
| [Writing effective tools for agents — with agents](https://www.anthropic.com/engineering/writing-tools-for-agents) | Anthropic engineering post on tool design for agents: fewer and higher-impact tools, namespacing, returning high-signal context, token efficiency, and evaluating tools rather than assuming them | Dated by its publisher: 2025-09-11 | 2026-08-19 |

There is more in this space than three works — plugin marketplaces, agent-team frameworks, competing
skill libraries. These three are named because they were read end to end, and naming a fourth from
reputation would be the exact failure this page exists to avoid.

---

## 2. Different layer, not a competitor

Read superpowers' own description of its workflow and the boundary is obvious. Its skills fire in
order — brainstorming, then a git worktree, then a written plan, then subagent-driven execution with
two-stage review, then RED-GREEN-REFACTOR test-first implementation, then code review, then
finishing the branch (README, v6.3.0, read 2026-08-19). Every one of those is an instruction to the
model about **what to do next**, carried in the model's context and enforced by the model choosing
to comply. Its own words for that: "Mandatory workflows, not suggestions."

This pack is the layer underneath, and it assumes compliance is not available. Nothing here tells
the model what order to work in. `../Test-PracticeClaims.ps1` resolves every citation, dates every
figure, and demands a version-and-date pin for every claim about the harness; the registries beside
it record each exemption with the reason it exists; `../claude-worktree-toolkit/wt.ps1` refuses
destructive operations by construction rather than by asking nicely.

| | superpowers | this pack |
|---|---|---|
| Enforced by | Skill instructions the model reads and follows | Scripts, hooks and a permission floor that run whether or not the model cooperates |
| Failure mode it targets | Skipping a step — coding before designing, writing code before a failing test | A check that reports PASS having measured nothing, and a claim that quietly went false |
| Unit of work | A skill that triggers on a situation | A registry entry that must still be cited, and an assertion that must still fail when broken |
| Where it lives | The model's context | The tree, the gate, and CI |

They compose, and the composition is the interesting configuration: a workflow layer that decides
what to build next, sitting on a verification layer that will not let either of you declare it done
on narration. Neither replaces the other. A methodology with no gate underneath it is a set of
habits; a gate with no methodology above it tells you nothing about what to build.

---

## 3. Convergence, and why it is the strongest evidence here

Three separate agreements, across three works, and they are worth more than anything any one of them
asserts alone.

**Untracked files are not recoverable, so a teardown must stop and ask.** The v6.3.0 release notes
record: *"Worktree removal no longer destroys untracked files. When `git worktree remove` refuses
because the tree holds uncommitted work, the skill stops, names the files, and asks — instead of
reaching for `--force`."* (read 2026-08-19). That is, independently, the conclusion of
[REVERSIBILITY.md](REVERSIBILITY.md) §§5-6 — gate the irreversible rather than the routine, and
prove the set before the destructive step — and it is the shape already shipped in
`../claude-worktree-toolkit/README.md`: a dirty tree is refused unless the override is passed, the
refusal **names the untracked files individually because those exist nowhere else and are in no
reflog**, and holding another live session's tree is a *separate* switch from discarding your own
work. The one safety primitive that toolkit kept when the rest of a more aggressive private setup was
deliberately left out is the non-destructive in-use probe. Same rule, same reasoning, two codebases
that had never read each other.

**Evidence outranks assertion.** Superpowers' stated philosophy includes *"Evidence over claims -
Verify before declaring success"* (README, read 2026-08-19). This pack's thesis sentence is *"a
check that could not run must never report PASS."* Anthropic's own best-practices page arrives from
a third direction, naming "the trust-then-verify gap" as a common failure and advising that Claude
"show evidence rather than asserting success" (read 2026-08-19). Three works, three vocabularies,
one rule.

**The tool surface is an input.** The third work, from a different angle again: Anthropic's tools
post (2025-09-11, read 2026-08-19) argues for fewer and higher-impact tools, namespaced so an agent
cannot confuse them, returning "only high signal information back to agents", and — the part that
matters here — **evaluated** rather than assumed correct. That is
[CODING-WITH-CLAUDE-CODE.md](CODING-WITH-CLAUDE-CODE.md) §6 in another vocabulary: the tool surface
is an input, and it is the one that fails quietly.

**Why the agreements matter, and exactly how much.** [GIT-AND-REVIEW.md](GIT-AND-REVIEW.md) §4 is
the reason to count them rather than merely enjoy them: two checks are worth gating against each
other only to
the extent their mistakes are independent, and what buys independence is **separate authorship**,
not a fresh window. These conclusions were reached by different authors, on different stacks, in
different languages, against different failures. Their errors are close to uncorrelated, which is
what makes agreement informative — two documents generated from one prompt would have agreed too,
and it would have meant nothing.

The same section bounds the claim, so it belongs here too. That ranking puts a **deterministic
assertion** above every form of judgement, agreeing judgements included. Three projects converging
raises confidence that the rule is real; it does not make the rule enforced. What enforces it is the
assertion, which is why this pack's answer to its own convergence was to write
`../claude-worktree-toolkit/Test-WorktreeMergedness.ps1` rather than to write it down more firmly.

---

## 4. Where this pack differs: claim hygiene, not correctness

The one real distinction, stated as narrowly as the evidence supports. It is **not** a criticism of
superpowers' advice, most of which this pack agrees with.

Its writing-skills skill makes several claims about the internals of the tools it runs on: that
skill frontmatter has a maximum of "1024 characters total" — for which it does cite a specification
— that a description should "Keep under 500 characters if possible", that skills should hold to
per-category word budgets, and that some skills "load into EVERY conversation". Read at v6.3.0 on
2026-08-19, **none of those claims carries a version or a date.** The only ISO date in that file
sits inside an illustrative quotation, not on a claim. So a reader cannot tell whether the numbers
were checked last week or eighteen months ago, and neither can the author.

This pack has the receipt for why that is the failure mode rather than a stylistic preference,
because it is the failure mode it walked into. **This pack's own** convention asserted a
1024-character cap on a skill description, and that this was what loaded into every system prompt.
Measurement killed both halves. The number was the author's own convention rather than the
platform's, and the
mechanism is a budgeted **listing** in which descriptions are *dropped, least-invoked first*, to
make room — which no lint can see, no error reports, and no amount of re-reading the convention
would have found. The correction, what it cost, and the two later cases where re-reading a source
killed a shipped example are in [VERIFIED-AGAINST.md](VERIFIED-AGAINST.md), with the pins in
`../practice-gate/verified-against.json`.

Note precisely what the difference is and is not. Their guidance may well be entirely correct today;
several of those numbers are plausible and one is sourced. The difference is that nothing dates
them, so **rot is invisible instead of visible** — and undated claims about a tool's internals do
not decay loudly, they just quietly stop being true while the sentence carrying them never changes.

And the honest counterweight, which this pack owes because it is the one making the argument: a date
is not truth. Both corrections recorded in [VERIFIED-AGAINST.md](VERIFIED-AGAINST.md) were found by
a person re-reading the source while every automated check stayed green. A pin makes rot visible to
somebody who looks; it does not do the looking.

---

## 5. What this page does not claim

Not a survey, and not a comparison of quality. It positions one layer against work on an adjacent
one, records what was read and when, and nothing more.

It is also not decoration, which is the specific way an attribution section rots: it gets written
once, the field moves, and it sits there flattering nobody. So it is wired to the same gate as every
other claim in this pack. `../practice-gate/prior-art.json` requires, per entry, the version read,
the date read, the relationship claimed, the specific thing being attributed, the documents citing
it, and the reason the entry exists — and it is checked in both directions, so an entry that has
stopped being cited fails as stale rather than persisting quietly. Re-checking means fetching the
work again and then updating the date. Bumping the date on its own is the drift, not the fix.
