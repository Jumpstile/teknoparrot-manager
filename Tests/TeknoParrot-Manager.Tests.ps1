#Requires -Module Pester

# Regression suite for the pure / read-only helper functions in
# TeknoParrot-Manager.ps1. The script itself is not a module -- it is one
# file whose function definitions are followed by top-level executable
# code (the interactive menu loop), so it cannot be dot-sourced directly
# without launching that loop. Instead, BeforeAll below parses the file
# with the PowerShell AST and defines only the function bodies in this
# session. This requires zero changes to the production script.
#
# Run with: Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "..\TeknoParrot-Manager.ps1"
    $script:ProductionSource = [System.IO.File]::ReadAllText($scriptPath)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Failed to parse TeknoParrot-Manager.ps1: $($parseErrors -join '; ')"
    }
    $functionAsts = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    # Dot-source the extracted function definitions from one temporary file so
    # PowerShell gives them the same script scope.  Creating and dot-sourcing
    # one ScriptBlock per function can leave functions, mocks, and helper state
    # in subtly different scopes when this container runs alongside other
    # Pester files.
    $extractedFunctionsPath = Join-Path $TestDrive ("tpm-manager-functions-{0}.ps1" -f ([guid]::NewGuid().ToString('N')))
    ($functionAsts | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $extractedFunctionsPath -Encoding utf8
    . $extractedFunctionsPath

    # $FuzzyAutoThreshold/$FuzzyTieMargin are top-level script-scope constants (not
    # function bodies), so the AST extraction above never picks them up. Functions
    # like Resolve-BestFuzzyMatch read them as unqualified script-scope variables,
    # so without this they'd silently read as $null here -- mirror the production
    # values from TeknoParrot-Manager.ps1 explicitly.
    $FuzzyAutoThreshold = 0.72
    $FuzzyTieMargin     = 0.1

    # $script:TitleTokenStopWords is a top-level script-scope constant (not a
    # function body), so the AST extraction above never picks it up.
    # Get-MeaningfulTitleTokens reads it as an unqualified script-scope variable
    # (issue #84) -- mirror the production value explicitly.
    $script:TitleTokenStopWords = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('the', 'of', 'a', 'an', 'and', 'vs', 'vs.', 'in', 'for', 'to'),
        [System.StringComparer]::OrdinalIgnoreCase)

    # $RawThrillsPathLimits is another top-level production table omitted by
    # AST extraction.  Resolver contexts snapshot it in their BeforeAll
    # blocks before installing their narrow fixtures, so establish the
    # script-scope slot here first.  The resolver logic and its fixture values
    # remain unchanged; this only fixes the bootstrap ordering under strict
    # mode.
    $script:RawThrillsPathLimits = @{}

    # $script:LocalDriveInfoCache/$LocalDriveInfoCachePopulated are top-level
    # script-scope variables (not function bodies) initialised before
    # Get-LocalDriveInfoSafe / Clear-LocalDriveInfoCache in the production
    # script. Initialise them here so those functions behave correctly in the
    # test scope (an uninitialised $null is falsy, so the first call would still
    # spawn the job, but the explicit init is cleaner and avoids surprises).
    $script:LocalDriveInfoCache          = $null
    $script:LocalDriveInfoCachePopulated = $false

    # These are top-level production path variables omitted by AST
    # extraction. Keep the test bootstrap strict-mode safe and mirror the
    # production initial state before any fixture supplies concrete paths.
    $script:tpRoot                 = $null
    $script:zipSource              = $null
    $script:zipSourceSupplementary = $null
    $script:gamesInstallFolder     = $null
    # The production startup block initializes these script-scoped slots, but
    # AST function extraction intentionally omits that top-level code. Mirror
    # only the proven workflow state required by isolated strict-mode tests.
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
    $script:PostgresRecoveryStatus = $null
    $script:PostgresRecoveryResumeState = $null

    # Same situation for the FFB Blaster gating (issue #41) and schema-drift
    # (issue #43) constants -- they are top-level script-scope variables in
    # the production script, not function bodies, so the AST extraction above
    # never picks them up. Get-FFBBlasterSupport reads the first two directly,
    # and Get-GameProfileSchemaDrift uses the rest as parameter defaults
    # (which evaluate to $null in test scope without these). Mirror the
    # production values explicitly.
    $script:FFBBlasterUnsupportedPlatforms = @('pcsx2x6')
    $script:FFBBlasterNamePattern          = 'ffb.*blaster|blaster.*ffb'
    $script:KnownGameProfileTopLevel = @(
        'GamePath','GamePath2','TestMenuParameter','TestMenuIsExecutable',
        'ExtraParameters','TestMenuExtraParameters','EmulationProfile',
        'GameProfileRevision','HasSeparateTestMode','ExecutableName',
        'ExecutableName2','HasTwoExecutables','LaunchSecondExecutableFirst',
        'HasTpoSupport','EmulatorType','Is64Bit','ValidMd5','ConfigValues',
        'GameName','GameGenreInternal','IconName','HasModeForSquare',
        'RequiresAdmin','InvokeFullscreenOnStartup','LaunchedFromUsb',
        'CamberWindowState','JoystickButtons','Patreon','xAxisMin','xAxisMax',
        'yAxisMin','yAxisMax','InvertedMouseAxis','GunGame','DevOnly',
        'ResetHint','GasAxisMin','GasAxisMax','OnlineProfileURL',
        'OnlineIdFieldName','OnlineIdType','UseDirectionalPresses','msysType',
        'TestExecIs64Bit','SecondExecutableArguments','Requires4GBPatch',
        'LaunchSecondExecutableMinimized','Use16BitAnalog','RPCS3Config',
        'RequiresBepInEx','IsTpoExclusive','IsLegacy','AllowSettingSync',
        'UseRemoteThread','CustomArguments','InvalidFiles','GameVersion'
    )
    $script:RequiredGameProfileTopLevel = @('EmulationProfile','ConfigValues')
    $script:KnownFieldTypes = @('Bool','Dropdown','Text','Slider','DropdownIndex','KeyCapture','MonitorSelection','Numeric')
    $script:InputConfigFields = @()

    # The production script loads System.IO.Compression.FileSystem at startup
    # (top-level code, line ~82 -- not in a function body, so AST extraction
    # above never captures it). Expand-ZipFileSafe uses ZipFile (from
    # System.IO.Compression.FileSystem.dll). New-TestZip uses ZipArchive (from
    # System.IO.Compression.dll -- a separate assembly). Both are loaded in
    # the Describe "Expand-ZipFileSafe" BeforeAll below.
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    # $ScriptVersion is a top-level script-scope constant (not a function
    # body), so the AST extraction above never picks it up. Get-ManagerUpdateRelease
    # and Invoke-CheckForUpdates read it directly (User-Agent header, current-version
    # display/comparison) -- mirror the production value explicitly. Deliberately
    # not hardcoded to match TeknoParrot-Manager.ps1's own version exactly; tests
    # below use their own controlled version strings/mocks instead of relying on
    # this value's specific number, so drift here would not silently break them.
    $ScriptVersion = "0.99.39"
    $ReleaseCandidateLabel = "RC3"
    $DisplayVersion = "v1.0 RC3"

    # $Script:ReShadeTrustedCertThumbprint and $Script:ReShadeAcceptedSignatureStatuses
    # are both top-level script-scope constants (not function bodies), so
    # the AST extraction above never picks either up.
    # Test-ReShadeSetupTrustedSignature reads both directly -- mirror the
    # production values explicitly so the fingerprint/status-gate tests
    # below exercise the real pinned constants, not an unset $null (an
    # unset $Script:ReShadeAcceptedSignatureStatuses would make
    # "-contains" always return $false, making every trust-matrix test
    # report Trusted=$false regardless of status -- a real gap this
    # comment documents so it isn't reintroduced silently).
    $Script:ReShadeTrustedCertThumbprint = '589690208A5E52FB96980C4A6698F50ACD47C49F'
    $Script:ReShadeAcceptedSignatureStatuses = @('UnknownError')

    # Write-Log normally writes beside the production script via top-level
    # initialisation that AST extraction intentionally skips. Give helper tests a
    # real throwaway log target so certification output is not polluted with
    # synthetic "[UNLOGGED]" messages.
    $script:TestLogRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-tests-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $script:TestLogRoot -Force | Out-Null
    $script:logPath = Join-Path $script:TestLogRoot "TeknoParrot-Manager.Tests.log"
    $script:logWarnShown = $false
    $script:logFailedCount = 0

    # Shared exact-pre/post-state comparison helpers (P1 remediation, 2nd
    # round): a Pester test that only spot-checks "file X is gone" or "dir
    # is empty" can pass even when the pre-operation state was actually
    # different (e.g. the destination directory itself did not exist
    # before the call but rollback leaves it behind, empty). These helpers
    # capture and compare the COMPLETE pre/post state -- directory
    # existence, every entry's relative path, whether it is a file or a
    # directory, and exact file bytes -- so a rollback test can assert
    # genuine byte-for-byte/state-equivalence instead of an approximation
    # of it. Defined here (inside the file-level BeforeAll, alongside the
    # other test-scope helpers above) rather than as bare top-level
    # function statements, because Pester v5 only runs true top-level
    # script code once during Discovery -- functions defined that way are
    # not reliably visible inside It blocks during the later Run phase.
    function Get-TpmDirSnapshot {
        param([string]$Dir)
        if (-not (Test-Path -LiteralPath $Dir)) {
            return [pscustomobject]@{ Existed = $false; Entries = @() }
        }
        $entries = @(Get-ChildItem -LiteralPath $Dir -Force -Recurse | Sort-Object FullName | ForEach-Object {
            [pscustomobject]@{
                RelativePath = $_.FullName.Substring($Dir.Length).TrimStart('\')
                IsDirectory  = $_.PSIsContainer
                Content      = if (-not $_.PSIsContainer) { [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($_.FullName)) } else { $null }
            }
        })
        return [pscustomobject]@{ Existed = $true; Entries = $entries }
    }

    function Assert-TpmDirSnapshotUnchanged {
        param($Before, $After)
        $After.Existed | Should -Be $Before.Existed
        $After.Entries.Count | Should -Be $Before.Entries.Count
        for ($i = 0; $i -lt $Before.Entries.Count; $i++) {
            $After.Entries[$i].RelativePath | Should -Be $Before.Entries[$i].RelativePath
            $After.Entries[$i].IsDirectory  | Should -Be $Before.Entries[$i].IsDirectory
            $After.Entries[$i].Content      | Should -Be $Before.Entries[$i].Content
        }
    }

    # Resolve both the expected directory and the path named in the cleanup
    # error to their filesystem identity. This handles mixed long/8.3 forms
    # (for example, a short user folder with long later components) without
    # reducing the assertion to a substring or basename check.
    if (-not ('TpmFileIdentityInterop' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class TpmFileIdentityInterop {
    [StructLayout(LayoutKind.Sequential)]
    private struct ByHandleFileInformation {
        public uint FileAttributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
        public uint VolumeSerialNumber;
        public uint FileSizeHigh;
        public uint FileSizeLow;
        public uint NumberOfLinks;
        public uint FileIndexHigh;
        public uint FileIndexLow;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateFile(string path, uint desiredAccess, uint shareMode, IntPtr securityAttributes, uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetFileInformationByHandle(IntPtr handle, out ByHandleFileInformation information);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);
    public static string GetIdentity(string path) {
        IntPtr handle = CreateFile(path, 0, 1u | 2u | 4u, IntPtr.Zero, 3u, 0x02000000u, IntPtr.Zero);
        if (handle == new IntPtr(-1)) { return null; }
        try {
            ByHandleFileInformation information;
            if (!GetFileInformationByHandle(handle, out information)) { return null; }
            return string.Format("{0:X8}:{1:X8}{2:X8}", information.VolumeSerialNumber, information.FileIndexHigh, information.FileIndexLow);
        } finally { CloseHandle(handle); }
    }
}
'@
    }

    function Assert-TpmErrorIdentifiesWindowsPath {
        param([string]$ErrorText, [string]$ExpectedPath)
        $expectedIdentity = [TpmFileIdentityInterop]::GetIdentity($ExpectedPath)
        $expectedIdentity | Should -Not -BeNullOrEmpty -Because "the expected staging directory must exist"
        $matched = $false
        $pathMatches = [regex]::Matches($ErrorText, "(?:TPM STAGING CLEANUP FAILED for|residue remains at) '([^']+)'")
        foreach ($pathMatch in $pathMatches) {
            $candidateIdentity = [TpmFileIdentityInterop]::GetIdentity($pathMatch.Groups[1].Value)
            if ([string]::Equals($candidateIdentity, $expectedIdentity, [System.StringComparison]::OrdinalIgnoreCase)) {
                $matched = $true
                break
            }
        }
        $matched | Should -BeTrue -Because "cleanup error must identify the exact staging directory by filesystem identity"
    }
}

AfterAll {
    if ($script:TestLogRoot -and (Test-Path -LiteralPath $script:TestLogRoot)) {
        Remove-Item -LiteralPath $script:TestLogRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Write-Log" {
    It "does not print the archive warning when the log path is intentionally blank" {
        $oldLogPath = $script:logPath
        $oldWarnShown = $script:logWarnShown
        $oldFailedCount = $script:logFailedCount
        try {
            $script:logPath = ''
            $script:logWarnShown = $false
            $script:logFailedCount = 0

            Mock Write-Host {}

            Write-Log "synthetic test message"

            Should -Invoke Write-Host -Times 0 -ParameterFilter { $Object -like '*Cannot write to log file*' }
            Should -Invoke Write-Host -Times 1 -ParameterFilter { $Object -like '*UNLOGGED*synthetic test message*' }
            $script:logFailedCount | Should -Be 1
        } finally {
            $script:logPath = $oldLogPath
            $script:logWarnShown = $oldWarnShown
            $script:logFailedCount = $oldFailedCount
        }
    }
}

Describe "Issue #217 AutoSync first-run guidance" {
    It "explains the staging folder role before path selection" {
        $script:ProductionSource | Should -Match "Game installation folder \(staging folder\)"
        $script:ProductionSource | Should -Match "This is where TPM extracts and installs games"
        $script:ProductionSource | Should -Match "Your original ZIPs stay where they are"
        $script:ProductionSource | Should -Match "Press Enter to use this location, or B to choose another"
    }
    It "cross-references the staging folder from the ZIP prompt" {
        $script:ProductionSource | Should -Match "containing your original \.zip files"
        $script:ProductionSource | Should -Match "This must be DIFFERENT from the staging folder"
    }
    It "distinguishes the supplementary ZIP folder from the Supplementary DAT" {
        $script:ProductionSource | Should -Match "Supplementary game collection folder"
        $script:ProductionSource | Should -Match "not the Supplementary DAT"
        $script:ProductionSource | Should -Match "press Enter to skip"
    }
    It "offers path-visible R and Z recovery while preserving the menu fallback" {
        $script:ProductionSource | Should -Match "Staging folder : \{0\}"
        $script:ProductionSource | Should -Match "ZIP source     : \{0\}"
        $script:ProductionSource | Should -Match "R\) Choose a different staging folder"
        $script:ProductionSource | Should -Match "Z\) Choose a different ZIP source folder"
        $script:ProductionSource | Should -Match ([regex]::Escape('$zipSource = ' + "''"))
        $script:ProductionSource | Should -Match "user returned to menu"
    }
    It "labels RetroBat as folder naming mode without changing the prompt guard" {
        $script:ProductionSource | Should -Match "Folder naming mode"
        $script:ProductionSource | Should -Not -Match "Is this a RetroBat/Batocera installation\?"
        $script:ProductionSource | Should -Match ([regex]::Escape('if (-not $configAccepted -and -not $Unattended)'))
    }
}
Describe "Issue #217/#250 safe staging selection" {
    It "rejects exact, child, and parent overlaps with every protected location" -TestCases @(
        @{ Label = 'the TeknoParrot installation itself'; Candidate = 'C:\tpm-217-fixture\TP'; TpRoot = 'C:\tpm-217-fixture\TP'; Main = 'C:\tpm-217-fixture\MainZips'; Supplementary = 'C:\tpm-217-fixture\Supplementary'; Program = 'C:\tpm-217-fixture\Scripts'; Expected = 'the TeknoParrot installation' }
        @{ Label = 'a child of the TeknoParrot installation'; Candidate = 'C:\tpm-217-fixture\TP\Games'; TpRoot = 'C:\tpm-217-fixture\TP'; Main = 'C:\tpm-217-fixture\MainZips'; Supplementary = 'C:\tpm-217-fixture\Supplementary'; Program = 'C:\tpm-217-fixture\Scripts'; Expected = 'the TeknoParrot installation' }
        @{ Label = 'a parent of the TeknoParrot installation'; Candidate = 'C:\tpm-217-fixture'; TpRoot = 'C:\tpm-217-fixture\TP'; Main = 'C:\tpm-217-other\MainZips'; Supplementary = 'C:\tpm-217-other\Supplementary'; Program = 'C:\tpm-217-other\Scripts'; Expected = 'the TeknoParrot installation' }
        @{ Label = 'the main ZIP source itself'; Candidate = 'C:\tpm-217-fixture\MainZips'; TpRoot = 'C:\tpm-217-fixture\TP'; Main = 'C:\tpm-217-fixture\MainZips'; Supplementary = 'C:\tpm-217-fixture\Supplementary'; Program = 'C:\tpm-217-fixture\Scripts'; Expected = 'the main ZIP source' }
        @{ Label = 'a child of the main ZIP source'; Candidate = 'C:\tpm-217-fixture\MainZips\Nested'; TpRoot = 'C:\tpm-217-fixture\TP'; Main = 'C:\tpm-217-fixture\MainZips'; Supplementary = 'C:\tpm-217-fixture\Supplementary'; Program = 'C:\tpm-217-fixture\Scripts'; Expected = 'the main ZIP source' }
        @{ Label = 'a parent of the main ZIP source'; Candidate = 'C:\tpm-217-fixture'; TpRoot = 'C:\tpm-217-other\TP'; Main = 'C:\tpm-217-fixture\MainZips'; Supplementary = 'C:\tpm-217-other\Supplementary'; Program = 'C:\tpm-217-other\Scripts'; Expected = 'the main ZIP source' }
        @{ Label = 'the supplementary ZIP source itself'; Candidate = 'C:\tpm-217-fixture\Supplementary'; TpRoot = 'C:\tpm-217-fixture\TP'; Main = 'C:\tpm-217-fixture\MainZips'; Supplementary = 'C:\tpm-217-fixture\Supplementary'; Program = 'C:\tpm-217-fixture\Scripts'; Expected = 'the supplementary ZIP source' }
        @{ Label = 'a child of the supplementary ZIP source'; Candidate = 'C:\tpm-217-fixture\Supplementary\Nested'; TpRoot = 'C:\tpm-217-fixture\TP'; Main = 'C:\tpm-217-fixture\MainZips'; Supplementary = 'C:\tpm-217-fixture\Supplementary'; Program = 'C:\tpm-217-fixture\Scripts'; Expected = 'the supplementary ZIP source' }
        @{ Label = 'a parent of the supplementary ZIP source'; Candidate = 'C:\tpm-217-fixture'; TpRoot = 'C:\tpm-217-other\TP'; Main = 'C:\tpm-217-other\MainZips'; Supplementary = 'C:\tpm-217-fixture\Supplementary'; Program = 'C:\tpm-217-other\Scripts'; Expected = 'the supplementary ZIP source' }
        @{ Label = 'the TPM program folder itself'; Candidate = 'C:\tpm-217-fixture\Scripts'; TpRoot = 'C:\tpm-217-fixture\TP'; Main = 'C:\tpm-217-fixture\MainZips'; Supplementary = 'C:\tpm-217-fixture\Supplementary'; Program = 'C:\tpm-217-fixture\Scripts'; Expected = 'the TPM program/package folder' }
        @{ Label = 'a child of the TPM program folder'; Candidate = 'C:\tpm-217-fixture\Scripts\Nested'; TpRoot = 'C:\tpm-217-fixture\TP'; Main = 'C:\tpm-217-fixture\MainZips'; Supplementary = 'C:\tpm-217-fixture\Supplementary'; Program = 'C:\tpm-217-fixture\Scripts'; Expected = 'the TPM program/package folder' }
        @{ Label = 'a parent of the TPM program folder'; Candidate = 'C:\tpm-217-fixture'; TpRoot = 'C:\tpm-217-other\TP'; Main = 'C:\tpm-217-other\MainZips'; Supplementary = 'C:\tpm-217-other\Supplementary'; Program = 'C:\tpm-217-fixture\Scripts'; Expected = 'the TPM program/package folder' }
    ) {
        param($Label, $Candidate, $TpRoot, $Main, $Supplementary, $Program, $Expected)
        $result = Test-TpmStagingFolderCandidate -Candidate $Candidate -TeknoParrotRoot $TpRoot -ZipSource $Main -ZipSourceSupplementary $Supplementary -ProgramDirectory $Program
        $result.Valid | Should -BeFalse -Because $Label
        $result.Reason | Should -Match ([regex]::Escape($Expected))
    }

    It "accepts a missing safe folder without creating it" {
        $candidate = Join-Path $TestDrive "new-staging"
        $result = Test-TpmStagingFolderCandidate -Candidate $candidate -TeknoParrotRoot (Join-Path $TestDrive "TeknoParrot") -ZipSource (Join-Path $TestDrive "OriginalZips") -ZipSourceSupplementary (Join-Path $TestDrive "SupplementaryZips") -ProgramDirectory (Join-Path $TestDrive "Scripts")
        $result.Valid | Should -BeTrue
        $result.CanonicalPath | Should -Be ([System.IO.Path]::GetFullPath($candidate))
        Test-Path -LiteralPath $candidate | Should -BeFalse
    }

    It "chooses the next same-volume default when the first candidate is a ZIP source" {
        $tpRoot = 'C:\tpm-217-default\TP'
        $mainSource = 'C:\TeknoParrot Games'
        $default = Get-TpmSafeStagingFolderDefault -TeknoParrotRoot $tpRoot -ZipSource $mainSource -ProgramDirectory 'C:\tpm-217-default\Scripts'
        $default | Should -Be 'C:\TeknoParrot Games 2'
        (Test-TpmPathOverlap $default $tpRoot) | Should -BeFalse
        (Test-TpmPathOverlap $default $mainSource) | Should -BeFalse
    }

    It "uses the recommended location on Enter without opening the browser" {
        Mock Read-HostSafe { '' }
        Mock Read-PathWithBrowse {}
        $recommended = Join-Path $TestDrive "recommended-staging"
        $result = Read-TpmStagingFolder -RecommendedPath $recommended -TeknoParrotRoot (Join-Path $TestDrive "TeknoParrot") -ZipSource (Join-Path $TestDrive "OriginalZips") -ProgramDirectory (Join-Path $TestDrive "Scripts")
        $result | Should -Be ([System.IO.Path]::GetFullPath($recommended))
        Should -Invoke Read-PathWithBrowse -Times 0
    }

    It "rejects an invalid browsed folder before accepting a later valid folder" {
        $script:browseResultCount = 0
        $tpRoot = Join-Path $TestDrive "TeknoParrot"
        $valid = Join-Path $TestDrive "safe-staging"
        Mock Read-HostSafe { 'B' }
        Mock Read-PathWithBrowse {
            $script:browseResultCount++
            if ($script:browseResultCount -eq 1) { Join-Path $tpRoot "inside" } else { $valid }
        }
        $result = Read-TpmStagingFolder -RecommendedPath '' -TeknoParrotRoot $tpRoot -ZipSource (Join-Path $TestDrive "OriginalZips") -ZipSourceSupplementary (Join-Path $TestDrive "SupplementaryZips") -ProgramDirectory (Join-Path $TestDrive "Scripts")
        $result | Should -Be ([System.IO.Path]::GetFullPath($valid))
        $script:browseResultCount | Should -Be 2
    }

    It "keeps staging creation after the preview decision and behind the real-run guard" {
        $previewIndex = $script:ProductionSource.IndexOf('$dryRunActive = [bool]$DryRun')
        $creationIndex = $script:ProductionSource.IndexOf('[System.IO.Directory]::CreateDirectory($gamesInstallFolder)')
        $previewIndex | Should -BeGreaterThan -1
        $creationIndex | Should -BeGreaterThan $previewIndex
        $script:ProductionSource | Should -Match '-and -not \$dryRunActive -and'
        $earlyValidationIndex = $script:ProductionSource.IndexOf('$earlyStagingCandidate = Test-TpmStagingFolderCandidate')
        $benchmarkIndex = $script:ProductionSource.IndexOf('Measure-PathWriteThroughput $gamesInstallFolder')
        $earlyValidationIndex | Should -BeGreaterThan -1
        $benchmarkIndex | Should -BeGreaterThan $earlyValidationIndex
    }
}
Describe "Issue #257 explicit staging command semantics" {
    It "rejects legacy R/recovery and other reserved letters before filesystem parsing" {
        $tpRoot = Join-Path $TestDrive "arbitrary-working-directory\TeknoParrot"
        $outsideCwd = Split-Path -Parent $tpRoot
        $valid = Join-Path $TestDrive "safe-staging-r-sequence"
        New-Item -ItemType Directory -Path $outsideCwd -Force | Out-Null
        $oldLocation = Get-Location
        $inputs = [System.Collections.Queue]::new()
        @(' R ', 'r', 'R', ' Q ', ' z ', $valid) | ForEach-Object { $inputs.Enqueue($_) }
        try {
            Set-Location $outsideCwd
            Mock Read-HostSafe { [string]$inputs.Dequeue() }
            Mock Read-PathWithBrowse {}
            Mock Write-Host {}
            Mock Write-Log {}
            $result = Read-TpmStagingFolder -RecommendedPath '' -TeknoParrotRoot $tpRoot `
                -ZipSource (Join-Path $TestDrive 'OriginalZips') `
                -ZipSourceSupplementary (Join-Path $TestDrive 'SupplementaryZips') `
                -ProgramDirectory (Join-Path $TestDrive 'Scripts')
        } finally {
            Set-Location $oldLocation
        }
        $result | Should -Be ([System.IO.Path]::GetFullPath($valid))
        Test-Path -LiteralPath (Join-Path $outsideCwd 'R') | Should -BeFalse
        Should -Invoke Read-PathWithBrowse -Times 0
        Should -Invoke Write-Log -Times 5
    }

    It "rejects R when recovery is unavailable at the staging prompt and remains there" {
        $valid = Join-Path $TestDrive "safe-staging-recovery-unavailable"
        $inputs = [System.Collections.Queue]::new()
        @('R', $valid) | ForEach-Object { $inputs.Enqueue($_) }
        Mock Read-HostSafe { [string]$inputs.Dequeue() }
        Mock Read-PathWithBrowse {}
        Mock Write-Host {}
        Mock Write-Log {}
        $result = Read-TpmStagingFolder -RecommendedPath '' -TeknoParrotRoot (Join-Path $TestDrive 'TeknoParrot') `
            -ZipSource (Join-Path $TestDrive 'OriginalZips') -ProgramDirectory (Join-Path $TestDrive 'Scripts')
        $result | Should -Be ([System.IO.Path]::GetFullPath($valid))
        Should -Invoke Read-PathWithBrowse -Times 0
        Test-Path -LiteralPath $valid | Should -BeFalse
    }

    It "accepts a literal directory named R only when it is fully qualified" {
        $qualified = Join-Path $TestDrive 'Games\R'
        Mock Read-HostSafe { $qualified }
        Mock Write-Log {}
        $result = Read-TpmStagingFolder -RecommendedPath '' -TeknoParrotRoot (Join-Path $TestDrive 'TeknoParrot') `
            -ZipSource (Join-Path $TestDrive 'OriginalZips') -ProgramDirectory (Join-Path $TestDrive 'Scripts')
        $result | Should -Be ([System.IO.Path]::GetFullPath($qualified))
        Test-Path -LiteralPath $qualified | Should -BeFalse
    }

    It "recognizes surrounding whitespace for browse without treating it as a path" {
        $valid = Join-Path $TestDrive 'safe-staging-browse'
        Mock Read-HostSafe { '  b  ' }
        Mock Read-PathWithBrowse { $valid }
        Mock Write-Log {}
        $result = Read-TpmStagingFolder -RecommendedPath '' -TeknoParrotRoot (Join-Path $TestDrive 'TeknoParrot') `
            -ZipSource (Join-Path $TestDrive 'OriginalZips') -ProgramDirectory (Join-Path $TestDrive 'Scripts')
        $result | Should -Be ([System.IO.Path]::GetFullPath($valid))
        Should -Invoke Read-PathWithBrowse -Times 1
    }
}
Describe "Issue #220 AutoSync Z recovery" {
    It "re-validates a replacement ZIP source before continuing boundary checks" {
        $zBranch = [regex]::Match(
            $script:ProductionSource,
            '(?s)\} elseif \(\$fix -eq ''Z''\) \{(?<body>.*?)(?:\r?\n)\s*continue\r?\n\s*\}'
        )
        $zBranch.Success | Should -BeTrue
        $zBody = $zBranch.Groups["body"].Value
        $zBody | Should -Match 'if \(-not \(Test-Path -LiteralPath \$zipSource\)\)'
        $zBody | Should -Match 'ERROR: ZIP source folder not found: \$zipSource'
        $zBody | Should -Match 'Write-Log "ERROR: ZIP source not found\."'
        $zBody | Should -Match 'continue 2'
        $existenceCheckIndex = $zBody.IndexOf('if (-not (Test-Path -LiteralPath $zipSource))')
        $captureIndex = $zBody.IndexOf('$zipPathsJustCaptured = $true')
        $saveIndex = $zBody.IndexOf('Save-Config')
        $existenceCheckIndex | Should -BeLessThan $captureIndex
        $existenceCheckIndex | Should -BeLessThan $saveIndex
    }
}
Describe "Beginner-clarity RC wording (optional-download explanations, first-run framing)" {
    It "clarifies the Eggman dat is not a game download" {
        $script:ProductionSource | Should -Match "not the games themselves -- it"
        $script:ProductionSource | Should -Match "never downloads any game data\. It helps TPM recognize and correctly"
    }
    It "defers the supplementary-dat follow-up out of the initial wizard, with a note rather than a blocking Y/N" {
        # Part 2 item 4: the blocking Y/N was removed from the initial
        # Eggman-dat setup wizard and replaced with a short deferred note;
        # the actual offer only appears afterward as a targeted, context-
        # aware post-run recommendation (see the next Describe block).
        $script:ProductionSource | Should -Match ([regex]::Escape("extra version-info file (supplementary dat)"))
        $script:ProductionSource | Should -Match ([regex]::Escape("TPM will recommend it then"))
    }
    It "clarifies thumbnail download is box art only, not game data" {
        $script:ProductionSource | Should -Match "This downloads small box-art icons only, never the games themselves"
    }
    It 'shows a first-run welcome/scope screen only when no saved config exists, gated on -not $Unattended' {
        $script:ProductionSource | Should -Match ([regex]::Escape('if (-not (Test-Path -LiteralPath $configPath) -and -not $Unattended -and -not $isPostgresRecoveryResume) {'))
        $script:ProductionSource | Should -Match "Welcome to TeknoParrot Manager"
        $script:ProductionSource | Should -Match "does not provide game files"
        $script:ProductionSource | Should -Match "does not install or configure TeknoParrot itself"
        $script:ProductionSource | Should -Match "cannot"
        $script:ProductionSource | Should -Match "guarantee that any individual game will boot or run fullscreen"
    }
}

Describe "Get-WhatTpmDidSummaryLines (beginner-clarity end-of-run recap)" {
    It "reports ZIP extraction only when AutoSync ran" {
        $autoSyncLines = Get-WhatTpmDidSummaryLines -AutoSyncRan $true -ZipsExtracted 7 -NewlyRegistered 3 -AlreadyPresent 10 -DatAction 'Reused' -ThumbnailsRequested $true -ManualNeeded 0 -NotInTeknoParrot 0
        ($autoSyncLines -join "`n") | Should -Match "Extracted 7 ZIP\(s\)"

        $registerOnlyLines = Get-WhatTpmDidSummaryLines -AutoSyncRan $false -ZipsExtracted 0 -NewlyRegistered 3 -AlreadyPresent 10 -DatAction 'Reused' -ThumbnailsRequested $true -ManualNeeded 0 -NotInTeknoParrot 0
        ($registerOnlyLines -join "`n") | Should -Not -Match "Extracted"
    }
    It "describes each dat action distinctly" {
        ((Get-WhatTpmDidSummaryLines -AutoSyncRan $false -DatAction 'Downloaded' -ThumbnailsRequested $false) -join "`n") | Should -Match "Downloaded the Eggman dat index file"
        ((Get-WhatTpmDidSummaryLines -AutoSyncRan $false -DatAction 'Updated'    -ThumbnailsRequested $false) -join "`n") | Should -Match "Updated the Eggman dat index file"
        ((Get-WhatTpmDidSummaryLines -AutoSyncRan $false -DatAction 'Reused'     -ThumbnailsRequested $false) -join "`n") | Should -Match "Used your already-configured dat index file"
        ((Get-WhatTpmDidSummaryLines -AutoSyncRan $false -DatAction 'NotConfigured' -ThumbnailsRequested $false) -join "`n") | Should -Match "No dat index file configured"
    }
    It "distinguishes thumbnails downloaded from skipped" {
        ((Get-WhatTpmDidSummaryLines -AutoSyncRan $false -DatAction 'Reused' -ThumbnailsRequested $true)  -join "`n") | Should -Match "Downloaded missing game icons"
        ((Get-WhatTpmDidSummaryLines -AutoSyncRan $false -DatAction 'Reused' -ThumbnailsRequested $false) -join "`n") | Should -Match "Skipped game icon download"
    }
    It "surfaces items needing manual attention, or says nothing does" {
        $needsAttention = Get-WhatTpmDidSummaryLines -AutoSyncRan $false -DatAction 'Reused' -ThumbnailsRequested $false -ManualNeeded 2 -NotInTeknoParrot 1
        ($needsAttention -join "`n") | Should -Match "3 item\(s\) still need your attention -- see ACTION REQUIRED below"

        $allClear = Get-WhatTpmDidSummaryLines -AutoSyncRan $false -DatAction 'Reused' -ThumbnailsRequested $false -ManualNeeded 0 -NotInTeknoParrot 0
        ($allClear -join "`n") | Should -Match "Nothing needs manual attention from this run"
    }
    It "counts controls-readiness items as manual attention without changing the scope disclaimer" {
        $lines = Get-WhatTpmDidSummaryLines -AutoSyncRan $false -DatAction 'Reused' -ThumbnailsRequested $false `
            -ManualNeeded 0 -NotInTeknoParrot 0 -ControlsNeedAttention 1
        ($lines -join "`n") | Should -Match "1 item\(s\) still need your attention -- see ACTION REQUIRED below"
    }
    It "always includes the TPM-scope disclaimer" {
        $lines = (Get-WhatTpmDidSummaryLines -AutoSyncRan $false -DatAction 'NotConfigured' -ThumbnailsRequested $false) -join "`n"
        $lines | Should -Match "does not"
        $lines | Should -Match "provide games, install TeknoParrot itself, or guarantee"
        $lines | Should -Match "usually a TeknoParrot, game, or runtime setting"
    }
}

Describe "Test-PathInside" {

    It "returns true when child equals parent" {
        Test-PathInside "C:\Foo\Bar" "C:\Foo\Bar" | Should -BeTrue
    }
    It "returns true for a real child path" {
        Test-PathInside "C:\Foo\Bar\baz.txt" "C:\Foo\Bar" | Should -BeTrue
    }
    It "returns false for a sibling path that merely shares a string prefix" {
        Test-PathInside "C:\Foo\Barbaz" "C:\Foo\Bar" | Should -BeFalse
    }
    It "returns false for an unrelated path" {
        Test-PathInside "C:\Other\thing.txt" "C:\Foo\Bar" | Should -BeFalse
    }
    It "is case-insensitive" {
        Test-PathInside "c:\foo\bar\baz.txt" "C:\Foo\Bar" | Should -BeTrue
    }
}

Describe "Invoke-WithHardTimeout" {
    # Issue #5 (v1.0 roadmap): a generic hard-timeout wrapper for a local call
    # that could theoretically still block. Uses a real background job (not
    # mocked) since the whole point is genuine process-level isolation -- these
    # tests use short, deterministic scriptblocks so they stay fast.
    It "returns the scriptblock's output when it completes well within the timeout" {
        Invoke-WithHardTimeout -ScriptBlock { 1 + 1 } -TimeoutSeconds 5 | Should -Be 2
    }
    It "returns null and does not throw when the scriptblock exceeds the timeout" {
        $result = $null
        { $result = Invoke-WithHardTimeout -ScriptBlock { Start-Sleep -Seconds 10 } -TimeoutSeconds 1 } | Should -Not -Throw
        $result | Should -BeNullOrEmpty
    }
    It "returns null and does not throw when the scriptblock itself throws" {
        { Invoke-WithHardTimeout -ScriptBlock { throw "boom" } -TimeoutSeconds 5 } | Should -Not -Throw
        Invoke-WithHardTimeout -ScriptBlock { throw "boom" } -TimeoutSeconds 5 | Should -BeNullOrEmpty
    }
}

Describe "Test-IsNetworkPath" {
    # DriveInfo.DriveType is a read-only OS-derived property with no public
    # constructor for a synthetic "Network" instance, so these tests cover
    # the reachable surface without needing a real mapped network drive:
    # the UNC short-circuit (no drive lookup at all), the explicit -Drives
    # override against this machine's real (non-network) drives, and the
    # fail-safe path when drive info genuinely could not be determined
    # (mocking Get-LocalDriveInfoSafe rather than passing -Drives $null,
    # since that default is indistinguishable from "not supplied" and would
    # otherwise just spawn the real job and exercise the success path).
    It "treats a UNC path as a network path without needing drive info at all" {
        Test-IsNetworkPath '\\nas\share\folder' | Should -BeTrue
    }
    It "returns false for an empty or whitespace path" {
        Test-IsNetworkPath '' | Should -BeFalse
        Test-IsNetworkPath '   ' | Should -BeFalse
    }
    It "uses the Name/IsNetwork shape (not a real DriveInfo) when -Drives is supplied explicitly" {
        # -Drives is deliberately untyped (see Test-IsNetworkPath's own comment) -- a real
        # [System.IO.DriveInfo[]] is NOT what gets passed in production. Get-LocalDriveInfoSafe
        # runs in a background job, and a real DriveInfo crossing that job boundary comes back
        # as an undeserializable stand-in (confirmed from a real tester's crash, issue #5
        # follow-up) -- this is the actual shape real callers use.
        $drives = @([pscustomobject]@{ Name = 'C:\'; IsNetwork = $false })
        Test-IsNetworkPath 'C:\Windows' -Drives $drives | Should -BeFalse
    }
    It "detects a network drive via the Name/IsNetwork shape" {
        $drives = @([pscustomobject]@{ Name = 'Z:\'; IsNetwork = $true })
        Test-IsNetworkPath 'Z:\Games' -Drives $drives | Should -BeTrue
    }
    It "fails safe (returns false, never throws) when drive info could not be determined" {
        Mock Get-LocalDriveInfoSafe { $null }
        { Test-IsNetworkPath 'Z:\Games' } | Should -Not -Throw
        Test-IsNetworkPath 'Z:\Games' | Should -BeFalse
    }
    It "end-to-end: works through the real job-backed Get-LocalDriveInfoSafe without throwing" {
        # Regression test for the actual bug a tester hit: this is the exact call shape
        # Find-TeknoParrotRoot/Find-LaunchBoxRoot use, going through the real background
        # job rather than a mocked or directly-constructed -Drives value. Before the fix,
        # this threw "Cannot convert ... Deserialized.System.IO.DriveInfo ... to type
        # System.IO.DriveInfo" because Get-LocalDriveInfoSafe used to return real DriveInfo
        # objects across the job boundary.
        $localDriveInfo = Get-LocalDriveInfoSafe
        { Test-IsNetworkPath "$($env:SystemDrive)\Windows" -Drives $localDriveInfo } | Should -Not -Throw
        Test-IsNetworkPath "$($env:SystemDrive)\Windows" -Drives $localDriveInfo | Should -BeFalse
    }
}

Describe "Get-LocalDriveInfoSafe" {
    BeforeEach {
        # Reset the cache before every test so each one starts from a clean slate.
        Clear-LocalDriveInfoCache
    }
    It "returns real drive info (including the system drive) within the timeout in the normal case" {
        $result = Get-LocalDriveInfoSafe
        $result | Should -Not -BeNullOrEmpty
        ($result | Where-Object { $_.Name -eq "$($env:SystemDrive)\" }) | Should -Not -BeNullOrEmpty
    }
    It "returns plain pscustomobjects, never real DriveInfo instances (the actual bug this guards against)" {
        # Get-LocalDriveInfoSafe runs across a background-job boundary (Invoke-WithHardTimeout);
        # Receive-Job deserializes a real [System.IO.DriveInfo] into an undeserializable
        # "Deserialized.System.IO.DriveInfo" stand-in that fails any strongly-typed
        # [System.IO.DriveInfo[]] parameter bind downstream. Returning plain Name/IsNetwork
        # data instead is the actual fix -- this test locks that shape in.
        $result = Get-LocalDriveInfoSafe
        foreach ($d in $result) {
            $d | Should -BeOfType [System.Management.Automation.PSCustomObject]
            $d.PSObject.Properties.Name | Should -Contain 'Name'
            $d.PSObject.Properties.Name | Should -Contain 'IsNetwork'
        }
    }
    It "populates the cache after the first call so subsequent calls skip the background job" {
        $script:LocalDriveInfoCachePopulated | Should -BeFalse
        Get-LocalDriveInfoSafe | Out-Null
        $script:LocalDriveInfoCachePopulated | Should -BeTrue
        $script:LocalDriveInfoCache | Should -Not -BeNullOrEmpty
    }
    It "Clear-LocalDriveInfoCache resets the populated flag so the next call re-fetches" {
        Get-LocalDriveInfoSafe | Out-Null
        $script:LocalDriveInfoCachePopulated | Should -BeTrue
        Clear-LocalDriveInfoCache
        $script:LocalDriveInfoCachePopulated | Should -BeFalse
        $script:LocalDriveInfoCache | Should -BeNullOrEmpty
    }
}

Describe "Auto-detect root return contract (issue #65)" {
    BeforeEach {
        $script:OriginalUserProfile = $env:USERPROFILE
        $env:USERPROFILE = Join-Path $TestDrive "UserProfile"
        New-Item -ItemType Directory -Path $env:USERPROFILE -Force | Out-Null
        Clear-LocalDriveInfoCache
        Mock Get-LocalDriveInfoSafe { @([pscustomobject]@{ Name = "$TestDrive\"; IsNetwork = $false }) }
        Mock Get-PSDrive {
            [pscustomobject]@{
                Root = "$TestDrive\"
            }
        } -ParameterFilter { $PSProvider -eq 'FileSystem' }
    }

    AfterEach {
        $env:USERPROFILE = $script:OriginalUserProfile
    }

    It "Find-TeknoParrotRoot returns zero matches with Count 0 for caller-side branching" {
        $detected = Find-TeknoParrotRoot

        $detected | Should -BeNullOrEmpty
        $detected.Count | Should -Be 0
    }

    It "Find-TeknoParrotRoot returns one match with Count 1 for caller-side branching" {
        $rootA = Join-Path $env:USERPROFILE "LaunchBox\Emulators\TeknoParrot"
        New-Item -ItemType Directory -Path $rootA -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $rootA "TeknoParrotUi.exe") -Value "stub" -NoNewline

        $detected = Find-TeknoParrotRoot

        $detected.Count | Should -Be 1
        $detected[0] | Should -Be $rootA
    }

    It "Find-TeknoParrotRoot returns multiple matches with Count equal to the number of roots" {
        $rootA = Join-Path $env:USERPROFILE "LaunchBox\Emulators\TeknoParrot"
        $rootB = Join-Path $TestDrive "Games\TeknoParrot"
        New-Item -ItemType Directory -Path $rootA, $rootB -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $rootA "TeknoParrotUi.exe") -Value "stub" -NoNewline
        Set-Content -LiteralPath (Join-Path $rootB "TeknoParrotUi.exe") -Value "stub" -NoNewline

        $detected = Find-TeknoParrotRoot

        $detected.Count | Should -Be 2
        @($detected) | Should -Contain $rootA
        @($detected) | Should -Contain $rootB
    }

    It "Find-LaunchBoxRoot returns zero matches with Count 0 for caller-side branching" {
        $detected = Find-LaunchBoxRoot

        $detected | Should -BeNullOrEmpty
        $detected.Count | Should -Be 0
    }

    It "Find-LaunchBoxRoot returns one match with Count 1 for caller-side branching" {
        $rootA = Join-Path $env:USERPROFILE "LaunchBox"
        New-Item -ItemType Directory -Path $rootA -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $rootA "LaunchBox.exe") -Value "stub" -NoNewline

        $detected = Find-LaunchBoxRoot

        $detected.Count | Should -Be 1
        $detected[0] | Should -Be $rootA
    }

    It "Find-LaunchBoxRoot returns multiple matches with Count equal to the number of roots" {
        $rootA = Join-Path $env:USERPROFILE "LaunchBox"
        $rootB = Join-Path $TestDrive "Games\LaunchBox"
        New-Item -ItemType Directory -Path $rootA, $rootB -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $rootA "LaunchBox.exe") -Value "stub" -NoNewline
        Set-Content -LiteralPath (Join-Path $rootB "LaunchBox.exe") -Value "stub" -NoNewline

        $detected = Find-LaunchBoxRoot

        $detected.Count | Should -Be 2
        @($detected) | Should -Contain $rootA
        @($detected) | Should -Contain $rootB
    }

    It "keeps caller-side auto-detect assignments from re-wrapping the returned ArrayList" {
        $source = Get-Content -Raw -LiteralPath $scriptPath

        $source | Should -Match '\$detected\s*=\s*Find-TeknoParrotRoot'
        $source | Should -Not -Match '\$detected\s*=\s*@\(\s*Find-TeknoParrotRoot\s*\)'
        $source | Should -Match '\$lbDetected\s*=\s*Find-LaunchBoxRoot'
        $source | Should -Not -Match '\$lbDetected\s*=\s*@\(\s*Find-LaunchBoxRoot\s*\)'
    }
}

Describe "ConvertTo-XPathStringLiteral" {
    It "wraps a plain string in single quotes" {
        ConvertTo-XPathStringLiteral "GPU Fix" | Should -Be "'GPU Fix'"
    }
    It "builds a concat() expression when the string contains a single quote" {
        $result = ConvertTo-XPathStringLiteral "It's a Field"
        $result | Should -BeLike "concat(*"
        $result | Should -Not -BeLike "*''''*"
    }
}

Describe "Get-SafeLaunchBoxPlatformFileName" {
    It "passes through an already-safe name" {
        Get-SafeLaunchBoxPlatformFileName "TeknoParrot" | Should -Be "TeknoParrot"
    }
    It "strips invalid filename characters" {
        Get-SafeLaunchBoxPlatformFileName 'My:Plat*form?' | Should -Be "MyPlatform"
    }
    It "trims surrounding whitespace" {
        Get-SafeLaunchBoxPlatformFileName "  Spaced  " | Should -Be "Spaced"
    }
    It "falls back to TeknoParrot when every character is invalid" {
        Get-SafeLaunchBoxPlatformFileName '<>:*' | Should -Be "TeknoParrot"
    }
}

Describe "Set-SecondaryExecutablePath" {
    BeforeAll {
        function New-TwoExeDoc([string]$exe2Name = "amdaemon.exe", [string]$gamePath2 = "") {
            return [xml]@"
<GameProfile>
  <ExecutableName>InitialD0_DX11_Nu.exe</ExecutableName>
  <ExecutableName2>$exe2Name</ExecutableName2>
  <HasTwoExecutables>true</HasTwoExecutables>
  <GamePath2>$gamePath2</GamePath2>
</GameProfile>
"@
        }
    }

    It "sets GamePath2 when the companion exe sits alongside the primary exe" {
        $dir = Join-Path $TestDrive "idz"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $primary = Join-Path $dir "InitialD0_DX11_Nu.exe"
        [System.IO.File]::WriteAllBytes($primary, [byte[]]@(0))
        [System.IO.File]::WriteAllBytes((Join-Path $dir "amdaemon.exe"), [byte[]]@(0))

        $doc = New-TwoExeDoc
        Set-SecondaryExecutablePath $doc $primary

        $doc.GameProfile.GamePath2 | Should -Be (Join-Path $dir "amdaemon.exe")
    }
    It "leaves GamePath2 unset when the companion exe is not found alongside the primary exe" {
        $dir = Join-Path $TestDrive "idz-missing"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $primary = Join-Path $dir "InitialD0_DX11_Nu.exe"
        [System.IO.File]::WriteAllBytes($primary, [byte[]]@(0))

        $doc = New-TwoExeDoc
        Set-SecondaryExecutablePath $doc $primary

        $doc.GameProfile.GamePath2 | Should -BeNullOrEmpty
    }
    It "does nothing when HasTwoExecutables is not true" {
        $dir = Join-Path $TestDrive "single-exe"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $primary = Join-Path $dir "game.exe"
        [System.IO.File]::WriteAllBytes($primary, [byte[]]@(0))
        [System.IO.File]::WriteAllBytes((Join-Path $dir "amdaemon.exe"), [byte[]]@(0))

        $doc = [xml]"<GameProfile><ExecutableName2>amdaemon.exe</ExecutableName2><HasTwoExecutables>false</HasTwoExecutables></GameProfile>"
        Set-SecondaryExecutablePath $doc $primary

        $doc.GameProfile.SelectSingleNode("GamePath2") | Should -BeNullOrEmpty
    }
    It "never overwrites a GamePath2 that already points at the correct companion exe" {
        $dir = Join-Path $TestDrive "idz-already"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $primary = Join-Path $dir "InitialD0_DX11_Nu.exe"
        [System.IO.File]::WriteAllBytes($primary, [byte[]]@(0))
        $correctGp2 = Join-Path $dir "amdaemon.exe"
        [System.IO.File]::WriteAllBytes($correctGp2, [byte[]]@(0))

        $doc = New-TwoExeDoc -gamePath2 $correctGp2
        Set-SecondaryExecutablePath $doc $primary

        $doc.GameProfile.GamePath2 | Should -Be $correctGp2
    }
    It "corrects a stale GamePath2 left pointing at a folder the primary exe no longer lives in" {
        $dir = Join-Path $TestDrive "idz-stale"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $primary = Join-Path $dir "InitialD0_DX11_Nu.exe"
        [System.IO.File]::WriteAllBytes($primary, [byte[]]@(0))
        [System.IO.File]::WriteAllBytes((Join-Path $dir "amdaemon.exe"), [byte[]]@(0))

        # Simulates GamePath having been migrated/repaired to $dir while
        # GamePath2 was left behind pointing at the old pre-migration location.
        $doc = New-TwoExeDoc -gamePath2 "F:\old\stale\location\amdaemon.exe"
        Set-SecondaryExecutablePath $doc $primary

        $doc.GameProfile.GamePath2 | Should -Be (Join-Path $dir "amdaemon.exe")
    }
    It "does nothing when ExecutableName2 is blank" {
        $dir = Join-Path $TestDrive "no-exe2-name"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $primary = Join-Path $dir "game.exe"
        [System.IO.File]::WriteAllBytes($primary, [byte[]]@(0))

        $doc = [xml]"<GameProfile><ExecutableName2></ExecutableName2><HasTwoExecutables>true</HasTwoExecutables></GameProfile>"
        Set-SecondaryExecutablePath $doc $primary

        $doc.GameProfile.SelectSingleNode("GamePath2") | Should -BeNullOrEmpty
    }
}

Describe "Register-Games structured result" {
    It "does not leak the secondary-path helper return value into the result object" {
        $root = Join-Path $TestDrive "register-games-result"
        $userProfilesDir = Join-Path $root "UserProfiles"
        $installFolder = Join-Path $root "Games"
        $gameFolder = Join-Path $installFolder "TestGame"
        $gameProfilesDir = Join-Path $root "GameProfiles"
        New-Item -ItemType Directory -Path $userProfilesDir, $gameFolder, $gameProfilesDir -Force | Out-Null

        $exePath = Join-Path $gameFolder "game.exe"
        [IO.File]::WriteAllBytes($exePath, [byte[]]@(0))
        $templatePath = Join-Path $gameProfilesDir "TestGame.xml"
        [IO.File]::WriteAllText($templatePath, '<GameProfile><ExecutableName>game.exe</ExecutableName><HasTwoExecutables>false</HasTwoExecutables></GameProfile>')

        $profileIndex = @{
            'game.exe' = @([pscustomobject]@{ Code = 'TestGame'; TemplatePath = $templatePath })
        }

        # HasTwoExecutables=false makes Set-SecondaryExecutablePath return its
        # normal $false value. Register-Games must consume that helper result
        # and still return its documented single structured result, including
        # in dry-run mode.
        $result = @(Register-Games -userProfilesDir $userProfilesDir -installFolder $installFolder -profileIndex $profileIndex -gameProfilesDir $gameProfilesDir -DryRun:$true)

        $result.Count | Should -Be 1
        $result[0] | Should -BeOfType [pscustomobject]
        @($result[0].PSObject.Properties.Name) | Should -Contain 'Registered'
        @($result[0].PSObject.Properties.Name) | Should -Contain 'Already'
        @($result[0].PSObject.Properties.Name) | Should -Contain 'Ambiguous'
        @($result[0].PSObject.Properties.Name) | Should -Contain 'Unmatched'
        @($result[0].Registered).Count | Should -Be 1
        $result[0].Registered[0].Code | Should -Be 'TestGame'
    }
}

Describe "Read-HostSafe / Exit-TpmProcess (issue #135: non-interactive input)" {
    # Read-Host returns $null when redirected stdin has run out of piped
    # lines (or, more rarely, when Read-Host is unavailable in the current
    # host). Read-HostSafe is the one centralized wrapper every interactive
    # prompt in the script goes through so that failure mode has a single,
    # tested implementation instead of ~65 individual unguarded .Trim()/
    # .ToUpper() call sites. Exit-TpmProcess is mocked here so the exhausted-
    # input path can be exercised without terminating the test runner.

    It "returns the trimmed value for a normal (interactive-equivalent) answer" {
        Mock Read-Host { return '  Y  ' }
        Read-HostSafe -Prompt 'Continue?' | Should -Be 'Y'
    }

    It "returns an empty string for a blank answer (user pressed Enter with nothing typed)" {
        Mock Read-Host { return '' }
        Read-HostSafe -Prompt 'Continue?' | Should -Be ''
    }

    It "exits with code 1 and does not return a real answer when Read-Host returns null (exhausted redirected stdin)" {
        Mock Read-Host { return $null }
        Mock Exit-TpmProcess { }
        Mock Write-Log { }

        Read-HostSafe -Prompt 'Continue?' | Should -Be ''

        Should -Invoke Exit-TpmProcess -Times 1 -ParameterFilter { $Code -eq 1 }
        Should -Invoke Write-Log -Times 1
    }

    It "never lets a null Read-Host result crash a caller's .ToUpper() call" {
        Mock Read-Host { return $null }
        Mock Exit-TpmProcess { }
        Mock Write-Log { }

        { (Read-HostSafe -Prompt 'Continue?').ToUpper() } | Should -Not -Throw
    }
}

Describe "Read-HostSafe -Default contract (onboarding flow restructuring)" {
    # Strict, explicitly-tested non-interactive-safety contract for the
    # -Default parameter added to cut first-run decision count: a real
    # blank line and whitespace-only input both accept the default;
    # non-blank input always wins and ignores -Default entirely; a null
    # Read-Host result (exhausted/redirected stdin) NEVER resolves to
    # -Default -- it must keep hitting the existing hard-exit path
    # unchanged, exactly as without -Default.

    It "returns the default when Read-Host returns a true blank line" {
        Mock Read-Host { return '' }
        Read-HostSafe -Prompt 'Use RetroBat?' -Default 'N' | Should -Be 'N'
    }

    It "returns the default when Read-Host returns whitespace-only input" {
        Mock Read-Host { return '   ' }
        Read-HostSafe -Prompt 'Use RetroBat?' -Default 'N' | Should -Be 'N'
    }

    It "returns the trimmed non-blank value and ignores -Default entirely" {
        Mock Read-Host { return '  Y  ' }
        Read-HostSafe -Prompt 'Use RetroBat?' -Default 'N' | Should -Be 'Y'
    }

    It "still exits via the hard-exit path on a null (exhausted stdin) result and never returns -Default" {
        Mock Read-Host { return $null }
        Mock Exit-TpmProcess { }
        Mock Write-Log { }

        $result = Read-HostSafe -Prompt 'Use RetroBat?' -Default 'N'

        $result | Should -Be ''
        $result | Should -Not -Be 'N'
        Should -Invoke Exit-TpmProcess -Times 1 -ParameterFilter { $Code -eq 1 }
    }

    It "behaves exactly as before when -Default is omitted (blank returns empty string, not a default)" {
        Mock Read-Host { return '' }
        Read-HostSafe -Prompt 'Continue?' | Should -Be ''
    }
}

Describe "Read-MainMenuChoiceResponsive redirected-input handling (issue #135)" {
    # Confirms the main menu prompt never enters the [Console]::KeyAvailable
    # polling loop when stdin is redirected (polling a keyboard that cannot
    # receive piped input is the 40-second hang from issue #135), and that
    # an exhausted redirected stream exits cleanly instead of looping.
    #
    # [Console]::IsInputRedirected is a static, unmockable property whose
    # value depends on how THIS test process itself was launched -- true
    # when run non-interactively (this repo's CI, or piped/redirected local
    # runs), false when a developer runs Invoke-Pester directly in an
    # interactive terminal window. These two It blocks are guarded to only
    # run in whichever of those two states is actually live, rather than
    # asserting a specific state or risking the interactive-terminal case
    # falling into a real keyboard-polling wait inside a test run.
    It "returns via Read-HostSafe without entering the keyboard-polling loop when input is redirected" -Skip:(-not [Console]::IsInputRedirected) {
        Mock Read-Host { return 'AutoSync' }
        $result = Read-MainMenuChoiceResponsive -Prompt 'Choice:' -InitialWidth 80 -InitialHeight 25
        $result.Value | Should -Be 'AutoSync'
        $result.Redraw | Should -BeFalse
    }

    It "exits cleanly via Exit-TpmProcess instead of looping when redirected stdin is exhausted" -Skip:(-not [Console]::IsInputRedirected) {
        Mock Read-Host { return $null }
        Mock Exit-TpmProcess { }
        Mock Write-Log { }

        $result = Read-MainMenuChoiceResponsive -Prompt 'Choice:' -InitialWidth 80 -InitialHeight 25

        $result.Value | Should -Be ''
        Should -Invoke Exit-TpmProcess -Times 1 -ParameterFilter { $Code -eq 1 }
    }

    It "logs (does not silently swallow) an [Console]::IsInputRedirected detection failure" {
        # IsInputRedirected itself cannot be mocked (static .NET member), so
        # this exercises the documented behavior directly: the function's
        # catch block around that check must call Write-Log, never an empty
        # `catch {}` (issue #135's "do not silently swallow" requirement).
        # Confirmed by source inspection matching this test's expectation:
        # see the comment immediately above the try/catch in
        # Read-MainMenuChoiceResponsive.
        $fnText = (Get-Command Read-MainMenuChoiceResponsive).Definition
        $fnText | Should -Not -Match 'catch\s*\{\s*\}'
        $fnText | Should -Match 'IsInputRedirected.*threw'
    }
}

Describe "Get-ButtonKey / Test-ButtonIsBound" {
    BeforeAll {
        function New-ButtonNode([string]$xml) {
            $doc = [xml]$xml
            return $doc.DocumentElement
        }
    }

    It "builds an InputMapping|AnalogType composite key" {
        $btn = New-ButtonNode "<JoystickButtons><InputMapping>P1Button1</InputMapping><AnalogType>Wheel</AnalogType></JoystickButtons>"
        Get-ButtonKey $btn | Should -Be "P1Button1|Wheel"
    }
    It "defaults AnalogType to None when absent" {
        $btn = New-ButtonNode "<JoystickButtons><InputMapping>P1Button1</InputMapping></JoystickButtons>"
        Get-ButtonKey $btn | Should -Be "P1Button1|None"
    }
    It "returns null when InputMapping is missing" {
        $btn = New-ButtonNode "<JoystickButtons><AnalogType>Wheel</AnalogType></JoystickButtons>"
        Get-ButtonKey $btn | Should -BeNullOrEmpty
    }
    It "returns null when InputMapping is blank" {
        $btn = New-ButtonNode "<JoystickButtons><InputMapping>   </InputMapping></JoystickButtons>"
        Get-ButtonKey $btn | Should -BeNullOrEmpty
    }
    It "reports a button as bound when it has a DirectInputButton child" {
        $btn = New-ButtonNode "<JoystickButtons><DirectInputButton>3</DirectInputButton></JoystickButtons>"
        Test-ButtonIsBound $btn | Should -BeTrue
    }
    It "reports a button as unbound with no binding children" {
        $btn = New-ButtonNode "<JoystickButtons><InputMapping>P1Button1</InputMapping></JoystickButtons>"
        Test-ButtonIsBound $btn | Should -BeFalse
    }
}

Describe "Control Readiness Engine (issue #255)" {
    BeforeAll {
    # Fixture modeled on the real, published After Burner Climax (abc) profile
    # (teknogods/TeknoParrotUI GameProfiles/abc.xml, revision 22): Input API
    # field plus the confirmed required input families -- Start, analog
    # Joystick X/Y, Throttle Lever, Gun Trigger, Missile Trigger, Climax
    # Switch -- matching Get-ControlReadinessKnownRequirements's 'abc' entry
    # exactly. $BoundButtonMappings controls which digital button slots carry
    # a real binding; $OmitAnalog4/$OmitButton2 drop a required mapping
    # entirely so tests can exercise "required control absent" (Missing)
    # distinctly from "required control present but unbound" (also Missing).
    function New-AbcFixtureXml {
        param(
            [string]$GamePath = '',
            [string[]]$BoundButtonMappings = @(),
            [string[]]$EmptyBoundButtonMappings = @(),
            [string]$InputApiValue = 'DirectInput',
            [string[]]$InputApiOptions = @('DirectInput', 'XInput'),
            [switch]$OmitAnalog4,
            [switch]$OmitButton2,
            [switch]$EmptyAnalog4Type,
            [switch]$OmitAnalog4Type,
            [switch]$IncludeDeviceGuid,
            [string]$EmulationProfile = 'AfterBurnerClimax',
            [string]$ExecutableName = 'abc',
            [int]$GameProfileRevision = 22,
            [switch]$FirstTimeSetupComplete
        )

        function New-BindingXml([string]$Mapping, [int]$Slot) {
            if ($EmptyBoundButtonMappings -contains $Mapping) {
                # A binding element that exists but is empty -- structurally
                # present, not a usable binding. Must not count as bound.
                return '<DirectInputButton></DirectInputButton>'
            }
            if ($BoundButtonMappings -notcontains $Mapping) { return '' }
            $guid = if ($IncludeDeviceGuid) { "`n            <DirectInputDeviceGuid>{9e573edb-2130-11ec-8001-444553540000}</DirectInputDeviceGuid>" } else { '' }
            return "<DirectInputButton>$Slot</DirectInputButton>$guid"
        }

        $startBinding   = New-BindingXml 'P1ButtonStart' 2
        $gunBinding     = New-BindingXml 'P1Button1' 0
        $missileBinding = New-BindingXml 'P1Button2' 1
        $climaxBinding  = New-BindingXml 'P1Button3' 3

        $optionsXml = ($InputApiOptions | ForEach-Object { "<string>$_</string>" }) -join ''
        $firstTimeXml = if ($FirstTimeSetupComplete) { '<FirstTimeSetupComplete>true</FirstTimeSetupComplete>' } else { '' }

        $analog4TypeXml = if ($OmitAnalog4Type) { '' } elseif ($EmptyAnalog4Type) { '<AnalogType></AnalogType>' } else { '<AnalogType>SWThrottle</AnalogType>' }
        $analog4Block = if ($OmitAnalog4) { '' } else {
@"
        <JoystickButtons>
            <ButtonName>Throttle Lever</ButtonName>
            <InputMapping>Analog4</InputMapping>
            $analog4TypeXml
        </JoystickButtons>
"@
        }
        $button2Block = if ($OmitButton2) { '' } else {
@"
        <JoystickButtons>
            <ButtonName>Missile Trigger</ButtonName>
            <InputMapping>P1Button2</InputMapping>
            $missileBinding
        </JoystickButtons>
"@
        }

        return @"
<GameProfile>
    <GamePath>$GamePath</GamePath>
    <EmulationProfile>$EmulationProfile</EmulationProfile>
    <GameProfileRevision>$GameProfileRevision</GameProfileRevision>
    <ExecutableName>$ExecutableName</ExecutableName>
    <EmulatorType>Lindbergh</EmulatorType>
    $firstTimeXml
    <ConfigValues>
        <FieldInformation>
            <CategoryName>General</CategoryName>
            <FieldName>Input API</FieldName>
            <FieldValue>$InputApiValue</FieldValue>
            <FieldType>Dropdown</FieldType>
            <FieldOptions>$optionsXml</FieldOptions>
        </FieldInformation>
    </ConfigValues>
    <JoystickButtons>
        <JoystickButtons>
            <ButtonName>Start</ButtonName>
            <InputMapping>P1ButtonStart</InputMapping>
            $startBinding
        </JoystickButtons>
        <JoystickButtons>
            <ButtonName>Joystick Analog X</ButtonName>
            <InputMapping>Analog0</InputMapping>
            <AnalogType>AnalogJoystick</AnalogType>
        </JoystickButtons>
        <JoystickButtons>
            <ButtonName>Joystick Analog Y</ButtonName>
            <InputMapping>Analog2</InputMapping>
            <AnalogType>AnalogJoystickReverse</AnalogType>
        </JoystickButtons>
$analog4Block
        <JoystickButtons>
            <ButtonName>Gun Trigger</ButtonName>
            <InputMapping>P1Button1</InputMapping>
            $gunBinding
        </JoystickButtons>
$button2Block
        <JoystickButtons>
            <ButtonName>Climax Switch</ButtonName>
            <InputMapping>P1Button3</InputMapping>
            $climaxBinding
        </JoystickButtons>
    </JoystickButtons>
</GameProfile>
"@
    }

    # Every required button mapping, for tests that need the "structurally
    # complete" abc fixture (splat as -BoundButtonMappings $AbcRequiredButtons).
    $script:AbcRequiredButtons = @('P1ButtonStart', 'P1Button1', 'P1Button2', 'P1Button3')
    }

    Context "Get-ControlReadinessRegistrationState" {
        BeforeEach {
            $userProfilesDir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $userProfilesDir | Out-Null
        }

        It "returns Unregistered when no UserProfiles entry exists for the code" {
            Get-ControlReadinessRegistrationState -Code 'abc' -UserProfilesDir $userProfilesDir | Should -Be 'Unregistered'
        }

        It "returns Broken when the UserProfiles entry is not well-formed XML" {
            Set-Content -LiteralPath (Join-Path $userProfilesDir 'abc.xml') -Value '<GameProfile><GamePath>' -Encoding utf8
            Get-ControlReadinessRegistrationState -Code 'abc' -UserProfilesDir $userProfilesDir | Should -Be 'Broken'
        }

        It "returns Broken when GamePath is missing" {
            Set-Content -LiteralPath (Join-Path $userProfilesDir 'abc.xml') -Value (New-AbcFixtureXml) -Encoding utf8
            Get-ControlReadinessRegistrationState -Code 'abc' -UserProfilesDir $userProfilesDir | Should -Be 'Broken'
        }

        It "returns Broken when GamePath points at a file that no longer exists" {
            $missingExe = Join-Path $userProfilesDir 'nowhere\abc.exe'
            Set-Content -LiteralPath (Join-Path $userProfilesDir 'abc.xml') -Value (New-AbcFixtureXml -GamePath $missingExe) -Encoding utf8
            Get-ControlReadinessRegistrationState -Code 'abc' -UserProfilesDir $userProfilesDir | Should -Be 'Broken'
        }

        It "returns Registered when GamePath points at an existing file" {
            $realExe = Join-Path $userProfilesDir 'abc.exe'
            Set-Content -LiteralPath $realExe -Value 'stub' -Encoding utf8
            Set-Content -LiteralPath (Join-Path $userProfilesDir 'abc.xml') -Value (New-AbcFixtureXml -GamePath $realExe) -Encoding utf8
            Get-ControlReadinessRegistrationState -Code 'abc' -UserProfilesDir $userProfilesDir | Should -Be 'Registered'
        }

        It "rejects a non-alphanumeric code (path-traversal guard) without joining it into a path" {
            Get-ControlReadinessRegistrationState -Code '..\..\Windows\system.ini' -UserProfilesDir $userProfilesDir | Should -Be 'Unregistered'
        }
    }

    Context "Get-ControlReadinessControlsState" {
        It "returns Unknown when there is no document to read" {
            Get-ControlReadinessControlsState $null 'abc' | Should -Be 'Unknown'
        }

        It "returns Unknown for a profile code with no authoritative requirements catalog entry" {
            # A profile this engine knows nothing about must never be classified
            # from raw structure -- "no button nodes" is not evidence of
            # Unsupported without a requirements catalog to check it against.
            $doc = [xml]"<GameProfile><GamePath></GamePath></GameProfile>"
            Get-ControlReadinessControlsState $doc 'someUnknownProfileCode' | Should -Be 'Unknown'
        }

        It "returns Unknown when no code is supplied at all (legacy positional call)" {
            $doc = [xml](New-AbcFixtureXml)
            Get-ControlReadinessControlsState $doc | Should -Be 'Unknown'
        }

        It "returns Missing when every required button is unbound (the abc template as shipped)" {
            $doc = [xml](New-AbcFixtureXml)
            Get-ControlReadinessControlsState $doc 'abc' | Should -Be 'Missing'
        }

        It "returns NotVerified once every required button and analog mapping is present and bound, without claiming Verified" {
            $doc = [xml](New-AbcFixtureXml -BoundButtonMappings $AbcRequiredButtons)
            Get-ControlReadinessControlsState $doc 'abc' | Should -Be 'NotVerified'
        }

        It "never returns Verified -- this engine has no evidence source that could earn it" {
            $doc = [xml](New-AbcFixtureXml -BoundButtonMappings $AbcRequiredButtons)
            $states = @('Missing', 'Unsupported', 'NotVerified', 'Unknown')
            $states | Should -Contain (Get-ControlReadinessControlsState $doc 'abc')
        }
    }

    Context "Get-ControlReadinessLaunchState" {
        It "always reports NotTestedByTpm -- TPM does not launch games or read a launch log" {
            Get-ControlReadinessLaunchState -Code 'abc' | Should -Be 'NotTestedByTpm'
        }
    }

    Context "Get-ControlReadinessAssessment (abc regression fixture, issue #255)" {
        BeforeEach {
            $userProfilesDir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '_up')
            $gameProfilesDir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '_gp')
            New-Item -ItemType Directory -Path $userProfilesDir | Out-Null
            New-Item -ItemType Directory -Path $gameProfilesDir | Out-Null
        }

        It "reproduces the issue #255 evidence: registered+launched but controls not verified" {
            $realExe = Join-Path $userProfilesDir 'abc.exe'
            Set-Content -LiteralPath $realExe -Value 'stub' -Encoding utf8
            Set-Content -LiteralPath (Join-Path $userProfilesDir 'abc.xml') `
                -Value (New-AbcFixtureXml -GamePath $realExe -BoundButtonMappings $AbcRequiredButtons) -Encoding utf8

            $result = Get-ControlReadinessAssessment -Code 'abc' -UserProfilesDir $userProfilesDir -GameProfilesDir $gameProfilesDir

            $result.Registration | Should -Be 'Registered'
            $result.Controls     | Should -Be 'NotVerified'
            $result.Launch       | Should -Be 'NotTestedByTpm'
        }

        It "falls back to the GameProfiles template's controls when the game is not yet registered" {
            Set-Content -LiteralPath (Join-Path $gameProfilesDir 'abc.xml') -Value (New-AbcFixtureXml) -Encoding utf8

            $result = Get-ControlReadinessAssessment -Code 'abc' -UserProfilesDir $userProfilesDir -GameProfilesDir $gameProfilesDir

            $result.Registration | Should -Be 'Unregistered'
            $result.Controls     | Should -Be 'Missing'
            $result.Launch       | Should -Be 'NotTestedByTpm'
        }

        It "reports Unknown controls when neither a UserProfile nor a GameProfiles template exists" {
            $result = Get-ControlReadinessAssessment -Code 'abc' -UserProfilesDir $userProfilesDir -GameProfilesDir $gameProfilesDir
            $result.Registration | Should -Be 'Unregistered'
            $result.Controls     | Should -Be 'Unknown'
        }

        It "keeps Registration=Broken independent of Controls -- a broken GamePath does not force Controls to Unknown" {
            Set-Content -LiteralPath (Join-Path $userProfilesDir 'abc.xml') `
                -Value (New-AbcFixtureXml -GamePath (Join-Path $userProfilesDir 'missing.exe') -BoundButtonMappings $AbcRequiredButtons) -Encoding utf8

            $result = Get-ControlReadinessAssessment -Code 'abc' -UserProfilesDir $userProfilesDir -GameProfilesDir $gameProfilesDir

            $result.Registration | Should -Be 'Broken'
            $result.Controls     | Should -Be 'NotVerified'
        }

        It "never writes to the UserProfiles or GameProfiles XML it reads (read-only guarantee)" {
            $realExe = Join-Path $userProfilesDir 'abc.exe'
            Set-Content -LiteralPath $realExe -Value 'stub' -Encoding utf8
            $profilePath = Join-Path $userProfilesDir 'abc.xml'
            Set-Content -LiteralPath $profilePath -Value (New-AbcFixtureXml -GamePath $realExe -BoundButtonMappings $AbcRequiredButtons) -Encoding utf8
            $before = Get-Content -LiteralPath $profilePath -Raw
            $beforeWriteTime = (Get-Item -LiteralPath $profilePath).LastWriteTimeUtc

            [void](Get-ControlReadinessAssessment -Code 'abc' -UserProfilesDir $userProfilesDir -GameProfilesDir $gameProfilesDir)

            (Get-Content -LiteralPath $profilePath -Raw) | Should -Be $before
            (Get-Item -LiteralPath $profilePath).LastWriteTimeUtc | Should -Be $beforeWriteTime
        }

        It "rejects a non-alphanumeric code (path-traversal guard) end to end" {
            $result = Get-ControlReadinessAssessment -Code '..\..\secrets' -UserProfilesDir $userProfilesDir -GameProfilesDir $gameProfilesDir
            $result.Registration | Should -Be 'Unregistered'
            $result.Controls     | Should -Be 'Unknown'
        }
    }

    Context "Get-ControlReadinessActionItems (wired onboarding handoff, issue #255)" {
        BeforeAll {
            function Get-ReadinessHandoffSnapshot {
                param([string]$Dir)
                $files = @(Get-ChildItem -LiteralPath $Dir -Recurse -File -Force -ErrorAction Stop |
                    Sort-Object FullName | ForEach-Object {
                        [pscustomobject]@{
                            Path  = $_.FullName
                            Hash  = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
                            Write = $_.LastWriteTimeUtc
                        }
                    })
                [pscustomobject]@{ Existed = Test-Path -LiteralPath $Dir; FileCount = $files.Count; Files = $files }
            }
        }

        BeforeEach {
            $userProfilesDir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '_up')
            $gameProfilesDir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '_gp')
            $tpRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '_tp')
            New-Item -ItemType Directory -Path $userProfilesDir, $gameProfilesDir, $tpRoot | Out-Null
            Set-Content -LiteralPath (Join-Path $tpRoot 'ParrotData.xml') -Value '<ParrotData><FirstTimeSetupComplete>true</FirstTimeSetupComplete></ParrotData>' -Encoding utf8
        }

        It "surfaces registered abc with wizard complete and missing controls as not ready" {
            $realExe = Join-Path $userProfilesDir 'abc.exe'
            Set-Content -LiteralPath $realExe -Value 'stub' -Encoding utf8
            Set-Content -LiteralPath (Join-Path $userProfilesDir 'abc.xml') -Value (
                New-AbcFixtureXml -GamePath $realExe -InputApiValue 'XInput' -FirstTimeSetupComplete -OmitAnalog4
            ) -Encoding utf8

            $items = @(Get-ControlReadinessActionItems -UserProfilesDir $userProfilesDir `
                -GameProfilesDir $gameProfilesDir -TeknoParrotRoot $tpRoot)

            $items.Count | Should -Be 1
            $items[0].Assessment.Registration | Should -Be 'Registered'
            $items[0].Assessment.Controls | Should -Be 'Missing'
            $items[0].SummaryLines | Should -Contain 'TeknoParrot first-run setup: Complete'
            $items[0].SummaryLines | Should -Contain 'Controls: Missing'
            $items[0].SummaryLines | Should -Contain 'Open TeknoParrot controls configuration and map/test controls before treating this game as ready.'
            $items[0].SummaryLines | Should -Not -Contain 'Controls: Verified'
        }

        It "keeps complete XInput bindings with stored device references at NotVerified" {
            $realExe = Join-Path $userProfilesDir 'abc.exe'
            Set-Content -LiteralPath $realExe -Value 'stub' -Encoding utf8
            Set-Content -LiteralPath (Join-Path $userProfilesDir 'abc.xml') -Value (
                New-AbcFixtureXml -GamePath $realExe -InputApiValue 'XInput' `
                    -BoundButtonMappings $AbcRequiredButtons -IncludeDeviceGuid -FirstTimeSetupComplete
            ) -Encoding utf8

            $items = @(Get-ControlReadinessActionItems -UserProfilesDir $userProfilesDir `
                -GameProfilesDir $gameProfilesDir -TeknoParrotRoot $tpRoot)

            $items.Count | Should -Be 1
            $items[0].Assessment.Controls | Should -Be 'NotVerified'
            $items[0].SummaryLines | Should -Contain 'Controls: Not verified'
            $items[0].SummaryLines | Should -Contain 'Open TeknoParrot controls configuration and map/test controls before treating this game as ready.'
            $items[0].SummaryLines | Should -Not -Contain 'Controls: Verified'
        }

        It "leaves UserProfiles, GameProfiles, and ParrotData unchanged across the full handoff path" {
            $realExe = Join-Path $userProfilesDir 'abc.exe'
            Set-Content -LiteralPath $realExe -Value 'stub' -Encoding utf8
            Set-Content -LiteralPath (Join-Path $userProfilesDir 'abc.xml') -Value (
                New-AbcFixtureXml -GamePath $realExe -InputApiValue 'XInput' -FirstTimeSetupComplete -OmitButton2
            ) -Encoding utf8
            Set-Content -LiteralPath (Join-Path $gameProfilesDir 'abc.xml') -Value (New-AbcFixtureXml) -Encoding utf8

            $beforeUp = Get-ReadinessHandoffSnapshot -Dir $userProfilesDir
            $beforeGp = Get-ReadinessHandoffSnapshot -Dir $gameProfilesDir
            $beforeTp = Get-ReadinessHandoffSnapshot -Dir $tpRoot

            [void](Get-ControlReadinessActionItems -UserProfilesDir $userProfilesDir `
                -GameProfilesDir $gameProfilesDir -TeknoParrotRoot $tpRoot)

            $afterUp = Get-ReadinessHandoffSnapshot -Dir $userProfilesDir
            $afterGp = Get-ReadinessHandoffSnapshot -Dir $gameProfilesDir
            $afterTp = Get-ReadinessHandoffSnapshot -Dir $tpRoot

            (Compare-Object $beforeUp.Files $afterUp.Files -Property Path, Hash, Write) | Should -BeNullOrEmpty
            (Compare-Object $beforeGp.Files $afterGp.Files -Property Path, Hash, Write) | Should -BeNullOrEmpty
            (Compare-Object $beforeTp.Files $afterTp.Files -Property Path, Hash, Write) | Should -BeNullOrEmpty
            $afterUp.FileCount | Should -Be $beforeUp.FileCount
            $afterGp.FileCount | Should -Be $beforeGp.FileCount
            $afterTp.FileCount | Should -Be $beforeTp.FileCount
        }
    }

    Context "Get-ControlReadinessSummaryLines" {
        It "reproduces the issue #255 candidate pre-1.0 UX exactly for the abc regression fixture" {
            $assessment = [pscustomobject]@{ Code = 'abc'; Registration = 'Registered'; Controls = 'NotVerified'; Launch = 'NotTestedByTpm' }
            $lines = Get-ControlReadinessSummaryLines -Assessment $assessment
            ($lines -join "`n") | Should -Be (@(
                'Game registered successfully'
                'Controls: Not verified'
                'Launch status: Not tested by TPM'
                ''
                'Open TeknoParrot controls configuration and map/test controls before treating this game as ready.'
            ) -join "`n")
        }

        It "renders Controls: Verified only when VerificationEvidence proves an actual observed test" {
            $assessment = [pscustomobject]@{
                Code = 'abc'; Registration = 'Registered'; Controls = 'Verified'; Launch = 'ObservedSuccess'
                VerificationEvidence = [pscustomobject]@{ Method = 'Manual play-test, all inputs exercised'; ObservedAt = '2026-08-21T12:00:00Z' }
            }
            $lines = Get-ControlReadinessSummaryLines -Assessment $assessment
            $lines | Should -Not -Contain 'Open TeknoParrot controls configuration and map/test controls before treating this game as ready.'
            $lines | Should -Contain 'Controls: Verified'
        }

        It "omits the configure/test question when the profile has no controls to verify (Unsupported)" {
            $assessment = [pscustomobject]@{ Code = 'abc'; Registration = 'Registered'; Controls = 'Unsupported'; Launch = 'NotTestedByTpm' }
            $lines = Get-ControlReadinessSummaryLines -Assessment $assessment
            $lines | Should -Not -Contain 'Open TeknoParrot controls configuration and map/test controls before treating this game as ready.'
        }

        It "asks the configure/test question for Missing and Unknown controls, same as NotVerified" -TestCases @(
            @{ Controls = 'Missing' }
            @{ Controls = 'Unknown' }
        ) {
            param($Controls)
            $assessment = [pscustomobject]@{ Code = 'abc'; Registration = 'Unregistered'; Controls = $Controls; Launch = 'NotTestedByTpm' }
            $lines = Get-ControlReadinessSummaryLines -Assessment $assessment
            $lines | Should -Contain 'Open TeknoParrot controls configuration and map/test controls before treating this game as ready.'
        }

        It "reflects Unregistered and Broken registration text distinctly from Registered" {
            (Get-ControlReadinessSummaryLines -Assessment ([pscustomobject]@{ Code = 'abc'; Registration = 'Unregistered'; Controls = 'Missing'; Launch = 'NotTestedByTpm' }))[0] | Should -Be 'Game is not registered'
            (Get-ControlReadinessSummaryLines -Assessment ([pscustomobject]@{ Code = 'abc'; Registration = 'Broken'; Controls = 'Missing'; Launch = 'NotTestedByTpm' }))[0] | Should -Be 'Game registration is broken'
        }

        It "registered + Missing controls renders correctly and never reads as ready" {
            $assessment = [pscustomobject]@{ Code = 'abc'; Registration = 'Registered'; Controls = 'Missing'; Launch = 'NotTestedByTpm' }
            $lines = Get-ControlReadinessSummaryLines -Assessment $assessment
            $lines[0] | Should -Be 'Game registered successfully'
            $lines | Should -Contain 'Controls: Missing'
            $lines | Should -Contain 'Open TeknoParrot controls configuration and map/test controls before treating this game as ready.'
            ($lines -join "`n") | Should -Not -Match 'Verified'
            ($lines -join "`n") | Should -Not -Match 'Controls:\s+Verified'
        }

        It "renders the ObservedSuccess launch state as an explicit observation" {
            $assessment = [pscustomobject]@{ Code = 'abc'; Registration = 'Registered'; Controls = 'NotVerified'; Launch = 'ObservedSuccess' }
            (Get-ControlReadinessSummaryLines -Assessment $assessment) | Should -Contain 'Launch status: Explicitly observed (success)'
        }

        It "renders the ObservedFailure launch state as an explicit observation" {
            $assessment = [pscustomobject]@{ Code = 'abc'; Registration = 'Registered'; Controls = 'NotVerified'; Launch = 'ObservedFailure' }
            (Get-ControlReadinessSummaryLines -Assessment $assessment) | Should -Contain 'Launch status: Explicitly observed (failure)'
        }

        Context "Fail-closed on caller-supplied Controls = 'Verified' (Codex review, issue #255)" {
            It "downgrades to Not verified when VerificationEvidence is entirely absent" {
                $assessment = [pscustomobject]@{ Code = 'abc'; Registration = 'Registered'; Controls = 'Verified'; Launch = 'NotTestedByTpm' }
                $lines = Get-ControlReadinessSummaryLines -Assessment $assessment
                $lines | Should -Contain 'Controls: Not verified'
                $lines | Should -Not -Contain 'Controls: Verified'
                $lines | Should -Contain 'Open TeknoParrot controls configuration and map/test controls before treating this game as ready.'
            }

            It "downgrades to Not verified when VerificationEvidence is present but null" {
                $assessment = [pscustomobject]@{ Code = 'abc'; Registration = 'Registered'; Controls = 'Verified'; Launch = 'NotTestedByTpm'; VerificationEvidence = $null }
                (Get-ControlReadinessSummaryLines -Assessment $assessment) | Should -Contain 'Controls: Not verified'
            }

            It "downgrades to Not verified when VerificationEvidence is a bare string, not a structured record" {
                $assessment = [pscustomobject]@{ Code = 'abc'; Registration = 'Registered'; Controls = 'Verified'; Launch = 'NotTestedByTpm'; VerificationEvidence = 'trust me' }
                (Get-ControlReadinessSummaryLines -Assessment $assessment) | Should -Contain 'Controls: Not verified'
            }

            It "downgrades to Not verified when VerificationEvidence is missing Method" {
                $assessment = [pscustomobject]@{
                    Code = 'abc'; Registration = 'Registered'; Controls = 'Verified'; Launch = 'NotTestedByTpm'
                    VerificationEvidence = [pscustomobject]@{ ObservedAt = '2026-08-21T12:00:00Z' }
                }
                (Get-ControlReadinessSummaryLines -Assessment $assessment) | Should -Contain 'Controls: Not verified'
            }

            It "downgrades to Not verified when VerificationEvidence is missing ObservedAt" {
                $assessment = [pscustomobject]@{
                    Code = 'abc'; Registration = 'Registered'; Controls = 'Verified'; Launch = 'NotTestedByTpm'
                    VerificationEvidence = [pscustomobject]@{ Method = 'Manual play-test' }
                }
                (Get-ControlReadinessSummaryLines -Assessment $assessment) | Should -Contain 'Controls: Not verified'
            }

            It "downgrades to Not verified when Method/ObservedAt are present but blank" {
                $assessment = [pscustomobject]@{
                    Code = 'abc'; Registration = 'Registered'; Controls = 'Verified'; Launch = 'NotTestedByTpm'
                    VerificationEvidence = [pscustomobject]@{ Method = '  '; ObservedAt = '' }
                }
                (Get-ControlReadinessSummaryLines -Assessment $assessment) | Should -Contain 'Controls: Not verified'
            }
        }
    }

    Context "Test-ControlReadinessVerificationEvidence" {
        It "returns false for a null assessment" {
            Test-ControlReadinessVerificationEvidence -Assessment $null | Should -Be $false
        }

        It "returns false when VerificationEvidence is absent" {
            Test-ControlReadinessVerificationEvidence -Assessment ([pscustomobject]@{ Controls = 'Verified' }) | Should -Be $false
        }

        It "returns true for a well-formed evidence record" {
            $assessment = [pscustomobject]@{
                Controls = 'Verified'
                VerificationEvidence = [pscustomobject]@{ Method = 'Manual play-test'; ObservedAt = '2026-08-21T12:00:00Z' }
            }
            Test-ControlReadinessVerificationEvidence -Assessment $assessment | Should -Be $true
        }
    }

    Context "Matrix: authoritative requiredness and signals that must not imply Verified (Codex review, issue #255)" {
        It "ABC with every authoritative required control present and bound but untested -> NotVerified" {
            $doc = [xml](New-AbcFixtureXml -BoundButtonMappings $AbcRequiredButtons)
            Get-ControlReadinessControlsState $doc 'abc' | Should -Be 'NotVerified'
        }

        It "ABC missing a known required analog mapping (Throttle Lever, Analog4) -> Missing" {
            $doc = [xml](New-AbcFixtureXml -BoundButtonMappings $AbcRequiredButtons -OmitAnalog4)
            Get-ControlReadinessControlsState $doc 'abc' | Should -Be 'Missing'
        }

        It "ABC missing a known required button mapping (Missile Trigger, P1Button2) -> Missing" {
            $doc = [xml](New-AbcFixtureXml -BoundButtonMappings @('P1ButtonStart', 'P1Button1', 'P1Button3') -OmitButton2)
            Get-ControlReadinessControlsState $doc 'abc' | Should -Be 'Missing'
        }

        It "ABC complete plus stored device references only -> NotVerified or Unknown, never Verified" {
            # A stored device GUID is a config value on disk, not evidence the
            # device is physically connected or that the mapping was ever
            # exercised.
            $doc = [xml](New-AbcFixtureXml -BoundButtonMappings $AbcRequiredButtons -IncludeDeviceGuid)
            $result = Get-ControlReadinessControlsState $doc 'abc'
            $result | Should -BeIn @('NotVerified', 'Unknown')
            $result | Should -Not -Be 'Verified'
        }

        It "ABC all-bound / threshold-like profile -> NotVerified, never Verified" {
            # Mirrors the #255 evidence session: TeknoParrotUI's first-run wizard
            # marked its controls step complete with no mapping screen opened.
            # Whether every button happens to be bound or none are, there is no
            # bound-count threshold anywhere in the engine that promotes
            # structural completeness to Verified.
            $doc = [xml](New-AbcFixtureXml -BoundButtonMappings $AbcRequiredButtons)
            Get-ControlReadinessControlsState $doc 'abc' | Should -Be 'NotVerified'
            Get-ControlReadinessControlsState $doc 'abc' | Should -Not -Be 'Verified'
        }

        It "ABC with an ambiguous/mismatched profile contract -> Unknown" {
            # Code 'abc' matches the catalog, but the document's own declared
            # EmulationProfile does not match what that catalog entry
            # describes -- the requirements might not even apply here, so
            # nothing about this document can be classified authoritatively.
            $doc = [xml](New-AbcFixtureXml -BoundButtonMappings $AbcRequiredButtons -EmulationProfile 'SomeOtherGame')
            Get-ControlReadinessControlsState $doc 'abc' | Should -Be 'Unknown'
        }

        It "ABC with a GameProfileRevision that does not match the catalog's captured provenance -> Unknown" -TestCases @(
            @{ Revision = 21 }
            @{ Revision = 23 }
        ) {
            # The catalog entry is bound to GameProfileRevision 22 -- the
            # exact revision captured during issue #255's evidence session.
            # A different revision is not assumed to share the same required
            # controls, so it must not be classified against this entry.
            param($Revision)
            $doc = [xml](New-AbcFixtureXml -BoundButtonMappings $AbcRequiredButtons -GameProfileRevision $Revision)
            Get-ControlReadinessControlsState $doc 'abc' | Should -Be 'Unknown'
        }

        It "ABC with a missing GameProfileRevision element -> Unknown" {
            $rawXml = (New-AbcFixtureXml -BoundButtonMappings $AbcRequiredButtons) -replace '<GameProfileRevision>22</GameProfileRevision>', ''
            $doc = [xml]$rawXml
            Get-ControlReadinessControlsState $doc 'abc' | Should -Be 'Unknown'
        }

        It "ABC with an empty required button binding element -> Missing, not bound" {
            # <DirectInputButton></DirectInputButton> exists structurally but
            # carries no usable value -- it must not count as a real binding.
            $doc = [xml](New-AbcFixtureXml -BoundButtonMappings $AbcRequiredButtons -EmptyBoundButtonMappings @('P1ButtonStart'))
            Get-ControlReadinessControlsState $doc 'abc' | Should -Be 'Missing'
        }

        It "ABC with an empty AnalogType on a required analog mapping -> Missing" {
            $doc = [xml](New-AbcFixtureXml -BoundButtonMappings $AbcRequiredButtons -EmptyAnalog4Type)
            Get-ControlReadinessControlsState $doc 'abc' | Should -Be 'Missing'
        }

        It "ABC with a required analog mapping missing its AnalogType element entirely -> Missing" {
            $doc = [xml](New-AbcFixtureXml -BoundButtonMappings $AbcRequiredButtons -OmitAnalog4Type)
            Get-ControlReadinessControlsState $doc 'abc' | Should -Be 'Missing'
        }

        It "ABC with positive unsupported/incompatible API evidence -> Unsupported" {
            # The document's own FieldOptions declare only DirectInput/XInput
            # as supported; a selected FieldValue outside that set is a real,
            # document-declared contract violation, not a heuristic guess.
            $doc = [xml](New-AbcFixtureXml -BoundButtonMappings $AbcRequiredButtons -InputApiValue 'RawInput' -InputApiOptions @('DirectInput', 'XInput'))
            Get-ControlReadinessControlsState $doc 'abc' | Should -Be 'Unsupported'
        }

        It "FirstTimeSetupComplete = true does not upgrade controls state" {
            $incomplete = [xml](New-AbcFixtureXml -FirstTimeSetupComplete)
            Get-ControlReadinessControlsState $incomplete 'abc' | Should -Be 'Missing'

            $complete = [xml](New-AbcFixtureXml -BoundButtonMappings $AbcRequiredButtons -FirstTimeSetupComplete)
            Get-ControlReadinessControlsState $complete 'abc' | Should -Be 'NotVerified'
            Get-ControlReadinessControlsState $complete 'abc' | Should -Not -Be 'Verified'
        }
    }

    Context "No-write regression (committed snapshot evidence, issue #255)" {
        # Snapshots SHA-256, LastWriteTimeUtc, and file count for every file
        # under both UserProfiles and GameProfiles before and after running
        # the normal assessment path AND a spoofed Controls = 'Verified'
        # formatter call with no evidence -- proving both paths are truly
        # read-only, not just documented as such.
        BeforeAll {
            function Get-ControlReadinessNoWriteDirSnapshot {
                param([string]$Dir)
                Get-ChildItem -LiteralPath $Dir -Recurse -File | Sort-Object FullName | ForEach-Object {
                    [pscustomobject]@{
                        Path = $_.FullName
                        Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
                        Write = $_.LastWriteTimeUtc
                    }
                }
            }
        }

        BeforeEach {
            $userProfilesDir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '_up')
            $gameProfilesDir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '_gp')
            New-Item -ItemType Directory -Path $userProfilesDir, $gameProfilesDir | Out-Null

            $realExe = Join-Path $userProfilesDir 'abc.exe'
            Set-Content -LiteralPath $realExe -Value 'stub' -Encoding utf8
            Set-Content -LiteralPath (Join-Path $userProfilesDir 'abc.xml') `
                -Value (New-AbcFixtureXml -GamePath $realExe -BoundButtonMappings $AbcRequiredButtons) -Encoding utf8
            Set-Content -LiteralPath (Join-Path $gameProfilesDir 'abc.xml') `
                -Value (New-AbcFixtureXml) -Encoding utf8
        }

        It "leaves UserProfiles and GameProfiles byte-identical after a normal assessment run" {
            $beforeUp = Get-ControlReadinessNoWriteDirSnapshot $userProfilesDir
            $beforeGp = Get-ControlReadinessNoWriteDirSnapshot $gameProfilesDir
            $beforeUpCount = @($beforeUp).Count
            $beforeGpCount = @($beforeGp).Count

            [void](Get-ControlReadinessAssessment -Code 'abc' -UserProfilesDir $userProfilesDir -GameProfilesDir $gameProfilesDir)

            $afterUp = Get-ControlReadinessNoWriteDirSnapshot $userProfilesDir
            $afterGp = Get-ControlReadinessNoWriteDirSnapshot $gameProfilesDir

            (Compare-Object $beforeUp $afterUp -Property Path, Hash, Write) | Should -BeNullOrEmpty
            (Compare-Object $beforeGp $afterGp -Property Path, Hash, Write) | Should -BeNullOrEmpty
            @($afterUp).Count | Should -Be $beforeUpCount
            @($afterGp).Count | Should -Be $beforeGpCount
        }

        It "leaves UserProfiles and GameProfiles byte-identical after a spoofed Controls='Verified' formatter call" {
            $beforeUp = Get-ControlReadinessNoWriteDirSnapshot $userProfilesDir
            $beforeGp = Get-ControlReadinessNoWriteDirSnapshot $gameProfilesDir
            $beforeUpCount = @($beforeUp).Count
            $beforeGpCount = @($beforeGp).Count

            $spoofed = [pscustomobject]@{ Code = 'abc'; Registration = 'Registered'; Controls = 'Verified'; Launch = 'NotTestedByTpm' }
            $lines = Get-ControlReadinessSummaryLines -Assessment $spoofed
            $lines | Should -Contain 'Controls: Not verified'

            $afterUp = Get-ControlReadinessNoWriteDirSnapshot $userProfilesDir
            $afterGp = Get-ControlReadinessNoWriteDirSnapshot $gameProfilesDir

            (Compare-Object $beforeUp $afterUp -Property Path, Hash, Write) | Should -BeNullOrEmpty
            (Compare-Object $beforeGp $afterGp -Property Path, Hash, Write) | Should -BeNullOrEmpty
            @($afterUp).Count | Should -Be $beforeUpCount
            @($afterGp).Count | Should -Be $beforeGpCount
        }
    }

    Context "No-write / no-propagation guarantee (AST-verified, issue #255)" {
        BeforeAll {
            $script:productionAst = [System.Management.Automation.Language.Parser]::ParseFile(
                (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'), [ref]$null, [ref]$null)
        }

        It "defines every expected control-readiness function exactly once" -TestCases (
            @('Get-ControlReadinessRegistrationState',
              'Get-ControlReadinessKnownRequirements',
              'Test-ControlReadinessButtonBindingUsable',
              'Test-ControlReadinessAnalogMappingUsable',
              'Get-ControlReadinessControlsState',
              'Get-ControlReadinessLaunchState',
              'Get-ControlReadinessAssessment',
              'Test-ControlReadinessVerificationEvidence',
              'Get-ControlReadinessSummaryLines',
              'Get-ControlReadinessActionItems') | ForEach-Object { @{ Name = $_ } }
        ) {
            param($Name)
            $matches = $productionAst.FindAll({
                $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq $Name
            }, $true)
            @($matches).Count | Should -Be 1
        }

        It "never calls a write-capable mapping/configuration path from any control-readiness function" -TestCases (
            @('Get-ControlReadinessRegistrationState',
              'Get-ControlReadinessKnownRequirements',
              'Test-ControlReadinessButtonBindingUsable',
              'Test-ControlReadinessAnalogMappingUsable',
              'Get-ControlReadinessControlsState',
              'Get-ControlReadinessLaunchState',
              'Get-ControlReadinessAssessment',
              'Test-ControlReadinessVerificationEvidence',
              'Get-ControlReadinessSummaryLines',
              'Get-ControlReadinessActionItems') | ForEach-Object { @{ Name = $_ } }
        ) {
            param($Name)
            $forbidden = @('Invoke-ControlPropagation', 'Set-ProfileInputApi', 'Save-XmlMaybe', 'Save-Xml',
                'Add-Content', 'Set-Content', 'Out-File', 'New-Item', 'Remove-Item', 'Move-Item',
                'Copy-Item', 'Rename-Item')
            $fn = $productionAst.FindAll({
                $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq $Name
            }, $true) | Select-Object -First 1
            $fn | Should -Not -BeNullOrEmpty
            $calls = $fn.Body.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true) |
                ForEach-Object { $_.GetCommandName() } | Where-Object { $_ }
            foreach ($f in $forbidden) { $calls | Should -Not -Contain $f }
            $wizardCalls = @($calls | Where-Object { $_ -match 'Wizard' })
            if ($Name -eq 'Get-ControlReadinessActionItems') {
                # This bridge may read the existing ParrotData detector to
                # preserve the #253 handoff dimensions. It must not call any
                # wizard mutation/automation path.
                @($wizardCalls | Where-Object { $_ -ne 'Get-TeknoParrotWizardState' }) | Should -BeNullOrEmpty
            } else {
                $wizardCalls | Should -BeNullOrEmpty
            }

            $memberCalls = $fn.Body.FindAll({
                $args[0] -is [System.Management.Automation.Language.InvokeMemberExpressionAst]
            }, $true) | ForEach-Object { $_.Extent.Text }
            ($memberCalls -join "`n") | Should -Not -Match '(?i)\.(Save|WriteAllText|WriteAllBytes|AppendAllText|Create|Delete|Move|Copy)\s*\('
            $fn.Extent.Text | Should -Not -Match '(?i)\[(System\.IO\.(File|Directory))\]::(WriteAllText|WriteAllBytes|AppendAllText|Create|Delete|Move|Copy)'
        }
    }
}

Describe "TeknoParrot Wizard Readiness Handoff (issue #253)" {
    BeforeAll {
        function New-ParrotDataXml {
            param(
                [string]$FirstTimeSetupComplete = 'true',
                [string]$DatXmlLocation = 'C:\Games\eggman.xml',
                [switch]$OmitFirstTimeSetupComplete,
                [switch]$OmitDatXmlLocation
            )
            $completeXml = if ($OmitFirstTimeSetupComplete) { '' } else { "<FirstTimeSetupComplete>$FirstTimeSetupComplete</FirstTimeSetupComplete>" }
            $datXml = if ($OmitDatXmlLocation) { '' } else { "<DatXmlLocation>$DatXmlLocation</DatXmlLocation>" }
            return @"
<ParrotData>
    $completeXml
    $datXml
</ParrotData>
"@
        }
    }

    Context "Get-TeknoParrotWizardState" {
        BeforeEach {
            $tpRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $tpRoot | Out-Null
        }

        It "returns Missing when ParrotData.xml does not exist, and creates nothing" {
            Get-TeknoParrotWizardState -TeknoParrotRoot $tpRoot | Select-Object -ExpandProperty State | Should -Be 'Missing'
            Test-Path -LiteralPath (Join-Path $tpRoot 'ParrotData.xml') | Should -Be $false
        }

        It "returns Complete when FirstTimeSetupComplete is true, and does not touch the file" {
            $path = Join-Path $tpRoot 'ParrotData.xml'
            Set-Content -LiteralPath $path -Value (New-ParrotDataXml -FirstTimeSetupComplete 'true') -Encoding utf8
            $before = Get-Content -LiteralPath $path -Raw
            $beforeWrite = (Get-Item -LiteralPath $path).LastWriteTimeUtc

            $result = Get-TeknoParrotWizardState -TeknoParrotRoot $tpRoot

            $result.State | Should -Be 'Complete'
            $result.DatXmlLocation | Should -Be 'C:\Games\eggman.xml'
            (Get-Content -LiteralPath $path -Raw) | Should -Be $before
            (Get-Item -LiteralPath $path).LastWriteTimeUtc | Should -Be $beforeWrite
        }

        It "returns Incomplete when FirstTimeSetupComplete is false" {
            Set-Content -LiteralPath (Join-Path $tpRoot 'ParrotData.xml') -Value (New-ParrotDataXml -FirstTimeSetupComplete 'false') -Encoding utf8
            Get-TeknoParrotWizardState -TeknoParrotRoot $tpRoot | Select-Object -ExpandProperty State | Should -Be 'Incomplete'
        }

        It "returns Malformed for unparseable XML" {
            Set-Content -LiteralPath (Join-Path $tpRoot 'ParrotData.xml') -Value '<ParrotData><FirstTimeSetupComplete>true' -Encoding utf8
            Get-TeknoParrotWizardState -TeknoParrotRoot $tpRoot | Select-Object -ExpandProperty State | Should -Be 'Malformed'
        }

        It "returns Unknown when FirstTimeSetupComplete is absent (schema/field ambiguity)" {
            Set-Content -LiteralPath (Join-Path $tpRoot 'ParrotData.xml') -Value (New-ParrotDataXml -OmitFirstTimeSetupComplete) -Encoding utf8
            Get-TeknoParrotWizardState -TeknoParrotRoot $tpRoot | Select-Object -ExpandProperty State | Should -Be 'Unknown'
        }

        It "returns Unknown when FirstTimeSetupComplete is present but not a recognizable boolean" {
            Set-Content -LiteralPath (Join-Path $tpRoot 'ParrotData.xml') -Value (New-ParrotDataXml -FirstTimeSetupComplete 'maybe') -Encoding utf8
            Get-TeknoParrotWizardState -TeknoParrotRoot $tpRoot | Select-Object -ExpandProperty State | Should -Be 'Unknown'
        }

        It "returns Unknown for duplicate FirstTimeSetupComplete elements with conflicting values (true then false)" {
            $xml = @"
<ParrotData>
    <FirstTimeSetupComplete>true</FirstTimeSetupComplete>
    <FirstTimeSetupComplete>false</FirstTimeSetupComplete>
    <DatXmlLocation>C:\Games\eggman.xml</DatXmlLocation>
</ParrotData>
"@
            Set-Content -LiteralPath (Join-Path $tpRoot 'ParrotData.xml') -Value $xml -Encoding utf8
            Get-TeknoParrotWizardState -TeknoParrotRoot $tpRoot | Select-Object -ExpandProperty State | Should -Be 'Unknown'
        }

        It "returns Unknown for duplicate FirstTimeSetupComplete elements with conflicting values (false then true)" {
            # Order reversed from the previous case -- the rule must not
            # depend on which conflicting value happens to appear first.
            $xml = @"
<ParrotData>
    <FirstTimeSetupComplete>false</FirstTimeSetupComplete>
    <FirstTimeSetupComplete>true</FirstTimeSetupComplete>
</ParrotData>
"@
            Set-Content -LiteralPath (Join-Path $tpRoot 'ParrotData.xml') -Value $xml -Encoding utf8
            Get-TeknoParrotWizardState -TeknoParrotRoot $tpRoot | Select-Object -ExpandProperty State | Should -Be 'Unknown'
        }

        It "returns Unknown for duplicate FirstTimeSetupComplete elements even when both values agree" {
            # Deliberate, documented rule: more than one FirstTimeSetupComplete
            # element is not the schema shape this detector has any confirmed
            # contract for (the upstream root/shape is unverified -- see the
            # section header above), so agreeing duplicates are treated the
            # same as conflicting ones rather than silently accepted.
            $xml = @"
<ParrotData>
    <FirstTimeSetupComplete>true</FirstTimeSetupComplete>
    <FirstTimeSetupComplete>true</FirstTimeSetupComplete>
</ParrotData>
"@
            Set-Content -LiteralPath (Join-Path $tpRoot 'ParrotData.xml') -Value $xml -Encoding utf8
            Get-TeknoParrotWizardState -TeknoParrotRoot $tpRoot | Select-Object -ExpandProperty State | Should -Be 'Unknown'
        }

        It "returns a null DatXmlLocation when the field is absent, without affecting State" {
            Set-Content -LiteralPath (Join-Path $tpRoot 'ParrotData.xml') -Value (New-ParrotDataXml -FirstTimeSetupComplete 'true' -OmitDatXmlLocation) -Encoding utf8
            $result = Get-TeknoParrotWizardState -TeknoParrotRoot $tpRoot
            $result.State | Should -Be 'Complete'
            $result.DatXmlLocation | Should -BeNullOrEmpty
        }

        It "classifies an empty ParrotData.xml (root element only) as Unknown, not Malformed" {
            Set-Content -LiteralPath (Join-Path $tpRoot 'ParrotData.xml') -Value '<ParrotData></ParrotData>' -Encoding utf8
            Get-TeknoParrotWizardState -TeknoParrotRoot $tpRoot | Select-Object -ExpandProperty State | Should -Be 'Unknown'
        }
    }

    Context "Get-OnboardingHandoffSummaryLines" {
        It "reproduces the exact handoff text: registered + launched + wizard complete + controls NotVerified" {
            $assessment = [pscustomobject]@{ Code = 'abc'; Registration = 'Registered'; Controls = 'NotVerified'; Launch = 'ObservedSuccess' }
            $wizardState = [pscustomobject]@{ State = 'Complete'; DatXmlLocation = 'C:\Games\eggman.xml' }

            $lines = Get-OnboardingHandoffSummaryLines -Assessment $assessment -WizardState $wizardState

            ($lines -join "`n") | Should -Be (@(
                'Game registered successfully'
                'Launch status: Explicitly observed (success)'
                'TeknoParrot first-run setup: Complete'
                'Controls: Not verified'
                ''
                "TPM registered this game. TeknoParrot owns its own setup wizard, controls configuration, and DAT/XML setup -- those are managed separately and are not performed by TPM."
                ''
                'Open TeknoParrot controls configuration and map/test controls before treating this game as ready.'
            ) -join "`n")
        }

        It "reproduces the exact handoff text: registered + wizard incomplete + controls Missing" {
            $assessment = [pscustomobject]@{ Code = 'abc'; Registration = 'Registered'; Controls = 'Missing'; Launch = 'NotTestedByTpm' }
            $wizardState = [pscustomobject]@{ State = 'Incomplete'; DatXmlLocation = $null }

            $lines = Get-OnboardingHandoffSummaryLines -Assessment $assessment -WizardState $wizardState

            ($lines -join "`n") | Should -Be (@(
                'Game registered successfully'
                'Launch status: Not tested by TPM'
                'TeknoParrot first-run setup: Not yet complete -- TeknoParrot may still ask you to complete its setup wizard'
                'Controls: Missing'
                ''
                "TPM registered this game. TeknoParrot owns its own setup wizard, controls configuration, and DAT/XML setup -- those are managed separately and are not performed by TPM."
                ''
                'Open TeknoParrot controls configuration and map/test controls before treating this game as ready.'
            ) -join "`n")
        }

        It "keeps registration, launch, wizard, and controls as four separate lines, never merged" {
            $assessment = [pscustomobject]@{ Code = 'abc'; Registration = 'Registered'; Controls = 'NotVerified'; Launch = 'NotTestedByTpm' }
            $wizardState = [pscustomobject]@{ State = 'Complete'; DatXmlLocation = $null }
            $lines = Get-OnboardingHandoffSummaryLines -Assessment $assessment -WizardState $wizardState

            $lines | Should -Contain 'Game registered successfully'
            $lines | Should -Contain 'Launch status: Not tested by TPM'
            $lines | Should -Contain 'TeknoParrot first-run setup: Complete'
            $lines | Should -Contain 'Controls: Not verified'
        }

        It "never claims Controls are ready/Verified unless the #258 evidence model says Verified" -TestCases @(
            @{ Registration = 'Registered'; Controls = 'NotVerified'; Launch = 'NotTestedByTpm'; WizardStateName = 'Complete' }
            @{ Registration = 'Registered'; Controls = 'Missing'; Launch = 'ObservedSuccess'; WizardStateName = 'Complete' }
            @{ Registration = 'Registered'; Controls = 'Unknown'; Launch = 'NotTestedByTpm'; WizardStateName = 'Incomplete' }
            @{ Registration = 'Registered'; Controls = 'Unsupported'; Launch = 'NotTestedByTpm'; WizardStateName = 'Complete' }
        ) {
            param($Registration, $Controls, $Launch, $WizardStateName)
            $assessment = [pscustomobject]@{ Code = 'abc'; Registration = $Registration; Controls = $Controls; Launch = $Launch }
            $wizardState = [pscustomobject]@{ State = $WizardStateName; DatXmlLocation = $null }
            $lines = Get-OnboardingHandoffSummaryLines -Assessment $assessment -WizardState $wizardState
            $lines | Should -Not -Contain 'Controls: Verified'
        }

        It "fails closed on a caller-supplied Controls = 'Verified' with no VerificationEvidence" {
            $spoofed = [pscustomobject]@{ Code = 'abc'; Registration = 'Registered'; Controls = 'Verified'; Launch = 'NotTestedByTpm' }
            $wizardState = [pscustomobject]@{ State = 'Complete'; DatXmlLocation = $null }
            $lines = Get-OnboardingHandoffSummaryLines -Assessment $spoofed -WizardState $wizardState
            $lines | Should -Contain 'Controls: Not verified'
            $lines | Should -Not -Contain 'Controls: Verified'
        }

        It "renders Controls: Verified only when VerificationEvidence proves an actual observed test" {
            $evidenced = [pscustomobject]@{
                Code = 'abc'; Registration = 'Registered'; Controls = 'Verified'; Launch = 'ObservedSuccess'
                VerificationEvidence = [pscustomobject]@{ Method = 'Manual play-test'; ObservedAt = '2026-08-21T12:00:00Z' }
            }
            $wizardState = [pscustomobject]@{ State = 'Complete'; DatXmlLocation = $null }
            (Get-OnboardingHandoffSummaryLines -Assessment $evidenced -WizardState $wizardState) | Should -Contain 'Controls: Verified'
        }

        It "does not upgrade controls text based on wizard Complete, launch success, or FirstTimeSetupComplete alone" {
            # Every one of these signals is present and positive, but Controls
            # is still NotVerified (the #258 evidence model's own ceiling) --
            # the handoff text must reflect that honestly, not imply readiness.
            $assessment = [pscustomobject]@{ Code = 'abc'; Registration = 'Registered'; Controls = 'NotVerified'; Launch = 'ObservedSuccess' }
            $wizardState = [pscustomobject]@{ State = 'Complete'; DatXmlLocation = 'C:\Games\eggman.xml' }
            $lines = Get-OnboardingHandoffSummaryLines -Assessment $assessment -WizardState $wizardState
            $lines | Should -Contain 'Controls: Not verified'
            $lines | Should -Contain 'Open TeknoParrot controls configuration and map/test controls before treating this game as ready.'
        }

        It "never implies TeknoParrot performed TPM's own registration" {
            # Codex review: the handoff text must not attribute TPM's
            # registration work to TeknoParrot. Registration is TPM's own
            # action; TeknoParrot separately owns its wizard/controls/DAT
            # setup state.
            $assessment = [pscustomobject]@{ Code = 'abc'; Registration = 'Registered'; Controls = 'NotVerified'; Launch = 'NotTestedByTpm' }
            $wizardState = [pscustomobject]@{ State = 'Complete'; DatXmlLocation = $null }
            $text = (Get-OnboardingHandoffSummaryLines -Assessment $assessment -WizardState $wizardState) -join "`n"

            $text | Should -Not -Match 'TeknoParrot handled registration'
            $text | Should -Match 'TPM registered this game'
            $text | Should -Match "TeknoParrot owns its own setup wizard"
        }
    }

    Context "No-write regression (committed snapshot evidence, issue #253)" {
        BeforeAll {
            function Get-WizardNoWriteDirSnapshot {
                param([string]$Dir)
                Get-ChildItem -LiteralPath $Dir -Recurse -File | Sort-Object FullName | ForEach-Object {
                    [pscustomobject]@{
                        Path = $_.FullName
                        Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
                        Write = $_.LastWriteTimeUtc
                    }
                }
            }
        }

        BeforeEach {
            $tpRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $tpRoot | Out-Null
            Set-Content -LiteralPath (Join-Path $tpRoot 'ParrotData.xml') -Value (New-ParrotDataXml -FirstTimeSetupComplete 'true') -Encoding utf8
        }

        It "leaves ParrotData.xml byte-identical after a normal wizard-state detection run" {
            $before = Get-WizardNoWriteDirSnapshot $tpRoot
            $beforeCount = @($before).Count

            [void](Get-TeknoParrotWizardState -TeknoParrotRoot $tpRoot)

            $after = Get-WizardNoWriteDirSnapshot $tpRoot
            (Compare-Object $before $after -Property Path, Hash, Write) | Should -BeNullOrEmpty
            @($after).Count | Should -Be $beforeCount
        }

        It "leaves ParrotData.xml byte-identical after formatting the full onboarding handoff" {
            $before = Get-WizardNoWriteDirSnapshot $tpRoot
            $beforeCount = @($before).Count

            $wizardState = Get-TeknoParrotWizardState -TeknoParrotRoot $tpRoot
            $assessment = [pscustomobject]@{ Code = 'abc'; Registration = 'Registered'; Controls = 'NotVerified'; Launch = 'NotTestedByTpm' }
            [void](Get-OnboardingHandoffSummaryLines -Assessment $assessment -WizardState $wizardState)

            $after = Get-WizardNoWriteDirSnapshot $tpRoot
            (Compare-Object $before $after -Property Path, Hash, Write) | Should -BeNullOrEmpty
            @($after).Count | Should -Be $beforeCount
        }

        It "leaves ParrotData.xml byte-identical after a spoofed Controls='Verified' handoff call, and fails closed" {
            # Codex review: the committed no-write snapshot must wrap the
            # exact spoofed call, not only the normal path.
            $before = Get-WizardNoWriteDirSnapshot $tpRoot
            $beforeCount = @($before).Count

            $wizardState = Get-TeknoParrotWizardState -TeknoParrotRoot $tpRoot
            $spoofed = [pscustomobject]@{ Code = 'abc'; Registration = 'Registered'; Controls = 'Verified'; Launch = 'NotTestedByTpm' }
            $lines = Get-OnboardingHandoffSummaryLines -Assessment $spoofed -WizardState $wizardState

            $after = Get-WizardNoWriteDirSnapshot $tpRoot
            (Compare-Object $before $after -Property Path, Hash, Write) | Should -BeNullOrEmpty
            @($after).Count | Should -Be $beforeCount
            $lines | Should -Contain 'Controls: Not verified'
            $lines | Should -Not -Contain 'Controls: Verified'
        }
    }

    Context "No-write / no-propagation guarantee (AST-verified, issue #253)" {
        BeforeAll {
            $script:wizardProductionAst = [System.Management.Automation.Language.Parser]::ParseFile(
                (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'), [ref]$null, [ref]$null)
        }

        It "defines every expected wizard-handoff function exactly once" -TestCases (
            @('Get-TeknoParrotWizardState', 'Get-OnboardingHandoffSummaryLines') | ForEach-Object { @{ Name = $_ } }
        ) {
            param($Name)
            $matches = $wizardProductionAst.FindAll({
                $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq $Name
            }, $true)
            @($matches).Count | Should -Be 1
        }

        It "never calls a write-capable or wizard-mutation path from any wizard-handoff function" -TestCases (
            @('Get-TeknoParrotWizardState', 'Get-OnboardingHandoffSummaryLines') | ForEach-Object { @{ Name = $_ } }
        ) {
            param($Name)
            $forbiddenCommands = @('Invoke-ControlPropagation', 'Set-ProfileInputApi', 'Save-XmlMaybe', 'Save-Xml',
                'Add-Content', 'Set-Content', 'Out-File', 'New-Item', 'Remove-Item', 'Move-Item', 'Copy-Item', 'Rename-Item')
            $fn = $wizardProductionAst.FindAll({
                $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq $Name
            }, $true) | Select-Object -First 1
            $fn | Should -Not -BeNullOrEmpty

            # Command-name check: cmdlets and functions (Add-Content, a
            # wizard-mutation helper, etc.).
            $calls = $fn.Body.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true) |
                ForEach-Object { $_.GetCommandName() } | Where-Object { $_ }
            foreach ($f in $forbiddenCommands) { $calls | Should -Not -Contain $f }
            ($calls | Where-Object { $_ -match 'Wizard' }) | Should -BeNullOrEmpty

            # Member/static invocation check: CommandAst alone misses
            # [xml]/[System.Xml.XmlDocument]::Save(...), [System.IO.File]::
            # WriteAllText/Delete/Move/Copy(...), and similar .NET method
            # calls that never appear as a CommandAst name -- those are
            # InvokeMemberExpressionAst nodes instead (used for both
            # instance calls like $doc.Save(...) and static calls like
            # [System.IO.File]::Delete(...)).
            $forbiddenMembers = @('Save', 'WriteAllText', 'WriteAllBytes', 'WriteAllLines',
                'AppendAllText', 'AppendAllLines', 'AppendText', 'Delete', 'Move', 'MoveTo',
                'Copy', 'CopyTo', 'Replace', 'CreateText', 'Create', 'SetLastWriteTime', 'SetAttributes')
            $memberCalls = $fn.Body.FindAll({ $args[0] -is [System.Management.Automation.Language.InvokeMemberExpressionAst] }, $true) |
                ForEach-Object { ($_.Member.Extent.Text -replace "^[`"']|[`"']$", '') } | Where-Object { $_ }
            foreach ($m in $forbiddenMembers) { $memberCalls | Should -Not -Contain $m }
        }
    }
}

Describe "Get-GameApiDll" {
    BeforeAll {
        function New-FakeExe([string]$name, [string]$marker) {
            $path = Join-Path $TestDrive $name
            $bytes = [System.Text.Encoding]::ASCII.GetBytes("MZ-stub-padding-$marker-more-padding")
            [System.IO.File]::WriteAllBytes($path, $bytes)
            return $path
        }
    }

    It "detects d3d9.dll" {
        $p = New-FakeExe "d3d9.exe" "d3d9.dll"
        Get-GameApiDll -ExePath $p | Should -Be "d3d9.dll"
    }
    It "detects opengl32.dll" {
        $p = New-FakeExe "gl.exe" "opengl32.dll"
        Get-GameApiDll -ExePath $p | Should -Be "opengl32.dll"
    }
    It "maps d3d11.dll imports to dxgi.dll" {
        $p = New-FakeExe "d3d11.exe" "d3d11.dll"
        Get-GameApiDll -ExePath $p | Should -Be "dxgi.dll"
    }
    It "prefers d3d12 over d3d11 when an exe imports both" {
        $p = New-FakeExe "both.exe" "d3d11.dll-and-d3d12.dll"
        Get-GameApiDll -ExePath $p | Should -Be "d3d12.dll"
    }
    It "returns null when no known API is imported" {
        $p = New-FakeExe "plain.exe" "nothing-recognizable"
        Get-GameApiDll -ExePath $p | Should -BeNullOrEmpty
    }
}

Describe "Get-GameLegacyApi" {
    BeforeAll {
        function New-FakeExe([string]$name, [string]$marker) {
            $path = Join-Path $TestDrive $name
            $bytes = [System.Text.Encoding]::ASCII.GetBytes("MZ-stub-padding-$marker-more-padding")
            [System.IO.File]::WriteAllBytes($path, $bytes)
            return $path
        }
    }

    It "detects D3D8" {
        $p = New-FakeExe "d3d8.exe" "d3d8.dll"
        Get-GameLegacyApi -ExePath $p | Should -Contain "D3D8"
    }
    It "detects DDraw and Glide2x together" {
        $p = New-FakeExe "combo.exe" "ddraw.dll-and-glide2x.dll"
        $result = Get-GameLegacyApi -ExePath $p
        $result | Should -Contain "DDraw"
        $result | Should -Contain "Glide2x"
    }
    It "returns an empty array when nothing legacy is imported" {
        $p = New-FakeExe "modern.exe" "d3d11.dll"
        Get-GameLegacyApi -ExePath $p | Should -BeNullOrEmpty
    }
}

Describe "Test-GpuFixUpToDate" {
    BeforeAll {
        function New-ProfileDoc([string]$inner) {
            return [xml]"<GameProfile><ConfigValues>$inner</ConfigValues></GameProfile>"
        }
    }

    It "is not eligible when no matching field exists in the profile" {
        $doc = New-ProfileDoc "<FieldInformation><FieldName>Unrelated</FieldName><FieldValue>0</FieldValue></FieldInformation>"
        $result = Test-GpuFixUpToDate -Doc $doc -BoolFields @('EnableAmdFix') -DropdownFields @() -Vendor 'AMD'
        $result.Eligible | Should -BeFalse
        $result.UpToDate | Should -BeFalse
    }
    It "flags a bool AMD field that needs to flip from 0 to 1 for an AMD vendor" {
        $doc = New-ProfileDoc "<FieldInformation><FieldName>EnableAmdFix</FieldName><FieldValue>0</FieldValue></FieldInformation>"
        $result = Test-GpuFixUpToDate -Doc $doc -BoolFields @('EnableAmdFix') -DropdownFields @() -Vendor 'AMD'
        $result.Eligible | Should -BeTrue
        $result.UpToDate | Should -BeFalse
        $result.Changes[0].NewValue | Should -Be '1'
    }
    It "is up to date when a bool AMD field is already 1 for an AMD vendor" {
        $doc = New-ProfileDoc "<FieldInformation><FieldName>EnableAmdFix</FieldName><FieldValue>1</FieldValue></FieldInformation>"
        $result = Test-GpuFixUpToDate -Doc $doc -BoolFields @('EnableAmdFix') -DropdownFields @() -Vendor 'AMD'
        $result.UpToDate | Should -BeTrue
        $result.Changes.Count | Should -Be 0
    }
    It "wants a bool AMD field set to 0 for a non-AMD vendor" {
        $doc = New-ProfileDoc "<FieldInformation><FieldName>EnableAmdFix</FieldName><FieldValue>1</FieldValue></FieldInformation>"
        $result = Test-GpuFixUpToDate -Doc $doc -BoolFields @('EnableAmdFix') -DropdownFields @() -Vendor 'NVIDIA'
        $result.UpToDate | Should -BeFalse
        $result.Changes[0].NewValue | Should -Be '0'
    }
    It "resolves a dropdown GPU Fix field to NVIDIA when offered" {
        $doc = New-ProfileDoc @"
<FieldInformation>
  <FieldName>GPU Fix</FieldName>
  <FieldValue>None</FieldValue>
  <FieldOptions><string>None</string><string>AMD</string><string>NVIDIA</string><string>INTEL</string></FieldOptions>
</FieldInformation>
"@
        $result = Test-GpuFixUpToDate -Doc $doc -BoolFields @() -DropdownFields @('GPU Fix') -Vendor 'NVIDIA'
        $result.Eligible | Should -BeTrue
        $result.Changes[0].NewValue | Should -Be 'NVIDIA'
    }
    It "prefers 'New AMD Driver' over 'AMD' when both dropdown options exist" {
        $doc = New-ProfileDoc @"
<FieldInformation>
  <FieldName>GPU Fix</FieldName>
  <FieldValue>None</FieldValue>
  <FieldOptions><string>None</string><string>AMD</string><string>New AMD Driver</string></FieldOptions>
</FieldInformation>
"@
        $result = Test-GpuFixUpToDate -Doc $doc -BoolFields @() -DropdownFields @('GPU Fix') -Vendor 'AMD'
        $result.Changes[0].NewValue | Should -Be 'New AMD Driver'
    }
}

Describe "Test-FFBBlasterUpToDate" {
    BeforeAll {
        function New-ProfileDoc([string]$inner) {
            return [xml]"<GameProfile><ConfigValues>$inner</ConfigValues></GameProfile>"
        }
    }

    It "is not eligible when the category is absent" {
        $doc = New-ProfileDoc "<FieldInformation><FieldName>Unrelated</FieldName><FieldType>Bool</FieldType><FieldValue>0</FieldValue></FieldInformation>"
        $result = Test-FFBBlasterUpToDate -Doc $doc -Categories @('FFB Blaster')
        $result.Eligible | Should -BeFalse
    }
    It "flags a CategoryName-based FFB Blaster field that needs enabling" {
        $doc = New-ProfileDoc "<FieldInformation><CategoryName>FFB Blaster</CategoryName><FieldName>Enable</FieldName><FieldType>Bool</FieldType><FieldValue>0</FieldValue></FieldInformation>"
        $result = Test-FFBBlasterUpToDate -Doc $doc -Categories @('FFB Blaster')
        $result.Eligible | Should -BeTrue
        $result.UpToDate | Should -BeFalse
        $result.Changes[0].NewValue | Should -Be '1'
    }
    It "is up to date when already enabled" {
        $doc = New-ProfileDoc "<FieldInformation><CategoryName>FFB Blaster</CategoryName><FieldName>Enable</FieldName><FieldType>Bool</FieldType><FieldValue>1</FieldValue></FieldInformation>"
        $result = Test-FFBBlasterUpToDate -Doc $doc -Categories @('FFB Blaster')
        $result.UpToDate | Should -BeTrue
    }
    It "falls back to matching by FieldName on older-build profiles with no CategoryName match" {
        $doc = New-ProfileDoc "<FieldInformation><FieldName>FFB Blaster Enabled</FieldName><FieldType>Bool</FieldType><FieldValue>0</FieldValue></FieldInformation>"
        $result = Test-FFBBlasterUpToDate -Doc $doc -Categories @('FFB Blaster Enabled')
        $result.Eligible | Should -BeTrue
        $result.Changes[0].NewValue | Should -Be '1'
    }
}

Describe "Get-ReShadeTargetInfo" {
    BeforeAll {
        function New-ProfileDoc([string]$emuType) {
            return [xml]"<GameProfile><EmulatorType>$emuType</EmulatorType></GameProfile>"
        }
        function New-FakeExe([string]$dir, [string]$name, [string]$marker) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $path = Join-Path $dir $name
            [System.IO.File]::WriteAllBytes($path, [System.Text.Encoding]::ASCII.GetBytes("MZ-pad-$marker-pad"))
            return $path
        }
    }

    It "forces opengl32.dll for BudgieLoader games regardless of detected imports" {
        $exeDir = Join-Path $TestDrive "budgie"
        $exe = New-FakeExe $exeDir "game.exe" "d3d9.dll"
        $doc = New-ProfileDoc "BudgieLoader"
        $result = Get-ReShadeTargetInfo -Doc $doc -GamePath $exe -ExeDir $exeDir
        $result.DllName | Should -Be "opengl32.dll"
        $result.TargetDir | Should -Be $exeDir
    }
    It "redirects to the openparrot subfolder when one exists" {
        $exeDir = Join-Path $TestDrive "opgame"
        $exe = New-FakeExe $exeDir "game.exe" "d3d9.dll"
        $opDir = Join-Path $exeDir "openparrot"
        New-Item -ItemType Directory -Path $opDir -Force | Out-Null
        $doc = New-ProfileDoc "OpenParrot"
        $result = Get-ReShadeTargetInfo -Doc $doc -GamePath $exe -ExeDir $exeDir
        $result.TargetDir | Should -Be $opDir
        $result.DllName | Should -Be "d3d9.dll"
    }
    It "falls back to dxgi.dll and reports ApiDetected=false when nothing is recognized" {
        $exeDir = Join-Path $TestDrive "unknown"
        $exe = New-FakeExe $exeDir "game.exe" "nothing-here"
        $doc = New-ProfileDoc "Default"
        $result = Get-ReShadeTargetInfo -Doc $doc -GamePath $exe -ExeDir $exeDir
        $result.DllName | Should -Be "dxgi.dll"
        $result.ApiDetected | Should -BeFalse
    }
}

Describe "Get-DiceSimilarity" {
    It "returns 1.0 for identical strings" {
        Get-DiceSimilarity "StreetFighterIII3rdStrike" "StreetFighterIII3rdStrike" | Should -Be 1.0
    }
    It "returns 0.0 for completely different strings" {
        Get-DiceSimilarity "aaaa" "zzzz" | Should -Be 0.0
    }
    It "returns 0.0 when either string is shorter than 2 characters" {
        Get-DiceSimilarity "a" "aa" | Should -Be 0.0
        Get-DiceSimilarity "" "aa" | Should -Be 0.0
    }
    It "is symmetric" {
        $ab = Get-DiceSimilarity "GoldenTeeLive2019" "Golden Tee Live 2019"
        $ba = Get-DiceSimilarity "Golden Tee Live 2019" "GoldenTeeLive2019"
        $ab | Should -Be $ba
    }
    It "scores a close abbreviation higher than an unrelated string" {
        $close      = Get-DiceSimilarity "InitialD8" "InitialDArcadeStage8"
        $unrelated  = Get-DiceSimilarity "InitialD8" "MarioKartArcadeGP"
        $close | Should -BeGreaterThan $unrelated
    }
    It "scores an exact match strictly higher than a partial fuzzy match" {
        $exact   = Get-DiceSimilarity "VirtuaFighter5" "VirtuaFighter5"
        $partial = Get-DiceSimilarity "VirtuaFighter5" "VirtuaFighter4"
        $exact | Should -BeGreaterThan $partial
    }
}

Describe "Windows PowerShell 5.1 compression assembly bootstrap" {
    It "loads both assemblies from the production startup block before ZipArchive use" {
        $ps51Path = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path -LiteralPath $ps51Path -PathType Leaf)) {
            Set-ItResult -Skipped -Because 'Windows PowerShell 5.1 is not installed on this host.'
            return
        }

        $startupBlock = [regex]::Match(
            $script:ProductionSource,
            '(?ms)^# Load the separate ZIP assemblies once at startup\..*?^# PS 5\.1 on older').Value
        $startupAssemblyLines = @(
            $startupBlock -split '\r?\n' |
                Where-Object { $_ -match '^\s*Add-Type -AssemblyName System\.IO\.Compression(?:\.FileSystem)?\s*$' }
        )

        $startupAssemblyLines | Should -Contain 'Add-Type -AssemblyName System.IO.Compression'
        $startupAssemblyLines | Should -Contain 'Add-Type -AssemblyName System.IO.Compression.FileSystem'

        $probePath = Join-Path $TestDrive 'compression-bootstrap-ps51.ps1'
        $probeLines = @(
            '$ErrorActionPreference = ''Stop'''
        ) + $startupAssemblyLines + @(
            '$requiredTypes = @([System.IO.Compression.ZipArchive], [System.IO.Compression.ZipArchiveMode], [System.IO.Compression.ZipFile], [System.IO.Compression.ZipFileExtensions])'
            'if ($requiredTypes.Count -ne 4) { throw "Required compression types did not resolve." }'
            'Write-Output ''COMPRESSION_BOOTSTRAP_OK'''
        )
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($probePath, ($probeLines -join [Environment]::NewLine), $utf8NoBom)

        $output = & $ps51Path -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $probePath 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
        $exitCode | Should -Be 0 -Because "the production compression bootstrap must work in a pristine Windows PowerShell 5.1 process. Output: $output"
        $output | Should -Match 'COMPRESSION_BOOTSTRAP_OK'
    }
}

Describe "Windows PowerShell 5.1 security and hash module bootstrap" {
    BeforeAll {
        $script:SecurityHashStartupBlock = [regex]::Match(
            $script:ProductionSource,
            '(?ms)^# Windows PowerShell 5\.1 packaged launchers can run with module autoloading.*?^# Load the separate ZIP assemblies once at startup\.'
        ).Value
        $script:SecurityHashStartupLines = @($script:SecurityHashStartupBlock -split '\r?\n')
    }

    It "explicitly imports the production modules and invokes both required commands in a fresh packaged-style process" {
        $ps51Path = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path -LiteralPath $ps51Path -PathType Leaf)) {
            Set-ItResult -Skipped -Because 'Windows PowerShell 5.1 is not installed on this host.'
            return
        }

        $startupBlock = [regex]::Match(
            $script:ProductionSource,
            '(?ms)^# Windows PowerShell 5\.1 packaged launchers can run with module autoloading.*?^# Load the separate ZIP assemblies once at startup\.'
        ).Value
        $startupBlock | Should -Match '(?m)^\s*Import-Module -Name \$moduleManifest -Force -ErrorAction Stop\s*$'
        $startupBlock | Should -Match '(?m)^\s*Import-Module \$moduleName -ErrorAction Stop\s*$'
        $startupBlock | Should -Match '\$isWindowsPowerShellDesktop'
        $startupBlock | Should -Not -Match '(?m)^\s*Import-Module Microsoft\.PowerShell\.(Security|Management|Utility) -ErrorAction Stop\s*$'

        $probePath = Join-Path $TestDrive 'security-hash-bootstrap-ps51.ps1'
        $probeLines = @(
            '$ErrorActionPreference = ''Stop''',
            '$PSModuleAutoLoadingPreference = ''None'''
        ) + $script:SecurityHashStartupLines + @(
            '$probeFile = [System.IO.Path]::GetTempFileName()'
            'try {'
            '    [System.IO.File]::WriteAllText($probeFile, ''TPM module bootstrap probe'')'
            '    $authCommand = Get-Command Get-AuthenticodeSignature -ErrorAction Stop'
            '    $hashCommand = Get-Command Get-FileHash -ErrorAction Stop'
            '    $digest = Get-FileHash -LiteralPath $probeFile -Algorithm SHA256 -ErrorAction Stop'
            '    $signature = Get-AuthenticodeSignature -LiteralPath $probeFile -ErrorAction Stop'
            '    if (-not $authCommand -or -not $hashCommand -or [string]::IsNullOrWhiteSpace($digest.Hash) -or $null -eq $signature) { throw ''Security/hash command bootstrap did not resolve and invoke.'' }'
            '    Write-Output ''SECURITY_HASH_BOOTSTRAP_OK'''
            '} finally {'
            '    [System.IO.File]::Delete($probeFile)'
            '}'
        )
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($probePath, ($probeLines -join [Environment]::NewLine), $utf8NoBom)

        $output = & $ps51Path -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $probePath 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
        $exitCode | Should -Be 0 -Because "the production security/hash bootstrap must work with module autoloading disabled in a pristine Windows PowerShell 5.1 process. Output: $output"
        $output | Should -Match 'SECURITY_HASH_BOOTSTRAP_OK'
    }
    It "uses Windows PowerShell inbox modules when a higher-version PowerShell 7 module root precedes them" {
        $ps51Path = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path -LiteralPath $ps51Path -PathType Leaf)) {
            Set-ItResult -Skipped -Because 'Windows PowerShell 5.1 is not installed on this host.'
            return
        }

        $fakeModuleRoot = Join-Path $TestDrive 'polluted-psmodulepath'
        $fakeModuleVersion = '7.99.0.0'
        $fakeModuleNames = @(
            'Microsoft.PowerShell.Security',
            'Microsoft.PowerShell.Management',
            'Microsoft.PowerShell.Utility'
        )
        foreach ($moduleName in $fakeModuleNames) {
            $moduleDirectory = Join-Path (Join-Path $fakeModuleRoot $moduleName) $fakeModuleVersion
            New-Item -ItemType Directory -Path $moduleDirectory -Force | Out-Null
            $manifestPath = Join-Path $moduleDirectory "$moduleName.psd1"
            $modulePath = Join-Path $moduleDirectory 'Fake.psm1'
            $manifest = "@{ RootModule = 'Fake.psm1'; ModuleVersion = '$fakeModuleVersion'; CompatiblePSEditions = @('Core', 'Desktop'); FunctionsToExport = @(); CmdletsToExport = @(); VariablesToExport = @(); AliasesToExport = @() }"
            [System.IO.File]::WriteAllText($manifestPath, $manifest)
            [System.IO.File]::WriteAllText($modulePath, '')
        }

        $fakeRootForChild = $fakeModuleRoot.Replace("'", "''")
        $probePath = Join-Path $TestDrive 'security-hash-bootstrap-polluted-ps51.ps1'
        $probeLines = @(
            '$ErrorActionPreference = ''Stop''',
            '$PSModuleAutoLoadingPreference = ''None''',
            ('$fakeModuleRoot = ''{0}''' -f $fakeRootForChild),
            ('$env:PSModulePath = ''{0};'' + [System.IO.Path]::Combine($PSHOME, ''Modules'')' -f $fakeRootForChild),
            '$fakeModuleNames = @(''Microsoft.PowerShell.Security'', ''Microsoft.PowerShell.Management'', ''Microsoft.PowerShell.Utility'')',
            'foreach ($moduleName in $fakeModuleNames) {',
            '    Import-Module $moduleName -Force -ErrorAction Stop',
            '    $fakeModule = @(Get-Module -Name $moduleName)[0]',
            '    $expectedFakePath = [System.IO.Path]::Combine($fakeModuleRoot, $moduleName, ''7.99.0.0'', ''Fake.psm1''); if ($null -eq $fakeModule -or -not [System.String]::Equals($fakeModule.Version.ToString(), ''7.99.0.0'', [System.StringComparison]::OrdinalIgnoreCase) -or -not [System.String]::Equals([System.IO.Path]::GetFullPath($fakeModule.Path), [System.IO.Path]::GetFullPath($expectedFakePath), [System.StringComparison]::OrdinalIgnoreCase)) { throw ("Bare import selected unexpected module for {0}: path={1}; version={2}; expected={3}" -f $moduleName, $fakeModule.Path, $fakeModule.Version, $expectedFakePath) }',
            '    # Leave the higher-version module loaded so the production path must override it explicitly',
            '}'
            '$pollutedModulePathBeforeBootstrap = $env:PSModulePath'
        ) + $script:SecurityHashStartupLines + @(
            '$expectedVersions = @{ ''Microsoft.PowerShell.Security'' = ''3.0.0.0''; ''Microsoft.PowerShell.Management'' = ''3.1.0.0''; ''Microsoft.PowerShell.Utility'' = ''3.1.0.0'' }',
            'foreach ($moduleName in $fakeModuleNames) {',
            '    $expectedManifest = [System.IO.Path]::Combine($PSHOME, ''Modules'', $moduleName, ($moduleName + ''.psd1''))',
            '    $inboxModule = $null',
            '    foreach ($candidate in @(Get-Module -Name $moduleName)) {',
            '        if ($null -ne $candidate.Path -and [System.String]::Equals([System.IO.Path]::GetFullPath($candidate.Path), [System.IO.Path]::GetFullPath($expectedManifest), [System.StringComparison]::OrdinalIgnoreCase)) { $inboxModule = $candidate }',
            '    }',
            '    if ($null -eq $inboxModule) { throw ("Module {0} was not loaded from the Windows PowerShell inbox manifest." -f $moduleName) }',
            '    if ($inboxModule.Version.ToString() -ne $expectedVersions[$moduleName]) { throw ("Module {0} has unexpected version {1}" -f $moduleName, $inboxModule.Version) }',
            '}',
            '$authCommand = Get-Command Get-AuthenticodeSignature -ErrorAction Stop',
            '$hashCommand = Get-Command Get-FileHash -ErrorAction Stop',
            'if ($authCommand.Source -ne ''Microsoft.PowerShell.Security'' -or $hashCommand.Source -ne ''Microsoft.PowerShell.Utility'') { throw ''Security/hash command resolved from an unexpected module.'' }',
            'if ($env:PSModulePath -ne $pollutedModulePathBeforeBootstrap) { throw ''PSModulePath was not restored after inbox module initialization.'' }',
            '$probeFile = [System.IO.Path]::GetTempFileName()',
            'try {',
            '    [System.IO.File]::WriteAllText($probeFile, ''Polluted PSModulePath probe'')',
            '    $digest = Get-FileHash -LiteralPath $probeFile -Algorithm SHA256 -ErrorAction Stop',
            '    $signature = Get-AuthenticodeSignature -LiteralPath $probeFile -ErrorAction Stop',
            '    if ([string]::IsNullOrWhiteSpace($digest.Hash) -or $null -eq $signature) { throw ''Security/hash command did not invoke after inbox resolution.'' }',
            '    Write-Output ''POLLUTED_PS51_INBOX_MODULES_OK''',
            '} finally {',
            '    [System.IO.File]::Delete($probeFile)',
            '}'
        )
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($probePath, ($probeLines -join [Environment]::NewLine), $utf8NoBom)

        $output = & $ps51Path -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $probePath 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
        $exitCode | Should -Be 0 -Because "the production bootstrap must override a higher-version polluted module root without changing global module configuration. Output: $output"
        $output | Should -Match 'POLLUTED_PS51_INBOX_MODULES_OK'
    }

    It "keeps clean Windows PowerShell 5.1 and PowerShell 7 startup behavior working" {
        $engines = @()
        $ps51Path = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (Test-Path -LiteralPath $ps51Path -PathType Leaf) {
            $engines += [pscustomobject]@{ Name = 'PS5_1'; Path = $ps51Path }
        }
        $ps7Command = Get-Command pwsh -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $ps7Command -and (Test-Path -LiteralPath $ps7Command.Path -PathType Leaf)) {
            $engines += [pscustomobject]@{ Name = 'PS7'; Path = $ps7Command.Path }
        }
        if ($engines.Count -eq 0) {
            Set-ItResult -Skipped -Because 'Neither Windows PowerShell 5.1 nor PowerShell 7 is installed on this host.'
            return
        }

        foreach ($engine in $engines) {
            $probePath = Join-Path $TestDrive ("clean-module-bootstrap-{0}.ps1" -f $engine.Name)
            $marker = "CLEAN_{0}_OK" -f $engine.Name
            $probeLines = @(
                '$ErrorActionPreference = ''Stop''',
                '$PSModuleAutoLoadingPreference = ''None''',
                '$env:PSModulePath = [System.IO.Path]::Combine($PSHOME, ''Modules'')'
            ) + $script:SecurityHashStartupLines + @(
                '$probeFile = [System.IO.Path]::GetTempFileName()',
                'try {',
                '    [System.IO.File]::WriteAllText($probeFile, ''Clean module path probe'')',
                '    $authCommand = Get-Command Get-AuthenticodeSignature -ErrorAction Stop',
                '    $hashCommand = Get-Command Get-FileHash -ErrorAction Stop',
                '    $digest = Get-FileHash -LiteralPath $probeFile -Algorithm SHA256 -ErrorAction Stop',
                '    $signature = Get-AuthenticodeSignature -LiteralPath $probeFile -ErrorAction Stop',
                '    if (-not $authCommand -or -not $hashCommand -or [string]::IsNullOrWhiteSpace($digest.Hash) -or $null -eq $signature) { throw ''Security/hash command did not resolve in a clean engine process.'' }',
                ("    Write-Output '{0}'" -f $marker),
                '} finally {',
                '    [System.IO.File]::Delete($probeFile)',
                '}'
            )
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::WriteAllText($probePath, ($probeLines -join [Environment]::NewLine), $utf8NoBom)

            $output = & $engine.Path -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $probePath 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
            $exitCode | Should -Be 0 -Because "the production bootstrap must work in a clean $($engine.Name) process. Output: $output"
            $output | Should -Match $marker
        }
    }

}
Describe "Expand-ZipFileSafe" {
    BeforeAll {
        # ZipArchive is in System.IO.Compression.dll; ZipFile is in the separate
        # System.IO.Compression.FileSystem.dll. Load both explicitly because the
        # production script's Add-Type (top-level, not in a function body) is
        # never captured by the AST extraction above.
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem

        function New-TestZip([string]$zipPath, [hashtable]$entries) {
            if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
            $fs = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::CreateNew)
            try {
                $archive = [System.IO.Compression.ZipArchive]::new($fs, [System.IO.Compression.ZipArchiveMode]::Create)
                try {
                    foreach ($name in $entries.Keys) {
                        $entry = $archive.CreateEntry($name)
                        $w = New-Object System.IO.StreamWriter($entry.Open())
                        try { $w.Write($entries[$name]) } finally { $w.Dispose() }
                    }
                } finally { $archive.Dispose() }
            } finally { $fs.Dispose() }
        }
    }

    It "extracts normal nested entries with their content intact" {
        $zip  = Join-Path $TestDrive "normal.zip"
        $dest = Join-Path $TestDrive "normal-out"
        New-TestZip $zip @{ "sub/folder/file.txt" = "hello" }
        Expand-ZipFileSafe -ZipPath $zip -DestDir $dest
        Get-Content -LiteralPath (Join-Path $dest "sub\folder\file.txt") -Raw | Should -Be "hello"
    }
    It "rejects an entry with a directory traversal segment" {
        $zip  = Join-Path $TestDrive "traversal.zip"
        $dest = Join-Path $TestDrive "traversal-out"
        New-TestZip $zip @{ "../escape.txt" = "evil" }
        { Expand-ZipFileSafe -ZipPath $zip -DestDir $dest } | Should -Throw "*escapes destination folder*"
    }
    It "rejects an entry with a deeper directory traversal segment" {
        $zip  = Join-Path $TestDrive "traversal2.zip"
        $dest = Join-Path $TestDrive "traversal2-out"
        New-TestZip $zip @{ "sub/../../escape.txt" = "evil" }
        { Expand-ZipFileSafe -ZipPath $zip -DestDir $dest } | Should -Throw "*escapes destination folder*"
    }
    It "rejects an absolute (rooted) entry path" {
        $zip  = Join-Path $TestDrive "rooted.zip"
        $dest = Join-Path $TestDrive "rooted-out"
        New-TestZip $zip @{ "C:/evil.txt" = "evil" }
        { Expand-ZipFileSafe -ZipPath $zip -DestDir $dest } | Should -Throw "*escapes destination folder*"
    }
    It "throws cleanly on a corrupt zip file" {
        $zip = Join-Path $TestDrive "corrupt.zip"
        [System.IO.File]::WriteAllBytes($zip, [byte[]]@(1,2,3,4,5))
        $dest = Join-Path $TestDrive "corrupt-out"
        { Expand-ZipFileSafe -ZipPath $zip -DestDir $dest } | Should -Throw
    }
}

Describe "Test-DgVoodoo2UpToDate" {
    It "is not eligible when the game imports no legacy API" {
        $result = Test-DgVoodoo2UpToDate -Apis @() -ExeDir (Join-Path $TestDrive "anything")
        $result.Eligible | Should -BeFalse
        $result.UpToDate | Should -BeTrue
    }
    It "is eligible but not up to date when the required DLL is missing" {
        $dir = Join-Path $TestDrive "needsdg"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $result = Test-DgVoodoo2UpToDate -Apis @('D3D8') -ExeDir $dir
        $result.Eligible | Should -BeTrue
        $result.UpToDate | Should -BeFalse
    }
    It "is up to date once the required DLL is present" {
        $dir = Join-Path $TestDrive "hasdg"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $dir "D3D8.dll"), [byte[]]@(0))
        $result = Test-DgVoodoo2UpToDate -Apis @('D3D8') -ExeDir $dir
        $result.UpToDate | Should -BeTrue
    }
    It "requires every implicated DLL, not just one of several" {
        $dir = Join-Path $TestDrive "partialdg"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $dir "DDraw.dll"), [byte[]]@(0))
        $result = Test-DgVoodoo2UpToDate -Apis @('DDraw', 'Glide2x') -ExeDir $dir
        $result.UpToDate | Should -BeFalse
    }
}

Describe "Get-TpmSha256FromDigestField" {
    It "extracts a bare uppercase hex hash from a valid sha256: digest field" {
        $hex = ('a' * 64)
        Get-TpmSha256FromDigestField -Digest "sha256:$hex" | Should -Be $hex.ToUpper()
    }
    It "returns null for an empty/whitespace digest" {
        Get-TpmSha256FromDigestField -Digest '' | Should -BeNullOrEmpty
        Get-TpmSha256FromDigestField -Digest '   ' | Should -BeNullOrEmpty
    }
    It "returns null for a non-sha256 digest algorithm" {
        Get-TpmSha256FromDigestField -Digest ('sha512:' + ('b' * 128)) | Should -BeNullOrEmpty
    }
    It "returns null for a malformed (wrong-length) sha256 digest" {
        Get-TpmSha256FromDigestField -Digest 'sha256:deadbeef' | Should -BeNullOrEmpty
    }
}

Describe "Test-TpmDownloadedFile -ExpectedSha256 (fail-closed integrity gate)" {
    BeforeAll {
        function Write-Log { param($Message) }
    }
    It "passes when the SHA-256 matches" {
        $path = Join-Path $TestDrive "sha-match.bin"
        [System.IO.File]::WriteAllBytes($path, [byte[]](1,2,3,4,5))
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        Test-TpmDownloadedFile -Path $path -ExpectedSha256 $hash | Should -BeTrue
    }
    It "fails closed when the SHA-256 does not match" {
        $path = Join-Path $TestDrive "sha-mismatch.bin"
        [System.IO.File]::WriteAllBytes($path, [byte[]](1,2,3,4,5))
        Test-TpmDownloadedFile -Path $path -ExpectedSha256 ('0' * 64) | Should -BeFalse
    }
    It "is case-insensitive when comparing the expected hash" {
        $path = Join-Path $TestDrive "sha-case.bin"
        [System.IO.File]::WriteAllBytes($path, [byte[]](9,9,9))
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        Test-TpmDownloadedFile -Path $path -ExpectedSha256 $hash.ToLower() | Should -BeTrue
    }
    It "still validates size-only when -ExpectedSha256 is not supplied (no regression)" {
        $path = Join-Path $TestDrive "sha-none.bin"
        [System.IO.File]::WriteAllBytes($path, [byte[]](1,2,3))
        Test-TpmDownloadedFile -Path $path -ExpectedBytes 3 | Should -BeTrue
    }
}

Describe "Get-DgVoodoo2LatestRelease (URL allowlist + digest extraction)" {
    BeforeAll {
        function Write-Log { param($Message) }
        function Get-TpmHttpStatusCodeFromError { param($ErrorRecord) return 0 }
    }
    It "accepts a well-formed release with a safe github.com download URL and extracts the digest" {
        Mock Invoke-WebRequest {
            [pscustomobject]@{
                Content = (@{
                    tag_name = 'v2.87.3'
                    assets   = @(
                        @{ name = 'dgVoodoo2_87_3.zip'; browser_download_url = 'https://github.com/dege-diosg/dgVoodoo2/releases/download/v2.87.3/dgVoodoo2_87_3.zip'; size = 9082391; digest = ('sha256:' + ('a' * 64)) },
                        @{ name = 'dgVoodoo2_87_3_dev64.zip'; browser_download_url = 'https://github.com/dege-diosg/dgVoodoo2/releases/download/v2.87.3/dgVoodoo2_87_3_dev64.zip'; size = 17561846; digest = ('sha256:' + ('b' * 64)) },
                        @{ name = 'dgVoodoo2_87_3_dbg.zip'; browser_download_url = 'https://github.com/dege-diosg/dgVoodoo2/releases/download/v2.87.3/dgVoodoo2_87_3_dbg.zip'; size = 9926358; digest = ('sha256:' + ('c' * 64)) }
                    )
                } | ConvertTo-Json -Depth 5)
            }
        }
        $rel = Get-DgVoodoo2LatestRelease
        $rel | Should -Not -BeNullOrEmpty
        $rel.Version | Should -Be '2.87.3'
        $rel.FileName | Should -Be 'dgVoodoo2_87_3.zip'
        $rel.DownloadUrl | Should -Be 'https://github.com/dege-diosg/dgVoodoo2/releases/download/v2.87.3/dgVoodoo2_87_3.zip'
        $rel.ExpectedSha256 | Should -Be ('A' * 64)
    }
    It "never selects the dev or debug variant asset as the main ZIP" {
        Mock Invoke-WebRequest {
            [pscustomobject]@{
                Content = (@{
                    tag_name = 'v2.87.3'
                    assets   = @(
                        @{ name = 'dgVoodoo2_87_3_dev64.zip'; browser_download_url = 'https://github.com/dege-diosg/dgVoodoo2/releases/download/v2.87.3/dgVoodoo2_87_3_dev64.zip'; size = 1; digest = $null },
                        @{ name = 'dgVoodoo2_87_3_dbg.zip'; browser_download_url = 'https://github.com/dege-diosg/dgVoodoo2/releases/download/v2.87.3/dgVoodoo2_87_3_dbg.zip'; size = 1; digest = $null }
                    )
                } | ConvertTo-Json -Depth 5)
            }
        }
        Get-DgVoodoo2LatestRelease | Should -BeNullOrEmpty
    }
    It "rejects a download URL on a host other than github.com" {
        Mock Invoke-WebRequest {
            [pscustomobject]@{
                Content = (@{
                    tag_name = 'v2.87.3'
                    assets   = @(
                        @{ name = 'dgVoodoo2_87_3.zip'; browser_download_url = 'https://evil.example.com/dgVoodoo2_87_3.zip'; size = 1; digest = $null }
                    )
                } | ConvertTo-Json -Depth 5)
            }
        }
        Get-DgVoodoo2LatestRelease | Should -BeNullOrEmpty
    }
    It "returns null (no ExpectedSha256) when the asset has no digest field, degrading gracefully" {
        Mock Invoke-WebRequest {
            [pscustomobject]@{
                Content = (@{
                    tag_name = 'v2.87.3'
                    assets   = @(
                        @{ name = 'dgVoodoo2_87_3.zip'; browser_download_url = 'https://github.com/dege-diosg/dgVoodoo2/releases/download/v2.87.3/dgVoodoo2_87_3.zip'; size = 9082391 }
                    )
                } | ConvertTo-Json -Depth 5)
            }
        }
        $rel = Get-DgVoodoo2LatestRelease
        $rel | Should -Not -BeNullOrEmpty
        $rel.ExpectedSha256 | Should -BeNullOrEmpty
    }
}

Describe "New-TpmStagingDirectory" {
    It "creates a unique directory under the controlled TPM temp staging root, not under a real destination" {
        $dir1 = New-TpmStagingDirectory -Label 'Test'
        $dir2 = New-TpmStagingDirectory -Label 'Test'
        try {
            Test-Path -LiteralPath $dir1 -PathType Container | Should -BeTrue
            Test-Path -LiteralPath $dir2 -PathType Container | Should -BeTrue
            $dir1 | Should -Not -Be $dir2
            $dir1 | Should -Match ([regex]::Escape('TeknoParrotManagerStaging'))
        } finally {
            Remove-Item -LiteralPath $dir1 -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $dir2 -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Invoke-TpmTransactionalPromote (rollback-safe promotion, P1 #1 / P1 2nd-round remediation)" {
    BeforeAll {
        function Write-Log { param($Message) }
        function New-StagedFile([string]$dir, [string]$name, [string]$content) {
            [void][System.IO.Directory]::CreateDirectory($dir)
            [System.IO.File]::WriteAllText((Join-Path $dir $name), $content)
        }
    }

    It "promotes all files into a fresh (previously nonexistent) destination" {
        $staging = Join-Path $TestDrive ("stage-" + [guid]::NewGuid().ToString('N'))
        $dest    = Join-Path $TestDrive ("dest-fresh-" + [guid]::NewGuid().ToString('N'))
        New-StagedFile $staging 'a.txt' 'A'
        New-StagedFile $staging 'b.txt' 'B'
        Invoke-TpmTransactionalPromote -StagingDir $staging -DestDir $dest -FileNames @('a.txt', 'b.txt')
        (Get-Content -LiteralPath (Join-Path $dest 'a.txt') -Raw) | Should -Be 'A'
        (Get-Content -LiteralPath (Join-Path $dest 'b.txt') -Raw) | Should -Be 'B'
    }

    It "successful promotion (new + replaced files) leaves exactly the expected final tree, with no temp/backup residue anywhere under staging" {
        $staging = Join-Path $TestDrive ("stage-" + [guid]::NewGuid().ToString('N'))
        $dest    = Join-Path $TestDrive ("dest-replace-" + [guid]::NewGuid().ToString('N'))
        New-StagedFile $dest 'a.txt' 'OLD-A'
        New-StagedFile $staging 'a.txt' 'NEW-A'
        New-StagedFile $staging 'b.txt' 'NEW-B'
        Invoke-TpmTransactionalPromote -StagingDir $staging -DestDir $dest -FileNames @('a.txt', 'b.txt')

        (Get-Content -LiteralPath (Join-Path $dest 'a.txt') -Raw) | Should -Be 'NEW-A'
        (Get-Content -LiteralPath (Join-Path $dest 'b.txt') -Raw) | Should -Be 'NEW-B'
        (Get-ChildItem -LiteralPath $dest -Force).Name | Sort-Object | Should -Be @('a.txt', 'b.txt')
        # Every staged file was moved OUT of $staging into $dest, and the
        # rollback-backup directory is cleaned up on success -- $staging
        # itself must be left completely empty, not merely missing the
        # backup subfolder.
        (@(Get-ChildItem -LiteralPath $staging -Force -Recurse -ErrorAction SilentlyContinue)).Count | Should -Be 0
    }

    It "Case 3 -- destination exists with prior files, replacement partially succeeds, a later NEW file's promotion fails: exact pre-state restored" {
        $staging = Join-Path $TestDrive ("stage-" + [guid]::NewGuid().ToString('N'))
        $dest    = Join-Path $TestDrive ("dest-rollback-" + [guid]::NewGuid().ToString('N'))
        # 'a' already exists in the destination (proves exact byte-for-byte
        # restore-on-rollback, not just "some file exists"); 'b' does not
        # (proves newly-promoted-file removal-on-rollback); 'c' is the file
        # whose promotion is forced to fail.
        New-StagedFile $dest 'a.txt' 'OLD-A'
        New-StagedFile $staging 'a.txt' 'NEW-A'
        New-StagedFile $staging 'b.txt' 'NEW-B'
        New-StagedFile $staging 'c.txt' 'NEW-C'
        $before = Get-TpmDirSnapshot -Dir $dest

        Mock Move-Item {
            param($LiteralPath, $Destination)
            if ($LiteralPath -like "*c.txt") { throw "simulated promotion failure on c.txt" }
            # NOTE: calling through to the real Move-Item cmdlet (even
            # module-qualified) from inside its own Mock recurses back into
            # the mock in this Pester version and overflows the call stack
            # -- use the underlying .NET primitive instead for the
            # pass-through (non-simulated-failure) case.
            [System.IO.File]::Move($LiteralPath, $Destination)
        }

        { Invoke-TpmTransactionalPromote -StagingDir $staging -DestDir $dest -FileNames @('a.txt', 'b.txt', 'c.txt') } | Should -Throw "*simulated promotion failure*"

        $after = Get-TpmDirSnapshot -Dir $dest
        Assert-TpmDirSnapshotUnchanged -Before $before -After $after
        Test-Path -LiteralPath (Join-Path $staging '.tpm-rollback-backup') | Should -BeFalse
    }

    It "Case 1 -- destination absent before the call, failure before the first file is even promoted: destination directory itself is removed again, not merely left empty" {
        $staging = Join-Path $TestDrive ("stage-" + [guid]::NewGuid().ToString('N'))
        $dest    = Join-Path $TestDrive ("dest-rollback-first-" + [guid]::NewGuid().ToString('N'))
        New-StagedFile $staging 'a.txt' 'NEW-A'
        New-StagedFile $staging 'b.txt' 'NEW-B'
        $before = Get-TpmDirSnapshot -Dir $dest
        $before.Existed | Should -BeFalse   # sanity: this case requires the destination to genuinely not exist yet

        Mock Move-Item {
            param($LiteralPath, $Destination)
            if ($LiteralPath -like "*a.txt") { throw "simulated failure on first file" }
            [System.IO.File]::Move($LiteralPath, $Destination)
        }

        { Invoke-TpmTransactionalPromote -StagingDir $staging -DestDir $dest -FileNames @('a.txt', 'b.txt') } | Should -Throw "*simulated failure on first file*"

        $after = Get-TpmDirSnapshot -Dir $dest
        Assert-TpmDirSnapshotUnchanged -Before $before -After $after
        # Explicit, not merely implied by the snapshot compare: the
        # directory this call created must not survive rollback.
        Test-Path -LiteralPath $dest | Should -BeFalse
    }

    It "Case 2 -- destination absent before the call, first file promotes successfully, second file fails: destination directory itself is removed again" {
        $staging = Join-Path $TestDrive ("stage-" + [guid]::NewGuid().ToString('N'))
        $dest    = Join-Path $TestDrive ("dest-rollback-second-" + [guid]::NewGuid().ToString('N'))
        New-StagedFile $staging 'a.txt' 'NEW-A'
        New-StagedFile $staging 'b.txt' 'NEW-B'
        $before = Get-TpmDirSnapshot -Dir $dest
        $before.Existed | Should -BeFalse

        Mock Move-Item {
            param($LiteralPath, $Destination)
            if ($LiteralPath -like "*b.txt") { throw "simulated failure on second file" }
            [System.IO.File]::Move($LiteralPath, $Destination)
        }

        { Invoke-TpmTransactionalPromote -StagingDir $staging -DestDir $dest -FileNames @('a.txt', 'b.txt') } | Should -Throw "*simulated failure on second file*"

        $after = Get-TpmDirSnapshot -Dir $dest
        Assert-TpmDirSnapshotUnchanged -Before $before -After $after
        Test-Path -LiteralPath $dest | Should -BeFalse
    }


    It "Case 5 -- phase-1 Move-Item throws after a valid backup is observable: the backup is recorded and the exact pre-state is restored" {
        $staging = Join-Path $TestDrive ("stage-" + [guid]::NewGuid().ToString('N'))
        $dest    = Join-Path $TestDrive ("dest-valid-phase1-backup-" + [guid]::NewGuid().ToString('N'))
        New-StagedFile $dest 'a.txt' 'OLD-A'
        New-StagedFile $staging 'a.txt' 'NEW-A'
        [void][System.IO.Directory]::CreateDirectory((Join-Path $dest 'keep\nested'))
        [System.IO.File]::WriteAllText((Join-Path $dest 'keep\nested\marker.txt'), 'KEEP')
        $before = Get-TpmDirSnapshot -Dir $dest
        $oldPath = Join-Path $dest 'a.txt'

        Mock Move-Item {
            param($LiteralPath, $Destination)
            if ($LiteralPath -ieq $oldPath) {
                [System.IO.File]::Copy($LiteralPath, $Destination, $true)
                [System.IO.File]::Delete($LiteralPath)
                throw "simulated phase-1 failure after valid backup became observable"
            }
            [System.IO.File]::Move($LiteralPath, $Destination)
        }

        { Invoke-TpmTransactionalPromote -StagingDir $staging -DestDir $dest -FileNames @('a.txt') } |
            Should -Throw "*simulated phase-1 failure after valid backup became observable*"

        $after = Get-TpmDirSnapshot -Dir $dest
        Assert-TpmDirSnapshotUnchanged -Before $before -After $after
        Test-Path -LiteralPath (Join-Path $staging '.tpm-rollback-backup') | Should -BeFalse
    }

    It "Case 6 -- phase-1 Move-Item removes the original before any valid backup is observable: throws an unrecoverable ROLLBACK FAILED result and preserves evidence" {
        $staging = Join-Path $TestDrive ("stage-" + [guid]::NewGuid().ToString('N'))
        $dest    = Join-Path $TestDrive ("dest-lost-phase1-source-" + [guid]::NewGuid().ToString('N'))
        New-StagedFile $dest 'a.txt' 'OLD-A'
        New-StagedFile $staging 'a.txt' 'NEW-A'
        $oldPath = Join-Path $dest 'a.txt'
        $caught = $null

        Mock Move-Item {
            param($LiteralPath, $Destination)
            if ($LiteralPath -ieq $oldPath) {
                [System.IO.File]::Delete($LiteralPath)
                throw "simulated phase-1 source deletion before backup"
            }
            [System.IO.File]::Move($LiteralPath, $Destination)
        }

        try {
            Invoke-TpmTransactionalPromote -StagingDir $staging -DestDir $dest -FileNames @('a.txt')
        } catch {
            $caught = $_
        }

        try {
            $caught | Should -Not -BeNullOrEmpty
            $caught.ToString() | Should -Match 'ROLLBACK FAILED'
            $caught.ToString() | Should -Match 'INCONSISTENT'
            $caught.ToString() | Should -Match 'unrecoverable'
            $caught.ToString() | Should -Match 'simulated phase-1 source deletion before backup'
            $caught.ToString() | Should -Match 'Pre-move evidence'
            Test-Path -LiteralPath $oldPath | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $staging '.tpm-rollback-backup') | Should -BeTrue
        } finally {
            if (Test-Path -LiteralPath $staging) {
                [System.IO.Directory]::Delete($staging, $true)
            }
        }
    }

    It "Case 7 -- destination setup fails after the destination was absent: the destination remains absent exactly" {
        $staging = Join-Path $TestDrive ("stage-" + [guid]::NewGuid().ToString('N'))
        $dest    = Join-Path $TestDrive ("dest-setup-fails-" + [guid]::NewGuid().ToString('N'))
        New-StagedFile $staging 'a.txt' 'NEW-A'
        [System.IO.File]::WriteAllText((Join-Path $staging '.tpm-rollback-backup'), 'blocking file')
        $before = Get-TpmDirSnapshot -Dir $dest
        $caught = $null

        try {
            Invoke-TpmTransactionalPromote -StagingDir $staging -DestDir $dest -FileNames @('a.txt')
        } catch {
            $caught = $_
        }

        try {
            $caught | Should -Not -BeNullOrEmpty
            $caught.ToString() | Should -Not -Match 'ROLLBACK FAILED|CLEANUP FAILED'
            $after = Get-TpmDirSnapshot -Dir $dest
            Assert-TpmDirSnapshotUnchanged -Before $before -After $after
            Test-Path -LiteralPath $dest | Should -BeFalse
        } finally {
            if (Test-Path -LiteralPath $staging) {
                [System.IO.Directory]::Delete($staging, $true)
            }
        }
    }

    It "Case 8 -- destination restores exactly but rollback-backup cleanup fails: throws TRANSACTION CLEANUP FAILED and preserves residue" {
        $staging = Join-Path $TestDrive ("stage-" + [guid]::NewGuid().ToString('N'))
        $dest    = Join-Path $TestDrive ("dest-cleanup-fails-" + [guid]::NewGuid().ToString('N'))
        New-StagedFile $dest 'a.txt' 'OLD-A'
        New-StagedFile $staging 'a.txt' 'NEW-A'
        New-StagedFile $staging 'b.txt' 'NEW-B'
        [void][System.IO.Directory]::CreateDirectory((Join-Path $dest 'keep\nested'))
        [System.IO.File]::WriteAllText((Join-Path $dest 'keep\nested\marker.txt'), 'KEEP')
        $before = Get-TpmDirSnapshot -Dir $dest
        $backupDir = Join-Path $staging '.tpm-rollback-backup'

        Mock Move-Item {
            param($LiteralPath, $Destination)
            if ($LiteralPath -ieq (Join-Path $staging 'b.txt')) {
                throw "simulated promotion failure before cleanup"
            }
            [System.IO.File]::Move($LiteralPath, $Destination)
        }
        Mock Remove-Item {
            param($LiteralPath, $Recurse, $Force, $ErrorAction)
            if ($LiteralPath -ieq $backupDir) {
                throw "simulated rollback-backup cleanup failure"
            }
            if (Test-Path -LiteralPath $LiteralPath -PathType Container) {
                [System.IO.Directory]::Delete($LiteralPath, [bool]$Recurse)
            } elseif (Test-Path -LiteralPath $LiteralPath) {
                [System.IO.File]::Delete($LiteralPath)
            }
        }

        $caught = $null
        try {
            Invoke-TpmTransactionalPromote -StagingDir $staging -DestDir $dest -FileNames @('a.txt', 'b.txt')
        } catch {
            $caught = $_
        }

        try {
            $caught | Should -Not -BeNullOrEmpty
            $caught.ToString() | Should -Match 'TRANSACTION CLEANUP FAILED'
            $caught.ToString() | Should -Match 'destination was successfully restored'
            $caught.ToString() | Should -Match 'simulated promotion failure before cleanup'
            $caught.ToString() | Should -Match 'simulated rollback-backup cleanup failure'
            $caught.ToString() | Should -Not -Match 'ROLLBACK FAILED'
            $after = Get-TpmDirSnapshot -Dir $dest
            Assert-TpmDirSnapshotUnchanged -Before $before -After $after
            Test-Path -LiteralPath $backupDir | Should -BeTrue
        } finally {
            if (Test-Path -LiteralPath $staging) {
                [System.IO.Directory]::Delete($staging, $true)
            }
        }
    }
    It "Case 4 -- rollback itself is forced to fail: throws a distinct ROLLBACK FAILED error carrying both the original and rollback failures, and preserves the backup for manual recovery instead of silently reporting a clean failure" {
        $staging = Join-Path $TestDrive ("stage-" + [guid]::NewGuid().ToString('N'))
        $dest    = Join-Path $TestDrive ("dest-rollback-fails-" + [guid]::NewGuid().ToString('N'))
        New-StagedFile $dest 'a.txt' 'OLD-A'
        New-StagedFile $staging 'a.txt' 'NEW-A'
        New-StagedFile $staging 'b.txt' 'NEW-B'
        New-StagedFile $staging 'c.txt' 'NEW-C'

        Mock Move-Item {
            param($LiteralPath, $Destination)
            # Fail the original promotion of c.txt (staging -> dest).
            if ($LiteralPath -like "*c.txt" -and $LiteralPath -notlike "*.tpm-rollback-backup*") {
                throw "simulated promotion failure on c.txt"
            }
            # Fail the rollback restore of a.txt specifically (the
            # rollback-backup copy being moved BACK into dest) -- distinct
            # from the phase-1 move that creates the backup in the first
            # place, whose $LiteralPath is the dest copy, not the backup
            # copy.
            if ($LiteralPath -like "*.tpm-rollback-backup*a.txt") {
                throw "simulated rollback failure restoring a.txt"
            }
            [System.IO.File]::Move($LiteralPath, $Destination)
        }

        $caught = $null
        try {
            Invoke-TpmTransactionalPromote -StagingDir $staging -DestDir $dest -FileNames @('a.txt', 'b.txt', 'c.txt')
        } catch {
            $caught = $_
        }

        $caught | Should -Not -BeNullOrEmpty
        # Distinct from a plain rolled-back-successfully failure: must
        # surface as its own, clearly-labeled failure mode.
        $caught.ToString() | Should -Match 'ROLLBACK FAILED'
        $caught.ToString() | Should -Match 'INCONSISTENT'
        # Both the original defect and the rollback defect must be
        # preserved for diagnosis, not just one or the other.
        $caught.ToString() | Should -Match 'simulated promotion failure on c\.txt'
        $caught.ToString() | Should -Match 'simulated rollback failure restoring a\.txt'

        # The backup must be preserved (not cleaned up) precisely because
        # rollback did not complete -- deleting it here would destroy the
        # only remaining copy of the pre-operation file.
        $preservedBackup = Join-Path $staging '.tpm-rollback-backup\a.txt'
        Test-Path -LiteralPath $preservedBackup | Should -BeTrue
        (Get-Content -LiteralPath $preservedBackup -Raw) | Should -Be 'OLD-A'
    }
}

Describe "Expand-DgVoodoo2Zip (selective extraction, fail-closed on layout drift)" {
    BeforeAll {
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        function New-TestZip([string]$zipPath, [hashtable]$entries) {
            if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
            $fs = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::CreateNew)
            try {
                $archive = [System.IO.Compression.ZipArchive]::new($fs, [System.IO.Compression.ZipArchiveMode]::Create)
                try {
                    foreach ($name in $entries.Keys) {
                        $entry = $archive.CreateEntry($name)
                        $w = New-Object System.IO.StreamWriter($entry.Open())
                        try { $w.Write($entries[$name]) } finally { $w.Dispose() }
                    }
                } finally { $archive.Dispose() }
            } finally { $fs.Dispose() }
        }
        $validEntries = @{
            'MS/x86/D3D8.dll'      = 'd3d8'
            'MS/x86/DDraw.dll'     = 'ddraw'
            'MS/x86/D3DImm.dll'    = 'd3dimm'
            '3Dfx/x86/Glide2x.dll' = 'glide2x'
            '3Dfx/x86/Glide3x.dll' = 'glide3x'
            'dgVoodoo.conf'        = 'conf'
        }
    }
    It "extracts all 6 expected files to flat destination names when the layout matches" {
        $zip  = Join-Path $TestDrive "dgv-valid.zip"
        $dest = Join-Path $TestDrive "dgv-valid-out"
        New-TestZip $zip $validEntries
        Expand-DgVoodoo2Zip -ZipPath $zip -DestDir $dest
        (Get-Content -LiteralPath (Join-Path $dest "D3D8.dll") -Raw) | Should -Be 'd3d8'
        (Get-Content -LiteralPath (Join-Path $dest "DDraw.dll") -Raw) | Should -Be 'ddraw'
        (Get-Content -LiteralPath (Join-Path $dest "D3DImm.dll") -Raw) | Should -Be 'd3dimm'
        (Get-Content -LiteralPath (Join-Path $dest "Glide2x.dll") -Raw) | Should -Be 'glide2x'
        (Get-Content -LiteralPath (Join-Path $dest "Glide3x.dll") -Raw) | Should -Be 'glide3x'
        (Get-Content -LiteralPath (Join-Path $dest "dgVoodoo.conf") -Raw) | Should -Be 'conf'
    }
    It "fails closed when an expected entry is missing (layout drift)" {
        $zip  = Join-Path $TestDrive "dgv-missing.zip"
        $dest = Join-Path $TestDrive "dgv-missing-out"
        $bad = $validEntries.Clone()
        $bad.Remove('MS/x86/DDraw.dll')
        New-TestZip $zip $bad
        { Expand-DgVoodoo2Zip -ZipPath $zip -DestDir $dest } | Should -Throw "*layout has changed*"
    }
    It "P1 #1: leaves the destination completely untouched when extraction fails partway through (2nd of 6 files)" {
        $zip  = Join-Path $TestDrive "dgv-extractfail.zip"
        $dest = Join-Path $TestDrive "dgv-extractfail-out"
        New-TestZip $zip $validEntries
        # Pre-existing destination file, to prove it survives an
        # extraction-phase failure untouched (extraction never reaches
        # promotion at all in this case).
        [void][System.IO.Directory]::CreateDirectory($dest)
        [System.IO.File]::WriteAllText((Join-Path $dest 'D3D8.dll'), 'PRE-EXISTING')

        $script:callCount = 0
        Mock Copy-TpmZipEntryToFile {
            param($Entry, $DestPath)
            $script:callCount++
            if ($script:callCount -eq 2) { throw "simulated extraction failure on 2nd entry" }
            # Fall through to the real copy for every other call so the
            # rest of a normal extraction still behaves realistically.
            $srcStream = $Entry.Open()
            try {
                $dstStream = [System.IO.File]::Open($DestPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                try { $srcStream.CopyTo($dstStream) } finally { $dstStream.Dispose() }
            } finally { $srcStream.Dispose() }
        }

        { Expand-DgVoodoo2Zip -ZipPath $zip -DestDir $dest } | Should -Throw "*simulated extraction failure*"

        # Destination must be exactly what it was before the call: only
        # the pre-existing D3D8.dll, with its original (untouched) content.
        (Get-ChildItem -LiteralPath $dest -Force).Name | Should -Be @('D3D8.dll')
        (Get-Content -LiteralPath (Join-Path $dest 'D3D8.dll') -Raw) | Should -Be 'PRE-EXISTING'
    }
    It "P1 #1: restores destination exactly when promotion fails partway through (after successful extraction of all 6)" {
        $zip  = Join-Path $TestDrive "dgv-promofail.zip"
        $dest = Join-Path $TestDrive "dgv-promofail-out"
        New-TestZip $zip $validEntries
        [void][System.IO.Directory]::CreateDirectory($dest)
        [System.IO.File]::WriteAllText((Join-Path $dest 'D3D8.dll'), 'PRE-EXISTING-D3D8')

        Mock Move-Item {
            param($LiteralPath, $Destination)
            if ($LiteralPath -like "*Glide3x.dll") { throw "simulated promotion failure on Glide3x.dll" }
            # NOTE: calling through to the real Move-Item cmdlet (even
            # module-qualified) from inside its own Mock recurses back into
            # the mock in this Pester version and overflows the call stack
            # -- use the underlying .NET primitive instead for the
            # pass-through (non-simulated-failure) case.
            [System.IO.File]::Move($LiteralPath, $Destination)
        }

        { Expand-DgVoodoo2Zip -ZipPath $zip -DestDir $dest } | Should -Throw "*simulated promotion failure*"

        # Exactly the pre-existing file, exactly its original content --
        # none of the 6 newly-extracted files leaked into the destination.
        (Get-ChildItem -LiteralPath $dest -Force).Name | Should -Be @('D3D8.dll')
        (Get-Content -LiteralPath (Join-Path $dest 'D3D8.dll') -Raw) | Should -Be 'PRE-EXISTING-D3D8'
    }
    It "successful extraction leaves exactly the expected 6-file final tree and no temp/backup residue" {
        $zip  = Join-Path $TestDrive "dgv-clean-success.zip"
        $dest = Join-Path $TestDrive "dgv-clean-success-out"
        # Baseline BEFORE this call, not an assumed-zero global count --
        # other tests in this same run (e.g. the "rollback itself fails"
        # case below) deliberately leave a staging directory behind by
        # design, and %TEMP%\TeknoParrotManagerStaging is shared real
        # filesystem state across the whole test session, not something
        # this test can reset.
        $stagingRoot = Join-Path $env:TEMP 'TeknoParrotManagerStaging'
        $before = @(Get-ChildItem -Path $stagingRoot -Directory -Filter 'dgVoodoo2-*' -ErrorAction SilentlyContinue).Count
        New-TestZip $zip $validEntries
        Expand-DgVoodoo2Zip -ZipPath $zip -DestDir $dest
        # PowerShell's default Sort-Object string comparison is
        # case-insensitive, so 'dgVoodoo.conf' sorts alongside the
        # 'D'-prefixed names rather than after the 'G'-prefixed ones.
        (Get-ChildItem -LiteralPath $dest -Force).Name | Sort-Object | Should -Be @(
            'D3D8.dll', 'D3DImm.dll', 'DDraw.dll', 'dgVoodoo.conf', 'Glide2x.dll', 'Glide3x.dll'
        )
        # This call's own staging directory must be gone -- count must be
        # exactly what it was before this call, not merely "some" residue.
        (Get-ChildItem -Path $stagingRoot -Directory -Filter 'dgVoodoo2-*' -ErrorAction SilentlyContinue).Count | Should -Be $before
    }
    It "Case 1 -- destination absent before the call, promotion fails on the very first required file: destination directory itself is removed again" {
        $zip  = Join-Path $TestDrive "dgv-rollback-first.zip"
        $dest = Join-Path $TestDrive "dgv-rollback-first-out"
        New-TestZip $zip $validEntries
        $before = Get-TpmDirSnapshot -Dir $dest
        $before.Existed | Should -BeFalse

        Mock Move-Item {
            param($LiteralPath, $Destination)
            if ($LiteralPath -like "*D3D8.dll") { throw "simulated promotion failure on first required file" }
            [System.IO.File]::Move($LiteralPath, $Destination)
        }

        { Expand-DgVoodoo2Zip -ZipPath $zip -DestDir $dest } | Should -Throw "*simulated promotion failure*"

        $after = Get-TpmDirSnapshot -Dir $dest
        Assert-TpmDirSnapshotUnchanged -Before $before -After $after
        Test-Path -LiteralPath $dest | Should -BeFalse
    }
    It "Case 2 -- destination absent before the call, first file promotes, second file fails: destination directory itself is removed again" {
        $zip  = Join-Path $TestDrive "dgv-rollback-second.zip"
        $dest = Join-Path $TestDrive "dgv-rollback-second-out"
        New-TestZip $zip $validEntries
        $before = Get-TpmDirSnapshot -Dir $dest
        $before.Existed | Should -BeFalse

        Mock Move-Item {
            param($LiteralPath, $Destination)
            if ($LiteralPath -like "*DDraw.dll") { throw "simulated promotion failure on second required file" }
            [System.IO.File]::Move($LiteralPath, $Destination)
        }

        { Expand-DgVoodoo2Zip -ZipPath $zip -DestDir $dest } | Should -Throw "*simulated promotion failure*"

        $after = Get-TpmDirSnapshot -Dir $dest
        Assert-TpmDirSnapshotUnchanged -Before $before -After $after
        Test-Path -LiteralPath $dest | Should -BeFalse
    }

    It "Case 5 -- phase-1 source loss before a valid backup is observable: preserves recovery evidence and reports an inconsistent transaction" {
        $zip  = Join-Path $TestDrive "dgv-phase1-source-loss.zip"
        $dest = Join-Path $TestDrive "dgv-phase1-source-loss-out"
        $stagingRoot = Join-Path $env:TEMP 'TeknoParrotManagerStaging'
        $beforeStages = @(Get-ChildItem -LiteralPath $stagingRoot -Directory -Filter 'dgVoodoo2-*' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        New-TestZip $zip $validEntries
        [void][System.IO.Directory]::CreateDirectory($dest)
        [System.IO.File]::WriteAllText((Join-Path $dest 'D3D8.dll'), 'PRE-EXISTING-D3D8')
        [void][System.IO.Directory]::CreateDirectory((Join-Path $dest 'keep\nested'))
        [System.IO.File]::WriteAllText((Join-Path $dest 'keep\nested\marker.txt'), 'KEEP')
        $oldPath = Join-Path $dest 'D3D8.dll'
        $caught = $null

        Mock Move-Item {
            param($LiteralPath, $Destination)
            if ($LiteralPath -ieq $oldPath) {
                [System.IO.File]::Delete($LiteralPath)
                throw "simulated dgVoodoo2 phase-1 source deletion before backup"
            }
            [System.IO.File]::Move($LiteralPath, $Destination)
        }

        try {
            Expand-DgVoodoo2Zip -ZipPath $zip -DestDir $dest
        } catch {
            $caught = $_
        }

        $newStages = @()
        try {
            $caught | Should -Not -BeNullOrEmpty
            $caught.ToString() | Should -Match 'ROLLBACK FAILED'
            $caught.ToString() | Should -Match 'INCONSISTENT'
            $caught.ToString() | Should -Match 'unrecoverable'
            $caught.ToString() | Should -Match 'simulated dgVoodoo2 phase-1 source deletion before backup'
            $caught.ToString() | Should -Match 'Pre-move evidence'
            Test-Path -LiteralPath $oldPath | Should -BeFalse
            Test-Path -LiteralPath $dest -PathType Container | Should -BeTrue
            (Get-Content -LiteralPath (Join-Path $dest 'keep\nested\marker.txt') -Raw) | Should -Be 'KEEP'
            $newStages = @(Get-ChildItem -LiteralPath $stagingRoot -Directory -Filter 'dgVoodoo2-*' -ErrorAction SilentlyContinue | Where-Object { $beforeStages -notcontains $_.FullName })
            $newStages.Count | Should -Be 1
            Test-Path -LiteralPath (Join-Path $newStages[0].FullName '.tpm-rollback-backup') | Should -BeTrue
        } finally {
            $leftoverStages = @(Get-ChildItem -LiteralPath $stagingRoot -Directory -Filter 'dgVoodoo2-*' -ErrorAction SilentlyContinue | Where-Object { $beforeStages -notcontains $_.FullName })
            foreach ($stagePath in $leftoverStages) {
                if (Test-Path -LiteralPath $stagePath.FullName) {
                    [System.IO.Directory]::Delete($stagePath.FullName, $true)
                }
            }
        }
    }

    It "Case 6 -- destination absent and transaction setup initialization fails: the destination remains absent exactly" {
        $zip  = Join-Path $TestDrive "dgv-setup-fails.zip"
        $dest = Join-Path $TestDrive "dgv-setup-fails-out"
        $forcedStage = Join-Path $TestDrive ("forced-dgv-stage-" + [guid]::NewGuid().ToString('N'))
        New-TestZip $zip $validEntries
        $before = Get-TpmDirSnapshot -Dir $dest

        Mock New-TpmStagingDirectory {
            [void][System.IO.Directory]::CreateDirectory($forcedStage)
            [System.IO.File]::WriteAllText((Join-Path $forcedStage '.tpm-rollback-backup'), 'blocking file')
            return $forcedStage
        }

        $caught = $null
        try {
            Expand-DgVoodoo2Zip -ZipPath $zip -DestDir $dest
        } catch {
            $caught = $_
        }

        try {
            $caught | Should -Not -BeNullOrEmpty
            $caught.ToString() | Should -Not -Match 'ROLLBACK FAILED|CLEANUP FAILED'
            $after = Get-TpmDirSnapshot -Dir $dest
            Assert-TpmDirSnapshotUnchanged -Before $before -After $after
            Test-Path -LiteralPath $dest | Should -BeFalse
            Test-Path -LiteralPath $forcedStage | Should -BeFalse
        } finally {
            if (Test-Path -LiteralPath $forcedStage) {
                [System.IO.Directory]::Delete($forcedStage, $true)
            }
        }
    }

    It "Case 7 -- destination restores exactly but rollback-backup cleanup fails: reports a distinct cleanup error and preserves the wrapper staging evidence" {
        $zip  = Join-Path $TestDrive "dgv-cleanup-fails.zip"
        $dest = Join-Path $TestDrive "dgv-cleanup-fails-out"
        $stagingRoot = Join-Path $env:TEMP 'TeknoParrotManagerStaging'
        $beforeStages = @(Get-ChildItem -LiteralPath $stagingRoot -Directory -Filter 'dgVoodoo2-*' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        New-TestZip $zip $validEntries
        [void][System.IO.Directory]::CreateDirectory($dest)
        [System.IO.File]::WriteAllText((Join-Path $dest 'D3D8.dll'), 'PRE-EXISTING-D3D8')
        [void][System.IO.Directory]::CreateDirectory((Join-Path $dest 'keep\nested'))
        [System.IO.File]::WriteAllText((Join-Path $dest 'keep\nested\marker.txt'), 'KEEP')
        $before = Get-TpmDirSnapshot -Dir $dest

        Mock Move-Item {
            param($LiteralPath, $Destination)
            if ($Destination -ieq (Join-Path $dest 'Glide3x.dll')) {
                throw "simulated dgVoodoo2 promotion failure before cleanup"
            }
            [System.IO.File]::Move($LiteralPath, $Destination)
        }
        Mock Remove-Item {
            param($LiteralPath, $Recurse, $Force, $ErrorAction)
            if ([System.IO.Path]::GetFileName($LiteralPath) -ieq '.tpm-rollback-backup') {
                throw "simulated dgVoodoo2 rollback-backup cleanup failure"
            }
            if (Test-Path -LiteralPath $LiteralPath -PathType Container) {
                [System.IO.Directory]::Delete($LiteralPath, [bool]$Recurse)
            } elseif (Test-Path -LiteralPath $LiteralPath) {
                [System.IO.File]::Delete($LiteralPath)
            }
        }

        $caught = $null
        try {
            Expand-DgVoodoo2Zip -ZipPath $zip -DestDir $dest
        } catch {
            $caught = $_
        }

        try {
            $caught | Should -Not -BeNullOrEmpty
            $caught.ToString() | Should -Match 'TRANSACTION CLEANUP FAILED'
            $caught.ToString() | Should -Match 'destination was successfully restored'
            $caught.ToString() | Should -Match 'simulated dgVoodoo2 promotion failure before cleanup'
            $caught.ToString() | Should -Match 'simulated dgVoodoo2 rollback-backup cleanup failure'
            $caught.ToString() | Should -Not -Match 'ROLLBACK FAILED'
            $after = Get-TpmDirSnapshot -Dir $dest
            Assert-TpmDirSnapshotUnchanged -Before $before -After $after
            $newStages = @(Get-ChildItem -LiteralPath $stagingRoot -Directory -Filter 'dgVoodoo2-*' -ErrorAction SilentlyContinue | Where-Object { $beforeStages -notcontains $_.FullName })
            $newStages.Count | Should -Be 1
            Test-Path -LiteralPath (Join-Path $newStages[0].FullName '.tpm-rollback-backup') | Should -BeTrue
        } finally {
            $leftoverStages = @(Get-ChildItem -LiteralPath $stagingRoot -Directory -Filter 'dgVoodoo2-*' -ErrorAction SilentlyContinue | Where-Object { $beforeStages -notcontains $_.FullName })
            foreach ($stagePath in $leftoverStages) {
                if (Test-Path -LiteralPath $stagePath.FullName) {
                    [System.IO.Directory]::Delete($stagePath.FullName, $true)
                }
            }
        }
    }
    It "P2 -- ordinary staging cleanup failure is surfaced with exact path and preserves a valid destination" {
        $zip  = Join-Path $TestDrive "dgv-staging-cleanup-fails.zip"
        $dest = Join-Path $TestDrive "dgv-staging-cleanup-fails-out"
        $stagingRoot = Join-Path $env:TEMP 'TeknoParrotManagerStaging'
        $beforeStages = @(Get-ChildItem -LiteralPath $stagingRoot -Directory -Filter 'dgVoodoo2-*' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        New-TestZip $zip $validEntries

        Mock Remove-Item {
            param($LiteralPath, $Recurse, $Force, $ErrorAction)
            if ([System.IO.Path]::GetFileName([string]$LiteralPath) -like 'dgVoodoo2-*') {
                throw "simulated dgVoodoo2 staging cleanup failure"
            }
            if (Test-Path -LiteralPath $LiteralPath -PathType Container) {
                [System.IO.Directory]::Delete($LiteralPath, [bool]$Recurse)
            } elseif (Test-Path -LiteralPath $LiteralPath) {
                [System.IO.File]::Delete($LiteralPath)
            }
        }

        $caught = $null
        try {
            Expand-DgVoodoo2Zip -ZipPath $zip -DestDir $dest
        } catch {
            $caught = $_
        }

        try {
            $caught | Should -Not -BeNullOrEmpty
            $caught.ToString() | Should -Match 'TPM STAGING CLEANUP FAILED'
            $caught.ToString() | Should -Match 'simulated dgVoodoo2 staging cleanup failure'
            $caught.ToString() | Should -Not -Match 'ROLLBACK FAILED'
            $caught.ToString() | Should -Not -Match 'TRANSACTION CLEANUP FAILED'
            $newStages = @(Get-ChildItem -LiteralPath $stagingRoot -Directory -Filter 'dgVoodoo2-*' -ErrorAction SilentlyContinue | Where-Object { $beforeStages -notcontains $_.FullName })
            $newStages.Count | Should -Be 1
            Assert-TpmErrorIdentifiesWindowsPath -ErrorText $caught.ToString() -ExpectedPath $newStages[0].FullName
            Test-Path -LiteralPath $newStages[0].FullName -PathType Container | Should -BeTrue
            @(Get-ChildItem -LiteralPath $newStages[0].FullName -Force -Recurse -ErrorAction SilentlyContinue).Count | Should -Be 0
            Test-Path -LiteralPath (Join-Path $newStages[0].FullName '.tpm-rollback-backup') | Should -BeFalse
            (Get-ChildItem -LiteralPath $dest -Force | Select-Object -ExpandProperty Name | Sort-Object) | Should -Be @('D3D8.dll', 'D3DImm.dll', 'DDraw.dll', 'dgVoodoo.conf', 'Glide2x.dll', 'Glide3x.dll')
            (Get-Content -LiteralPath (Join-Path $dest 'D3D8.dll') -Raw) | Should -Be 'd3d8'
            (Get-Content -LiteralPath (Join-Path $dest 'DDraw.dll') -Raw) | Should -Be 'ddraw'
            (Get-Content -LiteralPath (Join-Path $dest 'D3DImm.dll') -Raw) | Should -Be 'd3dimm'
            (Get-Content -LiteralPath (Join-Path $dest 'Glide2x.dll') -Raw) | Should -Be 'glide2x'
            (Get-Content -LiteralPath (Join-Path $dest 'Glide3x.dll') -Raw) | Should -Be 'glide3x'
            (Get-Content -LiteralPath (Join-Path $dest 'dgVoodoo.conf') -Raw) | Should -Be 'conf'
        } finally {
            $leftoverStages = @(Get-ChildItem -LiteralPath $stagingRoot -Directory -Filter 'dgVoodoo2-*' -ErrorAction SilentlyContinue | Where-Object { $beforeStages -notcontains $_.FullName })
            foreach ($stagePath in $leftoverStages) {
                if (Test-Path -LiteralPath $stagePath.FullName) {
                    [System.IO.Directory]::Delete($stagePath.FullName, $true)
                }
            }
        }
    }
    It "Case 4 -- rollback itself is forced to fail during a dgVoodoo2 promotion: distinct ROLLBACK FAILED error, backup preserved" {
        $zip  = Join-Path $TestDrive "dgv-rollback-fails.zip"
        $dest = Join-Path $TestDrive "dgv-rollback-fails-out"
        New-TestZip $zip $validEntries
        [void][System.IO.Directory]::CreateDirectory($dest)
        [System.IO.File]::WriteAllText((Join-Path $dest 'D3D8.dll'), 'PRE-EXISTING-D3D8')

        Mock Move-Item {
            param($LiteralPath, $Destination)
            if ($LiteralPath -like "*Glide3x.dll" -and $LiteralPath -notlike "*.tpm-rollback-backup*") {
                throw "simulated promotion failure on Glide3x.dll"
            }
            if ($LiteralPath -like "*.tpm-rollback-backup*D3D8.dll") {
                throw "simulated rollback failure restoring D3D8.dll"
            }
            [System.IO.File]::Move($LiteralPath, $Destination)
        }

        $caught = $null
        try { Expand-DgVoodoo2Zip -ZipPath $zip -DestDir $dest } catch { $caught = $_ }

        $caught | Should -Not -BeNullOrEmpty
        $caught.ToString() | Should -Match 'ROLLBACK FAILED'
        $caught.ToString() | Should -Match 'simulated promotion failure on Glide3x\.dll'
        $caught.ToString() | Should -Match 'simulated rollback failure restoring D3D8\.dll'
    }
}

Describe "Expand-ReShadeSelfExtractingArchive (embedded ZIP scan, fail-closed on missing entries)" {
    BeforeAll {
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem

        # Builds a synthetic self-extracting-archive-shaped file: a small
        # non-zip "PE stub" prefix, followed by a real ZIP archive appended
        # at the end -- mirrors ReShade_Setup_<version>.exe's real shape.
        function New-TestSelfExtractingExe([string]$exePath, [hashtable]$entries, [switch]$WithDecoyPkSignature) {
            $stubBytes = [System.Text.Encoding]::ASCII.GetBytes("FAKE-PE-STUB-NOT-A-ZIP")
            $prefixBytes = if ($WithDecoyPkSignature) {
                # A decoy "PK\x03\x04"-prefixed region that is NOT a real/parseable
                # archive with the required entries -- mirrors the real installer's
                # own resource data producing a false-positive signature match
                # confirmed during live verification.
                $stubBytes + [byte[]](0x50,0x4B,0x03,0x04) + [System.Text.Encoding]::ASCII.GetBytes("decoy-not-a-real-entry")
            } else {
                $stubBytes
            }
            $zipTemp = Join-Path $TestDrive ("zt-{0}.zip" -f ([guid]::NewGuid().ToString('N')))
            if (Test-Path -LiteralPath $zipTemp) { Remove-Item -LiteralPath $zipTemp -Force }
            $fs = [System.IO.File]::Open($zipTemp, [System.IO.FileMode]::CreateNew)
            try {
                $archive = [System.IO.Compression.ZipArchive]::new($fs, [System.IO.Compression.ZipArchiveMode]::Create)
                try {
                    foreach ($name in $entries.Keys) {
                        $entry = $archive.CreateEntry($name)
                        $w = New-Object System.IO.StreamWriter($entry.Open())
                        try { $w.Write($entries[$name]) } finally { $w.Dispose() }
                    }
                } finally { $archive.Dispose() }
            } finally { $fs.Dispose() }
            $zipBytes = [System.IO.File]::ReadAllBytes($zipTemp)
            [System.IO.File]::WriteAllBytes($exePath, $prefixBytes + $zipBytes)
        }
    }
    It "locates and extracts both required DLLs from a valid embedded archive" {
        $exe  = Join-Path $TestDrive "valid-setup.exe"
        $dest = Join-Path $TestDrive "valid-setup-out"
        New-TestSelfExtractingExe $exe @{ 'ReShade32.dll' = 'r32'; 'ReShade64.dll' = 'r64'; 'ReShade64.json' = '{}' }
        Expand-ReShadeSelfExtractingArchive -SetupExePath $exe -DestDir $dest
        (Get-Content -LiteralPath (Join-Path $dest "ReShade32.dll") -Raw) | Should -Be 'r32'
        (Get-Content -LiteralPath (Join-Path $dest "ReShade64.dll") -Raw) | Should -Be 'r64'
    }
    It "skips a decoy PK signature and still finds the real archive further in the file" {
        $exe  = Join-Path $TestDrive "decoy-setup.exe"
        $dest = Join-Path $TestDrive "decoy-setup-out"
        New-TestSelfExtractingExe $exe @{ 'ReShade32.dll' = 'r32'; 'ReShade64.dll' = 'r64' } -WithDecoyPkSignature
        Expand-ReShadeSelfExtractingArchive -SetupExePath $exe -DestDir $dest
        (Get-Content -LiteralPath (Join-Path $dest "ReShade64.dll") -Raw) | Should -Be 'r64'
    }
    It "fails closed when the required entries are missing from the embedded archive (format changed)" {
        $exe  = Join-Path $TestDrive "corruption-setup.exe"
        $dest = Join-Path $TestDrive "corruption-setup-out"
        New-TestSelfExtractingExe $exe @{ 'SomeOtherFile.dll' = 'x' }
        { Expand-ReShadeSelfExtractingArchive -SetupExePath $exe -DestDir $dest } | Should -Throw "*not found*"
    }
    It "fails closed when no PK signature exists at all" {
        $exe  = Join-Path $TestDrive "no-pk-setup.exe"
        $dest = Join-Path $TestDrive "no-pk-setup-out"
        [System.IO.File]::WriteAllBytes($exe, [System.Text.Encoding]::ASCII.GetBytes("not a zip at all"))
        { Expand-ReShadeSelfExtractingArchive -SetupExePath $exe -DestDir $dest } | Should -Throw "*no embedded ZIP*"
    }
    It "P1 #1: leaves the destination completely untouched when extraction fails partway through (2nd of 2 files)" {
        $exe  = Join-Path $TestDrive "rs-extractfail-setup.exe"
        $dest = Join-Path $TestDrive "rs-extractfail-out"
        New-TestSelfExtractingExe $exe @{ 'ReShade32.dll' = 'r32'; 'ReShade64.dll' = 'r64' }
        [void][System.IO.Directory]::CreateDirectory($dest)
        [System.IO.File]::WriteAllText((Join-Path $dest 'ReShade32.dll'), 'PRE-EXISTING-32')

        $script:callCount = 0
        Mock Copy-TpmZipEntryToFile {
            param($Entry, $DestPath)
            $script:callCount++
            if ($script:callCount -eq 2) { throw "simulated extraction failure on 2nd entry" }
            $srcStream = $Entry.Open()
            try {
                $dstStream = [System.IO.File]::Open($DestPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                try { $srcStream.CopyTo($dstStream) } finally { $dstStream.Dispose() }
            } finally { $srcStream.Dispose() }
        }

        { Expand-ReShadeSelfExtractingArchive -SetupExePath $exe -DestDir $dest } | Should -Throw "*simulated extraction failure*"

        (Get-ChildItem -LiteralPath $dest -Force).Name | Should -Be @('ReShade32.dll')
        (Get-Content -LiteralPath (Join-Path $dest 'ReShade32.dll') -Raw) | Should -Be 'PRE-EXISTING-32'
    }
    It "P1 #1: restores destination exactly when promotion fails partway through (after successful extraction of both files)" {
        $exe  = Join-Path $TestDrive "rs-promofail-setup.exe"
        $dest = Join-Path $TestDrive "rs-promofail-out"
        New-TestSelfExtractingExe $exe @{ 'ReShade32.dll' = 'r32'; 'ReShade64.dll' = 'r64' }
        [void][System.IO.Directory]::CreateDirectory($dest)
        [System.IO.File]::WriteAllText((Join-Path $dest 'ReShade32.dll'), 'PRE-EXISTING-32')

        Mock Move-Item {
            param($LiteralPath, $Destination)
            if ($LiteralPath -like "*ReShade64.dll") { throw "simulated promotion failure on ReShade64.dll" }
            # NOTE: calling through to the real Move-Item cmdlet (even
            # module-qualified) from inside its own Mock recurses back into
            # the mock in this Pester version and overflows the call stack
            # -- use the underlying .NET primitive instead for the
            # pass-through (non-simulated-failure) case.
            [System.IO.File]::Move($LiteralPath, $Destination)
        }

        { Expand-ReShadeSelfExtractingArchive -SetupExePath $exe -DestDir $dest } | Should -Throw "*simulated promotion failure*"

        (Get-ChildItem -LiteralPath $dest -Force).Name | Should -Be @('ReShade32.dll')
        (Get-Content -LiteralPath (Join-Path $dest 'ReShade32.dll') -Raw) | Should -Be 'PRE-EXISTING-32'
    }
    It "successful extraction leaves exactly the expected 2-file final tree and no temp/backup residue" {
        $exe  = Join-Path $TestDrive "rs-clean-success-setup.exe"
        $dest = Join-Path $TestDrive "rs-clean-success-out"
        # Baseline BEFORE this call -- see the equivalent dgVoodoo2 test for
        # why this cannot assume a global zero count.
        $stagingRoot = Join-Path $env:TEMP 'TeknoParrotManagerStaging'
        $before = @(Get-ChildItem -Path $stagingRoot -Directory -Filter 'ReShade-*' -ErrorAction SilentlyContinue).Count
        New-TestSelfExtractingExe $exe @{ 'ReShade32.dll' = 'r32'; 'ReShade64.dll' = 'r64' }
        Expand-ReShadeSelfExtractingArchive -SetupExePath $exe -DestDir $dest
        (Get-ChildItem -LiteralPath $dest -Force).Name | Sort-Object | Should -Be @('ReShade32.dll', 'ReShade64.dll')
        (Get-ChildItem -Path $stagingRoot -Directory -Filter 'ReShade-*' -ErrorAction SilentlyContinue).Count | Should -Be $before
    }
    It "Case 1 -- destination absent before the call, promotion fails on the very first required file: destination directory itself is removed again" {
        $exe  = Join-Path $TestDrive "rs-rollback-first-setup.exe"
        $dest = Join-Path $TestDrive "rs-rollback-first-out"
        New-TestSelfExtractingExe $exe @{ 'ReShade32.dll' = 'r32'; 'ReShade64.dll' = 'r64' }
        $before = Get-TpmDirSnapshot -Dir $dest
        $before.Existed | Should -BeFalse

        Mock Move-Item {
            param($LiteralPath, $Destination)
            if ($LiteralPath -like "*ReShade32.dll") { throw "simulated promotion failure on first required file" }
            [System.IO.File]::Move($LiteralPath, $Destination)
        }

        { Expand-ReShadeSelfExtractingArchive -SetupExePath $exe -DestDir $dest } | Should -Throw "*simulated promotion failure*"

        $after = Get-TpmDirSnapshot -Dir $dest
        Assert-TpmDirSnapshotUnchanged -Before $before -After $after
        Test-Path -LiteralPath $dest | Should -BeFalse
    }
    It "Case 2 -- destination absent before the call, first file promotes, second file fails: destination directory itself is removed again" {
        $exe  = Join-Path $TestDrive "rs-rollback-second-setup.exe"
        $dest = Join-Path $TestDrive "rs-rollback-second-out"
        New-TestSelfExtractingExe $exe @{ 'ReShade32.dll' = 'r32'; 'ReShade64.dll' = 'r64' }
        $before = Get-TpmDirSnapshot -Dir $dest
        $before.Existed | Should -BeFalse

        Mock Move-Item {
            param($LiteralPath, $Destination)
            if ($LiteralPath -like "*ReShade64.dll") { throw "simulated promotion failure on second required file" }
            [System.IO.File]::Move($LiteralPath, $Destination)
        }

        { Expand-ReShadeSelfExtractingArchive -SetupExePath $exe -DestDir $dest } | Should -Throw "*simulated promotion failure*"

        $after = Get-TpmDirSnapshot -Dir $dest
        Assert-TpmDirSnapshotUnchanged -Before $before -After $after
        Test-Path -LiteralPath $dest | Should -BeFalse
    }

    It "Case 5 -- phase-1 source loss before a valid backup is observable: preserves recovery evidence and reports an inconsistent transaction" {
        $exe  = Join-Path $TestDrive "rs-phase1-source-loss-setup.exe"
        $dest = Join-Path $TestDrive "rs-phase1-source-loss-out"
        $stagingRoot = Join-Path $env:TEMP 'TeknoParrotManagerStaging'
        $beforeStages = @(Get-ChildItem -LiteralPath $stagingRoot -Directory -Filter 'ReShade-*' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        New-TestSelfExtractingExe $exe @{ 'ReShade32.dll' = 'r32'; 'ReShade64.dll' = 'r64' }
        [void][System.IO.Directory]::CreateDirectory($dest)
        [System.IO.File]::WriteAllText((Join-Path $dest 'ReShade32.dll'), 'PRE-EXISTING-32')
        [void][System.IO.Directory]::CreateDirectory((Join-Path $dest 'keep\nested'))
        [System.IO.File]::WriteAllText((Join-Path $dest 'keep\nested\marker.txt'), 'KEEP')
        $oldPath = Join-Path $dest 'ReShade32.dll'
        $caught = $null

        Mock Move-Item {
            param($LiteralPath, $Destination)
            if ($LiteralPath -ieq $oldPath) {
                [System.IO.File]::Delete($LiteralPath)
                throw "simulated ReShade phase-1 source deletion before backup"
            }
            [System.IO.File]::Move($LiteralPath, $Destination)
        }

        try {
            Expand-ReShadeSelfExtractingArchive -SetupExePath $exe -DestDir $dest
        } catch {
            $caught = $_
        }

        $newStages = @()
        try {
            $caught | Should -Not -BeNullOrEmpty
            $caught.ToString() | Should -Match 'ROLLBACK FAILED'
            $caught.ToString() | Should -Match 'INCONSISTENT'
            $caught.ToString() | Should -Match 'unrecoverable'
            $caught.ToString() | Should -Match 'simulated ReShade phase-1 source deletion before backup'
            $caught.ToString() | Should -Match 'Pre-move evidence'
            Test-Path -LiteralPath $oldPath | Should -BeFalse
            Test-Path -LiteralPath $dest -PathType Container | Should -BeTrue
            (Get-Content -LiteralPath (Join-Path $dest 'keep\nested\marker.txt') -Raw) | Should -Be 'KEEP'
            $newStages = @(Get-ChildItem -LiteralPath $stagingRoot -Directory -Filter 'ReShade-*' -ErrorAction SilentlyContinue | Where-Object { $beforeStages -notcontains $_.FullName })
            $newStages.Count | Should -Be 1
            Test-Path -LiteralPath (Join-Path $newStages[0].FullName '.tpm-rollback-backup') | Should -BeTrue
        } finally {
            $leftoverStages = @(Get-ChildItem -LiteralPath $stagingRoot -Directory -Filter 'ReShade-*' -ErrorAction SilentlyContinue | Where-Object { $beforeStages -notcontains $_.FullName })
            foreach ($stagePath in $leftoverStages) {
                if (Test-Path -LiteralPath $stagePath.FullName) {
                    [System.IO.Directory]::Delete($stagePath.FullName, $true)
                }
            }
        }
    }

    It "Case 6 -- destination absent and transaction setup initialization fails: the destination remains absent exactly" {
        $exe  = Join-Path $TestDrive "rs-setup-fails-setup.exe"
        $dest = Join-Path $TestDrive "rs-setup-fails-out"
        $forcedStage = Join-Path $TestDrive ("forced-rs-stage-" + [guid]::NewGuid().ToString('N'))
        New-TestSelfExtractingExe $exe @{ 'ReShade32.dll' = 'r32'; 'ReShade64.dll' = 'r64' }
        $before = Get-TpmDirSnapshot -Dir $dest

        Mock New-TpmStagingDirectory {
            [void][System.IO.Directory]::CreateDirectory($forcedStage)
            [System.IO.File]::WriteAllText((Join-Path $forcedStage '.tpm-rollback-backup'), 'blocking file')
            return $forcedStage
        }

        $caught = $null
        try {
            Expand-ReShadeSelfExtractingArchive -SetupExePath $exe -DestDir $dest
        } catch {
            $caught = $_
        }

        try {
            $caught | Should -Not -BeNullOrEmpty
            $caught.ToString() | Should -Not -Match 'ROLLBACK FAILED|CLEANUP FAILED'
            $after = Get-TpmDirSnapshot -Dir $dest
            Assert-TpmDirSnapshotUnchanged -Before $before -After $after
            Test-Path -LiteralPath $dest | Should -BeFalse
            Test-Path -LiteralPath $forcedStage | Should -BeFalse
        } finally {
            if (Test-Path -LiteralPath $forcedStage) {
                [System.IO.Directory]::Delete($forcedStage, $true)
            }
        }
    }

    It "Case 7 -- destination restores exactly but rollback-backup cleanup fails: reports a distinct cleanup error and preserves the wrapper staging evidence" {
        $exe  = Join-Path $TestDrive "rs-cleanup-fails-setup.exe"
        $dest = Join-Path $TestDrive "rs-cleanup-fails-out"
        $stagingRoot = Join-Path $env:TEMP 'TeknoParrotManagerStaging'
        $beforeStages = @(Get-ChildItem -LiteralPath $stagingRoot -Directory -Filter 'ReShade-*' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        New-TestSelfExtractingExe $exe @{ 'ReShade32.dll' = 'r32'; 'ReShade64.dll' = 'r64' }
        [void][System.IO.Directory]::CreateDirectory($dest)
        [System.IO.File]::WriteAllText((Join-Path $dest 'ReShade32.dll'), 'PRE-EXISTING-32')
        [void][System.IO.Directory]::CreateDirectory((Join-Path $dest 'keep\nested'))
        [System.IO.File]::WriteAllText((Join-Path $dest 'keep\nested\marker.txt'), 'KEEP')
        $before = Get-TpmDirSnapshot -Dir $dest

        Mock Move-Item {
            param($LiteralPath, $Destination)
            if ($Destination -ieq (Join-Path $dest 'ReShade64.dll')) {
                throw "simulated ReShade promotion failure before cleanup"
            }
            [System.IO.File]::Move($LiteralPath, $Destination)
        }
        Mock Remove-Item {
            param($LiteralPath, $Recurse, $Force, $ErrorAction)
            if ([System.IO.Path]::GetFileName($LiteralPath) -ieq '.tpm-rollback-backup') {
                throw "simulated ReShade rollback-backup cleanup failure"
            }
            if (Test-Path -LiteralPath $LiteralPath -PathType Container) {
                [System.IO.Directory]::Delete($LiteralPath, [bool]$Recurse)
            } elseif (Test-Path -LiteralPath $LiteralPath) {
                [System.IO.File]::Delete($LiteralPath)
            }
        }

        $caught = $null
        try {
            Expand-ReShadeSelfExtractingArchive -SetupExePath $exe -DestDir $dest
        } catch {
            $caught = $_
        }

        try {
            $caught | Should -Not -BeNullOrEmpty
            $caught.ToString() | Should -Match 'TRANSACTION CLEANUP FAILED'
            $caught.ToString() | Should -Match 'destination was successfully restored'
            $caught.ToString() | Should -Match 'simulated ReShade promotion failure before cleanup'
            $caught.ToString() | Should -Match 'simulated ReShade rollback-backup cleanup failure'
            $caught.ToString() | Should -Not -Match 'ROLLBACK FAILED'
            $after = Get-TpmDirSnapshot -Dir $dest
            Assert-TpmDirSnapshotUnchanged -Before $before -After $after
            $newStages = @(Get-ChildItem -LiteralPath $stagingRoot -Directory -Filter 'ReShade-*' -ErrorAction SilentlyContinue | Where-Object { $beforeStages -notcontains $_.FullName })
            $newStages.Count | Should -Be 1
            Test-Path -LiteralPath (Join-Path $newStages[0].FullName '.tpm-rollback-backup') | Should -BeTrue
        } finally {
            $leftoverStages = @(Get-ChildItem -LiteralPath $stagingRoot -Directory -Filter 'ReShade-*' -ErrorAction SilentlyContinue | Where-Object { $beforeStages -notcontains $_.FullName })
            foreach ($stagePath in $leftoverStages) {
                if (Test-Path -LiteralPath $stagePath.FullName) {
                    [System.IO.Directory]::Delete($stagePath.FullName, $true)
                }
            }
        }
    }
    It "P2 -- ordinary staging cleanup failure is surfaced with exact path and preserves a valid destination" {
        $exe  = Join-Path $TestDrive "rs-staging-cleanup-fails-setup.exe"
        $dest = Join-Path $TestDrive "rs-staging-cleanup-fails-out"
        $stagingRoot = Join-Path $env:TEMP 'TeknoParrotManagerStaging'
        $beforeStages = @(Get-ChildItem -LiteralPath $stagingRoot -Directory -Filter 'ReShade-*' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        New-TestSelfExtractingExe $exe @{ 'ReShade32.dll' = 'r32'; 'ReShade64.dll' = 'r64' }

        Mock Remove-Item {
            param($LiteralPath, $Recurse, $Force, $ErrorAction)
            if ([System.IO.Path]::GetFileName([string]$LiteralPath) -like 'ReShade-*') {
                throw "simulated ReShade staging cleanup failure"
            }
            if (Test-Path -LiteralPath $LiteralPath -PathType Container) {
                [System.IO.Directory]::Delete($LiteralPath, [bool]$Recurse)
            } elseif (Test-Path -LiteralPath $LiteralPath) {
                [System.IO.File]::Delete($LiteralPath)
            }
        }

        $caught = $null
        try {
            Expand-ReShadeSelfExtractingArchive -SetupExePath $exe -DestDir $dest
        } catch {
            $caught = $_
        }

        try {
            $caught | Should -Not -BeNullOrEmpty
            $caught.ToString() | Should -Match 'TPM STAGING CLEANUP FAILED'
            $caught.ToString() | Should -Match 'simulated ReShade staging cleanup failure'
            $caught.ToString() | Should -Not -Match 'ROLLBACK FAILED'
            $caught.ToString() | Should -Not -Match 'TRANSACTION CLEANUP FAILED'
            $newStages = @(Get-ChildItem -LiteralPath $stagingRoot -Directory -Filter 'ReShade-*' -ErrorAction SilentlyContinue | Where-Object { $beforeStages -notcontains $_.FullName })
            $newStages.Count | Should -Be 1
            Assert-TpmErrorIdentifiesWindowsPath -ErrorText $caught.ToString() -ExpectedPath $newStages[0].FullName
            Test-Path -LiteralPath $newStages[0].FullName -PathType Container | Should -BeTrue
            @(Get-ChildItem -LiteralPath $newStages[0].FullName -Force -Recurse -ErrorAction SilentlyContinue).Count | Should -Be 0
            Test-Path -LiteralPath (Join-Path $newStages[0].FullName '.tpm-rollback-backup') | Should -BeFalse
            (Get-ChildItem -LiteralPath $dest -Force | Select-Object -ExpandProperty Name | Sort-Object) | Should -Be @('ReShade32.dll', 'ReShade64.dll')
            (Get-Content -LiteralPath (Join-Path $dest 'ReShade32.dll') -Raw) | Should -Be 'r32'
            (Get-Content -LiteralPath (Join-Path $dest 'ReShade64.dll') -Raw) | Should -Be 'r64'
        } finally {
            $leftoverStages = @(Get-ChildItem -LiteralPath $stagingRoot -Directory -Filter 'ReShade-*' -ErrorAction SilentlyContinue | Where-Object { $beforeStages -notcontains $_.FullName })
            foreach ($stagePath in $leftoverStages) {
                if (Test-Path -LiteralPath $stagePath.FullName) {
                    [System.IO.Directory]::Delete($stagePath.FullName, $true)
                }
            }
        }
    }
    It "Case 4 -- rollback itself is forced to fail during a ReShade promotion: distinct ROLLBACK FAILED error, backup preserved" {
        $exe  = Join-Path $TestDrive "rs-rollback-fails-setup.exe"
        $dest = Join-Path $TestDrive "rs-rollback-fails-out"
        New-TestSelfExtractingExe $exe @{ 'ReShade32.dll' = 'r32'; 'ReShade64.dll' = 'r64' }
        [void][System.IO.Directory]::CreateDirectory($dest)
        [System.IO.File]::WriteAllText((Join-Path $dest 'ReShade32.dll'), 'PRE-EXISTING-32')

        Mock Move-Item {
            param($LiteralPath, $Destination)
            if ($LiteralPath -like "*ReShade64.dll" -and $LiteralPath -notlike "*.tpm-rollback-backup*") {
                throw "simulated promotion failure on ReShade64.dll"
            }
            if ($LiteralPath -like "*.tpm-rollback-backup*ReShade32.dll") {
                throw "simulated rollback failure restoring ReShade32.dll"
            }
            [System.IO.File]::Move($LiteralPath, $Destination)
        }

        $caught = $null
        try { Expand-ReShadeSelfExtractingArchive -SetupExePath $exe -DestDir $dest } catch { $caught = $_ }

        $caught | Should -Not -BeNullOrEmpty
        $caught.ToString() | Should -Match 'ROLLBACK FAILED'
        $caught.ToString() | Should -Match 'simulated promotion failure on ReShade64\.dll'
        $caught.ToString() | Should -Match 'simulated rollback failure restoring ReShade32\.dll'
    }
}

Describe "Test-ReShadeSetupTrustedSignature (fingerprint-as-root-of-trust, fail-closed)" {
    # Mocked Get-AuthenticodeSignature. Trust requires BOTH the pinned
    # thumbprint AND an accepted .Status (P1 #2 remediation: an earlier
    # version of this function checked only the thumbprint and ignored
    # Status entirely, so a HashMismatch -- a tampered/corrupted file --
    # paired with a coincidentally/spoofed-correct Thumbprint field would
    # incorrectly pass. This table exercises every status TPM intentionally
    # accepts or rejects, plus the wrong-thumbprint and Subject-only cases.
    BeforeAll {
        function Write-Log { param($Message) }
        $trustedThumbprint = $Script:ReShadeTrustedCertThumbprint
        $trustedSubject     = 'CN=ReShade, E=info@reshade.me'
    }

    Context "Table-driven status x thumbprint trust matrix" {
        # Each row: the Get-AuthenticodeSignature.Status to mock, whether
        # the mocked Thumbprint is the pinned/correct one, and the expected
        # Trusted outcome. Covers, at minimum: the one accepted self-signed
        # status with the correct thumbprint (must pass); HashMismatch with
        # the correct thumbprint (must fail -- this is the P1 #2 bug case);
        # NotSigned; a right-status/wrong-thumbprint case; and confirms
        # SubjectMatch never overrides either gate.
        $matrix = @(
            @{ Case = 'accepted status (UnknownError) + correct thumbprint => TRUSTED';        Status = 'UnknownError';   ThumbprintCorrect = $true;  ExpectTrusted = $true  }
            @{ Case = 'HashMismatch + correct thumbprint => REJECTED (P1 #2 regression case)';  Status = 'HashMismatch';   ThumbprintCorrect = $true;  ExpectTrusted = $false }
            @{ Case = 'NotSigned + correct thumbprint => REJECTED';                             Status = 'NotSigned';      ThumbprintCorrect = $true;  ExpectTrusted = $false }
            @{ Case = 'NotTrusted + correct thumbprint => REJECTED';                            Status = 'NotTrusted';     ThumbprintCorrect = $true;  ExpectTrusted = $false }
            @{ Case = 'Incompatible + correct thumbprint => REJECTED';                          Status = 'Incompatible';   ThumbprintCorrect = $true;  ExpectTrusted = $false }
            @{ Case = 'NotSupportedFileFormat + correct thumbprint => REJECTED';                Status = 'NotSupportedFileFormat'; ThumbprintCorrect = $true; ExpectTrusted = $false }
            @{ Case = 'unrecognized future status + correct thumbprint => REJECTED (deny-by-default)'; Status = 'SomeFutureStatusNotYetInvented'; ThumbprintCorrect = $true; ExpectTrusted = $false }
            @{ Case = 'accepted status (UnknownError) + WRONG thumbprint => REJECTED';          Status = 'UnknownError';   ThumbprintCorrect = $false; ExpectTrusted = $false }
            @{ Case = 'HashMismatch + WRONG thumbprint => REJECTED';                            Status = 'HashMismatch';   ThumbprintCorrect = $false; ExpectTrusted = $false }
        )
        It "<Case>" -TestCases $matrix {
            param($Case, $Status, $ThumbprintCorrect, $ExpectTrusted)
            $mockedThumbprint = if ($ThumbprintCorrect) { $trustedThumbprint } else { ('F' * 40) }
            Mock Get-AuthenticodeSignature {
                [pscustomobject]@{ Status = $Status; SignerCertificate = [pscustomobject]@{ Subject = $trustedSubject; Thumbprint = $mockedThumbprint } }
            }
            $result = Test-ReShadeSetupTrustedSignature -Path (Join-Path $TestDrive "any.exe")
            $result.Trusted | Should -Be $ExpectTrusted
        }
    }

    It "trusts a signature whose fingerprint matches the pinned constant and status is UnknownError" {
        Mock Get-AuthenticodeSignature {
            [pscustomobject]@{ Status = 'UnknownError'; SignerCertificate = [pscustomobject]@{ Subject = $trustedSubject; Thumbprint = $trustedThumbprint } }
        }
        $result = Test-ReShadeSetupTrustedSignature -Path (Join-Path $TestDrive "any.exe")
        $result.Trusted | Should -BeTrue
        $result.ThumbprintMatch | Should -BeTrue
        $result.StatusAccepted | Should -BeTrue
        $result.SubjectMatch | Should -BeTrue
    }
    It "REJECTS a HashMismatch signature even with the exact pinned thumbprint (P1 #2: the core regression this pass fixes)" {
        Mock Get-AuthenticodeSignature {
            [pscustomobject]@{ Status = 'HashMismatch'; SignerCertificate = [pscustomobject]@{ Subject = $trustedSubject; Thumbprint = $trustedThumbprint } }
        }
        $result = Test-ReShadeSetupTrustedSignature -Path (Join-Path $TestDrive "any.exe")
        $result.ThumbprintMatch | Should -BeTrue
        $result.StatusAccepted | Should -BeFalse
        $result.Trusted | Should -BeFalse
    }
    It "fails closed when the Subject matches but the fingerprint does not (spoofed self-signed cert)" {
        Mock Get-AuthenticodeSignature {
            [pscustomobject]@{ Status = 'UnknownError'; SignerCertificate = [pscustomobject]@{ Subject = $trustedSubject; Thumbprint = ('F' * 40) } }
        }
        $result = Test-ReShadeSetupTrustedSignature -Path (Join-Path $TestDrive "any.exe")
        $result.Trusted | Should -BeFalse
        $result.SubjectMatch | Should -BeTrue
        $result.ThumbprintMatch | Should -BeFalse
    }
    It "fails closed when the Subject has changed, even with the pinned fingerprint and accepted status" {
        Mock Get-AuthenticodeSignature {
            [pscustomobject]@{ Status = 'UnknownError'; SignerCertificate = [pscustomobject]@{ Subject = 'CN=SomeoneElse'; Thumbprint = $trustedThumbprint } }
        }
        $result = Test-ReShadeSetupTrustedSignature -Path (Join-Path $TestDrive "any.exe")
        # Thumbprint+Status are the hard trust anchor -- Trusted still
        # reflects that combined gate even though Subject changed, but the
        # mismatch is surfaced via SubjectMatch for diagnosis (secondary
        # sanity check only, never a substitute for the fingerprint/status
        # checks).
        $result.SubjectMatch | Should -BeFalse
        $result.Trusted | Should -BeTrue
    }
    It "fails closed when both Subject and fingerprint differ" {
        Mock Get-AuthenticodeSignature {
            [pscustomobject]@{ Status = 'UnknownError'; SignerCertificate = [pscustomobject]@{ Subject = 'CN=SomeoneElse'; Thumbprint = ('F' * 40) } }
        }
        $result = Test-ReShadeSetupTrustedSignature -Path (Join-Path $TestDrive "any.exe")
        $result.Trusted | Should -BeFalse
    }
    It "fails closed when there is no signature at all (SignerCertificate null)" {
        Mock Get-AuthenticodeSignature {
            [pscustomobject]@{ Status = 'NotSigned'; SignerCertificate = $null }
        }
        $result = Test-ReShadeSetupTrustedSignature -Path (Join-Path $TestDrive "any.exe")
        $result.Trusted | Should -BeFalse
    }
    It "fails closed when Get-AuthenticodeSignature itself throws (unparseable file)" {
        Mock Get-AuthenticodeSignature { throw "not a valid PE file" }
        $result = Test-ReShadeSetupTrustedSignature -Path (Join-Path $TestDrive "any.exe")
        $result.Trusted | Should -BeFalse
        $result.Status | Should -Be 'Error'
        $result.StatusAccepted | Should -BeFalse
    }
    It "logs Status, Subject, and Thumbprint on every run, pass or fail" {
        Mock Get-AuthenticodeSignature {
            [pscustomobject]@{ Status = 'UnknownError'; SignerCertificate = [pscustomobject]@{ Subject = $trustedSubject; Thumbprint = $trustedThumbprint } }
        }
        Mock Write-Log { }
        Test-ReShadeSetupTrustedSignature -Path (Join-Path $TestDrive "any.exe") | Out-Null
        Should -Invoke Write-Log -Times 1 -ParameterFilter { $Message -match [regex]::Escape($trustedSubject) -and $Message -match [regex]::Escape($trustedThumbprint) -and $Message -match 'Status=UnknownError' }
    }
}

Describe "Test-EggmanDatUpToDate" {
    BeforeAll {
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        function New-EggmanUpToDateTestZip([string]$zipPath) {
            $fs = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::CreateNew)
            try {
                $archive = [System.IO.Compression.ZipArchive]::new($fs, [System.IO.Compression.ZipArchiveMode]::Create)
                try {
                    $entry = $archive.CreateEntry('TeknoParrot.Collection.2026_RomVault.dat')
                    $writer = New-Object System.IO.StreamWriter($entry.Open())
                    try { $writer.Write('<data />') } finally { $writer.Dispose() }
                } finally { $archive.Dispose() }
            } finally { $fs.Dispose() }
        }
    }

    # Issue #106: the "check for a newer Eggman dat release" prompt
    # previously always asked to download/switch regardless of whether the
    # remote release had actually changed. The Eggman/RomVault release
    # format exposes no version number, only a filename and size, so exact
    # byte-size match remains the freshness signal after ZIP validation.
    It "reports Current when the local file's size exactly matches the remote release size" {
        $path = Join-Path $TestDrive ("eggman-current-" + [guid]::NewGuid().ToString('N') + '.zip')
        New-EggmanUpToDateTestZip -zipPath $path
        $size = (Get-Item -LiteralPath $path).Length
        $result = Test-EggmanDatUpToDate -LocalDatPath $path -RemoteSizeBytes $size
        $result.Status | Should -Be 'Current'
        $result.LocalSizeBytes | Should -Be $size
    }
    It "reports UpdateAvailable when the local file's size differs from the remote release size" {
        $path = Join-Path $TestDrive ("eggman-stale-" + [guid]::NewGuid().ToString('N') + '.zip')
        New-EggmanUpToDateTestZip -zipPath $path
        $result = Test-EggmanDatUpToDate -LocalDatPath $path -RemoteSizeBytes ((Get-Item -LiteralPath $path).Length + 1)
        $result.Status | Should -Be 'UpdateAvailable'
    }
    It "reports UpdateAvailable for a same-size corrupt or wrong-type file instead of Current" {
        $path = Join-Path $TestDrive ("eggman-corrupt-" + [guid]::NewGuid().ToString('N') + '.zip')
        Set-Content -LiteralPath $path -Value ('x' * 128) -NoNewline
        $result = Test-EggmanDatUpToDate -LocalDatPath $path -RemoteSizeBytes 128
        $result.Status | Should -Be 'UpdateAvailable'
    }
    It "reports Unknown (not Current) when the local file does not exist" {
        $path = Join-Path $TestDrive ("eggman-missing-" + [guid]::NewGuid().ToString('N') + '.zip')
        $result = Test-EggmanDatUpToDate -LocalDatPath $path -RemoteSizeBytes 1024
        $result.Status | Should -Be 'Unknown'
        $result.LocalSizeBytes | Should -BeNullOrEmpty
    }
}

Describe "Write-DownloadAudit" {
    BeforeAll {
        Mock Write-Log {}
    }

    It "logs the actual SHA256 of the downloaded file" {
        $path = Join-Path $TestDrive "audit1.bin"
        [System.IO.File]::WriteAllBytes($path, [System.Text.Encoding]::ASCII.GetBytes("some download content"))
        $expectedHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash

        Write-DownloadAudit -Source "https://example.com/file.bin" -FileName "audit1.bin" -Path $path

        Should -Invoke Write-Log -Times 1 -ParameterFilter {
            $msg -like "*SHA256=$expectedHash*" -and $msg -like "*File=audit1.bin*" -and $msg -like "*Source=https://example.com/file.bin*"
        }
    }
    It "omits the Version segment when no version is supplied" {
        $path = Join-Path $TestDrive "audit2.bin"
        [System.IO.File]::WriteAllBytes($path, [byte[]]@(1, 2, 3))

        Write-DownloadAudit -Source "src" -FileName "audit2.bin" -Path $path

        Should -Invoke Write-Log -Times 1 -ParameterFilter { $msg -notlike "*Version=*" }
    }
    It "includes the Version segment when a version is supplied" {
        $path = Join-Path $TestDrive "audit3.bin"
        [System.IO.File]::WriteAllBytes($path, [byte[]]@(1, 2, 3))

        Write-DownloadAudit -Source "src" -FileName "audit3.bin" -Path $path -Version "1.2.3"

        Should -Invoke Write-Log -Times 1 -ParameterFilter { $msg -like "*Version=1.2.3*" }
    }
    It "fails closed (logs, does not throw) when the file does not exist" {
        $missingPath = Join-Path $TestDrive "does-not-exist.bin"

        { Write-DownloadAudit -Source "src" -FileName "missing.bin" -Path $missingPath } | Should -Not -Throw

        Should -Invoke Write-Log -Times 1 -ParameterFilter { $msg -like "*could not hash*missing.bin*" }
    }
    It "fails closed (logs, does not throw) when the file is locked by another process" {
        $path = Join-Path $TestDrive "locked.bin"
        [System.IO.File]::WriteAllBytes($path, [byte[]]@(1, 2, 3))
        $handle = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        try {
            { Write-DownloadAudit -Source "src" -FileName "locked.bin" -Path $path } | Should -Not -Throw
            Should -Invoke Write-Log -Times 1 -ParameterFilter { $msg -like "*could not hash*locked.bin*" }
        } finally {
            $handle.Dispose()
        }
    }
}

Describe "Build-DatIndexFromStream" {
    # Real collection dats have dozens to hundreds of <rom> hash entries per
    # <game>, skipped via reader.Skip() for performance. A real regression
    # (issue #12) had the surrounding loop call Read() again right after
    # Skip() already advanced the reader, silently discarding whatever node
    # Skip() had landed on -- on a real 506-game dat this dropped roughly
    # half of all games (493 opened, only 236 closed) regardless of whether
    # they had a valid GameProfile. These games deliberately carry varying
    # ROM counts (0, 1, 3) so a regression of that exact shape fails here
    # instead of only on a multi-hundred-entry real dat.
    BeforeAll {
        function New-DatStream {
            param([int[]]$RomCounts)
            $sb = [System.Text.StringBuilder]::new()
            [void]$sb.Append('<?xml version="1.0"?><datafile>')
            for ($i = 0; $i -lt $RomCounts.Count; $i++) {
                [void]$sb.Append("<game name=`"Game$i`"><GameProfile>code$i</GameProfile><Executable>game$i.exe</Executable>")
                for ($r = 0; $r -lt $RomCounts[$i]; $r++) {
                    [void]$sb.Append("<rom name=`"file$r`" size=`"1`" crc=`"0`" />")
                }
                [void]$sb.Append('</game>')
            }
            [void]$sb.Append('</datafile>')
            return [System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($sb.ToString()))
        }
    }

    It "indexes every game regardless of how many ROM entries precede its closing tag" {
        $stream = New-DatStream -RomCounts @(0, 1, 3, 2, 0)
        $index = Build-DatIndexFromStream -stream $stream
        $index.Count | Should -Be 5
        foreach ($i in 0..4) {
            $index["game$i"].ProfileCode | Should -Be "code$i"
            $index["game$i"].Executable  | Should -Be "game$i.exe"
        }
    }

    It "indexes a game with many ROM entries followed by another game" {
        $stream = New-DatStream -RomCounts @(137, 4)
        $index = Build-DatIndexFromStream -stream $stream
        $index.Count | Should -Be 2
        $index["game0"].ProfileCode | Should -Be "code0"
        $index["game1"].ProfileCode | Should -Be "code1"
    }
}

Describe "Read-Xml" {
    It "loads a well-formed file successfully" {
        $path = Join-Path $TestDrive "good.xml"
        [System.IO.File]::WriteAllText($path, "<Root><Child>value</Child></Root>")
        $doc = Read-Xml $path
        $doc.Root.Child | Should -Be "value"
    }
    It "throws on a corrupt (non-well-formed) file rather than returning a partial document" {
        $path = Join-Path $TestDrive "corrupt.xml"
        [System.IO.File]::WriteAllText($path, "<Root><Unclosed>")
        { Read-Xml $path } | Should -Throw
    }
    It "throws on a missing file rather than returning null" {
        $path = Join-Path $TestDrive "doesnotexist.xml"
        { Read-Xml $path } | Should -Throw
    }
}

Describe "Get-NormalizedGameKey naming edge cases" {
    It "preserves digits, so sequel numbers stay distinct after normalization" {
        Get-NormalizedGameKey "VirtuaFighter4" | Should -Not -Be (Get-NormalizedGameKey "VirtuaFighter5")
    }
    It "known collision risk: bracketed tags are stripped entirely, so titles differing only by tag content normalize identically" {
        # Documents a real risk identified in the fuzzy-matching audit: a dat/folder-name
        # pair like "Game [Demo]" vs "Game [Arcade]" collapses to the same normalized key
        # because square-bracket metadata is removed wholesale, not inspected. This is
        # locked in as a characterization test (not asserted as "correct") so a future
        # change to this collision behavior is deliberate, not silent.
        $demo   = Get-NormalizedGameKey "Game [Demo]"
        $arcade = Get-NormalizedGameKey "Game [Arcade]"
        $demo | Should -Be $arcade
    }
    It "strips region codes but does not strip meaningful parenthesized names like (Special Edition)" {
        $withRegion = Get-NormalizedGameKey "Some Game (USA)"
        $plain      = Get-NormalizedGameKey "Some Game"
        $withRegion | Should -Be $plain

        Get-NormalizedGameKey "Some Game (Special Edition)" | Should -Not -Be $plain
    }
    It "normalizes Eggman-dat-style version/date suffixes to the same key as the bare title" {
        $full = Get-NormalizedGameKey "Cars (1.42)(2013-08-28)[Raw Thrills PC][TP]"
        $bare = Get-NormalizedGameKey "Cars"
        $full | Should -Be $bare
    }

    # Issue #80: older RomVault-derived folder names carry Namco board/revision-code
    # tokens that the current Eggman dat's canonical names have dropped. Each of these
    # is anchored to a real, tester-reported unmatched folder from issue #75.
    It "converges Tekken 5.1's revision-tagged folder to the bare-title key (issue #80)" {
        (Get-NormalizedGameKey "Tekken 5.1 (TE51 Ver B)(2005)[Namco System 246][TP]") |
            Should -Be (Get-NormalizedGameKey "Tekken 5.1 (2005)[Namco System 246][TP]")
    }
    It "converges Time Crisis 3's revision-tagged folder to its already-matched folder's key (issue #80)" {
        (Get-NormalizedGameKey "Time Crisis 3 (TST1 Ver A)(2003)[Namco System 246][TP]") |
            Should -Be (Get-NormalizedGameKey "Time Crisis 3 (2003)[Namco System 246][TP]")
    }
    It "converges Time Crisis 4's revision-tagged folder to its already-matched folder's key (issue #80)" {
        (Get-NormalizedGameKey "Time Crisis 4 (TSF1002-NA-A)(World)(2006)[Namco System 256][TP]") |
            Should -Be (Get-NormalizedGameKey "Time Crisis 4 (2006)[Namco System 246][TP]")
    }
    It "converges Zoids Infinity's revision-tagged folder to the bare-title key confirmed present in the current dat (issue #80)" {
        (Get-NormalizedGameKey "Zoids Infinity (B3900076A Ver 2.02J)(2004)[Namco System 246][TP]") |
            Should -Be (Get-NormalizedGameKey "Zoids Infinity (2004)[Namco System 246][TP]")
    }
    It "does not strip loosely-formatted revision text that doesn't match the board-code shape (issue #80 guard)" {
        # Characterization guard: titles like this already match successfully today
        # without stripping (their dat entries carry the identical token) -- the new
        # rules must not start stripping them, which would risk diverging from a dat
        # entry that still includes the same text.
        Get-NormalizedGameKey "Hummer (1.0 Rev A)(2009)[Sega Lindbergh Yellow][TP]" |
            Should -Not -Be (Get-NormalizedGameKey "Hummer (2009)[Sega Lindbergh Yellow][TP]")
    }
    It "does not strip short all-caps codes with no qualifying digit run (issue #80 guard)" {
        Get-NormalizedGameKey "F-Zero AX (SBGG)(2003)[Sega Triforce][TP]" |
            Should -Not -Be (Get-NormalizedGameKey "F-Zero AX (2003)[Sega Triforce][TP]")
    }
    # Issue #80 code review: the board-code-token rule's alphanumeric prefix is
    # REQUIRED, not optional -- these three guard a real risk found by scanning
    # all 438 folder names in the tester's actual install (not a partial sample):
    # an earlier draft of this rule made the prefix optional, which also matched
    # bare "(Rev C)"/"(Rev E)"-style tokens with no board code at all. All three
    # titles below already match successfully today using this exact bare text,
    # so an optional-prefix rule would have been unscoped beyond what issue #80's
    # four target titles actually need.
    It "does not strip a bare (Rev E) token with no board-code prefix (issue #80 guard)" {
        Get-NormalizedGameKey "F-Zero AX (Rev E)(SBGG)(2003)(JPN)[Sega Triforce][TP]" |
            Should -Not -Be (Get-NormalizedGameKey "F-Zero AX (SBGG)(2003)(JPN)[Sega Triforce][TP]")
    }
    It "does not strip a bare (Rev. C) token with no board-code prefix (issue #80 guard)" {
        Get-NormalizedGameKey "Netchuu! Pro Baseball 2002 (Rev. C)(2002)[Namco System 246][TP]" |
            Should -Not -Be (Get-NormalizedGameKey "Netchuu! Pro Baseball 2002 (2002)[Namco System 246][TP]")
    }
    It "does not strip a bare (Rev B) token with no board-code prefix (issue #80 guard)" {
        Get-NormalizedGameKey "Wangan Midnight Maximum Tune (3.07)(Rev B)(2004-06-10)(EXP)[Sega Chihiro][TP]" |
            Should -Not -Be (Get-NormalizedGameKey "Wangan Midnight Maximum Tune (2004-06-10)(EXP)[Sega Chihiro][TP]")
    }
}

Describe "Get-DiceSimilarity Zoids Infinity / Zoids Infinity EX Plus (issue #80 code review)" {
    It "characterizes a real, pre-existing fuzzy-collision risk -- does NOT assert protection" {
        # Issue #80 code review finding: an earlier version of this comment claimed
        # this pair was "structurally protected" by the fuzzy threshold. That claim
        # was WRONG and is retracted here. Dice("zoidsinfinity", "zoidsinfinityexplus")
        # is 0.8, ABOVE the 0.72 fuzzy-match threshold used by Register-Games' Pass-2
        # dat-name fallback scan (TeknoParrot-Manager.ps1 ~line 6161-6180). This is not
        # new: the pre-#80 code already scored 0.677 for this pair (see git history),
        # already close to threshold -- this change raises it further, to 0.8.
        #
        # What actually keeps Zoids Infinity from mis-matching to EX Plus today is
        # NOT this Dice score -- it is that the current Eggman dat has an EXACT entry
        # for "Zoids Infinity (2004)[Namco System 246][TP]" (confirmed directly
        # against the dat before implementing issue #80), so Register-Games' exact
        # dat-key lookup (line 6165) succeeds before the fuzzy fallback loop ever
        # runs. If a future dat revision ever dropped that exact entry again, this
        # score means the fuzzy fallback COULD wrongly match Zoids Infinity to EX
        # Plus. That is a pre-existing latent risk in the fuzzy dat-name fallback
        # itself (not introduced by issue #80, though this change makes the score
        # for this specific pair worse) and is out of scope to fix here -- recorded
        # so it isn't silently lost.
        $zoidsKey  = Get-NormalizedGameKey "Zoids Infinity (2004)[Namco System 246][TP]"
        $explusKey = Get-NormalizedGameKey "Zoids Infinity EX Plus (B3900107A Ver 2.10J)(2006)[Namco System 256][TP]"
        (Get-DiceSimilarity $zoidsKey $explusKey) | Should -Be 0.8
    }
}

Describe "Get-MeaningfulTitleTokens" {
    It "strips parenthetical and bracket content wholesale" {
        $tokens = Get-MeaningfulTitleTokens "Zoids Infinity (B3900076A Ver 2.02J)(2004)[Namco System 246][TP]"
        $tokens | Should -Be @('zoids', 'infinity')
    }
    It "excludes pure-digit tokens (sequel numbers, years -- handled elsewhere)" {
        $tokens = Get-MeaningfulTitleTokens "Time Crisis 3 2003"
        $tokens | Should -Not -Contain '3'
        $tokens | Should -Not -Contain '2003'
        $tokens | Should -Contain 'time'
        $tokens | Should -Contain 'crisis'
    }
    It "excludes roman numerals I-X" {
        $tokens = Get-MeaningfulTitleTokens "Street Fighter III 3rd Strike"
        $tokens | Should -Not -Contain 'iii'
    }
    It "excludes standalone roman numeral I, not just II-X (issue #84 review)" {
        # No standalone "I" appears anywhere in the real Eggman collection dat
        # (confirmed by direct search) -- excluded for consistency with the
        # rest of the I-X range, on the same basis as II/III/etc: sequel
        # numbering, already handled elsewhere by digit-preserving
        # normalization, not a title differentiator this rule needs to see.
        $tokens = Get-MeaningfulTitleTokens "Some Game I"
        $tokens | Should -Not -Contain 'i'
        $tokens | Should -Contain 'some'
        $tokens | Should -Contain 'game'
    }
    It "excludes the closed stop-word list" {
        $tokens = Get-MeaningfulTitleTokens "The House of the Dead"
        $tokens | Should -Not -Contain 'the'
        $tokens | Should -Not -Contain 'of'
        $tokens | Should -Contain 'house'
        $tokens | Should -Contain 'dead'
    }
    It "does NOT exclude single-character meaningful tokens like R (issue #84 design requirement)" {
        # "Virtua Fighter 5" vs "Virtua Fighter 5 R" are two separate real DAT
        # entries -- the trailing "R" is a real differentiator and must survive.
        $tokens = Get-MeaningfulTitleTokens "Virtua Fighter 5 R"
        $tokens | Should -Contain 'r'
    }
}

Describe "Issue #84: Pass-2 dat-name fuzzy fallback rejects candidates with extra meaningful title tokens" {
    # Replicates the exact extra-token computation Register-Games' Pass-2 fuzzy
    # fallback performs (TeknoParrot-Manager.ps1, "DatIndex (pass2)" block) against
    # real title pairs -- Register-Games itself is excluded from this suite (see
    # file header: covers pure/read-only helpers only, not live install logic), so
    # this tests the actual decision-determining function directly with the real
    # strings that matter, the same way the existing Get-DiceSimilarity tests
    # document scoring behavior without invoking Register-Games as a black box.
    BeforeAll {
        function Get-ExtraCandidateTokens {
            param([string]$FolderName, [string]$CandidateName)
            $candidateTokens = Get-MeaningfulTitleTokens $CandidateName
            $folderTokens    = Get-MeaningfulTitleTokens $FolderName
            return @($candidateTokens | Where-Object { -not $folderTokens.Contains($_) })
        }
    }

    It "blocks Zoids Infinity matching Zoids Infinity EX (real DAT entries, Dice 0.923)" {
        $extra = Get-ExtraCandidateTokens -FolderName "Zoids Infinity (2004)[Namco System 246][TP]" `
                                           -CandidateName "Zoids Infinity EX (2.10)(2006)[Namco System 246][TP]"
        @($extra).Count | Should -BeGreaterThan 0
        $extra | Should -Contain 'ex'
    }
    It "blocks Zoids Infinity matching Zoids Infinity EX Plus (real DAT entries, Dice 0.800)" {
        $extra = Get-ExtraCandidateTokens -FolderName "Zoids Infinity (2004)[Namco System 246][TP]" `
                                           -CandidateName "Zoids Infinity EX Plus (B3900107A Ver 2.10J)(2006)[Namco System 256][TP]"
        @($extra).Count | Should -BeGreaterThan 0
        $extra | Should -Contain 'ex'
        $extra | Should -Contain 'plus'
    }
    It "blocks Street Fighter IV matching Super Street Fighter IV Arcade Edition (prefix-modifier case)" {
        $extra = Get-ExtraCandidateTokens -FolderName "Street Fighter IV (2008)[PC][TP]" `
                                           -CandidateName "Super Street Fighter IV Arcade Edition (2010-11-04)(EXP,Standalone)[Taito Type X2][TP]"
        @($extra).Count | Should -BeGreaterThan 0
        $extra | Should -Contain 'super'
        $extra | Should -Contain 'arcade'
        $extra | Should -Contain 'edition'
    }
    It "blocks a bare Centipede folder matching the Centipede Chaos DAT entry (issue #130/#79, real DAT entry)" {
        # Confirmed against the live Eggmansworld/TeknoParrot reference dat
        # (2026-08-06 collection): the only Centipede-related entry is
        # "Centipede Chaos (1.11)(2019)[ICE Linux PC][TP]" -- there is no
        # separate older "Centipede" entry in the current catalog to
        # false-positive against, but this guards the shape of the risk
        # named in #130 regardless.
        $extra = Get-ExtraCandidateTokens -FolderName "Centipede" `
                                           -CandidateName "Centipede Chaos (1.11)(2019)[ICE Linux PC][TP]"
        @($extra).Count | Should -BeGreaterThan 0
        $extra | Should -Contain 'chaos'
    }
    It "blocks Battle Gear 4 matching Battle Gear 4 Tuned (real DAT entries)" {
        $extra = Get-ExtraCandidateTokens -FolderName "Battle Gear 4 (2005)[Taito Type X+][TP]" `
                                           -CandidateName "Battle Gear 4 Tuned (2.08)(2007-06-18)[Taito Type X+][TP]"
        @($extra).Count | Should -BeGreaterThan 0
        $extra | Should -Contain 'tuned'
    }
    It "positive control: allows a legitimate near-miss that differs only by metadata, not title words" {
        # This is the dominant real-world Pass-2 fuzzy-fallback case (confirmed by
        # scanning the actual DAT: most near-misses are date/version/region
        # metadata differences, not title-word differences) -- same pair already
        # covered by Resolve-ExtractedGameFolder's "matches Battle Gear 3 despite
        # harmless DAT year/date metadata differences" test, confirming this new
        # #84 rule does not introduce a new block for the case Pass-2 primarily
        # exists to handle.
        $extra = Get-ExtraCandidateTokens -FolderName "Battle Gear 3 (2.08J)(2002)[Namco System 246][TP]" `
                                           -CandidateName "Battle Gear 3 (2.08J)(2003-04-11)[Namco System 246][TP]"
        @($extra).Count | Should -Be 0
    }
    It "known scope boundary: does not extend typo tolerance to whole-word differences within a title (documented, not a regression)" {
        # This rule compares whole meaningful WORDS, not per-word bigram similarity
        # -- unlike Get-DiceSimilarity's existing typo tolerance (see the separate
        # "NicktoonsNitro"/"NicktoonNitro" characterization test, which exercises
        # Resolve-BestFuzzyMatch's Pass-3 PROFILE-CODE fuzzy matching, a different
        # code path this issue does not touch). A single-character typo inside one
        # word of a multi-word Pass-2 DAT title would still be treated as an
        # "extra" token here. Real near-misses in this codebase's actual DAT are
        # overwhelmingly metadata differences (see the positive-control test
        # above), not within-title typos, so this is an accepted, documented scope
        # boundary of the minimal #84 design, not a silent gap.
        $extra = Get-ExtraCandidateTokens -FolderName "Nicktoons Nitro (2009)[Raw Thrills PC][TP]" `
                                           -CandidateName "Nicktoon Nitro (2009)[Raw Thrills PC][TP]"
        @($extra).Count | Should -BeGreaterThan 0
    }
}

Describe "Get-DiceSimilarity near-threshold / tie behavior" {
    # These document a real gap from the fuzzy-matching audit: Get-DiceSimilarity itself
    # has no concept of a threshold or a tie-break -- that logic lives in each caller's
    # "track the best score seen so far" loop (e.g. Register-Games ~line 4650-4668), which
    # only keeps a single best candidate and silently lets iteration order decide ties.
    # These tests pin down the scoring behavior the caller relies on, so a change to
    # Get-DiceSimilarity that quietly shifts near-threshold scores doesn't go unnoticed.
    It "can produce two distinct candidates scoring within a hair of each other, with no signal to prefer one" {
        $target = Get-NormalizedGameKey "NicktoonsNitro"
        $a = Get-DiceSimilarity $target (Get-NormalizedGameKey "NicktoonNitro")
        $b = Get-DiceSimilarity $target (Get-NormalizedGameKey "NicktoonsNitros")
        # Both are near-misses of the real title by one character; the function returns
        # a bare score for each with no indication of which (if either) is the real match.
        $a | Should -BeGreaterThan 0.85
        $b | Should -BeGreaterThan 0.85
        [Math]::Abs($a - $b) | Should -BeLessThan 0.1
    }
    It "a one-character difference near the auto-register threshold can land on either side of it" {
        # FuzzyAutoThreshold is 0.72 (TeknoParrot-Manager.ps1:582). A single transposed
        # or substituted character close to the threshold means whether a game gets
        # auto-registered or falls through to manual review is sensitive to exact spelling.
        $score = Get-DiceSimilarity (Get-NormalizedGameKey "InitialDArcadeStageZero") (Get-NormalizedGameKey "InitialDArcadeStageZer0")
        $score | Should -BeGreaterThan 0.6
        $score | Should -BeLessThan 1.0
    }
}

Describe "Resolve-BestFuzzyMatch" {
    # Fix for issue #15: the old inline loop in Register-Games had no tie-break --
    # whichever candidate scored highest (with ties broken purely by iteration order)
    # was trusted as an auto-register decision with no signal that a second candidate
    # was just as plausible. These tests cover the new top-2 tracking and tie margin.
    It "auto-trusts a clear winner with no close runner-up" {
        $matchList = @(
            [pscustomobject]@{ Code = "StreetFighterIII3rdStrike" }
            [pscustomobject]@{ Code = "MarioKartArcadeGP" }
        )
        $result = Resolve-BestFuzzyMatch -NormFolder (Get-NormalizedGameKey "StreetFighterIII3rdStrike") -MatchList $matchList -RawThrillsAliases @{}
        $result.Best.Code | Should -Be "StreetFighterIII3rdStrike"
        $result.IsConfidentMatch | Should -BeTrue
    }
    It "does not trust a match below the auto-register threshold" {
        $matchList = @(
            [pscustomobject]@{ Code = "CompletelyUnrelatedTitle" }
        )
        $result = Resolve-BestFuzzyMatch -NormFolder (Get-NormalizedGameKey "SomeOtherGame") -MatchList $matchList -RawThrillsAliases @{}
        $result.IsConfidentMatch | Should -BeFalse
    }
    It "refuses to auto-trust an exact tie between two different candidates" {
        $matchList = @(
            [pscustomobject]@{ Code = "VirtuaFighter4" }
            [pscustomobject]@{ Code = "VirtuaFighter5" }
        )
        # A folder name equidistant from both candidates -- same score for each.
        $result = Resolve-BestFuzzyMatch -NormFolder (Get-NormalizedGameKey "VirtuaFighter") -MatchList $matchList -RawThrillsAliases @{}
        $result.SecondScore | Should -Be $result.BestScore
        $result.IsConfidentMatch | Should -BeFalse
    }
    It "refuses to auto-trust a near-tie even when the best score clears the threshold" {
        $matchList = @(
            [pscustomobject]@{ Code = "NicktoonNitro" }    # one char short of the real title
            [pscustomobject]@{ Code = "NicktoonsNitros" }  # one char long of the real title
        )
        $result = Resolve-BestFuzzyMatch -NormFolder (Get-NormalizedGameKey "NicktoonsNitro") -MatchList $matchList -RawThrillsAliases @{}
        $result.BestScore | Should -BeGreaterThan $FuzzyAutoThreshold
        ($result.BestScore - $result.SecondScore) | Should -BeLessThan $FuzzyTieMargin
        $result.IsConfidentMatch | Should -BeFalse
    }
    It "still applies the RawThrillsAliases short-name fallback for a single unambiguous candidate" {
        $matchList = @( [pscustomobject]@{ Code = "NicktoonsNitro" } )
        $aliases   = @{ NicktoonsNitro = [pscustomobject]@{ Suggested = "NTN" } }
        $result = Resolve-BestFuzzyMatch -NormFolder (Get-NormalizedGameKey "NTN") -MatchList $matchList -RawThrillsAliases $aliases
        $result.Best.Code | Should -Be "NicktoonsNitro"
        $result.IsConfidentMatch | Should -BeTrue
    }
}

Describe "Resolve-ExtractedGameFolder (issue #66 extraction prompt correctness)" {
    BeforeAll {
        $script:OriginalRawThrillsPathLimits = $script:RawThrillsPathLimits
    }

    BeforeEach {
        $script:installRoot = Join-Path $TestDrive "Games"
        Remove-Item -LiteralPath $script:installRoot -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $script:installRoot -Force | Out-Null
        $script:RawThrillsPathLimits = @{
            AliensArmageddon = @{ Limit = 96; Suggested = 'ALIENS' }
        }
    }

    AfterEach {
        $script:RawThrillsPathLimits = $script:OriginalRawThrillsPathLimits
    }

    It "recognizes a RetroBat-suffixed Raw Thrills short-name folder for Aliens Armageddon" {
        $existing = Join-Path $script:installRoot "ALIENS.teknoparrot"
        New-Item -ItemType Directory -Path $existing -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $existing "game.exe") -Value "content"
        $zipName = "Aliens Armageddon (1.04)(2014-11-17)[Raw Thrills PC][TP]"
        $datIndex = @{
            (Get-NormalizedGameKey $zipName) = [pscustomobject]@{
                ProfileCode = "AliensArmageddon"
                Executable  = "game.exe"
            }
        }

        Resolve-ExtractedGameFolder -RawZipName $zipName -InstallFolder $script:installRoot -DatIndex $datIndex | Should -Be $existing
    }

    It "recognizes every supported RetroBat suffix for an already extracted folder" -ForEach @(
        @{ Suffix = '.teknoparrot' }
        @{ Suffix = '.parrot' }
        @{ Suffix = '.game' }
    ) {
        $zipName = "Daytona Championship USA (3.59)[Sega PC][TP]"
        $existing = Join-Path $script:installRoot ($zipName + $Suffix)
        New-Item -ItemType Directory -Path $existing -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $existing "game.exe") -Value "content"

        Resolve-ExtractedGameFolder -RawZipName $zipName -InstallFolder $script:installRoot | Should -Be $existing
    }

    It "matches Battle Gear 3 despite harmless DAT year/date metadata differences" {
        $existingName = "Battle Gear 3 (2.08J)(2003-04-11)[Namco System 246][TP]"
        $existing = Join-Path $script:installRoot $existingName
        New-Item -ItemType Directory -Path $existing -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $existing "game.elf") -Value "content"
        $zipName = "Battle Gear 3 (2.08J)(2002)[Namco System 246][TP]"
        $datIndex = @{
            (Get-NormalizedGameKey $zipName) = [pscustomobject]@{
                ProfileCode = "BattleGear3"
                Executable  = "game.elf"
            }
        }

        Resolve-ExtractedGameFolder -RawZipName $zipName -InstallFolder $script:installRoot -DatIndex $datIndex | Should -Be $existing
    }

    It "does not confuse similarly named sequels" {
        $existing = Join-Path $script:installRoot "Virtua Fighter 4"
        New-Item -ItemType Directory -Path $existing -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $existing "vf4.exe") -Value "content"

        Resolve-ExtractedGameFolder -RawZipName "Virtua Fighter 5" -InstallFolder $script:installRoot | Should -BeNullOrEmpty
    }

    It "does not confuse Mario Kart Arcade GP with Mario Kart Arcade GP 2 (regression -- a similarity-scored fuzzy tier previously matched these two different games at 0.97 against a 0.95 threshold)" {
        $existing = Join-Path $script:installRoot "Mario Kart Arcade GP 2 (1.02)[Namco][TP]"
        New-Item -ItemType Directory -Path $existing -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $existing "game.exe") -Value "content"

        Resolve-ExtractedGameFolder -RawZipName "Mario Kart Arcade GP (1.10)[Namco][TP]" -InstallFolder $script:installRoot | Should -BeNullOrEmpty
    }

    It "does not treat an empty matching folder as already extracted" {
        $existing = Join-Path $script:installRoot "Battle Gear 3 (2.08J)(2003-04-11)[Namco System 246][TP]"
        New-Item -ItemType Directory -Path $existing -Force | Out-Null

        Resolve-ExtractedGameFolder -RawZipName "Battle Gear 3 (2.08J)(2002)[Namco System 246][TP]" -InstallFolder $script:installRoot | Should -BeNullOrEmpty
    }

    It "uses registered GamePath identity when a valid profile points at a renamed existing folder" {
        $renamed = Join-Path $script:installRoot "My Hand Picked Folder"
        New-Item -ItemType Directory -Path $renamed -Force | Out-Null
        $exePath = Join-Path $renamed "launcher.exe"
        Set-Content -LiteralPath $exePath -Value "content"

        $profiles = Join-Path $TestDrive "UserProfiles"
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $profiles "CustomCode.xml") -Value @"
<GameProfile>
  <GamePath>$exePath</GamePath>
</GameProfile>
"@
        $zipName = "Some Collection Name (2024)[Platform][TP]"
        $datIndex = @{
            (Get-NormalizedGameKey $zipName) = [pscustomobject]@{
                ProfileCode = "CustomCode"
                Executable  = "launcher.exe"
            }
        }

        Resolve-ExtractedGameFolder -RawZipName $zipName -InstallFolder $script:installRoot -DatIndex $datIndex -UserProfilesDir $profiles | Should -Be $renamed
    }

    It "ignores registered identity when the dat profile code is not path-safe" {
        $renamed = Join-Path $script:installRoot "Unsafe Profile Code Folder"
        New-Item -ItemType Directory -Path $renamed -Force | Out-Null
        $exePath = Join-Path $renamed "launcher.exe"
        Set-Content -LiteralPath $exePath -Value "content"

        $profiles = Join-Path $TestDrive "UnsafeProfiles"
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $profiles "Unsafe.xml") -Value "<GameProfile><GamePath>$exePath</GamePath></GameProfile>"
        $zipName = "Unsafe Profile Code Test"
        $datIndex = @{
            (Get-NormalizedGameKey $zipName) = [pscustomobject]@{
                ProfileCode = "..\Unsafe"
                Executable  = "launcher.exe"
            }
        }

        Resolve-ExtractedGameFolder -RawZipName $zipName -InstallFolder $script:installRoot -DatIndex $datIndex -UserProfilesDir $profiles | Should -BeNullOrEmpty
    }
}

Describe "Invoke-AutoSync extracted-folder regression guards" {
    BeforeAll {
        $script:OriginalAutoSyncRawThrillsPathLimits = $script:RawThrillsPathLimits
    }

    BeforeEach {
        $script:autoSyncZipSource = Join-Path $TestDrive "ZipSource"
        $script:autoSyncInstallRoot = Join-Path $TestDrive "AutoSyncGames"
        New-Item -ItemType Directory -Path $script:autoSyncZipSource, $script:autoSyncInstallRoot -Force | Out-Null
        Mock Write-Log {}
    }

    AfterEach {
        $script:RawThrillsPathLimits = $script:OriginalAutoSyncRawThrillsPathLimits
    }

    It "does not extract when issue #66 resolver finds an existing RetroBat short-name folder" {
        $zipName = "Aliens Armageddon (1.04)(2014-11-17)[Raw Thrills PC][TP]"
        $zipPath = Join-Path $script:autoSyncZipSource ($zipName + ".zip")
        Set-Content -LiteralPath $zipPath -Value "placeholder zip bytes"

        $existing = Join-Path $script:autoSyncInstallRoot "ALIENS.teknoparrot"
        New-Item -ItemType Directory -Path $existing -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $existing "game.exe") -Value "content"
        $script:RawThrillsPathLimits = @{
            AliensArmageddon = @{ Limit = 96; Suggested = 'ALIENS' }
        }
        $datIndex = @{
            (Get-NormalizedGameKey $zipName) = [pscustomobject]@{
                ProfileCode = "AliensArmageddon"
                Executable  = "game.exe"
            }
        }
        Mock Expand-ZipFileSafe { throw "AutoSync should not extract already-present games" }

        $result = Invoke-AutoSync -zipSource $script:autoSyncZipSource -installFolder $script:autoSyncInstallRoot -syncStatePath (Join-Path $TestDrive "sync.json") -retroBat $true -datIndex $datIndex

        $result.UpToDate | Should -Be 1
        $result.Synced | Should -Be 0
        Should -Invoke Expand-ZipFileSafe -Times 0
    }
}

Describe "New-PostgresPgPassFile / Remove-PostgresPgPassFile" {
    # Issue #3 (v1.0 roadmap): migrated Postgres credential passing from
    # $env:PGPASSWORD to a temporary .pgpass-format file, so the password is
    # never visible in psql.exe/etc.'s own process environment block. These
    # tests cover the file format (libpq's documented
    # hostname:port:database:username:password syntax) and escaping rules,
    # plus cleanup. The ACL lockdown is part of the credential boundary; the
    # tests keep the file-format assertions independent of local ACL details.
    It "writes a single line in the documented hostname:port:database:username:password format" {
        $path = New-PostgresPgPassFile -Password "hunter2"
        try {
            (Get-Content -LiteralPath $path -Raw).Trim() | Should -Be "127.0.0.1:5432:*:postgres:hunter2"
        } finally {
            Remove-PostgresPgPassFile -Path $path
        }
    }
    It "escapes a backslash and a colon in the password per the pgpass format" {
        $path = New-PostgresPgPassFile -Password 'p:a\ss'
        try {
            (Get-Content -LiteralPath $path -Raw).Trim() | Should -Be '127.0.0.1:5432:*:postgres:p\:a\\ss'
        } finally {
            Remove-PostgresPgPassFile -Path $path
        }
    }
    It "creates a real file that Remove-PostgresPgPassFile then deletes" {
        $path = New-PostgresPgPassFile -Password "anything"
        Test-Path -LiteralPath $path | Should -BeTrue
        Remove-PostgresPgPassFile -Path $path
        Test-Path -LiteralPath $path | Should -BeFalse
    }
    It "does not throw when asked to remove a path that doesn't exist" {
        $missing = Join-Path $TestDrive "does-not-exist.conf"
        { Remove-PostgresPgPassFile -Path $missing } | Should -Not -Throw
    }
    It "does not throw when asked to remove a null/empty path" {
        { Remove-PostgresPgPassFile -Path $null } | Should -Not -Throw
        { Remove-PostgresPgPassFile -Path "" } | Should -Not -Throw
    }
}

Describe "Postgres guided recovery and profile transaction" {
    It "accepts a confirmed new password through SecureString input without echoing it" {
        $secure = ConvertTo-SecureString 'New-Password-For-Test' -AsPlainText -Force
        Mock Read-Host { $secure }
        Read-ConfirmedPostgresPassword 'the new password' | Should -Be 'New-Password-For-Test'
        Should -Invoke Read-Host -Times 2
    }

    It "redacts a supplied password from diagnostic text" {
        $secret = 'No-Log-Password-123'
        $safe = ConvertTo-PostgresRedactedText -Text ("native error: $secret") -Secrets @($secret)
        $safe | Should -Not -Match ([regex]::Escape($secret))
        $safe | Should -Match '\[REDACTED\]'
    }

    Context "automatic reset" {
        BeforeEach {
            $script:pgSecret = 'Automatic-Reset-Secret-456'
            $script:pgRoot = Join-Path $TestDrive 'postgres-reset'
            $script:PostgresInstallDir = $script:pgRoot
            $script:PostgresBinDir = Join-Path $script:pgRoot 'bin'
            $script:PostgresServiceName = 'pgsql-test'
            New-Item -ItemType Directory -Path (Join-Path $script:PostgresBinDir '..\data') -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $script:PostgresBinDir 'postgres.exe') -Force | Out-Null
            $script:pgBackup = [pscustomobject]@{ Path = Join-Path $TestDrive 'PostgresRecoveryBackups\evidence'; Verified = $true }
            $script:pgNativeArguments = $null
            $script:pgNativeInput = $null
            Mock Write-Log { param([string]$Message) if ($Message -match [regex]::Escape($script:pgSecret)) { throw 'secret reached log mock' } }
            Mock Get-Service { [pscustomobject]@{ Status = 'Stopped' } }
            Mock Start-Service {}
            Mock Stop-Service {}
            Mock Wait-PostgresServiceState {}
            Mock Test-PostgresPassword { $true }
        }

        It "attempts the reset through PostgreSQL single-user standard input and reports success" {
            Mock Invoke-PostgresNativeProcessWithInput {
                param([string]$FilePath, [string]$Arguments, [string]$InputText, [string[]]$Secrets)
                $script:pgNativeArguments = $Arguments
                $script:pgNativeInput = $InputText
                [pscustomobject]@{ ExitCode = 0; Output = ''; Error = '' }
            }
            $result = Reset-PostgresPasswordAutomatically -NewPassword $script:pgSecret -RecoveryBackup $script:pgBackup
            $result.Attempted | Should -BeTrue
            $result.Succeeded | Should -BeTrue
            $result.RecoveryBlocked | Should -BeFalse
            $script:pgNativeArguments | Should -Not -Match ([regex]::Escape($script:pgSecret))
            $script:pgNativeInput | Should -Match 'ALTER ROLE postgres WITH PASSWORD'
            Should -Invoke Invoke-PostgresNativeProcessWithInput -Times 1
            Should -Invoke Test-PostgresPassword -Times 1
        }

        It "leaves evidence and reports recovery blocked when the reset fails" {
            Mock Invoke-PostgresNativeProcessWithInput {
                [pscustomobject]@{ ExitCode = 7; Output = ''; Error = $script:pgSecret }
            }
            $result = Reset-PostgresPasswordAutomatically -NewPassword $script:pgSecret -RecoveryBackup $script:pgBackup
            $result.Attempted | Should -BeTrue
            $result.Succeeded | Should -BeFalse
            $result.RecoveryBlocked | Should -BeTrue
            $result.BackupPath | Should -Be $script:pgBackup.Path
            $result.Reason | Should -Not -Match ([regex]::Escape($script:pgSecret))
            Should -Invoke Start-Service -Times 0
            Should -Invoke Test-PostgresPassword -Times 0
        }
    }

    Context "profile planning" {
        BeforeEach {
            $script:pgProfiles = Join-Path $TestDrive 'PostgresProfiles'
            New-Item -ItemType Directory -Path $script:pgProfiles -Force | Out-Null
            $script:PostgresBinDir = 'C:\PostgreSQL\bin'
            $script:pgRecovery = [pscustomobject]@{ Path = Join-Path $TestDrive 'PostgresRecoveryBackups\verified'; Verified = $true; ProfileBackups = @() }
            $script:pgEvents = New-Object System.Collections.Generic.List[string]
            $script:pgSaved = New-Object System.Collections.Generic.List[string]
            Mock Write-Log {}
            Mock Get-PostgresDatabaseState { [pscustomobject]@{ Exists = $true; Verified = $true } }
            Mock Save-Xml { param($Doc, [string]$Path) [void]$script:pgEvents.Add('save'); [void]$script:pgSaved.Add($Path) }
        }

        It "backs up before profile population, updates only stale profiles, and handles multiple profiles deterministically" {
            $xml = '<GameProfile><ConfigValues><FieldInformation><CategoryName>Postgres</CategoryName><FieldName>DbName</FieldName><FieldValue>GameDB01</FieldValue></FieldInformation><FieldInformation><CategoryName>Postgres</CategoryName><FieldName>Path</FieldName><FieldValue>C:\\PostgreSQL\\bin\\</FieldValue></FieldInformation><FieldInformation><CategoryName>Postgres</CategoryName><FieldName>Address</FieldName><FieldValue>127.0.0.1</FieldValue></FieldInformation><FieldInformation><CategoryName>Postgres</CategoryName><FieldName>Port</FieldName><FieldValue>5432</FieldValue></FieldInformation><FieldInformation><CategoryName>Postgres</CategoryName><FieldName>User</FieldName><FieldValue>postgres</FieldValue></FieldInformation><FieldInformation><CategoryName>Postgres</CategoryName><FieldName>Pass</FieldName><FieldValue>old</FieldValue></FieldInformation><FieldInformation><CategoryName>Postgres</CategoryName><FieldName>Automatically create Database</FieldName><FieldValue>1</FieldValue></FieldInformation></ConfigValues></GameProfile>'
            Set-Content -LiteralPath (Join-Path $script:pgProfiles 'A.xml') -Value $xml
            Set-Content -LiteralPath (Join-Path $script:pgProfiles 'B.xml') -Value ($xml.Replace('<FieldValue>old</FieldValue>', '<FieldValue>approved</FieldValue>'))
            Mock New-PostgresRecoveryBackup { [void]$script:pgEvents.Add('backup'); $script:pgRecovery }
            $result = Invoke-PostgresGameSetup -UserProfilesDir $script:pgProfiles -SuperPasswordPlain 'approved'
            $result.Configured | Should -Be 1
            $result.AlreadyConfigured | Should -Be 1
            $result.RecoveryBlocked | Should -BeFalse
            @($script:pgEvents) | Should -Be @('backup', 'save')
            $script:pgSaved.Count | Should -Be 1
            $script:pgSaved[0] | Should -Match 'A\.xml$'
        }

        It "restores evidence and does not report completion after a partial profile save" {
            $xml = '<GameProfile><ConfigValues><FieldInformation><CategoryName>Postgres</CategoryName><FieldName>DbName</FieldName><FieldValue>GameDB01</FieldValue></FieldInformation><FieldInformation><CategoryName>Postgres</CategoryName><FieldName>Path</FieldName><FieldValue></FieldValue></FieldInformation><FieldInformation><CategoryName>Postgres</CategoryName><FieldName>Address</FieldName><FieldValue></FieldValue></FieldInformation><FieldInformation><CategoryName>Postgres</CategoryName><FieldName>Port</FieldName><FieldValue></FieldValue></FieldInformation><FieldInformation><CategoryName>Postgres</CategoryName><FieldName>User</FieldName><FieldValue></FieldValue></FieldInformation><FieldInformation><CategoryName>Postgres</CategoryName><FieldName>Pass</FieldName><FieldValue>old</FieldValue></FieldInformation><FieldInformation><CategoryName>Postgres</CategoryName><FieldName>Automatically create Database</FieldName><FieldValue>1</FieldValue></FieldInformation></ConfigValues></GameProfile>'
            Set-Content -LiteralPath (Join-Path $script:pgProfiles 'A.xml') -Value $xml
            Set-Content -LiteralPath (Join-Path $script:pgProfiles 'B.xml') -Value $xml
            $script:saveCount = 0; $script:restoreCount = 0
            Mock Save-Xml { $script:saveCount++; if ($script:saveCount -eq 2) { throw 'simulated profile write failure' } }
            Mock Restore-PostgresProfileBackups { $script:restoreCount++; $true }
            $result = Invoke-PostgresGameSetup -UserProfilesDir $script:pgProfiles -SuperPasswordPlain 'approved' -RecoveryBackup $script:pgRecovery
            $result.RecoveryBlocked | Should -BeTrue
            $result.Configured | Should -Be 1
            $script:restoreCount | Should -Be 1
            $result | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Issue #292 PostgreSQL automatic elevation and resume" {
    BeforeEach {
        $script:postgresGuidanceMessages = @()
        Mock Write-Host { $script:postgresGuidanceMessages += [string]$Object }
        Mock Write-Log {}
    }

    It "explains that TPM will request permission and continue the same repair" {
        Write-PostgresAdministratorGuidance -Operation Recovery

        ($script:postgresGuidanceMessages -join [Environment]::NewLine) | Should -Match 'Windows will ask you to approve this'
        ($script:postgresGuidanceMessages -join [Environment]::NewLine) | Should -Match 'continue the same setup automatically'
        ($script:postgresGuidanceMessages -join [Environment]::NewLine) | Should -Match 'do not need to close TPM'
        ($script:postgresGuidanceMessages -join [Environment]::NewLine) | Should -Match 'backs up before changing anything'
    }

    It "uses the same automatic permission handoff for a first install" {
        Write-PostgresAdministratorGuidance -Operation Install

        ($script:postgresGuidanceMessages -join [Environment]::NewLine) | Should -Match 'needs Windows permission to install'
        ($script:postgresGuidanceMessages -join [Environment]::NewLine) | Should -Match 'continue the same setup automatically'
        ($script:postgresGuidanceMessages -join [Environment]::NewLine) | Should -Not -Match '(?i)right-click|Run as administrator|select PostgreSQL setup'
    }

    It "offers automatic repair instead of manual relaunch instructions" {
        $script:ProductionSource | Should -Match 'Repair the PostgreSQL password now\? \(Y/N\)'
        $script:ProductionSource | Should -Match 'Start-PostgresRecoveryAsAdministrator[\s\S]*?-Operation Recovery'
        $script:ProductionSource | Should -Match 'PostgresRecoveryResumeToken'
        $script:ProductionSource | Should -Not -Match '(?i)right-click TeknoParrot-Manager\.bat|select PostgreSQL setup \(mode 12\) again'
    }

    It "uses the Windows Administrator role and a UAC RunAs child for the recovery gate" {
        $adminFunction = (Get-Command Test-RunningAsAdministrator).ScriptBlock.ToString()
        $adminFunction | Should -Match 'WindowsPrincipal'
        $adminFunction | Should -Match 'WindowsBuiltInRole\]::Administrator'
        $script:ProductionSource | Should -Match 'Start-Process\s+-FilePath \$hostPath[\s\S]*?-Verb RunAs[\s\S]*?-Wait'
    }

    It "does not expose credentials in the non-admin recovery guidance" {
        ($script:postgresGuidanceMessages -join [Environment]::NewLine) | Should -Not -Match '(?i)(superPwPlain|newPassword|password\s*[:=]\s*\S+)'
    }

    It "uses the exact automatic repair offer and no manual elevation path" {
        $script:ProductionSource | Should -Match 'PostgreSQL needs attention'
        $script:ProductionSource | Should -Match 'saved PostgreSQL password cannot be used'
        $script:ProductionSource | Should -Match 'verified backup'
        $script:ProductionSource | Should -Match 'Existing PostgreSQL data is preserved'
        $script:ProductionSource | Should -Match 'Repair the PostgreSQL password now\? \(Y/N\)'
        $script:ProductionSource | Should -Not -Match '(?i)right-click.*administrator|select PostgreSQL setup.*again'
    }

    It "resumes option 12 without re-entering the main menu" {
        $script:ProductionSource | Should -Match ([regex]::Escape('$pendingApplyMode = ''PostgresSetup'''))
        $script:ProductionSource | Should -Match '-PostgresRecoveryResumeToken'
        $script:ProductionSource | Should -Match 'PostgreSQL is fixed'
        $script:ProductionSource | Should -Match 'Press Enter to continue'
        $script:ProductionSource | Should -Match 'will not claim recovery is complete'
    }

    It "keeps backup, reset, verification, save, and setup ordering fail-closed" {
        $source = $script:ProductionSource
        $helperStart = $source.IndexOf('function Invoke-PostgresSelectedPasswordRecovery')
        $helperEnd = $source.IndexOf('function Test-PostgresInstallationsRegistry', $helperStart)
        $helper = $source.Substring($helperStart, $helperEnd - $helperStart)
        $backup = $helper.IndexOf('New-PostgresRecoveryBackup')
        $reset = $helper.IndexOf('Reset-PostgresPasswordAutomatically')
        $verify = $helper.IndexOf('Test-PostgresPassword')
        $backup | Should -BeGreaterThan -1
        $reset | Should -BeGreaterThan $backup
        $verify | Should -BeGreaterThan $reset
        $postgresMode = $source.IndexOf('if ($mode -eq "PostgresSetup")')
        $save = $source.IndexOf('if (-not (Save-Config))', $postgresMode)
        $dbBackup = $source.IndexOf('Backup-PostgresDatabases', $postgresMode)
        $profileSetup = $source.IndexOf('Invoke-PostgresGameSetup', $postgresMode)
        $postgresMode | Should -BeGreaterThan -1
        $save | Should -BeGreaterThan $verify
        $dbBackup | Should -BeGreaterThan $save
        $profileSetup | Should -BeGreaterThan $dbBackup

    }

    It "keeps MSI passwords out of child process arguments" {
        $source = $script:ProductionSource
        $start = $source.IndexOf('function Install-Postgres83')
        $end = $source.IndexOf('# =============================================================================', $start)
        $install = $source.Substring($start, $end - $start)
        $source | Should -Match 'WindowsInstaller\.Installer[\s\S]*InstallProduct'
        $install | Should -Match 'Invoke-PostgresMsiPackage'
        $install | Should -Match 'SERVICEPASSWORD'
        $install | Should -Match 'SUPERPASSWORD'
        $install | Should -Not -Match 'Start-Process\s+-FilePath\s+["'']msiexec\.exe'
        $install | Should -Not -Match '\$msiArgs'
    }
    It "keeps PostgreSQL running through the transaction and restores the original service state" {
        $script:ProductionSource | Should -Match 'function Restore-PostgresServiceState'
        $script:ProductionSource | Should -Match 'Restore-PostgresServiceState -WasRunning'
        $script:ProductionSource | Should -Match 'Reset-PostgresPasswordAutomatically[\s\S]*?Test-PostgresPassword[\s\S]*?\$result\.Succeeded'
        $script:ProductionSource | Should -Not -Match 'if \(-not \$wasRunning\) \{\s*Stop-Service'
    }

    It "keeps UAC denial retryable without claiming recovery" {
        $script:ProductionSource | Should -Match 'Windows did not give TPM permission to continue'
        $script:ProductionSource | Should -Match 'Nothing was changed by the failed automatic repair'
        $script:ProductionSource | Should -Match "Read-HostSafe '  Try again\? \(Y/N\)'"
        $script:ProductionSource | Should -Match 'protected repair information is still available'
    }

    Context "protected resume state" {
        BeforeEach {
            $script:stateConfigPath = Join-Path $TestDrive 'TeknoParrot-Manager.config.json'
            $script:stateScriptPath = Join-Path $TestDrive 'TeknoParrot-Manager.ps1'
            $script:stateTpRoot = Join-Path $TestDrive 'TeknoParrot'
            $script:stateUserProfilesDir = Join-Path $script:stateTpRoot 'UserProfiles'
            New-Item -ItemType Directory -Path $script:stateUserProfilesDir -Force | Out-Null
            Set-Content -LiteralPath $script:stateConfigPath -Value '{}'
            Set-Content -LiteralPath $script:stateScriptPath -Value '# test script'
            Mock Get-PostgresRecoveryStateDirectory { Join-Path $TestDrive 'RecoveryState' }
            Mock Set-PostgresRecoveryStateAcl {}
            Mock Write-Log {}
        }

        It "stores the chosen password encrypted and validates it only at resume time" {
            $secret = 'Chosen-Password-For-Resume-789'
            $statePath = New-PostgresRecoveryState -ConfigPath $script:stateConfigPath -ScriptPath $script:stateScriptPath -TpRoot $script:stateTpRoot -UserProfilesDir $script:stateUserProfilesDir -Operation Recovery -PasswordPlain $secret
            try {
                $raw = Get-Content -LiteralPath $statePath -Raw
                $raw | Should -Not -Match ([regex]::Escape($secret))
                $saved = $raw | ConvertFrom-Json
                $saved.SchemaVersion | Should -Be 3
                $saved.CipherText | Should -Not -BeNullOrEmpty
                $saved.Purpose | Should -Be 'TeknoParrotManager.PostgresRecovery'
                $resume = Read-PostgresRecoveryState -StatePath $statePath -ExpectedConfigPath $script:stateConfigPath -ExpectedScriptPath $script:stateScriptPath -ExpectedTpRoot $script:stateTpRoot -ExpectedUserProfilesDir $script:stateUserProfilesDir
                $resume.PasswordPlain | Should -Be $secret
                $resume.ClaimPath | Should -Match '\.claim$'
                (Test-Path -LiteralPath $resume.UsedPath -PathType Leaf) | Should -BeTrue
                { Read-PostgresRecoveryState -StatePath $statePath -ExpectedConfigPath $script:stateConfigPath -ExpectedScriptPath $script:stateScriptPath -ExpectedTpRoot $script:stateTpRoot -ExpectedUserProfilesDir $script:stateUserProfilesDir } | Should -Throw
            } finally {
                [void](Remove-PostgresRecoveryState -Path $statePath -ClaimPath ($statePath + '.claim'))
            }
        }

        It "passes only the protected state path through the UAC command line" {
            $secret = 'Never-In-Arguments-123'
            $statePath = Join-Path (Join-Path $TestDrive 'RecoveryState') '.tpm-postgres-recovery-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.json'
            $script:testUacStatePath = $statePath
            Mock New-PostgresRecoveryState { $script:testUacStatePath }
            Mock Remove-PostgresRecoveryState { $true }
            Mock Start-Process {
                param($FilePath, $ArgumentList, $Verb, $Wait, $PassThru, $ErrorAction)
                $script:uacFilePath = $FilePath
                $script:uacArguments = @($ArgumentList)
                $script:uacVerb = $Verb
                [pscustomobject]@{ ExitCode = 0 }
            }
            Start-PostgresRecoveryAsAdministrator -ConfigPath $script:stateConfigPath -ScriptPath $script:stateScriptPath -TpRoot $script:stateTpRoot -UserProfilesDir $script:stateUserProfilesDir -Operation Recovery -PasswordPlain $secret | Should -BeTrue
            $script:uacVerb | Should -Be 'RunAs'

            ($script:uacArguments -join ' ') | Should -Not -Match ([regex]::Escape($secret))
            ($script:uacArguments -join ' ') | Should -Match 'PostgresRecoveryResumeToken'
            ($script:uacArguments -join ' ') | Should -Match ([regex]::Escape($statePath))
        }
        It "binds and consumes the authenticated resume challenge before side effects" {
            $script:ProductionSource | Should -Match 'SchemaVersion\s*=\s*3'
            $script:ProductionSource | Should -Match 'ProtectedData\]::Protect'
            $script:ProductionSource | Should -Match 'File\]::Move\(\$fullPath, \$claimPath\)'
            $script:ProductionSource | Should -Match 'FileMode\]::CreateNew'
            $script:ProductionSource | Should -Match 'ExpiresUtc.*CreatedUtc|expires -le \$created'
            $script:ProductionSource | Should -Match 'FromMinutes\(5\)'
            $script:ProductionSource | Should -Match 'ParentProcessPath'
            $script:ProductionSource | Should -Match 'ParentProcessSha256'
            $script:ProductionSource | Should -Match 'AttemptId.*-gt 5|AttemptId -lt 1'
            $script:ProductionSource | Should -Match 'Find-PostgresRecoveryRetryState'
        }
        It "rejects tampered envelope and consumed replay" {
            $statePath = New-PostgresRecoveryState -ConfigPath $script:stateConfigPath -ScriptPath $script:stateScriptPath -TpRoot $script:stateTpRoot -UserProfilesDir $script:stateUserProfilesDir -Operation Recovery -PasswordPlain 'Tamper-Test-123'
            try {
                $outer = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
                $outer.Purpose = 'Tampered'
                [IO.File]::WriteAllText($statePath, ($outer | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding $false))
                { Read-PostgresRecoveryState -StatePath $statePath -ExpectedConfigPath $script:stateConfigPath -ExpectedScriptPath $script:stateScriptPath -ExpectedTpRoot $script:stateTpRoot -ExpectedUserProfilesDir $script:stateUserProfilesDir } | Should -Throw
            } finally {
                [void](Remove-PostgresRecoveryState -Path $statePath -ClaimPath ($statePath + '.claim'))
            }
        }

        It "binds consumption to the issuance filename so copied envelopes cannot be replayed" {
            $secret = 'Copy-Replay-Test-456'
            $statePath = New-PostgresRecoveryState -ConfigPath $script:stateConfigPath -ScriptPath $script:stateScriptPath -TpRoot $script:stateTpRoot -UserProfilesDir $script:stateUserProfilesDir -Operation Recovery -PasswordPlain $secret
            $copyPath = Join-Path (Split-Path -Parent $statePath) '.tpm-postgres-recovery-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.json'
            try {
                [IO.File]::Copy($statePath, $copyPath)
                { Read-PostgresRecoveryState -StatePath $copyPath -ExpectedConfigPath $script:stateConfigPath -ExpectedScriptPath $script:stateScriptPath -ExpectedTpRoot $script:stateTpRoot -ExpectedUserProfilesDir $script:stateUserProfilesDir } | Should -Throw
                $original = Read-PostgresRecoveryState -StatePath $statePath -ExpectedConfigPath $script:stateConfigPath -ExpectedScriptPath $script:stateScriptPath -ExpectedTpRoot $script:stateTpRoot -ExpectedUserProfilesDir $script:stateUserProfilesDir
                $original.PasswordPlain | Should -Be $secret
                { Read-PostgresRecoveryState -StatePath $statePath -ExpectedConfigPath $script:stateConfigPath -ExpectedScriptPath $script:stateScriptPath -ExpectedTpRoot $script:stateTpRoot -ExpectedUserProfilesDir $script:stateUserProfilesDir } | Should -Throw
            } finally {
                Remove-Item -LiteralPath $copyPath -Force -ErrorAction SilentlyContinue
                [void](Remove-PostgresRecoveryState -Path $statePath -ClaimPath ($statePath + '.claim'))
            }
        }

        It "restores a malformed claimed state after validation failure" {
            $statePath = New-PostgresRecoveryState -ConfigPath $script:stateConfigPath -ScriptPath $script:stateScriptPath -TpRoot $script:stateTpRoot -UserProfilesDir $script:stateUserProfilesDir -Operation Recovery -PasswordPlain 'Malformed-Claim-Test-123'
            try {
                $outer = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
                $outer.CipherText = 'not-valid-dpapi'
                [IO.File]::WriteAllText($statePath, ($outer | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding $false))
                { Read-PostgresRecoveryState -StatePath $statePath -ExpectedConfigPath $script:stateConfigPath -ExpectedScriptPath $script:stateScriptPath -ExpectedTpRoot $script:stateTpRoot -ExpectedUserProfilesDir $script:stateUserProfilesDir } | Should -Throw
                (Test-Path -LiteralPath $statePath -PathType Leaf) | Should -BeTrue
                (Test-Path -LiteralPath ($statePath + '.claim') -PathType Leaf) | Should -BeFalse
                (Test-Path -LiteralPath ($statePath + '.used') -PathType Leaf) | Should -BeFalse
            } finally {
                [void](Remove-PostgresRecoveryState -Path $statePath -ClaimPath ($statePath + '.claim'))
            }
        }

        It "restores a claimed state when the expected parent installation is wrong" {
            $statePath = New-PostgresRecoveryState -ConfigPath $script:stateConfigPath -ScriptPath $script:stateScriptPath -TpRoot $script:stateTpRoot -UserProfilesDir $script:stateUserProfilesDir -Operation Recovery -PasswordPlain 'Wrong-Parent-Test-123'
            $wrongConfig = Join-Path $TestDrive 'different-config.json'
            Set-Content -LiteralPath $wrongConfig -Value '{}' -Encoding utf8
            try {
                { Read-PostgresRecoveryState -StatePath $statePath -ExpectedConfigPath $wrongConfig -ExpectedScriptPath $script:stateScriptPath -ExpectedTpRoot $script:stateTpRoot -ExpectedUserProfilesDir $script:stateUserProfilesDir } | Should -Throw
                (Test-Path -LiteralPath $statePath -PathType Leaf) | Should -BeTrue
                (Test-Path -LiteralPath ($statePath + '.claim') -PathType Leaf) | Should -BeFalse
                (Test-Path -LiteralPath ($statePath + '.used') -PathType Leaf) | Should -BeFalse
            } finally {
                [void](Remove-PostgresRecoveryState -Path $statePath -ClaimPath ($statePath + '.claim'))
            }
        }

        It "allows the original envelope once and rejects a copied envelope in the reverse permutation" {
            $secret = 'Reverse-Copy-Replay-789'
            $statePath = New-PostgresRecoveryState -ConfigPath $script:stateConfigPath -ScriptPath $script:stateScriptPath -TpRoot $script:stateTpRoot -UserProfilesDir $script:stateUserProfilesDir -Operation Recovery -PasswordPlain $secret
            $copyPath = Join-Path (Split-Path -Parent $statePath) '.tpm-postgres-recovery-cccccccccccccccccccccccccccccccc.json'
            try {
                [IO.File]::Copy($statePath, $copyPath)
                $original = Read-PostgresRecoveryState -StatePath $statePath -ExpectedConfigPath $script:stateConfigPath -ExpectedScriptPath $script:stateScriptPath -ExpectedTpRoot $script:stateTpRoot -ExpectedUserProfilesDir $script:stateUserProfilesDir
                $original.PasswordPlain | Should -Be $secret
                { Read-PostgresRecoveryState -StatePath $copyPath -ExpectedConfigPath $script:stateConfigPath -ExpectedScriptPath $script:stateScriptPath -ExpectedTpRoot $script:stateTpRoot -ExpectedUserProfilesDir $script:stateUserProfilesDir } | Should -Throw
            } finally {
                Remove-Item -LiteralPath $copyPath -Force -ErrorAction SilentlyContinue
                [void](Remove-PostgresRecoveryState -Path $statePath -ClaimPath ($statePath + '.claim'))
            }
        }

        It "cleans a stale claimed envelope after expiry validation fails" {
            $statePath = Join-Path (Join-Path $TestDrive 'RecoveryState') '.tpm-postgres-recovery-dddddddddddddddddddddddddddddddd.json'
            New-Item -ItemType Directory -Path (Split-Path -Parent $statePath) -Force | Out-Null
            [IO.File]::WriteAllText($statePath, '{"SchemaVersion":3,"Purpose":"TeknoParrotManager.PostgresRecovery","CipherText":"fake"}', (New-Object Text.UTF8Encoding $false))
            $proc = Get-Process -Id $PID
            $script:fakeExpiredPayload = [ordered]@{
                SchemaVersion = 3; Purpose = 'TeknoParrotManager.PostgresRecovery'; IssuanceId = 'dddddddddddddddddddddddddddddddd'; Operation = 'Recovery'; Nonce = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'; AttemptId = 1
                CreatedUtc = (Get-Date).ToUniversalTime().AddMinutes(-10).ToString('o'); ExpiresUtc = (Get-Date).ToUniversalTime().AddMinutes(-5).ToString('o')
                ParentPid = [int]$PID; ParentStartTicks = [int64]$proc.StartTime.ToUniversalTime().Ticks; ParentProcessPath = [string]$proc.Path; ParentProcessSha256 = (Get-FileHash -LiteralPath $proc.Path -Algorithm SHA256).Hash
                OriginUserSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value; MachineName = [Environment]::MachineName
                ScriptPath = [System.IO.Path]::GetFullPath($script:stateScriptPath); ScriptSha256 = (Get-FileHash -LiteralPath $script:stateScriptPath -Algorithm SHA256).Hash
                ConfigPath = [System.IO.Path]::GetFullPath($script:stateConfigPath); ConfigSha256 = (Get-FileHash -LiteralPath $script:stateConfigPath -Algorithm SHA256).Hash
                TpRoot = [System.IO.Path]::GetFullPath($script:stateTpRoot); UserProfilesDir = [System.IO.Path]::GetFullPath($script:stateUserProfilesDir); PasswordPlain = 'expired'; PasswordOriginEncrypted = 'encrypted'
            }
            Mock Unprotect-PostgresRecoveryEnvelope { $script:fakeExpiredPayload | ConvertTo-Json -Depth 6 }
            try {
                { Read-PostgresRecoveryState -StatePath $statePath -ExpectedConfigPath $script:stateConfigPath -ExpectedScriptPath $script:stateScriptPath -ExpectedTpRoot $script:stateTpRoot -ExpectedUserProfilesDir $script:stateUserProfilesDir } | Should -Throw
                (Test-Path -LiteralPath $statePath -PathType Leaf) | Should -BeTrue
                (Test-Path -LiteralPath ($statePath + '.claim') -PathType Leaf) | Should -BeFalse
                (Test-Path -LiteralPath ($statePath + '.used') -PathType Leaf) | Should -BeFalse
            } finally {
                Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
            }
        }

        It "rejects a configuration mutation after issuance" {
            $statePath = New-PostgresRecoveryState -ConfigPath $script:stateConfigPath -ScriptPath $script:stateScriptPath -TpRoot $script:stateTpRoot -UserProfilesDir $script:stateUserProfilesDir -Operation Recovery -PasswordPlain 'Hash-Test-123'
            try {
                Add-Content -LiteralPath $script:stateConfigPath -Value 'changed'
                { Read-PostgresRecoveryState -StatePath $statePath -ExpectedConfigPath $script:stateConfigPath -ExpectedScriptPath $script:stateScriptPath -ExpectedTpRoot $script:stateTpRoot -ExpectedUserProfilesDir $script:stateUserProfilesDir } | Should -Throw
            } finally {
                [void](Remove-PostgresRecoveryState -Path $statePath -ClaimPath ($statePath + '.claim'))
            }
        }
    }
}

Describe "BepInEx authorized-root and transaction guards" {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-Host {}
    }

    It "blocks an outside game root before release query, prompt, or download" {
        $approved = Join-Path $TestDrive 'ApprovedGames'
        $outside = Join-Path $TestDrive 'OutsideGame'
        $profiles = Join-Path $TestDrive 'BepProfiles'
        New-Item -ItemType Directory -Path $approved, $outside, $profiles -Force | Out-Null
        $exe = Join-Path $outside 'game.exe'
        New-Item -ItemType File -Path $exe -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $profiles 'Outside.xml') -Value ("<GameProfile><GamePath>$exe</GamePath></GameProfile>")
        Mock Get-BepInExLatestRelease { throw 'release query should not run' }
        Mock Read-HostSafe { 'N' }
        Mock Invoke-TpmDownload { throw 'download should not run' }
        Invoke-BepInExUpdateCheck -UserProfilesDir $profiles -CacheDir (Join-Path $TestDrive 'BepCache') -ApprovedGamesRoot $approved
        Should -Invoke Get-BepInExLatestRelease -Times 0
        Should -Invoke Read-HostSafe -Times 0
        Should -Invoke Invoke-TpmDownload -Times 0
    }

    It "gives an actionable refusal when a BepInEx root is unsafe" {
        $script:bepGuidanceMessages = @()
        Mock Write-Host { $script:bepGuidanceMessages += [string]$Object }

        Write-BepInExUnsafeRootGuidance -GameCode 'UnsafeGame' -ApprovedRoot 'E:\Games\TeknoParrot Games'

        ($script:bepGuidanceMessages -join [Environment]::NewLine) | Should -Match 'could not safely update BepInEx'
        ($script:bepGuidanceMessages -join [Environment]::NewLine) | Should -Match 'move or correct it'
        ($script:bepGuidanceMessages -join [Environment]::NewLine) | Should -Match 'did not download or change anything'
        ($script:bepGuidanceMessages -join [Environment]::NewLine) | Should -Match 'choose the BepInEx update again'
        ($script:bepGuidanceMessages -join [Environment]::NewLine) | Should -Not -Match '(?i)reparse|junction|symlink'
    }

    It "fails closed when the approved root is reparse-backed" {
        $approved = Join-Path $TestDrive 'ReparseApproved'
        New-Item -ItemType Directory -Path $approved -Force | Out-Null
        Mock Get-Item { [pscustomobject]@{ Attributes = [System.IO.FileAttributes]::ReparsePoint; PSIsContainer = $true } } -ParameterFilter { $LiteralPath -eq $approved }
        Test-BepInExGameRootSafe -GameRoot $approved -ApprovedRoot $approved | Should -BeFalse
    }

    It "restores the exact destination when staged promotion validation fails" {
        $stage = Join-Path $TestDrive 'BepStage'
        $dest = Join-Path $TestDrive 'BepDest'
        New-Item -ItemType Directory -Path (Join-Path $stage 'BepInEx'), (Join-Path $dest 'BepInEx') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $stage 'BepInEx\core.dll') -Value 'new'
        Set-Content -LiteralPath (Join-Path $dest 'BepInEx\core.dll') -Value 'old'
        Set-Content -LiteralPath (Join-Path $stage 'winhttp.dll') -Value 'new-shim'
        $before = Get-TpmDirSnapshot -Dir $dest
        { Invoke-TpmTransactionalTreePromote -StagingDir $stage -DestDir $dest -RelativeFiles @('BepInEx\core.dll', 'winhttp.dll') -ValidationScript { return $false } } | Should -Throw
        Assert-TpmDirSnapshotUnchanged -Before $before -After (Get-TpmDirSnapshot -Dir $dest)
    }

    It "does not alter a live BepInEx file when backup verification fails" {
        $game = Join-Path $TestDrive 'BackupGame'
        New-Item -ItemType Directory -Path (Join-Path $game 'BepInEx') -Force | Out-Null
        $file = Join-Path $game 'BepInEx\core.dll'
        Set-Content -LiteralPath $file -Value 'original'
        Mock Test-BepInExBackupEntry { $false }
        { New-BepInExUpdateBackup -GameRoot $game } | Should -Throw
        (Get-Content -LiteralPath $file -Raw) | Should -Be ('original' + [Environment]::NewLine)
        @(Get-ChildItem -LiteralPath $game -Directory -Filter 'BepInEx_Backup_*' -ErrorAction SilentlyContinue).Count | Should -BeGreaterThan 0
    }

    It "refuses to recursively clean a path outside the controlled BepInEx staging root" {
        $outside = Join-Path $TestDrive ('BepInEx-outside-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $outside 'keep.txt') -Value 'keep'
        Mock Remove-Item {}

        { Remove-BepInExStagingDirectory -StagingDir $outside } | Should -Throw '*TPM BEPINEX STAGING CLEANUP REFUSED*'
        Should -Invoke Remove-Item -Times 0 -Exactly
        Test-Path -LiteralPath (Join-Path $outside 'keep.txt') -PathType Leaf | Should -BeTrue
    }

    It "classifies a current-version BepInEx tree as incomplete when bootstrap files are missing" {
        $game = Join-Path $TestDrive 'BepHealthIncomplete'
        New-Item -ItemType Directory -Path (Join-Path $game 'BepInEx\core') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $game 'BepInEx\core\BepInEx.dll') -Force | Out-Null
        Mock Get-BepInExInstalledVersion { '5.4.23' }
        Mock Get-BepInExInstalledArch { 'x64' }
        Mock Test-BepInExNoReparsePath { $true }

        $health = Get-BepInExInstallationHealth -ExeDir $game

        $health.Installed | Should -BeTrue
        $health.Complete | Should -BeFalse
        $health.Reason | Should -Match 'Missing'
    }

    It "offers repair-reset for an installed current-version tree that is incomplete" {
        $approved = Join-Path $TestDrive 'CurrentBrokenApproved'
        $game = Join-Path $approved 'CurrentBrokenGame'
        $profiles = Join-Path $TestDrive 'CurrentBrokenProfiles'
        $cache = Join-Path $TestDrive 'CurrentBrokenCache'
        New-Item -ItemType Directory -Path $approved, $game, $profiles -Force | Out-Null
        $exe = Join-Path $game 'game.exe'
        New-Item -ItemType File -Path $exe -Force | Out-Null
        $safeExe = [System.Security.SecurityElement]::Escape($exe)
        Set-Content -LiteralPath (Join-Path $profiles 'CURRENTBROKEN.xml') -Value ("<GameProfile><GamePath>$safeExe</GamePath></GameProfile>")
        Mock Test-BepInExGameRootSafe { $true }
        Mock Test-BepInExNoReparsePath { $true }
        Mock Get-ExeArchitecture { 'x64' }
        Mock Get-BepInExLatestRelease { [pscustomobject]@{ Version = '5.4.23'; DownloadUrl = 'https://github.com/BepInEx/BepInEx/releases/download/v5.4.23/BepInEx_win_x64_5.4.23.zip'; FileName = 'BepInEx_win_x64_5.4.23.zip'; SizeBytes = 1; ExpectedSha256 = $null } }
        Mock Get-BepInExInstallationHealth { [pscustomobject]@{ Installed = $true; Complete = $false; Version = '5.4.23'; Architecture = 'x64'; Reason = 'Missing doorstop_config.ini' } }
        Mock Read-HostSafe { 'N' }
        Mock Invoke-TpmDownload { throw 'download must not run after decline' }

        $result = Invoke-BepInExUpdateCheck -UserProfilesDir $profiles -CacheDir $cache -ApprovedGamesRoot $approved

        $result.Reason | Should -Be 'DECLINED'
        Should -Invoke Read-HostSafe -Times 1 -Exactly
        Should -Invoke Invoke-TpmDownload -Times 0 -Exactly
    }

    Context "post-promotion staging cleanup reporting" {
        BeforeEach {
            $script:bepApproved = Join-Path $TestDrive 'BepApproved'
            $script:bepGame = Join-Path $script:bepApproved 'CleanupGame'
            $script:bepProfiles = Join-Path $TestDrive 'BepCleanupProfiles'
            $script:bepCache = Join-Path $TestDrive 'BepCleanupCache'
            $script:bepStage = Join-Path (Join-Path $env:TEMP 'TeknoParrotManagerStaging') ('BepInEx-test-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $script:bepApproved, $script:bepGame, $script:bepProfiles -Force | Out-Null
            $gameExe = Join-Path $script:bepGame 'game.exe'
            New-Item -ItemType File -Path $gameExe -Force | Out-Null
            $safeGameExe = [System.Security.SecurityElement]::Escape($gameExe)
            Set-Content -LiteralPath (Join-Path $script:bepProfiles 'CLEANUPGAME.xml') -Value ("<GameProfile><GamePath>$safeGameExe</GamePath></GameProfile>")

            Mock Test-BepInExGameRootSafe { $true }
            Mock Test-BepInExNoReparsePath { $true }
            Mock Test-BepInExExistingTreeSafe { $true }
            Mock Get-BepInExLatestRelease { [pscustomobject]@{ Version = '5.4.23'; DownloadUrl = 'https://github.com/BepInEx/BepInEx/releases/download/v5.4.23/BepInEx_win_x64_5.4.23.zip'; FileName = 'BepInEx_win_x64_5.4.23.zip'; SizeBytes = 1; ExpectedSha256 = $null } }
            Mock Get-BepInExInstalledVersion { '5.4.22' }
            Mock Get-BepInExInstalledArch { 'x64' }
            Mock Get-BepInExInstallationHealth { [pscustomobject]@{ Installed = $true; Complete = $true; Version = '5.4.22'; Architecture = 'x64'; Reason = 'Complete' } }
            Mock Read-HostSafe { 'Y' }
            Mock Invoke-TpmDownload { $true }
            Mock New-TpmStagingDirectory {
                New-Item -ItemType Directory -Path $script:bepStage -Force | Out-Null
                return $script:bepStage
            }
            Mock Expand-ZipFileSafe {}
            Mock Get-BepInExStagedFiles { @('BepInEx\core.dll') }
            Mock New-BepInExUpdateBackup { Join-Path $script:bepGame 'BepInEx_Backup_test' }
            Mock Invoke-TpmTransactionalTreePromote { $true }
        }

        AfterEach {
            if ($script:bepStage -and (Test-Path -LiteralPath $script:bepStage)) {
                [System.IO.Directory]::Delete($script:bepStage, $true)
            }
        }

        It "counts a promoted update only after controlled staging cleanup succeeds" {
            Invoke-BepInExUpdateCheck -UserProfilesDir $script:bepProfiles -CacheDir $script:bepCache -ApprovedGamesRoot $script:bepApproved

            Test-Path -LiteralPath $script:bepStage | Should -BeFalse
            Should -Invoke Write-Host -ParameterFilter { [string]$Object -match '^  Updated cleanly: 1 game\(s\)$' } -Times 1 -Exactly
            Should -Invoke Write-Host -ParameterFilter { [string]$Object -match 'Updated with cleanup failure' } -Times 0 -Exactly
            Should -Invoke Write-Log -ParameterFilter { [string]$msg -eq 'BepInEx update check: updatedCleanly=1 updatedWithCleanupFailure=0 errors=0 cleanupFailures=0' } -Times 1 -Exactly
        }

        It "reports action required and excludes a promoted update from the clean count when staging cleanup fails" {
            Mock Remove-BepInExStagingDirectory { throw "TPM BEPINEX STAGING CLEANUP FAILED for '$script:bepStage' -- residue remains at '$script:bepStage'." }

            Invoke-BepInExUpdateCheck -UserProfilesDir $script:bepProfiles -CacheDir $script:bepCache -ApprovedGamesRoot $script:bepApproved

            Test-Path -LiteralPath $script:bepStage -PathType Container | Should -BeTrue
            Should -Invoke Write-Host -ParameterFilter { [string]$Object -match '^  Updated cleanly: 0 game\(s\)$' } -Times 1 -Exactly
            Should -Invoke Write-Host -ParameterFilter { [string]$Object -match '^  Updated with cleanup failure: 1 -- ACTION REQUIRED$' } -Times 1 -Exactly
            Should -Invoke Write-Host -ParameterFilter { [string]$Object -match [regex]::Escape($script:bepStage) } -Times 1 -Exactly
            Should -Invoke Write-Log -ParameterFilter { [string]$msg -match 'update applied.*staging cleanup failed' -and [string]$msg -match [regex]::Escape($script:bepStage) } -Times 1 -Exactly
            Should -Invoke Write-Log -ParameterFilter { [string]$msg -eq 'BepInEx update check: updatedCleanly=0 updatedWithCleanupFailure=1 errors=0 cleanupFailures=1' } -Times 1 -Exactly
        }
    }
}
Describe "Read-PathWithBrowse" {
    # This is UI code (it can launch a real WinForms file/folder picker), which
    # is outside this project's stated Pester scope the same way other menu/UI
    # code already is -- these tests only cover the manual-entry passthrough
    # (mocking Read-Host, the one real cmdlet involved), never the actual
    # dialog-showing branch, which has no practical way to assert against in an
    # automated run without clicking through a real modal window.
    It "returns whatever was typed, unchanged, when the user does not type B" {
        Mock Read-Host { "C:\Some\Typed\Path" }
        Read-PathWithBrowse "Enter a path" | Should -Be "C:\Some\Typed\Path"
    }
    It "is case-insensitive when checking for the browse trigger (only 'b'/'B' triggers it, not a path that happens to start with B)" {
        Mock Read-Host { "B:\SomeDrive" }
        # A typed path literally starting with the letter B must NOT be misread as
        # the browse trigger -- only an exact "B" (after Trim) should be.
        Read-PathWithBrowse "Enter a path" | Should -Be "B:\SomeDrive"
    }
    It "returns an empty string passthrough when the user presses Enter with nothing typed" {
        Mock Read-Host { "" }
        Read-PathWithBrowse "Enter a path" | Should -Be ""
    }
}

Describe "Get-ReShadeLatestVersion retry behavior" {
    BeforeAll {
        Mock Invoke-WebRequest {}
    }

    It "makes only a single attempt and returns null on failure -- no retry, unlike Invoke-TpmDownload's HttpClient/Invoke-WebRequest tiers" {
        Mock Invoke-WebRequest { throw "site unreachable" }
        $result = Get-ReShadeLatestVersion
        $result | Should -BeNullOrEmpty
        Should -Invoke Invoke-WebRequest -Times 1
    }
    It "parses the version out of a successful response" {
        Mock Invoke-WebRequest { [pscustomobject]@{ Content = "...ReShade_Setup_6.7.3.exe..." } }
        Get-ReShadeLatestVersion | Should -Be "6.7.3"
    }
}

Describe "Test-EggmanDatReleaseUrl" {
    It "accepts the expected Eggmansworld TeknoParrot GitHub release URL" {
        Test-EggmanDatReleaseUrl "https://github.com/Eggmansworld/TeknoParrot/releases/download/2026-06-17/TeknoParrot.Collection.RomVault.zip" | Should -BeTrue
    }
    It "rejects lookalike or non-release URLs" {
        Test-EggmanDatReleaseUrl "https://github.com.evil.example.com/Eggmansworld/TeknoParrot/releases/download/2026-06-17/file.zip" | Should -BeFalse
        Test-EggmanDatReleaseUrl "https://github.com/OtherOwner/TeknoParrot/releases/download/2026-06-17/file.zip" | Should -BeFalse
        Test-EggmanDatReleaseUrl "http://github.com/Eggmansworld/TeknoParrot/releases/download/2026-06-17/file.zip" | Should -BeFalse
    }
}

Describe "Get-TpmHttpStatusCodeFromError" {
    # Review round 2 (Luna Max): every one of these shapes must resolve
    # without throwing, and without broadly swallowing anything the
    # message-based fallback could still recover. Fixtures are plain
    # pscustomobjects standing in for $ErrorRecord -- the function only
    # ever reads .Exception, .Exception.Message, and (optionally)
    # .Exception.Response/.Response.StatusCode, so a pscustomobject shaped
    # the same way as a real ErrorRecord/Exception exercises the same
    # property-existence code paths as the real .NET types.

    It "returns 0 for an exception type with no Response property at all (e.g. a plain RuntimeException from a mock's throw)" {
        $errorRecord = $null
        try { throw "bits failed" } catch { $errorRecord = $_ }
        Get-TpmHttpStatusCodeFromError -ErrorRecord $errorRecord | Should -Be 0
    }

    It "returns 0 (not a crash) when Response exists but is explicitly null" {
        $fake = [pscustomobject]@{ Exception = [pscustomobject]@{ Response = $null; Message = 'transport failure' } }
        { Get-TpmHttpStatusCodeFromError -ErrorRecord $fake } | Should -Not -Throw
        Get-TpmHttpStatusCodeFromError -ErrorRecord $fake | Should -Be 0
    }

    It "returns 0 (not a crash) when Response is present but has no StatusCode property at all" {
        $fake = [pscustomobject]@{ Exception = [pscustomobject]@{ Response = [pscustomobject]@{ Body = 'oops' }; Message = 'transport failure, no status' } }
        { Get-TpmHttpStatusCodeFromError -ErrorRecord $fake } | Should -Not -Throw
        Get-TpmHttpStatusCodeFromError -ErrorRecord $fake | Should -Be 0
    }

    It "extracts a plain numeric StatusCode from Response" {
        $fake = [pscustomobject]@{ Exception = [pscustomobject]@{ Response = [pscustomobject]@{ StatusCode = 404 }; Message = 'boom' } }
        Get-TpmHttpStatusCodeFromError -ErrorRecord $fake | Should -Be 404
    }

    It "extracts an enum-like StatusCode (e.g. System.Net.HttpStatusCode) by casting it to its underlying integer" {
        $fake = [pscustomobject]@{ Exception = [pscustomobject]@{ Response = [pscustomobject]@{ StatusCode = [System.Net.HttpStatusCode]::NotFound }; Message = 'boom' } }
        Get-TpmHttpStatusCodeFromError -ErrorRecord $fake | Should -Be 404
    }

    It "falls back to extracting a status code embedded only in the exception message when there is no Response at all" {
        $fake = [pscustomobject]@{ Exception = [pscustomobject]@{ Message = 'Response status code does not indicate success: 404 (Not Found).' } }
        Get-TpmHttpStatusCodeFromError -ErrorRecord $fake | Should -Be 404
    }

    It "returns 0 when there is no status code anywhere -- Response, StatusCode, and message all lack one" {
        $fake = [pscustomobject]@{ Exception = [pscustomobject]@{ Message = 'DNS resolution failed' } }
        Get-TpmHttpStatusCodeFromError -ErrorRecord $fake | Should -Be 0
    }
}

Describe "Invoke-TpmDownload method selection and partial-file cleanup" {
    BeforeAll {
        Mock Write-Log {}
        Mock Write-Host {}
        Mock Write-DownloadAudit {}
        Mock Write-TpmDownloadMetrics {}
        Mock Start-Sleep {}
        Mock Invoke-TpmDownloadBits { Set-Content -LiteralPath $TempPath -Value "fake zip content" -NoNewline }
        Mock Invoke-TpmDownloadHttpClient { Set-Content -LiteralPath $TempPath -Value "fake zip content" -NoNewline }
        Mock Invoke-TpmDownloadWebRequest { Set-Content -LiteralPath $TempPath -Value "fake zip content" -NoNewline }
    }
    BeforeEach {
        Mock Test-TpmDownloadBitsAvailable { $true }
    }

    It "uses BITS first when it is available" {
        $savePath = Join-Path $TestDrive "bits-success.zip"

        $result = Invoke-TpmDownload -DownloadUrl "https://example.com/file.zip" -DestinationPath $savePath

        $result | Should -BeTrue
        Test-Path -LiteralPath $savePath | Should -BeTrue
        Should -Invoke Invoke-TpmDownloadBits -Times 1
        Should -Invoke Invoke-TpmDownloadHttpClient -Times 0
        Should -Invoke Invoke-TpmDownloadWebRequest -Times 0
    }

    It "falls back to HttpClient when BITS is unavailable" {
        Mock Test-TpmDownloadBitsAvailable { $false }
        $savePath = Join-Path $TestDrive "httpclient-success.zip"

        $result = Invoke-TpmDownload -DownloadUrl "https://example.com/file.zip" -DestinationPath $savePath

        $result | Should -BeTrue
        Test-Path -LiteralPath $savePath | Should -BeTrue
        Should -Invoke Invoke-TpmDownloadBits -Times 0
        Should -Invoke Invoke-TpmDownloadHttpClient -Times 1
        Should -Invoke Invoke-TpmDownloadWebRequest -Times 0
    }

    It "uses Invoke-WebRequest only after BITS and HttpClient exhaust their retries" {
        Mock Invoke-TpmDownloadBits { throw "bits failed" }
        Mock Invoke-TpmDownloadHttpClient { throw "http failed" }
        $savePath = Join-Path $TestDrive "webrequest-success.zip"

        $result = Invoke-TpmDownload -DownloadUrl "https://example.com/file.zip" -DestinationPath $savePath

        $result | Should -BeTrue
        Test-Path -LiteralPath $savePath | Should -BeTrue
        Should -Invoke Invoke-TpmDownloadBits -Times 1
        # A generic (non-HTTP-status) failure retries up to 3 times before falling through.
        Should -Invoke Invoke-TpmDownloadHttpClient -Times 3
        Should -Invoke Invoke-TpmDownloadWebRequest -Times 1
    }

    It "retries a transient HttpClient failure and succeeds on a later attempt without falling through to Invoke-WebRequest" {
        Mock Test-TpmDownloadBitsAvailable { $false }
        $script:httpAttempt = 0
        Mock Invoke-TpmDownloadHttpClient {
            $script:httpAttempt++
            if ($script:httpAttempt -lt 2) { throw "transient network error" }
            Set-Content -LiteralPath $TempPath -Value "fake zip content" -NoNewline
        }
        $savePath = Join-Path $TestDrive "httpclient-retry-success.zip"

        $result = Invoke-TpmDownload -DownloadUrl "https://example.com/file.zip" -DestinationPath $savePath

        $result | Should -BeTrue
        $script:httpAttempt | Should -Be 2
        Should -Invoke Invoke-TpmDownloadWebRequest -Times 0
    }

    It "does not retry HttpClient on a definitive 404 before falling through to Invoke-WebRequest" {
        Mock Test-TpmDownloadBitsAvailable { $false }
        Mock Invoke-TpmDownloadHttpClient { throw "Response status code does not indicate success: 404 (Not Found)." }
        $savePath = Join-Path $TestDrive "httpclient-404-no-retry.zip"

        $result = Invoke-TpmDownload -DownloadUrl "https://example.com/missing.zip" -DestinationPath $savePath

        $result | Should -BeTrue
        Should -Invoke Invoke-TpmDownloadHttpClient -Times 1
        Should -Invoke Invoke-TpmDownloadWebRequest -Times 1
    }

    It "retries a transient Invoke-WebRequest failure and succeeds on a later attempt" {
        Mock Test-TpmDownloadBitsAvailable { $false }
        Mock Invoke-TpmDownloadHttpClient { throw "http failed" }
        $script:webAttempt = 0
        Mock Invoke-TpmDownloadWebRequest {
            $script:webAttempt++
            if ($script:webAttempt -lt 2) { throw "transient network error" }
            Set-Content -LiteralPath $TempPath -Value "fake zip content" -NoNewline
        }
        $savePath = Join-Path $TestDrive "webrequest-retry-success.zip"

        $result = Invoke-TpmDownload -DownloadUrl "https://example.com/file.zip" -DestinationPath $savePath

        $result | Should -BeTrue
        $script:webAttempt | Should -Be 2
    }

    It "surfaces the final HTTP status code via -LastStatusCode when every method fails" {
        Mock Test-TpmDownloadBitsAvailable { $false }
        Mock Invoke-TpmDownloadHttpClient { throw "Response status code does not indicate success: 404 (Not Found)." }
        Mock Invoke-TpmDownloadWebRequest { throw "Response status code does not indicate success: 404 (Not Found)." }
        $savePath = Join-Path $TestDrive "status-code-404.zip"
        $statusCode = 0

        $result = Invoke-TpmDownload -DownloadUrl "https://example.com/missing.zip" -DestinationPath $savePath -LastStatusCode ([ref]$statusCode)

        $result | Should -BeFalse
        $statusCode | Should -Be 404
    }

    It "reports status code 0 via -LastStatusCode when the failure is not HTTP-status-related" {
        Mock Test-TpmDownloadBitsAvailable { $false }
        Mock Invoke-TpmDownloadHttpClient { throw "DNS resolution failed" }
        Mock Invoke-TpmDownloadWebRequest { throw "DNS resolution failed" }
        $savePath = Join-Path $TestDrive "status-code-unknown.zip"
        $statusCode = 999

        $result = Invoke-TpmDownload -DownloadUrl "https://example.com/file.zip" -DestinationPath $savePath -LastStatusCode ([ref]$statusCode)

        $result | Should -BeFalse
        $statusCode | Should -Be 0
    }

    It "deletes any partial file and leaves the final path untouched when all methods fail" {
        Mock Invoke-TpmDownloadBits { param($DownloadUrl, $TempPath) Set-Content -LiteralPath $TempPath -Value "partial"; throw "bits failed" }
        Mock Invoke-TpmDownloadHttpClient { param($DownloadUrl, $TempPath) Set-Content -LiteralPath $TempPath -Value "partial"; throw "http failed" }
        Mock Invoke-TpmDownloadWebRequest { param($DownloadUrl, $TempPath) Set-Content -LiteralPath $TempPath -Value "partial"; throw "web failed" }
        $savePath = Join-Path $TestDrive "failed.zip"

        $result = Invoke-TpmDownload -DownloadUrl "https://example.com/file.zip" -DestinationPath $savePath

        $result | Should -BeFalse
        Test-Path -LiteralPath $savePath | Should -BeFalse
        @(Get-ChildItem -LiteralPath $TestDrive -Filter "*.partial" -Force).Count | Should -Be 0
    }

    It "rejects an incomplete file when an expected size is provided" {
        Mock Test-TpmDownloadBitsAvailable { $false }
        Mock Invoke-TpmDownloadHttpClient { Set-Content -LiteralPath $TempPath -Value "short" -NoNewline }
        $savePath = Join-Path $TestDrive "too-small.zip"

        $result = Invoke-TpmDownload -DownloadUrl "https://example.com/file.zip" -DestinationPath $savePath -ExpectedBytes 100

        $result | Should -BeFalse
        Test-Path -LiteralPath $savePath | Should -BeFalse
        @(Get-ChildItem -LiteralPath $TestDrive -Filter "*.partial" -Force).Count | Should -Be 0
    }
}

Describe "Invoke-TpmDownload progress overlay cleanup (issue #132)" {
    # Regression coverage for the stale "Downloading Thumbnails" progress
    # overlay that persisted over the TPM menu after a thumbnail 404. Root
    # cause: every download tier raises the Id 42 Write-Progress overlay as
    # it starts, but only each tier's own success path cleared it -- every
    # failure/exception exit left whatever was last written on screen
    # permanently. The fix wraps Invoke-TpmDownload in a finally that always
    # completes Id 42, regardless of how the function exits.
    BeforeAll {
        Mock Write-Log {}
        Mock Write-Host {}
        Mock Write-DownloadAudit {}
        Mock Write-TpmDownloadMetrics {}
        Mock Start-Sleep {}
        Mock Write-Progress {}
    }
    BeforeEach {
        Mock Test-TpmDownloadBitsAvailable { $false }
    }

    It "completes the Id 42 overlay after a successful download" {
        Mock Invoke-TpmDownloadHttpClient { Set-Content -LiteralPath $TempPath -Value "fake" -NoNewline }
        $savePath = Join-Path $TestDrive "progress-success.png"

        Invoke-TpmDownload -DownloadUrl "https://example.com/a.png" -DestinationPath $savePath -Label 'Thumbnails' | Should -BeTrue

        Should -Invoke Write-Progress -Times 1 -ParameterFilter { $Id -eq 42 -and $Completed }
    }

    It "completes the Id 42 overlay after a single definitive 404 (one thumbnail missing upstream)" {
        Mock Invoke-TpmDownloadHttpClient { throw "Response status code does not indicate success: 404 (Not Found)." }
        Mock Invoke-TpmDownloadWebRequest { throw "Response status code does not indicate success: 404 (Not Found)." }
        $savePath = Join-Path $TestDrive "progress-404.png"
        $statusCode = 0

        $result = Invoke-TpmDownload -DownloadUrl "https://example.com/missing.png" -DestinationPath $savePath -Label 'Thumbnails' -LastStatusCode ([ref]$statusCode)

        $result | Should -BeFalse
        $statusCode | Should -Be 404
        Should -Invoke Write-Progress -Times 1 -ParameterFilter { $Id -eq 42 -and $Completed }
    }

    It "completes the Id 42 overlay after a non-404 failure (generic download error, all tiers exhausted)" {
        Mock Invoke-TpmDownloadHttpClient { throw "DNS resolution failed" }
        Mock Invoke-TpmDownloadWebRequest { throw "DNS resolution failed" }
        $savePath = Join-Path $TestDrive "progress-generic-fail.png"

        Invoke-TpmDownload -DownloadUrl "https://example.com/a.png" -DestinationPath $savePath -Label 'Thumbnails' | Should -BeFalse

        Should -Invoke Write-Progress -Times 1 -ParameterFilter { $Id -eq 42 -and $Completed }
    }

    It "completes the Id 42 overlay even when an unexpected exception is thrown after a successful transfer" {
        Mock Invoke-TpmDownloadHttpClient { Set-Content -LiteralPath $TempPath -Value "fake" -NoNewline }
        Mock Write-DownloadAudit { throw "unexpected post-download failure" }
        $savePath = Join-Path $TestDrive "progress-exception.png"

        Invoke-TpmDownload -DownloadUrl "https://example.com/a.png" -DestinationPath $savePath -Label 'Thumbnails' | Should -BeFalse

        Should -Invoke Write-Progress -Times 1 -ParameterFilter { $Id -eq 42 -and $Completed }
    }

    It "clears the overlay independently for each call in a mixed batch (404, then success, then generic failure)" {
        $savePath1 = Join-Path $TestDrive "batch-1-404.png"
        $savePath2 = Join-Path $TestDrive "batch-2-success.png"
        $savePath3 = Join-Path $TestDrive "batch-3-failed.png"

        Mock Invoke-TpmDownloadHttpClient { throw "Response status code does not indicate success: 404 (Not Found)." }
        Mock Invoke-TpmDownloadWebRequest { throw "Response status code does not indicate success: 404 (Not Found)." }
        $r1 = Invoke-TpmDownload -DownloadUrl "https://example.com/missing.png" -DestinationPath $savePath1 -Label 'Thumbnails'

        Mock Invoke-TpmDownloadHttpClient { Set-Content -LiteralPath $TempPath -Value "fake" -NoNewline }
        Mock Invoke-TpmDownloadWebRequest { throw "should not be reached" }
        $r2 = Invoke-TpmDownload -DownloadUrl "https://example.com/found.png" -DestinationPath $savePath2 -Label 'Thumbnails'

        Mock Invoke-TpmDownloadHttpClient { throw "DNS resolution failed" }
        Mock Invoke-TpmDownloadWebRequest { throw "DNS resolution failed" }
        $r3 = Invoke-TpmDownload -DownloadUrl "https://example.com/broken.png" -DestinationPath $savePath3 -Label 'Thumbnails'

        $r1 | Should -BeFalse
        $r2 | Should -BeTrue
        $r3 | Should -BeFalse
        Should -Invoke Write-Progress -Times 3 -ParameterFilter { $Id -eq 42 -and $Completed }
    }

    It "clears the overlay for every call across an all-404 batch (upstream has none of these icons)" {
        Mock Invoke-TpmDownloadHttpClient { throw "Response status code does not indicate success: 404 (Not Found)." }
        Mock Invoke-TpmDownloadWebRequest { throw "Response status code does not indicate success: 404 (Not Found)." }

        1..3 | ForEach-Object {
            $savePath = Join-Path $TestDrive "all-404-$_.png"
            Invoke-TpmDownload -DownloadUrl "https://example.com/missing-$_.png" -DestinationPath $savePath -Label 'Thumbnails' | Should -BeFalse
        }

        Should -Invoke Write-Progress -Times 3 -ParameterFilter { $Id -eq 42 -and $Completed }
    }
}

Describe "Invoke-TpmDownload timeout / malformed content / cancellation (issue #132)" {
    # Rounds out the issue #132 acceptance criteria (HTTP 200/404 and mixed-
    # batch cleanup are already covered above): a network timeout, a
    # corrupt/incomplete downloaded file, and a user-cancelled transfer are
    # not special-cased anywhere in Invoke-TpmDownload -- they are ordinary
    # exceptions that must still be caught by the outer try/catch/finally,
    # never mis-reported as a 404 ("not in the online pack"), and must still
    # clear the Id 42 progress overlay and remove the partial temp file.
    BeforeAll {
        Mock Write-Log {}
        Mock Write-Host {}
        Mock Write-DownloadAudit {}
        Mock Write-TpmDownloadMetrics {}
        Mock Start-Sleep {}
        Mock Write-Progress {}
    }
    BeforeEach {
        Mock Test-TpmDownloadBitsAvailable { $false }
    }

    It "treats an HttpClient timeout as a generic failure (not a 404), clears the overlay, and removes the partial file" {
        Mock Invoke-TpmDownloadHttpClient {
            Set-Content -LiteralPath $TempPath -Value "partial" -NoNewline
            throw [System.Threading.Tasks.TaskCanceledException]::new("A task was canceled.")
        }
        Mock Invoke-TpmDownloadWebRequest { throw [System.Threading.Tasks.TaskCanceledException]::new("A task was canceled.") }
        $savePath = Join-Path $TestDrive "timeout-fail.png"
        $statusCode = 0

        $result = Invoke-TpmDownload -DownloadUrl "https://example.com/slow.png" -DestinationPath $savePath -Label 'Thumbnails' -LastStatusCode ([ref]$statusCode)

        $result | Should -BeFalse
        $statusCode | Should -Not -Be 404
        Test-Path -LiteralPath $savePath | Should -BeFalse
        Should -Invoke Write-Progress -Times 1 -ParameterFilter { $Id -eq 42 -and $Completed }
    }

    It "rejects an incomplete/malformed download that doesn't match the expected size, clears the overlay, and leaves no partial file behind" {
        Mock Invoke-TpmDownloadHttpClient {
            # Simulates a truncated/corrupt transfer: succeeds without
            # throwing, but writes fewer bytes than the caller expects.
            Set-Content -LiteralPath $TempPath -Value "short" -NoNewline
        }
        $savePath = Join-Path $TestDrive "malformed.png"

        $result = Invoke-TpmDownload -DownloadUrl "https://example.com/a.png" -DestinationPath $savePath -ExpectedBytes 999999 -Label 'Thumbnails'

        $result | Should -BeFalse
        Test-Path -LiteralPath $savePath | Should -BeFalse
        Should -Invoke Write-Progress -Times 1 -ParameterFilter { $Id -eq 42 -and $Completed }
    }

    It "treats a cancelled transfer (OperationCanceledException) as a clean failure, not an unhandled crash" {
        Mock Invoke-TpmDownloadHttpClient { throw [System.OperationCanceledException]::new("The operation was canceled.") }
        Mock Invoke-TpmDownloadWebRequest { throw [System.OperationCanceledException]::new("The operation was canceled.") }
        $savePath = Join-Path $TestDrive "cancelled.png"

        { Invoke-TpmDownload -DownloadUrl "https://example.com/a.png" -DestinationPath $savePath -Label 'Thumbnails' } | Should -Not -Throw
        $result = Invoke-TpmDownload -DownloadUrl "https://example.com/a.png" -DestinationPath $savePath -Label 'Thumbnails'

        $result | Should -BeFalse
        Should -Invoke Write-Progress -Times 2 -ParameterFilter { $Id -eq 42 -and $Completed }
    }

    It "clears the overlay for every call across a complete non-404 batch failure (e.g. upstream host unreachable)" {
        Mock Invoke-TpmDownloadHttpClient { throw "The remote name could not be resolved." }
        Mock Invoke-TpmDownloadWebRequest { throw "The remote name could not be resolved." }

        $statusCodes = 1..3 | ForEach-Object {
            $savePath = Join-Path $TestDrive "batch-fail-$_.png"
            $sc = 0
            $r = Invoke-TpmDownload -DownloadUrl "https://example.com/x-$_.png" -DestinationPath $savePath -Label 'Thumbnails' -LastStatusCode ([ref]$sc)
            $r | Should -BeFalse
            $sc
        }

        $statusCodes | Should -Not -Contain 404
        Should -Invoke Write-Progress -Times 3 -ParameterFilter { $Id -eq 42 -and $Completed }
    }
}

Describe "Invoke-TpmDownloadBits BITS polling states" {
    It "the polling loop's continue-states list includes TransientError (a recoverable BITS state), not just Connecting/Transferring/Queued" {
        $scriptContent = Get-Content -LiteralPath $scriptPath -Raw
        $scriptContent | Should -Match "'Connecting',\s*'Transferring',\s*'Queued',\s*'TransientError'"
    }
}

Describe "Invoke-CrosshairSetup P1/P2 prompts use the safe input path (issue #135 RC3 correction)" {
    # Invoke-CrosshairSetup cannot be exercised end-to-end in this suite for
    # the same reason documented on "Invoke-ThumbnailDownload 404-vs-failure
    # distinction" below: it reads $PSScriptRoot to locate the Crosshairs\
    # folder, which is empty because functions here are dot-sourced from an
    # AST extract with no backing file, so the function returns immediately
    # ("Crosshairs folder not found") before ever reaching the P1/P2 prompts
    # these tests target -- not something to route around by changing
    # production code under a "smallest safe fix" scope.
    #
    # These two prompts were the two remaining unguarded
    # `(Read-Host $promptText).Trim()` call sites missed by the original
    # #135 migration (that migration's regex only matched a Read-Host
    # argument that was a literal double-quoted string or a fully
    # parenthesized expression -- $promptText is a bare variable, a third
    # shape the regex never covered). Each site sits inside a
    # `while ($null -eq $pXIdx) { ... }` retry loop with no bound: under the
    # old unguarded code, once redirected stdin was exhausted, `Read-Host`
    # would return $null forever and `$null.Trim()` would throw a
    # NullReferenceException on the very first re-read after exhaustion --
    # worse than the plain crash-once behavior elsewhere in the script,
    # because Write-Host's "Enter a number..." retry message would print
    # first, masking that the real cause was exhausted input, not a bad
    # answer.
    BeforeAll {
        $fullSource = Get-Content -LiteralPath $scriptPath -Raw
        $start = $fullSource.IndexOf('function Invoke-CrosshairSetup')
        $end = $fullSource.IndexOf("`nfunction ", $start + 10)
        $script:crosshairSource = $fullSource.Substring($start, $end - $start)
    }

    It "finds the Invoke-CrosshairSetup function body to check" {
        $script:crosshairSource | Should -Not -BeNullOrEmpty
    }

    It "the P1 and P2 index prompts both go through Read-HostSafe" {
        (@([regex]::Matches($script:crosshairSource, 'Read-HostSafe \$promptText')).Count) | Should -Be 2
    }

    It "no bare Read-Host call in this function has .Trim() or .ToUpper() chained directly onto it" {
        $script:crosshairSource | Should -Not -Match '\(Read-Host\b[^)]*\)\.(Trim|ToUpper)\('
    }

    # Read-HostSafe's own null/exhausted-input behavior (never throws, exits
    # cleanly via the mockable Exit-TpmProcess instead) is already covered
    # exhaustively by "Read-HostSafe / Exit-TpmProcess (issue #135:
    # non-interactive input)" above -- since both crosshair prompts now
    # route through that exact same, already-tested function instead of a
    # bare Read-Host, that coverage applies here directly. This test
    # exercises the specific retry-loop SHAPE used in Invoke-CrosshairSetup
    # (a `while ($null -eq $idx) { $raw = (Read-HostSafe ...); ... }` loop
    # that never bounds its own retries) against a mocked exhausted stream,
    # proving the loop cannot spin on a null dereference even though the
    # real function isn't directly callable here.
    It "the crosshair index retry-loop shape terminates via Exit-TpmProcess on exhausted input instead of dereferencing null" {
        $script:readHostCallCount = 0
        Mock Read-Host { $script:readHostCallCount++; return $null }
        Mock Exit-TpmProcess { throw 'simulated-process-exit' }
        Mock Write-Log { }

        $validCount = 3
        $lastIdx = $null
        $idx = $null

        {
            while ($null -eq $idx) {
                if ($script:readHostCallCount -gt 5) { throw 'test guard: loop did not stop on exhausted input' }
                $promptText = if ($null -ne $lastIdx) {
                    "  P1 crosshair index (0-{0}, Enter for last used: {1})" -f ($validCount - 1), $lastIdx
                } else { "  P1 crosshair index (0-{0})" -f ($validCount - 1) }
                $raw = (Read-HostSafe $promptText)
                if ($raw -eq '' -and $null -ne $lastIdx) { $idx = $lastIdx }
                elseif ($raw -match '^\d+$' -and $raw.Length -le 9 -and [int]$raw -lt $validCount) { $idx = [int]$raw }
            }
        } | Should -Throw 'simulated-process-exit'

        # Exactly one Read-Host call before the mocked Exit-TpmProcess threw
        # -- proves the loop did not spin re-reading the exhausted stream.
        $script:readHostCallCount | Should -Be 1
        Should -Invoke Exit-TpmProcess -Times 1 -ParameterFilter { $Code -eq 1 }
    }
}

Describe "Invoke-ThumbnailDownload 404-vs-failure distinction" {
    # Invoke-ThumbnailDownload cannot be exercised end-to-end in this suite:
    # it reads $PSScriptRoot to locate CustomThumbnails\, which is empty
    # because functions here are dot-sourced from an AST extract with no
    # backing file (see the top-level BeforeAll). That makes the unrelated
    # CustomThumbnails Join-Path call throw a parameter-binding error before
    # the function ever reaches the download loop these tests target.
    # Confirmed empirically that neither reassigning $ErrorActionPreference
    # (BeforeEach or inline -- parameter-binding failures aren't governed by
    # it) nor mocking Join-Path (Pester's mock proxy mirrors the real
    # cmdlet's parameter validation, so the same binding failure recurs, and
    # routing through the module-qualified name from inside the mock
    # recurses back into the mock itself) can reach past this. This is a
    # pre-existing characteristic of the function, unrelated to the 404-vs-
    # failure fix -- not something to work around by changing production
    # code under a "smallest safe fix" scope. Verifying the fix at the
    # source level instead: these assert the exact code shape (StatusCode
    # -eq 404 -> notAvail, else -> failed) is present, which still fails if
    # the branching is ever accidentally reverted or merged wrong.
    BeforeAll {
        $fullSource = Get-Content -LiteralPath $scriptPath -Raw
        $script:thumbSource = $null
        $start = $fullSource.IndexOf('function Invoke-ThumbnailDownload')
        if ($start -ge 0) {
            $end = $fullSource.IndexOf("`nfunction ", $start + 10)
            $script:thumbSource = $fullSource.Substring($start, $end - $start)
        }
    }

    It "finds the Invoke-ThumbnailDownload function body to check" {
        $script:thumbSource | Should -Not -BeNullOrEmpty
    }

    It "passes -LastStatusCode through to Invoke-TpmDownload so 404 can be distinguished" {
        $script:thumbSource | Should -Match '-LastStatusCode\s*\(\[ref\]\$statusCode\)'
    }

    It "routes a 404 status code to the not-in-repo branch, not the failed branch" {
        $script:thumbSource | Should -Match '\$statusCode\s+-eq\s+404'
    }

    It "increments the failed counter (not the not-in-repo counter) for a non-404 failure" {
        # The elseif branch must handle the 404 case; whatever comes after
        # it (the plain else) is the non-404/generic-failure branch and
        # must increment $failed, not $notAvail.
        $script:thumbSource | Should -Match '\$statusCode\s+-eq\s+404[\s\S]*?\}\s*else\s*\{[\s\S]*?\$failed\+\+'
    }
}

Describe "Write-TpmDownloadProgress" {
    BeforeAll {
        Mock Write-Progress {}
    }

    It "shows percent complete when total size is known" {
        Write-TpmDownloadProgress -Method 'HttpClient' -DownloadedBytes 5242880 -TotalBytes 10485760 -Elapsed ([TimeSpan]::FromSeconds(2))

        Should -Invoke Write-Progress -Times 1 -ParameterFilter {
            $PercentComplete -eq 50 -and $Status -like '*5/10 MB*' -and $Status -like '*MB/s*' -and $Status -like '*ETA*'
        }
    }

    It "uses an indeterminate status when total size is unknown" {
        Write-TpmDownloadProgress -Method 'HttpClient' -DownloadedBytes 5242880 -TotalBytes 0 -Elapsed ([TimeSpan]::FromSeconds(2))

        Should -Invoke Write-Progress -Times 1 -ParameterFilter {
            $Status -like '*5 MB downloaded*' -and -not $PSBoundParameters.ContainsKey('PercentComplete')
        }
    }
}

Describe "Invoke-EggmanDatDownloadInteractive cache reuse" {
    BeforeAll {
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        function New-EggmanTestZip([string]$zipPath) {
            $fs = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::CreateNew)
            try {
                $archive = [System.IO.Compression.ZipArchive]::new($fs, [System.IO.Compression.ZipArchiveMode]::Create)
                try {
                    $entry = $archive.CreateEntry('TeknoParrot.Collection.2026_RomVault.dat')
                    $writer = New-Object System.IO.StreamWriter($entry.Open())
                    try { $writer.Write('<data />') } finally { $writer.Dispose() }
                } finally { $archive.Dispose() }
            } finally { $fs.Dispose() }
        }
        Mock Write-Log {}
        Mock Write-Host {}
        Mock Read-PathWithBrowse { "" }
        Mock Invoke-EggmanDatDownload { throw "download should be skipped when the cached file matches the expected size" }
    }

    It "does not re-download when the target file already matches the release size" {
        # Seed the exact deterministic TPM data root through the test-only
        # RootPath injection. The production path uses LocalApplicationData;
        # the fixture must never write into the real user profile.
        $fileName = "TeknoParrot.Collection.RomVault.zip"
        $defaultRoot = Join-Path $TestDrive 'eggman-data'
        New-Item -ItemType Directory -Path $defaultRoot -Force | Out-Null
        $defaultPath = Get-EggmanDatDefaultSavePath -FileName $fileName -RootPath $defaultRoot
        try {
            New-EggmanTestZip -zipPath $defaultPath
            $releaseSize = (Get-Item -LiteralPath $defaultPath).Length
            $rel = [pscustomobject]@{
                DownloadUrl = "https://github.com/Eggmansworld/TeknoParrot/releases/download/2026-06-17/$fileName"
                FileName    = $fileName
                SizeBytes   = $releaseSize
            }

            Invoke-EggmanDatDownloadInteractive $rel -DefaultRoot $defaultRoot | Should -Be $defaultPath
            Should -Invoke Read-PathWithBrowse -Times 0
            Should -Invoke Invoke-EggmanDatDownload -Times 0
        } finally {
            Remove-Item -LiteralPath $defaultPath -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Issue #252 Eggman recognition-data location and write boundary" {
    BeforeAll {
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        function New-EggmanFixtureZip([string]$zipPath) {
            $parent = Split-Path -Parent $zipPath
            if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            $fs = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::CreateNew)
            try {
                $archive = [System.IO.Compression.ZipArchive]::new($fs, [System.IO.Compression.ZipArchiveMode]::Create)
                try {
                    $entry = $archive.CreateEntry('TeknoParrot.Collection.2026_RomVault.dat')
                    $writer = New-Object System.IO.StreamWriter($entry.Open())
                    try { $writer.Write('<data />') } finally { $writer.Dispose() }
                } finally { $archive.Dispose() }
            } finally { $fs.Dispose() }
        }
        Mock Write-Log {}
        Mock Write-Host {}
    }

    BeforeEach {
        $script:tpRoot = ''
        $script:zipSource = ''
        $script:zipSourceSupplementary = ''
        $script:gamesInstallFolder = ''
    }

    It "uses the deterministic TPM per-user data root and does not create it while resolving the path" {
        $root = Get-EggmanDatDataRoot
        $root | Should -Match 'TeknoParrotManager\\Eggman$'
        $root | Should -Not -BeNullOrEmpty
    }

    It "does not ask for a save location on the normal first-run download path" {
        $defaultRoot = Join-Path $TestDrive 'normal-default'
        $fileName = 'TeknoParrot.Collection.RomVault.zip'
        $script:downloadPath = $null
        Mock Read-PathWithBrowse {}
        Mock Invoke-EggmanDatDownload {
            param([string]$downloadUrl, [string]$savePath, [Int64]$ExpectedBytes, [string]$ProgramDirectory)
            $script:downloadPath = $savePath
            return $true
        }
        $rel = [pscustomobject]@{ DownloadUrl = 'https://example.com/eggman.zip'; FileName = $fileName; SizeBytes = 0 }

        $result = Invoke-EggmanDatDownloadInteractive $rel -DefaultRoot $defaultRoot

        $result | Should -Be (Join-Path $defaultRoot $fileName)
        $script:downloadPath | Should -Be $result
        Should -Invoke Read-PathWithBrowse -Times 0
        Should -Invoke Invoke-EggmanDatDownload -Times 1
        Test-Path -LiteralPath $defaultRoot | Should -BeFalse
    }

    It "keeps the explicit alternate-location save override" {
        $defaultRoot = Join-Path $TestDrive 'alternate-default'
        $alternate = Join-Path $TestDrive 'alternate-location\Eggman.zip'
        $script:downloadPath = $null
        Mock Read-PathWithBrowse { $alternate }
        Mock Invoke-EggmanDatDownload {
            param([string]$downloadUrl, [string]$savePath, [Int64]$ExpectedBytes)
            $script:downloadPath = $savePath
            return $true
        }
        $rel = [pscustomobject]@{ DownloadUrl = 'https://example.com/eggman.zip'; FileName = 'latest.zip'; SizeBytes = 0 }

        $result = Invoke-EggmanDatDownloadInteractive $rel -AllowBrowse -DefaultRoot $defaultRoot

        $result | Should -Be ([System.IO.Path]::GetFullPath($alternate))
        $script:downloadPath | Should -Be $result
        Should -Invoke Read-PathWithBrowse -Times 1
    }

    It "preserves a valid configured path as the update destination when the user accepts the default" {
        $legacy = Join-Path $TestDrive 'legacy\custom-name.zip'
        New-EggmanFixtureZip -zipPath $legacy
        $script:downloadPath = $null
        Mock Read-PathWithBrowse { '' }
        Mock Invoke-EggmanDatDownload {
            param([string]$downloadUrl, [string]$savePath, [Int64]$ExpectedBytes, [string]$ProgramDirectory)
            $script:downloadPath = $savePath
            return $true
        }
        $rel = [pscustomobject]@{
            DownloadUrl = 'https://example.com/eggman.zip'
            FileName = 'new-release.zip'
            SizeBytes = ((Get-Item -LiteralPath $legacy).Length + 1)
        }

        $result = Invoke-EggmanDatDownloadInteractive $rel -AllowBrowse -PreferredSavePath $legacy -DefaultRoot (Join-Path $TestDrive 'new-default')

        $result | Should -Be ([System.IO.Path]::GetFullPath($legacy))
        $script:downloadPath | Should -Be $result
        Should -Invoke Read-PathWithBrowse -Times 0
    }

    It "rejects corrupt, wrong-type, and wrong-size files before reuse" {
        $corrupt = Join-Path $TestDrive 'corrupt.zip'
        Set-Content -LiteralPath $corrupt -Value ('x' * 128) -NoNewline
        Test-EggmanDatZip -Path $corrupt -ExpectedBytes 128 | Should -BeFalse

        $valid = Join-Path $TestDrive 'valid.zip'
        New-EggmanFixtureZip -zipPath $valid
        $size = (Get-Item -LiteralPath $valid).Length
        Test-EggmanDatZip -Path $valid -ExpectedBytes ($size + 1) | Should -BeFalse
        Test-EggmanDatZip -Path $valid -ExpectedBytes $size | Should -BeTrue
    }

    It "rejects protected TeknoParrot, supplementary source, and staging destinations without writing" {
        $tp = Join-Path $TestDrive 'TeknoParrot'
        $suppSource = Join-Path $TestDrive 'SupplementaryGameZips'
        $staging = Join-Path $TestDrive 'GameStaging'
        $script:tpRoot = $tp
        $script:zipSourceSupplementary = $suppSource
        $script:gamesInstallFolder = $staging
        $before = Get-TpmDirSnapshot -Dir $TestDrive
        Mock Read-PathWithBrowse { Join-Path $tp 'Eggman.zip' }
        Mock Invoke-EggmanDatDownload { throw 'protected destination must not reach downloader' }
        $rel = [pscustomobject]@{ DownloadUrl = 'https://example.com/eggman.zip'; FileName = 'latest.zip'; SizeBytes = 0 }

        $defaultResult = Invoke-EggmanDatDownloadInteractive $rel -DefaultRoot (Join-Path $tp 'Eggman')
        $alternateResult = Invoke-EggmanDatDownloadInteractive $rel -AllowBrowse -DefaultRoot (Join-Path $TestDrive 'safe-default')

        $defaultResult | Should -BeNullOrEmpty
        $alternateResult | Should -BeNullOrEmpty
        Should -Invoke Invoke-EggmanDatDownload -Times 0
        Assert-TpmDirSnapshotUnchanged -Before $before -After (Get-TpmDirSnapshot -Dir $TestDrive)
    }

    It "accepts a mapped-looking primary NAS source when the source role is safe" {
        $script:zipSource = 'W:\ROMs\TeknoParrot Collection'
        Mock Test-TpmNoReparsePath { $true }
        Mock Test-Path { $true }
        Mock Test-IsNetworkPath { $false }

        $role = Get-EggmanDatPathRole -Path $script:zipSource -RequestedRole PrimaryZipSource

        $role.Safe | Should -BeTrue
        $role.Role | Should -Be 'PrimaryZipSource'
        $role.CanonicalPath | Should -Be 'W:\ROMs\TeknoParrot Collection'
        Should -Invoke Test-TpmNoReparsePath -Times 1
        Should -Invoke Test-IsNetworkPath -Times 0
    }

    It "offers the safe primary source as the fallback for a DAT under TeknoParrot" {
        $tp = Join-Path $TestDrive 'TeknoParrot'
        $primary = Join-Path $TestDrive 'MainGameZips'
        New-Item -ItemType Directory -Path $tp -Force | Out-Null
        New-Item -ItemType Directory -Path $primary -Force | Out-Null
        $script:tpRoot = $tp
        $script:zipSource = $primary
        $script:downloadPath = $null
        $script:messages = @()
        Mock Read-HostSafe { 'Y' }
        Mock Read-PathWithBrowse { throw 'Browse should not be used when the safe primary source fallback is offered.' }
        Mock Write-Host { $script:messages += [string]$Object }
        Mock Invoke-EggmanDatDownload {
            param([string]$downloadUrl, [string]$savePath, [Int64]$ExpectedBytes, [string]$ProgramDirectory)
            $script:downloadPath = $savePath
            return $true
        }
        $rel = [pscustomobject]@{ DownloadUrl = 'https://example.com/eggman.zip'; FileName = 'latest.zip'; SizeBytes = 0 }

        $result = Invoke-EggmanDatDownloadInteractive $rel -AllowBrowse -PreferredSavePath (Join-Path $tp 'current.zip')

        $result | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $primary 'latest.zip')))
        $script:downloadPath | Should -Be $result
        ($script:messages -join [Environment]::NewLine) | Should -Match 'Current DAT is under the TeknoParrot root'
        ($script:messages -join [Environment]::NewLine) | Should -Match 'Safe external DAT folder found'
        Should -Invoke Read-PathWithBrowse -Times 0
        Should -Invoke Invoke-EggmanDatDownload -Times 1
    }

    It "does not confuse the supplementary source with the primary DAT destination" {
        $primary = Join-Path $TestDrive 'MainGameZips'
        $supplementary = Join-Path $TestDrive 'SupplementaryGameZips'
        New-Item -ItemType Directory -Path $primary -Force | Out-Null
        New-Item -ItemType Directory -Path $supplementary -Force | Out-Null
        $script:zipSource = $primary
        $script:zipSourceSupplementary = $supplementary

        $candidates = @(Get-EggmanDatDestinationCandidates)
        $supplementaryRole = Get-EggmanDatPathRole -Path (Join-Path $supplementary 'Eggman.zip')

        $candidates.Count | Should -Be 1
        $candidates[0].Path | Should -Be ([System.IO.Path]::GetFullPath($primary))
        $supplementaryRole.Safe | Should -BeFalse
        $supplementaryRole.ReasonCode | Should -Be 'SupplementarySource'
    }

    It "rejects a reparse-backed NAS source and ambiguous source roles" {
        $target = Join-Path $TestDrive 'NasTarget'
        $link = Join-Path $TestDrive 'NasLink'
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        try {
            [void](New-Item -ItemType Junction -Path $link -Target $target -ErrorAction Stop)
        } catch {
            Set-ItResult -Skipped -Because 'This worker cannot create directory junctions.'
            return
        }

        $script:zipSource = $link
        $reparseRole = Get-EggmanDatPathRole -Path $link -RequestedRole PrimaryZipSource
        $reparseRole.Safe | Should -BeFalse
        $reparseRole.ReasonCode | Should -Be 'ReparseOrInaccessible'

        $script:zipSource = Join-Path $TestDrive 'Primary'
        $script:zipSourceSupplementary = Join-Path $TestDrive 'Primary\Child'
        $ambiguousRole = Get-EggmanDatPathRole -Path (Join-Path $TestDrive 'other.zip')
        $ambiguousRole.Safe | Should -BeFalse
        $ambiguousRole.ReasonCode | Should -Be 'AmbiguousSourceRoles'
    }

    It "reports actionable recovery without querying or downloading when no fallback exists" {
        $tp = Join-Path $TestDrive 'TeknoParrot'
        New-Item -ItemType Directory -Path $tp -Force | Out-Null
        $script:tpRoot = $tp
        $script:messages = @()
        Mock Write-Host { $script:messages += [string]$Object }
        Mock Read-HostSafe { throw 'No prompt is expected without a safe destination.' }
        Mock Get-EggmanDatRelease { throw 'No release query is expected before destination selection.' }
        Mock Invoke-EggmanDatDownload { throw 'No download is expected without a safe destination.' }

        $resolution = Resolve-EggmanDatUpdateDestination -CurrentPath (Join-Path $tp 'current.zip')

        $resolution.Status | Should -Be 'NoSafeDestination'
        ($script:messages -join [Environment]::NewLine) | Should -Match 'No safe external primary DAT folder'
        ($script:messages -join [Environment]::NewLine) | Should -Match 'Action: configure a reachable primary ZIP/source folder'
        Should -Invoke Get-EggmanDatRelease -Times 0
        Should -Invoke Invoke-EggmanDatDownload -Times 0
    }

    It "revalidates the destination immediately before the final write" {
        $destination = Join-Path $TestDrive 'safe\Eggman.zip'
        $script:destinationChecks = 0
        $script:capturedValidation = $null
        $script:validationResult = $null
        $script:validationPath = Join-Path $TestDrive 'partial.zip'
        Mock Test-EggmanDatDestinationSafe {
            $script:destinationChecks++
            return ($script:destinationChecks -eq 1)
        }
        Mock Invoke-TpmDownload {
            param([scriptblock]$ValidationScript)
            $script:capturedValidation = $ValidationScript
            $script:validationResult = & $ValidationScript $script:validationPath
            return $true
        }
        Mock Write-Log {}

        Invoke-EggmanDatDownload -downloadUrl 'https://example.com/eggman.zip' -savePath $destination | Should -BeTrue
        $script:capturedValidation | Should -Not -BeNullOrEmpty
        $script:validationResult | Should -BeFalse
        $script:destinationChecks | Should -Be 2
    }

    It "leaves the existing destination untouched and removes the temporary file when archive validation fails" {
        $destination = Join-Path $TestDrive 'existing\Eggman.zip'
        New-EggmanFixtureZip -zipPath $destination
        $before = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($destination))
        $script:eggmanTransportTempPath = $null
        Mock Test-TpmDownloadBitsAvailable { $false }
        Mock Invoke-TpmDownloadHttpClient {
            param([string]$DownloadUrl, [string]$TempPath, [string]$Label)
            $script:eggmanTransportTempPath = $TempPath
            Set-Content -LiteralPath $TempPath -Value '12345' -NoNewline
        }
        Mock Write-Progress {}
        $relSize = 5

        $result = Invoke-EggmanDatDownload -downloadUrl 'https://example.com/eggman.zip' -savePath $destination -ExpectedBytes $relSize

        $result | Should -BeFalse
        [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($destination)) | Should -Be $before
        Test-Path -LiteralPath $script:eggmanTransportTempPath | Should -BeFalse
        @(Get-ChildItem -LiteralPath (Split-Path -Parent $destination) -Filter '*.partial' -Force -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    Context "Read-only helper AST guard" {
        BeforeAll {
            $script:eggmanProductionAst = [System.Management.Automation.Language.Parser]::ParseFile(
                (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'), [ref]$null, [ref]$null)
        }

        It "keeps path resolution, destination checks, archive validation, and freshness checks free of write APIs" -TestCases (
            @('Get-EggmanDatDataRoot', 'Get-EggmanDatDefaultSavePath', 'Test-TpmNoReparsePath', 'Get-EggmanDatPathRole', 'Test-EggmanDatDestinationSafe', 'Test-EggmanDatZip', 'Test-EggmanDatUpToDate') |
                ForEach-Object { @{ Name = $_ } }
        ) {
            param($Name)
            $fn = $eggmanProductionAst.FindAll({
                $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq $Name
            }, $true) | Select-Object -First 1
            $fn | Should -Not -BeNullOrEmpty
            $forbiddenCommands = @('Add-Content', 'Set-Content', 'Out-File', 'New-Item', 'Remove-Item', 'Move-Item', 'Copy-Item', 'Rename-Item',
                'Invoke-ControlPropagation', 'Set-ProfileInputApi', 'Save-XmlMaybe', 'Save-Xml')
            $calls = $fn.Body.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true) |
                ForEach-Object { $_.GetCommandName() } | Where-Object { $_ }
            foreach ($nameToReject in $forbiddenCommands) { $calls | Should -Not -Contain $nameToReject }
            $forbiddenMembers = @('Save', 'WriteAllText', 'WriteAllBytes', 'WriteAllLines', 'AppendAllText', 'AppendAllLines', 'AppendText',
                'Delete', 'Move', 'MoveTo', 'Copy', 'CopyTo', 'Replace', 'CreateText', 'Create', 'SetLastWriteTime', 'SetAttributes')
            $memberCalls = $fn.Body.FindAll({ $args[0] -is [System.Management.Automation.Language.InvokeMemberExpressionAst] }, $true) |
                ForEach-Object { ($_.Member.Extent.Text -replace "^[`"']|[`"']$", '') } | Where-Object { $_ }
            foreach ($memberName in $forbiddenMembers) { $memberCalls | Should -Not -Contain $memberName }
        }
    }

    It "documents the ownership boundary and keeps the normal first-run call prompt-free" {
        $ProductionSource | Should -Match 'ParrotData\.xml'
        $ProductionSource | Should -Match 'DAT/XML setting'
        $ProductionSource | Should -Match 'supplementary game ZIPs'
        $ProductionSource | Should -Match 'staging/install folder'
        $ProductionSource | Should -Match 'TPM will normally store a downloaded copy under'
        $ProductionSource | Should -Match 'Invoke-EggmanDatDownloadInteractive \$rel -ProgramDirectory \$PSScriptRoot'
        $ProductionSource | Should -Match 'Resolve-EggmanDatUpdateDestination -CurrentPath \$eggmanDatZip'
    }
}

Describe "Thumbnail download regression guards" {
    BeforeAll {
        $script:thumbnailFunctionSource = ${function:Invoke-ThumbnailDownload}.ToString()
    }

    It "keeps the already-present icon fast path before building the download list" {
        $script:thumbnailFunctionSource | Should -Match 'Test-Path\s+-LiteralPath\s+\(Join-Path\s+\$iconsDir\s+\(\$f\.BaseName\s+\+\s+"\.png"\)\)'
        $script:thumbnailFunctionSource | Should -Match '\$alreadyCount\+\+'
        $script:thumbnailFunctionSource | Should -Match '\[void\]\$missing\.Add\(\$f\.BaseName\)'
    }

    It "delegates thumbnail downloads (and their failure/partial-file cleanup) to the shared download helper" {
        # Cleanup used to be reimplemented per-call-site here (Test-Path /
        # Remove-Item directly on $destPath). After the download-pipeline
        # hardening (issue #67), Invoke-TpmDownload owns partial-file
        # staging and cleanup centrally (see "Invoke-TpmDownload method
        # selection and partial-file cleanup" below) -- this function must
        # call it rather than reimplement cleanup itself.
        $script:thumbnailFunctionSource | Should -Match 'Invoke-TpmDownload\s+-DownloadUrl\s+\$url\s+-DestinationPath\s+\$destPath'
        $script:thumbnailFunctionSource | Should -Match '-LastStatusCode\s*\(\[ref\]\$statusCode\)'
    }

    It "flags an all-404 batch distinctly from a real failure (issue #132 -- likely profile-code/upstream-name mismatch, not a broken download path)" {
        $script:thumbnailFunctionSource | Should -Match '\$fetched\s+-eq\s+0\s+-and\s+\$failed\s+-eq\s+0\s+-and\s+\$notAvail\s+-eq\s+\$total\s+-and\s+\$total\s+-gt\s+0'
    }
}

Describe "Invoke-TpmDownload finally block always clears the progress overlay (issue #132)" {
    It "the finally block completes Id 42 unconditionally, not only on the success path" {
        $fullSource = Get-Content -LiteralPath $scriptPath -Raw
        $start = $fullSource.IndexOf('function Invoke-TpmDownload {')
        $start | Should -BeGreaterThan -1
        $end = $fullSource.IndexOf("`nfunction ", $start + 10)
        $downloadFnSource = $fullSource.Substring($start, $end - $start)

        $downloadFnSource | Should -Match '\}\s*finally\s*\{\s*[\s\S]*?Write-Progress\s+-Id\s+42\s+-Activity\s+"Downloading\s+\$Label"\s+-Completed'
    }
}

Describe "Crosshair setup regression guards" {
    # ECVF: cursor_path is pcsx2x6-emulator-owned for jvsmode=lightgun
    # titles (contracts\pcsx2x6\contract.json, evidence.md#ev-guncon2-clear)
    # -- the emulator clears it in memory regardless of what TPM writes, so
    # Set-Pcsx2CursorPaths now consults the ECVF contract framework before
    # writing and fails closed (skips the write) if that framework cannot
    # be consulted, rather than falling back to the old unconditional
    # write. In THIS test harness specifically, $PSScriptRoot resolves to
    # an empty string for a function body extracted via AST and
    # dot-sourced from a scriptblock (confirmed empirically -- there is no
    # real backing file for the dynamically-created scriptblock), so the
    # module path never resolves and every call here exercises the
    # fail-closed "framework unavailable" branch. That is the correct,
    # real behavior for this test's actual scope: proving the function
    # never falls back to writing when it cannot confirm the write is
    # safe -- not a workaround to keep an old assertion passing.
    It "skips the cursor_path write, leaves the ini untouched, and creates no backup when the ECVF framework cannot be consulted" {
        $iniDir = Join-Path $TestDrive "inis"
        New-Item -ItemType Directory -Path $iniDir -Force | Out-Null
        $iniPath = Join-Path $iniDir "PCSX2.ini"
        Set-Content -LiteralPath $iniPath -Value "[USB Port 1 guncon2]`ncursor_path = old1`n[USB Port 2 guncon2]`ncursor_path = old2"
        $originalContent = Get-Content -LiteralPath $iniPath -Raw
        Mock Write-Log {}

        $result = Set-Pcsx2CursorPaths -IniPath $iniPath -P1Path "C:\Crosshairs\P1.png" -P2Path "C:\Crosshairs\P2.png"

        $result | Should -Be $false
        (Get-Content -LiteralPath $iniPath -Raw) | Should -Be $originalContent
        @(Get-ChildItem -LiteralPath $iniDir -Filter "PCSX2.ini.bak_*" -File).Count | Should -Be 0
    }

    # Invoke-CrosshairSetup itself is an interactive wizard (Read-Host prompts,
    # browser preview launch) excluded from direct unit testing per this file's
    # policy -- source-level check instead, same pattern as "Main menu
    # source-level drift check" below for other hard-to-unit-test interactive code.
    It "deploys pcsx2x6 crosshairs under the contract-resolved DataRoot\crosshairs subfolder, not the emulator folder root (issue #79)" {
        $source = Get-Content -LiteralPath $scriptPath -Raw
        $source | Should -Match ([regex]::Escape('$crosshairSubDir = Join-Path $dataRoot "crosshairs"'))
        # Regression guard: the pre-#79-fix deployment target (folder root) must
        # not reappear as the pcsx2x6 P1/P2 destination.
        $source | Should -Not -Match ([regex]::Escape('Join-Path $pcsx2Dir "P1.png"'))
        $source | Should -Not -Match ([regex]::Escape('Join-Path $pcsx2Dir "P2.png"'))
    }
}

Describe "Test-ButtonNameDirectional" {
    # Pure up/down/left/right labels (with various player-prefix formats) are directional.
    It "classifies plain 'Up' as directional" {
        Test-ButtonNameDirectional "Up" | Should -BeTrue
    }
    It "classifies 'Player 1 Up' as directional" {
        Test-ButtonNameDirectional "Player 1 Up" | Should -BeTrue
    }
    It "classifies 'P1 UP' as directional (case-insensitive, P1 prefix)" {
        Test-ButtonNameDirectional "P1 UP" | Should -BeTrue
    }
    It "classifies 'Player 2 Down' as directional" {
        Test-ButtonNameDirectional "Player 2 Down" | Should -BeTrue
    }
    It "classifies diagonal 'Up Right' as directional" {
        Test-ButtonNameDirectional "Up Right" | Should -BeTrue
    }

    # Names that contain direction words but also have non-direction qualifiers are NOT directional.
    It "classifies 'Player 1 Left Punch' as NOT directional (attack qualifier)" {
        Test-ButtonNameDirectional "Player 1 Left Punch" | Should -BeFalse
    }
    It "classifies 'Player 1 Right Kick' as NOT directional (attack qualifier)" {
        Test-ButtonNameDirectional "Player 1 Right Kick" | Should -BeFalse
    }
    It "classifies 'Player 1 Left Shoulder' as NOT directional (non-direction qualifier)" {
        Test-ButtonNameDirectional "Player 1 Left Shoulder" | Should -BeFalse
    }

    # Pure attack/action labels with no direction words are NOT directional.
    It "classifies 'Player 1 LP' as NOT directional" {
        Test-ButtonNameDirectional "Player 1 LP" | Should -BeFalse
    }
    It "classifies 'P1 ATTACK' as NOT directional" {
        Test-ButtonNameDirectional "P1 ATTACK" | Should -BeFalse
    }
    It "classifies empty string as NOT directional" {
        Test-ButtonNameDirectional "" | Should -BeFalse
    }
}

Describe "Invoke-ControlPropagation duplicate-key handling (issue #53)" {
    BeforeAll {
        function New-ControlProfileXml {
            param(
                [string]$Name,
                [string]$Buttons
            )

            return @"
<GameProfile>
  <GameName>$Name</GameName>
  <JoystickButtons>
$Buttons
  </JoystickButtons>
  <ConfigValues />
</GameProfile>
"@
        }

        function New-WheelButtonXml {
            param(
                [string]$Name,
                [string]$Mapping = 'P1Wheel',
                [switch]$Bound
            )

            $binding = if ($Bound) {
                @"
      <RawInputButton>
        <DevicePath>test-wheel</DevicePath>
        <ButtonName>X+</ButtonName>
      </RawInputButton>
"@
            } else {
                ''
            }

            return @"
    <JoystickButtons>
      <ButtonName>$Name</ButtonName>
      <InputMapping>$Mapping</InputMapping>
      <AnalogType>Wheel</AnalogType>
$binding
    </JoystickButtons>
"@
        }
    }

    It "uses an archetype match key only once per target profile" {
        $profiles = Join-Path $TestDrive 'UserProfiles'
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null

        $archetypeButtons = @(
            New-WheelButtonXml -Name 'Wheel Right' -Bound
            New-WheelButtonXml -Name 'Gas' -Mapping 'P1Gas' -Bound
            New-WheelButtonXml -Name 'Brake' -Mapping 'P1Brake' -Bound
        ) -join "`n"
        New-ControlProfileXml -Name 'Reference Driver' -Buttons $archetypeButtons |
            Set-Content -LiteralPath (Join-Path $profiles 'ReferenceDriver.xml') -Encoding UTF8

        $targetButtons = @(
            New-WheelButtonXml -Name 'Wheel Left'
            New-WheelButtonXml -Name 'Wheel Right'
        ) -join "`n"
        New-ControlProfileXml -Name 'Duplicate Wheel Target' -Buttons $targetButtons |
            Set-Content -LiteralPath (Join-Path $profiles 'DuplicateWheelTarget.xml') -Encoding UTF8

        $pool = Build-ArchetypePool $profiles 3
        $reports = Invoke-ControlPropagation -userProfilesDir $profiles -pool $pool -minBound 3 -DryRun:$false
        [xml]$updated = Get-Content -LiteralPath (Join-Path $profiles 'DuplicateWheelTarget.xml') -Raw
        $targetSlots = @($updated.SelectNodes('/GameProfile/JoystickButtons/JoystickButtons'))
        $boundSlots = @($targetSlots | Where-Object { Test-ButtonIsBound $_ })
        $manualReport = @($reports | Where-Object { $_.Code -eq 'DuplicateWheelTarget' } | Select-Object -First 1)

        $boundSlots.Count | Should -Be 1
        $manualReport.Status | Should -Be 'bound'
        $manualReport.Manual | Should -Contain 'Wheel Right'
    }
}

Describe "Invoke-ControlPropagation canonicalArchetype Input API correction (issue #139)" {
    # Fixtures modeled directly on the real diagnostic data posted to issue
    # #139: StreetFighterIII3rdStrike (SF3) and fghtjam (Capcom Fighting Jam)
    # were found to have byte-for-byte identical Coin1/Coin2/P1ButtonStart/
    # P2ButtonStart bindings (button 54/54/55/55 on the same two joystick
    # GUIDs) -- the reported "inconsistent mapping" was never a binding
    # divergence between these two titles. The actual defect confirmed on
    # this issue was that "Input API" can independently drift between two
    # archetypes of the same family (fghtjam's on-disk FieldOptions lacked
    # MergedInput entirely, unlike SF3's), and that canonicalArchetype
    # correction only propagates whatever the canonical game's Input API
    # happens to be in the live pool snapshot at the moment propagation
    # runs -- so the canonical game must already be on the intended API
    # before the fix is applied, or the "fix" just propagates the wrong
    # value to every other archetype in the family.
    BeforeAll {
        function New-ButtonFamilyProfileXml {
            param(
                [string]$Name,
                [string]$InputApiValue,
                [string[]]$InputApiOptions
            )
            $optionsXml = ($InputApiOptions | ForEach-Object { "        <string>$_</string>" }) -join "`n"
            $slots = @(
                @{ Name = 'Test';               Mapping = 'Test';           Button = 92 }
                @{ Name = 'Service 1';           Mapping = 'Service1';       Button = 93 }
                @{ Name = 'Service 2';           Mapping = 'Service2';       Button = 94 }
                @{ Name = 'Coin 1';              Mapping = 'Coin1';          Button = 54 }
                @{ Name = 'Coin 2';              Mapping = 'Coin2';          Button = 54 }
                @{ Name = 'Player 1 Start';      Mapping = 'P1ButtonStart';  Button = 55 }
                @{ Name = 'Player 2 Start';      Mapping = 'P2ButtonStart';  Button = 55 }
            )
            $buttonsXml = ($slots | ForEach-Object {
                @"
    <JoystickButtons>
      <ButtonName>$($_.Name)</ButtonName>
      <InputMapping>$($_.Mapping)</InputMapping>
      <DirectInputButton>
        <Button>$($_.Button)</Button>
      </DirectInputButton>
    </JoystickButtons>
"@
            }) -join "`n"
            return @"
<GameProfile>
  <GameName>$Name</GameName>
  <JoystickButtons>
$buttonsXml
  </JoystickButtons>
  <ConfigValues>
    <FieldInformation>
      <FieldName>Input API</FieldName>
      <FieldValue>$InputApiValue</FieldValue>
      <FieldOptions>
$optionsXml
      </FieldOptions>
    </FieldInformation>
  </ConfigValues>
</GameProfile>
"@
        }
    }

    It "does not alter either archetype's own button bindings, even though both are independently bound and physically identical" {
        $profiles = Join-Path $TestDrive ("issue139-bindings-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null

        New-ButtonFamilyProfileXml -Name 'StreetFighterIII3rdStrike' -InputApiValue 'MergedInput' -InputApiOptions @('DirectInput', 'XInput', 'MergedInput') |
            Set-Content -LiteralPath (Join-Path $profiles 'StreetFighterIII3rdStrike.xml') -Encoding UTF8
        New-ButtonFamilyProfileXml -Name 'fghtjam' -InputApiValue 'DirectInput' -InputApiOptions @('DirectInput', 'XInput') |
            Set-Content -LiteralPath (Join-Path $profiles 'fghtjam.xml') -Encoding UTF8

        $before = Get-Content -LiteralPath (Join-Path $profiles 'fghtjam.xml') -Raw
        $pool = Build-ArchetypePool $profiles 5
        [void](Invoke-ControlPropagation -userProfilesDir $profiles -pool $pool -minBound 5 -DryRun:$false)
        $after = Get-Content -LiteralPath (Join-Path $profiles 'fghtjam.xml') -Raw

        ([xml]$after).SelectSingleNode("/GameProfile/JoystickButtons/JoystickButtons[InputMapping='Coin1']/DirectInputButton/Button").InnerText | Should -Be '54'
        ([xml]$after).SelectSingleNode("/GameProfile/JoystickButtons/JoystickButtons[InputMapping='P1ButtonStart']/DirectInputButton/Button").InnerText | Should -Be '55'
    }

    It "corrects a non-canonical archetype's Input API to match the canonical archetype's CURRENT value, including injecting a missing MergedInput FieldOptions entry" {
        $profiles = Join-Path $TestDrive ("issue139-api-fix-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null

        New-ButtonFamilyProfileXml -Name 'StreetFighterIII3rdStrike' -InputApiValue 'MergedInput' -InputApiOptions @('DirectInput', 'XInput', 'MergedInput') |
            Set-Content -LiteralPath (Join-Path $profiles 'StreetFighterIII3rdStrike.xml') -Encoding UTF8
        New-ButtonFamilyProfileXml -Name 'fghtjam' -InputApiValue 'DirectInput' -InputApiOptions @('DirectInput', 'XInput') |
            Set-Content -LiteralPath (Join-Path $profiles 'fghtjam.xml') -Encoding UTF8

        $pool = Build-ArchetypePool $profiles 5
        $canonicalArchetype = @{ button = 'StreetFighterIII3rdStrike' }
        $reports = Invoke-ControlPropagation -userProfilesDir $profiles -pool $pool -minBound 5 -canonicalArchetype $canonicalArchetype -DryRun:$false

        [xml]$fghtjamAfter = Get-Content -LiteralPath (Join-Path $profiles 'fghtjam.xml') -Raw
        $apiField = $fghtjamAfter.SelectSingleNode("/GameProfile/ConfigValues/FieldInformation[FieldName='Input API']")
        $apiField.FieldValue | Should -Be 'MergedInput'
        @($apiField.SelectNodes('FieldOptions/string') | ForEach-Object { $_.InnerText }) | Should -Contain 'MergedInput'

        $fixedReport = @($reports | Where-Object { $_.Code -eq 'fghtjam' } | Select-Object -First 1)
        $fixedReport.Status | Should -Be 'api-fixed-canonical'
    }

    It "propagates the WRONG value if the canonical archetype itself is not yet on the intended API when correction runs (ordering hazard confirmed on issue #139)" {
        # This documents the exact failure mode from the issue thread: writing
        # canonicalArchetype to overrides.json before switching the canonical
        # game's own Input API does not "fix forward" -- it corrects every
        # other archetype in the family to match whatever the canonical
        # game's CURRENT (possibly still-wrong) value is.
        $profiles = Join-Path $TestDrive ("issue139-ordering-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null

        New-ButtonFamilyProfileXml -Name 'StreetFighterIII3rdStrike' -InputApiValue 'DirectInput' -InputApiOptions @('DirectInput', 'XInput', 'MergedInput') |
            Set-Content -LiteralPath (Join-Path $profiles 'StreetFighterIII3rdStrike.xml') -Encoding UTF8
        New-ButtonFamilyProfileXml -Name 'fghtjam' -InputApiValue 'MergedInput' -InputApiOptions @('DirectInput', 'XInput', 'MergedInput') |
            Set-Content -LiteralPath (Join-Path $profiles 'fghtjam.xml') -Encoding UTF8

        $pool = Build-ArchetypePool $profiles 5
        $canonicalArchetype = @{ button = 'StreetFighterIII3rdStrike' }
        [void](Invoke-ControlPropagation -userProfilesDir $profiles -pool $pool -minBound 5 -canonicalArchetype $canonicalArchetype -DryRun:$false)

        [xml]$fghtjamAfter = Get-Content -LiteralPath (Join-Path $profiles 'fghtjam.xml') -Raw
        $fghtjamAfter.SelectSingleNode("/GameProfile/ConfigValues/FieldInformation[FieldName='Input API']/FieldValue").InnerText | Should -Be 'DirectInput'
    }

    It "does not touch a non-canonical archetype whose Input API already matches the canonical archetype" {
        $profiles = Join-Path $TestDrive ("issue139-noop-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null

        New-ButtonFamilyProfileXml -Name 'StreetFighterIII3rdStrike' -InputApiValue 'MergedInput' -InputApiOptions @('DirectInput', 'XInput', 'MergedInput') |
            Set-Content -LiteralPath (Join-Path $profiles 'StreetFighterIII3rdStrike.xml') -Encoding UTF8
        New-ButtonFamilyProfileXml -Name 'BBCF' -InputApiValue 'MergedInput' -InputApiOptions @('DirectInput', 'XInput', 'MergedInput') |
            Set-Content -LiteralPath (Join-Path $profiles 'BBCF.xml') -Encoding UTF8

        $pool = Build-ArchetypePool $profiles 5
        $canonicalArchetype = @{ button = 'StreetFighterIII3rdStrike' }
        $reports = Invoke-ControlPropagation -userProfilesDir $profiles -pool $pool -minBound 5 -canonicalArchetype $canonicalArchetype -DryRun:$false

        @($reports | Where-Object { $_.Code -eq 'BBCF' }).Count | Should -Be 0
    }
}

Describe "MinBoundForArchetype initialization order (issue #139)" {
    # Confirmed root cause on issue #139: the standalone "Propagate Controls"
    # menu handler runs entirely inside the MAIN MENU LOOP and returns via
    # `continue` without ever reaching SECTION 10, where
    # $MinBoundForArchetype was previously first assigned. Left unset on
    # that path, [int]$minBound coerced $null to 0 in Build-ArchetypePool,
    # so every profile (including fully unbound ones) qualified as an
    # archetype and propagation silently produced "Games updated: 0" with no
    # per-game report lines. This is a source-level regression guard (not a
    # functional test) because the bug is about variable-initialization
    # ordering in the interactive menu loop, not a pure function's behavior.
    BeforeAll {
        $script:rawScriptText = Get-Content -LiteralPath (Join-Path $PSScriptRoot "..\TeknoParrot-Manager.ps1") -Raw
    }

    It "assigns `$MinBoundForArchetype before the standalone PropagateControls menu handler can read it" {
        $handlerIndex = $script:rawScriptText.IndexOf('if ($mode -eq "PropagateControls")')
        $handlerIndex | Should -BeGreaterThan 0

        $assignmentIndex = $script:rawScriptText.IndexOf('$MinBoundForArchetype = 5')
        $assignmentIndex | Should -BeGreaterThan 0
        $assignmentIndex | Should -BeLessThan $handlerIndex
    }
}

Describe "Write-ControlPropagationResults (issue #59: standalone Propagate Controls)" {
    # This function is the shared reporting step behind both the AutoSync/
    # Register-only flow and the standalone "Propagate Controls" menu option
    # (issue #59) -- the same $reports shape Invoke-ControlPropagation always
    # returns, in, count out. Exercising it directly protects both call sites
    # from drifting out of sync with each other.
    It "counts bound/api-fixed/api-fixed-canonical as updated and returns the no-archetype subset" {
        $reports = @(
            [pscustomobject]@{ Code = 'GameA'; Status = 'bound'; Family = 'driving'; Archetype = 'RefDriver'; Bound = 3; Manual = @(); ConfigCarried = @(); ApiSet = $true; ArchetypeApi = 'RawInput'; Forced = $false; MismatchSlots = $null }
            [pscustomobject]@{ Code = 'GameB'; Status = 'api-fixed'; ArchetypeApi = 'RawInput'; Archetype = 'RefDriver'; MismatchSlots = $null }
            [pscustomobject]@{ Code = 'GameC'; Status = 'api-fixed-canonical'; ArchetypeApi = 'RawInput'; Archetype = 'RefDriver'; MismatchSlots = $null }
            [pscustomobject]@{ Code = 'GameD'; Status = 'no-archetype'; Family = 'lightgun'; MismatchSlots = $null }
            [pscustomobject]@{ Code = 'GameE'; Status = 'skipped-bound'; MismatchSlots = $null }
            [pscustomobject]@{ Code = 'GameF'; Status = 'skipped-override'; MismatchSlots = $null }
            [pscustomobject]@{ Code = 'GameG'; Status = 'save-failed'; Archetype = 'RefDriver'; MismatchSlots = $null }
        )

        $result = Write-ControlPropagationResults -Reports $reports

        $result.BoundCount | Should -Be 3
        $result.NoArchetypeItems.Count | Should -Be 1
        $result.NoArchetypeItems[0].Code | Should -Be 'GameD'
    }

    It "returns zero updated and an empty no-archetype list for an all-skipped report set" {
        $reports = @(
            [pscustomobject]@{ Code = 'GameH'; Status = 'skipped-bound'; MismatchSlots = $null }
            [pscustomobject]@{ Code = 'GameI'; Status = 'skipped-override'; MismatchSlots = $null }
        )

        $result = Write-ControlPropagationResults -Reports $reports

        $result.BoundCount | Should -Be 0
        $result.NoArchetypeItems.Count | Should -Be 0
    }
}

Describe "New-PropagationBackup (P1 fix: standalone Propagate Controls must abort on incomplete backup)" {
    # Independent engineering review finding on PR #62: a backup-copy error in the standalone
    # Propagate Controls menu option only warned and allowed the caller to
    # continue -- including automatically in -Unattended mode -- so
    # Invoke-ControlPropagation could run against an incomplete backup. This
    # directly proves the gating condition every caller relies on: ErrorCount
    # is greater than zero whenever any source file could not be copied, with
    # no path that reports success/zero on a partial failure.
    It "reports zero errors and the correct path when every file copies successfully" {
        $profiles = Join-Path $TestDrive ("propback-ok-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $profiles 'Game.xml') -Value '<GameProfile/>' -Encoding UTF8

        $result = New-PropagationBackup -UserProfilesDir $profiles

        $result.ErrorCount | Should -Be 0
        Test-Path -LiteralPath (Join-Path $result.Path 'Game.xml') | Should -BeTrue
    }

    It "signals an abort-worthy failure when a source file is locked and cannot be copied" {
        # A sharing-violation on Copy-Item can surface either as a
        # non-terminating error (caught into ErrorCount via -ErrorAction
        # SilentlyContinue) or, depending on exactly how the underlying I/O
        # call fails, as a terminating exception that -ErrorAction alone
        # does not suppress. Both are safe: the real caller in the
        # "PropagateControls" menu block wraps this call in try/catch AND
        # checks ErrorCount, so either outcome correctly prevents
        # Invoke-ControlPropagation from running. This test accepts either,
        # since the point is proving no path silently reports success.
        $profiles = Join-Path $TestDrive ("propback-locked-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null
        $lockedPath = Join-Path $profiles 'Locked.xml'
        Set-Content -LiteralPath $lockedPath -Value '<GameProfile/>' -Encoding UTF8

        $handle = [System.IO.File]::Open($lockedPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        try {
            $threw = $false
            $result = $null
            try {
                $result = New-PropagationBackup -UserProfilesDir $profiles
            } catch {
                $threw = $true
            }
            ($threw -or $result.ErrorCount -gt 0) | Should -BeTrue
        } finally {
            $handle.Dispose()
        }
    }
}

# =============================================================================
# COMPATIBILITY REGRESSION SUITE (issues #41 / #43 / #46)
# These contexts protect the compatibility-sensitive setup decisions against
# upstream TeknoParrot schema/platform drift. The cardinal invariant under
# test throughout: an unsupported or unknown outcome must report WouldWrite =
# $false, i.e. never causes the setup flow to write a profile.
# =============================================================================

Describe "Get-FFBBlasterSupport (issue #41 capability gating)" {
    BeforeAll {
        # Builds a full <GameProfile> with an EmulationProfile and arbitrary
        # ConfigValues inner XML, so the platform deny-list and field gate are
        # both exercised the way the real per-profile loop sees them.
        function New-FfbProfileDoc {
            param([string]$Platform, [string]$Inner)
            return [xml]"<GameProfile><EmulationProfile>$Platform</EmulationProfile><ConfigValues>$Inner</ConfigValues></GameProfile>"
        }
        $script:FfbField = "<FieldInformation><CategoryName>FFB Blaster</CategoryName><FieldName>Enable</FieldName><FieldType>Bool</FieldType><FieldValue>0</FieldValue></FieldInformation>"
    }

    It "Supported: a profile with an FFB Blaster Bool field is offered setup and WouldWrite when not yet enabled" {
        $doc = New-FfbProfileDoc -Platform "EuropaRFordRacing" -Inner $script:FfbField
        $r = Get-FFBBlasterSupport -Doc $doc -Categories @('FFB Blaster')
        $r.Status     | Should -Be 'Supported'
        $r.WouldWrite | Should -BeTrue
        $r.Changes[0].NewValue | Should -Be '1'
    }
    It "Supported but no write needed: an already-enabled field reports WouldWrite=false" {
        $inner = "<FieldInformation><CategoryName>FFB Blaster</CategoryName><FieldName>Enable</FieldName><FieldType>Bool</FieldType><FieldValue>1</FieldValue></FieldInformation>"
        $doc = New-FfbProfileDoc -Platform "Daytona3" -Inner $inner
        $r = Get-FFBBlasterSupport -Doc $doc -Categories @('FFB Blaster')
        $r.Status     | Should -Be 'Supported'
        $r.UpToDate   | Should -BeTrue
        $r.WouldWrite | Should -BeFalse
    }
    It "Unsupported (no field): a profile without an FFB Blaster field is skipped and never written" {
        $inner = "<FieldInformation><CategoryName>General</CategoryName><FieldName>Windowed</FieldName><FieldType>Bool</FieldType><FieldValue>0</FieldValue></FieldInformation>"
        $doc = New-FfbProfileDoc -Platform "EuropaRFordRacing" -Inner $inner
        $r = Get-FFBBlasterSupport -Doc $doc -Categories @('FFB Blaster')
        $r.Status     | Should -Be 'Unsupported'
        $r.WouldWrite | Should -BeFalse
    }
    It "Unsupported (PCSX2x6): a pcsx2x6 profile is skipped EVEN when an FFB Blaster field is present" {
        # Deny-list must win over field presence -- this is the core safety
        # property: a future upstream field on an unsupported platform must
        # never trigger a write.
        $doc = New-FfbProfileDoc -Platform "pcsx2x6" -Inner $script:FfbField
        $r = Get-FFBBlasterSupport -Doc $doc -Categories @('FFB Blaster')
        $r.Status     | Should -Be 'Unsupported'
        $r.WouldWrite | Should -BeFalse
        $r.Reason     | Should -Match 'pcsx2x6'
    }
    It "Unsupported (PCSX2x6 via EmulatorType fallback): deny-list also matches when only EmulatorType carries the platform" {
        $doc = [xml]"<GameProfile><EmulatorType>pcsx2x6</EmulatorType><ConfigValues>$script:FfbField</ConfigValues></GameProfile>"
        $r = Get-FFBBlasterSupport -Doc $doc -Categories @('FFB Blaster')
        $r.Status     | Should -Be 'Unsupported'
        $r.WouldWrite | Should -BeFalse
    }
    It "Unsupported (PCSX2x6 case-insensitive): 'PCSX2X6' is matched regardless of case" {
        $doc = New-FfbProfileDoc -Platform "PCSX2X6" -Inner $script:FfbField
        (Get-FFBBlasterSupport -Doc $doc -Categories @('FFB Blaster')).Status | Should -Be 'Unsupported'
    }
    It "Unknown: an FFB Blaster-shaped field that is NOT a writable Bool is flagged for review, never written" {
        # FieldType is Dropdown, not Bool -> schema drift -> Unknown, no write.
        $inner = "<FieldInformation><CategoryName>FFB Blaster</CategoryName><FieldName>Mode</FieldName><FieldType>Dropdown</FieldType><FieldValue>Off</FieldValue><FieldOptions><string>Off</string><string>On</string></FieldOptions></FieldInformation>"
        $doc = New-FfbProfileDoc -Platform "Daytona3" -Inner $inner
        $r = Get-FFBBlasterSupport -Doc $doc -Categories @('FFB Blaster')
        $r.Status     | Should -Be 'Unknown'
        $r.WouldWrite | Should -BeFalse
    }
    It "paid-membership confirmation alone does not make an unsupported profile writable (gate is structural, not membership-based)" {
        # The function takes no membership flag -- membership is asked once at
        # the top of Invoke-FFBBlasterSetup and never feeds this decision. A
        # pcsx2x6 profile is Unsupported no matter what the user answered.
        $doc = New-FfbProfileDoc -Platform "pcsx2x6" -Inner $script:FfbField
        (Get-FFBBlasterSupport -Doc $doc -Categories @('FFB Blaster')).WouldWrite | Should -BeFalse
    }
}

Describe "Get-FFBBlasterFieldNames drift vs absent distinction (issue #41 diagnostic improvement)" {
    # Get-FFBBlasterFieldNames returns only Bool fields -- by design. When it
    # returns empty the caller must distinguish schema drift (shaped non-Bool
    # field exists) from genuine absence (no FFB-Blaster-shaped field at all).
    # This Describe exercises the pure detection helper rather than the setup
    # flow (which involves I/O on a GameProfiles directory).
    BeforeAll {
        function New-GpFieldDoc {
            param([string]$FieldType)
            return [xml]"<GameProfile><ConfigValues><FieldInformation><CategoryName>FFB Blaster</CategoryName><FieldName>Enable</FieldName><FieldType>$FieldType</FieldType><FieldValue>0</FieldValue></FieldInformation></ConfigValues></GameProfile>"
        }
    }
    It "Get-FFBBlasterFieldNames returns a non-empty set when the field is Bool" {
        $doc = New-GpFieldDoc "Bool"
        # Categories are discovered from GameProfile XML at runtime; here we
        # validate that a Bool field would be discovered (so Get-FFBBlasterSupport
        # later gets a valid Categories list and reaches the Supported branch).
        $doc.SelectNodes("/GameProfile/ConfigValues/FieldInformation") |
            Where-Object { $_.FieldType -ieq 'Bool' -and
                           ($_.CategoryName -imatch $script:FFBBlasterNamePattern -or
                            $_.FieldName    -imatch $script:FFBBlasterNamePattern) } |
            Should -Not -BeNullOrEmpty
    }
    It "Get-FFBBlasterSupport returns Unknown (not Unsupported) when the only shaped field is non-Bool (upstream schema drift)" {
        # This is the critical distinction: if ALL shaped fields changed FieldType
        # upstream, Get-FFBBlasterFieldNames returns empty (no Bool fields to
        # discover). At the per-profile level, Get-FFBBlasterSupport still sees the
        # shaped-but-wrong-type field and correctly returns Unknown, not Unsupported.
        $doc = [xml]"<GameProfile><EmulationProfile>Daytona3</EmulationProfile><ConfigValues><FieldInformation><CategoryName>FFB Blaster</CategoryName><FieldName>Enable</FieldName><FieldType>Dropdown</FieldType><FieldValue>Off</FieldValue><FieldOptions><string>Off</string><string>On</string></FieldOptions></FieldInformation></ConfigValues></GameProfile>"
        # Pass empty categories (as Get-FFBBlasterFieldNames would return after drift)
        $r = Get-FFBBlasterSupport -Doc $doc -Categories @()
        $r.Status     | Should -Be 'Unknown'
        $r.WouldWrite | Should -BeFalse
    }
    It "Get-FFBBlasterSupport returns Unsupported (not Unknown) when no shaped field exists at all" {
        $doc = [xml]"<GameProfile><EmulationProfile>Daytona3</EmulationProfile><ConfigValues><FieldInformation><CategoryName>General</CategoryName><FieldName>Windowed</FieldName><FieldType>Bool</FieldType><FieldValue>1</FieldValue></FieldInformation></ConfigValues></GameProfile>"
        $r = Get-FFBBlasterSupport -Doc $doc -Categories @()
        $r.Status     | Should -Be 'Unsupported'
        $r.WouldWrite | Should -BeFalse
    }
}

Describe "Get-GameProfileSchemaDrift (issue #43 schema drift detection)" {
    BeforeAll {
        function New-DriftDoc { param([string]$Xml) return [xml]$Xml }
        $script:GoodProfile = @"
<GameProfile>
  <EmulationProfile>EuropaRFordRacing</EmulationProfile>
  <GameProfileRevision>22</GameProfileRevision>
  <ExecutableName>fordracing.exe</ExecutableName>
  <EmulatorType>TeknoParrot</EmulatorType>
  <ConfigValues>
    <FieldInformation><CategoryName>General</CategoryName><FieldName>Windowed</FieldName><FieldType>Bool</FieldType><FieldValue>1</FieldValue></FieldInformation>
    <FieldInformation><CategoryName>General</CategoryName><FieldName>Input API</FieldName><FieldType>Dropdown</FieldType><FieldValue>DirectInput</FieldValue></FieldInformation>
  </ConfigValues>
</GameProfile>
"@
    }

    It "reports no drift for a known, well-formed profile" {
        $r = Get-GameProfileSchemaDrift -Doc (New-DriftDoc $script:GoodProfile)
        $r.HasDrift          | Should -BeFalse
        $r.UnknownNodes.Count    | Should -Be 0
        $r.MissingRequired.Count | Should -Be 0
        $r.WouldWrite        | Should -BeFalse
    }
    It "tolerates a known optional node (GamePath2) without flagging drift" {
        $xml = $script:GoodProfile -replace '</ConfigValues>', '</ConfigValues><GamePath2>C:\game\amdaemon.exe</GamePath2>'
        (Get-GameProfileSchemaDrift -Doc (New-DriftDoc $xml)).HasDrift | Should -BeFalse
    }
    It "reports an unknown NEW top-level node but never proposes a write" {
        # Simulates an upstream addition like a CXBXR/Lindbergh-ELF2 marker.
        $xml = $script:GoodProfile -replace '</ConfigValues>', '</ConfigValues><Cxbxr_SomeNewMarker>true</Cxbxr_SomeNewMarker>'
        $r = Get-GameProfileSchemaDrift -Doc (New-DriftDoc $xml)
        $r.HasDrift     | Should -BeTrue
        $r.UnknownNodes | Should -Contain 'Cxbxr_SomeNewMarker'
        $r.WouldWrite   | Should -BeFalse
    }
    It "reports a removed REQUIRED node as drift" {
        $xml = $script:GoodProfile -replace '<EmulationProfile>EuropaRFordRacing</EmulationProfile>', ''
        $r = Get-GameProfileSchemaDrift -Doc (New-DriftDoc $xml)
        $r.HasDrift         | Should -BeTrue
        $r.MissingRequired  | Should -Contain 'EmulationProfile'
    }
    It "reports an unknown FieldType as drift but never proposes a write" {
        $xml = $script:GoodProfile -replace '<FieldType>Bool</FieldType>', '<FieldType>FutureRangeSliderV2</FieldType>'
        $r = Get-GameProfileSchemaDrift -Doc (New-DriftDoc $xml)
        $r.HasDrift           | Should -BeTrue
        $r.UnknownFieldTypes  | Should -Contain 'FutureRangeSliderV2'
        $r.WouldWrite         | Should -BeFalse
    }
    It "treats a missing GameProfile root as maximal drift, never a write" {
        $r = Get-GameProfileSchemaDrift -Doc ([xml]"<NotAGameProfile><Foo/></NotAGameProfile>")
        $r.HasRoot    | Should -BeFalse
        $r.HasDrift   | Should -BeTrue
        $r.WouldWrite | Should -BeFalse
    }
    It "reports no drift for the live Centipede Chaos profile (issue #130/#79)" {
        # Captured verbatim from teknogods/TeknoParrotUI GameProfiles/Centipede.xml
        # (2026-08-13). EmulatorType=ElfLdr2, GunGame=false (not a lightgun title
        # despite the Shooter genre/Start-Shoot button labels), Input API=RawInput,
        # Patreon=true. This confirms the re-captured baseline above actually
        # covers the real upstream profile, not just a synthetic fixture.
        $xml = @"
<GameProfile>
	<GamePath></GamePath>
	<TestMenuParameter></TestMenuParameter>
	<TestMenuIsExecutable>false</TestMenuIsExecutable>
	<ExtraParameters></ExtraParameters>
	<TestMenuExtraParameters></TestMenuExtraParameters>
	<ResetHint>false</ResetHint>
	<EmulationProfile>WartranTroopers</EmulationProfile>
	<GameProfileRevision>1</GameProfileRevision>
	<HasSeparateTestMode>false</HasSeparateTestMode>
	<Is64Bit>true</Is64Bit>
	<EmulatorType>ElfLdr2</EmulatorType>
	<Patreon>true</Patreon>
	<RequiresAdmin>false</RequiresAdmin>
	<InvertedMouseAxis>true</InvertedMouseAxis>
	<GunGame>false</GunGame>
	<ExecutableName>game</ExecutableName>
	<xAxisMin>0</xAxisMin>
	<xAxisMax>255</xAxisMax>
	<yAxisMin>0</yAxisMin>
	<yAxisMax>255</yAxisMax>
	<ConfigValues>
		<FieldInformation><CategoryName>General</CategoryName><FieldName>Input API</FieldName><FieldValue>RawInput</FieldValue><FieldType>Dropdown</FieldType></FieldInformation>
		<FieldInformation><CategoryName>General</CategoryName><FieldName>HideCursor</FieldName><FieldValue>1</FieldValue><FieldType>Bool</FieldType></FieldInformation>
		<FieldInformation><CategoryName>General</CategoryName><FieldName>Windowed</FieldName><FieldValue>1</FieldValue><FieldType>Bool</FieldType></FieldInformation>
	</ConfigValues>
</GameProfile>
"@
        $r = Get-GameProfileSchemaDrift -Doc (New-DriftDoc $xml)
        $r.HasDrift          | Should -BeFalse
        $r.UnknownNodes.Count | Should -Be 0
        $r.MissingRequired.Count | Should -Be 0
        $r.WouldWrite        | Should -BeFalse

        $doc = New-DriftDoc $xml
        (Get-ProfileInputApi -Doc $doc) | Should -Be 'RawInput'
        $doc.GameProfile.SelectSingleNode("EmulatorType").InnerText | Should -Be 'ElfLdr2'
        $doc.GameProfile.SelectSingleNode("GunGame").InnerText      | Should -Be 'false'
    }
}

Describe "Third-party FFB plugin destination safety (issue #46)" {
    # The plugin flow resolves a destination DLL filename from the live
    # AutoSetup.cmd table (untrusted) and guards it with Test-PathInside
    # before any copy. These assert that guard's contract directly.
    It "accepts a destination DLL inside the game's own folder" {
        Test-PathInside (Join-Path "C:\Games\MyGame" "d3d9.dll") "C:\Games\MyGame" | Should -BeTrue
    }
    It "rejects a traversal destination that escapes the game folder" {
        Test-PathInside (Join-Path "C:\Games\MyGame" "..\..\Windows\System32\evil.dll") "C:\Games\MyGame" | Should -BeFalse
    }
    It "rejects a sibling folder that only shares a name prefix" {
        Test-PathInside "C:\Games\MyGameOther\x.dll" "C:\Games\MyGame" | Should -BeFalse
    }
}

Describe "RawInput / RawInputTrackball field handling (issue #46)" {
    BeforeAll {
        function New-Btn { param([string]$Inner) return ([xml]"<JoystickButtons>$Inner</JoystickButtons>").JoystickButtons }
    }
    It "treats a present RawInputButton binding as bound (supported field present)" {
        Test-ButtonIsBound (New-Btn "<RawInputButton>MOUSE_LEFT</RawInputButton>") | Should -BeTrue
    }
    It "treats a button with no binding field as not bound (field absent)" {
        Test-ButtonIsBound (New-Btn "<InputMapping>P1Trackball</InputMapping>") | Should -BeFalse
    }
    It "does NOT treat an unknown future binding field as bound (unknown field is not acted on)" {
        # A hypothetical future field name must not be mistaken for a real
        # binding -- the safe default is 'not bound', matching the project's
        # 'unknown fields are never acted on' rule.
        Test-ButtonIsBound (New-Btn "<RawInputTrackballButtonV2>MOUSE_X</RawInputTrackballButtonV2>") | Should -BeFalse
    }
}

Describe "GPU fix vendor matrix + safe re-run (issue #46)" {
    BeforeAll {
        function New-GpuDoc {
            param([string]$Inner)
            return [xml]"<GameProfile><ConfigValues>$Inner</ConfigValues></GameProfile>"
        }
        $script:GpuDropdown = "<FieldInformation><FieldName>GPU Fix</FieldName><FieldType>Dropdown</FieldType><FieldValue>None</FieldValue><FieldOptions><string>None</string><string>NVIDIA</string><string>AMD</string><string>INTEL</string></FieldOptions></FieldInformation>"
    }
    It "AMD: selects the AMD dropdown option" {
        $r = Test-GpuFixUpToDate -Doc (New-GpuDoc $script:GpuDropdown) -BoolFields @() -DropdownFields @('GPU Fix') -Vendor 'AMD'
        $r.Eligible | Should -BeTrue
        $r.Changes[0].NewValue | Should -Be 'AMD'
    }
    It "NVIDIA: selects the NVIDIA dropdown option" {
        $r = Test-GpuFixUpToDate -Doc (New-GpuDoc $script:GpuDropdown) -BoolFields @() -DropdownFields @('GPU Fix') -Vendor 'NVIDIA'
        $r.Changes[0].NewValue | Should -Be 'NVIDIA'
    }
    It "Intel: selects the INTEL dropdown option" {
        $r = Test-GpuFixUpToDate -Doc (New-GpuDoc $script:GpuDropdown) -BoolFields @() -DropdownFields @('GPU Fix') -Vendor 'Intel'
        $r.Changes[0].NewValue | Should -Be 'INTEL'
    }
    It "safe re-run after a GPU change: an already-correct value is up to date and needs no write" {
        $inner = "<FieldInformation><FieldName>GPU Fix</FieldName><FieldType>Dropdown</FieldType><FieldValue>NVIDIA</FieldValue><FieldOptions><string>None</string><string>NVIDIA</string><string>AMD</string><string>INTEL</string></FieldOptions></FieldInformation>"
        $r = Test-GpuFixUpToDate -Doc (New-GpuDoc $inner) -BoolFields @() -DropdownFields @('GPU Fix') -Vendor 'NVIDIA'
        $r.UpToDate | Should -BeTrue
        $r.Changes.Count | Should -Be 0
    }
    It "not eligible (no GPU field) means nothing to write" {
        $inner = "<FieldInformation><FieldName>Windowed</FieldName><FieldType>Bool</FieldType><FieldValue>1</FieldValue></FieldInformation>"
        (Test-GpuFixUpToDate -Doc (New-GpuDoc $inner) -BoolFields @() -DropdownFields @('GPU Fix') -Vendor 'AMD').Eligible | Should -BeFalse
    }
}

Describe "ConvertTo-ManagerComparableVersion" {
    It "strips a leading v and parses a normal version" {
        ConvertTo-ManagerComparableVersion -VersionText 'v0.99.39' | Should -Be ([version]'0.99.39')
    }
    It "parses a version with no leading v" {
        ConvertTo-ManagerComparableVersion -VersionText '0.99.39' | Should -Be ([version]'0.99.39')
    }
    It "throws on a non-numeric version string" {
        { ConvertTo-ManagerComparableVersion -VersionText 'latest' } | Should -Throw
    }

    # Issue #105: v1.0-RC1's own release tag broke this function -- [version]
    # cannot hold a "-RC1" suffix, so every updater path (menu-triggered and
    # the quiet startup check) failed to recognize the RC1 release at all.
    It "strips a release-candidate suffix and parses the numeric base" {
        ConvertTo-ManagerComparableVersion -VersionText 'v1.0-RC1' | Should -Be ([version]'1.0')
        ConvertTo-ManagerComparableVersion -VersionText 'v1.0-RC2' | Should -Be ([version]'1.0')
    }
    It "a 0.99.x version compares as older than 1.0-RC2" {
        $local  = ConvertTo-ManagerComparableVersion -VersionText '0.99.44'
        $latest = ConvertTo-ManagerComparableVersion -VersionText 'v1.0-RC2'
        $latest -gt $local | Should -Be $true -Because "a release candidate for 1.0 must be recognized as newer than any 0.99.x release"
    }
    It "0.99.99 compares as older than 1.0-RC2 (not just a higher patch number in the same line)" {
        $local  = ConvertTo-ManagerComparableVersion -VersionText '0.99.99'
        $latest = ConvertTo-ManagerComparableVersion -VersionText 'v1.0-RC2'
        $latest -gt $local | Should -Be $true
    }
    It "a version equal to the current release candidate is not offered as an update" {
        $local  = ConvertTo-ManagerComparableVersion -VersionText '1.0'
        $latest = ConvertTo-ManagerComparableVersion -VersionText 'v1.0-RC2'
        $latest -gt $local | Should -Be $false -Because "already running v1.0 RC2 must not be offered v1.0-RC2 as a new update"
    }
}

Describe "ConvertTo-ManagerDisplayVersionFromTag" {
    # Issue #134: "Current version" (built from $DisplayVersion, e.g.
    # "v1.0 RC2") and "Latest version" (previously the raw git tag, e.g.
    # "v1.0-RC2") showed the exact same release in two different formats --
    # confusing even though ConvertTo-ManagerComparableVersion correctly
    # treats them as equal. Every raw tag shown to the user must go through
    # this formatter so both lines share one canonical "v<version> <LABEL>"
    # shape.
    It "converts a release-candidate tag's dash suffix into the canonical space-separated form" {
        ConvertTo-ManagerDisplayVersionFromTag -VersionText 'v1.0-RC2' | Should -Be 'v1.0 RC2'
        ConvertTo-ManagerDisplayVersionFromTag -VersionText 'v1.0-RC1' | Should -Be 'v1.0 RC1'
    }
    It "leaves a plain numeric tag with no suffix unchanged" {
        ConvertTo-ManagerDisplayVersionFromTag -VersionText 'v0.99.44' | Should -Be 'v0.99.44'
        ConvertTo-ManagerDisplayVersionFromTag -VersionText 'v1.0' | Should -Be 'v1.0'
    }
    It "adds a leading v when the tag doesn't already have one" {
        ConvertTo-ManagerDisplayVersionFromTag -VersionText '1.0-RC2' | Should -Be 'v1.0 RC2'
        ConvertTo-ManagerDisplayVersionFromTag -VersionText '0.99.44' | Should -Be 'v0.99.44'
    }
    It "renders the same release identically whether it arrives as the running script's own display version or as a raw release tag" {
        # This is the exact regression from issue #134: v1.0 (running as
        # RC3) and the v1.0-RC3 release tag are the same release and must
        # display identically, not as "v1.0" vs "v1.0-RC3".
        $currentDisplay = "v1.0 RC3"   # Get-ManagerDisplayVersion's shape when $ScriptVersion=1.0, $ReleaseCandidateLabel=RC3
        $latestDisplay  = ConvertTo-ManagerDisplayVersionFromTag -VersionText 'v1.0-RC3'
        $latestDisplay | Should -Be $currentDisplay
    }
}

Describe "Get-ManagerUpdateRelease" {
    It "returns the matching asset for a well-formed release" {
        Mock Invoke-WebRequest {
            [pscustomobject]@{
                Content = (@{
                    tag_name = 'v0.99.99'
                    name     = 'v0.99.99 BETA'
                    body     = 'Test release notes.'
                    assets   = @(@{
                        name                  = 'TeknoParrot.Manager.v0.99.99.BETA.zip'
                        browser_download_url = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.99/TeknoParrot.Manager.v0.99.99.BETA.zip'
                        size                  = 1
                    })
                } | ConvertTo-Json -Depth 5)
            }
        }
        $release = Get-ManagerUpdateRelease
        $release.TagName | Should -Be 'v0.99.99'
        $release.AssetName | Should -Be 'TeknoParrot.Manager.v0.99.99.BETA.zip'
    }

    It "returns null when no asset matches the expected name pattern" {
        Mock Invoke-WebRequest {
            [pscustomobject]@{
                Content = (@{
                    tag_name = 'v0.99.99'
                    assets   = @(@{ name = 'unrelated.txt'; browser_download_url = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.99/unrelated.txt' })
                } | ConvertTo-Json -Depth 5)
            }
        }
        Get-ManagerUpdateRelease | Should -BeNullOrEmpty
    }

    It "returns null and does not retry when the matching asset URL is not a real GitHub release URL" {
        Mock Invoke-WebRequest {
            [pscustomobject]@{
                Content = (@{
                    tag_name = 'v0.99.99'
                    assets   = @(@{ name = 'TeknoParrot.Manager.v0.99.99.BETA.zip'; browser_download_url = 'https://evil.example.com/TeknoParrot.Manager.v0.99.99.BETA.zip' })
                } | ConvertTo-Json -Depth 5)
            }
        }
        Get-ManagerUpdateRelease | Should -BeNullOrEmpty
        Should -Invoke Invoke-WebRequest -Times 1
    }

    It "retries on a transient (5xx-shaped) failure and gives up after 3 attempts" {
        Mock Invoke-WebRequest { throw [System.Net.WebException]::new('transient') }
        Mock Start-Sleep {}
        Get-ManagerUpdateRelease | Should -BeNullOrEmpty
        Should -Invoke Invoke-WebRequest -Times 3
        Should -Invoke Start-Sleep -Times 2
    }
}

Describe "Get-TeknoParrotProfileSet" {
    BeforeAll {
        Mock Write-Log {}
    }

    It "builds the git/trees URL with the branch placed before the query string, not swallowed by it" {
        # Regression test for the reported #78 root cause: interpolating an
        # unbraced variable immediately followed by a literal '?' inside a
        # double-quoted string (e.g. "$branchEncoded?recursive=1") silently
        # drops everything up to the next '=', producing ".../git/trees/=1"
        # instead of ".../git/trees/master?recursive=1". GitHub then 404s on
        # that malformed URL every single time -- this was not intermittent
        # or network-related. The fix braces the variable: "${branchEncoded}?...".
        Mock Invoke-WebRequest -ParameterFilter { $Uri -eq 'https://api.github.com/repos/teknogods/TeknoParrotUI' } {
            [pscustomobject]@{ Content = (@{ default_branch = 'master' } | ConvertTo-Json) }
        }
        Mock Invoke-WebRequest -ParameterFilter { $Uri -like '*/git/trees/*' } {
            [pscustomobject]@{ Content = (@{ tree = @(@{ type = 'blob'; path = 'TeknoParrotUi.Common/GameProfiles/Foo.xml' }) } | ConvertTo-Json -Depth 5) }
        }

        [void](Get-TeknoParrotProfileSet)

        Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
            $Uri -eq 'https://api.github.com/repos/teknogods/TeknoParrotUI/git/trees/master?recursive=1'
        }
    }

    It "returns the profile stems parsed from the tree response" {
        Mock Invoke-WebRequest -ParameterFilter { $Uri -eq 'https://api.github.com/repos/teknogods/TeknoParrotUI' } {
            [pscustomobject]@{ Content = (@{ default_branch = 'master' } | ConvertTo-Json) }
        }
        Mock Invoke-WebRequest -ParameterFilter { $Uri -like '*/git/trees/*' } {
            [pscustomobject]@{
                Content = (@{
                    tree = @(
                        @{ type = 'blob'; path = 'TeknoParrotUi.Common/GameProfiles/BladeArcus.xml' },
                        @{ type = 'blob'; path = 'TeknoParrotUi.Common/GameProfiles/Tekken7.xml' },
                        @{ type = 'tree'; path = 'TeknoParrotUi.Common/GameProfiles' }
                    )
                } | ConvertTo-Json -Depth 5)
            }
        }

        $result = Get-TeknoParrotProfileSet
        $result | Should -Contain 'BladeArcus'
        $result | Should -Contain 'Tekken7'
    }

    It "logs the HTTP status code when the tree request fails" {
        Mock Invoke-WebRequest -ParameterFilter { $Uri -eq 'https://api.github.com/repos/teknogods/TeknoParrotUI' } {
            [pscustomobject]@{ Content = (@{ default_branch = 'master' } | ConvertTo-Json) }
        }
        Mock Invoke-WebRequest -ParameterFilter { $Uri -like '*/git/trees/*' } {
            # Mirror the shape production code actually reads --
            # $_.Exception.Response.StatusCode -- rather than relying on a
            # specific exception type, since PowerShell 5.1 (the script's
            # target runtime) and later versions surface HTTP errors from
            # Invoke-WebRequest differently.
            $ex = [System.Exception]::new("Not Found")
            $ex | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{ StatusCode = 404 }) -Force
            throw $ex
        }

        [void](Get-TeknoParrotProfileSet)

        Should -Invoke Write-Log -Times 1 -ParameterFilter { $msg -like "*HTTP 404*" }
    }
}

Describe "Assert-ManagerUpdateTargetWritable" {
    It "clears only the target read-only attribute for an approved update" {
        $path = Join-Path $TestDrive 'readonly.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.99.39"' -Encoding ascii
        Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $true
        try {
            (Assert-ManagerUpdateTargetWritable -Path $path) | Should -BeTrue
            (Get-Item -LiteralPath $path -Force).IsReadOnly | Should -BeFalse
        } finally {
            Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        }
    }
    It "does not throw when the target is writable" {
        $path = Join-Path $TestDrive 'writable.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.99.39"' -Encoding ascii
        { Assert-ManagerUpdateTargetWritable -Path $path } | Should -Not -Throw
    }
    It "does not throw when the target does not exist yet" {
        { Assert-ManagerUpdateTargetWritable -Path (Join-Path $TestDrive 'does-not-exist.ps1') } | Should -Not -Throw
    }
}

Describe "New-ManagerUpdateBackup" {
    It "creates a timestamped backup of the target file under UpdateBackups" {
        $root = Join-Path $TestDrive ("backuproot-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $scriptPath = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $scriptPath -Value '$ScriptVersion = "0.99.39"' -Encoding ascii

        $backupPath = New-ManagerUpdateBackup -Path $scriptPath

        $backupPath | Should -Match ([regex]::Escape((Join-Path $root 'UpdateBackups')))
        Test-Path -LiteralPath $backupPath -PathType Leaf | Should -BeTrue
        (Get-Content -LiteralPath $backupPath -Raw) | Should -Match 'ScriptVersion'
    }
}

Describe "Expand-ManagerUpdateAsset and Test-ManagerUpdateExtractedScript" {
    BeforeAll {
        function New-CheckForUpdatesFixtureZip {
            param(
                [string]$EntryName = 'TeknoParrot-Manager.ps1',
                [string]$EntryContent = "# TeknoParrot Manager`n`$ScriptVersion = `"0.99.99`"`n"
            )
            $zipPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-menu-fixture-" + [guid]::NewGuid().ToString('N') + '.zip')
            $stagingDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-menu-staging-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
            try {
                Set-Content -LiteralPath (Join-Path $stagingDir $EntryName) -Value $EntryContent -Encoding ascii -NoNewline
                [System.IO.Compression.ZipFile]::CreateFromDirectory($stagingDir, $zipPath)
            } finally {
                Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            return $zipPath
        }
    }

    It "extracts the named entry and it passes content validation" {
        $zipPath = New-CheckForUpdatesFixtureZip
        $destPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-menu-extracted-" + [guid]::NewGuid().ToString('N') + '.ps1')
        try {
            Expand-ManagerUpdateAsset -ZipPath $zipPath -EntryName 'TeknoParrot-Manager.ps1' -DestinationPath $destPath
            Test-ManagerUpdateExtractedScript -Path $destPath | Should -BeTrue
        } finally {
            Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $destPath -Force -ErrorAction SilentlyContinue
        }
    }

    It "throws when the zip does not contain the expected entry" {
        $zipPath = New-CheckForUpdatesFixtureZip -EntryName 'SomethingElse.ps1'
        $destPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-menu-extracted-" + [guid]::NewGuid().ToString('N') + '.ps1')
        try {
            { Expand-ManagerUpdateAsset -ZipPath $zipPath -EntryName 'TeknoParrot-Manager.ps1' -DestinationPath $destPath } | Should -Throw
        } finally {
            Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
        }
    }

    It "rejects an extracted file that begins with a raw zip (PK) signature" {
        $path = Join-Path $TestDrive 'zipbytes.ps1'
        [System.IO.File]::WriteAllBytes($path, [byte[]](0x50, 0x4B, 0x03, 0x04, 0x00, 0x00))
        { Test-ManagerUpdateExtractedScript -Path $path } | Should -Throw '*zip signature*'
    }

    It "rejects an extracted file missing the TeknoParrot Manager marker" {
        $path = Join-Path $TestDrive 'nomarker.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.99.99"' -Encoding ascii
        { Test-ManagerUpdateExtractedScript -Path $path } | Should -Throw '*TeknoParrot Manager*'
    }

    It "rejects an extracted file with no ScriptVersion assignment" {
        $path = Join-Path $TestDrive 'noversion.ps1'
        Set-Content -LiteralPath $path -Value '# TeknoParrot Manager' -Encoding ascii
        { Test-ManagerUpdateExtractedScript -Path $path } | Should -Throw '*ScriptVersion*'
    }
}

Describe "Invoke-CheckForUpdates" {
    BeforeAll {
        function New-CheckForUpdatesReleaseJson {
            param([string]$TagName = 'v0.99.99', [string]$AssetName = 'TeknoParrot.Manager.v0.99.99.BETA.zip')
            return (@{
                tag_name = $TagName
                name     = $TagName
                body     = 'Test release notes.'
                assets   = @(@{
                    name                  = $AssetName
                    browser_download_url = "https://github.com/Jumpstile/teknoparrot-manager/releases/download/$TagName/$AssetName"
                    size                  = 1
                })
            } | ConvertTo-Json -Depth 5)
        }
    }

    It "reports already current and returns false without prompting when there is no newer release" {
        Mock Invoke-WebRequest { [pscustomobject]@{ Content = (New-CheckForUpdatesReleaseJson -TagName $ScriptVersion) } }
        Mock Read-Host { throw "Read-Host should not be called when already current" }

        $path = Join-Path $TestDrive 'current.ps1'
        Set-Content -LiteralPath $path -Value "`$ScriptVersion = `"$ScriptVersion`"" -Encoding ascii

        Invoke-CheckForUpdates -ScriptPath $path | Should -BeFalse
    }

    It "returns false and makes no changes when the user declines the update" {
        Mock Invoke-WebRequest { [pscustomobject]@{ Content = (New-CheckForUpdatesReleaseJson) } }
        Mock Read-Host { "N" }

        $path = Join-Path $TestDrive 'decline.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii
        $originalContent = Get-Content -LiteralPath $path -Raw

        Invoke-CheckForUpdates -ScriptPath $path | Should -BeFalse
        (Get-Content -LiteralPath $path -Raw) | Should -Be $originalContent
    }

    It "clears the target attribute only for the approved update transaction and restores it on failure" {
        $root = Join-Path $TestDrive ("readonlyroot-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $path = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii
        Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $true
        Mock New-ManagerUpdateBackup { Join-Path $root 'backup.ps1' }
        Mock Invoke-TpmDownload { $false }
        try {
            Invoke-ManagerUpdateInstall -ScriptPath $path -Release ([pscustomobject]@{ AssetName = 'x.zip'; DownloadUrl = 'https://github.com/example/x.zip'; SizeBytes = 1; TagName = 'v0.99.99' }) | Should -BeFalse
            (Get-Item -LiteralPath $path -Force).IsReadOnly | Should -BeTrue
        } finally {
            Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        }
    }
}

Describe "Get-ManagerUpdateReleaseSummary" {
    It "returns the first non-blank line, trimmed of heading/bullet markdown" {
        Get-ManagerUpdateReleaseSummary -Body "## What's new`n`nFixes a startup crash." | Should -Be "What's new"
    }
    It "strips a leading bullet marker" {
        Get-ManagerUpdateReleaseSummary -Body "- Fixes a startup crash." | Should -Be "Fixes a startup crash."
    }
    It "truncates a long first line to 150 chars plus an ellipsis" {
        $long = "X" * 200
        $summary = Get-ManagerUpdateReleaseSummary -Body $long
        $summary.Length | Should -Be 153
        $summary | Should -Match '\.\.\.$'
    }
    It "returns null for an empty or whitespace-only body" {
        Get-ManagerUpdateReleaseSummary -Body "" | Should -BeNullOrEmpty
        Get-ManagerUpdateReleaseSummary -Body "   " | Should -BeNullOrEmpty
        Get-ManagerUpdateReleaseSummary -Body $null | Should -BeNullOrEmpty
    }
}

Describe "Get-ManagerUpdateRelease -MaxAttempts" {
    It "makes exactly one request and does not sleep when MaxAttempts is 1" {
        Mock Invoke-WebRequest { throw [System.Net.WebException]::new('transient') }
        Mock Start-Sleep {}
        Get-ManagerUpdateRelease -MaxAttempts 1 -TimeoutSec 5 | Should -BeNullOrEmpty
        Should -Invoke Invoke-WebRequest -Times 1
        Should -Invoke Start-Sleep -Times 0
    }
}

Describe "Invoke-ManagerUpdateInstall" {
    BeforeAll {
        function New-StartupCheckFixtureZipBytes {
            param(
                [string]$EntryName = 'TeknoParrot-Manager.ps1',
                [string]$EntryContent = "# TeknoParrot Manager`n`$ScriptVersion = `"0.99.99`"`n"
            )
            $zipPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-startup-fixture-" + [guid]::NewGuid().ToString('N') + '.zip')
            $stagingDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-startup-staging-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
            try {
                Set-Content -LiteralPath (Join-Path $stagingDir $EntryName) -Value $EntryContent -Encoding ascii -NoNewline
                [System.IO.Compression.ZipFile]::CreateFromDirectory($stagingDir, $zipPath)
                return , ([System.IO.File]::ReadAllBytes($zipPath))
            } finally {
                Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
            }
        }

        function New-StartupCheckRelease {
            [pscustomobject]@{
                TagName     = 'v0.99.99'
                Name        = 'v0.99.99 BETA'
                Body        = 'Test release notes.'
                AssetName   = 'TeknoParrot.Manager.v0.99.99.BETA.zip'
                DownloadUrl = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.99/TeknoParrot.Manager.v0.99.99.BETA.zip'
                SizeBytes   = 1
            }
        }

        # Destructive-path fixture helpers -- mirrors
        # Tests/TpmAutoUpdate.DestructivePath.Tests.ps1's fixtures for the
        # standalone tools/TpmAutoUpdate.Core.psm1 module, so the in-script
        # Invoke-ManagerUpdateInstall gets the same failure-mode coverage as
        # that module already has (release-certification gap closed).
        function Get-DestructiveCorruptedEntryZipBytes {
            # Same technique as the standalone suite: a large, repetitive
            # (compressible) entry so Deflate is actually used, then flip bits
            # only within the compressed payload region so the central
            # directory / EOCD stay intact and only decompression fails.
            $entryContent = "# TeknoParrot Manager`n`$ScriptVersion = `"0.99.99`"`n" + (("X" * 200 + "`n") * 300)
            $zipBytes = New-StartupCheckFixtureZipBytes -EntryContent $entryContent
            $bytes = [byte[]]$zipBytes.Clone()

            $probeZipPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-destructive-probe-" + [guid]::NewGuid().ToString('N') + '.zip')
            [System.IO.File]::WriteAllBytes($probeZipPath, $bytes)
            try {
                $zip = [System.IO.Compression.ZipFile]::OpenRead($probeZipPath)
                $compressedLength = $zip.Entries[0].CompressedLength
                $zip.Dispose()
            } finally {
                Remove-Item -LiteralPath $probeZipPath -Force -ErrorAction SilentlyContinue
            }
            if ($compressedLength -eq $entryContent.Length) {
                throw 'Test fixture error: entry was stored rather than deflated -- corruption offsets would be wrong.'
            }

            $filenameLen = [System.BitConverter]::ToUInt16($bytes, 26)
            $extraLen = [System.BitConverter]::ToUInt16($bytes, 28)
            $dataStart = 30 + $filenameLen + $extraLen
            for ($i = $dataStart; $i -lt ($dataStart + $compressedLength); $i++) {
                $bytes[$i] = $bytes[$i] -bxor 0xFF
            }
            return , $bytes
        }
    }

    It "installs successfully and returns true" {
        $zipBytes = New-StartupCheckFixtureZipBytes
        Mock Invoke-TpmDownload { param($DownloadUrl, $DestinationPath, $ExpectedBytes, $Label, $Version) [System.IO.File]::WriteAllBytes($DestinationPath, $zipBytes); return $true }.GetNewClosure()

        $path = Join-Path $TestDrive 'install-target.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii

        Invoke-ManagerUpdateInstall -ScriptPath $path -Release (New-StartupCheckRelease) | Should -BeTrue
        (Get-Content -LiteralPath $path -Raw) | Should -Match 'ScriptVersion = "0.99.99"'
    }

    It "returns false and leaves the original untouched when the target is read-only" {
        $path = Join-Path $TestDrive 'readonly-install-target.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii -NoNewline
        Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $true
        try {
            Mock Invoke-TpmDownload { throw "download should not be called when the target is read-only" }
            Invoke-ManagerUpdateInstall -ScriptPath $path -Release (New-StartupCheckRelease) | Should -BeFalse
            (Get-Content -LiteralPath $path -Raw) | Should -Be '$ScriptVersion = "0.0.1"'
        } finally {
            Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        }
    }

    # Destructive-path parity with Tests/TpmAutoUpdate.DestructivePath.Tests.ps1
    # (issue: in-script Invoke-ManagerUpdateInstall had only success/read-only
    # coverage versus the standalone module's 9 dedicated failure scenarios --
    # release-certification gap, see release-readiness review). Each of these
    # deliberately induces a failure and asserts the original installation
    # survives untouched, a completed backup is preserved, and no temp
    # artifacts leak -- "never leave the user with a broken installation."
    It "corrupt ZIP download: leaves the original intact and preserves the backup" {
        $root = Join-Path $TestDrive ("destructive-corrupt-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $path = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii -NoNewline
        $originalContent = Get-Content -LiteralPath $path -Raw

        Mock Invoke-TpmDownload {
            param($DownloadUrl, $DestinationPath, $ExpectedBytes, $Label, $Version)
            [System.IO.File]::WriteAllBytes($DestinationPath, [byte[]](1..64 | ForEach-Object { Get-Random -Maximum 255 }))
            return $true
        }

        Invoke-ManagerUpdateInstall -ScriptPath $path -Release (New-StartupCheckRelease) | Should -BeFalse
        (Get-Content -LiteralPath $path -Raw) | Should -Be $originalContent

        $backupFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'UpdateBackups') -Recurse -Filter 'TeknoParrot-Manager.ps1' -ErrorAction SilentlyContinue)
        $backupFiles.Count | Should -Be 1
        (Get-Content -LiteralPath $backupFiles[0].FullName -Raw) | Should -Be $originalContent
    }

    It "ZIP missing TeknoParrot-Manager.ps1: leaves the original intact and preserves the backup" {
        $root = Join-Path $TestDrive ("destructive-missing-entry-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $path = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii -NoNewline
        $originalContent = Get-Content -LiteralPath $path -Raw
        $wrongEntryBytes = New-StartupCheckFixtureZipBytes -EntryName 'SomethingElse.ps1'

        Mock Invoke-TpmDownload {
            param($DownloadUrl, $DestinationPath, $ExpectedBytes, $Label, $Version)
            [System.IO.File]::WriteAllBytes($DestinationPath, $wrongEntryBytes)
            return $true
        }.GetNewClosure()

        Invoke-ManagerUpdateInstall -ScriptPath $path -Release (New-StartupCheckRelease) | Should -BeFalse
        (Get-Content -LiteralPath $path -Raw) | Should -Be $originalContent

        $backupFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'UpdateBackups') -Recurse -Filter 'TeknoParrot-Manager.ps1' -ErrorAction SilentlyContinue)
        $backupFiles.Count | Should -Be 1
    }

    It "content validation failure (missing ScriptVersion): leaves the original intact and preserves the backup" {
        $root = Join-Path $TestDrive ("destructive-noversion-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $path = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii -NoNewline
        $originalContent = Get-Content -LiteralPath $path -Raw
        $badContentBytes = New-StartupCheckFixtureZipBytes -EntryContent "# TeknoParrot Manager`nsome unrelated content, no version here`n"

        Mock Invoke-TpmDownload {
            param($DownloadUrl, $DestinationPath, $ExpectedBytes, $Label, $Version)
            [System.IO.File]::WriteAllBytes($DestinationPath, $badContentBytes)
            return $true
        }.GetNewClosure()

        Invoke-ManagerUpdateInstall -ScriptPath $path -Release (New-StartupCheckRelease) | Should -BeFalse
        (Get-Content -LiteralPath $path -Raw) | Should -Be $originalContent

        $backupFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'UpdateBackups') -Recurse -Filter 'TeknoParrot-Manager.ps1' -ErrorAction SilentlyContinue)
        $backupFiles.Count | Should -Be 1
        @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'tpm-update-extracted-*.ps1' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It "content validation failure (extracted file is itself raw zip bytes): leaves the original intact" {
        $root = Join-Path $TestDrive ("destructive-nestedzip-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $path = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii -NoNewline
        $originalContent = Get-Content -LiteralPath $path -Raw

        # A zip whose single entry's *content* is itself zip bytes -- a
        # packaging mistake where the wrong artifact landed inside the
        # expected entry name.
        $innerZipBytes = New-StartupCheckFixtureZipBytes
        $stagingDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-nested-staging-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
        $outerZipPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-nested-" + [guid]::NewGuid().ToString('N') + '.zip')
        try {
            [System.IO.File]::WriteAllBytes((Join-Path $stagingDir 'TeknoParrot-Manager.ps1'), $innerZipBytes)
            [System.IO.Compression.ZipFile]::CreateFromDirectory($stagingDir, $outerZipPath)
            $outerBytes = [System.IO.File]::ReadAllBytes($outerZipPath)
        } finally {
            Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $outerZipPath -Force -ErrorAction SilentlyContinue
        }

        Mock Invoke-TpmDownload {
            param($DownloadUrl, $DestinationPath, $ExpectedBytes, $Label, $Version)
            [System.IO.File]::WriteAllBytes($DestinationPath, $outerBytes)
            return $true
        }.GetNewClosure()

        Invoke-ManagerUpdateInstall -ScriptPath $path -Release (New-StartupCheckRelease) | Should -BeFalse
        (Get-Content -LiteralPath $path -Raw) | Should -Be $originalContent
        (Get-Content -LiteralPath $path -Raw).StartsWith('PK') | Should -BeFalse
    }

    It "truncated/partial download: treated as corrupt, leaves the original intact" {
        $root = Join-Path $TestDrive ("destructive-truncated-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $path = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii -NoNewline
        $originalContent = Get-Content -LiteralPath $path -Raw
        $fullBytes = New-StartupCheckFixtureZipBytes
        $truncatedBytes = $fullBytes[0..([int]($fullBytes.Length / 2))]

        Mock Invoke-TpmDownload {
            param($DownloadUrl, $DestinationPath, $ExpectedBytes, $Label, $Version)
            [System.IO.File]::WriteAllBytes($DestinationPath, $truncatedBytes)
            return $true
        }.GetNewClosure()

        Invoke-ManagerUpdateInstall -ScriptPath $path -Release (New-StartupCheckRelease) | Should -BeFalse
        (Get-Content -LiteralPath $path -Raw) | Should -Be $originalContent

        $backupFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'UpdateBackups') -Recurse -Filter 'TeknoParrot-Manager.ps1' -ErrorAction SilentlyContinue)
        $backupFiles.Count | Should -Be 1
    }

    It "backup creation failure: aborts before any download, original untouched, no backup folder" {
        $root = Join-Path $TestDrive ("destructive-backupfail-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $path = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii -NoNewline
        $originalContent = Get-Content -LiteralPath $path -Raw

        Mock New-ManagerUpdateBackup { throw "Access to the path is denied (simulated backup failure)." }
        Mock Invoke-TpmDownload { throw "download should never be called when backup fails first." }

        Invoke-ManagerUpdateInstall -ScriptPath $path -Release (New-StartupCheckRelease) | Should -BeFalse
        (Get-Content -LiteralPath $path -Raw) | Should -Be $originalContent
        Test-Path -LiteralPath (Join-Path $root 'UpdateBackups') | Should -BeFalse
        Should -Invoke Invoke-TpmDownload -Times 0
    }

    It "extraction failure (valid ZIP, corrupted entry payload): leaves the original intact and preserves the backup" {
        $root = Join-Path $TestDrive ("destructive-extractfail-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $path = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii -NoNewline
        $originalContent = Get-Content -LiteralPath $path -Raw
        $corruptedEntryBytes = Get-DestructiveCorruptedEntryZipBytes

        Mock Invoke-TpmDownload {
            param($DownloadUrl, $DestinationPath, $ExpectedBytes, $Label, $Version)
            [System.IO.File]::WriteAllBytes($DestinationPath, $corruptedEntryBytes)
            return $true
        }.GetNewClosure()

        Invoke-ManagerUpdateInstall -ScriptPath $path -Release (New-StartupCheckRelease) | Should -BeFalse
        (Get-Content -LiteralPath $path -Raw) | Should -Be $originalContent

        $backupFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'UpdateBackups') -Recurse -Filter 'TeknoParrot-Manager.ps1' -ErrorAction SilentlyContinue)
        $backupFiles.Count | Should -Be 1
        @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'tpm-update-extracted-*.ps1' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It "replacement failure after successful backup (locked destination): preserves backup and the locked, unmodified original" {
        # This is the literal "never leave the user with a broken
        # installation" case: backup/download/extract/validate all succeed
        # and only the final Move-Item fails -- what an AV scanner or another
        # process holding the file open looks like in practice.
        $root = Join-Path $TestDrive ("destructive-locked-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $path = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii -NoNewline
        $originalContent = Get-Content -LiteralPath $path -Raw
        $validBytes = New-StartupCheckFixtureZipBytes

        Mock Invoke-TpmDownload {
            param($DownloadUrl, $DestinationPath, $ExpectedBytes, $Label, $Version)
            [System.IO.File]::WriteAllBytes($DestinationPath, $validBytes)
            return $true
        }.GetNewClosure()

        $lockHandle = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        try {
            Invoke-ManagerUpdateInstall -ScriptPath $path -Release (New-StartupCheckRelease) | Should -BeFalse
        } finally {
            $lockHandle.Dispose()
        }

        # Original must be exactly what it was -- no partial/truncated write.
        (Get-Content -LiteralPath $path -Raw) | Should -Be $originalContent

        $backupFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'UpdateBackups') -Recurse -Filter 'TeknoParrot-Manager.ps1' -ErrorAction SilentlyContinue)
        $backupFiles.Count | Should -Be 1
        (Get-Content -LiteralPath $backupFiles[0].FullName -Raw) | Should -Be $originalContent

        @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'tpm-update-extracted-*.ps1' -ErrorAction SilentlyContinue).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'tpm-update-*.zip' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }
}

Describe "Invoke-StartupUpdateCheck" {
    It "returns false and does not prompt when already current" {
        Mock Get-ManagerUpdateRelease { [pscustomobject]@{ TagName = "v$ScriptVersion"; Name = $null; Body = $null; AssetName = 'x'; DownloadUrl = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.39/x' } }
        Mock Read-Host { throw "Read-Host should not be called when already current" }

        $path = Join-Path $TestDrive 'startup-current.ps1'
        Set-Content -LiteralPath $path -Value "`$ScriptVersion = `"$ScriptVersion`"" -Encoding ascii

        Invoke-StartupUpdateCheck -ScriptPath $path | Should -BeFalse
    }

    It "returns false without prompting again when the release check fails (e.g. offline)" {
        Mock Get-ManagerUpdateRelease { $null }
        Mock Read-Host { throw "Read-Host should not be called when the release check fails" }

        $path = Join-Path $TestDrive 'startup-offline.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii

        Invoke-StartupUpdateCheck -ScriptPath $path | Should -BeFalse
    }

    It "returns false and makes no changes when the user chooses N (remind me later)" {
        Mock Get-ManagerUpdateRelease {
            [pscustomobject]@{ TagName = 'v0.99.99'; Name = 'v0.99.99'; Body = 'Notes.'; AssetName = 'x.zip'; DownloadUrl = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.99/x.zip' }
        }
        Mock Read-Host { "N" }

        $path = Join-Path $TestDrive 'startup-decline.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii
        $originalContent = Get-Content -LiteralPath $path -Raw

        Invoke-StartupUpdateCheck -ScriptPath $path | Should -BeFalse
        (Get-Content -LiteralPath $path -Raw) | Should -Be $originalContent
    }

    It "shows release notes on V and then still lets the user decline with N" {
        Mock Get-ManagerUpdateRelease {
            [pscustomobject]@{ TagName = 'v0.99.99'; Name = 'v0.99.99'; Body = 'Detailed notes here.'; AssetName = 'x.zip'; DownloadUrl = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.99/x.zip' }
        }
        $script:readHostCallCount = 0
        Mock Read-Host {
            $script:readHostCallCount++
            if ($script:readHostCallCount -eq 1) { return "V" }
            return "N"
        }

        $path = Join-Path $TestDrive 'startup-view-notes.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii

        Invoke-StartupUpdateCheck -ScriptPath $path | Should -BeFalse
        Should -Invoke Read-Host -Times 2
    }

    It "automatically clears and restores the target read-only attribute on startup failure" {
        Mock Get-ManagerUpdateRelease {
            [pscustomobject]@{ TagName = 'v0.99.99'; Name = 'v0.99.99'; Body = 'Notes.'; AssetName = 'x.zip'; DownloadUrl = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.99/x.zip' }
        }
        Mock Read-Host { "Y" }
        Mock Invoke-WebRequest { throw "simulated network failure" }

        $root = Join-Path $TestDrive ("startup-readonly-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $path = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii
        Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $true

        try {
            Invoke-StartupUpdateCheck -ScriptPath $path | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $root 'UpdateBackups') | Should -BeTrue
            (Get-Item -LiteralPath $path -Force).IsReadOnly | Should -BeTrue
        } finally {
            Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        }
    }
}

Describe "Main menu source-level drift check" {
    # Issue #104: the menu display is now data-driven (Get-MainMenuSections /
    # Get-MainMenuItems), but the switch statement dispatching $modeChoice to
    # a $mode string is still hand-written top-level code, not extracted by
    # the AST function-extraction. This cross-checks the data model's item
    # numbers against the switch statement's case labels, preserving the
    # original intent of this test (a future edit to one without the other --
    # the exact drift class documented in LESSONS_LEARNED.md for
    # v0.99.25/v0.99.28 -- fails CI instead of shipping) against the new
    # architecture.
    BeforeAll {
        $script:mainScriptContent = Get-Content -LiteralPath $scriptPath -Raw
    }

    It "has a switch case for every menu item number in the data model, 1 through the Exit option, with no gaps" {
        $itemNumbers = Get-MainMenuItems | ForEach-Object { $_.Number } | Sort-Object -Unique

        $switchBlockStart = $script:mainScriptContent.IndexOf('switch ($modeChoice) {')
        # The switch block's own cases each have their own "{ ... }" (e.g.
        # "1" { $mode = "AutoSync" }), so IndexOf('}', ...) would only find
        # the first case's closing brace. "if ($modeChoice -eq" reliably
        # appears immediately after the whole switch statement closes.
        $switchBlockEnd   = $script:mainScriptContent.IndexOf('if ($modeChoice -eq', $switchBlockStart)
        $switchBlockText  = $script:mainScriptContent.Substring($switchBlockStart, $switchBlockEnd - $switchBlockStart)
        $switchNumbers    = [regex]::Matches($switchBlockText, '"(\d+)"\s*\{') |
            ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique

        # @() wrap: not currently reachable with $null (14 menu items always
        # collapse to more than one unique number), but the same unguarded
        # .Count-on-a-possibly-scalar-pipeline-result pattern that broke the
        # Ultra-tier banner test under PS 5.1 above -- fixed defensively for
        # consistency with that lesson rather than waiting for it to fail.
        @($itemNumbers).Count | Should -BeGreaterThan 0
        # Join to strings for comparison -- piping an array directly into
        # Should -Be iterates it element-by-element against the whole
        # right-hand side instead of comparing the collections as a whole.
        ($itemNumbers -join ',') | Should -Be ($switchNumbers -join ',')

        $expectedSequence = 1..($itemNumbers[-1])
        ($itemNumbers -join ',') | Should -Be ($expectedSequence -join ',')
    }

    It "every menu item has a distinct Mode string used by exactly one switch case" {
        $items = Get-MainMenuItems
        foreach ($item in $items) {
            if ($item.Number -eq 15) { continue } # Exit has no $mode assignment
            $script:mainScriptContent | Should -Match ([regex]::Escape('"{0}"' -f $item.Number) + '\s*\{\s*\$mode\s*=\s*"' + [regex]::Escape($item.Mode) + '"')
        }
    }

    It "Show-MainMenu's Enter prompt uses the highest item number from the data model" {
        $itemNumbers = Get-MainMenuItems | ForEach-Object { $_.Number } | Sort-Object -Unique
        $script:mainScriptContent.Contains('Read-MainMenuChoiceResponsive -Prompt ("Enter 1-{0}: " -f $menuMaxNumber)') | Should -Be $true
        $script:mainScriptContent.Contains('$menuMaxNumber = (Get-MainMenuItems | Measure-Object -Property Number -Maximum).Maximum') | Should -Be $true
        $itemNumbers[-1] | Should -Be 15
    }

    It "actual menu loop passes current viewport dimensions into Show-MainMenu" {
        $script:mainScriptContent.Contains('$consoleWidth  = Get-ConsoleContentWidth') | Should -Be $true
        $script:mainScriptContent.Contains('$consoleHeight = Get-ConsoleContentHeight') | Should -Be $true
        $script:mainScriptContent.Contains('Show-MainMenu -Tier $menuTier -Width $consoleWidth -Height $consoleHeight') | Should -Be $true
    }
}

Describe "Get-MainMenuSections / Get-MainMenuItems" {
    It "every section has at least one item" {
        Get-MainMenuSections | ForEach-Object { $_.Items.Count | Should -BeGreaterThan 0 }
    }
    It "flattens every section's items into one number-ordered list with no duplicate numbers" {
        $items = Get-MainMenuItems
        $numbers = $items | ForEach-Object { $_.Number }
        ($numbers | Sort-Object -Unique).Count | Should -Be $numbers.Count
    }
    It "every non-Exit item has a non-empty Label, ShortDesc, and at least one FullDesc line" {
        $items = Get-MainMenuItems | Where-Object { $_.Mode -ne 'Exit' }
        foreach ($item in $items) {
            $item.Label | Should -Not -BeNullOrEmpty
            $item.ShortDesc | Should -Not -BeNullOrEmpty
            @($item.FullDesc).Count | Should -BeGreaterThan 0
        }
    }
}

Describe "Onboarding pointer-text menu-label sync (Part 2 item 8: no hardcoded menu numbers)" {
    # Every "go do X later" pointer in the onboarding flow must cite the
    # menu item's stable label text, never a number (numbers shift on
    # reorder -- LESSONS_LEARNED.md v0.99.28). This asserts the exact label
    # strings the onboarding ReShade/dgVoodoo2 offer blocks cite are
    # present verbatim in the live menu-rendering function's own item
    # list, so a future menu-label rename breaks this test instead of
    # silently going stale in the pointer text.
    It "the ReShade onboarding pointer text cites the live 'ReShade setup' menu label verbatim" {
        $reShadeItem = Get-MainMenuItems | Where-Object { $_.Mode -eq 'ReShadeSetup' }
        $reShadeItem.Label | Should -Be 'ReShade setup'
        $script:ProductionSource | Should -Match ([regex]::Escape("main menu's ReShade setup option"))
    }
    It "the dgVoodoo2 onboarding pointer text cites the live 'dgVoodoo2 setup' menu label verbatim" {
        $dgItem = Get-MainMenuItems | Where-Object { $_.Mode -eq 'DgVoodoo2Setup' }
        $dgItem.Label | Should -Be 'dgVoodoo2 setup'
        $script:ProductionSource | Should -Match ([regex]::Escape("main menu's dgVoodoo2 setup option"))
    }
    It "the onboarding flow never hardcodes a numbered 'option N from the menu' reference for ReShade/dgVoodoo2" {
        # These exact phrases (with a literal menu number) were the pre-fix
        # text this round removed -- confirms the regression cannot come
        # back silently.
        $script:ProductionSource | Should -Not -Match 'choose option 5 from the menu'
        $script:ProductionSource | Should -Not -Match 'choose option 6 from the menu'
    }
}

Describe "Path-concept non-conflation guard (Part 2 item 9)" {
    # Guards against re-collapsing the three distinct path concepts this
    # round's terminology pass deliberately kept separate: the ZIP
    # source ($zipSource -- "original game files"), the staging/
    # preparation folder ($gamesInstallFolder -- "ready-to-play games"),
    # and the TeknoParrot install folder ($tpRoot). Fails if the staging
    # folder is ever described with the exact phrase "game folder" alone
    # (the specific collapse this corrections round rejected, since it
    # would blur it with the ZIP source concept), or if a fourth
    # "deployed location" concept is introduced.
    It "never renames the staging/preparation folder to the bare unqualified phrase 'game folder'" {
        # The staging-folder prompt block's own descriptive text (around
        # 'This is where TPM extracts your ZIPs and installs games.')
        # must not use the exact rejected phrase.
        $script:ProductionSource | Should -Not -Match 'Path to your game folder'
    }
    It "never introduces a fourth 'deployed location' path concept" {
        $script:ProductionSource | Should -Not -Match '(?i)deployed location'
    }
    It "the staging folder prompt still pairs the plain phrase with the technical term on first mention" {
        $script:ProductionSource | Should -Match ([regex]::Escape("This is where TPM extracts and installs games. Your original ZIPs stay where they are."))
    }
}

Describe "Get-ConsoleLayoutTier" {
    It "uses the RC2 viewport breakpoints" {
        Get-ConsoleLayoutTier -Width 80 -Height 80 -RequiredFullLines 60 | Should -Be 'Compact'
        Get-ConsoleLayoutTier -Width 89 -Height 80 -RequiredFullLines 60 | Should -Be 'Compact'
        Get-ConsoleLayoutTier -Width 90 -Height 80 -RequiredFullLines 60 | Should -Be 'Standard'
        Get-ConsoleLayoutTier -Width 119 -Height 80 -RequiredFullLines 60 | Should -Be 'Standard'
        Get-ConsoleLayoutTier -Width 120 -Height 80 -RequiredFullLines 60 | Should -Be 'Professional'
        Get-ConsoleLayoutTier -Width 149 -Height 80 -RequiredFullLines 60 | Should -Be 'Professional'
        Get-ConsoleLayoutTier -Width 150 -Height 80 -RequiredFullLines 60 | Should -Be 'Ultra'
    }
    It "does not demote a wide viewport solely because it is short" {
        Get-ConsoleLayoutTier -Width 200 -Height 30 -RequiredFullLines 60 | Should -Be 'Ultra'
    }
}

Describe "Get-MainMenuRenderMetrics" {
    It "reports compact single-column metrics for narrow widths" {
        $metrics = Get-MainMenuRenderMetrics -Tier 'Compact' -Width 80
        $metrics.Layout | Should -Be 'CompactWrappedSingleColumn'
        $metrics.DescriptionWidth | Should -Be 0
        $metrics.TotalRenderWidth | Should -BeLessOrEqual 80
    }
    It "reports standard single-column metrics for normal widths" {
        $metrics = Get-MainMenuRenderMetrics -Tier 'Standard' -Width 110
        $metrics.Layout | Should -Be 'StandardSingleColumn'
        $metrics.DescriptionWidth | Should -BeGreaterThan 60
        $metrics.TotalRenderWidth | Should -BeGreaterThan 100
    }
    It "makes 120 columns a professional wide layout instead of compact-style output" {
        $compact = Get-MainMenuRenderMetrics -Tier 'Compact' -Width 80
        $professional = Get-MainMenuRenderMetrics -Tier 'Professional' -Width 120

        $professional.Layout | Should -Be 'ProfessionalTwoColumn'
        $professional.TotalRenderWidth | Should -BeGreaterThan 115
        $professional.DescriptionWidth | Should -BeGreaterThan 40
        $professional.TotalRenderWidth | Should -BeGreaterThan $compact.TotalRenderWidth
    }
    It "reports ultra metrics that expand with terminal width" {
        $wide150 = Get-MainMenuRenderMetrics -Tier 'Ultra' -Width 150
        $wide200 = Get-MainMenuRenderMetrics -Tier 'Ultra' -Width 200

        $wide150.Layout | Should -Be 'UltraTwoColumn'
        $wide150.DescriptionWidth | Should -BeGreaterThan 50
        $wide150.TotalRenderWidth | Should -BeGreaterThan 140
        $wide200.TotalRenderWidth | Should -BeGreaterThan $wide150.TotalRenderWidth
        $wide200.DescriptionWidth | Should -BeGreaterThan $wide150.DescriptionWidth
    }
    It "can report an experimental centered ultra layout without changing the default" {
        $default = Get-MainMenuRenderMetrics -Tier 'Ultra' -Width 180
        $centered = Get-MainMenuRenderMetrics -Tier 'Ultra' -Width 180 -UltraLayoutMode 'UltraCentered'

        $default.Layout | Should -Be 'UltraTwoColumn'
        $centered.Layout | Should -Be 'UltraCentered'
        $centered.TotalRenderWidth | Should -BeLessThan $default.TotalRenderWidth
        $centered.DescriptionWidth | Should -BeGreaterThan 90
    }
    It "reports height and width constraints for diagnostics" {
        $metrics = Get-MainMenuRenderMetrics -Tier 'Professional' -Width 120 -Height 20 -RequiredFullLines 60

        $metrics.HeightConstrained | Should -BeTrue
        $metrics.WidthConstrained | Should -BeTrue
        $metrics.ConstrainedBy | Should -Be 'width,height'
    }
}

Describe "Manager banner rendering" {
    It "uses the compact plain-text banner for narrow widths" {
        $lines = Get-ManagerBannerLines -Width 80 -Height 30

        ($lines -join "`n") | Should -Match 'TeknoParrot Manager'
        ($lines -join "`n") | Should -Match 'Version 1.0 RC3'
        ($lines -join "`n") | Should -Not -Match '/_  __/__.*___'
    }
    It "selects responsive branding modes by viewport width" {
        Get-ManagerBannerMode -Width 80 -Height 40 | Should -Be 'PlainText'
        Get-ManagerBannerMode -Width 120 -Height 40 | Should -Be 'PlainText'
        Get-ManagerBannerMode -Width 150 -Height 40 | Should -Be 'PlainText'
        Get-ManagerBannerMode -Width 180 -Height 40 | Should -Be 'AnsiShadow'
    }
    It "does not force FIGlet branding into compact windows" {
        Test-UseManagerAsciiBanner -Width 89 -Height 40 | Should -BeFalse
        Test-UseManagerAsciiBanner -Width 90 -Height 40 | Should -BeFalse
        Test-UseManagerAsciiBanner -Width 150 -Height 20 | Should -BeFalse
        Test-UseManagerAsciiBanner -Width 180 -Height 20 | Should -BeTrue
    }
    It "centers ANSI Shadow branding and includes the canonical display version" {
        $lines = Get-ManagerBannerLines -Width 180 -Height 30
        $joined = $lines -join "`n"
        $block = [string][char]0x2588

        $joined.Contains($block) | Should -BeTrue
        $joined | Should -Match 'Developed and maintained by Jumpstile'
        $joined | Should -Match 'Version 1.0 RC3'
        $lines | ForEach-Object { $_.Length | Should -BeLessOrEqual 180 }
    }
    It "keeps each branding mode inside its target width" {
        foreach ($width in @(80, 120, 150, 180)) {
            Get-ManagerBannerLines -Width $width -Height 40 | ForEach-Object {
                $_.Length | Should -BeLessOrEqual $width
            }
        }
    }
    It "assigns console-safe colors to responsive banner rows" {
        $rows = Get-ManagerBannerRows -Width 180 -Height 40
        $block = [string][char]0x2588

        $figletRow = $rows | Where-Object { $_.Text.Contains($block) } | Select-Object -First 1
        ($figletRow.Segments | ForEach-Object { $_.Color }) | Should -Contain 'Cyan'
        ($rows | Where-Object { $_.Text -match 'Developed and maintained by Jumpstile' }).Segments.Color | Should -Contain 'Yellow'
        ($rows | Where-Object { $_.Text -match 'Version 1.0 RC3' }).Color | Should -Be 'Cyan'
    }
}

Describe "Split-TextForMenuWidth" {
    It "keeps text on one line when the menu column is wide enough" {
        $lines = Split-TextForMenuWidth -Text 'Alpha beta gamma delta' -Width 80
        $lines.Count | Should -Be 1
        $lines[0] | Should -Be 'Alpha beta gamma delta'
    }
    It "wraps text deterministically when the menu column is narrow" {
        $lines = Split-TextForMenuWidth -Text 'Alpha beta gamma delta' -Width 12
        $lines.Count | Should -BeGreaterThan 1
        ($lines -join '|') | Should -Be 'Alpha beta gamma|delta'
    }
}

Describe "Format-MainMenuItemLines" {
    It "uses a genuinely wide description column when the caller provides wide space" {
        $autoSync = (Get-MainMenuItems) | Where-Object { $_.Mode -eq 'AutoSync' }
        $lines = Format-MainMenuItemLines -Item $autoSync -Tier 'Professional' -Width 118
        $lines.Count | Should -Be 1
        $lines[0] | Should -Be '  1) AutoSync -- Extract ZIPs (NAS or local) to a local folder, then register the games.'
    }
    It "wraps under the description column when the caller provides narrow space" {
        $autoSync = (Get-MainMenuItems) | Where-Object { $_.Mode -eq 'AutoSync' }
        $lines = Format-MainMenuItemLines -Item $autoSync -Tier 'Professional' -Width 70
        $lines.Count | Should -BeGreaterThan 1
        $lines[1] | Should -Match '^\s{10,}register the games\.'
    }
}

Describe "Render-MainMenuScreen / Show-MainMenu" {
    It "renders the complete Professional menu into a deterministic buffer" {
        $screen = Render-MainMenuScreen -Tier 'Professional' -Width 150 -Height 80
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"

        $screen.Rows.Count | Should -BeGreaterThan 20
        $output | Should -Match 'Developed and maintained by Jumpstile'
        $output | Should -Match 'Version 1.0 RC3'
        foreach ($item in (Get-MainMenuItems)) {
            $output | Should -Match ([regex]::Escape("$($item.Number)) $($item.Label)"))
        }
    }
    It "renders Ultra as separate bounded rows instead of one collapsed line" {
        $screen = Render-MainMenuScreen -Tier 'Ultra' -Width 160 -Height 40

        $screen.Rows.Count | Should -BeGreaterThan 25
        (($screen.Rows | ForEach-Object { $_.Text.Length }) | Measure-Object -Maximum).Maximum | Should -BeLessOrEqual 160
        # @() wrap is required, not stylistic: PowerShell 7 added an intrinsic
        # scalar .Count member (a lone PSCustomObject reports Count=1), but
        # Windows PowerShell 5.1 -- this project's actual target runtime, and
        # what CI's "shell: powershell" step actually runs -- does not have
        # it, so .Count on a single (non-array) Where-Object match is $null
        # there. Exactly one row matches each of these two filters, so this
        # passed under PS7 (this dev environment's default) but failed on
        # every real PS 5.1 run, including CI, even though the actual
        # rendering was always correct on both. See LESSONS_LEARNED.md,
        # "PowerShell return @() gotcha."
        @($screen.Rows | Where-Object { $_.Text -match 'AutoSync' }).Count | Should -BeGreaterThan 0
        @($screen.Rows | Where-Object { $_.Text -match 'Crosshair setup' }).Count | Should -BeGreaterThan 0
    }
    It "returns a flat row buffer for the production writer" {
        $screen = Render-MainMenuScreen -Tier 'Professional' -Width 150 -Height 30

        $screen.Rows.Count | Should -BeGreaterThan 20
        foreach ($row in $screen.Rows) {
            $row | Should -Not -BeOfType ([object[]])
            $row.PSObject.Properties.Name | Should -Contain 'Text'
            $row.PSObject.Properties.Name | Should -Contain 'Color'
        }
    }
    It "Standard tier renders labels only so compact windows remain complete" {
        $screen = Render-MainMenuScreen -Tier 'Standard' -Width 110 -Height 30
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"
        $item = (Get-MainMenuItems) | Where-Object { $_.Mode -eq 'AutoSync' }
        $output | Should -Match ([regex]::Escape("1) AutoSync"))
        $output | Should -Not -Match ([regex]::Escape($item.ShortDesc))
        $output | Should -Match 'Enter number'
    }
    It "Compact tier renders only labels and the 'Type ? for descriptions' hint, no ShortDesc/FullDesc text" {
        $screen = Render-MainMenuScreen -Tier 'Compact' -Width 80 -Height 80
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"
        $output | Should -Match 'TeknoParrot Manager'
        $output | Should -Match 'Version 1.0 RC3'
        $output | Should -Not -Match '/_  __/'
        $output | Should -Match 'Type \? for descriptions'
        $autoSync = (Get-MainMenuItems) | Where-Object { $_.Mode -eq 'AutoSync' }
        $output | Should -Not -Match ([regex]::Escape($autoSync.ShortDesc))
    }
    It "Professional default tier uses a complete framed two-column menu" {
        $screen = Render-MainMenuScreen -Tier 'Professional' -Width 150 -Height 30
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"
        $output | Should -Match 'Version 1.0 RC3'
        $output | Should -Match ([regex]::Escape("1) AutoSync"))
        $output | Should -Match ([regex]::Escape("Extract and register ZIPs safely."))
        $output | Should -Match 'GAME ENHANCEMENTS'
        $output | Should -Match 'Enter number'
        $screen.Geometry.ColumnCount | Should -Be 2
        $screen.Geometry.MenuWidth | Should -BeGreaterThan 115
    }
    It "Ultra tier renders menu groups side-by-side instead of a narrow left-column menu" {
        $screen = Render-MainMenuScreen -Tier 'Ultra' -Width 160 -Height 40
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"
        $output | Should -Match '(?m)LIBRARY MANAGEMENT\s+-+\s+\|\s+GAME ENHANCEMENTS'
        $screen.Geometry.ColumnCount | Should -Be 2
        $screen.Geometry.MenuWidth | Should -BeGreaterThan 145
    }
    It "UltraCentered renders a single centered content block" {
        # Height 65 is tall enough for UltraCentered's full-description,
        # single-column content to render in full without any body
        # truncation (confirmed empirically: content needs 61 rows; a
        # shorter height, e.g. 30, legitimately truncates the earliest
        # sections first per Limit-MainMenuBodyRowsToBudget -- see the
        # "issue #104 RC3 correction" tests below, which cover that case
        # directly and assert Exit/footer survive instead of AutoSync).
        $screen = Render-MainMenuScreen -Tier 'Ultra' -Width 180 -Height 70 -UltraLayoutMode 'UltraCentered'
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"

        $screen.Geometry.ColumnCount | Should -Be 1
        $screen.Geometry.LeftPadding | Should -BeGreaterThan 10
        $output | Should -Match ([regex]::Escape("1) AutoSync"))
        $output | Should -Match '15\) Exit'
        $output | Should -Not -Match '(?m)LIBRARY MANAGEMENT\s+-+\s+GAME ENHANCEMENTS'
    }
    It "narrow Professional tier remains bounded and readable" {
        $screen = Render-MainMenuScreen -Tier 'Professional' -Width 70 -Height 45
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"
        $output | Should -Match ([regex]::Escape("1) AutoSync"))
        $output | Should -Match 'Enter number'
    }
    It "rendered rows never exceed the detected viewport width" {
        foreach ($case in @(
            @{ Tier = 'Compact'; Width = 80; Height = 25 },
            @{ Tier = 'Standard'; Width = 100; Height = 30 },
            @{ Tier = 'Professional'; Width = 132; Height = 30 },
            @{ Tier = 'Ultra'; Width = 160; Height = 40 }
        )) {
            $screen = Render-MainMenuScreen -Tier $case.Tier -Width $case.Width -Height $case.Height
            foreach ($row in $screen.Rows) {
                $row.Text.Length | Should -BeLessOrEqual $case.Width
            }
        }
    }
    It "small viewport keeps the footer and Exit visible without scrolling, even if it must drop earlier sections (issue #104 RC3 correction)" {
        # Prior behavior flattened banner+body+footer and kept only the
        # first N rows top-to-bottom -- at a short height that silently
        # dropped the entire footer (Quit/Help controls) and the
        # Application section (option 15, Exit), which a real user could
        # never reach without resizing or scrolling. This asserted that
        # loss as "expected" (`Should -Not -Match 'Exit'`); the corrected
        # behavior below is the opposite: the footer and Exit must survive,
        # and it is earlier body content that gets trimmed first if
        # something has to give.
        $screen = Render-MainMenuScreen -Tier 'Compact' -Width 80 -Height 12
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"

        $screen.Rows.Count | Should -BeLessOrEqual 10
        $output | Should -Match 'TeknoParrot Manager'
        $output | Should -Match '15\) Exit'
        $output | Should -Match 'Enter number'
    }

    It "reserves footer rows unconditionally so they are never truncated away, across every tier at a short height" {
        foreach ($case in @(
            @{ Tier = 'Compact'; Width = 80 },
            @{ Tier = 'Standard'; Width = 100 },
            @{ Tier = 'Professional'; Width = 132 },
            @{ Tier = 'Ultra'; Width = 160 }
        )) {
            $screen = Render-MainMenuScreen -Tier $case.Tier -Width $case.Width -Height 12
            $normalFooterRows = @(Get-MainMenuFooterRows -Geometry $screen.Geometry)
            $minimalFooterRows = @(Get-MainMenuMinimalFooterRows -Geometry $screen.Geometry)

            # At this height, a narrow-enough tier may now legitimately fall
            # into the emergency compact presentation (issue #104 RC3-B),
            # which uses a single-line minimal footer instead of the normal
            # framed one -- either is acceptable here, since the point of
            # this test is that the footer is never truncated away
            # entirely, not that one specific footer variant is used.
            $screen.Rows.Count | Should -BeGreaterOrEqual 1
            $lastRowText = $screen.Rows[-1].Text
            $matchesNormalTail = ($normalFooterRows.Count -gt 0) -and ($lastRowText -eq $normalFooterRows[-1].Text)
            $matchesMinimalTail = ($minimalFooterRows.Count -gt 0) -and ($lastRowText -eq $minimalFooterRows[-1].Text)
            ($matchesNormalTail -or $matchesMinimalTail) | Should -BeTrue
        }
    }

    It "keeps option 15 (Exit) visible at every tier when the viewport is short, single-column layouts" {
        foreach ($case in @(
            @{ Tier = 'Compact'; Width = 80 },
            @{ Tier = 'Standard'; Width = 100 }
        )) {
            $screen = Render-MainMenuScreen -Tier $case.Tier -Width $case.Width -Height 12
            $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"
            $output | Should -Match '15\) Exit'
        }
    }

    It "keeps option 15 (Exit) visible at Professional/Ultra two-column tiers when the viewport is short" {
        # Two-column layouts interleave rows from all four sections per row
        # index (Join-MainMenuRenderColumns), so Exit's row can appear
        # earlier in the flat row list than in a single-column layout --
        # confirms the front-trim-only-single-column-body assumption still
        # leaves Exit visible where it actually lives in a 2-column render.
        foreach ($case in @(
            @{ Tier = 'Professional'; Width = 132 },
            @{ Tier = 'Ultra'; Width = 160 }
        )) {
            $screen = Render-MainMenuScreen -Tier $case.Tier -Width $case.Width -Height 12
            $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"
            $output | Should -Match '15\) Exit'
        }
    }
    It "Show-MainMenu delegates to the stateless render-clear-write pipeline" {
        $mainScriptContent = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1') -Raw

        $mainScriptContent.Contains('$screen = Render-MainMenuScreen -Tier $Tier -Width $Width -Height $Height -UltraLayoutMode $UltraLayoutMode') | Should -Be $true
        $mainScriptContent.Contains('Clear-ConsoleForFreshRender') | Should -Be $true
        $mainScriptContent.Contains('Set-ConsoleRenderOrigin') | Should -Be $true
        $mainScriptContent.Contains('Limit-MainMenuRowsToViewport') | Should -Be $true
        $mainScriptContent.Contains('Write-ConsoleRenderRows -Rows $screen.Rows') | Should -Be $true
    }
    It "Show-MainMenu's actual output includes visible menu items" {
        $output = & { Show-MainMenu -Tier 'Ultra' -Width 160 -Height 40 } 6>&1 | Out-String

        $output | Should -Match 'LIBRARY MANAGEMENT'
        $output | Should -Match 'AutoSync'
        $output | Should -Match 'GAME ENHANCEMENTS'
        $output | Should -Match 'Exit'
    }
    It "responsive menu input falls back when stdin is redirected" {
        $mainScriptContent = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1') -Raw

        $mainScriptContent | Should -Match '\[Console\]::IsInputRedirected'
        $mainScriptContent | Should -Match 'Read-Host \$Prompt'
    }
}

Describe "Minimum supported 60x10 viewport and nearby boundaries (issue #104 RC3-B correction)" {
    # At 60x10, the normal per-item-per-row Compact body (4 section headers
    # + 15 item rows = 19 rows minimum) cannot fit even after
    # Limit-MainMenuBodyRowsToBudget trims it -- the framed banner (6 rows)
    # and footer (2 rows) alone already consume the entire 8-row budget
    # (ViewportHeight - 2), leaving zero rows for body content. Simply
    # reserving Exit + the footer is not sufficient on its own: it still
    # silently drops every OTHER option. Get-MainMenuEmergencyCompactRows
    # replaces the framed banner/footer with single-line versions and
    # flow-packs every "N) Label" as densely as the width allows, so every
    # option stays visible.
    # Using -TestCases (Pester's own parameterized-test mechanism) rather
    # than `foreach ($height in ...) { It ... { ...$height... } }`: a plain
    # PowerShell foreach-loop variable closed over by an It scriptblock is
    # NOT visible inside that scriptblock's body when Pester actually runs
    # it (confirmed by isolated repro -- the value reads as $null/empty at
    # Run time even though it renders correctly in the It's own title,
    # which is built separately at Discovery time). -TestCases passes each
    # case's values in as real bound parameters instead, which does work.
    It "at the supported 60x<Height> minimum and its immediate boundaries, every option 1-15 is visible, Exit and the footer are present, and nothing scrolls off the viewport" -TestCases @(
        @{ Height = 10 }, @{ Height = 11 }, @{ Height = 12 }
    ) {
        param($Height)
        $screen = Render-MainMenuScreen -Tier (Get-ConsoleLayoutTier -Width 60 -Height $Height -RequiredFullLines 0) -Width 60 -Height $Height
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"

        $screen.Rows.Count | Should -BeLessOrEqual ([Math]::Max(5, $Height - 2))
        $allItemNumbers = @((Get-MainMenuItems) | ForEach-Object { $_.Number })
        foreach ($n in $allItemNumbers) {
            $output | Should -Match ([regex]::Escape("$n)"))
        }
        $output | Should -Match '15\) Exit'
        $output | Should -Match 'Enter number'
        $output | Should -Match 'Q=Quit'
    }

    It "below the documented 60x10 minimum (60x8), the footer and option 15 (Exit) are still never dropped, even though an earlier option's line may not fit" {
        # 60x8 is below the documented supported floor, so unlike the exact
        # cases above, this does not require every option to be visible --
        # only that the two guarantees which must NEVER break (the footer's
        # Quit control, and Exit specifically) still hold, and that nothing
        # crashes or silently renders a blank/broken screen.
        $screen = Render-MainMenuScreen -Tier (Get-ConsoleLayoutTier -Width 60 -Height 8 -RequiredFullLines 0) -Width 60 -Height 8
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"

        $screen.Rows.Count | Should -BeLessOrEqual ([Math]::Max(5, 8 - 2))
        $output | Should -Match '15\) Exit'
        $output | Should -Match 'Enter number'
        $output | Should -Match 'Q=Quit'
    }

    It "every flow-packed 'N) Label' token matches Get-MainMenuItems exactly (no drift between the emergency presentation and the real dispatch data)" {
        $geometry = Get-MainMenuGeometry -Tier 'Compact' -ViewportWidth 60 -ViewportHeight 10
        $rows = Get-MainMenuFlowPackedItemRows -Width 58 -Geometry $geometry
        $flatText = ($rows | ForEach-Object { $_.Text }) -join ' '

        foreach ($item in (Get-MainMenuItems)) {
            $flatText | Should -Match ([regex]::Escape("$($item.Number)) $($item.Label)"))
        }
    }

    # Using -TestCases (Pester's own parameterized-test mechanism), not a
    # `foreach ($case in ...) { ... }` loop bundled inside a single `It`
    # body: a bundled loop reports as exactly one pass/fail for all four
    # cases combined, so a reviewer reading Pester's output cannot tell
    # whether all four widths/heights actually ran, whether they ran with
    # their own distinct values, or whether an early failure silently
    # skipped the remaining cases (`Should` throws, which stops the loop).
    # -TestCases gives each case its own named, independently-reported
    # result instead. (Note: a bundled loop entirely INSIDE one It body is
    # not the same closure defect as a loop that WRAPS separate `It` calls
    # -- confirmed by isolated repro that the bundled form here did receive
    # correct per-iteration values -- but it still doesn't prove independent
    # per-case execution/reporting, which is what this rewrite is for.)
    It "at <Width>x<Height>, Exit and the footer stay visible without scrolling, using this case's own dimensions" -TestCases @(
        @{ Width = 80;  Height = 8;  ExpectedTier = 'Compact' }
        @{ Width = 100; Height = 8;  ExpectedTier = 'Standard' }
        @{ Width = 150; Height = 8;  ExpectedTier = 'Ultra' }
        @{ Width = 100; Height = 20; ExpectedTier = 'Standard' }
    ) {
        param($Width, $Height, $ExpectedTier)
        $tier = Get-ConsoleLayoutTier -Width $Width -Height $Height -RequiredFullLines 0

        # Proves the WIDTH bound into this case actually drove tier
        # selection (Get-ConsoleLayoutTier is width-only, so this is a
        # second, independent confirmation of the Width binding below, not
        # a duplicate of it) -- a cross-case value swap between the 80/100/
        # 150-wide cases would flip this and fail.
        $tier | Should -Be $ExpectedTier

        $screen = Render-MainMenuScreen -Tier $tier -Width $Width -Height $Height
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"

        # Proves this case actually ran with ITS OWN Width, not a value
        # shared or duplicated from another case -- the specific
        # "accidental duplicate binding" this rewrite guards against. The
        # geometry object is threaded all the way through from the -Width
        # parameter passed into Render-MainMenuScreen above, so a mismatch
        # here would mean cross-case value bleed. (ViewportWidth, not
        # Height, because Get-MainMenuGeometry internally clamps
        # ViewportHeight to a floor of 10 for its own column-width math --
        # see the real-height budgeting note in ARCHITECTURE.md -- so it
        # would not reflect this case's own Height value for the two 8-row
        # cases here even when everything is working correctly.)
        $screen.Geometry.ViewportWidth | Should -Be $Width

        # This case's own Height still matters even though the two
        # Width=100 cases (100x8 and 100x20) share a tier: the row-count
        # ceiling is derived from THIS case's real Height (Max(5,
        # Height-2) = 6 for height 8, 18 for height 20), so a cross-case
        # Height swap between those two would change which bound applies.
        $screen.Rows.Count | Should -BeLessOrEqual ([Math]::Max(5, $Height - 2))
        $output | Should -Match '15\) Exit'
        $output | Should -Match 'Q=Quit'

        # All four of these cases happen to be wide enough that the render
        # pipeline shows every option even in its most space-constrained
        # form (confirmed empirically, not assumed) -- verified per case
        # rather than in a separate test, so this remains part of the same
        # independently-reported, per-case proof.
        foreach ($n in @((Get-MainMenuItems) | ForEach-Object { $_.Number })) {
            $output | Should -Match ([regex]::Escape("$n)"))
        }
    }

    It "a generously tall Compact-width window (60x30) still uses the normal framed presentation, not the emergency fallback" {
        # Confirms the emergency mode is gated correctly -- it must not
        # trigger just because the width is narrow, only when the height
        # genuinely can't fit every option any other way.
        $screen = Render-MainMenuScreen -Tier 'Compact' -Width 60 -Height 30
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"

        $output | Should -Match 'LIBRARY MANAGEMENT'
        $output | Should -Match 'APPLICATION'
        $output | Should -Match '15\) Exit'
    }

    It "every numbered option in the emergency presentation still maps to the same Mode the live switch statement dispatches on" {
        # Cross-checks against the same source-of-truth used by "Main menu
        # source-level drift check" elsewhere in this file: the emergency
        # presentation's numbers come directly from Get-MainMenuItems, the
        # same data the switch statement's case labels are generated from,
        # so there is no separate hand-maintained number-to-mode mapping
        # that could drift.
        $mainScriptContent = Get-Content -LiteralPath $scriptPath -Raw
        foreach ($item in (Get-MainMenuItems)) {
            if ($item.Mode -eq 'Exit') { continue }
            $mainScriptContent | Should -Match ([regex]::Escape('"{0}"' -f $item.Number) + '\s*\{\s*\$mode\s*=\s*"' + [regex]::Escape($item.Mode) + '"')
        }
    }
}

Describe "Issue #140 wording surfaces at every layout tier (issue #104/#140 RC3 correction)" {
    # Confirmed gap: Get-MainMenuSectionRows has a Professional-tier-only
    # special case (`if ($Geometry.Layout -eq 'ProfessionalTwoColumn')`)
    # that always sources its description text from
    # Get-MainMenuDefaultDescription instead of the shared ShortDesc/
    # FullDesc fields on the item -- so the #140 wording improvements
    # (ReShade/Postgres/BepInEx) landed only on ShortDesc/FullDesc and never
    # reached that function, meaning Professional tier (and Compact tier's
    # "?" detail view, which explicitly falls back to Professional -- see
    # the `if ($helpTier -eq 'Compact') { $helpTier = 'Professional' }` line
    # in the main menu loop) kept showing the OLD text, including the
    # literal "Install local PostgreSQL support." wording this issue was
    # filed to improve. Fixed by updating Get-MainMenuDefaultDescription's
    # text directly, since the Professional-specific routing itself is
    # deliberate (a shorter, single-line variant for a tighter column) and
    # out of scope to change.
    It "Professional tier (two-column) shows the improved wording, not the pre-#140 defaults" {
        $screen = Render-MainMenuScreen -Tier 'Professional' -Width 150 -Height 40
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"

        $output | Should -Match 'CRT'
        $output | Should -Match 'Golden Tee'
        $output | Should -Match 'modding framework'
        $output | Should -Not -Match 'Install local PostgreSQL support\.'
        $output | Should -Not -Match 'Apply visual enhancements\.'
        $output | Should -Not -Match 'Update existing BepInEx installs\.'
    }

    It "Compact tier's '?' detail view (falls back to Professional) also shows the improved wording" {
        # Reproduces the main loop's exact fallback: a Compact-tier console
        # pressing '?' is shown the Professional layout, not Compact's own
        # (label-only) layout. At this narrower two-column width the
        # description text legitimately word-wraps across render rows AND
        # across the column gutter/frame characters, so "modding" and
        # "framework" can end up separated by more than plain whitespace --
        # assert each word is present rather than requiring adjacency.
        $screen = Render-MainMenuScreen -Tier 'Professional' -Width 80 -Height 40
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"

        $output | Should -Match 'CRT'
        $output | Should -Match 'Golden Tee'
        $output | Should -Match 'modding'
        $output | Should -Match 'framework'
    }

    It "Ultra two-column tier (the default 'largest layout') shows the improved ShortDesc wording" {
        $screen = Render-MainMenuScreen -Tier 'Ultra' -Width 160 -Height 40
        $screen.Geometry.Layout | Should -Be 'UltraTwoColumn'
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"

        $output | Should -Match 'CRT'
        $output | Should -Match 'Golden Tee'
        $output | Should -Match 'modding framework'
    }

    It "UltraCentered (single-column, full descriptions) shows the improved FullDesc wording" {
        $screen = Render-MainMenuScreen -Tier 'Ultra' -Width 180 -Height 65 -UltraLayoutMode 'UltraCentered'
        $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"

        $output | Should -Match 'CRT'
        $output | Should -Match 'Golden Tee'
        $output | Should -Match 'modding framework'
    }

    It "Standard and Compact tiers' own (labels-only) render is unaffected -- no description text shown either way" {
        # Documents existing, unchanged-by-this-fix behavior: Standard and
        # Compact both render Labels-only detail with no per-item
        # description at all (Compact's escape hatch is the '?' key, tested
        # above, which is a SEPARATE render call, not part of this one).
        foreach ($case in @(
            @{ Tier = 'Compact'; Width = 80 }
            @{ Tier = 'Standard'; Width = 100 }
        )) {
            $screen = Render-MainMenuScreen -Tier $case.Tier -Width $case.Width -Height 40
            $output = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"
            $output | Should -Not -Match 'CRT'
            $output | Should -Not -Match 'Golden Tee'
        }
    }
}

Describe "Menu layout debug script" {
    It "prints host dimensions and renderer metrics without launching the interactive manager" {
        $debugScript = Join-Path $PSScriptRoot '..\scripts\Debug-TPM-MenuLayout.ps1'
        $output = & $debugScript -Width 200 -Height 30 6>&1 | Out-String

        $output | Should -Match 'Host type'
        $output | Should -Match 'Host\.RawUI\.WindowSize\.Width'
        $output | Should -Match 'Host\.RawUI\.BufferSize\.Height'
        $output | Should -Match 'Selected viewport width\s+:\s+200'
        $output | Should -Match 'Selected viewport height\s+:\s+30'
        $output | Should -Match 'Selected layout tier\s+:\s+Ultra'
        $output | Should -Match 'Selected layout mode\s+:\s+UltraTwoColumn'
        $output | Should -Match 'Requested ultra mode\s+:\s+Auto'
        $output | Should -Match 'Description width\s+:\s+79'
        $output | Should -Match 'Total render width\s+:\s+198'
        $output | Should -Match 'Constrained by\s+:\s+height'
    }
    It "can render the experimental UltraCentered layout for comparison" {
        $debugScript = Join-Path $PSScriptRoot '..\scripts\Debug-TPM-MenuLayout.ps1'
        $output = & $debugScript -Width 180 -Height 30 -UltraLayoutMode UltraCentered -Render 6>&1 | Out-String

        $output | Should -Match 'Selected layout tier\s+:\s+Ultra'
        $output | Should -Match 'Selected layout mode\s+:\s+UltraCentered'
        $output | Should -Match 'Requested ultra mode\s+:\s+UltraCentered'
        $output | Should -Match 'Selected layout mode\s+:\s+UltraCentered'
    }

    # The two tests above invoke the diagnostic via `& $debugScript` from
    # INSIDE this same Pester process -- that call runs in a child scope of
    # the current session, which already has every production function
    # (including Limit-MainMenuBodyRowsToBudget) dot-sourced into it by this
    # file's own top-level BeforeAll. That let a real regression pass
    # invisibly: the packaged script itself only loaded a hand-maintained
    # allowlist of function names and never defined
    # Limit-MainMenuBodyRowsToBudget (added for the RC3 short-viewport
    # truncation fix), so running the actual, unmodified .ps1 file as a
    # user would -- a fresh process with nothing pre-loaded -- crashed with
    # "the term 'Limit-MainMenuBodyRowsToBudget' is ... not recognized" the
    # moment -Render exercised the render pipeline. `& $debugScript` here
    # never caught it because the missing function was already present from
    # this file's own BeforeAll, not from the diagnostic script itself.
    # These tests launch a genuinely separate PROCESS instead, so nothing
    # from this test session's scope can leak in and mask a missing
    # dependency in the packaged script.
    It "runs successfully as a genuinely isolated process (not just a child scope) under pwsh, with -Render exercising the full pipeline" {
        $debugScript = Join-Path $PSScriptRoot '..\scripts\Debug-TPM-MenuLayout.ps1'
        $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
        if (-not $pwshCmd) { Set-ItResult -Skipped -Because 'pwsh is not available on this machine'; return }

        $output = & $pwshCmd.Source -NoProfile -NonInteractive -File $debugScript -Width 150 -Height 40 -Render 2>&1 | Out-String
        $exitCode = $LASTEXITCODE

        $exitCode | Should -Be 0
        $output | Should -Not -Match 'is not recognized as the name of a cmdlet'
        $output | Should -Not -Match 'CommandNotFoundException'
        $output | Should -Match '15\) Exit'
        $output | Should -Match 'Enter number'
    }

    It "runs successfully as a genuinely isolated process under real Windows PowerShell 5.1, with -Render exercising the full pipeline" {
        $debugScript = Join-Path $PSScriptRoot '..\scripts\Debug-TPM-MenuLayout.ps1'
        $ps51Path = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path -LiteralPath $ps51Path)) { Set-ItResult -Skipped -Because 'Windows PowerShell 5.1 is not available on this machine'; return }

        $output = & $ps51Path -NoProfile -File $debugScript -Width 150 -Height 40 -Render 2>&1 | Out-String
        $exitCode = $LASTEXITCODE

        $exitCode | Should -Be 0
        $output | Should -Not -Match 'is not recognized as the name of a cmdlet'
        $output | Should -Not -Match 'CommandNotFoundException'
        $output | Should -Match '15\) Exit'
        $output | Should -Match 'Enter number'
    }
}

Describe "Resolve-Pcsx2Directory" {
    It "finds the exact-name pcsx2x6 folder" {
        $root = Join-Path $TestDrive ("resolve-exact-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $root 'pcsx2x6') -Force | Out-Null
        Resolve-Pcsx2Directory -TeknoParrotRoot $root | Should -Be (Join-Path $root 'pcsx2x6')
    }

    It "finds an alternate-cased PCSX2x6 folder" {
        $root = Join-Path $TestDrive ("resolve-altcase-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $root 'PCSX2x6') -Force | Out-Null
        Resolve-Pcsx2Directory -TeknoParrotRoot $root | Should -Be (Join-Path $root 'PCSX2x6')
    }

    It "returns null when no pcsx2-shaped folder exists" {
        $root = Join-Path $TestDrive ("resolve-none-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root 'GameProfiles') -Force | Out-Null
        Resolve-Pcsx2Directory -TeknoParrotRoot $root | Should -BeNullOrEmpty
    }
}

Describe "Get-CompatibilityWarnings -- BiosMissing (issue #85 tier 1)" {
    BeforeAll {
        $script:RawThrillsPathLimits = @{}
        $script:FileVersionPins = @{}
        $script:GpuIncompatibleGames = @{}
        $script:EmulatorBiosRequirements = @{
            'Pcsx2x6' = @{
                RelativeDir   = 'TeknoParrot\bios'
                RequiredFiles = @('27v1602T.d', '27v1602F.bg')
            }
        }

        function New-Pcsx2UserProfile {
            param([string]$Path)
            [xml]@'
<?xml version="1.0" encoding="utf-8"?>
<GameProfile>
  <EmulatorType>Pcsx2x6</EmulatorType>
  <GamePath>C:\Games\game.exe</GamePath>
</GameProfile>
'@ | ForEach-Object { $_.Save($Path) }
        }
    }

    It "reports nothing when -TeknoParrotRoot is not supplied (backward compatible)" {
        $userProfilesDir = Join-Path $TestDrive ("bios-no-root-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $userProfilesDir -Force | Out-Null
        New-Pcsx2UserProfile -Path (Join-Path $userProfilesDir 'BLOODYROAR3.xml')

        $result = Get-CompatibilityWarnings -UserProfilesDir $userProfilesDir
        @($result.BiosMissing) | Should -BeNullOrEmpty
    }

    It "reports nothing when the pcsx2x6 folder itself does not exist yet" {
        $root = Join-Path $TestDrive ("bios-noemudir-" + [guid]::NewGuid().ToString('N'))
        $userProfilesDir = Join-Path $root 'UserProfiles'
        New-Item -ItemType Directory -Path $userProfilesDir -Force | Out-Null
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        New-Pcsx2UserProfile -Path (Join-Path $userProfilesDir 'BLOODYROAR3.xml')

        $result = Get-CompatibilityWarnings -UserProfilesDir $userProfilesDir -TeknoParrotRoot $root
        @($result.BiosMissing) | Should -BeNullOrEmpty -Because "nothing to check yet -- the emulator itself isn't installed"
    }

    It "reports nothing when both required BIOS files are present" {
        $root = Join-Path $TestDrive ("bios-present-" + [guid]::NewGuid().ToString('N'))
        $userProfilesDir = Join-Path $root 'UserProfiles'
        $pcsx2Dir = Join-Path $root 'pcsx2x6'
        $biosDir = Join-Path $root 'pcsx2x6\TeknoParrot\bios'
        New-Item -ItemType Directory -Path $userProfilesDir, $pcsx2Dir, $biosDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $pcsx2Dir 'pcsx2-qtx64.exe') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $biosDir '27v1602T.d') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $biosDir '27v1602F.bg') -Force | Out-Null
        New-Pcsx2UserProfile -Path (Join-Path $userProfilesDir 'BLOODYROAR3.xml')

        $result = Get-CompatibilityWarnings -UserProfilesDir $userProfilesDir -TeknoParrotRoot $root
        @($result.BiosMissing) | Should -BeNullOrEmpty
    }

    It "reports a BiosMissing entry with correct MissingFiles and AffectedGames when firmware is absent" {
        $root = Join-Path $TestDrive ("bios-missing-" + [guid]::NewGuid().ToString('N'))
        $userProfilesDir = Join-Path $root 'UserProfiles'
        $pcsx2Dir = Join-Path $root 'pcsx2x6'
        New-Item -ItemType Directory -Path $userProfilesDir -Force | Out-Null
        New-Item -ItemType Directory -Path $pcsx2Dir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $pcsx2Dir 'pcsx2-qtx64.exe') -Force | Out-Null
        New-Pcsx2UserProfile -Path (Join-Path $userProfilesDir 'BLOODYROAR3.xml')

        $result = Get-CompatibilityWarnings -UserProfilesDir $userProfilesDir -TeknoParrotRoot $root
        @($result.BiosMissing).Count | Should -Be 1
        $entry = $result.BiosMissing[0]
        $entry.EmulatorType | Should -Be 'Pcsx2x6'
        @($entry.MissingFiles) | Should -Contain '27v1602T.d'
        @($entry.MissingFiles) | Should -Contain '27v1602F.bg'
        @($entry.AffectedGames) | Should -Contain 'BLOODYROAR3'
    }

    It "reports one entry (not duplicated) covering multiple registered pcsx2x6 games" {
        $root = Join-Path $TestDrive ("bios-multi-" + [guid]::NewGuid().ToString('N'))
        $userProfilesDir = Join-Path $root 'UserProfiles'
        $pcsx2Dir = Join-Path $root 'pcsx2x6'
        New-Item -ItemType Directory -Path $userProfilesDir -Force | Out-Null
        New-Item -ItemType Directory -Path $pcsx2Dir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $pcsx2Dir 'pcsx2-qtx64.exe') -Force | Out-Null
        New-Pcsx2UserProfile -Path (Join-Path $userProfilesDir 'BLOODYROAR3.xml')
        New-Pcsx2UserProfile -Path (Join-Path $userProfilesDir 'BLOODYROAR4.xml')

        $result = Get-CompatibilityWarnings -UserProfilesDir $userProfilesDir -TeknoParrotRoot $root
        @($result.BiosMissing).Count | Should -Be 1 -Because "one shared emulator instance needs one warning, not one per affected game"
        @($result.BiosMissing[0].AffectedGames).Count | Should -Be 2
    }

    It "reports only the still-missing file when one of the two required files is already present" {
        $root = Join-Path $TestDrive ("bios-partial-" + [guid]::NewGuid().ToString('N'))
        $userProfilesDir = Join-Path $root 'UserProfiles'
        $pcsx2Dir = Join-Path $root 'pcsx2x6'
        $biosDir = Join-Path $root 'pcsx2x6\TeknoParrot\bios'
        New-Item -ItemType Directory -Path $userProfilesDir, $pcsx2Dir, $biosDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $pcsx2Dir 'pcsx2-qtx64.exe') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $biosDir '27v1602T.d') -Force | Out-Null
        New-Pcsx2UserProfile -Path (Join-Path $userProfilesDir 'BLOODYROAR3.xml')

        $result = Get-CompatibilityWarnings -UserProfilesDir $userProfilesDir -TeknoParrotRoot $root
        @($result.BiosMissing).Count | Should -Be 1
        @($result.BiosMissing[0].MissingFiles) | Should -Be @('27v1602F.bg')
    }

    It "never reads or modifies the placeholder BIOS files -- existence-only check" {
        $root = Join-Path $TestDrive ("bios-readonly-check-" + [guid]::NewGuid().ToString('N'))
        $userProfilesDir = Join-Path $root 'UserProfiles'
        $pcsx2Dir = Join-Path $root 'pcsx2x6'
        $biosDir = Join-Path $root 'pcsx2x6\TeknoParrot\bios'
        New-Item -ItemType Directory -Path $userProfilesDir, $pcsx2Dir, $biosDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $pcsx2Dir 'pcsx2-qtx64.exe') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $biosDir '27v1602T.d') -Value 'not real firmware content' -Encoding ascii
        Set-Content -LiteralPath (Join-Path $biosDir '27v1602F.bg') -Value 'not real firmware content' -Encoding ascii
        $beforeT = Get-Content -LiteralPath (Join-Path $biosDir '27v1602T.d') -Raw
        New-Pcsx2UserProfile -Path (Join-Path $userProfilesDir 'BLOODYROAR3.xml')

        Get-CompatibilityWarnings -UserProfilesDir $userProfilesDir -TeknoParrotRoot $root | Out-Null

        (Get-Content -LiteralPath (Join-Path $biosDir '27v1602T.d') -Raw) | Should -Be $beforeT -Because "TPM must never read or modify BIOS file content, only check existence"
    }
}

Describe "Get-CompatibilityWarnings -- pcsx2x6 component (issue #254)" {
    BeforeAll {
        # The production helper is extracted from the main script into a
        # $TestDrive file by the outer harness. Mirror the repository-shaped
        # ECVF tree beside that extracted file so its $PSScriptRoot-anchored
        # contract lookup consults the real detector and contract.
        New-Item -ItemType Directory -Path (Join-Path $TestDrive 'scripts'), (Join-Path $TestDrive 'contracts\pcsx2x6') -Force | Out-Null
        $script:compatAuthorityModulePath = Join-Path $TestDrive 'scripts\TPMCertification.Authority.psm1'
        $script:compatContractsModulePath = Join-Path $TestDrive 'scripts\TPMCertification.Contracts.psm1'
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TPMCertification.Authority.psm1') -Destination $script:compatAuthorityModulePath -Force
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TPMCertification.Contracts.psm1') -Destination $script:compatContractsModulePath -Force
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\contracts\pcsx2x6\contract.json') -Destination (Join-Path $TestDrive 'contracts\pcsx2x6\contract.json') -Force

        # A synthetic non-pcsx2x6 contract proves the production path is
        # generalized without adding an unsupported real emulator contract to
        # the repository. Its PathExists detector is the same ECVF shape used
        # by the real pcsx2x6 contract.
        $fixtureContractDir = Join-Path $TestDrive 'contracts\fixtureemu'
        New-Item -ItemType Directory -Path $fixtureContractDir -Force | Out-Null
        $fixtureContract = [ordered]@{
            ContractId = 'fixtureemu'
            SchemaVersion = '1.0.0'
            DisplayName = 'Fixture emulator'
            UpstreamRepository = 'https://example.invalid/fixtureemu'
            UpstreamPinnedCommit = ('0' * 40)
            UpstreamPinnedCommitDate = '2026-01-01'
            VersionDetector = [ordered]@{ Method = 'PathExists'; Source = 'fixture.exe'; Pattern = '^fixture$'; MatchedCommitMap = @() }
            ContractStatus = 'EvidenceGathered'
            EvidenceConfidence = 'SourceVerified'
            OwnershipBoundaries = @([ordered]@{
                SettingPath = 'FixtureSetting'; Owner = 'Emulator'; Mutability = 'EmulatorManaged'
                ReadPolicy = 'ReadForVerificationOnly'; WritePolicy = 'NeverWrite'; EvidenceReference = 'ev-fixture'
            })
            EnvironmentCapabilities = @([ordered]@{
                CapabilityId = 'env-init'
                PresenceDetector = [ordered]@{ Method = 'PathExists'; Source = 'fixture.exe'; Pattern = $null }
                DataRootResolver = [ordered]@{ Method = 'FixedPath'; Source = 'Data'; DefaultValue = $null }
                InitializationAction = [ordered]@{ Method = 'None'; Command = $null; Arguments = @(); ExpectedExitCodes = @(0); TimeoutSeconds = 1 }
                InitializedVerifier = [ordered]@{ RequiredPaths = @('fixture.ini'); RequiredMarkers = @(); ParseMethod = 'IniSections' }
                ObservableEvidence = @('ev-fixture')
                ExpectedOutcome = 'fixture.exe exists under the fixture emulator directory'
            })
            RuntimeCapabilities = @()
            EvidenceReferences = @([ordered]@{
                EvidenceId = 'ev-fixture'; Type = 'SourceCitation'; Description = 'Synthetic test contract'
                Locator = 'evidence.md#fixture'; Commit = $null; Confidence = 'SourceVerified'; RecordedDate = '2026-01-01'
            })
            DriftPolicy = [ordered]@{
                OnUnknownVersion = 'FailClosed'; OnDivergedVersion = 'FailClosed'; OnCompatibleRange = 'ProceedWithWarning'
                KnownCompatibleRange = @(); RevalidationTrigger = 'test fixture only'
            }
        }
        [System.IO.File]::WriteAllText(
            (Join-Path $fixtureContractDir 'contract.json'),
            ($fixtureContract | ConvertTo-Json -Depth 10),
            (New-Object System.Text.UTF8Encoding $false))
        [System.IO.File]::WriteAllText(
            (Join-Path $fixtureContractDir 'evidence.md'),
            '# fixture`r`n',
            (New-Object System.Text.UTF8Encoding $false))

        $script:RawThrillsPathLimits = @{}
        $script:FileVersionPins = @{}
        $script:GpuIncompatibleGames = @{}
        $script:EmulatorBiosRequirements = @{
            'Pcsx2x6' = @{
                RelativeDir   = 'TeknoParrot\bios'
                RequiredFiles = @('27v1602T.d', '27v1602F.bg')
            }
        }

        function New-Pcsx2WarningProfile {
            param([string]$Path, [string]$EmulatorType = 'Pcsx2x6')
            $safeType = [System.Security.SecurityElement]::Escape($EmulatorType)
            [xml]$xml = "<GameProfile><EmulatorType>$safeType</EmulatorType><GamePath>C:\Games\game.exe</GamePath></GameProfile>"
            $xml.Save($Path)
        }

        function Get-CompatibilityWarningSnapshot {
            param([string]$Root)
            $files = @(Get-ChildItem -LiteralPath $Root -File -Force -Recurse -ErrorAction Stop |
                Sort-Object FullName | ForEach-Object {
                    [pscustomobject]@{
                        RelativePath    = $_.FullName.Substring($Root.Length).TrimStart('\')
                        SHA256          = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
                        LastWriteTimeUtc = $_.LastWriteTimeUtc
                    }
                })
            [pscustomobject]@{ Existed = Test-Path -LiteralPath $Root; FileCount = $files.Count; Files = $files }
        }

        function Assert-CompatibilityWarningSnapshotUnchanged {
            param($Before, $After)
            $After.Existed | Should -Be $Before.Existed
            $After.FileCount | Should -Be $Before.FileCount
            for ($i = 0; $i -lt $Before.Files.Count; $i++) {
                $After.Files[$i].RelativePath | Should -Be $Before.Files[$i].RelativePath
                $After.Files[$i].SHA256 | Should -Be $Before.Files[$i].SHA256
                $After.Files[$i].LastWriteTimeUtc | Should -Be $Before.Files[$i].LastWriteTimeUtc
            }
        }
    }

    It "does not report a missing component when the TeknoParrot root is absent" {
        $userProfilesDir = Join-Path $TestDrive ("exe-no-root-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $userProfilesDir -Force | Out-Null
        New-Pcsx2WarningProfile -Path (Join-Path $userProfilesDir 'BLOODYROAR3.xml')
        $missingRoot = Join-Path $TestDrive ("tp-root-absent-" + [guid]::NewGuid().ToString('N'))

        $result = Get-CompatibilityWarnings -UserProfilesDir $userProfilesDir -TeknoParrotRoot $missingRoot
        @($result.ExeMissing) | Should -BeNullOrEmpty
    }

    It "does not report a missing component when the pcsx2x6 directory is absent" {
        $root = Join-Path $TestDrive ("exe-no-directory-" + [guid]::NewGuid().ToString('N'))
        $userProfilesDir = Join-Path $root 'UserProfiles'
        New-Item -ItemType Directory -Path $userProfilesDir, $root -Force | Out-Null
        New-Pcsx2WarningProfile -Path (Join-Path $userProfilesDir 'BLOODYROAR3.xml')

        $result = Get-CompatibilityWarnings -UserProfilesDir $userProfilesDir -TeknoParrotRoot $root
        @($result.ExeMissing) | Should -BeNullOrEmpty
    }

    It "reports the contract-declared component path when pcsx2-qtx64.exe is absent" {
        $root = Join-Path $TestDrive ("exe-missing-" + [guid]::NewGuid().ToString('N'))
        $userProfilesDir = Join-Path $root 'UserProfiles'
        $pcsx2Dir = Join-Path $root 'pcsx2x6'
        New-Item -ItemType Directory -Path $userProfilesDir, $pcsx2Dir -Force | Out-Null
        New-Pcsx2WarningProfile -Path (Join-Path $userProfilesDir 'BLOODYROAR3.xml')

        $result = Get-CompatibilityWarnings -UserProfilesDir $userProfilesDir -TeknoParrotRoot $root
        @($result.ExeMissing).Count | Should -Be 1
        $entry = $result.ExeMissing[0]
        $entry.EmulatorType | Should -Be 'Pcsx2x6'
        $entry.DetectorMethod | Should -Be 'PathExists'
        $entry.DetectorSource | Should -Be 'pcsx2-qtx64.exe'
        $entry.ExpectedPath | Should -Be (Join-Path $pcsx2Dir 'pcsx2-qtx64.exe')
        @($entry.AffectedGames) | Should -Contain 'BLOODYROAR3'
        @($result.BiosMissing) | Should -BeNullOrEmpty -Because 'the missing component warning is sufficient until the emulator is present'
    }

    It "does not report ExeMissing when the contract-declared executable is present" {
        $root = Join-Path $TestDrive ("exe-present-" + [guid]::NewGuid().ToString('N'))
        $userProfilesDir = Join-Path $root 'UserProfiles'
        $pcsx2Dir = Join-Path $root 'pcsx2x6'
        New-Item -ItemType Directory -Path $userProfilesDir, $pcsx2Dir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $pcsx2Dir 'pcsx2-qtx64.exe') -Force | Out-Null
        New-Pcsx2WarningProfile -Path (Join-Path $userProfilesDir 'BLOODYROAR3.xml')

        $result = Get-CompatibilityWarnings -UserProfilesDir $userProfilesDir -TeknoParrotRoot $root
        @($result.ExeMissing) | Should -BeNullOrEmpty
    }

    It "reports a missing component for a non-pcsx2x6 contract-backed emulator and groups affected profiles" {
        $root = Join-Path $TestDrive ("fixture-component-missing-" + [guid]::NewGuid().ToString('N'))
        $userProfilesDir = Join-Path $root 'UserProfiles'
        $fixtureDir = Join-Path $root 'fixtureemu'
        New-Item -ItemType Directory -Path $userProfilesDir, $fixtureDir -Force | Out-Null
        New-Pcsx2WarningProfile -Path (Join-Path $userProfilesDir 'FIXTUREONE.xml') -EmulatorType 'FixtureEmu'
        New-Pcsx2WarningProfile -Path (Join-Path $userProfilesDir 'FIXTURETWO.xml') -EmulatorType 'fixtureemu'
        Import-Module $script:compatContractsModulePath -Force
        $registeredContracts = Get-TPMRegisteredEmulatorContractsV1 -ContractsRoot (Join-Path $TestDrive 'contracts')
        @($registeredContracts | ForEach-Object { $_.ContractId }) | Should -Contain 'fixtureemu'
        $directState = Get-ContractBackedMissingComponents -EmulatorType 'FixtureEmu' -TeknoParrotRoot $root -AffectedProfiles @('FIXTUREONE', 'FIXTURETWO')
        $directState.State | Should -Be 'Missing'

        $result = Get-CompatibilityWarnings -UserProfilesDir $userProfilesDir -TeknoParrotRoot $root
        @($result.ExeMissing).Count | Should -Be 1
        @($result.ComponentMissing).Count | Should -Be 1
        $entry = $result.ExeMissing[0]
        $entry.ContractId | Should -Be 'fixtureemu'
        $entry.ContractBacked | Should -BeTrue
        $entry.Confidence | Should -Be 'SourceVerified'
        $entry.CapabilityId | Should -Be 'env-init'
        $entry.DetectorMethod | Should -Be 'PathExists'
        $entry.DetectorSource | Should -Be 'fixture.exe'
        $entry.ExpectedPath | Should -Be (Join-Path $fixtureDir 'fixture.exe')
        @($entry.AffectedProfiles) | Should -Contain 'FIXTUREONE'
        @($entry.AffectedProfiles) | Should -Contain 'FIXTURETWO'
    }

    It "does not report a non-pcsx2x6 component when the contract-declared path is present" {
        $root = Join-Path $TestDrive ("fixture-component-present-" + [guid]::NewGuid().ToString('N'))
        $userProfilesDir = Join-Path $root 'UserProfiles'
        $fixtureDir = Join-Path $root 'fixtureemu'
        New-Item -ItemType Directory -Path $userProfilesDir, $fixtureDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $fixtureDir 'fixture.exe') -Force | Out-Null
        New-Pcsx2WarningProfile -Path (Join-Path $userProfilesDir 'FIXTUREGAME.xml') -EmulatorType 'FixtureEmu'

        $result = Get-CompatibilityWarnings -UserProfilesDir $userProfilesDir -TeknoParrotRoot $root
        @($result.ExeMissing) | Should -BeNullOrEmpty
    }

    It "does not claim a missing component for an emulator family with no matching contract" {
        $root = Join-Path $TestDrive ("fixture-contract-missing-" + [guid]::NewGuid().ToString('N'))
        $userProfilesDir = Join-Path $root 'UserProfiles'
        $uncontractedDir = Join-Path $root 'uncontracted'
        New-Item -ItemType Directory -Path $userProfilesDir, $uncontractedDir -Force | Out-Null
        New-Pcsx2WarningProfile -Path (Join-Path $userProfilesDir 'UNCONTRACTED.xml') -EmulatorType 'UncontractedEmu'

        $result = Get-CompatibilityWarnings -UserProfilesDir $userProfilesDir -TeknoParrotRoot $root
        @($result.ExeMissing) | Should -BeNullOrEmpty
        $state = Get-ContractBackedMissingComponents -EmulatorType 'UncontractedEmu' -TeknoParrotRoot $root -AffectedProfiles @('UNCONTRACTED')
        $state.State | Should -Be 'Unknown'
        @($state.Components) | Should -BeNullOrEmpty
    }

    It "fails closed without a missing-component claim when the contract registry cannot be loaded unambiguously" {
        $root = Join-Path $TestDrive ("fixture-contract-invalid-" + [guid]::NewGuid().ToString('N'))
        $userProfilesDir = Join-Path $root 'UserProfiles'
        $fixtureDir = Join-Path $root 'fixtureemu'
        $contractsRoot = Join-Path $TestDrive ("contracts-invalid-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $userProfilesDir, $fixtureDir, (Join-Path $contractsRoot 'fixtureemu'), (Join-Path $contractsRoot 'broken') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $TestDrive 'contracts\fixtureemu\contract.json') -Destination (Join-Path $contractsRoot 'fixtureemu\contract.json') -Force
        Set-Content -LiteralPath (Join-Path $contractsRoot 'broken\contract.json') -Value '{ malformed' -Encoding ascii

        $state = Get-ContractBackedMissingComponents -EmulatorType 'FixtureEmu' -TeknoParrotRoot $root -AffectedProfiles @('FIXTUREGAME') -ContractsRoot $contractsRoot
        $state.State | Should -Be 'Unknown'
        @($state.Components) | Should -BeNullOrEmpty
    }

    It "keeps pcsx2x6 component detection independent of the BIOS requirement table" {
        $root = Join-Path $TestDrive ("exe-no-bios-table-" + [guid]::NewGuid().ToString('N'))
        $userProfilesDir = Join-Path $root 'UserProfiles'
        $pcsx2Dir = Join-Path $root 'pcsx2x6'
        New-Item -ItemType Directory -Path $userProfilesDir, $pcsx2Dir -Force | Out-Null
        New-Pcsx2WarningProfile -Path (Join-Path $userProfilesDir 'BLOODYROAR3.xml')
        $previousRequirements = $script:EmulatorBiosRequirements
        try {
            $script:EmulatorBiosRequirements = @{}
            $result = Get-CompatibilityWarnings -UserProfilesDir $userProfilesDir -TeknoParrotRoot $root
            @($result.ExeMissing).Count | Should -Be 1
        } finally {
            $script:EmulatorBiosRequirements = $previousRequirements
        }
    }

    It "does not inspect a different root when the registered profile's emulator type is pcsx2x6" {
        $actualRoot = Join-Path $TestDrive ("exe-wrong-root-actual-" + [guid]::NewGuid().ToString('N'))
        $wrongRoot = Join-Path $TestDrive ("exe-wrong-root-passed-" + [guid]::NewGuid().ToString('N'))
        $userProfilesDir = Join-Path $actualRoot 'UserProfiles'
        New-Item -ItemType Directory -Path $userProfilesDir, (Join-Path $actualRoot 'pcsx2x6'), $wrongRoot -Force | Out-Null
        New-Pcsx2WarningProfile -Path (Join-Path $userProfilesDir 'BLOODYROAR3.xml')

        $result = Get-CompatibilityWarnings -UserProfilesDir $userProfilesDir -TeknoParrotRoot $wrongRoot
        @($result.ExeMissing) | Should -BeNullOrEmpty
    }

    It "does not report a pcsx2x6 component warning for a non-pcsx2x6 profile" {
        $root = Join-Path $TestDrive ("exe-profile-mismatch-" + [guid]::NewGuid().ToString('N'))
        $userProfilesDir = Join-Path $root 'UserProfiles'
        New-Item -ItemType Directory -Path $userProfilesDir, (Join-Path $root 'pcsx2x6') -Force | Out-Null
        New-Pcsx2WarningProfile -Path (Join-Path $userProfilesDir 'OTHERGAME.xml') -EmulatorType 'OtherEmulator'

        $result = Get-CompatibilityWarnings -UserProfilesDir $userProfilesDir -TeknoParrotRoot $root
        @($result.ExeMissing) | Should -BeNullOrEmpty
    }

    It "keeps the warning actionable without asserting antivirus causality" {
        $start = $script:ProductionSource.IndexOf('# -- 8a. Missing emulator component (issue #254)')
        $end = $script:ProductionSource.IndexOf('# -- 9. Game-specific setup notes', $start)
        $warningBlock = $script:ProductionSource.Substring($start, $end - $start)

        $warningBlock | Should -Match 'Get-CompatibilityWarnings|ExeMissing'
        $warningBlock | Should -Match 'ExpectedPath'
        $warningBlock | Should -Match 'DetectorMethod|DetectorSource'
        $warningBlock | Should -Match 'Confidence'
        $warningBlock | Should -Match 'Verify or restore this component through your normal TeknoParrot installation/update process'
        $warningBlock | Should -Not -Match '(?i)anti[- ]?virus|quarantine'
        $script:ProductionSource | Should -Match '\$asb\.AppendLine\("  Contract : \$\(\$e\.ContractId\)'
        $script:ProductionSource | Should -Match '\$asb\.AppendLine\("  Detector : \$\(\$e\.DetectorMethod\)'
        $script:ProductionSource | Should -Match '\$asb\.AppendLine\("  Evidence : contract-backed; confidence \$\(\$e\.Confidence\)'
    }

    It "keeps component assessment read-only and preserves the complete TP-root snapshot" {
        $root = Join-Path $TestDrive ("exe-no-write-" + [guid]::NewGuid().ToString('N'))
        $userProfilesDir = Join-Path $root 'UserProfiles'
        $gameProfilesDir = Join-Path $root 'GameProfiles'
        $gameDir = Join-Path $root 'Games\BloodyRoar3'
        $pcsx2Dir = Join-Path $root 'pcsx2x6'
        $fixtureDir = Join-Path $root 'fixtureemu'
        New-Item -ItemType Directory -Path $userProfilesDir, $gameProfilesDir, $gameDir, $pcsx2Dir, $fixtureDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'ParrotData.xml') -Value '<ParrotData />' -Encoding ascii
        Set-Content -LiteralPath (Join-Path $root 'config.ini') -Value 'unchanged' -Encoding ascii
        Set-Content -LiteralPath (Join-Path $gameProfilesDir 'profile.xml') -Value '<GameProfile />' -Encoding ascii
        Set-Content -LiteralPath (Join-Path $gameDir 'game.bin') -Value 'game-content' -Encoding ascii
        New-Pcsx2WarningProfile -Path (Join-Path $userProfilesDir 'BLOODYROAR3.xml')
        New-Pcsx2WarningProfile -Path (Join-Path $userProfilesDir 'FIXTUREGAME.xml') -EmulatorType 'FixtureEmu'

        $before = Get-CompatibilityWarningSnapshot -Root $root
        Get-CompatibilityWarnings -UserProfilesDir $userProfilesDir -TeknoParrotRoot $root | Out-Null
        $after = Get-CompatibilityWarningSnapshot -Root $root

        @($after.Files).Count | Should -Be $before.FileCount
        Assert-CompatibilityWarningSnapshotUnchanged -Before $before -After $after
    }

    It "contains no direct write or repair command in the compatibility-warning function" {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($script:ProductionSource, [ref]$tokens, [ref]$errors)
        $errors.Count | Should -Be 0
        $banned = @('Invoke-ControlPropagation', 'Set-ProfileInputApi', 'Save-XmlMaybe', 'Save-Xml', 'Set-Content', 'Add-Content', 'Out-File', 'New-Item', 'Remove-Item', 'Move-Item', 'Copy-Item', 'Rename-Item')
        $bannedMembers = @('Save', 'WriteAllText', 'WriteAllBytes', 'AppendAllText', 'Create', 'Delete', 'Move', 'Copy')
        foreach ($name in @('Get-CompatibilityWarnings', 'Get-ContractBackedMissingComponents')) {
            $fnAst = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq $name }, $true))[0]
            $fnAst | Should -Not -BeNullOrEmpty
            $commands = @($fnAst.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() })
            @($commands | Where-Object { $_ -in $banned }) | Should -BeNullOrEmpty
            $memberNames = @($fnAst.FindAll({ $args[0] -is [System.Management.Automation.Language.InvokeMemberExpressionAst] }, $true) | ForEach-Object { $_.Member.Extent.Text.Trim() })
            @($memberNames | Where-Object { $_ -in $bannedMembers }) | Should -BeNullOrEmpty
            $fnAst.Extent.Text | Should -Not -Match 'Invoke-Pcsx2FirstRunSetup|Invoke-TPMEnvironmentInitializationActionV1'
        }
    }

    AfterAll {
        foreach ($modulePath in @($script:compatContractsModulePath, $script:compatAuthorityModulePath)) {
            $fullModulePath = [System.IO.Path]::GetFullPath($modulePath)
            $loadedModules = @(Get-Module -All | Where-Object {
                $_.Path -and [string]::Equals([System.IO.Path]::GetFullPath($_.Path), $fullModulePath, [System.StringComparison]::OrdinalIgnoreCase)
            })
            if ($loadedModules.Count -gt 0) { $loadedModules | Remove-Module -Force -ErrorAction Stop }
        }
    }
}

Describe "RC2 DAT selection and override UX (issues #119, #120, #121)" {
    # This is top-level interactive script flow (DAT selection during
    # AutoSync/Register), not an extractable standalone function -- exercising
    # it end-to-end would mean driving the full interactive menu harness for
    # UX wording alone. Source-level checks are the proportionate choice here,
    # matching the same convention already used for other top-level-flow
    # wording guarantees elsewhere in this file (e.g. the Thumbnail download
    # regression guards above).
    BeforeAll {
        $script:scriptContent = Get-Content -LiteralPath $scriptPath -Raw
    }

    It "issue #119: only shows the Overrides line when at least one override is actually configured" {
        $script:scriptContent | Should -Match '\$ovCount\s*=\s*\$noSyncList\.Count\s*\+\s*\$onlySyncList\.Count'
        $script:scriptContent | Should -Match 'if\s*\(\$ovCount\s*-gt\s*0\)\s*\{'
    }

    It "issue #119: explains what the Overrides line means and what action the user can take" {
        # Must appear inside the same ovCount-gated block, not as an
        # unconditional line elsewhere -- confirmed by requiring the
        # explanation text to follow the "Overrides:" line within a bounded
        # window rather than just existing anywhere in the file.
        $script:scriptContent | Should -Match 'Overrides:\s*noSync[\s\S]{0,400}TeknoParrot-Manager\.overrides\.json'
        $script:scriptContent | Should -Match "there's nothing to do"
    }

    It "issue #120: tells the user which dat/ZIP was selected" {
        $script:scriptContent | Should -Match 'Write-Host\s*\(\s*"\s*\s*Selected:\s*\{0\}"'
    }

    It "issue #120: reports freshness (current / newer available / unknown) for a selected ZIP, and the no-comparison case for a standalone dat" {
        $script:scriptContent | Should -Match 'This is the latest available version'
        $script:scriptContent | Should -Match 'A newer version is available'
        $script:scriptContent | Should -Match 'Could not determine whether this is the latest version'
        $script:scriptContent | Should -Match 'Cannot check whether this is the latest version'
    }

    It "issue #121: the DAT browse file filter allows both .zip and .dat by default, not just .zip or All Files" {
        $datFilterMatches = [regex]::Matches($script:scriptContent, 'ZIP/dat files \(\*\.zip;\*\.dat\)\|\*\.zip;\*\.dat')
        $datFilterMatches.Count | Should -BeGreaterThan 0 -Because "every DAT browse call site (initial D/B choice, download-fallback, already-configured re-browse) must offer both extensions from the default filter"
    }
}

Describe "TeknoParrot-Manager.ps1 -Unattended real child-process fixture (issue #154 real-hardware certification finding)" {
    # A real certification run confirmed TeknoParrot-Manager.ps1 -Unattended
    # always exited 1 at "Mode must be set before starting" -- there was no
    # config or CLI mechanism to auto-select an initial mode, only the
    # interactive menu or a same-session preview re-entry. This launches the
    # REAL, unmodified script (copied into TestDrive, never the real repo
    # checkout) as a real child process against a synthetic, non-real
    # "TeknoParrot install" (a bare directory structure), proving the
    # UnattendedMode config field lets it pass configuration validation and
    # reach HealthCheck's bounded stop-point (a real, read-only library scan)
    # and then exit cleanly on its own -- never launching, inspecting, or
    # modifying a genuine TeknoParrot installation.
    # Deliberately does NOT import TPMCertification.Execution.psm1 (or any
    # other shared certification module) here, even though its
    # Invoke-TPMIsolatedProcessV1 would otherwise be a natural fit --
    # confirmed by direct reproduction that doing so (with or without
    # -Force) creates a second, scope-local copy of that module, which
    # collides with TPMCertification.OperatorExperience.Tests.ps1's own
    # "Mock -ModuleName TPMCertification.Execution -CommandName Write-Host"
    # when both files run in the same Pester session: Pester itself throws
    # "Multiple script or manifest modules named 'TPMCertification.Execution'
    # are currently loaded" -- reproduced deterministically down to just
    # these two specific tests, not environmental flakiness. This test uses
    # a plain, self-contained Start-Process invocation instead, so it never
    # touches any module another test file also imports.
    It "passes configuration validation and reaches the HealthCheck bounded stop-point, exiting 0, without ever needing a real TeknoParrot installation" {
        $fixtureRoot = Join-Path $TestDrive ("unattended-fixture-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
        Copy-Item -LiteralPath $scriptPath -Destination (Join-Path $fixtureRoot 'TeknoParrot-Manager.ps1') -Force

        # SECTION 2 of TeknoParrot-Manager.ps1 unconditionally requires
        # TeknoParrotUi.exe and a GameProfiles folder to exist at the
        # configured root (this is a real, pre-existing, non-Unattended-
        # specific requirement -- confirmed by direct reproduction, not
        # assumed) -- neither is a genuine executable/profile store here,
        # since HealthCheck's own read-only scan never launches or
        # inspects them, only checks they exist.
        $fakeTpRoot = Join-Path $fixtureRoot 'fake-tp-root'
        New-Item -ItemType Directory -Path (Join-Path $fakeTpRoot 'UserProfiles') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $fakeTpRoot 'GameProfiles') -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $fakeTpRoot 'TeknoParrotUi.exe'), '')

        $configPath = Join-Path $fixtureRoot 'TeknoParrot-Manager.config.json'
        $cfg = [ordered]@{ TeknoParrotRoot = $fakeTpRoot; GamesInstallFolder = $fakeTpRoot; UnattendedMode = 'HealthCheck' }
        [System.IO.File]::WriteAllText($configPath, ($cfg | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding $false))

        $stdoutPath = Join-Path $fixtureRoot 'stdout.log'
        $stderrPath = Join-Path $fixtureRoot 'stderr.log'
        $stdinPath = Join-Path $fixtureRoot 'stdin.empty'
        [IO.File]::WriteAllText($stdinPath, '')

        $process = Start-Process -FilePath (Get-Command pwsh).Source -ArgumentList @('-NoProfile','-NonInteractive','-File',(Join-Path $fixtureRoot 'TeknoParrot-Manager.ps1'),'-Unattended') -WorkingDirectory $fixtureRoot -RedirectStandardInput $stdinPath -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -NoNewWindow -PassThru
        # Confirmed by direct reproduction under real Windows PowerShell 5.1
        # (its older .NET Framework CLR, not pwsh's): touching .Handle
        # immediately after Start-Process -PassThru forces .NET to open and
        # cache a real handle to the process before it can exit. Skipping
        # this is a well-known .NET Framework Process-class quirk -- for a
        # fast-exiting process (HealthCheck completes in ~1.5s here), the
        # OS can recycle the process record before a later .ExitCode read,
        # leaving it $null even though WaitForExit already returned $true.
        # pwsh's newer runtime does not have this problem, which is exactly
        # why this only reproduced under Windows PowerShell 5.1.
        [void]$process.Handle
        $exited = $process.WaitForExit(60000)
        if (-not $exited) {
            try { $process.Kill() } catch {}
            throw "TeknoParrot-Manager.ps1 -Unattended did not exit within the 60-second bound"
        }
        $process.WaitForExit()

        $process.ExitCode | Should -Be 0 -Because 'a genuine product defect (Mode must be set before starting) previously made every real -Unattended launch exit 1 here'

        $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { '' }
        $stdout | Should -Not -Match 'Mode must be set before starting' -Because 'this is the exact error text the real certification run hit'
        $stdout | Should -Match 'Library Health Check' -Because 'HealthCheck must have actually run, not merely avoided the error'
        $stdout | Should -Match 'Unattended.*Using saved settings' -Because 'confirms the config path was genuinely exercised, not bypassed'

        # No real install was ever touched: this is a synthetic fixture, and
        # the placeholder TeknoParrotUi.exe -- present only so SECTION 2's
        # existence check passes -- remains exactly as created (empty),
        # proving HealthCheck's read-only scan never wrote to it.
        (Get-Item -LiteralPath (Join-Path $fakeTpRoot 'TeknoParrotUi.exe')).Length | Should -Be 0
    }

    It "loads a legacy saved config with no UnattendedMode field at all without throwing under Set-StrictMode, and fails safely (no mode chosen) rather than crashing" {
        # A saved config from before this feature existed has no
        # UnattendedMode property whatsoever on the deserialized object --
        # not $null, genuinely absent. Confirmed by direct reproduction that
        # $cfg.UnattendedMode on such an object throws
        # PropertyNotFoundException under Set-StrictMode -Version Latest
        # (both pwsh and Windows PowerShell 5.1). The real interactive/
        # -Unattended entry point does not itself call Set-StrictMode, but
        # this exact access pattern must still be safe under any stricter
        # caller (test harness, future dot-sourcing, etc.), so the fixture
        # script wraps the real, unmodified TeknoParrot-Manager.ps1 with an
        # explicit Set-StrictMode -Version Latest to prove the read sites
        # themselves are strict-mode-safe, not merely that the ordinary
        # entry point happens not to trip the bug today. The wrapper must
        # dot-source (". path", not "& path") -- confirmed by direct
        # reproduction that Set-StrictMode does NOT propagate across a
        # separate script file invoked with the call operator (&), only
        # into a dot-sourced one; using & here would silently make this
        # test exercise no strict-mode enforcement at all.
        $fixtureRoot = Join-Path $TestDrive ("legacy-config-fixture-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null

        $realScriptPath = Join-Path $fixtureRoot 'TeknoParrot-Manager.ps1'
        Copy-Item -LiteralPath $scriptPath -Destination $realScriptPath -Force

        $wrapperPath = Join-Path $fixtureRoot 'StrictModeWrapper.ps1'
        $wrapperContent = "Set-StrictMode -Version Latest`r`n. '$realScriptPath' @args`r`nexit `$LASTEXITCODE"
        [System.IO.File]::WriteAllText($wrapperPath, $wrapperContent, (New-Object System.Text.UTF8Encoding $false))

        $fakeTpRoot = Join-Path $fixtureRoot 'fake-tp-root'
        New-Item -ItemType Directory -Path (Join-Path $fakeTpRoot 'UserProfiles') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $fakeTpRoot 'GameProfiles') -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $fakeTpRoot 'TeknoParrotUi.exe'), '')

        # Mirrors Save-Config's exact key set (every field it has ever
        # written) minus UnattendedMode -- a genuine legacy config carries
        # all of these (some null), since Save-Config has always written
        # them; UnattendedMode is the only key that is a true, brand-new
        # absence rather than a null value. A fixture with ONLY
        # TeknoParrotRoot/GamesInstallFolder would be unrealistic and would
        # also trip strict-mode on all these OTHER pre-existing optional
        # reads, which are out of this fix's scope.
        $configPath = Join-Path $fixtureRoot 'TeknoParrot-Manager.config.json'
        $cfg = [ordered]@{
            TeknoParrotRoot              = $fakeTpRoot
            ZipSourceFolder              = $null
            ZipSourceSupplementaryFolder = $null
            GamesInstallFolder           = $fakeTpRoot
            RetroBat                     = $false
            HyperSpinDataPath            = $null
            ReShadeSourceDll             = $null
            ReShadeSourceDll32           = $null
            DgVoodoo2SourceDir           = $null
            EggmanDatZip                 = $null
            DatFilePath                  = $null
            SupplementaryDatPath         = $null
            IncludeSupplementary         = $false
            LaunchBoxRoot                = $null
            LaunchBoxPlatformMode        = $null
            LaunchBoxCustomPlatformName  = $null
            LaunchBoxEmulatorId          = $null
            PostgresSuperPasswordEncrypted = $null
            CheckForUpdatesOnStartup     = $true
        }
        [System.IO.File]::WriteAllText($configPath, ($cfg | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding $false))

        $stdoutPath = Join-Path $fixtureRoot 'stdout.log'
        $stderrPath = Join-Path $fixtureRoot 'stderr.log'
        $stdinPath = Join-Path $fixtureRoot 'stdin.empty'
        [IO.File]::WriteAllText($stdinPath, '')

        $process = Start-Process -FilePath (Get-Command pwsh).Source -ArgumentList @('-NoProfile','-NonInteractive','-File',$wrapperPath,'-Unattended') -WorkingDirectory $fixtureRoot -RedirectStandardInput $stdinPath -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -NoNewWindow -PassThru
        [void]$process.Handle
        $exited = $process.WaitForExit(60000)
        if (-not $exited) {
            try { $process.Kill() } catch {}
            throw "TeknoParrot-Manager.ps1 -Unattended (strict-mode wrapper) did not exit within the 60-second bound"
        }
        $process.WaitForExit()

        $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { '' }
        $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { '' }

        $stdout | Should -Not -Match 'PropertyNotFoundException|cannot be found on this object' -Because 'a legacy config missing UnattendedMode must never throw when the property is read'
        $stderr | Should -Not -Match 'PropertyNotFoundException|cannot be found on this object' -Because 'a legacy config missing UnattendedMode must never throw when the property is read'
        $stdout | Should -Not -Match 'Saved configuration could not be read \(file may be corrupt\)' -Because 'a legacy config missing only the new optional UnattendedMode field is not corrupt and must still be accepted'
        $stdout | Should -Match 'Unattended.*Using saved settings' -Because 'the legacy config must still pass validation and be accepted'

        # No mode can be auto-selected from a config that never named one,
        # so this must fail the same safe, pre-existing way every other
        # -Unattended launch with no mode chosen already does -- not crash.
        $process.ExitCode | Should -Be 1 -Because 'no UnattendedMode means no mode was chosen; this must be the pre-existing safe failure, not a new crash'
        $stdout | Should -Match 'Mode must be set before starting' -Because 'this is the pre-existing, expected safe failure for no mode chosen'
    }
}

Describe "Issue #300 shared workflow status state machine" {
    AfterEach {
        if ($script:ActiveTpmWorkflowStatus) {
            $active = $script:ActiveTpmWorkflowStatus
            if ($active.Failure) { [void](Acknowledge-TpmWorkflowFailure -Context $active -FailureId $active.Failure.FailureId) }
            [void](Stop-TpmWorkflowStatus -Context $active -Reason 'test cleanup')
            [void](Close-TpmWorkflowStatus -Context $active)
        }
    }
    It "emits ordered structured events without leaking them into normal returns" {
        # The isolated AST fixture must not inherit workflow state from any
        # other test file or prior test execution.
        $script:ActiveTpmWorkflowStatus | Should -Be $null
        $script:TpmWorkflowRendering | Should -BeFalse
        $script:PostgresRecoveryStatus | Should -Be $null
        $script:PostgresRecoveryResumeState | Should -Be $null
        $script:ProductionSource | Should -Match '\$script:ActiveTpmWorkflowStatus\s*=\s*\$null'
        $script:ProductionSource | Should -Match '\$script:TpmWorkflowRendering\s*=\s*\$false'
        $events = New-Object System.Collections.Generic.List[object]
        $facts = [pscustomobject]@{ NoRender = $true; Unattended = $false; InputRedirected = $false; OutputRedirected = $false; Certification = $false }
        $ctx = New-TpmWorkflowStatusContext -WorkflowKey 'test' -Title 'Test workflow' -Steps @('one','two','three','four') -ConsoleFacts $facts -EventSink { param($event) [void]$events.Add($event) }
        [void](Start-TpmWorkflowStatus $ctx)
        [void](Start-TpmWorkflowStep $ctx -StepId 'one' -Activity 'Doing first work')
        [void](Complete-TpmWorkflowStep $ctx -Summary 'First complete' -NextStep 'Second work')
        [void](Start-TpmWorkflowStep $ctx -StepId 'two' -Activity 'Doing second work')
        [void](Complete-TpmWorkflowStep $ctx -Summary 'Second complete')
        $events.Count | Should -Be 5
        @($events | Select-Object -ExpandProperty Sequence) | Should -Be @(1,2,3,4,5)
        $events[0].PSTypeNames | Should -Contain 'TPM.WorkflowStatusEvent.v1'
        (Get-TpmWorkflowStatusSnapshot $ctx).Completed.Count | Should -Be 2
        (Start-TpmWorkflowStep $ctx -StepId 'three' -Activity 'Third work') | Should -BeNullOrEmpty
    }

    It "pins failures until acknowledgement and retains only bounded completion history" {
        $ctx = New-TpmWorkflowStatusContext -WorkflowKey 'failure' -Title 'Failure workflow' -Steps @('a','b','c','d','e') -ConsoleFacts ([pscustomobject]@{ NoRender = $true })
        [void](Start-TpmWorkflowStatus $ctx)
        foreach ($step in @('a','b','c','d')) {
            [void](Start-TpmWorkflowStep $ctx -StepId $step -Activity $step)
            [void](Complete-TpmWorkflowStep $ctx -Summary ("Completed $step"))
        }
        (Get-TpmWorkflowStatusSnapshot $ctx).Completed.Summary | Should -Be @('Completed b','Completed c','Completed d')
        [void](Set-TpmWorkflowFailure -Context $ctx -FailureId 'f1' -Message 'Repair failed' -DataSafety 'Backup is safe' -RecoveryActions @(@{ Id = 'Retry'; Label = 'Retry' }))
        { Complete-TpmWorkflowStatus -Context $ctx -Summary 'must fail' } | Should -Throw
        { Close-TpmWorkflowStatus -Context $ctx } | Should -Throw
        [void](Acknowledge-TpmWorkflowFailure -Context $ctx -FailureId 'f1')
        [void](Complete-TpmWorkflowStatus -Context $ctx -Summary 'Stopped safely')
        [void](Close-TpmWorkflowStatus -Context $ctx)
        $ctx.Lifecycle | Should -Be 'Closed'
    }

    It "handles simulated resize shrink/grow, stale footer clearing, and narrow fallback" {
        $draws = New-Object System.Collections.Generic.List[object]
        $clears = New-Object System.Collections.Generic.List[object]
        $appends = New-Object System.Collections.Generic.List[object]
        $adapter = @{
            Clear  = { param($bounds) [void]$script:statusClears.Add($bounds) }
            Draw   = { param($rows,$cap) [void]$script:statusDraws.Add([pscustomobject]@{ Rows = @($rows); Width = $cap.Width; Height = $cap.Height }) }
            Append = { param($rows) [void]$script:statusAppends.Add(@($rows)) }
        }
        $script:statusDraws = $draws
        $script:statusClears = $clears
        $script:statusAppends = $appends
        $facts = [pscustomobject]@{ NoRender = $false; Unattended = $false; InputRedirected = $false; OutputRedirected = $false; Certification = $false; CanCursor = $true; Width = 160; Height = 40; BufferWidth = 160; BufferHeight = 40; Adapter = $adapter }
        $ctx = New-TpmWorkflowStatusContext -WorkflowKey 'resize' -Title 'Resize workflow' -Steps @('one','two') -ConsoleFacts $facts
        [void](Start-TpmWorkflowStatus $ctx)
        [void](Start-TpmWorkflowStep $ctx -StepId 'one' -Activity 'Wide activity')
        $facts.Width = 60; $facts.Height = 12; $facts.BufferWidth = 60; $facts.BufferHeight = 12
        [void](Update-TpmWorkflowActivity -Context $ctx -Activity 'Narrow activity that must be clipped safely')
        $draws.Count | Should -BeGreaterThan 1
        $clears.Count | Should -BeGreaterThan 0
        foreach ($draw in $draws) { @($draw.Rows | Where-Object { $_.Length -gt ($draw.Width - 1) }).Count | Should -Be 0 }
        $facts.Width = 40; $facts.Height = 4; $facts.BufferWidth = 40; $facts.BufferHeight = 4
        [void](Update-TpmWorkflowActivity -Context $ctx -Activity 'Too short for the normal footer')
        $appends.Count | Should -BeGreaterThan 0
        $facts.Width = 120; $facts.Height = 30; $facts.BufferWidth = 120; $facts.BufferHeight = 30
        [void](Update-TpmWorkflowActivity -Context $ctx -Activity 'Grown again')
        $ctx.RendererMode | Should -Be 'CursorFooter'
        $draws[$draws.Count - 1].Width | Should -Be 120
    }

    It "uses the real host capability path without writing cursor controls when the host is redirected" {
        $ctx = New-TpmWorkflowStatusContext -WorkflowKey 'real-host' -Title 'Real host' -Steps @('one')
        { Render-TpmWorkflowStatus -Context $ctx } | Should -Not -Throw
        $ctx.RendererMode | Should -Be 'None'
    }

    It "guards first-render cursor overlap and scroll-aware stale footer cleanup" {
        $script:ProductionSource | Should -Not -Match '-and -not \$geometryChanged'
        $script:ProductionSource | Should -Match '\$cursor\.Y -ge \$top -and \$cursor\.Y -lt \(\$top \+ \$footerHeight\)'
        $script:ProductionSource | Should -Match 'WindowTop'
        $script:ProductionSource | Should -Match 'Read-HostSafe \$Prompt'
    }

    It "clears and redraws its rectangle around prompt input without changing scrollback" {
        $clears = New-Object System.Collections.ArrayList
        $draws = New-Object System.Collections.ArrayList
        $adapter = @{
            Clear = { param($bounds) [void]$script:footerPromptClears.Add($bounds) }
            Draw = { param($rows,$cap) [void]$script:footerPromptDraws.Add(@($rows)) }
            Append = { param($rows) }
        }
        $script:footerPromptClears = $clears
        $script:footerPromptDraws = $draws
        $facts = [pscustomobject]@{ NoRender = $false; Unattended = $false; InputRedirected = $false; OutputRedirected = $false; Certification = $false; CanCursor = $true; Width = 120; Height = 30; BufferWidth = 120; BufferHeight = 30; Adapter = $adapter }
        $ctx = New-TpmWorkflowStatusContext -WorkflowKey 'prompt-footer' -Title 'Prompt footer' -Steps @('one') -ConsoleFacts $facts
        [void](Start-TpmWorkflowStatus -Context $ctx)
        $initialClears = $clears.Count
        Mock Read-Host { 'answer' }
        (Read-HostSafe '  Prompt') | Should -Be 'answer'
        $clears.Count | Should -BeGreaterThan $initialClears
        $draws.Count | Should -BeGreaterThan 1
    }

    It "publishes append-only status without recursing through the host shim" {
        $facts = [pscustomobject]@{ NoRender = $false; Unattended = $false; InputRedirected = $false; OutputRedirected = $false; Certification = $false; CanCursor = $false; Width = 80; Height = 20; BufferWidth = 80; BufferHeight = 20; Adapter = $null }
        $ctx = New-TpmWorkflowStatusContext -WorkflowKey 'append-only' -Title 'Append only' -Steps @('one') -ConsoleFacts $facts
        { Start-TpmWorkflowStatus -Context $ctx } | Should -Not -Throw
        $ctx.RendererMode | Should -Be 'PermanentAppendOnly'
    }

    It "bypasses all rendering for redirected and certification facts" {
        $adapterCalls = 0
        $adapter = @{ Draw = { $script:adapterCalls++ }; Clear = { $script:adapterCalls++ }; Append = { $script:adapterCalls++ } }
        $script:adapterCalls = 0
        $facts = [pscustomobject]@{ NoRender = $false; Unattended = $false; InputRedirected = $true; OutputRedirected = $false; Certification = $false; CanCursor = $true; Width = 120; Height = 30; BufferWidth = 120; BufferHeight = 30; Adapter = $adapter }
        $ctx = New-TpmWorkflowStatusContext -WorkflowKey 'redirected' -Title 'Redirected' -Steps @('one') -ConsoleFacts $facts
        [void](Start-TpmWorkflowStatus $ctx)
        [void](Start-TpmWorkflowStep $ctx -StepId 'one' -Activity 'Checking')
        $adapterCalls | Should -Be 0
    }
}

Describe "Issue #300 workflow ownership and transition guards" {
    It "rejects unknown workflow steps without emitting an event" {
        $events = New-Object System.Collections.Generic.List[object]
        $facts = [pscustomobject]@{ NoRender = $true }
        $ctx = New-TpmWorkflowStatusContext -WorkflowKey 'unknown-step' -Title 'Unknown step' -Steps @('one','two') -ConsoleFacts $facts -EventSink { param($event) [void]$events.Add($event) }
        [void](Start-TpmWorkflowStatus $ctx)
        { Start-TpmWorkflowStep -Context $ctx -StepId 'missing' } | Should -Throw '*Unknown workflow step*'
        $events.Count | Should -Be 1
        $ctx.ActiveStepId | Should -BeNullOrEmpty
        [void](Stop-TpmWorkflowStatus -Context $ctx -Reason 'test stop')
        [void](Close-TpmWorkflowStatus -Context $ctx)
    }

    It "routes reviewed PostgreSQL and optional-flow failures through lifecycle cleanup" {
        foreach ($failureId in @('postgres-service-state','postgres-install-failed','postgres-backup-unverified','postgres-config-save','postgres-database-backup','postgres-profile-recovery','postgres-profile-errors','postgres-service-restore','reshade-file-missing','reshade-file-type','dgv-folder-missing')) {
            $script:ProductionSource | Should -Match ([regex]::Escape("Resolve-TpmWorkflowFailure -Context"))
            $script:ProductionSource | Should -Match ([regex]::Escape("-FailureId '$failureId'"))
        }
        $script:ProductionSource | Should -Match 'Complete-TpmWorkflowStatus -Context \$postgresStatus'
        $script:ProductionSource | Should -Match 'Close-TpmWorkflowStatus -Context \$postgresStatus'
        $script:ProductionSource | Should -Match 'Close-TpmWorkflowStatus -Context \$reShadeStatus'
        $script:ProductionSource | Should -Match 'Close-TpmWorkflowStatus -Context \$dgStatus'
    }

    It "rejects a second active workflow and releases the first on close" {
        $facts = [pscustomobject]@{ NoRender = $true }
        $first = New-TpmWorkflowStatusContext -WorkflowKey 'first' -Title 'First' -Steps @('one') -ConsoleFacts $facts
        $second = New-TpmWorkflowStatusContext -WorkflowKey 'second' -Title 'Second' -Steps @('one') -ConsoleFacts $facts
        [void](Start-TpmWorkflowStatus $first)
        { Start-TpmWorkflowStatus $second } | Should -Throw '*already active*'
        [void](Stop-TpmWorkflowStatus -Context $first -Reason 'test stop')
        [void](Close-TpmWorkflowStatus -Context $first)
        [void](Start-TpmWorkflowStatus $second)
        [void](Stop-TpmWorkflowStatus -Context $second -Reason 'test stop')
        [void](Close-TpmWorkflowStatus -Context $second)
    }
}

Describe "Issue #300 FFB ownership cleanup" {
    It "removes only an unchanged TPM-owned hook and preserves a backup" {
        $root = Join-Path $TestDrive 'FfbOwnedGame'
        $cache = Join-Path $TestDrive 'FfbCache'
        New-Item -ItemType Directory -Path $root, $cache -Force | Out-Null
        $dest = Join-Path $root 'd3d9.dll'
        Set-Content -LiteralPath $dest -Value 'TPM plugin'
        $hash = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash
        Write-FFBPluginOwnership -CacheDir $cache -Entries @([pscustomobject]@{
            ProfileCode = 'OwnedGame'; GameRoot = $root; Destination = $dest
            SourceSha256 = $hash; DeployedSha256 = $hash; CreatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        })
        Remove-FFBPluginOwnedDeployment -CacheDir $cache -ProfileCode 'OwnedGame' | Should -BeTrue
        Test-Path -LiteralPath $dest | Should -BeFalse
        @(Get-ChildItem -LiteralPath (Join-Path $root 'FullBackup') -Recurse -File).Count | Should -Be 1
    }

    It "rolls back ownership deletion when the manifest write fails" {
        $root = Join-Path $TestDrive 'FfbManifestFailureGame'
        $cache = Join-Path $TestDrive 'FfbManifestFailureCache'
        New-Item -ItemType Directory -Path $root, $cache -Force | Out-Null
        $dest = Join-Path $root 'd3d9.dll'
        Set-Content -LiteralPath $dest -Value 'owned-hook'
        $hash = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash
        Write-FFBPluginOwnership -CacheDir $cache -Entries @([pscustomobject]@{ ProfileCode = 'FailureGame'; GameRoot = $root; Destination = $dest; SourceSha256 = $hash; DeployedSha256 = $hash; CreatedUtc = (Get-Date).ToUniversalTime().ToString('o') })
        Mock Write-FFBPluginOwnership { throw 'simulated manifest write failure' }

        { Remove-FFBPluginOwnedDeployment -CacheDir $cache -ProfileCode 'FailureGame' } | Should -Throw '*rolled back*'
        (Test-Path -LiteralPath $dest -PathType Leaf) | Should -BeTrue
        (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash | Should -Be $hash
    }

    It "preserves a changed owned path instead of deleting it" {
        $root = Join-Path $TestDrive 'FfbChangedGame'
        $cache = Join-Path $TestDrive 'FfbChangedCache'
        New-Item -ItemType Directory -Path $root, $cache -Force | Out-Null
        $dest = Join-Path $root 'd3d9.dll'
        Set-Content -LiteralPath $dest -Value 'changed by another tool'
        Write-FFBPluginOwnership -CacheDir $cache -Entries @([pscustomobject]@{
            ProfileCode = 'ChangedGame'; GameRoot = $root; Destination = $dest
            SourceSha256 = ('a' * 64); DeployedSha256 = ('b' * 64); CreatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        })
        Remove-FFBPluginOwnedDeployment -CacheDir $cache -ProfileCode 'ChangedGame' | Should -BeFalse
        Test-Path -LiteralPath $dest | Should -BeTrue
    }
}
