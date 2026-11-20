#Requires -Module Pester

# Issue 402 (regression only): a run ended with "Illegal characters in path" (Windows PowerShell 5.1) at the Action Required screen,
# because an executable name saved in a game profile (quote, pipe, angle bracket, control character) was cut with
# [System.IO.Path]::GetFileName. The fix is already on this branch (Get-TpmExecutableDisplayName, see Fix406.NotesBadPath).
# This test pins what the user sees with the exact kinds of text from the report, and that no new GetFileName call is applied to
# profile text on the screen or in the saved report. Mutation: put GetFileName back on the executable name -> the last test fails.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $script:f402Source = [System.IO.File]::ReadAllText($scriptPath)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX402 bootstrap could not parse the production script.' }
    $function = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Get-TpmExecutableDisplayName' }, $true))
    if ($function.Count -ne 1) { throw 'FIX402 could not find Get-TpmExecutableDisplayName.' }
    $functionFile = Join-Path $TestDrive 'fix402-function.ps1'
    $function[0].Extent.Text | Set-Content -LiteralPath $functionFile -Encoding utf8
    . $functionFile
    function Write-Log { param([string]$msg) }
}

Describe 'An executable name with characters Windows paths refuse does not end the run (issue 402)' {
    It 'returns text and does not throw for <Case>' -TestCases @(
        @{ Case = 'a quote'; Name = 'L:\Games\"Cool Game".exe' }
        @{ Case = 'a pipe'; Name = 'one.exe|two.exe' }
        @{ Case = 'angle brackets'; Name = 'Game <Final>.exe' }
        @{ Case = 'a control character'; Name = ("bad" + [char]7 + "name.exe") }
        @{ Case = 'a trailing slash'; Name = 'D:\Games\Cool\' }
    ) {
        Mock Write-Log { }
        { $script:r402 = Get-TpmExecutableDisplayName -Name $Name -Codes 'CODE1' } | Should -Not -Throw
        $script:r402 | Should -Not -BeNullOrEmpty
    }

    It 'shows nothing for an empty or missing name' {
        Get-TpmExecutableDisplayName -Name '' -Codes 'CODE1' | Should -BeExactly ''
        Get-TpmExecutableDisplayName -Name $null -Codes 'CODE1' | Should -BeExactly ''
    }

    It 'no GetFileName call is applied to the executable text on the screen or in the saved report' {
        $starts = @([regex]::Matches($script:f402Source, 'FIX THESE GAME PATHS IN TEKNOPARROTUI') | ForEach-Object { $_.Index })
        $starts.Count | Should -BeGreaterOrEqual 2
        foreach ($start in $starts) {
            $script:f402Source.Substring($start, 900) | Should -Not -Match 'GetFileName'
        }
    }
}
