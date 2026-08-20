<#
.SYNOPSIS
    Share-pack gate -- is the tree that is about to leave this repository clean enough to leave?

.DESCRIPTION
    PLAN-external-share-pack.md section 3 enumerates the string classes that must not reach an
    external recipient, and says the enforcement should be "mechanical, so it can be a script
    rather than a careful read". This is that script, and its first design constraint is that it
    must NOT be a second copy of the list.

        tools/Test-PracticeClaims.ps1 already holds the identifier classes and the 0/1/2 exit
        contract. Re-implementing them here would give the pack two redaction lists that drift
        apart -- the failure section 3 warns about, committed by the gate written to prevent it.

    So this is a CALLER. It has the pack BUILT -- by Build-SharePack.ps1, which owns staging and is
    the single source of truth for what the pack is -- runs that gate over the built tree, and then
    adds only the checks a content scanner over tools/** structurally cannot make:

      1. PracticeGate    Run the staged copy of Test-PracticeClaims.ps1 against the staged bundle
                         and hold its output to account: the report must be parseable, every check
                         it names must appear in it, and its exit code must agree with its own
                         table. Nothing here re-implements a check; it verifies that the checks
                         RAN. A caller that trusts an exit code alone is one pipe away from
                         reporting success it never measured.

                         "RAN" INCLUDES "RAN WITH REAL PATTERNS", and that clause was bought
                         expensively. The delegated gate's redaction table is hold-listed out of the
                         pack, so a run pointed at the staged registries falls back to the shipped
                         placeholder table -- example-corp, acme_warehouse, names that appear in
                         nobody's tree -- and reports the same green Redaction line. The downgrade
                         was visible only as prose in a note inside a delegated report, and nothing
                         parses prose, so this wrapper printed "RESULT: PASS -- every check ran and
                         passed" over a pack whose identifiers had never been looked for. The note
                         now carries `table=<filename>` as a field, and this check FAILS if a pack
                         was certified by the example table. See TWO RUNS, TWO QUESTIONS below.

      2. BundleBoundary  A bundle is not the repository, and some findings are structural rather
                         than defects: a document citing a path that only exists outside tools/ is
                         a real citation in the repository and a dangling one in the pack. Those
                         are registered, with reasons, in practice-gate/share-pack.json -- and
                         checked in BOTH directions, so the day an assembly step rewrites one of
                         those citations the entry fails as stale rather than covering nothing
                         forever. Anything not registered is a FAIL.

      3. Coverage        The redaction check is EXTENSION-SCOPED. Every file whose extension is
                         not in its list is unexamined, silently, and "no findings" reads exactly
                         the same as "not looked at". So every staged file is either inside that
                         scan or registered here with the reason it cannot be -- and the count of
                         files this check expects the gate to have examined is compared against
                         the count the gate REPORTS examining. Two independent enumerations of one
                         scope; a disagreement means one of them is wrong and neither may pass.

      4. HoldList        Section 2f names assets that must never ship at all. That is a question
                         about PATHS, not contents: the redaction classes would not fire on an
                         accumulated permission corpus or on a park/reap script, both of which are
                         perfectly free of organisation identifiers and neither of which may leave.
                         The classes live in practice-gate/hold-classes.json, NOT in this file, for
                         the reason the redaction classes left the gate next door: a captioned list
                         of what an organisation withholds is a map of what it has, and two of these
                         classes name the organisation and its internal distribution route in the
                         pattern itself, because a path-shaped class has nowhere else to put a name.
                         So the table is held back by a class in itself, hold-classes.example.json
                         ships in its place, and a run that loaded the starter table says so.
                         The BUILDER reads the same table and withholds a matching file instead of
                         staging it, so this check has two jobs: nothing held is in the tree, AND
                         the builder's decisions and this table agree in both directions.

      5. RootFiles       THE PACK ROOT IS A SUBJECT, and until 2026-08-19 it was not one. The builder
                         places its root-layer files BESIDE the content tree -- enumerated from the
                         manifest rather than listed here, so the layer can grow without this
                         paragraph going quietly stale -- and every
                         other check in this file is scoped to the content tree: the delegated gate is
                         pointed at it, and the file list this gate derives is the manifest's entries
                         under the content prefix WITH THE PREFIX STRIPPED, so a root file drops out
                         of the enumeration by not carrying it. Both licence files are also
                         extensionless, so they fall outside the redaction scan's extension list for a
                         second, independent reason. Two ways to be invisible, and neither of them
                         printed anything.
                         WHAT THAT COST, measured: LICENSE and NOTICE carried four
                         organisation-identifying lines through every green run for the whole life of
                         this branch, and they were found by a hand grep. "No findings" read exactly
                         like "not looked at" -- the failure this repository is built to refuse --
                         on the one part of the pack a recipient opens first.
                         So the root files are enumerated FROM THE MANIFEST (never from a list written
                         here, so a future root file is covered the day the builder starts placing it),
                         cross-checked against a walk of the pack root in BOTH directions, and scanned
                         with the REAL redaction classes loaded by the resolver the delegated gate
                         uses -- one vocabulary, one home. Occurrences that are legally required are
                         registrable in practice-gate/share-pack.json with a reason, and that list is
                         EMPTY today because the files name no entity: Apache-2.0 requires the notices
                         to travel, not to name anybody, and 4(c)/4(d) are satisfied by a NOTICE that
                         carries the licence and the product. It exists anyway, because putting a
                         copyright holder back is a legitimate legal decision and it must land as a
                         registered entry rather than as a silent pass -- and, like every registry
                         here, it fails as stale when an entry covers nothing.

      6. Secrets         Section 3 class 7, belt and braces. Every OTHER class in this file is
                         delegated; this one is not, and the reason is a property of the reporter
                         rather than of the patterns: the redaction check QUOTES what it matched,
                         which is right for an organisation identifier -- the finding is useless
                         without it -- and catastrophic for a credential, which must be reported
                         as a class and a location and never as a value. A finding that quotes a
                         secret has manufactured the exposure it was hired to detect.

    TWO RUNS, TWO QUESTIONS, and collapsing them is what put a placeholder-pattern PASS one edit
    away. The delegated gate is invoked TWICE against the same staged tree, differing only in which
    registry directory it is pointed at, because "is this content clean?" and "does the gate work
    from a distribution?" are different questions with different right answers:

      * the CONTENT run is pointed at the REPOSITORY's practice-gate, which holds the real
        identifier table. It is the run every downstream check parses, and it is the only run
        entitled to say the pack is clean. Pointing it at the staged copy -- which is what this file
        did until 2026-08-19 -- asks the real question and answers it with fictional patterns.
      * the DISTRIBUTION run is pointed at the STAGED practice-gate and scoped to the redaction
        check. It is not asked whether the tree is clean; it is asked whether a recipient who has
        only what the pack ships can stand the gate up at all -- the tables load, the classes parse,
        every example still matches, the scan walks, the report prints. Its verdict on identifiers
        is worth nothing and is not read as one. What IS read is which table it loaded: it must be
        the EXAMPLE table, because if the real one is reachable from inside the pack then the pack
        ships the reconnaissance map, and that is a second, independent proof of the hold list
        working -- one that does not depend on the same hold list being right.

    THE ONE PROPERTY THIS FILE IS BUILT ON. Every pattern it applies -- every hold class, every
    secret class -- carries a worked EXAMPLE, and each example is matched against its own pattern on
    every run, not only in the self-test. A forbidding pattern that has stopped matching forbids
    nothing, reports nothing, and looks exactly like a clean tree. Several classes also carry a
    counter-example asserted NOT to match, because the ones that matter here are near-misses:
    settings.json must never ship and settings.template.json is the thing the pack ships instead;
    redaction-classes.json must never ship and redaction-classes.example.json is what ships in its
    place. One word apart, opposite verdicts, in both pairs. The root-file check adds the third pair,
    and it is the one that was actually got wrong: a de-branded NOTICE must PASS, and the same NOTICE
    carrying an organisation identifier must FAIL. Both halves are asserted on every run against an
    in-memory fixture, per class, so the assertion holds whatever the table says and nothing matchable
    is written down here.

    THE PRICE OF THAT PROPERTY, and how it is paid. An example has to match its class, so it is
    credential-shaped by construction -- and a credential-shaped literal in a committed file is
    exactly what a secret scanner is right to reject. This file's first push was blocked by GitHub
    push protection over the vendor-token example, correctly, because nothing about the shape
    distinguishes it from a live token. The two ways out were to whitelist the "secret", teaching
    every reader that the override is the way past that control, or to stop writing the literal.
    So every example here is ASSEMBLED from fragments at load time: the run-time positive control is
    unchanged, because the assembled string still matches and a broken class still fails, and there
    is no matchable literal on disk for a scanner, for this gate, or for a reader to mistake for the
    real thing. It also means this file needs no exemption from its own check, which is the better
    outcome -- an exemption is a thing somebody has to keep true.

    WHAT THIS GATE CANNOT SEE, stated rather than discovered by a recipient:
      * The auto-memory store. Its files are ordinary markdown with ordinary names; nothing in a
        path or an extension distinguishes a memory from a document. What catches it is the
        redaction check on its contents, which is a weaker guarantee than the rest of this file
        offers, and the reason section 2f says ship the toolkit and none of the store.
      * A secret this file has no pattern for. The class list is short and specific on purpose --
        an entropy heuristic over prose produces findings nobody reads -- so -Gitleaks exists for
        the belt-and-braces run, and when it is not asked for the report says so on its face.
      * Anything outside the staged tree. Which is the point: the subject is the pack, not the
        repository. A file left out of the pack is invisible here, and that is the assembly step's
        problem (build order 3), not this one's.
      * A SPACED ORGANISATION NAME. The root-file check applies the delegated gate's classes verbatim
        -- that is the point of it, one vocabulary with one home -- so it sees exactly what that table
        sees and no more. Measured 2026-08-19 against the four lines this branch removed from LICENSE
        and NOTICE: two are caught (a product name and a tenant URL) and two are not, because both are
        the organisation's name written out with spaces and the class matches the closed-up form. The
        remedy is one alternative in the `organisation` class in redaction-classes.json, not a second
        pattern list here; this file deliberately holds none, and adding one would recreate the drift
        the header opens by refusing. Recorded rather than left to be rediscovered by the next hand
        grep, since the point of a measured hole is that somebody can close it.
      * WHAT THE ROOT FILES USED TO BE, and it is worth keeping the old argument visible because it
        was wrong in an instructive way: this block used to say LICENSE and NOTICE were a deliberate
        exemption, because "a NOTICE file has to name the copyright holder". It does not. Apache-2.0
        4(c)/4(d) require the notices that ARE in the work to travel with a redistribution; they
        require nobody to be named, and 4(d) applies only if a NOTICE file exists at all. So the
        exemption was resting on a legal necessity that was not one, and it kept four identifier
        lines in the pack for the life of the branch. The files were de-branded and the exemption
        became a check.

    PRINT-ONLY. No -Fix, for the same reason the gate it calls has none.

.PARAMETER PackRoot
    The directory that becomes the pack. Default: the directory this script lives in -- tools/,
    which IS the pack root today: the build-in-place decision means permissions/ is
    tools/claude-permission-toolkit/, session/ is tools/claude-session-toolkit/, and so on. Point
    it at the assembled tree once build order 3 has lifted one.

.PARAMETER CitationPrefix
    Path under the staged root at which the pack is placed, because a citation resolves relative
    to the root, not to the pack. Default: the leaf name of PackRoot -- tools/, matching the
    repo-relative form the documents actually use (`tools/claude-dev-practice/README.md`). Pass ''
    for an assembled pack whose documents cite pack-relative paths.

.PARAMETER PracticeGate
    The gate to call. Default: Test-PracticeClaims.ps1 beside this script. The STAGED copy is the
    one that runs -- a distribution's own gate proving it works from a distribution.

.PARAMETER Builder
    The build step this gate calls to produce its subject. Default: Build-SharePack.ps1 beside this
    script. It owns staging; there is deliberately no second stager here, because two stagers drift
    and the gate would then certify a tree nothing ships. A builder that exits non-zero, or writes a
    manifest this gate cannot read, is a FAILURE: a gate that could not stage has no subject.

.PARAMETER RegistryPath
    practice-gate/share-pack.json: the bundle boundary, the unscanned-file exemptions, the
    secret-fixture list and the legally-required root-file occurrences. Every entry requires a
    reason, and every entry is checked for staleness.

.PARAMETER GateDir
    THE REPOSITORY's practice-gate directory -- the one holding the real pattern tables. Default:
    practice-gate beside this script. THREE things read it, and every one of them would be answering
    a fictional question without it: this file's hold list, the CONTENT run of the delegated gate,
    and the root-file scan, which loads the delegated gate's own redaction classes rather than
    keeping a second copy of them. The STAGED copy of that directory is used for the DISTRIBUTION
    run only; see TWO RUNS, TWO QUESTIONS above for why the two must not be collapsed.

.PARAMETER Skip
    Checks to deliberately not run. A skipped check exits 2 and is named in the report; it is
    never counted as a pass. Skipping PracticeGate also skips BundleBoundary, which has nothing to
    read without it -- reported as skipped-by-dependency rather than passing on an empty set.

.PARAMETER Gitleaks
    Also run gitleaks over the staged pack. Requested and unresolvable is a FAILURE, not a skip:
    asking for the belt and being told nothing is the state this contract exists to forbid. The
    run is guarded by a positive control -- a planted fixture the scanner must flag -- because a
    scanner that cannot see a repository prints "no leaks found" and exits 0 in about 14 ms.

.PARAMETER GitleaksPath
    Explicit path to the executable. Default: gitleaks on PATH.

.PARAMETER StageDir
    Where to stage. Default: a new temp directory, removed on exit.

.PARAMETER KeepStage
    Leave the staged tree in place and print its path. For debugging a finding by hand.

.PARAMETER ReportPath
    Optional file to write the full report to, with WriteAllText -- Set-Content honours -WhatIf
    and would silently skip the write.

.PARAMETER SelfTest
    Run the negative controls in a temp directory and exit. Writes nothing inside the repository.

.EXAMPLE
    pwsh -NoProfile -File tools/Test-SharePackClean.ps1

.EXAMPLE
    pwsh -NoProfile -File tools/Test-SharePackClean.ps1 -SelfTest

.EXAMPLE
    pwsh -NoProfile -File tools/Test-SharePackClean.ps1 -Gitleaks

.NOTES
    EXIT CONTRACT -- the same one the called gate uses, deliberately, so a caller cannot invent a
    softer vocabulary for the same outcomes:
      0  every check ran and passed
      1  a check FAILED, or ran and found ZERO candidates (INCONCLUSIVE), or the environment could
         not be resolved
      2  a check was deliberately not run (-Skip) and nothing else failed -- SKIPPED, never a pass

    The outcome vocabulary is a SECOND COPY of the called gate's, which is a fork unless something
    compares them. What compares them is the report parser: it accepts only PASS, FAIL,
    INCONCLUSIVE and SKIPPED, and reports INCONCLUSIVE if the gate ever prints a status it does not
    know. A vocabulary change there surfaces here as an unreadable report, not as a quiet pass.

    ps1-safety: $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest. READ-ONLY against
    the repository. Writes only into a temp staging directory it creates and removes, plus the
    optional -ReportPath. No network unless -Gitleaks resolves a binary that makes one; no secrets
    echoed anywhere -- findings carry a class and a location, never a matched value. Idempotent.
    Tolerates CRLF, since CI checks out on windows-latest.
#>
[CmdletBinding()]
param(
    [string]$PackRoot,
    [string]$CitationPrefix,
    [string]$PracticeGate,
    [string]$Builder,
    [string]$RegistryPath,
    [string]$GateDir,
    # THE SAME LIST AS $script:PackChecks, and the self-test compares the two by parsing this line
    # out of this file -- the move Get-DelegateScope makes against the gate next door, applied to
    # this one. A check in the dispatch list and not in this set cannot be skipped; a check in this
    # set and not dispatched means -Skip would report a check that never runs.
    [ValidateSet('PracticeGate', 'BundleBoundary', 'Coverage', 'HoldList', 'RootFiles', 'Secrets')]
    [string[]]$Skip = @(),
    [switch]$Gitleaks,
    [string]$GitleaksPath,
    [string]$StageDir,
    [switch]$KeepStage,
    [string]$ReportPath,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ── OUTCOME VOCABULARY ──────────────────────────────────────────────────────────
# PASS / FAIL / INCONCLUSIVE / SKIPPED, with INCONCLUSIVE meaning the check ran and measured
# nothing. See the .NOTES block for why a second copy of this vocabulary is acceptable and what
# holds it to the original.

class PackCheck {
    [string]$Name
    [string]$Status
    [int]$Candidates
    [System.Collections.Generic.List[string]]$Findings
    [string]$Note

    PackCheck([string]$name) {
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

    # INCONCLUSIVE must not overwrite a recorded FAIL: a check that found a defect has measured
    # something by definition, and relabelling it would both hide the finding and misdescribe it.
    [void] Seal() {
        if ($this.Candidates -eq 0 -and $this.Status -eq 'PASS') {
            $this.Status = 'INCONCLUSIVE'
            $this.Note = 'examined zero candidates -- the scope is empty or the enumerator is broken'
        }
    }
}

# ── THE PATTERN TABLES ──────────────────────────────────────────────────────────
# ONE OF THE TWO IS NOW A DATA FILE, and the split between them is the whole argument.
#
# The HOLD LIST moved to practice-gate/hold-classes.json on 2026-08-19. It used to sit here, and the
# comment defending that said a reader of the gate should see exactly what it forbids -- the same
# sentence the redaction classes used to be defended with, and it inverts on publication for the same
# reason. Two of those classes are a directory naming the internal distribution route and a filename
# prefix carrying the organisation; a class about a PATH has nowhere to put a name except the pattern
# and the worked example, so those two strings could not be written any other way. They shipped, in
# this file, in the pack advertised as externally shareable, and the redaction check could not see
# them because this script is on its self-exemption list. Moving them out is what let the pack's own
# hold list withhold them -- including, recursively, the table itself.
#
# The SECRET CLASSES stayed. They are not identifiers and they are not organisation-specific: every
# one is a public vendor credential SHAPE, and every example is assembled from fragments at load time
# so that nothing matchable sits on disk. There is nothing in them to withhold, and a data file would
# buy this gate a second fallback path and a second load failure for no gain.

# Section 2f, as paths -- loaded, never restated. The real table is preferred, the shipped generic
# starter is the fallback, and neither present is a THROW: a hold list that failed to load permits
# everything while looking exactly like a pack with nothing to withhold. Same resolution order, same
# two names, same shape as Import-RedactionClasses in the gate this one calls, deliberately -- there
# is one shape to learn here and one loader shape to review.
function Import-HoldClasses {
    param([string]$GateDir)

    $real = Join-Path $GateDir 'hold-classes.json'
    $example = Join-Path $GateDir 'hold-classes.example.json'

    if (Test-Path -LiteralPath $real -PathType Leaf) { $path = $real; $source = 'real' }
    elseif (Test-Path -LiteralPath $example -PathType Leaf) { $path = $example; $source = 'example' }
    else {
        throw "no hold class table in $GateDir -- neither hold-classes.json nor hold-classes.example.json is there, so this check has no paths to forbid and would report PASS while permitting every one of them"
    }

    $name = [System.IO.Path]::GetFileName($path)
    $table = $null
    try { $table = [System.IO.File]::ReadAllText($path) | ConvertFrom-Json -AsHashtable }
    catch { throw "$name does not parse as JSON ($($_.Exception.Message)) -- a hold list that failed to load forbids nothing" }
    if (-not $table.ContainsKey('classes')) {
        throw "$name has no 'classes' key -- shape-check failed, refusing to pass by checking nothing"
    }
    $classes = @($table.classes)
    if ($classes.Count -eq 0) {
        throw "$name has an empty 'classes' list -- that would pass by forbidding nothing"
    }
    return @{ Classes = $classes; Source = $source; File = $name }
}

# ── THE ROOT-FILE SCAN'S VOCABULARY, WHICH IS NOT THIS FILE'S ───────────────────
# The identifier classes live in ONE place -- practice-gate/redaction-classes.json, read by the
# delegated gate's Test-Redaction -- and the root-file check loads that same table rather than
# carrying organisation patterns of its own. The header opens by refusing to be a second copy of that
# list; a check added to this file is not exempt from the sentence the file starts with.
#
# THE TWO FILENAMES ARE NOT WRITTEN HERE EITHER. They arrive in $Scope, parsed out of the delegated
# gate's own resolution order by Get-DelegateScope -- the same pair the table-identity assertion is
# built on. Rename either table over there and this stops with an error naming the parse, instead of
# looking for a file nothing writes any more and reporting a root file scanned by nothing.
#
# NEITHER-PRESENT IS A THROW, and present-but-the-starter is a FAIL at the call site. The starter
# table forbids example-corp and acme_warehouse; a NOTICE certified by it has not been examined, for
# exactly the reason the content run may not be certified by it.
function Import-RootScanClasses {
    param([string]$GateDir, [hashtable]$Scope)

    if ([string]::IsNullOrWhiteSpace($Scope.RealTable) -or [string]::IsNullOrWhiteSpace($Scope.ExampleTable)) {
        throw "the delegated gate's redaction table filenames did not parse, so the root files have no class table to be scanned with -- see the PracticeGate findings; nothing here may certify a root file against patterns it could not load"
    }
    $real = Join-Path $GateDir $Scope.RealTable
    $example = Join-Path $GateDir $Scope.ExampleTable

    if (Test-Path -LiteralPath $real -PathType Leaf) { $path = $real; $source = 'real' }
    elseif (Test-Path -LiteralPath $example -PathType Leaf) { $path = $example; $source = 'example' }
    else {
        throw "no redaction class table in $GateDir -- neither $($Scope.RealTable) nor $($Scope.ExampleTable) is there, so the pack root has no patterns to be read against and this check would report PASS while forbidding nothing"
    }

    $name = [System.IO.Path]::GetFileName($path)
    $table = $null
    try { $table = [System.IO.File]::ReadAllText($path) | ConvertFrom-Json -AsHashtable }
    catch { throw "$name does not parse as JSON ($($_.Exception.Message)) -- a class table that failed to load forbids nothing and reports exactly what a clean pack root reports" }
    if (-not $table.ContainsKey('classes')) {
        throw "$name has no 'classes' key -- shape-check failed, refusing to pass by checking nothing"
    }
    $classes = @($table.classes)
    if ($classes.Count -eq 0) {
        throw "$name has an empty 'classes' list -- that would pass by forbidding nothing"
    }
    return @{ Classes = $classes; Source = $source; File = $name }
}

# THE DISPATCH LIST, DECLARED ONCE. It used to be an array literal in the foreach header, with the
# -Skip ValidateSet as a second literal thirty lines up saying the same thing -- the arrangement this
# file objects to in the gate it calls, where two lists that must agree are compared rather than
# trusted. Named here so the loop and the report walk one list, and the self-test parses the
# ValidateSet back out of this file and asserts the two match.
$script:PackChecks = @('PracticeGate', 'BundleBoundary', 'Coverage', 'HoldList', 'RootFiles', 'Secrets')

# Section 3 class 7. Ordered most-specific-first so a vendor token is reported as one rather than
# as a generic assignment. Findings carry the class and the location; the matched text is NEVER
# emitted, which is the whole reason this check is not delegated to a reporter that quotes.
#
# Deliberately short. An entropy heuristic over prose produces findings nobody reads, and a gate
# nobody reads is worse than no gate -- so the classes here are the ones with a shape, and
# -Gitleaks is how you ask for more than a shape.
#
# EVERY EXAMPLE IS ASSEMBLED, NEVER WRITTEN OUT WHOLE, and that is not fastidiousness. An example
# has to MATCH its class, so it is credential-shaped by construction -- and a credential-shaped
# literal sitting in a committed file is precisely what a scanner is right to reject. This file's
# first push was blocked by GitHub push protection over the vendor-token example, correctly: nothing
# about the shape distinguishes it from a live token, which is the whole reason the class exists.
# The available answers were to whitelist the "secret" (teaching everyone that the override is the
# way past this control) or to stop writing the literal. Concatenation keeps the run-time positive
# control completely real -- the assembled string still matches, so a broken class still fails -- and
# leaves nothing on disk for a scanner, this gate, or a reader to mistake for the real thing.
$script:SecretClasses = @(
    [pscustomobject]@{
        Class   = 'private key block'
        Pattern = '-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----'
        Example = ('-' * 5) + 'BEGIN OPENSSH PRIVATE KEY' + ('-' * 5)
    },
    [pscustomobject]@{
        Class   = 'vendor personal access token'
        Pattern = '\bdapi[0-9a-f]{32}\b'
        Example = 'da' + 'pi' + ('0' * 32)
    },
    [pscustomobject]@{
        Class   = 'code-forge token'
        Pattern = '\bgh[pousr]_[A-Za-z0-9]{36,}\b'
        Example = 'gh' + 'p_' + ('0' * 36)
    },
    [pscustomobject]@{
        Class   = 'cloud access key id'
        Pattern = '\bAKIA[0-9A-Z]{16}\b'
        Example = 'AK' + 'IA' + ('Z' * 16)
    },
    [pscustomobject]@{
        Class   = 'chat platform token'
        Pattern = '\bxox[baprs]-[A-Za-z0-9-]{12,}\b'
        Example = 'xo' + 'xb-0000-0000-' + ('a' * 12)
    },
    [pscustomobject]@{
        Class   = 'signed web token'
        Pattern = '\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}'
        Example = 'ey' + 'J0eXAiOiJKV1QifQ' + '.' + 'ey' + 'JhIjoxfQxx' + '.' + ('s' * 20)
    },
    [pscustomobject]@{
        Class   = 'credential in a connection url'
        Pattern = '(?i)\b[a-z][a-z0-9+.-]{2,}://[^\s/:@"'']{2,}:[^\s/@"'']{4,}@'
        Example = 'bolt://user:' + 'hunter2000' + '@example.invalid:7687'
    },
    [pscustomobject]@{
        Class   = 'bearer literal'
        Pattern = '(?i)\b(bearer|authorization:\s*bearer)\s+[A-Za-z0-9._~+/=-]{20,}'
        Example = 'Authorization: Bearer ' + ('a' * 30)
    },
    [pscustomobject]@{
        Class   = 'assigned credential'
        # The high-false-positive class, so it is the narrowest: a credential-shaped NAME, an
        # assignment, and a value that is not obviously a placeholder or an indirection. Prose is
        # excluded by requiring the assignment operator, and the interesting near-misses -- an
        # environment lookup, a template placeholder, an empty string -- are stripped below rather
        # than encoded here, because a lookahead after a greedy class is how the secret guard came
        # to block its own remediation advice.
        Pattern = '(?i)\b(password|passwd|pwd|secret|api[_-]?key|access[_-]?token|client[_-]?secret|connection[_-]?string)\b\s*[:=]\s*(?<v>[^\s"'',;)\]}]{8,})'
        Example = 'client_' + 'secret=' + 'Zk9mQ2xhc3NpZmllZDEyMzQ1'
    }
)

# The shapes PLANTED by the self-test's positive controls and by the gitleaks probe. Assembled for
# the same reason the examples above are, and held in one place so that a scanner-provoking string
# is constructed exactly once in this file rather than copied to each site that needs one.
#
# THEY HAVE TO BE HIGH-ENTROPY FAKES, and finding that out cost a red CI run worth having. The first
# version planted repeated characters -- a key prefix followed by sixteen Z's, a token prefix
# followed by thirty-six zeros -- which satisfies every pattern in the table above and is SILENTLY
# IGNORED by gitleaks, whose rules apply entropy and stopword filters. So the positive control, whose
# entire job is to prove the scanner can see, was itself a false pass: it would have reported "the
# scanner cannot read its target" on every clean run, and had it been written the other way round it
# would have reported a working scanner while proving nothing.
#
# Measured 2026-08-17 against the pinned gitleaks 8.28.0, on Windows, by installing it and asking:
# repeated-character fakes -> 0 findings; the random fakes below -> aws-access-token and
# slack-bot-token, exit 7. The same session reproduced the documented false pass, because it is the
# reason this probe exists: `detect --source <dir>` WITHOUT --no-git in a non-repository logs
# "fatal: not a git repository", then "no leaks found", and exits 0 having scanned 0 bytes.
$script:PlantedShapes = @(
    ('AK' + 'IA' + 'QYRT4XN2WLBZ6VJH'),
    ('xo' + 'xb-' + '4829105736-2947183650-' + 'Jd7Kq2Vn9Xs4Rt1Bw6Ym3Lp8')
)

# Values that satisfy the assignment shape and are NOT credentials. Two groups, and the second one
# is the one that matters:
#
#   a placeholder -- a template token, a row of asterisks, an empty string. Harmless noise.
#
#   an INDIRECTION -- `os.environ.get("X")`, `$env:X`, a vault lookup, a dotted config read. This is
#   the CORRECT way to reach a credential, and flagging it would make this check fault the practice
#   it exists to encourage. That is not a hypothetical: the secret guard next door told users in its
#   own block message to emit `.Length` instead of a value and then blocked that too, which teaches
#   exactly one lesson -- reach for the override.
#
# Applied AFTER the match, deliberately. As a lookahead behind a greedy character class it would
# behave the way the guard's did: the engine gives back a character and matches anyway.
$script:NonLiteralValue = '(?i)(^(<|\$|%|\{|@|\.\.\.|\*{3,}|x{4,}|0{8,}|redacted|changeme|your[-_ ]|placeholder|example|none|null|true|false|["'']{2})|^\d+$|[(\[]|^[A-Za-z_][A-Za-z0-9_]*[.:]|\b(env|environ|getenv|vault|keyring|credential_process)\b)'

# ── HELPERS ─────────────────────────────────────────────────────────────────────

function Read-PackLines {
    param([string]$Path)
    # -Raw then split, so CRLF and a missing trailing newline normalise on every runner.
    #
    # CALLER CONTRACT, copied from the called gate along with the trap it documents: ASSIGN this to
    # a variable before iterating. The `return ,$array` wrapper stops a one-line file unrolling
    # into a bare string, and it also means `foreach ($x in Read-PackLines ...)` iterates the
    # WRAPPER exactly once. Both forms run clean; only one reads the file.
    $raw = [System.IO.File]::ReadAllText($Path)
    return , ($raw -split "\r?\n")
}

function Import-PackRegistry {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "share-pack registry not found at $Path -- a gate whose registry is missing must not pass"
    }
    $json = [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json -AsHashtable
    foreach ($k in @('bundle_boundary', 'unscanned', 'secret_fixtures', 'root_file_allowed')) {
        if (-not $json.ContainsKey($k)) {
            throw "share-pack registry has no '$k' key -- shape-check failed, refusing to pass by checking nothing"
        }
    }
    foreach ($k in @('checks', 'citations')) {
        if (-not $json.bundle_boundary.ContainsKey($k)) {
            throw "share-pack registry bundle_boundary has no '$k' key -- shape-check failed"
        }
    }
    return $json
}

function Get-PackRelPath {
    param([string]$FullName, [string]$Root)
    return $FullName.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/'
}

# ── THE CALLED GATE'S SCOPE, BY PARSING IT ──────────────────────────────────────
# Read out of the gate, never restated here. This is the move the local-CI runner makes against a
# workflow file, and it fails in the loud direction on purpose: change the gate's shape and this
# returns an error that makes a check INCONCLUSIVE, rather than silently comparing against a stale
# copy of a list. The resolution is always to update the parse, never to hardcode the list.

function Get-DelegateScope {
    param([string]$Path)

    $scope = @{
        Extensions       = @()
        ExcludeRegex     = ''
        SelfNames        = @()
        CheckNames       = @()
        ValidateSetNames = @()
        RealTable        = ''
        ExampleTable     = ''
        Errors           = [System.Collections.Generic.List[string]]::new()
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        $scope.Errors.Add("the gate is not at $Path")
        return $scope
    }
    $raw = [System.IO.File]::ReadAllText($Path)

    # The redaction check's own extension list, taken from inside its function body rather than
    # from the first one in the file -- four checks call the same helper with different lists, and
    # the .md-only ones are not the scope this compares against.
    $fnAt = $raw.IndexOf('function Test-Redaction')
    if ($fnAt -lt 0) {
        $scope.Errors.Add('no "function Test-Redaction" in the gate -- the check this compares against has been renamed or removed')
    }
    else {
        $rest = $raw.Substring($fnAt)
        $nextFn = $rest.IndexOf("`nfunction ", 1)
        $body = if ($nextFn -gt 0) { $rest.Substring(0, $nextFn) } else { $rest }

        $m = [regex]::Match($body, '-Extensions\s+@\(([^)]*)\)')
        if (-not $m.Success) {
            $scope.Errors.Add('cannot find the redaction check''s -Extensions list -- its scan scope is unknown, so nothing here may claim the pack was covered')
        }
        else {
            $scope.Extensions = @([regex]::Matches($m.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() })
            if ($scope.Extensions.Count -eq 0) {
                $scope.Errors.Add('the redaction check''s -Extensions list parsed as empty')
            }
        }

        # The self-exemption. One or many, quoted, on one line: this file is the second name in it.
        $m = [regex]::Match($body, '(?m)^\s*\$selfNames?\s*=\s*(?<rhs>.+)$')
        if (-not $m.Success) {
            $scope.Errors.Add('cannot find the redaction check''s self-exemption ($selfName/$selfNames) -- the file count this compares cannot be derived')
        }
        else {
            $scope.SelfNames = @([regex]::Matches($m.Groups['rhs'].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
            if ($scope.SelfNames.Count -eq 0) {
                $scope.Errors.Add('the redaction check''s self-exemption parsed as empty')
            }
        }
    }

    # THE TWO NAMES OF THE REDACTION TABLE, read out of the gate's own resolution order rather than
    # written down here. This is what lets the table-identity assertion say "the run loaded the
    # EXAMPLE table" without this file holding an opinion about which filename that is: rename either
    # one over there and this parse fails, which makes the assertion INCONCLUSIVE instead of silently
    # comparing against a name nothing uses any more. Hardcoding them would have been shorter and
    # would have produced, on that rename, a wrapper that could no longer recognise the placeholder
    # table and therefore stopped objecting to it -- failure in the quiet direction, on the one check
    # written to stop exactly that.
    $m = [regex]::Match($raw, '(?m)^\s*\$real\s*=\s*Join-Path\s+\$GateDir\s+''(?<f>[^'']+)''')
    if (-not $m.Success) {
        $scope.Errors.Add('cannot find the redaction table''s primary filename ($real = Join-Path $GateDir ...) -- which table a delegated run loaded cannot be judged, so nothing here may certify a pack as scanned')
    }
    else { $scope.RealTable = $m.Groups['f'].Value }
    $m = [regex]::Match($raw, '(?m)^\s*\$example\s*=\s*Join-Path\s+\$GateDir\s+''(?<f>[^'']+)''')
    if (-not $m.Success) {
        $scope.Errors.Add('cannot find the redaction table''s fallback filename ($example = Join-Path $GateDir ...) -- the placeholder table cannot be recognised, and an unrecognised placeholder run reads exactly like a real one')
    }
    else { $scope.ExampleTable = $m.Groups['f'].Value }

    # The directory exclusions, from the shared file enumerator.
    $m = [regex]::Match($raw, '\$_\.FullName\s+-notmatch\s+''(?<rx>[^'']+)''')
    if (-not $m.Success) {
        $scope.Errors.Add('cannot find the gate''s directory-exclusion pattern -- staging cannot mirror what it skips')
    }
    else { $scope.ExcludeRegex = $m.Groups['rx'].Value }

    # The dispatch list, and the ValidateSet that is supposed to say the same thing. Two lists in
    # one file that must agree; comparing them costs nothing and catches a check that was added to
    # one and not the other.
    # The list moved out of the `foreach` header and into a named variable when -Only was added:
    # the loop now walks a SELECTION, and the selection is not the full set the report is asserted
    # against. Read the canonical list where it is now declared, or completeness is measured
    # against whatever a scoped run happened to select.
    $m = [regex]::Match($raw, '(?m)^\s*\$allChecks\s*=\s*@\((?<names>[^)]*)\)')
    if (-not $m.Success) {
        $scope.Errors.Add('cannot find the gate''s check dispatch list ($allChecks) -- completeness of its report cannot be asserted')
    }
    else {
        $scope.CheckNames = @([regex]::Matches($m.Groups['names'].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
    }
    # There are now TWO ValidateSets saying the same thing -- one for -Skip, one for -Only -- so
    # the "two lists that must agree" problem this block exists for became a three-list problem
    # the moment the second was added. Every occurrence is read and they must be identical;
    # checking only the first would let -Only drift into accepting a check nothing dispatches.
    $sets = @([regex]::Matches($raw, "(?s)\[ValidateSet\((?<names>[^)]*)\)\]") | ForEach-Object {
            , @([regex]::Matches($_.Groups['names'].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
        })
    if ($sets.Count -gt 0) {
        $scope.ValidateSetNames = $sets[0]
        for ($s = 1; $s -lt $sets.Count; $s++) {
            if (($sets[$s] -join '|') -ne ($sets[0] -join '|')) {
                $scope.Errors.Add("the gate's ValidateSet #$($s + 1) does not match its first -- -Skip and -Only must accept the same checks, or one of them names a check the other cannot")
            }
        }
    }

    return $scope
}

# ── STAGING, WHICH THIS FILE NO LONGER DOES ─────────────────────────────────────
# The gate runs against a STAGED COPY, not against tools/ in place, and that is the difference
# between checking the repository and checking the pack. HANDOFF.md has carried the instruction
# "simulate a distribution whenever tools/ changes: copy tools/ to a temp dir with no .git, .github
# or skills/, and run with -RepoRoot at that root" as a procedure somebody remembers. A procedure
# somebody remembers is not a guarantee, so it is done on every run -- but it is no longer done HERE.
#
# THIS FILE HAD ITS OWN STAGER (New-PackStage) UNTIL 2026-08-19, and the problem with that was not
# the code, which was thirty correct lines. It was that a gate for "the share pack" built its subject
# in a temp directory and threw it away in its own finally, so the artifact certified had never left
# %TEMP% and the artifact shipped was whatever somebody copied by hand. Build-SharePack.ps1 now owns
# staging and is the single source of truth for what the pack IS; two stagers would drift, which is
# precisely the failure this file's header names about duplicated redaction lists. So the stager is
# gone and this is a caller: every gate run is now an end-to-end exercise of the real build step, and
# the manifest -- the thing a recipient actually reads -- is on the path rather than beside it.
#
# WHERE THE OLD CONTROLS WENT. The two staging controls this file's self-test used to assert -- a
# one-file tree stages as one file rather than unrolling to zero, and the exclusion pattern is
# mirrored AND counted rather than silently dropping files -- are now Build-SharePack.ps1's, in
# Invoke-BuildSelfTest under "-- staging --". They were not deleted; they moved to the file that owns
# the behaviour, which is the only place they can still fail for the right reason.

function Get-BuilderManifestName {
    # Read out of the builder, never restated. The same move this file makes for the content gate's
    # extension list and its exclusion pattern, for the same reason: rename the manifest over there
    # and this stops with an error naming the parse, rather than looking for a file that is no longer
    # called that and reporting a build that produced nothing.
    param([string]$Builder)

    if (-not (Test-Path -LiteralPath $Builder -PathType Leaf)) {
        throw "the build step is not at $Builder -- pass -Builder if it lives elsewhere in this distribution"
    }
    $raw = [System.IO.File]::ReadAllText($Builder)
    $m = [regex]::Match($raw, '(?m)^\s*\$script:ManifestName\s*=\s*''(?<n>[^'']+)''')
    if (-not $m.Success) {
        throw "cannot find the builder's manifest name (`$script:ManifestName = '...') in $Builder -- its shape changed, and this gate must not guess the name of the file it derives its whole scope from"
    }
    return $m.Groups['n'].Value
}

function Invoke-PackBuilder {
    # Invoke, not dot-source. Dot-sourcing a script with a param block and a main body needs an
    # "am I being dot-sourced" guard -- a control that has to keep being true and does nothing
    # observable when it stops -- and it would exercise a FUNCTION while the artifact a recipient
    # runs is a SCRIPT. Invoking means the thing under test is the thing that ships.
    param(
        [string]$Builder,
        [string]$PackRoot,
        [string]$StageRoot,
        [string]$Prefix,
        [string]$ExcludeRegex,
        [string]$ManifestName
    )

    if (-not (Test-Path -LiteralPath $Builder -PathType Leaf)) {
        throw "the build step is not at $Builder -- this gate has no way to produce its subject, and a gate with no subject must not report PASS. Pass -Builder if it lives elsewhere in this distribution."
    }

    # The same host that is running this script, resolved from the process rather than from PATH, for
    # the reason Invoke-DelegateGate gives: a `pwsh` lookup answers what is installed, not what is
    # executing.
    $hostExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $buildArgs = @(
        '-NoProfile', '-File', $Builder,
        '-PackRoot', $PackRoot,
        '-OutDir', $StageRoot,
        '-Prefix', $Prefix,
        # Passed rather than left to the builder's own parse, because this gate has ALREADY parsed it
        # out of the content gate and the two must be the same string. The builder would reach the
        # same answer by the same parse; handing it over means a divergence is impossible rather than
        # unlikely.
        '-ExcludeRegex', $ExcludeRegex,
        '-Force'
    )

    # NO PIPE, and the exit code is read immediately. `& exe | tail` returns tail's status.
    $stdout = & $hostExe @buildArgs 2>&1
    $code = $LASTEXITCODE
    $text = ($stdout | Out-String)

    if ($code -ne 0) {
        throw ("the build step exited $code, so there is no pack to check. A gate that could not stage must not pass.`n" +
            "--- builder output ---`n$text")
    }

    $manifestPath = Join-Path $StageRoot $ManifestName
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw ("the build step exited 0 and wrote no manifest at $manifestPath -- reported success and produced nothing this gate can read.`n" +
            "--- builder output ---`n$text")
    }
    $manifest = $null
    try { $manifest = [System.IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json -AsHashtable }
    catch { throw "the pack manifest at $manifestPath does not parse as JSON ($($_.Exception.Message)) -- the subject of this gate cannot describe itself" }

    # SHAPE-CHECKED BEFORE IT IS TRUSTED, and every key here is one this gate reads. A missing key
    # would otherwise surface as $null flowing into a count and a check that measured nothing while
    # reporting PASS.
    foreach ($k in @('files', 'excluded_non_content', 'held_back', 'held_back_paths', 'hold_class_table', 'pack_prefix')) {
        if (-not $manifest.ContainsKey($k)) {
            throw "the pack manifest has no '$k' key -- shape-check failed, and this gate will not derive its scope from a manifest it does not understand"
        }
    }
    if ([string]$manifest.pack_prefix -ne $Prefix) {
        throw "the pack manifest declares pack_prefix '$($manifest.pack_prefix)' and this gate asked for '$Prefix' -- the tree it built is not the tree this gate is about to describe"
    }

    $packDir = if ([string]::IsNullOrEmpty($Prefix)) { $StageRoot } else { Join-Path $StageRoot $Prefix }
    if (-not (Test-Path -LiteralPath $packDir -PathType Container)) {
        throw "the build step reported success and there is no content directory at $packDir -- nothing here may be scanned"
    }

    # THE GRAIN, and it is the one thing about this function worth being pedantic over. The manifest
    # lists the WHOLE pack at pack-root-relative grain: LICENSE and NOTICE at the root beside the
    # content tree. Every downstream check in this file -- Coverage, HoldList, Secrets -- is written
    # against PackDir-relative paths, and the delegated gate is pointed at PackDir too, so its
    # candidate count is at that grain as well. So the prefix is STRIPPED here and the root files
    # drop out by not carrying it. Skipping this step would inflate the file count by two, break the
    # two-enumerations comparison in Coverage by exactly that, and make every Secrets path resolve
    # one directory too deep.
    #
    # THE ROOT FILES ARE NOW KEPT RATHER THAN DROPPED, and that is the whole of the 2026-08-19 fix.
    # "The prefix is stripped and the root files drop out by not carrying it" was correct about the
    # grain and silent about the consequence: the entries that failed the StartsWith test went
    # nowhere, so LICENSE and NOTICE were not in any list any check in this file read. They are now
    # collected into their own list at pack-ROOT-relative grain -- a SECOND grain in one return value,
    # which is the price of the pack having two layers, and every consumer of either list is named in
    # the field comment below so the two cannot be confused. Derived from the manifest, so a third
    # root file the builder starts placing lands in this list without an edit here.
    $relPaths = [System.Collections.Generic.List[string]]::new()
    $heldPaths = [System.Collections.Generic.List[string]]::new()
    $rootPaths = [System.Collections.Generic.List[string]]::new()
    if ([string]::IsNullOrEmpty($Prefix)) {
        # No prefix means no root LAYER: the content tree IS the pack root, every entry is content,
        # and the only file beside the content is the manifest -- which is never in `files`, because
        # it cannot list itself. So rootPaths stays empty here on purpose rather than by omission,
        # and the root-file check adds the manifest to whatever this returns.
        foreach ($f in @($manifest.files)) { $relPaths.Add([string]$f) }
        foreach ($f in @($manifest.held_back_paths)) { $heldPaths.Add([string]$f) }
    }
    else {
        $head = "$Prefix/"
        foreach ($f in @($manifest.files)) {
            $s = [string]$f
            if ($s.StartsWith($head, [System.StringComparison]::Ordinal)) { $relPaths.Add($s.Substring($head.Length)) }
            else { $rootPaths.Add($s) }
        }
        foreach ($f in @($manifest.held_back_paths)) {
            $s = [string]$f
            if ($s.StartsWith($head, [System.StringComparison]::Ordinal)) { $heldPaths.Add($s.Substring($head.Length)) }
        }
    }
    if ($relPaths.Count -eq 0) {
        throw "the pack manifest lists no file under '$Prefix/' -- either the build staged an empty content tree or this gate is reading the wrong grain; both are failures, and neither may be scanned to a PASS"
    }

    # Root, PackDir, Prefix, RelPaths and Excluded are the shape New-PackStage returned and every
    # downstream check still consumes unchanged. HeldPaths / HeldBack / HoldTable are additions the
    # old stager had nothing to say about: the builder now WITHHOLDS files rather than staging
    # everything, and a decision the gate cannot see is a decision it cannot cross-check.
    return @{
        Root       = [System.IO.Path]::GetFullPath($StageRoot)
        PackDir    = (Resolve-Path -LiteralPath $packDir).Path
        Prefix     = $Prefix
        # CONTENT-TREE-RELATIVE. Read by Coverage, HoldList and Secrets, and it is the grain the
        # delegated gate reports its own candidate count at.
        RelPaths   = $relPaths
        Excluded   = [int]$manifest.excluded_non_content
        HeldPaths  = $heldPaths
        HeldBack   = [int]$manifest.held_back
        HoldTable  = [string]$manifest.hold_class_table
        # PACK-ROOT-RELATIVE, and read by RootFiles ALONE. Deliberately disjoint from RelPaths: a
        # path appears in exactly one of the two lists, so the two checks cannot double-count and
        # Coverage's partition still reconciles over the content tree it is an argument about.
        RootPaths    = $rootPaths
        ManifestName = $ManifestName
        Stdout     = $text
    }
}

# ── RUNNING THE CALLED GATE ─────────────────────────────────────────────────────

function Invoke-DelegateGate {
    param([string]$Delegate, [hashtable]$Stage, [string]$GateDir, [string]$Only = '')

    $report = Join-Path ([System.IO.Path]::GetTempPath()) ("share-pack-delegate-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".txt")

    # The same host that is running this script, resolved from the process rather than from PATH:
    # a `pwsh` lookup answers a different question (what is installed) than the one that matters
    # (what is executing), and the gate must run under the interpreter this file was launched with.
    $hostExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName

    # NOT $args: that is an automatic variable inside a function, and shadowing it works right up
    # until somebody reads the line and has to stop and think about which one they are looking at.
    # -GateDir IS THE CALLER'S DECISION, and it is the difference between two questions. See TWO
    # RUNS, TWO QUESTIONS in the header: the CONTENT run passes the repository's registry directory,
    # because "is this content free of real organisation identifiers?" can only be answered by the
    # real table -- which is hold-listed out of the pack precisely so it cannot be reached from
    # inside one. The DISTRIBUTION run passes the staged copy, because "can a recipient stand this
    # gate up from what we shipped?" can only be answered by the shipped registries. Until
    # 2026-08-19 this line hardcoded the staged copy and the two questions were one: the wrapper
    # asked the first and got an answer to neither, because the real table was not there and the
    # fallback answered in placeholder vocabulary. The parameter exists so that a caller must say
    # which question it is asking.
    $gateArgs = @(
        '-NoProfile', '-File', $Delegate,
        '-DocRoot', $Stage.PackDir,
        '-RepoRoot', $Stage.Root,
        '-GateDir', $GateDir,
        '-ReportPath', $report
    )
    # One value, not a list. -Only takes an array over there, but a native command boundary turns
    # 'a,b' into one string that its ValidateSet then refuses -- so this passes at most one check
    # name, which is all the distribution run needs, rather than a joined string that would fail in
    # a way that reads like the gate being broken.
    if (-not [string]::IsNullOrWhiteSpace($Only)) { $gateArgs += @('-Only', $Only) }

    # NO PIPE. `& exe | tail` returns tail's status, and reporting success from that has happened
    # on this work already. Stdout is assigned, the exit code is read immediately afterwards, and
    # the verdict is taken from the REPORT FILE rather than from either.
    $stdout = & $hostExe @gateArgs 2>&1
    $code = $LASTEXITCODE

    $text = if (Test-Path -LiteralPath $report) { [System.IO.File]::ReadAllText($report) } else { '' }
    # The report has been read into memory, so the file has no further job. Left behind, this dropped
    # one delegate report into %TEMP% per run -- harmless individually, and the reason the staging
    # directory two functions up is cleaned in a finally rather than trusted to tidy itself. The path
    # stays on the returned object for diagnostics; it names where the report WAS.
    Remove-Item -LiteralPath $report -Force -ErrorAction SilentlyContinue
    return @{
        ExitCode   = $code
        ReportPath = $report
        ReportText = $text
        Stdout     = ($stdout | Out-String)
        Rows       = (ConvertFrom-DelegateReport -Text $text)
    }
}

function ConvertFrom-DelegateReport {
    param([string]$Text)

    $rows = [System.Collections.Generic.List[object]]::new()
    if ([string]::IsNullOrWhiteSpace($Text)) { return $rows }

    $known = @('PASS', 'FAIL', 'INCONCLUSIVE', 'SKIPPED')
    # Plain assignment. The `,($array)` wrapper is a RETURN-value guard -- it stops a one-element
    # result unrolling on the way out of a function -- and wrapping then immediately indexing back
    # out of it here was ceremony that looked like a safety measure. The guard lives where it does
    # something, on Read-PackLines.
    $lines = $Text -replace "`r`n", "`n" -split "`n"
    $current = $null
    foreach ($line in $lines) {
        # A table row: name, status, candidate count, optional note. The status token set is the
        # boundary that holds this file's copy of the vocabulary to the original -- an unrecognised
        # status is reported rather than skipped, and see Test-DelegateRun for what happens then.
        $m = [regex]::Match($line, '^(?<name>[A-Za-z][A-Za-z0-9_-]*)\s+(?<status>[A-Z]+)\s+(?<n>\d+) candidate\(s\)(\s+--\s+(?<note>.*))?$')
        if ($m.Success) {
            $current = [pscustomobject]@{
                Name       = $m.Groups['name'].Value
                Status     = $m.Groups['status'].Value
                Candidates = [int]$m.Groups['n'].Value
                Note       = $m.Groups['note'].Value
                Known      = ($known -contains $m.Groups['status'].Value)
                Findings   = [System.Collections.Generic.List[string]]::new()
            }
            $rows.Add($current)
            continue
        }
        $m = [regex]::Match($line, '^\s+- (?<finding>.+)$')
        if ($m.Success -and $null -ne $current) { $current.Findings.Add($m.Groups['finding'].Value.Trim()) }
    }
    return $rows
}

# ── CHECK 1 -- THE CALLED GATE ACTUALLY RAN ─────────────────────────────────────
# Mechanics only. Whether its findings are acceptable is check 2's question; this one asks whether
# there is a result here worth reading at all.

function Get-DelegateRedactionTable {
    # WHICH PATTERN TABLE THE DELEGATED RUN ACTUALLY LOADED, parsed out of the Redaction row's note.
    # The note opens with `table=<filename>` in both of its branches -- real and fallback -- and that
    # field is a contract stated in the gate at the site that writes it.
    #
    # THE ALTERNATIVE WAS TO READ THE PROSE, and the prose is what failed. Before this field existed
    # the fallback was announced as "PATTERNS FROM redaction-classes.example.json -- the generic
    # starter table..." and the real case as "5 class(es) from redaction-classes.json...": two
    # different sentence shapes, no common field, and nothing but a human between them and a green
    # RESULT line. Returns '' when there is no Redaction row or no field to read, and every caller
    # treats '' as "unusable", never as "probably fine".
    param([hashtable]$Run)

    $rows = @($Run.Rows | Where-Object { $_.Name -eq 'Redaction' })
    if ($rows.Count -eq 0) { return '' }
    $m = [regex]::Match([string]$rows[0].Note, '(?<![A-Za-z0-9_])table=(?<f>[^\s;,]+)')
    if (-not $m.Success) { return '' }
    return $m.Groups['f'].Value
}

function Test-DelegateRun {
    param([hashtable]$Run, [hashtable]$Scope, [hashtable]$DistRun)

    $r = [PackCheck]::new('PracticeGate')

    foreach ($e in $Scope.Errors) {
        $r.Fail("cannot read the called gate's own scope: $e")
    }

    if ([string]::IsNullOrWhiteSpace($Run.ReportText)) {
        $r.Note = "the gate exited $($Run.ExitCode) and wrote no report"
        $r.Seal()
        if ($r.Status -eq 'PASS') { $r.Status = 'INCONCLUSIVE' }
        return $r
    }

    $rows = @($Run.Rows)
    $r.Candidates = $rows.Count
    if ($rows.Count -eq 0) {
        $r.Note = 'the gate wrote a report this parser could not read a single row from -- its report shape changed'
        $r.Seal()
        return $r
    }

    foreach ($row in $rows) {
        if (-not $row.Known) {
            $r.Fail("$($row.Name) reports status '$($row.Status)', which is not in this parser's vocabulary (PASS/FAIL/INCONCLUSIVE/SKIPPED) -- the gate's outcome set changed and nothing here may interpret it")
        }
    }

    # COMPLETENESS. Every check the gate dispatches must appear in its report. A check that vanishes
    # from the output takes its coverage with it and leaves a report that still looks whole.
    foreach ($name in $Scope.CheckNames) {
        if (-not ($rows | Where-Object { $_.Name -eq $name })) {
            $r.Fail("the gate dispatches a check named '$name' and its report has no row for it -- coverage went missing without failing")
        }
    }
    if ($Scope.CheckNames.Count -gt 0 -and $Scope.ValidateSetNames.Count -gt 0) {
        $onlyDispatch = @($Scope.CheckNames | Where-Object { $_ -notin $Scope.ValidateSetNames })
        $onlySet = @($Scope.ValidateSetNames | Where-Object { $_ -notin $Scope.CheckNames })
        foreach ($n in $onlyDispatch) { $r.Fail("the gate dispatches '$n' but its -Skip ValidateSet does not accept it -- the check cannot be skipped and the two lists disagree") }
        foreach ($n in $onlySet) { $r.Fail("the gate's -Skip ValidateSet accepts '$n' and nothing dispatches it -- skipping it would report a check that does not run") }
    }

    # THE EXIT CODE MUST AGREE WITH THE TABLE. Both are the gate's own statements about the same
    # run, so a disagreement means one of them is wrong -- and the direction that matters is exit 0
    # over a table with a failure in it, which is exactly the shape a caller trusts blindly.
    $expected = 0
    if (@($rows | Where-Object { $_.Status -in @('FAIL', 'INCONCLUSIVE') }).Count -gt 0) { $expected = 1 }
    elseif (@($rows | Where-Object { $_.Status -eq 'SKIPPED' }).Count -gt 0) { $expected = 2 }
    if ($Run.ExitCode -ne $expected) {
        $r.Fail("the gate exited $($Run.ExitCode) and its own table implies $expected -- its summary and its findings disagree, so neither can be relied on")
    }

    # ── THE PATTERN TABLE THE CONTENT RUN USED ──────────────────────────────────
    # THE CARDINAL FAILURE OF THIS REPOSITORY IS A CHECK THAT COULD NOT RUN REPORTING PASS, and this
    # is the one place it could still happen silently. The delegated redaction check has a FALLBACK:
    # its real pattern table is hold-listed out of the pack, so a run pointed at a staged registry
    # directory loads the shipped starter table instead, forbids example-corp and acme_warehouse, and
    # reports a green Redaction line over a tree nobody has looked at for real identifiers. Every
    # count downstream still reconciles -- the file count is identical, the two enumerations agree,
    # the exit code is 0 -- because the fallback is a change of PATTERNS, not of scope. Nothing in
    # this wrapper's output said so.
    #
    # So the identity of the table is asserted, not narrated. Failing here is failing loudly on the
    # only question the pack actually turns on.
    $contentTable = Get-DelegateRedactionTable -Run $Run
    if ([string]::IsNullOrWhiteSpace($Scope.RealTable) -or [string]::IsNullOrWhiteSpace($Scope.ExampleTable)) {
        # The parse of the two names failed; $Scope.Errors already carries a FAIL for it above, so
        # nothing further is said here. Deliberately not falling back to a hardcoded pair: a
        # remembered filename is how this check would come to accept the placeholder table again.
    }
    elseif ([string]::IsNullOrWhiteSpace($contentTable)) {
        $r.Fail("the gate's Redaction row does not say which pattern table it loaded (no 'table=' field in its note) -- a redaction scan whose table is unknown cannot be told apart from one that fell back to placeholder patterns, and a pack must not be certified on a scan of unknown strength")
    }
    elseif ($contentTable -eq $Scope.ExampleTable) {
        $r.Fail("the content run scanned with $contentTable, the GENERIC STARTER table -- it forbids placeholder vocabulary that appears in no real tree, so this pack has NOT been examined for organisation identifiers and must not be certified. Point -GateDir at a registry directory holding $($Scope.RealTable); the staged copy will never hold it, because it is hold-listed out of the pack on purpose")
    }
    elseif ($contentTable -ne $Scope.RealTable) {
        $r.Fail("the content run scanned with '$contentTable', which is neither $($Scope.RealTable) nor $($Scope.ExampleTable) -- the gate resolved a table this wrapper cannot classify, so the strength of the scan is unknown and no pack may be certified on it")
    }

    # ── THE DISTRIBUTION RUN ────────────────────────────────────────────────────
    # A SECOND, INDEPENDENT PROOF THAT THE REAL TABLE DID NOT SHIP, and its independence is the
    # point: the hold list is one mechanism, and asking the hold list whether the hold list worked
    # proves nothing. This run is the delegated gate loading its registries from INSIDE the pack. If
    # it can reach the real table, the pack contains the reconnaissance map -- whatever the hold list
    # believes.
    #
    # Its verdict on identifiers is NOT read as one. It scanned with placeholder patterns by design,
    # so a green line here says the plumbing works from a distribution and says nothing about the
    # tree; that is why this block asserts the table and the mechanics and never the finding count.
    if ($null -ne $DistRun) {
        if ([string]::IsNullOrWhiteSpace($DistRun.ReportText)) {
            $r.Fail("the distribution run -- the gate loading its registries from inside the pack -- exited $($DistRun.ExitCode) and wrote no report, so a recipient cannot stand this pack's own gate up and nothing here has established that they can")
        }
        else {
            $distRows = @($DistRun.Rows | Where-Object { $_.Name -eq 'Redaction' })
            if ($distRows.Count -eq 0) {
                $r.Fail('the distribution run wrote a report with no Redaction row -- the check that has to work from a distribution did not report from one')
            }
            else {
                if ($distRows[0].Status -in @('FAIL', 'INCONCLUSIVE')) {
                    $r.Fail("the distribution run's redaction check reported $($distRows[0].Status) against the pack's own registries -- a recipient's first run of the gate they were shipped would be red, and the finding is theirs to read before it is ours: $(@($distRows[0].Findings) -join ' | ')")
                }
                $distTable = Get-DelegateRedactionTable -Run $DistRun
                if (-not [string]::IsNullOrWhiteSpace($Scope.RealTable) -and $distTable -eq $Scope.RealTable) {
                    $r.Fail("the distribution run loaded $distTable FROM INSIDE THE PACK -- the real pattern table shipped. In aggregate that table is every internal identifier this repository knows about, captioned with why each matters; it is hold-listed for exactly that reason, and this run reached it anyway")
                }
                elseif ([string]::IsNullOrWhiteSpace($distTable)) {
                    $r.Fail("the distribution run does not say which pattern table it loaded -- so nothing here has established that the pack ships the starter table rather than the real one")
                }
            }
        }
    }

    $r.Note = "$($rows.Count) check(s) reported; gate exit $($Run.ExitCode); content run scanned with $(if ($contentTable) { $contentTable } else { '<table not stated>' })"
    if ($null -ne $DistRun) {
        $dt = Get-DelegateRedactionTable -Run $DistRun
        $r.Note += "; the pack's own copy resolves $(if ($dt) { $dt } else { '<table not stated>' })"
    }
    $r.Seal()
    return $r
}

# ── CHECK 2 -- EVERY DEVIATION IS A REGISTERED BUNDLE BOUNDARY ──────────────────
# The bundle is not the repository. Two classes of finding are structural rather than defects, and
# both are registered with reasons instead of being remembered:
#
#   * a check that cannot apply to a distribution at all (the negative-claim inversion reads
#     planning documents a pack does not ship), and
#   * a citation that resolves in the repository and not in the bundle.
#
# Checked in both directions. An entry that no longer corresponds to a finding FAILS, because the
# quiet way this rots is somebody fixing the citation -- at which point the entry covers nothing
# and goes on suppressing forever.

function Test-BundleBoundary {
    param([hashtable]$Run, [hashtable]$Registry)

    $r = [PackCheck]::new('BundleBoundary')

    $rows = @($Run.Rows)
    if ($rows.Count -eq 0) {
        $r.Note = 'no readable report from the called gate -- nothing to hold the registry against'
        $r.Seal()
        return $r
    }

    $regChecks = @($Registry.bundle_boundary.checks)
    $regCites = @($Registry.bundle_boundary.citations)
    foreach ($e in $regChecks) {
        if (-not $e.ContainsKey('check') -or -not $e.ContainsKey('reason') -or [string]::IsNullOrWhiteSpace([string]$e.reason)) {
            $r.Fail("a bundle_boundary.checks entry is missing 'check' or 'reason' -- an escape hatch without a reason is a silencer")
        }
    }
    foreach ($e in $regCites) {
        if (-not $e.ContainsKey('document') -or -not $e.ContainsKey('token') -or -not $e.ContainsKey('reason') -or [string]::IsNullOrWhiteSpace([string]$e.reason)) {
            $r.Fail("a bundle_boundary.citations entry is missing 'document', 'token' or 'reason' -- an escape hatch without a reason is a silencer")
        }
    }

    $seenChecks = [System.Collections.Generic.HashSet[string]]::new()
    $seenCites = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($row in $rows) {
        $r.Candidates++
        if ($row.Status -eq 'PASS') { continue }

        $regCheck = @($regChecks | Where-Object { $_.check -eq $row.Name })
        if ($regCheck.Count -gt 0) {
            $null = $seenChecks.Add($row.Name)
            # A registered check may deviate only in the registered WAY. 'Assertions is not
            # applicable to a bundle' does not license Assertions failing for some other reason.
            $allowed = @($regCheck[0].statuses)
            if ($allowed.Count -gt 0 -and $row.Status -notin $allowed) {
                $r.Fail("$($row.Name) is a registered bundle boundary for status(es) $($allowed -join '/'), and reported $($row.Status) -- this is a different deviation and is not covered")
            }
            continue
        }

        # Not a registered check, so every finding it raised must be registered individually.
        if ($row.Findings.Count -eq 0) {
            $r.Fail("$($row.Name) reported $($row.Status) against the staged bundle with no findings to attribute -- unregistered, and unexplainable from the report")
            continue
        }
        foreach ($f in $row.Findings) {
            # Citation findings are the only class registrable per-finding, and they are matched on
            # DOCUMENT plus TOKEN, never on a line number: a line number rots on the next edit to
            # the paragraph above it, which is why the plan deleted its line counts rather than
            # updating them.
            $m = [regex]::Match($f, "^(?<doc>[^:]+):(?<line>\d+)\s+cites '(?<token>[^']+)'")
            if (-not $m.Success) {
                $r.Fail("$($row.Name): $f -- not a registered bundle boundary, and not a citation this check knows how to register")
                continue
            }
            $doc = $m.Groups['doc'].Value
            $tok = $m.Groups['token'].Value
            $hit = @($regCites | Where-Object { $_.document -eq $doc -and $_.token -eq $tok })
            if ($hit.Count -eq 0) {
                $r.Fail("$doc cites '$tok', which does not resolve in the bundle and is not registered in bundle_boundary.citations -- either register it with the reason it cannot resolve, or rewrite the citation to a path the pack ships")
            }
            else { $null = $seenCites.Add("$doc||$tok") }
        }
    }

    # THE REVERSE DIRECTION.
    foreach ($e in $regChecks) {
        if (-not $e.ContainsKey('check')) { continue }
        if (-not $seenChecks.Contains([string]$e.check)) {
            $r.Fail("bundle_boundary registers check '$($e.check)' as not applying to a bundle, and it reported PASS or did not appear -- the boundary moved; strike the entry")
        }
    }
    foreach ($e in $regCites) {
        if (-not $e.ContainsKey('document') -or -not $e.ContainsKey('token')) { continue }
        if (-not $seenCites.Contains("$($e.document)||$($e.token)")) {
            $r.Fail("bundle_boundary registers '$($e.token)' in $($e.document) as a dangling citation, and the bundle run no longer reports it -- the citation was fixed or the document changed; strike the entry")
        }
    }

    $r.Note = "$($regChecks.Count) check boundary(ies), $($regCites.Count) citation boundary(ies) registered"
    $r.Seal()
    return $r
}

# ── CHECK 3 -- EVERY STAGED FILE IS INSIDE SOME SCAN ────────────────────────────

function Test-PackCoverage {
    param([hashtable]$Stage, [hashtable]$Run, [hashtable]$Scope, [hashtable]$Registry)

    $r = [PackCheck]::new('Coverage')

    if ($Scope.Errors.Count -gt 0) {
        $r.Note = "the called gate's scan scope could not be parsed, so coverage is unknown -- see the PracticeGate findings"
        $r.Seal()
        return $r
    }

    $files = @($Stage.RelPaths)
    $r.Candidates = $files.Count
    if ($files.Count -eq 0) { $r.Seal(); return $r }

    $exempt = @($Registry.unscanned)
    foreach ($e in $exempt) {
        if (-not $e.ContainsKey('path') -or -not $e.ContainsKey('reason') -or [string]::IsNullOrWhiteSpace([string]$e.reason)) {
            $r.Fail("an 'unscanned' entry is missing 'path' or 'reason' -- an escape hatch without a reason is a silencer")
        }
    }

    # THREE DISJOINT BUCKETS, AND THEY MUST COVER THE TREE. Every staged file lands in exactly one:
    # scanned, outside the scan by extension, or exempted by the gate by NAME. The third used to be
    # `continue` -- counted nowhere -- which is what made the note below fail to add up: it printed
    # 87 staged, 83 scanned, 0 outside, and left four files unaccounted for with no term naming them.
    # A file dropped from a sum by a bare `continue` is invisible in exactly the way this check exists
    # to prevent, so it now has a counter and a name in the output.
    $scanned = [System.Collections.Generic.List[string]]::new()
    $unscanned = [System.Collections.Generic.List[string]]::new()
    $selfExempt = [System.Collections.Generic.List[string]]::new()
    foreach ($rel in $files) {
        $ext = [System.IO.Path]::GetExtension($rel).ToLowerInvariant()
        $name = [System.IO.Path]::GetFileName($rel)
        # Extension FIRST, then the name exemption -- the order the delegated gate applies them in,
        # and the stricter of the two: a self-exempt file whose extension is out of scope is outside
        # the scan for two reasons, and must still be registered with one. Swapping these would let a
        # name exemption quietly absorb a coverage gap.
        if (-not ($Scope.Extensions -contains $ext)) { $unscanned.Add($rel); continue }
        if ($Scope.SelfNames -contains $name) { $selfExempt.Add($rel); continue }
        $scanned.Add($rel)
    }

    foreach ($rel in $unscanned) {
        if (-not (@($exempt | Where-Object { $_.path -eq $rel }).Count -gt 0)) {
            $r.Fail("$rel is outside the redaction scan (extension '$([System.IO.Path]::GetExtension($rel))' is not in its list) and is not registered in 'unscanned' -- it ships unexamined; add the extension to the gate, or register the file with the reason it cannot be read")
        }
    }
    # Reverse direction, both modes: an entry for a file that has gone, and an entry for a file
    # that is now scanned -- the second keeps working forever while exempting nothing.
    foreach ($e in $exempt) {
        if (-not $e.ContainsKey('path')) { continue }
        $p = [string]$e.path
        if ($files -notcontains $p) {
            $r.Fail("'unscanned' registers $p, which is not in the staged pack -- the file was moved or removed; strike the entry")
        }
        elseif ($unscanned -notcontains $p) {
            $r.Fail("'unscanned' registers $p and the redaction scan now covers it -- the exemption is suppressing a check that would pass; strike the entry")
        }
    }

    # TWO ENUMERATIONS OF ONE SCOPE. This one counted from the staged tree; the gate reported its
    # own. They are derived independently -- the only shared input is the extension list, parsed --
    # so a disagreement means one side is wrong and this check must not pass either way. It is also
    # the only assertion here that the gate looked at the PACK rather than at something else.
    $redaction = @($Run.Rows | Where-Object { $_.Name -eq 'Redaction' })
    if ($redaction.Count -eq 0) {
        $r.Fail('the called gate reported no Redaction row, so there is no count to compare the staged tree against')
    }
    elseif ($redaction[0].Status -eq 'SKIPPED') {
        $r.Fail('the called gate SKIPPED its redaction check, so the pack was never scanned for identifiers -- a share pack may not be certified clean on a skipped scan')
    }
    elseif ($redaction[0].Candidates -ne $scanned.Count) {
        $r.Fail("the staged pack holds $($scanned.Count) file(s) inside the redaction scan and the gate reports examining $($redaction[0].Candidates) -- two enumerations of one scope disagree; the parse of the gate's scan scope is stale, or the two trees are not the same tree")
    }

    # THE NOTE HAS TO ADD UP, and it did not. It read "87 staged file(s): 83 scanned, 0 outside the
    # redaction scan, 2 excluded as non-content" -- 83 + 0 + 2 = 85, four short, and the four missing
    # were the delegated gate's self-exempt names, which the line never mentioned. Worse, the term
    # that made it look like a sum was the staging exclusion, which is not a term in this sum at all:
    # excluded files were never staged, so they are not among the staged files being partitioned. A
    # check whose entire argument is "two independent enumerations of one scope agree" cannot print a
    # line that does not reconcile; a reader who checks the arithmetic and finds it wrong has been
    # taught to stop checking.
    #
    # So the partition is printed as a partition, with an explicit `=`, and the two staging statistics
    # are reported after a semicolon as what they are: facts about files that are NOT in this sum.
    $sum = $scanned.Count + $unscanned.Count + $selfExempt.Count
    if ($sum -ne $files.Count) {
        # Cannot happen while the three buckets stay disjoint and exhaustive, which is exactly why it
        # is asserted: the next edit to that loop is the one that breaks it, and a partition that has
        # stopped partitioning would otherwise show up as nothing at all.
        $r.Fail("this check partitioned $($files.Count) staged file(s) into buckets totalling $sum -- the three cases are no longer disjoint and exhaustive, so the coverage argument does not hold and must not be reported as though it did")
    }
    $r.Note = ("{0} staged file(s) = {1} scanned + {2} outside the redaction scan + {3} self-exempt by the gate; separately, staging withheld {4} as non-content" -f
        $files.Count, $scanned.Count, $unscanned.Count, $selfExempt.Count, $Stage.Excluded)
    if ($Stage.ContainsKey('HeldBack')) {
        $r.Note += " and $($Stage.HeldBack) as hold-listed"
    }
    # THE SCOPE OF THE PARTITION, STATED. What this check counts has not changed -- it is the content
    # tree, as it always was, because $Stage.RelPaths is content-tree-relative and the root files were
    # never in it. What changed is that their absence is now SAID rather than left as an unexplained
    # difference between this line and a directory listing of the pack root. They are a different
    # check's subject; reading this line and finding two files missing from it, with nothing saying
    # where they went, is how the hole stayed open for the life of the branch.
    if ($Stage.ContainsKey('RootPaths')) {
        $rootCount = @($Stage.RootPaths).Count + 1   # + the manifest, which is never in its own list
        $r.Note += ". The pack root's $rootCount file(s) are NOT in this partition -- they sit beside the content tree and are the RootFiles check's subject"
    }
    $r.Seal()
    return $r
}

# ── CHECK 4 -- NOTHING FROM THE HOLD LIST IS IN THE TREE ────────────────────────

function Test-HoldList {
    param([hashtable]$Stage, [object[]]$Classes, [string]$TableName = '')

    $r = [PackCheck]::new('HoldList')

    $classList = @($Classes)
    if ($classList.Count -eq 0) {
        $r.Fail('the hold list is empty -- a check that forbids nothing must not report a pass')
        return $r
    }
    $label = if ([string]::IsNullOrWhiteSpace($TableName)) { 'the hold list' } else { $TableName }

    # THE PATTERN TABLE IS TESTED FIRST, ON EVERY RUN. A regex that has stopped matching produces
    # an empty finding set, which is indistinguishable from a clean tree. Each class carries an
    # example it must catch, and most carry the near-miss the pack legitimately ships, which it
    # must not.
    #
    # [regex]::IsMatch, NOT -match, AND THAT IS LOAD-BEARING -- the same correction the redaction
    # check carries one file over. PowerShell's -match is case-insensitive whatever the pattern says;
    # the walk below and the BUILDER both use [regex]::IsMatch, which is not. A control written the
    # idiomatic way would report a class healthy on an example the walk itself walks straight past,
    # and now that the builder acts on these patterns it would also withhold a different set of files
    # than the ones this check believes it is asserting about.
    #
    # KEYS ARE THE DATA FILE'S, not the old inline table's: name / pattern / example /
    # counter_example / reason -- deliberately identical to the redaction table's, so there is one
    # shape to learn. Every one is required except counter_example, and a class missing one is
    # reported rather than skipped: a patternless or unexplained class cannot be trusted to forbid
    # anything, and silently dropping it would shrink the hold list without saying so.
    $active = [System.Collections.Generic.List[object]]::new()
    foreach ($c in $classList) {
        $name = if ($c.ContainsKey('name') -and -not [string]::IsNullOrWhiteSpace([string]$c.name)) { [string]$c.name } else { '(unnamed)' }
        $ok = $true
        foreach ($k in @('name', 'pattern', 'example', 'reason')) {
            if (-not $c.ContainsKey($k) -or [string]::IsNullOrWhiteSpace([string]$c[$k])) {
                $r.Fail("${label}: hold class '$name' is missing required key '$k' -- an unnamed, unexplained or patternless class cannot be trusted to forbid anything")
                $ok = $false
            }
        }
        if (-not $ok) { continue }
        if (-not [regex]::IsMatch([string]$c.example, [string]$c.pattern)) {
            $r.Fail("${label}: hold class '$name' no longer matches its own example ($($c.example)) -- the pattern is broken and this class forbids nothing")
            continue
        }
        if ($c.ContainsKey('counter_example') -and -not [string]::IsNullOrWhiteSpace([string]$c.counter_example)) {
            if ([regex]::IsMatch([string]$c.counter_example, [string]$c.pattern)) {
                $r.Fail("${label}: hold class '$name' matches its counter-example ($($c.counter_example)), which the pack is supposed to ship -- the pattern is too broad and would fail a clean pack, or worse, make the builder withhold a file the recipient needs")
                continue
            }
        }
        $active.Add([pscustomobject]@{ Name = $name; Pattern = [string]$c.pattern; Reason = [string]$c.reason })
    }

    $files = @($Stage.RelPaths)
    $r.Candidates = $files.Count
    foreach ($rel in $files) {
        # $active, not $classList: a class that failed its own controls has already been reported, and
        # sweeping with a pattern known to be broken would add its silence to the report as coverage.
        foreach ($c in $active) {
            if ([regex]::IsMatch($rel, $c.Pattern)) {
                $r.Fail("$rel  $($c.Name) -- must not ship. $($c.Reason)")
            }
        }
    }

    # ── THE BUILDER'S DECISIONS, CROSS-CHECKED IN BOTH DIRECTIONS ────────────────
    # The builder reads this same table and WITHHOLDS a matching file instead of staging it, which is
    # what keeps the real pattern tables out of the pack. Two readers of one table is one loader more
    # than strictly necessary, and the way that arrangement rots is silently: the builder withholds
    # against a table this check is not looking at, or this check forbids a path the builder shipped,
    # and both runs stay green because neither is asked about the other. So they are compared.
    #
    # The forward direction is the loop above -- anything held that IS in the tree is a finding, which
    # is the check the builder should have made impossible. The reverse direction is here: everything
    # the builder says it withheld must be something this table actually holds. A withheld file that
    # matches no class means the builder is withholding on some other authority, and the next thing it
    # withholds silently could be a file the recipient needed.
    if ($Stage.ContainsKey('HeldPaths')) {
        foreach ($rel in @($Stage.HeldPaths)) {
            $hit = @($active | Where-Object { [regex]::IsMatch($rel, $_.Pattern) })
            if ($hit.Count -eq 0) {
                $r.Fail("the build step withheld '$rel' from the pack and no class in $label holds it -- the builder is withholding files on an authority this check cannot see, so it could withhold one the recipient needs without anything here objecting")
            }
        }
        if ($Stage.ContainsKey('HoldTable') -and -not [string]::IsNullOrWhiteSpace($TableName) -and $Stage.HoldTable -ne $TableName) {
            $r.Fail("the build step withheld files using '$($Stage.HoldTable)' and this check is asserting against '$TableName' -- two readers of what was supposed to be one table, so neither the pack's contents nor this verdict describes the other")
        }
    }

    if ($r.Note -eq '') {
        $r.Note = "$($active.Count) hold class(es) from $label, each verified against its own example"
        if ($Stage.ContainsKey('HeldPaths')) {
            $held = @($Stage.HeldPaths)
            $r.Note += "; the build withheld $($held.Count) file(s)$(if ($held.Count -gt 0) { ": $($held -join ', ')" } else { '' })"
        }
    }
    $r.Seal()
    return $r
}

# ── CHECK 5 -- THE PACK ROOT IS A SUBJECT ───────────────────────────────────────
# Everything above this line is about the CONTENT TREE. The pack has a second layer -- LICENSE,
# NOTICE and the manifest, beside the tree rather than in it -- and it had no check at all, for two
# independent reasons that each look like a clean result:
#
#   * the file list every check here reads is the manifest's entries under the content prefix with
#     the prefix stripped, so a root file is filtered out by not carrying the prefix; and
#   * both licence files are extensionless, so they are outside the delegated redaction scan's
#     extension list even if something did point it at them.
#
# Four organisation-identifying lines rode through every green run of this gate for the life of the
# branch and were found by a hand grep. That is the shape this whole repository is written against:
# "no findings" and "not looked at" printing the same line.

function Get-RootFileFixture {
    # THE RUN-TIME CONTROL'S SUBJECT, and the reason it is a fixture rather than the real NOTICE: a
    # control has to be able to fail. Scanning the real file proves the real file is clean, which is
    # the CHECK; proving that this scan can still SEE an identifier in a root file needs a document
    # that carries one, and the pack must not contain one for the control's benefit.
    #
    # Shaped like a de-branded notice on purpose -- a product line, the licence sentence, and the
    # standard unfilled Apache appendix copyright line, brackets and all. That last line is the
    # near-miss that matters: `Copyright [yyyy] [name of copyright owner]` is what a de-branded
    # LICENSE carries, it looks like an attribution, and a class broad enough to fire on it would
    # fail every clean pack forever.
    #
    # Get-, not New-: PSUseShouldProcessForStateChangingFunctions demands SupportsShouldProcess on a
    # New-* function, and ShouldProcess is the mechanism that lets a writer report success under
    # -WhatIf having written nothing. This one writes nothing and returns a string.
    param([string]$Injected = '')

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('a-practice-pack')
    $lines.Add('')
    $lines.Add('Licensed under the Apache License, Version 2.0. You may obtain a copy of')
    $lines.Add('the License in the LICENSE file distributed with this work, or at')
    $lines.Add('http://www.apache.org/licenses/LICENSE-2.0')
    $lines.Add('')
    $lines.Add('   Copyright [yyyy] [name of copyright owner]')
    # ON ITS OWN LINE, and that is not cosmetic. The scan below is line-based, so an example spliced
    # into the middle of a sentence would stop matching any class anchored with ^ or $ -- and the
    # control would then report a healthy class as broken. A bare line is the form every class can
    # match if it matches at all.
    if (-not [string]::IsNullOrEmpty($Injected)) { $lines.Add($Injected) }
    return (($lines -join "`n") + "`n")
}

function Find-RootFileMatches {
    # One line-based sweep, used for BOTH the real root files and the run-time fixtures, so the
    # control exercises the same code path as the check. A control that runs through a different
    # scanner than the check is a control over the control.
    #
    # [regex]::Match, NOT -match: PowerShell's -match is case-insensitive whatever the pattern says,
    # and one class in the delegated table -- the portfolio nouns -- is deliberately case-SENSITIVE
    # because its lowercase spellings are ordinary English. Sweeping with -match would fire on prose.
    param([string]$Text, [object[]]$Classes, [string]$Label)

    $hits = [System.Collections.Generic.List[object]]::new()
    $lines = $Text -replace "`r`n", "`n" -split "`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        foreach ($c in @($Classes)) {
            $m = [regex]::Match($lines[$i], $c.Pattern)
            if ($m.Success) {
                $hits.Add([pscustomobject]@{ Path = $Label; Line = ($i + 1); Class = $c.Name; Match = $m.Value })
            }
        }
    }
    # CALLER CONTRACT, and the opposite one to Read-PackLines' -- read that comment first, because the
    # two look like they should agree and must not. Read-PackLines returns `,$array` so that a one-LINE
    # file does not unroll into a bare string, which costs its callers a variable assignment. Here the
    # elements are objects and every caller wants to iterate or filter them, so the wrapper would be
    # actively wrong: `@(Find-RootFileMatches ...)` around a wrapped list yields an array holding the
    # LIST, one element, and `$_.Class` on it throws -- which is exactly what it did on the first run
    # of this check. So this unrolls, and every call site wraps in @() to normalise the zero and one
    # cases.
    return $hits.ToArray()
}

function Test-PackRootFiles {
    param([hashtable]$Stage, [hashtable]$Registry, [hashtable]$Scope, [string]$GateDir)

    $r = [PackCheck]::new('RootFiles')

    # ── THE VOCABULARY, FAIL-CLOSED ──────────────────────────────────────────────
    # A throw here is caught and reported as a FAIL rather than aborting the gate, because the other
    # five checks have already measured real things and their findings are worth printing. What it is
    # NOT is a degrade: there is no branch below that proceeds with an empty class list.
    $loaded = $null
    try { $loaded = Import-RootScanClasses -GateDir $GateDir -Scope $Scope }
    catch {
        $r.Fail("the pack root could not be scanned: $($_.Exception.Message)")
        return $r
    }
    if ($loaded.Source -ne 'real') {
        # Same argument as the content run's table-identity assertion, one layer out. The starter
        # table forbids placeholder vocabulary that appears in no real tree, so a root file cleared
        # by it has not been examined -- and this is the layer where that mattered most, because the
        # licence files are the first thing a recipient opens.
        $r.Fail("the pack root would be scanned with $($loaded.File), the GENERIC STARTER table -- it forbids placeholder vocabulary only, so the pack root would be certified by patterns that match nothing real. Point -GateDir at a registry directory holding $($Scope.RealTable)")
        return $r
    }

    # ── THE TABLE IS TESTED BEFORE IT IS TRUSTED, ON EVERY RUN ───────────────────
    # Identical treatment to the hold list above and to the delegated gate's own controls, and for
    # the identical reason: a class that has stopped matching produces an empty finding set, which is
    # exactly what a clean pack root produces.
    $active = [System.Collections.Generic.List[object]]::new()
    foreach ($c in @($loaded.Classes)) {
        $name = if ($c.ContainsKey('name') -and -not [string]::IsNullOrWhiteSpace([string]$c.name)) { [string]$c.name } else { '(unnamed)' }
        $ok = $true
        foreach ($k in @('name', 'pattern', 'example', 'reason')) {
            if (-not $c.ContainsKey($k) -or [string]::IsNullOrWhiteSpace([string]$c[$k])) {
                $r.Fail("$($loaded.File): class '$name' is missing required key '$k' -- an unnamed, unexplained or patternless class cannot be trusted to forbid anything")
                $ok = $false
            }
        }
        if (-not $ok) { continue }
        if (-not [regex]::IsMatch([string]$c.example, [string]$c.pattern)) {
            $r.Fail("$($loaded.File): class '$name' no longer matches its own example ('$($c.example)') -- the pattern is broken and this class forbids nothing in the pack root either")
            continue
        }
        if ($c.ContainsKey('counter_example') -and -not [string]::IsNullOrWhiteSpace([string]$c.counter_example)) {
            if ([regex]::IsMatch([string]$c.counter_example, [string]$c.pattern)) {
                $r.Fail("$($loaded.File): class '$name' matches its counter-example ('$($c.counter_example)') -- the pattern is too broad and would fail a clean pack root")
                continue
            }
        }
        $active.Add([pscustomobject]@{ Name = $name; Pattern = [string]$c.pattern; Example = [string]$c.example })
    }
    if ($active.Count -eq 0) {
        $r.Fail("$($loaded.File) yielded no usable class -- every class failed its own controls, so this check forbids nothing and must not report a pass")
        return $r
    }

    # ── THE PAIR THAT WAS ACTUALLY GOT WRONG ─────────────────────────────────────
    # A DE-BRANDED NOTICE MUST PASS AND A BRANDED ONE MUST FAIL, asserted on every run, in both
    # directions, per class. The two halves catch opposite failures and only one of them is loud:
    #
    #   * the near-miss half (nothing injected, zero findings expected) catches a class broad enough
    #     to fire on an ordinary licence header. That fails every clean pack, so somebody notices.
    #   * the positive half (each class's own example injected, that class expected to fire) catches
    #     a scan that cannot see an identifier in a root file. That is the silent one, and it is the
    #     defect this check was written for -- it does not fail anything; it prints a green line.
    #
    # NOTHING MATCHABLE IS WRITTEN DOWN HERE. The injected string is each class's OWN example, taken
    # off the loaded table, which is the same trick as assembling the secret examples from fragments:
    # the run-time control is completely real, and this file holds no organisation identifier for a
    # scanner, for the delegated gate, or for a recipient's grep to find. It also means the control
    # keeps working when the table is edited, which a literal would not.
    $cleanHits = @(Find-RootFileMatches -Text (Get-RootFileFixture) -Classes $active -Label '<fixture>')
    foreach ($h in $cleanHits) {
        $r.Fail("class '$($h.Class)' fires on a de-branded notice fixture, at '$($h.Match)' -- the pattern is too broad for a root file: an ordinary Apache header with no organisation in it would fail this check, so the class must be narrowed rather than this control relaxed")
    }
    foreach ($c in $active) {
        $dirty = @(Find-RootFileMatches -Text (Get-RootFileFixture -Injected $c.Example) -Classes $active -Label '<fixture>')
        if (@($dirty | Where-Object { $_.Class -eq $c.Name }).Count -eq 0) {
            $r.Fail("class '$($c.Name)' does not fire when its own example is placed in a notice fixture -- this scan cannot see that identifier in a root file, so a clean verdict on the pack root means nothing for that class")
        }
    }

    # ── WHAT THE ROOT FILES ARE, FROM THE MANIFEST ───────────────────────────────
    # Never from a list written here. The builder decides what sits beside the content tree, records
    # it, and this derives the set -- so a third root file it starts placing is scanned the same day,
    # with no edit to this file and no window in which it ships unexamined.
    if (-not $Stage.ContainsKey('RootPaths') -or -not $Stage.ContainsKey('ManifestName')) {
        $r.Fail('the staged pack description carries no root-file list -- the manifest read did not produce one, so this check has no subject and must not report a pass')
        return $r
    }
    $manifestName = [string]$Stage.ManifestName
    if ([string]::IsNullOrWhiteSpace($manifestName)) {
        $r.Fail('the manifest filename is empty, so the manifest itself -- a root file, and the one a recipient reads first -- cannot be located or scanned')
        return $r
    }
    # The manifest is a root file too, and it is the one no other check can ever reach: it is not in
    # its own `files` list, because a manifest cannot list itself.
    $declared = [System.Collections.Generic.List[string]]::new()
    foreach ($p in @($Stage.RootPaths)) { $declared.Add([string]$p) }
    if (@($Stage.RootPaths).Count -eq 0 -and -not [string]::IsNullOrEmpty([string]$Stage.Prefix)) {
        # A pack built with a content prefix and NOTHING beside it means either the licence files went
        # missing -- which the builder treats as a build failure, so this would be the second
        # independent report of it -- or this gate is reading the wrong grain and every root file
        # silently fell into the content bucket. Both are failures; neither may be scanned to a pass.
        $r.Fail("the manifest declares no file beside the content tree at '$($Stage.Prefix)/' -- Apache-2.0 4(a) and 4(d) put LICENSE and NOTICE there, so either the build omitted them or this check is reading the wrong grain and they were counted as content")
    }
    $declared.Add($manifestName)

    # ── TWO ENUMERATIONS OF ONE LAYER ────────────────────────────────────────────
    # The manifest's account of the pack root, and a walk of the pack root. A root file this check
    # does not know about must FAIL rather than pass by not being enumerated -- which is precisely how
    # LICENSE and NOTICE came to be unexamined.
    $contentAtRoot = @()
    if ([string]::IsNullOrEmpty([string]$Stage.Prefix)) {
        # With no prefix the content tree IS the pack root, so a top-level content file is not a root
        # file and must not be double-counted here. Coverage owns those.
        $contentAtRoot = @(@($Stage.RelPaths) | Where-Object { $_ -notmatch '[\\/]' })
    }
    $onDisk = @(Get-ChildItem -LiteralPath $Stage.Root -File | ForEach-Object { $_.Name } |
        Where-Object { $contentAtRoot -notcontains $_ })
    foreach ($n in $onDisk) {
        if ($declared -notcontains $n) {
            $r.Fail("the pack root holds '$n' and the manifest declares no such file there -- it ships unexamined by every check in this gate, which is exactly the state LICENSE and NOTICE were in; declare it in the manifest so it is scanned, or stop shipping it")
        }
    }
    foreach ($n in $declared) {
        if ($onDisk -notcontains $n) {
            $r.Fail("the manifest declares root file '$n' and the pack root does not hold it -- the pack is short of what it claims, and a file that is not there cannot be scanned clean")
        }
    }

    # ── THE SCAN ─────────────────────────────────────────────────────────────────
    $allowed = @()
    if (-not $Registry.ContainsKey('root_file_allowed')) {
        $r.Fail("the share-pack registry has no 'root_file_allowed' list -- a legally-required occurrence has nowhere to be registered, so the only way past this check would be to weaken it")
    }
    else { $allowed = @($Registry.root_file_allowed) }
    foreach ($e in $allowed) {
        if (-not $e.ContainsKey('path') -or -not $e.ContainsKey('match') -or -not $e.ContainsKey('reason') -or
            [string]::IsNullOrWhiteSpace([string]$e.reason)) {
            $r.Fail("a 'root_file_allowed' entry is missing 'path', 'match' or 'reason' -- an escape hatch without a reason is a silencer, and this is the one list in this registry that can put an organisation identifier back in the pack")
        }
    }
    $seen = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($n in $declared) {
        $full = Join-Path $Stage.Root $n
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }   # already reported above
        $raw = [System.IO.File]::ReadAllText($full)
        if ($raw.Contains([char]0)) {
            # NOT `continue`. A root file this scan cannot read as text ships unexamined, and the
            # whole argument of this check is that unexamined must not read as clean. The binary
            # skip that IS legitimate is in Secrets, over a content tree whose every non-text file
            # is already a registered, reasoned decision; the pack root has no such register.
            $r.Fail("$n is not readable as text (it contains NUL bytes), so nothing has examined it -- a binary file beside the licence is not something this gate may pass by skipping")
            continue
        }
        $r.Candidates++
        foreach ($h in @(Find-RootFileMatches -Text $raw -Classes $active -Label $n)) {
            $hit = @($allowed | Where-Object { [string]$_.path -eq $h.Path -and [string]$_.match -eq $h.Match })
            if ($hit.Count -gt 0) {
                $null = $seen.Add("$($h.Path)||$($h.Match)")
                continue
            }
            # THE MATCHED VALUE IS QUOTED, and the split from Secrets is deliberate: an organisation
            # identifier is useless as a finding without it -- somebody has to know which word to
            # remove -- whereas a quoted credential manufactures the exposure it was hired to
            # detect. Same reasoning the header gives for why Secrets is the one check not delegated.
            $r.Fail("$($h.Path)`:$($h.Line)  $($h.Class) -- '$($h.Match)'. This is the pack ROOT: it is the first thing a recipient opens. Remove it, or -- if it is legally required -- register it in root_file_allowed with the reason")
        }
    }

    # THE REVERSE DIRECTION, same as every other registry in this file. An entry that stops matching
    # goes on permitting forever while covering nothing, and the quiet way this one rots is somebody
    # rewording the notice: the allowance survives the sentence it was written for.
    foreach ($e in $allowed) {
        if (-not $e.ContainsKey('path') -or -not $e.ContainsKey('match')) { continue }
        if (-not $seen.Contains("$([string]$e.path)||$([string]$e.match)")) {
            $r.Fail("'root_file_allowed' permits '$([string]$e.match)' in $([string]$e.path) and the scan no longer finds it there -- the notice was reworded or the file was renamed; strike the entry rather than leaving it to permit something nobody is checking for")
        }
    }

    $r.Note = ("{0} root file(s) scanned ({1}) with {2}, {3} class(es) each verified against its own example and against a de-branded notice fixture; {4} registered legal exception(s)" -f
        $r.Candidates, (@($declared) -join ', '), $loaded.File, $active.Count, @($allowed).Count)
    $r.Seal()
    return $r
}

# ── CHECK 6 -- NO CREDENTIAL, BELT AND BRACES ───────────────────────────────────

function Test-PackSecrets {
    param(
        [hashtable]$Stage,
        [hashtable]$Registry,
        [object[]]$Classes,
        [switch]$UseGitleaks,
        [string]$GitleaksExe
    )

    $r = [PackCheck]::new('Secrets')

    $classList = @($Classes)
    if ($classList.Count -eq 0) {
        $r.Fail('the secret class list is empty -- a check that matches nothing must not report a pass')
        return $r
    }
    foreach ($c in $classList) {
        if (-not ($c.Example -match $c.Pattern)) {
            $r.Fail("secret class '$($c.Class)' no longer matches its own example -- the classifier is broken and this class finds nothing")
        }
    }

    $fixtures = @($Registry.secret_fixtures)
    foreach ($e in $fixtures) {
        if (-not $e.ContainsKey('path') -or -not $e.ContainsKey('reason') -or [string]::IsNullOrWhiteSpace([string]$e.reason)) {
            $r.Fail("a 'secret_fixtures' entry is missing 'path' or 'reason' -- an escape hatch without a reason is a silencer")
        }
    }
    $fixturePaths = @($fixtures | Where-Object { $_.ContainsKey('path') } | ForEach-Object { [string]$_.path })
    $fixtureHits = @{}

    # Binary by extension, not by sniffing every byte: the pack's own hold list forbids archives
    # outright, and the coverage check has already made every remaining non-text file a registered,
    # reasoned decision. A NUL sniff is still applied below for anything that lies about itself.
    $binary = @('.pyc', '.zip', '.7z', '.tar', '.gz', '.tgz', '.png', '.jpg', '.jpeg', '.gif', '.pdf', '.docx', '.xlsx', '.pptx', '.exe', '.dll', '.ico', '.woff', '.woff2')

    foreach ($rel in @($Stage.RelPaths)) {
        $ext = [System.IO.Path]::GetExtension($rel).ToLowerInvariant()
        if ($binary -contains $ext) { continue }
        $full = Join-Path $Stage.PackDir $rel
        $raw = [System.IO.File]::ReadAllText($full)
        if ($raw.Contains([char]0)) { continue }
        $r.Candidates++

        $isFixture = $fixturePaths -contains $rel
        $lines = Read-PackLines -Path $full
        for ($i = 0; $i -lt $lines.Count; $i++) {
            foreach ($c in $classList) {
                $m = [regex]::Match($lines[$i], $c.Pattern)
                if (-not $m.Success) { continue }
                # Placeholders and indirections are stripped here rather than encoded as a
                # lookahead in the pattern. A lookahead after a greedy character class is how the
                # secret guard next door came to block the very remediation its own message
                # recommended -- the engine gives back a character and matches anyway.
                if ($m.Groups['v'].Success -and $m.Groups['v'].Value -match $script:NonLiteralValue) { continue }
                if ($isFixture) {
                    $fixtureHits[$rel] = $true
                    continue
                }
                # THE VALUE IS NOT IN THIS MESSAGE, and must never be added to it. A class and a
                # location are enough to go and look; a quoted credential in a report that gets
                # committed, mailed or pasted into a ticket is the exposure this check exists to
                # prevent, manufactured by the check itself.
                $r.Fail("$rel`:$($i + 1)  $($c.Class) -- value withheld deliberately; open the file to see it")
            }
        }
    }

    # A fixture that has stopped holding secret-shaped strings has stopped being a fixture, and its
    # exemption now covers a file nobody is checking.
    foreach ($p in $fixturePaths) {
        if (@($Stage.RelPaths) -notcontains $p) {
            $r.Fail("'secret_fixtures' registers $p, which is not in the staged pack -- strike the entry")
        }
        elseif (-not $fixtureHits.ContainsKey($p)) {
            $r.Fail("'secret_fixtures' exempts $p and nothing in it matches any secret class any more -- it is no longer a fixture and the exemption is suppressing a check that would pass; strike the entry")
        }
    }

    $note = "$($r.Candidates) text file(s), $($classList.Count) class(es) each verified against its own example; $($fixturePaths.Count) registered fixture(s)"

    if ($UseGitleaks) {
        $gl = Invoke-GitleaksScan -Stage $Stage -GitleaksExe $GitleaksExe -FixturePaths $fixturePaths
        foreach ($f in $gl.Findings) { $r.Fail($f) }
        $note += "; gitleaks: $($gl.Note)"
    }
    else {
        # Said on its face rather than left to be inferred from a green line. This check is a
        # shape scan, and the report should not read as more than that.
        $note += '; gitleaks NOT run (-Gitleaks not passed) -- this is a shape scan, not a full secret scan'
    }
    $r.Note = $note
    $r.Seal()
    return $r
}

# A scanner's idea of a path is not this script's. Measured 2026-08-17 against gitleaks 8.28.0, the
# reported File comes back ABSOLUTE with forward slashes even when --source was given a relative
# path -- but that is one version's behaviour on one platform, so the fixture list is matched on a
# normalised SUFFIX rather than on the form observed. Pulled out as its own function because the
# invocation cannot be exercised without the binary present, while the parsing can: this half is
# covered by controls over all three forms, leaving only the invocation to the live run.
function Get-ScannerRelPath {
    param([string]$File, [string]$PackDir)
    $norm = ($File -replace '\\', '/')
    $root = ($PackDir -replace '\\', '/').TrimEnd('/')
    if ($norm -like "$root/*") { $norm = $norm.Substring($root.Length + 1) }
    return $norm.TrimStart('.', '/')
}

function Test-IsRegisteredFixture {
    param([string]$File, [string]$PackDir, [string[]]$FixturePaths)
    $rel = Get-ScannerRelPath -File $File -PackDir $PackDir
    foreach ($f in @($FixturePaths)) {
        if ($rel -eq $f -or $rel.EndsWith("/$f")) { return $true }
    }
    return $false
}

function Invoke-GitleaksScan {
    param([hashtable]$Stage, [string]$GitleaksExe, [string[]]$FixturePaths)

    $findings = [System.Collections.Generic.List[string]]::new()

    $exe = $GitleaksExe
    if ([string]::IsNullOrWhiteSpace($exe)) {
        $cmd = Get-Command 'gitleaks' -ErrorAction SilentlyContinue
        if ($cmd) { $exe = $cmd.Source }
    }
    if ([string]::IsNullOrWhiteSpace($exe) -or -not (Test-Path -LiteralPath $exe)) {
        # Requested and unavailable is a failure, not a skip. -Gitleaks is the caller saying the
        # belt is required for this run; answering "there is no belt" with a pass is the exact
        # state the exit contract forbids.
        $findings.Add('-Gitleaks was requested and no executable could be resolved -- install it or pass -GitleaksPath; a requested scan that did not happen is not a pass')
        return @{ Findings = $findings; Note = 'unresolvable' }
    }

    # POSITIVE CONTROL FIRST. A scanner that cannot read its target reports "no leaks found" and
    # exits 0 in about 14 milliseconds -- a false pass, which is worse than no scan. So the run
    # starts by asking it to find something planted, and a clean answer THERE invalidates the
    # clean answer everywhere.
    $probe = Join-Path ([System.IO.Path]::GetTempPath()) ("share-pack-gitleaks-probe-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $null = New-Item -ItemType Directory -Path $probe -Force
    [System.IO.File]::WriteAllText((Join-Path $probe 'planted.txt'), (($script:PlantedShapes -join "`n") + "`n"))
    $probeReport = Join-Path $probe 'report.json'
    $null = & $exe detect --no-git --redact --source $probe --report-format json --report-path $probeReport --exit-code 7 2>&1
    $probeCode = $LASTEXITCODE
    Remove-Item -LiteralPath $probe -Recurse -Force -ErrorAction SilentlyContinue
    if ($probeCode -ne 7) {
        $findings.Add("the gitleaks positive control did not fire (exit $probeCode against a directory holding two planted credentials) -- the scanner is not reading its target, so its clean verdict on the pack means nothing")
        return @{ Findings = $findings; Note = 'positive control failed' }
    }

    $report = Join-Path ([System.IO.Path]::GetTempPath()) ("share-pack-gitleaks-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".json")
    # --no-git is explicit: the pack is a directory, not a repository, and without it gitleaks looks
    # for history, fails to find any, and says clean.
    $null = & $exe detect --no-git --redact --source $Stage.PackDir --report-format json --report-path $report --exit-code 7 2>&1
    $code = $LASTEXITCODE

    $count = 0
    if (Test-Path -LiteralPath $report) {
        $json = [System.IO.File]::ReadAllText($report)
        if (-not [string]::IsNullOrWhiteSpace($json)) {
            $items = @($json | ConvertFrom-Json)
            foreach ($it in $items) {
                if (Test-IsRegisteredFixture -File $it.File -PackDir $Stage.PackDir -FixturePaths $FixturePaths) { continue }
                $rel = Get-ScannerRelPath -File $it.File -PackDir $Stage.PackDir
                $count++
                # gitleaks ran with --redact, and this message adds no value of its own either.
                $findings.Add("$rel`:$($it.StartLine)  gitleaks rule '$($it.RuleID)' -- value withheld deliberately")
            }
        }
        Remove-Item -LiteralPath $report -Force -ErrorAction SilentlyContinue
    }
    elseif ($code -ne 0 -and $code -ne 7) {
        $findings.Add("gitleaks exited $code and wrote no report -- the scan did not complete and its silence is not a pass")
    }

    return @{ Findings = $findings; Note = "ran, $count unregistered finding(s)" }
}

# ── SELF-TEST ───────────────────────────────────────────────────────────────────
# Negative controls. The point is not that the gate passes on a clean tree -- it is that it FAILS
# on each specific defect, including the ones that look like success: an empty scope, a report
# nobody could read, an exit code that disagrees with its own table, and a registry entry that has
# outlived the finding it excused.

function Invoke-PackSelfTest {
    param([string]$RegistryPath, [string]$GateDir)

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("share-pack-selftest-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $null = New-Item -ItemType Directory -Path $tmp -Force
    $failures = 0

    function Assert-Case {
        param([string]$Name, [string]$Expected, [string]$Actual)
        $ok = $Expected -eq $Actual
        $mark = if ($ok) { 'ok  ' } else { 'FAIL' }
        Write-Host ("  [{0}] {1,-58} expected {2}, got {3}" -f $mark, $Name, $Expected, $Actual)
        return $ok
    }

    function New-Stub {
        param([string]$Dir, [string]$Name, [string]$Table, [int]$Code, [switch]$NoReport)
        # A stand-in for the called gate: writes a report table and exits with a chosen code, so
        # the caller's own assertions can be driven into every shape a real gate could produce.
        $body = if ($NoReport) {
            "param([string]`$DocRoot,[string]`$RepoRoot,[string]`$GateDir,[string]`$ReportPath)`nexit $Code`n"
        }
        else {
            "param([string]`$DocRoot,[string]`$RepoRoot,[string]`$GateDir,[string]`$ReportPath)`n" +
            "[System.IO.File]::WriteAllText(`$ReportPath, @'`n$Table`n'@)`nexit $Code`n"
        }
        $p = Join-Path $Dir $Name
        [System.IO.File]::WriteAllText($p, $body)
        return $p
    }

    $goodTable = @'

PRACTICE CLAIM GATE -- x
==============================================================================
Citations      PASS              1 candidate(s)
Redaction      PASS              1 candidate(s)
==============================================================================
RESULT: PASS -- every check ran and passed
'@

    # THE SAME TABLE WITH THE PATTERN-TABLE FIELD PRESENT. $goodTable deliberately keeps its bare
    # Redaction row, because "the note does not say which table it loaded" is itself a control below;
    # this is the shape a healthy content run produces, and it is what the PASS controls are written
    # against so that a pass here means the whole chain agreed rather than that nothing objected.
    $realTable = $goodTable -replace 'Redaction      PASS              1 candidate\(s\)',
    'Redaction      PASS              1 candidate(s)  -- table=redaction-classes.json -- 5 class(es), each verified against its own example'
    $exampleTable = $goodTable -replace 'Redaction      PASS              1 candidate\(s\)',
    'Redaction      PASS              1 candidate(s)  -- table=redaction-classes.example.json -- PATTERNS FROM THE GENERIC STARTER TABLE, NOT this tree''s own'
    # The distribution run: one row, because it is invoked with -Only Redaction.
    $distExample = @'

PRACTICE CLAIM GATE -- x
SCOPED RUN (-Only): Redaction. The other 5 check(s) were not applicable to this root, not declined.
==============================================================================
Redaction      PASS              1 candidate(s)  -- table=redaction-classes.example.json -- PATTERNS FROM THE GENERIC STARTER TABLE
==============================================================================
RESULT: PASS -- every check IN SCOPE ran and passed (Redaction)
'@
    $distReal = $distExample -replace 'redaction-classes\.example\.json', 'redaction-classes.json'

    Write-Host "`nSELF-TEST -- negative controls" -ForegroundColor Cyan

    try {
        $scope = @{
            Extensions = @('.md'); ExcludeRegex = '[\\/](__pycache__)[\\/]'; SelfNames = @('Test-PracticeClaims.ps1')
            CheckNames = @('Citations', 'Redaction'); ValidateSetNames = @('Citations', 'Redaction')
            RealTable  = 'redaction-classes.json'; ExampleTable = 'redaction-classes.example.json'
            Errors     = [System.Collections.Generic.List[string]]::new()
        }
        $emptyReg = @{
            bundle_boundary = @{ checks = @(); citations = @() }
            unscanned       = @()
            secret_fixtures = @()
        }

        # ── the called gate's own report ──────────────────────────────────────────
        # 1. no report at all: the gate may have exited 0, and this caller has measured nothing.
        $run = @{ ExitCode = 0; ReportText = ''; Rows = @(); Stdout = ''; ReportPath = '' }
        $res = Test-DelegateRun -Run $run -Scope $scope
        if (-not (Assert-Case 'a gate that wrote no report is INCONCLUSIVE, not PASS' 'INCONCLUSIVE' $res.Status)) { $failures++ }

        # 2. a report whose shape this parser cannot read -- coverage unknown, not clean.
        $run = @{ ExitCode = 0; ReportText = "some other tool's output`n"; Rows = (ConvertFrom-DelegateReport -Text "some other tool's output`n"); Stdout = ''; ReportPath = '' }
        $res = Test-DelegateRun -Run $run -Scope $scope
        if (-not (Assert-Case 'an unreadable report is INCONCLUSIVE' 'INCONCLUSIVE' $res.Status)) { $failures++ }

        # 3. exit 0 over a table containing a failure. The shape a caller trusts blindly.
        $t = $goodTable -replace 'Redaction      PASS', 'Redaction      FAIL'
        $run = @{ ExitCode = 0; ReportText = $t; Rows = (ConvertFrom-DelegateReport -Text $t); Stdout = ''; ReportPath = '' }
        $res = Test-DelegateRun -Run $run -Scope $scope
        if (-not (Assert-Case 'exit 0 with a FAIL row is caught' 'FAIL' $res.Status)) { $failures++ }

        # 4. ...and the other direction: a non-zero exit over an all-PASS table is equally a
        #    disagreement, and reading only the table would have called it clean.
        $run = @{ ExitCode = 1; ReportText = $goodTable; Rows = (ConvertFrom-DelegateReport -Text $goodTable); Stdout = ''; ReportPath = '' }
        $res = Test-DelegateRun -Run $run -Scope $scope
        if (-not (Assert-Case 'a non-zero exit over an all-PASS table is caught' 'FAIL' $res.Status)) { $failures++ }

        # 5. a dispatched check missing from the report -- coverage vanishing without failing.
        $t = $goodTable -replace '(?m)^Citations.*\r?\n', ''
        $run = @{ ExitCode = 0; ReportText = $t; Rows = (ConvertFrom-DelegateReport -Text $t); Stdout = ''; ReportPath = '' }
        $res = Test-DelegateRun -Run $run -Scope $scope
        if (-not (Assert-Case 'a dispatched check absent from the report fails' 'FAIL' $res.Status)) { $failures++ }

        # 6. an unknown status token: the boundary that holds this file's copy of the outcome
        #    vocabulary to the original.
        $t = $goodTable -replace 'Redaction      PASS', 'Redaction      CLEANISH'
        $run = @{ ExitCode = 0; ReportText = $t; Rows = (ConvertFrom-DelegateReport -Text $t); Stdout = ''; ReportPath = '' }
        $res = Test-DelegateRun -Run $run -Scope $scope
        if (-not (Assert-Case 'a status outside the shared vocabulary fails' 'FAIL' $res.Status)) { $failures++ }

        # 7. the two lists inside the called gate disagreeing with each other.
        $badScope = @{
            Extensions = @('.md'); ExcludeRegex = ''; SelfNames = @('x')
            CheckNames = @('Citations', 'Redaction'); ValidateSetNames = @('Citations', 'Redaction', 'Ghost')
            RealTable  = 'redaction-classes.json'; ExampleTable = 'redaction-classes.example.json'
            Errors     = [System.Collections.Generic.List[string]]::new()
        }
        $run = @{ ExitCode = 0; ReportText = $goodTable; Rows = (ConvertFrom-DelegateReport -Text $goodTable); Stdout = ''; ReportPath = '' }
        $res = Test-DelegateRun -Run $run -Scope $badScope
        if (-not (Assert-Case 'a check in the gate''s ValidateSet that nothing dispatches fails' 'FAIL' $res.Status)) { $failures++ }

        # 8. an unparseable scan scope must make this INCONCLUSIVE rather than let it compare
        #    against a hardcoded list. The parse failing loudly is the design.
        $errScope = @{
            Extensions = @(); ExcludeRegex = ''; SelfNames = @(); CheckNames = @(); ValidateSetNames = @()
            RealTable  = ''; ExampleTable = ''
            Errors     = [System.Collections.Generic.List[string]]::new()
        }
        $errScope.Errors.Add('cannot find the redaction check''s -Extensions list')
        $run = @{ ExitCode = 0; ReportText = $goodTable; Rows = (ConvertFrom-DelegateReport -Text $goodTable); Stdout = ''; ReportPath = '' }
        $res = Test-DelegateRun -Run $run -Scope $errScope
        if (-not (Assert-Case 'an unparseable gate scope fails rather than passing' 'FAIL' $res.Status)) { $failures++ }

        # ── WHICH PATTERN TABLE THE CONTENT RUN USED ──────────────────────────────
        # THE CONTROL THIS WHOLE BRANCH TURNS ON. Every one of these runs is otherwise flawless: a
        # parseable report, every dispatched check present, exit code agreeing with the table, the
        # file counts reconciling. The only thing wrong with the second one is that the patterns were
        # fictional -- and for one revision of this file that produced "RESULT: PASS -- every check
        # ran and passed" with the downgrade recorded nowhere in the output.
        $mk = {
            param($T, $Code)
            @{ ExitCode = $Code; ReportText = $T; Rows = (ConvertFrom-DelegateReport -Text $T); Stdout = ''; ReportPath = '' }
        }
        $res = Test-DelegateRun -Run (& $mk $realTable 0) -Scope $scope -DistRun (& $mk $distExample 0)
        if (-not (Assert-Case 'a content run on the REAL table passes' 'PASS' $res.Status)) { $failures++ }
        if (-not (Assert-Case '...and the note names the table it scanned with' 'True' ($res.Note -match 'redaction-classes\.json').ToString())) { $failures++ }

        $res = Test-DelegateRun -Run (& $mk $exampleTable 0) -Scope $scope -DistRun (& $mk $distExample 0)
        if (-not (Assert-Case 'a content run on the EXAMPLE table FAILS, never certifies' 'FAIL' $res.Status)) { $failures++ }
        if (-not (Assert-Case '...and the finding says the pack was not examined' 'True' (@($res.Findings | Where-Object { $_ -match 'has NOT been examined' }).Count -gt 0).ToString())) { $failures++ }

        # No field at all: unknown strength, which must be treated as unusable rather than as
        # probably-fine. This is why $goodTable's Redaction row was left bare.
        $res = Test-DelegateRun -Run (& $mk $goodTable 0) -Scope $scope -DistRun (& $mk $distExample 0)
        if (-not (Assert-Case 'a run that does not name its pattern table fails' 'FAIL' $res.Status)) { $failures++ }

        # A table this wrapper cannot classify is not a third acceptable answer.
        $thirdTable = $goodTable -replace 'Redaction      PASS              1 candidate\(s\)',
        'Redaction      PASS              1 candidate(s)  -- table=someone-elses-classes.json -- 5 class(es)'
        $res = Test-DelegateRun -Run (& $mk $thirdTable 0) -Scope $scope -DistRun (& $mk $distExample 0)
        if (-not (Assert-Case 'a run on an unrecognised pattern table fails' 'FAIL' $res.Status)) { $failures++ }

        # ── THE DISTRIBUTION RUN ──────────────────────────────────────────────────
        # Independent of the hold list, which is the point: asking the hold list whether the hold list
        # worked proves nothing. If the gate can load the real table from INSIDE the pack, the real
        # table shipped, whatever the hold list believes.
        $res = Test-DelegateRun -Run (& $mk $realTable 0) -Scope $scope -DistRun (& $mk $distReal 0)
        if (-not (Assert-Case 'the real table reachable from inside the pack FAILS' 'FAIL' $res.Status)) { $failures++ }
        if (-not (Assert-Case '...and says so as a shipped table, not as a scan result' 'True' (@($res.Findings | Where-Object { $_ -match 'FROM INSIDE THE PACK' }).Count -gt 0).ToString())) { $failures++ }

        $res = Test-DelegateRun -Run (& $mk $realTable 0) -Scope $scope -DistRun @{ ExitCode = 1; ReportText = ''; Rows = @(); Stdout = ''; ReportPath = '' }
        if (-not (Assert-Case 'a distribution run that wrote no report fails' 'FAIL' $res.Status)) { $failures++ }

        $distFail = $distExample -replace 'Redaction      PASS', 'Redaction      FAIL'
        $res = Test-DelegateRun -Run (& $mk $realTable 0) -Scope $scope -DistRun (& $mk $distFail 1)
        if (-not (Assert-Case 'a distribution run whose own gate goes red fails' 'FAIL' $res.Status)) { $failures++ }

        # ── the bundle boundary registry ──────────────────────────────────────────
        $citeTable = @'

PRACTICE CLAIM GATE -- x
==============================================================================
Citations      FAIL              1 candidate(s)
                 - tools/a.md:12  cites 'skills/x/SKILL.md' -- does not resolve, and is not registered in external-citations.json
Redaction      PASS              1 candidate(s)
==============================================================================
RESULT: FAIL -- 1 check(s) failed or measured nothing
'@
        $run = @{ ExitCode = 1; ReportText = $citeTable; Rows = (ConvertFrom-DelegateReport -Text $citeTable); Stdout = ''; ReportPath = '' }
        $res = Test-BundleBoundary -Run $run -Registry $emptyReg
        if (-not (Assert-Case 'an unregistered dangling citation fails' 'FAIL' $res.Status)) { $failures++ }

        $reg = @{
            bundle_boundary = @{ checks = @(); citations = @(@{ document = 'tools/a.md'; token = 'skills/x/SKILL.md'; reason = 'self-test fixture' }) }
            unscanned       = @(); secret_fixtures = @()
        }
        $res = Test-BundleBoundary -Run $run -Registry $reg
        if (-not (Assert-Case 'a registered dangling citation passes' 'PASS' $res.Status)) { $failures++ }

        $reg.bundle_boundary.citations = @(@{ document = 'tools/a.md'; token = 'skills/x/SKILL.md' })
        $res = Test-BundleBoundary -Run $run -Registry $reg
        if (-not (Assert-Case 'a boundary entry with no reason fails' 'FAIL' $res.Status)) { $failures++ }

        # the quiet direction: somebody fixed the citation and the entry now covers nothing.
        $reg.bundle_boundary.citations = @(
            @{ document = 'tools/a.md'; token = 'skills/x/SKILL.md'; reason = 'self-test fixture' },
            @{ document = 'tools/a.md'; token = 'skills/gone/SKILL.md'; reason = 'self-test fixture' })
        $res = Test-BundleBoundary -Run $run -Registry $reg
        if (-not (Assert-Case 'a boundary entry the bundle run no longer reports fails' 'FAIL' $res.Status)) { $failures++ }

        # a whole check registered as not applying -- and only for the status registered.
        $skipTable = @'

PRACTICE CLAIM GATE -- x
==============================================================================
Citations      PASS              1 candidate(s)
Assertions     SKIPPED           0 candidate(s)  -- none of the 2 scoped document(s) is in this tree
==============================================================================
RESULT: SKIPPED -- 1 check(s) deliberately not run
'@
        $run2 = @{ ExitCode = 2; ReportText = $skipTable; Rows = (ConvertFrom-DelegateReport -Text $skipTable); Stdout = ''; ReportPath = '' }
        $reg2 = @{
            bundle_boundary = @{ checks = @(@{ check = 'Assertions'; statuses = @('SKIPPED'); reason = 'self-test fixture' }); citations = @() }
            unscanned       = @(); secret_fixtures = @()
        }
        $res = Test-BundleBoundary -Run $run2 -Registry $reg2
        if (-not (Assert-Case 'a check registered as not applying to a bundle passes' 'PASS' $res.Status)) { $failures++ }

        $t = $skipTable -replace 'Assertions     SKIPPED', 'Assertions     FAIL   '
        $run3 = @{ ExitCode = 1; ReportText = $t; Rows = (ConvertFrom-DelegateReport -Text $t); Stdout = ''; ReportPath = '' }
        $res = Test-BundleBoundary -Run $run3 -Registry $reg2
        if (-not (Assert-Case 'a registered check deviating a DIFFERENT way fails' 'FAIL' $res.Status)) { $failures++ }

        $reg2.bundle_boundary.checks = @(@{ check = 'Figures'; statuses = @('SKIPPED'); reason = 'self-test fixture' })
        $res = Test-BundleBoundary -Run $run2 -Registry $reg2
        if (-not (Assert-Case 'a registered check that now passes fails as stale' 'FAIL' $res.Status)) { $failures++ }

        # ── coverage ──────────────────────────────────────────────────────────────
        $pack = Join-Path $tmp 'pack'; $null = New-Item -ItemType Directory -Path (Join-Path $pack 'tools') -Force
        [System.IO.File]::WriteAllText((Join-Path $pack 'tools/a.md'), "hello`n")
        [System.IO.File]::WriteAllText((Join-Path $pack 'tools/b.docx'), "not really a docx`n")
        $stage = @{ Root = $pack; PackDir = (Join-Path $pack 'tools'); Prefix = 'tools'; RelPaths = @('a.md', 'b.docx'); Excluded = 0 }
        $oneScanned = @{ ExitCode = 0; ReportText = ''; Stdout = ''; ReportPath = ''
            Rows                  = @([pscustomobject]@{ Name = 'Redaction'; Status = 'PASS'; Candidates = 1; Note = ''; Known = $true; Findings = [System.Collections.Generic.List[string]]::new() })
        }
        $res = Test-PackCoverage -Stage $stage -Run $oneScanned -Scope $scope -Registry $emptyReg
        if (-not (Assert-Case 'a file outside the redaction scan and unregistered fails' 'FAIL' $res.Status)) { $failures++ }

        $reg3 = @{ bundle_boundary = @{ checks = @(); citations = @() }; secret_fixtures = @()
            unscanned              = @(@{ path = 'b.docx'; reason = 'self-test fixture' })
        }
        $res = Test-PackCoverage -Stage $stage -Run $oneScanned -Scope $scope -Registry $reg3
        if (-not (Assert-Case 'a registered unscanned file passes' 'PASS' $res.Status)) { $failures++ }

        $reg3.unscanned = @(@{ path = 'b.docx'; reason = 'self-test fixture' }, @{ path = 'gone.bin'; reason = 'self-test fixture' })
        $res = Test-PackCoverage -Stage $stage -Run $oneScanned -Scope $scope -Registry $reg3
        if (-not (Assert-Case 'an unscanned entry for a file that is gone fails' 'FAIL' $res.Status)) { $failures++ }

        $reg3.unscanned = @(@{ path = 'a.md'; reason = 'self-test fixture' })
        $res = Test-PackCoverage -Stage $stage -Run $oneScanned -Scope $scope -Registry $reg3
        if (-not (Assert-Case 'an unscanned entry for a file now scanned fails' 'FAIL' $res.Status)) { $failures++ }

        # the two-enumerations assertion, in both failure directions.
        $reg4 = @{ bundle_boundary = @{ checks = @(); citations = @() }; secret_fixtures = @()
            unscanned              = @(@{ path = 'b.docx'; reason = 'self-test fixture' })
        }
        $twoScanned = @{ ExitCode = 0; ReportText = ''; Stdout = ''; ReportPath = ''
            Rows                  = @([pscustomobject]@{ Name = 'Redaction'; Status = 'PASS'; Candidates = 2; Note = ''; Known = $true; Findings = [System.Collections.Generic.List[string]]::new() })
        }
        $res = Test-PackCoverage -Stage $stage -Run $twoScanned -Scope $scope -Registry $reg4
        if (-not (Assert-Case 'a candidate count that disagrees with the staged tree fails' 'FAIL' $res.Status)) { $failures++ }

        $skippedRedaction = @{ ExitCode = 2; ReportText = ''; Stdout = ''; ReportPath = ''
            Rows                        = @([pscustomobject]@{ Name = 'Redaction'; Status = 'SKIPPED'; Candidates = 0; Note = ''; Known = $true; Findings = [System.Collections.Generic.List[string]]::new() })
        }
        $res = Test-PackCoverage -Stage $stage -Run $skippedRedaction -Scope $scope -Registry $reg4
        if (-not (Assert-Case 'a SKIPPED redaction scan cannot certify a pack' 'FAIL' $res.Status)) { $failures++ }

        $emptyStage = @{ Root = $pack; PackDir = (Join-Path $pack 'tools'); Prefix = 'tools'; RelPaths = @(); Excluded = 0 }
        $res = Test-PackCoverage -Stage $emptyStage -Run $oneScanned -Scope $scope -Registry $emptyReg
        if (-not (Assert-Case 'an empty pack is INCONCLUSIVE, not PASS' 'INCONCLUSIVE' $res.Status)) { $failures++ }

        # ── THE NOTE HAS TO ADD UP ────────────────────────────────────────────────
        # A check whose whole argument is "two independent enumerations of one scope agree" printed a
        # summary line that did not reconcile -- 87 staged, 83 scanned, 0 outside, 2 excluded, four
        # files named nowhere. The arithmetic is now asserted rather than eyeballed: the numbers are
        # read back OUT of the note, so a note that stops matching the counts it was built from fails
        # here rather than being read past by whoever notices it does not add up.
        $sumStage = @{ Root = $pack; PackDir = (Join-Path $pack 'tools'); Prefix = 'tools'
            RelPaths          = @('a.md', 'b.docx', 'Test-PracticeClaims.ps1', 'notes.md'); Excluded = 2
            HeldPaths         = @('x/held.json'); HeldBack = 1; HoldTable = 'hold-classes.json'
        }
        $sumScope = @{
            Extensions = @('.md', '.ps1'); ExcludeRegex = ''; SelfNames = @('Test-PracticeClaims.ps1')
            CheckNames = @('Citations', 'Redaction'); ValidateSetNames = @('Citations', 'Redaction')
            RealTable  = 'redaction-classes.json'; ExampleTable = 'redaction-classes.example.json'
            Errors     = [System.Collections.Generic.List[string]]::new()
        }
        $sumRun = @{ ExitCode = 0; ReportText = ''; Stdout = ''; ReportPath = ''
            Rows              = @([pscustomobject]@{ Name = 'Redaction'; Status = 'PASS'; Candidates = 2; Note = ''; Known = $true; Findings = [System.Collections.Generic.List[string]]::new() })
        }
        $sumReg = @{ bundle_boundary = @{ checks = @(); citations = @() }; secret_fixtures = @()
            unscanned              = @(@{ path = 'b.docx'; reason = 'self-test fixture' })
        }
        $res = Test-PackCoverage -Stage $sumStage -Run $sumRun -Scope $sumScope -Registry $sumReg
        if (-not (Assert-Case 'a mixed tree with a self-exempt file passes' 'PASS' $res.Status)) { $failures++ }
        $m = [regex]::Match($res.Note, '^(?<staged>\d+) staged file\(s\) = (?<scan>\d+) scanned \+ (?<out>\d+) outside the redaction scan \+ (?<self>\d+) self-exempt')
        if (-not (Assert-Case 'the coverage note is in the reconcilable form' 'True' "$($m.Success)")) { $failures++ }
        if ($m.Success) {
            $lhs = [int]$m.Groups['staged'].Value
            $rhs = [int]$m.Groups['scan'].Value + [int]$m.Groups['out'].Value + [int]$m.Groups['self'].Value
            if (-not (Assert-Case '...and the three terms sum to the staged count' "$lhs" "$rhs")) { $failures++ }
            if (-not (Assert-Case '...with the self-exempt term actually populated' '1' "$($m.Groups['self'].Value)")) { $failures++ }
        }
        # The staging statistics are reported, and reported OUTSIDE the sum: they describe files that
        # were never staged, so a line that put them inside the partition would be claiming they were.
        if (-not (Assert-Case 'the staging exclusions are reported separately' 'True' ($res.Note -match 'separately, staging withheld 2 as non-content and 1 as hold-listed').ToString())) { $failures++ }
        if (-not (Assert-Case '...and are NOT terms in the partition' 'False' ($res.Note -match '\+ 2 excluded').ToString())) { $failures++ }

        # ── the hold list ─────────────────────────────────────────────────────────
        # THE LIVE TABLE, loaded rather than mocked. It moved out of this file into
        # practice-gate/hold-classes.json on 2026-08-19, so these controls now also stand for the
        # loader: a table that failed to load produces an empty class list, and an empty class list
        # forbids nothing while looking exactly like a clean pack.
        $liveHold = $null
        if (Test-Path -LiteralPath $GateDir -PathType Container) {
            try { $liveHold = Import-HoldClasses -GateDir $GateDir } catch { $liveHold = $null }
        }
        if ($null -eq $liveHold) {
            Write-Host "  [SKIP] no hold class table under $GateDir; the hold-list controls did not run" -ForegroundColor Yellow
            $failures++   # controls that did not run are not controls that passed
            $liveHoldClasses = @()
        }
        else {
            $liveHoldClasses = @($liveHold.Classes)
            if (-not (Assert-Case 'the live hold table is the real one, not the starter' 'real' "$($liveHold.Source)")) { $failures++ }
        }

        $holdStage = @{ Root = $pack; PackDir = (Join-Path $pack 'tools'); Prefix = 'tools'
            RelPaths            = @('permissions/settings.local.json'); Excluded = 0
        }
        $res = Test-HoldList -Stage $holdStage -Classes $liveHoldClasses -TableName 'hold-classes.json'
        if (-not (Assert-Case 'a held asset in the tree fails' 'FAIL' $res.Status)) { $failures++ }

        $cleanStage = @{ Root = $pack; PackDir = (Join-Path $pack 'tools'); Prefix = 'tools'
            RelPaths             = @('permissions/settings.template.json', 'a.md'); Excluded = 0
        }
        $res = Test-HoldList -Stage $cleanStage -Classes $liveHoldClasses -TableName 'hold-classes.json'
        if (-not (Assert-Case 'the near-miss the pack does ship passes' 'PASS' $res.Status)) { $failures++ }

        # THE PAIR THIS BRANCH ADDED, and the reason the counter-example is not decoration: the two
        # names differ by one word and carry opposite verdicts. Held, the table is withheld from every
        # pack; shipped, the starter table is what lets a recipient stand the gate up at all.
        $tableStage = @{ Root = $pack; PackDir = (Join-Path $pack 'tools'); Prefix = 'tools'
            RelPaths            = @('practice-gate/redaction-classes.json'); Excluded = 0
        }
        $res = Test-HoldList -Stage $tableStage -Classes $liveHoldClasses -TableName 'hold-classes.json'
        if (-not (Assert-Case 'the REAL redaction table in the tree fails' 'FAIL' $res.Status)) { $failures++ }
        $tableStage.RelPaths = @('practice-gate/redaction-classes.example.json')
        $res = Test-HoldList -Stage $tableStage -Classes $liveHoldClasses -TableName 'hold-classes.json'
        if (-not (Assert-Case '...and the .example table beside it still ships' 'PASS' $res.Status)) { $failures++ }
        # ...and the same pair for the hold table itself. A hold list that does not hold itself back
        # is the one asset on the list whose absence nobody would notice.
        $tableStage.RelPaths = @('practice-gate/hold-classes.json')
        $res = Test-HoldList -Stage $tableStage -Classes $liveHoldClasses -TableName 'hold-classes.json'
        if (-not (Assert-Case 'the REAL hold table in the tree fails' 'FAIL' $res.Status)) { $failures++ }
        $tableStage.RelPaths = @('practice-gate/hold-classes.example.json')
        $res = Test-HoldList -Stage $tableStage -Classes $liveHoldClasses -TableName 'hold-classes.json'
        if (-not (Assert-Case '...and the .example table beside it still ships' 'PASS' $res.Status)) { $failures++ }

        # THE PATTERN TABLE ITSELF: a class that has stopped matching its own example forbids
        # nothing, and looks exactly like a clean tree.
        $broken = @(@{ name = 'broken'; pattern = '(?i)(^|/)nothing-matches-this$'; example = 'permissions/settings.local.json'; reason = 'self-test fixture' })
        $res = Test-HoldList -Stage $cleanStage -Classes $broken -TableName 'fixture.json'
        if (-not (Assert-Case 'a hold class that no longer matches its example fails' 'FAIL' $res.Status)) { $failures++ }

        $tooBroad = @(@{ name = 'too broad'; pattern = '(?i)settings.*\.json$'; example = 'permissions/settings.local.json'; counter_example = 'permissions/settings.template.json'; reason = 'self-test fixture' })
        $res = Test-HoldList -Stage $cleanStage -Classes $tooBroad -TableName 'fixture.json'
        if (-not (Assert-Case 'a hold class matching its counter-example fails' 'FAIL' $res.Status)) { $failures++ }

        $noReason = @(@{ name = 'unexplained'; pattern = '(?i)(^|/)settings\.local\.json$'; example = 'permissions/settings.local.json' })
        $res = Test-HoldList -Stage $cleanStage -Classes $noReason -TableName 'fixture.json'
        if (-not (Assert-Case 'a hold class with no reason fails' 'FAIL' $res.Status)) { $failures++ }

        $res = Test-HoldList -Stage $cleanStage -Classes @() -TableName 'fixture.json'
        if (-not (Assert-Case 'an empty hold list fails rather than passing' 'FAIL' $res.Status)) { $failures++ }

        $res = Test-HoldList -Stage $emptyStage -Classes $liveHoldClasses -TableName 'hold-classes.json'
        if (-not (Assert-Case 'an empty pack is INCONCLUSIVE for the hold list too' 'INCONCLUSIVE' $res.Status)) { $failures++ }

        # THE BUILDER'S SIDE OF IT, both directions. The builder reads this same table and withholds
        # instead of staging, so the two must agree -- and the way two readers of one table rot is
        # that neither is ever asked about the other.
        $goodHold = @(@{ name = 'held'; pattern = '(?i)(^|/)held\.json$'; example = 'x/held.json'; counter_example = 'x/held.example.json'; reason = 'self-test fixture' })
        $agreeStage = @{ Root = $pack; PackDir = (Join-Path $pack 'tools'); Prefix = 'tools'
            RelPaths           = @('a.md'); Excluded = 0
            HeldPaths          = @('x/held.json'); HeldBack = 1; HoldTable = 'fixture.json'
        }
        $res = Test-HoldList -Stage $agreeStage -Classes $goodHold -TableName 'fixture.json'
        if (-not (Assert-Case 'a withheld path this table holds passes' 'PASS' $res.Status)) { $failures++ }

        $agreeStage.HeldPaths = @('x/held.json', 'x/on-some-other-authority.txt')
        $res = Test-HoldList -Stage $agreeStage -Classes $goodHold -TableName 'fixture.json'
        if (-not (Assert-Case 'a withheld path NO class holds fails' 'FAIL' $res.Status)) { $failures++ }

        $agreeStage.HeldPaths = @('x/held.json')
        $agreeStage.HoldTable = 'some-other-table.json'
        $res = Test-HoldList -Stage $agreeStage -Classes $goodHold -TableName 'fixture.json'
        if (-not (Assert-Case 'builder and gate reading DIFFERENT tables fails' 'FAIL' $res.Status)) { $failures++ }

        # And the forward direction, which is the one the builder should have made impossible: a held
        # path that is in the tree anyway means the withholding did not happen.
        $agreeStage.HoldTable = 'fixture.json'
        $agreeStage.RelPaths = @('a.md', 'x/held.json')
        $agreeStage.HeldPaths = @()
        $res = Test-HoldList -Stage $agreeStage -Classes $goodHold -TableName 'fixture.json'
        if (-not (Assert-Case 'a held path staged anyway fails' 'FAIL' $res.Status)) { $failures++ }

        # ── loading the hold list, fail-closed ────────────────────────────────────
        $ht = Join-Path $tmp 'hold-tables'; $null = New-Item -ItemType Directory -Path $ht -Force
        $threw = 'no'
        try { $null = Import-HoldClasses -GateDir $ht } catch { $threw = 'yes' }
        if (-not (Assert-Case 'neither hold table present refuses rather than permitting all' 'yes' $threw)) { $failures++ }
        [System.IO.File]::WriteAllText((Join-Path $ht 'hold-classes.example.json'), '{"classes":[{"name":"x","pattern":"(^|/)x$","example":"x","reason":"fixture"}]}')
        $loaded = Import-HoldClasses -GateDir $ht
        if (-not (Assert-Case 'with only the starter table, the starter table is used' 'example' "$($loaded.Source)")) { $failures++ }
        if (-not (Assert-Case '...and it is NAMED, so the fallback is not silent' 'hold-classes.example.json' "$($loaded.File)")) { $failures++ }
        [System.IO.File]::WriteAllText((Join-Path $ht 'hold-classes.json'), '{"classes":[]}')
        $threw = 'no'
        try { $null = Import-HoldClasses -GateDir $ht } catch { $threw = 'yes' }
        if (-not (Assert-Case 'a hold table with zero classes refuses to load' 'yes' $threw)) { $failures++ }
        [System.IO.File]::WriteAllText((Join-Path $ht 'hold-classes.json'), '{"nope":[]}')
        $threw = 'no'
        try { $null = Import-HoldClasses -GateDir $ht } catch { $threw = 'yes' }
        if (-not (Assert-Case 'a hold table with no classes key refuses to load' 'yes' $threw)) { $failures++ }

        # ── THE PACK ROOT ─────────────────────────────────────────────────────────
        # The layer that had no check. Every control here is a defect that used to print a green line:
        # an identifier in NOTICE, a root file nothing declared, a class table that could not be
        # loaded, and an allowance that has outlived the sentence it was written for.
        #
        # THE SWEEP FIRST, ON ITS OWN. The per-class fixture control inside the check asserts that a
        # class fires when its own example is placed in a notice fixture -- which cannot fail on
        # account of the CLASS, since the injected line IS the example. What it can fail on is the
        # sweep: the line split, the case-sensitive [regex]::Match, the shape of what comes back. That
        # is the machinery the missing check was missing, so it gets its own controls.
        $swClass = @([pscustomobject]@{ Name = 'fixture org'; Pattern = 'ORGNAMEX'; Example = 'ORGNAMEX' })
        $swClean = @(Find-RootFileMatches -Text (Get-RootFileFixture) -Classes $swClass -Label 'NOTICE')
        if (-not (Assert-Case 'the sweep finds nothing in a de-branded fixture' '0' "$($swClean.Count)")) { $failures++ }
        $swDirty = @(Find-RootFileMatches -Text (Get-RootFileFixture -Injected 'Copyright 2026 ORGNAMEX') -Classes $swClass -Label 'NOTICE')
        if (-not (Assert-Case '...and finds an injected identifier in the same fixture' '1' "$($swDirty.Count)")) { $failures++ }
        if (-not (Assert-Case '...reporting the file it was given' 'NOTICE' "$(@($swDirty)[0].Path)")) { $failures++ }
        if (-not (Assert-Case '...the class that fired' 'fixture org' "$(@($swDirty)[0].Class)")) { $failures++ }
        if (-not (Assert-Case '...and the matched text, which a root-file finding must quote' 'ORGNAMEX' "$(@($swDirty)[0].Match)")) { $failures++ }
        # The line number, because a finding that cannot be located is a finding nobody acts on. The
        # injected line is the 8th of the fixture.
        if (-not (Assert-Case '...at the line it was on' '8' "$(@($swDirty)[0].Line)")) { $failures++ }
        # Case sensitivity: the delegated table has one deliberately case-SENSITIVE class, so a sweep
        # written with -match would report findings on ordinary prose. Asserted rather than assumed.
        $swCase = @(Find-RootFileMatches -Text (Get-RootFileFixture -Injected 'orgnamex in lower case') -Classes $swClass -Label 'NOTICE')
        if (-not (Assert-Case 'the sweep is case-sensitive, like the live scan' '0' "$($swCase.Count)")) { $failures++ }

        # A pack root to point the check at: the two licence files, a manifest, and a content tree.
        $rootPack = Join-Path $tmp 'rootpack'
        $null = New-Item -ItemType Directory -Path (Join-Path $rootPack 'tools') -Force
        [System.IO.File]::WriteAllText((Join-Path $rootPack 'tools/a.md'), "hello`n")
        $writeRoot = {
            param($Notice)
            [System.IO.File]::WriteAllText((Join-Path $rootPack 'LICENSE'), (Get-RootFileFixture))
            [System.IO.File]::WriteAllText((Join-Path $rootPack 'NOTICE'), (Get-RootFileFixture -Injected $Notice))
            [System.IO.File]::WriteAllText((Join-Path $rootPack 'share-pack-manifest.json'), "{ `"files`": [] }`n")
        }
        $rootStage = @{ Root = $rootPack; PackDir = (Join-Path $rootPack 'tools'); Prefix = 'tools'
            RelPaths           = @('a.md'); Excluded = 0
            RootPaths          = @('LICENSE', 'NOTICE'); ManifestName = 'share-pack-manifest.json'
        }
        $rootReg = @{ bundle_boundary = @{ checks = @(); citations = @() }; unscanned = @(); secret_fixtures = @()
            root_file_allowed        = @()
        }

        # 1. THE CLEAN CASE, and it is the one the branch had to be able to state: a de-branded
        #    NOTICE, scanned with the real classes, PASSES.
        & $writeRoot ''
        $res = Test-PackRootFiles -Stage $rootStage -Registry $rootReg -Scope $scope -GateDir $GateDir
        if (-not (Assert-Case 'a de-branded pack root passes' 'PASS' $res.Status)) { $failures++ }
        if (-not (Assert-Case '...having examined all three root files' '3' "$($res.Candidates)")) { $failures++ }
        if (-not (Assert-Case '...including the manifest, which no other check can reach' 'True' ($res.Note -match 'share-pack-manifest\.json').ToString())) { $failures++ }

        # 2. THE DEFECT. An organisation identifier back in NOTICE must FAIL and must NAME the file.
        #    The injected string is the live table's own example, so nothing matchable is written here
        #    and the control keeps working when the table is edited.
        $liveRedaction = $null
        try { $liveRedaction = Import-RootScanClasses -GateDir $GateDir -Scope $scope } catch { $liveRedaction = $null }
        if ($null -eq $liveRedaction -or $liveRedaction.Source -ne 'real') {
            Write-Host "  [SKIP] no real redaction table under $GateDir; the root-file defect controls did not run" -ForegroundColor Yellow
            $failures++   # controls that did not run are not controls that passed
        }
        else {
            $orgClass = @(@($liveRedaction.Classes) | Where-Object { [string]$_.name -eq 'organisation' })
            $probe = if ($orgClass.Count -gt 0) { [string]$orgClass[0].example } else { [string]@($liveRedaction.Classes)[0].example }
            & $writeRoot $probe
            $res = Test-PackRootFiles -Stage $rootStage -Registry $rootReg -Scope $scope -GateDir $GateDir
            if (-not (Assert-Case 'an organisation identifier in NOTICE fails' 'FAIL' $res.Status)) { $failures++ }
            if (-not (Assert-Case '...and the finding names NOTICE' 'True' (@($res.Findings | Where-Object { $_ -match '^NOTICE:' }).Count -gt 0).ToString())) { $failures++ }
            # QUOTED, deliberately, and the split from the Secrets check is the reason: nobody can
            # remove a word they were not told.
            if (-not (Assert-Case '...and quotes what it matched' 'True' (@($res.Findings | Where-Object { $_.Contains($probe) -or $_ -match "'[^']+'" }).Count -gt 0).ToString())) { $failures++ }

            # 3. ...and the same occurrence, REGISTERED, passes. The legal decision lands as an entry
            #    with a reason instead of as a silent pass.
            $matched = [regex]::Match(@($res.Findings | Where-Object { $_ -match '^NOTICE:' })[0], "-- '(?<m>[^']+)'")
            $rootReg.root_file_allowed = @(@{ path = 'NOTICE'; match = $matched.Groups['m'].Value; reason = 'self-test fixture' })
            $res = Test-PackRootFiles -Stage $rootStage -Registry $rootReg -Scope $scope -GateDir $GateDir
            if (-not (Assert-Case 'a registered legally-required occurrence passes' 'PASS' $res.Status)) { $failures++ }

            # 4. ...and stops passing the moment the reason is dropped.
            $rootReg.root_file_allowed = @(@{ path = 'NOTICE'; match = $matched.Groups['m'].Value })
            $res = Test-PackRootFiles -Stage $rootStage -Registry $rootReg -Scope $scope -GateDir $GateDir
            if (-not (Assert-Case 'an allowance with no reason fails' 'FAIL' $res.Status)) { $failures++ }
        }

        # 5. THE QUIET DIRECTION, which is the whole reason this list is checked both ways: somebody
        #    de-brands the notice and the allowance stays behind, permitting something nobody is
        #    checking for.
        & $writeRoot ''
        $rootReg.root_file_allowed = @(@{ path = 'NOTICE'; match = 'Some Organisation Ltd'; reason = 'self-test fixture' })
        $res = Test-PackRootFiles -Stage $rootStage -Registry $rootReg -Scope $scope -GateDir $GateDir
        if (-not (Assert-Case 'an allowance the scan no longer finds fails as stale' 'FAIL' $res.Status)) { $failures++ }
        if (-not (Assert-Case '...saying the entry should be struck' 'True' (@($res.Findings | Where-Object { $_ -match 'strike the entry' }).Count -gt 0).ToString())) { $failures++ }
        $rootReg.root_file_allowed = @()

        # 6. A registry with no allowance list at all. There would then be no way past this check
        #    except to weaken it, which is how an escape hatch becomes an edit to the gate.
        $noListReg = @{ bundle_boundary = @{ checks = @(); citations = @() }; unscanned = @(); secret_fixtures = @() }
        $res = Test-PackRootFiles -Stage $rootStage -Registry $noListReg -Scope $scope -GateDir $GateDir
        if (-not (Assert-Case 'a registry with no root_file_allowed list fails' 'FAIL' $res.Status)) { $failures++ }

        # 7. A ROOT FILE THIS CHECK DOES NOT KNOW ABOUT. Not a pass by not being enumerated -- that
        #    is exactly how LICENSE and NOTICE came to be unexamined for the life of the branch.
        [System.IO.File]::WriteAllText((Join-Path $rootPack 'EXTRA.txt'), "undeclared`n")
        $res = Test-PackRootFiles -Stage $rootStage -Registry $rootReg -Scope $scope -GateDir $GateDir
        if (-not (Assert-Case 'an undeclared file at the pack root fails' 'FAIL' $res.Status)) { $failures++ }
        if (-not (Assert-Case '...naming it' 'True' (@($res.Findings | Where-Object { $_ -match "'EXTRA\.txt'" }).Count -gt 0).ToString())) { $failures++ }
        Remove-Item -LiteralPath (Join-Path $rootPack 'EXTRA.txt') -Force

        # 8. ...and the other direction: declared and not there. A file that is absent cannot be
        #    scanned clean, and the pack is short of what it claims.
        $rootStage.RootPaths = @('LICENSE', 'NOTICE', 'GONE')
        $res = Test-PackRootFiles -Stage $rootStage -Registry $rootReg -Scope $scope -GateDir $GateDir
        if (-not (Assert-Case 'a declared root file that is missing fails' 'FAIL' $res.Status)) { $failures++ }
        $rootStage.RootPaths = @('LICENSE', 'NOTICE')

        # 9. FAIL CLOSED ON AN EMPTY ROOT LIST. A pack with a content prefix and nothing beside it
        #    means either the build omitted the licence files or this check is reading the wrong
        #    grain and they were counted as content. Both were live possibilities; both must be red.
        $emptyRootStage = @{ Root = $rootPack; PackDir = (Join-Path $rootPack 'tools'); Prefix = 'tools'
            RelPaths                = @('a.md'); Excluded = 0
            RootPaths               = @(); ManifestName = 'share-pack-manifest.json'
        }
        $res = Test-PackRootFiles -Stage $emptyRootStage -Registry $rootReg -Scope $scope -GateDir $GateDir
        if (-not (Assert-Case 'an empty root-file list fails rather than passing' 'FAIL' $res.Status)) { $failures++ }

        # 10. A staged description with no root-file list at all -- the shape this gate had before
        #     Invoke-PackBuilder kept the entries that do not carry the content prefix.
        $noRootStage = @{ Root = $rootPack; PackDir = (Join-Path $rootPack 'tools'); Prefix = 'tools'
            RelPaths           = @('a.md'); Excluded = 0
        }
        $res = Test-PackRootFiles -Stage $noRootStage -Registry $rootReg -Scope $scope -GateDir $GateDir
        if (-not (Assert-Case 'a stage carrying no root-file list fails' 'FAIL' $res.Status)) { $failures++ }

        # 11. AN UNREADABLE ROOT FILE. A binary beside the licence is not something to pass by
        #     skipping: the content tree's non-text files are each a registered decision, and the
        #     pack root has no such register.
        [System.IO.File]::WriteAllBytes((Join-Path $rootPack 'NOTICE'), [byte[]]@(0x41, 0x00, 0x42))
        $res = Test-PackRootFiles -Stage $rootStage -Registry $rootReg -Scope $scope -GateDir $GateDir
        if (-not (Assert-Case 'a root file that is not readable as text fails' 'FAIL' $res.Status)) { $failures++ }
        & $writeRoot ''

        # 12. NO CLASS TABLE AT ALL. The cardinal failure of this repository is a check that could not
        #     run reporting PASS, and a root-file scan with no patterns is exactly that shape.
        $rootGate = Join-Path $tmp 'root-gate'; $null = New-Item -ItemType Directory -Path $rootGate -Force
        $res = Test-PackRootFiles -Stage $rootStage -Registry $rootReg -Scope $scope -GateDir $rootGate
        if (-not (Assert-Case 'no resolvable class table fails rather than passing' 'FAIL' $res.Status)) { $failures++ }

        # 13. ONLY THE STARTER TABLE. It forbids placeholder vocabulary that appears in no real tree,
        #     so a NOTICE it clears has not been examined -- the same argument as the content run's,
        #     one layer out, and this is the layer a recipient opens first.
        [System.IO.File]::WriteAllText((Join-Path $rootGate 'redaction-classes.example.json'),
            '{"classes":[{"name":"placeholder org","pattern":"(?i)example-corp","example":"example-corp","reason":"fixture"}]}')
        $res = Test-PackRootFiles -Stage $rootStage -Registry $rootReg -Scope $scope -GateDir $rootGate
        if (-not (Assert-Case 'the starter table cannot certify the pack root' 'FAIL' $res.Status)) { $failures++ }
        if (-not (Assert-Case '...and says the patterns match nothing real' 'True' (@($res.Findings | Where-Object { $_ -match 'GENERIC STARTER' }).Count -gt 0).ToString())) { $failures++ }

        # 14. A CLASS THAT HAS STOPPED MATCHING ITS OWN EXAMPLE forbids nothing and looks exactly
        #     like a clean pack root.
        [System.IO.File]::WriteAllText((Join-Path $rootGate 'redaction-classes.json'),
            '{"classes":[{"name":"broken","pattern":"NOTHINGMATCHESTHIS","example":"ORGNAMEX","reason":"fixture"}]}')
        $res = Test-PackRootFiles -Stage $rootStage -Registry $rootReg -Scope $scope -GateDir $rootGate
        if (-not (Assert-Case 'a class that no longer matches its own example fails' 'FAIL' $res.Status)) { $failures++ }

        # 15. THE NEAR-MISS THAT MATTERS. `Copyright [yyyy] [name of copyright owner]` is what a
        #     de-branded LICENSE carries; it reads like an attribution and it is not one. A class
        #     broad enough to fire on it would fail every clean pack forever, so it fails HERE, once,
        #     with a message about the class rather than about the file.
        [System.IO.File]::WriteAllText((Join-Path $rootGate 'redaction-classes.json'),
            '{"classes":[{"name":"too broad","pattern":"(?i)copyright","example":"Copyright 2026 ORGNAMEX","reason":"fixture"}]}')
        $res = Test-PackRootFiles -Stage $rootStage -Registry $rootReg -Scope $scope -GateDir $rootGate
        if (-not (Assert-Case 'a class firing on an unfilled copyright line fails' 'FAIL' $res.Status)) { $failures++ }
        if (-not (Assert-Case '...as a pattern problem, not a pack problem' 'True' (@($res.Findings | Where-Object { $_ -match 'too broad for a root file' }).Count -gt 0).ToString())) { $failures++ }

        # 16. A table with an empty class list, and one that does not parse. Both permit everything
        #     while looking like a pack with nothing in it.
        [System.IO.File]::WriteAllText((Join-Path $rootGate 'redaction-classes.json'), '{"classes":[]}')
        $res = Test-PackRootFiles -Stage $rootStage -Registry $rootReg -Scope $scope -GateDir $rootGate
        if (-not (Assert-Case 'an empty class table fails' 'FAIL' $res.Status)) { $failures++ }
        [System.IO.File]::WriteAllText((Join-Path $rootGate 'redaction-classes.json'), '{ not json')
        $res = Test-PackRootFiles -Stage $rootStage -Registry $rootReg -Scope $scope -GateDir $rootGate
        if (-not (Assert-Case 'a class table that does not parse fails' 'FAIL' $res.Status)) { $failures++ }

        # 17. And the two table NAMES not parsing out of the delegated gate. Deliberately not falling
        #     back to a remembered filename: that is how the content run came to accept the
        #     placeholder table, one check over.
        $res = Test-PackRootFiles -Stage $rootStage -Registry $rootReg -Scope $errScope -GateDir $GateDir
        if (-not (Assert-Case 'unparseable table filenames fail rather than passing' 'FAIL' $res.Status)) { $failures++ }

        # ── THIS FILE'S OWN TWO LISTS ─────────────────────────────────────────────
        # The dispatch list and the -Skip ValidateSet must say the same thing. This gate makes exactly
        # this comparison against the gate it CALLS -- Get-DelegateScope parses both and fails on a
        # disagreement -- and made it against everyone but itself until RootFiles was added, which is
        # the shape of every exemption in this repository that turned out to be a hole. The set is
        # parsed back out of this file rather than restated, so the control cannot pass by agreeing
        # with a stale copy of itself.
        $ownRaw = [System.IO.File]::ReadAllText($PSCommandPath)
        $ownSets = @([regex]::Matches($ownRaw, "(?s)\[ValidateSet\((?<names>[^)]*)\)\]") | ForEach-Object {
                , @([regex]::Matches($_.Groups['names'].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
            })
        if (-not (Assert-Case 'this gate''s own -Skip ValidateSet parses' 'True' "$($ownSets.Count -gt 0)")) { $failures++ }
        if ($ownSets.Count -gt 0) {
            if (-not (Assert-Case '...and matches the dispatch list exactly' ($script:PackChecks -join '|') ($ownSets[0] -join '|'))) { $failures++ }
        }
        if (-not (Assert-Case 'the dispatch list names the root-file check' 'True' "$($script:PackChecks -contains 'RootFiles')")) { $failures++ }

        # ── secrets ───────────────────────────────────────────────────────────────
        $sec = Join-Path $tmp 'sec'; $null = New-Item -ItemType Directory -Path $sec -Force
        [System.IO.File]::WriteAllText((Join-Path $sec 'x.md'), "token: $($script:PlantedShapes[0])`n")
        $secStage = @{ Root = $tmp; PackDir = $sec; Prefix = ''; RelPaths = @('x.md'); Excluded = 0 }
        $res = Test-PackSecrets -Stage $secStage -Registry $emptyReg -Classes $script:SecretClasses
        if (-not (Assert-Case 'a planted credential is caught' 'FAIL' $res.Status)) { $failures++ }

        # THE VALUE MUST NOT BE IN THE FINDING. A report that quotes the credential has
        # manufactured the exposure it was hired to detect. Matched on the planted value itself, so
        # the control cannot pass by the finding format merely having changed.
        $leaked = @($res.Findings | Where-Object { $_.Contains($script:PlantedShapes[0]) }).Count
        if (-not (Assert-Case 'no finding quotes the matched value' '0' "$leaked")) { $failures++ }

        [System.IO.File]::WriteAllText((Join-Path $sec 'x.md'), "client_secret=`${env:THING}`npassword: <your-password-here>`n")
        $res = Test-PackSecrets -Stage $secStage -Registry $emptyReg -Classes $script:SecretClasses
        if (-not (Assert-Case 'placeholders and indirections do not fire' 'PASS' $res.Status)) { $failures++ }

        # a registered fixture is exempt...
        [System.IO.File]::WriteAllText((Join-Path $sec 'x.md'), "token: $($script:PlantedShapes[0])`n")
        $regF = @{ bundle_boundary = @{ checks = @(); citations = @() }; unscanned = @()
            secret_fixtures        = @(@{ path = 'x.md'; reason = 'self-test fixture' })
        }
        $res = Test-PackSecrets -Stage $secStage -Registry $regF -Classes $script:SecretClasses
        if (-not (Assert-Case 'a registered secret fixture is exempt' 'PASS' $res.Status)) { $failures++ }

        # ...and stops being exempt the moment it stops being a fixture.
        [System.IO.File]::WriteAllText((Join-Path $sec 'x.md'), "nothing interesting here`n")
        $res = Test-PackSecrets -Stage $secStage -Registry $regF -Classes $script:SecretClasses
        if (-not (Assert-Case 'a fixture entry whose file holds no secret shape fails' 'FAIL' $res.Status)) { $failures++ }

        $regF.secret_fixtures = @(@{ path = 'gone.md'; reason = 'self-test fixture' })
        $res = Test-PackSecrets -Stage $secStage -Registry $regF -Classes $script:SecretClasses
        if (-not (Assert-Case 'a fixture entry for a file that is gone fails' 'FAIL' $res.Status)) { $failures++ }

        $brokenClass = @([pscustomobject]@{ Class = 'broken'; Pattern = 'NEVERMATCHESANYTHING'; Example = $script:PlantedShapes[0] })
        $res = Test-PackSecrets -Stage $secStage -Registry $emptyReg -Classes $brokenClass
        if (-not (Assert-Case 'a secret class that no longer matches its example fails' 'FAIL' $res.Status)) { $failures++ }

        $res = Test-PackSecrets -Stage $secStage -Registry $emptyReg -Classes @()
        if (-not (Assert-Case 'an empty secret class list fails' 'FAIL' $res.Status)) { $failures++ }

        # ── the external scanner's path forms ─────────────────────────────────────
        # The one part of the gitleaks path that IS testable here, and the part that decides
        # whether a registered fixture is recognised. Three forms, because --no-git --source has
        # been observed reporting each of them, and a fixture the matcher does not recognise turns
        # into a finding against a file that is a fixture on purpose.
        $pd = 'C:/tmp/stage/tools'
        $fx = @('claude-permission-toolkit/guard-probes.json')
        if (-not (Assert-Case 'an absolute scanner path matches a fixture' 'True' "$(Test-IsRegisteredFixture -File 'C:\tmp\stage\tools\claude-permission-toolkit\guard-probes.json' -PackDir $pd -FixturePaths $fx)")) { $failures++ }
        if (-not (Assert-Case 'a source-relative scanner path matches a fixture' 'True' "$(Test-IsRegisteredFixture -File 'claude-permission-toolkit/guard-probes.json' -PackDir $pd -FixturePaths $fx)")) { $failures++ }
        if (-not (Assert-Case 'a cwd-relative scanner path matches a fixture' 'True' "$(Test-IsRegisteredFixture -File './stage/tools/claude-permission-toolkit/guard-probes.json' -PackDir $pd -FixturePaths $fx)")) { $failures++ }
        if (-not (Assert-Case 'a different file does NOT match a fixture' 'False' "$(Test-IsRegisteredFixture -File 'claude-permission-toolkit/replay_permissions.py' -PackDir $pd -FixturePaths $fx)")) { $failures++ }
        # ...and the near-miss that a suffix match must not swallow: a longer name ENDING in the
        # registered one is a different file.
        if (-not (Assert-Case 'a same-suffix but different file does not match' 'False' "$(Test-IsRegisteredFixture -File 'other/notguard-probes.json' -PackDir $pd -FixturePaths @('guard-probes.json'))")) { $failures++ }

        # ── parsing the called gate's scope out of the gate itself ────────────────
        $liveGate = Join-Path $PSScriptRoot 'Test-PracticeClaims.ps1'
        if (Test-Path -LiteralPath $liveGate) {
            $s = Get-DelegateScope -Path $liveGate
            if (-not (Assert-Case 'the live gate''s scope parses with no errors' '0' "$($s.Errors.Count)")) { $failures++ }
            if (-not (Assert-Case 'the parsed extension list is not empty' 'True' "$($s.Extensions.Count -gt 0)")) { $failures++ }
            if (-not (Assert-Case 'the parsed self-exemption names this file' 'True' "$($s.SelfNames -contains 'Test-SharePackClean.ps1')")) { $failures++ }
            if (-not (Assert-Case 'the parsed dispatch list is not empty' 'True' "$($s.CheckNames.Count -gt 0)")) { $failures++ }
            # The two table names, parsed rather than remembered. Without these the table-identity
            # assertion has nothing to compare against and would have to hold an opinion of its own
            # about which filename is the placeholder -- which is how it would come to stop
            # recognising one.
            if (-not (Assert-Case 'the real pattern table''s name parses out of the gate' 'redaction-classes.json' "$($s.RealTable)")) { $failures++ }
            if (-not (Assert-Case 'the fallback pattern table''s name parses too' 'redaction-classes.example.json' "$($s.ExampleTable)")) { $failures++ }
            if (-not (Assert-Case '...and they are not the same file' 'False' "$($s.RealTable -eq $s.ExampleTable)")) { $failures++ }
        }
        else {
            Write-Host "  [SKIP] the live gate is not beside this script; scope-parse controls not run" -ForegroundColor Yellow
            $failures++   # not a pass: the controls did not run
        }

        # a gate that is not there at all
        $s = Get-DelegateScope -Path (Join-Path $tmp 'no-such-gate.ps1')
        if (-not (Assert-Case 'a missing gate reports a scope error' 'True' "$($s.Errors.Count -gt 0)")) { $failures++ }

        # a gate whose redaction check has been renamed away
        $stubDir = Join-Path $tmp 'stub'; $null = New-Item -ItemType Directory -Path $stubDir -Force
        $stub = New-Stub -Dir $stubDir -Name 'Gate.ps1' -Table $goodTable -Code 0
        $s = Get-DelegateScope -Path $stub
        if (-not (Assert-Case 'a gate with no redaction check reports a scope error' 'True' "$($s.Errors.Count -gt 0)")) { $failures++ }

        # ── STAGING -- MOVED, NOT DELETED ─────────────────────────────────────────
        # Two controls used to sit here: a one-file tree stages as one file rather than unrolling to
        # zero, and the exclusion pattern is mirrored AND counted rather than silently dropping files.
        # They asserted against this file's own New-PackStage, which no longer exists -- staging is
        # Build-SharePack.ps1's, so those controls are now in ITS -SelfTest, under "-- staging --",
        # where they can still fail for the right reason. Duplicating them here would have left two
        # sets of controls over one behaviour, which is the same drift the stager itself was
        # consolidated to avoid.
        #
        # WHAT THIS FILE OWNS INSTEAD is the boundary between the two: the builder is invoked, its
        # exit code is believed only when it is zero, and its manifest is read at the grain the checks
        # downstream require. All three of those failing loudly is what these controls are for.
        $bld = Join-Path $tmp 'builders'; $null = New-Item -ItemType Directory -Path $bld -Force
        $bldSrc = Join-Path $tmp 'bld-src'; $null = New-Item -ItemType Directory -Path $bldSrc -Force
        [System.IO.File]::WriteAllText((Join-Path $bldSrc 'only.md'), "one file`n")

        $manifestBody = @'
{
  "schema": "share-pack-manifest/v1",
  "pack_prefix": "tools",
  "exclude_regex": "x",
  "hold_class_table": "hold-classes.json",
  "file_count": 3,
  "excluded_non_content": 1,
  "held_back": 1,
  "held_back_paths": [ "tools/practice-gate/redaction-classes.json" ],
  "files": [ "LICENSE", "NOTICE", "tools/only.md" ]
}
'@
        # A stand-in builder: it creates the content directory, writes a manifest, and exits with a
        # chosen code -- so the caller's assertions can be driven into every shape a real builder
        # could produce without waiting on a real build.
        $mkBuilder = {
            param($Name, $Code, $Manifest)
            $body = "param([string]`$PackRoot,[string]`$OutDir,[string]`$Prefix,[string]`$ExcludeRegex,[switch]`$Force)`n" +
            "`$null = New-Item -ItemType Directory -Path (Join-Path `$OutDir `$Prefix) -Force`n" +
            "[System.IO.File]::WriteAllText((Join-Path (Join-Path `$OutDir `$Prefix) 'only.md'), `"x`n`")`n"
            if ($null -ne $Manifest) {
                $body += "[System.IO.File]::WriteAllText((Join-Path `$OutDir 'share-pack-manifest.json'), @'`n$Manifest`n'@)`n"
            }
            $body += "exit $Code`n"
            $p = Join-Path $bld $Name
            [System.IO.File]::WriteAllText($p, $body)
            return $p
        }

        $okBuilder = & $mkBuilder 'ok.ps1' 0 $manifestBody
        $st = Invoke-PackBuilder -Builder $okBuilder -PackRoot $bldSrc -StageRoot (Join-Path $tmp 'bld1') `
            -Prefix 'tools' -ExcludeRegex 'x' -ManifestName 'share-pack-manifest.json'
        # THE GRAIN. The manifest lists the whole pack -- LICENSE and NOTICE at the root -- and every
        # check downstream is written against content-tree-relative paths. Reading the list without
        # stripping the prefix would inflate the count by exactly the number of root files and break
        # the two-enumerations comparison in Coverage by the same amount.
        if (-not (Assert-Case 'the manifest file list is read at PackDir-relative grain' 'only.md' "$(@($st.RelPaths) -join ',')")) { $failures++ }
        if (-not (Assert-Case '...so the root files are not counted as content' '1' "$(@($st.RelPaths).Count)")) { $failures++ }
        if (-not (Assert-Case 'the staging exclusion count comes off the manifest' '1' "$($st.Excluded)")) { $failures++ }
        if (-not (Assert-Case 'the withheld list is read, and at the same grain' 'practice-gate/redaction-classes.json' "$(@($st.HeldPaths) -join ',')")) { $failures++ }
        if (-not (Assert-Case '...and names the table the decision came from' 'hold-classes.json' "$($st.HoldTable)")) { $failures++ }

        # A builder that FAILED. The one thing a gate must never do here is scan whatever happens to
        # be on disk and report on it.
        $badBuilder = & $mkBuilder 'bad.ps1' 1 $manifestBody
        $threw = 'no'
        try { $null = Invoke-PackBuilder -Builder $badBuilder -PackRoot $bldSrc -StageRoot (Join-Path $tmp 'bld2') -Prefix 'tools' -ExcludeRegex 'x' -ManifestName 'share-pack-manifest.json' } catch { $threw = 'yes' }
        if (-not (Assert-Case 'a builder that exits non-zero aborts the gate' 'yes' $threw)) { $failures++ }

        # Exit 0 and no manifest: reported success and produced nothing readable, which is the exact
        # shape of a success message printed over a write that did not happen.
        $noManifest = & $mkBuilder 'no-manifest.ps1' 0 $null
        $threw = 'no'
        try { $null = Invoke-PackBuilder -Builder $noManifest -PackRoot $bldSrc -StageRoot (Join-Path $tmp 'bld3') -Prefix 'tools' -ExcludeRegex 'x' -ManifestName 'share-pack-manifest.json' } catch { $threw = 'yes' }
        if (-not (Assert-Case 'exit 0 with no manifest aborts the gate' 'yes' $threw)) { $failures++ }

        $brokenManifest = & $mkBuilder 'broken-manifest.ps1' 0 '{ this is not json'
        $threw = 'no'
        try { $null = Invoke-PackBuilder -Builder $brokenManifest -PackRoot $bldSrc -StageRoot (Join-Path $tmp 'bld4') -Prefix 'tools' -ExcludeRegex 'x' -ManifestName 'share-pack-manifest.json' } catch { $threw = 'yes' }
        if (-not (Assert-Case 'a manifest that does not parse aborts the gate' 'yes' $threw)) { $failures++ }

        $shortManifest = & $mkBuilder 'short-manifest.ps1' 0 '{ "schema": "share-pack-manifest/v1", "files": [ "tools/only.md" ] }'
        $threw = 'no'
        try { $null = Invoke-PackBuilder -Builder $shortManifest -PackRoot $bldSrc -StageRoot (Join-Path $tmp 'bld5') -Prefix 'tools' -ExcludeRegex 'x' -ManifestName 'share-pack-manifest.json' } catch { $threw = 'yes' }
        if (-not (Assert-Case 'a manifest missing a key this gate reads aborts it' 'yes' $threw)) { $failures++ }

        # A manifest describing a DIFFERENT tree than the one asked for. Silent otherwise: the paths
        # simply would not start with the prefix, the file list would come out empty, and an empty
        # scope is a gate that measured nothing.
        $wrongPrefix = & $mkBuilder 'wrong-prefix.ps1' 0 ($manifestBody -replace '"pack_prefix": "tools"', '"pack_prefix": "elsewhere"')
        $threw = 'no'
        try { $null = Invoke-PackBuilder -Builder $wrongPrefix -PackRoot $bldSrc -StageRoot (Join-Path $tmp 'bld6') -Prefix 'tools' -ExcludeRegex 'x' -ManifestName 'share-pack-manifest.json' } catch { $threw = 'yes' }
        if (-not (Assert-Case 'a manifest for a different prefix aborts the gate' 'yes' $threw)) { $failures++ }

        $threw = 'no'
        try { $null = Invoke-PackBuilder -Builder (Join-Path $tmp 'no-such-builder.ps1') -PackRoot $bldSrc -StageRoot (Join-Path $tmp 'bld7') -Prefix 'tools' -ExcludeRegex 'x' -ManifestName 'share-pack-manifest.json' } catch { $threw = 'yes' }
        if (-not (Assert-Case 'a missing builder aborts rather than staging nothing' 'yes' $threw)) { $failures++ }

        # The manifest NAME is parsed out of the builder, never restated here.
        if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'Build-SharePack.ps1')) {
            if (-not (Assert-Case 'the live builder''s manifest name parses out of it' 'share-pack-manifest.json' "$(Get-BuilderManifestName -Builder (Join-Path $PSScriptRoot 'Build-SharePack.ps1'))")) { $failures++ }
        }
        else {
            Write-Host "  [SKIP] the builder is not beside this script; its manifest-name parse was not exercised" -ForegroundColor Yellow
            $failures++
        }
        $stubBuilder = Join-Path $tmp 'stub-builder.ps1'
        [System.IO.File]::WriteAllText($stubBuilder, "# a builder with no manifest-name line`nexit 0`n")
        $threw = 'no'
        try { $null = Get-BuilderManifestName -Builder $stubBuilder } catch { $threw = 'yes' }
        if (-not (Assert-Case 'a builder whose manifest name has moved refuses' 'yes' $threw)) { $failures++ }

        # ── the live registry ─────────────────────────────────────────────────────
        # Loaded rather than mocked: a shape check that only ever sees fixtures is checking the
        # fixtures. This is the same reason the sibling gate's self-test reads its live registries.
        if (Test-Path -LiteralPath $RegistryPath) {
            $live = Import-PackRegistry -Path $RegistryPath
            if (-not (Assert-Case 'the live registry loads and shape-checks' 'True' "$($null -ne $live)")) { $failures++ }
        }
        else {
            Write-Host "  [SKIP] no live registry at $RegistryPath" -ForegroundColor Yellow
            $failures++
        }

        # a registry missing a key it is read for must refuse to load, not load empty.
        $badReg = Join-Path $tmp 'bad.json'
        [System.IO.File]::WriteAllText($badReg, '{ "unscanned": [], "secret_fixtures": [] }')
        $threw = 'no'
        try { $null = Import-PackRegistry -Path $badReg } catch { $threw = 'yes' }
        if (-not (Assert-Case 'a registry missing a required key refuses to load' 'yes' $threw)) { $failures++ }
    }
    finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    if ($failures -gt 0) {
        Write-Host "SELF-TEST FAILED -- $failures control(s) did not behave as specified" -ForegroundColor Red
        return 1
    }
    Write-Host "SELF-TEST PASSED -- every control behaved as specified" -ForegroundColor Green
    return 0
}

# ── MAIN ────────────────────────────────────────────────────────────────────────

if (-not $PackRoot) { $PackRoot = $PSScriptRoot }
if (-not (Test-Path -LiteralPath $PackRoot)) {
    Write-Host "ENVIRONMENT: -PackRoot '$PackRoot' does not exist" -ForegroundColor Red
    Write-Host "A gate that cannot locate its subject must not report PASS." -ForegroundColor Red
    exit 1
}
$PackRoot = (Resolve-Path -LiteralPath $PackRoot).Path
# NOT `if (-not $CitationPrefix)` and not `if ($null -eq ...)`. An unbound [string] parameter is the
# EMPTY STRING, not $null, so a null test never fired and the default never applied -- every
# document's `tools/...` citation then dangled in the staged bundle and the boundary registry filled
# up with 40-odd entries that were an artifact of the bug. Meanwhile '' is a legitimate value here,
# meaning "stage at the root", so the two cases have to be told apart by whether the caller passed
# it at all. Caught by the first live run, which is the argument for running a gate before believing
# its registry.
if (-not $PSBoundParameters.ContainsKey('CitationPrefix')) { $CitationPrefix = Split-Path -Leaf $PackRoot }
if (-not $PracticeGate) { $PracticeGate = Join-Path $PSScriptRoot 'Test-PracticeClaims.ps1' }
if (-not $Builder) { $Builder = Join-Path $PSScriptRoot 'Build-SharePack.ps1' }
if (-not $GateDir) { $GateDir = Join-Path $PSScriptRoot 'practice-gate' }
if (-not $RegistryPath) { $RegistryPath = Join-Path $GateDir 'share-pack.json' }

if ($SelfTest) { exit (Invoke-PackSelfTest -RegistryPath $RegistryPath -GateDir $GateDir) }

if (-not (Test-Path -LiteralPath $PracticeGate)) {
    Write-Host "ENVIRONMENT: the gate this one calls is not at $PracticeGate" -ForegroundColor Red
    Write-Host "Pass -PracticeGate if it lives elsewhere in this distribution. A caller whose callee" -ForegroundColor Red
    Write-Host "is missing has measured nothing, and must not report PASS." -ForegroundColor Red
    exit 1
}
$PracticeGate = (Resolve-Path -LiteralPath $PracticeGate).Path

if (-not (Test-Path -LiteralPath $Builder)) {
    Write-Host "ENVIRONMENT: the build step that produces this gate's subject is not at $Builder" -ForegroundColor Red
    Write-Host "Pass -Builder if it lives elsewhere. This gate does not stage the pack itself -- the" -ForegroundColor Red
    Write-Host "builder owns that, so a missing builder means there is nothing to check." -ForegroundColor Red
    exit 1
}
$Builder = (Resolve-Path -LiteralPath $Builder).Path

if (-not (Test-Path -LiteralPath $GateDir -PathType Container)) {
    Write-Host "ENVIRONMENT: -GateDir '$GateDir' does not exist" -ForegroundColor Red
    Write-Host "It holds this gate's hold list and the REAL pattern table the delegated content scan" -ForegroundColor Red
    Write-Host "needs. Without it the only tables available are the shipped placeholders, and a pack" -ForegroundColor Red
    Write-Host "certified by placeholder patterns has not been examined at all." -ForegroundColor Red
    exit 1
}
$GateDir = (Resolve-Path -LiteralPath $GateDir).Path

$registry = Import-PackRegistry -Path $RegistryPath
$scope = Get-DelegateScope -Path $PracticeGate

# Loaded here, so that a missing or malformed table is an ENVIRONMENT failure before a staging
# directory exists -- and a THROW rather than an empty list, because a hold list that failed to load
# forbids nothing and reports exactly what a clean pack reports.
$holdTable = $null
try { $holdTable = Import-HoldClasses -GateDir $GateDir }
catch {
    Write-Host "ENVIRONMENT: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
$manifestName = $null
try { $manifestName = Get-BuilderManifestName -Builder $Builder }
catch {
    Write-Host "ENVIRONMENT: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$stageRoot = if ($StageDir) { $StageDir } else {
    Join-Path ([System.IO.Path]::GetTempPath()) ("share-pack-stage-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
}
# RECORDED BEFORE THE MKDIR, because the finally has to know whether this run created the directory.
# The cleanup was an unconditional `Remove-Item -Recurse -Force` on $stageRoot, which is fine for the
# generated temp path -- a fresh guid, so it never pre-exists -- and was destructive for a
# caller-supplied -StageDir: point it at a directory holding anything and the directory went, contents
# and all, on a PRINT-ONLY gate. Found by hand on 2026-08-19 while testing the builder's refusal path,
# and the way it was found is the argument: the builder REFUSES to build into a directory holding
# files it did not create, reported that refusal correctly, the gate aborted with exit 1 -- and then
# the finally deleted the directory the builder had just declined to touch. One half of the code
# protecting what the other half removes. So the removal is now scoped to what this run created.
$stageRootWasOurs = -not (Test-Path -LiteralPath $stageRoot)
$null = New-Item -ItemType Directory -Path $stageRoot -Force
$results = [System.Collections.Generic.List[PackCheck]]::new()

# Initialised BEFORE the try, and to 1. If anything below throws, the finally clears the staging
# directory and execution reaches `exit $exit` with nothing assigned -- which under StrictMode is a
# second error on top of the first, in place of a verdict. A crash before the report is a failure,
# so the default is the failure.
$exit = 1

try {
    # THE BUILDER STAGES. Not this file -- see the block above Invoke-PackBuilder for why there is no
    # second stager here, and where the two controls that used to guard this one went.
    $stage = Invoke-PackBuilder -Builder $Builder -PackRoot $PackRoot -StageRoot $stageRoot `
        -Prefix $CitationPrefix -ExcludeRegex $scope.ExcludeRegex -ManifestName $manifestName

    # The STAGED gate is the one that runs: a distribution's own copy, proving it works from a
    # distribution rather than only from the repository that built it. That is a claim about the
    # SCRIPT, and it is separate from which registries the script reads -- see the two calls below.
    $stagedGate = Join-Path $stage.PackDir (Split-Path -Leaf $PracticeGate)
    if (-not (Test-Path -LiteralPath $stagedGate)) { $stagedGate = $PracticeGate }

    $run = $null
    $distRun = $null
    if ($Skip -notcontains 'PracticeGate') {
        # RUN 1 -- CONTENT. The repository's registry directory, because the question is "is this
        # content free of real organisation identifiers?" and only the real table can answer it. The
        # real table is hold-listed out of the pack, so it is not reachable from the staged copy by
        # design; pointing this run there -- which is what this line did until 2026-08-19 -- asks the
        # real question and gets an answer about example-corp.
        $run = Invoke-DelegateGate -Delegate $stagedGate -Stage $stage -GateDir $GateDir

        # RUN 2 -- DISTRIBUTION. The STAGED registry directory, scoped to the redaction check, asking
        # a different question: can a recipient holding only what we shipped stand this gate up? Its
        # verdict on identifiers is worth nothing and is not read as one -- what is read is that it
        # ran, and WHICH table it found, because finding the real one would mean the pack shipped the
        # reconnaissance map. Scoped with -Only because that is the whole question: the other five
        # checks read registries that are byte-identical in both directories, so running them again
        # would double the gate's cost to re-measure the same thing.
        $distRun = Invoke-DelegateGate -Delegate $stagedGate -Stage $stage `
            -GateDir (Join-Path $stage.PackDir 'practice-gate') -Only 'Redaction'
    }

    foreach ($name in $script:PackChecks) {
        if ($Skip -contains $name) {
            $c = [PackCheck]::new($name)
            $c.Status = 'SKIPPED'
            $c.Note = 'deliberately not run (-Skip) -- this is not a pass'
            $results.Add($c)
            continue
        }
        if ($null -eq $run -and $name -in @('PracticeGate', 'BundleBoundary', 'Coverage')) {
            # Skipped by DEPENDENCY, not by choice, and not a pass either: these three read the
            # called gate's report and there is none.
            $c = [PackCheck]::new($name)
            $c.Status = 'SKIPPED'
            $c.Note = 'not run: it reads the called gate''s report, and PracticeGate was skipped'
            $results.Add($c)
            continue
        }
        switch ($name) {
            'PracticeGate' { $results.Add((Test-DelegateRun -Run $run -Scope $scope -DistRun $distRun)) }
            'BundleBoundary' { $results.Add((Test-BundleBoundary -Run $run -Registry $registry)) }
            'Coverage' { $results.Add((Test-PackCoverage -Stage $stage -Run $run -Scope $scope -Registry $registry)) }
            'HoldList' { $results.Add((Test-HoldList -Stage $stage -Classes @($holdTable.Classes) -TableName $holdTable.File)) }
            'RootFiles' { $results.Add((Test-PackRootFiles -Stage $stage -Registry $registry -Scope $scope -GateDir $GateDir)) }
            'Secrets' { $results.Add((Test-PackSecrets -Stage $stage -Registry $registry -Classes $script:SecretClasses -UseGitleaks:$Gitleaks -GitleaksExe $GitleaksPath)) }
        }
    }

    # ── REPORT ──────────────────────────────────────────────────────────────────
    $out = [System.Text.StringBuilder]::new()
    function Emit { param([string]$Text, [string]$Colour = 'Gray'); Write-Host $Text -ForegroundColor $Colour; $null = $out.AppendLine($Text) }

    Emit ""
    Emit "SHARE PACK GATE -- $PackRoot"
    Emit ("built as {0} in {1} by {2}" -f $(if ($CitationPrefix) { "$CitationPrefix/" } else { '<root>' }), $stage.Root, (Split-Path -Leaf $Builder))
    # ON THE FACE OF THE REPORT, not buried in a note in a delegated report nobody parses. Which
    # pattern table answered the content question is the single fact that decides whether any of the
    # lines below mean anything, and for one revision of this file it appeared nowhere in the output
    # at all.
    Emit ("pattern tables: hold list {0}; content scan {1}" -f $holdTable.File,
        $(if ($null -ne $run) { $t = Get-DelegateRedactionTable -Run $run; if ($t) { $t } else { '<not stated>' } } else { '<not run>' }))
    Emit ("=" * 78)

    foreach ($c in $results) {
        $colour = switch ($c.Status) {
            'PASS' { 'Green' } 'FAIL' { 'Red' } 'INCONCLUSIVE' { 'Red' } 'SKIPPED' { 'Yellow' } default { 'Gray' }
        }
        Emit ("{0,-16} {1,-13} {2,5} candidate(s){3}" -f $c.Name, $c.Status, $c.Candidates, $(if ($c.Note) { "  -- $($c.Note)" } else { '' })) $colour
        # ASCII only, for the same reason the sibling gate says so: windows-latest turned a
        # non-ASCII bullet into a replacement character and made the log unreadable.
        foreach ($f in $c.Findings) { Emit "                   - $f" $colour }
    }

    # The registered boundary is PRINTED on a green run. An exemption nobody sees is one nobody
    # revisits, which is how the list grows into a silencer.
    Emit ("-" * 78)
    $bChecks = @($registry.bundle_boundary.checks)
    $bCites = @($registry.bundle_boundary.citations)
    $unscan = @($registry.unscanned)
    $fix = @($registry.secret_fixtures)
    # PRINTED EVEN WHEN IT IS EMPTY, and it is empty today. "Nothing is permitted in the pack root"
    # and "the list of permitted things is not being read" are different facts, and a line that
    # appears only when there is something to say cannot tell them apart.
    $rootAllow = @()
    if ($registry.ContainsKey('root_file_allowed')) { $rootAllow = @($registry.root_file_allowed) }
    Emit "registered bundle boundary: $($bChecks.Count) check(s), $($bCites.Count) citation(s); $($unscan.Count) unscanned file(s); $($fix.Count) secret fixture(s); $($rootAllow.Count) root-file exception(s)"
    foreach ($e in $bChecks) { Emit "  boundary  check      $($e.check) [$(@($e.statuses) -join '/')]" }
    foreach ($e in $bCites) { Emit "  boundary  citation   $($e.document) -> $($e.token)" }
    foreach ($e in $unscan) { Emit "  exempt    unscanned  $($e.path)" }
    foreach ($e in $fix) { Emit "  exempt    fixture    $($e.path)" }
    foreach ($e in $rootAllow) { Emit "  exempt    root file  $($e.path) -> '$($e.match)'" }

    $failed = @($results | Where-Object { $_.Status -in @('FAIL', 'INCONCLUSIVE') })
    $skipped = @($results | Where-Object { $_.Status -eq 'SKIPPED' })

    Emit ("=" * 78)
    if ($failed.Count -gt 0) {
        Emit "RESULT: FAIL -- $($failed.Count) check(s) failed or measured nothing" 'Red'
        $exit = 1
    }
    elseif ($skipped.Count -gt 0) {
        Emit "RESULT: SKIPPED -- $($skipped.Count) check(s) not run; the rest passed." 'Yellow'
        Emit "        This is not a pass. Re-run without -Skip before shipping anything." 'Yellow'
        $exit = 2
    }
    else {
        Emit "RESULT: PASS -- every check ran and passed" 'Green'
        $exit = 0
    }
    Emit ""

    if ($ReportPath) {
        # WriteAllText, not Set-Content: Set-Content honours -WhatIf and would silently skip the
        # write, leaving a report nobody notices is missing.
        [System.IO.File]::WriteAllText($ReportPath, $out.ToString())
        Write-Host "report written to $ReportPath"
    }
}
catch {
    # A THROW IS A FAILURE, REPORTED AS ONE. Staging, the manifest read and the hold-list load all
    # throw rather than degrading, because each of them is a precondition for having a subject at all
    # -- and without this block a throw reached `exit $exit` past a finally, printing a raw
    # PowerShell error and no verdict. $exit is already 1 for that reason; this makes the reason
    # legible instead of leaving it to whoever reads a stack trace.
    Write-Host ""
    Write-Host "SHARE PACK GATE -- ABORTED, no verdict" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "A gate that could not run must not report PASS. Exiting 1." -ForegroundColor Red
    $exit = 1
}
finally {
    if ($KeepStage) { Write-Host "staged tree left at $stageRoot" -ForegroundColor Cyan }
    elseif (-not $stageRootWasOurs) {
        # Said out loud rather than silently skipped: a directory left behind that the caller expects
        # to have been cleaned is its own small surprise, and "we did not delete your directory" is
        # the whole point of the branch.
        Write-Host "staged tree left at $stageRoot -- this gate did not create that directory, so it will not remove it" -ForegroundColor Cyan
    }
    else { Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

exit $exit
