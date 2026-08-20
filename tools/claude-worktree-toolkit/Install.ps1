#requires -Version 7
<#
    Install.ps1 — one-time setup for the claude-worktree-toolkit.

    Wires wt.ps1 into your PowerShell profile so `nwt/cwt/lwt/pwt/swt/rwt` are available in every new
    pwsh session (and every Claude Code session, which launches pwsh). Idempotent: re-running updates the
    block it manages instead of duplicating it, and it backs your profile up first. Nothing is deleted or
    force-run — it only appends a small, clearly-delimited block to your $PROFILE.

    Usage:
      ./Install.ps1 -RepoPath 'C:\path\to\your\primary-clone'
      ./Install.ps1 -RepoPath '/Users/you/code/your-repo' -WtHome '~/wt' -Base main
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepoPath,          # your existing git clone (hosts .git); worktrees branch off it
    [string]$WtHome = (Join-Path $HOME 'wt'),         # where worktrees live
    [string]$Base   = 'main'                          # default base branch
)

$ErrorActionPreference = 'Stop'
function Ok($m)   { Write-Host "  + $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  ! $m" -ForegroundColor Yellow }

Write-Host "`nclaude-worktree-toolkit — install`n" -ForegroundColor Cyan

# 1) the tool must sit next to this installer
$wt = Join-Path $PSScriptRoot 'wt.ps1'
if (-not (Test-Path $wt)) { throw "wt.ps1 not found next to Install.ps1 ($PSScriptRoot). Keep the toolkit files together." }
Ok "found wt.ps1"

# 2) prerequisites
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "git not found on PATH — install git first (https://git-scm.com)." }
Ok "git found"
if (Get-Command gh -ErrorAction SilentlyContinue) { Ok "gh found" }
else { Warn "gh (GitHub CLI) not found — 'pwt' and 'rwt -Merge' need it. Install later: https://cli.github.com" }
if (-not $IsWindows) { Warn "Non-Windows: core commands work, but the 'is this tree live?' safety probe is a no-op — don't reap a worktree you have a session in." }

# 3) validate the repo path
$resolved = (Resolve-Path -LiteralPath $RepoPath -ErrorAction SilentlyContinue)?.Path
if ($resolved) { $RepoPath = $resolved }
if (-not (Test-Path (Join-Path $RepoPath '.git'))) { throw "No .git found at '$RepoPath' — point -RepoPath at your primary clone." }
Ok "repo: $RepoPath"

# 4) wire an idempotent block into the profile (loaded by every pwsh host for this user)
$profilePath = $PROFILE.CurrentUserAllHosts
$dir = Split-Path $profilePath
if (-not (Test-Path $dir))         { New-Item -ItemType Directory -Force $dir | Out-Null }
if (-not (Test-Path $profilePath)) { New-Item -ItemType File -Force $profilePath | Out-Null; Ok "created profile: $profilePath" }
else { Copy-Item $profilePath "$profilePath.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"; Ok "backed up existing profile" }

$begin = '# >>> claude-worktree-toolkit >>>'
$end   = '# <<< claude-worktree-toolkit <<<'
# These four values are interpolated into SINGLE-QUOTED PowerShell literals, so the one character
# that can break out is the single quote -- and a path containing one is legal on Windows
# (C:\Users\O'Brien\repos). Unescaped, that wrote a profile that fails to parse, i.e. a shell that
# will not start, from an installer that reported success. Doubling is the escape inside a
# single-quoted string; there is no other metacharacter to worry about in this context.
$q = { param($s) $s -replace "'", "''" }
$block = @"
$begin
`$env:WT_REPO = '$(& $q $RepoPath)'
`$env:WT_HOME = '$(& $q $WtHome)'
`$env:WT_BASE = '$(& $q $Base)'
. '$(& $q $wt)'
$end
"@

$content = (Get-Content $profilePath -Raw -ErrorAction SilentlyContinue) ?? ''
$pattern = [regex]::Escape($begin) + '.*?' + [regex]::Escape($end) + '\r?\n?'
$content = [regex]::Replace($content, $pattern, '', 'Singleline')   # drop any prior managed block
$content = ($content.TrimEnd() + "`n`n" + $block + "`n").TrimStart()
# WriteAllText, then read back and check. Three reasons, in order of how quietly they fail:
#   * Set-Content supports ShouldProcess, so under $WhatIfPreference it writes NOTHING and the "Ok"
#     below still prints -- an installer reporting success having done nothing.
#   * This is the user's $PROFILE. Truncate-then-write is not atomic, and the .bak above only helps
#     someone who knows to look for it.
#   * A write that succeeded and a write that produced the wrong bytes are different states, and
#     only reading it back tells them apart.
[System.IO.File]::WriteAllText($profilePath, $content, [System.Text.UTF8Encoding]::new($true))
if ([System.IO.File]::ReadAllText($profilePath) -ne $content) {
    throw "wrote $profilePath but read back something different -- restore the .bak beside it before opening a new shell."
}
Ok "profile updated"

Write-Host "`nDone. Open a NEW PowerShell session (or run:  . `$PROFILE ), then try:" -ForegroundColor Cyan
Write-Host "    nwt try the toolkit      # new worktree, cd's you in (auto-named if you omit words)"
Write-Host "    lwt                      # list your worktrees"
Write-Host "    swt                      # print-only: what's safe to clean up"
Write-Host "    rwt                      # tear down the current worktree`n"
Write-Host "Keep this toolkit folder where it is — your profile now points at $wt`n" -ForegroundColor DarkGray
