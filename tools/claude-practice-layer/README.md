# claude-practice-layer

**The part of this pack that fires.** Everything else here is prose you have to remember to read;
this is the same discipline installed where the tool consults it without being asked.

That distinction is the whole reason the unit exists. `tools/claude-dev-practice/` argues, at
length and with evidence, that a guarantee depending on somebody remembering to apply it is not a
guarantee — and then ships as four documents somebody has to remember to open. This unit closes
that gap for the subset of the practice that can be made mechanical.

| Part | What it is | Fires when |
|---|---|---|
| [`CLAUDE-FRAGMENT.md`](CLAUDE-FRAGMENT.md) | The always-on subset: command shape, evidence before assertion, memory and context hygiene, autonomous execution | Every task, because it is in context before anything is opened |
| [`skills/`](skills/) | Four practice skills, each derived from one document and reduced to a procedure | Its own trigger, judged from the description |
| The floor + guard | A deny/ask floor and a `PreToolUse` hook, sourced from [`../claude-permission-toolkit/`](../claude-permission-toolkit/) | Every matching tool call, before the call happens |
| [`Install-PracticeLayer.ps1`](Install-PracticeLayer.ps1) | Puts the three above into a configuration directory, and takes them back out | You run it |

---

## Install

```powershell
# See exactly what it would do. Writes nothing.
pwsh -NoProfile -File Install-PracticeLayer.ps1 -DryRun

# Do it.
pwsh -NoProfile -File Install-PracticeLayer.ps1

# Take it back out. Removes what it recorded installing, and nothing else.
pwsh -NoProfile -File Install-PracticeLayer.ps1 -Uninstall
```

`-ClaudeHome` targets a different configuration directory — use it to try the whole thing against a
throwaway copy first, which is how every claim on this page was measured. `-SelfTest` runs the
negative controls in a temp directory. `-Force`, `-HooksDir`, `-FragmentPath`, `-SkillsRoot` and
`-FloorTemplate` exist for the cases where discovery is wrong or a path is unusable; the script
names the one you need when it needs one.

Exit codes are the pack's: **0** installed · **1** failed, nothing written or the backup restored ·
**2** deliberately incomplete — a dry run, or a decline. **A skip is never a pass.**

> **Nothing is in effect until you open a new session.** The configuration file, the always-on
> fragment and the skills are read at startup, not mid-session. An installer that said "done" and
> left you testing a session that had already loaded the old configuration would be reporting a
> success you cannot observe.

## What makes this safe enough to run actively

The conservative sibling, `../claude-memory-toolkit/install.py`, copies its files and *prints* the
configuration snippet for you to merge. That is the right default and it cannot break anything. An
active install was chosen here on purpose — a floor that waits for a manual merge is not a floor —
so the safety has to be earned rather than assumed:

- **One dated fact drives the whole design: a configuration file that fails validation is rejected
  whole.** A malformed write does not cost you one bad rule, it switches the file off. So every
  write goes temp file → parse and shape-validate → back up → swap → read back → re-parse, and any
  failure in that sequence restores the backup **and names it**.
- **It refuses to repair.** If your configuration file does not already parse, the script stops
  before writing anything and tells you to fix it by hand. What a broken file *meant* to say is a
  guess, and a guess written there silently changes which permissions apply.
- **Union-merge, never replace.** Your own deny and ask entries, your unrelated keys, and your other
  hooks all survive. The `allow` list is never touched at all — it is the only list that *grants*.
- **An install manifest, because JSON has no comment markers.** The managed-block trick used by
  `../claude-worktree-toolkit/Install.ps1` cannot mark ownership inside a JSON file, so the script
  records every entry it added. `-Uninstall` removes exactly those. Without that record an uninstall
  either under-removes or eats rules you wrote yourself.
- **It declines rather than reverts.** Anything you have changed since installing is left alone and
  reported, and that run exits 2 — refusing to overwrite your edit is the script working, but the
  layer is then partly installed and must not read as clean.
- **Your pre-install backups are named and never deleted.** "Redundant" is the script's opinion, and
  acting on it deletes somebody's only copy of their old configuration.

## What it does not cover

Stated here rather than discovered later, because a limit you find yourself is a limit nobody
warned you about.

- **The hook firing under a live session is not exercised by any test here.** The self-test proves
  the hook is *installed*, that its command re-parses, and that the guard file exists beside the
  entry naming it. Whether the tool then invokes it as intended needs a real session, and no gate in
  this pack can assert it. Treat that as unmeasured.
- **The guard has known gaps of its own**, listed in `../claude-permission-toolkit/README.md` as
  passing probes rather than prose — so the day one closes, a gate goes red and somebody has to come
  and say so. Read them before relying on it.
- **Uninstall cannot distinguish an entry you added independently** from the identical entry the
  script installed. Two identical strings have no provenance, so that one will be removed. It is
  recorded in the script's header as the price of merging by value.
- **The skills carry `owner` and `approved_by` as an unset placeholder.** That is honest for a
  recipient we do not know, and it is also a real gap: set them before you adopt the layer, because
  a governance field nobody has filled in is a question with no answer rather than an answer of
  "nobody".
- **Four skills is not the whole practice.** Only the disciplines that reduce cleanly to a procedure
  are here. The reasoning, the failure stories, and everything that needs judgement stay in
  `../claude-dev-practice/` and are meant to be read.

## A note on what "enforced" means here

The floor and the hook are enforcement: they act whether or not anyone remembers them. The fragment
and the skills are not — they load into context, and what happens next is a judgement call made by a
model. That difference is deliberate and worth keeping in view, because the failure mode of this
whole unit is treating the second kind as though it were the first.

So the fragment is short on purpose. It is charged to every task, including the ones it has nothing
to say about, and a long always-on file is a slow tax on all of them plus a weaker signal on each.
If a rule only bites in one area, it belongs in a path-scoped rules file rather than here; if it is
a procedure, it belongs in a skill. The
[front door](../claude-dev-practice/CODING-WITH-CLAUDE-CODE.md) sets out which home is which and
why the wrong one fails quietly.
