param(
    [Parameter(Mandatory=$true)]
    [string]$RepoPath,

    [Parameter(Mandatory=$true)]
    [string]$TeknoParrotRoot,

    [string]$HarnessRoot,

    [string]$ReportDirectory,

    [string]$OperatorStatusPath,

    [switch]$RunUnattendedTPM,

    # Optional operator-pinned identity. When supplied, the sealed
    # repository fact must match both values and the cached upstream ref must
    # point at the same commit. The start/end snapshots below still protect
    # runs where an operator records identity separately.
    [string]$ExpectedBranch,

    [string]$ExpectedCommit,

    # Summary (default): only the final certification scorecard and any real
    # test failures reach the console -- the underlying Pester run (which
    # includes noisy Write-Host output from mocked production-code scenarios,
    # e.g. auto-update destructive-path tests) is captured to file only.
    # Detailed: Pester's own per-file/per-test progress, as before this
    # parameter existed. Diagnostic: Pester's own Diagnostic verbosity (full
    # mock/trace output) on top of Detailed. All three levels always write
    # the same full report files -- this only controls what streams to the
    # console during the run.
    [ValidateSet('Summary', 'Detailed', 'Diagnostic')]
    [string]$VerbosityLevel = 'Summary',

    # Issue #136: hard ceiling on the Pester regression gate. A full local
    # run of the whole Tests\ folder takes well under a minute; 1800s (30
    # minutes) is generous headroom for slower real-hardware I/O while still
    # guaranteeing the certification run cannot hang forever. Exposed as a
    # parameter (not a hardcoded constant) so a real slow-hardware run can
    # raise it without a code change, and so tests can exercise a near-zero
    # timeout without waiting.
    [int]$PesterRegressionTimeoutSeconds = 1800
)

$ErrorActionPreference = "Stop"
$runTimer = [System.Diagnostics.Stopwatch]::StartNew()

. (Join-Path $PSScriptRoot 'Resolve-Pcsx2Directory.ps1')
Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Execution.psm1') -Force
# ADR155-0309 Checkpoint B2: the production authority is the sole
# certification decision/publication path. TPMCertification.Shadow.psm1 is
# deliberately not imported here -- Phase 2's shadow adapter is
# placeholder-tolerant and never-authoritative; production facts/evidence
# come from TPMCertification.ProductionFacts.psm1 and
# TPMCertification.ProductionEvidence.psm1 instead. Each module is imported
# directly here rather than assumed to already be loaded transitively by
# another import -- confirmed in Checkpoint B1 that a nested Import-Module
# call from within one module does not reliably expose that module's own
# exports to a sibling module's Get-Command calls.
Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Authority.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Production.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Reports.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Publication.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'TPMCertification.ProductionFacts.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'TPMCertification.ProductionCycle.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'TPMCertification.ProductionEvidence.psm1') -Force

$RepoPath = (Resolve-Path -LiteralPath $RepoPath).ProviderPath
$certificationRepositoryLock = Enter-TPMCertificationRepositoryLockV1 -RepositoryPath $RepoPath
$certificationIdentityStart = Get-TPMCertificationGitIdentitySnapshotV1 -RepositoryPath $RepoPath
if (!(Test-Path -LiteralPath $TeknoParrotRoot -PathType Container)) {
    throw "TeknoParrot root not found: $TeknoParrotRoot"
}
$TeknoParrotRoot = (Resolve-Path -LiteralPath $TeknoParrotRoot).Path
$gitScopedArguments = @('-c', ("safe.directory={0}" -f $RepoPath), '-C', $RepoPath)

if ([string]::IsNullOrWhiteSpace($HarnessRoot)) {
    $repoParent = Split-Path -Parent $RepoPath
    $HarnessRoot = Join-Path $repoParent "TPM-TestHarness"
}

$stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportDir = if ([string]::IsNullOrWhiteSpace($ReportDirectory)) { Join-Path $HarnessRoot "Reports\$stamp" } else { [IO.Path]::GetFullPath($ReportDirectory) }
$backupDir = Join-Path $HarnessRoot "Backups\$stamp"
# ADR155-0309 round 3: HarnessRoot is this harness's own top-level trusted
# boundary, but Assert-TPMOwnedDirectoryV1 requires a trusted ROOT to
# already exist -- HarnessRoot itself may not exist yet on a first run, so
# it cannot be its own bootstrap root. The genuinely already-existing
# anchor one level further up is HarnessRoot's own parent directory (in
# the default case, the same directory containing the resolved repository
# checkout). $reportDir/$backupDir are brought into existence one
# authorized, reparse-checked level at a time via
# New-TPMOwnedDirectoryChainV1 (see scripts/TPMCertification.Execution.psm1),
# never via a raw New-Item -Force that would silently create untracked
# intermediate levels ("Reports"/"Backups") without ever reparse-checking
# them -- the exact gap the prior round's root==target collapse left open.
# A caller-supplied -ReportDirectory that does not actually resolve under
# HarnessRoot's parent is rejected here (PROCESS_PATH_OUTSIDE_OWNED_ROOT)
# rather than silently trusted.
$harnessRootParent = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($HarnessRoot))
if ([string]::IsNullOrEmpty($harnessRootParent)) { throw "PROCESS_DIRECTORY_INVALID: HarnessRoot has no resolvable parent directory to anchor trust in: $HarnessRoot" }
[void](New-TPMOwnedDirectoryChainV1 -Root $harnessRootParent -Path $reportDir)
[void](New-TPMOwnedDirectoryChainV1 -Root $harnessRootParent -Path $backupDir)

# Issue #151: certification evidence screenshots. Beneath $reportDir, not a
# separate top-level folder -- keeps every artifact for one certification
# run (reports, Pester output, screenshots) under the same timestamped
# directory. Created lazily by New-TPMCertificationScreenshot itself, not
# here, so "screenshot directory creation" is covered by that function's
# own regression tests rather than assumed to already exist.
$screenshotDir = Join-Path $reportDir "Screenshots"

# ADR155-0309 Checkpoint B2: $reportDir is the sole authoritative
# publication destination -- TPM-Certification-{Eligibility,Publication,
# Final-Outcome,Scorecard,Validation,Manifest,Commit}.{json,md} are written
# there only by New-TPMPublicationCommitV1 (via
# Complete-TPMProductionCertificationCycleV1, far below), never by this
# harness directly. The legacy TPM-Validation-Report.{md,json}/
# TPM-Certification-Scorecard.{md,json} files, and the Add-Report/
# Add-CertificationReport accumulators that built them, are removed --
# their only consumer was the legacy Publish-TPMCertificationArtifacts
# builder (also removed; see the problem-class sweep below).
$productionStagingParentRoot = Join-Path $HarnessRoot 'ProductionStaging'
$productionWorkingDirectory = Join-Path $HarnessRoot "ProductionWork\$stamp"
# ADR155-0309 round 3: establish $productionWorkingDirectory (two levels
# below HarnessRoot: "ProductionWork", then the run-specific $stamp) one
# authorized level at a time, same discipline as $reportDir/$backupDir
# above. Once established here it is itself a validated, already-existing
# path, so it is passed as its own trusted root (Root == Target, the
# deliberately supported degenerate case) to the parser-probe isolation
# calls deeper inside TPMCertification.ProductionFacts.psm1.
[void](New-TPMOwnedDirectoryChainV1 -Root $HarnessRoot -Path $productionWorkingDirectory)

function Copy-IfExists {
    param([string]$Path, [string]$DestName)
    if (Test-Path -LiteralPath $Path) {
        Copy-Item -LiteralPath $Path -Destination (Join-Path $backupDir $DestName) -Recurse -Force
        return $true
    }
    return $false
}

function Get-TreeHash {
    # Issue #172: a bare "return @()" collapses to $null at the caller --
    # capturing zero pipeline objects into a variable always yields $null,
    # not an empty array, on this environment (confirmed by direct
    # reproduction; the same class already documented in LESSONS_LEARNED.md
    # under "return @() unwraps to $null"). An absent tree must produce a
    # real, zero-length snapshot, not $null, so every caller downstream can
    # trust "no entries" without re-deriving it from a null check of its
    # own. The comma operator forces this return to be captured as a
    # genuine empty array.
    param([string]$Path)
    if (!(Test-Path -LiteralPath $Path)) { return ,@() }
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $base = $resolved.TrimEnd('\')
    Get-ChildItem -LiteralPath $resolved -Recurse -File -ErrorAction SilentlyContinue |
        Sort-Object FullName |
        ForEach-Object {
            $relative = $_.FullName
            if ($_.FullName.Length -gt $base.Length) {
                $relative = $_.FullName.Substring($base.Length).TrimStart('\')
            }
            if ([string]::IsNullOrWhiteSpace($relative)) {
                $relative = $_.Name
            }
            $h = Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256
            [pscustomobject]@{
                RelativePath = $relative
                Path = $_.FullName
                Hash = $h.Hash
                Length = $_.Length
            }
        }
}

function Compare-TreeSnapshot {
    # Issue #172: defensive, caller-independent normalization. Whatever
    # produced $Before/$After -- Get-TreeHash's own absent-tree case (now
    # fixed above), a future caller that passes $null directly, or any
    # other producer -- a missing/null snapshot argument must become a
    # real, zero-entry snapshot here too, never a phantom one-element
    # array. Confirmed by direct reproduction: wrapping a genuinely $null
    # argument in "@($Before)" produces a ONE-element array containing a
    # single $null (PowerShell's "@($null)" behavior), which the per-item
    # loop below then counted as one skipped entry that never actually
    # existed. Both branches of the null-check are comma-wrapped -- also
    # confirmed by direct reproduction that an un-wrapped empty-array
    # branch of an if/else collapses to $null under this same "captured by
    # assignment" rule, even on the branch that is not the $null case.
    #
    # This normalization only ever collapses a null/absent ARGUMENT to
    # empty. It does not touch the per-item loop below, which still flags
    # a genuinely malformed entry (a real $null element, or a real element
    # with a blank RelativePath) inside an otherwise non-empty snapshot as
    # skipped -- that fail-closed behavior is unchanged and still exercised
    # by a snapshot that legitimately contains such an entry.
    param([object[]]$Before, [object[]]$After)
    $beforeItems = if ($null -eq $Before) { ,@() } else { ,@($Before) }
    $afterItems = if ($null -eq $After) { ,@() } else { ,@($After) }
    $beforeMap = @{}
    $beforeSkipped = 0
    foreach ($item in $beforeItems) {
        if (-not $item -or [string]::IsNullOrWhiteSpace([string]$item.RelativePath)) { $beforeSkipped++; continue }
        $beforeMap[[string]$item.RelativePath] = $item.Hash
    }
    $afterMap = @{}
    $afterSkipped = 0
    foreach ($item in $afterItems) {
        if (-not $item -or [string]::IsNullOrWhiteSpace([string]$item.RelativePath)) { $afterSkipped++; continue }
        $afterMap[[string]$item.RelativePath] = $item.Hash
    }
    $added = 0
    $removed = 0
    $changed = 0
    foreach ($key in $afterMap.Keys) {
        if (-not $beforeMap.ContainsKey($key)) { $added++ }
        elseif ($beforeMap[$key] -ne $afterMap[$key]) { $changed++ }
    }
    foreach ($key in $beforeMap.Keys) {
        if (-not $afterMap.ContainsKey($key)) { $removed++ }
    }
    [pscustomobject]@{
        BeforeCount = $beforeItems.Count
        AfterCount = $afterItems.Count
        Added = $added
        Removed = $removed
        Changed = $changed
        BeforeSkipped = $beforeSkipped
        AfterSkipped = $afterSkipped
    }
}

# Issue #146: the requested -TeknoParrotRoot was previously only checked for
# existing as SOME container (line ~40, still first), then the three
# installation markers below were checked much later (informationally, not
# gating) after Pester/PSScriptAnalyzer/backups had already run against it.
# A real certification run against a root that was not a TeknoParrot install
# at all (missing all three markers) still produced an 8/9 scorecard instead
# of failing fast with an unambiguous "this environment is not a TeknoParrot
# install" result. Pure/testable so the exact marker set can be verified
# without needing a real install on disk.
function Test-TPMCertificationRootValid {
    param([string]$TeknoParrotRoot)
    $markers = @(
        [pscustomobject]@{ Name = 'TeknoParrotUi.exe'; RelativePath = 'TeknoParrotUi.exe'; Type = 'Leaf' }
        [pscustomobject]@{ Name = 'GameProfiles';      RelativePath = 'GameProfiles';      Type = 'Container' }
        [pscustomobject]@{ Name = 'UserProfiles';      RelativePath = 'UserProfiles';      Type = 'Container' }
    )
    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($m in $markers) {
        $path = Join-Path $TeknoParrotRoot $m.RelativePath
        if (-not (Test-Path -LiteralPath $path -PathType $m.Type)) {
            [void]$missing.Add($m.Name)
        }
    }
    return [pscustomobject]@{
        TeknoParrotRoot = $TeknoParrotRoot
        IsValid = ($missing.Count -eq 0)
        MissingMarkers = @($missing)
    }
}

# One clear, greppable message used both on-console and in the invalid-
# environment report -- deliberately says "not a TPM product failure" so
# whoever reads it (an operator, a later reviewer, an automated gate parser)
# cannot mistake this for an ordinary certification FAIL against a real
# install, per issue #146's "clearly distinguish an invalid environment from
# a TPM product failure" requirement.
function Get-TPMInvalidCertificationEnvironmentMessage {
    param([string]$TeknoParrotRoot, [string[]]$MissingMarkers)
    return ("INVALID CERTIFICATION ENVIRONMENT: '{0}' is missing required TeknoParrot installation marker(s): {1}. This is not a TPM product failure -- the requested -TeknoParrotRoot does not point at a real TeknoParrot installation, so no certification gates were run against it." -f $TeknoParrotRoot, ($MissingMarkers -join ', '))
}

function New-TPMPesterChildEnvironment {
    param([Parameter(Mandatory = $true)][string]$RepositoryPath)

    # GIT_CONFIG_* is inherited only by the isolated child process. It adds
    # one exact safe.directory value without reading or writing persistent
    # Git configuration, so NoAIAttribution can use its existing git ls-files
    # call on a NAS-owned worktree.
    return @{
        NO_COLOR            = '1'
        TERM                = 'dumb'
        GIT_TERMINAL_PROMPT = '0'
        GIT_CONFIG_GLOBAL   = 'NUL'
        GIT_CONFIG_NOSYSTEM = '1'
        GIT_CONFIG_COUNT    = '1'
        GIT_CONFIG_KEY_0    = 'safe.directory'
        GIT_CONFIG_VALUE_0  = $RepositoryPath
    }
}

# Issue #146: unattended TPM must be bound to the exact requested
# certification root, not whatever root was last saved interactively on this
# machine (TeknoParrot-Manager.ps1's own -Unattended flow reads
# TeknoParrot-Manager.config.json, which the certification harness does not
# otherwise control). These three functions snapshot/override/restore that
# config file's TeknoParrotRoot field around the unattended run, so the
# override never survives past this one certification run and a developer's
# real saved settings are never corrupted, regardless of how the run
# finishes (see the try/finally around their use below).
function Get-TPMConfigJsonSnapshot {
    param([string]$ConfigPath)
    if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
        return Get-Content -LiteralPath $ConfigPath -Raw
    }
    return $null
}

function Set-TPMConfigJsonRoot {
    # Issue #154 real-hardware certification finding: TeknoParrot-Manager.ps1's
    # -Unattended flow has no way to choose which mode to auto-run -- every
    # mode's own body already auto-answers its internal prompts under
    # -Unattended, but the initial mode selection itself was only ever
    # reachable through the interactive menu. Confirmed by direct
    # reproduction that a real -Unattended launch reached the menu loop with
    # no mode ever chosen and exited 1 at "Mode must be set before starting."
    # UnattendedMode is the config field the product now reads (see SECTION 1
    # of TeknoParrot-Manager.ps1) to auto-select an initial mode only when
    # -Unattended is set; HealthCheck is the read-only mode this harness's
    # own "Unattended TPM root binding" gate actually needs -- it proves
    # config-driven root binding and mode selection work end-to-end without
    # writing, deleting, or modifying anything in the real install.
    # Add-Member -Force is required, not a plain "=" assignment -- confirmed
    # by direct reproduction that assigning to a PSCustomObject property that
    # does not already exist throws SetValueInvocationException, which a
    # pre-existing config saved before this field existed would otherwise
    # hit. Every other field on an existing config is left untouched.
    param([string]$ConfigPath, [string]$TeknoParrotRoot, [string]$UnattendedMode = 'HealthCheck')
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { return $false }
    $raw = Get-Content -LiteralPath $ConfigPath -Raw
    $cfg = $raw | ConvertFrom-Json
    $cfg | Add-Member -MemberType NoteProperty -Name TeknoParrotRoot -Value $TeknoParrotRoot -Force
    $cfg | Add-Member -MemberType NoteProperty -Name UnattendedMode -Value $UnattendedMode -Force
    [System.IO.File]::WriteAllText($ConfigPath, ($cfg | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding $false))
    return $true
}

# Issue #146 review round 2 (finding #2): a machine with no saved
# TeknoParrot-Manager.config.json previously could not have unattended TPM
# bound to the requested certification root at all -- the run was skipped
# outright and both checks failed. TeknoParrot-Manager.ps1's own
# -Unattended flow (see its "SECTION 1" config load) only requires
# TeknoParrotRoot and GamesInstallFolder to be non-empty strings to get
# past config load and print its "Configuration:" block (which is all this
# harness reads back); GamesInstallFolder's existence on disk is never
# checked at that point, so reusing the already-validated TeknoParrotRoot
# for it is a safe, always-valid placeholder that needs no extra folder to
# be created or cleaned up. This is intentionally the minimal config
# TeknoParrot-Manager.ps1 requires, not a full settings file. The caller
# treats the resulting file exactly like any other override -- it is
# removed afterward by the same Restore-TPMConfigJsonSnapshot call used for
# the existing-config path, because the pre-run snapshot for a config that
# did not exist yet is $null.
function New-TPMTemporaryUnattendedConfig {
    # See Set-TPMConfigJsonRoot's comment for why UnattendedMode is required
    # and why HealthCheck is the correct value for this harness's own
    # unattended-root-binding proof. This is the complete minimal config
    # TeknoParrot-Manager.ps1's -Unattended flow needs to pass config load
    # AND actually select and run a mode to completion: TeknoParrotRoot and
    # GamesInstallFolder (pre-existing requirement) plus UnattendedMode
    # (this fix).
    param([string]$ConfigPath, [string]$TeknoParrotRoot, [string]$UnattendedMode = 'HealthCheck')
    $cfg = [ordered]@{
        TeknoParrotRoot    = $TeknoParrotRoot
        GamesInstallFolder = $TeknoParrotRoot
        UnattendedMode     = $UnattendedMode
    }
    [System.IO.File]::WriteAllText($ConfigPath, ($cfg | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding $false))
    return $true
}

function Restore-TPMConfigJsonSnapshot {
    # $Snapshot is deliberately untyped, not [string] -- a [string]-typed
    # parameter coerces a $null argument to an empty string during binding,
    # which would make the $null-eq check below never match a real "no
    # config existed before this override" case, and instead overwrite the
    # config path with an empty file rather than removing it. Confirmed by
    # a failing test before this fix: Restore-TPMConfigJsonSnapshot -Snapshot
    # $null left a zero-byte file in place instead of deleting it.
    param([string]$ConfigPath, $Snapshot)
    if ($null -eq $Snapshot) {
        if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
            Remove-Item -LiteralPath $ConfigPath -Force -ErrorAction SilentlyContinue
        }
        return
    }
    [System.IO.File]::WriteAllText($ConfigPath, [string]$Snapshot, (New-Object System.Text.UTF8Encoding $false))
}

# Issue #146 review round 2 (finding #3): Restore-TPMConfigJsonSnapshot's
# own success was never verified -- a locked file that silently survived
# Remove-Item's -ErrorAction SilentlyContinue, or any other restore failure,
# left the developer's real saved config permanently overwritten with the
# certification's temporary override with no failure signal anywhere. This
# reads the config path back after a restore attempt and compares it
# against what the pre-run snapshot says should be there, so a failed
# restore is always caught and reported, never assumed to have worked
# because the call itself didn't throw.
function Test-TPMConfigRestored {
    param([string]$ConfigPath, $ExpectedSnapshot)
    if ($null -eq $ExpectedSnapshot) {
        return -not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)
    }
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { return $false }
    $current = Get-Content -LiteralPath $ConfigPath -Raw
    return ($current -eq [string]$ExpectedSnapshot)
}

# Issue #146 review round 3: extracts the full snapshot -> override/create ->
# invoke -> restore -> verify orchestration (previously inline top-level code
# in the -RunUnattendedTPM block below) into an independently testable
# function, so the round 2 fixes can be covered by integration-level tests
# rather than only their individual pure-function pieces. $InvokeUnattended is
# a scriptblock the caller supplies to actually run TPM (real callers pass one
# that shells out to pwsh and writes $LogPath; tests substitute a fake one
# that writes a fabricated log, or throws, without ever launching a real
# subprocess). An exception from $InvokeUnattended is deliberately NOT caught
# here and propagates to the caller -- same as before this extraction, where
# the pwsh call was a plain statement inside the try/finally below and an
# exception there aborted the whole certification run via the harness's outer
# catch block -- but the finally block still runs unconditionally either way,
# so a config override is always restored regardless of how the run finishes.
function Invoke-TPMUnattendedRootBinding {
    param(
        [string]$ConfigPath,
        [string]$TeknoParrotRoot,
        [string]$LogPath,
        [Parameter(Mandatory=$true)][scriptblock]$InvokeUnattended
    )

    $checkResults = New-Object System.Collections.Generic.List[object]
    $effectiveRoot = $null

    $configSnapshot = Get-TPMConfigJsonSnapshot -ConfigPath $ConfigPath
    try {
        if ($null -eq $configSnapshot) {
            $overrideWritten = New-TPMTemporaryUnattendedConfig -ConfigPath $ConfigPath -TeknoParrotRoot $TeknoParrotRoot
        } else {
            $overrideWritten = Set-TPMConfigJsonRoot -ConfigPath $ConfigPath -TeknoParrotRoot $TeknoParrotRoot
        }
        if (-not $overrideWritten) {
            $checkResults.Add([pscustomobject]@{ Name = 'TPM unattended run'; Passed = $false; Details = "could not prepare TeknoParrot-Manager.config.json at $ConfigPath for the unattended run" })
            $checkResults.Add([pscustomobject]@{ Name = 'Unattended TPM used requested root'; Passed = $false; Details = "no config available to bind to the requested root at $ConfigPath" })
        } else {
            & $InvokeUnattended
            $checkResults.Add([pscustomobject]@{ Name = 'TPM unattended run'; Passed = $true; Details = "log=$LogPath" })

            $effectiveRoot = Get-TPMEffectiveRootFromUnattendedLog -LogPath $LogPath
            $rootsMatch = Test-TPMUnattendedRootMatch -RequestedRoot $TeknoParrotRoot -EffectiveRoot $effectiveRoot
            $effectiveRootDetailText = if ($effectiveRoot) { $effectiveRoot } else { '(not found in unattended log)' }
            if ($rootsMatch) {
                $checkResults.Add([pscustomobject]@{ Name = 'Unattended TPM used requested root'; Passed = $true; Details = ("requested={0} effective={1}" -f $TeknoParrotRoot, $effectiveRootDetailText) })
            } else {
                # Issue #146 review round 2 (finding #4): this failure must
                # be reported with its own explicit reason and must never
                # be conflated with, or read back later as, smoke mode.
                $checkResults.Add([pscustomobject]@{ Name = 'Unattended TPM used requested root'; Passed = $false; Details = ("requested={0} effective={1} -- effective root missing, unparsable, or does not match the requested root" -f $TeknoParrotRoot, $effectiveRootDetailText) })
            }
        }
    } finally {
        # Issue #146 review round 2 (finding #3): the restore call's own
        # success is never assumed -- it is verified by reading the config
        # path back, and a failed restore fails certification with an
        # explicit reason rather than continuing silently.
        $restoreError = $null
        try {
            Restore-TPMConfigJsonSnapshot -ConfigPath $ConfigPath -Snapshot $configSnapshot
        } catch {
            $restoreError = $_.Exception.Message
        }
        $restoreVerified = Test-TPMConfigRestored -ConfigPath $ConfigPath -ExpectedSnapshot $configSnapshot
        if ($restoreError) {
            $checkResults.Add([pscustomobject]@{ Name = 'Unattended TPM config restoration'; Passed = $false; Details = "restore threw: $restoreError" })
        } elseif (-not $restoreVerified) {
            $checkResults.Add([pscustomobject]@{ Name = 'Unattended TPM config restoration'; Passed = $false; Details = "config file state at $ConfigPath does not match its pre-run snapshot after restore" })
        } else {
            $checkResults.Add([pscustomobject]@{ Name = 'Unattended TPM config restoration'; Passed = $true; Details = "config file at $ConfigPath restored to its pre-run state" })
        }
    }

    $snapshotHash = $null
    if ($null -ne $configSnapshot) {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $snapshotBytes = (New-Object System.Text.UTF8Encoding $false).GetBytes([string]$configSnapshot)
            $snapshotHash = -join ($sha256.ComputeHash($snapshotBytes) | ForEach-Object { $_.ToString('x2') })
        } finally {
            $sha256.Dispose()
        }
    }
    $restorationCheck = @($checkResults.ToArray() | Where-Object { $_.Name -ceq 'Unattended TPM config restoration' }) | Select-Object -Last 1

    return [pscustomobject]@{
        PriorConfigExisted = ($null -ne $configSnapshot)
        TemporaryConfigCreated = ($null -eq $configSnapshot -and [bool]$overrideWritten)
        RestoreAttempted = $true
        RestoreSucceeded = ($null -eq $restoreError)
        VerificationSucceeded = [bool]$restoreVerified
        SnapshotSha256 = $snapshotHash
        RestorationFailureReason = $(if ($restorationCheck -and -not $restorationCheck.Passed) { [string]$restorationCheck.Details } else { $null })
        # .ToArray(), not @($checkResults) -- confirmed by direct repro that
        # wrapping a System.Collections.Generic.List[object] in @(...) inside
        # a function that also has parameters throws "Argument types do not
        # match" (System.ArgumentException) under real Windows PowerShell
        # 5.1's dynamic binder (PSToObjectArrayBinder/PSEnumerableBinder),
        # independent of whether the scriptblock parameter is ever invoked.
        # .ToArray() sidesteps the dynamic-site binding entirely.
        Checks = $checkResults.ToArray()
        EffectiveTeknoParrotRoot = $effectiveRoot
    }
}

# Issue #146 review round 2 (finding #4): extracted so the "Certification
# Target" report section's effective-root text is independently testable --
# it previously fell back to "smoke mode" text whenever EffectiveRoot was
# empty, with no regard for whether unattended TPM was actually requested,
# misreporting a real -RunUnattendedTPM failure (missing/unparsable
# effective root) as if it were an ordinary smoke-mode run.
function Get-TPMEffectiveRootReportText {
    param([string]$EffectiveRoot, [bool]$SmokeMode)
    if ($EffectiveRoot) { return $EffectiveRoot }
    if ($SmokeMode) { return 'not applicable -- smoke mode (no unattended TPM run)' }
    return '(not found in unattended log) -- unattended TPM was requested but the effective root could not be confirmed'
}

# Parses the TeknoParrot root TPM actually used from its own unattended-run
# console log, specifically from the "Configuration:" block (the settings
# actually applied THIS run) rather than the earlier "Saved configuration
# found:" block (what was on disk before this harness's override) -- issue
# #146. Returns $null if the log has no Configuration block with a
# TeknoParrot root line, which Test-TPMUnattendedRootMatch below treats as
# a failure, not an inconclusive pass.
function Get-TPMEffectiveRootFromUnattendedLog {
    param([string]$LogPath)
    if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) { return $null }
    $text = Get-Content -LiteralPath $LogPath -Raw
    $configBlockMatch = [regex]::Match($text, '(?ms)^Configuration:\s*$(.*?)(?:\r?\n\r?\n|\z)')
    if (-not $configBlockMatch.Success) { return $null }
    $rootMatch = [regex]::Match($configBlockMatch.Groups[1].Value, '(?m)^\s*TeknoParrot root\s*:\s*(.+?)\s*$')
    if (-not $rootMatch.Success) { return $null }
    return $rootMatch.Groups[1].Value.Trim()
}

# Trailing backslashes are the only normalization needed here -- both sides
# are already-resolved absolute paths from the same machine (the requested
# root via Resolve-Path earlier in this script, the effective root as TPM's
# own Configuration block prints it), never a relative path or a different
# machine's path style.
function Test-TPMUnattendedRootMatch {
    param([string]$RequestedRoot, [string]$EffectiveRoot)
    if ([string]::IsNullOrWhiteSpace($EffectiveRoot)) { return $false }
    return ($RequestedRoot.TrimEnd('\') -eq $EffectiveRoot.TrimEnd('\'))
}

# Issue #146: the health gate previously passed as soon as
# Invoke-TPM-InstallHealthCheck.ps1 produced a report file, regardless of
# what the report said -- a real certification run against a non-install
# collected a report with three WARN-level "does not exist" findings for
# the installation-critical markers and still scored [PASS]. Gate success
# must reflect the structured health result's own meaning, not merely that
# a report was written. Pure/testable against a fabricated health result.
#
# Issue #146 review round 2 (finding #1): the first version of this gate
# only looked for critical-named Checks entries that were PRESENT and
# FAILED -- a HealthResult with the critical entries missing entirely (a
# truncated/corrupted-but-still-parseable JSON, or any structure that
# simply omits them) matched nothing in that filter and PASSED by default.
# Absent data must never read as success: every one of the three
# installation-critical checks must be explicitly present, with an
# explicit boolean Passed = $true, or the gate fails and says exactly
# which check was missing/null/non-boolean/false. $LoadError lets the call
# site distinguish "file missing" from "file present but invalid JSON" in
# the reported reason without this function needing to know how the JSON
# was read.
function Test-TPMInstallHealthGate {
    param($HealthResult, [string]$LoadError)
    $installCriticalNames = @('TeknoParrotUi.exe exists', 'GameProfiles folder exists', 'UserProfiles folder exists')

    if (-not $HealthResult) {
        $reason = if ($LoadError) { $LoadError } else { 'no health result collected' }
        return [pscustomobject]@{ Passed = $false; Reason = $reason }
    }

    # $HealthResult.Checks may be entirely absent (not merely empty/null) on a
    # malformed health result -- under strict mode, dot-accessing a property
    # that doesn't exist at all throws PropertyNotFoundException before any
    # wrap below ever runs. Checking via PSObject first treats a missing
    # Checks property the same as an explicitly null/empty one.
    #
    # The wrap itself must happen AFTER a null check, not by wrapping
    # $checksProperty.Value directly: @($null) is a one-element array
    # containing $null (Count = 1), not an empty array.
    #
    # Review round 2 (Luna Max): the null check must also assign $checks
    # directly inside each branch of a real if/else STATEMENT, not via
    # "$checks = if (...) { @() } else { ... }". Capturing @() as the
    # output of an if/else used as an expression collapses it to $null --
    # PowerShell only preserves an empty array through a *direct*
    # assignment, not through pipeline/output-stream capture of a block
    # that emits zero objects. Without strict mode this accidentally still
    # "worked" only because bare $null.Count conveniently returns 0 -- but
    # that convenience is itself suppressed under Set-StrictMode, so the
    # collapsed-to-null $checks then threw PropertyNotFoundException on
    # .Count instead of the fail-fast branch below ever being reached.
    $checksProperty = $HealthResult.PSObject.Properties['Checks']
    $rawChecks = if ($checksProperty) { $checksProperty.Value } else { $null }
    if ($null -eq $rawChecks) {
        $checks = @()
    } else {
        $checks = @($rawChecks)
    }
    if ($checks.Count -eq 0) {
        return [pscustomobject]@{ Passed = $false; Reason = 'health result has no Checks entries' }
    }

    # Issue #146 review round 3: each of the three installation-critical
    # names must occur exactly once. A prior version of this loop just
    # overwrote $checkByName on every match, so a duplicate name silently
    # took whichever entry appeared last -- a health result with the same
    # critical name listed twice (once failing, once passing, in either
    # order) could pass depending on write order, rather than being
    # rejected outright as malformed. $criticalCountByName is tallied
    # separately so a count > 1 is caught before any Passed value is even
    # looked at.
    $checkByName = @{}
    $criticalCountByName = @{}
    foreach ($c in $checks) {
        if ($null -ne $c -and $c.PSObject.Properties.Name -contains 'Name' -and -not [string]::IsNullOrWhiteSpace([string]$c.Name)) {
            $n = [string]$c.Name
            if ($installCriticalNames -contains $n) {
                if ($criticalCountByName.ContainsKey($n)) { $criticalCountByName[$n]++ } else { $criticalCountByName[$n] = 1 }
            }
            $checkByName[$n] = $c
        }
    }

    $problems = New-Object System.Collections.Generic.List[string]
    foreach ($name in $installCriticalNames) {
        $occurrences = if ($criticalCountByName.ContainsKey($name)) { $criticalCountByName[$name] } else { 0 }
        if ($occurrences -eq 0) {
            [void]$problems.Add("$name -- missing from health result")
            continue
        }
        if ($occurrences -gt 1) {
            [void]$problems.Add("$name -- appears $occurrences times in health result (duplicate installation-critical check names are not allowed)")
            continue
        }
        $check = $checkByName[$name]
        if (-not ($check.PSObject.Properties.Name -contains 'Passed') -or $null -eq $check.Passed) {
            [void]$problems.Add("$name -- Passed value missing or null")
            continue
        }
        if ($check.Passed -isnot [bool]) {
            [void]$problems.Add("$name -- Passed value is not a boolean (got: $($check.Passed))")
            continue
        }
        if ($check.Passed -ne $true) {
            [void]$problems.Add("$name -- failed")
        }
    }

    if ($problems.Count -gt 0) {
        return [pscustomobject]@{ Passed = $false; Reason = ("installation-critical check(s) not confirmed passing: " + ($problems -join '; ')) }
    }

    return [pscustomobject]@{ Passed = $true; Reason = 'all installation-critical checks present and passed' }
}

# Issue #136: the Pester regression gate previously ran synchronously with
# no visibility into progress and no way to distinguish "still running" from
# "hung forever" -- both looked identical to an operator watching the
# console (process alive, report folder created, nothing updating). These
# two pure decision functions back the runspace-polling loop below; kept
# separate and side-effect-free so they can be unit tested directly without
# needing to run actual Pester-in-Pester or spin up a real runspace.
function Test-TPMPesterHeartbeatDue {
    param(
        [double]$ElapsedSeconds,
        [double]$LastHeartbeatSeconds,
        [double]$HeartbeatIntervalSeconds
    )
    return (($ElapsedSeconds - $LastHeartbeatSeconds) -ge $HeartbeatIntervalSeconds)
}

function Test-TPMPesterTimedOut {
    param(
        [double]$ElapsedSeconds,
        [double]$TimeoutSeconds
    )
    return ($ElapsedSeconds -ge $TimeoutSeconds)
}

function Get-TPMPesterHeartbeatMessage {
    param(
        [double]$ElapsedSeconds,
        [string]$LastOutputLine
    )
    $suffix = if ([string]::IsNullOrWhiteSpace($LastOutputLine)) { '' } else { " -- last: $LastOutputLine" }
    return ("  ... still running ({0:n0}s elapsed){1}" -f $ElapsedSeconds, $suffix)
}

function Get-TPMPesterTimeoutMessage {
    param(
        [double]$ElapsedSeconds,
        [double]$TimeoutSeconds,
        [string]$LastOutputLine,
        [string]$OutputPath,
        [string]$ProgressPath
    )
    $lastText = if ([string]::IsNullOrWhiteSpace($LastOutputLine)) { '(no output captured)' } else { $LastOutputLine }
    return ("Pester regression suite timed out after {0}s (limit {1}s). Last known output: {2}. See {3} and {4} for details." -f `
        [int]$ElapsedSeconds, [int]$TimeoutSeconds, $lastText, $OutputPath, $ProgressPath)
}

function Get-PesterSummary {
    param([Parameter(Mandatory=$true)]$PesterResult)
    $candidate = $PesterResult
    if ($PesterResult -is [array]) {
        $candidate = @($PesterResult) | Where-Object {
            $_ -and ($_.PSObject.Properties.Name -contains 'PassedCount' -or $_.PSObject.Properties.Name -contains 'Passed') -and ($_.PSObject.Properties.Name -contains 'FailedCount' -or $_.PSObject.Properties.Name -contains 'Failed')
        } | Select-Object -Last 1
    }
    $summary = [ordered]@{
        Passed = $null
        Failed = $null
        Skipped = $null
        Inconclusive = $null
        NotRun = $null
        Total = $null
        Duration = $null
        Result = 'Unknown'
    }
    if (-not $candidate) { return [pscustomobject]$summary }
    $fields = @(
        @('Passed','PassedCount','Passed'),
        @('Failed','FailedCount','Failed'),
        @('Skipped','SkippedCount','Skipped'),
        @('Inconclusive','InconclusiveCount','Inconclusive'),
        @('NotRun','NotRunCount','NotRun'),
        @('Total','TotalCount','Total')
    )
    foreach ($pair in $fields) {
        foreach ($name in $pair[1..($pair.Count-1)]) {
            if ($candidate.PSObject.Properties.Name -contains $name) {
                $summary[$pair[0]] = $candidate.$name
                break
            }
        }
    }
    foreach ($name in @('Duration','Time')) {
        if ($candidate.PSObject.Properties.Name -contains $name) {
            $summary.Duration = [string]$candidate.$name
            break
        }
    }
    if ($candidate.PSObject.Properties.Name -contains 'Result') { $summary.Result = [string]$candidate.Result }
    if ($null -eq $summary.Total -and $null -ne $summary.Passed -and $null -ne $summary.Failed) {
        $total = 0
        foreach ($key in @('Passed','Failed','Skipped','Inconclusive','NotRun')) {
            if ($null -ne $summary[$key]) { $total += [int]$summary[$key] }
        }
        $summary.Total = $total
    }
    if ($summary.Result -eq 'Unknown' -and $summary.Failed -eq 0) { $summary.Result = 'Passed' }
    [pscustomobject]$summary
}

# Issue #151: RC3 arcade certification of a fully-passing merged commit
# still returned ARCADE CERTIFICATION FAIL because the required
# certification evidence (screenshots of the run itself) did not exist and
# had to be captured manually. This function is the core, independently
# testable piece of automatic screenshot capture: it never touches the
# screen itself -- $CaptureAction is an injectable scriptblock that
# performs the real capture and is expected to write a file to the $Path
# it receives as its own single positional argument, optionally returning
# a CaptureScope string ('Window'/'FullDesktop', meaningful only for
# ScreenCapture evidence -- see Save-TPMScreenCapture below). Real callers
# pass a scriptblock backed by System.Drawing/System.Windows.Forms; tests
# substitute a fake action that writes a dummy file or throws, so capture
# behavior -- directory creation, naming, validation, and the explicit
# failure path -- can be exercised without a live display session (this
# harness's own regression suite runs headless in CI, where a real screen
# grab is not reliably available).
#
# A capture is never silently skipped: every call returns a result object
# with an explicit Status of 'Captured', 'Failed', or 'Skipped' (only ever
# used when the caller passes -Skip for a genuinely not-applicable "when
# displayed" evidence slot, e.g. live thumbnail/controls evidence that
# this particular run never triggered) -- never just omitted from the
# evidence list, so a reviewer always sees what was attempted and why an
# item is missing if it is. Review round 1 (finding #3): the record also
# carries an explicit EvidenceType ('ScreenCapture'/'DeterministicRender'
# for a successful capture, 'Skipped'/'Failed' otherwise) and a Label
# (currently identical to Name, exposed under its own name because the
# finding asked for it explicitly) -- callers and reports must never have
# to infer capture method from free-text Details.
function New-TPMCertificationScreenshot {
    param(
        [AllowNull()][AllowEmptyString()][string]$ScreenshotDir,
        [AllowNull()][AllowEmptyString()][string]$Name,
        [AllowNull()][AllowEmptyString()][string]$EvidenceType,
        [scriptblock]$CaptureAction,
        [switch]$Skip,
        [string]$SkipReason
    )

    $recordName = if ([string]::IsNullOrWhiteSpace($Name)) { 'unnamed-evidence' } else { $Name }
    if ([string]::IsNullOrWhiteSpace($Name)) { return [pscustomobject]@{ Name=$recordName; Label=$recordName; Path=$null; Status='Failed'; EvidenceType='Failed'; Required=$true; WorkflowId=$script:tpmEvidenceWorkflowId; CaptureScope=$null; Details='invalid evidence metadata: Name is empty' } }
    if ($Skip) { return [pscustomobject]@{ Name=$recordName; Label=$recordName; Path=$null; Status='Skipped'; EvidenceType='Skipped'; Required=$false; WorkflowId=$script:tpmEvidenceWorkflowId; CaptureScope=$null; Details=$(if ($SkipReason) { $SkipReason } else { 'not applicable to this run' }) } }
    if ([string]::IsNullOrWhiteSpace($ScreenshotDir)) { return [pscustomobject]@{ Name=$recordName; Label=$recordName; Path=$null; Status='Failed'; EvidenceType='Failed'; Required=$true; WorkflowId=$script:tpmEvidenceWorkflowId; CaptureScope=$null; Details='invalid evidence metadata: ScreenshotDir is empty' } }
    if (@('ScreenCapture','DeterministicRender') -cnotcontains $EvidenceType) {
        $suppliedType = if ([string]::IsNullOrWhiteSpace($EvidenceType)) { '(empty)' } else { $EvidenceType }
        return [pscustomobject]@{ Name=$recordName; Label=$recordName; Path=$null; Status='Failed'; EvidenceType='Failed'; Required=$true; WorkflowId=$script:tpmEvidenceWorkflowId; CaptureScope=$null; Details="invalid evidence metadata: EvidenceType '$suppliedType' is not ScreenCapture or DeterministicRender" }
    }
    if (-not $CaptureAction) { return [pscustomobject]@{ Name=$recordName; Label=$recordName; Path=$null; Status='Failed'; EvidenceType='Failed'; Required=$true; WorkflowId=$script:tpmEvidenceWorkflowId; CaptureScope=$null; Details='no CaptureAction supplied' } }

    if (-not (Test-Path -LiteralPath $ScreenshotDir -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $ScreenshotDir | Out-Null
    }

    try {
        $path = New-TPMScreenshotReservedPath -ScreenshotDir $ScreenshotDir -Name $Name
    } catch {
        return [pscustomobject]@{ Name = $Name; Label = $Name; Path = $null; Status = 'Failed'; EvidenceType = 'Failed'; Required = $true; WorkflowId = $script:tpmEvidenceWorkflowId; CaptureScope = $null; Details = "could not reserve a unique screenshot path: $($_.Exception.Message)" }
    }

    try {
        $captureScope = & $CaptureAction $path
        # Review round 1 (finding #5): a path being returned is not
        # success -- verified against the real file on disk (exists,
        # non-empty, decodes as a valid image with positive dimensions)
        # before Status is ever set to 'Captured'. The invalid artifact
        # (if any) is preserved, not deleted, so a reviewer can inspect
        # exactly what went wrong -- consistent with never silently
        # discarding evidence, even evidence of a failure.
        $validation = Test-TPMScreenshotFileValid -Path $path
        if (-not $validation.Valid) {
            return [pscustomobject]@{ Name = $Name; Label = $Name; Path = $path; Status = 'Failed'; EvidenceType = 'Failed'; Required = $true; WorkflowId = $script:tpmEvidenceWorkflowId; CaptureScope = $null; Details = $validation.Reason }
        }
        $resolvedScope = if ($EvidenceType -eq 'ScreenCapture' -and $captureScope) { [string]$captureScope } else { $null }
        return [pscustomobject]@{ Name = $Name; Label = $Name; Path = $path; Status = 'Captured'; EvidenceType = $EvidenceType; Required = $true; WorkflowId = $script:tpmEvidenceWorkflowId; CaptureScope = $resolvedScope; Details = 'captured' }
    } catch {
        return [pscustomobject]@{ Name = $Name; Label = $Name; Path = $path; Status = 'Failed'; EvidenceType = 'Failed'; Required = $true; WorkflowId = $script:tpmEvidenceWorkflowId; CaptureScope = $null; Details = $_.Exception.Message }
    }
}

# Issue #151 review round 1 (finding #2): millisecond-precision timestamps
# alone were not collision-safe -- two captures of the same evidence label
# within the same millisecond (or two independent harness processes
# sharing a report directory) could produce the same file name. This
# combines a timestamp, a per-run monotonic counter, and a short random
# suffix for a human-readable-but-unique candidate name, then reserves it
# atomically via FileMode.CreateNew (which throws if the path already
# exists, eliminating the check-then-write race a plain Test-Path guard
# would still have), retrying with a new candidate on collision. The
# reserved file is a zero-byte placeholder -- $CaptureAction's real
# content overwrites it immediately afterward.
$script:tpmScreenshotSequence = 0
$script:tpmEvidenceWorkflowId = [guid]::NewGuid().ToString('N')

# System Invariant Inventory: evidence issuance ledger. This is the
# workflow's own private record of what it actually issued, populated only
# by Add-Screenshot in real append order. It is currently consulted only by
# Add-Screenshot itself (the same-path duplicate-reservation check a few
# lines below) -- since ADR155-0309 Checkpoint B2, the certification
# decision path no longer runs it through Complete-TPMCertificationTransaction
# (removed; see the Checkpoint B2 comment near the certification tail
# below). The current production pipeline (New-TPMProductionEvidenceRecordV1
# plus Authority.psm1's Assert-TPMEvidenceRecordV1, invoked via
# RecordEvidence/IssueFinalEvidence) validates each submitted evidence
# record's own path containment, on-disk hash (re-read twice, defeating a
# same-instant on-disk swap), PNG validity, and required-vs-skipped
# consistency -- but, unlike the removed transaction, it does not verify
# that the submitted record is literally the same object instance this
# ledger produced ([object]::ReferenceEquals). A record reconstructed with
# every field copied from a genuine ledger entry is not distinguished from
# the genuine entry by the current pipeline the way it was by the removed
# one.
$script:tpmEvidenceLedger = New-Object System.Collections.Generic.List[object]
# Sealed the instant 'final-certification-result' is issued (successfully,
# skipped, or failed) -- no further evidence may be appended afterward.
# This makes "the final record was genuinely issued last" and "no evidence
# can be replayed in after finalization" true by construction: there is no
# code path left that can grow the ledger once this is set, independent of
# any check the transaction later performs.
$script:tpmEvidenceLedgerSealed = $false

function Reset-TPMEvidenceLedger {
    # Real production flow never calls this (the script-scope initializers
    # above already establish a fresh ledger once per run) -- it exists so
    # Pester fixtures can start each It block with an empty, unsealed ledger
    # and a fresh workflow identity, the same way the harness starts each
    # real run, instead of accumulating state across tests.
    $script:tpmEvidenceLedger = New-Object System.Collections.Generic.List[object]
    $script:tpmEvidenceLedgerSealed = $false
    $script:tpmEvidenceWorkflowId = [guid]::NewGuid().ToString('N')
    $script:tpmScreenshotSequence = 0
}

function New-TPMScreenshotReservedPath {
    param([string]$ScreenshotDir, [string]$Name)
    $safeName = ($Name -replace '[^A-Za-z0-9_\-]', '-')
    $attempt = 0
    while ($true) {
        $attempt++
        $script:tpmScreenshotSequence++
        $screenshotStamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss-fff'
        $randomSuffix = '{0:x6}' -f (Get-Random -Maximum 0xFFFFFF)
        $fileName = "{0}_{1}_{2:D5}_{3}.png" -f $safeName, $screenshotStamp, $script:tpmScreenshotSequence, $randomSuffix
        $candidatePath = Join-Path $ScreenshotDir $fileName
        $handle = $null
        try {
            $handle = [System.IO.File]::Open($candidatePath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
            return $candidatePath
        } catch [System.IO.IOException] {
            if ($attempt -ge 1000) { throw "could not reserve a unique screenshot path under $ScreenshotDir after 1000 attempts" }
        } finally {
            if ($handle) { $handle.Dispose() }
        }
    }
}

# Issue #151 review round 3: GDI+ decoding, even forced via LockBits, does
# not validate PNG CRC integrity -- a valid PNG with one byte flipped
# inside its IDAT payload (signature, chunk structure, and IEND all still
# intact) decoded and locked-bits successfully, since GDI+'s deflate
# decompressor tolerates plenty of bit-level corruption without raising an
# error. CRC validation is the only way to actually detect this class of
# corruption, and the PNG spec ties a CRC to each individual chunk, so it
# has to be computed per-chunk, not over the whole file. Standard CRC-32
# (polynomial 0xEDB88320, same variant zlib/PNG both use), table-based for
# speed. $script:tpmCrc32Table is built once and reused -- this can run
# per-chunk per-screenshot, and rebuilding a 256-entry table on every call
# would be wasted work for no benefit.
function Get-TPMCrc32 {
    param([byte[]]$Bytes, [int]$Offset, [int]$Count)
    if (-not $script:tpmCrc32Table) {
        $table = New-Object 'uint32[]' 256
        for ($n = 0; $n -lt 256; $n++) {
            $c = [uint32]$n
            for ($k = 0; $k -lt 8; $k++) {
                if (($c -band 1) -ne 0) {
                    $c = 0xEDB88320 -bxor ($c -shr 1)
                } else {
                    $c = $c -shr 1
                }
            }
            $table[$n] = $c
        }
        $script:tpmCrc32Table = $table
    }
    # [uint32]::MaxValue, not [uint32]0xFFFFFFFF -- PowerShell parses the
    # hex literal 0xFFFFFFFF as a signed Int32 (-1) first, and casting a
    # negative value to [uint32] is a checked conversion that throws
    # ("Value was either too large or too small for a UInt32") rather than
    # wrapping the way C-style unchecked casts do. Confirmed by direct
    # repro.
    $crc = [uint32]::MaxValue
    for ($i = 0; $i -lt $Count; $i++) {
        $index = ($crc -bxor [uint32]$Bytes[$Offset + $i]) -band [uint32]0xFF
        $crc = $script:tpmCrc32Table[$index] -bxor ($crc -shr 8)
    }
    return $crc -bxor [uint32]::MaxValue
}

# Issue #151 review round 3: parses the PNG chunk stream directly instead
# of trusting a decoder's opinion of it -- "GDI+ decoded it" and "GDI+
# decoded it losslessly" are different claims, and only chunk-level CRC
# validation actually establishes the second one. Every chunk is walked
# (4-byte big-endian length, 4-byte type, data, 4-byte CRC), each is
# required to stay fully within the file's bounds, the first chunk must be
# IHDR with exactly 13 bytes of data (both mandated by the spec), the
# stream must end in a zero-length IEND with nothing after it, and every
# chunk's stored CRC (not just the three critical ones -- ancillary chunks
# too, since this is cheap enough on a screenshot-sized file to just do
# for all of them rather than special-case which ones matter) is
# recomputed and compared against what is actually in the file. Position
# arithmetic uses [int64] throughout -- a chunk's declared length is a
# 32-bit field an attacker-or-corruption-controlled file could set close
# to its max value, and adding that directly to a 32-bit position/length
# comparison risks silent integer overflow masking exactly the "chunk
# claims to extend past the file" case this function exists to catch.
# Issue #151 review round 4: CRC validation alone is not spec conformance
# -- a CRC-valid PNG containing a second, CRC-valid IHDR chunk passed
# round 3's validator, since nothing checked chunk ordering or uniqueness.
# This is a deliberately scoped subset of the PNG specification: enough to
# make a trustworthy certification-evidence validator (structure,
# ordering, uniqueness, the handful of IHDR fields that determine whether
# the rest of the file can even be interpreted, and enough content
# validation on PLTE to catch a structurally-impossible palette), not a
# full PNG decoder. All string comparisons against chunk type names use
# the case-sensitive operators (-ceq/-cne/-ccontains) throughout --
# PowerShell's default -eq/-ne/-contains are case-INSENSITIVE, and chunk
# type case is semantically load-bearing in the PNG spec itself (bit 5 of
# each of the 4 type bytes encodes critical/ancillary, public/private,
# reserved, and safe-to-copy; a chunk named "ihdr" is a different,
# unrecognized ancillary chunk, not a case-insensitive alias for "IHDR")
# -- confirmed by direct repro that the case-insensitive default would
# have treated them as the same chunk.
function Test-TPMPngStructure {
    param([byte[]]$Bytes)

    $pngSignature = [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
    if ($Bytes.Length -lt 8) {
        return [pscustomobject]@{ Valid = $false; Reason = 'file is too short to contain a PNG signature' }
    }
    for ($i = 0; $i -lt 8; $i++) {
        if ($Bytes[$i] -ne $pngSignature[$i]) {
            return [pscustomobject]@{ Valid = $false; Reason = 'file does not start with the PNG signature (magic bytes) -- not a real PNG regardless of its .png extension' }
        }
    }

    # PNG chunk length fields are 4-byte unsigned integers, but the spec
    # itself restricts a chunk's actual length to fit in a signed 32-bit
    # value (0 .. 2^31-1) -- rejected here as "allocation safety" before
    # the declared length is used in any further arithmetic, independent
    # of whether it would also overrun this particular file's bounds.
    [int64]$maxChunkLength = 0x7FFFFFFF
    $knownCriticalTypes = @('IHDR', 'PLTE', 'IDAT', 'IEND')
    $staticUnsupportedTypes = @('acTL', 'fcTL', 'fdAT')
    $singleAncillaryTypes = @('cHRM', 'cICP', 'gAMA', 'iCCP', 'mDCV', 'cLLI', 'sBIT', 'sRGB', 'bKGD', 'hIST', 'tRNS', 'eXIf', 'pHYs', 'tIME')
    $beforePlteAndIdatTypes = @('cHRM', 'cICP', 'gAMA', 'iCCP', 'mDCV', 'cLLI', 'sBIT', 'sRGB')
    $beforeIdatTypes = @('eXIf', 'pHYs', 'sPLT')
    $afterPlteBeforeIdatTypes = @('bKGD', 'hIST', 'tRNS')
    $validColorTypes = @(0, 2, 3, 4, 6)
    $validBitDepthsByColorType = @{ 0 = @(1, 2, 4, 8, 16); 2 = @(8, 16); 3 = @(1, 2, 4, 8); 4 = @(8, 16); 6 = @(8, 16) }
    $seenAncillary = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([System.StringComparer]::Ordinal)

    [int64]$pos = 8
    [int64]$fileLength = $Bytes.Length
    $chunkIndex = 0
    $sawIend = $false
    $ihdrCount = 0
    $iendCount = 0
    $plteCount = 0
    $idatCount = 0
    $idatStarted = $false
    $idatEnded = $false
    $paletteDependentSeenBeforePlte = $false
    $colorType = $null
    $bitDepth = $null

    while ($pos -lt $fileLength) {
        if ($sawIend) {
            return [pscustomobject]@{ Valid = $false; Reason = 'PNG contains extra data after its terminating IEND chunk' }
        }
        if ($pos + 8 -gt $fileLength) {
            return [pscustomobject]@{ Valid = $false; Reason = 'PNG chunk header runs past the end of the file -- truncated or malformed' }
        }

        # Chunk type validation: all four type bytes must be ASCII letters
        # (0x41-0x5A / 0x61-0x7A) per spec -- checked on the raw bytes,
        # not the decoded string, since ASCII-decoding arbitrary bytes
        # never throws and would otherwise silently let a malformed type
        # through as a weird-looking-but-technically-valid .NET string.
        for ($tb = 0; $tb -lt 4; $tb++) {
            $b = $Bytes[$pos + 4 + $tb]
            if (-not (($b -ge 65 -and $b -le 90) -or ($b -ge 97 -and $b -le 122))) {
                return [pscustomobject]@{ Valid = $false; Reason = 'PNG chunk type is not 4 ASCII letters -- malformed chunk name' }
            }
        }
        $type = [System.Text.Encoding]::ASCII.GetString($Bytes, [int]($pos + 4), 4)
        if (($Bytes[$pos + 6] -band 0x20) -ne 0) { return [pscustomobject]@{ Valid = $false; Reason = "PNG chunk '$type' sets the reserved third type bit" } }

        [int64]$length = ([uint32]$Bytes[$pos] -shl 24) -bor ([uint32]$Bytes[$pos + 1] -shl 16) -bor ([uint32]$Bytes[$pos + 2] -shl 8) -bor [uint32]$Bytes[$pos + 3]
        if ($length -gt $maxChunkLength) {
            return [pscustomobject]@{ Valid = $false; Reason = "PNG '$type' chunk declares a length ($length) that exceeds the maximum a PNG chunk may have (2^31 - 1)" }
        }

        [int64]$dataStart = $pos + 8
        [int64]$crcStart = $dataStart + $length
        if ($crcStart + 4 -gt $fileLength) {
            return [pscustomobject]@{ Valid = $false; Reason = "PNG '$type' chunk declares a length ($length) whose data/CRC overruns the end of the file" }
        }

        if ($chunkIndex -eq 0 -and $type -cne 'IHDR') {
            return [pscustomobject]@{ Valid = $false; Reason = "PNG's first chunk must be IHDR, found '$type'" }
        }

        if ($staticUnsupportedTypes -ccontains $type) { return [pscustomobject]@{ Valid = $false; Reason = "PNG chunk '$type' is APNG animation data; certification evidence must be static" } }
        if ($singleAncillaryTypes -ccontains $type) {
            if ($seenAncillary.ContainsKey($type)) { return [pscustomobject]@{ Valid = $false; Reason = "PNG contains more than one $type chunk" } }
            $seenAncillary.Add($type, 1)
        }
        if ($beforePlteAndIdatTypes -ccontains $type -and ($plteCount -gt 0 -or $idatStarted)) { return [pscustomobject]@{ Valid = $false; Reason = "PNG $type chunk must appear before PLTE and IDAT" } }
        if ($beforeIdatTypes -ccontains $type -and $idatStarted) { return [pscustomobject]@{ Valid = $false; Reason = "PNG $type chunk must appear before IDAT" } }
        if ($afterPlteBeforeIdatTypes -ccontains $type) {
            if (($type -ceq 'bKGD' -or $type -ceq 'tRNS') -and $plteCount -eq 0 -and $colorType -ne 3) { $paletteDependentSeenBeforePlte = $true }
            if ($idatStarted) { return [pscustomobject]@{ Valid = $false; Reason = "PNG $type chunk must appear before IDAT" } }
            if (($type -ceq 'hIST' -or $colorType -eq 3) -and $plteCount -eq 0) { return [pscustomobject]@{ Valid = $false; Reason = "PNG $type chunk requires and must follow PLTE" } }
        }

        if ($type -ceq 'IHDR') {
            $ihdrCount++
            if ($ihdrCount -gt 1) {
                return [pscustomobject]@{ Valid = $false; Reason = 'PNG contains more than one IHDR chunk -- a PNG must have exactly one, even if every copy is individually CRC-valid' }
            }
            if ($length -ne 13) {
                return [pscustomobject]@{ Valid = $false; Reason = "PNG IHDR chunk must be exactly 13 bytes, found $length" }
            }
        }
        if ($type -ceq 'IEND') {
            $iendCount++
            if ($iendCount -gt 1) {
                return [pscustomobject]@{ Valid = $false; Reason = 'PNG contains more than one IEND chunk' }
            }
            if ($length -ne 0) {
                return [pscustomobject]@{ Valid = $false; Reason = "PNG IEND chunk must have zero length, found $length" }
            }
        }
        if ($type -ceq 'PLTE') {
            if ($paletteDependentSeenBeforePlte) { return [pscustomobject]@{ Valid = $false; Reason = 'PNG PLTE must appear before any bKGD or tRNS chunk when a palette is present' } }
            $plteCount++
            if ($plteCount -gt 1) {
                return [pscustomobject]@{ Valid = $false; Reason = 'PNG contains more than one PLTE chunk -- a PNG must have at most one' }
            }
            if ($idatStarted) {
                return [pscustomobject]@{ Valid = $false; Reason = 'PNG PLTE chunk must appear before the first IDAT chunk' }
            }
            if ($length -eq 0 -or ($length % 3) -ne 0) {
                return [pscustomobject]@{ Valid = $false; Reason = "PNG PLTE chunk length ($length) must be a nonzero multiple of 3 (one RGB triplet per palette entry)" }
            }
            if ($length -gt 768) {
                return [pscustomobject]@{ Valid = $false; Reason = "PNG PLTE chunk length ($length) exceeds the maximum of 768 bytes (256 palette entries)" }
            }
            if ($null -ne $colorType -and ($colorType -eq 0 -or $colorType -eq 4)) {
                return [pscustomobject]@{ Valid = $false; Reason = "PNG PLTE chunk is not permitted for color type $colorType (grayscale, with or without alpha)" }
            }
            if ($null -ne $colorType -and $colorType -eq 3 -and $null -ne $bitDepth) {
                $paletteEntries = $length / 3
                $maxEntries = [Math]::Pow(2, $bitDepth)
                if ($paletteEntries -gt $maxEntries) {
                    return [pscustomobject]@{ Valid = $false; Reason = "PNG PLTE chunk has $paletteEntries palette entries, more than IHDR's bit depth $bitDepth can index (max $([int]$maxEntries))" }
                }
            }
        }
        if ($type -ceq 'IDAT') {
            if ($idatEnded) {
                return [pscustomobject]@{ Valid = $false; Reason = 'PNG IDAT chunks must be consecutive -- another chunk already appeared after the IDAT sequence ended' }
            }
            $idatStarted = $true
            $idatCount++
        } elseif ($idatStarted -and -not $idatEnded) {
            $idatEnded = $true
        }

        # Unknown critical chunk: bit 5 of the first type byte (0x20)
        # clear means uppercase means critical per spec -- a decoder that
        # does not recognize a critical chunk must not proceed, since it
        # cannot know what that chunk means for interpreting the image.
        # Unknown ANCILLARY chunks (lowercase first letter) are fine and
        # intentionally allowed through once their own bounds/CRC checks
        # (below, and above) pass -- this validator does not need to
        # understand every possible ancillary chunk to trust the file.
        $firstTypeByte = $Bytes[$pos + 4]
        $isCritical = ($firstTypeByte -band 0x20) -eq 0
        if ($isCritical -and ($knownCriticalTypes -cnotcontains $type)) {
            return [pscustomobject]@{ Valid = $false; Reason = "PNG contains an unrecognized critical chunk '$type' -- an unknown critical chunk cannot be safely treated as valid evidence" }
        }

        $storedCrc = ([uint32]$Bytes[$crcStart] -shl 24) -bor ([uint32]$Bytes[$crcStart + 1] -shl 16) -bor ([uint32]$Bytes[$crcStart + 2] -shl 8) -bor [uint32]$Bytes[$crcStart + 3]
        $computedCrc = Get-TPMCrc32 -Bytes $Bytes -Offset ([int]($pos + 4)) -Count ([int](4 + $length))
        if ($storedCrc -ne $computedCrc) {
            return [pscustomobject]@{ Valid = $false; Reason = ("PNG '{0}' chunk failed CRC validation (stored=0x{1:X8} computed=0x{2:X8}) -- structurally corrupted" -f $type, $storedCrc, $computedCrc) }
        }

        if ($type -ceq 'IHDR') {
            # Safe to read data bytes 8-12 unconditionally here -- $length
            # was already confirmed to be exactly 13 above, and the
            # data/CRC bounds check already confirmed dataStart+13 (and
            # therefore dataStart+12, the last data byte) is within the
            # file.
            [int64]$width = ([uint32]$Bytes[$dataStart] -shl 24) -bor ([uint32]$Bytes[$dataStart + 1] -shl 16) -bor ([uint32]$Bytes[$dataStart + 2] -shl 8) -bor [uint32]$Bytes[$dataStart + 3]
            [int64]$height = ([uint32]$Bytes[$dataStart + 4] -shl 24) -bor ([uint32]$Bytes[$dataStart + 5] -shl 16) -bor ([uint32]$Bytes[$dataStart + 6] -shl 8) -bor [uint32]$Bytes[$dataStart + 7]
            $bitDepth = [int]$Bytes[$dataStart + 8]
            $colorType = [int]$Bytes[$dataStart + 9]
            $compressionMethod = [int]$Bytes[$dataStart + 10]
            $filterMethod = [int]$Bytes[$dataStart + 11]
            $interlaceMethod = [int]$Bytes[$dataStart + 12]

            if ($width -lt 1 -or $width -gt $maxChunkLength) { return [pscustomobject]@{ Valid = $false; Reason = "PNG IHDR width ($width) must be 1 through 2^31 - 1" } }
            if ($height -lt 1 -or $height -gt $maxChunkLength) { return [pscustomobject]@{ Valid = $false; Reason = "PNG IHDR height ($height) must be 1 through 2^31 - 1" } }

            if ($validColorTypes -notcontains $colorType) {
                return [pscustomobject]@{ Valid = $false; Reason = "PNG IHDR declares an unknown color type ($colorType) -- valid values are 0, 2, 3, 4, 6" }
            }
            if ($validBitDepthsByColorType[$colorType] -notcontains $bitDepth) {
                $allowed = $validBitDepthsByColorType[$colorType] -join ', '
                return [pscustomobject]@{ Valid = $false; Reason = "PNG IHDR declares bit depth $bitDepth for color type $colorType, which the PNG spec does not permit (allowed: $allowed)" }
            }
            if ($compressionMethod -ne 0) {
                return [pscustomobject]@{ Valid = $false; Reason = "PNG IHDR declares an unknown compression method ($compressionMethod) -- only 0 is defined by the spec" }
            }
            if ($filterMethod -ne 0) {
                return [pscustomobject]@{ Valid = $false; Reason = "PNG IHDR declares an unknown filter method ($filterMethod) -- only 0 is defined by the spec" }
            }
            if ($interlaceMethod -ne 0 -and $interlaceMethod -ne 1) {
                return [pscustomobject]@{ Valid = $false; Reason = "PNG IHDR declares an unknown interlace method ($interlaceMethod) -- only 0 (none) and 1 (Adam7) are defined by the spec" }
            }
        }

        if ($type -ceq 'IEND') { $sawIend = $true }
        $pos = $crcStart + 4
        $chunkIndex++
    }

    if (-not $sawIend) {
        return [pscustomobject]@{ Valid = $false; Reason = 'PNG does not end with an IEND chunk -- likely truncated' }
    }
    if ($ihdrCount -eq 0) {
        return [pscustomobject]@{ Valid = $false; Reason = 'PNG has no IHDR chunk' }
    }
    if ($idatCount -eq 0) {
        return [pscustomobject]@{ Valid = $false; Reason = 'PNG has no IDAT chunk -- a PNG must contain image data' }
    }
    if ($colorType -eq 3 -and $plteCount -eq 0) {
        return [pscustomobject]@{ Valid = $false; Reason = 'PNG uses indexed color (color type 3) but has no PLTE chunk -- PLTE is required for this color type' }
    }

    return [pscustomobject]@{ Valid = $true; Reason = 'PNG chunk structure, ordering, uniqueness, and CRC validation passed' }
}

# Issue #151 review round 2/3: "successfully constructed an Image object"
# was not strong enough proof of a real, complete, uncorrupted PNG. GDI+
# detects actual image format from content, not the file extension, so
# JPEG bytes saved with a .png name previously decoded without error and
# passed as 'Captured'. GDI+ can also decode a materially truncated PNG
# far enough to report valid-looking dimensions before ever touching the
# (incomplete) pixel data, since Image.FromStream does not eagerly decode
# scanlines -- and even forced full-frame decoding (LockBits) does not
# validate per-chunk CRC integrity, so a PNG with a single corrupted byte
# inside IDAT (signature, structure, and IEND all otherwise intact) can
# still decode losslessly-looking without ever raising an error. None of
# "right filename", "GDI+ guessed a format", "GDI+ decoded *something*",
# or "GDI+ decoded the full frame without throwing" is sufficient proof on
# its own, so validation layers six independent checks before any of them
# can report success:
#   1. file exists / is non-empty
#   2. Test-TPMPngStructure: signature, chunk-by-chunk bounds/structure
#      (first chunk IHDR with exactly 13 bytes, terminal zero-length IEND,
#      nothing after it), and CRC-32 validation of every chunk -- this is
#      the only layer that actually detects payload-level corruption that
#      preserves the file's overall shape
#   3. GDI+ decodes it AND reports RawFormat = Png specifically (not just
#      "some image") -- this is what actually catches a renamed JPEG,
#      since GDI+ would decode it successfully but report RawFormat = Jpeg
#   4. positive width/height
#   5. LockBits over the full frame forces GDI+ to materialize every
#      scanline right now rather than lazily on first pixel access --
#      throws on incomplete/corrupt compressed data that construction
#      alone did not touch
#   6. no file lock remains afterward (verified by validating from an
#      in-memory byte copy in the first place -- see below)
# Reads the file's bytes into memory and constructs the validation Image
# from that byte array (System.Drawing.Image.FromStream), never
# Image.FromFile -- the latter keeps an open handle on the source file
# tied to the Image's lifetime even after pixel data is read, which would
# leave the just-captured screenshot locked; validating from an in-memory
# copy guarantees no file lock remains once this function returns.
function Test-TPMScreenshotFileValid {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ Valid = $false; Reason = 'file does not exist' }
    }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -eq 0) {
        return [pscustomobject]@{ Valid = $false; Reason = 'file is empty (zero length)' }
    }

    $structure = Test-TPMPngStructure -Bytes $bytes
    if (-not $structure.Valid) {
        return [pscustomobject]@{ Valid = $false; Reason = $structure.Reason }
    }

    # Same hardcoded-literal false positive as the other Add-Type calls in
    # this file -- traced, no untrusted input reaches this call.
    Add-Type -AssemblyName System.Drawing
    $stream = New-Object System.IO.MemoryStream(,$bytes)
    try {
        try {
            $image = [System.Drawing.Image]::FromStream($stream)
        } catch {
            return [pscustomobject]@{ Valid = $false; Reason = "file could not be decoded as a valid image: $($_.Exception.Message)" }
        }
        try {
            if ($image.RawFormat.Guid -ne [System.Drawing.Imaging.ImageFormat]::Png.Guid) {
                return [pscustomobject]@{ Valid = $false; Reason = "file decoded successfully but not as PNG (detected format: $($image.RawFormat)) -- likely a renamed image of a different format" }
            }
            if ($image.Width -le 0 -or $image.Height -le 0) {
                return [pscustomobject]@{ Valid = $false; Reason = "image has invalid dimensions ($($image.Width)x$($image.Height))" }
            }
            try {
                $bitmap = [System.Drawing.Bitmap]$image
                $rect = New-Object System.Drawing.Rectangle 0, 0, $bitmap.Width, $bitmap.Height
                $bmpData = $bitmap.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, $bitmap.PixelFormat)
                $bitmap.UnlockBits($bmpData)
            } catch {
                return [pscustomobject]@{ Valid = $false; Reason = "PNG pixel data could not be fully decoded (likely truncated or corrupt): $($_.Exception.Message)" }
            }
            return [pscustomobject]@{ Valid = $true; Reason = 'valid PNG' }
        } finally {
            $image.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

# Issue #151 review round 1 (finding #4): privacy/containment safeguard --
# GetConsoleWindow (kernel32) returns the console window handle actually
# associated with this process, which GetWindowRect (user32) then bounds,
# so the capture below can be narrowed to just that window instead of the
# full virtual desktop whenever the host environment makes that handle
# available. Returns $null (never throws) when it cannot be obtained
# reliably -- some hosting environments (certain remote sessions, some
# integrated terminals) never populate it -- so callers have an explicit
# signal to fall back to a full-desktop capture rather than silently
# guessing at a bad rectangle.
$tpmWindowInteropSource = @'
using System;
using System.Runtime.InteropServices;
public class TPMWindowInterop {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
}
'@
function Get-TPMConsoleWindowRect {
    try {
        if (-not ('TPMWindowInterop' -as [type])) {
            # InjectionHunter flags this Add-Type call (InjectionRisk.AddType).
            # Traced: $tpmWindowInteropSource is a fixed literal defined a few
            # lines above in this same file, never built from external or
            # caller-supplied input -- same hardcoded-literal false-positive
            # class already documented on the other Add-Type calls in this
            # file.
            Add-Type -Language CSharp -TypeDefinition $tpmWindowInteropSource -ErrorAction Stop
        }
        $hwnd = [TPMWindowInterop]::GetConsoleWindow()
        if ($hwnd -eq [IntPtr]::Zero) { return $null }
        $rect = New-Object TPMWindowInterop+RECT
        $ok = [TPMWindowInterop]::GetWindowRect($hwnd, [ref]$rect)
        if (-not $ok) { return $null }
        $width = $rect.Right - $rect.Left
        $height = $rect.Bottom - $rect.Top
        if ($width -le 0 -or $height -le 0) { return $null }
        return [pscustomobject]@{ X = $rect.Left; Y = $rect.Top; Width = $width; Height = $height }
    } catch {
        return $null
    }
}

# Review round 2 (Luna Max): distinguishes "this native error IS the signal
# for no usable interactive display" from every other Win32Exception, as its
# own pure, independently-testable decision -- kept separate from the actual
# GDI+ probe below so the classification itself can be exercised with a
# fabricated exception, without needing a real (or genuinely absent) display
# to hit either branch. ERROR_INVALID_HANDLE (6) is exactly the native error
# CopyFromScreen raises when there is no capturable desktop/window station
# (confirmed by direct reproduction in a non-interactive session). Any other
# native error code is a different, real problem and must not be classified
# as "no display".
function Test-TPMWin32ErrorIndicatesNoDisplay {
    param([int]$NativeErrorCode)
    return ($NativeErrorCode -eq 6)   # ERROR_INVALID_HANDLE
}

# Deterministically proves whether THIS session currently has a usable
# interactive display, by attempting the exact real primitive
# Save-TPMScreenCapture depends on (GDI+ Graphics.CopyFromScreen), at the
# smallest possible size. This is a live capability probe, not a static
# assumption -- a remote/headless session's desktop can transiently gain or
# lose screen-capture capability (confirmed: the same probe that failed with
# "The handle is invalid" in one run of this environment succeeded moments
# later in another), so a one-time environment check taken once and cached
# would go stale.
#
# Only the specific ERROR_INVALID_HANDLE signal (via
# Test-TPMWin32ErrorIndicatesNoDisplay) is treated as "no display, safe to
# skip" -- PowerShell wraps a thrown .NET exception from a method call in a
# MethodInvocationException, so the real Win32Exception is unwrapped from
# .InnerException before classifying it. Any other exception (a different
# Win32 error, or an unrelated failure entirely) is NOT a "no display"
# signal and is allowed to propagate -- a real certification run whose
# display access fails for some other, genuine reason must still fail
# loudly, never be silently absorbed as "environment doesn't support this".
function Test-TPMInteractiveDisplayAvailable {
    Add-Type -AssemblyName System.Drawing
    $bitmap = New-Object System.Drawing.Bitmap 1, 1
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.CopyFromScreen(0, 0, 0, 0, (New-Object System.Drawing.Size 1, 1))
            return $true
        } catch {
            $inner = $_.Exception.InnerException
            if ($inner -is [System.ComponentModel.Win32Exception] -and (Test-TPMWin32ErrorIndicatesNoDisplay -NativeErrorCode $inner.NativeErrorCode)) {
                return $false
            }
            throw
        } finally {
            $graphics.Dispose()
        }
    } finally {
        $bitmap.Dispose()
    }
}

# Real capture action for an on-screen console moment (certification suite
# running, final result, requested/effective root evidence) -- grabs the
# certification console's own window when Get-TPMConsoleWindowRect can
# resolve it (CaptureScope = 'Window'); falls back to the full virtual
# screen, explicitly classified as such, only when it cannot (CaptureScope
# = 'FullDesktop'). Returns the scope string so New-TPMCertificationScreenshot
# can record which one actually happened -- never silently reported as a
# narrow capture when it was not. In production this must keep failing
# loudly (never NotApplicable) when a real certification run cannot capture
# required evidence -- Test-TPMInteractiveDisplayAvailable above exists for
# the *test's* own runtime skip decision, and is never consulted here.
function Save-TPMScreenCapture {
    param([string]$Path)
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $windowBounds = Get-TPMConsoleWindowRect
    if ($windowBounds) {
        $x = $windowBounds.X; $y = $windowBounds.Y; $w = $windowBounds.Width; $h = $windowBounds.Height
        $scope = 'Window'
    } else {
        $full = [System.Windows.Forms.SystemInformation]::VirtualScreen
        $x = $full.Location.X; $y = $full.Location.Y; $w = $full.Width; $h = $full.Height
        $scope = 'FullDesktop'
    }
    $bitmap = New-Object System.Drawing.Bitmap $w, $h
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.CopyFromScreen($x, $y, 0, 0, (New-Object System.Drawing.Size $w, $h))
        } finally {
            $graphics.Dispose()
        }
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $bitmap.Dispose()
    }
    return $scope
}

# Real capture action for the adaptive-menu and Smoke File Safety evidence
# slots. Rasterizes already-rendered text (from Debug-TPM-MenuLayout.ps1
# -Render, or the exact real Smoke File Safety gate line built from this
# run's own $certification.Items) directly into a PNG via GDI+ instead of
# opening, resizing, and screen-grabbing a real console window --
# deterministic and does not depend on a live, focusable desktop session
# being available on the certification machine, which a real windowed
# capture would.
function Save-TPMRenderedTextCapture {
    param([string]$Path, [string[]]$Lines)
    # Same hardcoded-literal false positive as Save-TPMScreenCapture
    # above -- no untrusted input reaches this Add-Type call.
    Add-Type -AssemblyName System.Drawing
    # [System.Drawing.Font]::new(...), not New-Object -- New-Object's
    # comma-separated -ArgumentList left the (string, int, FontStyle)
    # overload ambiguous under real PowerShell 5.1 ("Multiple ambiguous
    # overloads found for 'Font' and the argument count: 3", confirmed by
    # direct repro); the static ::new() call resolves it correctly.
    $font = [System.Drawing.Font]::new('Consolas', 12.0, [System.Drawing.FontStyle]::Regular)
    $lineHeight = [int]($font.GetHeight() * 1.15)
    $longest = if ($Lines.Count -gt 0) { ($Lines | Measure-Object -Property Length -Maximum).Maximum } else { 40 }
    $width = [Math]::Max(200, ($longest * 9) + 40)
    $height = [Math]::Max(60, ($Lines.Count * $lineHeight) + 40)
    $bitmap = New-Object System.Drawing.Bitmap $width, $height
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.Clear([System.Drawing.Color]::Black)
            $brush = [System.Drawing.Brushes]::LightGray
            $y = 20
            foreach ($line in $Lines) {
                $graphics.DrawString($line, $font, $brush, 20, $y)
                $y += $lineHeight
            }
        } finally {
            $graphics.Dispose()
        }
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $bitmap.Dispose()
        $font.Dispose()
    }
    return $null
}

# Issue #151 review round 1 (finding #1): single source of truth for the
# [PASS]/[FAIL]/[N/A] mark shown for a scorecard item, shared by the real
# "## Gates" Markdown renderer below and the new Smoke File Safety
# evidence capture -- both must agree on exactly what mark a given item's
# real Status/Passed fields produce, since the evidence capture exists
# specifically to prove the two never diverge.
function Get-TPMGateMark {
    param($Item)
    if ($Item.PSObject.Properties.Name -contains 'Status' -and $Item.Status -eq 'NotApplicable') { return 'N/A' }
    if ($Item.Passed) { return 'PASS' }
    return 'FAIL'
}

function New-CertificationScorecard {
    param([hashtable]$Results)

    $checkMap = @{}
    foreach ($check in @($Results.Checks)) {
        $checkMap[$check.Name] = [bool]$check.Passed
    }

    $snapshotClean = $true
    if ($Results.Snapshots) {
        foreach ($name in $Results.Snapshots.Keys) {
            $s = $Results.Snapshots[$name]
            if (($s.Added + $s.Removed + $s.Changed) -ne 0) { $snapshotClean = $false }
        }
    }

    # Issue #149: $Results.Snapshots is populated unconditionally by the
    # harness (the pre/post tree-hash diffing runs regardless of
    # -RunUnattendedTPM), but "no unexpected changes" is a smoke-mode-only
    # invariant -- the per-check "Smoke mode no change: <area>" entries this
    # scorecard reads via $checkMap are themselves only ever added when NOT
    # running unattended (see the `if (-not $RunUnattendedTPM)` gate around
    # those Add-CheckResult calls in the main flow below). A real RC3
    # arcade certification run using -RunUnattendedTPM still scored this
    # item [PASS] with the literal text "no unexpected changes in smoke
    # mode" -- true in the sense that $snapshotClean happened to be true,
    # but a materially misleading claim: the run was not smoke mode, and
    # nothing in this harness actually asserts "no unexpected changes" as a
    # pass/fail condition for a real unattended run (there is no defined
    # baseline yet for which changes an unattended AutoSync/Register pass
    # is expected to make). Same explicit-N/A pattern as the restoration
    # item above: unattended mode marks this item Status = 'NotApplicable'
    # rather than reusing smoke-mode wording as if it were evidence.
    $smokeFileSafetyDetails = if ($Results.SmokeMode) {
        'no unexpected changes in smoke mode'
    } else {
        'not applicable in unattended mode -- file-safety diffing is a smoke-mode-only invariant, not asserted against real unattended runs'
    }
    $smokeFileSafetyStatus = if ($Results.SmokeMode) { if ($snapshotClean) { 'Pass' } else { 'Fail' } } else { 'NotApplicable' }
    $smokeFileSafetyPassed = if ($Results.SmokeMode) { $snapshotClean } else { $null }

    # PowerShell parses hashtable-literal (@{...}) values in command mode, not
    # expression mode -- an inline "if (...) {...} else {...}" as a value,
    # even parenthesized, fails at runtime with "The term 'if' is not
    # recognized..." (confirmed by direct repro; this crashed the harness
    # after Pester/install-health completed, on every real run). Precompute
    # into a variable first and reference the variable as the value instead.
    $pcsx2x6Details = if ($Results.Pcsx2x6.Present) {
        "canonicalDeployed=$($Results.Pcsx2x6.CanonicalFilesDeployed) cursorPathCanonical=$($Results.Pcsx2x6.CursorPathPointsCanonical)"
    } else {
        'not applicable -- no pcsx2x6 in this install'
    }

    $vbtDetails = if ($Results.VirtualBetaTester) {
        ("total={0} passed={1} failed={2} | human-behaviors={3} idempotency={4} recovery={5} environment-variations={6} high-tvd-behaviors={7}" -f `
            $Results.VirtualBetaTester.Total, $Results.VirtualBetaTester.Passed, $Results.VirtualBetaTester.Failed, `
            $Results.VirtualBetaTester.HumanBehaviors, $Results.VirtualBetaTester.IdempotencyChecks, `
            $Results.VirtualBetaTester.RecoveryBehaviors, $Results.VirtualBetaTester.EnvironmentVariations, `
            $Results.VirtualBetaTester.HighTvdBehaviors)
    } else {
        'not collected'
    }

    # Issue #146: precomputed into variables first, not inline in the
    # @(...) score-item list below -- PowerShell parses hashtable-literal
    # values in command mode, not expression mode, so an inline if/else
    # there parses cleanly but throws "The term 'if' is not recognized..."
    # only at execution (see the guard test and comment on $pcsx2x6Details
    # above for the confirmed real incident this class of bug caused).
    $effectiveRootDisplay = if ($Results.EffectiveTeknoParrotRoot) { $Results.EffectiveTeknoParrotRoot } else { '(not found in unattended log)' }
    $unattendedRootDetails = if ($Results.SmokeMode) {
        'not applicable -- smoke mode (no unattended TPM run)'
    } else {
        ("requested={0} effective={1}" -f $Results.RequestedTeknoParrotRoot, $effectiveRootDisplay)
    }
    $unattendedRootPassed = if ($Results.SmokeMode) { $true } else { [bool]$checkMap['Unattended TPM used requested root'] }

    # Issue #146 review round 3: the "Unattended TPM config restoration"
    # check (added round 2 to catch a silently-failed config restore) was
    # recorded by Add-CheckResult during the run but never actually rolled
    # up into the scorecard -- a failed or missing restoration could not,
    # by itself, flip Overall to NOT CERTIFIED. Same smoke-mode-explicit
    # pattern as the root-binding item above: smoke mode never attempts a
    # restore at all (the unattended block that would add this check never
    # runs), so it is explicitly not applicable there, never silently
    # "passing" by coincidence of an absent key.
    $restoreDetails = if ($Results.SmokeMode) {
        'not applicable in smoke mode -- no unattended TPM run, nothing to restore'
    } else {
        $restoreCheck = @($Results.Checks) | Where-Object { $_.Name -eq 'Unattended TPM config restoration' } | Select-Object -Last 1
        if ($restoreCheck) { $restoreCheck.Details } else { 'no restoration check recorded' }
    }
    # Issue #146 review round 4: smoke mode previously reported this item as
    # Passed = $true, which the Markdown renderer below then printed as
    # "[PASS] ... not applicable" -- not-applicable is not the same claim as
    # passed, and collapsing the two let a gate that never actually ran read
    # as evidence the way a real pass does. $restoreStatus is the single
    # source of truth for this item: 'Pass' / 'Fail' / 'NotApplicable'. Only
    # this item carries a Status property -- every other score item is
    # untouched and keeps deriving PASS/FAIL from Passed alone, both in the
    # scoring loop and the Markdown renderer below.
    $restorePassedRaw = [bool]$checkMap['Unattended TPM config restoration']
    $restoreStatus = if ($Results.SmokeMode) { 'NotApplicable' } elseif ($restorePassedRaw) { 'Pass' } else { 'Fail' }
    # Deliberately $null, not $true, in smoke mode -- an N/A item must never
    # be representable as "Passed = $true" even internally, since any future
    # code path that reads .Passed without also checking .Status (as the old
    # scoring loop did) would otherwise silently miscount it as evidence of a
    # pass.
    $restorePassed = if ($Results.SmokeMode) { $null } else { $restorePassedRaw }

    $scoreItems = @(
        [pscustomobject]@{Area='Repository'; Passed=($checkMap['Repository available'] -and $checkMap['Repository clean']); Details=$Results.GitStatus},
        [pscustomobject]@{Area='Pester'; Passed=($Results.Pester -and $Results.Pester.Failed -eq 0); Details=("total={0} passed={1} failed={2}" -f $Results.Pester.Total, $Results.Pester.Passed, $Results.Pester.Failed)},
        [pscustomobject]@{Area='Static Analysis'; Passed=($Results.PSScriptAnalyzerFindings -eq 0); Details=("findings={0}" -f $Results.PSScriptAnalyzerFindings)},
        [pscustomobject]@{Area='Real Install Health'; Passed=[bool]$checkMap['Real install health check']; Details=$Results.InstallHealthReport},
        [pscustomobject]@{Area='Backups'; Passed=($Results.Backup.UserProfiles -or $Results.Backup.GameProfiles); Details=("UserProfiles={0} GameProfiles={1}" -f $Results.Backup.UserProfiles, $Results.Backup.GameProfiles)},
        [pscustomobject]@{Area='Smoke File Safety'; Passed=$smokeFileSafetyPassed; Status=$smokeFileSafetyStatus; Details=$smokeFileSafetyDetails},
        # ADR155-0309 Checkpoint B2: this is the informational/provisional
        # preview only -- the real Artifacts readiness signal (staging,
        # publisher availability, genuine synthetic pipeline invocation) is
        # the production authority's own Artifacts fact
        # (Test-TPMProductionPackagePreflightV1, in ProductionFacts.psm1),
        # not this directory-existence check.
        [pscustomobject]@{Area='Artifacts'; Passed=(Test-Path -LiteralPath $reportDir -PathType Container); Details=$reportDir},
        [pscustomobject]@{Area='pcsx2x6 crosshair path (issue #79)'; Passed=[bool]$checkMap['pcsx2x6 crosshair path (issue #79)']; Details=$pcsx2x6Details},
        [pscustomobject]@{Area='Behavioral Certification (Virtual Beta Tester)'; Passed=($Results.VirtualBetaTester -and $Results.VirtualBetaTester.Total -gt 0 -and $Results.VirtualBetaTester.Failed -eq 0); Details=$vbtDetails},
        [pscustomobject]@{Area='Unattended TPM root binding'; Passed=$unattendedRootPassed; Details=$unattendedRootDetails},
        [pscustomobject]@{Area='Unattended TPM config restoration'; Passed=$restorePassed; Status=$restoreStatus; Details=$restoreDetails}
    )

    # ADR155-0309 Checkpoint B2: this is an informational/provisional
    # preview only, never consulted for the certification decision, exit
    # code, or publication -- Get-TPMCertificationScoreFromItems (the
    # legacy scoring authority) has been removed entirely. N/A items
    # (currently only the restoration item in smoke mode) are still
    # excluded from both sides of this preview count, matching the
    # dispatcher's own real scoring semantics, so the provisional display
    # does not visibly disagree with the eventual authoritative result on
    # that specific point.
    $previewApplicableItems = @($scoreItems | Where-Object { -not ($_.PSObject.Properties.Name -contains 'Status' -and $_.Status -eq 'NotApplicable') })
    $previewPassedCount = @($previewApplicableItems | Where-Object { $_.Passed }).Count
    $previewTotalCount = @($previewApplicableItems).Count
    $previewOverall = if ($previewTotalCount -gt 0 -and $previewPassedCount -eq $previewTotalCount) { 'CERTIFIED' } else { 'NOT CERTIFIED' }
    $previewScorePercent = if ($previewTotalCount -gt 0) { [math]::Round(($previewPassedCount / [double]$previewTotalCount) * 100, 2) } else { 0 }

    [pscustomobject]@{
        Timestamp = $Results.Timestamp
        Overall = $previewOverall
        Passed = $previewPassedCount
        Total = $previewTotalCount
        ScorePercent = $previewScorePercent
        Items = $scoreItems
        ReportDir = $reportDir
        # Issue #111: certification provenance, duplicated onto this object
        # (not just $results/the validation JSON) so a reviewer can confirm
        # the certified commit from the certification scorecard JSON alone,
        # without needing to cross-reference a second file.
        Repository = $Results.RepoPath
        Branch = $Results.GitBranch
        Commit = $Results.Commit
        CommitShort = $Results.CommitShort
        OriginMainCommit = $Results.OriginMainCommit
        SyncStatus = $Results.SyncStatus
        WorkingTreeClean = ($Results.GitStatus -eq '(clean)')
        GitVersion = $Results.GitVersion
        PowerShellVersion = $Results.PowerShellVersion
        TpmScriptVersion = $Results.TpmScriptVersion
        TpmDisplayVersion = $Results.TpmDisplayVersion
        # Issue #146: requested vs effective TeknoParrot root, both on the
        # scorecard object itself for the same reason as the git provenance
        # fields above -- readable from the certification scorecard JSON
        # alone, without cross-referencing TPM-Unattended.log.
        RequestedTeknoParrotRoot = $Results.RequestedTeknoParrotRoot
        EffectiveTeknoParrotRoot = $Results.EffectiveTeknoParrotRoot
        # Issue #151: certification evidence, duplicated onto the
        # scorecard object for the same reason as the git/root provenance
        # fields above. Deliberately NOT part of $scoreItems/scoring --
        # see $applicableItems above, which never reads this property.
        Screenshots = @($Results.Screenshots)
    }
}

$results = [ordered]@{
    Timestamp = $stamp
    RepoPath = $RepoPath
    TeknoParrotRoot = $TeknoParrotRoot
    # Issue #146: explicit Requested/Effective pair, distinct from the
    # legacy TeknoParrotRoot field above (kept for compatibility with
    # anything already reading it) -- EffectiveTeknoParrotRoot is populated
    # only when -RunUnattendedTPM actually ran (see that block below); it
    # stays $null for a smoke-mode run, which is a normal, non-failing state
    # since there is no unattended TPM process whose effective root could be
    # checked.
    RequestedTeknoParrotRoot = $TeknoParrotRoot
    EffectiveTeknoParrotRoot = $null
    HarnessRoot = $HarnessRoot
    ReportDir = $reportDir
    BackupDir = $backupDir
    SmokeMode = (-not $RunUnattendedTPM)
    Checks = @()
    # Evidence remains outside numeric score arithmetic, but required
    # evidence eligibility is enforced by the production authority (a
    # Skipped record for a Required slot is rejected immediately at
    # RecordEvidence time -- EVIDENCE_REQUIRED_SKIPPED -- via
    # Authority.psm1's Assert-TPMEvidenceRecordV1). A perfect numeric score
    # therefore cannot certify an incomplete run.
    Screenshots = @()
    EvidenceWorkflowId = $script:tpmEvidenceWorkflowId
    PreliminaryStatus = 'RUNNING'
    CertificationIdentity = $null
}

# Collection is a prerequisite phase, not part of finalization. These values
# exist before any collection operation so strict mode can never turn an early
# failure into a secondary uninitialized-variable/property exception.
$collectionCompleted = $false
$collectionLocationPushed = $false
$collectionFailure = $null
$collectionFailureDiagnostic = $null
$healthResult = $null
$healthLoadError = $null

# Records one screenshot attempt (captured, failed, or skipped) onto
# $results.Screenshots and echoes a short status line to the console --
# the same "one accumulator, one console line" pattern Add-CheckResult
# uses for check results, kept separate because screenshots are evidence,
# not a pass/fail check.
function Add-Screenshot {
    param([string]$ScreenshotDir,[string]$Name,[string]$EvidenceType,[scriptblock]$CaptureAction,[switch]$Skip,[string]$SkipReason)

    # System Invariant Inventory: replay prevention / final-record ordering.
    # The ledger seals itself the instant 'final-certification-result' is
    # issued -- fail loudly (throw) rather than silently accept evidence
    # after finalization, since that would mean the certification workflow
    # itself has a logic error, not something a structured Failed record
    # should quietly absorb.
    if ($script:tpmEvidenceLedgerSealed) {
        throw "certification evidence ledger is sealed -- no further evidence may be issued after final-certification-result (attempted: '$Name')"
    }

    try {
        if ($Skip) { $shot=New-TPMCertificationScreenshot -ScreenshotDir $ScreenshotDir -Name $Name -Skip -SkipReason $SkipReason }
        else { $shot=New-TPMCertificationScreenshot -ScreenshotDir $ScreenshotDir -Name $Name -EvidenceType $EvidenceType -CaptureAction $CaptureAction }
    } catch {
        $safeName=if([string]::IsNullOrWhiteSpace($Name)){'unnamed-evidence'}else{$Name}
        $shot=[pscustomobject]@{Name=$safeName;Label=$safeName;Path=$null;Status='Failed';EvidenceType='Failed';Required=(-not $Skip);WorkflowId=$script:tpmEvidenceWorkflowId;CaptureScope=$null;Details="evidence creation failed safely: $($_.Exception.Message)"}
    }

    # System Invariant Inventory: path ownership / containment, checked at
    # issuance (fail closed, before the record can ever enter the ledger),
    # not only re-checked later against the caller's copy of it.
    if ($shot.Path) {
        $fullPath = [System.IO.Path]::GetFullPath([string]$shot.Path)
        $fullScreenshotDir = [System.IO.Path]::GetFullPath($ScreenshotDir)
        if (-not $fullPath.StartsWith($fullScreenshotDir, [System.StringComparison]::OrdinalIgnoreCase)) {
            $shot = [pscustomobject]@{Name=$shot.Name;Label=$shot.Name;Path=$shot.Path;Status='Failed';EvidenceType='Failed';Required=$true;WorkflowId=$script:tpmEvidenceWorkflowId;CaptureScope=$null;Details="issued evidence path escapes this run's screenshot directory: $($shot.Path)"}
        } elseif (@($script:tpmEvidenceLedger | Where-Object { $_.Path -and ([string]$_.Path -ceq [string]$shot.Path) }).Count -gt 0) {
            $shot = [pscustomobject]@{Name=$shot.Name;Label=$shot.Name;Path=$shot.Path;Status='Failed';EvidenceType='Failed';Required=$true;WorkflowId=$script:tpmEvidenceWorkflowId;CaptureScope=$null;Details="issued evidence path is already owned by another ledger record: $($shot.Path)"}
        }
    }

    # Sequence remains an informational/reporting field only. Evidence
    # ordering that the production pipeline actually trusts comes from each
    # New-TPMProductionEvidenceRecordV1 call's own position in the harness's
    # fixed for-loop over $legacyEvidence (see the Checkpoint B2 certification
    # tail below), not from this mutable property on an already-issued object.
    $shot = $shot | Add-Member -NotePropertyName Sequence -NotePropertyValue ($script:tpmEvidenceLedger.Count + 1) -Force -PassThru
    $script:tpmEvidenceLedger.Add($shot)
    if ([string]$shot.Name -ceq 'final-certification-result') {
        $script:tpmEvidenceLedgerSealed = $true
    }
    $script:results.Screenshots += $shot
    $mark=switch($shot.Status){'Captured'{'[SHOT]'}'Skipped'{'[SKIP]'}default{'[FAIL]'}}
    $scopeSuffix=if($shot.CaptureScope){" ($($shot.CaptureScope))"}else{''}
    Write-Host ("  {0} {1}{2}: {3}" -f $mark,$shot.Label,$scopeSuffix,$(if($shot.Path){$shot.Path}else{$shot.Details}))
    return $shot
}

function Add-CheckResult {
    param([string]$Name, [bool]$Passed, [string]$Details)
    $script:results.Checks += [pscustomobject]@{
        Name = $Name
        Passed = $Passed
        Details = $Details
    }
}

# Issue #122: prints a short, concise header before each gate so an operator
# watching a long-running certification pass can see which gate is currently
# running, why it exists, and what a good outcome looks like -- without
# waiting for the final scorecard to find out anything failed. Deliberately
# terse (one line each) per the issue's own "concise, not verbose narration"
# requirement.
# Keep a persistent status signal visible even when the console body is
# temporarily blank or Pester output is suppressed by Summary mode.
function Set-TPMConsoleStatus {
    param([string]$Gate, [string]$Purpose, [string]$Expected)

    $title = if ([string]::IsNullOrWhiteSpace($Gate)) {
        'TeknoParrot Manager Certification Suite'
    } else {
        "TPM Certification - $Gate"
    }

    try { [Console]::Title = $title } catch {}
    try {
        $status = if ([string]::IsNullOrWhiteSpace($Purpose)) {
            $Expected
        } elseif ([string]::IsNullOrWhiteSpace($Expected)) {
            $Purpose
        } else {
            "$Purpose | $Expected"
        }
        if (-not [string]::IsNullOrWhiteSpace($script:OperatorStatusPath)) { Add-Content -LiteralPath $script:OperatorStatusPath -Value $status -Encoding utf8 }

    } catch {}
}

function Clear-TPMConsoleStatus {
    try { [Console]::Title = 'TeknoParrot Manager Certification Suite' } catch {}
}

function Write-TPMGateHeader {
    param([string]$Gate, [string]$Purpose, [string]$Expected)
    Set-TPMConsoleStatus -Gate $Gate -Purpose $Purpose -Expected $Expected
    Write-Host ""
    $script:tpmOperatorPhase++
    $line = ("[{0}/8] {1} -- {2}" -f $script:tpmOperatorPhase,$Gate,$Expected)
    if (-not [string]::IsNullOrWhiteSpace($script:OperatorStatusPath)) { Add-Content -LiteralPath $script:OperatorStatusPath -Value $line -Encoding utf8 }
    Write-Host $line
    Write-Host ("    Purpose : {0}" -f $Purpose) -ForegroundColor DarkGray
    Write-Host ("    Expected: {0}" -f $Expected) -ForegroundColor DarkGray
}

# Issue #146: fail fast, before any gate runs (Pester, static analysis,
# backups, unattended TPM, etc.), when the requested -TeknoParrotRoot is not
# actually a TeknoParrot installation. Every one of those gates either does
# nothing meaningful against such a root or actively wastes the time of a
# full certification pass to produce a misleading partial scorecard -- a
# real run against a root missing all three markers previously still scored
# 8/9 instead of failing outright. This never enters the normal
# $results/Add-CheckResult/New-CertificationScorecard flow: it writes its
# own clearly-labeled report and throws before that flow's $results object
# is even built, so this failure mode can never be confused with an ordinary
# TPM product certification FAIL.
$rootValidation = Test-TPMCertificationRootValid -TeknoParrotRoot $TeknoParrotRoot
if (-not $rootValidation.IsValid) {
    $invalidMsg = Get-TPMInvalidCertificationEnvironmentMessage -TeknoParrotRoot $TeknoParrotRoot -MissingMarkers $rootValidation.MissingMarkers

    Write-Host ""
    Write-Host "============================================" -ForegroundColor Red
    Write-Host " INVALID CERTIFICATION ENVIRONMENT" -ForegroundColor Red
    Write-Host "============================================" -ForegroundColor Red
    Write-Host $invalidMsg -ForegroundColor Red
    Write-Host ""

    $invalidReportLines = @(
        "# TPM Certification Scorecard"
        ""
        "Overall: **INVALID CERTIFICATION ENVIRONMENT**"
        ""
        "This run did NOT certify TPM product behavior. The requested"
        "-TeknoParrotRoot does not point at a valid TeknoParrot installation,"
        "so no certification gates (Pester, static analysis, install health,"
        "unattended TPM, etc.) were run against it. This is not a TPM"
        "product failure."
        ""
        "## Certification Target"
        ""
        "- Requested TeknoParrot root: $TeknoParrotRoot"
        "- Missing installation marker(s): $($rootValidation.MissingMarkers -join ', ')"
        "- Certified at: $stamp"
        ""
        "## Required installation markers"
        ""
        "- TeknoParrotUi.exe"
        "- GameProfiles"
        "- UserProfiles"
    )
    # Distinctly-named, non-authoritative diagnostic files -- this never
    # reaches the production authority/publication path at all (it throws
    # immediately below), so these must never share a filename with
    # anything New-TPMPublicationCommitV1 could later write to $reportDir.
    $invalidEnvironmentMd = Join-Path $reportDir "TPM-Invalid-Certification-Environment.md"
    $invalidEnvironmentJson = Join-Path $reportDir "TPM-Invalid-Certification-Environment.json"
    $invalidReportLines -join [Environment]::NewLine | Out-File -FilePath $invalidEnvironmentMd -Encoding utf8

    [pscustomobject]@{
        Overall = 'INVALID CERTIFICATION ENVIRONMENT'
        RequestedTeknoParrotRoot = $TeknoParrotRoot
        MissingMarkers = $rootValidation.MissingMarkers
        Timestamp = $stamp
    } | ConvertTo-Json -Depth 4 | Out-File -FilePath $invalidEnvironmentJson -Encoding utf8

    throw $invalidMsg
}

$script:OperatorStatusPath=$OperatorStatusPath
$script:tpmOperatorPhase=0
try {
    Push-Location $RepoPath
    $collectionLocationPushed = $true

    # Issue #151: first required evidence slot -- captured as early as
    # possible in the real gate flow so the screenshot actually shows the
    # certification suite mid-run, not an empty or pre-launch console.
    [void](Add-Screenshot -ScreenshotDir $screenshotDir -Name 'certification-suite-running' -EvidenceType 'ScreenCapture' -CaptureAction { param($p) Save-TPMScreenCapture -Path $p })

    Write-TPMGateHeader -Gate 'Repository' -Purpose 'Confirms the certified branch, commit, remote SHA, and working-tree state' -Expected 'clean worktree, pinned branch/commit, cached upstream SHA matches HEAD'
    $gitVersion = & git @gitScopedArguments --version
    $gitBranch = & git @gitScopedArguments rev-parse --abbrev-ref HEAD
    $gitCommit = & git @gitScopedArguments rev-parse HEAD
    $gitCommitShort = & git @gitScopedArguments rev-parse --short HEAD
    $gitStatusLines = @(& git @gitScopedArguments status --short)
    $repoClean = ($gitStatusLines.Count -eq 0)
    if ($repoClean) {
        $gitStatusText = '(clean)'
    } else {
        $gitStatusText = ($gitStatusLines -join [Environment]::NewLine)
    }

    # Certification is read-only and never performs network synchronization.
    # Compare only with an already-present cached remote-tracking ref.
    $originMainCommit = $null
    try {
        $env:GIT_TERMINAL_PROMPT = '0'
        $originMainCommit = (& git @gitScopedArguments rev-parse --verify origin/main 2>$null)
        if ($LASTEXITCODE -ne 0) { $originMainCommit = $null }
    } catch { $originMainCommit = $null }
    $syncStatus = if (-not $originMainCommit) {
        'UNKNOWN -- cached origin/main is unavailable; certification does not access the network'
    } elseif ($gitCommit -eq $originMainCommit) {
        'MATCHES cached origin/main'
    } else {
        "DIFFERS from cached origin/main ($originMainCommit)"
    }
    $results.GitVersion = $gitVersion
    $results.GitBranch = $gitBranch
    $results.Commit = $gitCommit
    $results.CommitShort = $gitCommitShort
    $results.GitStatus = $gitStatusText
    $results.OriginMainCommit = $originMainCommit
    $results.SyncStatus = $syncStatus
    $results.PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    Add-CheckResult 'Repository available' $true "branch=$gitBranch commit=$gitCommit"
    Add-CheckResult 'Repository clean' $repoClean $gitStatusText

    # Resolved once, here, and reused for every pcsx2x6-related check below
    # (backup, snapshot, issue #79 verification, scorecard) -- previously
    # backup and snapshot both hardcoded the literal folder name "pcsx2x6"
    # while the #79 block below did a proper candidate search, so an install
    # where the real folder wasn't literally named "pcsx2x6" would silently
    # skip backup/snapshot coverage while the #79 check still found it
    # correctly. Flagged by Codex review as a required-before-1.0 fix.
    $pcsx2Dir = Resolve-Pcsx2Directory -TeknoParrotRoot $TeknoParrotRoot
    $crosshairPath = if ($pcsx2Dir) { Join-Path $pcsx2Dir 'TeknoParrot\crosshairs' } else { '' }

    Write-TPMGateHeader -Gate 'Backups' -Purpose 'Snapshots UserProfiles/GameProfiles/config before any test runs' -Expected 'backup created for every folder present'
    $backupItems = [ordered]@{}
    $backupItems.UserProfiles = Copy-IfExists (Join-Path $TeknoParrotRoot 'UserProfiles') 'UserProfiles'
    $backupItems.GameProfiles = Copy-IfExists (Join-Path $TeknoParrotRoot 'GameProfiles') 'GameProfiles'
    $backupItems.Pcsx2x6Crosshairs = if ($crosshairPath) { Copy-IfExists $crosshairPath 'pcsx2x6-crosshairs' } else { $false }
    $backupItems.Config = Copy-IfExists (Join-Path $RepoPath 'TeknoParrot-Manager.config.json') 'TeknoParrot-Manager.config.json'
    $results.Backup = $backupItems

    $userProfilesPath = Join-Path $TeknoParrotRoot 'UserProfiles'
    $gameProfilesPath = Join-Path $TeknoParrotRoot 'GameProfiles'
    $preUserProfiles = Get-TreeHash $userProfilesPath
    $preGameProfiles = Get-TreeHash $gameProfilesPath
    # Issue #172: this if/else's own empty branch is comma-wrapped for the
    # same reason Compare-TreeSnapshot's internal normalization is -- an
    # un-wrapped "else { @() }" here collapses to $null when captured by
    # this assignment, on this environment, confirmed by direct
    # reproduction. Compare-TreeSnapshot now also defends against a null
    # argument on its own, but no caller should rely on that alone to
    # avoid producing a null snapshot in the first place.
    $preCrosshairs = if ($crosshairPath) { Get-TreeHash $crosshairPath } else { ,@() }

    Write-TPMGateHeader -Gate 'Pester regression suite' -Purpose 'Runs every unit/regression test in an isolated PowerShell process' -Expected 'zero failed tests'
    $pesterChild = Join-Path $PSScriptRoot 'Invoke-TPM-PesterChild.ps1'
    $pesterResultPath = Join-Path $reportDir 'Pester-result-v1.json'
    $pesterNUnitPath = Join-Path $reportDir 'Pester-NUnit.xml'
    $technicalLogDirectory = Join-Path $reportDir 'TechnicalLogs'
    $pesterProcess = Invoke-TPMIsolatedProcessV1 -FilePath (Get-Command pwsh).Source -ArgumentList @(
        '-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$pesterChild,
        '-RepositoryPath',$RepoPath,'-ResultPath',$pesterResultPath,'-NUnitPath',$pesterNUnitPath
    ) -WorkingDirectoryRoot $RepoPath -WorkingDirectory $RepoPath -LogDirectoryRoot $reportDir -LogDirectory $technicalLogDirectory -Identity 'pester' -TimeoutSeconds $PesterRegressionTimeoutSeconds -Environment (New-TPMPesterChildEnvironment -RepositoryPath $RepoPath)
    if ($pesterProcess.TimedOut) { throw "Pester regression suite timed out after $PesterRegressionTimeoutSeconds seconds." }
    $pesterContract = Read-TPMPesterResultV1 -Path $pesterResultPath
    if (($pesterProcess.ExitCode -eq 0) -ne ($pesterContract.Failed -eq 0 -and $pesterContract.FailedContainers -eq 0)) {
        throw 'PESTER_RESULT_CONTRADICTORY: child exit code disagrees with structured result'
    }
    $results.PesterVersion = $pesterContract.Engine
    $results.Pester = [pscustomobject]@{
        Passed=$pesterContract.Passed;Failed=$pesterContract.Failed;Skipped=$pesterContract.Skipped
        Inconclusive=0;NotRun=$pesterContract.NotRun;Total=$pesterContract.Discovered
        Duration=[timespan]::FromMilliseconds($pesterContract.DurationMilliseconds);Result=$(if($pesterContract.Failed -eq 0){'Passed'}else{'Failed'})
    }
    $results.Pester | ConvertTo-Json -Depth 4 | Out-File (Join-Path $reportDir 'Pester-summary.json') -Encoding utf8
    Add-CheckResult 'Pester tests' ($pesterContract.Failed -eq 0) "total=$($pesterContract.Discovered) passed=$($pesterContract.Passed) failed=$($pesterContract.Failed)"
    if(-not[string]::IsNullOrWhiteSpace($script:OperatorStatusPath)){Add-Content -LiteralPath $script:OperatorStatusPath -Value ("Pester totals: total={0} passed={1} failed={2} skipped={3} containers={4}" -f $pesterContract.Discovered,$pesterContract.Passed,$pesterContract.Failed,$pesterContract.Skipped,$pesterContract.Containers) -Encoding utf8}
    $categories=$pesterContract.Categories
    $results.VirtualBetaTester=[pscustomobject]@{
        Total=$categories.VirtualBetaTesterTotal;Passed=$categories.VirtualBetaTesterPassed;Failed=$categories.VirtualBetaTesterFailed
        HumanBehaviors=$categories.HumanBehaviors;IdempotencyChecks=$categories.IdempotencyChecks
        RecoveryBehaviors=$categories.RecoveryBehaviors;EnvironmentVariations=$categories.EnvironmentVariations;HighTvdBehaviors=$categories.HighTvdBehaviors
    }
    Add-CheckResult 'Behavioral Certification (Virtual Beta Tester)' ($categories.VirtualBetaTesterTotal -gt 0 -and $categories.VirtualBetaTesterFailed -eq 0) "total=$($categories.VirtualBetaTesterTotal) passed=$($categories.VirtualBetaTesterPassed) failed=$($categories.VirtualBetaTesterFailed)"
    $failureLines=@($pesterContract.Failures|ForEach-Object{"- $($_.Name): $($_.Message)"})
    if($failureLines.Count-eq0){$failureLines=@('(no failures)')}
    $failureLines|Out-File -FilePath (Join-Path $reportDir 'Pester-Failures.txt') -Encoding utf8
    Write-TPMGateHeader -Gate 'Static analysis (PSScriptAnalyzer)' -Purpose 'Scans TeknoParrot-Manager.ps1 for known-bad patterns' -Expected 'zero Error/Warning findings'
    $analyzerCommand = Get-Command Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue
    if (-not $analyzerCommand) { throw 'Invoke-ScriptAnalyzer not found. Install it with: Install-Module PSScriptAnalyzer -Scope CurrentUser -Force' }
    $analyzerModule = Get-Module PSScriptAnalyzer -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    if ($analyzerModule) { $results.PSScriptAnalyzerVersion = $analyzerModule.Version.ToString() }
    # Matches the documented release gate exactly (RELEASE-SAFETY-CHECKLIST.md
    # section 1): TeknoParrot-Manager.ps1 only, Error/Warning severity, using
    # the project's approved-exclusions settings file. An earlier version of
    # this check ran "-Path $RepoPath -Recurse" with no severity filter and no
    # settings file -- that scanned every file in the repo (tools/, scripts/,
    # Tests/) against defaults never meant to apply to them, and surfaced
    # Information-severity findings the settings file specifically documents
    # as accepted. That produced 33 "findings" that were never real gate
    # failures, just a different (wrong) invocation than what release sign-off
    # actually checks.
    $analyzerSettingsPath = Join-Path $RepoPath 'PSScriptAnalyzerSettings.psd1'
    $mainScriptPath = Join-Path $RepoPath 'TeknoParrot-Manager.ps1'
    $analyzer = Invoke-ScriptAnalyzer -Path $mainScriptPath -Severity Error, Warning -Settings $analyzerSettingsPath
    $analyzer | ConvertTo-Json -Depth 6 | Out-File (Join-Path $reportDir 'PSScriptAnalyzer.json') -Encoding utf8
    $results.PSScriptAnalyzerFindings = @($analyzer).Count
    Add-CheckResult 'PSScriptAnalyzer' (@($analyzer).Count -eq 0) "findings=$(@($analyzer).Count)"

    $pathsToCheck = @(
        @{Name='TeknoParrot root'; Path=$TeknoParrotRoot; Type='Container'},
        @{Name='TeknoParrotUi.exe'; Path=(Join-Path $TeknoParrotRoot 'TeknoParrotUi.exe'); Type='Leaf'},
        @{Name='GameProfiles'; Path=$gameProfilesPath; Type='Container'},
        @{Name='UserProfiles'; Path=$userProfilesPath; Type='Container'}
    )
    foreach ($p in $pathsToCheck) {
        $exists = Test-Path -LiteralPath $p.Path -PathType $p.Type
        Add-CheckResult $p.Name $exists $p.Path
    }

    Write-TPMGateHeader -Gate 'pcsx2x6 crosshair path (issue #79)' -Purpose 'Confirms crosshair deployment path is correct for pcsx2x6 installs' -Expected 'pass, or not-applicable if no pcsx2x6 folder exists'
    # Issue #79: pcsx2x6 crosshair path verification. Read-only -- this never
    # runs the interactive Invoke-CrosshairSetup wizard (Read-Host prompts,
    # browser launch) against the real install, it only inspects whatever
    # state already exists there. Not every TeknoParrot install has pcsx2x6
    # (it's specific to a handful of lightgun titles), so this is conditional
    # on the pcsx2x6 folder actually being present -- absence is reported as
    # not-applicable, not a failure, unlike the unconditional hard-fail this
    # replaced (which would have certified-FAIL any install without pcsx2x6
    # at all). $pcsx2Dir was already resolved once, above, and is reused here
    # rather than searched for again.
    if (-not $pcsx2Dir) {
        $results.Pcsx2x6 = [pscustomobject]@{ Present = $false }
        Add-CheckResult 'pcsx2x6 crosshair path (issue #79)' $true 'not applicable -- no pcsx2x6 folder in this install'
    } else {
        $canonicalDir  = Join-Path $pcsx2Dir 'TeknoParrot\crosshairs'
        $legacyP1      = Join-Path $pcsx2Dir 'P1.png'
        $legacyP2      = Join-Path $pcsx2Dir 'P2.png'
        $canonicalP1   = Join-Path $canonicalDir 'P1.png'
        $canonicalP2   = Join-Path $canonicalDir 'P2.png'
        $iniPath       = Join-Path $pcsx2Dir 'inis\PCSX2.ini'

        $canonicalDeployed = (Test-Path -LiteralPath $canonicalP1 -PathType Leaf) -and (Test-Path -LiteralPath $canonicalP2 -PathType Leaf)
        $legacyPresent     = (Test-Path -LiteralPath $legacyP1 -PathType Leaf) -or (Test-Path -LiteralPath $legacyP2 -PathType Leaf)

        $cursorPathP1 = $null
        $cursorPathP2 = $null
        $iniFound = Test-Path -LiteralPath $iniPath -PathType Leaf
        if ($iniFound) {
            # Read-only parse -- mirrors Set-Pcsx2CursorPaths' own section
            # tracking without writing anything back.
            $lines = [System.IO.File]::ReadAllLines($iniPath)
            $sect = ''
            foreach ($ln in $lines) {
                $t = $ln.Trim()
                if ($t -match '^\[(.+)\]$') { $sect = $matches[1].ToLower(); continue }
                if ($t -match '^cursor_path\s*=\s*(.*)$') {
                    if ($sect -eq 'usb port 1 guncon2') { $cursorPathP1 = $matches[1].Trim() }
                    elseif ($sect -eq 'usb port 2 guncon2') { $cursorPathP2 = $matches[1].Trim() }
                }
            }
        }

        $cursorPointsCanonical = ($cursorPathP1 -and $cursorPathP1.TrimEnd('\') -eq $canonicalP1.TrimEnd('\')) -and
                                  ($cursorPathP2 -and $cursorPathP2.TrimEnd('\') -eq $canonicalP2.TrimEnd('\'))

        $results.Pcsx2x6 = [pscustomobject]@{
            Present                = $true
            Pcsx2Dir               = $pcsx2Dir
            CanonicalDir           = $canonicalDir
            CanonicalFilesDeployed = $canonicalDeployed
            LegacyRootFilesPresent = $legacyPresent
            IniFound               = $iniFound
            CursorPathP1           = $cursorPathP1
            CursorPathP2           = $cursorPathP2
            CursorPathPointsCanonical = $cursorPointsCanonical
        }

        # Informational, not a hard requirement: the canonical files/ini only
        # reflect the new location once crosshair setup has actually been run
        # since the #79 fix shipped. What this DOES assert is that the check
        # itself ran and could inspect the real install without modifying it.
        Add-CheckResult 'pcsx2x6 crosshair path (issue #79)' $true `
            ("pcsx2Dir={0} canonicalDeployed={1} legacyRootPresent={2} iniFound={3} cursorPathCanonical={4}" -f `
                $pcsx2Dir, $canonicalDeployed, $legacyPresent, $iniFound, $cursorPointsCanonical)

        if ($iniFound -and (-not $cursorPathP1 -or -not $cursorPathP2)) {
            Add-CheckResult 'pcsx2x6 PCSX2.ini has cursor_path for both USB ports' $false `
                ("P1={0} P2={1}" -f $cursorPathP1, $cursorPathP2)
        } elseif ($iniFound) {
            Add-CheckResult 'pcsx2x6 PCSX2.ini has cursor_path for both USB ports' $true `
                ("P1={0} P2={1}" -f $cursorPathP1, $cursorPathP2)
        }
    }

    # ECVF: generic Emulator Contract Verification, informational and
    # side-by-side with the legacy pcsx2x6-specific block above -- not yet
    # authoritative (see TPMCertification.Shadow.psm1's
    # Get-TPMShadowEmulatorContractVerificationV1 doc comment for why: no
    # new mandatory Section 9 fact identifier has been registered, and
    # cutting the live gate over is a separate, later, explicitly-approved
    # step gated on the jvs-lightgun RuntimeCapability no longer being
    # Unconfirmed). $pcsx2Dir here is the already-resolved pcsx2x6 folder
    # itself, matching the contract's PresenceDetector, which expects
    # InstallRoot to be the emulator's own folder, not the overall
    # TeknoParrot root -- a second contract with a different subfolder
    # convention will need this reconciled, not copied.
    Write-TPMGateHeader -Gate 'Emulator Contract Verification (ECVF, informational)' -Purpose 'Generic, contract-driven verification alongside the legacy pcsx2x6 block -- reports only, never blocks' -Expected 'pass, or not-applicable if no pcsx2x6 folder exists'
    if ($pcsx2Dir) {
        try {
            $ecvf = Get-TPMShadowEmulatorContractVerificationV1 -TeknoParrotRoot $pcsx2Dir
            if (-not $ecvf.RegistryValid) {
                $errorSummary = ($ecvf.Errors | ForEach-Object { "$($_.ContractId): $($_.Message)" }) -join '; '
                Add-CheckResult 'Emulator Contract Verification (ECVF, informational)' $false "registry invalid -- $errorSummary"
            } else {
                $summary = ($ecvf.Records | ForEach-Object { "$($_.ContractId)/$($_.CapabilityType)/$($_.CapabilityId)=$($_.Status)" }) -join ', '
                Add-CheckResult 'Emulator Contract Verification (ECVF, informational)' $true $(if ($summary) { $summary } else { 'no applicable capabilities' })
            }
        } catch {
            Add-CheckResult 'Emulator Contract Verification (ECVF, informational)' $false "evaluation threw -- $_"
        }
    } else {
        Add-CheckResult 'Emulator Contract Verification (ECVF, informational)' $true 'not applicable -- no pcsx2x6 folder in this install'
    }

    # Issue #146: "Expected" now states the real gate condition -- a report
    # being written is necessary but not sufficient. Add-CheckResult below
    # is gated on Test-TPMInstallHealthGate's semantic read of the
    # structured health result, not merely that InstallHealth.json/.md
    # exist on disk.
    Write-TPMGateHeader -Gate 'Real install health check' -Purpose 'Read-only scan of the actual TeknoParrot install for registration gaps' -Expected 'report collected AND no installation-critical checks failed'
    $healthScript = Join-Path $PSScriptRoot 'Invoke-TPM-InstallHealthCheck.ps1'
    if (Test-Path -LiteralPath $healthScript -PathType Leaf) {
        $healthOutDir = Join-Path $reportDir 'InstallHealth'
        & $healthScript -TeknoParrotRoot $TeknoParrotRoot -OutDir $healthOutDir | Out-File -FilePath (Join-Path $reportDir 'InstallHealth-console.txt') -Encoding utf8
        $results.InstallHealthReport = Join-Path $healthOutDir 'InstallHealth.md'
        $healthJsonPath = Join-Path $healthOutDir 'InstallHealth.json'
        $healthResult = $null
        $healthLoadError = $null
        if (-not (Test-Path -LiteralPath $healthJsonPath -PathType Leaf)) {
            $healthLoadError = "InstallHealth.json not found at $healthJsonPath"
        } else {
            try {
                $healthResult = Get-Content -LiteralPath $healthJsonPath -Raw | ConvertFrom-Json
            } catch {
                $healthLoadError = "InstallHealth.json at $healthJsonPath failed to parse: $($_.Exception.Message)"
            }
        }
        $healthGate = Test-TPMInstallHealthGate -HealthResult $healthResult -LoadError $healthLoadError
        $results.InstallHealthGate = $healthGate
        Add-CheckResult 'Real install health check' $healthGate.Passed ("{0} -- {1}" -f $results.InstallHealthReport, $healthGate.Reason)
    } else {
        $healthLoadError = "install health script not found at $healthScript"
        Add-CheckResult 'Real install health check' $false "missing=$healthScript"
    }

    $profiles = @()
    if (Test-Path -LiteralPath $gameProfilesPath) { $profiles = @(Get-ChildItem -LiteralPath $gameProfilesPath -File -ErrorAction SilentlyContinue) }
    $userProfiles = @()
    if (Test-Path -LiteralPath $userProfilesPath) { $userProfiles = @(Get-ChildItem -LiteralPath $userProfilesPath -File -ErrorAction SilentlyContinue) }
    $centipede = @($profiles | Where-Object { $_.Name -match 'centipede|chaos' })
    $results.GameProfilesCount = $profiles.Count
    $results.UserProfilesCount = $userProfiles.Count
    $results.CentipedeChaosCandidates = @($centipede | Select-Object -ExpandProperty Name)
    Add-CheckResult 'GameProfiles count' ($profiles.Count -gt 0) "count=$($profiles.Count)"
    Add-CheckResult 'UserProfiles count' ($userProfiles.Count -ge 0) "count=$($userProfiles.Count)"
    if ($centipede.Count -gt 0) {
        $centipedeDetails = $centipede.Name -join ', '
    } else {
        $centipedeDetails = 'none found'
    }
    Add-CheckResult 'Centipede Chaos profile scan' $true $centipedeDetails

    if ($RunUnattendedTPM) {
        Write-TPMGateHeader -Gate 'Unattended TPM root binding' -Purpose 'Confirms unattended TPM actually ran against the requested certification root' -Expected 'effective root (from the run log) equals the requested -TeknoParrotRoot'
        $scriptPath = Join-Path $RepoPath 'TeknoParrot-Manager.ps1'
        if (!(Test-Path -LiteralPath $scriptPath -PathType Leaf)) { throw "TeknoParrot-Manager.ps1 not found at $scriptPath" }
        $tpmLog = Join-Path $reportDir 'TPM-Unattended.log'

        # Issue #146: TeknoParrot-Manager.ps1's own -Unattended flow reads
        # its saved TeknoParrot-Manager.config.json and has no CLI override
        # for which TeknoParrot root to use -- a real certification run
        # confirmed it silently launched against whatever root was last
        # saved interactively on that machine, not the certification's
        # requested -TeknoParrotRoot, so the resulting log was not actually
        # evidence against the target named in the scorecard. Invoke-
        # TPMUnattendedRootBinding (issue #146 review round 3) is the full
        # snapshot -> override/create -> invoke -> restore -> verify
        # orchestration, extracted so it is covered by integration-level
        # tests, not just its individual pure-function pieces.
        $tpmConfigPath = Join-Path $RepoPath 'TeknoParrot-Manager.config.json'
        $binding = Invoke-TPMUnattendedRootBinding -ConfigPath $tpmConfigPath -TeknoParrotRoot $TeknoParrotRoot -LogPath $tpmLog -InvokeUnattended {
            $unattended=Invoke-TPMIsolatedProcessV1 -FilePath (Get-Command pwsh).Source -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$scriptPath,'-Unattended') -WorkingDirectoryRoot $RepoPath -WorkingDirectory $RepoPath -LogDirectoryRoot $reportDir -LogDirectory (Join-Path $reportDir 'TechnicalLogs') -Identity 'unattended-tpm' -Environment @{NO_COLOR='1';TERM='dumb';GIT_TERMINAL_PROMPT='0'}
            Copy-Item -LiteralPath $unattended.StdOutPath -Destination $tpmLog -Force
            if($unattended.ExitCode-ne0){throw "Unattended TPM exited with code $($unattended.ExitCode). See $($unattended.StdErrPath)"}
        }
        $results.EffectiveTeknoParrotRoot = $binding.EffectiveTeknoParrotRoot
        $results.UnattendedBinding = $binding
        foreach ($check in $binding.Checks) {
            Add-CheckResult $check.Name $check.Passed $check.Details
        }
    }

    # Issue #151: requested/effective root evidence. Printed to the
    # console (not just the report files) immediately before capture, so
    # the screenshot itself actually shows the evidence a reviewer needs,
    # rather than an unrelated console state that merely happened to be on
    # screen at this point in the run.
    Write-Host ""
    Write-Host ("  Requested TeknoParrot root: {0}" -f $results.RequestedTeknoParrotRoot)
    Write-Host ("  Effective TeknoParrot root: {0}" -f (Get-TPMEffectiveRootReportText -EffectiveRoot $results.EffectiveTeknoParrotRoot -SmokeMode $results.SmokeMode))
    [void](Add-Screenshot -ScreenshotDir $screenshotDir -Name 'requested-effective-root-evidence' -EvidenceType 'ScreenCapture' -CaptureAction { param($p) Save-TPMScreenCapture -Path $p })

    # Issue #151: "live thumbnail evidence" and "live controls evidence"
    # are conditional, "(when displayed)" evidence slots -- this harness
    # does not itself drive TeknoParrot-Manager.ps1's live thumbnail
    # download (AutoSync) or Propagate Controls flows (both require
    # interactive menu choices this read-only/-Unattended harness never
    # makes), so neither is ever genuinely displayed by a certification
    # run today. Recorded as explicitly Skipped, with the real reason, so
    # a reviewer sees these evidence slots were considered and correctly
    # not applicable to this harness's current scope, rather than silently
    # missing from the evidence list.
    [void](Add-Screenshot -ScreenshotDir $screenshotDir -Name 'live-thumbnail-evidence' -Skip -SkipReason 'not displayed -- this harness does not drive TeknoParrot-Manager.ps1''s live thumbnail download flow')
    [void](Add-Screenshot -ScreenshotDir $screenshotDir -Name 'live-controls-evidence' -Skip -SkipReason 'not displayed -- this harness does not drive TeknoParrot-Manager.ps1''s live Propagate Controls flow')

    Write-TPMGateHeader -Gate 'Smoke file safety' -Purpose 'Confirms nothing changed in UserProfiles/GameProfiles during this smoke run' -Expected 'no unexpected file changes'
    $postUserProfiles = Get-TreeHash $userProfilesPath
    $postGameProfiles = Get-TreeHash $gameProfilesPath
    # Issue #172: see the matching $preCrosshairs comment above -- the
    # empty branch here must be comma-wrapped for the same reason.
    $postCrosshairs = if ($crosshairPath) { Get-TreeHash $crosshairPath } else { ,@() }
    $results.Snapshots = [ordered]@{
        UserProfiles = Compare-TreeSnapshot $preUserProfiles $postUserProfiles
        GameProfiles = Compare-TreeSnapshot $preGameProfiles $postGameProfiles
        Pcsx2x6Crosshairs = Compare-TreeSnapshot $preCrosshairs $postCrosshairs
    }
    if (-not $RunUnattendedTPM) {
        foreach ($name in $results.Snapshots.Keys) {
            $s = $results.Snapshots[$name]
            Add-CheckResult "Smoke mode no change: $name" (($s.Added + $s.Removed + $s.Changed) -eq 0) "added=$($s.Added) removed=$($s.Removed) changed=$($s.Changed) skipped=$($s.BeforeSkipped + $s.AfterSkipped)"
        }
    }

    # Issue #151: adaptive-menu evidence (normal/small/maximized). Uses
    # Debug-TPM-MenuLayout.ps1 -Render (already the harness's own
    # deterministic diagnostic for the adaptive menu, issue #104) to get
    # the actual rendered menu text for a given viewport, then rasterizes
    # that text directly into a PNG -- deterministic evidence of the real
    # render pipeline's output at each named tier, without needing to open,
    # resize, and screen-grab a real console window (which would depend on
    # a live, focusable desktop session the certification machine may not
    # have). Width/height pairs land inside Get-ConsoleLayoutTier's actual
    # tier boundaries: Compact (<90) for "small", Standard (90-119) for
    # "normal", Ultra (>=150) for "maximized".
    Write-TPMGateHeader -Gate 'Adaptive menu evidence' -Purpose 'Captures the real adaptive-menu render at three viewport tiers' -Expected 'one screenshot per tier, or an explicit failure if rendering could not be captured'
    $debugMenuScript = Join-Path $PSScriptRoot 'Debug-TPM-MenuLayout.ps1'
    $adaptiveMenuTiers = @(
        [pscustomobject]@{ Name = 'adaptive-menu-normal';    Width = 100; Height = 32 }
        [pscustomobject]@{ Name = 'adaptive-menu-small';     Width = 60;  Height = 22 }
        [pscustomobject]@{ Name = 'adaptive-menu-maximized'; Width = 180; Height = 50 }
    )
    if (!(Test-Path -LiteralPath $debugMenuScript -PathType Leaf)) {
        foreach ($tier in $adaptiveMenuTiers) {
            [void](Add-Screenshot -ScreenshotDir $screenshotDir -Name $tier.Name -EvidenceType 'DeterministicRender' -CaptureAction { param($p) throw "Debug-TPM-MenuLayout.ps1 not found at $debugMenuScript (target screenshot: $p)" })
        }
    } else {
        foreach ($tier in $adaptiveMenuTiers) {
            $tierWidth = $tier.Width
            $tierHeight = $tier.Height
            [void](Add-Screenshot -ScreenshotDir $screenshotDir -Name $tier.Name -EvidenceType 'DeterministicRender' -CaptureAction {
                param($p)
                $render=Invoke-TPMIsolatedProcessV1 -FilePath (Get-Command pwsh).Source -ArgumentList @('-NoProfile','-NonInteractive','-File',$debugMenuScript,'-Width',[string]$tierWidth,'-Height',[string]$tierHeight,'-Render') -WorkingDirectoryRoot $RepoPath -WorkingDirectory $RepoPath -LogDirectoryRoot $reportDir -LogDirectory (Join-Path $reportDir 'TechnicalLogs') -Identity ("menu-{0}"-f$tier.Name) -Environment @{NO_COLOR='1';TERM='dumb'}
                if($render.ExitCode-ne0){throw "Menu renderer exited with code $($render.ExitCode)."}
                $renderedLines = @(Get-Content -LiteralPath $render.StdOutPath)
                if ($renderedLines.Count -eq 0) { throw "Debug-TPM-MenuLayout.ps1 -Width $tierWidth -Height $tierHeight -Render produced no output" }
                Save-TPMRenderedTextCapture -Path $p -Lines $renderedLines
            })
        }
    }

    $certificationIdentityEnd = Get-TPMCertificationGitIdentitySnapshotV1 -RepositoryPath $RepoPath
    $results.CertificationIdentity = New-TPMCertificationGitIdentityV1 -Start $certificationIdentityStart -End $certificationIdentityEnd -ExpectedBranch $ExpectedBranch -ExpectedCommit $ExpectedCommit
    $identityDetails=if($results.CertificationIdentity.IdentityValid){"branch=$($certificationIdentityEnd.Branch) commit=$($certificationIdentityEnd.Commit) remote=$($certificationIdentityEnd.RemoteCommit) clean=$($certificationIdentityEnd.Clean)"}else{[string]$results.CertificationIdentity.RefMutationReason}
    Add-CheckResult 'Certification identity' ([bool]$results.CertificationIdentity.IdentityValid) $identityDetails
    $results.PreliminaryStatus = if (@($results.Checks | Where-Object { -not $_.Passed }).Count -eq 0) { 'PASS' } else { 'FAIL' }
    $collectionCompleted = $true
}
catch {
    $collectionFailure = $_
    $collectionFailureDiagnostic = ($_ | Out-String).Trim()
    $results.PreliminaryStatus = 'FAIL'
    $results.Error = $collectionFailure.Exception.Message
    try { Add-CheckResult 'Unhandled validation error' $false $collectionFailure.Exception.Message }
    catch {
        $secondaryDiagnostic = ($_ | Out-String).Trim()
        $collectionFailureDiagnostic += [Environment]::NewLine +
            "Secondary failure while recording the validation check (initiating failure retained): $secondaryDiagnostic"
    }
}
finally {
    if($collectionLocationPushed){
        try { Pop-Location }
        catch {
            if($collectionCompleted){
                $collectionCompleted=$false
                $collectionFailure=$_
                $collectionFailureDiagnostic=($_|Out-String).Trim()
                $results.PreliminaryStatus='FAIL'
                $results.Error=$collectionFailure.Exception.Message
            }
        }
    }
    $runTimer.Stop()
    $results.Elapsed = $runTimer.Elapsed.ToString()
    $results.PowerShellVersion = $PSVersionTable.PSVersion.ToString()

    if(-not$collectionCompleted){
        $collectionAbortMessage=if($null-ne$collectionFailure){$collectionFailure.Exception.Message}else{'collection did not reach its successful completion point'}
        Write-Host ""
        Write-Host "============================================" -ForegroundColor Red
        Write-Host " CERTIFICATION PIPELINE ABORTED (infrastructure failure)" -ForegroundColor Red
        Write-Host "============================================" -ForegroundColor Red
        Write-Host (" REASON       : {0}" -f $collectionAbortMessage) -ForegroundColor Red
        if(-not[string]::IsNullOrWhiteSpace($collectionFailureDiagnostic)){
            Write-Host " DIAGNOSTIC   :" -ForegroundColor Red
            Write-Host $collectionFailureDiagnostic -ForegroundColor Red
        }
        Write-Host " STATUS       : NOT DETERMINED -- no certification decision was reached" -ForegroundColor Red
        Write-Host " PUBLISHED    : false -- collection was incomplete; production composition was not entered" -ForegroundColor Red
        if(-not[string]::IsNullOrWhiteSpace($script:OperatorStatusPath)){
            Add-Content -LiteralPath $script:OperatorStatusPath -Value 'FINAL STATUS: PIPELINE ABORTED' -Encoding utf8
            Add-Content -LiteralPath $script:OperatorStatusPath -Value ("Reason: {0}" -f (ConvertTo-TPMSafeTechnicalTextV1 -Text $collectionAbortMessage)) -Encoding utf8
        }
        Exit-TPMCertificationRepositoryLockV1 -Lock $certificationRepositoryLock
        exit 1
    }

    # Issue #111 / Release Integrity: TPM script version and display version
    # are read via regex against the raw file text, never by executing
    # TeknoParrot-Manager.ps1 -- this harness must never run arbitrary
    # top-level script code as a side effect of generating a report. Computed
    # before New-CertificationScorecard is called below, since that function
    # reads these fields.
    $tpmScriptVersion = 'unknown'
    $tpmDisplayVersion = 'unknown'
    try {
        $mainScriptContent = Get-Content -LiteralPath $mainScriptPath -Raw
        $versionMatch = [regex]::Match($mainScriptContent, '(?m)^\$ScriptVersion\s*=\s*"([^"]+)"')
        if ($versionMatch.Success) { $tpmScriptVersion = $versionMatch.Groups[1].Value }
        $candidateMatch = [regex]::Match($mainScriptContent, '(?m)^\$ReleaseCandidateLabel\s*=\s*"([^"]+)"')
        if ($candidateMatch.Success) {
            $tpmDisplayVersion = "v$tpmScriptVersion $($candidateMatch.Groups[1].Value)"
        } else {
            $headerMatch = [regex]::Match($mainScriptContent, '(?m)^# TeknoParrot Manager\s+\|\s+(.+)$')
            if ($headerMatch.Success) { $tpmDisplayVersion = $headerMatch.Groups[1].Value.Trim() }
        }
    } catch {
        $tpmScriptVersion = 'unknown (could not read TeknoParrot-Manager.ps1)'
        $tpmDisplayVersion = 'unknown (could not read TeknoParrot-Manager.ps1)'
    }
    $results.TpmScriptVersion = $tpmScriptVersion
    $results.TpmDisplayVersion = $tpmDisplayVersion

    # Issue #151: computed once here (Overall/Passed/Total/ScorePercent are
    # needed for the final console summary below), but every file this run
    # writes -- both certificationJson/certificationMd, both json/md -- is
    # written further down, AFTER the final-certification-result screenshot
    # is captured and appended to $results.Screenshots. A screenshot taken
    # of the final console summary cannot, by construction, already be
    # listed in a report written before that screenshot exists; writing
    # every report only after capture is what makes the final entry appear
    # in all of them, not just the console-only ones.
    $certification = New-CertificationScorecard -Results $results

    # Issue #151 review round 1 (finding #1): a deterministic rendering of
    # this run's ACTUAL Smoke File Safety gate line -- Area, mark (via
    # Get-TPMGateMark, the exact same function the "## Gates" Markdown
    # section below uses), and Details -- not a generic root or final-
    # result screenshot. During an unattended run this item's real Status
    # is 'NotApplicable' (issue #149), so the rendered evidence shows
    # "[N/A] Smoke File Safety" with unattended-mode Details and no smoke-
    # mode wording; during a smoke-mode run it shows the real Pass/Fail
    # result instead. Either way this is the real scorecard content, not a
    # fabrication -- confirmed by review-round tests that this rendered
    # text always matches $certification.Items directly.
    $smokeFileSafetyItem = $certification.Items | Where-Object { $_.Area -eq 'Smoke File Safety' } | Select-Object -First 1
    $smokeFileSafetyLines = if ($smokeFileSafetyItem) {
        @(
            'Smoke File Safety Evidence'
            '=========================='
            ''
            ("Certification mode : {0}" -f $(if ($results.SmokeMode) { 'Smoke' } else { 'Unattended' }))
            ("[{0}] {1}: {2}" -f (Get-TPMGateMark -Item $smokeFileSafetyItem), $smokeFileSafetyItem.Area, $smokeFileSafetyItem.Details)
        )
    } else {
        @('Smoke File Safety Evidence', '==========================', '', '(Smoke File Safety item not found in this run''s scorecard)')
    }
    [void](Add-Screenshot -ScreenshotDir $screenshotDir -Name 'smoke-file-safety-evidence' -EvidenceType 'DeterministicRender' -CaptureAction { param($p) Save-TPMRenderedTextCapture -Path $p -Lines $smokeFileSafetyLines })

    Write-Host ""
    Write-Host "============================================"
    Write-Host " TPM CERTIFICATION SCORECARD - PROVISIONAL"
    Write-Host "============================================"
    Write-Host (" Pending : final evidence validation (gate result: {0})" -f $certification.Overall)
    Write-Host (" Score   : {0}/{1} ({2}%)" -f $certification.Passed, $certification.Total, $certification.ScorePercent)
    Write-Host (" Report  : {0}" -f (Join-Path $reportDir 'TPM-Certification-Scorecard.md'))
    Write-Host "============================================"
    [void](Add-Screenshot -ScreenshotDir $screenshotDir -Name 'final-certification-result' -EvidenceType 'ScreenCapture' -CaptureAction { param($p) Save-TPMScreenCapture -Path $p })

    # ADR155-0309 Checkpoint B2: the production authority is the sole
    # certification decision/publication path from here on. There is
    # exactly one authoritative destination ($reportDir), one bundle, and
    # one publisher (New-TPMPublicationCommitV1, invoked only through
    # Complete-TPMProductionCertificationCycleV1). The legacy
    # Complete-TPMCertificationTransaction / Get-TPMCertificationScoreFromItems /
    # Test-TPMScoreItemManifest / Test-TPMArtifactManifest /
    # Publish-TPMCertificationArtifacts mechanism, and the
    # Add-Report/Add-CertificationReport artifact-text accumulators that fed
    # it, have been removed entirely -- there is no remaining code path in
    # this file that can assign a competing FINAL STATUS/OVERALL/ExitCode or
    # write a competing bundle/marker.
    #
    # If ANY exception occurs anywhere in this block -- before a genuine
    # TPMFinalOutcomeV1 exists -- this harness must not fabricate NOT
    # CERTIFIED or any other authoritative outcome, must report an
    # infrastructure/aborted-pipeline diagnostic instead, must return a
    # nonzero exit code, must publish no authoritative marker or bundle, and
    # must never fall back to the removed legacy authority. The try/catch
    # below is the only place that can happen.
    $productionDestinationRoot = $reportDir
    $productionAborted = $false
    $productionAbortMessage = $null
    $productionCycleResult = $null
    try {
        $productionPngValidator = {
            param($Path)
            $valid = Test-TPMScreenshotFileValid -Path $Path
            if (-not $valid.Valid) { return [pscustomobject]@{Valid=$false;Reason=$valid.Reason;Width=0;Height=0} }
            $image = [System.Drawing.Image]::FromFile($Path)
            try { return [pscustomobject]@{Valid=$true;Reason=$valid.Reason;Width=$image.Width;Height=$image.Height} }
            finally { $image.Dispose() }
        }

        $productionAuthority = New-TPMProductionWorkflowAuthorityV1 -Mode $(if($results.SmokeMode){'Smoke'}else{'Unattended'}) -EvidenceRoot $screenshotDir -ReportRoot $reportDir -PngValidator $productionPngValidator

        # Step 1 of the harness's own required sequence: create the
        # production authority (above), then record the eleven production
        # facts (below) -- New-TPMProductionFactRecordsV1 is Checkpoint B1's
        # dedicated fact adapter; it never imports or calls Shadow.psm1.
        $productionFacts = @(New-TPMProductionFactRecordsV1 -Results $results -RepositoryPath $RepoPath -ReportDirectory $reportDir -BackupDirectory $backupDir -HealthResult $healthResult -HealthLoadError $healthLoadError -UnattendedBinding $binding -StagingParentRoot $productionStagingParentRoot -DestinationRoot $productionDestinationRoot -WorkingDirectoryRoot $productionWorkingDirectory -WorkingDirectory $productionWorkingDirectory)
        $productionIdentityEnd = Get-TPMCertificationGitIdentitySnapshotV1 -RepositoryPath $RepoPath
        $productionIdentity = New-TPMCertificationGitIdentityV1 -Start $certificationIdentityStart -End $productionIdentityEnd -ExpectedBranch $ExpectedBranch -ExpectedCommit $ExpectedCommit
        $results.CertificationIdentity = $productionIdentity
        $repositoryFact = $productionFacts | Where-Object { $_.Identifier -ceq 'Repository' } | Select-Object -First 1
        $repositoryFact.Data.CertificationIdentity = $productionIdentity
        $repositoryFact.Data.RepositoryClean = [bool]$productionIdentityEnd.Clean
        $repositoryFact.Data.GitStatus = if($productionIdentityEnd.Clean){'(clean)'}else{'not clean at final identity check'}
        foreach ($fact in $productionFacts) { [void](&$productionAuthority RecordFact $fact) }

        # Step 2: record the nine evidence records in their required order
        # and provenance. $results.Screenshots is this run's real evidence
        # issuance ledger, in the exact order Get-TPMEvidenceManifestV1
        # expects (certification-suite-running, requested-effective-root-
        # evidence, live-thumbnail-evidence, live-controls-evidence, the
        # three adaptive-menu captures, smoke-file-safety-evidence,
        # final-certification-result -- confirmed by the Add-Screenshot call
        # sites above, in that exact order). New-TPMProductionEvidenceRecordV1
        # is a fresh, independent adapter against Authority.psm1's own
        # evidence schema -- it does not import or call Shadow.psm1's
        # evidence adapter.
        $productionEvidenceManifest = Get-TPMEvidenceManifestV1
        $legacyEvidence = @($results.Screenshots)
        if ($legacyEvidence.Count -ne 9) { throw "PRODUCTION_EVIDENCE_COUNT_INVALID: expected 9 harness evidence records, found $($legacyEvidence.Count)" }
        for ($i = 0; $i -lt 8; $i++) {
            $productionRecord = New-TPMProductionEvidenceRecordV1 -LegacyRecord $legacyEvidence[$i] -Expected $productionEvidenceManifest[$i] -EvidenceRoot $screenshotDir -PngValidator $productionPngValidator
            [void](&$productionAuthority RecordEvidence $productionRecord)
        }

        # Step 3: issue final evidence -- the dispatcher's own phase machine
        # requires the score preview it was derived from as a dependency.
        $productionScorePreview = &$productionAuthority DeriveScorePreview
        $productionFinalEvidence = New-TPMProductionEvidenceRecordV1 -LegacyRecord $legacyEvidence[8] -Expected $productionEvidenceManifest[8] -EvidenceRoot $screenshotDir -PngValidator $productionPngValidator
        [void](&$productionAuthority IssueFinalEvidence $productionFinalEvidence $productionScorePreview)

        # Step 4: seal the authority.
        $preSealIdentityEnd = Get-TPMCertificationGitIdentitySnapshotV1 -RepositoryPath $RepoPath
        $preSealIdentity = New-TPMCertificationGitIdentityV1 -Start $certificationIdentityStart -End $preSealIdentityEnd -ExpectedBranch $ExpectedBranch -ExpectedCommit $ExpectedCommit
        if(-not$preSealIdentity.IdentityValid-or[string]$preSealIdentityEnd.RefSnapshotSha256-ne[string]$productionIdentityEnd.RefSnapshotSha256-or[string]$preSealIdentityEnd.ReflogSnapshotSha256-ne[string]$productionIdentityEnd.ReflogSnapshotSha256){throw "CERTIFICATION_IDENTITY_CHANGED_BEFORE_SEAL: $($preSealIdentity.RefMutationReason)"}
        $productionSealedRun = &$productionAuthority Seal

        $postSealIdentityEnd = Get-TPMCertificationGitIdentitySnapshotV1 -RepositoryPath $RepoPath
        $postSealIdentity = New-TPMCertificationGitIdentityV1 -Start $certificationIdentityStart -End $postSealIdentityEnd -ExpectedBranch $ExpectedBranch -ExpectedCommit $ExpectedCommit
        if(-not$postSealIdentity.IdentityValid-or[string]$postSealIdentityEnd.RefSnapshotSha256-ne[string]$productionIdentityEnd.RefSnapshotSha256-or[string]$postSealIdentityEnd.ReflogSnapshotSha256-ne[string]$productionIdentityEnd.ReflogSnapshotSha256){throw "CERTIFICATION_IDENTITY_CHANGED_AFTER_SEAL: $($postSealIdentity.RefMutationReason)"}

        # Step 5: invoke the sole seven-step certification core
        # (Checkpoint B1/ADR155-0309 Sub-step A's
        # Complete-TPMProductionCertificationCycleV1) -- eligibility,
        # Section 8.3 candidate (bundle construction only, never presented as
        # an authoritative runtime outcome), staging, publication commit,
        # genuine dispatcher-issued TPMFinalOutcomeV1, and the runtime
        # projection derived exclusively from that genuine final outcome.
        $productionCycleResult = Complete-TPMProductionCertificationCycleV1 -Authority $productionAuthority -SealedRun $productionSealedRun -StagingParentRoot $productionStagingParentRoot -DestinationRoot $productionDestinationRoot
    } catch {
        $productionAborted = $true
        $productionAbortMessage = $_.Exception.Message
    }

    Clear-TPMConsoleStatus

    if ($productionAborted) {
        # No genuine TPMFinalOutcomeV1 exists. Do not fabricate NOT
        # CERTIFIED or any other authoritative outcome; report an
        # infrastructure/aborted-pipeline diagnostic and return nonzero.
        # There is no fallback to the removed legacy authority.
        #
        # Whether "no authoritative marker or bundle was written" is
        # actually TRUE depends on where the exception occurred:
        # New-TPMPublicationCommitV1's own atomicity guarantees that an
        # exception BEFORE a successful commit leaves nothing behind, and
        # Complete-TPMProductionCertificationCycleV1's own post-commit
        # safety net (Remove-TPMPublicationCommitV1, ADR155-0309 Checkpoint
        # B2 review correction) rolls back a bundle that WAS committed if a
        # later step (RegisterCommittedPublication/IssueFinalOutcome)
        # throws before a genuine final outcome exists. That rollback can
        # itself fail to fully complete (e.g. a locked file); when it does,
        # the cycle's own exception message is prefixed
        # "POST_COMMIT_ROLLBACK_FAILED:" specifically so this harness never
        # claims "nothing published" when that cannot be proven true.
        $rollbackDidNotFullyComplete = [string]$productionAbortMessage -like 'POST_COMMIT_ROLLBACK_FAILED:*'
        Write-Host ""
        Write-Host "============================================" -ForegroundColor Red
        Write-Host " CERTIFICATION PIPELINE ABORTED (infrastructure failure)" -ForegroundColor Red
        Write-Host "============================================" -ForegroundColor Red
        Write-Host (" REASON       : {0}" -f $productionAbortMessage) -ForegroundColor Red
        Write-Host (" STATUS       : NOT DETERMINED -- no certification decision was reached") -ForegroundColor Red
        if ($rollbackDidNotFullyComplete) {
            Write-Host (" PUBLISHED    : UNKNOWN -- publication rollback did not fully complete; a bundle may still be present at {0} and requires manual verification" -f $productionDestinationRoot) -ForegroundColor Red
        } else {
            Write-Host (" PUBLISHED    : false -- no authoritative marker or bundle was written") -ForegroundColor Red
            if(-not[string]::IsNullOrWhiteSpace($script:OperatorStatusPath)){Add-Content -LiteralPath $script:OperatorStatusPath -Value 'FINAL STATUS: PIPELINE ABORTED' -Encoding utf8;Add-Content -LiteralPath $script:OperatorStatusPath -Value ("Reason: {0}" -f (ConvertTo-TPMSafeTechnicalTextV1 -Text $productionAbortMessage)) -Encoding utf8}
        }
        Exit-TPMCertificationRepositoryLockV1 -Lock $certificationRepositoryLock
        exit 1
    }

    # The dispatcher-issued final outcome's runtime projection is the only
    # source of externally visible certification status and exit code.
    # There is no separate legacy FINAL STATUS/OVERALL/ExitCode decision
    # left anywhere in this file.
    $productionProjection = $productionCycleResult.Projection
    $finalColor = if ($productionProjection.FinalStatus -ceq 'CERTIFIED') { 'Green' } else { 'Red' }
    # The publisher commits into DestinationRoot\<RunIdentity>, not
    # DestinationRoot itself -- $productionCycleResult.Commit.DestinationDirectory
    # is the genuine, real on-disk bundle location for a committed
    # publication. When publication did not commit (Committed=$false), no
    # such directory is authoritative, so this displays an explicit
    # "not published" value rather than implying $productionDestinationRoot
    # itself is a report bundle.
    $reportsDisplay = if ($productionCycleResult.Commit.Committed) { $productionCycleResult.Commit.DestinationDirectory } else { '(not published)' }
    Write-Host ""
$finalLine=("FINAL STATUS: {0}" -f $productionProjection.FinalStatus); Write-Host $finalLine -ForegroundColor $finalColor; if(-not[string]::IsNullOrWhiteSpace($script:OperatorStatusPath)){Add-Content -LiteralPath $script:OperatorStatusPath -Value $finalLine -Encoding utf8;Add-Content -LiteralPath $script:OperatorStatusPath -Value ("Total elapsed: {0}" -f $runTimer.Elapsed) -Encoding utf8;Add-Content -LiteralPath $script:OperatorStatusPath -Value ("Report: {0}" -f $reportDir) -Encoding utf8;Add-Content -LiteralPath $script:OperatorStatusPath -Value ("Technical log: {0}" -f (Join-Path $reportDir 'TechnicalLogs')) -Encoding utf8}
    Write-Host (" EXIT CODE    : {0}" -f $productionProjection.ExitCode) -ForegroundColor $finalColor
    Write-Host (" RUN IDENTITY : {0}" -f $productionProjection.RunIdentity) -ForegroundColor $finalColor
    Write-Host (" REPORTS      : {0}" -f $reportsDisplay) -ForegroundColor $finalColor
    Exit-TPMCertificationRepositoryLockV1 -Lock $certificationRepositoryLock
    exit $productionProjection.ExitCode
}
