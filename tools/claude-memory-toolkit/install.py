#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
install.py — one-command setup for claude-memory-toolkit.

  * finds your Claude Code memory directory (or takes --dir),
  * copies the toolkit into ~/.claude/hooks/claude-memory-toolkit/,
  * runs an initial index rebuild,
  * prints the settings.json snippet to auto-rebuild on every memory write.

It never edits settings.json for you (that's yours to merge) and never deletes anything.
Pure stdlib. Cross-platform.

Usage:
    python install.py                 # auto-detect the memory dir
    python install.py --dir "<path>"  # specify the memory dir explicitly
    python install.py --print-only    # just print the hook snippet, install nothing
"""
import os, sys, glob, shutil, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
CLAUDE = os.path.join(os.path.expanduser("~"), ".claude")
DEST = os.path.join(CLAUDE, "hooks", "claude-memory-toolkit")


def _arg(name):
    for i, a in enumerate(sys.argv):
        if a == name and i + 1 < len(sys.argv):
            return sys.argv[i + 1]
        if a.startswith(name + "="):
            return a.split("=", 1)[1]
    return None


def find_memory_dirs():
    found = []
    for d in glob.glob(os.path.join(CLAUDE, "projects", "*", "memory")):
        if os.path.exists(os.path.join(d, "MEMORY.md")) or glob.glob(os.path.join(d, "*.md")):
            found.append(d)
    return found


def main():
    print_only = "--print-only" in sys.argv
    memdir = _arg("--dir")

    if not memdir and not print_only:
        cands = find_memory_dirs()
        if len(cands) == 1:
            memdir = cands[0]
            print("memory dir detected: %s" % memdir)
        elif len(cands) > 1:
            print("Multiple memory dirs found — re-run with --dir set to one of:")
            for c in cands:
                print("  " + c)
            return 1
        else:
            print("No Claude memory dir found under %s%sprojects%s*%smemory."
                  % (CLAUDE, os.sep, os.sep, os.sep))
            print("Re-run with:  python install.py --dir \"<path-to-your-memory-dir>\"")
            return 1

    py = (sys.executable or "python").replace("\\", "/")
    script = os.path.join(DEST, "rebuild_memory_index.py")

    if not print_only:
        os.makedirs(DEST, exist_ok=True)
        for f in ("rebuild_memory_index.py", "README.md"):
            src = os.path.join(HERE, f)
            if os.path.exists(src):
                shutil.copy2(src, DEST)
        print("installed -> %s" % DEST)
        print("running initial rebuild...")
        rc = subprocess.call([py, script, "--dir", memdir])
        if rc != 0:
            print("  (rebuild returned %d — check the memory dir path)" % rc)

    md = (memdir or "<YOUR_MEMORY_DIR>").replace("\\", "/")
    win = os.name == "nt"
    shell_line = '\n            "shell": "powershell",' if win else ""
    # Quote every path (spaces-safe). On Windows/PowerShell an exe invoked by a quoted path needs
    # the call operator `&`; POSIX shells don't.
    tmpl = '& "%s" "%s" --dir "%s"' if win else '"%s" "%s" --dir "%s"'
    cmd = (tmpl % (py, script.replace("\\", "/"), md)).replace('"', '\\"')
    snippet = ('''{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": "%s",%s
            "if": "Write(*memory*.md)",
            "timeout": 20,
            "statusMessage": "Recomputing memory index priority order..."
          }
        ]
      }
    ]
  }
}''' % (cmd, shell_line))

    print("\n--- OPTIONAL: auto-rebuild on every memory write ---")
    print("Merge this PostToolUse block into ~/.claude/settings.json:")
    print(snippet)
    print("\nRecursion-safe: the script writes MEMORY.md via file I/O (not the Write tool), so it")
    print("does not re-trigger this hook. You can also just run the rebuild by hand any time.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
