param(
    [Parameter(Mandatory=$true)]
    [string]$RepoPath,

    [Parameter(Mandatory=$true)]
    [string]$TeknoParrotRoot,

    [string]$HarnessRoot,

    [switch]$RunUnattendedTPM,

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
Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Shadow.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Production.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Orchestration.psm1') -Force

$RepoPath = (Resolve-Path -LiteralPath $RepoPath).Path
if (!(Test-Path -LiteralPath $TeknoParrotRoot -PathType Container)) {
    throw "TeknoParrot root not found: $TeknoParrotRoot"
}
$TeknoParrotRoot = (Resolve-Path -LiteralPath $TeknoParrotRoot).Path

if ([string]::IsNullOrWhiteSpace($HarnessRoot)) {
    $repoParent = Split-Path -Parent $RepoPath
    $HarnessRoot = Join-Path $repoParent "TPM-TestHarness"
}

$stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportDir = Join-Path $HarnessRoot "Reports\$stamp"
$backupDir = Join-Path $HarnessRoot "Backups\$stamp"
New-Item -ItemType Directory -Force -Path $reportDir, $backupDir | Out-Null

$md = Join-Path $reportDir "TPM-Validation-Report.md"
$json = Join-Path $reportDir "TPM-Validation-Report.json"
$certificationMd = Join-Path $reportDir "TPM-Certification-Scorecard.md"
$certificationJson = Join-Path $reportDir "TPM-Certification-Scorecard.json"
# Issue #151: certification evidence screenshots. Beneath $reportDir, not a
# separate top-level folder -- keeps every artifact for one certification
# run (reports, Pester output, screenshots) under the same timestamped
# directory. Created lazily by New-TPMCertificationScreenshot itself, not
# here, so "screenshot directory creation" is covered by that function's
# own regression tests rather than assumed to already exist.
$screenshotDir = Join-Path $reportDir "Screenshots"

$script:tpmValidationReportLines = New-Object System.Collections.Generic.List[string]
$script:tpmCertificationReportLines = New-Object System.Collections.Generic.List[string]

function Add-Report {
    param([string]$Text)
    $script:tpmValidationReportLines.Add($Text)
}

function Add-CertificationReport {
    param([string]$Text)
    $script:tpmCertificationReportLines.Add($Text)
}

function Publish-TPMCertificationArtifacts {
    param([object[]]$Artifacts)

    if (@($Artifacts).Count -lt 1) {
        throw 'no authoritative artifacts supplied'
    }

    $encoding = New-Object System.Text.UTF8Encoding($false)
    $staged = New-Object System.Collections.Generic.List[object]
    $destinations = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    try {
        foreach ($artifact in $Artifacts) {
            if ($null -eq $artifact -or [string]::IsNullOrWhiteSpace([string]$artifact.Path)) {
                throw 'authoritative artifact has no destination path'
            }
            $destination = [System.IO.Path]::GetFullPath([string]$artifact.Path)
            if (-not $destinations.Add($destination)) {
                throw "duplicate authoritative artifact destination: $destination"
            }
            if (Test-Path -LiteralPath $destination) {
                throw "authoritative artifact destination already exists: $destination"
            }
            $parent = [System.IO.Path]::GetDirectoryName($destination)
            if ([string]::IsNullOrWhiteSpace($parent) -or -not (Test-Path -LiteralPath $parent -PathType Container)) {
                throw "authoritative artifact parent does not exist: $parent"
            }
        }
        foreach ($artifact in $Artifacts) {
            $destination = [System.IO.Path]::GetFullPath([string]$artifact.Path)
            $parent = [System.IO.Path]::GetDirectoryName($destination)
            $pending = Join-Path $parent ('.' + [System.IO.Path]::GetFileName($destination) + '.' + [guid]::NewGuid().ToString('N') + '.pending')
            [System.IO.File]::WriteAllText($pending, [string]$artifact.Content, $encoding)
            if (-not (Test-Path -LiteralPath $pending -PathType Leaf) -or (Get-Item -LiteralPath $pending).Length -le 0) {
                throw "authoritative artifact staging failed: $destination"
            }
            $staged.Add([pscustomobject]@{ Pending=$pending; Final=$destination; Promoted=$false; Content=[string]$artifact.Content })
        }
        # System Invariant Inventory: durable complete-set verification and a
        # real commit boundary. The last staged artifact is treated as the
        # commit marker (Test-TPMArtifactManifest requires it and the
        # -BuildArtifacts callback always appends it last): every other
        # artifact is promoted and durably re-read back from disk first, and
        # only once every one of them is confirmed to match what was staged
        # is the marker itself promoted and verified. A concurrent reader,
        # or a process that resumes after this run was interrupted, should
        # treat the marker's absence as "not committed" regardless of what
        # report files it can already see on disk -- partial output is never
        # authoritative.
        $markerIndex = $staged.Count - 1
        $nonMarker = $staged.GetRange(0, $markerIndex)
        $marker = $staged[$markerIndex]
        foreach ($item in $nonMarker) {
            Move-Item -LiteralPath $item.Pending -Destination $item.Final -ErrorAction Stop
            $item.Promoted = $true
        }
        foreach ($item in $nonMarker) {
            $onDisk = [System.IO.File]::ReadAllText($item.Final, $encoding)
            if ($onDisk -cne $item.Content) {
                throw "authoritative artifact durable verification failed (on-disk content does not match staged content): $($item.Final)"
            }
        }
        Move-Item -LiteralPath $marker.Pending -Destination $marker.Final -ErrorAction Stop
        $marker.Promoted = $true
        $markerOnDisk = [System.IO.File]::ReadAllText($marker.Final, $encoding)
        if ($markerOnDisk -cne $marker.Content) {
            throw "authoritative commit marker durable verification failed: $($marker.Final)"
        }
    } catch {
        $failure = $_.Exception.Message
        $cleanupErrors = New-Object System.Collections.Generic.List[string]
        foreach ($item in $staged) {
            foreach ($path in @($item.Pending, $(if ($item.Promoted) { $item.Final } else { $null }))) {
                if (-not [string]::IsNullOrWhiteSpace([string]$path) -and (Test-Path -LiteralPath $path)) {
                    try { Remove-Item -LiteralPath $path -Force -ErrorAction Stop }
                    catch { $cleanupErrors.Add("$path -- $($_.Exception.Message)") }
                }
            }
        }
        if ($cleanupErrors.Count -gt 0) {
            throw "certification artifact publication failed: $failure; partial-artifact cleanup also failed: $($cleanupErrors -join '; ')"
        }
        throw "certification artifact publication failed; no authoritative reports were retained: $failure"
    }
}

function Copy-IfExists {
    param([string]$Path, [string]$DestName)
    if (Test-Path -LiteralPath $Path) {
        Copy-Item -LiteralPath $Path -Destination (Join-Path $backupDir $DestName) -Recurse -Force
        return $true
    }
    return $false
}

function Get-TreeHash {
    # Issue #172: must always return a genuine array, never bare $null.
    # PowerShell collapses a zero-object pipeline/return to $null at the
    # caller (a nonexistent path, or an existing-but-empty directory, both
    # produce zero output objects) -- Compare-TreeSnapshot's own @($Before)
    # wrapping then turns that $null into a one-element array containing a
    # single $null, miscounted as one unreadable file. Collecting into an
    # explicit list and returning it with the unary comma operator (,) below
    # forces the array itself through as one object, never enumerated onto
    # the pipeline and never collapsed, regardless of element count -- 0, 1,
    # or many.
    param([string]$Path)
    $results = New-Object Collections.Generic.List[object]
    if (Test-Path -LiteralPath $Path) {
        $resolved = (Resolve-Path -LiteralPath $Path).Path
        $base = $resolved.TrimEnd('\')
        foreach ($file in @(Get-ChildItem -LiteralPath $resolved -Recurse -File -ErrorAction SilentlyContinue | Sort-Object FullName)) {
            $relative = $file.FullName
            if ($file.FullName.Length -gt $base.Length) {
                $relative = $file.FullName.Substring($base.Length).TrimStart('\')
            }
            if ([string]::IsNullOrWhiteSpace($relative)) {
                $relative = $file.Name
            }
            try {
                $h = Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop
                $results.Add([pscustomobject]@{
                    RelativePath = $relative
                    Path = $file.FullName
                    Hash = $h.Hash
                    Length = $file.Length
                })
            } catch {
                # A file that exists but genuinely cannot be hashed (locked,
                # access denied, disappeared mid-enumeration) is a real
                # unreadable entry -- represented explicitly with a null
                # RelativePath so Compare-TreeSnapshot's existing skip
                # detection counts it correctly, rather than letting the
                # exception propagate under this script's global
                # $ErrorActionPreference = "Stop" and abort the whole run.
                $results.Add([pscustomobject]@{
                    RelativePath = $null
                    Path = $file.FullName
                    Hash = $null
                    Length = $null
                })
            }
        }
    }
    return ,$results.ToArray()
}

function Compare-TreeSnapshot {
    # Issue #172: defensively normalize a bare $null to a true empty array
    # here too, not just at Get-TreeHash's boundary -- [object[]] parameter
    # typing does not coerce $null to @() on its own (confirmed empirically),
    # so @($Before) on a $null argument would otherwise produce the same
    # phantom one-null-element array this function exists to count
    # correctly for genuine unreadable entries.
    param([object[]]$Before, [object[]]$After)
    if ($null -eq $Before) { $Before = @() }
    if ($null -eq $After) { $After = @() }
    $beforeMap = @{}
    $beforeSkipped = 0
    foreach ($item in @($Before)) {
        if (-not $item -or [string]::IsNullOrWhiteSpace([string]$item.RelativePath)) { $beforeSkipped++; continue }
        $beforeMap[[string]$item.RelativePath] = $item.Hash
    }
    $afterMap = @{}
    $afterSkipped = 0
    foreach ($item in @($After)) {
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
        BeforeCount = @($Before).Count
        AfterCount = @($After).Count
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
    param([string]$ConfigPath, [string]$TeknoParrotRoot)
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { return $false }
    $raw = Get-Content -LiteralPath $ConfigPath -Raw
    $cfg = $raw | ConvertFrom-Json
    $cfg.TeknoParrotRoot = $TeknoParrotRoot
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
    param([string]$ConfigPath, [string]$TeknoParrotRoot)
    $cfg = [ordered]@{
        TeknoParrotRoot    = $TeknoParrotRoot
        GamesInstallFolder = $TeknoParrotRoot
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

    $checks = @($HealthResult.Checks)
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

# System Invariant Inventory: authoritative evidence issuance ledger. This is
# the workflow's own private record of what it actually issued, populated
# only by Add-Screenshot in real append order -- not the public
# $results.Screenshots array, which anything in this script's scope could in
# principle splice a fabricated record into. Complete-TPMCertificationTransaction
# validates the submitted evidence (the public array a caller passes in)
# against this ledger by reference identity, not by re-checking field
# values: constructing a brand-new object with every field copied from a
# real record -- WorkflowId, Sequence, Path, whatever -- still produces a
# different object, and [object]::ReferenceEquals against this ledger's
# entries is false for it. Ordering is likewise never trusted off a mutable
# Sequence property read back from an object; it is derived from the
# record's actual position in this list.
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

# System Invariant Inventory: authoritative score-item manifest. The exact,
# closed set of certification score-item identifiers this harness is allowed
# to score against. Complete-TPMCertificationTransaction validates
# $Certification.Items against this manifest before it is ever handed to
# Get-TPMCertificationScoreFromItems, so a synthetic, partial, duplicated, or
# malformed Items array -- including a hand-built single-item "100% passing"
# scorecard -- is rejected before it can influence the score at all. Defined
# as a function returning a fresh manifest each call (not a top-level
# script-scope assignment) -- this repo's Pester harness extracts and
# dot-sources only function definitions from this file (see
# Tests/TPMCertificationHarness.Tests.ps1's header comment), so a bare
# top-level statement would silently never execute under test.
function Get-TPMExpectedScoreItemManifest {
    [ordered]@{
        'Repository' = [pscustomobject]@{ AllowsNotApplicable = $false }
        'Pester' = [pscustomobject]@{ AllowsNotApplicable = $false }
        'Static Analysis' = [pscustomobject]@{ AllowsNotApplicable = $false }
        'Real Install Health' = [pscustomobject]@{ AllowsNotApplicable = $false }
        'Backups' = [pscustomobject]@{ AllowsNotApplicable = $false }
        'Smoke File Safety' = [pscustomobject]@{ AllowsNotApplicable = $true }
        'Artifacts' = [pscustomobject]@{ AllowsNotApplicable = $false }
        'pcsx2x6 crosshair path (issue #79)' = [pscustomobject]@{ AllowsNotApplicable = $false }
        'Behavioral Certification (Virtual Beta Tester)' = [pscustomobject]@{ AllowsNotApplicable = $false }
        'Unattended TPM root binding' = [pscustomobject]@{ AllowsNotApplicable = $false }
        'Unattended TPM config restoration' = [pscustomobject]@{ AllowsNotApplicable = $true }
    }
}

function Test-TPMScoreItemManifest {
    param([object[]]$Items)
    $errors = New-Object System.Collections.Generic.List[string]
    $items = @($Items)
    $expectedScoreItems = Get-TPMExpectedScoreItemManifest

    foreach ($expectedArea in $expectedScoreItems.Keys) {
        $itemsForArea = @($items | Where-Object { $_ -and (@($_.PSObject.Properties.Name) -contains 'Area') -and [string]$_.Area -ceq $expectedArea })
        if ($itemsForArea.Count -ne 1) {
            $errors.Add("expected exactly one '$expectedArea' score item; found $($itemsForArea.Count)")
        }
    }

    foreach ($item in $items) {
        if ($null -eq $item) { $errors.Add('null score item is not permitted'); continue }
        $properties = @($item.PSObject.Properties.Name)
        if ($properties -notcontains 'Area' -or [string]::IsNullOrWhiteSpace([string]$item.Area)) {
            $errors.Add('score item has no valid Area')
            continue
        }
        $area = [string]$item.Area
        if (@($expectedScoreItems.Keys) -cnotcontains $area) {
            $errors.Add("unexpected score item '$area'")
            continue
        }
        $expected = $expectedScoreItems[$area]
        $hasStatus = ($properties -contains 'Status')
        $status = if ($hasStatus) { [string]$item.Status } else { $null }
        if ($hasStatus -and $status -ceq 'NotApplicable') {
            if (-not $expected.AllowsNotApplicable) {
                $errors.Add("score item '$area' is not permitted to be NotApplicable")
            }
            if ($properties -notcontains 'Passed' -or $null -ne $item.Passed) {
                $errors.Add("score item '$area' is NotApplicable but Passed is not `$null")
            }
        } else {
            if ($properties -notcontains 'Passed' -or $item.Passed -isnot [bool]) {
                $errors.Add("score item '$area' has a missing or non-Boolean Passed value")
            }
        }
    }

    [pscustomobject]@{
        Valid = ($errors.Count -eq 0)
        Details = $(if ($errors.Count -eq 0) { 'score-item manifest validated' } else { $errors -join '; ' })
    }
}

# System Invariant Inventory: authoritative publication artifact manifest.
# The exact, closed set of report identities a certification run must
# publish -- four human/machine-readable reports plus the commit marker
# (see Publish-TPMCertificationArtifacts). -BuildArtifacts is required to
# tag each artifact it returns with one of these Ids; an arbitrary,
# incomplete, duplicated, or wrongly-destined artifact set is rejected
# before Publish-TPMCertificationArtifacts ever touches disk. Defined as a
# function for the same reason as Get-TPMExpectedScoreItemManifest above --
# a bare top-level assignment is invisible to the AST-extraction test
# harness.
function Get-TPMExpectedArtifactManifest {
    [ordered]@{
        'CertificationScorecardJson' = $true
        'ValidationReportJson' = $true
        'CertificationScorecardMarkdown' = $true
        'ValidationReportMarkdown' = $true
        'CommitMarker' = $true
    }
}

function Test-TPMArtifactManifest {
    param([object[]]$Artifacts, [string]$ReportDir)
    $errors = New-Object System.Collections.Generic.List[string]
    $artifacts = @($Artifacts)
    $expectedArtifacts = Get-TPMExpectedArtifactManifest
    $reportDirFull = [System.IO.Path]::GetFullPath($ReportDir)
    $seenIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $seenPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($artifact in $artifacts) {
        if ($null -eq $artifact) { $errors.Add('null artifact is not permitted'); continue }
        $properties = @($artifact.PSObject.Properties.Name)
        if ($properties -notcontains 'Id' -or [string]::IsNullOrWhiteSpace([string]$artifact.Id)) {
            $errors.Add('artifact has no valid Id')
            continue
        }
        $id = [string]$artifact.Id
        if (@($expectedArtifacts.Keys) -cnotcontains $id) {
            $errors.Add("unexpected artifact identity '$id'")
            continue
        }
        if (-not $seenIds.Add($id)) {
            $errors.Add("duplicate artifact identity '$id'")
            continue
        }
        if ($properties -notcontains 'Path' -or [string]::IsNullOrWhiteSpace([string]$artifact.Path)) {
            $errors.Add("artifact '$id' has no destination path")
            continue
        }
        $fullPath = [System.IO.Path]::GetFullPath([string]$artifact.Path)
        if (-not $fullPath.StartsWith($reportDirFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            $errors.Add("artifact '$id' destination is not contained within this run's report directory: $($artifact.Path)")
            continue
        }
        if (-not $seenPaths.Add($fullPath)) {
            $errors.Add("artifact '$id' reuses a destination already claimed by another artifact: $($artifact.Path)")
            continue
        }
        if ($properties -notcontains 'Content' -or $null -eq $artifact.Content) {
            $errors.Add("artifact '$id' has no content")
        }
    }

    foreach ($expectedId in $expectedArtifacts.Keys) {
        if (-not $seenIds.Contains($expectedId)) {
            $errors.Add("expected artifact identity '$expectedId' was not produced")
        }
    }

    [pscustomobject]@{
        Valid = ($errors.Count -eq 0)
        Details = $(if ($errors.Count -eq 0) { 'artifact manifest validated' } else { $errors -join '; ' })
    }
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

# Real capture action for an on-screen console moment (certification suite
# running, final result, requested/effective root evidence) -- grabs the
# certification console's own window when Get-TPMConsoleWindowRect can
# resolve it (CaptureScope = 'Window'); falls back to the full virtual
# screen, explicitly classified as such, only when it cannot (CaptureScope
# = 'FullDesktop'). Returns the scope string so New-TPMCertificationScreenshot
# can record which one actually happened -- never silently reported as a
# narrow capture when it was not. Never called from tests; production-only,
# since it requires a live display session this harness's own CI run does
# not have.
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

# System Invariant Inventory: derived scorecard state. Overall/Passed/Total/
# ScorePercent are always computed from $Items by this single pure function --
# nothing that needs the true score ever reads a precomputed field off the
# scorecard object instead. This exists specifically so
# Complete-TPMCertificationTransaction can derive its own scoring decision
# from $Certification.Items at commit time rather than trusting
# $Certification.Overall, a mutable field nothing prevents another code path
# from setting stale: the same arithmetic can never diverge between the
# provisional scorecard display and the final commit decision, because both
# call this and only this.
function Get-TPMCertificationScoreFromItems {
    param([object[]]$Items)
    $applicableItems = @($Items | Where-Object { -not ($_.PSObject.Properties.Name -contains 'Status' -and $_.Status -eq 'NotApplicable') })
    $passedCount = @($applicableItems | Where-Object { $_.Passed }).Count
    $totalCount = @($applicableItems).Count
    $overall = if ($totalCount -gt 0 -and $passedCount -eq $totalCount) { 'CERTIFIED' } else { 'NOT CERTIFIED' }
    [pscustomobject]@{
        Overall = $overall
        Passed = $passedCount
        Total = $totalCount
        ScorePercent = if ($totalCount -gt 0) { [math]::Round(($passedCount / [double]$totalCount) * 100, 2) } else { 0 }
    }
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
        [pscustomobject]@{Area='Artifacts'; Passed=((Test-Path -LiteralPath $json -PathType Leaf) -and (Test-Path -LiteralPath $md -PathType Leaf)); Details=$reportDir},
        [pscustomobject]@{Area='pcsx2x6 crosshair path (issue #79)'; Passed=[bool]$checkMap['pcsx2x6 crosshair path (issue #79)']; Details=$pcsx2x6Details},
        [pscustomobject]@{Area='Behavioral Certification (Virtual Beta Tester)'; Passed=($Results.VirtualBetaTester -and $Results.VirtualBetaTester.Total -gt 0 -and $Results.VirtualBetaTester.Failed -eq 0); Details=$vbtDetails},
        [pscustomobject]@{Area='Unattended TPM root binding'; Passed=$unattendedRootPassed; Details=$unattendedRootDetails},
        [pscustomobject]@{Area='Unattended TPM config restoration'; Passed=$restorePassed; Status=$restoreStatus; Details=$restoreDetails}
    )

    # Issue #146 review round 4: N/A items (currently only the restoration
    # item in smoke mode) are excluded from both sides of the score --
    # they must not increase or decrease it, and must never by themselves
    # force NOT CERTIFIED. Items without a Status property (every other
    # score item) are unaffected -- this filter only ever excludes an item
    # that explicitly opted in with Status = 'NotApplicable'.
    $score = Get-TPMCertificationScoreFromItems -Items $scoreItems

    [pscustomobject]@{
        Timestamp = $Results.Timestamp
        Overall = $score.Overall
        Passed = $score.Passed
        Total = $score.Total
        ScorePercent = $score.ScorePercent
        Items = $scoreItems
        ReportDir = $reportDir
        ValidationReport = $md
        ValidationJson = $json
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
    # evidence eligibility is enforced by Complete-TPMCertificationTransaction.
    # A perfect numeric score therefore cannot certify an incomplete run.
    Screenshots = @()
    EvidenceWorkflowId = $script:tpmEvidenceWorkflowId
    PreliminaryStatus = 'RUNNING'
}

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

    # Sequence remains an informational/reporting field only -- it is never
    # what Complete-TPMCertificationTransaction trusts for ordering (that is
    # derived from the ledger's own append order, immune to a property being
    # mutated on an already-issued object).
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

function Complete-TPMCertificationTransaction {
    param(
        $Certification,
        $Results,
        [Parameter(Mandatory=$true)][scriptblock]$BuildArtifacts,
        [Parameter(Mandatory=$true)][string]$ScreenshotDir,
        [Parameter(Mandatory=$true)][string]$ReportDir
    )

    # System Invariant Inventory: this manifest is the authoritative production
    # evidence contract. Every expected identifier occurs exactly once; no
    # unrelated record can substitute for a missing required artifact.
    $expectedEvidence = [ordered]@{
        'certification-suite-running' = [pscustomobject]@{ Required=$true; EvidenceType='ScreenCapture' }
        'requested-effective-root-evidence' = [pscustomobject]@{ Required=$true; EvidenceType='ScreenCapture' }
        'live-thumbnail-evidence' = [pscustomobject]@{ Required=$false; EvidenceType='Skipped' }
        'live-controls-evidence' = [pscustomobject]@{ Required=$false; EvidenceType='Skipped' }
        'adaptive-menu-normal' = [pscustomobject]@{ Required=$true; EvidenceType='DeterministicRender' }
        'adaptive-menu-small' = [pscustomobject]@{ Required=$true; EvidenceType='DeterministicRender' }
        'adaptive-menu-maximized' = [pscustomobject]@{ Required=$true; EvidenceType='DeterministicRender' }
        'smoke-file-safety-evidence' = [pscustomobject]@{ Required=$true; EvidenceType='DeterministicRender' }
        'final-certification-result' = [pscustomobject]@{ Required=$true; EvidenceType='ScreenCapture' }
    }
    $errors = New-Object System.Collections.Generic.List[string]
    # .ToArray(), not @(...) -- wrapping a List[object] directly in @(...)
    # hits a PowerShell dynamic-binder edge case (PSEnumerableBinder /
    # PSToObjectArrayBinder) that throws "Argument types do not match" for
    # this exact generic-collection shape. Confirmed by direct repro before
    # this fix; .ToArray() sidesteps the dynamic binder entirely.
    $ledger = $script:tpmEvidenceLedger.ToArray()
    $submitted = @($Results.Screenshots)
    $workflowId = [string]$Results.EvidenceWorkflowId

    if ([string]::IsNullOrWhiteSpace($workflowId) -or $workflowId -cne $script:tpmEvidenceWorkflowId) {
        $errors.Add('certification evidence workflow identity is missing or does not match the active workflow')
    }

    # System Invariant Inventory: unforgeable in-process record association.
    # The submitted evidence (whatever a caller passes as $Results.Screenshots)
    # is validated against the workflow's own private issuance ledger by
    # reference identity, position for position -- not by re-checking field
    # values. A completely synthetic record, or a real record's fields
    # copied onto a new object, is never [object]::ReferenceEquals to what
    # the ledger actually holds, so it fails here regardless of how
    # convincing its Name/WorkflowId/Sequence/Path look.
    if ($submitted.Count -ne $ledger.Count) {
        $errors.Add("submitted evidence count ($($submitted.Count)) does not match the workflow's issued evidence ledger ($($ledger.Count))")
    } else {
        for ($i = 0; $i -lt $ledger.Count; $i++) {
            if (-not [object]::ReferenceEquals($submitted[$i], $ledger[$i])) {
                $errors.Add("submitted evidence at position $i is not the object the workflow actually issued at that position")
            }
        }
    }

    # System Invariant Inventory: final record genuinely issued last. The
    # ledger seals itself the instant final-certification-result is issued
    # (Add-Screenshot), so nothing can have been appended after it -- this
    # merely confirms that actually happened this run (it is possible for
    # the ledger to be empty or unsealed if the run never reached
    # finalization at all).
    if ($ledger.Count -eq 0 -or -not $script:tpmEvidenceLedgerSealed) {
        $errors.Add('certification evidence ledger was never sealed by a final-certification-result issuance')
    } elseif ([string]$ledger[$ledger.Count - 1].Name -cne 'final-certification-result') {
        $errors.Add('the last evidence issued by the workflow was not final-certification-result')
    }

    foreach ($expectedName in $expectedEvidence.Keys) {
        $recordsForName = @($ledger | Where-Object { $_.Name -ceq $expectedName })
        if ($recordsForName.Count -ne 1) {
            $errors.Add("expected exactly one '$expectedName' evidence record; found $($recordsForName.Count)")
        }
    }

    $screenshotDirFull = [System.IO.Path]::GetFullPath($ScreenshotDir)
    $seenPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($shot in $ledger) {
        if ($null -eq $shot) {
            $errors.Add('null evidence record is not permitted')
            continue
        }
        $properties = @($shot.PSObject.Properties.Name)
        if ($properties -notcontains 'Name' -or [string]::IsNullOrWhiteSpace([string]$shot.Name)) {
            $errors.Add('evidence record has no valid Name')
            continue
        }
        $name = [string]$shot.Name
        if (@($expectedEvidence.Keys) -cnotcontains $name) {
            $errors.Add("unexpected evidence record '$name'")
            continue
        }
        $expected = $expectedEvidence[$name]
        if ($properties -notcontains 'WorkflowId' -or [string]::IsNullOrWhiteSpace([string]$shot.WorkflowId) -or
            [string]$shot.WorkflowId -cne $workflowId) {
            $errors.Add("evidence '$name' did not originate from this certification evidence workflow")
            continue
        }
        if ($properties -notcontains 'Required' -or $shot.Required -isnot [bool] -or $shot.Required -ne $expected.Required) {
            $errors.Add("evidence '$name' has invalid Required metadata")
            continue
        }
        # System Invariant Inventory: identifier-to-label consistency and
        # path ownership/uniqueness/containment/identifier-to-filename
        # consistency, re-verified here against the ledger's own copy of
        # each field (not the caller's), even though Add-Screenshot already
        # enforces path containment and uniqueness at issuance time.
        if ($properties -notcontains 'Label' -or [string]$shot.Label -cne $name) {
            $errors.Add("evidence '$name' has a Label that does not match its identifier")
            continue
        }
        if ($shot.Path) {
            $shotFullPath = [System.IO.Path]::GetFullPath([string]$shot.Path)
            if (-not $shotFullPath.StartsWith($screenshotDirFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                $errors.Add("evidence '$name' path is not contained within this run's screenshot directory: $($shot.Path)")
                continue
            }
            if (-not $seenPaths.Add($shotFullPath)) {
                $errors.Add("evidence '$name' reuses a path already claimed by another ledger record: $($shot.Path)")
                continue
            }
            $safeNamePrefix = ($name -replace '[^A-Za-z0-9_\-]', '-') + '_'
            $fileName = [System.IO.Path]::GetFileName($shotFullPath)
            if (-not $fileName.StartsWith($safeNamePrefix, [System.StringComparison]::Ordinal)) {
                $errors.Add("evidence '$name' filename does not match its issued identifier: $fileName")
                continue
            }
        }
        if ($expected.Required) {
            if ($shot.Status -cne 'Captured') {
                $errors.Add("required evidence '$name' is $($shot.Status): $($shot.Details)")
                continue
            }
            if ([string]$shot.EvidenceType -cne $expected.EvidenceType) {
                $errors.Add("required evidence '$name' has EvidenceType '$($shot.EvidenceType)', expected '$($expected.EvidenceType)'")
                continue
            }
            # System Invariant Inventory: real capture provenance. A required
            # ScreenCapture record must document which capture scope
            # actually produced it (Window or FullDesktop -- see
            # Save-TPMScreenCapture) -- a missing CaptureScope on an
            # otherwise-Captured ScreenCapture record is a sign the evidence
            # did not genuinely come through the real capture path.
            if ($expected.EvidenceType -ceq 'ScreenCapture' -and [string]::IsNullOrWhiteSpace([string]$shot.CaptureScope)) {
                $errors.Add("required evidence '$name' is missing its capture scope")
                continue
            }
            if ([string]::IsNullOrWhiteSpace([string]$shot.Path)) {
                $errors.Add("required evidence '$name' has no file path")
                continue
            }
            try {
                $validation = Test-TPMScreenshotFileValid -Path ([string]$shot.Path)
                if (-not $validation.Valid) {
                    $errors.Add("required evidence '$name' failed final validation: $($validation.Reason)")
                }
            } catch {
                $errors.Add("required evidence '$name' final validation threw: $($_.Exception.Message)")
            }
        } elseif ($shot.Status -cne 'Skipped' -or $shot.EvidenceType -cne 'Skipped' -or $shot.Path) {
            $errors.Add("optional evidence '$name' is not an explicit pathless Skipped record")
        }
    }

    $evidencePassed = ($errors.Count -eq 0)
    $evidenceStatus = [pscustomobject]@{
        Passed = $evidencePassed
        Status = $(if ($evidencePassed) { 'Pass' } else { 'Fail' })
        Details = $(if ($evidencePassed) { 'complete evidence manifest validated against the workflow issuance ledger, including exactly one final-certification-result' } else { $errors -join '; ' })
    }

    # System Invariant Inventory: authoritative score-item manifest, derived
    # scorecard state. $Certification.Items is validated against the exact
    # expected identifier set (Test-TPMScoreItemManifest) before it is ever
    # handed to Get-TPMCertificationScoreFromItems -- a synthetic, partial,
    # or malformed Items array cannot reach the scoring arithmetic at all,
    # let alone be trusted directly the way $Certification.Overall used to be.
    $scoreManifest = Test-TPMScoreItemManifest -Items @($Certification.Items)
    if ($scoreManifest.Valid) {
        $score = Get-TPMCertificationScoreFromItems -Items @($Certification.Items)
        $scoreEligible = ($score.Overall -ceq 'CERTIFIED')
    } else {
        $scoreEligible = $false
    }
    $certified = ($scoreEligible -and $evidencePassed)
    $finalStatus = if ($certified) { 'PASS' } else { 'FAIL' }
    $finalOverall = if ($certified) { 'CERTIFIED' } else { 'NOT CERTIFIED' }
    $exitCode = if ($certified) { 0 } else { 1 }
    $transaction = [pscustomobject]@{
        Passed = $certified
        Status = $finalStatus
        Overall = $finalOverall
        ExitCode = $exitCode
        ScoreEligible = $scoreEligible
        Evidence = $evidenceStatus
        ScoreManifest = $scoreManifest
        Published = $false
        PublicationError = $null
    }

    # A decision snapshot deliberately excludes Published/PublicationError --
    # this is what gets serialized into the certification/validation JSON
    # and Markdown artifacts, and it is generated before publication is even
    # attempted. Whether publication itself will succeed is not a fact this
    # snapshot can know about itself; embedding a Published field here would
    # always read $false (or a value fixed before the real outcome exists)
    # in a report that later gets promoted successfully, which is exactly
    # the stale-serialized-state failure mode this design avoids. The
    # commit marker artifact (see Publish-TPMCertificationArtifacts) is the
    # actual durable proof of a complete publish; its content never needs
    # to describe an outcome that hadn't happened yet when it was written,
    # because a failed publish never leaves it on disk at all.
    $decisionSnapshot = [pscustomobject]@{
        Passed = $certified
        Status = $finalStatus
        Overall = $finalOverall
        ExitCode = $exitCode
        ScoreEligible = $scoreEligible
        Evidence = $evidenceStatus
        ScoreManifest = $scoreManifest
    }

    # This is the only assignment point for final authoritative outcome state.
    $Certification.Overall = $finalOverall
    $Certification.Screenshots = $ledger
    $Certification | Add-Member -NotePropertyName Status -NotePropertyValue $finalStatus -Force
    $Certification | Add-Member -NotePropertyName ExitCode -NotePropertyValue $exitCode -Force
    $Certification | Add-Member -NotePropertyName ScoreEligible -NotePropertyValue $scoreEligible -Force
    $Certification | Add-Member -NotePropertyName EvidenceFinalization -NotePropertyValue $evidenceStatus -Force
    $Certification | Add-Member -NotePropertyName Finalization -NotePropertyValue $decisionSnapshot -Force
    $Results.Status = $finalStatus
    $Results.EvidenceFinalization = $evidenceStatus
    $Results.Finalization = $decisionSnapshot
    $Results.CertificationOverall = $finalOverall
    $Results.ExitCode = $exitCode

    # System Invariant Inventory: mandatory publication commit. -BuildArtifacts
    # is a required parameter (PowerShell parameter binding itself rejects a
    # missing/$null callback before this function body ever runs), and its
    # returned artifact set is validated against the exact expected artifact
    # identity manifest (Test-TPMArtifactManifest) before anything is
    # written to disk. Publish-TPMCertificationArtifacts still performs the
    # actual atomic stage/promote/durably-verify/commit-marker sequence; a
    # failure anywhere in that chain downgrades this same transaction object
    # in place, so there is exactly one authority for the outcome regardless
    # of which half failed.
    try {
        $artifacts = @(& $BuildArtifacts $decisionSnapshot)
        $artifactManifest = Test-TPMArtifactManifest -Artifacts $artifacts -ReportDir $ReportDir
        if (-not $artifactManifest.Valid) {
            throw "authoritative artifact manifest invalid: $($artifactManifest.Details)"
        }
        Publish-TPMCertificationArtifacts -Artifacts $artifacts
        $transaction.Published = $true
    } catch {
        $transaction.Published = $false
        $transaction.PublicationError = $_.Exception.Message
        $transaction.Passed = $false
        $transaction.Status = 'FAIL'
        $transaction.Overall = 'NOT CERTIFIED'
        $transaction.ExitCode = 1
        $Certification.Overall = $transaction.Overall
        $Certification | Add-Member -NotePropertyName Status -NotePropertyValue $transaction.Status -Force
        $Certification | Add-Member -NotePropertyName ExitCode -NotePropertyValue $transaction.ExitCode -Force
        $Results.Status = $transaction.Status
        $Results.CertificationOverall = $transaction.Overall
        $Results.ExitCode = $transaction.ExitCode
    }

    return $transaction
}

function Get-TPMCertificationFinalConsoleLines {
    param($Finalization)
    @(
        "FINAL STATUS : $($Finalization.Status)"
        "OVERALL      : $($Finalization.Overall)"
        "EXIT CODE    : $($Finalization.ExitCode)"
        "EVIDENCE     : $($Finalization.Evidence.Status) -- $($Finalization.Evidence.Details)"
    )
}

function Get-TPMCertificationFinalReportLines {
    param($Finalization)
    @(
        "Status: **$($Finalization.Status)**"
        "Overall: **$($Finalization.Overall)**"
        "Process exit code: $($Finalization.ExitCode)"
        "Evidence finalization: $($Finalization.Evidence.Status) -- $($Finalization.Evidence.Details)"
    )
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
        Write-Progress -Id 42 -Activity 'TPM Certification Suite' -Status $status -PercentComplete 0
    } catch {}
}

function Clear-TPMConsoleStatus {
    try { Write-Progress -Id 42 -Activity 'TPM Certification Suite' -Completed } catch {}
    try { [Console]::Title = 'TeknoParrot Manager Certification Suite' } catch {}
}

function Write-TPMGateHeader {
    param([string]$Gate, [string]$Purpose, [string]$Expected)
    Set-TPMConsoleStatus -Gate $Gate -Purpose $Purpose -Expected $Expected
    Write-Host ""
    Write-Host ("--- Running: {0}" -f $Gate) -ForegroundColor Cyan
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
    $invalidReportLines -join [Environment]::NewLine | Out-File -FilePath $certificationMd -Encoding utf8

    [pscustomobject]@{
        Overall = 'INVALID CERTIFICATION ENVIRONMENT'
        RequestedTeknoParrotRoot = $TeknoParrotRoot
        MissingMarkers = $rootValidation.MissingMarkers
        Timestamp = $stamp
    } | ConvertTo-Json -Depth 4 | Out-File -FilePath $certificationJson -Encoding utf8

    throw $invalidMsg
}

Push-Location $RepoPath
try {
    # Issue #151: first required evidence slot -- captured as early as
    # possible in the real gate flow so the screenshot actually shows the
    # certification suite mid-run, not an empty or pre-launch console.
    [void](Add-Screenshot -ScreenshotDir $screenshotDir -Name 'certification-suite-running' -EvidenceType 'ScreenCapture' -CaptureAction { param($p) Save-TPMScreenCapture -Path $p })

    Write-TPMGateHeader -Gate 'Repository' -Purpose 'Confirms the certified commit and working-tree state' -Expected 'clean working tree, HEAD matches origin/main'
    $gitVersion = git --version
    $gitBranch = git rev-parse --abbrev-ref HEAD
    $gitCommit = git rev-parse HEAD
    $gitCommitShort = git rev-parse --short HEAD
    $gitStatusLines = @(git status --short)
    $repoClean = ($gitStatusLines.Count -eq 0)
    if ($repoClean) {
        $gitStatusText = '(clean)'
    } else {
        $gitStatusText = ($gitStatusLines -join [Environment]::NewLine)
    }

    # Issue #111: origin/main comparison, so a reviewer can tell from the
    # scorecard alone whether this run actually certified the latest pushed
    # commit or a stale/local one. Never blocks the run over a failed
    # fetch (no network is a real, non-fatal scenario) -- says so plainly
    # instead of silently omitting the comparison.
    $originMainCommit = $null
    $fetchFailed = $false
    try {
        git fetch origin main --quiet 2>$null
        if ($LASTEXITCODE -ne 0) { $fetchFailed = $true }
        else { $originMainCommit = (git rev-parse origin/main 2>$null) }
    } catch {
        $fetchFailed = $true
    }
    $syncStatus = if ($fetchFailed -or -not $originMainCommit) {
        'UNKNOWN -- could not fetch origin/main (offline or unreachable)'
    } elseif ($gitCommit -eq $originMainCommit) {
        'MATCHES origin/main'
    } else {
        "DIFFERS from origin/main ($originMainCommit) -- this run may not reflect the latest pushed commit"
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
    $preCrosshairs = if ($crosshairPath) { Get-TreeHash $crosshairPath } else { @() }

    Write-TPMGateHeader -Gate 'Pester regression suite' -Purpose 'Runs every unit/regression test in the repo' -Expected 'zero failed tests'
    $pesterCommand = Get-Command Invoke-Pester -ErrorAction SilentlyContinue
    if (-not $pesterCommand) { throw 'Invoke-Pester not found. Install it with: Install-Module Pester -Scope CurrentUser -Force' }
    $pesterModule = Get-Module Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    if ($pesterModule) { $results.PesterVersion = $pesterModule.Version.ToString() }
    $pesterOutputText = Join-Path $reportDir 'Pester-output.txt'

    # Issue #136: Output.Verbosity 'None' (the previous Summary-mode setting)
    # means Pester emits literally zero per-file/per-test text, to any
    # stream -- there is nothing "quiet capture" could have captured. A real
    # certification timeout came back with "Last known output: (no output
    # captured)" because of this, not a capture-mechanism bug. Verbosity is
    # now always at least 'Detailed' so a hang can always be diagnosed
    # (which file, which Describe block, how many tests completed) -- see
    # the stream choice below for how this stays console-quiet in Summary
    # mode despite that.
    $pesterOutputVerbosity = switch ($VerbosityLevel) {
        'Summary'    { 'Detailed' }
        'Detailed'   { 'Detailed' }
        'Diagnostic' { 'Diagnostic' }
    }
    $pesterConfig = New-PesterConfiguration
    $pesterConfig.Run.Path = $RepoPath
    $pesterConfig.Run.PassThru = $true
    $pesterConfig.Output.Verbosity = $pesterOutputVerbosity

    # Issue #136: runs on a dedicated in-process runspace, not a background
    # Job -- a Job is a separate process, so its PassThru result would cross
    # process boundaries via CliXml serialization, which does not preserve
    # the deep object graph the Virtual Beta Tester reporting below actually
    # reads (.Tests, .Block.Tag, .ScriptBlock.File several levels deep). A
    # same-process runspace keeps $pesterResult a live, fully-populated
    # object while still letting this loop poll for a hang/timeout.
    $pesterProgressText = Join-Path $reportDir 'Pester-progress.txt'
    $pesterHeartbeatIntervalSeconds = 15
    $pesterRunspace = [runspacefactory]::CreateRunspace()
    $pesterRunspace.Open()
    $pesterPs = [powershell]::Create()
    $pesterPs.Runspace = $pesterRunspace
    [void]$pesterPs.AddScript({
        param($Config, $OutputPath)
        Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
        # Issue #136: Pester's own live per-Describe/per-test progress text
        # is written to the Information stream (6), not the Error stream
        # (2) -- confirmed by direct reproduction: with 2>&1, the file stayed
        # completely empty for the whole run and only received the final
        # PassThru result object's default-formatted text dump at the very
        # end (useless during an actual hang, since that end is never
        # reached). With 6>&1, the file receives each line live as Pester
        # writes it. Also confirmed 6>&1 does not additionally echo to the
        # live console (tested in a real foreground session, not just a
        # background job) -- so Summary mode's "keep the console quiet"
        # intent still holds even though Verbosity is no longer 'None'.
        Invoke-Pester -Configuration $Config 6>&1 | Tee-Object -FilePath $OutputPath
    }).AddArgument($pesterConfig).AddArgument($pesterOutputText)

    $pesterStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $pesterAsyncResult = $pesterPs.BeginInvoke()
    $lastHeartbeatSeconds = 0
    $pesterTimedOut = $false
    $pesterResult = $null

    try {
        while (-not $pesterAsyncResult.IsCompleted) {
            Start-Sleep -Milliseconds 500
            $elapsed = $pesterStopwatch.Elapsed.TotalSeconds

            if (Test-TPMPesterHeartbeatDue -ElapsedSeconds $elapsed -LastHeartbeatSeconds $lastHeartbeatSeconds -HeartbeatIntervalSeconds $pesterHeartbeatIntervalSeconds) {
                $lastHeartbeatSeconds = $elapsed
                $lastLine = ''
                try {
                    if (Test-Path -LiteralPath $pesterOutputText) {
                        $lastLine = [string](Get-Content -LiteralPath $pesterOutputText -Tail 1 -ErrorAction SilentlyContinue)
                    }
                } catch {}
                $heartbeatMsg = Get-TPMPesterHeartbeatMessage -ElapsedSeconds $elapsed -LastOutputLine $lastLine
                Write-Host $heartbeatMsg -ForegroundColor DarkGray
                Add-Content -LiteralPath $pesterProgressText -Value ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $heartbeatMsg)
                Set-TPMConsoleStatus -Gate 'Pester regression suite' -Purpose ("Running -- {0:n0}s elapsed" -f $elapsed) -Expected 'zero failed tests'
            }

            if (Test-TPMPesterTimedOut -ElapsedSeconds $elapsed -TimeoutSeconds $PesterRegressionTimeoutSeconds) {
                $pesterTimedOut = $true
                break
            }
        }

        if ($pesterTimedOut) {
            $lastLine = ''
            try {
                if (Test-Path -LiteralPath $pesterOutputText) {
                    $lastLine = ((Get-Content -LiteralPath $pesterOutputText -Tail 5 -ErrorAction SilentlyContinue) -join ' | ')
                }
            } catch {}
            try { $pesterPs.Stop() } catch {}
            $timeoutMsg = Get-TPMPesterTimeoutMessage -ElapsedSeconds $pesterStopwatch.Elapsed.TotalSeconds -TimeoutSeconds $PesterRegressionTimeoutSeconds -LastOutputLine $lastLine -OutputPath $pesterOutputText -ProgressPath $pesterProgressText
            Add-Content -LiteralPath $pesterProgressText -Value ("[{0}] TIMED OUT -- {1}" -f (Get-Date -Format 'HH:mm:ss'), $timeoutMsg)
            $results.Pester = [pscustomobject]@{
                Passed = $null; Failed = $null; Skipped = $null; Inconclusive = $null; NotRun = $null; Total = $null
                Duration = $pesterStopwatch.Elapsed.ToString(); Result = 'TimedOut'
            }
            Add-CheckResult 'Pester tests' $false $timeoutMsg
            throw $timeoutMsg
        }

        # EndInvoke returns a PSDataCollection[PSObject], not a bare array --
        # "-is [array]" is false for it, so Get-PesterSummary and the VBT
        # candidate-selection logic below (which both branch on
        # "-is [array]" to unwrap a single-result collection) would silently
        # treat the wrapper itself as the result object and find none of the
        # expected properties. Confirmed directly: without this @() wrap,
        # every field in $results.Pester comes back $null even on a normal
        # passing run. Wrapping here makes it a real array, matching what a
        # direct (non-runspace) Invoke-Pester call already produced before
        # this fix.
        $pesterResult = @($pesterPs.EndInvoke($pesterAsyncResult))
    } finally {
        try { $pesterPs.Dispose() } catch {}
        try { $pesterRunspace.Close() } catch {}
        try { $pesterRunspace.Dispose() } catch {}
    }

    $pesterSummary = Get-PesterSummary -PesterResult $pesterResult
    $pesterSummary | ConvertTo-Json -Depth 4 | Out-File (Join-Path $reportDir 'Pester-summary.json') -Encoding utf8
    $results.Pester = $pesterSummary
    Add-CheckResult 'Pester tests' ($pesterSummary.Failed -eq 0) "total=$($pesterSummary.Total) passed=$($pesterSummary.Passed) failed=$($pesterSummary.Failed)"

    # Issue #88 Phase 1/1.5: report Behavioral Certification (Virtual Beta
    # Tester) coverage as its own visible line, not folded anonymously into
    # the overall Pester count -- a scorecard reader should be able to see
    # this coverage exists, and its shape by category, without opening
    # individual test files. Derived from the same PassThru result already
    # collected above, filtered to Tests/VirtualBetaTester*.Tests.ps1 by
    # source file, not by name pattern (robust to Describe/It renames).
    $vbtCandidate = $pesterResult
    if ($pesterResult -is [array]) {
        $vbtCandidate = @($pesterResult) | Where-Object {
            $_ -and ($_.PSObject.Properties.Name -contains 'Tests')
        } | Select-Object -Last 1
    }
    $vbtTests = @()
    if ($vbtCandidate -and $vbtCandidate.PSObject.Properties.Name -contains 'Tests') {
        $vbtTests = @($vbtCandidate.Tests | Where-Object {
            $_.ScriptBlock -and $_.ScriptBlock.File -and ([System.IO.Path]::GetFileName($_.ScriptBlock.File) -like 'VirtualBetaTester.*.Tests.ps1')
        })
    }
    $vbtPassed = @($vbtTests | Where-Object { $_.Result -eq 'Passed' }).Count
    $vbtFailed = @($vbtTests | Where-Object { $_.Result -eq 'Failed' }).Count

    # Category breakdown by Describe-block name, not a separate tagging
    # system -- each category below maps to one or more Describe blocks
    # already named distinctly enough to classify by simple keyword match.
    function Get-VbtCategoryCount {
        param($Tests, [string[]]$Keywords)
        return @($Tests | Where-Object {
            $blockName = ($_.Block.Name)
            $matched = $false
            foreach ($kw in $Keywords) { if ($blockName -like "*$kw*") { $matched = $true; break } }
            $matched
        }).Count
    }
    $vbtHumanBehaviors  = Get-VbtCategoryCount -Tests $vbtTests -Keywords @('human workflow', 'main menu', 'decision paths')
    $vbtIdempotency     = Get-VbtCategoryCount -Tests $vbtTests -Keywords @('idempotency', 'repeat-run', 'AutoSync repeat-run', 'preview')
    $vbtRecoveryChecks  = Get-VbtCategoryCount -Tests $vbtTests -Keywords @('backup safety', 'read-only', 'recovery')
    $vbtEnvironmentVars = Get-VbtCategoryCount -Tests $vbtTests -Keywords @('messy environment')

    # Issue #88 phase 1.6: Tester Value Density is recorded as a real Pester
    # tag on each Describe block ('TVD-High'/'TVD-Medium'/'TVD-Low'), not
    # just a code comment, specifically so this count is queryable evidence
    # rather than a guess. Per CONSTITUTION.md ("Tester Value Density"),
    # this is tracked as coverage evidence only -- never converted to a
    # percentage or folded into the Pass/Fail decision for this gate.
    # -Tag on a Describe block lands on the containing Block, not copied down
    # to each individual test's own .Tag (confirmed empty on .Tests[].Tag) --
    # check .Block.Tag instead.
    $vbtHighTvd = @($vbtTests | Where-Object { $_.Block -and $_.Block.Tag -and ($_.Block.Tag -contains 'TVD-High') }).Count

    $results.VirtualBetaTester = [pscustomobject]@{
        Total               = $vbtTests.Count
        Passed              = $vbtPassed
        Failed              = $vbtFailed
        HumanBehaviors      = $vbtHumanBehaviors
        IdempotencyChecks   = $vbtIdempotency
        RecoveryBehaviors   = $vbtRecoveryChecks
        EnvironmentVariations = $vbtEnvironmentVars
        HighTvdBehaviors    = $vbtHighTvd
    }
    Add-CheckResult 'Behavioral Certification (Virtual Beta Tester)' ($vbtTests.Count -gt 0 -and $vbtFailed -eq 0) `
        ("total={0} passed={1} failed={2} | human-behaviors={3} idempotency={4} recovery={5} environment-variations={6} high-tvd-behaviors={7}" -f `
            $vbtTests.Count, $vbtPassed, $vbtFailed, $vbtHumanBehaviors, $vbtIdempotency, $vbtRecoveryChecks, $vbtEnvironmentVars, $vbtHighTvd)

    # Never hidden by -VerbosityLevel Summary: if anything actually failed,
    # print exactly what, regardless of console verbosity. Also persisted to
    # a file, not just printed. Independent of the issue #136 fix to
    # Output.Verbosity/stream capture above (Pester-output.txt now gets live
    # per-test detail at every -VerbosityLevel) -- this file exists because
    # relying on parsing that text would be fragile; $pesterResult.Failed is
    # read directly as an object instead.
    $failuresText = Join-Path $reportDir 'Pester-Failures.txt'
    if ($pesterSummary.Failed -gt 0) {
        Write-Host ""
        Write-Host "Pester failures ($($pesterSummary.Failed)):" -ForegroundColor Red
        $failedTests = @($pesterResult.Failed)
        if ($failedTests.Count -eq 0 -and $pesterResult -is [array]) {
            $failedTests = @($pesterResult | Where-Object { $_.PSObject.Properties.Name -contains 'Failed' } | Select-Object -ExpandProperty Failed)
        }
        $failureLines = @()
        foreach ($failedTest in $failedTests) {
            $testPath = if ($failedTest.PSObject.Properties.Name -contains 'ExpandedPath') { $failedTest.ExpandedPath } else { $failedTest.Name }
            Write-Host "  - $testPath" -ForegroundColor Red
            $failureLines += "- $testPath"
            $errorRecord = $null
            if ($failedTest.PSObject.Properties.Name -contains 'ErrorRecord' -and $failedTest.ErrorRecord) {
                $errorRecord = @($failedTest.ErrorRecord) | Select-Object -First 1
            }
            if ($errorRecord) {
                $failureLines += "    $($errorRecord.ToString())"
            }
        }
        $failureLines | Out-File -FilePath $failuresText -Encoding utf8
    } else {
        "(no failures)" | Out-File -FilePath $failuresText -Encoding utf8
    }

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
            pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Unattended *> $tpmLog
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
    $postCrosshairs = if ($crosshairPath) { Get-TreeHash $crosshairPath } else { @() }
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
                $renderedLines = @(& pwsh -NoProfile -File $debugMenuScript -Width $tierWidth -Height $tierHeight -Render)
                if ($renderedLines.Count -eq 0) { throw "Debug-TPM-MenuLayout.ps1 -Width $tierWidth -Height $tierHeight -Render produced no output" }
                Save-TPMRenderedTextCapture -Path $p -Lines $renderedLines
            })
        }
    }

    $results.PreliminaryStatus = if (@($results.Checks | Where-Object { -not $_.Passed }).Count -eq 0) { 'PASS' } else { 'FAIL' }
}
catch {
    $results.PreliminaryStatus = 'FAIL'
    $results.Error = $_.Exception.Message
    Add-CheckResult 'Unhandled validation error' $false $_.Exception.Message
    throw
}
finally {
    Pop-Location
    $runTimer.Stop()
    $results.Elapsed = $runTimer.Elapsed.ToString()
    $results.PowerShellVersion = $PSVersionTable.PSVersion.ToString()

    # The "Artifacts" gate below checks that both report files exist on
    # disk. $md's real content can't be written until after $certification
    # exists (the validation report shows the certification verdict inline),
    # so without this stub the gate was checking for a file that structurally
    # could not exist yet at this point in execution -- it failed on every
    # run regardless of whether anything was actually wrong. Confirmed via
    # two independent real-instance runs, both showing "[FAIL] Artifacts"
    # with an otherwise fully passing run. Pre-creating an empty $md here
    # (Add-Report below still builds its real content via -Append) makes the
    # existence check honest without changing what it actually verifies.
    if (-not (Test-Path -LiteralPath $md -PathType Leaf)) {
        # New-Item, not Out-File -- a zero-byte file, so the real content
        # Add-Report appends below doesn't end up with a stray leading
        # blank line.
        [void](New-Item -ItemType File -Path $md -Force)
    }
    # Issue #151: same stub-then-real-content split as $md above, extended
    # to $json -- the real, final $results (including the
    # final-certification-result screenshot, captured further down, after
    # the console summary it's evidence of) is written once, at the very
    # end of this finally block, not here. A stub only needs to exist for
    # the Artifacts gate's existence check.
    if (-not (Test-Path -LiteralPath $json -PathType Leaf)) {
        [void](New-Item -ItemType File -Path $json -Force)
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
    Write-Host (" Report  : {0}" -f $certificationMd)
    Write-Host "============================================"
    [void](Add-Screenshot -ScreenshotDir $screenshotDir -Name 'final-certification-result' -EvidenceType 'ScreenCapture' -CaptureAction { param($p) Save-TPMScreenCapture -Path $p })
    # ADR-0155 Phase 2: execute the new authority as a shadow observer only.
    # Its result is written outside the legacy publication directory and is
    # never consulted for score, report, console, status, or exit-code output.
    $shadowDiagnosticDir = Join-Path $HarnessRoot 'ShadowMigration'
    $shadowDiagnosticPath = Join-Path $shadowDiagnosticDir ("{0}.json" -f $stamp)
    try {
        $shadowFacts = New-TPMShadowFactRecordsFromLegacyV1 -Results $results -RepositoryPath $RepoPath -ReportDirectory $reportDir -BackupDirectory $backupDir -HealthResult $healthResult -HealthLoadError $healthLoadError -UnattendedBinding $binding
        $shadowPngValidator = {
            param($Path)
            $valid = Test-TPMScreenshotFileValid -Path $Path
            if (-not $valid.Valid) { return [pscustomobject]@{Valid=$false;Reason=$valid.Reason;Width=0;Height=0} }
            $image = [System.Drawing.Image]::FromFile($Path)
            try { return [pscustomobject]@{Valid=$true;Reason=$valid.Reason;Width=$image.Width;Height=$image.Height} }
            finally { $image.Dispose() }
        }
        [void](Invoke-TPMShadowCertificationV1 -Mode $(if($results.SmokeMode){'Smoke'}else{'Unattended'}) -EvidenceRoot $screenshotDir -FactRecords $shadowFacts -LegacyEvidence $results.Screenshots -LegacyScoreItems $certification.Items -DiagnosticPath $shadowDiagnosticPath -PngValidator $shadowPngValidator)
    } catch {
        # Shadow authority has no production authority in Phase 2. A failure
        # excludes this run from migration evidence but cannot alter legacy
        # certification output. Persist the cause separately and continue.
        if (-not (Test-Path -LiteralPath $shadowDiagnosticDir -PathType Container)) { [void](New-Item -ItemType Directory -Path $shadowDiagnosticDir) }
        $shadowFailure = [ordered]@{SchemaVersion=1;Mode=$(if($results.SmokeMode){'Smoke'}else{'Unattended'});RunIdentity=$null;MigrationEligible=$false;Phase='Failed';SealedRunSha256=$null;Divergences=@([ordered]@{Path='ShadowAdapter';Legacy='completed';Shadow='failed';ComparisonRule='both observation adapters complete'});ErrorCode='SHADOW_ADAPTER_FAILED';ErrorMessage=$_.Exception.Message}
        [System.IO.File]::WriteAllText($shadowDiagnosticPath,($shadowFailure | ConvertTo-Json -Depth 8 -Compress),(New-Object System.Text.UTF8Encoding $false))
    }

    # ADR-0155 Phase 3 (ADR155-0309): execute the real authority. From this
    # point on, $productionResult.Projection -- not legacy $finalization -- is
    # what determines the console FINAL STATUS line and the process exit
    # code below. Legacy scoring, its own console reports, and its own
    # publication (immediately below this block) are unchanged and
    # untouched; only the decision that exits the process moves to this
    # authority, per ADR Section 11's atomic-cutover framing (this is
    # harness wiring only -- legacy removal is a separate, later change).
    # Independent of the Phase 2 shadow block above: this authority does not
    # read $shadowFacts or depend on the shadow try/catch having succeeded.
    # Its bundle publishes under $reportDir\Authoritative\<RunIdentity>\,
    # never inside $reportDir itself, since legacy already owns canonical
    # filenames there (e.g. TPM-Certification-Commit.json) that
    # Publication.psm1's never-overwrite contract would otherwise collide
    # with.
    $productionStagingParentRoot = Join-Path $reportDir 'Authoritative\_staging'
    $productionDestinationRoot = Join-Path $reportDir 'Authoritative'
    $productionDispositionRegistryPath = Join-Path $PSScriptRoot 'InjectionHunterDispositions.psd1'
    try {
        # Real facts, not the Phase 2 shadow placeholder (issue #171): Static
        # Analysis and Artifacts are genuinely observed here (real parser/
        # encoding/InjectionHunter execution, real staging/publisher
        # preflight), not hardcoded not-executed defaults.
        $productionFacts = New-TPMProductionFactRecordsFromLegacyV1 -Results $results -RepositoryPath $RepoPath -ReportDirectory $reportDir -BackupDirectory $backupDir -HealthResult $healthResult -HealthLoadError $healthLoadError -UnattendedBinding $binding -StagingParentRoot $productionStagingParentRoot -DestinationRoot $productionDestinationRoot -DispositionRegistryPath $productionDispositionRegistryPath
        $productionPngValidator = {
            param($Path)
            $valid = Test-TPMScreenshotFileValid -Path $Path
            if (-not $valid.Valid) { return [pscustomobject]@{Valid=$false;Reason=$valid.Reason;Width=0;Height=0} }
            $image = [System.Drawing.Image]::FromFile($Path)
            try { return [pscustomobject]@{Valid=$true;Reason=$valid.Reason;Width=$image.Width;Height=$image.Height} }
            finally { $image.Dispose() }
        }
        $productionResult = Invoke-TPMProductionCertificationV1 -Mode $(if($results.SmokeMode){'Smoke'}else{'Unattended'}) -Facts $productionFacts -EvidenceRoot $screenshotDir -ReportRoot $reportDir -LegacyEvidence $results.Screenshots -StagingParentRoot $productionStagingParentRoot -DestinationRoot $productionDestinationRoot -PngValidator $productionPngValidator
    } catch {
        # The authoritative pipeline could not reach a decision at all. Per
        # ADR Section 11, this is never certifiable and must not fall back to
        # any other decision source -- doing so would reintroduce the "mixed
        # authorities" ambiguity the ADR prohibits. Fail closed: hard NOT
        # CERTIFIED / exit 1, with the cause preserved for diagnosis.
        $productionResult = [pscustomobject]@{
            Projection = [pscustomobject]@{
                RunIdentity = $null
                FinalStatus = 'NOT CERTIFIED'
                ExitCode = 1
                ConsoleMessage = "Certification authority pipeline failed before reaching a decision: $($_.Exception.Message)"
            }
            CommitResult = $null
            Error = $_.Exception.Message
        }
    }

    # System Invariant Inventory: publication as part of commit. Report
    # content depends on the transaction's decision (it renders Finalization
    # into both reports), so it cannot be built before the transaction runs --
    # but it must still be staged and promoted atomically as part of the same
    # commit, not as a separate step the caller can get out of sync with. This
    # scriptblock is handed to Complete-TPMCertificationTransaction, which
    # invokes it with the provisional (pre-publish) decision once evidence and
    # score validation both complete, then publishes whatever it returns
    # itself -- there is no code outside the transaction that also knows how
    # to decide FAIL/NOT CERTIFIED/exit-1 on a publication failure.
    $buildCertificationArtifacts = {
        param($Finalization)

        # $results.Screenshots now includes the final-certification-result
        # entry, and Complete-TPMCertificationTransaction has already
        # refreshed $certification.Screenshots to match (a snapshot array
        # copy taken when New-CertificationScorecard was called above, before
        # that entry existed) -- so both JSON artifacts reflect the complete
        # list, not the incomplete one from before the final screenshot.
        Add-CertificationReport "# TPM Certification Scorecard"
    Add-CertificationReport ""
    foreach ($line in @(Get-TPMCertificationFinalReportLines -Finalization $Finalization)) {
        Add-CertificationReport $line
    }
    Add-CertificationReport ("Score: {0}/{1} ({2}%)" -f $certification.Passed, $certification.Total, $certification.ScorePercent)
    Add-CertificationReport ("Elapsed: {0}" -f $results.Elapsed)
    Add-CertificationReport ""
    Add-CertificationReport "## Certification Target"
    Add-CertificationReport ""
    Add-CertificationReport ("- Repository: {0}" -f $RepoPath)
    Add-CertificationReport ("- Branch: {0}" -f $results.GitBranch)
    Add-CertificationReport ("- Commit: {0} ({1})" -f $results.Commit, $results.CommitShort)
    $originMainText = if ($results.OriginMainCommit) { $results.OriginMainCommit } else { 'unavailable' }
    $workingTreeText = if ($repoClean) { 'clean' } else { 'dirty' }
    Add-CertificationReport ("- Origin/main: {0}" -f $originMainText)
    Add-CertificationReport ("- Sync status: {0}" -f $results.SyncStatus)
    Add-CertificationReport ("- Working tree: {0}" -f $workingTreeText)
    Add-CertificationReport ("- Git version: {0}" -f $results.GitVersion)
    Add-CertificationReport ("- PowerShell version: {0}" -f $results.PowerShellVersion)
    Add-CertificationReport ("- TPM script version: {0}" -f $tpmScriptVersion)
    Add-CertificationReport ("- TPM display version: {0}" -f $tpmDisplayVersion)
    $effectiveRootReportText = Get-TPMEffectiveRootReportText -EffectiveRoot $results.EffectiveTeknoParrotRoot -SmokeMode $results.SmokeMode
    Add-CertificationReport ("- Requested TeknoParrot root: {0}" -f $results.RequestedTeknoParrotRoot)
    Add-CertificationReport ("- Effective TeknoParrot root: {0}" -f $effectiveRootReportText)
    Add-CertificationReport ("- Certified at: {0}" -f $results.Timestamp)
    Add-CertificationReport ""
    Add-CertificationReport "## Gates"
    foreach ($item in $certification.Items) {
        # Issue #146 review round 4 / #151 review round 1: Get-TPMGateMark
        # is the single source of truth for this mark -- the Smoke File
        # Safety evidence screenshot above renders through the exact same
        # function, so the two can never disagree about what a given
        # item's real Status/Passed fields mean.
        $mark = Get-TPMGateMark -Item $item
        Add-CertificationReport ("- [{0}] {1}: {2}" -f $mark, $item.Area, $item.Details)
    }
    Add-CertificationReport ""
    Add-CertificationReport "## Screenshots"
    Add-CertificationReport ""
    # Issue #151 review round 1 (finding #4): standing disclosure,
    # printed whenever at least one ScreenCapture-type entry exists,
    # regardless of whether it actually fell back to a full-desktop
    # capture this run -- a future run's console-window capture could
    # fall back silently otherwise, and a reviewer should not have to
    # infer the risk from an individual entry's CaptureScope.
    if (@($certification.Screenshots | Where-Object { $_.EvidenceType -eq 'ScreenCapture' }).Count -gt 0) {
        Add-CertificationReport "**Disclosure:** entries marked ScreenCapture below capture a real screen region and may include desktop content unrelated to this certification run beyond the certification console itself (see each entry's capture scope: Window = console-only, FullDesktop = full virtual desktop fallback). DeterministicRender entries never capture the screen -- they rasterize only this run's own rendered report/menu text."
        Add-CertificationReport ""
    }
    if (@($certification.Screenshots).Count -eq 0) {
        Add-CertificationReport "(none captured)"
    } else {
        foreach ($shot in $certification.Screenshots) {
            $shotMark = switch ($shot.Status) { 'Captured' { 'SHOT' } 'Skipped' { 'SKIP' } default { 'FAIL' } }
            $shotLocation = if ($shot.Path) { $shot.Path } else { $shot.Details }
            $shotScopeText = if ($shot.CaptureScope) { " scope=$($shot.CaptureScope)" } else { '' }
            Add-CertificationReport ("- [{0}] {1} (type={2}{3}): {4}" -f $shotMark, $shot.Label, $shot.EvidenceType, $shotScopeText, $shotLocation)
        }
    }
    Add-CertificationReport ""
    Add-CertificationReport "## Artifact folder"
    Add-CertificationReport $reportDir

    Add-Report "# TPM Validation Report"
    Add-Report ""
    Add-Report "## Summary"
    Add-Report ""
    foreach ($line in @(Get-TPMCertificationFinalReportLines -Finalization $Finalization)) {
        Add-Report $line
    }
    Add-Report "Elapsed: $($results.Elapsed)"
    Add-Report ("Report folder: {0}" -f $reportDir)
    Add-Report ("Backup folder: {0}" -f $backupDir)
    Add-Report ""
    Add-Report "## Environment"
    Add-Report ""
    Add-Report ("- Repo: {0}" -f $RepoPath)
    Add-Report ("- TeknoParrot root: {0}" -f $TeknoParrotRoot)
    Add-Report "- Branch: $($results.GitBranch)"
    Add-Report "- Commit: $($results.Commit)"
    Add-Report "- Git: $($results.GitVersion)"
    Add-Report "- PowerShell: $($results.PowerShellVersion)"
    Add-Report "- Pester: $($results.PesterVersion)"
    Add-Report "- PSScriptAnalyzer: $($results.PSScriptAnalyzerVersion)"
    Add-Report ""
    Add-Report "## Test Results"
    Add-Report ""
    Add-Report "- Pester total: $($results.Pester.Total)"
    Add-Report "- Pester passed: $($results.Pester.Passed)"
    Add-Report "- Pester failed: $($results.Pester.Failed)"
    Add-Report "- PSScriptAnalyzer findings: $($results.PSScriptAnalyzerFindings)"
    Add-Report ""
    Add-Report "## Checks"
    Add-Report ""
    foreach ($check in $results.Checks) {
        $mark = if ($check.Passed) { 'PASS' } else { 'FAIL' }
        Add-Report ("- [{0}] {1}: {2}" -f $mark, $check.Name, $check.Details)
    }
    Add-Report ""
    Add-Report "## Artifacts"
    Add-Report ""
    Add-Report ("- Certification scorecard: {0}" -f $certificationMd)
    Add-Report ("- Certification JSON: {0}" -f $certificationJson)
    Add-Report ("- JSON report: {0}" -f $json)
    Add-Report ("- Pester summary: {0}" -f (Join-Path $reportDir 'Pester-summary.json'))
    Add-Report ("- Pester output: {0}" -f (Join-Path $reportDir 'Pester-output.txt'))
    Add-Report ("- Pester failures (names + errors): {0}" -f (Join-Path $reportDir 'Pester-Failures.txt'))
    Add-Report ("- PSScriptAnalyzer: {0}" -f (Join-Path $reportDir 'PSScriptAnalyzer.json'))
    if ($results.InstallHealthReport) {
        Add-Report ("- Install health: {0}" -f $results.InstallHealthReport)
    }
    Add-Report ""
    Add-Report "## Screenshots"
    Add-Report ""
    if (@($results.Screenshots | Where-Object { $_.EvidenceType -eq 'ScreenCapture' }).Count -gt 0) {
        Add-Report "**Disclosure:** entries marked ScreenCapture below capture a real screen region and may include desktop content unrelated to this certification run beyond the certification console itself (see each entry's capture scope: Window = console-only, FullDesktop = full virtual desktop fallback). DeterministicRender entries never capture the screen -- they rasterize only this run's own rendered report/menu text."
        Add-Report ""
    }
    if (@($results.Screenshots).Count -eq 0) {
        Add-Report "(none captured)"
    } else {
        foreach ($shot in $results.Screenshots) {
            $shotMark = switch ($shot.Status) { 'Captured' { 'SHOT' } 'Skipped' { 'SKIP' } default { 'FAIL' } }
            $shotLocation = if ($shot.Path) { $shot.Path } else { $shot.Details }
            $shotScopeText = if ($shot.CaptureScope) { " scope=$($shot.CaptureScope)" } else { '' }
            Add-Report ("- [{0}] {1} (type={2}{3}): {4}" -f $shotMark, $shot.Label, $shot.EvidenceType, $shotScopeText, $shotLocation)
        }
    }

        $newline = [Environment]::NewLine
        # The commit marker is always last -- Publish-TPMCertificationArtifacts
        # treats the final array entry as the marker and only promotes it
        # after every other artifact is durably verified on disk. Its
        # content is static (never references Finalization), since a failed
        # publish never leaves it on disk at all: the marker's mere presence
        # is the proof, not anything it says about itself.
        $commitMarkerPath = Join-Path $reportDir 'TPM-Certification-Commit.json'
        @(
            [pscustomobject]@{Id='CertificationScorecardJson';Path=$certificationJson;Content=($certification | ConvertTo-Json -Depth 8)}
            [pscustomobject]@{Id='ValidationReportJson';Path=$json;Content=($results | ConvertTo-Json -Depth 8)}
            [pscustomobject]@{Id='CertificationScorecardMarkdown';Path=$certificationMd;Content=(($script:tpmCertificationReportLines -join $newline) + $newline)}
            [pscustomobject]@{Id='ValidationReportMarkdown';Path=$md;Content=(($script:tpmValidationReportLines -join $newline) + $newline)}
            [pscustomobject]@{Id='CommitMarker';Path=$commitMarkerPath;Content=(('{"schemaVersion":1,"committed":true,"artifactCount":5}') + $newline)}
        )
    }

    $finalization = Complete-TPMCertificationTransaction -Certification $certification -Results $results -BuildArtifacts $buildCertificationArtifacts -ScreenshotDir $screenshotDir -ReportDir $reportDir
    Clear-TPMConsoleStatus

    if (-not $finalization.Published) {
        Write-Host (" FINAL STATUS : FAIL") -ForegroundColor Red
        Write-Host (" OVERALL      : NOT CERTIFIED") -ForegroundColor Red
        Write-Host (" EXIT CODE    : 1") -ForegroundColor Red
        Write-Host (" REPORTS      : {0}" -f $finalization.PublicationError) -ForegroundColor Red
    } else {
        $finalColor = if ($finalization.Passed) { 'Green' } else { 'Red' }
        foreach ($line in @(Get-TPMCertificationFinalConsoleLines -Finalization $finalization)) {
            Write-Host (" {0}" -f $line) -ForegroundColor $finalColor
        }
    }

    # ADR-0155 Phase 3 (ADR155-0309): the process exit code and the
    # authoritative FINAL STATUS line derive from $productionResult.Projection
    # (Section 9's runtime TPMFinalOutcomeV1), not from legacy $finalization
    # above -- legacy's own PASS/FAIL/CERTIFIED lines printed above remain
    # informational only. This is the harness-wiring half of the atomic
    # cutover; legacy's own decision computation and publication are
    # otherwise untouched and continue to run exactly as before.
    $authoritativeColor = if ($productionResult.Projection.FinalStatus -eq 'CERTIFIED') { 'Green' } else { 'Red' }
    Write-Host ""
    Write-Host " ============================================" -ForegroundColor $authoritativeColor
    Write-Host " AUTHORITATIVE CERTIFICATION RESULT (ADR-0155)" -ForegroundColor $authoritativeColor
    Write-Host " ============================================" -ForegroundColor $authoritativeColor
    Write-Host (" {0}" -f $productionResult.Projection.ConsoleMessage) -ForegroundColor $authoritativeColor
    if ($productionResult.CommitResult -and $productionResult.CommitResult.Committed) {
        Write-Host (" Authoritative bundle : {0}" -f $productionResult.CommitResult.DestinationDirectory) -ForegroundColor $authoritativeColor
    }
    exit $productionResult.Projection.ExitCode
}
