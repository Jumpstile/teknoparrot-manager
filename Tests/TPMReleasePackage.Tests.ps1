#Requires -Version 5.1
#Requires -Module Pester

BeforeAll {
function New-PackageSourceFixture {
    param([Parameter(Mandatory = $true)][string]$Destination, [Parameter(Mandatory = $true)][string]$RepositoryRoot)
    $map = @(Get-TPMReleasePackageFileMapV1 -SourceRoot $RepositoryRoot)
    foreach ($item in $map) {
        $source = Join-Path $RepositoryRoot ($item.SourcePath.Replace('/', [IO.Path]::DirectorySeparatorChar))
        $target = Join-Path $Destination ($item.SourcePath.Replace('/', [IO.Path]::DirectorySeparatorChar))
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force
    }
    foreach ($name in @('evidence.md','experiments.md')) {
        $source = Join-Path $RepositoryRoot "contracts/pcsx2x6/$name"
        $target = Join-Path $Destination "contracts/pcsx2x6/$name"
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force
    }
}


function Copy-PackageArchiveFixture {
    param([string]$Source, [string]$Destination)
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Add-PackageArchiveEntry {
    param([string]$ZipPath, [string]$Name, [string]$Text, [switch]$Replace)
    $archive = [System.IO.Compression.ZipFile]::Open($ZipPath, [System.IO.Compression.ZipArchiveMode]::Update)
    try {
        if ($Replace) {
            $existing = $archive.GetEntry($Name)
            if ($null -ne $existing) { $existing.Delete() }
        }
        $entry = $archive.CreateEntry($Name)
        $stream = $entry.Open()
        try {
            $writer = New-Object System.IO.StreamWriter($stream, (New-Object System.Text.UTF8Encoding($false)))
            try { $writer.Write($Text) } finally { $writer.Dispose() }
        } finally { $stream.Dispose() }
    } finally { $archive.Dispose() }
}

function Remove-PackageArchiveEntry {
    param([string]$ZipPath, [string]$Name)
    $archive = [System.IO.Compression.ZipFile]::Open($ZipPath, [System.IO.Compression.ZipArchiveMode]::Update)
    try { $entry = $archive.GetEntry($Name); if ($null -ne $entry) { $entry.Delete() } }
    finally { $archive.Dispose() }
}

function Corrupt-PackageArchiveCompressedMember {
    param([Parameter(Mandatory = $true)][string]$ZipPath, [Parameter(Mandatory = $true)][string]$Name)
    $bytes = [IO.File]::ReadAllBytes($ZipPath)
    $eocd = -1
    for ($offset = $bytes.Length - 22; $offset -ge [Math]::Max(0, $bytes.Length - 65557); $offset--) {
        if ([BitConverter]::ToUInt32($bytes, $offset) -eq 0x06054b50) { $eocd = $offset; break }
    }
    if ($eocd -lt 0) { throw 'Synthetic ZIP end record missing' }
    $entryCount = [BitConverter]::ToUInt16($bytes, $eocd + 10)
    $centralOffset = [BitConverter]::ToUInt32($bytes, $eocd + 16)
    $cursor = [int]$centralOffset
    for ($index = 0; $index -lt $entryCount; $index++) {
        if ([BitConverter]::ToUInt32($bytes, $cursor) -ne 0x02014b50) { throw 'Synthetic ZIP central directory malformed' }
        $method = [BitConverter]::ToUInt16($bytes, $cursor + 10)
        $compressedLength = [BitConverter]::ToUInt32($bytes, $cursor + 20)
        $nameLength = [BitConverter]::ToUInt16($bytes, $cursor + 28)
        $extraLength = [BitConverter]::ToUInt16($bytes, $cursor + 30)
        $commentLength = [BitConverter]::ToUInt16($bytes, $cursor + 32)
        $entryName = [Text.Encoding]::UTF8.GetString($bytes, $cursor + 46, $nameLength)
        if ($entryName -ceq $Name) {
            if ($method -ne 8 -or $compressedLength -lt 4) { throw \"Member $Name was not Deflate-compressed for this test\" }
            $localOffset = [BitConverter]::ToUInt32($bytes, $cursor + 42)
            $localNameLength = [BitConverter]::ToUInt16($bytes, $localOffset + 26)
            $localExtraLength = [BitConverter]::ToUInt16($bytes, $localOffset + 28)
            $dataOffset = [int]$localOffset + 30 + $localNameLength + $localExtraLength
            $corruptAt = $dataOffset + [int]($compressedLength / 2)
            $bytes[$corruptAt] = $bytes[$corruptAt] -bxor 0xFF
            [IO.File]::WriteAllBytes($ZipPath, $bytes)
            return
        }
        $cursor += 46 + $nameLength + $extraLength + $commentLength
    }
    throw \"Synthetic ZIP member missing: $Name\"
}

function Expand-PackageArchiveFixture {
    param([string]$ZipPath, [string]$Destination)
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $Destination)
    return $Destination
}


    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:packageInitialModules = @(Get-Module -All)
    $script:packageOwnedModulePaths = @(
        [IO.Path]::GetFullPath((Join-Path $script:repoRoot 'scripts/TPMReleasePackage.Core.psm1')),
        [IO.Path]::GetFullPath((Join-Path $script:repoRoot 'scripts/TPMCertification.Contracts.psm1')),
        [IO.Path]::GetFullPath((Join-Path $script:repoRoot 'scripts/TPMCertification.Authority.psm1'))
    )
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Import-Module (Join-Path $script:repoRoot 'scripts/TPMReleasePackage.Core.psm1') -Force
    Import-Module (Join-Path $script:repoRoot 'scripts/TPMCertification.Contracts.psm1') -Force
    $script:fixtureSource = Join-Path $TestDrive 'source fixture [package]'
    New-Item -ItemType Directory -Path $script:fixtureSource -Force | Out-Null
    New-PackageSourceFixture -Destination $script:fixtureSource -RepositoryRoot $script:repoRoot
    $script:validZip = Join-Path $TestDrive 'valid package [fixture].zip'
    & (Join-Path $script:repoRoot 'scripts/New-TPMReleasePackage.ps1') -OutputPath $script:validZip -SourceRoot $script:fixtureSource | Out-Null
}

Describe 'Strict user release package contents' {
    It 'accepts the complete source-mapped allowlist and byte-identical files' {
        $result = Test-TPMReleasePackageArchiveV1 -ZipPath $script:validZip -SourceRoot $script:fixtureSource
        $result.Valid | Should -BeTrue
        $result.FileCount | Should -Be 341
        $result.CrosshairPngCount | Should -Be 321
        $result.PathLeakCount | Should -Be 0
        { & (Join-Path $script:repoRoot 'Tests/Test-ReleasePackage.ps1') -ZipPath $script:validZip } | Should -Not -Throw
    }

    It 'builds from a fresh stock Windows PowerShell process without ambient compression assemblies' {
        $builder = Join-Path $script:repoRoot 'scripts/New-TPMReleasePackage.ps1'
        $output = Join-Path $TestDrive 'stock powershell package.zip'
        $powershell = Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $powershell
        $startInfo.Arguments = '-NoProfile -File "{0}" -OutputPath "{1}" -SourceRoot "{2}"' -f $builder, $output, $script:fixtureSource
        $startInfo.WorkingDirectory = $script:repoRoot
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true
        $startInfo.EnvironmentVariables['PSModulePath'] = @(
            (Join-Path $env:ProgramFiles 'WindowsPowerShell/Modules')
            (Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/Modules')
        ) -join ';'
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        $null = $process.Start()
        $processHandle = $process.Handle
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $exitCode = [int]$process.ExitCode
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
        $process.Dispose()

        $processHandle | Should -Not -Be ([IntPtr]::Zero)
        $exitCode | Should -Be 0
        $stderr | Should -Be ''
        Test-Path -LiteralPath $output -PathType Leaf | Should -BeTrue
    }
    It 'refuses overwrite and removes failed builder candidates' {
        $originalHash = (Get-FileHash -LiteralPath $script:validZip -Algorithm SHA256).Hash
        { & (Join-Path $script:repoRoot 'scripts/New-TPMReleasePackage.ps1') -OutputPath $script:validZip -SourceRoot $script:fixtureSource } | Should -Throw '*PACKAGE_OUTPUT_EXISTS*'
        (Get-FileHash -LiteralPath $script:validZip -Algorithm SHA256).Hash | Should -Be $originalHash

        $badRoot = Join-Path $TestDrive 'builder missing source evidence'
        New-Item -ItemType Directory -Path $badRoot -Force | Out-Null
        New-PackageSourceFixture -Destination $badRoot -RepositoryRoot $script:repoRoot
        Remove-Item -LiteralPath (Join-Path $badRoot 'contracts/pcsx2x6/evidence.md') -Force
        $failedOutput = Join-Path $TestDrive 'failed candidate.zip'
        { & (Join-Path $script:repoRoot 'scripts/New-TPMReleasePackage.ps1') -OutputPath $failedOutput -SourceRoot $badRoot } | Should -Throw '*SOURCE_EVIDENCE_MISSING*'
        Test-Path -LiteralPath $failedOutput | Should -BeFalse
        @(Get-ChildItem -LiteralPath $TestDrive -Filter '.tpm-package-*.tmp' -File -Recurse -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'keeps the menu diagnostic out of the user file map' {
        @(Get-TPMReleasePackageFileMapV1 | Where-Object ZipPath -eq 'scripts/Debug-TPM-MenuLayout.ps1').Count | Should -Be 0
        Test-Path -LiteralPath (Join-Path $script:repoRoot 'scripts/Debug-TPM-MenuLayout.ps1') -PathType Leaf | Should -BeTrue
    }

    It 'rejects unknown root and nested entries' {
        foreach ($case in @(@{ Name = 'developer-notes.md'; Replace = 'tools/' },@{ Name = 'scripts/private/'; Replace = 'scripts/resources/' },@{ Name = 'scripts/private/extra.ps1'; Replace = 'scripts/resources/' })) {
            $zip = Join-Path $TestDrive (([guid]::NewGuid().ToString('N')) + '.zip')
            Copy-PackageArchiveFixture -Source $script:validZip -Destination $zip
            Remove-PackageArchiveEntry -ZipPath $zip -Name $case.Replace
            Add-PackageArchiveEntry -ZipPath $zip -Name $case.Name -Text 'unknown'
            { Test-TPMReleasePackageArchiveV1 -ZipPath $zip -SourceRoot $script:fixtureSource } | Should -Throw '*PACKAGE_ENTRY_UNKNOWN*'
        }
    }

    It 'rejects missing entries, collisions, unsafe paths, oversize streams and malformed compression' {
        $missing = Join-Path $TestDrive 'missing-file.zip'
        Copy-PackageArchiveFixture -Source $script:validZip -Destination $missing
        Remove-PackageArchiveEntry -ZipPath $missing -Name 'LICENSE'
        { Test-TPMReleasePackageArchiveV1 -ZipPath $missing -SourceRoot $script:fixtureSource } | Should -Throw '*PACKAGE_ENTRY_MISSING*'

        $collision = Join-Path $TestDrive 'case-collision.zip'
        Copy-PackageArchiveFixture -Source $script:validZip -Destination $collision
        Remove-PackageArchiveEntry -ZipPath $collision -Name 'tools/'
        Add-PackageArchiveEntry -ZipPath $collision -Name 'license' -Text 'collision'
        { Test-TPMReleasePackageArchiveV1 -ZipPath $collision -SourceRoot $script:fixtureSource } | Should -Throw '*PACKAGE_PATH_DUPLICATE_OR_CASE_COLLISION*'

        foreach ($entryName in @('../escape.txt','tools\alternate.ps1')) {
            $zip = Join-Path $TestDrive (([guid]::NewGuid().ToString('N')) + '.zip')
            Copy-PackageArchiveFixture -Source $script:validZip -Destination $zip
            Remove-PackageArchiveEntry -ZipPath $zip -Name 'tools/'
            Add-PackageArchiveEntry -ZipPath $zip -Name $entryName -Text 'invalid'
            { Test-TPMReleasePackageArchiveV1 -ZipPath $zip -SourceRoot $script:fixtureSource } | Should -Throw '*PACKAGE_PATH_NONCANONICAL*'
        }

        $oversized = Join-Path $TestDrive 'oversized-file.zip'
        Copy-PackageArchiveFixture -Source $script:validZip -Destination $oversized
        Add-PackageArchiveEntry -ZipPath $oversized -Name 'LICENSE' -Text ('x' * 65536) -Replace
        { Test-TPMReleasePackageArchiveV1 -ZipPath $oversized -SourceRoot $script:fixtureSource } | Should -Throw '*PACKAGE_SOURCE_SIZE_MISMATCH*'

        $malformed = Join-Path $TestDrive 'malformed-compression.zip'
        Copy-PackageArchiveFixture -Source $script:validZip -Destination $malformed
        Corrupt-PackageArchiveCompressedMember -ZipPath $malformed -Name 'scripts/TPMCertification.Contracts.psm1'
        { Test-TPMReleasePackageArchiveV1 -ZipPath $malformed -SourceRoot $script:fixtureSource } | Should -Throw
        $reopened = [System.IO.Compression.ZipFile]::OpenRead($malformed)
        $reopened.Dispose()
    }

    It 'preserves absolute-path leak rejection for generic user and UNC paths' {
        $leakRoot = Join-Path $TestDrive 'source fixture [path leak]'
        New-Item -ItemType Directory -Path $leakRoot -Force | Out-Null
        New-PackageSourceFixture -Destination $leakRoot -RepositoryRoot $script:repoRoot
        $readme = Join-Path $leakRoot 'TeknoParrot-Manager-README.txt'
        $profileRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
        $leakText = "`nW:\Arcade\private`n\\omvnas\Arcade\private`n"
        if (-not [string]::IsNullOrWhiteSpace($profileRoot)) { $leakText += $profileRoot.TrimEnd('\','/') + '\private' }
        [IO.File]::AppendAllText($readme, $leakText, (New-Object System.Text.UTF8Encoding($false)))
        $leakZip = Join-Path $TestDrive 'path-leak-package.zip'
        { & (Join-Path $script:repoRoot 'scripts/New-TPMReleasePackage.ps1') -OutputPath $leakZip -SourceRoot $leakRoot } | Should -Throw '*PACKAGE_PATH_LEAK*'
    }

    It 'rejects forged projections, missing source docs and missing source headings' {
        $forgedRoot = Join-Path $TestDrive 'forged source [index]'
        New-Item -ItemType Directory -Path $forgedRoot -Force | Out-Null
        New-PackageSourceFixture -Destination $forgedRoot -RepositoryRoot $script:repoRoot
        $indexPath = Join-Path $forgedRoot 'contracts/pcsx2x6/runtime-evidence-index.json'
        $indexText = [IO.File]::ReadAllText($indexPath).Replace('ev-portable-root','ev-altered-root')
        [IO.File]::WriteAllText($indexPath, $indexText, (New-Object System.Text.UTF8Encoding($false)))
        { Test-TPMReleasePackageArchiveV1 -ZipPath $script:validZip -SourceRoot $forgedRoot } | Should -Throw '*PACKAGE_SOURCE_INDEX_STALE*'

        $missingDocsRoot = Join-Path $TestDrive 'missing source docs [index present]'
        New-Item -ItemType Directory -Path $missingDocsRoot -Force | Out-Null
        New-PackageSourceFixture -Destination $missingDocsRoot -RepositoryRoot $script:repoRoot
        Remove-Item -LiteralPath (Join-Path $missingDocsRoot 'contracts/pcsx2x6/evidence.md') -Force
        { Test-TPMReleasePackageArchiveV1 -ZipPath $script:validZip -SourceRoot $missingDocsRoot } | Should -Throw '*SOURCE_EVIDENCE_MISSING*'

        $missingHeadingRoot = Join-Path $TestDrive 'missing source heading [index present]'
        New-Item -ItemType Directory -Path $missingHeadingRoot -Force | Out-Null
        New-PackageSourceFixture -Destination $missingHeadingRoot -RepositoryRoot $script:repoRoot
        $evidencePath = Join-Path $missingHeadingRoot 'contracts/pcsx2x6/evidence.md'
        $evidenceText = [IO.File]::ReadAllText($evidencePath).Replace('ev-portable-root','ev-renamed-portable-root')
        [IO.File]::WriteAllText($evidencePath, $evidenceText, (New-Object System.Text.UTF8Encoding($false)))
        { Test-TPMReleasePackageArchiveV1 -ZipPath $script:validZip -SourceRoot $missingHeadingRoot } | Should -Throw '*SOURCE_EVIDENCE_HEADING_MISSING*'
    }
}

Describe 'Packaged PCSx2x6 runtime projection' {
    It 'loads registry and read-only observations from a private extracted path with spaces and brackets' {
        $actualZip = Join-Path $TestDrive 'actual source package [private build].zip'
        $buildResult = & (Join-Path $script:repoRoot 'scripts/New-TPMReleasePackage.ps1') -OutputPath $actualZip -SourceRoot $script:repoRoot
        $buildResult.Valid | Should -BeTrue
        $buildResult.FileCount | Should -Be 341
        $buildResult.CrosshairPngCount | Should -Be 321
        $stage = Join-Path $TestDrive 'private extracted package [runtime path]'
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        Expand-PackageArchiveFixture -ZipPath $actualZip -Destination $stage | Out-Null
        $modulePath = Join-Path $stage 'scripts/TPMCertification.Contracts.psm1'
            Import-Module $modulePath -Force -PassThru | Out-Null
        (Get-TPMContractsRootV1 -ValidationMode Runtime) | Should -Be (Join-Path $stage 'scripts/resources/contracts')
        $loaded = Get-TPMEmulatorContractV1 -ContractId 'pcsx2x6' -ValidationMode Runtime
        $loaded.Contract.EvidenceReferences.Count | Should -Be 9
        $integrity = Test-TPMContractRegistryIntegrityV1 -ValidationMode Runtime
        $integrity.Valid | Should -BeTrue
        $observations = Get-TPMEmulatorContractObservationsV1 -InstallRoot (Join-Path $TestDrive 'empty synthetic install root') -ValidationMode Runtime
        $observations.RegistryValid | Should -BeTrue
        (Test-Path -LiteralPath (Join-Path $stage 'contracts')) | Should -BeFalse
        (Test-Path -LiteralPath (Join-Path $stage 'scripts/resources/contracts/pcsx2x6/evidence.md')) | Should -BeFalse
        (Test-Path -LiteralPath (Join-Path $stage 'scripts/resources/contracts/_schema')) | Should -BeFalse
        $mainPath = Join-Path $stage 'TeknoParrot-Manager.ps1'
        $tokens = $null
        $parseErrors = $null
        $mainAst = [System.Management.Automation.Language.Parser]::ParseFile($mainPath, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors).Count | Should -Be 0
        $wantedFunctions = @('Resolve-Pcsx2Directory','Get-ContractBackedMissingComponents')
        $functions = @($mainAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $wantedFunctions -contains $node.Name
        }, $true))
        $functions.Count | Should -Be 2
        $helperPath = Join-Path $stage 'packaged-main-support-helpers.ps1'
        $helperText = ($functions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
        [IO.File]::WriteAllText($helperPath, $helperText, (New-Object System.Text.UTF8Encoding($false)))
        . $helperPath
        $syntheticRoot = Join-Path $TestDrive 'synthetic TeknoParrot root'
        $pcsx2Directory = Join-Path $syntheticRoot 'pcsx2x6'
        New-Item -ItemType Directory -Path $pcsx2Directory -Force | Out-Null
        $mainAssessment = Get-ContractBackedMissingComponents -EmulatorType 'pcsx2x6' -TeknoParrotRoot $syntheticRoot
        $mainAssessment.State | Should -Be 'Missing'
        $mainAssessment.ContractId | Should -Be 'pcsx2x6'
        $mainAssessment.Components.Count | Should -BeGreaterThan 0
        $sourceContractDirectory = Join-Path $stage 'contracts/pcsx2x6'
        New-Item -ItemType Directory -Path $sourceContractDirectory -Force | Out-Null
        foreach ($name in @('contract.json','runtime-evidence-index.json','evidence.md','experiments.md')) {
            Copy-Item -LiteralPath (Join-Path $script:repoRoot "contracts/pcsx2x6/$name") -Destination (Join-Path $sourceContractDirectory $name) -Force
        }
        @(Get-TPMRegisteredEmulatorContractsV1 -ValidationMode Source -ContractsRoot (Join-Path $stage 'contracts')).Count | Should -Be 1
        Remove-Item -LiteralPath (Join-Path $stage 'scripts/resources/contracts') -Recurse -Force
        $noFallbackAssessment = Get-ContractBackedMissingComponents -EmulatorType 'pcsx2x6' -TeknoParrotRoot $syntheticRoot
        $noFallbackAssessment.State | Should -Be 'Unknown'
        $noFallbackAssessment.Components.Count | Should -Be 0
    }

    It 'rejects missing or duplicated rows, stale contract hash, and altered reference mappings' {
        foreach ($case in @('missing-index','stale-contract-hash','wrong-locator','missing-row','duplicate-row','wrong-heading')) {
            $stage = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $stage -Force | Out-Null
            Expand-PackageArchiveFixture -ZipPath $script:validZip -Destination $stage | Out-Null
            $indexPath = Join-Path $stage 'scripts/resources/contracts/pcsx2x6/runtime-evidence-index.json'
            $contractPath = Join-Path $stage 'scripts/resources/contracts/pcsx2x6/contract.json'
            if ($case -eq 'missing-index') {
                Remove-Item -LiteralPath $indexPath -Force
                { Get-TPMEmulatorContractV1 -ContractId 'pcsx2x6' -ValidationMode Runtime -ContractsRoot (Join-Path $stage 'scripts/resources/contracts') } | Should -Throw '*RUNTIME_EVIDENCE_INDEX_MISSING*'
                continue
            }
            $index = [IO.File]::ReadAllText($indexPath) | ConvertFrom-Json
            if ($case -eq 'stale-contract-hash') {
                $index.ContractSha256 = ('0' * 64)
            } elseif ($case -eq 'wrong-locator') {
                $index.EvidenceReferences[0].Locator = 'evidence.md#wrong-heading'
            } elseif ($case -eq 'missing-row') {
                $index.EvidenceReferences = @($index.EvidenceReferences | Select-Object -Skip 1)
            } elseif ($case -eq 'duplicate-row') {
                $index.EvidenceReferences = @($index.EvidenceReferences) + @($index.EvidenceReferences[0])
            } elseif ($case -eq 'wrong-heading') {
                $index.EvidenceReferences[0].Heading = 'wrong-heading'
            }
            [IO.File]::WriteAllText($indexPath, ($index | ConvertTo-Json -Depth 8 -Compress), (New-Object System.Text.UTF8Encoding($false)))
            $expectedError = if ($case -eq 'stale-contract-hash') { '*RUNTIME_EVIDENCE_CONTRACT_HASH_MISMATCH*' } else { '*RUNTIME_EVIDENCE_INDEX_INVALID*' }
            { Get-TPMEmulatorContractV1 -ContractId 'pcsx2x6' -ValidationMode Runtime -ContractsRoot (Join-Path $stage 'scripts/resources/contracts') } | Should -Throw $expectedError
        }
    }
}
AfterAll {
    $testDrivePrefix = [IO.Path]::GetFullPath($TestDrive)
    if (-not $testDrivePrefix.EndsWith([IO.Path]::DirectorySeparatorChar.ToString())) {
        $testDrivePrefix += [IO.Path]::DirectorySeparatorChar
    }
    $corePath = $script:packageOwnedModulePaths[0]
    foreach ($module in @(Get-Module -All)) {
        if (-not $module.Path -or -not [string]::Equals([IO.Path]::GetFullPath($module.Path),$corePath,[StringComparison]::OrdinalIgnoreCase)) { continue }
        $wasPreexisting = $false
        foreach ($prior in $script:packageInitialModules) {
            if ([object]::ReferenceEquals($module,$prior)) { $wasPreexisting = $true; break }
        }
        if ($wasPreexisting) { continue }
        $stillLoaded = $false
        foreach ($current in @(Get-Module -All)) {
            if ([object]::ReferenceEquals($module,$current)) { $stillLoaded = $true; break }
        }
        if ($stillLoaded) { Remove-Module -ModuleInfo $module -Force }
    }
    foreach ($module in @(Get-Module -All)) {
        if (-not $module.Path) { continue }
        $modulePath = [IO.Path]::GetFullPath($module.Path)
        $isOwned = $script:packageOwnedModulePaths -contains $modulePath -or $modulePath.StartsWith($testDrivePrefix,[StringComparison]::OrdinalIgnoreCase)
        if (-not $isOwned) { continue }
        $wasPreexisting = $false
        foreach ($prior in $script:packageInitialModules) {
            if ([object]::ReferenceEquals($module,$prior)) { $wasPreexisting = $true; break }
        }
        if ($wasPreexisting) { continue }
        $stillLoaded = $false
        foreach ($current in @(Get-Module -All)) {
            if ([object]::ReferenceEquals($module,$current)) { $stillLoaded = $true; break }
        }
        if ($stillLoaded) { Remove-Module -ModuleInfo $module -Force }
    }
    Import-Module $script:packageOwnedModulePaths[2] -Global -Force
    Import-Module $script:packageOwnedModulePaths[1] -Global -Force
}
