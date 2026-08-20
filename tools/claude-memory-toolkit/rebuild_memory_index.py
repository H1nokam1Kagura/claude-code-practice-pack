#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
rebuild_memory_index.py — priority-ordered index for Claude Code auto-memory.

Claude Code loads only the FIRST ~200 lines / ~25 KB of MEMORY.md at session start, then
truncates the rest. If you accumulate more memory than that, the tail silently stops loading.
This script regenerates MEMORY.md from each topic file's frontmatter and ORDERS it so the
highest-value entries survive the cut:

  1. Type grouping   — `feedback` (cross-cutting rules) first, then `project`, `reference`, `other`.
  2. Citation-centrality — within each section, entries cited by >= FLOAT_INBOUND_MIN other
                       memories (via [[name]] links) float to the top; leaf entries sink to the
                       bottom, where truncation is harmless.
  3. Per-file override — frontmatter `pin: true` force-floats an entry to the top of its section.

Priority is computed DYNAMICALLY from the live link graph on every run — it is never stored
per-memory. (A brand-new memory has 0 inbound citations at birth; a stored score would drift
the instant another memory cites it.)

SAFETY: this only ever WRITES MEMORY.md (via an atomic temp+rename, with a one-time .bak of any
pre-existing hand-authored MEMORY.md). Topic files are only ever READ — never modified or deleted.

TOPIC-FILE FRONTMATTER SCHEMA (YAML):
    ---
    name: kebab-case-slug          # the [[link]] target; defaults to the filename stem
    description: one-line summary   # becomes the index hook (truncated to HOOK_LIMIT)
    metadata:
      type: feedback | project | reference
      index: false                  # optional — keep on disk but omit from the index
      pin: true                     # optional — force-float to the top of its section
    ---
    <body…>  link related memories with [[their-name]]

CONFIG (env var wins, else CLI arg, else default):
    CLAUDE_MEMORY_DIR            memory dir (default: this script's own directory)
    CLAUDE_MEMORY_HOOK_LIMIT     max index-hook chars                 (default 46)
    CLAUDE_MEMORY_FLOAT_INBOUND  float-to-top citation threshold      (default 3)
    CLAUDE_MEMORY_LINE_BUDGET    lines that load before truncation    (default 200)
    CLAUDE_MEMORY_MARGIN         stability-warning band around the cut (default 15)

USAGE:  python rebuild_memory_index.py [--dir PATH]
Pure stdlib — no dependencies, any Python 3.6+. Safe to run on every memory write.
"""
import os, re, glob, io, sys


def _env_int(name, default):
    try:
        return int(os.environ.get(name, ""))
    except ValueError:
        return default


def _resolve_dir():
    for i, a in enumerate(sys.argv):
        if a == "--dir" and i + 1 < len(sys.argv):
            return sys.argv[i + 1]
        if a.startswith("--dir="):
            return a.split("=", 1)[1]
    return os.environ.get("CLAUDE_MEMORY_DIR") or os.path.dirname(os.path.abspath(__file__))


MEM = _resolve_dir()
HOOK_LIMIT = _env_int("CLAUDE_MEMORY_HOOK_LIMIT", 46)
FLOAT_INBOUND_MIN = _env_int("CLAUDE_MEMORY_FLOAT_INBOUND", 3)
LINE_BUDGET = _env_int("CLAUDE_MEMORY_LINE_BUDGET", 200)
# Entries landing within this many lines of the cut are "borderline" — a small unrelated memory
# change could flip them across the load boundary. The rebuild warns so you can `pin` the ones that
# matter. Keep LINE_BUDGET a little under the real 200 (e.g. 185) to bank headroom.
MARGIN = _env_int("CLAUDE_MEMORY_MARGIN", 15)


def parse(txt, fp):
    """Return (name, type, description, indexed, pin) from a topic file's frontmatter `txt`."""
    m = re.match(r"^---\s*\n(.*?)\n---", txt, re.S)
    fm = m.group(1) if m else ""

    def grab(k):
        # value match uses [ \t]* (not \s*) so an EMPTY field can't bleed onto the next line.
        mm = re.search(r"^[ \t]*%s:[ \t]*(.*)$" % k, fm, re.M)
        return mm.group(1).strip().strip('"').strip() if mm else ""

    name = grab("name") or os.path.splitext(os.path.basename(fp))[0]
    desc = grab("description").replace('\\"', '"').replace('\\', '')
    indexed = not re.search(r"^\s*index:\s*false", fm, re.M)
    pin = grab("pin").lower()
    t = "other"
    for line in fm.splitlines():
        s = line.strip()
        if s.startswith("type:") and "node_type" not in s:
            t = s.split("type:", 1)[1].strip() or "other"
            break
    return name, t, desc, indexed, pin


def title(name):
    s = re.sub(r"^(feedback|project|reference)_", "", name).replace("_", " ").strip()
    return s[:1].upper() + s[1:]


def hook(desc, limit=None):
    limit = HOOK_LIMIT if limit is None else limit
    d = " ".join(desc.split())
    if len(d) <= limit:
        return d
    cut = d[:limit]
    for sep in ["; ", ". ", " — ", ", ", " "]:
        idx = cut.rfind(sep)
        if idx > limit * 0.45:
            return cut[:idx].rstrip(" ;.,—") + " …"
    return cut.rstrip() + " …"


def main():
    files = sorted(f for f in glob.glob(os.path.join(MEM, "*.md"))
                   if os.path.basename(f) != "MEMORY.md")
    if not files:
        sys.stderr.write("no topic files in %s\n" % MEM)
        return

    # Pass 1: read each file ONCE (error-safe; handle closed promptly), parse, and skip non-memory
    # files (no frontmatter) or any file that fails to parse — a single bad file must never crash a
    # rebuild that runs on every memory write.
    meta = {}
    txts = {}
    skipped = []
    for fp in files:
        try:
            with io.open(fp, encoding="utf-8", errors="replace") as fh:
                txt = fh.read()
        except (IOError, OSError) as e:
            skipped.append("%s: unreadable (%s)" % (os.path.basename(fp), e))
            continue
        if not re.match(r"^---\s*\n.*?\n---", txt, re.S):
            continue  # not a memory (no frontmatter) — ignore stray .md files silently
        try:
            meta[fp] = parse(txt, fp)
            txts[fp] = txt
        except Exception as e:  # never let one malformed file abort the whole rebuild
            skipped.append("%s: parse error (%s)" % (os.path.basename(fp), e))
    files = [fp for fp in files if fp in meta]

    # Duplicate `name:` slugs collide in the citation graph (one overwrites the other) and mis-count.
    seen, dup_names = {}, []
    for fp in files:
        nm = meta[fp][0]
        if nm in seen:
            dup_names.append("%s & %s share name '%s'"
                             % (os.path.basename(seen[nm]), os.path.basename(fp), nm))
        else:
            seen[nm] = fp

    # Build the inbound-citation graph (count [[name]] links FROM active memories).
    inbound = {meta[fp][0]: 0 for fp in files}
    for fp in files:
        name, t, desc, indexed, pin = meta[fp]
        if not indexed:
            continue
        for tgt in set(re.findall(r"\[\[([A-Za-z0-9_-]+)\]\]", txts[fp])):
            if tgt in inbound and tgt != name:
                inbound[tgt] += 1

    # Pass 2: bucket by type.
    groups = {"feedback": [], "project": [], "reference": [], "other": []}
    dropped = 0
    for fp in files:
        name, t, desc, indexed, pin = meta[fp]
        if not indexed:
            dropped += 1
            continue
        ib = inbound.get(name, 0)
        row = (title(name), os.path.basename(fp), hook(desc), ib, pin)
        (groups[t] if t in groups else groups["other"]).append(row)

    def sortkey(r):
        # pinned + cited hubs (>= FLOAT_INBOUND_MIN) float to the top of the section, then alphabetical.
        floated = 0 if (r[4] in ("true", "float", "yes") or r[3] >= FLOAT_INBOUND_MIN) else 1
        return (floated, r[0].lower())

    order = [("feedback", "Feedback"), ("project", "Project"),
             ("reference", "Reference"), ("other", "Other")]
    out = ["# Memory Index",
           "_One line per memory; detail in each topic file. Superseded ones kept on disk (banner), omitted here._",
           "_Cross-cutting rules float first; within each section, memories cited by others float up and leaf "
           "entries sink — only the first %d lines load, so the least-referenced tail is the disposable one. "
           "`pin: true` locks an entry to the top._" % LINE_BUDGET]
    total = 0
    lineno = {}
    for key, label in order:
        rows = sorted(groups[key], key=sortkey)
        if not rows:
            continue
        out.append("")
        out.append("## " + label)
        for ttl, fn, hk, ib, pin in rows:
            out.append("- [%s](%s) — %s" % (ttl, fn, hk))
            lineno[fn] = len(out)
            total += 1

    content = "\n".join(out).rstrip() + "\n"
    path = os.path.join(MEM, "MEMORY.md")
    lines = content.count("\n")

    # Write ONLY if changed — idempotent; a no-op edit won't churn MEMORY.md or re-trigger anything.
    try:
        with io.open(path, encoding="utf-8", errors="replace") as fh:
            prev = fh.read()
    except (IOError, OSError):
        prev = None
    changed = (prev != content)
    if changed:
        # One-time safety net: if an existing MEMORY.md does NOT look like one this tool generated
        # (someone hand-authored it), preserve it as MEMORY.md.bak before the first overwrite. Never
        # clobber an existing .bak. Topic files are only ever READ — never touched.
        bak = path + ".bak"
        if prev is not None and not prev.lstrip().startswith("# Memory Index") and not os.path.exists(bak):
            try:
                with io.open(bak, "w", encoding="utf-8", newline="\n") as fh:
                    fh.write(prev)
                print("  safety: backed up your existing (non-generated) MEMORY.md -> MEMORY.md.bak")
            except (IOError, OSError):
                pass
        tmp = path + ".tmp"
        with io.open(tmp, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(content)
        os.replace(tmp, path)  # atomic swap — a crash mid-write never corrupts MEMORY.md

    # --- robustness self-checks (advisory; never fatal) ---
    dropped_cited = []   # cited entries already past the cut (must pin or they're lost)
    borderline = []      # non-pinned entries within MARGIN of the cut (could flip on a small change)
    schema = []          # frontmatter drift that will mis-index quietly
    for fp in files:
        name, t, desc, indexed, pin = meta[fp]
        if not indexed:
            continue
        bn = os.path.basename(fp)
        lp = lineno.get(bn, 0)
        ib = inbound.get(name, 0)
        if not desc:
            schema.append("%s: blank `description` (empty index hook)" % bn)
        elif t == "other" and re.match(r"^(feedback|project|reference)_", bn):
            schema.append("%s: filename implies a type but `type:` is missing/unrecognized" % bn)
        if pin in ("true", "float", "yes"):
            continue
        if ib >= FLOAT_INBOUND_MIN and lp > LINE_BUDGET:
            dropped_cited.append((ib, lp, name))
        elif LINE_BUDGET - MARGIN <= lp <= LINE_BUDGET + MARGIN:
            borderline.append((ib, lp, name))

    print("entries=%d dropped=%d bytes=%d lines=%d budget=%d%s"
          % (total, dropped, len(content.encode("utf-8")), lines, LINE_BUDGET,
             "" if changed else " (unchanged, not rewritten)"))
    if lines > LINE_BUDGET:
        print("  note: %d lines exceed the %d-line load budget — the tail will not auto-load." % (lines, LINE_BUDGET))
    if dropped_cited:
        print("  WARNING: %d well-cited memor%s fell past the cut (dropped) — add `pin: true` to protect:"
              % (len(dropped_cited), "y" if len(dropped_cited) == 1 else "ies"))
        for ib, lp, nm in sorted(dropped_cited, reverse=True):
            print("    line=%d inbound=%d %s" % (lp, ib, nm))
    if borderline:
        print("  STABILITY: %d entr%s within %d lines of the cut — a small change could flip them across it; `pin: true` to lock:"
              % (len(borderline), "y" if len(borderline) == 1 else "ies", MARGIN))
        for ib, lp, nm in sorted(borderline, reverse=True):
            print("    line=%d [%s] inbound=%d %s" % (lp, "loaded" if lp <= LINE_BUDGET else "dropped", ib, nm))
    if schema:
        print("  SCHEMA: %d file(s) may mis-index — fix frontmatter:" % len(schema))
        for w in schema[:12]:
            print("    " + w)
    if dup_names:
        print("  DUPLICATE names (citation counts collide — rename one):")
        for w in dup_names[:12]:
            print("    " + w)
    if skipped:
        print("  SKIPPED %d file(s) (unreadable or unparseable — left out of the index):" % len(skipped))
        for w in skipped[:12]:
            print("    " + w)


if __name__ == "__main__":
    main()
