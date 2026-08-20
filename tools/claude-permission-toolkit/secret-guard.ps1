#requires -Version 7
<#
secret-guard.ps1 -- a PreToolUse hook that blocks shell commands which would leak a secret.

WHY A HOOK AND NOT A PERMISSION RULE
    Permission matching splits a compound command on ; | && || and matches every segment
    independently, so no rule can express "this command emits a secret" across a pipe. A hook is
    handed the raw command string before any of that happens. Enforcement that needs to see the
    whole command belongs here; everything else belongs in the deny list. See README.md.

WHAT IT BLOCKS  (four shapes -- guard-probes.json is the executable specification)
    1. a literal vendor PAT inlined into a command
    2. `secrets put-secret --string-value <literal>`, which puts the secret in argv
    3. an emit verb (echo / printf / Write-Host / Write-Output / ...) within 30 characters of a
       secret-NAMED variable
    4. PowerShell's `($var = ...)`, which is an expression that emits the value it assigns

WHAT IT DOES NOT BLOCK -- read this before relying on it
    These are stated here, on the artifact, rather than left to be discovered. Each one is also a
    probe in guard-probes.json, so it is a fact the parity gate re-checks rather than a comment
    that can quietly stop being true.

    a. PIPE-TO-SHELL IS NOT COVERED. `curl … | sh` and `iwr … | iex` pass. This is the sharpest
       gap, because it is precisely the thing a hook could catch and a permission rule cannot.
       This guard is scoped to secret leakage and stops there.
    b. Detection is NAME-based. A secret in `$x` is invisible.
    c. The 30-character proximity window in rule 3 is defeated by padding. Widening it trades the
       hole for false positives, and a noisy guard is a guard people switch off.
    d. It sees Bash and PowerShell commands only -- never a secret written into a file by
       Write/Edit, whose payload is `tool_input.content`, not `tool_input.command`.
    e. It inspects the COMMAND, never the output. A command that prints a secret without naming
       one cannot be caught here by construction.
    f. It FAILS OPEN. Any error at all exits 0 and allows the call. A guard that bricks tool use
       when it has a bug is worse than the leak it prevents, so this is deliberate -- but it does
       mean a broken guard is silent. Run check_guard_parity.py rather than assuming it works.

ESCAPE HATCH
    Include `# secret-guard: allow` anywhere in the command. Deliberately explicit and greppable:
    an override you have to type is a decision, and a guard with no override is one that gets
    removed entirely the first time it is wrong.

A CORRECTION CARRIED IN THIS COPY
    The version this was lifted from told the user, in its own block message, to emit `.Length` or
    `[bool]$env:X` instead of a value -- and then blocked both of them. The `(?!\.(Length|Count))`
    lookahead sat after a greedy `[A-Za-z0-9_]*`, so the engine backtracked the variable name by
    one character and matched anyway. Measured 2026-08-16: `Write-Host $env:DB_PASSWORD.Length`
    was DENIED by the original. A guard whose remediation advice is itself blocked teaches the
    only lesson it can -- reach for the override -- so this copy strips the provably-safe uses
    before testing rather than trying to express them as a lookahead. Probes `length-only` and
    `bool-cast` hold it to that.

EXIT CONTRACT
    Always 0. The deny is carried in the JSON on stdout, not in the exit code:
    `hookSpecificOutput.permissionDecision = "deny"`. Exit 2 would also block, but it reports
    through stderr and loses the structured reason.
#>
$ErrorActionPreference = 'Stop'
try {
    $raw = [Console]::In.ReadToEnd()
    if (-not $raw) { exit 0 }
    $p = $raw | ConvertFrom-Json
    $tool = [string]$p.tool_name
    if ($tool -ne 'Bash' -and $tool -ne 'PowerShell') { exit 0 }
    $c = [string]$p.tool_input.command
    if (-not $c) { exit 0 }

    if ($c -match '(?i)#\s*secret-guard:\s*allow') { exit 0 }   # explicit, intentional override

    # A variable name that DENOTES a secret. Names only -- see gap (b).
    $secretName = '\$(env:)?[A-Za-z0-9_]*(PASSWORD|PASS|PWD|TOKEN|SECRET|APIKEY|API_KEY|CREDENTIAL)[A-Za-z0-9_]*'

    # Strip the uses that cannot leak a value, THEN look for emissions in what is left. Doing it
    # this way instead of with a negative lookahead is the correction described in the header: a
    # lookahead placed after a greedy character class is not a constraint, it is a suggestion the
    # backtracker is free to ignore.
    $safeUses = "(?i)(\[bool\]\s*$secretName)|($secretName\s*\.\s*(Length|Count))"
    $scrubbed = [regex]::Replace($c, $safeUses, 'SAFEUSE')

    $reasons = @()

    if ($c -match 'dapi[0-9a-f]{16,}') {
        $reasons += 'Literal vendor PAT (dapi...) present. Never inline a token -- use OAuth or a secret store.'
    }
    if (($c -match '(?i)secrets\s+put-secret') -and ($c -match '(?i)--string-value(\s+|=)\S')) {
        $reasons += 'put-secret --string-value <literal> puts the secret in argv and in shell history. Omit the flag and paste at the interactive prompt.'
    }
    $emitSecret = "(?i)(Write-Output|Write-Host|Write-Information|Out-Host|Out-Default|\becho\b|\bprintf\b)\b[^\n;|]{0,30}$secretName"
    if ($scrubbed -match $emitSecret) {
        $reasons += 'Command appears to print a secret-bearing variable. Emit only its .Length or a set/unset boolean ([bool]$env:X) -- never the value. Both of those are allowed here.'
    }
    if (([regex]::IsMatch($scrubbed, "(?i)$secretName")) -and ($scrubbed -match '\(\s*\$[A-Za-z_][A-Za-z0-9_]*\s*=')) {
        $reasons += 'PowerShell "($var = ...)" is an expression that EMITS the value it assigns; with a secret present it leaks it. Assign on its own line, then reference $var.'
    }

    if ($reasons.Count -gt 0) {
        $msg = "secret-guard blocked this command:`n - " + ($reasons -join "`n - ") +
               "`nIf this is intentional and safe, append '# secret-guard: allow' to the command."
        $out = @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; permissionDecision = 'deny'; permissionDecisionReason = $msg } } |
               ConvertTo-Json -Compress -Depth 6
        [Console]::Out.WriteLine($out)
    }
    exit 0
} catch { exit 0 }
