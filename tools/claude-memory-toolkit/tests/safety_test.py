# -*- coding: utf-8 -*-
"""
Data-safety suite for ../rebuild_memory_index.py.

Proves the toolkit ONLY ever writes MEMORY.md (+ .bak / .tmp) and NEVER modifies or deletes a
topic file — including on adversarial input and when mis-pointed at a foreign folder. Uses a
throwaway system-temp fixture (never writes inside the repo) and sha256-checks every file
before/after each run.

Run:  python tests/safety_test.py     (exit 0 = all pass)
Pure stdlib; no dependencies.
"""
import os, sys, io, hashlib, shutil, subprocess, glob, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.normpath(os.path.join(HERE, "..", "rebuild_memory_index.py"))
PY = sys.executable or "python"
results = []


def check(name, ok, detail=""):
    results.append(ok)
    print(("PASS " if ok else "FAIL ") + name + (("  -- " + detail) if detail and not ok else ""))


def sha(p):
    with open(p, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def snapshot(d):
    return {os.path.basename(p): sha(p) for p in glob.glob(os.path.join(d, "*")) if os.path.isfile(p)}


def run(d, *extra):
    return subprocess.run([PY, SCRIPT, "--dir", d] + list(extra), capture_output=True, text=True)


def w(d, fn, content, binary=False):
    p = os.path.join(d, fn)
    if binary:
        with open(p, "wb") as f:
            f.write(content)
    else:
        with io.open(p, "w", encoding="utf-8", newline="\n") as f:
            f.write(content)


def main():
    base = tempfile.mkdtemp(prefix="cmt_safety_")
    try:
        # ---------- Fixture: a realistic, adversarial memory dir ----------
        w(base, "feedback_rule_a.md", "---\nname: rule-a\ndescription: cross-cutting rule A\nmetadata:\n  type: feedback\n---\nbody [[rule-b]]\n")
        w(base, "feedback_rule_b.md", "---\nname: rule-b\ndescription: cross-cutting rule B\nmetadata:\n  type: feedback\n---\nbody\n")
        w(base, "project_hub.md", "---\nname: hub\ndescription: a hub\nmetadata:\n  type: project\n---\ncited [[rule-a]]\n")
        w(base, "reference_archived_thing.md", "---\nname: archived-thing\ndescription: old\nmetadata:\n  type: reference\n  index: false\n---\nkept on disk, not indexed\n")
        w(base, "project_dupe1.md", "---\nname: same-slug\ndescription: dup 1\nmetadata:\n  type: project\n---\nx\n")
        w(base, "project_dupe2.md", "---\nname: same-slug\ndescription: dup 2\nmetadata:\n  type: project\n---\nx\n")
        w(base, "NOTES.md", "# not a memory\njust notes, no frontmatter\n")
        w(base, "reference_binary.md", b"\xff\xfe\x00 garbage \x80\x81 not utf8", binary=True)
        w(base, "feedback_unicode.md", "---\nname: unicode-note\ndescription: café naïve — 日本語 \U0001F600\nmetadata:\n  type: feedback\n---\nx\n")
        w(base, "project_empty.md", "")
        w(base, "project_no_type.md", "---\nname: no-type\ndescription: foreign schema, no type field\n---\nx\n")
        HAND = "My hand-written memory index\n- do not lose this\n"
        w(base, "MEMORY.md", HAND)

        before = snapshot(base)
        topic_before = {k for k in before if k != "MEMORY.md"}

        r1 = run(base)
        check("run1 exits 0 (no crash on adversarial input)", r1.returncode == 0, r1.stderr[-300:])
        after1 = snapshot(base)

        changed = [k for k in topic_before if before.get(k) != after1.get(k)]
        check("A. NO topic file modified (all sha256 identical)", not changed, "changed: %s" % changed)
        missing = topic_before - set(after1)
        check("B. NO topic file deleted", not missing, "missing: %s" % missing)

        bak = os.path.join(base, "MEMORY.md.bak")
        bak_ok = os.path.exists(bak) and io.open(bak, encoding="utf-8").read() == HAND
        check("C. hand-authored MEMORY.md preserved verbatim -> MEMORY.md.bak", bak_ok)

        mm = io.open(os.path.join(base, "MEMORY.md"), encoding="utf-8").read()
        check("D. MEMORY.md regenerated (has index header)", mm.startswith("# Memory Index"))
        check("E. index:false file kept on disk AND omitted from index",
              os.path.exists(os.path.join(base, "reference_archived_thing.md")) and "archived_thing" not in mm)
        check("F. stray/binary/empty files excluded from index",
              all(x not in mm for x in ("NOTES", "reference_binary", "project_empty")))
        check("G. no stray MEMORY.md.tmp (atomic write clean)", not os.path.exists(os.path.join(base, "MEMORY.md.tmp")))

        s1 = sha(os.path.join(base, "MEMORY.md"))
        r2 = run(base)
        s2 = sha(os.path.join(base, "MEMORY.md"))
        check("H. idempotent (MEMORY.md byte-identical on re-run)", s1 == s2)
        check("H2. re-run reports 'unchanged, not rewritten'", "unchanged" in r2.stdout)
        check("I. MEMORY.md.bak not clobbered on subsequent runs", io.open(bak, encoding="utf-8").read() == HAND)
        check("J. duplicate-name warning surfaced", "DUPLICATE" in r1.stdout)

        # ---------- Foreign-dir safety: point at a NON-memory folder ----------
        foreign = os.path.join(base, "foreign")
        os.makedirs(foreign)
        w(foreign, "meeting-notes.md", "---\ntitle: Q3 planning\ntags: [work]\n---\nImportant personal notes. DO NOT TOUCH.\n")
        w(foreign, "recipe.md", "# Grandma's recipe\n2 cups flour...\n")
        fbefore = snapshot(foreign)
        run(foreign)
        fafter = snapshot(foreign)
        fchanged = [k for k in fbefore if fbefore[k] != fafter.get(k)]
        check("K. foreign dir: pre-existing .md files NOT modified", not fchanged, "changed: %s" % fchanged)
        check("K2. foreign dir: no file deleted", set(fbefore).issubset(set(fafter)))

        npass = sum(1 for ok in results if ok)
        print("\n%d/%d PASS" % (npass, len(results)))
        return 0 if npass == len(results) else 1
    finally:
        shutil.rmtree(base, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
