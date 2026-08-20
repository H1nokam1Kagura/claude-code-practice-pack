# Testing discipline

What makes a test worth having. Every example is a real test in this repo, not an invention — the
paths are there so you can check the claim.

The one-line version:

> **Assert the property, not the implementation.** A test that restates the code passes for as long
> as the code is wrong in the same way.

---

## 1. Assert what must never happen

The strongest tests name a property that must hold *however* the code is written, then try to
violate it from every direction at once.

`skills/build-compliance/scripts/test_scan.py`:

```
test_no_credential_survives_into_a_serialised_finding
    "The control: a planted secret must not reach findings.json by ANY field."
```

Note what it does *not* do. It does not check that `redact()` was called, or that a particular
regex matched, or that `summary` was scrubbed. It plants a credential, runs the real pipeline, and
asserts the secret appears in **no field of the serialised output**. Add a new field to `Finding`
next year and forget to redact it, and this test fails — which a call-site assertion never would.

That is the shape to reach for: **plant the bad thing, run the real path, assert the bad thing is
absent from the whole output.**

A second in the same file:

```
test_every_control_cited_by_a_check_exists_in_the_catalog
    "A finding may cite only a control the catalog defines."
```

This is an *invariant across two artifacts* — code and data — rather than a fact about either. It
catches a class of drift (a check citing a control someone renamed) that no unit test of either
side would see.

---

## 2. Keep the bugs you have already paid for

When something breaks in a way that read as obviously correct beforehand, the fix is not the
lesson — the **test** is. `tools/claude-permission-toolkit/test_replay.py`:

```
class TestKnownWorkflowBreakers(unittest.TestCase):
    """Four rules that read as obviously correct and each broke a real workflow.

    All four were caught by replay in seconds and none was visible by inspection. If any of these
    starts passing, the matcher has drifted toward the intuition and away from the harness.
    """
```

Four permission rules, each of which looked fine written down and each of which broke real work:
`Bash(rm -rf /*)` (under Git Bash every absolute path starts with `/`), `Bash(git push --force*)`
(the no-space wildcard also swallows `--force-with-lease`, the safe form), `Read(**/*secret*)`
(blocks reading the secret-guard hook itself), `Read(**/.env.*)` (blocks `.env.example`).

Each is now a named test with its story in the docstring. The docstring matters as much as the
assertion: a bare `assert decide(...) == DENY` tells a future reader nothing about why anyone
cared.

A fifth case sits in the same class and is the reason the docstring is load-bearing. `Read(**/.env)`
against `cat .env` was on that list until 2026-08-16, when it stopped being true — the harness grew
a layer that applies file denies to the shell commands it recognises. The assertion was left exactly
as it was, because it still states what the matcher models; only the story around it was rewritten.
**A test whose story has gone false does not fail, and nothing else in a suite will tell you** —
which is why the story belongs where somebody editing the assertion has to read it.

**Corollary:** when you fix a bug, ask "what would have caught this?" and write *that*, not a test
of the patch.

---

## 3. Prove the safety claim you make in the README

If your docs promise a safety property, something should demonstrate it.
`tools/claude-memory-toolkit/tests/safety_test.py` exists because the README says *"your memory
files are never at risk"* and that *"your topic files are **read-only**"*. It sha256-checks every
file before and after a run and proves they are byte-identical — and the README then tells the
reader to run it themselves.

An unverified safety claim is a marketing claim. This one is checkable in about a second, which is
the difference.

---

## 4. Test the failure paths, not just the happy one

Most real damage happens on a path nobody exercised. Worth explicit tests:

- **The degraded mode.** `freshness.py --no-connector` exits 2 and banners the report. There is a
  test that a check which could not run reports SKIPPED and never PASS.
- **The unknown answer.** `_Wt-BranchSuperseded` returns `null` — not `false` — for an unresolvable
  ref, and a test asserts exactly that. "Unknown" collapsing into "no" is how a false negative gets
  manufactured.
- **The empty input.** `load_corpus` raises rather than reporting a successful replay of nothing.
  `load_source_map` refuses a file with no `documents` array. **Reporting zero coverage as success
  is the single failure mode most of these gates exist to prevent**, so it gets its own test.
- **The malformed input.** One bad file must not abort a batch. The memory toolkit skips and
  reports; a test proves a binary/empty/non-UTF-8 file does not take the run down.

---

## 5. Test the boundary you actually run on

`test_resolve_scan_dir_detects_a_worktree_gitfile`, in
`skills/build-compliance/scripts/test_scan.py`, looks like trivia until you know the story: in a
git **worktree**, `.git` is a *file*, not a directory. Mount that into a container and git cannot
resolve it — so the scanner logs an error, then prints "no leaks found" and **exits 0 after about
14 milliseconds** (recorded 2026-08-10). A false pass, which is worse than no scan.

The test is there because the environment, not the logic, was the bug. If your team runs on
worktrees, in containers, on Windows paths, behind a proxy — test that, because a green suite on a
substrate nobody uses is not evidence.

---

## 6. Make disagreement between two implementations a test

Where the same question is answered twice, gate the answers against each other rather than trusting
them to stay aligned.

`tools/claude-permission-toolkit/check_interpreter_parity.py` compares two independently written
detectors of "does this rule grant arbitrary execution?" On its first run they disagreed — and each
had found something the other missed. Neither gap was visible by reading either list.

This is the cheapest high-value test available whenever duplication is deliberate (two tools that
must ship standalone, a cached mirror, a spec and its implementation). **Keep the copies, gate the
copies.**

---

## 7. Anti-patterns

- **Mirroring the implementation.** If the test changes every time the code is refactored without
  behaviour changing, it is testing structure. Delete it or raise its altitude.
- **Asserting the mock.** Verifying that a function was called with certain arguments proves the
  test's model of the code, not the code.
- **A test that cannot fail.** Write it, watch it fail, then make it pass. `check_interpreter_parity`
  earned its keep by failing on run one; a gate that has never been red is unproven.
- **Counting tests.** A suite where every test asserts a property is worth more than one with three
  times as many asserting call sites. (And keep the count in the docs honest — a README claiming
  "28 tests" against a suite of 29 is a small thing that quietly teaches readers not to trust the
  docs.)
- **Trusting an exit code as evidence of work done.** `tar` archiving a symlink exits 0 having
  archived one entry. Assert the *contents*, not the status — see
  [REVERSIBILITY.md](REVERSIBILITY.md).
