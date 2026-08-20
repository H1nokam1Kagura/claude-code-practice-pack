#requires -Version 7
<#
.SYNOPSIS
    Install the practice firing layer into a recipient's Claude Code configuration -- an always-on
    CLAUDE.md fragment, the practice skills, and a permission floor plus PreToolUse hook.

.DESCRIPTION
    This is the riskiest script in the pack, and the reason is one dated fact: a Claude Code
    settings file that fails validation is rejected WHOLE. A malformed write does not degrade the
    recipient's configuration by one bad rule -- it turns the whole file off. So the ordinary
    installer shape (open, edit, save, print "done") is not available here. Every write to
    settings.json goes temp file -> parse and shape-validate -> back up the original -> swap ->
    read back and re-parse, and any failure in that sequence restores the backup and says so by
    name.

    WHY THIS GOES FURTHER THAN THE SIBLING INSTALLERS, AND WHAT IT OWES THEM

      claude-memory-toolkit/install.py copies its files and PRINTS the settings.json snippet for the
      user to merge. That is the conservative precedent and it is the right default: it cannot
      break anything. An active install was chosen here deliberately -- a firing layer that arrives
      as a paragraph of instructions is a firing layer most recipients never wire up -- so this
      script has to be correspondingly safer, not merely bolder. Everything below is that debt.

      claude-worktree-toolkit/Install.ps1 is the house pattern reused here: a managed block with
      begin/end markers, a timestamped backup, WriteAllText plus a read-back compare, and the
      single-quote escaping fix. Read its comment: a path containing an apostrophe is legal on
      Windows, and unescaped it wrote a $PROFILE that would not parse -- a shell that will not
      start, from an installer that reported success.

      THAT LESSON ARRIVES HERE IN A DIFFERENT SUBSTRATE, and the fix is not the same one. JSON does
      not care about apostrophes, so the profile escape is not what is needed. The place a path
      becomes shell syntax is the hook COMMAND: Claude Code hands that string to a shell, and
      `pwsh -NoProfile -File C:/Users/O'Brien/.claude/hooks/secret-guard.ps1` opens a quote that is
      never closed, in bash and in PowerShell alike. So the guard path is always emitted
      DOUBLE-quoted, which also covers spaces, and a double quote cannot be in a Windows path so
      the quoting character is safe by construction. Two characters remain hostile inside double
      quotes -- `$` (PowerShell and POSIX expansion) and a backtick (PowerShell escape) -- and both
      are legal in a Windows path. Those are REFUSED at pre-flight with the remedy named, rather
      than escaped for a shell this script cannot identify: the hook shell is not knowable from
      here, and a wrongly-escaped hook fails silently, which is the failure class this file exists
      to avoid.

    JSON HAS NO COMMENT MARKERS, so the managed-block trick cannot mark what this script owns
    inside settings.json. That is what the INSTALL MANIFEST is for
    (<ClaudeHome>/.practice-layer-install.json): it records the exact deny entries, ask entries,
    hook entries and file paths that were added, each file's hash, any backup taken, plus the
    source commit and the install time. -Uninstall removes precisely those and nothing else.
    Without a manifest an uninstall has only two options, and both are wrong: subtract the floor
    template, which eats any rule the recipient wrote that happens to also be in it; or subtract
    nothing, and leave the layer behind while reporting removal.

    UNION-MERGE, NEVER REPLACE. permissions.deny and permissions.ask are merged as sets, and only
    the entries that were NOT already there are recorded as ours. That is what makes uninstall
    correct rather than approximate: an entry the recipient already had is not in the manifest, so
    uninstall cannot take it away. The converse limit is real and is stated rather than hidden -- if
    the recipient independently adds an entry this script had already installed, the two are
    indistinguishable strings and uninstall will remove it.

    permissions.allow IS NOT TOUCHED, on purpose. Every other list here tightens; allow is the only
    one that GRANTS, and a floor that grants is not a floor. The template it comes from ships an
    empty allow list for the same reason.

    NOR IS settings.local.json, NOR defaultMode, NOR any other key. This script adds to
    permissions.deny, permissions.ask and hooks.PreToolUse in settings.json, and writes the fragment
    and the skills; it reads everything else and puts it back byte-for-byte in its original key order.
    defaultMode in particular is left alone deliberately: the floor is what makes a permissive mode
    survivable, so that choice belongs to whoever has replayed their own traffic -- which is the
    argument the floor template makes for omitting it, and inheriting it from an installer would be
    worse than inheriting it from a stranger's config.

    ALREADY-UNPARSEABLE settings.json IS REFUSED, NOT REPAIRED. A file that does not parse is
    already fully off, so there is nothing to protect by pressing on -- and a repair is a guess
    about intent written into the one file the recipient cannot afford a guess in. The script says
    which file, which parse error, and stops with the original bytes untouched.

    WHAT IS NOT DUPLICATED HERE, and why there is no settings.floor.json beside this script: the
    floor is READ OUT of claude-permission-toolkit/settings.template.json, which is the artifact
    that already has a test suite holding it to being a floor (test_template_floor.py, in both
    polarities). A second copy would be a fork the moment either moved, and nothing would be
    comparing them. The tradeoff is that this installer FAILS when the template is missing or
    reshaped, rather than falling back to a remembered list -- the loud direction, and the same
    choice Build-SharePack.ps1 makes when it parses the exclusion pattern out of the content gate.

    THE FRAGMENT AND THE SKILLS ARE DISCOVERED, NEVER ASSUMED. They are authored separately from
    this script, so their exact names are not a fact this file may hold. The fragment is found by
    pattern in the layer directory and the skills by walking skills/*/SKILL.md; an absent or
    ambiguous result is a clear failure naming what was looked for and where, never a silent
    install of the half that was present.

.PARAMETER ClaudeHome
    The configuration directory to install into. Default: ~/.claude. Pass a throwaway directory to
    rehearse against something that is not the live configuration -- which is the only way this
    script is ever tested, and -SelfTest refuses to use the default at all.

.PARAMETER LayerRoot
    Directory holding the fragment and skills/. Default: the directory this script lives in.

.PARAMETER FragmentPath
    The CLAUDE.md fragment, when discovery cannot or should not choose. Default: discovered.

.PARAMETER SkillsRoot
    Directory of skill directories. Default: skills/ under -LayerRoot.

.PARAMETER FloorTemplate
    The permission floor. Default: ../claude-permission-toolkit/settings.template.json. Not copied
    into this directory, on purpose -- see the DESCRIPTION.

.PARAMETER GuardScript
    The PreToolUse hook to install. Default: ../claude-permission-toolkit/secret-guard.ps1.

.PARAMETER HooksDir
    Where the guard is installed and where the hook command points. Default: hooks/ under
    -ClaudeHome. The escape hatch for a home directory containing a character that is hostile
    inside a shell double-quoted string.

.PARAMETER SourceCommit
    Assert the source commit for the manifest instead of asking git, for installing from an export
    that has no .git.

.PARAMETER Uninstall
    Remove exactly what the manifest records, and decline anything that has been modified since.
    Combines with -DryRun.

.PARAMETER DryRun
    Print the exact diff that would be applied and write nothing at all. Honoured by the write path
    itself, not narrated over a real install. Exits 2.

.PARAMETER Force
    Authorise overwriting a file at a target path that this script did not install and whose content
    differs. The original is backed up first either way; without -Force the install FAILS and names
    the path. It does not authorise anything about settings.json, whose merge never overwrites.

.PARAMETER FaultInject
    Deliberately break one step, to prove the restore path runs. A recovery path that is never
    exercised is a comment. REFUSED unless -ClaudeHome was passed explicitly and resolves somewhere
    other than the default, so it cannot be aimed at a live configuration.

.PARAMETER SelfTest
    Run the negative controls in a temp directory and exit. Never touches -ClaudeHome.

.EXAMPLE
    pwsh -NoProfile -File tools/claude-practice-layer/Install-PracticeLayer.ps1 -DryRun

.EXAMPLE
    pwsh -NoProfile -File tools/claude-practice-layer/Install-PracticeLayer.ps1

.EXAMPLE
    pwsh -NoProfile -File tools/claude-practice-layer/Install-PracticeLayer.ps1 -Uninstall -DryRun

.EXAMPLE
    pwsh -NoProfile -File tools/claude-practice-layer/Install-PracticeLayer.ps1 -SelfTest

.NOTES
    EXIT CONTRACT -- the same one every gate and the builder in this pack use, deliberately, so an
    installer cannot invent a softer vocabulary than the gates that judge the pack it ships in:
      0  installed (or uninstalled) and verified
      1  FAILED, or a step measured nothing (INCONCLUSIVE), or the environment could not be resolved
      2  -DryRun, or a step deliberately not done, or an uninstall that DECLINED to touch something
         the recipient has since modified -- SKIPPED, never a pass

    A DECLINE MAPS TO 2, and that is a decision worth stating. It is not a failure: declining to
    revert somebody's edit is the script working. It is not a pass either: the layer is still
    partly installed and the manifest is deliberately left behind so a second uninstall can finish
    the job once the recipient has looked. 2 is the code that already means "deliberately not done".

    ps1-safety: $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest. WRITES OUTSIDE THE
    REPOSITORY BY DESIGN -- that is what it is for -- and every one of those writes is inside
    -ClaudeHome, guarded by an existence check, and backed up first if it overwrites something this
    script did not create. -SelfTest and -DryRun write nothing there at all.

    Files are written with [System.IO.File]::WriteAllText and never with Set-Content: Set-Content
    supports ShouldProcess, so under -WhatIf it writes NOTHING while the success message still
    prints -- an installer reporting success having done nothing. The same argument retires three
    more cmdlets here: directories are created with [System.IO.Directory]::CreateDirectory rather
    than New-Item, and deletions in -Uninstall go through [System.IO.File]::Delete and
    [System.IO.Directory]::Delete rather than Remove-Item. All three of those cmdlets support
    ShouldProcess too, and an installer whose deletions can be silently no-opped by an inherited
    preference is the same bug wearing a different verb.

    No ShouldProcess is declared anywhere in this file, for that reason. -DryRun is the substitute
    and it is a real branch: nothing under -ClaudeHome is created, written or deleted on that path.

    No network. No secrets read or echoed. Tolerates CRLF, since CI checks out on windows-latest.
    Idempotent: two installs of one source converge on one state, and the second adds no duplicate
    permission entry, no second managed block and no second hook.
#>
[CmdletBinding()]
param(
    [string]$ClaudeHome,
    [string]$LayerRoot,
    [string]$FragmentPath,
    [string]$SkillsRoot,
    [string]$FloorTemplate,
    [string]$GuardScript,
    [string]$HooksDir,
    [string]$SourceCommit,
    [switch]$Uninstall,
    [switch]$DryRun,
    [switch]$Force,
    [ValidateSet('SettingsTempInvalid', 'SettingsSwap', 'SettingsReadback')]
    [string]$FaultInject,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ── OUTCOME VOCABULARY ──────────────────────────────────────────────────────────
# PASS / FAIL / INCONCLUSIVE / SKIPPED. A FIFTH copy of the vocabulary the three gates and the
# builder share, and a fifth copy is a fork unless something compares them. What compares this one
# is Test-ScriptQuality.ps1 and the local-CI runner: they read exit codes, and 2 means the same
# thing in all five files. A divergence here surfaces as a pipeline reporting the wrong colour for
# an installer, not as a quiet pass.

class InstallStep {
    [string]$Name
    [string]$Status
    [int]$Count
    [System.Collections.Generic.List[string]]$Findings
    [string]$Note

    InstallStep([string]$name) {
        $this.Name = $name
        $this.Status = 'PASS'
        $this.Count = 0
        $this.Findings = [System.Collections.Generic.List[string]]::new()
        $this.Note = ''
    }

    [void] Fail([string]$msg) {
        $this.Findings.Add($msg)
        $this.Status = 'FAIL'
    }

    # DECLINED is recorded as SKIPPED with the reason on the finding line. It must not become FAIL:
    # refusing to revert somebody's edit is the correct behaviour, and colouring it red trains the
    # recipient to reach for a flag that overrides it.
    [void] Decline([string]$msg) {
        $this.Findings.Add("DECLINED -- $msg")
        if ($this.Status -eq 'PASS') { $this.Status = 'SKIPPED' }
    }

    [void] Skip([string]$why) {
        if ($this.Status -eq 'PASS') { $this.Status = 'SKIPPED' }
        $this.Note = $why
    }

    # INCONCLUSIVE must not overwrite a recorded FAIL or DECLINE: a step that found something has
    # measured something by definition, and relabelling it hides the finding.
    [void] Seal([string]$emptyNote) {
        if ($this.Count -eq 0 -and $this.Status -eq 'PASS') {
            $this.Status = 'INCONCLUSIVE'
            $this.Note = $emptyNote
        }
    }
}

# ── WHAT THIS SCRIPT OWNS, as constants ─────────────────────────────────────────
# The only facts about the layer written down in this file. Everything else -- the fragment, the
# skills, the floor, the guard -- is discovered, parsed or measured.

# HTML comment markers, because CLAUDE.md is markdown and markdown has comments. This is the
# claude-worktree-toolkit managed-block pattern in the syntax the target file supports; the same
# begin/end pair, the same "replace any prior block rather than append a second one" rule.
$script:BlockBegin = '<!-- >>> claude-practice-layer >>> -->'
$script:BlockEnd = '<!-- <<< claude-practice-layer <<< -->'

$script:ManifestName = '.practice-layer-install.json'
$script:ManifestSchema = 'practice-layer-install/v1'
$script:HookEvent = 'PreToolUse'
$script:GuardName = 'secret-guard.ps1'

# The token in settings.template.json that has to become a real path. Named here so that a template
# which stops carrying it FAILS the install loudly: a hook command still holding a placeholder is a
# hook that never runs, and Claude Code reports nothing about it.
$script:HooksPlaceholder = '<<HOOKS_DIR>>'

# Characters that are hostile inside a shell double-quoted string, in both shells a hook might run
# under. All are legal in a Windows path. `'` is deliberately NOT here: it is the character the
# sibling installer was bitten by, and double-quoting is what makes it safe rather than refused.
$script:ShellHostile = @('$', '`', '"', '%')

# ── HELPERS ─────────────────────────────────────────────────────────────────────

function Get-Sha256Hex {
    param([byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return [System.BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-FileSha256 {
    param([string]$Path)
    return Get-Sha256Hex -Bytes ([System.IO.File]::ReadAllBytes($Path))
}

function Get-TextSha256 {
    # Line endings normalised to LF FIRST. This repository is edited LF and checked out CRLF on the
    # Windows runner, and a recipient's editor may rewrite either way. Hashing raw bytes would make
    # a line-ending rewrite indistinguishable from an edit, and the consequence lands on -Uninstall:
    # it would DECLINE to remove its own managed block because a newline convention changed.
    param([string]$Text)
    return Get-Sha256Hex -Bytes ([System.Text.Encoding]::UTF8.GetBytes(($Text -replace "`r`n", "`n")))
}

function Format-Utc {
    # ConvertFrom-Json turns an ISO-8601 string into a [datetime] whether you wanted one or not, and
    # interpolating that renders it in the HOST's culture -- so the manifest's UTC timestamp came back
    # out of the uninstall report as '08/19/2026 17:26:25', local format, no zone, on one machine and
    # differently on the next. Formatted back to what was written instead.
    param([object]$Value)
    if ($Value -is [datetime]) { return ([datetime]$Value).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
    return [string]$Value
}

function Test-HasProp {
    # Set-StrictMode -Version Latest makes a missing-property read an error rather than $null, and
    # every object here comes from somebody else's JSON where any key may be absent. One helper, used
    # everywhere, beats a try/catch per access.
    #
    # NOT `$Object.PSObject.Properties.Name -contains $Name`. That is member enumeration over a
    # collection, and under Set-StrictMode -Version Latest it THROWS on an empty one -- "The property
    # 'Name' cannot be found on this object" -- which is exactly the case that matters here: a
    # first-ever install reads a brand-new [pscustomobject]@{} with no properties at all. Iterating
    # the collection has no such edge.
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($Name) }
    foreach ($p in $Object.PSObject.Properties) { if ($p.Name -ceq $Name) { return $true } }
    return $false
}

function Get-PropName {
    # Same trap, same reason: the caller wants every top-level key of somebody else's JSON, and that
    # object is legitimately empty.
    param([object]$Object)
    $names = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Object) { return $names.ToArray() }
    foreach ($p in $Object.PSObject.Properties) { $names.Add($p.Name) }
    return $names.ToArray()
}

function Get-RelUnder {
    # Relative to $Root when it is under it; the ABSOLUTE path otherwise, and that fallback is not a
    # nicety. -HooksDir exists so that a recipient whose home directory contains a shell-hostile
    # character can put the guard somewhere else -- i.e. deliberately OUTSIDE -ClaudeHome -- and a
    # manifest that recorded that as a relative path would have -Uninstall delete a path under the
    # home that does not exist while leaving the real file behind.
    param([string]$FullName, [string]$Root)
    $full = [System.IO.Path]::GetFullPath($FullName)
    $r = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    if ($full.StartsWith($r + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($r.Length).TrimStart('\', '/').Replace('\', '/')
    }
    return $full.Replace('\', '/')
}

function Resolve-RecordPath {
    # The inverse of Get-RelUnder, and the only way a manifest path is ever turned back into a
    # filesystem path. One function, so the rooted case cannot be handled correctly in one place and
    # forgotten in the next.
    param([string]$Rel, [string]$HomeDir)
    if ([System.IO.Path]::IsPathRooted($Rel)) { return ($Rel -replace '/', [System.IO.Path]::DirectorySeparatorChar) }
    return (Join-Path $HomeDir ($Rel -replace '/', [System.IO.Path]::DirectorySeparatorChar))
}

function Get-MissingAncestor {
    # EVERY directory that has to be created, deepest last, so all of them can be recorded.
    #
    # Recording only the leaf is the bug this replaces, and it is invisible in an install: creating
    # skills/alpha/references also creates skills/alpha and skills, and an uninstall that only knows
    # about the leaf leaves two empty directories behind in the recipient's configuration -- for
    # ever, because nothing else will ever claim them.
    param([string]$Dir, [string]$Stop)
    $need = [System.Collections.Generic.List[string]]::new()
    $cur = [System.IO.Path]::GetFullPath($Dir)
    $stopAt = [System.IO.Path]::GetFullPath($Stop).TrimEnd('\', '/')
    while (-not [string]::IsNullOrWhiteSpace($cur) -and -not (Test-Path -LiteralPath $cur)) {
        if ($cur.TrimEnd('\', '/') -ieq $stopAt) { break }
        $need.Add($cur)
        $parent = [System.IO.Path]::GetDirectoryName($cur)
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -ieq $cur) { break }
        $cur = $parent
    }
    $need.Reverse()
    # Plain return, for the reason on Test-ShellSafePath: comma-wrapped, an empty result reads as one
    # element holding the empty string, and this one is fed straight to Get-RelUnder -- which calls
    # GetFullPath('') and throws. That is how the idiom was caught.
    return $need.ToArray()
}

function Get-SortedOrdinal {
    # ORDINAL, not Sort-Object: Sort-Object is culture-sensitive, and these lists are written into a
    # manifest that a later run compares against. A list whose order depends on the machine turns
    # that comparison into a coin toss on the day somebody diffs it as text.
    #
    # THIS is the one function in the file that keeps `return , $array`, and the reason is the call
    # site: its result is assigned STRAIGHT into a manifest property that ConvertTo-Json serialises.
    # Without the wrapper an empty list serialises as `null` and a one-element list as a bare string
    # -- and `null` where an array belongs is a manifest field an uninstall reads as "nothing of that
    # kind was installed". Every OTHER array-returning helper here does the opposite, because their
    # callers wrap in @(...), where the wrapper produces a phantom empty element instead. The two
    # idioms are not interchangeable and each one is wrong in the other's place.
    param([string[]]$Values)
    $copy = [string[]]::new($Values.Count)
    [System.Array]::Copy($Values, $copy, $Values.Count)
    [System.Array]::Sort($copy, [System.StringComparer]::Ordinal)
    return , $copy
}

function Test-ShellSafePath {
    # Returns the offending characters, empty when the path can be emitted double-quoted safely.
    param([string]$Path)
    $bad = [System.Collections.Generic.List[string]]::new()
    foreach ($c in $script:ShellHostile) { if ($Path.Contains($c)) { $bad.Add($c) } }
    # NO `return , $array` -- see Get-SortedOrdinal for the one place that idiom is right and why it
    # is WRONG here. Every caller of this wraps in @(...), and a comma-wrapped EMPTY array read that
    # way comes back as one element holding the empty string. Count would then be 1 for a perfectly
    # clean path, and the pre-flight below would refuse every install ever attempted. Measured.
    return $bad.ToArray()
}

function Get-LayerProvenance {
    # The commit the layer was installed from, and whether the tree matched it. Both go in the
    # manifest.
    #
    # UNRESOLVED IS A WARNING HERE, NOT A FAILURE -- which is the opposite of Build-SharePack.ps1,
    # and the difference is what the field is FOR. There, provenance is the product: a pack whose
    # source commit reads "unknown" cannot be traced back and must not ship. Here the manifest's job
    # is uninstall precision, and every field uninstall reads is measured locally. A recipient
    # installing from an unzipped pack has no .git by construction, and refusing them an install
    # over a field nothing downstream consumes would be a gate that teaches people to route around
    # it.
    param([string]$SourceRoot, [string]$SourceCommit)

    if (-not [string]::IsNullOrWhiteSpace($SourceCommit)) {
        return @{ Commit = $SourceCommit.Trim(); State = 'asserted' }
    }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        return @{ Commit = ''; State = 'unresolved (git is not on PATH)' }
    }

    # In PowerShell 7.4+ $PSNativeCommandUseErrorActionPreference defaults on, so a non-zero exit
    # from a native command THROWS under $ErrorActionPreference = 'Stop'. Installing from outside a
    # repository is a case this function answers, not one it should die of.
    $PSNativeCommandUseErrorActionPreference = $false

    $commit = ''
    try {
        $out = git -C $SourceRoot rev-parse HEAD 2>$null
        if ($LASTEXITCODE -eq 0) { $commit = "$out".Trim() }
    }
    catch { $commit = '' }
    if ([string]::IsNullOrWhiteSpace($commit)) {
        return @{ Commit = ''; State = 'unresolved (no enclosing repository or no HEAD)' }
    }

    $state = 'clean'
    try {
        $porcelain = git -C $SourceRoot status --porcelain 2>$null
        if ($LASTEXITCODE -ne 0) { $state = 'unknown' }
        elseif (-not [string]::IsNullOrWhiteSpace(($porcelain | Out-String))) { $state = 'dirty' }
    }
    catch { $state = 'unknown' }
    return @{ Commit = $commit; State = $state }
}

# ── THE SOURCE: DISCOVERED, NEVER ASSUMED ───────────────────────────────────────

function Get-LayerFragment {
    # Patterns in preference order, and AMBIGUITY IS AN ERROR rather than a first match. Two files
    # both looking like the fragment means the author is mid-rename, and picking one installs half a
    # rename into somebody's always-on context where it is invisible until it is wrong.
    param([string]$LayerRoot, [string]$FragmentPath)

    if (-not [string]::IsNullOrWhiteSpace($FragmentPath)) {
        if (-not (Test-Path -LiteralPath $FragmentPath -PathType Leaf)) {
            throw "-FragmentPath '$FragmentPath' is not a file. This is the always-on CLAUDE.md fragment; there is nothing to install without it."
        }
        return (Resolve-Path -LiteralPath $FragmentPath).Path
    }

    $patterns = @('CLAUDE-FRAGMENT*.md', '*FRAGMENT*.md', 'CLAUDE.md.template')
    foreach ($p in $patterns) {
        $hits = @(Get-ChildItem -LiteralPath $LayerRoot -File -Filter $p -ErrorAction SilentlyContinue |
            Sort-Object Name)
        if ($hits.Count -eq 1) { return $hits[0].FullName }
        if ($hits.Count -gt 1) {
            throw ("more than one file in $LayerRoot matches '$p' (" + (@($hits | ForEach-Object { $_.Name }) -join ', ') +
                ") -- which of them is the fragment is not something this installer may guess. Pass -FragmentPath.")
        }
    }
    throw ("no CLAUDE.md fragment found in $LayerRoot -- looked for " + ($patterns -join ', ') +
        ". The fragment is authored separately from this installer; it is not there yet, or it has been renamed. Pass -FragmentPath to name it explicitly.")
}

function Get-LayerSkill {
    # A skill is a directory containing SKILL.md. Everything under it ships, so an author adding a
    # references/ subdirectory does not have to come and tell this file about it.
    param([string]$SkillsRoot)

    if (-not (Test-Path -LiteralPath $SkillsRoot -PathType Container)) {
        throw "no skills directory at $SkillsRoot -- the practice skills are authored separately from this installer and are not there yet. Pass -SkillsRoot, or install the fragment-only layer once that is a thing this script offers (it is not)."
    }
    $skills = [System.Collections.Generic.List[object]]::new()
    $malformed = [System.Collections.Generic.List[string]]::new()
    foreach ($d in @(Get-ChildItem -LiteralPath $SkillsRoot -Directory | Sort-Object Name)) {
        if (-not (Test-Path -LiteralPath (Join-Path $d.FullName 'SKILL.md') -PathType Leaf)) {
            $malformed.Add($d.Name)
            continue
        }
        $files = @(Get-ChildItem -LiteralPath $d.FullName -Recurse -File |
            Where-Object { $_.FullName -notmatch '[\\/](__pycache__|node_modules|\.git)[\\/]' } |
            Sort-Object FullName)
        $skills.Add(@{ Name = $d.Name; Root = $d.FullName; Files = $files })
    }
    if ($malformed.Count -gt 0) {
        throw ("skill director" + $(if ($malformed.Count -eq 1) { 'y' } else { 'ies' }) + " with no SKILL.md: " +
            (@($malformed) -join ', ') + " -- a skill without its SKILL.md does not load, and installing it would put a directory Claude Code silently ignores into the recipient's configuration.")
    }
    if ($skills.Count -eq 0) {
        throw "no skills found under $SkillsRoot -- it exists and holds no skill directory. An empty install is not the same as a clean one, so this stops rather than reporting a firing layer that fires nothing."
    }
    # NO `return , $array` HERE, and the difference is not cosmetic. That wrapper is the right idiom
    # for a function returning STRINGS, where the hazard is a one-element result unrolling to a bare
    # string. Used on a list of objects whose caller writes @(...), it does the opposite: the caller
    # gets a one-element array holding the whole inner array, every $skill.Name reads as the JOIN of
    # all the names, and the first thing that notices is a CreateDirectory call with two paths
    # concatenated into one. That is exactly how this was found. Callers wrap in @(...), which handles
    # the one-element case correctly for a plain array return.
    return $skills.ToArray()
}

function Import-FloorTemplate {
    # THE FLOOR IS READ, NEVER RESTATED. settings.template.json is the artifact with a suite holding
    # it to being a floor; this script is a caller. A missing or reshaped template FAILS -- the loud
    # direction, because the quiet one installs a floor made of whatever this file remembered.
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "the permission floor is not at $Path -- this installer does not carry its own copy, on purpose (a second copy is a fork the moment either moves). Pass -FloorTemplate, or restore the file."
    }
    $obj = $null
    try { $obj = [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json }
    catch { throw "$Path does not parse as JSON ($($_.Exception.Message)) -- refusing to install a floor read out of a file nothing could read" }

    if (-not (Test-HasProp $obj 'permissions')) {
        throw "$Path has no 'permissions' block -- shape check failed, and an installer must not install an empty floor while reporting a floor"
    }
    $deny = @()
    $ask = @()
    if (Test-HasProp $obj.permissions 'deny') { $deny = @($obj.permissions.deny) }
    if (Test-HasProp $obj.permissions 'ask') { $ask = @($obj.permissions.ask) }
    if ($deny.Count -eq 0 -and $ask.Count -eq 0) {
        throw "$Path carries no deny and no ask entries -- that is not a floor, and installing it would leave the recipient exactly where they started while the report said otherwise"
    }

    # The hook wiring, if the template ships it. Absent is legitimate: the floor half stands alone.
    $hookGroup = $null
    if ((Test-HasProp $obj 'hooks') -and (Test-HasProp $obj.hooks $script:HookEvent)) {
        $groups = @($obj.hooks.$($script:HookEvent))
        if ($groups.Count -gt 1) {
            throw "$Path ships $($groups.Count) $($script:HookEvent) groups -- this installer merges one, and choosing among several is not a decision it may make silently"
        }
        if ($groups.Count -eq 1) { $hookGroup = $groups[0] }
    }

    return @{
        Deny      = @($deny | ForEach-Object { [string]$_ })
        Ask       = @($ask | ForEach-Object { [string]$_ })
        HookGroup = $hookGroup
        Path      = $Path
    }
}

function Resolve-HookCommand {
    # Substitute the placeholder for the real guard path, DOUBLE-QUOTED.
    #
    # THE QUOTING IS THE POINT, and it is the sibling installer's apostrophe lesson in a different
    # substrate. JSON does not care about an apostrophe, so nothing here needs the doubling that fixed
    # the $PROFILE write -- but Claude Code hands this string to a SHELL, and
    # `-File C:/Users/O'Brien/.claude/hooks/secret-guard.ps1` opens a quote that is never closed in
    # bash and in PowerShell alike. Double quotes close that hole and the space hole with it, and a
    # double quote cannot occur in a Windows path so it is a safe delimiter by construction. The two
    # characters that survive double quotes -- `$` and a backtick -- are refused at pre-flight
    # instead, because escaping for a shell this script cannot identify is a guess.
    #
    # String .Replace, never -replace: a regex replacement reads `$` in the path as a capture
    # reference and would silently truncate a legal Windows path. Belt to the pre-flight braces --
    # the two checks live in different places and only one of them is in this function.
    #
    # ONLY the exact `<<HOOKS_DIR>>/secret-guard.ps1` form is understood. Substituting a bare
    # `<<HOOKS_DIR>>` would have to quote a DIRECTORY mid-argument -- `-File "C:/h"/secret-guard.ps1`
    # -- which is broken quoting that happens to work in one shell and not the other. A template this
    # function cannot resolve exactly is an error, not a best effort.
    param([string]$Template, [string]$GuardTarget)

    $token = $script:HooksPlaceholder + '/' + $script:GuardName
    if (-not $Template.Contains($token)) {
        throw ("the floor's hook command does not contain '$token', so this installer cannot tell where in it the guard path belongs: " +
            "`n           $Template`n         The floor template's hook command shape changed. Fix the substitution here rather than installing a command that points somewhere unverified -- a PreToolUse hook whose file does not exist fails SILENTLY on every tool call.")
    }
    $cmd = $Template.Replace($token, ('"' + ($GuardTarget -replace '\\', '/') + '"'))
    if ($cmd.Contains($script:HooksPlaceholder)) {
        # Reachable: a template naming the placeholder twice (`... <<HOOKS_DIR>>/secret-guard.ps1
        # -Log <<HOOKS_DIR>>/guard.log`) leaves the second one behind. An inert guard would be worse
        # than none, so this one is exercised in -SelfTest.
        throw "the hook command still contains $($script:HooksPlaceholder) after substitution -- it would be installed pointing at a placeholder, and a PreToolUse hook whose command does not resolve fails silently on every tool call"
    }
    return $cmd
}

# ── settings.json: READ, VALIDATE, MERGE, WRITE ─────────────────────────────────

function Test-SettingsShape {
    # Shape assertions beyond "it parsed". Returns findings; EMPTY means usable, so the empty case is
    # the load-bearing one -- which is why this returns a plain array and not `return , $array`. Read
    # back through @(...) the wrapper turns "no findings" into ONE finding holding an empty array,
    # every valid settings.json in the world is refused as malformed, and the reported finding reads
    # `System.String[]`. That is not a hypothetical: it is what the self-test caught on this function.
    #
    # These are the properties the merge relies on, asserted before it relies on them, because a
    # permissions.deny that is a STRING rather than an array would be merged into something Claude
    # Code rejects -- and rejection is whole-file.
    param([object]$Object, [string]$Label)

    $findings = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Object) { $findings.Add("${Label}: parsed to null"); return $findings.ToArray() }
    if ($Object -isnot [System.Management.Automation.PSCustomObject]) {
        $findings.Add("${Label}: the top level is a $($Object.GetType().Name), not a JSON object")
        return $findings.ToArray()
    }
    if (Test-HasProp $Object 'permissions') {
        $p = $Object.permissions
        if ($p -isnot [System.Management.Automation.PSCustomObject]) {
            $findings.Add("${Label}: 'permissions' is a $($p.GetType().Name), not an object")
        }
        else {
            foreach ($k in @('deny', 'ask', 'allow')) {
                if (-not (Test-HasProp $p $k)) { continue }
                $v = $p.$k
                if ($null -ne $v -and $v -isnot [System.Object[]]) {
                    $findings.Add("${Label}: 'permissions.$k' is a $($v.GetType().Name), not an array")
                }
            }
        }
    }
    if (Test-HasProp $Object 'hooks') {
        $h = $Object.hooks
        if ($h -isnot [System.Management.Automation.PSCustomObject]) {
            $findings.Add("${Label}: 'hooks' is a $($h.GetType().Name), not an object")
        }
        elseif (Test-HasProp $h $script:HookEvent) {
            $v = $h.$($script:HookEvent)
            if ($null -ne $v -and $v -isnot [System.Object[]]) {
                $findings.Add("${Label}: 'hooks.$($script:HookEvent)' is a $($v.GetType().Name), not an array")
            }
        }
    }
    return $findings.ToArray()
}

function Test-SettingsIsVacuous {
    # "Nothing is left in this file except the empty containers this installer put there." Used by
    # -Uninstall to finish the job on a settings.json it CREATED, symmetrically with CLAUDE.md -- which
    # it already deletes when it created the file and nothing else is in it. Without this the uninstall
    # reports "everything the manifest recorded has been removed, and nothing else" and leaves a
    # `{"permissions":{"deny":[],"ask":[]},"hooks":{"PreToolUse":[]}}` behind, which is inert but is
    # also not nothing, and the sentence is then not quite true.
    #
    # Deliberately strict: ANY key this installer does not write, and any non-empty list under one it
    # does, makes the file the recipient's and it stays. `permissions.allow` counts even though this
    # script never adds to it -- a non-empty allow list is a decision somebody made.
    param([object]$Object)
    foreach ($p in @(Get-PropName -Object $Object)) {
        if ($p -ceq 'permissions') {
            foreach ($q in @(Get-PropName -Object $Object.permissions)) {
                if ($q -cnotin @('deny', 'ask', 'allow')) { return $false }
                $v = $Object.permissions.$q
                if ($null -ne $v -and @($v).Count -gt 0) { return $false }
            }
            continue
        }
        if ($p -ceq 'hooks') {
            foreach ($q in @(Get-PropName -Object $Object.hooks)) {
                $v = $Object.hooks.$q
                if ($null -ne $v -and @($v).Count -gt 0) { return $false }
            }
            continue
        }
        return $false
    }
    return $true
}

function Import-SettingsFile {
    # ConvertFrom-Json WITHOUT -AsHashtable, and that is load-bearing. -AsHashtable returns an
    # unordered Hashtable, so writing it back reorders every key in somebody else's configuration --
    # a diff that looks like this script rewrote the file when all it did was add two entries, and a
    # git-tracked ~/.claude would show it. PSCustomObject preserves document order in PowerShell 7.
    #
    # AN UNPARSEABLE FILE THROWS. It is not repaired and not replaced: it is already fully rejected
    # by Claude Code, so there is nothing to save by pressing on, and a repair is a guess about
    # intent written into the file that can least afford one.
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @{ Object = [pscustomobject]@{}; Existed = $false }
    }
    $raw = [System.IO.File]::ReadAllText($Path)
    if ([string]::IsNullOrWhiteSpace($raw)) {
        # Empty and absent are different facts, and only one of them is a file somebody wrote. An
        # empty settings.json is treated as an empty object rather than refused, because that is
        # what a `touch` leaves behind and there is nothing in it to protect.
        return @{ Object = [pscustomobject]@{}; Existed = $true }
    }
    $obj = $null
    try { $obj = $raw | ConvertFrom-Json }
    catch {
        throw ("$Path does not parse as JSON: $($_.Exception.Message)`n" +
            "         REFUSING TO CONTINUE, and refusing to repair it. A settings file that fails validation is rejected WHOLE, so this file is already switched off in its entirety -- but what it was MEANT to say is a guess, and a guess written here silently changes which permissions apply. Fix the JSON by hand (or move it aside) and re-run. Nothing has been written.")
    }
    $findings = @(Test-SettingsShape -Object $obj -Label $Path)
    if ($findings.Count -gt 0) {
        throw ("$Path parses but is not shaped like a settings file:`n           " + ($findings -join "`n           ") +
            "`n         REFUSING TO CONTINUE. Merging into this would produce a file Claude Code rejects whole.")
    }
    return @{ Object = $obj; Existed = $true }
}

function Merge-PermissionFloor {
    # UNION, and it records ONLY what it added. That second half is what makes -Uninstall precise:
    # an entry the recipient already had never enters the manifest, so uninstall cannot take it.
    #
    # Ordering: existing entries keep their positions and new ones are appended. Permission matching
    # is not order-sensitive for deny/ask, so this buys nothing functional -- it buys a diff the
    # recipient can read, which is the difference between an installer they trust twice and one they
    # run once.
    param([object]$Settings, [string[]]$Deny, [string[]]$Ask, [object]$HookGroup, [string]$HookCommand)

    $denyAdded = [System.Collections.Generic.List[string]]::new()
    $askAdded = [System.Collections.Generic.List[string]]::new()
    $hooksAdded = [System.Collections.Generic.List[object]]::new()
    $present = [System.Collections.Generic.List[string]]::new()

    if (-not (Test-HasProp $Settings 'permissions')) {
        $Settings | Add-Member -NotePropertyName 'permissions' -NotePropertyValue ([pscustomobject]@{})
    }
    $perm = $Settings.permissions

    foreach ($pair in @(@{ Key = 'deny'; Want = $Deny; Added = $denyAdded }, @{ Key = 'ask'; Want = $Ask; Added = $askAdded })) {
        $key = $pair.Key
        $have = [System.Collections.Generic.List[string]]::new()
        if (Test-HasProp $perm $key) {
            foreach ($e in @($perm.$key)) { if ($null -ne $e) { $have.Add([string]$e) } }
        }
        # ORDINAL comparison. A permission rule is matched by Claude Code as text, so 'Read(**/.ENV)'
        # and 'Read(**/.env)' are two different rules -- treating them as one here would silently
        # drop one of them from the file.
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($e in $have) { $null = $seen.Add($e) }
        foreach ($e in $pair.Want) {
            if ($seen.Contains($e)) { $present.Add("$key : $e"); continue }
            $have.Add($e)
            $null = $seen.Add($e)
            $pair.Added.Add($e)
        }
        # .ToArray() rather than @(...). A List[string] handed to ConvertTo-Json through @() unrolls,
        # and a ONE-ELEMENT list then serialises as a bare string instead of an array -- which is a
        # settings file Claude Code rejects whole, written by an installer that reported success.
        if (Test-HasProp $perm $key) { $perm.$key = $have.ToArray() }
        else { $perm | Add-Member -NotePropertyName $key -NotePropertyValue $have.ToArray() }
    }

    # permissions.allow is deliberately not merged. See the DESCRIPTION: allow is the only list that
    # grants, and the floor's own allow list is empty for the same reason.

    if ($null -ne $HookGroup) {
        $matcher = ''
        if (Test-HasProp $HookGroup 'matcher') { $matcher = [string]$HookGroup.matcher }

        if (-not (Test-HasProp $Settings 'hooks')) {
            $Settings | Add-Member -NotePropertyName 'hooks' -NotePropertyValue ([pscustomobject]@{})
        }
        if (-not (Test-HasProp $Settings.hooks $script:HookEvent)) {
            $Settings.hooks | Add-Member -NotePropertyName $script:HookEvent -NotePropertyValue @()
        }
        $groups = [System.Collections.Generic.List[object]]::new()
        foreach ($g in @($Settings.hooks.$($script:HookEvent))) { if ($null -ne $g) { $groups.Add($g) } }

        $target = $null
        foreach ($g in $groups) {
            if ((Test-HasProp $g 'matcher') -and ([string]$g.matcher -ceq $matcher)) { $target = $g; break }
        }
        $groupCreated = $false
        if ($null -eq $target) {
            $target = [pscustomobject]@{ matcher = $matcher; hooks = @() }
            $groups.Add($target)
            $groupCreated = $true
        }
        if (-not (Test-HasProp $target 'hooks')) {
            $target | Add-Member -NotePropertyName 'hooks' -NotePropertyValue @()
        }

        $inner = [System.Collections.Generic.List[object]]::new()
        foreach ($h in @($target.hooks)) { if ($null -ne $h) { $inner.Add($h) } }

        # Identity is the COMMAND STRING. Not the whole object: a recipient who raised the timeout on
        # this hook has adjusted our entry, not written their own, and a second copy of the same
        # command would run the guard twice on every tool call.
        $already = $false
        foreach ($h in $inner) {
            if ((Test-HasProp $h 'command') -and ([string]$h.command -ceq $HookCommand)) { $already = $true; break }
        }
        if ($already) {
            $present.Add("hooks.$($script:HookEvent) : $matcher -> the guard command is already wired")
        }
        else {
            $hook = [pscustomobject]@{ type = 'command'; command = $HookCommand }
            if (Test-HasProp $HookGroup 'hooks') {
                foreach ($h in @($HookGroup.hooks)) {
                    if ((Test-HasProp $h 'timeout')) { $hook | Add-Member -NotePropertyName 'timeout' -NotePropertyValue $h.timeout; break }
                }
            }
            $inner.Add($hook)
            $hooksAdded.Add(@{
                    event         = $script:HookEvent
                    matcher       = $matcher
                    group_created = $groupCreated
                    command       = $HookCommand
                    hook          = $hook
                })
        }
        $target.hooks = $inner.ToArray()
        $Settings.hooks.$($script:HookEvent) = $groups.ToArray()
    }

    return @{
        Settings   = $Settings
        DenyAdded  = $denyAdded.ToArray()
        AskAdded   = $askAdded.ToArray()
        HooksAdded = $hooksAdded.ToArray()
        Present    = $present.ToArray()
    }
}

function Write-JsonChecked {
    # THE WHOLE POINT OF THE FILE, in one function. Temp -> parse-validate -> back up -> swap ->
    # read back and re-parse, and any failure restores the backup and names it.
    #
    # Why each step, in the order the failures bite:
    #   * A settings file that fails validation is REJECTED WHOLE, so a malformed write does not
    #     degrade the configuration by one rule -- it disables all of it. Validating the temp file
    #     before it is anywhere near the real path is the only step that can prevent that rather
    #     than apologise for it.
    #   * Truncate-then-write is not atomic. Move-with-overwrite is a single filesystem operation,
    #     so a process killed mid-install leaves either the old file or the new one.
    #   * A write that succeeded and a write that produced the wrong bytes are different states, and
    #     only reading it back distinguishes them.
    #   * The backup exists for the case where the read-back is the thing that fails: at that point
    #     the bad file is already in place and only a restore helps.
    #
    # WriteAllText and File.Move, never Set-Content / Move-Item: both of those support ShouldProcess
    # and would write NOTHING under an inherited $WhatIfPreference while every success message below
    # still printed.
    #
    # -TakeBackup $false is for a file this script wholly OWNS -- the install manifest. A backup exists to
    # protect content somebody else wrote, and there is none here; taking one anyway drops a
    # .bak-<timestamp> into the recipient's configuration directory on every single re-install, which
    # accumulates for ever because nothing ever claims those files again. Measured: two installs left
    # one. File.Move is atomic, so the old manifest survives a failed write regardless.
    # NOT NAMED $Backup. PowerShell variable names are CASE-INSENSITIVE, so a parameter $Backup and
    # the local $backup holding the backup path below are ONE variable: `$backup = ''` silently zeroed
    # the parameter, `if ($Backup ...)` was then always false, and no backup was EVER taken -- by the
    # function whose entire job is taking one. It reported success throughout. Found by the
    # fault-injection controls, which restored nothing because there was nothing to restore.
    param([string]$Path, [object]$Object, [string]$Fault, [bool]$TakeBackup = $true)

    $json = $Object | ConvertTo-Json -Depth 100
    $dir = [System.IO.Path]::GetDirectoryName($Path)
    if (-not [string]::IsNullOrWhiteSpace($dir)) { $null = [System.IO.Directory]::CreateDirectory($dir) }
    $tmp = "$Path.tmp-" + [guid]::NewGuid().ToString('N').Substring(0, 8)

    # UTF-8 WITHOUT a BOM. JSON is UTF-8 by specification and a BOM is not part of it; several JSON
    # parsers treat the three bytes as content and fail on them, which here means a settings file
    # rejected whole for a reason nothing in it explains.
    $enc = [System.Text.UTF8Encoding]::new($false)
    if ($Fault -eq 'SettingsTempInvalid') {
        # Fault injection: a temp file that will not parse. Proves the validate step is what stops
        # the swap, rather than the swap happening to work.
        [System.IO.File]::WriteAllText($tmp, ($json + "`n{ this is not json"), $enc)
    }
    else {
        [System.IO.File]::WriteAllText($tmp, ($json + "`n"), $enc)
    }

    $backup = ''
    try {
        # 1) validate the CANDIDATE, before the real path is involved at all
        $candidate = $null
        try { $candidate = [System.IO.File]::ReadAllText($tmp) | ConvertFrom-Json }
        # These two throws deliberately do NOT state the outcome. The catch below does, and it is the
        # only place that KNOWS it -- whether a backup was taken and restored, or the target is
        # untouched, or no file was created at all. Saying it in both produced "... is untouched.
        # ... is unchanged." in one finding, and a message that repeats itself reads as a message
        # nobody assembled on purpose.
        catch { throw "the file this install was about to write does not parse as JSON ($($_.Exception.Message))." }
        $shape = @(Test-SettingsShape -Object $candidate -Label 'the candidate file')
        if ($shape.Count -gt 0) {
            throw ("the file this install was about to write is not shaped like a settings file:`n           " +
                ($shape -join "`n           "))
        }

        # 2) back up the original, if there is one to lose
        if ($TakeBackup -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
            $backup = "$Path.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
            [System.IO.File]::Copy($Path, $backup, $true)
        }

        # 3) swap
        if ($Fault -eq 'SettingsSwap') { throw 'fault injection: the swap failed' }
        [System.IO.File]::Move($tmp, $Path, $true)

        # 4) read back and re-parse. Bytes AND meaning: a truncated write can still be valid JSON.
        $readBack = [System.IO.File]::ReadAllText($Path)
        if ($Fault -eq 'SettingsReadback') { $readBack = '{ "sabotaged": ' }
        $reparsed = $null
        try { $reparsed = $readBack | ConvertFrom-Json }
        catch { throw "wrote $Path and read back something that does not parse ($($_.Exception.Message))" }
        if ($null -eq $reparsed) { throw "wrote $Path and read back an empty document" }
        if ($readBack.TrimEnd() -cne $json.TrimEnd() -and $Fault -ne 'SettingsReadback') {
            throw "wrote $Path and read back different bytes"
        }
        if ($Fault -eq 'SettingsReadback') { throw "wrote $Path and read back different bytes (fault injection)" }

        return @{ Backup = $backup; Bytes = [System.Text.Encoding]::UTF8.GetByteCount($json) }
    }
    catch {
        $msg = $_.Exception.Message
        $restored = ''
        if ($backup -and (Test-Path -LiteralPath $backup -PathType Leaf)) {
            [System.IO.File]::Copy($backup, $Path, $true)
            $restored = " The previous $([System.IO.Path]::GetFileName($Path)) HAS BEEN RESTORED from $([System.IO.Path]::GetFileName($backup)), which is still there."
        }
        elseif (Test-Path -LiteralPath $Path -PathType Leaf) {
            $restored = " $Path is unchanged."
        }
        else {
            $restored = " No $([System.IO.Path]::GetFileName($Path)) was created."
        }
        if (Test-Path -LiteralPath $tmp -PathType Leaf) { [System.IO.File]::Delete($tmp) }
        throw "$msg$restored"
    }
}

function Write-TextChecked {
    # The same discipline for a text file: temp -> back up -> swap -> read back and compare. There is
    # no parse step, because there is no grammar to check -- so the read-back compare is the whole
    # verification and it is not optional.
    param([string]$Path, [string]$Text, [bool]$Bom)

    $dir = [System.IO.Path]::GetDirectoryName($Path)
    if (-not [string]::IsNullOrWhiteSpace($dir)) { $null = [System.IO.Directory]::CreateDirectory($dir) }
    $tmp = "$Path.tmp-" + [guid]::NewGuid().ToString('N').Substring(0, 8)
    [System.IO.File]::WriteAllText($tmp, $Text, [System.Text.UTF8Encoding]::new($Bom))

    $backup = ''
    try {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            $backup = "$Path.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
            [System.IO.File]::Copy($Path, $backup, $true)
        }
        [System.IO.File]::Move($tmp, $Path, $true)
        if ([System.IO.File]::ReadAllText($Path) -cne $Text) {
            throw "wrote $Path but read back something different"
        }
        return @{ Backup = $backup }
    }
    catch {
        $msg = $_.Exception.Message
        if ($backup -and (Test-Path -LiteralPath $backup -PathType Leaf)) {
            [System.IO.File]::Copy($backup, $Path, $true)
            $msg += " -- restored from $([System.IO.Path]::GetFileName($backup))"
        }
        if (Test-Path -LiteralPath $tmp -PathType Leaf) { [System.IO.File]::Delete($tmp) }
        throw $msg
    }
}

# ── THE MANAGED BLOCK IN CLAUDE.md ──────────────────────────────────────────────

function Get-ManagedBlock {
    # Returns the block BODY (between the markers, exclusive) or $null. Regex over LF-normalised
    # text: this repository is edited LF and checked out CRLF, and a marker pair compared against
    # raw text matches locally and stops matching in CI -- reporting "no block" about a block that
    # is right there, and appending a second one.
    param([string]$Text)

    $norm = $Text -replace "`r`n", "`n"
    $pattern = [regex]::Escape($script:BlockBegin) + '\n?(?<body>.*?)' + [regex]::Escape($script:BlockEnd)
    $m = [regex]::Match($norm, $pattern, 'Singleline')
    if (-not $m.Success) { return $null }
    return $m.Groups['body'].Value
}

function Merge-ManagedBlock {
    # Replace any prior block, never append a second. Same rule as the sibling installer's $PROFILE
    # block, and the same reason: two blocks means the second silently wins and the first is dead
    # text nobody can tell from live text.
    param([string][AllowEmptyString()]$Existing, [string]$Body)

    $norm = ($Existing -replace "`r`n", "`n")
    $block = $script:BlockBegin + "`n" + $Body.TrimEnd() + "`n" + $script:BlockEnd
    $pattern = [regex]::Escape($script:BlockBegin) + '.*?' + [regex]::Escape($script:BlockEnd) + '\n?'
    if ([regex]::IsMatch($norm, $pattern, 'Singleline')) {
        $out = [regex]::Replace($norm, $pattern, ($block + "`n"), 'Singleline')
    }
    else {
        $out = if ([string]::IsNullOrWhiteSpace($norm)) { $block + "`n" } else { $norm.TrimEnd() + "`n`n" + $block + "`n" }
    }
    return $out
}

function Get-TextWithoutBlock {
    # NOT NAMED Remove-*, and the reason is the same one that made the pack builder's stager
    # Copy-PackTree instead of New-PackStage: PSUseShouldProcessForStateChangingFunctions demands
    # SupportsShouldProcess on a Remove-* function, and ShouldProcess is the exact mechanism that
    # lets a writer report success having written nothing under an inherited -WhatIf -- which is the
    # bug this whole file is built to avoid. Paying the finding down rather than registering it is
    # also free here, because the old name was wrong: this function removes nothing. It takes a
    # string and returns a shorter string; every actual deletion in this file is an explicit
    # [System.IO.File]::Delete call at a call site that can be read.
    param([string]$Text)
    $norm = $Text -replace "`r`n", "`n"
    $pattern = '\n*' + [regex]::Escape($script:BlockBegin) + '.*?' + [regex]::Escape($script:BlockEnd) + '\n?'
    $out = [regex]::Replace($norm, $pattern, '', 'Singleline')
    if ([string]::IsNullOrWhiteSpace($out)) { return '' }
    return $out.TrimEnd() + "`n"
}

# ── THE MANIFEST ────────────────────────────────────────────────────────────────

function Import-InstallManifest {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $obj = $null
    try { $obj = [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json }
    catch {
        throw "$Path does not parse as JSON ($($_.Exception.Message)) -- this is the record of what was installed, and without it an uninstall can only guess. Fix or delete it by hand; deleting it means a later uninstall removes nothing."
    }
    if (-not (Test-HasProp $obj 'schema') -or [string]$obj.schema -ne $script:ManifestSchema) {
        $found = if (Test-HasProp $obj 'schema') { [string]$obj.schema } else { '<none>' }
        throw "$Path declares schema '$found', not '$($script:ManifestSchema)' -- refusing to read a record written by a different version of this installer, because the field an uninstall acts on may not mean what it says"
    }
    # Shape-checked, so an uninstall never reads a key that is not there. An absent list would read as
    # "nothing of that kind was installed", which is exactly what a hand-truncated manifest looks
    # like -- and the consequence is a silent under-removal reported as a clean uninstall.
    $missing = @()
    foreach ($k in @('deny_added', 'ask_added', 'hooks_added', 'claude_md', 'files', 'dirs_created', 'backups', 'settings_created')) {
        if (-not (Test-HasProp $obj $k)) { $missing += $k }
    }
    if ($missing.Count -gt 0) {
        throw "$Path is missing $($missing -join ', ') -- it declares the right schema and does not carry it. An uninstall reading this would remove less than was installed and report success; fix or delete the file by hand."
    }
    return $obj
}

# ── THE PLAN (what -DryRun prints and the write path executes) ───────────────────

function Add-PlanLine {
    param([System.Collections.Generic.List[object]]$Plan, [string]$Target, [string]$Op, [string]$Detail)
    $Plan.Add([pscustomobject]@{ Target = $Target; Op = $Op; Detail = $Detail })
}

# ── INSTALL ─────────────────────────────────────────────────────────────────────

function Invoke-LayerInstall {
    param([hashtable]$Ctx)

    $steps = [System.Collections.Generic.List[object]]::new()
    $plan = [System.Collections.Generic.List[object]]::new()
    $result = @{ Steps = $steps; Plan = $plan; Manifest = $null }

    $dry = [bool]$Ctx.DryRun
    $homeDir = $Ctx.ClaudeHome
    $manifestPath = Join-Path $homeDir $script:ManifestName

    # ── 1. SOURCES ─────────────────────────────────────────────────────────────
    $s1 = [InstallStep]::new('Sources')
    $steps.Add($s1)
    $src = $null
    try {
        $src = @{}
        $src.Fragment = Get-LayerFragment -LayerRoot $Ctx.LayerRoot -FragmentPath $Ctx.FragmentPath
        $src.Skills = @(Get-LayerSkill -SkillsRoot $Ctx.SkillsRoot)
        $src.Floor = Import-FloorTemplate -Path $Ctx.FloorTemplate
        if (-not (Test-Path -LiteralPath $Ctx.GuardScript -PathType Leaf)) {
            throw "the PreToolUse guard is not at $($Ctx.GuardScript) -- the floor's hook command points at it, so installing the floor without it wires a hook to a file that does not exist. That fails silently on every tool call."
        }
        $src.Guard = (Resolve-Path -LiteralPath $Ctx.GuardScript).Path

        # THE RECIPIENT'S settings.json IS PARSED HERE, IN THE PRE-FLIGHT, and not first touched in
        # the Settings step where it is merged. The reason is ordering: the steps run Sources ->
        # Files -> ClaudeMd -> Settings, so a file discovered to be unparseable at step 4 has already
        # had the skills copied in and the managed block written at steps 2 and 3. "Refuse and change
        # nothing" then is not true, and it was not true here until this line -- the -SelfTest control
        # for the unparseable case caught it by walking into a half-written home. Parsed twice, on
        # purpose: cheap, and the alternative is carrying a parsed object through three steps that
        # have no business holding it.
        $null = Import-SettingsFile -Path (Join-Path $homeDir 'settings.json')

        $s1.Count = 1 + @($src.Skills).Count
        $s1.Note = "fragment $([System.IO.Path]::GetFileName($src.Fragment)); $(@($src.Skills).Count) skill(s): " +
        (@(@($src.Skills) | ForEach-Object { $_.Name }) -join ', ') +
        "; floor $(@($src.Floor.Deny).Count) deny + $(@($src.Floor.Ask).Count) ask from $([System.IO.Path]::GetFileName($src.Floor.Path))"
    }
    catch {
        $s1.Fail($_.Exception.Message)
        $s1.Count = 1
        return $result
    }
    $s1.Seal('found no fragment and no skills -- the discovery walk is broken')
    if ($s1.Status -ne 'PASS') { return $result }

    # The existing manifest, read BEFORE anything is written. A re-install must carry forward the
    # provenance the first one recorded -- above all the pre-install BACKUP of a file it overwrote.
    # Without that, install-twice-then-uninstall restores the state after install #1 instead of the
    # state before it, which is a restore that looks exact and is not.
    $prior = $null
    try { $prior = Import-InstallManifest -Path $manifestPath }
    catch {
        $s1.Fail($_.Exception.Message)
        return $result
    }
    $priorFiles = @{}
    if ($null -ne $prior -and (Test-HasProp $prior 'files')) {
        foreach ($f in @($prior.files)) { if (Test-HasProp $f 'path') { $priorFiles[[string]$f.path] = $f } }
    }

    # ── 2. FILES (skills + the guard) ──────────────────────────────────────────
    $s2 = [InstallStep]::new('Files')
    $steps.Add($s2)
    $fileRecords = [System.Collections.Generic.List[object]]::new()
    $dirsCreated = [System.Collections.Generic.List[string]]::new()
    # Every backup this run takes, so the manifest can NAME them and -Uninstall can tell the recipient
    # what is still sitting in their configuration directory rather than leaving them to find it.
    $backupsTaken = [System.Collections.Generic.List[string]]::new()

    $copies = [System.Collections.Generic.List[object]]::new()
    foreach ($sk in @($src.Skills)) {
        foreach ($f in @($sk.Files)) {
            $rel = 'skills/' + $sk.Name + '/' + (Get-RelUnder -FullName $f.FullName -Root $sk.Root)
            $copies.Add(@{ Source = $f.FullName; Rel = $rel })
        }
    }
    $guardRel = (Get-RelUnder -FullName $Ctx.GuardTarget -Root $homeDir)
    $copies.Add(@{ Source = $src.Guard; Rel = $guardRel })

    foreach ($c in $copies) {
        $s2.Count++
        $target = Resolve-RecordPath -Rel $c.Rel -HomeDir $homeDir
        $srcHash = Get-FileSha256 -Path $c.Source
        $record = @{ path = $c.Rel; sha256 = $srcHash; backup = ''; pre_existing = $false }
        if ($priorFiles.ContainsKey($c.Rel)) {
            $p = $priorFiles[$c.Rel]
            if (Test-HasProp $p 'backup') { $record.backup = [string]$p.backup }
            if (Test-HasProp $p 'pre_existing') { $record.pre_existing = [bool]$p.pre_existing }
        }

        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            Add-PlanLine $plan $c.Rel '+' 'new file'
            if (-not $dry) {
                $dirTarget = [System.IO.Path]::GetDirectoryName($target)
                foreach ($d in @(Get-MissingAncestor -Dir $dirTarget -Stop $homeDir)) {
                    $dirsCreated.Add((Get-RelUnder -FullName $d -Root $homeDir))
                }
                if (-not (Test-Path -LiteralPath $dirTarget)) { $null = [System.IO.Directory]::CreateDirectory($dirTarget) }
                [System.IO.File]::Copy($c.Source, $target, $false)
                if ((Get-FileSha256 -Path $target) -ne $srcHash) {
                    $s2.Fail("$($c.Rel): copied and the hash does not match the source -- the file on disk is not what was installed")
                    continue
                }
            }
            $fileRecords.Add($record)
            continue
        }

        $haveHash = Get-FileSha256 -Path $target
        if ($haveHash -eq $srcHash) {
            Add-PlanLine $plan $c.Rel '=' 'identical, nothing to do'
            $fileRecords.Add($record)
            continue
        }
        # It differs. Ours (recorded in the prior manifest with the hash we last installed) is a
        # plain upgrade. Anything else is the recipient's file, and overwriting it needs -Force.
        $isOurs = $priorFiles.ContainsKey($c.Rel) -and (Test-HasProp $priorFiles[$c.Rel] 'sha256') -and
        ([string]$priorFiles[$c.Rel].sha256 -eq $haveHash)
        if (-not $isOurs -and -not $Ctx.Force) {
            $s2.Fail("$($c.Rel) exists with content this installer did not put there. Not overwriting it. Re-run with -Force to back it up and replace it, or move it aside.")
            continue
        }
        Add-PlanLine $plan $c.Rel '~' $(if ($isOurs) { 'differs from the installed copy -- back up and replace' } else { 'NOT ours and differs -- back up and replace (-Force)' })
        if (-not $dry) {
            $bak = "$target.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
            [System.IO.File]::Copy($target, $bak, $true)
            $backupsTaken.Add((Get-RelUnder -FullName $bak -Root $homeDir))
            # Only the FIRST backup is recorded. A second install must not overwrite the pointer to
            # the recipient's original with a pointer to our own previous copy.
            if (-not $isOurs -and [string]::IsNullOrWhiteSpace([string]$record.backup)) {
                $record.backup = Get-RelUnder -FullName $bak -Root $homeDir
                $record.pre_existing = $true
            }
            [System.IO.File]::Copy($c.Source, $target, $true)
            if ((Get-FileSha256 -Path $target) -ne $srcHash) {
                $s2.Fail("$($c.Rel): replaced and the hash does not match the source")
                continue
            }
        }
        $fileRecords.Add($record)
    }
    $s2.Seal('nothing to copy -- the source walk found a fragment and skills and then produced no files')
    if ($s2.Status -eq 'FAIL') { return $result }

    # ── 3. CLAUDE.md ───────────────────────────────────────────────────────────
    $s3 = [InstallStep]::new('ClaudeMd')
    $steps.Add($s3)
    $claudeMd = Join-Path $homeDir 'CLAUDE.md'
    $body = ([System.IO.File]::ReadAllText($src.Fragment) -replace "`r`n", "`n").Trim()
    $mdRecord = @{ path = 'CLAUDE.md'; created = $false; block_sha256 = (Get-TextSha256 -Text $body); backup = '' }
    if ($null -ne $prior -and (Test-HasProp $prior 'claude_md')) {
        if (Test-HasProp $prior.claude_md 'created') { $mdRecord.created = [bool]$prior.claude_md.created }
        if (Test-HasProp $prior.claude_md 'backup') { $mdRecord.backup = [string]$prior.claude_md.backup }
    }
    try {
        $s3.Count = 1
        if ([string]::IsNullOrWhiteSpace($body)) {
            throw "the fragment $([System.IO.Path]::GetFileName($src.Fragment)) is empty -- installing an empty managed block into somebody's always-on context is an install that reports a firing layer and delivers nothing"
        }
        $existing = ''
        $mdExisted = Test-Path -LiteralPath $claudeMd -PathType Leaf
        if ($mdExisted) { $existing = [System.IO.File]::ReadAllText($claudeMd) }
        else { $mdRecord.created = $true }
        $prev = Get-ManagedBlock -Text $existing
        $merged = Merge-ManagedBlock -Existing $existing -Body $body
        $lines = @($body -split "`n").Count

        if ($null -eq $prev) {
            Add-PlanLine $plan 'CLAUDE.md' '+' "managed block, $lines line(s)$(if ($mdExisted) { ' appended to the existing file' } else { ' (file created)' })"
        }
        elseif ((Get-TextSha256 -Text $prev.Trim()) -eq $mdRecord.block_sha256) {
            Add-PlanLine $plan 'CLAUDE.md' '=' "managed block already present and identical, $lines line(s)"
        }
        else {
            Add-PlanLine $plan 'CLAUDE.md' '~' "managed block replaced, $(@($prev.Trim() -split "`n").Count) line(s) -> $lines line(s)"
        }

        if (-not $dry -and (($existing -replace "`r`n", "`n") -cne $merged)) {
            $w = Write-TextChecked -Path $claudeMd -Text $merged -Bom $false
            if ($w.Backup) { $backupsTaken.Add((Get-RelUnder -FullName $w.Backup -Root $homeDir)) }
            # First backup only, same reason as the file records above.
            if ($mdExisted -and -not $mdRecord.created -and [string]::IsNullOrWhiteSpace([string]$mdRecord.backup) -and $w.Backup) {
                $mdRecord.backup = Get-RelUnder -FullName $w.Backup -Root $homeDir
            }
        }
    }
    catch {
        $s3.Fail($_.Exception.Message)
        return $result
    }
    $s3.Seal('no CLAUDE.md work recorded')

    # ── 4. settings.json ───────────────────────────────────────────────────────
    $s4 = [InstallStep]::new('Settings')
    $steps.Add($s4)
    $settingsPath = Join-Path $homeDir 'settings.json'
    $merge = $null
    $hookCommand = ''
    # Carried forward, like claude_md.created: install #2 finds the file present, and a manifest that
    # recorded only this run would forget that install #1 was the thing that brought it into
    # existence.
    $settingsCreated = $false
    if ($null -ne $prior -and (Test-HasProp $prior 'settings_created')) { $settingsCreated = [bool]$prior.settings_created }
    try {
        $loaded = Import-SettingsFile -Path $settingsPath
        if (-not $loaded.Existed) { $settingsCreated = $true }
        $hookGroup = $src.Floor.HookGroup
        if ($null -ne $hookGroup) {
            $tmplCmd = ''
            if (Test-HasProp $hookGroup 'hooks') {
                foreach ($h in @($hookGroup.hooks)) {
                    if (Test-HasProp $h 'command') { $tmplCmd = [string]$h.command; break }
                }
            }
            if ([string]::IsNullOrWhiteSpace($tmplCmd)) {
                throw "the floor's $($script:HookEvent) group carries no hook command -- it would install a matcher that runs nothing, which reads as enforcement and is not"
            }
            $hookCommand = Resolve-HookCommand -Template $tmplCmd -GuardTarget $Ctx.GuardTarget
        }
        $merge = Merge-PermissionFloor -Settings $loaded.Object -Deny $src.Floor.Deny -Ask $src.Floor.Ask `
            -HookGroup $hookGroup -HookCommand $hookCommand

        $s4.Count = @($merge.DenyAdded).Count + @($merge.AskAdded).Count + @($merge.HooksAdded).Count + @($merge.Present).Count
        foreach ($e in @($merge.DenyAdded)) { Add-PlanLine $plan 'settings.json' '+' "permissions.deny[]  $e" }
        foreach ($e in @($merge.AskAdded)) { Add-PlanLine $plan 'settings.json' '+' "permissions.ask[]   $e" }
        foreach ($h in @($merge.HooksAdded)) {
            Add-PlanLine $plan 'settings.json' '+' ("hooks.$($h.event)  matcher '$($h.matcher)'" +
                $(if ($h.group_created) { ' (new group)' } else { ' (appended to the existing group)' }) + " -> $($h.command)")
        }
        foreach ($e in @($merge.Present)) { Add-PlanLine $plan 'settings.json' '=' "already present: $e" }

        # UNION-MERGE ASSERTED, NOT ASSUMED: nothing that was in the file may be missing from the
        # candidate. This is the check that would catch a merge bug rewriting an array instead of
        # extending it -- the failure the recipient would only find the next time a rule they wrote
        # did not fire.
        if ($loaded.Existed) {
            $before = $null
            try { $before = [System.IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json } catch { $before = $null }
            if ($null -ne $before -and (Test-HasProp $before 'permissions')) {
                foreach ($k in @('deny', 'ask', 'allow')) {
                    if (-not (Test-HasProp $before.permissions $k)) { continue }
                    $now = @()
                    if (Test-HasProp $merge.Settings.permissions $k) { $now = @($merge.Settings.permissions.$k | ForEach-Object { [string]$_ }) }
                    foreach ($e in @($before.permissions.$k)) {
                        if ($now -cnotcontains [string]$e) {
                            $s4.Fail("permissions.$k entry '$e' was in $settingsPath and is not in the merged result -- the merge dropped something the recipient wrote. Nothing has been written.")
                        }
                    }
                }
            }
            if ($null -ne $before) {
                foreach ($p in @(Get-PropName -Object $before)) {
                    if (-not (Test-HasProp $merge.Settings $p)) {
                        $s4.Fail("top-level key '$p' was in $settingsPath and is not in the merged result. Nothing has been written.")
                    }
                }
            }
        }
        if ($s4.Status -eq 'FAIL') { return $result }

        if (-not $dry) {
            $changed = @($merge.DenyAdded).Count + @($merge.AskAdded).Count + @($merge.HooksAdded).Count
            if ($changed -gt 0 -or -not $loaded.Existed) {
                $w = Write-JsonChecked -Path $settingsPath -Object $merge.Settings -Fault $Ctx.FaultInject
                if ($w.Backup) {
                    $backupsTaken.Add((Get-RelUnder -FullName $w.Backup -Root $homeDir))
                    Add-PlanLine $plan 'settings.json' 'b' "backed up to $([System.IO.Path]::GetFileName($w.Backup))"
                }
            }
            else {
                Add-PlanLine $plan 'settings.json' '=' 'nothing to add -- not rewritten'
            }
        }
    }
    catch {
        $s4.Fail($_.Exception.Message)
        return $result
    }
    $s4.Seal("the floor merged into $settingsPath with zero entries either added or already present -- the floor was read as empty")
    if ($s4.Status -ne 'PASS') { return $result }

    # ── 5. MANIFEST ────────────────────────────────────────────────────────────
    $s5 = [InstallStep]::new('Manifest')
    $steps.Add($s5)
    $prov = Get-LayerProvenance -SourceRoot $Ctx.LayerRoot -SourceCommit $Ctx.SourceCommit
    $denyAll = [System.Collections.Generic.List[string]]::new()
    $askAll = [System.Collections.Generic.List[string]]::new()
    $hooksAll = [System.Collections.Generic.List[object]]::new()
    $backupsAll = [System.Collections.Generic.List[string]]::new()
    # Carried forward from the prior manifest and UNIONED. An entry install #1 added is still ours
    # after install #2, even though install #2 found it already present and added nothing.
    if ($null -ne $prior) {
        if (Test-HasProp $prior 'deny_added') { foreach ($e in @($prior.deny_added)) { $denyAll.Add([string]$e) } }
        if (Test-HasProp $prior 'ask_added') { foreach ($e in @($prior.ask_added)) { $askAll.Add([string]$e) } }
        if (Test-HasProp $prior 'hooks_added') { foreach ($h in @($prior.hooks_added)) { $hooksAll.Add($h) } }
        # DIRECTORIES AND BACKUPS ARE CARRIED FORWARD TOO, and forgetting them was a real defect
        # rather than a tidiness point. A second install copies nothing (every file is already there
        # and identical), so $dirsCreated is EMPTY on that run -- and writing the manifest from this
        # run alone silently replaced install #1's record of the four skill directories with []. The
        # uninstall then removed every file correctly and left the whole skills/ tree behind, in the
        # recipient's configuration, permanently, while reporting a clean removal. Measured over
        # install-install-uninstall on 2026-08-19; nothing inside a single install/uninstall pair can
        # see it.
        if (Test-HasProp $prior 'dirs_created') { foreach ($d in @($prior.dirs_created)) { $dirsCreated.Add([string]$d) } }
        if (Test-HasProp $prior 'backups') { foreach ($b in @($prior.backups)) { $backupsAll.Add([string]$b) } }
    }
    foreach ($b in @($backupsTaken)) { if ($backupsAll -cnotcontains $b) { $backupsAll.Add($b) } }
    foreach ($e in @($merge.DenyAdded)) { if ($denyAll -cnotcontains $e) { $denyAll.Add($e) } }
    foreach ($e in @($merge.AskAdded)) { if ($askAll -cnotcontains $e) { $askAll.Add($e) } }
    foreach ($h in @($merge.HooksAdded)) {
        $dup = $false
        foreach ($k in $hooksAll) { if ((Test-HasProp $k 'command') -and ([string]$k.command -ceq [string]$h.command)) { $dup = $true; break } }
        if (-not $dup) { $hooksAll.Add([pscustomobject]$h) }
    }

    $manifest = [pscustomobject]@{
        schema        = $script:ManifestSchema
        installed_utc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        source_commit = $prov.Commit
        source_state  = $prov.State
        # The full path, not a path relative to a guessed repository root. Two reasons: it is what a
        # recipient needs in order to re-run or uninstall, and the relative form was computed from
        # Split-Path -Parent twice, which returns the empty string for a layer sitting at a drive root
        # and takes GetFullPath('') with it.
        layer_root    = ([string]$Ctx.LayerRoot).Replace('\', '/')
        floor_source  = [System.IO.Path]::GetFileName($src.Floor.Path)
        settings_file = 'settings.json'
        settings_created = $settingsCreated
        deny_added    = (Get-SortedOrdinal -Values $denyAll.ToArray())
        ask_added     = (Get-SortedOrdinal -Values $askAll.ToArray())
        hooks_added   = $hooksAll.ToArray()
        claude_md     = [pscustomobject]$mdRecord
        files         = @($fileRecords | ForEach-Object { [pscustomobject]$_ })
        dirs_created  = (Get-SortedOrdinal -Values $dirsCreated.ToArray())
        # Named, not just counted, and NOT deleted by -Uninstall. These are the recipient's
        # pre-install copies of files this script had to overwrite; after a clean uninstall the live
        # file is already correct, so they are redundant -- but "redundant" is this script's opinion
        # and deleting somebody's only copy of their previous configuration on the strength of it is
        # not a trade worth making. -Uninstall names every one that is still there instead, which is
        # the same argument the pack builder makes for printing withheld files rather than counting
        # them: a decision reported as a number is a decision nobody revisits.
        backups       = (Get-SortedOrdinal -Values $backupsAll.ToArray())
    }
    $s5.Count = @($manifest.deny_added).Count + @($manifest.ask_added).Count + @($manifest.hooks_added).Count + @($manifest.files).Count + 1
    try {
        if ($dry) {
            Add-PlanLine $plan $script:ManifestName '+' "$($s5.Count) recorded item(s) -- what -Uninstall would remove, and the ONLY thing it removes"
        }
        else {
            $null = Write-JsonChecked -Path (Join-Path $homeDir $script:ManifestName) -Object $manifest -Fault '' -TakeBackup $false
            Add-PlanLine $plan $script:ManifestName '+' "$($s5.Count) recorded item(s)"
        }
        # The provenance is REPORTED, including when it is unresolved. It is a warning and not a
        # failure here (see Get-LayerProvenance), and a warning nobody prints is not a warning.
        $s5.Note = "$(@($manifest.deny_added).Count) deny, $(@($manifest.ask_added).Count) ask, $(@($manifest.hooks_added).Count) hook(s), $(@($manifest.files).Count) file(s), 1 managed block; source $(if ($prov.Commit) { $prov.Commit.Substring(0, [Math]::Min(12, $prov.Commit.Length)) } else { '<none>' }) ($($prov.State))"
    }
    catch {
        $s5.Fail($_.Exception.Message)
        return $result
    }
    $s5.Seal('the manifest records nothing -- an uninstall would remove nothing')
    $result.Manifest = $manifest

    # ── 6. VERIFY ──────────────────────────────────────────────────────────────
    # Read the RESULT off disk. "reported success" and "the configuration on disk is what was
    # reported" must not be able to come apart, which is the same last-step-reads-it-back rule the
    # pack builder ends on.
    $s6 = [InstallStep]::new('Verify')
    $steps.Add($s6)
    if ($dry) {
        $s6.Skip('nothing was written, so there is nothing to read back')
        return $result
    }
    try {
        $onDisk = Import-SettingsFile -Path $settingsPath
        $s6.Count++
        $haveDeny = @()
        if ((Test-HasProp $onDisk.Object 'permissions') -and (Test-HasProp $onDisk.Object.permissions 'deny')) {
            $haveDeny = @($onDisk.Object.permissions.deny | ForEach-Object { [string]$_ })
        }
        foreach ($e in @($src.Floor.Deny)) {
            if ($haveDeny -cnotcontains $e) { $s6.Fail("permissions.deny on disk does not contain '$e' after a reported successful install") }
        }
        # And no duplicates, which is what a non-idempotent merge produces on the second run.
        $dupes = @($haveDeny | Group-Object -CaseSensitive | Where-Object { $_.Count -gt 1 })
        foreach ($d in $dupes) { $s6.Fail("permissions.deny contains '$($d.Name)' $($d.Count) times -- the merge is not idempotent") }

        foreach ($f in @($manifest.files)) {
            $s6.Count++
            $t = Resolve-RecordPath -Rel ([string]$f.path) -HomeDir $homeDir
            if (-not (Test-Path -LiteralPath $t -PathType Leaf)) { $s6.Fail("$($f.path) is recorded as installed and is not on disk"); continue }
            if ((Get-FileSha256 -Path $t) -ne [string]$f.sha256) { $s6.Fail("$($f.path) is on disk with a different hash than the manifest records") }
        }

        $s6.Count++
        $blockNow = Get-ManagedBlock -Text ([System.IO.File]::ReadAllText($claudeMd))
        if ($null -eq $blockNow) { $s6.Fail("the managed block is not in $claudeMd after a reported successful install") }
        elseif ((Get-TextSha256 -Text $blockNow.Trim()) -ne [string]$manifest.claude_md.block_sha256) {
            $s6.Fail("the managed block in $claudeMd does not match the fragment that was installed")
        }
        # Exactly one block, not two. The append-a-second-block bug produces a file where the layer
        # still works, so nothing else here would notice.
        $count = ([regex]::Matches(([System.IO.File]::ReadAllText($claudeMd) -replace "`r`n", "`n"), [regex]::Escape($script:BlockBegin))).Count
        if ($count -ne 1) { $s6.Fail("$claudeMd contains $count managed-block begin markers -- there must be exactly one") }
    }
    catch {
        $s6.Fail($_.Exception.Message)
    }
    $s6.Seal('verified nothing -- the read-back walk is broken')
    return $result
}

# ── UNINSTALL ───────────────────────────────────────────────────────────────────

function Invoke-LayerUninstall {
    param([hashtable]$Ctx)

    $steps = [System.Collections.Generic.List[object]]::new()
    $plan = [System.Collections.Generic.List[object]]::new()
    $result = @{ Steps = $steps; Plan = $plan; Manifest = $null }
    $dry = [bool]$Ctx.DryRun
    $homeDir = $Ctx.ClaudeHome
    $manifestPath = Join-Path $homeDir $script:ManifestName

    $s0 = [InstallStep]::new('Manifest')
    $steps.Add($s0)
    $m = $null
    try { $m = Import-InstallManifest -Path $manifestPath }
    catch { $s0.Fail($_.Exception.Message); return $result }
    if ($null -eq $m) {
        # NOT a pass, and not a failure either: there is nothing recorded, so there is nothing this
        # script is entitled to remove. Guessing from the floor template is the one thing an
        # uninstall must never do -- it would delete rules the recipient wrote that happen to also
        # be in it.
        $s0.Skip("no $($script:ManifestName) in $homeDir -- nothing recorded as installed, so nothing removed. This installer will not reconstruct what to delete from the floor template: that would eat any rule the recipient wrote that the template also carries.")
        return $result
    }
    $s0.Count = 1
    $s0.Note = "installed $(Format-Utc -Value $m.installed_utc) from commit $(if ([string]::IsNullOrWhiteSpace([string]$m.source_commit)) { '<unresolved>' } else { ([string]$m.source_commit).Substring(0, [Math]::Min(12, ([string]$m.source_commit).Length)) })"
    $result.Manifest = $m

    # ── settings.json ──────────────────────────────────────────────────────────
    $s1 = [InstallStep]::new('Settings')
    $steps.Add($s1)
    $settingsPath = Join-Path $homeDir 'settings.json'
    try {
        $loaded = Import-SettingsFile -Path $settingsPath
        if (-not $loaded.Existed) {
            $s1.Skip("$settingsPath does not exist -- nothing to unmerge")
        }
        else {
            $changed = 0
            if (Test-HasProp $loaded.Object 'permissions') {
                foreach ($pair in @(@{ Key = 'deny'; Recorded = @($m.deny_added) }, @{ Key = 'ask'; Recorded = @($m.ask_added) })) {
                    $key = $pair.Key
                    if (-not (Test-HasProp $loaded.Object.permissions $key)) { continue }
                    $keep = [System.Collections.Generic.List[string]]::new()
                    $drop = [System.Collections.Generic.List[string]]::new()
                    $recorded = @($pair.Recorded | ForEach-Object { [string]$_ })
                    foreach ($e in @($loaded.Object.permissions.$key)) {
                        $s = [string]$e
                        if ($recorded -ccontains $s) { $drop.Add($s) } else { $keep.Add($s) }
                    }
                    foreach ($e in $recorded) {
                        $s1.Count++
                        if ($drop -cnotcontains $e) { Add-PlanLine $plan 'settings.json' '.' "permissions.$key[] '$e' already gone" }
                    }
                    foreach ($e in $drop) { Add-PlanLine $plan 'settings.json' '-' "permissions.$key[]  $e" }
                    if ($drop.Count -gt 0) {
                        $changed += $drop.Count
                        if (-not $dry) { $loaded.Object.permissions.$key = $keep.ToArray() }
                    }
                }
            }

            if ((Test-HasProp $loaded.Object 'hooks') -and (Test-HasProp $loaded.Object.hooks $script:HookEvent)) {
                $groups = [System.Collections.Generic.List[object]]::new()
                foreach ($g in @($loaded.Object.hooks.$($script:HookEvent))) { if ($null -ne $g) { $groups.Add($g) } }
                foreach ($rec in @($m.hooks_added)) {
                    $s1.Count++
                    $recCmd = [string]$rec.command
                    $recMatcher = if (Test-HasProp $rec 'matcher') { [string]$rec.matcher } else { '' }
                    $group = $null
                    foreach ($g in $groups) {
                        if ((Test-HasProp $g 'matcher') -and ([string]$g.matcher -ceq $recMatcher)) { $group = $g; break }
                    }
                    if ($null -eq $group) { Add-PlanLine $plan 'settings.json' '.' "hooks.$($script:HookEvent) matcher '$recMatcher' already gone"; continue }
                    $inner = [System.Collections.Generic.List[object]]::new()
                    foreach ($h in @($group.hooks)) { if ($null -ne $h) { $inner.Add($h) } }
                    $hit = $null
                    foreach ($h in $inner) { if ((Test-HasProp $h 'command') -and ([string]$h.command -ceq $recCmd)) { $hit = $h; break } }
                    if ($null -eq $hit) {
                        # The command string is the identity, so a command that has been EDITED reads
                        # as absent here. Reported as such rather than as "already gone", because the
                        # two are indistinguishable from this side and only one of them is finished.
                        Add-PlanLine $plan 'settings.json' '.' "hooks.$($script:HookEvent) '$recCmd' not found -- removed already, or the command was edited by hand (left alone either way)"
                        continue
                    }
                    # Present, but has it been adjusted? A recipient who changed the timeout has
                    # taken ownership of this entry.
                    $recHook = if (Test-HasProp $rec 'hook') { $rec.hook } else { $null }
                    $sameShape = $true
                    if ($null -ne $recHook) {
                        $a = ($recHook | ConvertTo-Json -Depth 20 -Compress)
                        $b = ($hit | ConvertTo-Json -Depth 20 -Compress)
                        $sameShape = ($a -ceq $b)
                    }
                    if (-not $sameShape) {
                        $s1.Decline("hooks.$($script:HookEvent) entry for '$recCmd' has been modified since it was installed (it now reads $($hit | ConvertTo-Json -Depth 20 -Compress)). Left in place. Remove it by hand if you want it gone.")
                        continue
                    }
                    Add-PlanLine $plan 'settings.json' '-' "hooks.$($script:HookEvent)  $recCmd"
                    $changed++
                    if (-not $dry) {
                        $kept = [System.Collections.Generic.List[object]]::new()
                        foreach ($h in $inner) { if (-not ((Test-HasProp $h 'command') -and ([string]$h.command -ceq $recCmd))) { $kept.Add($h) } }
                        $group.hooks = $kept.ToArray()
                        # Remove the GROUP only if this script created it and it is now empty. A group
                        # the recipient already had stays, empty or not: it is theirs.
                        $created = (Test-HasProp $rec 'group_created') -and ([bool]$rec.group_created)
                        if ($created -and $kept.Count -eq 0) {
                            $groups.Remove($group) | Out-Null
                            Add-PlanLine $plan 'settings.json' '-' "hooks.$($script:HookEvent) matcher '$recMatcher' (the group this installer created, now empty)"
                        }
                    }
                }
                if (-not $dry) { $loaded.Object.hooks.$($script:HookEvent) = $groups.ToArray() }
            }

            if ($changed -gt 0) {
                $ourFile = (Test-HasProp $m 'settings_created') -and ([bool]$m.settings_created)
                if ($ourFile -and (Test-SettingsIsVacuous -Object $loaded.Object)) {
                    Add-PlanLine $plan 'settings.json' '-' 'the file itself -- this installer created it and nothing but empty containers is left in it'
                    if (-not $dry) { [System.IO.File]::Delete($settingsPath) }
                }
                elseif (-not $dry) {
                    $w = Write-JsonChecked -Path $settingsPath -Object $loaded.Object -Fault $Ctx.FaultInject
                    if ($w.Backup) { Add-PlanLine $plan 'settings.json' 'b' "backed up to $([System.IO.Path]::GetFileName($w.Backup)) before the unmerge -- left in place" }
                }
            }
            else {
                Add-PlanLine $plan 'settings.json' '.' 'nothing of ours left in it -- not rewritten'
            }
        }
    }
    catch { $s1.Fail($_.Exception.Message) }
    $s1.Seal('the manifest recorded no permission or hook entries -- nothing to unmerge')

    # ── CLAUDE.md ──────────────────────────────────────────────────────────────
    $s2 = [InstallStep]::new('ClaudeMd')
    $steps.Add($s2)
    $claudeMd = Join-Path $homeDir 'CLAUDE.md'
    try {
        $s2.Count = 1
        if (-not (Test-Path -LiteralPath $claudeMd -PathType Leaf)) {
            Add-PlanLine $plan 'CLAUDE.md' '.' 'already gone'
        }
        else {
            $text = [System.IO.File]::ReadAllText($claudeMd)
            $block = Get-ManagedBlock -Text $text
            if ($null -eq $block) {
                Add-PlanLine $plan 'CLAUDE.md' '.' 'no managed block -- already removed'
            }
            elseif ((Get-TextSha256 -Text $block.Trim()) -cne [string]$m.claude_md.block_sha256) {
                $s2.Decline("the managed block in $claudeMd has been edited since it was installed. Left exactly as it is -- reverting it would throw away whatever was changed. Delete the block by hand, markers included, if you want it gone.")
            }
            else {
                $rest = Get-TextWithoutBlock -Text $text
                $created = (Test-HasProp $m.claude_md 'created') -and ([bool]$m.claude_md.created)
                if ([string]::IsNullOrWhiteSpace($rest) -and $created) {
                    Add-PlanLine $plan 'CLAUDE.md' '-' 'managed block, and the file (this installer created it and nothing else is in it)'
                    if (-not $dry) { [System.IO.File]::Delete($claudeMd) }
                }
                else {
                    Add-PlanLine $plan 'CLAUDE.md' '-' "managed block, $(@($block.Trim() -split "`n").Count) line(s); the rest of the file is left alone"
                    if (-not $dry) {
                        $w = Write-TextChecked -Path $claudeMd -Text $rest -Bom $false
                        # Named here as well as in the Backups step. That step reads the MANIFEST, which
                        # was written at install time and cannot know about a backup this uninstall is
                        # taking right now -- so without this line the uninstall leaves a .bak-<stamp>
                        # in the recipient's configuration directory and names only the older one.
                        if ($w.Backup) { Add-PlanLine $plan 'CLAUDE.md' 'b' "backed up to $([System.IO.Path]::GetFileName($w.Backup)) before the block was cut out -- left in place" }
                    }
                }
            }
        }
    }
    catch { $s2.Fail($_.Exception.Message) }
    $s2.Seal('no CLAUDE.md record in the manifest')

    # ── files ──────────────────────────────────────────────────────────────────
    $s3 = [InstallStep]::new('Files')
    $steps.Add($s3)
    $survivors = 0
    try {
        foreach ($f in @($m.files)) {
            $s3.Count++
            $rel = [string]$f.path
            $t = Resolve-RecordPath -Rel $rel -HomeDir $homeDir
            if (-not (Test-Path -LiteralPath $t -PathType Leaf)) { Add-PlanLine $plan $rel '.' 'already gone'; continue }
            if ((Get-FileSha256 -Path $t) -cne [string]$f.sha256) {
                $s3.Decline("$rel has been modified since it was installed. Left in place -- deleting it would throw the edit away. Remove it by hand if you want it gone.")
                $survivors++
                continue
            }
            $bak = if (Test-HasProp $f 'backup') { [string]$f.backup } else { '' }
            if (-not [string]::IsNullOrWhiteSpace($bak)) {
                $bakFull = Resolve-RecordPath -Rel $bak -HomeDir $homeDir
                if (Test-Path -LiteralPath $bakFull -PathType Leaf) {
                    Add-PlanLine $plan $rel '-' "removed, and the pre-install file restored from $([System.IO.Path]::GetFileName($bakFull))"
                    if (-not $dry) {
                        [System.IO.File]::Copy($bakFull, $t, $true)
                        [System.IO.File]::Delete($bakFull)
                    }
                    continue
                }
                Add-PlanLine $plan $rel '-' "removed; the recorded backup $bak is gone, so there is nothing to restore"
            }
            else {
                Add-PlanLine $plan $rel '-' 'removed'
            }
            if (-not $dry) { [System.IO.File]::Delete($t) }
        }

        # Directories this script created, deepest first, and ONLY if empty. A skills directory the
        # recipient has put their own skill into is not ours to delete.
        $dirs = @()
        if (Test-HasProp $m 'dirs_created') { $dirs = @($m.dirs_created | ForEach-Object { [string]$_ }) }
        foreach ($d in @($dirs | Sort-Object -Property Length -Descending)) {
            $full = Resolve-RecordPath -Rel $d -HomeDir $homeDir
            if (-not (Test-Path -LiteralPath $full -PathType Container)) { continue }
            $remaining = @(Get-ChildItem -LiteralPath $full -Force -ErrorAction SilentlyContinue)
            if ($remaining.Count -gt 0) {
                Add-PlanLine $plan "$d/" '.' "left in place -- $($remaining.Count) item(s) still in it"
                continue
            }
            Add-PlanLine $plan "$d/" '-' 'empty directory this installer created'
            if (-not $dry) { [System.IO.Directory]::Delete($full, $false) }
        }
    }
    catch { $s3.Fail($_.Exception.Message) }
    $s3.Seal('the manifest records no files')

    # ── the recipient's pre-install backups ────────────────────────────────────
    # NAMED AND LEFT ALONE. These are their copies of files this installer had to overwrite. After a
    # clean uninstall the live files are already correct, so the backups are redundant -- but
    # "redundant" is this script's opinion, and acting on it means deleting somebody's only copy of
    # their previous configuration. Reported instead, by name, so the tidying is their call and not a
    # surprise they find in six months. The alternative that was rejected is silence, which is how a
    # configuration directory fills up with files nobody can date.
    $sB = [InstallStep]::new('Backups')
    $steps.Add($sB)
    try {
        $left = [System.Collections.Generic.List[string]]::new()
        foreach ($b in @($m.backups)) {
            $sB.Count++
            $full = Resolve-RecordPath -Rel ([string]$b) -HomeDir $homeDir
            if (Test-Path -LiteralPath $full -PathType Leaf) { $left.Add([string]$b) }
        }
        foreach ($b in $left) { Add-PlanLine $plan $b '.' 'LEFT IN PLACE -- your pre-install copy; delete it yourself when you are satisfied' }
        $sB.Note = if ($left.Count -eq 0) { 'no pre-install backup files are still on disk' }
        else { "$($left.Count) pre-install backup file(s) left in place, named above -- this script does not delete your only copy of your previous configuration" }
    }
    catch { $sB.Fail($_.Exception.Message) }
    # Deliberately NOT Sealed. Zero backups is the normal case for a first-time install that
    # overwrote nothing, and INCONCLUSIVE would turn the commonest clean run red.

    # ── the manifest itself ────────────────────────────────────────────────────
    $s4 = [InstallStep]::new('Record')
    $steps.Add($s4)
    $s4.Count = 1
    $declined = @($steps | Where-Object { $_.Status -eq 'SKIPPED' -and $_.Findings.Count -gt 0 }).Count
    if ($declined -gt 0 -or $survivors -gt 0) {
        $s4.Skip("$($script:ManifestName) KEPT, because something was declined and is still installed. Run -Uninstall again once you have looked at it and it will finish the job.")
        Add-PlanLine $plan $script:ManifestName '.' 'kept -- the uninstall is incomplete'
    }
    else {
        Add-PlanLine $plan $script:ManifestName '-' 'removed'
        if (-not $dry) {
            if (Test-Path -LiteralPath $manifestPath -PathType Leaf) { [System.IO.File]::Delete($manifestPath) }
        }
    }
    return $result
}

function Get-LayerExit {
    # FAIL ahead of SKIPPED ahead of PASS. The order is the contract: a skip must never mask a
    # failure, and a skip -- including a DECLINE -- must never be reported as a pass.
    param([object[]]$Steps, [bool]$DryRun)
    if (@($Steps | Where-Object { $_.Status -in @('FAIL', 'INCONCLUSIVE') }).Count -gt 0) { return 1 }
    if ($DryRun) { return 2 }
    if (@($Steps | Where-Object { $_.Status -eq 'SKIPPED' }).Count -gt 0) { return 2 }
    return 0
}

# ── SELF-TEST ───────────────────────────────────────────────────────────────────
# Negative controls, in the shape the gates and the builder use. The point is not that the installer
# works on a good day: it is that each guarantee it claims FAILS when it should. A control that has
# only ever been green is not evidence.
#
# EVERY CONTROL RUNS AGAINST A TEMP DIRECTORY. The live configuration is never a subject here, and
# the entry point below refuses -SelfTest against the default -ClaudeHome for that reason -- an
# installer's self-test that can reach the thing it installs into is not a test, it is an install.

function Assert-Case {
    param([string]$Name, [string]$Expected, [string]$Actual)
    $ok = $Expected -eq $Actual
    $mark = if ($ok) { 'ok  ' } else { 'FAIL' }
    Write-Host ("  [{0}] {1,-70} expected {2}, got {3}" -f $mark, $Name, $Expected, $Actual)
    return $ok
}

function Assert-Exit {
    # Assert an exit code AND print the findings when it is wrong. Written after the plain form cost
    # a debugging round: "expected 2, got 1" names the contract that broke and says nothing about
    # which step broke it, and a self-test that can only tell you that something failed makes you
    # add print statements to find out -- which is the state a suite is in just before somebody
    # stops running it.
    param([string]$Name, [string]$Expected, [object]$Run, [bool]$DryRun)
    $ok = Assert-Case $Name $Expected "$(Get-LayerExit -Steps @($Run.Steps) -DryRun $DryRun)"
    if (-not $ok) {
        foreach ($s in @($Run.Steps)) {
            if ($s.Status -eq 'PASS') { continue }
            Write-Host ("         {0} {1}: {2} {3}" -f $s.Name, $s.Status, (@($s.Findings) -join ' | '), $s.Note) -ForegroundColor DarkYellow
        }
    }
    return $ok
}

function Write-LayerFixture {
    # A layer-shaped source tree: one fragment, two skills (one of them with a nested file, so the
    # recursive walk is exercised rather than assumed), a minimal floor template carrying the hook
    # placeholder, and a guard script.
    param([string]$Root)
    $null = [System.IO.Directory]::CreateDirectory((Join-Path $Root 'skills/alpha/references'))
    $null = [System.IO.Directory]::CreateDirectory((Join-Path $Root 'skills/beta'))
    [System.IO.File]::WriteAllText((Join-Path $Root 'CLAUDE-FRAGMENT.md'), "## Practice layer`n`nAlways do the thing.`n")
    [System.IO.File]::WriteAllText((Join-Path $Root 'skills/alpha/SKILL.md'), "---`nname: alpha`n---`nalpha`n")
    [System.IO.File]::WriteAllText((Join-Path $Root 'skills/alpha/references/more.md'), "more`n")
    [System.IO.File]::WriteAllText((Join-Path $Root 'skills/beta/SKILL.md'), "---`nname: beta`n---`nbeta`n")
    [System.IO.File]::WriteAllText((Join-Path $Root 'secret-guard.ps1'), "# fixture guard`nexit 0`n")
    $floor = @{
        permissions = @{
            deny  = @('Bash(rm -rf /)', 'Read(**/.env)')
            ask   = @('Bash(git push*)')
            allow = @()
        }
        hooks       = @{
            PreToolUse = @(@{
                    matcher = 'Bash|PowerShell'
                    hooks   = @(@{ type = 'command'; command = 'pwsh -NoProfile -File <<HOOKS_DIR>>/secret-guard.ps1'; timeout = 10 })
                })
        }
    }
    [System.IO.File]::WriteAllText((Join-Path $Root 'settings.template.json'), ($floor | ConvertTo-Json -Depth 20))
}

function Get-FixtureContext {
    param([string]$LayerRoot, [string]$ClaudeHome, [bool]$DryRun, [bool]$Force, [string]$FaultInject)
    $hooks = Join-Path $ClaudeHome 'hooks'
    return @{
        ClaudeHome    = $ClaudeHome
        LayerRoot     = $LayerRoot
        FragmentPath  = ''
        SkillsRoot    = (Join-Path $LayerRoot 'skills')
        FloorTemplate = (Join-Path $LayerRoot 'settings.template.json')
        GuardScript   = (Join-Path $LayerRoot 'secret-guard.ps1')
        HooksDir      = $hooks
        GuardTarget   = (Join-Path $hooks $script:GuardName)
        SourceCommit  = ('a' * 40)
        DryRun        = $DryRun
        Force         = $Force
        FaultInject   = $FaultInject
    }
}

function Invoke-LayerSelfTest {
    param([string]$RealFloor, [string]$RealGuard)

    Write-Host "SELF-TEST -- negative controls" -ForegroundColor Cyan
    $failures = 0
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("practice-layer-selftest-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $null = [System.IO.Directory]::CreateDirectory($tmp)
    $layer = Join-Path $tmp 'layer'
    Write-LayerFixture -Root $layer

    try {
        # ── DISCOVERY: the sibling's files are not this script's to assume ─────────
        $bare = Join-Path $tmp 'bare'; $null = [System.IO.Directory]::CreateDirectory($bare)
        $threw = $false; $msg = ''
        try { $null = Get-LayerFragment -LayerRoot $bare -FragmentPath '' } catch { $threw = $true; $msg = $_.Exception.Message }
        if (-not (Assert-Case 'no fragment: raises rather than installing half a layer' 'True' $threw.ToString())) { $failures++ }
        if (-not (Assert-Case '...and the message names what it looked for' 'True' ($msg -match 'CLAUDE-FRAGMENT').ToString())) { $failures++ }

        $ambig = Join-Path $tmp 'ambig'; $null = [System.IO.Directory]::CreateDirectory($ambig)
        [System.IO.File]::WriteAllText((Join-Path $ambig 'CLAUDE-FRAGMENT.md'), "a`n")
        [System.IO.File]::WriteAllText((Join-Path $ambig 'CLAUDE-FRAGMENT-v2.md'), "b`n")
        $threw = $false
        try { $null = Get-LayerFragment -LayerRoot $ambig -FragmentPath '' } catch { $threw = $true }
        if (-not (Assert-Case 'two candidate fragments: raises rather than picking one' 'True' $threw.ToString())) { $failures++ }

        $threw = $false
        try { $null = Get-LayerSkill -SkillsRoot (Join-Path $bare 'skills') } catch { $threw = $true }
        if (-not (Assert-Case 'no skills directory: raises' 'True' $threw.ToString())) { $failures++ }
        $emptySkills = Join-Path $tmp 'empty-skills/skills'; $null = [System.IO.Directory]::CreateDirectory($emptySkills)
        $threw = $false
        try { $null = Get-LayerSkill -SkillsRoot $emptySkills } catch { $threw = $true }
        if (-not (Assert-Case 'a skills directory holding no skill: raises, never installs zero' 'True' $threw.ToString())) { $failures++ }
        $null = [System.IO.Directory]::CreateDirectory((Join-Path $emptySkills 'gamma'))
        $threw = $false
        try { $null = Get-LayerSkill -SkillsRoot $emptySkills } catch { $threw = $true }
        if (-not (Assert-Case 'a skill directory with no SKILL.md: raises' 'True' $threw.ToString())) { $failures++ }
        # THE ARRAY-SHAPE CONTROLS. Both polarities, because the two failures are opposite and each
        # looks like a clean run: a one-element result unrolling to a scalar reports ZERO skills, and a
        # `return ,$array` wrapper reports ONE skill whose Name is every name joined together. The
        # second is not hypothetical -- it was the state of this file until the control below was
        # written, and the first symptom was a directory being created with two paths concatenated.
        $oneSkill = Join-Path $tmp 'one-skill/skills'; $null = [System.IO.Directory]::CreateDirectory((Join-Path $oneSkill 'solo'))
        [System.IO.File]::WriteAllText((Join-Path $oneSkill 'solo/SKILL.md'), "solo`n")
        if (-not (Assert-Case 'a one-skill layer counts as one skill, not zero' '1' "$(@(Get-LayerSkill -SkillsRoot $oneSkill).Count)")) { $failures++ }
        if (-not (Assert-Case '...and its name is a string, not a collection' 'solo' "$(@(Get-LayerSkill -SkillsRoot $oneSkill)[0].Name)")) { $failures++ }
        $two = @(Get-LayerSkill -SkillsRoot (Join-Path $layer 'skills'))
        if (-not (Assert-Case 'a two-skill layer counts as two, not as one wrapper' '2' "$($two.Count)")) { $failures++ }
        if (-not (Assert-Case '...and each name is its own, not the join of both' 'alpha|beta' (@($two | ForEach-Object { $_.Name }) -join '|'))) { $failures++ }

        # ── THE FLOOR IS READ, NEVER RESTATED ─────────────────────────────────────
        $threw = $false
        try { $null = Import-FloorTemplate -Path (Join-Path $tmp 'no-such-template.json') } catch { $threw = $true }
        if (-not (Assert-Case 'a missing floor template raises, never a remembered fallback' 'True' $threw.ToString())) { $failures++ }
        [System.IO.File]::WriteAllText((Join-Path $tmp 'empty-floor.json'), '{"permissions":{"deny":[],"ask":[],"allow":[]}}')
        $threw = $false
        try { $null = Import-FloorTemplate -Path (Join-Path $tmp 'empty-floor.json') } catch { $threw = $true }
        if (-not (Assert-Case 'a floor with no deny and no ask raises -- that is not a floor' 'True' $threw.ToString())) { $failures++ }
        # ...and the SHIPPED template loads and yields a real floor. This is the control that ties
        # this installer to the artifact that has its own suite, rather than to a fixture.
        if (Test-Path -LiteralPath $RealFloor) {
            $real = Import-FloorTemplate -Path $RealFloor
            if (-not (Assert-Case 'the shipped floor template loads and carries deny entries' 'True' (@($real.Deny).Count -gt 20).ToString())) { $failures++ }
            if (-not (Assert-Case '...and its hook group, so the guard really gets wired' 'True' ($null -ne $real.HookGroup).ToString())) { $failures++ }
        }
        else {
            Write-Host "  [SKIP] the shipped floor template is not at $RealFloor" -ForegroundColor Yellow
            $failures++
        }

        # ── THE HOOK COMMAND: THE APOSTROPHE LESSON, IN JSON'S SUBSTRATE ───────────
        $expect = 'pwsh -NoProfile -File "C:/Users/O' + [char]39 + 'Brien/.claude/hooks/secret-guard.ps1"'
        $q = Resolve-HookCommand -Template 'pwsh -NoProfile -File <<HOOKS_DIR>>/secret-guard.ps1' -GuardTarget "C:/Users/O'Brien/.claude/hooks/secret-guard.ps1"
        if (-not (Assert-Case 'a path with an apostrophe is emitted double-quoted' $expect $q)) { $failures++ }
        # Backslashes are normalised, so the emitted command is not full of shell escapes either.
        $bs = Resolve-HookCommand -Template 'pwsh -File <<HOOKS_DIR>>/secret-guard.ps1' -GuardTarget 'C:\h k\secret-guard.ps1'
        if (-not (Assert-Case '...and a path with a space is quoted, with forward slashes' 'pwsh -File "C:/h k/secret-guard.ps1"' $bs)) { $failures++ }
        # A template this function cannot resolve EXACTLY must raise. Best-effort substitution here
        # produces a hook pointing somewhere unverified, and a PreToolUse hook whose file is missing
        # fails silently on every single tool call.
        $threw = $false
        try { $null = Resolve-HookCommand -Template 'pwsh -File <<SOMETHING_ELSE>>/x.ps1' -GuardTarget 'C:/h/secret-guard.ps1' } catch { $threw = $true }
        if (-not (Assert-Case 'a template with no resolvable placeholder raises' 'True' $threw.ToString())) { $failures++ }
        # ...and the leftover-placeholder guard is REACHABLE rather than decorative.
        $threw = $false
        try { $null = Resolve-HookCommand -Template 'pwsh -File <<HOOKS_DIR>>/secret-guard.ps1 -Log <<HOOKS_DIR>>/g.log' -GuardTarget 'C:/h/secret-guard.ps1' } catch { $threw = $true }
        if (-not (Assert-Case 'a placeholder left over after substitution raises' 'True' $threw.ToString())) { $failures++ }
        if (-not (Assert-Case 'a $ in the path is reported as shell-hostile' '$' "$((Test-ShellSafePath -Path 'C:/Users/a$b/.claude') -join ',')")) { $failures++ }
        if (-not (Assert-Case 'a backtick in the path is reported as shell-hostile' '`' "$((Test-ShellSafePath -Path ('C:/Users/a' + [char]96 + 'b/.claude')) -join ',')")) { $failures++ }
        if (-not (Assert-Case "...and an apostrophe is NOT -- double-quoting handles it" '' "$((Test-ShellSafePath -Path "C:/Users/O'Brien/.claude") -join ',')")) { $failures++ }
        # THE PHANTOM-ELEMENT CONTROL, and it is the sharpest one in this file. A -join over a
        # comma-wrapped empty array is '' whether the array holds nothing or holds one empty string,
        # so the assertion above passes in BOTH states -- and in the second, .Count is 1, and the
        # pre-flight refuses every install on every machine. The COUNT is the property that
        # distinguishes them, so the count is what is asserted.
        if (-not (Assert-Case '...and a clean path yields ZERO entries, not one empty one' '0' "$(@(Test-ShellSafePath -Path 'C:/Users/plain/.claude').Count)")) { $failures++ }
        if (-not (Assert-Case '...while a hostile path yields exactly one' '1' "$(@(Test-ShellSafePath -Path 'C:/Users/a$b/.claude').Count)")) { $failures++ }
        # The same idiom, the same trap, on the directory walk -- where the phantom '' reached
        # GetFullPath and threw.
        if (-not (Assert-Case 'an already-existing directory needs ZERO ancestors created' '0' "$(@(Get-MissingAncestor -Dir $tmp -Stop $tmp).Count)")) { $failures++ }
        if (-not (Assert-Case '...and a three-deep missing path needs three, outermost first' '3' "$(@(Get-MissingAncestor -Dir (Join-Path $tmp 'p/q/r') -Stop $tmp).Count)")) { $failures++ }
        if (-not (Assert-Case '...and an object with no properties yields ZERO names' '0' "$(@(Get-PropName -Object ([pscustomobject]@{})).Count)")) { $failures++ }

        # ── AN UNPARSEABLE settings.json IS REFUSED, NOT REPAIRED ─────────────────
        $bad = Join-Path $tmp 'bad-home'; $null = [System.IO.Directory]::CreateDirectory($bad)
        $badJson = "{`n  `"permissions`": {`n    `"deny`": [`"Bash(rm -rf /)`",`n  }`n"
        [System.IO.File]::WriteAllText((Join-Path $bad 'settings.json'), $badJson)
        $threw = $false; $msg = ''
        try { $null = Import-SettingsFile -Path (Join-Path $bad 'settings.json') } catch { $threw = $true; $msg = $_.Exception.Message }
        if (-not (Assert-Case 'an unparseable settings.json raises' 'True' $threw.ToString())) { $failures++ }
        if (-not (Assert-Case '...and says it will not repair it' 'True' ($msg -match 'refusing to repair').ToString())) { $failures++ }
        $r = Invoke-LayerInstall -Ctx (Get-FixtureContext -LayerRoot $layer -ClaudeHome $bad -DryRun $false -Force $false -FaultInject '')
        if (-not (Assert-Exit '...and the INSTALL fails on it' '1' $r $false)) { $failures++ }
        if (-not (Assert-Case '...leaving the broken file byte-identical (no repair, no backup swap)' 'True' ([System.IO.File]::ReadAllText((Join-Path $bad 'settings.json')) -eq $badJson).ToString())) { $failures++ }

        # A file that parses but is shaped wrong is the same defect wearing valid JSON.
        $shape = Join-Path $tmp 'shape-home'; $null = [System.IO.Directory]::CreateDirectory($shape)
        [System.IO.File]::WriteAllText((Join-Path $shape 'settings.json'), '{"permissions":{"deny":"Bash(rm -rf /)"}}')
        $threw = $false
        try { $null = Import-SettingsFile -Path (Join-Path $shape 'settings.json') } catch { $threw = $true }
        if (-not (Assert-Case 'a deny list that is a STRING is refused, not merged into' 'True' $threw.ToString())) { $failures++ }
        # THE OTHER POLARITY, and without it the control above passes against a shape check that
        # refuses EVERYTHING -- which is the state this file was in until the empty-array return was
        # fixed: every valid settings file was reported malformed, with the finding text reading
        # `System.String[]`.
        if (-not (Assert-Case '...and a well-shaped one produces ZERO findings' '0' "$(@(Test-SettingsShape -Object ('{"permissions":{"deny":["a"],"allow":[]},"model":"x"}' | ConvertFrom-Json) -Label 'fixture').Count)")) { $failures++ }
        if (-not (Assert-Case '...and so does a completely empty object' '0' "$(@(Test-SettingsShape -Object ([pscustomobject]@{}) -Label 'fixture').Count)")) { $failures++ }
        if (-not (Assert-Case '...while a hooks block that is an array produces exactly one' '1' "$(@(Test-SettingsShape -Object ('{"hooks":[1,2]}' | ConvertFrom-Json) -Label 'fixture').Count)")) { $failures++ }

        # ── DRY RUN WRITES NOTHING ────────────────────────────────────────────────
        $dryHome = Join-Path $tmp 'dry-home'
        $r = Invoke-LayerInstall -Ctx (Get-FixtureContext -LayerRoot $layer -ClaudeHome $dryHome -DryRun $true -Force $false -FaultInject '')
        if (-not (Assert-Exit 'a dry run reports SKIPPED, never PASS' '2' $r $true)) { $failures++ }
        if (-not (Assert-Case '...and creates no settings.json' 'False' "$(Test-Path -LiteralPath (Join-Path $dryHome 'settings.json'))")) { $failures++ }
        if (-not (Assert-Case '...and no CLAUDE.md' 'False' "$(Test-Path -LiteralPath (Join-Path $dryHome 'CLAUDE.md'))")) { $failures++ }
        if (-not (Assert-Case '...and no skill files' 'False' "$(Test-Path -LiteralPath (Join-Path $dryHome 'skills/alpha/SKILL.md'))")) { $failures++ }
        if (-not (Assert-Case '...and no manifest' 'False' "$(Test-Path -LiteralPath (Join-Path $dryHome $script:ManifestName))")) { $failures++ }
        if (-not (Assert-Case '...and it printed a real plan rather than a sentence' 'True' (@($r.Plan).Count -gt 5).ToString())) { $failures++ }

        # ── CLEAN INSTALL, THEN AGAIN (IDEMPOTENT) ────────────────────────────────
        $homeDir = Join-Path $tmp 'home'
        $ctx = Get-FixtureContext -LayerRoot $layer -ClaudeHome $homeDir -DryRun $false -Force $false -FaultInject ''
        $r = Invoke-LayerInstall -Ctx $ctx
        if (-not (Assert-Exit 'a clean install passes' '0' $r $false)) { $failures++ }
        if (-not (Assert-Case '...the skill files are on disk' 'True' "$(Test-Path -LiteralPath (Join-Path $homeDir 'skills/alpha/references/more.md'))")) { $failures++ }
        if (-not (Assert-Case '...the guard is on disk where the hook points' 'True' "$(Test-Path -LiteralPath (Join-Path $homeDir 'hooks/secret-guard.ps1'))")) { $failures++ }
        $set1 = [System.IO.File]::ReadAllText((Join-Path $homeDir 'settings.json')) | ConvertFrom-Json
        if (-not (Assert-Case '...deny carries the floor' '2' "$(@($set1.permissions.deny).Count)")) { $failures++ }
        if (-not (Assert-Case '...the hook command is double-quoted round the guard path' 'True' ([string]$set1.hooks.PreToolUse[0].hooks[0].command -match '-File "').ToString())) { $failures++ }
        if (-not (Assert-Case '...and carries no leftover placeholder' 'False' ([string]$set1.hooks.PreToolUse[0].hooks[0].command -match 'HOOKS_DIR').ToString())) { $failures++ }

        $r2 = Invoke-LayerInstall -Ctx $ctx
        if (-not (Assert-Exit 'installing AGAIN passes' '0' $r2 $false)) { $failures++ }
        $set2 = [System.IO.File]::ReadAllText((Join-Path $homeDir 'settings.json')) | ConvertFrom-Json
        if (-not (Assert-Case '...and adds no duplicate deny entry' '2' "$(@($set2.permissions.deny).Count)")) { $failures++ }
        if (-not (Assert-Case '...and no duplicate hook' '1' "$(@($set2.hooks.PreToolUse[0].hooks).Count)")) { $failures++ }
        if (-not (Assert-Case '...and no second managed block' '1' "$(([regex]::Matches(([System.IO.File]::ReadAllText((Join-Path $homeDir 'CLAUDE.md')) -replace "`r`n", "`n"), [regex]::Escape($script:BlockBegin))).Count)")) { $failures++ }

        # ── UNION OVER A CONFIG THAT ALREADY HAS CONTENT ──────────────────────────
        $u = Join-Path $tmp 'union-home'; $null = [System.IO.Directory]::CreateDirectory($u)
        $theirs = [pscustomobject]@{
            model       = 'their-model'
            permissions = [pscustomobject]@{
                deny  = @('Bash(rm -rf /)', 'Bash(their-own-rule *)')
                allow = @('Bash(ls *)')
            }
            hooks       = [pscustomobject]@{ PreToolUse = @([pscustomobject]@{ matcher = 'Bash|PowerShell'; hooks = @([pscustomobject]@{ type = 'command'; command = 'their-own-hook' }) }) }
        }
        [System.IO.File]::WriteAllText((Join-Path $u 'settings.json'), ($theirs | ConvertTo-Json -Depth 20))
        [System.IO.File]::WriteAllText((Join-Path $u 'CLAUDE.md'), "# Their own always-on notes`n`nKeep this.`n")
        $uctx = Get-FixtureContext -LayerRoot $layer -ClaudeHome $u -DryRun $false -Force $false -FaultInject ''
        $r = Invoke-LayerInstall -Ctx $uctx
        if (-not (Assert-Exit 'installing over a populated config passes' '0' $r $false)) { $failures++ }
        $su = [System.IO.File]::ReadAllText((Join-Path $u 'settings.json')) | ConvertFrom-Json
        if (-not (Assert-Case "...their unrelated top-level key survives" 'their-model' "$($su.model)")) { $failures++ }
        if (-not (Assert-Case '...their own deny entry survives' 'True' (@($su.permissions.deny) -ccontains 'Bash(their-own-rule *)').ToString())) { $failures++ }
        if (-not (Assert-Case '...their allow list is untouched' '1' "$(@($su.permissions.allow).Count)")) { $failures++ }
        if (-not (Assert-Case '...the deny they already shared with the floor is not duplicated' '1' "$(@(@($su.permissions.deny) | Where-Object { $_ -ceq 'Bash(rm -rf /)' }).Count)")) { $failures++ }
        if (-not (Assert-Case '...deny is the union: 2 theirs + 1 new' '3' "$(@($su.permissions.deny).Count)")) { $failures++ }
        if (-not (Assert-Case '...their hook survives in the group ours joined' 'True' (@(@($su.hooks.PreToolUse[0].hooks) | ForEach-Object { [string]$_.command }) -ccontains 'their-own-hook').ToString())) { $failures++ }
        if (-not (Assert-Case '...and ours was APPENDED to their group, not a second group' '1' "$(@($su.hooks.PreToolUse).Count)")) { $failures++ }
        if (-not (Assert-Case '...their CLAUDE.md prose survives above the block' 'True' ([System.IO.File]::ReadAllText((Join-Path $u 'CLAUDE.md')) -match 'Keep this').ToString())) { $failures++ }
        # The entry the recipient already had must NOT be recorded as ours -- that is the whole
        # reason uninstall can be precise.
        $mu = [System.IO.File]::ReadAllText((Join-Path $u $script:ManifestName)) | ConvertFrom-Json
        if (-not (Assert-Case '...and the manifest does NOT claim their pre-existing deny entry' 'False' (@($mu.deny_added) -ccontains 'Bash(rm -rf /)').ToString())) { $failures++ }

        # ── UNINSTALL RESTORES EXACTLY ────────────────────────────────────────────
        $r = Invoke-LayerUninstall -Ctx $uctx
        if (-not (Assert-Exit 'uninstall passes' '0' $r $false)) { $failures++ }
        $sd = [System.IO.File]::ReadAllText((Join-Path $u 'settings.json')) | ConvertFrom-Json
        if (-not (Assert-Case '...their own deny entry survives the uninstall' 'True' (@($sd.permissions.deny) -ccontains 'Bash(their-own-rule *)').ToString())) { $failures++ }
        if (-not (Assert-Case '...and so does the one they shared with the floor' 'True' (@($sd.permissions.deny) -ccontains 'Bash(rm -rf /)').ToString())) { $failures++ }
        if (-not (Assert-Case '...deny is back to their 2' '2' "$(@($sd.permissions.deny).Count)")) { $failures++ }
        if (-not (Assert-Case '...their top-level key still there' 'their-model' "$($sd.model)")) { $failures++ }
        if (-not (Assert-Case '...their hook survives and ours is gone' 'their-own-hook' "$(@(@($sd.hooks.PreToolUse[0].hooks) | ForEach-Object { [string]$_.command }) -join ',')")) { $failures++ }
        if (-not (Assert-Case '...the group they owned was NOT removed' '1' "$(@($sd.hooks.PreToolUse).Count)")) { $failures++ }
        if (-not (Assert-Case '...the managed block is gone' 'True' ($null -eq (Get-ManagedBlock -Text ([System.IO.File]::ReadAllText((Join-Path $u 'CLAUDE.md'))))).ToString())) { $failures++ }
        if (-not (Assert-Case '...and their CLAUDE.md prose is still there' 'True' ([System.IO.File]::ReadAllText((Join-Path $u 'CLAUDE.md')) -match 'Keep this').ToString())) { $failures++ }
        if (-not (Assert-Case '...the skill files are gone' 'False' "$(Test-Path -LiteralPath (Join-Path $u 'skills/alpha/SKILL.md'))")) { $failures++ }
        if (-not (Assert-Case '...the skill directory this installer created is gone' 'False' "$(Test-Path -LiteralPath (Join-Path $u 'skills/alpha'))")) { $failures++ }
        if (-not (Assert-Case '...and the manifest is gone' 'False' "$(Test-Path -LiteralPath (Join-Path $u $script:ManifestName))")) { $failures++ }

        # ── INSTALL TWICE, THEN UNINSTALL ─────────────────────────────────────────
        # The manifest must survive a re-install that copies NOTHING. A second install finds every
        # file already there and identical, so its own dirsCreated list is empty -- and a manifest
        # written from that run alone silently replaces install #1's record of the skill directories
        # with []. Every file is then still removed correctly and the whole skills/ tree is left
        # behind for ever, under a report that reads PASS. Neither a single install/uninstall pair nor
        # two consecutive installs can see this; it takes all three, in order.
        $tw = Join-Path $tmp 'twice-home'
        $twctx = Get-FixtureContext -LayerRoot $layer -ClaudeHome $tw -DryRun $false -Force $false -FaultInject ''
        $null = Invoke-LayerInstall -Ctx $twctx
        $null = Invoke-LayerInstall -Ctx $twctx
        $mtw = [System.IO.File]::ReadAllText((Join-Path $tw $script:ManifestName)) | ConvertFrom-Json
        if (-not (Assert-Case 'a second install does NOT forget the directories the first created' 'True' (@($mtw.dirs_created).Count -ge 3).ToString())) { $failures++ }
        $r = Invoke-LayerUninstall -Ctx $twctx
        if (-not (Assert-Exit 'uninstall after two installs passes' '0' $r $false)) { $failures++ }
        if (-not (Assert-Case '...and the skills tree is really gone, not just its files' 'False' "$(Test-Path -LiteralPath (Join-Path $tw 'skills'))")) { $failures++ }
        if (-not (Assert-Case '...and the hooks directory with it' 'False' "$(Test-Path -LiteralPath (Join-Path $tw 'hooks'))")) { $failures++ }

        # ── THE BACKUPS ARE NAMED, NOT SILENTLY LEFT ──────────────────────────────
        $bk = Join-Path $tmp 'backup-home'; $null = [System.IO.Directory]::CreateDirectory($bk)
        [System.IO.File]::WriteAllText((Join-Path $bk 'CLAUDE.md'), "# theirs`n")
        $bkctx = Get-FixtureContext -LayerRoot $layer -ClaudeHome $bk -DryRun $false -Force $false -FaultInject ''
        $null = Invoke-LayerInstall -Ctx $bkctx
        $mbk = [System.IO.File]::ReadAllText((Join-Path $bk $script:ManifestName)) | ConvertFrom-Json
        if (-not (Assert-Case 'the CLAUDE.md this install overwrote is recorded as a backup' 'True' (@($mbk.backups).Count -ge 1).ToString())) { $failures++ }
        $r = Invoke-LayerUninstall -Ctx $bkctx
        if (-not (Assert-Exit 'uninstall passes with a backup still on disk' '0' $r $false)) { $failures++ }
        if (-not (Assert-Case '...and it is NAMED in the plan rather than silently left' 'True' (@($r.Plan | Where-Object { $_.Detail -match 'LEFT IN PLACE' }).Count -ge 1).ToString())) { $failures++ }
        if (-not (Assert-Case '...and NOT deleted -- it is their only copy of their old config' 'True' (@(Get-ChildItem -LiteralPath $bk -Filter 'CLAUDE.md.bak-*').Count -ge 1).ToString())) { $failures++ }

        # ...and on a home where this installer created CLAUDE.md, uninstall removes the file.
        $r = Invoke-LayerUninstall -Ctx $ctx
        if (-not (Assert-Exit 'uninstall of a home this installer created passes' '0' $r $false)) { $failures++ }
        if (-not (Assert-Case '...and CLAUDE.md, which it created, is removed' 'False' "$(Test-Path -LiteralPath (Join-Path $homeDir 'CLAUDE.md'))")) { $failures++ }
        # ...and settings.json too, symmetrically. Leaving an empty
        # {"permissions":{"deny":[],"ask":[]}} behind is inert, and it also makes "everything the
        # manifest recorded has been removed, and nothing else" not quite true.
        if (-not (Assert-Case '...and settings.json, which it also created, is removed' 'False' "$(Test-Path -LiteralPath (Join-Path $homeDir 'settings.json'))")) { $failures++ }
        # THE OTHER POLARITY, twice, because a rule that deletes a file has to be shown NOT deleting
        # the two files it must not touch.
        if (-not (Assert-Case 'a config with an unrelated top-level key is NOT vacuous' 'False' "$(Test-SettingsIsVacuous -Object ('{"permissions":{"deny":[]},"model":"x"}' | ConvertFrom-Json))")) { $failures++ }
        if (-not (Assert-Case '...nor one with a non-empty allow list this script never wrote' 'False' "$(Test-SettingsIsVacuous -Object ('{"permissions":{"deny":[],"allow":["Bash(ls *)"]}}' | ConvertFrom-Json))")) { $failures++ }
        if (-not (Assert-Case '...nor one with a hook left in it' 'False' "$(Test-SettingsIsVacuous -Object ('{"hooks":{"PreToolUse":[{"matcher":"*"}]}}' | ConvertFrom-Json))")) { $failures++ }
        if (-not (Assert-Case '...while the empty shell this installer leaves IS' 'True' "$(Test-SettingsIsVacuous -Object ('{"permissions":{"deny":[],"ask":[]},"hooks":{"PreToolUse":[]}}' | ConvertFrom-Json))")) { $failures++ }
        # ...and end to end: a home where WE created settings.json but the recipient then added a rule
        # of their own keeps its file.
        $kp = Join-Path $tmp 'keep-home'
        $kpctx = Get-FixtureContext -LayerRoot $layer -ClaudeHome $kp -DryRun $false -Force $false -FaultInject ''
        $null = Invoke-LayerInstall -Ctx $kpctx
        $ks = [System.IO.File]::ReadAllText((Join-Path $kp 'settings.json')) | ConvertFrom-Json
        $ks.permissions.deny = @(@($ks.permissions.deny) + 'Bash(mine *)')
        [System.IO.File]::WriteAllText((Join-Path $kp 'settings.json'), ($ks | ConvertTo-Json -Depth 100))
        $r = Invoke-LayerUninstall -Ctx $kpctx
        if (-not (Assert-Exit 'uninstall passes when a rule of theirs is in a file we created' '0' $r $false)) { $failures++ }
        if (-not (Assert-Case '...and the file is KEPT, not deleted' 'True' "$(Test-Path -LiteralPath (Join-Path $kp 'settings.json'))")) { $failures++ }
        if (-not (Assert-Case '...with their rule in it' 'Bash(mine *)' (@((([System.IO.File]::ReadAllText((Join-Path $kp 'settings.json')) | ConvertFrom-Json).permissions.deny)) -join ','))) { $failures++ }
        # Uninstalling twice must be safe rather than an error about things already gone.
        $r = Invoke-LayerUninstall -Ctx $ctx
        if (-not (Assert-Exit 'uninstall with no manifest left is SKIPPED, never a pass' '2' $r $false)) { $failures++ }

        # ── UNINSTALL DECLINES WHAT THE RECIPIENT HAS EDITED ──────────────────────
        $ed = Join-Path $tmp 'edited-home'
        $ectx = Get-FixtureContext -LayerRoot $layer -ClaudeHome $ed -DryRun $false -Force $false -FaultInject ''
        $null = Invoke-LayerInstall -Ctx $ectx
        [System.IO.File]::WriteAllText((Join-Path $ed 'skills/beta/SKILL.md'), "---`nname: beta`n---`nEDITED BY THE RECIPIENT`n")
        $r = Invoke-LayerUninstall -Ctx $ectx
        if (-not (Assert-Exit 'an edited installed file makes uninstall SKIPPED, not PASS' '2' $r $false)) { $failures++ }
        if (-not (Assert-Case '...the edited file is still there' 'True' "$(Test-Path -LiteralPath (Join-Path $ed 'skills/beta/SKILL.md'))")) { $failures++ }
        if (-not (Assert-Case '...with the edit intact' 'True' ([System.IO.File]::ReadAllText((Join-Path $ed 'skills/beta/SKILL.md')) -match 'EDITED BY THE RECIPIENT').ToString())) { $failures++ }
        if (-not (Assert-Case '...the decline is named in the report' 'True' (@($r.Steps | Where-Object { $_.Findings -match 'DECLINED' }).Count -gt 0).ToString())) { $failures++ }
        if (-not (Assert-Case '...and the manifest is KEPT so a second run can finish' 'True' "$(Test-Path -LiteralPath (Join-Path $ed $script:ManifestName))")) { $failures++ }
        if (-not (Assert-Case '...while the unedited skill WAS removed' 'False' "$(Test-Path -LiteralPath (Join-Path $ed 'skills/alpha/SKILL.md'))")) { $failures++ }

        # ...and the same property for the managed block.
        $eb = Join-Path $tmp 'edited-block-home'
        $bctx = Get-FixtureContext -LayerRoot $layer -ClaudeHome $eb -DryRun $false -Force $false -FaultInject ''
        $null = Invoke-LayerInstall -Ctx $bctx
        $bt = [System.IO.File]::ReadAllText((Join-Path $eb 'CLAUDE.md'))
        [System.IO.File]::WriteAllText((Join-Path $eb 'CLAUDE.md'), ($bt -replace 'Always do the thing', 'Always do the OTHER thing'))
        $r = Invoke-LayerUninstall -Ctx $bctx
        if (-not (Assert-Exit 'an edited managed block makes uninstall SKIPPED' '2' $r $false)) { $failures++ }
        if (-not (Assert-Case '...and the edit survives' 'True' ([System.IO.File]::ReadAllText((Join-Path $eb 'CLAUDE.md')) -match 'OTHER thing').ToString())) { $failures++ }

        # A CRLF rewrite of the block must NOT read as an edit -- otherwise an editor's line-ending
        # setting is enough to make the uninstall decline forever.
        $crlf = Join-Path $tmp 'crlf-home'
        $cctx = Get-FixtureContext -LayerRoot $layer -ClaudeHome $crlf -DryRun $false -Force $false -FaultInject ''
        $null = Invoke-LayerInstall -Ctx $cctx
        $ct = [System.IO.File]::ReadAllText((Join-Path $crlf 'CLAUDE.md'))
        $crlfText = (($ct -replace "`r`n", "`n") -replace "`n", "`r`n")
        [System.IO.File]::WriteAllText((Join-Path $crlf 'CLAUDE.md'), $crlfText)
        $r = Invoke-LayerUninstall -Ctx $cctx
        if (-not (Assert-Exit 'a CRLF rewrite of the block is not mistaken for an edit' '0' $r $false)) { $failures++ }

        # ── A DRY-RUN UNINSTALL WRITES NOTHING ────────────────────────────────────
        $dd = Join-Path $tmp 'dry-uninstall-home'
        $dctx = Get-FixtureContext -LayerRoot $layer -ClaudeHome $dd -DryRun $false -Force $false -FaultInject ''
        $null = Invoke-LayerInstall -Ctx $dctx
        $before = [System.IO.File]::ReadAllText((Join-Path $dd 'settings.json'))
        $r = Invoke-LayerUninstall -Ctx (Get-FixtureContext -LayerRoot $layer -ClaudeHome $dd -DryRun $true -Force $false -FaultInject '')
        if (-not (Assert-Exit 'a dry-run uninstall reports SKIPPED' '2' $r $true)) { $failures++ }
        if (-not (Assert-Case '...and changes settings.json not at all' 'True' ([System.IO.File]::ReadAllText((Join-Path $dd 'settings.json')) -eq $before).ToString())) { $failures++ }
        if (-not (Assert-Case '...and leaves the skill files alone' 'True' "$(Test-Path -LiteralPath (Join-Path $dd 'skills/alpha/SKILL.md'))")) { $failures++ }
        if (-not (Assert-Case '...and the manifest alone' 'True' "$(Test-Path -LiteralPath (Join-Path $dd $script:ManifestName))")) { $failures++ }
        if (-not (Assert-Case '...while still printing what it would remove' 'True' (@($r.Plan | Where-Object { $_.Op -eq '-' }).Count -gt 3).ToString())) { $failures++ }

        # ── A FILE AT A TARGET PATH THAT IS NOT OURS ──────────────────────────────
        $col = Join-Path $tmp 'collide-home'
        $null = [System.IO.Directory]::CreateDirectory((Join-Path $col 'skills/alpha'))
        [System.IO.File]::WriteAllText((Join-Path $col 'skills/alpha/SKILL.md'), "the recipient's own alpha skill`n")
        $cctx2 = Get-FixtureContext -LayerRoot $layer -ClaudeHome $col -DryRun $false -Force $false -FaultInject ''
        $r = Invoke-LayerInstall -Ctx $cctx2
        if (-not (Assert-Exit 'a foreign file at a target path FAILS without -Force' '1' $r $false)) { $failures++ }
        if (-not (Assert-Case '...and is left exactly as it was' 'True' ([System.IO.File]::ReadAllText((Join-Path $col 'skills/alpha/SKILL.md')) -match "recipient's own").ToString())) { $failures++ }
        if (-not (Assert-Case '...and no settings.json was written on the way past' 'False' "$(Test-Path -LiteralPath (Join-Path $col 'settings.json'))")) { $failures++ }
        $r = Invoke-LayerInstall -Ctx (Get-FixtureContext -LayerRoot $layer -ClaudeHome $col -DryRun $false -Force $true -FaultInject '')
        if (-not (Assert-Exit '-Force installs over it' '0' $r $false)) { $failures++ }
        $mc = [System.IO.File]::ReadAllText((Join-Path $col $script:ManifestName)) | ConvertFrom-Json
        $rec = @($mc.files | Where-Object { $_.path -eq 'skills/alpha/SKILL.md' })[0]
        if (-not (Assert-Case '...and records the backup, so uninstall can put theirs back' 'True' (-not [string]::IsNullOrWhiteSpace([string]$rec.backup)).ToString())) { $failures++ }
        $null = Invoke-LayerUninstall -Ctx $cctx2
        if (-not (Assert-Case '...and uninstall restores their original file' 'True' ((Test-Path -LiteralPath (Join-Path $col 'skills/alpha/SKILL.md')) -and ([System.IO.File]::ReadAllText((Join-Path $col 'skills/alpha/SKILL.md')) -match "recipient's own")).ToString())) { $failures++ }

        # ── A HOME PATH CONTAINING A SINGLE QUOTE ─────────────────────────────────
        # The character the sibling installer was bitten by, on a real Windows path. It must INSTALL,
        # not be refused: refusing O'Brien is not a fix, it is the bug with better manners.
        $qHome = Join-Path $tmp "O'Brien-home"
        $qctx = Get-FixtureContext -LayerRoot $layer -ClaudeHome $qHome -DryRun $false -Force $false -FaultInject ''
        $r = Invoke-LayerInstall -Ctx $qctx
        if (-not (Assert-Exit "a home path containing an apostrophe installs" '0' $r $false)) { $failures++ }
        $sq = [System.IO.File]::ReadAllText((Join-Path $qHome 'settings.json')) | ConvertFrom-Json
        $cmdq = [string]$sq.hooks.PreToolUse[0].hooks[0].command
        if (-not (Assert-Case "...and the guard path is double-quoted, so no shell sees a dangling quote" 'True' ($cmdq -match '-File "[^"]*O''Brien[^"]*"').ToString())) { $failures++ }
        if (-not (Assert-Case '...and settings.json still parses when read back' 'True' ($null -ne $sq).ToString())) { $failures++ }
        if (-not (Assert-Exit '...and uninstall of it passes too' '0' (Invoke-LayerUninstall -Ctx $qctx) $false)) { $failures++ }

        # ── MID-WRITE FAILURE: THE BACKUP IS RESTORED ─────────────────────────────
        # Three injection points, because the three failures are different states: before the swap
        # (nothing to restore), at the swap (backup taken, original still in place), and at the
        # read-back (the bad file is already live and only a restore helps).
        foreach ($fault in @('SettingsTempInvalid', 'SettingsSwap', 'SettingsReadback')) {
            $fh = Join-Path $tmp "fault-$fault"
            $fctx = Get-FixtureContext -LayerRoot $layer -ClaudeHome $fh -DryRun $false -Force $false -FaultInject ''
            $null = Invoke-LayerInstall -Ctx $fctx
            $good = [System.IO.File]::ReadAllText((Join-Path $fh 'settings.json'))
            # Add a new deny entry to the floor so the second install has something to write.
            $floor2 = [System.IO.File]::ReadAllText((Join-Path $layer 'settings.template.json')) | ConvertFrom-Json
            $floor2.permissions.deny = @(@($floor2.permissions.deny) + 'Bash(a-new-rule *)')
            $layer2 = Join-Path $tmp "layer-$fault"
            $null = [System.IO.Directory]::CreateDirectory($layer2)
            foreach ($f in @(Get-ChildItem -LiteralPath $layer -Recurse -File)) {
                $rel = Get-RelUnder -FullName $f.FullName -Root $layer
                $dest = Join-Path $layer2 ($rel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                $null = [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($dest))
                [System.IO.File]::Copy($f.FullName, $dest, $true)
            }
            [System.IO.File]::WriteAllText((Join-Path $layer2 'settings.template.json'), ($floor2 | ConvertTo-Json -Depth 20))
            $fctx2 = Get-FixtureContext -LayerRoot $layer2 -ClaudeHome $fh -DryRun $false -Force $false -FaultInject $fault
            $r = Invoke-LayerInstall -Ctx $fctx2
            if (-not (Assert-Exit "fault '$fault': the install FAILS" '1' $r $false)) { $failures++ }
            $after = [System.IO.File]::ReadAllText((Join-Path $fh 'settings.json'))
            if (-not (Assert-Case "...and settings.json is the pre-failure file, byte for byte" 'True' ($after -eq $good).ToString())) { $failures++ }
            if (-not (Assert-Case "...and it still parses" 'True' ($null -ne ($after | ConvertFrom-Json)).ToString())) { $failures++ }
            $said = @($r.Steps | ForEach-Object { $_.Findings }) -join ' '
            if (-not (Assert-Case "...and the report says so out loud" 'True' ($said -match 'RESTORED|untouched|unchanged').ToString())) { $failures++ }
            if (-not (Assert-Case "...and no .tmp- file is left behind" '0' "$(@(Get-ChildItem -LiteralPath $fh -Filter 'settings.json.tmp-*' -ErrorAction SilentlyContinue).Count)")) { $failures++ }
        }

        # ── THE WRITE PATH'S OWN CONTROLS ─────────────────────────────────────────
        # A candidate that does not parse must never reach the target -- proved directly, because the
        # end-to-end control above cannot distinguish "the validate step stopped it" from "the swap
        # happened to fail".
        $wh = Join-Path $tmp 'write-home'; $null = [System.IO.Directory]::CreateDirectory($wh)
        $target = Join-Path $wh 'settings.json'
        [System.IO.File]::WriteAllText($target, '{"keep":"me"}')
        $threw = $false
        try { $null = Write-JsonChecked -Path $target -Object ([pscustomobject]@{ a = 1 }) -Fault 'SettingsTempInvalid' } catch { $threw = $true }
        if (-not (Assert-Case 'an invalid candidate never reaches the target' 'True' $threw.ToString())) { $failures++ }
        if (-not (Assert-Case '...and the target is untouched' '{"keep":"me"}' ([System.IO.File]::ReadAllText($target)))) { $failures++ }
        if (-not (Assert-Case '...and no backup was taken, because nothing was risked' '0' "$(@(Get-ChildItem -LiteralPath $wh -Filter 'settings.json.bak-*' -ErrorAction SilentlyContinue).Count)")) { $failures++ }
        # A one-element list must serialise as an ARRAY. A bare string there is a settings file
        # Claude Code rejects whole, written by an installer that reported success.
        $solo = Join-Path $wh 'solo.json'
        $null = Write-JsonChecked -Path $solo -Object ([pscustomobject]@{ permissions = [pscustomobject]@{ deny = ([string[]]@('only-one')) } }) -Fault ''
        if (-not (Assert-Case 'a one-entry deny list serialises as an array, not a string' 'True' ([System.IO.File]::ReadAllText($solo) -match '"deny":\s*\[').ToString())) { $failures++ }
        # Key ORDER is preserved: an installer that reorders somebody's config produces a diff that
        # looks like a rewrite.
        $ord = Join-Path $wh 'order.json'
        [System.IO.File]::WriteAllText($ord, '{"zebra":1,"alpha":2,"mid":3}')
        $o = Import-SettingsFile -Path $ord
        $null = Write-JsonChecked -Path $ord -Object $o.Object -Fault ''
        if (-not (Assert-Case 'round-tripping a config preserves key order' 'zebra,alpha,mid' (@(Get-PropName -Object ([System.IO.File]::ReadAllText($ord) | ConvertFrom-Json)) -join ','))) { $failures++ }
        # ...and it DID take a backup, because that file was not ours.
        if (-not (Assert-Case '...and a file we did not create is backed up before the swap' '1' "$(@(Get-ChildItem -LiteralPath $wh -Filter 'order.json.bak-*').Count)")) { $failures++ }
        # -TakeBackup $false takes none. Without this the manifest gains a .bak-<timestamp> on every
        # re-install, in the recipient's configuration directory, for ever -- there is no content to
        # protect in a file this script wholly writes. Measured: two installs left one.
        $own = Join-Path $wh 'own.json'
        [System.IO.File]::WriteAllText($own, '{"a":1}')
        $null = Write-JsonChecked -Path $own -Object ([pscustomobject]@{ a = 2 }) -Fault '' -TakeBackup $false
        if (-not (Assert-Case 'a file this script owns is rewritten with NO backup litter' '0' "$(@(Get-ChildItem -LiteralPath $wh -Filter 'own.json.bak-*').Count)")) { $failures++ }

        # ── THE MANIFEST IS THE ONLY AUTHORITY FOR REMOVAL ────────────────────────
        $nm = Join-Path $tmp 'no-manifest-home'; $null = [System.IO.Directory]::CreateDirectory($nm)
        [System.IO.File]::WriteAllText((Join-Path $nm 'settings.json'), '{"permissions":{"deny":["Bash(rm -rf /)"]}}')
        $r = Invoke-LayerUninstall -Ctx (Get-FixtureContext -LayerRoot $layer -ClaudeHome $nm -DryRun $false -Force $false -FaultInject '')
        if (-not (Assert-Exit 'uninstall with no manifest is SKIPPED, never PASS' '2' $r $false)) { $failures++ }
        if (-not (Assert-Case '...and removes nothing it was not told about' 'True' ([System.IO.File]::ReadAllText((Join-Path $nm 'settings.json')) -match 'rm -rf').ToString())) { $failures++ }
        [System.IO.File]::WriteAllText((Join-Path $nm $script:ManifestName), '{"schema":"some-other-installer/v9"}')
        $r = Invoke-LayerUninstall -Ctx (Get-FixtureContext -LayerRoot $layer -ClaudeHome $nm -DryRun $false -Force $false -FaultInject '')
        if (-not (Assert-Exit "a manifest with the wrong schema FAILS rather than being acted on" '1' $r $false)) { $failures++ }
        [System.IO.File]::WriteAllText((Join-Path $nm $script:ManifestName), 'not json at all')
        $r = Invoke-LayerUninstall -Ctx (Get-FixtureContext -LayerRoot $layer -ClaudeHome $nm -DryRun $false -Force $false -FaultInject '')
        if (-not (Assert-Exit 'an unparseable manifest FAILS rather than being guessed at' '1' $r $false)) { $failures++ }

        # ── THE EXIT CONTRACT ITSELF ──────────────────────────────────────────────
        $sPass = [InstallStep]::new('a'); $sFail = [InstallStep]::new('b'); $sFail.Fail('x')
        $sSkip = [InstallStep]::new('c'); $sSkip.Skip('y')
        $sDecl = [InstallStep]::new('d'); $sDecl.Decline('z')
        if (-not (Assert-Case 'FAIL outranks SKIPPED' '1' "$(Get-LayerExit -Steps @($sSkip, $sFail) -DryRun $false)")) { $failures++ }
        if (-not (Assert-Case 'SKIPPED outranks PASS' '2' "$(Get-LayerExit -Steps @($sPass, $sSkip) -DryRun $false)")) { $failures++ }
        if (-not (Assert-Case 'a DECLINE is SKIPPED, not FAIL and not PASS' '2' "$(Get-LayerExit -Steps @($sPass, $sDecl) -DryRun $false)")) { $failures++ }
        if (-not (Assert-Case 'a dry run is SKIPPED even when every step passed' '2' "$(Get-LayerExit -Steps @($sPass) -DryRun $true)")) { $failures++ }
        $sInc = [InstallStep]::new('e'); $sInc.Seal('measured nothing')
        if (-not (Assert-Case 'INCONCLUSIVE is 1, not 0 -- measuring nothing is not passing' '1' "$(Get-LayerExit -Steps @($sInc) -DryRun $false)")) { $failures++ }
        $sBoth = [InstallStep]::new('f'); $sBoth.Fail('real finding'); $sBoth.Seal('measured nothing')
        if (-not (Assert-Case 'Seal must not relabel a recorded FAIL as INCONCLUSIVE' 'FAIL' $sBoth.Status)) { $failures++ }

        # ── THE REAL FLOOR, END TO END ────────────────────────────────────────────
        # Everything above runs on a fixture floor. This runs the SHIPPED floor and the SHIPPED guard
        # into a temp home, because a control that only ever sees a fixture is a control that has
        # never met the artifact.
        if ((Test-Path -LiteralPath $RealFloor) -and (Test-Path -LiteralPath $RealGuard)) {
            $rh = Join-Path $tmp 'real-floor-home'
            $rctx = Get-FixtureContext -LayerRoot $layer -ClaudeHome $rh -DryRun $false -Force $false -FaultInject ''
            $rctx.FloorTemplate = $RealFloor
            $rctx.GuardScript = $RealGuard
            $r = Invoke-LayerInstall -Ctx $rctx
            if (-not (Assert-Exit 'the shipped floor and guard install end to end' '0' $r $false)) { $failures++ }
            $sr = [System.IO.File]::ReadAllText((Join-Path $rh 'settings.json')) | ConvertFrom-Json
            if (-not (Assert-Case '...with the real deny list on disk' 'True' (@($sr.permissions.deny).Count -gt 20).ToString())) { $failures++ }
            if (-not (Assert-Case '...and the guard file beside the hook that names it' 'True' "$(Test-Path -LiteralPath (Join-Path $rh 'hooks/secret-guard.ps1'))")) { $failures++ }
            if (-not (Assert-Exit '...and uninstall takes all of it back out' '0' (Invoke-LayerUninstall -Ctx $rctx) $false)) { $failures++ }
            if (-not (Assert-Case '...leaving the home with nothing of ours in it at all' '' ((Get-ChildItem -LiteralPath $rh -Recurse -Force | ForEach-Object { $_.Name }) -join ','))) { $failures++ }
        }
        else {
            Write-Host "  [FAIL] the shipped floor or guard is missing -- the end-to-end control could not run" -ForegroundColor Red
            $failures++
        }
    }
    catch {
        # An exception escaping a control is a FAILURE with a name and a stack trace, not a raw
        # PowerShell dump on the way out. Without this the suite reported the exception text and
        # nothing about which control it escaped, and the only way to find out was to add print
        # statements -- which is how a suite stops being run.
        Write-Host "  [FAIL] an unexpected exception escaped a control: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ($_.ScriptStackTrace -split "`n" | ForEach-Object { "         $_" }) -ForegroundColor DarkGray
        $failures++
    }
    finally {
        if (Test-Path -LiteralPath $tmp) { [System.IO.Directory]::Delete($tmp, $true) }
    }

    Write-Host ""
    if ($failures -eq 0) { Write-Host "SELF-TEST: PASS -- every control behaved as specified" -ForegroundColor Green; return 0 }
    Write-Host "SELF-TEST: FAIL -- $failures control(s) did not behave as specified" -ForegroundColor Red
    return 1
}

# ── ENVIRONMENT ─────────────────────────────────────────────────────────────────
# Resolved BEFORE anything is written, and failing to 1 rather than 0. An installer that cannot
# locate its inputs must not report success, and must not leave half a configuration behind while
# finding out.

if (-not $LayerRoot) { $LayerRoot = $PSScriptRoot }
if (-not (Test-Path -LiteralPath $LayerRoot -PathType Container)) {
    Write-Host "ENVIRONMENT: -LayerRoot '$LayerRoot' does not exist." -ForegroundColor Red
    exit 1
}
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path

if (-not $SkillsRoot) { $SkillsRoot = Join-Path $LayerRoot 'skills' }
$toolkit = Join-Path (Split-Path -Parent $LayerRoot) 'claude-permission-toolkit'
if (-not $FloorTemplate) { $FloorTemplate = Join-Path $toolkit 'settings.template.json' }
if (-not $GuardScript) { $GuardScript = Join-Path $toolkit $script:GuardName }

$defaultHome = Join-Path $HOME '.claude'

if ($SelfTest) {
    # The self-test never touches -ClaudeHome, default or otherwise. It builds its own temp homes.
    exit (Invoke-LayerSelfTest -RealFloor $FloorTemplate -RealGuard $GuardScript)
}

if (-not $ClaudeHome) { $ClaudeHome = $defaultHome }
# GetFullPath, not Resolve-Path: the directory legitimately may not exist yet on a first install,
# and Resolve-Path throws on that.
$ClaudeHome = [System.IO.Path]::GetFullPath($ClaudeHome)

if (-not $HooksDir) { $HooksDir = Join-Path $ClaudeHome 'hooks' }
$HooksDir = [System.IO.Path]::GetFullPath($HooksDir)
$guardTarget = Join-Path $HooksDir $script:GuardName

# THE SHELL-HOSTILE PATH CHECK. The hook command is handed to a shell this script cannot identify,
# so the guard path is emitted double-quoted -- which handles spaces and the apostrophe that bit the
# sibling installer. `$` and a backtick survive double quotes in PowerShell, `$` also in POSIX
# shells, and all of them are legal in a Windows path. Rather than escape for a shell nobody here
# can name, this refuses and offers the way out: -HooksDir somewhere plainer. Refusing the WHOLE
# install rather than only the hook, because a floor installed without its enforcement half is a
# configuration that reads as protected and is not.
$hostile = @(Test-ShellSafePath -Path $guardTarget)
if ($hostile.Count -gt 0) {
    Write-Host "ENVIRONMENT: the guard would be installed at" -ForegroundColor Red
    Write-Host "               $guardTarget" -ForegroundColor Red
    Write-Host "             which contains $($hostile -join ' and ') -- character(s) that a shell re-interprets even inside" -ForegroundColor Red
    Write-Host "             double quotes. The PreToolUse hook command would be wrong, and a wrong hook command" -ForegroundColor Red
    Write-Host "             fails SILENTLY on every tool call rather than reporting anything." -ForegroundColor Red
    Write-Host "             Re-run with -HooksDir pointing at a path without those characters." -ForegroundColor Red
    Write-Host "             Nothing has been written." -ForegroundColor Red
    exit 1
}

if ($FaultInject) {
    # Fault injection exists to prove the restore path runs, and it must not be pointable at a real
    # configuration. Two conditions, because either alone is defeatable by accident: the caller has
    # to have named a home explicitly, AND it must not be the default one.
    if (-not $PSBoundParameters.ContainsKey('ClaudeHome')) {
        Write-Host "ENVIRONMENT: -FaultInject requires an explicit -ClaudeHome. It deliberately breaks a write to prove the restore works, and it is not going to do that to a configuration nobody named." -ForegroundColor Red
        exit 1
    }
    if ($ClaudeHome -eq [System.IO.Path]::GetFullPath($defaultHome)) {
        Write-Host "ENVIRONMENT: -FaultInject refuses to run against the default configuration directory ($defaultHome). Point -ClaudeHome at a throwaway copy." -ForegroundColor Red
        exit 1
    }
}

$ctx = @{
    ClaudeHome    = $ClaudeHome
    LayerRoot     = $LayerRoot
    FragmentPath  = $FragmentPath
    SkillsRoot    = $SkillsRoot
    FloorTemplate = $FloorTemplate
    GuardScript   = $GuardScript
    HooksDir      = $HooksDir
    GuardTarget   = $guardTarget
    SourceCommit  = $SourceCommit
    DryRun        = [bool]$DryRun
    Force         = [bool]$Force
    FaultInject   = $FaultInject
}

if (-not $DryRun -and -not (Test-Path -LiteralPath $ClaudeHome -PathType Container)) {
    if ($Uninstall) {
        Write-Host "ENVIRONMENT: -ClaudeHome '$ClaudeHome' does not exist, so there is nothing installed there to remove." -ForegroundColor Yellow
        exit 2
    }
    $null = [System.IO.Directory]::CreateDirectory($ClaudeHome)
}

$run = if ($Uninstall) { Invoke-LayerUninstall -Ctx $ctx } else { Invoke-LayerInstall -Ctx $ctx }

# ── REPORT ──────────────────────────────────────────────────────────────────────
# ASCII only, for the reason the gates state: windows-latest turned a non-ASCII bullet into a
# replacement character and made the log unreadable. The output boundary is part of the tool.

Write-Host ""
Write-Host "PRACTICE FIRING LAYER -- $(if ($Uninstall) { 'UNINSTALL' } else { 'INSTALL' })$(if ($DryRun) { ' (DRY RUN)' } else { '' })"
Write-Host ("layer  {0}" -f $LayerRoot)
Write-Host ("target {0}{1}" -f $ClaudeHome, $(if ($DryRun) { '   <nothing written>' } else { '' }))
Write-Host ("=" * 96)

foreach ($s in $run.Steps) {
    $colour = switch ($s.Status) {
        'PASS' { 'Green' } 'FAIL' { 'Red' } 'INCONCLUSIVE' { 'Red' } 'SKIPPED' { 'Yellow' } default { 'Gray' }
    }
    Write-Host ("{0,-10} {1,-13} {2,4} item(s){3}" -f $s.Name, $s.Status, $s.Count, $(if ($s.Note) { "  -- $($s.Note)" } else { '' })) -ForegroundColor $colour
    foreach ($f in $s.Findings) { Write-Host "           - $f" -ForegroundColor $colour }
}

if (@($run.Plan).Count -gt 0) {
    Write-Host ("-" * 96)
    Write-Host $(if ($DryRun) { "THE DIFF THAT WOULD BE APPLIED   ( + add   ~ replace   - remove   = already so   . nothing to do   b backup )" }
        else { "WHAT WAS DONE   ( + added   ~ replaced   - removed   = already so   . nothing to do   b backup )" })
    foreach ($p in @($run.Plan)) {
        $colour = switch ($p.Op) { '+' { 'Green' } '~' { 'Yellow' } '-' { 'Yellow' } 'b' { 'DarkGray' } default { 'DarkGray' } }
        Write-Host ("  {0} {1,-34} {2}" -f $p.Op, $p.Target, $p.Detail) -ForegroundColor $colour
    }
}

$exit = Get-LayerExit -Steps @($run.Steps) -DryRun ([bool]$DryRun)

Write-Host ("=" * 96)
if ($exit -eq 1) {
    Write-Host "RESULT: FAIL -- the layer is NOT installed as described above. Read the finding(s): each one" -ForegroundColor Red
    Write-Host "        states what was and was not written, and names any backup it restored." -ForegroundColor Red
}
elseif ($exit -eq 2) {
    if ($DryRun) {
        Write-Host "RESULT: DRY RUN -- nothing was written. This is not an install." -ForegroundColor Yellow
        Write-Host "        Re-run without -DryRun to apply the diff above." -ForegroundColor Yellow
    }
    else {
        Write-Host "RESULT: SKIPPED -- something was deliberately not done. This is not a pass." -ForegroundColor Yellow
        Write-Host "        A DECLINED line means a file or block has been changed since it was installed and was" -ForegroundColor Yellow
        Write-Host "        left exactly as it is. Look at it, then re-run to finish." -ForegroundColor Yellow
    }
}
elseif ($Uninstall) {
    Write-Host "RESULT: PASS -- everything the manifest recorded has been removed, and nothing else." -ForegroundColor Green
    Write-Host "        Open a NEW Claude Code session: settings.json is read at startup, not mid-session." -ForegroundColor Green
}
else {
    Write-Host "RESULT: PASS -- installed and read back from disk." -ForegroundColor Green
    Write-Host "        Open a NEW Claude Code session: settings.json, CLAUDE.md and the skills are read at" -ForegroundColor Green
    Write-Host "        startup, not mid-session, so nothing above is in effect until you do." -ForegroundColor Green
    Write-Host "        To take it back out: this script with -Uninstall. It removes exactly what" -ForegroundColor Green
    Write-Host "        $($script:ManifestName) records and declines anything you have since changed." -ForegroundColor Green
}
Write-Host ""

exit $exit
