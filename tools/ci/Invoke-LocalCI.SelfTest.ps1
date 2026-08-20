#Requires -Version 7
<#
.SYNOPSIS
    Negative controls for Invoke-LocalCI.ps1. Proves the runner can fail.

.DESCRIPTION
    The runner this one is extracted from had no self-test. That is not a small omission: its
    central claim is a claim about COMPLETENESS -- "every gate the workflow declares ran here" --
    and that claim went false once already, on 2026-08-08, while the summary kept printing it.
    A completeness check nobody has ever seen fail is a completeness check nobody has tested.

    So the controls below are aimed at the runner's own failure modes rather than at the gates it
    runs. Each builds a throwaway workflow in a temp directory and asserts what the runner does
    with it, by exit code and by output.

.EXAMPLE
    pwsh -NoProfile -File ci/Invoke-LocalCI.SelfTest.ps1

.NOTES
    EXIT CONTRACT
      0  every control behaved as specified
      1  a control did not

    ps1-safety: $ErrorActionPreference='Stop'. Writes only inside a temp directory it creates and
    removes. Never invokes the real ci/verify.yml -- a self-test that ran the live gates would take
    minutes and would report THEIR health, not the runner's.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$runner = Join-Path $PSScriptRoot 'Invoke-LocalCI.ps1'
if (-not (Test-Path -LiteralPath $runner)) { throw "cannot find the runner at $runner" }

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("localci-selftest-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Path $tmp -Force
$failures = 0

function Assert-Case {
    param([string]$Name, [string]$Expected, [string]$Actual)
    $ok = $Expected -eq $Actual
    $mark = if ($ok) { 'ok  ' } else { 'FAIL' }
    Write-Host ("  [{0}] {1,-54} expected {2}, got {3}" -f $mark, $Name, $Expected, $Actual)
    return $ok
}

# Each fixture lives in <tmp>/<case>/ci/verify.yml, so the runner's default RepoRoot -- the parent
# of the workflow's directory -- lands on <tmp>/<case>. That mirrors the shipped layout exactly
# rather than special-casing the test, which is the difference between a control and a rehearsal.
function New-Fixture {
    param([string]$Case, [string]$Steps)
    $dir = Join-Path $tmp "$Case/ci"
    $null = New-Item -ItemType Directory -Path $dir -Force
    $path = Join-Path $dir 'verify.yml'
    # The join is a newline on purpose. A here-string does not carry a trailing one, so
    # "$header + $steps" glues `steps:` onto the first `- name:` and every fixture silently
    # becomes a workflow with no parseable step -- which several controls would then have passed
    # for entirely the wrong reason. Caught by control 3, which expects a 0 and got the throw.
    [System.IO.File]::WriteAllText($path, ($script:header + "`n" + $Steps + "`n"))
    return $path
}

function Invoke-Runner {
    param([string]$WorkflowPath)
    $out = & pwsh -NoProfile -File $runner -Workflow $WorkflowPath 2>&1
    return [pscustomobject]@{ Code = $LASTEXITCODE; Text = ($out | Out-String) }
}

$header = @'
name: Fixture
on: [workflow_dispatch]
jobs:
  verify:
    runs-on: windows-latest
    steps:
'@

Write-Host "SELF-TEST -- negative controls for the local CI runner"

try {
    # 1. THE 2026-08-08 CLASS. A step shape the runner cannot execute must hard-fail, not vanish
    #    from the run while the summary still claims parity. This is the whole reason the
    #    completeness check exists, so it is the first thing controlled.
    $f = New-Fixture 'unknown-shape' @'
      - name: Something it can run
        shell: pwsh
        run: exit 0
      - name: Something it cannot
        shell: bash
        run: for f in *; do echo $f; done
'@
    $r = Invoke-Runner $f
    if (-not (Assert-Case 'an unexecutable step shape hard-fails' '1' "$($r.Code)")) { $failures++ }
    if (-not (Assert-Case '...and names the step rather than dropping it' 'True' ($r.Text -match 'cannot execute').ToString())) { $failures++ }
    if (-not (Assert-Case '...and never prints a pass' 'False' ($r.Text -match 'LOCAL CI PASSED').ToString())) { $failures++ }

    # 2. A block scalar is a multi-line shell body this runner will not guess at. It must reach the
    #    completeness check as unaccounted, not be quietly half-executed.
    $f = New-Fixture 'block-scalar' @'
      - name: Runnable
        shell: pwsh
        run: exit 0
      - name: Multi-line body
        shell: pwsh
        run: |
          Write-Host one
          Write-Host two
'@
    $r = Invoke-Runner $f
    if (-not (Assert-Case 'a run: | block scalar hard-fails' '1' "$($r.Code)")) { $failures++ }
    if (-not (Assert-Case '...and says which shape it was' 'True' ($r.Text -match 'BLOCK SCALAR').ToString())) { $failures++ }

    # 3. Routing is by the DECLARED shell. A pwsh step must go through the Actions-faithful pwsh
    #    path, not `cmd /c`, which cannot run PowerShell at all.
    $f = New-Fixture 'pwsh-routing' @'
      - name: PowerShell only
        shell: pwsh
        run: if ($PSVersionTable.PSVersion.Major -ge 7) { exit 0 } else { exit 3 }
'@
    $r = Invoke-Runner $f
    if (-not (Assert-Case 'a shell: pwsh step is run by pwsh, not cmd' '0' "$($r.Code)")) { $failures++ }

    # 4. Exit codes are REPORTED, not collapsed. `pwsh -Command` would turn a 7 into a 1: still
    #    non-zero, so it fails closed -- but by luck, and the number a reader sees would not be the
    #    gate's. "Fails closed by luck is not a property to build a parity claim on."
    $f = New-Fixture 'exit-code' @'
      - name: Exits seven
        shell: pwsh
        run: exit 7
'@
    $r = Invoke-Runner $f
    if (-not (Assert-Case 'a failing gate fails the run' '1' "$($r.Code)")) { $failures++ }
    if (-not (Assert-Case '...reporting ITS exit code, not a collapsed 1' 'True' ($r.Text -match 'exit 7').ToString())) { $failures++ }

    # 5. INCONCLUSIVE is not SKIPPED. Nobody chose to run nothing: a workflow the parser finds no
    #    runnable step in means the workflow is empty or the runner has stopped recognising it.
    #    Either way nothing was measured, and that is exit 1 -- never 0, and not 2 either.
    $f = New-Fixture 'no-steps' @'
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
'@
    $r = Invoke-Runner $f
    if (-not (Assert-Case 'a workflow with no runnable step is INCONCLUSIVE' '1' "$($r.Code)")) { $failures++ }
    if (-not (Assert-Case '...typed as INCONCLUSIVE, not FAIL or SKIPPED' 'True' ($r.Text -match 'INCONCLUSIVE').ToString())) { $failures++ }

    # 6. Exit 2 is the shipped skip convention. It must surface as SKIPPED and exit 2 -- partial
    #    cover, never folded into a green 0.
    $f = New-Fixture 'skipped' @'
      - name: Could not run
        shell: pwsh
        run: exit 2
'@
    $r = Invoke-Runner $f
    if (-not (Assert-Case 'a gate exiting 2 is SKIPPED, and the run exits 2' '2' "$($r.Code)")) { $failures++ }
    if (-not (Assert-Case '...and the summary refuses to call it green' 'True' ($r.Text -match 'not a green build').ToString())) { $failures++ }

    # 7. A FAIL alongside a SKIP is still a FAIL. The skip must not mask it, and 2 must not win
    #    over 1 just because it is the larger number.
    $f = New-Fixture 'fail-beats-skip' @'
      - name: Skipped one
        shell: pwsh
        run: exit 2
      - name: Failed one
        shell: pwsh
        run: exit 1
'@
    $r = Invoke-Runner $f
    if (-not (Assert-Case 'a FAIL outranks a SKIP in the verdict' '1' "$($r.Code)")) { $failures++ }

    # 8. The ignore list accounts for a step rather than executing it -- and the run still passes,
    #    which is the only reason the list is allowed to exist.
    $f = New-Fixture 'ignorable' @'
      - name: Dependency install
        shell: pwsh
        run: python -m pip install PyYAML --quiet
      - name: Real gate
        shell: pwsh
        run: exit 0
'@
    $r = Invoke-Runner $f
    if (-not (Assert-Case 'an ignore-list entry does not break completeness' '0' "$($r.Code)")) { $failures++ }

    # 9. STEP BOUNDARY. `shell:` on one step must not govern the next. Get this wrong and a step
    #    the workflow runs under one shell is silently run locally under another.
    $f = New-Fixture 'shell-leak' @'
      - name: Declares pwsh
        shell: pwsh
        run: exit 0
      - name: Declares nothing, and is not python
        run: some-command-that-does-not-exist --flag
'@
    $r = Invoke-Runner $f
    if (-not (Assert-Case 'shell: does not leak onto the following step' '1' "$($r.Code)")) { $failures++ }
    if (-not (Assert-Case '...the unshelled step is unaccounted, not run as pwsh' 'True' ($r.Text -match 'cannot execute').ToString())) { $failures++ }

    # 10. The folded form IS supported, and its continuation lines are joined rather than each
    #     being treated as an unaccounted step -- otherwise the check fires on a shape the runner
    #     handles, which is the noisiest possible way to be wrong.
    $f = New-Fixture 'folded' @'
      - name: Long command
        shell: pwsh
        run: >-
          if ($true)
          { exit 0 }
'@
    $r = Invoke-Runner $f
    if (-not (Assert-Case 'a folded >- scalar is joined and executed' '0' "$($r.Code)")) { $failures++ }

    # 11. No workflow at all is a refusal, not an empty pass. A runner that mirrors nothing cannot
    #     claim parity with anything.
    $out = & pwsh -NoProfile -File $runner -Workflow (Join-Path $tmp 'nope/verify.yml') 2>&1
    $code = $LASTEXITCODE
    if (-not (Assert-Case 'an absent workflow refuses rather than passing' '1' "$code")) { $failures++ }
    if (-not (Assert-Case '...and never prints a pass' 'False' (($out | Out-String) -match 'LOCAL CI PASSED').ToString())) { $failures++ }

    # 12. The shipped workflow must remain parseable BY THIS RUNNER. Parsing only -- the live gates
    #     take minutes and their health is not what this file is about. If verify.yml ever grows a
    #     shape the runner cannot execute, this control goes red before anyone waits for the run.
    $shipped = Join-Path $PSScriptRoot 'verify.yml'
    if (Test-Path -LiteralPath $shipped) {
        # EVERY `run:` line, folded markers included. A `run: >-` IS a step -- filtering it out
        # here would make the two sides count different things and the control would pass by
        # comparing 16 apples with 16 oranges.
        $declared = @(Select-String -Path $shipped -Pattern '^\s*run:\s*\S' | ForEach-Object { $_.Line })
        $seen = @()
        $src = Get-Content -Raw $runner
        $src = $src -replace '(?s)^.*?function Get-WorkflowSteps', 'function Get-WorkflowSteps'
        $src = $src -replace '(?s)\r?\nfunction Invoke-PwshStep.*$', ''
        . ([scriptblock]::Create($src))
        $seen = @(Get-WorkflowSteps $shipped | Where-Object Run | ForEach-Object { $_.Run })
        if (-not (Assert-Case 'every run: in the shipped verify.yml is parsed' "$($declared.Count)" "$($seen.Count)")) { $failures++ }
        $blocks = @(Get-WorkflowSteps $shipped | Where-Object Block).Count
        if (-not (Assert-Case 'the shipped verify.yml uses no block scalars' '0' "$blocks")) { $failures++ }
    }
    else {
        Write-Host "  [FAIL] the shipped verify.yml is missing -- nothing to check parseability against"
        $failures++
    }
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
if ($failures -gt 0) {
    Write-Host "SELF-TEST FAILED -- $failures control(s) did not behave as specified" -ForegroundColor Red
    exit 1
}
Write-Host "SELF-TEST PASSED -- every control behaved as specified" -ForegroundColor Green
exit 0
