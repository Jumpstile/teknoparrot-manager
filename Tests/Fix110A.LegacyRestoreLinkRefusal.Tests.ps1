#Requires -Module Pester

# FIX110A (S-25): the UserProfiles restore worker (Invoke-RestoreBackupLegacy, reached by the main-menu restore through Invoke-RestoreBackup
#   and by Reset and Restore) refuses a link (junction or symlink) inside UserProfiles before it takes the rollback snapshot or
#   removes anything. Before, only the Reset and Restore route ran that refusal; the main-menu route copied and deleted
#   top-level entries without it.
# The production script is parsed and only its function definitions are dot-sourced; no top-level product code runs.
# Everything lives under TestDrive with synthetic files and a junction between two TestDrive folders. TEMP and TMP point into
# TestDrive while a test runs, so a rollback snapshot (which would be made in the temp folder) can be seen.
# Each It names the product change that makes it fail.
# What this CANNOT prove: what Windows PowerShell would do with a link target in the old code (not tested).

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX110A tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $functionFile = Join-Path $TestDrive 'tpm-fix110a-restore-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:F110BackupName = 'Startup_2026-11-03_10-00-57_326_c8ae9bbf'

    # A UserProfiles folder with one live profile and one saved copy; -WithLink adds a junction to a folder outside it.
    function New-F110RestoreFixture {
        param([switch]$WithLink)
        $root = Join-Path $TestDrive ('f110-restore-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $profiles = Join-Path $root 'UserProfiles'
        $outside = Join-Path $root 'Outside'
        $privateTemp = Join-Path $root 'Temp'
        $folder = Join-Path (Join-Path $profiles 'FullBackup') $script:F110BackupName
        foreach ($dir in @($profiles, $outside, $privateTemp, $folder)) { [void][System.IO.Directory]::CreateDirectory($dir) }
        [System.IO.File]::WriteAllText((Join-Path $profiles 'CURRENT.xml'), '<GameProfile><GameName>Current</GameName></GameProfile>')
        [System.IO.File]::WriteAllText((Join-Path $folder 'G.xml'), '<GameProfile><GameName>Backed up</GameName></GameProfile>')
        [System.IO.File]::WriteAllText((Join-Path $outside 'Outside.xml'), '<GameProfile><GameName>Not ours</GameName></GameProfile>')
        $link = Join-Path $profiles 'LinkedFolder'
        if ($WithLink) { [void](New-Item -ItemType Junction -Path $link -Target $outside) }
        return [pscustomobject]@{ Profiles = $profiles; Outside = $outside; Link = $link; BackupFolder = $folder; PrivateTemp = $privateTemp }
    }
}

Describe 'FIX110A S-25: the UserProfiles restore refuses a link before it snapshots or deletes anything' {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-Host {}
        Mock Write-TpmCompactExtractionProgress {}
        Mock Wait-TpmForProcessClose { return $true }
        Mock Read-HostSafe { return 'UNVERIFIED' }
        $script:F110SavedTemp = $env:TEMP
        $script:F110SavedTmp = $env:TMP
    }
    AfterEach {
        $env:TEMP = $script:F110SavedTemp
        $env:TMP = $script:F110SavedTmp
        if ($null -ne $script:F110Fixture -and (Test-Path -LiteralPath $script:F110Fixture.Link)) { [System.IO.Directory]::Delete($script:F110Fixture.Link) }
        $script:F110Fixture = $null
    }

    It 'restores normally when UserProfiles has no link' {
        # Mutation: refuse always (for example a broken footprint check) -> the ordinary restore no longer runs.
        $script:F110Fixture = New-F110RestoreFixture
        $env:TEMP = $script:F110Fixture.PrivateTemp; $env:TMP = $script:F110Fixture.PrivateTemp
        $result = Invoke-RestoreBackupLegacy -userProfilesDir $script:F110Fixture.Profiles -SelectedBackupPath $script:F110Fixture.BackupFolder -AlreadyConfirmed
        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        Test-Path -LiteralPath (Join-Path $script:F110Fixture.Profiles 'G.xml') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:F110Fixture.Profiles 'CURRENT.xml') | Should -BeFalse
    }

    It 'refuses before any snapshot or deletion when UserProfiles holds a link' {
        # Mutation: remove the footprint refusal from Invoke-RestoreBackupLegacy -> the worker snapshots, deletes the live entries and restores.
        $script:F110Fixture = New-F110RestoreFixture -WithLink
        $env:TEMP = $script:F110Fixture.PrivateTemp; $env:TMP = $script:F110Fixture.PrivateTemp
        $result = Invoke-RestoreBackupLegacy -userProfilesDir $script:F110Fixture.Profiles -SelectedBackupPath $script:F110Fixture.BackupFolder -AlreadyConfirmed
        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -BeExactly 'LINK_INSIDE_USERPROFILES'
        $result.Summary | Should -Match 'Nothing was changed'
        $result.Summary | Should -Match 'link'
        Test-Path -LiteralPath (Join-Path $script:F110Fixture.Profiles 'CURRENT.xml') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:F110Fixture.Profiles 'G.xml') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:F110Fixture.Outside 'Outside.xml') | Should -BeTrue
        Test-Path -LiteralPath $script:F110Fixture.Link | Should -BeTrue
        @(Get-ChildItem -LiteralPath $script:F110Fixture.PrivateTemp -Force -Filter 'tpm-restore-rollback-*').Count | Should -Be 0
    }

    It 'gives the same refusal through the main-menu route (Invoke-RestoreBackup)' {
        # Mutation: run the refusal only for the Reset and Restore route -> the main-menu route wrapper returns a restore result.
        $script:F110Fixture = New-F110RestoreFixture -WithLink
        $env:TEMP = $script:F110Fixture.PrivateTemp; $env:TMP = $script:F110Fixture.PrivateTemp
        $result = Invoke-RestoreBackup -userProfilesDir $script:F110Fixture.Profiles -SelectedBackupPath $script:F110Fixture.BackupFolder -AlreadyConfirmed
        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -BeExactly 'LINK_INSIDE_USERPROFILES'
        Test-Path -LiteralPath (Join-Path $script:F110Fixture.Profiles 'CURRENT.xml') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:F110Fixture.Outside 'Outside.xml') | Should -BeTrue
    }
}
