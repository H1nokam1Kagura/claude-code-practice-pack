#!/usr/bin/env python3
"""Tests for replay_permissions.py -- stdlib unittest, no network, no fixtures on disk.

The four breakers in TestKnownWorkflowBreakers are the point of the whole tool. Each is a real rule
that was proposed for a real floor, read as obviously correct, and would have broken real work.
They are kept as tests so the matcher can never regress into agreeing with the intuition instead
of with the harness. A fifth case is kept there for the opposite reason -- it was a breaker until
the harness closed it, and it now records what the matcher models rather than a live gap.

    python test_replay.py
"""
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from replay_permissions import (
    ALLOW, ASK, DENY, UNMATCHED, Ruleset, load_corpus, parse_rule, rule_matches,
)


def rs(deny=(), ask=(), allow=()) -> Ruleset:
    return Ruleset(list(deny), list(ask), list(allow))


class TestRuleParsing(unittest.TestCase):
    def test_bare_tool_has_no_pattern(self):
        r = parse_rule("PowerShell")
        self.assertEqual(r.tool, "PowerShell")
        self.assertIsNone(r.pattern)

    def test_bare_tool_matches_every_invocation(self):
        self.assertTrue(rule_matches(parse_rule("PowerShell"), "PowerShell", "anything at all"))

    def test_pattern_containing_parentheses_survives(self):
        # A lazy regex truncates at the first ')' and silently changes the rule's meaning.
        r = parse_rule('Bash(echo "(x)")')
        self.assertEqual(r.tool, "Bash")
        self.assertEqual(r.pattern, 'echo "(x)"')

    def test_empty_and_junk_are_rejected_not_guessed(self):
        self.assertIsNone(parse_rule(""))
        self.assertIsNone(parse_rule("   "))


class TestPerToolIsolation(unittest.TestCase):
    def test_a_bash_rule_does_not_constrain_powershell(self):
        r = rs(deny=["Bash(rm -rf /)"])
        self.assertEqual(r.decide("PowerShell", "rm -rf /")[0], UNMATCHED)

    def test_a_read_rule_does_not_constrain_bash(self):
        r = rs(deny=["Read(**/.env)"])
        self.assertEqual(r.decide("Read", ".env")[0], DENY)
        self.assertEqual(r.decide("Bash", "cat .env")[0], UNMATCHED)


class TestOrdering(unittest.TestCase):
    def test_deny_beats_a_more_specific_allow(self):
        # First match wins and specificity is ignored -- the narrow allow does not rescue this.
        r = rs(deny=["Bash(git push --force *)"], allow=["Bash(git push --force origin main)"])
        self.assertEqual(r.decide("Bash", "git push --force origin main")[0], DENY)

    def test_ask_fires_even_though_allow_also_matches(self):
        r = rs(ask=["Bash(git push*)"], allow=["Bash(git *)"])
        self.assertEqual(r.decide("Bash", "git push origin main")[0], ASK)


class TestCompoundSplitting(unittest.TestCase):
    def test_every_segment_must_match_for_allow(self):
        r = rs(allow=["Bash(ls *)"])
        self.assertEqual(r.decide("Bash", "ls -la")[0], ALLOW)
        self.assertEqual(r.decide("Bash", "ls -la && rm -rf /tmp/x")[0], UNMATCHED)

    def test_one_denied_segment_denies_the_whole_command(self):
        r = rs(deny=["Bash(cat *.env)"], allow=["Bash(ls *)", "Bash(cat *)"])
        self.assertEqual(r.decide("Bash", "ls -la; cat prod.env")[0], DENY)

    def test_double_pipe_is_not_split_into_two_empty_segments(self):
        r = rs(allow=["Bash(ls *)", "Bash(echo *)"])
        self.assertEqual(r.decide("Bash", "ls -la || echo failed")[0], ALLOW)

    def test_path_tools_are_not_split(self):
        # A filename may legitimately contain ';' or '|'; splitting a path would be nonsense.
        r = rs(allow=["Read(**/a;b.txt)"])
        self.assertEqual(r.decide("Read", "a;b.txt")[0], ALLOW)


class TestWildcardWidth(unittest.TestCase):
    def test_star_spans_spaces_in_command_patterns(self):
        r = rs(allow=["Bash(git *)"])
        self.assertEqual(r.decide("Bash", "git log --oneline -n 5")[0], ALLOW)


class TestPathGlobs(unittest.TestCase):
    def test_double_star_prefix_also_matches_at_the_root(self):
        # Read(**/.env) must catch '.env' in the cwd, or it misses the file it exists for.
        r = rs(deny=["Read(**/.env)"])
        self.assertEqual(r.decide("Read", ".env")[0], DENY)
        self.assertEqual(r.decide("Read", "app/config/.env")[0], DENY)

    def test_single_star_does_not_cross_a_separator(self):
        r = rs(deny=["Read(secrets/*)"])
        self.assertEqual(r.decide("Read", "secrets/key.txt")[0], DENY)
        self.assertNotEqual(r.decide("Read", "secrets/nested/key.txt")[0], DENY)

    def test_windows_separators_are_normalised(self):
        r = rs(deny=["Read(**/.ssh/**)"])
        self.assertEqual(r.decide("Read", r"C:\Users\x\.ssh\id_rsa")[0], DENY)


class TestKnownWorkflowBreakers(unittest.TestCase):
    """Four rules that read as obviously correct and each broke a real workflow.

    All four were caught by replay in seconds and none was visible by inspection. If any of these
    starts passing, the matcher has drifted toward the intuition and away from the harness.

    A FIFTH case is kept here and is no longer one of the four -- see
    test_read_rule_is_not_a_bash_rule_in_the_matcher. It was a breaker until the harness closed it.
    Its assertion is unchanged and still correct; what went false was the story, and a test whose
    story has gone false goes on passing. That is why the docstrings here are load-bearing.
    """

    def test_rm_rf_slash_star_blocks_ordinary_scratch_deletes(self):
        # Under Git Bash every absolute path begins with '/', so this denies far more than root.
        r = rs(deny=["Bash(rm -rf /*)"])
        self.assertEqual(r.decide("Bash", "rm -rf /tmp/scratch/build")[0], DENY)

    def test_no_space_wildcard_swallows_force_with_lease(self):
        """The reason the floor spells the force-push denies out longhand.

        `git push --force*` is the natural way to write it and it also denies
        `--force-with-lease`, which is the SAFE form and is in active use.
        """
        naive = rs(deny=["Bash(git push --force*)"])
        self.assertEqual(naive.decide("Bash", "git push --force-with-lease origin x")[0], DENY)

        correct = rs(deny=["Bash(git push --force)", "Bash(git push --force *)"])
        self.assertNotEqual(
            correct.decide("Bash", "git push --force-with-lease origin x")[0], DENY)
        self.assertEqual(correct.decide("Bash", "git push --force origin x")[0], DENY)

    def test_read_rule_is_not_a_bash_rule_in_the_matcher(self):
        """NO LONGER A WORKFLOW BREAKER, and kept to say so. Do not weaken the assertion.

        This was on the list as `Read(**/.env)` says nothing about `cat .env`. The matcher models
        permission RULES, literally and per tool, and by that model a Read rule is not a Bash rule
        -- which is what this asserts and what remains true.

        What changed is the harness around the rules. As of 2026-08-16 it applies Read and Edit
        DENY rules to the file commands it recognises in Bash -- cat, head, tail, sed -- so the
        floor this case said failed to bind now binds. The consequence for this tool is that it
        UNDER-predicts denials on those commands: it reports ALLOW where the live harness blocks.
        That is the safe direction for a regression detector, which must never invent a regression,
        and it is a stated limit rather than a defect to patch here -- the matcher is a model of
        the rules, and modelling a separate enforcement layer inside it would make the two
        indistinguishable in the output.

        The per-tool PRINCIPLE is untouched: a Write(path) rule is accepted and never consulted,
        no file rule reaches a Python or Node script that opens the file itself, and a floor
        written in one tool's spelling is still half a floor. TestPerToolIsolation holds the
        matcher to the part of that a rule model can express.
        """
        r = rs(deny=["Read(**/.env)"], allow=["Bash(cat *)"])
        self.assertEqual(r.decide("Bash", "cat .env")[0], ALLOW)

    def test_star_secret_star_blocks_the_secret_guard_itself(self):
        r = rs(deny=["Read(**/*secret*)"])
        self.assertEqual(r.decide("Read", "hooks/secret-guard.ps1")[0], DENY)

    def test_env_dot_star_blocks_the_example_template(self):
        r = rs(deny=["Read(**/.env.*)"])
        self.assertEqual(r.decide("Read", ".env.example")[0], DENY)


class TestBlastRadius(unittest.TestCase):
    def test_an_interpreter_grant_is_flagged(self):
        r = rs(allow=["Bash(ls *)", "Bash(pwsh *)", "Bash(python3 *)"])
        flagged = {x.raw for x in r.arbitrary_execution_grants()}
        self.assertEqual(flagged, {"Bash(pwsh *)", "Bash(python3 *)"})

    def test_a_bare_command_tool_is_flagged(self):
        r = rs(allow=["PowerShell"])
        self.assertEqual([x.raw for x in r.arbitrary_execution_grants()], ["PowerShell"])

    def test_a_path_prefixed_interpreter_is_still_an_interpreter(self):
        r = rs(allow=["Bash(/usr/bin/python3 *)"])
        self.assertTrue(r.arbitrary_execution_grants())

    def test_an_mcp_tool_is_not_arbitrary_execution(self):
        self.assertFalse(rs(allow=["mcp__x__query"]).arbitrary_execution_grants())


class TestCorpusLoading(unittest.TestCase):
    def _write(self, obj, suffix=".json") -> Path:
        f = tempfile.NamedTemporaryFile("w", suffix=suffix, delete=False, encoding="utf-8")
        f.write(json.dumps(obj) if suffix == ".json" else obj)
        f.close()
        return Path(f.name)

    def test_literals_and_representatives_are_distinguished(self):
        p = self._write({"permissions": {"allow": ["Bash(git status)", "Bash(git log *)"]}})
        c = load_corpus(p)
        self.assertEqual(len(c.entries), 2)
        self.assertEqual([e.representative for e in c.entries], [False, True])

    def test_literals_only_drops_the_representatives(self):
        p = self._write({"permissions": {"allow": ["Bash(git status)", "Bash(git log *)"]}})
        self.assertEqual(len(load_corpus(p, literals_only=True).entries), 1)

    def test_bare_tool_entries_are_not_counted_as_coverage(self):
        # "PowerShell" records a wholesale grant; there is no invocation to replay.
        p = self._write({"permissions": {"allow": ["PowerShell", "Bash(ls -la)"]}})
        c = load_corpus(p)
        self.assertEqual(len(c.entries), 1)
        self.assertEqual(c.unparsed, [])

    def test_an_empty_allow_list_refuses_rather_than_passing(self):
        # Replaying nothing and reporting success is the failure this contract exists to prevent.
        p = self._write({"permissions": {"allow": []}})
        with self.assertRaises(SystemExit):
            load_corpus(p)

    def test_a_text_corpus_skips_comments_and_blanks(self):
        p = self._write("# a comment\n\nBash(ls -la)\n", suffix=".txt")
        self.assertEqual(len(load_corpus(p).entries), 1)


class TestMissingFloorIsVisible(unittest.TestCase):
    def test_absent_deny_and_ask_keys_do_not_error(self):
        # The absent floor is the single most common state and must be reportable, not fatal.
        r = rs(allow=["Bash(ls *)"])
        self.assertEqual(r.deny, [])
        self.assertEqual(r.ask, [])
        self.assertEqual(r.decide("Bash", "ls -la")[0], ALLOW)


if __name__ == "__main__":
    unittest.main(verbosity=2)
