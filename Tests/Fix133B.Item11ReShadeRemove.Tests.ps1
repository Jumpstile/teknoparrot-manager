#Requires -Module Pester
BeforeAll {
    $prod = (Join-Path (Split-Path -Parent $PSScriptRoot) 'TeknoParrot-Manager.ps1')
    $tokens = $null; $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText($prod), [ref]$tokens, [ref]$errs)
    $defs = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    $ff = Join-Path $TestDrive ('f133b11-' + [guid]::NewGuid().ToString('N') + '.ps1')
    [IO.File]::WriteAllText($ff, (@($defs | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"), (New-Object Text.UTF8Encoding $false))
    . $ff
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Tests\TpmExtractedScriptState.ps1')
}
Describe 'F133B finding 11' {
    It 'Remove after the user edited ReShade.ini must not leave a manifest that blocks later setup' {
        Mock Write-TpmCompactExtractionProgress {}
        Mock Write-Log {}
        $root = Join-Path $TestDrive ('f11-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        $profiles = Join-Path $root 'UserProfiles'; $state = Join-Path $root 'state'; $gameDir = Join-Path $root 'game'
        [void][IO.Directory]::CreateDirectory($profiles); [void][IO.Directory]::CreateDirectory($gameDir)
        $exe = Join-Path $gameDir 'game.exe'; $hook = Join-Path $gameDir 'dxgi.dll'; $ini = Join-Path $gameDir 'ReShade.ini'
        [IO.File]::WriteAllText($exe, 'game'); [IO.File]::WriteAllText($hook, 'tpm-dll'); [IO.File]::WriteAllText($ini, "; TPM-managed approved ReShade profile: CleanSharp`r`n")
        [IO.File]::WriteAllText((Join-Path $profiles 'G.xml'), "<GameProfile><GamePath>$exe</GamePath><EmulatorType>Default</EmulatorType></GameProfile>")
        $hHash = (Get-FileHash $hook -Algorithm SHA256).Hash; $iHash = (Get-FileHash $ini -Algorithm SHA256).Hash
        $mp = Get-TpmReShadeProfileOwnershipPath -GameId G -StateRoot $state
        Save-TpmReShadeOwnershipManifest -Path $mp -Manifest ([pscustomobject]@{ SchemaVersion = 1; EffectId = 'ReShadeProfile.CleanSharp'; PinnedRevision = 'TPM-PROFILE'; Files = @(
            [pscustomobject]@{ RelativeSource = 'dxgi.dll'; DestinationPath = $hook; ExpectedSHA256 = $hHash; ActualSHA256 = $hHash; TPMManaged = $true; Kind = 'ReShadeDll' },
            [pscustomobject]@{ RelativeSource = 'ReShade.ini'; DestinationPath = $ini; ExpectedSHA256 = $iHash; ActualSHA256 = $iHash; TPMManaged = $true; Kind = 'ReShadePreset' }) })
        [IO.File]::AppendAllText($ini, "EffectSearchPaths=C:\mine`r`n")   # user edits ReShade.ini
        $scan = Get-TpmReShadeRemovalScan -UserProfilesDir $profiles -StateRoot $state
        $res = Remove-TpmReShadeOwnedDeployment -ScanRecord @($scan.Records | Where-Object { $_.Status -eq 'Removable' })[0] -UserProfilesDir $profiles -BackupRoot (Join-Path $root 'bk') -StateRoot $state -ConfirmRemoval
        Write-Host ("REMOVE status={0} hookExists={1} iniExists={2} manifestExists={3}" -f $res.Status, (Test-Path $hook), (Test-Path $ini), (Test-Path $mp))
        $m = Read-TpmReShadeOwnershipManifest -Path $mp
        Write-Host ('manifest kinds left: ' + ((@($m.Files) | ForEach-Object Kind) -join ','))
        $cls = Get-TpmReShadeOwnershipClassification -HookPath $hook -TargetRoot $gameDir -ProfileDefinition ([pscustomobject]@{ ProfileId = 'CleanSharp' }) -Manifest $m
        Write-Host ("CLASS={0} -- {1}" -f $cls.Status, $cls.Detail)
        # The removal itself must have happened as the title says: TPM's own DLL gone, the user's edited ReShade.ini kept, and no manifest left behind.
        $res.Status | Should -Be 'Removed'
        Test-Path -LiteralPath $hook | Should -BeFalse
        Test-Path -LiteralPath $ini | Should -BeTrue
        Test-Path -LiteralPath $mp | Should -BeFalse
        # The user's edited ReShade.ini stays and is theirs: later setup treats it as a user-owned file (it saves a copy first), not as TPM ownership, so nothing blocks setup.
        $cls.Status | Should -Be 'UnknownUserOwnedConflict'
    }
}
