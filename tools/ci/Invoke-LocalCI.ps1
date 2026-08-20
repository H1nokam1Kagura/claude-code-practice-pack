#Requires -Version 7
<#
.SYNOPSIS
    Run the gates ci/verify.yml declares, on this machine, by PARSING that workflow.

.DESCRIPTION
    A local runner that keeps its own copy of the command list is a second source of truth, and it
    drifts the moment somebody edits one and not the other -- silently, in the direction that
    matters, because the local run is the one you trust when you are in a hurry.

    So this script reads the commands out of the workflow. Add a step to CI and the local run picks
    it up with no edit here. Change the workflow's shape into something this runner cannot execute
    and it FAILS rather than quietly checking less.

    THE COMPLETENESS CHECK IS THE POINT. This does not merely extract the steps it recognises: it
    accounts for every `run:` line in the job and hard-fails on any shape it cannot execute. See the
    2026-08-08 fail-open recorded at that check, which is why it exists.

.PARAMETER Workflow
    The workflow to parse and mirror. Default: verify.yml beside this script.

.PARAMETER RepoRoot
    Directory the steps are run from. The steps in verify.yml are written root-relative, so this is
    not cosmetic -- get it wrong and every gate reports "cannot find the file".

    Default: the nearest ancestor of the workflow holding a `.git` entry, and failing that the
    parent of the workflow's directory. Two shapes, both real. In a repository this directory sits
    at tools/ci/, one level deeper than the pack layout, so a fixed number of levels up is wrong
    for one of them; in an unpacked distribution there is no git at all, so the walk must have a
    stated fallback rather than a guess. Which one was used is printed, because a runner that
    silently chose the wrong root would report every gate red for the same uninformative reason.

.EXAMPLE
    pwsh -NoProfile -File ci/Invoke-LocalCI.ps1

.NOTES
    EXIT CONTRACT
      0  every gate ran and passed
      1  a gate FAILED, or a gate ran and measured nothing (INCONCLUSIVE), or this runner could not
         claim parity with the workflow and refused to report anything
      2  everything that ran passed, but at least one gate was SKIPPED -- partial cover, not green

    FOUR STATES, and INCONCLUSIVE is the one that is easy to lose. PASS / FAIL / INCONCLUSIVE /
    SKIPPED. "I chose not to run this" (2) and "it ran and measured nothing" (1) are different
    states and do not share an exit code -- a check whose extractor has broken produces an empty
    result set, and empty must never share an outcome with clean.

    The runner this was extracted from had INCONCLUSIVE in the code and documented only SKIPPED in
    its rule file, so a reader of the documentation could not have known the state existed. All
    four are documented here on purpose.

    ps1-safety: $ErrorActionPreference='Stop'. READ-ONLY against the repository -- it writes only
    a per-step temp script under $env:TEMP, which it removes. No network, no secrets, no docker.
    Whether the STEPS it runs are read-only is the steps' business; every gate in the shipped
    verify.yml is.
#>
[CmdletBinding()]
param(
    [string]$Workflow,
    [string]$RepoRoot
)

# THE ACTUAL GUARANTEE, and the reason the interpreter check further down is labelled decorative:
# an unresolvable `& pwsh` is a TERMINATING error here, so this script aborts before the verdict
# block and no pass is ever printed.
$ErrorActionPreference = 'Stop'

function Write-Head { param([string]$T) Write-Host "`n=== $T" -ForegroundColor Cyan }
function Write-Ok { param([string]$T) Write-Host "  OK    $T" -ForegroundColor Green }
function Write-Bad { param([string]$T) Write-Host "  FAIL  $T" -ForegroundColor Red }
function Write-Note { param([string]$T) Write-Host "  ..    $T" -ForegroundColor DarkGray }

function Get-WorkflowSteps([string]$path) {
    # Enough YAML to answer one question per step: which shell, running which command. A real parser
    # is not needed (and adding a PowerShell YAML dependency to a script whose whole point is running
    # offline would be a poor trade), but the STEP boundary matters: `shell:` and `run:` have to be
    # attributed to the same list item, or a `shell: pwsh` on one step silently governs the next.
    # Block scalars (`run: |`) are recorded and flagged rather than guessed at -- a multi-line shell
    # body is not something this runner can faithfully reproduce, so it must reach the completeness
    # check below as an unaccounted step and fail, not be quietly half-executed.
    #
    # The folded form (`run: >-`) IS supported, because verify.yml uses it for the two commands too
    # long for one line: the continuation lines are joined with single spaces, which is what YAML
    # does with them, and the result is still one command this runner can execute.
    $steps = [System.Collections.Generic.List[object]]::new()
    $cur = $null
    $folding = $false
    $foldIndent = 0
    $flush = { if ($cur -and $cur.Run) { $steps.Add([pscustomobject]$cur) } }
    foreach ($line in [System.IO.File]::ReadAllLines($path)) {
        if ($folding) {
            if ($line.Trim() -eq '') { continue }
            $indent = $line.Length - $line.TrimStart().Length
            if ($indent -ge $foldIndent) { $cur.Run = ($cur.Run + ' ' + $line.Trim()).Trim(); continue }
            $folding = $false
        }
        if ($line -match '^\s*#') { continue }
        if ($line -match '^\s*-\s') { & $flush; $cur = [ordered]@{ Name = $null; Shell = $null; Run = $null; Block = $false; Exec = $null } }
        if ($null -eq $cur) { continue }
        if ($line -match '^\s*(?:-\s+)?name:\s*(.+?)\s*$' -and -not $cur.Name) { $cur.Name = $matches[1] }
        if ($line -match '^\s*(?:-\s+)?shell:\s*(\S+)\s*$' -and -not $cur.Run) { $cur.Shell = $matches[1] }
        if ($line -match '^\s*(?:-\s+)?run:\s*(.*?)\s*$' -and -not $cur.Run) {
            $val = $matches[1]
            if ($val -match '^>[-+]?$') {
                # folded scalar: collect the more-indented block that follows
                $folding = $true
                $foldIndent = ($line.Length - $line.TrimStart().Length) + 1
                $cur.Run = ''
                continue
            }
            $cur.Run = $val
            if ($cur.Run -match '^\|') { $cur.Block = $true }
        }
    }
    & $flush
    return $steps
}

function Invoke-PwshStep([string]$command) {
    # GitHub Actions' `shell: pwsh` does NOT run `pwsh -File <your line>`. It writes the run block to
    # a script file and executes it with `$ErrorActionPreference='stop'` prepended and an explicit
    # `exit $LASTEXITCODE` epilogue appended. Reproduce that, because the two obvious shortcuts are
    # both wrong and both were measured wrong on 2026-08-08:
    #   * `pwsh -File "<line with args>"` treats the WHOLE line as a filename -> exit 64,
    #     "is not recognized as the name of a script file". This is why the original runner could not
    #     execute a .ps1 gate that takes an argument at all, and it would have mis-reported the FIRST
    #     such gate as a failing gate rather than an unrunnable one.
    #   * `pwsh -Command "<line>"` COLLAPSES the exit code: a script exiting 7 comes back as 1.
    #     Non-zero, so it happens to fail closed -- but the number reported would not be the gate's,
    #     and "fails closed by luck" is not a property to build a parity claim on.
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("localci-step-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".ps1")
    # WriteAllText, not Set-Content: Set-Content supports ShouldProcess, so under $WhatIfPreference
    # it silently writes nothing and returns success. The step script would then not exist, `pwsh
    # -File` would exit 64, and this runner would report a FAILING GATE for a file it never wrote --
    # a wrong answer that looks exactly like a real regression. Same reason the two gates under
    # tools/ use WriteAllText for their fixtures.
    [System.IO.File]::WriteAllText($tmp, (@(
        '$ErrorActionPreference = ''stop''',
        $command,
        'if ((Test-Path -LiteralPath variable:/LASTEXITCODE)) { exit $LASTEXITCODE }'
    ) -join "`n") + "`n", [System.Text.UTF8Encoding]::new($false))
    try {
        $out = & pwsh -NoProfile -File $tmp 2>&1
        $code = $LASTEXITCODE
    }
    finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    return [pscustomobject]@{ Output = $out; Code = $code }
}

function Get-StepScriptPath([object]$step) {
    # The file a step actually runs, for the two shapes this runner executes. Null for anything
    # else -- an arbitrary command has no single path and must not be guessed at.
    $t = @($step.Run -split '\s+' | Where-Object { $_ })
    if ($t.Count -eq 0) { return $null }
    $p = if ($t[0] -match '^(python|python3|py)$') { if ($t.Count -gt 1) { $t[1] } else { $null } }
    elseif ($t[0] -match '\.ps1$') { $t[0] }
    else { $null }
    if (-not $p -or $p.StartsWith('-')) { return $null }
    return ($p -replace '^\./', '')
}

# ---------------------------------------------------------------- resolve
if (-not $Workflow) { $Workflow = Join-Path $PSScriptRoot 'verify.yml' }
if (-not (Test-Path -LiteralPath $Workflow)) {
    throw "no workflow at $Workflow. This runner mirrors a workflow; without one there is nothing to claim parity with."
}
$Workflow = (Resolve-Path -LiteralPath $Workflow).Path

$results = [System.Collections.Generic.List[object]]::new()
function Add-Result([string]$Gate, [string]$Status, [string]$Detail) {
    $results.Add([pscustomobject]@{ Gate = $Gate; Status = $Status; Detail = $Detail })
}

Write-Head "Local CI -- $(Split-Path -Leaf $Workflow)"

# ---------------------------------------------------------------- parse and route
# Pull every runnable step, in workflow order, WITH the shell the workflow DECLARES for it.
# TWO shapes are executed here:
#   `shell: pwsh` + any single-line command  -- everything in the shipped verify.yml
#   default shell + `python <script>.py [args]`  -- the shape a recipient's own workflow may use
#
# Routing is by the declared `shell:`, NOT by sniffing the command text for ".ps1". Until
# 2026-08-08 it was the latter, which is wrong in both directions: a bash step that merely
# MENTIONS a .ps1 (`shellcheck foo.ps1`) would have been re-routed through pwsh locally -- running
# something the cloud never runs -- while a `shell: pwsh` step that is not a bare script path
# (`Import-Module x; Test-Y`) was not recognised at all.
$steps = Get-WorkflowSteps $Workflow
$pyPattern = '^python\s+\S+\.py(\s|$)'
foreach ($s in $steps) {
    $s.Exec = if ($s.Block) { $null }    # block scalar -- see Get-WorkflowSteps
    elseif ($s.Shell -in @('pwsh', 'powershell')) { 'pwsh' }
    elseif (-not $s.Shell -and $s.Run -match $pyPattern) { 'python' }
    else { $null }
}
$runCmds = @($steps | Where-Object Exec | ForEach-Object { $_.Run })

# COMPLETENESS, not just extraction. Until 2026-08-08 the original parser matched ONLY
# `python *.py`, so adding a step in any other shell silently vanished from the local mirror while
# the verdict still read "every gate GitHub Actions would have run passed here" -- a false parity
# claim, and exactly the fail-open shape the gates themselves exist to catch. (It happened
# immediately: the pwsh parse gate was skipped without a word. Eight reported, nine in the
# workflow, no warning.) So count EVERY `run:` in the job and account for all of them. A step this
# runner does not know how to execute is a hard failure, not a silent omission.
#
# Note what the fix was: not "add pwsh support" but "add a completeness check so the class cannot
# recur."
$allRun = @(Select-String -Path $Workflow -Pattern '^\s*run:\s*(\S.*)$' |
    ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() } |
    Where-Object { $_ -notmatch '^>[-+]?$' })
# Steps deliberately NOT mirrored locally, with the reason. Keep this list tiny and specific --
# it is an allow-list of known-irrelevant setup, never a dumping ground for "didn't work locally".
$ignorablePatterns = @(
    '^python -m pip install'   # runner dependency install; the local box already has these
)
$unaccounted = @($allRun | Where-Object {
        $c = $_
        # A folded step's recorded command is the JOINED line, so compare on the first physical
        # line too -- otherwise every `>-` step looks unaccounted and the check fires on its own
        # supported shape, which is the noisiest possible way to be wrong.
        (-not ($runCmds | Where-Object { $_ -eq $c -or $_.StartsWith($c) })) -and
        -not ($ignorablePatterns | Where-Object { $c -match $_ })
    })
if ($unaccounted.Count -gt 0) {
    Write-Bad "$($unaccounted.Count) workflow step(s) this runner cannot execute -- local CI is NOT a mirror:"
    $unaccounted | ForEach-Object { Write-Host "        run: $_" }
    if (@($steps | Where-Object Block).Count -gt 0) {
        Write-Host "        (at least one is a BLOCK SCALAR 'run: |' -- a multi-line shell body this runner will not guess at)" -ForegroundColor DarkGray
    }
    throw "Invoke-LocalCI does not know how to run the step(s) above, so it cannot claim parity with the workflow. Teach it that shape (see Get-WorkflowSteps and the `$s.Exec routing block) or add a justified entry to `$ignorablePatterns. Do NOT widen `$ignorablePatterns to make a failure go away -- that is how the 2026-08-08 fail-open comes back. Refusing to report a pass."
}

# FAIL CLOSED if the shell a step declares is not actually here: a missing interpreter must be a
# hard failure, never a skipped gate that still lets the verdict read "every gate GitHub Actions
# would have run passed here".
# BE HONEST ABOUT WHICH LAYER IS LOAD-BEARING -- this one is belt-and-braces, not the guarantee.
# pwsh.exe PREPENDS $PSHOME to $env:PATH inside its own process at startup (measured 2026-08-08:
# scrub every pwsh-bearing entry from the parent's PATH and the child still resolves `pwsh`), so
# under `#Requires -Version 7` this check is very nearly unfalsifiable and must not be mistaken for
# the protection. The actual guarantee is $ErrorActionPreference='Stop' at the top of this script:
# if `& pwsh` cannot be resolved, the CommandNotFoundException is TERMINATING (verified: category
# ObjectNotFound), so the script aborts before the verdict block and no pass is ever printed. The
# check below exists only to make that failure legible instead of a stack trace.
$pwshSteps = @($steps | Where-Object { $_.Exec -eq 'pwsh' })
if ($pwshSteps.Count -gt 0 -and -not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
    throw "$(Split-Path -Leaf $Workflow) declares $($pwshSteps.Count) 'shell: pwsh' step(s) but pwsh is not on PATH. Refusing to report a pass on gates that were never run."
}

# ---------------------------------------------------------------- resolve the root, by evidence
#
# CHOSEN AND VERIFIED, never assumed. The steps are written relative to a root this file does not
# name, and the two layouts this ships in disagree about where that is by one level: in the share
# pack the workflow sits at `ci/verify.yml` and the root is its grandparent; in a repository it
# sits at `tools/ci/verify.yml` and the grandparent is `tools/`, one level short.
#
# An earlier version picked the grandparent and printed which rule it had used, which sounds
# careful and is not: it was WRONG for the layout it actually ships in, and a `.git` walk masked
# that in-repo. Measured on a simulated distribution 2026-08-16 -- every path resolved under
# `tools/tools/`, thirteen gates reported SKIPPED, and the summary read like a recipient had
# deliberately declined to run them.
#
# So: propose candidates, then test each one against the paths the steps actually name, and take
# the best. A root under which nothing resolves is not a root, and this refuses rather than
# reporting eighteen skips.
$wantPaths = @($steps | Where-Object Exec | ForEach-Object { Get-StepScriptPath $_ } | Where-Object { $_ } | Sort-Object -Unique)
if (-not $RepoRoot) {
    $candidates = [System.Collections.Generic.List[object]]::new()
    $gitProbe = Split-Path -Parent $Workflow
    while ($gitProbe) {
        # A `.git` ENTRY, not a directory: inside a worktree it is a file.
        if (Test-Path -LiteralPath (Join-Path $gitProbe '.git')) {
            $candidates.Add([pscustomobject]@{ Path = $gitProbe; Why = 'nearest .git ancestor' }); break
        }
        $up = Split-Path -Parent $gitProbe
        if ($up -eq $gitProbe) { break }
        $gitProbe = $up
    }
    $d = Split-Path -Parent $Workflow
    $candidates.Add([pscustomobject]@{ Path = (Split-Path -Parent $d); Why = 'workflow grandparent (pack layout)' })
    $candidates.Add([pscustomobject]@{ Path = (Split-Path -Parent (Split-Path -Parent $d)); Why = 'one above that (in-repo layout)' })
    $candidates.Add([pscustomobject]@{ Path = $d; Why = 'the workflow directory itself' })

    $best = $null
    foreach ($c in $candidates) {
        if (-not $c.Path -or -not (Test-Path -LiteralPath $c.Path)) { continue }
        $hit = @($wantPaths | Where-Object { Test-Path -LiteralPath (Join-Path $c.Path $_) }).Count
        if (-not $best -or $hit -gt $best.Hit) {
            $best = [pscustomobject]@{ Path = $c.Path; Why = $c.Why; Hit = $hit }
        }
    }
    if ($wantPaths.Count -gt 0 -and (-not $best -or $best.Hit -eq 0)) {
        throw "cannot locate the root these steps are written against. Tried: $(($candidates | Where-Object Path | ForEach-Object { $_.Path }) -join ', '). Not one of the $($wantPaths.Count) path(s) the workflow names resolves under any of them. Pass -RepoRoot. Refusing to run every gate from the wrong directory and report the results as skips."
    }
    $RepoRoot = if ($best) { $best.Path } else { Split-Path -Parent $Workflow }
    $rootWhy = if ($best) { "$($best.Why); $($best.Hit)/$($wantPaths.Count) step path(s) resolve" } else { 'no step paths to verify against' }
}
else { $rootWhy = 'given with -RepoRoot' }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
# The steps are written relative to the repo root, so the runner has to stand there -- but this is a
# PROCESS-WIDE change, and dot-sourcing or importing this file used to leave the caller's shell in a
# different directory than it started in, silently. The .NOTES block claims this script is read-only
# against the repository; a cwd it never gives back is a write in every sense that matters.
$script:EntryLocation = (Get-Location).Path
Set-Location -LiteralPath $RepoRoot
Write-Note "root: $RepoRoot   [$rootWhy]"

# ---------------------------------------------------------------- execute
if ($runCmds.Count -eq 0) {
    # Not a pass, and not a skip either. Nobody chose to run nothing; the parser found nothing to
    # run, which means either the workflow is empty or this runner has stopped recognising it. The
    # original threw here. A typed INCONCLUSIVE is better: it reaches the verdict table with a
    # reason instead of a stack trace, and it is the same exit code.
    Write-Bad "0 executable step(s) parsed out of $(Split-Path -Leaf $Workflow)"
    Add-Result 'workflow' 'INCONCLUSIVE' 'no runnable step parsed -- nothing was measured'
}
else {
    Write-Note "$($runCmds.Count) step(s) found"
    foreach ($step in ($steps | Where-Object Exec)) {
        $cmd = $step.Run
        $label = if ($step.Name) { $step.Name }
        elseif ($step.Exec -eq 'pwsh') { ($cmd -split '\s+')[0] -replace '.*[\\/]', '' }
        else { ($cmd -split '\s+')[1] -replace '.*[\\/]', '' }
        # PRE-FLIGHT, because exit 2 is overloaded and the collision is not theoretical.
        # Exit 2 is this pack's skip convention, and it is ALSO what a Python interpreter returns
        # for "can't open file" -- so a step pointed at a path that does not exist came back
        # indistinguishable from a check that deliberately declined to run. Thirteen of them did,
        # on a simulated distribution, and the verdict table said SKIPPED thirteen times.
        # A missing script is the runner failing to run what the workflow declares. That is
        # INCONCLUSIVE, and it names the path so the cause is one line rather than a guess.
        $needs = Get-StepScriptPath $step
        if ($needs -and -not (Test-Path -LiteralPath (Join-Path $RepoRoot $needs))) {
            Write-Bad "$label -- $needs does not exist under $RepoRoot"
            Add-Result $label 'INCONCLUSIVE' "$needs not found -- not run, and not a skip"
            continue
        }
        Write-Note "run: $cmd$(if ($step.Shell) { "   [shell: $($step.Shell)]" })"
        # `cmd /c` cannot run PowerShell; route pwsh-declared steps the way Actions does (see above).
        $r = if ($step.Exec -eq 'pwsh') { Invoke-PwshStep $cmd }
        else { $o = & cmd /c "$cmd 2>&1"; [pscustomobject]@{ Output = $o; Code = $LASTEXITCODE } }
        $out = $r.Output
        $code = $r.Code
        $tail = ($out | Select-Object -Last 3) -join ' / '
        switch ($code) {
            0 { Write-Ok "$label (exit 0)"; Add-Result $label 'PASS' $tail }
            2 {
                # Exit 2 is the shipped skip convention across every gate in this pack: the check
                # could not run and said so. Report it as SKIPPED, which is partial cover, never a
                # pass -- and never silently folded into PASS, which is what makes it useful.
                Write-Note "$label (exit 2) SKIPPED -- $tail"
                Add-Result $label 'SKIPPED' "exit 2 -- not run; do not read this as a pass"
            }
            default {
                Write-Bad "$label (exit $code)"
                ($out | Select-Object -Last 25) | ForEach-Object { Write-Host "        $_" }
                Add-Result $label 'FAIL' "exit $code"
            }
        }
    }
}

# Every step has run, so the borrowed cwd goes back before anything else happens. Placed here
# rather than in a finally because the exits below are the only way out and a `finally` around an
# `exit` in a dot-sourced script would take the caller's session with it.
Set-Location -LiteralPath $script:EntryLocation

# ---------------------------------------------------------------- verdict
Write-Head "Verdict"
$results | Format-Table Gate, Status, Detail -AutoSize | Out-String -Width 160 | Write-Host
$bad = @($results | Where-Object Status -in @('FAIL', 'INCONCLUSIVE'))
$skipped = @($results | Where-Object Status -eq 'SKIPPED')
if ($bad.Count) {
    Write-Host "LOCAL CI FAILED -- $($bad.Count) gate(s) failed or measured nothing." -ForegroundColor Red
    exit 1
}
if ($skipped.Count) {
    Write-Host "LOCAL CI PASSED, WITH $($skipped.Count) GATE(S) SKIPPED -- that is partial cover, not a green build." -ForegroundColor Yellow
    exit 2
}
Write-Host "LOCAL CI PASSED -- every gate $(Split-Path -Leaf $Workflow) declares passed here." -ForegroundColor Green
Write-Host "Reminder: where hosted CI exists it stays authoritative. A local pass is evidence, not authority." -ForegroundColor DarkGray
exit 0
