#requires -Version 7
# Inherited, not incidental: this file dot-sources wt.ps1, which cannot PARSE under Windows
# PowerShell 5.1. Declaring it here means the suite refuses with a version message instead of
# failing inside a dot-source with a syntax error pointing at someone else's file.
<#
.SYNOPSIS
    Tests the questions claude-worktree-toolkit asks before it deletes a branch or opens a PR.

.DESCRIPTION
    `rwt` deletes a branch when it believes the branch's work is on base. `swt` prints a verdict
    built on the same belief. Until this file existed, NOTHING tested either one -- the toolkit's
    only self-check (`lore-check`) compares animal names.

    So these are not unit tests of a matcher. They build REAL git repositories in a temp directory,
    perform REAL squash-merges, and assert what the toolkit concludes:

      1  single-commit branch, squash-merged     -> Merged = yes
      2  multi-commit branch, squash-merged      -> Merged = NO, Superseded = yes, Ahead = 2
      3  content folded into a DIFFERENT squash  -> Merged = NO, Superseded = yes
      4  origin/<base> unresolvable              -> Ran = NO, Merged = NO
      5  branch behind on an UNRELATED file      -> Superseded = yes  (scope control)
      6  rwt against an unresolvable base        -> BRANCH SURVIVES    <- the incident, end to end
      7  base resolves, BRANCH does not          -> Ran = NO           (second fail-open guard)
      8  branch with zero files of its own       -> Superseded = yes   (empty-pathspec guard)
      9  branch that genuinely adds work         -> Superseded = NO    (the other polarity)
     10  dirty tree, and each half of -Force     -> refused, and the refusal NAMES the loss
     11  a PR that would propose nothing         -> refused before push, both polarities

    WHY 10 EXISTS. `-DiscardChanges` and `-EvictLiveSession` were one `-Force`. They guard different
    hazards -- losing your own uncommitted work, versus pulling files from under someone else's live
    session -- so the case asserts that the wrong flag does NOT open the other gate, and that the
    refusal names the untracked handoff it would otherwise have destroyed.

    WHY 11 EXISTS. An empty PR pushes, goes green, reports MERGED, and lands nothing; nothing in
    that chain reads as alarming. Both polarities of the predicate, plus the consumer refusing
    before it pushes or touches gh.

    WHY 9 EXISTS. Cases 2, 3, 5 and 8 all assert `Superseded = yes`, and case 4 asserts `null`. With
    only those, an implementation reduced to `return $true` passes every assertion. A gate asserted
    in one polarity is half-verified: it must be shown to say NO in the state it was built to catch
    AND yes once that state is genuinely cleared.

    WHY 6 AND 10 EXIST. Every other case asserts a private `_Wt-Branch*` helper. The defect that
    prompted this file was not in a helper -- it was that `rwt` CONSUMED the answer without the
    guard `swt` already had. A suite that only tests the predicate stays green while the consumer
    reintroduces the bug, which is the shape of the original failure, not a test of it. Cases 6 and
    10 therefore drive `Reap-InvestWorktree` itself against real linked worktrees, and case 11 drives
    `Publish-InvestWorktree`.

    Assertions are on PROPERTIES -- "does it conclude merged?", "did the branch survive?" -- never
    on how the conclusion was reached.

.PARAMETER KeepFixtures
    Leave the temp repositories on disk and print the path, for debugging a failure.

.PARAMETER Skip
    Case numbers to deliberately NOT run. A skipped case exits 2 and is named. Never a pass.

.PARAMETER SelfTest
    Run the negative controls and exit. Proves this suite can FAIL -- including that its own
    comparer fires, and that a genuinely unlanded branch is not reported merged. A gate that has
    never been red is not evidence. Writes nothing inside the repository.

.EXAMPLE
    pwsh -NoProfile -File tools/claude-worktree-toolkit/Test-WorktreeMergedness.ps1

.EXAMPLE
    pwsh -NoProfile -File tools/claude-worktree-toolkit/Test-WorktreeMergedness.ps1 -SelfTest

.NOTES
    EXIT CONTRACT
      0  every case ran and passed
      1  a case FAILED, or fewer cases ran than exist, or the environment could not be resolved
      2  a case was deliberately skipped (-Skip) and nothing else failed -- SKIPPED, never a pass

    Case count is COUNTED, never printed as a literal: a suite that silently stops running a case
    must not report full coverage. A check that could not run must never report PASS.

    Requires: git (>= 2.28, for --initial-branch), pwsh 7+. No network. Writes only inside its own
    temp directory.
#>
[CmdletBinding()]
param(
    [switch]$KeepFixtures,
    [ValidateRange(1, 11)][int[]]$Skip = @(),
    [switch]$SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:TOTAL_CASES = 11

$script:Failures = @()
$script:Passes   = 0
$script:Skipped  = @()
$script:CasesRun = 0

function Assert-Equal {
    param([Parameter(Mandatory)][AllowNull()]$Expected, [Parameter(Mandatory)][AllowNull()]$Actual,
          [Parameter(Mandatory)][string]$What, [switch]$Quiet)
    # TYPE-STRICT on purpose. PowerShell coerces the right operand to the left operand's type, so
    # `$false -eq ''` and `$false -eq @()` are both TRUE. Most assertions here expect $false, so a
    # contract change returning an empty string or empty array for .Merged would pass silently.
    $ok = if ($null -eq $Expected)      { $null -eq $Actual }
          elseif ($Expected -is [bool]) { ($Actual -is [bool]) -and ($Actual -eq $Expected) }
          else                          { $Expected -eq $Actual }
    if ($ok) {
        if (-not $Quiet) { Write-Host "    ok   $What" -ForegroundColor DarkGray }
        $script:Passes++
    } else {
        if (-not $Quiet) { Write-Host "    FAIL $What -- expected [$Expected], got [$Actual]" -ForegroundColor Red }
        $script:Failures += $What
    }
    return $ok
}

function Invoke-Git {
    # Fixture helper. Fails loudly: a fixture that half-built would produce a meaningless verdict.
    param([Parameter(Mandatory)][string]$RepoPath, [Parameter(Mandatory)][string[]]$GitArgs)
    $out = & git -C $RepoPath @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "fixture git failed: git -C $RepoPath $($GitArgs -join ' ')`n$out" }
    return $out
}

function New-Fixture {
    <#  Builds an origin + working clone with a 'main' holding one commit. Returns the clone path. #>
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Name)

    $originPath = Join-Path $Root "$Name-origin.git"
    $workPath   = Join-Path $Root $Name
    $null = New-Item -ItemType Directory -Path $originPath -Force
    $null = New-Item -ItemType Directory -Path $workPath -Force

    # These two are the least portable calls in the file (--initial-branch is git >= 2.28), so they
    # go through the loud helper too. Discarding their exit codes made an old-git failure surface
    # four lines later as a confusing `git config` error.
    $out = & git init --bare --initial-branch=main $originPath 2>&1
    if ($LASTEXITCODE -ne 0) { throw "fixture git init --bare failed (git >= 2.28 required?)`n$out" }
    $out = & git init --initial-branch=main $workPath 2>&1
    if ($LASTEXITCODE -ne 0) { throw "fixture git init failed (git >= 2.28 required?)`n$out" }

    Invoke-Git $workPath @('config','user.email','test@example.invalid') | Out-Null
    Invoke-Git $workPath @('config','user.name','Fixture') | Out-Null
    Invoke-Git $workPath @('config','commit.gpgsign','false') | Out-Null
    # A global core.hooksPath would otherwise run the operator's hooks inside every fixture commit —
    # an uncommitted input the fixture would silently inherit. Point it at a directory that does not
    # exist: git then finds no hooks, which is the intent, without an empty config value.
    Invoke-Git $workPath @('config','core.hooksPath',(Join-Path $workPath '.git/no-such-hooks')) | Out-Null

    [System.IO.File]::WriteAllText((Join-Path $workPath 'seed.txt'), 'seed')
    Invoke-Git $workPath @('add','-A') | Out-Null
    Invoke-Git $workPath @('commit','-m','seed') | Out-Null
    Invoke-Git $workPath @('remote','add','origin',$originPath) | Out-Null
    Invoke-Git $workPath @('push','-u','origin','main') | Out-Null
    return $workPath
}

function Add-Commit {
    param([Parameter(Mandatory)][string]$RepoPath, [Parameter(Mandatory)][string]$File,
          [Parameter(Mandatory)][string]$Content, [Parameter(Mandatory)][string]$Message)
    [System.IO.File]::WriteAllText((Join-Path $RepoPath $File), $Content)
    Invoke-Git $RepoPath @('add','-A') | Out-Null
    Invoke-Git $RepoPath @('commit','-m',$Message) | Out-Null
}

function Test-BranchExists {
    param([Parameter(Mandatory)][string]$RepoPath, [Parameter(Mandatory)][string]$Branch)
    $null = & git -C $RepoPath rev-parse --verify --quiet "refs/heads/$Branch" 2>$null
    return ($LASTEXITCODE -eq 0)
}

function New-TempRoot {
    $p = Join-Path ([System.IO.Path]::GetTempPath()) ("wt-mergedness-" + [guid]::NewGuid().ToString('N').Substring(0,8))
    $null = New-Item -ItemType Directory -Path $p -Force
    return $p
}

function Remove-TempRoot {
    param([Parameter(Mandatory)][string]$Path)
    # -LiteralPath: a '[' or ']' in %TEMP% makes positional -Path a wildcard and a silent no-op.
    # And VERIFY the removal -- an unverified cleanup that quietly leaves five working trees behind
    # is the same "absence reported as success" this suite exists to catch, one layer down.
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $Path) {
        Write-Host "  ! fixtures could not be removed (a handle is held): $Path" -ForegroundColor Yellow
    }
}

# ── locate and load the toolkit ────────────────────────────────────────────────────────────────
# Sits beside wt.ps1 deliberately, so it travels INSIDE the distributed zip. A test that documents
# the toolkit's central verdict is no use to a recipient who did not receive it.
$toolkit = Join-Path $PSScriptRoot 'wt.ps1'
if (-not (Test-Path $toolkit)) {
    Write-Host "wt.ps1 not found beside this script ($PSScriptRoot) -- cannot test what is not there." -ForegroundColor Red
    exit 1
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "git not on PATH -- cannot build fixtures." -ForegroundColor Red
    exit 1
}
. $toolkit

# ── negative controls ──────────────────────────────────────────────────────────────────────────
if ($SelfTest) {
    Write-Host "`nSELF-TEST -- negative controls" -ForegroundColor Cyan
    $ctlPass = 0; $ctlFail = @()
    function Control {
        param([string]$Name, [bool]$Got, [bool]$Want)
        if ($Got -eq $Want) { Write-Host "  [ok  ] $Name" -ForegroundColor DarkGray; $script:ctlPass++ }
        else { Write-Host "  [FAIL] $Name -- wanted $Want, got $Got" -ForegroundColor Red; $script:ctlFail += $Name }
    }

    # 1-2. Grade the grader, in both directions.
    $saveF = $script:Failures; $saveP = $script:Passes
    $script:Failures = @(); $script:Passes = 0
    $r1 = Assert-Equal -Expected $true -Actual $true  -What 'x' -Quiet
    $r2 = Assert-Equal -Expected $true -Actual $false -What 'x' -Quiet
    # 3. The coercion trap: $false -eq '' is TRUE in PowerShell. The comparer must not agree.
    $r3 = Assert-Equal -Expected $false -Actual ''    -What 'x' -Quiet
    $r4 = Assert-Equal -Expected $false -Actual @()   -What 'x' -Quiet
    $script:Failures = $saveF; $script:Passes = $saveP

    Control 'comparer passes a real match'                      $r1 $true
    Control 'comparer FAILS a real mismatch'                    $r2 $false
    Control 'comparer rejects empty-string coerced to $false'   $r3 $false
    Control 'comparer rejects empty-array coerced to $false'    $r4 $false

    # 5. Positive control: the harness can build a fixture in which a branch is genuinely unlanded,
    # and reports it so. Without this, case 4's three negatives are also what a broken environment
    # returns -- no repo, no git, $WtRepo still at wt.ps1's placeholder default.
    $root = New-TempRoot
    try {
        $repo = New-Fixture -Root $root -Name 'ctl'
        $script:WtRepo = $repo; $script:WtBase = 'main'
        Invoke-Git $repo @('checkout','-q','-b','genuinely-unlanded') | Out-Null
        Add-Commit -RepoPath $repo -File 'never-landed.txt' -Content 'x' -Message 'unlanded work'
        $m = _Wt-BranchMerged 'genuinely-unlanded'
        Control 'fixture is real: base resolves, question can be asked' $m.Ran $true
        Control 'genuinely unlanded branch is NOT reported merged'      $m.Merged $false
        Control 'and it is reported as ahead'                           ($m.Ahead -ge 1) $true
    } finally { Remove-TempRoot $root }

    Write-Host ''
    if ($ctlFail.Count) {
        Write-Host "SELF-TEST FAILED -- $($ctlFail.Count) control(s) misbehaved:" -ForegroundColor Red
        $ctlFail | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        exit 1
    }
    Write-Host "SELF-TEST PASSED -- every control behaved as specified ($ctlPass)" -ForegroundColor Green
    exit 0
}

# ── cases ──────────────────────────────────────────────────────────────────────────────────────
$tempRoot = New-TempRoot
Write-Host "`n=== worktree merged-ness tests ===" -ForegroundColor Cyan
Write-Host "fixtures: $tempRoot`n" -ForegroundColor DarkGray

try {
    if (1 -notin $Skip) {
        $script:CasesRun++
        Write-Host "  [1] single-commit branch, squash-merged"
        $repo = New-Fixture -Root $tempRoot -Name 'case1'
        $script:WtRepo = $repo; $script:WtBase = 'main'
        Invoke-Git $repo @('checkout','-q','-b','single') | Out-Null
        Add-Commit -RepoPath $repo -File 'f1.txt' -Content 'one' -Message 'add f1'
        Invoke-Git $repo @('checkout','-q','main') | Out-Null
        Invoke-Git $repo @('merge','--squash','single') | Out-Null
        Invoke-Git $repo @('commit','-m','squash of single') | Out-Null
        Invoke-Git $repo @('push','origin','main') | Out-Null

        $m = _Wt-BranchMerged 'single'
        $null = Assert-Equal -Expected $true -Actual $m.Ran    -What '1: the question could be asked'
        $null = Assert-Equal -Expected $true -Actual $m.Merged -What '1: single-commit squash reports MERGED'
    } else { $script:Skipped += '1' }

    if (2 -notin $Skip) {
        $script:CasesRun++
        Write-Host "  [2] multi-commit branch, squash-merged"
        $repo = New-Fixture -Root $tempRoot -Name 'case2'
        $script:WtRepo = $repo; $script:WtBase = 'main'
        Invoke-Git $repo @('checkout','-q','-b','multi') | Out-Null
        Add-Commit -RepoPath $repo -File 'f2.txt' -Content 'two'   -Message 'add f2'
        Add-Commit -RepoPath $repo -File 'f3.txt' -Content 'three' -Message 'add f3'
        Invoke-Git $repo @('checkout','-q','main') | Out-Null
        Invoke-Git $repo @('merge','--squash','multi') | Out-Null
        Invoke-Git $repo @('commit','-m','squash of multi') | Out-Null
        Invoke-Git $repo @('push','origin','main') | Out-Null

        $m = _Wt-BranchMerged 'multi'
        $null = Assert-Equal -Expected $true  -Actual $m.Ran    -What '2: the question could be asked'
        $null = Assert-Equal -Expected $false -Actual $m.Merged -What '2: multi-commit squash reports NOT merged (the documented blind spot)'
        # Ahead is printed to the user on the confirmation line immediately before a branch is
        # deleted, so it is part of the contract, not a diagnostic.
        $null = Assert-Equal -Expected 2      -Actual $m.Ahead  -What '2: reports BOTH commits as ahead'
        $null = Assert-Equal -Expected $true  -Actual (_Wt-BranchSuperseded 'multi') -What '2: superseded check DOES see it'
    } else { $script:Skipped += '2' }

    if (3 -notin $Skip) {
        $script:CasesRun++
        Write-Host "  [3] content folded into a different PR's squash"
        $repo = New-Fixture -Root $tempRoot -Name 'case3'
        $script:WtRepo = $repo; $script:WtBase = 'main'
        Invoke-Git $repo @('checkout','-q','-b','folded') | Out-Null
        Add-Commit -RepoPath $repo -File 'f4.txt' -Content 'four' -Message 'add f4 on folded'
        Invoke-Git $repo @('checkout','-q','main') | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $repo 'f4.txt'), 'four')
        [System.IO.File]::WriteAllText((Join-Path $repo 'f5.txt'), 'five')
        Invoke-Git $repo @('add','-A') | Out-Null
        Invoke-Git $repo @('commit','-m','someone else PR: f4 + f5') | Out-Null
        Invoke-Git $repo @('push','origin','main') | Out-Null

        $m = _Wt-BranchMerged 'folded'
        $null = Assert-Equal -Expected $true  -Actual $m.Ran    -What '3: the question could be asked'
        $null = Assert-Equal -Expected $false -Actual $m.Merged -What '3: folded-into-another-squash reports NOT merged'
        $null = Assert-Equal -Expected $true  -Actual (_Wt-BranchSuperseded 'folded') -What '3: superseded check sees the content is already on base'
    } else { $script:Skipped += '3' }

    if (4 -notin $Skip) {
        $script:CasesRun++
        Write-Host "  [4] origin/<base> unresolvable"
        $repo = New-Fixture -Root $tempRoot -Name 'case4'
        $script:WtRepo = $repo
        $script:WtBase = 'main'
        Invoke-Git $repo @('checkout','-q','-b','unlanded') | Out-Null
        Add-Commit -RepoPath $repo -File 'f6.txt' -Content 'genuinely unlanded' -Message 'real work'
        # Positive control FIRST: prove the fixture answers normally, so the negatives below cannot
        # be satisfied by a broken environment.
        $null = Assert-Equal -Expected $true -Actual (_Wt-BranchMerged 'unlanded').Ran -What '4: control -- with a good base the question CAN be asked'

        $script:WtBase = 'no-such-base-branch'   # a WT_BASE typo / renamed default / failed fetch
        $m = _Wt-BranchMerged 'unlanded'
        $null = Assert-Equal -Expected $false -Actual $m.Ran    -What '4: reports that the question could NOT be asked'
        $null = Assert-Equal -Expected $false -Actual $m.Merged -What '4: UNKNOWN is not merged (branch with real work is NOT deletable)'
        $null = Assert-Equal -Expected $null  -Actual (_Wt-BranchSuperseded 'unlanded') -What '4: superseded is UNKNOWN, never a false yes'
    } else { $script:Skipped += '4' }

    if (5 -notin $Skip) {
        $script:CasesRun++
        Write-Host "  [5] branch behind on an UNRELATED shared file"
        $repo = New-Fixture -Root $tempRoot -Name 'case5'
        $script:WtRepo = $repo; $script:WtBase = 'main'
        Add-Commit -RepoPath $repo -File 'shared.txt' -Content 'v1' -Message 'shared v1'
        # TWO commits, so patch-id is genuinely blind here -- otherwise this case would pass for the
        # wrong reason (a single commit landing verbatim IS patch-visible; that is case 1).
        Invoke-Git $repo @('checkout','-q','-b','contributor') | Out-Null
        Add-Commit -RepoPath $repo -File 'f7.txt' -Content 'seven' -Message 'add f7'
        Add-Commit -RepoPath $repo -File 'f8.txt' -Content 'eight' -Message 'add f8'
        Invoke-Git $repo @('checkout','-q','main') | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $repo 'f7.txt'), 'seven')
        [System.IO.File]::WriteAllText((Join-Path $repo 'f8.txt'), 'eight')
        Invoke-Git $repo @('add','-A') | Out-Null
        Invoke-Git $repo @('commit','-m','land f7 + f8 in one squash') | Out-Null
        Add-Commit -RepoPath $repo -File 'shared.txt' -Content 'v2-moved-on' -Message 'shared v2'
        Invoke-Git $repo @('push','origin','main') | Out-Null

        $m = _Wt-BranchMerged 'contributor'
        $null = Assert-Equal -Expected $true  -Actual $m.Ran    -What '5: the question could be asked'
        $null = Assert-Equal -Expected $false -Actual $m.Merged -What '5: patch-id still reports NOT merged'
        $null = Assert-Equal -Expected $true  -Actual (_Wt-BranchSuperseded 'contributor') `
            -What '5: superseded is YES -- scoped to the branch own files, so being behind on shared.txt is irrelevant'
    } else { $script:Skipped += '5' }

    if (6 -notin $Skip) {
        $script:CasesRun++
        Write-Host "  [6] rwt against an unresolvable base  <- the incident, end to end"
        $repo = New-Fixture -Root $tempRoot -Name 'case6'
        $script:WtRepo = $repo; $script:WtBase = 'main'
        $script:WtHome = Join-Path $tempRoot 'case6-trees'
        $null = New-Item -ItemType Directory -Path $script:WtHome -Force

        $slug   = _Wt-Slug 'doomed'
        $wtPath = Join-Path $script:WtHome $slug
        Invoke-Git $repo @('worktree','add','-b','doomed',$wtPath,'main') | Out-Null
        Invoke-Git $wtPath @('config','user.email','test@example.invalid') | Out-Null
        Invoke-Git $wtPath @('config','user.name','Fixture') | Out-Null
        Invoke-Git $wtPath @('config','commit.gpgsign','false') | Out-Null
        Add-Commit -RepoPath $wtPath -File 'precious.txt' -Content 'never landed anywhere' -Message 'unlanded work'

        $null = Assert-Equal -Expected $true -Actual (Test-BranchExists $repo 'doomed') -What '6: control -- the branch exists before rwt runs'

        # Break the base the way a failed fetch / renamed default / WT_BASE typo would.
        $script:WtBase = 'no-such-base-branch'
        # Production runs from a $PROFILE without StrictMode; imposing it only here would exercise a
        # configuration the toolkit never actually runs under.
        Set-StrictMode -Off
        try { Reap-InvestWorktree -Branch 'doomed' -Yes -ErrorAction SilentlyContinue | Out-Null }
        catch { Write-Host "    (rwt threw: $($_.Exception.Message))" -ForegroundColor DarkGray }
        Set-StrictMode -Version Latest

        # THE ASSERTION THIS FILE EXISTS FOR. Before the guard, this branch was force-deleted and
        # the user was told it was "patch-id-verified".
        $null = Assert-Equal -Expected $true -Actual (Test-BranchExists $repo 'doomed') `
            -What '6: branch SURVIVES rwt when merged status is unknown'
        $script:WtHome = $null
    } else { $script:Skipped += '6' }

    if (7 -notin $Skip) {
        $script:CasesRun++
        Write-Host "  [7] base resolves but the BRANCH does not"
        $repo = New-Fixture -Root $tempRoot -Name 'case7'
        $script:WtRepo = $repo; $script:WtBase = 'main'
        # Case 4 short-circuits on the base guard, so the exit-code check after `git cherry` is
        # never reached there. This is the input that reaches it.
        $m = _Wt-BranchMerged 'no-such-branch-at-all'
        $null = Assert-Equal -Expected $false -Actual $m.Ran    -What '7: an unresolvable BRANCH is also UNKNOWN, not merged'
        $null = Assert-Equal -Expected $false -Actual $m.Merged -What '7: and therefore not deletable'
    } else { $script:Skipped += '7' }

    if (8 -notin $Skip) {
        $script:CasesRun++
        Write-Host "  [8] branch with zero files of its own"
        $repo = New-Fixture -Root $tempRoot -Name 'case8'
        $script:WtRepo = $repo; $script:WtBase = 'main'
        # A branch created off main that changes nothing. The empty-pathspec guard exists because an
        # empty file list would otherwise widen the next diff to EVERY path and invert the answer.
        Invoke-Git $repo @('checkout','-q','-b','empty-branch') | Out-Null
        Invoke-Git $repo @('checkout','-q','main') | Out-Null
        Add-Commit -RepoPath $repo -File 'moved-on.txt' -Content 'base kept working' -Message 'base moves on'
        Invoke-Git $repo @('push','origin','main') | Out-Null

        $null = Assert-Equal -Expected $true -Actual (_Wt-BranchSuperseded 'empty-branch') `
            -What '8: a branch that changes nothing adds nothing (empty pathspec does not invert it)'
    } else { $script:Skipped += '8' }

    if (9 -notin $Skip) {
        $script:CasesRun++
        Write-Host "  [9] branch that genuinely adds work"
        $repo = New-Fixture -Root $tempRoot -Name 'case9'
        $script:WtRepo = $repo; $script:WtBase = 'main'
        # Real unlanded work: nothing on base matches it. Without this case, a _Wt-BranchSuperseded
        # stubbed to `return $true` would satisfy every other assertion in the file.
        Invoke-Git $repo @('checkout','-q','-b','contributing') | Out-Null
        Add-Commit -RepoPath $repo -File 'brand-new.txt' -Content 'genuinely new work' -Message 'real contribution'

        $null = Assert-Equal -Expected $false -Actual (_Wt-BranchSuperseded 'contributing') `
            -What '9: a branch with real unlanded work is NOT superseded'
        $null = Assert-Equal -Expected $false -Actual (_Wt-BranchMerged 'contributing').Merged `
            -What '9: and it is not merged either'
    } else { $script:Skipped += '9' }

    if (10 -notin $Skip) {
        $script:CasesRun++
        Write-Host " [10] dirty tree, and the two halves of the old -Force"
        $repo = New-Fixture -Root $tempRoot -Name 'case10'
        $script:WtRepo = $repo; $script:WtBase = 'main'
        $script:WtHome = Join-Path $tempRoot 'case10-trees'
        $null = New-Item -ItemType Directory -Path $script:WtHome -Force

        $wtPath = Join-Path $script:WtHome (_Wt-Slug 'dirty-tree')
        Invoke-Git $repo @('worktree','add','-b','dirty-tree',$wtPath,'main') | Out-Null
        # An untracked handoff: gitignored by design in real use, so it exists ONLY here.
        [System.IO.File]::WriteAllText((Join-Path $wtPath 'HANDOFF.md'), 'the only copy of this')

        Set-StrictMode -Off
        $err = $null
        try { Reap-InvestWorktree -Branch 'dirty-tree' -Yes -ErrorAction Stop | Out-Null } catch { $err = "$_" }
        $null = Assert-Equal -Expected $true -Actual ($null -ne $err) -What '10: a dirty tree is refused'
        $null = Assert-Equal -Expected $true -Actual ([bool]($err -match 'HANDOFF')) `
            -What '10: and the refusal NAMES the untracked handoff it would have destroyed'
        $null = Assert-Equal -Expected $true -Actual (Test-Path $wtPath) -What '10: the tree is still there'

        # -EvictLiveSession must NOT unlock the dirty gate. That separation is the whole change.
        $err2 = $null
        try { Reap-InvestWorktree -Branch 'dirty-tree' -Yes -EvictLiveSession -ErrorAction Stop | Out-Null } catch { $err2 = "$_" }
        $null = Assert-Equal -Expected $true -Actual ($null -ne $err2) `
            -What '10: -EvictLiveSession alone does NOT authorise discarding uncommitted work'
        $null = Assert-Equal -Expected $true -Actual (Test-Path $wtPath) -What '10: still there after the wrong flag'

        # -DiscardChanges is the flag that does, and it must actually work.
        # The verdict is the assertion two lines down -- whether the tree is GONE -- not whether the
        # call threw, because rwt legitimately reports non-fatal noise here (a base fetch it cannot
        # reach in a fixture repo with no remote). So the error is captured rather than swallowed:
        # an empty catch discards the one piece of evidence that explains a surprising failure.
        $err3 = $null
        try { Reap-InvestWorktree -Branch 'dirty-tree' -Yes -DiscardChanges -ErrorAction SilentlyContinue | Out-Null } catch { $err3 = "$_" }
        Set-StrictMode -Version Latest
        if ($err3 -and (Test-Path $wtPath)) { Write-Host "    (rwt -DiscardChanges reported: $err3)" -ForegroundColor DarkGray }
        $null = Assert-Equal -Expected $false -Actual (Test-Path $wtPath) -What '10: -DiscardChanges does reap it'
        $script:WtHome = $null
    } else { $script:Skipped += '10' }

    if (11 -notin $Skip) {
        $script:CasesRun++
        Write-Host " [11] a PR that would propose nothing"
        $repo = New-Fixture -Root $tempRoot -Name 'case11'
        $script:WtRepo = $repo; $script:WtBase = 'main'

        # Both polarities of the predicate, then the consumer refusing on the empty one.
        Invoke-Git $repo @('checkout','-q','-b','proposes-nothing') | Out-Null
        Invoke-Git $repo @('checkout','-q','main') | Out-Null
        Add-Commit -RepoPath $repo -File 'base-moved.txt' -Content 'base kept working' -Message 'base moves on'
        Invoke-Git $repo @('push','origin','main') | Out-Null
        $null = Assert-Equal -Expected $true -Actual (_Wt-BranchIntroducesNothing -RepoPath $repo -Branch 'proposes-nothing') `
            -What '11: a branch with no changes of its own introduces nothing'

        Invoke-Git $repo @('checkout','-q','-b','proposes-something') | Out-Null
        Add-Commit -RepoPath $repo -File 'real.txt' -Content 'actual work' -Message 'real work'
        $null = Assert-Equal -Expected $false -Actual (_Wt-BranchIntroducesNothing -RepoPath $repo -Branch 'proposes-something') `
            -What '11: a branch with real work does NOT (the other polarity)'

        # The consumer: pwt must refuse BEFORE it pushes or touches gh.
        Set-StrictMode -Off
        Push-Location $repo
        try {
            Invoke-Git $repo @('checkout','-q','proposes-nothing') | Out-Null
            $perr = $null
            try { Publish-InvestWorktree -ErrorAction Stop | Out-Null } catch { $perr = "$_" }
            $null = Assert-Equal -Expected $true -Actual ([bool]($perr -match 'introduces no change')) `
                -What '11: pwt refuses to open the empty PR'
        } finally { Pop-Location; Set-StrictMode -Version Latest }
    } else { $script:Skipped += '11' }
}
finally {
    if ($KeepFixtures) { Write-Host "`nfixtures kept: $tempRoot" -ForegroundColor Yellow }
    else { Remove-TempRoot $tempRoot }
}

# ── report ─────────────────────────────────────────────────────────────────────────────────────
Write-Host ''
$ran = $script:Passes + $script:Failures.Count
if ($ran -eq 0) {
    Write-Host "INCONCLUSIVE -- zero assertions ran. Not a pass." -ForegroundColor Red
    exit 1
}
$expectedCases = $script:TOTAL_CASES - $script:Skipped.Count
if ($script:CasesRun -ne $expectedCases) {
    Write-Host "INCONCLUSIVE -- ran $($script:CasesRun) case(s), expected $expectedCases. A case vanished; that is not a pass." -ForegroundColor Red
    exit 1
}
if ($script:Failures.Count) {
    Write-Host "FAILED  $($script:Failures.Count) of $ran assertion(s):" -ForegroundColor Red
    $script:Failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
if ($script:Skipped.Count) {
    Write-Host "PASSED $ran assertion(s), but case(s) $($script:Skipped -join ', ') were SKIPPED -- not a full pass." -ForegroundColor Yellow
    exit 2
}
Write-Host "PASSED  $ran assertion(s) across $($script:CasesRun)/$($script:TOTAL_CASES) cases, nothing skipped." -ForegroundColor Green
exit 0
