#!/usr/bin/env python3
"""Tests for secret_guard.py -- driven off guard-probes.json, plus the cases that file cannot hold.

The probe file is the shared specification: check_guard_parity.py runs it against both guards, and
this suite runs it against the Python one alone, so the twin is still tested on a machine with no
pwsh -- which is the entire reason the twin exists.

    python test_secret_guard.py
"""
from __future__ import annotations

import json
import subprocess
import sys
import unittest
from pathlib import Path

from secret_guard import main, reasons_to_block

HERE = Path(__file__).resolve().parent
PROBES = json.loads((HERE / "guard-probes.json").read_text(encoding="utf-8"))["probes"]


class TestAgainstTheSharedProbes(unittest.TestCase):
    def test_probe_file_is_not_empty(self):
        # A suite that silently ran zero probes and reported OK is the failure this whole toolkit
        # is written against.
        self.assertGreater(len(PROBES), 15)

    def test_every_probe(self):
        for p in PROBES:
            with self.subTest(probe=p["id"]):
                blocked = bool(reasons_to_block(p["tool"], p["command"]))
                note = p.get("gap") or p.get("why", "")
                self.assertEqual(
                    blocked, bool(p["expect_block"]),
                    "%s: expected block=%s, got %s -- %s"
                    % (p["id"], p["expect_block"], blocked, note[:120]))


class TestTheRegressionThatMadeTheTwinNecessary(unittest.TestCase):
    """The lookahead-after-a-greedy-class defect, kept as named tests.

    The version this was lifted from told the user to emit `.Length` or `[bool]$env:X` instead of a
    value, and blocked both. `(?!\\.(Length|Count))` sat after a greedy `[A-Za-z0-9_]*`, so the
    engine gave back one character of the variable name and matched anyway. A guard that blocks its
    own remediation advice teaches exactly one lesson: use the override.
    """

    def test_length_is_allowed(self):
        self.assertEqual(reasons_to_block("PowerShell", "Write-Host $env:DB_PASSWORD.Length"), [])

    def test_count_is_allowed(self):
        self.assertEqual(reasons_to_block("PowerShell", "Write-Output $env:API_TOKEN.Count"), [])

    def test_bool_cast_is_allowed(self):
        self.assertEqual(reasons_to_block("PowerShell", "Write-Host ([bool]$env:DB_PASSWORD)"), [])

    def test_but_the_bare_value_is_still_blocked(self):
        # The exemptions must not have opened the barn door they were meant to leave shut.
        self.assertTrue(reasons_to_block("PowerShell", "Write-Host $env:DB_PASSWORD"))

    def test_a_safe_use_beside_an_unsafe_one_still_blocks(self):
        # Scrubbing removes the safe span only; the leak in the same command must survive it.
        self.assertTrue(reasons_to_block(
            "PowerShell", "Write-Host $env:DB_PASSWORD.Length; Write-Host $env:API_TOKEN"))


class TestPerToolScope(unittest.TestCase):
    def test_only_bash_and_powershell_are_inspected(self):
        for tool in ("Read", "Write", "Edit", "Glob", "WebFetch", "mcp__x__query"):
            with self.subTest(tool=tool):
                self.assertEqual(reasons_to_block(tool, "Write-Host $env:DB_PASSWORD"), [])

    def test_both_shells_are_inspected(self):
        for tool in ("Bash", "PowerShell"):
            with self.subTest(tool=tool):
                self.assertTrue(reasons_to_block(tool, "echo $DB_PASSWORD"))


class TestOverride(unittest.TestCase):
    def test_override_releases_the_block(self):
        self.assertEqual(
            reasons_to_block("PowerShell", "Write-Host $env:DB_PASSWORD # secret-guard: allow"), [])

    def test_override_is_case_and_space_insensitive(self):
        self.assertEqual(
            reasons_to_block("Bash", "echo $API_TOKEN #  SECRET-GUARD:   ALLOW"), [])

    def test_a_near_miss_does_not_release_it(self):
        # "secret guard allow" is not the override. An escape hatch you can hit by accident is not
        # an escape hatch.
        self.assertTrue(reasons_to_block("Bash", "echo $API_TOKEN # secret guard allow"))


class TestFailsOpen(unittest.TestCase):
    """Every one of these must exit 0 and emit nothing. A guard bug must never brick tool use."""

    def _run(self, stdin_text: str):
        p = subprocess.run([sys.executable, str(HERE / "secret_guard.py")],
                           input=stdin_text, capture_output=True, text=True)
        return p.returncode, p.stdout.strip()

    def test_empty_stdin(self):
        self.assertEqual(self._run(""), (0, ""))

    def test_malformed_json(self):
        self.assertEqual(self._run("{not json"), (0, ""))

    def test_missing_tool_input(self):
        self.assertEqual(self._run(json.dumps({"tool_name": "Bash"})), (0, ""))

    def test_null_command(self):
        self.assertEqual(
            self._run(json.dumps({"tool_name": "Bash", "tool_input": {"command": None}})), (0, ""))

    def test_wrong_shape_entirely(self):
        self.assertEqual(self._run(json.dumps([1, 2, 3])), (0, ""))


class TestDenyIsCarriedInJsonNotTheExitCode(unittest.TestCase):
    def test_block_emits_a_deny_decision_and_still_exits_zero(self):
        payload = json.dumps({"tool_name": "PowerShell",
                              "tool_input": {"command": "Write-Host $env:DB_PASSWORD"}})
        p = subprocess.run([sys.executable, str(HERE / "secret_guard.py")],
                           input=payload, capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, "the deny travels in the JSON, never in the exit code")
        out = json.loads(p.stdout)["hookSpecificOutput"]
        self.assertEqual(out["hookEventName"], "PreToolUse")
        self.assertEqual(out["permissionDecision"], "deny")
        self.assertIn("secret-guard: allow", out["permissionDecisionReason"],
                      "a block must tell the user how to override it deliberately")


class TestKnownGapsAreStillGaps(unittest.TestCase):
    """The gaps are asserted, not just described.

    Prose describing a limitation drifts away from the code silently. These fail the day a gap is
    closed -- which is the right time to be told, because the README says the gap exists.
    """

    def test_gap_probes_exist_and_are_all_non_blocking(self):
        gaps = [p for p in PROBES if "gap" in p]
        self.assertGreaterEqual(len(gaps), 5, "the documented gaps are not all represented")
        for p in gaps:
            with self.subTest(probe=p["id"]):
                self.assertFalse(p["expect_block"])
                self.assertFalse(bool(reasons_to_block(p["tool"], p["command"])))

    def test_pipe_to_shell_is_the_headline_gap_and_is_recorded(self):
        ids = {p["id"] for p in PROBES if "gap" in p}
        self.assertIn("gap-pipe-to-shell", ids)
        self.assertIn("gap-iwr-to-iex", ids)


if __name__ == "__main__":
    unittest.main(verbosity=2)
