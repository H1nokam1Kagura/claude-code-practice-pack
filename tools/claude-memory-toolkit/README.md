# claude-memory-toolkit

A tiny, stdlib-only toolkit for **managing Claude Code auto-memory at scale** — so that when the
index outgrows what loads, the part left behind is the part you could afford to lose.

Claude Code power-user infrastructure: it solves a problem you only hit once you lean on the tool
hard enough to accumulate more memory than the loader will read.

---

## The problem it solves

Claude Code's auto-memory (`~/.claude/projects/<project>/memory/`) loads **only the first 200
lines, or the first 25 KB, of `MEMORY.md`** — whichever comes first — at the start of every
conversation. Content past that point is not loaded. Topic files are not loaded at startup at all;
they are read on demand, with ordinary file tools, when something points Claude at one. The index
is therefore the whole of what Claude knows it has, and the tail of the index is knowledge Claude
does not know it has. Verified against the memory documentation, 2026-08-16.

**Overflow is no longer silent, and that changes the problem rather than removing it.** After a
write to `MEMORY.md`, Claude Code measures the file against both limits: near a limit it reminds
Claude to shorten the index — one line per entry, detail moved into topic files, stale entries
merged or dropped — and over a limit the write still succeeds, but an error comes back telling
Claude to rewrite the index, because everything past the limit is dropped on the next load. Only
the content that loads is measured: YAML frontmatter and block-level HTML comments are stripped
first, so they cost nothing. (Before v2.1.211 the raw file was measured, and either could trip the
error while the loaded content fit.) Verified 2026-08-16.

Three things survive that improvement, and together they are why this toolkit still exists:

- **The tail is still dropped.** The signal says the file is too long. It does not make the
  overflow load.
- **The signal fires at write time and names no entry.** "Shorten the index" is a length
  instruction. *Which* entries are worth keeping is the actual question, and nothing in the harness
  answers it — so the answer is still ordering.
- **A warning is not a gate.** It arrives as a reminder, to the same model that just decided the
  entry was worth writing; it blocks nothing, and a reminder that fires and is ignored leaves the
  file exactly as long as it was. A check that reports rather than fails is the failure mode this
  toolkit was built for — and it applies to the toolkit's own warnings too, which is why the
  Robustness section below says so about itself.

The obvious fixes were tested rather than assumed, and none of them works:

- **Deleting "stale" memories by keyword** (`retired`, `superseded`, `deprecated`) is ~100%
  false-positive on an active index — those words are usually *subject matter* ("X was retired"),
  and the memory is the current authoritative record. The genuinely-dead ones are already archived.
- **Just shrinking hooks / entry text** buys almost nothing.
- **Per-directory memory overlays** aren't supported — auto-memory is one whole-loaded store per
  repo, no tree-merge. The store is keyed by **git repository**: the project path is derived from
  the repo, so every worktree and every subdirectory of one repo share a single memory directory
  and a single index (verified 2026-08-16). A per-worktree store is not a lever either.

**The lever that works is ordering, not deletion:** put the highest-value entries in the first
200 lines and let the cut land on the disposable tail. This toolkit does that automatically.

---

## What it does

`rebuild_memory_index.py` regenerates `MEMORY.md` from your topic files' frontmatter and orders it by
a **priority computed live from the memory link-graph** (never stored per-memory):

1. **Type tier** — `feedback` (cross-cutting rules) first, then `project`, `reference`, `other`.
2. **Citation-centrality** — within each section, entries cited by ≥ `FLOAT_INBOUND_MIN` (default 3)
   other memories via `[[name]]` links float to the top; the least-referenced leaf entries sink to
   the bottom, where the cut is harmless.
3. **Per-file override** — frontmatter `pin: true` force-floats an entry to the top of its section.

It also **self-checks**: if any well-cited memory still lands past the load budget, it prints a
`WARNING` telling you which one to `pin`.

> **Why not store a priority number in each file?** A brand-new memory has 0 inbound citations at
> birth, and a stored score drifts the instant another memory cites it. Centrality is only correct
> when computed dynamically — so the script recomputes it every run.

---

## What it measures, and what it does not

Worth knowing before trusting a green run: `rebuild_memory_index.py` orders and warns on **lines
only**. Every threshold in it — an entry's position, the `LINE_BUDGET` comparison, the borderline
band — is a line number. The `bytes=` value in its run line is the UTF-8 length of the whole
generated file, printed for information; there is no byte budget and nothing fails on one.

Two consequences, stated here rather than left to be discovered:

- **The 25 KB half of the cut is unguarded.** A file of long index hooks can cross it while every
  line check stays green. Keep hooks short — that is what `CLAUDE_MEMORY_HOOK_LIMIT` is for.
- **A raw byte count is the wrong number in general, and the right one here.** Claude Code measures
  only the content that loads, with YAML frontmatter and block-level HTML comments stripped first
  (verified 2026-08-16); a generated `MEMORY.md` carries neither — it opens at the `# Memory Index`
  heading — so raw length and measured length coincide. Hand-edit frontmatter or a comment block
  into the index and the printed number stops matching what the harness counts.

---

## Safety — your memory files are never at risk

This tool only ever **writes `MEMORY.md`**. Your topic files are **read-only** — never modified,
never deleted (there are *zero* delete calls in the code). Verified by an included data-safety suite
that sha256-checks every file before and after a run — run it yourself: `python tests/safety_test.py`.

- **Read-only on your data** — topic files are only read; the sole outputs are `MEMORY.md`
  (regenerated) and, at most, a one-time `MEMORY.md.bak`.
- **Atomic write** — `MEMORY.md` is written to a temp file and renamed into place, so a crash
  mid-write can never leave it half-written or corrupt.
- **Backs up a hand-authored index** — if an existing `MEMORY.md` doesn't look tool-generated, it's
  copied to `MEMORY.md.bak` before the first overwrite (and never clobbered after).
- **Never crashes on bad input** — a malformed, binary, empty, or non-UTF-8 file is skipped and
  reported, not fatal. One bad file can't break a rebuild that runs on every write.
- **Safe if mis-pointed** — aimed at the wrong folder (a docs / Obsidian dir), it leaves every file
  untouched and only creates a `MEMORY.md`. Files without frontmatter are ignored, not parsed.
- **Idempotent** — re-running changes nothing; a no-op edit doesn't even rewrite `MEMORY.md`.
- **Nothing outside its lane** — it writes only inside your memory dir; `install.py` copies the
  toolkit into `~/.claude/hooks/` and *prints* the settings snippet (it never edits `settings.json`).

---

## Topic-file frontmatter schema

```markdown
---
name: kebab-case-slug          # the [[link]] target; defaults to the filename stem
description: one-line summary   # becomes the index hook (truncated)
metadata:
  type: feedback | project | reference
  index: false                  # optional — keep the file on disk but omit it from the index
  pin: true                     # optional — force-float to the top of its section
---
The fact. Link related memories with [[their-name]] — those links drive the priority ordering.
```

Filenames are `feedback_*.md`, `project_*.md`, `reference_*.md` under your memory dir.

---

## Setup

**Quick install (recommended):** unzip, then from the folder run:

```bash
python install.py
```

It finds your memory dir, copies the toolkit into `~/.claude/hooks/claude-memory-toolkit/`, runs an
initial rebuild, and prints the (optional) auto-rebuild hook snippet to merge into `settings.json`.
It never edits your settings or deletes anything. (`python install.py --dir "<path>"` if auto-detect
can't find it; `--print-only` to just see the snippet.)

**Manual setup:**

1. **Drop `rebuild_memory_index.py` somewhere** (e.g. `~/.claude/hooks/`).
2. **Point it at your memory dir** — it defaults to its own directory; otherwise set one of:
   - `python rebuild_memory_index.py --dir "/path/to/.../memory"`
   - `export CLAUDE_MEMORY_DIR="/path/to/.../memory"`
   Your memory dir is under `~/.claude/projects/<project>/memory/` (the folder holding `MEMORY.md`).
3. **Run it** whenever the index drifts: `python rebuild_memory_index.py`.
4. **(Optional) auto-rebuild on every memory write** — add a `PostToolUse(Write)` hook so the index
   re-orders itself as you add memories. See `examples/settings-hook-snippet.json`.

Pure stdlib, Python 3.6+. No dependencies. Safe to run repeatedly (idempotent).

---

## Config

For the memory directory the precedence is **`--dir` first, then `CLAUDE_MEMORY_DIR`, then the
default** — the CLI argument wins, not the environment. The four tuning values below have no CLI
form at all and are environment-only.

| Setting | Env var | Default |
|---|---|---|
| Memory dir | `CLAUDE_MEMORY_DIR` (or `--dir`) | script's own directory |
| Index-hook length | `CLAUDE_MEMORY_HOOK_LIMIT` | 46 |
| Float-to-top threshold | `CLAUDE_MEMORY_FLOAT_INBOUND` | 3 |
| Load budget (lines) | `CLAUDE_MEMORY_LINE_BUDGET` | 200 |
| Stability-warning margin | `CLAUDE_MEMORY_MARGIN` | 15 |

**`CLAUDE_MEMORY_LINE_BUDGET` is this toolkit's build target, not the loader's cut.** The cut is
200 lines or 25 KB, whichever comes first, and no setting here moves it. The default matches the
line half of the cut; the headroom advice below is to set it deliberately *lower*, which is a
choice about slack, not a claim about the harness.

**`CLAUDE_MEMORY_DIR` and `--dir` point this script at a directory. They do not relocate the real
store.** Claude Code takes that from an `autoMemoryDirectory` setting — an absolute or
`~/`-prefixed path, readable from any settings scope — and the feature itself is switched off by
`autoMemoryEnabled` or the `CLAUDE_CODE_DISABLE_AUTO_MEMORY` environment variable (verified
2026-08-16). If the store has been moved, point the script at wherever that setting resolves to;
setting the toolkit's variable alone just rebuilds an index nothing loads.

---

## Reliable domain scoping (beyond the index)

If a chunk of domain knowledge is only relevant when you're editing files in that area, the *most
reliable* home is **not** auto-memory at all — it's a **path-specific rule**:

```markdown
---
paths: ["payments/**", "**/*payment*"]
---
# Payments gotchas — loads on-demand ONLY when Claude reads a matching file.
```

Put it in `.claude/rules/<domain>.md`. Claude Code loads it **deterministically when it reads a file
under the path glob** — a hard trigger, unlike a memory-index entry (which is subject to the load
cut) or a "read this pack when relevant" pointer (which is a judgment call). See
`examples/rules-domain.example.md`.

The length limit is the index's alone: a `CLAUDE.md` is loaded in full regardless of length, and
nothing truncates it (verified 2026-08-16). That is a reason to put a must-always-load rule in one,
not a reason to make it long — a shorter file still gets better adherence.

**Reliability ladder for domain-scoped knowledge, most → least deterministic:**

| Mechanism | Trigger | Reliability |
|---|---|---|
| Global `MEMORY.md` entry | loads every session (if inside the first 200 lines / 25 KB) | 100% but costs budget |
| `.claude/rules/*.md` path rule | Claude reads a file under the `paths` glob | deterministic (file-anchored) |
| Skill-bundled reference | the skill's description matches the task | deterministic *when the skill fires* |
| "Read this pack when relevant" pointer | the model notices + chooses to open it | **unreliable — silent misses** |

Rule of thumb: **rules/skills scope by hard triggers (file-path, invocation); memory does not scope
by conversational topic.** Don't build "load-on-topic" memory pointers — they miss silently.

---

## Robustness — surviving small memory changes

The one real fragility is the **hard load cut**: an entry sitting near line 200, or hovering at
exactly the citation threshold, can cross the boundary (or flip float↔sink) when you add an
*unrelated* memory or link — unannounced, because the harness's length reminder names no entry. The
toolkit is built to make that visible per entry:

- **Write-only-if-changed** — a no-op memory edit doesn't rewrite `MEMORY.md` or churn anything. The
  index is stable under small, non-structural changes.
- **Stability warnings** — every rebuild reports entries **within `MARGIN` (default 15) lines of the
  cut** ("a small change could flip them across it") and any **well-cited memory that already fell
  past the cut** — each with a `pin: true` fix. You get told *before* something drops, not after.
- **Schema warnings** — files with a blank `description` or a missing/typo'd `type:` are flagged, so
  a fat-fingered frontmatter change can't quietly mis-index a memory.
- **Bank headroom** — set `CLAUDE_MEMORY_LINE_BUDGET` a little under the real 200 (e.g. **185**). The
  index then orders against 185, leaving ~15 lines of slack so ordinary growth doesn't immediately
  push entries over the real edge. The budget is the toolkit's target; the 200 is the harness's.
- **Pin your core** — `pin: true` removes an entry from citation-dependent ordering entirely, so it
  loads deterministically no matter how the rest of memory churns. Pin the handful of
  safety-critical / must-always-load memories and they become immune to small-change drift.
  (`feedback` rules already never sink.)

Net: small changes either don't move the index (no-op guard) or produce a **warning** naming exactly
which entry to pin.

**And a warning is all it is — including this toolkit's own.** Every self-check above is advisory
and never fatal: the rebuild exits the same way whether or not it printed one, so a rebuild wired
to run on every memory write will happily print the same finding forever. What earns it its keep is
not that it fires but that it names *one entry* and *one fix*, which a length complaint cannot. If
you want a gate rather than a report, the rebuild's output is the thing to gate on.

## Caveats

- **Native memory is evolving, and this document has already been overtaken once.** Its original
  headline claim was that overflow was silent and named nothing; the harness now warns at write
  time and errors past a limit, which narrowed the problem without removing it (checked
  2026-08-16). The *implementation* needs upkeep as Claude Code changes; the *insights* (centrality
  ordering, path-rule scoping) are durable. Re-read the memory documentation before trusting any
  behavioural sentence here.
- **Centrality is a proxy.** A critical-but-rarely-cited memory would score low — which is why
  `feedback` rules **always float** (never sink) and `pin: true` force-floats anything you can't
  afford to drop. Use those safety valves for safety-critical singletons.
- **Memory dir is git-ignored by default** in most setups — this toolkit manages the *index*, not
  version control of the memories themselves.

---

## Files in this bundle

| File | What |
|---|---|
| `install.py` | one-command setup: copies the toolkit, runs an initial rebuild, prints the hook snippet |
| `rebuild_memory_index.py` | the priority-ordering index rebuild (stdlib, configurable) |
| `tests/safety_test.py` | data-safety suite (14/14): proves topic files stay read-only, atomic write, backup |
| `examples/memory-topic.example.md` | a topic file showing the frontmatter schema |
| `examples/rules-domain.example.md` | a `.claude/rules/` path-specific rule template |
| `examples/settings-hook-snippet.json` | wiring to auto-rebuild on every memory write |

Feedback welcome — raise it wherever you got this.
