#Requires -Module Pester
# Issue #352: a game that could not be registered must be counted and named, never hidden behind a clean-looking recap,
# and an AutoSync that unpacked nothing because ZIP files failed must say so instead of "nothing new was extracted".
# Function definitions and one named script-body statement are taken from the parsed script (AST); nothing is run for real.
BeforeAll {
    $script:R352ScriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null; $parseErrors = $null
    $script:R352Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:R352ScriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'The production script could not be parsed.' }
    $functionFile = Join-Path $TestDrive 'r352-functions.ps1'
    (@($script:R352Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" |
        Set-Content -LiteralPath $functionFile -Encoding UTF8
    . $functionFile
    $script:R352Titles = @{ GameOne = 'Game One'; GameTwo = 'Game Two'; GameThree = 'Game Three' }
    function Get-TpmGameTitle { param([string]$Code, [string]$TpRoot = '') $title = [string]$script:R352Titles[$Code]; return $title }
    function Get-TpmSessionRunId { return 'r352-run' }
    # The registration if/elseif block of the script body (the one that decides what to say when nothing was extracted).
    $found = @($script:R352Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -ceq '$registrationFolders.Count -gt 0' }, $true))
    if ($found.Count -ne 1) { throw 'The registration message block was not found.' }
    $script:R352SkipBlock = $found[0].Extent.Text
    function Invoke-R352SkipBlock {
        param([hashtable]$Variables)
        foreach ($key in $Variables.Keys) { Set-Variable -Name $key -Value $Variables[$key] }
        foreach ($once in 1) { . ([scriptblock]::Create($script:R352SkipBlock)) }
    }
}

Describe 'Issue 352: a registration failure is counted, named and given a next step' {
    It 'the recap is Attention, counts the failed games and says what to do' {
        # Mutation: drop RegistrationFailed from Get-TpmRegistrationRecap -> a run where profiles failed to save looks green.
        $recap = Get-TpmRegistrationRecap -AutoSyncRan $true -ZipsExtracted 3 -NewlyRegistered 1 -RegistrationFailed @('GameOne', 'GameTwo')
        $recap.Status | Should -Be 'Attention'
        @($recap.Needs) | Should -Contain '2 games could not be registered: Game One and Game Two. Close TeknoParrotUI, then run Register Games again. The ACTION REQUIRED list and the log have the reason.'
        $did = @(@($recap.DetailBlocks | Where-Object { $_.Heading -eq 'What TeknoParrot Manager did' })[0].Lines)
        $did | Should -Contain 'Failed: 2 games could not be registered.'
    }

    It 'says "1 game" for a single failure and adds nothing when none failed' {
        $one = Get-TpmRegistrationRecap -NewlyRegistered 2 -RegistrationFailed @('GameThree')
        (@($one.Needs) -join ' ') | Should -Match '^1 game could not be registered: Game Three\.'
        $none = Get-TpmRegistrationRecap -NewlyRegistered 2
        $none.Status | Should -Be 'Ok'
        (@(@($none.DetailBlocks | Where-Object { $_.Heading -eq 'What TeknoParrot Manager did' })[0].Lines) -join ' ') | Should -Not -Match 'Failed:'
    }

    It 'the saved ACTION REQUIRED list names every game that failed or could not be verified' {
        # Mutation: leave FailedItems/UnknownItems out of New-TpmActionRequiredReportText -> support sees nothing about the failed games.
        $result = [pscustomobject]@{ Unmatched = @(); FailedItems = @('GameTwo'); UnknownItems = @('GameOne') }
        $text = New-TpmActionRequiredReportText -Result $result
        $text | Should -Match 'GAMES THAT COULD NOT BE REGISTERED'
        $text | Should -Match 'run Register Games again'
        $text | Should -Match '(?m)^  GameOne\r?$'
        $text | Should -Match '(?m)^  GameTwo\r?$'
        (New-TpmActionRequiredReportText -Result ([pscustomobject]@{ Unmatched = @() })) | Should -Not -Match 'COULD NOT BE REGISTERED'
    }
}

Describe 'Issue 352: nothing registered because ZIP files failed is said plainly' {
    BeforeEach {
        $script:R352Lines = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { [void]$script:R352Lines.Add([string]$Object) }
        Mock Write-Log {}
    }

    It 'says the ZIP files could not be unpacked and what to do, not "nothing new was extracted"' {
        # Mutation: restore the single "Nothing new was extracted" message -> a failed unpack reads like a quiet no-op.
        Invoke-R352SkipBlock -Variables @{
            registrationFolders = @(); skipAutoSyncRegistration = $true; dryRunActive = $false
            sync = @{ Synced = 0; Failed = 1; UnsafePathSkipped = 0 }; syncSupp = @{ Synced = 0; Failed = 0; UnsafePathSkipped = 1 }
        }
        $text = $script:R352Lines -join "`n"
        $text | Should -Match 'No game was unpacked, so nothing was registered\. 2 ZIP files could not be unpacked\.'
        $text | Should -Match 'Next: open View Log to see why, then run AutoSync again\.'
        $text | Should -Not -Match 'Nothing new was extracted'
    }

    It 'keeps the plain "nothing new" message when no ZIP file failed' {
        Invoke-R352SkipBlock -Variables @{
            registrationFolders = @(); skipAutoSyncRegistration = $true; dryRunActive = $false
            sync = @{ Synced = 0; Failed = 0; UnsafePathSkipped = 0 }; syncSupp = $null
        }
        $text = $script:R352Lines -join "`n"
        $text | Should -Match 'Nothing new was extracted, so registration was skipped\.'
        $text | Should -Not -Match 'could not be unpacked'
    }
}
