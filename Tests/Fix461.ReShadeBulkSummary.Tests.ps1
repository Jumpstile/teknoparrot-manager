#Requires -Module Pester
# Issue 461: the bulk ReShade result screen. A tester set up 331 games: 35 were eligible and all 35 were installed, but the screen printed
# 697 game names in four lists, one message per skipped game, and "partial data safety" / "try again" warnings as if part of the install
# had failed. These tests drive the real summary functions with synthetic results; nothing touches TeknoParrot, LaunchBox or the network.
# What this CANNOT prove: how a real console paints the rows.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX461 bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'fix461-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')

    # The tester's run: 331 selected, 35 installed, 296 left alone for different reasons, nothing failed.
    function New-Fix461Result {
        param([int]$Failed = 0)
        $selected = @(1..331 | ForEach-Object { 'Game{0:D3}' -f $_ })
        $changed = @($selected | Select-Object -First (35 - $Failed))
        $skipped = @($selected | Select-Object -Skip 35)
        return [pscustomobject]@{
            SelectedItems = $selected; ChangedItems = $changed; CompletedItems = $changed; SkippedItems = $skipped
            FailedItems = @($selected | Select-Object -Skip (35 - $Failed) -First $Failed)
            Deployed = (35 - $Failed); Errors = $Failed; ErrorCount = $Failed
            Protected = 1; Unsafe = 5; UnresolvedTarget = 5; MissingPath = 0; MissingDevice = 100; Unsupported = 0; LinuxStyle = 50; UnknownArch = 140; KeptPrevious = 0
            SourceFolderItems = @(); UnverifiedItems = @(); NativeCrtNeedsRestoreItems = @()
            NativeShaderWarnings = @([pscustomobject]@{ Game = 'EXVS2XB'; Warning = 'Native settings were preserved; display effects may stack.' })
            ProtectedDetails = @('Quake: protected existing ReShade files'); UnsafeDetails = @('Game010: could not tell which ReShade file this game needs.')
            DetailNotes = @('Game036: could not tell whether this game is 32-bit or 64-bit; the game is not damaged and was left unchanged')
        }
    }
    function Get-Fix461Text { param($Result) return ((@(Format-TpmReShadeBulkSummaryRows -Result $Result)) -join "`n") }
}

Describe 'ReShade bulk result summary (issue 461)' {
    It 'says all eligible games were set up, accounts for every selected game, and shows no failure or retry warning' {
        $result = New-Fix461Result
        $rows = @(Format-TpmReShadeBulkSummaryRows -Result $result)
        $text = $rows -join "`n"
        $text | Should -Match 'All 35 games that could be set up were set up\.'
        foreach ($line in @('Selected: 331 games', 'Could be set up: 35 games', 'Set up: 35 games', 'Failed: 0 games', 'Skipped before setup: 296 games')) { $text | Should -Match ([regex]::Escape($line)) }
        $text | Should -Not -Match '(?i)did not finish|data safety|partial|try again|malformed|unsafe'
        $rows.Count | Should -BeLessThan 25 -Because 'the summary replaces four lists of 331, 35, 35 and 296 names'
        $text | Should -Not -Match 'Game0\d\d' -Because 'no game name is printed in the summary'
    }

    It 'groups the skipped games by one plain reason each, with counts, and says unreadable type was left unchanged' {
        $text = Get-Fix461Text -Result (New-Fix461Result)
        foreach ($line in @(
            '- 1 game: protected. ReShade files that TeknoParrot Manager did not install are already there',
            '- 100 games: the game files are on a drive that is not connected.',
            '- 50 games: the game type does not use ReShade',
            '- 140 games: the 32-bit or 64-bit type could not be read, so nothing was changed.'
        )) { $text | Should -Match ([regex]::Escape($line)) }
        $text | Should -Match 'Native game settings were kept as they were in 1 game\.'
        # 1 + 100 + 50 + 140 + 5 = 296: every skipped game is in exactly one group
        $text | Should -Match ([regex]::Escape('- 5 games: could not be matched to a ReShade file'))
    }

    It 'shows the failure and safety wording only when a game really failed' {
        $text = Get-Fix461Text -Result (New-Fix461Result -Failed 2)
        $text | Should -Match '2 games of the 35 games that could be set up did not finish\.'
        $text | Should -Match 'Failed: 2 games'
        $text | Should -Match 'not counted as set up'
        $text | Should -Match 'Run ReShade setup again for those games'
        $text | Should -Not -Match 'All 35 games'
    }

    It 'puts every per-game list behind Details once, and never lists the same games as both completed and changed' {
        $blocks = @(Get-TpmReShadeBulkDetailBlocks -Result (New-Fix461Result))
        $headings = @($blocks | ForEach-Object { $_.Heading })
        $headings | Should -Contain 'Set up (35)'
        $headings | Should -Contain 'Skipped (296)'
        @($headings | Where-Object { $_ -like 'Completed*' -or $_ -like 'Changed*' -or $_ -like 'Selected*' }).Count | Should -Be 0
        $all = ($blocks | ForEach-Object { $_.Lines }) -join "`n"
        ([regex]::Matches($all, 'Game001')).Count | Should -Be 1 -Because 'a set-up game is listed once'
        $all | Should -Match 'Game036: could not tell whether this game is 32-bit or 64-bit'
        $all | Should -Not -Match '(?i)malformed|unsafe/malformed'
    }
}
