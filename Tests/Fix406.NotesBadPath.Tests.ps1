#Requires -Module Pester

# A beta tester's run stopped at the very end of onboarding with "Illegal characters in path" (Windows PowerShell 5.1).
# Cause: the Action Required screen cut the executable name saved in a profile with [System.IO.Path]::GetFileName, which
# refuses text with quotes, pipes or angle brackets. One odd profile ended the whole run instead of returning to the menu.
# Now the name is cut by plain text work (Get-TpmExecutableDisplayName), odd text is shown as written and one log line names the game.
# The screen itself is top-level script code, so the helper is tested directly and the wiring is checked in the source.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $script:f406Source = [System.IO.File]::ReadAllText($scriptPath)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX406 bootstrap could not parse the production script.' }
    $function = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Get-TpmExecutableDisplayName' }, $true))
    if ($function.Count -ne 1) { throw 'FIX406 could not find Get-TpmExecutableDisplayName.' }
    $functionFile = Join-Path $TestDrive 'fix406-function.ps1'
    $function[0].Extent.Text | Set-Content -LiteralPath $functionFile -Encoding utf8
    . $functionFile
    function Write-Log { param([string]$msg) }
    $script:f406Log = New-Object System.Collections.Generic.List[string]
}

Describe 'The Action Required screen survives an odd executable name (FIX406)' {
    BeforeEach {
        $script:f406Log.Clear()
        Mock Write-Log { [void]$script:f406Log.Add([string]$msg) }
    }

    It 'shows a normal name as just the file name and writes no log line' {
        Get-TpmExecutableDisplayName -Name 'C:\Games\Cool Game\game.exe' -Codes 'CG1' | Should -BeExactly 'game.exe'
        Get-TpmExecutableDisplayName -Name 'game.exe' -Codes 'CG1' | Should -BeExactly 'game.exe'
        $script:f406Log.Count | Should -Be 0
    }

    It 'does not throw for <Name>, still shows it, and the log names the game' -TestCases @(
        @{ Name = '"game one.exe"'; Shown = '"game one.exe"' }
        @{ Name = 'one.exe|two.exe'; Shown = 'one.exe|two.exe' }
        @{ Name = 'a<b>.exe'; Shown = 'a<b>.exe' }
        @{ Name = 'L:\Games\"odd|name.exe'; Shown = '"odd|name.exe' }
    ) {
        { $script:shown406 = Get-TpmExecutableDisplayName -Name $Name -Codes 'BAD1 and BAD2' } | Should -Not -Throw
        $script:shown406 | Should -BeExactly $Shown
        @($script:f406Log | Where-Object { $_ -like '*BAD1 and BAD2*' -and $_ -like '*shown as written*' }).Count | Should -Be 1
    }

    It 'one odd entry does not hide the others' {
        $names = [ordered]@{ 'GOOD1' = 'D:\g\one.exe'; 'ODD1' = 'x|y.exe'; 'GOOD2' = 'D:\g\two.exe' }
        $shown = @(foreach ($code in $names.Keys) { Get-TpmExecutableDisplayName -Name $names[$code] -Codes $code })
        ($shown -join ',') | Should -BeExactly 'one.exe,x|y.exe,two.exe'
        @($script:f406Log | Where-Object { $_ -like '*ODD1*' }).Count | Should -Be 1
        @($script:f406Log | Where-Object { $_ -like '*GOOD*' }).Count | Should -Be 0
    }

    # The same repair results are shown on screen AND written to the saved Action Required report. Both used the call that crashed,
    # so fixing only the screen would have crashed the run a moment later, on the way back to the menu.
    It 'the screen and the saved report both use this helper, not the path check that crashed' {
        $starts = @([regex]::Matches($script:f406Source, 'FIX THESE GAME PATHS IN TEKNOPARROTUI') | ForEach-Object { $_.Index })
        $starts.Count | Should -BeGreaterOrEqual 2
        foreach ($start in $starts) {
            $block = $script:f406Source.Substring($start, 900)
            $block | Should -Match 'Get-TpmExecutableDisplayName -Name \$exePath'
            $block | Should -Not -Match 'GetFileName'
        }
        [regex]::Matches($script:f406Source, 'GetFileName\(\$exePath\)').Count | Should -Be 0
    }
}

Describe 'An unexpected error ends in plain words (FIX406)' {
    It 'says what happened, what to do, and keeps the technical text under Details' {
        $start = $script:f406Source.IndexOf('$errFull = "FATAL ERROR -- script aborted (unhandled)')
        $start | Should -BeGreaterThan 0
        $handler = $script:f406Source.Substring($start, 2200)
        $handler | Should -Match 'stopped unexpectedly'
        $handler | Should -Match 'What to do: press Enter to close this window, then start'
        $handler | Should -Match 'You will be back at the menu'
        $handler.IndexOf('Details:') | Should -BeGreaterThan $handler.IndexOf('What to do:')
        $handler.IndexOf('$errMsg') | Should -BeGreaterThan $handler.IndexOf('Details:')
    }

    It 'the GPU fix says a missing drive is not connected and how to fix it' {
        # RC9 names the drive ("Drive E: is not connected.") and ends with one plain next step.
        $script:f406Source | Should -Match 'Drive \{0\} is not connected\.'
        $script:f406Source | Should -Match 'Connect the drive, or choose 14 \(Library health check\) in the main menu to repair these games\.'
        $script:f406Source | Should -Match 'Then run GPU Compatibility Fix again from the main menu\.'
    }
}
