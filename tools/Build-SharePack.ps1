#requires -Version 7
<#
.SYNOPSIS
    Assemble the share pack -- the tree that leaves this repository -- as a reproducible artifact.

.DESCRIPTION
    Test-SharePackClean.ps1 is a gate over "the share pack". Until this file existed, the only thing
    that had ever produced a share pack was a temp directory built INSIDE that gate, thrown away in
    its own `finally`. So the repository had a gate for an artifact no reproducible step built: the
    thing shipped to a recipient was whatever somebody copied by hand, and the thing the gate
    certified was something else that had never left %TEMP%. A green gate said nothing about the zip
    in the recipient's mail.

    This is the missing step. It is the SINGLE SOURCE OF TRUTH for what the pack IS.

        THE ONE DESIGN POINT THIS FILE TURNS ON: this script and Test-SharePackClean.ps1 must not
        both implement staging. Two stagers drift apart -- that is the exact failure that gate's own
        header names about duplicated redaction lists, which is why it delegates its content checks
        rather than re-implementing them. Staging was the one thing it did NOT delegate, because
        there was nothing to delegate it to. Now there is: the builder stages, the gate becomes a
        caller.

        The integration chosen is INVOCATION, not dot-sourcing. The gate runs this script into its
        own staging directory and reads the manifest for the file list and the excluded count.
        Dot-sourcing would have been fewer moving parts, and it costs two things this repository has
        already been bitten by: a script with a param block and a main body needs an "am I being
        dot-sourced" guard, which is a control that has to keep being true and does nothing
        observable when it stops; and dot-sourcing exercises a FUNCTION while shipping a SCRIPT, so
        the artifact a recipient actually runs stays unexercised. Invoking means every gate run is
        an end-to-end test of the build step, and the manifest -- the thing the recipient reads --
        is on the path rather than beside it.

    WHAT THE PACK IS, and where each boundary comes from. The distinction matters, because one of
    these is a filter and the other three are not, and writing filters for the other three would
    leave four guards in the file of which three could never fire:

      * tools/ staged as tools/, plus LICENSE, NOTICE and README.md at the pack ROOT beside it.
        That is the whole pack.
      * No .git, no .github, no skills/. STRUCTURAL, not filtered: the copy root is tools/, so those
        paths are simply not underneath it. There is deliberately no exclusion pattern for them --
        an inert guard reads as protection and provides none. The property is ASSERTED in -SelfTest
        against a built tree instead, which is where a claim like this belongs.
      * __pycache__ / node_modules / .git directories. The first real FILTER, and its pattern is not
        written here either: it is READ OUT of Test-PracticeClaims.ps1, whose scanner applies the
        same exclusion when it walks the staged tree. Restating it would put the pack's idea of
        "non-content" and the scanner's idea of it in two places, one of which would eventually be
        wrong. A build that cannot parse it FAILS rather than falling back to a remembered list.
      * The HOLD LIST -- assets that must never leave at all. The second real filter, and the only
        one that is about a DECISION rather than about mechanics: an accumulated permission corpus,
        a host-specific teardown script, a populated identifier table. Its patterns are not written
        here either, for the reason above and one more: a captioned list of what an organisation
        withholds is a map of what it has, so the populated table is itself on the list. It is
        loaded from practice-gate/hold-classes.json, with hold-classes.example.json as the shipped
        generic fallback and a THROW when there is neither -- a hold list that failed to load
        permits everything while looking exactly like a pack with nothing to withhold. Every class
        is proved against its own worked example, on every build, before anything is withheld.
        Test-SharePackClean.ps1 reads the SAME table and cross-checks the two directions: a path
        this builder withheld that the gate's table does not hold, or a staged path the gate's table
        does hold, is a finding rather than a quiet difference of opinion.
      * Both counts are REPORTED, never silent, and they are reported SEPARATELY. "0 files
        excluded" and "the exclusion pattern stopped matching" are different facts and must not
        share an output; neither may "excluded as non-content" and "withheld by decision", which
        are different KINDS of fact about different files.

    THE PACK'S ROOT FILES ARE PART OF THE PACK, AND A MISSING ONE IS A BUILD FAILURE. There are
    three, and they come from two different reasons. Apache-2.0 4(a) and 4(d) require a
    redistribution to carry the License text and, where the work has one, the NOTICE file. The
    README is not a legal requirement at all: the pack is published as a standalone repository, and
    without it a cloner sees LICENSE, NOTICE, a manifest and a tools/ directory with nothing saying
    what any of them are. All three live at the repository root, i.e. outside tools/, so nothing
    about staging tools/ would ever pick them up: a pack built by copying tools/ alone is an
    unlicensed distribution with no front door, emitted from a licensed repository that has one.
    They are copied to the pack root and counted in the manifest like every other file.

    Absent at the source, ANY of the three fails the build -- it does not warn. The legal reason
    covers two of them and not the third, and the SEVERITY is deliberately the same anyway, because
    it does not rest on the legal reason: this step's entire job is proving the pack COMPLETE, and
    once a file is a declared part of the pack, "somebody decided not to ship it" and "the build
    lost it" are the two states a completeness check exists to tell apart. Only a failure tells them
    apart; a warning makes them the same log line. A warning on an unlicensed or doorless artifact is
    a warning nobody reads until the artifact is already out.

    THE MANIFEST is how a recipient, and the gate, can tell what they got: the file list, the count,
    the source commit, the UTC build time, and the profile. It carries NO absolute paths, by
    decision -- an absolute source path on this kind of machine contains a user account name and a
    checkout name, and the manifest ships. It also does not list itself, which is stated in the file
    rather than left for someone to deduce from a count that is one short.

    PRINT-AND-WRITE, and the write path is the only place that decides anything. -DryRun is honoured
    by the enumerator and by every mkdir and file write, not narrated over the top of a real build.

.PARAMETER OutDir
    Where to build. Created if absent. Refuses a directory holding anything this builder did not
    create, and refuses a previous pack unless -Force. Required for a real build; optional under
    -DryRun, which has no destination because it writes nothing.

.PARAMETER Profile
    Which pack to build. 'public' is the ONLY currently-valid value, and the switch exists anyway so
    that adding a second profile later -- a narrower internal pack, say -- does not have to rewrite
    every caller and every CI step at the same time as introducing the profile. One value today is
    the honest state; a [ValidateSet] with one member says so out loud and refuses a typo, where a
    free string would build a differently-named nothing.

    The parameter VARIABLE is $PackProfile, not $Profile: $PROFILE is a PowerShell automatic
    variable, so a parameter of that name shadows it inside this script. -Profile is what a caller
    types, via an alias, because that is the flag the callers were specified against.

.PARAMETER PackRoot
    The tree that becomes the pack's content directory. Default: the directory this script lives in
    -- tools/, which IS the pack content root today.

.PARAMETER SourceRoot
    Repository root: where the pack's root files -- LICENSE, NOTICE and PACK-README.md -- and the
    git metadata are read from. Default: the parent of PackRoot.

.PARAMETER Prefix
    Directory under OutDir at which the content tree is placed. Default: the leaf name of PackRoot,
    i.e. tools/. Pass '' to stage the content at the pack root.

.PARAMETER ExcludeRegex
    The non-content exclusion pattern. Default: parsed out of the content gate (see -ScanGate), so
    the pack and the scanner cannot disagree about what is not content. Pass it explicitly when the
    caller has already parsed it -- which is what Test-SharePackClean.ps1 does.

.PARAMETER ScanGate
    The gate the exclusion pattern is read out of. Default: Test-PracticeClaims.ps1 beside this
    script.

.PARAMETER GateDir
    The registry directory the HOLD LIST is loaded from. Default: practice-gate beside this script.
    hold-classes.json is preferred; hold-classes.example.json is the shipped generic fallback; with
    neither present the build FAILS rather than staging a tree nothing was withheld from.

.PARAMETER SourceCommit
    Assert the source commit instead of asking git. For building from an export that has no .git.
    Without it, and with no resolvable commit, the build FAILS: a manifest whose provenance field
    reads "unknown" is not provenance.

.PARAMETER Skip
    Steps to deliberately not run. A skipped step exits 2 and is named in the report; it is never
    counted as a pass.

.PARAMETER Force
    Rebuild over a previous pack in OutDir -- the pack directory and the manifest, and nothing else.
    It does NOT authorise clearing a directory that holds anything else; that is refused with or
    without it.

.PARAMETER DryRun
    Enumerate what would be staged and write nothing at all -- no OutDir, no tree, no manifest.
    Exits 2, because a dry run is the whole build deliberately not done and must not be mistaken in
    a log or a pipeline for a green build.

.PARAMETER SelfTest
    Run the negative controls in a temp directory and exit. Writes nothing inside the repository.

.EXAMPLE
    pwsh -NoProfile -File tools/Build-SharePack.ps1 -OutDir out/share-pack

.EXAMPLE
    pwsh -NoProfile -File tools/Build-SharePack.ps1 -OutDir out/share-pack -Force

.EXAMPLE
    pwsh -NoProfile -File tools/Build-SharePack.ps1 -DryRun

.EXAMPLE
    pwsh -NoProfile -File tools/Build-SharePack.ps1 -SelfTest

.NOTES
    EXIT CONTRACT -- the same one every gate in this pack uses, deliberately, so a builder cannot
    invent a softer vocabulary than the gate that judges its output:
      0  the pack was built and verified clean
      1  the build FAILED, or a step measured nothing (INCONCLUSIVE), or the environment could not
         be resolved
      2  the pack was built and something was deliberately not done (-Skip), or -DryRun -- SKIPPED,
         never a pass

    A skip is never a pass, and there is no silent pass: the last thing a real build does is read
    the tree and the manifest back OFF DISK and compare them, so "reported success" and "produced
    the artifact" cannot come apart.

    IDEMPOTENT: two -Force builds of one commit produce the same tree and the same file list. The
    manifest is not byte-identical between them and is not meant to be -- built_utc differs by
    design, because when a pack was assembled is a fact a recipient needs and a reproducibility
    claim this repository has no way to make.

    ps1-safety: $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest. READ-ONLY against the
    repository -- every write lands under -OutDir, and -SelfTest writes only into a temp directory it
    creates and removes. Files are written with [System.IO.File]::WriteAllText and never with
    Set-Content: Set-Content supports ShouldProcess, so under -WhatIf it writes NOTHING while the
    success message still prints -- a builder reporting success having done nothing. Every
    destructive action is guarded by an existence check and touches only paths this script created.
    No network, no secrets echoed, no ShouldProcess anywhere. Tolerates CRLF, since CI checks out on
    windows-latest.
#>
[CmdletBinding()]
param(
    [string]$OutDir,
    [Alias('Profile')]
    [ValidateSet('public')]
    [string]$PackProfile = 'public',
    [string]$PackRoot,
    [string]$SourceRoot,
    [string]$Prefix,
    [string]$ExcludeRegex,
    [string]$ScanGate,
    [string]$GateDir,
    [string]$SourceCommit,
    [ValidateSet('Manifest', 'Verify')]
    [string[]]$Skip = @(),
    [switch]$Force,
    [switch]$DryRun,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ── OUTCOME VOCABULARY ──────────────────────────────────────────────────────────
# PASS / FAIL / INCONCLUSIVE / SKIPPED, with INCONCLUSIVE meaning the step ran and measured nothing.
# A FOURTH copy of the vocabulary the three gates share, and a fourth copy is a fork unless something
# compares them. What compares this one is Test-SharePackClean.ps1: it invokes this builder and reads
# the manifest, so a divergence here surfaces there as a gate that cannot build its own subject,
# rather than as a quiet pass.

class BuildStep {
    [string]$Name
    [string]$Status
    [int]$Count
    [System.Collections.Generic.List[string]]$Findings
    [string]$Note

    BuildStep([string]$name) {
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

    [void] Skip([string]$why) {
        $this.Status = 'SKIPPED'
        $this.Note = $why
    }

    # INCONCLUSIVE must not overwrite a recorded FAIL: a step that found a defect has measured
    # something by definition, and relabelling it would hide the finding and misdescribe it.
    [void] Seal([string]$emptyNote) {
        if ($this.Count -eq 0 -and $this.Status -eq 'PASS') {
            $this.Status = 'INCONCLUSIVE'
            $this.Note = $emptyNote
        }
    }
}

# ── WHAT THE PACK IS, as constants ──────────────────────────────────────────────
# Three root files and a schema string. Everything else about the pack is enumerated, parsed or
# measured; these are the only facts about it that are written down, and each is written down
# exactly once.

# THE PACK ROOT LAYER, as SOURCE -> DESTINATION. Copied to the pack ROOT, beside the content tree
# and NEVER INTO IT: Apache-2.0 4(a) is satisfied by "a copy of this License", which means the file
# a recipient can find, and a licence filed inside a subdirectory of a distribution is a licence
# somebody has to go looking for. The same argument puts the README there, for the same reason with
# the legal clause taken out: a front door nobody trips over is not a front door.
#
# THAT SENTENCE USED TO END "and never renamed", stated as a rule about every root file, and this
# table makes it false -- so it is amended here rather than left to rot, which is the defect class
# this repository keeps writing gates against. The rule was over-broad because it generalised from
# the one root file whose rename happens to be zero characters wide. What each root file must
# actually carry is THE NAME THE RECIPIENT'S TOOLING AND HABITS LOOK FOR, and it is that name --
# never the source tree's name -- that may not be changed:
#   * LICENSE stays LICENSE because a licence scanner, a forge's licence detector and a lawyer all
#     look for exactly that, so 4(a)'s "can find it" is a claim about the name as much as the place.
#   * NOTICE stays NOTICE on the same argument for 4(d).
#   * The front door has to arrive as README.md, because that is the name a forge renders on the
#     repository page. It cannot be AUTHORED as README.md: this repository already has a README.md,
#     describing the repository rather than the pack, and two files cannot share one path. So the
#     pack's README is authored as PACK-README.md and takes its recipient-facing name on the way
#     out. Renaming it is not a weakening of the rule above, it is the rule applied to a file whose
#     source and destination names genuinely differ.
#
# ONE SEAM. Every consumer derives from this table and none of them restates it: the source
# preflight tests Source, the copy reads Source and writes Dest, the -Force ownership list and the
# manifest are Dest (they describe the PACK, not the tree it came from), and Why is the sentence the
# preflight fails with, so the reason a file is mandatory lives beside the file rather than in the
# error message of whichever check happened to notice first. Dest defaults to Source, so a root file
# that is not renamed is still written down exactly once.
$script:RootFiles = @(
    @{ Source = 'LICENSE'
        Why   = 'Apache-2.0 4(a) requires a redistribution to carry the License text, so a pack without it is an unlicensed distribution'
    }
    @{ Source = 'NOTICE'
        Why   = 'Apache-2.0 4(d) requires the NOTICE file of a work that has one to travel with a redistribution of it, and this work has one'
    }
    @{ Source = 'PACK-README.md'
        Dest  = 'README.md'
        Why   = 'the pack is published as a standalone repository, and its README is the only thing that tells a cloner what a LICENSE, a NOTICE, a manifest and a tools/ directory are -- a declared part of the pack, so its absence is a build failure for the completeness reason rather than the legal one'
    }
) | ForEach-Object {
    [pscustomobject]@{
        Source = [string]$_.Source
        Dest   = if ($_.ContainsKey('Dest')) { [string]$_.Dest } else { [string]$_.Source }
        Why    = [string]$_.Why
    }
}

$script:ManifestName = 'share-pack-manifest.json'
$script:ManifestSchema = 'share-pack-manifest/v1'

# ── HELPERS ─────────────────────────────────────────────────────────────────────

function Get-PackRelPath {
    param([string]$FullName, [string]$Root)
    return $FullName.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/'
}

function Get-SortedOrdinal {
    # ORDINAL, not Sort-Object. Sort-Object is culture-sensitive, so the same tree sorts differently
    # on a runner with a different culture -- and the manifest's file list is a thing two independent
    # enumerations are compared through. A list whose ORDER depends on the machine turns that
    # comparison into a coin toss on the day somebody compares it as text.
    param([string[]]$Values)
    $copy = [string[]]::new($Values.Count)
    [System.Array]::Copy($Values, $copy, $Values.Count)
    [System.Array]::Sort($copy, [System.StringComparer]::Ordinal)
    return , $copy
}

function Get-PackExcludeRegex {
    # Read out of the content gate, never restated here. This is the move Test-SharePackClean.ps1
    # makes for the same value and the local-CI runner makes against a workflow file, and it fails
    # in the LOUD direction on purpose: rename that line and the build stops with an error naming
    # the parse, rather than quietly staging against a remembered pattern that no longer matches
    # what the scanner skips. The resolution is always to update the parse, never to hardcode.
    param([string]$ScanGate)

    if (-not (Test-Path -LiteralPath $ScanGate)) {
        throw "the content gate is not at $ScanGate, so the pack's non-content exclusions cannot be read out of it -- pass -ExcludeRegex explicitly, or -ScanGate to where the gate lives. A build that guesses this ships a tree the scanner never agreed to."
    }
    $raw = [System.IO.File]::ReadAllText($ScanGate)
    $m = [regex]::Match($raw, '\$_\.FullName\s+-notmatch\s+''(?<rx>[^'']+)''')
    if (-not $m.Success) {
        throw "cannot find the content gate's directory-exclusion pattern in $ScanGate -- its shape changed, and staging must not mirror a pattern it could not read"
    }
    return $m.Groups['rx'].Value
}

function Import-HoldClasses {
    # THE HOLD LIST, loaded fail-closed. Same resolution order, same two names, same throw as
    # Test-PracticeClaims.ps1's Import-RedactionClasses -- deliberately the same shape, because the
    # two tables answer the same kind of question about different subjects and there is nothing to
    # be gained by a second style. A recipient has only the .example table, this repository has
    # both, and a recipient must not be handed a red build for being in the state the distribution
    # puts them in. What they must not be handed is a silent one: the table's NAME goes in the
    # report and in the manifest, in both directions.
    #
    # AND WITH NEITHER FILE PRESENT THIS THROWS. An empty hold list withholds nothing, which is
    # indistinguishable from a pack that had nothing to withhold -- and the difference is the whole
    # decision this list records.
    param([string]$GateDir)

    $real = Join-Path $GateDir 'hold-classes.json'
    $example = Join-Path $GateDir 'hold-classes.example.json'

    if (Test-Path -LiteralPath $real -PathType Leaf) { $path = $real; $source = 'real' }
    elseif (Test-Path -LiteralPath $example -PathType Leaf) { $path = $example; $source = 'example' }
    else {
        throw "no hold class table in $GateDir -- neither hold-classes.json nor hold-classes.example.json is there, so the build has no list of assets to withhold and would ship every one of them while reporting success"
    }

    $name = [System.IO.Path]::GetFileName($path)
    $table = $null
    try { $table = [System.IO.File]::ReadAllText($path) | ConvertFrom-Json -AsHashtable }
    catch { throw "$name does not parse as JSON ($($_.Exception.Message)) -- a hold list that failed to load withholds nothing" }
    if (-not $table.ContainsKey('classes')) {
        throw "$name has no 'classes' key -- shape check failed, and a build must not withhold nothing by reading nothing"
    }
    $classes = @($table.classes)
    if ($classes.Count -eq 0) {
        throw "$name has an empty 'classes' list -- that would ship everything while looking like a clean build"
    }
    return @{ Classes = $classes; Source = $source; File = $name }
}

function Test-HoldClassTable {
    # THE RUN-TIME POSITIVE CONTROL, run before anything is withheld and not only in the self-test.
    # A pattern that has stopped matching withholds nothing, reports nothing, and looks exactly like
    # a pack with nothing to withhold; the counter-example is the other direction, and it is the one
    # that bites here, because the near-misses are one word apart (settings.json vs
    # settings.template.json, hold-classes.json vs hold-classes.example.json) and a class too broad
    # silently drops a file the recipient needed.
    #
    # [regex]::IsMatch, NOT -match: PowerShell's -match is case-insensitive by default, and a class
    # written without (?i) would be reported healthy against an example the walk itself walks past.
    param([object[]]$Classes, [string]$TableName)

    $findings = [System.Collections.Generic.List[string]]::new()
    foreach ($c in @($Classes)) {
        $label = if ($c.ContainsKey('name') -and -not [string]::IsNullOrWhiteSpace([string]$c.name)) { [string]$c.name } else { '(unnamed)' }
        $ok = $true
        foreach ($k in @('name', 'pattern', 'example', 'reason')) {
            if (-not $c.ContainsKey($k) -or [string]::IsNullOrWhiteSpace([string]$c[$k])) {
                $findings.Add("${TableName}: hold class '$label' is missing required key '$k' -- an unnamed, unexplained or patternless class cannot be trusted to withhold anything")
                $ok = $false
            }
        }
        if (-not $ok) { continue }
        if (-not [regex]::IsMatch([string]$c.example, [string]$c.pattern)) {
            $findings.Add("${TableName}: hold class '$label' no longer matches its own example ('$($c.example)') -- the pattern is broken, so this class withholds nothing and the build cannot tell that apart from a clean pack")
            continue
        }
        if ($c.ContainsKey('counter_example') -and -not [string]::IsNullOrWhiteSpace([string]$c.counter_example)) {
            if ([regex]::IsMatch([string]$c.counter_example, [string]$c.pattern)) {
                $findings.Add("${TableName}: hold class '$label' matches its counter-example ('$($c.counter_example)'), which the pack is supposed to SHIP -- the pattern is too broad and would silently withhold a file the recipient needs")
            }
        }
    }
    return $findings
}

function Get-PackProvenance {
    # The commit the pack was built from, plus whether the working tree matched it. Both go in the
    # manifest; the second is why the first is not a reproducibility claim on its own.
    param([string]$SourceRoot, [string]$SourceCommit)

    if (-not [string]::IsNullOrWhiteSpace($SourceCommit)) {
        return @{ Commit = $SourceCommit.Trim(); State = 'asserted'; Error = '' }
    }

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        return @{ Commit = ''; State = 'unresolved'; Error = 'git is not on PATH' }
    }

    # In PowerShell 7.4+ $PSNativeCommandUseErrorActionPreference defaults on, so a non-zero exit
    # from a native command THROWS under $ErrorActionPreference = 'Stop'. Building outside a
    # repository is a case this function is supposed to answer, not a case it should die of, so the
    # preference is turned off for this scope and the exit code is read explicitly.
    $PSNativeCommandUseErrorActionPreference = $false

    # --show-toplevel first, and compared. `git -C <dir> rev-parse HEAD` walks UP: run inside a
    # subdirectory of some unrelated repository -- %TEMP% on a machine where it happens to sit under
    # one, an export unpacked inside a checkout -- it cheerfully answers with an ANCESTOR's commit,
    # which does not describe this tree at all. A wrong SHA in a manifest is worse than none: the
    # recipient can act on it.
    $top = ''
    try {
        $out = git -C $SourceRoot rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0) { $top = "$out".Trim() }
    }
    catch {
        $top = ''
    }
    if ([string]::IsNullOrWhiteSpace($top)) {
        return @{ Commit = ''; State = 'unresolved'; Error = "$SourceRoot is not inside a git repository" }
    }
    $a = [System.IO.Path]::GetFullPath($top).TrimEnd('\', '/')
    $b = [System.IO.Path]::GetFullPath($SourceRoot).TrimEnd('\', '/')
    if (-not $a.Equals($b, [System.StringComparison]::OrdinalIgnoreCase)) {
        return @{ Commit = ''; State = 'unresolved'; Error = "the enclosing git repository is $a, not the source root -- its HEAD does not describe this tree" }
    }

    $commit = ''
    try {
        $out = git -C $SourceRoot rev-parse HEAD 2>$null
        if ($LASTEXITCODE -eq 0) { $commit = "$out".Trim() }
    }
    catch {
        $commit = ''
    }
    if ([string]::IsNullOrWhiteSpace($commit)) {
        return @{ Commit = ''; State = 'unresolved'; Error = 'the repository has no HEAD commit' }
    }

    $state = 'clean'
    try {
        $porcelain = git -C $SourceRoot status --porcelain 2>$null
        if ($LASTEXITCODE -ne 0) { $state = 'unknown' }
        elseif (-not [string]::IsNullOrWhiteSpace(($porcelain | Out-String))) { $state = 'dirty' }
    }
    catch {
        $state = 'unknown'
    }
    return @{ Commit = $commit; State = $state; Error = '' }
}

# ── STAGING -- THE SINGLE SOURCE OF TRUTH ───────────────────────────────────────
# Lifted out of Test-SharePackClean.ps1's New-PackStage, whose live call site and self-test cases
# this replaces rather than joins. Same parameters, same returned shape -- Root, PackDir, Prefix,
# RelPaths, Excluded -- because a caller that was reading Stage.Excluded must keep reading it: a
# Coverage check downstream reports "N excluded as non-content", and losing the count would turn a
# broken exclusion pattern into a clean-looking run.
#
# NOT NAMED New-PackStage, and the reason is not cosmetic. PSScriptAnalyzer's state-changing-verb
# rule demands SupportsShouldProcess on a New-* function, and ShouldProcess is precisely the
# mechanism that makes a writer report success having written nothing under -WhatIf -- the failure
# this file's .NOTES names about Set-Content. The alternative was a fourth registered analyzer
# exception for a decision the repository has already made three times. Copy- is an approved verb,
# it is not in that rule's set, and it says what the function does.
#
# Two deliberate divergences from the lifted original, both in the loud direction:
#   * -DryRun. The original always copied, because it was only ever called to produce a tree the
#     caller was about to scan. A builder has to be able to enumerate without writing, and the
#     enumeration and the copy must be the SAME walk -- a dry run that lists via one code path what
#     a real run copies via another is a preview of a different build.
#   * No -ErrorAction SilentlyContinue on the enumeration. The original silenced it; in a gate that
#     costs coverage, in a builder it ships a pack with a file missing and reports success. An
#     unreadable source file stops the build.
#
# TWO FILTERS, APPLIED IN ORDER AND COUNTED APART. Non-content first (mechanics: compiled residue
# nothing can read), then the hold list (a decision: assets that must never leave). The order is
# load-bearing only in that it decides which counter a __pycache__ file lands in -- it is
# non-content, and reporting it as "withheld by decision" would make the decision counter unreadable
# -- but the SEPARATION is load-bearing everywhere. Collapsing them into one number would make "the
# hold list withheld nothing today" and "the hold list stopped matching" the same output, which is
# the failure this whole file is arranged against.
function Copy-PackTree {
    param(
        [string]$PackRoot,
        [string]$StageRoot,
        [string]$Prefix,
        [string]$ExcludeRegex,
        [object[]]$HoldClasses = @(),
        [switch]$DryRun
    )

    $packDir = if ([string]::IsNullOrEmpty($Prefix)) { $StageRoot } else { Join-Path $StageRoot $Prefix }
    if (-not $DryRun) {
        if (-not (Test-Path -LiteralPath $packDir)) { $null = New-Item -ItemType Directory -Path $packDir -Force }
    }

    $excluded = 0
    $copied = [System.Collections.Generic.List[string]]::new()
    $held = [System.Collections.Generic.List[string]]::new()
    foreach ($f in @(Get-ChildItem -LiteralPath $PackRoot -Recurse -File)) {
        # Mirror the scanner's own exclusions, using the pattern parsed out of it, so the staged tree
        # and the scanned tree cannot disagree about what counts as content.
        if ($ExcludeRegex -and $f.FullName -match $ExcludeRegex) { $excluded++; continue }
        $rel = Get-PackRelPath -FullName $f.FullName -Root $PackRoot
        # The hold list, against the PACK-RELATIVE path with forward slashes -- the same string the
        # gate's own hold check matches, and the same string the classes' worked examples are
        # written as. Matching the absolute source path instead would make every class that anchors
        # on (^|/) behave differently here than in the gate.
        #
        # [regex]::IsMatch, not -match, for the reason Test-HoldClassTable gives: the controls and
        # the walk must agree about case, and only one of the two spellings is case-sensitive.
        $isHeld = $false
        foreach ($c in @($HoldClasses)) {
            if ([regex]::IsMatch($rel, [string]$c.pattern)) { $isHeld = $true; break }
        }
        if ($isHeld) { $held.Add($rel); continue }
        if (-not $DryRun) {
            $dest = Join-Path $packDir $rel
            $destDir = Split-Path -Parent $dest
            if (-not (Test-Path -LiteralPath $destDir)) { $null = New-Item -ItemType Directory -Path $destDir -Force }
            Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
        }
        $copied.Add($rel)
    }

    # Resolve-Path would have to touch the disk, and under -DryRun there is nothing there to touch.
    # GetFullPath normalises lexically, so both modes return the same shape of path.
    return @{
        Root      = [System.IO.Path]::GetFullPath($StageRoot)
        PackDir   = [System.IO.Path]::GetFullPath($packDir)
        Prefix    = $Prefix
        RelPaths  = $copied
        Excluded  = $excluded
        HeldPaths = $held
    }
}

function Copy-PackRootFile {
    # The pack root layer -- LICENSE, NOTICE, README.md -- read by SOURCE name and written under
    # DESTINATION name. Returns what it took and what it could not find; the caller turns a Missing
    # entry into a build FAILURE, because neither an unlicensed pack nor a pack that cannot say what
    # it is may exist even briefly enough for somebody to send it.
    #
    # Copied is DESTINATION names and Missing is SOURCE names, which is not an inconsistency: Copied
    # goes into the manifest, which describes the pack a recipient holds, and Missing goes into an
    # error message naming the file somebody has to go and put back.
    param(
        [string]$SourceRoot,
        [string]$StageRoot,
        [object[]]$Files,
        [switch]$DryRun
    )

    $copied = [System.Collections.Generic.List[string]]::new()
    $missing = [System.Collections.Generic.List[string]]::new()
    foreach ($f in $Files) {
        $src = Join-Path $SourceRoot $f.Source
        if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { $missing.Add($f.Source); continue }
        if (-not $DryRun) {
            Copy-Item -LiteralPath $src -Destination (Join-Path $StageRoot $f.Dest) -Force
        }
        $copied.Add($f.Dest)
    }
    return @{ Copied = $copied; Missing = $missing }
}

# ── THE OUTPUT DIRECTORY ────────────────────────────────────────────────────────
# Refuse rather than clobber, and back up nothing this script did not create. -Force authorises
# rebuilding a PACK -- the content directory and the manifest -- and nothing wider. A directory
# holding anything else is somebody's directory, and it is refused with or without -Force, which is
# the difference between an idempotent builder and `rm -rf $OutDir`.

function Get-OutDirState {
    # $RootDestNames is the DESTINATION side of the root-file seam, and it has to be: what this
    # builder owns in the output directory is what it WRITES there. Handed the source names instead,
    # a rebuild would look for PACK-README.md, find the README.md its own previous run had placed,
    # class it a stranger and refuse -- and the refusal would name the wrong file.
    param([string]$OutDir, [string]$Prefix, [string]$ManifestName, [string[]]$RootDestNames)

    # EVERYTHING this builder writes, and the list has to be complete or -Force stops working. It
    # was first written without the root files, which meant the second -Force build of any pack saw
    # the LICENSE and NOTICE its own previous run had put there, decided the destination belonged to
    # somebody else, and refused. Caught by the idempotence control, which is what that control is
    # for -- the failure was in the safety rule, not in the pack.
    $owned = @()
    if (-not [string]::IsNullOrEmpty($Prefix)) { $owned += $Prefix }
    $owned += $ManifestName
    foreach ($n in $RootDestNames) { $owned += $n }

    if (-not (Test-Path -LiteralPath $OutDir)) {
        return @{ Exists = $false; Existing = @(); Strangers = @() }
    }
    $children = @(Get-ChildItem -LiteralPath $OutDir -Force | ForEach-Object { $_.Name })
    $strangers = @($children | Where-Object { $owned -notcontains $_ })
    $existing = @($children | Where-Object { $owned -contains $_ })
    return @{ Exists = $true; Existing = $existing; Strangers = $strangers }
}

# ── THE MANIFEST ────────────────────────────────────────────────────────────────

function Build-PackManifest {
    # An ordered dictionary, so the JSON reads top-down for a human: what this is, when and from
    # what it was built, then the counts, then the list.
    #
    # NO ABSOLUTE PATHS, deliberately. This file ships inside the pack, and an absolute source path
    # on the machines this is built on carries a user account name and a checkout name -- which is
    # the identifier class the content gate exists to keep out of the pack. Paths in here are
    # pack-relative and nothing else.
    param(
        [hashtable]$Stage,
        [string[]]$RootFiles,
        [hashtable]$Provenance,
        [string]$PackProfile,
        [string]$ExcludeRegex,
        [string]$HoldClassTable,
        [string]$BuiltUtc
    )

    # ONE list, at ONE grain: pack-root-relative, so LICENSE at the root and a file deep inside the
    # content tree are the same kind of entry and the count is the count of the whole pack. A caller
    # that wants the content-tree-relative form derives it by stripping pack_prefix -- deriving is
    # not drifting, whereas a second list beside this one would be.
    #
    # $RootFiles here is DESTINATION names, because this document describes the pack a recipient
    # holds and not the tree it was built from: the pack holds README.md, and a manifest listing the
    # source name PACK-README.md would send both the downstream gate and the recipient's own tooling
    # looking for a file that is not there.
    $all = [System.Collections.Generic.List[string]]::new()
    foreach ($n in $RootFiles) { $all.Add($n) }
    foreach ($rel in $Stage.RelPaths) {
        if ([string]::IsNullOrEmpty($Stage.Prefix)) { $all.Add($rel) }
        else { $all.Add("$($Stage.Prefix)/$rel") }
    }
    $files = Get-SortedOrdinal -Values $all.ToArray()

    # The withheld list, at the SAME grain as files -- pack-root-relative -- so a reader is not
    # switching grain between two lists in one document. It names paths and nothing else: no
    # patterns, no class names, no reasons. That is deliberate. The paths are the two starter-table
    # names a recipient is told about anyway; the classes and their reasons are the part that was
    # withheld in the first place, and copying them into a file that ships would undo the decision
    # this list is recording.
    $heldAll = [System.Collections.Generic.List[string]]::new()
    foreach ($rel in @($Stage.HeldPaths)) {
        if ([string]::IsNullOrEmpty($Stage.Prefix)) { $heldAll.Add($rel) }
        else { $heldAll.Add("$($Stage.Prefix)/$rel") }
    }
    $held = Get-SortedOrdinal -Values $heldAll.ToArray()

    return [ordered]@{
        _comment            = @(
            'Manifest for a share pack built by tools/Build-SharePack.ps1. It records what this',
            'pack contains and what it was built from, so a recipient can tell what they got and a',
            'gate can check the tree against a list rather than against a memory.',
            '',
            'files is pack-root-relative and holds EVERY file in the pack except this manifest,',
            'which cannot list itself. So the pack root holds file_count + 1 files in total.',
            '',
            'excluded_non_content counts files under the content tree that were deliberately not',
            'staged (compiled residue and the like), matched by exclude_regex. It is reported even',
            'when it is zero: "nothing was excluded" and "the exclusion pattern stopped matching"',
            'are different facts and must not share an output.',
            '',
            'held_back is a DIFFERENT KIND of not-staged, counted apart from the line above for that',
            'reason: not "nothing here can read it" but "this must not leave". held_back_paths names',
            'them, at the same pack-root-relative grain as files. hold_class_table names the table',
            'the decision came out of -- a build that fell back to the shipped .example table',
            'withheld placeholder paths and nothing of yours, and that is a fact about the pack',
            'rather than a footnote about the build.',
            '',
            'source_state qualifies source_commit. dirty means the working tree did not match the',
            'commit when this was built, so the SHA names an ancestor of these bytes, not these',
            'bytes. asserted means the commit was supplied by the caller rather than read from git.'
        )
        schema              = $script:ManifestSchema
        profile             = $PackProfile
        built_utc           = $BuiltUtc
        source_commit       = $Provenance.Commit
        source_state        = $Provenance.State
        pack_prefix         = $Stage.Prefix
        manifest_file       = $script:ManifestName
        exclude_regex       = $ExcludeRegex
        hold_class_table    = $HoldClassTable
        file_count          = $files.Count
        excluded_non_content = $Stage.Excluded
        held_back           = $held.Count
        held_back_paths     = $held
        files               = $files
    }
}

function Test-PackTree {
    # THE READ-BACK. Two independent enumerations of one pack: the manifest as it now sits on disk,
    # and a fresh walk of the built tree. A builder that reports what it INTENDED to write has
    # reported nothing -- "wrote it" and "wrote the right bytes in the right places" are different
    # states, and only reading it back tells them apart. Returns findings; empty means verified.
    param([string]$OutDir, [string]$ManifestPath, [string]$ManifestName)

    $findings = [System.Collections.Generic.List[string]]::new()

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        $findings.Add("no manifest at $ManifestName -- the pack cannot describe itself, so nothing here can confirm it is complete")
        return $findings
    }
    $manifest = $null
    try {
        $manifest = [System.IO.File]::ReadAllText($ManifestPath) | ConvertFrom-Json -AsHashtable
    }
    catch {
        $findings.Add("the manifest does not parse as JSON ($($_.Exception.Message)) -- a manifest a recipient's tooling cannot read is not a manifest")
        return $findings
    }
    foreach ($k in @('schema', 'file_count', 'files')) {
        if (-not $manifest.ContainsKey($k)) {
            $findings.Add("the manifest has no '$k' key -- shape check failed, refusing to verify by checking nothing")
        }
    }
    if ($findings.Count -gt 0) { return $findings }
    if ($manifest.schema -ne $script:ManifestSchema) {
        $findings.Add("the manifest declares schema '$($manifest.schema)' and this builder writes '$($script:ManifestSchema)' -- something else wrote it, or this run wrote nothing")
    }

    # [string[]] AFTER the @() wrap, not inside it: @() re-wraps into Object[], and a HashSet[string]
    # constructor has no overload taking IEnumerable[object] -- which fails as a missing overload at
    # the comparison below rather than as a type error here.
    $listed = [string[]]@($manifest.files)
    if ([int]$manifest.file_count -ne $listed.Count) {
        $findings.Add("the manifest says file_count $($manifest.file_count) and lists $($listed.Count) file(s) -- its own two statements about one pack disagree")
    }

    $onDisk = [System.Collections.Generic.List[string]]::new()
    foreach ($f in @(Get-ChildItem -LiteralPath $OutDir -Recurse -File)) {
        $rel = Get-PackRelPath -FullName $f.FullName -Root ([System.IO.Path]::GetFullPath($OutDir))
        if ($rel -eq $ManifestName) { continue }
        $onDisk.Add($rel)
    }
    $diskArray = [string[]]$onDisk.ToArray()
    $diskSet = [System.Collections.Generic.HashSet[string]]::new($diskArray, [System.StringComparer]::Ordinal)
    $listSet = [System.Collections.Generic.HashSet[string]]::new($listed, [System.StringComparer]::Ordinal)

    # ASSIGNED, then iterated. Get-SortedOrdinal returns `,$array` so that a one-file pack does not
    # unroll into a bare string on the way out -- and that same wrapper means `foreach ($x in
    # Get-SortedOrdinal ...)` iterates the WRAPPER exactly once, with $x bound to the whole array.
    # Both forms run clean; only one compares anything. This cost a run where every file in the pack
    # was reported missing and present at the same time, as one finding each.
    $listedSorted = Get-SortedOrdinal -Values $listed
    $diskSorted = Get-SortedOrdinal -Values $diskArray
    foreach ($rel in $listedSorted) {
        if (-not $diskSet.Contains($rel)) {
            $findings.Add("the manifest lists '$rel' and the built tree does not hold it -- the pack is short of what it claims")
        }
    }
    foreach ($rel in $diskSorted) {
        if (-not $listSet.Contains($rel)) {
            $findings.Add("the built tree holds '$rel' and the manifest does not list it -- the pack ships a file nothing accounted for")
        }
    }
    if ($onDisk.Count -ne $listed.Count) {
        $findings.Add("the built tree holds $($onDisk.Count) file(s) beside the manifest and the manifest counts $($listed.Count) -- two enumerations of one pack disagree, so neither may be relied on")
    }
    return $findings
}

# ── THE BUILD ───────────────────────────────────────────────────────────────────
# One function, so the self-test drives the same code the command line does. Steps fail forward: a
# FAILED step marks the ones that depend on it SKIPPED-by-dependency, and the exit resolution puts
# FAIL ahead of SKIPPED so a dependency cascade cannot downgrade a failure to a 2.

function Invoke-PackBuild {
    param(
        [string]$PackRoot,
        [string]$SourceRoot,
        [string]$OutDir,
        [string]$Prefix,
        [string]$ExcludeRegex,
        [object[]]$HoldClasses,
        [string]$HoldClassTable,
        [string]$PackProfile,
        [string]$SourceCommit,
        [string[]]$SkipSteps,
        [bool]$Force,
        [bool]$DryRun
    )

    $steps = [System.Collections.Generic.List[BuildStep]]::new()
    $result = @{
        Steps        = $steps
        Stage        = $null
        Manifest     = $null
        ManifestPath = ''
        Provenance   = $null
        OutDir       = $OutDir
    }

    # ---- step 1: the sources -----------------------------------------------------------------
    # Everything the build reads, checked before anything is written. A build that gets three steps
    # in and then discovers there is no LICENSE has already created a directory and half a pack.
    $s1 = [BuildStep]::new('Sources')
    if (-not (Test-Path -LiteralPath $PackRoot -PathType Container)) {
        $s1.Fail("the content root '$PackRoot' does not exist -- a builder that cannot find its subject must not report success")
    }
    else { $s1.Count++ }
    if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
        $s1.Fail("the source root '$SourceRoot' does not exist, so the pack's root files and the source commit cannot be read")
    }
    else { $s1.Count++ }

    # THE SOURCE side of the root-file seam, because this is the only check that looks at the
    # repository rather than at the pack: it is PACK-README.md that has to be present here, and
    # README.md that has to be present in the built pack. A preflight testing the destination name
    # would go looking for the repository's OWN README.md, find it, and pass on the wrong file.
    #
    # Each failure carries the file's own Why, so the reason a root file is mandatory travels with
    # the file. The severity does not: it is the same for all three and it is stated once, here,
    # because it comes from what this builder IS -- a completeness proof, which cannot distinguish a
    # deliberate omission from a lost file unless a missing declared file stops the build.
    $rootPresent = @()
    if (Test-Path -LiteralPath $SourceRoot -PathType Container) {
        foreach ($rf in $script:RootFiles) {
            if (Test-Path -LiteralPath (Join-Path $SourceRoot $rf.Source) -PathType Leaf) { $rootPresent += $rf.Source; $s1.Count++ }
            else {
                $s1.Fail("$($rf.Source) is not at the source root, and it is a declared part of the pack: $($rf.Why). This is a build failure and not a warning -- a builder whose job is proving the pack complete cannot report a pass on a pack it knows is short")
            }
        }
    }

    # THE HOLD LIST IS A SOURCE INPUT, and it is proved here rather than trusted at the walk. A
    # broken class means the build must not run at all: staging happens in step 3, so a failure here
    # cascades to SKIPPED and no tree is written. A pack assembled with a hold class that had stopped
    # matching is the exact artifact this list exists to prevent, and it looks like a clean build.
    $holdList = @($HoldClasses)
    if ($holdList.Count -eq 0) {
        $s1.Fail("the hold class table is empty -- nothing would be withheld from this pack, and a build that withholds nothing is indistinguishable from a build with nothing to withhold. Import-HoldClasses throws rather than returning an empty table, so reaching here means it was bypassed")
    }
    else {
        foreach ($f in Test-HoldClassTable -Classes $holdList -TableName $HoldClassTable) { $s1.Fail($f) }
        $s1.Count++
    }

    $prov = Get-PackProvenance -SourceRoot $SourceRoot -SourceCommit $SourceCommit
    $result.Provenance = $prov
    if ($prov.State -eq 'unresolved') {
        $s1.Fail("no source commit: $($prov.Error) -- pass -SourceCommit if you are building from an export. A manifest whose provenance reads 'unknown' answers the recipient's only question with a shrug")
    }
    else { $s1.Count++ }

    $s1.Seal('checked zero source inputs -- the preflight itself is broken')
    if ($s1.Status -eq 'PASS') {
        $s1.Note = "commit $($prov.Commit.Substring(0, [Math]::Min(12, $prov.Commit.Length))) ($($prov.State)); $($rootPresent -join ' + ') present; $($holdList.Count) hold class(es) from $HoldClassTable, each proved against its own example"
    }
    $steps.Add($s1)

    if ($s1.Status -ne 'PASS') {
        foreach ($n in @('OutDir', 'Stage', 'Manifest', 'Verify')) {
            $s = [BuildStep]::new($n)
            $s.Skip('not run: the source preflight failed, and nothing may be written against sources that did not resolve')
            $steps.Add($s)
        }
        return $result
    }

    # ---- step 2: the output directory --------------------------------------------------------
    $s2 = [BuildStep]::new('OutDir')
    if ($DryRun) {
        $s2.Skip('dry run -- no directory created, nothing removed')
    }
    else {
        $state = Get-OutDirState -OutDir $OutDir -Prefix $Prefix -ManifestName $script:ManifestName -RootDestNames @($script:RootFiles.Dest)
        $s2.Count = 1
        if ($state.Strangers.Count -gt 0) {
            $s2.Fail("'$OutDir' holds $($state.Strangers.Count) item(s) this builder did not create ($(($state.Strangers | Select-Object -First 4) -join ', ')) -- refusing to build into somebody else's directory, with or without -Force. Point -OutDir at a new path or at a directory that holds only a previous pack")
        }
        elseif ($state.Existing.Count -gt 0 -and -not $Force) {
            $s2.Fail("'$OutDir' already holds a pack ($(($state.Existing) -join ', ')) -- pass -Force to rebuild it. Refusing rather than clobbering: an overwrite that was not asked for is indistinguishable from a build that quietly lost files")
        }
        else {
            foreach ($n in $state.Existing) {
                # Guarded, and scoped to the two names this builder owns. Re-tested immediately
                # before the delete rather than trusted from the enumeration above.
                $p = Join-Path $OutDir $n
                if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
            }
            if (-not (Test-Path -LiteralPath $OutDir)) { $null = New-Item -ItemType Directory -Path $OutDir -Force }
            $s2.Note = if ($state.Existing.Count -gt 0) { "rebuilt over a previous pack (-Force): $(($state.Existing) -join ', ')" } else { 'clean destination' }
        }
    }
    $steps.Add($s2)

    if ($s2.Status -eq 'FAIL') {
        foreach ($n in @('Stage', 'Manifest', 'Verify')) {
            $s = [BuildStep]::new($n)
            $s.Skip('not run: the output directory was refused')
            $steps.Add($s)
        }
        return $result
    }

    # ---- step 3: stage -----------------------------------------------------------------------
    $s3 = [BuildStep]::new('Stage')
    $stage = Copy-PackTree -PackRoot $PackRoot -StageRoot $OutDir -Prefix $Prefix -ExcludeRegex $ExcludeRegex `
        -HoldClasses $holdList -DryRun:$DryRun
    $result.Stage = $stage
    $rootCopy = Copy-PackRootFile -SourceRoot $SourceRoot -StageRoot $OutDir -Files $script:RootFiles -DryRun:$DryRun
    foreach ($n in $rootCopy.Missing) {
        # Belt and braces: step 1 already failed on this, so reaching here means the file vanished
        # between the preflight and the copy. Rare, and the wrong thing to discover from a count. The
        # SOURCE name is what this reports, because that is the file somebody has to go and restore.
        $s3.Fail("$n disappeared between the preflight and the copy -- the pack would ship without a declared root file")
    }
    $s3.Count = @($stage.RelPaths).Count + @($rootCopy.Copied).Count
    $s3.Seal('staged zero files -- the content root is empty or the walk is broken, and an empty pack must not report a pass')
    if ($s3.Status -eq 'PASS') {
        $s3.Note = "$(@($stage.RelPaths).Count) file(s) under $(if ($Prefix) { "$Prefix/" } else { '<pack root>' }) + $(@($rootCopy.Copied).Count) at the pack root; $($stage.Excluded) excluded as non-content; $(@($stage.HeldPaths).Count) held back by $HoldClassTable"
    }
    $steps.Add($s3)

    if ($s3.Status -ne 'PASS') {
        foreach ($n in @('Manifest', 'Verify')) {
            $s = [BuildStep]::new($n)
            $s.Skip('not run: staging did not produce a tree to describe')
            $steps.Add($s)
        }
        return $result
    }

    # ---- step 4: the manifest ----------------------------------------------------------------
    $manifestPath = Join-Path $OutDir $script:ManifestName
    $result.ManifestPath = $manifestPath
    $s4 = [BuildStep]::new('Manifest')
    $manifest = Build-PackManifest -Stage $stage -RootFiles @($rootCopy.Copied) -Provenance $prov `
        -PackProfile $PackProfile -ExcludeRegex $ExcludeRegex -HoldClassTable $HoldClassTable `
        -BuiltUtc ([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))
    $result.Manifest = $manifest

    if ($DryRun) { $s4.Skip('dry run -- nothing written') }
    elseif ($SkipSteps -contains 'Manifest') {
        $s4.Skip('deliberately not run (-Skip Manifest) -- this is not a pass: the pack cannot say what it contains')
    }
    else {
        $json = ($manifest | ConvertTo-Json -Depth 6) + "`n"
        # WriteAllText, never Set-Content: Set-Content supports ShouldProcess, so under -WhatIf it
        # writes NOTHING while the success message still prints -- a builder reporting success
        # having done nothing. No BOM, because this is JSON read by other people's tooling and a
        # BOM is what makes a strict JSON parser reject the first byte of a valid document.
        [System.IO.File]::WriteAllText($manifestPath, $json, [System.Text.UTF8Encoding]::new($false))
        $s4.Count = [int]$manifest['file_count']
        $s4.Note = "$($script:ManifestName): $($manifest['file_count']) file(s), $($manifest['excluded_non_content']) excluded, $($manifest['held_back']) held back"
    }
    $steps.Add($s4)

    # ---- step 5: read it back ----------------------------------------------------------------
    $s5 = [BuildStep]::new('Verify')
    if ($DryRun) { $s5.Skip('dry run -- there is no tree to read back') }
    elseif ($SkipSteps -contains 'Verify') {
        $s5.Skip('deliberately not run (-Skip Verify) -- this is not a pass: nothing has confirmed the tree matches the manifest')
    }
    elseif ($s4.Status -ne 'PASS') {
        $s5.Skip('not run: it compares the tree against the manifest, and the manifest step did not run')
    }
    else {
        foreach ($f in Test-PackTree -OutDir $OutDir -ManifestPath $manifestPath -ManifestName $script:ManifestName) {
            $s5.Fail($f)
        }
        $s5.Count = [int]$manifest['file_count']
        if ($s5.Status -eq 'PASS') { $s5.Note = 'the built tree and the manifest agree, file for file' }
    }
    $steps.Add($s5)

    return $result
}

function Get-PackExit {
    # FAIL ahead of SKIPPED ahead of PASS. The order is the contract: a skip must never be able to
    # mask a failure, and a skip must never be reported as a pass.
    param([object[]]$Steps)
    if (@($Steps | Where-Object { $_.Status -in @('FAIL', 'INCONCLUSIVE') }).Count -gt 0) { return 1 }
    if (@($Steps | Where-Object { $_.Status -eq 'SKIPPED' }).Count -gt 0) { return 2 }
    return 0
}

# ── SELF-TEST ───────────────────────────────────────────────────────────────────
# Negative controls, in the shape the two gates use. The point is not that the builder works on a
# good day: it is that each guarantee it claims FAILS when it should. A control that has only ever
# been green is not evidence.

function Assert-Case {
    param([string]$Name, [string]$Expected, [string]$Actual)
    $ok = $Expected -eq $Actual
    $mark = if ($ok) { 'ok  ' } else { 'FAIL' }
    Write-Host ("  [{0}] {1,-62} expected {2}, got {3}" -f $mark, $Name, $Expected, $Actual)
    return $ok
}

function Write-Fixture {
    # The fixture repository-shaped tree every control below is built from: a source root holding
    # the three root files, a content tree, and the three things the pack must not contain -- .git,
    # .github and skills/ -- sitting exactly where they sit in the real repository, i.e. OUTSIDE the
    # content root. Their absence from a built pack is then a measured property of the copy root
    # rather than a claim about a filter.
    #
    # It also holds a README.md OF ITS OWN, which is not scenery: it is the reason the pack's front
    # door is authored as PACK-README.md, and it is the file a preflight written against the
    # destination name would find instead. Its absence from the built pack is asserted below, so the
    # rename is measured as a rename rather than as "some README arrived".
    param([string]$Root)
    $null = New-Item -ItemType Directory -Path (Join-Path $Root 'tools/nested') -Force
    $null = New-Item -ItemType Directory -Path (Join-Path $Root 'tools/__pycache__') -Force
    $null = New-Item -ItemType Directory -Path (Join-Path $Root '.git') -Force
    $null = New-Item -ItemType Directory -Path (Join-Path $Root '.github/workflows') -Force
    $null = New-Item -ItemType Directory -Path (Join-Path $Root 'skills/some-skill') -Force
    [System.IO.File]::WriteAllText((Join-Path $Root 'LICENSE'), "Apache License 2.0 (fixture)`n")
    [System.IO.File]::WriteAllText((Join-Path $Root 'NOTICE'), "Fixture notice`n")
    [System.IO.File]::WriteAllText((Join-Path $Root 'PACK-README.md'), "# the pack's front door (fixture)`n")
    [System.IO.File]::WriteAllText((Join-Path $Root 'README.md'), "# the REPOSITORY's own readme (fixture) -- must never reach the pack`n")
    [System.IO.File]::WriteAllText((Join-Path $Root 'tools/a.md'), "content`n")
    [System.IO.File]::WriteAllText((Join-Path $Root 'tools/nested/b.ps1'), "# content`n")
    [System.IO.File]::WriteAllText((Join-Path $Root 'tools/__pycache__/c.pyc'), "residue`n")
    [System.IO.File]::WriteAllText((Join-Path $Root '.git/HEAD'), "ref: refs/heads/main`n")
    [System.IO.File]::WriteAllText((Join-Path $Root '.github/workflows/ci.yml'), "name: ci`n")
    [System.IO.File]::WriteAllText((Join-Path $Root 'skills/some-skill/SKILL.md'), "internal`n")
}

function Invoke-BuildSelfTest {
    param([string]$ScanGate, [string]$GateDir)

    Write-Host "SELF-TEST -- negative controls" -ForegroundColor Cyan
    $failures = 0
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("share-pack-build-selftest-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $null = New-Item -ItemType Directory -Path $tmp -Force

    # A fixed exclusion pattern and a fixed commit for the fixtures: the controls below are about the
    # builder's guarantees, and the two things that vary with the host -- the parse and git -- get
    # their own controls at the end rather than being a hidden dependency of all the others. The
    # fixture hold list is fixed for the same reason: it holds a name that exists nowhere in the
    # fixture tree, so the general controls measure staging rather than the hold list, and the hold
    # list gets its own controls further down.
    $rx = '[\\/](__pycache__|node_modules|\.git)[\\/]'
    $sha = '0' * 40
    $holdFxName = 'hold-classes.fixture.json'
    $holdFx = @(
        @{ name = 'held fixture'; pattern = '(?i)(^|/)held\.md$'; example = 'nested/held.md'
            counter_example = 'nested/held.example.md'; reason = 'self-test fixture'
        }
    )

    try {
        # ── staging ───────────────────────────────────────────────────────────────
        # The one-file unrolling trap, carried over from the gate this staging came out of:
        # `return ,$list` and List[string] both exist to stop a one-element result unrolling into a
        # bare string on the way out. A one-file pack that reports zero files is a clean-looking run.
        $one = Join-Path $tmp 'one'; $null = New-Item -ItemType Directory -Path $one -Force
        [System.IO.File]::WriteAllText((Join-Path $one 'only.md'), "one file`n")
        $st = Copy-PackTree -PackRoot $one -StageRoot (Join-Path $tmp 'stage-one') -Prefix 'tools' -ExcludeRegex $rx
        if (-not (Assert-Case 'a one-file tree stages as one file, not as zero' '1' "$(@($st.RelPaths).Count)")) { $failures++ }

        $null = New-Item -ItemType Directory -Path (Join-Path $one '__pycache__') -Force
        [System.IO.File]::WriteAllText((Join-Path $one '__pycache__/x.pyc'), "junk`n")
        $st = Copy-PackTree -PackRoot $one -StageRoot (Join-Path $tmp 'stage-two') -Prefix 'tools' -ExcludeRegex $rx
        if (-not (Assert-Case 'an excluded path is not staged' '1' "$(@($st.RelPaths).Count)")) { $failures++ }
        if (-not (Assert-Case '...and the exclusion is COUNTED, not silent' '1' "$($st.Excluded)")) { $failures++ }
        if (-not (Assert-Case '...and it is really not on disk either' 'False' "$(Test-Path -LiteralPath (Join-Path $tmp 'stage-two/tools/__pycache__/x.pyc'))")) { $failures++ }

        # ── the hold list ─────────────────────────────────────────────────────────
        # The near-miss pair is the point of every one of these: held.md must not leave and
        # held.example.md is the thing the pack ships instead. One word apart, opposite verdicts --
        # which is precisely the shape of the two real classes (settings.json /
        # settings.template.json, redaction-classes.json / redaction-classes.example.json).
        $hold = Join-Path $tmp 'hold'; $null = New-Item -ItemType Directory -Path (Join-Path $hold 'nested') -Force
        [System.IO.File]::WriteAllText((Join-Path $hold 'nested/held.md'), "must not leave`n")
        [System.IO.File]::WriteAllText((Join-Path $hold 'nested/held.example.md'), "ships instead`n")
        [System.IO.File]::WriteAllText((Join-Path $hold 'ordinary.md'), "ships`n")
        $st = Copy-PackTree -PackRoot $hold -StageRoot (Join-Path $tmp 'stage-hold') -Prefix 'tools' -ExcludeRegex $rx -HoldClasses $holdFx
        if (-not (Assert-Case 'a hold-listed file is not staged' '2' "$(@($st.RelPaths).Count)")) { $failures++ }
        if (-not (Assert-Case '...and the hold is COUNTED, not silent' '1' "$(@($st.HeldPaths).Count)")) { $failures++ }
        if (-not (Assert-Case '...and named, so a decision is not just a number' 'nested/held.md' "$(@($st.HeldPaths) -join ',')")) { $failures++ }
        if (-not (Assert-Case '...and it is really not on disk' 'False' "$(Test-Path -LiteralPath (Join-Path $tmp 'stage-hold/tools/nested/held.md'))")) { $failures++ }
        # The counter-example half: a class too broad withholds a file the recipient needed, and
        # nothing about the resulting pack looks wrong.
        if (-not (Assert-Case '...and the near-miss the pack ships IS staged' 'True' "$(Test-Path -LiteralPath (Join-Path $tmp 'stage-hold/tools/nested/held.example.md'))")) { $failures++ }
        # Counted apart. Collapsing the two counters would make "withheld nothing" and "the pattern
        # stopped matching" the same output.
        if (-not (Assert-Case 'non-content and held-back are counted separately' '0' "$($st.Excluded)")) { $failures++ }

        # A class that has stopped matching its own example withholds nothing, and a pack built with
        # one looks exactly like a pack with nothing to withhold. The build must not run.
        $brokenHold = @(@{ name = 'broken'; pattern = '(?i)(^|/)nothing-matches-this$'; example = 'nested/held.md'; reason = 'self-test fixture' })
        $findings = @(Test-HoldClassTable -Classes $brokenHold -TableName $holdFxName)
        if (-not (Assert-Case 'a hold class that no longer matches its example is a finding' 'True' "$($findings.Count -gt 0)")) { $failures++ }
        $tooBroadHold = @(@{ name = 'too broad'; pattern = '(?i)held.*\.md$'; example = 'nested/held.md'; counter_example = 'nested/held.example.md'; reason = 'self-test fixture' })
        $findings = @(Test-HoldClassTable -Classes $tooBroadHold -TableName $holdFxName)
        if (-not (Assert-Case 'a hold class matching its counter-example is a finding' 'True' "$($findings.Count -gt 0)")) { $failures++ }
        $noReason = @(@{ name = 'unexplained'; pattern = '(?i)(^|/)held\.md$'; example = 'nested/held.md' })
        $findings = @(Test-HoldClassTable -Classes $noReason -TableName $holdFxName)
        if (-not (Assert-Case 'a hold class with no reason is a finding' 'True' "$($findings.Count -gt 0)")) { $failures++ }
        if (-not (Assert-Case 'the fixture table itself passes its own controls' '0' "$(@(Test-HoldClassTable -Classes $holdFx -TableName $holdFxName).Count)")) { $failures++ }

        # ...and a broken class stops the BUILD, in the Sources step, before a tree exists.
        $srcBH = Join-Path $tmp 'src-broken-hold'
        Write-Fixture -Root $srcBH
        $rBH = Invoke-PackBuild -PackRoot (Join-Path $srcBH 'tools') -SourceRoot $srcBH -OutDir (Join-Path $tmp 'out-broken-hold') -Prefix 'tools' `
            -ExcludeRegex $rx -HoldClasses $brokenHold -HoldClassTable $holdFxName -PackProfile 'public' `
            -SourceCommit $sha -SkipSteps @() -Force $false -DryRun $false
        if (-not (Assert-Case 'a broken hold class FAILS the build' '1' "$(Get-PackExit -Steps $rBH.Steps)")) { $failures++ }
        if (-not (Assert-Case '...in the Sources step, before anything is written' 'False' "$(Test-Path -LiteralPath (Join-Path $tmp 'out-broken-hold'))")) { $failures++ }
        $rEH = Invoke-PackBuild -PackRoot (Join-Path $srcBH 'tools') -SourceRoot $srcBH -OutDir (Join-Path $tmp 'out-empty-hold') -Prefix 'tools' `
            -ExcludeRegex $rx -HoldClasses @() -HoldClassTable $holdFxName -PackProfile 'public' `
            -SourceCommit $sha -SkipSteps @() -Force $false -DryRun $false
        if (-not (Assert-Case 'an EMPTY hold list FAILS the build rather than shipping everything' '1' "$(Get-PackExit -Steps $rEH.Steps)")) { $failures++ }

        # ── loading the hold list, fail-closed ────────────────────────────────────
        $ht = Join-Path $tmp 'hold-tables'; $null = New-Item -ItemType Directory -Path $ht -Force
        $threw = 'no'
        try { $null = Import-HoldClasses -GateDir $ht } catch { $threw = 'yes' }
        if (-not (Assert-Case 'neither hold table present refuses rather than permitting all' 'yes' $threw)) { $failures++ }
        [System.IO.File]::WriteAllText((Join-Path $ht 'hold-classes.example.json'), '{"classes":[{"name":"x","pattern":"(^|/)x$","example":"x","reason":"fixture"}]}')
        $loaded = Import-HoldClasses -GateDir $ht
        if (-not (Assert-Case 'with only the example table, the example table is used' 'example' "$($loaded.Source)")) { $failures++ }
        if (-not (Assert-Case '...and it is NAMED, so the fallback is not silent' 'hold-classes.example.json' "$($loaded.File)")) { $failures++ }
        [System.IO.File]::WriteAllText((Join-Path $ht 'hold-classes.json'), '{"classes":[{"name":"y","pattern":"(^|/)y$","example":"y","reason":"fixture"}]}')
        $loaded = Import-HoldClasses -GateDir $ht
        if (-not (Assert-Case 'with both present, the real table wins' 'real' "$($loaded.Source)")) { $failures++ }
        [System.IO.File]::WriteAllText((Join-Path $ht 'hold-classes.json'), '{"classes":[]}')
        $threw = 'no'
        try { $null = Import-HoldClasses -GateDir $ht } catch { $threw = 'yes' }
        if (-not (Assert-Case 'a hold table with zero classes refuses to load' 'yes' $threw)) { $failures++ }
        [System.IO.File]::WriteAllText((Join-Path $ht 'hold-classes.json'), '{ not json')
        $threw = 'no'
        try { $null = Import-HoldClasses -GateDir $ht } catch { $threw = 'yes' }
        if (-not (Assert-Case 'a hold table that does not parse refuses to load' 'yes' $threw)) { $failures++ }

        # THE LIVE TABLE, loaded rather than mocked -- a shape check that only ever sees fixtures is
        # checking the fixtures. This is also the control that keeps the recursion honest: the real
        # table must hold ITSELF back, or the one asset whose absence nobody would notice ships.
        if (Test-Path -LiteralPath $GateDir -PathType Container) {
            $live = Import-HoldClasses -GateDir $GateDir
            if (-not (Assert-Case 'the live hold table loads' 'True' "$($null -ne $live)")) { $failures++ }
            if (-not (Assert-Case '...and it is the real one, not the shipped starter' 'real' "$($live.Source)")) { $failures++ }
            if (-not (Assert-Case '...and every class passes its own controls' '0' "$(@(Test-HoldClassTable -Classes @($live.Classes) -TableName $live.File).Count)")) { $failures++ }
            $selfHeld = $false
            $exampleHeld = $false
            foreach ($c in @($live.Classes)) {
                if ([regex]::IsMatch('practice-gate/hold-classes.json', [string]$c.pattern)) { $selfHeld = $true }
                if ([regex]::IsMatch('practice-gate/hold-classes.example.json', [string]$c.pattern)) { $exampleHeld = $true }
            }
            if (-not (Assert-Case '...and the live hold table holds ITSELF back' 'True' "$selfHeld")) { $failures++ }
            if (-not (Assert-Case '...and does NOT hold back the starter table that ships' 'False' "$exampleHeld")) { $failures++ }
        }
        else {
            Write-Host "  [SKIP] no registry directory at $GateDir; the live hold-table controls did not run" -ForegroundColor Yellow
            $failures++   # controls that did not run are not controls that passed
        }

        # ── a whole build, and what the pack does NOT contain ─────────────────────
        $src = Join-Path $tmp 'src'
        Write-Fixture -Root $src
        $out1 = Join-Path $tmp 'out1'
        $r = Invoke-PackBuild -PackRoot (Join-Path $src 'tools') -SourceRoot $src -OutDir $out1 -Prefix 'tools' `
            -ExcludeRegex $rx -HoldClasses $holdFx -HoldClassTable $holdFxName -PackProfile 'public' -SourceCommit $sha -SkipSteps @() -Force $false -DryRun $false
        if (-not (Assert-Case 'a clean build exits 0' '0' "$(Get-PackExit -Steps $r.Steps)")) { $failures++ }

        $listed = @([string[]]$r.Manifest['files'])
        if (-not (Assert-Case 'LICENSE is in the pack, at its root' 'True' "$($listed -contains 'LICENSE')")) { $failures++ }
        if (-not (Assert-Case 'NOTICE is in the pack, at its root' 'True' "$($listed -contains 'NOTICE')")) { $failures++ }
        if (-not (Assert-Case '...and LICENSE was not filed inside the content tree' 'False' "$(Test-Path -LiteralPath (Join-Path $out1 'tools/LICENSE'))")) { $failures++ }

        # ── THE RENAME, measured on both sides ────────────────────────────────────
        # A root file whose source and destination names differ is the case the "never renamed"
        # comment used to forbid, so every half of it is asserted rather than described: the pack
        # holds the DESTINATION name, the manifest lists that name (the downstream gate enumerates
        # the pack root from the manifest, so an unlisted root file ships unscanned), the SOURCE name
        # appears nowhere at all, and the bytes are the pack's front door rather than the
        # repository's own README.md, which sits beside it at the fixture source root.
        if (-not (Assert-Case 'README.md is in the pack, under its DESTINATION name' 'True' "$($listed -contains 'README.md')")) { $failures++ }
        if (-not (Assert-Case '...and the manifest lists it, so the gate can scan it' 'True' "$($listed -contains 'README.md')")) { $failures++ }
        if (-not (Assert-Case '...and it really is on disk at the pack root' 'True' "$(Test-Path -LiteralPath (Join-Path $out1 'README.md'))")) { $failures++ }
        if (-not (Assert-Case '...and the SOURCE name is in no manifest entry' '0' "$(@($listed | Where-Object { $_ -match 'PACK-README' }).Count)")) { $failures++ }
        if (-not (Assert-Case '...and the SOURCE name is nowhere on disk either' '0' "$(@(Get-ChildItem -LiteralPath $out1 -Recurse -File | Where-Object { $_.Name -eq 'PACK-README.md' }).Count)")) { $failures++ }
        if (-not (Assert-Case '...and the README was not filed inside the content tree' 'False' "$(Test-Path -LiteralPath (Join-Path $out1 'tools/README.md'))")) { $failures++ }
        # The bytes, not just the name: a preflight or a copy written against the DESTINATION name
        # would find the repository's own README.md, copy that, and produce a pack whose front door
        # describes the wrong thing while every name-shaped control above stays green.
        if (-not (Assert-Case "...and it carries the PACK's readme, not the repository's" 'True' "$([System.IO.File]::ReadAllText((Join-Path $out1 'README.md')).Contains("the pack's front door"))")) { $failures++ }

        # STRUCTURAL, asserted rather than filtered: .git, .github and skills/ are outside the copy
        # root, so they cannot arrive. Measured against the built tree, so the day somebody moves
        # the copy root up one level this control is what says so.
        $forbidden = @($listed | Where-Object { $_ -match '(^|/)(\.git|\.github|skills)(/|$)' })
        if (-not (Assert-Case 'no .git / .github / skills path is in the pack' '0' "$($forbidden.Count)")) { $failures++ }
        if (-not (Assert-Case '...and none of them reached the disk' 'False' "$((Test-Path -LiteralPath (Join-Path $out1 'tools/.git')) -or (Test-Path -LiteralPath (Join-Path $out1 '.github')) -or (Test-Path -LiteralPath (Join-Path $out1 'skills')))")) { $failures++ }

        # THE COUNT. The manifest's number, its own list, and a fresh walk of the tree -- three
        # statements about one pack, and the manifest does not count itself.
        $onDisk = @(Get-ChildItem -LiteralPath $out1 -Recurse -File | Where-Object { $_.Name -ne $script:ManifestName })
        if (-not (Assert-Case 'the manifest count matches the staged count' "$($onDisk.Count)" "$($r.Manifest['file_count'])")) { $failures++ }
        if (-not (Assert-Case '...and matches the length of its own list' "$($listed.Count)" "$($r.Manifest['file_count'])")) { $failures++ }
        if (-not (Assert-Case 'the excluded count is reported on a real build' '1' "$($r.Manifest['excluded_non_content'])")) { $failures++ }

        # No absolute source path in a file that ships. On this class of machine that path carries a
        # user account name, which is the identifier class the content gate exists to keep out.
        $manifestText = [System.IO.File]::ReadAllText((Join-Path $out1 $script:ManifestName))
        if (-not (Assert-Case 'the manifest leaks no absolute source path' 'False' "$($manifestText.Contains($src))")) { $failures++ }

        # ── idempotence ───────────────────────────────────────────────────────────
        $r2 = Invoke-PackBuild -PackRoot (Join-Path $src 'tools') -SourceRoot $src -OutDir $out1 -Prefix 'tools' `
            -ExcludeRegex $rx -HoldClasses $holdFx -HoldClassTable $holdFxName -PackProfile 'public' -SourceCommit $sha -SkipSteps @() -Force $true -DryRun $false
        if (-not (Assert-Case 'a second -Force build exits 0' '0' "$(Get-PackExit -Steps $r2.Steps)")) { $failures++ }
        $l1 = (Get-SortedOrdinal -Values $listed) -join '|'
        $l2 = (Get-SortedOrdinal -Values ([string[]]$r2.Manifest['files'])) -join '|'
        if (-not (Assert-Case '...and produces the identical file list' 'True' "$($l1 -eq $l2)")) { $failures++ }

        # ── the output directory ──────────────────────────────────────────────────
        $r3 = Invoke-PackBuild -PackRoot (Join-Path $src 'tools') -SourceRoot $src -OutDir $out1 -Prefix 'tools' `
            -ExcludeRegex $rx -HoldClasses $holdFx -HoldClassTable $holdFxName -PackProfile 'public' -SourceCommit $sha -SkipSteps @() -Force $false -DryRun $false
        if (-not (Assert-Case 'a non-empty OutDir is REFUSED without -Force' '1' "$(Get-PackExit -Steps $r3.Steps)")) { $failures++ }
        $outDirStep = @($r3.Steps | Where-Object { $_.Name -eq 'OutDir' })
        if (-not (Assert-Case '...as a FAIL, not as a skip' 'FAIL' "$($outDirStep[0].Status)")) { $failures++ }

        $stranger = Join-Path $tmp 'stranger'
        $null = New-Item -ItemType Directory -Path $stranger -Force
        [System.IO.File]::WriteAllText((Join-Path $stranger 'someone-elses-work.txt'), "do not delete me`n")
        $r4 = Invoke-PackBuild -PackRoot (Join-Path $src 'tools') -SourceRoot $src -OutDir $stranger -Prefix 'tools' `
            -ExcludeRegex $rx -HoldClasses $holdFx -HoldClassTable $holdFxName -PackProfile 'public' -SourceCommit $sha -SkipSteps @() -Force $true -DryRun $false
        if (-not (Assert-Case 'an OutDir holding other files is refused even with -Force' '1' "$(Get-PackExit -Steps $r4.Steps)")) { $failures++ }
        if (-not (Assert-Case '...and the file it did not create is still there' 'True' "$(Test-Path -LiteralPath (Join-Path $stranger 'someone-elses-work.txt'))")) { $failures++ }

        # ── the root layer: every declared root file, absent, FAILS the build ─────
        $noLic = Join-Path $tmp 'no-licence'
        Write-Fixture -Root $noLic
        Remove-Item -LiteralPath (Join-Path $noLic 'LICENSE') -Force
        $out2 = Join-Path $tmp 'out2'
        $r5 = Invoke-PackBuild -PackRoot (Join-Path $noLic 'tools') -SourceRoot $noLic -OutDir $out2 -Prefix 'tools' `
            -ExcludeRegex $rx -HoldClasses $holdFx -HoldClassTable $holdFxName -PackProfile 'public' -SourceCommit $sha -SkipSteps @() -Force $false -DryRun $false
        if (-not (Assert-Case 'a source root with no LICENSE FAILS the build' '1' "$(Get-PackExit -Steps $r5.Steps)")) { $failures++ }
        if (-not (Assert-Case '...and writes no pack at all' 'False' "$(Test-Path -LiteralPath $out2)")) { $failures++ }

        $noNotice = Join-Path $tmp 'no-notice'
        Write-Fixture -Root $noNotice
        Remove-Item -LiteralPath (Join-Path $noNotice 'NOTICE') -Force
        $r6 = Invoke-PackBuild -PackRoot (Join-Path $noNotice 'tools') -SourceRoot $noNotice -OutDir (Join-Path $tmp 'out3') -Prefix 'tools' `
            -ExcludeRegex $rx -HoldClasses $holdFx -HoldClassTable $holdFxName -PackProfile 'public' -SourceCommit $sha -SkipSteps @() -Force $false -DryRun $false
        if (-not (Assert-Case 'a source root with no NOTICE FAILS the build' '1' "$(Get-PackExit -Steps $r6.Steps)")) { $failures++ }

        # THE MISSING README IS A FAILURE TOO, AND THE CONTROL SAYS SO IN ITS NAME -- decided, not
        # inherited. The two above fail for a legal reason that does not reach this file; this one
        # fails because a completeness proof that shipped a pack it knew was short of a declared file
        # would have to report the same green result for "we meant to drop it" and "the copy lost it".
        # The fixture keeps its own README.md, so what is measured is the absence of the SOURCE file
        # and not the absence of any readme.
        $noReadme = Join-Path $tmp 'no-readme'
        Write-Fixture -Root $noReadme
        Remove-Item -LiteralPath (Join-Path $noReadme 'PACK-README.md') -Force
        $r6b = Invoke-PackBuild -PackRoot (Join-Path $noReadme 'tools') -SourceRoot $noReadme -OutDir (Join-Path $tmp 'out3b') -Prefix 'tools' `
            -ExcludeRegex $rx -HoldClasses $holdFx -HoldClassTable $holdFxName -PackProfile 'public' -SourceCommit $sha -SkipSteps @() -Force $false -DryRun $false
        if (-not (Assert-Case 'a source root with no PACK-README.md FAILS the build' '1' "$(Get-PackExit -Steps $r6b.Steps)")) { $failures++ }
        if (-not (Assert-Case '...in Sources, and writes no pack at all' 'False' "$(Test-Path -LiteralPath (Join-Path $tmp 'out3b'))")) { $failures++ }
        # ...and it fails naming the SOURCE file, so the fix is not a hunt. A finding naming README.md
        # would send somebody to the repository's own README.md, which is present and is not the file.
        $srcStep = @($r6b.Steps | Where-Object { $_.Name -eq 'Sources' })
        if (-not (Assert-Case '...naming PACK-README.md, the file to restore' 'True' "$(@($srcStep[0].Findings | Where-Object { $_ -match 'PACK-README\.md' }).Count -gt 0)")) { $failures++ }

        # ── the read-back, in every direction it can catch ────────────────────────
        $mPath = Join-Path $out1 $script:ManifestName
        if (-not (Assert-Case 'a verified pack has no read-back findings' '0' "$(@(Test-PackTree -OutDir $out1 -ManifestPath $mPath -ManifestName $script:ManifestName).Count)")) { $failures++ }

        $tampered = [System.IO.File]::ReadAllText($mPath) | ConvertFrom-Json -AsHashtable
        $tampered.file_count = [int]$tampered.file_count + 1
        [System.IO.File]::WriteAllText((Join-Path $out1 'tampered.json'), ($tampered | ConvertTo-Json -Depth 6))
        $bad = @(Test-PackTree -OutDir $out1 -ManifestPath (Join-Path $out1 'tampered.json') -ManifestName 'tampered.json')
        if (-not (Assert-Case 'a manifest count that disagrees with its own list is caught' 'True' "$($bad.Count -gt 0)")) { $failures++ }
        Remove-Item -LiteralPath (Join-Path $out1 'tampered.json') -Force

        $victim = Join-Path $out1 'tools/a.md'
        if (Test-Path -LiteralPath $victim) { Remove-Item -LiteralPath $victim -Force }
        $bad = @(Test-PackTree -OutDir $out1 -ManifestPath $mPath -ManifestName $script:ManifestName)
        if (-not (Assert-Case 'a file the manifest lists and the tree lacks is caught' 'True' "$($bad.Count -gt 0)")) { $failures++ }
        [System.IO.File]::WriteAllText($victim, "content`n")

        [System.IO.File]::WriteAllText((Join-Path $out1 'tools/uninvited.md'), "nobody listed me`n")
        $bad = @(Test-PackTree -OutDir $out1 -ManifestPath $mPath -ManifestName $script:ManifestName)
        if (-not (Assert-Case 'a file in the tree the manifest omits is caught' 'True' "$($bad.Count -gt 0)")) { $failures++ }
        Remove-Item -LiteralPath (Join-Path $out1 'tools/uninvited.md') -Force

        $absent = @(Test-PackTree -OutDir $out1 -ManifestPath (Join-Path $out1 'no-such-manifest.json') -ManifestName 'no-such-manifest.json')
        if (-not (Assert-Case 'a missing manifest is a finding, not a clean verify' 'True' "$($absent.Count -gt 0)")) { $failures++ }

        [System.IO.File]::WriteAllText((Join-Path $out1 'broken.json'), "{ this is not json")
        $absent = @(Test-PackTree -OutDir $out1 -ManifestPath (Join-Path $out1 'broken.json') -ManifestName 'broken.json')
        if (-not (Assert-Case 'a manifest that does not parse is a finding' 'True' "$($absent.Count -gt 0)")) { $failures++ }
        Remove-Item -LiteralPath (Join-Path $out1 'broken.json') -Force

        # ── the exit contract itself ──────────────────────────────────────────────
        $out4 = Join-Path $tmp 'out4'
        $r7 = Invoke-PackBuild -PackRoot (Join-Path $src 'tools') -SourceRoot $src -OutDir $out4 -Prefix 'tools' `
            -ExcludeRegex $rx -HoldClasses $holdFx -HoldClassTable $holdFxName -PackProfile 'public' -SourceCommit $sha -SkipSteps @('Manifest') -Force $false -DryRun $false
        if (-not (Assert-Case 'a deliberately skipped step exits 2, never 0' '2' "$(Get-PackExit -Steps $r7.Steps)")) { $failures++ }
        $verifyStep = @($r7.Steps | Where-Object { $_.Name -eq 'Verify' })
        if (-not (Assert-Case '...and Verify is skipped by DEPENDENCY, not passed' 'SKIPPED' "$($verifyStep[0].Status)")) { $failures++ }

        $r8 = Invoke-PackBuild -PackRoot (Join-Path $noLic 'tools') -SourceRoot $noLic -OutDir (Join-Path $tmp 'out5') -Prefix 'tools' `
            -ExcludeRegex $rx -HoldClasses $holdFx -HoldClassTable $holdFxName -PackProfile 'public' -SourceCommit $sha -SkipSteps @('Verify') -Force $false -DryRun $false
        if (-not (Assert-Case 'a FAIL beats a skip: exit 1, not 2' '1' "$(Get-PackExit -Steps $r8.Steps)")) { $failures++ }

        $empty = Join-Path $tmp 'empty-content'
        $null = New-Item -ItemType Directory -Path (Join-Path $empty 'tools') -Force
        [System.IO.File]::WriteAllText((Join-Path $empty 'LICENSE'), "fixture`n")
        [System.IO.File]::WriteAllText((Join-Path $empty 'NOTICE'), "fixture`n")
        [System.IO.File]::WriteAllText((Join-Path $empty 'PACK-README.md'), "fixture`n")
        $r9 = Invoke-PackBuild -PackRoot (Join-Path $empty 'tools') -SourceRoot $empty -OutDir (Join-Path $tmp 'out6') -Prefix 'tools' `
            -ExcludeRegex $rx -HoldClasses $holdFx -HoldClassTable $holdFxName -PackProfile 'public' -SourceCommit $sha -SkipSteps @() -Force $false -DryRun $false
        $stageStep = @($r9.Steps | Where-Object { $_.Name -eq 'Stage' })
        # The root layer alone is not a pack. Its files are counted, so the step is not INCONCLUSIVE
        # -- what makes this a failure is that a pack of a licence, a notice and a readme is not a
        # distribution of anything, and it is the Verify/count chain that has to keep being able to
        # say so. The expected number is the root-file table's own length, derived rather than typed:
        # a fourth root file must not turn this control red for the wrong reason.
        if (-not (Assert-Case 'an empty content tree stages only the pack root layer' "$(@($script:RootFiles).Count)" "$($stageStep[0].Count)")) { $failures++ }

        # ── -DryRun writes NOTHING ────────────────────────────────────────────────
        $dry = Join-Path $tmp 'dry-out'
        $r10 = Invoke-PackBuild -PackRoot (Join-Path $src 'tools') -SourceRoot $src -OutDir $dry -Prefix 'tools' `
            -ExcludeRegex $rx -HoldClasses $holdFx -HoldClassTable $holdFxName -PackProfile 'public' -SourceCommit $sha -SkipSteps @() -Force $false -DryRun $true
        if (-not (Assert-Case '-DryRun creates no output directory' 'False' "$(Test-Path -LiteralPath $dry)")) { $failures++ }
        if (-not (Assert-Case '-DryRun is never a pass -- it exits 2' '2' "$(Get-PackExit -Steps $r10.Steps)")) { $failures++ }
        $dryStage = @($r10.Steps | Where-Object { $_.Name -eq 'Stage' })
        # The dry run and the real run must enumerate the SAME set. A preview produced by a second
        # code path is a preview of a different build.
        if (-not (Assert-Case '...and enumerates exactly what a real build stages' "$($listed.Count)" "$($dryStage[0].Count)")) { $failures++ }

        # ── provenance ────────────────────────────────────────────────────────────
        # No commit and no -SourceCommit: the fixture is a temp directory, not a repository.
        $r11 = Invoke-PackBuild -PackRoot (Join-Path $src 'tools') -SourceRoot $src -OutDir (Join-Path $tmp 'out7') -Prefix 'tools' `
            -ExcludeRegex $rx -HoldClasses $holdFx -HoldClassTable $holdFxName -PackProfile 'public' -SourceCommit '' -SkipSteps @() -Force $false -DryRun $false
        if (-not (Assert-Case 'no resolvable commit and no -SourceCommit FAILS' '1' "$(Get-PackExit -Steps $r11.Steps)")) { $failures++ }
        if (-not (Assert-Case '...and writes no pack' 'False' "$(Test-Path -LiteralPath (Join-Path $tmp 'out7'))")) { $failures++ }

        # A real repository, so the git path is exercised rather than assumed -- including the
        # ancestor trap, which is the one that would put a WRONG sha in a manifest instead of none.
        if (Get-Command git -ErrorAction SilentlyContinue) {
            $repo = Join-Path $tmp 'repo'
            $null = New-Item -ItemType Directory -Path (Join-Path $repo 'sub') -Force
            [System.IO.File]::WriteAllText((Join-Path $repo 'f.txt'), "x`n")
            $PSNativeCommandUseErrorActionPreference = $false
            $null = git -C $repo init --quiet 2>$null
            $null = git -C $repo -c user.email='selftest@example.invalid' -c user.name='selftest' add f.txt 2>$null
            $null = git -C $repo -c user.email='selftest@example.invalid' -c user.name='selftest' commit -q -m 'fixture' 2>$null
            $p = Get-PackProvenance -SourceRoot $repo -SourceCommit ''
            if (-not (Assert-Case 'a real repository resolves a 40-char commit' '40' "$($p.Commit.Length)")) { $failures++ }
            if (-not (Assert-Case '...and reports the working tree as clean' 'clean' "$($p.State)")) { $failures++ }
            [System.IO.File]::WriteAllText((Join-Path $repo 'f.txt'), "changed`n")
            $p = Get-PackProvenance -SourceRoot $repo -SourceCommit ''
            if (-not (Assert-Case 'a modified working tree is reported dirty, not clean' 'dirty' "$($p.State)")) { $failures++ }
            # THE ANCESTOR TRAP: rev-parse walks up, so a subdirectory answers with the enclosing
            # repository's HEAD. That sha does not describe the subdirectory, and a recipient would
            # act on it. Refused.
            $p = Get-PackProvenance -SourceRoot (Join-Path $repo 'sub') -SourceCommit ''
            if (-not (Assert-Case 'a commit from an ENCLOSING repository is refused' 'unresolved' "$($p.State)")) { $failures++ }
        }
        else {
            Write-Host "  [SKIP] git is not on PATH; the provenance controls did not run" -ForegroundColor Yellow
            $failures++   # controls that did not run are not controls that passed
        }

        $p = Get-PackProvenance -SourceRoot $tmp -SourceCommit 'deadbeef'
        if (-not (Assert-Case 'an asserted commit is recorded as asserted' 'asserted' "$($p.State)")) { $failures++ }

        # ── reading the exclusion pattern out of the content gate ─────────────────
        if (Test-Path -LiteralPath $ScanGate) {
            $live = Get-PackExcludeRegex -ScanGate $ScanGate
            if (-not (Assert-Case 'the live exclusion pattern parses out of the content gate' 'True' "$(-not [string]::IsNullOrWhiteSpace($live))")) { $failures++ }
            # The parsed pattern has to actually forbid something. A pattern that matches nothing
            # excludes nothing and looks exactly like a tree with no residue in it.
            if (-not (Assert-Case '...and it still matches compiled residue' 'True' "$('tools/x/__pycache__/y.pyc' -match $live)")) { $failures++ }
            if (-not (Assert-Case '...and does not match ordinary content' 'False' "$('tools/x/y.py' -match $live)")) { $failures++ }
        }
        else {
            Write-Host "  [SKIP] the content gate is not beside this script; the parse controls did not run" -ForegroundColor Yellow
            $failures++
        }

        $threw = 'no'
        try { $null = Get-PackExcludeRegex -ScanGate (Join-Path $tmp 'no-such-gate.ps1') } catch { $threw = 'yes' }
        if (-not (Assert-Case 'a missing content gate refuses rather than defaulting' 'yes' $threw)) { $failures++ }

        $stub = Join-Path $tmp 'stub-gate.ps1'
        [System.IO.File]::WriteAllText($stub, "# a gate with no exclusion line`nWrite-Host 'hi'`n")
        $threw = 'no'
        try { $null = Get-PackExcludeRegex -ScanGate $stub } catch { $threw = 'yes' }
        if (-not (Assert-Case 'a gate whose exclusion line has moved refuses' 'yes' $threw)) { $failures++ }
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
# Resolved BEFORE anything is written, and failing to 1 rather than 0. A builder that cannot locate
# its inputs must not report success, and must not leave half a directory behind while finding out.

if (-not $PackRoot) { $PackRoot = $PSScriptRoot }
if (-not (Test-Path -LiteralPath $PackRoot)) {
    Write-Host "ENVIRONMENT: -PackRoot '$PackRoot' does not exist." -ForegroundColor Red
    exit 1
}
$PackRoot = (Resolve-Path -LiteralPath $PackRoot).Path

if (-not $SourceRoot) { $SourceRoot = Split-Path -Parent $PackRoot }
if (-not (Test-Path -LiteralPath $SourceRoot)) {
    Write-Host "ENVIRONMENT: -SourceRoot '$SourceRoot' does not exist. LICENSE, NOTICE and the source commit live there." -ForegroundColor Red
    exit 1
}
$SourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path

# NOT `if (-not $Prefix)`. An unbound [string] parameter is the EMPTY STRING, not $null, and '' is a
# legitimate value here meaning "stage the content at the pack root" -- so the two cases can only be
# told apart by whether the caller passed it. The sibling gate had exactly this bug, and its symptom
# was 40-odd registry entries covering for a default that never applied.
if (-not $PSBoundParameters.ContainsKey('Prefix')) { $Prefix = Split-Path -Leaf $PackRoot }

if (-not $ScanGate) { $ScanGate = Join-Path $PSScriptRoot 'Test-PracticeClaims.ps1' }
if (-not $GateDir) { $GateDir = Join-Path $PSScriptRoot 'practice-gate' }

if ($SelfTest) { exit (Invoke-BuildSelfTest -ScanGate $ScanGate -GateDir $GateDir) }

if (-not $PSBoundParameters.ContainsKey('ExcludeRegex')) {
    try { $ExcludeRegex = Get-PackExcludeRegex -ScanGate $ScanGate }
    catch {
        Write-Host "ENVIRONMENT: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Resolved here rather than inside the build, so that a missing or malformed table is an ENVIRONMENT
# failure with no directory created -- the same treatment the exclusion pattern gets, for the same
# reason: neither is a thing to discover halfway through writing a pack.
$holdTable = $null
try { $holdTable = Import-HoldClasses -GateDir $GateDir }
catch {
    Write-Host "ENVIRONMENT: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if (-not $OutDir) {
    # No default destination, on purpose. Every candidate default is wrong in a way that is hard to
    # notice: a path inside the repository puts an unversioned tree where `git status` will start
    # arguing about it, and a temp path produces a pack somebody has to be told the location of.
    # -DryRun is the exception because it has no destination to get wrong.
    if (-not $DryRun) {
        Write-Host "ENVIRONMENT: -OutDir is required for a real build. Pass a new directory, or one holding only a previous pack (add -Force to rebuild it)." -ForegroundColor Red
        Write-Host "             Use -DryRun to see what would be staged without naming a destination." -ForegroundColor Red
        exit 1
    }
    $OutDir = Join-Path ([System.IO.Path]::GetTempPath()) 'share-pack-dry-run-never-written'
}

$build = Invoke-PackBuild -PackRoot $PackRoot -SourceRoot $SourceRoot -OutDir $OutDir -Prefix $Prefix `
    -ExcludeRegex $ExcludeRegex -HoldClasses @($holdTable.Classes) -HoldClassTable $holdTable.File `
    -PackProfile $PackProfile -SourceCommit $SourceCommit `
    -SkipSteps $Skip -Force ([bool]$Force) -DryRun ([bool]$DryRun)

# ── REPORT ──────────────────────────────────────────────────────────────────────
# ASCII only, for the reason the gates state: windows-latest turned a non-ASCII bullet into a
# replacement character and made the log unreadable. The output boundary is part of the tool.

Write-Host ""
Write-Host "SHARE PACK BUILD -- profile '$PackProfile'"
Write-Host ("content root {0} -> {1}" -f $PackRoot, $(if ($DryRun) { '<nothing written -- dry run>' } else { $OutDir }))
Write-Host ("=" * 78)

foreach ($s in $build.Steps) {
    $colour = switch ($s.Status) {
        'PASS' { 'Green' } 'FAIL' { 'Red' } 'INCONCLUSIVE' { 'Red' } 'SKIPPED' { 'Yellow' } default { 'Gray' }
    }
    Write-Host ("{0,-10} {1,-13} {2,5} file(s){3}" -f $s.Name, $s.Status, $s.Count, $(if ($s.Note) { "  -- $($s.Note)" } else { '' })) -ForegroundColor $colour
    foreach ($f in $s.Findings) { Write-Host "             - $f" -ForegroundColor $colour }
}

if ($null -ne $build.Manifest) {
    Write-Host ("-" * 78)
    Write-Host ("pack: {0} file(s) [{1} at the pack root, {2} under {3}], {4} excluded as non-content" -f `
            $build.Manifest['file_count'], $script:RootFiles.Count, (@($build.Stage.RelPaths).Count),
        $(if ($Prefix) { "$Prefix/" } else { '<pack root>' }), $build.Manifest['excluded_non_content'])
    # Named, not just counted. A withheld asset is a DECISION, and a decision reported as a number
    # is a decision nobody revisits -- the same argument the gates make for printing their
    # registered exemptions on a green run.
    Write-Host ("held: {0} file(s) withheld by {1}{2}" -f $build.Manifest['held_back'], $build.Manifest['hold_class_table'],
        $(if ([int]$build.Manifest['held_back'] -gt 0) { ' -- ' + (@($build.Manifest['held_back_paths']) -join ', ') } else { '' }))
    Write-Host ("from: commit {0} ({1}) at {2}" -f $build.Manifest['source_commit'], $build.Manifest['source_state'], $build.Manifest['built_utc'])
}

$exit = Get-PackExit -Steps $build.Steps

Write-Host ("=" * 78)
if ($exit -eq 1) {
    Write-Host "RESULT: FAIL -- the pack was NOT built. Nothing here may be shipped." -ForegroundColor Red
}
elseif ($exit -eq 2) {
    if ($DryRun) {
        Write-Host "RESULT: DRY RUN -- nothing was written. This is not a build." -ForegroundColor Yellow
    }
    else {
        Write-Host "RESULT: SKIPPED -- the pack was built with step(s) deliberately not run." -ForegroundColor Yellow
        Write-Host "        This is not a pass. Re-run without -Skip before shipping anything." -ForegroundColor Yellow
    }
}
else {
    Write-Host "RESULT: PASS -- pack built and verified against its manifest" -ForegroundColor Green
    Write-Host "        Now run Test-SharePackClean.ps1 before it leaves: this step proves the pack is" -ForegroundColor Green
    Write-Host "        COMPLETE, not that its contents are clean." -ForegroundColor Green
}
Write-Host ""

exit $exit
