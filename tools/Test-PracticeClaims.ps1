<#
.SYNOPSIS
    Claim gate for tools/** -- the practice documents, the toolkits, the firing layer and the CI
    layer: nine directories, plus the four gate and builder scripts beside them, so thirteen entries
    in all. claude-dev-practice holds documents rather than a toolkit, claude-practice-layer is the
    one unit that installs rather than being read, and practice-gate holds this script's registries.

    THIS SENTENCE USED TO SAY "the four toolkits ... seven directories" AND IT WENT WRONG SILENTLY,
    which is the same defect check H below was added for and is the reason the count is now stated
    here at all rather than being left vague enough never to be falsifiable. Nothing gates this
    docblock -- check H gates the README's version of the same list, and the honest note is that a
    number in a comment is the weaker of the two homes.

.DESCRIPTION
    tools/ ships prose that makes checkable assertions: that a cited file exists, that a quoted
    measurement was actually measured, that nothing organisation-specific leaks, and that a claim
    about the harness was verified at some point a reader can name. Until this script existed
    nothing in CI looked at tools/ at all, and the reason is worth keeping even though the directory
    names are not: both workflows were scoped by path glob to the two trees anyone was actively
    editing -- the skills tree and the packaging tree that redistributes it, each named explicitly,
    with their own scripts and workflow files -- so every path glob in CI was a list of somewhere
    else. tools/ was not on any of those lists, which meant the repo's own "no personal paths" rule
    had never fired there once. A path-globbed gate does not report the directories it was never
    pointed at; it reports green. (build-and-verify.yml now globs tools/** as well -- which is this
    script's own CI hook, so keep the workflow's list and this script's scope in step.)

    The documents' own thesis is the reason this is a script and not a careful read:

        A check that could not run must never report PASS, and a guarantee that depends on
        remembering to apply it is not a guarantee.

    EIGHT CHECKS. They are lettered A-H in the order they were written, which is no longer the order
    they appear in this file or run in -- E and F were added after B/C/D, and G and H after all of
    them. The letters are historical labels, not sequence.

      A. Citations       Every path-shaped or script-named token cited in tools/**/*.md resolves
                         on disk, or is registered in practice-gate/external-citations.json with a
                         reason. The README promises "if a document says a thing is enforced, you
                         can go and read the enforcement" -- this is that promise, executed.

      E. Sourcing        The other half of A, and the half that was missing. A only inspects the
                         citations that EXIST; it is silent about a section containing none, which
                         is how an entirely unsourced section shipped -- second-longest in the
                         document, zero paths, every check green. Every section must carry at least
                         one resolvable citation or be registered in practice-gate/sourcing.json
                         with the reason no path can be given.

      B. Figures         Every measurement-shaped literal (2,673 · 87% · 10 versus 12 · ~14 ms)
                         either has an ISO date in its own paragraph, or is registered in
                         practice-gate/figures.json with the date it was measured and a reason.
                         An undated number reads as current state and rots silently.

      C. Redaction       No organisation identifier anywhere in tools/**. Pattern classes are the
                         ones enumerated in PLAN-external-share-pack.md §3, and they live in
                         practice-gate/redaction-classes.json rather than in this file: inline,
                         they published the whole internal identifier vocabulary in one screen.
                         That table is held back from any distribution and a generic
                         redaction-classes.example.json ships in its place, so this check has a
                         fallback -- and a fallback nobody is told about is a downgrade nobody
                         notices, which is why the report names the table it loaded and this check
                         THROWS when there is none.

      D. Harness pins    Every claim about Claude Code's OWN behaviour names when it was last
                         verified. This check does NOT know whether a claim is true and must never
                         pretend to -- it asserts only that the claim is dated, which is what turns
                         silent rot into visible staleness. It caught nothing on the day it was
                         written; it exists because an undated harness claim had already gone
                         false on the page (double-Esc), and no amount of re-reading finds that.

                         MARKERS ARE MATCHED CASE-SENSITIVELY; KEYWORDS ARE NOT. A marker is a
                         literal quotation of prose, so case is part of it -- and until 2026-08-17
                         a marker could cover a sentence about an unrelated mechanism, because
                         PowerShell's -match ignores case. Keywords stay case-insensitive by
                         default because they are per-keyword regexes carrying their own flags.
                         Full reasoning at the site, both polarities in the self-test.

      F. Assertions      The inversion of D, and the only check that reads OUTSIDE tools/. Every
                         negative claim in the scoped planning documents -- "X does not exist",
                         "nothing does Y" -- is re-tested against the tree, because the way a gap
                         statement goes false is by somebody CLOSING the gap and not striking the
                         sentence. Its scope is the registry, not the tree walk.

                         F was implemented, dispatched, and missing from this list for as long as
                         it existed: the header said SIX and named five. Left recorded rather than
                         quietly corrected, because a gate whose own docblock undercounts its
                         checks is this file's subject turned on itself, and nothing here reads
                         this docblock.

      G. Prior art       Every entry in practice-gate/prior-art.json names a version, a date, a
                         relationship and a reason, and is checked in BOTH directions against the
                         prose: forward, the documents it says cite it must exist and must contain
                         the work's name verbatim; reverse, an entry nothing cites FAILS AS STALE.
                         Attribution is the one claim here a reader cannot check by running
                         something, and it rots by DECORATING -- written once for credit, and left
                         flattering nobody after the field moves. Nothing else in this file would
                         have gone red for that.

      H. Front door      Every entry directly under this gate's scanned root is named in the
                         repository README's tools section, and every unit that section names
                         exists. The second check that reads OUTSIDE the scanned tree, and the only
                         one whose subject is what the prose OMITS rather than what it asserts.
                         A-G all read the text that is there; an enumeration-by-example rots by
                         going quiet, so everything it still names resolves and the omission is
                         invisible from inside a green run. The table described seven units against
                         thirteen on disk, and the newest of the three it never mentioned was the
                         only one that makes the practice fire. Exemptions and the two controls are
                         in practice-gate/front-door.json, both directions, same as everything else
                         here. Applicability is decided by a marker rather than by the heading --
                         see the check for why that inversion matters -- and a distribution reports
                         SKIPPED, registered as a bundle boundary in practice-gate/share-pack.json.

    PRINT-ONLY BY CONSTRUCTION. There is no -Fix. A reporter that prints the edit is safer than an
    applier that grows a -Yes the first time somebody scripts it.

.PARAMETER DocRoot
    Directory to scan. Default: the directory this script lives in (tools/).

.PARAMETER RepoRoot
    Root the citations resolve against. Default: the parent of the directory this script lives in.
    Override it when the gate runs over a distribution rather than this repository -- a share pack
    holding only tools/ and ci/ has a different root, and until this parameter existed the gate
    exited 1 there with "cannot resolve the repository root", which reads like a broken checkout
    rather than a different shape.

.PARAMETER GateDir
    Directory holding the registries (external-citations, sourcing, figures, verified-against,
    assertions, prior-art, front-door, and the redaction class table).
    Default: RepoRoot/tools/practice-gate.

    The redaction table is the one registry with a fallback: redaction-classes.json if it is there,
    redaction-classes.example.json if it is not, and a throw if neither is. See check C.

.PARAMETER Skip
    Check names to deliberately NOT run: Citations, Sourcing, Figures, Redaction, HarnessPins,
    Assertions, PriorArt, FrontDoor -- the full set the ValidateSet accepts. A skipped check exits 2
    and is named in the report. It is never counted as a pass.

.PARAMETER Only
    The inverse of -Skip: the checks this run CONSISTS OF. Everything else is out of scope rather
    than declined, so the run can still exit 0.

    The two are not interchangeable and the difference is the exit code. -Skip means "this check
    applies here and I chose not to run it", which is exit 2 forever, so a -Skip run can never
    gate anything -- and reading exit 2 as success is precisely the fail-open this repository has
    already been bitten by twice. -Only means "this is the whole check for this root". Citations
    over skills/ is the case it exists for: Sourcing, Figures, Redaction, HarnessPins and PriorArt
    are tuned to tools/ prose and are not applicable there, and FrontDoor is an argument about a
    section of the README that enumerates tools/ and nothing else, so declining them is not the
    claim being made.

    Mutually exclusive with -Skip -- passing both is a contradiction about what the run is, and
    is rejected rather than resolved.

.PARAMETER MaxPinAgeDays
    A registered harness pin older than this is STALE and fails. Default 180. The same window
    expires a prior-art entry's date_checked: a description of somebody else's repository is a claim
    about a moving artifact and rots at the same rate as a claim about the harness, so it gets the
    same limit rather than a second knob nobody would tune separately.

.PARAMETER MaxFigureAgeDays
    A registered figures.json MEASUREMENT older than this is STALE and fails. Default 180, the
    same window as harness pins and for the same reason: a dated measurement and a dated harness
    claim rot at the same rate, and this registry required a date but expired nothing, so an
    entry could carry a two-year-old date and stay green forever. Illustrations are exempt --
    they have no measurement date to go stale, which is the point of the kind split.

.PARAMETER ReportPath
    Optional file to write the full report to. Written with [System.IO.File]::WriteAllText --
    Set-Content honours -WhatIf and would silently skip the write under a dry run.

.PARAMETER SelfTest
    Run the negative controls against fixtures in a temp directory and exit. Proves the gate can
    fail -- including the case it exists for, an empty scan reporting INCONCLUSIVE rather than PASS.
    Writes nothing inside the repository.

.EXAMPLE
    pwsh -NoProfile -File tools/Test-PracticeClaims.ps1

.EXAMPLE
    pwsh -NoProfile -File tools/Test-PracticeClaims.ps1 -SelfTest

.NOTES
    EXIT CONTRACT
      0  every check ran and passed
      1  a check FAILED, or a check ran and found ZERO candidates (INCONCLUSIVE), or the
         environment could not be resolved
      2  a check was deliberately not run (-Skip) and nothing else failed -- SKIPPED, never a pass

    Zero candidates maps to 1, not 0, on purpose. A regex that stops matching produces an empty
    finding set, and "clean" must not share an outcome with "the extractor broke". That is the
    single failure mode this script exists to prevent and it has its own self-test.

    "I chose not to run this" (2) and "it ran and measured nothing" (1) are different states and
    do not share an exit code.

    ps1-safety: $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest; READ-ONLY against
    the repository in every mode EXCEPT -SelfTest, whose fixtures are otherwise in a temp directory
    it creates and removes. The exception is one file, zz-selftest-probe.md, written at the
    repository root and removed in a finally: the inversion controls assert that a negative claim
    about a file that EXISTS fires, so the probe has to sit inside the scanned root to be seen at
    all. Stated here because an earlier version of this line said "writes only into a temp
    directory", which was false, and a false safety note is worse than none.
    The only other write is the optional -ReportPath.
    No network, no secrets, no docker, no database surface.
    Idempotent trivially. Tolerates CRLF, since build-and-verify.yml checks out on windows-latest.
#>
[CmdletBinding()]
param(
    [string]$DocRoot,
    [string]$RepoRoot,
    [string]$GateDir,
    [ValidateSet('Citations', 'Sourcing', 'Figures', 'Redaction', 'HarnessPins', 'Assertions', 'PriorArt', 'FrontDoor')]
    [string[]]$Skip = @(),
    [ValidateSet('Citations', 'Sourcing', 'Figures', 'Redaction', 'HarnessPins', 'Assertions', 'PriorArt', 'FrontDoor')]
    [string[]]$Only = @(),
    [int]$MaxPinAgeDays = 180,
    [int]$MaxFigureAgeDays = 180,
    [string]$ReportPath,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ── OUTCOME VOCABULARY ──────────────────────────────────────────────────────────
# PASS / FAIL / INCONCLUSIVE / SKIPPED. INCONCLUSIVE is not a softer FAIL: it means the check ran
# and measured nothing, so its PASS would have been vacuous.

class CheckResult {
    [string]$Name
    [string]$Status
    [int]$Candidates
    [System.Collections.Generic.List[string]]$Findings
    [string]$Note

    CheckResult([string]$name) {
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

    # Call once, after counting. A check that examined nothing cannot have passed.
    #
    # It must NOT downgrade a recorded FAIL, though: a check that found a defect has measured
    # something by definition, and INCONCLUSIVE would both hide the finding and misdescribe it as
    # "the extractor is broken". Only a check that is still clean AND counted nothing is
    # inconclusive. Caught by a self-test on a registry pointing at a file that no longer exists,
    # where the failure was real and the count was legitimately zero.
    [void] Seal() {
        if ($this.Candidates -eq 0 -and $this.Status -eq 'PASS') {
            $this.Status = 'INCONCLUSIVE'
            $this.Note = 'extracted zero candidates -- the extractor is broken or the scope is empty'
        }
    }
}

# ── HELPERS ─────────────────────────────────────────────────────────────────────

function Get-ScanFiles {
    param([string]$Root, [string[]]$Extensions)
    if (-not (Test-Path -LiteralPath $Root)) { return @() }
    return @(Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $Extensions -contains $_.Extension.ToLowerInvariant() -and
            $_.FullName -notmatch '[\\/](__pycache__|node_modules|\.git)[\\/]'
        })
}

function Read-Lines {
    param([string]$Path)
    # -Raw then split, rather than Get-Content's line mode, so CRLF and a missing trailing
    # newline both normalise to the same thing on every runner.
    $raw = [System.IO.File]::ReadAllText($Path)
    return , ($raw -split "\r?\n")
}

function Read-Paragraphs {
    param([string]$Path)
    # CRLF is normalised FIRST. A paragraph break in a CRLF file is \r\n\r\n, so splitting on
    # \n\n+ without this matches nothing and the whole document comes back as one paragraph --
    # which reads as "every figure is in a paragraph that has a date somewhere in it".
    $raw = [System.IO.File]::ReadAllText($Path) -replace "\r\n", "`n"
    return , ($raw -split "`n`n+")
}

# CALLER CONTRACT for Read-Lines and Read-Paragraphs, learned the hard way:
# ALWAYS assign the result to a variable before iterating it. The `return ,$array` wrapper is what
# stops a one-element result from being unrolled into a bare string, but it also means
# `foreach ($x in Read-Paragraphs ...)` iterates the WRAPPER -- exactly once, binding $x to the
# whole array. Assignment unrolls the wrapper and iterates the elements. Both forms run clean and
# report success; only one of them is reading the file. Guarded by a self-test.

function Import-Registry {
    # RequireKeys is per-registry, not fixed: each one is shape-checked against the keys IT needs.
    # A single hardcoded key made the check simultaneously too strict (a registry with no 'entries'
    # could not load at all) and too weak (nothing verified the keys that registry actually reads).
    param([string]$Path, [string]$Name, [string[]]$RequireKeys = @('entries'))
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
    return $FullName.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/'
}

# ONE extractor, two consumers: check A asks whether each citation RESOLVES, check E asks whether a
# section has ANY. Written twice they would drift, and the drift would be invisible -- a section
# could satisfy E with a token A does not consider a citation at all.
function Get-CitationTokens {
    param([string]$Line)

    $tokens = [System.Collections.Generic.List[string]]::new()

    foreach ($m in [regex]::Matches($Line, '`([^`]+)`')) {
        $t = $m.Groups[1].Value.Trim()
        # A backticked span is often an INVOCATION, not a bare path -- `freshness.py --no-connector`
        # names a real file this repo ships. Rejecting anything containing a space missed those
        # entirely, so both checks under-counted: check A never verified them, and check E called
        # the section unsourced. Take the first word and shape-test that instead. Prose and rule
        # syntax still fall out, because their first word is not path-shaped either: `cat .env` ->
        # 'cat', `git push --force*` -> 'git', `Bash(pwsh *)` -> 'Bash(pwsh'.
        $head = ($t -split '\s+')[0]
        if ($head -match '[\*\(\)]') { continue }       # glob / permission-rule syntax
        if ($head -match '^https?://') { continue }
        if ($head -match '/' -or $head -match '\.(py|ps1|psd1)$') { $tokens.Add($head) }
    }
    foreach ($m in [regex]::Matches($Line, '\]\(([^)]+)\)')) {
        $t = $m.Groups[1].Value.Trim()
        if ($t -match '^(https?:|#|mailto:)') { continue }
        $tokens.Add($t)
    }

    # SCOPE LIMIT, stated rather than silent: this verifies REPO-ANCHORED citations. Three shapes
    # are excluded because a repository-scoped gate cannot resolve them and must not imply that it
    # did --
    #   <placeholder>   names a shape the reader substitutes into
    #   ~/... or .claude/ host configuration, outside every repository
    #   origin/...      a git ref namespace, not a path
    #   .ps1            a bare EXTENSION names a file type, not a file
    #   $u.input_tokens a VARIABLE EXPRESSION, not a path
    # A bare script name is NOT excluded: it could resolve here, so if it does not, that is a
    # finding (this is what catches a cross-repo citation given without its path).
    #
    # The extension case is a defect, not a scope limit, and it was invisible while this gate only
    # ever read tools/: prose there says "the script", while a skill about PowerShell says "any
    # plan-mode session whose deliverable is a `.ps1`". The shape test admits it because it ends
    # in .ps1 -- which is the test working as designed on an input that is not a citation at all.
    # Excluded by shape rather than registered, because there is no file it could ever resolve to
    # and an exemption implies there is one.
    #
    # A token opening with `$` is the same case: `$u.input_tokens ?? 0`, `${NEO4J_USER}/${PASS}`,
    # `$m='C:/...';` are variable expressions quoted from code, and the ones containing a slash
    # pass the shape test for no better reason than that a Neo4j auth pair and a docker volume
    # mapping both spell themselves with one. There is no file at the end of any of them. Eleven
    # of these surfaced the moment the gate read skills/, across four skills, which is the point
    # at which registering them one by one stops being a decision and starts being a ritual.
    return , [string[]]@(
        $tokens | Where-Object {
            $_ -notmatch '[<>]' -and $_ -notmatch '^~/' -and
            $_ -notmatch '^\.claude/' -and $_ -notmatch '^origin/' -and
            $_ -notmatch '^\.[A-Za-z0-9]+$' -and $_ -notmatch '^\$'
        })
}

# ── CHECK A -- CITATIONS RESOLVE ─────────────────────────────────────────────────
# A citation is a backticked token that is path-shaped (contains /) or names a script (.py/.ps1),
# plus every relative markdown link target. Globs, permission-rule syntax and bare generic
# filenames are deliberately NOT citations: they name a shape, not an artifact.

function Test-Citations {
    param([string]$Root, [string]$RepoRoot, [hashtable]$Registry)

    $r = [CheckResult]::new('Citations')
    $exempt = @{}
    $exemptUsed = @{}
    $exemptRoot = @{}
    # The registry is REPO-WIDE; the walk is root-scoped. Until this gate only ever read tools/
    # those were the same thing, and the reverse check below could read "no document cites this"
    # as "this is dead". Run it over any other root and all five entries report stale at once --
    # not because they rotted, but because their documents were out of scope. An entry therefore
    # declares the root it was written for.
    #
    # An entry with NO declared root stays in scope everywhere, which is the old behaviour. That
    # direction is deliberate and the self-test pins it: defaulting an undeclared entry to tools
    # would have made it invisible to every other root's reverse check -- an exemption nothing can
    # ever call dead, which is the silencer this registry's own header warns about. Undeclared
    # therefore means "answerable to every root", never "answerable to none". The five entries
    # that predate multi-root say root: tools explicitly rather than leaning on a default.
    $runRoot = (Get-RelPath -FullName $Root -Root $RepoRoot)
    if ([string]::IsNullOrWhiteSpace($runRoot)) { $runRoot = '.' }
    foreach ($e in $Registry.entries) {
        # A registered exemption without a stated reason is a silencer, which is the wording the
        # figures registry already uses for the same shape. This registry did not check it, so an
        # entry could suppress a finding while recording nothing about why.
        if (-not $e.ContainsKey('reason') -or [string]::IsNullOrWhiteSpace([string]$e.reason)) {
            $r.Fail("external-citations.json entry '$($e.token)' has no reason -- an exemption nobody justified is a silencer, not a decision")
        }
        $exempt[$e.token] = $e
        $exemptUsed[$e.token] = $false
        $exemptRoot[$e.token] = if ($e.ContainsKey('root') -and -not [string]::IsNullOrWhiteSpace([string]$e.root)) { ([string]$e.root).Trim('/') } else { '' }
    }

    # Every file in the repo, indexed by basename, so a bare script name can be resolved.
    $byName = @{}
    foreach ($f in Get-ChildItem -LiteralPath $RepoRoot -Recurse -File -ErrorAction SilentlyContinue) {
        if ($f.FullName -match '[\\/](\.git|__pycache__|node_modules)[\\/]') { continue }
        $byName[$f.Name] = $true
    }

    foreach ($file in Get-ScanFiles -Root $Root -Extensions @('.md')) {
        $rel = Get-RelPath -FullName $file.FullName -Root $RepoRoot
        $lines = Read-Lines -Path $file.FullName
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            $tokens = Get-CitationTokens -Line $line

            foreach ($t in $tokens) {
                $r.Candidates++
                $clean = ($t -split '#')[0].TrimEnd('/')
                if ([string]::IsNullOrWhiteSpace($clean)) { continue }
                if ($exempt.ContainsKey($clean)) { $exemptUsed[$clean] = $true; continue }

                $resolved = $false
                # relative to the citing document
                if (Test-Path -LiteralPath (Join-Path $file.DirectoryName $clean)) { $resolved = $true }
                # relative to the repository root
                elseif (Test-Path -LiteralPath (Join-Path $RepoRoot $clean)) { $resolved = $true }
                # bare script name, anywhere in the repository
                elseif ($clean -notmatch '/' -and $byName.ContainsKey($clean)) { $resolved = $true }

                if (-not $resolved) {
                    $r.Fail("$rel`:$($i + 1)  cites '$clean' -- does not resolve, and is not registered in external-citations.json")
                }
            }
        }
    }

    # THE REVERSE CHECK, which this registry did not have. `sweep_exclusions` gained one because an
    # exemption that outlives its cause is indistinguishable from one still doing work -- and that
    # is not hypothetical here: an entry in THIS file records that its own previous reason
    # "outlived the fact", found by a person re-reading it. Two failure modes, both silent:
    #
    #   * nothing cites the token any more -- the exemption is dead weight carrying a stale reason
    #   * the token now RESOLVES -- the citation came home, and the exemption is skipping a check
    #     that would pass, which is the worse one, because it keeps working while meaning nothing
    #
    # Checked after the walk rather than during it: an entry is only unused once every document
    # has been read.
    foreach ($tok in $exemptUsed.Keys) {
        if ($exemptUsed[$tok]) {
            # It is cited. Is it still EXTERNAL? An exemption for something now in the tree is a
            # gate that has been talked out of running.
            $here = (Test-Path -LiteralPath (Join-Path $RepoRoot $tok)) -or
                    ($tok -notmatch '/' -and $byName.ContainsKey($tok))
            if ($here) {
                $r.Fail("external-citations.json exempts '$tok', but it now resolves under $RepoRoot -- the citation came home and the exemption is suppressing a check that would pass; remove the entry")
            }
            continue
        }
        # Only an entry whose declared root this run actually covers can be called dead by it.
        # In scope when either path contains the other: the run is inside the entry's root, or it
        # sweeps it. Anything else is simply not this run's subject, and saying so would turn a
        # scoped run into a machine for deleting other roots' exemptions.
        $er = $exemptRoot[$tok]
        $inScope = ($er -eq '') -or ($runRoot -eq '.') -or ($runRoot -eq $er) -or
                   $runRoot.StartsWith("$er/") -or $er.StartsWith("$runRoot/")
        if (-not $inScope) { continue }
        $where = if ($er) { " (root: $er)" } else { '' }
        $r.Fail("external-citations.json exempts '$tok'$where, which no document under $Root cites -- the exemption outlived the claim it was written for; remove it, or fix the token")
    }

    $r.Seal()
    return $r
}

# ── CHECK E -- EVERY SECTION IS SOURCED ─────────────────────────────────────────
# Check A asks whether the citations that exist resolve. It says nothing about a section that
# cites NOTHING, which is how an entirely unsourced section shipped: it was the second-longest in
# the document, pointed at no code, and passed every check here because it made no claim a regex
# could test. Found by a human read -- exactly the kind of finding that should become a gate
# rather than a lesson.
#
# So: every section of a document that promises "every claim points at code you can go and read"
# must carry at least one resolvable citation, or be registered as deliberately unsourced WITH the
# reason. Registering is cheap and honest -- a section that cannot be sourced should say so on its
# face, and the registry makes that a decision rather than an oversight.

function Test-Sourcing {
    param([string]$Root, [string]$RepoRoot, [hashtable]$Registry)

    $r = [CheckResult]::new('Sourcing')

    if (-not $Registry.ContainsKey('scope')) {
        throw "sourcing.json has no 'scope' -- refusing to guess which documents make the promise"
    }
    $scope = @($Registry.scope)

    $exempt = @{}
    foreach ($e in $Registry.entries) {
        $ok = $true
        foreach ($k in @('file', 'section', 'reason')) {
            if (-not $e.ContainsKey($k)) {
                $r.Fail("sourcing.json entry is missing required key '$k' -- an unsourced section without a stated reason is an oversight, not a decision")
                $ok = $false
            }
        }
        if ($ok) { $exempt['{0}||{1}' -f $e.file, $e.section] = $e }
    }

    $docs = @(Get-ScanFiles -Root $Root -Extensions @('.md') | Where-Object {
            $rel = Get-RelPath -FullName $_.FullName -Root $RepoRoot
            $keep = $false
            foreach ($pat in $scope) { if ($rel -like $pat) { $keep = $true; break } }
            $keep
        })
    if ($docs.Count -eq 0) {
        $r.Status = 'INCONCLUSIVE'
        $r.Note = "scope matched no documents under $Root -- widen it, or check the path shape"
        return $r
    }

    # Every section actually walked, key -> citation count. The forward check only needs the
    # zero-citation ones; the reverse check below needs all of them, because the two ways a
    # sourcing exemption rots are "the heading is gone" and "the heading now cites something",
    # and telling those apart requires knowing the section was seen at all.
    $seen = @{}

    foreach ($file in $docs) {
        $rel = Get-RelPath -FullName $file.FullName -Root $RepoRoot
        $lines = Read-Lines -Path $file.FullName

        $section = $null        # stays null until the first heading: the preamble is not a section
        $cites = 0
        $startLine = 0
        $inFence = $false

        # The loop runs one past the end and feeds itself a sentinel heading, so the LAST section
        # is evaluated by the same code path as every other one. Closing it separately after the
        # loop is how the final section ends up unchecked.
        for ($i = 0; $i -le $lines.Count; $i++) {
            $line = if ($i -lt $lines.Count) { $lines[$i] } else { '## end-sentinel' }

            if ($line -match '^\s*```') { $inFence = -not $inFence; continue }
            if ($inFence) { continue }

            if ($line -match '^##\s+(.+?)\s*$') {
                if ($section) {
                    $r.Candidates++
                    # Parenthesised deliberately: inside a method-call argument list PowerShell
                    # splits on the comma first, so `ContainsKey('{0}||{1}' -f $a, $b)` passes TWO
                    # arguments and the format string never sees {1}.
                    $key = '{0}||{1}' -f $rel, $section
                    $seen[$key] = $cites
                    if ($cites -eq 0 -and -not $exempt.ContainsKey($key)) {
                        $r.Fail("$rel`:$startLine  section '$section' cites nothing -- give it a path to follow, or register it in sourcing.json with the reason it cannot have one")
                    }
                }
                $section = $Matches[1]
                $cites = 0
                $startLine = $i + 1
                continue
            }

            if ($section) {
                $toks = Get-CitationTokens -Line $line
                $cites += $toks.Count
            }
        }
    }

    # ── the reverse half ────────────────────────────────────────────────────────
    # An entry here exempts a section from having to cite anything. Both ways that exemption can
    # rot are silent, and the second is the dangerous one:
    #
    #   * the (file, section) pair no longer exists -- the heading was renamed or removed, so the
    #     entry exempts nothing. Dead weight, and worse: the NEXT section to take that heading
    #     inherits an exemption nobody granted it.
    #   * the section is still there and now CITES something -- the exemption is suppressing a
    #     check that would pass. It keeps working forever while meaning nothing.
    #
    # Checked after the walk rather than during it: an entry is only unused once every document in
    # scope has been read. Same shape and same reason as the external-citations reverse check.
    foreach ($key in $exempt.Keys) {
        $parts = $key -split '\|\|', 2
        $entry = $exempt[$key]
        if (-not $seen.ContainsKey($key)) {
            $r.Fail("sourcing.json exempts '$($parts[1])' in $($parts[0]), but no section by that name was found there -- the heading was renamed or removed and the exemption now covers nothing; remove it, or fix the section name. Reason on file: $($entry.reason)")
            continue
        }
        if ($seen[$key] -gt 0) {
            $r.Fail("sourcing.json exempts '$($parts[1])' in $($parts[0]) from needing a citation, but it now carries $($seen[$key]) -- the section came home and the exemption is suppressing a check that would pass; remove the entry")
        }
    }

    $r.Seal()
    return $r
}

# ── CHECK F -- NEGATIVE CLAIMS ARE STILL TRUE ───────────────────────────────────
# The inverse of every other check here. Those ask whether something asserted to exist can be
# found; this asks whether something asserted to be MISSING is still missing.
#
# A gap list is the one kind of prose that goes stale by being ACTED ON. "The replay validator does
# not exist as a script" was true when written and false the moment somebody wrote one, and nothing
# in the document changed. The gate cannot tell whether a gap has been CLOSED -- that is a
# judgement -- but it can tell whether the artifact a gap says is missing is now sitting in the
# tree, which is the part a reader cannot check without going and looking.
#
# Scoped to documents that cannot live under the main gate: a plan whose subject is the identifier
# classes to redact will never pass a redaction scan. Registry says which, and why.

function Test-Assertions {
    param([string]$RepoRoot, [hashtable]$Registry)

    $r = [CheckResult]::new('Assertions')

    foreach ($k in @('scope', 'negative_claim_markers')) {
        if (-not $Registry.ContainsKey($k)) {
            throw "assertions.json has no '$k' -- refusing to sweep with an unspecified $k"
        }
    }
    $markers = @($Registry.negative_claim_markers)
    if ($markers.Count -eq 0) {
        throw "assertions.json 'negative_claim_markers' is empty -- that would pass by checking nothing"
    }

    # CANDIDATES ARE NEGATIVE CLAIMS, NOT LINES. This counted lines, which made Seal() unreachable:
    # a scoped plan is a thousand-odd lines, so Candidates was always large and always non-zero,
    # and the check would have reported PASS with $negatives at 0. The failure that gets you there
    # is not exotic -- rewording "does not exist" to "is absent" in the plans, or narrowing a
    # marker, drops every match while leaving the documents in scope and the registry valid. The
    # extractor breaks and the gate says clean, which is the one outcome this file exists to
    # prevent, in the only check that was not counting the thing it tests.
    # NOT APPLICABLE is a different outcome from A REGISTRY POINTING AT NOTHING, and only one of
    # them is a defect. SOME of the scope missing means an entry outlived its document -- a real
    # finding, and the one this loop was written for. ALL of it missing means something else: this
    # registry was written for a different tree. A distribution ships tools/ and not the planning
    # documents, so a recipient running the documented command met six red lines about files they
    # were never sent, on their first run. That is how a gate teaches people to ignore it. Measured
    # against a simulated distribution 2026-08-16.
    $scope = @($Registry.scope)
    $present = @($scope | Where-Object { Test-Path -LiteralPath (Join-Path $RepoRoot $_) })
    if ($scope.Count -gt 0 -and $present.Count -eq 0) {
        $r.Status = 'SKIPPED'
        $r.Note = "none of the $($scope.Count) scoped document(s) is in this tree -- this registry was written for a different one. NOT RUN, and not a pass"
        return $r
    }

    $negatives = 0
    $linesRead = 0
    foreach ($rel in $scope) {
        $full = Join-Path $RepoRoot $rel
        if (-not (Test-Path -LiteralPath $full)) {
            # A scoped document that has been deleted or renamed is itself a finding: the registry
            # is now pointing at nothing, and silence would read as "nothing to check here".
            $r.Fail("$rel is in assertions.json scope but does not exist -- remove it from scope, or fix the path")
            continue
        }

        $lines = Read-Lines -Path $full
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            $linesRead++

            $hit = $null
            foreach ($m in $markers) { if ($line -like "*$m*") { $hit = $m; break } }
            if (-not $hit) { continue }
            $negatives++
            $r.Candidates++

            # A WINDOW, not a line. Prose wraps at ~95 characters, so the claim and the path it
            # names routinely land on different lines and a line-scoped check silently covers only
            # the ones that happened to fit.
            $window = ($lines[$i..([Math]::Min($i + 2, $lines.Count - 1))]) -join ' '

            # ...but an entry already marked resolved is not a stale claim, it is a record of one.
            # Without this the check fires hardest on exactly the entries somebody has just fixed,
            # which teaches people to stop marking them.
            if ($window -match '(?i)(~~|\bCLOSED\b|\bRESOLVED\b|\bDONE\b|no longer (true|open))') { continue }

            foreach ($t in (Get-CitationTokens -Line $window)) {
                $clean = ($t -split '#')[0].TrimEnd('/')
                if ([string]::IsNullOrWhiteSpace($clean)) { continue }
                if (Test-Path -LiteralPath (Join-Path $RepoRoot $clean)) {
                    $r.Fail("$rel`:$($i + 1)  says '$hit' of ``$clean``, which now EXISTS -- the gap was closed and the sentence was not")
                }
            }
        }
    }
    $r.Note = "$negatives negative claim(s) found and re-tested across $linesRead line(s)"
    $r.Seal()
    return $r
}

# ── CHECK B -- MEASURED FIGURES ARE DATED ────────────────────────────────────────
# A number that was measured is evidence; the same number undated is a claim about now. The
# document set's own rule is that a current count belongs nowhere, so every figure must say when.

function Test-Figures {
    param([string]$Root, [string]$RepoRoot, [hashtable]$Registry)

    $r = [CheckResult]::new('Figures')

    # Two kinds of number, and conflating them is what makes an undated figure defensible:
    #   measurement  evidence. Somebody ran something on a day. MUST carry an ISO date.
    #   illustration an anecdote or a derived/arithmetic value used to make a point. A date would
    #                be fabricated, so it is not demanded -- but the entry must say so out loud.
    # Without this split the only way to register an anecdote is to invent a measurement date for
    # it, which is precisely the failure this check exists to prevent.
    $exempt = @{}
    foreach ($e in $Registry.entries) {
        $key = '{0}||{1}' -f $e.file, $e.figure
        $exempt[$key] = $e
        if (-not $e.ContainsKey('kind') -or -not $e.ContainsKey('reason')) {
            $r.Fail("figures.json entry '$key' must carry 'kind' and 'reason' -- an escape hatch without a reason is a silencer")
            continue
        }
        if ($e.kind -notin @('measurement', 'illustration')) {
            $r.Fail("figures.json entry '$key' has kind '$($e.kind)' -- must be 'measurement' or 'illustration'")
        }
        if ($e.kind -eq 'measurement') {
            if (-not $e.ContainsKey('measured') -or $e.measured -notmatch '^\d{4}-\d{2}-\d{2}$') {
                $r.Fail("figures.json entry '$key' is a measurement, so 'measured' must be an ISO date -- got '$(if ($e.ContainsKey('measured')) { $e.measured } else { '<absent>' })'")
            }
            else {
                # Requiring a date and never expiring it buys one day of accuracy. Harness pins
                # have expired at 180 days since they were written; this registry demanded the
                # same evidence and then held it forever, so a figure measured two years ago read
                # exactly like one measured this morning. Same window, same reason, and the same
                # instruction: re-measure, do not just bump the date.
                $age = (Get-Date) - [datetime]::Parse($e.measured)
                if ($age.Days -gt $MaxFigureAgeDays) {
                    $r.Fail("figures.json entry '$key' was measured $($e.measured) -- $([int]$age.Days) days ago, over the $MaxFigureAgeDays-day limit. Re-measure it, do not just bump the date")
                }
            }
        }
    }

    # Measurement shapes. Deliberately narrow: a shape that fires on ordinary section numbering
    # would train the reader to ignore this gate.
    $shapes = @(
        '\b\d{1,3},\d{3}\b',              # 2,673   1,235
        '\b\d{1,3}\s?%',                  # 87%
        '\b\d+\s*(versus|vs\.?)\s*\d+\b', # 10 versus 12   10 vs 12
        '\b(versus|vs\.?)\s+\d{2,}\b',    # versus 534     vs 534
                                          # `vs` is not a synonym the author picks freely -- it is
                                          # the SAME figure written shorter. Watching only the long
                                          # spelling meant PLAN-external-share-pack.md could carry
                                          # "vs 534" outside this class entirely, and dating that
                                          # line did not bring it under the gate. Measured 2026-08-17.
        '~?\s?\b\d+\s?(ms|milliseconds)\b',
        '\b\d+\s?\xD7',                   # 100x -- U+00D7 as an ESCAPE, never as a literal.
                                          # A literal here put a non-ASCII byte inside a live
                                          # pattern: decode this file as anything but UTF-8 and the
                                          # class silently stops matching, which is indistinguishable
                                          # from a clean tree. The BOM makes the decode reliable; the
                                          # escape makes the pattern not depend on it.
        '\b\d{2,}\s+tests\b'
    )
    # Digit-boundary lookarounds, NOT \b. `_` is a word character, so \b never fires against an
    # underscore -- which meant `_measured 2026-08-16_`, the italic form this registry's own
    # _comment tells authors to use, was not recognised as a date at all. An author following the
    # documented advice was told to register an exemption instead, so the guidance quietly grew
    # the registry it exists to keep small. Found 2026-08-16 by writing a falsification that used
    # the recommended form and watching it pass for the wrong reason; one live instance already
    # existed in claude-permission-toolkit/README.md. The lookarounds accept the italic, bracketed
    # and trailing-punctuation forms while still refusing a date inside a longer run of digits.
    $isoDate = '(?<!\d)20\d\d-\d\d-\d\d(?!\d)'

    # Occurrences of each registered figure, so the reverse check below can tell "the figure is
    # gone" from "the figure is still there and now carries a date". Counted for every occurrence,
    # dated or not -- the forward check short-circuits on a dated paragraph, and a reverse check
    # built on that short-circuit would call a dated figure missing.
    $figSeen = @{}      # key -> total occurrences
    $figUndated = @{}   # key -> occurrences whose paragraph carries no date

    foreach ($file in Get-ScanFiles -Root $Root -Extensions @('.md')) {
        $rel = Get-RelPath -FullName $file.FullName -Root $RepoRoot
        $paras = Read-Paragraphs -Path $file.FullName      # assign first -- see caller contract
        foreach ($para in $paras) {
            if ([string]::IsNullOrWhiteSpace($para)) { continue }
            $paraHasDate = $para -match $isoDate
            foreach ($shape in $shapes) {
                foreach ($m in [regex]::Matches($para, $shape)) {
                    $fig = $m.Value.Trim()
                    $r.Candidates++
                    $key = '{0}||{1}' -f $rel, $fig
                    if ($exempt.ContainsKey($key)) {
                        $figSeen[$key] = 1 + $(if ($figSeen.ContainsKey($key)) { $figSeen[$key] } else { 0 })
                        if (-not $paraHasDate) {
                            $figUndated[$key] = 1 + $(if ($figUndated.ContainsKey($key)) { $figUndated[$key] } else { 0 })
                        }
                    }
                    if ($paraHasDate) { continue }
                    if ($exempt.ContainsKey($key)) { continue }
                    $snippet = ($para -replace '\s+', ' ')
                    if ($snippet.Length -gt 90) { $snippet = $snippet.Substring(0, 90) + '...' }
                    $r.Fail("$rel  figure '$fig' has no measurement date in its paragraph and is not registered -- $snippet")
                }
            }
        }
    }

    # ── the reverse half ────────────────────────────────────────────────────────
    # Same two rot modes as the citations and sourcing registries. An entry here exempts a figure
    # from carrying a date:
    #
    #   * the figure no longer appears in that file -- the number was edited, rounded or cut, so
    #     the entry exempts nothing and its recorded measurement date describes a figure that is
    #     not on the page any more.
    #   * the figure is still there and now carries a date in every paragraph that uses it -- the
    #     exemption is suppressing a check that would pass, and it will go on doing so silently.
    #
    # The second is the one that keeps a stale reason alive: an entry reading "derived, no date can
    # be given" outlives the day somebody gives it one.
    foreach ($key in $exempt.Keys) {
        $parts = $key -split '\|\|', 2
        $total = if ($figSeen.ContainsKey($key)) { $figSeen[$key] } else { 0 }
        $undated = if ($figUndated.ContainsKey($key)) { $figUndated[$key] } else { 0 }

        if ($total -eq 0) {
            $r.Fail("figures.json registers figure '$($parts[1])' in $($parts[0]), but no such figure appears there any more -- the number was changed or removed and the entry now covers nothing; remove it, or update it to the figure that replaced it")
            continue
        }
        if ($undated -eq 0) {
            $r.Fail("figures.json exempts figure '$($parts[1])' in $($parts[0]) from needing a date, but every paragraph using it now carries one -- the figure came home and the exemption is suppressing a check that would pass; remove the entry")
        }
    }

    $r.Seal()
    return $r
}

# ── CHECK C -- NO ORGANISATION IDENTIFIERS ───────────────────────────────────────
# Classes enumerated in PLAN-external-share-pack.md §3, and held in
# practice-gate/redaction-classes.json rather than in this file.
#
# THEY WERE INLINE HERE, and the comment defending that said a reader of the gate should see exactly
# what it forbids. That was right for as long as every reader was inside the organisation, and it
# inverts on publication: an annotated table of these patterns is every internal identifier this
# repository knows about, collected, deduplicated and captioned with why each one matters. It is a
# better reconnaissance map than the tree it guards -- the tree leaks an identifier by accident, and
# the table lists them on purpose. There is no sanitised middle: the patterns ARE the forbidden
# strings, and a class blurred enough to publish stops matching without saying so.
#
# So the real table is hold-listed out of every distribution and a generic
# redaction-classes.example.json ships in its place, which is what gives this check a fallback.
#
# THE FALLBACK IS NOT A CONVENIENCE, and it must not read like one. The example table forbids
# example-corp and acme_warehouse -- placeholder vocabulary that appears in nobody's tree -- so a
# run against it exercises the plumbing and certifies nothing about the recipient's identifiers.
# Same PASS line, materially weaker guarantee, and the only difference visible from outside is the
# note. Hence the note says which table was loaded on EVERY run, in both directions: silence about
# a downgrade is how the downgrade survives.
#
# AND WITH NEITHER FILE PRESENT THIS CHECK THROWS. A pattern table that failed to load produces an
# empty finding set, and an empty finding set is exactly what a clean tree produces; the two are
# indistinguishable from the outside. Same reasoning and the same shape as the empty
# harness_keywords set in check D -- refusing to sweep with nothing to sweep for.

function Import-RedactionClasses {
    # Resolution order, and the reason it is an order rather than a required file: a recipient has
    # only the example, this repository has both, and a recipient must not be handed a red gate for
    # being in the state the distribution puts them in. What they must not be handed is a green one
    # that reads like ours -- that is the caller's note, not this function's job.
    param([string]$GateDir)

    $real = Join-Path $GateDir 'redaction-classes.json'
    $example = Join-Path $GateDir 'redaction-classes.example.json'

    if (Test-Path -LiteralPath $real) { $path = $real; $source = 'real' }
    elseif (Test-Path -LiteralPath $example) { $path = $example; $source = 'example' }
    else {
        throw "no redaction class table in $GateDir -- neither redaction-classes.json nor redaction-classes.example.json is there, so the check has no patterns and would report PASS while forbidding nothing"
    }

    $name = [System.IO.Path]::GetFileName($path)
    $reg = Import-Registry -Path $path -Name $name -RequireKeys @('classes')
    $classes = @($reg.classes)
    if ($classes.Count -eq 0) {
        throw "$name has an empty 'classes' list -- that would pass by checking nothing"
    }
    return @{ Classes = $classes; Source = $source; File = $name }
}

function Test-Redaction {
    param([string]$Root, [string]$RepoRoot, [string]$GateDir)

    $r = [CheckResult]::new('Redaction')

    $loaded = Import-RedactionClasses -GateDir $GateDir
    $classes = @($loaded.Classes)

    # THE PATTERN TABLE IS TESTED FIRST, ON EVERY RUN, not only in the self-test. A regex that has
    # stopped matching -- edited, escaped wrong, or emptied -- forbids nothing, reports nothing, and
    # looks exactly like a clean tree. Each class carries an example it MUST catch; most carry the
    # near-miss the tree is allowed to keep, which it must NOT catch. Same property the share-pack
    # gate is built on, one file over.
    #
    # [regex]::IsMatch, NOT -match, AND THAT IS LOAD-BEARING. PowerShell's -match is
    # case-insensitive by default; the scan below uses [regex]::Match, which is not. 'portfolio
    # noun' deliberately carries no (?i), so a control written the idiomatic way would report that
    # class healthy against an example the scan itself walks straight past -- the marker-matching
    # trap in check D, arriving one check earlier.
    $active = [System.Collections.Generic.List[object]]::new()
    foreach ($c in $classes) {
        $label = if ($c.ContainsKey('name') -and -not [string]::IsNullOrWhiteSpace([string]$c.name)) { [string]$c.name } else { '(unnamed)' }
        $ok = $true
        foreach ($k in @('name', 'pattern', 'example', 'reason')) {
            if (-not $c.ContainsKey($k) -or [string]::IsNullOrWhiteSpace([string]$c[$k])) {
                # 'reason' is required for the same purpose it is required in every registry here:
                # a class nobody can justify is a class nobody can widen, narrow or strike.
                $r.Fail("$($loaded.File): class '$label' is missing required key '$k' -- an unnamed, unexplained or patternless class cannot be trusted to forbid anything")
                $ok = $false
            }
        }
        if (-not $ok) { continue }

        if (-not [regex]::IsMatch([string]$c.example, [string]$c.pattern)) {
            $r.Fail("$($loaded.File): class '$label' no longer matches its own example ('$($c.example)') -- the pattern is broken and this class forbids nothing")
            continue
        }
        if ($c.ContainsKey('counter_example') -and -not [string]::IsNullOrWhiteSpace([string]$c.counter_example)) {
            if ([regex]::IsMatch([string]$c.counter_example, [string]$c.pattern)) {
                $r.Fail("$($loaded.File): class '$label' matches its counter-example ('$($c.counter_example)'), which the tree is allowed to carry -- the pattern is too broad and would fail a clean tree")
                continue
            }
        }
        $active.Add([pscustomobject]@{ Name = $label; Pattern = [string]$c.pattern })
    }

    # Written before the scan so it is on the report whatever the verdict; Seal() replaces it only
    # in the zero-candidate case, where INCONCLUSIVE is the more urgent thing to say.
    #
    # BOTH BRANCHES OPEN WITH `table=<filename>`, AND THAT FIELD IS A CONTRACT, not a nicety. It was
    # added 2026-08-19 because the note was prose only, and prose is what nothing parses: the
    # share-pack gate wraps this one, prints "RESULT: PASS -- every check ran and passed", and had no
    # way to tell a run that scanned with the real table from a run that fell back to the placeholder
    # one -- so a pack could be certified clean by patterns that forbid example-corp and nothing
    # else, with the downgrade visible only to a human reading this note inside a delegated report.
    # It now parses this field and FAILS on the example table. Keep the field first, keep it
    # `table=` + the bare filename, and keep it in BOTH branches: a caller that cannot find it is
    # required to treat the run as unusable rather than to guess, so dropping it from either branch
    # turns the wrapper red rather than quiet, which is the correct direction and still a bug.
    if ($loaded.Source -eq 'example') {
        $r.Note = "table=$($loaded.File) -- PATTERNS FROM THE GENERIC STARTER TABLE, NOT this tree's own. It forbids placeholder vocabulary only, so a clean result here is not the guarantee the real table gives; write your classes into redaction-classes.json"
    }
    else {
        $r.Note = "table=$($loaded.File) -- $($active.Count) class(es), each verified against its own example"
    }

    # SELF-EXEMPTION, narrow and named. This file necessarily contains every string it forbids --
    # they are the patterns. Scanning it produced 8 findings against the only file in the tree that
    # cannot avoid them, which is the Read(**/*secret*) failure exactly: a rule so broadly written
    # that it blocks reading the guard itself. The resolution there was to narrow, not to delete,
    # so this exempts files by NAME rather than by a *gate* glob, and the self-test still plants a
    # personal path in a fixture to prove the class is caught elsewhere.
    #
    # The list grew to two on 2026-08-17, and the second name is the one to be careful about.
    # Test-SharePackClean.ps1 is the section 3 gate that CALLS this one, and its hold list is
    # section 2f written as paths -- which means it necessarily spells out the names of assets that
    # must never ship, one of which carries the organisation. Same argument as this file's own
    # exemption, one level out. Deliberately NOT written as 'Test-*.ps1': a glob would exempt every
    # future test file in the tree from the only check that reads it, which is how a narrow
    # exemption becomes a hole. A third name should have to be argued for here.
    #
    # THE THIRD AND FOURTH NAMES, argued for as that line demands. Both are class tables, and a class
    # table holds every string in every class by definition -- the same argument as this file's own
    # exemption, following the patterns into the data file they moved to. Nothing about the move
    # weakens or strengthens it. Two alternatives were rejected: assembling each pattern from
    # fragments at load time, the way the share-pack gate's secret examples are (the table is
    # documentation an internal reader has to be able to read, and a spliced regex is neither
    # reviewable nor obviously correct); and exempting the whole practice-gate directory (the reason a
    # glob was rejected above -- it would exempt every present and future registry from the only
    # check that reads them, and the siblings carry prose, paths and quoted findings that must stay
    # scanned).
    #
    # THE EXAMPLE TABLE IS EXEMPT UNCONDITIONALLY, AND IT WAS NOT MEANT TO BE. The first cut left it
    # scanned, on the reasoning that a generic file's cleanliness is a claim worth checking rather
    # than an impossibility -- and that held for exactly as long as the real table was present. Take
    # the real table away, which is the state every distribution is in, and the example table becomes
    # the ACTIVE one: its patterns then match its own examples, and a recipient's first run reports
    # findings against the starter file the pack has just told them to copy -- 15 of them, measured
    # 2026-08-19 by taking the real table away and running the gate. Red for the wrong reason, on the
    # one run that has to teach them what the gate is for.
    #
    # The exemption is therefore by NAME and not by role, even though by-role is what the reasoning
    # actually says. Test-SharePackClean.ps1 parses this list out of this line to cross-check its own
    # enumeration of the scan against the count reported here; a name added conditionally at run time
    # is invisible to that parse, so the two counts would disagree by one and the caller would fail
    # with a message about drifting scopes. A static list that is occasionally broader than it needs
    # to be beats a dynamic one that lies to the check built to catch exactly this.
    #
    # WHAT THAT COSTS, stated rather than left to be discovered: nothing in this gate reads the
    # starter table for real identifiers. It is generic by construction, it is reviewed by eye, and
    # the share-pack gate's own secret sweep and gitleaks pass still read it -- but if somebody writes
    # a live hostname into an example there, this check is not what catches it.
    # THE FIFTH NAME, argued for as the line above demands. hold-classes.json is the share-pack
    # gate's hold list, moved out of that gate into a data file on 2026-08-19 for exactly the reason
    # the redaction classes moved out of this one -- and it inherits this exemption for exactly the
    # reason the second name has it, because it IS the second name's content. Two of its classes are
    # a directory that names the internal distribution route and a filename prefix that carries the
    # organisation; a path-shaped class has nowhere to put a name except the pattern and the worked
    # example, so the file cannot be written any other way. Scanning it reports the table rather than
    # the tree.
    #
    # Its .example sibling is deliberately NOT on this list, and the asymmetry with the redaction
    # pair is the interesting part. redaction-classes.example.json had to be exempted
    # unconditionally because taking the real table away makes the example table ACTIVE -- its own
    # examples then match its own patterns. Nothing does that to a hold list: it is matched against
    # PATHS, never against file contents, so hold-classes.example.json is never its own subject. It
    # is generic by construction and it ships, so it is scanned like any other shipped file -- which
    # is what catches the day somebody writes a real internal directory into a starter example.
    $selfNames = @('Test-PracticeClaims.ps1', 'Test-SharePackClean.ps1', 'redaction-classes.json', 'redaction-classes.example.json', 'hold-classes.json')

    # .template is in this list because a template is a document with a placeholder in it, not a
    # different kind of artifact: CLAUDE.md.template is prose that ships, and until 2026-08-17 its
    # extension put it outside every check here. Found by the share-pack gate's coverage check on
    # its first run, which is what that check is for -- an extension-scoped scan cannot see the
    # files it does not scan, and neither can its author.
    foreach ($file in Get-ScanFiles -Root $Root -Extensions @('.md', '.py', '.ps1', '.psd1', '.json', '.yml', '.yaml', '.txt', '.template')) {
        if ($selfNames -contains $file.Name) { continue }
        $r.Candidates++
        $rel = Get-RelPath -FullName $file.FullName -Root $RepoRoot
        $lines = Read-Lines -Path $file.FullName
        for ($i = 0; $i -lt $lines.Count; $i++) {
            # $active, not $classes: a class that failed its own controls above has already been
            # reported and is deliberately not swept with. Scanning on a pattern known to be broken
            # would add its silence to the report as though it were coverage.
            foreach ($class in $active) {
                $m = [regex]::Match($lines[$i], $class.Pattern)
                if ($m.Success) {
                    $r.Fail("$rel`:$($i + 1)  $($class.Name) -- '$($m.Value)'")
                }
            }
        }
    }
    $r.Seal()
    return $r
}

# ── CHECK D -- HARNESS CLAIMS ARE PINNED ─────────────────────────────────────────
# This check does not and must not evaluate whether a claim is TRUE. It asserts that a claim about
# Claude Code's own behaviour names the version and date it was last verified against -- which is
# the only property a script can hold, and the one that was missing when a harness claim on this
# page went false.
#
# Three assertions:
#   1. every registered pin still points at prose that exists   (a stale registry is drift)
#   2. every registered pin was verified within -MaxPinAgeDays  (freshness)
#   3. every line carrying a harness keyword is covered by some pin  (over-flags on purpose:
#      the resolution is to register the claim, and registering it forces somebody to look it up)

function Test-HarnessPins {
    param([string]$Root, [string]$RepoRoot, [hashtable]$Registry)

    $r = [CheckResult]::new('HarnessPins')

    if (-not $Registry.ContainsKey('harness_keywords')) {
        throw "verified-against.json has no 'harness_keywords' -- refusing to sweep with an empty keyword set"
    }
    $keywords = @($Registry.harness_keywords)
    if ($keywords.Count -eq 0) {
        throw "verified-against.json 'harness_keywords' is empty -- that would pass by checking nothing"
    }

    # SCOPE IS AN OPT-OUT, NOT AN OPT-IN, and that inversion was earned.
    #
    # This was a whitelist -- `sweep_scope`, a list of documents that make harness claims. A
    # whitelist fails in the one direction nobody notices: a document nobody remembers to add is
    # exempt from the only check that dates its claims, and it is exempt SILENTLY, because a
    # missing entry looks exactly like a document with nothing to pin. It bit twice. A shipped
    # toolkit README asserted a loader behaviour that had since become false and no pin was ever
    # demanded of it, because it had never been listed.
    #
    # The original narrowing had a real reason at the time -- sweeping the toolkit READMEs produced
    # 15 findings against one document that asserts nothing about the harness. But the keyword set
    # was itself narrowed afterwards (see _keyword_note) from vocabulary to behavioural assertions,
    # which removed that reason, and nobody re-measured. Measured again 2026-08-16 against every
    # markdown file under tools/: widening costs 3 findings, not 15, and two of those three were
    # keywords inside a fenced example rather than claims at all.
    #
    # So: every document is swept unless an exclusion says otherwise, each exclusion carries the
    # reason it cannot be pinned, a stale exclusion is itself a finding, and the whole list is
    # printed on every run -- which the note in the registry used to claim and the code did not do.
    if (-not $Registry.ContainsKey('sweep_exclusions')) {
        throw "verified-against.json has no 'sweep_exclusions' -- the sweep is an opt-out list; an absent key would silently sweep nothing or everything depending on the reader's assumption"
    }
    $exclusions = @($Registry.sweep_exclusions)
    $exclusionHit = @{}
    foreach ($x in $exclusions) {
        $r.Candidates++
        foreach ($k in @('path', 'reason')) {
            if (-not $x.ContainsKey($k)) {
                $r.Fail("sweep_exclusions entry is missing required key '$k' -- a document exempted from the pin sweep without a stated reason is an oversight, not a decision")
            }
        }
        if ($x.ContainsKey('path')) { $exclusionHit[$x.path] = $false }
    }

    $docs = @(Get-ScanFiles -Root $Root -Extensions @('.md') | Where-Object {
            $rel = Get-RelPath -FullName $_.FullName -Root $RepoRoot
            $keep = $true
            foreach ($x in $exclusions) {
                if ($x.ContainsKey('path') -and $rel -like $x.path) {
                    $exclusionHit[$x.path] = $true
                    $keep = $false
                    break
                }
            }
            $keep
        })

    # An exclusion matching nothing is the mirror of a pin matching no prose: the document was
    # renamed or deleted and the exemption outlived it, so the next file to land on that path
    # inherits an exemption nobody granted it.
    foreach ($p in $exclusionHit.Keys) {
        if (-not $exclusionHit[$p]) {
            $r.Fail("sweep_exclusions entry '$p' matches no document under $Root -- the exemption outlived the file it was written for; remove it, or fix the path")
        }
    }

    if ($docs.Count -eq 0) {
        # Scope that matches nothing is the projection-drops-everything failure: a smaller table,
        # not an error. Return INCONCLUSIVE here rather than falling through -- with no prose to
        # search, every pin would report "matches no prose" and the operator would be sent to fix
        # a registry that is fine. A gate that is red for the wrong reason costs as much as one
        # that is green for the wrong reason.
        $r.Status = 'INCONCLUSIVE'
        $r.Note = "every document under $Root is excluded -- the exclusion list has swallowed the sweep"
        return $r
    }

    # The limit is printed on EVERY run, not only when it bites. The registry note used to claim
    # this and the code did not do it: the narrowing was set once and then lived only in a data
    # file nobody opens, which is the same silence the exclusions themselves are designed against.
    $r.Note = "swept $($docs.Count) document(s); $($exclusions.Count) excluded by registry"
    # Normalise line endings before any marker matching. This repo is checked out CRLF on the
    # Windows runner and edited LF here, so a marker that happens to span a line break would match
    # locally and silently stop matching in CI -- reporting "the claim was reworded" about prose
    # nobody touched. Markers are compared against LF text on every substrate.
    $allText = (($docs | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }) -join "`n") -replace "`r`n", "`n"

    # 1 + 2 -- registry health
    foreach ($e in $Registry.entries) {
        $r.Candidates++
        foreach ($k in @('id', 'claim', 'verified_against', 'verified_on', 'source', 'markers')) {
            if (-not $e.ContainsKey($k)) {
                $r.Fail("pin '$($e.id)' is missing required key '$k'")
            }
        }
        if ($e.ContainsKey('verified_on')) {
            $age = (Get-Date) - [datetime]::Parse($e.verified_on)
            if ($age.Days -gt $MaxPinAgeDays) {
                $r.Fail("pin '$($e.id)' was last verified $($e.verified_on) -- $([int]$age.Days) days ago, over the $MaxPinAgeDays-day limit. Re-verify against $($e.source), do not just bump the date")
            }
        }
        if ($e.ContainsKey('markers')) {
            # -cmatch, NOT -match. See the MARKERS ARE CASE-SENSITIVE note above check 3.
            $found = $false
            foreach ($mk in @($e.markers)) { if ($allText -cmatch [regex]::Escape($mk)) { $found = $true; break } }
            if (-not $found) {
                $r.Fail("pin '$($e.id)' matches no prose -- the claim was reworded or removed and the pin is now stale")
            }
        }
    }

    # 3 -- unpinned harness claims
    #
    # MARKERS ARE CASE-SENSITIVE (-cmatch), AND THE KEYWORDS DELIBERATELY ARE NOT.
    #
    # PowerShell's -match is case-INSENSITIVE by default, and markers are short literal phrases, so
    # a marker could cover prose it had nothing to do with. Found 2026-08-17 by a falsification that
    # did not fire: the sentence "For each memory, the first match wins" -- in a document about
    # memory TIERING -- was reported as covered, because the permission-ordering pin carries the
    # marker "First match wins". The keyword fired, the marker absorbed it, and a claim about one
    # mechanism was silently pinned to a claim about a different one. Nothing failed.
    #
    # That is this registry's own `_keyword_note` trap arriving one level in. It had already been
    # met on the KEYWORD side -- `statusLine` carries an explicit (?-i) because the camelCase
    # spelling is a settings key and the spaced lowercase one is an ordinary English noun -- and the
    # marker side never got the same treatment. Two pins carry both capitalisations of the same
    # phrase as separate markers, which is redundant under -match and is evidence the author
    # believed matching was already case-sensitive.
    #
    # The asymmetry is intentional and is the part to not "tidy up" later:
    #   markers  are LITERAL substrings of prose, regex-escaped. Case is part of the quotation, so
    #            an inexact match is a different sentence. -cmatch.
    #   keywords are REGEXES, written per-keyword, and carry their own inline flags where case
    #            matters. Forcing case-sensitivity on them would break \bEsc\b and make (?-i)
    #            meaningless. Left on -match.
    #
    # Measured before the change, across every markdown file under tools/: 0 pins lose their prose
    # and 0 lines were relying on a case-insensitive hit. The blast radius was nil, so this is a
    # tightening with no migration -- but it is the kind of change that only stays correct while
    # somebody keeps quoting markers exactly, hence the two self-test controls in both polarities.
    $markerPatterns = [System.Collections.Generic.List[string]]::new()
    foreach ($e in $Registry.entries) {
        if ($e.ContainsKey('markers')) { foreach ($mk in @($e.markers)) { $markerPatterns.Add([regex]::Escape($mk)) } }
    }

    foreach ($file in $docs) {
        $rel = Get-RelPath -FullName $file.FullName -Root $RepoRoot
        if ($rel -match 'VERIFIED-AGAINST\.md$') { continue }
        $lines = Read-Lines -Path $file.FullName
        $inFence = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]

            # A keyword inside a fenced block is being DEMONSTRATED, not asserted. A document
            # showing what a `paths:` rule file looks like is not claiming anything about how the
            # harness treats one, and demanding a pin for it sends the reader to date a code
            # sample. Test-Sourcing has skipped fences since it was written; this check did not,
            # and the inconsistency was invisible for as long as the sweep was narrow enough never
            # to meet a fenced example. Widening the sweep is what surfaced it.
            if ($line -match '^\s*```') { $inFence = -not $inFence; continue }
            if ($inFence) { continue }

            $hit = $null
            foreach ($k in $keywords) { if ($line -match $k) { $hit = $k; break } }
            if (-not $hit) { continue }
            $r.Candidates++
            $covered = $false
            foreach ($p in $markerPatterns) { if ($line -cmatch $p) { $covered = $true; break } }
            if (-not $covered) {
                $r.Fail("$rel`:$($i + 1)  unpinned harness claim (keyword '$hit') -- register it in verified-against.json with the version and date it was checked")
            }
        }
    }
    $r.Seal()
    return $r
}

# ── CHECK G -- PRIOR ART IS STILL CITED ──────────────────────────────────────────
# Attribution is the one claim in this pack a reader cannot check by running something, and it rots
# in a way none of the other registries do: it DECORATES. It gets written once for credit, the field
# moves, and it sits on the page flattering nobody while looking exactly like diligence. Nothing
# here would ever have gone red for that -- a paragraph of goodwill cites no path, states no figure
# and asserts nothing about the harness, so checks A through F are all silent about it.
#
# So: the same both-directions shape the citation, sourcing and figures registries already carry.
#
#   forward  every path in `cited_in` exists AND the document at it contains the `work` string
#            VERBATIM. An entry naming a document that does not mention the work is a claim nobody
#            made, and it is the failure mode that looks best from outside -- the registry is full,
#            the reasons read well, and the paragraph they describe was deleted a release ago.
#   reverse  something under the scanned root cites the work at all. An entry nothing cites FAILS
#            AS STALE rather than persisting while covering nothing. This is the half that makes the
#            file a registry instead of a list, and it is the quieter of the two: a dead entry is
#            indistinguishable from a live one by reading it.
#
# VERBATIM MEANS ORDINAL AND CASE-SENSITIVE -- String.Contains, not -match. Same decision markers
# got in check D and for the same reason: a name quoted almost-exactly is a different string, and
# only the exact one is checkable. prior-art.json's own header records the corollary, which is a
# constraint on the DATA rather than on this code: each `work` is a plain substring of the prose,
# carrying no publisher suffix the prose never writes, precisely so this match can be exact. Do not
# "tidy" those values and do not soften this to a fuzzy compare -- a fuzzy reverse check is a
# reverse check that passes.
#
# AND IT REFUSES AN EMPTY REGISTRY. Import-Registry already throws on a file that is missing or will
# not parse; this throws on a parseable one holding no entries, because zero attributions and a pack
# with nothing to attribute produce the same report, and one of them is a pack that quietly stopped
# acknowledging the field it was published into. Same shape, same wording, as the empty
# harness_keywords refusal in check D.
#
# WHAT THIS COSTS, stated rather than left to be discovered: a scan root that does not hold the
# citing documents fails every entry at once. There is no per-entry `root` escape hatch here -- the
# one external-citations.json grew for exactly this problem -- because the data file is not this
# check's to edit, and inventing a default would mean guessing which roots an entry answers to. The
# runs that gate anything (the full gate over tools/, and the share-pack gate over a staged bundle)
# both carry the documents; a narrower root has to say so with -Only.

function Test-PriorArt {
    param([string]$Root, [string]$RepoRoot, [hashtable]$Registry)

    $r = [CheckResult]::new('PriorArt')

    $entries = @($Registry.entries)
    if ($entries.Count -eq 0) {
        throw "prior-art.json has no entries -- an attribution registry with nothing in it would pass by checking nothing, which is exactly how an acknowledgement section dies quietly"
    }

    $required = @('work', 'url', 'version_checked', 'date_checked', 'relationship', 'claim', 'cited_in', 'reason')
    # A field filled with a placeholder is worse than an absent one: it satisfies a presence check
    # while recording nothing, and it reads as considered. Same refusal the skill lint makes of a
    # description that says TBD.
    $placeholders = @('TBD', 'TODO', 'None', 'N/A', '-')
    # complementary / convergent / contrast, and the value is where the honesty lives. convergent is
    # the strongest evidence either work has and is only worth counting because the authorship was
    # independent; contrast has to be stated as a difference and not as a verdict. An unrecognised
    # value is an unstated claim, so it fails rather than being passed through.
    $relationships = @('complementary', 'convergent', 'contrast')

    # The tree, read ONCE. The reverse half asks whether ANY document mentions each work, and a walk
    # per entry is the same walk N times -- with the extra defect that two entries could disagree
    # about which files exist if the walks were ever written differently.
    $docs = @{}
    foreach ($f in Get-ScanFiles -Root $Root -Extensions @('.md')) {
        $rel = Get-RelPath -FullName $f.FullName -Root $RepoRoot
        # CRLF normalised for the reason check D normalises before marker matching: a `work` is
        # compared against file text on both substrates and must not depend on the checkout.
        $docs[$rel] = ([System.IO.File]::ReadAllText($f.FullName) -replace "`r`n", "`n")
    }
    if ($docs.Count -eq 0) {
        # No prose at all is the projection-drops-everything case, not a defect in the registry:
        # every entry would report stale and send the operator to fix a file that is fine.
        $r.Status = 'INCONCLUSIVE'
        $r.Note = "no markdown document under $Root -- there is nothing an attribution could be cited in, so 'nothing cites this' would be true of a perfectly healthy registry"
        return $r
    }

    foreach ($e in $entries) {
        $label = if ($e.ContainsKey('work') -and -not [string]::IsNullOrWhiteSpace([string]$e.work)) { [string]$e.work } else { '(unnamed work)' }
        $r.Candidates++

        $shapeOk = $true
        foreach ($k in $required) {
            if (-not $e.ContainsKey($k)) {
                $r.Fail("prior-art.json entry '$label' is missing required key '$k' -- an attribution with no version, date, relationship or reason is a compliment, not a citation")
                $shapeOk = $false
                continue
            }
            # cited_in is a list and every other field is a scalar, so both go through @() and the
            # same emptiness rules apply to each element. A cited_in of [] is an entry claiming to be
            # cited nowhere, which is the reverse check's finding stated in the data.
            $vals = @($e[$k])
            if ($vals.Count -eq 0) {
                $r.Fail("prior-art.json entry '$label' has an empty '$k'")
                $shapeOk = $false
                continue
            }
            foreach ($v in $vals) {
                $s = [string]$v
                if ([string]::IsNullOrWhiteSpace($s)) {
                    $r.Fail("prior-art.json entry '$label' has a blank value in '$k'")
                    $shapeOk = $false
                }
                elseif ($placeholders -contains $s.Trim()) {
                    $r.Fail("prior-art.json entry '$label' has placeholder '$($s.Trim())' in '$k' -- a placeholder passes a presence check and records nothing, which is worse than leaving the field out")
                    $shapeOk = $false
                }
            }
        }
        # Nothing below can be trusted about an entry whose shape failed: reading date_checked off an
        # entry that has none, or matching prose against a blank `work` (which every document
        # trivially contains), would report a second finding about the first one.
        if (-not $shapeOk) { continue }

        if ($e.relationship -notin $relationships) {
            $r.Fail("prior-art.json entry '$label' claims relationship '$($e.relationship)' -- must be one of $($relationships -join ', ')")
        }

        if ([string]$e.date_checked -notmatch '^\d{4}-\d{2}-\d{2}$') {
            $r.Fail("prior-art.json entry '$label' has date_checked '$($e.date_checked)' -- must be an ISO date, or nothing can say how old the reading is")
        }
        else {
            $when = [datetime]::Parse([string]$e.date_checked)
            if ($when.Date -gt (Get-Date).Date) {
                $r.Fail("prior-art.json entry '$label' records date_checked '$($e.date_checked)', which is in the future -- a date nobody could have read on is not evidence of a reading")
            }
            else {
                # Expired for the reason a harness pin expires, on the same window: this is a claim
                # about a moving artifact, and demanding a date while never expiring it buys one day
                # of accuracy. Re-fetch the work, then set the date -- bumping it alone is the drift.
                $age = (Get-Date) - $when
                if ($age.Days -gt $MaxPinAgeDays) {
                    $r.Fail("prior-art.json entry '$label' was last read $($e.date_checked) -- $([int]$age.Days) days ago, over the $MaxPinAgeDays-day limit. Re-fetch it at its current version, do not just bump the date")
                }
            }
        }

        $work = [string]$e.work

        # ── forward ─────────────────────────────────────────────────────────────
        foreach ($p in @($e.cited_in)) {
            $r.Candidates++
            $rel = (([string]$p).Trim()) -replace '\\', '/'
            $full = $null
            foreach ($cand in @((Join-Path $RepoRoot $rel), (Join-Path $Root $rel))) {
                if (Test-Path -LiteralPath $cand -PathType Leaf) { $full = $cand; break }
            }
            if (-not $full) {
                # Last resort, by BASENAME and only when it is unambiguous -- the same fallback
                # check A uses for a bare script name. A distribution is entitled to a different
                # layout, and a check that reads a relocation as a deletion is red for the wrong
                # reason. Two matches is not a resolution, so it stays unresolved and reports.
                $leaf = [System.IO.Path]::GetFileName($rel)
                $hits = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter $leaf -ErrorAction SilentlyContinue)
                if ($hits.Count -eq 1) { $full = $hits[0].FullName }
            }
            if (-not $full) {
                $r.Fail("prior-art.json entry '$label' says it is cited in '$rel', which does not exist -- the document was renamed or removed and the attribution now points at nothing")
                continue
            }
            $text = ([System.IO.File]::ReadAllText($full) -replace "`r`n", "`n")
            if (-not $text.Contains($work)) {
                $r.Fail("prior-art.json entry '$label' names '$rel' as citing it, and that document does not contain '$work' -- an entry naming a document that never mentions the work is a claim nobody made; fix the path, quote the work exactly, or strike the entry")
            }
        }

        # ── reverse ─────────────────────────────────────────────────────────────
        # Deliberately a sweep of the WHOLE root rather than a re-read of cited_in: the two halves
        # have to be able to disagree. A document that dropped the mention while a sibling kept it
        # fails forward and passes here, which is the finding "your cited_in is out of date" rather
        # than "this attribution is dead", and they are different repairs.
        $r.Candidates++
        $citing = @($docs.Keys | Where-Object { $docs[$_].Contains($work) })
        if ($citing.Count -eq 0) {
            $r.Fail("prior-art.json registers '$label' and no document under $Root mentions it -- the attribution outlived the paragraph it was written for and is now collecting credit for a comparison that has been deleted; restore the citation, or strike the entry")
        }
    }

    $r.Note = "$($entries.Count) attribution(s) checked in both directions across $($docs.Count) document(s)"
    $r.Seal()
    return $r
}

# ── CHECK H -- THE FRONT DOOR ENUMERATES EVERY UNIT ──────────────────────────────
# Every check above reads the prose and asks whether what it SAYS is true. This one asks whether it
# says enough, which is a different failure and the only one none of the others can see.
#
# The repository README carries a section enumerating what is under tools/. It was complete when it
# was written and went incomplete as units were added -- seven described against thirteen entries on
# disk -- and the newest of the three it never mentioned was the only unit that makes any of the
# practice actually fire. Nothing here went red. It could not: an enumeration-by-example rots in the
# one direction no other check looks, because everything it DOES name still resolves. Citations
# passed, sections were sourced, figures were dated, and the omission was invisible from inside a
# green run. Third occurrence of that defect class in this repository -- a remembered list of
# shipped scripts that said six when it was nine, and a whitelisted pin sweep that exempted whatever
# nobody remembered to add, are the other two, and both were fixed by enumerating from the tree and
# checking the registry BOTH WAYS. So is this.
#
#   forward  every entry directly under the scanned root is named in the section, or is registered
#            in practice-gate/front-door.json with the reason it deliberately is not.
#   reverse  every unit the section names exists. The quieter half: a row pointing at a directory
#            somebody renamed reads exactly like a row pointing at one that is still there.
#
# IT REACHES OUTSIDE THE SCANNED ROOT, and that is not a new liberty -- check F already reads
# planning documents that could never survive a redaction scan, and its scope is a registry rather
# than a tree walk. Same shape here, and the same cost: a root that does not hold the front door
# cannot answer the question. What it must not do is guess.
#
# SO APPLICABILITY IS DECIDED BY A MARKER, AND THE MARKER IS NOT THE SECTION HEADING. A distribution
# carries a README.md at its root as well, and it is a DIFFERENT DOCUMENT -- the pack's front door
# is authored under another name and renamed on the way in, because this repository already has a
# README.md. A check keyed on "is there a README.md here" would read the pack's front door, not find
# a section that was never in it, and report the pack broken. It keys on the SOURCE name instead,
# which the builder asserts is nowhere on disk in a built pack: present means this tree is the
# repository the front door belongs to, absent means it is not, and the answer is SKIPPED -- never
# a pass, and registered as a bundle boundary in share-pack.json so the day that changes the entry
# fails as stale.
#
# Keying on the heading would have been simpler and it inverts the whole check: a mangled or deleted
# heading would then be indistinguishable from a distribution, and the section this check exists to
# police would switch it off by disappearing. So in a tree that HAS the marker, a missing heading is
# a FAIL that quotes the heading it looked for, and a unit list that comes back empty refuses
# outright rather than reporting a section that documents nothing as complete.

function Test-FrontDoor {
    param([string]$Root, [string]$RepoRoot, [hashtable]$Registry)

    $r = [CheckResult]::new('FrontDoor')

    # Same refusals, same wording, as the empty harness_keywords set in check D and the empty
    # attribution registry in check G. A blank front door, a blank heading or a blank marker each
    # leave this check scanning for nothing, and scanning for nothing is indistinguishable from a
    # complete section.
    foreach ($k in @('front_door', 'section_heading', 'repository_marker')) {
        if ([string]::IsNullOrWhiteSpace([string]$Registry[$k])) {
            throw "front-door.json has a blank '$k' -- refusing to check a front door, a section or a tree it cannot name"
        }
    }
    foreach ($k in @('worked_example', 'counter_example')) {
        $ctl = $Registry[$k]
        if ($null -eq $ctl -or -not $ctl.ContainsKey('unit') -or [string]::IsNullOrWhiteSpace([string]$ctl.unit) -or
            -not $ctl.ContainsKey('reason') -or [string]::IsNullOrWhiteSpace([string]$ctl.reason)) {
            throw "front-door.json '$k' needs a non-blank 'unit' and 'reason' -- a control with no subject asserts nothing, and one with no reason cannot be widened, narrowed or struck"
        }
    }

    $frontDoor = [string]$Registry.front_door
    $heading = [string]$Registry.section_heading
    $marker = [string]$Registry.repository_marker

    # APPLICABILITY FIRST, before anything is enumerated or read. Deciding this after the tree walk
    # would mean a distribution's differently-shaped tools/ produced findings that were then thrown
    # away, and a check that computes findings it discards is one edit from reporting them.
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $marker))) {
        $r.Status = 'SKIPPED'
        $r.Note = "no $marker beside $RepoRoot -- the README.md here is a distribution's front door and not the repository's, which is a different document. NOT RUN, and not a pass"
        return $r
    }

    $doorPath = Join-Path $RepoRoot $frontDoor
    if (-not (Test-Path -LiteralPath $doorPath -PathType Leaf)) {
        $r.Fail("$marker is here, so this is the repository -- and there is no $frontDoor at $RepoRoot. The front door is the one document this check is about; a tree missing it cannot be reported complete")
        return $r
    }

    # ENUMERATED FROM THE TREE, NEVER FROM A LIST, which is the entire remedy for this defect class.
    # Directories AND files at the top level, because four of the thirteen units are single scripts
    # and a directory-only walk would have exempted every one of them. Build residue is dropped by
    # the same names Get-ScanFiles drops, so the two walks cannot disagree about what counts as
    # content.
    $onDiskNames = @(Get-ChildItem -LiteralPath $Root -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '^(__pycache__|node_modules|\.git)$' } |
        ForEach-Object { $_.Name } | Sort-Object)
    if ($onDiskNames.Count -eq 0) {
        throw "nothing to enumerate under $Root -- an empty unit list would agree with every section ever written, including one that documents nothing"
    }
    # ORDINAL SETS, case included, and that is a decision rather than an idiom. PowerShell's
    # -contains is case-INSENSITIVE, so a row spelled with the wrong case would satisfy this check
    # and still be a link that 404s on a case-sensitive forge -- which is where this README is read.
    $onDisk = [System.Collections.Generic.HashSet[string]]::new([string[]]$onDiskNames, [System.StringComparer]::Ordinal)

    # THE SECTION, delimited by the next level-2 heading. `^## ` and not `^##`: the section carries
    # level-3 subheadings of its own, and a terminator that stopped at the first of those would read
    # one table out of two and report every unit in the second as undocumented.
    $lines = Read-Lines -Path $doorPath
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].TrimEnd() -eq $heading) { $start = $i; break }
    }
    if ($start -lt 0) {
        $r.Fail("$frontDoor has no line reading exactly '$heading' -- the section this check is about is gone or was renamed, and a front door with no unit list must not be reported complete. Restore the heading, or change section_heading in front-door.json to the one it now carries")
        return $r
    }
    $end = $lines.Count
    for ($i = $start + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^## ') { $end = $i; break }
    }
    $section = ($lines[($start + 1)..($end - 1)]) -join "`n"

    # THE WHOLE SECTION, not just its tables. Three of the units are documented in prose below the
    # tables rather than in a row, and demanding a table row would have failed a section that
    # describes them at length. What is being asserted is that the front door MENTIONS each unit
    # where a reader will find it, which is what the section is.
    $documentedNames = @([regex]::Matches($section, '(?<![A-Za-z0-9._-])tools/(?<n>[A-Za-z0-9][A-Za-z0-9._-]*)') |
        ForEach-Object { $_.Groups['n'].Value } | Sort-Object -Unique)
    $documented = [System.Collections.Generic.HashSet[string]]::new([string[]]$documentedNames, [System.StringComparer]::Ordinal)
    if ($documented.Count -eq 0) {
        $r.Fail("the '$heading' section of $frontDoor names no unit under $Root at all -- either the section was emptied or the extractor has stopped matching, and both look exactly like a tree with nothing in it")
        return $r
    }

    # The exemptions, shape-checked before they are trusted to excuse anything. An entry with no
    # reason is a silencer, which is the same refusal the sweep exclusions in check D make.
    $exempt = @($Registry.exempt)
    $exemptNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($e in $exempt) {
        if ($null -eq $e -or -not $e.ContainsKey('entry') -or [string]::IsNullOrWhiteSpace([string]$e.entry)) {
            $r.Fail("front-door.json has an exempt entry with no 'entry' -- an exemption that names nothing excuses everything or nothing, and neither is a decision")
            continue
        }
        if (-not $e.ContainsKey('reason') -or [string]::IsNullOrWhiteSpace([string]$e.reason)) {
            $r.Fail("front-door.json exempts 'tools/$($e.entry)' with no stated reason -- an entry left out of the front door without one is an oversight, not a decision")
        }
        $null = $exemptNames.Add([string]$e.entry)
    }

    # ── the controls, asserted on every run ─────────────────────────────────────
    # Not self-test-only, for the reason every class table here proves itself before it scans: a
    # comparison that has stopped matching produces an empty finding set, and an empty finding set
    # is exactly what a complete section produces.
    $we = [string]$Registry.worked_example.unit
    $r.Candidates++
    if (-not $onDisk.Contains($we)) {
        $r.Fail("the registered worked example 'tools/$we' is not under $Root -- it was chosen as the unit whose omission this check exists for, so a run that cannot find it is a run whose PASS means nothing. Point worked_example at a unit that is there")
    }
    if (-not $documented.Contains($we)) {
        $r.Fail("the registered worked example 'tools/$we' is not named in the '$heading' section -- the positive control did not fire, so this check is not measuring what it claims to")
    }

    $ce = [string]$Registry.counter_example.unit
    $r.Candidates++
    $extends = @($onDiskNames | Where-Object { $ce.StartsWith($_, [System.StringComparison]::Ordinal) -and $ce -ne $_ })
    if ($extends.Count -eq 0) {
        $r.Fail("the registered counter-example 'tools/$ce' is not an extension of any entry under $Root, so asserting that it does not resolve proves nothing -- it exists to prove the comparison is EXACT rather than prefix-wise, and a name that was never a candidate for the loose match cannot show that. Pick a real unit's name with a token appended")
    }
    if ($onDisk.Contains($ce)) {
        $r.Fail("the registered counter-example 'tools/$ce' now EXISTS -- it was picked as a near-miss that resolves against nothing, so either document it as a unit and pick another near-miss, or rename it")
    }
    if ($documented.Contains($ce)) {
        $r.Fail("the '$heading' section names 'tools/$ce', which was registered as a near-miss that resolves against nothing -- the section has acquired a row for a unit that does not exist")
    }

    # ── forward ─────────────────────────────────────────────────────────────────
    foreach ($name in $onDiskNames) {
        $r.Candidates++
        if ($exemptNames.Contains($name)) { continue }
        if (-not $documented.Contains($name)) {
            $r.Fail("tools/$name exists and the '$heading' section of $frontDoor does not name it -- a reader of the front door has no way to learn it is there. Add it to the section, or register it in front-door.json with the reason it stays out")
        }
    }

    # ── reverse ─────────────────────────────────────────────────────────────────
    foreach ($name in $documentedNames) {
        $r.Candidates++
        if (-not $onDisk.Contains($name)) {
            $r.Fail("the '$heading' section of $frontDoor names 'tools/$name', and there is no such entry under $Root -- the unit was renamed or removed and the front door was not. Fix the name, or strike the row")
        }
    }

    # ── the exemptions, both ways ───────────────────────────────────────────────
    # An exemption is not allowed to be a silence with nothing under it. Same reasoning as a stale
    # sweep exclusion in check D and a dead attribution in check G: it keeps working forever while
    # covering nothing, and it is indistinguishable by reading from one that is still load-bearing.
    foreach ($e in $exempt) {
        if ($null -eq $e -or -not $e.ContainsKey('entry') -or [string]::IsNullOrWhiteSpace([string]$e.entry)) { continue }
        $n = [string]$e.entry
        $r.Candidates++
        if (-not $onDisk.Contains($n)) {
            $r.Fail("front-door.json exempts 'tools/$n' from the front door and no such entry is under $Root -- the exemption outlived the file it was written for, and the next unit to land on that name inherits an exemption nobody granted it. Remove it, or fix the name")
        }
        elseif ($documented.Contains($n)) {
            $r.Fail("front-door.json exempts 'tools/$n' from the front door and the '$heading' section names it anyway -- the exemption covers nothing; strike it")
        }
    }

    $r.Note = "$($onDiskNames.Count) entry(ies) under $Root, $($documentedNames.Count) named in '$heading', $($exempt.Count) registered exempt"
    $r.Seal()
    return $r
}

# ── SELF-TEST ───────────────────────────────────────────────────────────────────
# A gate that has never been red is unproven. These are the negative controls, run against
# fixtures in a temp directory; nothing is written inside the repository.

function Invoke-SelfTest {
    param([string]$RepoRoot, [string]$GateDir)

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("practice-gate-selftest-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $null = New-Item -ItemType Directory -Path $tmp -Force
    $failures = 0
    # Passed in rather than re-derived: control 9 below loads the LIVE registries, so a self-test
    # that computed its own path could go green against a different directory than the live run
    # reads. Two derivations of one path is the drift this repo gates against everywhere else.
    $gateDir = $GateDir

    function Assert-Case {
        param([string]$Name, [string]$Expected, [string]$Actual)
        $ok = $Expected -eq $Actual
        $mark = if ($ok) { 'ok  ' } else { 'FAIL' }
        Write-Host ("  [{0}] {1,-52} expected {2}, got {3}" -f $mark, $Name, $Expected, $Actual)
        return $ok
    }

    Write-Host "`nSELF-TEST -- negative controls" -ForegroundColor Cyan

    try {
        # 1. an empty scope must be INCONCLUSIVE, never PASS. This is the case the whole exit
        #    contract exists for: zero findings and zero candidates are not the same result.
        $empty = Join-Path $tmp 'empty'; $null = New-Item -ItemType Directory -Path $empty -Force
        $res = Test-Redaction -Root $empty -RepoRoot $RepoRoot -GateDir $gateDir
        if (-not (Assert-Case 'empty scope reports INCONCLUSIVE not PASS' 'INCONCLUSIVE' $res.Status)) { $failures++ }

        # THE PLANT-AND-CATCH CONTROLS RUN ON A FIXTURE TABLE, and that follows from moving the
        # patterns into a data file. A recipient of a share pack holds only the example table, whose
        # patterns forbid placeholder vocabulary -- so a control that plants a REAL identifier and
        # demands a FAIL would be red in every distribution, for a reason the recipient cannot fix
        # and which says nothing whatever about the code. A gate red for the wrong reason costs as
        # much as one green for the wrong reason; this file says so about Test-HarnessPins and the
        # rule does not stop applying here.
        #
        # What these three controls are actually about is the SCAN: that a match produces a finding
        # at all, that the exemption is by NAME and not by glob, that .template is inside the
        # extension list. None of that is a claim about which strings one organisation forbids. The
        # live table's own patterns are proven against their own examples on every run inside the
        # check, 2b below exercises the live table end to end, and control 9 asserts it loads.
        #
        # The planted path is a fictional account for the same reason the patterns moved: this file
        # ships, and a fixture is a poor argument for publishing somebody's username.
        $stGate = Join-Path $tmp 'selftest-gate'; $null = New-Item -ItemType Directory -Path $stGate -Force
        $stTable = @{ classes = @(
                @{
                    name            = 'personal path or identity'
                    pattern         = '(?i)[\\/]Users[\\/][a-z]+[\\/]\.wt\b'
                    example         = 'C:\Users\someone\.wt\thing.ps1'
                    counter_example = 'C:\Users\<you>\.claude\settings.json'
                    reason          = 'self-test fixture -- the scan controls must not depend on which vocabulary is deployed'
                }) }
        [System.IO.File]::WriteAllText((Join-Path $stGate 'redaction-classes.json'), ($stTable | ConvertTo-Json -Depth 5))

        # 2. a planted personal path must be caught
        $dirty = Join-Path $tmp 'dirty'; $null = New-Item -ItemType Directory -Path $dirty -Force
        [System.IO.File]::WriteAllText((Join-Path $dirty 'x.ps1'), "# C:\Users\someone\.wt\thing.ps1`n")
        $res = Test-Redaction -Root $dirty -RepoRoot $RepoRoot -GateDir $stGate
        if (-not (Assert-Case 'planted personal path is caught' 'FAIL' $res.Status)) { $failures++ }

        # 2a. THE SELF-EXEMPTION IS NAMES, NOT A GLOB. A file called Test-Something.ps1 is scanned
        #     like anything else; only the two named gates and the two class tables are exempt, and
        #     the reason the distinction matters is that 'Test-*.ps1' would quietly exempt every
        #     future test file in the tree from the only check that reads it.
        [System.IO.File]::WriteAllText((Join-Path $dirty 'Test-Something.ps1'), "# C:\Users\someone\.wt\thing.ps1`n")
        $res = Test-Redaction -Root $dirty -RepoRoot $RepoRoot -GateDir $stGate
        if (-not (Assert-Case 'a file merely NAMED like a gate is still scanned' 'FAIL' $res.Status)) { $failures++ }
        Remove-Item -LiteralPath (Join-Path $dirty 'Test-Something.ps1') -Force

        # 2b. ...and the exempt names really are exempt, otherwise this check cannot describe its
        #     own patterns without failing on them. Run against the LIVE table rather than the
        #     fixture, deliberately: PASS here also means every class in whichever table is deployed
        #     matched its own example and missed its own counter-example, since either failure is
        #     reported as a finding before the scan starts. It holds in a distribution too, because
        #     the assertion is about the exemption and not about the vocabulary.
        $exemptDir = Join-Path $tmp 'exempt'; $null = New-Item -ItemType Directory -Path $exemptDir -Force
        [System.IO.File]::WriteAllText((Join-Path $exemptDir 'Test-SharePackClean.ps1'), "# C:\Users\someone\.wt\thing.ps1`n")
        [System.IO.File]::WriteAllText((Join-Path $exemptDir 'clean.md'), "nothing to see here`n")
        $res = Test-Redaction -Root $exemptDir -RepoRoot $RepoRoot -GateDir $gateDir
        if (-not (Assert-Case 'the named gates are exempt from their own patterns' 'PASS' $res.Status)) { $failures++ }

        # 2c. A TEMPLATE IS A DOCUMENT. .template joined the extension list on 2026-08-17; before
        #     that a CLAUDE.md.template could carry a personal path through every check in this
        #     file. The control is worth keeping because the failure mode is invisible: an
        #     extension-scoped scan reports the same clean line whether the file is clean or unread.
        $tpl = Join-Path $tmp 'tpl'; $null = New-Item -ItemType Directory -Path $tpl -Force
        [System.IO.File]::WriteAllText((Join-Path $tpl 'CLAUDE.md.template'), "# C:\Users\someone\.wt\thing.ps1`n")
        $res = Test-Redaction -Root $tpl -RepoRoot $RepoRoot -GateDir $stGate
        if (-not (Assert-Case 'a .template file is inside the redaction scan' 'FAIL' $res.Status)) { $failures++ }

        # 2d. THE PATTERN TABLE IS THE CHECK. It moved out of this file into
        #     practice-gate/redaction-classes.json on 2026-08-19, because inline it published the
        #     entire internal identifier vocabulary in one screen of a repository about to go public.
        #     The move introduces exactly one new failure mode and it is the worst one on offer: a
        #     table that does not load leaves the scan with no patterns, a scan with no patterns
        #     finds nothing, and finding nothing is what a clean tree looks like. The controls from
        #     here to 2i all assert one property from different sides -- a redaction check with no
        #     usable patterns must never report PASS.
        $noTable = Join-Path $tmp 'no-table'; $null = New-Item -ItemType Directory -Path $noTable -Force
        $threw = $false
        try { $null = Test-Redaction -Root $dirty -RepoRoot $RepoRoot -GateDir $noTable } catch { $threw = $true }
        if (-not (Assert-Case 'no class table at all raises, never passes' 'True' $threw.ToString())) { $failures++ }

        # 2e. ...and a table that parses but holds no classes is the same defect wearing a valid
        #     file. Nothing may read "loaded successfully" as "has patterns".
        [System.IO.File]::WriteAllText((Join-Path $noTable 'redaction-classes.json'), '{"classes":[]}')
        $threw = $false
        try { $null = Test-Redaction -Root $dirty -RepoRoot $RepoRoot -GateDir $noTable } catch { $threw = $true }
        if (-not (Assert-Case 'an empty class table raises, never passes' 'True' $threw.ToString())) { $failures++ }

        # 2f. THE FALLBACK, AND THE NOTE THAT HAS TO TRAVEL WITH IT. A recipient of a share pack
        #     holds redaction-classes.example.json and not the real table, so the gate has to run for
        #     them -- being handed a red gate for being in the state the distribution puts you in
        #     teaches nothing. What they must not be handed is a PASS that reads like this
        #     repository's. Copying the LIVE example file rather than writing a fixture is
        #     deliberate: this is also the only control that proves the shipped starter table parses
        #     and that every example in it still matches its own pattern.
        #
        #     THE FIXTURE IS ALSO THE SCAN ROOT, and that is the half this control was missing on its
        #     first cut. The example table was left inside the scan on the reasoning that a generic
        #     file is worth reading -- true while the real table is present, false the moment it is
        #     not, because then the example table is the ACTIVE one and its patterns match its own
        #     examples. Scanning $exemptDir proved the load and missed that entirely; a recipient's
        #     first run reported 15 findings against the file the pack had just told them to copy.
        $fallback = Join-Path $tmp 'fallback'; $null = New-Item -ItemType Directory -Path $fallback -Force
        Copy-Item -LiteralPath (Join-Path $gateDir 'redaction-classes.example.json') -Destination $fallback -Force
        [System.IO.File]::WriteAllText((Join-Path $fallback 'clean.md'), "nothing to see here`n")
        $res = Test-Redaction -Root $fallback -RepoRoot $RepoRoot -GateDir $fallback
        if (-not (Assert-Case 'the shipped example table loads and runs' 'PASS' $res.Status)) { $failures++ }
        if (-not (Assert-Case '...and the note names it, so the downgrade is visible' 'True' ($res.Note -match 'redaction-classes\.example\.json').ToString())) { $failures++ }

        #     ...and here is what that note is warning about, asserted rather than assumed: the same
        #     planted personal path, in the same fixture, caught at control 2 and clean here. Both
        #     tables load, both scans run, both report a status -- and only the note distinguishes
        #     them. The fallback is a materially weaker gate, not a spare key.
        $res = Test-Redaction -Root $dirty -RepoRoot $RepoRoot -GateDir $fallback
        if (-not (Assert-Case 'the example table does NOT catch this tree (hence the note)' 'PASS' $res.Status)) { $failures++ }

        # 2g. A CLASS THAT NO LONGER MATCHES ITS OWN EXAMPLE. This is the run-time positive control,
        #     and the reason every class carries an example at all: a pattern edited wrong stops
        #     matching, reports nothing, and cannot be told apart from a clean tree by reading the
        #     report. The control has to fire in the LIVE run and not only under -SelfTest, or every
        #     real run trusts a table nobody checked.
        $broken = Join-Path $tmp 'broken'; $null = New-Item -ItemType Directory -Path $broken -Force
        [System.IO.File]::WriteAllText((Join-Path $broken 'redaction-classes.json'),
            '{"classes":[{"name":"broken","pattern":"zzz-nothing-matches-this","example":"an example the pattern no longer catches","reason":"self-test fixture"}]}')
        $res = Test-Redaction -Root $exemptDir -RepoRoot $RepoRoot -GateDir $broken
        if (-not (Assert-Case 'a class not matching its own example fails' 'FAIL' $res.Status)) { $failures++ }

        # 2h. ...and the other polarity: a class broad enough to match the near-miss the tree is
        #     allowed to carry. Unchecked, that fails a clean tree, which is how a gate teaches
        #     people to route around it.
        [System.IO.File]::WriteAllText((Join-Path $broken 'redaction-classes.json'),
            '{"classes":[{"name":"too broad","pattern":"(?i)example","example":"an example","counter_example":"another example","reason":"self-test fixture"}]}')
        $res = Test-Redaction -Root $exemptDir -RepoRoot $RepoRoot -GateDir $broken
        if (-not (Assert-Case 'a class matching its counter-example fails' 'FAIL' $res.Status)) { $failures++ }

        # 2i. ...and a class with no stated reason, which every other registry in this directory
        #     already refuses. An unexplained class cannot be widened, narrowed or struck by the
        #     next reader, so it survives on nobody's judgement.
        [System.IO.File]::WriteAllText((Join-Path $broken 'redaction-classes.json'),
            '{"classes":[{"name":"unexplained","pattern":"zzz","example":"zzz"}]}')
        $res = Test-Redaction -Root $exemptDir -RepoRoot $RepoRoot -GateDir $broken
        if (-not (Assert-Case 'a class with no reason fails' 'FAIL' $res.Status)) { $failures++ }

        # 3. a citation to a file that does not exist must fail
        $cite = Join-Path $tmp 'cite'; $null = New-Item -ItemType Directory -Path $cite -Force
        [System.IO.File]::WriteAllText((Join-Path $cite 'a.md'), "See ``tools/nope/missing_file.py`` for details.`n")
        $reg = @{ entries = @() }
        $res = Test-Citations -Root $cite -RepoRoot $RepoRoot -Registry $reg
        if (-not (Assert-Case 'unresolvable citation fails' 'FAIL' $res.Status)) { $failures++ }

        # 4. …and passes once registered, which is the escape hatch working as designed
        $reg = @{ entries = @(@{ token = 'tools/nope/missing_file.py'; reason = 'self-test fixture' }) }
        $res = Test-Citations -Root $cite -RepoRoot $RepoRoot -Registry $reg
        if (-not (Assert-Case 'registered citation passes' 'PASS' $res.Status)) { $failures++ }

        # 4b. THE REVERSE DIRECTION, which this registry did not have until 2026-08-16. Three
        #     controls, because the exemption rots in three different ways and only the first is
        #     obvious. The escape hatch proved above is exactly what has to be watched.
        $reg = @{ entries = @(
                @{ token = 'tools/nope/missing_file.py'; reason = 'self-test fixture' },
                @{ token = 'tools/nope/nobody_cites_this.py'; reason = 'self-test fixture' }) }
        $res = Test-Citations -Root $cite -RepoRoot $RepoRoot -Registry $reg
        if (-not (Assert-Case 'an exemption nothing cites fails' 'FAIL' $res.Status)) { $failures++ }

        # ...and the quieter one: the token now resolves, so the exemption is skipping a check
        # that would have passed. It keeps working forever while meaning nothing.
        [System.IO.File]::WriteAllText((Join-Path $cite 'c.md'), "See ``tools/Test-PracticeClaims.ps1`` for details.`n")
        $reg = @{ entries = @(
                @{ token = 'tools/nope/missing_file.py'; reason = 'self-test fixture' },
                @{ token = 'tools/Test-PracticeClaims.ps1'; reason = 'self-test fixture' }) }
        $res = Test-Citations -Root $cite -RepoRoot $RepoRoot -Registry $reg
        if (-not (Assert-Case 'an exemption whose token now resolves fails' 'FAIL' $res.Status)) { $failures++ }
        Remove-Item -LiteralPath (Join-Path $cite 'c.md') -Force

        # ...and an entry with no stated reason, which the sibling registries already refused and
        # this one accepted.
        $reg = @{ entries = @(@{ token = 'tools/nope/missing_file.py' }) }
        $res = Test-Citations -Root $cite -RepoRoot $RepoRoot -Registry $reg
        if (-not (Assert-Case 'exemption with no reason fails' 'FAIL' $res.Status)) { $failures++ }

        # 5. an undated figure must fail, and the same figure dated must pass
        $fig = Join-Path $tmp 'fig'; $null = New-Item -ItemType Directory -Path $fig -Force
        [System.IO.File]::WriteAllText((Join-Path $fig 'b.md'), "The list held 2,673 rules and bounded nothing.`n")
        $res = Test-Figures -Root $fig -RepoRoot $RepoRoot -Registry @{ entries = @() }
        if (-not (Assert-Case 'undated figure fails' 'FAIL' $res.Status)) { $failures++ }

        [System.IO.File]::WriteAllText((Join-Path $fig 'b.md'), "Measured 2026-08-10: the list held 2,673 rules and bounded nothing.`n")
        $res = Test-Figures -Root $fig -RepoRoot $RepoRoot -Registry @{ entries = @() }
        if (-not (Assert-Case 'dated figure passes' 'PASS' $res.Status)) { $failures++ }

        # 5-vs. THE SHORT SPELLING IS THE SAME FIGURE. A comparison written `vs 534` is the number
        #       `versus 534` states, and until 2026-08-17 only the long form was a measurement shape
        #       -- so shortening the word moved a figure out of the gate without changing it. The
        #       control asserts the SHORT form alone, because the long one already passes above and
        #       would mask a pattern that only ever matched `versus`.
        [System.IO.File]::WriteAllText((Join-Path $fig 'b.md'), "One entry from the junctioned directory vs 534 from the canonical one.`n")
        $res = Test-Figures -Root $fig -RepoRoot $RepoRoot -Registry @{ entries = @() }
        if (-not (Assert-Case 'undated figure written `vs` fails too' 'FAIL' $res.Status)) { $failures++ }

        [System.IO.File]::WriteAllText((Join-Path $fig 'b.md'), "Measured 2026-08-07: one entry from the junctioned directory vs 534 from the canonical one.`n")
        $res = Test-Figures -Root $fig -RepoRoot $RepoRoot -Registry @{ entries = @() }
        if (-not (Assert-Case '...and dated, it passes' 'PASS' $res.Status)) { $failures++ }

        # 5a. THE ITALIC FORM COUNTS. figures.json's own _comment tells authors to write
        #     '_measured 2026-08-10_' beside the number -- and \b never fires against an underscore,
        #     because `_` is a word character, so that exact form was not recognised as a date. The
        #     documented fix failed the check and pushed the author into the registry instead, which
        #     grew the thing the guidance exists to keep small. One live instance already existed.
        [System.IO.File]::WriteAllText((Join-Path $fig 'b.md'), "The list held 2,673 rules (_measured 2026-08-10_) and bounded nothing.`n")
        $res = Test-Figures -Root $fig -RepoRoot $RepoRoot -Registry @{ entries = @() }
        if (-not (Assert-Case 'the documented _italic_ date form counts as a date' 'PASS' $res.Status)) { $failures++ }

        # 5b. THE REVERSE DIRECTION for figures, mode 1: the number was edited, so the entry covers
        #     nothing and its recorded measurement date describes a figure not on the page.
        [System.IO.File]::WriteAllText((Join-Path $fig 'b.md'), "The list held 2,673 rules and bounded nothing.`n")
        $figReg = @{ entries = @(
                @{ file = 'b.md'; figure = '2,673'; kind = 'illustration'; reason = 'self-test fixture' },
                @{ file = 'b.md'; figure = '9,999'; kind = 'illustration'; reason = 'self-test fixture' }) }
        $res = Test-Figures -Root $fig -RepoRoot $fig -Registry $figReg
        if (-not (Assert-Case 'figures entry naming a missing figure fails' 'FAIL' $res.Status)) { $failures++ }

        #     ...mode 2: the figure is still there and now carries a date, so the exemption skips a
        #     check that would pass.
        [System.IO.File]::WriteAllText((Join-Path $fig 'b.md'), "The list held 2,673 rules (_measured 2026-08-10_).`n")
        $figReg = @{ entries = @(@{ file = 'b.md'; figure = '2,673'; kind = 'illustration'; reason = 'self-test fixture' }) }
        $res = Test-Figures -Root $fig -RepoRoot $fig -Registry $figReg
        if (-not (Assert-Case 'figures entry whose figure is now dated fails' 'FAIL' $res.Status)) { $failures++ }

        # 5c. A registered MEASUREMENT expires. The registry demanded an ISO date and then held it
        #     forever, so a figure measured two years ago read exactly like one measured today.
        #     Harness pins have expired at 180 days since they were written; same window, same
        #     reason. An illustration has no measurement date and must NOT expire.
        [System.IO.File]::WriteAllText((Join-Path $fig 'b.md'), "The list held 2,673 rules and bounded nothing.`n")
        $stale = (Get-Date).AddDays(-($MaxFigureAgeDays + 30)).ToString('yyyy-MM-dd')
        $figReg = @{ entries = @(@{ file = 'b.md'; figure = '2,673'; kind = 'measurement'; measured = $stale; reason = 'self-test fixture' }) }
        $res = Test-Figures -Root $fig -RepoRoot $fig -Registry $figReg
        if (-not (Assert-Case 'a measurement older than the age limit fails' 'FAIL' $res.Status)) { $failures++ }

        $fresh = (Get-Date).AddDays(-1).ToString('yyyy-MM-dd')
        $figReg = @{ entries = @(@{ file = 'b.md'; figure = '2,673'; kind = 'measurement'; measured = $fresh; reason = 'self-test fixture' }) }
        $res = Test-Figures -Root $fig -RepoRoot $fig -Registry $figReg
        if (-not (Assert-Case 'a recent measurement passes' 'PASS' $res.Status)) { $failures++ }

        $figReg = @{ entries = @(@{ file = 'b.md'; figure = '2,673'; kind = 'illustration'; reason = 'self-test fixture' }) }
        $res = Test-Figures -Root $fig -RepoRoot $fig -Registry $figReg
        if (-not (Assert-Case 'an illustration does not expire' 'PASS' $res.Status)) { $failures++ }

        # 4b. A section that cites nothing must fail -- the hole that let an entirely unsourced
        #     section ship past every other check.
        $src = Join-Path $tmp 'src'; $null = New-Item -ItemType Directory -Path $src -Force
        $srcReg = @{ scope = @('*'); entries = @() }
        [System.IO.File]::WriteAllText((Join-Path $src 'd.md'), "## One`n`nProse making a confident claim with nothing behind it.`n")
        $res = Test-Sourcing -Root $src -RepoRoot $src -Registry $srcReg
        if (-not (Assert-Case 'section citing nothing fails' 'FAIL' $res.Status)) { $failures++ }

        # 4c. ...and passes once registered, with a reason.
        $srcReg.entries = @(@{ file = 'd.md'; section = 'One'; reason = 'self-test fixture' })
        $res = Test-Sourcing -Root $src -RepoRoot $src -Registry $srcReg
        if (-not (Assert-Case 'registered unsourced section passes' 'PASS' $res.Status)) { $failures++ }

        # 4d. A registration without a reason is a silencer, not a decision.
        $srcReg.entries = @(@{ file = 'd.md'; section = 'One' })
        $res = Test-Sourcing -Root $src -RepoRoot $src -Registry $srcReg
        if (-not (Assert-Case 'registration without a reason fails' 'FAIL' $res.Status)) { $failures++ }

        # 4d-i. THE REVERSE DIRECTION for sourcing, added 2026-08-16 alongside the same half for
        #       figures. external-citations.json got this in the previous pass and these two did
        #       not, so the rule was enforced on one registry out of three. Both modes are silent
        #       and the second is the worse one.
        #
        #       Mode 1: the heading was renamed, so the entry exempts nothing -- and the NEXT
        #       section to take that name inherits an exemption nobody granted it.
        $srcReg.entries = @(@{ file = 'd.md'; section = 'Renamed Away'; reason = 'self-test fixture' })
        $res = Test-Sourcing -Root $src -RepoRoot $src -Registry $srcReg
        if (-not (Assert-Case 'sourcing entry naming a missing section fails' 'FAIL' $res.Status)) { $failures++ }

        #       Mode 2: the section is still there and now cites something, so the exemption is
        #       suppressing a check that would pass. It keeps working forever while meaning nothing.
        [System.IO.File]::WriteAllText((Join-Path $src 'd.md'),
            "## One`n`nSee ``tools/Test-PracticeClaims.ps1`` for this.`n")
        $srcReg.entries = @(@{ file = 'd.md'; section = 'One'; reason = 'self-test fixture' })
        $res = Test-Sourcing -Root $src -RepoRoot $src -Registry $srcReg
        if (-not (Assert-Case 'sourcing entry whose section now cites fails' 'FAIL' $res.Status)) { $failures++ }

        # restore the fixture the later controls expect
        [System.IO.File]::WriteAllText((Join-Path $src 'd.md'), "## One`n`nProse making a confident claim with nothing behind it.`n")

        # 4e. THE LAST SECTION IS EVALUATED. A section walker that closes sections only when it
        #     meets the NEXT heading silently exempts the final section of every file -- and the
        #     final section is where late additions land. Sourced first section, unsourced last.
        $srcReg.entries = @()
        [System.IO.File]::WriteAllText((Join-Path $src 'd.md'),
            "## One`n`nSee ``tools/Test-PracticeClaims.ps1`` for this.`n`n## Last`n`nNothing behind this one at all.`n")
        $res = Test-Sourcing -Root $src -RepoRoot (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path -Registry @{ scope = @('*'); entries = @() }
        if (-not (Assert-Case 'the LAST section is evaluated, not exempt' 'FAIL' $res.Status)) { $failures++ }

        # 4f. A backticked INVOCATION is still a citation. `freshness.py --no-connector` names a
        #     real file; rejecting any span containing a space missed it, so check A never verified
        #     it and check E called its section unsourced. Both under-counted, silently.
        $toks = Get-CitationTokens -Line 'The degraded mode: `freshness.py --no-connector` exits 2.'
        if (-not (Assert-Case 'invocation with a flag is a citation' 'freshness.py' ([string]$toks[0]))) { $failures++ }
        $toks = Get-CitationTokens -Line 'A floor in one spelling: `cat .env` says nothing about `Bash(pwsh *)`.'
        if (-not (Assert-Case 'prose and rule syntax are not citations' '0' ([string]$toks.Count))) { $failures++ }

        # 4g. SOME of the scope missing is a finding. The registry is pointing at nothing.
        # The present half is THIS script, which is the one file guaranteed to sit under $RepoRoot
        # in every layout that can run this self-test. An earlier draft used README.md and passed
        # in-repo while turning SKIPPED in a distribution -- a control whose verdict depends on
        # which tree it happens to run in is not a control.
        $res = Test-Assertions -RepoRoot $RepoRoot -Registry @{ scope = @('tools/Test-PracticeClaims.ps1', 'x'); negative_claim_markers = @('does not exist') }
        if (-not (Assert-Case 'scoped document that is missing fails' 'FAIL' $res.Status)) { $failures++ }

        # ...but ALL of it missing is a different claim: the registry was written for another
        # tree. A distribution ships tools/ and not the planning documents, and a recipient met
        # six red lines about files nobody sent them. The two must not share an outcome, and the
        # scope fact must not be a pass either.
        $res = Test-Assertions -RepoRoot $RepoRoot -Registry @{ scope = @('x', 'y'); negative_claim_markers = @('does not exist') }
        if (-not (Assert-Case 'a scope wholly absent is SKIPPED, not FAIL' 'SKIPPED' $res.Status)) { $failures++ }

        # the real inversion, against the live repo: a claim that a present file is absent
        $probe = Join-Path $tmp 'probe.md'
        [System.IO.File]::WriteAllText($probe, "The gate ``tools/Test-PracticeClaims.ps1`` does not exist as a script.`n")
        Copy-Item -LiteralPath $probe -Destination (Join-Path $RepoRoot 'zz-selftest-probe.md') -Force
        try {
            $res = Test-Assertions -RepoRoot $RepoRoot -Registry @{ scope = @('zz-selftest-probe.md'); negative_claim_markers = @('does not exist') }
            if (-not (Assert-Case 'negative claim about a file that EXISTS fails' 'FAIL' $res.Status)) { $failures++ }

            # 4h. ...and the same claim marked resolved does NOT fire. A check that fires hardest on
            #     the entries somebody just fixed teaches people to stop marking them.
            [System.IO.File]::WriteAllText((Join-Path $RepoRoot 'zz-selftest-probe.md'),
                "1. ~~The gate ``tools/Test-PracticeClaims.ps1`` does not exist.~~ RESOLVED 2026-08-16.`n")
            $res = Test-Assertions -RepoRoot $RepoRoot -Registry @{ scope = @('zz-selftest-probe.md'); negative_claim_markers = @('does not exist') }
            if (-not (Assert-Case 'a claim marked RESOLVED does not fire' 'PASS' $res.Status)) { $failures++ }

            # 4i. THE WRAP. Claim and path on different lines -- a line-scoped check misses this
            #     silently, and prose wraps, so "silently" means "most of them".
            [System.IO.File]::WriteAllText((Join-Path $RepoRoot 'zz-selftest-probe.md'),
                "1. The permission replay validator does not exist as a script; it should be`n   built at ``tools/Test-PracticeClaims.ps1`` when someone has time.`n")
            $res = Test-Assertions -RepoRoot $RepoRoot -Registry @{ scope = @('zz-selftest-probe.md'); negative_claim_markers = @('does not exist') }
            if (-not (Assert-Case 'claim and path on DIFFERENT lines still fires' 'FAIL' $res.Status)) { $failures++ }

            # 4j. THE EXTRACTOR BREAKING. A scoped document present and readable, and not one
            #     marker matching -- the shape you get by rewording the prose or narrowing a
            #     marker, both of which leave the registry valid. Until Candidates counted CLAIMS
            #     rather than LINES this reported PASS, because a thousand-line plan always had a
            #     large non-zero count. It is the one failure mode this whole file exists for, and
            #     it was open in the only check that was not counting the thing it tests.
            [System.IO.File]::WriteAllText((Join-Path $RepoRoot 'zz-selftest-probe.md'),
                ("Nothing here trips a marker.`n" * 400))
            $res = Test-Assertions -RepoRoot $RepoRoot -Registry @{ scope = @('zz-selftest-probe.md'); negative_claim_markers = @('does not exist') }
            if (-not (Assert-Case 'zero matches over a long document is INCONCLUSIVE' 'INCONCLUSIVE' $res.Status)) { $failures++ }
            if (-not (Assert-Case '...and counts claims, not lines' '0' ([string]$res.Candidates))) { $failures++ }
        }
        finally {
            Remove-Item -LiteralPath (Join-Path $RepoRoot 'zz-selftest-probe.md') -Force -ErrorAction SilentlyContinue
        }

        # 5b. THE PROPERTY, not the patch: a date somewhere else in the document must NOT excuse an
        #     undated figure. Written in CRLF because both bugs this catches were invisible in LF --
        #     a paragraph splitter that does not normalise CRLF returns the whole file as one
        #     paragraph, and `foreach ($x in Read-Paragraphs ...)` binds $x to the entire array
        #     rather than to each element. Both make every figure look dated, both exit 0, and
        #     neither is visible by reading the check. Keep this test even if the splitter is
        #     rewritten: it asserts what must hold however the code is written.
        $crlf = "Some prose dated 2026-08-10 in its own paragraph.`r`n`r`nA later claim: the list held 2,673 rules.`r`n"
        [System.IO.File]::WriteAllText((Join-Path $fig 'b.md'), $crlf)
        $res = Test-Figures -Root $fig -RepoRoot $RepoRoot -Registry @{ entries = @() }
        if (-not (Assert-Case 'date in a DIFFERENT paragraph does not excuse (CRLF)' 'FAIL' $res.Status)) { $failures++ }

        # 6. a stale pin -- one whose prose has gone -- must be reported rather than pass quietly
        $pin = Join-Path $tmp 'pin'; $null = New-Item -ItemType Directory -Path $pin -Force
        [System.IO.File]::WriteAllText((Join-Path $pin 'c.md'), "Nothing here mentions the harness at all.`n")
        # RepoRoot is the fixture dir here so the relative paths the scope matches on are the
        # fixture's own, not a slice of an unrelated absolute path.
        $reg = @{
            harness_keywords = @('Esc')
            sweep_exclusions = @()
            entries          = @(@{
                    id = 'ghost'; claim = 'a claim whose prose was deleted'
                    verified_against = '9.9.9'; verified_on = (Get-Date).ToString('yyyy-MM-dd')
                    source = 'https://example.invalid'; markers = @('double-Esc is not a rewind')
                })
        }
        $res = Test-HarnessPins -Root $pin -RepoRoot $pin -Registry $reg
        if (-not (Assert-Case 'pin pointing at deleted prose fails' 'FAIL' $res.Status)) { $failures++ }

        # 7. an expired pin must fail even though its prose is intact -- the freshness half
        [System.IO.File]::WriteAllText((Join-Path $pin 'c.md'), "We claim that double-Esc is not a rewind.`n")
        $reg.entries[0].verified_on = (Get-Date).AddDays(-400).ToString('yyyy-MM-dd')
        $res = Test-HarnessPins -Root $pin -RepoRoot $pin -Registry $reg
        if (-not (Assert-Case 'pin older than the age limit fails' 'FAIL' $res.Status)) { $failures++ }

        # 7b. an exclusion list that swallows every document must be INCONCLUSIVE, not PASS. A scope
        #     predicate that selects no rows produces a smaller table, not an error.
        $reg.sweep_exclusions = @(@{ path = '*'; reason = 'excludes everything, on purpose, for this control' })
        $reg.entries[0].verified_on = (Get-Date).ToString('yyyy-MM-dd')
        $res = Test-HarnessPins -Root $pin -RepoRoot $pin -Registry $reg
        if (-not (Assert-Case 'exclusions swallowing every document is INCONCLUSIVE' 'INCONCLUSIVE' $res.Status)) { $failures++ }

        # 7c. THE CONTROL FOR THE INVERSION ITSELF. The sweep used to be a whitelist, where an
        #     unlisted document was silently exempt -- and a shipped README carried a harness claim
        #     that had gone false for exactly that reason. So: a document nobody named must now be
        #     swept, and its unpinned claim must be a finding rather than silence.
        [System.IO.File]::WriteAllText((Join-Path $pin 'newcomer.md'), "A brand new document nobody added to any list: pressing Esc twice does something.`n")
        $reg.sweep_exclusions = @()
        $res = Test-HarnessPins -Root $pin -RepoRoot $pin -Registry $reg
        if (-not (Assert-Case 'a document nobody listed is swept, not exempt' 'FAIL' $res.Status)) { $failures++ }

        # 7d. an exclusion is an exemption, and an exemption without a stated reason is an oversight
        #     rather than a decision -- the same rule sourcing.json holds its entries to.
        $reg.sweep_exclusions = @(@{ path = 'newcomer.md' })
        $res = Test-HarnessPins -Root $pin -RepoRoot $pin -Registry $reg
        if (-not (Assert-Case 'exclusion with no reason fails' 'FAIL' $res.Status)) { $failures++ }

        # 7e. a STALE exclusion -- one whose file was renamed or deleted -- is itself a finding. It
        #     is the mirror of a pin matching no prose: the exemption outlives the document it was
        #     written for, and the next file to land on that path inherits an exemption nobody
        #     granted it. Without this, the opt-out list rots exactly the way the whitelist did.
        $reg.sweep_exclusions = @(
            @{ path = 'newcomer.md'; reason = 'covered by the control above' },
            @{ path = 'deleted-long-ago.md'; reason = 'this file no longer exists' }
        )
        $res = Test-HarnessPins -Root $pin -RepoRoot $pin -Registry $reg
        if (-not (Assert-Case 'exclusion matching no document fails' 'FAIL' $res.Status)) { $failures++ }

        # 7f. a keyword inside a FENCED BLOCK is being demonstrated, not asserted. Test-Sourcing has
        #     skipped fences since it was written and this check did not, which stayed invisible
        #     while the sweep was too narrow to meet a fenced example. Widening it surfaced two.
        Remove-Item -LiteralPath (Join-Path $pin 'newcomer.md') -Force
        $fenced = "Prose that asserts nothing.`n`n``````markdown`n---`npaths:`n  - ""src/**""`n---`nPressing Esc twice does something.`n```````n`nMore prose.`n"
        [System.IO.File]::WriteAllText((Join-Path $pin 'fenced.md'), $fenced)
        $reg.sweep_exclusions = @()
        $res = Test-HarnessPins -Root $pin -RepoRoot $pin -Registry $reg
        if (-not (Assert-Case 'a keyword inside a fenced block is not a claim' 'PASS' $res.Status)) { $failures++ }

        # ...and the same keyword OUTSIDE the fence in the same file still fires, so 7f is proving
        # fence-awareness rather than a check that has quietly stopped looking at the file at all.
        [System.IO.File]::WriteAllText((Join-Path $pin 'fenced.md'), $fenced + "`nAnd in prose: pressing Esc twice does something.`n")
        $res = Test-HarnessPins -Root $pin -RepoRoot $pin -Registry $reg
        if (-not (Assert-Case '...but the same keyword outside the fence still fires' 'FAIL' $res.Status)) { $failures++ }
        Remove-Item -LiteralPath (Join-Path $pin 'fenced.md') -Force

        # 7g. MARKERS ARE CASE-SENSITIVE -- the coverage half.
        #
        #     Found 2026-08-17 by a falsification that did not fire. PowerShell's -match ignores
        #     case, and markers are short literal phrases, so a marker could silently cover a
        #     sentence about an entirely different mechanism: "the first match wins" in a document
        #     about memory tiering was reported as pinned, by the marker belonging to the
        #     PERMISSION-ORDERING claim. The keyword fired, the marker absorbed it, nothing failed.
        #
        #     The two halves are separated deliberately. Here the pin's marker DOES appear verbatim
        #     somewhere in the tree, so registry health is satisfied and the only thing that can
        #     produce a finding is coverage -- otherwise this control would pass for the wrong
        #     reason, which is the failure mode it was written about.
        $caseReg = @{
            harness_keywords = @('Esc')
            sweep_exclusions = @()
            entries          = @(@{
                    id = 'cased'; claim = 'a claim quoted with specific capitalisation'
                    verified_against = '9.9.9'; verified_on = (Get-Date).ToString('yyyy-MM-dd')
                    source = 'https://example.invalid'; markers = @('double-Esc is not a rewind')
                })
        }
        [System.IO.File]::WriteAllText((Join-Path $pin 'c.md'),
            "We claim that double-Esc is not a rewind.`nSeparately: Double-Esc Is Not A Rewind, restated in title case.`n")
        $res = Test-HarnessPins -Root $pin -RepoRoot $pin -Registry $caseReg
        if (-not (Assert-Case 'a marker differing only in CASE does not cover' 'FAIL' $res.Status)) { $failures++ }

        #     ...and the same line quoting the marker exactly IS covered, so 7g is proving
        #     case-sensitivity rather than a check that has stopped covering anything at all.
        [System.IO.File]::WriteAllText((Join-Path $pin 'c.md'),
            "We claim that double-Esc is not a rewind.`nSeparately: double-Esc is not a rewind, restated verbatim.`n")
        $res = Test-HarnessPins -Root $pin -RepoRoot $pin -Registry $caseReg
        if (-not (Assert-Case '...and an exactly-quoted marker still covers' 'PASS' $res.Status)) { $failures++ }

        # 7h. MARKERS ARE CASE-SENSITIVE -- the registry-health half, isolated the other way. The
        #     fixture carries NO harness keyword, so coverage examines nothing and the only thing
        #     that can fail is the pin's own claim to point at prose that exists. A pin whose
        #     sentence survives only in a different capitalisation is quoting something that is no
        #     longer on the page, and "reworded" is exactly what that is.
        $healthReg = @{
            harness_keywords = @('Esc')
            sweep_exclusions = @()
            entries          = @(@{
                    id = 'health'; claim = 'a claim whose prose was recapitalised'
                    verified_against = '9.9.9'; verified_on = (Get-Date).ToString('yyyy-MM-dd')
                    source = 'https://example.invalid'; markers = @('the floor is the only durable constraint')
                })
        }
        [System.IO.File]::WriteAllText((Join-Path $pin 'c.md'),
            "A quotation, recapitalised: THE FLOOR IS THE ONLY DURABLE CONSTRAINT.`n")
        $res = Test-HarnessPins -Root $pin -RepoRoot $pin -Registry $healthReg
        if (-not (Assert-Case 'a pin whose prose survives only in another case is stale' 'FAIL' $res.Status)) { $failures++ }

        [System.IO.File]::WriteAllText((Join-Path $pin 'c.md'),
            "A quotation, verbatim: the floor is the only durable constraint.`n")
        $res = Test-HarnessPins -Root $pin -RepoRoot $pin -Registry $healthReg
        if (-not (Assert-Case '...and the same prose quoted exactly satisfies the pin' 'PASS' $res.Status)) { $failures++ }

        # 8. the registries the live run depends on must be shape-checked, not trusted
        $bad = Join-Path $tmp 'bad.json'
        [System.IO.File]::WriteAllText($bad, '{"not_entries": []}')
        $threw = $false
        try { $null = Import-Registry -Path $bad -Name 'bad' } catch { $threw = $true }
        if (-not (Assert-Case 'registry missing entries[] raises' 'True' $threw.ToString())) { $failures++ }

        $threw = $false
        try { $null = Import-Registry -Path (Join-Path $tmp 'does-not-exist.json') -Name 'absent' } catch { $threw = $true }
        if (-not (Assert-Case 'missing registry raises rather than passing' 'True' $threw.ToString())) { $failures++ }

        # 9. the live registries must actually load -- a self-test that never touches the real
        #    data files would go green against registries nobody can parse
        foreach ($n in @('external-citations', 'figures', 'verified-against', 'sourcing', 'prior-art')) {
            $ok = $true
            try { $null = Import-Registry -Path (Join-Path $gateDir "$n.json") -Name $n } catch { $ok = $false }
            if (-not (Assert-Case "live registry $n.json loads" 'True' $ok.ToString())) { $failures++ }
        }

        #    front-door.json keys on none of 'entries', so it needs its own line with the keys the
        #    dispatch site actually demands. Asserted with the SAME key list, deliberately: a
        #    registry that loads under a laxer shape than the live run requires is a control that
        #    passes for a file the live run would refuse.
        $ok = $true
        try {
            $null = Import-Registry -Path (Join-Path $gateDir 'front-door.json') -Name 'front-door' `
                -RequireKeys @('front_door', 'section_heading', 'repository_marker', 'worked_example', 'counter_example', 'exempt')
        }
        catch { $ok = $false }
        if (-not (Assert-Case 'live registry front-door.json loads' 'True' $ok.ToString())) { $failures++ }

        #    The class table needs its own line: it is loaded through a resolver rather than
        #    Import-Registry and it keys on 'classes' rather than 'entries', so the loop above cannot
        #    reach it. Asserted as "resolves to SOMETHING and parses", not as "resolves to the real
        #    table" -- a distribution legitimately has only the example, and a control that demanded
        #    the real one would go red in exactly the tree this fallback exists for. WHICH table was
        #    loaded is reported in the note on every live run, which is where that belongs.
        $ok = $true
        $src = ''
        try { $src = (Import-RedactionClasses -GateDir $gateDir).Source } catch { $ok = $false }
        if (-not (Assert-Case 'live redaction class table loads' 'True' $ok.ToString())) { $failures++ }
        if (-not (Assert-Case '...and names which table it resolved to' 'True' ($src -in @('real', 'example')).ToString())) { $failures++ }

        # 10. -RepoRoot / -GateDir. These are read in MAIN, before this function is reached, so the
        #     only honest way to control them is to run the script as a child process and read its
        #     exit code. The third case is the regression control for the change that added them:
        #     the environment check used to require a .github directory, so a distribution shipping
        #     tools/ and the registries and no .github was rejected as an unresolvable repository
        #     root -- a recipient running the documented command would have read a shape difference
        #     as a broken checkout.
        $envRoot = Join-Path $tmp 'envcheck'
        $null = New-Item -ItemType Directory -Path $envRoot -Force
        [System.IO.File]::WriteAllText((Join-Path $envRoot 'clean.md'), "# Clean`n`nNothing to cite here.`n")

        $null = & pwsh -NoProfile -File $PSCommandPath -RepoRoot (Join-Path $tmp 'no-such-root') 2>&1
        if (-not (Assert-Case 'absent -RepoRoot exits 1, never 0' '1' "$LASTEXITCODE")) { $failures++ }

        $null = & pwsh -NoProfile -File $PSCommandPath -RepoRoot $envRoot -GateDir (Join-Path $envRoot 'no-registries') 2>&1
        if (-not (Assert-Case 'absent -GateDir exits 1, never 0' '1' "$LASTEXITCODE")) { $failures++ }

        $out10 = & pwsh -NoProfile -File $PSCommandPath -RepoRoot $envRoot -GateDir $gateDir -DocRoot $envRoot 2>&1
        $reached = (($out10 -join "`n") -match 'PRACTICE CLAIM GATE').ToString()
        if (-not (Assert-Case 'a root with registries and no .github still runs' 'True' $reached)) { $failures++ }

        # 11. PRIOR ART -- both directions, the refusal, and the polarity that proves them.
        #
        #     The registry this reads is attribution, which fails differently from every other
        #     registry here: it does not go wrong, it goes DECORATIVE. So the controls are about the
        #     two silences -- an entry naming a document that never mentions the work, and an entry
        #     nothing mentions at all -- plus the one that makes both of them meaningless, which is a
        #     check that reports PASS with no data.
        $pa = Join-Path $tmp 'priorart'; $null = New-Item -ItemType Directory -Path $pa -Force
        $paDoc = "# Prior art`n`nThis pack stands next to obra/superpowers, read at v0.0.0.`n"
        [System.IO.File]::WriteAllText((Join-Path $pa 'p.md'), $paDoc)
        $paBase = @{
            work            = 'obra/superpowers'
            url             = 'https://example.invalid/superpowers'
            version_checked = 'v0.0.0'
            date_checked    = (Get-Date).ToString('yyyy-MM-dd')
            relationship    = 'complementary'
            claim           = 'a claim about somebody else''s moving artifact'
            cited_in        = @('p.md')
            reason          = 'self-test fixture'
        }
        # A fresh clone per control: these mutate single fields, and a control that inherited the
        # previous one's edit would pass or fail for a reason no line here states.
        #
        # Get-, not New-, and that is the analyzer's call rather than a style preference:
        # PSUseShouldProcessForStateChangingFunctions flags a New-* function that declares no
        # -WhatIf, and it is right to -- a reader seeing New- expects something to be created. This
        # one clones a hashtable in memory. Renamed rather than registered as an exemption, because
        # the finding was correct.
        function Get-PaEntry {
            param([hashtable]$Override = @{})
            $c = @{}
            foreach ($k in $paBase.Keys) { $c[$k] = $paBase[$k] }
            foreach ($k in $Override.Keys) { $c[$k] = $Override[$k] }
            return $c
        }

        $res = Test-PriorArt -Root $pa -RepoRoot $pa -Registry @{ entries = @((Get-PaEntry)) }
        if (-not (Assert-Case 'a cited, dated attribution passes' 'PASS' $res.Status)) { $failures++ }

        #     REVERSE: an entry nothing cites. The document is intact and the entry is well formed;
        #     the only thing wrong with it is that the comparison it records is not on the page any
        #     more, which is precisely the state that is invisible by reading the registry.
        $res = Test-PriorArt -Root $pa -RepoRoot $pa -Registry @{ entries = @(
                (Get-PaEntry),
                (Get-PaEntry @{ work = 'nobody/mentions-this'; cited_in = @('p.md') })) }
        if (-not (Assert-Case 'an attribution nothing cites fails as stale' 'FAIL' $res.Status)) { $failures++ }

        #     FORWARD, mode 1: the named document exists and does not mention the work. The entry
        #     claims a citation that nobody wrote, and the registry looks fuller for it.
        [System.IO.File]::WriteAllText((Join-Path $pa 'q.md'), "# Something else`n`nNo attribution here at all.`n")
        $res = Test-PriorArt -Root $pa -RepoRoot $pa -Registry @{ entries = @((Get-PaEntry @{ cited_in = @('q.md') })) }
        if (-not (Assert-Case 'cited_in naming a document that does not mention it fails' 'FAIL' $res.Status)) { $failures++ }

        #     FORWARD, mode 2: the named document is gone.
        $res = Test-PriorArt -Root $pa -RepoRoot $pa -Registry @{ entries = @((Get-PaEntry @{ cited_in = @('deleted-long-ago.md') })) }
        if (-not (Assert-Case 'cited_in naming a missing document fails' 'FAIL' $res.Status)) { $failures++ }

        #     ...and VERBATIM means verbatim. A work quoted in a different capitalisation is a
        #     different string, the same way a marker is in check D -- and this is the control that
        #     stops somebody "helpfully" loosening the compare to -match, which would let a
        #     paraphrase satisfy the reverse half forever.
        [System.IO.File]::WriteAllText((Join-Path $pa 'p.md'), "# Prior art`n`nThis pack stands next to Obra/Superpowers, read at v0.0.0.`n")
        $res = Test-PriorArt -Root $pa -RepoRoot $pa -Registry @{ entries = @((Get-PaEntry)) }
        if (-not (Assert-Case 'a work matching only in CASE does not count as cited' 'FAIL' $res.Status)) { $failures++ }
        [System.IO.File]::WriteAllText((Join-Path $pa 'p.md'), $paDoc)

        #     The four field rules, each of which is a way of filling the registry in without
        #     reading anything.
        $res = Test-PriorArt -Root $pa -RepoRoot $pa -Registry @{ entries = @((Get-PaEntry @{ version_checked = 'TBD' })) }
        if (-not (Assert-Case 'a placeholder in a required field fails' 'FAIL' $res.Status)) { $failures++ }

        $res = Test-PriorArt -Root $pa -RepoRoot $pa -Registry @{ entries = @((Get-PaEntry @{ reason = '' })) }
        if (-not (Assert-Case 'an attribution with no stated reason fails' 'FAIL' $res.Status)) { $failures++ }

        $res = Test-PriorArt -Root $pa -RepoRoot $pa -Registry @{ entries = @((Get-PaEntry @{ relationship = 'inspiration' })) }
        if (-not (Assert-Case 'an unrecognised relationship fails' 'FAIL' $res.Status)) { $failures++ }

        $res = Test-PriorArt -Root $pa -RepoRoot $pa -Registry @{ entries = @((Get-PaEntry @{ date_checked = (Get-Date).AddDays(1).ToString('yyyy-MM-dd') })) }
        if (-not (Assert-Case 'a date_checked in the future fails' 'FAIL' $res.Status)) { $failures++ }

        $res = Test-PriorArt -Root $pa -RepoRoot $pa -Registry @{ entries = @((Get-PaEntry @{ date_checked = (Get-Date).AddDays(-($MaxPinAgeDays + 30)).ToString('yyyy-MM-dd') })) }
        if (-not (Assert-Case 'a reading older than the age limit fails' 'FAIL' $res.Status)) { $failures++ }

        #     AND THE ONE THAT MATTERS MOST: no data must never be a pass. A registry that parses and
        #     holds nothing is what a pack looks like the day somebody empties the acknowledgement
        #     section, and an empty finding set is what a healthy one produces.
        $threw = $false
        try { $null = Test-PriorArt -Root $pa -RepoRoot $pa -Registry @{ entries = @() } } catch { $threw = $true }
        if (-not (Assert-Case 'an empty prior-art registry raises, never passes' 'True' $threw.ToString())) { $failures++ }

        #     ...and a root with no prose at all is INCONCLUSIVE rather than a wall of stale
        #     findings: every entry would report uncited, and the operator would be sent to fix a
        #     registry that is fine.
        $paEmpty = Join-Path $tmp 'priorart-empty'; $null = New-Item -ItemType Directory -Path $paEmpty -Force
        $res = Test-PriorArt -Root $paEmpty -RepoRoot $paEmpty -Registry @{ entries = @((Get-PaEntry)) }
        if (-not (Assert-Case 'a root with no prose is INCONCLUSIVE, not a pass' 'INCONCLUSIVE' $res.Status)) { $failures++ }

        # 12. THE NEW KEYWORD CLASS -- skill listing budget and description vocabulary.
        #
        #     Added 2026-08-19 because the keyword set had a hole exactly the shape of the one the
        #     sweep_scope whitelist had: no keyword covered skill-description or listing-budget
        #     prose, so the skill-frontmatter-loading pin was VOLUNTARY. Its markers matched the
        #     prose that happened to exist, and a new undated claim of that class anywhere under
        #     tools/ would have passed unswept -- the whitelist failure arriving on the other side of
        #     the same check. Widening it cost four findings, all of them the same claim quoted in
        #     four places, and all four were resolved by adding markers to that pin rather than by
        #     rewording the prose to dodge the keyword.
        #
        #     THE KEYWORDS COME FROM THE LIVE REGISTRY, and each case asserts the keyword BY NAME in
        #     the finding text. So this is not a test of four regexes written twice: delete or edit
        #     one of them in verified-against.json and the control fails here, which is the only way
        #     a "worked example asserted on every run" is worth anything.
        $kwDir = Join-Path $tmp 'kw'; $null = New-Item -ItemType Directory -Path $kwDir -Force
        $liveKw = @((Import-Registry -Path (Join-Path $gateDir 'verified-against.json') -Name 'verified-against').harness_keywords)
        $kwCases = @(
            @{
                keyword = '(?i)least[- ]invoked'
                example = 'On overflow the listing drops the least-invoked descriptions first.'
                # The near-miss that matters: the same two words in the other order are ordinary
                # English about how often something runs, and the harness prose uses that spelling
                # ("the skills you invoke least") one sentence away from the claim.
                counter = 'The gate is invoked least on a clean tree, which proves nothing.'
            },
            @{
                keyword = '(?i)character budget'
                example = 'The skill listing has a character budget that scales with the context window.'
                # A budget this pack sets itself is not a claim about the harness. The authoring
                # toolkit README carries this exact near-miss and must stay out of the sweep, or the
                # keyword flags the one number the documents already label a convention.
                counter = 'The byte budget is a convention with no source, and is labelled as one.'
            },
            @{
                keyword = '(?i)description[s]?[^.]{0,30}(dropped|truncated)'
                example = 'When the listing overflows, descriptions are dropped to make room.'
                # The sentence boundary is the whole point of [^.]{0,30}: a description in one
                # sentence and a dropped registry entry in the next are not one claim, and a window
                # that crossed the full stop would flag every second paragraph in this repository.
                counter = 'A description belongs in the body. The stale registry entry was dropped.'
            },
            @{
                keyword = '(?i)loads only when'
                example = "A skill's body loads only when it is used, so length there is nearly free."
                # "loads only once, when" is a claim about frequency, not about laziness. It is also
                # the shape the memory prose uses, and it must not be dragged into a pin about skill
                # loading.
                counter = 'The index loads only once, when the session starts.'
            }
        )
        foreach ($c in $kwCases) {
            if (-not ($liveKw -contains $c.keyword)) {
                Write-Host ("  [FAIL] {0,-52} expected {1}, got {2}" -f "keyword '$($c.keyword)' is in the live registry", 'present', 'absent')
                $failures++
                continue
            }
            # entries = @() on purpose: with no pins there are no markers, so the ONLY thing that can
            # produce a finding is the keyword firing. A dummy pin would have to carry a marker, and
            # a marker that missed would fail this control for the wrong reason.
            $kwReg = @{ harness_keywords = $liveKw; sweep_exclusions = @(); entries = @() }

            [System.IO.File]::WriteAllText((Join-Path $kwDir 'k.md'), ($c.example + "`n"))
            $res = Test-HarnessPins -Root $kwDir -RepoRoot $kwDir -Registry $kwReg
            # String.Contains, NOT -like. A keyword is a REGEX, and two of these four carry `[- ]`,
            # `[s]?` and `[^.]{0,30}` -- which -like reads as wildcard character classes, so the
            # pattern matched nothing and two controls reported the keyword had not fired when it
            # had. Caught 2026-08-19 on the first run of this block, which is the whole argument for
            # asserting the keyword BY NAME rather than settling for a FAIL status: a status-only
            # assertion would have gone green on the wrong keyword and told nobody.
            $named = (($res.Findings -join ' ').Contains("keyword '" + $c.keyword + "'")).ToString()
            if (-not (Assert-Case "keyword '$($c.keyword)' fires on its worked example" 'True' $named)) { $failures++ }

            [System.IO.File]::WriteAllText((Join-Path $kwDir 'k.md'), ($c.counter + "`n"))
            $res = Test-HarnessPins -Root $kwDir -RepoRoot $kwDir -Registry $kwReg
            if (-not (Assert-Case '...and no keyword fires on its counter-example' '0' ([string]$res.Findings.Count))) { $failures++ }
        }

        # 13. THE FRONT DOOR -- both directions, the refusals, and the two inversions that decide
        #     whether this check is worth having.
        #
        #     The defect it exists for is an omission, so every control here is about a SILENCE
        #     rather than about a wrong string: an entry nothing mentions, a row pointing at nothing,
        #     an exemption covering nothing, a heading that has gone and taken the check with it. The
        #     last of those is the one that matters most, because it is the only way this check can
        #     fail OPEN -- delete the section and a heading-keyed applicability test would report the
        #     tree as a distribution and pass. So 13d and 13e are a matched pair and must stay one:
        #     no marker is SKIPPED, marker and no heading is FAIL, and nothing may be PASS.
        $fdRoot = Join-Path $tmp 'frontdoor'
        $fdTools = Join-Path $fdRoot 'tools'
        $null = New-Item -ItemType Directory -Path (Join-Path $fdTools 'alpha-toolkit') -Force
        [System.IO.File]::WriteAllText((Join-Path $fdTools 'beta.ps1'), "# fixture`n")
        [System.IO.File]::WriteAllText((Join-Path $fdRoot 'PACK-README.md'), "# the pack's front door (fixture)`n")

        # The fixture front door. A trailing section AFTER the tools section on purpose: the third
        # unit is mentioned only there, so 13b also asserts that the section boundary is real and
        # that a mention elsewhere in the document does not count as documentation of a unit.
        function Write-FdReadme {
            param([string]$Body, [string]$Heading = '## Tools')
            [System.IO.File]::WriteAllText((Join-Path $fdRoot 'README.md'),
                "# fixture`n`n$Heading`n`n$Body`n`n## Something else`n`nMentions tools/gamma out of scope.`n")
        }
        $fdReg = @{
            front_door        = 'README.md'
            section_heading   = '## Tools'
            repository_marker = 'PACK-README.md'
            worked_example    = @{ unit = 'alpha-toolkit'; reason = 'self-test fixture' }
            counter_example   = @{ unit = 'alpha-toolkit-extra'; reason = 'self-test fixture' }
            exempt            = @()
        }
        $fdComplete = "| [``alpha-toolkit/``](tools/alpha-toolkit/README.md) | a unit |`n| [``tools/beta.ps1``](tools/beta.ps1) | a script |"

        # 13a. the baseline: a section naming every entry passes. Without this every FAIL below could
        #      be the check being broken rather than the fixture being wrong.
        Write-FdReadme -Body $fdComplete
        $res = Test-FrontDoor -Root $fdTools -RepoRoot $fdRoot -Registry $fdReg
        if (-not (Assert-Case 'a section naming every entry passes' 'PASS' $res.Status)) { $failures++ }

        # 13b. FORWARD: an entry the section does not name. This is the measured defect, reproduced.
        #      The finding must NAME the unit -- a status-only assertion would go green on the wrong
        #      one and tell nobody, which is the lesson control 12 records.
        Write-FdReadme -Body "| [``alpha-toolkit/``](tools/alpha-toolkit/README.md) | a unit |"
        $res = Test-FrontDoor -Root $fdTools -RepoRoot $fdRoot -Registry $fdReg
        if (-not (Assert-Case 'an undocumented entry fails' 'FAIL' $res.Status)) { $failures++ }
        $named = (($res.Findings -join ' ').Contains('tools/beta.ps1 exists')).ToString()
        if (-not (Assert-Case '...naming the unit the front door omits' 'True' $named)) { $failures++ }

        # 13c. REVERSE: a row for a unit that is not there. The quieter half -- it reads exactly like
        #      a row for one that is.
        Write-FdReadme -Body ($fdComplete + "`n| [``tools/delta-toolkit/``](tools/delta-toolkit/README.md) | gone |")
        $res = Test-FrontDoor -Root $fdTools -RepoRoot $fdRoot -Registry $fdReg
        if (-not (Assert-Case 'a row for a unit that does not exist fails as stale' 'FAIL' $res.Status)) { $failures++ }
        $named = (($res.Findings -join ' ').Contains("names 'tools/delta-toolkit'")).ToString()
        if (-not (Assert-Case '...naming the row to strike' 'True' $named)) { $failures++ }

        # 13c-nm. THE NEAR-MISS, AND IT IS THE CASE THAT MATTERS. A row for alpha-toolkit-extra must
        #      fail even though alpha-toolkit is on disk. Under -contains, StartsWith or -like it
        #      would resolve against its shorter sibling, and a stale row would sit there green
        #      forever -- which is the failure the reverse direction was added to catch.
        Write-FdReadme -Body ($fdComplete + "`n| [``tools/alpha-toolkit-extra/``](tools/alpha-toolkit-extra/README.md) | near miss |")
        $res = Test-FrontDoor -Root $fdTools -RepoRoot $fdRoot -Registry $fdReg
        if (-not (Assert-Case 'a near-miss row is NOT satisfied by its prefix' 'FAIL' $res.Status)) { $failures++ }

        # 13c-case. Case is part of the name. A row spelled Alpha-toolkit is a link that 404s on a
        #      case-sensitive forge, and PowerShell's -contains would have called it a match.
        Write-FdReadme -Body "| [``tools/Alpha-toolkit/``](tools/Alpha-toolkit/README.md) | wrong case |`n| [``tools/beta.ps1``](tools/beta.ps1) | a script |"
        $res = Test-FrontDoor -Root $fdTools -RepoRoot $fdRoot -Registry $fdReg
        if (-not (Assert-Case 'a row differing only in case does not satisfy the check' 'FAIL' $res.Status)) { $failures++ }

        # 13d. FAIL CLOSED. The heading is gone, and the marker says this is the repository -- so
        #      there is no honest reading of this tree as complete. Nothing here may be PASS.
        Write-FdReadme -Body $fdComplete -Heading '## Toolss'
        $res = Test-FrontDoor -Root $fdTools -RepoRoot $fdRoot -Registry $fdReg
        if (-not (Assert-Case 'a mangled section heading FAILS, never passes' 'FAIL' $res.Status)) { $failures++ }
        $named = (($res.Findings -join ' ').Contains("no line reading exactly '## Tools'")).ToString()
        if (-not (Assert-Case '...quoting the heading it looked for' 'True' $named)) { $failures++ }

        # 13d-empty. A section that is present and names nothing is the extractor-broke case wearing
        #      a valid document, and it must not pass either.
        Write-FdReadme -Body 'Prose with no unit reference in it at all.'
        $res = Test-FrontDoor -Root $fdTools -RepoRoot $fdRoot -Registry $fdReg
        if (-not (Assert-Case 'a section naming no unit at all fails' 'FAIL' $res.Status)) { $failures++ }

        # 13d-h3. THE SECTION BOUNDARY IS `## `, NOT `##`. The live section carries level-3
        #      subheadings, and a terminator that stopped at the first of those would read one table
        #      out of two and call every unit in the second undocumented -- a red gate for a
        #      complete document, which costs as much as a green one for an incomplete one.
        Write-FdReadme -Body "### Toolkits`n`n| [``tools/alpha-toolkit/``](tools/alpha-toolkit/README.md) | a unit |`n`n### Scripts`n`n| [``tools/beta.ps1``](tools/beta.ps1) | a script |"
        $res = Test-FrontDoor -Root $fdTools -RepoRoot $fdRoot -Registry $fdReg
        if (-not (Assert-Case 'level-3 subheadings do not truncate the section' 'PASS' $res.Status)) { $failures++ }

        # 13e. ...and the other polarity of 13d, which is what makes it meaningful. No marker means
        #      the README.md here is a distribution's front door -- a different document -- and the
        #      answer is SKIPPED. If this were PASS, 13d would be the only thing standing between a
        #      deleted section and a green gate.
        $fdDist = Join-Path $tmp 'frontdoor-dist'
        $null = New-Item -ItemType Directory -Path (Join-Path $fdDist 'tools/alpha-toolkit') -Force
        [System.IO.File]::WriteAllText((Join-Path $fdDist 'README.md'), "# a distribution's front door`n`n## What's inside`n`nNo tools section here.`n")
        $res = Test-FrontDoor -Root (Join-Path $fdDist 'tools') -RepoRoot $fdDist -Registry $fdReg
        if (-not (Assert-Case 'a tree with no source marker reports SKIPPED' 'SKIPPED' $res.Status)) { $failures++ }

        # 13e-door. The marker is there and the front door is not: a repository that has lost its
        #      README is not a distribution, and must not borrow the SKIPPED verdict.
        $fdNoDoor = Join-Path $tmp 'frontdoor-nodoor'
        $null = New-Item -ItemType Directory -Path (Join-Path $fdNoDoor 'tools/alpha-toolkit') -Force
        [System.IO.File]::WriteAllText((Join-Path $fdNoDoor 'PACK-README.md'), "# fixture`n")
        $res = Test-FrontDoor -Root (Join-Path $fdNoDoor 'tools') -RepoRoot $fdNoDoor -Registry $fdReg
        if (-not (Assert-Case 'marker present and front door missing FAILS' 'FAIL' $res.Status)) { $failures++ }

        # 13f. AN EMPTY UNIT LIST REFUSES. It would agree with every section ever written, including
        #      one that documents nothing -- the same refusal the empty keyword set makes in check D.
        $fdEmpty = Join-Path $tmp 'frontdoor-empty'
        $null = New-Item -ItemType Directory -Path (Join-Path $fdEmpty 'tools') -Force
        [System.IO.File]::WriteAllText((Join-Path $fdEmpty 'PACK-README.md'), "# fixture`n")
        [System.IO.File]::WriteAllText((Join-Path $fdEmpty 'README.md'), "# fixture`n`n## Tools`n`nSee tools/alpha-toolkit/README.md.`n")
        $threw = $false
        try { $null = Test-FrontDoor -Root (Join-Path $fdEmpty 'tools') -RepoRoot $fdEmpty -Registry $fdReg } catch { $threw = $true }
        if (-not (Assert-Case 'an empty unit list raises, never passes' 'True' $threw.ToString())) { $failures++ }

        # 13g. A BLANK REGISTRY FIELD RAISES rather than defaulting to something plausible. A guessed
        #      heading or a guessed marker is a check about a document nobody chose.
        Write-FdReadme -Body $fdComplete
        foreach ($blank in @('front_door', 'section_heading', 'repository_marker')) {
            $bad = @{
                front_door        = 'README.md'
                section_heading   = '## Tools'
                repository_marker = 'PACK-README.md'
                worked_example    = @{ unit = 'alpha-toolkit'; reason = 'fixture' }
                counter_example   = @{ unit = 'alpha-toolkit-extra'; reason = 'fixture' }
                exempt            = @()
            }
            $bad[$blank] = ''
            $threw = $false
            try { $null = Test-FrontDoor -Root $fdTools -RepoRoot $fdRoot -Registry $bad } catch { $threw = $true }
            if (-not (Assert-Case "a blank '$blank' raises" 'True' $threw.ToString())) { $failures++ }
        }

        # 13h. THE CONTROLS THEMSELVES. A worked example the section does not name means the positive
        #      control did not fire, and a run in which it did not fire proves nothing at all.
        $missWe = @{
            front_door = 'README.md'; section_heading = '## Tools'; repository_marker = 'PACK-README.md'
            worked_example = @{ unit = 'beta.ps1'; reason = 'fixture' }
            counter_example = @{ unit = 'alpha-toolkit-extra'; reason = 'fixture' }
            exempt = @()
        }
        Write-FdReadme -Body "| [``alpha-toolkit/``](tools/alpha-toolkit/README.md) | a unit |"
        $res = Test-FrontDoor -Root $fdTools -RepoRoot $fdRoot -Registry $missWe
        $named = (($res.Findings -join ' ').Contains('worked example')).ToString()
        if (-not (Assert-Case 'a worked example the section omits is reported as such' 'True' $named)) { $failures++ }

        # 13h-ce. ...and a counter-example that is not an extension of any entry is a control that
        #      cannot prove what it is for. Asserting that 'zzz-nonesuch' does not resolve says
        #      nothing about whether the comparison is exact; only a name a prefix-wise match WOULD
        #      have accepted can show that.
        Write-FdReadme -Body $fdComplete
        $vacuousCe = @{
            front_door = 'README.md'; section_heading = '## Tools'; repository_marker = 'PACK-README.md'
            worked_example = @{ unit = 'alpha-toolkit'; reason = 'fixture' }
            counter_example = @{ unit = 'zzz-nonesuch'; reason = 'fixture' }
            exempt = @()
        }
        $res = Test-FrontDoor -Root $fdTools -RepoRoot $fdRoot -Registry $vacuousCe
        if (-not (Assert-Case 'a counter-example extending nothing fails as vacuous' 'FAIL' $res.Status)) { $failures++ }

        # 13i. AN EXEMPTION IS A DECISION, AND A DECISION HAS A REASON. Without one it is a silencer,
        #      which is what this whole registry exists instead of.
        Write-FdReadme -Body "| [``alpha-toolkit/``](tools/alpha-toolkit/README.md) | a unit |"
        $noReason = $fdReg.Clone(); $noReason.exempt = @(@{ entry = 'beta.ps1' })
        $res = Test-FrontDoor -Root $fdTools -RepoRoot $fdRoot -Registry $noReason
        if (-not (Assert-Case 'an exemption with no reason fails' 'FAIL' $res.Status)) { $failures++ }

        # 13j. ...and with a reason it works, which is the escape hatch behaving as designed. Without
        #      this the registry would be a list nobody can ever add to.
        $withReason = $fdReg.Clone()
        $withReason.exempt = @(@{ entry = 'beta.ps1'; reason = 'self-test fixture -- deliberately not in the front door' })
        $res = Test-FrontDoor -Root $fdTools -RepoRoot $fdRoot -Registry $withReason
        if (-not (Assert-Case 'a registered exemption with a reason passes' 'PASS' $res.Status)) { $failures++ }

        # 13k. THE REVERSE DIRECTION ON THE EXEMPTIONS, mode 1: the file it was written for is gone,
        #      so the exemption now covers nothing and the next unit to land on that name inherits it.
        $goneExempt = $fdReg.Clone()
        $goneExempt.exempt = @(@{ entry = 'gamma.ps1'; reason = 'self-test fixture' })
        Write-FdReadme -Body $fdComplete
        $res = Test-FrontDoor -Root $fdTools -RepoRoot $fdRoot -Registry $goneExempt
        if (-not (Assert-Case 'an exemption naming nothing on disk fails as stale' 'FAIL' $res.Status)) { $failures++ }

        # 13l. ...mode 2, and the quieter one: somebody documented the unit anyway. The exemption is
        #      now suppressing a finding that no longer exists, and reading it tells you nothing.
        $redundant = $fdReg.Clone()
        $redundant.exempt = @(@{ entry = 'beta.ps1'; reason = 'self-test fixture' })
        $res = Test-FrontDoor -Root $fdTools -RepoRoot $fdRoot -Registry $redundant
        if (-not (Assert-Case 'an exemption for a documented unit fails as stale' 'FAIL' $res.Status)) { $failures++ }
    }
    finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host ""
    if ($failures -gt 0) {
        Write-Host "SELF-TEST FAILED -- $failures control(s) did not behave as specified" -ForegroundColor Red
        return 1
    }
    Write-Host "SELF-TEST PASSED -- every control behaved as specified" -ForegroundColor Green
    return 0
}

# ── MAIN ────────────────────────────────────────────────────────────────────────

if (-not $DocRoot) { $DocRoot = $PSScriptRoot }
$DocRoot = (Resolve-Path -LiteralPath $DocRoot).Path
if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot '..' }
if (-not (Test-Path -LiteralPath $RepoRoot)) {
    Write-Host "ENVIRONMENT: -RepoRoot '$RepoRoot' does not exist" -ForegroundColor Red
    Write-Host "A gate that cannot locate its subject must not report PASS." -ForegroundColor Red
    exit 1
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
if (-not $GateDir) { $GateDir = Join-Path $RepoRoot 'tools/practice-gate' }

# Resolve against the thing this gate ACTUALLY reads, not a proxy for it. This used to test for a
# .github directory, which is neither necessary nor sufficient: a share pack ships the registries
# and no .github, so the gate exited 1 there reporting an unresolvable repository root -- a
# recipient running the documented command would have read that as a broken checkout. Meanwhile a
# repository with .github and no registries got past this line and failed later, further from the
# cause. Test the registries.
if (-not (Test-Path -LiteralPath $GateDir)) {
    Write-Host "ENVIRONMENT: no registry directory at $GateDir" -ForegroundColor Red
    Write-Host "Pass -GateDir if the registries live elsewhere in this distribution." -ForegroundColor Red
    Write-Host "A gate that cannot locate its subject must not report PASS." -ForegroundColor Red
    exit 1
}
$GateDir = (Resolve-Path -LiteralPath $GateDir).Path

if ($SelfTest) { exit (Invoke-SelfTest -RepoRoot $RepoRoot -GateDir $GateDir) }

$gateDir = $GateDir
$results = [System.Collections.Generic.List[CheckResult]]::new()

$allChecks = @('Citations', 'Sourcing', 'Figures', 'Redaction', 'HarnessPins', 'Assertions', 'PriorArt', 'FrontDoor')

# -Only is scope, -Skip is refusal, and they make incompatible claims about the same run. Resolving
# the contradiction silently would mean guessing which one the caller meant, and the wrong guess is
# an exit code that reads as a verdict it did not earn.
if ($Only.Count -gt 0 -and $Skip.Count -gt 0) {
    Write-Host "ENVIRONMENT: -Only and -Skip are mutually exclusive." -ForegroundColor Red
    Write-Host "-Only says what the run consists of; -Skip says what it declined to run." -ForegroundColor Red
    exit 1
}
# The outer @() is load-bearing: an `if` used as an expression unrolls a one-element result to a
# scalar, and under Set-StrictMode -Version Latest a scalar has no .Count to fall back on. The
# single-check case -- which is the whole point of -Only -- is exactly the one that would break.
$selected = @(if ($Only.Count -gt 0) { $allChecks | Where-Object { $Only -contains $_ } } else { $allChecks })

foreach ($name in $selected) {
    if ($Skip -contains $name) {
        $r = [CheckResult]::new($name)
        $r.Status = 'SKIPPED'
        $r.Note = 'deliberately not run (-Skip) -- this is not a pass'
        $results.Add($r)
        continue
    }
    switch ($name) {
        'Citations' { $results.Add((Test-Citations   -Root $DocRoot -RepoRoot $RepoRoot -Registry (Import-Registry -Path (Join-Path $gateDir 'external-citations.json') -Name 'external-citations'))) }
        'Sourcing' { $results.Add((Test-Sourcing    -Root $DocRoot -RepoRoot $RepoRoot -Registry (Import-Registry -Path (Join-Path $gateDir 'sourcing.json') -Name 'sourcing'))) }
        'Figures' { $results.Add((Test-Figures     -Root $DocRoot -RepoRoot $RepoRoot -Registry (Import-Registry -Path (Join-Path $gateDir 'figures.json') -Name 'figures'))) }
        # -GateDir rather than a pre-loaded -Registry: this is the one check whose registry has a
        # fallback, and the fallback has to be reported. Resolving it at the call site would put the
        # decision here and the note there.
        'Redaction' { $results.Add((Test-Redaction   -Root $DocRoot -RepoRoot $RepoRoot -GateDir $gateDir)) }
        'HarnessPins' { $results.Add((Test-HarnessPins -Root $DocRoot -RepoRoot $RepoRoot -Registry (Import-Registry -Path (Join-Path $gateDir 'verified-against.json') -Name 'verified-against'))) }
        # Not scoped by -DocRoot: this one deliberately reaches OUTSIDE tools/, to documents that
        # cannot live under the redaction check. Its scope is the registry, not the tree walk.
        'Assertions' { $results.Add((Test-Assertions  -RepoRoot $RepoRoot -Registry (Import-Registry -Path (Join-Path $gateDir 'assertions.json') -Name 'assertions' -RequireKeys @('scope', 'negative_claim_markers')))) }
        # Scoped by -DocRoot like the other tree walks: the reverse half asks whether anything in
        # the scanned prose still cites each work, so the root it sweeps IS the question.
        'PriorArt' { $results.Add((Test-PriorArt    -Root $DocRoot -RepoRoot $RepoRoot -Registry (Import-Registry -Path (Join-Path $gateDir 'prior-art.json') -Name 'prior-art'))) }
        # BOTH roots, and both are load-bearing: -DocRoot is the tree whose entries are enumerated,
        # -RepoRoot is where the front door and the marker that identifies it live. This is the
        # second check that reaches outside -DocRoot, and unlike Assertions it still walks the tree
        # -- so it needs the pair rather than a registry standing in for one of them.
        'FrontDoor' { $results.Add((Test-FrontDoor   -Root $DocRoot -RepoRoot $RepoRoot -Registry (Import-Registry -Path (Join-Path $gateDir 'front-door.json') -Name 'front-door' -RequireKeys @('front_door', 'section_heading', 'repository_marker', 'worked_example', 'counter_example', 'exempt')))) }
    }
}

# ── REPORT ──────────────────────────────────────────────────────────────────────

$out = [System.Text.StringBuilder]::new()
function Emit { param([string]$Text, [string]$Colour = 'Gray'); Write-Host $Text -ForegroundColor $Colour; $null = $out.AppendLine($Text) }

Emit ""
Emit "PRACTICE CLAIM GATE -- $DocRoot"
# A scoped run's PASS must not read like the full gate's PASS. Say what ran, in the report and in
# the final line, or "RESULT: PASS" over one check of six is a true sentence that misleads.
if ($Only.Count -gt 0) {
    Emit ("SCOPED RUN (-Only): {0}. The other {1} check(s) were not applicable to this root, not declined." -f ($selected -join ', '), ($allChecks.Count - $selected.Count)) 'Cyan'
}
Emit ("=" * 78)

foreach ($r in $results) {
    $colour = switch ($r.Status) {
        'PASS' { 'Green' } 'FAIL' { 'Red' } 'INCONCLUSIVE' { 'Red' } 'SKIPPED' { 'Yellow' } default { 'Gray' }
    }
    Emit ("{0,-14} {1,-13} {2,5} candidate(s){3}" -f $r.Name, $r.Status, $r.Candidates, $(if ($r.Note) { "  -- $($r.Note)" } else { '' })) $colour
    # ASCII only: this runs on windows-latest, where a non-ASCII bullet came back as a
    # replacement character and made the log unreadable. The output boundary is part of the tool.
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
elseif ($Only.Count -gt 0) {
    Emit ("RESULT: PASS -- every check IN SCOPE ran and passed ({0})" -f ($selected -join ', ')) 'Green'
    $exit = 0
}
else {
    Emit "RESULT: PASS -- every check ran and passed" 'Green'
    $exit = 0
}
Emit ""

if ($ReportPath) {
    # WriteAllText, not Set-Content: Set-Content supports ShouldProcess and silently skips the
    # write under -WhatIf, which would leave a report nobody notices is missing.
    [System.IO.File]::WriteAllText($ReportPath, $out.ToString())
    Write-Host "report written to $ReportPath"
}

exit $exit
