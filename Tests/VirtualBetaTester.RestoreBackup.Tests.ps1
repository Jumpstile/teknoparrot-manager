#Requires -Module Pester

# TPM Certification Suite Phase 1.7 (issue #88, priority A2): Restore Backup
# Behavioral Recovery. Invoke-RestoreBackup had zero prior test coverage of
# any kind despite being one of TPM's highest-value safety features -- it
# is the last line of defense if a run goes wrong. Each test documents the
# human behavior replaced, the defect class it catches, and why existing
# certification wouldn't already catch it.
#
# Deterministic: no network, no GUI, no real TeknoParrot root, all writes
# confined to $TestDrive. Read-Host is mocked to drive the interactive
# choice/confirm prompts deterministically.
#
# Run with: Invoke-Pester -Path .\Tests\VirtualBetaTester.RestoreBackup.Tests.ps1

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "..\TeknoParrot-Manager.ps1"
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Failed to parse TeknoParrot-Manager.ps1: $($parseErrors -join '; ')"
    }
    $functionAsts = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $extractedFunctionsPath = Join-Path $TestDrive ("vbt-restore-backup-functions-" + [guid]::NewGuid().ToString('N') + '.ps1')
    ($functionAsts | ForEach-Object { $_.Extent.Text }) -join "`n`n" | Set-Content -LiteralPath $extractedFunctionsPath -Encoding utf8
    . $extractedFunctionsPath

    $script:logPath = Join-Path $TestDrive "vbt-restore-backup.log"

    function New-RestoreFixture {
        param([string]$Name)
        $root = Join-Path $TestDrive ($Name + '-' + [guid]::NewGuid().ToString('N'))
        $userProfilesDir = Join-Path $root 'UserProfiles'
        New-Item -ItemType Directory -Path $userProfilesDir -Force | Out-Null
        return $userProfilesDir
    }
}

Describe "Virtual Beta Tester: restore backup enumeration and selection (issue #88 A2)" -Tag 'TVD-High' {
    It "restores the selected backup's content into UserProfiles, replacing current content" {
        $userProfilesDir = New-RestoreFixture -Name 'restore-basic'
        Set-Content -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml') -Value '<GameProfile>current</GameProfile>' -Encoding ascii
        $backupDir = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2026-07-01_12-00-00'
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $backupDir 'ALIENS.xml') -Value '<GameProfile>backed-up</GameProfile>' -Encoding ascii
        Mock Read-Host { return "1" } -ParameterFilter { $Prompt -like "*Enter number to restore*" }
        Mock Read-Host { return "YES" } -ParameterFilter { $Prompt -like "*Type YES to confirm*" }
        Mock Wait-TpmForProcessClose { return $true }
        Invoke-RestoreBackup -userProfilesDir $userProfilesDir
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'ALIENS.xml')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml')) | Should -Be $false
    }

    It "picks the correct backup when multiple exist (numbered by the sorted, most-recent-first list)" {
        $userProfilesDir = New-RestoreFixture -Name 'restore-multi'
        $newerDir = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2026-07-02_09-00-00'
        $olderDir = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2026-07-01_09-00-00'
        New-Item -ItemType Directory -Path $newerDir -Force | Out-Null
        New-Item -ItemType Directory -Path $olderDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $newerDir 'NEWER.xml') -Value '<GameProfile>newer</GameProfile>' -Encoding ascii
        Set-Content -LiteralPath (Join-Path $olderDir 'OLDER.xml') -Value '<GameProfile>older</GameProfile>' -Encoding ascii
        Mock Read-Host { return "1" } -ParameterFilter { $Prompt -like "*Enter number to restore*" }
        Mock Read-Host { return "YES" } -ParameterFilter { $Prompt -like "*Type YES to confirm*" }
        Mock Wait-TpmForProcessClose { return $true }
        Invoke-RestoreBackup -userProfilesDir $userProfilesDir
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'NEWER.xml')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'OLDER.xml')) | Should -Be $false
    }
}

Describe "Virtual Beta Tester: restore backup safe cancel/decline (issue #88 A2 / A4)" -Tag 'TVD-High' {
    It "pressing Enter at the backup-selection prompt cancels with zero changes" {
        $userProfilesDir = New-RestoreFixture -Name 'restore-cancel-select'
        Set-Content -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml') -Value '<GameProfile>current</GameProfile>' -Encoding ascii
        $backupDir = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2026-07-01_12-00-00'
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $backupDir 'ALIENS.xml') -Value '<GameProfile>backed-up</GameProfile>' -Encoding ascii
        Mock Read-Host { return "" } -ParameterFilter { $Prompt -like "*Enter number to restore*" }
        Invoke-RestoreBackup -userProfilesDir $userProfilesDir
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml')) | Should -Be $true
        (Test-Path -LiteralPath $backupDir) | Should -Be $true
    }

    It "declining the YES confirmation cancels with zero changes -- current content is never deleted before confirmation" {
        $userProfilesDir = New-RestoreFixture -Name 'restore-decline-confirm'
        Set-Content -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml') -Value '<GameProfile>current</GameProfile>' -Encoding ascii
        $backupDir = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2026-07-01_12-00-00'
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $backupDir 'ALIENS.xml') -Value '<GameProfile>backed-up</GameProfile>' -Encoding ascii
        Mock Read-Host { return "1" } -ParameterFilter { $Prompt -like "*Enter number to restore*" }
        Mock Read-Host { return "no" } -ParameterFilter { $Prompt -like "*Type YES to confirm*" }
        Invoke-RestoreBackup -userProfilesDir $userProfilesDir
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'ALIENS.xml')) | Should -Be $false
    }

    It "an invalid selection (out of range) is treated as a cancel with zero changes" {
        $userProfilesDir = New-RestoreFixture -Name 'restore-invalid-select'
        Set-Content -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml') -Value '<GameProfile>current</GameProfile>' -Encoding ascii
        $backupDir = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2026-07-01_12-00-00'
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $backupDir 'ALIENS.xml') -Value '<GameProfile>backed-up</GameProfile>' -Encoding ascii
        Mock Read-Host { return "99" } -ParameterFilter { $Prompt -like "*Enter number to restore*" }
        Invoke-RestoreBackup -userProfilesDir $userProfilesDir
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'ALIENS.xml')) | Should -Be $false
    }
}

Describe "Virtual Beta Tester: restore backup malformed-backup rejection (issue #88 A2)" -Tag 'TVD-High' {
    It "refuses to restore a backup folder containing zero XML profiles, leaving current content untouched" {
        $userProfilesDir = New-RestoreFixture -Name 'restore-empty-backup'
        Set-Content -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml') -Value '<GameProfile>current</GameProfile>' -Encoding ascii
        $emptyBackupDir = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2026-07-01_12-00-00'
        New-Item -ItemType Directory -Path $emptyBackupDir -Force | Out-Null
        Mock Read-Host { return "1" } -ParameterFilter { $Prompt -like "*Enter number to restore*" }
        Invoke-RestoreBackup -userProfilesDir $userProfilesDir
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml')) | Should -Be $true
    }
}

Describe "Virtual Beta Tester: restore backup preserves unrelated state (issue #88 A2)" -Tag 'TVD-High' {
    It "restoring one backup leaves every other backup snapshot in FullBackup completely intact" {
        $userProfilesDir = New-RestoreFixture -Name 'restore-preserves-siblings'
        $selectedDir = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2026-07-02_09-00-00'
        $siblingDir  = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2026-07-01_09-00-00'
        New-Item -ItemType Directory -Path $selectedDir -Force | Out-Null
        New-Item -ItemType Directory -Path $siblingDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $selectedDir 'SELECTED.xml') -Value '<GameProfile>selected</GameProfile>' -Encoding ascii
        Set-Content -LiteralPath (Join-Path $siblingDir 'SIBLING.xml') -Value '<GameProfile>sibling</GameProfile>' -Encoding ascii
        Mock Read-Host { return "1" } -ParameterFilter { $Prompt -like "*Enter number to restore*" }
        Mock Read-Host { return "YES" } -ParameterFilter { $Prompt -like "*Type YES to confirm*" }
        Mock Wait-TpmForProcessClose { return $true }
        Invoke-RestoreBackup -userProfilesDir $userProfilesDir
        (Test-Path -LiteralPath (Join-Path $siblingDir 'SIBLING.xml')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $selectedDir 'SELECTED.xml')) | Should -Be $true
    }

    It "refuses to restore while TeknoParrotUi.exe is running, leaving current content untouched" {
        $userProfilesDir = New-RestoreFixture -Name 'restore-tp-running'
        Set-Content -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml') -Value '<GameProfile>current</GameProfile>' -Encoding ascii
        $backupDir = Join-Path $userProfilesDir 'FullBackup\PropagateControls_2026-07-01_12-00-00'
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $backupDir 'ALIENS.xml') -Value '<GameProfile>backed-up</GameProfile>' -Encoding ascii
        Mock Read-Host { return "1" } -ParameterFilter { $Prompt -like "*Enter number to restore*" }
        Mock Read-Host { return "YES" } -ParameterFilter { $Prompt -like "*Type YES to confirm*" }
        Mock Wait-TpmForProcessClose { return $false }
        Invoke-RestoreBackup -userProfilesDir $userProfilesDir
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'CURRENT.xml')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $userProfilesDir 'ALIENS.xml')) | Should -Be $false
    }
}
