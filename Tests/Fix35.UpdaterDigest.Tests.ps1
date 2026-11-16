#Requires -Module Pester
# FIX35: real digest gates, real ZIP extraction, isolated filesystem fixtures.
BeforeAll {
    $global:f35OldTemp = $env:TEMP
    $global:f35OldTmp = $env:TMP
    $env:TEMP = $TestDrive
    $env:TMP = $TestDrive
    $root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $global:f35Orchestrator = Join-Path $root 'tools\Invoke-TpmAutoUpdate.ps1'
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'TeknoParrot-Manager.ps1'), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw 'Main script parsing failed.' }
    $wanted = @(
        'Get-TpmTransactionOutcomeNames', 'Get-TpmTransactionProductStateNames', 'Get-TpmTransactionField',
        'Get-TpmTransactionItemKey', 'Get-TpmTransactionItemKeys', 'Test-TpmTransactionUserSafeSummary',
        'Assert-TpmTransactionItemSets', 'Assert-TpmTransactionResult', 'Test-TpmTransactionResult',
        'New-TpmTransactionResult', 'New-TpmProfileTransactionResult',
        'Test-TpmNoReparsePath', 'Assert-TpmNoReparseWriteTarget',
        'Get-ManagerVersionIdentity', 'Get-ManagerIdentityWriteTargetInfo', 'Get-ManagerIdentityTargetName',
        'Get-ManagerScriptVersionIdentityFromContent', 'Get-ManagerVersionParts', 'Compare-ManagerVersionText',
        'Assert-ManagerUpdateTargetWritable', 'New-ManagerUpdateBackup', 'Expand-ManagerUpdateAsset',
        'Test-ManagerUpdatePackageIsSingleScript', 'Test-ManagerUpdateExtractedScript', 'Get-ManagerUpdatePreState',
        'Get-ManagerUpdateRelease', 'Get-TpmHttpStatusCodeFromError',
        'New-TpmManagerUpdateTransactionResult', 'Invoke-ManagerUpdateInstall', 'Get-TpmSha256FromDigestField',
        'Test-TpmDownloadedFile'
    )
    $functions = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] }, $true) | Where-Object { $wanted -contains $_.Name })
    foreach ($name in $wanted) {
        if (@($functions | Where-Object Name -eq $name).Count -ne 1) { throw "Missing helper: $name" }
    }
    $helpers = Join-Path $TestDrive 'fix35-main-functions.ps1'
    ($functions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $helpers -Encoding ASCII
    . $helpers
    Import-Module (Join-Path $root 'tools\TpmAutoUpdate.Core.psm1') -Force
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    function Write-Log { param($msg) }
    $script:ScriptVersion = '0.0.1'
    function Invoke-TpmWebRequestSilently {
        param($Uri, [switch]$UseBasicParsing, $TimeoutSec, $Headers)
        throw 'Network is forbidden; release API must be mocked.'
    }
    function Invoke-TpmDownload {
        param($DownloadUrl, $DestinationPath, $ExpectedBytes, $Label, $Version, $ExpectedSha256)
        throw 'Network is forbidden; download must be mocked.'
    }
    function New-F35Fixture {
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($dir)
        $stage = Join-Path $dir 'stage'
        [void][IO.Directory]::CreateDirectory($stage)
        $candidate = "# TeknoParrot Manager`r`n`$ScriptVersion = `"0.99.99`"`r`n"
        [IO.File]::WriteAllText((Join-Path $stage 'TeknoParrot-Manager.ps1'), $candidate)
        $zip = Join-Path $dir 'source.zip'
        [IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip)
        $app = Join-Path $dir 'app'
        [void][IO.Directory]::CreateDirectory($app)
        $installed = Join-Path $app 'TeknoParrot-Manager.ps1'
        [IO.File]::WriteAllText($installed, '$ScriptVersion = "0.0.1"')
        $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
        return [pscustomobject]@{
            Root=$dir; App=$app; Installed=$installed; Zip=$zip; Hash=$hash; Candidate=$candidate
            Original=[Convert]::ToBase64String([IO.File]::ReadAllBytes($installed))
            Attributes=[IO.File]::GetAttributes($installed)
        }
    }
    function New-F35Metadata {
        param($Fixture)
        return [pscustomobject]@{
            TagName='v0.99.99'; Name='manager.zip'; Body='Fixture'; AssetName='manager.zip'
            DownloadUrl='https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.99/manager.zip'
            SizeBytes=(Get-Item -LiteralPath $Fixture.Zip).Length
            Digest=('sha256:' + $Fixture.Hash)
            size=(Get-Item -LiteralPath $Fixture.Zip).Length
            browser_download_url='https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.99/manager.zip'
        }
    }
    function Assert-F35Unchanged {
        param($Fixture)
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($Fixture.Installed)) | Should -BeExactly $Fixture.Original
        [IO.File]::GetAttributes($Fixture.Installed) | Should -Be $Fixture.Attributes
        Test-Path -LiteralPath (Join-Path $Fixture.App 'UpdateBackups') | Should -BeFalse
        if ($global:f35Download) { Test-Path -LiteralPath $global:f35Download | Should -BeFalse }
    }
}
AfterAll {
    $env:TEMP = $global:f35OldTemp
    $env:TMP = $global:f35OldTmp
    Remove-Module TpmAutoUpdate.Core -ErrorAction SilentlyContinue
    foreach ($n in 'f35Fixture','f35Metadata','f35Download','f35Swap','f35Orchestrator','f35OldTemp','f35OldTmp') { Remove-Variable -Name $n -Scope Global -ErrorAction SilentlyContinue }
}
Describe 'FIX35 updater digest boundaries' {
    BeforeEach {
        $global:f35Fixture = New-F35Fixture
        $global:f35Metadata = New-F35Metadata $global:f35Fixture
        $global:f35Download = $null
        $global:f35Swap = $false
        Mock Write-Host {}
        Mock Invoke-WebRequest { throw 'Network forbidden.' }
        Mock Invoke-RestMethod { throw 'Network forbidden.' }
        Mock Invoke-TpmWebRequestSilently {
            $asset = @{
                name='TeknoParrot.Manager.v0.99.99.zip'
                browser_download_url=$global:f35Metadata.DownloadUrl
                size=$global:f35Metadata.SizeBytes
            }
            if ($global:f35Metadata.PSObject.Properties['Digest']) { $asset.digest = $global:f35Metadata.Digest }
            [pscustomobject]@{ Content=(@{ tag_name='v0.99.99'; name='Fixture'; body='Fixture'; assets=@($asset) } | ConvertTo-Json -Depth 5) }
        }
        Mock Get-LatestRelease {
            [pscustomobject]@{ tag_name='v0.99.99'; assets=@($global:f35Metadata) }
        }
        $download = {
            $global:f35Download = $DestinationPath
            if (-not [IO.Path]::GetFullPath($DestinationPath).StartsWith(([IO.Path]::GetFullPath($TestDrive).TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Updater download escaped TestDrive.'
            }
            Copy-Item -LiteralPath $global:f35Fixture.Zip -Destination $DestinationPath
            if ($global:f35Swap) {
                # Keep byte length unchanged so only the digest gate can reject it.
                $swapped = [IO.File]::ReadAllBytes($DestinationPath)
                $swapped[0] = $swapped[0] -bxor 1
                [IO.File]::WriteAllBytes($DestinationPath, $swapped)
                $global:f35Metadata.Digest = 'sha256:' + (Get-FileHash -LiteralPath $DestinationPath -Algorithm SHA256).Hash
            }
            return $true
        }
        Mock Invoke-TpmDownload $download
        Mock Invoke-TpmDownload $download -ModuleName TpmAutoUpdate.Core
    }
    It '<Path> matching digest reaches real extraction/install (<Case>)' -TestCases @(
        @{ Path='main'; Case='original' }, @{ Path='main'; Case='mixed case' },
        @{ Path='standalone'; Case='original' }, @{ Path='standalone'; Case='mixed case' }
    ) {
        if ($Case -eq 'mixed case') { $global:f35Metadata.Digest = 'SHA256:' + $global:f35Fixture.Hash.ToLowerInvariant() }
        if ($Path -eq 'main') {
            $global:f35Metadata = Get-ManagerUpdateRelease
            $result = Invoke-ManagerUpdateInstall -ScriptPath $global:f35Fixture.Installed -Release $global:f35Metadata
            $result.Installed | Should -BeTrue
            $result.ReasonCode | Should -BeExactly 'UPDATE_INSTALLED_VERIFIED'
            [IO.File]::ReadAllText($global:f35Fixture.Installed) | Should -BeExactly $global:f35Fixture.Candidate
            @(Get-ChildItem -LiteralPath (Join-Path $global:f35Fixture.App 'UpdateBackups') -Recurse -File).Count | Should -Be 1
        } else {
            & $global:f35Orchestrator -Apply -Confirm:$false -ScriptPath $global:f35Fixture.Installed -AssetNamePattern '^manager\.zip$'
            [IO.File]::ReadAllText($global:f35Fixture.Installed) | Should -BeExactly $global:f35Fixture.Candidate
            @(Get-ChildItem -LiteralPath (Join-Path $global:f35Fixture.App 'UpdateBackups') -Recurse -File).Count | Should -Be 1
        }
        Test-Path -LiteralPath $global:f35Download | Should -BeFalse
    }
    It '<Path> refuses <Kind> before download or mutation' -TestCases @(
        @{Path='main';Kind='missing'}, @{Path='standalone';Kind='missing'},
        @{Path='main';Kind='null'}, @{Path='standalone';Kind='null'},
        @{Path='main';Kind='empty'}, @{Path='standalone';Kind='empty'},
        @{Path='main';Kind='algorithm'}, @{Path='standalone';Kind='algorithm'},
        @{Path='main';Kind='nonhex'}, @{Path='standalone';Kind='nonhex'},
        @{Path='main';Kind='short'}, @{Path='standalone';Kind='short'},
        @{Path='main';Kind='long'}, @{Path='standalone';Kind='long'},
        @{Path='main';Kind='newline'}, @{Path='standalone';Kind='newline'}
    ) {
        switch ($Kind) {
            'missing' { $global:f35Metadata.PSObject.Properties.Remove('Digest') }
            'null' { $global:f35Metadata.Digest = $null }
            'empty' { $global:f35Metadata.Digest = '' }
            'algorithm' { $global:f35Metadata.Digest = 'sha512:' + ('a' * 64) }
            'nonhex' { $global:f35Metadata.Digest = 'sha256:' + ('g' * 64) }
            'short' { $global:f35Metadata.Digest = 'sha256:' + ('a' * 63) }
            'long' { $global:f35Metadata.Digest = 'sha256:' + ('a' * 65) }
            'newline' { $global:f35Metadata.Digest += "`n" }
        }
        Mock Expand-ManagerUpdateAsset { throw 'Extraction forbidden.' }
        Mock Expand-TpmReleaseZipEntry { throw 'Extraction forbidden.' }
        if ($Path -eq 'main') {
            $global:f35Metadata = Get-ManagerUpdateRelease
            $result = Invoke-ManagerUpdateInstall -ScriptPath $global:f35Fixture.Installed -Release $global:f35Metadata
            $result.ReasonCode | Should -BeExactly 'UPDATE_DIGEST_UNAVAILABLE'
            $result.Mutation.Started | Should -BeFalse
        } else {
            { & $global:f35Orchestrator -Apply -Confirm:$false -ScriptPath $global:f35Fixture.Installed -AssetNamePattern '^manager\.zip$' } | Should -Throw '*digest is missing or invalid*'
        }
        $global:f35Download | Should -BeNullOrEmpty
        Should -Invoke Invoke-TpmDownload -Times 0 -Exactly
        Should -Invoke Invoke-TpmDownload -ModuleName TpmAutoUpdate.Core -Times 0 -Exactly
        Should -Invoke Expand-ManagerUpdateAsset -Times 0 -Exactly
        Should -Invoke Expand-TpmReleaseZipEntry -Times 0 -Exactly
        Assert-F35Unchanged $global:f35Fixture
    }
    It '<Path> refuses <Kind>, cleans owned ZIP, and preserves bytes and attributes' -TestCases @(
        @{Path='main';Kind='mismatch'}, @{Path='standalone';Kind='mismatch'},
        @{Path='main';Kind='metadata and downloaded asset swapped'}, @{Path='standalone';Kind='metadata and downloaded asset swapped'}
    ) {
        Set-ItemProperty -LiteralPath $global:f35Fixture.Installed -Name IsReadOnly -Value $true
        $global:f35Fixture.Attributes = [IO.File]::GetAttributes($global:f35Fixture.Installed)
        if ($Kind -eq 'mismatch') { $global:f35Metadata.Digest = 'sha256:' + ('0' * 64) } else { $global:f35Swap = $true }
        Mock Expand-ManagerUpdateAsset { throw 'Extraction forbidden.' }
        Mock Expand-TpmReleaseZipEntry { throw 'Extraction forbidden.' }
        try {
            if ($Path -eq 'main') {
                $global:f35Metadata = Get-ManagerUpdateRelease
                $result = Invoke-ManagerUpdateInstall -ScriptPath $global:f35Fixture.Installed -Release $global:f35Metadata
                $result.ReasonCode | Should -BeExactly 'UPDATE_DIGEST_MISMATCH'
                $result.Mutation.Started | Should -BeFalse
            } else {
                { & $global:f35Orchestrator -Apply -Confirm:$false -ScriptPath $global:f35Fixture.Installed -AssetNamePattern '^manager\.zip$' } | Should -Throw '*digest mismatch*'
            }
            $global:f35Download | Should -Not -BeNullOrEmpty
            Assert-F35Unchanged $global:f35Fixture
            Should -Invoke Expand-ManagerUpdateAsset -Times 0 -Exactly
            Should -Invoke Expand-TpmReleaseZipEntry -Times 0 -Exactly
        } finally {
            Set-ItemProperty -LiteralPath $global:f35Fixture.Installed -Name IsReadOnly -Value $false
        }
    }
}
