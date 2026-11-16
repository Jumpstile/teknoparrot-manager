#Requires -Module Pester

# FIX21A ASTRA-04 coverage for the main script's in-place updater
# (Invoke-ManagerUpdateInstall). A release ZIP may carry only the root entry
# named exactly (ordinal, case-sensitive) 'TeknoParrot-Manager.ps1'. Alias
# forms of that name ('./', '.\', other casing, a nested copy) are extra files
# and must be refused before extraction with the installed script unchanged.
# A second entry with exactly the script's name is also an extra file, so a
# ZIP with two exact-name entries is refused the same way.
#
# The production script is parsed and only the update transaction plus its
# real helpers are dot-sourced. The download is an inert stub that each test
# mocks to copy a ZIP built under $TestDrive.
#
# Run with: Invoke-Pester -Path .\Tests\Fix21A.UpdatePackageRefusal.Tests.ps1
BeforeAll {
    $script:f21RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:f21SourcePath = Join-Path $script:f21RepoRoot 'TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:f21SourcePath,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0) {
        throw "Failed to parse TeknoParrot-Manager.ps1: $($parseErrors -join '; ')"
    }

    $wanted = @(
        'Get-TpmTransactionOutcomeNames', 'Get-TpmTransactionProductStateNames', 'Get-TpmTransactionField',
        'Get-TpmTransactionItemKey', 'Get-TpmTransactionItemKeys', 'Test-TpmTransactionUserSafeSummary',
        'Assert-TpmTransactionItemSets', 'Assert-TpmTransactionResult', 'Test-TpmTransactionResult',
        'New-TpmTransactionResult', 'New-TpmProfileTransactionResult',
        'Test-TpmNoReparsePath', 'Assert-TpmNoReparseWriteTarget',
        'Get-ManagerVersionIdentity', 'Get-ManagerIdentityWriteTargetInfo', 'Get-ManagerIdentityTargetName',
        'Get-ManagerScriptVersionIdentityFromContent', 'Get-ManagerVersionParts', 'Compare-ManagerVersionText',
        'Get-TpmSha256FromDigestField',
        'Assert-ManagerUpdateTargetWritable', 'New-ManagerUpdateBackup', 'Expand-ManagerUpdateAsset',
        'Test-ManagerUpdatePackageIsSingleScript', 'Test-ManagerUpdateExtractedScript', 'Get-ManagerUpdatePreState',
        'Get-ManagerUpdatePackageFiles', 'ConvertTo-SafeZipEntryRelativePath',
        'New-TpmManagerUpdateTransactionResult', 'Invoke-ManagerUpdateInstall'
    )
    $functions = @(
        $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $true) | Where-Object { $wanted -contains $_.Name }
    )
    foreach ($name in $wanted) {
        $found = @($functions | Where-Object { $_.Name -eq $name }).Count
        if ($found -ne 1) { throw "Expected exactly one definition of $name; found $found." }
    }

    $functionPath = Join-Path $TestDrive ('f21upr-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.ps1')
    ($functions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" |
        Set-Content -LiteralPath $functionPath -Encoding utf8
    . $functionPath

    Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

    $script:f21Log = New-Object System.Collections.Generic.List[string]
    $script:f21ZipToServe = $null

    # Dependencies outside this scope. Signatures mirror production so Mock
    # parameter binding behaves the same.
    function Write-Log {
        param([string]$msg)
        [void]$script:f21Log.Add([string]$msg)
    }
    function Invoke-TpmDownload {
        param([string]$DownloadUrl, [string]$DestinationPath, [Int64]$ExpectedBytes = 0, [string]$Label = 'Download', [string]$Version = '', [switch]$Quiet, [ref]$LastStatusCode, [string]$ExpectedSha256 = '', [scriptblock]$ValidationScript, [string]$AllowedRoot = '', [switch]$NoOverwrite)
        throw 'Invoke-TpmDownload stub must be mocked.'
    }

    # Writes a ZIP whose entries keep the exact FullName given (no
    # normalization) in the given order, each with its own ASCII content.
    function New-F21UpdateZip {
        param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][object[]]$Entries)
        $zip = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($item in $Entries) {
                $entry = $zip.CreateEntry([string]$item.Name)
                $stream = $entry.Open()
                try {
                    $bytes = [System.Text.Encoding]::ASCII.GetBytes([string]$item.Text)
                    $stream.Write($bytes, 0, $bytes.Length)
                } finally {
                    $stream.Dispose()
                }
            }
        } finally {
            $zip.Dispose()
        }
        return $Path
    }
    function Get-F21ZipEntryNames {
        param([Parameter(Mandatory)][string]$Path)
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        try {
            return [string[]]@($zip.Entries | ForEach-Object { [string]$_.FullName })
        } finally {
            $zip.Dispose()
        }
    }
    function New-F21InstalledScript {
        param([Parameter(Mandatory)][string]$Prefix)
        $root = Join-Path $TestDrive ($Prefix + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $appDir = Join-Path $root 'app'
        [void][System.IO.Directory]::CreateDirectory($appDir)
        $path = Join-Path $appDir 'TeknoParrot-Manager.ps1'
        [System.IO.File]::WriteAllText($path, '$ScriptVersion = "0.0.1"')
        return [pscustomobject]@{
            Root          = $root
            AppDir        = $appDir
            ScriptPath    = $path
            OriginalBytes = [System.IO.File]::ReadAllBytes($path)
        }
    }
    function New-F21Release {
        return [pscustomobject]@{
            TagName     = 'v0.99.99'
            Name        = 'v0.99.99 BETA'
            Body        = 'Test release notes.'
            AssetName   = 'TeknoParrot.Manager.v0.99.99.BETA.zip'
            DownloadUrl = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.99/TeknoParrot.Manager.v0.99.99.BETA.zip'
            SizeBytes   = 1
            Digest      = 'sha256:' + (Get-FileHash -LiteralPath $script:f21ZipToServe -Algorithm SHA256 -ErrorAction Stop).Hash
        }
    }

    $script:f21CandidateText = "# TeknoParrot Manager`r`n`$ScriptVersion = `"0.99.99`"`r`n"
}

Describe 'Invoke-ManagerUpdateInstall refuses unsafe or repeated names of the script entry (FIX21A ASTRA-04, FIX403)' {
    BeforeEach {
        $script:f21Log.Clear()
        Mock Write-Host {}
        Mock Invoke-TpmDownload {
            Copy-Item -LiteralPath $script:f21ZipToServe -Destination $DestinationPath -Force
            return $true
        }
        Mock Expand-ManagerUpdateAsset { throw 'Expand-ManagerUpdateAsset must not run for a refused package.' }
    }

    It 'refuses the exact entry plus <Extra> before extraction and leaves the installed script unchanged' -TestCases @(
        @{ Extra = './TeknoParrot-Manager.ps1' }
        @{ Extra = '.\TeknoParrot-Manager.ps1' }
        @{ Extra = 'teknoparrot-manager.ps1' }
    ) {
        $fixture = New-F21InstalledScript -Prefix 'alias'
        $script:f21ZipToServe = New-F21UpdateZip -Path (Join-Path $fixture.Root 'rel.zip') -Entries @(
            [pscustomobject]@{ Name = 'TeknoParrot-Manager.ps1'; Text = $script:f21CandidateText }
            [pscustomobject]@{ Name = $Extra; Text = $script:f21CandidateText }
        )
        # The fixture must really carry the alias name verbatim.
        (Get-F21ZipEntryNames -Path $script:f21ZipToServe) -join '|' | Should -BeExactly ('TeknoParrot-Manager.ps1|' + $Extra)

        $result = Invoke-ManagerUpdateInstall -ScriptPath $fixture.ScriptPath -Release (New-F21Release)

        (Test-TpmTransactionResult -Result $result) | Should -BeTrue
        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.ProductState | Should -BeExactly 'UNCHANGED'
        $result.ReasonCode | Should -BeExactly 'UPDATE_PACKAGE_BAD_ENTRY'
        $result.Installed | Should -BeFalse
        $result.Mutation.Started | Should -BeFalse
        (@($result.Errors) -join '|') | Should -BeExactly 'The update package has a file name that is not safe. Nothing was installed. See https://github.com/Jumpstile/teknoparrot-manager/releases.'
        @($script:f21Log | Where-Object { $_ -clike 'CheckForUpdates: release v0.99.99 refused before extraction -- *' }).Count | Should -Be 1
        [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($fixture.ScriptPath)) | Should -BeExactly ([Convert]::ToBase64String($fixture.OriginalBytes))
        (@(Get-ChildItem -LiteralPath $fixture.AppDir -File -Force | ForEach-Object { $_.Name }) -join '|') | Should -BeExactly 'TeknoParrot-Manager.ps1'
        Test-Path -LiteralPath (Join-Path $fixture.AppDir 'UpdateBackups') | Should -BeFalse
        Should -Invoke Invoke-TpmDownload -Times 1 -Exactly
        Should -Invoke Expand-ManagerUpdateAsset -Times 0 -Exactly
    }
}

Describe 'Invoke-ManagerUpdateInstall refuses two exact-name script entries (FIX21A ASTRA-04)' {
    BeforeEach {
        $script:f21Log.Clear()
        Mock Write-Host {}
        Mock Invoke-TpmDownload {
            Copy-Item -LiteralPath $script:f21ZipToServe -Destination $DestinationPath -Force
            return $true
        }
        Mock Expand-ManagerUpdateAsset { throw 'Expand-ManagerUpdateAsset must not run for a refused package.' }
    }

    It 'refuses a ZIP with two TeknoParrot-Manager.ps1 entries before extraction and leaves the installed script unchanged' {
        $fixture = New-F21InstalledScript -Prefix 'dup'
        $script:f21ZipToServe = New-F21UpdateZip -Path (Join-Path $fixture.Root 'rel.zip') -Entries @(
            [pscustomobject]@{ Name = 'TeknoParrot-Manager.ps1'; Text = $script:f21CandidateText + "# duplicate entry: first`r`n" }
            [pscustomobject]@{ Name = 'TeknoParrot-Manager.ps1'; Text = $script:f21CandidateText + "# duplicate entry: second`r`n" }
        )
        (Get-F21ZipEntryNames -Path $script:f21ZipToServe) -join '|' | Should -BeExactly 'TeknoParrot-Manager.ps1|TeknoParrot-Manager.ps1'
        $composition = Test-ManagerUpdatePackageIsSingleScript -ZipPath $script:f21ZipToServe
        $composition.SingleScript | Should -BeFalse
        $composition.ExtraEntryCount | Should -Be 1
        (@($composition.ExtraEntrySample) -join '|') | Should -BeExactly 'TeknoParrot-Manager.ps1'

        $result = Invoke-ManagerUpdateInstall -ScriptPath $fixture.ScriptPath -Release (New-F21Release)

        (Test-TpmTransactionResult -Result $result) | Should -BeTrue
        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.ProductState | Should -BeExactly 'UNCHANGED'
        $result.ReasonCode | Should -BeExactly 'UPDATE_PACKAGE_BAD_ENTRY'
        $result.Installed | Should -BeFalse
        $result.Mutation.Started | Should -BeFalse
        (@($result.Errors) -join '|') | Should -BeExactly 'The update package has a file name that is not safe. Nothing was installed. See https://github.com/Jumpstile/teknoparrot-manager/releases.'
        @($script:f21Log | Where-Object { $_ -clike 'CheckForUpdates: release v0.99.99 refused before extraction -- *' }).Count | Should -Be 1
        [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($fixture.ScriptPath)) | Should -BeExactly ([Convert]::ToBase64String($fixture.OriginalBytes))
        (@(Get-ChildItem -LiteralPath $fixture.AppDir -File -Force | ForEach-Object { $_.Name }) -join '|') | Should -BeExactly 'TeknoParrot-Manager.ps1'
        # Nothing is written before the refusal: no backup folder is left behind for a package that is never installed.
        Test-Path -LiteralPath (Join-Path $fixture.AppDir 'UpdateBackups') | Should -BeFalse
        Should -Invoke Invoke-TpmDownload -Times 1 -Exactly
        Should -Invoke Expand-ManagerUpdateAsset -Times 0 -Exactly
    }

    It 'says plainly that there is no script in the release when the ZIP has none' {
        $fixture = New-F21InstalledScript -Prefix 'noscript'
        $script:f21ZipToServe = New-F21UpdateZip -Path (Join-Path $fixture.Root 'rel.zip') -Entries @(
            [pscustomobject]@{ Name = 'notes.txt'; Text = 'no script here' }
        )

        $result = Invoke-ManagerUpdateInstall -ScriptPath $fixture.ScriptPath -Release (New-F21Release)

        (Test-TpmTransactionResult -Result $result) | Should -BeTrue
        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.ProductState | Should -BeExactly 'UNCHANGED'
        $result.ReasonCode | Should -BeExactly 'UPDATE_PACKAGE_HAS_NO_SCRIPT'
        $result.Summary | Should -Match 'no script in this release'
        $result.Summary | Should -Not -Match 'multi-file'
        [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($fixture.ScriptPath)) | Should -BeExactly ([Convert]::ToBase64String($fixture.OriginalBytes))
        Should -Invoke Expand-ManagerUpdateAsset -Times 0 -Exactly
    }
}
