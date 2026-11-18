#Requires -Module Pester

# FIX87: one helper per job. The name-list helper that two lanes both defined is now one function, and the count helpers
# (Format-TpmCount, Get-TpmZipCountText and the inline "if (-eq 1)" plural words) are now Format-TpmCountNoun.
# These tests drive the real product functions; no file, service, registry or network is touched.
# Each It names the product change that makes it fail.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $script:F87Ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX87 tests could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'fix87-functions.ps1'
    ($script:F87Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:F87Rows = New-Object 'System.Collections.Generic.List[string]'
}

Describe 'FIX87 Format-TpmNameList is one function with every caller signature' {
    It 'is defined exactly once' {
        # Mutation: define the helper a second time (as FIX81 and FIX83 did) -> the later definition silently replaces the first.
        $definitions = @($script:F87Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -ieq 'Format-TpmNameList' }, $true))
        $definitions.Count | Should -Be 1
    }

    It 'shows five names and counts the rest when the caller gives no limit' {
        # Mutation: change the default limit back to 3 (the FIX83 default) -> "A, B, C and 4 more".
        (Format-TpmNameList -Names @('A', 'B', 'C', 'D', 'E', 'F', 'G')) | Should -BeExactly 'A, B, C, D, E and 2 more'
        (Format-TpmNameList -Names @('A', 'B', 'C', 'D', 'E')) | Should -BeExactly 'A, B, C, D and E'
    }

    It 'takes -Limit (the FIX81 callers)' {
        # Mutation: remove the -Limit parameter -> "A parameter cannot be found that matches parameter name 'Limit'".
        (Format-TpmNameList -Limit 3 -Names @('A', 'B', 'C', 'D', 'E')) | Should -BeExactly 'A, B, C and 2 more'
        (Format-TpmNameList -Limit 3 -Names @('A', 'B', 'C')) | Should -BeExactly 'A, B and C'
    }

    It 'takes -Max as the same limit (the FIX83 callers)' {
        # Mutation: remove the Max alias, or let -Max change a different value than -Limit.
        (Format-TpmNameList -Names @('A', 'B', 'C', 'D', 'E', 'F') -Max 3) | Should -BeExactly 'A, B, C and 3 more'
        (Format-TpmNameList -Names @('A', 'B') -Max 3) | Should -BeExactly 'A and B'
        (Format-TpmNameList -Names @('Only') -Max 3) | Should -BeExactly 'Only'
    }

    It 'lists every name when the caller asks for a big limit' {
        # Mutation: cap the limit at a fixed number -> "and N more" appears for a Max of 1000.
        $names = @(1..12 | ForEach-Object { 'G{0}' -f $_ })
        (Format-TpmNameList -Names $names -Max 1000) | Should -BeExactly 'G1, G2, G3, G4, G5, G6, G7, G8, G9, G10, G11 and G12'
    }

    It 'returns WhenEmpty only for an empty list, and an empty text without it' {
        # Mutation: return WhenEmpty for a list that has names, or drop the WhenEmpty parameter.
        (Format-TpmNameList -Names @() -Max 1000 -WhenEmpty 'none') | Should -BeExactly 'none'
        (Format-TpmNameList -Names @('', '  ') -WhenEmpty 'none') | Should -BeExactly 'none'
        (Format-TpmNameList -Names @('A') -WhenEmpty 'none') | Should -BeExactly 'A'
        (Format-TpmNameList -Names @()) | Should -BeExactly ''
    }

    It 'never says "and 1 more": one name over the limit is shown by name' {
        # Mutation: go back to "A, B, C and 1 more" -> a game is hidden behind a count that saves no space.
        (Format-TpmNameList -Names @('A', 'B', 'C', 'D') -Limit 3) | Should -BeExactly 'A, B, C and D'
        (Format-TpmNameList -Names @('A', 'B', 'C', 'D', 'E') -Limit 3) | Should -BeExactly 'A, B, C and 2 more'
    }

    It 'ignores blank names when it counts' {
        # Mutation: count the blank names -> the list is longer than the limit and prints "A, , B and 2 more".
        (Format-TpmNameList -Names @('A', '', 'B', ' ', 'C') -Limit 3) | Should -BeExactly 'A, B and C'
    }
}

Describe 'FIX87 Format-TpmCountNoun is the one count formatter' {
    It 'is the only count helper left besides the ReShade game wrapper' {
        # Mutation: bring back Format-TpmCount or Get-TpmZipCountText -> a second helper for the same job.
        foreach ($removed in @('Format-TpmCount', 'Get-TpmZipCountText')) {
            @($script:F87Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -ieq $removed }, $true)).Count | Should -Be 0 -Because $removed
        }
        (Format-TpmGameCount -Count 1) | Should -BeExactly '1 game'
        (Format-TpmGameCount -Count 4) | Should -BeExactly '4 games'
    }

    It 'gives the words the replaced helpers and inline plurals gave' {
        # Mutation: always add "s" -> "1 files"; or drop the singular case -> "1 ZIP files", "1 problems", "1 unavailable-device skips".
        (Format-TpmCountNoun -Count 1 -Singular 'file') | Should -BeExactly '1 file'
        (Format-TpmCountNoun -Count 0 -Singular 'file') | Should -BeExactly '0 files'
        (Format-TpmCountNoun -Count 7 -Singular 'restore point') | Should -BeExactly '7 restore points'
        (Format-TpmCountNoun -Count 1 -Singular 'item') | Should -BeExactly '1 item'
        (Format-TpmCountNoun -Count 3 -Singular 'item') | Should -BeExactly '3 items'
        (Format-TpmCountNoun -Count 1 -Singular 'ZIP file') | Should -BeExactly '1 ZIP file'
        (Format-TpmCountNoun -Count 5 -Singular 'ZIP file') | Should -BeExactly '5 ZIP files'
        (Format-TpmCountNoun -Count 1 -Singular 'problem') | Should -BeExactly '1 problem'
        (Format-TpmCountNoun -Count 2 -Singular 'problem') | Should -BeExactly '2 problems'
        (Format-TpmCountNoun -Count 1 -Singular 'unavailable-device skip') | Should -BeExactly '1 unavailable-device skip'
        (Format-TpmCountNoun -Count 2 -Singular 'unavailable-device skip') | Should -BeExactly '2 unavailable-device skips'
    }

    It 'puts a modifier between the number and the noun' {
        # Mutation: put the modifier after the noun, or ignore it -> "5 games more" or "5 games".
        (Format-TpmCountNoun -Count 5 -Singular 'game' -Modifier 'more') | Should -BeExactly '5 more games'
        (Format-TpmCountNoun -Count 1 -Singular 'game' -Modifier 'more') | Should -BeExactly '1 more game'
        (Format-TpmCountNoun -Count 1 -Singular 'game') | Should -BeExactly '1 game'
    }
}

Describe 'FIX87 the screens that used inline plural words print the same text' {
    It 'writes the partial ReShade summary with the right singular and plural words' {
        # Mutation: always use the plural word, or swap the error and skip counts in the sentence.
        $one = [pscustomobject]@{ Deployed = 1; ErrorCount = 1; MissingDevice = 1 }
        $many = [pscustomobject]@{ Deployed = 2; ErrorCount = 3; MissingDevice = 0 }
        (Get-TpmReShadeResultSummaryText -Result $one) | Should -BeExactly 'ReShade applied partially: 1 game changed, 1 error, 1 unavailable-device skip.'
        (Get-TpmReShadeResultSummaryText -Result $many) | Should -BeExactly 'ReShade applied partially: 2 games changed, 3 errors, 0 unavailable-device skips.'
    }

    It 'writes the More line of the Undo list with the number before "more"' {
        # Mutation: write "More: M (more 5 games)" or always write "games".
        Mock Write-Log {}
        Mock Get-ConsoleContentWidth { 100 }
        Mock Get-TpmReShadeUndoRowText { 'row' }
        $script:F87Rows.Clear()
        Mock Write-Host { [void]$script:F87Rows.Add([string]$Object) }
        Write-TpmReShadeUndoList -Visible @('a', 'b', 'c', 'd') -Total 9 -PageCount 3
        Write-TpmReShadeUndoList -Visible @('a', 'b', 'c', 'd') -Total 5 -PageCount 2
        @($script:F87Rows) | Should -Contain '  More: M (5 more games)'
        @($script:F87Rows) | Should -Contain '  More: M (1 more game)'
    }
}
