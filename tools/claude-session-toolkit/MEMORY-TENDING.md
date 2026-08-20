# Tending an auto-memory store

Auto-memory accumulates. Left alone it accumulates badly: near-duplicates piled beside each other,
volatile counts frozen into confident assertions, and an index that has grown past what actually
loads. This document is the curation pass that stops that — run at the end of a session, or on
demand, and safe to re-run.

It is the **judgement** half of the problem. The **mechanics** half — how the index is ordered, what
the loader reads, how to configure any of it — belongs to `../claude-memory-toolkit/README.md`, and
is deliberately not restated here. One statement of a harness behaviour is hard enough to keep true;
two is a fork.

What you do need in hand before touching anything is four facts, each pinned with the date it was
last checked in `../claude-dev-practice/VERIFIED-AGAINST.md`:

1. **Only the index auto-loads, and only its head.** Content past the cut is not loaded. Topic files
   are never loaded at startup — they are read on demand, with ordinary file tools, when something
   points at one.
2. **The tail is what gets dropped**, so ordering is the whole lever. Put the map of what exists at
   the top and the disposable leaves at the bottom.
3. **Overflow is signalled, but a signal is not a gate.** A write near the limit comes back with a
   reminder to shorten the index; a write over it succeeds and returns an error. Neither makes the
   overflow load, and neither names an entry — "shorten the index" is a length instruction, and
   *which* entries are worth keeping is the actual question.
4. **The store is keyed by git repository.** Every worktree and every subdirectory of one repo
   share a single memory directory and a single index. So there is one file to fix, never one per
   project — a write is global, and a parallel session may be writing at the same time. Mind that
   before any batch operation.

That fourth one has a sharp edge attached to it, and it is in the guardrails at the bottom.

---

## The layout this pass assumes

- **The index** — auto-loaded, and the only guaranteed-in-context tier. Cross-cutting rules and
  general lookups, followed by a **router**: a line naming every theme that exists elsewhere.
- **Topic files** — one fact each, with frontmatter carrying a name, a description, and a type
  (`feedback`, `project`, `reference`). The name is the link target; the description is the recall
  surface.
- **Optionally, a spoke file** — not auto-loaded, reached through the router. Theme-tagged entries,
  project entries, and an overflow section holding what the budget demoted.

The two-file split is a property of *your generator*, not of the harness. The toolkit shipped beside
this document implements the ordering half against a single index; a generator that also emits
spokes adds a second file and a router. Everything below holds either way — where it matters, the
text says which shape it is talking about.

**Emit the router first, right after the preamble.** If the index is ever cut, the map of what
exists must not be the thing that falls off. This is not hypothetical: an index that overflowed was
cut mid-router, losing most of a theme list and an entire pointer to the project entries. What
remained gave no indication that anything was missing.

**Recall of a file the index does not name is undocumented and unreliable.** Assume it will not be
found. That is *why* the router matters, and why you must never quietly drop an entry out of the
index without leaving a pointer to it.

---

## Deciding the tier

For each memory, take the **first rule that matches**:

1. **Is it a volatile count, a build state, a current status number?** → **Do not memorialise it.**
   A count is a query, not a memory, and it is the single largest source of confident staleness. If
   the state genuinely must be recorded, date it and label it a snapshot.
2. **Is it a durable, cross-cutting operating rule or a hard-won lesson** — a gotcha, a repeatable
   *how to do X*, a stated preference — that would help in a session about something else entirely?
   → **`feedback`, in the index.** It must carry both a **Why** and a **How to apply**; a rule
   without either is an assertion nobody can act on.
3. **Is it a stable external lookup** — where a fact lives, a canonical source, a code table, an
   auth command? → **`reference`.** In the index if it is general; in a spoke if it is tied to one
   theme, with that theme's prefix on the filename.
4. **Is it ongoing work** — a build, a plan, a named initiative with a lifecycle? → **`project`, in
   a spoke.** Projects are inherently on-demand; they are recalled when their work is active and
   cost index budget the rest of the time.
5. **Is it specific to one theme?** → **spoke**, filename prefixed with the theme token — even when
   it is shaped like a cross-cutting lesson. A lesson that only bites in one area belongs with that
   area.

Keep the theme vocabulary in one place — the generator that routes on it — and treat any addition
as touching both the vocabulary and whatever document explains it, in the same pass. Never one
without the other.

### Slop tests

Apply to every new or changed memory:

- **Does one already exist on this topic?** Update it, or fold into it. Never pile a second beside
  the first. This is the most common defect and the one that compounds.
- **Two facts in one file?** Split them.
- **Is the description precise and keyword-rich?** It is the recall surface — a vague description is
  a memory that never surfaces. Rewrite it.
- **Right filename prefix and theme token?** So the generator routes it without an override.
- **Does the feedback entry carry Why and How to apply?** Add them.
- **Is it over-nuanced?** If a blunt rule would do, keep the blunt headline where it loads and let
  the detail live in a linked file that is recalled only when that area is active.

---

## The pass

Run the safe steps without asking. **Gate the meaning-changing ones** — rewrites, folds, anything
that drops an entry out of the index — behind a backup and an explicit confirmation.

### A. Surface what changed

List the topic files created or modified this session. Descriptions and first paragraphs are
enough; do not pull the whole store.

**File times are local; most log and API timestamps are not.** Passing a UTC cutoff to a
modified-since filter puts the cutoff in the future, and the tool then returns **zero files and
exits 0** — which reads exactly like "nothing changed this session" when in fact everything did. If
the result is empty, widen the window before believing it, and sanity-check against a plain listing
sorted by time. An empty result and a successful exit are not evidence of a clean store.

### B. Route each one

Against the rubric above. Wrong tier, wrong prefix, or a missing theme token → rename so the
generator routes it correctly. Vague description → rewrite. Missing Why or How → add. Two facts →
split. Volatile count → strip it or date-label it. Duplicates something → fold, which is step C.

### C. Fold, when the generator tells you to

**Do not guess at when a consolidation sweep is due.** The generator knows. When it reports that the
budget has begun evicting *well-cited* entries, demotion has stopped being free and has started
costing you connected knowledge — that is the signal. Without it, a periodic skim is optional.

When you do fold:

- Pick the **survivor**: the most-cited, broadest memory. It **keeps its name**, so inbound links
  still resolve.
- Add a **blunt headline and a link** for each absorbed topic into the survivor, and broaden the
  survivor's description to cover what it has taken on.
- Mark each absorbed file superseded — a banner naming the survivor and the date, and drop it from
  the index. **Never delete it.** The detail stays on disk and is recalled when that specific area
  is active.
- **Do not over-fold.** Genuinely distinct rules stay distinct. A fold that merges two different
  rules produces one rule that is wrong at both ends.

### D. Rebuild and verify

Run the generator. Then **read its report — the report is the acceptance test.** Whether the index
came in under budget is the *expected* outcome, not an achievement; what earns your attention is
everything printed above that line. In descending order of severity:

| Report line | What to do |
|---|---|
| An **invariant failure** — the generator's own accounting says an entry was lost | **Stop.** Do not rebuild over it. Find the lost entry first. This is the guard against exactly the silent-drop class the whole pass exists to prevent |
| **The index exceeds the loader cut** | Context is being lost right now. Fold before anything else |
| **Well-cited entries are being evicted** | Fold — this is the signal step C waits for |
| **A well-cited entry landed past the cut** | Pin the named files so they are exempt from demotion |
| **Still over target after demoting everything eligible** | The index is structurally too big; folding is overdue |
| **Over-long lines** | Usually the generator's own prose. Fix it there, not in the output |
| **Schema problems, duplicate names, skipped files** | Chase these. A skipped file is an unindexed file, which is an unrecallable one |

"Nothing changed" is the *expected* result of a fold that touched only already-indexed files, not a
sign the rebuild no-opped.

**Then verify every link you wrote resolves.** A fold's entire value is its pointers, and a typo'd
link fails silently — it does not error, it simply never resolves, and the absorbed detail becomes
unreachable while looking filed.

### E. Report

A plain summary: what was added, how each was routed or fixed, what was folded, and the current
index size with its headroom. Name paths the reader might open; leave out everything else.

---

## Guardrails

**Back up before any batch fold — and verify the archive's contents, never its exit code.** Count
the entries in the archive and compare against a live count of the store, not a remembered one. The
corpus grows, so any number written into a procedure rots, and "looks about right" is how an empty
backup gets accepted.

The trap this is guarding against is specific and it exits 0. If your store is reached through a
**symlink** — a junction, a linked directory, anything that is not the real path — then `tar`
archives *the link itself*: one entry, about a kilobyte, no warning, successful exit. A backup that
protects nothing then licenses the risky fold that follows. The same hazard applies to a recursive
copy, to `rsync` without dereferencing, and to zip. Either work from the real directory or tell the
tool to follow links — and check the entry count, because the exit code will not tell you. The
measurement behind that, and the general form of a tool reporting success having done nothing, is
[REVERSIBILITY.md](../claude-dev-practice/REVERSIBILITY.md) §3.

Worth being precise about *why* that comes up, because the obvious explanation is wrong. Worktrees
share a memory store because the store is keyed by the **repository** and the path is derived from
it — not because anything is linked. Links appear when a *host* arranges its own convenience on top
of that, and the trap belongs to the link, not to the harness. Fix the wrong cause and you will
carefully avoid the wrong directory.

**Never delete a memory.** Supersede it: banner, pointer, out of the index, still on disk.

**Never drop an entry from the index without a router pointer.** See the recall rule at the top.

**Never memorialise a volatile count.**

**The generator owns the index — do not hand-edit it.** Hand edits are overwritten on the next
write, which reads as the problem recurring on its own. Edit the topic files' frontmatter and
rebuild.

**If the index is structurally wrong, fix the generator, not the file.** Ordering, budget, what gets
demoted — those are generator behaviour. Before editing it, confirm it really is the producer: run
it and check it reproduces the index byte-for-byte. If it does, it is authoritative and safe to
change. If it does not, something else is writing the file and you need to find that first.

**A warning is not a gate.** The overflow incident at the top of this document happened while the
generator was *correctly detecting* the overflow and shipping anyway; the diagnosis was printed and
ignored for weeks. When you add a check to this pass, make it change the output or fail — not just
narrate.

---

## When memory is the wrong home

Tending is not free, and some knowledge should never have entered the store. Two alternatives beat
it outright:

- **Knowledge that applies to one area of a codebase** belongs in a rules file with a `paths:` glob,
  which loads deterministically when a matching file is read. That is a hard trigger; an index entry
  is subject to the load cut, and a "read this when relevant" pointer is a judgement call that
  misses silently.
- **Knowledge that must always load** belongs in the always-on project file, which is not subject to
  the index budget at all.

Memory scopes by *what loaded*, not by what the conversation is about. Anything that needs to fire
on a topic rather than on a file path or an invocation is better off somewhere with a real trigger.
