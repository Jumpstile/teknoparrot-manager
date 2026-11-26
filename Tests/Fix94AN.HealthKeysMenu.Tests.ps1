#Requires -Module Pester

# FIX94AN: three user-visible bugs.
#   B1  the library health "Game database" row threw under strict mode when a game uses Internal storage
#   B2  a control the player was asked to press again and skipped kept its old saved key
#   B3  the compact main menu dropped option numbers in its number-only fallback
# The production script is parsed and only its function definitions are dot-sourced; no top-level product code runs.
# Everything uses temp folders and fake key presses.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX94AN tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $functionFile = Join-Path $TestDrive 'tpm-fix94an-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
    function New-F94Folder {
        $folder = Join-Path $TestDrive ('f94-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        [void][System.IO.Directory]::CreateDirectory($folder)
        return $folder
    }
}

Describe 'Library health Game database row' {
    It 'says "uses" for 1 game and "use" for 2 games, under strict mode' {
        # Mutation: pass the old third argument ($Report.S11Games) -> strict mode throws.
        Set-StrictMode -Version Latest
        $base = @{ DiscoveryComplete = $true; Registered = 2; Broken = @(); Empty = @(); Valid = @('a', 'b'); Unreadable = @(); GpuFixNeeded = @(); FfbBlasterNeeded = @(); DgVoodoo2Needed = @(); PostgresNeeded = @(); PostgresConfigured = 0; PostgresInventoryStatus = 'Complete' }
        $one = [pscustomobject]($base + @{ InternalDatabaseLabels = @('Game A') })
        $two = [pscustomobject]($base + @{ InternalDatabaseLabels = @('Game A', 'Game B') })
        $rowOne = @(Get-TpmLibraryHealthRows -Result $one | Where-Object Area -eq 'Game database')
        $rowTwo = @(Get-TpmLibraryHealthRows -Result $two | Where-Object Area -eq 'Game database')
        $rowOne.Count | Should -Be 1
        $rowOne[0].Text | Should -Match '^OK - 1 game uses Internal storage, so no database install is needed\. Start each game once'
        $rowTwo[0].Text | Should -Match '^OK - 2 games use Internal storage, so no database install is needed\. Start each game once'
    }
}

Describe 'Learning arcade buttons: a skipped control loses its old key' {
    BeforeEach {
        Mock Write-Host { }
        Mock Write-Log { }
        Mock Test-TpmKeyPressAvailable { $true }
        Mock Read-TpmChoice { '1' }
        Mock Get-TpmKeysPressedOnTheirOwn { @() }
        Mock Get-TpmLedBlinkyKeyMap { [pscustomobject]@{ Found = $false; Controls = @() } }
        Mock Get-TpmStandardArcadeKeys { [ordered]@{} }
        Mock Get-TpmControllerEvidence { [pscustomobject]@{ EvidenceStatus = 'Observed'; DeviceObservations = @() } }
        Mock Get-TpmEncoderCount { 0 }
        Mock Get-TpmEncoderFingerprints { @() }
    }

    It 'removes the saved key of a control skipped on "press every control again", and keeps a control that was kept' {
        # Mutation: drop the Remove-TpmCabinetKey loop -> the skipped control keeps its old key.
        $state = New-F94Folder
        $controls = @(Get-TpmCabinetControlList -Players 1 -Buttons 1)
        $cabinet = Read-TpmCabinetState -StateRoot $state
        $saved = @{}
        foreach ($control in $controls) { $saved[[string]$control.Control] = @{ Key = ('OLD' + $saved.Count); Source = 'PressedByPlayer' } }
        Set-TpmCabinetKeys -State $cabinet -Keys $saved -Players 1 -ButtonsPerPlayer 1
        Save-TpmCabinetState -State $cabinet -StateRoot $state
        $skippedId = [string]$controls[0].Control
        $script:f94Skip = $skippedId
        Mock Read-TpmYesNo { if ($Prompt -match 'Save this') { 'Y' } else { 'N' } }
        Mock Invoke-TpmLearnKeys {
            $k = @{}
            foreach ($c in @($Controls)) { if ([string]$c.Control -ne $script:f94Skip) { $k[[string]$c.Control] = 'NEW' } }
            [pscustomobject]@{ Keys = $k; Skipped = @($script:f94Skip) }
        }
        Invoke-TpmButtonLearning -StateRoot $state
        $after = Read-TpmCabinetState -StateRoot $state
        (Get-TpmCabinetKey -State $after -Control $skippedId) | Should -Be ''
        (Get-TpmCabinetKey -State $after -Control ([string]$controls[1].Control)) | Should -Be 'NEW'

        # Keep-the-saved-keys answer: nothing is asked, a skipped-free run keeps every key.
        $state2 = New-F94Folder
        $cab2 = Read-TpmCabinetState -StateRoot $state2
        Set-TpmCabinetKeys -State $cab2 -Keys $saved -Players 1 -ButtonsPerPlayer 1
        Save-TpmCabinetState -State $cab2 -StateRoot $state2
        Mock Read-TpmYesNo { if ($Prompt -match 'Save this|Keep those') { 'Y' } else { 'N' } }
        Invoke-TpmButtonLearning -StateRoot $state2
        $kept = Read-TpmCabinetState -StateRoot $state2
        (Get-TpmCabinetKey -State $kept -Control $skippedId) | Should -Be $saved[$skippedId].Key
    }
}

Describe 'Compact main menu keeps every option number' {
    It 'shows every menu number when the row budget is tiny' -ForEach @(@{ Rows = 8 }, @{ Rows = 5 }, @{ Rows = 3 }) {
        # Mutation: restore the unconditional Select-Object -Last cut -> the earliest numbers vanish (all of them at budget 0).
        $geometry = Get-MainMenuGeometry -Tier 'Compact' -ViewportWidth 60 -ViewportHeight 10
        $rows = @(Get-MainMenuEmergencyCompactRows -Geometry $geometry -MaxRows $Rows)
        $expected = @(Get-MainMenuItems | ForEach-Object { [int]$_.Number })
        $visible = @(Get-MainMenuVisibleOptionNumbers -Rows $rows)
        @($expected | Where-Object { $visible -notcontains $_ }) | Should -BeNullOrEmpty
    }
}
