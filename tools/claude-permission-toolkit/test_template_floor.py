#!/usr/bin/env python3
"""Acceptance test for settings.template.json -- run in BOTH polarities, on purpose.

WHY ONE CORPUS IS NOT ENOUGH, AND THIS IS THE WHOLE POINT OF THE FILE

    The obvious way to validate a candidate floor is to replay a corpus of previously-approved
    commands against it and check that nothing is denied. Do only that here and the test cannot
    fail. The template ships an EMPTY `allow` list by design, so every entry the floor does not
    hit comes back UNMATCHED -- and UNMATCHED is not a regression. An empty floor and a good floor
    score identically: zero denials, exit 0, green.

    So the suite asserts both directions:

      MUST_NOT_DENY   ordinary work the floor must let through   (catches over-reach)
      MUST_DENY       the shapes the floor exists for            (catches a floor that does nothing)
      MUST_ASK        reversible but outward-facing              (catches a floor that over-denies)

    and then, because a suite that has never been red is not evidence, TestTheseAssertionsCanFail
    runs the same assertions against two deliberately broken rulesets and requires them to fail.

    The MUST_NOT_DENY set leads with the four rules in test_replay.py's TestKnownWorkflowBreakers --
    the ones that read as obviously correct and each broke a real workflow. There they are tested as
    traps to avoid. Here the SHIPPED floor is held to them as acceptance criteria.

    python test_template_floor.py
"""
from __future__ import annotations

import json
import unittest
from pathlib import Path

from replay_permissions import ALLOW, ASK, DENY, UNMATCHED, Ruleset, load_corpus

HERE = Path(__file__).resolve().parent
TEMPLATE = HERE / "settings.template.json"
CORPUS = HERE / "corpus" / "approved.example.txt"


# (tool, invocation, why it matters). The `why` is printed on failure, because a bare
# "expected DENY got UNMATCHED" tells a maintainer nothing about which property just broke.
MUST_NOT_DENY = [
    ("Read", ".env.example",
     "a template, not a secret -- Read(**/.env.*) would block it"),
    ("Read", "hooks/secret-guard.ps1",
     "the guard itself -- Read(**/*secret*) would block the thing doing the guarding"),
    ("Bash", "git push --force-with-lease origin feature/x",
     "the SAFE force form -- `git push --force*` swallows it, so the floor spells it out longhand"),
    ("Bash", "rm -rf /tmp/scratch/build",
     "under Git Bash every absolute path starts with '/', so `rm -rf /*` denies ordinary work"),
    ("Read", "config/settings.yaml", "ordinary project file"),
    ("Edit", ".env.example",
     "the template again, on the write path -- seeding a real config from it must still work"),
    ("Edit", "src/parser/tokenize.py", "ordinary source edit"),
    ("Bash", "npm ci && npm test", "compound; every segment must pass independently"),
    ("Bash", "chmod +x scripts/deploy.sh", "not the 777 shape"),
    ("PowerShell", "Get-ChildItem -Recurse -File src", "ordinary inspection"),
]

MUST_DENY = [
    ("Bash", "rm -rf /", "root delete"),
    ("Bash", "rm -rf $HOME", "home delete"),
    ("PowerShell", "Remove-Item -Recurse -Force C:/", "root delete, the other tool spelling"),
    ("Bash", "git push --force origin main", "true force push"),
    ("PowerShell", "git push -f origin main", "true force push, the other tool spelling"),
    ("Bash", "chmod -R 777 /srv/app", "world-writable, recursively"),
    ("Read", ".env", "the secret itself"),
    ("Read", "app/config/.env", "…and nested, which is what the leading **/ is for"),
    ("Bash", "cat .env", "rules are PER TOOL: the Read deny says nothing about the shell"),
    ("PowerShell", "Get-Content prod.env", "…and nothing about the third spelling either"),
    ("Read", "secrets/api-key.txt", "a secrets directory"),
    ("Read", "C:\\Users\\someone\\.ssh\\id_rsa", "a private key, Windows separators"),
    ("Bash", "ls -la; cat prod.env", "one denied segment denies the whole compound"),
    ("Edit", ".env",
     "a Read deny covers Edit and Write but NOT NotebookEdit, so the floor spells Edit out too"),
    ("Edit", "app/config/.env", "…and nested, for the same reason"),
    ("Edit", "secrets/api-key.txt", "a secrets directory, by the write path"),
    ("Edit", "C:\\Users\\someone\\.ssh\\id_rsa", "a private key must be unwritable, not just unreadable"),
    ("Edit", "certs/client.pfx", "a certificate bundle, by the write path"),
]

MUST_ASK = [
    ("Bash", "git push origin main", "reversible, but it leaves this machine"),
    ("Bash", "gh pr merge 42 --squash", "outward-facing"),
    ("Bash", "docker rm app-dev", "reversible only if the image can be rebuilt"),
    ("PowerShell", "Register-ScheduledTask -TaskName x", "installs something that outlives the session"),
    ("Bash", "winget install SomeTool", "changes the machine, not the project"),
]


def _template() -> Ruleset:
    return Ruleset.from_settings(TEMPLATE)


def _read_denies_without_an_edit_twin(rs: Ruleset) -> list:
    """Read-deny path patterns the floor does not also deny to Edit.

    Factored out so the property can be run against a deliberately broken ruleset as well as
    against the template -- an assertion that has only ever been green is not evidence.
    """
    read = {r.pattern for r in rs.deny if r.tool == "Read"}
    edit = {r.pattern for r in rs.deny if r.tool == "Edit"}
    return sorted(read - edit)


class TestTemplateIsStillAFloor(unittest.TestCase):
    """Guards against the template being emptied, reshaped, or having secrets pasted back in."""

    def test_deny_and_ask_are_both_populated(self):
        rs = _template()
        self.assertTrue(rs.deny, "template has no deny list -- there is no floor")
        self.assertTrue(rs.ask, "template has no ask list -- there is no floor")

    def test_allow_is_empty_on_purpose(self):
        # If a starter allow-list ever lands here, it contradicts the artifact beside it: one
        # `Bash(pwsh *)` entry makes the whole list equivalent to `Bash(*)`.
        self.assertEqual(_template().allow, [])

    def test_no_arbitrary_execution_is_conceded(self):
        self.assertEqual(_template().arbitrary_execution_grants(), [])

    def test_ships_no_mcp_servers_and_no_env(self):
        # The live settings file this was derived from carries credentials under `mcpServers`.
        # The template must never grow one back.
        data = json.loads(TEMPLATE.read_text(encoding="utf-8"))
        for forbidden in ("mcpServers", "env", "apiKeyHelper", "awsAuthRefresh"):
            self.assertNotIn(forbidden, data, f"template must not ship a '{forbidden}' block")

    def test_every_read_deny_is_mirrored_as_an_edit_deny(self):
        """A Read deny already covers the Edit and Write tools on that path. NotebookEdit is not
        covered, so without the Edit spelling every secret path here is unreadable and still
        writable -- and a floor that can be written to is not a floor.

        Asserted as a set difference rather than entry by entry, because the gap is invisible in a
        list where every line looks right on its own. Add a Read deny next year and forget the
        twin, and this fails; that is the point of writing it this way.
        """
        rs = _template()
        self.assertTrue([r for r in rs.deny if r.tool == "Read"],
                        "template has no Read denies -- the secret-path floor is gone")
        missing = _read_denies_without_an_edit_twin(rs)
        self.assertEqual(missing, [],
                         f"Read-denied paths with no Edit twin, so NotebookEdit may write them: {missing}")

    def test_every_shell_deny_is_written_in_both_tool_spellings(self):
        """A floor written in one tool's spelling is half a floor.

        Not every rule needs both -- `type`/`head`/`tail` are shell-only and `gc` is
        PowerShell-only -- so this asserts the PROPERTY that matters: for each of the
        unrecoverable families, at least one Bash rule and at least one PowerShell rule exist.
        """
        rs = _template()
        bash = [r.pattern for r in rs.deny if r.tool == "Bash"]
        pwsh = [r.pattern for r in rs.deny if r.tool == "PowerShell"]
        for family in ("rm -rf", "git push --force"):
            self.assertTrue(any(p.startswith(family) for p in bash), f"no Bash deny for {family}")
        self.assertTrue(any("Remove-Item" in p for p in pwsh), "no PowerShell recursive-delete deny")
        self.assertTrue(any(p.startswith("git push") for p in pwsh), "no PowerShell force-push deny")


class TestFloorLetsOrdinaryWorkThrough(unittest.TestCase):
    def test_must_not_deny(self):
        rs = _template()
        for tool, payload, why in MUST_NOT_DENY:
            with self.subTest(invocation=f"{tool}({payload})"):
                verdict, rule, seg = rs.decide(tool, payload)
                self.assertNotEqual(
                    verdict, DENY,
                    f"{tool}({payload}) was DENIED by {rule.raw if rule else '?'} "
                    f"on segment {seg!r} -- {why}")


class TestFloorCatchesWhatItExistsFor(unittest.TestCase):
    def test_must_deny(self):
        rs = _template()
        for tool, payload, why in MUST_DENY:
            with self.subTest(invocation=f"{tool}({payload})"):
                verdict, _, _ = rs.decide(tool, payload)
                self.assertEqual(verdict, DENY, f"{tool}({payload}) was {verdict} -- {why}")

    def test_must_ask(self):
        rs = _template()
        for tool, payload, why in MUST_ASK:
            with self.subTest(invocation=f"{tool}({payload})"):
                verdict, _, _ = rs.decide(tool, payload)
                self.assertEqual(verdict, ASK, f"{tool}({payload}) was {verdict} -- {why}")


class TestApprovedCorpusReplaysClean(unittest.TestCase):
    def test_corpus_is_not_empty(self):
        # Replaying nothing and reporting success is the failure the exit contract exists to stop.
        self.assertGreater(len(load_corpus(CORPUS).entries), 20)

    def test_nothing_in_the_corpus_is_denied(self):
        rs, corpus = _template(), load_corpus(CORPUS)
        self.assertEqual(corpus.unparsed, [], "corpus entries failed to parse -- not a pass")
        denied = []
        for e in corpus.entries:
            verdict, rule, _ = rs.decide(e.tool, e.payload)
            if verdict == DENY:
                denied.append(f"{e.tool}({e.payload}) by {rule.raw if rule else '?'}")
        self.assertEqual(denied, [], "previously-approved traffic is denied by this floor")


class TestTheseAssertionsCanFail(unittest.TestCase):
    """The negative controls. A suite that has never been red is not evidence.

    Every other test in this file passes against the real template. These prove that they are
    reading the template rather than agreeing with themselves -- one ruleset that denies nothing,
    one that denies everything, each of which must break the half of the suite it should break,
    and one that denies a path to Read alone.
    """

    def test_an_empty_floor_fails_the_must_deny_set(self):
        empty = Ruleset([], [], [])
        survived = [f"{t}({p})" for t, p, _ in MUST_DENY if empty.decide(t, p)[0] == DENY]
        self.assertEqual(
            survived, [],
            "sanity: an empty ruleset cannot deny anything")           # nothing should be DENY…
        # …which is exactly why MUST_DENY is load-bearing: without it, this empty floor would
        # pass every other test in the file.
        self.assertNotEqual(len(MUST_DENY), 0)

    def test_a_deny_everything_floor_fails_the_must_not_deny_set(self):
        paranoid = Ruleset(["Bash", "PowerShell", "Read", "Edit", "Write"], [], [])
        blocked = [f"{t}({p})" for t, p, _ in MUST_NOT_DENY if paranoid.decide(t, p)[0] == DENY]
        self.assertEqual(
            len(blocked), len(MUST_NOT_DENY),
            "a bare-tool deny must catch every MUST_NOT_DENY entry; if it does not, the "
            "over-reach half of this suite is not actually testing the tools it claims to")

    def test_a_read_only_deny_is_reported_as_unmirrored(self):
        # The state the template was in before the Edit entries were added: read-proof, writable.
        one_sided = Ruleset(["Read(**/.env)", "Read(**/*.pem)"], [], [])
        self.assertEqual(
            _read_denies_without_an_edit_twin(one_sided), ["**/*.pem", "**/.env"],
            "the mirror check must name a Read deny that has no Edit twin, or it passes on "
            "exactly the floor it exists to catch")


if __name__ == "__main__":
    unittest.main(verbosity=2)
