#Requires -Module Pester

# Issue 387 (regression only): the startup-file check used to cover only PCSX2x6 and Chihiro. On this branch the table also covers
# RPCS3 (PlayStation 3 firmware, marker liblv2.sprx) and Play! (per-game arcadedef). This pins what the user sees: a game on RPCS3
# whose firmware is missing is reported (not shown as ready), and is not reported once the firmware marker file is there.
# Synthetic files only, under TestDrive. Mutation: remove the RPCS3 entry from the table -> the first test fails.

BeforeAll {
    $script:F387ProductionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $source = [System.IO.File]::ReadAllText($script:F387ProductionPath)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX387 tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $functionFile = Join-Path $TestDrive 'tpm-fix387-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $progressModuleDirectory = Join-Path $TestDrive 'scripts'
    [void][System.IO.Directory]::CreateDirectory($progressModuleDirectory)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Destination (Join-Path $progressModuleDirectory 'TpmProgress.psm1') -Force
    $assignment = @($ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -eq '$EmulatorBiosRequirements' })
    if ($assignment.Count -ne 1) { throw 'FIX387 tests expected exactly one production assignment of $EmulatorBiosRequirements.' }
    $script:EmulatorBiosRequirements = & ([scriptblock]::Create($assignment[0].Right.Extent.Text))
    $script:RawThrillsPathLimits = @{}
    $script:FileVersionPins = @{}
    $script:GpuIncompatibleGames = @{}
    $script:ScriptVersion = 'test'
    $script:tpRoot = $null

    function New-F387Root {
        param([string[]]$Games = @('Tekken6'))
        $root = Join-Path $TestDrive ('f387-' + [guid]::NewGuid().ToString('N'))
        $profiles = Join-Path $root 'UserProfiles'
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null
        foreach ($game in $Games) {
            [System.IO.File]::WriteAllText((Join-Path $profiles ($game + '.xml')), '<?xml version="1.0" encoding="utf-8"?><GameProfile><EmulatorType>RPCS3</EmulatorType><GamePath>C:\Games\game.exe</GamePath></GameProfile>')
        }
        New-Item -ItemType Directory -Path (Join-Path $root 'RPCS3') -Force | Out-Null
        return [pscustomobject]@{ Root = $root; Profiles = $profiles; Rpcs3 = (Join-Path $root 'RPCS3') }
    }
}

Describe 'The startup-file check covers more than PCSX2x6 and Chihiro (issue 387)' {
    BeforeEach {
        Mock Write-Log { }
        Mock Write-Host { }
        Mock Write-TpmText { }
    }

    It 'knows PCSX2x6, Chihiro, RPCS3 and Play!' {
        foreach ($type in @('Pcsx2x6', 'cxbxr', 'RPCS3', 'Play')) {
            $script:EmulatorBiosRequirements.ContainsKey($type) | Should -BeTrue -Because $type
        }
    }

    It 'reports an RPCS3 game whose firmware is missing, naming the game and the missing file' {
        $fixture = New-F387Root -Games @('Tekken6', 'ttt2')
        $found = @((Get-CompatibilityWarnings -UserProfilesDir $fixture.Profiles -TeknoParrotRoot $fixture.Root).BiosMissing)
        $found.Count | Should -Be 1
        $found[0].EmulatorType | Should -Be 'RPCS3'
        @($found[0].MissingFiles) | Should -Be @('liblv2.sprx')
        @($found[0].AffectedGames) | Should -Be @('Tekken6', 'ttt2')
        $found[0].ExpectedDir | Should -Be (Join-Path $fixture.Rpcs3 'dev_flash\sys\external')
    }

    It 'does not report the game once the firmware marker file is in place' {
        $fixture = New-F387Root
        $dir = Join-Path $fixture.Rpcs3 'dev_flash\sys\external'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $dir 'liblv2.sprx') -Force | Out-Null
        @((Get-CompatibilityWarnings -UserProfilesDir $fixture.Profiles -TeknoParrotRoot $fixture.Root).BiosMissing).Count | Should -Be 0
    }
}
