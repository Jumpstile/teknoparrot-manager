#Requires -Module Pester

# FIX110B (N-1, N-2): the update summaries say TeknoParrot Manager, and "could not be checked" and "does not match" are different messages.
#   Before, both an unavailable published-file digest and a completed digest comparison that found a mismatch said
#   "could not be checked against the published file", which is wrong for the mismatch.
# The real Invoke-ManagerUpdateInstall runs against a synthetic release and a synthetic ZIP in $TestDrive (the network is forbidden and
# mocked). What this CANNOT prove: the live GitHub release API.

BeforeAll {
    $global:f110OldTemp = $env:TEMP
    $global:f110OldTmp = $env:TMP
    $env:TEMP = $TestDrive
    $env:TMP = $TestDrive
    $root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:F110UpdaterToolPath = Join-Path $root 'tools\Invoke-TpmAutoUpdate.ps1'
    $tokens = $null
    $errors = $null
    $script:F110UpdaterAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'TeknoParrot-Manager.ps1'), [ref]$tokens, [ref]$errors)
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
    $functions = @($script:F110UpdaterAst.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] }, $true) | Where-Object { $wanted -contains $_.Name })
    foreach ($name in $wanted) {
        if (@($functions | Where-Object Name -eq $name).Count -ne 1) { throw "Missing helper: $name" }
    }
    $helpers = Join-Path $TestDrive 'fix110b-updater-functions.ps1'
    ($functions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $helpers -Encoding ASCII
    . $helpers
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
    function New-F110Fixture {
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
        return [pscustomobject]@{ Root = $dir; App = $app; Installed = $installed; Zip = $zip; Hash = $hash }
    }
}
AfterAll {
    $env:TEMP = $global:f110OldTemp
    $env:TMP = $global:f110OldTmp
    foreach ($n in 'f110Fixture', 'f110Metadata', 'f110OldTemp', 'f110OldTmp') { Remove-Variable -Name $n -Scope Global -ErrorAction SilentlyContinue }
}

Describe 'FIX110B N-2 the update refusal says "could not check" or "does not match", not the same words for both' {
    BeforeEach {
        $global:f110Fixture = New-F110Fixture
        $global:f110Metadata = [pscustomobject]@{
            TagName = 'v0.99.99'; Name = 'manager.zip'; Body = 'Fixture'; AssetName = 'manager.zip'
            DownloadUrl = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.99/manager.zip'
            SizeBytes = (Get-Item -LiteralPath $global:f110Fixture.Zip).Length
            Digest = ('sha256:' + $global:f110Fixture.Hash)
            size = (Get-Item -LiteralPath $global:f110Fixture.Zip).Length
            browser_download_url = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.99/manager.zip'
        }
        Mock Write-Host {}
        Mock Invoke-WebRequest { throw 'Network forbidden.' }
        Mock Invoke-RestMethod { throw 'Network forbidden.' }
        Mock Invoke-TpmWebRequestSilently {
            $asset = @{
                name = 'TeknoParrot.Manager.v0.99.99.zip'
                browser_download_url = $global:f110Metadata.DownloadUrl
                size = $global:f110Metadata.SizeBytes
            }
            if ($global:f110Metadata.PSObject.Properties['Digest']) { $asset.digest = $global:f110Metadata.Digest }
            [pscustomobject]@{ Content = (@{ tag_name = 'v0.99.99'; name = 'Fixture'; body = 'Fixture'; assets = @($asset) } | ConvertTo-Json -Depth 5) }
        }
        Mock Invoke-TpmDownload {
            Copy-Item -LiteralPath $global:f110Fixture.Zip -Destination $DestinationPath
            return $true
        }
        Mock Expand-ManagerUpdateAsset { throw 'Extraction forbidden.' }
    }

    It 'says the published file could not be checked, and suggests trying again later, when no digest is available' {
        # Mutation: give the unavailable-digest refusal the mismatch wording (or the old shared sentence) -> the user is told a check failed when none could be made.
        $global:f110Metadata.PSObject.Properties.Remove('Digest')
        $release = Get-ManagerUpdateRelease
        $result = Invoke-ManagerUpdateInstall -ScriptPath $global:f110Fixture.Installed -Release $release
        $result.ReasonCode | Should -BeExactly 'UPDATE_DIGEST_UNAVAILABLE'
        $result.Summary | Should -Match 'could not check it against the published file'
        $result.Summary | Should -Match 'Try again later'
        $result.Summary | Should -Not -Match '(?i)damaged|not the same'
        $result.Summary | Should -Not -Match '\bTPM\b'
        $result.Mutation.Started | Should -BeFalse
    }

    It 'says the downloaded file does not match the published file, and that it may be damaged, when the check found a difference' {
        # Mutation: keep "could not be checked" for a completed comparison -> the user is told nothing was checked after a mismatch was found.
        $global:f110Metadata.Digest = 'sha256:' + ('0' * 64)
        $release = Get-ManagerUpdateRelease
        $result = Invoke-ManagerUpdateInstall -ScriptPath $global:f110Fixture.Installed -Release $release
        $result.ReasonCode | Should -BeExactly 'UPDATE_DIGEST_MISMATCH'
        $result.Summary | Should -Match 'not the same as the published file'
        $result.Summary | Should -Match 'may be damaged'
        $result.Summary | Should -Not -Match 'could not check'
        $result.Summary | Should -Not -Match '\bTPM\b'
        $result.Mutation.Started | Should -BeFalse
        [IO.File]::ReadAllText($global:f110Fixture.Installed) | Should -BeExactly '$ScriptVersion = "0.0.1"'
    }

    It 'every update summary sentence says TeknoParrot Manager, not TPM' {
        # Mutation: put "TPM" back into any $summary sentence of the updater -> ordinary output uses the internal abbreviation again.
        $function = @($script:F110UpdaterAst.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-ManagerUpdateInstall' }, $true))[0]
        $assignments = @($function.FindAll({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$summary' }, $true))
        $assignments.Count | Should -BeGreaterThan 4
        foreach ($assignment in $assignments) {
            $assignment.Right.Extent.Text | Should -Not -Match '\bTPM\b' -Because $assignment.Extent.Text
        }
    }
}

Describe 'FIX110B N-1 the standalone updater says TeknoParrot Manager' {
    It 'prints no bare TPM and uses the full product name in its labels' {
        # Mutation: restore the "[TPM updater]" prefix or the "Installed TPM version" label -> every updater line shows the abbreviation.
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($script:F110UpdaterToolPath, [ref]$tokens, [ref]$errors)
        $errors.Count | Should -Be 0
        $texts = @($ast.FindAll({
            param($n)
            $n -is [Management.Automation.Language.StringConstantExpressionAst] -or $n -is [Management.Automation.Language.ExpandableStringExpressionAst]
        }, $true) | ForEach-Object { $_.Extent.Text })
        @($texts | Where-Object { $_ -cmatch '\bTPM\b' }).Count | Should -Be 0
        (@($texts) -join "`n") | Should -Match '\[TeknoParrot Manager updater\]'
        (@($texts) -join "`n") | Should -Match 'Installed TeknoParrot Manager version:'
        (@($texts) -join "`n") | Should -Match 'Latest TeknoParrot Manager release'
    }
}
