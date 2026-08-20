#requires -Version 7
# The guard is load-bearing, not decorative. This file is meant to be dot-sourced from $PROFILE,
# and it uses `??` (see _Wt-Base and _Wt-PrDetails). Under Windows PowerShell 5.1 that is a PARSE
# error, so the failure is not "the tool does not work" but "your shell does not start", with a
# message that names a line rather than a version. #requires turns that into one sentence.
# wt.ps1 — repeatable git-worktree management for Claude Code (shareable edition)
# ---------------------------------------------------------------------------
# A tiny, safe worktree workflow for people who run several Claude Code sessions
# in parallel: one unit of work = one worktree, branched fresh from origin/<base>,
# with a memorable auto-name. Dot-source this from your PowerShell $PROFILE and
# every shell (and every Claude Code session, which launches pwsh) gets:
#
#   nwt [name]     new worktree (fetch base, add, cd in). No name => a silly
#                  <adjective>-<animal> name (sassy-terrapin, feral-raccoon…).
#   cwt <msg>      stage-all + commit here (guards base/primary; -Coauthor trailer)
#   lwt            list worktrees + dirty state
#   pwt            publish: push + open/refresh a PR (no merge); -Message commits first,
#                  -Coauthor adds the trailer, -AllowEmpty overrides the refusal to open a
#                  PR that introduces no change vs base
#   lore-check     drift-check the animal gloss table against the name generator
#   swt            PRINT-ONLY stale-worktree report: which trees are clean,
#                  already merged into <base> (patch-id, which counts a squash only
#                  when the branch held ONE commit) and idle — i.e. safe to remove.
#                  Also flags "superseded" trees patch-id cannot see.
#                  Reports; never deletes.
#   rwt            teardown one worktree: remove it + delete the branch IF it is
#                  fully merged into <base>. -Merge squash-merges the PR first.
#                  -DiscardChanges / -EvictLiveSession are the two halves of -Force.
#
# What this edition deliberately OMITS (vs. the author's personal setup): no
# automatic/background reaping, no scheduled task, no process-killing, no
# window-hiding. Teardown is one explicit command (rwt); stragglers are surfaced
# by swt and removed on your say-so. Nothing here force-kills a process, uses
# --admin to bypass branch protection, or deletes anything without a merge check.
#
# SETUP: set the two paths below (or the WT_REPO / WT_HOME env vars). That's it.
# gh commands infer your repo from the worktree's origin remote — no repo slug to
# hardcode. Requires: git, PowerShell 7+, and (for pwt / rwt -Merge) the gh CLI.
# ---------------------------------------------------------------------------

# ── config ─────────────────────────────────────────────────────────────────
# Primary clone that hosts .git. NOBODY works in here — every unit of work is a
# worktree under $WtHome. Point this at your existing clone.
$script:WtRepo = if ($env:WT_REPO) { $env:WT_REPO } else { 'C:\path\to\your\primary-clone' }  # <-- EDIT ME
# Where all worktrees live (one folder per branch).
$script:WtHome = if ($env:WT_HOME) { $env:WT_HOME } else { Join-Path $HOME 'wt' }
# Default base branch.
$script:WtBase = if ($env:WT_BASE) { $env:WT_BASE } else { 'main' }
# Co-author trailer appended when you commit with -Coauthor (edit to taste).
$script:WtCoauthorTrailer = 'Co-Authored-By: Claude <noreply@anthropic.com>'

function script:_Wt-Slug([string]$Branch) {
    # feat/foo-bar -> feat-foo-bar ; keep it filesystem-safe and readable
    ($Branch -replace '[/\\]', '-' -replace '[^A-Za-z0-9._-]', '').Trim('-')
}

# ── animal lore: a one-line gloss for the animal in a generated worktree name ─
# Sibling file, resolved off $PSScriptRoot so it travels with the toolkit wherever
# you keep it. $PSCommandPath is captured at dot-source time because it is EMPTY
# inside a called function.
$script:WtSelf     = if ($PSCommandPath) { $PSCommandPath } else { Join-Path $PSScriptRoot 'wt.ps1' }
$script:WtLoreFile = Join-Path $PSScriptRoot 'animal-lore.ps1'
$script:WtLore     = $null

function script:_Wt-Lore {
    # Lazy-load + cache. A missing or broken lore file means NO lore, never an error --
    # this is decoration and must never block cutting or resuming a worktree.
    if ($null -eq $script:WtLore) {
        $script:WtLore = @{}
        if (Test-Path -LiteralPath $script:WtLoreFile) {
            try { $script:WtLore = & $script:WtLoreFile } catch { $script:WtLore = @{} }
        }
    }
    $script:WtLore
}

function script:_Wt-LoreParts($Value) {
    # Entry is '<emoji>','<gloss>'. Tolerate a bare string -> generic paw print.
    # U+1F43E is above U+FFFF, so [char]0x1F43E THROWS -- ConvertFromUtf32 is required.
    if ($Value -is [array] -and $Value.Count -ge 2) { return @($Value[0], $Value[1]) }
    return @([char]::ConvertFromUtf32(0x1F43E), [string]$Value)
}

function script:_Wt-ShowLore([string]$Slug) {
    # "  🐋 minke — Smallest baleen rorqual: fast, curious, often solitary"
    # Silent for hand-named worktrees (release-hotfix): nothing matches, nothing prints.
    $lore = _Wt-Lore
    if (-not $lore.Count) { return }
    foreach ($tok in ($Slug -split '[-_]')) {
        $k = $tok.ToLower()
        if ($lore.ContainsKey($k)) {
            $icon, $text = _Wt-LoreParts $lore[$k]
            Write-Host ("  {0} {1} — {2}" -f $icon, $k, $text) -ForegroundColor DarkCyan
            return
        }
    }
}

function Test-WtAnimalLore {
    # Drift check: every animal in _Wt-FunName needs a gloss, and vice versa. Alias: lore-check
    $src = Get-Content -LiteralPath $script:WtSelf -Raw
    # Needle built at runtime, and NO local named like the array: a literal here would be found
    # by IndexOf first (it sits above the real array) and the scan would parse $words instead.
    $needle = '{0}animals = @(' -f '$'
    $i = $src.IndexOf($needle)
    $declared = @()
    if ($i -ge 0) {
        $j = $src.IndexOf("`n    )", $i)
        $declared = [regex]::Matches($src.Substring($i, $j - $i), "'([a-z]+)'") | ForEach-Object { $_.Groups[1].Value }
    }
    $lore = _Wt-Lore
    $missing = @($declared | Where-Object { -not $lore.ContainsKey($_) })
    $orphan  = @($lore.Keys | Where-Object { $_ -notin $declared })
    $noIcon  = @($lore.Keys | Where-Object { -not ($lore[$_] -is [array] -and $lore[$_].Count -ge 2) })
    Write-Host ("animals: {0}   glosses: {1}" -f $declared.Count, $lore.Count) -ForegroundColor Cyan
    if ($missing) { Write-Host ("  no gloss:  " + ($missing -join ', ')) -ForegroundColor Yellow }
    if ($orphan)  { Write-Host ("  no animal: " + ($orphan  -join ', ')) -ForegroundColor Yellow }
    if ($noIcon)  { Write-Host ("  no icon:   " + ($noIcon  -join ', ')) -ForegroundColor Yellow }
    if (-not $missing -and -not $orphan -and -not $noIcon) { Write-Host "✓ animal-lore.ps1 is in sync" -ForegroundColor Green }
}

# Cross-platform path compare. git emits '/'-separated paths on every OS, while $WtRepo may be set with
# native separators ('\' on Windows, '/' on macOS/Linux). Canonicalize BOTH sides to '/' before comparing
# so the "is this the primary clone?" guards work everywhere (a one-sided '-replace' silently fails off-Windows).
function script:_Wt-NormPath([string]$p) { if ($p) { ($p -replace '\\', '/').TrimEnd('/') } else { '' } }
function script:_Wt-SamePath([string]$a, [string]$b) { [string]::Equals((_Wt-NormPath $a), (_Wt-NormPath $b), 'OrdinalIgnoreCase') }

# ── the best part: silly memorable worktree names ────────────────────────────
function script:_Wt-FunName {
    # Random memorable branch name: <silly-verb/adjective>-<animal>. Re-rolls on collision.
    $words = @(
        'sneaky','wobbly','turbo','sassy','grumpy','sleepy','zesty','spicy','jazzy','bouncy',
        'cranky','dizzy','feral','plucky','rowdy','snazzy','cosmic','funky','groovy','nifty',
        'quirky','rascally','scrappy','waddling','prancing','yeeting','galloping','noodling',
        'vibing','lurking','skulking','moseying','bamboozled','flustered','smug','chonky',
        'derpy','goofy','zoomy','squishy','floofy','snuggly','jaunty','whimsical','kooky','loopy',
        'bonkers','gnarly','peppy','zippy','giddy','cheeky','bumbling','clumsy','squeaky','drowsy',
        'hangry','snacky','toasty','cozy','fluffy','majestic','sparkly','twinkly','chaotic','unhinged',
        'boisterous','mischievous','disheveled','befuddled','discombobulated','rambunctious','meandering',
        'gallivanting','scampering','tumbling','wiggly','jiggly','grouchy','cuddly','wonky','janky',
        'bodacious','gallant','snickering','cackling','kerfuffled','yodeling','honking','scheming',
        'brooding','gloating','frolicking','cavorting','flabbergasted','nefarious','dapper','snoozing',
        'mid','lowkey','rizzy','bussin','sussy','based','goated','delulu','sigma','slaying',
        'drippy','vibey','cheugy','unserious','cracked','iconic','bougie','menacing','nonchalant',
        'radical','tubular','righteous','bogus','heinous','stoked','grody','wicked','fresh','dope',
        # 2026 intake
        'cooked','lockedin','crashingout','aurafarming','yappy','glazed','brainrotted','clankered',
        'chopped','lorepilled','tuff','mogging','npcpilled','unclockable'
    )
    $animals = @(
        'narwhal','quokka','platypus','axolotl','wombat','pangolin','capybara','ocelot','meerkat',
        'lemur','otter','badger','raccoon','ferret','gecko','marmot','tapir','okapi','dingo',
        'koala','sloth','gibbon','mongoose','walrus','puffin','newt','stoat','weasel','kiwi','manatee',
        'alpaca','llama','wallaby','numbat','echidna','aardvark','armadillo','hedgehog','chinchilla',
        'hamster','gerbil','chipmunk','beaver','opossum','skunk','mole','shrew','dormouse','lemming',
        'fennec','jerboa','kinkajou','coati','binturong','serval','caracal','fossa','quoll','bilby',
        'bandicoot','cassowary','kakapo','toucan','hornbill','lorikeet','cockatoo','salamander','tortoise',
        'terrapin','chameleon','iguana','skink','komodo','pufferfish','cuttlefish','seahorse','blobfish',
        'tardigrade','mantis','snail','tanuki','capuchin','tamarin','marmoset','wolverine','pudu','tenrec',
        'kookaburra','shoebill','dodo','hoopoe','nudibranch','nautilus','isopod','earwig',
        'dugong','saiga','markhor','gelada','babirusa','vaquita','sifaka','indri','galago','loris',
        'pika','viscacha','degu','agouti','paca','nutria','genet','marten','dhole','civet',
        'pademelon','potoroo','bettong','cuscus','colugo','hyrax','sengi','manul','mara','springhare',
        'zorilla','ratel','margay','jaguarundi','moonrat','solenodon','desman','olm','hellbender','mudpuppy',
        'mudskipper','wobbegong','coelacanth','oarfish','anglerfish','lumpsucker','hagfish','arapaima','snakehead',
        'potoo','frogmouth','hoatzin','kea','weka','takahe','kagu','motmot','turaco','quetzal',
        'dovekie','avocet','lapwing','whimbrel','velvetworm','seapig','coconutcrab','yeticrab','springtail',
        'glowworm','katydid','treehopper','dobsonfly',
        'orca','beluga','boto','porpoise','minke','humpback','dolphin','luwak',
        'boobook','morepork','sawwhet','scops','elfowl','barnowl','fishowl'
    )
    for ($i = 0; $i -lt 12; $i++) {
        $name = '{0}-{1}' -f (Get-Random -InputObject $words), (Get-Random -InputObject $animals)
        $dirTaken = Test-Path (Join-Path $script:WtHome $name)
        $branchTaken = git -C $script:WtRepo rev-parse --verify --quiet "refs/heads/$name" 2>$null
        if (-not $dirTaken -and -not $branchTaken) { return $name }
    }
    # extremely unlucky — add a short suffix so it can't collide
    '{0}-{1}-{2:x3}' -f (Get-Random -InputObject $words), (Get-Random -InputObject $animals), (Get-Random -Maximum 4095)
}

function script:_Wt-KebabBranch([string]$Raw) {
    # Free-text -> a clean branch name. Empty -> a random verb-animal name.
    # "Fix the parser!" -> "fix-the-parser" ; "feat/Fix parser" -> "feat/fix-parser" ; "" -> "feral-axolotl"
    $t = ($Raw ?? '').Trim()
    if (-not $t) { return (_Wt-FunName) }
    $t = $t.ToLower() -replace '[^a-z0-9/]+', '-' -replace '-{2,}', '-'
    $t = $t.Trim('-/')
    if (-not $t) { return (_Wt-FunName) }
    return $t
}

function script:_Wt-EnsureRepo {
    if (-not (Test-Path (Join-Path $script:WtRepo '.git'))) {
        throw "Primary clone not found at '$script:WtRepo' — set `$script:WtRepo in wt.ps1 (or the WT_REPO env var)."
    }
    if (-not (Test-Path $script:WtHome)) { New-Item -ItemType Directory -Path $script:WtHome -Force | Out-Null }
}

# Non-destructive "is this directory held by a live process (a session cwd'd here)?" probe.
# Opens the dir with share=NONE; any other open handle (a running session's cwd) => sharing violation.
# Opens + closes only — nothing is modified. This is the ONE safe piece worth salvaging from a heavier
# reaper: it's how swt/rwt avoid reporting or removing a worktree a live session is sitting in.
# Windows-only (Windows handle semantics); a no-op elsewhere. The native type compiles lazily on first
# use, so dot-sourcing this file into your $PROFILE stays cheap (no per-shell Add-Type cost).
function script:_Wt-DirInUse([string]$Path) {
    if (-not $IsWindows) { return $false }                 # handle probe is Windows-only; other signals still apply
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    if (-not ([System.Management.Automation.PSTypeName]'WtDirProbe').Type) {
        Add-Type @"
using System; using System.Runtime.InteropServices;
public static class WtDirProbe {
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern IntPtr CreateFileW(string name, uint access, uint share, IntPtr sec, uint disp, uint flags, IntPtr tmpl);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr h);
}
"@
    }
    $DELETE = 0x00010000; $SHARE_NONE = 0; $OPEN_EXISTING = 3; $BACKUP = 0x02000000
    $h = [WtDirProbe]::CreateFileW($Path, $DELETE, $SHARE_NONE, [IntPtr]::Zero, $OPEN_EXISTING, $BACKUP, [IntPtr]::Zero)
    if ($h -eq [IntPtr](-1)) { return $true }              # sharing/access violation => held by a live session
    [WtDirProbe]::CloseHandle($h) | Out-Null
    return $false
}

function script:_Wt-CommitHere([string]$Message, [switch]$Coauthor) {
    # Stage-all + commit in the current worktree. Guards: must be a worktree on a non-base branch, never
    # the primary clone. Runs hooks (no --no-verify). Returns $true if it committed, $false if clean.
    $path = (Get-Location).Path
    $branch = git -C $path rev-parse --abbrev-ref HEAD 2>$null
    if (-not $branch)                                  { throw "Not inside a git worktree." }
    if (_Wt-SamePath $path $script:WtRepo)             { throw "Refusing to commit in the PRIMARY clone." }
    if ($branch -eq $script:WtBase)                    { throw "You're on $script:WtBase — never commit to base. Cut a worktree with nwt." }
    $state = _Wt-WorktreeDirty $path
    if (-not $state.Ran)                               { throw "Could not read the working tree state of $path — refusing to commit blind." }
    if (-not $state.Dirty) { Write-Host "✓ nothing to commit — working tree clean" -ForegroundColor DarkGray; return $false }
    if (-not $Message)                                 { throw "A commit message is required, e.g.  cwt ""fix the parser""" }
    git -C $path add -A
    if ($LASTEXITCODE -ne 0) { throw "git add -A failed — nothing was staged, so the commit below would have been empty or partial." }
    $full = if ($Coauthor) { "$Message`n`n$script:WtCoauthorTrailer" } else { $Message }
    git -C $path commit -m $full
    if ($LASTEXITCODE -ne 0) { throw "git commit failed (a pre-commit hook may have rejected it) — nothing committed." }
    Write-Host "✓ committed on $branch$(if ($Coauthor) { ' (+ co-author trailer)' })" -ForegroundColor Green
    return $true
}

function Commit-InvestWorktree {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments)][string[]]$Message,
        [switch]$Coauthor
    )
    $ErrorActionPreference = 'Continue'
    [void](_Wt-CommitHere ($Message -join ' ') -Coauthor:$Coauthor)
}

function New-InvestWorktree {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments)][string[]]$Name,
        [string]$Base = $script:WtBase,
        [switch]$Launch   # start `claude` in the new worktree
    )
    $ErrorActionPreference = 'Continue'
    _Wt-EnsureRepo
    $Branch = _Wt-KebabBranch ($Name -join ' ')
    Write-Host "→ fetching origin (prune)…" -ForegroundColor DarkGray
    git -C $script:WtRepo fetch origin --prune --quiet
    if ($LASTEXITCODE -ne 0) { Write-Warning "git fetch failed (offline?) — proceeding against your last-fetched origin/$Base, which may be stale." }
    git -C $script:WtRepo worktree prune

    $slug = _Wt-Slug $Branch
    $path = Join-Path $script:WtHome $slug

    $existing = (git -C $script:WtRepo worktree list --porcelain) -match "^worktree .*[/\\]$([regex]::Escape($slug))$"
    if ($existing) {
        Write-Host "✓ worktree already exists — switching to it" -ForegroundColor Green
    }
    elseif (Test-Path $path) {
        throw "$path exists but is not a registered worktree — remove it or pick another branch name"
    }
    else {
        $localRef  = git -C $script:WtRepo rev-parse --verify --quiet "refs/heads/$Branch"
        $remoteRef = git -C $script:WtRepo rev-parse --verify --quiet "refs/remotes/origin/$Branch"
        if ($localRef -or $remoteRef) {
            Write-Host "→ branch '$Branch' already exists — checking it out into a worktree" -ForegroundColor DarkGray
            git -C $script:WtRepo worktree add -q "$path" "$Branch"
        } else {
            Write-Host "→ creating '$Branch' off origin/$Base" -ForegroundColor DarkGray
            git -C $script:WtRepo worktree add -q "$path" -b "$Branch" "origin/$Base"
        }
        if ($LASTEXITCODE -ne 0) { throw "git worktree add failed" }
    }

    Set-Location $path
    Write-Host "✓ now in $path on '$Branch'" -ForegroundColor Green
    _Wt-ShowLore $slug

    if ($Launch) {
        # Open a fresh Claude Code session rooted in the new worktree.
        #
        # CC-specific gotcha worth keeping: when you launch `claude` from INSIDE an existing session,
        # that parent leaks subprocess markers into the environment — CLAUDE_CODE_CHILD_SESSION=1
        # (which DISABLES transcript persistence for the child), a stale CLAUDE_CODE_SESSION_ID /
        # CLAUDE_PID, and NO_COLOR=1 (renders the new session all-white). Start-Process inherits the
        # current env, so we strip these before launching and restore them for this shell afterward,
        # making the launched session indistinguishable from a hand-run `claude`.
        $stripVars = 'CLAUDE_CODE_CHILD_SESSION', 'CLAUDE_CODE_SESSION_ID', 'CLAUDE_PID', 'NO_COLOR'
        $saved = @{}
        foreach ($v in $stripVars) {
            $saved[$v] = [Environment]::GetEnvironmentVariable($v)
            Remove-Item "Env:\$v" -ErrorAction SilentlyContinue
        }
        try {
            # Prefer a dedicated new Windows Terminal window titled with the branch; fall back to a
            # bare `claude` if wt.exe isn't installed (non-Windows-Terminal / other OS shells).
            if (Get-Command wt.exe -ErrorAction SilentlyContinue) {
                Start-Process wt.exe -ArgumentList @('-w', 'new', 'nt', '--title', "$Branch", '-d', "$path", 'claude')
            } else {
                Start-Process claude -WorkingDirectory $path
            }
        } finally {
            foreach ($v in $stripVars) {
                if ($null -ne $saved[$v]) { Set-Item "Env:\$v" -Value $saved[$v] }
            }
        }
        Write-Host "✓ launching a Claude Code session there…" -ForegroundColor Green
    }
}

function Get-InvestWorktrees {
    _Wt-EnsureRepo
    git -C $script:WtRepo worktree prune
    $lines = git -C $script:WtRepo worktree list --porcelain
    $wt = $null; $rows = @()
    foreach ($l in $lines) {
        if ($l -like 'worktree *') { $wt = @{ Path = $l.Substring(9) } }
        elseif ($l -like 'branch *') { $wt.Branch = ($l.Substring(7) -replace '^refs/heads/', '') }
        elseif ($l -eq '' -and $wt) {
            $st = _Wt-WorktreeDirty $wt.Path
            $dirty = if (-not $st.Ran) { 'UNREADABLE' } elseif ($st.Dirty) { 'dirty' } else { 'clean' }
            $isPrimary = _Wt-SamePath $wt.Path $script:WtRepo
            $rows += [pscustomobject]@{
                Branch = $wt.Branch
                State  = if ($isPrimary) { "$dirty (PRIMARY — don't work here)" } else { $dirty }
                Path   = $wt.Path
            }
            $wt = $null
        }
    }
    $rows | Format-Table -AutoSize
}

function _Wt-WorktreeDirty {
    # "Does this worktree have uncommitted changes?" — the `git status --porcelain` question, asked
    # in ONE place, for exactly the reason _Wt-BranchMerged below exists.
    #
    # Five callers asked it inline and every one of them read FAILURE AS CLEAN: `git status` writes
    # nothing to stdout when it errors, so `-not (git status --porcelain)` is $true whether the tree
    # is clean or the command never ran. The consequences were not symmetric — in Reap-InvestWorktree
    # that answer authorises deleting a worktree whose contents could not be read.
    #
    # Returns @{ Ran; Dirty }. Ran=$false means the question could not be ASKED, and Dirty is then
    # $true: UNKNOWN IS NOT CLEAN, the same way unknown is not merged.
    param([Parameter(Mandatory)][string]$Path)
    $out = @(git -C $Path status --porcelain 2>$null)
    if ($LASTEXITCODE -ne 0) { return @{ Ran = $false; Dirty = $true } }
    return @{ Ran = $true; Dirty = [bool]$out.Count }
}

function _Wt-BranchMerged {
    # "Are this branch's commits in base, by patch-id?" — the `git cherry` question, asked in ONE place.
    #
    # It lives in a function because `swt` and `rwt` used to ask it separately, and they DRIFTED: swt
    # guarded an unresolvable base ref, rwt did not. The same missing ref that made swt throw made rwt
    # read empty output as "nothing unmerged" and force-delete a branch it could not prove had landed —
    # while printing "patch-id-verified". One caller, one answer, one guard.
    #
    # Returns @{ Ran; Merged; Ahead }. Ran=$false means the question could not be ASKED at all, and
    # Merged is then $false: UNKNOWN IS NOT MERGED, because the caller's next move may be a delete.
    param([Parameter(Mandatory)][string]$Branch)
    $base = "origin/$script:WtBase"
    if (-not [bool](git -C $script:WtRepo rev-parse --verify --quiet $base 2>$null)) {
        return @{ Ran = $false; Merged = $false; Ahead = 0 }
    }
    $cherry = @(git -C $script:WtRepo cherry $base $Branch 2>$null)
    if ($LASTEXITCODE -ne 0) { return @{ Ran = $false; Merged = $false; Ahead = 0 } }
    $ahead = @($cherry | Where-Object { $_ -like '+*' })
    return @{ Ran = $true; Merged = ($ahead.Count -eq 0); Ahead = $ahead.Count }
}

function _Wt-BranchIntroducesNothing {
    # "Would a PR from this branch propose anything at all?" — asked before `gh pr create`.
    #
    # THREE-dot, measured from the merge base: the question is what THIS BRANCH'S AUTHOR changed.
    # Two-dot answers a different question and would count every commit base gained meanwhile as a
    # deletion by this branch, so an ordinary branch would look like it reverts other people's work.
    #
    # Returns $true / $false / $null, where $null means the base could not be resolved. Unknown must
    # not trigger a refusal any more than it may authorise a delete — the caller skips the check.
    param([Parameter(Mandatory)][string]$RepoPath, [Parameter(Mandatory)][string]$Branch)
    $base = "origin/$script:WtBase"
    if (-not [bool](git -C $RepoPath rev-parse --verify --quiet $base 2>$null)) { return $null }
    $changed = @(git -C $RepoPath diff --name-only "$base...$Branch" 2>$null)
    if ($LASTEXITCODE -ne 0) { return $null }
    return ($changed.Count -eq 0)
}

function _Wt-BranchSuperseded {
    # "Does this branch still ADD anything to base?" — the question `git cherry` cannot answer.
    #
    # Two steps, and the order is the whole point:
    #   1. THREE-dot `base...branch` — the files THIS BRANCH's author touched, measured from the merge
    #      base. The right question for SCOPE; it ignores files other people changed on base meanwhile.
    #   2. TWO-dot `base..branch` restricted to those paths — do they still differ from base NOW?
    # Empty at step 2 means every file the branch touched already matches base, however it got there —
    # a different PR's squash included. That is precisely the case patch-id structurally cannot see.
    #
    # Scoping to the branch's OWN files is what makes this usable. Comparing ALL paths instead lets a
    # branch that is merely BEHIND on some unrelated shared file report not-superseded forever — and
    # being behind is regression, not contribution, so it is not this question.
    #
    # Still deliberately CONSERVATIVE: empty is sufficient for "superseded", never necessary, and a
    # "yes" only ever ADDS a note to a print-only report — it never moves a tree into REAPABLE.
    param([Parameter(Mandatory)][string]$Branch)
    $base = "origin/$script:WtBase"
    $own = @(git -C $script:WtRepo diff --name-only "$base...$Branch" 2>$null)
    if ($LASTEXITCODE -ne 0) { return $null }   # unresolvable ref — unknown, never a false "yes"
    # Touched nothing since the merge base, so it adds nothing. Guarded explicitly: an empty pathspec
    # in the next call would silently widen the diff back to EVERY path and invert the answer.
    if ($own.Count -eq 0) { return $true }
    $still = @(git -C $script:WtRepo diff --name-only "$base..$Branch" -- $own 2>$null)
    if ($LASTEXITCODE -ne 0) { return $null }
    return ($still.Count -eq 0)
}

function Show-StaleWorktrees {
    # PRINT-ONLY stale-worktree report. Never removes anything — it just tells you which worktrees are
    # safe to reap so you can run `rwt -Branch <name>` on the ones you actually want gone.
    #
    # For each linked worktree (never the primary tree) it reports:
    #   Clean?   working tree has no uncommitted changes
    #   Merged?  patch-id check via `git cherry origin/<base> <branch>` — 0 '+' commits = fully merged.
    #            KNOW WHAT THIS DOES NOT SEE. `git cherry` compares PER-COMMIT patch-ids, and a squash
    #            collapses the branch into ONE commit whose patch is the union of all of them. So it
    #            matches in exactly one case: the branch held a SINGLE commit. A multi-commit branch
    #            squashed as itself, and content squashed into a DIFFERENT PR, are both invisible —
    #            such a branch reports "no" forever though every line of it is already on <base>.
    #            Both fail SAFE for a report — it says "review", never "delete".
    #   Superseded?  The check that covers that blind spot, and the reason it is a separate column
    #            rather than folded into Merged: it answers a DIFFERENT QUESTION. `git cherry` asks
    #            "are this branch's commits in main?"; this asks "does this branch still ADD
    #            anything?" — a file-set comparison scoped to the branch's own files
    #            (see _Wt-BranchSuperseded).
    #            Name the question before trusting either answer; they disagree in both directions.
    #   Idle     days since the branch's last commit.
    #   Verdict  REAPABLE = clean + merged (safe to remove); otherwise a short reason to keep it.
    #            A superseded-but-unmerged tree stays KEEP on purpose. This report only ever ADDS
    #            information; widening what gets deleted is a decision for you, not for a heuristic.
    [CmdletBinding()]
    param(
        [int]$StaleDays = 7,        # a clean+merged tree older than this is flagged; younger ones noted but not urged
        [switch]$All                # also list worktrees that are NOT reapable (default hides clearly-live ones)
    )
    _Wt-EnsureRepo
    git -C $script:WtRepo worktree prune
    Write-Host "→ fetching origin (once)…" -ForegroundColor DarkGray
    git -C $script:WtRepo fetch origin --prune --quiet 2>$null
    # Checked for the same reason as in rwt: the ref guard below catches an ABSENT base, not a STALE
    # one. Every verdict in this report is measured against origin/<base>, so if the fetch failed the
    # whole table is computed against an old snapshot — landed work reads as unmerged.
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "git fetch failed (offline?) — every verdict below is computed against your LAST-FETCHED origin/$script:WtBase and may be stale."
    }
    if (-not (git -C $script:WtRepo rev-parse --verify --quiet "origin/$script:WtBase")) {
        throw "origin/$script:WtBase not found — can't compute merged status."
    }

    $lines = git -C $script:WtRepo worktree list --porcelain
    $wt = $null; $rows = @()
    foreach ($l in $lines) {
        if ($l -like 'worktree *')   { $wt = @{ Path = $l.Substring(9); Locked = $false; Detached = $false } }
        elseif ($l -like 'branch *') { $wt.Branch = ($l.Substring(7) -replace '^refs/heads/', '') }
        elseif ($l -like 'locked*')  { $wt.Locked = $true }
        elseif ($l -like 'detached*'){ $wt.Detached = $true }
        elseif ($l -eq '' -and $wt) {
            if (_Wt-SamePath $wt.Path $script:WtRepo) { $wt = $null; continue }  # skip primary

            $clean  = -not (_Wt-WorktreeDirty $wt.Path).Dirty
            $inUse  = _Wt-DirInUse $wt.Path
            $branch = $wt.Branch
            $merged = $false; $idleDays = $null; $superseded = $null
            $mergeKnown = $true; $ahead = $null
            if ($branch -and -not $wt.Detached) {
                $m = _Wt-BranchMerged $branch
                $merged     = $m.Merged
                # Carry ALL THREE fields. rwt distinguishes "could not measure" from "measured, not
                # merged"; swt used to collapse them and print the positive claim "has commits not in
                # main" about a measurement that never ran. Extracting the helper ended the drift in
                # the predicate — this ends it at the presentation layer.
                $mergeKnown = $m.Ran
                $ahead      = if ($m.Ran) { $m.Ahead } else { $null }
                # Only worth asking when patch-id said "unmerged" — that is exactly where its blind
                # spot lives, and the answer changes what you'd do about the tree.
                if (-not $merged) { $superseded = _Wt-BranchSuperseded $branch }
                $lastEpoch = git -C $wt.Path log -1 --format=%ct 2>$null
                if ($lastEpoch) { $idleDays = [int]([DateTimeOffset]::UtcNow - [DateTimeOffset]::FromUnixTimeSeconds([int64]$lastEpoch)).TotalDays }
            }

            $verdict = if ($wt.Locked)          { 'KEEP  (locked)' }
                       elseif ($wt.Detached)    { 'KEEP  (detached HEAD)' }
                       elseif (-not $clean)     { 'KEEP  (dirty — uncommitted work)' }
                       elseif (-not $mergeKnown) { 'KEEP  (merged status UNKNOWN — could not be measured)' }
                       elseif (-not $merged -and $superseded -eq $true) { 'KEEP? (superseded — its own files all match base; patch-id cannot see it)' }
                       elseif (-not $merged)    { "KEEP  (unmerged — has commits not in $script:WtBase)" }
                       elseif ($inUse)          { 'KEEP  (in use — live session cwd here)' }
                       elseif ($null -ne $idleDays -and $idleDays -lt $StaleDays) { "REAPABLE (recent — idle ${idleDays}d)" }
                       else                     { "REAPABLE$(if($null -ne $idleDays){" (idle ${idleDays}d)"})" }

            $rows += [pscustomobject]@{
                Verdict = $verdict
                Branch  = $branch ?? '(none)'
                Clean   = if ($clean) { 'yes' } else { 'no' }
                # '-' means NOT MEASURED, and is deliberately not 'no'. Same convention in both columns.
                Merged  = if (-not $mergeKnown) { '-' } elseif ($merged) { 'yes' } else { 'no' }
                # Show the number the verdict was computed from, not just the conclusion.
                Ahead   = $ahead
                Superseded = if ($superseded -eq $true) { 'yes' } elseif ($null -eq $superseded) { '-' } else { 'no' }
                InUse   = if ($inUse) { 'yes' } else { 'no' }
                IdleDays = $idleDays
                Path    = $wt.Path
            }
            $wt = $null
        }
    }

    $reapable = @($rows | Where-Object { $_.Verdict -like 'REAPABLE*' })
    $shown = if ($All) { $rows } else { if ($reapable.Count) { $reapable } else { $rows } }

    Write-Host "`n=== stale-worktree report  (print-only — nothing is removed)  base=origin/$script:WtBase ===" -ForegroundColor Cyan
    if (-not $rows.Count) { Write-Host "  No linked worktrees. Nothing to report."; return }
    $shown | Sort-Object @{e={$_.Verdict -notlike 'REAPABLE*'}}, IdleDays -Descending |
        Format-Table Verdict, Branch, Clean, Merged, Ahead, Superseded, InUse, IdleDays, Path -AutoSize

    $sup = @($rows | Where-Object { $_.Superseded -eq 'yes' })
    if ($sup.Count) {
        # State exactly what was measured. "Adds and changes nothing" overclaims: the branch may
        # still hold STALE copies of files it never touched — those are out of scope by construction.
        Write-Host "$($sup.Count) tree(s) report Superseded=yes: every file the branch itself touched now matches origin/$script:WtBase," -ForegroundColor Yellow
        Write-Host "so its own content is already there — typically folded into another PR's squash, which patch-id cannot detect." -ForegroundColor Yellow
        Write-Host "(It may still be BEHIND on files it never touched. That is staleness, not contribution, and is not measured here.)" -ForegroundColor Yellow
        # The confirmation command must REPRODUCE the verdict. An unscoped `diff origin/<base> HEAD`
        # prints a non-empty diffstat for any superseded-but-behind branch, so following it would
        # tell the operator the tool is wrong — a proof that disproves its own finding is worse than
        # none. This is the same two-dot-scoped-to-own-files comparison the verdict came from.
        Write-Host "They are NOT listed as reapable. Reproduce the verdict with:" -ForegroundColor DarkYellow
        Write-Host "  git -C <repo> diff --name-only origin/$script:WtBase..<branch> -- `$(git -C <repo> diff --name-only origin/$script:WtBase...<branch>)   # empty output = superseded" -ForegroundColor DarkYellow
    }

    if ($reapable.Count) {
        Write-Host "$($reapable.Count) worktree(s) are clean + merged into $script:WtBase — safe to remove when you're ready:" -ForegroundColor Yellow
        foreach ($r in $reapable) { Write-Host ("    rwt -Branch {0}" -f $r.Branch) -ForegroundColor DarkYellow }
    } else {
        Write-Host "Nothing is safely reapable right now (all worktrees are dirty, unmerged, locked, or detached)." -ForegroundColor DarkGray
    }
    if (-not $All -and $rows.Count -gt $shown.Count) {
        Write-Host "($($rows.Count - $shown.Count) live/keep worktree(s) hidden — pass -All to see them.)" -ForegroundColor DarkGray
    }
}

function Publish-InvestWorktree {
    [CmdletBinding()]
    param(
        [string]$Title,
        [string]$Message,   # if given, commit staged+unstaged changes with this message before publishing
        [switch]$Coauthor,
        [switch]$AllowEmpty # open a PR even if the branch introduces no change vs base
    )
    $ErrorActionPreference = 'Continue'   # gh pr view exits nonzero when no PR exists — control flow, not an error
    $path = (Get-Location).Path
    $branch = git -C $path rev-parse --abbrev-ref HEAD
    if ($branch -eq $script:WtBase) { throw "You're on $script:WtBase — never publish from base." }
    if ($Message) { [void](_Wt-CommitHere $Message -Coauthor:$Coauthor) }
    $pubState = _Wt-WorktreeDirty $path
    if (-not $pubState.Ran) { throw "Could not read the working tree state of $path — refusing to publish without knowing whether work is uncommitted." }
    if ($pubState.Dirty) { throw "Uncommitted changes — commit first (cwt ""msg""), or pass -Message to commit and publish in one step." }

    # ── refuse to open a PR that proposes nothing ──────────────────────────────────────────────
    # An empty PR is not an error anywhere in the toolchain: it pushes, CI goes green, `gh pr merge`
    # reports MERGED, and nothing lands. Nothing in that sequence reads as alarming, which is why it
    # can repeat for cycles before anyone notices — the tell is several squash commits on base
    # sharing one title, because the title is derived from identical content.
    #
    # Reachable here mainly when the branch's content ALREADY landed: folded into another PR's
    # squash, or the branch was reset onto base after a squash-merge and then re-published.
    #
    # The comparison itself, and why it is three-dot, is in _Wt-BranchIntroducesNothing.
    if (-not $AllowEmpty) {
        # Fetch first: comparing against a stale base is how a branch that DID land still looks new.
        git -C $path fetch origin --quiet 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "git fetch failed (offline?) — the emptiness check below is against your last-fetched origin/$script:WtBase."
        }
        if ((_Wt-BranchIntroducesNothing -RepoPath $path -Branch $branch) -eq $true) {
            throw @"
'$branch' introduces no change versus origin/$script:WtBase — a PR from it would be empty.
An empty PR still pushes, still goes green, and still reports MERGED, having landed nothing.
  Already landed inside another PR's squash?  git log --oneline origin/$script:WtBase | head
  Meant to start fresh from base?             git checkout -B $branch origin/$script:WtBase
  Really want an empty PR?                    pwt -AllowEmpty
"@
        }
        # An unresolvable base is NOT treated as "empty" — _Wt-BranchIntroducesNothing returns $null
        # there, which is not $true, so the check simply does not fire. Unknown must not trigger a
        # refusal any more than it may authorise a delete.
    }

    Write-Host "→ pushing $branch…" -ForegroundColor DarkGray
    git -C $path push -u origin $branch
    if ($LASTEXITCODE -ne 0) {
        throw "push rejected for '$branch'. If the remote diverged (e.g. the branch was reused after a squash-merge), reconcile:`n  git -C '$path' pull --rebase origin $branch`nor, only if you're SURE local is canonical:`n  git -C '$path' push --force-with-lease origin $branch"
    }
    # gh infers the repo from the worktree's origin remote — no repo slug to hardcode.
    Push-Location $path
    try {
        $existing = gh pr view $branch --json number 2>$null
        if ($existing) {
            Write-Host "✓ PR already open for $branch — pushed updates" -ForegroundColor Green
            gh pr view $branch --json number,url --jq '"  #\(.number)  \(.url)"'
        } else {
            $t = if ($Title) { $Title } else { $branch }
            gh pr create --base $script:WtBase --head $branch --title "$t" --fill
            # Unchecked, this reported a successful publish for every failure gh has: a 503 from the
            # GraphQL API, an expired token, a base branch that does not exist on the remote. The
            # push above had already happened, so the tree looked published and no PR existed.
            if ($LASTEXITCODE -ne 0) { throw "gh pr create failed for '$branch' — the branch was pushed, but no PR was opened. Re-run pwt once the cause is fixed." }
        }
    } finally { Pop-Location }
}

function Reap-InvestWorktree {
    # Teardown ONE worktree — safe and synchronous. Removes the worktree and deletes its branch ONLY if
    # that branch is fully merged into origin/<base> (patch-id, which counts a squash only when the branch
    # held ONE commit — a multi-commit squash, or content folded into a different PR, reports unmerged
    # and is kept, which is the safe direction here; `swt` flags it as superseded so you can decide).
    # If origin/<base> cannot be resolved at all, merged status is UNKNOWN and the branch is kept. No merge,
    # no destructive default: -Merge opts into squash-merging the PR first via gh (normal merge — NOT
    # --admin, so branch protection is respected). Flags:
    #   -Merge            squash-merge the branch's PR (push + open one if needed) BEFORE teardown
    #   -Branch <b>       target another worktree by branch/slug instead of the one you're standing in
    #   -DiscardChanges   allow teardown of a DIRTY tree (destroys uncommitted work, incl. untracked)
    #   -EvictLiveSession allow teardown of a tree ANOTHER live session is sitting in
    #   -Force            deprecated: both of the two above at once
    #   -Yes              skip the y/N confirmation
    #
    # -DiscardChanges and -EvictLiveSession were ONE -Force switch. They guard different hazards with
    # different blast radius — losing your own uncommitted work, versus pulling files out from under
    # somebody else's running session — and collapsing them meant the flag you reached for to clear
    # the first silently cleared the second too. `rwt -Force -Yes` was a fully unattended
    # destroy-dirty-tree-held-by-a-live-session. -Force is kept as an alias so nothing breaks.
    [CmdletBinding()]
    param(
        [string]$Branch,
        [switch]$Merge,
        [switch]$Force,
        [switch]$DiscardChanges,
        [switch]$EvictLiveSession,
        [switch]$Yes
    )
    # Resolve the alias once, here, so no downstream check has to remember to consider both.
    $allowDirty  = $DiscardChanges.IsPresent   -or $Force.IsPresent
    $allowEvict  = $EvictLiveSession.IsPresent -or $Force.IsPresent
    $ErrorActionPreference = 'Continue'   # gh/git exit codes here are control flow, not errors
    _Wt-EnsureRepo

    # ── resolve the target worktree path + its branch ──
    if ($Branch) {
        $target = Join-Path $script:WtHome (_Wt-Slug $Branch)
        if (_Wt-SamePath $target $script:WtRepo) { throw "Refusing to reap the PRIMARY clone." }
        if (-not (Test-Path $target)) { throw "No worktree at $target" }
    } else {
        $target = (Get-Location).Path
        if (_Wt-SamePath $target $script:WtRepo) { throw "Refusing to reap the PRIMARY clone (cd into a worktree, or pass -Branch)." }
    }
    $wtBranch = git -C $target rev-parse --abbrev-ref HEAD 2>$null
    if (-not $wtBranch)               { throw "$target is not a git worktree." }
    if ($wtBranch -eq $script:WtBase) { throw "Target is on $script:WtBase — never reap base." }
    # -Branch resolves to a PATH via _Wt-Slug, which is MANY-TO-ONE: `feat/foo`, `feat-foo` and
    # `feat.foo` all slug to `feat-foo`. Everything after this point acts on $wtBranch — the branch
    # actually checked out at that path — so a near-miss name would remove one worktree and delete a
    # different branch than the one you named. Resolve on the identity, not on the derived key.
    if ($Branch -and $wtBranch -ne $Branch) {
        throw "Refusing to reap: -Branch '$Branch' resolves to $target, which is on '$wtBranch'. Re-run with -Branch '$wtBranch' if that is what you meant."
    }

    # Read inline rather than through _Wt-WorktreeDirty because the LINES are needed below, to name
    # what would be lost. The guard is the helper's, and it matters most here: this is the caller
    # whose next move is a delete, and an unread tree must never present as clean.
    $status = @(git -C $target status --porcelain 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "Could not read the working tree state of $target — refusing to reap a worktree whose contents cannot be listed." }
    $dirty  = [bool]$status.Count
    if ($dirty -and -not $allowDirty) {
        # NAME WHAT WOULD BE LOST. "has uncommitted changes" is true and useless: it does not tell you
        # whether that is one stray build artifact or the only copy of something.
        #
        # Untracked files matter most here. A /handoff writes HANDOFF.md, which is gitignored ON
        # PURPOSE and therefore exists ONLY in this tree — it dies with it and is in no reflog. It
        # also makes the tree read "dirty", so -DiscardChanges is exactly the flag someone reaches
        # for at the moment it is about to be destroyed.
        $untracked = @($status | Where-Object { $_ -like '??*' } | ForEach-Object { $_.Substring(3) })
        $tracked   = @($status | Where-Object { $_ -notlike '??*' }).Count
        $lines = @("$target has uncommitted changes and will NOT be reaped.")
        if ($tracked)          { $lines += "  $tracked tracked file(s) modified — recoverable only if you commit (cwt ""msg"") or stash." }
        if ($untracked.Count)  {
            $lines += "  $($untracked.Count) UNTRACKED file(s) — these exist nowhere else and are in no reflog:"
            $lines += ($untracked | Select-Object -First 10 | ForEach-Object { "    $_" })
            if ($untracked.Count -gt 10) { $lines += "    … and $($untracked.Count - 10) more" }
            $handoff = @($untracked | Where-Object { $_ -match 'HANDOFF' })
            if ($handoff.Count) {
                $lines += "  ! $($handoff -join ', ') looks like a session handoff. It is gitignored by design, so reaping this tree DELETES it."
                $lines += "    Resume the tree instead, or copy it somewhere tracked first."
            }
        }
        $lines += "  Pass -DiscardChanges to destroy the above."
        throw ($lines -join "`n")
    }

    # ── optional: squash-merge the PR first (normal merge, respects branch protection) ──
    $mergedViaPr = $false
    if ($Merge) {
        if ($dirty) { throw "Can't merge a dirty tree — commit first, or drop -Merge to just tear down." }
        Push-Location $target
        try {
            $pr = gh pr view $wtBranch --json number,url,state 2>$null | ConvertFrom-Json
            if (-not $pr) {
                Write-Host "→ no PR yet — pushing + opening one…" -ForegroundColor DarkGray
                git -C $target push -u origin $wtBranch
                if ($LASTEXITCODE -ne 0) { throw "push failed for '$wtBranch' — reconcile, or drop -Merge." }
                gh pr create --base $script:WtBase --head $wtBranch --fill
                $pr = gh pr view $wtBranch --json number,url,state 2>$null | ConvertFrom-Json
                if (-not $pr) { throw "PR creation failed — reconcile, or drop -Merge." }
            }
            if (-not $Yes) {
                Write-Host "About to squash-merge PR #$($pr.number) ($wtBranch → $script:WtBase), then reap worktree $target." -ForegroundColor Yellow
                $ans = Read-Host "Proceed? (y/N)"
                if ($ans -notmatch '^[Yy]') { Write-Host "Aborted."; return }
            }
            # DELIBERATELY not checking $LASTEXITCODE on the merge: `gh pr merge` exits 1 while
            # SUCCEEDING when base is checked out in a sibling worktree — it fails at the local git
            # step, after the API-side merge has already landed. The exit code answers the wrong
            # question, so the verdict below is taken from the PR's state instead.
            gh pr merge $pr.number --squash --delete-branch
            $state = gh pr view $pr.number --json state --jq '.state'
            # ...which makes THIS call load-bearing. Unchecked, a failed read left $state empty and
            # the throw below read "state=" — an unreadable PR and an unmerged one are different
            # facts and must not share a message.
            if ($LASTEXITCODE -ne 0) { throw "Could not read the state of PR #$($pr.number) after merging — nothing reaped. Check the PR by hand before re-running; it may well have merged." }
            if ($state -ne 'MERGED') { throw "PR #$($pr.number) did not merge (state=$state) — nothing reaped. (Branch protection? Merge it in the UI, then rerun rwt without -Merge.)" }
            Write-Host "✓ PR #$($pr.number) merged." -ForegroundColor Green
            $mergedViaPr = $true
        } finally { Pop-Location }
    }

    # ── decide whether the branch is safe to delete (fully merged into origin/<base>, patch-id checked) ──
    git -C $script:WtRepo fetch origin --prune --quiet 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "git fetch failed (offline?) — merged-ness is being computed against your LAST-FETCHED origin/$script:WtBase, which may be stale. A stale base makes landed work look unmerged, so this errs toward keeping the branch."
    }
    # _Wt-BranchMerged carries the base-ref guard, so an unresolvable origin/<base> (a renamed
    # default branch, a WT_BASE typo, no origin at all, a clone that never fetched) can no longer
    # read as "nothing unmerged" and force-delete a branch that never landed. Unknown is not merged.
    #
    # A FAILED FETCH IS A DIFFERENT CASE and the guard above does NOT catch it: on any repo that has
    # ever fetched, origin/<base> still resolves, just staler. That is why the fetch is checked
    # separately here. A stale base makes landed work look unmerged, so it errs toward KEEPING the
    # branch — which is also why nobody investigates it.
    $m = _Wt-BranchMerged $wtBranch
    $cherryRan = $m.Ran
    $ahead = $m.Ahead
    if (-not $cherryRan) {
        Write-Host "  ! origin/$script:WtBase did not resolve — merged status UNKNOWN, so the branch will be KEPT." -ForegroundColor Yellow
    }
    # A just-completed -Merge is authoritative: a multi-commit squash is patch-unique, so `git cherry`
    # would wrongly report it unmerged and strand the local branch. Otherwise trust the cherry check —
    # but only when it actually RAN. An empty result from a command that failed is not proof of merge.
    $merged = $mergedViaPr -or $m.Merged

    # -Merge already prompted for the whole merge+reap up front; only confirm here when it didn't.
    if (-not $Yes -and -not $Merge) {
        $what = if ($merged)          { "remove worktree $target and DELETE the (merged) branch '$wtBranch'" }
                elseif (-not $cherryRan) { "remove worktree $target and KEEP the branch '$wtBranch' (merged status UNKNOWN — origin/$script:WtBase did not resolve)" }
                else                  { "remove worktree $target and KEEP the branch '$wtBranch' ($ahead commit(s) not in $script:WtBase)" }
        Write-Host "About to $what." -ForegroundColor Yellow
        $ans = Read-Host "Proceed? (y/N)"
        if ($ans -notmatch '^[Yy]') { Write-Host "Aborted."; return }
    }

    # ── teardown: step out if we're inside the target, de-register, delete files ──
    $inside = (_Wt-NormPath (Get-Location).Path).StartsWith((_Wt-NormPath $target), 'OrdinalIgnoreCase')
    if ($inside) { Set-Location $script:WtHome }
    # Refuse to yank a worktree out from under ANOTHER live session. The Set-Location above releases THIS
    # session's own handle, so anything still holding the dir is a different, live process. -Force overrides.
    if ((_Wt-DirInUse $target) -and -not $allowEvict) {
        throw "$target is open in another session (a live process is cwd'd there). Close that window first, or pass -EvictLiveSession to remove anyway."
    }
    git -C $script:WtRepo worktree remove "$target" 2>$null
    if ($LASTEXITCODE -ne 0 -or (Test-Path $target)) { git -C $script:WtRepo worktree remove --force "$target" 2>$null }
    git -C $script:WtRepo worktree prune
    # VERIFY the removal rather than assuming it. A LOCKED worktree requires --force TWICE, so the
    # single --force above leaves it registered and `prune` will not clear it either — and the old
    # closing message told the user to "close the window and it clears", which for a locked tree
    # diagnoses the wrong cause and promises a state that will never arrive.
    $stillRegistered = [bool](@(git -C $script:WtRepo worktree list --porcelain 2>$null |
        Where-Object { $_ -like 'worktree *' } |
        Where-Object { _Wt-SamePath ($_ -replace '^worktree\s+','') $target }).Count)

    if ($merged) {
        $tip = git -C $script:WtRepo rev-parse $wtBranch 2>$null
        $del = git -C $script:WtRepo branch -d $wtBranch 2>&1
        if ($LASTEXITCODE -ne 0) {
            # `branch -d` also refuses for reasons that have nothing to do with merge state — the
            # branch is checked out in another worktree, or gh's --delete-branch already removed it.
            # So force, and then CHECK. The previous version piped -D to Out-Null and printed
            # "force-deleted" unconditionally: the same unverified-claim defect this function was
            # just fixed for, three statements away from the fix.
            $forced = git -C $script:WtRepo branch -D $wtBranch 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "  ! branch '$wtBranch' could NOT be deleted and is still present: $forced" -ForegroundColor Yellow
            } else {
                # NAME WHICH PROOF — after a -Merge it was the PR's MERGED state, not patch-id
                # (cherry reports a multi-commit squash as unmerged, which is why -Merge overrides it).
                $proof   = if ($mergedViaPr) { 'PR merged' } else { 'patch-id-verified' }
                # $tip is empty if the ref was already gone; don't hand out a restore command that
                # cannot work.
                $restore = if ($tip) { " Restore if needed: git branch $wtBranch $tip" } else { '' }
                Write-Host "  branch force-deleted (merged; $proof).$restore" -ForegroundColor DarkGray
            }
        } else { Write-Host "  $del" -ForegroundColor DarkGray }
    } elseif (-not $cherryRan) {
        Write-Host "  branch '$wtBranch' kept (merged status could not be determined). Delete it yourself once you've confirmed it landed." -ForegroundColor DarkGray
    } else {
        Write-Host "  branch '$wtBranch' kept (not fully in $script:WtBase). Delete it yourself once it lands." -ForegroundColor DarkGray
    }

    if ($stillRegistered) {
        # Not a cleanup that merely needs a window closed — the worktree is STILL REGISTERED. The
        # usual cause is a `git worktree lock` (lock-for-keep), which needs --force twice to defeat
        # and which this edition deliberately will not do for you.
        Write-Host "! NOT reaped — $target is still a registered worktree. If it is locked (lock-for-keep), that is git refusing on purpose: git worktree unlock `"$target`" first." -ForegroundColor Yellow
    } elseif (Test-Path $target) {
        # De-registered, but the folder is still held — you ran rwt from inside the tree, or another
        # shell is cwd'd here. No background killer in this edition: close that window and the folder
        # frees up. (Windows holds a cwd handle open.)
        Write-Host "✓ reaped$(if($merged){' (merged)'}). The folder is still open in a window — close it and it clears." -ForegroundColor Green
    } else {
        Write-Host "✓ reaped$(if($merged){' (merged)'}), worktree removed, base refreshed. You're clean." -ForegroundColor Green
    }
}

Set-Alias nwt New-InvestWorktree    -Scope Global
Set-Alias cwt Commit-InvestWorktree -Scope Global
Set-Alias lwt Get-InvestWorktrees   -Scope Global
Set-Alias pwt Publish-InvestWorktree -Scope Global
Set-Alias swt Show-StaleWorktrees   -Scope Global
Set-Alias lore-check Test-WtAnimalLore -Scope Global   # animal list <-> animal-lore.ps1 drift check
Set-Alias rwt Reap-InvestWorktree   -Scope Global
