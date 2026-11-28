#Requires -Module Pester
# Issue 509 follow-up: every game ReShade setup leaves out is named with a plain reason, and the numbers add up on both result screens.
# The fixture is a run where 84 games were ready at the first check, 80 were set up, and the rest were left out for different reasons:
# ReShade files that are not TeknoParrot Manager's, a game program whose type could not be read, a game file that moved, one game that
# did not finish, and two games the player answered No for one by one.
# Nothing touches TeknoParrot, LaunchBox, the registry or the network.
# What this CANNOT prove: how a real console paints the rows, or why a real game changed state between the two checks.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'RC95U9 bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'rc95u9-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:DisplayVersion = 'v1.0 RC9'
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
    $script:logPath = Join-Path $TestDrive 'rc95u9.log'
    $script:logWarnShown = $false

    function New-Rc95u9Result {
        $selected = @(1..100 | ForEach-Object { 'Game{0:D3}' -f $_ })
        $drops = @(
            [pscustomobject]@{ Game = 'Alpha Racer'; Id = 'Game001'; Kind = 'Protected'; Reason = 'ReShade files that TeknoParrot Manager did not install were found in the game folder, so nothing was changed.' }
            [pscustomobject]@{ Game = 'Beta Shooter'; Id = 'Game002'; Kind = 'Skipped'; Reason = 'could not tell whether this game is 32-bit or 64-bit; the game is not damaged and was left unchanged' }
            [pscustomobject]@{ Game = 'Gamma Fighter'; Id = 'Game003'; Kind = 'Skipped'; Reason = 'saved game executable was not found' }
        )
        return [pscustomobject]@{
            SelectedItems = $selected; ChangedItems = @($selected | Select-Object -First 80); SkippedItems = @($selected | Select-Object -Skip 80 -First 19); FailedItems = @('Game090')
            Deployed = 80; Errors = 1; ErrorCount = 1
            Protected = 1; Unsafe = 0; UnresolvedTarget = 0; MissingPath = 1; MissingDevice = 0; Unsupported = 0; LinuxStyle = 0; UnknownArch = 1; KeptPrevious = 0
            SourceFolderItems = @(); UnverifiedItems = @(); NativeCrtNeedsRestoreItems = @(); NativeShaderWarnings = @()
            ReadyAtCheck = 84; DroppedAfterCheck = $drops; DeclinedItems = @('Game098', 'Game099')
            SelectedProfileName = 'Crisp 3D Glow'; ProtectedRecords = @(); ProtectedDetails = @(); UnsafeDetails = @()
            SummaryDetails = @(); DetailNotes = @(); SelectedProfileTechniques = ''
        }
    }
}

Describe 'ReShade setup names every game it leaves out (issue 509)' {
    It 'adds up from the first check to the end and names each left-out game with its reason, each declined game and the game that did not finish' {
        $text = (@(Get-TpmReShadeLastCheckRows -Result (New-Rc95u9Result))) -join "`n"
        $text | Should -Match 'First check, before you confirmed: 84 ready, 16 left out\.'
        $text | Should -Match 'Of the 84 ready, 80 were set up and 3 were skipped at the last check, right before installing, and 1 did not finish\.'
        $text | Should -Match ([regex]::Escape('- Alpha Racer: ReShade files that TeknoParrot Manager did not install were found'))
        $text | Should -Match ([regex]::Escape('- Beta Shooter: could not tell whether this game is 32-bit or 64-bit'))
        $text | Should -Match ([regex]::Escape('- Gamma Fighter: saved game executable was not found'))
        $text | Should -Match 'You chose No for 2 games, so they are not counted above: Game098 and Game099\.'
        $text | Should -Match 'Did not finish: Game090\.'
    }

    It 'shows nothing extra when every ready game was set up' {
        $result = New-Rc95u9Result
        $result.ReadyAtCheck = 80; $result.DroppedAfterCheck = @(); $result.DeclinedItems = @(); $result.FailedItems = @()
        $text = (@(Get-TpmReShadeLastCheckRows -Result $result)) -join "`n"
        $text | Should -Match 'Of the 80 ready, 80 were set up and 0 were skipped'
        $text | Should -Not -Match 'Skipped at the last check \('
        $text | Should -Not -Match 'You chose No'
    }

    It 'lists every left-out game, past the first 10, in the Details' {
        $result = New-Rc95u9Result
        $result.DroppedAfterCheck = @(1..14 | ForEach-Object { [pscustomobject]@{ Game = ('Dropped {0}' -f $_); Id = ('D{0}' -f $_); Kind = 'Skipped'; Reason = 'reason' } })
        $screen = (@(Get-TpmReShadeLastCheckRows -Result $result)) -join "`n"
        $screen | Should -Match 'and 4 more\. Details lists them all\.'
        $details = @(Get-TpmReShadeBulkDetailBlocks -Result $result | Where-Object { $_.Heading -like 'Skipped at the last check*' })
        $details.Count | Should -Be 1
        $details[0].Lines.Count | Should -Be 14
        $details[0].Lines | Should -Contain 'Dropped 14: reason'
    }

    It 'prints the same numbers and names on the main-menu result screen, and does not call an unreadable game 32-bit' {
        $script:said = New-Object System.Collections.Generic.List[string]
        Mock Write-TpmText { $script:said.Add([string]$Text) }
        Mock Write-Host { }
        Mock Write-Log { }
        Mock Read-HostSafe { '' }
        Mock Read-TpmChoice { 'B' }
        Mock Show-TpmDetailBlocks { }
        $null = Show-TpmReShadeSetupResult -Result (New-Rc95u9Result)
        $plain = ($script:said -join ' ') -replace '\s+', ' '
        $plain | Should -Match 'First check, before you confirmed: 84 ready, 16 left out\.'
        $plain | Should -Match ([regex]::Escape('- Beta Shooter: could not tell whether this game is 32-bit or 64-bit'))
        $plain | Should -Match ([regex]::Escape('- Gamma Fighter: saved game executable was not found'))
        $plain | Should -Match 'Did not finish: Game090\.'
        $plain | Should -Match 'program type could not be read'
        $plain | Should -Not -Match '(?i)(games that are|are the|were) 32-bit'
    }
}
