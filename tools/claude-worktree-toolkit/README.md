# `wt` — a parallel-worktree workflow for Claude Code

A tiny PowerShell command set for people who run **several Claude Code sessions at once**.
The model: your primary clone hosts `.git` and **nobody works in it**; each unit of work gets
its own git worktree under one home folder, branched fresh from `origin/main`, with a memorable
auto-name (`sassy-terrapin`, `feral-raccoon`, …). Create with `nwt`, publish a PR with `pwt`,
tear down safely with `rwt`, and see what's safe to clean up with the print-only `swt`.

---

## ⚠️ Requires (read this first)

This is a **git-worktree wrapper** and an **advanced-workflow** tool. It is *not* a universal helper.

| Need | Why |
|---|---|
| **git** | The whole tool is built on `git worktree`. No git, no tool. |
| **A GitHub repo you've cloned** | The "primary clone" that hosts `.git`; you branch worktrees off `origin/<base>`. |
| **`gh` CLI, authenticated** | For `pwt` (open/refresh a PR) and `rwt -Merge` (squash-merge). |
| **PowerShell 7+** (`pwsh`) | Uses pwsh-7 syntax (ternary, `$IsWindows`) and lazy P/Invoke. |
| **A PR-based GitHub flow** | The model assumes `origin/<base>` + squash-merge via PR. |
| **You run parallel CC sessions** | The tool exists to manage many worktrees at once. One session in one folder gets nothing from it. |

> **Claude Code itself does *not* require git** — `claude` runs in any plain folder. *This tool* does.
> If you're not already fluent in branches / PRs / worktrees, this isn't your starting point.

**Who it's for:** developers already running several parallel Claude Code sessions on GitHub repos.
**Who it's not for:** single-session, single-folder use — you'll get no value and some confusion.

---

## Quick start

From the extracted folder, in **PowerShell 7**:
```powershell
./Install.ps1 -RepoPath 'C:\path\to\your\primary-clone'   # or /Users/you/code/your-repo on macOS
```
`Install.ps1` checks prerequisites, points the toolkit at your repo, and wires it into your PowerShell
profile — idempotent, and it backs the profile up first. Then open a **new** session and go:
```powershell
nwt try the toolkit     # new worktree, cd's you in
```

> **Downloaded as a zip?** Windows may flag the files. In the extracted folder, run once before installing:
> ```powershell
> Get-ChildItem -Recurse | Unblock-File
> ```

## Manual setup (if you'd rather not run the installer)

1. **Point it at your repo.** Either set env vars, or edit the config block at the top of `wt.ps1`:
   ```powershell
   $env:WT_REPO = 'C:\path\to\your\primary-clone'   # or /Users/you/code/your-repo on macOS
   $env:WT_HOME = "$HOME/wt"                          # where worktrees live (default: ~/wt)
   $env:WT_BASE = 'main'                             # default base branch
   ```
2. **Dot-source from your PowerShell `$PROFILE`** so every shell (and every CC session, which launches `pwsh`) has the commands:
   ```powershell
   . "/path/to/claude-worktree-toolkit/wt.ps1"
   ```

---

## Commands

| Command | Does |
|---|---|
| `nwt [name]` | New worktree off `origin/<base>`, `cd` in. No name → a silly `<adjective>-<animal>` name. `-Launch` opens a fresh `claude` session there (Windows: a new Windows Terminal window). |
| `cwt <msg>` | Stage-all + commit in the current worktree. Guards against committing in base/primary. `-Coauthor` adds a trailer. |
| `lwt` | List worktrees + clean/dirty state. |
| `pwt` | Push + open/refresh a PR (no merge). `-Message` commits first; `-Coauthor` adds the trailer to that commit; `-Title` sets the PR title. **Refuses to open a PR that proposes nothing** — `-AllowEmpty` overrides. |
| `swt` | **Print-only** stale-worktree report: which trees are clean, merged into base, and idle — i.e. safe to remove. Suggests `rwt` lines. Never deletes anything. |
| `rwt` | Tear down one worktree: remove it + delete its branch **only if fully merged**. `-Merge` squash-merges the PR first; `-Branch <b>` targets another; `-DiscardChanges` destroys uncommitted work; `-EvictLiveSession` removes a tree another session holds; `-Force` = both (deprecated); `-Yes` skips the prompt. |

### The everyday loop

```text
nwt fix the parser      # -> new worktree 'fix-the-parser', you're in it
#   …work with Claude…
cwt "fix the parser"    # commit
pwt                     # push + open a PR
#   …review + merge the PR (UI, or `rwt -Merge`)…
swt                     # what's safe to clean up?
rwt -Branch fix-the-parser
```

---

## Platform support — Windows vs macOS/Linux

The **core lifecycle works on all three** (pwsh 7). Two features are Windows-only:

| Capability | Windows | macOS / Linux |
|---|---|---|
| `nwt` / `cwt` / `lwt` / `pwt` | ✅ | ✅ |
| `swt` merged / clean / idle detection | ✅ | ✅ |
| `rwt` teardown, `-Merge`, merged-branch deletion | ✅ | ✅ |
| Primary-clone detection (path compare) | ✅ | ✅ *(fixed to normalize both separator styles)* |
| **Liveness protection** (won't report/remove a tree a live session is in) | ✅ (Win32 handle probe) | ⚠️ **no-op** — the probe is Windows-only |
| **`nwt -Launch`** opens a new terminal window | ✅ (Windows Terminal) | ⚠️ falls back to a detached `claude` with no TTY — not useful; just `cd` in and run `claude` yourself |

> **macOS/Linux caveat:** because the liveness probe is a no-op there, `swt` can't tell that a
> clean+merged worktree still has an *active session* in it, and `rwt`'s in-use guard won't fire.
> On those OSes there are no file locks, so `rwt` won't crash a session — but it can pull files out
> from under an active build. **Rule: don't `rwt` a worktree you currently have a session in.**

---

## Safety model

- **`swt` is read-only.** Its only side effects are `git worktree prune` (removes admin metadata for
  already-gone worktrees), `git fetch --prune` (remote-tracking refs only), and reads. It never touches
  a working tree, branch, commit, or build output. It reports.
- **`rwt` is gated so it can't lose work:**
  - refuses a **dirty** tree unless `-DiscardChanges`, and the refusal **names what would be lost** —
    untracked files individually, because those exist nowhere else and are in no reflog. A
    `HANDOFF.md` is called out by name: it is gitignored by design, so it makes the tree read dirty
    and dies with it, which is exactly when someone reaches for the override;
  - refuses to remove a tree **another live session holds** (Windows probe) unless `-EvictLiveSession`.
    That is a *separate* switch from the one above on purpose — losing your own uncommitted work and
    yanking files from under someone else's running session are different hazards, and one flag for
    both meant clearing the first silently cleared the second. `-Force` still means both, for
    compatibility;
  - deletes a branch **only** when it's fully merged — proven by `git cherry` (patch-id, which counts
    a squash only when the branch held a **single commit**), *or* by a `-Merge` that just completed.
    See *What patch-id cannot see* below for the cases it misses, and why missing them is the safe
    direction;
  - uses a **normal squash-merge** (not `--admin`) so branch protection is respected;
  - echoes the branch **tip SHA** before a force-delete for reflog recovery (omitted only when the
    ref was already gone, rather than printing a restore command that cannot work);
  - **checks that the delete and the worktree removal actually happened**, and says so plainly when
    they did not. A locked worktree needs `--force` twice, which this edition will not do for you —
    so it reports the tree as still registered instead of claiming a reap it did not perform;
  - refuses when `-Branch` resolves to a tree holding a *different* branch. The path is derived from
    a slug, and slugs are many-to-one (`feat/foo` and `feat-foo` collide), so the branch actually
    checked out there is the identity that counts.
- **No process-killing, no background reaper, no window-hiding, no scheduled task.** Teardown is one
  explicit command; stragglers are surfaced by `swt` and removed on your say-so.
- **`pwt` refuses to open a PR that proposes nothing.** An empty PR is not an error anywhere in the
  toolchain: it pushes, CI goes green, `gh pr merge` reports MERGED, and nothing lands. Nothing in
  that sequence reads as alarming, so it can repeat for cycles — the tell is several squash commits
  on base sharing one title, because the title is derived from identical content. The check is a
  three-dot comparison against a freshly fetched base (*what did this branch's author change?*);
  `-AllowEmpty` overrides it, and an unresolvable base skips it rather than triggering it.

### What patch-id cannot see

`git cherry` compares **per-commit** patch-ids: for each commit on this branch, is there a
patch-equivalent commit on base? A squash-merge collapses the branch into **one** commit whose patch
is the union of all of them. So the comparison succeeds in exactly one case — **the branch held a
single commit** (or, by coincidence, the squash's patch equals some one commit's).

Two things it therefore cannot see, and neither is exotic:

- **A multi-commit branch, squash-merged as itself.** The squash commit's patch matches none of the
  individual commits, so every one of them reports as unique and the branch reads unmerged forever.
- **Content squashed into a *different* PR**, alongside other work. Same reason — and here not even
  the branch name hints that it landed.

Both point the same way: **the branch is kept when it could have been removed.** `rwt` therefore
refuses to delete it, which is the error you want a teardown tool to make.

`swt` covers the gap with a separate **`Superseded`** column, because it answers a *different
question* — not *"are these commits in base?"* but *"does this branch still add anything?"* Two
steps: take the files the branch itself touched (**three-dot** `base...branch`, so files other
people changed on base meanwhile are out of scope), then ask whether **those paths** still differ
from base (**two-dot**, restricted to them). Empty means everything the branch touched already
matches base — however it got there.

Scoping to the branch's own files is what makes it usable: compare *all* paths instead and a branch
that is merely **behind** on some unrelated shared file reports not-superseded forever. Being behind
is regression, not contribution, and it is not the question being asked.

The two disagree in both directions, so **name the question before trusting either answer**:

| Question | Use |
|---|---|
| What did this branch's author change? | three-dot `base...branch` — two-dot reads other people's newer commits as a revert by this PR |
| Does this branch still add anything? | file-set compare + two-dot — three-dot reads already-landed content as this branch's contribution |

A `Superseded=yes` tree is **not** listed as reapable. The report only ever adds information;
widening what gets deleted is your call, not a heuristic's.

`Superseded=yes` means **every file the branch itself touched now matches base** — not that the
branch is worthless. It may still be *behind* on files it never touched; that is staleness, not
contribution, and it is deliberately out of scope. A `-` in either column means **not measured**,
never "no", and `swt` prints the `Ahead` count the verdict was computed from rather than only the
conclusion.

One case neither check covers: if the fetch fails, both are computed against your last-fetched
base. The ref still resolves, so nothing errors — it just goes stale, which reads as *unmerged* and
therefore errs toward keeping a branch. Both commands warn when the fetch fails; the warning is the
only signal you get.

Every claim on this page about what patch-id can and cannot see is asserted against real
squash-merges in real repositories by
[`Test-WorktreeMergedness.ps1`](Test-WorktreeMergedness.ps1), which ships beside this file —
including the case that matters most: when `origin/<base>` cannot be resolved, merged status is
**unknown**, and unknown is never treated as merged. Read the test rather than trusting the prose:

```powershell
pwsh -NoProfile -File Test-WorktreeMergedness.ps1
```

---

## What's intentionally left out

The author's personal setup also has automatic/background reaping, a daily scheduled prune that
force-kills processes holding a worktree, and a Windows window-hiding system. All of that is
**deliberately excluded** here — it's aggressive (process kills, `--admin` merges) and tailored to one
person's machine and workflow. This edition keeps only the safe, portable core plus one salvaged safety
primitive (the non-destructive in-use probe).

**Also left out, and specified rather than built:** `rwt -Merge` does no *revert* analysis. A
squash applies the merge-base diff, so merging a branch that is behind on a file it touched
replaces base's newer copy with the branch's older one — silently, with green CI. The signal, the
portable heuristic, the `git merge-tree` version, and the refuse-versus-warn decision that has to
be made before any of it ships are written up in
[`SPEC-merge-revert-analysis.md`](SPEC-merge-revert-analysis.md). It is a proposal awaiting a
decision, not a description of behaviour — read it that way.

## The names

Yes, the silly `<adjective>-<animal>` names are load-bearing morale infrastructure, and they earn
their keep twice over: `bamboozled-quokka` is easier to say out loud across a desk than
`feature-branch-3`, and it is memorable enough that you notice when you are in the wrong one.

182 animals × 141 adjectives ≈ 25,000 names, so you'll go a long time before a repeat.

### Animal lore

`nwt` and the resume path print a one-line gloss of whatever animal you landed on:

```text
✓ now in C:\Users\you\wt\cooked-minke on 'cooked-minke'
  🐋 minke — Smallest baleen rorqual: fast, curious, often solitary
```

Glosses live in `animal-lore.ps1` next to `wt.ps1`, keyed by animal, each entry an
icon plus 5–10 words. Icons are matched to the clade — a whale for a minke, an owl for a
morepork, 🐾 only for the ~20 animals Unicode has nothing for. Keep the two files together:
the path is resolved off `$PSScriptRoot`, and a missing lore file just means no gloss (never
an error). Hand-named worktrees like `release-hotfix` match nothing and print nothing.

`lore-check` (`Test-WtAnimalLore`) verifies the table against the generator's animal list in
both directions and flags any entry missing an icon — run it after adding an animal.

Two gotchas if you reuse this elsewhere:

- **Emoji need UTF-8 on the way out.** Anything piping this through a non-UTF-8 host (a
  Windows console at cp437, a statusline harness) renders `??` unless it sets
  `[Console]::OutputEncoding` to UTF-8 first.
- **`[char]0x1F43E` throws.** The paw print is above U+FFFF, so it needs
  `[char]::ConvertFromUtf32` — the naive cast silently kills whatever block it's in.
