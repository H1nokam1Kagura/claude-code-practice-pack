# Verified against

Every mechanic these documents describe is **observed behaviour, not a documented API contract**.
The permission ordering, the hook semantics, what a keystroke does, how a rules file is triggered —
all of it can change in a release, and none of it announces itself when it does.

So each claim about the harness carries a version and a date. Not because the date makes it true,
but because a reader can see how old it is and go and check.

> This file exists because a claim here had already gone false. The front door asserted that
> double-Esc is "not a rewind" and called the widespread belief a myth. Double-Esc on an empty
> prompt is exactly how you open the rewind menu. Nothing in the document was wrong about the
> *reasoning*; it was wrong about a fact that had moved, and there was no date on it to prompt
> anyone to look. Undated harness claims do not decay visibly — they just quietly become false.

**Verified against Claude Code `2.1.235`, on 2026-08-19**, unless a row says otherwise.

That is a **partial** re-verification, and labelling it as one is the point. Sixteen of the
seventeen pins in `../practice-gate/verified-against.json` were re-read against their sources on
2026-08-19 and carry that date. One does not: the status-line row still says 2026-08-10, because it
was not re-read. It describes a capability nothing in this pack ships, it is the only row here with
no consumer, and it will expire on its own well inside the window. Bumping it along with the rest
would have been a blanket date change wearing the shape of a re-verification, which is the one move
this page forbids. What *was* read first was chosen by what the pack now installs: the permission
floor, the `PreToolUse` rows (the practice-layer installer now installs such a hook), the
settings-layering row (its whole safety design rests on it), the skill-listing and `CLAUDE.md`
loading rows, and the auto-memory rows. **Three of those readings changed a claim.** They are
recorded under the table, worst first.

| Claim | Where | Source | Verified |
|---|---|---|---|
| `Esc` twice on an empty prompt opens the rewind menu; with text in the box it clears the box | front door §3 | [checkpointing](https://code.claude.com/docs/en/checkpointing) | 2026-08-19 |
| Rewind does not cover shell-command file changes or symlinked/hard-linked paths. Subagent edits are **usually** not restored — the exception is a **foreground** forked skill, whose edits happen during your own turn and *are* restored. A background fork, which is the default, is not | front door §3, reversibility §4 | [checkpointing](https://code.claude.com/docs/en/checkpointing) | 2026-08-19 |
| Permission order is `deny → ask → allow`; first match wins and specificity is ignored | front door §2 | [permissions](https://code.claude.com/docs/en/permissions), and separately a replay corpus | 2026-08-19 |
| `deny` and `ask` survive `defaultMode: auto` and `bypassPermissions`; `allow` rules are inert under `bypassPermissions`. One carve-out: neither `deny` nor `ask` applies to `EndConversation` while Claude has another tool it can call | front door §2 | [permission modes](https://code.claude.com/docs/en/permission-modes), and separately measured on host | 2026-08-19 |
| A `PreToolUse` hook can only tighten permissions, never loosen them. Hook decisions do **not** bypass permission rules: a matching deny still blocks and a matching ask still prompts even when the hook returned `allow`. The one direction a hook *does* override is an **allow** rule — exit code 2 stops the call before rules are evaluated at all | front door §2, permission toolkit README | [permissions](https://code.claude.com/docs/en/permissions) | 2026-08-19 |
| Permission rules are per-tool — a floor in one tool's spelling does not bind another; a `Write(path)` rule is accepted and never consulted, and no file rule reaches a script that opens the file itself. A bare `Write` deny with **no path** is a different thing and *is* enforced, at the tool level everywhere | front door §2, permission toolkit README | [permissions](https://code.claude.com/docs/en/permissions) | 2026-08-19 |
| Read and Edit **deny** rules *do* reach the file commands Claude Code recognises in Bash — `cat`, `head`, `tail`, `sed` — and also block Edit and Write on the same path. **Not** NotebookEdit, so a path no tool may change needs its own `Edit` deny. `Read(.env)` and `Read(**/.env)` are equivalent | permission toolkit README, front door §2, `settings.template.json` | [permissions](https://code.claude.com/docs/en/permissions) | 2026-08-19 |
| Compound commands are split into subcommands and every segment must match independently. The recognised separators are **seven, not four**: `&&` `\|\|` `;` `\|` `\|&` `&` and **newlines**. PowerShell splits through its AST | front door §2 | [permissions](https://code.claude.com/docs/en/permissions), and separately a replay corpus | 2026-08-19 |
| A `.claude/rules/*.md` file with a `paths:` glob loads when a matching file is read — on the read, not on every tool use. A rules file with no `paths:` loads unconditionally at launch | front door §2, §5 | [memory](https://code.claude.com/docs/en/memory), and separately measured on host | 2026-08-19 |
| A status line can report context runway, so the handoff point becomes a number | front door §3 | measured on host | 2026-08-10 — **not re-read**, see above |
| A `PreToolUse` hook states a decision by writing `hookSpecificOutput.permissionDecision` to stdout and exiting 0. That field takes **four** values — `allow`, `deny`, `ask`, `escalate` — and the object may also carry `updatedInput`. Exiting 0 with the JSON is the *structured* channel, not the only one: exit code 2 also blocks, ahead of rule evaluation, but reports through stderr and discards the reason. `matcher` matches the tool name, accepts `,` and `\|` alternation, and becomes an unanchored regex once it holds anything else | permission toolkit README | [hooks](https://code.claude.com/docs/en/hooks) | 2026-08-19 |
| `permissions.{deny,ask,allow}` and `defaultMode` live in the settings `permissions` object; managed → command line → local → project → user by priority, and a user, project or local file that fails validation is rejected **whole**. **Managed** settings are the documented exception: a bad entry there is stripped and the rest of the policy still applies | permission toolkit README | [settings](https://code.claude.com/docs/en/settings) | 2026-08-19 |
| A `CLAUDE.md` loads **in full at the start of every session** regardless of length — nothing truncates it; the documented target is under 200 lines. HTML comments are stripped before injection. A project-root file is re-injected after `/compact`; path-scoped rules and nested files are not. An `@path` import is expanded **at launch**, so splitting a long file organises it without reducing what loads | authoring toolkit README, `CLAUDE.md.template` | [memory](https://code.claude.com/docs/en/memory) | 2026-08-19 |
| A skill's **body** loads only on use, while a **listing** of every skill's name and description loads up front. That listing has a budget defaulting to 1 % of the context window, and on overflow descriptions are **dropped**, least-invoked first; each entry's description text is separately truncated at 1,536 characters. Frontmatter `name` is a display label in a personal or project skill (the command comes from the directory) and sets the command only in a bundled one. Outside the CLI just six frontmatter fields are accepted and an unknown **top-level** key is an error, so a governance block survives only nested under `metadata` — where a non-map value is silently dropped. All three of the platform's numbers here are **defaults** and are configurable | `SKILL-FRONTMATTER.md`, `skill-schema.json`, authoring toolkit README, prior art §4 | [skills](https://code.claude.com/docs/en/skills) | 2026-08-19 |
| Auto-memory loads only the first **200 lines or 25 KB** of `MEMORY.md`, whichever comes first; the rest is not loaded. Topic files are never loaded at startup. The store is keyed by **git repository**, so every worktree of one repo shares one directory and index | memory toolkit README | [memory](https://code.claude.com/docs/en/memory) | 2026-08-19 |
| Overflow of that index is **not silent**: a write near a limit returns a reminder to shorten it, and a write over a limit succeeds but returns an **error**. Only the content that loads is measured — frontmatter and block-level HTML comments are stripped first (before v2.1.211 the raw file was measured) | memory toolkit README | [memory](https://code.claude.com/docs/en/memory) | 2026-08-19 |
| `autoMemoryDirectory` relocates the store and `autoMemoryEnabled` / `CLAUDE_CODE_DISABLE_AUTO_MEMORY` switch the feature off. Set in a *project* settings file, the relocation is subject to the same workspace-trust rule as hooks | memory toolkit README | [memory](https://code.claude.com/docs/en/memory) | 2026-08-19 |

> **A claim on this page had gone false again — the rewind row, found 2026-08-19.** It said flatly
> that rewind does not restore *subagent edits*. The checkpointing page still carries a heading
> reading exactly that, and the paragraph under it no longer supports it: whether rewinding restores
> a subagent's edits now **depends on how the subagent runs**. A foreground forked skill edits your
> working tree during your own turn, so its edits are restored like any other; every other subagent,
> including a *background* fork — which is the default — is not. The claim was narrowed rather than
> withdrawn, because the operative case did not move: the shape you actually meet is the background
> one. Note what could not have caught it, because the list is identical to the per-tool case below:
> the sentence carrying the claim never changed, so the marker check stayed green; the pin was four
> days old, so the 180-day rule stayed green. **And note the part that is still open.** Two prose
> sites still carry the flat version — `CODING-WITH-CLAUDE-CODE.md` and `REVERSIBILITY.md`, in its
> checkpoint table — and this page cannot fix them, because the pass that found this owned the
> registry and not the documents. They need the *exception* added, not the sentence deleted.
<!-- -->
> **Two more readings changed a claim, and both were the compression rather than the source.** The
> hook-decision row recorded `permissionDecision` as taking three values. It takes four: `allow`,
> `deny`, `ask`, `escalate` — and the missing one is the useful one, because `ask` is what a guard
> that wants a prompt rather than a block should return, while a reader of the old row would have
> reached for `escalate`. Worse, the same row said "the exit code is not the refusal channel" as an
> absolute, which the hook row four lines above it has contradicted since 2026-08-16: exit code 2
> blocks, ahead of rule evaluation. Two pins describing one mechanism disagreed with each other for
> three days and nothing failed, because no check here can compare two claims to each other. The
> prose the pins point at was already the careful version — the permission toolkit README says the
> exit code is not the *structured* channel and then immediately says a non-zero exit blocks anyway
> — so this was a registry defect and not a document one, which is the direction that is easiest to
> miss: the compression is what the next reader trusts.
>
> The compound-command row is the other. It listed four separators; the source enumerates seven,
> adding `|&`, a bare `&` and **newlines**. Not false, and incomplete in the *safe* direction — more
> splitting means more segments checked, so nothing was under-guarded — but a reader who took the
> list as exhaustive would believe a backgrounded or newline-joined command escaped matching, which
> is the exact opposite of true, and would write a rule on that belief. Three prose sites still say
> four: `CODING-WITH-CLAUDE-CODE.md`, `../claude-permission-toolkit/COMMAND-SHAPE.md`, and
> `../claude-permission-toolkit/README.md` in two places. The pin's marker deliberately stops at
> *"Compound commands split on"* so that it keeps matching all three while they are widened —
> extending it to the separator list would make the pin go stale on the edit that fixes the prose.
<!-- -->
> **Everything else re-read on 2026-08-19 was unchanged**, most of it still verbatim on the page:
> both `Esc` behaviours, the deny-then-ask-then-allow ordering, the deny floor surviving every mode,
> the hook-cannot-loosen-a-deny asymmetry, per-tool rule scoping, the reach of a `Read` deny into
> Bash file commands, whole-file rejection of an invalid settings file, `CLAUDE.md` loading in full,
> all four halves of the skill-listing contract, and all three auto-memory rows. Two rows gained a
> *source* rather than a correction: the permission ordering and the `paths:` trigger were pinned to
> host measurement and are now documented as well, so each is held up by two pieces of evidence with
> uncorrelated failure modes rather than one. Saying "nothing had changed" plainly is worth more
> than manufacturing a correction to make a pass look productive.
<!-- -->
> **The row above is the first one where the lookup changed the rule rather than confirming it.**
> The convention being extracted said a skill description is capped at 1024 characters and that
> this "is what loads into every system prompt". Both halves were wrong in the same direction:
> the number is the author's own convention rather than the platform's, and the mechanism is a
> budgeted *listing*, not the system prompt. That matters because the failure mode inverts — the
> risk is not a file the platform rejects at a hard limit, it is a description quietly dropped to
> make room for another skill's, which no lint can see and no error reports. The shipped budget is
> now labelled a convention on its face, and `skill-schema.json` says so in the file rather than
> leaving a reader to infer a platform rule from a script.
<!-- -->
> **The conflict recorded here on 2026-08-16 is now closed, and it closed in favour of the older
> pin.** The hooks page lists `permissionDecision: "allow"`, which reads as a hook *loosening* a
> decision, and neither pin was edited on a hunch because whether that overrode a deny **rule** —
> as opposed to a prompt — had not been established. The permissions page settles it: *"Hook
> decisions don't bypass permission rules … a matching deny rule blocks the call, and a matching
> ask rule still prompts even when the hook returned `allow`."* So `allow` suppresses the prompt,
> not the floor. Worth keeping the shape of this on the page: the conflict sat open and dated for
> six days rather than being guessed at, which is what *re-verify, do not just bump the date* looks
> like when it is actually followed. One asymmetry arrived with the answer and is easy to get
> backwards — a hook cannot loosen a **deny**, but it *can* override an **allow**, because exit
> code 2 short-circuits ahead of rule evaluation entirely.
<!-- -->
> **And one row above is the case this whole file exists for, arriving a second time.** The
> per-tool row's evidence used to be four rules found by replay, the second of which was
> *"`Read(**/.env)` says nothing about `cat .env`"*. Re-reading the source on 2026-08-16 killed
> that example: a `Read` deny now reaches the Bash file commands. The principle survived, so the
> claim was narrowed rather than withdrawn, the dead example was **retired** from the documents
> instead of reworded, and the test asserting it was renamed and kept to say so. Note what could
> not have caught this. The sentence carrying the claim never changed, so the marker check stayed
> green; the pin was six days old, so the 180-day rule stayed green; nothing failed anywhere. Only
> re-reading the source found it. **A pin makes rot visible to somebody who looks — it does not do
> the looking.**

## How to re-verify

Read the source again, then update the date. **Do not just bump the date** — that silences the
staleness signal without refreshing the claim, which is the exact drift this file exists to catch.

`../Test-PracticeClaims.ps1` enforces four things and cannot enforce a fifth:

1. every pin still points at prose that exists — a pin whose claim was reworded is stale and fails;
2. no pin is older than 180 days;
3. every line carrying a harness keyword, **in every markdown file under `tools/`**, is covered by
   some pin — unless that document is registered as excluded *with the reason it cannot be pinned*;
4. every such exclusion still matches a document that exists, so an exemption cannot outlive the
   file it was written for and be silently inherited by the next file on that path.

Point 3 was an opt-**in** list until 2026-08-16, and the inversion is the more important half of
this file's own lesson. A whitelist fails in the direction nobody notices: a document nobody
remembers to add is exempt from the only check that dates its claims, and it is exempt *silently*,
because a missing entry and a document with nothing to pin look identical. That is not
hypothetical — the memory toolkit's README asserted for months that auto-memory overflow was
silent and unannounced, long after the harness grew a write-time reminder and an over-limit error,
and no pin was ever demanded of it because it had never been listed. Re-measured before the change:
widening the sweep costs three findings, not the fifteen the original narrowing was made against.

Point 3 had a hole of exactly the same shape on the **keyword** side, closed on 2026-08-19. No
keyword covered skill-description or listing-budget vocabulary, so the skills row above was
effectively *voluntary*: its markers matched the prose that happened to exist, and a new undated
claim of that class anywhere under `tools/` would have passed unswept. An absence like that looks
identical to nothing-to-check, which is the whitelist failure arriving one level in. Four keywords
were added — the drop *order*, the listing's character budget, descriptions being dropped or
truncated, and the body-loads-only-on-use asymmetry — and each carries a worked example plus the
near-miss it must **not** fire on, asserted against the live registry by name on every `-SelfTest`
run, so editing a keyword out fails a control instead of silently narrowing the sweep.

Widening cost **four** findings, measured across every markdown file under `tools/` on 2026-08-19.
All four were the same claim quoted in four places — `../claude-authoring-toolkit/README.md`,
`../claude-authoring-toolkit/SKILL-FRONTMATTER.md` twice, and `PRIOR-ART.md` §4, which turns out to
be the only claim about the harness that either of the two newly landed documents makes. Every one
was resolved by adding the sentence it actually uses as a **marker** on the pin that already covers
the claim. None was resolved by rewording the prose to dodge the new keyword: doing that inside the
check is the failure this page exists to catch, wearing a lab coat.

## Attribution carries the same pins

`../practice-gate/prior-art.json` holds the version, date, relationship, claim, citing documents and
reason for each work the pack stands next to, and `../Test-PracticeClaims.ps1` checks it in both
directions — forward, the documents it names must exist and must contain the work's name verbatim;
reverse, an entry nothing cites **fails as stale**. The registry is here for the reason this page is:
a claim about somebody else's repository is a claim about a moving artifact, and it rots the same
silent way, except worse, because attribution *decorates*. Written once for credit, it sits on the
page flattering nobody after the field moves, and nothing else in the gate would ever have gone red
for it. The check refuses to run on an empty or absent registry, because zero attributions and a
pack with nothing to attribute produce the same report.

What it deliberately does **not** do is decide whether a claim is *true*. No script can. It asserts
only that the claim is dated and sourced, which is the property that turns a silent rot into a
visible one and puts a human in front of it. Every correction on this page — the double-`Esc` myth,
the retired `cat .env` example, the flat subagent claim, and the two compressions in the registry —
was found by a person re-reading the source, while every check stayed green.
