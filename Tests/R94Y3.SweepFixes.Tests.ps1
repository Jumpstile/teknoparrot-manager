#Requires -Module Pester

# R94Y3 sweep fixes. Synthetic data only, under TestDrive. The product script is parsed and only its function definitions are
# dot-sourced; no top-level product code runs and no TeknoParrot, LaunchBox, registry or user-profile data is read or written.

BeforeAll {
    $script:R94Y3ProductionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $source = [System.IO.File]::ReadAllText($script:R94Y3ProductionPath)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'R94Y3 tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $functionFile = Join-Path $TestDrive 'tpm-r94y3-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $progressModuleDirectory = Join-Path $TestDrive 'scripts'
    [void][System.IO.Directory]::CreateDirectory($progressModuleDirectory)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Destination (Join-Path $progressModuleDirectory 'TpmProgress.psm1') -Force
    $script:RawThrillsPathLimits = @{}
    $script:FileVersionPins = @{}
    $script:EmulatorBiosRequirements = @{}
    $script:ScriptVersion = 'test'
    $script:tpRoot = $null

    function New-R94Y3GpuFixture {
        param([string[]]$Games)
        $root = Join-Path $TestDrive ('gpu-' + [guid]::NewGuid().ToString('N'))
        $profiles = Join-Path $root 'UserProfiles'
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null
        $exe = Join-Path $root 'game.exe'
        [System.IO.File]::WriteAllText($exe, 'x')
        foreach ($game in $Games) {
            [System.IO.File]::WriteAllText((Join-Path $profiles ($game + '.xml')), ('<?xml version="1.0" encoding="utf-8"?><GameProfile><EmulatorType>Other</EmulatorType><GamePath>{0}</GamePath></GameProfile>' -f $exe))
        }
        return [pscustomobject]@{ Root = $root; Profiles = $profiles }
    }
}

Describe 'Graphics-card warnings reach AMD and Intel players (item 1)' {
    BeforeEach {
        Mock Write-Log { }
        Mock Write-Host { }
        Mock Write-TpmText { }
    }

    It 'warns for a card maker whose shipped list has many codes (and for a code in a different letter case)' {
        $script:GpuIncompatibleGames = @{ 'AMD' = @('GameA', 'GameB', 'GameC') }
        Mock Get-DetectedGpuVendor { [pscustomobject]@{ Vendor = 'AMD' } }
        Mock Get-TpmGameRulesGpuCodes { @() }
        Mock Get-TpmMetadataGpuIncompatibleCodes { @() }
        $fixture = New-R94Y3GpuFixture -Games @('gameb', 'GameZ')
        $result = Get-CompatibilityWarnings -UserProfilesDir $fixture.Profiles -ErrorVariable gpuErrors -ErrorAction SilentlyContinue
        @($gpuErrors | Where-Object { $_ } | ForEach-Object { [string]$_ }) | Should -Be @()
        @($result.GpuIncompatible).Count | Should -Be 1
        $result.GpuIncompatible[0].Code | Should -Be 'gameb'
        $result.GpuIncompatible[0].Vendor | Should -Be 'AMD'
    }

    It 'warns for a card maker whose shipped list has exactly one code' {
        $script:GpuIncompatibleGames = @{ 'Intel' = @('OnlyGame') }
        Mock Get-DetectedGpuVendor { [pscustomobject]@{ Vendor = 'Intel' } }
        Mock Get-TpmGameRulesGpuCodes { @() }
        Mock Get-TpmMetadataGpuIncompatibleCodes { @() }
        $fixture = New-R94Y3GpuFixture -Games @('OnlyGame')
        $result = Get-CompatibilityWarnings -UserProfilesDir $fixture.Profiles -ErrorVariable gpuErrors -ErrorAction SilentlyContinue
        @($gpuErrors | Where-Object { $_ } | ForEach-Object { [string]$_ }) | Should -Be @()
        @($result.GpuIncompatible).Count | Should -Be 1
    }

    It 'warns from the signed rules and TeknoParrot metadata codes when the shipped list has none for this card maker' {
        $script:GpuIncompatibleGames = @{}
        Mock Get-DetectedGpuVendor { [pscustomobject]@{ Vendor = 'Intel' } }
        Mock Get-TpmGameRulesGpuCodes { @('RuleGame') }
        Mock Get-TpmMetadataGpuIncompatibleCodes { @('MetaGame') }
        $fixture = New-R94Y3GpuFixture -Games @('RuleGame', 'MetaGame', 'Fine')
        $result = Get-CompatibilityWarnings -UserProfilesDir $fixture.Profiles -ErrorVariable gpuErrors -ErrorAction SilentlyContinue
        @($gpuErrors | Where-Object { $_ } | ForEach-Object { [string]$_ }) | Should -Be @()
        @($result.GpuIncompatible | ForEach-Object { $_.Code } | Sort-Object) | Should -Be @('MetaGame', 'RuleGame')
    }

    It 'adds nothing for a card maker with no codes anywhere and shows no error' {
        $script:GpuIncompatibleGames = @{}
        Mock Get-DetectedGpuVendor { [pscustomobject]@{ Vendor = 'NVIDIA' } }
        Mock Get-TpmGameRulesGpuCodes { @() }
        Mock Get-TpmMetadataGpuIncompatibleCodes { @() }
        $fixture = New-R94Y3GpuFixture -Games @('GameA')
        $result = Get-CompatibilityWarnings -UserProfilesDir $fixture.Profiles -ErrorVariable gpuErrors -ErrorAction SilentlyContinue
        @($gpuErrors | Where-Object { $_ } | ForEach-Object { [string]$_ }) | Should -Be @()
        @($result.GpuIncompatible).Count | Should -Be 0
    }
}

Describe 'The firmware next step is firmware-specific even before a plan exists (item 1, bug 3)' {
    It 'points a PlayStation 3 firmware finding at the player''s own collection when the screen is drawn without a plan' {
        $warning = [pscustomobject]@{ EmulatorType = 'RPCS3'; AffectedGames = @('GameA'); MissingFiles = @('liblv2.sprx'); ExpectedDir = 'X:\emu\dev_flash'; Requirement = @{ InstallVia = 'RPCS3' } }
        $lines = Get-TpmPrerequisiteScreenLines -Warning $warning
        (@($lines.Plain) -join ' ') | Should -Match 'PlayStation 3 style hardware'
    }
}

Describe 'A CRT setting that was already off is not reported as turned off (item 2, bug 3)' {
    BeforeAll {
        function New-R94Y3CrtRecord {
            param([string]$Game, [string]$Outcome)
            $ok = ($Outcome -ceq 'TurnedOff' -or $Outcome -ceq 'AlreadyOff')
            return [pscustomobject]@{ Game = $Game; Field = 'Video / CRT Shader'; OldValue = 'None'; NewValue = 'None'; Succeeded = $ok; Outcome = $Outcome; RolledBack = $false; NeedsRestore = $false; Reason = ''; TempRemoved = @(); TempKept = @() }
        }
    }
    BeforeEach {
        Mock Write-Log { }
        $script:r94y3Outcome = $null
        Mock Write-TpmOutcome { $script:r94y3Outcome = @{ Title = $Title; Done = @($Done); NotChanged = $NotChanged; Blocks = @($DetailBlocks) } }
    }

    It 'says it was already off when nothing had to change' {
        $state = [pscustomobject]@{ Requested = $true; Items = @{ GameOne = $null }; NotOffered = @(); BackupTried = $true; BackupOk = $true; BackupPath = 'C:\Backup'; BackupReason = ''; Records = @(New-R94Y3CrtRecord -Game 'GameOne' -Outcome 'AlreadyOff') }
        Write-TpmReShadeNativeCrtOutcome -State $state
        $script:r94y3Outcome.Title | Should -Match 'already off'
        $script:r94y3Outcome.Title | Should -Not -Match 'was turned off'
        (@($script:r94y3Outcome.Blocks | Where-Object { $_.Heading -ceq 'GameOne' })[0].Lines -join ' ') | Should -Match 'already off'
        (@($script:r94y3Outcome.Blocks | Where-Object { $_.Heading -ceq 'GameOne' })[0].Lines -join ' ') | Should -Not -Match 'turned off'
    }

    It 'counts only the games that really changed as turned off' {
        $records = @((New-R94Y3CrtRecord -Game 'GameOne' -Outcome 'TurnedOff'), (New-R94Y3CrtRecord -Game 'GameTwo' -Outcome 'AlreadyOff'))
        $state = [pscustomobject]@{ Requested = $true; Items = @{ GameOne = $null; GameTwo = $null }; NotOffered = @(); BackupTried = $true; BackupOk = $true; BackupPath = 'C:\Backup'; BackupReason = ''; Records = $records }
        Write-TpmReShadeNativeCrtOutcome -State $state
        $script:r94y3Outcome.Title | Should -Match 'turned off for 1 game\.'
        $script:r94y3Outcome.Title | Should -Match 'already had it off'
    }
}

Describe 'The crosshair preview answers an empty list gracefully (item 2, bug 1)' {
    It 'returns NO_CROSSHAIRS instead of a binding error' {
        $result = Show-TpmCrosshairPreviewWindow -CrosshairPaths @()
        $result.Reason | Should -Be 'NO_CROSSHAIRS'
        $result.Available | Should -BeFalse
    }
}
