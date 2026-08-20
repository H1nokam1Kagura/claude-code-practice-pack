# claude-code-practice-pack

Practice, tooling and gates for coding with Claude Code — the verification layer, not the workflow
layer, and every claim in it dated against the version it was checked on.

- [How it works](#how-it-works)
- [Installation](#installation)
- [The basic workflow](#the-basic-workflow)
- [What's inside](#whats-inside)
- [Philosophy](#philosophy)
- [Prior art](#prior-art)
- [What this does not do](#what-this-does-not-do)
- [Contributing](#contributing)
- [Updating](#updating)
- [License](#license)

## How it works

An agentic coding tool fails differently from a compiler. It does not usually stop; it produces
something fluent and plausible, and the cost lands later, in a number somebody quotes for a quarter
or a backup that archived a single symlink and exited 0.

So this pack is not advice about prompting. It is the layer underneath: a permission floor and a
hook that act whether or not anyone remembers them, gates that refuse to report PASS for a check
that could not run, validators that replay a real corpus rather than reading a ruleset, and a set of
essays that exist because each of those was learned the expensive way first.

Two properties are worth knowing before you read anything else.

**Every claim about the tool's own behaviour carries a version and a date.** Those mechanics are
observed behaviour, not a documented API contract, and none of them announces itself when it
changes. `tools/claude-dev-practice/VERIFIED-AGAINST.md` is the register, and it exists because a
claim in these documents had already gone false. One went false again during the last pass — the
correction is on that page, along with the note that nothing except re-reading the source could have
caught it.

**The gates are run against this pack, not just shipped with it.** Three of them hold these
documents to their own standard: that a cited path resolves, that a measurement-shaped figure is
dated, that a forbidding pattern still matches its own worked example. If a document here says a
thing is enforced, you can go and read the enforcement.

## Installation

Nothing needs installing to *read* the practice documents — they are prose, and that is most of the
pack. The parts that install are the ones that have to bind.

Requirements are stated per component rather than up front, because they differ: the Python is
stdlib-only, and the PowerShell needs **pwsh 7** and was developed and measured on Windows.

### The firing layer

The always-on fragment, the practice skills, and a permission floor plus hook, installed into a
configuration directory with a backup and a precise uninstall.

```powershell
# See exactly what it would do. Writes nothing.
pwsh -NoProfile -File tools/claude-practice-layer/Install-PracticeLayer.ps1 -DryRun

pwsh -NoProfile -File tools/claude-practice-layer/Install-PracticeLayer.ps1
```

Try it against a throwaway directory first with `-ClaudeHome`; that is how every claim about it was
measured. Read `tools/claude-practice-layer/README.md` before running it actively — it explains what
it writes, why it refuses to repair a configuration file that does not already parse, and what it
cannot cover.

### The permission floor, validated by replay

```bash
python tools/claude-permission-toolkit/replay_permissions.py \
    --candidate settings.json --corpus your-approved-commands.json
```

A ruleset cannot be reviewed by looking at it. This replays invocations that were previously
approved against a candidate floor and treats any DENY as a regression. It found four rules that all
read as obviously correct and each broke a real workflow.

### The memory index

```bash
python tools/claude-memory-toolkit/install.py
```

Copies the toolkit into place and prints the hook snippet for you to merge. It never edits your
settings for you.

### Parallel worktrees

```powershell
pwsh -NoProfile -File tools/claude-worktree-toolkit/Install.ps1 -RepoPath 'C:\path\to\your\clone'
```

### Offline CI

`tools/ci/Invoke-LocalCI.ps1` runs the gates your pipeline would run, locally, so a decision to
merge is an informed one rather than an optimistic one.

## The basic workflow

1. **Read the front door** — `tools/claude-dev-practice/CODING-WITH-CLAUDE-CODE.md`. It is the only
   document that assumes you have read nothing else.
2. **Put a floor in place** before widening anything. Judge a permission config by its floor, never
   by the length of its allow list.
3. **Validate that floor by replay**, against commands you have actually run.
4. **Install the firing layer** so the rules that must bind are not things you have to remember.
5. **Make the work checkable** — decide what would prove it right before writing the thing that has
   to be proved.
6. **Gate anything destructive** on dry-run → execute → verify → rollback, and verify by contents
   rather than by exit code.
7. **Hand off deliberately** at a boundary you chose, rather than compacting at a cliff.

## What's inside

### Practice documents — `tools/claude-dev-practice/`

- **CODING-WITH-CLAUDE-CODE.md** — the front door. What the model writes versus what checks it;
  configuring the harness instead of the conversation; context as a resource; where knowledge lives
- **TESTING-DISCIPLINE.md** — what makes a test worth having. Assert properties, not implementations
- **REVERSIBILITY.md** — making a destructive operation safe to run, and the ways a tool reports
  success having done nothing
- **GIT-AND-REVIEW.md** — which comparison answers which question; merges that report success and
  land nothing; why "independent reviewer" means uncorrelated errors rather than a fresh window
- **ORCHESTRATION.md** — splitting work across agents. Why a second agent earns its keep for what it
  is *not allowed to see*; the auditor contract; one file, one writer
- **PRIOR-ART.md** — the work this sits beside, read and dated
- **VERIFIED-AGAINST.md** — every harness claim, its source, and when it was last checked

### Toolkits

- **`claude-practice-layer/`** — the always-on fragment, five practice skills, and the installer
- **`claude-permission-toolkit/`** — replay validator, a floor to start from, two secret guards held
  to one shared specification, and the parity checks that keep the duplicated pieces honest
- **`claude-memory-toolkit/`** — index rebuilder with a data-safety suite, and an installer
- **`claude-worktree-toolkit/`** — parallel-session workflow, with a merged-ness test that returns
  *unknown* rather than *no* for a reference it cannot resolve
- **`claude-session-toolkit/`** — handoff and memory-tending discipline
- **`claude-authoring-toolkit/`** — a frontmatter contract for skills, a linter, and a triggering
  eval that probes what should *not* fire as well as what should

### Gates — `tools/practice-gate/` and `tools/Test-*.ps1`

Run them against the pack. They check that citations resolve, that figures are dated, that
forbidding patterns still match their own examples, that attribution is still cited, and that
nothing in a built distribution carries an identifier that should not leave.

## Philosophy

- **A check that could not run must never report PASS.** An honest SKIPPED is worth more than a
  green tick
- **A guarantee that depends on remembering to apply it is not a guarantee.** Configure the harness,
  not the conversation
- **A warning is not a gate.** Narration is not enforcement
- **Never credit theatre — and never fault an enforced control.** Both are scoring the artifact
  instead of the behaviour
- **Independence means uncorrelated errors**, not a second window
- **Measure it; never quote a count from memory**

## Prior art

This is the verification layer. There is good work on the *workflow* layer — what to do, in what
order — and the two compose rather than compete. `tools/claude-dev-practice/PRIOR-ART.md` sets out
what was read, when it was read, where separately-authored projects reached the same rule, and what
that agreement is worth.

## What this does not do

- **It is not general software-engineering advice.** There is plenty of that and it is mostly
  better. This covers what is specific to working with an agentic coding tool
- **It does not test that an installed hook fires in a live session.** The tests prove it is
  installed and that its command parses — not that the tool invokes it. That needs a real session
  and no gate here can assert it
- **The PowerShell is not portable by claim.** It requires pwsh 7 and was measured on Windows. The
  Python is stdlib-only and has no such constraint
- **It is not finished.** Every document here was written from a failure that had already happened.
  More will arrive

Several examples in these documents are unflattering — a gate that printed a false parity claim for
weeks, an allow list of thousands of rules that bounded nothing, a backup that archived one symlink
and exited 0. They are kept deliberately. A practice document with only successes in it teaches
nothing, because the reader cannot tell which advice is load-bearing.

## Contributing

1. Read the front door first — much of what looks like a missing feature is a stated decision.
2. Run the gates before and after your change: `pwsh -NoProfile -File tools/Test-PracticeClaims.ps1`
   and the two beside it. Candidate counts should rise, never fall — a falling count means something
   stopped being scanned.
3. Run the self-tests. Every gate has a `-SelfTest` that proves it fails when it should.
4. If you add a claim about the tool's own behaviour, add it to `VERIFIED-AGAINST.md` with the source
   you read and the date you read it. Do not reword a claim to avoid the check that dates it.
5. If you add prose that asserts something is enforced, add the enforcement in the same change.

## Updating

Pull, then re-run the gates and the self-tests. If a harness pin is older than you are comfortable
with, re-read its source — and update the date only for what you actually re-read.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
