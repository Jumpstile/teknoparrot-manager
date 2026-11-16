#Requires -Module Pester

# A tester saw the same red PowerShell error on the screen again and again ("Join-Path : Cannot find drive...") and his log had no line
# for it. An error the script does not handle is now written to the log (one line per kind, with a count), so the log and the support
# package (which copies the log) show what the user saw. Errors the script handles or silences are not written.
# The capture functions run for real here on errors made in the test. What this CANNOT prove: that no handled error of a real run is
# ever counted (a handled error raised by a command with no -ErrorAction on its line looks the same as an unhandled one).

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $script:f408Source = [System.IO.File]::ReadAllText($scriptPath)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX408 bootstrap could not parse the production script.' }
    $wanted = @('Test-TpmErrorWasShown', 'Write-TpmUnhandledErrorsToLog', 'Redact-TpmSupportText')
    $functions = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $wanted -contains $args[0].Name }, $true))
    if ($functions.Count -ne $wanted.Count) { throw 'FIX408 could not find the functions under test.' }
    $functionFile = Join-Path $TestDrive 'fix408-functions.ps1'
    ($functions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    . $functionFile
    function Write-Log { param([string]$msg) }
    $script:f408Log = New-Object System.Collections.Generic.List[string]
    $script:f408Missing = @('Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z' | Where-Object { -not (Test-Path -LiteralPath ($_ + ':\')) }) | Select-Object -First 1
    if (-not $script:f408Missing) { throw 'FIX408 needs one unused drive letter.' }
}

Describe 'Errors the user saw end up in the log (FIX408)' {
    BeforeEach {
        $script:f408Log.Clear()
        $global:Error.Clear()
        $script:TpmErrorLogMark = $null
        Mock Write-Log { [void]$script:f408Log.Add([string]$msg) }
    }

    It 'an unhandled error repeated many times is ONE log line with a count, the command and the line' {
        & {
            # Errors are kept but not printed, so the test output stays clean; the line has no -ErrorAction text.
            $ErrorActionPreference = 'SilentlyContinue'
            1..5 | ForEach-Object { Join-Path ($script:f408Missing + ':\Games\x') 'b.exe' | Out-Null }
        }

        Write-TpmUnhandledErrorsToLog -Where 'back at the main menu'

        $script:f408Log.Count | Should -Be 1
        $script:f408Log[0] | Should -Match 'Error shown on screen \(back at the main menu\)'
        $script:f408Log[0] | Should -Match "Cannot find drive"
        $script:f408Log[0] | Should -Match 'command: Join-Path'
        $script:f408Log[0] | Should -Match 'line \d+\]'
        $script:f408Log[0] | Should -Match '\(x5\)$'
    }

    It 'errors the script handles or silences are not written' {
        & {
            $ErrorActionPreference = 'SilentlyContinue'
            Get-ChildItem -LiteralPath ($script:f408Missing + ':\nope') -ErrorAction SilentlyContinue | Out-Null
            try { Get-Item -LiteralPath (Join-Path $TestDrive 'nope.txt') -ErrorAction Stop } catch { }
            try { throw 'handled' } catch { }
            try { [System.IO.Path]::GetFileName('a|b') } catch { }
            Get-Item -LiteralPath (Join-Path $TestDrive 'nope.txt') 2>$null | Out-Null
            # ErrorAction handed over in a hashtable (as the web download helper does): the line itself shows no -ErrorAction.
            $splat = @{ ErrorAction = 'Stop' }
            try { Get-Item -LiteralPath (Join-Path $TestDrive 'nope.txt') @splat } catch { }
        }

        Write-TpmUnhandledErrorsToLog -Where 'back at the main menu'

        $script:f408Log.Count | Should -Be 0
    }

    It 'the same error is written once, not again at the next capture point' {
        & {
            # The failing command is on its own line: a line that also names ErrorActionPreference is treated as handled and skipped.
            $ErrorActionPreference = 'SilentlyContinue'
            Join-Path ($script:f408Missing + ':\x') 'y' | Out-Null
        }
        Write-TpmUnhandledErrorsToLog -Where 'first'
        Write-TpmUnhandledErrorsToLog -Where 'second'
        $script:f408Log.Count | Should -Be 1
    }

    It 'writes at most 50 lines per capture point and ends with how many were not shown' {
        & {
            $ErrorActionPreference = 'SilentlyContinue'
            # Different message text for each (a path inside the temp folder would be shortened to the same words by the redaction).
            1..60 | ForEach-Object { Write-Error ('problem number ' + $_) }
        }

        Write-TpmUnhandledErrorsToLog -Where 'end of this run'

        $script:f408Log.Count | Should -Be 50
        $script:f408Log[49] | Should -BeExactly 'Error shown on screen (end of this run): 11 more not shown.'
    }

    It 'secrets and user folder names in the error text are removed' {
        & {
            $ErrorActionPreference = 'SilentlyContinue'
            Write-Error 'upload failed with password=hunter2 for C:\Users\SomeOne\Documents\x.txt'
        }

        Write-TpmUnhandledErrorsToLog -Where 'back at the main menu'

        $script:f408Log.Count | Should -Be 1
        $script:f408Log[0] | Should -Not -Match 'hunter2|SomeOne'
        $script:f408Log[0] | Should -Match 'password=<redacted>'
    }
}

Describe 'The log with these lines is in the support package, and capture points exist (FIX408)' {
    It 'the support package copies the whole log (redacted), so the new lines are in it' {
        $script:f408Source | Should -Match "TeknoParrot-Manager\.log"
        $script:f408Source | Should -Match '\$redacted = Redact-TpmSupportText -Text \$content\.Text'
    }

    It 'errors are written before the support package is built, at the menu, at the end of a run, in the final handler and on exit' {
        $source = $script:f408Source
        $source | Should -Match "Write-TpmUnhandledErrorsToLog -Where 'back at the main menu'"
        $source | Should -Match "Write-TpmUnhandledErrorsToLog -Where 'end of this run'"
        $source | Should -Match "Write-TpmUnhandledErrorsToLog -Where 'unexpected stop'"
        $source | Should -Match "Write-TpmUnhandledErrorsToLog -Where 'exit'"
        $beforeBuild = $source.IndexOf("Write-TpmUnhandledErrorsToLog -Where 'before the support package'")
        $build = $source.IndexOf('$supportResult = Invoke-TpmProgressGroup -Title ''Support package''')
        $beforeBuild | Should -BeGreaterThan 0
        $build | Should -BeGreaterThan $beforeBuild
    }
}
