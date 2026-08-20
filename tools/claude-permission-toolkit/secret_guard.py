#!/usr/bin/env python3
"""secret_guard.py -- the portable twin of secret-guard.ps1. Same detections, same verdicts.

WHY TWO IMPLEMENTATIONS
    The floor in settings.template.json is useless to a recipient who cannot run the hook that
    enforces it, and `pwsh` is not a safe assumption outside Windows. So the guard ships twice --
    once in the language the original was written and proven in, once in the language of the rest
    of this toolkit.

    Duplication is a liability unless something checks it. check_guard_parity.py feeds every probe
    in guard-probes.json to BOTH guards and requires them to return the same verdict AND the right
    one -- because two implementations that agree with each other and disagree with reality are no
    better than one. Same control, same reasoning, as check_interpreter_parity.py next door: keep
    the copies, gate the copies.

    Neither guard imports the other, and neither imports anything outside the standard library.

WHAT IT BLOCKS, WHAT IT DOES NOT, AND WHY IT FAILS OPEN
    Identical to secret-guard.ps1. That file's header is the canonical statement of the four
    detections and the six gaps (pipe-to-shell, name-based detection, the proximity window, the
    Bash/PowerShell-only scope, command-not-output, fail-open). It is not restated here, because a
    second copy of a limits list is exactly the thing that goes stale first. Read it there.

USAGE -- as a PreToolUse hook, reading the payload on stdin
    {"type": "command", "command": "python3 /path/to/secret_guard.py", "timeout": 10}

EXIT CONTRACT
    Always 0. The deny travels in the JSON on stdout, never in the exit code.

STDLIB ONLY. Python 3.8+.
"""
from __future__ import annotations

import json
import re
import sys

# A variable name that DENOTES a secret. Names only -- a secret in `$x` is invisible, by design
# and by necessity; see the gap list in secret-guard.ps1.
SECRET_NAME = (
    r"\$(?:env:)?[A-Za-z0-9_]*"
    r"(?:PASSWORD|PASS|PWD|TOKEN|SECRET|APIKEY|API_KEY|CREDENTIAL)"
    r"[A-Za-z0-9_]*"
)

# Uses that cannot leak a value. Stripped BEFORE the emit test rather than expressed as a negative
# lookahead -- a lookahead after a greedy character class is not a constraint, because the engine
# backtracks the name by one character and matches anyway. That defect is the reason the original
# blocked `.Length`, which is one of the two things its own block message tells you to do instead.
SAFE_USE = re.compile(
    r"(?:\[bool\]\s*" + SECRET_NAME + r")"
    r"|(?:" + SECRET_NAME + r"\s*\.\s*(?:Length|Count))",
    re.IGNORECASE,
)

OVERRIDE = re.compile(r"#\s*secret-guard:\s*allow", re.IGNORECASE)
PAT_LITERAL = re.compile(r"dapi[0-9a-f]{16,}")
PUT_SECRET = re.compile(r"secrets\s+put-secret", re.IGNORECASE)
STRING_VALUE = re.compile(r"--string-value(?:\s+|=)\S", re.IGNORECASE)
EMIT_SECRET = re.compile(
    r"(?:Write-Output|Write-Host|Write-Information|Out-Host|Out-Default|\becho\b|\bprintf\b)"
    r"\b[^\n;|]{0,30}" + SECRET_NAME,
    re.IGNORECASE,
)
ASSIGN_IN_PARENS = re.compile(r"\(\s*\$[A-Za-z_][A-Za-z0-9_]*\s*=")
ANY_SECRET = re.compile(SECRET_NAME, re.IGNORECASE)

GUARDED_TOOLS = ("Bash", "PowerShell")

_PAT = ("Literal vendor PAT (dapi...) present. Never inline a token -- use OAuth or a "
        "secret store.")
_PUT = ("put-secret --string-value <literal> puts the secret in argv and in shell history. "
        "Omit the flag and paste at the interactive prompt.")
_EMIT = ("Command appears to print a secret-bearing variable. Emit only its .Length or a "
         "set/unset boolean ([bool]$env:X) -- never the value. Both of those are allowed here.")
_ASSIGN = ('PowerShell "($var = ...)" is an expression that EMITS the value it assigns; with a '
           "secret present it leaks it. Assign on its own line, then reference $var.")


def reasons_to_block(tool_name: str, command: str) -> "list[str]":
    """The whole decision, as a pure function -- so it is testable without a subprocess.

    Returns the list of reasons to deny. Empty list == allow.
    """
    if tool_name not in GUARDED_TOOLS:
        return []
    if not command:
        return []
    if OVERRIDE.search(command):
        return []

    scrubbed = SAFE_USE.sub("SAFEUSE", command)

    out = []
    if PAT_LITERAL.search(command):
        out.append(_PAT)
    if PUT_SECRET.search(command) and STRING_VALUE.search(command):
        out.append(_PUT)
    if EMIT_SECRET.search(scrubbed):
        out.append(_EMIT)
    if ANY_SECRET.search(scrubbed) and ASSIGN_IN_PARENS.search(scrubbed):
        out.append(_ASSIGN)
    return out


def main() -> int:
    # FAIL OPEN on anything unexpected. A guard bug must never brick tool use -- which also means
    # a broken guard is silent, which is why check_guard_parity.py exists.
    try:
        raw = sys.stdin.read()
        if not raw:
            return 0
        payload = json.loads(raw)
        tool = str(payload.get("tool_name") or "")
        command = str((payload.get("tool_input") or {}).get("command") or "")

        why = reasons_to_block(tool, command)
        if why:
            msg = ("secret-guard blocked this command:\n - " + "\n - ".join(why) +
                   "\nIf this is intentional and safe, append '# secret-guard: allow' to the "
                   "command.")
            sys.stdout.write(json.dumps({
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": msg,
                }
            }) + "\n")
    except Exception:  # noqa: BLE001 -- deliberate, see above
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
