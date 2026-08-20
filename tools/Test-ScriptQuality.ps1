#requires -Version 7
<#
.SYNOPSIS
    Static analysis and preamble/encoding conventions for the PowerShell this pack ships.

.DESCRIPTION
    The pack's thesis is that an ungated check is not a check. Every other discipline here is
    enforced by something runnable -- the redaction classes by Test-PracticeClaims.ps1, the pack
    boundary by Test-SharePackClean.ps1, the workflow-parity claim by ci/Invoke-LocalCI.ps1. The
    PowerShell carrying all of it was the one thing nothing measured: PSScriptAnalyzer appeared
    nowhere in the repository, and the per-file convention (an $ErrorActionPreference line, a
    Set-StrictMode line, a ps1-safety note in .NOTES) was asserted by nobody.

    Five checks. Four of them are deterministic and need no module, so a recipient with no gallery
    access still gets a real answer; the fifth adds PSScriptAnalyzer and is required in the CI we
    own. That split is the same one -Gitleaks makes in Test-SharePackClean.ps1, for the same reason.

      Encoding      A .ps1 containing non-ASCII bytes must carry a UTF-8 BOM. Without one, Windows
                    PowerShell 5.1 decodes the FILE as the ANSI code page at parse time -- so a
                    non-ASCII character inside a live regex silently stops matching, and a pattern
                    that matches nothing looks exactly like a clean tree. Eight of the ten scripts
                    were in that state on 2026-08-17.

      VersionGuard  A script using PowerShell 7 syntax must declare #requires -Version 7. Detected
                    by PARSING, not by grepping for '??', because a lazy quantifier in a regex
                    string is not a null-coalescing operator and a gate that cannot tell them apart
                    trains people to ignore it. wt.ps1 is the case that matters: it is dot-sourced
                    from $PROFILE, so under 5.1 the failure is not "the tool is broken" but "your
                    shell does not start".

      Preamble      Every script sets $ErrorActionPreference = 'Stop' at script scope, or is
                    registered exempt with a reason that is about what the file IS.

      Coverage      Every .ps1 under the scope roots is analysed, and every registry entry names a
                    file that is in scope. Both directions. This is the check that would have caught
                    a handoff putting the shipped-script count at six when it was nine: a gate built
                    from a remembered list reports a clean run over the files it happens to know.

      Analyzer      The registry's own shape, always; and with -Analyzer, PSScriptAnalyzer findings
                    compared to the registered set EXACTLY, in both directions. A registered
                    exception that no longer occurs fails as stale and demands striking.

.PARAMETER Root
    Repository root. Defaults to the parent of this script's directory.

.PARAMETER GateDir
    Directory holding script-quality.json. Defaults to practice-gate/ beside this script.

.PARAMETER Skip
    Deliberately do not run a check. Exit 2, never a pass.

.PARAMETER Analyzer
    Also run PSScriptAnalyzer. Requested-and-unresolvable is a FAILURE, never a skip.

.PARAMETER AnalyzerModulePath
    Path to a PSScriptAnalyzer module directory or .psd1, for a runner where it is not installed.

.PARAMETER ReportPath
    Write the report table to this file as well as to the console.

.PARAMETER SelfTest
    Run the negative controls and exit. A gate that has never been red is not evidence.

.NOTES
    EXIT CONTRACT -- identical to Test-PracticeClaims.ps1 and Test-SharePackClean.ps1
      0  every check ran and passed
      1  a check FAILED, or a check ran and found ZERO candidates (INCONCLUSIVE), or the
         environment could not be resolved
      2  a check was deliberately not run (-Skip) and nothing else failed -- SKIPPED, never a pass

    Zero candidates maps to 1, not 0, on purpose: an enumerator that returns nothing produces an
    empty finding set, and "clean" must not share an outcome with "the scope walk broke".

    ps1-safety: $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest; READ-ONLY against the
    repository -- the only write is the optional -ReportPath, and -SelfTest writes only into a temp
    directory it creates and removes. No network, no secrets, no docker, no database surface.
    Idempotent trivially. Tolerates CRLF, since build-and-verify.yml checks out on windows-latest.
#>
[CmdletBinding()]
param(
    [string]$Root,
    [string]$GateDir,
    [ValidateSet('Encoding', 'VersionGuard', 'Preamble', 'Coverage', 'Analyzer')]
    [string[]]$Skip = @(),
    [switch]$Analyzer,
    [string]$AnalyzerModulePath,
    [string]$ReportPath,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ── OUTCOME VOCABULARY ──────────────────────────────────────────────────────────
# PASS / FAIL / INCONCLUSIVE / SKIPPED. A THIRD copy of the vocabulary the other two gates use, and
# a third copy is a fork unless something compares them. What compares them here is ci/verify.yml
# and build-and-verify.yml treating all three exit codes identically, and Invoke-LocalCI.ps1 mapping
# exit 2 to SKIPPED for every gate alike. A divergence in this file surfaces there as a gate that
# reports the wrong colour, not as a quiet pass.

class QualityCheck {
    [string]$Name
    [string]$Status
    [int]$Candidates
    [System.Collections.Generic.List[string]]$Findings
    [string]$Note

    QualityCheck([string]$name) {
        $this.Name = $name
        $this.Status = 'PASS'
        $this.Candidates = 0
        $this.Findings = [System.Collections.Generic.List[string]]::new()
        $this.Note = ''
    }

    [void] Fail([string]$msg) {
        $this.Findings.Add($msg)
        $this.Status = 'FAIL'
    }

    # Call once, after counting. Must not downgrade a recorded FAIL: a check that found a defect has
    # measured something by definition, and INCONCLUSIVE would both hide the finding and misdescribe
    # it as a broken enumerator.
    [void] Seal() {
        if ($this.Candidates -eq 0 -and $this.Status -eq 'PASS') {
            $this.Status = 'INCONCLUSIVE'
            $this.Note = 'examined zero scripts -- the scope walk is broken or the scope is empty'
        }
    }
}

# ── HELPERS ─────────────────────────────────────────────────────────────────────

function Import-Registry {
    param([string]$Path, [string]$Name, [string[]]$RequireKeys)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "registry '$Name' not found at $Path -- a gate whose registry is missing must not pass"
    }
    $json = [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json -AsHashtable
    foreach ($k in $RequireKeys) {
        if (-not $json.ContainsKey($k)) {
            throw "registry '$Name' has no '$k' key -- shape-check failed, refusing to pass by checking nothing"
        }
    }
    return $json
}

function Get-RelPath {
    param([string]$FullName, [string]$Root)
    $rel = $FullName
    if ($FullName.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) {
        $rel = $FullName.Substring($Root.Length).TrimStart('\', '/')
    }
    return $rel.Replace('\', '/')
}

function Get-ScopeFile {
    # The scope is ENUMERATED from roots, never listed. A root that names nothing is an error and
    # not an empty result: "the directory moved" and "there are no scripts" are different facts, and
    # only one of them is compatible with a pass.
    param([string]$Root, [hashtable]$Scope)
    $files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    $missing = [System.Collections.Generic.List[string]]::new()
    foreach ($r in $Scope.roots) {
        $p = Join-Path $Root $r
        if (-not (Test-Path -LiteralPath $p)) { $missing.Add($r); continue }
        $item = Get-Item -LiteralPath $p
        if ($item.PSIsContainer) {
            foreach ($f in Get-ChildItem -LiteralPath $p -Recurse -File -Filter '*.ps1' -ErrorAction SilentlyContinue) {
                if ($f.FullName -notmatch $Scope.exclude_dirs) { $files.Add($f) }
            }
        }
        elseif ($item.Extension -eq '.ps1') { $files.Add($item) }
        else { $missing.Add("$r (not a directory and not a .ps1)") }
    }
    return @{ Files = @($files | Sort-Object FullName); Missing = @($missing) }
}

function Get-FileFacts {
    # One parse per file, shared by three checks. Parsing rather than pattern-matching is the whole
    # difference between VersionGuard and a grep: '??' occurs inside regex strings in this very
    # repository, and a check that cannot tell a lazy quantifier from a null-coalescing operator
    # produces false findings, which is how a gate gets switched off.
    param([System.IO.FileInfo]$File)

    $bytes = [System.IO.File]::ReadAllBytes($File.FullName)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $nonAscii = 0
    foreach ($b in $bytes) { if ($b -gt 127) { $nonAscii++ } }

    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$tokens, [ref]$errors)

    # PowerShell-7-only surface, by token kind and AST node type rather than by text.
    $sevenOnly = [System.Collections.Generic.List[string]]::new()
    foreach ($t in $tokens) {
        switch ($t.Kind) {
            'QuestionQuestion' { $sevenOnly.Add('?? (null-coalescing)') }
            'QuestionQuestionEquals' { $sevenOnly.Add('??= (null-coalescing assignment)') }
            'QuestionDot' { $sevenOnly.Add('?. (null-conditional)') }
            'QuestionLBracket' { $sevenOnly.Add('?[ (null-conditional index)') }
        }
    }
    if ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.TernaryExpressionAst] }, $true).Count -gt 0) {
        $sevenOnly.Add('a ? b : c (ternary)')
    }
    foreach ($v in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)) {
        if ($v.VariablePath.UserPath -in @('IsWindows', 'IsLinux', 'IsMacOS', 'IsCoreCLR')) {
            $sevenOnly.Add("`$$($v.VariablePath.UserPath) (does not exist in 5.1)")
        }
    }

    # #requires is a token kind of its own, so this reads the parsed directive rather than line 1.
    $requiresVersion = $null
    if ($ast.ScriptRequirements -and $ast.ScriptRequirements.RequiredPSVersion) {
        $requiresVersion = $ast.ScriptRequirements.RequiredPSVersion
    }

    # $ErrorActionPreference = 'Stop' at SCRIPT scope -- i.e. an assignment that is not inside a
    # function. Set inside a function it protects that function and nothing else, which is a
    # legitimate choice for a dot-sourced file and not the same claim.
    $eapStop = $false
    foreach ($a in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
        if ($a.Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }
        if ($a.Left.VariablePath.UserPath -ne 'ErrorActionPreference') { continue }
        $inFunction = $false
        $p = $a.Parent
        while ($p) {
            if ($p -is [System.Management.Automation.Language.FunctionDefinitionAst]) { $inFunction = $true; break }
            $p = $p.Parent
        }
        if (-not $inFunction -and "$($a.Right)" -match "(?i)'stop'|""stop""") { $eapStop = $true }
    }

    return @{
        HasBom          = $hasBom
        NonAsciiBytes   = $nonAscii
        SevenOnly       = @($sevenOnly | Sort-Object -Unique)
        RequiresVersion = $requiresVersion
        EapStop         = $eapStop
        ParseErrors     = @($errors)
    }
}

# ── CHECKS ──────────────────────────────────────────────────────────────────────

function Test-QualityEncoding {
    param([System.IO.FileInfo[]]$Files, [string]$Root)
    $r = [QualityCheck]::new('Encoding')
    foreach ($f in $Files) {
        $r.Candidates++
        $facts = Get-FileFacts -File $f
        if ($facts.NonAsciiBytes -gt 0 -and -not $facts.HasBom) {
            $r.Fail("$(Get-RelPath $f.FullName $Root): $($facts.NonAsciiBytes) non-ASCII byte(s) and no UTF-8 BOM -- Windows PowerShell 5.1 will decode this file as the ANSI code page, silently")
        }
    }
    $r.Seal()
    if ($r.Status -eq 'PASS') { $r.Note = 'every non-ASCII script carries a BOM' }
    return $r
}

function Test-QualityVersionGuard {
    param([System.IO.FileInfo[]]$Files, [string]$Root)
    $r = [QualityCheck]::new('VersionGuard')
    $guarded = 0
    foreach ($f in $Files) {
        $r.Candidates++
        $rel = Get-RelPath $f.FullName $Root
        $facts = Get-FileFacts -File $f

        # A file that does not parse cannot have been checked for anything else in it.
        if ($facts.ParseErrors.Count -gt 0) {
            $r.Fail("${rel}: does not parse ($($facts.ParseErrors[0].Message)) -- nothing downstream of the parser has examined this file")
            continue
        }
        if ($facts.SevenOnly.Count -eq 0) { continue }
        if ($facts.RequiresVersion -and $facts.RequiresVersion.Major -ge 7) { $guarded++; continue }
        $r.Fail("${rel}: uses $($facts.SevenOnly -join ', ') and declares no '#requires -Version 7' -- under 5.1 this is a PARSE error, so a dot-sourced file takes the whole shell down with it")
    }
    $r.Seal()
    if ($r.Status -eq 'PASS') { $r.Note = "$guarded script(s) use PowerShell 7 syntax and declare it" }
    return $r
}

function Test-QualityPreamble {
    param([System.IO.FileInfo[]]$Files, [string]$Root, [hashtable]$Registry)
    $r = [QualityCheck]::new('Preamble')
    $exempt = @{}
    foreach ($e in $Registry.preamble_exempt) {
        if (-not $e.ContainsKey('file')) { $r.Fail('a preamble_exempt entry has no file'); continue }
        if (-not $e.ContainsKey('reason') -or [string]::IsNullOrWhiteSpace($e.reason)) {
            $r.Fail("preamble_exempt entry '$($e.file)' has no reason -- an exemption nobody had to justify is a hole, not a decision")
            continue
        }
        $exempt[$e.file] = $e.reason
    }

    $seenExempt = @{}
    foreach ($f in $Files) {
        $r.Candidates++
        $rel = Get-RelPath $f.FullName $Root
        $facts = Get-FileFacts -File $f
        if ($exempt.ContainsKey($rel)) {
            $seenExempt[$rel] = $true
            # An exemption for a file that no longer needs it is stale, and staleness in this
            # direction is the one that accumulates unnoticed.
            if ($facts.EapStop) {
                $r.Fail("${rel}: registered as preamble-exempt, but it now sets `$ErrorActionPreference = 'Stop' at script scope -- strike the entry")
            }
            continue
        }
        if (-not $facts.EapStop) {
            $r.Fail("${rel}: no `$ErrorActionPreference = 'Stop' at script scope, and no registered exemption")
        }
    }
    foreach ($k in $exempt.Keys) {
        if (-not $seenExempt.ContainsKey($k)) {
            $r.Fail("preamble_exempt names '$k', which is not in scope -- the entry is pointing at nothing")
        }
    }
    $r.Seal()
    if ($r.Status -eq 'PASS') { $r.Note = "$($exempt.Count) registered exemption(s), each still true" }
    return $r
}

function Test-QualityCoverage {
    param([System.IO.FileInfo[]]$Files, [string]$Root, [hashtable]$Registry, [string[]]$Missing)
    $r = [QualityCheck]::new('Coverage')

    foreach ($m in $Missing) {
        $r.Fail("scope root '$m' does not exist -- the scope moved and the walk would have reported a clean run over what is left")
    }

    $inScope = @{}
    foreach ($f in $Files) { $r.Candidates++; $inScope[(Get-RelPath $f.FullName $Root)] = $true }

    # The reverse direction: every registry entry must name a file the walk actually found. This is
    # the half that catches a scope narrowing under a registry nobody re-read.
    foreach ($e in $Registry.accepted) {
        if (-not $inScope.ContainsKey($e.file)) {
            $r.Fail("accepted entry names '$($e.file)', which the scope walk did not find -- either the file moved or the scope no longer covers it")
        }
    }
    foreach ($e in $Registry.preamble_exempt) {
        if (-not $inScope.ContainsKey($e.file)) {
            $r.Fail("preamble_exempt names '$($e.file)', which the scope walk did not find")
        }
    }
    $r.Seal()
    if ($r.Status -eq 'PASS') {
        $r.Note = "$($inScope.Count) script(s) enumerated from $($Registry.scope.roots.Count) root(s); every registry entry resolves"
    }
    return $r
}

function Test-QualityAnalyzer {
    # $StubFindings is the New-Stub analogue: a list of @{ File; Rule } that stands in for a
    # PSScriptAnalyzer run, so every classification control below is exercised on a host with no
    # module. Controls that only ever run against the real scanner are controls that do not run.
    param(
        [System.IO.FileInfo[]]$Files,
        [string]$Root,
        [hashtable]$Registry,
        [bool]$UseAnalyzer,
        [string]$ModulePath,
        [object[]]$StubFindings
    )
    $r = [QualityCheck]::new('Analyzer')

    # ---- structural, always: the registry's own shape -------------------------------------
    $excluded = @{}
    foreach ($x in $Registry.rule_exclusions) {
        $r.Candidates++
        if (-not $x.ContainsKey('reason') -or [string]::IsNullOrWhiteSpace($x.reason)) {
            $r.Fail("rule_exclusions entry '$($x.rule)' has no reason -- turning a rule off for the whole codebase is a decision, and a decision has a why")
            continue
        }
        $excluded[$x.rule] = $true
    }

    $registered = @{}
    foreach ($e in $Registry.accepted) {
        $r.Candidates++
        $key = "$($e.file)|$($e.rule)"
        if ($registered.ContainsKey($key)) {
            $r.Fail("accepted has two entries for $key -- two counts for one fact, and only one of them can be checked")
            continue
        }
        if (-not $e.ContainsKey('reason') -or [string]::IsNullOrWhiteSpace($e.reason)) {
            $r.Fail("accepted entry $key has no reason")
            continue
        }
        if ($excluded.ContainsKey($e.rule)) {
            $r.Fail("accepted entry $key names a rule that rule_exclusions already turns off everywhere -- the entry can never fail, so it is not an exception, it is decoration")
            continue
        }
        $registered[$key] = [int]$e.count
    }

    # ---- additive: the scanner ------------------------------------------------------------
    if (-not $UseAnalyzer -and $null -eq $StubFindings) {
        $r.Seal()
        if ($r.Status -eq 'PASS') {
            $r.Note = 'registry shape only; PSScriptAnalyzer NOT run (-Analyzer not passed) -- the four checks above are conventions, not static analysis'
        }
        return $r
    }

    $findings = $null
    if ($null -ne $StubFindings) { $findings = @($StubFindings) }
    else {
        $mod = $null
        if (-not [string]::IsNullOrWhiteSpace($ModulePath)) {
            if (Test-Path -LiteralPath $ModulePath) { $mod = $ModulePath }
        }
        else {
            $available = Get-Module -ListAvailable -Name PSScriptAnalyzer -ErrorAction SilentlyContinue |
                Sort-Object Version -Descending | Select-Object -First 1
            if ($available) { $mod = $available.Path }
        }
        if (-not $mod) {
            # Requested and unavailable is a FAILURE, not a skip. -Analyzer is the caller saying the
            # analysis is required for this run; answering "there is no analyzer" with a pass is the
            # exact state the exit contract forbids. Same rule as -Gitleaks in Test-SharePackClean.
            $r.Fail('-Analyzer was requested and PSScriptAnalyzer could not be resolved -- install it or pass -AnalyzerModulePath; a requested analysis that did not happen is not a pass')
            $r.Note = 'unresolvable'
            return $r
        }
        Import-Module $mod -ErrorAction Stop
        $exclude = @($Registry.rule_exclusions | ForEach-Object { $_.rule })
        $findings = [System.Collections.Generic.List[object]]::new()
        foreach ($f in $Files) {
            foreach ($d in Invoke-ScriptAnalyzer -Path $f.FullName -ExcludeRule $exclude) {
                $findings.Add(@{ File = (Get-RelPath $f.FullName $Root); Rule = $d.RuleName })
            }
        }
        $findings = @($findings)
    }

    $actual = @{}
    foreach ($d in $findings) {
        $key = "$($d.File)|$($d.Rule)"
        if (-not $actual.ContainsKey($key)) { $actual[$key] = 0 }
        $actual[$key]++
    }

    # Both directions, and the count is exact. A >= comparison would let findings accumulate
    # silently up to the registered number.
    foreach ($key in $actual.Keys) {
        if (-not $registered.ContainsKey($key)) {
            $r.Fail("${key}: $($actual[$key]) unregistered finding(s) -- fix it, or register it with a reason")
        }
        elseif ($registered[$key] -ne $actual[$key]) {
            $r.Fail("${key}: registered $($registered[$key]), found $($actual[$key]) -- the exception moved, so the reason attached to it no longer describes what is there")
        }
    }
    foreach ($key in $registered.Keys) {
        if (-not $actual.ContainsKey($key)) {
            $r.Fail("${key}: registered as an accepted exception, and it no longer occurs -- STALE, strike the entry (this is the gate working, not the gate wrong)")
        }
    }

    $r.Seal()
    if ($r.Status -eq 'PASS') {
        $src = if ($null -ne $StubFindings) { 'stub' } else { 'PSScriptAnalyzer' }
        $r.Note = "${src}: $($findings.Count) finding(s), all registered; $($excluded.Count) rule(s) excluded wholesale"
    }
    return $r
}

# ── SELF-TEST ───────────────────────────────────────────────────────────────────

function Assert-Case {
    param([string]$Name, [string]$Expected, [string]$Actual)
    $ok = $Expected -eq $Actual
    $mark = if ($ok) { 'ok  ' } else { 'FAIL' }
    Write-Host ("  [{0}] {1,-56} expected {2}, got {3}" -f $mark, $Name, $Expected, $Actual)
    return $ok
}

function New-ProbeScript {
    param([string]$Path, [string]$Body, [bool]$Bom)
    [System.IO.File]::WriteAllText($Path, $Body, [System.Text.UTF8Encoding]::new($Bom))
    return (Get-Item -LiteralPath $Path)
}

function Invoke-QualitySelfTest {
    param([string]$RegistryPath)
    Write-Host "SELF-TEST -- negative controls" -ForegroundColor Cyan
    $failures = 0
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("script-quality-selftest-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $null = New-Item -ItemType Directory -Path $tmp -Force

    try {
        $emptyReg = @{ scope = @{ roots = @('x'); exclude_dirs = 'nothing' }; rule_exclusions = @(); accepted = @(); preamble_exempt = @() }

        # ---- Encoding -----------------------------------------------------------------
        # The defect this whole check exists for, in both polarities. Only the pair is evidence:
        # a check that fires on everything and a check that fires on nothing look identical from
        # one control.
        $noBom = New-ProbeScript (Join-Path $tmp 'nobom.ps1') "# an em dash: `u{2014}`n" $false
        $res = Test-QualityEncoding -Files @($noBom) -Root $tmp
        if (-not (Assert-Case 'non-ASCII without a BOM fails' 'FAIL' $res.Status)) { $failures++ }

        $withBom = New-ProbeScript (Join-Path $tmp 'withbom.ps1') "# an em dash: `u{2014}`n" $true
        $res = Test-QualityEncoding -Files @($withBom) -Root $tmp
        if (-not (Assert-Case '...and the same bytes with a BOM pass' 'PASS' $res.Status)) { $failures++ }

        $ascii = New-ProbeScript (Join-Path $tmp 'ascii.ps1') "# plain ascii`n" $false
        $res = Test-QualityEncoding -Files @($ascii) -Root $tmp
        if (-not (Assert-Case 'pure ASCII needs no BOM' 'PASS' $res.Status)) { $failures++ }

        $res = Test-QualityEncoding -Files @() -Root $tmp
        if (-not (Assert-Case 'an empty scope is INCONCLUSIVE, never PASS' 'INCONCLUSIVE' $res.Status)) { $failures++ }

        # ---- VersionGuard -------------------------------------------------------------
        $sevenNoGuard = New-ProbeScript (Join-Path $tmp 'seven.ps1') "`$a = `$null`n`$b = `$a ?? 'x'`n" $false
        $res = Test-QualityVersionGuard -Files @($sevenNoGuard) -Root $tmp
        if (-not (Assert-Case 'PowerShell 7 syntax with no #requires fails' 'FAIL' $res.Status)) { $failures++ }

        $sevenGuarded = New-ProbeScript (Join-Path $tmp 'seven-ok.ps1') "#requires -Version 7`n`$a = `$null`n`$b = `$a ?? 'x'`n" $false
        $res = Test-QualityVersionGuard -Files @($sevenGuarded) -Root $tmp
        if (-not (Assert-Case '...and the same file guarded passes' 'PASS' $res.Status)) { $failures++ }

        $ternary = New-ProbeScript (Join-Path $tmp 'ternary.ps1') "`$x = (1 -eq 1) ? 'a' : 'b'`n" $false
        $res = Test-QualityVersionGuard -Files @($ternary) -Root $tmp
        if (-not (Assert-Case 'a ternary is 7-only too, not just ??' 'FAIL' $res.Status)) { $failures++ }

        # THE FALSE POSITIVE THIS CHECK MUST NOT HAVE. '??' inside a regex string is a lazy
        # quantifier, and this repository ships regex strings. A grep-based version of this check
        # fires here, and a check that fires on correct code is a check somebody turns off.
        $regexQ = New-ProbeScript (Join-Path $tmp 'regexq.ps1') "`$p = '\d??x'`n`$s = 'a ? b : c'`n" $false
        $res = Test-QualityVersionGuard -Files @($regexQ) -Root $tmp
        if (-not (Assert-Case '?? inside a STRING is not 7-only syntax' 'PASS' $res.Status)) { $failures++ }

        $broken = New-ProbeScript (Join-Path $tmp 'broken.ps1') "function {`n" $false
        $res = Test-QualityVersionGuard -Files @($broken) -Root $tmp
        if (-not (Assert-Case 'a file that does not parse fails, never passes' 'FAIL' $res.Status)) { $failures++ }

        # ---- Preamble -----------------------------------------------------------------
        $noEap = New-ProbeScript (Join-Path $tmp 'noeap.ps1') "Write-Host 'hi'`n" $false
        $res = Test-QualityPreamble -Files @($noEap) -Root $tmp -Registry $emptyReg
        if (-not (Assert-Case 'no ErrorActionPreference and no exemption fails' 'FAIL' $res.Status)) { $failures++ }

        $withEap = New-ProbeScript (Join-Path $tmp 'eap.ps1') "`$ErrorActionPreference = 'Stop'`n" $false
        $res = Test-QualityPreamble -Files @($withEap) -Root $tmp -Registry $emptyReg
        if (-not (Assert-Case '...and setting it at script scope passes' 'PASS' $res.Status)) { $failures++ }

        # Set inside a function it protects that function only. Accepting it would make the check
        # agree with a file that has not made the claim the check is about.
        $fnEap = New-ProbeScript (Join-Path $tmp 'fneap.ps1') "function f {`n  `$ErrorActionPreference = 'Stop'`n}`n" $false
        $res = Test-QualityPreamble -Files @($fnEap) -Root $tmp -Registry $emptyReg
        if (-not (Assert-Case 'set inside a function does not satisfy script scope' 'FAIL' $res.Status)) { $failures++ }

        $reg = @{ preamble_exempt = @(@{ file = 'noeap.ps1'; reason = 'a data file' }) }
        $res = Test-QualityPreamble -Files @($noEap) -Root $tmp -Registry $reg
        if (-not (Assert-Case 'a registered exemption with a reason passes' 'PASS' $res.Status)) { $failures++ }

        $reg = @{ preamble_exempt = @(@{ file = 'noeap.ps1' }) }
        $res = Test-QualityPreamble -Files @($noEap) -Root $tmp -Registry $reg
        if (-not (Assert-Case 'an exemption with no reason fails' 'FAIL' $res.Status)) { $failures++ }

        $reg = @{ preamble_exempt = @(@{ file = 'eap.ps1'; reason = 'no longer true' }) }
        $res = Test-QualityPreamble -Files @($withEap) -Root $tmp -Registry $reg
        if (-not (Assert-Case 'an exemption for a file that now complies is stale' 'FAIL' $res.Status)) { $failures++ }

        $reg = @{ preamble_exempt = @(@{ file = 'gone.ps1'; reason = 'points at nothing' }) }
        $res = Test-QualityPreamble -Files @($withEap) -Root $tmp -Registry $reg
        if (-not (Assert-Case 'an exemption naming a file not in scope fails' 'FAIL' $res.Status)) { $failures++ }

        # ---- Coverage -----------------------------------------------------------------
        $covReg = @{ scope = @{ roots = @('a') }; accepted = @(); preamble_exempt = @() }
        $res = Test-QualityCoverage -Files @($ascii) -Root $tmp -Registry $covReg -Missing @()
        if (-not (Assert-Case 'a scope that resolves passes' 'PASS' $res.Status)) { $failures++ }

        $res = Test-QualityCoverage -Files @($ascii) -Root $tmp -Registry $covReg -Missing @('tools')
        if (-not (Assert-Case 'a scope root that has moved fails' 'FAIL' $res.Status)) { $failures++ }

        $covReg2 = @{ scope = @{ roots = @('a') }; accepted = @(@{ file = 'not-in-scope.ps1'; rule = 'X' }); preamble_exempt = @() }
        $res = Test-QualityCoverage -Files @($ascii) -Root $tmp -Registry $covReg2 -Missing @()
        if (-not (Assert-Case 'an accepted entry outside the scope walk fails' 'FAIL' $res.Status)) { $failures++ }

        $res = Test-QualityCoverage -Files @() -Root $tmp -Registry $covReg -Missing @()
        if (-not (Assert-Case 'a scope walk that found nothing is INCONCLUSIVE' 'INCONCLUSIVE' $res.Status)) { $failures++ }

        # ---- Analyzer -----------------------------------------------------------------
        # Driven from stub findings, so every one of these runs on a host with no module.
        $aReg = @{
            rule_exclusions = @(@{ rule = 'PSAvoidUsingWriteHost'; reason = 'console tools' })
            accepted        = @(@{ file = 'x.ps1'; rule = 'PSUseApprovedVerbs'; count = 2; reason = 'typed by a human' })
        }
        $stub = @(@{ File = 'x.ps1'; Rule = 'PSUseApprovedVerbs' }, @{ File = 'x.ps1'; Rule = 'PSUseApprovedVerbs' })
        $res = Test-QualityAnalyzer -Files @() -Root $tmp -Registry $aReg -UseAnalyzer $false -ModulePath '' -StubFindings $stub
        if (-not (Assert-Case 'findings matching the registry exactly pass' 'PASS' $res.Status)) { $failures++ }

        $stub = @(@{ File = 'x.ps1'; Rule = 'PSUseApprovedVerbs' })
        $res = Test-QualityAnalyzer -Files @() -Root $tmp -Registry $aReg -UseAnalyzer $false -ModulePath '' -StubFindings $stub
        if (-not (Assert-Case 'a registered count that DROPPED fails as moved' 'FAIL' $res.Status)) { $failures++ }

        $res = Test-QualityAnalyzer -Files @() -Root $tmp -Registry $aReg -UseAnalyzer $false -ModulePath '' -StubFindings @()
        if (-not (Assert-Case 'a registered exception that no longer occurs is STALE' 'FAIL' $res.Status)) { $failures++ }

        $stub = @(@{ File = 'y.ps1'; Rule = 'PSAvoidUsingCmdletAliases' })
        $res = Test-QualityAnalyzer -Files @() -Root $tmp -Registry $aReg -UseAnalyzer $false -ModulePath '' -StubFindings $stub
        if (-not (Assert-Case 'an unregistered finding fails' 'FAIL' $res.Status)) { $failures++ }

        $badReg = @{ rule_exclusions = @(@{ rule = 'PSUseApprovedVerbs'; reason = 'off everywhere' }); accepted = @(@{ file = 'x.ps1'; rule = 'PSUseApprovedVerbs'; count = 1; reason = 'cannot ever fire' }) }
        $res = Test-QualityAnalyzer -Files @() -Root $tmp -Registry $badReg -UseAnalyzer $false -ModulePath '' -StubFindings @()
        if (-not (Assert-Case 'an accepted entry under an excluded rule fails' 'FAIL' $res.Status)) { $failures++ }

        $noReason = @{ rule_exclusions = @(@{ rule = 'PSUseApprovedVerbs' }); accepted = @() }
        $res = Test-QualityAnalyzer -Files @() -Root $tmp -Registry $noReason -UseAnalyzer $false -ModulePath '' -StubFindings @()
        if (-not (Assert-Case 'a rule exclusion with no reason fails' 'FAIL' $res.Status)) { $failures++ }

        $dupe = @{ rule_exclusions = @(); accepted = @(@{ file = 'x.ps1'; rule = 'R'; count = 1; reason = 'a' }, @{ file = 'x.ps1'; rule = 'R'; count = 2; reason = 'b' }) }
        $res = Test-QualityAnalyzer -Files @() -Root $tmp -Registry $dupe -UseAnalyzer $false -ModulePath '' -StubFindings @(@{ File = 'x.ps1'; Rule = 'R' })
        if (-not (Assert-Case 'two accepted entries for one file/rule fail' 'FAIL' $res.Status)) { $failures++ }

        # THE ONE THAT MATTERS MOST: requested and unresolvable is a FAILURE, never a skip.
        $res = Test-QualityAnalyzer -Files @() -Root $tmp -Registry $aReg -UseAnalyzer $true -ModulePath (Join-Path $tmp 'no-such-module.psd1') -StubFindings $null
        if (-not (Assert-Case '-Analyzer with an unresolvable module FAILS' 'FAIL' $res.Status)) { $failures++ }
        if (-not (Assert-Case '...and does not report SKIPPED' 'False' ([string]($res.Status -eq 'SKIPPED')))) { $failures++ }

        # ...and NOT requested is not silently narrower: the report says so on its own face.
        $res = Test-QualityAnalyzer -Files @() -Root $tmp -Registry $aReg -UseAnalyzer $false -ModulePath '' -StubFindings $null
        if (-not (Assert-Case 'without -Analyzer the note states no analysis ran' 'True' ([string]($res.Note -match 'NOT run')))) { $failures++ }

        # ---- the live registry, not a fixture -----------------------------------------
        # A shape check that only ever sees fixtures is checking the fixtures.
        $live = Import-Registry -Path $RegistryPath -Name 'script-quality' -RequireKeys @('scope', 'rule_exclusions', 'accepted', 'preamble_exempt')
        if (-not (Assert-Case 'the live registry loads and shape-checks' 'True' ([string]($null -ne $live)))) { $failures++ }
        $threw = $false
        try { $null = Import-Registry -Path $RegistryPath -Name 'script-quality' -RequireKeys @('no_such_key') } catch { $threw = $true }
        if (-not (Assert-Case 'a registry missing a required key refuses to load' 'True' ([string]$threw))) { $failures++ }
    }
    finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host ""
    if ($failures -eq 0) {
        Write-Host "SELF-TEST PASSED -- every control behaved as specified" -ForegroundColor Green
        return 0
    }
    Write-Host "SELF-TEST FAILED -- $failures control(s) did not" -ForegroundColor Red
    return 1
}

# ── ENVIRONMENT ─────────────────────────────────────────────────────────────────
# Resolved BEFORE anything else and failing to 1, never 0. A gate that cannot locate its subject
# must not report PASS.

if (-not $Root) { $Root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path }
if (-not (Test-Path -LiteralPath $Root)) {
    Write-Host "ENVIRONMENT: -Root '$Root' does not exist. A gate that cannot locate its subject must not report PASS." -ForegroundColor Red
    exit 1
}
$Root = (Resolve-Path -LiteralPath $Root).Path

if (-not $GateDir) { $GateDir = Join-Path $PSScriptRoot 'practice-gate' }
$registryPath = Join-Path $GateDir 'script-quality.json'
if (-not (Test-Path -LiteralPath $registryPath)) {
    Write-Host "ENVIRONMENT: no script-quality.json under '$GateDir'. A gate that cannot locate its registry must not report PASS." -ForegroundColor Red
    exit 1
}

if ($SelfTest) { exit (Invoke-QualitySelfTest -RegistryPath $registryPath) }

$registry = Import-Registry -Path $registryPath -Name 'script-quality' -RequireKeys @('scope', 'rule_exclusions', 'accepted', 'preamble_exempt')
$scope = Get-ScopeFile -Root $Root -Scope $registry.scope
$files = $scope.Files

# ── DISPATCH ────────────────────────────────────────────────────────────────────
# The list and the [ValidateSet] on -Skip say the same thing in two places. They are compared by
# the same mechanism that compares the other gates' pair: a check dispatched here and absent from
# the report is coverage going missing without failing.

$results = [System.Collections.Generic.List[object]]::new()
foreach ($name in @('Encoding', 'VersionGuard', 'Preamble', 'Coverage', 'Analyzer')) {
    if ($Skip -contains $name) {
        $r = [QualityCheck]::new($name)
        $r.Status = 'SKIPPED'
        $r.Note = 'deliberately not run (-Skip) -- this is not a pass'
        $results.Add($r); continue
    }
    switch ($name) {
        'Encoding' { $results.Add((Test-QualityEncoding -Files $files -Root $Root)) }
        'VersionGuard' { $results.Add((Test-QualityVersionGuard -Files $files -Root $Root)) }
        'Preamble' { $results.Add((Test-QualityPreamble -Files $files -Root $Root -Registry $registry)) }
        'Coverage' { $results.Add((Test-QualityCoverage -Files $files -Root $Root -Registry $registry -Missing $scope.Missing)) }
        'Analyzer' { $results.Add((Test-QualityAnalyzer -Files $files -Root $Root -Registry $registry -UseAnalyzer ([bool]$Analyzer) -ModulePath $AnalyzerModulePath -StubFindings $null)) }
    }
}

# ── REPORT ──────────────────────────────────────────────────────────────────────

$out = [System.Text.StringBuilder]::new()
function Emit { param([string]$Text, [string]$Colour = 'Gray'); Write-Host $Text -ForegroundColor $Colour; $null = $out.AppendLine($Text) }

Emit ""
Emit "SCRIPT QUALITY GATE -- $Root"
Emit "scope: $($registry.scope.roots -join ', ')   ($($files.Count) script(s))"
Emit ("=" * 78)

foreach ($r in $results) {
    $colour = switch ($r.Status) {
        'PASS' { 'Green' } 'FAIL' { 'Red' } 'INCONCLUSIVE' { 'Red' } 'SKIPPED' { 'Yellow' } default { 'Gray' }
    }
    Emit ("{0,-14} {1,-13} {2,5} candidate(s){3}" -f $r.Name, $r.Status, $r.Candidates, $(if ($r.Note) { "  -- $($r.Note)" } else { '' })) $colour
    # ASCII only: this runs on windows-latest, where a non-ASCII bullet came back as a replacement
    # character and made the log unreadable. The output boundary is part of the tool.
    foreach ($f in $r.Findings) { Emit "                 - $f" $colour }
}

$failed = @($results | Where-Object { $_.Status -in @('FAIL', 'INCONCLUSIVE') })
$skipped = @($results | Where-Object { $_.Status -eq 'SKIPPED' })

Emit ("=" * 78)
if ($failed.Count -gt 0) {
    Emit "RESULT: FAIL -- $($failed.Count) check(s) failed or measured nothing" 'Red'
    $exit = 1
}
elseif ($skipped.Count -gt 0) {
    Emit "RESULT: SKIPPED -- $($skipped.Count) check(s) deliberately not run; the rest passed." 'Yellow'
    Emit "        This is not a pass. Re-run without -Skip before trusting it." 'Yellow'
    $exit = 2
}
else {
    Emit "RESULT: PASS -- every check ran and passed" 'Green'
    $exit = 0
}
Emit ""

if ($ReportPath) {
    # WriteAllText, not Set-Content: Set-Content supports ShouldProcess and silently skips the write
    # under -WhatIf, which would leave a report nobody notices is missing.
    [System.IO.File]::WriteAllText($ReportPath, $out.ToString())
    Write-Host "report written to $ReportPath"
}

exit $exit
